part of 'app_controller.dart';

/// Retains immutable signal records. Check-in definitions may contain mutable
/// maps, so their serialized values still participate in each comparison.
class _SleepEnergyInputs {
  _SleepEnergyInputs(this.owner, this.checkInsJson, List<SignalReading> signals)
    : readings = signals
          .where((s) => s.type != SignalType.heartRate)
          .toList(growable: false);

  final String owner;
  final String checkInsJson;
  final List<SignalReading> readings;

  SleepEnergyHistory? _history;

  SleepEnergyHistory historyAt(List<DailyCheckIn> reports, DateTime now) {
    final cached = _history;
    if (cached != null && cached.covers(now)) return cached;
    return _history = SleepEnergyHistory(
      checkIns: reports,
      signals: readings,
      asOf: now,
    );
  }

  bool matches(
    String currentOwner,
    String currentCheckIns,
    List<SignalReading> signals,
  ) {
    if (owner != currentOwner || checkInsJson != currentCheckIns) return false;
    var i = 0;
    for (final signal in signals) {
      if (signal.type == SignalType.heartRate) continue;
      if (i == readings.length) return false;
      final previous = readings[i];
      if (!identical(signal, previous)) {
        if (!mapEquals(signal.toJson(), previous.toJson())) return false;
        readings[i] = signal;
      }
      i++;
    }
    return i == readings.length;
  }
}

/// Explicit local fits and optional future collection. This experiment never
/// supplies the production score, cloud model, or recommendation engine.
extension _SleepEnergyLearning on AppController {
  bool get _sleepEnergyHealthWithdrawn =>
      !healthAuthorized &&
      healthAuthorization == HealthAuthorizationState.revoked;

  _SleepEnergyInputs get _sleepEnergyInputs {
    final owner = _ai1Owner;
    final reports = jsonEncode(checkIns.map((r) => r.toJson()).toList());
    final cached = _sleepEnergyInputCache;
    if (cached != null && cached.matches(owner, reports, signals)) {
      return cached;
    }
    return _sleepEnergyInputCache = _SleepEnergyInputs(owner, reports, signals);
  }

  SleepEnergyReadiness _prepareSleepEnergy() {
    final now = _now();
    if (!sleepEnergyCanInspect) {
      return SleepEnergyExperiment.prepare(checkIns: [], signals: [], now: now);
    }
    return _sleepEnergyInputs.historyAt(checkIns, now).readiness;
  }

  List<SleepEnergyPredictionEvaluation> _sleepEnergyResults() {
    if (!sleepEnergyCanInspect || _sleepEnergyStudy.owner != _ai1Owner) {
      return [];
    }
    final predictions = _sleepEnergyStudy.predictions;
    if (predictions.isEmpty) return [];
    final now = _now();
    return _sleepEnergyInputs
        .historyAt(checkIns, now)
        .evaluate(
          predictions.map(
            (p) => _sleepEnergyHealthWithdrawn && p.source == 'healthKit'
                ? p.invalidate('health_source_disconnected', now)
                : p,
          ),
          now,
        );
  }

  Future<void> _eraseSleepEnergyForConsent() async {
    _sleepEnergyInputCache = null;
    final owner = _ai1Owner;
    final revision = _sessionRevision;
    if (_sleepEnergyConsentClearedOwner == owner) return;
    await _sleepEnergyStudy.clear(owner);
    if (owner == _ai1Owner && revision == _sessionRevision && !outcomeConsent) {
      _sleepEnergyConsentClearedOwner = owner;
    }
  }

