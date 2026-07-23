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

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Forecast'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Energy Forecast'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('Insights'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your Fatigue Model'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Add & Explore'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Coach'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Today’s plan'), findsOneWidget);

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

    await tester.scrollUntilVisible(find.text('AI Coach'), 250);
    await tester.tap(find.text('AI Coach'));
    await tester.pumpAndSettle();
    expect(find.text('Today’s plan'), findsOneWidget);
  });

  testWidgets('Version 0.6 activity log validates and saves manual data', (
    tester,
  ) async {
    final controller = readyController();
    await tester.pumpWidget(TonyoApp(controller: controller));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity log'));
    await tester.pumpAndSettle();

    expect(find.text('Log today’s activity'), findsOneWidget);
    expect(find.text('None'), findsNothing);
    await tester.enterText(find.byKey(const Key('hydration-field')), '11');
    await tester.ensureVisible(find.text('Save activity'));
    await tester.tap(find.text('Save activity'));
    await tester.pump();
    expect(find.text('Enter 0–10 liters.'), findsOneWidget);
    expect(controller.activityLogs, isEmpty);

    await tester.enterText(find.byKey(const Key('hydration-field')), '2.5');
    await tester.ensureVisible(find.text('Save activity'));
    await tester.tap(find.text('Save activity'));
    await tester.pumpAndSettle();
    expect(find.text('Activity log saved.'), findsOneWidget);
    expect(controller.activityLogs, hasLength(1));
    expect(controller.activityLogs.single.hydrationLiters, 2.5);
    expect(controller.activityLogs.single.studyHours, 0);
    expect(controller.activityLogs.single.exerciseHours, 0);
    expect(controller.activityLogs.single.screenTimeHours, 0);
    expect(
      controller.signals.where(
        (signal) => signal.groupId == controller.activityLogs.single.id,
      ),
      hasLength(4),
    );
    expect(find.text('Last 7 days by category'), findsOneWidget);
    expect(find.text('Hydration'), findsWidgets);
  });

  testWidgets('Version 0.7 sleep log shows duration and recent entries', (
    tester,
  ) async {
    final controller = readyController();
    await tester.pumpWidget(TonyoApp(controller: controller));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sleep log'));
    await tester.pumpAndSettle();

    expect(find.text('How did you sleep?'), findsOneWidget);
    expect(find.text('Calculated duration: 8h 00m'), findsOneWidget);
    await tester.tap(find.text('Save sleep'));
    await tester.pumpAndSettle();
    expect(find.text('Sleep log saved.'), findsOneWidget);
    expect(controller.sleepLogs, hasLength(1));
    await tester.scrollUntilVisible(find.textContaining('quality 3/5'), 250);
    expect(find.textContaining('quality 3/5'), findsOneWidget);
  });

  testWidgets('new users see the welcome screen', (tester) async {
    final controller = AppController()..isReady = true;
    await tester.pumpWidget(TonyoApp(controller: controller));
    expect(find.text('Tonyo'), findsOneWidget);
    expect(find.text('Create my account'), findsOneWidget);
  });

  testWidgets('welcome leads to account creation before profile setup', (
    tester,
  ) async {
    final controller = AppController()..isReady = true;
    await tester.pumpWidget(TonyoApp(controller: controller));

    await tester.tap(find.text('Create my account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'maya@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'tonyo-pass',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'tonyo-pass',
    );
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Continue to my profile'));
    await tester.pumpAndSettle();

    expect(find.text('Make it yours'), findsOneWidget);
  });

  testWidgets('confirm password can be edited and revealed independently', (
    tester,
  ) async {
    final controller = AppController()..isReady = true;
    await tester.pumpWidget(TonyoApp(controller: controller));
    await tester.tap(find.text('Create my account'));
    await tester.pumpAndSettle();

    final passwordFinder = find.byKey(const Key('password-field'));
    final confirmFinder = find.byKey(const Key('confirm-password-field'));
    await tester.enterText(passwordFinder, 'first-password');
    await tester.enterText(confirmFinder, 'first-password');
    await tester.enterText(confirmFinder, 'changed-password');

    expect(
      tester.widget<TextFormField>(confirmFinder).controller!.text,
      'changed-password',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('password-visibility')),
        matching: find.byIcon(Icons.visibility_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('confirm-password-visibility')),
        matching: find.byIcon(Icons.visibility_outlined),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('confirm-password-visibility')));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('password-visibility')),
        matching: find.byIcon(Icons.visibility_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('confirm-password-visibility')),
        matching: find.byIcon(Icons.visibility_off_outlined),
      ),
      findsOneWidget,
    );
  });
}
