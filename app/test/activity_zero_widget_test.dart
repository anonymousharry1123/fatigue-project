import 'package:app/src/activity_sync_logic.dart';
import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/activity_log_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final now = DateTime(2026, 9, 7, 12);
  Finder field(String key) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(TextFormField),
  );
  Future<void> pump(
    WidgetTester tester,
    AppController controller, {
    ActivityLogEntry? initial,
  }) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: buildTonyoTheme(),
          home: ActivityLogScreen(initialLog: initial),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'activity editor displays zero and blank distinctly and clears explicitly',
    (tester) async {
      final controller = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        clock: () => now,
      );
      addTearDown(controller.dispose);
      controller.signals = [
        SignalReading(
          id: 'health-exercise',
          type: SignalType.exercise,
          value: 1.5,
          source: SignalSource.healthKit,
          timestamp: now,
        ),
      ];
      await controller.saveActivityLog(
        id: 'activity-edit-zero',
        hydrationLiters: 1,
        exerciseHours: 0,
        timestamp: now,
      );
      await pump(tester, controller, initial: controller.activityLogs.single);
      expect(
        tester.widget<TextFormField>(field('exercise-field')).controller!.text,
        '0',
      );
      expect(
        tester.widget<TextFormField>(field('study-field')).controller!.text,
        '',
      );
      expect(
        ActivitySyncLogic.aggregateForDay(
          controller.signals,
          type: SignalType.exercise,
          day: now,
        )!.total,
        0,
      );
      await tester.enterText(field('exercise-field'), '');
      await tester.ensureVisible(find.text('Update activity'));
      await tester.tap(find.text('Update activity'));
      await tester.pumpAndSettle();
      expect(controller.activityLogs.single.exerciseHours, isNull);
      expect(controller.activityLogs.single.studyHours, isNull);
      expect(
        ActivitySyncLogic.aggregateForDay(
          controller.signals,
          type: SignalType.exercise,
          day: now,
        )!.total,
        1.5,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new zero-only entry saves the observed category without filling blanks',
    (tester) async {
      final controller = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        clock: () => now,
      );
      addTearDown(controller.dispose);
      await pump(tester, controller);
      await tester.enterText(field('study-field'), '0');
      await tester.ensureVisible(find.text('Save activity'));
      await tester.tap(find.text('Save activity'));
      await tester.pumpAndSettle();
      expect(controller.signals, hasLength(1));
      expect(controller.signals.single.type, SignalType.study);
      expect(controller.signals.single.value, 0);
      expect(controller.activityLogs.single.hydrationLiters, isNull);
      expect(controller.activityLogs.single.exerciseHours, isNull);
      expect(controller.activityLogs.single.screenTimeHours, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
