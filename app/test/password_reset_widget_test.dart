import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/screens/account_sign_in_dialog.dart';
import 'package:app/src/screens/change_password_dialog.dart';
import 'package:app/src/screens/password_reset_dialog.dart';
import 'package:app/src/screens/profile_screen.dart';
import 'package:app/src/theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

/// Lets a test replace one auth step with a Firebase failure.
class _FailingResetAuth extends MemoryAccountAuth {
  _FailingResetAuth({
    super.session,
    super.expectedPassword,
    this.sendError,
    this.verifyError,
    this.reauthError,
  });

  final String? sendError;
  final String? verifyError;
  final String? reauthError;
  int sendCalls = 0;

  @override
  Future<void> sendPasswordReset({required String email}) async {
    sendCalls++;
    if (sendError != null) throw FirebaseAuthException(code: sendError!);
    await super.sendPasswordReset(email: email);
  }

  @override
  Future<String> verifyPasswordResetCode(String code) async {
    if (verifyError != null) throw FirebaseAuthException(code: verifyError!);
    return super.verifyPasswordResetCode(code);
  }

  @override
  Future<void> reauthenticate({required String password}) async {
    if (reauthError != null && password != expectedPassword) {
      throw FirebaseAuthException(code: reauthError!);
    }
    await super.reauthenticate(password: password);
  }
}

class _DialogOutcome {
  bool closed = false;
  String? email;
}

const _resetLink =
    'https://tonyo-app.firebaseapp.com/__/auth/action'
    '?mode=resetPassword&oobCode=${MemoryAccountAuth.testResetCode}'
    '&apiKey=key&lang=en';

