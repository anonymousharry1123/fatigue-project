import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/device_timezone_service.dart';
import 'package:app/src/energy_model_repository.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/models.dart';
import 'package:app/src/notification_service.dart';
import 'package:app/src/screen_time_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _Repository extends MemoryCloudRepository {
  _Repository() : super(signedInUid: 'nap-user');
  int signalQueries = 0;

  @override
  Future<List<SignalReading>> signalsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
    SignalType? type,
  }) {
    signalQueries++;
    return super.signalsByRange(uid, start: start, end: end, type: type);
  }
}

class _Notifications implements NotificationService {
  @override
  bool get supportsScheduling => false;
  @override
  Future<void> cancelGuidance() async {}
  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {}
  @override
  Future<NotificationPermissionState> permissionStatus() async =>
      NotificationPermissionState.unavailable;
  @override
  Future<NotificationPermissionState> requestPermission() async =>
      NotificationPermissionState.unavailable;
}

class _Controller extends AppController {
  _Controller(
    _Repository repository,
    DateTime Function() clock,
    MemoryEnergyModelMetadataWriter writer,
  ) : super(
        cloudRepository: repository,
        accountAuth: MemoryAccountAuth(
          session: const AccountSession(
            uid: 'nap-user',
            email: 'nap@example.com',
          ),
        ),
        clock: clock,
        initialPrivacyConsent: testAdultPrivacyConsent,
        energyModelStore: MemoryEnergyModelStore(),
        energyModelMetadataWriter: writer,
        notificationService: _Notifications(),
        deviceTimezoneService: DeviceTimezoneService(
          readIdentifier: () async => null,
          clock: clock,
        ),
      );

  int guidanceRefreshes = 0;
  int insightsRefreshes = 0;
  @override
  Future<HealthAuthorizationState> refreshHealthAuthorization({
    bool notify = true,
  }) async => HealthAuthorizationState.unavailable;
  @override
  Future<ScreenTimeAuthorizationState> refreshScreenTimeAuthorization({
    bool notify = true,
  }) async => ScreenTimeAuthorizationState.unavailable;
  @override
  Future<void> refreshGuidance({DateTime? day, bool notify = true}) async {
    guidanceRefreshes++;
    await super.refreshGuidance(day: day, notify: notify);
  }

