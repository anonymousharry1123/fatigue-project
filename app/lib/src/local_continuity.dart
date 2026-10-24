part of 'app_controller.dart';

extension _LocalContinuity on AppController {
  bool _isTransientConnectionFailure(Object error) =>
      error is TimeoutException ||
      (error is FirebaseException &&
          const {
            'unavailable',
            'deadline-exceeded',
            'network-request-failed',
            'network-error',
          }.contains(error.code.toLowerCase()));

  void _recordOfflineVerification() {
    if (!_cloudPrivacyVerified ||
        deletionPending ||
        _privacyConsent?.validAt(_now()) != true ||
        _privacyConsent?.ageBand != PrivacyAgeBand.adult) {
      _offlineAccessLease = null;
    } else if (cloudUid != null &&
        _claimsVerifiedOwner == cloudUid &&
        _claimsVerifiedRevision == _sessionRevision) {
      _offlineAccessLease = OfflineAccessLease(
        uid: cloudUid!,
        verifiedAt: _now(),
        consent: _privacyConsent!,
      );
    }
    _scheduleOfflineExpiry();
  }

  void _scheduleOfflineExpiry() {
    _offlineExpiryTimer?.cancel();
    _offlineExpiryTimer = null;
    if (!_appInForeground ||
        !_offlineLocalAccess ||
        _offlineAccessLease == null) {
      return;
    }
    final delay = _offlineAccessLease!.expiresAt.difference(_now());
    final revision = _sessionRevision;
    final uid = cloudUid;
    _offlineExpiryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () async {
        if (_disposed ||
            revision != _sessionRevision ||
            uid != cloudUid ||
            !_offlineLocalAccess ||
            isUsingOfflineData) {
          return;
        }
        _offlineLocalAccess = false;
        _invalidateHealthWork();
        _unloadAi1Capture();
        _energyModelService.unload();
        await _disableContinuousHealthUpdates();
        if (_disposed || revision != _sessionRevision || uid != cloudUid) {
          return;
        }
        healthBackgroundRefreshEnabled = false;
        privacyOperationError =
            'Offline access expired. Reconnect to verify your account; saved records are kept on this iPhone.';
        notifyListeners();
      },
    );
  }
}
