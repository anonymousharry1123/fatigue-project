import 'dart:async';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/models.dart';
import 'package:app/src/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Use the plugin's test store to exercise an actual failed durable write.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'privacy_test_support.dart';

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore() : super.empty();
  @override
  Future<bool> setValue(String type, String key, Object value) async =>
      key == 'flutter.tonyo_state_v1'
      ? false
      : super.setValue(type, key, value);
}

class _Notifications implements NotificationService {
  NotificationPermissionState permission = NotificationPermissionState.granted;
  int permissionRequests = 0;
  int cancellations = 0;
  bool failSchedule = false;
  Completer<NotificationPermissionState>? permissionGate;
  Completer<void>? scheduleGate;
  Completer<void>? started;
  List<GuidanceNotification> scheduled = [];
  @override
  bool get supportsScheduling => true;
  @override
  Future<NotificationPermissionState> permissionStatus() async => permission;
  @override
  Future<NotificationPermissionState> requestPermission() async {
    permissionRequests++;
    return permissionGate?.future ?? permission;
  }

  @override
  Future<void> cancelGuidance() async {
    cancellations++;
    scheduled = [];
  }

  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {
    if (failSchedule) throw StateError('Platform scheduler failed');
    scheduled = List.of(notifications);
    final gate = scheduleGate;
    scheduleGate = null;
    started?.complete();
    started = null;
    if (gate != null) await gate.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var now = DateTime(2026, 9, 20, 6);
  late _Notifications service;

  AppController local() =>
      AppController(
          initialPrivacyConsent: testAdultPrivacyConsent,
          notificationService: service,
          clock: () => now,
        )
        ..checkIns = [
          DailyCheckIn(
            id: 'morning',
            timestamp: now,
            energy: 7,
            mood: 6,
            stress: 4,
          ),
        ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 9, 20, 6);
    service = _Notifications();
  });

  test(
    'one opt-in schedules actual plan blocks without changing status',
    () async {
      final controller = local();
      addTearDown(controller.dispose);
      await controller.refreshGuidance();
      expect(controller.recommendations, isNotEmpty);
      expect(service.permissionRequests, 0);
      expect(service.scheduled, isEmpty);
      await controller.setCoachPlanNotifications(true);
      expect(service.permissionRequests, 1);
      expect(controller.coachPlanNotificationsEnabled, isTrue);
      expect(controller.scheduledCoachNotificationCount, greaterThan(0));
      for (final reminder in service.scheduled.where(
        (item) => item.kind == GuidanceNotificationKind.coachPlan,
      )) {
        final block = controller.recommendations.singleWhere(
          (item) => item.id == reminder.sourceRecommendationId,
        );
        expect(reminder.scheduledAt, block.scheduledAt);
        expect(block.status, RecommendationStatus.suggested);
        expect(controller.notificationForRecommendation(block.id), reminder);
      }
      final saved = jsonDecode(controller.exportJson()) as Map;
      expect(saved['coachPlanNotificationsEnabled'], isTrue);
      final restarted = local();
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.coachPlanNotificationsEnabled, isTrue);
      expect(service.permissionRequests, 1);
    },
  );

  test(
    'new preference defaults off for existing forecast subscribers',
    () async {
      final first = local();
      addTearDown(first.dispose);
      await first.setNotifications(true);
      final json = jsonDecode(first.exportJson()) as Map<String, dynamic>;
      json.remove('coachPlanNotificationsEnabled');
      SharedPreferences.setMockInitialValues({
        'tonyo_state_v1': jsonEncode(json),
      });
      final restored = local();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.notificationsEnabled, isTrue);
      expect(restored.coachPlanNotificationsEnabled, isFalse);
      expect(restored.scheduledCoachNotificationCount, 0);
      expect(service.permissionRequests, 1);
    },
  );

  test(
    'disabled category replaces plan reminders and keeps forecast preference',
    () async {
      final app = local();
      addTearDown(app.dispose);
      await app.refreshGuidance();
      await app.setCoachPlanNotifications(true);
      await app.setCoachPlanNotifications(false);
      expect(app.notificationsEnabled, isTrue);
      expect(app.crashNotificationsEnabled, isTrue);
      expect(app.scheduledCoachNotificationCount, 0);
      expect(
        service.scheduled.where(
          (item) => item.kind == GuidanceNotificationKind.coachPlan,
        ),
        isEmpty,
      );
    },
  );

  test(
    'denied permission and scheduler failure never claim reminders scheduled',
    () async {
      final app = local();
      addTearDown(app.dispose);
      await app.refreshGuidance();
      service.permission = NotificationPermissionState.denied;
      await app.setCoachPlanNotifications(true);
      expect(app.notificationsEnabled, isFalse);
      expect(app.scheduledCoachNotificationCount, 0);
      expect(app.notificationError, contains('blocked'));
      service.permission = NotificationPermissionState.granted;
      service.failSchedule = true;
      await app.setCoachPlanNotifications(true);
      expect(app.notificationError, contains('unavailable'));
      expect(app.scheduledCoachNotificationCount, 0);
      expect(
        app.notificationForRecommendation(app.recommendations.first.id),
        isNull,
      );
    },
  );

  test('late permission approval cannot undo a newer off choice', () async {
    final app = local();
    addTearDown(app.dispose);
    final gate = Completer<NotificationPermissionState>();
    service.permissionGate = gate;
    final enable = app.setCoachPlanNotifications(true);
    await app.setNotifications(false);
    gate.complete(NotificationPermissionState.granted);
    await enable;
    expect(app.notificationsEnabled, isFalse);
    expect(service.scheduled, isEmpty);
    expect(app.isNotificationSyncing, isFalse);
    expect(jsonDecode(app.exportJson())['notificationsEnabled'], isFalse);
  });

  test('a failed device save does not schedule new reminders', () async {
    SharedPreferencesStorePlatform.instance = _FailingStore();
    final app = local();
    addTearDown(app.dispose);
    await app.refreshGuidance();
    await expectLater(app.setCoachPlanNotifications(true), throwsStateError);
    await app.refreshGuidance();
    expect(service.scheduled, isEmpty);
    expect(app.scheduledCoachNotificationCount, 0);
    expect(app.notificationError, contains('Could not save'));
    expect(app.isNotificationSyncing, isFalse);
  });

  test('superseded schedule completion cannot cancel the newer plan', () async {
    final app = local();
    addTearDown(app.dispose);
    await app.refreshGuidance();
    await app.setCoachPlanNotifications(true);
    final gate = Completer<void>();
    final started = Completer<void>();
    service.scheduleGate = gate;
    service.started = started;
    final old = app.refreshNotifications();
    await started.future;
    await app.setCoachPlanNotifications(false);
    final cancellations = service.cancellations;
    final latest = List.of(service.scheduled);
    gate.complete();
    await old;
    expect(service.cancellations, cancellations);
    expect(service.scheduled, latest);
    expect(app.isNotificationSyncing, isFalse);
  });

  test(
    'refresh and elapsed blocks do not report stale pending reminders',
    () async {
      final app = local();
      addTearDown(app.dispose);
      await app.refreshGuidance();
      await app.setCoachPlanNotifications(true);
      final first = service.scheduled.firstWhere(
        (item) => item.kind == GuidanceNotificationKind.coachPlan,
      );
      now = first.scheduledAt.add(const Duration(minutes: 1));
      expect(
        app.notificationForRecommendation(first.sourceRecommendationId!),
        isNull,
      );
      await app.refreshGuidance();
      expect(
        service.scheduled.every((item) => item.scheduledAt.isAfter(now)),
        isTrue,
      );
      await app.signOut();
      expect(service.scheduled, isEmpty);
      expect(app.scheduledCoachNotificationCount, 0);
    },
  );

  test(
    'daily reminder preference syncs independently and survives account reload',
    () async {
      final repo = MemoryCloudRepository(signedInUid: 'owner')
        ..seed(
          'owner',
          CloudUserState(
            profile: const UserProfile(),
            accountEmail: 'owner@example.com',
            onboardingComplete: false,
            notificationsEnabled: false,
            outcomeConsent: false,
            healthAuthorized: false,
            signals: const [],
            checkIns: const [],
            privacyConsent: testAdultPrivacyConsent,
            notificationPrefsVersion: notificationPreferencesVersion,
            migrationVersion: localMigrationVersion,
          ),
        );
      final auth = MemoryAccountAuth(
        session: const AccountSession(uid: 'owner', email: 'owner@example.com'),
      );
      AppController make() => AppController(
        notificationService: service,
        cloudRepository: repo,
        accountAuth: auth,
        clock: () => now,
      );
      final app = make();
      addTearDown(app.dispose);
      await app.load();
      await app.setCoachPlanNotifications(true);
      expect(
        (await repo.readUser('owner'))!.coachPlanNotificationsEnabled,
        isTrue,
      );
      SharedPreferences.setMockInitialValues({});
      final otherDevice = make();
      addTearDown(otherDevice.dispose);
      await otherDevice.load();
      expect(otherDevice.coachPlanNotificationsEnabled, isTrue);
      expect(service.permissionRequests, 1);
      await otherDevice.setCoachPlanNotifications(false);
      expect(
        (await repo.readUser('owner'))!.coachPlanNotificationsEnabled,
        isFalse,
      );
    },
  );
}