  @override
  Future<void> refreshInsights({DateTime? day, bool notify = true}) async {
    insightsRefreshes++;
    await super.refreshInsights(day: day, notify: notify);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final napEnd = DateTime(2026, 9, 19, 14, 30);

  _Repository repository() => _Repository()
    ..seed(
      'nap-user',
      CloudUserState(
        privacyConsent: testAdultPrivacyConsent,
        profile: const UserProfile(name: 'Nap test'),
        accountEmail: 'nap@example.com',
        onboardingComplete: true,
        notificationsEnabled: false,
        outcomeConsent: false,
        healthAuthorized: false,
        migrationVersion: localMigrationVersion,
        signals: [
          SignalReading(
            id: 'main-sleep',
            type: SignalType.sleep,
            value: 8,
            timestamp: DateTime(2026, 9, 19, 7),
          ),
          SignalReading(
            id: 'nap',
            type: SignalType.nap,
            value: .5,
            timestamp: napEnd,
          ),
        ],
        checkIns: const [],
      ),
    );

  double napCredit(AppController controller) => controller.score.drivers
      .singleWhere((driver) => driver.label == 'Nap recovery')
      .contribution;

  test(
    'resume updates nap recovery and all derived views only after time passes',
    () async {
      var now = napEnd;
      final source = repository();
      final writer = MemoryEnergyModelMetadataWriter();
      final controller = _Controller(source, () => now, writer);
      addTearDown(controller.dispose);
      await controller.load();
      final baseEnergy = controller.score.energy;
      final initialQueries = source.signalQueries;
      final initialWrites = source.scoreUpsertCallCount;
      final initialForecastWrites = source.forecastReplaceCallCount;
      final initialGuidance = controller.guidanceRefreshes;
      final initialInsights = controller.insightsRefreshes;
      expect(napCredit(controller), 0);

      await controller.handleAppResumed();
      expect(source.signalQueries, initialQueries);
      expect(source.scoreUpsertCallCount, initialWrites);
      expect(source.forecastReplaceCallCount, initialForecastWrites);
      expect(controller.guidanceRefreshes, initialGuidance);
      expect(controller.insightsRefreshes, initialInsights);

      now = napEnd.add(const Duration(hours: 1));
      await controller.handleAppResumed();
      expect(napCredit(controller), 3);
      expect(controller.score.energy, baseEnergy + 3);
      expect(source.scoreUpsertCallCount, initialWrites + 1);
      expect(
        source.forecastReplaceCallCount,
        greaterThan(initialForecastWrites),
      );
      expect(controller.guidanceRefreshes, initialGuidance + 1);
      expect(controller.insightsRefreshes, initialInsights + 1);
      expect(
        controller
            .forecastDataFor(now)
            .every((point) => point.updatedAt == now),
        isTrue,
      );
      final refreshedQueries = source.signalQueries;
      now = now.add(const Duration(seconds: 59));
      await controller.handleAppResumed();
      expect(source.signalQueries, refreshedQueries);

      now = napEnd.add(const Duration(hours: 6));
      await controller.handleAppResumed();
      expect(napCredit(controller), 0);
      expect(controller.score.energy, baseEnergy);
      expect(controller.guidanceRefreshes, initialGuidance + 2);
      expect(controller.insightsRefreshes, initialInsights + 2);
      expect(
        controller
            .forecastDataFor(now)
            .every((point) => point.updatedAt == now),
        isTrue,
      );
      expect(writer.writes, 0);
      expect(controller.isRefreshingPersonalizedModel, isFalse);

      final expiredQueries = source.signalQueries;
      final expiredWrites = source.scoreUpsertCallCount;
      now = napEnd.add(const Duration(hours: 7));
      await controller.handleAppResumed();
      expect(source.signalQueries, expiredQueries);
      expect(source.scoreUpsertCallCount, expiredWrites);
      expect(controller.guidanceRefreshes, initialGuidance + 2);
      expect(controller.insightsRefreshes, initialInsights + 2);

      await controller.signOut();
      final signedOutQueries = source.signalQueries;
      now = now.add(const Duration(hours: 1));
      await controller.handleAppResumed();
      expect(source.signalQueries, signedOutQueries);
    },
  );

  test(
    'active nap snapshots refresh with time and expired zero snapshots are reusable',
    () async {
      var now = napEnd;
      final source = repository();
      final writer = MemoryEnergyModelMetadataWriter();
      final controller = _Controller(source, () => now, writer);
      addTearDown(controller.dispose);
      await controller.load();
      expect(napCredit(controller), 0);
      final firstWrites = source.scoreUpsertCallCount;

      // UTC and local encodings of an instant are the same cache timestamp.
      now = napEnd.toUtc();
      await controller.refreshScores();
      expect(controller.scoreLoadedFromSnapshot, isTrue);
      expect(source.scoreUpsertCallCount, firstWrites);

      now = napEnd.add(const Duration(hours: 1));
      await controller.refreshScores();
      expect(controller.scoreLoadedFromSnapshot, isFalse);
      expect(napCredit(controller), 3);
      expect(source.scoreUpsertCallCount, firstWrites + 1);

      now = napEnd.add(const Duration(hours: 6));
      await controller.refreshScores();
      expect(controller.scoreLoadedFromSnapshot, isFalse);
      expect(napCredit(controller), 0);
      expect(source.scoreUpsertCallCount, firstWrites + 2);
      final saved = await source.scoreSnapshotForDay('nap-user', now);
      expect(saved?.calculatedAt?.isAtSameMomentAs(now), isTrue);
      expect(saved?.energy, controller.score.energy);
      now = napEnd.add(const Duration(hours: 7));
      await controller.refreshScores();
      expect(controller.scoreLoadedFromSnapshot, isTrue);
      expect(source.scoreUpsertCallCount, firstWrites + 2);
      expect(writer.writes, 0);
    },
  );
}
