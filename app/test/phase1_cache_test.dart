import 'package:app/src/app_controller.dart';
import 'package:app/src/models.dart';
import 'package:app/src/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _Notifications implements NotificationService {
  int cancellations = 0;
  @override
  bool get supportsScheduling => true;
  @override
  Future<void> cancelGuidance() async {
    cancellations++;
  }

  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {}
  @override
  Future<NotificationPermissionState> permissionStatus() async =>
      NotificationPermissionState.granted;
  @override
  Future<NotificationPermissionState> requestPermission() async =>
      NotificationPermissionState.granted;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final now = DateTime(2026, 10, 3, 10);
  DailyCheckIn check(double mood) => DailyCheckIn(
    id: 'current-check',
    timestamp: now,
    energy: 6,
    mood: mood,
    stress: 4,
  );
  AppController controller() => AppController(
    initialPrivacyConsent: testAdultPrivacyConsent,
    clock: () => now,
  )..checkIns = [check(3)];

  test(
    'changed evidence with same availability cannot reuse a cached score',
    () async {
      final app = controller();
      addTearDown(app.dispose);
      await app.refreshScores();
      final before = app.score.energy;
      app.checkIns = [check(9)];
      expect(app.score.canEstimateEnergy, isTrue);
      expect(app.score.energy, greaterThan(before));
      expect(
        app.score.drivers
            .singleWhere((driver) => driver.label == 'Mood')
            .detail,
        contains('9'),
      );
    },
  );

  test(
    'loss of linked evidence invalidates curve even with another scored input',
    () async {
      final app = controller()
        ..signals = [
          SignalReading(
            id: 'study',
            type: SignalType.study,
            value: 2,
            timestamp: now,
          ),
        ];
      addTearDown(app.dispose);
      await app.refreshScores();
      await app.refreshForecasts();
      expect(
        app.forecastFor(now).first.checkInEvidenceIds,
        contains('current-check'),
      );
      app.checkIns.clear();
      expect(app.score.canEstimateEnergy, isTrue);
      expect(app.forecastFor(now), isNotEmpty);
      expect(
        app.forecastFor(now).every((point) => point.checkInEvidenceIds.isEmpty),
        isTrue,
      );
    },
  );

  test(
    'day rollover immediately hides old scores and curves before refresh',
    () async {
      var clock = now;
      final app = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        clock: () => clock,
      )..checkIns = [check(8)];
      addTearDown(app.dispose);
      await app.refreshScores();
      await app.refreshForecasts();
      expect(app.score.canEstimateEnergy, isTrue);
      clock = DateTime(2026, 10, 4, 1);
      expect(app.score.canEstimateEnergy, isFalse);
      expect(app.score.canEstimateCognitive, isFalse);
      expect(app.forecastFor(clock), isEmpty);
    },
  );

  test(
    'launch cancels obsolete native schedules even behind sign-out gate',
    () async {
      SharedPreferences.setMockInitialValues({'tonyo_signed_out_v1': true});
      final notifications = _Notifications();
      final app = AppController(
        notificationService: notifications,
        clock: () => now,
      );
      addTearDown(app.dispose);
      await app.load();
      expect(app.isSignedOut, isTrue);
      expect(app.privacyConsent, isNull);
      expect(notifications.cancellations, 1);
      expect(app.scheduledNotificationCount, 0);
    },
  );
}
