import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/demo_data.dart';
import 'package:app/src/models.dart';
import 'package:app/src/today_dashboard_logic.dart';
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
    expect(find.textContaining(', Maya'), findsOneWidget);

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
    expect(find.text('Daily Score Models'), findsOneWidget);

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
    await tester.scrollUntilVisible(find.text('Daily check-in'), 200);
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

    await tester.scrollUntilVisible(find.text('Reaction test'), 200);
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

  testWidgets('Version 0.11 clearly presents an explainable estimate', (
    tester,
  ) async {
    final now = DateTime.now();
    final recordedAt = now;
    final controller = AppController()
      ..isReady = true
      ..onboardingComplete = true
      ..signals = [
        for (final entry in const {
          SignalType.sleep: 8.0,
          SignalType.hydration: 2.2,
          SignalType.study: 3.0,
          SignalType.exercise: .75,
          SignalType.screenTime: 2.5,
        }.entries)
          SignalReading(
            id: entry.key.name,
            type: entry.key,
            value: entry.value,
            timestamp: recordedAt,
          ),
        SignalReading(
          id: 'reaction',
          type: SignalType.reactionTime,
          value: 270,
          timestamp: recordedAt,
        ),
      ]
      ..checkIns = [
        DailyCheckIn(
          id: 'today',
          timestamp: recordedAt,
          energy: 7,
          mood: 8,
          stress: 3,
        ),
      ];
    await controller.refreshEnergyScore();

    await tester.pumpWidget(TonyoApp(controller: controller));

    expect(find.text('ESTIMATED ENERGY SCORE'), findsOneWidget);
    expect(find.textContaining('7/7 inputs'), findsOneWidget);
    expect(
      find.text(TodayDashboardLogic.statusFor(controller.score.energy).label),
      findsOneWidget,
    );
    expect(find.byKey(const Key('recent-signal-grid')), findsOneWidget);
    expect(find.text('Today’s signals'), findsOneWidget);
    expect(find.text('8.0 hr'), findsOneWidget);
    expect(find.text('2.2 L'), findsOneWidget);
    expect(find.text('ESTIMATED COGNITIVE SCORE'), findsOneWidget);
    expect(find.textContaining('5/5 cognitive inputs'), findsOneWidget);
    expect(find.textContaining('First Cognitive Score'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Today’s score factors'), 250);
    expect(find.text('Today’s score factors'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('energy-score-explanation')),
      250,
    );
    expect(find.textContaining('This wellness estimate'), findsOneWidget);
    expect(find.text('WHAT SHAPED THIS ESTIMATE'), findsOneWidget);
  });

  testWidgets('Version 0.14 presents ranked drivers and confidence evidence', (
    tester,
  ) async {
    final now = DateTime.now();
    final controller = AppController()
      ..isReady = true
      ..onboardingComplete = true
      ..signals = [
        for (final entry in const {
          SignalType.sleep: 5.0,
          SignalType.hydration: 3.0,
          SignalType.study: 7.0,
          SignalType.exercise: 1.0,
          SignalType.screenTime: 8.0,
          SignalType.reactionTime: 245.0,
        }.entries)
          SignalReading(
            id: entry.key.name,
            type: entry.key,
            value: entry.value,
            timestamp: now,
            source: SignalSource.healthKit,
          ),
      ]
      ..checkIns = [
        DailyCheckIn(
          id: 'today',
          timestamp: now,
          energy: 7,
          mood: 9,
          stress: 8,
        ),
      ];
    await controller.refreshEnergyScore();
    await tester.pumpWidget(TonyoApp(controller: controller));

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Forecast'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('Insights'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Daily Score Models'), findsOneWidget);
    expect(find.textContaining('100% coverage'), findsWidgets);
    expect(find.textContaining('% fresh'), findsWidgets);
    await tester.scrollUntilVisible(find.text('SUPPORTING TODAY'), 250);
    expect(find.text('SUPPORTING TODAY'), findsWidgets);
    expect(find.text('REDUCING TODAY'), findsWidgets);
    expect(find.textContaining('recovery range'), findsWidgets);
  });

  testWidgets('Version 0.16 presents uncertainty and forecast provenance', (
    tester,
  ) async {
    await tester.pumpWidget(TonyoApp(controller: readyController()));

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Forecast'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Limited confidence'), findsOneWidget);
    expect(find.byTooltip('Refresh forecast'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Calculated on this device'),
      250,
    );
    expect(find.textContaining('Calculated on this device'), findsOneWidget);
    expect(find.textContaining('fixture data'), findsNothing);
  });

  testWidgets('Version 0.17 presents three key windows with linked evidence', (
    tester,
  ) async {
    final now = DateTime.now().subtract(const Duration(minutes: 5));
    final controller = AppController()
      ..isReady = true
      ..onboardingComplete = true
      ..signals = [
        for (final entry in const {
          SignalType.sleep: 8.0,
          SignalType.bedtime: 23.0,
          SignalType.hydration: 2.4,
          SignalType.study: 4.0,
          SignalType.exercise: .75,
        }.entries)
          SignalReading(
            id: '${entry.key.name}-live',
            type: entry.key,
            value: entry.value,
            timestamp: now,
          ),
      ]
      ..checkIns = [
        DailyCheckIn(
          id: 'check-in-live',
          timestamp: now,
          energy: 7,
          mood: 8,
          stress: 4,
        ),
      ];
    await tester.pumpWidget(TonyoApp(controller: controller));
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Forecast'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Key windows'), 250);
    expect(find.text('Key windows'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('forecast-window-peak')),
      250,
    );
    expect(find.text('Peak focus'), findsOneWidget);
    expect(find.text('LINKED EVIDENCE'), findsWidgets);
    expect(
      find.byKey(const Key('forecast-evidence-signal-sleep-live')),
      findsWidgets,
    );
    await tester.scrollUntilVisible(find.text('Predicted crash'), 250);
    expect(find.text('Predicted crash'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Recovery window'), 250);
    expect(find.text('Recovery window'), findsOneWidget);
    expect(find.textContaining('Linked signal'), findsWidgets);
    expect(find.textContaining('Linked check-in'), findsWidgets);
  });

  testWidgets('Version 0.16 Week view uses calculated daily summaries', (
    tester,
  ) async {
    await tester.pumpWidget(TonyoApp(controller: readyController()));
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Forecast'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('Week'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('7-DAY OUTLOOK'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Daily summaries'), 250);
    expect(find.text('Daily summaries'), findsOneWidget);
    expect(find.textContaining('Peak '), findsWidgets);
  });

  testWidgets('Version 0.16 handles an empty authenticated forecast range', (
    tester,
  ) async {
    final controller =
        AppController(
            accountAuth: MemoryAccountAuth(
              session: const AccountSession(
                uid: 'empty-forecast',
                email: 'empty@example.com',
              ),
            ),
            cloudRepository: MemoryCloudRepository(
              signedInUid: 'empty-forecast',
            ),
          )
          ..isReady = true
          ..onboardingComplete = true;
    await tester.pumpWidget(TonyoApp(controller: controller));
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Forecast'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No forecast available'), findsOneWidget);
    expect(find.text('Build forecast'), findsOneWidget);
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

  testWidgets(
    'Version 0.10 history groups days and edits/deletes manual logs',
    (tester) async {
      final controller = readyController();
      await controller.saveActivityLog(
        hydrationLiters: 2.5,
        timestamp: DateTime(2026, 7, 21, 18),
      );
      final activityId = controller.activityLogs.single.id;

      await tester.pumpWidget(TonyoApp(controller: controller));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily history'));
      await tester.pumpAndSettle();

      expect(find.text('Your daily record'), findsOneWidget);
      expect(find.text('Complete'), findsWidgets);
      expect(find.text('Activity'), findsWidgets);
      expect(find.text('Sleep'), findsWidgets);
      expect(find.text('Check-in'), findsWidgets);
      expect(find.text('Reaction'), findsWidgets);

      final activityItem = find.byKey(Key('history-item-$activityId'));
      final editActivity = find.descendant(
        of: activityItem,
        matching: find.byTooltip('Edit Activity log'),
      );
      await tester.tap(editActivity);
      await tester.pumpAndSettle();
      expect(find.text('Edit activity'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('hydration-field')), '3.5');
      await tester.ensureVisible(find.text('Update activity'));
      await tester.tap(find.text('Update activity'));
      await tester.pumpAndSettle();
      expect(controller.activityLogs.single.hydrationLiters, 3.5);
      expect(
        controller.activityLogs.single.timestamp,
        DateTime(2026, 7, 21, 18),
      );
      expect(find.text('Your daily record'), findsOneWidget);

      final updatedItem = find.byKey(Key('history-item-$activityId'));
      final deleteActivity = find.descendant(
        of: updatedItem,
        matching: find.byTooltip('Delete Activity log'),
      );
      await tester.tap(deleteActivity);
      await tester.pumpAndSettle();
      expect(find.text('Delete history entry?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(controller.activityLogs, isEmpty);
    },
  );

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
