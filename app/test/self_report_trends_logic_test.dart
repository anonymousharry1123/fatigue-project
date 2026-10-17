import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/models.dart';
import 'package:app/src/self_report_trends_logic.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 10, 10, 18);
final _reportTime = DateTime.utc(2026, 10, 10, 10);

DailyCheckIn _report(
  String id, {
  int daysAgo = 0,
  Map<String, Object?> changes = const {},
}) {
  final timestamp =
      changes['timestamp'] as DateTime? ??
      _reportTime.subtract(Duration(days: daysAgo));
  final offset = changes['utcOffsetMinutes'] as int? ?? 0;
  final local = timestamp.toUtc().add(Duration(minutes: offset));
  final language = changes['questionnaireLanguage'] as String? ?? 'en';
  final version = changes.containsKey('questionnaireVersion')
      ? changes['questionnaireVersion'] as String?
      : CheckInMeasurement.currentVersion;
  final fields = <String, Object?>{
    'energy': 7,
    'fatigue': 3,
    'period': CheckInPeriod.morning,
    'recordedAt': timestamp.add(const Duration(minutes: 1)),
    'localDate': local.toIso8601String().substring(0, 10),
    'timezone': 'Etc/UTC',
    'source': 'selfReport',
    'note': '',
    'questionnaireSnapshot': {
      ...CheckInMeasurement.snapshot(
        language: language,
        translate: (value) => value,
      ),
      'version': version,
    },
    ...changes,
  };
  return DailyCheckIn(
    id: id,
    timestamp: timestamp,
    recordedAt: fields['recordedAt'] as DateTime?,
    energy: (fields['energy'] as num?)?.toDouble(),
    fatigue: (fields['fatigue'] as num?)?.toDouble(),
    sleepiness: (fields['sleepiness'] as num?)?.toDouble(),
    focus: (fields['focus'] as num?)?.toDouble(),
    mood: (fields['mood'] as num?)?.toDouble(),
    stress: (fields['stress'] as num?)?.toDouble(),
    period: fields['period'] as CheckInPeriod,
    localDate: fields['localDate'] as String?,
    timezone: fields['timezone'] as String?,
    utcOffsetMinutes: offset,
    questionnaireVersion: version,
    questionnaireLanguage: language,
    source: fields['source'] as String?,
    note: fields['note'] as String,
    questionnaireSnapshot:
        fields['questionnaireSnapshot'] as Map<String, dynamic>?,
    legacyPeriodMissing: fields['legacyPeriodMissing'] as bool? ?? false,
  );
}

SignalReading _sleep(
  String id, {
  DateTime? end,
  double hours = 8,
  SignalSource source = SignalSource.manual,
  SignalType type = SignalType.sleep,
  String? groupId,
  double quality = 1,
  String? note,
  DateTime? syncedAt,
  DateTime? recordedAt,
}) => SignalReading(
  id: id,
  type: type,
  value: hours,
  timestamp: end ?? DateTime.utc(2026, 10, 10, 7),
  source: source,
  groupId: groupId,
  quality: quality,
  note: note,
  syncedAt: syncedAt,
  recordedAt: recordedAt,
);

SelfReportTrendsSummary _build(
  Iterable<DailyCheckIn> checkIns, {
  Iterable<SignalReading> signals = const [],
  CheckInPeriod period = CheckInPeriod.morning,
  String language = 'en',
  DateTime? now,
  String endDate = '2026-10-10',
}) => SelfReportTrendsLogic.build(
  checkIns: checkIns,
  signals: signals,
  now: now ?? _now,
  period: period,
  questionnaireLanguage: language,
  endDate: endDate,
);

SelfReportSleepMatch _match(
  Iterable<SignalReading> signals, {
  DailyCheckIn? report,
  DateTime? asOf,
}) => SelfReportTrendsLogic.matchSleep(
  report ?? _report('report'),
  signals,
  asOf ?? _now,
);

