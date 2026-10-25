import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/add_data_screen.dart';
import 'package:app/src/screens/daily_history_screen.dart';
import 'package:app/src/screens/heart_metrics_screen.dart';
import 'package:app/src/screens/insights_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final day = DateTime(2026, 1, 24, 12);
  SignalReading reading(String id, SignalType type, double value) =>
      SignalReading(
        id: id,
        type: type,
        value: value,
        timestamp: day,
        source: SignalSource.healthKit,
      );

  Future<AppController> pump(
    WidgetTester tester,
    Widget screen, {
    List<SignalReading>? readings,
    double textScale = 1,
  }) async {
    final controller = AppController()
      ..isReady = true
      ..signals =
          readings ??
          [
            reading('pulse-1', SignalType.heartRate, 60),
            reading('pulse-2', SignalType.heartRate, 80),
            reading('resting', SignalType.restingHeartRate, 55),
            reading('hrv', SignalType.hrv, 45),
          ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: buildTonyoTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(body: screen),
        ),
      ),
    );
    return controller;
  }

  testWidgets(
    'heart metrics moves from Add to Insights and exposes resting HR and HRV',
    (tester) async {
      await pump(tester, const AddDataScreen());
      expect(find.text('Heart metrics'), findsNothing);
      expect(find.text('Daily history'), findsNothing);
      await pump(tester, const InsightsScreen());
      expect(find.text('History'), findsOneWidget);
      await tester.tap(find.text('Heart metrics'));
      await tester.pumpAndSettle();
      expect(find.byType(HeartMetricsScreen), findsOneWidget);
      expect(find.text('70.0 bpm'), findsOneWidget);
      expect(find.text('Resting heart rate'), findsOneWidget);
      expect(find.text('55.0 bpm'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Heart rate variability (HRV)'),
        200,
      );
      expect(find.text('45.0 ms'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'daily history shows only the heart-rate average and retains raw data',
    (tester) async {
      final controller = await pump(tester, const DailyHistoryScreen());
      await tester.scrollUntilVisible(find.text('Average heart rate'), 200);
      expect(find.text('70.0 bpm'), findsOneWidget);
      expect(find.byKey(const Key('history-item-pulse-1')), findsNothing);
      expect(find.byKey(const Key('history-item-pulse-2')), findsNothing);
      expect(find.text('60 bpm'), findsNothing);
      expect(find.text('80 bpm'), findsNothing);
      expect(controller.signals, hasLength(4));
    },
  );

  testWidgets(
    'empty metrics remain discoverable with guidance at large text size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pump(
        tester,
        const HeartMetricsScreen(),
        readings: [],
        textScale: 2,
      );
      expect(find.text('No heart data yet'), findsOneWidget);
      expect(find.textContaining('Profile → Apple Health'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Resting heart rate'), 250);
      expect(find.text('Resting heart rate'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
