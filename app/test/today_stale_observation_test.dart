import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'privacy_test_support.dart';

void main() {
  testWidgets(
    'unavailable Today estimate dates the latest retained observation',
    (tester) async {
      final now = DateTime(2026, 10, 3, 10);
      final app =
          AppController(
              initialPrivacyConsent: testAdultPrivacyConsent,
              clock: () => now,
            )
            ..signals = [
              SignalReading(
                id: 'old-study',
                type: SignalType.study,
                value: 2,
                timestamp: DateTime(2026, 10, 1, 9),
              ),
              SignalReading(
                id: 'generated-context',
                type: SignalType.study,
                value: 2,
                timestamp: now,
                source: SignalSource.model,
              ),
            ]
            ..checkIns = [
              DailyCheckIn(
                id: 'old-check',
                timestamp: DateTime(2026, 10, 2, 8),
                energy: 8,
                mood: 8,
                stress: 2,
              ),
              DailyCheckIn(
                id: 'future-check',
                timestamp: now.add(const Duration(days: 1)),
                energy: 8,
                mood: 8,
                stress: 2,
              ),
            ];
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AppScope(
            controller: app,
            child: Scaffold(body: TodayScreen(onOpenProfile: () {})),
          ),
        ),
      );
      expect(find.text('Not enough information to estimate'), findsOneWidget);
      final notice = tester.widget<Text>(
        find.byKey(const Key('latest-observation-age')),
      );
      expect(notice.data, contains('2026-10-02'));
      expect(notice.data, contains('1 day'));
      expect(notice.data, contains('not a current measurement'));
      expect(find.text('Fresh'), findsNothing);
      expect(find.text('Moderate'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty Today view does not invent an observation date', (
    tester,
  ) async {
    final app = AppController(
      initialPrivacyConsent: testAdultPrivacyConsent,
      clock: () => DateTime(2026, 10, 3, 10),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          controller: app,
          child: Scaffold(body: TodayScreen(onOpenProfile: () {})),
        ),
      ),
    );
    expect(find.text('Not enough information to estimate'), findsOneWidget);
    expect(find.byKey(const Key('latest-observation-age')), findsNothing);
    expect(find.text('Fresh'), findsNothing);
    expect(find.text('Moderate'), findsNothing);
  });
}
