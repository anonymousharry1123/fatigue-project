import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'check_in_logic.dart';
import 'demo_data.dart';
import 'fatigue_engine.dart';
import 'health_service.dart';
import 'models.dart';
import 'reaction_test_logic.dart';

class AppController extends ChangeNotifier {
  AppController({HealthService? healthService})
    : _healthService = healthService ?? const HealthService();

  static const _storageKey = 'tonyo_state_v1';
  final HealthService _healthService;

  bool isReady = false;
  bool onboardingComplete = false;
  bool notificationsEnabled = true;
  bool outcomeConsent = false;
  bool healthAvailable = false;
  bool healthAuthorized = false;
  bool isSyncing = false;
  DateTime? lastSync;
  UserProfile profile = const UserProfile();
  List<SignalReading> signals = [];
  List<DailyCheckIn> checkIns = [];
  final Map<String, RecommendationStatus> _recommendationStatuses = {};

  ScoreSnapshot get score =>
      FatigueEngine.score(signals: signals, checkIns: checkIns);
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

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        onboardingComplete = json['onboardingComplete'] as bool? ?? false;
        notificationsEnabled = json['notificationsEnabled'] as bool? ?? true;
        outcomeConsent = json['outcomeConsent'] as bool? ?? false;
        healthAuthorized = json['healthAuthorized'] as bool? ?? false;
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
          _recommendationStatuses[entry.key] = RecommendationStatus.values
              .byName(entry.value as String);
        }
      } on Object {
        onboardingComplete = false;
        signals = [];
        checkIns = [];
      }
    }
    healthAvailable = await _healthService.isAvailable();
    isReady = true;
    notifyListeners();
  }

  Future<void> completeOnboarding(UserProfile newProfile) async {
    profile = newProfile;
    onboardingComplete = true;
    if (signals.isEmpty) {
      signals = buildDemoSignals(DateTime.now());
      checkIns = buildDemoCheckIns(DateTime.now());
    }
    await _commit();
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
    await _commit();
  }

  Future<void> addSleep({
    required DateTime bedtime,
    required DateTime wakeTime,
    required double quality,
  }) async {
    var end = wakeTime;
    if (!end.isAfter(bedtime)) end = end.add(const Duration(days: 1));
    final hours = end.difference(bedtime).inMinutes / 60;
    signals.insertAll(0, [
      SignalReading(
        id: 'manual-sleep-${DateTime.now().microsecondsSinceEpoch}',
        type: SignalType.sleep,
        value: hours,
        timestamp: wakeTime,
        quality: quality / 5,
        note:
            '${_clock(bedtime)}–${_clock(end)} · quality ${quality.round()}/5',
      ),
      SignalReading(
        id: 'manual-bed-${DateTime.now().microsecondsSinceEpoch}',
        type: SignalType.bedtime,
        value: bedtime.hour + bedtime.minute / 60,
        timestamp: bedtime,
      ),
    ]);
    await _commit();
  }

  Future<void> addCheckIn({
    required double energy,
    required double mood,
    required double stress,
    CheckInPeriod? period,
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
    checkIns.insert(
      0,
      DailyCheckIn(
        id: 'checkin-${when.microsecondsSinceEpoch}',
        timestamp: when,
        energy: CheckInLogic.clampRating(energy),
        mood: CheckInLogic.clampRating(mood),
        stress: CheckInLogic.clampRating(stress),
        period: period ?? CheckInLogic.suggestedPeriod(when),
        note: note,
      ),
    );
    await _commit();
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
    await _commit();
  }

  Future<void> deleteCheckIn(String id) async {
    checkIns.removeWhere((item) => item.id == id);
    await _commit();
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
    await _commit();
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert(_json());

  Future<void> reset() async {
    onboardingComplete = false;
    notificationsEnabled = true;
    outcomeConsent = false;
    healthAuthorized = false;
    lastSync = null;
    profile = const UserProfile();
    signals = [];
    checkIns = [];
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
    'lastSync': lastSync?.toIso8601String(),
    'profile': profile.toJson(),
    'signals': signals.map((item) => item.toJson()).toList(),
    'checkIns': checkIns.map((item) => item.toJson()).toList(),
    'recommendationStatuses': _recommendationStatuses.map(
      (key, value) => MapEntry(key, value.name),
    ),
  };

  Future<void> _commit() async {
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(_json()));
  }

  static String _clock(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$hour:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
  }
}
