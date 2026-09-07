import 'dart:convert';

import 'energy_model_repository.dart';
import 'energy_residual_model.dart';
import 'ml_prep_builder.dart';
import 'ml_prep_models.dart';
import 'ml_prep_service.dart';

/// Owns a tiny local artifact and a durable training-attempt ledger. No source
/// reads, listeners, timers, or inference writes are available on this path.
class EnergyModelService {
  EnergyModelService({
    required this.store,
    required this.writer,
    required this.currentUid,
    required this.consentAllowed,
    required this.now,
  });

  final EnergyModelStore store;
  final EnergyModelMetadataWriter? writer;
  final String? Function() currentUid;
  final bool Function() consentAllowed;
  final DateTime Function() now;
  EnergyResidualModel? _model;
  String? _loadedUid;
  DateTime? _lastAttempt;
  Set<String> _previousOutcomes = {};
  Future<void>? _loading;
  String? _loadingUid;
  int _generation = 0;
  bool busy = false;
  String status = 'Deterministic Energy scoring · no accepted local model.';

  EnergyResidualModel? get model {
    final value = _model;
    if (value == null ||
        !consentAllowed() ||
        currentUid() != _loadedUid ||
        value.ownerKey != prepFingerprint({'uid': currentUid()}) ||
        now().isBefore(value.trainedAt)) {
      return null;
    }
    return value;
  }

  void cancelPending() => _generation++;

  void unload() {
    cancelPending();
    _model = null;
    _loadedUid = null;
    _lastAttempt = null;
    _previousOutcomes = {};
    status = 'Deterministic Energy scoring · sign in and prepare your data.';
  }

  /// Restores only owner-local storage. Never trains or contacts Firebase.
  Future<void> load() {
    final uid = currentUid();
    if (uid == null || !consentAllowed()) {
      unload();
      return Future.value();
    }
    if (_loadingUid == uid && _loading != null) return _loading!;
    final task = _loadOwner(uid);
    _loading = task;
    _loadingUid = uid;
    return task.whenComplete(() {
      if (identical(_loading, task)) {
        _loading = null;
        _loadingUid = null;
      }
    });
  }

