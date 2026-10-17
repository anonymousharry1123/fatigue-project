import 'dart:convert';

import 'ai1_dataset_builder.dart';
import 'ai1_protocol.dart';
import 'ai1_records.dart';
import 'ai_model_artifact.dart';

/// A software-test store. Its receipts simulate persistence timing; they are
/// never evidence of a native durable write, actual participant data or consent.
abstract interface class AiShadowSimulatedStore {
  Future<Map<String, dynamic>?> read(String scope);
  Future<DateTime> write(String scope, Map<String, dynamic> snapshot);
  Future<void> clear(String scope);
}

/// The whole evaluation calendar and one synthetic model are frozen in advance.
class AiShadowBlock {
  AiShadowBlock({
    required this.blockId,
    required this.artifact,
    required this.protocol,
    required List<Ai1Opportunity> opportunities,
  }) : opportunities = List.unmodifiable(
         [...opportunities]..sort((a, b) => a.cutoff.compareTo(b.cutoff)),
       ) {
    if (blockId.trim().isEmpty || this.opportunities.isEmpty) {
      throw ArgumentError('A named, nonempty synthetic calendar is required.');
    }
    if (artifact.protocol.id != protocol.id) {
      throw ArgumentError('The artifact must use the frozen block protocol.');
    }
    final ids = <String>{};
    for (final opportunity in this.opportunities) {
      if (!ids.add(opportunity.id) ||
          opportunity.protocolId != protocol.id ||
          opportunity.participantKey != artifact.participantKey ||
          opportunity.timezone != artifact.timezone) {
        throw ArgumentError('The frozen calendar must match one model scope.');
      }
    }
    if (artifact.fittedAt.isAfter(this.opportunities.first.cutoff) ||
        artifact.dataCutoff.isAfter(this.opportunities.first.cutoff)) {
      throw ArgumentError('Freeze the model before the evaluation block.');
    }
  }

  final String blockId;
  final AiModelArtifact artifact;
  final Ai1Protocol protocol;
  final List<Ai1Opportunity> opportunities;
  String get fingerprint => ai1CanonicalJson({
    'blockId': blockId,
    'artifact': artifact.fingerprint,
    'protocolId': protocol.id,
    'opportunities': [
      for (final opportunity in opportunities)
        {
          'id': opportunity.id,
          'timezone': opportunity.timezone,
          'cutoff': opportunity.cutoff.toIso8601String(),
          'outcomeEnd': opportunity.outcomeEnd.toIso8601String(),
        },
    ],
  });
}

/// An isolated, synthetic-only rehearsal. No app, native store, background task,
/// real-data loader, visible prediction, Coach, registry or training is connected.
class AiShadowHarness {
  factory AiShadowHarness({
    required AiShadowSimulatedStore store,
    required DateTime Function() clock,
  }) => AiShadowHarness._(store, clock);

  AiShadowHarness._(this._store, this._clock);

  final AiShadowSimulatedStore _store;
  final DateTime Function() _clock;
  Future<void>? _queue;
  int _generation = 0;
  String? _scope;
  AiShadowBlock? _block;
  Map<String, dynamic>? _committed;
  final Map<String, String> _failures = {};
  final Set<String> _pendingErasures = {};
  final Set<String> _eraseObligations = {};
  bool _interrupted = false;
  bool _hasWriteAttempted = false;
  DateTime? _lastClock;

  bool get active => _scope != null && _committed != null && !_interrupted;
  String? get scope => _scope;

