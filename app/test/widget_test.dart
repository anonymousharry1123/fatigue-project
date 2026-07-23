import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/demo_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppController readyController() {
    final controller = AppController()
      ..isReady = true
      ..onboardingComplete = true
      ..signals = buildDemoSignals(DateTime(2026, 7, 21, 9))
      ..checkIns = buildDemoCheckIns(DateTime(2026, 7, 21, 9));
    return controller;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shell exposes all Version 0.5 destinations', (tester) async {
    await tester.pumpWidget(TonyoApp(controller: readyController()));
    expect(find.textContaining('Morning,'), findsOneWidget);

    await tester.tap(find.text('Forecast'));
    await tester.pumpAndSettle();
    expect(find.text('Energy Forecast'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Add & Explore'), findsOneWidget);

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();
    expect(find.text('Your Fatigue Model'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Connected data sources'), findsOneWidget);
  });

  testWidgets('additional designs open from Add and Today', (tester) async {
    await tester.pumpWidget(TonyoApp(controller: readyController()));

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily check-in'));
    await tester.pumpAndSettle();
    expect(find.text('How are you feeling?'), findsOneWidget);
    expect(find.text('Energy'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Stress'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Mood'), findsOneWidget);
    expect(find.text('Stress'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Check-in history'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Check-in history'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reaction test'));
    await tester.pumpAndSettle();
    expect(find.text('Reaction Test'), findsOneWidget);
    expect(find.text('Personal baseline'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('AI Coach'));
    await tester.pumpAndSettle();
    expect(find.text('Today’s plan'), findsOneWidget);
  });

  testWidgets('new users see the welcome screen', (tester) async {
    final controller = AppController()..isReady = true;
    await tester.pumpWidget(TonyoApp(controller: controller));
    expect(find.text('Tonyo'), findsOneWidget);
    expect(find.text('Build my fatigue model'), findsOneWidget);
  });
}
