import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Version 0.31 Firestore rules gate outcome writes on both flags', () {
    final rules = File('firestore.rules').readAsStringSync();

    expect(rules, contains('match /outcomes/{outcomeId}'));
    expect(rules, contains('flags.outcomeCollection == true'));
    expect(rules, contains('flags.trainingRecordUse == true'));
    expect(
      rules,
      contains(
        'allow create, update: if isOwner(uid) && outcomeConsentGranted(uid)',
      ),
    );
    expect(rules, contains('allow read, delete: if isOwner(uid)'));
  });
}