  /// Starting another account first restores the prior committed snapshot after
  /// any canceled write. Previously stored blocks cannot silently be replaced.
  Future<void> start({
    required String scope,
    required AiShadowBlock block,
  }) async {
    if (scope.trim().isEmpty || scope != block.artifact.ownerScope) {
      throw ArgumentError('The scope must match the synthetic model owner.');
    }
    final oldScope = _scope;
    final oldState = _committed == null ? null : _copy(_committed!);
    final restoreOld = _hasWriteAttempted;
    final clearOld =
        _pendingErasures.isNotEmpty || _failures.containsValue('erase_failed');
    if (oldScope != null && clearOld) _eraseObligations.add(oldScope);
    final generation = ++_generation;
    _scope = scope;
    _block = block;
    _committed = null;
    _interrupted = false;
    _hasWriteAttempted = false;
    _failures.clear();
    _pendingErasures.clear();
    _lastClock = null;
    await _serialized(() async {
      await _retryErasures();
      if (oldScope != null && restoreOld && !clearOld) {
        await _restore(oldScope, oldState);
      }
      if (!_current(scope, generation)) return;
      final saved = await _store.read(scope);
      if (!_current(scope, generation)) return;
      final now = _now();
      if (block.artifact.fittedAt.isAfter(now)) {
        throw StateError('A future fit cannot be frozen in a present plan.');
      }
      if (saved != null) {
        _validateSaved(saved, scope, block);
        final savedAt = DateTime.parse(saved['lastReceiptAt'] as String);
        if (now.isBefore(savedAt)) {
          throw StateError('Simulated clock moved backwards.');
        }
        _committed = _copy(saved);
        return;
      }
      if (!now.isBefore(block.opportunities.first.dayStart)) {
        throw StateError('Prespecify the calendar before its first local day.');
      }
      final pending = <String, dynamic>{
        'schemaVersion': 'ai6-synthetic-shadow-state-v1',
        'synthetic': true,
        'simulatedDurability': true,
        'scope': scope,
        'blockFingerprint': block.fingerprint,
        'planCreatedAt': now.toIso8601String(),
        'planReceiptAt': null,
        'lastReceiptAt': null,
        'pending': true,
        'events': <String, dynamic>{},
        'outcomes': <String, dynamic>{},
        'tombstones': <String, dynamic>{},
      };
      try {
        _hasWriteAttempted = true;
        final receipt = (await _store.write(scope, _copy(pending))).toUtc();
        if (!_current(scope, generation)) return;
        if (receipt.isBefore(now) ||
            !receipt.isBefore(block.opportunities.first.dayStart)) {
          throw StateError('The simulated plan receipt was not prospective.');
        }
        final complete = _copy(pending)
          ..['planReceiptAt'] = receipt.toIso8601String()
          ..['lastReceiptAt'] = receipt.toIso8601String()
          ..['pending'] = false;
        final completion = (await _store.write(scope, _copy(complete))).toUtc();
        if (!_current(scope, generation)) return;
        if (completion.isBefore(receipt)) {
          throw StateError('Simulated clock moved backwards.');
        }
        _committed = complete;
      } on Object {
        if (_current(scope, generation)) _interrupted = true;
        rethrow;
      }
    });
  }

  /// Only the injected clock and store receipt determine execution time. Caller
  /// supplied issuedAt/durableAt fields are deliberately not trusted or reused.
  Future<Map<String, dynamic>?> recordMorning(Ai1FixtureDay evidence) async {
    _validateEvidence(evidence);
    if (_requestsErasure(evidence)) {
      _pendingErasures.add(evidence.opportunity.id);
    }
    final scope = _scope!;
    final generation = _generation;
    Map<String, dynamic>? result;
    await _serialized(() async {
      if (!_current(scope, generation)) return;
      _requireActive();
      final state = _committed!;
      final id = evidence.opportunity.id;
      if ((state['tombstones'] as Map).containsKey(id)) {
        _pendingErasures.remove(id);
        return;
      }
      if (evidence.withdrawn ||
          evidence.sleepRevisions.any((row) => row.deleted) ||
          evidence.responseRevisions.any((row) => row.deleted)) {
        await _eraseDay(
          scope,
          generation,
          id,
          evidence.withdrawn ? 'withdrawn' : 'deleted',
          _now(),
        );
        return;
      }
      final previous = (state['events'] as Map)[id];
      if (previous != null) {
        result = _copy(Map<String, dynamic>.from(previous as Map));
        return;
      }
      final now = _now();
      final opportunity = evidence.opportunity;
      if (now.isBefore(opportunity.cutoff)) return;
      var execution = now.isBefore(opportunity.issuanceDeadline)
          ? 'executed'
          : 'missed_window';
      if (evidence.withdrawn) execution = 'withdrawn';
      if (evidence.timezoneChanges.any((time) => !time.isAfter(now))) {
        execution = 'timezone_changed_before_execution';
      }
      final selected = Ai1DatasetBuilder.selectSleep(
        _block!.protocol,
        evidence,
      );
      final feature = selected.record;
      final inference = execution == 'executed'
          ? _block!.artifact.predict(
              context: AiModelInferenceContext(
                ownerScope: scope,
                participantKey: opportunity.participantKey,
                protocol: _block!.protocol,
                timezone: opportunity.timezone,
                at: now,
                featureCutoff: opportunity.cutoff,
                dataGeneration: _block!.artifact.dataGeneration,
              ),
              sleepHours: feature?.durationHours,
              sleepAvailableAt: feature?.availableAt,
            )
          : null;
      final event = <String, dynamic>{
        'eventId': ai1CanonicalJson([_block!.blockId, scope, id]),
        'opportunityId': id,
        'artifactId': _block!.artifact.artifactId,
        'artifactFingerprint': _block!.artifact.fingerprint,
        'executedAt': now.toIso8601String(),
        'receiptAt': null,
        'executionStatus': execution,
        'sleepStatus': selected.status,
        'modelStatus':
            inference?.abstentionReason ??
            (inference?.predicted == true ? 'predicted' : 'no_execution'),
        'rawPrediction': inference?.rawPrediction,
        'prediction': inference?.prediction,
        'feature': feature == null || execution != 'executed'
            ? null
            : _featureSnapshot(feature),
      };
      final next = _copy(state);
      (next['events'] as Map)[id] = event;
      await _save(scope, generation, next, now, id, (receipt) {
        event['receiptAt'] = receipt.toIso8601String();
        if (execution == 'executed' &&
            !receipt.isBefore(opportunity.issuanceDeadline)) {
          event['executionStatus'] = 'missed_window';
          event['modelStatus'] = 'no_execution';
          event['rawPrediction'] = null;
          event['prediction'] = null;
          event['feature'] = null;
        }
      });
      if (_current(scope, generation) && !_interrupted) result = _copy(event);
    });
    return result;
  }

