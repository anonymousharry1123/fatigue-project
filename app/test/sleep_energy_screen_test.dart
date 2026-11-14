import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/profile_screen.dart';
import 'package:app/src/screens/sleep_energy_screen.dart';
import 'package:app/src/sleep_energy_experiment.dart';
import 'package:app/src/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';
import 'font_test_support.dart';

const _visualReview = bool.fromEnvironment('SLEEP_ENERGY_SCREENSHOTS');

class _Controller extends AppController {
  _Controller()
    : super(
        initialPrivacyConsent: testAdultPrivacyConsent,
        clock: () => DateTime.utc(2026, 10, 10, 12),
      ) {
    checkIns = [for (var day = 1; day <= 5; day++) _report(day)];
    signals = [for (var day = 1; day <= 5; day++) _sleep(day)];
    isReady = true;
    onboardingComplete = true;
  }

  bool inspectable = true;
  bool available = true;
  bool busy = false;
  bool logging = false;
  int refreshes = 0;
  int trainings = 0;
  int captures = 0;
  int clears = 0;
  int revision = 0;
  String? status;
  String? failingAction;
  SleepEnergyRun? savedRun;
  List<SleepEnergyPredictionEvaluation> evaluations = [];

  @override
  int get sessionRevision => revision;
  @override
  bool get sleepEnergyCanInspect => inspectable;
  @override
  SleepEnergyReadiness get sleepEnergyReadiness =>
      SleepEnergyExperiment.prepare(
        checkIns: checkIns,
        signals: signals,
        now: currentTime,
      );
  @override
  bool get sleepEnergyAvailable => available;
  @override
  bool get sleepEnergyBusy => busy;
  @override
  bool get sleepEnergyLoggingEnabled => logging;
  @override
  String? get sleepEnergyStatus => status;
  @override
  String get sleepEnergyPredictionStatus =>
      evaluations.any((result) => result.status == 'awaiting_evening')
      ? 'Prediction saved before check-in.'
      : 'No prediction saved today.';
  @override
  SleepEnergyRun? get sleepEnergyRun => savedRun;
  @override
  List<SleepEnergyPredictionEvaluation> get sleepEnergyProspectiveResults =>
      evaluations;
  @override
  Future<void> refreshSleepEnergyExperiment() async => refreshes++;
  @override
  Future<void> trainSleepEnergyModel() async {
    if (failingAction == 'train') throw StateError('save failed');
    trainings++;
  }

  @override
  Future<void> setSleepEnergyLoggingEnabled(bool value) async {
    if (failingAction == 'logging') throw StateError('save failed');
    logging = value;
    notifyListeners();
  }

  @override
  Future<void> recordSleepEnergyPrediction() async {
    if (failingAction == 'prediction') throw StateError('save failed');
    captures++;
  }

  @override
  Future<void> clearSleepEnergyHistory() async {
    if (failingAction == 'clear') throw StateError('save failed');
    clears++;
    logging = false;
    savedRun = null;
    evaluations = [];
    notifyListeners();
  }

  void refreshView() => notifyListeners();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  _Controller controller() {
    final value = _Controller();
    addTearDown(value.dispose);
    return value;
  }

