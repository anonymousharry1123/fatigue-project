import 'package:app/src/privacy_consent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime.utc(2026, 9, 7, 12);

  test('only explicit versioned acknowledgements round trip', () {
    final receipt = PrivacyConsent(
      ageBand: PrivacyAgeBand.adult,
      region: PrivacyRegion.us,
      acceptedAt: at,
    );
    final restored = PrivacyConsent.tryParse(receipt.toJson())!;
    expect(restored.sameIdentity(receipt), isTrue);
    expect(restored.acceptedAt, at);
    expect(restored.validAt(at), isTrue);
    expect(restored.guardianRequired, isFalse);
    expect(PrivacyConsent.tryParse(receipt.toCloud())!.acceptedAt, at);
    expect(receipt.toJson().keys, isNot(contains('dateOfBirth')));
    expect(receipt.toJson().keys, isNot(contains('guardianVerified')));
  });

  test('all minor age bands fail closed without separate server authority', () {
    for (final age in PrivacyAgeBand.values.where(
      (age) => age != PrivacyAgeBand.adult,
    )) {
      for (final region in PrivacyRegion.values) {
        final receipt = PrivacyConsent(
          ageBand: age,
          region: region,
          acceptedAt: at,
        );
        expect(receipt.guardianRequired, isTrue);
      }
    }
  });

  test(
    'missing, malformed and unsupported historical flags are not consent',
    () {
      final valid = PrivacyConsent(
        ageBand: PrivacyAgeBand.adult,
        region: PrivacyRegion.us,
        acceptedAt: at,
      ).toJson();
      for (final raw in <Object?>[
        null,
        {},
        true,
        {'wellnessOnlyAcknowledged': true},
        {...valid, 'policyVersion': 0},
        {...valid, 'policyVersion': 1.0},
        {...valid, 'wellnessAcknowledged': false},
        {...valid, 'ageBand': '16–18'},
        {...valid, 'region': 'auto'},
        {...valid, 'acceptedAt': '2026-09-07T12:00:00'},
        {...valid, 'acceptedAt': null},
        {...valid, 'guardianVerified': true},
      ]) {
        expect(PrivacyConsent.tryParse(raw), isNull);
      }
    },
  );

  test('future timestamps do not activate a receipt', () {
    final receipt = PrivacyConsent(
      ageBand: PrivacyAgeBand.adult,
      region: PrivacyRegion.us,
      acceptedAt: at.add(const Duration(days: 1)),
    );
    expect(receipt.validAt(at), isFalse);
  });
}
