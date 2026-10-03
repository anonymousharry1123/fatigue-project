import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/models.dart';
import 'package:app/src/personal_baseline_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 9, 19);
  final now = day.add(const Duration(hours: 15, minutes: 30));
  SignalReading sleep(int daysAgo) => SignalReading(
    id: 'main-$daysAgo',
    type: SignalType.sleep,
    value: 8,
    timestamp: day
        .subtract(Duration(days: daysAgo))
        .add(const Duration(hours: 7)),
  );
  SignalReading nap({double hours = .5, DateTime? at}) => SignalReading(
    id: 'nap',
    type: SignalType.nap,
    value: hours,
    timestamp: at ?? now.subtract(const Duration(hours: 1)),
  );
  final study = SignalReading(
    id: 'study',
    type: SignalType.study,
    value: 2,
    timestamp: day.add(const Duration(hours: 9)),
  );
  ScoreSnapshot score(List<SignalReading> signals, {DateTime? at}) =>
      FatigueEngine.score(signals: signals, checkIns: const [], now: at ?? now);

  test(
    'naps do not receive a precise restorative equivalent or score points',
    () {
      final nights = [for (var i = 0; i < 8; i++) sleep(i)];
      final reference = score([...nights, study]);
      for (final hours in [.25, .5, 1.0, 2.0]) {
        final changed = score([...nights, study, nap(hours: hours)]);
        expect(changed.energy, reference.energy);
        expect(changed.cognitive, reference.cognitive);
        expect(changed.confidence, reference.confidence);
        expect(changed.cognitiveConfidence, reference.cognitiveConfidence);
        expect(
          changed.drivers.map((d) => d.label),
          isNot(contains('Nap recovery')),
        );
      }
      final withNap = PersonalBaselineLogic.build(
        signals: [...nights, nap()],
        asOf: day.add(const Duration(days: 1)),
      );
      final withoutNap = PersonalBaselineLogic.build(
        signals: nights,
        asOf: day.add(const Duration(days: 1)),
      );
      expect(
        withNap.metric(PersonalBaselineType.sleep)?.value,
        withoutNap.metric(PersonalBaselineType.sleep)?.value,
      );
      expect(
        withNap.metric(PersonalBaselineType.sleep)?.sampleCount,
        withoutNap.metric(PersonalBaselineType.sleep)?.sampleCount,
      );
    },
  );

  test('nap-only evidence never manufactures current readiness', () {
    final snapshot = score([nap()]);
    expect(snapshot.canEstimateEnergy, isFalse);
    expect(snapshot.canEstimateCognitive, isFalse);
    expect(snapshot.inputCount, 0);
    expect(snapshot.confidence, 0);
    expect(snapshot.cognitiveConfidence, 0);
    expect(
      FatigueEngine.forecast(snapshot, day, signals: [nap()], generatedAt: now),
      isEmpty,
    );
  });

  test('nap timing, repeats and duration do not restore forecast bonuses', () {
    final inputs = [study, sleep(0)];
    final referenceScore = score(inputs);
    final reference = FatigueEngine.forecast(
      referenceScore,
      day,
      signals: inputs,
      generatedAt: now,
    );
    expect(reference, isNotEmpty);
    final variants = [
      nap(),
      nap(hours: 2),
      nap(at: now.add(const Duration(hours: 1))),
      nap(at: now.subtract(const Duration(days: 1))),
      nap(hours: double.nan),
      nap(hours: -1),
      nap(at: day.add(const Duration(hours: 6))),
    ];
    for (final extra in variants) {
      final signals = [...inputs, extra, extra];
      final changed = score(signals);
      expect(changed.energy, referenceScore.energy);
      for (final date in [day, day.add(const Duration(days: 1))]) {
        final expected = FatigueEngine.forecast(
          referenceScore,
          date,
          signals: inputs,
          generatedAt: now,
        );
        final actual = FatigueEngine.forecast(
          changed,
          date,
          signals: signals,
          generatedAt: now,
        );
        expect(actual.map((p) => p.energy), expected.map((p) => p.energy));
        expect(
          actual.expand((p) => p.signalEvidenceIds),
          isNot(contains('nap')),
        );
      }
    }
  });
}
