import 'package:app/src/models.dart';
import 'package:app/src/sleep_sync_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 9, 19);
  final mainStart = DateTime(2026, 9, 18, 23);
  final mainEnd = DateTime(2026, 9, 19, 7);

  SignalReading sample(String id, DateTime start, DateTime end) =>
      SignalReading(
        id: id,
        type: SignalType.sleepCore,
        value: end.difference(start).inMinutes / 60,
        timestamp: end,
        source: SignalSource.healthKit,
        groupId: 'watch',
      );

  SignalReading manualMain({double hours = 8}) => SignalReading(
    id: 'sleep-main-duration',
    groupId: 'sleep-main',
    type: SignalType.sleep,
    value: hours,
    timestamp: mainEnd,
  );

  test('longest main sleep survives a later legacy short sleep log', () {
    final main = manualMain();
    final later = SignalReading(
      id: 'legacy-short',
      type: SignalType.sleep,
      value: .5,
      timestamp: day.add(const Duration(hours: 15)),
    );
    expect(SleepSyncLogic.preferredSleepReadings([later, main]), [main]);
  });

  test('explicit naps do not enter main sleep or bedtime selections', () {
    final main = manualMain();
    final bedtime = SignalReading(
      id: 'sleep-main-bedtime',
      type: SignalType.bedtime,
      value: 23,
      timestamp: mainStart,
      groupId: main.groupId,
    );
    final nap = SignalReading(
      id: 'sleep-nap-duration',
      type: SignalType.nap,
      value: .5,
      timestamp: day.add(const Duration(hours: 15)),
      groupId: 'sleep-nap',
    );
    final readings = [main, bedtime, nap];
    expect(SleepSyncLogic.preferredSleepReadings(readings), [main]);
    expect(SleepSyncLogic.preferredBedtimeReadings(readings), [bedtime]);
    expect(SleepSyncLogic.preferredNapReadings(readings), [nap]);
  });

  test('full HealthKit import separates main and nap and reimports once', () {
    final imported = [
      sample('main', mainStart, mainEnd),
      sample(
        'nap',
        day.add(const Duration(hours: 14)),
        day.add(const Duration(hours: 14, minutes: 30)),
      ),
    ];
    final firstSync = day.add(const Duration(hours: 15));
    final first = SleepSyncLogic.merge(
      existing: [],
      imported: imported,
      syncedAt: firstSync,
    );
    expect(first.importedNightCount, 1);
    expect(
      SleepSyncLogic.preferredSleepReadings(first.readings).single.value,
      8,
    );
    final nap = SleepSyncLogic.preferredNapReadings(first.readings).single;
    expect(nap.value, .5);
    expect(
      first.readings.where((r) => r.type == SignalType.bedtime),
      hasLength(1),
    );

    final repeat = SleepSyncLogic.merge(
      existing: first.readings,
      imported: imported,
      syncedAt: firstSync.add(const Duration(hours: 1)),
    );
    expect(repeat.importedSignalCount, 0);
    expect(repeat.readings, hasLength(first.readings.length));
    expect(
      SleepSyncLogic.preferredNapReadings(repeat.readings).single.syncedAt,
      firstSync,
    );
  });

  test('nap-only incremental import respects an existing main sleep', () {
    final main = manualMain();
    final result = SleepSyncLogic.merge(
      existing: [main],
      imported: [
        sample(
          'nap',
          day.add(const Duration(hours: 14)),
          day.add(const Duration(hours: 14, minutes: 20)),
        ),
      ],
    );
    expect(result.importedNightCount, 0);
    expect(SleepSyncLogic.preferredSleepReadings(result.readings), [main]);
    expect(
      SleepSyncLogic.preferredNapReadings(result.readings).single.value,
      closeTo(1 / 3, .0001),
    );
  });

  test('shorter corrected HealthKit nap replaces the old interval only', () {
    final first = SleepSyncLogic.merge(
      existing: [manualMain()],
      imported: [
        sample(
          'nap',
          day.add(const Duration(hours: 14)),
          day.add(const Duration(hours: 14, minutes: 30)),
        ),
      ],
    );
    final manualNap = SignalReading(
      id: 'sleep-manual-nap',
      type: SignalType.nap,
      value: .5,
      timestamp: day.add(const Duration(hours: 14, minutes: 30)),
      groupId: 'sleep-manual-nap',
    );
    final unrelated = SignalReading(
      id: 'unrelated-imported-nap',
      type: SignalType.nap,
      value: .5,
      timestamp: day.add(const Duration(hours: 18)),
      source: SignalSource.healthKit,
      groupId: '${SleepSyncLogic.importedNapGroupPrefix}unrelated',
    );
    final corrected = SleepSyncLogic.merge(
      existing: [...first.readings, manualNap, unrelated],
      imported: [
        sample(
          'nap',
          day.add(const Duration(hours: 14)),
          day.add(const Duration(hours: 14, minutes: 15)),
        ),
      ],
    );
    final importedNaps = corrected.readings
        .where(
          (r) => r.type == SignalType.nap && r.source == SignalSource.healthKit,
        )
        .toList();
    expect(importedNaps, hasLength(2));
    expect(importedNaps.map((r) => r.value), containsAll([.25, .5]));
    expect(corrected.readings, containsAll([manualNap, unrelated]));
    expect(
      SleepSyncLogic.preferredNapReadings(
        corrected.readings.where((r) => r.id != manualNap.id),
      ).map((r) => r.value),
      containsAll([.25, .5]),
    );
    expect(
      corrected.readings.any(
        (r) =>
            r.id ==
            first.readings.firstWhere((r) => r.type == SignalType.nap).id,
      ),
      isFalse,
    );
  });

  test('main bedtime excludes overlapping nap despite awake gaps', () {
    final main = manualMain(hours: 6);
    final bedtime = SignalReading(
      id: 'sleep-main-bedtime',
      type: SignalType.bedtime,
      value: 23,
      timestamp: mainStart,
      groupId: main.groupId,
    );
    final nap = SignalReading(
      id: 'overlapping-nap',
      type: SignalType.nap,
      value: .5,
      timestamp: mainStart.add(const Duration(minutes: 45)),
      source: SignalSource.healthKit,
    );
    expect(SleepSyncLogic.preferredNapReadings([main, bedtime, nap]), isEmpty);
  });
}