  /// A closed-window assessment saved at the actual simulated execution time.
  /// Later revisions may replace this assessment, never the frozen prediction.
  Future<void> linkOutcome(Ai1FixtureDay evidence) async {
    _validateEvidence(evidence);
    if (_requestsErasure(evidence)) {
      _pendingErasures.add(evidence.opportunity.id);
    }
    final scope = _scope!;
    final generation = _generation;
    await _serialized(() async {
      if (!_current(scope, generation)) return;
      _requireActive();
      final now = _now();
      final opportunity = evidence.opportunity;
      if (now.isBefore(opportunity.outcomeEnd)) {
        throw StateError('The outcome window has not closed.');
      }
      final id = opportunity.id;
      if ((_committed!['tombstones'] as Map).containsKey(id)) {
        _pendingErasures.remove(id);
        return;
      }
      if (evidence.withdrawn ||
          evidence.sleepRevisions.any((row) => row.deleted) ||
          evidence.responseRevisions.any((row) => row.deleted)) {
        await _eraseDay(
          scope,
          generation,
          id,
          evidence.withdrawn ? 'withdrawn' : 'deleted',
          now,
        );
        return;
      }
      final event = (_committed!['events'] as Map)[id] as Map?;
      final executed = event?['executionStatus'] == 'executed';
      final day = Ai1FixtureDay(
        opportunity: opportunity,
        synthetic: true,
        sleepHistoryComplete: evidence.sleepHistoryComplete,
        responseHistoryComplete: evidence.responseHistoryComplete,
        sleepRevisions: evidence.sleepRevisions,
        responseRevisions: evidence.responseRevisions,
        issuedAt: executed
            ? DateTime.parse(event!['executedAt'] as String)
            : null,
        durableAt: executed
            ? DateTime.parse(event!['receiptAt'] as String)
            : null,
        timezoneChanges: evidence.timezoneChanges,
      );
      final row = Ai1DatasetBuilder.buildSynthetic(
        protocol: _block!.protocol,
        days: [day],
        asOf: now,
        datasetVersion: 'shadow-link-${_block!.blockId}',
      ).rows.single;
      var status = row.outcomeStatus;
      int? energy = row.energy;
      final previousOutcome = (_committed!['outcomes'] as Map)[id] as Map?;
      final knownResponses = <String, String>{
        if (previousOutcome != null)
          ...Map<String, String>.from(
            previousOutcome['knownResponseFingerprints'] as Map,
          ),
      };
      final suppliedResponses = <String, String>{};
      String? responseIntegrityStatus =
          previousOutcome?['responseIntegrityStatus'] as String?;
      for (final response in evidence.responseRevisions.where(
        (response) =>
            response.participantKey == opportunity.participantKey &&
            !response.availableAt.isAfter(now),
      )) {
        final key = ai1CanonicalJson([
          response.participantKey,
          response.sourceId,
          response.revision,
        ]);
        final old = knownResponses[key] ?? suppliedResponses[key];
        if (old != null && old != response.fingerprint) {
          responseIntegrityStatus = 'conflicting_response_revision';
        }
        suppliedResponses[key] = response.fingerprint;
        // Once observed, a source revision is immutable and cannot disappear.
        knownResponses.putIfAbsent(key, () => response.fingerprint);
      }
      if (responseIntegrityStatus == null &&
          knownResponses.keys.any(
            (key) => !suppliedResponses.containsKey(key),
          )) {
        responseIntegrityStatus = 'response_history_regressed';
      }
      if (previousOutcome?['status'] == 'selected_response_revised' ||
          status == 'selected_response_revised') {
        responseIntegrityStatus ??= 'selected_response_revised';
      }
      var pairingStatus = 'compatible';
      if (_block!.artifact.candidateId == 'M1' &&
          event?['prediction'] != null) {
        final selected = Ai1DatasetBuilder.selectSleep(
          _block!.protocol,
          evidence,
        ).record;
        if (selected == null ||
            ai1CanonicalJson(event?['feature']) !=
                ai1CanonicalJson(_featureSnapshot(selected))) {
          pairingStatus = 'feature_lineage_changed';
        }
      }
      if (row.outcome != null &&
          evidence.timezoneChanges.any(
            (time) => !time.isAfter(row.outcome!.observedAt),
          )) {
        status = 'timezone_changed';
        energy = null;
      }
      if (responseIntegrityStatus != null) {
        status = responseIntegrityStatus;
        energy = null;
      }
      final lateIds = evidence.responseRevisions
          .where(
            (response) =>
                response.revision == 1 &&
                response.participantKey == opportunity.participantKey &&
                response.localDate == opportunity.localDate &&
                response.period == 'Evening' &&
                response.timezone == opportunity.timezone &&
                response.lineageComplete &&
                response.sourceId.trim().isNotEmpty &&
                !response.initialSavedAt.isBefore(response.observedAt) &&
                !response.availableAt.isBefore(response.initialSavedAt) &&
                !response.availableAt.isAfter(now) &&
                (!response.observedAt.isBefore(opportunity.outcomeEnd) ||
                    !response.initialSavedAt.isBefore(opportunity.outcomeEnd)),
          )
          .map((row) => row.sourceId)
          .toSet();
      final outcome = <String, dynamic>{
        'assessedAt': now.toIso8601String(),
        'receiptAt': null,
        'status': status,
        'energy': energy,
        'pairingStatus': pairingStatus,
        'lateOriginalResponses': lateIds.length,
        'knownResponseFingerprints': knownResponses,
        'responseIntegrityStatus': responseIntegrityStatus,
        'previousAssessments': [
          if ((_committed!['outcomes'] as Map)[id] case final Map previous) ...[
            ...previous['previousAssessments'] as List,
            Map<String, dynamic>.from(previous)..remove('previousAssessments'),
          ],
        ],
      };
      final next = _copy(_committed!);
      (next['outcomes'] as Map)[id] = outcome;
      await _save(
        scope,
        generation,
        next,
        now,
        id,
        (receipt) => outcome['receiptAt'] = receipt.toIso8601String(),
      );
    });
  }

