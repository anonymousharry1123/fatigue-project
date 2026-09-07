import 'package:app/src/privacy_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Existing feature tests explicitly opt in their fictional adult test account.
/// Production defaults remain unacknowledged, including legacy accounts.
final testAdultPrivacyConsent = PrivacyConsent(
  ageBand: PrivacyAgeBand.adult,
  region: PrivacyRegion.us,
  acceptedAt: DateTime.utc(2020),
);

Future<void> acknowledgeAdultPrivacy(WidgetTester tester) async {
  final age = find.byKey(const Key('privacy-age-band'));
  await tester.ensureVisible(age);
  await tester.pumpAndSettle();
  await tester.tap(age);
  await tester.pumpAndSettle();
  await tester.tap(find.text(PrivacyAgeBand.adult.label).last);
  await tester.pumpAndSettle();
  final region = find.byKey(const Key('privacy-region'));
  await tester.ensureVisible(region);
  await tester.pumpAndSettle();
  await tester.tap(region);
  await tester.pumpAndSettle();
  await tester.tap(find.text(PrivacyRegion.us.label).last);
  await tester.pumpAndSettle();
  final ack = find.byKey(const Key('privacy-acknowledgement'));
  final checkbox = find.descendant(of: ack, matching: find.byType(Checkbox));
  await tester.ensureVisible(checkbox);
  await tester.pumpAndSettle();
  await tester.tap(checkbox.hitTestable());
  await tester.pump();
  expect(tester.widget<CheckboxListTile>(ack).value, isTrue);
}

Future<void> finishOnboardingPrivacyStep(WidgetTester tester) async {
  await acknowledgeAdultPrivacy(tester);
  await tester.tap(find.text('Continue with these choices'));
  await tester.pumpAndSettle();
}
