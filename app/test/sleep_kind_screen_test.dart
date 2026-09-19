import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/daily_history_screen.dart';
import 'package:app/src/screens/sleep_log_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  AppController controller() =>
      AppController(initialPrivacyConsent: testAdultPrivacyConsent)
        ..isReady = true;

  Widget screen(AppController controller, Widget child) => AppScope(
    controller: controller,
    child: MaterialApp(theme: buildTonyoTheme(), home: child),
  );

  for (final width in [390.0, 320.0]) {
    testWidgets('sleep form fits ${width.toInt()}px with double text size', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = controller();
      addTearDown(model.dispose);
      await tester.pumpWidget(
        screen(
          model,
          MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: const TextScaler.linear(2),
            ),
            child: const SleepLogScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Nap'));
      await tester.tap(find.text('Nap'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save nap'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save nap'));
      await tester.pumpAndSettle();
      expect(model.sleepLogs.single.isNap, isTrue);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.byTooltip('Edit nap'), 300);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit nap'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Update nap'), -300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'saving a nap keeps the main sleep average and summary separate',
    (tester) async {
      final model = controller();
      addTearDown(model.dispose);
      final now = DateTime.now();
      await model.addSleep(
        bedtime: DateTime(now.year, now.month, now.day - 1, 23),
        wakeTime: DateTime(now.year, now.month, now.day, 7),
        quality: 3,
      );
      final mainSleepAverage =
          model.insightsSnapshot.currentSummary.averageSleepHours;
      await tester.pumpWidget(screen(model, const SleepLogScreen()));

      await tester.tap(find.text('Nap'));
      await tester.pump();
      expect(find.text('Nap start'), findsOneWidget);
      expect(find.text('Nap end'), findsOneWidget);
      expect(find.text('Calculated duration: 0h 30m'), findsOneWidget);
      await tester.ensureVisible(find.text('Save nap'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save nap'));
      await tester.pumpAndSettle();

      expect(find.text('Nap saved.'), findsOneWidget);
      expect(model.sleepLogs.where((entry) => entry.isNap), hasLength(1));
      expect(model.sleepLogs.where((entry) => !entry.isNap), hasLength(1));
      expect(
        model.signals.where((entry) => entry.type == SignalType.bedtime),
        hasLength(1),
      );
      expect(
        model.insightsSnapshot.currentSummary.averageSleepHours,
        mainSleepAverage,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('nap-summary')),
        180,
      );
      expect(find.text('1 nap · 0h 30m total'), findsOneWidget);
      expect(find.text('Add 2 main sleeps to calculate'), findsOneWidget);
    },
  );

  testWidgets('history edits a nap into main sleep without duplicating it', (
    tester,
  ) async {
    final model = controller();
    addTearDown(model.dispose);
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 14, 30);
    await model.addSleep(
      bedtime: end.subtract(const Duration(minutes: 30)),
      wakeTime: end,
      quality: 4,
      kind: SleepKind.nap,
    );
    final entryId = model.sleepLogs.single.id;
    await tester.pumpWidget(screen(model, const DailyHistoryScreen()));
    expect(find.text('Nap'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit Nap'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<SleepKind>>(
            find.byKey(const Key('sleep-kind-selector')),
          )
          .selected,
      {SleepKind.nap},
    );
    await tester.tap(find.text('Main sleep'));
    await tester.pump();
    expect(find.text('Calculated duration: 0h 30m'), findsOneWidget);
    await tester.ensureVisible(find.text('Update sleep'));
    await tester.tap(find.text('Update sleep'));
    await tester.pumpAndSettle();

    expect(model.sleepLogs, hasLength(1));
    expect(model.sleepLogs.single.id, entryId);
    expect(model.sleepLogs.single.isNap, isFalse);
    expect(
      model.signals.where((entry) => entry.type == SignalType.nap),
      isEmpty,
    );
    expect(find.text('Main sleep'), findsOneWidget);
    expect(find.text('Nap'), findsNothing);
  });

  testWidgets('converting a long sleep to a nap shows duration validation', (
    tester,
  ) async {
    final model = controller();
    addTearDown(model.dispose);
    final now = DateTime.now();
    await model.addSleep(
      bedtime: DateTime(now.year, now.month, now.day - 2, 23),
      wakeTime: DateTime(now.year, now.month, now.day - 1, 7),
      quality: 3,
    );
    await tester.pumpWidget(
      screen(model, SleepLogScreen(initialLog: model.sleepLogs.single)),
    );
    await tester.tap(find.text('Nap'));
    await tester.pump();
    await tester.ensureVisible(find.text('Update nap'));
    await tester.tap(find.text('Update nap'));
    await tester.pumpAndSettle();

    expect(
      find.text('Nap duration must be between 5 minutes and 3 hours.'),
      findsOneWidget,
    );
    expect(model.sleepLogs.single.isNap, isFalse);
    expect(model.sleepLogs.single.durationHours, 8);
  });
}
