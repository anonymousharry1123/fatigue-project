import 'package:app/src/account_error.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('credential errors do not disclose whether an email exists', () {
    final messages = [
      'invalid-credential',
      'INVALID_LOGIN_CREDENTIALS',
      'wrong-password',
      'user-not-found',
      'invalid-login-credentials',
    ].map((code) => accountErrorMessage(FirebaseAuthException(code: code)));
    expect(messages.toSet(), hasLength(1));
    expect(messages.first, contains('email or password is incorrect'));
  });

  test(
    'network and configuration failures are not described as bad passwords',
    () {
      expect(
        accountErrorMessage(
          FirebaseAuthException(code: 'network-request-failed'),
        ),
        contains('internet connection'),
      );
      expect(
        accountErrorMessage(FirebaseAuthException(code: 'invalid-api-key')),
        contains('Firebase configuration'),
      );
    },
  );

  test('unknown exceptions do not expose raw credentials or SDK messages', () {
    for (final error in [
      StateError('secret-password private@example.com'),
      FirebaseAuthException(code: 'unknown', message: 'secret-password'),
    ]) {
      expect(accountErrorMessage(error), isNot(contains('secret-password')));
      expect(
        accountErrorMessage(error),
        isNot(contains('private@example.com')),
      );
      expect(
        accountErrorMessage(error, signingIn: false),
        contains('Account setup'),
      );
    }
  });
}
