import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/demo_data.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/models.dart';
import 'package:app/src/notification_service.dart';
import 'package:app/src/today_dashboard_logic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppController readyController({
    NotificationService? notificationService,
    HealthService? healthService,
  }) {
    final controller =
        AppController(
            notificationService: notificationService,
            healthService: healthService,
          )
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
    await tester.scrollUntilVisible(find.text('Daily Score Models'), 250);
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

  testWidgets('Version 0.20 exposes explicit forecast alert controls', (
    tester,
  ) async {
    final notifications = _WidgetNotificationService();
    final controller = readyController(notificationService: notifications);
    await tester.pumpWidget(TonyoApp(controller: controller));

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Forecast alerts'), 200);
    await tester.tap(find.text('Forecast alerts'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notification-master-switch')), findsOneWidget);
    expect(find.textContaining('Permission is requested only'), findsOneWidget);
    expect(find.textContaining('never presents a diagnosis'), findsOneWidget);
    expect(controller.notificationsEnabled, isFalse);

    await tester.tap(find.byKey(const Key('notification-master-switch')));
    await tester.pumpAndSettle();

    expect(notifications.permissionRequests, 1);
    expect(controller.notificationsEnabled, isTrue);
    expect(find.byKey(const Key('notification-crash-switch')), findsOneWidget);

    await tester.tap(find.byKey(const Key('notification-crash-switch')));
    await tester.pumpAndSettle();
    expect(controller.crashNotificationsEnabled, isFalse);
  });

  testWidgets('Version 0.21 presents private calculated weekly insights', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final controller = AppController()
      ..isReady = true
      ..onboardingComplete = true
      ..signals = [
        for (var index = 0; index < 7; index++) ...[
          SignalReading(
            id: 'insight-sleep-$index',
            type: SignalType.sleep,
            value: 6.5 + index * .2,
            timestamp: today.subtract(Duration(days: 6 - index)),
          ),
          SignalReading(
            id: 'insight-study-$index',
            type: SignalType.study,
            value: 1 + index * .5,
            timestamp: today.subtract(Duration(days: 6 - index)),
          ),
          SignalReading(
            id: 'insight-exercise-$index',
            type: SignalType.exercise,
            value: .4 + index * .1,
            timestamp: today.subtract(Duration(days: 6 - index)),
          ),
        ],
      ];
    await controller.refreshInsights();
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

    expect(find.text('7-day overview'), findsOneWidget);
    expect(find.text('Avg sleep'), findsOneWidget);
    expect(find.textContaining('no cohort comparisons'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('insights-daily-trend')),
      220,
    );
    expect(find.byKey(const Key('insights-daily-trend')), findsOneWidget);
    await tester.tap(find.byKey(const Key('insight-metric-sleep')));
    await tester.pump();
    expect(find.textContaining('Latest logged sleep duration'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('insights-associations')),
      220,
    );
    expect(
      find.textContaining('do not establish that one behavior caused'),
      findsOneWidget,
    );
  });

  testWidgets('Version 0.22 explains and manages Apple Health permissions', (
    tester,
  ) async {
    final health = _WidgetHealthService();
    final controller = readyController(healthService: health)
      ..healthAvailable = true
      ..healthAuthorization = HealthAuthorizationState.notDetermined;
    await tester.pumpWidget(TonyoApp(controller: controller));

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('health-source-card')),
      200,
    );
    await tester.tap(find.byKey(const Key('health-source-card')));
    await tester.pumpAndSettle();

    expect(find.text('Apple Health permissions'), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Heart'), findsOneWidget);
    expect(find.text('Workouts'), findsOneWidget);
    expect(find.text('Hydration'), findsOneWidget);
    expect(find.textContaining('read access only'), findsOneWidget);
    expect(find.textContaining('Manual sleep and activity'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('health-connect-button')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('health-connect-button')));
    await tester.pumpAndSettle();

    expect(health.permissionRequests, 1);
    expect(controller.healthAuthorized, isTrue);
    expect(find.textContaining('choices are saved'), findsOneWidget);
  });

  testWidgets('syncs heart, sleep, workout, steps, and water data', (
    tester,
  ) async {
    final health = _WidgetHealthService(
      readings: [
        SignalReading(
          id: 'healthkit-widget-hrv',
          type: SignalType.hrv,
          value: 58,
          timestamp: DateTime.now(),
          source: SignalSource.healthKit,
        ),
      ],
      sleepReadings: [
        SignalReading(
          id: 'healthkit-widget-core',
          type: SignalType.sleepCore,
          value: 6,
          timestamp: DateTime.now(),
          source: SignalSource.healthKit,
          groupId: 'com.apple.health.watch',
        ),
      ],
      activityReadings: [
        SignalReading(
          id: 'healthkit-widget-workout',
          type: SignalType.exercise,
          value: 1.25,
          timestamp: DateTime.now(),
          source: SignalSource.healthKit,
        ),
        SignalReading(
          id: 'healthkit-widget-water',
          type: SignalType.hydration,
          value: .4,
          timestamp: DateTime.now(),
          source: SignalSource.healthKit,
        ),
        SignalReading(
          id: 'healthkit-steps-2026-08-18',
          type: SignalType.steps,
          value: 6400,
          timestamp: DateTime.now(),
          source: SignalSource.healthKit,
        ),
      ],
    );
    final controller = readyController(healthService: health)
      ..healthAvailable = true
      ..healthAuthorized = true
      ..healthAuthorization = HealthAuthorizationState.authorized
      ..signals = [];
    await tester.pumpWidget(TonyoApp(controller: controller));

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('health-source-card')),
      200,
    );
    await tester.tap(find.byKey(const Key('health-source-card')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('health-sync-button')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('health-sync-button')));
    await tester.pumpAndSettle();

    expect(health.syncCalls, 1);
    expect(controller.healthKitHeartSignalCount, 1);
    expect(controller.healthKitSleepNightCount, 1);
    expect(controller.healthKitWorkoutSignalCount, 1);
    expect(controller.healthKitHydrationSignalCount, 1);
    expect(controller.healthKitStepSignalCount, 1);
    expect(find.textContaining('Imported 1 new heart signal'), findsOneWidget);
    expect(find.textContaining('Reconciled 1 night'), findsOneWidget);
    expect(
      find.textContaining('Imported 3 new or updated activity signals'),
      findsOneWidget,
    );
    expect(find.textContaining('30-day window'), findsOneWidget);
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
    expect(find.textContaining('6/6 cognitive inputs'), findsOneWidget);
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

    await tester.scrollUntilVisible(find.text('Daily Score Models'), 250);
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

  testWidgets(
    'Versions 0.18–0.19 show grounded guidance and dismiss wellness flags',
    (tester) async {
      final now = DateTime.now();
      final controller = AppController()
        ..isReady = true
        ..onboardingComplete = true
        ..signals = [
          for (var index = 0; index < 4; index++)
            SignalReading(
              id: 'short-sleep-$index',
              type: SignalType.sleep,
              value: 5.5,
              timestamp: now.subtract(Duration(days: index)),
            ),
          SignalReading(
            id: 'bedtime-live',
            type: SignalType.bedtime,
            value: 1,
            timestamp: now,
          ),
          SignalReading(
            id: 'study-live',
            type: SignalType.study,
            value: 6,
            timestamp: now,
          ),
          SignalReading(
            id: 'hydration-live',
            type: SignalType.hydration,
            value: .6,
            timestamp: now,
          ),
        ]
        ..checkIns = [
          for (var index = 0; index < 3; index++)
            DailyCheckIn(
              id: 'strained-$index',
              timestamp: now.subtract(Duration(days: index)),
              energy: 3,
              mood: 4,
              stress: 9,
            ),
        ];
      await controller.refreshGuidance();
      final alertId = controller.alerts.first.id;

      await tester.pumpWidget(TonyoApp(controller: controller));
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Coach'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Grounded daily guidance'), findsOneWidget);
      expect(find.text('Wellness flags'), findsOneWidget);
      expect(find.text('Short-sleep pattern'), findsOneWidget);
      expect(find.textContaining('fixture'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(Key('dismiss-risk-$alertId')),
        180,
      );
      await tester.tap(find.byKey(Key('dismiss-risk-$alertId')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('risk-alert-$alertId')), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Protect a 60-minute focus block'),
        220,
      );
      expect(find.text('Protect a 60-minute focus block'), findsOneWidget);
      expect(find.textContaining('WINDOW'), findsWidgets);
      expect(find.byIcon(Icons.link_rounded), findsWidgets);
      await tester.scrollUntilVisible(
        find.textContaining('general wellness only'),
        220,
      );
      expect(find.textContaining('does not diagnose'), findsOneWidget);
    },
  );

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

