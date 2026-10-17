import 'package:app/src/password_reset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const actionUrl =
      'https://tonyo-app.firebaseapp.com/__/auth/action'
      '?mode=resetPassword&oobCode=AbC-123_xyz&apiKey=key&lang=en';

  group('parsePasswordResetCode', () {
    test('returns a raw code unchanged after trimming', () {
      expect(parsePasswordResetCode('AbC-123_xyz'), 'AbC-123_xyz');
      expect(parsePasswordResetCode('  AbC-123_xyz \n'), 'AbC-123_xyz');
    });

    test('reads oobCode from a full Firebase action URL', () {
      expect(parsePasswordResetCode(actionUrl), 'AbC-123_xyz');
      expect(parsePasswordResetCode(' $actionUrl '), 'AbC-123_xyz');
    });

    test('accepts an action URL pasted without a scheme', () {
      expect(
        parsePasswordResetCode(
          'tonyo-app.firebaseapp.com/__/auth/action'
          '?mode=resetPassword&oobCode=NoScheme1',
        ),
        'NoScheme1',
      );
    });

    test('accepts an action URL without a mode parameter', () {
      expect(
        parsePasswordResetCode('https://example.com/reset?oobCode=Plain42'),
        'Plain42',
      );
    });

    test('unwraps a URL-encoded link parameter', () {
      final wrapped =
          'https://tonyo.page.link/?link=${Uri.encodeComponent(actionUrl)}'
          '&apn=com.example.tonyo';
      expect(parsePasswordResetCode(wrapped), 'AbC-123_xyz');
    });

    test('unwraps a continueUrl parameter', () {
      final wrapped =
          'https://example.com/landing'
          '?continueUrl=${Uri.encodeComponent(actionUrl)}';
      expect(parsePasswordResetCode(wrapped), 'AbC-123_xyz');
    });

    test('unwraps a link nested two levels deep', () {
      final middle =
          'https://tonyo.page.link/?link=${Uri.encodeComponent(actionUrl)}';
      final outer =
          'https://mail.example.com/redirect'
          '?continueUrl=${Uri.encodeComponent(middle)}';
      expect(parsePasswordResetCode(outer), 'AbC-123_xyz');
    });

    test('stops unwrapping after two nested levels', () {
      var link = actionUrl;
      for (var i = 0; i < 3; i++) {
        link = 'https://example.com/r$i?link=${Uri.encodeComponent(link)}';
      }
      expect(parsePasswordResetCode(link), isNull);
    });

    test('rejects links for a different action mode', () {
      expect(
        parsePasswordResetCode(
          'https://tonyo-app.firebaseapp.com/__/auth/action'
          '?mode=verifyEmail&oobCode=AbC-123_xyz',
        ),
        isNull,
      );
      final wrapped =
          'https://tonyo.page.link/?link=${Uri.encodeComponent('https://tonyo-app.firebaseapp.com/__/auth/action?mode=recoverEmail&oobCode=Other')}';
      expect(parsePasswordResetCode(wrapped), isNull);
    });

    test('returns null for empty or whitespace input', () {
      expect(parsePasswordResetCode(''), isNull);
      expect(parsePasswordResetCode('   '), isNull);
      expect(parsePasswordResetCode('\n\t'), isNull);
    });

    test('returns null when a code contains inner whitespace', () {
      expect(parsePasswordResetCode('abc def'), isNull);
      expect(parsePasswordResetCode('abc\ndef'), isNull);
    });

    test('returns null for URLs without a reset code', () {
      expect(parsePasswordResetCode('https://example.com/reset'), isNull);
      expect(
        parsePasswordResetCode(
          'https://example.com/reset?mode=resetPassword&oobCode=',
        ),
        isNull,
      );
      expect(
        parsePasswordResetCode('https://example.com/?link=not-a-url'),
        isNull,
      );
    });

    test('returns null when query encoding is not valid UTF-8', () {
      expect(
        parsePasswordResetCode('https://example.com/?oobCode=%E0%A4'),
        isNull,
      );
    });
  });

  group('validateNewPassword', () {
    test('requires a password', () {
      expect(validateNewPassword(null), 'Enter a new password.');
      expect(validateNewPassword(''), 'Enter a new password.');
    });

    test('requires at least 8 characters', () {
      expect(validateNewPassword('short'), 'Use at least 8 characters');
      expect(validateNewPassword('1234567'), 'Use at least 8 characters');
    });

    test('accepts passwords of 8 or more characters', () {
      expect(validateNewPassword('12345678'), isNull);
      expect(validateNewPassword('a much longer passphrase'), isNull);
    });
  });
}
