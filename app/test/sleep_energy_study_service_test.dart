import 'dart:async';
import 'dart:convert';

import 'package:app/src/ai1_capture_store.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/models.dart';
import 'package:app/src/sleep_energy_experiment.dart';
import 'package:app/src/sleep_energy_study_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Models the native store's ordering: a blocked write has not completed, and
/// its returned receipt is measured only after the replacement has completed.
class _ReceiptStore implements Ai1CaptureStore {
  _ReceiptStore(this.clock);

  final DateTime Function() clock;
  final values = <String, String>{};
  final failWrites = <int>{};
  final failAfterReplacement = <int>{};
  final operations = <String>[];
  bool available = true;
  bool failNextClear = false;
  int writeCount = 0;
  int? blockedWrite;
  Completer<void>? enteredWrite;
  Completer<void>? releaseWrite;

  void blockNextWrite() {
    blockWrite(writeCount + 1);
  }

  void blockWrite(int number) {
    blockedWrite = number;
    enteredWrite = Completer<void>();
    releaseWrite = Completer<void>();
  }

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<String?> read(String owner) async => values[owner];

  @override
  Future<DateTime> write(String owner, String value) async {
    final number = ++writeCount;
    operations.add('write-start:$owner:$number');
    if (number == blockedWrite) {
      enteredWrite!.complete();
      await releaseWrite!.future;
    }
    if (failWrites.contains(number)) {
      throw StateError('Native replacement failed.');
    }
    values[owner] = value;
    operations.add('write-finish:$owner:$number');
    if (failAfterReplacement.contains(number)) {
      throw StateError('Directory flush failed after replacing the file.');
    }
    return clock().toUtc();
  }

  @override
  Future<void> clear(String owner) async {
    operations.add('clear:$owner');
    if (failNextClear) {
      failNextClear = false;
      throw StateError('Native erasure failed.');
    }
    values.remove(owner);
  }

  @override
  Future<void> clearAll() async {
    throw StateError('An owner-scoped service must not erase every journal.');
  }
}

Map<String, dynamic> _definition() => CheckInMeasurement.snapshot(
  language: 'en',
  translate: AppLocalizations('en').text,
);

DailyCheckIn _report(int day, {double energy = 7, String? id}) {
  final observed = DateTime.utc(2026, 11, day, 20);
  return DailyCheckIn(
    id: id ?? 'response-$day',
    timestamp: observed,
    recordedAt: observed.add(const Duration(seconds: 1)),
    period: CheckInPeriod.evening,
    energy: energy,
    localDate: '2026-11-${day.toString().padLeft(2, '0')}',
    timezone: 'Etc/UTC',
    utcOffsetMinutes: 0,
    questionnaireVersion: CheckInMeasurement.currentVersion,
    questionnaireLanguage: 'en',
    source: 'selfReport',
    questionnaireSnapshot: _definition(),
  );
}

SignalReading _sleep(int day) => SignalReading(
  id: 'sleep-$day',
  groupId: 'sleep-group-$day',
  type: SignalType.sleep,
  value: [6.0, 7.0, 8.0, 7.5][day - 1],
  timestamp: DateTime.utc(2026, 11, day, 8),
  recordedAt: DateTime.utc(2026, 11, day, 8),
  quality: .8,
);

