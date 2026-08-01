import 'package:app/src/demo_data.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 21, 9);

  test('Version 0.11 uses all seven explainable Energy Score factors', () {
    final score = FatigueEngine.score(
      signals: buildDemoSignals(now),
      checkIns: buildDemoCheckIns(now),
      now: now,
    );

    expect(score.energy, inInclusiveRange(0, 100));
    expect(score.cognitive, inInclusiveRange(0, 100));
    expect(score.confidence, inInclusiveRange(0, 1));
    expect(score.inputCount, 7);
    expect(score.isEstimate, isTrue);
    expect(score.drivers.map((driver) => driver.label).toSet(), {
      'Sleep',
      'Exercise',
      'Hydration',
      'Workload',
      'Screen time',
      'Mood',
      'Stress',
    });
  });

  test('daily activity values are totaled and future values are excluded', () {
    final score = FatigueEngine.score(
      signals: [
        SignalReading(
          id: 'water-1',
          type: SignalType.hydration,
          value: .8,
          timestamp: DateTime(2026, 7, 21, 7),
        ),
        SignalReading(
          id: 'water-2',
          type: SignalType.hydration,
          value: 1.2,
          timestamp: DateTime(2026, 7, 21, 8),
        ),
        SignalReading(
          id: 'future-water',
          type: SignalType.hydration,
          value: 5,
          timestamp: DateTime(2026, 7, 21, 12),
        ),
      ],
      checkIns: const [],
      now: now,
    );

    expect(score.inputCount, 1);
    expect(score.drivers.single.label, 'Hydration');
    expect(score.drivers.single.detail, contains('2.0 L'));
    expect(score.drivers.single.contribution, 0);
  });

  test('self-reported energy does not circularly change the Energy Score', () {
    ScoreSnapshot calculate(double energy) => FatigueEngine.score(
      signals: const [],
      checkIns: [
        DailyCheckIn(
          id: 'check-in',
          timestamp: DateTime(2026, 7, 21, 8),
          energy: energy,
          mood: 7,
          stress: 4,
        ),
      ],
      now: now,
    );

    expect(calculate(1).energy, calculate(10).energy);
    expect(calculate(1).inputCount, 2);
  });

  test('forecast returns an hourly curve and all three window types', () {
    const score = ScoreSnapshot(
      energy: 74,
      cognitive: 78,
      confidence: .82,
      drivers: [],
    );
    final points = FatigueEngine.forecast(score, now);
    final windows = FatigueEngine.windows(points, score);

    expect(points, hasLength(17));
    expect(
      points.every((point) => point.energy >= 0 && point.energy <= 100),
      isTrue,
    );
    expect(
      windows.map((item) => item.type).toSet(),
      ForecastWindowType.values.toSet(),
    );
  });

  test('missing signals lower confidence without breaking scores', () {
    final score = FatigueEngine.score(
      signals: const [],
      checkIns: const [],
      now: now,
    );

    expect(score.confidence, lessThan(.5));
    expect(score.inputCount, 0);
    expect(score.confidence, .2);
    expect(score.energy, inInclusiveRange(0, 100));
    expect(score.cognitive, inInclusiveRange(0, 100));
  });
}
