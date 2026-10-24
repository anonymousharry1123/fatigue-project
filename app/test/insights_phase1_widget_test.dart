import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/insights_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'privacy_test_support.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Insights shows accessible preferred sleep stages at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final now = DateTime(2026, 10, 24, 20);
        final controller = AppController(
          initialPrivacyConsent: testAdultPrivacyConsent,
          clock: () => now,
        );
        addTearDown(controller.dispose);
        controller.signals = [
          for (final entry in {
            SignalType.sleep: 8.0,
            SignalType.sleepCore: 4.0,
            SignalType.sleepDeep: 1.5,
            SignalType.sleepRem: 2.5,
            SignalType.sleepAwake: .5,
          }.entries)
            SignalReading(
              id: 'healthkit-sleep-night-${entry.key.name}',
              type: entry.key,
              value: entry.value,
              timestamp: DateTime(2026, 10, 24, 8),
              source: SignalSource.healthKit,
              groupId: 'healthkit-sleep-night',
            ),
          SignalReading(
            id: 'manual-night',
            type: SignalType.sleep,
            value: 8,
            timestamp: DateTime(2026, 10, 23, 8),
            groupId: 'sleep-manual-night',
          ),
        ];
        await controller.refreshInsights();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: AppScope(
              controller: controller,
              child: const Scaffold(body: InsightsScreen()),
            ),
          ),
        );

        await tester.scrollUntilVisible(
          find.text('Avg deep sleep'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Avg deep sleep'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final stageRow = find.byKey(
          Key(
            'insights-sleep-stage-${DateTime(2026, 10, 24).toIso8601String()}',
          ),
        );
        await tester.scrollUntilVisible(
          stageRow,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('insights-sleep-stages')), findsOneWidget);
        final semantics = tester.widget<Semantics>(stageRow).properties.label;
        expect(semantics, contains('Core: 4.0 hr'));
        expect(semantics, contains('Deep: 1.5 hr'));
        expect(semantics, contains('REM: 2.5 hr'));
        expect(semantics, contains('Awake: 0.5 hr'));
        expect(
          find.byKey(
            Key(
              'insights-sleep-stage-${DateTime(2026, 10, 23).toIso8601String()}',
            ),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

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
      expect(find.byKey(const Key('insights-sleep-stages')), findsNothing);

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
