import 'package:app/src/cloud_schema.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/models.dart';
import 'package:app/src/personal_baseline_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 18, 15);
  final day = DateTime(2026, 10, 18);
  SignalReading reading(
    String id,
    SignalType type,
    double value,
    DateTime observedAt,
  ) => SignalReading(
    id: id,
    type: type,
    value: value,
    timestamp: observedAt,
    source: SignalSource.healthKit,
  );

  final regularHeart = [
    for (var i = 0; i < 30; i++)
      reading(
        'regular-heart-$i',
        SignalType.heartRate,
        70 + i.toDouble(),
        now.subtract(Duration(days: i)),
      ),
  ];

  test('regular heart rate alone does not create a fatigue estimate', () {
    final baselines = PersonalBaselineLogic.build(
      signals: regularHeart,
      asOf: now,
    );
    final score = FatigueEngine.score(
      signals: regularHeart,
      checkIns: const [],
      now: now,
      personalBaselines: baselines,
    );
    expect(baselines.readyCount, 0);
    expect(score.canEstimateEnergy, isFalse);
    expect(score.canEstimateCognitive, isFalse);
    expect(score.inputCount, 0);
    expect(score.cognitiveInputCount, 0);
    expect(score.confidence, 0);
    expect(score.cognitiveConfidence, 0);
    expect(score.drivers, isEmpty);
    expect(score.cognitiveDrivers, isEmpty);
    expect(
      FatigueEngine.forecast(
        score,
        day,
        signals: regularHeart,
        generatedAt: now,
      ),
      isEmpty,
    );
  });

  test(
    'regular heart rate leaves scores, baselines and forecasts unchanged',
    () {
      final inputs = [
        for (var i = 1; i <= 8; i++) ...[
          reading(
            'hrv-$i',
            SignalType.hrv,
            50,
            now.subtract(Duration(days: i)),
          ),
          reading(
            'resting-$i',
            SignalType.restingHeartRate,
            60,
            now.subtract(Duration(days: i)),
          ),
        ],
        reading(
          'hrv-now',
          SignalType.hrv,
          55,
          now.subtract(const Duration(hours: 2)),
        ),
        reading(
          'resting-now',
          SignalType.restingHeartRate,
          63,
          now.subtract(const Duration(hours: 2)),
        ),
        reading(
          'study',
          SignalType.study,
          2,
          now.subtract(const Duration(hours: 1)),
        ),
        reading(
          'sleep',
          SignalType.sleep,
          8,
          day.add(const Duration(hours: 8)),
        ),
      ];
      ScoreSnapshot calculate(List<SignalReading> signals) =>
          FatigueEngine.score(
            signals: signals,
            checkIns: const [],
            now: now,
            personalBaselines: PersonalBaselineLogic.build(
              signals: signals,
              asOf: now,
            ),
          );
      final before = calculate(inputs);
      final after = calculate([...inputs, ...regularHeart]);
      expect(before.canEstimateEnergy, isTrue);
      expect(
        scoreSnapshotToCloud(snapshot: after, day: day),
        scoreSnapshotToCloud(snapshot: before, day: day),
      );
      final beforeForecast = FatigueEngine.forecast(
        before,
        day,
        signals: inputs,
        generatedAt: now,
      );
      final afterForecast = FatigueEngine.forecast(
        after,
        day,
        signals: [...inputs, ...regularHeart],
        generatedAt: now,
      );
      expect(beforeForecast, isNotEmpty);
      expect(
        afterForecast.map(forecastPointToCloud).toList(),
        beforeForecast.map(forecastPointToCloud).toList(),
      );
    },
  );
}
