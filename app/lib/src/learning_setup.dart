part of 'app_controller.dart';

/// Remembers the first-run offer on this device, separately for each account.
/// This receipt suppresses prompts; it never restores or grants feature consent.
extension LearningSetup on AppController {
  bool get learningSetupAvailable =>
      isReady && onboardingComplete && _canProcessData && ai1CaptureAvailable;

  String get _learningSetupKey =>
      '${AppController._learningSetupKeyPrefix}${prepFingerprint({'owner': _ai1Owner})}';

  Future<bool> shouldOfferLearningSetup() async {
    if (!learningSetupAvailable) return false;
    final ensureCurrent = _beginMutation();
    final preferences = await SharedPreferences.getInstance();
    ensureCurrent();
    final saved = preferences.getString(_learningSetupKey);
    if (saved != null) {
      try {
        final receipt = jsonDecode(saved);
        if (receipt is Map &&
            receipt['version'] == 1 &&
            const {
              'enabled',
              'declined',
              'already_enabled',
            }.contains(receipt['choice'])) {
          return false;
        }
      } on FormatException {
        // An unreadable prompt receipt cannot establish a prior choice.
      }
    }
    if (ai1CaptureEnabled && outcomeConsent) {
      await _saveLearningSetupChoice(
        preferences,
        'already_enabled',
        ensureCurrent,
      );
      return false;
    }
    return true;
  }

  Future<void> completeLearningSetup({required bool enable}) async {
    if (!learningSetupAvailable || _learningSetupSaving || isPrivacyBusy) {
      throw StateError('Learning setup is unavailable or still being saved.');
    }
    final ensureCurrent = _beginMutation();
    _learningSetupSaving = true;
    try {
      if (enable) {
        if (!ai1CaptureEnabled) await setAi1CaptureEnabled(true);
        ensureCurrent();
        if (!ai1CaptureEnabled) {
          throw StateError('Local study history was not enabled.');
        }
        if (!outcomeConsent) await setOutcomeConsent(true);
        ensureCurrent();
        if (!outcomeConsent) {
          throw StateError('Outcome learning was not enabled.');
        }
      }
      final preferences = await SharedPreferences.getInstance();
      ensureCurrent();
      await _saveLearningSetupChoice(
        preferences,
        enable ? 'enabled' : 'declined',
        ensureCurrent,
      );
    } finally {
      _learningSetupSaving = false;
    }
  }

  Future<void> _saveLearningSetupChoice(
    SharedPreferences preferences,
    String choice,
    void Function() ensureCurrent,
  ) async {
    ensureCurrent();
    try {
      final saved = await preferences.setString(
        _learningSetupKey,
        jsonEncode({
          'version': 1,
          'choice': choice,
          'decidedAt': _now().toUtc().toIso8601String(),
        }),
      );
      ensureCurrent();
      if (!saved) throw StateError('Learning setup choice was not saved.');
    } on Object {
      // SharedPreferences updates its cache before the platform confirms a write.
      try {
        await preferences.reload();
      } on Object {
        /* keep the save error */
      }
      rethrow;
    }
  }
}