class _WidgetNotificationService implements NotificationService {
  int permissionRequests = 0;

  @override
  bool get supportsScheduling => true;

  @override
  Future<void> cancelGuidance() async {}

  @override
  Future<NotificationPermissionState> permissionStatus() async =>
      NotificationPermissionState.granted;

  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {}

  @override
  Future<NotificationPermissionState> requestPermission() async {
    permissionRequests += 1;
    return NotificationPermissionState.granted;
  }
}

class _WidgetHealthService extends HealthService {
  _WidgetHealthService({
    this.readings = const [],
    this.sleepReadings = const [],
    this.activityReadings = const [],
  });

  int permissionRequests = 0;
  int syncCalls = 0;
  final List<SignalReading> readings;
  final List<SignalReading> sleepReadings;
  final List<SignalReading> activityReadings;

  @override
  Future<HealthAuthorizationState> authorizationStatus() async =>
      HealthAuthorizationState.notDetermined;

  @override
  Future<HealthAuthorizationState> requestAuthorization() async {
    permissionRequests += 1;
    return HealthAuthorizationState.authorized;
  }

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<List<SignalReading>> sync() async {
    syncCalls += 1;
    return readings;
  }

  @override
  Future<List<SignalReading>> syncSleep() async => sleepReadings;

  @override
  Future<List<SignalReading>> syncActivity() async => activityReadings;
}
