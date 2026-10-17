import 'dart:convert';

import 'ai1_protocol.dart';

enum Ai5Experiment { f1, f2, f3, f4, f5, f6 }

/// A fixed feature contract, not an instruction to collect more observations.
class Ai5FeatureDefinition {
  const Ai5FeatureDefinition({
    required this.id,
    required this.unit,
    required this.source,
    required this.selectionVersion,
    required this.observationRule,
    required this.availabilityRule,
  });

  final String id;
  final String unit;
  final Ai1SleepSource source;
  final String selectionVersion;
  final String observationRule;
  final String availabilityRule;

  Map<String, Object?> toJson() => {
    'id': id,
    'unit': unit,
    'source': source.name,
    'selectionVersion': selectionVersion,
    'observationRule': observationRule,
    'availabilityRule': availabilityRule,
  };
}

/// Only F1 has an implemented feature definition. Later ladder entries cannot
/// become executable merely by changing a label or supplying arbitrary units.
class Ai5FeatureManifest {
  Ai5FeatureManifest({
    required this.protocol,
    required this.experiment,
    required Iterable<Ai5FeatureDefinition> features,
    this.comparisonPartition = 'development_only',
    this.preprocessing = 'identity_no_fitted_transform',
  }) : features = List.unmodifiable(features) {
    if (experiment != Ai5Experiment.f1) {
      throw UnsupportedError('F2–F6 feature definitions are not implemented.');
    }
    if (comparisonPartition != 'development_only' ||
        preprocessing != 'identity_no_fitted_transform') {
      throw ArgumentError('Unreviewed feature comparison or preprocessing.');
    }
    if (this.features.length != 1) {
      throw ArgumentError('F1 requires exactly one ordered sleep feature.');
    }
    final feature = this.features.single;
    if (feature.id != sleepFeatureId ||
        feature.unit != 'hours' ||
        feature.source != protocol.sleepSource ||
        feature.selectionVersion != sleepSelectionVersion ||
        feature.observationRule != sleepObservationRule ||
        feature.availabilityRule != localAvailabilityRule) {
      throw ArgumentError('Incompatible F1 feature identity, unit or timing.');
    }
  }

  factory Ai5FeatureManifest.sleepOnly({required Ai1Protocol protocol}) =>
      Ai5FeatureManifest(
        protocol: protocol,
        experiment: Ai5Experiment.f1,
        features: [
          Ai5FeatureDefinition(
            id: sleepFeatureId,
            unit: 'hours',
            source: protocol.sleepSource,
            selectionVersion: sleepSelectionVersion,
            observationRule: sleepObservationRule,
            availabilityRule: localAvailabilityRule,
          ),
        ],
      );

  static const schemaVersion = 'ai5-feature-manifest-v1';
  static const sleepFeatureId = 'main_sleep_duration_hours';
  static const sleepSelectionVersion = 'tonyo-study-sleep-v1';
  static const sleepObservationRule =
      'main_sleep_ends_on_opportunity_date_at_or_before_cutoff';
  static const localAvailabilityRule =
      'durably_available_on_issuing_device_at_or_before_cutoff';

  final Ai1Protocol protocol;
  final Ai5Experiment experiment;
  final List<Ai5FeatureDefinition> features;
  final String comparisonPartition;
  final String preprocessing;

  /// Validates fixture metadata only. This does not establish the provenance of
  /// caller-supplied timestamps or replace AI-1 source/revision eligibility.
  void validateObservation({
    required String featureId,
    required String unit,
    required Ai1SleepSource source,
    required double value,
    required DateTime observedAt,
    required DateTime availableAt,
    required DateTime historyWindowEnd,
    required DateTime cutoff,
  }) {
    final feature = features.single;
    if (featureId != feature.id ||
        unit != feature.unit ||
        source != feature.source) {
      throw ArgumentError('Observation does not match the frozen feature.');
    }
    if (!value.isFinite || value < 0.5 || value > 16) {
      throw ArgumentError('Sleep value fails the existing software bounds.');
    }
    if (observedAt.isAfter(cutoff) ||
        availableAt.isAfter(cutoff) ||
        historyWindowEnd.isAfter(cutoff) ||
        availableAt.isBefore(observedAt) ||
        historyWindowEnd.isBefore(observedAt)) {
      throw ArgumentError('Feature evidence extends beyond its allowed past.');
    }
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'experiment': experiment.name.toUpperCase(),
    'protocolId': protocol.id,
    'protocolVersion': protocol.version,
    'measurement': jsonDecode(protocol.measurement),
    'sleepSource': protocol.sleepSource.name,
    'featureOrder': features.map((feature) => feature.id).toList(),
    'features': features.map((feature) => feature.toJson()).toList(),
    'comparisonPartition': comparisonPartition,
    'preprocessing': preprocessing,
    'missingFeaturePolicy': 'abstain_no_imputation_or_source_fallback',
    'target': 'raw_evening_energy_1_through_10',
    'sameOutcomeWindowFeaturesAllowed': false,
    'realDataUseAuthorized': false,
    'ladder': [
      {'experiment': 'F1', 'status': 'implemented_synthetic_sleep_only'},
      for (final id in ['F2', 'F3'])
        {
          'experiment': id,
          'status': 'not_implemented_requires_definition_and_review',
        },
      for (final id in ['F4', 'F5', 'F6'])
        {'experiment': id, 'status': 'optional_deferred_not_implemented'},
    ],
  };
}

