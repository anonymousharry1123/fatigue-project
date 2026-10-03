import 'package:app/src/insights_logic.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/models.dart';
import 'package:app/src/personal_baseline_logic.dart';
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
    test(
      'historical series discloses current deterministic recomputations',
      () {
        final result = InsightsLogic.build(
          now: now,
          signals: const [],
          checkIns: const [],
        );

        expect(result.energyModelVersion, FatigueEngine.energyModelVersion);
        expect(
          result.cognitiveModelVersion,
          FatigueEngine.cognitiveModelVersion,
        );
        expect(
          result.calculationBasis,
          contains('current deterministic rules'),
        );
        expect(result.calculationBasis, contains('No learned personalization'));
        expect(result.calculationBasis, contains('not the scores originally'));
        expect(result.currentSummary.averageEstimatedEnergy, isNull);
        expect(
          result.currentDays.every((day) => day.estimatedEnergy == null),
          isTrue,
        );
      },
    );

    test(
      'earliest displayed day receives the full historical baseline window',
      () {
        final historicalDay = today.subtract(const Duration(days: 13));
        final readings = [
          for (var index = 0; index < 7; index++)
            signal(
              'prior-hrv-$index',
              SignalType.hrv,
              40,
              historicalDay.subtract(Duration(days: 35 + index)),
            ),
          signal(
            'historical-hrv',
            SignalType.hrv,
            60,
            historicalDay.add(const Duration(hours: 8)),
          ),
        ];
        final cutoff = historicalDay
            .add(const Duration(days: 1))
            .subtract(const Duration(microseconds: 1));
        final expected = FatigueEngine.score(
          signals: readings,
          checkIns: const [],
          now: cutoff,
          day: historicalDay,
          personalBaselines: PersonalBaselineLogic.build(
            signals: readings,
            asOf: cutoff,
          ),
        );
        final result = InsightsLogic.build(
          now: now,
          signals: readings,
          checkIns: const [],
        );

        expect(InsightsLogic.queryLookbackDays, 56);
        expect(
          expected.personalBaselines!
              .metric(PersonalBaselineType.hrv)!
              .sampleCount,
          7,
        );
        expect(result.previousDays.first.estimatedEnergy, expected.energy);
        expect(result.previousDays.first.hasTrackedData, isTrue);
        expect(result.currentDays.last.estimatedEnergy, isNull);
      },
    );

    test(
      'Today and Insights use the same deterministic reference and baseline',
      () {
        final readings = [
          for (var index = 1; index <= 7; index++)
            signal(
              'hrv-$index',
              SignalType.hrv,
              40,
              today.subtract(Duration(days: index)),
            ),
          signal(
            'hrv-current',
            SignalType.hrv,
            60,
            today.add(const Duration(hours: 8)),
          ),
          signal(
            'study-current',
            SignalType.study,
            0,
            today.add(const Duration(hours: 9)),
          ),
        ];
        final reference = FatigueEngine.score(
          signals: readings,
          checkIns: const [],
          now: now,
          day: today,
          personalBaselines: PersonalBaselineLogic.build(
            signals: readings,
            asOf: today,
          ),
        );
        final result = InsightsLogic.build(
          now: now,
          signals: readings,
          checkIns: const [],
        );

        expect(result.currentDays.last.estimatedEnergy, reference.energy);
        expect(result.currentDays.last.estimatedCognitive, reference.cognitive);
        expect(result.currentDays.last.studyHours, 0);
        expect(result.currentDays.last.trainingHours, isNull);
      },
    );

    test('contextual-only observations do not create a reassuring score', () {
      final result = InsightsLogic.build(
        now: now,
        signals: [
          signal(
            'water',
            SignalType.hydration,
            0,
            today.add(const Duration(hours: 8)),
          ),
          signal(
            'exercise',
            SignalType.exercise,
            0,
            today.add(const Duration(hours: 8)),
          ),
          signal(
            'old-study',
            SignalType.study,
            1,
            today.subtract(const Duration(days: 7)),
          ),
        ],
        checkIns: const [],
      );

      expect(result.currentDays.last.trainingHours, 0);
      expect(result.currentDays.last.estimatedEnergy, isNull);
      expect(result.currentDays.last.estimatedCognitive, isNull);
      expect(result.currentSummary.averageEstimatedEnergy, isNull);
    });

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
