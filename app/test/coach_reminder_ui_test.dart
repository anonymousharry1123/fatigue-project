import 'dart:async';

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/models.dart';
import 'package:app/src/notification_service.dart';
import 'package:app/src/screens/coach_screen.dart';
import 'package:app/src/screens/profile_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

final _now = DateTime(2026, 9, 20, 12);
Recommendation _plan(
  String id,
  int hour, {
  RecommendationStatus status = RecommendationStatus.suggested,
}) => Recommendation(
  id: id,
  title: 'Plan $id',
  detail: 'Take a short recovery break.',
  timeLabel: '$hour:00',
  category: 'Recovery',
  scheduledAt: DateTime(2026, 9, 20, hour),
  day: DateTime(2026, 9, 20),
  generatedAt: _now,
  status: status,
);

class _ReminderController extends AppController {
  _ReminderController()
    : super(initialPrivacyConsent: testAdultPrivacyConsent, clock: () => _now) {
    isReady = true;
    onboardingComplete = true;
  }
  List<Recommendation> plans = [_plan('future', 14)];
  final scheduled = <String, GuidanceNotification>{};
  bool supported = true;
  bool deny = false;
  bool fail = false;
  int optIns = 0;
  Completer<void>? pending;
  @override
  bool get notificationSchedulingSupported => supported;
  @override
  List<Recommendation> get recommendations => plans;
  @override
  GuidanceNotification? notificationForRecommendation(String id) =>
      notificationsEnabled &&
          coachPlanNotificationsEnabled &&
          notificationError == null
      ? scheduled[id]
      : null;
  @override
  int get scheduledCoachNotificationCount => scheduled.length;
  @override
  Future<void> setCoachPlanNotifications(bool enabled) async {
    optIns++;
    if (fail) throw StateError('Could not save to this device');
    await pending?.future;
    coachPlanNotificationsEnabled = enabled;
    if (enabled) {
      notificationsEnabled = !deny;
      notificationPermission = deny
          ? NotificationPermissionState.denied
          : NotificationPermissionState.granted;
      notificationError = deny
          ? 'Notifications are blocked in system settings.'
          : null;
    }
    notifyListeners();
  }

  @override
  Future<void> setRecommendationFeedback(String id, bool helpful) async {
    plans = plans
        .map((item) => item.id == id ? item.copyWith(helpful: helpful) : item)
        .toList();
    notifyListeners();
  }
}

