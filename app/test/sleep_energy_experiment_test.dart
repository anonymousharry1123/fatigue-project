import 'dart:convert';

import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/models.dart';
import 'package:app/src/sleep_energy_experiment.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _at(int day, [int hour = 20, int minute = 0]) =>
    DateTime.utc(2026, 10, day, hour, minute);
String _day(int day) => _at(day).toIso8601String().substring(0, 10);
Map<String, dynamic> _definition() =>
    CheckInMeasurement.snapshot(language: 'en', translate: (v) => v);
DailyCheckIn _response(
  int day, {
  String? id,
  double? energy = 6,
  int hour = 20,
  int minute = 0,
  DateTime? savedAt,
  CheckInPeriod period = CheckInPeriod.evening,
  String timezone = 'Etc/UTC',
  Map<String, dynamic>? definition,
}) => DailyCheckIn(
  id: id ?? 'response-$day',
  timestamp: _at(day, hour, minute),
  recordedAt: savedAt ?? _at(day, hour, minute),
  energy: energy,
  fatigue: 4,
  period: period,
  localDate: _day(day),
  timezone: timezone,
  utcOffsetMinutes: 0,
  questionnaireVersion: CheckInMeasurement.currentVersion,
  questionnaireLanguage: 'en',
  questionnaireSnapshot: definition ?? _definition(),
  source: 'selfReport',
);
SignalReading _sleep(
  int day, {
  double? hours,
  SignalSource source = SignalSource.manual,
  DateTime? savedAt,
  bool unknownAvailability = false,
  int hour = 8,
}) => SignalReading(
  id: 'sleep-$day',
  type: SignalType.sleep,
  value: hours ?? 5.0 + day % 4,
  timestamp: _at(day, hour),
  source: source,
  recordedAt: unknownAvailability ? null : savedAt ?? _at(day, hour),
);
SignalReading _activity(
  int day, {
  double value = 1,
  DateTime? savedAt,
  String? id,
}) => SignalReading(
  id: id ?? 'exercise-$day',
  groupId: 'activity-$day',
  type: SignalType.exercise,
  value: value,
  timestamp: _at(day, 19),
  recordedAt: savedAt ?? _at(day, 19),
);
SleepEnergyReadiness _prepare(
  List<DailyCheckIn> reports,
  List<SignalReading> signals, {
  DateTime? now,
}) => SleepEnergyExperiment.prepare(
  checkIns: reports,
  signals: signals,
  now: now ?? _at(31, 23),
);
SleepEnergyRun _train(
  List<DailyCheckIn> reports,
  List<SignalReading> signals, {
  DateTime? now,
}) => SleepEnergyExperiment.train(
  _prepare(reports, signals, now: now),
  trainedAt: now ?? _at(31, 23),
);