  Future<void> _refreshSleepEnergy() async {
    if (_disposed || _sleepEnergyResetting || _isClearingTrackingData) {
      return;
    }
    final knownOwner =
        _sleepEnergyStudy.owner == _ai1Owner ||
        (cloudUid != null && _privacyOwnerUid == cloudUid) ||
        (!cloudEnabled && !isSignedOut);
    if (!outcomeConsent && (_canProcessData || (isReady && knownOwner))) {
      try {
        await _eraseSleepEnergyForConsent();
      } on Object {
        _sleepEnergyError =
            'Could not remove experiment history. Retry after reopening Tonyo.';
      }
      return;
    }
    if (!_canProcessData || !outcomeConsent) return;
    final revision = _sessionRevision;
    final owner = _ai1Owner;
    bool current() =>
        !_disposed &&
        sleepEnergyCanInspect &&
        revision == _sessionRevision &&
        owner == _ai1Owner;
    try {
      _sleepEnergyConsentClearedOwner = null;
      await _sleepEnergyStudy.load(owner);
      if (!current()) return;
      if (_sleepEnergyHealthWithdrawn &&
          ((_sleepEnergyStudy.run?.fits.any(
                    (f) => f.sleepSource == 'healthKit',
                  ) ??
                  false) ||
              _sleepEnergyStudy.predictions.any(
                (p) => p.source == 'healthKit' && p.invalidatedAt == null,
              ))) {
        await _sleepEnergyStudy.invalidateHealthSource();
        if (!current()) return;
      }
      if (_sleepEnergyStudy.needsReconciliation) {
        final inputs = _sleepEnergyInputs;
        await _sleepEnergyStudy.reconcileHistory(
          inputs.historyAt(checkIns, _now()),
        );
        if (!current()) return;
        // An edit can finish while the native write is pending.
        if (inputs != _sleepEnergyInputs) _sleepEnergyRefreshAgain = true;
      }
      _sleepEnergyError = null;
    } on Object {
      if (current()) {
        _sleepEnergyError =
            'Could not update experiment history. Refresh before training or recording predictions.';
      }
    }
    if (current()) notifyListeners();
  }

  void _scheduleSleepEnergyRefresh() {
    if (_disposed) return;
    _sleepEnergyRefreshAgain = true;
    if (_sleepEnergyRefreshing) return;
    _sleepEnergyRefreshing = true;
    unawaited(() async {
      try {
        while (_sleepEnergyRefreshAgain && !_disposed) {
          _sleepEnergyRefreshAgain = false;
          await _refreshSleepEnergy();
          if (_appInForeground &&
              initialRefreshComplete &&
              !isPrivacyBusy &&
              sleepEnergyLoggingEnabled &&
              _sleepEnergyError == null &&
              _sleepEnergyCheckInEditors == 0 &&
              !_deviceSaveFailed &&
              _localWriteQueue == null) {
            await _recordSleepEnergy(automatic: true);
          }
        }
      } on Object {
        if (!_disposed) {
          _sleepEnergyError =
              'Prediction was not confirmed. Open the experiment to review its status.';
          notifyListeners();
        }
      } finally {
        _sleepEnergyRefreshing = false;
      }
    }());
  }

  void _requireSleepEnergyReady() {
    _requirePrivacy();
    if (!outcomeConsent ||
        !sleepEnergyAvailable ||
        isPrivacyBusy ||
        _deviceSaveFailed ||
        _sleepEnergyError != null) {
      throw StateError(
        'Finish privacy setup and refresh saved experiment data first.',
      );
    }
  }

  Future<void> _trainSleepEnergy() async {
    final ensureCurrent = _beginMutation();
    await _localWriteQueue;
    ensureCurrent();
    await _refreshSleepEnergy();
    ensureCurrent();
    _requireSleepEnergyReady();
    final readiness = sleepEnergyReadiness;
    if (!readiness.canTrain) {
      throw StateError(
        'There are not enough compatible paired days to fit an experimental model yet.',
      );
    }
    final owner = _ai1Owner;
    final revision = _sessionRevision;
    final key = _sleepEnergyInputs;
    final run = SleepEnergyExperiment.train(readiness, trainedAt: _now());
    if (_sleepEnergyHealthWithdrawn &&
        run.fits.any((f) => f.sleepSource == 'healthKit')) {
      throw StateError(
        'Reconnect Apple Health before training with its sleep records.',
      );
    }
    await _sleepEnergyStudy.saveRun(
      run,
      stillEligible: () =>
          sleepEnergyCanInspect &&
          owner == _ai1Owner &&
          revision == _sessionRevision &&
          key == _sleepEnergyInputs,
    );
    ensureCurrent();
    await _refreshSleepEnergy();
    notifyListeners();
  }