  Future<void> deleteOpportunity(String opportunityId) async {
    _requireActive();
    if (!_block!.opportunities.any((day) => day.id == opportunityId)) {
      throw ArgumentError('The opportunity is outside this frozen calendar.');
    }
    _pendingErasures.add(opportunityId);
    final scope = _scope!;
    final generation = _generation;
    await _serialized(() async {
      if (!_current(scope, generation)) return;
      await _eraseDay(scope, generation, opportunityId, 'deleted', _now());
    });
  }

  Future<void> _eraseDay(
    String scope,
    int generation,
    String id,
    String reason,
    DateTime now,
  ) async {
    final next = _copy(_committed!);
    (next['events'] as Map).remove(id);
    (next['outcomes'] as Map).remove(id);
    final marker = <String, dynamic>{
      'reason': reason,
      'observedAt': now.toIso8601String(),
      'receiptAt': null,
    };
    (next['tombstones'] as Map)[id] = marker;
    await _save(
      scope,
      generation,
      next,
      now,
      id,
      (receipt) => marker['receiptAt'] = receipt.toIso8601String(),
      failureStatus: 'erase_failed',
    );
    if (_current(scope, generation) && !_interrupted) {
      _pendingErasures.remove(id);
    }
  }

  Future<void> _save(
    String scope,
    int generation,
    Map<String, dynamic> next,
    DateTime now,
    String id,
    void Function(DateTime) attachReceipt, {
    String failureStatus = 'save_failed',
  }) async {
    try {
      next['pending'] = true;
      _hasWriteAttempted = true;
      final receipt = (await _store.write(scope, _copy(next))).toUtc();
      if (!_current(scope, generation)) return;
      if (receipt.isBefore(now) ||
          receipt.isBefore(
            DateTime.parse(_committed!['lastReceiptAt'] as String),
          )) {
        throw StateError('Simulated receipt cannot backdate an operation.');
      }
      attachReceipt(receipt);
      next['pending'] = false;
      next['lastReceiptAt'] = receipt.toIso8601String();
      final completion = (await _store.write(scope, _copy(next))).toUtc();
      if (!_current(scope, generation)) return;
      if (completion.isBefore(receipt)) {
        throw StateError('Simulated clock moved backwards.');
      }
      _committed = _copy(next);
    } on Object {
      if (_current(scope, generation)) {
        _interrupted = true;
        _failures[id] = failureStatus;
      }
      rethrow;
    }
  }

  /// Hides all state immediately; the queued rollback cancels in-flight writes
  /// while preserving only the last previously committed scoped history.
  Future<void> signOut() => _leave(clear: false);
  Future<void> optOut() => _leave(clear: true);
  Future<void> reset() => _leave(clear: true);

