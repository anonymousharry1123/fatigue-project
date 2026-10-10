import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/models.dart';
import 'package:app/src/self_report_reference_logic.dart';
import 'package:flutter_test/flutter_test.dart';

final _currentTime = DateTime.utc(2026, 10, 10, 12);
final _asOf = DateTime.utc(2026, 10, 10, 23);

DailyCheckIn _response(
  String id, {
  int daysAgo = 0,
  Map<String, Object?> changes = const {},
}) {
  final at =
      changes['timestamp'] as DateTime? ??
      _currentTime.subtract(Duration(days: daysAgo));
  final offset = changes['utcOffsetMinutes'] as int? ?? 0;
  final local = at.toUtc().add(Duration(minutes: offset));
  final version = changes.containsKey('questionnaireVersion')
      ? changes['questionnaireVersion'] as String?
      : CheckInMeasurement.currentVersion;
  final language = changes['questionnaireLanguage'] as String? ?? 'en';
  final values = <String, Object?>{
    'energy': 6.0,
    'fatigue': 3.0,
    'sleepiness': null,
    'focus': null,
    'mood': null,
    'stress': null,
    'period': CheckInPeriod.morning,
    'recordedAt': at.add(const Duration(minutes: 1)),
    'localDate': local.toIso8601String().substring(0, 10),
    'timezone': 'Etc/UTC',
    'source': 'selfReport',
    'note': '',
    'questionnaireSnapshot': {
      ...CheckInMeasurement.snapshot(
        language: language,
        translate: (text) => text,
      ),
      'version': version,
    },
    ...changes,
  };
  return DailyCheckIn(
    id: id,
    timestamp: at,
    energy: (values['energy'] as num?)?.toDouble(),
    fatigue: (values['fatigue'] as num?)?.toDouble(),
    sleepiness: (values['sleepiness'] as num?)?.toDouble(),
    focus: (values['focus'] as num?)?.toDouble(),
    mood: (values['mood'] as num?)?.toDouble(),
    stress: (values['stress'] as num?)?.toDouble(),
    period: values['period'] as CheckInPeriod,
    recordedAt: values['recordedAt'] as DateTime?,
    localDate: values['localDate'] as String?,
    timezone: values['timezone'] as String?,
    utcOffsetMinutes: offset,
    questionnaireVersion: version,
    questionnaireLanguage: language,
    source: values['source'] as String?,
    note: values['note'] as String,
    questionnaireSnapshot:
        values['questionnaireSnapshot'] as Map<String, dynamic>?,
    originalLegacyRatings:
        values['originalLegacyRatings'] as Map<String, Object?>?,
    legacyPeriodMissing: values['legacyPeriodMissing'] as bool? ?? false,
  );
}

SelfReportReferenceSummary _build(
  Iterable<DailyCheckIn> history, {
  DailyCheckIn? current,
  DateTime? asOf,
}) => SelfReportReferenceLogic.build(
  checkIns: history,
  current: current ?? _response('current', changes: {'energy': 8}),
  asOf: asOf ?? _asOf,
);

Object? _reverseMaps(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final key in value.keys.toList().reversed)
        key as String: _reverseMaps(value[key]),
    };
  }
  if (value is List) return value.map(_reverseMaps).toList();
  return value;
}

