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
    expect(score.cognitiveConfidence, lessThanOrEqualTo(.95));
    expect(score.cognitiveConfidence, greaterThan(.85));
    expect(score.freshness, inInclusiveRange(0, 1));
    expect(score.cognitiveFreshness, inInclusiveRange(0, 1));
    expect(score.inputCount, 7);
    expect(score.cognitiveInputCount, 5);
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
    expect(score.cognitiveDrivers.map((driver) => driver.label).toSet(), {
      'Reaction time',
      'Sleep',
      'Study load',
      'Mood',
      'Stress',
    });
  });

  test('Version 0.12 compares reaction time and the previous daily score', () {
    const previous = ScoreSnapshot(
      energy: 70,
      cognitive: 60,
      confidence: .8,
      drivers: [],
      hasCognitiveScore: true,
    );
    final score = FatigueEngine.score(
      signals: [
        SignalReading(
          id: 'reaction-today',
          type: SignalType.reactionTime,
          value: 250,
          timestamp: DateTime(2026, 7, 21, 8),
        ),
        SignalReading(
          id: 'reaction-yesterday',
          type: SignalType.reactionTime,
          value: 300,
          timestamp: DateTime(2026, 7, 10, 8),
        ),
      ],
      checkIns: const [],
      now: now,
      previousDay: previous,
    );

    final reaction = score.cognitiveDrivers.single;
    expect(reaction.label, 'Reaction time');
    expect(reaction.contribution, greaterThan(0));
    expect(reaction.detail, contains('250 ms vs 300 ms baseline'));
    expect(score.previousCognitive, 60);
    expect(score.cognitiveChange, score.cognitive - 60);
  });

  test('legacy Energy-only snapshots do not create a false comparison', () {
    const previous = ScoreSnapshot(
      energy: 70,
      cognitive: 0,
      confidence: .8,
      drivers: [],
      hasCognitiveScore: false,
    );
    final score = FatigueEngine.score(
      signals: const [],
      checkIns: const [],
      now: now,
      previousDay: previous,
    );

    expect(score.previousCognitive, isNull);
    expect(score.cognitiveChange, isNull);
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
    expect(score.cognitiveInputCount, 0);
    expect(score.cognitiveConfidence, .2);
  });

  test('Version 0.14 ranks positive and negative drivers independently', () {
    final score = FatigueEngine.score(
      signals: [
        for (final entry in const {
          SignalType.sleep: 5.0,
          SignalType.hydration: 3.0,
          SignalType.exercise: 1.0,
          SignalType.study: 7.0,
          SignalType.screenTime: 8.0,
          SignalType.reactionTime: 245.0,
        }.entries)
          SignalReading(
            id: entry.key.name,
            type: entry.key,
            value: entry.value,
            timestamp: now,
            source: SignalSource.healthKit,
          ),
      ],
      checkIns: [
        DailyCheckIn(
          id: 'check-in',
          timestamp: now,
          energy: 7,
          mood: 9,
          stress: 8,
        ),
      ],
      now: now,
    );

    expect(score.energyPositiveDrivers, isNotEmpty);
    expect(score.energyNegativeDrivers, isNotEmpty);
    expect(
      score.energyPositiveDrivers.map((driver) => driver.contribution),
      orderedEquals(
        [...score.energyPositiveDrivers.map((driver) => driver.contribution)]
          ..sort((left, right) => right.compareTo(left)),
      ),
    );
    expect(
      score.energyNegativeDrivers.map((driver) => driver.contribution),
      orderedEquals(
        [...score.energyNegativeDrivers.map((driver) => driver.contribution)]
          ..sort(),
      ),
    );
    expect(
      score.drivers.every((driver) => driver.explanation.isNotEmpty),
      isTrue,
    );
    expect(score.drivers.every((driver) => driver.freshness != null), isTrue);
    expect(
      score.drivers.singleWhere((driver) => driver.label == 'Hydration').source,
      SignalSource.healthKit,
    );
  });

  test('Version 0.14 confidence falls as evidence becomes stale', () {
    final late = DateTime(2026, 7, 21, 23);

    ScoreSnapshot calculate({required bool fresh}) {
      final activityTime = fresh ? late : DateTime(2026, 7, 21);
      final sleepTime = fresh ? late : DateTime(2026, 7, 15);
      final checkInTime = fresh ? late : DateTime(2026, 7, 20, 13);
      return FatigueEngine.score(
        signals: [
          for (final entry in const {
            SignalType.hydration: 2.0,
            SignalType.exercise: 1.0,
            SignalType.study: 3.0,
            SignalType.screenTime: 3.0,
          }.entries)
            SignalReading(
              id: entry.key.name,
              type: entry.key,
              value: entry.value,
              timestamp: activityTime,
              source: fresh ? SignalSource.healthKit : SignalSource.model,
            ),
          SignalReading(
            id: 'sleep',
            type: SignalType.sleep,
            value: 7.5,
            timestamp: sleepTime,
            source: fresh ? SignalSource.healthKit : SignalSource.model,
          ),
        ],
        checkIns: [
          DailyCheckIn(
            id: 'check-in',
            timestamp: checkInTime,
            energy: 7,
            mood: 7,
            stress: 4,
          ),
        ],
        now: late,
      );
    }

    final fresh = calculate(fresh: true);
    final stale = calculate(fresh: false);

    expect(fresh.inputCount, stale.inputCount);
    expect(fresh.completeness, stale.completeness);
    expect(fresh.freshness, greaterThan(stale.freshness!));
    expect(fresh.confidence, greaterThan(stale.confidence));
  });
}
