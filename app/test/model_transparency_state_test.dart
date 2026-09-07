import 'package:app/src/energy_model_summary.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/model_transparency_state.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 9, 7, 18);

EnergyModelSummary _summary({int trainedDay = 2}) =>
    EnergyModelSummary.tryParse({
      'modelVersion': 1,
      'schemaVersion': 1,
      'trainedAt': DateTime.utc(2026, 8, trainedDay).toIso8601String(),
      'window': {
        'start': '2026-07-02T00:00:00Z',
        'end': '2026-08-01T00:00:00Z',
        'timezone': 'UTC',
      },
      'labelCount': 20,
      'holdoutMae': 7,
      'deterministicMae': 10,
      'featureCoverage': {
        for (final name in MlPrepBuilder.energyFeatureNames) name: .8,
      },
    })!;

void main() {
  final reference = FatigueEngine.score(
    signals: const [],
    checkIns: const [],
    now: _now,
  );

  test('a loaded cloud summary is not a locally active model', () {
    final state = ModelTransparencyState(
      snapshot: reference,
      viewedAt: _now,
      signedIn: true,
      consentEnabled: true,
      cloudModel: _summary(),
    );
    expect(state.personalizedEnergyApplied, isFalse);
    expect(state.modelStatusTitle, 'Standard scoring on this device');
    expect(state.modelStatusDetail, contains('not its weights'));
  });

  test(
    'zero correction is model ready, not falsely applied personalization',
    () {
      final state = ModelTransparencyState(
        snapshot: reference.withEnergyCorrection(0, 'energy-ridge-v1'),
        viewedAt: _now,
        signedIn: true,
        consentEnabled: true,
        localModel: _summary(),
      );
      expect(state.personalizedEnergyApplied, isFalse);
      expect(state.modelStatusTitle, 'Model ready · baseline used');
    },
  );

  test(
    'applied model separates actual score correction from validation error',
    () {
      final personalized = reference.withEnergyCorrection(6, 'energy-ridge-v1');
      final state = ModelTransparencyState(
        snapshot: personalized,
        viewedAt: _now,
        signedIn: true,
        consentEnabled: true,
        scoreFromCloud: true,
        localModel: _summary(),
      );
      expect(state.personalizedEnergyApplied, isTrue);
      expect(state.modelStatusDetail, contains('+6 points'));
      expect(state.modelStatusDetail, contains('confidence are unchanged'));
      expect(state.scoreSourceLabel, contains('on-device adjustment'));
      expect(state.snapshot.confidence, reference.confidence);
      expect(state.snapshot.cognitive, reference.cognitive);
      expect(state.energyModelVersion, 'energy-rules-v1');
      expect(state.cognitiveModelVersion, 'cognitive-rules-v1');
      expect(state.localModel!.improvementPercent, closeTo(30, .001));
    },
  );

  test('newer local model never overwrites the last-read Firebase claims', () {
    final cloud = _summary();
    final state = ModelTransparencyState(
      snapshot: reference,
      viewedAt: _now,
      signedIn: true,
      consentEnabled: true,
      localModel: _summary(trainedDay: 4),
      cloudModel: cloud,
      metadataFetchedAt: DateTime.utc(2026, 8, 3),
    );
    expect(state.cloudModel, same(cloud));
    expect(state.notices.join(' '), contains('newer than'));
    expect(state.notices.join(' '), contains('not model training time'));
  });

  test('old snapshots do not get fabricated model versions', () {
    final state = ModelTransparencyState(
      snapshot: const ScoreSnapshot(
        energy: 60,
        cognitive: 0,
        confidence: .2,
        drivers: [],
        hasCognitiveScore: false,
      ),
      viewedAt: _now,
    );
    expect(state.energyModelVersion, 'Not recorded in this snapshot');
    expect(state.cognitiveModelVersion, 'No Cognitive score recorded');
    expect(state.modelStatusDetail, contains('Outcome learning is off'));
  });

  test('absent cloud metadata cannot establish that local model is newer', () {
    final state = ModelTransparencyState(
      snapshot: reference,
      viewedAt: _now,
      signedIn: true,
      consentEnabled: true,
      localModel: _summary(),
    );
    expect(state.notices.join(' '), isNot(contains('newer than')));
    expect(state.notices.join(' '), contains('no supported Firebase summary'));
  });

  test(
    'new driver evidence records aggregate sources and seeded input markers',
    () {
      final at = DateTime(2026, 9, 7, 18);
      final score = FatigueEngine.score(
        signals: [
          SignalReading(
            id: 'demo-sleep-1',
            type: SignalType.sleep,
            value: 7,
            timestamp: at.subtract(const Duration(days: 1)),
            source: SignalSource.healthKit,
          ),
          SignalReading(
            id: 'sleep-1788810000000',
            type: SignalType.sleep,
            value: 8,
            timestamp: at.subtract(const Duration(hours: 8)),
            source: SignalSource.manual,
          ),
        ],
        checkIns: [
          DailyCheckIn(
            id: 'seed-checkin-1',
            timestamp: at.subtract(const Duration(hours: 1)),
            energy: 8,
            mood: 8,
            stress: 4,
            period: CheckInPeriod.evening,
          ),
        ],
        now: at,
      );
      final sleep = score.drivers.singleWhere((d) => d.label == 'Sleep');
      expect(sleep.evidenceSources.toSet(), {
        SignalSource.healthKit,
        SignalSource.manual,
      });
      expect(sleep.containsDemoEvidence, isTrue);
      final mood = score.drivers.singleWhere((d) => d.label == 'Mood');
      expect(mood.source, SignalSource.manual);
      expect(mood.containsDemoEvidence, isTrue);
      final corrected = score.withEnergyCorrection(4, 'energy-ridge-v1');
      expect(corrected.energyModelVersion, score.energyModelVersion);
      expect(corrected.cognitiveModelVersion, score.cognitiveModelVersion);
      expect(corrected.drivers.last.evidenceSources, [SignalSource.model]);
      expect(
        corrected.withoutPersonalization().energyModelVersion,
        'energy-rules-v1',
      );
    },
  );
}
