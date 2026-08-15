import 'package:app/src/insights_logic.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 15, 20);
  final today = DateTime(2026, 8, 15);

  SignalReading signal(
    String id,
    SignalType type,
    double value,
    DateTime timestamp,
  ) => SignalReading(id: id, type: type, value: value, timestamp: timestamp);

  group('Version 0.21 InsightsLogic', () {
    test('aggregates current and prior seven-day ranges', () {
      final signals = <SignalReading>[];
      final checkIns = <DailyCheckIn>[];
      for (var offset = 0; offset < 14; offset++) {
        final day = today.subtract(Duration(days: 13 - offset));
        final currentIndex = offset - 7;
        final sleep = offset < 7 ? 6.0 : 6.0 + currentIndex * .3;
        final training = offset < 7 ? .25 : .5 + currentIndex * .1;
        final study = offset < 7 ? 1.0 : 2.0 + currentIndex * .5;
        signals.addAll([
          signal(
            'sleep-$offset',
            SignalType.sleep,
            sleep,
            day.add(const Duration(hours: 7)),
          ),
          signal(
            'exercise-$offset',
            SignalType.exercise,
            training,
            day.add(const Duration(hours: 17)),
          ),
          signal(
            'study-$offset',
            SignalType.study,
            study,
            day.add(const Duration(hours: 18)),
          ),
        ]);
        checkIns.add(
          DailyCheckIn(
            id: 'check-$offset',
            timestamp: day.add(const Duration(hours: 19)),
            energy: 5 + offset / 10,
            mood: 6,
            stress: 4,
          ),
        );
      }

      final result = InsightsLogic.build(
        now: now,
        signals: signals,
        checkIns: checkIns,
      );

      expect(result.currentDays, hasLength(7));
      expect(result.previousDays, hasLength(7));
      expect(result.currentDays.first.date, DateTime(2026, 8, 9));
      expect(result.currentDays.last.date, today);
      expect(result.currentSummary.averageSleepHours, closeTo(6.9, .001));
      expect(result.currentSummary.trainingHours, closeTo(5.6, .001));
      expect(result.currentSummary.studyHours, closeTo(24.5, .001));
      expect(result.currentSummary.averageEstimatedEnergy, isNotNull);
      expect(result.currentSummary.trackedDayCount, 7);
      expect(result.previousSummary.averageSleepHours, 6);
      expect(result.sourceSignalCount, 21);
      expect(result.sourceCheckInCount, 7);
    });

    test(
      'keeps missing metrics blank and uses the latest nightly sleep row',
      () {
        final day = today.subtract(const Duration(days: 1));
        final result = InsightsLogic.build(
          now: now,
          signals: [
            signal(
              'sleep-old',
              SignalType.sleep,
              4,
              day.add(const Duration(hours: 6)),
            ),
            signal(
              'sleep-new',
              SignalType.sleep,
              8,
              day.add(const Duration(hours: 8)),
            ),
          ],
          checkIns: const [],
        );
        final yesterday = result.currentDays[result.currentDays.length - 2];

        expect(yesterday.sleepHours, 8);
        expect(yesterday.trainingHours, isNull);
        expect(yesterday.studyHours, isNull);
        expect(result.currentSummary.trainingHours, isNull);
        expect(result.currentSummary.studyHours, isNull);
      },
    );

    test('excludes future and out-of-window entries', () {
      final result = InsightsLogic.build(
        now: now,
        signals: [
          signal(
            'future',
            SignalType.study,
            8,
            today.add(const Duration(hours: 22)),
          ),
          signal(
            'old',
            SignalType.exercise,
            3,
            today.subtract(const Duration(days: 21)),
          ),
        ],
        checkIns: const [],
      );

      expect(result.hasCurrentData, isFalse);
      expect(result.sourceSignalCount, 0);
      expect(result.currentSummary.averageEstimatedEnergy, isNull);
    });

    test('associations are sample-gated and explicitly non-causal', () {
      final signals = <SignalReading>[];
      for (var index = 0; index < 7; index++) {
        final day = today.subtract(Duration(days: 6 - index));
        signals.addAll([
          signal(
            'sleep-$index',
            SignalType.sleep,
            5.5 + index * .4,
            day.add(const Duration(hours: 7)),
          ),
          signal(
            'study-$index',
            SignalType.study,
            1 + index.toDouble(),
            day.add(const Duration(hours: 16)),
          ),
        ]);
      }

      final result = InsightsLogic.build(
        now: now,
        signals: signals,
        checkIns: const [],
      );

      expect(result.associations, isNotEmpty);
      expect(result.associations.every((item) => item.sampleDays >= 3), isTrue);
      expect(
        result.associations.every(
          (item) => item.detail.contains('not proof of cause'),
        ),
        isTrue,
      );
      expect(
        result.associations.map((item) => item.metric),
        isNot(contains(InsightTrendMetric.training)),
      );
    });
  });
}
