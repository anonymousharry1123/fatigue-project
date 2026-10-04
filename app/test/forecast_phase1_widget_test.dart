import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/forecast_screen.dart';
import 'package:app/src/widgets/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'privacy_test_support.dart';

class _ForecastController extends AppController {
  _ForecastController(this.snapshot, this.points, {this.windows = const []})
    : super(initialPrivacyConsent: testAdultPrivacyConsent);

  final ScoreSnapshot snapshot;
  final List<ForecastPoint> points;
  @override
  final List<ForecastWindow> windows;

  @override
  ScoreSnapshot get score => snapshot;
  @override
  List<ForecastPoint> forecastDataFor(DateTime day) => points;
  @override
  List<ForecastWindow> windowsFor(DateTime day) => windows;
  @override
  List<ForecastDaySummary> forecastSummariesFor(
    DateTime day, {
    int dayCount = AppController.forecastDayCount,
  }) =>
      points.isEmpty ? const [] : [ForecastDaySummary.fromPoints(day, points)];
}

void main() {
  Future<void> open(
    WidgetTester tester,
    _ForecastController controller, {
    String language = 'en',
  }) async {
    addTearDown(controller.dispose);
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
        home: AppScope(
          controller: controller,
          child: const Scaffold(body: ForecastScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
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

  testWidgets('demo forecast evidence never masquerades as HealthKit import', (
    tester,
  ) async {
    final now = DateTime.now();
    await open(
      tester,
      _ForecastController(
        available,
        points(now),
        windows: [
          ForecastWindow(
            ForecastWindowType.peak,
            now,
            now.add(const Duration(hours: 1)),
            60,
            'Experimental curve',
            evidence: [
              ForecastEvidence(
                id: 'demo-sleep-0',
                kind: ForecastEvidenceKind.signal,
                label: 'Sleep',
                detail:
                    'Main-sleep completion at 8:00 AM; timing only in this curve',
                timestamp: now,
                signalType: SignalType.sleep,
                source: SignalSource.healthKit,
              ),
              ForecastEvidence(
                id: 'health-sleep-import-123',
                kind: ForecastEvidenceKind.signal,
                label: 'Sleep',
                detail:
                    'Main-sleep completion at 7:00 AM; timing only in this curve',
                timestamp: now,
                signalType: SignalType.sleep,
                source: SignalSource.healthKit,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('forecast-evidence-signal-demo-sleep-0')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final demo = find.byKey(const Key('forecast-evidence-signal-demo-sleep-0'));
    expect(
      find.descendant(
        of: demo,
        matching: find.textContaining('Demo / synthetic example'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: demo, matching: find.textContaining('HealthKit')),
      findsNothing,
    );
    final imported = find.byKey(
      const Key('forecast-evidence-signal-health-sleep-import-123'),
    );
    expect(
      find.descendant(of: imported, matching: find.textContaining('HealthKit')),
      findsOneWidget,
    );
  });

  for (final language in ['es', 'zh-Hans', 'zh-Hant']) {
    testWidgets(
      '$language forecast retains translated uncertainty and unavailable-state limits',
      (tester) async {
        final unavailable = FatigueEngine.score(
          signals: const [],
          checkIns: const [],
          now: DateTime.now(),
        );
        final l10n = AppLocalizations(language);
        await open(
          tester,
          _ForecastController(unavailable, const []),
          language: language,
        );
        expect(find.text(l10n.text('No forecast available')), findsOneWidget);
        expect(
          find.text(
            l10n.text(
              'Not enough current information to estimate this range. An optional check-in can add an observation.',
            ),
          ),
          findsOneWidget,
        );
        expect(find.text('No forecast available'), findsNothing);
        await tester.scrollUntilVisible(
          find.text(
            l10n.text(
              'The curve and shaded bands are uncalibrated estimates, not statistical confidence intervals. They do not establish when you will feel alert or tired, or whether exercise is safe.',
            ),
          ),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byType(ForecastChart), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
