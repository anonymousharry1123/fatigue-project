import 'package:app/src/check_in_logic.dart';
import 'package:app/src/daily_plan_logic.dart';
import 'package:app/src/insights_logic.dart';
import 'package:app/src/local_day.dart';
import 'package:app/src/models.dart';
import 'package:app/src/today_dashboard_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UTC and local views of an instant share a calendar day', () {
    final instant = DateTime.utc(2026, 9, 19, 1);
    final local = instant.toLocal();
    expect(localDay(instant), DateTime(local.year, local.month, local.day));
    expect(localDayKey(instant), localDayKey(local));
    expect(CheckInLogic.periodFor(instant), CheckInLogic.periodFor(local));
  });

  for (final day in [DateTime(2026, 3, 8), DateTime(2026, 11, 1)]) {
    test(
      'calendar boundaries include late records on ${day.month}/${day.day}',
      () {
        final late = DateTime(day.year, day.month, day.day, 23, 30);
        final next = localDay(day, 1);
        expect(next.hour, 0);
        expect(next.day, day.day + 1);
        expect(late.isBefore(next), isTrue);
        final readings = [
          SignalReading(
            id: 'late-study',
            type: SignalType.study,
            value: 1,
            timestamp: late.toUtc(),
          ),
        ];
        final today = TodayDashboardLogic.summariesForDay(
          readings,
          day: day,
          now: late,
        );
        expect(
          today
              .singleWhere((item) => item.type == SignalType.study)
              .displayValue,
          '1.0 hr',
        );
        final insights = InsightsLogic.build(
          now: late,
          signals: readings,
          checkIns: [],
        );
        expect(
          insights.currentDays.map((item) => localDayKey(item.date)).toSet(),
          hasLength(7),
        );
        expect(insights.currentDays.last.studyHours, 1);
      },
    );
  }

  test('overnight clock normalization preserves wall times through DST', () {
    for (final wake in [DateTime(2026, 3, 8, 7), DateTime(2026, 11, 1, 7)]) {
      final pair = SleepLogEntry.normalizeOvernightPair(
        bedtime: DateTime(wake.year, wake.month, wake.day, 23),
        wakeTime: wake,
      );
      expect(pair.$1, DateTime(wake.year, wake.month, wake.day - 1, 23));
      expect(pair.$2, wake);
      expect(pair.$2.difference(pair.$1).inHours, inInclusiveRange(7, 9));
    }
  });

  test(
    'Coach wake schedule retains local wall time on DST transition days',
    () {
      for (final day in [DateTime(2026, 3, 8), DateTime(2026, 11, 1)]) {
        DateTime at(int hour) => DateTime(day.year, day.month, day.day, hour);
        final evidence = ForecastEvidence(
          id: 'sleep-main',
          kind: ForecastEvidenceKind.signal,
          label: 'Sleep',
          detail: 'Main sleep',
          timestamp: at(7),
          signalType: SignalType.sleep,
          source: SignalSource.manual,
        );
        final plan = DailyPlanLogic.build(
          windows: [
            ForecastWindow(
              ForecastWindowType.peak,
              at(9),
              at(11),
              80,
              'Peak',
              evidence: [evidence],
            ),
            ForecastWindow(
              ForecastWindowType.crash,
              at(14),
              at(15),
              50,
              'Dip',
              evidence: [evidence],
            ),
            ForecastWindow(
              ForecastWindowType.recovery,
              at(17),
              at(18),
              70,
              'Recovery',
              evidence: [evidence],
            ),
          ],
          score: const ScoreSnapshot(
            energy: 70,
            cognitive: 70,
            confidence: .8,
            cognitiveConfidence: .8,
            drivers: [],
          ),
          profile: const UserProfile(wakeHour: 7, bedHour: 23),
          day: day.toUtc(),
          generatedAt: at(6),
        );
        expect(
          plan.first.scheduledAt,
          DateTime(day.year, day.month, day.day, 7, 15),
        );
      }
    },
  );
}
