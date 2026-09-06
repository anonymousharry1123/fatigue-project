import 'dart:async';

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/models.dart';
import 'package:app/src/notification_service.dart';
import 'package:app/src/screens/account_sign_in_dialog.dart';
import 'package:app/src/screens/profile_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ControlledSignOutAuth extends MemoryAccountAuth {
  _ControlledSignOutAuth()
    : super(
        session: const AccountSession(
          uid: 'profile-user',
          email: 'person@example.com',
        ),
      );

  final attempts = <Completer<void>>[];

  @override
  Future<void> signOut() async {
    final attempt = Completer<void>();
    attempts.add(attempt);
    await attempt.future;
    await super.signOut();
  }

  void accept() => attempts.last.complete();

  void reject() => attempts.last.completeError(StateError('Sign-out failed'));
}

class _SignOutHealthService extends HealthService {
  @override
  Future<void> disableBackgroundUpdates() async {}
}

class _SignOutNotificationService implements NotificationService {
  @override
  bool get supportsScheduling => false;

  @override
  Future<void> cancelGuidance() async {}

  @override
  Future<NotificationPermissionState> permissionStatus() async =>
      NotificationPermissionState.unavailable;

  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {}

  @override
  Future<NotificationPermissionState> requestPermission() async =>
      NotificationPermissionState.unavailable;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const signOutKey = Key('profile-sign-out-button');
  late _ControlledSignOutAuth auth;
  late MemoryCloudRepository repository;
  late AppController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = _ControlledSignOutAuth();
    repository = MemoryCloudRepository(signedInUid: 'profile-user');
    controller =
        AppController(
            accountAuth: auth,
            cloudRepository: repository,
            healthService: _SignOutHealthService(),
            notificationService: _SignOutNotificationService(),
            clock: () => DateTime(2026, 9, 6, 12),
          )
          ..isReady = true
          ..onboardingComplete = true
          ..accountEmail = 'person@example.com'
          ..profile = const UserProfile(name: 'Returning Maya')
          ..signals = [
            SignalReading(
              id: 'retained-health-signal',
              type: SignalType.steps,
              value: 4000,
              timestamp: DateTime(2026, 9, 6, 10),
              source: SignalSource.healthKit,
            ),
          ]
          ..checkIns = [
            DailyCheckIn(
              id: 'retained-check-in',
              timestamp: DateTime(2026, 9, 6, 9),
              energy: 7,
              mood: 8,
              stress: 3,
            ),
          ];
    repository.seed(
      'profile-user',
      CloudUserState(
        profile: controller.profile,
        accountEmail: controller.accountEmail!,
        onboardingComplete: true,
        notificationsEnabled: false,
        outcomeConsent: false,
        healthAuthorized: false,
        migrationVersion: localMigrationVersion,
        signals: controller.signals,
        checkIns: controller.checkIns,
      ),
    );
  });

  tearDown(() => controller.dispose());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: buildTonyoTheme(),
          home: const Scaffold(body: ProfileScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('signed-in profile has an explicit sign-out button', (
    tester,
  ) async {
    await open(tester);

    expect(find.byKey(signOutKey), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byKey(signOutKey)).onPressed,
      isNotNull,
    );
    await tester.scrollUntilVisible(find.text('Goals & schedule'), 200);
    expect(find.text('Cloud account'), findsNothing);
  });

  testWidgets('signed-out profile offers sign-in instead of sign-out', (
    tester,
  ) async {
    auth.session = null;
    controller.isSignedOut = true;
    await open(tester);

    expect(find.byKey(signOutKey), findsNothing);
    await tester.scrollUntilVisible(find.text('Cloud account'), 200);
    await tester.tap(find.text('Cloud account'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountSignInDialog), findsOneWidget);
  });

  testWidgets('sign-out retains local and cloud data and allows sign-in', (
    tester,
  ) async {
    final localCache = controller.exportJson();
    SharedPreferences.setMockInitialValues({'tonyo_state_v1': localCache});
    final originalSignals = controller.signals.map((s) => s.toJson()).toList();
    final originalCheckIns = controller.checkIns
        .map((c) => c.toJson())
        .toList();
    await open(tester);

    await tester.tap(find.byKey(signOutKey));
    await tester.pump();
    expect(auth.attempts, hasLength(1));
    auth.accept();
    await tester.pumpAndSettle();

    expect(controller.isCloudAuthenticated, isFalse);
    expect(controller.isSignedOut, isTrue);
    expect(controller.cloudUid, isNull);
    expect(controller.onboardingComplete, isTrue);
    expect(controller.profile.name, 'Returning Maya');
    expect(controller.signals.map((s) => s.toJson()).toList(), originalSignals);
    expect(
      controller.checkIns.map((c) => c.toJson()).toList(),
      originalCheckIns,
    );
    expect(
      (await SharedPreferences.getInstance()).getString('tonyo_state_v1'),
      localCache,
    );
    final cloud = await repository.readUser('profile-user');
    expect(cloud, isNotNull);
    expect(cloud!.signals.map((s) => s.toJson()).toList(), originalSignals);
    expect(cloud.checkIns.map((c) => c.toJson()).toList(), originalCheckIns);
    expect(repository.replaceUserCallCount, 0);
    expect(find.byKey(signOutKey), findsNothing);
    expect(
      find.text('Signed out. Your saved data is kept on this device.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Cloud account'), 200);
    await tester.tap(find.text('Cloud account'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountSignInDialog), findsOneWidget);
  });

  testWidgets(
    'pending sign-out disables the button and blocks duplicate calls',
    (tester) async {
      await open(tester);
      final submit = tester
          .widget<OutlinedButton>(find.byKey(signOutKey))
          .onPressed!;
      submit();
      submit();
      await tester.pump();

      expect(auth.attempts, hasLength(1));
      expect(controller.isCloudAuthenticated, isTrue);
      expect(find.text('Signing out…'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byKey(signOutKey)).onPressed,
        isNull,
      );
      auth.accept();
      await tester.pumpAndSettle();
      expect(controller.isCloudAuthenticated, isFalse);
    },
  );

  testWidgets('failed sign-out retains the session and enables retry', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(signOutKey));
    await tester.pump();
    auth.reject();
    await tester.pumpAndSettle();

    expect(controller.isCloudAuthenticated, isTrue);
    expect(controller.isSignedOut, isFalse);
    expect(controller.cloudUid, 'profile-user');
    expect(controller.onboardingComplete, isTrue);
    expect(controller.checkIns.single.id, 'retained-check-in');
    expect(find.text('Could not sign out. Please try again.'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Signing out…'), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byKey(signOutKey)).onPressed,
      isNotNull,
    );
    expect(repository.replaceUserCallCount, 0);

    await tester.tap(find.byKey(signOutKey));
    await tester.pump();
    expect(auth.attempts, hasLength(2));
    auth.accept();
    await tester.pumpAndSettle();
    expect(controller.isCloudAuthenticated, isFalse);
    expect(find.byKey(signOutKey), findsNothing);
  });
}
