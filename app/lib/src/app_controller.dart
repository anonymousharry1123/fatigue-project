import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activity_log_logic.dart';
import 'check_in_logic.dart';
import 'cloud_repository.dart';
import 'cloud_schema.dart';
import 'daily_history_logic.dart';
import 'demo_data.dart';
import 'fatigue_engine.dart';
import 'health_service.dart';
import 'models.dart';
import 'reaction_test_logic.dart';

class AppController extends ChangeNotifier {
  AppController({
    HealthService? healthService,
    AccountAuth? accountAuth,
    this.cloudRepository,
  }) : _healthService = healthService ?? const HealthService(),
       _accountAuth = accountAuth ?? const LocalOnlyAccountAuth();

  static const _storageKey = 'tonyo_state_v1';
  final HealthService _healthService;
  final AccountAuth _accountAuth;
  final CloudRepository? cloudRepository;

  bool isReady = false;
  bool onboardingComplete = false;
  bool notificationsEnabled = true;
  bool outcomeConsent = false;
  bool healthAvailable = false;
  bool healthAuthorized = false;
  bool isSyncing = false;
  bool isCloudSyncing = false;
  bool isEnergyScoreLoading = false;
  DateTime? lastSync;
  String? accountEmail;
  String? cloudSyncError;
  String? energyScoreError;
  UserProfile profile = const UserProfile();
  List<SignalReading> signals = [];
  List<DailyCheckIn> checkIns = [];
  ScoreSnapshot? _energyScore;
  final Map<String, RecommendationStatus> _recommendationStatuses = {};

  bool get cloudEnabled => _accountAuth.isConfigured && cloudRepository != null;
  bool get isCloudAuthenticated => _accountAuth.currentSession != null;
  String? get cloudUid => _accountAuth.currentSession?.uid;

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
      _energyScore ?? FatigueEngine.score(signals: signals, checkIns: checkIns);
  List<ForecastPoint> forecastFor(DateTime day) =>
      FatigueEngine.forecast(score, day);
  List<ForecastWindow> get windows =>
      FatigueEngine.windows(forecastFor(DateTime.now()), score);
  List<RiskAlert> get alerts => FatigueEngine.alerts(signals, checkIns, score);
  List<Recommendation> get recommendations =>
      FatigueEngine.recommendations(windows, score)
          .map(
            (item) => item.copyWith(status: _recommendationStatuses[item.id]),
          )
          .toList();

  /// Personal reaction baseline from prior valid tests (Version 0.9).
  double? get reactionBaseline => ReactionTestLogic.baselineMs(signals);

  List<DailyCheckIn> recentCheckIns({int limit = 8}) =>
      CheckInLogic.recentHistory(checkIns, limit: limit);

