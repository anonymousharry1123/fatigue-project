import 'dart:async';

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/demo_data.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/activity_log_screen.dart';
import 'package:app/src/screens/add_data_screen.dart';
import 'package:app/src/screens/coach_screen.dart';
import 'package:app/src/screens/daily_checkin_screen.dart';
import 'package:app/src/screens/sleep_log_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final entry in <String, Widget>{
    'activity': const ActivityLogScreen(),
    'check-in': const DailyCheckInScreen(),
    'add': const Scaffold(body: AddDataScreen()),
    'coach': const CoachScreen(),
  }.entries) {
    testWidgets('${entry.key} content fits 320px with double text size', (
      tester,
    ) async {
      final now = DateTime.now();
      final controller =
          AppController(initialPrivacyConsent: testAdultPrivacyConsent)
            ..isReady = true
            ..signals = buildDemoSignals(now)
            ..checkIns = buildDemoCheckIns(now);
      addTearDown(controller.dispose);
      if (entry.key == 'activity') {
        await controller.saveActivityLog(
          hydrationLiters: 2.5,
          studyHours: 4,
          exerciseHours: 1,
          screenTimeHours: 5,
        );
      }
      if (entry.key == 'coach') await controller.refreshGuidance();
      await _pump(tester, controller, entry.value, largeText: true);
      expect(tester.takeException(), isNull);
      final scrollable = find.byType(Scrollable).first;
      var priorOffset = -1.0;
      for (var i = 0; i < 100; i++) {
        final position = tester.state<ScrollableState>(scrollable).position;
        if (position.pixels == priorOffset) break;
        priorOffset = position.pixels;
        await tester.drag(find.byType(ListView).first, const Offset(0, -450));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.pixels, position.maxScrollExtent);
    });
  }

  testWidgets('check-in slider announces its name and rating', (tester) async {
    final controller = AppController(
      initialPrivacyConsent: testAdultPrivacyConsent,
    );
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();
    await _pump(tester, controller, const DailyCheckInScreen());
    await tester.scrollUntilVisible(find.byType(Slider).first, 250);
    final energy = tester.getSemantics(find.byType(Slider).first);
    expect(energy.label, 'Energy');
    SemanticsNode? rating;
    energy.visitChildren((child) {
      if (child.value.isNotEmpty) rating = child;
      return true;
    });
    expect(rating?.value, '6 out of 10');
    expect(rating?.increasedValue, '7 out of 10');
    expect(rating?.decreasedValue, '5 out of 10');
    expect(
      tester.getSize(find.byType(Slider).first).height,
      greaterThanOrEqualTo(48),
    );
    semantics.dispose();
  });

  testWidgets('activity failed save unlocks retry and retains entered data', (
    tester,
  ) async {
    final controller = _FailingSaveController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, const ActivityLogScreen());
    await tester.enterText(find.byType(TextFormField).first, '2.5');
    await tester.ensureVisible(find.text('Save activity'));
    await tester.tap(find.text('Save activity'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
      isFalse,
    );
    controller.pending.completeError(StateError('disk unavailable'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save activity.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      '2.5',
    );
    expect(find.text('Save activity'), findsOneWidget);
    controller.pending = Completer<void>();
    await tester.tap(find.text('Save activity'));
    await tester.pump();
    expect(controller.activityAttempts, 2);
    expect(controller.activityIds.first, isNotNull);
    expect(controller.activityIds.toSet(), hasLength(1));
    expect(controller.activityLogs, hasLength(1));
    controller.pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Activity log saved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('check-in failed save keeps note and enables retry', (
    tester,
  ) async {
    final controller = _FailingSaveController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, const DailyCheckInScreen());
    await tester.scrollUntilVisible(find.byType(TextField), 300);
    await tester.enterText(find.byType(TextField), 'A busy day');
    await tester.tap(find.text('Save check-in'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    controller.pending.completeError(StateError('disk unavailable'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not save your check-in.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'A busy day',
    );
    expect(find.text('Save check-in'), findsOneWidget);
    expect(controller.checkInAttempts, 1);
    controller.pending = Completer<void>();
    await tester.tap(find.text('Save check-in'));
    await tester.pump();
    controller.pending.completeError(StateError('still unavailable'));
    await tester.pumpAndSettle();
    expect(controller.checkInAttempts, 2);
    expect(controller.checkInIds.first, isNotNull);
    expect(controller.checkInIds.toSet(), hasLength(1));
    expect(controller.checkIns, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'coach outcome dialog retains rating after failed save at large text',
    (tester) async {
      final controller = _FailingSaveController()..outcomeConsent = true;
      addTearDown(controller.dispose);
      await _pump(tester, controller, const CoachScreen(), largeText: true);
      await tester.scrollUntilVisible(
        find.byKey(const Key('record-outcome-test-plan')),
        350,
      );
      await tester.ensureVisible(
        find.byKey(const Key('record-outcome-test-plan')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('record-outcome-test-plan')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('save-observed-energy')));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      controller.pending.completeError(StateError('disk unavailable'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save your energy rating. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('6/10'), findsOneWidget);
      controller.pending = Completer<void>();
      await tester.tap(find.byKey(const Key('save-observed-energy')));
      await tester.pump();
      controller.pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.outcomeAttempts, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('nap save failure unlocks a retry without creating a duplicate', (
    tester,
  ) async {
    final controller = _FailingSaveController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, const SleepLogScreen());
    await tester.tap(find.text('Nap'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save nap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save nap'));
    await tester.pump();
    controller.pending.completeError(StateError('disk unavailable'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save sleep.'), findsOneWidget);
    expect(find.text('Save nap'), findsOneWidget);
    expect(find.text('Calculated duration: 0h 30m'), findsOneWidget);
    controller.pending = Completer<void>();
    await tester.tap(find.text('Save nap'));
    await tester.pump();
    controller.pending.complete();
    await tester.pumpAndSettle();
    expect(controller.sleepIds.first, isNotNull);
    expect(controller.sleepIds.toSet(), hasLength(1));
    expect(controller.sleepLogs, hasLength(1));
    expect(controller.sleepLogs.single.isNap, isTrue);
    expect(find.text('Nap saved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving sleep while saving does not update disposed UI', (
    tester,
  ) async {
    final controller = _FailingSaveController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, const SleepLogScreen());
    await tester.ensureVisible(find.text('Save sleep'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save sleep'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    controller.pending.completeError(StateError('session changed'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  AppController controller,
  Widget screen, {
  bool largeText = false,
}) async {
  tester.view.physicalSize = Size(largeText ? 320 : 390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        theme: buildTonyoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(largeText ? 2 : 1)),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FailingSaveController extends AppController {
  _FailingSaveController()
    : super(initialPrivacyConsent: testAdultPrivacyConsent);

  Completer<void> pending = Completer<void>();
  int activityAttempts = 0;
  int checkInAttempts = 0;
  int outcomeAttempts = 0;
  final activityIds = <String?>[];
  final checkInIds = <String?>[];
  final sleepIds = <String?>[];

  @override
  Future<void> addSleep({
    String? id,
    required DateTime bedtime,
    required DateTime wakeTime,
    required double quality,
    SleepKind kind = SleepKind.mainSleep,
  }) async {
    sleepIds.add(id);
    await Future.wait([
      pending.future,
      super.addSleep(
        id: id,
        bedtime: bedtime,
        wakeTime: wakeTime,
        quality: quality,
        kind: kind,
      ),
    ]);
  }

  @override
  List<Recommendation> get recommendations => const [
    Recommendation(
      id: 'test-plan',
      title: 'Recovery break',
      detail: 'Take a short break.',
      timeLabel: '2:00 PM',
      category: 'Recovery',
      status: RecommendationStatus.completed,
    ),
  ];

  @override
  Future<void> recordObservedEnergy(
    double energy, {
    String? recommendationId,
    DateTime? observedAt,
  }) {
    outcomeAttempts++;
    return pending.future;
  }

  @override
  Future<void> saveActivityLog({
    String? id,
    double? hydrationLiters,
    double? studyHours,
    double? exerciseHours,
    double? screenTimeHours,
    DateTime? timestamp,
  }) async {
    activityAttempts++;
    activityIds.add(id);
    await Future.wait([
      pending.future,
      super.saveActivityLog(
        id: id,
        hydrationLiters: hydrationLiters,
        studyHours: studyHours,
        exerciseHours: exerciseHours,
        screenTimeHours: screenTimeHours,
        timestamp: timestamp,
      ),
    ]);
  }

  @override
  Future<void> addCheckIn({
    String? id,
    required double energy,
    required double mood,
    required double stress,
    String note = '',
    DateTime? timestamp,
  }) async {
    checkInAttempts++;
    checkInIds.add(id);
    await Future.wait([
      pending.future,
      super.addCheckIn(
        id: id,
        energy: energy,
        mood: mood,
        stress: stress,
        note: note,
        timestamp: timestamp,
      ),
    ]);
  }
}
