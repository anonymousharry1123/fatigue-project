import 'package:firebase_core/firebase_core.dart';

import 'cloud_repository.dart';
import 'cloud_schema.dart';
import 'cloud_sync.dart';
import 'models.dart';
import 'privacy_consent.dart';

/// One circuit breaker covers every ordinary repository read and write.
/// It is owner-scoped, persists through the controller, and an explicit Retry
/// grants a fresh attempt. It never substitutes cached privacy evidence.
class CloudQuotaGate {
  CloudQuotaGate({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final Map<String, DateTime> _until = {};
  bool paused(String uid) => _until[uid]?.isAfter(_clock()) == true;
  DateTime? retryAt(String uid) => _until[uid];
  void retryNow(String uid) => _until.remove(uid);
  Map<String, String> toJson() => {
    for (final entry in _until.entries)
      if (entry.value.isAfter(_clock()))
        entry.key: entry.value.toUtc().toIso8601String(),
  };
  void restore(Object? value) {
    if (value is! Map) return;
    for (final entry in value.entries) {
      final date = DateTime.tryParse(entry.value.toString());
      if (entry.key is String && date != null && date.isAfter(_clock())) {
        _until[entry.key as String] = date;
      }
    }
  }

  Future<T> run<T>(String uid, Future<T> Function() operation) async {
    if (paused(uid)) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'resource-exhausted',
        message:
            'Cloud quota cooldown is active. Changes remain on this device.',
      );
    }
    try {
      return await operation();
    } on FirebaseException catch (error) {
      if (error.code.toLowerCase() == 'resource-exhausted') {
        _until[uid] = _clock().add(const Duration(hours: 1));
      }
      rethrow;
    }
  }
}

class QuotaCloudRepository implements CloudRepository {
  QuotaCloudRepository(this.inner, {CloudQuotaGate? gate})
    : gate = gate ?? CloudQuotaGate();
  final CloudRepository inner;
  final CloudQuotaGate gate;

  @override
  Future<CloudUserState?> readUser(String uid) =>
      gate.run(uid, () => inner.readUser(uid));

  @override
  Future<AccountPrivacySnapshot> readAccountPrivacy(String uid) =>
      gate.run(uid, () => inner.readAccountPrivacy(uid));

  @override
  Future<PrivacyConsent> savePrivacyConsent(
    String uid,
    PrivacyConsent receipt,
  ) => gate.run(uid, () => inner.savePrivacyConsent(uid, receipt));

  @override
  Future<DateTime> saveOutcomeConsent(String uid, bool enabled) =>
      gate.run(uid, () => inner.saveOutcomeConsent(uid, enabled));

  @override
  Future<void> replaceUser(String uid, CloudUserState state) =>
      gate.run(uid, () => inner.replaceUser(uid, state));

  @override
  Future<void> applyInputPatch(String uid, InputSyncPatch patch) =>
      gate.run(uid, () => inner.applyInputPatch(uid, patch));