  Future<void> _setSleepEnergyLogging(bool value) async {
    final revision = _sessionRevision;
    final owner = _ai1Owner;
    // Disabling pauses an in-flight capture immediately, before queued I/O.
    if (!value && sleepEnergyAvailable) {
      await _sleepEnergyStudy.setLogging(false);
      notifyListeners();
      return;
    }
    await _refreshSleepEnergy();
    if (revision != _sessionRevision || owner != _ai1Owner) {
      throw StateError('Account changed. The previous action was stopped.');
    }
    _requireSleepEnergyReady();
    if (sleepEnergyRun == null || !sleepEnergyRun!.fits.any((f) => f.fitted)) {
      throw StateError(
        'Train an experimental model before enabling future predictions.',
      );
    }
    await _sleepEnergyStudy.setLogging(value);
    if (revision != _sessionRevision || owner != _ai1Owner) return;
    if (value) await _recordSleepEnergy();
    notifyListeners();
  }

  Future<void> _recordSleepEnergy({bool automatic = false}) async {
    final revision = _sessionRevision;
    final owner = _ai1Owner;
    if (!automatic) {
      await _localWriteQueue;
      if (revision != _sessionRevision || owner != _ai1Owner) return;
      await _refreshSleepEnergy();
      if (revision != _sessionRevision || owner != _ai1Owner) return;
    }
    _requireSleepEnergyReady();
    if (!sleepEnergyLoggingEnabled) return;
    if (_sleepEnergyCheckInEditors > 0) {
      _sleepEnergyPredictionMessage =
          'Prediction logging is paused while a check-in form is open.';
      notifyListeners();
      return;
    }
    final run = sleepEnergyRun;
    final timezone = deviceTimezoneIdentifier;
    if (run == null || timezone == null) {
      _sleepEnergyPredictionMessage =
          'A saved fit and known device timezone are required.';
      notifyListeners();
      return;
    }
    final editorRevision = _sleepEnergyEditorRevision;
    final key = _sleepEnergyInputs;
    final result = SleepEnergyExperiment.draftPrediction(
      run: run,
      readiness: sleepEnergyReadiness,
      checkIns: checkIns,
      signals: key.readings,
      now: _now(),
      timezone: timezone,
    );
    final draft = result.draft;
    if (draft == null) {
      _sleepEnergyPredictionMessage = switch (result.reason) {
        'evening_response_already_exists' =>
          'An Evening check-in already exists today. The next prediction must be for a future day.',
        'training_data_changed' =>
          'Training records changed. Train again first.',
        'ambiguous_model_cohort' =>
          'More than one compatible model matches today. No prediction was saved.',
        'training_time_in_future' =>
          'Check your device clock before logging predictions.',
        _ =>
          'Waiting for a future day with known sleep, the same timezone, and no Evening check-in yet.',
      };
      notifyListeners();
      return;
    }
    if (draft.source == 'healthKit' && !healthAuthorized) {
      _sleepEnergyPredictionMessage =
          'Reconnect Apple Health before recording predictions from Health sleep.';
      notifyListeners();
      return;
    }
    await _sleepEnergyStudy.record(
      draft,
      stillEligible: () =>
          sleepEnergyLoggingEnabled &&
          revision == _sessionRevision &&
          owner == _ai1Owner &&
          editorRevision == _sleepEnergyEditorRevision &&
          _sleepEnergyCheckInEditors == 0 &&
          deviceTimezoneIdentifier == timezone &&
          !_deviceSaveFailed &&
          _localWriteQueue == null &&
          !isPrivacyBusy &&
          (!automatic || _appInForeground) &&
          key == _sleepEnergyInputs,
    );
    if (revision == _sessionRevision && owner == _ai1Owner) {
      _sleepEnergyPredictionMessage =
          _sleepEnergyStudy.status ?? 'No prediction was confirmed.';
      notifyListeners();
    }
  }

  Future<void> _clearSleepEnergyHistory() async {
    _requirePrivacy();
    if (!outcomeConsent) throw StateError('Outcome learning is paused.');
    final owner = _ai1Owner;
    await _sleepEnergyStudy.clear(owner);
    _sleepEnergyError = null;
    _sleepEnergyPredictionMessage = 'Train an experimental model first.';
    await _refreshSleepEnergy();
    notifyListeners();
  }
}
