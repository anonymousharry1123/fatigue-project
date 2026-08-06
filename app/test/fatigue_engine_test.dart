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
    expect(score.cognitiveInputCount, 6);
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
      'Screen time',
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

  test('Version 0.15 forecast is hourly, bounded, and signal-aware', () {
    const score = ScoreSnapshot(
      energy: 74,
      cognitive: 78,
      confidence: .82,
      drivers: [],
    );
    List<SignalReading> inputs({required bool recovered}) => [
      SignalReading(
        id: 'sleep',
        type: SignalType.sleep,
        value: recovered ? 8.5 : 5,
        timestamp: now.subtract(const Duration(hours: 2)),
      ),
      SignalReading(
        id: 'bedtime',
        type: SignalType.bedtime,
        value: recovered ? 23 : 1,
        timestamp: now.subtract(const Duration(hours: 10)),
      ),
      SignalReading(
        id: 'study',
        type: SignalType.study,
        value: recovered ? 2 : 8,
        timestamp: now.subtract(const Duration(hours: 1)),
      ),
      SignalReading(
        id: 'exercise',
        type: SignalType.exercise,
        value: recovered ? .75 : 3,
        timestamp: now.subtract(const Duration(hours: 1)),
      ),
      SignalReading(
        id: 'hydration',
        type: SignalType.hydration,
        value: recovered ? 2.5 : .5,
        timestamp: now.subtract(const Duration(minutes: 30)),
      ),
    ];
    final recovered = FatigueEngine.forecast(
      score,
      now,
      signals: inputs(recovered: true),
      checkIns: [
        DailyCheckIn(
          id: 'ready',
          timestamp: now,
          energy: 8,
          mood: 8,
          stress: 2,
        ),
      ],
      generatedAt: now,
    );
    final strained = FatigueEngine.forecast(
      score,
      now,
      signals: inputs(recovered: false),
      checkIns: [
        DailyCheckIn(
          id: 'strained',
          timestamp: now,
          energy: 3,
          mood: 4,
          stress: 9,
        ),
      ],
      generatedAt: now,
    );
    final windows = FatigueEngine.windows(recovered, score);

    expect(recovered, hasLength(17));
    expect(
      recovered.every(
        (point) =>
            point.energy >= 0 &&
            point.energy <= 100 &&
            point.uncertainty >= 0 &&
            point.uncertainty <= 100,
      ),
      isTrue,
    );
    expect(recovered.every((point) => point.updatedAt == now), isTrue);
    expect(
      recovered
          .skip(1)
          .indexed
          .every(
            (entry) =>
                entry.$2.time.difference(recovered[entry.$1].time) ==
                const Duration(hours: 1),
          ),
      isTrue,
    );
    expect(
      recovered.map((point) => point.energy).reduce((a, b) => a + b) /
          recovered.length,
      greaterThan(
        strained.map((point) => point.energy).reduce((a, b) => a + b) /
            strained.length,
      ),
    );
    expect(
      windows.map((item) => item.type).toSet(),
      ForecastWindowType.values.toSet(),
    );
  });

  test('Version 0.15 uncertainty reflects evidence and forecast horizon', () {
    const score = ScoreSnapshot(
      energy: 70,
      cognitive: 70,
      confidence: .8,
      drivers: [],
    );
    final complete = FatigueEngine.forecast(
      score,
      now,
      signals: [
        for (final entry in const {
          SignalType.sleep: 8.0,
          SignalType.bedtime: 23.0,
          SignalType.study: 3.0,
          SignalType.hydration: 2.0,
        }.entries)
          SignalReading(
            id: entry.key.name,
            type: entry.key,
            value: entry.value,
            timestamp: now,
          ),
      ],
      checkIns: [
        DailyCheckIn(
          id: 'check-in',
          timestamp: now,
          energy: 7,
          mood: 7,
          stress: 3,
        ),
      ],
      generatedAt: now,
    );
    final missing = FatigueEngine.forecast(score, now, generatedAt: now);
    final tomorrow = FatigueEngine.forecast(
      score,
      now.add(const Duration(days: 1)),
      signals: const [],
      generatedAt: now,
    );
    final afterMidnightBedtime = FatigueEngine.forecast(
      score,
      now,
      profile: const UserProfile(bedHour: 25),
      generatedAt: now,
    );

    expect(missing.first.uncertainty, greaterThan(complete.first.uncertainty));
    expect(tomorrow.last.uncertainty, greaterThan(missing.first.uncertainty));
    expect(afterMidnightBedtime.last.time.hour, 23);
    expect(
      afterMidnightBedtime.every((point) => point.time.day == now.day),
      isTrue,
    );
  });

  test('Version 0.16 daily summaries expose confidence and staleness', () {
    final updatedAt = now.subtract(const Duration(hours: 13));
    final summary = ForecastDaySummary.fromPoints(now, [
      ForecastPoint(now, 60, 20, updatedAt: updatedAt),
      ForecastPoint(
        now.add(const Duration(hours: 1)),
        80,
        18,
        updatedAt: updatedAt,
      ),
    ]);

    expect(summary.averageEnergy, 70);
    expect(summary.lowEnergy, 60);
    expect(summary.peakEnergy, 80);
    expect(summary.peakTime, now.add(const Duration(hours: 1)));
    expect(summary.averageUncertainty, 19);
    expect(summary.isLowConfidence, isTrue);
    expect(summary.isStaleAt(now), isTrue);
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
