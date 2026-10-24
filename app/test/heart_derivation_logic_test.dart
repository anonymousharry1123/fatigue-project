import 'package:app/src/heart_derivation_logic.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 10, 24);
  final now = DateTime(2026, 10, 24, 12);

  SignalReading heart(int minute, double value, {String? id, String? note}) =>
      SignalReading(
        id: id ?? 'healthkit-heart-$minute',
        type: SignalType.heartRate,
        value: value,
        timestamp: day.add(Duration(minutes: minute)),
        source: SignalSource.healthKit,
        note: note ?? 'Apple Health · Oura',
        syncedAt: day.add(const Duration(hours: 9)),
      );

  List<SignalReading> overnight() => [
    heart(60, 60),
    heart(90, 30),
    heart(120, 58),
    heart(150, 62),
    heart(180, 61),
  ];

  HeartDerivationResult derive(Iterable<SignalReading> readings) =>
      HeartDerivationLogic.reconcile(readings: readings, now: now);

  test(
    'sparse overnight samples produce a labelled robust resting estimate',
    () {
      final result = derive(overnight());
      final estimated = result.estimatedRestingHeartRates.single;
      expect(estimated.id, 'derived-hr-resting-2026-10-24');
      expect(estimated.value, 58);
      expect(estimated.timestamp, day.add(const Duration(minutes: 120)));
      expect(estimated.source, SignalSource.model);
      expect(estimated.quality, .5);
      expect(estimated.note, contains('Estimated resting HR'));
      expect(estimated.note, contains('Apple Health · Oura'));
      expect(estimated.recordedAt, now);
      expect(result.days.single.overnightSampleCount, 5);
      expect(
        result.days.single.restingStatus,
        RestingHeartRateDerivationStatus.estimated,
      );
      expect(result.changed, isTrue);
    },
  );

  test(
    'ordinary bpm never creates HRV even with dense regular observations',
    () {
      for (final interval in [1, 30]) {
        final samples = List.generate(
          12,
          (index) => heart(index * interval, 55 + (index % 3).toDouble()),
        );
        final result = derive(samples);
        expect(result.readings.where((r) => r.type == SignalType.hrv), isEmpty);
        expect(
          result.days.single.hrvStatus,
          HeartRateVariabilityAvailability.beatIntervalsRequired,
        );
      }
    },
  );

  test(
    'daytime variation reports successive bpm changes separately from HRV',
    () {
      final result = derive([
        for (var index = 0; index < 6; index++)
          heart(480 + index * 30, index.isEven ? 60 : 64),
      ]);
      final variation = result.days.single.variation!;
      expect(variation.rmsSuccessiveDifferenceBpm, 4);
      expect(variation.sampleCount, 6);
      expect(variation.pairCount, 5);
      expect(variation.start, day.add(const Duration(hours: 8)));
      expect(variation.end, day.add(const Duration(hours: 10, minutes: 30)));
      expect(result.readings.where((r) => r.type == SignalType.hrv), isEmpty);
      expect(result.estimatedRestingHeartRates, isEmpty);
      expect(result.changed, isFalse);
    },
  );

  test('variation rejects short bursts, too few samples and large gaps', () {
    for (final samples in [
      [for (var i = 0; i < 6; i++) heart(480 + i, 60 + i.toDouble())],
      [for (var i = 0; i < 5; i++) heart(480 + i * 30, 60 + i.toDouble())],
      [for (var i = 0; i < 6; i++) heart(480 + i * 60, 60 + i.toDouble())],
    ]) {
      expect(derive(samples).days.single.variation, isNull);
    }
  });

  test('variation excludes changes across gaps and overnight samples', () {
    final samples = [
      ...overnight(),
      for (var i = 0; i < 6; i++) heart(480 + i * 30, 60),
      for (var i = 0; i < 6; i++) heart(720 + i * 30, 100),
    ];
    final variation = HeartDerivationLogic.sampledHeartRateVariation(
      samples,
      now: day.add(const Duration(hours: 16)),
    )!;
    expect(variation.rmsSuccessiveDifferenceBpm, 0);
    expect(variation.sampleCount, 12);
    expect(variation.pairCount, 10);
  });

  test(
    'persisted local timestamp resolver keeps historical variation stable',
    () {
      final samples = [
        for (var i = 0; i < 6; i++) heart(i * 30, i.isEven ? 60 : 64),
      ];
      expect(
        HeartDerivationLogic.sampledHeartRateVariation(samples, now: now),
        isNull,
      );
      final variation = HeartDerivationLogic.sampledHeartRateVariation(
        samples,
        now: now,
        localTimestamp: (reading) =>
            reading.timestamp.add(const Duration(hours: 8)),
      )!;
      expect(variation.rmsSuccessiveDifferenceBpm, 4);
      expect(variation.sampleCount, 6);
      expect(variation.start, samples.first.timestamp);
      expect(variation.end, samples.last.timestamp);
    },
  );

  test('two overnight samples or daytime-only samples do not create RHR', () {
    for (final samples in [
      [heart(60, 58), heart(90, 60)],
      [heart(480, 58), heart(510, 60), heart(540, 59)],
    ]) {
      final result = derive(samples);
      expect(result.estimatedRestingHeartRates, isEmpty);
      expect(
        result.days.single.restingStatus,
        RestingHeartRateDerivationStatus.insufficientSamples,
      );
    }
  });

  test(
    'minimum overnight coverage is required separately for each local day',
    () {
      final result = HeartDerivationLogic.reconcile(
        readings: [
          heart(60, 60),
          heart(90, 58),
          heart(24 * 60 + 60, 62),
          heart(24 * 60 + 90, 61),
        ],
        now: now.add(const Duration(days: 1)),
      );
      expect(result.estimatedRestingHeartRates, isEmpty);
      expect(result.days, hasLength(2));
      expect(result.days.map((day) => day.overnightSampleCount), [2, 2]);
    },
  );

  test('native RHR and HRV win and remove a same-day old estimate', () {
    final estimated = derive(overnight()).estimatedRestingHeartRates.single;
    final nativeRhr = SignalReading(
      id: 'healthkit-native-resting',
      type: SignalType.restingHeartRate,
      value: 57,
      timestamp: day.add(const Duration(hours: 7)),
      source: SignalSource.healthKit,
    );
    final nativeHrv = nativeRhr.copyWith(
      id: 'healthkit-native-hrv',
      type: SignalType.hrv,
      value: 42,
    );
    final result = derive([...overnight(), estimated, nativeRhr, nativeHrv]);
    expect(result.estimatedRestingHeartRates, isEmpty);
    expect(result.readings, containsAll([nativeRhr, nativeHrv]));
    expect(result.readings, isNot(contains(estimated)));
    expect(
      result.days.single.restingStatus,
      RestingHeartRateDerivationStatus.native,
    );
    expect(
      result.days.single.hrvStatus,
      HeartRateVariabilityAvailability.native,
    );
  });

  test('manual resting measurement also keeps the day free of estimates', () {
    final manual = SignalReading(
      id: 'manual-resting',
      type: SignalType.restingHeartRate,
      value: 57,
      timestamp: day.add(const Duration(hours: 7)),
    );
    final result = derive([...overnight(), manual]);
    expect(result.estimatedRestingHeartRates, isEmpty);
    expect(result.readings, contains(manual));
    expect(
      result.days.single.restingStatus,
      RestingHeartRateDerivationStatus.existingMeasurement,
    );
  });

  test(
    'idempotent derivation preserves original save and import availability',
    () {
      final initial = derive(overnight());
      final repeated = HeartDerivationLogic.reconcile(
        readings: initial.readings,
        now: now.add(const Duration(hours: 2)),
      );
      expect(repeated.changed, isFalse);
      expect(
        repeated.estimatedRestingHeartRates.single,
        same(initial.estimatedRestingHeartRates.single),
      );
      final edited = HeartDerivationLogic.reconcile(
        readings: [
          ...initial.readings.where((r) => r.type != SignalType.heartRate),
          heart(60, 70),
          heart(90, 72),
          heart(120, 71),
        ],
        now: now.add(const Duration(hours: 2)),
      );
      expect(edited.estimatedRestingHeartRates.single.value, 71);
      expect(
        edited.estimatedRestingHeartRates.single.recordedAt,
        now.add(const Duration(hours: 2)),
      );
    },
  );

  test('insufficient remaining raw data removes the obsolete day estimate', () {
    final estimate = derive(overnight()).estimatedRestingHeartRates.single;
    final result = derive([estimate, heart(60, 60)]);
    expect(result.estimatedRestingHeartRates, isEmpty);
    expect(result.changed, isTrue);
  });

  test(
    'summary restore retains estimate until the local day is authoritative',
    () {
      final estimate = derive(overnight()).estimatedRestingHeartRates.single;
      final restored = derive([estimate]);
      expect(restored.estimatedRestingHeartRates, [estimate]);
      expect(restored.changed, isFalse);
      final deleted = HeartDerivationLogic.reconcile(
        readings: [estimate],
        now: now,
        authoritativeLocalDays: {day.add(const Duration(hours: 4))},
      );
      expect(deleted.estimatedRestingHeartRates, isEmpty);
      expect(deleted.changed, isTrue);
    },
  );

  test('duplicate ids and timestamps cannot satisfy minimum sample count', () {
    final samples = [
      heart(60, 60, id: 'healthkit-ONE'),
      heart(90, 58, id: 'healthkit-one'),
      heart(60, 59, id: 'healthkit-second-device'),
      heart(120, 60),
    ];
    final result = derive(samples);
    expect(result.estimatedRestingHeartRates, isEmpty);
    expect(result.days.single.overnightSampleCount, 2);
  });

  test('future observed or imported data cannot support current estimates', () {
    final result = HeartDerivationLogic.reconcile(
      readings: [
        heart(60, 60).copyWith(syncedAt: day),
        heart(90, 58).copyWith(syncedAt: day),
        heart(120, 59).copyWith(syncedAt: day),
        heart(75, 40),
      ],
      now: day.add(const Duration(minutes: 100)),
    );
    expect(result.estimatedRestingHeartRates, isEmpty);
    expect(result.days.single.overnightSampleCount, 2);
  });

  test('uses only valid HealthKit samples and retains unrelated signals', () {
    final samples = [
      heart(0, 60),
      heart(30, double.nan),
      heart(60, 60).copyWith(source: SignalSource.manual),
      heart(90, 19),
      heart(120, 301),
      heart(150, 60).copyWith(quality: 0),
    ];
    final result = derive(samples);
    expect(result.estimatedRestingHeartRates, isEmpty);
    expect(result.readings, containsAll(samples));
    expect(result.days.single.overnightSampleCount, 1);
  });

  test('does not invent a device source and reduces low input quality', () {
    final result = derive([
      for (var index = 0; index < 3; index++)
        SignalReading(
          id: 'unknown-source-$index',
          type: SignalType.heartRate,
          value: 60,
          timestamp: day.add(Duration(hours: index)),
          source: SignalSource.healthKit,
          quality: .4,
        ),
    ]);
    final estimate = result.estimatedRestingHeartRates.single;
    expect(estimate.note, endsWith('Apple Health'));
    expect(estimate.note, isNot(contains('Oura')));
    expect(estimate.quality, .2);
  });

  test(
    'empty input has no invented measurements and describes unavailable HRV',
    () {
      final result = derive([]);
      expect(result.readings, isEmpty);
      expect(result.changed, isFalse);
      expect(result.days.single.localDay, day);
      expect(
        result.days.single.hrvStatus,
        HeartRateVariabilityAvailability.noHeartRateSamples,
      );
    },
  );
}
