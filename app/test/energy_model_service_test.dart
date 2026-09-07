import 'dart:async';
import 'dart:convert';

import 'package:app/src/energy_model_repository.dart';
import 'package:app/src/energy_model_service.dart';
import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:app/src/ml_prep_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/benchmark_energy_model.dart' show benchmarkSnapshot;

void main() {
  late PrepRun ready;
  late PrepRun moreOutcomes;

  setUpAll(() {
    ready = cachedRun(benchmarkSnapshot());
    moreOutcomes = cachedRun(benchmarkSnapshot(days: 21));
    expect(ready.report.energyReady, isTrue);
    expect(moreOutcomes.report.energyReady, isTrue);
  });

  test(
    'constructor and local load never train or upload; explicit cached refresh uploads once',
    () async {
      final harness = _Harness();
      final service = harness.create();
      expect(service.model, isNull);
      expect(harness.store.reads, 0);
      expect(harness.store.writes, 0);
      await service.load();
      expect(harness.store.reads, 1);
      expect(harness.store.writes, 0);
      expect(harness.writer.writes, 0);

      await service.refresh(ready);
      expect(service.model, isNotNull, reason: service.status);
      expect(harness.store.reads, 1);
      expect(harness.store.writes, 2);
      expect(harness.writer.writes, 1);
      expect(harness.writer.values.keys, ['isolated-benchmark']);
      expect(
        harness.writer.values.values.single.keys.toSet(),
        EnergyModelMetadata.fields,
      );
      expect(service.busy, isFalse);
    },
  );

  test(
    'reopening restores weights locally without training or metadata writes',
    () async {
      final harness = _Harness();
      final first = harness.create();
      await first.refresh(ready);
      final fingerprint = first.model!.fingerprint;
      final writes = harness.store.writes;
      final restored = harness.create();
      await restored.load();
      expect(restored.model!.fingerprint, fingerprint);
      expect(harness.store.writes, writes);
      expect(harness.writer.writes, 1);
    },
  );

  test(
    'persisted daily throttle survives recreation and permits new outcomes at exactly 24h',
    () async {
      final harness = _Harness();
      await harness.create().refresh(ready);
      final writes = harness.store.writes;
      harness.at = harness.at.add(const Duration(hours: 23, minutes: 59));
      final restored = harness.create();
      await restored.refresh(moreOutcomes);
      expect(restored.status, contains('once per 24 hours'));
      expect(harness.store.writes, writes);
      expect(harness.writer.writes, 1);
      harness.at = harness.at.add(const Duration(minutes: 1));
      await restored.refresh(moreOutcomes);
      expect(restored.model!.labelCount, 21);
      expect(harness.writer.writes, 2);
      expect(harness.store.writes, writes + 2);
    },
  );

  test(
    'elapsed time alone cannot retrain without a new eligible Energy outcome',
    () async {
      final harness = _Harness();
      final service = harness.create();
      await service.refresh(ready);
      final writes = harness.store.writes;
      harness.at = harness.at.add(const Duration(days: 2));
      await service.refresh(ready);
      expect(service.status, contains('No new eligible Energy outcome'));
      expect(harness.store.writes, writes);
      expect(harness.writer.writes, 1);
      expect(service.model, isNotNull);
    },
  );

  test(
    'editing existing outcome values does not bypass new-outcome requirement',
    () async {
      final harness = _Harness();
      final service = harness.create();
      await service.refresh(ready);
      harness.at = harness.at.add(const Duration(days: 2));
      final edited = cachedRun(benchmarkSnapshot(residual: 7));
      await service.refresh(edited);
      expect(service.status, contains('No new eligible Energy outcome'));
      expect(harness.writer.writes, 1);
      expect(harness.store.writes, 2);
    },
  );

  test(
    'insufficient labels and holdout underperformance never upload a candidate',
    () async {
      for (final snapshot in [
        benchmarkSnapshot(days: 8),
        benchmarkSnapshot(residual: 8, holdoutResidual: -8),
      ]) {
        final harness = _Harness();
        final service = harness.create();
        await service.refresh(cachedRun(snapshot));
        expect(service.model, isNull);
        expect(harness.writer.writes, 0);
        expect(service.busy, isFalse);
      }
    },
  );

  test(
    'rejects missing auth, either consent gate, wrong snapshot owner, or absent writer',
    () async {
      final harness = _Harness();
      harness.uid = null;
      await expectLater(harness.create().refresh(ready), throwsStateError);
      harness.uid = 'different-owner';
      await expectLater(harness.create().refresh(ready), throwsStateError);
      harness.uid = 'isolated-benchmark';
      harness.consent = false;
      await expectLater(harness.create().refresh(ready), throwsStateError);
      harness.consent = true;
      await expectLater(
        harness.create().refresh(cachedRun(benchmarkSnapshot(consent: false))),
        throwsStateError,
      );
      await expectLater(
        harness.create(withWriter: false).refresh(ready),
        throwsStateError,
      );
      expect(harness.store.writes, 0);
      expect(harness.writer.writes, 0);
    },
  );

  test(
    'metadata failure retains local acceptance with no automatic retry',
    () async {
      final harness = _Harness();
      final writer = _FailingWriter();
      final service = harness.create(customWriter: writer);
      await service.refresh(ready);
      expect(service.model, isNotNull);
      expect(
        service.status,
        contains('accepted locally; metadata sync unavailable'),
      );
      expect(writer.attempts, 1);
      await service.refresh(ready);
      final restored = harness.create(customWriter: writer);
      await restored.load();
      await restored.refresh(moreOutcomes);
      expect(restored.model, isNotNull);
      expect(writer.attempts, 1);
      expect(harness.store.writes, 2);
    },
  );

  test(
    'corrupt or wrong-owner artifacts fall back without training or uploading',
    () async {
      final harness = _Harness();
      await harness.create().refresh(ready);
      final valid = harness.store.values['isolated-benchmark']!;
      final corruptArtifact = jsonDecode(valid) as Map<String, dynamic>;
      (corruptArtifact['model'] as Map)['weights'] = [9999];
      final wrongOwner = jsonDecode(valid) as Map<String, dynamic>;
      wrongOwner['ownerKey'] = 'different-owner';
      for (final raw in [
        'not-json',
        '{}',
        jsonEncode(corruptArtifact),
        jsonEncode(wrongOwner),
      ]) {
        harness.store.values['isolated-benchmark'] = raw;
        final restored = harness.create();
        await restored.load();
        expect(restored.model, isNull);
        expect(restored.status, contains('Saved model unavailable'));
        await restored.refresh(moreOutcomes);
        expect(restored.model, isNull);
        expect(restored.status, contains('once per 24 hours'));
        expect(harness.writer.writes, 1);
      }
    },
  );

  test(
    'runtime owner, consent, and clock checks instantly hide accepted weights',
    () async {
      final harness = _Harness();
      final service = harness.create();
      await service.refresh(ready);
      expect(service.model, isNotNull);
      harness.consent = false;
      expect(service.model, isNull);
      harness.consent = true;
      harness.uid = 'other';
      expect(service.model, isNull);
      harness.uid = 'isolated-benchmark';
      harness.at = harness.at.subtract(const Duration(seconds: 1));
      expect(service.model, isNull);
      service.unload();
      expect(service.model, isNull);
      expect(harness.writer.writes, 1);
    },
  );

  test(
    'corrupt ledger repairs once and cooldown does not restart on recreation',
    () async {
      final harness = _Harness();
      harness.store.values['isolated-benchmark'] = 'corrupt ledger';
      final first = harness.create();
      await first.load();
      expect(first.model, isNull);
      expect(harness.store.writes, 1);
      final repaired =
          jsonDecode(harness.store.values['isolated-benchmark']!) as Map;
      expect(repaired['model'], isNull);
      expect(repaired['lastAttemptAt'], harness.at.toIso8601String());
      harness.at = harness.at.add(const Duration(hours: 23));
      final restored = harness.create();
      await restored.refresh(ready);
      expect(restored.status, contains('once per 24 hours'));
      expect(harness.store.writes, 1);
      harness.at = harness.at.add(const Duration(hours: 1));
      await restored.refresh(ready);
      expect(restored.model, isNotNull, reason: restored.status);
      expect(harness.store.writes, 3);
      expect(harness.writer.writes, 1);
    },
  );

  test(
    'concurrent local loads coalesce without extra storage or cloud traffic',
    () async {
      final harness = _Harness();
      await harness.create().refresh(ready);
      final initialReads = harness.store.reads;
      final pause = harness.store.pauseNextRead();
      final service = harness.create();
      final first = service.load();
      await pause.started.future;
      final second = service.load();
      expect(harness.store.reads, initialReads + 1);
      pause.release.complete();
      await Future.wait([first, second]);
      expect(service.model, isNotNull);
      expect(harness.store.reads, initialReads + 1);
      expect(harness.store.writes, 2);
      expect(harness.writer.writes, 1);
    },
  );

  test(
    'discard removes weights while preserving the daily ledger across restart',
    () async {
      final harness = _Harness();
      final service = harness.create();
      await service.refresh(ready);
      final before =
          jsonDecode(harness.store.values['isolated-benchmark']!) as Map;
      harness.consent = false;
      await service.discard();
      expect(service.model, isNull);
      final after =
          jsonDecode(harness.store.values['isolated-benchmark']!) as Map;
      expect(after['model'], isNull);
      expect(after['lastAttemptAt'], before['lastAttemptAt']);
      expect(after['eligibleOutcomeKeys'], before['eligibleOutcomeKeys']);
      harness.consent = true;
      final restored = harness.create();
      await restored.refresh(moreOutcomes);
      expect(restored.model, isNull);
      expect(restored.status, contains('once per 24 hours'));
      expect(harness.writer.writes, 1);
    },
  );

  test(
    'discard before load preserves ledger without restoring weights under revoked consent',
    () async {
      final harness = _Harness();
      await harness.create().refresh(ready);
      final before =
          jsonDecode(harness.store.values['isolated-benchmark']!) as Map;
      harness.consent = false;
      final unloaded = harness.create();
      await unloaded.discard();
      final after =
          jsonDecode(harness.store.values['isolated-benchmark']!) as Map;
      expect(unloaded.model, isNull);
      expect(after['model'], isNull);
      expect(after['lastAttemptAt'], before['lastAttemptAt']);
      expect(after['eligibleOutcomeKeys'], before['eligibleOutcomeKeys']);
      expect(harness.writer.writes, 1);
    },
  );

  for (final transition in ['consent', 'owner', 'cancel']) {
    test(
      '$transition change during local load cannot expose accepted weights',
      () async {
        final harness = _Harness();
        await harness.create().refresh(ready);
        final pause = harness.store.pauseNextRead();
        final service = harness.create();
        final pending = service.load();
        await pause.started.future;
        switch (transition) {
          case 'consent':
            harness.consent = false;
          case 'owner':
            harness.uid = 'other-owner';
          case 'cancel':
            service.cancelPending();
        }
        pause.release.complete();
        await pending;
        expect(service.model, isNull);
        expect(harness.writer.writes, 1);
      },
    );

    test(
      '$transition change during attempt persistence cancels fitting and upload',
      () async {
        final harness = _Harness();
        final pause = harness.store.pauseWrite(1);
        final service = harness.create();
        final pending = service.refresh(ready);
        await pause.started.future;
        switch (transition) {
          case 'consent':
            harness.consent = false;
          case 'owner':
            harness.uid = 'other-owner';
          case 'cancel':
            service.cancelPending();
        }
        pause.release.complete();
        await pending;
        expect(service.model, isNull);
        expect(harness.writer.writes, 0);
        expect(harness.store.writes, 1);
        expect(
          (jsonDecode(harness.store.values['isolated-benchmark']!)
              as Map)['model'],
          isNull,
        );
        expect(service.busy, isFalse);
      },
    );
  }

  test(
    'duplicate explicit refresh while busy performs only one fit and upload',
    () async {
      final harness = _Harness();
      final pause = harness.store.pauseWrite(1);
      final service = harness.create();
      final pending = service.refresh(ready);
      await pause.started.future;
      expect(service.busy, isTrue);
      await service.refresh(moreOutcomes);
      expect(harness.store.writes, 1);
      pause.release.complete();
      await pending;
      expect(service.model!.labelCount, 20);
      expect(harness.store.writes, 2);
      expect(harness.writer.writes, 1);
    },
  );

  test(
    'cancellation during refresh initial load must not adopt a newer generation',
    () async {
      final harness = _Harness();
      final pause = harness.store.pauseNextRead();
      final service = harness.create();
      final pending = service.refresh(ready);
      await pause.started.future;
      service.cancelPending();
      pause.release.complete();
      // A cancelled refresh may report a stale-snapshot error or return quietly,
      // but it must never continue into fitting or metadata publication.
      try {
        await pending;
      } on StateError {
        /* Explicit stale request is safe. */
      }
      expect(service.model, isNull);
      expect(harness.store.writes, 0);
      expect(harness.writer.writes, 0);
      expect(service.busy, isFalse);
    },
  );

  test(
    'revocation during candidate persistence removes stale weights and avoids metadata',
    () async {
      final harness = _Harness();
      final pause = harness.store.pauseWrite(2);
      final service = harness.create();
      final pending = service.refresh(ready);
      await pause.started.future;
      harness.consent = false;
      pause.release.complete();
      await pending;
      expect(service.model, isNull);
      expect(harness.writer.writes, 0);
      expect(
        (jsonDecode(harness.store.values['isolated-benchmark']!)
            as Map)['model'],
        isNull,
      );
      expect(harness.store.writes, 3);
    },
  );
}