Future<void> _pump(
  WidgetTester tester,
  _ReminderController controller, {
  Widget screen = const CoachScreen(),
  bool narrow = false,
}) async {
  if (narrow) {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        theme: buildTonyoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 300,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Coach offers explicit reminder opt-in without prompting on opening',
    (tester) async {
      final controller = _ReminderController();
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      final toggle = find.byKey(const Key('coach-plan-reminder-switch'));
      await _reveal(tester, toggle);
      expect(controller.optIns, 0);
      expect(tester.widget<SwitchListTile>(toggle).value, false);
      expect(find.textContaining('Open Tonyo each day'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(controller.optIns, 1);
      expect(controller.notificationsEnabled, true);
      expect(tester.widget<SwitchListTile>(toggle).value, true);
    },
  );

  testWidgets(
    'a pending opt-in disables duplicate requests and shows denied permission',
    (tester) async {
      final controller = _ReminderController()
        ..deny = true
        ..pending = Completer<void>();
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      final toggle = find.byKey(const Key('coach-plan-reminder-switch'));
      await _reveal(tester, toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
      expect(controller.optIns, 1);
      controller.pending!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('Notifications are blocked in system settings.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('coach-enable-notifications')),
        findsOneWidget,
      );
      expect(controller.notificationsEnabled, false);
    },
  );

  testWidgets(
    'plan blocks show actual scheduled, past and unscheduled states without workflow actions',
    (tester) async {
      final controller = _ReminderController()
        ..plans = [
          _plan('past', 9, status: RecommendationStatus.completed),
          _plan('future', 14, status: RecommendationStatus.accepted),
          _plan('unscheduled', 16, status: RecommendationStatus.dismissed),
        ]
        ..coachPlanNotificationsEnabled = true
        ..notificationsEnabled = true;
      controller.scheduled['future'] = GuidanceNotification(
        id: 'scheduled',
        platformId: 42,
        kind: GuidanceNotificationKind.coachPlan,
        scheduledAt: DateTime(2026, 9, 20, 14),
        title: 'Plan future',
        body: 'Take a break',
        sourceRecommendationId: 'future',
      );
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await _reveal(tester, find.byKey(const Key('plan-reminder-status-past')));
      expect(find.text('Time passed'), findsOneWidget);
      await _reveal(
        tester,
        find.byKey(const Key('plan-reminder-status-future')),
      );
      expect(find.textContaining('Reminder scheduled ·'), findsOneWidget);
      await _reveal(
        tester,
        find.byKey(const Key('plan-reminder-status-unscheduled')),
      );
      expect(find.text('No reminder scheduled'), findsOneWidget);
      for (final label in [
        'Accept',
        'Complete',
        'SUGGESTED',
        'ACCEPTED',
        'COMPLETED',
        'DISMISSED',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(
        find.byKey(const Key('dismiss-recommendation-unscheduled')),
        findsNothing,
      );
      expect(find.textContaining('delivered'), findsNothing);
      expect(find.text('Log observed energy'), findsNothing);
    },
  );

  testWidgets('feedback is optional and available for a suggested block', (
    tester,
  ) async {
    final controller = _ReminderController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final helpful = find.byKey(const Key('helpful-recommendation-future'));
    await _reveal(tester, helpful);
    await tester.tap(helpful);
    await tester.pumpAndSettle();
    expect(controller.plans.single.helpful, true);
    expect(controller.plans.single.status, RecommendationStatus.suggested);
    expect(find.text('Helpful · saved'), findsOneWidget);
    expect(find.text('Reminders off'), findsOneWidget);
  });

  testWidgets('Coach reminder timeline fits 320px at double text size', (
    tester,
  ) async {
    final controller = _ReminderController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, narrow: true);
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    for (var i = 0; i < 60 && position.pixels < position.maxScrollExtent; i++) {
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(position.pixels, position.maxScrollExtent);
    expect(
      find.byKey(const Key('helpful-recommendation-future')),
      findsOneWidget,
    );
  });

  testWidgets(
    'Profile notification setting failures are shown without an uncaught error',
    (tester) async {
      final controller = _ReminderController()..fail = true;
      addTearDown(controller.dispose);
      await _pump(
        tester,
        controller,
        screen: const Scaffold(body: ProfileScreen()),
      );
      await _reveal(tester, find.text('Notifications'));
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
      final coach = find.byKey(const Key('notification-coach-plan-switch'));
      await _reveal(tester, coach);
      await tester.tap(coach);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save notification settings. Please try again.'),
        findsOneWidget,
      );
      expect(controller.coachPlanNotificationsEnabled, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Profile offers daily plan reminders alongside forecast categories at large text',
    (tester) async {
      final controller = _ReminderController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        controller,
        screen: const Scaffold(body: ProfileScreen()),
        narrow: true,
      );
      await _reveal(tester, find.text('Notifications'));
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
      final coach = find.byKey(const Key('notification-coach-plan-switch'));
      await _reveal(tester, coach);
      expect(tester.widget<SwitchListTile>(coach).value, false);
      expect(tester.widget<SwitchListTile>(coach).onChanged, isNotNull);
      await tester.tap(coach);
      await tester.pumpAndSettle();
      expect(controller.optIns, 1);
      expect(controller.notificationsEnabled, true);
      await _reveal(
        tester,
        find.byKey(const Key('notification-recovery-switch')),
      );
      expect(
        find.byKey(const Key('notification-crash-switch')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notification-master-switch')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
