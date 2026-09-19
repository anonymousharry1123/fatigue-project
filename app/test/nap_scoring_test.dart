import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/models.dart';
import 'package:app/src/personal_baseline_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 9, 19);
  final now = day.add(const Duration(hours: 15, minutes: 30));

  SignalReading mainSleep({double hours = 8, int daysAgo = 0}) => SignalReading(
    id: 'main-$daysAgo',
    type: SignalType.sleep,
    value: hours,
    timestamp: day
        .subtract(Duration(days: daysAgo))
        .add(const Duration(hours: 7)),
  );

  SignalReading nap({String id = 'nap', double hours = .5, DateTime? end}) =>
      SignalReading(
        id: id,
        type: SignalType.nap,
        value: hours,
        timestamp: end ?? day.add(const Duration(hours: 14, minutes: 30)),
      );

  ScoreSnapshot score(List<SignalReading> signals, {DateTime? at}) =>
      FatigueEngine.score(signals: signals, checkIns: const [], now: at ?? now);

  ScoreDriver sleepDriver(ScoreSnapshot snapshot) =>
      snapshot.drivers.singleWhere((driver) => driver.label == 'Sleep');

  double napImpact(ScoreSnapshot snapshot) => snapshot.drivers
      .where((driver) => driver.label == 'Nap recovery')
      .fold<double>(0, (total, driver) => total + driver.contribution);

  test('a nap preserves main sleep average, baseline and confidence', () {
    final nights = [
      for (var i = 0; i < 8; i++) mainSleep(hours: 8, daysAgo: i),
    ];
    final without = score(nights);
    final withNap = score([...nights, nap()]);

    expect(sleepDriver(withNap).detail, sleepDriver(without).detail);
    expect(
      sleepDriver(withNap).contribution,
      sleepDriver(without).contribution,
    );
    expect(sleepDriver(withNap).detail, contains('8.0 hr 3-night average'));
    expect(withNap.energy, without.energy + 3);
    expect(withNap.cognitive, without.cognitive + 2);
    expect(withNap.inputCount, without.inputCount);
    expect(withNap.cognitiveInputCount, without.cognitiveInputCount);
    expect(withNap.confidence, without.confidence);
    expect(withNap.cognitiveConfidence, without.cognitiveConfidence);
    expect(withNap.freshness, without.freshness);
    final withBaseline = PersonalBaselineLogic.build(
      signals: [...nights, nap()],
      asOf: day.add(const Duration(days: 1)),
    ).metric(PersonalBaselineType.sleep);
    final withoutBaseline = PersonalBaselineLogic.build(
      signals: nights,
      asOf: day.add(const Duration(days: 1)),
    ).metric(PersonalBaselineType.sleep);
    expect(withBaseline?.value, withoutBaseline?.value);
    expect(withBaseline?.sampleCount, withoutBaseline?.sampleCount);
  });

  test('longer and repeated naps cannot erase short main sleep', () {
    final nights = [mainSleep(hours: 5)];
    final without = score(nights);
    final withNap = score([
      ...nights,
      nap(hours: 2),
      nap(id: 'earlier', end: day.add(const Duration(hours: 11))),
      nap(id: 'duplicate', hours: 2),
    ]);
    expect(napImpact(withNap), lessThanOrEqualTo(3));
    expect(withNap.energy - without.energy, inInclusiveRange(0, 3));
    expect(withNap.cognitive - without.cognitive, inInclusiveRange(0, 2));
    expect(withNap.energy, lessThan(score([mainSleep(hours: 7.5)]).energy));
    expect(
      withNap.cognitive,
      lessThan(score([mainSleep(hours: 7.5)]).cognitive),
    );
    expect(
      sleepDriver(withNap).contribution,
      sleepDriver(without).contribution,
    );
  });

  test(
    'nap recovery ramps after waking and fades without becoming negative',
    () {
      final napEnd = day.add(const Duration(hours: 12));
      final signals = [mainSleep(), nap(end: napEnd)];
      double atMinutes(int minutes) =>
          napImpact(score(signals, at: napEnd.add(Duration(minutes: minutes))));

      expect(atMinutes(0), 0);
      expect(atMinutes(30), 0);
      expect(atMinutes(45), closeTo(1.5, .001));
      expect(atMinutes(60), 3);
      expect(atMinutes(120), 3);
      expect(atMinutes(240), closeTo(1.5, .001));
      expect(atMinutes(360), 0);
      expect(atMinutes(420), 0);
      expect(
        napImpact(score([mainSleep(), nap(hours: .25)])),
        closeTo(1.5, .001),
      );
    },
  );

  test('a nap alone does not manufacture main sleep evidence', () {
    final snapshot = score([nap()]);
    expect(snapshot.drivers.map((driver) => driver.label), ['Nap recovery']);
    expect(snapshot.inputCount, 0);
    expect(snapshot.cognitiveInputCount, 0);
    expect(snapshot.confidence, .2);
    expect(snapshot.cognitiveConfidence, .2);
    expect(snapshot.energy, 63);
    expect(snapshot.cognitive, 67);
  });

  test(
    'future, previous-day, invalid and main-sleep-overlapping naps add nothing',
    () {
      final baseline = score([mainSleep()]);
      final snapshot = score([
        mainSleep(),
        nap(id: 'future', end: now.add(const Duration(hours: 1))),
        nap(id: 'yesterday', end: now.subtract(const Duration(days: 1))),
        nap(id: 'invalid', hours: double.nan),
        nap(id: 'negative', hours: -1),
        nap(id: 'overlap', end: day.add(const Duration(hours: 6))),
      ]);
      expect(snapshot.energy, baseline.energy);
      expect(snapshot.cognitive, baseline.cognitive);
      expect(snapshot.inputCount, baseline.inputCount);
    },
  );

  test('nap does not alter earlier, expired or next-day forecast points', () {
    final nights = [mainSleep()];
    final signals = [...nights, nap()];
    final without = score(nights);
    final withNap = score(signals);

    List<ForecastPoint> forecast(ScoreSnapshot snapshot, DateTime date) =>
        FatigueEngine.forecast(
          snapshot,
          date,
          signals: signals,
          generatedAt: now,
        );

    final reference = FatigueEngine.forecast(
      without,
      day,
      signals: nights,
      generatedAt: now,
    );
    final adjusted = forecast(withNap, day);
    for (var i = 0; i < reference.length; i++) {
      final point = adjusted[i];
      if (point.time.hour <= 15 || point.time.hour >= 21) {
        expect(point.energy, reference[i].energy);
        expect(point.signalEvidenceIds, isNot(contains('nap')));
      }
      if (point.time.hour == 16) {
        expect(point.energy, closeTo(reference[i].energy + 3, .001));
        expect(point.signalEvidenceIds, contains('nap'));
      }
    }
    final tomorrow = day.add(const Duration(days: 1));
    final tomorrowReference = FatigueEngine.forecast(
      without,
      tomorrow,
      signals: nights,
      generatedAt: now,
    );
    expect(
      forecast(withNap, tomorrow).map((point) => point.energy),
      tomorrowReference.map((point) => point.energy),
    );
  });

  test('naps never create a sustained short-sleep alert', () {
    final signals = [
      for (var i = 0; i < 4; i++) ...[
        mainSleep(daysAgo: i),
        nap(
          id: 'nap-$i',
          end: now.subtract(Duration(days: i, hours: 1)),
        ),
      ],
    ];
    final alerts = FatigueEngine.alerts(
      signals,
      const [],
      score(signals),
      now: now,
      day: day,
    );
    expect(
      alerts.where((alert) => alert.category == RiskAlertCategory.sleepDebt),
      isEmpty,
    );
  });
}