enum AiPredataRequirement {
  measurementDefinition,
  populationAndDataUse,
  sourceTimingAndRevisionPolicy,
  privacyRetentionAndWithdrawal,
  studySizeAndPrecision,
  realDataReadiness,
  chronologicalSplitAndBaselines,
  featureDefinitions,
  metricsAndPromotionCriteria,
  uncertaintyMethod,
  physicalDeviceAcceptance,
  frozenEvaluation,
  prospectiveShadowEvaluation,
  artifactMigrationAndRollback,
  releaseAndMonitoringDecision,
}

enum AiPredataEvidenceStatus {
  pendingReview,
  syntheticOnly,
  acceptedForDeclaredScope,
  rejected,
}

enum AiPredataEvidenceKind {
  reviewRecord,
  syntheticSoftware,
  prospectiveDataAssessment,
  physicalDeviceObservation,
}

/// Declared evidence is audited for completeness and scope; its truth is not
/// authenticated by this library and it never unlocks app behavior or fitting.
class AiPredataEvidence {
  const AiPredataEvidence({
    required this.requirement,
    required this.status,
    required this.kind,
    required this.experimentId,
    required this.protocolId,
    required this.decisionVersion,
    required this.reference,
    this.reviewer,
    this.reviewedAt,
  });

  final AiPredataRequirement requirement;
  final AiPredataEvidenceStatus status;
  final AiPredataEvidenceKind kind;
  final String experimentId;
  final String protocolId;
  final String decisionVersion;
  final String reference;
  final String? reviewer;
  final DateTime? reviewedAt;
}

class AiPredataSettings {
  AiPredataSettings({
    required this.protocol,
    required this.experimentId,
    required this.features,
    Map<AiPredataRequirement, String> decisionVersions = const {},
  }) : decisionVersions = Map.unmodifiable(decisionVersions) {
    if (experimentId.trim().isEmpty ||
        features.protocol.id != protocol.id ||
        features.protocol.measurement != protocol.measurement ||
        this.decisionVersions.values.any((version) => version.trim().isEmpty)) {
      throw ArgumentError('Settings must have consistent, nonempty scope.');
    }
  }

  factory AiPredataSettings.preparation({required Ai1Protocol protocol}) =>
      AiPredataSettings(
        protocol: protocol,
        experimentId: 'tonyo-pre-data-preparation-v1',
        features: Ai5FeatureManifest.sleepOnly(protocol: protocol),
      );

  final Ai1Protocol protocol;
  final String experimentId;
  final Ai5FeatureManifest features;

  /// Exact versions of substantive decisions, not checkbox defaults. The
  /// preparation factory intentionally supplies none of these missing records.
  final Map<AiPredataRequirement, String> decisionVersions;
}

class AiPredataGateReport {
  AiPredataGateReport._(Map<String, Object?> data)
    : _json = ai1CanonicalJson(data);

  final String _json;

  Map<String, dynamic> toJson() => jsonDecode(_json) as Map<String, dynamic>;

  bool get realDataFittingAllowed => false;
  bool get appModelReleaseAllowed => false;
}

