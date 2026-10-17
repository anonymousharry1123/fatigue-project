import 'local_day.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activity_log_logic.dart';
import 'activity_sync_logic.dart';
import 'ai1_capture.dart';
import 'ai1_capture_store.dart';
import 'ai1_protocol.dart';
import 'check_in_logic.dart';
import 'cloud_repository.dart';
import 'cloud_schema.dart';
import 'cloud_sync.dart';
import 'continuous_refresh_logic.dart';
import 'daily_history_logic.dart';
import 'daily_plan_logic.dart';
import 'demo_data.dart';
import 'device_timezone_service.dart';
import 'fatigue_engine.dart';
import 'energy_model_repository.dart';
import 'energy_model_service.dart';
import 'energy_model_summary.dart';
import 'health_service.dart';
import 'heart_sync_logic.dart';
import 'insights_logic.dart';
import 'language_preference.dart';
import 'l10n/app_localizations.dart';
import 'check_in_measurement.dart';
import 'ml_prep_models.dart';
import 'ml_prep_builder.dart';
import 'ml_prep_service.dart';
import 'models.dart';
import 'model_transparency_state.dart';
import 'notification_logic.dart';
import 'notification_service.dart';
import 'personal_baseline_logic.dart';
import 'privacy_consent.dart';
import 'reaction_test_logic.dart';
import 'recommendation_feedback_logic.dart';
import 'screen_time_service.dart';
import 'schedule_logic.dart';
import 'sleep_sync_logic.dart';
import 'today_dashboard_logic.dart';

part 'backup_restore.dart';
part 'sync_conflict_resolution.dart';
part 'coach_sync.dart';

class AppController extends ChangeNotifier {
  AppController({
    HealthService? healthService,
    ScreenTimeService? screenTimeService,
    AccountAuth? accountAuth,
    NotificationService? notificationService,
    DeviceTimezoneService? deviceTimezoneService,
    DateTime Function()? clock,
    PrepDataSource? prepDataSource,
    EnergyModelStore? energyModelStore,
    Ai1CaptureStore? captureStore,
    this.energyModelMetadataWriter,
    this.cloudRepository,
    PrivacyConsent? initialPrivacyConsent,
  }) : _healthService = healthService ?? const HealthService(),
       _screenTimeService = screenTimeService ?? const ScreenTimeService(),
       _accountAuth = accountAuth ?? const LocalOnlyAccountAuth(),
       _notificationService = notificationService ?? LocalNotificationService(),
       _deviceTimezoneService =
           deviceTimezoneService ?? DeviceTimezoneService(),
       _now = clock ?? DateTime.now,
       _energyModelStore =
           energyModelStore ?? SharedPreferencesEnergyModelStore(),
       _ai1CaptureStore = captureStore ?? const MethodChannelAi1CaptureStore(),
       _mlPrepService = prepDataSource == null
           ? null
           : MlPrepService(
               source: prepDataSource,
               cache: SharedPreferencesPrepCache(),
             ) {
    _privacyConsent = initialPrivacyConsent;
    _privacyOwnerUid = _accountAuth.currentSession?.uid;
    _cloudPrivacyVerified = initialPrivacyConsent != null;
  }

  static const _storageKey = 'tonyo_state_v1';
  // Device navigation state, deliberately separate from profile/cloud data.
  static const _signedOutKey = 'tonyo_signed_out_v1';
  static const _deletionKey = 'tonyo_privacy_deletion_v1';
  static const _deviceRecoveryKeyPrefix = 'tonyo_device_recovery_v1_';
  static const _prepWindowKeyPrefix = 'tonyo_ml_prep_window_v1_';
  static const forecastDayCount = 7;
  static const forecastFreshnessWindow = Duration(hours: 12);
  static const outcomeHistoryWindow = Duration(days: 90);
  final HealthService _healthService;
  final ScreenTimeService _screenTimeService;
  final AccountAuth _accountAuth;
  final NotificationService _notificationService;
  final DeviceTimezoneService _deviceTimezoneService;
  String? get deviceTimezoneIdentifier => _deviceTimezoneService.identifier;
  String get deviceTimezoneLabel => _deviceTimezoneService.label;
  String? _lastLocalDay;
  bool _localClockChanged = false;
  final DateTime Function() _now;
  final CloudRepository? cloudRepository;
  final MlPrepService? _mlPrepService;
  final EnergyModelStore _energyModelStore;
  final Ai1CaptureStore _ai1CaptureStore;
  late final _ai1Capture = Ai1CaptureJournal(
    store: _ai1CaptureStore,
    clock: _now,
  );
  int _ai1CaptureGeneration = 0;
  String get _ai1Owner => cloudUid == null ? 'local' : 'cloud:$cloudUid';
  bool get ai1CaptureAvailable => _ai1Capture.available;
  bool get ai1CaptureEnabled =>
      _canProcessData && _ai1Capture.owner == _ai1Owner && _ai1Capture.enabled;
  bool get ai1CaptureBusy => _ai1Capture.busy;
  String? get ai1CaptureError => _ai1Capture.error;
  int get ai1CapturedRevisionCount =>
      _canProcessData && _ai1Capture.owner == _ai1Owner
      ? _ai1Capture.revisionCount
      : 0;

  /// Optional device history only. This never enables model training.
  Future<void> setAi1CaptureEnabled(bool value) async {
    final void Function() ensureCurrent;
    if (value) {
      ensureCurrent = _beginMutation();
    } else {
      // Erasure remains available when collection awaits privacy review.
      final revision = _sessionRevision;
      final uid = cloudUid;
      void checkSession() {
        if (isSignedOut ||
            _isSigningOut ||
            isDeletingAccount ||
            (cloudEnabled && !isCloudAuthenticated) ||
            revision != _sessionRevision ||
            uid != cloudUid) {
          throw StateError('Sign in and finish the account operation first.');
        }
      }

      checkSession();
      ensureCurrent = checkSession;
    }
    final owner = _ai1Owner;
    _ai1CaptureGeneration++;
    final task = value
        ? _ai1Capture.start(owner)
        : _ai1Capture.stopAndClear(owner);
    notifyListeners();
    try {
      await task;
      ensureCurrent();
    } finally {
      notifyListeners();
    }
  }

  Future<void> _loadAi1Capture() async {
    if (!_canProcessData) return;
    final revision = _sessionRevision;
    final generation = _ai1CaptureGeneration;
    final owner = _ai1Owner;
    if (_ai1Capture.owner != owner) await _ai1Capture.load(owner);
    if (revision != _sessionRevision ||
        owner != _ai1Owner ||
        !_canProcessData) {
      // A later sign-in may already be loading another owner's journal.
      if (generation == _ai1CaptureGeneration) _unloadAi1Capture();
      return;
    }
    await _reconcileAi1Capture(_json());
  }

  void _unloadAi1Capture() {
    _ai1CaptureGeneration++;
    _ai1Capture.unload();
  }

  _Ai1CaptureIntent? _captureIntent(
    Ai1CaptureObservation Function() createObservation,
    int? generation,
  ) {
    if (generation == null ||
        generation != _ai1CaptureGeneration ||
        !ai1CaptureEnabled) {
      return null;
    }
    try {
      final observation = createObservation();
      return _Ai1CaptureIntent(
        observation: observation,
        generation: generation,
        sourceSnapshot: _ai1SourceSnapshot(_json(), observation),
      );
    } on FormatException {
      _ai1CaptureGeneration++;
      _ai1Capture.pauseAfterCaptureFailure();
      return null;
    }
  }

  String _ai1SourceSnapshot(
    Map<String, Object?> state,
    Ai1CaptureObservation observation,
  ) => ai1CanonicalJson(
    (state[observation.collection == 'checkIns' ? 'checkIns' : 'signals']
            as List)
        .whereType<Map>()
        .where(
          (row) => observation.collection == 'checkIns'
              ? row['id'] == observation.sourceId
              : row['groupId'] == observation.sourceId,
        )
        .toList(),
  );

  Future<void> _purgeAi1Source(String collection, String sourceId) async {
    _ai1CaptureGeneration++;
    if (_ai1Capture.owner != _ai1Owner) return;
    await _ai1Capture.deleteSource(
      owner: _ai1Owner,
      collection: collection,
      sourceId: sourceId,
    );
  }

