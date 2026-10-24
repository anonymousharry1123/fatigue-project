import 'dart:async';

import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/forecast_day_store.dart';
import 'package:app/src/local_day.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 10, 24);
  ForecastPoint point(int hour, {double energy = 60, DateTime? updatedAt}) =>
      ForecastPoint(
        DateTime(day.year, day.month, day.day, hour),
        energy,
        12,
        updatedAt: updatedAt ?? day,
        rulesVersion: 'rules-1',
        signalEvidenceIds: const ['sleep-1', 'hrv-1'],
        checkInEvidenceIds: const ['check-in-1'],
      );

  test(
    'daily packing preserves every forecast point field and calendar bounds',
    () {
      final points = [point(18), point(8)];
      final packed = forecastDayToCloud(day, points);
      final restored = forecastDayFromCloud(packed);
      expect(packed['localDate'], '2026-10-24');
      expect(packed['day'], localDay(day));
      expect(packed['dayEnd'], localDay(day, 1));
      expect(packed['utcOffsetMinutes'], day.timeZoneOffset.inMinutes);
      expect(restored.map((p) => p.time.hour), [8, 18]);
      expect(
        sameSyncValue(
          restored.map(forecastPointToCloud).toList(),
          [point(8), point(18)].map(forecastPointToCloud).toList(),
        ),
        isTrue,
      );
    },
  );

  test('calendar boundaries include the last hour on a DST transition day', () {
    for (final start in [DateTime(2026, 3, 8), DateTime(2026, 11, 1)]) {
      final lastHour = DateTime(start.year, start.month, start.day, 23);
      final packed = forecastDayToCloud(start, [
        ForecastPoint(lastHour, 60, 12, updatedAt: start),
      ]);
      expect(
        packed['dayEnd'],
        DateTime(start.year, start.month, start.day + 1),
      );
      expect(forecastDayFromCloud(packed).single.time, lastHour);
    }
  });

  test('packing and decoding reject mixed days and duplicate instants', () {
    expect(() => forecastDayToCloud(day, [point(24)]), throwsArgumentError);
    expect(
      () => forecastDayToCloud(day, [point(8), point(8)]),
      throwsArgumentError,
    );
    final packed = forecastDayToCloud(day, [point(8)]);
    expect(
      () => forecastDayFromCloud({...packed, 'formatVersion': 2}),
      throwsFormatException,
    );
    expect(
      () => forecastDayFromCloud({...packed, 'dayEnd': day}),
      throwsFormatException,
    );
  });

  test(
    'semantic equality ignores only generation time and order of input points',
    () {
      final before = forecastDayToCloud(day, [point(8), point(18)]);
      final regenerated = forecastDayToCloud(day, [
        point(18, updatedAt: day.add(const Duration(hours: 1))),
        point(8, updatedAt: day.add(const Duration(hours: 1))),
      ]);
      expect(sameForecastDayContent(before, regenerated), isTrue);
      expect(
        sameForecastDayContent(
          before,
          forecastDayToCloud(day, [point(8, energy: 61), point(18)]),
        ),
        isFalse,
      );
    },
  );

  test(
    'legacy days migrate once; empty days do not repeat legacy queries',
    () async {
      final fake = _FakeStore()..legacy.addAll([point(8), point(18)]);
      final first = await fake.store.readRange(
        'owner',
        start: day,
        end: localDay(day, 3),
      );
      expect(first, hasLength(2));
      expect(fake.legacyReads, 1);
      expect(fake.writes, 3);
      expect(fake.documents['owner'], hasLength(3));
      final second = await fake.store.readRange(
        'owner',
        start: day,
        end: localDay(day, 3),
      );
      expect(second, hasLength(2));
      expect(fake.legacyReads, 1);
      expect(fake.writes, 3);
    },
  );

  test(
    'reads filter partial boundaries and packed data wins over retained legacy',
    () async {
      final fake = _FakeStore()
        ..legacy.addAll([point(8, energy: 10), point(18)]);
      fake.documents['owner'] = {
        '2026-10-24': forecastDayToCloud(day, [point(8), point(18)]),
      };
      final result = await fake.store.readRange(
        'owner',
        start: point(8).time,
        end: point(18).time,
      );
      expect(result, hasLength(1));
      expect(result.single.energy, 60);
      expect(fake.legacyReads, 0);
      expect(fake.writes, 0);
    },
  );

  test(
    'replacement is one write and unchanged regeneration skips all extra IO',
    () async {
      final fake = _FakeStore();
      await fake.store.replaceDay(
        'owner',
        day: day,
        points: [point(8), point(18)],
      );
      expect(fake.dayReads, 1);
      expect(fake.writes, 1);
      await fake.store.replaceDay(
        'owner',
        day: day,
        points: [
          point(8, updatedAt: day.add(const Duration(hours: 1))),
          point(18, updatedAt: day.add(const Duration(hours: 1))),
        ],
      );
      expect(fake.dayReads, 1);
      expect(fake.writes, 1);
      expect(
        forecastDayFromCloud(
          fake.documents['owner']!['2026-10-24']!,
        ).first.updatedAt,
        day,
      );
      await fake.store.replaceDay(
        'owner',
        day: day,
        points: [point(8, energy: 50)],
      );
      expect(fake.writes, 2);
      expect(fake.legacyReads, 0);
    },
  );

  test('failed writes are retried and never cached as acknowledged', () async {
    final fake = _FakeStore()..failWrite = true;
    await expectLater(
      fake.store.replaceDay('owner', day: day, points: [point(8)]),
      throwsStateError,
    );
    fake.failWrite = false;
    await fake.store.replaceDay('owner', day: day, points: [point(8)]);
    expect(fake.writes, 2);
    expect(fake.documents['owner'], hasLength(1));
  });

  test(
    'cache is owner scoped and range-loaded days skip replacement rereads',
    () async {
      final fake = _FakeStore();
      fake.documents['owner'] = {
        '2026-10-24': forecastDayToCloud(day, [point(8)]),
      };
      await fake.store.readRange('owner', start: day, end: localDay(day, 1));
      await fake.store.replaceDay('owner', day: day, points: [point(8)]);
      expect(fake.dayReads, 0);
      expect(fake.writes, 0);
      await fake.store.replaceDay('other-owner', day: day, points: [point(8)]);
      expect(fake.dayReads, 1);
      expect(fake.writes, 1);
      expect(fake.documents['other-owner'], hasLength(1));
    },
  );

  test(
    'owner cache reset forces an authoritative read before replacement',
    () async {
      final fake = _FakeStore();
      await fake.store.replaceDay('owner', day: day, points: [point(8)]);
      fake.documents.clear();
      fake.store.clearOwner('owner');
      await fake.store.replaceDay('owner', day: day, points: [point(8)]);
      expect(fake.dayReads, 2);
      expect(fake.writes, 2);
    },
  );

  test(
    'owner reset rejects an in-flight read before it can revive the cache',
    () async {
      final pending = Completer<Map<String, Map<String, dynamic>>>();
      var writes = 0;
      final store = ForecastDayStore(
        loadDays: (_, _, _) => pending.future,
        loadDay: (_, _) async => null,
        loadLegacy: (_, _, _) async => [],
        writeDay: (_, _, _) async {
          writes++;
        },
      );
      final read = store.readRange('owner', start: day, end: localDay(day, 1));
      store.clearOwner('owner');
      pending.complete({
        '2026-10-24': forecastDayToCloud(day, [point(8)]),
      });
      await expectLater(read, throwsStateError);
      await store.replaceDay('owner', day: day, points: [point(8)]);
      expect(writes, 1);
    },
  );

  test(
    'clearing memory guidance removes saved forecasts for the owner',
    () async {
      final repository = MemoryCloudRepository(signedInUid: 'owner');
      await repository.replaceForecastPoints(
        'owner',
        day: day,
        points: [point(8)],
      );
      await expectLater(
        repository.clearGuidance('another-owner'),
        throwsStateError,
      );
      expect(
        await repository.forecastPointsByRange(
          'owner',
          start: day,
          end: localDay(day, 1),
        ),
        hasLength(1),
      );
      await repository.clearGuidance('owner');
      expect(
        await repository.forecastPointsByRange(
          'owner',
          start: day,
          end: localDay(day, 1),
        ),
        isEmpty,
      );
    },
  );
}

class _FakeStore {
  final documents = <String, Map<String, Map<String, dynamic>>>{};
  final legacy = <ForecastPoint>[];
  int legacyReads = 0;
  int dayReads = 0;
  int writes = 0;
  bool failWrite = false;

  late final store = ForecastDayStore(
    loadDays: (uid, firstDate, lastDate) async => {
      for (final entry in (documents[uid] ?? {}).entries)
        if (entry.key.compareTo(firstDate) >= 0 &&
            entry.key.compareTo(lastDate) <= 0)
          entry.key: entry.value,
    },
    loadDay: (uid, id) async {
      dayReads++;
      return documents[uid]?[id];
    },
    loadLegacy: (uid, start, end) async {
      legacyReads++;
      return legacy
          .where(
            (point) => !point.time.isBefore(start) && point.time.isBefore(end),
          )
          .toList();
    },
    writeDay: (uid, id, data) async {
      writes++;
      if (failWrite) throw StateError('Quota exceeded');
      documents.putIfAbsent(uid, () => {})[id] = data;
    },
  );
}
