import 'package:app/src/cloud_schema.dart';
import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/benchmark_energy_model.dart' show benchmarkSnapshot;

PrepSnapshot _typedInputSnapshot() {
  final original = benchmarkSnapshot();
  final checkIds = <String, String>{};
  final checks = [
    for (final raw in original.checkIns)
      {
        ...raw,
        'id': checkIds[raw['id'] as String] =
            'checkin-${DateTime.parse(raw['timestamp'] as String).microsecondsSinceEpoch}',
        'recordedAt': raw['createdAt'],
        'period':
            original.window
                    .localTime(DateTime.parse(raw['timestamp'] as String))
                    .hour <
                14
            ? 'morning'
            : 'evening',
      },
  ];
  return PrepSnapshot(
    uid: original.uid,
    window: original.window,
    consent: original.consent,
    fetchedAt: original.fetchedAt,
    schemaVersion: original.schemaVersion,
    signals: [
      for (final raw in original.signals)
        {
          ...raw,
          'id':
              'manual-${DateTime.parse(raw['timestamp'] as String).microsecondsSinceEpoch}-${raw['type']}',
          'recordedAt': raw['createdAt'],
        },
    ],
    checkIns: checks,
    outcomes: [
      for (final raw in original.outcomes)
        {...raw, 'sourceId': checkIds[raw['sourceId']]},
    ],
  );
}

void main() {
  const reference = ScoreSnapshot(
    energy: 64,
    cognitive: 71,
    confidence: .42,
    cognitiveConfidence: .63,
    drivers: [ScoreDriver('Sleep', 3, 'Observed sleep')],
    cognitiveDrivers: [ScoreDriver('Reaction', 2, 'Observed reaction')],
    cognitiveInputCount: 3,
    inputCount: 6,
    freshness: .75,
    cognitiveFreshness: .8,
    baselineConfidence: .3,
    isEstimate: false,
  );

  test(
    'bounded Energy correction preserves Cognitive and every confidence value',
    () {
      final adjusted = reference.withEnergyCorrection(50, 'energy-ridge-v1');
      expect(adjusted.energy, 74);
      expect(adjusted.deterministicEnergy, 64);
      expect(adjusted.personalizedModelVersion, 'energy-ridge-v1');
      expect(adjusted.cognitive, reference.cognitive);
      expect(adjusted.cognitiveDrivers, reference.cognitiveDrivers);
      expect(adjusted.cognitiveInputCount, reference.cognitiveInputCount);
      expect(adjusted.confidence, reference.confidence);
      expect(adjusted.cognitiveConfidence, reference.cognitiveConfidence);
      expect(adjusted.baselineConfidence, reference.baselineConfidence);
      expect(adjusted.freshness, reference.freshness);
      expect(adjusted.cognitiveFreshness, reference.cognitiveFreshness);
      expect(adjusted.isEstimate, reference.isEstimate);
      expect(reference.withEnergyCorrection(-50, 'v1').energy, 54);
      expect(reference.withEnergyCorrection(double.nan, 'v1'), same(reference));
      expect(
        reference.withEnergyCorrection(double.infinity, 'v1'),
        same(reference),
      );

      final base = adjusted.withoutPersonalization();
      expect(base.energy, reference.energy);
      expect(base.drivers, reference.drivers);
      expect(base.deterministicEnergy, isNull);
      expect(base.personalizedModelVersion, isNull);
      expect(base.cognitive, reference.cognitive);
      expect(base.confidence, reference.confidence);
    },
  );

  test(
    'reapplying a model starts from the deterministic base, not prior correction',
    () {
      final once = reference.withEnergyCorrection(8, 'v1');
      final twice = once.withEnergyCorrection(8, 'v1');
      expect(once.energy, 72);
      expect(twice.energy, 72);
      expect(
        twice.drivers.where((d) => d.label == 'Personalized Energy adjustment'),
        hasLength(1),
      );
      expect(twice.withEnergyCorrection(-5, 'v2').energy, 59);
      expect(
        twice.withoutPersonalization().withoutPersonalization().energy,
        64,
      );
    },
  );

  test(
    'daily cloud snapshot round-trip retains a reversible deterministic base',
    () {
      final adjusted = reference.withEnergyCorrection(8, 'energy-ridge-v1');
      final payload = scoreSnapshotToCloud(
        snapshot: adjusted,
        day: DateTime.utc(2026, 7, 31),
      );
      expect(payload['deterministicEnergy'], 64);
      expect(payload['personalizedModelVersion'], 'energy-ridge-v1');
      final restored = scoreSnapshotFromCloud(payload);
      expect(restored.energy, adjusted.energy);
      expect(restored.withoutPersonalization().energy, reference.energy);
      expect(restored.confidence, reference.confidence);
      expect(restored.cognitive, reference.cognitive);
      expect(restored.cognitiveConfidence, reference.cognitiveConfidence);
      expect(restored.withoutPersonalization().drivers.map((d) => d.label), [
        'Sleep',
      ]);

      final oldPayload = scoreSnapshotToCloud(
        snapshot: reference,
        day: DateTime.utc(2026, 7, 31),
      );
      expect(oldPayload, isNot(contains('deterministicEnergy')));
      expect(
        scoreSnapshotFromCloud(oldPayload).withoutPersonalization().energy,
        64,
      );
    },
  );

  test(
    'live typed inputs reproduce the same prep feature definitions and freshness',
    () {
      final snapshot = _typedInputSnapshot();
      final report = MlPrepBuilder.build(snapshot);
      expect(report.energyReady, isTrue);
      final prepared = report.examples.last;
      final sourceId = snapshot.outcomes.firstWhere(
        (r) => r['id'] == prepared.outcomeId,
      )['sourceId'];
      final input = MlPrepBuilder.energyInput(
        signals: snapshot.signals.map(SignalReading.fromJson).toList(),
        checkIns: snapshot.checkIns
            .where((r) => r['id'] != sourceId)
            .map(DailyCheckIn.fromJson)
            .toList(),
        at: prepared.observedAt,
        timezone: snapshot.window.timezone,
      );
      expect(input, isNotNull);
      expect(input!.features, prepared.features);
      expect(input.featureAgeHours, prepared.featureAgeHours);
      expect(input.features.keys.toList(), MlPrepBuilder.energyFeatureNames);
    },
  );

  test(
    'synthetic, uncertain and not-yet-recorded inputs have no learned features',
    () {
      final window = benchmarkSnapshot().window;
      final at = window.start.add(const Duration(days: 10, hours: 15));
      final before = at.subtract(const Duration(hours: 1));
      final input = MlPrepBuilder.energyInput(
        signals: [
          SignalReading(
            id: 'seed-hydration',
            type: SignalType.hydration,
            value: 4,
            timestamp: before,
            recordedAt: before,
          ),
          SignalReading(
            id: 'unverified-exercise',
            type: SignalType.exercise,
            value: 4,
            timestamp: before,
            recordedAt: before,
          ),
          SignalReading(
            id: 'manual-${before.microsecondsSinceEpoch}',
            type: SignalType.caffeine,
            value: 4,
            timestamp: before,
            recordedAt: at.add(const Duration(hours: 1)),
          ),
        ],
        checkIns: [
          DailyCheckIn(
            id: 'seed-checkin',
            timestamp: before,
            recordedAt: before,
            energy: 10,
            mood: 10,
            stress: 10,
          ),
        ],
        at: at,
        timezone: window.timezone,
      );
      expect(input, isNotNull);
      expect(input!.features.values, everyElement(isNull));
    },
  );
}
