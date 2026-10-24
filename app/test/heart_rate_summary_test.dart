import 'dart:convert';

import 'package:app/src/heart_rate_summary.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

SignalReading pulse(
  String id,
  String time, {
  double value = 72,
  double quality = 1,
  SignalType type = SignalType.heartRate,
  SignalSource source = SignalSource.healthKit,
  DateTime? syncedAt,
}) => SignalReading(
  id: id,
  type: type,
  value: value,
  timestamp: DateTime.parse(time),
  source: source,
  quality: quality,
  syncedAt: syncedAt,
);

void main() {
  group('daily cardiac context', () {
    test('raw-only v1 wire format and proof remain unchanged', () {
      final readings = [pulse('a', '2026-10-24T12:00:00Z')];
      final day = HeartRateSummary.build(readings).single;
      expect(day.schemaVersion, 1);
      expect(day.cardiacContext, isNull);
      expect(day.rawContentDigest, HeartRateSummary.contentDigest(readings));
      expect(day.contentDigest, day.rawContentDigest);
      expect(day.toJson(), isNot(contains('rawContentDigest')));
      expect(day.toJson(), isNot(contains('cardiacContext')));
      expect(
        HeartRateDailySummary.fromJson(day.toJson()).toJson(),
        day.toJson(),
      );
    });

    test('native averages exclude derived/manual values and retain counts', () {
      final readings = [
        pulse('raw', '2026-10-24T12:00:00Z'),
        pulse(
          'healthkit-hrv-a',
          '2026-10-24T12:00:00Z',
          type: SignalType.hrv,
          value: 40,
        ),
        pulse(
          'healthkit-hrv-b',
          '2026-10-24T13:00:00Z',
          type: SignalType.hrv,
          value: 60,
        ),
        pulse(
          'HEALTHKIT-HRV-A',
          '2026-10-24T12:00:00Z',
          type: SignalType.hrv,
          value: 40,
        ),
        pulse(
          'manual-hrv',
          '2026-10-24T12:00:00Z',
          type: SignalType.hrv,
          source: SignalSource.manual,
          value: 100,
        ),
        pulse(
          'healthkit-rhr',
          '2026-10-24T12:00:00Z',
          type: SignalType.restingHeartRate,
          value: 62,
        ),
        pulse(
          'derived-hr-resting-2026-10-24',
          '2026-10-24T12:00:00Z',
          type: SignalType.restingHeartRate,
          source: SignalSource.model,
          quality: .5,
          value: 50,
        ),
        pulse(
          'healthkit-prior',
          '2026-10-23T12:00:00Z',
          type: SignalType.hrv,
          value: 100,
        ),
      ];
      final day = HeartRateSummary.build(readings).single;
      expect(day.schemaVersion, 2);
      expect(day.cardiacContext!.hrv!.mean, 50);
      expect(day.cardiacContext!.hrv!.sampleCount, 2);
      expect(day.cardiacContext!.hrv!.source, 'healthKit');
      expect(day.cardiacContext!.restingHeartRate!.mean, 62);
      expect(day.cardiacContext!.restingHeartRate!.sampleCount, 1);
      expect(day.cardiacContext!.restingHeartRate!.source, 'healthKit');
      expect(day.rawContentDigest, HeartRateSummary.contentDigest(readings));
      expect(day.contentDigest, isNot(day.rawContentDigest));
      expect(
        HeartRateDailySummary.fromJson(day.toJson()).toJson(),
        day.toJson(),
      );
      expect(
        HeartRateSummary.build(readings.reversed).single.toJson(),
        day.toJson(),
      );
    });

    test(
      'estimated resting HR fills only a native gap and never becomes HRV',
      () {
        final day = HeartRateSummary.build([
          pulse('raw', '2026-10-24T12:00:00Z'),
          pulse(
            'derived-hr-resting-2026-10-24',
            '2026-10-24T12:00:00Z',
            type: SignalType.restingHeartRate,
            source: SignalSource.model,
            quality: .5,
            value: 50,
          ),
          pulse(
            'invented-proxy',
            '2026-10-24T12:00:00Z',
            type: SignalType.hrv,
            source: SignalSource.model,
            quality: .5,
            value: 50,
          ),
        ]).single;
        expect(day.cardiacContext!.restingHeartRate!.mean, 50);
        expect(
          day.cardiacContext!.restingHeartRate!.source,
          'estimatedFromHeartRate',
        );
        expect(day.cardiacContext!.hrv, isNull);
      },
    );

    List<SignalReading> variationReadings() => [
      for (var index = 0; index < 6; index++)
        pulse(
          'raw-$index',
          DateTime.utc(2026, 10, 24, 15, index * 30).toIso8601String(),
          value: 60 + index * 2.0,
          syncedAt: DateTime.utc(2026, 10, 25),
        ),
    ];
    final provenance = {
      for (var index = 0; index < 6; index++)
        'raw-$index': const HeartRateSampleProvenance(
          offsetMinutes: -420,
          timezoneName: 'America/Los_Angeles',
        ),
    };

    test(
      'variation uses frozen import offsets, not current timezone or reimport time',
      () {
        final raw = variationReadings();
        final first = HeartRateSummary.build(
          raw,
          sampleProvenance: provenance,
        ).single;
        final reimported = HeartRateSummary.build([
          for (final sample in raw)
            sample.copyWith(
              timestamp: sample.timestamp.toLocal(),
              syncedAt: DateTime.utc(2026, 11, 1),
            ),
        ], sampleProvenance: provenance).single;
        expect(first.cardiacContext!.variation!.rmsSuccessiveDifferenceBpm, 2);
        expect(first.cardiacContext!.variation!.sampleCount, 6);
        expect(first.cardiacContext!.variation!.pairCount, 5);
        expect(first.cardiacContext!.variation!.toJson()['unit'], 'bpm');
        expect(first.cardiacContext!.hrv, isNull);
        expect(reimported.contentDigest, first.contentDigest);
        expect(sameHeartRateSummaryStatistics(first, reimported), isTrue);
        expect(
          HeartRateDailySummary.fromJson(first.toJson()).toJson(),
          first.toJson(),
        );
        final historicalNight = HeartRateSummary.build(
          raw,
          sampleProvenance: {
            for (final sample in raw)
              rawHeartRateSampleId(sample): const HeartRateSampleProvenance(
                offsetMinutes: 600,
              ),
          },
        ).single;
        expect(historicalNight.cardiacContext, isNull);
        expect(HeartRateSummary.build(raw).single.cardiacContext, isNull);
      },
    );

    test('context changes its proof while preserving raw cleanup proof', () {
      final raw = variationReadings();
      final first = HeartRateSummary.build([
        ...raw,
        pulse(
          'native',
          '2026-10-24T16:00:00Z',
          type: SignalType.hrv,
          value: 40,
        ),
      ], sampleProvenance: provenance).single;
      final corrected = HeartRateSummary.build([
        ...raw,
        pulse(
          'native',
          '2026-10-24T16:00:00Z',
          type: SignalType.hrv,
          value: 50,
        ),
      ], sampleProvenance: provenance).single;
      expect(first.rawContentDigest, corrected.rawContentDigest);
      expect(first.sampleIdDigest, corrected.sampleIdDigest);
      expect(first.contentDigest, isNot(corrected.contentDigest));
      expect(sameHeartRateSummaryStatistics(first, corrected), isFalse);
      final wire =
          jsonDecode(jsonEncode(first.toJson())) as Map<String, dynamic>;
      (wire['cardiacContext']['hrv'] as Map)['mean'] = 41;
      expect(() => HeartRateDailySummary.fromJson(wire), throwsFormatException);
      final invalidSource =
          jsonDecode(jsonEncode(first.toJson())) as Map<String, dynamic>;
      (invalidSource['cardiacContext']['hrv'] as Map)['source'] =
          'estimatedFromHeartRate';
      expect(
        () => HeartRateDailySummary.fromJson(invalidSource),
        throwsFormatException,
      );
      expect(
        () => HeartRateDailySummary.fromJson({
          ...first.toJson(),
          'rawContentDigest': 'a' * 64,
        }),
        throwsFormatException,
      );
    });
  });

  test(
    'summarizes only ordinary HealthKit pulse and retains hourly detail',
    () {
      final samples = [
        pulse('a', '2026-10-24T01:00:00Z', value: 60),
        pulse('b', '2026-10-24T01:30:00Z', value: 80, quality: 0),
        pulse('c', '2026-10-24T02:30:00.123456Z', value: 70, quality: .5),
        pulse('hrv', '2026-10-24T01:00:00Z', type: SignalType.hrv),
        pulse('rhr', '2026-10-24T01:00:00Z', type: SignalType.restingHeartRate),
        pulse('manual', '2026-10-24T01:00:00Z', source: SignalSource.manual),
      ];
      final summary = HeartRateSummary.build(samples).single;
      expect(summary.id, '2026-10-24');
      expect(summary.sampleCount, 3);
      expect(summary.sum, 210);
      expect(summary.mean, 70);
      expect(summary.min, 60);
      expect(summary.max, 80);
      expect(summary.latestAt.toIso8601String(), '2026-10-24T02:30:00.123456Z');
      expect(summary.latestValue, 70);
      expect(summary.aggregate.qualitySum, 1.5);
      expect(summary.aggregate.qualityMin, 0);
      expect(summary.aggregate.zeroQualityCount, 1);
      expect(summary.hours.map((h) => h.hour), [1, 2]);
      expect(summary.hours.first.count, 2);
      expect(summary.hours.first.sum, 140);
      expect(summary.hours.first.latestValue, 80);
    },
  );

  test('UTC buckets do not change with encoded local offsets or midnight', () {
    final summaries = HeartRateSummary.build([
      pulse('a', '2026-10-24T18:59:59-05:00'),
      pulse('b', '2026-10-25T02:00:00+02:00'),
    ]);
    expect(summaries.map((s) => s.id), ['2026-10-24', '2026-10-25']);
    expect(summaries.first.hours.single.hour, 23);
    expect(summaries.last.hours.single.hour, 0);
    expect(summaries.first.timezoneProvenance['kind'], 'unknown');
    expect(summaries.first.timezoneProvenance['offsetMinutes'], isEmpty);
  });

  test(
    'UUID duplicates and corrected payloads resolve independent of order',
    () {
      final older = pulse(
        'healthkit-ABC',
        '2026-10-24T01:00:00Z',
        value: 60,
        syncedAt: DateTime.utc(2026, 10, 24, 1),
      );
      final newer = pulse(
        ' healthkit-abc ',
        '2026-10-24T01:00:00Z',
        value: 65,
        syncedAt: DateTime.utc(2026, 10, 24, 2),
      );
      final a = HeartRateSummary.build([older, newer, older]).single;
      final b = HeartRateSummary.build([newer, older]).single;
      expect(a.sampleCount, 1);
      expect(a.latestValue, 65);
      expect(a.toJson(), b.toJson());
      expect(
        HeartRateSummary.build([
          pulse('distinct-a', '2026-10-24T01:00:00Z'),
          pulse('distinct-b', '2026-10-24T01:00:01Z'),
        ]).single.sampleCount,
        2,
      );
    },
  );

  test(
    'ID proof remains stable while corrected content changes its digest',
    () {
      final sample = pulse('a', '2026-10-24T01:00:00Z');
      final baseline = HeartRateSummary.build([sample]).single;
      final reimport = HeartRateSummary.build([
        sample.copyWith(syncedAt: DateTime.utc(2026, 10, 25)),
      ]).single;
      final correction = HeartRateSummary.build([
        sample.copyWith(value: 80),
      ]).single;
      expect(reimport.contentDigest, baseline.contentDigest);
      expect(correction.sampleIdDigest, baseline.sampleIdDigest);
      expect(correction.contentDigest, isNot(baseline.contentDigest));
      expect(baseline.contentDigest, matches(RegExp(r'^[a-f0-9]{64}$')));
    },
  );

  test(
    'same-time latest value and digest are deterministic across ordering',
    () {
      final a = pulse('a', '2026-10-24T01:00:00Z', value: 60);
      final b = pulse('b', '2026-10-24T01:00:00Z', value: 80);
      final first = HeartRateSummary.build([a, b]).single;
      final second = HeartRateSummary.build([b, a]).single;
      expect(first.toJson(), second.toJson());
      expect(first.latestValue, 80);
    },
  );

  test(
    'provenance preserves known import zones and labels unknown history',
    () {
      final summary = HeartRateSummary.build(
        [
          pulse('a', '2026-10-24T01:00:00Z'),
          pulse('b', '2026-10-24T02:00:00Z'),
        ],
        sampleProvenance: {
          'a': const HeartRateSampleProvenance(
            offsetMinutes: -420,
            timezoneName: 'America/Los_Angeles',
          ),
        },
      ).single;
      expect(summary.timezoneProvenance, {
        'kind': 'device-local-at-import',
        'zoneNames': ['America/Los_Angeles'],
        'offsetMinutes': [-420],
        'unknownSampleCount': 1,
      });
    },
  );

  test(
    'round trip checks totals and refuses future schema or non-finite data',
    () {
      final summary = HeartRateSummary.build([
        pulse('a', '2026-10-24T01:00:00Z'),
        pulse('b', '2026-10-24T02:00:00Z'),
      ]).single;
      final json =
          jsonDecode(jsonEncode(summary.toJson())) as Map<String, dynamic>;
      expect(HeartRateDailySummary.fromJson(json).toJson(), summary.toJson());
      expect(
        () => HeartRateDailySummary.fromJson({...json, 'schemaVersion': 2}),
        throwsFormatException,
      );
      expect(
        () => HeartRateDailySummary.fromJson({...json, 'sum': 150}),
        throwsFormatException,
      );
      expect(
        () => HeartRateSummary.build([
          pulse('invalid', '2026-10-24T01:00:00Z', quality: double.nan),
        ]),
        throwsFormatException,
      );
    },
  );
}
