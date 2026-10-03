import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/forecast_screen.dart';
import 'package:app/src/widgets/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'privacy_test_support.dart';

class _ForecastController extends AppController {
  _ForecastController(this.snapshot, this.points)
    : super(initialPrivacyConsent: testAdultPrivacyConsent);

  final ScoreSnapshot snapshot;
  final List<ForecastPoint> points;

  @override
  ScoreSnapshot get score => snapshot;
  @override
  List<ForecastPoint> forecastDataFor(DateTime day) => points;
  @override
  List<ForecastWindow> windowsFor(DateTime day) => const [];
  @override
  List<ForecastDaySummary> forecastSummariesFor(
    DateTime day, {
    int dayCount = AppController.forecastDayCount,
  }) =>
      points.isEmpty ? const [] : [ForecastDaySummary.fromPoints(day, points)];
}

void main() {
  Future<void> open(WidgetTester tester, _ForecastController controller) async {
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          controller: controller,
          child: const Scaffold(body: ForecastScreen()),
        ),
      ),
    );
  }

  List<ForecastPoint> points(DateTime updatedAt) {
    final today = DateTime.now();
    return [
      for (var hour = 8; hour < 20; hour++)
        ForecastPoint(
          DateTime(today.year, today.month, today.day, hour),
          60,
          20,
          updatedAt: updatedAt,
          rulesVersion: FatigueEngine.energyModelVersion,
        ),
    ];
  }

  const available = ScoreSnapshot(
    energy: 60,
    cognitive: 60,
    confidence: .4,
    inputCount: 1,
    drivers: [],
  );

  testWidgets(
    'unavailable evidence hides numeric forecast even if cached points exist',
    (tester) async {
      final unavailable = FatigueEngine.score(
        signals: const [],
        checkIns: const [],
        now: DateTime.now(),
      );
      await open(
        tester,
        _ForecastController(unavailable, points(DateTime.now())),
      );
      expect(find.text('No forecast available'), findsOneWidget);
      expect(
        find.textContaining('Not enough current information'),
        findsOneWidget,
      );
      expect(find.byType(ForecastChart), findsNothing);
      expect(find.textContaining('Curve high'), findsNothing);
    },
  );

  testWidgets('outdated points do not remain a visible current forecast', (
    tester,
  ) async {
    await open(
      tester,
      _ForecastController(
        available,
        points(DateTime.now().subtract(const Duration(days: 2))),
      ),
    );
    expect(find.text('Forecast is out of date'), findsOneWidget);
    expect(find.byType(ForecastChart), findsNothing);
    expect(find.textContaining('Curve high'), findsNothing);
  });

  testWidgets('curve bands and timing are explicitly uncalibrated', (
    tester,
  ) async {
    await open(tester, _ForecastController(available, points(DateTime.now())));
    expect(find.text('Limited data quality'), findsOneWidget);
    expect(find.textContaining('Curve high'), findsOneWidget);
    expect(find.text('Predicted crash'), findsNothing);
    expect(find.text('Peak focus'), findsNothing);
    await tester.scrollUntilVisible(
      find.textContaining('not statistical confidence intervals'),
      250,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    expect(
      find.textContaining('not statistical confidence intervals'),
      findsOneWidget,
    );
    expect(find.textContaining('whether exercise is safe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
