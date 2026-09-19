import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/demo_data.dart';
import 'package:app/src/screens/forecast_screen.dart';
import 'package:app/src/screens/insights_screen.dart';
import 'package:app/src/screens/shell_screen.dart';
import 'package:app/src/screens/today_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

Future<AppController> _controller() async {
  final now = DateTime.now();
  final controller =
      AppController(initialPrivacyConsent: testAdultPrivacyConsent)
        ..isReady = true
        ..onboardingComplete = true
        ..signals = buildDemoSignals(now)
        ..checkIns = buildDemoCheckIns(now);
  await controller.refreshForecasts();
  await controller.refreshInsights();
  return controller;
}

Future<void> _pumpScreen(
  WidgetTester tester,
  AppController controller,
  Widget screen, {
  double textScale = 2,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const SizedBox.shrink());
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
  await tester.pumpAndSettle();
}

Future<void> _checkEntireScroll(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  final scrollable = find.byType(Scrollable).first;
  final position = tester.state<ScrollableState>(scrollable).position;
  var scrolls = 0;
  while (position.pixels < position.maxScrollExtent && scrolls++ < 100) {
    await tester.drag(scrollable, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
  expect(position.pixels, position.maxScrollExtent);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Shell and Forecast/Insights navigation fit 320px at 2x text', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _pumpScreen(tester, controller, const ShellScreen());
    expect(tester.takeException(), isNull);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Forecast'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Energy Forecast'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<int>).first,
        matching: find.text('Insights'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Your daily patterns and model-estimated trends'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today announces score meaning and keeps actions reachable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = await _controller();
    addTearDown(controller.dispose);
    var profileOpened = false;
    await _pumpScreen(
      tester,
      controller,
      TodayScreen(onOpenProfile: () => profileOpened = true),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.tap(find.byTooltip('Open profile'));
    expect(profileOpened, isTrue);
    for (final label in ['Energy', 'Cognitive']) {
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('$label score'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel('$label score')),
        matchesSemantics(
          label: '$label score',
          value:
              '${label == 'Energy' ? controller.score.energy : controller.score.cognitive} out of 100',
        ),
      );
    }
    await tester.scrollUntilVisible(
      find.byKey(const Key('today-score-transparency')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'Forecast range controls and weekly chart expose usable semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = await _controller();
      addTearDown(controller.dispose);
      await _pumpScreen(tester, controller, const ForecastScreen());
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('forecast-week-chart-scroll')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('Average estimated Energy:.*out of 100')),
        findsWidgets,
      );
      await tester.drag(
        find.byKey(const Key('forecast-week-chart-scroll')),
        const Offset(-350, 0),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('Uncertainty: plus or minus')),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('Insights trend reads dates, units, and missing observations', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = await _controller();
    addTearDown(controller.dispose);
    controller.signals = [];
    controller.checkIns = [];
    await controller.refreshInsights();
    await _pumpScreen(tester, controller, const InsightsScreen());
    await tester.scrollUntilVisible(
      find.byKey(const Key('insight-metric-sleep')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('insight-metric-sleep')));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await tester.scrollUntilVisible(
      find.byKey(const Key('insights-trend-chart-scroll')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp(r'\d{4}\. Sleep: Not logged')),
      findsWidgets,
    );
    expect(find.bySemanticsLabel(RegExp('Sleep: 0.0 hours')), findsNothing);

    controller.signals = buildDemoSignals(DateTime.now());
    await controller.refreshInsights();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('insights-trend-chart-scroll')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp(r'Sleep: \d+\.\d hours')),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets('Today fits 320px at ${textScale}x text throughout the page', (
      tester,
    ) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await _pumpScreen(
        tester,
        controller,
        TodayScreen(onOpenProfile: () {}),
        textScale: textScale,
      );
      await _checkEntireScroll(tester);
    });

    testWidgets('Forecast ranges fit 320px at ${textScale}x text', (
      tester,
    ) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      for (final range in ['Today', 'Tomorrow', 'Week']) {
        await _pumpScreen(
          tester,
          controller,
          ForecastScreen(key: ValueKey(range)),
          textScale: textScale,
        );
        await tester.tap(find.text(range));
        await tester.pumpAndSettle();
        await _checkEntireScroll(tester);
      }
    });

    testWidgets(
      'Insights fits 320px at ${textScale}x text throughout the page',
      (tester) async {
        final controller = await _controller();
        addTearDown(controller.dispose);
        await _pumpScreen(
          tester,
          controller,
          const InsightsScreen(),
          textScale: textScale,
        );
        await _checkEntireScroll(tester);
      },
    );
  }
}