void main() {
  late DateTime now;
  late _ReceiptStore store;
  late List<DailyCheckIn> reports;
  late List<SignalReading> sleeps;
  late SleepEnergyReadiness readiness;
  late SleepEnergyRun run;
  late SleepEnergyPrediction draft;

  SleepEnergyStudyService service() =>
      SleepEnergyStudyService(store: store, clock: () => now);

  Future<SleepEnergyStudyService> enrolled() async {
    final study = service();
    await study.load('local');
    await study.saveRun(run);
    await study.setLogging(true);
    return study;
  }

  ({
    SleepEnergyRun run,
    SleepEnergyPrediction draft,
    List<SignalReading> sleeps,
  })
  healthExample() {
    final healthSleeps = [
      for (final sleep in sleeps)
        SignalReading.fromJson({...sleep.toJson(), 'source': 'healthKit'}),
    ];
    final healthReadiness = SleepEnergyExperiment.prepare(
      checkIns: reports,
      signals: healthSleeps,
      now: now,
    );
    final healthRun = SleepEnergyExperiment.train(
      healthReadiness,
      trainedAt: now,
    );
    final healthDraft = SleepEnergyExperiment.draftPrediction(
      run: healthRun,
      readiness: healthReadiness,
      checkIns: reports,
      signals: healthSleeps,
      now: now,
      timezone: 'Etc/UTC',
    ).draft!;
    return (run: healthRun, draft: healthDraft, sleeps: healthSleeps);
  }

  setUp(() {
    now = DateTime.utc(2026, 11, 4, 12);
    store = _ReceiptStore(() => now);
    reports = [
      _report(1, energy: 4),
      _report(2, energy: 6),
      _report(3, energy: 7),
    ];
    sleeps = [for (var day = 1; day <= 4; day++) _sleep(day)];
    readiness = SleepEnergyExperiment.prepare(
      checkIns: reports,
      signals: sleeps,
      now: now,
    );
    expect(readiness.pairCount, 3);
    expect(readiness.canTrain, isTrue);
    run = SleepEnergyExperiment.train(readiness, trainedAt: now);
    final issued = SleepEnergyExperiment.draftPrediction(
      run: run,
      readiness: readiness,
      checkIns: reports,
      signals: sleeps,
      now: now,
      timezone: 'Etc/UTC',
    );
    expect(issued.reason, isNull);
    draft = issued.draft!;
  });

  test('loading is read only and neither trains nor enrolls', () async {
    final study = service();
    await study.load('local');
    expect(study.available, isTrue);
    expect(study.loaded, isTrue);
    expect(study.loggingEnabled, isFalse);
    expect(study.run, isNull);
    expect(study.predictions, isEmpty);
    expect(store.writeCount, 0);

    await study.reconcile(
      readiness: readiness,
      checkIns: reports,
      signals: sleeps,
    );
    await study.record(draft, stillEligible: () => true);
    expect(study.run, isNull);
    expect(study.predictions, isEmpty);
    expect(store.writeCount, 0);
  });

  test('unsupported storage fails closed without writing', () async {
    store.available = false;
    final study = service();
    await study.load('local');
    expect(study.loaded, isTrue);
    expect(study.available, isFalse);
    expect(study.loggingEnabled, isFalse);
    expect(study.status, contains('iPhone'));
    await expectLater(study.saveRun(run), throwsStateError);
    await expectLater(study.setLogging(true), throwsStateError);
    expect(store.values, isEmpty);
  });

  test(
    'explicit fits and logging survive restart only for their owner',
    () async {
      final study = await enrolled();
      await study.record(draft, stillEligible: () => true);
      final stored = study.predictions.single.toJson();
      final restarted = service();
      await restarted.load('cloud:another-account');
      expect(restarted.loggingEnabled, isFalse);
      expect(restarted.run, isNull);
      expect(restarted.predictions, isEmpty);

      await restarted.load('local');
      expect(restarted.loggingEnabled, isTrue);
      expect(restarted.run!.toJson(), run.toJson());
      expect(restarted.predictions.single.toJson(), stored);
      expect(store.values.keys, ['sleep-energy:local']);

      await restarted.clear('cloud:another-account');
      expect(restarted.owner, 'local');
      expect(restarted.predictions.single.toJson(), stored);
      expect(store.values, contains('sleep-energy:local'));
    },
  );

  test(
    'a mismatched journal owner cannot expose a different account',
    () async {
      final study = await enrolled();
      await study.record(draft, stillEligible: () => true);
      store.values['sleep-energy:cloud:other'] =
          store.values['sleep-energy:local']!;
      final other = service();
      await other.load('cloud:other');
      expect(other.loaded, isFalse);
      expect(other.loggingEnabled, isFalse);
      expect(other.run, isNull);
      expect(other.predictions, isEmpty);
      expect(other.status, contains('Could not read'));
    },
  );

  test(
    'receipt is the native completion time after a blocked payload write',
    () async {
      final study = await enrolled();
      store.blockNextWrite();
      final recording = study.record(draft, stillEligible: () => true);
      await store.enteredWrite!.future;
      expect(study.predictions.single.receiptAt, isNull);
      now = now.add(const Duration(minutes: 1));
      store.releaseWrite!.complete();
      await recording;
      expect(study.predictions.single.createdAt, draft.createdAt);
      expect(study.predictions.single.receiptAt, now);
      expect(study.predictions.single.receiptAt, isNot(draft.createdAt));
    },
  );

  test(
    'failed receipt snapshot remains unscored and reserved after restart',
    () async {
      final study = await enrolled();
      store.failWrites.add(store.writeCount + 2);
      await expectLater(
        study.record(draft, stillEligible: () => true),
        throwsStateError,
      );
      expect(study.predictions.single.receiptAt, isNull);
      final restarted = service();
      await restarted.load('local');
      expect(restarted.predictions.single.receiptAt, isNull);
      final evaluation = SleepEnergyExperiment.evaluatePrediction(
        restarted.predictions.single,
        checkIns: [...reports, _report(4)],
        signals: sleeps,
        now: DateTime.utc(2026, 11, 4, 21),
      );
      expect(evaluation.status, 'pending_receipt');
      final beforeRetry = store.writeCount;
      await restarted.record(draft, stillEligible: () => true);
      expect(store.writeCount, beforeRetry);
      expect(restarted.predictions, hasLength(1));
    },
  );

  test(
    'replacement followed by flush failure cannot lose the reserved day',
    () async {
      final study = await enrolled();
      store.failAfterReplacement.add(store.writeCount + 1);
      await expectLater(
        study.record(draft, stillEligible: () => true),
        throwsStateError,
      );
      expect(study.predictions.single.receiptAt, isNull);
      // This later settings snapshot used to erase the pending entry that native
      // storage had replaced before reporting its directory-flush failure.
      await study.setLogging(false);
      final restarted = service();
      await restarted.load('local');
      expect(restarted.predictions.single.receiptAt, isNull);
      await restarted.setLogging(true);
      final writes = store.writeCount;
      await restarted.record(draft, stillEligible: () => true);
      expect(store.writeCount, writes);
      expect(restarted.predictions, hasLength(1));
    },
  );

  test(
    'opening a form after issuance does not require a rollback write',
    () async {
      final study = await enrolled();
      var eligible = true;
      final priorWrites = store.writeCount;
      store.blockWrite(priorWrites + 2);
      // A rollback would fail. It is unnecessary because the first native
      // receipt already proved issuance before the form was opened.
      store.failWrites.add(priorWrites + 3);
      final recording = study.record(draft, stillEligible: () => eligible);
      await store.enteredWrite!.future;
      eligible = false;
      now = now.add(const Duration(minutes: 1));
      store.releaseWrite!.complete();
      await recording;
      expect(store.writeCount, priorWrites + 2);
      expect(study.predictions.single.receiptAt, draft.createdAt);
      final restarted = service();
      await restarted.load('local');
      expect(restarted.predictions.single.receiptAt, draft.createdAt);
    },
  );

  test(
    'pausing during confirmation retains an already-issued prediction',
    () async {
      final study = await enrolled();
      store.blockWrite(store.writeCount + 2);
      final recording = study.record(draft, stillEligible: () => true);
      await store.enteredWrite!.future;
      final disabling = study.setLogging(false);
      store.releaseWrite!.complete();
      await Future.wait([recording, disabling]);
      expect(study.loggingEnabled, isFalse);
      expect(study.predictions.single.receiptAt, isNotNull);
      final restarted = service();
      await restarted.load('local');
      expect(restarted.loggingEnabled, isFalse);
      expect(restarted.predictions.single.receiptAt, isNotNull);
    },
  );

  test(
    'unload during a payload write cannot publish into the next owner',
    () async {
      final study = await enrolled();
      store.blockNextWrite();
      final recording = study.record(draft, stillEligible: () => true);
      await store.enteredWrite!.future;
      study.unload();
      final loadingOther = study.load('cloud:other');
      store.releaseWrite!.complete();
      await Future.wait([recording, loadingOther]);
      expect(study.owner, 'cloud:other');
      expect(study.loggingEnabled, isFalse);
      expect(study.run, isNull);
      expect(study.predictions, isEmpty);
      await study.load('local');
      expect(study.predictions.single.receiptAt, isNull);
    },
  );

  test(
    'clear drains an in-flight write and durably erases only its owner',
    () async {
      final study = await enrolled();
      store.values['sleep-energy:cloud:other'] = 'unrelated journal';
      store.values['cloud:local-ai1'] = 'unrelated AI1 history';
      store.blockNextWrite();
      final recording = study.record(draft, stillEligible: () => true);
      await store.enteredWrite!.future;
      final clearing = study.clear('local');
      expect(study.owner, isNull);
      expect(study.loggingEnabled, isFalse);
      store.releaseWrite!.complete();
      await Future.wait([recording, clearing]);
      expect(store.values.containsKey('sleep-energy:local'), isFalse);
      expect(store.values['sleep-energy:cloud:other'], 'unrelated journal');
      expect(store.values['cloud:local-ai1'], 'unrelated AI1 history');
      expect(store.operations.last, 'clear:sleep-energy:local');
      final restarted = service();
      await restarted.load('local');
      expect(restarted.run, isNull);
      expect(restarted.loggingEnabled, isFalse);
      expect(restarted.predictions, isEmpty);
    },
  );

  test('failed erasure is retried before an owner can be loaded', () async {
    final study = await enrolled();
    store.failNextClear = true;
    await expectLater(study.clear('local'), throwsStateError);
    expect(study.owner, isNull);
    expect(study.predictions, isEmpty);
    expect(store.values, contains('sleep-energy:local'));
    await study.load('local');
    expect(store.values.containsKey('sleep-energy:local'), isFalse);
    expect(study.loaded, isTrue);
    expect(study.loggingEnabled, isFalse);
    expect(study.run, isNull);
  });

  test(
    'disabling during payload save preserves an unscored day reservation',
    () async {
      final study = await enrolled();
      store.blockNextWrite();
      final recording = study.record(draft, stillEligible: () => true);
      await store.enteredWrite!.future;
      final disabling = study.setLogging(false);
      expect(study.loggingEnabled, isFalse);
      store.releaseWrite!.complete();
      await Future.wait([recording, disabling]);
      expect(study.predictions.single.receiptAt, isNull);
      expect(study.loggingEnabled, isFalse);
      final restarted = service();
      await restarted.load('local');
      expect(restarted.loggingEnabled, isFalse);
      expect(restarted.predictions.single.receiptAt, isNull);
      await restarted.setLogging(true);
      final writes = store.writeCount;
      await restarted.record(draft, stillEligible: () => true);
      expect(store.writeCount, writes);
      expect(restarted.predictions, hasLength(1));
    },
  );

  test(
    'eligibility lost while saving never becomes a backdated prediction',
    () async {
      final study = await enrolled();
      var eligible = true;
      store.blockNextWrite();
      final recording = study.record(draft, stillEligible: () => eligible);
      await store.enteredWrite!.future;
      eligible = false;
      store.releaseWrite!.complete();
      await recording;
      expect(study.predictions.single.receiptAt, isNull);
      final restarted = service();
      await restarted.load('local');
      expect(restarted.predictions.single.receiptAt, isNull);
      final writes = store.writeCount;
      await restarted.record(draft, stillEligible: () => true);
      expect(store.writeCount, writes);
    },
  );

  test(
    'ineligible issuance does not create a pending or committed record',
    () async {
      final study = await enrolled();
      final writes = store.writeCount;
      await study.record(draft, stillEligible: () => false);
      expect(store.writeCount, writes);
      expect(study.predictions, isEmpty);
    },
  );

  test(
    'later outcomes seal the target while every issued estimate stays frozen',
    () async {
      final study = await enrolled();
      await study.record(draft, stillEligible: () => true);
      final before = study.predictions.single;
      now = DateTime.utc(2026, 11, 4, 21);
      reports.add(_report(4, energy: 10));
      await study.reconcile(
        readiness: SleepEnergyExperiment.prepare(
          checkIns: reports,
          signals: sleeps,
          now: now,
        ),
        checkIns: reports,
        signals: sleeps,
      );
      final sealed = study.predictions.single;
      expect(sealed.targetId, 'response-4');
      expect(sealed.actual, 10);
      expect(sealed.modelPrediction, before.modelPrediction);
      expect(sealed.meanPrediction, before.meanPrediction);
      expect(sealed.lastPrediction, before.lastPrediction);
      expect(sealed.modelFingerprint, before.modelFingerprint);
      expect(study.run!.toJson(), run.toJson());
      final restarted = service();
      await restarted.load('local');
      expect(restarted.predictions.single.toJson(), sealed.toJson());
    },
  );

  test(
    'training-source deletion clears the fit and permanently invalidates issuance',
    () async {
      final study = await enrolled();
      await study.record(draft, stillEligible: () => true);
      final removed = reports.removeAt(0);
      await study.reconcile(
        readiness: SleepEnergyExperiment.prepare(
          checkIns: reports,
          signals: sleeps,
          now: now,
        ),
        checkIns: reports,
        signals: sleeps,
      );
      expect(study.run, isNull);
      expect(study.predictions, hasLength(1));
      reports.insert(0, removed);
      reports.add(_report(4));
      now = DateTime.utc(2026, 11, 4, 21);
      final restarted = service();
      await restarted.load('local');
      final result = SleepEnergyExperiment.evaluatePrediction(
        restarted.predictions.single,
        checkIns: reports,
        signals: sleeps,
        now: now,
      );
      expect(result.status, 'invalidated');
    },
  );

  test(
    'edited target never replaces the original prospectively paired answer',
    () async {
      final study = await enrolled();
      await study.record(draft, stillEligible: () => true);
      now = DateTime.utc(2026, 11, 4, 21);
      reports.add(_report(4, energy: 8));
      Future<void> reconcile() => study.reconcile(
        readiness: SleepEnergyExperiment.prepare(
          checkIns: reports,
          signals: sleeps,
          now: now,
        ),
        checkIns: reports,
        signals: sleeps,
      );
      await reconcile();
      final original = study.predictions.single;
      reports[3] = _report(4, energy: 2);
      await reconcile();
      expect(study.predictions.single.actual, original.actual);
      expect(
        study.predictions.single.targetFingerprint,
        original.targetFingerprint,
      );
      final evaluation = SleepEnergyExperiment.evaluatePrediction(
        study.predictions.single,
        checkIns: reports,
        signals: sleeps,
        now: now,
      );
      expect(evaluation.status, 'invalidated');
      final persisted = jsonDecode(store.values['sleep-energy:local']!) as Map;
      expect((persisted['predictions'] as List).single['actual'], 8);
    },
  );

  test(
    'Health disconnection retires Health predictions and preserves manual ones',
    () async {
      final study = await enrolled();
      await study.record(draft, stillEligible: () => true);
      final manual = study.predictions.single.toJson();
      final health = healthExample();
      await study.saveRun(health.run);
      await study.record(health.draft, stillEligible: () => true);
      await study.invalidateHealthSource();
      expect(study.run, isNull);
      expect(study.loggingEnabled, isFalse);
      expect(study.predictions.first.toJson(), manual);
      expect(
        study.predictions.last.invalidationReason,
        'health_source_disconnected',
      );
      final restarted = service();
      await restarted.load('local');
      expect(restarted.run, isNull);
      expect(restarted.predictions.last.invalidatedAt, isNotNull);
      final evaluation = SleepEnergyExperiment.evaluatePrediction(
        restarted.predictions.last,
        checkIns: [...reports, _report(4)],
        signals: health.sleeps,
        now: DateTime.utc(2026, 11, 4, 21),
      );
      expect(evaluation.status, 'invalidated');
    },
  );

  test(
    'failed Health invalidation is retried even when sources did not change',
    () async {
      final study = await enrolled();
      final health = healthExample();
      await study.saveRun(health.run);
      await study.record(health.draft, stillEligible: () => true);
      store.failWrites.add(store.writeCount + 1);
      await expectLater(study.invalidateHealthSource(), throwsStateError);
      expect(study.run, isNull);
      expect(study.predictions.single.invalidatedAt, isNotNull);
      final writes = store.writeCount;
      await study.reconcile(
        readiness: SleepEnergyExperiment.prepare(
          checkIns: reports,
          signals: health.sleeps,
          now: now,
        ),
        checkIns: reports,
        signals: health.sleeps,
      );
      expect(store.writeCount, writes + 1);
      final restarted = service();
      await restarted.load('local');
      expect(restarted.loggingEnabled, isFalse);
      expect(restarted.run, isNull);
      expect(
        restarted.predictions.single.invalidationReason,
        'health_source_disconnected',
      );
    },
  );

  test(
    'Health disconnection during payload save leaves a permanently excluded reservation',
    () async {
      final study = await enrolled();
      final health = healthExample();
      await study.saveRun(health.run);
      store.blockNextWrite();
      final recording = study.record(health.draft, stillEligible: () => true);
      await store.enteredWrite!.future;
      final disconnecting = study.invalidateHealthSource();
      store.releaseWrite!.complete();
      await Future.wait([recording, disconnecting]);
      expect(study.loggingEnabled, isFalse);
      expect(study.run, isNull);
      expect(study.predictions.single.receiptAt, isNull);
      expect(
        study.predictions.single.invalidationReason,
        'health_source_disconnected',
      );
      final restarted = service();
      await restarted.load('local');
      expect(restarted.predictions.single.invalidatedAt, isNotNull);
    },
  );

  test('an outdated training request is not saved', () async {
    final study = service();
    await study.load('local');
    await study.saveRun(run, stillEligible: () => false);
    expect(study.run, isNull);
    expect(store.writeCount, 0);
  });

  test(
    'training data changed during a blocked save clears the obsolete fit',
    () async {
      final study = service();
      await study.load('local');
      var eligible = true;
      store.blockNextWrite();
      final saving = study.saveRun(run, stillEligible: () => eligible);
      await store.enteredWrite!.future;
      eligible = false;
      store.releaseWrite!.complete();
      await saving;
      expect(study.run, isNull);
      final restarted = service();
      await restarted.load('local');
      expect(restarted.run, isNull);
    },
  );
}
