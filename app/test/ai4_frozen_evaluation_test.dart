import 'dart:convert';

import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/ai1_records.dart';
import 'package:app/src/ai4_frozen_evaluation.dart';
import 'package:app/src/ai_model_artifact.dart';
import 'package:flutter_test/flutter_test.dart';

final protocol = Ai1Protocol.draft();
DateTime at(int day, [int hour = 10]) => DateTime.utc(2026, 2, day, hour);
Ai4FrozenManifest manifest() => Ai4FrozenManifest(
  protocol: protocol,
  experimentId: 'invented-frozen-test',
  datasetVersion: 'v1',
  historyStart: at(1),
  fitCutoff: at(3),
  finalStart: at(5),
  evaluationEnd: at(7),
  analysisAsOf: at(8),
);

Ai1FixtureDay day(
  int number, {
  double sleep = 7,
  int? energy = 6,
  String person = 'invented-person',
  bool hasSleep = true,
  bool issued = true,
  bool synthetic = true,
  bool withdrawn = false,
  DateTime? available,
  DateTime? revised,
  List<Ai1ResponseRevision> extra = const [],
  String timezone = 'Etc/UTC',
}) {
  final opportunity = Ai1Opportunity.forDate(
    protocol: protocol,
    participantKey: person,
    localDate: '2026-02-${number.toString().padLeft(2, '0')}',
    timezone: timezone,
  );
  final observed = opportunity.outcomeStart.add(const Duration(minutes: 30));
  Ai1ResponseRevision response(int revision, DateTime availableAt) =>
      Ai1ResponseRevision(
        participantKey: person,
        sourceId: 'response-$number',
        revision: revision,
        observedAt: observed,
        initialSavedAt: observed,
        availableAt: availableAt,
        localDate: opportunity.localDate,
        timezone: opportunity.timezone,
        measurement: protocol.measurement,
        period: 'Evening',
        energy: energy,
      );
  return Ai1FixtureDay(
    opportunity: opportunity,
    synthetic: synthetic,
    sleepHistoryComplete: true,
    responseHistoryComplete: true,
    withdrawn: withdrawn,
    sleepRevisions: [
      if (hasSleep)
        Ai1SleepRevision(
          participantKey: person,
          collection: 'synthetic-sleep',
          sourceId: 'sleep-$number',
          revision: 1,
          source: protocol.sleepSource,
          durationHours: sleep,
          endedAt: opportunity.cutoff.subtract(const Duration(hours: 3)),
          availableAt: opportunity.cutoff.subtract(const Duration(hours: 2)),
        ),
    ],
    responseRevisions: [
      response(1, available ?? observed),
      if (revised != null) response(2, revised),
      ...extra,
    ],
    issuedAt: issued
        ? opportunity.cutoff.add(const Duration(minutes: 1))
        : null,
    durableAt: issued
        ? opportunity.cutoff.add(const Duration(minutes: 2))
        : null,
  );
}

List<Ai1FixtureDay> training() => [
  day(1, sleep: 6, energy: 4),
  day(2, sleep: 8, energy: 8),
];
Ai4FrozenExperiment prepare({
  List<Ai1FixtureDay>? train,
  List<Ai1FixtureDay>? development,
}) => Ai4FrozenExperiment.prepareSynthetic(
  manifest: manifest(),
  trainingDays: train ?? training(),
  developmentDays: development ?? [day(3), day(4)],
);
Map<String, dynamic> finalReport(
  Ai4FrozenExperiment experiment, {
  List<Ai1FixtureDay>? days,
}) => experiment.openSyntheticFinal(
  days: days ?? [day(5), day(6, sleep: 9, energy: 9)],
);
Map<String, dynamic> row(Map<String, dynamic> report, int index) =>
    report['final']['rows'][index] as Map<String, dynamic>;

