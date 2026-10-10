import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/device_timezone_service.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/models.dart';
import 'package:app/src/self_report_reference_logic.dart';
import 'package:app/src/theme.dart';
import 'package:app/src/widgets/self_report_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

final _now = DateTime.utc(2026, 10, 10, 20);

DailyCheckIn _report({
  int daysAgo = 0,
  CheckInPeriod period = CheckInPeriod.morning,
  double? energy = 4,
  double? fatigue = 6,
  String language = 'en',
}) {
  final stamp = _now.subtract(Duration(days: daysAgo));
  return DailyCheckIn(
    id: 'report-$daysAgo-${period.name}',
    timestamp: stamp,
    recordedAt: stamp,
    localDate: stamp.toIso8601String().substring(0, 10),
    utcOffsetMinutes: 0,
    timezone: 'Etc/UTC',
    period: period,
    energy: energy,
    fatigue: fatigue,
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Today preserves raw answers and shows independent references', (
    tester,
  ) async {
    final current = _report(energy: 5, fatigue: null);
    final rows = [
      current,
      for (var day = 1; day <= 7; day++) _report(daysAgo: day),
    ];
    final original = jsonEncode(rows.map((item) => item.toJson()).toList());
    await _pump(tester, rows);
    expect(find.text('Energy: 5 / 10'), findsOneWidget);
    expect(find.text('Fatigue: Not answered'), findsOneWidget);
    await _expand(tester);
    expect(find.text('Energy average: 4.0 / 10'), findsOneWidget);
    expect(find.text('Fatigue average: 6.0 / 10'), findsOneWidget);
    expect(find.text('7 days with an answer'), findsNWidgets(2));
    expect(find.text('Higher than your recent average'), findsOneWidget);
    expect(
      find.text('Today’s answer is missing; no comparison.'),
      findsNWidgets(5),
    );
    expect(find.text('Sleepiness: Not enough history'), findsOneWidget);
    expect(find.text('0 of 7 days needed'), findsNWidgets(4));
    expect(
      find.text('Previous 28 days · 2026-09-12 to 2026-10-09 · Excludes today'),
      findsOneWidget,
    );
    expect(jsonEncode(rows.map((item) => item.toJson()).toList()), original);
    expect(tester.takeException(), isNull);
  });

  for (final higherHistory in [true, false]) {
    testWidgets(
      'small ${higherHistory ? 'lower' : 'higher'} comparison remains visible after rounding',
      (tester) async {
        await _pump(tester, [
          _report(energy: 6),
          for (var day = 1; day <= 21; day++)
            _report(
              daysAgo: day,
              energy: day == 21 ? (higherHistory ? 7 : 5) : 6,
            ),
        ]);
        await _expand(tester);
        expect(
          find.text('Energy average: ${higherHistory ? '6.05' : '5.95'} / 10'),
          findsOneWidget,
        );
        expect(
          find.text(
            higherHistory
                ? 'Lower than your recent average'
                : 'Higher than your recent average',
          ),
          findsOneWidget,
        );
        expect(find.text('Energy average: 6.0 / 10'), findsNothing);
      },
    );
  }

  testWidgets('six days with many submissions do not show an average', (
    tester,
  ) async {
    final rows = [
      _report(),
      for (var day = 1; day <= 6; day++) ...[
        _report(daysAgo: day),
        _report(daysAgo: day),
        _report(daysAgo: day, period: CheckInPeriod.evening, energy: 10),
      ],
    ];
    await _pump(tester, rows);
    await _expand(tester);
    expect(find.text('Energy: Not enough history'), findsOneWidget);
    expect(find.text('6 of 7 days needed'), findsNWidgets(2));
    expect(find.textContaining('Energy average:'), findsNothing);
  });

  testWidgets(
    'legacy questionnaire keeps raw display without a new reference',
    (tester) async {
      await _pump(tester, [
        DailyCheckIn(
          id: 'earlier',
          timestamp: _now,
          energy: 8,
          mood: 7,
          stress: 2,
        ),
        for (var day = 1; day <= 7; day++) _report(daysAgo: day),
      ]);
      await _expand(tester);
      expect(find.text('Energy: 8 / 10'), findsOneWidget);
      expect(
        find.text('Comparison is unavailable for this questionnaire format.'),
        findsOneWidget,
      );
      expect(find.textContaining('Energy average:'), findsNothing);
    },
  );

  testWidgets(
    'Today waits for recording availability before displaying a report',
    (tester) async {
      final pending = DailyCheckIn.fromJson({
        ..._report().toJson(),
        'recordedAt': _now.add(const Duration(hours: 1)).toIso8601String(),
      });
      await _pump(tester, [pending]);
      expect(find.text('No self-report recorded for today.'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
    },
  );

  for (final language in ['en', 'es', 'zh-Hans', 'zh-Hant']) {
    testWidgets('$language references fit at 320 pixels and double text size', (
      tester,
    ) async {
      await _pump(
        tester,
        [
          _report(language: language, energy: 9),
          for (var day = 1; day <= 7; day++)
            _report(daysAgo: day, language: language),
        ],
        language: language,
        largeText: true,
      );
      await _expand(tester);
      final tr = AppLocalizations(language);
      expect(
        find.text(tr.text('Higher than your recent average')),
        findsOneWidget,
      );
      expect(
        find.text(
          tr.text(
            '{measure} average: {value} / 10',
            args: {
              'measure': tr.text('Energy'),
              'value': language == 'es' ? '4,0' : '4.0',
            },
          ),
        ),
        findsOneWidget,
      );
      final scrollable = find.byType(Scrollable).first;
      for (var i = 0; i < 30; i++) {
        expect(tester.takeException(), isNull);
        final position = tester.state<ScrollableState>(scrollable).position;
        if (position.extentAfter == 0) break;
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
      }
      expect(tester.state<ScrollableState>(scrollable).position.extentAfter, 0);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'local reload, edits and deletion recompute references without model inputs',
    () async {
      var clock = _now.subtract(const Duration(days: 7));
      AppController controller() {
        final app = AppController(
          clock: () => clock,
          initialPrivacyConsent: testAdultPrivacyConsent,
          deviceTimezoneService: DeviceTimezoneService(
            clock: () => clock,
            readIdentifier: () async => 'Etc/UTC',
          ),
        );
        addTearDown(app.dispose);
        return app;
      }

      final first = controller();
      await first.load();
      for (var day = 7; day >= 0; day--) {
        clock = _now.subtract(Duration(days: day));
        await first.saveSelfReportCheckIn(
          id: 'saved-$day',
          period: CheckInPeriod.morning,
          energy: day == 0 ? 9 : 4,
          fatigue: 6,
          questionnaireLanguage: 'en',
          questionnaireSnapshot: CheckInMeasurement.snapshot(
            language: 'en',
            translate: (text) => text,
          ),
        );
      }
      final restarted = controller();
      await restarted.load();
      SelfReportReferenceMetric metric(AppController app, String id) =>
          SelfReportReferenceLogic.build(
            checkIns: app.checkIns,
            current: app.checkIns.singleWhere((row) => row.id == 'saved-0'),
            asOf: clock,
          ).metrics[id]!;
      expect(metric(restarted, 'energy').average, 4);
      expect(metric(restarted, 'energy').sampleCount, 7);
      await restarted.saveSelfReportCheckIn(
        id: 'saved-1',
        period: CheckInPeriod.morning,
        fatigue: 3,
        questionnaireLanguage: 'en',
        questionnaireSnapshot: CheckInMeasurement.snapshot(
          language: 'en',
          translate: (text) => text,
        ),
      );
      expect(metric(restarted, 'energy').average, isNull);
      expect(metric(restarted, 'energy').sampleCount, 6);
      expect(metric(restarted, 'fatigue').sampleCount, 7);
      await restarted.deleteCheckIn('saved-2');
      final afterDeletion = controller();
      await afterDeletion.load();
      expect(metric(afterDeletion, 'energy').sampleCount, 5);
      expect(metric(afterDeletion, 'fatigue').average, isNull);
      expect(afterDeletion.outcomes, isEmpty);
      expect(afterDeletion.score.canEstimateEnergy, isFalse);
      expect(afterDeletion.score.canEstimateCognitive, isFalse);
    },
  );
}

Future<void> _expand(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(ExpansionTile));
  await tester.tap(find.byType(ExpansionTile));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  List<DailyCheckIn> rows, {
  String language = 'en',
  bool largeText = false,
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
      theme: buildTonyoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(largeText ? 2 : 1)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: TodaySelfReportCard(checkIns: rows, now: _now),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
