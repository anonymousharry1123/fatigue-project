import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _Repository extends MemoryCloudRepository {
  _Repository({required this.fullHistory}) : super(signedInUid: 'owner');
  final bool fullHistory;
  int returnedRows = 0;
  final filters = <bool>[];

  @override
  Future<List<SignalReading>> signalsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
    SignalType? type,
    bool includeHeartRate = true,
  }) async {
    filters.add(includeHeartRate);
    final result = await super.signalsByRange(
      uid,
      start: start,
      end: end,
      type: type,
      includeHeartRate: fullHistory || includeHeartRate,
    );
    returnedRows += result.length;
    return result;
  }
}

void main() {
  test(
    'dense heart history is not reread by scoring, forecasts and Coach',
    () async {
      final now = DateTime(2026, 10, 24, 12);
      final day = DateTime(2026, 10, 24);
      final inputs = [
        for (var i = 0; i < 2500; i++)
          SignalReading(
            id: 'heart-$i',
            type: SignalType.heartRate,
            value: 65,
            source: SignalSource.healthKit,
            timestamp: day.add(Duration(seconds: i)),
          ),
        for (final type in [
          SignalType.sleep,
          SignalType.study,
          SignalType.hrv,
          SignalType.restingHeartRate,
        ])
          SignalReading(id: type.name, type: type, value: 7, timestamp: day),
      ];
      Future<(_Repository, AppController)> load(bool fullHistory) async {
        SharedPreferences.setMockInitialValues({});
        final repo = _Repository(fullHistory: fullHistory)
          ..seed(
            'owner',
            CloudUserState(
              profile: const UserProfile(),
              accountEmail: 'owner@example.com',
              onboardingComplete: true,
              notificationsEnabled: false,
              notificationPrefsVersion: notificationPreferencesVersion,
              outcomeConsent: false,
              healthAuthorized: false,
              migrationVersion: localMigrationVersion,
              privacyConsent: testAdultPrivacyConsent,
              signals: inputs,
              checkIns: [
                DailyCheckIn(
                  id: 'check-in',
                  timestamp: day,
                  energy: 7,
                  mood: 6,
                  stress: 3,
                ),
              ],
            ),
          );
        final app = AppController(
          cloudRepository: repo,
          accountAuth: MemoryAccountAuth(
            session: const AccountSession(
              uid: 'owner',
              email: 'owner@example.com',
            ),
          ),
          initialPrivacyConsent: testAdultPrivacyConsent,
          clock: () => now,
        );
        addTearDown(app.dispose);
        await app.load();
        return (repo, app);
      }

      final (fullRepo, full) = await load(true);
      final (filteredRepo, filtered) = await load(false);
      expect(filteredRepo.filters.where((all) => !all), hasLength(5));
      expect(fullRepo.returnedRows - filteredRepo.returnedRows, 12500);
      expect(
        sameSyncValue(
          scoreSnapshotToCloud(snapshot: filtered.score, day: day),
          scoreSnapshotToCloud(snapshot: full.score, day: day),
        ),
        isTrue,
      );
      expect(
        filtered.forecastFor(day).map((point) => point.energy),
        full.forecastFor(day).map((point) => point.energy),
      );
      expect(
        sameSyncValue(
          filtered.recommendations.map(recommendationToCloud).toList(),
          full.recommendations.map(recommendationToCloud).toList(),
        ),
        isTrue,
      );
      // Insights still counts all raw records, and full sync/display is intact.
      expect(filtered.insightsSnapshot.sourceSignalCount, inputs.length);
      expect(
        filtered.insightsSnapshot.sourceSignalCount,
        full.insightsSnapshot.sourceSignalCount,
      );
      expect(filtered.signals.length, inputs.length);
      expect(filtered.latestHealthKitHeartRate?.id, 'heart-2499');
      expect(
        (await filteredRepo.readUser('owner'))!.signals.length,
        inputs.length,
      );
    },
  );
}
