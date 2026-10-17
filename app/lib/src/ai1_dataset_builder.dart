import 'ai1_protocol.dart';
import 'ai1_records.dart';

/// First AI-1 slice: deterministic checks on invented, local fixtures only.
/// There is deliberately no adapter from app records or training entry point.
abstract final class Ai1DatasetBuilder {
  static Ai1DatasetReport buildSynthetic({
    required Ai1Protocol protocol,
    required Iterable<Ai1FixtureDay> days,
    required DateTime asOf,
    required String datasetVersion,
  }) {
    final freeze = asOf.toUtc();
    if (datasetVersion.trim().isEmpty) {
      throw ArgumentError.value(datasetVersion, 'datasetVersion');
    }
    final uniqueDays = <String, Ai1FixtureDay>{};
    for (final day in days) {
      if (!day.synthetic) {
        throw ArgumentError('AI-1 currently accepts synthetic fixtures only.');
      }
      if (day.opportunity.protocolId != protocol.id) {
        throw ArgumentError('Each opportunity must use the supplied protocol.');
      }
      if (freeze.isBefore(day.opportunity.outcomeEnd)) {
        throw ArgumentError(
          'The analysis freeze must follow the outcome window.',
        );
      }
      final previous = uniqueDays[day.opportunity.id];
      if (previous != null &&
          _dayFingerprint(previous) != _dayFingerprint(day)) {
        throw ArgumentError('Conflicting copies of one daily opportunity.');
      }
      uniqueDays[day.opportunity.id] = day;
    }
    final ordered = uniqueDays.values.toList()
      ..sort((a, b) => a.opportunity.id.compareTo(b.opportunity.id));
    return Ai1DatasetReport._(
      protocol: protocol,
      datasetVersion: datasetVersion,
      asOf: freeze,
      rows: [for (final day in ordered) _buildDay(protocol, day, freeze)],
    );
  }

  static Ai1DatasetRow _buildDay(
    Ai1Protocol protocol,
    Ai1FixtureDay day,
    DateTime asOf,
  ) {
    if (day.withdrawn) {
      return Ai1DatasetRow._(
        opportunity: day.opportunity,
        sleepStatus: 'withdrawn',
        issuanceStatus: 'withdrawn',
        outcomeStatus: 'withdrawn',
      );
    }
    final sleep = _selectSleep(protocol, day);
    final issuance = _issuanceStatus(day, sleep.status);
    final outcome = _selectOutcome(protocol, day, asOf, issuance == 'issued');
    return Ai1DatasetRow._(
      opportunity: day.opportunity,
      sleepStatus: sleep.status,
      issuanceStatus: issuance,
      outcomeStatus: outcome.status,
      feature: issuance == 'issued' ? sleep.record : null,
      issuedAt: issuance == 'issued' ? day.issuedAt : null,
      durableAt: issuance == 'issued' ? day.durableAt : null,
      energy: outcome.energy,
      responseId: outcome.responseId,
      outcome: outcome.record,
    );
  }

