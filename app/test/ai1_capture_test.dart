import 'dart:async';
import 'dart:convert';

import 'package:app/src/ai1_capture.dart';
import 'package:app/src/ai1_capture_store.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

final _startedAt = DateTime.utc(2026, 10, 11, 8);

class _MemoryStore implements Ai1CaptureStore {
  final values = <String, String>{};
  final writes = <({String owner, String value})>[];
  bool available = true;
  int? failWrite;
  bool failClear = false;
  Future<void> Function(int count)? beforeWrite;
  DateTime Function(int count)? receipt;

  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<String?> read(String owner) async => values[owner];
  @override
  Future<DateTime> write(String owner, String value) async {
    writes.add((owner: owner, value: value));
    final count = writes.length;
    await beforeWrite?.call(count);
    if (count == failWrite) throw StateError('Synthetic write failure');
    values[owner] = value;
    return receipt?.call(count) ?? _startedAt.add(Duration(minutes: count));
  }

  @override
  Future<void> clear(String owner) async {
    if (failClear) throw StateError('Synthetic clear failure');
    values.remove(owner);
  }

  @override
  Future<void> clearAll() async {
    if (failClear) throw StateError('Synthetic clear failure');
    values.clear();
  }
}

Ai1CaptureObservation _sleep({
  String id = 'sleep-1',
  double hours = 8,
  bool original = true,
}) {
  final end = DateTime.utc(2026, 10, 11, 7);
  return Ai1CaptureObservation.manualSleep(
    sourceId: id,
    startedAt: end.subtract(Duration(minutes: (hours * 60).round())),
    endedAt: end,
    durationHours: hours,
    isNap: false,
    originalLocal: original,
  );
}

Ai1CaptureObservation _response({
  String id = 'response-1',
  double? energy = 7,
  String note = '',
  bool original = true,
  Map<String, dynamic>? definition,
}) => Ai1CaptureObservation.selfReport(
  checkIn: DailyCheckIn(
    id: id,
    timestamp: DateTime.utc(2026, 10, 11, 7),
    recordedAt: DateTime.utc(2026, 10, 11, 7, 1),
    energy: energy,
    focus: 6,
    period: CheckInPeriod.evening,
    note: note,
    localDate: '2026-10-11',
    timezone: 'Etc/UTC',
    utcOffsetMinutes: 0,
    questionnaireVersion: CheckInMeasurement.currentVersion,
    questionnaireLanguage: 'en',
    source: 'selfReport',
    questionnaireSnapshot:
        definition ??
        CheckInMeasurement.snapshot(language: 'en', translate: (text) => text),
  ),
  sharedHeading: 'How do you feel right now?',
  originalLocal: original,
);

Ai1CaptureJournal _journal(_MemoryStore store) =>
    Ai1CaptureJournal(store: store, clock: () => _startedAt);

