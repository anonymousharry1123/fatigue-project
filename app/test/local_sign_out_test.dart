import 'dart:async';

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/models.dart';
import 'package:app/src/notification_service.dart';
import 'package:app/src/screen_time_service.dart';
import 'package:app/src/screens/onboarding_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _session = AccountSession(
  uid: 'saved-user',
  email: 'returning@example.com',
);
const _signOutKey = Key('profile-sign-out-button');
final _now = DateTime(2026, 9, 6, 12);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester, AppController controller) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(TonyoApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> openProfile(WidgetTester tester) async {
    await tester.tap(find.byType(NavigationDestination).last);
    await tester.pumpAndSettle();
    expect(find.byKey(_signOutKey), findsOneWidget);
  }

  void expectWelcome() {
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(_signOutKey), findsNothing);
  }

  Future<void> enterSignIn(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      _session.email,
    );
    await tester.enterText(find.byKey(const Key('password-field')), 'secret');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
  }

  testWidgets(
    'local sign-out returns to welcome, survives restart and resumes saved data',
    (tester) async {
      final health = _TrackingHealth();
      final notifications = _TrackingNotifications();
      final controller = _readyController(
        health: health,
        notifications: notifications,
      );
      addTearDown(controller.dispose);
      final savedCache = controller.exportJson();
      SharedPreferences.setMockInitialValues({'tonyo_state_v1': savedCache});
      await open(tester, controller);
      await openProfile(tester);
      await tester.tap(find.byKey(_signOutKey));
      await tester.pumpAndSettle();

      expectWelcome();
      expect(controller.isSignedOut, isTrue);
      expect(controller.onboardingComplete, isTrue);
      expect(controller.canResumeLocalProfile, isTrue);
      expect(health.disableCalls, 1);
      expect(notifications.cancelCalls, 1);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('tonyo_signed_out_v1'), isTrue);
      expect(preferences.getString('tonyo_state_v1'), savedCache);

      await tester.pumpWidget(const SizedBox.shrink());
      final restartedHealth = _TrackingHealth();
      final restartedScreenTime = _TrackingScreenTime();
      final restarted = AppController(
        healthService: restartedHealth,
        screenTimeService: restartedScreenTime,
        notificationService: _TrackingNotifications(),
        clock: () => _now,
      );
      addTearDown(restarted.dispose);
      await open(tester, restarted);
      expectWelcome();
      expect(restarted.isReady, isTrue);
      expect(restarted.isSignedOut, isTrue);
      expect(restartedHealth.readCalls, 0);
      expect(restartedHealth.enableCalls, 0);
      expect(restartedScreenTime.readCalls, 0);
      expect(preferences.getString('tonyo_state_v1'), savedCache);

      await restarted.handleAppResumed();
      expect(restartedHealth.readCalls, 0);
      expect(restartedScreenTime.readCalls, 0);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Continue local profile'),
      );
      await tester.pumpAndSettle();

      expect(restarted.isSignedOut, isFalse);
      expect(restarted.canResumeLocalProfile, isFalse);
      expect(preferences.getBool('tonyo_signed_out_v1'), isNot(isTrue));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      _expectSavedRecords(restarted);
    },
  );

  testWidgets(
    'explicit local resume restores derived views and previously enabled services',
    (tester) async {
      final saved = _readyController()
        ..healthAuthorized = true
        ..healthAuthorization = HealthAuthorizationState.authorized
        ..notificationsEnabled = true;
      addTearDown(saved.dispose);
      SharedPreferences.setMockInitialValues({
        'tonyo_state_v1': saved.exportJson(),
        'tonyo_signed_out_v1': true,
      });
      final health = _TrackingHealth();
      final screenTime = _TrackingScreenTime();
      final notifications = _TrackingNotifications()
        ..schedulingSupported = true;
      final controller = AppController(
        healthService: health,
        screenTimeService: screenTime,
        notificationService: notifications,
        clock: () => _now,
      );
      addTearDown(controller.dispose);
      await open(tester, controller);
      expectWelcome();
      expect(health.readCalls, 0);
      expect(screenTime.readCalls, 0);
      expect(notifications.reconcileCalls, 0);
      expect(controller.insightsSnapshot.sourceCheckInCount, 0);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Continue local profile'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(controller.insightsSnapshot.sourceSignalCount, 1);
      expect(controller.insightsSnapshot.sourceCheckInCount, 1);
      expect(controller.recommendations, isNotEmpty);
      expect(health.readCalls, greaterThanOrEqualTo(1));
      expect(screenTime.readCalls, greaterThanOrEqualTo(1));
      expect(health.enableCalls, 1);
      expect(controller.healthBackgroundRefreshEnabled, isTrue);
      expect(notifications.reconcileCalls, greaterThanOrEqualTo(1));
      _expectSavedRecords(controller);
    },
  );

  testWidgets(
    'health import finishing after sign-out cannot change cache or reschedule alerts',
    (tester) async {
      final health = _TrackingHealth()
        ..pendingImport = Completer<List<SignalReading>>();
      final notifications = _TrackingNotifications()
        ..schedulingSupported = true;
      final controller =
          _readyController(health: health, notifications: notifications)
            ..healthAuthorized = true
            ..healthAuthorization = HealthAuthorizationState.authorized
            ..notificationsEnabled = true;
      addTearDown(controller.dispose);
      final savedCache = controller.exportJson();
      SharedPreferences.setMockInitialValues({'tonyo_state_v1': savedCache});
      await open(tester, controller);
      final pendingSync = controller.syncHealth(notify: false);
      expect(health.readCalls, 1);
      expect(controller.isSyncing, isTrue);
      await openProfile(tester);
      await tester.tap(find.byKey(_signOutKey));
      await tester.pumpAndSettle();
      expectWelcome();
      expect(notifications.cancelCalls, 1);

      health.pendingImport!.complete([
        SignalReading(
          id: 'late-health-import',
          type: SignalType.hrv,
          value: 55,
          timestamp: _now,
          source: SignalSource.healthKit,
        ),
      ]);
      await pendingSync;
      await tester.pumpAndSettle();

      expectWelcome();
      expect(controller.isSignedOut, isTrue);
      expect(controller.isSyncing, isFalse);
      expect(health.readCalls, 1);
      expect(notifications.reconcileCalls, 0);
      expect(
        (await SharedPreferences.getInstance()).getString('tonyo_state_v1'),
        savedCache,
      );
      _expectSavedRecords(controller);
    },
  );

  testWidgets(
    'cloud sign-out survives restart without opening cache or querying services',
    (tester) async {
      final auth = _ControlledAuth();
      final repository = _TrackingRepository()
        ..seed(_session.uid, _savedState());
      final controller = _readyController(auth: auth, repository: repository);
      addTearDown(controller.dispose);
      final savedCache = controller.exportJson();
      SharedPreferences.setMockInitialValues({'tonyo_state_v1': savedCache});
      await open(tester, controller);
      await openProfile(tester);
      await tester.tap(find.byKey(_signOutKey));
      await tester.pumpAndSettle();

      expectWelcome();
      expect(auth.currentSession, isNull);
      expect(controller.isSignedOut, isTrue);
      expect(controller.canResumeLocalProfile, isFalse);
      expect(find.text('Continue local profile'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      expect(repository.reads, 0);
      expect(repository.replaceUserCallCount, 0);
      expect(repository.deleteCalls, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      final restartedHealth = _TrackingHealth();
      // Even an unexpectedly restored native session cannot bypass the device
      // gate or trigger hydration until the person explicitly signs in again.
      final staleAuth = _ControlledAuth();
      final restarted = AppController(
        accountAuth: staleAuth,
        cloudRepository: repository,
        healthService: restartedHealth,
        screenTimeService: _TrackingScreenTime(),
        notificationService: _TrackingNotifications(),
        clock: () => _now,
      );
      addTearDown(restarted.dispose);
      await open(tester, restarted);
      expectWelcome();
      expect(restarted.isSignedOut, isTrue);
      expect(restarted.canResumeLocalProfile, isFalse);
      expect(repository.reads, 0);
      expect(repository.replaceUserCallCount, 0);
      expect(repository.scoreUpsertCallCount, 0);
      expect(repository.forecastReplaceCallCount, 0);
      expect(restartedHealth.readCalls, 0);
      expect(restartedHealth.enableCalls, 0);
      expect(
        (await SharedPreferences.getInstance()).getString('tonyo_state_v1'),
        savedCache,
      );
      await restarted.handleAppResumed();
      expect(repository.reads, 0);
      expect(restartedHealth.readCalls, 0);
      _expectSavedRecords(restarted);
    },
  );

  testWidgets(
    'incorrect credentials cannot reopen a signed-out cached profile',
    (tester) async {
      final auth = _ControlledAuth();
      final repository = _TrackingRepository()
        ..seed(_session.uid, _savedState());
      final controller = _readyController(auth: auth, repository: repository);
      addTearDown(controller.dispose);
      await controller.signOut();
      await open(tester, controller);
      await enterSignIn(tester);
      expect(controller.isSignedOut, isTrue);
      expect(find.byType(NavigationBar), findsNothing);
      auth.rejectSignIn();
      await tester.pumpAndSettle();

      expect(controller.isSignedOut, isTrue);
      expect(controller.isCloudAuthenticated, isFalse);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(
        find.text('The email or password is incorrect. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
      expect(repository.reads, 0);
      expect(repository.replaceUserCallCount, 0);
      expect(
        (await SharedPreferences.getInstance()).getBool('tonyo_signed_out_v1'),
        isTrue,
      );
      _expectSavedRecords(controller);
    },
  );

  testWidgets(
    'successful reauthentication opens the app only after hydration',
    (tester) async {
      final auth = _ControlledAuth();
      final health = _TrackingHealth();
      final notifications = _TrackingNotifications()
        ..schedulingSupported = true;
      final remote = _savedState(enableServices: true);
      final repository = _TrackingRepository()
        ..seed(_session.uid, remote)
        ..pendingRead = Completer<CloudUserState?>();
      final controller =
          _readyController(
              auth: auth,
              repository: repository,
              health: health,
              notifications: notifications,
            )
            ..healthAuthorized = true
            ..healthAuthorization = HealthAuthorizationState.authorized
            ..notificationsEnabled = true;
      addTearDown(controller.dispose);
      await controller.signOut();
      await open(tester, controller);
      await enterSignIn(tester);
      auth.acceptSignIn();
      await tester.pump();
      await tester.pump();

      expect(repository.reads, 1);
      expect(controller.isSignedOut, isTrue);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Please wait…'), findsOneWidget);
      expect(health.readCalls, 0);
      expect(health.enableCalls, 0);
      expect(notifications.reconcileCalls, 0);
      repository.pendingRead!.complete(remote);
      await tester.pumpAndSettle();

      expect(controller.isSignedOut, isFalse);
      expect(controller.isCloudAuthenticated, isTrue);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(repository.replaceUserCallCount, 0);
      expect(health.readCalls, greaterThanOrEqualTo(1));
      expect(health.enableCalls, 1);
      expect(controller.healthBackgroundRefreshEnabled, isTrue);
      expect(notifications.reconcileCalls, greaterThanOrEqualTo(1));
      expect(
        (await SharedPreferences.getInstance()).getBool('tonyo_signed_out_v1'),
        isNot(isTrue),
      );
      _expectSavedRecords(controller);
    },
  );

  testWidgets(
    'cloud restore failure keeps the previously saved profile gated',
    (tester) async {
      final auth = _ControlledAuth();
      final repository = _TrackingRepository()..failReads = true;
      final controller = _readyController(auth: auth, repository: repository);
      addTearDown(controller.dispose);
      await controller.signOut();
      await open(tester, controller);
      await enterSignIn(tester);
      auth.acceptSignIn();
      await tester.pumpAndSettle();

      expect(controller.isSignedOut, isTrue);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.textContaining('Your password was verified'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(repository.replaceUserCallCount, 0);
      expect(repository.scoreUpsertCallCount, 0);
      expect(repository.forecastReplaceCallCount, 0);
      expect(
        (await SharedPreferences.getInstance()).getBool('tonyo_signed_out_v1'),
        isTrue,
      );
      _expectSavedRecords(controller);
    },
  );

  testWidgets(
    'failed cloud sign-out keeps the active session and allows retry',
    (tester) async {
      final auth = _ControlledAuth()..failSignOut = true;
      final repository = _TrackingRepository();
      final controller = _readyController(auth: auth, repository: repository);
      addTearDown(controller.dispose);
      await open(tester, controller);
      await openProfile(tester);
      await tester.tap(find.byKey(_signOutKey));
      await tester.pumpAndSettle();

      expect(controller.isSignedOut, isFalse);
      expect(controller.isCloudAuthenticated, isTrue);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(
        find.text('Could not sign out. Please try again.'),
        findsOneWidget,
      );
      expect(repository.replaceUserCallCount, 0);
      expect(repository.deleteCalls, 0);
      expect(
        (await SharedPreferences.getInstance()).getBool('tonyo_signed_out_v1'),
        isNot(isTrue),
      );
      auth.failSignOut = false;
      await tester.tap(find.byKey(_signOutKey));
      await tester.pumpAndSettle();
      expectWelcome();
      expect(controller.isSignedOut, isTrue);
    },
  );
}

AppController _readyController({
  _ControlledAuth? auth,
  _TrackingRepository? repository,
  _TrackingHealth? health,
  _TrackingNotifications? notifications,
}) {
  final saved = _savedState();
  return AppController(
      accountAuth: auth,
      cloudRepository: repository,
      healthService: health ?? _TrackingHealth(),
      screenTimeService: _TrackingScreenTime(),
      notificationService: notifications ?? _TrackingNotifications(),
      clock: () => _now,
    )
    ..isReady = true
    ..onboardingComplete = true
    ..accountEmail = saved.accountEmail
    ..profile = saved.profile
    ..signals = List.of(saved.signals)
    ..checkIns = List.of(saved.checkIns);
}

CloudUserState _savedState({bool enableServices = false}) => CloudUserState(
  profile: const UserProfile(name: 'Saved Maya', wakeHour: 6),
  accountEmail: _session.email,
  onboardingComplete: true,
  notificationsEnabled: enableServices,
  notificationPrefsVersion: notificationPreferencesVersion,
  outcomeConsent: false,
  healthAuthorized: enableServices,
  // A just-synced account should restore observers without fetching the same
  // native history again or needlessly rewriting its cloud records.
  lastHealthSyncAttempt: enableServices ? _now : null,
  migrationVersion: localMigrationVersion,
  signals: [
    SignalReading(
      id: 'saved-health-signal',
      type: SignalType.steps,
      value: 4321,
      timestamp: _now.subtract(const Duration(hours: 1)),
      source: SignalSource.healthKit,
    ),
  ],
  checkIns: [
    DailyCheckIn(
      id: 'saved-check-in',
      timestamp: _now.subtract(const Duration(hours: 2)),
      energy: 7,
      mood: 8,
      stress: 3,
    ),
  ],
);

void _expectSavedRecords(AppController controller) {
  final saved = _savedState();
  expect(controller.onboardingComplete, isTrue);
  expect(controller.profile.toJson(), saved.profile.toJson());
  expect(
    controller.signals.map((item) => item.toJson()).toList(),
    saved.signals.map((item) => item.toJson()).toList(),
  );
  expect(
    controller.checkIns.map((item) => item.toJson()).toList(),
    saved.checkIns.map((item) => item.toJson()).toList(),
  );
}

class _ControlledAuth extends MemoryAccountAuth {
  _ControlledAuth() : super(session: _session);
  Completer<AccountSession> pendingSignIn = Completer<AccountSession>();
  bool failSignOut = false;

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) async {
    final verified = await pendingSignIn.future;
    session = verified;
    return verified;
  }

  void acceptSignIn() => pendingSignIn.complete(_session);
  void rejectSignIn() => pendingSignIn.completeError(
    FirebaseAuthException(code: 'invalid-credential'),
  );

  @override
  Future<void> signOut() async {
    if (failSignOut) throw StateError('Sign-out failed');
    await super.signOut();
  }
}

class _TrackingRepository extends MemoryCloudRepository {
  _TrackingRepository() : super(signedInUid: _session.uid);
  int reads = 0;
  int deleteCalls = 0;
  bool failReads = false;
  Completer<CloudUserState?>? pendingRead;

  @override
  Future<CloudUserState?> readUser(String uid) {
    reads++;
    if (failReads) throw StateError('Cloud is offline');
    return pendingRead?.future ?? super.readUser(uid);
  }

  @override
  Future<void> deleteUserTree(String uid) {
    deleteCalls++;
    return super.deleteUserTree(uid);
  }
}

class _TrackingHealth extends HealthService {
  int readCalls = 0;
  int enableCalls = 0;
  int disableCalls = 0;
  Completer<List<SignalReading>>? pendingImport;

  @override
  Future<HealthAuthorizationState> authorizationStatus() async {
    readCalls++;
    return HealthAuthorizationState.authorized;
  }

  @override
  Future<bool> enableBackgroundUpdates(
    Future<void> Function() onHealthDataChanged,
  ) async {
    enableCalls++;
    return true;
  }

  @override
  Future<void> disableBackgroundUpdates() async => disableCalls++;

  @override
  Future<List<SignalReading>> sync() async {
    readCalls++;
    return pendingImport == null ? [] : await pendingImport!.future;
  }

  @override
  Future<List<SignalReading>> syncSleep() => sync();

  @override
  Future<List<SignalReading>> syncActivity() => sync();
}

class _TrackingScreenTime extends ScreenTimeService {
  int readCalls = 0;

  @override
  Future<ScreenTimeAuthorizationState> authorizationStatus() async {
    readCalls++;
    return ScreenTimeAuthorizationState.unavailable;
  }
}

class _TrackingNotifications implements NotificationService {
  int cancelCalls = 0;
  int reconcileCalls = 0;
  bool schedulingSupported = false;

  @override
  bool get supportsScheduling => schedulingSupported;

  @override
  Future<void> cancelGuidance() async => cancelCalls++;

  @override
  Future<NotificationPermissionState> permissionStatus() async =>
      schedulingSupported
      ? NotificationPermissionState.granted
      : NotificationPermissionState.unavailable;

  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async =>
      reconcileCalls++;

  @override
  Future<NotificationPermissionState> requestPermission() async =>
      NotificationPermissionState.unavailable;
}
