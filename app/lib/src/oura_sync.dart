part of 'app_controller.dart';

extension OuraSync on AppController {
  bool get ouraAvailable => _ouraService.supported && _ouraService.configured;
  bool get canConnectOura =>
      ouraAvailable &&
      cloudUid != null &&
      _canProcessData &&
      !isSignedOut &&
      !isPrivacyBusy &&
      !_isClearingTrackingData;
  int get ouraSignalCount =>
      signals.where((s) => s.source == SignalSource.oura).length;

  String _ouraPauseKey(String uid) =>
      '${AppController._ouraPauseKeyPrefix}${prepFingerprint({'owner': uid})}';

  bool _ouraCurrent(String uid, int revision, int generation) =>
      !_disposed &&
      !isSignedOut &&
      !_isSigningOut &&
      _canProcessData &&
      uid == cloudUid &&
      revision == _sessionRevision &&
      generation == _ouraGeneration;

  void _invalidateOuraWork() {
    _ouraGeneration++;
    ouraConnected = false;
    isOuraBusy = false;
    ouraDisconnectPending = false;
    ouraError = null;
    lastOuraSync = null;
    _lastOuraAttempt = null;
    unawaited(_ouraService.cancel());
  }

  Future<void> connectOura() async {
    if (!canConnectOura || isOuraBusy) return;
    final uid = cloudUid!;
    final revision = _sessionRevision;
    final generation = ++_ouraGeneration;
    bool current() => _ouraCurrent(uid, revision, generation);
    isOuraBusy = true;
    ouraError = null;
    notifyListeners();
    var connected = false;
    try {
      await _ouraService.connect(uid);
      if (!current()) return;
      final prefs = await SharedPreferences.getInstance();
      if (!current()) return;
      if (!await prefs.remove(_ouraPauseKey(uid)) ||
          !await prefs.remove('${_ouraPauseKey(uid)}_pending')) {
        throw StateError('Oura choice was not saved.');
      }
      if (!current()) return;
      ouraConnected = connected = true;
      ouraDisconnectPending = false;
      _lastOuraAttempt = null;
    } on Object catch (error) {
      if (current()) ouraError = _ouraMessage(error);
    } finally {
      if (current()) {
        isOuraBusy = false;
        notifyListeners();
      }
    }
    if (current() && connected) await syncOura();
  }

  /// Polling is bounded to once per fifteen minutes while the app is open.
  /// Reopening can import newly synced ring data; no background guarantee is made.
  Future<void> syncOura({bool automatic = false}) async {
    if (!canConnectOura || isOuraBusy || _isClearingTrackingData) return;
    if (automatic &&
        _lastOuraAttempt != null &&
        _now().difference(_lastOuraAttempt!) < const Duration(minutes: 15)) {
      return;
    }
    final uid = cloudUid!;
    final revision = _sessionRevision;
    final generation = _ouraGeneration;
    bool current() => _ouraCurrent(uid, revision, generation);
    isOuraBusy = true;
    _lastOuraAttempt = _now();
    if (!automatic) ouraError = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!current()) return;
      if (ouraDisconnectPending ||
          prefs.getBool('${_ouraPauseKey(uid)}_pending') == true ||
          prefs.getBool(_ouraPauseKey(uid)) == true) {
        // A failed disconnect remains paused across restarts; a foreground
        // retry removes credentials without collecting any further data.
        ouraConnected = false;
        if (ouraDisconnectPending ||
            prefs.getBool('${_ouraPauseKey(uid)}_pending') == true) {
          ouraDisconnectPending = true;
          if (!await prefs.setBool(_ouraPauseKey(uid), true)) {
            throw StateError('Could not save pause.');
          }
          if (!current()) return;
          await _ouraService.disconnect(uid);
          if (!current()) return;
          if (!await prefs.remove('${_ouraPauseKey(uid)}_pending')) {
            throw StateError('Could not save disconnect.');
          }
          if (!current()) return;
          ouraDisconnectPending = false;
          ouraError = null;
        }
        return;
      }
      final connected = await _ouraService.status(uid);
      if (!current()) return;
      ouraConnected = connected;
      if (!connected) return;
      final result = await _ouraService.sync(uid);
      if (!current()) return;
      final raw = result['sleep'];
      final syncedAt = DateTime.tryParse('${result['syncedAt']}');
      if (raw is! List || syncedAt == null || raw.any((row) => row is! Map)) {
        throw const OuraException('invalid_response');
      }
      final merged = OuraData.reconcile(
        signals,
        raw.map((row) => Map<String, dynamic>.from(row as Map)),
        syncedAt: syncedAt,
        startDay: '${result['startDate']}',
        endDay: '${result['endDate']}',
      );
      final before = {for (final row in signals) row.id: row.toJson()};
      final after = {for (final row in merged) row.id: row.toJson()};
      if (!sameSyncValue(before, after)) {
        signals = merged;
        await _commit();
        if (!current()) return;
      }
      lastOuraSync = syncedAt.toLocal();
      ouraError = null;
    } on Object catch (error) {
      if (!current()) return;
      if (error is OuraException &&
          {'not_connected', 'reconnect_required'}.contains(error.code)) {
        ouraConnected = false;
      }
      ouraError = _ouraMessage(error);
    } finally {
      if (current()) {
        isOuraBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> disconnectOura() async {
    final uid = cloudUid;
    if (uid == null || (isOuraBusy && ouraDisconnectPending)) return;
    _invalidateOuraWork();
    final revision = _sessionRevision;
    final generation = _ouraGeneration;
    bool current() =>
        !_disposed &&
        !isSignedOut &&
        !_isSigningOut &&
        uid == cloudUid &&
        revision == _sessionRevision &&
        generation == _ouraGeneration;
    isOuraBusy = true;
    ouraDisconnectPending = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!current()) return;
      if (!await prefs.setBool('${_ouraPauseKey(uid)}_pending', true) ||
          !await prefs.setBool(_ouraPauseKey(uid), true)) {
        throw StateError('Could not save disconnect.');
      }
      if (!current()) return;
      await _ouraService.disconnect(uid);
      if (!current()) return;
      if (!await prefs.remove('${_ouraPauseKey(uid)}_pending')) {
        throw StateError('Could not save disconnect.');
      }
      if (!current()) return;
      ouraDisconnectPending = false;
      // Disconnect stops future collection. Existing imported observations
      // remain ordinary user data and can be cleared with tracking history.
      ouraError = null;
    } on Object {
      if (current()) {
        ouraError = 'Oura sync is paused. Retry disconnect to finish.';
      }
    } finally {
      if (current()) {
        isOuraBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _pauseOuraForClear() async {
    final uid = cloudUid;
    if (uid == null || !_ouraService.configured) return;
    final revision = _sessionRevision;
    final prefs = await SharedPreferences.getInstance();
    if (uid != cloudUid || revision != _sessionRevision) return;
    if (!await prefs.setBool('${_ouraPauseKey(uid)}_pending', true) ||
        !await prefs.setBool(_ouraPauseKey(uid), true)) {
      throw StateError('Could not pause Oura.');
    }
    if (uid != cloudUid || revision != _sessionRevision) return;
    try {
      await _ouraService.disconnect(uid);
      if (uid == cloudUid && revision == _sessionRevision) {
        await prefs.remove('${_ouraPauseKey(uid)}_pending');
      }
    } on Object {
      /* A later resume retries without importing. */
    }
  }

  String _ouraMessage(Object error) => error is OuraException
      ? error.message
      : 'Oura could not finish syncing. Please retry.';
}
