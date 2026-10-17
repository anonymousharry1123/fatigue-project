import 'dart:async';
import 'dart:convert';

import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/ai1_records.dart';
import 'package:app/src/ai_model_artifact.dart';
import 'package:app/src/ai_shadow_evaluation.dart';
import 'package:flutter_test/flutter_test.dart';

final _protocol = Ai1Protocol.draft();
DateTime _at(int day, [int hour = 10, int minute = 0]) =>
    DateTime.utc(2026, 1, day, hour, minute);
Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

class _Store implements AiShadowSimulatedStore {
  _Store(this.clock);
  final DateTime Function() clock;
  final values = <String, Map<String, dynamic>>{};
  Future<void> Function()? beforeWrite;
  Future<void> Function(String)? beforeRead;
  int writes = 0;
  int? failWrite;
  bool failClear = false;
  DateTime? receipt;
  @override
  Future<Map<String, dynamic>?> read(String scope) async {
    await beforeRead?.call(scope);
    return values[scope] == null ? null : _copy(values[scope]!);
  }

  @override
  Future<DateTime> write(String scope, Map<String, dynamic> snapshot) async {
    final count = ++writes;
    await beforeWrite?.call();
    if (count == failWrite) throw StateError('Synthetic interrupted write');
    values[scope] = _copy(snapshot);
    return receipt ?? clock();
  }

  @override
  Future<void> clear(String scope) async {
    if (failClear) throw StateError('Synthetic interrupted clear');
    values.remove(scope);
  }
}

AiShadowBlock _block({
  String scope = 'invented-owner-a',
  String participant = 'invented-person-a',
  String artifactId = 'fixture-model-v1',
  String candidate = 'M1',
  int first = 3,
}) => AiShadowBlock(
  blockId: 'invented-block-$scope',
  artifact: AiModelArtifact.synthetic(
    artifactId: artifactId,
    candidateId: candidate,
    protocol: _protocol,
    ownerScope: scope,
    participantKey: participant,
    timezone: 'Etc/UTC',
    fittedAt: _at(2, 9),
    dataCutoff: _at(1, 22),
    trainingOpportunityIds: candidate == 'B1'
        ? ['invented-history-1']
        : ['invented-history-1', 'invented-history-2'],
    intercept: candidate == 'M1' ? -8 : null,
    slope: candidate == 'M1' ? 2 : null,
    constantPrediction: candidate == 'M1' ? null : 6,
  ),
  protocol: _protocol,
  opportunities: [
    for (var day = first; day < first + 3; day++)
      _opportunity(day, participant),
  ],
);

Ai1Opportunity _opportunity(
  int day, [
  String participant = 'invented-person-a',
]) => Ai1Opportunity.forDate(
  protocol: _protocol,
  participantKey: participant,
  localDate: '2026-01-${day.toString().padLeft(2, '0')}',
  timezone: 'Etc/UTC',
);