void main() {
  test('averages each item independently without changing raw responses', () {
    final history = [
      for (var day = 1; day <= 8; day++)
        _response(
          'report-$day',
          daysAgo: day,
          changes: {
            'energy': day,
            'fatigue': day == 8 ? null : 3,
            'sleepiness': day <= 6 ? 9 : null,
            'focus': 7,
            'mood': 5,
            'stress': day == 8 ? null : 2,
          },
        ),
    ];
    final rawBefore = history.map((report) => report.toJson()).toList();
    final result = _build(history);
    expect(result.currentCompatible, isTrue);
    expect(result.windowDays, 28);
    expect(result.minimumDays, 7);
    expect(result.startDate, '2026-09-12');
    expect(result.endDate, '2026-10-09');
    expect(result.metrics.keys, DailyCheckIn.measurementIds);
    expect(result.metrics['energy']!.average, 4.5);
    expect(result.metrics['energy']!.sampleCount, 8);
    expect(result.metrics['energy']!.currentValue, 8);
    expect(result.metrics['energy']!.difference, 3.5);
    expect(result.metrics['fatigue']!.average, 3);
    expect(result.metrics['fatigue']!.sampleCount, 7);
    expect(result.metrics['sleepiness']!.sampleCount, 6);
    expect(result.metrics['sleepiness']!.average, isNull);
    expect(result.metrics['sleepiness']!.difference, isNull);
    expect(result.metrics['focus']!.average, 7);
    expect(result.metrics['focus']!.currentValue, isNull);
    expect(result.metrics['focus']!.difference, isNull);
    expect(result.metrics['mood']!.average, 5);
    expect(result.metrics['stress']!.average, 2);
    expect(history.map((report) => report.toJson()).toList(), rawBefore);
  });

  test(
    'withholds averages until seven independent days, never fills missing',
    () {
      final result = _build([
        for (var day = 1; day <= 6; day++)
          _response('report-$day', daysAgo: day, changes: {'energy': null}),
      ]);
      expect(result.metrics['energy']!.sampleCount, 0);
      expect(result.metrics['energy']!.average, isNull);
      expect(result.metrics['energy']!.currentValue, 8);
      expect(result.metrics['energy']!.difference, isNull);
      expect(result.metrics['fatigue']!.sampleCount, 6);
      expect(result.metrics['fatigue']!.average, isNull);
    },
  );

  test('window includes exactly previous 28 captured dates', () {
    final result = _build([
      for (var day = -1; day <= 29; day++)
        _response('report-$day', daysAgo: day),
    ]);
    expect(result.metrics['energy']!.sampleCount, 28);
    expect(result.metrics['energy']!.average, 6);
  });

  test(
    'excludes same-day, future, later-instant, and late-recorded reports',
    () {
      final result = _build([
        _response(
          'earlier-today',
          changes: {
            'timestamp': _currentTime.subtract(const Duration(hours: 2)),
          },
        ),
        _response('future', daysAgo: -1),
        _response('available', daysAgo: 1),
        _response(
          'not-available',
          daysAgo: 2,
          changes: {'recordedAt': _asOf.add(const Duration(seconds: 1))},
        ),
        // A captured date before today's date does not make a future instant
        // eligible when crossing the international date line.
        _response(
          'future-instant',
          changes: {
            'timestamp': _currentTime.add(const Duration(minutes: 30)),
            'utcOffsetMinutes': -840,
          },
        ),
      ]);
      expect(result.metrics['energy']!.sampleCount, 1);
    },
  );

  test(
    'recordedAt equal to asOf is available; one microsecond later is not',
    () {
      final result = _build([
        _response('at-cutoff', daysAgo: 1, changes: {'recordedAt': _asOf}),
        _response(
          'after-cutoff',
          daysAgo: 2,
          changes: {'recordedAt': _asOf.add(const Duration(microseconds: 1))},
        ),
      ]);
      expect(result.metrics['energy']!.sampleCount, 1);
    },
  );

  test('legacy, synthetic, invalid and unknown versions are excluded', () {
    final reports = [
      DailyCheckIn(
        id: 'legacy',
        timestamp: _currentTime.subtract(const Duration(days: 1)),
        energy: 7,
      ),
      _response('seed-report', daysAgo: 2),
      _response('syn-import', daysAgo: 13),
      _response(
        'marked-report',
        daysAgo: 3,
        changes: {'note': 'Synthetic cohort'},
      ),
      _response('wrong-source', daysAgo: 4, changes: {'source': 'model'}),
      _response(
        'unknown',
        daysAgo: 5,
        changes: {'questionnaireVersion': 'next-v2'},
      ),
      _response('fraction', daysAgo: 6, changes: {'energy': 6.5}),
      _response('bad-date', daysAgo: 7, changes: {'localDate': '2026-02-30'}),
      _response('no-recording', daysAgo: 8, changes: {'recordedAt': null}),
      _response('bad-offset', daysAgo: 9, changes: {'utcOffsetMinutes': 900}),
      _response('nan', daysAgo: 10, changes: {'energy': double.nan}),
      _response(
        'legacy-metadata',
        daysAgo: 11,
        changes: {'legacyPeriodMissing': true},
      ),
      _response('valid', daysAgo: 12),
    ];
    expect(_build(reports).metrics['energy']!.sampleCount, 1);
  });

  test(
    'requires matching explicit period, language and exact saved definition',
    () {
      final changed = CheckInMeasurement.snapshot(
        language: 'en',
        translate: (text) => text,
      );
      ((changed['items'] as List).first as Map)['label'] =
          'Changed energy wording';
      final result = _build([
        _response(
          'evening',
          daysAgo: 1,
          changes: {'period': CheckInPeriod.evening},
        ),
        _response(
          'spanish',
          daysAgo: 2,
          changes: {'questionnaireLanguage': 'es'},
        ),
        _response(
          'changed-wording',
          daysAgo: 3,
          changes: {'questionnaireSnapshot': changed},
        ),
        _response('matching', daysAgo: 4),
      ]);
      expect(result.metrics['energy']!.sampleCount, 1);
    },
  );

  test(
    'canonical definition comparison ignores nested map insertion order',
    () {
      final snapshot = CheckInMeasurement.snapshot(
        language: 'en',
        translate: (text) => text,
      );
      final result = _build([
        _response(
          'reordered',
          daysAgo: 1,
          changes: {'questionnaireSnapshot': _reverseMaps(snapshot)},
        ),
      ]);
      expect(result.metrics['energy']!.sampleCount, 1);
    },
  );

  test(
    'latest day submission controls every item including cleared answers',
    () {
      final history = <DailyCheckIn>[];
      for (var day = 1; day <= 7; day++) {
        final earlier = _currentTime.subtract(Duration(days: day));
        history.add(
          _response(
            'earlier-$day',
            changes: {'timestamp': earlier, 'energy': 10, 'fatigue': null},
          ),
        );
        history.add(
          _response(
            'later-$day',
            changes: {
              'timestamp': earlier.add(const Duration(hours: 1)),
              'energy': null,
              'fatigue': 4,
            },
          ),
        );
      }
      final result = _build(history);
      expect(result.metrics['energy']!.sampleCount, 0);
      expect(result.metrics['energy']!.average, isNull);
      expect(result.metrics['fatigue']!.sampleCount, 7);
      expect(result.metrics['fatigue']!.average, 4);
    },
  );

  test(
    'an entirely cleared latest submission does not resurrect earlier day',
    () {
      final at = _currentTime.subtract(const Duration(days: 1));
      final result = _build([
        _response('earlier', changes: {'timestamp': at}),
        _response(
          'cleared',
          changes: {
            'timestamp': at.add(const Duration(hours: 1)),
            'energy': null,
            'fatigue': null,
          },
        ),
      ]);
      expect(result.metrics['energy']!.sampleCount, 0);
      expect(result.metrics['fatigue']!.sampleCount, 0);
    },
  );

  test('duplicate identities use latest revision before eligibility', () {
    for (final replacement in [
      {'energy': null, 'fatigue': 4},
      {'energy': 11},
      {'recordedAt': _asOf.add(const Duration(seconds: 1))},
      {'questionnaireVersion': 'future-v2'},
    ]) {
      final old = _response('same-id', daysAgo: 1);
      final latest = _response(
        'same-id',
        daysAgo: 1,
        changes: {
          'recordedAt': _currentTime.subtract(const Duration(hours: 1)),
          ...replacement,
        },
      );
      expect(_build([old, latest]).metrics['energy']!.sampleCount, 0);
      expect(_build([latest, old]).metrics['energy']!.sampleCount, 0);
    }
  });

  test(
    'submission ties use recordedAt then id, independent of input order',
    () {
      final at = _currentTime.subtract(const Duration(days: 1));
      final reports = [
        _response('z', changes: {'timestamp': at, 'energy': 10}),
        _response(
          'a',
          changes: {
            'timestamp': at,
            'recordedAt': at.add(const Duration(minutes: 2)),
            'energy': 3,
          },
        ),
        _response(
          'b',
          changes: {
            'timestamp': at,
            'recordedAt': at.add(const Duration(minutes: 2)),
            'energy': null,
          },
        ),
      ];
      for (final order in [reports, reports.reversed]) {
        final result = _build(order);
        expect(result.metrics['energy']!.sampleCount, 0);
        expect(result.metrics['fatigue']!.sampleCount, 1);
      }
    },
  );

  test(
    'exact duplicate revision ties resolve deterministically and preserve clearing',
    () {
      final reports = [
        _response('same-id', daysAgo: 1),
        _response('same-id', daysAgo: 1, changes: {'energy': null}),
      ];
      expect(_build(reports).metrics['energy']!.sampleCount, 0);
      expect(_build(reports.reversed).metrics['energy']!.sampleCount, 0);
    },
  );

  test(
    'current identity cannot contribute an older revision to its reference',
    () {
      expect(
        _build([
          _response('current', daysAgo: 1),
        ]).metrics['energy']!.sampleCount,
        0,
      );
    },
  );

  test(
    'invalid, future, legacy or synthetic targets produce no comparison',
    () {
      final targets = [
        DailyCheckIn(id: 'legacy', timestamp: _currentTime, energy: 7),
        _response('demo-target'),
        _response('syn-target'),
        _response('unknown', changes: {'questionnaireVersion': 'unknown-v99'}),
        _response('invalid', changes: {'energy': 0}),
        _response('empty', changes: {'energy': null, 'fatigue': null}),
        _response('future', daysAgo: -1),
        _response(
          'late',
          changes: {'recordedAt': _asOf.add(const Duration(seconds: 1))},
        ),
      ];
      for (final current in targets) {
        final result = _build([
          _response('earlier', daysAgo: 1),
        ], current: current);
        expect(result.currentCompatible, isFalse, reason: current.id);
        for (final metric in result.metrics.values) {
          expect(metric.sampleCount, 0);
          expect(metric.average, isNull);
          expect(metric.currentValue, isNull);
          expect(metric.difference, isNull);
        }
      }
    },
  );

  test(
    'captured dates survive travel across midnight and date-line changes',
    () {
      final current = _response(
        'current',
        changes: {
          'timestamp': DateTime.utc(2026, 10, 9, 16),
          'utcOffsetMinutes': 480,
          'timezone': 'Asia/Shanghai',
        },
      );
      final result = _build([
        _response(
          'prior-local-day',
          changes: {
            'timestamp': DateTime.utc(2026, 10, 9, 15),
            'utcOffsetMinutes': -420,
            'timezone': 'America/Los_Angeles',
          },
        ),
        _response(
          'same-local-day',
          changes: {
            'timestamp': DateTime.utc(2026, 10, 9, 12),
            'utcOffsetMinutes': 840,
            'timezone': 'Pacific/Kiritimati',
          },
        ),
      ], current: current);
      expect(result.startDate, '2026-09-12');
      expect(result.endDate, '2026-10-09');
      expect(result.metrics['energy']!.sampleCount, 1);
    },
  );

  test('DST boundaries count calendar days using each saved offset', () {
    final current = _response(
      'current',
      changes: {
        'timestamp': DateTime.utc(2026, 11, 2, 8, 30),
        'utcOffsetMinutes': -480,
        'timezone': 'America/Los_Angeles',
      },
    );
    final result = _build(
      [
        _response(
          'fall-back-first-hour',
          changes: {
            'timestamp': DateTime.utc(2026, 11, 1, 8, 30),
            'utcOffsetMinutes': -420,
            'timezone': 'America/Los_Angeles',
            'energy': 9,
          },
        ),
        _response(
          'fall-back-second-hour',
          changes: {
            'timestamp': DateTime.utc(2026, 11, 1, 9, 30),
            'utcOffsetMinutes': -480,
            'timezone': 'America/Los_Angeles',
            'energy': null,
          },
        ),
        _response(
          'window-boundary',
          changes: {
            'timestamp': DateTime.utc(2026, 10, 5, 7),
            'utcOffsetMinutes': -420,
            'timezone': 'America/Los_Angeles',
          },
        ),
        _response(
          'outside-window',
          changes: {
            'timestamp': DateTime.utc(2026, 10, 5, 6, 59),
            'utcOffsetMinutes': -420,
            'timezone': 'America/Los_Angeles',
          },
        ),
      ],
      current: current,
      asOf: DateTime.utc(2026, 11, 3),
    );
    expect(result.startDate, '2026-10-05');
    expect(result.endDate, '2026-11-01');
    expect(result.metrics['energy']!.sampleCount, 1);
    expect(result.metrics['fatigue']!.sampleCount, 2);
  });
}