void main() {
  test(
    'frozen means/latest/regression use only training and retain exact lineage',
    () {
      final experiment = prepare();
      expect(experiment.finalOpened, isFalse);
      final result = finalReport(experiment);
      expect(experiment.finalOpened, isTrue);
      expect(row(result, 0)['methods']['B0']['prediction'], 6);
      expect(row(result, 0)['methods']['B1']['prediction'], 8);
      expect(row(result, 0)['methods']['M1']['prediction'], 6);
      expect(row(result, 1)['methods']['B0']['prediction'], 6);
      expect(row(result, 1)['methods']['B1']['prediction'], 8);
      expect(row(result, 1)['methods']['M1']['prediction'], 10);
      expect(
        row(result, 1)['methods']['M1']['trainingOpportunityIds'],
        training().map((d) => d.opportunity.id).toList(),
      );
      expect(result['final']['methods']['M1']['mae'], 0.5);
      expect(result['final']['selectedComparison']['maeDifference'], -1);
    },
  );

  test(
    'development labels never select/refit final coefficients or baselines',
    () {
      final a = prepare();
      final b = prepare(development: [day(3, energy: 1), day(4, energy: 10)]);
      expect(
        b.artifacts['invented-person']!['M1']!.fingerprint,
        a.artifacts['invented-person']!['M1']!.fingerprint,
      );
      expect(finalReport(b)['final'], finalReport(a)['final']);
    },
  );

  test('final answers never update any later final prediction', () {
    final a = finalReport(prepare());
    final b = finalReport(
      prepare(),
      days: [day(5, energy: 1), day(6, sleep: 9, energy: 2)],
    );
    for (var index = 0; index < 2; index++) {
      for (final id in ['B0', 'B1', 'M1']) {
        expect(
          row(a, index)['methods'][id]['prediction'],
          row(b, index)['methods'][id]['prediction'],
        );
      }
    }
  });

  test(
    'training label unavailable at fit cutoff cannot enter later frozen fits',
    () {
      final result = finalReport(
        prepare(
          train: [
            day(1, sleep: 6, energy: 4),
            day(2, sleep: 8, energy: 8, available: at(4)),
          ],
        ),
      );
      expect(row(result, 0)['methods']['B0']['prediction'], 4);
      expect(row(result, 0)['methods']['M1']['status'], 'no_frozen_model');
    },
  );

  test(
    'availability exactly at freeze is included; later edits do not rewrite fit',
    () {
      final result = finalReport(
        prepare(
          train: [
            day(1, sleep: 6, energy: 4),
            day(2, sleep: 8, energy: 8, available: at(3), revised: at(4)),
          ],
        ),
      );
      expect(row(result, 0)['methods']['M1']['prediction'], 6);
    },
  );

  test('final target edits affect scoring but never numerical issuance', () {
    final result = finalReport(
      prepare(),
      days: [
        day(5, revised: at(6)),
        day(6),
      ],
    );
    expect(row(result, 0)['outcomeStatus'], 'selected_response_revised');
    expect(row(result, 0)['methods']['M1']['prediction'], 6);
    expect(row(result, 0)['methods']['M1']['scored'], isFalse);
  });

  test(
    'missing outcomes preserve prediction denominator and unscored rows',
    () {
      final result = finalReport(prepare(), days: [day(5, energy: null)]);
      expect(result['final']['methods']['M1']['coverage'], 1);
      expect(result['final']['methods']['M1']['scoredCoverage'], 0);
      expect(result['final']['methods']['M1']['mae'], isNull);
      expect(result['final']['selectedComparison']['maeDifference'], isNull);
    },
  );

  test(
    'missing sleep and missed execution expose method-specific coverage',
    () {
      final result = finalReport(
        prepare(),
        days: [day(5, hasSleep: false), day(6, issued: false)],
      );
      expect(result['final']['methods']['B0']['predicted'], 1);
      expect(result['final']['methods']['M1']['predicted'], 0);
      expect(row(result, 1)['methods']['B0']['status'], 'no_execution');
    },
  );

  test('unseen participant cannot borrow another person model or baseline', () {
    final result = finalReport(
      prepare(),
      days: [day(5, person: 'new-invented-person')],
    );
    for (final id in ['B0', 'B1', 'M1']) {
      expect(row(result, 0)['methods'][id]['status'], 'no_frozen_model');
    }
  });

  test(
    'final access is separate and one-use; invalidated fits cannot be scored',
    () {
      final used = prepare();
      finalReport(used);
      expect(() => finalReport(used), throwsStateError);
      final erased = prepare()..invalidate();
      expect(() => finalReport(erased), throwsStateError);
    },
  );

  test(
    'captured data and overlapping or out-of-window partitions are rejected',
    () {
      expect(
        () => prepare(train: [day(1, synthetic: false)]),
        throwsArgumentError,
      );
      expect(() => prepare(development: [day(2)]), throwsArgumentError);
      expect(() => finalReport(prepare(), days: [day(4)]), throwsArgumentError);
      expect(() => finalReport(prepare(), days: [day(7)]), throwsArgumentError);
    },
  );

  test(
    'conflicting duplicate evidence is rejected and identical copies deduplicate',
    () {
      expect(
        () => prepare(train: [day(1), day(1, energy: 8)]),
        throwsArgumentError,
      );
      final original = finalReport(prepare());
      final repeated = finalReport(
        prepare(train: [...training(), training().first]),
        days: [day(6, sleep: 9, energy: 9), day(5), day(5)],
      );
      expect(jsonEncode(repeated), jsonEncode(original));
    },
  );

  test(
    'artifact serialization preserves inference without a legacy conversion',
    () {
      final artifact = prepare().artifacts['invented-person']!['M1']!;
      final restored = AiModelArtifact.fromJson(artifact.toJson());
      final result = restored.predict(
        context: AiModelInferenceContext(
          ownerScope: Ai4FrozenExperiment.ownerScope,
          participantKey: 'invented-person',
          protocol: protocol,
          timezone: 'Etc/UTC',
          at: at(5),
          featureCutoff: at(5),
        ),
        sleepHours: 7,
        sleepAvailableAt: at(5, 8),
      );
      expect(result.prediction, 6);
      expect(restored.fingerprint, artifact.fingerprint);
    },
  );

  test(
    'empty and withdrawn partitions do not invent rates or statistical claims',
    () {
      final experiment = prepare(train: [], development: []);
      final result = finalReport(experiment, days: [day(5, withdrawn: true)]);
      expect(result['final']['coverage']['activeOpportunities'], 0);
      expect(result['final']['methods']['B0']['coverage'], isNull);
      expect(result['decision'], 'blocked_no_empirical_evidence');
      expect(result['modelPromotionAllowed'], isFalse);
      expect(
        result['uncertainty']['status'],
        'not_estimated_pending_statistical_review',
      );
    },
  );

  test(
    'known training tombstones invalidate both development and final access',
    () {
      final original = training().first.responseRevisions.first;
      final tombstone = Ai1ResponseRevision(
        participantKey: original.participantKey,
        sourceId: original.sourceId,
        revision: 2,
        observedAt: original.observedAt,
        initialSavedAt: original.initialSavedAt,
        availableAt: at(6),
        localDate: original.localDate,
        timezone: original.timezone,
        measurement: original.measurement,
        period: original.period,
        energy: original.energy,
        deleted: true,
      );
      expect(
        () => prepare(
          development: [
            day(3, extra: [tombstone]),
          ],
        ),
        throwsStateError,
      );
      expect(
        () => finalReport(
          prepare(),
          days: [
            day(5, extra: [tombstone]),
          ],
        ),
        throwsStateError,
      );
    },
  );

  test(
    'constant sleep leaves regression unavailable with baseline fit intact',
    () {
      final result = finalReport(
        prepare(train: [day(1, energy: 4), day(2, energy: 8)]),
      );
      expect(row(result, 0)['methods']['B0']['prediction'], 6);
      expect(row(result, 0)['methods']['M1']['status'], 'no_frozen_model');
    },
  );

  test('fixed participant timezone applies across development and final', () {
    final experiment = prepare(development: [day(3, person: 'new-person')]);
    expect(
      () => finalReport(
        experiment,
        days: [day(5, person: 'new-person', timezone: 'America/New_York')],
      ),
      throwsArgumentError,
    );
  });

  test(
    'invalid manifest ordering and same candidate/comparator are rejected',
    () {
      expect(
        () => Ai4FrozenManifest(
          protocol: protocol,
          experimentId: 'x',
          datasetVersion: 'v1',
          historyStart: at(1),
          fitCutoff: at(3),
          finalStart: at(5),
          evaluationEnd: at(7),
          analysisAsOf: at(6),
        ),
        throwsArgumentError,
      );
      expect(
        () => Ai4FrozenManifest(
          protocol: protocol,
          experimentId: 'x',
          datasetVersion: 'v1',
          historyStart: at(1),
          fitCutoff: at(3),
          finalStart: at(5),
          evaluationEnd: at(7),
          analysisAsOf: at(8),
          candidateId: 'B0',
          comparatorId: 'B0',
        ),
        throwsArgumentError,
      );
    },
  );
}
