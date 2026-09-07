import 'privacy_test_support.dart';
import 'dart:async';

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/screens/account_sign_in_dialog.dart';
import 'package:app/src/screens/profile_screen.dart';
import 'package:app/src/theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ControlledAuth extends MemoryAccountAuth {
  final attempts = <Completer<AccountSession>>[];
  final emails = <String>[];
  final passwords = <String>[];

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) async {
    emails.add(email);
    passwords.add(password);
    final attempt = Completer<AccountSession>();
    attempts.add(attempt);
    session = await attempt.future;
    return session!;
  }

  void accept() => attempts.last.complete(
    const AccountSession(uid: 'profile-user', email: 'person@example.com'),
  );

  void reject(String code) =>
      attempts.last.completeError(FirebaseAuthException(code: code));
}

class _ControlledRepository extends MemoryCloudRepository {
  _ControlledRepository() : super(signedInUid: 'profile-user');

  Completer<void>? readGate;
  int userReads = 0;

  @override
  Future<CloudUserState?> readUser(String uid) async {
    userReads++;
    await readGate?.future;
    return super.readUser(uid);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const emailKey = Key('profile-sign-in-email');
  const passwordKey = Key('profile-sign-in-password');
  const submitKey = Key('profile-sign-in-submit');
  const cancelKey = Key('profile-sign-in-cancel');
  const errorKey = Key('profile-sign-in-error');

  late _ControlledAuth auth;
  late _ControlledRepository repository;
  late AppController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = _ControlledAuth();
    repository = _ControlledRepository();
    controller = AppController(
      initialPrivacyConsent: testAdultPrivacyConsent,
      accountAuth: auth,
      cloudRepository: repository,
    )..isReady = true;
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
    await tester.scrollUntilVisible(find.text('Cloud account'), 200);
    await tester.tap(find.text('Cloud account'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountSignInDialog), findsOneWidget);
  }

  Future<void> enterCredentials(
    WidgetTester tester, {
    String email = 'person@example.com',
    String password = 'entered-password',
  }) async {
    await tester.enterText(find.byKey(emailKey), email);
    await tester.enterText(find.byKey(passwordKey), password);
  }

  testWidgets(
    'keeps the dialog open and blocks edits and dismissal while pending',
    (tester) async {
      await open(tester);
      await enterCredentials(tester);
      final submit = tester
          .widget<FilledButton>(find.byKey(submitKey))
          .onPressed!;
      submit();
      submit();
      await tester.pump();

      expect(auth.attempts, hasLength(1));
      expect(controller.isCloudAuthenticated, isFalse);
      expect(repository.userReads, 0);
      expect(repository.replaceUserCallCount, 0);
      expect(find.text('Signing in…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<TextFormField>(find.byKey(emailKey)).enabled,
        isFalse,
      );
      expect(
        tester.widget<TextFormField>(find.byKey(passwordKey)).enabled,
        isFalse,
      );
      expect(
        tester.widget<FilledButton>(find.byKey(submitKey)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(find.byKey(cancelKey)).onPressed,
        isNull,
      );

      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AccountSignInDialog), findsOneWidget);

      auth.reject('wrong-password');
      await tester.pumpAndSettle();
      expect(find.byType(AccountSignInDialog), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.widget<TextButton>(find.byKey(cancelKey)).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'rejected password stays inline and allows retry with retained email',
    (tester) async {
      await open(tester);
      await enterCredentials(tester, email: ' person@example.com ');
      await tester.tap(find.byKey(submitKey));
      await tester.pump();
      auth.reject('invalid-credential');
      await tester.pumpAndSettle();

      expect(controller.isCloudAuthenticated, isFalse);
      expect(repository.userReads, 0);
      expect(repository.replaceUserCallCount, 0);
      expect(find.byType(AccountSignInDialog), findsOneWidget);
      expect(
        find.text('The email or password is incorrect. Please try again.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextFormField>(find.byKey(emailKey)).controller!.text,
        ' person@example.com ',
      );
      expect(
        tester.widget<TextFormField>(find.byKey(passwordKey)).enabled,
        isTrue,
      );

      await tester.enterText(find.byKey(passwordKey), ' corrected-password ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(auth.attempts, hasLength(2));
      expect(auth.emails, ['person@example.com', 'person@example.com']);
      expect(auth.passwords.last, ' corrected-password ');
      expect(find.byKey(errorKey), findsNothing);
      expect(find.byType(AccountSignInDialog), findsOneWidget);

      auth.accept();
      await tester.pumpAndSettle();
      expect(controller.isCloudAuthenticated, isTrue);
      expect(find.byType(AccountSignInDialog), findsNothing);
      await tester.scrollUntilVisible(
        find.text('● Private cloud sync active'),
        -200,
      );
      expect(find.text('● Private cloud sync active'), findsOneWidget);
    },
  );

  testWidgets(
    'successful credentials do not close the dialog before account loading',
    (tester) async {
      repository.readGate = Completer<void>();
      await open(tester);
      await enterCredentials(tester);
      await tester.tap(find.byKey(submitKey));
      await tester.pump();
      auth.accept();
      await tester.pump();
      await tester.pump();
      expect(repository.userReads, 1);
      expect(find.byType(AccountSignInDialog), findsOneWidget);
      expect(find.text('Signing in…'), findsOneWidget);

      repository.readGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AccountSignInDialog), findsNothing);
      expect(controller.isCloudAuthenticated, isTrue);
    },
  );

  testWidgets(
    'requires a valid email and nonempty password before authentication',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(submitKey));
      await tester.pumpAndSettle();
      expect(find.text('Enter your email.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(auth.attempts, isEmpty);

      await enterCredentials(tester, email: 'invalid email');
      await tester.tap(find.byKey(submitKey));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(auth.attempts, isEmpty);

      await enterCredentials(tester, password: 'short');
      await tester.tap(find.byKey(submitKey));
      await tester.pump();
      expect(auth.attempts, hasLength(1));
      auth.reject('wrong-password');
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'network failure gives retry feedback without dismissing the dialog',
    (tester) async {
      await open(tester);
      await enterCredentials(tester);
      await tester.tap(find.byKey(submitKey));
      await tester.pump();
      auth.reject('network-request-failed');
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Unable to connect. Check your internet connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.byType(AccountSignInDialog), findsOneWidget);
      expect(controller.isCloudAuthenticated, isFalse);
      await tester.tap(find.byKey(cancelKey));
      await tester.pumpAndSettle();
      expect(find.byType(AccountSignInDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelling idle form does not authenticate or dispose fields too early',
    (tester) async {
      await open(tester);
      await enterCredentials(tester);
      await tester.tap(find.byKey(cancelKey));
      await tester.pumpAndSettle();
      expect(auth.attempts, isEmpty);
      expect(find.byType(AccountSignInDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late failure after widget removal does not update disposed state',
    (tester) async {
      await open(tester);
      await enterCredentials(tester);
      await tester.tap(find.byKey(submitKey));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      auth.reject('wrong-password');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.isCloudAuthenticated, isFalse);
    },
  );
}
