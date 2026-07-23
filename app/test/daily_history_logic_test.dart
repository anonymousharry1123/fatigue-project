import 'package:app/src/daily_history_logic.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DailyHistoryLogic', () {
    test(
      'groups semantic entries by date without grouped-signal duplicates',
      () {
        final day = DateTime(2026, 7, 23);
        const activityId = 'activity-1';
        const sleepId = 'sleep-1';
        final activity = ActivityLogEntry(
          id: activityId,
          timestamp: day.add(const Duration(hours: 18)),
          hydrationLiters: 2,
          studyHours: 3,
          exerciseHours: 1,
          screenTimeHours: 4,
        );
        final sleep = SleepLogEntry(
          id: sleepId,
          bedtime: day.subtract(const Duration(hours: 1)),
          wakeTime: day.add(const Duration(hours: 7)),
          quality: 4,
        );
        final checkIn = DailyCheckIn(
          id: 'checkin-1',
          timestamp: day.add(const Duration(hours: 9)),
          energy: 8,
          mood: 7,
          stress: 3,
        );
        final signals = [
          SignalReading(
            id: '$activityId-hydration',
            groupId: activityId,
            type: SignalType.hydration,
            value: 2,
            timestamp: activity.timestamp,
          ),
          SignalReading(
            id: '$sleepId-duration',
            groupId: sleepId,
            type: SignalType.sleep,
            value: 8,
            timestamp: sleep.wakeTime,
          ),
          SignalReading(
            id: 'reaction-1',
            type: SignalType.reactionTime,
            value: 280,
            timestamp: day.add(const Duration(hours: 10)),
          ),
        ];

        final history = DailyHistoryLogic.build(
          signals: signals,
          checkIns: [checkIn],
          activityLogs: [activity],
          sleepLogs: [sleep],
        );

        expect(history, hasLength(1));
        expect(history.single.date, day);
        expect(history.single.items, hasLength(4));
        expect(history.single.isComplete, isTrue);
        expect(history.single.completionCount, 4);
        expect(
          history.single.items.map((item) => item.kind),
          containsAll(DailyHistoryItemKind.values),
        );
      },
    );

    test('sorts newest days first and keeps imported signals read-only', () {
      final older = DateTime(2026, 7, 21, 8);
      final newer = DateTime(2026, 7, 22, 8);
      final history = DailyHistoryLogic.build(
        signals: [
          SignalReading(
            id: 'health-hrv',
            type: SignalType.hrv,
            value: 52,
            timestamp: older,
            source: SignalSource.healthKit,
          ),
          SignalReading(
            id: 'demo-reaction',
            type: SignalType.reactionTime,
            value: 280,
            timestamp: newer,
          ),
        ],
        checkIns: const [],
        activityLogs: const [],
        sleepLogs: const [],
      );

      expect(history.map((day) => day.date), [
        DateTime(2026, 7, 22),
        DateTime(2026, 7, 21),
      ]);
      expect(history.first.completionCount, 1);
      expect(history.first.items.single.isFixture, isTrue);
      expect(history.first.items.single.canDelete, isFalse);
      expect(history.last.items.single.isManual, isFalse);
    });

    test('assigns an overnight sleep entry to its wake date', () {
      final sleep = SleepLogEntry(
        id: 'sleep-overnight',
        bedtime: DateTime(2026, 7, 22, 23),
        wakeTime: DateTime(2026, 7, 23, 7),
        quality: 4,
      );
      final history = DailyHistoryLogic.build(
        signals: const [],
        checkIns: const [],
        activityLogs: const [],
        sleepLogs: [sleep],
      );

      expect(history.single.date, DateTime(2026, 7, 23));
      expect(history.single.completedCategories, {
        DailyCompletionCategory.sleep,
      });
    });
  });
}
