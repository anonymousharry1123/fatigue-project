import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;

import 'ai1_capture_store.dart';
import 'models.dart';
import 'sleep_energy_experiment.dart';

/// Owner-scoped experimental results and prospective predictions. Native
/// receipts are obtained after a flushed file replacement. Nothing is uploaded
/// or applied to the normal Energy score.
class SleepEnergyStudyService {
  SleepEnergyStudyService({
    required this.store,
    required this.clock,
    this.onChanged,
  });

  static const schemaVersion = 'tonyo-sleep-energy-study-v1';
  static const maximumPredictions = 730;
  final Ai1CaptureStore store;
  final DateTime Function() clock;
  final void Function()? onChanged;
  String? owner;
  bool available = false;
  bool loaded = false;
  bool loggingEnabled = false;
  String? status;
  SleepEnergyRun? run;
  List<SleepEnergyPrediction> _predictions = [];
  List<SleepEnergyPrediction> get predictions =>
      List.unmodifiable(_predictions);
  DateTime? _lastReceipt;
  bool _needsPersistence = false;
  Future<void>? _queue;
  int _generation = 0;
  int _loggingRequest = 0;
  int _busy = 0;
  bool get busy => _busy > 0;
  final Set<String> _pendingErasure = {};

  static String storageOwner(String owner) => 'sleep-energy:$owner';

  void unload() {
    _generation++;
    _loggingRequest++;
    owner = null;
    available = false;
    loaded = false;
    loggingEnabled = false;
    run = null;
    _predictions = [];
    _lastReceipt = null;
    _needsPersistence = false;
    status = null;
  }

