import 'package:app/src/app_controller.dart';
import 'package:app/src/device_timezone_service.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/notification_service.dart';
import 'package:app/src/screen_time_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'privacy_test_support.dart';

class _Notifications implements NotificationService {
  int cancellations = 0;
  @override
  bool get supportsScheduling => false;
  @override
  Future<void> cancelGuidance() async {
    cancellations++;
  }

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
    DeviceTimezoneService timezone,
    _Notifications notifications,
    DateTime Function() now,
  ) : super(
        deviceTimezoneService: timezone,
        notificationService: notifications,
        clock: now,
        initialPrivacyConsent: testAdultPrivacyConsent,
      );
  final calls = <String>[];
  @override
  Future<HealthAuthorizationState> refreshHealthAuthorization({
    bool notify = true,
  }) async => HealthAuthorizationState.unavailable;
  @override
  Future<ScreenTimeAuthorizationState> refreshScreenTimeAuthorization({
    bool notify = true,
  }) async => ScreenTimeAuthorizationState.unavailable;
  @override
  Future<void> refreshScores({
    DateTime? day,
    bool notify = true,
    bool forceRecalculate = false,
  }) async {
    calls.add('score:$forceRecalculate');
  }

  @override
  Future<void> refreshForecasts({
    DateTime? day,
    bool notify = true,
    bool forceRecalculate = false,
  }) async {
    calls.add('forecast:$forceRecalculate');
  }

  @override
  Future<void> refreshGuidance({DateTime? day, bool notify = true}) async {
    calls.add('guidance');
  }

  @override
  Future<void> refreshInsights({DateTime? day, bool notify = true}) async {
    calls.add('insights');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'travel rebuilds derived views once, without training or repeated refresh',
    () async {
      var region = 'America/Los_Angeles';
      var now = DateTime(2026, 9, 19, 12);
      final service = DeviceTimezoneService(
        readIdentifier: () async => region,
        clock: () => now,
      );
      await service.refresh();
      final notifications = _Notifications();
      final controller = _Controller(service, notifications, () => now)
        ..onboardingComplete = true;
      addTearDown(controller.dispose);
      await controller.handleAppResumed();
      expect(controller.calls, isEmpty);
      region = 'Asia/Tokyo';
      await controller.handleAppResumed();
      expect(controller.deviceTimezoneIdentifier, 'Asia/Tokyo');
      expect(controller.calls, [
        'score:true',
        'forecast:true',
        'guidance',
        'insights',
      ]);
      expect(notifications.cancellations, 1);
      controller.calls.clear();
      await controller.handleAppResumed();
      expect(controller.calls, isEmpty);
      now = DateTime(2026, 9, 20, 12);
      await controller.handleAppResumed();
      expect(controller.calls, [
        'score:true',
        'forecast:true',
        'guidance',
        'insights',
      ]);
    },
  );

  test(
    'a signed-out device updates its region without rebuilding private views',
    () async {
      var region = 'America/Los_Angeles';
      final service = DeviceTimezoneService(readIdentifier: () async => region);
      await service.refresh();
      final controller = _Controller(service, _Notifications(), DateTime.now)
        ..isSignedOut = true
        ..onboardingComplete = true;
      addTearDown(controller.dispose);
      region = 'Europe/London';
      await controller.handleAppResumed();
      expect(controller.deviceTimezoneIdentifier, region);
      expect(controller.calls, isEmpty);
    },
  );
}
