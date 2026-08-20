import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activity_log_logic.dart';
import 'activity_sync_logic.dart';
import 'check_in_logic.dart';
import 'cloud_repository.dart';
import 'cloud_schema.dart';
import 'daily_history_logic.dart';
import 'demo_data.dart';
import 'fatigue_engine.dart';
import 'health_service.dart';
import 'heart_sync_logic.dart';
import 'insights_logic.dart';
import 'models.dart';
import 'notification_logic.dart';
import 'notification_service.dart';
import 'reaction_test_logic.dart';
import 'sleep_sync_logic.dart';
import 'today_dashboard_logic.dart';

class AppController extends ChangeNotifier {
  AppController({
    HealthService? healthService,
    AccountAuth? accountAuth,
    NotificationService? notificationService,
    this.cloudRepository,
  }) : _healthService = healthService ?? const HealthService(),
       _accountAuth = accountAuth ?? const LocalOnlyAccountAuth(),
       _notificationService = notificationService ?? LocalNotificationService();

  static const _storageKey = 'tonyo_state_v1';
  static const forecastDayCount = 7;
  static const forecastFreshnessWindow = Duration(hours: 12);
  final HealthService _healthService;
  final AccountAuth _accountAuth;
  final NotificationService _notificationService;
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
  bool isSyncing = false;
  bool isCloudSyncing = false;
  bool isEnergyScoreLoading = false;
  bool isForecastLoading = false;
  bool isGuidanceLoading = false;
  bool isNotificationSyncing = false;
  bool isInsightsLoading = false;
  DateTime? lastSync;
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
  String? healthError;
  String? healthSyncError;
  String? sleepSyncError;
  String? activitySyncError;
  HealthAuthorizationState healthAuthorization =
      HealthAuthorizationState.unavailable;
  NotificationPermissionState notificationPermission =
      NotificationPermissionState.unknown;
  UserProfile profile = const UserProfile();
  List<SignalReading> signals = [];
  List<DailyCheckIn> checkIns = [];
  ScoreSnapshot? _scoreSnapshot;
  List<SignalReading> _todaySignals = [];
  bool _scoreLoadedFromSnapshot = false;
  bool _forecastLoadedFromCloud = false;
  bool _guidanceSavedToCloud = false;
  bool insightsLoadedFromCloud = false;
  final Map<String, List<ForecastPoint>> _forecastsByDay = {};
  final Map<String, RecommendationStatus> _recommendationStatuses = {};
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
  NotificationPlan get notificationPlan => _notificationPlan;
  int get scheduledNotificationCount =>
      notificationPermission == NotificationPermissionState.granted
      ? _notificationPlan.notifications.length
      : 0;
  GuidanceNotification? get nextScheduledNotification =>
      scheduledNotificationCount == 0
      ? null
      : _notificationPlan.notifications.first;
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
    final currentTime = DateTime.now();
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
            savedSnapshot.cognitiveFreshness != null) {
          _scoreSnapshot = savedSnapshot;
          _scoreLoadedFromSnapshot = true;
          return;
        }

        final scoringResults = await Future.wait<Object?>([
          repository.signalsByRange(
            session.uid,
            start: start.subtract(const Duration(days: 6)),
            end: end,
          ),
          repository.reactionBaselineWindow(session.uid, limit: 14),
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
        final reactionHistory = scoringResults[1]! as List<SignalReading>;
        scoringSignals = {
          for (final signal in scoringSignals) signal.id: signal,
          for (final signal in reactionHistory) signal.id: signal,
        }.values.toList();
        scoringCheckIns = scoringResults[2]! as List<DailyCheckIn>;
        previousDay = scoringResults[3] as ScoreSnapshot?;
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

  /// Builds Versions 0.18–0.19 guidance from a seven-day, user-scoped input
  /// range, then replaces today's private recommendation and alert documents.
  Future<void> refreshGuidance({DateTime? day, bool notify = true}) async {
    final clock = DateTime.now();
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
      List<RiskAlert> savedAlerts = const [],
    }) {
      final windowValues = FatigueEngine.windows(
        forecastDataFor(targetDay),
        score,
        signals: sourceSignals,
        checkIns: sourceCheckIns,
      );
      final savedStatuses = {
        for (final item in savedRecommendations) item.id: item.status,
      };
      _recommendations =
          FatigueEngine.recommendations(
            windowValues,
            score,
            day: targetDay,
            generatedAt: clock,
          ).map((item) {
            final status =
                savedStatuses[item.id] ?? _recommendationStatuses[item.id];
            if (status != null) _recommendationStatuses[item.id] = status;
            return item.copyWith(status: status);
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
          repository.riskAlertsForDay(session.uid, targetDay),
        ]);
        derive(
          sourceSignals: values[0] as List<SignalReading>,
          sourceCheckIns: values[1] as List<DailyCheckIn>,
          savedRecommendations: values[2] as List<Recommendation>,
          savedAlerts: values[3] as List<RiskAlert>,
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
    if (isCloudAuthenticated) {
      await _hydrateOrMigrateCloud();
      await _writeLocal();
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
    await _finishCloudAuth();
  }

  /// Registers a new Firebase Auth user, then uploads this device’s local
  /// Tonyo data if the cloud account is empty.
  Future<void> createCloudAccount({
    required String email,
    required String password,
  }) async {
    if (!cloudEnabled) throw StateError('Firebase is not configured.');
    await _accountAuth.register(email: email, password: password);
    await _finishCloudAuth();
  }

  Future<void> _finishCloudAuth() async {
    await _hydrateOrMigrateCloud();
    await _writeLocal();
    if (onboardingComplete) {
      await refreshScores(notify: false);
      await refreshForecasts(notify: false);
      await refreshGuidance(notify: false);
      await refreshInsights(notify: false);
    }
    notifyListeners();
  }

  Future<void> signOut() async {
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
    final when = timestamp ?? DateTime.now();
    final checkInId = id ?? 'checkin-${when.microsecondsSinceEpoch}';
    checkIns.removeWhere((item) => item.id == checkInId);
    checkIns.insert(
      0,
      DailyCheckIn(
        id: checkInId,
        timestamp: when,
        energy: CheckInLogic.clampRating(energy),
        mood: CheckInLogic.clampRating(mood),
        stress: CheckInLogic.clampRating(stress),
        // Period always follows the check-in timestamp (morning < 14:00).
        period: CheckInLogic.periodFor(when),
        note: note,
      ),
    );
    await _commit(energyInputsChanged: true);
  }

  Future<void> addReactionResult(double averageMs, {String? note}) async {
    if (!ReactionTestLogic.isValidReaction(averageMs.round())) {
      throw ArgumentError(
        'Reaction average must be between '
        '${ReactionTestLogic.minValidMs} and ${ReactionTestLogic.maxValidMs} ms',
      );
    }
    await addSignal(
      SignalType.reactionTime,
      averageMs,
      note: note ?? 'Three-round reaction test',
    );
  }

  Future<void> deleteSignal(String id) async {
    signals.removeWhere((item) => item.id == id);
    await _commit(energyInputsChanged: true);
  }

  Future<void> deleteCheckIn(String id) async {
    checkIns.removeWhere((item) => item.id == id);
    await _commit(energyInputsChanged: true);
  }

  Future<void> setRecommendationStatus(
    String id,
    RecommendationStatus status,
  ) async {
    _recommendationStatuses[id] = status;
    _recommendations = _recommendations
        .map((item) => item.id == id ? item.copyWith(status: status) : item)
        .toList();
    await _commit();
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
    await _commit();
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
    if (healthAuthorized) await syncHealth();
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
      }
    }
    if (notify) notifyListeners();
    return healthAuthorization;
  }

  Future<void> disconnectHealth() async {
    healthAuthorized = false;
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

  Future<HeartSyncMergeResult?> syncHealth() async {
    if (!healthAuthorized || isSyncing) return null;
    isSyncing = true;
    healthSyncError = null;
    sleepSyncError = null;
    activitySyncError = null;
    notifyListeners();
    HeartSyncMergeResult? heartResult;
    SleepSyncMergeResult? sleepResult;
    ActivitySyncMergeResult? activityResult;
    try {
      final imported = await _healthService.sync();
      heartResult = HeartSyncLogic.merge(existing: signals, imported: imported);
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
      sleepResult = SleepSyncLogic.merge(existing: signals, imported: imported);
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
      );
      signals = activityResult.readings;
      lastActivityImportCount = activityResult.importedCount;
      lastActivityDuplicateCount = activityResult.duplicateCount;
      lastActivityRejectedCount = activityResult.rejectedCount;
    } on HealthSyncException catch (error) {
      activitySyncError = error.message;
    } on Object {
      activitySyncError =
          'Apple Health workout and hydration data could not be imported.';
    } finally {
      if (heartResult != null ||
          (sleepResult?.importedNightCount ?? 0) > 0 ||
          activityResult != null) {
        lastSync = DateTime.now();
      }
      isSyncing = false;
      notifyListeners();
    }

    if (heartResult == null && sleepResult == null && activityResult == null) {
      return null;
    }
    await _commit(
      energyInputsChanged:
          (heartResult?.importedCount ?? 0) > 0 ||
          (sleepResult?.importedSignalCount ?? 0) > 0 ||
          (activityResult?.importedCount ?? 0) > 0,
    );
    return heartResult;
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
    if (isSyncing) return 'Reading the last 30 days of workouts and water…';
    if (activitySyncError != null) return activitySyncError!;
    if (lastSync == null) {
      return 'Workouts and hydration have not been synced yet.';
    }
    final workouts = healthKitWorkoutSignalCount;
    final hydration = healthKitHydrationSignalCount;
    final total = workouts + hydration;
    if (lastActivityImportCount == 0) {
      if (lastActivityDuplicateCount > 0) {
        return 'Up to date · $lastActivityDuplicateCount matching ${lastActivityDuplicateCount == 1 ? 'sample was' : 'samples were'} already saved.';
      }
      return total == 0
          ? 'No readable workouts or water samples found. Manual activity logging remains available.'
          : 'Up to date · $workouts ${workouts == 1 ? 'workout' : 'workouts'} and $hydration water ${hydration == 1 ? 'sample' : 'samples'} saved.';
    }
    return 'Imported $lastActivityImportCount new ${lastActivityImportCount == 1 ? 'activity signal' : 'activity signals'} · $workouts ${workouts == 1 ? 'workout' : 'workouts'} and $hydration water ${hydration == 1 ? 'sample' : 'samples'} saved.';
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
    lastSync = null;
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
    _dismissedRiskAlertIds.clear();
    _recommendations = [];
    _riskAlerts = [];
    guidanceError = null;
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session != null && repository != null) {
      await repository.clearScoreSnapshots(session.uid);
      await repository.clearGuidance(session.uid);
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
    'profile': profile.toJson(),
    'signals': signals.map((item) => item.toJson()).toList(),
    'checkIns': checkIns.map((item) => item.toJson()).toList(),
    'recommendationStatuses': _recommendationStatuses.map(
      (key, value) => MapEntry(key, value.name),
    ),
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
      _dismissedRiskAlertIds.clear();
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
    // Health authorization is device-specific. Cloud state must not turn on
    // access on a different device; the local platform check remains primary.
    lastSync = state.lastSync;
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
    _recommendationStatuses.clear();
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
    final statuses =
        (json['recommendationStatuses'] as Map?)?.cast<String, dynamic>() ??
        const {};
    for (final entry in statuses.entries) {
      _recommendationStatuses[entry.key] = RecommendationStatus.values.byName(
        entry.value as String,
      );
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