  static ({String status, Ai1SleepRevision? record}) _selectSleep(
    Ai1Protocol protocol,
    Ai1FixtureDay day,
  ) {
    if (!day.sleepHistoryComplete) {
      return (status: 'sleep_lineage_incomplete', record: null);
    }
    final opportunity = day.opportunity;
    final relevant = day.sleepRevisions
        .where((row) => row.participantKey == opportunity.participantKey)
        .toList();
    final selectedKeys = relevant
        .where((row) => row.source == protocol.sleepSource)
        .map((row) => row.key)
        .toSet();
    final groups = <String, List<Ai1SleepRevision>>{};
    for (final row in relevant.where((row) => selectedKeys.contains(row.key))) {
      (groups[row.key] ??= []).add(row);
    }
    final candidates = <Ai1SleepRevision>[];
    for (final key in groups.keys.toList()..sort()) {
      final revisions = groups[key]!;
      // Unknown availability cannot be filled with the observation instant.
      if (revisions.any((row) => row.availableAt == null)) {
        return (status: 'unknown_sleep_availability', record: null);
      }
      final past = revisions
          .where((row) => !row.availableAt!.isAfter(opportunity.cutoff))
          .toList();
      if (past.isEmpty) continue;
      if (past.any((row) => !row.lineageComplete)) {
        return (status: 'sleep_lineage_incomplete', record: null);
      }
      if (past.any(
        (row) =>
            row.revision < 1 ||
            row.collection.trim().isEmpty ||
            row.sourceId.trim().isEmpty ||
            row.source != protocol.sleepSource,
      )) {
        return (status: 'invalid_sleep', record: null);
      }
      final byRevision = <int, Ai1SleepRevision>{};
      for (final row in past) {
        final previous = byRevision[row.revision];
        if (previous != null && previous.fingerprint != row.fingerprint) {
          return (status: 'conflicting_sleep_revision', record: null);
        }
        byRevision[row.revision] = row;
      }
      final ordered = byRevision.values.toList()
        ..sort((a, b) => a.revision.compareTo(b.revision));
      if (ordered.first.revision != 1) {
        return (status: 'sleep_lineage_incomplete', record: null);
      }
      for (var i = 1; i < ordered.length; i++) {
        if (ordered[i].revision != ordered[i - 1].revision + 1 ||
            ordered[i].availableAt!.isBefore(ordered[i - 1].availableAt!)) {
          return (status: 'sleep_lineage_incomplete', record: null);
        }
      }
      final row = ordered.last;
      // A tombstone may remove the latest summary's main-sleep/date fields.
      // Inspect the retained history first so it cannot promote a replacement.
      if (revisions.any((revision) => revision.deleted) &&
          past.any(
            (revision) =>
                revision.isMainSleep &&
                !revision.endedAt.isBefore(opportunity.dayStart) &&
                !revision.endedAt.isAfter(opportunity.cutoff),
          )) {
        return (status: 'sleep_deleted', record: null);
      }
      if (!row.isMainSleep ||
          row.endedAt.isBefore(opportunity.dayStart) ||
          row.endedAt.isAfter(opportunity.cutoff)) {
        continue;
      }
      if (row.selectionDependencies.any((time) => time == null)) {
        return (status: 'unknown_sleep_availability', record: null);
      }
      if (row.selectionDependencies.any(
        (time) => time!.isAfter(opportunity.cutoff),
      )) {
        continue;
      }
      if (!row.durationHours.isFinite ||
          row.durationHours < 0.5 ||
          row.durationHours > 16 ||
          row.availableAt!.isBefore(row.endedAt) ||
          (row.startedAt != null && !row.startedAt!.isBefore(row.endedAt))) {
        return (status: 'invalid_sleep', record: null);
      }
      candidates.add(row);
    }
    if (candidates.isEmpty) return (status: 'no_eligible_sleep', record: null);
    if (candidates.length > 1) return (status: 'ambiguous_sleep', record: null);
    return (status: 'eligible', record: candidates.single);
  }

  static String _issuanceStatus(Ai1FixtureDay day, String sleepStatus) {
    final issuedAt = day.issuedAt;
    if (issuedAt == null) return 'not_issued';
    final opportunity = day.opportunity;
    if (!_inWindow(
      issuedAt,
      opportunity.cutoff,
      opportunity.issuanceDeadline,
    )) {
      return 'missed_cutoff';
    }
    final durableAt = day.durableAt;
    if (durableAt == null || durableAt.isBefore(issuedAt)) {
      return 'save_not_proven';
    }
    if (!_inWindow(
      durableAt,
      opportunity.cutoff,
      opportunity.issuanceDeadline,
    )) {
      return 'missed_cutoff';
    }
    if (sleepStatus != 'eligible') return 'no_eligible_sleep';
    return 'issued';
  }