/// An offline preparation audit, never an authorization service. Ordinary
/// personal app entry is unchanged; this reports experiment/release evidence.
abstract final class AiPredataGate {
  static AiPredataGateReport assess({
    required AiPredataSettings settings,
    required Iterable<AiPredataEvidence> evidence,
    DateTime? asOf,
  }) {
    final byRequirement = <AiPredataRequirement, AiPredataEvidence>{};
    for (final item in evidence) {
      if (byRequirement.containsKey(item.requirement)) {
        throw ArgumentError('Conflicting or duplicate review evidence.');
      }
      byRequirement[item.requirement] = item;
    }
    final rows = <Map<String, Object?>>[];
    for (final requirement in AiPredataRequirement.values) {
      final item = byRequirement[requirement];
      final expectedVersion = settings.decisionVersions[requirement];
      final blockers = <String>[];
      if (expectedVersion == null) blockers.add('decision_version_not_defined');
      if (item == null) {
        blockers.add('evidence_not_supplied');
      } else {
        if (item.experimentId != settings.experimentId ||
            item.protocolId != settings.protocol.id) {
          blockers.add('evidence_scope_mismatch');
        }
        if (item.decisionVersion.trim().isEmpty ||
            item.decisionVersion != expectedVersion) {
          blockers.add('decision_version_mismatch');
        }
        if (item.reference.trim().isEmpty) {
          blockers.add('evidence_reference_missing');
        }
        if (item.kind == AiPredataEvidenceKind.syntheticSoftware ||
            item.status == AiPredataEvidenceStatus.syntheticOnly) {
          blockers.add('synthetic_evidence_does_not_establish_real_readiness');
        }
        if (item.status != AiPredataEvidenceStatus.acceptedForDeclaredScope) {
          blockers.add('review_not_accepted_for_declared_scope');
        } else {
          if (item.reviewer == null || item.reviewer!.trim().isEmpty) {
            blockers.add('reviewer_not_recorded');
          }
          if (item.reviewedAt == null) {
            blockers.add('review_date_not_recorded');
          } else if (asOf == null || item.reviewedAt!.isAfter(asOf)) {
            blockers.add('review_not_verifiable_at_assessment_time');
          }
          if (item.kind != _requiredKind(requirement)) {
            blockers.add('evidence_kind_does_not_satisfy_requirement');
          }
        }
      }
      rows.add({
        'requirement': requirement.name,
        'expectedDecisionVersion': expectedVersion,
        'declaredStatus': item?.status.name ?? 'notSupplied',
        'evidenceKind': item?.kind.name,
        'reference': item?.reference,
        'reviewer': item?.reviewer,
        'reviewedAt': item?.reviewedAt?.toUtc().toIso8601String(),
        'recordCompleteForDeclaredScope': blockers.isEmpty,
        'blockers': blockers,
      });
    }
    return AiPredataGateReport._({
      'schemaVersion': 'ai-predata-evidence-audit-v1',
      'experimentId': settings.experimentId,
      'protocolId': settings.protocol.id,
      'protocolVersion': settings.protocol.version,
      'measurement': jsonDecode(settings.protocol.measurement),
      'asOf': asOf?.toUtc().toIso8601String(),
      'featureManifest': settings.features.toJson(),
      'requirements': rows,
      'incompleteRequirementCount': rows
          .where((row) => row['recordCompleteForDeclaredScope'] != true)
          .length,
      'realDataUseAuthorized': false,
      'realDataFittingAllowed': false,
      'appModelReleaseAllowed': false,
      'authorizationPolicy': 'audit_only_no_permission_or_unlock_path',
      'ordinaryPersonalAppEntryChanged': false,
      'evidenceAuthenticityVerified': false,
      'executionBlockers': ['real_data_execution_and_release_not_implemented'],
      'interpretation':
          'Records describe supplied evidence, not independently verified '
          'approvals. Synthetic success and complete declarations never grant '
          'data-use permission, fitting or model release. No ordinary personal '
          'app entry restriction is added.',
    });
  }

  static AiPredataEvidenceKind _requiredKind(
    AiPredataRequirement requirement,
  ) => switch (requirement) {
    AiPredataRequirement.realDataReadiness ||
    AiPredataRequirement.frozenEvaluation ||
    AiPredataRequirement.prospectiveShadowEvaluation =>
      AiPredataEvidenceKind.prospectiveDataAssessment,
    AiPredataRequirement.physicalDeviceAcceptance =>
      AiPredataEvidenceKind.physicalDeviceObservation,
    _ => AiPredataEvidenceKind.reviewRecord,
  };
}
