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
    expect(rules, contains('allow get, list, delete: if isOwner(uid)'));
  });

  test(
    'Version 0.32 model metadata is owner-only and consent-gated when changed',
    () {
      final rules = File('firestore.rules').readAsStringSync();
      expect(rules, contains('allow create: if isOwner(uid)'));
      expect(rules, contains('allow update: if isOwner(uid)'));
      expect(
        rules,
        contains('request.resource.data.diff(resource.data).affectedKeys()'),
      );
      expect(rules, contains(".hasAny(['personalizedEnergyModel'])"));
      expect(
        rules,
        contains(
          "!request.resource.data.keys().hasAny(['personalizedEnergyModel'])",
        ),
      );
      expect(
        rules,
        contains('validEnergyModelMetadata(request.resource.data)'),
      );
      expect(rules, contains('data.consentFlags.outcomeCollection == true'));
      expect(rules, contains('data.consentFlags.trainingRecordUse == true'));
      expect(rules, contains('allow get, list, delete: if isOwner(uid)'));
      expect(rules, contains('&& ownerDataWritable(uid)'));
      expect(rules, contains('allow read, write: if false'));
    },
  );

  test(
    'Version 0.32 rules constrain compact metadata and accepted error bounds',
    () {
      final rules = File('firestore.rules').readAsStringSync();
      expect(rules, contains('model.keys().hasAll(fields)'));
      expect(rules, contains('model.keys().hasOnly(fields)'));
      expect(
        rules,
        contains('model.modelVersion is int && model.modelVersion == 1'),
      );
      expect(
        rules,
        contains('model.schemaVersion is int && model.schemaVersion == 1'),
      );
      expect(
        rules,
        contains('model.labelCount >= 14 && model.labelCount <= 100'),
      );
      expect(
        rules,
        contains('model.holdoutMae <= model.deterministicMae * 0.95'),
      );
      expect(rules, contains('coverage.keys().hasOnly(features)'));
      expect(rules, contains('model.window.timezone.size() <= 100'));
      for (final feature in [
        'sleepDeviation',
        'movement',
        'hydration',
        'studyScreenLoad',
        'caffeine',
        'mood',
        'stress',
        'recoveryDeviation',
      ]) {
        expect(rules, contains('modelFraction(coverage.$feature)'));
      }
      expect(rules, isNot(contains('match /trainingExamples/')));
      expect(rules, isNot(contains('match /models/')));
    },
  );

  test('Version 0.34 denies listing users and arbitrary child writes', () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules, contains('allow get: if isOwner(uid)'));
    expect(rules, contains('allow list: if false'));
    expect(rules, isNot(contains("collection != 'outcomes'")));
    expect(rules, contains("collection in ['signals', 'checkIns'"));
    expect(rules, contains('getAfter('));
    expect(
      rules,
      contains("request.auth.token.get('guardianConsentVerified', false)"),
    );
    expect(
      rules,
      contains("request.auth.token.get('guardianConsentPolicyVersion', 0)"),
    );
    expect(
      rules,
      contains("request.auth.token.get('syntheticLabAdmin', false)"),
    );
    expect(rules, isNot(contains('if isSignedIn()')));
    expect(rules, contains('&& recentAuthentication()'));
    expect(rules, contains('!deletionPending(resource.data)'));
  });
}