  static ({
    String status,
    int? energy,
    String? responseId,
    Ai1ResponseRevision? record,
  })
  _selectOutcome(
    Ai1Protocol protocol,
    Ai1FixtureDay day,
    DateTime asOf,
    bool issued,
  ) {
    ({
      String status,
      int? energy,
      String? responseId,
      Ai1ResponseRevision? record,
    })
    missing(String status, [String? id]) =>
        (status: status, energy: null, responseId: id, record: null);

    if (!day.responseHistoryComplete) {
      return missing('response_lineage_incomplete');
    }
    final opportunity = day.opportunity;
    final groups = <String, List<Ai1ResponseRevision>>{};
    for (final row in day.responseRevisions) {
      if (row.participantKey == opportunity.participantKey) {
        (groups[row.key] ??= []).add(row);
      }
    }
    final originals = <Ai1ResponseRevision>[];
    for (final key in groups.keys.toList()..sort()) {
      final revisions = groups[key]!;
      final known = revisions
          .where((row) => !row.availableAt.isAfter(asOf))
          .toList();
      if (known.isEmpty) continue;
      if (known.any(
        (row) =>
            !row.lineageComplete ||
            row.revision < 1 ||
            row.sourceId.trim().isEmpty,
      )) {
        return missing('response_lineage_incomplete');
      }
      final byRevision = <int, Ai1ResponseRevision>{};
      for (final row in known) {
        final previous = byRevision[row.revision];
        if (previous != null && previous.fingerprint != row.fingerprint) {
          return missing('conflicting_response_revision');
        }
        byRevision[row.revision] = row;
      }
      final original = byRevision[1];
      if (original == null ||
          original.availableAt.isBefore(original.initialSavedAt)) {
        return missing('response_lineage_incomplete');
      }
      final ordered = byRevision.values.toList()
        ..sort((a, b) => a.revision.compareTo(b.revision));
      for (var i = 1; i < ordered.length; i++) {
        if (ordered[i].revision != ordered[i - 1].revision + 1 ||
            ordered[i].availableAt.isBefore(ordered[i - 1].availableAt) ||
            ordered[i].initialSavedAt != original.initialSavedAt) {
          return missing('response_lineage_incomplete');
        }
      }
      // Check timing, provenance and exact wording before inspecting Energy.
      if (original.period != 'Evening' ||
          original.localDate != opportunity.localDate ||
          original.timezone != opportunity.timezone ||
          original.measurement != protocol.measurement ||
          !_inWindow(
            original.observedAt,
            opportunity.outcomeStart,
            opportunity.outcomeEnd,
          ) ||
          !_inWindow(
            original.initialSavedAt,
            opportunity.outcomeStart,
            opportunity.outcomeEnd,
          ) ||
          original.initialSavedAt.isBefore(original.observedAt) ||
          (issued && !original.observedAt.isAfter(day.durableAt!))) {
        continue;
      }
      originals.add(original);
    }
    originals.sort((a, b) {
      var comparison = a.observedAt.compareTo(b.observedAt);
      if (comparison == 0) {
        comparison = a.initialSavedAt.compareTo(b.initialSavedAt);
      }
      if (comparison == 0) comparison = a.sourceId.compareTo(b.sourceId);
      return comparison;
    });
    if (originals.isEmpty) return missing('no_response_in_window');
    final selected = originals.first;
    final revisions = groups[selected.key]!;
    if (revisions.any((row) => row.deleted)) {
      return missing('selected_response_deleted', selected.sourceId);
    }
    if (revisions.any(
      (row) => row.revision > 1 && !row.availableAt.isAfter(asOf),
    )) {
      return missing('selected_response_revised', selected.sourceId);
    }
    if (issued &&
        day.timezoneChanges.any(
          (time) =>
              !time.isBefore(day.issuedAt!) &&
              !time.isAfter(selected.observedAt),
        )) {
      return missing('timezone_changed', selected.sourceId);
    }
    final energy = selected.energy;
    if (energy == null) return missing('missing_energy', selected.sourceId);
    if (!energy.isFinite ||
        energy < 1 ||
        energy > 10 ||
        energy != energy.roundToDouble()) {
      return missing('invalid_energy', selected.sourceId);
    }
    return (
      status: 'matched',
      energy: energy.toInt(),
      responseId: selected.sourceId,
      record: selected,
    );
  }
}

/// Coverage remains auditable even when a fixture has no prediction or target.
class Ai1DatasetRow {
  Ai1DatasetRow._({
    required this.opportunity,
    required this.sleepStatus,
    required this.issuanceStatus,
    required this.outcomeStatus,
    this.feature,
    this.issuedAt,
    this.durableAt,
    this.energy,
    this.responseId,
    this.outcome,
  });

  final Ai1Opportunity opportunity;
  final String sleepStatus;
  final String issuanceStatus;
  final String outcomeStatus;
  final Ai1SleepRevision? feature;
  final DateTime? issuedAt;
  final DateTime? durableAt;
  final int? energy;
  final String? responseId;
  final Ai1ResponseRevision? outcome;

  bool get hasPair => issuanceStatus == 'issued' && outcomeStatus == 'matched';

