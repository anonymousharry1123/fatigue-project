import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Version 0.21 loads owner-scoped cloud ranges and refreshes on input',
    () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final signals = <SignalReading>[
        for (var index = 0; index < 7; index++) ...[
          // Midnight keeps today's fixtures before the real test clock.
          SignalReading(
            id: 'sleep-$index',
            type: SignalType.sleep,
            value: 7 + index * .1,
            timestamp: today.subtract(Duration(days: 6 - index)),
          ),
          SignalReading(
            id: 'study-$index',
            type: SignalType.study,
            value: 1,
            timestamp: today.subtract(Duration(days: 6 - index)),
          ),
          SignalReading(
            id: 'exercise-$index',
            type: SignalType.exercise,
            value: .5,
            timestamp: today.subtract(Duration(days: 6 - index)),
          ),
        ],
      ];
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'insights-uid',
          email: 'insights@example.com',
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'insights-uid')
        ..seed(
          'insights-uid',
          CloudUserState(
            profile: const UserProfile(name: 'Insight Maya'),
            accountEmail: 'insights@example.com',
            onboardingComplete: true,
            notificationsEnabled: false,
            notificationPrefsVersion: notificationPreferencesVersion,
            outcomeConsent: false,
            healthAuthorized: false,
            migrationVersion: localMigrationVersion,
            signals: signals,
            checkIns: const [],
          ),
        );
      final controller = AppController(
        accountAuth: auth,
        cloudRepository: repository,
      );

      await controller.load();

      expect(controller.insightsLoadedFromCloud, isTrue);
      expect(controller.insightsError, isNull);
      expect(controller.insightsSnapshot.sourceSignalCount, 21);
      expect(controller.insightsSnapshot.currentSummary.trackedDayCount, 7);
      expect(controller.insightsSnapshot.currentSummary.studyHours, 7);

      await controller.addSignal(SignalType.study, 1.5);

      expect(controller.insightsLoadedFromCloud, isTrue);
      expect(controller.insightsSnapshot.sourceSignalCount, 22);
      expect(controller.insightsSnapshot.currentSummary.studyHours, 8.5);
      final cloud = await repository.readUser('insights-uid');
      expect(
        cloud!.signals.where((item) => item.type == SignalType.study).length,
        8,
      );
    },
  );
}
