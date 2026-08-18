import 'package:app/src/activity_sync_logic.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Version 0.25 normalizes imports without replacing manual rows', () {
    final timestamp = DateTime.utc(2026, 8, 17, 10);
    final manual = SignalReading(
      id: 'manual-exercise',
      type: SignalType.exercise,
      value: 1,
      timestamp: timestamp.toLocal(),
    );
    final existingHealth = SignalReading(
      id: 'healthkit-water-existing',
      type: SignalType.hydration,
      value: .25,
      timestamp: timestamp.toLocal(),
      source: SignalSource.healthKit,
    );

    final result = ActivitySyncLogic.merge(
      existing: [manual, existingHealth],
      imported: [
        SignalReading(
          id: 'healthkit-workout',
          type: SignalType.exercise,
          value: 1,
          timestamp: timestamp,
          source: SignalSource.manual,
          quality: 1.4,
        ),
        SignalReading(
          id: 'healthkit-water-existing',
          type: SignalType.hydration,
          value: .25,
          timestamp: timestamp,
        ),
        SignalReading(
          id: 'healthkit-water-near-duplicate',
          type: SignalType.hydration,
          value: .26,
          timestamp: timestamp.add(const Duration(minutes: 2)),
        ),
        SignalReading(
          id: 'healthkit-invalid',
          type: SignalType.hydration,
          value: -1,
          timestamp: timestamp,
        ),
        SignalReading(
          id: 'healthkit-wrong-type',
          type: SignalType.study,
          value: 1,
          timestamp: timestamp,
        ),
      ],
    );

    expect(result.importedCount, 1);
    expect(result.duplicateCount, 2);
    expect(result.rejectedCount, 2);
    expect(result.readings, contains(manual));
    final workout = result.readings.singleWhere(
      (item) => item.id == 'healthkit-workout',
    );
    expect(workout.source, SignalSource.healthKit);
    expect(workout.quality, 1);
    expect(workout.timestamp.isUtc, isFalse);
  });

  test('Version 0.25 unions overlapping workouts into daily training load', () {
    final day = DateTime(2026, 8, 17);
    final readings = [
      SignalReading(
        id: 'workout-a',
        type: SignalType.exercise,
        value: 2,
        timestamp: day.add(const Duration(hours: 10)),
        source: SignalSource.healthKit,
      ),
      SignalReading(
        id: 'workout-b',
        type: SignalType.exercise,
        value: 2,
        timestamp: day.add(const Duration(hours: 11)),
        source: SignalSource.healthKit,
      ),
    ];

    final aggregate = ActivitySyncLogic.trainingLoadForDay(readings, day: day);

    expect(aggregate, isNotNull);
    expect(aggregate!.total, 3);
    expect(aggregate.evidence, hasLength(2));
    expect(aggregate.usesManualCorrection, isFalse);
  });

  test(
    'manual correction overrides imports and deletion restores fallback',
    () {
      final day = DateTime(2026, 8, 17);
      final imported = [
        SignalReading(
          id: 'workout',
          type: SignalType.exercise,
          value: 2,
          timestamp: day.add(const Duration(hours: 10)),
          source: SignalSource.healthKit,
        ),
        SignalReading(
          id: 'water-a',
          type: SignalType.hydration,
          value: .4,
          timestamp: day.add(const Duration(hours: 9)),
          source: SignalSource.healthKit,
        ),
        SignalReading(
          id: 'water-b',
          type: SignalType.hydration,
          value: .6,
          timestamp: day.add(const Duration(hours: 11)),
          source: SignalSource.healthKit,
        ),
      ];
      final corrections = [
        SignalReading(
          id: 'activity-manual-exercise',
          groupId: 'activity-manual',
          type: SignalType.exercise,
          value: .75,
          timestamp: day.add(const Duration(hours: 12)),
        ),
        SignalReading(
          id: 'activity-manual-hydration',
          groupId: 'activity-manual',
          type: SignalType.hydration,
          value: 1.8,
          timestamp: day.add(const Duration(hours: 12)),
        ),
      ];

      final correctedExercise = ActivitySyncLogic.aggregateForDay(
        [...imported, ...corrections],
        type: SignalType.exercise,
        day: day,
      );
      final correctedHydration = ActivitySyncLogic.aggregateForDay(
        [...imported, ...corrections],
        type: SignalType.hydration,
        day: day,
      );
      final fallbackExercise = ActivitySyncLogic.aggregateForDay(
        imported,
        type: SignalType.exercise,
        day: day,
      );
      final fallbackHydration = ActivitySyncLogic.aggregateForDay(
        imported,
        type: SignalType.hydration,
        day: day,
      );

      expect(correctedExercise!.total, .75);
      expect(correctedExercise.usesManualCorrection, isTrue);
      expect(correctedHydration!.total, 1.8);
      expect(fallbackExercise!.total, 2);
      expect(fallbackHydration!.total, 1);
    },
  );

  test('blank manual placeholders do not override an imported value', () {
    final day = DateTime(2026, 8, 17);
    final imported = SignalReading(
      id: 'workout',
      type: SignalType.exercise,
      value: 2,
      timestamp: day.add(const Duration(hours: 10)),
      source: SignalSource.healthKit,
    );
    final blank = SignalReading(
      id: 'activity-study-only-exercise',
      type: SignalType.exercise,
      value: 0,
      timestamp: day.add(const Duration(hours: 12)),
      note: ActivitySyncLogic.blankManualValueNote,
    );
    final explicitZero = SignalReading(
      id: 'activity-zero-exercise',
      type: SignalType.exercise,
      value: 0,
      timestamp: day.add(const Duration(hours: 13)),
      note: ActivitySyncLogic.manualCorrectionNote,
    );

    expect(
      ActivitySyncLogic.trainingLoadForDay([imported, blank], day: day)!.total,
      2,
    );
    final corrected = ActivitySyncLogic.trainingLoadForDay([
      imported,
      blank,
      explicitZero,
    ], day: day);
    expect(corrected!.total, 0);
    expect(corrected.usesManualCorrection, isTrue);
  });

  test('daily step totals update in place instead of accumulating', () {
    final day = DateTime(2026, 8, 18);
    SignalReading steps(double value, int hour) => SignalReading(
      id: 'healthkit-steps-2026-08-18',
      type: SignalType.steps,
      value: value,
      timestamp: day.add(Duration(hours: hour)),
      source: SignalSource.healthKit,
    );

    final result = ActivitySyncLogic.merge(
      existing: [steps(1200, 10)],
      imported: [steps(6400, 15)],
    );
    final aggregate = ActivitySyncLogic.aggregateForDay(
      result.readings,
      type: SignalType.steps,
      day: day,
    );

    expect(result.importedCount, 1);
    expect(result.duplicateCount, 0);
    expect(result.readings, hasLength(1));
    expect(aggregate!.total, 6400);
  });
}
