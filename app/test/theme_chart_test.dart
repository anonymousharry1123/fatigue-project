import 'dart:ui' as ui;

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/admin/admin_charts.dart';
import 'package:app/src/screens/reaction_test_screen.dart';
import 'package:app/src/synthetic/cohort_stats.dart';
import 'package:app/src/theme.dart';
import 'package:app/src/widgets/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'privacy_test_support.dart';

void main() {
  final points = [
    ForecastPoint(DateTime(2026, 9, 20, 8), 50, 10),
    ForecastPoint(DateTime(2026, 9, 20, 12), 50, 10),
  ];
  const scatterPoints = [
    CohortScatterPoint(1, 40, 'first'),
    CohortScatterPoint(2, 60, 'second'),
  ];

  testWidgets('ring, forecast and cohort painters repaint as themes change', (
    tester,
  ) async {
    final theme = ValueNotifier(buildTonyoTheme());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<ThemeData>(
        valueListenable: theme,
        builder: (context, selectedTheme, child) => MaterialApp(
          theme: selectedTheme,
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: Column(
              children: [
                const ScoreRing(value: 65, label: 'Energy'),
                ForecastChart(points: points, height: 150),
                const CohortScatterChart(
                  points: scatterPoints,
                  xLabel: 'Sleep',
                  yLabel: 'Energy',
                  height: 150,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    List<CustomPainter> painters() => [
      for (final type in [ScoreRing, ForecastChart, CohortScatterChart])
        tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(type),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!,
    ];
    var previous = painters();
    for (final brightness in Brightness.values) {
      for (final preset in tonyoThemePresets) {
        theme.value = buildTonyoTheme(
          brightness: brightness,
          colors: preset.colors,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final current = painters();
        // The data stayed identical: these rebuilds must still repaint for
        // palette changes, including axis labels, tracks, and grid lines.
        for (var index = 0; index < current.length; index++) {
          expect(current[index].shouldRepaint(previous[index]), isTrue);
        }
        previous = current;
      }
    }
    theme.value = theme.value.copyWith(
      textTheme: theme.value.textTheme.apply(fontFamily: 'ChartFont'),
    );
    await tester.pump();
    final withFont = painters();
    expect((withFont[1] as ForecastPainter).textStyle.fontFamily, 'ChartFont');
    expect(withFont[1].shouldRepaint(previous[1]), isTrue);
    expect(withFont[2].shouldRepaint(previous[2]), isTrue);
  });

  testWidgets('identical custom colors retain dashed uncertainty boundaries', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const identicalColors = TonyoColorPair(
        main: Color(0xFF2563EB),
        secondary: Color(0xFF2563EB),
      );
      for (final brightness in Brightness.values) {
        final palette = TonyoPalette.resolve(brightness, identicalColors);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(palette.surface, BlendMode.src);
        ForecastPainter(
          points,
          colors: palette,
          compact: true,
        ).paint(canvas, const Size(180, 140));
        final picture = recorder.endRecording();
        final image = await picture.toImage(180, 140);
        final bytes = (await image.toByteData())!;
        // The upper bound is at y=66; the estimated value is at y=78.
        // Count foreground pixels across each row to verify a continuous
        // estimate and a visibly interrupted uncertainty boundary.
        int inkAt(int y) {
          var count = 0;
          for (var x = 2; x < 178; x++) {
            final offset = (y * 180 + x) * 4;
            final pixel = Color.fromARGB(
              bytes.getUint8(offset + 3),
              bytes.getUint8(offset),
              bytes.getUint8(offset + 1),
              bytes.getUint8(offset + 2),
            );
            if (tonyoContrastRatio(pixel, palette.surface) > 2) count++;
          }
          return count;
        }

        expect(inkAt(78), greaterThan(170));
        expect(inkAt(66), inInclusiveRange(70, 130));
        image.dispose();
        picture.dispose();
      }
    });
  });

  testWidgets('reaction test cues stay semantic across custom theme changes', (
    tester,
  ) async {
    final controller = AppController(
      initialPrivacyConsent: testAdultPrivacyConsent,
    );
    addTearDown(controller.dispose);
    final theme = ValueNotifier(
      buildTonyoTheme(
        colors: const TonyoColorPair(main: Colors.red, secondary: Colors.red),
      ),
    );
    addTearDown(theme.dispose);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: ValueListenableBuilder<ThemeData>(
          valueListenable: theme,
          builder: (context, selectedTheme, child) => MaterialApp(
            theme: selectedTheme,
            themeAnimationDuration: Duration.zero,
            home: const ReactionTestScreen(waitDuration: Duration(seconds: 1)),
          ),
        ),
      ),
    );
    final panel = find.byKey(const Key('reaction-test-panel'));
    Color panelColor() =>
        (tester
                    .widget<Ink>(
                      find.descendant(of: panel, matching: find.byType(Ink)),
                    )
                    .decoration!
                as BoxDecoration)
            .color!;
    final firstPalette = theme.value.extension<TonyoPalette>()!;
    await tester.tap(panel);
    await tester.pump();
    expect(panelColor(), firstPalette.warning);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('TAP NOW'), findsOneWidget);
    expect(panelColor(), firstPalette.success);

    theme.value = buildTonyoTheme(
      colors: const TonyoColorPair(main: Colors.black, secondary: Colors.white),
    );
    await tester.pump();
    expect(find.text('TAP NOW'), findsOneWidget);
    expect(panelColor(), firstPalette.success);
    expect(tester.takeException(), isNull);
  });
}
