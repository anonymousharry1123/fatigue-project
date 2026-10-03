import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/screens/insights_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'privacy_test_support.dart';

void main() {
  testWidgets(
    'Insights discloses recomputations and hides unavailable estimates',
    (tester) async {
      final controller = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AppScope(
            controller: controller,
            child: const Scaffold(body: InsightsScreen()),
          ),
        ),
      );

      final basis = tester.widget<Text>(
        find.byKey(const Key('insights-calculation-basis')),
      );
      expect(basis.data, contains('current deterministic rules'));
      expect(basis.data, contains(FatigueEngine.energyModelVersion));
      expect(basis.data, contains('No learned personalization'));
      expect(basis.data, contains('Missing history'));

      await tester.scrollUntilVisible(
        find.text('Energy data quality'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Not enough information to estimate'), findsWidgets);
      expect(find.text('Unavailable'), findsWidgets);
      expect(find.text('60'), findsNothing);
      expect(find.text('65'), findsNothing);
      expect(find.textContaining('% confidence'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
