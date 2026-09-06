import 'dart:async';
import 'dart:convert';

import 'package:app/src/ml_prep_models.dart';
import 'package:app/src/ml_prep_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const allowed = PrepConsent(collection: true, trainingUse: true, version: 1);
const denied = PrepConsent(collection: false, trainingUse: false, version: 0);

class CountingSource implements PrepDataSource {
  @override
  String? currentUid = 'owner';
  PrepConsent consent = allowed;
  int metadataReads = 0;
  int queries = 0;
  final limits = <PrepCollection, int>{};
  final rows = <PrepCollection, List<Map<String, dynamic>>>{};
  Completer<void>? barrier;

  @override
  Future<PrepAccountMetadata> readAccount(String uid) async {
    expect(uid, currentUid);
    metadataReads++;
    if (barrier != null) await barrier!.future;
    return PrepAccountMetadata(consent: consent, schemaVersion: 7);
  }

  @override
  Future<List<Map<String, dynamic>>> readCollection(
    String uid,
    PrepCollection collection,
    PrepWindow window, {
    required int limit,
  }) async {
    expect(uid, currentUid);
    queries++;
    limits[collection] = limit;
    return rows[collection] ?? [];
  }
}

class RecoverableCache extends MemoryPrepCache {
  bool failClear = true;
  @override
  Future<void> clear() async {
    if (failClear) throw StateError('Temporary storage failure');
    await super.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final window = PrepWindow.endingOn(
    DateTime(2026, 7, 31),
    timezone: 'America/Los_Angeles',
  );

  test('30 local dates are half-open and DST aware, not 720 fixed hours', () {
    expect(window.start, DateTime.utc(2026, 7, 2, 7));
    expect(window.end, DateTime.utc(2026, 8, 1, 7));
    expect(window.contains(window.start), isTrue);
    expect(window.contains(window.end), isFalse);
    final dst = PrepWindow.endingOn(
      DateTime(2026, 3, 20),
      timezone: 'America/Los_Angeles',
    );
    expect(dst.end.difference(dst.start).inHours, 719);
    expect(dst.dayKey(dst.start), '2026-02-19');
    expect(dst.parseTime('2026-03-08T08:00:00'), DateTime.utc(2026, 3, 8, 15));
    expect(PrepWindow.fromJson(dst.toJson()).toJson(), dst.toJson());
    expect(
      () => PrepWindow.fromJson({
        ...dst.toJson(),
        'start': DateTime.utc(2026, 2, 18).toIso8601String(),
      }),
      throwsFormatException,
    );
    expect(
      PrepWindow.endingOn(DateTime(2026, 3, 20), timezone: 'UTC').timezone,
      'Etc/UTC',
    );
  });

  test(
    'first run has 3 capped queries and 1 shared metadata read; cache has zero',
    () async {
      final source = CountingSource();
      final cache = MemoryPrepCache();
      final service = MlPrepService(source: source, cache: cache);
      final first = await service.prepare(window: window);
      expect(source.queries, 3);
      expect(source.metadataReads, 1);
      expect(source.limits, {
        PrepCollection.signals: 1500,
        PrepCollection.checkIns: 100,
        PrepCollection.outcomes: 100,
      });
      final reopened = MlPrepService(source: source, cache: cache);
      final second = await reopened.prepare(window: window);
      expect(second.cacheHit, isTrue);
      expect(second.collectionQueries, 0);
      expect(second.metadataReads, 0);
      expect(second.returnedDocuments.values.every((n) => n == 0), isTrue);
      expect(source.queries, 3);
      expect(source.metadataReads, 1);
      expect(second.snapshot.fingerprint, first.snapshot.fingerprint);
      expect(second.report.toJson(), first.report.toJson());
      expect(jsonEncode(second.toJson()), isNot(contains('owner')));
      expect((second.toJson()['database'] as Map)['writes'], 0);
    },
  );

  test(
    'shared loaded metadata skips consent read and complete snapshot skips all reads',
    () async {
      final source = CountingSource();
      final service = MlPrepService(source: source, cache: MemoryPrepCache());
      final run = await service.prepare(
        window: window,
        knownAccount: const PrepAccountMetadata(
          consent: allowed,
          schemaVersion: 7,
        ),
      );
      expect(run.metadataReads, 0);
      expect(source.metadataReads, 0);
      await service.invalidate();
      final loaded = await service.prepare(
        window: window,
        loadedSnapshot: run.snapshot,
      );
      expect(loaded.collectionQueries, 0);
      expect(loaded.metadataReads, 0);
      expect(source.queries, 3);
    },
  );

  test(
    'training preparation rejects missing consent before collection queries',
    () async {
      final source = CountingSource()..consent = denied;
      final service = MlPrepService(source: source, cache: MemoryPrepCache());
      await expectLater(
        service.prepare(window: window, coverageOnly: false),
        throwsStateError,
      );
      expect(source.metadataReads, 1);
      expect(source.queries, 0);
      final coverage = await service.prepare(window: window);
      expect(coverage.report.examples, isEmpty);
      expect(coverage.report.energyReady, isFalse);
      await expectLater(
        service.prepare(window: window, coverageOnly: false),
        throwsStateError,
      );
      expect(source.queries, 3);
    },
  );

  test('cache known consent change cannot retain consented examples', () async {
    final source = CountingSource();
    final service = MlPrepService(source: source, cache: MemoryPrepCache());
    await service.prepare(window: window);
    source.consent = denied;
    final run = await service.prepare(window: window, knownConsent: denied);
    expect(run.cacheHit, isFalse);
    expect(run.snapshot.consent.allowed, isFalse);
    expect(run.report.examples, isEmpty);
    expect(source.queries, 6);
  });

  test(
    'edited value and deleted row invalidate without relying on counts/latest date',
    () async {
      final source = CountingSource();
      source.rows[PrepCollection.signals] = [
        {
          'id': 'manual-123',
          'timestamp': '2026-07-10T12:00:00Z',
          'type': 'caffeine',
          'value': 0,
          'unit': 'mg',
          'source': 'manual',
        },
      ];
      final service = MlPrepService(source: source, cache: MemoryPrepCache());
      final original = await service.prepare(window: window);
      source.rows[PrepCollection.signals]![0]['value'] = 25;
      final stillCached = await service.prepare(window: window);
      expect(stillCached.snapshot.fingerprint, original.snapshot.fingerprint);
      await service.invalidate();
      final edited = await service.prepare(window: window);
      expect(edited.snapshot.fingerprint, isNot(original.snapshot.fingerprint));
      source.rows[PrepCollection.signals] = [];
      await service.invalidate();
      final deleted = await service.prepare(window: window);
      expect(deleted.snapshot.fingerprint, isNot(edited.snapshot.fingerprint));
      expect(source.queries, 9);
    },
  );

  test('unknown remote changes require explicit foreground refresh', () async {
    final source = CountingSource();
    final service = MlPrepService(source: source, cache: MemoryPrepCache());
    await service.prepare(window: window);
    final fresh = await service.prepare(window: window, refresh: true);
    expect(fresh.cacheHit, isFalse);
    expect(source.queries, 6);
    expect(source.metadataReads, 2);
  });

  test('corrupt cache causes one bounded rebuild', () async {
    final source = CountingSource();
    final cache = MemoryPrepCache();
    final service = MlPrepService(source: source, cache: cache);
    await service.prepare(window: window);
    cache.values[cache.values.keys.single] = '{invalid';
    final run = await service.prepare(window: window);
    expect(run.cacheHit, isFalse);
    expect(source.queries, 6);
  });

  test(
    'hitting any cap reports truncated and never produces training examples',
    () async {
      final source = CountingSource();
      source.rows[PrepCollection.checkIns] = List.generate(
        100,
        (i) => {
          'id': 'checkin-$i',
          'timestamp': '2026-07-10T12:00:00Z',
          'energy': 7,
          'mood': 5,
          'stress': 5,
        },
      );
      final run = await MlPrepService(
        source: source,
        cache: MemoryPrepCache(),
      ).prepare(window: window);
      expect(run.snapshot.isTruncated, isTrue);
      expect(run.report.examples, isEmpty);
      expect(run.report.energyReady, isFalse);
      expect(run.report.cognitiveReady, isFalse);
      expect(source.queries, 3);
    },
  );

  test(
    'signed-out and switched accounts cannot obtain a cached result',
    () async {
      final source = CountingSource();
      final service = MlPrepService(source: source, cache: MemoryPrepCache());
      final original = await service.prepare(window: window);
      source.currentUid = null;
      await expectLater(service.prepare(window: window), throwsStateError);
      source.currentUid = 'different-owner';
      await expectLater(
        service.prepare(window: window, loadedSnapshot: original.snapshot),
        throwsStateError,
      );
      expect(source.queries, 3);
    },
  );

  test(
    'concurrent callers share one bounded fetch; edit cancels stale in-flight work',
    () async {
      final source = CountingSource()..barrier = Completer<void>();
      final cache = MemoryPrepCache();
      final service = MlPrepService(source: source, cache: cache);
      final first = service.prepare(window: window);
      final second = service.prepare(window: window);
      await Future<void>.delayed(Duration.zero);
      expect(source.metadataReads, 1);
      source.barrier!.complete();
      await Future.wait([first, second]);
      expect(source.queries, 3);
      await service.invalidate();
      source.barrier = Completer<void>();
      final stale = service.prepare(window: window);
      final assertion = expectLater(stale, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      await service.invalidate();
      source.barrier!.complete();
      await assertion;
      expect(cache.values, isEmpty);
      expect(source.queries, 3);
    },
  );

  test(
    'canonical fingerprints ignore map/row order and include nested edits',
    () {
      PrepSnapshot snapshot(List<Map<String, dynamic>> rows) => PrepSnapshot(
        uid: 'owner',
        window: window,
        consent: allowed,
        fetchedAt: DateTime.utc(2026, 8, 1),
        signals: rows,
        checkIns: [],
        outcomes: [],
        schemaVersion: 7,
      );
      final a = snapshot([
        {
          'id': 'b',
          'meta': {'value': 1},
        },
        {'id': 'a'},
      ]);
      final b = snapshot([
        {'id': 'a'},
        {
          'meta': {'value': 1},
          'id': 'b',
        },
      ]);
      final c = snapshot([
        {'id': 'a'},
        {
          'meta': {'value': 2},
          'id': 'b',
        },
      ]);
      expect(a.fingerprint, b.fingerprint);
      expect(a.fingerprint, isNot(c.fingerprint));
      expect(
        PrepSnapshot.fromJson(a.toJson(), uid: 'owner').fingerprint,
        a.fingerprint,
      );
      expect(
        () => (a.signals.first['meta'] as Map)['value'] = 9,
        throwsUnsupportedError,
      );
    },
  );

  test(
    'consent denial cannot coalesce with allowed in-flight training prep',
    () async {
      final source = CountingSource()..barrier = Completer<void>();
      final service = MlPrepService(source: source, cache: MemoryPrepCache());
      final first = service.prepare(window: window, coverageOnly: false);
      await expectLater(
        service.prepare(
          window: window,
          coverageOnly: false,
          knownConsent: denied,
        ),
        throwsStateError,
      );
      source.barrier!.complete();
      await first;
      expect(source.queries, 3);
    },
  );

  test(
    'loaded snapshot schema must match known current account schema',
    () async {
      final source = CountingSource();
      final service = MlPrepService(source: source, cache: MemoryPrepCache());
      final run = await service.prepare(window: window);
      await service.invalidate();
      await expectLater(
        service.prepare(
          window: window,
          loadedSnapshot: run.snapshot,
          knownAccount: const PrepAccountMetadata(
            consent: allowed,
            schemaVersion: 8,
          ),
        ),
        throwsStateError,
      );
      expect(source.queries, 3);
    },
  );

  test(
    'source budget violation is rejected without writing a prep cache',
    () async {
      final source = CountingSource();
      source.rows[PrepCollection.outcomes] = List.generate(
        101,
        (i) => {'id': '$i'},
      );
      final cache = MemoryPrepCache();
      await expectLater(
        MlPrepService(source: source, cache: cache).prepare(window: window),
        throwsStateError,
      );
      expect(cache.values, isEmpty);
    },
  );

  test(
    'failed cache invalidation can recover after storage recovers',
    () async {
      final source = CountingSource();
      final cache = RecoverableCache();
      final service = MlPrepService(source: source, cache: cache);
      await expectLater(service.invalidate(), throwsStateError);
      cache.failClear = false;
      await service.invalidate();
      await service.prepare(window: window);
      expect(source.queries, 3);
    },
  );

  test(
    'raw owner fields are removed without losing foreign-account rejection',
    () {
      final snapshot = PrepSnapshot(
        uid: 'owner',
        window: window,
        consent: allowed,
        fetchedAt: DateTime.utc(2026, 8, 1),
        signals: [
          {'id': 'one', 'uid': 'owner'},
          {'id': 'two', 'accountUid': 'foreign'},
        ],
        checkIns: [],
        outcomes: [],
        schemaVersion: 7,
      );
      final serialized = jsonEncode(snapshot.toJson());
      expect(serialized, isNot(contains('owner')));
      expect(serialized, isNot(contains('foreign')));
      expect(snapshot.signals[1]['_prepForeignAccount'], isTrue);
      expect(
        PrepSnapshot.fromJson(
          snapshot.toJson(),
          uid: 'owner',
        ).signals.singleWhere((row) => row['id'] == 'two')['_prepForeignAccount'],
        isTrue,
      );
    },
  );

  test('prep durable storage never clears application history', () async {
    SharedPreferences.setMockInitialValues({'tonyo_state_v1': 'preserved'});
    final store = SharedPreferencesPrepCache();
    await store.write('first', 'snapshot-one');
    await store.write('second', 'snapshot-two');
    expect(await store.read('first'), isNull);
    expect(await store.read('second'), 'snapshot-two');
    await store.clear();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('tonyo_state_v1'), 'preserved');
    expect(await store.read('second'), isNull);
  });
}
