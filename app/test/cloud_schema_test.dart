import 'package:app/src/cloud_schema.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Version 0.10-a Firestore schema', () {
    test('serializes and restores every SignalReading field', () {
      final signal = SignalReading(
        id: 'signal-1',
        type: SignalType.hydration,
        value: 2.4,
        timestamp: DateTime.utc(2026, 7, 28, 17),
        source: SignalSource.manual,
        quality: .9,
        note: 'After practice',
        groupId: 'activity-1',
      );

      final cloud = signalToCloud(signal);
      expect(cloud['unit'], 'L');
      expect(cloud['timestamp'], isA<DateTime>());
      expect(cloud, isNot(contains('id')));
      expect(cloud, isNot(contains('password')));

      final restored = signalFromCloud(signal.id, cloud);
      expect(restored.id, signal.id);
      expect(restored.type, signal.type);
      expect(restored.value, signal.value);
      expect(restored.timestamp, signal.timestamp);
      expect(restored.source, signal.source);
      expect(restored.quality, signal.quality);
      expect(restored.note, signal.note);
      expect(restored.groupId, signal.groupId);
    });

    test('rejects a stored unit that conflicts with the stable type', () {
      expect(
        () => signalFromCloud('bad', {
          'type': 'hydration',
          'value': 2,
          'unit': 'ml',
          'timestamp': DateTime.utc(2026, 7, 28),
        }),
        throwsFormatException,
      );
    });

    test('serializes and restores DailyCheckIn fields', () {
      final checkIn = DailyCheckIn(
        id: 'checkin-1',
        period: CheckInPeriod.evening,
        energy: 6,
        mood: 7,
        stress: 4,
        note: 'Recovered',
        timestamp: DateTime.utc(2026, 7, 28, 23),
      );

      final cloud = checkInToCloud(checkIn);
      final restored = checkInFromCloud(checkIn.id, cloud);

      expect(restored.id, checkIn.id);
      expect(restored.period, CheckInPeriod.evening);
      expect(restored.energy, 6);
      expect(restored.mood, 7);
      expect(restored.stress, 4);
      expect(restored.note, 'Recovered');
      expect(restored.timestamp, checkIn.timestamp);
    });

    test('profile metadata contains prefs and consent but no password', () {
      final cloud = profileToCloud(
        profile: const UserProfile(name: 'Jordan'),
        email: 'jordan@example.com',
        onboardingComplete: true,
        notificationsEnabled: false,
        outcomeConsent: true,
        healthAuthorized: false,
        updatedAt: DateTime.utc(2026, 7, 28),
      );

      expect((cloud['profile'] as Map)['name'], 'Jordan');
      expect((cloud['prefs'] as Map)['notificationsEnabled'], isFalse);
      expect(
        (cloud['prefs'] as Map)['notificationPreferencesVersion'],
        notificationPreferencesVersion,
      );
      expect((cloud['prefs'] as Map)['crashNotificationsEnabled'], isTrue);
      expect((cloud['prefs'] as Map)['recoveryNotificationsEnabled'], isTrue);
      expect((cloud['consentFlags'] as Map)['outcomeCollection'], isTrue);
      expect(cloud['localMigrationVersion'], localMigrationVersion);
      expect(cloud.toString().toLowerCase(), isNot(contains('password')));
      expect(cloud.toString().toLowerCase(), isNot(contains('medical')));
    });

    test('Version 0.14 score snapshots round-trip driver evidence', () {
      final day = DateTime.utc(2026, 7, 28);
      final calculatedAt = day.add(const Duration(hours: 15));
      final score = scoreSnapshotToCloud(
        snapshot: ScoreSnapshot(
          energy: 72,
          cognitive: 68,
          confidence: .8,
          drivers: [
            ScoreDriver(
              'Sleep',
              8,
              'Strong recovery',
              explanation: 'Recent sleep supported recovery.',
              freshness: .91,
              source: SignalSource.healthKit,
              evidenceAt: calculatedAt.subtract(const Duration(hours: 7)),
            ),
          ],
          day: day,
          calculatedAt: calculatedAt,
          inputCount: 6,
          cognitiveConfidence: .73,
          cognitiveInputCount: 4,
          cognitiveDrivers: const [
            ScoreDriver('Reaction time', 7, '255 ms vs 270 ms baseline'),
          ],
          previousCognitive: 63,
          freshness: .84,
          cognitiveFreshness: .79,
        ),
        day: day,
      );

      final restored = scoreSnapshotFromCloud(score);
      expect(
        score.keys,
        containsAll([
          'energy',
          'cognitive',
          'confidence',
          'cognitiveConfidence',
          'freshness',
          'cognitiveFreshness',
          'drivers',
          'cognitiveDrivers',
          'previousCognitive',
          'cognitiveDelta',
          'day',
        ]),
      );
      expect(restored.energy, 72);
      expect(restored.cognitive, 68);
      expect(restored.hasCognitiveScore, isTrue);
      expect(restored.cognitiveConfidence, .73);
      expect(restored.cognitiveInputCount, 4);
      expect(restored.cognitiveDrivers.single.label, 'Reaction time');
      expect(restored.previousCognitive, 63);
      expect(restored.cognitiveChange, 5);
      expect(restored.inputCount, 6);
      expect(restored.day, day);
      expect(restored.calculatedAt, calculatedAt);
      expect(restored.drivers.single.label, 'Sleep');
      expect(restored.freshness, .84);
      expect(restored.cognitiveFreshness, .79);
      expect(restored.drivers.single.explanation, contains('supported'));
      expect(restored.drivers.single.freshness, .91);
      expect(restored.drivers.single.source, SignalSource.healthKit);
      expect(
        restored.drivers.single.evidenceAt,
        calculatedAt.subtract(const Duration(hours: 7)),
      );
    });

    test('reads a Version 0.11 Energy-only snapshot without false history', () {
      final restored = scoreSnapshotFromCloud({
        'energy': 72,
        'confidence': .8,
        'inputCount': 6,
        'isEstimate': true,
        'drivers': const [],
        'day': DateTime.utc(2026, 7, 28),
      });

      expect(restored.energy, 72);
      expect(restored.cognitive, 0);
      expect(restored.hasCognitiveScore, isFalse);
      expect(restored.cognitiveChange, isNull);
    });

    test('derived collection serializers match roadmap field names', () {
      final forecastUpdatedAt = DateTime.utc(2026, 7, 28, 8, 30);
      final forecast = forecastPointToCloud(
        ForecastPoint(
          DateTime.utc(2026, 7, 28, 9),
          75,
          6,
          updatedAt: forecastUpdatedAt,
          signalEvidenceIds: const ['sleep-1', 'hydration-1'],
          checkInEvidenceIds: const ['check-in-1'],
        ),
      );
      final restoredForecast = forecastPointFromCloud(
        forecast.cast<String, dynamic>(),
      );
      final recommendation = recommendationToCloud(
        Recommendation(
          id: 'rec-1',
          title: 'Hydrate',
          detail: 'Drink water',
          timeLabel: '1:30 PM',
          category: 'Hydration',
          priority: RecommendationPriority.important,
          windowType: ForecastWindowType.crash,
          scheduledAt: DateTime.utc(2026, 7, 28, 13, 30),
          day: DateTime.utc(2026, 7, 28),
          generatedAt: forecastUpdatedAt,
          signalEvidenceIds: const ['hydration-1'],
          checkInEvidenceIds: const ['check-in-1'],
        ),
      );
      final alert = riskAlertToCloud(
        RiskAlert(
          'Sleep trend',
          'Short sleep',
          AlertSeverity.caution,
          id: 'alert-1',
          category: RiskAlertCategory.sleepDebt,
          day: DateTime.utc(2026, 7, 28),
          detectedAt: forecastUpdatedAt,
          signalEvidenceIds: const ['sleep-1'],
        ),
      );
      final restoredRecommendation = recommendationFromCloud(
        'rec-1',
        recommendation.cast<String, dynamic>(),
      );
      final restoredAlert = riskAlertFromCloud(
        'alert-1',
        alert.cast<String, dynamic>(),
      );

      expect(
        forecast.keys,
        containsAll([
          'time',
          'energy',
          'uncertainty',
          'updatedAt',
          'signalEvidenceIds',
          'checkInEvidenceIds',
        ]),
      );
      expect(restoredForecast.time, DateTime.utc(2026, 7, 28, 9));
      expect(restoredForecast.energy, 75);
      expect(restoredForecast.uncertainty, 6);
      expect(restoredForecast.updatedAt, forecastUpdatedAt);
      expect(restoredForecast.signalEvidenceIds, ['sleep-1', 'hydration-1']);
      expect(restoredForecast.checkInEvidenceIds, ['check-in-1']);
      expect(
        recommendation.keys,
        containsAll([
          'title',
          'detail',
          'status',
          'priority',
          'windowType',
          'scheduledAt',
          'day',
          'generatedAt',
          'signalEvidenceIds',
          'checkInEvidenceIds',
          'feedback',
        ]),
      );
      expect(restoredRecommendation.windowType, ForecastWindowType.crash);
      expect(restoredRecommendation.priority, RecommendationPriority.important);
      expect(restoredRecommendation.signalEvidenceIds, ['hydration-1']);
      expect(restoredRecommendation.checkInEvidenceIds, ['check-in-1']);
      expect(
        alert.keys,
        containsAll([
          'title',
          'severity',
          'category',
          'dismissed',
          'day',
          'detectedAt',
          'signalEvidenceIds',
          'checkInEvidenceIds',
        ]),
      );
      expect(restoredAlert.category, RiskAlertCategory.sleepDebt);
      expect(restoredAlert.signalEvidenceIds, ['sleep-1']);
      expect(restoredAlert.dismissed, isFalse);
    });

    test('rejects invalid persisted forecast values', () {
      expect(
        () => forecastPointFromCloud({
          'time': DateTime.utc(2026, 7, 28, 9),
          'energy': 101,
          'uncertainty': 6,
        }),
        throwsFormatException,
      );
    });

    test('reads legacy forecasts without evidence links', () {
      final restored = forecastPointFromCloud({
        'time': DateTime.utc(2026, 7, 28, 9),
        'energy': 75,
        'uncertainty': 6,
      });

      expect(restored.signalEvidenceIds, isEmpty);
      expect(restored.checkInEvidenceIds, isEmpty);
    });
  });
}