  Future<void> _leave({required bool clear}) async {
    final scope = _scope;
    final committed = _committed == null ? null : _copy(_committed!);
    final restoreNeeded = _hasWriteAttempted;
    final mustClear =
        clear ||
        _pendingErasures.isNotEmpty ||
        _failures.containsValue('erase_failed');
    if (scope != null && mustClear) _eraseObligations.add(scope);
    ++_generation;
    _scope = null;
    _block = null;
    _committed = null;
    _failures.clear();
    _pendingErasures.clear();
    _interrupted = false;
    _hasWriteAttempted = false;
    _lastClock = null;
    if (scope == null && _eraseObligations.isEmpty) return;
    await _serialized(() async {
      await _retryErasures();
      if (scope != null && !mustClear && restoreNeeded) {
        await _restore(scope, committed);
      }
    });
  }

  Map<String, dynamic> report({DateTime? asOf}) {
    if (_scope == null || _block == null || _committed == null) {
      throw StateError('Sign in to a started synthetic block first.');
    }
    final now = _now();
    final freeze = (asOf ?? now).toUtc();
    if (freeze.isAfter(now) ||
        freeze.isBefore(
          DateTime.parse(_committed!['planReceiptAt'] as String),
        )) {
      throw ArgumentError(
        'An analysis freeze cannot precede the plan or be in the future.',
      );
    }
    final rows = <Map<String, dynamic>>[];
    for (final opportunity in _block!.opportunities.where(
      (day) => !day.outcomeEnd.isAfter(freeze),
    )) {
      final id = opportunity.id;
      final failed = _failures.containsKey(id);
      final tombstone = (_committed!['tombstones'] as Map)[id] as Map?;
      final event = (_committed!['events'] as Map)[id] as Map?;
      final assessment = (_committed!['outcomes'] as Map)[id] as Map?;
      final knownEvent =
          event != null &&
              !DateTime.parse(event['receiptAt'] as String).isAfter(freeze)
          ? event
          : null;
      Map? knownOutcome;
      if (assessment != null) {
        for (final revision in [
          ...assessment['previousAssessments'] as List,
          assessment,
        ].cast<Map>()) {
          if (!DateTime.parse(
            revision['receiptAt'] as String,
          ).isAfter(freeze)) {
            knownOutcome = revision;
          }
        }
      }
      final energy = tombstone == null && !failed
          ? (knownOutcome?['energy'] as num?)
          : null;
      final prediction = tombstone == null && !failed
          ? (knownEvent?['prediction'] as num?)
          : null;
      final error =
          energy == null ||
              prediction == null ||
              knownOutcome?['pairingStatus'] != 'compatible'
          ? null
          : prediction - energy;
      rows.add({
        'opportunityId': id,
        'localDate': opportunity.localDate,
        'cutoff': opportunity.cutoff.toIso8601String(),
        'executionStatus':
            tombstone?['reason'] ??
            _failures[id] ??
            knownEvent?['executionStatus'] ??
            'not_executed',
        'outcomeStatus':
            tombstone?['reason'] ??
            _failures[id] ??
            knownOutcome?['status'] ??
            'not_linked',
        'pairingStatus':
            tombstone?['reason'] ??
            knownOutcome?['pairingStatus'] ??
            'not_linked',
        'event': tombstone == null && !failed && knownEvent != null
            ? _copy(Map<String, dynamic>.from(knownEvent))
            : null,
        'outcome': tombstone == null && !failed && knownOutcome != null
            ? _copy(Map<String, dynamic>.from(knownOutcome))
            : null,
        'prediction': prediction,
        'energy': energy,
        'scored': error != null,
        'signedError': error,
        'absoluteError': error?.abs(),
      });
    }
    final active = rows
        .where((row) => row['executionStatus'] != 'withdrawn')
        .toList();
    final predictions = active.where((row) => row['prediction'] != null).length;
    final completed = active.where((row) => row['energy'] != null).length;
    final errors = active
        .map((row) => row['absoluteError'])
        .whereType<num>()
        .toList();
    return _copy({
      'schemaVersion': 'ai6-synthetic-shadow-rehearsal-v1',
      'synthetic': true,
      'simulatedDurability': true,
      'realProspectiveEvidence': false,
      'appModelActivationAllowed': false,
      'coachUseAllowed': false,
      'realDataTrainingAllowed': false,
      'scope': _scope,
      'blockId': _block!.blockId,
      'artifact': _block!.artifact.toJson(),
      'asOf': freeze.toIso8601String(),
      'interrupted': _interrupted,
      'coverage': {
        'plannedOpportunities': _block!.opportunities.length,
        'closedOpportunities': rows.length,
        'withdrawnOpportunities': rows.length - active.length,
        'activeClosedOpportunities': active.length,
        'executed': active
            .where((row) => row['executionStatus'] == 'executed')
            .length,
        'predicted': predictions,
        'completedOutcomes': completed,
        'missingOrUnusableOutcomes': active.length - completed,
        'unlinkedOutcomes': active
            .where((row) => row['outcomeStatus'] == 'not_linked')
            .length,
        'scored': errors.length,
        'predictionCoverage': active.isEmpty
            ? null
            : predictions / active.length,
        'outcomeMissingnessRate': active.isEmpty
            ? null
            : (active.length - completed) / active.length,
        'lateOriginalResponses': active.fold<int>(
          0,
          (sum, row) =>
              sum +
              ((row['outcome'] as Map?)?['lateOriginalResponses'] as int? ?? 0),
        ),
        'mae': errors.isEmpty
            ? null
            : errors.reduce((a, b) => a + b) / errors.length,
      },
      'rows': rows,
      'limitations': [
        'Invented fixtures and simulated store receipts are not actual prospective measurements or native durability proof.',
        'Unopened planned days remain in closed-window denominators; not_linked means assessment is unavailable, not an inferred missing answer.',
        'Failure statuses are in-memory diagnostics, not proof that a failed write was saved.',
        'Failed erasures block later reads and are retried within this harness instance; this is not native crash-recovery evidence.',
        'Observed response revisions are immutable and cumulative; omitted or changed known history fails closed on later assessments.',
        'Erasure applies to every replay; signout preserves only previously committed scoped history.',
        'One immutable model is frozen per block; no app display, Coach action, real-data inference or training is enabled.',
      ],
    });
  }

