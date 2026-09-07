import 'package:app/src/models.dart';
import 'package:app/src/sleep_sync_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SignalReading sample({
    required String id,
    required SignalType type,
    required DateTime start,
    required DateTime end,
    required String source,
  }) => SignalReading(
    id: id,
    type: type,
    value: end.difference(start).inMinutes / 60,
    timestamp: end,
    source: SignalSource.healthKit,
    groupId: source,
  );

  test('Version 0.24 reconciles overlapping HealthKit sleep sources', () {
    final day = DateTime(2026, 8, 17);
    final start = day.subtract(const Duration(hours: 2));
    final imported = [
      sample(
        id: 'phone-unspecified',
        type: SignalType.sleepUnspecified,
        start: start,
        end: day.add(const Duration(hours: 6)),
        source: 'phone',
      ),
      sample(
        id: 'watch-core-1',
        type: SignalType.sleepCore,
        start: start,
        end: day,
        source: 'watch',
      ),
      sample(
        id: 'watch-deep',
        type: SignalType.sleepDeep,
        start: day,
        end: day.add(const Duration(hours: 1)),
        source: 'watch',
      ),
      sample(
        id: 'watch-core-2',
        type: SignalType.sleepCore,
        start: day.add(const Duration(hours: 1)),
        end: day.add(const Duration(hours: 4)),
        source: 'watch',
      ),
      sample(
        id: 'watch-rem-1',
        type: SignalType.sleepRem,
        start: day.add(const Duration(hours: 4)),
        end: day.add(const Duration(hours: 5)),
        source: 'watch',
      ),
      sample(
        id: 'watch-awake',
        type: SignalType.sleepAwake,
        start: day.add(const Duration(hours: 5)),
        end: day.add(const Duration(hours: 5, minutes: 15)),
        source: 'watch',
      ),
      sample(
        id: 'watch-rem-2',
        type: SignalType.sleepRem,
        start: day.add(const Duration(hours: 5, minutes: 15)),
        end: day.add(const Duration(hours: 6)),
        source: 'watch',
      ),
    ];

    final first = SleepSyncLogic.merge(existing: const [], imported: imported);

    expect(first.importedNightCount, 1);
    expect(first.rejectedSampleCount, 0);
    expect(first.importedSignalCount, 6);
    expect(
      first.readings
          .where((item) => item.type == SignalType.sleep)
          .single
          .value,
      7.75,
    );
    expect(
      first.readings
          .where((item) => item.type == SignalType.sleepCore)
          .single
          .value,
      5,
    );
    expect(
      first.readings
          .where((item) => item.type == SignalType.sleepDeep)
          .single
          .value,
      1,
    );
    expect(
      first.readings
          .where((item) => item.type == SignalType.sleepRem)
          .single
          .value,
      1.75,
    );
    expect(
      first.readings
          .where((item) => item.type == SignalType.sleepAwake)
          .single
          .value,
      .25,
    );
    expect(
      first.readings.where((item) => item.type == SignalType.sleepUnspecified),
      isEmpty,
    );
    expect(first.readings.first.note, contains('2 Apple Health sources'));

    final second = SleepSyncLogic.merge(
      existing: first.readings,
      imported: imported,
    );
    expect(second.importedSignalCount, 0);
    expect(second.duplicateCount, 6);
    expect(second.readings, hasLength(6));
  });

  test('Version 0.24 keeps manual sleep when an import is incomplete', () {
    final wake = DateTime(2026, 8, 17, 7);
    final manual = SignalReading(
      id: 'sleep-manual-duration',
      groupId: 'sleep-manual',
      type: SignalType.sleep,
      value: 8,
      timestamp: wake,
    );
    final result = SleepSyncLogic.merge(
      existing: [manual],
      imported: [
        sample(
          id: 'phone-unspecified',
          type: SignalType.sleepUnspecified,
          start: wake.subtract(const Duration(hours: 7, minutes: 30)),
          end: wake,
          source: 'phone',
        ),
      ],
    );

    expect(result.skippedManualNightCount, 1);
    expect(
      result.readings.where(
        (item) =>
            item.type == SignalType.sleep &&
            item.source == SignalSource.healthKit,
      ),
      isEmpty,
    );
    expect(
      result.readings.where((item) => item.type == SignalType.sleepUnspecified),
      hasLength(1),
    );
    expect(SleepSyncLogic.preferredSleepReadings(result.readings), [manual]);
  });

  test(
    'identical sleep refresh preserves original availability timestamps',
    () {
      final wake = DateTime(2026, 8, 17, 7);
      final firstSync = wake.add(const Duration(hours: 1));
      final laterSync = wake.add(const Duration(days: 10));
      final imported = [
        sample(
          id: 'watch-core',
          type: SignalType.sleepCore,
          start: wake.subtract(const Duration(hours: 8)),
          end: wake,
          source: 'watch',
        ),
      ];
      final first = SleepSyncLogic.merge(
        existing: const [],
        imported: imported,
        syncedAt: firstSync,
      );
      // An optional persisted record time must survive unchanged too.
      final saved = [
        for (final reading in first.readings)
          reading.copyWith(recordedAt: firstSync),
      ];
      final duplicate = SleepSyncLogic.merge(
        existing: saved,
        imported: imported,
        syncedAt: laterSync,
      );
      expect(duplicate.importedSignalCount, 0);
      expect(duplicate.duplicateCount, saved.length);
      expect(duplicate.readings.length, saved.length);
      for (final reading in duplicate.readings) {
        final original = saved.firstWhere((value) => value.id == reading.id);
        expect(identical(reading, original), isTrue);
        expect(reading.syncedAt, firstSync);
        expect(reading.recordedAt, firstSync);
        expect(reading.timestamp, original.timestamp);
      }
    },
  );

  test(
    'changed sleep import receives fresh availability instead of retaining old value',
    () {
      final wake = DateTime(2026, 8, 17, 7);
      final firstSync = wake.add(const Duration(hours: 1));
      final laterSync = wake.add(const Duration(hours: 2));
      List<SignalReading> imported(int hours) => [
        sample(
          id: 'watch-core',
          type: SignalType.sleepCore,
          start: wake.subtract(Duration(hours: hours)),
          end: wake,
          source: 'watch',
        ),
      ];
      final first = SleepSyncLogic.merge(
        existing: const [],
        imported: imported(7),
        syncedAt: firstSync,
      );
      final changed = SleepSyncLogic.merge(
        existing: first.readings,
        imported: imported(8),
        syncedAt: laterSync,
      );
      expect(changed.importedSignalCount, greaterThan(0));
      final total = changed.readings.singleWhere(
        (value) => value.type == SignalType.sleep,
      );
      expect(total.value, 8);
      expect(total.syncedAt, laterSync);
      expect(total.recordedAt, isNull);
    },
  );

  test('duplicate samples cannot inflate a source completeness score', () {
    final wake = DateTime(2026, 8, 17, 7);
    final start = wake.subtract(const Duration(hours: 8));
    final imported = [
      sample(
        id: 'complete-core',
        type: SignalType.sleepCore,
        start: start,
        end: wake,
        source: 'complete-source',
      ),
      for (var index = 0; index < 10; index += 1)
        sample(
          id: 'duplicate-deep-$index',
          type: SignalType.sleepDeep,
          start: start,
          end: start.add(const Duration(hours: 1)),
          source: 'duplicate-source',
        ),
    ];

    final result = SleepSyncLogic.merge(existing: const [], imported: imported);

    expect(
      result.readings
          .where((item) => item.type == SignalType.sleepCore)
          .single
          .value,
      8,
    );
    expect(
      result.readings.where((item) => item.type == SignalType.sleepDeep),
      isEmpty,
    );
  });

  test('Version 0.24 prefers a sufficiently complete staged import', () {
    final wake = DateTime(2026, 8, 17, 7);
    final manual = SignalReading(
      id: 'sleep-manual-duration',
      groupId: 'sleep-manual',
      type: SignalType.sleep,
      value: 8,
      timestamp: wake,
    );
    final start = wake.subtract(const Duration(hours: 8));
    final result = SleepSyncLogic.merge(
      existing: [manual],
      imported: [
        sample(
          id: 'watch-core',
          type: SignalType.sleepCore,
          start: start,
          end: start.add(const Duration(hours: 5)),
          source: 'watch',
        ),
        sample(
          id: 'watch-deep',
          type: SignalType.sleepDeep,
          start: start.add(const Duration(hours: 5)),
          end: start.add(const Duration(hours: 6, minutes: 30)),
          source: 'watch',
        ),
        sample(
          id: 'watch-rem',
          type: SignalType.sleepRem,
          start: start.add(const Duration(hours: 6, minutes: 30)),
          end: wake,
          source: 'watch',
        ),
      ],
    );

    expect(result.skippedManualNightCount, 0);
    final preferred = SleepSyncLogic.preferredSleepReadings(result.readings);
    expect(preferred, hasLength(1));
    expect(preferred.single.source, SignalSource.healthKit);
    expect(preferred.single.value, 8);
  });
}