  /// Reconciliation never creates history for cloud, backups or legacy rows.
  Future<void> _reconcileAi1Capture(Map<String, Object?> state) async {
    if (!_canProcessData || _ai1Capture.owner != _ai1Owner) return;
    final tracked = <String, Ai1CaptureEntry>{};
    for (final entry in _ai1Capture.entries) {
      final key = Ai1CaptureObservation.sourceKey(
        entry.collection,
        entry.sourceId,
      );
      if ((tracked[key]?.revision ?? 0) < entry.revision) tracked[key] = entry;
    }
    if (tracked.isEmpty) return;
    Ai1CaptureObservation? validObservation(
      Ai1CaptureObservation Function() create,
    ) {
      try {
        return create();
      } on FormatException {
        // A changed, malformed remote row has no matching captured evidence.
        // Its history is purged below without blocking the ordinary row save.
        return null;
      }
    }

    final fingerprints = <String, String>{};
    final currentSignals = (state['signals'] as List)
        .whereType<Map>()
        .map((row) => SignalReading.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    final currentCheckIns = (state['checkIns'] as List)
        .whereType<Map>()
        .map((row) => DailyCheckIn.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    for (final trackedEntry in tracked.entries) {
      final entry = trackedEntry.value;
      Ai1CaptureObservation? observation;
      if (entry.collection == 'checkIns') {
        final matching = currentCheckIns.where(
          (row) => row.id == entry.sourceId && row.isValidResearchResponse,
        );
        final heading = entry.data['sharedHeading'];
        if (matching.length == 1 && heading is String) {
          observation = validObservation(
            () => Ai1CaptureObservation.selfReport(
              checkIn: matching.single,
              sharedHeading: heading,
              originalLocal: false,
            ),
          );
        }
      } else if (entry.collection == 'sleepLogs') {
        final group = currentSignals.where(
          (row) =>
              row.groupId == entry.sourceId &&
              row.source == SignalSource.manual,
        );
        final durations = group.where(
          (row) => row.type == SignalType.sleep || row.type == SignalType.nap,
        );
        if (durations.length == 1) {
          final duration = durations.single;
          final isNap = duration.type == SignalType.nap;
          final starts = group.where((row) => row.type == SignalType.bedtime);
          DateTime? start = starts.length == 1 ? starts.single.timestamp : null;
          // Naps lack an independent start signal. Reuse the retained actual
          // start for comparison only when the saved end and duration agree.
          if (isNap &&
              entry.data['endedAt'] ==
                  duration.timestamp.toUtc().toIso8601String() &&
              entry.data['durationHours'] == duration.value) {
            start = DateTime.tryParse(entry.data['startedAt'] as String? ?? '');
          }
          if (start != null) {
            observation = validObservation(
              () => Ai1CaptureObservation.manualSleep(
                sourceId: entry.sourceId,
                startedAt: start!,
                endedAt: duration.timestamp,
                durationHours: duration.value,
                isNap: isNap,
                originalLocal: false,
              ),
            );
          }
        }
      }
      if (observation != null) {
        fingerprints[trackedEntry.key] = observation.fingerprint;
      }
    }
    await _ai1Capture.reconcile(
      owner: _ai1Owner,
      currentFingerprints: fingerprints,
    );
  }

  final EnergyModelMetadataWriter? energyModelMetadataWriter;
  late final _energyModelService = EnergyModelService(
    store: _energyModelStore,
    writer: energyModelMetadataWriter,
    currentUid: () => cloudUid,
    consentAllowed: () => outcomeConsent && _canProcessData,
    now: _now,
  );
  PrepRun? _preparedModelRun;
  bool get isRefreshingPersonalizedModel => _energyModelService.busy;
  String get personalizedModelStatus => _energyModelService.status;
  String? get personalizedModelBlocker =>
      modelPreparationBlocker ??
      (!outcomeConsent
          ? 'Enable Outcome learning before training your Energy model.'
          : energyModelMetadataWriter == null
          ? 'Model metadata sync is not configured in this build.'
          : null);

  Future<void> refreshPersonalizedModel({required PrepWindow window}) async {
    if (isRefreshingPersonalizedModel) return;
    final blocker = personalizedModelBlocker;
    if (blocker != null) throw StateError(blocker);
    final run = _preparedModelRun;
    if (run == null ||
        run.snapshot.uid != cloudUid ||
        canonicalPrepJson(run.snapshot.window.toJson()) !=
            canonicalPrepJson(window.toJson())) {
      throw StateError(
        'Prepare the selected 30-day snapshot before refreshing the model.',
      );
    }
    final task = _energyModelService.refresh(run);
    notifyListeners();
    try {
      await task;
      // Local recomputation only. Ordinary score refresh owns the next daily
      // snapshot write; fitting adds no score queries or broad account writes.
      if (!isSignedOut) {
        _scoreSnapshot = _personalizeEnergy(
          (_scoreSnapshot ??
                  FatigueEngine.score(
                    signals: signals,
                    checkIns: checkIns,
                    now: _now(),
                  ))
              .withoutPersonalization(),
          signals,
          checkIns,
          _now(),
        );
      }
    } finally {
      notifyListeners();
    }
  }

  int _modelPreparationRevision = 0;
  int get modelPreparationRevision => _modelPreparationRevision;
  PrepWindow? _lastModelPreparationWindow;
  String? _lastModelPreparationWindowUid;
  PrepWindow? get lastModelPreparationWindow =>
      cloudUid == _lastModelPreparationWindowUid
      ? _lastModelPreparationWindow
      : null;

  bool isReady = false;
  bool onboardingComplete = false;
  bool isSignedOut = false;
  bool _isSigningOut = false;
  int _sessionRevision = 0;
  int get sessionRevision => _sessionRevision;
  InputSyncSnapshot? _syncBaseline;
  String? _syncOwnerUid;
  Future<void>? _pendingCloudPush;
  bool cloudSyncConflict = false;
  CloudSyncFailureKind? cloudSyncFailureKind;
  DateTime? _lastCloudSyncAt;
  String? _lastCloudSyncOwnerUid;
  DateTime? get lastCloudSyncAt =>
      cloudUid == _lastCloudSyncOwnerUid ? _lastCloudSyncAt : null;
  Timer? _cloudRetryTimer;
  Duration _cloudRetryDelay = const Duration(seconds: 5);
  bool _appInForeground = false;
  bool _disposed = false;
  Future<void>? _pendingSyncCycle;
  final Map<Object, ({String? uid, int revision})> _cloudSyncActivities = {};
  String? _coachSyncOwnerUid;
  final Map<String, _PendingRecommendationAction> _pendingCoachWrites = {};
  final Map<String, RiskAlert> _pendingAlertWrites = {};
  Future<void>? _pendingCoachPush;
  Future<void>? _pendingGuidanceWrite;
  int _coachSyncGeneration = 0;
  bool get hasPendingCoachChanges =>
      cloudUid != null &&
      cloudUid == _coachSyncOwnerUid &&
      (_pendingCoachWrites.isNotEmpty || _pendingAlertWrites.isNotEmpty);
  bool get hasAnyPendingCloudChanges =>
      hasPendingCloudChanges ||
      hasPendingOutcomeChanges ||
      hasPendingCoachChanges;
  int get pendingCloudRecordCount {
    var count = 0;
    if (cloudUid != null &&
        _syncOwnerUid == cloudUid &&
        _syncBaseline != null) {
      final patch = InputSyncPatch(
        _syncBaseline!,
        InputSyncSnapshot.fromState(
          _cloudState(migrationVersion: localMigrationVersion),
        ),
      );
      count +=
          patch.signals.length +
          patch.checkIns.length +
          (patch.root.isEmpty ? 0 : 1);
    }
    if (hasPendingOutcomeChanges) count += _pendingOutcomeWrites.length;
    if (hasPendingCoachChanges) {
      count += _pendingCoachWrites.length + _pendingAlertWrites.length;
    }
    return count;
  }

  String get cloudSyncStatusMessage {
    if (isSignedOut || !isCloudAuthenticated) {
      return 'Sign in to sync this device.';
    }
    if (deletionPending || isDeletingAccount) {
      return 'Cloud sync is paused during account deletion.';
    }
    if (isCloudSyncing) return 'Syncing device changes…';
    if (cloudSyncConflict) {
      return 'Your edits are saved here. Review the changes from the other device.';
    }
    if (cloudSyncError != null) return cloudSyncError!;
    if (hasAnyPendingCloudChanges) {
      return '$pendingCloudRecordCount ${pendingCloudRecordCount == 1 ? "record" : "records"} saved on this device · waiting to sync';
    }
    if (!_cloudPrivacyVerified) {
      return 'Reconnect to verify account privacy and resume sync.';
    }
    return lastCloudSyncAt == null
        ? 'No pending device changes.'
        : 'All device changes are synced.';
  }

  @override
  void dispose() {
    _unloadAi1Capture();
    _disposed = true;
    _cloudSyncActivities.clear();
    isCloudSyncing = false;
    _appInForeground = false;
    _sessionRevision++;
    _invalidateHealthWork();
    _cloudRetryTimer?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    // Privacy/export operations can temporarily pause retries. Their final
    // state notification restarts pending work once the device is eligible.
    scheduleCloudRetry();
    super.notifyListeners();
  }

  /// The app owns foreground retry lifetime; headless controllers create no timers.
  void setAppForeground(bool foreground) {
    _appInForeground = foreground && !_disposed;
    if (!_appInForeground) {
      _cloudRetryTimer?.cancel();
      _cloudRetryTimer = null;
      return;
    }
    scheduleCloudRetry();
  }

  bool get hasPendingCloudChanges =>
      cloudUid != null &&
      _syncOwnerUid == cloudUid &&
      _syncBaseline != null &&
      !InputSyncPatch(
        _syncBaseline!,
        InputSyncSnapshot.fromState(
          _cloudState(migrationVersion: localMigrationVersion),
        ),
      ).isEmpty;
  PrivacyConsent? _privacyConsent;
  String? _privacyOwnerUid;
  bool _cloudPrivacyVerified = false;
  int _privacyRefreshGeneration = 0;
  String? _deletionOwner;
  String? _deletionStage;
  DateTime? outcomeConsentUpdatedAt;
  PrivacyConsent? get privacyConsent => _privacyConsent;
  bool get guardianConsentVerified =>
      _accountAuth.currentSession?.guardianConsentVerified ?? false;
  bool get deletionPending => _deletionOwner != null;
  bool isDeletingAccount = false;
  bool isExportingData = false;
  bool _isSavingPrivacy = false;
  bool get isPrivacyBusy =>
      isDeletingAccount || isExportingData || _isSavingPrivacy;
  String? privacyOperationError;
  String? get guardianConsentBlocker =>
      _privacyConsent?.guardianRequired == true && !guardianConsentVerified
      ? 'Guardian verification is required. This build cannot verify a guardian '
            'yet. New tracking and uploads stay paused; export and deletion '
            'remain available.'
      : null;
  bool get privacyFeaturesAllowed =>
      !deletionPending &&
      (!cloudEnabled || isCloudAuthenticated || !onboardingComplete) &&
      _privacyConsent?.validAt(_now()) == true &&
      guardianConsentBlocker == null &&
      (!isCloudAuthenticated ||
          (_cloudPrivacyVerified && _privacyOwnerUid == cloudUid));
  bool get privacyReviewRequired => !privacyFeaturesAllowed;
  bool get _canProcessData =>
      privacyFeaturesAllowed &&
      !isSignedOut &&
      !_isSigningOut &&
      !isDeletingAccount &&
      (!cloudEnabled || isCloudAuthenticated);

  void _requirePrivacy() {
    if (!_canProcessData) {
      throw StateError(
        deletionPending
            ? 'Account deletion is pending. Retry it in Privacy center.'
            : guardianConsentBlocker ??
                  'Review your privacy choices before continuing.',
      );
    }
  }

  void Function() _beginMutation() {
    _requirePrivacy();
    final revision = _sessionRevision;
    final uid = cloudUid;
    if (uid != null && (_syncBaseline == null || _syncOwnerUid != uid)) {
      _syncOwnerUid = uid;
      _syncBaseline = InputSyncSnapshot.fromState(
        _cloudState(migrationVersion: localMigrationVersion),
      );
    }
    return () {
      _requirePrivacy();
      if (revision != _sessionRevision || uid != cloudUid) {
        throw StateError('Account changed. The previous action was stopped.');
      }
    };
  }

  Future<void> acceptPrivacy({
    required PrivacyAgeBand ageBand,
    required PrivacyRegion region,
    required bool acknowledged,
  }) async {
    if (isPrivacyBusy || deletionPending) {
      throw StateError('Finish the current privacy operation first.');
    }
    if (!acknowledged) {
      throw ArgumentError('Please acknowledge the data use notice.');
    }
    final receipt = PrivacyConsent(
      ageBand: ageBand,
      region: region,
      acceptedAt: _now(),
    );
    if (_privacyConsent != null && !_privacyConsent!.sameIdentity(receipt)) {
      throw StateError(
        'Age band and region cannot be changed to bypass verification. Contact support for a correction.',
      );
    }
    if (receipt.guardianRequired && !guardianConsentVerified) {
      throw StateError(
        'Verified guardian setup is required before collecting personal information. It is not available in this build.',
      );
    }
    _isSavingPrivacy = true;
    _privacyRefreshGeneration++;
    privacyOperationError = null;
    notifyListeners();
    try {
      final uid = cloudUid;
      final saved = uid == null || cloudRepository == null
          ? receipt
          : await cloudRepository!.savePrivacyConsent(uid, receipt);
      if (uid != cloudUid || deletionPending) {
        throw StateError('Account changed. Retry privacy review.');
      }
      _privacyConsent = saved;
      _privacyOwnerUid = uid;
      _cloudPrivacyVerified = uid != null;
      // This notice never opts anyone into optional learning.
      outcomeConsent = false;
      _reconcileOutcomeSync();
      outcomeConsentUpdatedAt = saved.acceptedAt;
      await _discardPersonalizedModel();
      await _writeLocal();
      await _loadAi1Capture();
    } on Object {
      privacyOperationError =
          'Privacy choices were not saved. Check your connection and retry.';
      rethrow;
    } finally {
      _isSavingPrivacy = false;
      notifyListeners();
    }
    if (onboardingComplete && _canProcessData) {
      await handleAppResumed();
      await refreshScores();
    }
  }

  bool get canResumeLocalProfile =>
      isSignedOut && onboardingComplete && !cloudEnabled;
  bool notificationsEnabled = false;
  bool crashNotificationsEnabled = true;
  bool recoveryNotificationsEnabled = true;
  bool coachPlanNotificationsEnabled = false;
  bool outcomeConsent = false;
  bool healthAvailable = false;
  bool healthAuthorized = false;
  bool isHealthAuthorizing = false;
  bool isScreenTimeAuthorizing = false;
  bool isSyncing = false;
  bool isCloudSyncing = false;
  bool isEnergyScoreLoading = false;
  bool isForecastLoading = false;
  bool isGuidanceLoading = false;
  bool isNotificationSyncing = false;
  bool isInsightsLoading = false;
  bool isOutcomeLoading = false;
  DateTime? lastSync;
  DateTime? lastHealthSyncAttempt;
  DateTime? lastHealthChangeAt;
  HealthSyncStatus healthSyncStatus = HealthSyncStatus.idle;
  HealthRefreshReason? lastHealthRefreshReason;
  bool healthBackgroundRefreshEnabled = false;
  int _healthConnectionGeneration = 0;
  (int, int, String?)? _healthSyncContext;
  Future<HeartSyncMergeResult?>? _pendingHealthSync;
  bool _healthRefreshRequested = false;
  Future<void>? _healthObserverQueue;
  Future<void>? _pendingHealthObserverSetup;
  int lastHealthImportCount = 0;
  int lastHealthDuplicateCount = 0;
  int lastHealthRejectedCount = 0;
  int lastSleepImportCount = 0;
  int lastSleepDuplicateCount = 0;
  int lastSleepRejectedCount = 0;
  int lastSleepNightCount = 0;
  int lastSleepManualPreferenceCount = 0;
  int lastActivityImportCount = 0;
  int lastActivityDuplicateCount = 0;
  int lastActivityRejectedCount = 0;
  String? accountEmail;
  String? cloudSyncError;
  String? energyScoreError;
  String? forecastError;
  String? guidanceError;
  String? notificationError;
  String? insightsError;
  String? outcomeError;
  String? healthError;
  String? screenTimeError;
  String? healthSyncError;
  String? sleepSyncError;
  String? activitySyncError;
  HealthAuthorizationState healthAuthorization =
      HealthAuthorizationState.unavailable;
  ScreenTimeAuthorizationState screenTimeAuthorization =
      ScreenTimeAuthorizationState.unavailable;
  NotificationPermissionState notificationPermission =
      NotificationPermissionState.unknown;
  UserProfile profile = const UserProfile();
  String? _onboardingLanguagePreference;
  Future<void>? _languageWriteQueue;
  Future<void>? _localWriteQueue;
  String get effectiveLanguage => normalizeLanguagePreference(
    onboardingComplete && !isSignedOut
        ? profile.preferredLanguage
        : _onboardingLanguagePreference ?? defaultLanguagePreference,
  );

  /// The signup preview changes presentation before an account exists. The
  /// selected value is persisted only with the normally consented profile.
  void previewOnboardingLanguage(String value) {
    if (onboardingComplete && !isSignedOut) return;
    _onboardingLanguagePreference = normalizeLanguagePreference(value);
    notifyListeners();
  }

  List<SignalReading> signals = [];
  List<DailyCheckIn> checkIns = [];
  List<OutcomeRecord> _outcomes = [];
  String? _outcomeSyncOwnerUid;
  DateTime? _outcomeSyncConsentAt;
  final Map<String, OutcomeRecord?> _pendingOutcomeWrites = {};
  Future<void>? _pendingOutcomePush;
  int _outcomeSyncGeneration = 0;
  bool get hasPendingOutcomeChanges =>
      cloudUid != null &&
      _outcomeSyncOwnerUid == cloudUid &&
      _pendingOutcomeWrites.isNotEmpty;

  void _clearOutcomeSync() {
    _outcomeSyncGeneration++;
    _pendingOutcomeWrites.clear();
    _outcomeSyncOwnerUid = null;
    _outcomeSyncConsentAt = null;
  }

  bool _sameOutcomeConsentAt(DateTime? left, DateTime? right) => left == null
      ? right == null
      : right != null && left.isAtSameMomentAs(right);

  // A renewed consent receipt never grants permission to upload outcomes
  // collected under an earlier receipt. Explicit deletes remain safe to retry.
  void _reconcileOutcomeSync() {
    if (_outcomeSyncOwnerUid != null &&
        cloudUid != null &&
        _outcomeSyncOwnerUid != cloudUid) {
      _outcomes = [];
      _clearOutcomeSync();
      return;
    }
    // Authentication can be temporarily unavailable at startup. Preserve an
    // owner's retry intent until identity is known; no upload can run without it.
    if (_outcomeSyncOwnerUid != null && cloudUid == null && outcomeConsent) {
      return;
    }
    if (!outcomeConsent) _outcomes = [];
    if (!outcomeConsent ||
        !_sameOutcomeConsentAt(
          _outcomeSyncConsentAt,
          outcomeConsentUpdatedAt,
        )) {
      if (_pendingOutcomeWrites.values.any((value) => value != null)) {
        final discardedIds = _pendingOutcomeWrites.entries
            .where((entry) => entry.value != null)
            .map((entry) => entry.key)
            .toSet();
        _outcomes.removeWhere((outcome) => discardedIds.contains(outcome.id));
        _outcomeSyncGeneration++;
        _pendingOutcomeWrites.removeWhere((_, value) => value != null);
      }
      _outcomeSyncConsentAt = outcomeConsentUpdatedAt;
    }
  }

  void _queueOutcomeWrite(String id, OutcomeRecord? outcome) {
    _reconcileOutcomeSync();
    if (cloudUid == null || cloudRepository == null) return;
    _outcomeSyncOwnerUid = cloudUid;
    _outcomeSyncConsentAt = outcomeConsentUpdatedAt;
    _pendingOutcomeWrites[id] = outcome;
  }

  Future<void> _retryOutcomeSync() async {
    final revision = _sessionRevision;
    final uid = cloudUid;
    while (_pendingOutcomePush != null) {
      await _pendingOutcomePush;
    }
    if (revision != _sessionRevision || uid != cloudUid || !_canProcessData) {
      return;
    }
    _reconcileOutcomeSync();
    if (!hasPendingOutcomeChanges) return;
    final task = _flushOutcomeSync();
    _pendingOutcomePush = task;
    try {
      await task;
    } finally {
      if (identical(_pendingOutcomePush, task)) _pendingOutcomePush = null;
      scheduleCloudRetry();
    }
  }

  Future<void> _flushOutcomeSync() async {
    final uid = cloudUid;
    final repository = cloudRepository;
    if (uid == null || repository == null) return;
    final revision = _sessionRevision;
    final generation = _outcomeSyncGeneration;
    final consentAt = outcomeConsentUpdatedAt;
    bool current() =>
        revision == _sessionRevision &&
        generation == _outcomeSyncGeneration &&
        uid == cloudUid &&
        uid == _outcomeSyncOwnerUid &&
        _canProcessData;
    try {
      // Persist the retry intent before sending any writes. A crash after a
      // successful network write simply repeats the same owner-scoped ID.
      await _writeLocal();
      if (!current()) return;
      for (final entry in _pendingOutcomeWrites.entries.toList()) {
        if (!current()) return;
        if (!_pendingOutcomeWrites.containsKey(entry.key) ||
            !identical(_pendingOutcomeWrites[entry.key], entry.value)) {
          continue;
        }
        if (entry.value == null) {
          await repository.deleteOutcome(uid, entry.key);
        } else {
          if (!outcomeConsent ||
              !_sameOutcomeConsentAt(consentAt, outcomeConsentUpdatedAt)) {
            return;
          }
          await repository.upsertOutcome(uid, entry.value!);
        }
        if (!current()) return;
        if (_pendingOutcomeWrites.containsKey(entry.key) &&
            identical(_pendingOutcomeWrites[entry.key], entry.value)) {
          _pendingOutcomeWrites.remove(entry.key);
        }
        _markCloudUploadSuccess();
        await _writeLocal();
        if (!current()) return;
      }
      outcomeError = hasPendingOutcomeChanges
          ? 'Outcomes saved on this device · cloud update pending'
          : null;
    } on Object catch (error) {
      // A late response from a signed-out or revoked session cannot change the
      // new account's visible status or acknowledge its retry journal.
      if (!current()) return;
      outcomeError = 'Outcomes saved on this device · cloud update pending';
      _recordCloudFailure(error);
    }
  }

  ScoreSnapshot? _scoreSnapshot;
  int _scoreRefreshGeneration = 0;
  EnergyModelSummary? _cloudEnergySummary;
  String? _cloudMetadataUid;
  DateTime? _cloudMetadataFetchedAt;
  DateTime? _cloudUserUpdatedAt;
  List<SignalReading> _todaySignals = [];
  bool _scoreLoadedFromSnapshot = false;
  bool _forecastLoadedFromCloud = false;
  bool _guidanceSavedToCloud = false;
  bool insightsLoadedFromCloud = false;
  final Map<String, List<ForecastPoint>> _forecastsByDay = {};
  final Map<String, RecommendationStatus> _recommendationStatuses = {};
  final Map<String, bool> _recommendationFeedback = {};
  final Set<String> _dismissedRiskAlertIds = {};
  List<Recommendation> _recommendations = [];
  List<RiskAlert> _riskAlerts = [];
  NotificationPlan _notificationPlan = const NotificationPlan(
    state: NotificationPlanState.disabled,
  );
  bool _notificationScheduleConfirmed = false;
  bool _notificationPreferencesPersisted = true;
  InsightsSnapshot? _insightsSnapshot;

  bool get cloudEnabled => _accountAuth.isConfigured && cloudRepository != null;
  bool get isCloudAuthenticated => _accountAuth.currentSession != null;
  String? get cloudUid => _accountAuth.currentSession?.uid;
  String? get modelPreparationBlocker {
    if (!cloudEnabled || _mlPrepService == null) {
      return 'Firebase is not configured in this build. Launch with '
          '--dart-define-from-file=config/firebase_options.json to connect '
          'your account.';
    }
    if (!isCloudAuthenticated || isSignedOut || _isSigningOut) {
      return 'Sign in through Profile → Cloud account before preparing your '
          '30-day account snapshot.';
    }
    if (!_canProcessData) {
      return guardianConsentBlocker ??
          'Review your privacy choices before preparing a model.';
    }
    return null;
  }

  /// Explicit foreground action only. This path never commits or uploads data.
  Future<PrepRun> prepareModelSnapshot({
    required PrepWindow window,
    bool refresh = false,
  }) async {
    final blocker = modelPreparationBlocker;
    if (blocker != null) throw StateError(blocker);
    final uid = cloudUid;
    final sessionRevision = _sessionRevision;
    await _rememberModelPreparationWindow(window);
    if (cloudUid != uid ||
        !_canProcessData ||
        sessionRevision != _sessionRevision) {
      throw StateError('Account changed during preparation.');
    }
    final revision = _modelPreparationRevision;
    final run = await _mlPrepService!.prepare(
      window: window,
      refresh: refresh,
      coverageOnly: true,
    );
    if (cloudUid != uid ||
        revision != _modelPreparationRevision ||
        sessionRevision != _sessionRevision ||
        !_canProcessData) {
      throw StateError(
        'Account data changed during preparation. Prepare again.',
      );
    }
    _preparedModelRun = run;
    return run;
  }

  String _prepWindowKey(String uid) =>
      '$_prepWindowKeyPrefix${prepFingerprint({'uid': uid})}';

  Future<void> _rememberModelPreparationWindow(PrepWindow window) async {
    final ensureCurrent = _beginMutation();
    final uid = cloudUid;
    if (uid == null) throw StateError('Sign in to select an account window.');
    final preferences = await SharedPreferences.getInstance();
    ensureCurrent();
    if (cloudUid != uid) {
      throw StateError('Account changed during preparation.');
    }
    _lastModelPreparationWindow = window;
    _lastModelPreparationWindowUid = uid;
    if (!await preferences.setString(
      _prepWindowKey(uid),
      jsonEncode(window.toJson()),
    )) {
      throw StateError('Could not save the selected preparation window.');
    }
    ensureCurrent();
  }

  void _restoreModelPreparationWindow(SharedPreferences preferences) {
    final uid = cloudUid;
    _lastModelPreparationWindow = null;
    _lastModelPreparationWindowUid = null;
    if (uid == null) return;
    final raw = preferences.getString(_prepWindowKey(uid));
    if (raw == null) return;
    try {
      _lastModelPreparationWindow = PrepWindow.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      _lastModelPreparationWindowUid = uid;
    } on Object {
      // Invalid local preferences must not trigger a replacement account read.
    }
  }

  Future<void> _clearModelPreparationWindow() async {
    _lastModelPreparationWindow = null;
    _lastModelPreparationWindowUid = null;
    try {
      final preferences = await SharedPreferences.getInstance();
      for (final key in preferences.getKeys().where(
        (key) => key.startsWith(_prepWindowKeyPrefix),
      )) {
        await preferences.remove(key);
      }
    } on Object catch (error) {
      debugPrint('Tonyo could not clear the saved prep window: $error');
    }
  }

  Future<void> _invalidateModelPreparation() async {
    _modelPreparationRevision += 1;
    _preparedModelRun = null;
    _energyModelService.cancelPending();
    try {
      await _mlPrepService?.invalidate();
    } on Object catch (error) {
      // Prep cache maintenance must not prevent an account edit or sign-out.
      debugPrint('Tonyo could not clear the model preparation cache: $error');
    }
  }

  Future<void> _discardPersonalizedModel() async {
    await _energyModelService.discard();
    _scoreSnapshot = _scoreSnapshot?.withoutPersonalization();
    _forecastsByDay.clear();
  }

  bool get isScoreLoading => isEnergyScoreLoading;
  String? get scoreError => energyScoreError;
  bool get scoreLoadedFromSnapshot =>
      _scoreLoadedFromSnapshot &&
      _scoreSnapshot != null &&
      _currentScoreReference(_scoreSnapshot!, _now()) &&
      _scoreReferenceKey(_scoreSnapshot!) == _scoreReferenceKey(score);
  bool get forecastLoadedFromCloud => _forecastLoadedFromCloud;
  bool get guidanceSavedToCloud => _guidanceSavedToCloud;
  InsightsSnapshot get insightsSnapshot =>
      _insightsSnapshot ??
      InsightsLogic.build(now: _now(), signals: const [], checkIns: const []);
  bool get notificationSchedulingSupported =>
      _notificationService.supportsScheduling;

  DateTime get currentTime => _now();
  bool get canOpenNotificationTarget =>
      isReady && onboardingComplete && _canProcessData && !isPrivacyBusy;

  Future<void> initializeNotificationResponses(
    void Function(String payload) onTap,
  ) async {
    if (_notificationService case NotificationResponseSource source) {
      await source.initializeResponses(onTap);
    }
  }

  bool get screenTimeReportAvailable =>
      screenTimeAuthorization != ScreenTimeAuthorizationState.unavailable &&
      screenTimeAuthorization !=
          ScreenTimeAuthorizationState.entitlementRequired;
  int get manualScreenTimeSignalCount => signals
      .where(
        (item) =>
            item.type == SignalType.screenTime &&
            item.source == SignalSource.manual,
      )
      .length;
  NotificationPlan get notificationPlan => _notificationPlan;
  int get scheduledNotificationCount => _notificationsConfirmed
      ? _notificationPlan.notifications
            .where((item) => item.scheduledAt.isAfter(_now()))
            .length
      : 0;
  bool get _notificationsConfirmed =>
      _notificationScheduleConfirmed &&
      _notificationPreferencesPersisted &&
      _canProcessData &&
      notificationsEnabled &&
      notificationPermission == NotificationPermissionState.granted &&
      !isNotificationSyncing &&
      notificationError == null;
  int get scheduledCoachNotificationCount => _notificationsConfirmed
      ? _notificationPlan.notifications
            .where(
              (item) =>
                  item.kind == GuidanceNotificationKind.coachPlan &&
                  item.scheduledAt.isAfter(_now()),
            )
            .length
      : 0;
  GuidanceNotification? notificationForRecommendation(String id) =>
      !_notificationsConfirmed
      ? null
      : _notificationPlan.notifications
            .where(
              (item) =>
                  item.sourceRecommendationId == id &&
                  item.scheduledAt.isAfter(_now()),
            )
            .firstOrNull;
  GuidanceNotification? get nextScheduledNotification =>
      scheduledNotificationCount == 0
      ? null
      : _notificationPlan.notifications
            .where((item) => item.scheduledAt.isAfter(_now()))
            .firstOrNull;
  List<OutcomeRecord> get outcomes => List.unmodifiable(_outcomes);
  int get observedEnergyOutcomeCount => _outcomes
      .where((outcome) => outcome.type == OutcomeType.observedEnergy)
      .length;
  int get cognitiveOutcomeCount => _outcomes
      .where((outcome) => outcome.type == OutcomeType.cognitiveReaction)
      .length;
  OutcomeRecord? outcomeForRecommendation(String recommendationId) => _outcomes
      .where((outcome) => outcome.recommendationId == recommendationId)
      .firstOrNull;
  int get healthKitHeartSignalCount => signals
      .where(
        (item) =>
            item.source == SignalSource.healthKit &&
            HeartSyncLogic.supportedTypes.contains(item.type),
      )
      .length;
  int get healthKitSleepSignalCount => signals
      .where(
        (item) =>
            item.source == SignalSource.healthKit &&
            SleepSyncLogic.stageTypes.contains(item.type),
      )
      .length;
  int get healthKitSleepNightCount => signals
      .where(
        (item) =>
            item.source == SignalSource.healthKit &&
            (item.groupId?.startsWith(SleepSyncLogic.importedGroupPrefix) ??
                false),
      )
      .map((item) => item.groupId)
      .toSet()
      .length;
  int get healthKitWorkoutSignalCount => signals
      .where(
        (item) =>
            item.source == SignalSource.healthKit &&
            item.type == SignalType.exercise,
      )
      .length;
  int get healthKitHydrationSignalCount => signals
      .where(
        (item) =>
            item.source == SignalSource.healthKit &&
            item.type == SignalType.hydration,
      )
      .length;
  int get healthKitStepSignalCount => signals
      .where(
        (item) =>
            item.source == SignalSource.healthKit &&
            item.type == SignalType.steps,
      )
      .length;
  bool get isHealthSyncFresh =>
      lastSync != null &&
      _now().difference(lastSync!) < const Duration(hours: 2);
  List<TodaySignalSummary> get todaySignalSummaries =>
      TodayDashboardLogic.summariesForDay(
        _todaySignals.isEmpty ? signals : _todaySignals,
        day: _now(),
        now: _now(),
      );

  List<ActivityLogEntry> get activityLogs {
    final grouped = <String, List<SignalReading>>{};
    for (final signal in signals) {
      final groupId = signal.groupId;
      if (groupId != null && groupId.startsWith('activity-')) {
        grouped.putIfAbsent(groupId, () => []).add(signal);
      }
    }
    final entries = <ActivityLogEntry>[];
    for (final group in grouped.entries) {
      double? valueFor(SignalType type) =>
          group.value.where((item) => item.type == type).firstOrNull?.value;
      final hydration = valueFor(SignalType.hydration);
      final study = valueFor(SignalType.study);
      final exercise = valueFor(SignalType.exercise);
      final screenTime = valueFor(SignalType.screenTime);
      if (hydration == null &&
          study == null &&
          exercise == null &&
          screenTime == null) {
        continue;
      }
      entries.add(
        ActivityLogEntry(
          id: group.key,
          timestamp: group.value.first.timestamp,
          hydrationLiters: hydration,
          studyHours: study,
          exerciseHours: exercise,
          screenTimeHours: screenTime,
        ),
      );
    }
    return entries..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<SleepLogEntry> get sleepLogs {
    final grouped = <String, List<SignalReading>>{};
    for (final signal in signals) {
      final groupId = signal.groupId;
      if (groupId != null && groupId.startsWith('sleep-')) {
        grouped.putIfAbsent(groupId, () => []).add(signal);
      }
    }
    final entries = <SleepLogEntry>[];
    for (final group in grouped.entries) {
      final sleep = group.value
          .where(
            (item) =>
                item.type == SignalType.sleep || item.type == SignalType.nap,
          )
          .firstOrNull;
      final bedtime = group.value
          .where((item) => item.type == SignalType.bedtime)
          .firstOrNull;
      if (sleep == null || (bedtime == null && sleep.type != SignalType.nap)) {
        continue;
      }
      entries.add(
        SleepLogEntry(
          id: group.key,
          bedtime:
              (bedtime?.timestamp ??
                      sleep.timestamp.subtract(
                        Duration(
                          microseconds:
                              (sleep.value * Duration.microsecondsPerHour)
                                  .round(),
                        ),
                      ))
                  .toLocal(),
          wakeTime: sleep.timestamp.toLocal(),
          quality: sleep.quality * 5,
          kind: sleep.type == SignalType.nap
              ? SleepKind.nap
              : SleepKind.mainSleep,
        ),
      );
    }
    return entries..sort((a, b) => b.wakeTime.compareTo(a.wakeTime));
  }

  double get bedtimeConsistencyMinutes =>
      SleepLogEntry.bedtimeConsistencyMinutes(
        sleepLogs.where((entry) => !entry.isNap).take(7),
      );

  List<DailyHistoryDay> get dailyHistory => DailyHistoryLogic.build(
    signals: signals,
    checkIns: checkIns,
    activityLogs: activityLogs,
    sleepLogs: sleepLogs,
  );

  bool _currentScoreReference(ScoreSnapshot value, DateTime at) =>
      value.energyModelVersion == FatigueEngine.energyModelVersion &&
      value.cognitiveModelVersion == FatigueEngine.cognitiveModelVersion &&
      value.day != null &&
      sameLocalDay(value.day!, at) &&
      value.calculatedAt != null &&
      !value.calculatedAt!.isAfter(at) &&
      at.difference(value.calculatedAt!) < const Duration(minutes: 1);

  String _scoreReferenceKey(ScoreSnapshot value) {
    final fields =
        scoreSnapshotToCloud(
          snapshot: value.withoutPersonalization(),
          day: value.day ?? localDay(_now()),
        )..removeWhere(
          (key, _) => const {
            'calculatedAt',
            'previousCognitive',
            'cognitiveDelta',
          }.contains(key),
        );
    try {
      return jsonEncode(
        fields,
        toEncodable: (value) => (value as DateTime).toUtc().toIso8601String(),
      );
    } on Object {
      return ''; // Malformed derived cache cannot displace a valid raw reference.
    }
  }

  ScoreSnapshot get score {
    final at = _now();
    final reference = FatigueEngine.score(
      signals: signals,
      checkIns: checkIns,
      now: at,
      personalBaselines: PersonalBaselineLogic.build(
        signals: signals,
        asOf: localDay(at),
      ),
    );
    final cached = _scoreSnapshot;
    // Never let an old cloud/device estimate outlive its source evidence.
    final value =
        cached != null &&
            _currentScoreReference(cached, at) &&
            _scoreReferenceKey(cached) == _scoreReferenceKey(reference)
        ? cached
        : reference;
    return _energyModelService.model == null
        ? value.withoutPersonalization()
        : _personalizeEnergy(value, signals, checkIns, at);
  }

  /// Opening transparency only projects already loaded state. No model load,
  /// collection query, metadata write or consent mutation happens here.
  ModelTransparencyState get modelTransparency {
    final visible = !isSignedOut && !_isSigningOut;
    final accountVisible = visible && isCloudAuthenticated;
    final sameOwner = accountVisible && cloudUid == _cloudMetadataUid;
    final local = accountVisible ? _energyModelService.model : null;
    final at = _now();
    return ModelTransparencyState(
      snapshot: visible
          ? score
          : const ScoreSnapshot(
              energy: 0,
              cognitive: 0,
              confidence: 0,
              drivers: [],
              hasCognitiveScore: false,
            ),
      viewedAt: at,
      scoreFromCloud: visible && scoreLoadedFromSnapshot,
      offline:
          accountVisible &&
          (cloudSyncError != null || energyScoreError != null),
      signedIn: accountVisible,
      consentEnabled: visible && outcomeConsent,
      loading: visible && isScoreLoading,
      localModel: local == null
          ? null
          : EnergyModelSummary.tryParse(local.metadata),
      cloudModel:
          sameOwner && _cloudEnergySummary?.trainedAt.isAfter(at) == false
          ? _cloudEnergySummary
          : null,
      metadataFetchedAt:
          sameOwner && _cloudMetadataFetchedAt?.isAfter(at) == false
          ? _cloudMetadataFetchedAt
          : null,
      accountUpdatedAt: sameOwner && _cloudUserUpdatedAt?.isAfter(at) == false
          ? _cloudUserUpdatedAt
          : null,
      localModelStatus: accountVisible ? _energyModelService.status : '',
    );
  }

  ScoreSnapshot _personalizeEnergy(
    ScoreSnapshot score,
    List<SignalReading> sourceSignals,
    List<DailyCheckIn> sourceChecks,
    DateTime at,
  ) {
    final base = score.withoutPersonalization();
    final model = _energyModelService.model;
    if (!base.canEstimateEnergy ||
        model == null ||
        at.isBefore(model.trainedAt)) {
      return base;
    }
    try {
      final input = MlPrepBuilder.energyInput(
        signals: sourceSignals,
        checkIns: sourceChecks,
        at: at,
        timezone: model.window.timezone,
      );
      if (input == null) return base;
      final timer = Stopwatch()..start();
      final correction = model.correction(
        features: input.features,
        featureAgeHours: input.featureAgeHours,
      );
      timer.stop();
      if (correction == null || timer.elapsedMicroseconds >= 1000) return base;
      return base.withEnergyCorrection(correction, 'energy-ridge-v1');
    } on Object {
      return base;
    }
  }

  PersonalBaselines get personalBaselines =>
      score.personalBaselines ??
      PersonalBaselineLogic.build(signals: signals, asOf: _now());
  bool _eligibleForecast(List<ForecastPoint> points) {
    final at = _now();
    final signalIds = signals.map((item) => item.id).toSet();
    final checkInIds = checkIns
        .where((item) => !item.isResearchCheckIn)
        .map((item) => item.id)
        .toSet();
    if (!score.canEstimateEnergy ||
        points.isEmpty ||
        !points.every(
          (point) =>
              point.rulesVersion == FatigueEngine.energyModelVersion &&
              point.signalEvidenceIds.every(signalIds.contains) &&
              point.checkInEvidenceIds.every(checkInIds.contains) &&
              point.updatedAt != null &&
              !point.updatedAt!.isAfter(at) &&
              sameLocalDay(point.updatedAt!, at) &&
              at.difference(point.updatedAt!) <= forecastFreshnessWindow,
        )) {
      return false;
    }
    final generatedAt = points.first.updatedAt!;
    if (points.any((point) => point.updatedAt != generatedAt) ||
        signals.any(
          (item) =>
              item.source != SignalSource.model &&
              item.timestamp.isAfter(generatedAt) &&
              !item.timestamp.isAfter(at),
        ) ||
        checkIns.any(
          (item) =>
              !item.isResearchCheckIn &&
              item.timestamp.isAfter(generatedAt) &&
              !item.timestamp.isAfter(at),
        )) {
      return false;
    }
    // A raw edit can reach another device before the replacement curve does.
    // IDs alone cannot validate changed values, schedules, or learned weights.
    // Replay at the saved generation time so unchanged data can still reuse
    // its curve without relabeling the original freshness or provenance.
    final reference = FatigueEngine.score(
      signals: signals,
      checkIns: checkIns,
      now: generatedAt,
      personalBaselines: PersonalBaselineLogic.build(
        signals: signals,
        asOf: localDay(generatedAt),
      ),
    );
    final expected = FatigueEngine.forecast(
      _personalizeEnergy(reference, signals, checkIns, generatedAt),
      points.first.time,
      signals: signals,
      checkIns: checkIns,
      profile: profile,
      generatedAt: generatedAt,
    );
    if (expected.length != points.length) return false;
    final ordered = [...points]..sort((a, b) => a.time.compareTo(b.time));
    bool sameIds(List<String> left, List<String> right) =>
        left.length == right.length && left.toSet().containsAll(right);
    for (var index = 0; index < ordered.length; index++) {
      final saved = ordered[index];
      final current = expected[index];
      if (!saved.time.isAtSameMomentAs(current.time) ||
          !((saved.energy - current.energy).abs() <= .000001) ||
          !((saved.uncertainty - current.uncertainty).abs() <= .000001) ||
          !sameIds(saved.signalEvidenceIds, current.signalEvidenceIds) ||
          !sameIds(saved.checkInEvidenceIds, current.checkInEvidenceIds)) {
        return false;
      }
    }
    return true;
  }

  List<ForecastPoint> forecastFor(DateTime day) {
    final cached = _forecastsByDay[_dayKey(day)];
    if (cached != null && _eligibleForecast(cached)) return cached;
    return FatigueEngine.forecast(
      score,
      day,
      signals: signals,
      checkIns: checkIns,
      profile: profile,
      generatedAt: _now(),
    );
  }

  List<ForecastPoint> forecastDataFor(DateTime day) {
    final saved = _forecastsByDay[_dayKey(day)];
    if (saved != null && _eligibleForecast(saved)) return saved;
    if (isCloudAuthenticated && forecastError == null) return const [];
    return forecastFor(day);
  }

  List<ForecastDaySummary> forecastSummariesFor(
    DateTime start, {
    int dayCount = forecastDayCount,
  }) {
    final firstDay = localDay(start);
    final summaries = <ForecastDaySummary>[];
    for (var index = 0; index < dayCount; index++) {
      final day = localDay(firstDay, index);
      final points = forecastDataFor(day);
      if (points.isNotEmpty) {
        summaries.add(ForecastDaySummary.fromPoints(day, points));
      }
    }
    return summaries;
  }

  List<ForecastWindow> windowsFor(DateTime day) => FatigueEngine.windows(
    forecastDataFor(day),
    score,
    signals: signals,
    checkIns: checkIns,
  );
  List<ForecastWindow> get windows => windowsFor(_now());
  List<RiskAlert> get alerts =>
      List.unmodifiable(_riskAlerts.where((alert) => !alert.dismissed));
  List<RiskAlert> get allAlerts => List.unmodifiable(_riskAlerts);
  List<Recommendation> get recommendations =>
      List.unmodifiable(_recommendations);
  int get recommendationFeedbackHistoryCount => _recommendations.fold(
    0,
    (total, item) => total + item.feedbackSampleCount,
  );

  /// Personal reaction baseline from prior valid tests (Version 0.9).
  double? get reactionBaseline => ReactionTestLogic.baselineMs(signals);

  List<DailyCheckIn> recentCheckIns({int limit = 8}) =>
      CheckInLogic.recentHistory(checkIns, limit: limit);

  /// Loads the Version 0.13 daily snapshot and day-scoped signal summary.
  /// When missing or explicitly refreshed, recalculates both scores from
  /// user-scoped inputs and persists scoreSnapshots/{yyyy-MM-dd}.
  Future<void> refreshScores({
    DateTime? day,
    bool notify = true,
    bool forceRecalculate = false,
  }) async {
    if (!_canProcessData) return;
    final currentTime = _now();
    final target = day ?? currentTime;
    final start = localDay(target);
    final end = localDay(start, 1);
    final calculationTime = _sameDay(currentTime, start)
        ? currentTime
        : end.subtract(const Duration(microseconds: 1));
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    final revision = _sessionRevision;
    final generation = ++_scoreRefreshGeneration;
    bool currentRequest() =>
        revision == _sessionRevision &&
        generation == _scoreRefreshGeneration &&
        cloudUid == session?.uid &&
        _canProcessData;

    isEnergyScoreLoading = true;
    energyScoreError = null;
    if (notify) notifyListeners();
    try {
      List<SignalReading> scoringSignals = signals;
      List<DailyCheckIn> scoringCheckIns = checkIns;
      ScoreSnapshot? previousDay;
      final canUseCloud =
          session != null &&
          repository != null &&
          cloudSyncError == null &&
          !hasPendingCloudChanges;
      if (canUseCloud) {
        final dashboardResults = await Future.wait<Object?>([
          repository.scoreSnapshotForDay(session.uid, start),
          repository.signalsByRange(session.uid, start: start, end: end),
        ]);
        if (!currentRequest()) return;
        final savedSnapshot = dashboardResults[0] as ScoreSnapshot?;
        _todaySignals = dashboardResults[1]! as List<SignalReading>;
        if (!forceRecalculate &&
            savedSnapshot != null &&
            _currentScoreReference(savedSnapshot, calculationTime) &&
            savedSnapshot.freshness != null &&
            savedSnapshot.cognitiveFreshness != null &&
            savedSnapshot.personalBaselines != null &&
            savedSnapshot.energyModelVersion ==
                FatigueEngine.energyModelVersion &&
            savedSnapshot.cognitiveModelVersion ==
                FatigueEngine.cognitiveModelVersion &&
            savedSnapshot.day == start &&
            !(_sameDay(currentTime, start) &&
                _napScoreNeedsRefresh(savedSnapshot, calculationTime))) {
          _scoreSnapshot = _personalizeEnergy(
            savedSnapshot,
            signals,
            checkIns,
            calculationTime,
          );
          _scoreLoadedFromSnapshot = true;
          return;
        }

        final scoringResults = await Future.wait<Object?>([
          repository.signalsByRange(
            session.uid,
            start: localDay(start, -PersonalBaselineLogic.windowDays),
            end: end,
          ),
          repository.checkInsByRange(
            session.uid,
            start: start.subtract(const Duration(hours: 36)),
            end: end,
          ),
          repository.scoreSnapshotForDay(session.uid, localDay(start, -1)),
        ]);
        if (!currentRequest()) return;
        scoringSignals = scoringResults[0]! as List<SignalReading>;
        scoringCheckIns = scoringResults[1]! as List<DailyCheckIn>;
        previousDay = scoringResults[2] as ScoreSnapshot?;
      } else if (session != null && repository != null) {
        energyScoreError = 'Cloud scoring unavailable · using cached inputs';
      }
      if (!canUseCloud) {
        _todaySignals = signals
            .where(
              (item) =>
                  !item.timestamp.isBefore(start) &&
                  item.timestamp.isBefore(end),
            )
            .toList();
      }
      final reference = FatigueEngine.score(
        signals: scoringSignals,
        checkIns: scoringCheckIns,
        now: calculationTime,
        day: start,
        previousDay: previousDay,
        personalBaselines: PersonalBaselineLogic.build(
          signals: scoringSignals,
          asOf: start,
        ),
      );
      final snapshot = _personalizeEnergy(
        reference,
        scoringSignals,
        scoringCheckIns,
        calculationTime,
      );
      if (canUseCloud) {
        if (!currentRequest()) return;
        await repository.upsertScoreSnapshot(session.uid, snapshot);
        if (!currentRequest()) return;
      }
      _scoreSnapshot = snapshot;
      _scoreLoadedFromSnapshot = false;
    } on Object {
      if (!currentRequest()) return;
      // A network/query failure must not make the wellness estimate disappear.
      _scoreSnapshot = FatigueEngine.score(
        signals: signals,
        checkIns: checkIns,
        now: calculationTime,
        day: start,
        personalBaselines: PersonalBaselineLogic.build(
          signals: signals,
          asOf: start,
        ),
      );
      _todaySignals = signals
          .where(
            (item) =>
                !item.timestamp.isBefore(start) && item.timestamp.isBefore(end),
          )
          .toList();
      _scoreLoadedFromSnapshot = false;
      energyScoreError = 'Cloud scoring unavailable · using cached inputs';
    } finally {
      if (revision == _sessionRevision &&
          generation == _scoreRefreshGeneration &&
          cloudUid == session?.uid) {
        isEnergyScoreLoading = false;
        if (notify) notifyListeners();
      }
    }
  }

  /// Compatibility entry point retained for Version 0.11 callers.
  Future<void> refreshEnergyScore({DateTime? day, bool notify = true}) =>
      refreshScores(day: day, notify: notify, forceRecalculate: true);

  int _forecastRefreshGeneration = 0;
  int _guidanceRefreshGeneration = 0;
  int _notificationRefreshGeneration = 0;
  int _notificationPreferenceGeneration = 0;
  int _insightsRefreshGeneration = 0;
  int _outcomeRefreshGeneration = 0;

  /// Loads or regenerates Today and Tomorrow hourly forecasts. Authenticated
  /// users read and write their private forecastPoints collection; local and
  /// failed-cloud sessions retain the same deterministic offline model.
  Future<void> refreshForecasts({
    DateTime? day,
    bool notify = true,
    bool forceRecalculate = false,
  }) async {
    if (!_canProcessData) return;
    final clock = _now();
    final target = day ?? clock;
    final firstDay = localDay(target);
    final days = List.generate(
      forecastDayCount,
      (index) => localDay(firstDay, index),
    );
    final rangeEnd = localDay(days.last, 1);
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    final revision = _sessionRevision;
    final generation = ++_forecastRefreshGeneration;
    bool sameRequest() =>
        revision == _sessionRevision &&
        generation == _forecastRefreshGeneration &&
        cloudUid == session?.uid;
    bool currentRequest() => sameRequest() && _canProcessData;

    isForecastLoading = true;
    forecastError = null;
    if (notify) notifyListeners();
    try {
      if (session != null &&
          repository != null &&
          cloudSyncError == null &&
          !hasPendingCloudChanges) {
        if (!forceRecalculate) {
          final saved = await repository.forecastPointsByRange(
            session.uid,
            start: firstDay,
            end: rangeEnd,
          );
          if (!currentRequest()) return;
          final savedByDay = _groupForecasts(saved);
          if (days.every((targetDay) {
            final points = savedByDay[_dayKey(targetDay)] ?? const [];
            return _eligibleForecast(points) &&
                _isCompleteForecast(points, targetDay) &&
                !ForecastDaySummary.fromPoints(
                  targetDay,
                  points,
                ).isStaleAt(clock, maximumAge: forecastFreshnessWindow);
          })) {
            _forecastsByDay.addAll(savedByDay);
            _forecastLoadedFromCloud = true;
            return;
          }
        }

        final inputs = await Future.wait<Object>([
          repository.signalsByRange(
            session.uid,
            start: localDay(firstDay, -7),
            end: rangeEnd,
          ),
          repository.checkInsByRange(
            session.uid,
            start: localDay(firstDay, -7),
            end: rangeEnd,
          ),
        ]);
        if (!currentRequest()) return;
        final forecastSignals = inputs[0] as List<SignalReading>;
        final forecastCheckIns = inputs[1] as List<DailyCheckIn>;
        final generated = {
          for (final targetDay in days)
            _dayKey(targetDay): FatigueEngine.forecast(
              score,
              targetDay,
              signals: forecastSignals,
              checkIns: forecastCheckIns,
              profile: profile,
              generatedAt: clock,
            ),
        };
        await Future.wait([
          for (final targetDay in days)
            repository.replaceForecastPoints(
              session.uid,
              day: targetDay,
              points: generated[_dayKey(targetDay)]!,
            ),
        ]);
        if (!currentRequest()) return;
        _forecastsByDay.addAll(generated);
        _forecastLoadedFromCloud = false;
        return;
      }

      _generateLocalForecasts(days, generatedAt: clock);
      _forecastLoadedFromCloud = false;
      if (session != null && repository != null) {
        forecastError = 'Cloud sync pending · using saved device inputs';
      }
    } on Object {
      if (!currentRequest()) return;
      _generateLocalForecasts(days, generatedAt: clock);
      _forecastLoadedFromCloud = false;
      forecastError = 'Cloud forecast unavailable · using cached inputs';
    } finally {
      if (sameRequest()) {
        isForecastLoading = false;
        if (notify) notifyListeners();
      }
    }
  }

  /// Builds Version 0.30's feedback-ranked daily plan plus Version 0.19 alerts
  /// from owner-scoped inputs, then replaces today's private documents.
  Future<void> refreshGuidance({DateTime? day, bool notify = true}) async {
    if (!_canProcessData) return;
    final clock = _now();
    final target = day ?? clock;
    final targetDay = localDay(target);
    final rangeStart = localDay(targetDay, -6);
    final rangeEnd = localDay(targetDay, 1);
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    final revision = _sessionRevision;
    final generation = ++_guidanceRefreshGeneration;
    bool sameRequest() =>
        revision == _sessionRevision &&
        generation == _guidanceRefreshGeneration &&
        cloudUid == session?.uid;
    bool currentRequest() => sameRequest() && _canProcessData;

    isGuidanceLoading = true;
    guidanceError = null;
    if (notify) notifyListeners();

    void derive({
      required List<SignalReading> sourceSignals,
      required List<DailyCheckIn> sourceCheckIns,
      List<Recommendation> savedRecommendations = const [],
      List<Recommendation> feedbackHistory = const [],
      List<RiskAlert> savedAlerts = const [],
    }) {
      final windowValues = FatigueEngine.windows(
        forecastDataFor(targetDay),
        score,
        signals: sourceSignals,
        checkIns: sourceCheckIns,
      );
      final savedById = {
        for (final item in savedRecommendations) item.id: item,
      };
      _recommendations =
          RecommendationFeedbackLogic.rank(
            plan: DailyPlanLogic.build(
              windows: windowValues,
              score: score,
              profile: profile,
              day: targetDay,
              generatedAt: clock,
            ),
            history: feedbackHistory,
          ).map((item) {
            final saved = savedById[item.id];
            final pending = _pendingCoachWrites[item.id];
            final status =
                pending?.status ??
                saved?.status ??
                _recommendationStatuses[item.id];
            final helpful =
                pending?.helpful ??
                saved?.helpful ??
                _recommendationFeedback[item.id];
            if (status != null) _recommendationStatuses[item.id] = status;
            if (helpful != null) _recommendationFeedback[item.id] = helpful;
            return item.copyWith(status: status, helpful: helpful);
          }).toList();

      final savedDismissals = {
        for (final item in savedAlerts) item.id: item.dismissed,
      };
      _riskAlerts =
          FatigueEngine.alerts(
            sourceSignals,
            sourceCheckIns,
            score,
            now: clock,
            day: targetDay,
          ).map((item) {
            final dismissed =
                savedDismissals[item.id] == true ||
                _dismissedRiskAlertIds.contains(item.id);
            if (dismissed) _dismissedRiskAlertIds.add(item.id);
            return item.copyWith(dismissed: dismissed);
          }).toList();
    }

    try {
      if (hasPendingCoachChanges) {
        await _retryCoachSync();
        if (!currentRequest()) return;
      }
      if (session != null &&
          repository != null &&
          cloudSyncError == null &&
          !hasPendingCloudChanges &&
          !hasPendingCoachChanges) {
        final values = await Future.wait<Object>([
          repository.signalsByRange(
            session.uid,
            start: rangeStart,
            end: rangeEnd,
          ),
          repository.checkInsByRange(
            session.uid,
            start: rangeStart,
            end: rangeEnd,
          ),
          repository.recommendationsForDay(session.uid, targetDay),
          repository.recommendationsByRange(
            session.uid,
            start: targetDay.subtract(
              RecommendationFeedbackLogic.historyWindow,
            ),
            end: targetDay,
          ),
          repository.riskAlertsForDay(session.uid, targetDay),
        ]);
        if (!currentRequest()) return;
        derive(
          sourceSignals: values[0] as List<SignalReading>,
          sourceCheckIns: values[1] as List<DailyCheckIn>,
          savedRecommendations: values[2] as List<Recommendation>,
          feedbackHistory: values[3] as List<Recommendation>,
          savedAlerts: values[4] as List<RiskAlert>,
        );
        final write = Future.wait([
          repository.replaceRecommendationsForDay(
            session.uid,
            day: targetDay,
            recommendations: _recommendations,
          ),
          repository.replaceRiskAlertsForDay(
            session.uid,
            day: targetDay,
            alerts: _riskAlerts,
          ),
        ]);
        _pendingGuidanceWrite = write;
        try {
          await write;
        } finally {
          if (identical(_pendingGuidanceWrite, write)) {
            _pendingGuidanceWrite = null;
          }
        }
        if (!currentRequest()) return;
        _guidanceSavedToCloud = true;
        return;
      }
      derive(sourceSignals: signals, sourceCheckIns: checkIns);
      _guidanceSavedToCloud = false;
      if (session != null && repository != null) {
        guidanceError = 'Cloud sync pending · using saved device inputs';
      }
    } on Object {
      if (!currentRequest()) return;
      derive(sourceSignals: signals, sourceCheckIns: checkIns);
      _guidanceSavedToCloud = false;
      guidanceError = 'Cloud guidance unavailable · using cached inputs';
    } finally {
      if (sameRequest()) isGuidanceLoading = false;
      if (currentRequest()) {
        await refreshNotifications(notify: false);
      }
      if (sameRequest() && notify) notifyListeners();
    }
  }

  Future<void> refreshNotifications({bool notify = true}) async {
    if (!_canProcessData || isSignedOut || _isSigningOut) {
      await _notificationService.cancelGuidance();
      _notificationScheduleConfirmed = false;
      return;
    }
    if (!_notificationPreferencesPersisted) return;
    final sessionRevision = _sessionRevision;
    final uid = cloudUid;
    final generation = ++_notificationRefreshGeneration;
    bool sameRequest() =>
        sessionRevision == _sessionRevision &&
        generation == _notificationRefreshGeneration &&
        cloudUid == uid;
    bool currentRequest() => sameRequest() && _canProcessData;
    isNotificationSyncing = true;
    _notificationScheduleConfirmed = false;
    notificationError = null;
    if (notify) notifyListeners();

    try {
      final now = _now();
      _notificationPlan = NotificationLogic.build(
        now: now,
        points: forecastDataFor(now),
        windows: windowsFor(now),
        riskAlerts: _riskAlerts,
        recommendations: _recommendations,
        enabled: notificationsEnabled,
        crashEnabled: crashNotificationsEnabled,
        recoveryEnabled: recoveryNotificationsEnabled,
        coachPlanEnabled: coachPlanNotificationsEnabled,
        currentEvidenceEligible:
            score.canEstimateEnergy || score.canEstimateCognitive,
      );
      if (!notificationsEnabled) {
        notificationPermission = NotificationPermissionState.unknown;
        await _notificationService.cancelGuidance();
        return;
      }
      if (!_notificationService.supportsScheduling) {
        notificationPermission = NotificationPermissionState.unavailable;
        notificationError = 'Scheduled alerts are unavailable on this device.';
        return;
      }
      final permission = await _notificationService.permissionStatus();
      if (!currentRequest()) return;
      notificationPermission = permission;
      if (notificationPermission != NotificationPermissionState.granted) {
        await _notificationService.cancelGuidance();
        if (!currentRequest()) return;
        notificationError =
            notificationPermission == NotificationPermissionState.denied
            ? 'Notifications are blocked in system settings.'
            : 'Notification permission is required.';
        return;
      }
      await _notificationService.reconcile(_notificationPlan.notifications);
      // The service serializes replacements and cancellations. A superseded
      // request must not cancel a newer schedule queued behind it.
      if (currentRequest()) _notificationScheduleConfirmed = true;
      if (!_canProcessData) {
        _notificationScheduleConfirmed = false;
        await _notificationService.cancelGuidance();
      }
    } on Object {
      if (!currentRequest()) return;
      notificationError = 'Notification schedule unavailable · try again';
    } finally {
      if (sameRequest()) {
        isNotificationSyncing = false;
        if (notify) notifyListeners();
      }
    }
  }

  Future<void> refreshInsights({DateTime? day, bool notify = true}) async {
    if (!_canProcessData) return;
    final clock = day ?? _now();
    final targetDay = localDay(clock);
    final rangeStart = localDay(
      targetDay,
      -(InsightsLogic.queryLookbackDays - 1),
    );
    final rangeEnd = localDay(targetDay, 1);
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    final revision = _sessionRevision;
    final generation = ++_insightsRefreshGeneration;
    bool sameRequest() =>
        revision == _sessionRevision &&
        generation == _insightsRefreshGeneration &&
        cloudUid == session?.uid;
    bool currentRequest() => sameRequest() && _canProcessData;

    isInsightsLoading = true;
    insightsError = null;
    if (notify) notifyListeners();
    try {
      if (session != null &&
          repository != null &&
          cloudSyncError == null &&
          !hasPendingCloudChanges) {
        final values = await Future.wait<Object>([
          repository.signalsByRange(
            session.uid,
            start: rangeStart,
            end: rangeEnd,
          ),
          repository.checkInsByRange(
            session.uid,
            start: rangeStart,
            end: rangeEnd,
          ),
        ]);
        if (!currentRequest()) return;
        _insightsSnapshot = InsightsLogic.build(
          now: clock,
          signals: values[0] as List<SignalReading>,
          checkIns: values[1] as List<DailyCheckIn>,
        );
        insightsLoadedFromCloud = true;
        return;
      }
      _insightsSnapshot = InsightsLogic.build(
        now: clock,
        signals: signals,
        checkIns: checkIns,
      );
      insightsLoadedFromCloud = false;
      if (session != null && repository != null) {
        insightsError = 'Cloud sync pending · using saved device inputs';
      }
    } on Object {
      if (!currentRequest()) return;
      _insightsSnapshot = InsightsLogic.build(
        now: clock,
        signals: signals,
        checkIns: checkIns,
      );
      insightsLoadedFromCloud = false;
      insightsError = 'Cloud insights unavailable · using cached entries';
    } finally {
      if (sameRequest()) {
        isInsightsLoading = false;
        if (notify) notifyListeners();
      }
    }
  }

  /// Loads only consented, owner-scoped Version 0.31 outcome records.
  Future<void> refreshOutcomes({bool notify = true}) async {
    if (!_canProcessData) return;
    _reconcileOutcomeSync();
    if (!outcomeConsent) {
      _outcomes = [];
      outcomeError = null;
      isOutcomeLoading = false;
      await _retryOutcomeSync();
      await _writeLocal();
      if (notify) notifyListeners();
      return;
    }
    final now = _now();
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    final revision = _sessionRevision;
    final generation = ++_outcomeRefreshGeneration;
    bool sameRequest() =>
        revision == _sessionRevision &&
        generation == _outcomeRefreshGeneration &&
        cloudUid == session?.uid;
    bool currentRequest() => sameRequest() && _canProcessData && outcomeConsent;
    isOutcomeLoading = true;
    outcomeError = null;
    if (notify) notifyListeners();
    try {
      if (session != null && repository != null) {
        await _retryOutcomeSync();
        if (!currentRequest()) return;
        final refreshed = await repository.outcomesByRange(
          session.uid,
          start: now.subtract(outcomeHistoryWindow),
          end: now.add(const Duration(days: 1)),
        );
        if (!currentRequest()) return;
        // Reads can succeed while uploads are unavailable. Keep pending local
        // records (and hide pending deletes) until their writes are acknowledged.
        final reconciled = {
          for (final outcome in refreshed) outcome.id: outcome,
        };
        if (_outcomeSyncOwnerUid == session.uid) {
          for (final entry in _pendingOutcomeWrites.entries) {
            if (entry.value == null) {
              reconciled.remove(entry.key);
            } else if (!entry.value!.observedAt.isBefore(
                  now.subtract(outcomeHistoryWindow),
                ) &&
                entry.value!.observedAt.isBefore(
                  now.add(const Duration(days: 1)),
                )) {
              reconciled[entry.key] = entry.value!;
            }
          }
        }
        final visible = reconciled.values.toList()
          ..sort((left, right) => right.observedAt.compareTo(left.observedAt));
        if (jsonEncode(_outcomes.map((item) => item.toJson()).toList()) !=
            jsonEncode(visible.map((item) => item.toJson()).toList())) {
          await _invalidateModelPreparation();
          if (!currentRequest()) return;
        }
        _outcomes = visible;
        await _writeLocal();
      } else {
        _outcomes =
            _outcomes
                .where(
                  (outcome) =>
                      !outcome.observedAt.isBefore(
                        now.subtract(outcomeHistoryWindow),
                      ) &&
                      outcome.observedAt.isBefore(
                        now.add(const Duration(days: 1)),
                      ),
                )
                .toList()
              ..sort(
                (left, right) => right.observedAt.compareTo(left.observedAt),
              );
      }
    } on Object {
      if (!currentRequest()) return;
      outcomeError = 'Private outcomes unavailable · cached records retained';
    } finally {
      if (sameRequest()) {
        isOutcomeLoading = false;
        if (notify) notifyListeners();
      }
    }
  }

  Future<void> load() async {
    // Native schedules survive app upgrades and sign-out. Clear before any
    // privacy/network early return; eligible schedule reminders are rebuilt.
    try {
      await _notificationService.cancelGuidance();
    } on Object {
      notificationError =
          'Previous reminders could not be cleared on this device.';
    }
    await _deviceTimezoneService.refresh();
    _lastLocalDay = _dayKey(_now());
    final preferences = await SharedPreferences.getInstance();
    isSignedOut = preferences.getBool(_signedOutKey) ?? false;
    _restoreModelPreparationWindow(preferences);
    final raw = preferences.getString(_storageKey);
    if (raw != null) {
      try {
        _restoreLocal(jsonDecode(raw) as Map<String, dynamic>);
        final saved = jsonDecode(raw) as Map<String, dynamic>;
        _localClockChanged =
            saved['derivedRulesVersion'] != FatigueEngine.energyModelVersion ||
            saved['deviceTimezone'] != deviceTimezoneIdentifier ||
            saved['deviceUtcOffsetMinutes'] !=
                _deviceTimezoneService.utcOffset.inMinutes;
      } on Object catch (error) {
        // Keep whatever defaults we have; do not treat a parse failure as a
        // fresh install silently — log so web/debug storage issues are visible.
        debugPrint('Tonyo failed to restore local cache: $error');
        onboardingComplete = false;
        signals = [];
        checkIns = [];
      }
    } else {
      debugPrint(
        'Tonyo local cache empty (key $_storageKey). '
        'On Flutter web, use a fixed --web-port so localhost storage persists.',
      );
    }
    await _restoreDeletionJournal(preferences);
    // A saved local profile is not an active session. Do not hydrate cloud
    // state or resume health/model work behind the welcome screen.
    if (isSignedOut || deletionPending) {
      isReady = true;
      notifyListeners();
      return;
    }
    if (isCloudAuthenticated) {
      _cloudPrivacyVerified = false;
      try {
        await _accountAuth.refreshPrivacyClaims();
      } on Object catch (error) {
        privacyOperationError =
            'Account privacy could not be verified. Reconnect and retry.';
        _recordCloudFailure(error);
        isReady = true;
        notifyListeners();
        return;
      }
      await _hydrateOrMigrateCloud();
      await _writeLocal();
      if (!outcomeConsent) await _discardPersonalizedModel();
    }
    if (!_canProcessData) {
      isReady = true;
      notifyListeners();
      return;
    }
    await _loadAi1Capture();
    if (hasPendingCloudChanges) await _pushCloud();
    if (hasPendingCoachChanges) await _retryCoachSync();
    await refreshHealthAuthorization(notify: false);
    await refreshScreenTimeAuthorization(notify: false);
    await _energyModelService.load();
    if (outcomeConsent || hasPendingOutcomeChanges) {
      await refreshOutcomes(notify: false);
    }
    if (healthAuthorized &&
        healthAuthorization == HealthAuthorizationState.authorized) {
      await _ensureContinuousHealthUpdates();
      await refreshHealthIfDue(
        reason: HealthRefreshReason.initial,
        notify: false,
      );
    }
    if (onboardingComplete) {
      await refreshScores(notify: false, forceRecalculate: _localClockChanged);
      await refreshForecasts(
        notify: false,
        forceRecalculate: _localClockChanged,
      );
      await refreshGuidance(notify: false);
      await refreshInsights(notify: false);
    }
    _localClockChanged = false;
    await _writeLocal();
    isReady = true;
    notifyListeners();
  }

  Future<void> handleAppResumed() async {
    final timezoneWasInitialized = _deviceTimezoneService.isInitialized;
    final timezoneChanged = await _deviceTimezoneService.refresh();
    final resumedAt = _now();
    final localDay = _dayKey(resumedAt);
    _localClockChanged =
        _localClockChanged ||
        (timezoneWasInitialized && timezoneChanged) ||
        (_lastLocalDay != null && _lastLocalDay != localDay);
    _lastLocalDay = localDay;
    // Nap recovery changes with elapsed time even when no input or region has
    // changed. Refresh on foreground entry, with a one-minute threshold to
    // avoid repeated derived-data queries during immediate lifecycle events.
    final derivedViewsNeedRefresh =
        _localClockChanged ||
        _napScoreNeedsRefresh(
          _scoreSnapshot,
          resumedAt,
          minimumAge: const Duration(minutes: 1),
        );
    if (_localClockChanged) {
      // Supersede old-zone async responses before waiting for privacy/network.
      _scoreRefreshGeneration++;
      _forecastRefreshGeneration++;
      _guidanceRefreshGeneration++;
      _notificationRefreshGeneration++;
      _insightsRefreshGeneration++;
      _scoreSnapshot = null;
      _todaySignals = [];
      _forecastsByDay.clear();
      _recommendations = [];
      _riskAlerts = [];
      _insightsSnapshot = null;
      isEnergyScoreLoading = false;
      isForecastLoading = false;
      isGuidanceLoading = false;
      isInsightsLoading = false;
      _notificationScheduleConfirmed = false;
      try {
        await _notificationService.cancelGuidance();
      } on Object {
        /* Foreground regeneration retries guidance scheduling. */
      }
    }
    notifyListeners();
    if (isSignedOut || deletionPending || isPrivacyBusy) return;
    final revision = _sessionRevision;
    final owner = cloudUid;
    final generation = ++_privacyRefreshGeneration;
    bool current() =>
        revision == _sessionRevision &&
        owner == cloudUid &&
        generation == _privacyRefreshGeneration &&
        !isSignedOut &&
        !isPrivacyBusy;
    if (isCloudAuthenticated && cloudRepository != null) {
      final recoveringConnection =
          !_cloudPrivacyVerified || cloudSyncError != null;
      try {
        if (!await _refreshCloudPrivacy(current)) return;
        if (isReady && (_syncBaseline == null || _syncOwnerUid != owner)) {
          await _hydrateOrMigrateCloud(isCurrent: current);
          if (!current()) return;
        }
        if (recoveringConnection &&
            _canProcessData &&
            !hasPendingCloudChanges) {
          await _pushCloud();
          if (!current()) return;
        }
      } on Object catch (error) {
        if (!current()) return;
        _cloudPrivacyVerified = false;
        _recordCloudFailure(error);
        privacyOperationError =
            'Privacy status could not be verified. Reconnect and reopen Tonyo before new collection.';
      }
    }
    if (!current()) return;
    if (!_canProcessData) {
      _unloadAi1Capture();
      _invalidateHealthWork();
      await _invalidateModelPreparation();
      await _disableContinuousHealthUpdates();
      healthBackgroundRefreshEnabled = false;
      _energyModelService.unload();
      try {
        await _notificationService.cancelGuidance();
      } on Object {
        /* fail closed collection */
      }
      notifyListeners();
      return;
    }
    await _loadAi1Capture();
    if (!current()) return;
    final hadPendingInputs = hasPendingCloudChanges;
    if (hadPendingInputs) {
      await _pushCloud();
      if (!current()) return;
    }
    if (hasPendingOutcomeChanges) {
      await refreshOutcomes(notify: false);
      if (!current()) return;
    }
    if (hasPendingCoachChanges) {
      await _retryCoachSync();
      if (!current()) return;
    }
    scheduleCloudRetry();
    final status = await refreshHealthAuthorization(notify: false);
    await refreshScreenTimeAuthorization(notify: false);
    if (!current()) return;
    if ((derivedViewsNeedRefresh ||
            (hadPendingInputs && !hasPendingCloudChanges)) &&
        onboardingComplete) {
      if (_localClockChanged) {
        // Recreate local DateTime views from stored instants after travel/DST.
        signals = signals
            .map((item) => SignalReading.fromJson(item.toJson()))
            .toList();
        checkIns = checkIns
            .map((item) => DailyCheckIn.fromJson(item.toJson()))
            .toList();
      }
      _scoreSnapshot = null;
      _forecastsByDay.clear();
      await refreshScores(notify: false, forceRecalculate: true);
      if (!current()) return;
      await refreshForecasts(notify: false, forceRecalculate: true);
      if (!current()) return;
      await refreshGuidance(notify: false);
      if (!current()) return;
      await refreshInsights(notify: false);
      if (!current()) return;
      _localClockChanged = false;
      await _writeLocal();
    }
    if (status == HealthAuthorizationState.authorized && healthAuthorized) {
      await _ensureContinuousHealthUpdates();
      await refreshHealthIfDue(reason: HealthRefreshReason.foreground);
    } else {
      notifyListeners();
    }
  }

  /// A failed offline launch must be recoverable without passing the privacy
  /// mutation gate first. Server verification still precedes any upload.
  Future<bool> _refreshCloudPrivacy(bool Function() current) async {
    final uid = cloudUid;
    final repository = cloudRepository;
    if (uid == null || repository == null) return false;
    await _accountAuth.refreshPrivacyClaims();
    if (!current() || deletionPending) return false;
    final state = await repository.readAccountPrivacy(uid);
    if (!current() || deletionPending) return false;
    // Do not reassign another account's cached inputs to this session.
    final owners = [
      _privacyOwnerUid,
      _syncOwnerUid,
      _cloudMetadataUid,
    ].whereType<String>().toSet();
    final hasLocalData =
        onboardingComplete ||
        accountEmail != null ||
        signals.isNotEmpty ||
        checkIns.isNotEmpty ||
        _outcomes.isNotEmpty;
    if (owners.any((owner) => owner != uid) ||
        (owners.isEmpty && hasLocalData)) {
      throw StateError('Sign in again to restore this account.');
    }
    _privacyConsent = state.consent;
    _privacyOwnerUid = uid;
    _cloudPrivacyVerified = true;
    privacyOperationError = null;
    outcomeConsent = state.outcomeConsent;
    outcomeConsentUpdatedAt = state.outcomeConsentUpdatedAt;
    _reconcileOutcomeSync();
    if (state.deletionPending) await _saveDeletionJournal(uid, 'requested');
    if (!current()) return false;
    if (!outcomeConsent) await _discardPersonalizedModel();
    if (!current()) return false;
    await _writeLocal();
    return current();
  }

  // Kept as a private call-site name for the existing lifecycle path. All
  // estimates now age, not a special nap reward (which no longer exists).
  static bool _napScoreNeedsRefresh(
    ScoreSnapshot? snapshot,
    DateTime at, {
    Duration minimumAge = Duration.zero,
  }) {
    if (snapshot == null) return true;
    if (snapshot.energyModelVersion != FatigueEngine.energyModelVersion ||
        snapshot.cognitiveModelVersion != FatigueEngine.cognitiveModelVersion ||
        snapshot.day == null ||
        !sameLocalDay(snapshot.day!, at)) {
      return true;
    }
    final calculated = snapshot.calculatedAt;
    if (calculated == null || calculated.isAfter(at)) return true;
    return at.difference(calculated) >= const Duration(minutes: 1) &&
        at.difference(calculated) >= minimumAge;
  }

  Future<void> completeOnboarding(
    UserProfile newProfile, {
    String? email,
    String? password,
    bool signInToExistingAccount = false,
  }) async {
    final normalizedEmail = email?.trim().toLowerCase();
    if (!signInToExistingAccount && !privacyFeaturesAllowed) {
      throw StateError('Complete privacy review before creating an account.');
    }
    if (cloudEnabled) {
      if (normalizedEmail == null ||
          normalizedEmail.isEmpty ||
          password == null ||
          password.isEmpty) {
        throw ArgumentError('Email and password are required for cloud setup.');
      }
      if (signInToExistingAccount) {
        await signIn(email: normalizedEmail, password: password);
        await completeAuthenticatedOnboarding(newProfile);
        return;
      } else {
        await _accountAuth.register(email: normalizedEmail, password: password);
        final uid = cloudUid;
        if (uid == null || cloudRepository == null) {
          throw StateError('Cloud account storage is unavailable.');
        }
        _privacyConsent = await cloudRepository!.savePrivacyConsent(
          uid,
          _privacyConsent!,
        );
        _privacyOwnerUid = uid;
        _cloudPrivacyVerified = true;
        await _clearModelPreparationWindow();
        await _invalidateModelPreparation();
      }
    }
    await _finishOnboarding(newProfile, email: normalizedEmail);
  }

  /// Finish setup only after the account form has authenticated with Firebase.
  /// Returning accounts with a saved profile must never be replaced by defaults.
  Future<void> completeAuthenticatedOnboarding(UserProfile newProfile) async {
    _requirePrivacy();
    if (!cloudEnabled || !isCloudAuthenticated) {
      throw StateError('Sign in before finishing account setup.');
    }
    if (cloudSyncError != null) {
      throw StateError('Restore cloud data before finishing account setup.');
    }
    if (onboardingComplete) return;
    await _finishOnboarding(newProfile);
  }

  Future<void> _finishOnboarding(
    UserProfile newProfile, {
    String? email,
  }) async {
    if (!privacyFeaturesAllowed) {
      throw StateError('Complete privacy review before setup.');
    }
    if (cloudUid != null &&
        cloudRepository != null &&
        (_syncBaseline == null || _syncOwnerUid != cloudUid)) {
      final uid = cloudUid!;
      final revision = _sessionRevision;
      final remote = await cloudRepository!.readUser(uid);
      if (revision != _sessionRevision || uid != cloudUid || remote == null) {
        throw StateError('Account setup changed. Please retry.');
      }
      _syncOwnerUid = uid;
      _syncBaseline = InputSyncSnapshot.fromState(remote);
    }
    profile = newProfile;
    accountEmail = _accountAuth.currentSession?.email ?? email ?? accountEmail;
    onboardingComplete = true;
    if (signals.isEmpty) {
      signals = buildDemoSignals(DateTime.now());
      checkIns = buildDemoCheckIns(DateTime.now());
    }
    await _setSignedOut(false);
    await _commit(energyInputsChanged: true);
    await _loadAi1Capture();
  }

  Future<void> signIn({required String email, required String password}) async {
    if (isPrivacyBusy) {
      throw StateError('Finish pending privacy operations first.');
    }
    if (!cloudEnabled) throw StateError('Firebase is not configured.');
    final wasSignedOut = isSignedOut;
    // A rejected password must not change local account state or prep caches.
    await _accountAuth.signIn(email: email, password: password);
    _unloadAi1Capture();
    _sessionRevision++;
    _invalidateHealthWork();
    _cloudPrivacyVerified = false;
    try {
      await _accountAuth.refreshPrivacyClaims();
    } on Object {
      cloudSyncError =
          'Account privacy could not be verified. Reconnect and retry sign-in.';
      rethrow;
    }
    final preferences = await SharedPreferences.getInstance();
    await _restoreDeletionJournal(preferences);
    if (deletionPending) {
      await _setSignedOut(false);
      notifyListeners();
      return;
    }
    await _clearModelPreparationWindow();
    await _invalidateModelPreparation();
    await _hydrateOrMigrateCloud();
    if (cloudSyncError != null) {
      throw StateError(
        'Your account data could not be restored. Please retry.',
      );
    }
    await _setSignedOut(false);
    await _writeLocal();
    if (!_canProcessData) {
      notifyListeners();
      return;
    }
    await _loadAi1Capture();
    if (hasPendingCloudChanges) await _pushCloud();
    if (hasPendingCoachChanges) await _retryCoachSync();
    if (!outcomeConsent) await _discardPersonalizedModel();
    if (outcomeConsent || hasPendingOutcomeChanges) {
      await refreshOutcomes(notify: false);
    }
    if (onboardingComplete) {
      await refreshScores(notify: false);
      await refreshForecasts(notify: false);
      await refreshGuidance(notify: false);
      await refreshInsights(notify: false);
      await _setSignedOut(false);
      await _energyModelService.load();
      _scoreSnapshot = _personalizeEnergy(score, signals, checkIns, _now());
      if (wasSignedOut) {
        await handleAppResumed();
        if (notificationsEnabled) await refreshNotifications(notify: false);
      }
    }
    notifyListeners();
  }

  // Password recovery never touches local data or the current session.
  void _requirePasswordAccountAccess() {
    if (isPrivacyBusy) {
      throw StateError('Finish pending privacy operations first.');
    }
    if (!cloudEnabled) throw StateError('Firebase is not configured.');
  }

  Future<void> sendPasswordReset({required String email}) async {
    _requirePasswordAccountAccess();
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Enter your account email.');
    }
    await _accountAuth.sendPasswordReset(email: normalizedEmail);
  }

  Future<String> verifyPasswordResetCode(String code) async {
    _requirePasswordAccountAccess();
    return _accountAuth.verifyPasswordResetCode(code.trim());
  }

  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {
    _requirePasswordAccountAccess();
    await _accountAuth.confirmPasswordReset(
      code: code.trim(),
      newPassword: newPassword,
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _requirePasswordAccountAccess();
    if (!isCloudAuthenticated) {
      throw StateError('Sign in before changing the password.');
    }
    await _accountAuth.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  Future<void> _setSignedOut(bool value) async {
    await _writeSignedOutPreference(value);
    isSignedOut = value;
  }

  Future<void> _writeSignedOutPreference(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setBool(_signedOutKey, value)) {
      throw StateError('Could not save the device session state.');
    }
  }

  /// Local mode has no password authentication. Explicitly resume the same
  /// saved profile, without registering or rerunning profile/demo setup.
  Future<void> resumeLocalProfile() async {
    if (!canResumeLocalProfile) {
      throw StateError('No signed-out local profile is available.');
    }
    await _setSignedOut(false);
    await _loadAi1Capture();
    await refreshScores(notify: false);
    await refreshForecasts(notify: false);
    await refreshGuidance(notify: false);
    await refreshInsights(notify: false);
    await handleAppResumed();
    notifyListeners();
  }

  Future<void> signOut() async {
    if (isPrivacyBusy) {
      throw StateError('Wait for the privacy operation to finish.');
    }
    if (isSignedOut || _isSigningOut) return;
    _isSigningOut = true;
    _notificationScheduleConfirmed = false;
    _notificationPlan = NotificationPlan(
      state: notificationsEnabled
          ? NotificationPlanState.noFutureWindows
          : NotificationPlanState.disabled,
    );
    _cloudRetryTimer?.cancel();
    _cloudRetryTimer = null;
    _sessionRevision += 1;
    _unloadAi1Capture();
    _invalidateHealthWork();
    isForecastLoading = false;
    isGuidanceLoading = false;
    isInsightsLoading = false;
    isOutcomeLoading = false;
    isCloudSyncing = false;
    _cloudSyncActivities.clear();
    isNotificationSyncing = false;
    isEnergyScoreLoading = false;
    _energyModelService.unload();
    try {
      await _clearModelPreparationWindow();
      await _invalidateModelPreparation();
      await _disableContinuousHealthUpdates();
      healthBackgroundRefreshEnabled = false;
      try {
        await _notificationService.cancelGuidance();
      } on Object {
        // Signing out must still succeed if the platform scheduler is unavailable.
      }
      // Persist the gate before ending auth so a restart cannot reopen the cache.
      // A failed auth sign-out rolls it back and retains the existing screen.
      await _writeSignedOutPreference(true);
      try {
        await _accountAuth.signOut();
      } on Object {
        await _writeSignedOutPreference(false);
        rethrow;
      }
      isSignedOut = true;
      cloudSyncError = null;
      insightsLoadedFromCloud = false;
      _notificationPlan = const NotificationPlan(
        state: NotificationPlanState.disabled,
      );
      notificationPermission = NotificationPermissionState.unknown;
      notifyListeners();
    } finally {
      _isSigningOut = false;
    }
  }

  Future<void> updateProfile(UserProfile value) async {
    final ensureCurrent = _beginMutation();
    if (value.wakeHour != profile.wakeHour ||
        value.bedHour != profile.bedHour) {
      final error = ScheduleLogic.validationError(profile, value);
      if (error != null) throw ArgumentError(error);
    }
    profile = value;
    await _commit(forecastInputsChanged: true);
    ensureCurrent();
  }

  Future<void> setPreferredLanguage(String value) async {
    final ensureCurrent = _beginMutation();
    // SharedPreferences can finish overlapping platform writes out of order.
    // Serialize choices so a slower earlier save cannot replace the latest one.
    Future<void> save() async {
      ensureCurrent();
      final previous = profile;
      final changed = profile.copyWith(preferredLanguage: value);
      if (changed.preferredLanguage == previous.preferredLanguage) return;
      profile = changed;
      notifyListeners();
      try {
        await _writeLocal();
      } on Object {
        ensureCurrent();
        if (profile.preferredLanguage == changed.preferredLanguage) {
          profile = profile.copyWith(
            preferredLanguage: previous.preferredLanguage,
          );
        }
        // SharedPreferences updates its memory cache before confirming a write.
        // A failed preference change must not look saved to the next reader.
        try {
          await (await SharedPreferences.getInstance()).reload();
        } on Object {
          // Preserve the last confirmed in-memory choice even if reload fails.
        }
        notifyListeners();
        rethrow;
      }
      ensureCurrent();
      await _pushCloud();
      ensureCurrent();
      // Language is a presentation preference. It does not invalidate scores,
      // training preparation or the user's protected-sleep schedule.
      notifyListeners();
    }

    final previousWrite = _languageWriteQueue;
    final pending = previousWrite == null
        ? save()
        : previousWrite.then((_) => save());
    // A failed choice is reported to its caller without blocking the next save.
    final tail = pending.catchError((Object _) {});
    _languageWriteQueue = tail;
    try {
      await pending;
    } finally {
      if (identical(_languageWriteQueue, tail)) _languageWriteQueue = null;
    }
  }

  Future<void> addSignal(SignalType type, double value, {String? note}) async {
    final ensureCurrent = _beginMutation();
    final now = _now();
    signals.insert(
      0,
      SignalReading(
        id: 'manual-${now.microsecondsSinceEpoch}-${signals.length}',
        type: type,
        value: value,
        timestamp: now,
        recordedAt: now,
        note: note,
      ),
    );
    await _commit(energyInputsChanged: true);
    ensureCurrent();
  }

  Future<void> saveActivityLog({
    String? id,
    double? hydrationLiters,
    double? studyHours,
    double? exerciseHours,
    double? screenTimeHours,
    DateTime? timestamp,
  }) async {
    final ensureCurrent = _beginMutation();
    final hydration = hydrationLiters;
    final study = studyHours;
    final exercise = exerciseHours;
    final screenTime = screenTimeHours;
    if (!ActivityLogLogic.hasAnyLoggedValue(
      hydrationLiters: hydration,
      studyHours: study,
      exerciseHours: exercise,
      screenTimeHours: screenTime,
    )) {
      throw ArgumentError('Enter at least one activity value.');
    }
    final values = <SignalType, double?>{
      SignalType.hydration: hydration,
      SignalType.study: study,
      SignalType.exercise: exercise,
      SignalType.screenTime: screenTime,
    };
    for (final entry in values.entries) {
      if (entry.value == null) continue;
      final message = ActivityLogEntry.validationMessage(
        entry.key,
        entry.value!,
      );
      if (message != null) {
        throw ArgumentError.value(entry.value, entry.key.name, message);
      }
    }
    final now = _now();
    final groupId =
        id ?? 'activity-${now.microsecondsSinceEpoch}-${signals.length}';
    final recordedAt = timestamp ?? now;
    if (signals.any((item) => item.groupId == groupId)) {
      await _discardPersonalizedModel();
      ensureCurrent();
    }
    signals.removeWhere((item) => item.groupId == groupId);
    signals.insertAll(
      0,
      values.entries
          .where((entry) => entry.value != null)
          .map(
            (entry) => SignalReading(
              id: '$groupId-${entry.key.name}',
              groupId: groupId,
              type: entry.key,
              value: entry.value!,
              timestamp: recordedAt,
              recordedAt: now,
              note: switch (entry.key) {
                SignalType.hydration ||
                SignalType.exercise => ActivitySyncLogic.manualCorrectionNote,
                _ => null,
              },
            ),
          ),
    );
    await _commit(energyInputsChanged: true);
    ensureCurrent();
  }

  Future<void> deleteActivityLog(String id) async {
    final ensureCurrent = _beginMutation();
    await _discardPersonalizedModel();
    ensureCurrent();
    signals.removeWhere((item) => item.groupId == id);
    await _commit(energyInputsChanged: true);
    ensureCurrent();
  }

  Future<void> addSleep({
    String? id,
    required DateTime bedtime,
    required DateTime wakeTime,
    required double quality,
    SleepKind kind = SleepKind.mainSleep,
  }) async {
    final ensureCurrent = _beginMutation();
    final captureGeneration = ai1CaptureEnabled ? _ai1CaptureGeneration : null;
    final normalized = SleepLogEntry.normalizeOvernightPair(
      bedtime: bedtime,
      wakeTime: wakeTime,
    );
    final start = normalized.$1;
    final end = normalized.$2;
    final validation = SleepLogEntry.validationMessage(
      bedtime: start,
      wakeTime: end,
      quality: quality,
      kind: kind,
    );
    if (validation != null) throw ArgumentError(validation);
    final hours = end.difference(start).inMinutes / 60;
    final recordedAt = _now();
    final groupId =
        id ?? 'sleep-${recordedAt.microsecondsSinceEpoch}-${signals.length}';
    final existing = signals.any((item) => item.groupId == groupId);
    if (existing) {
      await _discardPersonalizedModel();
      ensureCurrent();
    }
    signals.removeWhere((item) => item.groupId == groupId);
    signals.insertAll(0, [
      SignalReading(
        id: '$groupId-duration',
        groupId: groupId,
        type: kind == SleepKind.nap ? SignalType.nap : SignalType.sleep,
        value: hours,
        timestamp: end,
        recordedAt: recordedAt,
        quality: quality / 5,
        note: '${_clock(start)}–${_clock(end)} · quality ${quality.round()}/5',
      ),
      if (kind == SleepKind.mainSleep)
        SignalReading(
          id: '$groupId-bedtime',
          groupId: groupId,
          type: SignalType.bedtime,
          value: start.hour + start.minute / 60,
          timestamp: start,
          recordedAt: recordedAt,
        ),
    ]);
    await _commit(
      energyInputsChanged: true,
      ai1Capture: _captureIntent(
        () => Ai1CaptureObservation.manualSleep(
          sourceId: groupId,
          startedAt: start,
          endedAt: end,
          durationHours: hours,
          isNap: kind == SleepKind.nap,
          originalLocal: !existing,
        ),
        captureGeneration,
      ),
    );
    ensureCurrent();
  }

  Future<void> deleteSleepLog(String id) async {
    final ensureCurrent = _beginMutation();
    await _purgeAi1Source('sleepLogs', id);
    ensureCurrent();
    await _discardPersonalizedModel();
    ensureCurrent();
    signals.removeWhere((item) => item.groupId == id);
    await _commit(energyInputsChanged: true);
    ensureCurrent();
  }

  Future<void> addCheckIn({
    String? id,
    required double energy,
    required double mood,
    required double stress,
    String note = '',
    DateTime? timestamp,
    CheckInPeriod? period,
  }) async {
    final ensureCurrent = _beginMutation();
    final linkOutcome = outcomeConsent;
    final consentAt = outcomeConsentUpdatedAt;
    if (!CheckInLogic.isValidRating(energy) ||
        !CheckInLogic.isValidRating(mood) ||
        !CheckInLogic.isValidRating(stress)) {
      throw ArgumentError(
        'Energy, mood, and stress must each be between '
        '${CheckInLogic.minRating} and ${CheckInLogic.maxRating}',
      );
    }
    final when = timestamp ?? _now();
    final checkInId = id ?? 'checkin-${when.microsecondsSinceEpoch}';
    final existing = checkIns.where((item) => item.id == checkInId).firstOrNull;
    if (existing?.isResearchCheckIn ?? false) {
      throw ArgumentError(
        'A versioned self-report cannot become a legacy check-in.',
      );
    }
    if (existing?.originalLegacyRatings != null) {
      throw ArgumentError(
        'Original legacy-scale responses are read-only. Create a new check-in.',
      );
    }
    if (existing != null) {
      await _discardPersonalizedModel();
      ensureCurrent();
    }
    final checkIn = DailyCheckIn(
      id: checkInId,
      timestamp: when,
      recordedAt: _now(),
      energy: CheckInLogic.clampRating(energy),
      mood: CheckInLogic.clampRating(mood),
      stress: CheckInLogic.clampRating(stress),
      // Retain the historical default only for legacy callers. Editing an
      // existing response must not reclassify its period after travel.
      period: period ?? existing?.period ?? CheckInLogic.periodFor(when),
      note: note,
    );
    checkIns.removeWhere((item) => item.id == checkInId);
    checkIns.insert(0, checkIn);
    await _commit(energyInputsChanged: true);
    ensureCurrent();
    // A slow save must retain its original consent receipt. Enabling learning
    // during that save does not authorize a previously collected response.
    if (linkOutcome &&
        outcomeConsent &&
        _sameOutcomeConsentAt(consentAt, outcomeConsentUpdatedAt)) {
      await _saveOutcome(
        OutcomeRecord(
          id: 'energy-checkin-$checkInId',
          type: OutcomeType.observedEnergy,
          value: checkIn.energy!,
          observedAt: checkIn.timestamp,
          recordedAt: _now(),
          source: OutcomeSource.checkIn,
          sourceId: checkInId,
        ),
        sourceIsCurrent: () => checkIns.any(
          (item) =>
              item.id == checkIn.id &&
              jsonEncode(item.toJson()) == jsonEncode(checkIn.toJson()),
        ),
      );
    }
  }

  /// Stores a custom draft measurement independently of legacy model inputs.
  /// The explicit period is the respondent's choice, not inferred from time.
  Future<void> saveSelfReportCheckIn({
    String? id,
    required CheckInPeriod period,
    double? energy,
    double? fatigue,
    double? sleepiness,
    double? focus,
    double? mood,
    double? stress,
    String note = '',
    required Map<String, dynamic> questionnaireSnapshot,
    required String questionnaireLanguage,
    String? sharedHeading,
    DateTime? timestamp,
  }) async {
    final ensureCurrent = _beginMutation();
    final captureGeneration = ai1CaptureEnabled ? _ai1CaptureGeneration : null;
    final when = timestamp ?? _now();
    final checkInId = id ?? 'checkin-${when.microsecondsSinceEpoch}';
    if (checkInId.isEmpty || checkInId.contains('/')) {
      throw ArgumentError('Invalid check-in identifier.');
    }
    final existing = checkIns.where((item) => item.id == checkInId).firstOrNull;
    if (existing != null &&
        existing.questionnaireVersion != CheckInMeasurement.currentVersion) {
      throw ArgumentError(
        'Keep this response in its original measurement format.',
      );
    }
    final observedAt = existing?.timestamp ?? when;
    final local = _deviceTimezoneService.localTime(observedAt);
    String two(int value) => value.toString().padLeft(2, '0');
    final checkIn = DailyCheckIn(
      id: checkInId,
      timestamp: observedAt,
      recordedAt: _now(),
      period: period,
      energy: energy,
      fatigue: fatigue,
      sleepiness: sleepiness,
      focus: focus,
      mood: mood,
      stress: stress,
      note: note,
      localDate:
          existing?.localDate ??
          '${local.year}-${two(local.month)}-${two(local.day)}',
      timezone: existing == null ? deviceTimezoneIdentifier : existing.timezone,
      utcOffsetMinutes:
          existing?.utcOffsetMinutes ?? local.timeZoneOffset.inMinutes,
      questionnaireVersion: CheckInMeasurement.currentVersion,
      questionnaireLanguage:
          existing?.questionnaireLanguage ?? questionnaireLanguage,
      source: 'selfReport',
      questionnaireSnapshot:
          (jsonDecode(
                    jsonEncode(
                      existing?.questionnaireSnapshot ?? questionnaireSnapshot,
                    ),
                  )
                  as Map)
              .cast<String, dynamic>(),
    );
    final validation = checkIn.researchValidationMessage;
    if (validation != null) throw ArgumentError(validation);
    checkIns.removeWhere((item) => item.id == checkInId);
    checkIns.insert(0, checkIn);
    // Raw preparation caches become stale, but score coefficients, fitted
    // artifacts, training-attempt safeguards and reminders are unchanged.
    await _commit(
      ai1Capture: _captureIntent(
        () => Ai1CaptureObservation.selfReport(
          checkIn: checkIn,
          sharedHeading:
              sharedHeading ??
              AppLocalizations(
                questionnaireLanguage,
              ).text('How do you feel right now?'),
          originalLocal: existing == null,
        ),
        captureGeneration,
      ),
    );
    ensureCurrent();
    // Deliberately no legacy observed-energy outcome: this wording/version has
    // no approved compatibility contract with that model's target.
  }

  Future<void> addReactionResult(
    double averageMs, {
    String? note,
    String? resultId,
    DateTime? observedAt,
  }) async {
    final ensureCurrent = _beginMutation();
    final linkOutcome = outcomeConsent;
    final consentAt = outcomeConsentUpdatedAt;
    if (!ReactionTestLogic.isValidReaction(averageMs)) {
      throw ArgumentError(
        'Reaction average must be between '
        '${ReactionTestLogic.minValidMs} and ${ReactionTestLogic.maxValidMs} ms',
      );
    }
    observedAt ??= _now();
    final signalId =
        resultId ??
        'manual-${observedAt.microsecondsSinceEpoch}-${signals.length}';
    if (signalId.contains('/') || signalId.isEmpty || !averageMs.isFinite) {
      throw ArgumentError('Invalid reaction result.');
    }
    final signal = SignalReading(
      id: signalId,
      type: SignalType.reactionTime,
      value: averageMs,
      timestamp: observedAt,
      recordedAt: _now(),
      note: note ?? 'Three-round reaction test',
    );
    signals.removeWhere((item) => item.id == signalId);
    signals.insert(0, signal);
    await _commit(energyInputsChanged: true);
    ensureCurrent();
    if (linkOutcome &&
        outcomeConsent &&
        _sameOutcomeConsentAt(consentAt, outcomeConsentUpdatedAt)) {
      await _saveOutcome(
        OutcomeRecord(
          id: 'reaction-$signalId',
          type: OutcomeType.cognitiveReaction,
          value: averageMs,
          observedAt: observedAt,
          recordedAt: _now(),
          source: OutcomeSource.reactionSignal,
          sourceId: signalId,
        ),
        sourceIsCurrent: () => signals.any(
          (item) =>
              item.id == signal.id &&
              jsonEncode(item.toJson()) == jsonEncode(signal.toJson()),
        ),
      );
    }
  }

  Future<void> recordObservedEnergy(
    double energy, {
    String? recommendationId,
    DateTime? observedAt,
  }) async {
    _requirePrivacy();
    if (!outcomeConsent) {
      throw StateError('Outcome learning requires explicit consent.');
    }
    if (!CheckInLogic.isValidRating(energy)) {
      throw ArgumentError('Observed energy must be between 1 and 10.');
    }
    if (recommendationId != null) {
      final recommendation = _recommendations
          .where((item) => item.id == recommendationId)
          .firstOrNull;
      if (recommendation?.status != RecommendationStatus.completed) {
        throw StateError('Complete the recommendation before rating energy.');
      }
    }
    final when = observedAt ?? _now();
    final sourceId = recommendationId ?? '${when.microsecondsSinceEpoch}';
    await _saveOutcome(
      OutcomeRecord(
        id: 'energy-coach-$sourceId',
        type: OutcomeType.observedEnergy,
        value: CheckInLogic.clampRating(energy),
        observedAt: when,
        recordedAt: _now(),
        source: OutcomeSource.coach,
        sourceId: sourceId,
        recommendationId: recommendationId,
      ),
    );
  }

  Future<void> _saveOutcome(
    OutcomeRecord outcome, {
    bool Function()? sourceIsCurrent,
  }) async {
    final ensureCurrent = _beginMutation();
    final consentAt = outcomeConsentUpdatedAt;
    void ensureConsent() {
      ensureCurrent();
      if (!outcomeConsent ||
          !_sameOutcomeConsentAt(consentAt, outcomeConsentUpdatedAt)) {
        throw StateError(
          'Outcome learning consent changed. The record was stopped.',
        );
      }
    }

    if (!outcomeConsent) {
      throw StateError('Outcome learning requires explicit consent.');
    }
    if (sourceIsCurrent != null && !sourceIsCurrent()) return;
    await _invalidateModelPreparation();
    ensureConsent();
    if (_outcomes.any((item) => item.id == outcome.id)) {
      await _discardPersonalizedModel();
      ensureConsent();
    }
    // Edits and deletions can complete while the source save or model-cache
    // work is pending. Never restore an obsolete label or an orphaned outcome.
    if (sourceIsCurrent != null && !sourceIsCurrent()) return;
    _queueOutcomeWrite(outcome.id, outcome);
    _outcomes.removeWhere((item) => item.id == outcome.id);
    _outcomes.insert(0, outcome);
    _outcomeRefreshGeneration++;
    isOutcomeLoading = false;
    outcomeError = null;
    notifyListeners();
    await _writeLocal();
    ensureCurrent();
    await _retryOutcomeSync();
    ensureCurrent();
    notifyListeners();
  }

  Future<void> deleteSignal(String id) async {
    final ensureCurrent = _beginMutation();
    final source = signals.where((item) => item.id == id).firstOrNull;
    if (source?.groupId != null) {
      await _purgeAi1Source('sleepLogs', source!.groupId!);
      ensureCurrent();
    }
    await _discardPersonalizedModel();
    ensureCurrent();
    signals.removeWhere((item) => item.id == id);
    await _commit(energyInputsChanged: true);
    ensureCurrent();
    await _deleteOutcome('reaction-$id');
  }

  Future<void> deleteCheckIn(String id) async {
    final ensureCurrent = _beginMutation();
    await _purgeAi1Source('checkIns', id);
    ensureCurrent();
    final researchOnly =
        checkIns
            .where((item) => item.id == id)
            .firstOrNull
            ?.isResearchCheckIn ??
        false;
    if (!researchOnly) await _discardPersonalizedModel();
    ensureCurrent();
    checkIns.removeWhere((item) => item.id == id);
    await _commit(energyInputsChanged: !researchOnly);
    ensureCurrent();
    await _deleteOutcome('energy-checkin-$id');
  }

  Future<void> _deleteOutcome(String outcomeId) async {
    final ensureCurrent = _beginMutation();
    await _invalidateModelPreparation();
    ensureCurrent();
    _outcomes.removeWhere((item) => item.id == outcomeId);
    _queueOutcomeWrite(outcomeId, null);
    _outcomeRefreshGeneration++;
    isOutcomeLoading = false;
    await _writeLocal();
    ensureCurrent();
    await _retryOutcomeSync();
    ensureCurrent();
    notifyListeners();
  }

  Future<void> setRecommendationStatus(
    String id,
    RecommendationStatus status,
  ) async {
    final ensureCurrent = _beginMutation();
    final record = _recommendations.where((item) => item.id == id).firstOrNull;
    if (record == null) {
      throw StateError(
        'This recommendation is no longer available. Refresh Coach.',
      );
    }
    _guidanceRefreshGeneration++;
    isGuidanceLoading = false;
    _recommendationStatuses[id] = status;
    _recommendations = _recommendations
        .map((item) => item.id == id ? item.copyWith(status: status) : item)
        .toList();
    _queueRecommendationAction(record, status: status);
    guidanceError = hasPendingCoachChanges
        ? 'Coach changes saved on this device · cloud update pending'
        : null;
    notifyListeners();
    await _writeLocal();
    ensureCurrent();
    await _retryCoachSync();
    ensureCurrent();
    notifyListeners();
  }

  Future<void> setRecommendationFeedback(String id, bool helpful) async {
    final ensureCurrent = _beginMutation();
    final record = _recommendations.where((item) => item.id == id).firstOrNull;
    if (record == null) {
      throw StateError(
        'This recommendation is no longer available. Refresh Coach.',
      );
    }
    _guidanceRefreshGeneration++;
    isGuidanceLoading = false;
    _recommendationFeedback[id] = helpful;
    _recommendations = _recommendations
        .map((item) => item.id == id ? item.copyWith(helpful: helpful) : item)
        .toList();
    _queueRecommendationAction(record, helpful: helpful);
    guidanceError = hasPendingCoachChanges
        ? 'Coach changes saved on this device · cloud update pending'
        : null;
    notifyListeners();
    await _writeLocal();
    ensureCurrent();
    await _retryCoachSync();
    ensureCurrent();
    notifyListeners();
  }

  Future<void> dismissRiskAlert(String id) async {
    final ensureCurrent = _beginMutation();
    final record = _riskAlerts.where((item) => item.id == id).firstOrNull;
    if (record == null) {
      throw StateError('This alert is no longer available. Refresh Coach.');
    }
    _guidanceRefreshGeneration++;
    isGuidanceLoading = false;
    _dismissedRiskAlertIds.add(id);
    _riskAlerts = _riskAlerts
        .map((item) => item.id == id ? item.copyWith(dismissed: true) : item)
        .toList();
    if (cloudUid != null && cloudRepository != null) {
      _reconcileCoachSync();
      _coachSyncOwnerUid = cloudUid;
      _pendingAlertWrites[id] = record.copyWith(dismissed: true);
    }
    guidanceError = hasPendingCoachChanges
        ? 'Coach changes saved on this device · cloud update pending'
        : null;
    notifyListeners();
    await _writeLocal();
    ensureCurrent();
    await _retryCoachSync();
    ensureCurrent();
    await refreshNotifications();
    ensureCurrent();
    notifyListeners();
  }

  Future<NotificationPermissionState> setNotifications(bool value) =>
      _setNotificationPreferences(enabled: value);

  Future<void> setCoachPlanNotifications(bool value) async {
    await _setNotificationPreferences(
      coachPlan: value,
      enabled: value && !notificationsEnabled ? true : null,
    );
  }

  Future<void> setCrashNotifications(bool value) async {
    await _setNotificationPreferences(crash: value);
  }

  Future<void> setRecoveryNotifications(bool value) async {
    await _setNotificationPreferences(recovery: value);
  }

  Future<NotificationPermissionState> _setNotificationPreferences({
    bool? enabled,
    bool? coachPlan,
    bool? crash,
    bool? recovery,
  }) async {
    _requirePrivacy();
    final revision = _sessionRevision;
    final uid = cloudUid;
    final generation = ++_notificationPreferenceGeneration;
    var ownedRefreshGeneration = ++_notificationRefreshGeneration;
    bool sameRequest() =>
        revision == _sessionRevision &&
        uid == cloudUid &&
        generation == _notificationPreferenceGeneration;
    bool current() => sameRequest() && _canProcessData;
    final previous = (
      enabled: notificationsEnabled,
      coach: coachPlanNotificationsEnabled,
      crash: crashNotificationsEnabled,
      recovery: recoveryNotificationsEnabled,
    );
    _notificationPreferencesPersisted = false;
    _notificationScheduleConfirmed = false;
    if (coachPlan != null) coachPlanNotificationsEnabled = coachPlan;
    if (crash != null) crashNotificationsEnabled = crash;
    if (recovery != null) recoveryNotificationsEnabled = recovery;
    isNotificationSyncing = true;
    notificationError = null;
    notifyListeners();
    try {
      if (enabled == true) {
        try {
          final permission = await _notificationService.requestPermission();
          if (!current()) return notificationPermission;
          notificationPermission = permission;
          notificationsEnabled =
              permission == NotificationPermissionState.granted;
          if (!notificationsEnabled) {
            notificationError = switch (permission) {
              NotificationPermissionState.unavailable =>
                'Scheduled reminders are unavailable on this device.',
              NotificationPermissionState.denied =>
                'Notifications are blocked in system settings.',
              _ => 'Notification permission was not granted.',
            };
          }
        } on Object {
          if (!current()) return notificationPermission;
          notificationsEnabled = false;
          notificationPermission = NotificationPermissionState.unknown;
          notificationError = 'Could not request notification permission.';
        }
      } else if (enabled == false) {
        notificationsEnabled = false;
        notificationPermission = NotificationPermissionState.unknown;
      }
      if (!notificationsEnabled) {
        _notificationPlan = const NotificationPlan(
          state: NotificationPlanState.disabled,
        );
        try {
          await _notificationService.cancelGuidance();
        } on Object {
          if (current()) {
            notificationError =
                'Could not clear scheduled reminders. Please retry.';
          }
        }
        if (!current()) return notificationPermission;
      }
      // Save the choice before scheduling. A storage failure must not report
      // new reminders as scheduled or leave an unrecorded schedule behind.
      await _commit();
      if (!current()) return notificationPermission;
      _notificationPreferencesPersisted = true;
      if (notificationsEnabled) {
        ownedRefreshGeneration = _notificationRefreshGeneration + 1;
        await refreshNotifications(notify: false);
      }
      return notificationPermission;
    } on Object {
      if (current()) {
        notificationsEnabled = previous.enabled;
        coachPlanNotificationsEnabled = previous.coach;
        crashNotificationsEnabled = previous.crash;
        recoveryNotificationsEnabled = previous.recovery;
        notificationError = 'Could not save reminder settings. Please retry.';
        // SharedPreferences updates its cache before the platform write. Repair
        // that cache too, and pause scheduling until an explicit save succeeds.
        try {
          await _writeLocal();
        } on Object {
          /* keep the original save error */
        }
        if (current()) {
          try {
            await _notificationService.cancelGuidance();
          } on Object {
            /* keep the original save error */
          }
        }
      }
      rethrow;
    } finally {
      if (sameRequest() &&
          ownedRefreshGeneration == _notificationRefreshGeneration) {
        isNotificationSyncing = false;
        notifyListeners();
      }
    }
  }

  Future<void> setOutcomeConsent(bool value) async {
    if (isPrivacyBusy || deletionPending || isSignedOut) {
      throw StateError('Finish pending privacy operations first.');
    }
    if (value) _requirePrivacy();
    _isSavingPrivacy = true;
    _privacyRefreshGeneration++;
    privacyOperationError = null;
    final uid = cloudUid;
    final revision = _sessionRevision;
    try {
      if (!value) {
        outcomeConsent = false;
        _outcomes = [];
        _reconcileOutcomeSync();
        await _discardPersonalizedModel();
        await _writeLocal();
      }
      final at = uid != null && cloudRepository != null
          ? await cloudRepository!.saveOutcomeConsent(uid, value)
          : _now();
      if (uid != cloudUid || revision != _sessionRevision) {
        throw StateError('Account changed while saving consent.');
      }
      outcomeConsent = value;
      outcomeConsentUpdatedAt = at;
      _reconcileOutcomeSync();
      outcomeError = null;
      await _invalidateModelPreparation();
      await _writeLocal();
      if (value) await refreshOutcomes();
    } on Object {
      privacyOperationError = value
          ? 'Outcome learning was not enabled. Reconnect and retry.'
          : 'Learning is paused on this device, but cloud consent was not updated. Reconnect and turn it off again.';
      rethrow;
    } finally {
      _isSavingPrivacy = false;
      notifyListeners();
    }
  }

  Future<bool> connectHealth() async {
    _requirePrivacy();
    if (!healthAvailable || isHealthAuthorizing || _disposed) return false;
    _invalidateHealthWork();
    final context = _healthContext;
    bool current() => _healthContextCurrent(context);
    isHealthAuthorizing = true;
    healthError = null;
    healthSyncError = null;
    sleepSyncError = null;
    activitySyncError = null;
    notifyListeners();
    try {
      final status = await _healthService.requestAuthorization();
      if (!current()) return false;
      healthAuthorization = status;
      healthAvailable =
          healthAuthorization != HealthAuthorizationState.unavailable;
      healthAuthorized =
          healthAuthorization == HealthAuthorizationState.authorized;
      if (!healthAuthorized) {
        healthError = switch (healthAuthorization) {
          HealthAuthorizationState.denied =>
            'The Apple Health permission sheet was not completed.',
          HealthAuthorizationState.unavailable =>
            'Apple Health is unavailable on this device.',
          _ => 'Apple Health permissions could not be requested.',
        };
      }
    } on Object {
      if (!current()) return false;
      healthAuthorization = HealthAuthorizationState.error;
      healthAuthorized = false;
      healthError = 'Apple Health permissions could not be requested.';
    } finally {
      if (current()) isHealthAuthorizing = false;
    }
    if (!current()) return false;
    await _commit();
    if (!current()) return false;
    if (healthAuthorized) {
      await _ensureContinuousHealthUpdates();
      if (!current()) return false;
      await syncHealth(reason: HealthRefreshReason.initial);
    }
    return current() && healthAuthorized;
  }

  Future<HealthAuthorizationState> refreshHealthAuthorization({
    bool notify = true,
  }) async {
    final context = _healthContext;
    final previous = healthAuthorization;
    final status = await _healthService.authorizationStatus();
    if (!_healthContextCurrent(context)) {
      return healthAuthorization;
    }
    healthAvailable = status != HealthAuthorizationState.unavailable;
    if (status != HealthAuthorizationState.error) healthError = null;
    // A Tonyo-level disconnect remains in force until the person explicitly
    // reconnects, even if iOS still has some read categories enabled.
    if (previous == HealthAuthorizationState.revoked &&
        !healthAuthorized &&
        status == HealthAuthorizationState.authorized) {
      healthAuthorization = HealthAuthorizationState.revoked;
    } else {
      healthAuthorization = status;
      if (status != HealthAuthorizationState.authorized) {
        final hadObservers =
            healthBackgroundRefreshEnabled ||
            _pendingHealthObserverSetup != null;
        healthAuthorized = false;
        _invalidateHealthWork();
        if (hadObservers) {
          healthSyncStatus = HealthSyncStatus.disabled;
          await _disableContinuousHealthUpdates();
        }
      }
    }
    if (notify) notifyListeners();
    return healthAuthorization;
  }

  Future<void> disconnectHealth() async {
    // Stop accepting callbacks/results before waiting on the native channel.
    _invalidateHealthWork();
    final context = _healthContext;
    healthAuthorized = false;
    healthBackgroundRefreshEnabled = false;
    healthSyncStatus = HealthSyncStatus.disabled;
    healthAuthorization = healthAvailable
        ? HealthAuthorizationState.revoked
        : HealthAuthorizationState.unavailable;
    healthError = null;
    healthSyncError = null;
    sleepSyncError = null;
    activitySyncError = null;
    notifyListeners();
    // Persist the local opt-out even if privacy/network checks currently pause
    // cloud processing. Native observer removal must also run if saving fails.
    await Future.wait([_writeLocal(), _disableContinuousHealthUpdates()]);
    if (!_healthContextCurrent(context)) return;
    await _commit();
  }

  Future<bool> openHealthSettings() async {
    final opened = await _healthService.openSettings();
    healthError = opened
        ? null
        : 'Open Settings to manage Apple Health access.';
    notifyListeners();
    return opened;
  }

  Future<ScreenTimeAuthorizationState> refreshScreenTimeAuthorization({
    bool notify = true,
  }) async {
    screenTimeAuthorization = await _screenTimeService.authorizationStatus();
    screenTimeError = switch (screenTimeAuthorization) {
      ScreenTimeAuthorizationState.error =>
        'Screen Time report status could not be checked.',
      _ => null,
    };
    if (notify) notifyListeners();
    return screenTimeAuthorization;
  }

  Future<ScreenTimeAuthorizationState> authorizeScreenTimeReport() async {
    _requirePrivacy();
    final revision = _sessionRevision;
    final uid = cloudUid;
    bool current() =>
        revision == _sessionRevision && uid == cloudUid && _canProcessData;
    isScreenTimeAuthorizing = true;
    screenTimeError = null;
    notifyListeners();
    try {
      final status = await _screenTimeService.requestAuthorization();
      if (!current()) return screenTimeAuthorization;
      screenTimeAuthorization = status;
      screenTimeError = switch (screenTimeAuthorization) {
        ScreenTimeAuthorizationState.denied =>
          'Screen Time report permission was not granted.',
        ScreenTimeAuthorizationState.entitlementRequired =>
          'Apple Family Controls entitlement access is still required.',
        ScreenTimeAuthorizationState.error =>
          'Screen Time report permission could not be requested.',
        _ => null,
      };
    } on Object {
      if (!current()) return screenTimeAuthorization;
      screenTimeAuthorization = ScreenTimeAuthorizationState.error;
      screenTimeError = 'Screen Time report permission could not be requested.';
    } finally {
      isScreenTimeAuthorizing = false;
      notifyListeners();
    }
    return screenTimeAuthorization;
  }

  Future<bool> showScreenTimeReport() async {
    _requirePrivacy();
    if (screenTimeAuthorization != ScreenTimeAuthorizationState.authorized) {
      screenTimeError = 'Allow the private Screen Time report first.';
      notifyListeners();
      return false;
    }
    final shown = await _screenTimeService.showReport();
    screenTimeError = shown
        ? null
        : 'The private Screen Time report could not be opened.';
    notifyListeners();
    return shown;
  }

  Future<void> refreshHealthIfDue({
    HealthRefreshReason reason = HealthRefreshReason.foreground,
    bool notify = true,
  }) async {
    if (_disposed || !_canProcessData || !healthAuthorized) return;
    final now = _now();
    // A HealthKit notification is evidence of changed data, not a foreground
    // poll. Never acknowledge it while silently discarding it in the throttle.
    if (reason != HealthRefreshReason.background &&
        !ContinuousRefreshLogic.shouldRefresh(
          now: now,
          lastAttempt: lastHealthSyncAttempt,
        )) {
      if (notify) notifyListeners();
      return;
    }
    await syncHealth(reason: reason, notify: notify);
  }

  Future<HeartSyncMergeResult?> syncHealth({
    HealthRefreshReason reason = HealthRefreshReason.manual,
    bool notify = true,
  }) {
    if (_disposed || !_canProcessData || !healthAuthorized) {
      return Future.value(null);
    }
    final context = _healthContext;
    final pending = _pendingHealthSync;
    if (pending != null && _healthSyncContext == context) {
      // Several categories may notify together. Keep one trailing read so a
      // change after a category was read still arrives without a button press.
      if (reason == HealthRefreshReason.background) {
        _healthRefreshRequested = true;
      }
      return pending;
    }
    final completion = Completer<HeartSyncMergeResult?>();
    final operation = completion.future;
    _pendingHealthSync = operation;
    _healthSyncContext = context;
    _healthRefreshRequested = false;
    isSyncing = true;
    bool current() => _healthContextCurrent(context) && healthAuthorized;
    unawaited(() async {
      try {
        var nextReason = reason;
        HeartSyncMergeResult? result;
        do {
          _healthRefreshRequested = false;
          result = await _syncHealthOnce(
            reason: nextReason,
            notify: notify,
            current: current,
          );
          nextReason = HealthRefreshReason.background;
        } while (current() && _healthRefreshRequested);
        completion.complete(current() ? result : null);
      } on Object catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        // An old connection must never clear a newer connection's busy state.
        if (identical(_pendingHealthSync, operation)) {
          _pendingHealthSync = null;
          _healthSyncContext = null;
          _healthRefreshRequested = false;
          isSyncing = false;
          if (notify) notifyListeners();
        }
      }
    }());
    return operation;
  }

  Future<HeartSyncMergeResult?> _syncHealthOnce({
    required HealthRefreshReason reason,
    required bool notify,
    required bool Function() current,
  }) async {
    bool sessionEnded() => !current();
    if (sessionEnded()) return null;

    final attemptTime = _now();
    final before = List<SignalReading>.of(signals);
    healthSyncStatus = HealthSyncStatus.syncing;
    lastHealthSyncAttempt = attemptTime;
    lastHealthRefreshReason = reason;
    healthSyncError = null;
    sleepSyncError = null;
    activitySyncError = null;
    if (notify) notifyListeners();
    HeartSyncMergeResult? heartResult;
    SleepSyncMergeResult? sleepResult;
    ActivitySyncMergeResult? activityResult;
    try {
      final imported = await _healthService.sync();
      if (sessionEnded()) return null;
      heartResult = HeartSyncLogic.merge(
        existing: signals,
        imported: imported,
        syncedAt: attemptTime.toUtc(),
      );
      signals = heartResult.readings;
      lastHealthImportCount = heartResult.importedCount;
      lastHealthDuplicateCount = heartResult.duplicateCount;
      lastHealthRejectedCount = heartResult.rejectedCount;
    } on HealthSyncException catch (error) {
      if (sessionEnded()) return null;
      healthSyncError = error.message;
    } on Object {
      if (sessionEnded()) return null;
      healthSyncError = 'Apple Health heart data could not be imported.';
    }

    if (sessionEnded()) return null;
    try {
      final imported = await _healthService.syncSleep();
      if (sessionEnded()) return null;
      sleepResult = SleepSyncLogic.merge(
        existing: signals,
        imported: imported,
        syncedAt: attemptTime.toUtc(),
      );
      signals = sleepResult.readings;
      lastSleepImportCount = sleepResult.importedSignalCount;
      lastSleepDuplicateCount = sleepResult.duplicateCount;
      lastSleepRejectedCount = sleepResult.rejectedSampleCount;
      lastSleepNightCount = sleepResult.importedNightCount;
      lastSleepManualPreferenceCount = sleepResult.skippedManualNightCount;
    } on HealthSyncException catch (error) {
      if (sessionEnded()) return null;
      sleepSyncError = error.message;
    } on Object {
      if (sessionEnded()) return null;
      sleepSyncError = 'Apple Health sleep data could not be imported.';
    }

    if (sessionEnded()) return null;
    try {
      final imported = await _healthService.syncActivity();
      if (sessionEnded()) return null;
      activityResult = ActivitySyncLogic.merge(
        existing: signals,
        imported: imported,
        syncedAt: attemptTime.toUtc(),
      );
      signals = activityResult.readings;
      lastActivityImportCount = activityResult.importedCount;
      lastActivityDuplicateCount = activityResult.duplicateCount;
      lastActivityRejectedCount = activityResult.rejectedCount;
    } on HealthSyncException catch (error) {
      if (sessionEnded()) return null;
      activitySyncError = error.message;
    } on Object {
      if (sessionEnded()) return null;
      activitySyncError =
          'Apple Health workout, step, and hydration data could not be imported.';
    }
    if (sessionEnded()) return null;
    final successfulSourceCount = [
      heartResult,
      sleepResult,
      activityResult,
    ].where((result) => result != null).length;
    final importedCount =
        (heartResult?.importedCount ?? 0) +
        (sleepResult?.importedSignalCount ?? 0) +
        (activityResult?.importedCount ?? 0);
    if (successfulSourceCount > 0) {
      lastSync = attemptTime;
    }
    healthSyncStatus = successfulSourceCount == 0
        ? HealthSyncStatus.failed
        : successfulSourceCount < 3
        ? HealthSyncStatus.partialFailure
        : importedCount > 0
        ? HealthSyncStatus.updated
        : HealthSyncStatus.upToDate;
    if (notify) notifyListeners();

    final meaningfulChange = ContinuousRefreshLogic.hasMeaningfulModelChange(
      before,
      signals,
    );
    if (meaningfulChange) lastHealthChangeAt = attemptTime;
    await _commit(energyInputsChanged: meaningfulChange);
    return heartResult;
  }

  Future<void> _ensureContinuousHealthUpdates() async {
    if (_disposed ||
        !_canProcessData ||
        !healthAuthorized ||
        healthBackgroundRefreshEnabled) {
      return;
    }
    final pending = _pendingHealthObserverSetup;
    if (pending != null) return pending;
    final context = _healthContext;
    bool current() => _healthContextCurrent(context) && healthAuthorized;
    final setup = _queueHealthObserverOperation(() async {
      if (!current()) return;
      final enabled = await _healthService.enableBackgroundUpdates(() async {
        if (!current()) return;
        await refreshHealthIfDue(reason: HealthRefreshReason.background);
      });
      if (current()) {
        healthBackgroundRefreshEnabled = enabled;
      } else {
        // Cleanup is serialized before the next connection's registration.
        await _healthService.disableBackgroundUpdates();
      }
    });
    _pendingHealthObserverSetup = setup;
    try {
      await setup;
    } finally {
      if (identical(_pendingHealthObserverSetup, setup)) {
        _pendingHealthObserverSetup = null;
      }
    }
  }

  (int, int, String?) get _healthContext =>
      (_healthConnectionGeneration, _sessionRevision, cloudUid);

  bool _healthContextCurrent((int, int, String?) context) =>
      !_disposed && _canProcessData && context == _healthContext;

  void _invalidateHealthWork() {
    _healthConnectionGeneration++;
    _healthSyncContext = null;
    _pendingHealthSync = null;
    _pendingHealthObserverSetup = null;
    _healthRefreshRequested = false;
    healthBackgroundRefreshEnabled = false;
    isHealthAuthorizing = false;
    isSyncing = false;
  }

  Future<void> _disableContinuousHealthUpdates() =>
      _queueHealthObserverOperation(_healthService.disableBackgroundUpdates);

  Future<void> _queueHealthObserverOperation(
    Future<void> Function() operation,
  ) async {
    final previous = _healthObserverQueue;
    final pending = previous == null
        ? operation()
        : previous.then((_) => operation());
    final tail = pending.catchError((Object _) {});
    _healthObserverQueue = tail;
    try {
      await pending;
    } finally {
      if (identical(_healthObserverQueue, tail)) _healthObserverQueue = null;
    }
  }

  String get healthSyncSummary {
    if (isSyncing) return 'Reading the last 30 days of heart data…';
    if (healthSyncError != null) return healthSyncError!;
    if (lastSync == null) return 'Heart data has not been synced yet.';
    final total = healthKitHeartSignalCount;
    if (lastHealthImportCount == 0) {
      if (lastHealthDuplicateCount > 0) {
        return 'No new signals · $lastHealthDuplicateCount matching ${lastHealthDuplicateCount == 1 ? 'entry was' : 'entries were'} already saved.';
      }
      return total == 0
          ? 'No readable heart samples found. You can retry after checking Apple Health access.'
          : 'Up to date · $total saved heart ${total == 1 ? 'signal' : 'signals'}.';
    }
    return 'Imported $lastHealthImportCount new heart ${lastHealthImportCount == 1 ? 'signal' : 'signals'} · $total saved.';
  }

  String get sleepSyncSummary {
    if (isSyncing) return 'Reading the last 30 days of sleep stages…';
    if (sleepSyncError != null) return sleepSyncError!;
    if (lastSync == null) return 'Sleep stages have not been synced yet.';
    final nights = healthKitSleepNightCount;
    final stages = healthKitSleepSignalCount;
    if (lastSleepNightCount == 0) {
      return nights == 0
          ? 'No readable sleep samples found. Check Sleep access in Apple Health.'
          : 'Up to date · $nights imported ${nights == 1 ? 'night' : 'nights'} saved.';
    }
    final manualNote = lastSleepManualPreferenceCount == 0
        ? ''
        : ' · Kept manual sleep for $lastSleepManualPreferenceCount ${lastSleepManualPreferenceCount == 1 ? 'night' : 'nights'}';
    return 'Reconciled $lastSleepNightCount ${lastSleepNightCount == 1 ? 'night' : 'nights'} · $stages stage ${stages == 1 ? 'signal' : 'signals'} saved$manualNote.';
  }

  String get activitySyncSummary {
    if (isSyncing) {
      return 'Reading the last 30 days of workouts, steps, and water…';
    }
    if (activitySyncError != null) return activitySyncError!;
    if (lastSync == null) {
      return 'Workouts, steps, and hydration have not been synced yet.';
    }
    final workouts = healthKitWorkoutSignalCount;
    final hydration = healthKitHydrationSignalCount;
    final steps = healthKitStepSignalCount;
    final total = workouts + hydration + steps;
    if (lastActivityImportCount == 0) {
      if (lastActivityDuplicateCount > 0) {
        return 'Up to date · $lastActivityDuplicateCount matching ${lastActivityDuplicateCount == 1 ? 'sample was' : 'samples were'} already saved.';
      }
      return total == 0
          ? 'No readable workouts, steps, or water samples found. Manual activity logging remains available.'
          : 'Up to date · $workouts ${workouts == 1 ? 'workout' : 'workouts'}, $steps daily step ${steps == 1 ? 'total' : 'totals'}, and $hydration water ${hydration == 1 ? 'sample' : 'samples'} saved.';
    }
    return 'Imported $lastActivityImportCount new or updated ${lastActivityImportCount == 1 ? 'activity signal' : 'activity signals'} · $workouts ${workouts == 1 ? 'workout' : 'workouts'}, $steps daily step ${steps == 1 ? 'total' : 'totals'}, and $hydration water ${hydration == 1 ? 'sample' : 'samples'} saved.';
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert(_json());

  bool get canExportDeviceBackup =>
      !isSignedOut &&
      !_isSigningOut &&
      !deletionPending &&
      !isDeletingAccount &&
      (cloudUid == null
          ? !cloudEnabled && _privacyOwnerUid == null
          : _privacyOwnerUid == cloudUid);

  static String _deviceRecoveryKey(String uid) =>
      '$_deviceRecoveryKeyPrefix${base64Url.encode(utf8.encode(uid))}';

  /// Offline backup never reads Firebase, requires renewed consent, or changes
  /// a sync acknowledgement. The journal retains edits and deletion tombstones.
  Future<String> exportDeviceBackup() async {
    if (!canExportDeviceBackup) {
      throw StateError('Device data is unavailable for this account.');
    }
    final uid = cloudUid;
    final revision = _sessionRevision;
    final preferences = await SharedPreferences.getInstance();
    if (!canExportDeviceBackup ||
        uid != cloudUid ||
        revision != _sessionRevision) {
      throw StateError('Account changed. Nothing was exported.');
    }
    final recovery = uid == null
        ? null
        : preferences.getString(_deviceRecoveryKey(uid));
    final savedRecovery = recovery == null ? null : jsonDecode(recovery);
    return const JsonEncoder.withIndent('  ').convert({
      'backupVersion': 1,
      'backupType': 'tonyoDeviceData',
      'exportedAt': _now().toUtc().toIso8601String(),
      'ownerUid': uid,
      'local': _json(),
      'sync': {
        'pendingInputs': hasPendingCloudChanges,
        'pendingOutcomes': hasPendingOutcomeChanges,
        'pendingCoach': hasPendingCoachChanges,
        'cloudVerifiedForSession': _cloudPrivacyVerified,
        'cloudSyncInProgress': isCloudSyncing,
      },
      if (savedRecovery is Map && savedRecovery['ownerUid'] == uid)
        'beforeCloudRestore': savedRecovery,
      'scope': {
        'source': 'thisDevice',
        'includesUnsyncedChanges': true,
        'cloudFetched': false,
        'excludes': [
          'Cloud-only records',
          'Authentication credentials',
          'Original Apple Health store',
          'Derived model and preparation caches',
          'Device experiment history',
        ],
      },
    });
  }

  Future<void> _preserveDeviceDataBeforeRestore(String uid) async {
    if (_privacyOwnerUid != uid ||
        (signals.isEmpty && checkIns.isEmpty && _outcomes.isEmpty)) {
      return;
    }
    final revision = _sessionRevision;
    final backup = <String, Object?>{
      'ownerUid': uid,
      'savedAt': _now().toUtc().toIso8601String(),
      'reason': 'Device data before cloud restore; prior sync status unknown',
      'local': _json(),
    };
    final preferences = await SharedPreferences.getInstance();
    if (revision != _sessionRevision || cloudUid != uid || deletionPending) {
      throw StateError('Account changed during cloud restore.');
    }
    final key = _deviceRecoveryKey(uid);
    final previous = preferences.getString(key);
    if (previous != null) {
      final saved = Map<String, dynamic>.from(jsonDecode(previous) as Map);
      if (saved['ownerUid'] != uid) {
        throw StateError(
          'The device recovery copy belongs to another account.',
        );
      }
      if (sameSyncValue(saved['local'], backup['local'])) return;
      // A later interrupted restore must preserve both the original backup
      // and new device edits, rather than silently dropping either snapshot.
      final earlier = saved.remove('earlierSnapshots') as List? ?? [];
      backup['earlierSnapshots'] = [...earlier, saved];
    }
    if (!await preferences.setString(key, jsonEncode(backup))) {
      throw StateError('Could not preserve device data. Cloud restore paused.');
    }
  }

  Future<String> exportAllData() async {
    if (isSignedOut || isPrivacyBusy) {
      throw StateError(
        'Sign in and finish pending privacy operations before exporting.',
      );
    }
    isExportingData = true;
    privacyOperationError = null;
    notifyListeners();
    final uid = cloudUid;
    final revision = _sessionRevision;
    try {
      if (cloudEnabled && (uid == null || cloudRepository == null)) {
        throw StateError('Sign in to export your cloud account.');
      }
      final cloud = uid == null ? null : await cloudRepository!.exportUser(uid);
      final prefs = await SharedPreferences.getInstance();
      if (uid != cloudUid || revision != _sessionRevision || isSignedOut) {
        throw StateError(
          'Account changed during export. Nothing was exported.',
        );
      }
      // Only include this owner's cache. Never attach another signed-out user's
      // device state to a newly authenticated account's export.
      final local = uid == _privacyOwnerUid ? _json() : <String, Object?>{};
      final localCaches = <String, Object?>{};
      for (final key in prefs.getKeys()) {
        if (!key.startsWith('tonyo_energy_model_v1_') &&
            !key.startsWith('tonyo_ml_prep_v1_') &&
            !key.startsWith(_deviceRecoveryKeyPrefix) &&
            !key.startsWith(_prepWindowKeyPrefix)) {
          continue;
        }
        final raw = prefs.get(key);
        if (raw is! String) continue;
        try {
          final value = jsonDecode(raw);
          if (value is Map && uid != null) {
            final ownedModel =
                key ==
                    'tonyo_energy_model_v1_${base64Url.encode(utf8.encode(uid))}' &&
                value['ownerKey'] == prepFingerprint({'uid': uid});
            final snapshot = value['snapshot'];
            var ownedPrep = false;
            if (key.startsWith('tonyo_ml_prep_v1_') && snapshot is Map) {
              // Prep snapshots deliberately omit UID. Validate the actual
              // service envelope (including its content checksum) and bind its
              // owner through the request key and account-specific identity.
              final prepared = PrepSnapshot.fromJson(
                Map<String, dynamic>.from(snapshot),
                uid: uid,
              );
              final requestKey = prepFingerprint({
                'uid': uid,
                'window': prepared.window.toJson(),
                'prepVersion': mlPrepVersion,
              });
              final identity = prepFingerprint({
                'uid': uid,
                'window': prepared.window.toJson(),
                'prepVersion': mlPrepVersion,
                'schemaVersion': prepared.schemaVersion,
                'consent': prepared.consent.toJson(),
              });
              ownedPrep =
                  key == 'tonyo_ml_prep_v1_$requestKey' &&
                  value['identity'] == identity;
            }
            final ownedRecovery =
                key == _deviceRecoveryKey(uid) && value['ownerUid'] == uid;
            if (ownedModel ||
                key == _prepWindowKey(uid) ||
                ownedPrep ||
                ownedRecovery) {
              localCaches[key] = value;
            }
          }
        } on Object {
          /* Invalid/unowned cache is not exported as this account. */
        }
      }
      return const JsonEncoder.withIndent('  ').convert({
        'exportVersion': 2,
        'exportedAt': _now().toUtc().toIso8601String(),
        'cloud': cloud,
        'local': {...local, 'derivedCaches': localCaches},
        'scope': {
          'cloudCollections': uid == null
              ? <String>[]
              : userDataChildCollections,
          'pointInTimeSnapshot': false,
          'excludes': [
            'Original Apple Health store',
            'Device experiment history',
            'Other devices and previous exports',
            'Authentication credentials',
            'Administrator-created unknown or nested collections',
          ],
        },
      });
    } on Object {
      privacyOperationError =
          'Export did not complete. No partial export was returned. Reconnect and retry.';
      rethrow;
    } finally {
      isExportingData = false;
      notifyListeners();
    }
  }

  /// Clears signals, check-ins, and score snapshots but keeps the account and
  /// profile so the user can start a fresh manual tracking period.
  Future<void> clearTrackingData() async {
    final ensureCurrent = _beginMutation();
    _ai1CaptureGeneration++;
    await _ai1Capture.stopAndClear(_ai1Owner);
    ensureCurrent();
    // Finish an already-issued outcome upload before clearing its collection;
    // otherwise a late success could recreate data after the clear completes.
    while (_pendingOutcomePush != null) {
      await _pendingOutcomePush;
      ensureCurrent();
    }
    while (_pendingCoachPush != null || _pendingGuidanceWrite != null) {
      await _pendingCoachPush;
      await _pendingGuidanceWrite;
      ensureCurrent();
    }
    _guidanceRefreshGeneration++;
    _clearCoachSync();
    await _discardPersonalizedModel();
    ensureCurrent();
    signals = [];
    checkIns = [];
    _outcomes = [];
    _clearOutcomeSync();
    outcomeError = null;
    lastSync = null;
    lastHealthSyncAttempt = null;
    lastHealthChangeAt = null;
    healthSyncStatus = healthAuthorized
        ? HealthSyncStatus.idle
        : HealthSyncStatus.disabled;
    lastHealthRefreshReason = null;
    lastHealthImportCount = 0;
    lastHealthDuplicateCount = 0;
    lastHealthRejectedCount = 0;
    lastSleepImportCount = 0;
    lastSleepDuplicateCount = 0;
    lastSleepRejectedCount = 0;
    lastSleepNightCount = 0;
    lastSleepManualPreferenceCount = 0;
    lastActivityImportCount = 0;
    lastActivityDuplicateCount = 0;
    lastActivityRejectedCount = 0;
    healthSyncError = null;
    sleepSyncError = null;
    activitySyncError = null;
    _scoreSnapshot = null;
    _todaySignals = [];
    _scoreLoadedFromSnapshot = false;
    energyScoreError = null;
    _recommendationStatuses.clear();
    _recommendationFeedback.clear();
    _dismissedRiskAlertIds.clear();
    _recommendations = [];
    _riskAlerts = [];
    guidanceError = null;
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session != null && repository != null) {
      await repository.clearScoreSnapshots(session.uid);
      await repository.clearGuidance(session.uid);
      await repository.clearOutcomes(session.uid);
      ensureCurrent();
      final preferences = await SharedPreferences.getInstance();
      ensureCurrent();
      if (!await preferences.remove(_deviceRecoveryKey(session.uid))) {
        throw StateError('Could not clear the device recovery copy. Retry.');
      }
    }
    await _commit(energyInputsChanged: true);
    ensureCurrent();
  }

  /// Erases the known account schema and Auth identity, then this device's
  /// Tonyo cache. A durable journal prevents migration or sync after failure.
  Future<void> deleteAccountData({String? password}) async {
    if (isPrivacyBusy || isSignedOut) {
      throw StateError('Finish the current operation and sign in first.');
    }
    isDeletingAccount = true;
    _cloudSyncActivities.clear();
    isCloudSyncing = false;
    _cloudRetryTimer?.cancel();
    _cloudRetryTimer = null;
    privacyOperationError = null;
    notifyListeners();
    final uid = cloudUid;
    try {
      final authAlreadyDeleted = _deletionStage == 'authDeleted';
      if (uid != null && cloudRepository == null) {
        throw StateError(
          'Cloud storage is unavailable. Restore the connection before deleting the account.',
        );
      }
      if (cloudEnabled && !authAlreadyDeleted) {
        if (uid == null ||
            cloudRepository == null ||
            password == null ||
            password.isEmpty) {
          throw StateError(
            'Enter your current account password before deletion.',
          );
        }
        // Must precede every destructive operation, including local cache work.
        await _accountAuth.reauthenticate(password: password);
        if (cloudUid != uid) {
          throw StateError('Account changed before deletion.');
        }
      }
      if (!authAlreadyDeleted) {
        await _saveDeletionJournal(uid ?? 'local', 'requested');
      }
      _sessionRevision++;
      _unloadAi1Capture();
      _invalidateHealthWork();
      _scoreRefreshGeneration++;
      _energyModelService.unload();
      await _invalidateModelPreparation();
      await _disableContinuousHealthUpdates();
      healthBackgroundRefreshEnabled = false;
      try {
        await _notificationService.cancelGuidance();
      } on Object {
        /* cache clearing still proceeds */
      }
      if (uid != null && !authAlreadyDeleted) {
        await cloudRepository!.deleteUserTree(uid);
        await _saveDeletionJournal(uid, 'cloudDeleted');
        if (cloudUid != uid) {
          throw StateError('Account changed before authentication deletion.');
        }
        await _accountAuth.deleteCurrentAccount();
        await _saveDeletionJournal(uid, 'authDeleted');
      }
      await reset();
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.remove(_deletionKey)) {
        throw StateError('Could not clear deletion recovery state.');
      }
      _deletionOwner = null;
      _deletionStage = null;
    } on Object {
      privacyOperationError = deletionPending
          ? 'Deletion is incomplete; some data may already be removed. Sync stays paused. Retry to finish.'
          : 'Password verification or deletion could not start. No data was deleted. Check your password and connection.';
      rethrow;
    } finally {
      isDeletingAccount = false;
      notifyListeners();
    }
  }

  Future<void> _saveDeletionJournal(String owner, String stage) async {
    _deletionOwner = owner;
    _deletionStage = stage;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      _deletionKey,
      jsonEncode({'owner': owner, 'stage': stage}),
    )) {
      throw StateError('Could not save deletion recovery state.');
    }
  }

  Future<void> _restoreDeletionJournal(SharedPreferences prefs) async {
    _deletionOwner = null;
    _deletionStage = null;
    final raw = prefs.getString(_deletionKey);
    if (raw == null) return;
    try {
      final value = jsonDecode(raw) as Map;
      final owner = value['owner'] as String;
      final stage = value['stage'] as String;
      if (owner == cloudUid ||
          (owner == 'local' && !cloudEnabled) ||
          cloudUid == null) {
        _deletionOwner = owner;
        _deletionStage = stage;
      }
    } on Object {
      // Corrupt recovery state cannot safely be treated as a fresh account.
      _deletionOwner = cloudUid ?? 'local';
      _deletionStage = 'requested';
    }
  }

  /// Recovery action with deliberately narrower scope than account deletion.
  /// The UI must explain that this does not confirm cloud/Auth deletion.
  Future<void> clearDeviceAfterInterruptedDeletion() async {
    if (!deletionPending || isCloudAuthenticated || isPrivacyBusy) {
      throw StateError(
        'Device-only recovery is only available after interrupted deletion without an active account.',
      );
    }
    isDeletingAccount = true;
    try {
      _sessionRevision++;
      _unloadAi1Capture();
      _invalidateHealthWork();
      await reset();
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.remove(_deletionKey)) {
        throw StateError('Could not clear device recovery state.');
      }
      _deletionOwner = null;
      _deletionStage = null;
    } finally {
      isDeletingAccount = false;
      notifyListeners();
    }
  }

  Future<void> reset() async {
    _cloudSyncActivities.clear();
    isCloudSyncing = false;
    _cloudRetryTimer?.cancel();
    _cloudRetryTimer = null;
    _clearCoachSync();
    _lastCloudSyncAt = null;
    _lastCloudSyncOwnerUid = null;
    cloudSyncFailureKind = null;
    cloudSyncError = null;
    _sessionRevision++;
    _unloadAi1Capture();
    _invalidateHealthWork();
    // A preference platform write already in progress cannot be canceled.
    // Invalidate its session, then drain it before removing the account cache,
    // so a completed deletion cannot be undone by a late language save.
    await _localWriteQueue;
    await _ai1Capture.clearAll();
    _scoreRefreshGeneration++;
    isForecastLoading = false;
    isGuidanceLoading = false;
    isOutcomeLoading = false;
    isEnergyScoreLoading = false;
    _energyModelService.unload();
    _cloudEnergySummary = null;
    _cloudMetadataUid = null;
    _cloudMetadataFetchedAt = null;
    _cloudUserUpdatedAt = null;
    await _energyModelStore.clear();
    await _clearModelPreparationWindow();
    await _invalidateModelPreparation();
    await SharedPreferencesPrepCache().clear();
    await _disableContinuousHealthUpdates();
    try {
      await _notificationService.cancelGuidance();
    } on Object {
      // Local reset still proceeds when platform notification APIs fail.
    }
    onboardingComplete = false;
    notificationsEnabled = false;
    crashNotificationsEnabled = true;
    recoveryNotificationsEnabled = true;
    coachPlanNotificationsEnabled = false;
    isNotificationSyncing = false;
    notificationError = null;
    notificationPermission = NotificationPermissionState.unknown;
    _notificationPlan = const NotificationPlan(
      state: NotificationPlanState.disabled,
    );
    outcomeConsent = false;
    outcomeConsentUpdatedAt = null;
    _privacyConsent = null;
    _privacyOwnerUid = null;
    _cloudPrivacyVerified = false;
    _outcomes = [];
    _clearOutcomeSync();
    isOutcomeLoading = false;
    outcomeError = null;
    healthAuthorized = false;
    isHealthAuthorizing = false;
    isScreenTimeAuthorizing = false;
    screenTimeAuthorization = ScreenTimeAuthorizationState.notDetermined;
    screenTimeError = null;
    healthAuthorization = healthAvailable
        ? HealthAuthorizationState.revoked
        : HealthAuthorizationState.unavailable;
    healthError = null;
    healthSyncError = null;
    sleepSyncError = null;
    activitySyncError = null;
    lastSync = null;
    lastHealthSyncAttempt = null;
    lastHealthChangeAt = null;
    healthSyncStatus = HealthSyncStatus.idle;
    lastHealthRefreshReason = null;
    healthBackgroundRefreshEnabled = false;
    lastHealthImportCount = 0;
    lastHealthDuplicateCount = 0;
    lastHealthRejectedCount = 0;
    lastSleepImportCount = 0;
    lastSleepDuplicateCount = 0;
    lastSleepRejectedCount = 0;
    lastSleepNightCount = 0;
    lastSleepManualPreferenceCount = 0;
    lastActivityImportCount = 0;
    lastActivityDuplicateCount = 0;
    lastActivityRejectedCount = 0;
    _syncBaseline = null;
    _syncOwnerUid = null;
    cloudSyncConflict = false;
    accountEmail = null;
    profile = const UserProfile();
    signals = [];
    checkIns = [];
    _scoreSnapshot = null;
    _todaySignals = [];
    _scoreLoadedFromSnapshot = false;
    _forecastsByDay.clear();
    _forecastLoadedFromCloud = false;
    energyScoreError = null;
    forecastError = null;
    guidanceError = null;
    _recommendationStatuses.clear();
    _recommendationFeedback.clear();
    _dismissedRiskAlertIds.clear();
    _recommendations = [];
    _riskAlerts = [];
    _guidanceSavedToCloud = false;
    _insightsSnapshot = null;
    isInsightsLoading = false;
    insightsLoadedFromCloud = false;
    insightsError = null;
    final preferences = await SharedPreferences.getInstance();
    for (final key in preferences.getKeys().where(
      (key) =>
          key == _storageKey ||
          key == _signedOutKey ||
          key.startsWith(_deviceRecoveryKeyPrefix) ||
          key.startsWith(_prepWindowKeyPrefix) ||
          key.startsWith('tonyo_ml_prep_v1_') ||
          key.startsWith('tonyo_energy_model_v1_'),
    )) {
      if (!await preferences.remove(key)) {
        throw StateError(
          'Device cache removal did not finish. Retry deletion.',
        );
      }
    }
    isSignedOut = false;
    notifyListeners();
  }

  Map<String, Object?> _json() => {
    if (_coachSyncOwnerUid != null) 'coachSync': _coachSyncJson(),
    if (_lastCloudSyncOwnerUid != null)
      'cloudSyncMetadata': {
        'uid': _lastCloudSyncOwnerUid,
        'lastUploadedAt': _lastCloudSyncAt?.toUtc().toIso8601String(),
      },
    if (_syncBaseline != null && _syncOwnerUid != null)
      'inputSync': {
        'version': 1,
        'uid': _syncOwnerUid,
        'baseline': _syncBaseline!.toJson(),
      },
    'derivedRulesVersion': FatigueEngine.energyModelVersion,
    'deviceTimezone': deviceTimezoneIdentifier,
    'deviceUtcOffsetMinutes': _deviceTimezoneService.utcOffset.inMinutes,
    'privacyOwnerUid': _privacyOwnerUid,
    'privacyConsent': _privacyConsent?.toJson(),
    'outcomeConsentUpdatedAt': outcomeConsentUpdatedAt
        ?.toUtc()
        .toIso8601String(),
    if (_cloudMetadataUid != null)
      'modelTransparencyCache': {
        'uid': _cloudMetadataUid,
        'fetchedAt': _cloudMetadataFetchedAt?.toUtc().toIso8601String(),
        'userUpdatedAt': _cloudUserUpdatedAt?.toUtc().toIso8601String(),
        'personalizedEnergyModel': _cloudEnergySummary?.toJson(),
      },
    'onboardingComplete': onboardingComplete,
    'notificationsEnabled': notificationsEnabled,
    'crashNotificationsEnabled': crashNotificationsEnabled,
    'recoveryNotificationsEnabled': recoveryNotificationsEnabled,
    'coachPlanNotificationsEnabled': coachPlanNotificationsEnabled,
    'notificationPreferencesVersion': notificationPreferencesVersion,
    'outcomeConsent': outcomeConsent,
    'healthAuthorized': healthAuthorized,
    'healthAuthorizationState': healthAuthorization.name,
    'lastHealthImportCount': lastHealthImportCount,
    'lastHealthDuplicateCount': lastHealthDuplicateCount,
    'lastHealthRejectedCount': lastHealthRejectedCount,
    'lastSleepImportCount': lastSleepImportCount,
    'lastSleepDuplicateCount': lastSleepDuplicateCount,
    'lastSleepRejectedCount': lastSleepRejectedCount,
    'lastSleepNightCount': lastSleepNightCount,
    'lastSleepManualPreferenceCount': lastSleepManualPreferenceCount,
    'lastActivityImportCount': lastActivityImportCount,
    'lastActivityDuplicateCount': lastActivityDuplicateCount,
    'lastActivityRejectedCount': lastActivityRejectedCount,
    'accountEmail': accountEmail,
    'lastSync': lastSync?.toUtc().toIso8601String(),
    'lastHealthSyncAttempt': lastHealthSyncAttempt?.toUtc().toIso8601String(),
    'lastHealthChangeAt': lastHealthChangeAt?.toUtc().toIso8601String(),
    'healthSyncStatus': healthSyncStatus.name,
    'lastHealthRefreshReason': lastHealthRefreshReason?.name,
    'healthBackgroundRefreshEnabled': healthBackgroundRefreshEnabled,
    'profile': profile.toJson(),
    'signals': signals.map((item) => item.toJson()).toList(),
    'checkIns': checkIns.map((item) => item.toJson()).toList(),
    'outcomes': _outcomes.map((item) => item.toJson()).toList(),
    if (_outcomeSyncOwnerUid != null && _pendingOutcomeWrites.isNotEmpty)
      'outcomeSync': {
        'version': 1,
        'uid': _outcomeSyncOwnerUid,
        'consentAt': _outcomeSyncConsentAt?.toUtc().toIso8601String(),
        'writes': {
          for (final entry in _pendingOutcomeWrites.entries)
            entry.key: entry.value?.toJson(),
        },
      },
    'recommendationStatuses': _recommendationStatuses.map(
      (key, value) => MapEntry(key, value.name),
    ),
    'recommendationFeedback': _recommendationFeedback,
    'dismissedRiskAlertIds': _dismissedRiskAlertIds.toList(),
  };

  Future<void> _commit({
    bool energyInputsChanged = false,
    bool forecastInputsChanged = false,
    _Ai1CaptureIntent? ai1Capture,
  }) async {
    if (!_canProcessData) return;
    final revision = _sessionRevision;
    final uid = cloudUid;
    bool current() =>
        revision == _sessionRevision && uid == cloudUid && _canProcessData;
    if (energyInputsChanged || forecastInputsChanged) {
      // Retire derived views before the first persistence/network await. New
      // values must not briefly show a curve or native reminder for old inputs.
      if (energyInputsChanged) {
        _scoreSnapshot = null;
        _scoreLoadedFromSnapshot = false;
        _insightsSnapshot = null;
      }
      _forecastsByDay.clear();
      _forecastLoadedFromCloud = false;
      _recommendations = [];
      _riskAlerts = [];
      _notificationRefreshGeneration++;
      _notificationScheduleConfirmed = false;
      try {
        await _notificationService.cancelGuidance();
      } on Object {
        notificationError =
            'Previous reminders could not be cleared on this device.';
      }
      if (!current()) return;
    }
    await _invalidateModelPreparation();
    if (!current()) return;
    notifyListeners();
    await _writeLocal(ai1Capture: ai1Capture);
    if (!current()) return;
    await _pushCloud();
    if (!current()) return;
    if (energyInputsChanged && onboardingComplete) {
      await refreshScores(forceRecalculate: true);
      if (!current()) return;
    }
    if ((energyInputsChanged || forecastInputsChanged) && onboardingComplete) {
      await refreshForecasts(forceRecalculate: true);
      if (!current()) return;
      await refreshGuidance();
      if (!current()) return;
    }
    if (energyInputsChanged && onboardingComplete) {
      await refreshInsights();
    }
  }

  Future<void> _writeLocal({_Ai1CaptureIntent? ai1Capture}) async {
    if (deletionPending || isDeletingAccount) return;
    final revision = _sessionRevision;
    // Language, observations and background refresh share one state document.
    // Preserve request order, and capture current state only when its write can
    // start, so a late preference snapshot cannot erase a newer observation.
    Future<void> write() async {
      final preferences = await SharedPreferences.getInstance();
      if (revision != _sessionRevision ||
          deletionPending ||
          isDeletingAccount) {
        return;
      }
      final encoded = jsonEncode(_json());
      final savedState = Map<String, Object?>.from(jsonDecode(encoded) as Map);
      if (!await preferences.setString(_storageKey, encoded)) {
        throw StateError(
          'Could not save to this device. Keep this screen open and retry.',
        );
      }
      if (revision == _sessionRevision &&
          !deletionPending &&
          !isDeletingAccount) {
        final previousCaptureCount = ai1CapturedRevisionCount;
        final previousCaptureError = ai1CaptureError;
        final previousCaptureEnabled = ai1CaptureEnabled;
        if (ai1Capture != null &&
            ai1Capture.generation == _ai1CaptureGeneration &&
            ai1CaptureEnabled &&
            _ai1SourceSnapshot(savedState, ai1Capture.observation) ==
                ai1Capture.sourceSnapshot) {
          await _ai1Capture.capture(
            owner: _ai1Owner,
            observation: ai1Capture.observation,
          );
        }
        if (revision != _sessionRevision ||
            deletionPending ||
            isDeletingAccount) {
          return;
        }
        await _reconcileAi1Capture(savedState);
        if (previousCaptureCount != ai1CapturedRevisionCount ||
            previousCaptureError != ai1CaptureError ||
            previousCaptureEnabled != ai1CaptureEnabled) {
          notifyListeners();
        }
        scheduleCloudRetry();
      }
    }

    final previousWrite = _localWriteQueue;
    final pending = previousWrite == null
        ? write()
        : previousWrite.then((_) => write());
    final tail = pending.catchError((Object _) {});
    _localWriteQueue = tail;
    try {
      await pending;
    } finally {
      if (identical(_localWriteQueue, tail)) _localWriteQueue = null;
    }
  }

  Future<void> _hydrateOrMigrateCloud({bool Function()? isCurrent}) async {
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session == null || repository == null) return;
    final revision = _sessionRevision;
    final pending = _syncOwnerUid == session.uid && _syncBaseline != null
        ? InputSyncPatch(
            _syncBaseline!,
            InputSyncSnapshot.fromState(
              _cloudState(migrationVersion: localMigrationVersion),
            ),
          )
        : null;
    _cloudPrivacyVerified = false;
    final syncActivity = _beginCloudSyncActivity();
    cloudSyncError = null;
    notifyListeners();
    try {
      final remote = await repository.readUser(session.uid);
      if (cloudUid != session.uid ||
          _sessionRevision != revision ||
          (isCurrent != null && !isCurrent()) ||
          _isSigningOut ||
          deletionPending) {
        return;
      }
      final metadataFetchedAt = _now();
      if (remote == null || pending == null) {
        await _preserveDeviceDataBeforeRestore(session.uid);
        if (cloudUid != session.uid ||
            _sessionRevision != revision ||
            (isCurrent != null && !isCurrent()) ||
            _isSigningOut ||
            deletionPending) {
          return;
        }
      }
      if (remote == null) {
        if (onboardingComplete &&
            accountEmail != null &&
            accountEmail!.trim().toLowerCase() !=
                session.email.trim().toLowerCase()) {
          throw StateError(
            'The saved device profile belongs to another account and cannot be migrated.',
          );
        }
        // Missing server state is never permission to resurrect a deleted
        // account or upload another user's cache. New setup is explicit.
        _syncBaseline = null;
        _syncOwnerUid = null;
        _privacyConsent = null;
        _privacyOwnerUid = session.uid;
        onboardingComplete = false;
        profile = const UserProfile();
        accountEmail = session.email;
        signals = [];
        checkIns = [];
        _outcomes = [];
        outcomeConsent = false;
      } else {
        final remoteInputs = InputSyncSnapshot.fromState(remote);
        if (pending != null && !pending.isEmpty) {
          _syncBaseline = remoteInputs.overlay(pending, useBefore: true);
          _applyCloud(remoteInputs.overlay(pending).toState(remote));
        } else {
          _syncBaseline = remoteInputs;
          _applyCloud(remote);
        }
        _syncOwnerUid = session.uid;
        _cloudPrivacyVerified = true;
        if (remote.deletionPending) {
          await _saveDeletionJournal(session.uid, 'requested');
        }
        accountEmail = session.email;
        // The ordinary pending patch upgrades only the migration field. Never
        // replace whole input collections while restoring an older account.
      }
      if (cloudUid == session.uid &&
          _sessionRevision == revision &&
          (isCurrent == null || isCurrent()) &&
          !_isSigningOut) {
        _cloudMetadataUid = session.uid;
        _cloudMetadataFetchedAt = metadataFetchedAt;
        _cloudEnergySummary = remote?.personalizedEnergyModel;
        _cloudUserUpdatedAt = remote?.userUpdatedAt;
      }
    } on Object catch (error) {
      if (cloudUid == session.uid &&
          _sessionRevision == revision &&
          (isCurrent == null || isCurrent())) {
        _recordCloudFailure(error);
      }
    } finally {
      _endCloudSyncActivity(syncActivity);
    }
  }

  Future<void> _pushCloud() async {
    // Serialize commits; a later local edit is compared against the last
    // acknowledged snapshot after the current request finishes.
    final revision = _sessionRevision;
    final uid = cloudUid;
    while (_pendingCloudPush != null) {
      await _pendingCloudPush;
    }
    if (revision != _sessionRevision || uid != cloudUid) return;
    final task = _pushCloudNow();
    _pendingCloudPush = task;
    try {
      await task;
    } finally {
      if (identical(_pendingCloudPush, task)) _pendingCloudPush = null;
      scheduleCloudRetry();
    }
  }

  Future<void> _pushCloudNow() async {
    if (!_canProcessData) return;
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session == null || repository == null) return;
    final revision = _sessionRevision;
    bool current() =>
        revision == _sessionRevision &&
        cloudUid == session.uid &&
        _canProcessData;
    final syncActivity = _beginCloudSyncActivity();
    cloudSyncError = null;
    cloudSyncFailureKind = null;
    cloudSyncConflict = false;
    notifyListeners();
    try {
      if (_syncBaseline == null || _syncOwnerUid != session.uid) {
        final remote = await repository.readUser(session.uid);
        if (!current()) return;
        if (remote == null) {
          throw StateError('Restore the cloud account before syncing.');
        }
        final known = InputSyncSnapshot.fromState(remote);
        // First setup may upload local records, but cannot delete unseen ones.
        _syncBaseline = InputSyncSnapshot(
          root: known.root,
          signals: {},
          checkIns: {},
        );
        _syncOwnerUid = session.uid;
      }
      final desired = InputSyncSnapshot.fromState(
        _cloudState(migrationVersion: localMigrationVersion),
      );
      final patch = InputSyncPatch(_syncBaseline!, desired);
      await _writeLocal(); // durable retry baseline before any network write
      if (!current()) return;
      if (!patch.isEmpty) await repository.applyInputPatch(session.uid, patch);
      if (!current()) return;
      _syncBaseline = desired;
      if (!patch.isEmpty) _markCloudUploadSuccess();
      await _writeLocal();
    } on Object catch (error) {
      if (!current()) return;
      _recordCloudFailure(error);
    } finally {
      _endCloudSyncActivity(syncActivity);
    }
  }

  Future<void> retryCloudSync() async {
    if (isSignedOut || _isSigningOut || deletionPending || isPrivacyBusy) {
      throw StateError('Finish the current account operation before syncing.');
    }
    final uid = cloudUid;
    final revision = _sessionRevision;
    final generation = ++_privacyRefreshGeneration;
    bool current() =>
        uid == cloudUid &&
        revision == _sessionRevision &&
        generation == _privacyRefreshGeneration &&
        !isSignedOut &&
        !_isSigningOut &&
        !isPrivacyBusy;
    if (isCloudAuthenticated && cloudRepository != null) {
      final syncActivity = _beginCloudSyncActivity();
      notifyListeners();
      try {
        if (!await _refreshCloudPrivacy(current)) return;
        if (_syncBaseline == null || _syncOwnerUid != uid) {
          await _hydrateOrMigrateCloud(isCurrent: current);
          if (!current()) return;
          if (cloudSyncError != null) {
            throw StateError('Cloud account could not be restored. Retry.');
          }
        }
      } on Object catch (error) {
        if (current()) {
          _cloudPrivacyVerified = false;
          _recordCloudFailure(error);
          privacyOperationError =
              'Account privacy could not be verified. Reconnect and retry.';
        }
        rethrow;
      } finally {
        _endCloudSyncActivity(syncActivity);
      }
    }
    if (!current()) return;
    final ensureCurrent = _beginMutation();
    await _pushCloud();
    ensureCurrent();
    await _retryCoachSync();
    ensureCurrent();
    if (outcomeConsent || hasPendingOutcomeChanges) {
      await refreshOutcomes(notify: false);
      ensureCurrent();
    }
    if (cloudSyncError == null && onboardingComplete) {
      await refreshScores(forceRecalculate: true);
      ensureCurrent();
      await refreshForecasts(forceRecalculate: true);
      ensureCurrent();
      await refreshGuidance();
      ensureCurrent();
      await refreshInsights();
      ensureCurrent();
    }
    notifyListeners();
  }

  /// Explicit UI-confirmed discard of pending local input edits only.
  Future<void> useCloudInputs() async {
    final ensureCurrent = _beginMutation();
    while (_pendingCloudPush != null) {
      await _pendingCloudPush;
      ensureCurrent();
    }
    final task = _useCloudInputsNow(ensureCurrent);
    _pendingCloudPush = task;
    try {
      await task;
    } finally {
      if (identical(_pendingCloudPush, task)) _pendingCloudPush = null;
    }
  }

  Future<void> _useCloudInputsNow(void Function() ensureCurrent) async {
    final uid = cloudUid;
    final repository = cloudRepository;
    if (uid == null || repository == null) return;
    final original = InputSyncSnapshot.fromState(
      _cloudState(migrationVersion: localMigrationVersion),
    );
    void ensureInputsUnchanged() {
      ensureCurrent();
      if (!InputSyncPatch(
        original,
        InputSyncSnapshot.fromState(
          _cloudState(migrationVersion: localMigrationVersion),
        ),
      ).isEmpty) {
        throw StateError(
          'New data was saved during recovery. Review it and retry.',
        );
      }
    }

    final remote = await repository.readUser(uid);
    ensureInputsUnchanged();
    if (remote == null || remote.deletionPending) {
      throw StateError('Cloud data is unavailable.');
    }
    await _discardPersonalizedModel();
    ensureInputsUnchanged();
    _syncOwnerUid = uid;
    _syncBaseline = InputSyncSnapshot.fromState(remote);
    _applyCloud(remote);
    cloudSyncError = null;
    cloudSyncConflict = false;
    await _writeLocal();
    ensureCurrent();
    notifyListeners();
    if (onboardingComplete) {
      await refreshScores(forceRecalculate: true);
      ensureCurrent();
      await refreshForecasts(forceRecalculate: true);
      ensureCurrent();
      await refreshGuidance();
      ensureCurrent();
      await refreshInsights();
      ensureCurrent();
    }
  }

  CloudUserState _cloudState({required int migrationVersion}) => CloudUserState(
    privacyConsent: _privacyConsent,
    outcomeConsentUpdatedAt: outcomeConsentUpdatedAt,
    personalizedEnergyModel: cloudUid == _cloudMetadataUid
        ? _cloudEnergySummary
        : null,
    userUpdatedAt: cloudUid == _cloudMetadataUid ? _cloudUserUpdatedAt : null,
    profile: profile,
    accountEmail: _accountAuth.currentSession?.email ?? accountEmail ?? '',
    onboardingComplete: onboardingComplete,
    notificationsEnabled: notificationsEnabled,
    crashNotificationsEnabled: crashNotificationsEnabled,
    recoveryNotificationsEnabled: recoveryNotificationsEnabled,
    coachPlanNotificationsEnabled: coachPlanNotificationsEnabled,
    notificationPrefsVersion: notificationPreferencesVersion,
    outcomeConsent: outcomeConsent,
    healthAuthorized: healthAuthorized,
    lastSync: lastSync,
    healthSyncStatus: healthSyncStatus,
    lastHealthRefreshReason: lastHealthRefreshReason,
    lastHealthSyncAttempt: lastHealthSyncAttempt,
    lastHealthChangeAt: lastHealthChangeAt,
    healthBackgroundRefreshEnabled: healthBackgroundRefreshEnabled,
    migrationVersion: migrationVersion,
    signals: List.unmodifiable(signals),
    checkIns: List.unmodifiable(checkIns),
  );

  void _applyCloud(CloudUserState state) {
    _notificationPreferenceGeneration++;
    _notificationRefreshGeneration++;
    _notificationScheduleConfirmed = false;
    _notificationPreferencesPersisted = true;
    isNotificationSyncing = false;
    _reconcileCoachSync();
    _privacyConsent = state.privacyConsent;
    _privacyOwnerUid = cloudUid;
    outcomeConsentUpdatedAt = state.outcomeConsentUpdatedAt;
    _scoreRefreshGeneration++;
    isEnergyScoreLoading = false;
    final prepInputsChanged =
        outcomeConsent != state.outcomeConsent ||
        jsonEncode(signals.map((item) => item.toJson()).toList()) !=
            jsonEncode(state.signals.map((item) => item.toJson()).toList()) ||
        jsonEncode(checkIns.map((item) => item.toJson()).toList()) !=
            jsonEncode(state.checkIns.map((item) => item.toJson()).toList());
    if (prepInputsChanged) unawaited(_invalidateModelPreparation());
    final sameAccount =
        accountEmail?.trim().toLowerCase() ==
        state.accountEmail.trim().toLowerCase();
    _scoreSnapshot = null;
    _todaySignals = [];
    _scoreLoadedFromSnapshot = false;
    _forecastsByDay.clear();
    _forecastLoadedFromCloud = false;
    _recommendations = [];
    _riskAlerts = [];
    _guidanceSavedToCloud = false;
    _insightsSnapshot = null;
    insightsLoadedFromCloud = false;
    insightsError = null;
    if (!sameAccount) {
      _recommendationStatuses.clear();
      _recommendationFeedback.clear();
      _dismissedRiskAlertIds.clear();
      _outcomes = [];
      lastHealthImportCount = 0;
      lastHealthDuplicateCount = 0;
      lastHealthRejectedCount = 0;
      lastSleepImportCount = 0;
      lastSleepDuplicateCount = 0;
      lastSleepRejectedCount = 0;
      lastSleepNightCount = 0;
      lastSleepManualPreferenceCount = 0;
      lastActivityImportCount = 0;
      lastActivityDuplicateCount = 0;
      lastActivityRejectedCount = 0;
      healthSyncError = null;
      sleepSyncError = null;
      activitySyncError = null;
    }
    profile = state.profile;
    accountEmail = state.accountEmail;
    onboardingComplete = state.onboardingComplete;
    notificationsEnabled =
        state.notificationPrefsVersion >= notificationPreferencesVersion &&
        state.notificationsEnabled;
    crashNotificationsEnabled = state.crashNotificationsEnabled;
    recoveryNotificationsEnabled = state.recoveryNotificationsEnabled;
    coachPlanNotificationsEnabled = state.coachPlanNotificationsEnabled;
    if (!notificationsEnabled || !onboardingComplete) {
      // Account restoration can return to setup without regenerating guidance.
      // Queue cancellation now so a former device plan cannot remain active.
      final revision = _sessionRevision;
      final generation = _notificationRefreshGeneration;
      unawaited(
        _notificationService.cancelGuidance().catchError((Object error) {
          if (revision == _sessionRevision &&
              generation == _notificationRefreshGeneration) {
            notificationError =
                'Could not clear scheduled reminders. Please retry.';
            notifyListeners();
          }
        }),
      );
    }
    notificationPermission = NotificationPermissionState.unknown;
    notificationError = null;
    _notificationPlan = const NotificationPlan(
      state: NotificationPlanState.disabled,
    );
    outcomeConsent = state.outcomeConsent;
    _reconcileOutcomeSync();
    if (!outcomeConsent) _outcomes = [];
    outcomeError = null;
    // Health authorization is device-specific. Cloud state must not turn on
    // access on a different device; the local platform check remains primary.
    lastSync = state.lastSync;
    lastHealthSyncAttempt = state.lastHealthSyncAttempt;
    lastHealthChangeAt = state.lastHealthChangeAt;
    healthSyncStatus = state.healthSyncStatus;
    lastHealthRefreshReason = state.lastHealthRefreshReason;
    // Observer registration is device-process state and must be re-established
    // after every launch even when another device wrote `true` to Firestore.
    healthBackgroundRefreshEnabled = false;
    signals = [...state.signals]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    checkIns = [...state.checkIns]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  void _restoreLocal(Map<String, dynamic> json) {
    _notificationPreferenceGeneration++;
    _notificationRefreshGeneration++;
    _notificationScheduleConfirmed = false;
    _notificationPreferencesPersisted = true;
    isNotificationSyncing = false;
    final sync = json['inputSync'];
    if (sync is Map && sync['version'] == 1 && sync['uid'] is String) {
      try {
        _syncOwnerUid = sync['uid'] as String;
        _syncBaseline = InputSyncSnapshot.fromJson(
          Map<String, dynamic>.from(sync['baseline'] as Map),
        );
      } on Object {
        _syncOwnerUid = null;
        _syncBaseline = null;
      }
    }

    _privacyConsent = PrivacyConsent.tryParse(json['privacyConsent']);
    _privacyOwnerUid = json['privacyOwnerUid'] as String?;
    outcomeConsentUpdatedAt = DateTime.tryParse(
      json['outcomeConsentUpdatedAt'] as String? ?? '',
    );
    _cloudEnergySummary = null;
    _cloudMetadataUid = null;
    _cloudMetadataFetchedAt = null;
    _cloudUserUpdatedAt = null;
    final metadata = json['modelTransparencyCache'];
    if (metadata is Map && metadata['uid'] is String) {
      _cloudMetadataUid = metadata['uid'] as String;
      final fetched = metadata['fetchedAt'];
      final updated = metadata['userUpdatedAt'];
      _cloudMetadataFetchedAt = fetched is String
          ? DateTime.tryParse(fetched)
          : null;
      _cloudUserUpdatedAt = updated is String
          ? DateTime.tryParse(updated)
          : null;
      _cloudEnergySummary = EnergyModelSummary.tryParse(
        metadata['personalizedEnergyModel'],
      );
    }
    _scoreSnapshot = null;
    _todaySignals = [];
    _scoreLoadedFromSnapshot = false;
    _forecastsByDay.clear();
    _forecastLoadedFromCloud = false;
    _recommendations = [];
    _riskAlerts = [];
    _guidanceSavedToCloud = false;
    _insightsSnapshot = null;
    insightsLoadedFromCloud = false;
    insightsError = null;
    _outcomes = [];
    outcomeError = null;
    _recommendationStatuses.clear();
    _recommendationFeedback.clear();
    _dismissedRiskAlertIds.clear();
    onboardingComplete = json['onboardingComplete'] as bool? ?? false;
    final notificationPrefsVersion =
        (json['notificationPreferencesVersion'] as num?)?.round() ?? 0;
    notificationsEnabled =
        notificationPrefsVersion >= notificationPreferencesVersion &&
        (json['notificationsEnabled'] as bool? ?? false);
    crashNotificationsEnabled =
        json['crashNotificationsEnabled'] as bool? ?? true;
    recoveryNotificationsEnabled =
        json['recoveryNotificationsEnabled'] as bool? ?? true;
    coachPlanNotificationsEnabled =
        json['coachPlanNotificationsEnabled'] as bool? ?? false;
    notificationPermission = NotificationPermissionState.unknown;
    notificationError = null;
    _notificationPlan = const NotificationPlan(
      state: NotificationPlanState.disabled,
    );
    outcomeConsent = json['outcomeConsent'] as bool? ?? false;
    healthAuthorized = json['healthAuthorized'] as bool? ?? false;
    healthAuthorization =
        HealthAuthorizationState.values
            .where(
              (value) =>
                  value.name == json['healthAuthorizationState'] as String?,
            )
            .firstOrNull ??
        (healthAuthorized
            ? HealthAuthorizationState.authorized
            : HealthAuthorizationState.notDetermined);
    accountEmail = json['accountEmail'] as String?;
    lastSync = json['lastSync'] == null
        ? null
        : DateTime.tryParse(json['lastSync'] as String);
    lastHealthSyncAttempt = json['lastHealthSyncAttempt'] == null
        ? null
        : DateTime.tryParse(json['lastHealthSyncAttempt'] as String);
    lastHealthChangeAt = json['lastHealthChangeAt'] == null
        ? null
        : DateTime.tryParse(json['lastHealthChangeAt'] as String);
    healthSyncStatus =
        HealthSyncStatus.values
            .where((value) => value.name == json['healthSyncStatus'])
            .firstOrNull ??
        HealthSyncStatus.idle;
    lastHealthRefreshReason = HealthRefreshReason.values
        .where((value) => value.name == json['lastHealthRefreshReason'])
        .firstOrNull;
    healthBackgroundRefreshEnabled = false;
    lastHealthImportCount =
        (json['lastHealthImportCount'] as num?)?.round() ?? 0;
    lastHealthDuplicateCount =
        (json['lastHealthDuplicateCount'] as num?)?.round() ?? 0;
    lastHealthRejectedCount =
        (json['lastHealthRejectedCount'] as num?)?.round() ?? 0;
    lastSleepImportCount = (json['lastSleepImportCount'] as num?)?.round() ?? 0;
    lastSleepDuplicateCount =
        (json['lastSleepDuplicateCount'] as num?)?.round() ?? 0;
    lastSleepRejectedCount =
        (json['lastSleepRejectedCount'] as num?)?.round() ?? 0;
    lastSleepNightCount = (json['lastSleepNightCount'] as num?)?.round() ?? 0;
    lastSleepManualPreferenceCount =
        (json['lastSleepManualPreferenceCount'] as num?)?.round() ?? 0;
    lastActivityImportCount =
        (json['lastActivityImportCount'] as num?)?.round() ?? 0;
    lastActivityDuplicateCount =
        (json['lastActivityDuplicateCount'] as num?)?.round() ?? 0;
    lastActivityRejectedCount =
        (json['lastActivityRejectedCount'] as num?)?.round() ?? 0;
    profile = UserProfile.fromJson(
      (json['profile'] as Map).cast<String, dynamic>(),
    );
    signals = ((json['signals'] as List?) ?? const [])
        .map(
          (item) =>
              SignalReading.fromJson((item as Map).cast<String, dynamic>()),
        )
        .toList();
    checkIns = ((json['checkIns'] as List?) ?? const [])
        .map(
          (item) =>
              DailyCheckIn.fromJson((item as Map).cast<String, dynamic>()),
        )
        .toList();
    if (outcomeConsent) {
      _outcomes =
          ((json['outcomes'] as List?) ?? const [])
              .map(
                (item) => OutcomeRecord.fromJson(
                  (item as Map).cast<String, dynamic>(),
                ),
              )
              .toList()
            ..sort(
              (left, right) => right.observedAt.compareTo(left.observedAt),
            );
    }
    _clearOutcomeSync();
    final outcomeSync = json['outcomeSync'];
    if (outcomeSync is Map &&
        outcomeSync['version'] == 1 &&
        outcomeSync['uid'] is String &&
        outcomeSync['writes'] is Map) {
      try {
        _outcomeSyncOwnerUid = outcomeSync['uid'] as String;
        _outcomeSyncConsentAt = DateTime.tryParse(
          outcomeSync['consentAt'] as String? ?? '',
        );
        for (final entry in (outcomeSync['writes'] as Map).entries) {
          final id = entry.key as String;
          if (id.isEmpty || id.contains('/')) throw const FormatException();
          final outcome = entry.value == null
              ? null
              : OutcomeRecord.fromJson(
                  (entry.value as Map).cast<String, dynamic>(),
                );
          if (outcome != null && outcome.id != id) {
            throw const FormatException();
          }
          _pendingOutcomeWrites[id] = outcome;
        }
        // Signed-out caches retain their owner's journal for the next sign-in;
        // active sessions can never inherit another account's pending records.
        if (!isSignedOut) _reconcileOutcomeSync();
      } on Object {
        _clearOutcomeSync();
      }
    }
    final statuses =
        (json['recommendationStatuses'] as Map?)?.cast<String, dynamic>() ??
        const {};
    for (final entry in statuses.entries) {
      _recommendationStatuses[entry.key] = RecommendationStatus.values.byName(
        entry.value as String,
      );
    }
    final feedback =
        (json['recommendationFeedback'] as Map?)?.cast<String, dynamic>() ??
        const {};
    for (final entry in feedback.entries) {
      if (entry.value is bool) {
        _recommendationFeedback[entry.key] = entry.value as bool;
      }
    }
    _dismissedRiskAlertIds.addAll(
      ((json['dismissedRiskAlertIds'] as List?) ?? const []).cast<String>(),
    );
    _restoreCoachSync(json['coachSync']);
    final syncMetadata = json['cloudSyncMetadata'];
    _lastCloudSyncAt = null;
    _lastCloudSyncOwnerUid = null;
    if (syncMetadata is Map && syncMetadata['uid'] is String) {
      _lastCloudSyncOwnerUid = syncMetadata['uid'] as String;
      _lastCloudSyncAt = DateTime.tryParse(
        syncMetadata['lastUploadedAt'] as String? ?? '',
      )?.toLocal();
    }
  }

  static String _clock(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$hour:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  static bool _sameDay(DateTime left, DateTime right) =>
      sameLocalDay(left, right);

  void _generateLocalForecasts(
    List<DateTime> days, {
    required DateTime generatedAt,
  }) {
    for (final day in days) {
      _forecastsByDay[_dayKey(day)] = FatigueEngine.forecast(
        score,
        day,
        signals: signals,
        checkIns: checkIns,
        profile: profile,
        generatedAt: generatedAt,
      );
    }
  }

  static Map<String, List<ForecastPoint>> _groupForecasts(
    List<ForecastPoint> points,
  ) {
    final grouped = <String, List<ForecastPoint>>{};
    for (final point in points) {
      grouped.putIfAbsent(_dayKey(point.time), () => []).add(point);
    }
    for (final values in grouped.values) {
      values.sort((left, right) => left.time.compareTo(right.time));
    }
    return grouped;
  }

  bool _isCompleteForecast(List<ForecastPoint> points, DateTime day) {
    final startHour = profile.wakeHour.isFinite
        ? profile.wakeHour.round().clamp(4, 11)
        : 7;
    final endHour = profile.bedHour.isFinite
        ? profile.bedHour.round().clamp(startHour + 10, 23)
        : 23;
    if (points.length != endHour - startHour + 1) return false;
    for (var index = 0; index < points.length; index++) {
      if (points[index].time !=
          DateTime(day.year, day.month, day.day, startHour + index)) {
        return false;
      }
    }
    return true;
  }

  static String _dayKey(DateTime day) => localDayKey(day);
}

class _Ai1CaptureIntent {
  const _Ai1CaptureIntent({
    required this.observation,
    required this.generation,
    required this.sourceSnapshot,
  });

  final Ai1CaptureObservation observation;
  final int generation;
  final String sourceSnapshot;
}