Ai1FixtureDay _day(
  int day, {
  String participant = 'invented-person-a',
  bool synthetic = true,
  bool hasSleep = true,
  bool responded = true,
  bool withdrawn = false,
  double sleep = 7,
  num? energy = 7,
  DateTime? sleepAvailableAt,
  DateTime? sleepRevisedAt,
  DateTime? responseAt,
  DateTime? revisedAt,
  bool deleted = false,
  List<DateTime?> dependencies = const [],
  List<DateTime> timezoneChanges = const [],
}) {
  final opportunity = _opportunity(day, participant);
  final observed = responseAt ?? _at(day, 19);
  Ai1ResponseRevision response(
    int revision,
    DateTime available,
    num? value, {
    bool tombstone = false,
  }) => Ai1ResponseRevision(
    participantKey: participant,
    sourceId: 'invented-response-$day',
    revision: revision,
    observedAt: observed,
    initialSavedAt: observed,
    availableAt: available,
    localDate: opportunity.localDate,
    timezone: opportunity.timezone,
    measurement: _protocol.measurement,
    period: 'Evening',
    energy: value,
    deleted: tombstone,
  );
  return Ai1FixtureDay(
    opportunity: opportunity,
    synthetic: synthetic,
    withdrawn: withdrawn,
    sleepHistoryComplete: true,
    responseHistoryComplete: true,
    sleepRevisions: [
      if (hasSleep)
        Ai1SleepRevision(
          participantKey: participant,
          collection: 'invented-sleep',
          sourceId: 'invented-sleep-$day',
          revision: 1,
          source: Ai1SleepSource.manual,
          endedAt: _at(day, 7),
          startedAt: _at(
            day,
            7,
          ).subtract(Duration(minutes: (sleep * 60).round())),
          durationHours: sleep,
          availableAt: sleepAvailableAt ?? _at(day, 8),
          selectionDependencies: dependencies,
        ),
      if (hasSleep && sleepRevisedAt != null)
        Ai1SleepRevision(
          participantKey: participant,
          collection: 'invented-sleep',
          sourceId: 'invented-sleep-$day',
          revision: 2,
          source: Ai1SleepSource.manual,
          endedAt: _at(day, 7),
          startedAt: _at(day, 0),
          durationHours: 5,
          availableAt: sleepRevisedAt,
          selectionDependencies: dependencies,
        ),
    ],
    responseRevisions: [
      if (responded) response(1, observed, energy),
      if (responded && revisedAt != null)
        response(2, revisedAt, 1, tombstone: deleted),
    ],
    // Deliberately supplied by the fixture: execution must ignore these fields.
    issuedAt: _at(day, 10, 1),
    durableAt: _at(day, 10, 2),
    timezoneChanges: timezoneChanges,
  );
}

