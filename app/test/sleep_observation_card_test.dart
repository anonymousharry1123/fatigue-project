import 'package:app/src/demo_data.dart';
import 'package:app/src/models.dart';
import 'package:app/src/privacy_consent.dart';
import 'package:app/src/widgets/sleep_observation_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'onboarding demo sleep is labeled synthetic, not imported Health data',
    (tester) async {
      final now = DateTime(2026, 10, 3, 12);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SleepObservationCard(
                signals: buildDemoSignals(now),
                now: now,
                ageBand: PrivacyAgeBand.adult,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Demo sleep'), findsOneWidget);
      expect(find.textContaining('Latest main sleep: 6.2 h'), findsOneWidget);
      expect(find.textContaining('Demo / synthetic example'), findsOneWidget);
      expect(find.textContaining('Apple Health estimate'), findsNothing);
      expect(
        find.textContaining('not imported or measured sleep'),
        findsOneWidget,
      );
      expect(find.textContaining('Displayed sleep total'), findsOneWidget);
      expect(find.textContaining('personal pattern'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mixed real and demo sleep cannot be confirmed as personal coverage',
    (tester) async {
      final now = DateTime(2026, 10, 3, 12);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SleepObservationCard(
                signals: [
                  SignalReading(
                    id: 'main',
                    type: SignalType.sleep,
                    value: 8,
                    timestamp: DateTime(2026, 10, 3, 7),
                  ),
                  SignalReading(
                    id: 'demo-nap',
                    type: SignalType.nap,
                    value: .5,
                    timestamp: DateTime(2026, 10, 2, 15),
                  ),
                ],
                now: now,
                ageBand: PrivacyAgeBand.age16to17,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Recorded and demo sleep'), findsOneWidget);
      expect(find.textContaining('Latest main sleep: 8.0 h'), findsOneWidget);
      final confirmation = tester.widget<CheckboxListTile>(
        find.byKey(const Key('sleep-coverage-confirmation')),
      );
      expect(confirmation.onChanged, isNull);
      expect(confirmation.value, isFalse);
      expect(
        find.textContaining('Comparison unavailable: demo/synthetic'),
        findsOneWidget,
      );
      expect(find.textContaining('within the teen range'), findsNothing);
    },
  );

  testWidgets('sleep fact, age guidance and explicit coverage stay separate', (
    tester,
  ) async {
    final now = DateTime(2026, 10, 3, 12);
    final rows = [
      SignalReading(
        id: 'main',
        type: SignalType.sleep,
        value: 8,
        timestamp: DateTime(2026, 10, 3, 7),
      ),
    ];
    Future<void> show({
      DateTime? at,
      PrivacyAgeBand age = PrivacyAgeBand.age16to17,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SleepObservationCard(
              signals: rows,
              now: at ?? now,
              ageBand: age,
            ),
          ),
        ),
      ),
    );
    await show();
    expect(find.textContaining('Latest main sleep: 8.0 h'), findsOneWidget);
    expect(find.textContaining('not an age recommendation'), findsOneWidget);
    expect(find.textContaining('Comparison unavailable until'), findsOneWidget);
    final confirmation = find.byKey(const Key('sleep-coverage-confirmation'));
    await tester.ensureVisible(confirmation);
    await tester.tap(confirmation);
    await tester.pump();
    expect(
      find.textContaining('within the teen range. This does not'),
      findsOneWidget,
    );
    await show(at: now.add(const Duration(minutes: 1)));
    expect(find.textContaining('Comparison unavailable until'), findsOneWidget);
    await show(age: PrivacyAgeBand.adult);
    expect(confirmation, findsNothing);
    expect(find.textContaining('AASM teen recommendation'), findsNothing);
    expect(find.textContaining('No age-specific comparison'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