  Future<void> _loadOwner(String uid) async {
    final generation = ++_generation;
    _loadedUid = null;
    _model = null;
    _lastAttempt = null;
    _previousOutcomes = {};
    status = 'Deterministic Energy scoring · no accepted local model.';
    try {
      final raw = await store.read(uid);
      if (!_current(uid, generation)) return;
      _loadedUid = uid;
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['schemaVersion'] != 1 ||
          json['ownerKey'] != prepFingerprint({'uid': uid})) {
        throw const FormatException('Incompatible model state.');
      }
      final attempt = json['lastAttemptAt'];
      _lastAttempt = attempt == null ? null : DateTime.parse(attempt as String);
      final keys = (json['eligibleOutcomeKeys'] as List).cast<String>();
      if (keys.length > 100 || keys.any((key) => key.length > 80)) {
        throw const FormatException('Invalid training ledger.');
      }
      _previousOutcomes = keys.toSet();
      if (json['model'] != null) {
        final candidate = EnergyResidualModel.fromJson(
          Map<String, dynamic>.from(json['model'] as Map),
        );
        if (candidate.ownerKey != prepFingerprint({'uid': uid})) {
          throw const FormatException('Model owner mismatch.');
        }
        _model = candidate;
        status =
            'Accepted on-device Energy model restored. Cognitive stays deterministic.';
      }
    } on Object {
      if (!_current(uid, generation)) return;
      _model = null;
      // A corrupt ledger cannot be used to bypass the daily training limit.
      _lastAttempt = now();
      _previousOutcomes = {};
      _loadedUid = uid;
      status =
          'Saved model unavailable. Using deterministic scoring; retry a model refresh after 24 hours.';
      // Repair only local storage; otherwise each restart of a corrupt ledger
      // would restart the cooldown and make recovery impossible.
      try {
        await store.write(uid, _envelope(uid));
      } on Object {
        /* Keep fallback. */
      }
    }
  }

  bool _current(String uid, int generation) =>
      currentUid() == uid && consentAllowed() && generation == _generation;

  String _envelope(String uid) => jsonEncode({
    'schemaVersion': 1,
    'ownerKey': prepFingerprint({'uid': uid}),
    'model': _model?.toJson(),
    'lastAttemptAt': _lastAttempt?.toUtc().toIso8601String(),
    'eligibleOutcomeKeys': _previousOutcomes.toList()..sort(),
  });

  /// Revocation/deletion erases weights, but keeps the rate-limit ledger.
  Future<void> discard() async {
    cancelPending();
    final generation = _generation;
    final uid = currentUid();
    _model = null;
    status =
        'Deterministic Energy scoring · model cleared after data or consent changed.';
    if (uid == null) return;
    // Read only the ledger if this owner has not been loaded (e.g. revocation
    // immediately after launch). Never restore a model while consent is off.
    var attempt = _lastAttempt;
    var keys = _previousOutcomes;
    if (_loadedUid != uid) {
      attempt = null;
      keys = {};
      try {
        final raw = await store.read(uid);
        if (raw != null) {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          if (json['ownerKey'] == prepFingerprint({'uid': uid})) {
            attempt = DateTime.tryParse(json['lastAttemptAt'] as String? ?? '');
            keys = (json['eligibleOutcomeKeys'] as List)
                .cast<String>()
                .take(100)
                .toSet();
          }
        }
      } on Object {
        attempt = now();
      }
    }
    if (currentUid() == uid && _generation == generation) {
      _lastAttempt = attempt;
      _previousOutcomes = keys;
      _loadedUid = uid;
      await store.write(uid, _envelope(uid));
    }
  }

  /// The caller must supply its still-valid prepared snapshot. In particular,
  /// this method cannot silently fetch a replacement window from the server.
  Future<void> refresh(PrepRun run) async {
    if (busy) return;
    final uid = currentUid();
    if (uid == null || !consentAllowed() || writer == null) {
      throw StateError(
        'Sign in and enable outcome learning before model refresh.',
      );
    }
    busy = true;
    try {
      if (_loadedUid != uid) {
        final loading = load();
        final expectedGeneration = _generation;
        await loading;
        if (!_current(uid, expectedGeneration) || _loadedUid != uid) return;
      }
      final generation = _generation;
      if (!_current(uid, generation) ||
          run.snapshot.uid != uid ||
          !run.snapshot.consent.allowed) {
        throw StateError(
          'Account or consent changed. Prepare the account again.',
        );
      }
      // Rebuild eligibility from immutable source records, never trust a caller
      // to change report flags, labels, provenance, or the split in-place.
      final report = MlPrepBuilder.build(run.snapshot);
      if (!report.energyReady || run.snapshot.fetchedAt.isAfter(now())) {
        await discard();
        status =
            'Not enough eligible data. Energy needs 14 genuine labeled days and sufficient known inputs; deterministic scoring is unchanged.';
        return;
      }
      final at = now();
      if (_lastAttempt != null &&
          at.difference(_lastAttempt!) < const Duration(hours: 24)) {
        status =
            'Model refresh is limited to once per 24 hours. The existing scoring mode is unchanged.';
        return;
      }
      final keys = report.examples
          .where((row) => row.head == 'energy')
          .map((row) => prepFingerprint({'outcomeId': row.outcomeId}))
          .toSet();
      if (keys.difference(_previousOutcomes).isEmpty) {
        status =
            'No new eligible Energy outcome. Keep collecting real outcomes before refreshing.';
        return;
      }
      _lastAttempt = at;
      _previousOutcomes = keys;
      // Record attempts before fitting so even rejection, process interruption,
      // or an unavailable metadata write cannot cause repeated daily training.
      await store.write(uid, _envelope(uid));
      if (!_current(uid, generation)) return;
      final fit = EnergyResidualTrainer.train(
        snapshot: run.snapshot,
        report: report,
        trainedAt: at,
      );
      if (!_current(uid, generation)) return;
      final previous = _model;
      _model = fit.model;
      final acceptedEnvelope = _envelope(uid);
      final canceledEnvelope = jsonEncode({
        ...jsonDecode(acceptedEnvelope) as Map<String, dynamic>,
        'model': null,
      });
      await store.write(uid, acceptedEnvelope);
      if (!_current(uid, generation)) {
        if (_loadedUid == uid) _model = null;
        // Keep the consumed training attempt but remove stale candidate weights.
        await store.write(uid, canceledEnvelope);
        return;
      }
      if (_model == null) {
        status =
            'Candidate not promoted (${fit.reason}). Using deterministic Energy scoring.';
        return;
      }
      status =
          'Energy model accepted on device after holdout validation. Cognitive and confidence are unchanged.';
      if (previous?.fingerprint != _model!.fingerprint ||
          previous?.trainedAt != _model!.trainedAt) {
        try {
          await writer!.writeAccepted(uid, _model!.metadata);
          if (!_current(uid, generation)) return;
        } on Object {
          if (_current(uid, generation)) {
            status =
                'Energy model accepted locally; metadata sync unavailable. No automatic retry or extra database traffic.';
          }
        }
      }
    } finally {
      busy = false;
    }
  }
}