const _emailKey = Key('password-reset-email');
const _sendKey = Key('password-reset-send');
const _haveCodeKey = Key('password-reset-have-code');
const _sentKey = Key('password-reset-sent');
const _codeKey = Key('password-reset-code');
const _verifyKey = Key('password-reset-verify');
const _accountEmailKey = Key('password-reset-account-email');
const _newPasswordKey = Key('password-reset-new-password');
const _confirmPasswordKey = Key('password-reset-confirm-password');
const _submitKey = Key('password-reset-submit');
const _cancelKey = Key('password-reset-cancel');
const _errorKey = Key('password-reset-error');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  AppController buildController(MemoryAccountAuth auth) {
    final controller = AppController(
      initialPrivacyConsent: testAdultPrivacyConsent,
      accountAuth: auth,
      cloudRepository: MemoryCloudRepository(signedInUid: 'profile-user'),
    )..isReady = true;
    addTearDown(controller.dispose);
    return controller;
  }

  Future<_DialogOutcome> openResetDialog(
    WidgetTester tester,
    AppController controller, {
    String? initialEmail,
  }) async {
    final outcome = _DialogOutcome();
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: buildTonyoTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  outcome.email = await PasswordResetDialog.show(
                    context,
                    controller: controller,
                    initialEmail: initialEmail,
                  );
                  outcome.closed = true;
                },
                child: const Text('Open reset'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open reset'));
    await tester.pumpAndSettle();
    expect(find.byType(PasswordResetDialog), findsOneWidget);
    return outcome;
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  Future<void> requestEmail(
    WidgetTester tester, {
    String email = 'person@example.com',
  }) async {
    await tester.enterText(find.byKey(_emailKey), email);
    await tapKey(tester, _sendKey);
  }

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(_codeKey), code);
    await tapKey(tester, _verifyKey);
  }

  Future<void> enterNewPassword(
    WidgetTester tester,
    String password, {
    String? confirm,
  }) async {
    await tester.enterText(find.byKey(_newPasswordKey), password);
    await tester.enterText(
      find.byKey(_confirmPasswordKey),
      confirm ?? password,
    );
    await tapKey(tester, _submitKey);
  }

  String fieldText(WidgetTester tester, Key key) =>
      tester.widget<TextFormField>(find.byKey(key)).controller!.text;

  group('PasswordResetDialog', () {
    testWidgets('request step shows the neutral sent message', (tester) async {
      final auth = MemoryAccountAuth();
      final controller = buildController(auth);
      await openResetDialog(tester, controller);

      await requestEmail(tester, email: ' Person@Example.com ');

      expect(auth.lastPasswordResetEmail, 'person@example.com');
      expect(auth.issuedResetCode, MemoryAccountAuth.testResetCode);
      expect(find.byKey(_sentKey), findsOneWidget);
      expect(
        find.textContaining('If an account exists for Person@Example.com'),
        findsOneWidget,
      );
      expect(find.byKey(_codeKey), findsOneWidget);
      expect(find.byKey(_verifyKey), findsOneWidget);
      expect(find.byKey(_errorKey), findsNothing);
    });

    testWidgets('request step validates the email before sending', (
      tester,
    ) async {
      final auth = _FailingResetAuth();
      final controller = buildController(auth);
      await openResetDialog(tester, controller);

      await tapKey(tester, _sendKey);
      expect(find.text('Enter your email.'), findsOneWidget);
      await requestEmail(tester, email: 'not an email');
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(auth.sendCalls, 0);
      expect(find.byKey(_sentKey), findsNothing);
    });

    testWidgets('unknown accounts still show the neutral sent message', (
      tester,
    ) async {
      final auth = _FailingResetAuth(sendError: 'user-not-found');
      final controller = buildController(auth);
      await openResetDialog(tester, controller);

      await requestEmail(tester, email: 'nobody@example.com');

      expect(auth.sendCalls, 1);
      expect(find.byKey(_sentKey), findsOneWidget);
      expect(
        find.textContaining('If an account exists for nobody@example.com'),
        findsOneWidget,
      );
      expect(find.byKey(_errorKey), findsNothing);
      expect(find.byKey(_codeKey), findsOneWidget);
    });

    testWidgets('other request failures stay on the request step', (
      tester,
    ) async {
      final auth = _FailingResetAuth(sendError: 'network-request-failed');
      final controller = buildController(auth);
      await openResetDialog(tester, controller);

      await requestEmail(tester);

      expect(find.byKey(_sentKey), findsNothing);
      expect(find.byKey(_emailKey), findsOneWidget);
      expect(
        find.text(
          'Unable to connect. Check your internet connection and try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('invalid code shows an error and stays on the code step', (
      tester,
    ) async {
      final auth = MemoryAccountAuth();
      final controller = buildController(auth);
      await openResetDialog(tester, controller);
      await requestEmail(tester);

      await tapKey(tester, _verifyKey);
      expect(
        find.text('Paste the reset link or code from the email.'),
        findsOneWidget,
      );

      await enterCode(tester, 'wrong-code');
      expect(find.byKey(_errorKey), findsOneWidget);
      expect(
        find.text('The password could not be reset. Please try again.'),
        findsOneWidget,
      );
      expect(find.byKey(_codeKey), findsOneWidget);
      expect(find.byKey(_newPasswordKey), findsNothing);
      expect(auth.issuedResetCode, MemoryAccountAuth.testResetCode);
    });

    testWidgets('expired Firebase code asks for a new email', (tester) async {
      final auth = _FailingResetAuth(verifyError: 'expired-action-code');
      final controller = buildController(auth);
      await openResetDialog(tester, controller);
      await requestEmail(tester);

      await enterCode(tester, _resetLink);
      expect(
        find.text(
          'This reset code is invalid or has expired. Request a new email.',
        ),
        findsOneWidget,
      );

      await tapKey(tester, const Key('password-reset-request-new'));
      expect(find.byKey(_emailKey), findsOneWidget);
      expect(find.byKey(_errorKey), findsNothing);
      expect(fieldText(tester, _emailKey), 'person@example.com');
    });

    testWidgets('valid link resets the password and returns the email', (
      tester,
    ) async {
      final auth = MemoryAccountAuth(expectedPassword: 'old-password');
      final controller = buildController(auth);
      final outcome = await openResetDialog(
        tester,
        controller,
        initialEmail: 'person@example.com',
      );
      expect(fieldText(tester, _emailKey), 'person@example.com');

      await tapKey(tester, _sendKey);
      await enterCode(tester, _resetLink);

      expect(find.byKey(_accountEmailKey), findsOneWidget);
      expect(
        find.text('Choose a new password for person@example.com.'),
        findsOneWidget,
      );

      await enterNewPassword(tester, 'new-password-1');

      expect(outcome.closed, isTrue);
      expect(outcome.email, 'person@example.com');
      expect(find.byType(PasswordResetDialog), findsNothing);
      expect(auth.expectedPassword, 'new-password-1');
      expect(auth.issuedResetCode, isNull);
    });

    testWidgets('existing code can be entered without requesting again', (
      tester,
    ) async {
      final auth = MemoryAccountAuth(
        lastPasswordResetEmail: 'person@example.com',
        issuedResetCode: MemoryAccountAuth.testResetCode,
      );
      final controller = buildController(auth);
      final outcome = await openResetDialog(tester, controller);

      await tapKey(tester, _haveCodeKey);
      expect(find.byKey(_sentKey), findsNothing);
      await enterCode(tester, ' ${MemoryAccountAuth.testResetCode} ');
      await enterNewPassword(tester, 'new-password-2');

      expect(outcome.email, 'person@example.com');
      expect(auth.expectedPassword, 'new-password-2');
    });

    testWidgets('mismatched or short passwords are rejected before reset', (
      tester,
    ) async {
      final auth = MemoryAccountAuth(expectedPassword: 'old-password');
      final controller = buildController(auth);
      final outcome = await openResetDialog(tester, controller);
      await requestEmail(tester);
      await enterCode(tester, _resetLink);

      await enterNewPassword(
        tester,
        'new-password-1',
        confirm: 'new-password-2',
      );
      expect(find.text('Passwords do not match'), findsOneWidget);

      await enterNewPassword(tester, 'short');
      expect(find.text('Use at least 8 characters'), findsOneWidget);

      expect(outcome.closed, isFalse);
      expect(find.byType(PasswordResetDialog), findsOneWidget);
      expect(auth.expectedPassword, 'old-password');
      expect(auth.issuedResetCode, MemoryAccountAuth.testResetCode);
    });

    testWidgets('cancel closes without a result', (tester) async {
      final auth = MemoryAccountAuth();
      final controller = buildController(auth);
      final outcome = await openResetDialog(tester, controller);

      await tapKey(tester, _cancelKey);

      expect(outcome.closed, isTrue);
      expect(outcome.email, isNull);
      expect(auth.lastPasswordResetEmail, isNull);
    });
  });

  group('sign-in entry points', () {
    Future<void> pumpProfile(
      WidgetTester tester,
      AppController controller,
    ) async {
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

    testWidgets('profile sign-in forgot password prefills the reset email', (
      tester,
    ) async {
      final auth = MemoryAccountAuth(expectedPassword: 'old-password');
      final controller = buildController(auth);
      await pumpProfile(tester, controller);
      await tester.scrollUntilVisible(find.text('Cloud account'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cloud account'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountSignInDialog), findsOneWidget);

      const forgotKey = Key('profile-sign-in-forgot-password');
      expect(find.byKey(forgotKey), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('profile-sign-in-email')),
        ' Person@Example.com ',
      );
      await tester.enterText(
        find.byKey(const Key('profile-sign-in-password')),
        'forgotten',
      );
      await tapKey(tester, forgotKey);

      expect(find.byType(PasswordResetDialog), findsOneWidget);
      expect(fieldText(tester, _emailKey), 'Person@Example.com');

      await tapKey(tester, _sendKey);
      await enterCode(tester, _resetLink);
      await enterNewPassword(tester, 'new-password-1');

      expect(find.byType(PasswordResetDialog), findsNothing);
      expect(find.byType(AccountSignInDialog), findsOneWidget);
      expect(auth.expectedPassword, 'new-password-1');
      expect(
        fieldText(tester, const Key('profile-sign-in-email')),
        'person@example.com',
      );
      expect(fieldText(tester, const Key('profile-sign-in-password')), isEmpty);
      expect(find.byKey(const Key('profile-sign-in-info')), findsOneWidget);
      expect(
        find.text('Password updated. Sign in with your new password.'),
        findsOneWidget,
      );
      expect(controller.isCloudAuthenticated, isFalse);
    });

    testWidgets('onboarding sign-in offers forgot password with cloud', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = MemoryAccountAuth();
      final controller = AppController(
        accountAuth: auth,
        cloudRepository: MemoryCloudRepository(signedInUid: 'returning-uid'),
      )..isReady = true;
      addTearDown(controller.dispose);
      await tester.pumpWidget(TonyoApp(controller: controller));
      await tester.tap(find.byKey(const Key('onboarding-welcome-sign-in')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'returning@example.com',
      );

      const forgotKey = Key('onboarding-forgot-password');
      expect(find.byKey(forgotKey), findsOneWidget);
      await tapKey(tester, forgotKey);
      expect(fieldText(tester, _emailKey), 'returning@example.com');

      await tapKey(tester, _sendKey);
      await enterCode(tester, _resetLink);
      await enterNewPassword(tester, 'new-password-1');

      expect(find.byType(PasswordResetDialog), findsNothing);
      expect(auth.expectedPassword, 'new-password-1');
      expect(
        find.text('Password updated. Sign in with your new password.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('password-field')))
            .controller!
            .text,
        isEmpty,
      );
      expect(controller.isCloudAuthenticated, isFalse);
    });
  });

  group('ChangePasswordDialog', () {
    const buttonKey = Key('profile-change-password-button');
    const currentKey = Key('change-password-current');
    const newKey = Key('change-password-new');
    const confirmKey = Key('change-password-confirm');
    const changeSubmitKey = Key('change-password-submit');
    const changeErrorKey = Key('change-password-error');
    const session = AccountSession(
      uid: 'profile-user',
      email: 'person@example.com',
    );

    AppController signedInController(MemoryAccountAuth auth) =>
        buildController(auth)
          ..onboardingComplete = true
          ..accountEmail = 'person@example.com';

    Future<void> openChangePassword(
      WidgetTester tester,
      AppController controller,
    ) async {
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
      expect(find.byKey(buttonKey), findsOneWidget);
      await tapKey(tester, buttonKey);
      expect(find.byType(ChangePasswordDialog), findsOneWidget);
      expect(find.byKey(const Key('change-password-email')), findsOneWidget);
    }

    Future<void> submitChange(
      WidgetTester tester, {
      required String current,
      required String next,
      String? confirm,
    }) async {
      await tester.enterText(find.byKey(currentKey), current);
      await tester.enterText(find.byKey(newKey), next);
      await tester.enterText(find.byKey(confirmKey), confirm ?? next);
      await tapKey(tester, changeSubmitKey);
    }

    testWidgets('profile button is shown only for cloud accounts', (
      tester,
    ) async {
      final controller = buildController(MemoryAccountAuth())
        ..onboardingComplete = true;
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
      expect(find.byKey(const Key('profile-sign-out-button')), findsOneWidget);
      expect(find.byKey(buttonKey), findsNothing);

      final signedIn = signedInController(MemoryAccountAuth(session: session));
      await tester.pumpWidget(
        AppScope(
          controller: signedIn,
          child: MaterialApp(
            theme: buildTonyoTheme(),
            home: const Scaffold(body: ProfileScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(buttonKey), findsOneWidget);
      expect(find.text('Change password'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byKey(buttonKey)).onPressed,
        isNotNull,
      );
    });

    testWidgets('wrong current password shows an error', (tester) async {
      final auth = MemoryAccountAuth(
        session: session,
        expectedPassword: 'current-pass-1',
      );
      final controller = signedInController(auth);
      await openChangePassword(tester, controller);

      await submitChange(tester, current: 'wrong-pass-1', next: 'new-pass-12');

      expect(find.byKey(changeErrorKey), findsOneWidget);
      expect(
        find.text('The password could not be changed. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(ChangePasswordDialog), findsOneWidget);
      expect(auth.expectedPassword, 'current-pass-1');
    });

    testWidgets('Firebase credential rejection names the current password', (
      tester,
    ) async {
      final auth = _FailingResetAuth(
        session: session,
        expectedPassword: 'current-pass-1',
        reauthError: 'invalid-credential',
      );
      final controller = signedInController(auth);
      await openChangePassword(tester, controller);

      await submitChange(tester, current: 'wrong-pass-1', next: 'new-pass-12');

      expect(find.text('Current password is incorrect.'), findsOneWidget);
      expect(auth.expectedPassword, 'current-pass-1');
    });

    testWidgets('new password must differ from the current one', (
      tester,
    ) async {
      final auth = MemoryAccountAuth(
        session: session,
        expectedPassword: 'current-pass-1',
      );
      final controller = signedInController(auth);
      await openChangePassword(tester, controller);

      await submitChange(
        tester,
        current: 'current-pass-1',
        next: 'current-pass-1',
      );

      expect(
        find.text('Choose a password different from your current one.'),
        findsOneWidget,
      );
      expect(find.byKey(changeErrorKey), findsNothing);
      expect(find.byType(ChangePasswordDialog), findsOneWidget);

      await submitChange(
        tester,
        current: 'current-pass-1',
        next: 'new-pass-12',
        confirm: 'new-pass-13',
      );
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(auth.expectedPassword, 'current-pass-1');
    });

    testWidgets('correct current password updates the password', (
      tester,
    ) async {
      final auth = MemoryAccountAuth(
        session: session,
        expectedPassword: 'current-pass-1',
      );
      final controller = signedInController(auth);
      await openChangePassword(tester, controller);

      await submitChange(
        tester,
        current: 'current-pass-1',
        next: 'new-pass-12',
      );

      expect(find.byType(ChangePasswordDialog), findsNothing);
      expect(find.text('Password updated.'), findsOneWidget);
      expect(auth.expectedPassword, 'new-pass-12');
      expect(controller.isCloudAuthenticated, isTrue);
    });
  });
}
