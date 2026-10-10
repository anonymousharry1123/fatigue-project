import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/l10n/self_report_trends_translations.dart';
import 'package:app/src/models.dart';
import 'package:app/src/theme.dart';
import 'package:app/src/typography.dart';
import 'package:app/src/widgets/self_report_trends_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'font_test_support.dart';

final _now = DateTime.utc(2026, 10, 10, 12);

DailyCheckIn _report({
  int daysAgo = 0,
  double? energy = 6,
  double? focus,
  CheckInPeriod period = CheckInPeriod.morning,
  String language = 'en',
  String? id,
}) {
  final observed = _now.subtract(Duration(days: daysAgo));
  return DailyCheckIn(
    id: id ?? 'report-$daysAgo-${period.name}-$language',
    timestamp: observed,
    recordedAt: observed,
    localDate: observed.toIso8601String().substring(0, 10),
    utcOffsetMinutes: 0,
    timezone: 'Etc/UTC',
    period: period,
    energy: energy,
    focus: focus,
    mood: null,
    stress: null,
    questionnaireVersion: CheckInMeasurement.currentVersion,
    questionnaireLanguage: language,
    questionnaireSnapshot: CheckInMeasurement.snapshot(
      language: language,
      translate: AppLocalizations(language).text,
    ),
    source: 'selfReport',
  );
}

SignalReading _sleep(int daysAgo, {bool availabilityKnown = true}) {
  final end = _now.subtract(Duration(days: daysAgo, hours: 4));
  return SignalReading(
    id: 'sleep-$daysAgo',
    type: SignalType.sleep,
    value: 6 + daysAgo % 4 / 2,
    timestamp: end,
    recordedAt: availabilityKnown ? end : null,
    source: SignalSource.manual,
  );
}