PrepRun cachedRun(PrepSnapshot snapshot) => PrepRun(
  snapshot: snapshot,
  report: MlPrepBuilder.build(snapshot),
  cacheHit: true,
  collectionQueries: 0,
  metadataReads: 0,
  returnedDocuments: const {},
);

class _Harness {
  final store = _CountingStore();
  final writer = MemoryEnergyModelMetadataWriter();
  String? uid = 'isolated-benchmark';
  bool consent = true;
  DateTime at = DateTime.utc(2026, 8, 3);

  EnergyModelService create({
    bool withWriter = true,
    EnergyModelMetadataWriter? customWriter,
  }) => EnergyModelService(
    store: store,
    writer: withWriter ? customWriter ?? writer : null,
    currentUid: () => uid,
    consentAllowed: () => consent,
    now: () => at,
  );
}

class _Pause {
  final started = Completer<void>();
  final release = Completer<void>();
}

class _CountingStore extends MemoryEnergyModelStore {
  int reads = 0;
  int writes = 0;
  _Pause? _readPause;
  final _writePauses = <int, _Pause>{};

  _Pause pauseNextRead() => _readPause = _Pause();
  _Pause pauseWrite(int writeNumber) => _writePauses[writeNumber] = _Pause();

  @override
  Future<String?> read(String uid) async {
    reads++;
    final pause = _readPause;
    _readPause = null;
    if (pause != null) {
      pause.started.complete();
      await pause.release.future;
    }
    return super.read(uid);
  }

  @override
  Future<void> write(String uid, String value) async {
    writes++;
    final pause = _writePauses.remove(writes);
    if (pause != null) {
      pause.started.complete();
      await pause.release.future;
    }
    await super.write(uid, value);
  }
}

class _FailingWriter implements EnergyModelMetadataWriter {
  int attempts = 0;
  @override
  Future<void> writeAccepted(String uid, Map<String, Object?> metadata) async {
    attempts++;
    throw StateError('Metadata is offline');
  }
}