  @override
  Future<List<SignalReading>> signalsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
    SignalType? type,
    bool includeHeartRate = true,
  }) => gate.run(
    uid,
    () => inner.signalsByRange(
      uid,
      start: start,
      end: end,
      type: type,
      includeHeartRate: includeHeartRate,
    ),
  );

  @override
  Future<List<DailyCheckIn>> checkInsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) => gate.run(uid, () => inner.checkInsByRange(uid, start: start, end: end));

  @override
  Future<DailyCheckIn?> latestCheckIn(String uid) =>
      gate.run(uid, () => inner.latestCheckIn(uid));

  @override
  Future<List<SignalReading>> reactionBaselineWindow(
    String uid, {
    int limit = 14,
  }) => gate.run(uid, () => inner.reactionBaselineWindow(uid, limit: limit));

  @override
  Future<void> upsertScoreSnapshot(String uid, ScoreSnapshot snapshot) =>
      gate.run(uid, () => inner.upsertScoreSnapshot(uid, snapshot));

  @override
  Future<ScoreSnapshot?> scoreSnapshotForDay(String uid, DateTime day) =>
      gate.run(uid, () => inner.scoreSnapshotForDay(uid, day));

  @override
  Future<void> clearScoreSnapshots(String uid) =>
      gate.run(uid, () => inner.clearScoreSnapshots(uid));

  @override
  Future<List<ForecastPoint>> forecastPointsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) => gate.run(
    uid,
    () => inner.forecastPointsByRange(uid, start: start, end: end),
  );

  @override
  Future<void> replaceForecastPoints(
    String uid, {
    required DateTime day,
    required List<ForecastPoint> points,
  }) => gate.run(
    uid,
    () => inner.replaceForecastPoints(uid, day: day, points: points),
  );

  @override
  Future<List<Recommendation>> recommendationsForDay(
    String uid,
    DateTime day,
  ) => gate.run(uid, () => inner.recommendationsForDay(uid, day));

  @override
  Future<List<Recommendation>> recommendationsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) => gate.run(
    uid,
    () => inner.recommendationsByRange(uid, start: start, end: end),
  );

  @override
  Future<void> replaceRecommendationsForDay(
    String uid, {
    required DateTime day,
    required List<Recommendation> recommendations,
  }) => gate.run(
    uid,
    () => inner.replaceRecommendationsForDay(
      uid,
      day: day,
      recommendations: recommendations,
    ),
  );

  @override
  Future<void> setRecommendationStatus(
    String uid,
    String recommendationId, {
    required RecommendationStatus status,
  }) => gate.run(
    uid,
    () => inner.setRecommendationStatus(uid, recommendationId, status: status),
  );

  @override
  Future<void> setRecommendationFeedback(
    String uid,
    String recommendationId, {
    required bool helpful,
  }) => gate.run(
    uid,
    () => inner.setRecommendationFeedback(
      uid,
      recommendationId,
      helpful: helpful,
    ),
  );

  @override
  Future<void> applyRecommendationAction(
    String uid,
    Recommendation record, {
    RecommendationStatus? status,
    bool? helpful,
  }) => gate.run(
    uid,
    () => inner.applyRecommendationAction(
      uid,
      record,
      status: status,
      helpful: helpful,
    ),
  );

  @override
  Future<void> applyRiskAlertDismissal(String uid, RiskAlert record) =>
      gate.run(uid, () => inner.applyRiskAlertDismissal(uid, record));

  @override
  Future<void> upsertOutcome(String uid, OutcomeRecord outcome) =>
      gate.run(uid, () => inner.upsertOutcome(uid, outcome));

  @override
  Future<List<OutcomeRecord>> outcomesByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) => gate.run(uid, () => inner.outcomesByRange(uid, start: start, end: end));

  @override
  Future<void> clearOutcomes(String uid) =>
      gate.run(uid, () => inner.clearOutcomes(uid));

  @override
  Future<void> deleteOutcome(String uid, String outcomeId) =>
      gate.run(uid, () => inner.deleteOutcome(uid, outcomeId));

  @override
  Future<List<RiskAlert>> riskAlertsForDay(String uid, DateTime day) =>
      gate.run(uid, () => inner.riskAlertsForDay(uid, day));

  @override
  Future<void> replaceRiskAlertsForDay(
    String uid, {
    required DateTime day,
    required List<RiskAlert> alerts,
  }) => gate.run(
    uid,
    () => inner.replaceRiskAlertsForDay(uid, day: day, alerts: alerts),
  );

  @override
  Future<void> setRiskAlertDismissed(
    String uid,
    String alertId, {
    required bool dismissed,
  }) => gate.run(
    uid,
    () => inner.setRiskAlertDismissed(uid, alertId, dismissed: dismissed),
  );

  @override
  Future<void> clearGuidance(String uid) =>
      gate.run(uid, () => inner.clearGuidance(uid));

  @override
  Future<Map<String, Object?>> exportUser(String uid) =>
      gate.run(uid, () => inner.exportUser(uid));

  @override
  Future<void> deleteUserTree(String uid) =>
      gate.run(uid, () => inner.deleteUserTree(uid));
}