void main() {
  test('trend translations retain all template arguments in each language', () {
    final placeholders = RegExp(r'\{[A-Za-z][A-Za-z0-9_]*\}');
    Set<String> arguments(String text) =>
        placeholders.allMatches(text).map((match) => match.group(0)!).toSet();
    for (final entry in selfReportTrendsTranslations.entries) {
      for (final language in ['es', 'zh-Hans', 'zh-Hant']) {
        final translated = entry.value[language];
        expect(translated, isNotNull, reason: '${entry.key}: $language');
        expect(translated, isNotEmpty, reason: '${entry.key}: $language');
        expect(arguments(translated!), arguments(entry.key));
        expect(AppLocalizations(language).text(entry.key), translated);
      }
    }
  });
  testWidgets('sparse raw answers and sleep pairs use dated records', (
    tester,
  ) async {
    final reports = [_report(daysAgo: 1, energy: 4), _report(energy: 8)];
    final signals = [_sleep(1, availabilityKnown: false)];
    final before = jsonEncode(reports.map((row) => row.toJson()).toList());
    await _pump(tester, reports: reports, signals: signals);
    expect(find.byKey(const Key('self-report-rating-chart')), findsNothing);
    expect(find.byKey(const Key('self-report-sleep-chart')), findsNothing);
    expect(
      find.text('2 of 28 dates have a report · 2 answers · 26 missing'),
      findsOneWidget,
    );
    expect(find.text('2026-10-09: 4 / 10'), findsOneWidget);
    expect(find.text('2026-10-10: 8 / 10'), findsOneWidget);
    expect(
      find.text('1 paired answers · 1 answers without a sleep match'),
      findsOneWidget,
    );
    expect(
      find.text('2026-10-09: 4 / 10 · 6.5 hours of sleep'),
      findsOneWidget,
    );
    expect(
      find.text('Manual entry · Availability time unknown'),
      findsOneWidget,
    );
    await _expandRecords(tester);
    expect(
      find.text('No matching self-report on this date.'),
      findsNWidgets(26),
    );
    expect(
      find.text('No eligible main sleep in the preceding 24 hours.'),
      findsOneWidget,
    );
    expect(jsonEncode(reports.map((row) => row.toJson()).toList()), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selectors independently filter measure, period and language', (
    tester,
  ) async {
    await _pump(
      tester,
      reports: [
        for (var day = 0; day < 8; day++)
          _report(daysAgo: day, focus: day == 0 ? 3 : null),
        _report(period: CheckInPeriod.evening, energy: 9, focus: 8),
        _report(language: 'es', energy: 2, focus: 7),
      ],
      signals: [for (var day = 0; day < 8; day++) _sleep(day)],
    );
    expect(find.byKey(const Key('self-report-rating-chart')), findsOneWidget);
    expect(find.byKey(const Key('self-report-sleep-chart')), findsOneWidget);
    await _tap(tester, 'self-report-trend-measure-focus');
    expect(find.byKey(const Key('self-report-rating-chart')), findsNothing);
    expect(
      find.text('8 of 28 dates have a report · 1 answers · 27 missing'),
      findsOneWidget,
    );
    expect(find.text('2026-10-10: 3 / 10'), findsOneWidget);
    await _tap(tester, 'self-report-trend-period-evening');
    expect(find.text('2026-10-10: 8 / 10'), findsOneWidget);
    await _tap(tester, 'self-report-trend-language-es');
    expect(
      find.text('No matching self-reports in this window.'),
      findsOneWidget,
    );
    await _tap(tester, 'self-report-trend-period-morning');
    expect(find.text('2026-10-10: 7 / 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and synthetic histories never produce charts or ratings', (
    tester,
  ) async {
    await _pump(tester, reports: [_report(id: 'syn-untrusted')]);
    expect(
      find.text('No matching self-reports in this window.'),
      findsOneWidget,
    );
    expect(find.text('No paired answers in this window.'), findsOneWidget);
    expect(find.byKey(const Key('self-report-rating-chart')), findsNothing);
    expect(find.byKey(const Key('self-report-sleep-chart')), findsNothing);
    expect(find.byType(ChoiceChip), findsNWidgets(12));
  });

  testWidgets('chart summaries and per-date records are accessible', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      reports: [
        for (var day = 0; day < 8; day++)
          _report(daysAgo: day, energy: 2 + day.toDouble()),
      ],
      signals: [for (var day = 0; day < 8; day++) _sleep(day)],
    );
    await tester.ensureVisible(
      find.byKey(const Key('self-report-rating-chart')),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        RegExp(r'Raw Energy ratings, 1–10\. 8 answered dates'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const Key('self-report-sleep-chart')),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp(r'8 paired records\. Horizontal axis')),
      findsOneWidget,
    );
    await _expandRecords(tester);
    expect(
      find.byKey(const Key('self-report-trend-record-2026-10-10')),
      findsOneWidget,
    );
    expect(find.text('Energy: 2 / 10'), findsOneWidget);
    expect(
      find.text('No matching self-report on this date.'),
      findsNWidgets(20),
    );
    semantics.dispose();
  });

  testWidgets(
    'identical sleep pairs retain exact records without overplotting',
    (tester) async {
      await _pump(
        tester,
        reports: [for (var day = 0; day < 8; day++) _report(daysAgo: day)],
        signals: [
          for (var day = 0; day < 8; day++) _sleep(day).copyWith(value: 7.25),
        ],
      );
      expect(find.byKey(const Key('self-report-sleep-chart')), findsNothing);
      expect(
        find.text('These paired records have no variation to compare.'),
        findsOneWidget,
      );
      expect(
        find.text('2026-10-10: 6 / 10 · 7.25 hours of sleep'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'synthetic screenshot QA',
    (tester) async {
      await tester.runAsync(() async {
        await loadAppearanceFonts();
        const cjkPath = String.fromEnvironment('TRENDS_CJK_FONT');
        if (cjkPath.isNotEmpty) {
          final cjk = FontLoader('TrendsCjk')
            ..addFont(File(cjkPath).readAsBytes().then(ByteData.sublistView));
          await cjk.load();
        }
      });
      for (final largeText in [false, true]) {
        await _pump(
          tester,
          reports: [
            for (var day = 0; day < 9; day++)
              _report(daysAgo: day, energy: 1 + day.toDouble()),
          ],
          signals: [for (var day = 0; day < 9; day++) _sleep(day)],
          largeText: largeText,
          realFont: true,
        );
        if (!largeText) {
          await _capture(
            tester,
            'trends-qa-card',
            '/tmp/self-report-trends-full-390.png',
          );
        }
        for (final kind in ['rating', 'sleep']) {
          await Scrollable.ensureVisible(
            tester.element(find.byKey(Key('self-report-$kind-chart'))),
            alignment: .3,
          );
          await tester.pumpAndSettle();
          await _capture(
            tester,
            'trends-qa-viewport',
            '/tmp/self-report-trends-$kind-${largeText ? '320-large' : '390'}.png',
          );
        }
      }
    },
    skip: !const bool.fromEnvironment('CAPTURE_TRENDS_QA'),
  );

  for (final brightness in Brightness.values) {
    for (final language in ['en', 'es', 'zh-Hans', 'zh-Hant']) {
      testWidgets(
        '${brightness.name} $language charts fit 320 pixels at double text size',
        (tester) async {
          await _pump(
            tester,
            reports: [
              for (var day = 0; day < 9; day++)
                _report(
                  daysAgo: day,
                  energy: 1 + day.toDouble(),
                  language: language,
                ),
            ],
            signals: [for (var day = 0; day < 9; day++) _sleep(day)],
            language: language,
            brightness: brightness,
            largeText: true,
          );
          expect(
            find.byKey(const Key('self-report-rating-chart')),
            findsOneWidget,
          );
          expect(
            find.text(AppLocalizations(language).text('Self-report trends')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('self-report-sleep-chart')),
            findsOneWidget,
          );
          final scrollable = find.byType(Scrollable).first;
          for (var attempt = 0; attempt < 80; attempt++) {
            expect(tester.takeException(), isNull);
            final position = tester.state<ScrollableState>(scrollable).position;
            if (position.extentAfter == 0) break;
            await tester.drag(
              find.byType(SingleChildScrollView),
              const Offset(0, -500),
            );
            await tester.pumpAndSettle();
          }
          expect(
            tester.state<ScrollableState>(scrollable).position.extentAfter,
            0,
          );
          await _expandRecords(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String key, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(Key(key)),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _expandRecords(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(ExpansionTile));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ExpansionTile));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  required List<DailyCheckIn> reports,
  List<SignalReading> signals = const [],
  String language = 'en',
  Brightness brightness = Brightness.light,
  bool largeText = false,
  bool realFont = false,
}) async {
  tester.view.physicalSize = Size(largeText ? 320 : 390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: localeForLanguage(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _theme(brightness, realFont),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(largeText ? 2 : 1)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: const Key('trends-qa-viewport'),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: RepaintBoundary(
              key: const Key('trends-qa-card'),
              child: SelfReportTrendsCard(
                checkIns: reports,
                signals: signals,
                now: _now,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ThemeData _theme(Brightness brightness, bool realFont) {
  final theme = buildTonyoTheme(
    brightness: brightness,
    font: realFont ? TonyoFont.inter : TonyoFont.system,
  );
  return realFont
      ? theme.copyWith(
          textTheme: theme.textTheme.apply(
            fontFamilyFallback: const ['TrendsCjk'],
          ),
        )
      : theme;
}