  testWidgets('readiness opens without training or prediction side effects', (
    tester,
  ) async {
    final app = controller();
    await _pump(tester, app);
    expect(app.refreshes, 1);
    expect(app.trainings, 0);
    expect(app.captures, 0);
    expect(app.logging, isFalse);
    expect(find.text('5 usable sleep–Energy days'), findsOneWidget);
    await _tap(tester, 'sleep-energy-train');
    expect(app.trainings, 1);
    expect(app.captures, 0);
    await _reveal(
      tester,
      find.byKey(const Key('sleep-energy-record-prediction')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('sleep-energy-record-prediction')),
          )
          .onPressed,
      isNull,
    );
    await _tap(tester, 'sleep-energy-logging');
    expect(app.logging, isTrue);
    expect(app.captures, 0);
    await _tap(tester, 'sleep-energy-record-prediction');
    expect(app.captures, 1);
  });

  testWidgets(
    'missing first Energy is explained without pretending data exists',
    (tester) async {
      final app = controller();
      app.checkIns = [_report(1, energy: null), _report(1, later: true)];
      await _pump(tester, app);
      expect(find.text('0 usable sleep–Energy days'), findsOneWidget);
      await _tap(tester, 'sleep-energy-exclusions');
      expect(
        find.textContaining('First evening check-in has no Energy answer'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sleep-energy-train')))
            .onPressed,
        isNull,
      );
      await _reveal(tester, find.text('0 / 25 complete paired days'));
      await tester.pumpAndSettle();
      expect(find.text('Sleep + previous-day activity:'), findsNothing);
    },
  );

  testWidgets(
    'unsupported save capability preserves readiness but disables mutations',
    (tester) async {
      final app = controller()..available = false;
      app.status = 'Saved experiments are unavailable on this device.';
      await _pump(tester, app);
      expect(find.text('5 usable sleep–Energy days'), findsOneWidget);
      await _reveal(tester, find.byKey(const Key('sleep-energy-train')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sleep-energy-train')))
            .onPressed,
        isNull,
      );
      await _reveal(tester, find.byKey(const Key('sleep-energy-logging')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('sleep-energy-logging')),
            )
            .onChanged,
        isNull,
      );
    },
  );

  testWidgets('privacy or session change hides the experiment immediately', (
    tester,
  ) async {
    final app = controller();
    await _pump(tester, app);
    expect(find.text('5 usable sleep–Energy days'), findsOneWidget);
    app.inspectable = false;
    app.refreshView();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sleep-energy-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('sleep-energy-pair-count')), findsNothing);
    expect(find.byKey(const Key('sleep-energy-train')), findsNothing);
  });

  testWidgets('history removal is explicit and keeps source records', (
    tester,
  ) async {
    final app = controller()..logging = true;
    final checks = app.checkIns.toList();
    final sleep = app.signals.toList();
    await _pump(tester, app);
    await _tap(tester, 'sleep-energy-clear');
    expect(app.clears, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(app.clears, 0);
    await _tap(tester, 'sleep-energy-clear');
    await tester.tap(find.byKey(const Key('sleep-energy-clear-confirm')));
    await tester.pumpAndSettle();
    expect(app.clears, 1);
    expect(app.logging, isFalse);
    expect(app.checkIns, checks);
    expect(app.signals, sleep);
  });

  testWidgets(
    'historical results state the test size and stay separate from future days',
    (tester) async {
      final app = controller();
      app.savedRun = SleepEnergyExperiment.train(
        app.sleepEnergyReadiness,
        trainedAt: app.currentTime,
      );
      await _pump(tester, app);
      await _reveal(tester, find.text('Historical test · saved past days'));
      await tester.pumpAndSettle();
      expect(
        find.text('Earlier training days: 4 · later held-out days: 1'),
        findsOneWidget,
      );
      expect(
        find.textContaining('This test has very few days.'),
        findsOneWidget,
      );
      expect(
        find.text('Sleep model: 0.00', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('Training-days average: 0.00', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('Last training rating: 0.00', findRichText: true),
        findsOneWidget,
      );
      await _reveal(
        tester,
        find.byKey(const Key('sleep-energy-no-predictions')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No future-day predictions have been saved.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a history confirmation cannot cross an account change', (
    tester,
  ) async {
    final app = controller();
    await _pump(tester, app);
    await _tap(tester, 'sleep-energy-clear');
    app.revision++;
    app.refreshView();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sleep-energy-clear-confirm')));
    await tester.pumpAndSettle();
    expect(app.clears, 0);
  });

  testWidgets(
    'pending and invalidated predictions hide values; scored cohorts stay separate',
    (tester) async {
      final app = controller();
      app.evaluations = [
        SleepEnergyPredictionEvaluation(
          prediction: _prediction('waiting', model: 9.13),
          status: 'awaiting_evening',
        ),
        SleepEnergyPredictionEvaluation(
          prediction: _prediction('changed', model: 8.43),
          status: 'invalidated',
        ),
        SleepEnergyPredictionEvaluation(
          prediction: _prediction('answered', model: 6.27, day: 9),
          status: 'scored',
          actual: 7,
        ),
        SleepEnergyPredictionEvaluation(
          prediction: _prediction(
            'other-source',
            model: 4.25,
            source: 'healthKit',
          ),
          status: 'scored',
          actual: 8,
        ),
      ];
      await _pump(tester, app);
      await _reveal(
        tester,
        find.byKey(const Key('sleep-energy-hidden-waiting')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Prediction saved before check-in'), findsOneWidget);
      expect(find.textContaining('9.13', findRichText: true), findsNothing);
      expect(find.textContaining('8.43', findRichText: true), findsNothing);
      expect(
        find.text('Sleep model: 0.73', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('Training-days average: 1.75', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('Last training rating: 1.00', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'These comparison values are fixed from the training days.',
        ),
        findsNWidgets(2),
      );
      expect(
        find.textContaining('Previous evening rating', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('Predicted Energy: 6.27 / 10'),
        findsOneWidget,
      );
      expect(
        find.text('Sleep model: 3.75', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Sleep model: 2.24', findRichText: true), findsNothing);
    },
  );

  testWidgets('Profile opens the experiment with the current controller', (
    tester,
  ) async {
    final app = controller();
    await _pump(tester, app, profile: true);
    await tester.scrollUntilVisible(
      find.byKey(const Key('sleep-energy-setting')),
      350,
      scrollable: find.byType(Scrollable).last,
    );
    await _reveal(tester, find.byKey(const Key('sleep-energy-setting')));
    await tester.tap(find.byKey(const Key('sleep-energy-setting')));
    await tester.pumpAndSettle();
    expect(find.byType(SleepEnergyScreen), findsOneWidget);
    expect(
      tester
          .widget<SleepEnergyScreen>(find.byType(SleepEnergyScreen))
          .controller,
      same(app),
    );
    expect(app.trainings, 0);
    expect(app.captures, 0);
  });

  for (final (action, key, message) in [
    (
      'train',
      'sleep-energy-train',
      'Could not save the training result. Please try again.',
    ),
    (
      'logging',
      'sleep-energy-logging',
      'Could not change prediction logging. Please try again.',
    ),
    (
      'prediction',
      'sleep-energy-record-prediction',
      'Could not save the prediction. Please try again.',
    ),
    (
      'clear',
      'sleep-energy-clear',
      'Could not remove experiment history. Please try again.',
    ),
  ]) {
    testWidgets('$action failure is shown without an unhandled exception', (
      tester,
    ) async {
      final app = controller()
        ..logging = action == 'prediction'
        ..failingAction = action;
      await _pump(tester, app);
      await _tap(tester, key);
      if (action == 'clear') {
        await tester.tap(find.byKey(const Key('sleep-energy-clear-confirm')));
        await tester.pumpAndSettle();
      }
      expect(find.text(message), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in ['en', 'es', 'zh-Hans', 'zh-Hant']) {
    testWidgets('$language fits at 320px and 2x text', (tester) async {
      final app = controller();
      app.savedRun = SleepEnergyExperiment.train(
        app.sleepEnergyReadiness,
        trainedAt: app.currentTime,
      );
      app.evaluations = [
        SleepEnergyPredictionEvaluation(
          prediction: _prediction('answered', model: 6.27, day: 9),
          status: 'scored',
          actual: 7,
        ),
      ];
      await _pump(tester, app, language: language, large: true);
      for (final key in [
        'sleep-energy-train',
        'sleep-energy-logging',
        'sleep-energy-record-prediction',
        'sleep-energy-clear',
      ]) {
        await _reveal(tester, find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await _tap(tester, 'sleep-energy-clear');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('synthetic visual review', (tester) async {
    await tester.runAsync(loadAppearanceFonts);
    final app = controller()..logging = true;
    app.savedRun = SleepEnergyExperiment.train(
      app.sleepEnergyReadiness,
      trainedAt: app.currentTime,
    );
    app.evaluations = [
      SleepEnergyPredictionEvaluation(
        prediction: _prediction('waiting', model: 9.13),
        status: 'awaiting_evening',
      ),
      SleepEnergyPredictionEvaluation(
        prediction: _prediction('answered', model: 6.27, day: 9),
        status: 'scored',
        actual: 7,
      ),
    ];
    for (final large in [false, true]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, app, large: large);
      final size = large ? '320-large' : '390';
      await _capture(tester, 'readiness-$size');
      for (final section in [
        'Saved training results',
        'Predictions before check-in',
        'Results on future days',
      ]) {
        await _reveal(tester, find.text(section));
        await Scrollable.ensureVisible(
          tester.element(find.text(section)),
          alignment: .08,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          '${section.toLowerCase().replaceAll(' ', '-')}-$size',
        );
      }
    }
  }, skip: !_visualReview);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('sleep-energy-visual-viewport')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/sleep-energy-review')
      ..createSync(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

DailyCheckIn _report(int day, {double? energy = 7, bool later = false}) {
  final at = DateTime.utc(2026, 10, day, later ? 21 : 20);
  return DailyCheckIn(
    id: 'saved-check-$day-${later ? 2 : 1}',
    timestamp: at,
    recordedAt: at,
    energy: energy,
    fatigue: 4,
    period: CheckInPeriod.evening,
    localDate: '2026-10-${day.toString().padLeft(2, '0')}',
    utcOffsetMinutes: 0,
    timezone: 'Etc/UTC',
    questionnaireVersion: CheckInMeasurement.currentVersion,
    questionnaireLanguage: 'en',
    questionnaireSnapshot: CheckInMeasurement.snapshot(
      language: 'en',
      translate: (value) => value,
    ),
    source: 'selfReport',
  );
}

SleepEnergyPrediction _prediction(
  String id, {
  required double model,
  String source = 'manual',
  int day = 10,
}) => SleepEnergyPrediction(
  id: id,
  localDate: '2026-10-${day.toString().padLeft(2, '0')}',
  createdAt: DateTime.utc(2026, 10, day, 10),
  receiptAt: DateTime.utc(2026, 10, day, 10, 0, 1),
  source: source,
  cohortKey: 'test-$source',
  modelFingerprint: 'model-fingerprint',
  timezone: 'Etc/UTC',
  definition: CheckInMeasurement.snapshot(
    language: 'en',
    translate: (value) => value,
  ),
  sleepId: 'sleep-10',
  sleepFingerprint: 'sleep-fingerprint',
  sleepPairAvailableAt: DateTime.utc(2026, 10, day, 9),
  sleepHours: 8,
  modelPrediction: model,
  meanPrediction: 5.25,
  lastPrediction: 6,
  dependencies: const {'day-1': 'fingerprint'},
);

SignalReading _sleep(int day) => SignalReading(
  id: 'saved-sleep-$day',
  type: SignalType.sleep,
  value: 6 + day / 2,
  timestamp: DateTime.utc(2026, 10, day, 8),
  recordedAt: DateTime.utc(2026, 10, day, 9),
  groupId: 'sleep-day-$day',
);

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: .2);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await _reveal(tester, finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  AppController app, {
  String language = 'en',
  bool large = false,
  bool profile = false,
}) async {
  tester.view.physicalSize = Size(large ? 320 : 390, 1000);
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
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: buildTonyoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const Key('sleep-energy-visual-viewport'),
          child: profile
              ? const Scaffold(body: ProfileScreen())
              : SleepEnergyScreen(controller: app),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