void main() {
  late DateTime now;
  late _Store store;
  late AiShadowHarness harness;
  late AiShadowBlock block;
  setUp(() {
    now = _at(2, 12);
    store = _Store(() => now);
    harness = AiShadowHarness(store: store, clock: () => now);
    block = _block();
  });
  Future<void> start() =>
      harness.start(scope: 'invented-owner-a', block: block);
  Map row(int day) =>
      (harness.report()['rows'] as List).singleWhere(
            (row) =>
                row['localDate'] == '2026-01-${day.toString().padLeft(2, '0')}',
          )
          as Map;

  test(
    'frozen model executes once at actual clock then links independent outcome',
    () async {
      await start();
      now = _at(3, 10, 4);
      final event = await harness.recordMorning(_day(3));
      expect(event!['executedAt'], now.toIso8601String());
      expect(event['receiptAt'], now.toIso8601String());
      expect(event['prediction'], 6);
      expect(event['artifactId'], 'fixture-model-v1');
      now = _at(3, 23);
      await harness.linkOutcome(_day(3));
      final report = harness.report();
      expect(row(3)['energy'], 7);
      expect(row(3)['signedError'], -1);
      expect(report['coverage']['mae'], 1);
      expect(report['coverage']['predicted'], 1);
      expect(report['simulatedDurability'], isTrue);
      expect(report['synthetic'], isTrue);
      expect(report['realProspectiveEvidence'], isFalse);
      expect(report['appModelActivationAllowed'], isFalse);
      expect(report['coachUseAllowed'], isFalse);
    },
  );

  test(
    'calendar includes unopened days and rates use all closed opportunities',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      now = _at(3, 23);
      await harness.linkOutcome(_day(3));
      now = _at(5, 23);
      final coverage = harness.report()['coverage'];
      expect(coverage['plannedOpportunities'], 3);
      expect(coverage['closedOpportunities'], 3);
      expect(coverage['predicted'], 1);
      expect(coverage['completedOutcomes'], 1);
      expect(coverage['unlinkedOutcomes'], 2);
      expect(coverage['predictionCoverage'], closeTo(1 / 3, 1e-12));
      expect(row(4)['executionStatus'], 'not_executed');
      expect(row(4)['outcomeStatus'], 'not_linked');
      expect(row(4)['prediction'], isNull);
    },
  );

  test(
    'empty closed calendar uses null rates and cannot be backdated or future dated',
    () async {
      await start();
      final coverage = harness.report()['coverage'];
      expect(coverage['closedOpportunities'], 0);
      expect(coverage['predictionCoverage'], isNull);
      expect(coverage['outcomeMissingnessRate'], isNull);
      expect(coverage['mae'], isNull);
      expect(() => harness.report(asOf: _at(1)), throwsArgumentError);
      expect(() => harness.report(asOf: _at(6)), throwsArgumentError);
    },
  );

  test(
    'missed actual execution never uses fixture timestamps to backdate a prediction',
    () async {
      await start();
      now = _at(3, 9, 59);
      expect(await harness.recordMorning(_day(3)), isNull);
      now = _at(3, 10, 15);
      final event = await harness.recordMorning(_day(3));
      expect(event!['executionStatus'], 'missed_window');
      expect(event['executedAt'], _at(3, 10, 15).toIso8601String());
      expect(event['prediction'], isNull);
      now = _at(3, 23);
      await harness.linkOutcome(_day(3));
      expect(row(3)['energy'], 7);
      expect(row(3)['scored'], isFalse);
    },
  );

  test(
    'simulated durable receipt at deadline invalidates an attempted prediction',
    () async {
      await start();
      now = _at(3, 10, 14);
      store.receipt = _at(3, 10, 15);
      final event = await harness.recordMorning(_day(3));
      expect(event!['executionStatus'], 'missed_window');
      expect(event['prediction'], isNull);
      expect(event['feature'], isNull);
      store.receipt = null;
      now = _at(3, 23);
      expect(harness.report()['coverage']['predicted'], 0);
    },
  );

  test(
    'late feature or late selection dependency cannot enter morning inference',
    () async {
      await start();
      now = _at(3, 10, 5);
      expect(
        (await harness.recordMorning(
          _day(3, sleepAvailableAt: _at(3, 10, 1)),
        ))!['prediction'],
        isNull,
      );
      now = _at(4, 10, 5);
      expect(
        (await harness.recordMorning(
          _day(4, dependencies: [_at(4, 10, 1)]),
        ))!['prediction'],
        isNull,
      );
      now = _at(5, 10, 5);
      expect(
        (await harness.recordMorning(
          _day(5, dependencies: [null]),
        ))!['prediction'],
        isNull,
      );
    },
  );

  test(
    'baseline model executes without sleep while preserving independent travel exclusion',
    () async {
      block = _block(candidate: 'B0');
      await start();
      now = _at(3, 10, 4);
      expect(
        (await harness.recordMorning(_day(3, hasSleep: false)))!['prediction'],
        6,
      );
      now = _at(3, 23);
      await harness.linkOutcome(
        _day(3, hasSleep: false, timezoneChanges: [_at(3, 11)]),
      );
      expect(row(3)['outcomeStatus'], 'timezone_changed');
      expect(row(3)['scored'], isFalse);
    },
  );

  test(
    'event retry and changed evidence never revise its frozen prediction',
    () async {
      await start();
      now = _at(3, 10, 3);
      final first = await harness.recordMorning(_day(3, sleep: 7));
      final writes = store.writes;
      now = _at(3, 10, 4);
      final retry = await harness.recordMorning(_day(3, sleep: 5));
      expect(retry, first);
      expect(store.writes, writes);
      final restored = AiShadowHarness(store: store, clock: () => now);
      await restored.start(scope: 'invented-owner-a', block: block);
      expect(await restored.recordMorning(_day(3, sleep: 9)), first);
    },
  );

  test(
    'missing and late outcomes are explicit, never replaced with a neutral target',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      now = _at(3, 21);
      await expectLater(harness.linkOutcome(_day(3)), throwsStateError);
      now = _at(3, 23);
      await harness.linkOutcome(_day(3, energy: null));
      expect(row(3)['outcomeStatus'], 'missing_energy');
      expect(row(3)['energy'], isNull);
      now = _at(4, 10, 3);
      await harness.recordMorning(_day(4));
      now = _at(4, 23);
      await harness.linkOutcome(_day(4, responseAt: _at(4, 22)));
      expect(row(4)['outcomeStatus'], 'no_response_in_window');
      expect(harness.report()['coverage']['lateOriginalResponses'], 1);
      expect(harness.report()['coverage']['scored'], 0);
      expect(harness.report()['coverage']['mae'], isNull);
    },
  );

  test(
    'later outcome correction invalidates scoring while preserving prediction',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      now = _at(3, 23);
      await harness.linkOutcome(_day(3));
      final event = row(3)['event'];
      now = _at(4, 12);
      await harness.linkOutcome(_day(3, revisedAt: _at(4, 11)));
      expect(row(3)['event'], event);
      expect(row(3)['outcomeStatus'], 'selected_response_revised');
      expect(row(3)['scored'], isFalse);
      final historical =
          (harness.report(asOf: _at(3, 23))['rows'] as List).single as Map;
      expect(historical['outcomeStatus'], 'matched');
      expect(historical['energy'], 7);
      expect(historical['signedError'], -1);
      expect(historical['outcome']['assessedAt'], _at(3, 23).toIso8601String());
      expect(historical['outcome'], isNot(contains('previousAssessments')));
      final restored = AiShadowHarness(store: store, clock: () => now);
      await restored.start(scope: 'invented-owner-a', block: block);
      expect(restored.report(asOf: _at(3, 23))['rows'], [historical]);
    },
  );

  test(
    'a changed precutoff feature cannot silently score the frozen prediction',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      now = _at(3, 23);
      await harness.linkOutcome(_day(3, sleep: 5));
      expect(row(3)['prediction'], 6);
      expect(row(3)['energy'], 7);
      expect(row(3)['pairingStatus'], 'feature_lineage_changed');
      expect(row(3)['scored'], isFalse);
      expect(harness.report()['coverage']['completedOutcomes'], 1);
      expect(harness.report()['coverage']['scored'], 0);
      expect(harness.report()['coverage']['mae'], isNull);
    },
  );

  test(
    'known response correction cannot disappear after retry or reopening',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      now = _at(3, 23);
      await harness.linkOutcome(_day(3));
      now = _at(4, 12);
      await harness.linkOutcome(_day(3, revisedAt: _at(4, 11)));
      expect(row(3)['outcomeStatus'], 'selected_response_revised');
      now = _at(4, 13);
      await harness.linkOutcome(_day(3));
      expect(row(3)['outcomeStatus'], 'selected_response_revised');
      expect(row(3)['energy'], isNull);
      expect(row(3)['scored'], isFalse);
      final restored = AiShadowHarness(store: store, clock: () => now);
      await restored.start(scope: 'invented-owner-a', block: block);
      now = _at(4, 14);
      await restored.linkOutcome(_day(3));
      final latest = (restored.report()['rows'] as List).single as Map;
      expect(latest['outcomeStatus'], 'selected_response_revised');
      expect(latest['scored'], isFalse);
      final original =
          (restored.report(asOf: _at(3, 23))['rows'] as List).single as Map;
      expect(original['energy'], 7);
      expect(original['scored'], isTrue);
    },
  );

  test(
    'mutating an already observed source revision invalidates scoring permanently',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      now = _at(3, 23);
      await harness.linkOutcome(_day(3));
      now = _at(4, 12);
      await harness.linkOutcome(_day(3, energy: 9));
      expect(row(3)['outcomeStatus'], 'conflicting_response_revision');
      expect(row(3)['energy'], isNull);
      expect(row(3)['scored'], isFalse);
      final restored = AiShadowHarness(store: store, clock: () => now);
      await restored.start(scope: 'invented-owner-a', block: block);
      now = _at(4, 13);
      await restored.linkOutcome(_day(3));
      expect(
        (restored.report()['rows'] as List).single['outcomeStatus'],
        'conflicting_response_revision',
      );
      expect(restored.report()['coverage']['scored'], 0);
    },
  );

  test(
    'omitted original evidence cannot be replaced with another target later',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      now = _at(3, 23);
      await harness.linkOutcome(_day(3));
      now = _at(4, 12);
      await harness.linkOutcome(_day(3, responded: false));
      expect(row(3)['outcomeStatus'], 'response_history_regressed');
      now = _at(4, 13);
      await harness.linkOutcome(_day(3));
      expect(row(3)['outcomeStatus'], 'response_history_regressed');
      expect(row(3)['scored'], isFalse);
    },
  );

  test(
    'a legitimate later sleep revision preserves the original cutoff feature',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      now = _at(3, 23);
      await harness.linkOutcome(_day(3, sleepRevisedAt: _at(3, 12)));
      expect(row(3)['event']['feature']['revision'], 1);
      expect(row(3)['event']['feature']['durationHours'], 7);
      expect(row(3)['pairingStatus'], 'compatible');
      expect(row(3)['scored'], isTrue);
    },
  );

  for (final withdraw in [true, false]) {
    test(
      'idempotent retry honors ${withdraw ? 'withdrawal' : 'source deletion'} first',
      () async {
        await start();
        now = _at(3, 10, 3);
        await harness.recordMorning(_day(3));
        now = _at(3, 10, 4);
        final retry = await harness.recordMorning(
          _day(
            3,
            withdrawn: withdraw,
            revisedAt: withdraw ? null : _at(4),
            deleted: !withdraw,
          ),
        );
        expect(retry, isNull);
        expect(store.values['invented-owner-a']!['events'], isEmpty);
        now = _at(3, 23);
        expect(row(3)['executionStatus'], withdraw ? 'withdrawn' : 'deleted');
        expect(row(3)['prediction'], isNull);
        expect(await harness.recordMorning(_day(3)), isNull);
      },
    );
  }

  for (final mutation in [
    'prediction',
    'feature',
    'unknown_field',
    'outcome',
  ]) {
    test('restoring rejects mutated saved $mutation', () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      now = _at(3, 23);
      await harness.linkOutcome(_day(3));
      final snapshot = store.values['invented-owner-a']!;
      final event = (snapshot['events'] as Map).values.single as Map;
      switch (mutation) {
        case 'prediction':
          event['prediction'] = 9;
        case 'feature':
          event['feature']['availableAt'] = _at(3, 11).toIso8601String();
        case 'unknown_field':
          event['privateNotes'] = 'Unapproved raw field';
        case 'outcome':
          ((snapshot['outcomes'] as Map).values.single as Map)['energy'] = 99;
      }
      final restored = AiShadowHarness(store: store, clock: () => now);
      await expectLater(
        restored.start(scope: 'invented-owner-a', block: block),
        throwsStateError,
      );
      expect(restored.active, isFalse);
      expect(() => restored.report(), throwsStateError);
    });
  }

  test(
    'an interrupted outcome correction cannot score an earlier stale assessment',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      now = _at(3, 23);
      await harness.linkOutcome(_day(3));
      store.failWrite = store.writes + 1;
      now = _at(4, 12);
      await expectLater(
        harness.linkOutcome(_day(3, revisedAt: _at(4, 11))),
        throwsStateError,
      );
      expect(row(3)['outcomeStatus'], 'save_failed');
      expect(row(3)['energy'], isNull);
      expect(row(3)['event'], isNull);
      expect(row(3)['outcome'], isNull);
      expect(row(3)['scored'], isFalse);
    },
  );

  test(
    'failed erasure hides payload immediately and signout clears the saved scope',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      now = _at(3, 23);
      await harness.linkOutcome(_day(3));
      store.failWrite = store.writes + 1;
      await expectLater(
        harness.deleteOpportunity(_opportunity(3).id),
        throwsStateError,
      );
      expect(row(3)['executionStatus'], 'erase_failed');
      expect(row(3)['prediction'], isNull);
      expect(row(3)['energy'], isNull);
      await harness.signOut();
      expect(store.values['invented-owner-a'], isNull);
    },
  );

  test(
    'deletion erases event and target payloads while retaining a denominator tombstone',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      now = _at(3, 23);
      await harness.linkOutcome(_day(3));
      await harness.deleteOpportunity(_opportunity(3).id);
      expect(row(3)['executionStatus'], 'deleted');
      expect(row(3)['event'], isNull);
      expect(row(3)['outcome'], isNull);
      expect(harness.report()['coverage']['activeClosedOpportunities'], 1);
      expect(await harness.recordMorning(_day(3)), isNull);
      expect(store.values['invented-owner-a']!['events'], isEmpty);
      expect(store.values['invented-owner-a']!['outcomes'], isEmpty);
    },
  );

  test(
    'source tombstone and withdrawal erase derived payload and never resurrect',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      now = _at(3, 23);
      await harness.linkOutcome(_day(3, revisedAt: _at(4), deleted: true));
      expect(row(3)['executionStatus'], 'deleted');
      now = _at(4, 23);
      await harness.linkOutcome(_day(4, withdrawn: true));
      expect(row(4)['executionStatus'], 'withdrawn');
      expect(harness.report()['coverage']['withdrawnOpportunities'], 1);
      expect(harness.report()['coverage']['activeClosedOpportunities'], 1);
    },
  );

  test(
    'receipt-write failure has no valid event or false durable claim',
    () async {
      await start();
      now = _at(3, 10, 3);
      store.failWrite = store.writes + 2;
      await expectLater(harness.recordMorning(_day(3)), throwsStateError);
      expect(harness.active, isFalse);
      expect(store.values['invented-owner-a']!['pending'], isTrue);
      now = _at(3, 23);
      expect(row(3)['executionStatus'], 'save_failed');
      expect(row(3)['prediction'], isNull);
      expect(harness.report()['interrupted'], isTrue);
      final restored = AiShadowHarness(store: store, clock: () => now);
      await expectLater(
        restored.start(scope: 'invented-owner-a', block: block),
        throwsStateError,
      );
    },
  );

  test(
    'a backdated simulated receipt and clock rollback fail closed',
    () async {
      await start();
      now = _at(3, 10, 3);
      store.receipt = _at(3, 10, 2);
      await expectLater(harness.recordMorning(_day(3)), throwsStateError);
      expect(harness.active, isFalse);
      now = _at(3, 10, 1);
      expect(() => harness.report(), throwsStateError);
    },
  );

  test(
    'captured inputs, out-of-calendar evidence, and wrong owner scopes reject',
    () async {
      await start();
      now = _at(3, 10, 3);
      await expectLater(
        harness.recordMorning(_day(3, synthetic: false)),
        throwsArgumentError,
      );
      await expectLater(
        harness.linkOutcome(_day(3, synthetic: false)),
        throwsArgumentError,
      );
      await expectLater(harness.recordMorning(_day(6)), throwsArgumentError);
      await expectLater(
        harness.start(scope: 'another-owner', block: block),
        throwsArgumentError,
      );
    },
  );

  test(
    'an existing block cannot change models; a late plan cannot create past opportunities',
    () async {
      await start();
      await expectLater(
        harness.start(
          scope: 'invented-owner-a',
          block: _block(artifactId: 'different-model'),
        ),
        throwsStateError,
      );
      await harness.reset();
      now = _at(3, 10);
      await expectLater(start(), throwsStateError);
    },
  );

  test(
    'signout hides state and preserves only previously committed history',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      await harness.signOut();
      expect(harness.active, isFalse);
      expect(() => harness.report(), throwsStateError);
      expect(store.values['invented-owner-a']!['events'], hasLength(1));
      await start();
      now = _at(3, 23);
      expect(row(3)['prediction'], 6);
      await harness.optOut();
      expect(store.values['invented-owner-a'], isNull);
      expect(() => harness.report(), throwsStateError);
    },
  );

  test(
    'failed clear stays hidden, retries, and blocks reloading unerased history',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      store.failClear = true;
      await expectLater(harness.optOut(), throwsStateError);
      expect(store.values['invented-owner-a']!['events'], hasLength(1));
      expect(harness.active, isFalse);
      expect(() => harness.report(), throwsStateError);
      await expectLater(harness.optOut(), throwsStateError);
      await expectLater(start(), throwsStateError);
      expect(harness.active, isFalse);
      store.failClear = false;
      await harness.reset();
      expect(store.values['invented-owner-a'], isNull);
    },
  );

  for (final field in ['planCreatedAt', 'planReceiptAt', 'lastReceiptAt']) {
    test('restoring rejects a noncanonical or impossible $field', () async {
      await start();
      store.values['invented-owner-a']![field] = field == 'planCreatedAt'
          ? _at(2, 13).toIso8601String()
          : '2026-01-02T12:00:00';
      final restored = AiShadowHarness(store: store, clock: () => now);
      await expectLater(
        restored.start(scope: 'invented-owner-a', block: block),
        throwsStateError,
      );
      expect(restored.active, isFalse);
    });
  }

  test(
    'signout during an in-flight write rolls it back before scope can resume',
    () async {
      await start();
      now = _at(3, 10, 3);
      final entered = Completer<void>();
      final release = Completer<void>();
      store.beforeWrite = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final pending = harness.recordMorning(_day(3));
      await entered.future;
      final leaving = harness.signOut();
      expect(harness.active, isFalse);
      expect(() => harness.report(), throwsStateError);
      release.complete();
      expect(await pending, isNull);
      await leaving;
      expect(store.values['invented-owner-a']!['events'], isEmpty);
      await start();
      now = _at(3, 23);
      expect(row(3)['prediction'], isNull);
    },
  );

  test(
    'optout during a pending write clears its eventual stored payload',
    () async {
      await start();
      now = _at(3, 10, 3);
      final entered = Completer<void>();
      final release = Completer<void>();
      store.beforeWrite = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final pending = harness.recordMorning(_day(3));
      await entered.future;
      final clearing = harness.optOut();
      release.complete();
      expect(await pending, isNull);
      await clearing;
      expect(store.values['invented-owner-a'], isNull);
    },
  );

  for (final action in ['signout', 'switch']) {
    test(
      'an in-flight erasure survives $action without restoring deleted data',
      () async {
        await start();
        now = _at(3, 10, 3);
        await harness.recordMorning(_day(3));
        final entered = Completer<void>();
        final release = Completer<void>();
        store.beforeWrite = () async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        };
        final deleting = harness.deleteOpportunity(_opportunity(3).id);
        await entered.future;
        final leaving = action == 'signout'
            ? harness.signOut()
            : harness.start(
                scope: 'invented-owner-b',
                block: _block(
                  scope: 'invented-owner-b',
                  participant: 'invented-person-b',
                  first: 4,
                ),
              );
        release.complete();
        await deleting;
        await leaving;
        expect(store.values['invented-owner-a'], isNull);
      },
    );
  }

  test(
    'a queued source withdrawal remains an erasure when signout happens before its write',
    () async {
      await start();
      now = _at(3, 10, 3);
      await harness.recordMorning(_day(3));
      final deleting = harness.recordMorning(_day(3, withdrawn: true));
      final leaving = harness.signOut();
      await deleting;
      await leaving;
      expect(store.values['invented-owner-a'], isNull);
    },
  );

  test(
    'account switch cancels pending prediction without exposing another scope',
    () async {
      await start();
      now = _at(3, 10, 3);
      final entered = Completer<void>();
      final release = Completer<void>();
      store.beforeWrite = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final pending = harness.recordMorning(_day(3));
      await entered.future;
      final other = _block(
        scope: 'invented-owner-b',
        participant: 'invented-person-b',
        first: 4,
      );
      final switching = harness.start(scope: 'invented-owner-b', block: other);
      release.complete();
      await pending;
      await switching;
      expect(harness.scope, 'invented-owner-b');
      expect(store.values['invented-owner-a']!['events'], isEmpty);
      now = _at(4, 23);
      expect(
        jsonEncode(harness.report()),
        isNot(contains('invented-person-a')),
      );
      await expectLater(harness.recordMorning(_day(4)), throwsArgumentError);
    },
  );

  test(
    'switching away during read never erases a previously saved account',
    () async {
      await start();
      final before = _copy(store.values['invented-owner-a']!);
      await harness.signOut();
      final entered = Completer<void>();
      final release = Completer<void>();
      store.beforeRead = (scope) async {
        if (scope == 'invented-owner-a') {
          entered.complete();
          await release.future;
        }
      };
      final loading = start();
      await entered.future;
      final switching = harness.start(
        scope: 'invented-owner-b',
        block: _block(
          scope: 'invented-owner-b',
          participant: 'invented-person-b',
        ),
      );
      release.complete();
      await loading;
      await switching;
      expect(store.values['invented-owner-a'], before);
      expect(harness.scope, 'invented-owner-b');
    },
  );
}