  /// Recalculates Version 0.11 from a user-scoped cloud query when signed in,
  /// then persists one deterministic scoreSnapshots/{yyyy-MM-dd} document.
  /// Local inputs remain a safe offline fallback.
  Future<void> refreshEnergyScore({DateTime? day, bool notify = true}) async {
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
      final canUseCloud =
          session != null && repository != null && cloudSyncError == null;
      if (canUseCloud) {
        scoringSignals = await repository.signalsByRange(
          session.uid,
          start: start.subtract(const Duration(days: 6)),
          end: end,
        );
        scoringCheckIns = await repository.checkInsByRange(
          session.uid,
          start: start.subtract(const Duration(hours: 36)),
          end: end,
        );
      } else if (session != null && repository != null) {
        energyScoreError = 'Cloud scoring unavailable · using cached inputs';
      }
      final snapshot = FatigueEngine.score(
        signals: scoringSignals,
        checkIns: scoringCheckIns,
        now: calculationTime,
        day: start,
      );
      if (canUseCloud) {
        await repository.upsertScoreSnapshot(session.uid, snapshot);
      }
      _energyScore = snapshot;
    } on Object {
      // A network/query failure must not make the wellness estimate disappear.
      _energyScore = FatigueEngine.score(
        signals: signals,
        checkIns: checkIns,
        now: calculationTime,
        day: start,
      );
      energyScoreError = 'Cloud scoring unavailable · using cached inputs';
    } finally {
      isEnergyScoreLoading = false;
      if (notify) notifyListeners();
    }
  }

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw != null) {
      try {
        _restoreLocal(jsonDecode(raw) as Map<String, dynamic>);
      } on Object {
        onboardingComplete = false;
        signals = [];
        checkIns = [];
      }
    }
    healthAvailable = await _healthService.isAvailable();
    if (isCloudAuthenticated) {
      await _hydrateOrMigrateCloud();
      await _writeLocal();
    }
    if (onboardingComplete) await refreshEnergyScore(notify: false);
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
          await refreshEnergyScore(notify: false);
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
    if (onboardingComplete) await refreshEnergyScore(notify: false);
    notifyListeners();
  }

  Future<void> signOut() async {
    await _accountAuth.signOut();
    cloudSyncError = null;
    notifyListeners();
  }

  Future<void> updateProfile(UserProfile value) async {
    profile = value;
    await _commit();
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
    var end = wakeTime;
    if (!end.isAfter(bedtime)) end = end.add(const Duration(days: 1));
    final validation = SleepLogEntry.validationMessage(
      bedtime: bedtime,
      wakeTime: end,
      quality: quality,
    );
    if (validation != null) throw ArgumentError(validation);
    final hours = end.difference(bedtime).inMinutes / 60;
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
        note:
            '${_clock(bedtime)}–${_clock(end)} · quality ${quality.round()}/5',
      ),
      SignalReading(
        id: '$groupId-bedtime',
        groupId: groupId,
        type: SignalType.bedtime,
        value: bedtime.hour + bedtime.minute / 60,
        timestamp: bedtime,
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
    await _commit();
  }

  Future<void> setNotifications(bool value) async {
    notificationsEnabled = value;
    await _commit();
  }

  Future<void> setOutcomeConsent(bool value) async {
    outcomeConsent = value;
    await _commit();
  }

  Future<bool> connectHealth() async {
    if (!healthAvailable) return false;
    healthAuthorized = await _healthService.requestAuthorization();
    if (healthAuthorized) await syncHealth();
    await _commit();
    return healthAuthorized;
  }

  Future<void> syncHealth() async {
    if (!healthAuthorized || isSyncing) return;
    isSyncing = true;
    notifyListeners();
    final imported = await _healthService.sync();
    for (final reading in imported) {
      final duplicate = signals.any(
        (item) =>
            item.type == reading.type &&
            item.timestamp.difference(reading.timestamp).inMinutes.abs() < 2 &&
            (item.value - reading.value).abs() < .01,
      );
      if (!duplicate) signals.add(reading);
    }
    signals.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    lastSync = DateTime.now();
    isSyncing = false;
    await _commit(energyInputsChanged: true);
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert(_json());

  Future<String> exportAllData() async {
    final session = _accountAuth.currentSession;
    final repository = cloudRepository;
    if (session == null || repository == null) return exportJson();
    final exported = await repository.exportUser(session.uid);
    return const JsonEncoder.withIndent('  ').convert(exported);
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
    onboardingComplete = false;
    notificationsEnabled = true;
    outcomeConsent = false;
    healthAuthorized = false;
    lastSync = null;
    accountEmail = null;
    profile = const UserProfile();
    signals = [];
    checkIns = [];
    _energyScore = null;
    energyScoreError = null;
    _recommendationStatuses.clear();
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
    notifyListeners();
  }

  Map<String, Object?> _json() => {
    'onboardingComplete': onboardingComplete,
    'notificationsEnabled': notificationsEnabled,
    'outcomeConsent': outcomeConsent,
    'healthAuthorized': healthAuthorized,
    'accountEmail': accountEmail,
    'lastSync': lastSync?.toIso8601String(),
    'profile': profile.toJson(),
    'signals': signals.map((item) => item.toJson()).toList(),
    'checkIns': checkIns.map((item) => item.toJson()).toList(),
    'recommendationStatuses': _recommendationStatuses.map(
      (key, value) => MapEntry(key, value.name),
    ),
  };

  Future<void> _commit({bool energyInputsChanged = false}) async {
    notifyListeners();
    await _writeLocal();
    await _pushCloud();
    if (energyInputsChanged && onboardingComplete) {
      await refreshEnergyScore();
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
    outcomeConsent: outcomeConsent,
    healthAuthorized: healthAuthorized,
    lastSync: lastSync,
    migrationVersion: migrationVersion,
    signals: List.unmodifiable(signals),
    checkIns: List.unmodifiable(checkIns),
  );

  void _applyCloud(CloudUserState state) {
    _energyScore = null;
    profile = state.profile;
    accountEmail = state.accountEmail;
    onboardingComplete = state.onboardingComplete;
    notificationsEnabled = state.notificationsEnabled;
    outcomeConsent = state.outcomeConsent;
    healthAuthorized = state.healthAuthorized;
    lastSync = state.lastSync;
    signals = [...state.signals]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    checkIns = [...state.checkIns]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  void _restoreLocal(Map<String, dynamic> json) {
    _energyScore = null;
    onboardingComplete = json['onboardingComplete'] as bool? ?? false;
    notificationsEnabled = json['notificationsEnabled'] as bool? ?? true;
    outcomeConsent = json['outcomeConsent'] as bool? ?? false;
    healthAuthorized = json['healthAuthorized'] as bool? ?? false;
    accountEmail = json['accountEmail'] as String?;
    lastSync = json['lastSync'] == null
        ? null
        : DateTime.tryParse(json['lastSync'] as String);
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
  }

  static String _clock(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$hour:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
