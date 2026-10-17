import 'package:app/src/ai1_capture.dart';
import 'package:app/src/ai1_capture_store.dart';
import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/ai1_study.dart';
import 'package:app/src/ai1_study_schema.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements Ai1CaptureStore {
  _MemoryStore(this.clock);

  final DateTime Function() clock;
  final values = <String, String>{};
  DateTime? receipt;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> read(String owner) async => values[owner];

  @override
  Future<DateTime> write(String owner, String value) async {
    values[owner] = value;
    return receipt ?? clock();
  }

  @override
  Future<void> clear(String owner) async => values.remove(owner);

  @override
  Future<void> clearAll() async => values.clear();
}

void main() {
  const owner = 'synthetic-owner';
  late DateTime now;
  late _MemoryStore store;
  late Ai1CaptureJournal journal;
  late Ai1Study study;

  DateTime day(int hour) => DateTime.utc(2026, 10, 17, hour);

  SignalReading sample({
    double hours = 8,
    String? producer = 'test.producer',
  }) => SignalReading(
    id: 'synthetic-sample',
    type: SignalType.sleepCore,
    value: hours,
    timestamp: day(7),
    source: SignalSource.healthKit,
    quality: 1,
    groupId: producer,
  );

  Future<void> capture(List<SignalReading> samples) =>
      study.captureHealth(owner: owner, now: now, samples: samples);

  Future<void> tick({String timezone = 'Etc/UTC', DateTime? observedAt}) =>
      study.tick(
        owner: owner,
        now: observedAt ?? now,
        deviceTimezone: timezone,
      );

  Future<void> morning() async {
    now = day(8);
    await capture([sample()]);
    now = day(10).add(const Duration(minutes: 3));
    await tick();
  }

  Future<void> response() => journal.capture(
    owner: owner,
    observation: Ai1CaptureObservation.selfReport(
      checkIn: DailyCheckIn(
        id: 'synthetic-response',
        timestamp: now,
        recordedAt: now,
        energy: 7,
        period: CheckInPeriod.evening,
        localDate: Ai1Study.dateKey(now),
        timezone: 'Etc/UTC',
        utcOffsetMinutes: 0,
        questionnaireVersion: CheckInMeasurement.currentVersion,
        questionnaireLanguage: 'en',
        source: 'selfReport',
        questionnaireSnapshot: CheckInMeasurement.snapshot(
          language: 'en',
          translate: (text) => text,
        ),
      ),
      sharedHeading: 'How do you feel right now?',
      originalLocal: true,
    ),
  );

  setUp(() async {
    now = DateTime.utc(2026, 10, 16, 12);
    store = _MemoryStore(() => now);
    journal = Ai1CaptureJournal(store: store, clock: () => now);
    await journal.start(owner);
    study = Ai1Study(journal);
    await study.start(
      owner: owner,
      timezone: 'Etc/UTC',
      startDate: '2026-10-17',
      endDate: '2026-11-20',
      source: Ai1SleepSource.appleHealth,
      now: now,
    );
  });

  Map<String, Object?> snapshot(Map<String, Object?> sampleData) => {
    'kind': 'health',
    'observedAt': day(8).toIso8601String(),
    'samples': [sampleData],
  };

  Map<String, Object?> validSample() => {
    'id': 'synthetic-sample',
    'type': 'sleepCore',
    'value': 8,
    'timestamp': day(7).toIso8601String(),
    'sourceGroup': 'test.producer',
  };

  test('Health schema rejects absent, blank and oversized producer groups', () {
    final missing = validSample()..remove('sourceGroup');
    expect(
      () => validateAi1StudyData(snapshot(missing)),
      throwsFormatException,
    );
    for (final producer in ['', '   ', 'x' * 201]) {
      final invalid = validSample()..['sourceGroup'] = producer;
      expect(
        () => validateAi1StudyData(snapshot(invalid)),
        throwsFormatException,
      );
    }
  });

  test('Health schema rejects blank and oversized sample identities', () {
    for (final id in ['', '   ', 'x' * 201]) {
      final invalid = validSample()..['id'] = id;
      expect(
        () => validateAi1StudyData(snapshot(invalid)),
        throwsFormatException,
      );
    }
  });

  for (final producer in [null, '', '   ']) {
    test(
      'capture pauses instead of inventing producer ${producer ?? 'null'}',
      () async {
        now = day(8);
        await capture([sample(producer: producer)]);
        expect(journal.enabled, isFalse);
        expect(
          journal.entries.where((entry) => entry.data['kind'] == 'health'),
          isEmpty,
        );
      },
    );
  }

  test(
    'rolling expiry uses sample start and preserves older query and event',
    () async {
      await morning();
      final originalQuery = journal.entries.singleWhere(
        (entry) => entry.data['kind'] == 'health',
      );
      final originalEvent = journal.entries.singleWhere(
        (entry) => entry.data['kind'] == 'event',
      );
      // Sample starts Oct 16 at 23:00. Its end is still inside the recent
      // interval, but its start is one microsecond outside the 29-day boundary.
      now = DateTime.utc(2026, 11, 14, 23, 0, 0, 0, 1);
      await capture([]);
      expect(journal.tombstones, isEmpty);
      expect(
        journal.entries.any((entry) => entry.key == originalQuery.key),
        isTrue,
      );
      expect(
        journal.entries.any((entry) => entry.key == originalEvent.key),
        isTrue,
      );
      final report = study.dataset(
        asOf: day(23),
        datasetVersion: 'before-expiry',
      );
      expect(report.rows.single.feature?.durationHours, 8);
      expect(report.rows.single.issuanceStatus, 'issued');
    },
  );

  test(
    'absence at inclusive recent sample-start boundary purges derived copies',
    () async {
      await morning();
      final originalQuery = journal.entries.singleWhere(
        (entry) => entry.data['kind'] == 'health',
      );
      final originalEvent = journal.entries.singleWhere(
        (entry) => entry.data['kind'] == 'event',
      );
      now = DateTime.utc(2026, 11, 14, 23);
      await capture([]);
      expect(
        journal.tombstones,
        containsAll([originalQuery.key, originalEvent.key]),
      );
      expect(
        journal.entries.any((entry) => entry.key == originalQuery.key),
        isFalse,
      );
      expect(
        journal.entries.any((entry) => entry.key == originalEvent.key),
        isFalse,
      );
      final report = study.dataset(
        asOf: day(23),
        datasetVersion: 'after-absence',
      );
      expect(report.rows.single.feature, isNull);
      expect(report.rows.single.sleepStatus, 'sleep_lineage_incomplete');
    },
  );

  test(
    'export links Health feature to exact earlier query and episode',
    () async {
      await morning();
      now = day(11);
      await capture([sample(hours: 6)]);
      final exported = study.export(asOf: day(23), datasetVersion: 'lineage');
      final event = (exported['predictionEvents'] as List).single as Map;
      final feature = event['feature'] as Map;
      final queries = (exported['healthQueries'] as List).cast<Map>();
      final parent = queries.singleWhere(
        (query) => query['queryId'] == feature['parentQueryId'],
      );
      expect(queries, hasLength(2));
      expect(feature['episodeIndex'], 0);
      expect(feature['main_sleep_duration_hours'], 8);
      expect(parent['availableAt'], day(8).toIso8601String());
      expect(((parent['samples'] as List).single as Map)['valueHours'], 8);
      expect(queries.last['queryId'], isNot(feature['parentQueryId']));
    },
  );

  test(
    'future event receipt is omitted until the exact analysis freeze',
    () async {
      now = day(8);
      await capture([sample()]);
      now = day(10).add(const Duration(minutes: 3));
      final receipt = day(23).add(const Duration(microseconds: 1));
      store.receipt = receipt;
      await tick();
      final earlier = study.export(
        asOf: day(23),
        datasetVersion: 'before-event',
      );
      final earlierEvent = (earlier['predictionEvents'] as List).single as Map;
      expect(earlierEvent['snapshotStatus'], 'not_issued');
      expect(earlierEvent['issuedAt'], isNull);
      expect(earlierEvent['feature'], isNull);
      final atReceipt = study.dataset(
        asOf: receipt,
        datasetVersion: 'at-event',
      );
      expect(atReceipt.rows.single.issuanceStatus, 'missed_cutoff');
    },
  );

  test(
    'future timezone receipt cannot affect an earlier frozen outcome',
    () async {
      await morning();
      now = day(19);
      await response();
      final receipt = day(23).add(const Duration(microseconds: 1));
      store.receipt = receipt;
      // Model a delayed durable record of an earlier detected change.
      await tick(timezone: 'Europe/London', observedAt: day(11));
      final earlier = study.dataset(
        asOf: day(23),
        datasetVersion: 'before-zone',
      );
      expect(earlier.rows.single.outcomeStatus, 'matched');
      expect(earlier.rows.single.hasPair, isTrue);
      final atReceipt = study.dataset(asOf: receipt, datasetVersion: 'at-zone');
      expect(atReceipt.rows.single.outcomeStatus, 'timezone_changed');
      expect(atReceipt.rows.single.hasPair, isFalse);
    },
  );
}
