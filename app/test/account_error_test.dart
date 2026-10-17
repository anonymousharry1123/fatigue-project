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

  group('passwordResetErrorMessage', () {
    test('invalid, expired, and unknown-account codes share one message', () {
      for (final code in [
        'expired-action-code',
        'invalid-action-code',
        'user-not-found',
      ]) {
        expect(
          passwordResetErrorMessage(FirebaseAuthException(code: code)),
          'This reset code is invalid or has expired. Request a new email.',
          reason: code,
        );
      }
    });

    test('reauthentication failures report an incorrect current password', () {
      for (final code in [
        'requires-recent-login',
        'wrong-password',
        'invalid-credential',
        'INVALID_LOGIN_CREDENTIALS',
        'invalid-login-credentials',
      ]) {
        expect(
          passwordResetErrorMessage(
            FirebaseAuthException(code: code),
            changingPassword: true,
          ),
          'Current password is incorrect.',
          reason: code,
        );
      }
    });

    test('shared account failures reuse the account error copy', () {
      for (final code in [
        'weak-password',
        'network-request-failed',
        'too-many-requests',
        'invalid-email',
        'user-disabled',
        'invalid-api-key',
      ]) {
        final error = FirebaseAuthException(code: code);
        expect(
          passwordResetErrorMessage(error),
          accountErrorMessage(error),
          reason: code,
        );
      }
      expect(
        passwordResetErrorMessage(FirebaseAuthException(code: 'weak-password')),
        'Choose a stronger password and try again.',
      );
      expect(
        passwordResetErrorMessage(
          FirebaseAuthException(code: 'network-request-failed'),
        ),
        contains('internet connection'),
      );
      expect(
        passwordResetErrorMessage(
          FirebaseAuthException(code: 'too-many-requests'),
        ),
        contains('Too many attempts'),
      );
    });

    test('unknown failures use generic copy without leaking details', () {
      for (final error in [
        StateError('secret-password private@example.com'),
        FirebaseAuthException(code: 'unknown', message: 'secret-password'),
      ]) {
        final reset = passwordResetErrorMessage(error);
        final change = passwordResetErrorMessage(error, changingPassword: true);
        expect(reset, 'The password could not be reset. Please try again.');
        expect(change, 'The password could not be changed. Please try again.');
        for (final message in [reset, change]) {
          expect(message, isNot(contains('secret-password')));
          expect(message, isNot(contains('private@example.com')));
        }
      }
    });
  });
}
