import 'package:app/src/models.dart';
import 'package:app/src/today_dashboard_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Version 0.13 maps Energy Scores to dashboard fatigue states', () {
    expect(TodayDashboardLogic.statusFor(72), TodayFatigueStatus.fresh);
    expect(TodayDashboardLogic.statusFor(71), TodayFatigueStatus.moderate);
    expect(TodayDashboardLogic.statusFor(52), TodayFatigueStatus.moderate);
    expect(TodayDashboardLogic.statusFor(51), TodayFatigueStatus.fatigued);
  });

  test('Version 0.13 summarizes only available day-scoped signals', () {
    final day = DateTime(2026, 8, 4);
    final summaries = TodayDashboardLogic.summariesForDay(
      [
        SignalReading(
          id: 'water-1',
          type: SignalType.hydration,
          value: .8,
          timestamp: day.add(const Duration(hours: 8)),
        ),
        SignalReading(
          id: 'water-2',
          type: SignalType.hydration,
          value: 1.1,
          timestamp: day.add(const Duration(hours: 10)),
        ),
        SignalReading(
          id: 'reaction',
          type: SignalType.reactionTime,
          value: 274,
          timestamp: day.add(const Duration(hours: 9)),
        ),
        SignalReading(
          id: 'future-study',
          type: SignalType.study,
          value: 3,
          timestamp: day.add(const Duration(hours: 15)),
        ),
        SignalReading(
          id: 'yesterday-sleep',
          type: SignalType.sleep,
          value: 8,
          timestamp: day.subtract(const Duration(hours: 4)),
        ),
      ],
      day: day,
      now: day.add(const Duration(hours: 12)),
    );

    final hydration = summaries.singleWhere(
      (item) => item.type == SignalType.hydration,
    );
    final reaction = summaries.singleWhere(
      (item) => item.type == SignalType.reactionTime,
    );
    final study = summaries.singleWhere(
      (item) => item.type == SignalType.study,
    );
    final sleep = summaries.singleWhere(
      (item) => item.type == SignalType.sleep,
    );

    expect(summaries, hasLength(7));
    expect(hydration.displayValue, '1.9 L');
    expect(hydration.readingCount, 2);
    expect(reaction.displayValue, '274 ms');
    expect(study.isAvailable, isFalse);
    expect(sleep.isAvailable, isFalse);
  });

  test('Version 0.25 uses manual daily activity corrections once', () {
    final day = DateTime(2026, 8, 17);
    final summaries = TodayDashboardLogic.summariesForDay(
      [
        SignalReading(
          id: 'health-workout',
          type: SignalType.exercise,
          value: 2,
          timestamp: day.add(const Duration(hours: 10)),
          source: SignalSource.healthKit,
        ),
        SignalReading(
          id: 'manual-exercise',
          type: SignalType.exercise,
          value: .75,
          timestamp: day.add(const Duration(hours: 12)),
        ),
        SignalReading(
          id: 'health-water',
          type: SignalType.hydration,
          value: .5,
          timestamp: day.add(const Duration(hours: 9)),
          source: SignalSource.healthKit,
        ),
        SignalReading(
          id: 'manual-water',
          type: SignalType.hydration,
          value: 1.8,
          timestamp: day.add(const Duration(hours: 12)),
        ),
      ],
      day: day,
      now: day.add(const Duration(hours: 13)),
    );

    expect(
      summaries
          .singleWhere((item) => item.type == SignalType.exercise)
          .displayValue,
      '0.8 hr',
    );
    expect(
      summaries
          .singleWhere((item) => item.type == SignalType.hydration)
          .displayValue,
      '1.8 L',
    );
  });

  test('shows Apple Health daily steps as a separate signal', () {
    final day = DateTime(2026, 8, 18);
    final summaries = TodayDashboardLogic.summariesForDay(
      [
        SignalReading(
          id: 'healthkit-steps-2026-08-18',
          type: SignalType.steps,
          value: 6432,
          timestamp: day.add(const Duration(hours: 12)),
          source: SignalSource.healthKit,
        ),
      ],
      day: day,
      now: day.add(const Duration(hours: 13)),
    );

    final steps = summaries.singleWhere(
      (item) => item.type == SignalType.steps,
    );
    expect(steps.displayValue, '6432 steps');
    expect(steps.readingCount, 1);
  });
}
