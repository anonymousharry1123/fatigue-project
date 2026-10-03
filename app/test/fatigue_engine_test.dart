import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/models.dart';
import 'package:app/src/personal_baseline_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 21, 15);
  final day = DateTime(2026, 7, 21);
  SignalReading reading(
    SignalType type,
    double value, {
    String? id,
    DateTime? at,
    SignalSource source = SignalSource.manual,
    double quality = 1,
  }) => SignalReading(
    id: id ?? type.name,
    type: type,
    value: value,
    timestamp: at ?? now,
    source: source,
    quality: quality,
  );
  DailyCheckIn checkIn({
    DateTime? at,
    double energy = 6,
    double mood = 6,
    double stress = 5,
    String id = 'check-in',
  }) => DailyCheckIn(
    id: id,
    timestamp: at ?? now,
    energy: energy,
    mood: mood,
    stress: stress,
  );
  ScoreSnapshot score(
    List<SignalReading> signals, {
    List<DailyCheckIn> checkIns = const [],
    DateTime? at,
  }) =>
      FatigueEngine.score(signals: signals, checkIns: checkIns, now: at ?? now);
  List<ForecastPoint> forecast(
    ScoreSnapshot snapshot,
    List<SignalReading> signals, {
    List<DailyCheckIn> checkIns = const [],
    DateTime? date,
    DateTime? at,
  }) => FatigueEngine.forecast(
    snapshot,
    date ?? day,
    signals: signals,
    checkIns: checkIns,
    generatedAt: at ?? now,
  );

  test(
    'empty and yesterday-only inputs do not establish current estimates',
    () {
      for (final snapshot in [
        score([]),
        score(
          [
            reading(SignalType.sleep, 10),
            reading(
              SignalType.study,
              0,
              at: now.subtract(const Duration(days: 1)),
            ),
          ],
          checkIns: [checkIn(at: now.subtract(const Duration(days: 1)))],
        ),
      ]) {
        expect(snapshot.canEstimateEnergy, isFalse);
        expect(snapshot.canEstimateCognitive, isFalse);
        expect(snapshot.hasEnergyScore, isFalse);
        expect(snapshot.hasCognitiveScore, isFalse);
        expect(snapshot.confidence, 0);
        expect(snapshot.cognitiveConfidence, 0);
        expect(forecast(snapshot, []), isEmpty);
      }
    },
  );

  test('valid explicit zero is observed; missing and invalid are not zero', () {
    final explicitZero = score([reading(SignalType.study, 0)]);
    expect(explicitZero.canEstimateEnergy, isTrue);
    expect(explicitZero.canEstimateCognitive, isTrue);
    expect(explicitZero.inputCount, 1);
    expect(explicitZero.completeness, closeTo(1 / 6, .00001));
    expect(explicitZero.cognitiveCompleteness, closeTo(1 / 5, .00001));
    expect(explicitZero.drivers.single.detail, startsWith('0.0 hr'));
    for (final invalid in [double.nan, double.infinity, -1.0]) {
      expect(
        score([reading(SignalType.study, invalid)]).canEstimateEnergy,
        isFalse,
      );
    }
    expect(
      score([reading(SignalType.reactionTime, 0)]).canEstimateCognitive,
      isFalse,
    );
    expect(
      score([reading(SignalType.study, 2, quality: 0)]).canEstimateEnergy,
      isFalse,
    );
    expect(
      score([
        reading(SignalType.study, 2, source: SignalSource.model),
      ]).canEstimateEnergy,
      isFalse,
    );
  });

  test('future observations and check-ins cannot leak into current score', () {
    final future = now.add(const Duration(hours: 1));
    final snapshot = score(
      [reading(SignalType.study, 0, at: future)],
      checkIns: [checkIn(at: future)],
    );
    expect(snapshot.canEstimateEnergy, isFalse);
    final futureDay = FatigueEngine.score(
      signals: [
        reading(SignalType.study, 0, at: now.add(const Duration(days: 1))),
      ],
      checkIns: const [],
      now: now,
      day: now.add(const Duration(days: 1)),
    );
    expect(futureDay.canEstimateEnergy, isFalse);
  });

  test('context-only logs never create score availability or coverage', () {
    final snapshot = score([
      reading(SignalType.sleep, 10),
      reading(SignalType.nap, 2),
      reading(SignalType.caffeine, 2),
      reading(SignalType.hydration, 3),
      reading(SignalType.exercise, 1),
      reading(SignalType.steps, 9000),
    ]);
    expect(snapshot.canEstimateEnergy, isFalse);
    expect(snapshot.canEstimateCognitive, isFalse);
    expect(snapshot.inputCount, 0);
    expect(
      snapshot.drivers.every((driver) => driver.contribution == 0),
      isTrue,
    );
    expect(
      snapshot.drivers.map((driver) => driver.label),
      isNot(contains('Sleep')),
    );
    expect(
      snapshot.drivers.map((driver) => driver.label),
      isNot(contains('Nap recovery')),
    );
  });

  test(
    'caffeine, fluid volume and exercise duration cannot alter scores or forecasts',
    () {
      final inputs = [reading(SignalType.study, 2)];
      final reference = score(inputs);
      final referenceForecast = forecast(reference, inputs);
      expect(referenceForecast, isNotEmpty);
      for (final type in [
        SignalType.caffeine,
        SignalType.hydration,
        SignalType.exercise,
        SignalType.steps,
      ]) {
        for (final value in [0.0, 1.0, 2.0, 4.0, 20.0]) {
          final signals = [...inputs, reading(type, value)];
          final changed = score(signals);
          expect(changed.energy, reference.energy, reason: '$type $value');
          expect(
            changed.cognitive,
            reference.cognitive,
            reason: '$type $value',
          );
          expect(changed.confidence, reference.confidence);
          expect(changed.inputCount, reference.inputCount);
          final points = forecast(changed, signals);
          expect(
            points.map((point) => point.energy),
            referenceForecast.map((point) => point.energy),
          );
          expect(
            points.map((point) => point.uncertainty),
            referenceForecast.map((point) => point.uncertainty),
          );
          expect(
            points.expand((point) => point.signalEvidenceIds),
            isNot(contains(type.name)),
          );
        }
      }
    },
  );

  test(
    'sleep duration has no composite or forecast reward at fixed timing',
    () {
      final inputs = [reading(SignalType.study, 2)];
      final short = [
        ...inputs,
        reading(SignalType.sleep, 5, at: day.add(const Duration(hours: 7))),
      ];
      final long = [
        ...inputs,
        reading(SignalType.sleep, 12, at: day.add(const Duration(hours: 7))),
      ];
      expect(score(long).energy, score(short).energy);
      expect(score(long).cognitive, score(short).cognitive);
      expect(
        forecast(score(long), long).map((p) => p.energy),
        forecast(score(short), short).map((p) => p.energy),
      );
    },
  );

  test('context retains activity source reconciliation and explicit zeros', () {
    final snapshot = score([
      reading(
        SignalType.exercise,
        2,
        id: 'health-workout',
        source: SignalSource.healthKit,
      ),
      reading(SignalType.exercise, 0, id: 'manual-exercise'),
    ]);
    final exercise = snapshot.drivers.single;
    expect(exercise.detail, contains('0.0 hr'));
    expect(exercise.source, SignalSource.manual);
    expect(exercise.contribution, 0);
    expect(snapshot.canEstimateEnergy, isFalse);
  });

  test(
    'self-reported energy is not circularly used in current Energy score',
    () {
      expect(
        score([], checkIns: [checkIn(energy: 2)]).energy,
        score([], checkIns: [checkIn(energy: 9)]).energy,
      );
    },
  );

  test('current check-in differs from a stale or invalid check-in', () {
    final current = score([], checkIns: [checkIn()]);
    expect(current.canEstimateEnergy, isTrue);
    expect(current.inputCount, 2);
    expect(
      score([], checkIns: [checkIn(mood: double.nan)]).canEstimateEnergy,
      isFalse,
    );
    expect(
      score(
        [],
        checkIns: [checkIn(at: day.subtract(const Duration(minutes: 1)))],
      ).canEstimateEnergy,
      isFalse,
    );
  });

  test(
    'reaction score comparisons require same version and adequate prior evidence',
    () {
      final currentSignals = [reading(SignalType.reactionTime, 250)];
      final prior = FatigueEngine.score(
        signals: [
          reading(
            SignalType.reactionTime,
            300,
            at: now.subtract(const Duration(days: 1)),
          ),
        ],
        checkIns: const [],
        now: now.subtract(const Duration(days: 1)),
      );
      final current = FatigueEngine.score(
        signals: currentSignals,
        checkIns: const [],
        now: now,
        previousDay: prior,
      );
      expect(current.canEstimateEnergy, isFalse);
      expect(current.canEstimateCognitive, isTrue);
      expect(current.previousCognitive, prior.cognitive);
      final legacy = FatigueEngine.score(
        signals: currentSignals,
        checkIns: const [],
        now: now,
        previousDay: const ScoreSnapshot(
          energy: 70,
          cognitive: 80,
          confidence: .8,
          cognitiveInputCount: 2,
          drivers: [],
        ),
      );
      expect(legacy.previousCognitive, isNull);
    },
  );

  test(
    'forecast requires current compatible anchor and raw supporting observations',
    () {
      final signals = [reading(SignalType.study, 2)];
      final snapshot = score(signals);
      expect(forecast(snapshot, signals), isNotEmpty);
      expect(forecast(snapshot, []), isEmpty);
      expect(
        forecast(snapshot, signals, at: now.add(const Duration(days: 1))),
        isEmpty,
      );
      const legacy = ScoreSnapshot(
        energy: 80,
        cognitive: 80,
        confidence: .9,
        inputCount: 7,
        drivers: [],
        energyModelVersion: 'energy-rules-v2-sleep',
      );
      expect(forecast(legacy, signals), isEmpty);
      expect(forecast(score([]), signals), isEmpty);
    },
  );

  test(
    'experimental forecast points are bounded, versioned and carry source IDs',
    () {
      final signals = [reading(SignalType.study, 2)];
      final snapshot = score(signals, checkIns: [checkIn()]);
      final points = forecast(snapshot, signals, checkIns: [checkIn()]);
      expect(points, hasLength(17));
      expect(
        points.every(
          (p) => p.energy >= 0 && p.energy <= 100 && p.uncertainty >= 0,
        ),
        isTrue,
      );
      expect(
        points.every(
          (p) =>
              p.updatedAt == now &&
              p.rulesVersion == FatigueEngine.energyModelVersion,
        ),
        isTrue,
      );
      expect(
        points.every(
          (p) =>
              p.signalEvidenceIds.contains('study') &&
              p.checkInEvidenceIds.contains('check-in'),
        ),
        isTrue,
      );
      final tomorrow = forecast(
        snapshot,
        signals,
        checkIns: [checkIn()],
        date: day.add(const Duration(days: 1)),
      );
      expect(tomorrow.last.uncertainty, greaterThan(points.last.uncertainty));
      final windows = FatigueEngine.windows(
        points,
        snapshot,
        signals: signals,
        checkIns: [checkIn()],
      );
      expect(
        windows.map((w) => w.type).toSet(),
        ForecastWindowType.values.toSet(),
      );
      expect(windows.every((w) => w.reason.startsWith('Experimental')), isTrue);
      expect(
        FatigueEngine.windows([ForecastPoint(now, 70, 10)], snapshot),
        isEmpty,
      );
    },
  );

  test('obsolete forecast-based nap/workout prescriptions are disabled', () {
    final signals = [reading(SignalType.study, 2)];
    final snapshot = score(signals);
    final points = forecast(snapshot, signals);
    final windows = FatigueEngine.windows(points, snapshot, signals: signals);
    expect(windows, isNotEmpty);
    expect(FatigueEngine.recommendations(windows, snapshot, day: day), isEmpty);
  });

  test(
    'fixed hours cannot infer overtraining; incomplete sleep does not infer deficit',
    () {
      final signals = [
        for (var i = 0; i < 4; i++) ...[
          reading(
            SignalType.exercise,
            5,
            id: 'exercise-$i',
            at: now.subtract(Duration(days: i)),
          ),
          reading(
            SignalType.sleep,
            4,
            id: 'sleep-$i',
            at: now.subtract(Duration(days: i)),
          ),
        ],
      ];
      expect(
        FatigueEngine.alerts(signals, [], score(signals), now: now),
        isEmpty,
      );
    },
  );

  test(
    'repeated check-in observations are factual and require a current day',
    () {
      final checkIns = [
        for (var i = 0; i < 3; i++)
          checkIn(
            id: 'report-$i',
            energy: 3,
            stress: 8,
            at: now.subtract(Duration(days: i)),
          ),
      ];
      final alerts = FatigueEngine.alerts(
        [],
        checkIns,
        score([], checkIns: checkIns),
        now: now,
      );
      expect(alerts, hasLength(1));
      expect(alerts.single.title, 'Recent check-in observations');
      expect(alerts.single.detail, contains('4/10'));
      expect(alerts.single.severity, AlertSeverity.info);
      expect(alerts.single.checkInEvidenceIds, hasLength(3));
      expect(
        FatigueEngine.alerts(
          [],
          checkIns,
          score([]),
          now: now.add(const Duration(days: 1)),
        ),
        isEmpty,
      );
      final sameDay = [
        for (var i = 0; i < 3; i++)
          checkIn(id: 'same-$i', energy: 3, stress: 8),
      ];
      expect(FatigueEngine.alerts([], sameDay, score([]), now: now), isEmpty);
    },
  );

  test(
    'data quality reflects evidence age without claiming prediction probability',
    () {
      final fresh = score([reading(SignalType.study, 2)]);
      final older = score([reading(SignalType.study, 2, at: day)]);
      expect(fresh.inputCount, older.inputCount);
      expect(fresh.freshness, greaterThan(older.freshness!));
      expect(fresh.confidence, greaterThan(older.confidence));
    },
  );

  test(
    'personal baselines retain raw history and bound experimental effects',
    () {
      final signals = [
        for (var i = 1; i <= 8; i++) ...[
          reading(
            SignalType.hrv,
            50,
            id: 'hrv-$i',
            at: now.subtract(Duration(days: i)),
          ),
          reading(
            SignalType.restingHeartRate,
            60,
            id: 'rhr-$i',
            at: now.subtract(Duration(days: i)),
          ),
        ],
        reading(SignalType.hrv, 60),
        reading(SignalType.restingHeartRate, 70),
      ];
      final baselines = PersonalBaselineLogic.build(
        signals: signals,
        asOf: day,
      );
      final snapshot = FatigueEngine.score(
        signals: signals,
        checkIns: const [],
        now: now,
        personalBaselines: baselines,
      );
      expect(baselines.metric(PersonalBaselineType.hrv)?.sampleCount, 8);
      expect(snapshot.canEstimateEnergy, isTrue);
      expect(
        snapshot.energyPositiveDrivers.single.contribution,
        inInclusiveRange(0, 8),
      );
      expect(
        snapshot.energyNegativeDrivers.single.contribution,
        inInclusiveRange(-8, 0),
      );
      expect(
        snapshot.drivers.every(
          (d) => d.explanation.isNotEmpty && d.evidenceAt != null,
        ),
        isTrue,
      );
    },
  );

  test(
    'heart observations without a ready baseline do not expose neutral readiness',
    () {
      final signals = [
        reading(SignalType.hrv, 50),
        reading(SignalType.restingHeartRate, 60),
      ];
      final baseline = PersonalBaselineLogic.build(signals: signals, asOf: now);
      final snapshot = FatigueEngine.score(
        signals: signals,
        checkIns: const [],
        now: now,
        personalBaselines: baseline,
      );
      expect(snapshot.canEstimateEnergy, isFalse);
      expect(snapshot.inputCount, 0);
      expect(snapshot.confidence, 0);
      expect(snapshot.drivers, hasLength(2));
      expect(
        snapshot.drivers.every(
          (driver) =>
              driver.contribution == 0 &&
              driver.explanation.contains('baseline is building'),
        ),
        isTrue,
      );
      expect(forecast(snapshot, signals), isEmpty);
      final observed = FatigueEngine.score(
        signals: [...signals, reading(SignalType.study, 0)],
        checkIns: const [],
        now: now,
        personalBaselines: baseline,
      );
      expect(observed.canEstimateEnergy, isTrue);
      expect(observed.inputCount, 1);
    },
  );

  test('unavailable snapshots cannot acquire a personalized correction', () {
    final snapshot = score([]);
    final corrected = snapshot.withEnergyCorrection(10, 'unexpected-model');
    expect(corrected.personalizedModelVersion, isNull);
    expect(corrected.canEstimateEnergy, isFalse);
  });
}
