import 'dart:async';

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/models.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openSignIn(WidgetTester tester, AppController controller) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(TonyoApp(controller: controller));
    if (controller.isSignedOut) {
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    } else {
      await tester.tap(find.byKey(const Key('onboarding-welcome-sign-in')));
    }
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'returning@example.com',
    );
    await tester.enterText(find.byKey(const Key('password-field')), 'secret');
    await tester.pump();
  }

  for (final error in {
    'invalid-credential':
        'The email or password is incorrect. Please try again.',
    'network-request-failed':
        'Unable to connect. Check your internet connection and try again.',
    'too-many-requests':
        'Too many attempts. Please wait a little before trying again.',
  }.entries) {
    testWidgets('onboarding stays at sign-in on ${error.key}', (tester) async {
      final auth = _ControlledAuth();
      final repository = _TrackingRepository();
      final controller = AppController(
        accountAuth: auth,
        cloudRepository: repository,
      )..isReady = true;
      addTearDown(controller.dispose);
      await openSignIn(tester, controller);

      final submit = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Sign in'))
          .onPressed!;
      submit();
      submit(); // Two rapid submissions still issue exactly one auth request.
      await tester.pump();
      expect(auth.signInCalls, 1);
      expect(auth.registerCalls, 0);
      expect(controller.isCloudAuthenticated, isFalse);
      expect(controller.onboardingComplete, isFalse);
      expect(repository.reads, 0);
      expect(repository.writes, 0);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Please wait…'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('password-field')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Create a new account instead'),
            )
            .onPressed,
        isNull,
      );

      auth.pending.completeError(FirebaseAuthException(code: error.key));
      await tester.pumpAndSettle();
      expect(find.text(error.value), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(controller.isCloudAuthenticated, isFalse);
      expect(controller.onboardingComplete, isFalse);
      expect(controller.accountEmail, isNull);
      expect(controller.signals, isEmpty);
      expect(controller.modelPreparationRevision, 0);
      expect(repository.reads, 0);
      expect(repository.writes, 0);
      expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, 'Email'))
            .controller!
            .text,
        'returning@example.com',
      );
    });
  }

  testWidgets(
    'valid retry restores existing profile directly from account form',
    (tester) async {
      final auth = _ControlledAuth();
      final repository = _TrackingRepository()
        ..seed('returning-uid', _savedState());
      final controller = AppController(
        accountAuth: auth,
        cloudRepository: repository,
      )..isReady = true;
      addTearDown(controller.dispose);
      await openSignIn(tester, controller);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      auth.pending.completeError(FirebaseAuthException(code: 'wrong-password'));
      await tester.pumpAndSettle();

      auth.pending = Completer<AccountSession>();
      await tester.enterText(
        find.byKey(const Key('password-field')),
        'correct-pass',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      expect(find.byKey(const Key('onboarding-account-error')), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      auth.succeed();
      await tester.pumpAndSettle();

      expect(auth.signInCalls, 2);
      expect(auth.registerCalls, 0);
      expect(controller.isCloudAuthenticated, isTrue);
      expect(controller.onboardingComplete, isTrue);
      expect(controller.profile.name, 'Saved profile');
      expect(controller.profile.wakeHour, 6);
      expect(controller.signals.single.id, 'saved-signal');
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Make it yours'), findsNothing);
      expect(controller.exportJson(), isNot(contains('correct-pass')));
      expect(repository.writes, 0);
    },
  );

  for (final signedOut in [false, true]) {
    testWidgets(
      'verified account without a profile can finish setup without reauth (signedOut: $signedOut)',
      (tester) async {
        final auth = _ControlledAuth();
        final repository = _TrackingRepository();
        final controller =
            AppController(accountAuth: auth, cloudRepository: repository)
              ..isReady = true
              ..isSignedOut = signedOut;
        addTearDown(controller.dispose);
        await openSignIn(tester, controller);
        await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
        await tester.pump();
        expect(find.text('Make it yours'), findsNothing);
        auth.succeed();
        await tester.pumpAndSettle();
        expect(find.text('Privacy center'), findsOneWidget);
        expect(controller.isCloudAuthenticated, isTrue);
        expect(controller.onboardingComplete, isFalse);
        expect(repository.writes, 0);

        await acknowledgeAdultPrivacy(tester);
        await tester.ensureVisible(
          find.byKey(const Key('privacy-accept-button')),
        );
        await tester.tap(find.byKey(const Key('privacy-accept-button')));
        await tester.pumpAndSettle();
        expect(find.text('Make it yours'), findsOneWidget);

        await tester.tap(find.text('Set my schedule'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Finish account setup'));
        await tester.pumpAndSettle();
        expect(controller.onboardingComplete, isTrue);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(auth.signInCalls, 1);
        expect(auth.registerCalls, 0);
        expect(repository.writes, 1);
      },
    );
  }

  testWidgets(
    'cloud read failure after valid credentials cannot create defaults',
    (tester) async {
      final auth = _ControlledAuth();
      final repository = _TrackingRepository()..failReads = true;
      final controller = AppController(
        accountAuth: auth,
        cloudRepository: repository,
      )..isReady = true;
      addTearDown(controller.dispose);
      await openSignIn(tester, controller);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      auth.succeed();
      await tester.pumpAndSettle();

      expect(controller.isCloudAuthenticated, isTrue);
      expect(controller.onboardingComplete, isFalse);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.textContaining('Your password was verified'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(repository.writes, 0);
      await expectLater(
        controller.completeAuthenticatedOnboarding(const UserProfile()),
        throwsStateError,
      );
      expect(repository.writes, 0);
    },
  );

  test(
    'finishing existing-account setup requires an authenticated session',
    () async {
      final controller = AppController(
        accountAuth: _ControlledAuth(),
        cloudRepository: _TrackingRepository(),
      );
      addTearDown(controller.dispose);
      await expectLater(
        controller.completeAuthenticatedOnboarding(const UserProfile()),
        throwsStateError,
      );
      expect(controller.onboardingComplete, isFalse);
      expect(controller.signals, isEmpty);
    },
  );

  testWidgets(
    'wrong-password retry replaces the previous verified-but-offline error',
    (tester) async {
      final auth = _ControlledAuth();
      final repository = _TrackingRepository()..failReads = true;
      final controller =
          AppController(accountAuth: auth, cloudRepository: repository)
            ..isReady = true
            ..isSignedOut = true;
      addTearDown(controller.dispose);
      await openSignIn(tester, controller);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      auth.succeed();
      await tester.pumpAndSettle();

      expect(find.textContaining('Your password was verified'), findsOneWidget);
      expect(controller.cloudSyncError, isNotNull);
      expect(controller.isSignedOut, isTrue);
      expect(repository.reads, 1);

      auth.pending = Completer<AccountSession>();
      await tester.enterText(
        find.byKey(const Key('password-field')),
        'wrong-password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      auth.pending.completeError(FirebaseAuthException(code: 'wrong-password'));
      await tester.pumpAndSettle();

      expect(
        find.text('The email or password is incorrect. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Your password was verified'), findsNothing);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(controller.isSignedOut, isTrue);
      expect(auth.signInCalls, 2);
      expect(auth.registerCalls, 0);
      expect(repository.reads, 1);
      expect(repository.writes, 0);
    },
  );

  testWidgets(
    'signed-out cache is not migrated to a different account without cloud data',
    (tester) async {
      final auth = _ControlledAuth();
      final repository = _TrackingRepository();
      final saved = _savedState();
      final controller =
          AppController(accountAuth: auth, cloudRepository: repository)
            ..isReady = true
            ..isSignedOut = true
            ..onboardingComplete = true
            ..accountEmail = 'original@example.com'
            ..profile = saved.profile
            ..signals = saved.signals
            ..checkIns = saved.checkIns;
      addTearDown(controller.dispose);
      final savedCache = controller.exportJson();
      SharedPreferences.setMockInitialValues({
        'tonyo_state_v1': savedCache,
        'tonyo_signed_out_v1': true,
      });
      await openSignIn(tester, controller);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      auth.succeed();
      await tester.pumpAndSettle();

      expect(controller.isCloudAuthenticated, isTrue);
      expect(controller.isSignedOut, isTrue);
      expect(controller.onboardingComplete, isTrue);
      expect(controller.accountEmail, 'original@example.com');
      expect(controller.exportJson(), savedCache);
      expect(
        (await SharedPreferences.getInstance()).getString('tonyo_state_v1'),
        savedCache,
      );
      expect(
        controller.cloudSyncError,
        contains('belongs to another account and cannot be migrated'),
      );
      expect(repository.reads, 1);
      expect(repository.writes, 0);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.byKey(const Key('onboarding-account-error')), findsOneWidget);
      expect(find.text('Make it yours'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  test(
    'legacy existing-account onboarding cannot write after cloud read failure',
    () async {
      final auth = _ControlledAuth();
      final repository = _TrackingRepository()..failReads = true;
      final controller = AppController(
        accountAuth: auth,
        cloudRepository: repository,
      );
      addTearDown(controller.dispose);
      final attempt = controller.completeOnboarding(
        const UserProfile(name: 'Must not overwrite saved profile'),
        email: 'returning@example.com',
        password: 'secret',
        signInToExistingAccount: true,
      );
      final expectation = expectLater(attempt, throwsStateError);
      auth.succeed();
      await expectation;
      expect(controller.onboardingComplete, isFalse);
      expect(controller.signals, isEmpty);
      expect(repository.writes, 0);
      expect(auth.registerCalls, 0);
    },
  );
}

CloudUserState _savedState() => CloudUserState(
  profile: const UserProfile(name: 'Saved profile', wakeHour: 6),
  accountEmail: 'returning@example.com',
  onboardingComplete: true,
  notificationsEnabled: false,
  outcomeConsent: false,
  privacyConsent: testAdultPrivacyConsent,
  healthAuthorized: false,
  migrationVersion: localMigrationVersion,
  signals: [
    SignalReading(
      id: 'saved-signal',
      type: SignalType.hydration,
      value: 2,
      timestamp: DateTime(2026, 9, 6),
    ),
  ],
  checkIns: const [],
);

class _ControlledAuth extends MemoryAccountAuth {
  Completer<AccountSession> pending = Completer<AccountSession>();
  int signInCalls = 0;
  int registerCalls = 0;

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    final verified = await pending.future;
    session = verified;
    return verified;
  }

  void succeed() => pending.complete(
    const AccountSession(uid: 'returning-uid', email: 'returning@example.com'),
  );

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) {
    registerCalls++;
    throw StateError('Returning users must not register another account.');
  }
}

class _TrackingRepository extends MemoryCloudRepository {
  _TrackingRepository() : super(signedInUid: 'returning-uid');
  int reads = 0;
  int writes = 0;
  bool failReads = false;

  @override
  Future<CloudUserState?> readUser(String uid) {
    reads++;
    if (failReads) throw StateError('Cloud is offline.');
    return super.readUser(uid);
  }

  @override
  Future<void> replaceUser(String uid, CloudUserState state) {
    writes++;
    return super.replaceUser(uid, state);
  }
}