  void _validateEvidence(Ai1FixtureDay evidence) {
    _requireActive();
    if (!evidence.synthetic) {
      throw ArgumentError('Invented synthetic evidence is required.');
    }
    final expected = _block!.opportunities
        .where((day) => day.id == evidence.opportunity.id)
        .firstOrNull;
    if (expected == null ||
        expected.timezone != evidence.opportunity.timezone ||
        expected.cutoff != evidence.opportunity.cutoff) {
      throw ArgumentError('Evidence must match the prespecified calendar.');
    }
  }

  void _requireActive() {
    if (!active) {
      throw StateError('Start an uninterrupted synthetic session first.');
    }
  }

  DateTime _now() {
    final now = _clock().toUtc();
    if (_lastClock != null && now.isBefore(_lastClock!)) {
      throw StateError('The simulated clock moved backwards.');
    }
    if (_committed != null &&
        now.isBefore(DateTime.parse(_committed!['lastReceiptAt'] as String))) {
      throw StateError('The simulated clock precedes committed history.');
    }
    _lastClock = now;
    return now;
  }

  bool _current(String scope, int generation) =>
      _scope == scope && _generation == generation;
  Future<void> _restore(String scope, Map<String, dynamic>? state) async {
    if (state == null) {
      _eraseObligations.add(scope);
      await _retryErasures();
    } else {
      try {
        await _store.write(scope, _copy(state));
      } on Object {
        // A canceled write may have reached storage; never reload it as valid.
        _eraseObligations.add(scope);
        rethrow;
      }
    }
  }

  Future<void> _retryErasures() async {
    for (final scope in _eraseObligations.toList()) {
      await _store.clear(scope);
      _eraseObligations.remove(scope);
    }
  }

  Future<void> _serialized(Future<void> Function() action) async {
    final previous = _queue;
    final pending = previous == null
        ? action()
        : previous.then((_) => action());
    final tail = pending.catchError((Object _) {});
    _queue = tail;
    try {
      await pending;
    } finally {
      if (identical(_queue, tail)) _queue = null;
    }
  }

