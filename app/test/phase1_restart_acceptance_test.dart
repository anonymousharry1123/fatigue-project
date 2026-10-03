import 'package:app/src/activity_sync_logic.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/models.dart';
import 'package:app/src/notification_service.dart';
import 'package:app/src/schedule_logic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

// These tests recreate the controller over the plugin's synthetic store. They
// establish serialization/lifecycle behavior, not physical restart or delivery.
class _Notifications implements NotificationService {
  int cancellations = 0;
  List<GuidanceNotification> scheduled = [];

  @override
  bool get supportsScheduling => true;

  @override
  Future<void> cancelGuidance() async {
    cancellations++;
    scheduled = [];
  }

  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {
    scheduled = List.of(notifications);
  }

  @override
  Future<NotificationPermissionState> permissionStatus() async =>
      NotificationPermissionState.granted;

  @override
  Future<NotificationPermissionState> requestPermission() async =>
      NotificationPermissionState.granted;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late _Notifications notifications;

  AppController create() {
    final app = AppController(
      initialPrivacyConsent: testAdultPrivacyConsent,
      notificationService: notifications,
      clock: () => now,
    );
    addTearDown(app.dispose);
    return app;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 10, 3, 6);
    notifications = _Notifications();
  });

  test(
    'exercise zero survives recreation; deleting override restores import',
    () async {
      final first = create()
        ..signals = [
          SignalReading(
            id: 'synthetic-import',
            type: SignalType.exercise,
            value: 1.5,
            timestamp: now,
            source: SignalSource.healthKit,
          ),
        ];
      await first.saveActivityLog(
        id: 'activity-manual-zero',
        exerciseHours: 0,
        timestamp: now,
      );

      final restarted = create();
      await restarted.load();
      expect(restarted.activityLogs.single.exerciseHours, 0);
      expect(restarted.activityLogs.single.studyHours, isNull);
      final zero = ActivitySyncLogic.aggregateForDay(
        restarted.signals,
        type: SignalType.exercise,
        day: now,
      )!;
      expect(zero.total, 0);
      expect(zero.usesManualCorrection, isTrue);
      expect(
        restarted.signals
            .singleWhere((item) => item.id == 'synthetic-import')
            .value,
        1.5,
      );

      await restarted.deleteActivityLog('activity-manual-zero');
      final afterClear = create();
      await afterClear.load();
      expect(afterClear.activityLogs, isEmpty);
      final imported = ActivitySyncLogic.aggregateForDay(
        afterClear.signals,
        type: SignalType.exercise,
        day: now,
      )!;
      expect(imported.total, 1.5);
      expect(imported.usesManualCorrection, isFalse);
    },
  );

  test(
    'edited overnight schedule persists and regenerated blocks protect sleep',
    () async {
      final first = create()
        ..onboardingComplete = true
        ..checkIns = [
          DailyCheckIn(
            id: 'synthetic-check',
            timestamp: now,
            energy: 6,
            mood: 6,
            stress: 4,
          ),
        ];
      await first.updateProfile(
        first.profile.copyWith(wakeHour: 9.5, bedHour: 1.5),
      );
      await first.setCoachPlanNotifications(true);
      expect(notifications.scheduled, isNotEmpty);

      final restarted = create();
      await restarted.load();
      expect(restarted.profile.wakeHour, 9.5);
      expect(restarted.profile.bedHour, 1.5);
      expect(restarted.coachPlanNotificationsEnabled, isTrue);
      final window = ScheduleLogic.wakingWindow(now, restarted.profile)!;
      expect(window.wake, DateTime(2026, 10, 3, 9, 30));
      expect(window.bed, DateTime(2026, 10, 4, 1, 30));
      final blocks = restarted.recommendations.toList()
        ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
      expect(blocks, isNotEmpty);
      DateTime? priorEnd;
      for (final block in blocks) {
        final start = block.scheduledAt!;
        final end = start.add(Duration(minutes: block.durationMinutes!));
        expect(start.isBefore(window.wake), isFalse);
        expect(end.isAfter(window.bed), isFalse);
        if (priorEnd != null) expect(start.isBefore(priorEnd), isFalse);
        priorEnd = end;
      }
      expect(notifications.scheduled, isNotEmpty);
      for (final reminder in notifications.scheduled) {
        expect(reminder.kind, GuidanceNotificationKind.coachPlan);
        expect(
          blocks.any((item) => item.id == reminder.sourceRecommendationId),
          isTrue,
        );
        expect(reminder.scheduledAt.isBefore(window.wake), isFalse);
        expect(reminder.scheduledAt.isAfter(window.bed), isFalse);
      }
    },
  );

  test(
    'stale observations remain recorded after restart but cannot schedule or score',
    () async {
      final first = create()
        ..onboardingComplete = true
        ..checkIns = [
          DailyCheckIn(
            id: 'synthetic-check',
            timestamp: now,
            energy: 8,
            mood: 8,
            stress: 2,
          ),
        ];
      await first.updateProfile(first.profile);
      await first.setCoachPlanNotifications(true);
      expect(first.score.canEstimateEnergy, isTrue);
      expect(notifications.scheduled, isNotEmpty);

      now = DateTime(2026, 10, 4, 6);
      final restarted = create();
      await restarted.load();
      expect(restarted.checkIns.single.timestamp, DateTime(2026, 10, 3, 6));
      expect(restarted.score.canEstimateEnergy, isFalse);
      expect(restarted.score.canEstimateCognitive, isFalse);
      expect(restarted.forecastFor(now), isEmpty);
      expect(restarted.recommendations, isEmpty);
      expect(notifications.scheduled, isEmpty);
      expect(restarted.scheduledNotificationCount, 0);
      await restarted.handleAppResumed();
      expect(notifications.scheduled, isEmpty);
    },
  );

  test(
    'disabled notifications stay canceled after recreation and resume',
    () async {
      final first = create()
        ..onboardingComplete = true
        ..checkIns = [
          DailyCheckIn(
            id: 'synthetic-check',
            timestamp: now,
            energy: 6,
            mood: 6,
            stress: 4,
          ),
        ];
      await first.updateProfile(first.profile);
      await first.setCoachPlanNotifications(true);
      expect(notifications.scheduled, isNotEmpty);
      await first.setNotifications(false);
      expect(notifications.scheduled, isEmpty);

      final restarted = create();
      await restarted.load();
      expect(restarted.notificationsEnabled, isFalse);
      expect(restarted.checkIns, hasLength(1));
      expect(notifications.scheduled, isEmpty);
      await restarted.handleAppResumed();
      expect(notifications.scheduled, isEmpty);
      expect(restarted.scheduledNotificationCount, 0);
    },
  );
}
