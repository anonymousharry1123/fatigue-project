import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/ai_predata_gate.dart';
import 'package:flutter_test/flutter_test.dart';

final _protocol = Ai1Protocol.draft();
final _asOf = DateTime.utc(2026, 10, 17);

Ai5FeatureDefinition _feature({
  String id = Ai5FeatureManifest.sleepFeatureId,
  String unit = 'hours',
  Ai1SleepSource source = Ai1SleepSource.manual,
  String observationRule = Ai5FeatureManifest.sleepObservationRule,
  String availabilityRule = Ai5FeatureManifest.localAvailabilityRule,
}) => Ai5FeatureDefinition(
  id: id,
  unit: unit,
  source: source,
  selectionVersion: Ai5FeatureManifest.sleepSelectionVersion,
  observationRule: observationRule,
  availabilityRule: availabilityRule,
);

AiPredataSettings _settings({Map<AiPredataRequirement, String>? versions}) =>
    AiPredataSettings(
      protocol: _protocol,
      experimentId: 'invented-scope-v1',
      features: Ai5FeatureManifest.sleepOnly(protocol: _protocol),
      decisionVersions:
          versions ??
          {for (final id in AiPredataRequirement.values) id: 'decision-v1'},
    );

AiPredataEvidence _evidence(
  AiPredataRequirement requirement, {
  AiPredataEvidenceStatus status =
      AiPredataEvidenceStatus.acceptedForDeclaredScope,
  AiPredataEvidenceKind? kind,
  String experimentId = 'invented-scope-v1',
  String? protocolId,
  String decisionVersion = 'decision-v1',
  String reference = 'invented-test-reference',
  String? reviewer = 'invented-test-reviewer',
  DateTime? reviewedAt,
}) => AiPredataEvidence(
  requirement: requirement,
  status: status,
  kind:
      kind ??
      switch (requirement) {
        AiPredataRequirement.realDataReadiness ||
        AiPredataRequirement.frozenEvaluation ||
        AiPredataRequirement.prospectiveShadowEvaluation =>
          AiPredataEvidenceKind.prospectiveDataAssessment,
        AiPredataRequirement.physicalDeviceAcceptance =>
          AiPredataEvidenceKind.physicalDeviceObservation,
        _ => AiPredataEvidenceKind.reviewRecord,
      },
  experimentId: experimentId,
  protocolId: protocolId ?? _protocol.id,
  decisionVersion: decisionVersion,
  reference: reference,
  reviewer: reviewer,
  reviewedAt: reviewedAt ?? _asOf,
);

Map<String, dynamic> _row(
  Map<String, dynamic> report,
  AiPredataRequirement id,
) => (report['requirements'] as List).cast<Map<String, dynamic>>().singleWhere(
  (row) => row['requirement'] == id.name,
);