void main() {
  test('capture is off by default and does not backfill on start', () async {
    final store = _MemoryStore();
    final journal = _journal(store);
    await journal.load('owner');
    expect(journal.available, isTrue);
    expect(journal.enabled, isFalse);
    await journal.capture(owner: 'owner', observation: _sleep());
    expect(store.writes, isEmpty);
    await journal.start('owner');
    expect(journal.enabled, isTrue);
    expect(journal.entries, isEmpty);
    final encoded = jsonDecode(store.values['owner']!);
    expect(encoded['trainingEligible'], isFalse);
    expect(encoded['entries'], isEmpty);
  });

  test('unavailable storage cannot start capture', () async {
    final store = _MemoryStore()..available = false;
    final journal = _journal(store);
    await journal.load('owner');
    await expectLater(journal.start('owner'), throwsStateError);
    expect(journal.enabled, isFalse);
    expect(store.writes, isEmpty);
  });

  test('restart retains opt-in and immutable acknowledged revisions', () async {
    final store = _MemoryStore();
    final journal = _journal(store);
    await journal.start('owner');
    await journal.capture(owner: 'owner', observation: _sleep());
    await journal.capture(
      owner: 'owner',
      observation: _sleep(hours: 7, original: false),
    );
    final restarted = _journal(store);
    await restarted.load('owner');
    expect(restarted.enabled, isTrue);
    expect(restarted.entries.map((entry) => entry.revision), [1, 2]);
    expect(restarted.entries.map((entry) => entry.data['durationHours']), [
      8,
      7,
    ]);
    expect(
      restarted.entries.every(
        (entry) => entry.originalLocal && entry.lineageComplete,
      ),
      isTrue,
    );
    expect(() => restarted.entries.clear(), throwsUnsupportedError);
    expect(
      () => restarted.entries.first.data['durationHours'] = 1,
      throwsUnsupportedError,
    );
  });

  test('first captured edit never becomes a proven original', () async {
    final store = _MemoryStore();
    final journal = _journal(store);
    await journal.start('owner');
    await journal.capture(owner: 'owner', observation: _sleep(original: false));
    await journal.capture(owner: 'owner', observation: _sleep(hours: 7));
    expect(
      journal.entries.every(
        (entry) => !entry.originalLocal && !entry.lineageComplete,
      ),
      isTrue,
    );
  });

  test('identical retries and note-only saves add no revision', () async {
    final store = _MemoryStore();
    final journal = _journal(store);
    await journal.start('owner');
    await journal.capture(
      owner: 'owner',
      observation: _response(note: 'private note'),
    );
    final writes = store.writes.length;
    await journal.capture(
      owner: 'owner',
      observation: _response(note: 'different private note', original: false),
    );
    expect(journal.entries, hasLength(1));
    expect(store.writes.length, writes);
    expect(store.values['owner'], isNot(contains('private note')));
    expect(journal.entries.single.data, isNot(contains('recordedAt')));
  });

  test(
    'snapshots freeze definition deeply and preserve missing Energy',
    () async {
      final store = _MemoryStore();
      final journal = _journal(store);
      final definition = CheckInMeasurement.snapshot(
        language: 'en',
        translate: (text) => text,
      );
      final observation = _response(definition: definition, energy: null);
      (definition['items'] as List).first['label'] = 'Changed later';
      await journal.start('owner');
      await journal.capture(owner: 'owner', observation: observation);
      final captured = journal.entries.single.data;
      expect((captured['ratings'] as Map)['energy'], isNull);
      expect(
        ((captured['definition'] as Map)['items'] as List).first['label'],
        'Energy',
      );
      expect(
        () => ((captured['definition'] as Map)['items'] as List).clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'availability is the native payload receipt rather than start or second save',
    () async {
      final store = _MemoryStore()
        ..receipt = (count) => _startedAt.add(Duration(seconds: count * 10));
      final journal = _journal(store);
      await journal.start('owner');
      await journal.capture(owner: 'owner', observation: _sleep());
      expect(
        journal.entries.single.acknowledgedAt,
        _startedAt.add(const Duration(seconds: 20)),
      );
      expect(store.writes, hasLength(3));
      final pending = jsonDecode(store.writes[1].value)['entries'].single;
      expect(pending['acknowledgedAt'], isNull);
      expect(pending['lineageComplete'], isFalse);
    },
  );

  test('failed payload save never creates an acknowledged revision', () async {
    final store = _MemoryStore()..failWrite = 2;
    final journal = _journal(store);
    await journal.start('owner');
    await journal.capture(owner: 'owner', observation: _sleep());
    expect(journal.enabled, isFalse);
    expect(journal.revisionCount, 0);
    expect(journal.error, isNotNull);
    await expectLater(journal.start('owner'), throwsStateError);
  });

  test(
    'interrupted receipt remains pending and fails closed after restart',
    () async {
      final store = _MemoryStore()..failWrite = 3;
      final journal = _journal(store);
      await journal.start('owner');
      await journal.capture(owner: 'owner', observation: _sleep());
      expect(journal.enabled, isFalse);
      expect(journal.revisionCount, 0);
      final restarted = _journal(store);
      await restarted.load('owner');
      expect(restarted.enabled, isFalse);
      expect(restarted.entries.single.acknowledgedAt, isNull);
      expect(restarted.entries.single.lineageComplete, isFalse);
      await expectLater(restarted.start('owner'), throwsStateError);
      await restarted.stopAndClear('owner');
      await restarted.start('owner');
      expect(restarted.enabled, isTrue);
      expect(restarted.entries, isEmpty);
    },
  );

  test(
    'backward native clock pauses capture with no invented receipt',
    () async {
      final store = _MemoryStore()
        ..receipt = (_) => _startedAt.subtract(const Duration(seconds: 1));
      final journal = _journal(store);
      await journal.start('owner');
      await journal.capture(owner: 'owner', observation: _sleep());
      expect(journal.enabled, isFalse);
      expect(journal.revisionCount, 0);
    },
  );

  test('clock rollback across different sources also pauses capture', () async {
    final store = _MemoryStore()
      ..receipt = (count) =>
          _startedAt.add(Duration(minutes: count == 4 ? 15 : count * 10));
    final journal = _journal(store);
    await journal.start('owner');
    await journal.capture(
      owner: 'owner',
      observation: _sleep(id: 'first'),
    );
    expect(
      journal.entries.single.acknowledgedAt,
      _startedAt.add(const Duration(minutes: 20)),
    );
    await journal.capture(
      owner: 'owner',
      observation: _sleep(id: 'second'),
    );
    expect(journal.enabled, isFalse);
    expect(journal.revisionCount, 1);
    expect(journal.entries.last.acknowledgedAt, isNull);
    expect(journal.entries.last.lineageComplete, isFalse);
    final restarted = _journal(store);
    await restarted.load('owner');
    expect(restarted.enabled, isFalse);
    expect(restarted.revisionCount, 1);
  });

  test(
    'source deletion erases payloads and prevents reappearance after restart',
    () async {
      final store = _MemoryStore();
      final journal = _journal(store);
      await journal.start('owner');
      await journal.capture(owner: 'owner', observation: _sleep());
      await journal.capture(
        owner: 'owner',
        observation: _sleep(id: 'kept'),
      );
      await journal.deleteSource(
        owner: 'owner',
        collection: 'sleepLogs',
        sourceId: 'sleep-1',
      );
      expect(journal.entries.single.sourceId, 'kept');
      final restarted = _journal(store);
      await restarted.load('owner');
      final writes = store.writes.length;
      await restarted.capture(owner: 'owner', observation: _sleep(hours: 6));
      expect(restarted.entries.single.sourceId, 'kept');
      expect(store.writes.length, writes);
      expect(jsonDecode(store.values['owner']!)['tombstones'], [
        '["sleepLogs","sleep-1"]',
      ]);
    },
  );

  test('deletion storage failure cannot report success', () async {
    final store = _MemoryStore();
    final journal = _journal(store);
    await journal.start('owner');
    await journal.capture(owner: 'owner', observation: _sleep());
    store.failWrite = store.writes.length + 1;
    await expectLater(
      journal.deleteSource(
        owner: 'owner',
        collection: 'sleepLogs',
        sourceId: 'sleep-1',
      ),
      throwsStateError,
    );
    expect(journal.enabled, isFalse);
    expect(journal.error, contains('cleared'));
  });

  test('source identity is collection scoped', () async {
    final store = _MemoryStore();
    final journal = _journal(store);
    await journal.start('owner');
    await journal.capture(
      owner: 'owner',
      observation: _sleep(id: 'shared'),
    );
    await journal.capture(
      owner: 'owner',
      observation: _response(id: 'shared'),
    );
    await journal.deleteSource(
      owner: 'owner',
      collection: 'sleepLogs',
      sourceId: 'shared',
    );
    expect(journal.entries.single.collection, 'checkIns');
  });

  test(
    'owner switching hides old rows and owner-specific clear is isolated',
    () async {
      final store = _MemoryStore();
      final journal = _journal(store);
      await journal.start('A');
      await journal.capture(owner: 'A', observation: _sleep());
      await journal.load('B');
      expect(journal.enabled, isFalse);
      expect(journal.entries, isEmpty);
      await journal.capture(owner: 'A', observation: _sleep(hours: 6));
      await journal.start('B');
      await journal.capture(
        owner: 'B',
        observation: _sleep(id: 'B-sleep'),
      );
      await journal.stopAndClear('B');
      expect(store.values.keys, ['A']);
      await journal.load('A');
      expect(journal.entries.single.sourceId, 'sleep-1');
      await journal.clearAll();
      expect(store.values, isEmpty);
      expect(journal.owner, isNull);
    },
  );

  test('queued capture cannot recreate data after clearing', () async {
    final store = _MemoryStore();
    final journal = _journal(store);
    await journal.start('owner');
    final entered = Completer<void>();
    final release = Completer<void>();
    store.beforeWrite = (count) async {
      if (count == 2) {
        entered.complete();
        await release.future;
      }
    };
    final capture = journal.capture(owner: 'owner', observation: _sleep());
    await entered.future;
    final clearing = journal.stopAndClear('owner');
    expect(journal.enabled, isFalse);
    release.complete();
    await Future.wait([capture, clearing]);
    expect(store.values, isEmpty);
    expect(journal.entries, isEmpty);
    expect(journal.busy, isFalse);
  });

  test('queued deletion removes the source currently being captured', () async {
    final store = _MemoryStore();
    final journal = _journal(store);
    await journal.start('owner');
    final entered = Completer<void>();
    final release = Completer<void>();
    store.beforeWrite = (count) async {
      if (count == 2) {
        entered.complete();
        await release.future;
      }
    };
    final capture = journal.capture(owner: 'owner', observation: _sleep());
    await entered.future;
    final deletion = journal.deleteSource(
      owner: 'owner',
      collection: 'sleepLogs',
      sourceId: 'sleep-1',
    );
    release.complete();
    await Future.wait([capture, deletion]);
    expect(journal.entries, isEmpty);
    await journal.capture(owner: 'owner', observation: _sleep());
    expect(journal.entries, isEmpty);
  });

  test(
    'remote changes purge captured history without importing unseen rows',
    () async {
      final store = _MemoryStore();
      final journal = _journal(store);
      await journal.start('owner');
      final first = _sleep();
      final kept = _sleep(id: 'kept');
      await journal.capture(owner: 'owner', observation: first);
      await journal.capture(owner: 'owner', observation: kept);
      await journal.reconcile(
        owner: 'owner',
        currentFingerprints: {
          first.key: _sleep(hours: 6).fingerprint,
          kept.key: kept.fingerprint,
          'unseen': 'unseen',
        },
      );
      expect(journal.entries.single.sourceId, 'kept');
    },
  );

  test(
    'queued reconciliation includes a capture still being persisted',
    () async {
      final store = _MemoryStore();
      final journal = _journal(store);
      await journal.start('owner');
      final entered = Completer<void>();
      final release = Completer<void>();
      store.beforeWrite = (count) async {
        if (count == 2) {
          entered.complete();
          await release.future;
        }
      };
      final capture = journal.capture(owner: 'owner', observation: _sleep());
      await entered.future;
      final reconcile = journal.reconcile(
        owner: 'owner',
        currentFingerprints: const {},
      );
      release.complete();
      await Future.wait([capture, reconcile]);
      expect(journal.entries, isEmpty);
      await journal.capture(owner: 'owner', observation: _sleep());
      expect(journal.entries, isEmpty);
    },
  );

  test(
    'deleting a source clears an unreadable journal conservatively',
    () async {
      final store = _MemoryStore()..values['owner'] = '{damaged';
      final journal = _journal(store);
      await journal.load('owner');
      expect(journal.error, isNotNull);
      await journal.deleteSource(
        owner: 'owner',
        collection: 'sleepLogs',
        sourceId: 'sleep-1',
      );
      expect(store.values, isEmpty);
      expect(journal.entries, isEmpty);
      expect(journal.enabled, isFalse);
    },
  );

  test(
    'malformed journals fail closed instead of accepting changed provenance',
    () async {
      final sourceStore = _MemoryStore();
      final source = _journal(sourceStore);
      await source.start('owner');
      await source.capture(owner: 'owner', observation: _sleep());
      final valid = sourceStore.values['owner']!;
      final corruptions = <void Function(Map<String, dynamic>)>[
        (json) => json['schemaVersion'] = 2,
        (json) => json['owner'] = 'other-owner',
        (json) => json['trainingEligible'] = true,
        (json) => json['notes'] = 'unexpected private text',
        (json) => json['entries'][0]['revision'] = 2,
        (json) => json['entries'][0]['originalLocal'] = false,
        (json) => json['entries'][0]['acknowledgedAt'] = null,
        (json) =>
            json['entries'][0]['data']['notes'] = 'unexpected private text',
        (json) => json['entries'][0]['data']['durationHours'] = 24,
        (json) => json['tombstones'] = ['["sleepLogs","sleep-1"]'],
      ];
      for (final corrupt in corruptions) {
        final json = jsonDecode(valid) as Map<String, dynamic>;
        corrupt(json);
        final store = _MemoryStore()..values['owner'] = jsonEncode(json);
        final restarted = _journal(store);
        await restarted.load('owner');
        expect(restarted.enabled, isFalse);
        expect(restarted.entries, isEmpty);
        expect(restarted.error, isNotNull);
        await expectLater(restarted.start('owner'), throwsStateError);
      }
    },
  );
}
