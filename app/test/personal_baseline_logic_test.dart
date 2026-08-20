import 'package:app/src/models.dart';
import 'package:app/src/personal_baseline_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Version 0.27 builds robust rolling baselines from prior days only', () {
    final today = DateTime(2026, 8, 20);
    final signals = <SignalReading>[];
    for (var daysAgo = 1; daysAgo <= 8; daysAgo++) {
      final day = today.subtract(Duration(days: daysAgo));
      signals.addAll([
        SignalReading(
          id: 'hrv-$daysAgo-a',
          type: SignalType.hrv,
          value: (50 + daysAgo).toDouble(),
          timestamp: day.add(const Duration(hours: 7)),
          source: SignalSource.healthKit,
        ),
        SignalReading(
          id: 'hrv-$daysAgo-b',
          type: SignalType.hrv,
          value: (52 + daysAgo).toDouble(),
          timestamp: day.add(const Duration(hours: 8)),
          source: SignalSource.healthKit,
        ),
        SignalReading(
          id: 'rhr-$daysAgo',
          type: SignalType.restingHeartRate,
          value: 60 + daysAgo / 10,
          timestamp: day.add(const Duration(hours: 8)),
          source: SignalSource.healthKit,
        ),
        SignalReading(
          id: 'sleep-$daysAgo',
          type: SignalType.sleep,
          value: 8,
          timestamp: day.add(const Duration(hours: 7)),
        ),
        SignalReading(
          id: 'reaction-$daysAgo',
          type: SignalType.reactionTime,
          value: (270 + daysAgo).toDouble(),
          timestamp: day.add(const Duration(hours: 9)),
        ),
      ]);
    }
    signals.add(
      SignalReading(
        id: 'today-outlier',
        type: SignalType.hrv,
        value: 500,
        timestamp: today.add(const Duration(hours: 8)),
      ),
    );

    final baselines = PersonalBaselineLogic.build(
      signals: signals,
      asOf: today,
    );

    expect(baselines.readyCount, 4);
    expect(baselines.metric(PersonalBaselineType.hrv)?.sampleCount, 8);
    expect(baselines.metric(PersonalBaselineType.hrv)?.value, 55.5);
    expect(baselines.metric(PersonalBaselineType.sleep)?.value, 8);
    expect(
      baselines.metric(PersonalBaselineType.reactionTime)?.isReady,
      isTrue,
    );
    expect(baselines.overallReadiness, 1);
  });

  test('Version 0.27 reports building state until minimum history exists', () {
    final today = DateTime(2026, 8, 20);
    final baselines = PersonalBaselineLogic.build(
      asOf: today,
      signals: [
        for (var daysAgo = 1; daysAgo <= 3; daysAgo++)
          SignalReading(
            id: 'reaction-$daysAgo',
            type: SignalType.reactionTime,
            value: 275,
            timestamp: today.subtract(Duration(days: daysAgo)),
          ),
      ],
    );
    final reaction = baselines.metric(PersonalBaselineType.reactionTime)!;

    expect(reaction.isReady, isFalse);
    expect(reaction.samplesNeeded, 2);
    expect(reaction.readiness, .6);
    expect(
      PersonalBaselineLogic.differencePercent(current: 250, baseline: reaction),
      isNull,
    );
  });
}