void main() {
  test(
    'F1 preserves source, measurement, order and explicit deferred ladder',
    () {
      for (final source in Ai1SleepSource.values) {
        final protocol = Ai1Protocol.draft(sleepSource: source);
        final json = Ai5FeatureManifest.sleepOnly(protocol: protocol).toJson();
        expect(json['sleepSource'], source.name);
        expect(json['featureOrder'], ['main_sleep_duration_hours']);
        expect((json['features'] as List).single['unit'], 'hours');
        expect(json['comparisonPartition'], 'development_only');
        expect(json['realDataUseAuthorized'], isFalse);
        expect(json['sameOutcomeWindowFeaturesAllowed'], isFalse);
        expect((json['ladder'] as List).length, 6);
      }
    },
  );

  test(
    'F2 through F6 cannot be promoted to implemented by changing labels',
    () {
      for (final experiment in Ai5Experiment.values.skip(1)) {
        expect(
          () => Ai5FeatureManifest(
            protocol: _protocol,
            experiment: experiment,
            features: [_feature()],
          ),
          throwsUnsupportedError,
        );
      }
    },
  );

  test(
    'unknown units, outcome features and incompatible timing are rejected',
    () {
      for (final feature in [
        _feature(unit: 'minutes'),
        _feature(id: 'same_evening_energy'),
        _feature(id: 'same_evening_fatigue'),
        _feature(source: Ai1SleepSource.appleHealth),
        _feature(observationRule: 'same_outcome_window'),
        _feature(availabilityRule: 'current_record_even_if_uploaded_late'),
      ]) {
        expect(
          () => Ai5FeatureManifest(
            protocol: _protocol,
            experiment: Ai5Experiment.f1,
            features: [feature],
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test('missing/duplicate features and final-test feature selection fail', () {
    for (final features in <List<Ai5FeatureDefinition>>[
      [],
      [_feature(), _feature()],
    ]) {
      expect(
        () => Ai5FeatureManifest(
          protocol: _protocol,
          experiment: Ai5Experiment.f1,
          features: features,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => Ai5FeatureManifest(
        protocol: _protocol,
        experiment: Ai5Experiment.f1,
        features: [_feature()],
        comparisonPartition: 'final_test',
      ),
      throwsArgumentError,
    );
    expect(
      () => Ai5FeatureManifest(
        protocol: _protocol,
        experiment: Ai5Experiment.f1,
        features: [_feature()],
        preprocessing: 'fit_on_all_supplied_rows',
      ),
      throwsArgumentError,
    );
  });

  test('feature list is copied and cannot change after validation', () {
    final source = [_feature()];
    final manifest = Ai5FeatureManifest(
      protocol: _protocol,
      experiment: Ai5Experiment.f1,
      features: source,
    );
    source.clear();
    expect(manifest.features, hasLength(1));
    expect(() => manifest.features.clear(), throwsUnsupportedError);
  });

  test(
    'observation, durable receipt and window end must all precede cutoff',
    () {
      final manifest = Ai5FeatureManifest.sleepOnly(protocol: _protocol);
      final cutoff = DateTime.utc(2026, 1, 1, 10);
      void validate({
        DateTime? observedAt,
        DateTime? availableAt,
        DateTime? historyWindowEnd,
        String featureId = Ai5FeatureManifest.sleepFeatureId,
        String unit = 'hours',
        Ai1SleepSource source = Ai1SleepSource.manual,
        double value = 7,
      }) => manifest.validateObservation(
        featureId: featureId,
        unit: unit,
        source: source,
        value: value,
        observedAt: observedAt ?? cutoff,
        availableAt: availableAt ?? cutoff,
        historyWindowEnd: historyWindowEnd ?? cutoff,
        cutoff: cutoff,
      );
      validate();
      final late = cutoff.add(const Duration(microseconds: 1));
      expect(() => validate(observedAt: late), throwsArgumentError);
      expect(() => validate(availableAt: late), throwsArgumentError);
      expect(() => validate(historyWindowEnd: late), throwsArgumentError);
      expect(() => validate(unit: 'minutes'), throwsArgumentError);
      expect(() => validate(featureId: 'energy'), throwsArgumentError);
      expect(
        () => validate(source: Ai1SleepSource.appleHealth),
        throwsArgumentError,
      );
      expect(() => validate(value: double.nan), throwsArgumentError);
      expect(() => validate(value: double.infinity), throwsArgumentError);
      expect(() => validate(value: 0.49), throwsArgumentError);
      expect(() => validate(value: 16.01), throwsArgumentError);
      expect(
        () =>
            validate(availableAt: cutoff.subtract(const Duration(seconds: 1))),
        throwsArgumentError,
      );
    },
  );

  test(
    'preparation has explicit missing records and no execution permission',
    () {
      final report = AiPredataGate.assess(
        settings: AiPredataSettings.preparation(protocol: _protocol),
        evidence: const [],
      );
      final json = report.toJson();
      expect(json['incompleteRequirementCount'], 15);
      expect(json['asOf'], isNull);
      expect(report.realDataFittingAllowed, isFalse);
      expect(report.appModelReleaseAllowed, isFalse);
      expect(json['realDataUseAuthorized'], isFalse);
      expect(json['ordinaryPersonalAppEntryChanged'], isFalse);
      for (final row in json['requirements'] as List) {
        expect(row['declaredStatus'], 'notSupplied');
        expect(row['blockers'], [
          'decision_version_not_defined',
          'evidence_not_supplied',
        ]);
      }
    },
  );

  test('synthetic success cannot satisfy empirical or review requirements', () {
    final report = AiPredataGate.assess(
      settings: _settings(),
      evidence: [
        for (final requirement in AiPredataRequirement.values)
          _evidence(
            requirement,
            status: AiPredataEvidenceStatus.syntheticOnly,
            kind: AiPredataEvidenceKind.syntheticSoftware,
          ),
      ],
      asOf: _asOf,
    ).toJson();
    expect(report['incompleteRequirementCount'], 15);
    for (final row in report['requirements'] as List) {
      expect(
        row['blockers'],
        contains('synthetic_evidence_does_not_establish_real_readiness'),
      );
    }
  });

  test('complete declared records still cannot unlock fitting or release', () {
    final report = AiPredataGate.assess(
      settings: _settings(),
      evidence: AiPredataRequirement.values.map(_evidence),
      asOf: _asOf,
    ).toJson();
    expect(report['incompleteRequirementCount'], 0);
    expect(report['evidenceAuthenticityVerified'], isFalse);
    expect(report['realDataUseAuthorized'], isFalse);
    expect(report['realDataFittingAllowed'], isFalse);
    expect(report['appModelReleaseAllowed'], isFalse);
    expect(report['executionBlockers'], [
      'real_data_execution_and_release_not_implemented',
    ]);
  });

  test(
    'evidence for another protocol, experiment or decision cannot transfer',
    () {
      const id = AiPredataRequirement.measurementDefinition;
      for (final evidence in [
        _evidence(id, experimentId: 'other-experiment'),
        _evidence(
          id,
          protocolId: Ai1Protocol.draft(
            sleepSource: Ai1SleepSource.appleHealth,
          ).id,
        ),
        _evidence(id, decisionVersion: 'earlier-version'),
      ]) {
        final row = _row(
          AiPredataGate.assess(
            settings: _settings(),
            evidence: [evidence],
            asOf: _asOf,
          ).toJson(),
          id,
        );
        expect(row['recordCompleteForDeclaredScope'], isFalse);
        expect(row['blockers'], isNotEmpty);
      }
    },
  );

  test('a review note cannot substitute for empirical/device evidence', () {
    for (final id in [
      AiPredataRequirement.realDataReadiness,
      AiPredataRequirement.frozenEvaluation,
      AiPredataRequirement.prospectiveShadowEvaluation,
      AiPredataRequirement.physicalDeviceAcceptance,
    ]) {
      final row = _row(
        AiPredataGate.assess(
          settings: _settings(),
          evidence: [_evidence(id, kind: AiPredataEvidenceKind.reviewRecord)],
          asOf: _asOf,
        ).toJson(),
        id,
      );
      expect(
        row['blockers'],
        contains('evidence_kind_does_not_satisfy_requirement'),
      );
    }
  });

  test(
    'review metadata, dates and pending/rejected decisions remain explicit',
    () {
      const id = AiPredataRequirement.measurementDefinition;
      for (final evidence in [
        _evidence(id, reference: ''),
        _evidence(id, reviewer: null),
        _evidence(id, reviewedAt: _asOf.add(const Duration(seconds: 1))),
        _evidence(id, status: AiPredataEvidenceStatus.pendingReview),
        _evidence(id, status: AiPredataEvidenceStatus.rejected),
        _evidence(id, kind: AiPredataEvidenceKind.syntheticSoftware),
      ]) {
        final row = _row(
          AiPredataGate.assess(
            settings: _settings(),
            evidence: [evidence],
            asOf: _asOf,
          ).toJson(),
          id,
        );
        expect(row['recordCompleteForDeclaredScope'], isFalse);
      }
      final noTime = _row(
        AiPredataGate.assess(
          settings: _settings(),
          evidence: [_evidence(id)],
        ).toJson(),
        id,
      );
      expect(
        noTime['blockers'],
        contains('review_not_verifiable_at_assessment_time'),
      );
    },
  );

  test('duplicate decisions fail instead of choosing a favorable review', () {
    final evidence = _evidence(AiPredataRequirement.measurementDefinition);
    expect(
      () => AiPredataGate.assess(
        settings: _settings(),
        evidence: [evidence, evidence],
        asOf: _asOf,
      ),
      throwsArgumentError,
    );
  });

  test(
    'settings reject scope mismatch/blank versions and freeze mutable input',
    () {
      final versions = {AiPredataRequirement.measurementDefinition: 'v1'};
      final settings = _settings(versions: versions);
      versions.clear();
      expect(settings.decisionVersions, hasLength(1));
      expect(() => settings.decisionVersions.clear(), throwsUnsupportedError);
      expect(
        () => _settings(
          versions: {AiPredataRequirement.measurementDefinition: ''},
        ),
        throwsArgumentError,
      );
      expect(
        () => AiPredataSettings(
          protocol: _protocol,
          experimentId: 'test',
          features: Ai5FeatureManifest.sleepOnly(
            protocol: Ai1Protocol.draft(
              sleepSource: Ai1SleepSource.appleHealth,
            ),
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test('report output mutation cannot alter the saved assessment', () {
    final report = AiPredataGate.assess(
      settings: AiPredataSettings.preparation(protocol: _protocol),
      evidence: const [],
    );
    final changed = report.toJson();
    changed['realDataFittingAllowed'] = true;
    (changed['requirements'] as List).clear();
    expect(report.toJson()['realDataFittingAllowed'], isFalse);
    expect(report.toJson()['requirements'], hasLength(15));
  });
}
