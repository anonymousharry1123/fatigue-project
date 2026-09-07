import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activity_log_logic.dart';
import 'activity_sync_logic.dart';
import 'check_in_logic.dart';
import 'cloud_repository.dart';
import 'cloud_schema.dart';
import 'continuous_refresh_logic.dart';
import 'daily_history_logic.dart';
import 'daily_plan_logic.dart';
import 'demo_data.dart';
import 'fatigue_engine.dart';
import 'energy_model_repository.dart';
import 'energy_model_service.dart';
import 'energy_model_summary.dart';
import 'health_service.dart';
import 'heart_sync_logic.dart';
import 'insights_logic.dart';
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
import 'sleep_sync_logic.dart';
import 'today_dashboard_logic.dart';

class AppController extends ChangeNotifier {
  AppController({
    HealthService? healthService,
    ScreenTimeService? screenTimeService,
    AccountAuth? accountAuth,
    NotificationService? notificationService,
    DateTime Function()? clock,
    PrepDataSource? prepDataSource,
    EnergyModelStore? energyModelStore,
    this.energyModelMetadataWriter,
    this.cloudRepository,
    PrivacyConsent? initialPrivacyConsent,
  }) : _healthService = healthService ?? const HealthService(),
       _screenTimeService = screenTimeService ?? const ScreenTimeService(),
       _accountAuth = accountAuth ?? const LocalOnlyAccountAuth(),
       _notificationService = notificationService ?? LocalNotificationService(),
       _now = clock ?? DateTime.now,
       _energyModelStore =
           energyModelStore ?? SharedPreferencesEnergyModelStore(),
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
  static const _prepWindowKeyPrefix = 'tonyo_ml_prep_window_v1_';
  static const forecastDayCount = 7;
  static const forecastFreshnessWindow = Duration(hours: 12);
  static const outcomeHistoryWindow = Duration(days: 90);
  final HealthService _healthService;
  final ScreenTimeService _screenTimeService;
  final AccountAuth _accountAuth;
  final NotificationService _notificationService;
  final DateTime Function() _now;
  final CloudRepository? cloudRepository;
  final MlPrepService? _mlPrepService;
  final EnergyModelStore _energyModelStore;
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
      outcomeConsentUpdatedAt = saved.acceptedAt;
      await _discardPersonalizedModel();
      await _writeLocal();
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
  List<SignalReading> signals = [];
  List<DailyCheckIn> checkIns = [];
  List<OutcomeRecord> _outcomes = [];
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
  bool get scoreLoadedFromSnapshot => _scoreLoadedFromSnapshot;
  bool get forecastLoadedFromCloud => _forecastLoadedFromCloud;
  bool get guidanceSavedToCloud => _guidanceSavedToCloud;
  InsightsSnapshot get insightsSnapshot =>
      _insightsSnapshot ??
      InsightsLogic.build(
        now: DateTime.now(),
        signals: const [],
        checkIns: const [],
      );
  bool get notificationSchedulingSupported =>
      _notificationService.supportsScheduling;
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
  int get scheduledNotificationCount =>
      notificationPermission == NotificationPermissionState.granted
      ? _notificationPlan.notifications.length
      : 0;
  GuidanceNotification? get nextScheduledNotification =>
      scheduledNotificationCount == 0
      ? null
      : _notificationPlan.notifications.first;
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
        day: DateTime.now(),
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
          hydrationLiters: hydration ?? 0,
          studyHours: study ?? 0,
          exerciseHours: exercise ?? 0,
          screenTimeHours: screenTime ?? 0,
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
          .where((item) => item.type == SignalType.sleep)
          .firstOrNull;
      final bedtime = group.value
          .where((item) => item.type == SignalType.bedtime)
          .firstOrNull;
      if (sleep == null || bedtime == null) continue;
      entries.add(
        SleepLogEntry(
          id: group.key,
          bedtime: bedtime.timestamp,
          wakeTime: sleep.timestamp,
          quality: sleep.quality * 5,
        ),
      );
    }
    return entries..sort((a, b) => b.wakeTime.compareTo(a.wakeTime));
  }

  double get bedtimeConsistencyMinutes =>
      SleepLogEntry.bedtimeConsistencyMinutes(sleepLogs.take(7));

  List<DailyHistoryDay> get dailyHistory => DailyHistoryLogic.build(
    signals: signals,
    checkIns: checkIns,
    activityLogs: activityLogs,
    sleepLogs: sleepLogs,
  );

  ScoreSnapshot get score {
    final value =
        _scoreSnapshot ??
        FatigueEngine.score(signals: signals, checkIns: checkIns, now: _now());
    return _energyModelService.model == null
        ? value.withoutPersonalization()
        : value;
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
      scoreFromCloud: visible && _scoreLoadedFromSnapshot,
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
    if (model == null || at.isBefore(model.trainedAt)) return base;
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
  List<ForecastPoint> forecastFor(DateTime day) =>
      _forecastsByDay[_dayKey(day)] ??
      FatigueEngine.forecast(
        score,
        day,
        signals: signals,
        checkIns: checkIns,
        profile: profile,
      );
  List<ForecastPoint> forecastDataFor(DateTime day) {
    final saved = _forecastsByDay[_dayKey(day)];
    if (saved != null) return saved;
    if (isCloudAuthenticated && forecastError == null) return const [];
    return forecastFor(day);
  }

  List<ForecastDaySummary> forecastSummariesFor(
    DateTime start, {
    int dayCount = forecastDayCount,
  }) {
    final firstDay = DateTime(start.year, start.month, start.day);
    final summaries = <ForecastDaySummary>[];
    for (var index = 0; index < dayCount; index++) {
      final day = firstDay.add(Duration(days: index));
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
  List<ForecastWindow> get windows => windowsFor(DateTime.now());
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
    final start = DateTime(target.year, target.month, target.day);
    final end = start.add(const Duration(days: 1));
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
          session != null && repository != null && cloudSyncError == null;
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
            savedSnapshot.hasCognitiveScore &&
            savedSnapshot.freshness != null &&
            savedSnapshot.cognitiveFreshness != null &&
            savedSnapshot.personalBaselines != null) {
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
            start: start.subtract(
              const Duration(days: PersonalBaselineLogic.windowDays),
            ),
            end: end,
          ),
          repository.checkInsByRange(
            session.uid,
            start: start.subtract(const Duration(hours: 36)),
            end: end,
          ),
          repository.scoreSnapshotForDay(
            session.uid,
            start.subtract(const Duration(days: 1)),
          ),
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
    final clock = DateTime.now();
    final target = day ?? clock;
    final firstDay = DateTime(target.year, target.month, target.day);
    final days = List.generate(
      forecastDayCount,
      (index) => firstDay.add(Duration(days: index)),
    );
    final rangeEnd = days.last.add(const Duration(days: 1));
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
      if (session != null && repository != null) {
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
            return _isCompleteForecast(points, targetDay) &&
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
            start: firstDay.subtract(const Duration(days: 7)),
            end: rangeEnd,
          ),
          repository.checkInsByRange(
            session.uid,
            start: firstDay.subtract(const Duration(days: 7)),
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
    final targetDay = DateTime(target.year, target.month, target.day);
    final rangeStart = targetDay.subtract(const Duration(days: 6));
    final rangeEnd = targetDay.add(const Duration(days: 1));
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
            final status = saved?.status ?? _recommendationStatuses[item.id];
            final helpful = saved?.helpful ?? _recommendationFeedback[item.id];
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
      if (session != null && repository != null) {
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
        await Future.wait([
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
        if (!currentRequest()) return;
        _guidanceSavedToCloud = true;
        return;
      }
      derive(sourceSignals: signals, sourceCheckIns: checkIns);
      _guidanceSavedToCloud = false;
    } on Object {
      if (!currentRequest()) return;
      derive(sourceSignals: signals, sourceCheckIns: checkIns);
      _guidanceSavedToCloud = false;
      guidanceError = 'Cloud guidance unavailable · using cached inputs';
    } finally {
      if (sameRequest()) isGuidanceLoading = false;
      if (currentRequest() && notificationsEnabled) {
        await refreshNotifications(notify: false);
      }
      if (sameRequest() && notify) notifyListeners();
    }
  }

  Future<void> refreshNotifications({bool notify = true}) async {
    if (!_canProcessData) return;
    if (isSignedOut || _isSigningOut) return;
    final sessionRevision = _sessionRevision;
    final uid = cloudUid;
    final generation = ++_notificationRefreshGeneration;
    bool sameRequest() =>
        sessionRevision == _sessionRevision &&
        generation == _notificationRefreshGeneration &&
        cloudUid == uid;
    bool currentRequest() => sameRequest() && _canProcessData;
    isNotificationSyncing = true;
    notificationError = null;
    if (notify) notifyListeners();

    try {
      final now = DateTime.now();
      _notificationPlan = NotificationLogic.build(
        now: now,
        points: forecastDataFor(now),
        windows: windowsFor(now),
        riskAlerts: _riskAlerts,
        enabled: notificationsEnabled,
        crashEnabled: crashNotificationsEnabled,
        recoveryEnabled: recoveryNotificationsEnabled,
      );
      if (!notificationsEnabled) {
        notificationPermission = NotificationPermissionState.unknown;
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
      if (!currentRequest()) {
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
    final clock = day ?? DateTime.now();
    final targetDay = DateTime(clock.year, clock.month, clock.day);
    final rangeStart = targetDay.subtract(
      const Duration(days: InsightsLogic.queryLookbackDays - 1),
    );
    final rangeEnd = targetDay.add(const Duration(days: 1));
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
      if (session != null && repository != null) {
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
    if (!outcomeConsent) {
      _outcomes = [];
      outcomeError = null;
      isOutcomeLoading = false;
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
        final refreshed = await repository.outcomesByRange(
          session.uid,
          start: now.subtract(outcomeHistoryWindow),
          end: now.add(const Duration(days: 1)),
        );
        if (!currentRequest()) return;
        if (jsonEncode(_outcomes.map((item) => item.toJson()).toList()) !=
            jsonEncode(refreshed.map((item) => item.toJson()).toList())) {
          await _invalidateModelPreparation();
          if (!currentRequest()) return;
        }
        _outcomes = refreshed;
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
    final preferences = await SharedPreferences.getInstance();
    isSignedOut = preferences.getBool(_signedOutKey) ?? false;
    _restoreModelPreparationWindow(preferences);
    final raw = preferences.getString(_storageKey);
    if (raw != null) {
      try {
        _restoreLocal(jsonDecode(raw) as Map<String, dynamic>);
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
      } on Object {
        privacyOperationError =
            'Account privacy could not be verified. Reconnect and retry.';
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
    await refreshHealthAuthorization(notify: false);
    await refreshScreenTimeAuthorization(notify: false);
    await _energyModelService.load();
    if (outcomeConsent) await refreshOutcomes(notify: false);
    if (healthAuthorized &&
        healthAuthorization == HealthAuthorizationState.authorized) {
      await _ensureContinuousHealthUpdates();
      await refreshHealthIfDue(
        reason: HealthRefreshReason.initial,
        notify: false,
      );
    }
    if (onboardingComplete) {
      await refreshScores(notify: false);
      await refreshForecasts(notify: false);
      await refreshGuidance(notify: false);
      await refreshInsights(notify: false);
    }
    isReady = true;
    notifyListeners();
  }

  Future<void> handleAppResumed() async {
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
      final uid = cloudUid!;
      try {
        await _accountAuth.refreshPrivacyClaims();
        if (!current() || deletionPending) return;
        final state = await cloudRepository!.readAccountPrivacy(uid);
        if (!current() || deletionPending) return;
        _privacyConsent = state.consent;
        _privacyOwnerUid = uid;
        _cloudPrivacyVerified = true;
        privacyOperationError = null;
        outcomeConsent = state.outcomeConsent;
        outcomeConsentUpdatedAt = state.outcomeConsentUpdatedAt;
        if (state.deletionPending) await _saveDeletionJournal(uid, 'requested');
        if (!current()) return;
        if (!outcomeConsent) await _discardPersonalizedModel();
        if (!current()) return;
        await _writeLocal();
      } on Object {
        if (!current()) return;
        _cloudPrivacyVerified = false;
        privacyOperationError =
            'Privacy status could not be verified. Reconnect and reopen Tonyo before new collection.';
      }
    }
    if (!current()) return;
    if (!_canProcessData) {
      await _invalidateModelPreparation();
      await _healthService.disableBackgroundUpdates();
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
    final status = await refreshHealthAuthorization(notify: false);
    await refreshScreenTimeAuthorization(notify: false);
    if (status == HealthAuthorizationState.authorized && healthAuthorized) {
      await _ensureContinuousHealthUpdates();
      await refreshHealthIfDue(reason: HealthRefreshReason.foreground);
    } else {
      notifyListeners();
    }
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
    profile = newProfile;
    accountEmail = _accountAuth.currentSession?.email ?? email ?? accountEmail;
    onboardingComplete = true;
    if (signals.isEmpty) {
      signals = buildDemoSignals(DateTime.now());
      checkIns = buildDemoCheckIns(DateTime.now());
    }
    await _setSignedOut(false);
    await _commit(energyInputsChanged: true);
  }

  Future<void> signIn({required String email, required String password}) async {
    if (isPrivacyBusy) {
      throw StateError('Finish pending privacy operations first.');
    }
    if (!cloudEnabled) throw StateError('Firebase is not configured.');
    final wasSignedOut = isSignedOut;
    // A rejected password must not change local account state or prep caches.
    await _accountAuth.signIn(email: email, password: password);
    _sessionRevision++;
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
    if (!outcomeConsent) await _discardPersonalizedModel();
    if (outcomeConsent) await refreshOutcomes(notify: false);
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
    _sessionRevision += 1;
    isForecastLoading = false;
    isGuidanceLoading = false;
    isInsightsLoading = false;
    isOutcomeLoading = false;
    isNotificationSyncing = false;
    isEnergyScoreLoading = false;
    _energyModelService.unload();
    try {
      await _clearModelPreparationWindow();
      await _invalidateModelPreparation();
      await _healthService.disableBackgroundUpdates();
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
    profile = value;
    await _commit(forecastInputsChanged: true);
    ensureCurrent();
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
    final hydration = ActivityLogLogic.valueOrZero(hydrationLiters);
    final study = ActivityLogLogic.valueOrZero(studyHours);
    final exercise = ActivityLogLogic.valueOrZero(exerciseHours);
    final screenTime = ActivityLogLogic.valueOrZero(screenTimeHours);
    if (!ActivityLogLogic.hasAnyLoggedValue(
      hydrationLiters: hydration,
      studyHours: study,
      exerciseHours: exercise,
      screenTimeHours: screenTime,
    )) {
      throw ArgumentError('Enter at least one activity value.');
    }
    final values = <SignalType, double>{
      SignalType.hydration: hydration,
      SignalType.study: study,
      SignalType.exercise: exercise,
      SignalType.screenTime: screenTime,
    };
    for (final entry in values.entries) {
      final message = ActivityLogEntry.validationMessage(
        entry.key,
        entry.value,
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
          .where((entry) => entry.value > 0)
          .map(
            (entry) => SignalReading(
              id: '$groupId-${entry.key.name}',
              groupId: groupId,
              type: entry.key,
              value: entry.value,
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
  }) async {
    final ensureCurrent = _beginMutation();
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
    );
    if (validation != null) throw ArgumentError(validation);
    final hours = end.difference(start).inMinutes / 60;
    final recordedAt = _now();
    final groupId =
        id ?? 'sleep-${recordedAt.microsecondsSinceEpoch}-${signals.length}';
    if (signals.any((item) => item.groupId == groupId)) {
      await _discardPersonalizedModel();
      ensureCurrent();
    }
    signals.removeWhere((item) => item.groupId == groupId);
    signals.insertAll(0, [
      SignalReading(
        id: '$groupId-duration',
        groupId: groupId,
        type: SignalType.sleep,
        value: hours,
        timestamp: end,
        recordedAt: recordedAt,
        quality: quality / 5,
        note: '${_clock(start)}–${_clock(end)} · quality ${quality.round()}/5',
      ),
      SignalReading(
        id: '$groupId-bedtime',
        groupId: groupId,
        type: SignalType.bedtime,
        value: start.hour + start.minute / 60,
        timestamp: start,
        recordedAt: recordedAt,
      ),
    ]);
    await _commit(energyInputsChanged: true);
    ensureCurrent();
  }

  Future<void> deleteSleepLog(String id) async {
    final ensureCurrent = _beginMutation();
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
  }) async {
    final ensureCurrent = _beginMutation();
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
    if (checkIns.any((item) => item.id == checkInId)) {
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
      // Period always follows the check-in timestamp (morning < 14:00).
      period: CheckInLogic.periodFor(when),
      note: note,
    );
    checkIns.removeWhere((item) => item.id == checkInId);
    checkIns.insert(0, checkIn);
    await _commit(energyInputsChanged: true);
    ensureCurrent();
    if (outcomeConsent) {
      await _saveOutcome(
        OutcomeRecord(
          id: 'energy-checkin-$checkInId',
          type: OutcomeType.observedEnergy,
          value: checkIn.energy,
          observedAt: checkIn.timestamp,
          recordedAt: _now(),
          source: OutcomeSource.checkIn,
          sourceId: checkInId,
        ),
      );
    }
  }

  Future<void> addReactionResult(double averageMs, {String? note}) async {
    final ensureCurrent = _beginMutation();
    if (!ReactionTestLogic.isValidReaction(averageMs.round())) {
      throw ArgumentError(
        'Reaction average must be between '
        '${ReactionTestLogic.minValidMs} and ${ReactionTestLogic.maxValidMs} ms',
      );
    }
    final observedAt = _now();
    final signalId =
        'manual-${observedAt.microsecondsSinceEpoch}-${signals.length}';
    signals.insert(
      0,
      SignalReading(
        id: signalId,
        type: SignalType.reactionTime,
        value: averageMs,
        timestamp: observedAt,
        recordedAt: _now(),
        note: note ?? 'Three-round reaction test',
      ),
    );
    await _commit(energyInputsChanged: true);
    ensureCurrent();
    if (outcomeConsent) {
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

  Future<void> _saveOutcome(OutcomeRecord outcome) async {
    final ensureCurrent = _beginMutation();
    if (!outcomeConsent) {
      throw StateError('Outcome learning requires explicit consent.');
    }
    await _invalidateModelPreparation();
    ensureCurrent();
    if (_outcomes.any((item) => item.id == outcome.id)) {
      await _discardPersonalizedModel();
      ensureCurrent();
    }
    _outcomes.removeWhere((item) => item.id == outcome.id);
    _outcomes.insert(0, outcome);
    outcomeError = null;
    notifyListeners();
    await _writeLocal();
    ensureCurrent();
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session != null && repository != null) {
      try {
        await repository.upsertOutcome(session.uid, outcome);
      } on Object {
        outcomeError = 'Outcome saved on this device · cloud update pending';
        notifyListeners();
      }
    }
  }

  Future<void> deleteSignal(String id) async {
    final ensureCurrent = _beginMutation();
    await _discardPersonalizedModel();
    ensureCurrent();
    signals.removeWhere((item) => item.id == id);
    await _commit(energyInputsChanged: true);
    ensureCurrent();
    await _deleteOutcome('reaction-$id');
  }

  Future<void> deleteCheckIn(String id) async {
    final ensureCurrent = _beginMutation();
    await _discardPersonalizedModel();
    ensureCurrent();
    checkIns.removeWhere((item) => item.id == id);
    await _commit(energyInputsChanged: true);
    ensureCurrent();
    await _deleteOutcome('energy-checkin-$id');
  }

  Future<void> _deleteOutcome(String outcomeId) async {
    final ensureCurrent = _beginMutation();
    await _invalidateModelPreparation();
    ensureCurrent();
    _outcomes.removeWhere((item) => item.id == outcomeId);
    await _writeLocal();
    ensureCurrent();
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session != null && repository != null) {
      try {
        await repository.deleteOutcome(session.uid, outcomeId);
      } on Object {
        outcomeError = 'Outcome deletion pending · retry when connected';
        notifyListeners();
      }
    }
  }

  Future<void> setRecommendationStatus(
    String id,
    RecommendationStatus status,
  ) async {
    final ensureCurrent = _beginMutation();
    _recommendationStatuses[id] = status;
    _recommendations = _recommendations
        .map((item) => item.id == id ? item.copyWith(status: status) : item)
        .toList();
    guidanceError = null;
    notifyListeners();
    await _writeLocal();
    ensureCurrent();
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session != null && repository != null) {
      try {
        await repository.setRecommendationStatus(
          session.uid,
          id,
          status: status,
        );
      } on Object {
        guidanceError =
            'Recommendation updated on this device · cloud update pending';
        notifyListeners();
      }
    }
  }

  Future<void> setRecommendationFeedback(String id, bool helpful) async {
    final ensureCurrent = _beginMutation();
    _recommendationFeedback[id] = helpful;
    _recommendations = _recommendations
        .map((item) => item.id == id ? item.copyWith(helpful: helpful) : item)
        .toList();
    guidanceError = null;
    notifyListeners();
    await _writeLocal();
    ensureCurrent();
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session != null && repository != null) {
      try {
        await repository.setRecommendationFeedback(
          session.uid,
          id,
          helpful: helpful,
        );
      } on Object {
        guidanceError = 'Feedback saved on this device · cloud update pending';
        notifyListeners();
      }
    }
  }

  Future<void> dismissRiskAlert(String id) async {
    final ensureCurrent = _beginMutation();
    _dismissedRiskAlertIds.add(id);
    _riskAlerts = _riskAlerts
        .map((item) => item.id == id ? item.copyWith(dismissed: true) : item)
        .toList();
    guidanceError = null;
    notifyListeners();
    await _writeLocal();
    ensureCurrent();
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session != null && repository != null) {
      try {
        await repository.setRiskAlertDismissed(
          session.uid,
          id,
          dismissed: true,
        );
      } on Object {
        guidanceError = 'Alert dismissed on this device · cloud update pending';
        notifyListeners();
      }
    }
    await refreshNotifications();
  }

  Future<NotificationPermissionState> setNotifications(bool value) async {
    _requirePrivacy();
    final revision = _sessionRevision;
    final uid = cloudUid;
    bool current() =>
        revision == _sessionRevision && uid == cloudUid && _canProcessData;
    if (!value) {
      notificationsEnabled = false;
      notificationError = null;
      notificationPermission = NotificationPermissionState.unknown;
      _notificationPlan = const NotificationPlan(
        state: NotificationPlanState.disabled,
      );
      try {
        await _notificationService.cancelGuidance();
      } on Object {
        notificationError = 'Could not clear scheduled alerts.';
      }
      await _commit();
      return notificationPermission;
    }

    isNotificationSyncing = true;
    notificationError = null;
    notifyListeners();
    try {
      final permission = await _notificationService.requestPermission();
      if (!current()) return notificationPermission;
      notificationPermission = permission;
      notificationsEnabled =
          notificationPermission == NotificationPermissionState.granted;
      if (!notificationsEnabled) {
        notificationError = switch (notificationPermission) {
          NotificationPermissionState.unavailable =>
            'Scheduled alerts are unavailable on this device.',
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
    } finally {
      isNotificationSyncing = false;
    }
    await _commit();
    if (notificationsEnabled) await refreshNotifications();
    return notificationPermission;
  }

  Future<void> setCrashNotifications(bool value) async {
    final ensureCurrent = _beginMutation();
    crashNotificationsEnabled = value;
    await _commit();
    ensureCurrent();
    await refreshNotifications();
  }

  Future<void> setRecoveryNotifications(bool value) async {
    final ensureCurrent = _beginMutation();
    recoveryNotificationsEnabled = value;
    await _commit();
    ensureCurrent();
    await refreshNotifications();
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
    final revision = _sessionRevision;
    final uid = cloudUid;
    bool current() =>
        revision == _sessionRevision && uid == cloudUid && _canProcessData;
    if (!healthAvailable) return false;
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
      isHealthAuthorizing = false;
    }
    await _commit();
    if (healthAuthorized) {
      await _ensureContinuousHealthUpdates();
      await syncHealth(reason: HealthRefreshReason.initial);
    }
    return healthAuthorized;
  }

  Future<HealthAuthorizationState> refreshHealthAuthorization({
    bool notify = true,
  }) async {
    final revision = _sessionRevision;
    final previous = healthAuthorization;
    final status = await _healthService.authorizationStatus();
    if (revision != _sessionRevision || deletionPending || isSignedOut) {
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
        healthAuthorized = false;
        if (healthBackgroundRefreshEnabled) {
          await _healthService.disableBackgroundUpdates();
          healthBackgroundRefreshEnabled = false;
          healthSyncStatus = HealthSyncStatus.disabled;
        }
      }
    }
    if (notify) notifyListeners();
    return healthAuthorization;
  }

  Future<void> disconnectHealth() async {
    await _healthService.disableBackgroundUpdates();
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
    if (!_canProcessData) return;
    if (isSignedOut) return;
    final now = _now();
    if (!ContinuousRefreshLogic.shouldRefresh(
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
  }) async {
    if (!_canProcessData || !healthAuthorized || isSyncing) {
      return null;
    }
    final sessionRevision = _sessionRevision;
    bool sessionEnded() {
      if (!isSignedOut &&
          _canProcessData &&
          sessionRevision == _sessionRevision) {
        return false;
      }
      isSyncing = false;
      if (notify) notifyListeners();
      return true;
    }

    final attemptTime = _now();
    final before = List<SignalReading>.of(signals);
    isSyncing = true;
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
      healthSyncError = error.message;
    } on Object {
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
      sleepSyncError = error.message;
    } on Object {
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
      activitySyncError = error.message;
    } on Object {
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
    isSyncing = false;
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
    if (!_canProcessData) return;
    if (isSignedOut ||
        _isSigningOut ||
        !healthAuthorized ||
        healthBackgroundRefreshEnabled) {
      return;
    }
    final sessionRevision = _sessionRevision;
    healthBackgroundRefreshEnabled = await _healthService
        .enableBackgroundUpdates(
          () => refreshHealthIfDue(reason: HealthRefreshReason.background),
        );
    if (isSignedOut || _isSigningOut || sessionRevision != _sessionRevision) {
      await _healthService.disableBackgroundUpdates();
      healthBackgroundRefreshEnabled = false;
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
            if (ownedModel || key == _prepWindowKey(uid) || ownedPrep) {
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
    await _discardPersonalizedModel();
    ensureCurrent();
    signals = [];
    checkIns = [];
    _outcomes = [];
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
      _scoreRefreshGeneration++;
      _energyModelService.unload();
      await _invalidateModelPreparation();
      await _healthService.disableBackgroundUpdates();
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
    _sessionRevision++;
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
    await _healthService.disableBackgroundUpdates();
    try {
      await _notificationService.cancelGuidance();
    } on Object {
      // Local reset still proceeds when platform notification APIs fail.
    }
    onboardingComplete = false;
    notificationsEnabled = false;
    crashNotificationsEnabled = true;
    recoveryNotificationsEnabled = true;
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
    'lastSync': lastSync?.toIso8601String(),
    'lastHealthSyncAttempt': lastHealthSyncAttempt?.toIso8601String(),
    'lastHealthChangeAt': lastHealthChangeAt?.toIso8601String(),
    'healthSyncStatus': healthSyncStatus.name,
    'lastHealthRefreshReason': lastHealthRefreshReason?.name,
    'healthBackgroundRefreshEnabled': healthBackgroundRefreshEnabled,
    'profile': profile.toJson(),
    'signals': signals.map((item) => item.toJson()).toList(),
    'checkIns': checkIns.map((item) => item.toJson()).toList(),
    'outcomes': _outcomes.map((item) => item.toJson()).toList(),
    'recommendationStatuses': _recommendationStatuses.map(
      (key, value) => MapEntry(key, value.name),
    ),
    'recommendationFeedback': _recommendationFeedback,
    'dismissedRiskAlertIds': _dismissedRiskAlertIds.toList(),
  };

  Future<void> _commit({
    bool energyInputsChanged = false,
    bool forecastInputsChanged = false,
  }) async {
    if (!_canProcessData) return;
    await _invalidateModelPreparation();
    notifyListeners();
    await _writeLocal();
    await _pushCloud();
    if (energyInputsChanged && onboardingComplete) {
      await refreshScores(forceRecalculate: true);
    }
    if ((energyInputsChanged || forecastInputsChanged) && onboardingComplete) {
      await refreshForecasts(forceRecalculate: true);
      await refreshGuidance();
    }
    if (energyInputsChanged && onboardingComplete) {
      await refreshInsights();
    }
  }

  Future<void> _writeLocal() async {
    if (deletionPending || isDeletingAccount) return;
    final revision = _sessionRevision;
    final preferences = await SharedPreferences.getInstance();
    if (revision != _sessionRevision || deletionPending || isDeletingAccount) {
      return;
    }
    await preferences.setString(_storageKey, jsonEncode(_json()));
  }

  Future<void> _hydrateOrMigrateCloud() async {
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session == null || repository == null) return;
    final revision = _sessionRevision;
    _cloudPrivacyVerified = false;
    isCloudSyncing = true;
    cloudSyncError = null;
    notifyListeners();
    try {
      final remote = await repository.readUser(session.uid);
      if (cloudUid != session.uid ||
          _sessionRevision != revision ||
          _isSigningOut ||
          deletionPending) {
        return;
      }
      final metadataFetchedAt = _now();
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
        _applyCloud(remote);
        _cloudPrivacyVerified = true;
        if (remote.deletionPending) {
          await _saveDeletionJournal(session.uid, 'requested');
        }
        accountEmail = session.email;
        if (privacyFeaturesAllowed &&
            remote.migrationVersion < localMigrationVersion) {
          await repository.replaceUser(
            session.uid,
            remote.copyWith(migrationVersion: localMigrationVersion),
          );
        }
      }
      if (cloudUid == session.uid &&
          _sessionRevision == revision &&
          !_isSigningOut) {
        _cloudMetadataUid = session.uid;
        _cloudMetadataFetchedAt = metadataFetchedAt;
        _cloudEnergySummary = remote?.personalizedEnergyModel;
        _cloudUserUpdatedAt = remote?.userUpdatedAt;
      }
    } on Object catch (error) {
      if (cloudUid == session.uid && _sessionRevision == revision) {
        cloudSyncError = error.toString();
      }
    } finally {
      isCloudSyncing = false;
    }
  }

  Future<void> _pushCloud() async {
    if (!_canProcessData) return;
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session == null || repository == null) return;
    isCloudSyncing = true;
    cloudSyncError = null;
    notifyListeners();
    try {
      await repository.replaceUser(
        session.uid,
        _cloudState(migrationVersion: localMigrationVersion),
      );
    } on Object catch (error) {
      // SharedPreferences remains the authoritative offline cache. A later
      // successful commit retries the complete user-scoped snapshot.
      cloudSyncError = error.toString();
    } finally {
      isCloudSyncing = false;
      notifyListeners();
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
    notificationPermission = NotificationPermissionState.unknown;
    notificationError = null;
    _notificationPlan = const NotificationPlan(
      state: NotificationPlanState.disabled,
    );
    outcomeConsent = state.outcomeConsent;
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
  }

  static String _clock(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$hour:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

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
      if (points[index].time != day.add(Duration(hours: startHour + index))) {
        return false;
      }
    }
    return true;
  }

  static String _dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
