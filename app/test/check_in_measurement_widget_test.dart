import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/daily_checkin_screen.dart';
import 'package:app/src/screens/today_screen.dart';
import 'package:app/src/theme.dart';
import 'package:app/src/widgets/self_report_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final now = DateTime(2026, 10, 4, 9);
  AppController controller() => AppController(
    initialPrivacyConsent: testAdultPrivacyConsent,
    clock: () => now,
  );

  testWidgets(
    'new self-report has no default answers or period, and permits partial answers',
    (tester) async {
      final app = controller();
      addTearDown(app.dispose);
      await _pump(tester, app, const DailyCheckInScreen());
      expect(find.byType(Slider), findsNothing);
      await tester.tap(find.byKey(const Key('save-checkin')));
      await tester.pumpAndSettle();
      expect(app.checkIns, isEmpty);
      expect(
        find.text('Choose Morning or Evening before saving.'),
        findsWidgets,
      );
      await _tap(tester, 'checkin-period-evening');
      await tester.tap(find.byKey(const Key('save-checkin')));
      await tester.pumpAndSettle();
      expect(app.checkIns, isEmpty);
      expect(
        find.text('Select at least one rating before saving.'),
        findsWidgets,
      );
      await _tap(tester, 'rating-energy-1');
      await _tap(tester, 'skip-energy');
      expect(find.text('Skipped'), findsOneWidget);
      await _tap(tester, 'rating-fatigue-10');
      await tester.tap(find.byKey(const Key('save-checkin')));
      await tester.pumpAndSettle();
      final saved = app.checkIns.single;
      expect(saved.energy, isNull);
      expect(saved.fatigue, 10);
      expect(saved.sleepiness, isNull);
      expect(saved.focus, isNull);
      expect(saved.mood, isNull);
      expect(saved.stress, isNull);
      expect(saved.period, CheckInPeriod.evening);
      expect(
        saved.timestamp,
        now,
      ); // A morning clock must not override the choice.
      expect(saved.completionStatus, 'partial');
      expect(saved.questionnaireVersion, CheckInMeasurement.currentVersion);
      expect(saved.questionnaireLanguage, 'en');
      expect(saved.questionnaireSnapshot!['recallPeriod'], 'right now');
      expect(app.outcomes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all six Spanish answers and the actual displayed draft wording are saved separately',
    (tester) async {
      final app = controller();
      addTearDown(app.dispose);
      await _pump(tester, app, const DailyCheckInScreen(), language: 'es');
      expect(find.text('¿Cómo te sientes ahora mismo?'), findsOneWidget);
      await _tap(tester, 'checkin-period-morning');
      final selections = {
        'energy': 1,
        'fatigue': 10,
        'sleepiness': 8,
        'focus': 2,
        'mood': 7,
        'stress': 3,
      };
      for (final selection in selections.entries) {
        await _tap(tester, 'rating-${selection.key}-${selection.value}');
      }
      await tester.scrollUntilVisible(
        find.byKey(const Key('checkin-note')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const Key('checkin-note')),
        'Save activity',
      );
      await tester.tap(find.byKey(const Key('save-checkin')));
      await tester.pumpAndSettle();
      final saved = app.checkIns.single;
      expect(
        selfReportRatings(saved),
        selections.map((key, value) => MapEntry(key, value.toDouble())),
      );
      expect(saved.note, 'Save activity');
      expect(saved.completionStatus, 'complete');
      expect(saved.questionnaireLanguage, 'es');
      final items = saved.questionnaireSnapshot!['items'] as List;
      expect(items.map((item) => item['id']), selections.keys);
      expect(
        items[1]['prompt'],
        '¿Cuánta fatiga o agotamiento sientes ahora mismo?',
      );
      expect(items[0]['anchors']['1'], 'energía extremadamente baja');
      expect(items[0]['anchors']['5'], 'aproximadamente en la media');
      expect(items[3]['anchors']['10'], 'extremadamente fácil concentrarse');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing a Spanish draft under Chinese UI retains original questions and metadata',
    (tester) async {
      final app = controller();
      addTearDown(app.dispose);
      final spanish = const AppLocalizations('es');
      final snapshot = CheckInMeasurement.snapshot(
        language: 'es',
        translate: spanish.text,
      );
      await app.saveSelfReportCheckIn(
        id: 'original',
        period: CheckInPeriod.evening,
        energy: 7,
        fatigue: 3,
        questionnaireSnapshot: snapshot,
        questionnaireLanguage: 'es',
        timestamp: now.subtract(const Duration(days: 1)),
      );
      final original = app.checkIns.single;
      await _pump(
        tester,
        app,
        DailyCheckInScreen(initialCheckIn: original),
        language: 'zh-Hans',
      );
      await _tap(tester, 'rating-fatigue-8');
      expect(
        find.text('¿Cuánta fatiga o agotamiento sientes ahora mismo?'),
        findsOneWidget,
      );
      expect(find.text('你现在感觉有多疲劳或疲惫？'), findsNothing);
      await tester.tap(find.byKey(const Key('save-checkin')));
      await tester.pumpAndSettle();
      final updated = app.checkIns.single;
      expect(updated.fatigue, 8);
      expect(updated.period, CheckInPeriod.evening);
      expect(updated.timestamp, original.timestamp);
      expect(updated.localDate, original.localDate);
      expect(updated.timezone, original.timezone);
      expect(updated.utcOffsetMinutes, original.utcOffsetMinutes);
      expect(updated.questionnaireLanguage, 'es');
      expect(updated.questionnaireSnapshot, snapshot);
      expect(updated.questionnaireVersion, original.questionnaireVersion);
    },
  );

  testWidgets(
    'legacy edit keeps the original three questions and saved period',
    (tester) async {
      final app = controller();
      addTearDown(app.dispose);
      final original = DailyCheckIn(
        id: 'legacy',
        timestamp: now,
        energy: 6,
        mood: 7,
        stress: 2,
        period: CheckInPeriod.evening,
      );
      app.checkIns = [original];
      await _pump(tester, app, DailyCheckInScreen(initialCheckIn: original));
      expect(find.text('Evening check-in'), findsWidgets);
      expect(find.byKey(const Key('rating-fatigue')), findsNothing);
      await tester.scrollUntilVisible(find.byType(Slider).first, 250);
      tester.widget<Slider>(find.byType(Slider).first).onChanged!(9);
      await tester.pump();
      await tester.tap(find.byKey(const Key('save-checkin')));
      await tester.pumpAndSettle();
      final updated = app.checkIns.single;
      expect(updated.energy, 9);
      expect(updated.mood, 7);
      expect(updated.stress, 2);
      expect(updated.fatigue, isNull);
      expect(updated.questionnaireVersion, isNull);
      expect(updated.period, CheckInPeriod.evening);
      expect(updated.timestamp, original.timestamp);
    },
  );

  testWidgets(
    'Today shows raw separate measures and excludes synthetic records',
    (tester) async {
      final app = controller();
      addTearDown(app.dispose);
      await app.saveSelfReportCheckIn(
        id: 'raw',
        period: CheckInPeriod.morning,
        energy: 2,
        fatigue: 9,
        focus: 8,
        questionnaireSnapshot: CheckInMeasurement.snapshot(
          language: 'en',
          translate: (text) => text,
        ),
        questionnaireLanguage: 'en',
        timestamp: now,
      );
      app.checkIns.add(
        DailyCheckIn(
          id: 'demo-checkin',
          timestamp: now,
          energy: 10,
          mood: 10,
          stress: 1,
          period: CheckInPeriod.evening,
        ),
      );
      await _pump(
        tester,
        app,
        Scaffold(body: TodayScreen(onOpenProfile: () {})),
      );
      expect(find.text('Today’s self-report'), findsOneWidget);
      expect(find.text('Energy: 2 / 10'), findsOneWidget);
      expect(find.text('Fatigue: 9 / 10'), findsOneWidget);
      expect(find.text('Focus: 8 / 10'), findsOneWidget);
      expect(find.text('Sleepiness: Not answered'), findsOneWidget);
      expect(find.text('Evening check-in'), findsNothing);
      expect(find.textContaining('3/6 answered'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('energy-score-card')),
        300,
      );
      expect(find.text('EXPERIMENTAL ESTIMATES'), findsOneWidget);
      expect(find.text('ESTIMATED ENERGY SCORE'), findsOneWidget);
    },
  );

  testWidgets(
    'original 1–5 answers display raw without their compatibility projection',
    (tester) async {
      final app = controller();
      addTearDown(app.dispose);
      final original = DailyCheckIn.fromJson({
        'id': 'original-five',
        'timestamp': now.toUtc().toIso8601String(),
        'energy': 4,
        'mood': 3,
        'stress': 2,
      });
      expect(original.energy, 8); // Internal legacy scoring projection only.
      app.checkIns = [original];
      await _pump(
        tester,
        app,
        Scaffold(body: TodayScreen(onOpenProfile: () {})),
      );
      expect(find.text('Energy: 4 / 5'), findsOneWidget);
      expect(find.text('Energy: 8 / 10'), findsNothing);
      expect(
        find.text('Earlier 1–5 self-report · Original answers'),
        findsOneWidget,
      );
      expect(
        find.text('Earlier check-in (period not recorded)'),
        findsOneWidget,
      );
    },
  );

  testWidgets('old 1–5 and incomplete legacy records are safely read-only', (
    tester,
  ) async {
    final app = controller();
    addTearDown(app.dispose);
    final original = DailyCheckIn.fromJson({
      'id': 'old-five',
      'timestamp': now.toUtc().toIso8601String(),
      'energy': 4,
      'mood': 3,
      'stress': 2,
    });
    await _pump(tester, app, DailyCheckInScreen(initialCheckIn: original));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('save-checkin')))
          .onPressed,
      isNull,
    );
    expect(find.byType(Slider), findsNothing);
    expect(find.text('Energy: 4 / 5'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final incomplete = DailyCheckIn(
      id: 'partial-old',
      timestamp: now,
      energy: 3,
      mood: null,
      stress: 2,
    );
    await _pump(tester, app, DailyCheckInScreen(initialCheckIn: incomplete));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('save-checkin')))
          .onPressed,
      isNull,
    );
    expect(find.text('Mood: Not answered'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today omits seeded, synthetic note and syn cohort records', (
    tester,
  ) async {
    final app = controller();
    addTearDown(app.dispose);
    final synthetic = [
      DailyCheckIn(
        id: 'seed-check',
        timestamp: now,
        energy: 7,
        mood: 7,
        stress: 3,
      ),
      DailyCheckIn(
        id: 'syn-0004-check',
        timestamp: now,
        energy: 7,
        mood: 7,
        stress: 3,
      ),
      DailyCheckIn(
        id: 'marked-note',
        timestamp: now,
        energy: 7,
        mood: 7,
        stress: 3,
        note: 'Synthetic fixture',
      ),
    ];
    await _pump(
      tester,
      app,
      Scaffold(
        body: TodaySelfReportCard(checkIns: synthetic, now: now),
      ),
    );
    expect(find.text('No self-report recorded for today.'), findsOneWidget);
    expect(find.text('Energy: 7 / 10'), findsNothing);
    expect(synthetic.every(selfReportIsSynthetic), isTrue);
  });

  for (final language in ['es', 'zh-Hans', 'zh-Hant']) {
    testWidgets('$language draft cards fit a narrow large-text screen', (
      tester,
    ) async {
      final app = controller();
      addTearDown(app.dispose);
      await _pump(
        tester,
        app,
        const DailyCheckInScreen(),
        language: language,
        largeText: true,
      );
      final scrollable = find.byType(Scrollable).first;
      var previous = -1.0;
      for (var attempt = 0; attempt < 100; attempt++) {
        final position = tester.state<ScrollableState>(scrollable).position;
        if (position.pixels == previous) break;
        previous = position.pixels;
        await tester.drag(find.byType(ListView).first, const Offset(0, -450));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(tester.state<ScrollableState>(scrollable).position.extentAfter, 0);
    });
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  AppController app,
  Widget screen, {
  String language = 'en',
  bool largeText = false,
}) async {
  tester.view.physicalSize = Size(largeText ? 320 : 390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AppScope(
      controller: app,
      child: MaterialApp(
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
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => screen)),
              child: const Text('Open test screen'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open test screen'));
  await tester.pumpAndSettle();
}
