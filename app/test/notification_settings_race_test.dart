import 'dart:async';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/models.dart';
import 'package:app/src/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _Notifications implements NotificationService {
  final statusGates = <Completer<NotificationPermissionState>>[];
  final statusStarted = <Completer<void>>[];
  Completer<NotificationPermissionState>? requestGate;
  Completer<void>? requestStarted;
  List<GuidanceNotification> scheduled = [];

  @override
  bool get supportsScheduling => true;
  @override
  Future<NotificationPermissionState> permissionStatus() async {
    if (statusGates.isEmpty) return NotificationPermissionState.granted;
    final gate = statusGates.removeAt(0);
    statusStarted.removeAt(0).complete();
    return gate.future;
  }

  @override
  Future<NotificationPermissionState> requestPermission() async {
    requestStarted?.complete();
    requestStarted = null;
    return requestGate?.future ?? NotificationPermissionState.granted;
  }

  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {
    scheduled = List.of(notifications);
  }

  @override
  Future<void> cancelGuidance() async {
    scheduled = [];
  }
}

class _FailedSignOut extends MemoryAccountAuth {
  _FailedSignOut() : super(configured: false);
  @override
  Future<void> signOut() async => throw StateError('Sign-out unavailable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 20, 6);
  final morning = DailyCheckIn(
    id: 'morning',
    timestamp: now,
    energy: 7,
    mood: 6,
    stress: 4,
  );
  late _Notifications notifications;

  AppController local({AccountAuth? auth}) => AppController(
    notificationService: notifications,
    accountAuth: auth,
    initialPrivacyConsent: testAdultPrivacyConsent,
    clock: () => now,
  )..checkIns = [morning];

  CloudUserState cloudState({bool onboardingComplete = true}) => CloudUserState(
    profile: const UserProfile(),
    accountEmail: 'owner@example.com',
    onboardingComplete: onboardingComplete,
    notificationsEnabled: false,
    coachPlanNotificationsEnabled: false,
    outcomeConsent: false,
    healthAuthorized: false,
    signals: const [],
    checkIns: [morning],
    privacyConsent: testAdultPrivacyConsent,
    notificationPrefsVersion: notificationPreferencesVersion,
    migrationVersion: localMigrationVersion,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifications = _Notifications();
  });

  test(
    'a completed preference toggle cannot confirm a newer pending plan',
    () async {
      final app = local();
      addTearDown(app.dispose);
      await app.refreshGuidance();
      await app.setCoachPlanNotifications(true);
      final oldNativePlan = List.of(notifications.scheduled);
      final olderGate = Completer<NotificationPermissionState>();
      final newerGate = Completer<NotificationPermissionState>();
      final olderStarted = Completer<void>();
      final newerStarted = Completer<void>();
      notifications.statusGates.addAll([olderGate, newerGate]);
      notifications.statusStarted.addAll([olderStarted, newerStarted]);

      final toggle = app.setCrashNotifications(false);
      await olderStarted.future;
      app.profile = app.profile.copyWith(wakeHour: 9);
      final refresh = app.refreshGuidance();
      await newerStarted.future;
      olderGate.complete(NotificationPermissionState.granted);
      await toggle;
      expect(notifications.scheduled, oldNativePlan);
      expect(app.scheduledCoachNotificationCount, 0);
      expect(app.isNotificationSyncing, isTrue);
      expect(app.nextScheduledNotification, isNull);
      expect(
        app.notificationForRecommendation(app.recommendations.first.id),
        isNull,
      );

      newerGate.complete(NotificationPermissionState.granted);
      await refresh;
      expect(app.isNotificationSyncing, isFalse);
      expect(app.scheduledCoachNotificationCount, greaterThan(0));
      expect(notifications.scheduled, isNot(oldNativePlan));
    },
  );

  test(
    'applying cloud master-off invalidates an older permission approval',
    () async {
      final repository = MemoryCloudRepository(signedInUid: 'owner')
        ..seed('owner', cloudState());
      final auth = MemoryAccountAuth(
        session: const AccountSession(uid: 'owner', email: 'owner@example.com'),
      );
      final app = AppController(
        notificationService: notifications,
        cloudRepository: repository,
        accountAuth: auth,
        clock: () => now,
      );
      addTearDown(app.dispose);
      await app.load();
      final gate = notifications.requestGate =
          Completer<NotificationPermissionState>();
      final started = notifications.requestStarted = Completer<void>();
      final enable = app.setCoachPlanNotifications(true);
      await started.future;
      await app.useCloudInputs();
      gate.complete(NotificationPermissionState.granted);
      await enable;

      expect(app.notificationsEnabled, isFalse);
      expect(app.coachPlanNotificationsEnabled, isFalse);
      expect(app.isNotificationSyncing, isFalse);
      expect(app.scheduledNotificationCount, 0);
      expect(notifications.scheduled, isEmpty);
      final persisted =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'tonyo_state_v1',
                )!,
              )
              as Map;
      expect(persisted['notificationsEnabled'], isFalse);
      expect(persisted['coachPlanNotificationsEnabled'], isFalse);
      expect(
        (await repository.readUser('owner'))!.notificationsEnabled,
        isFalse,
      );
      expect(
        (await repository.readUser('owner'))!.coachPlanNotificationsEnabled,
        isFalse,
      );
    },
  );

  test(
    'failed sign-out never reports the reminders it already canceled',
    () async {
      final app = local(auth: _FailedSignOut());
      addTearDown(app.dispose);
      await app.refreshGuidance();
      await app.setCoachPlanNotifications(true);
      expect(app.scheduledCoachNotificationCount, greaterThan(0));
      await expectLater(app.signOut(), throwsStateError);
      expect(app.isSignedOut, isFalse);
      expect(notifications.scheduled, isEmpty);
      expect(app.scheduledCoachNotificationCount, 0);
      expect(app.nextScheduledNotification, isNull);
    },
  );

  test(
    'restoring cloud notifications off cancels reminders even before setup',
    () async {
      final repository = MemoryCloudRepository(signedInUid: 'owner')
        ..seed('owner', cloudState());
      final app = AppController(
        notificationService: notifications,
        cloudRepository: repository,
        accountAuth: MemoryAccountAuth(
          session: const AccountSession(
            uid: 'owner',
            email: 'owner@example.com',
          ),
        ),
        clock: () => now,
      );
      addTearDown(app.dispose);
      await app.load();
      await app.setCoachPlanNotifications(true);
      expect(notifications.scheduled, isNotEmpty);
      repository.seed('owner', cloudState(onboardingComplete: false));
      await app.useCloudInputs();
      expect(app.onboardingComplete, isFalse);
      expect(app.notificationsEnabled, isFalse);
      expect(notifications.scheduled, isEmpty);
      expect(app.scheduledNotificationCount, 0);
    },
  );
}