void main() {
  test('28 captured days preserve gaps and six independent raw measures', () {
    final reports = [
      _report(
        'today',
        changes: {'energy': 10, 'fatigue': null, 'sleepiness': 8},
      ),
      _report(
        'two-days',
        daysAgo: 2,
        changes: {'energy': 1, 'focus': 9, 'mood': 6, 'stress': 4},
      ),
      _report('boundary', daysAgo: 27),
      _report('too-old', daysAgo: 28),
    ];
    final raw = reports.map((row) => row.toJson()).toList();
    final result = _build(reports, signals: [_sleep('sleep')]);
    expect(result.startDate, '2026-09-13');
    expect(result.endDate, '2026-10-10');
    expect(result.windowDays, 28);
    expect(result.days, hasLength(28));
    expect(result.selectedReportCount, 3);
    expect(result.series.keys, DailyCheckIn.measurementIds);
    expect(result.days[26].response, isNull);
    expect(result.series['energy']!.values[26], isNull);
    expect(result.series['energy']!.values[25], 1);
    expect(result.series['energy']!.values.last, 10);
    expect(result.series['energy']!.answeredCount, 3);
    expect(result.series['energy']!.matchedCount, 1);
    expect(result.series['fatigue']!.answeredCount, 2);
    expect(result.series['fatigue']!.matchedCount, 0);
    expect(result.series['focus']!.answeredCount, 1);
    expect(result.series['mood']!.values[25], 6);
    expect(result.series['stress']!.values[25], 4);
    expect(result.series['sleepiness']!.matchedCount, 1);
    expect(reports.map((row) => row.toJson()).toList(), raw);
  });

  test('latest daily submission selected before per-item missingness', () {
    final earlier = _report('earlier');
    final later = _report(
      'later',
      changes: {
        'timestamp': _reportTime.add(const Duration(hours: 1)),
        'energy': null,
        'fatigue': 5,
      },
    );
    final result = _build([later, earlier]);
    expect(result.selectedReportCount, 1);
    expect(result.days.last.response!.id, 'later');
    expect(result.series['energy']!.answeredCount, 0);
    expect(result.series['fatigue']!.values.last, 5);
  });

  test(
    'latest cleared or invalid daily submission never revives earlier one',
    () {
      for (final patch in [
        {'energy': null, 'fatigue': null},
        {'energy': 11},
      ]) {
        final result = _build([
          _report('earlier'),
          _report(
            'later',
            changes: {
              'timestamp': _reportTime.add(const Duration(hours: 1)),
              ...patch,
            },
          ),
        ]);
        expect(result.selectedReportCount, 0);
        expect(result.days.last.response, isNull);
      }
    },
  );

  test('duplicate identity collapses before filtering revisions', () {
    for (final replacement in [
      {'energy': null},
      {'questionnaireVersion': 'next-version'},
      {'energy': 0},
      {'recordedAt': _now.add(const Duration(seconds: 1))},
    ]) {
      final reports = [
        _report('same-id'),
        _report('same-id', changes: {'recordedAt': _now, ...replacement}),
      ];
      expect(_build(reports).series['energy']!.answeredCount, 0);
      expect(_build(reports.reversed).series['energy']!.answeredCount, 0);
    }
  });

  test('ties resolve by recording time then ID independently of order', () {
    final reports = [
      _report('z-old-recording'),
      _report('a', changes: {'recordedAt': _now, 'energy': 1}),
      _report('b', changes: {'recordedAt': _now, 'energy': null}),
    ];
    for (final order in [reports, reports.reversed]) {
      final result = _build(order);
      expect(result.days.last.response!.id, 'b');
      expect(result.series['energy']!.values.last, isNull);
    }
  });

  test(
    'latest valid chosen-language definition anchors exact compatibility',
    () {
      final changed = CheckInMeasurement.snapshot(
        language: 'en',
        translate: (text) => text,
      );
      ((changed['items'] as List).first as Map)['prompt'] = 'Different prompt';
      final reversed = <String, dynamic>{
        for (final key in changed.keys.toList().reversed) key: changed[key],
      };
      final reports = [
        _report('old-wording', daysAgo: 2),
        _report(
          'compatible',
          daysAgo: 1,
          changes: {'questionnaireSnapshot': reversed},
        ),
        _report('new-wording', changes: {'questionnaireSnapshot': changed}),
        _report(
          'spanish',
          changes: {
            'questionnaireLanguage': 'es',
            'timestamp': _reportTime.add(const Duration(hours: 1)),
          },
        ),
        _report(
          'evening',
          changes: {
            'period': CheckInPeriod.evening,
            'timestamp': _reportTime.add(const Duration(hours: 2)),
          },
        ),
      ];
      expect(_build(reports).selectedReportCount, 2);
      expect(_build(reports, language: 'es').selectedReportCount, 1);
      expect(
        _build(reports, period: CheckInPeriod.evening).selectedReportCount,
        1,
      );
    },
  );

  test('legacy, demo, invalid and future reports never enter trends', () {
    final reports = [
      DailyCheckIn(id: 'legacy', timestamp: _reportTime, energy: 7),
      _report('syn-target', daysAgo: 1),
      _report('seed-target', daysAgo: 2),
      _report('marked', daysAgo: 3, changes: {'note': 'Synthetic cohort'}),
      _report(
        'unknown',
        daysAgo: 4,
        changes: {'questionnaireVersion': 'unknown'},
      ),
      _report('fraction', daysAgo: 5, changes: {'energy': 1.5}),
      _report('nan', daysAgo: 6, changes: {'energy': double.nan}),
      _report(
        'future',
        changes: {'timestamp': _now.add(const Duration(minutes: 1))},
      ),
      _report(
        'late',
        daysAgo: 7,
        changes: {'recordedAt': _now.add(const Duration(minutes: 1))},
      ),
      _report('invalid-date', daysAgo: 8, changes: {'localDate': '2026-02-30'}),
      _report(
        'legacy-projection',
        daysAgo: 9,
        changes: {'legacyPeriodMissing': true},
      ),
      _report('valid', daysAgo: 10),
    ];
    expect(_build(reports).selectedReportCount, 1);
  });

  test('travel uses captured date and optional current calendar date', () {
    final result = _build([
      _report(
        'travel',
        changes: {
          'timestamp': DateTime.utc(2026, 10, 9, 17),
          'utcOffsetMinutes': 480,
          'timezone': 'Asia/Shanghai',
        },
      ),
    ]);
    expect(result.days.last.date, '2026-10-10');
    expect(result.days.last.response!.id, 'travel');
    expect(() => _build([], endDate: '2026-02-30'), throwsArgumentError);
  });

  test(
    'sleep pairs retain raw duration, end, source and actual availability',
    () {
      final sleep = _sleep(
        'manual',
        hours: 7.25,
        recordedAt: DateTime.utc(2026, 10, 10, 8),
      );
      final before = sleep.toJson();
      final result = _match([sleep]);
      expect(result.isMatched, isTrue);
      expect(result.reading, same(sleep));
      expect(result.durationHours, 7.25);
      expect(result.endTime, sleep.timestamp);
      expect(result.source, SignalSource.manual);
      expect(result.availabilityKnown, isTrue);
      expect(result.availableAt, sleep.recordedAt);
      expect(result.reason, isNull);
      expect(sleep.toJson(), before);
    },
  );

  test(
    'unknown sleep availability is explicit, never replaced by end time',
    () {
      final result = _match([_sleep('unknown-availability')]);
      expect(result.isMatched, isTrue);
      expect(result.availableAt, isNull);
      expect(result.availabilityKnown, isFalse);
    },
  );

  test(
    'retrospective late imports count only once available at viewing time',
    () {
      final sleep = _sleep(
        'health',
        source: SignalSource.healthKit,
        syncedAt: DateTime.utc(2026, 10, 10, 14),
      );
      expect(
        _match([sleep], asOf: DateTime.utc(2026, 10, 10, 13)).isMatched,
        isFalse,
      );
      final later = _match([sleep], asOf: DateTime.utc(2026, 10, 10, 14));
      expect(later.isMatched, isTrue);
      expect(later.availableAt, sleep.syncedAt);
      expect(later.availableAt!.isAfter(_reportTime), isTrue);
    },
  );

  test(
    'sleep end and preceding24hour cutoff are inclusive elapsed instants',
    () {
      for (final end in [
        _reportTime,
        _reportTime.subtract(const Duration(hours: 24)),
      ]) {
        expect(_match([_sleep('boundary', end: end)]).isMatched, isTrue);
      }
      for (final end in [
        _reportTime.add(const Duration(microseconds: 1)),
        _reportTime.subtract(const Duration(hours: 24, microseconds: 1)),
      ]) {
        final result = _match([_sleep('outside', end: end)]);
        expect(result.isMatched, isFalse);
        expect(result.reason, SelfReportTrendsLogic.noSleepReason);
      }
    },
  );

  test(
    'naps, model, synthetic, invalid duration, quality and timing excluded',
    () {
      final invalid = [
        _sleep('nap', type: SignalType.nap),
        _sleep('misclassified-nap', groupId: 'healthkit-nap-123'),
        _sleep('model', source: SignalSource.model),
        _sleep('syn-sleep'),
        _sleep('fixture-sleep'),
        _sleep('group-marked', groupId: 'syn-group'),
        _sleep('noted', note: 'Synthetic cohort'),
        _sleep('short', hours: 0.49),
        _sleep('long', hours: 16.01),
        _sleep('nan', hours: double.nan),
        _sleep('zero-quality', quality: 0),
        _sleep('bad-quality', quality: double.nan),
        _sleep(
          'late-save',
          recordedAt: _now.add(const Duration(microseconds: 1)),
        ),
        _sleep(
          'late-sync',
          syncedAt: _now.add(const Duration(microseconds: 1)),
        ),
        _sleep('impossible-save', recordedAt: DateTime.utc(2026, 10, 10, 6)),
      ];
      for (final sleep in invalid) {
        expect(_match([sleep]).isMatched, isFalse, reason: sleep.id);
      }
    },
  );

  test('invalid or unavailable check-in cannot receive a sleep pair', () {
    for (final report in [
      _report('syn-report'),
      _report('unknown', changes: {'questionnaireVersion': 'future'}),
      _report('invalid', changes: {'energy': 0}),
      _report(
        'late',
        changes: {'recordedAt': _now.add(const Duration(seconds: 1))},
      ),
    ]) {
      final result = _match([_sleep('sleep')], report: report);
      expect(result.isMatched, isFalse);
      expect(result.reason, SelfReportTrendsLogic.ineligibleResponseReason);
    }
  });

  test(
    'sleep identity revisions collapse before availability and validity',
    () {
      final old = _sleep('same-id', recordedAt: DateTime.utc(2026, 10, 10, 8));
      for (final latest in [
        _sleep('same-id', hours: 0, recordedAt: DateTime.utc(2026, 10, 10, 9)),
        _sleep('same-id', recordedAt: _now.add(const Duration(seconds: 1))),
        _sleep(
          'same-id',
          type: SignalType.nap,
          recordedAt: DateTime.utc(2026, 10, 10, 9),
        ),
      ]) {
        expect(_match([old, latest]).isMatched, isFalse);
        expect(_match([latest, old]).isMatched, isFalse);
      }
    },
  );

  test(
    'conflicting same-source summaries and unknown overlap are withheld',
    () {
      for (final rows in [
        [_sleep('a', hours: 8), _sleep('b', hours: 7)],
        [_sleep('a'), _sleep('b', end: DateTime.utc(2026, 10, 10, 6))],
      ]) {
        final result = _match(rows);
        expect(result.isMatched, isFalse);
        expect(result.reason, SelfReportTrendsLogic.ambiguousSleepReason);
      }
    },
  );

  test('identical repeated summaries do not create false ambiguity', () {
    final result = _match([_sleep('a'), _sleep('b')]);
    expect(result.isMatched, isTrue);
    expect(result.durationHours, 8);
  });

  test('only observed bedtime can establish a separate earlier main sleep', () {
    final rows = [
      _sleep('latest', groupId: 'latest-group'),
      _sleep('earlier', end: DateTime.utc(2026, 10, 9, 16), hours: 5),
    ];
    expect(_match(rows).reason, SelfReportTrendsLogic.ambiguousSleepReason);
    final result = _match([
      ...rows,
      _sleep(
        'bedtime',
        type: SignalType.bedtime,
        end: DateTime.utc(2026, 10, 9, 23),
        hours: 23,
        groupId: 'latest-group',
      ),
    ]);
    expect(result.isMatched, isTrue);
    expect(result.reading!.id, 'latest');
    expect(result.availabilityKnown, isFalse);
  });

  test('equivalent bedtime ties keep availability deterministic', () {
    final saved = DateTime.utc(2026, 10, 10, 8);
    final bedtime = _sleep(
      'bedtime-known',
      type: SignalType.bedtime,
      end: DateTime.utc(2026, 10, 9, 23),
      hours: 23,
      groupId: 'latest-group',
      recordedAt: saved,
    );
    final rows = [
      _sleep('latest', groupId: 'latest-group', recordedAt: saved),
      _sleep('earlier', end: DateTime.utc(2026, 10, 9, 16), hours: 5),
      _sleep(
        'bedtime-unknown',
        type: SignalType.bedtime,
        end: bedtime.timestamp,
        hours: 23,
        groupId: bedtime.groupId,
      ),
      bedtime,
    ];
    for (final order in [rows, rows.reversed]) {
      final result = _match(order);
      expect(result.isMatched, isTrue);
      expect(result.availabilityKnown, isTrue);
      expect(result.availableAt, saved);
    }
  });

  test('manual sleep remains preferred without sufficient genuine stages', () {
    final manual = _sleep('manual', hours: 8);
    final health = _sleep(
      'health',
      source: SignalSource.healthKit,
      hours: 7,
      groupId: 'healthkit-sleep-2026-10-10',
    );
    expect(_match([manual, health]).source, SignalSource.manual);
    final sparse = _sleep(
      'core',
      source: SignalSource.healthKit,
      type: SignalType.sleepCore,
      hours: 3,
      groupId: health.groupId,
    );
    expect(_match([manual, health, sparse]).source, SignalSource.manual);
    final fake = _sleep(
      'demo-core',
      source: SignalSource.healthKit,
      type: SignalType.sleepCore,
      hours: 6,
      groupId: health.groupId,
    );
    expect(_match([manual, health, fake]).source, SignalSource.manual);
  });

  test(
    'Health preference uses available compatible stage coverage and duration',
    () {
      final available = DateTime.utc(2026, 10, 10, 8);
      final manual = _sleep('manual', hours: 8, recordedAt: available);
      final stagedAt = DateTime.utc(2026, 10, 10, 14);
      final health = _sleep(
        'health',
        source: SignalSource.healthKit,
        hours: 7,
        groupId: 'healthkit-sleep-2026-10-10',
        syncedAt: available,
      );
      final stage = _sleep(
        'core',
        source: SignalSource.healthKit,
        type: SignalType.sleepCore,
        hours: 4,
        groupId: health.groupId,
        syncedAt: stagedAt,
      );
      final result = _match([manual, health, stage]);
      expect(result.source, SignalSource.healthKit);
      expect(result.durationHours, 7);
      expect(result.availabilityKnown, isTrue);
      expect(result.availableAt, stagedAt);
      expect(
        _match([
          manual,
          health,
          stage,
        ], asOf: DateTime.utc(2026, 10, 10, 12)).source,
        SignalSource.manual,
      );
      final shortHealth = health.copyWith(value: 6);
      expect(_match([manual, shortHealth, stage]).source, SignalSource.manual);
    },
  );

  test('late stage evidence cannot backdate a changed sleep preference', () {
    final saved = DateTime.utc(2026, 10, 10, 8);
    final revised = DateTime.utc(2026, 10, 10, 14);
    final manual = _sleep('manual', recordedAt: saved);
    final health = _sleep(
      'health',
      source: SignalSource.healthKit,
      hours: 7,
      groupId: 'healthkit-sleep-2026-10-10',
      syncedAt: saved,
    );
    final stage = _sleep(
      'core-one',
      source: SignalSource.healthKit,
      type: SignalType.sleepCore,
      hours: 4,
      groupId: health.groupId,
      syncedAt: saved,
    );
    final rows = [
      manual,
      health,
      stage,
      stage.copyWith(id: 'core-two', syncedAt: revised),
    ];
    expect(
      _match(rows, asOf: DateTime.utc(2026, 10, 10, 12)).source,
      SignalSource.healthKit,
    );
    for (final order in [rows, rows.reversed]) {
      final result = _match(order);
      expect(result.source, SignalSource.manual);
      expect(result.reading!.recordedAt, saved);
      expect(result.availabilityKnown, isTrue);
      expect(result.availableAt, revised);
    }
  });

  test('unknown competing sleep availability remains unknown for the pair', () {
    final saved = DateTime.utc(2026, 10, 10, 8);
    final manual = _sleep('manual', recordedAt: saved);
    final health = _sleep(
      'health',
      source: SignalSource.healthKit,
      hours: 7,
      groupId: 'healthkit-sleep-2026-10-10',
    );
    final result = _match([manual, health]);
    expect(result.source, SignalSource.manual);
    expect(result.availabilityKnown, isFalse);
    expect(result.availableAt, isNull);
  });

  test(
    'duplicated or impossible stage totals cannot promote Health summary',
    () {
      final manual = _sleep('manual');
      final health = _sleep(
        'health',
        source: SignalSource.healthKit,
        hours: 7,
        groupId: 'healthkit-sleep-2026-10-10',
      );
      final first = _sleep(
        'core-one',
        source: SignalSource.healthKit,
        type: SignalType.sleepCore,
        hours: 4,
        groupId: health.groupId,
      );
      for (final second in [
        first.copyWith(id: 'core-two'),
        first.copyWith(id: 'rem', type: SignalType.sleepRem),
      ]) {
        expect(
          _match([manual, health, first, second]).source,
          SignalSource.manual,
        );
      }
    },
  );

  test(
    'manual/Health summaries at different ends require observed overlap',
    () {
      final manual = _sleep('manual', groupId: 'manual-group');
      final health = _sleep(
        'health',
        source: SignalSource.healthKit,
        end: DateTime.utc(2026, 10, 10, 8),
        hours: 7,
        groupId: 'healthkit-sleep-2026-10-10',
      );
      expect(
        _match([manual, health]).reason,
        SelfReportTrendsLogic.ambiguousSleepReason,
      );
      final rows = [
        manual,
        health,
        _sleep(
          'manual-bedtime',
          type: SignalType.bedtime,
          end: DateTime.utc(2026, 10, 9, 23),
          hours: 23,
          groupId: manual.groupId,
        ),
        _sleep(
          'health-bedtime',
          type: SignalType.bedtime,
          source: SignalSource.healthKit,
          end: DateTime.utc(2026, 10, 10),
          hours: 0,
          groupId: health.groupId,
        ),
      ];
      expect(_match(rows).source, SignalSource.manual);
    },
  );

  test(
    'DST repeated hour remains one captured day and uses elapsed sleep age',
    () {
      final first = _report(
        'first-hour',
        changes: {
          'timestamp': DateTime.utc(2026, 11, 1, 8, 30),
          'utcOffsetMinutes': -420,
          'timezone': 'America/Los_Angeles',
        },
      );
      final second = _report(
        'second-hour',
        changes: {
          'timestamp': DateTime.utc(2026, 11, 1, 9, 30),
          'utcOffsetMinutes': -480,
          'timezone': 'America/Los_Angeles',
          'energy': null,
        },
      );
      final now = DateTime.utc(2026, 11, 1, 20);
      final result = _build([first, second], now: now, endDate: '2026-11-01');
      expect(result.selectedReportCount, 1);
      expect(result.days.last.response!.id, 'second-hour');
      expect(result.series['energy']!.values.last, isNull);
      final exactly24 = _sleep(
        'cutoff',
        end: second.timestamp.subtract(const Duration(hours: 24)),
      );
      expect(_match([exactly24], report: second, asOf: now).isMatched, isTrue);
      expect(
        _match(
          [
            exactly24.copyWith(
              timestamp: exactly24.timestamp.subtract(
                const Duration(seconds: 1),
              ),
            ),
          ],
          report: second,
          asOf: now,
        ).isMatched,
        isFalse,
      );
    },
  );
}