  void _validateSaved(
    Map<String, dynamic> state,
    String scope,
    AiShadowBlock block,
  ) {
    _exactKeys(state, {
      'schemaVersion',
      'synthetic',
      'simulatedDurability',
      'scope',
      'blockFingerprint',
      'planCreatedAt',
      'planReceiptAt',
      'lastReceiptAt',
      'pending',
      'events',
      'outcomes',
      'tombstones',
    });
    if (state['schemaVersion'] != 'ai6-synthetic-shadow-state-v1' ||
        state['synthetic'] != true ||
        state['simulatedDurability'] != true ||
        state['scope'] != scope ||
        state['blockFingerprint'] != block.fingerprint ||
        state['pending'] != false ||
        state['events'] is! Map ||
        state['outcomes'] is! Map ||
        state['tombstones'] is! Map) {
      throw StateError(
        'Stored synthetic history is interrupted or incompatible; reset it.',
      );
    }
    final created = _storedTime(state['planCreatedAt']);
    final receipt = _storedTime(state['planReceiptAt']);
    final last = _storedTime(state['lastReceiptAt']);
    if (created.isBefore(block.artifact.fittedAt) ||
        receipt.isBefore(created) ||
        !receipt.isBefore(block.opportunities.first.dayStart) ||
        last.isBefore(receipt)) {
      throw StateError('Invalid simulated plan receipt.');
    }
    final allowed = block.opportunities.map((day) => day.id).toSet();
    for (final name in ['events', 'outcomes', 'tombstones']) {
      final entries = state[name] as Map;
      for (final entry in entries.entries) {
        if (!allowed.contains(entry.key) ||
            entry.value is! Map ||
            (entry.value as Map)['receiptAt'] is! String) {
          throw StateError('Invalid simulated history entry.');
        }
        final timestamp = DateTime.tryParse(
          (entry.value as Map)['receiptAt'] as String,
        );
        if (timestamp == null ||
            timestamp.isBefore(receipt) ||
            timestamp.isAfter(last)) {
          throw StateError('Invalid simulated history receipt.');
        }
      }
    }
    final events = state['events'] as Map;
    final outcomes = state['outcomes'] as Map;
    final tombstones = state['tombstones'] as Map;
    for (final entry in events.entries) {
      final event = entry.value as Map;
      _exactKeys(event, {
        'eventId',
        'opportunityId',
        'artifactId',
        'artifactFingerprint',
        'executedAt',
        'receiptAt',
        'executionStatus',
        'sleepStatus',
        'modelStatus',
        'rawPrediction',
        'prediction',
        'feature',
      });
      if (event['artifactFingerprint'] != block.artifact.fingerprint) {
        throw StateError('A block cannot change its model.');
      }
      final opportunity = block.opportunities.singleWhere(
        (day) => day.id == entry.key,
      );
      final executed = _storedTime(event['executedAt']);
      final saved = _storedTime(event['receiptAt']);
      if (event['opportunityId'] != entry.key ||
          event['eventId'] !=
              ai1CanonicalJson([block.blockId, scope, entry.key]) ||
          event['artifactId'] != block.artifact.artifactId ||
          executed.isBefore(receipt) ||
          saved.isBefore(executed) ||
          event['sleepStatus'] is! String) {
        throw StateError('Invalid frozen simulated event.');
      }
      if (event['executionStatus'] == 'executed') {
        if (executed.isBefore(opportunity.cutoff) ||
            !executed.isBefore(opportunity.issuanceDeadline) ||
            !saved.isBefore(opportunity.issuanceDeadline)) {
          throw StateError('An event receipt missed its execution window.');
        }
        final rawFeature = event['feature'];
        Map? feature;
        if (rawFeature != null) {
          if (rawFeature is! Map) throw StateError('Invalid frozen feature.');
          feature = rawFeature;
          _exactKeys(feature, {
            'sourceKey',
            'revision',
            'source',
            'durationHours',
            'startedAt',
            'endedAt',
            'availableAt',
            'selectionDependencies',
          });
          final hours = feature['durationHours'];
          final ended = _storedTime(feature['endedAt']);
          final available = _storedTime(feature['availableAt']);
          if (feature['sourceKey'] is! String ||
              (feature['sourceKey'] as String).isEmpty ||
              feature['revision'] is! int ||
              (feature['revision'] as int) < 1 ||
              feature['source'] != block.protocol.sleepSource.name ||
              hours is! num ||
              !hours.isFinite ||
              hours < 0.5 ||
              hours > 16 ||
              ended.isBefore(opportunity.dayStart) ||
              ended.isAfter(opportunity.cutoff) ||
              available.isBefore(ended) ||
              available.isAfter(opportunity.cutoff) ||
              feature['selectionDependencies'] is! List ||
              (feature['startedAt'] != null &&
                  !_storedTime(feature['startedAt']).isBefore(ended))) {
            throw StateError('Invalid frozen feature provenance.');
          }
          for (final dependency in feature['selectionDependencies'] as List) {
            if (_storedTime(dependency).isAfter(opportunity.cutoff)) {
              throw StateError('A selection dependency arrived after cutoff.');
            }
          }
        }
        final prediction = block.artifact.predict(
          context: AiModelInferenceContext(
            ownerScope: scope,
            participantKey: opportunity.participantKey,
            protocol: block.protocol,
            timezone: opportunity.timezone,
            at: executed,
            featureCutoff: opportunity.cutoff,
            dataGeneration: block.artifact.dataGeneration,
          ),
          sleepHours: (feature?['durationHours'] as num?)?.toDouble(),
          sleepAvailableAt: feature == null
              ? null
              : _storedTime(feature['availableAt']),
        );
        if (event['prediction'] != prediction.prediction ||
            event['rawPrediction'] != prediction.rawPrediction ||
            event['modelStatus'] !=
                (prediction.predicted
                    ? 'predicted'
                    : prediction.abstentionReason)) {
          throw StateError('A stored result does not match the frozen model.');
        }
      } else if (!{
            'missed_window',
            'timezone_changed_before_execution',
            'withdrawn',
          }.contains(event['executionStatus']) ||
          event['prediction'] != null ||
          event['rawPrediction'] != null ||
          event['feature'] != null ||
          event['modelStatus'] != 'no_execution') {
        throw StateError('An unexecuted event cannot carry a prediction.');
      }
    }
    for (final entry in outcomes.entries) {
      final current = entry.value as Map;
      if (current['previousAssessments'] is! List) {
        throw StateError('Invalid outcome revision history.');
      }
      _exactKeys(current, {
        'assessedAt',
        'receiptAt',
        'status',
        'energy',
        'pairingStatus',
        'lateOriginalResponses',
        'knownResponseFingerprints',
        'responseIntegrityStatus',
        'previousAssessments',
      });
      final opportunity = block.opportunities.singleWhere(
        (day) => day.id == entry.key,
      );
      DateTime? previous;
      Map<String, String> knownResponses = {};
      String? integrity;
      for (final raw in [
        ...current['previousAssessments'] as List,
        Map.from(current)..remove('previousAssessments'),
      ]) {
        if (raw is! Map) throw StateError('Invalid outcome revision.');
        _exactKeys(raw, {
          'assessedAt',
          'receiptAt',
          'status',
          'energy',
          'pairingStatus',
          'lateOriginalResponses',
          'knownResponseFingerprints',
          'responseIntegrityStatus',
        });
        final assessed = _storedTime(raw['assessedAt']);
        final saved = _storedTime(raw['receiptAt']);
        final energy = raw['energy'];
        final storedKnowledge = raw['knownResponseFingerprints'];
        final nextIntegrity = raw['responseIntegrityStatus'];
        if (storedKnowledge is! Map ||
            storedKnowledge.entries.any(
              (entry) =>
                  entry.key is! String ||
                  entry.value is! String ||
                  (entry.key as String).isEmpty ||
                  (entry.value as String).isEmpty,
            ) ||
            knownResponses.entries.any(
              (entry) => storedKnowledge[entry.key] != entry.value,
            ) ||
            (nextIntegrity != null &&
                !{
                  'selected_response_revised',
                  'conflicting_response_revision',
                  'response_history_regressed',
                }.contains(nextIntegrity)) ||
            (integrity != null && nextIntegrity == null) ||
            (nextIntegrity != null &&
                (raw['status'] != nextIntegrity || energy != null))) {
          throw StateError(
            'Known response history cannot be removed or changed.',
          );
        }
        knownResponses = Map<String, String>.from(storedKnowledge);
        integrity = nextIntegrity as String?;
        if (assessed.isBefore(opportunity.outcomeEnd) ||
            saved.isBefore(assessed) ||
            saved.isAfter(last) ||
            (previous != null && saved.isBefore(previous)) ||
            raw['status'] is! String ||
            (raw['status'] as String).isEmpty ||
            !{
              'compatible',
              'feature_lineage_changed',
            }.contains(raw['pairingStatus']) ||
            raw['lateOriginalResponses'] is! int ||
            (raw['lateOriginalResponses'] as int) < 0 ||
            (raw['status'] == 'matched'
                ? energy is! int || energy < 1 || energy > 10
                : energy != null)) {
          throw StateError('Invalid closed-window outcome assessment.');
        }
        previous = saved;
      }
    }
    for (final entry in tombstones.entries) {
      final marker = entry.value as Map;
      _exactKeys(marker, {'reason', 'observedAt', 'receiptAt'});
      if (!{'deleted', 'withdrawn'}.contains(marker['reason']) ||
          _storedTime(
            marker['receiptAt'],
          ).isBefore(_storedTime(marker['observedAt'])) ||
          events.containsKey(entry.key) ||
          outcomes.containsKey(entry.key)) {
        throw StateError('Deleted evidence must not retain derived payloads.');
      }
    }
  }
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

bool _requestsErasure(Ai1FixtureDay evidence) =>
    evidence.withdrawn ||
    evidence.sleepRevisions.any((row) => row.deleted) ||
    evidence.responseRevisions.any((row) => row.deleted);

Map<String, dynamic> _featureSnapshot(Ai1SleepRevision row) => {
  'sourceKey': row.key,
  'revision': row.revision,
  'source': row.source.name,
  'durationHours': row.durationHours,
  'startedAt': row.startedAt?.toIso8601String(),
  'endedAt': row.endedAt.toIso8601String(),
  'availableAt': row.availableAt!.toIso8601String(),
  'selectionDependencies': row.selectionDependencies
      .map((time) => time!.toIso8601String())
      .toList(),
};

void _exactKeys(Map value, Set<String> expected) {
  if (value.length != expected.length || !expected.every(value.containsKey)) {
    throw StateError('Unexpected simulated history fields.');
  }
}

DateTime _storedTime(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw StateError('Invalid simulated UTC timestamp.');
  }
  return parsed;
}