  Map<String, Object?> toJson() => {
    ..._opportunityJson(opportunity),
    'sleepStatus': sleepStatus,
    'issuanceStatus': issuanceStatus,
    'outcomeStatus': outcomeStatus,
    'issuedAt': issuedAt?.toIso8601String(),
    'durableAt': durableAt?.toIso8601String(),
    'feature': feature == null
        ? null
        : {
            'main_sleep_duration_hours': feature!.durationHours,
            'source': feature!.source.name,
            'sourceKey': feature!.key,
            'revision': feature!.revision,
            'endedAt': feature!.endedAt.toIso8601String(),
            'startedAt': feature!.startedAt?.toIso8601String(),
            'availableAt': feature!.availableAt!.toIso8601String(),
            'selectionDependencies': [
              for (final time in feature!.selectionDependencies)
                time!.toIso8601String(),
            ],
          },
    'responseId': responseId,
    'energy': energy,
    'outcomeObservedAt': outcome?.observedAt.toIso8601String(),
    'outcomeInitialSavedAt': outcome?.initialSavedAt.toIso8601String(),
    'outcomeAvailableAt': outcome?.availableAt.toIso8601String(),
    'fixturePair': hasPair,
    'trainingEligible': false,
  };
}

class Ai1DatasetReport {
  Ai1DatasetReport._({
    required this.protocol,
    required this.datasetVersion,
    required this.asOf,
    required List<Ai1DatasetRow> rows,
  }) : rows = List.unmodifiable(rows);

  final Ai1Protocol protocol;
  final String datasetVersion;
  final DateTime asOf;
  final List<Ai1DatasetRow> rows;

  int get fixturePairCount => rows.where((row) => row.hasPair).length;
  int get trainingEligibleCount => 0;

  Map<String, Object?> toJson() => {
    'schemaVersion': 'ai1-synthetic-audit-v1',
    'datasetVersion': datasetVersion,
    'asOf': asOf.toIso8601String(),
    'synthetic': true,
    'protocolId': protocol.id,
    'measurement': protocol.measurement,
    'coverage': {
      'opportunities': rows.length,
      'sleepEligible': rows
          .where((row) => row.sleepStatus == 'eligible')
          .length,
      'issued': rows.where((row) => row.issuanceStatus == 'issued').length,
      'outcomeComplete': rows
          .where((row) => row.outcomeStatus == 'matched')
          .length,
      'fixturePairs': fixturePairCount,
      'trainingEligible': trainingEligibleCount,
      'sleepStatuses': _counts(rows.map((row) => row.sleepStatus)),
      'issuanceStatuses': _counts(rows.map((row) => row.issuanceStatus)),
      'outcomeStatuses': _counts(rows.map((row) => row.outcomeStatus)),
    },
    'rows': [for (final row in rows) row.toJson()],
  };
}

bool _inWindow(DateTime time, DateTime start, DateTime end) =>
    !time.isBefore(start) && time.isBefore(end);

Map<String, int> _counts(Iterable<String> values) {
  final result = <String, int>{};
  for (final value in values) {
    result.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  return result;
}

Map<String, Object?> _opportunityJson(Ai1Opportunity opportunity) => {
  'opportunityId': opportunity.id,
  'protocolId': opportunity.protocolId,
  'participantKey': opportunity.participantKey,
  'localDate': opportunity.localDate,
  'timezone': opportunity.timezone,
  'dayStart': opportunity.dayStart.toIso8601String(),
  'cutoff': opportunity.cutoff.toIso8601String(),
  'issuanceDeadline': opportunity.issuanceDeadline.toIso8601String(),
  'outcomeStart': opportunity.outcomeStart.toIso8601String(),
  'outcomeEnd': opportunity.outcomeEnd.toIso8601String(),
};

String _dayFingerprint(Ai1FixtureDay day) => ai1CanonicalJson({
  'opportunity': _opportunityJson(day.opportunity),
  'sleepHistoryComplete': day.sleepHistoryComplete,
  'responseHistoryComplete': day.responseHistoryComplete,
  'sleepRevisions':
      day.sleepRevisions.map((row) => row.fingerprint).toSet().toList()..sort(),
  'responseRevisions':
      day.responseRevisions.map((row) => row.fingerprint).toSet().toList()
        ..sort(),
  'issuedAt': day.issuedAt?.toIso8601String(),
  'durableAt': day.durableAt?.toIso8601String(),
  'timezoneChanges':
      day.timezoneChanges.map((time) => time.toIso8601String()).toSet().toList()
        ..sort(),
  'withdrawn': day.withdrawn,
});
