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
import 'health_service.dart';
import 'heart_sync_logic.dart';
import 'insights_logic.dart';
import 'models.dart';
import 'notification_logic.dart';
import 'notification_service.dart';
import 'personal_baseline_logic.dart';
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
    this.cloudRepository,
  }) : _healthService = healthService ?? const HealthService(),
       _screenTimeService = screenTimeService ?? const ScreenTimeService(),
       _accountAuth = accountAuth ?? const LocalOnlyAccountAuth(),
       _notificationService = notificationService ?? LocalNotificationService(),
       _now = clock ?? DateTime.now;

  static const _storageKey = 'tonyo_state_v1';
  static const forecastDayCount = 7;
  static const forecastFreshnessWindow = Duration(hours: 12);
  static const outcomeHistoryWindow = Duration(days: 90);
  final HealthService _healthService;
  final ScreenTimeService _screenTimeService;
  final AccountAuth _accountAuth;
  final NotificationService _notificationService;
  final DateTime Function() _now;
  final CloudRepository? cloudRepository;

  bool isReady = false;
  bool onboardingComplete = false;
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

  ScoreSnapshot get score =>
      _scoreSnapshot ??
      FatigueEngine.score(signals: signals, checkIns: checkIns);
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
    final currentTime = _now();
    final target = day ?? currentTime;
    final start = DateTime(target.year, target.month, target.day);
    final end = start.add(const Duration(days: 1));
    final calculationTime = _sameDay(currentTime, start)
        ? currentTime
        : end.subtract(const Duration(microseconds: 1));
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;

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
        final savedSnapshot = dashboardResults[0] as ScoreSnapshot?;
        _todaySignals = dashboardResults[1]! as List<SignalReading>;
        if (!forceRecalculate &&
            savedSnapshot != null &&
            savedSnapshot.hasCognitiveScore &&
            savedSnapshot.freshness != null &&
            savedSnapshot.cognitiveFreshness != null &&
            savedSnapshot.personalBaselines != null) {
          _scoreSnapshot = savedSnapshot;
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
      final snapshot = FatigueEngine.score(
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
      if (canUseCloud) {
        await repository.upsertScoreSnapshot(session.uid, snapshot);
      }
      _scoreSnapshot = snapshot;
      _scoreLoadedFromSnapshot = false;
    } on Object {
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
      isEnergyScoreLoading = false;
      if (notify) notifyListeners();
    }
  }

  /// Compatibility entry point retained for Version 0.11 callers.
  Future<void> refreshEnergyScore({DateTime? day, bool notify = true}) =>
      refreshScores(day: day, notify: notify, forceRecalculate: true);

  /// Loads or regenerates Today and Tomorrow hourly forecasts. Authenticated
  /// users read and write their private forecastPoints collection; local and
  /// failed-cloud sessions retain the same deterministic offline model.
  Future<void> refreshForecasts({
    DateTime? day,
    bool notify = true,
    bool forceRecalculate = false,
  }) async {
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
        _forecastsByDay.addAll(generated);
        _forecastLoadedFromCloud = false;
        return;
      }

      _generateLocalForecasts(days, generatedAt: clock);
      _forecastLoadedFromCloud = false;
    } on Object {
      _generateLocalForecasts(days, generatedAt: clock);
      _forecastLoadedFromCloud = false;
      forecastError = 'Cloud forecast unavailable · using cached inputs';
    } finally {
      isForecastLoading = false;
      if (notify) notifyListeners();
    }
  }

  /// Builds Version 0.30's feedback-ranked daily plan plus Version 0.19 alerts
  /// from owner-scoped inputs, then replaces today's private documents.
  Future<void> refreshGuidance({DateTime? day, bool notify = true}) async {
    final clock = _now();
    final target = day ?? clock;
    final targetDay = DateTime(target.year, target.month, target.day);
    final rangeStart = targetDay.subtract(const Duration(days: 6));
    final rangeEnd = targetDay.add(const Duration(days: 1));
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;

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
        _guidanceSavedToCloud = true;
        return;
      }
      derive(sourceSignals: signals, sourceCheckIns: checkIns);
      _guidanceSavedToCloud = false;
    } on Object {
      derive(sourceSignals: signals, sourceCheckIns: checkIns);
      _guidanceSavedToCloud = false;
      guidanceError = 'Cloud guidance unavailable · using cached inputs';
    } finally {
      isGuidanceLoading = false;
      if (notificationsEnabled) {
        await refreshNotifications(notify: false);
      }
      if (notify) notifyListeners();
    }
  }

  Future<void> refreshNotifications({bool notify = true}) async {
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
      notificationPermission = await _notificationService.permissionStatus();
      if (notificationPermission != NotificationPermissionState.granted) {
        await _notificationService.cancelGuidance();
        notificationError =
            notificationPermission == NotificationPermissionState.denied
            ? 'Notifications are blocked in system settings.'
            : 'Notification permission is required.';
        return;
      }
      await _notificationService.reconcile(_notificationPlan.notifications);
    } on Object {
      notificationError = 'Notification schedule unavailable · try again';
    } finally {
      isNotificationSyncing = false;
      if (notify) notifyListeners();
    }
  }

  Future<void> refreshInsights({DateTime? day, bool notify = true}) async {
    final clock = day ?? DateTime.now();
    final targetDay = DateTime(clock.year, clock.month, clock.day);
    final rangeStart = targetDay.subtract(
      const Duration(days: InsightsLogic.queryLookbackDays - 1),
    );
    final rangeEnd = targetDay.add(const Duration(days: 1));
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;

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
      _insightsSnapshot = InsightsLogic.build(
        now: clock,
        signals: signals,
        checkIns: checkIns,
      );
      insightsLoadedFromCloud = false;
      insightsError = 'Cloud insights unavailable · using cached entries';
    } finally {
      isInsightsLoading = false;
      if (notify) notifyListeners();
    }
  }

  /// Loads only consented, owner-scoped Version 0.31 outcome records.
  Future<void> refreshOutcomes({bool notify = true}) async {
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
    isOutcomeLoading = true;
    outcomeError = null;
    if (notify) notifyListeners();
    try {
      if (session != null && repository != null) {
        _outcomes = await repository.outcomesByRange(
          session.uid,
          start: now.subtract(outcomeHistoryWindow),
          end: now.add(const Duration(days: 1)),
        );
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
      outcomeError = 'Private outcomes unavailable · cached records retained';
    } finally {
      isOutcomeLoading = false;
      if (notify) notifyListeners();
    }
  }

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
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
    await refreshHealthAuthorization(notify: false);
    await refreshScreenTimeAuthorization(notify: false);
    if (isCloudAuthenticated) {
      await _hydrateOrMigrateCloud();
      await _writeLocal();
    }
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
    if (cloudEnabled) {
      if (normalizedEmail == null ||
          normalizedEmail.isEmpty ||
          password == null ||
          password.isEmpty) {
        throw ArgumentError('Email and password are required for cloud setup.');
      }
      if (signInToExistingAccount) {
        await _accountAuth.signIn(email: normalizedEmail, password: password);
        await _hydrateOrMigrateCloud();
        if (onboardingComplete) {
          await _writeLocal();
          if (outcomeConsent) await refreshOutcomes(notify: false);
          await refreshScores(notify: false);
          await refreshForecasts(notify: false);
          await refreshGuidance(notify: false);
          await refreshInsights(notify: false);
          notifyListeners();
          return;
        }
      } else {
        await _accountAuth.register(email: normalizedEmail, password: password);
      }
    }
    profile = newProfile;
    accountEmail =
        _accountAuth.currentSession?.email ?? normalizedEmail ?? accountEmail;
    onboardingComplete = true;
    if (signals.isEmpty) {
      signals = buildDemoSignals(DateTime.now());
      checkIns = buildDemoCheckIns(DateTime.now());
    }
    await _commit(energyInputsChanged: true);
  }

  Future<void> signIn({required String email, required String password}) async {
    if (!cloudEnabled) throw StateError('Firebase is not configured.');
    await _accountAuth.signIn(email: email, password: password);
    await _hydrateOrMigrateCloud();
    await _writeLocal();
    if (outcomeConsent) await refreshOutcomes(notify: false);
    if (onboardingComplete) {
      await refreshScores(notify: false);
      await refreshForecasts(notify: false);
      await refreshGuidance(notify: false);
      await refreshInsights(notify: false);
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    await _healthService.disableBackgroundUpdates();
    healthBackgroundRefreshEnabled = false;
    try {
      await _notificationService.cancelGuidance();
    } on Object {
      // Signing out must still succeed if the platform scheduler is unavailable.
    }
    await _accountAuth.signOut();
    cloudSyncError = null;
    insightsLoadedFromCloud = false;
    _notificationPlan = const NotificationPlan(
      state: NotificationPlanState.disabled,
    );
    notificationPermission = NotificationPermissionState.unknown;
    notifyListeners();
  }

  Future<void> updateProfile(UserProfile value) async {
    profile = value;
    await _commit(forecastInputsChanged: true);
  }

  Future<void> addSignal(SignalType type, double value, {String? note}) async {
    signals.insert(
      0,
      SignalReading(
        id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        value: value,
        timestamp: DateTime.now(),
        note: note,
      ),
    );
    await _commit(energyInputsChanged: true);
  }

  Future<void> saveActivityLog({
    String? id,
    double? hydrationLiters,
    double? studyHours,
    double? exerciseHours,
    double? screenTimeHours,
    DateTime? timestamp,
  }) async {
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
    final now = DateTime.now();
    final groupId = id ?? 'activity-${now.microsecondsSinceEpoch}';
    final recordedAt = timestamp ?? now;
    signals.removeWhere((item) => item.groupId == groupId);
    signals.insertAll(
      0,
      values.entries.map(
        (entry) => SignalReading(
          id: '$groupId-${entry.key.name}',
          groupId: groupId,
          type: entry.key,
          value: entry.value,
          timestamp: recordedAt,
          note: switch (entry.key) {
            SignalType.hydration when hydrationLiters != null =>
              ActivitySyncLogic.manualCorrectionNote,
            SignalType.exercise when exerciseHours != null =>
              ActivitySyncLogic.manualCorrectionNote,
            SignalType.hydration ||
            SignalType.exercise => ActivitySyncLogic.blankManualValueNote,
            _ => null,
          },
        ),
      ),
    );
    await _commit(energyInputsChanged: true);
  }

  Future<void> deleteActivityLog(String id) async {
    signals.removeWhere((item) => item.groupId == id);
    await _commit(energyInputsChanged: true);
  }

  Future<void> addSleep({
    String? id,
    required DateTime bedtime,
    required DateTime wakeTime,
    required double quality,
  }) async {
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
    final groupId = id ?? 'sleep-${DateTime.now().microsecondsSinceEpoch}';
    signals.removeWhere((item) => item.groupId == groupId);
    signals.insertAll(0, [
      SignalReading(
        id: '$groupId-duration',
        groupId: groupId,
        type: SignalType.sleep,
        value: hours,
        timestamp: end,
        quality: quality / 5,
        note: '${_clock(start)}–${_clock(end)} · quality ${quality.round()}/5',
      ),
      SignalReading(
        id: '$groupId-bedtime',
        groupId: groupId,
        type: SignalType.bedtime,
        value: start.hour + start.minute / 60,
        timestamp: start,
      ),
    ]);
    await _commit(energyInputsChanged: true);
  }

  Future<void> deleteSleepLog(String id) async {
    signals.removeWhere((item) => item.groupId == id);
    await _commit(energyInputsChanged: true);
  }

  Future<void> addCheckIn({
    String? id,
    required double energy,
    required double mood,
    required double stress,
    String note = '',
    DateTime? timestamp,
  }) async {
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
    final checkIn = DailyCheckIn(
      id: checkInId,
      timestamp: when,
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
        note: note ?? 'Three-round reaction test',
      ),
    );
    await _commit(energyInputsChanged: true);
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
    if (!outcomeConsent) {
      throw StateError('Outcome learning requires explicit consent.');
    }
    _outcomes.removeWhere((item) => item.id == outcome.id);
    _outcomes.insert(0, outcome);
    outcomeError = null;
    notifyListeners();
    await _writeLocal();
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
    signals.removeWhere((item) => item.id == id);
    await _commit(energyInputsChanged: true);
    await _deleteOutcome('reaction-$id');
  }

  Future<void> deleteCheckIn(String id) async {
    checkIns.removeWhere((item) => item.id == id);
    await _commit(energyInputsChanged: true);
    await _deleteOutcome('energy-checkin-$id');
  }

  Future<void> _deleteOutcome(String outcomeId) async {
    _outcomes.removeWhere((item) => item.id == outcomeId);
    await _writeLocal();
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
    _recommendationStatuses[id] = status;
    _recommendations = _recommendations
        .map((item) => item.id == id ? item.copyWith(status: status) : item)
        .toList();
    guidanceError = null;
    notifyListeners();
    await _writeLocal();
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
    _recommendationFeedback[id] = helpful;
    _recommendations = _recommendations
        .map((item) => item.id == id ? item.copyWith(helpful: helpful) : item)
        .toList();
    guidanceError = null;
    notifyListeners();
    await _writeLocal();
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
    _dismissedRiskAlertIds.add(id);
    _riskAlerts = _riskAlerts
        .map((item) => item.id == id ? item.copyWith(dismissed: true) : item)
        .toList();
    guidanceError = null;
    notifyListeners();
    await _writeLocal();
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
      notificationPermission = await _notificationService.requestPermission();
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
    crashNotificationsEnabled = value;
    await _commit();
    await refreshNotifications();
  }

  Future<void> setRecoveryNotifications(bool value) async {
    recoveryNotificationsEnabled = value;
    await _commit();
    await refreshNotifications();
  }

  Future<void> setOutcomeConsent(bool value) async {
    outcomeConsent = value;
    outcomeError = null;
    if (!value) _outcomes = [];
    await _commit();
    if (value) await refreshOutcomes();
  }

  Future<bool> connectHealth() async {
    if (!healthAvailable) return false;
    isHealthAuthorizing = true;
    healthError = null;
    healthSyncError = null;
    sleepSyncError = null;
    activitySyncError = null;
    notifyListeners();
    try {
      healthAuthorization = await _healthService.requestAuthorization();
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
    final previous = healthAuthorization;
    final status = await _healthService.authorizationStatus();
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
    isScreenTimeAuthorizing = true;
    screenTimeError = null;
    notifyListeners();
    try {
      screenTimeAuthorization = await _screenTimeService.requestAuthorization();
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
      screenTimeAuthorization = ScreenTimeAuthorizationState.error;
      screenTimeError = 'Screen Time report permission could not be requested.';
    } finally {
      isScreenTimeAuthorizing = false;
      notifyListeners();
    }
    return screenTimeAuthorization;
  }

  Future<bool> showScreenTimeReport() async {
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
    if (!healthAuthorized || isSyncing) return null;
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

    try {
      final imported = await _healthService.syncSleep();
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

    try {
      final imported = await _healthService.syncActivity();
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
    } finally {
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
    }

    final meaningfulChange = ContinuousRefreshLogic.hasMeaningfulModelChange(
      before,
      signals,
    );
    if (meaningfulChange) lastHealthChangeAt = attemptTime;
    await _commit(energyInputsChanged: meaningfulChange);
    return heartResult;
  }

  Future<void> _ensureContinuousHealthUpdates() async {
    if (!healthAuthorized || healthBackgroundRefreshEnabled) return;
    healthBackgroundRefreshEnabled = await _healthService
        .enableBackgroundUpdates(
          () => refreshHealthIfDue(reason: HealthRefreshReason.background),
        );
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
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session == null || repository == null) return exportJson();
    final exported = await repository.exportUser(session.uid);
    return const JsonEncoder.withIndent('  ').convert(exported);
  }

  /// Clears signals, check-ins, and score snapshots but keeps the account and
  /// profile so the user can start a fresh manual tracking period.
  Future<void> clearTrackingData() async {
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
  }

  /// Permanently removes all documents under users/{uid}, deletes the Firebase
  /// Auth account, and then clears the local cache.
  Future<void> deleteAccountData() async {
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session != null && repository != null) {
      await repository.deleteUserTree(session.uid);
      await _accountAuth.deleteCurrentAccount();
    }
    await reset();
  }

  Future<void> reset() async {
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
    _outcomes = [];
    isOutcomeLoading = false;
    outcomeError = null;
    healthAuthorized = false;
    isHealthAuthorizing = false;
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
    await preferences.remove(_storageKey);
    notifyListeners();
  }

  Map<String, Object?> _json() => {
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
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(_json()));
  }

  Future<void> _hydrateOrMigrateCloud() async {
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session == null || repository == null) return;
    isCloudSyncing = true;
    cloudSyncError = null;
    notifyListeners();
    try {
      final remote = await repository.readUser(session.uid);
      if (remote == null) {
        if (onboardingComplete) {
          accountEmail = session.email;
          await repository.replaceUser(
            session.uid,
            _cloudState(migrationVersion: localMigrationVersion),
          );
        }
      } else {
        _applyCloud(remote);
        accountEmail = session.email;
        if (remote.migrationVersion < localMigrationVersion) {
          await repository.replaceUser(
            session.uid,
            remote.copyWith(migrationVersion: localMigrationVersion),
          );
        }
      }
    } on Object catch (error) {
      cloudSyncError = error.toString();
    } finally {
      isCloudSyncing = false;
    }
  }

  Future<void> _pushCloud() async {
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
