import 'dart:async';
import 'dart:convert';

import 'package:app/src/ai1_capture.dart';
import 'package:app/src/ai1_capture_store.dart';
import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/ai1_study.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements Ai1CaptureStore {
  _Store(this.clock);
  final DateTime Function() clock;
  final values = <String, String>{};
  Future<void> Function()? beforeWrite;
  DateTime? receipt;
  bool fail = false;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<String?> read(String owner) async => values[owner];
  @override
  Future<DateTime> write(String owner, String value) async {
    await beforeWrite?.call();
    if (fail) throw StateError('Synthetic storage failure');
    values[owner] = value;
    return receipt ?? clock();
  }

  @override
  Future<void> clear(String owner) async {
    values.remove(owner);
  }

  @override
  Future<void> clearAll() async {
    values.clear();
  }
}

void main() {
  late DateTime now;
  late _Store store;
  late Ai1CaptureJournal journal;
  late Ai1Study study;
  DateTime day(int hour, [int minute = 0]) =>
      DateTime.utc(2026, 10, 17, hour, minute);
  setUp(() async {
    now = DateTime.utc(2026, 10, 16, 12);
    store = _Store(() => now);
    journal = Ai1CaptureJournal(store: store, clock: () => now);
    await journal.start('private-owner@example.invalid');
    study = Ai1Study(journal);
  });
  const owner = 'private-owner@example.invalid';
  Future<void> start({
    Ai1SleepSource source = Ai1SleepSource.manual,
    String end = '2026-10-20',
  }) => study.start(
    owner: owner,
    timezone: 'Etc/UTC',
    startDate: '2026-10-17',
    endDate: end,
    source: source,
    now: now,
  );
  Future<void> sleep({
    String id = 'private-sleep-id',
    double hours = 8,
    bool original = true,
  }) => journal.capture(
    owner: owner,
    observation: Ai1CaptureObservation.manualSleep(
      sourceId: id,
      startedAt: day(7).subtract(Duration(minutes: (hours * 60).round())),
      endedAt: day(7),
      durationHours: hours,
      isNap: false,
      originalLocal: original,
    ),
  );
  Future<void> response({
    String id = 'private-response-id',
    double? energy = 7,
    bool original = true,
  }) => journal.capture(
    owner: owner,
    observation: Ai1CaptureObservation.selfReport(
      checkIn: DailyCheckIn(
        id: id,
        timestamp: now,
        recordedAt: now,
        energy: energy,
        focus: 6,
        period: CheckInPeriod.evening,
        note: 'private note never exported',
        localDate: Ai1Study.dateKey(now),
        timezone: 'Etc/UTC',
        utcOffsetMinutes: 0,
        questionnaireVersion: CheckInMeasurement.currentVersion,
        questionnaireLanguage: 'en',
        source: 'selfReport',
        questionnaireSnapshot: CheckInMeasurement.snapshot(
          language: 'en',
          translate: (s) => s,
        ),
      ),
      sharedHeading: 'How do you feel right now?',
      originalLocal: original,
    ),
  );
  Future<void> tick() =>
      study.tick(owner: owner, now: now, deviceTimezone: 'Etc/UTC');
  Future<void> morning() async {
    await start();
    now = day(8);
    await sleep();
    now = day(10, 3);
    await tick();
  }

  dynamic report() => study.dataset(asOf: day(23), datasetVersion: 'test-v1');
  SignalReading sample(String id, int end, double hours) => SignalReading(
    id: id,
    type: SignalType.sleepCore,
    value: hours,
    timestamp: day(end),
    source: SignalSource.healthKit,
    quality: 1,
    groupId: 'private.health.producer',
  );

  test(
    'closed calendar retains unopened days; no future opportunities in dataset',
    () async {
      await start();
      final data = study.dataset(
        asOf: DateTime.utc(2026, 10, 19, 23),
        datasetVersion: 'a',
      );
      expect(data.rows.length, 3);
      expect(data.rows.every((r) => r.issuanceStatus == 'not_issued'), isTrue);
      expect(data.synthetic, isFalse);
      expect(data.trainingEligibleCount, 0);
    },
  );
  test(
    'manual path captures frozen inputs and a separate later Energy outcome',
    () async {
      await morning();
      now = day(19);
      await response();
      final data = report();
      expect(data.rows.single.hasPair, isTrue);
      expect(data.rows.single.feature.durationHours, 8);
      expect(data.rows.single.energy, 7);
      now = day(20);
      await sleep(hours: 5, original: false);
      expect(report().rows.single.feature.durationHours, 8);
    },
  );
  test('late sleep cannot become available at morning cutoff', () async {
    await start();
    now = day(10, 1);
    await sleep();
    now = day(10, 3);
    await tick();
    now = day(19);
    await response();
    expect(report().rows.single.sleepStatus, 'no_eligible_sleep');
    expect(report().rows.single.hasPair, isFalse);
    expect(report().rows.single.energy, 7);
  });
  test('missed window is never backfilled', () async {
    await start();
    now = day(8);
    await sleep();
    now = day(10, 15);
    await tick();
    expect(journal.entries.where((e) => e.data['kind'] == 'event'), isEmpty);
    expect(report().rows.single.issuanceStatus, 'not_issued');
  });
  test(
    'native completion at deadline excludes an attempted snapshot',
    () async {
      await start();
      now = day(8);
      await sleep();
      now = day(10, 14);
      store.receipt = day(10, 15);
      await tick();
      expect(report().rows.single.issuanceStatus, 'missed_cutoff');
    },
  );
  test('concurrent tick calls retain only first immutable event', () async {
    await start();
    now = day(8);
    await sleep();
    now = day(10, 3);
    await Future.wait([
      tick(),
      study.tick(owner: owner, now: day(10, 4), deviceTimezone: 'Etc/UTC'),
    ]);
    final events = journal.entries
        .where((e) => e.data['kind'] == 'event')
        .toList();
    expect(events.length, 1);
    expect(events.single.revision, 1);
  });
  test('plan receipt must precede first calendar day', () async {
    store.receipt = day(0);
    await expectLater(start(), throwsStateError);
    expect(study.active, isFalse);
  });
  test(
    'missing first Energy never falls back to a later answered report',
    () async {
      await morning();
      now = day(18, 30);
      await response(energy: null);
      now = day(20);
      await response(id: 'second', energy: 8);
      expect(report().rows.single.outcomeStatus, 'missing_energy');
    },
  );
  test('substantive correction excludes original target', () async {
    await morning();
    now = day(19);
    await response();
    now = day(20);
    await response(energy: 4, original: false);
    expect(report().rows.single.outcomeStatus, 'selected_response_revised');
  });
  test(
    'deleted first response cannot promote another answer or retain snapshot',
    () async {
      await morning();
      now = day(19);
      await response();
      now = day(20);
      await response(id: 'second');
      await journal.deleteSource(
        owner: owner,
        collection: 'checkIns',
        sourceId: 'private-response-id',
      );
      expect(report().rows.single.outcomeStatus, 'response_lineage_incomplete');
      expect(journal.entries.where((e) => e.data['kind'] == 'event'), isEmpty);
      expect(
        journal.entries.where((e) => e.sourceId == 'private-response-id'),
        isEmpty,
      );
    },
  );
  test(
    'sleep erasure purges frozen payload and blocks replacement feature',
    () async {
      await morning();
      await journal.deleteSource(
        owner: owner,
        collection: 'sleepLogs',
        sourceId: 'private-sleep-id',
      );
      now = day(10, 5);
      await sleep(id: 'replacement');
      await tick();
      expect(report().rows.single.sleepStatus, 'sleep_lineage_incomplete');
      expect(report().rows.single.feature, isNull);
    },
  );
  test(
    'restart restores frozen plan and snapshots without new issuance',
    () async {
      await morning();
      final restored = Ai1CaptureJournal(store: store, clock: () => now);
      await restored.load(owner);
      final service = Ai1Study(restored);
      await service.tick(
        owner: owner,
        now: day(10, 4),
        deviceTimezone: 'Etc/UTC',
      );
      expect(
        restored.entries.where((e) => e.data['kind'] == 'event').length,
        1,
      );
      expect(
        service
            .dataset(asOf: day(23), datasetVersion: 'b')
            .rows
            .single
            .issuanceStatus,
        'issued',
      );
    },
  );
  test('interrupted persistence fails closed for all dataset access', () async {
    await morning();
    store.fail = true;
    now = day(19);
    await response();
    expect(study.active, isFalse);
    expect(report, throwsStateError);
  });
  test(
    'dataset cannot inspect a pending write or select an older response',
    () async {
      await morning();
      now = day(19);
      await response();
      final entered = Completer<void>();
      final release = Completer<void>();
      store.beforeWrite = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      now = day(20);
      final pending = response(energy: 3, original: false);
      await entered.future;
      expect(report, throwsStateError);
      release.complete();
      await pending;
      expect(report().rows.single.outcomeStatus, 'selected_response_revised');
    },
  );
  test(
    'detected timezone change suppresses future snapshot and excludes old pair',
    () async {
      await morning();
      now = day(11);
      await study.tick(owner: owner, now: now, deviceTimezone: 'Europe/London');
      now = day(19);
      await response();
      expect(report().rows.single.outcomeStatus, 'timezone_changed');
    },
  );
  test(
    'Health captures pre-reconciliation intervals and keeps competing episodes',
    () async {
      await start(source: Ai1SleepSource.appleHealth);
      now = day(8);
      await study.captureHealth(
        owner: owner,
        now: now,
        samples: [sample('first', 3, 3), sample('second', 7, 1)],
      );
      now = day(10, 3);
      await tick();
      expect(report().rows.single.sleepStatus, 'ambiguous_sleep');
    },
  );
  test(
    'different Health queries at the same clock instant retain unique lineage',
    () async {
      await start(source: Ai1SleepSource.appleHealth);
      now = day(8);
      await study.captureHealth(
        owner: owner,
        now: now,
        samples: [sample('stage', 7, 8)],
      );
      await study.captureHealth(
        owner: owner,
        now: now,
        samples: [sample('stage', 7, 6)],
      );
      now = day(10, 3);
      await tick();
      final data = study.export(asOf: day(23), datasetVersion: 'same-clock');
      final queries = (data['healthQueries'] as List).cast<Map>();
      expect(queries.length, 2);
      expect(queries.map((q) => q['queryId']).toSet().length, 2);
      final feature =
          ((data['predictionEvents'] as List).single as Map)['feature'] as Map;
      expect(feature['parentQueryId'], queries.last['queryId']);
      expect(feature['main_sleep_duration_hours'], 6);
    },
  );
  test('Health and manual sources cannot silently fill each other', () async {
    await start(source: Ai1SleepSource.appleHealth);
    now = day(8);
    await sleep();
    now = day(10, 3);
    await tick();
    expect(report().rows.single.sleepStatus, 'sleep_lineage_incomplete');
  });
  test('Health late replacement leaves earlier frozen query intact', () async {
    await start(source: Ai1SleepSource.appleHealth);
    now = day(8);
    await study.captureHealth(
      owner: owner,
      now: now,
      samples: [sample('stage', 7, 8)],
    );
    now = day(10, 3);
    await tick();
    now = day(11);
    await study.captureHealth(
      owner: owner,
      now: now,
      samples: [sample('stage', 7, 6)],
    );
    expect(report().rows.single.feature.durationHours, 8);
    now = day(19);
    await response();
    final exported = study.export(asOf: day(23), datasetVersion: 'health');
    final feature =
        ((exported['predictionEvents'] as List).single as Map)['feature']
            as Map;
    expect(feature['parentQueryId'], isNotNull);
    expect(
      (exported['healthQueries'] as List).any(
        (q) => q['queryId'] == feature['parentQueryId'],
      ),
      isTrue,
    );
  });
  test(
    'Health capture bounds sample ends but retains later in-scope corrections',
    () async {
      await start(source: Ai1SleepSource.appleHealth, end: '2026-10-17');
      // Lead-in observations can be retained before the first study day.
      now = DateTime.utc(2026, 10, 16, 23);
      await study.captureHealth(
        owner: owner,
        now: now,
        samples: [sample('lead-in', -1, 1)],
      );
      expect(
        (journal.entries.last.data['samples'] as List).single['id'],
        'lead-in',
      );
      now = day(8);
      await study.captureHealth(
        owner: owner,
        now: now,
        samples: [sample('lead-in', -1, 1), sample('stage', 7, 8)],
      );
      now = day(10, 3);
      await tick();
      // Adjacent lead-in and morning stage intervals form one 9-hour episode.
      expect(report().rows.single.feature.durationHours, 9);

      // A next-day query can correct old evidence but not collect new sleep
      // beyond the final day's cutoff. The exact cutoff remains in scope.
      now = DateTime.utc(2026, 10, 18, 12);
      final queried = [
        sample('lead-in', -1, 1),
        sample('stage', 7, 6),
        sample('cutoff-end', 10, 1),
        sample('after-cutoff', 11, 1),
        sample('next-day', 31, 8),
      ];
      await study.captureHealth(owner: owner, now: now, samples: queried);
      final retained = (journal.entries.last.data['samples'] as List)
          .cast<Map>();
      expect(retained.map((row) => row['id']).toSet(), {
        'lead-in',
        'stage',
        'cutoff-end',
      });
      expect(retained.singleWhere((row) => row['id'] == 'stage')['value'], 6);
      expect(report().rows.single.feature.durationHours, 9);
      final revisionCount = journal.revisionCount;
      now = DateTime.utc(2026, 10, 19, 12);
      await study.captureHealth(
        owner: owner,
        now: now,
        samples: [...queried, sample('another-future-day', 55, 8)],
      );
      expect(journal.revisionCount, revisionCount);
    },
  );
  test(
    'observed Health removal erases old query copies and event features',
    () async {
      await start(source: Ai1SleepSource.appleHealth);
      now = day(8);
      await study.captureHealth(
        owner: owner,
        now: now,
        samples: [sample('stage', 7, 8)],
      );
      now = day(10, 3);
      await tick();
      now = day(11);
      await study.captureHealth(owner: owner, now: now, samples: []);
      expect(report().rows.single.feature, isNull);
      expect(
        jsonEncode(journal.entries.map((e) => e.toJson()).toList()),
        isNot(contains('stage')),
      );
    },
  );
  test(
    'private export removes account/source IDs, notes and numeric predictions',
    () async {
      await morning();
      now = day(19);
      await response();
      final data = study.export(asOf: day(23), datasetVersion: 'private');
      final encoded = jsonEncode(data);
      for (final value in [
        owner,
        'private-sleep-id',
        'private-response-id',
        'private note',
        journal.captureId!,
      ]) {
        expect(encoded, isNot(contains(value)));
      }
      final row = (data['predictionEvents'] as List).single;
      expect(row['prediction'], isNull);
      expect(row['trainingEligible'], isFalse);
      expect(row['analysisPair'], isTrue);
    },
  );
  test(
    'export freeze excludes later raw responses and query payloads',
    () async {
      await morning();
      now = DateTime.utc(2026, 10, 18, 19);
      await response();
      final data = study.export(asOf: day(23), datasetVersion: 'earlier');
      expect(
        (data['rawMeasurements'] as List).where(
          (r) => r['collection'] == 'checkIns',
        ),
        isEmpty,
      );
    },
  );
  test('analysis freeze cannot precede plan creation', () async {
    await start();
    expect(
      () => study.export(
        asOf: now.subtract(const Duration(seconds: 1)),
        datasetVersion: 'invalid-freeze',
      ),
      throwsArgumentError,
    );
  });
  test('opt-out erases plan, evidence, snapshots and availability', () async {
    await morning();
    await journal.stopAndClear(owner);
    expect(study.active, isFalse);
    expect(store.values[owner], isNull);
    expect(report, throwsStateError);
  });
  test('plan rejects skipped calendar days and oversized ranges', () async {
    expect(
      () => Ai1Study.dates('2026-02-30', '2026-03-01'),
      throwsFormatException,
    );
    expect(
      () => Ai1Study.dates('2026-01-01', '2028-01-01'),
      throwsFormatException,
    );
  });
}
