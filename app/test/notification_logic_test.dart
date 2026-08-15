import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/models.dart';
import 'package:app/src/notification_logic.dart';
import 'package:app/src/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 8, 15, 12);
  final day = DateTime(now.year, now.month, now.day);

  List<ForecastPoint> points({double uncertainty = 8, DateTime? updatedAt}) => [
    ForecastPoint(
      day.add(const Duration(hours: 9)),
      72,
      uncertainty,
      updatedAt: updatedAt ?? now.subtract(const Duration(minutes: 20)),
    ),
    ForecastPoint(
      day.add(const Duration(hours: 15)),
      42,
      uncertainty,
      updatedAt: updatedAt ?? now.subtract(const Duration(minutes: 20)),
    ),
    ForecastPoint(
      day.add(const Duration(hours: 18)),
      63,
      uncertainty,
      updatedAt: updatedAt ?? now.subtract(const Duration(minutes: 20)),
    ),
  ];

  List<ForecastWindow> windows({bool past = false}) {
    final offset = past ? -8 : 0;
    return [
      ForecastWindow(
        ForecastWindowType.crash,
        day.add(Duration(hours: 15 + offset)),
        day.add(Duration(hours: 16 + offset)),
        42,
        'Forecast energy change',
      ),
      ForecastWindow(
        ForecastWindowType.recovery,
        day.add(Duration(hours: 17 + offset)),
        day.add(Duration(hours: 19 + offset)),
        63,
        'Forecast recovery',
      ),
    ];
  }

  NotificationPlan build({
    List<ForecastPoint>? forecast,
    List<ForecastWindow>? forecastWindows,
    bool enabled = true,
    bool crashEnabled = true,
    bool recoveryEnabled = true,
  }) => NotificationLogic.build(
    now: now,
    points: forecast ?? points(),
    windows: forecastWindows ?? windows(),
    riskAlerts: [
      RiskAlert(
        'Private active title',
        'Private active detail',
        AlertSeverity.caution,
        id: 'active-risk',
      ),
      RiskAlert(
        'Private dismissed title',
        'Private dismissed detail',
        AlertSeverity.high,
        id: 'dismissed-risk',
        dismissed: true,
      ),
    ],
    enabled: enabled,
    crashEnabled: crashEnabled,
    recoveryEnabled: recoveryEnabled,
  );

  group('Version 0.20 notification planning', () {
    test('builds deterministic crash and recovery reminders', () {
      final first = build();
      final second = build();

      expect(first.state, NotificationPlanState.ready);
      expect(first.notifications, hasLength(2));
      expect(
        first.notifications.map((item) => item.id),
        second.notifications.map((item) => item.id),
      );
      expect(
        first.notifications.map((item) => item.platformId),
        second.notifications.map((item) => item.platformId),
      );
      expect(
        first.notifications.first.scheduledAt,
        day.add(const Duration(hours: 14, minutes: 45)),
      );
      expect(
        first.notifications.last.scheduledAt,
        day.add(const Duration(hours: 17)),
      );
      expect(first.dismissedRiskAlertCount, 1);
      for (final notification in first.notifications) {
        expect(notification.sourceRiskAlertIds, ['active-risk']);
        expect(notification.body, isNot(contains('Private')));
        expect(notification.body.toLowerCase(), isNot(contains('diagnos')));
        expect(notification.payload, startsWith('tonyo-guidance:'));
      }
    });

    test('suppresses stale forecasts', () {
      final plan = build(
        forecast: points(updatedAt: now.subtract(const Duration(hours: 13))),
      );

      expect(plan.state, NotificationPlanState.staleForecast);
      expect(plan.notifications, isEmpty);
    });

    test('suppresses low-confidence forecasts', () {
      final plan = build(forecast: points(uncertainty: 18));

      expect(plan.state, NotificationPlanState.lowConfidence);
      expect(plan.notifications, isEmpty);
    });

    test('suppresses past windows and honors category preferences', () {
      expect(
        build(forecastWindows: windows(past: true)).state,
        NotificationPlanState.noFutureWindows,
      );
      final recoveryOnly = build(crashEnabled: false);
      expect(recoveryOnly.notifications, hasLength(1));
      expect(
        recoveryOnly.notifications.single.kind,
        GuidanceNotificationKind.recovery,
      );
    });
  });

  group('Version 0.20 notification consent', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'requests permission only during explicit opt-in and persists it',
      () async {
        final service = _FakeNotificationService();
        final controller = AppController(notificationService: service);
        await controller.load();

        expect(controller.notificationsEnabled, isFalse);
        expect(service.permissionRequests, 0);

        final result = await controller.setNotifications(true);

        expect(result, NotificationPermissionState.granted);
        expect(controller.notificationsEnabled, isTrue);
        expect(service.permissionRequests, 1);
        expect(service.reconciliations, 1);
        final export =
            jsonDecode(controller.exportJson()) as Map<String, dynamic>;
        expect(export['notificationPreferencesVersion'], 1);
        expect(export['notificationsEnabled'], isTrue);

        final restored = AppController(notificationService: service);
        await restored.load();
        expect(restored.notificationsEnabled, isTrue);
        expect(service.permissionRequests, 1);

        await restored.setNotifications(false);
        expect(restored.notificationsEnabled, isFalse);
        expect(service.cancellations, greaterThan(0));
      },
    );

    test('does not treat the legacy default-on flag as consent', () async {
      SharedPreferences.setMockInitialValues({
        'tonyo_state_v1': jsonEncode({
          'onboardingComplete': false,
          'notificationsEnabled': true,
          'profile': const UserProfile().toJson(),
          'signals': const [],
          'checkIns': const [],
        }),
      });
      final service = _FakeNotificationService();
      final controller = AppController(notificationService: service);

      await controller.load();

      expect(controller.notificationsEnabled, isFalse);
      expect(service.permissionRequests, 0);
      expect(service.reconciliations, 0);
    });

    test('keeps alerts off when platform permission is denied', () async {
      final service = _FakeNotificationService(
        permission: NotificationPermissionState.denied,
      );
      final controller = AppController(notificationService: service);
      await controller.load();

      final result = await controller.setNotifications(true);

      expect(result, NotificationPermissionState.denied);
      expect(controller.notificationsEnabled, isFalse);
      expect(controller.notificationError, contains('blocked'));
      expect(service.reconciliations, 0);
    });
  });
}

class _FakeNotificationService implements NotificationService {
  _FakeNotificationService({
    this.permission = NotificationPermissionState.granted,
  });

  NotificationPermissionState permission;
  int permissionRequests = 0;
  int reconciliations = 0;
  int cancellations = 0;
  List<GuidanceNotification> scheduled = const [];

  @override
  bool get supportsScheduling => true;

  @override
  Future<NotificationPermissionState> permissionStatus() async => permission;

  @override
  Future<NotificationPermissionState> requestPermission() async {
    permissionRequests += 1;
    return permission;
  }

  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {
    reconciliations += 1;
    scheduled = List.unmodifiable(notifications);
  }

  @override
  Future<void> cancelGuidance() async {
    cancellations += 1;
    scheduled = const [];
  }
}
