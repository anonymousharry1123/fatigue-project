import 'package:app/src/daily_history_logic.dart';
import 'package:app/src/models.dart';
import 'package:app/src/oura_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Oura uses original sleep day while other signals keep local dates', () {
    final timestamp = DateTime(2026, 10, 24, 9);
    final oura = SignalReading(
      id: 'oura-hrv-2026-10-23',
      type: SignalType.hrv,
      value: 50,
      timestamp: timestamp,
      source: SignalSource.oura,
      sourceDay: '2026-10-23',
      measurementMethod: OuraData.hrvMethod,
    );
    final apple = oura.copyWith(
      id: 'apple',
      source: SignalSource.healthKit,
      measurementMethod: 'sdnn',
    );
    final history = DailyHistoryLogic.build(
      signals: [oura, apple],
      checkIns: [],
      activityLogs: [],
      sleepLogs: [],
      now: DateTime(2026, 10, 25),
    );
    expect(history.map((day) => day.date), [
      DateTime(2026, 10, 24),
      DateTime(2026, 10, 23),
    ]);
    expect(history.first.items.single.signal, apple);
    expect(history.last.items.single.signal, oura);
    expect(history.last.items.single.canDelete, isFalse);
  });

  test(
    'history suppresses identified Oura mirrors without changing raw records',
    () {
      final timestamp = DateTime(2026, 10, 24, 9);
      final oura = SignalReading(
        id: 'oura-hrv-2026-10-24',
        type: SignalType.hrv,
        value: 50,
        timestamp: timestamp,
        source: SignalSource.oura,
        sourceDay: '2026-10-24',
        measurementMethod: OuraData.hrvMethod,
      );
      final mirror = oura.copyWith(
        id: 'mirror',
        source: SignalSource.healthKit,
        sourceBundleId: 'com.ouraring.oura',
      );
      final apple = oura.copyWith(
        id: 'apple',
        source: SignalSource.healthKit,
        sourceBundleId: 'com.apple.health',
        measurementMethod: 'sdnn',
      );
      final signals = [oura, mirror, apple];
      List<DailyHistoryDay> history(List<SignalReading> values) =>
          DailyHistoryLogic.build(
            signals: values,
            checkIns: [],
            activityLogs: [],
            sleepLogs: [],
            now: DateTime(2026, 10, 25),
          );
      expect(
        history(signals).single.items.map((item) => item.id),
        unorderedEquals([oura.id, apple.id]),
      );
      expect(signals, hasLength(3));
      expect(history([mirror]).single.items.single.signal, mirror);
      final futureOura = oura.copyWith(timestamp: DateTime(2026, 10, 26));
      expect(history([futureOura, mirror]).single.items.single.signal, mirror);
    },
  );

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