void main() {
  test(
    'first Evening is selected before Energy; later response cannot fill missing target',
    () {
      final readiness = _prepare(
        [
          _response(1, energy: null, hour: 19),
          _response(1, id: 'later', energy: 8),
          _response(2, period: CheckInPeriod.morning),
          _response(3, id: 'demo-response'),
          DailyCheckIn(id: 'legacy', timestamp: _at(4), energy: 4),
        ],
        [_sleep(1), _sleep(2)],
      );
      expect(readiness.pairCount, 0);
      expect(
        readiness.exclusions,
        containsPair('selected_first_response_missing_energy', 1),
      );
      expect(
        readiness.exclusions,
        containsPair('later_compatible_response_same_date', 1),
      );
      expect(
        readiness.exclusions,
        containsPair('incompatible_measurement_source_or_period', 1),
      );
      expect(readiness.exclusions, containsPair('export_synthetic', 1));
      expect(readiness.exclusions, containsPair('export_legacy', 1));
    },
  );

  test(
    'missing Energy still reserves sleep before next local-date selection',
    () {
      final readiness = _prepare(
        [
          _response(1, energy: null, hour: 23, minute: 30),
          _response(2, hour: 0, minute: 30),
        ],
        [_sleep(1, hour: 23)],
      );
      expect(readiness.pairCount, 0);
      expect(readiness.exclusions['selected_first_response_missing_energy'], 1);
      expect(
        readiness.exclusions['sleep_already_selected_by_earlier_response'],
        1,
      );
    },
  );

  test(
    'timezone, availability, raw demo and ambiguous main sleep fail closed',
    () {
      final readiness = _prepare(
        [
          _response(1, timezone: 'Unknown/Zone'),
          _response(2),
          _response(3),
          _response(4),
        ],
        [
          _sleep(1),
          _sleep(2, unknownAvailability: true),
          _sleep(3).copyWith(id: 'syn-sleep'),
          _sleep(4),
          _sleep(4).copyWith(id: 'second-sleep', timestamp: _at(4, 7)),
        ],
      );
      expect(readiness.pairCount, 0);
      expect(
        readiness.exclusions['invalid_response_date_timezone_or_timing'],
        1,
      );
      expect(readiness.exclusions['sleep_availability_unknown'], 1);
      expect(readiness.exclusions['selected_response_sleep_unmatched'], 2);
    },
  );

  test(
    'retrospective saved-after-outcome sleep allowed; activity comparison excludes it',
    () {
      final readiness = _prepare(
        [_response(2)],
        [_sleep(2, savedAt: _at(2, 22)), _activity(1)],
      );
      expect(readiness.pairCount, 1);
      expect(readiness.pairs.single.activityHours, isNull);
    },
  );

  test('wording, timezone and sleep source remain separate cohorts', () {
    final changed = _definition();
    (changed['items'] as List).first['label'] = 'Current Energy';
    final readiness = _prepare(
      [
        _response(1),
        _response(2, definition: changed),
        _response(3, timezone: 'UTC'),
        _response(4),
      ],
      [
        _sleep(1),
        _sleep(2),
        _sleep(3),
        _sleep(4, source: SignalSource.healthKit),
      ],
    );
    expect(readiness.pairCount, 4);
    expect(readiness.cohorts, hasLength(4));
    expect(readiness.cohorts.map((c) => c.pairCount), everyElement(1));
  });

  test(
    'chronological ceil20% holdout uses OLS and frozen training baselines',
    () {
      final reports = [
        for (var d = 1; d <= 6; d++)
          _response(d, energy: [2.0, 4.0, 6.0, 8.0, 7.0, 9.0][d - 1]),
      ];
      final sleeps = [
        for (var d = 1; d <= 6; d++) _sleep(d, hours: (d + 3).toDouble()),
      ];
      final run = _train(reports.reversed.toList(), sleeps);
      final fit = run.fits.single;
      expect(fit.trainingCount, 4);
      expect(fit.holdoutCount, 2);
      expect(fit.trainingEndDate, _day(4));
      expect(fit.holdoutStartDate, _day(5));
      expect(fit.slope, closeTo(2, 1e-12));
      expect(fit.intercept, closeTo(-6, 1e-12));
      expect(fit.trainingMean, 5);
      expect(fit.lastTrainingEnergy, 8);
      expect(fit.modelMae, 2);
      expect(fit.meanMae, 3);
      expect(fit.previousMae, 1);
      // Changing only holdout targets cannot alter fitted coefficients or baselines.
      final changed = _train([
        ...reports.take(4),
        _response(5, energy: 1),
        _response(6, energy: 1),
      ], sleeps).fits.single;
      expect(changed.slope, fit.slope);
      expect(changed.intercept, fit.intercept);
      expect(changed.trainingMean, fit.trainingMean);
      expect(changed.lastTrainingEnergy, fit.lastTrainingEnergy);
      final restored = SleepEnergyRun.fromJson(
        jsonDecode(jsonEncode(run.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), run.toJson());
    },
  );

  test('too few days or constant training sleep are blocked', () {
    expect(
      _train(
        [_response(1), _response(2)],
        [_sleep(1), _sleep(2)],
      ).fits.single.blocker,
      'fewer_than_two_training_rows',
    );
    final run = _train(
      [for (var d = 1; d <= 5; d++) _response(d)],
      [for (var d = 1; d <= 5; d++) _sleep(d, hours: 7)],
    );
    expect(run.fits.single.blocker, 'no_sleep_variation_in_training');
  });

  test('new dates preserve frozen run, edits/deletion invalidate it', () {
    final reports = [for (var d = 1; d <= 3; d++) _response(d)];
    final sleeps = [for (var d = 1; d <= 3; d++) _sleep(d)];
    final run = _train(reports, sleeps);
    expect(
      SleepEnergyExperiment.isRunCurrent(
        run,
        _prepare([...reports, _response(4)], [...sleeps, _sleep(4)]),
      ),
      isTrue,
    );
    expect(
      SleepEnergyExperiment.isRunCurrent(
        run,
        _prepare(reports.skip(1).toList(), sleeps),
      ),
      isFalse,
    );
    expect(
      SleepEnergyExperiment.isRunCurrent(
        run,
        _prepare([_response(1, energy: 9), ...reports.skip(1)], sleeps),
      ),
      isFalse,
    );
  });

  test(
    'activity requires explicit prior-date manual total known by sleep availability',
    () {
      final readiness = _prepare(
        [for (var d = 2; d <= 6; d++) _response(d)],
        [
          for (var d = 2; d <= 6; d++) _sleep(d),
          _activity(1, value: 0), // Explicit zero is an actual measurement.
          _activity(
            2,
            savedAt: _at(3, 9),
          ), // Too late for day 3 sleep feature cutoff.
          _activity(3),
          _activity(3, id: 'duplicate-total'), // Ambiguous totals.
          _activity(
            4,
          ).copyWith(source: SignalSource.healthKit), // Different semantics.
          // No day 5 activity; missing does not become zero.
        ],
      );
      expect(readiness.pairs.map((p) => p.activityHours), [
        0,
        null,
        null,
        null,
        null,
      ]);
      final comparison = SleepEnergyExperiment.train(
        readiness,
        trainedAt: _at(31),
      ).activityComparisons.single;
      expect(comparison.completePairCount, 1);
      expect(comparison.minimumPairCount, 25);
      expect(comparison.blocker, 'fewer_than_25_complete_pairs');
    },
  );

  test(
    'activity comparison uses identical 20 train / 5 test rows and frozen baselines',
    () {
      final reports = [
        for (var d = 2; d <= 26; d++)
          _response(d, energy: (2 + d % 4 + (d % 3)).toDouble()),
      ];
      final signals = [
        for (var d = 2; d <= 26; d++) _sleep(d),
        for (var d = 1; d <= 25; d++)
          _activity(d, value: ((d + 1) % 3).toDouble()),
      ];
      final comparison = _train(reports, signals).activityComparisons.single;
      expect(comparison.completePairCount, 25);
      expect(comparison.trainingCount, 20);
      expect(comparison.holdoutCount, 5);
      expect(comparison.fitted, isTrue);
      expect(comparison.sleepActivityMae, closeTo(0, 1e-10));
      expect(
        comparison.sleepOnlyMae!,
        greaterThan(comparison.sleepActivityMae!),
      );
      expect(comparison.meanMae, isNotNull);
      expect(comparison.previousMae, isNotNull);
    },
  );

  group('future receipts and immutable evaluation', () {
    late List<DailyCheckIn> reports;
    late List<SignalReading> signals;
    late SleepEnergyRun run;
    late DateTime now;
    SleepEnergyPredictionDraftResult draft({
      List<DailyCheckIn>? rows,
      List<SignalReading>? readings,
      DateTime? at,
    }) {
      final r = rows ?? reports, s = readings ?? signals, time = at ?? now;
      return SleepEnergyExperiment.draftPrediction(
        run: run,
        readiness: _prepare(r, s, now: time),
        checkIns: r,
        signals: s,
        now: time,
        timezone: 'Etc/UTC',
      );
    }

    SleepEnergyPredictionEvaluation evaluate(
      SleepEnergyPrediction p,
      List<DailyCheckIn> rows, {
      List<SignalReading>? readings,
    }) => SleepEnergyExperiment.evaluatePrediction(
      p,
      checkIns: rows,
      signals: readings ?? signals,
      now: _at(4, 23),
    );
    setUp(() {
      reports = [
        for (var d = 1; d <= 3; d++) _response(d, energy: (d + 3).toDouble()),
      ];
      signals = [for (var d = 1; d <= 4; d++) _sleep(d)];
      now = _at(4, 12);
      run = _train(reports, signals, now: now);
    });
    test('a reused history observes exact save times and clock reversals', () {
      final prediction = draft().draft!.withReceipt(now);
      final observed = _at(4, 20);
      final saved = observed.add(const Duration(seconds: 30));
      final history = SleepEnergyHistory(
        checkIns: [...reports, _response(4, savedAt: saved)],
        signals: signals,
        asOf: observed,
      );
      expect(history.readiness.pairCount, 3);
      final beforeSave = saved.subtract(const Duration(microseconds: 1));
      expect(
        history.evaluate([prediction], beforeSave).single.status,
        'awaiting_evening',
      );
      expect(history.evaluate([prediction], saved).single.status, 'scored');
      final beforeReceipt = now.subtract(const Duration(seconds: 1));
      expect(
        history.evaluate([prediction], beforeReceipt).single.reason,
        'invalid_receipt_time',
      );
    });
    test(
      'known sleep, strictly earlier dates, and no Evening answer are required',
      () {
        expect(draft().draft, isNotNull);
        expect(
          draft(
            rows: [...reports, _response(4, energy: null, hour: 10)],
          ).reason,
          'evening_response_already_exists',
        );
        expect(
          draft(
            readings: [
              ...signals.take(3),
              _sleep(4, unknownAvailability: true),
            ],
          ).draft,
          isNull,
        );
        final day3 = SleepEnergyExperiment.draftPrediction(
          run: run,
          readiness: _prepare(reports, signals),
          checkIns: reports.take(2),
          signals: signals,
          now: _at(3, 23),
          timezone: 'Etc/UTC',
        );
        expect(day3.draft, isNull);
      },
    );
    test(
      'pending receipt never scores; receipt is immutable and must precede observation and save',
      () {
        final p = draft().draft!;
        expect(
          evaluate(p, [...reports, _response(4)]).status,
          'pending_receipt',
        );
        final committed = p.withReceipt(now.add(const Duration(seconds: 1)));
        expect(
          () => committed.withReceipt(now.add(const Duration(seconds: 2))),
          throwsStateError,
        );
        final scored = evaluate(committed, [
          ...reports,
          _response(4, energy: 7),
        ]);
        expect(scored.scored, isTrue);
        expect(scored.actual, 7);
        expect(scored.prediction.targetId, 'response-4');
        final early = evaluate(committed, [
          ...reports,
          _response(4, hour: 11, savedAt: _at(4, 20)),
        ]);
        expect(early.status, 'invalidated');
        expect(early.prediction.invalidatedAt, isNotNull);
      },
    );
    test('first compatible target missing Energy never falls back later', () {
      final p = draft().draft!.withReceipt(now.add(const Duration(seconds: 1)));
      final result = evaluate(p, [
        ...reports,
        _response(4, energy: null, hour: 19),
        _response(4, id: 'later', energy: 8),
      ]);
      expect(result.status, 'excluded');
      expect(result.prediction.targetId, 'response-4');
    });
    test(
      'scored target deletion or edit invalidates permanently after serialization',
      () {
        final p = draft().draft!.withReceipt(
          now.add(const Duration(seconds: 1)),
        );
        final target = _response(4, energy: 7);
        final scored = evaluate(p, [...reports, target]).prediction;
        final deleted = evaluate(scored, reports);
        expect(deleted.status, 'invalidated');
        final restored = SleepEnergyPrediction.fromJson(
          jsonDecode(jsonEncode(deleted.prediction.toJson()))
              as Map<String, dynamic>,
        );
        expect(evaluate(restored, [...reports, target]).status, 'invalidated');
        expect(
          evaluate(scored, [...reports, _response(4, energy: 8)]).status,
          'invalidated',
        );
      },
    );
    test(
      'source deletion invalidates permanently and future values remain hidden',
      () {
        final p = draft().draft!.withReceipt(
          now.add(const Duration(seconds: 1)),
        );
        final result = evaluate(p, reports, readings: signals.take(3).toList());
        expect(result.status, 'invalidated');
        expect(result.modelAbsoluteError, isNull);
        expect(
          evaluate(result.prediction, [...reports, _response(4)]).status,
          'invalidated',
        );
      },
    );
    test(
      'saved malformed non-finite predictions and model source are rejected',
      () {
        final p = draft().draft!;
        expect(
          () => SleepEnergyPrediction.fromJson({
            ...p.toJson(),
            'source': 'model',
          }),
          throwsFormatException,
        );
        expect(
          () => SleepEnergyPrediction.fromJson({
            ...p.toJson(),
            'modelPrediction': double.nan,
          }),
          throwsFormatException,
        );
        expect(
          () =>
              SleepEnergyPrediction.fromJson({...p.toJson(), 'sleepHours': 0}),
          throwsFormatException,
        );
      },
    );
  });

  test(
    'conflicting invalid revisions are excluded without attempting serialization',
    () {
      final first = _response(1);
      final invalid = DailyCheckIn(
        id: first.id,
        timestamp: first.timestamp,
        recordedAt: first.recordedAt,
        questionnaireVersion: CheckInMeasurement.currentVersion,
      );
      expect(_prepare([first, invalid], [_sleep(1)]).pairCount, 0);
    },
  );

  test(
    'unusable non-finite sleep inputs cannot contaminate dependencies or crash preparation',
    () {
      final readiness = _prepare(
        [_response(1)],
        [_sleep(1), _sleep(1).copyWith(id: 'broken-sleep', value: double.nan)],
      );
      expect(readiness.pairCount, 1);
      expect(
        () => readiness.pairs.single.definition['language'] = 'changed',
        throwsUnsupportedError,
      );
      final items = readiness.pairs.single.definition['items'] as List;
      expect(
        () => (items.first as Map)['label'] = 'changed',
        throwsUnsupportedError,
      );
    },
  );

  test(
    'saved fits reject contradictory cohort, split, and out-of-range errors',
    () {
      final run = _train(
        [for (var d = 1; d <= 3; d++) _response(d)],
        [for (var d = 1; d <= 3; d++) _sleep(d)],
      );
      final fit = run.fits.single.toJson();
      expect(
        () => SleepEnergyFit.fromJson({...fit, 'sleepSource': 'healthKit'}),
        throwsFormatException,
      );
      expect(
        () => SleepEnergyFit.fromJson({...fit, 'holdoutCount': 2}),
        throwsFormatException,
      );
      expect(
        () => SleepEnergyFit.fromJson({...fit, 'modelMae': -1}),
        throwsFormatException,
      );
      expect(
        () => SleepEnergyRun.fromJson({
          ...run.toJson(),
          'dependencies': <String, String>{},
        }),
        throwsFormatException,
      );
    },
  );
}