  bool _current(String expectedOwner, int generation) =>
      owner == expectedOwner && generation == _generation;

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final previous = _queue;
    _busy++;
    onChanged?.call();
    final task = (previous ?? Future<void>.value()).then((_) => operation());
    final tail = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _queue = tail;
    return task.whenComplete(() {
      _busy--;
      if (identical(_queue, tail)) _queue = null;
      onChanged?.call();
    });
  }

  Future<void> _retryErasures() async {
    for (final key in _pendingErasure.toList()) {
      await store.clear(storageOwner(key));
      _pendingErasure.remove(key);
    }
  }

  Future<void> load(String requestedOwner) async {
    if (owner == requestedOwner && loaded) return;
    final generation = ++_generation;
    owner = requestedOwner;
    loaded = false;
    loggingEnabled = false;
    run = null;
    _predictions = [];
    _lastReceipt = null;
    _needsPersistence = false;
    status = null;
    await _serialized(() async {
      try {
        await _retryErasures();
        final supported = await store.isAvailable();
        if (!_current(requestedOwner, generation)) return;
        available = supported;
        if (!supported) {
          loaded = true;
          status =
              'Saved experiments and prediction logging are available on iPhone. You can still inspect your paired days here.';
          return;
        }
        final raw = await store.read(storageOwner(requestedOwner));
        if (!_current(requestedOwner, generation)) return;
        if (raw != null) _restore(raw, requestedOwner);
        loaded = true;
      } on Object {
        if (!_current(requestedOwner, generation)) return;
        available = false;
        loaded = false;
        loggingEnabled = false;
        run = null;
        _predictions = [];
        status =
            'Could not read experiment history. Your ordinary records are unchanged. Retry or remove experiment history.';
      }
    });
  }

  Map<String, dynamic> _snapshot({
    SleepEnergyRun? replacementRun,
    bool replaceRun = false,
    List<SleepEnergyPrediction>? predictions,
    bool? enabled,
    DateTime? lastReceipt,
  }) => {
    'schemaVersion': schemaVersion,
    'owner': owner,
    'loggingEnabled': enabled ?? loggingEnabled,
    'run': (replaceRun ? replacementRun : run)?.toJson(),
    'predictions': (predictions ?? _predictions)
        .map((p) => p.toJson())
        .toList(),
    'lastReceiptAt': (lastReceipt ?? _lastReceipt)?.toUtc().toIso8601String(),
  };

  void _restore(String raw, String expectedOwner) {
    if (utf8.encode(raw).length > ai1CaptureMaximumBytes) {
      throw const FormatException(
        'Experiment history exceeds the storage limit.',
      );
    }
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value['schemaVersion'] != schemaVersion ||
        value['owner'] != expectedOwner ||
        value['loggingEnabled'] is! bool ||
        value['predictions'] is! List) {
      throw const FormatException('Incompatible experiment history.');
    }
    final rows = value['predictions'] as List;
    if (rows.length > maximumPredictions) {
      throw const FormatException('Too many experiment predictions.');
    }
    final predictions = rows
        .map(
          (p) => SleepEnergyPrediction.fromJson(
            Map<String, dynamic>.from(p as Map),
          ),
        )
        .toList();
    if (predictions.map((p) => p.id).toSet().length != predictions.length ||
        predictions
                .map((p) => jsonEncode([p.localDate, p.cohortKey]))
                .toSet()
                .length !=
            predictions.length) {
      throw const FormatException('Duplicate experiment predictions.');
    }
    final receipt = value['lastReceiptAt'];
    if (receipt != null) {
      if (receipt is! String) {
        throw const FormatException('Invalid save receipt.');
      }
      _lastReceipt = DateTime.parse(receipt).toUtc();
      if (_lastReceipt!.difference(clock().toUtc()) >
          const Duration(milliseconds: 2)) {
        throw const FormatException('Clock precedes the last experiment save.');
      }
    }
    run = value['run'] == null
        ? null
        : SleepEnergyRun.fromJson(
            Map<String, dynamic>.from(value['run'] as Map),
          );
    _predictions = predictions;
    loggingEnabled = value['loggingEnabled'] as bool;
  }

  Future<DateTime> _write(String key, Map<String, dynamic> snapshot) async {
    final generation = _generation;
    try {
      final raw = jsonEncode(snapshot);
      if (utf8.encode(raw).length > ai1CaptureMaximumBytes) {
        throw StateError(
          'Experiment history is full. Export or remove it before logging more predictions.',
        );
      }
      final requestedAt = clock().toUtc();
      if (_lastReceipt != null &&
          _lastReceipt!.difference(requestedAt) >
              const Duration(milliseconds: 2)) {
        throw StateError(
          'The device clock moved backward. Prediction logging is paused.',
        );
      }
      final receipt = (await store.write(storageOwner(key), raw)).toUtc();
      if (receipt.isBefore(requestedAt) ||
          (_lastReceipt != null && receipt.isBefore(_lastReceipt!))) {
        throw StateError(
          'The device could not confirm the experiment save time.',
        );
      }
      if (_current(key, generation)) _needsPersistence = false;
      return receipt;
    } on Object {
      if (_current(key, generation)) _needsPersistence = true;
      rethrow;
    }
  }

  void _requireReady() {
    if (!available || !loaded || owner == null) {
      throw StateError(
        'Experiment storage is unavailable. Refresh this screen first.',
      );
    }
  }

  Future<void> saveRun(
    SleepEnergyRun value, {
    bool Function()? stillEligible,
  }) async {
    _requireReady();
    final key = owner!;
    final generation = _generation;
    await _serialized(() async {
      if (!_current(key, generation)) return;
      if (stillEligible != null && !stillEligible()) {
        status =
            'Training records changed. Review your paired days and train again.';
        return;
      }
      final snapshot = _snapshot(replacementRun: value, replaceRun: true);
      final receipt = await _write(key, snapshot);
      if (!_current(key, generation)) return;
      _lastReceipt = receipt;
      if (stillEligible != null && !stillEligible()) {
        // A source mutation may finish while the native write is pending.
        // Clear the obsolete fit before any new issuance can consult it.
        run = null;
        final clearReceipt = await _write(key, _snapshot());
        if (!_current(key, generation)) return;
        _lastReceipt = clearReceipt;
        status =
            'Training records changed during the save. Train again to use the current records.';
        return;
      }
      run = value;
      status = 'Experimental fit saved. It does not change your Energy score.';
    });
  }

  Future<void> setLogging(bool enabled) async {
    _requireReady();
    final key = owner!;
    final generation = _generation;
    final request = ++_loggingRequest;
    // Pause synchronously, but retain any already-written pending day. The
    // queued settings save must not discard an in-flight reservation.
    if (!enabled) loggingEnabled = false;
    await _serialized(() async {
      if (!_current(key, generation) || request != _loggingRequest) return;
      final receipt = await _write(key, _snapshot(enabled: enabled));
      if (!_current(key, generation) || request != _loggingRequest) return;
      loggingEnabled = enabled;
      _lastReceipt = receipt;
      status = enabled
          ? 'Future predictions will be saved while the app is open, before an Evening check-in is started.'
          : 'New prediction logging is paused. Saved results are retained.';
    });
  }

  /// A pending record is persisted first. A second snapshot records the native
  /// receipt from that write. A crash or cancellation leaves an unscored
  /// pending record; no receipt is invented on load or retry.
  Future<void> record(
    SleepEnergyPrediction draft, {
    required bool Function() stillEligible,
  }) async {
    _requireReady();
    if (draft.receiptAt != null ||
        draft.targetId != null ||
        draft.invalidatedAt != null) {
      throw ArgumentError('Only a new, unissued prediction can be recorded.');
    }
    final key = owner!;
    final generation = _generation;
    await _serialized(() async {
      if (!_current(key, generation) || !loggingEnabled || !stillEligible()) {
        return;
      }
      if (_predictions.any(
        (p) =>
            p.id == draft.id ||
            (p.localDate == draft.localDate && p.cohortKey == draft.cohortKey),
      )) {
        status =
            'A prediction was already recorded for this day and sleep source.';
        return;
      }
      if (_predictions.length >= maximumPredictions) {
        throw StateError(
          'Prediction history is full. Remove experiment history to start a new collection.',
        );
      }
      final pending = [..._predictions, draft];
      // The native replacement can succeed and then fail its directory flush.
      // Reserve the day before awaiting it, so any later settings/result write
      // retains that possibly persisted payload even without a receipt.
      _predictions = pending;
      final DateTime firstReceipt;
      try {
        firstReceipt = await _write(key, _snapshot(predictions: pending));
      } on Object {
        if (_current(key, generation)) {
          status =
              'Prediction save was not confirmed. This day remains unscored and will not be issued again.';
        }
        rethrow;
      }
      if (!_current(key, generation)) return;
      // Keep the pending day reserved even if a form opens or data changes
      // during the save. The day is never reissued after a failed capture.
      _lastReceipt = firstReceipt;
      if (!loggingEnabled || !stillEligible()) {
        status =
            'Prediction was interrupted before confirmation and will not be scored.';
        return;
      }
      final committed = draft.withReceipt(firstReceipt);
      final finalRows = [...pending.take(pending.length - 1), committed];
      final secondReceipt = await _write(
        key,
        _snapshot(predictions: finalRows, lastReceipt: firstReceipt),
      );
      if (!_current(key, generation)) return;
      // firstReceipt is the issuance boundary: the payload was already durable
      // and eligible then. An editor opening or logging pause during this
      // confirmation write cannot make that earlier issuance retroactive.
      // Later source changes are handled by permanent reconciliation.
      _predictions = finalRows;
      _lastReceipt = secondReceipt;
      status =
          'Prediction saved before your check-in. Its value stays hidden until you answer.';
    });
  }

  Future<void> reconcile({
    required SleepEnergyReadiness readiness,
    required Iterable<DailyCheckIn> checkIns,
    required Iterable<SignalReading> signals,
  }) => reconcileHistory(
    SleepEnergyHistory(checkIns: checkIns, signals: signals, asOf: clock()),
    readiness: readiness,
  );

  bool get needsReconciliation =>
      available &&
      loaded &&
      (_needsPersistence || run != null || _predictions.isNotEmpty);

  Future<void> reconcileHistory(
    SleepEnergyHistory history, {
    SleepEnergyReadiness? readiness,
  }) async {
    if (!available || !loaded || owner == null) return;
    final key = owner!;
    final generation = _generation;
    await _serialized(() async {
      if (!_current(key, generation)) return;
      final oldRun = run;
      final now = clock();
      final current = history.at(now);
      final retainedRun =
          oldRun != null &&
              !SleepEnergyExperiment.isRunCurrent(
                oldRun,
                readiness ?? current.readiness,
              )
          ? null
          : oldRun;
      final revised = current
          .evaluate(_predictions, now)
          .map((result) => result.prediction)
          .toList();
      // Evaluation returns existing immutable records until a result is sealed or
      // invalidated. A retained identity means the persisted row is unchanged.
      if (!_needsPersistence &&
          identical(oldRun, retainedRun) &&
          listEquals(revised, _predictions)) {
        return;
      }
      // Invalidations must stay in memory even if a native replacement fails;
      // a later successful save must not resurrect a deleted dependency.
      run = retainedRun;
      _predictions = revised;
      final receipt = await _write(
        key,
        _snapshot(
          replacementRun: retainedRun,
          replaceRun: true,
          predictions: revised,
        ),
      );
      if (!_current(key, generation)) return;
      _lastReceipt = receipt;
      if (oldRun != null && retainedRun == null) {
        status =
            'Saved training records changed. Train again before recording more predictions.';
      }
    });
  }

  /// Disconnecting Health retires Health-derived fits and issued predictions,
  /// including a record whose native write was already in progress.
  Future<void> invalidateHealthSource() async {
    if (!available || !loaded || owner == null) return;
    final key = owner!;
    final generation = _generation;
    ++_loggingRequest;
    loggingEnabled = false;
    await _serialized(() async {
      if (!_current(key, generation)) return;
      if (run?.fits.any((fit) => fit.sleepSource == 'healthKit') ?? false) {
        run = null;
      }
      _predictions = [
        for (final prediction in _predictions)
          prediction.source == 'healthKit'
              ? prediction.invalidate('health_source_disconnected', clock())
              : prediction,
      ];
      status =
          'Health-derived experiments have been retired and new prediction logging is paused.';
      final receipt = await _write(key, _snapshot());
      if (!_current(key, generation)) return;
      _lastReceipt = receipt;
    });
  }

  Future<void> clear(String requestedOwner) async {
    _pendingErasure.add(requestedOwner);
    if (owner == requestedOwner) unload();
    await _serialized(() async {
      await _retryErasures();
    });
  }
}
