import 'dart:convert';

import 'ai1_dataset_builder.dart';
import 'ai1_protocol.dart';
import 'ai1_records.dart';
import 'ai_experiment_evidence.dart';

/// Fixed software-fixture choices, not an approved real-data experiment.
/// Boundaries select opportunities by their morning UTC cutoff, not row order.
class Ai3SyntheticManifest {
  Ai3SyntheticManifest({
    required this.protocol,
    required this.experimentId,
    required this.datasetVersion,
    required DateTime historyStart,
    required DateTime evaluationStart,
    required DateTime evaluationEnd,
    required DateTime analysisAsOf,
  }) : historyStart = historyStart.toUtc(),
       evaluationStart = evaluationStart.toUtc(),
       evaluationEnd = evaluationEnd.toUtc(),
       analysisAsOf = analysisAsOf.toUtc() {
    if (experimentId.trim().isEmpty || datasetVersion.trim().isEmpty) {
      throw ArgumentError(
        'Experiment and fixture dataset versions are required.',
      );
    }
    if (this.historyStart.isAfter(this.evaluationStart) ||
        !this.evaluationStart.isBefore(this.evaluationEnd) ||
        this.analysisAsOf.isBefore(this.evaluationEnd)) {
      throw ArgumentError('Invalid chronological experiment boundaries.');
    }
  }

  static const version = 'ai3-synthetic-expanding-personal-v1';
  static const sleepSumSquaresTolerance = 1e-12;
  final Ai1Protocol protocol;
  final String experimentId;
  final String datasetVersion;
  final DateTime historyStart;
  final DateTime evaluationStart;
  final DateTime evaluationEnd;
  final DateTime analysisAsOf;

  Map<String, Object?> toJson() => {
    'schemaVersion': version,
    'experimentId': experimentId,
    'datasetVersion': datasetVersion,
    'protocolId': protocol.id,
    'protocolVersion': protocol.version,
    'sleepSource': protocol.sleepSource.name,
    'measurement': jsonDecode(protocol.measurement),
    'historyStart': historyStart.toIso8601String(),
    'evaluationStart': evaluationStart.toIso8601String(),
    'evaluationEnd': evaluationEnd.toIso8601String(),
    'analysisAsOf': analysisAsOf.toIso8601String(),
    'intervalRule': 'morning_cutoff_start_inclusive_end_exclusive',
    'evidenceKind': 'synthetic_software_fixture',
    'updatePolicy': 'expanding_personal_history_rebuilt_at_each_cutoff',
    'historyRule': 'closed_prior_windows_with_outcomes_available_by_cutoff',
    'erasureRule': 'withdrawal_and_tombstones_apply_to_all_replays',
    'candidateIds': ['B0', 'B1', 'M1'],
    'candidates': {
      'B0': 'mean_of_eligible_prior_personal_evening_outcomes',
      'B1': 'latest_eligible_prior_personal_evening_outcome',
      'M1': 'personal_sleep_only_centered_ordinary_least_squares',
    },
    'historyOrdering': [
      'outcome_observed_at',
      'initial_saved_at',
      'opportunity_id',
    ],
    'minimumBaselineObservations': 1,
    'minimumRegressionPairs': 2,
    'sleepCenteredSumSquaresTolerance': sleepSumSquaresTolerance,
    'minimumsInterpretation': 'mathematical_conditions_not_study_sufficiency',
    'regressionFeatures': ['main_sleep_duration_hours'],
    'intercept': 'fitted',
    'slopeConstraint': 'none',
    'populationFallback': 'none',
    'missingTargetPolicy': 'exclude_from_scoring_never_impute',
    'outputRule': 'clip_to_1_through_10_retain_raw_do_not_round',
    'tuningBudget': 0,
    'finalHoldout': false,
    'realDataTrainingAllowed': false,
    'appModelActivationAllowed': false,
  };
}

/// Pure, explicit synthetic replay. It has no file loader, capture adapter,
/// model repository or production entry point. Relabeling real records as
/// fixtures is outside this API's contract and never grants training permission.
abstract final class Ai3ComparisonRunner {
  static Ai3ComparisonReport runSynthetic({
    required Ai3SyntheticManifest manifest,
    required Iterable<Ai1FixtureDay> days,
  }) {
    final supplied = days.toList(growable: false);
    final zones = <String, String>{};
    for (final day in supplied) {
      if (!day.synthetic) {
        throw ArgumentError('AI-3 preparation accepts invented fixtures only.');
      }
      final opportunity = day.opportunity;
      if (opportunity.cutoff.isBefore(manifest.historyStart) ||
          !opportunity.cutoff.isBefore(manifest.evaluationEnd)) {
        throw ArgumentError(
          'Every supplied opportunity must be in the manifest interval.',
        );
      }
      final previousZone = zones[opportunity.participantKey];
      if (previousZone != null && previousZone != opportunity.timezone) {
        throw ArgumentError(
          'One participant must retain one planned timezone.',
        );
      }
      zones[opportunity.participantKey] = opportunity.timezone;
    }

    // Validate exact duplicate/conflicting evidence and final-window closure
    // through AI-1 before deduplicating. A final report is used ONLY for scoring.
    final finalDataset = Ai1DatasetBuilder.buildSynthetic(
      protocol: manifest.protocol,
      days: supplied,
      asOf: manifest.analysisAsOf,
      datasetVersion: manifest.datasetVersion,
    );
    final byId = {for (final day in supplied) day.opportunity.id: day};
    final ordered = byId.values.toList()..sort(_compareDays);
    final finalRows = {
      for (final row in finalDataset.rows) row.opportunity.id: row,
    };
    final rows = <Map<String, dynamic>>[];
    for (final day in ordered) {
      final opportunity = day.opportunity;
      if (opportunity.cutoff.isBefore(manifest.evaluationStart)) continue;
      final execution = AiExperimentEvidence.executionStatus(day);
      final finalRow = finalRows[opportunity.id]!;
      final target = AiExperimentEvidence.target(day, finalRow);

      // This separate as-of build is essential: a revision made tomorrow must
      // not retrospectively change which label was available this morning.
      final priorDays = ordered.where(
        (prior) =>
            prior.opportunity.participantKey == opportunity.participantKey &&
            prior.opportunity.cutoff.isBefore(opportunity.cutoff) &&
            !prior.opportunity.outcomeEnd.isAfter(opportunity.cutoff),
      );
      final history = Ai1DatasetBuilder.buildSynthetic(
        protocol: manifest.protocol,
        days: priorDays,
        asOf: opportunity.cutoff,
        datasetVersion: manifest.datasetVersion,
      );
      final outcomes =
          history.rows
              .where(
                (prior) =>
                    AiExperimentEvidence.target(
                      byId[prior.opportunity.id]!,
                      prior,
                    ).status ==
                    'matched',
              )
              .toList()
            ..sort(_compareOutcomes);
      final pairs = outcomes
          .where(
            (prior) =>
                prior.hasPair &&
                AiExperimentEvidence.executionStatus(
                      byId[prior.opportunity.id]!,
                    ) ==
                    'executed',
          )
          .toList();
      final methods = <String, _Prediction>{};
      if (execution != 'executed') {
        for (final id in _candidateIds) {
          methods[id] = _Prediction.absent('no_execution');
        }
      } else {
        methods['B0'] = outcomes.isEmpty
            ? _Prediction.absent('no_personal_history')
            : _Prediction.value(
                _mean(outcomes.map((row) => row.energy!.toDouble())),
                outcomes,
              );
        methods['B1'] = outcomes.isEmpty
            ? _Prediction.absent('no_personal_history')
            : _Prediction.value(outcomes.last.energy!.toDouble(), [
                outcomes.last,
              ]);
        methods['M1'] = _regression(finalRow.feature, pairs);
      }
      rows.add({
        'opportunityId': opportunity.id,
        'participantKey': opportunity.participantKey,
        'localDate': opportunity.localDate,
        'timezone': opportunity.timezone,
        'cutoff': opportunity.cutoff.toIso8601String(),
        'executedAt': day.issuedAt?.toIso8601String(),
        'durableAt': day.durableAt?.toIso8601String(),
        'executionStatus': execution,
        'sleepStatus': finalRow.sleepStatus,
        'outcomeStatus': target.status,
        'energy': target.energy,
        'methods': {
          for (final id in _candidateIds)
            id: methods[id]!.toJson(target.energy),
        },
      });
    }

    final active = rows
        .where((row) => row['executionStatus'] != 'withdrawn')
        .toList();
    final summaries = <String, dynamic>{};
    final participantKeys =
        active.map((row) => row['participantKey'] as String).toSet().toList()
          ..sort();
    for (final id in _candidateIds) {
      final participants = [
        for (final key in participantKeys)
          {
            'participantKey': key,
            ..._metrics(
              active.where((row) => row['participantKey'] == key).toList(),
              id,
            ),
          },
      ];
      final participantErrors = participants
          .map((row) => row['mae'])
          .whereType<double>()
          .toList();
      summaries[id] = {
        ..._metrics(active, id),
        'perParticipant': participants,
        'participantsScored': participantErrors.length,
        'macroParticipantMae': participantErrors.isEmpty
            ? null
            : _mean(participantErrors),
      };
    }
    final pairwise = <Map<String, dynamic>>[];
    for (var left = 0; left < _candidateIds.length; left++) {
      for (var right = left + 1; right < _candidateIds.length; right++) {
        final leftId = _candidateIds[left];
        final rightId = _candidateIds[right];
        final common = active
            .where(
              (row) =>
                  row['methods'][leftId]['scored'] == true &&
                  row['methods'][rightId]['scored'] == true,
            )
            .toList();
        final leftMae = _metrics(common, leftId)['mae'] as double?;
        final rightMae = _metrics(common, rightId)['mae'] as double?;
        pairwise.add({
          'left': leftId,
          'right': rightId,
          'commonScored': common.length,
          'opportunityIds': [for (final row in common) row['opportunityId']],
          'leftMae': leftMae,
          'rightMae': rightMae,
          'maeDifference': leftMae == null || rightMae == null
              ? null
              : leftMae - rightMae,
        });
      }
    }
    final commonAll = active
        .where(
          (row) =>
              _candidateIds.every((id) => row['methods'][id]['scored'] == true),
        )
        .toList();
    return Ai3ComparisonReport._({
      'schemaVersion': 'ai3-synthetic-comparison-v1',
      'evidenceKind': 'synthetic_software_fixture',
      'synthetic': true,
      'modelingReadinessEstablished': false,
      'realDataTrainingAllowed': false,
      'appModelActivationAllowed': false,
      'manifest': manifest.toJson(),
      'inputSnapshot': [for (final day in ordered) _inputSnapshot(day)],
      'coverage': {
        'suppliedUniqueOpportunities': ordered.length,
        'historyOnlyOpportunities': ordered.length - rows.length,
        'evaluationOpportunities': rows.length,
        'withdrawnOpportunities': rows.length - active.length,
        'activeEvaluationOpportunities': active.length,
        'participantsWithActiveOpportunities': participantKeys.length,
        'executionStatuses': _counts(
          rows.map((row) => row['executionStatus'] as String),
        ),
        'outcomeStatuses': _counts(
          rows.map((row) => row['outcomeStatus'] as String),
        ),
      },
      'methods': summaries,
      'pairwise': pairwise,
      'commonAllCandidates': {
        'scored': commonAll.length,
        'opportunityIds': [for (final row in commonAll) row['opportunityId']],
        'methods': {
          for (final id in _candidateIds) id: _metrics(commonAll, id),
        },
      },
      'rows': rows,
      'interpretation': [
        'Invented fixtures test software behavior, not real predictive accuracy.',
        'Expanding-history replay may use earlier evaluation outcomes at later cutoffs; this is not an untouched final test.',
        'Method-specific errors use different scored sets; compare methods on the explicit common sets.',
        'Signed error is prediction minus observed Energy; MAE uses clipped, unrounded predictions.',
        'Coverage uses all non-withdrawn evaluation opportunities, including missed executions and missing outcomes.',
        'No tuning, model promotion, uncertainty estimate, clinical claim or real-data authorization is supplied.',
      ],
    });
  }
}

/// A canonical, detached result: callers cannot mutate subsequent serializations.
class Ai3ComparisonReport {
  Ai3ComparisonReport._(Map<String, dynamic> value)
    : _json = ai1CanonicalJson(value);
  final String _json;
  Map<String, dynamic> toJson() => jsonDecode(_json) as Map<String, dynamic>;
}

const _candidateIds = ['B0', 'B1', 'M1'];

_Prediction _regression(Ai1SleepRevision? feature, List<Ai1DatasetRow> pairs) {
  if (feature == null) return _Prediction.absent('no_sleep_feature');
  if (pairs.length < 2) return _Prediction.absent('insufficient_pairs', pairs);
  final meanX = _mean(pairs.map((row) => row.feature!.durationHours));
  final meanY = _mean(pairs.map((row) => row.energy!.toDouble()));
  var xx = 0.0;
  var xy = 0.0;
  for (final row in pairs) {
    final dx = row.feature!.durationHours - meanX;
    xx += dx * dx;
    xy += dx * (row.energy! - meanY);
  }
  if (xx <= Ai3SyntheticManifest.sleepSumSquaresTolerance) {
    return _Prediction.absent('degenerate_sleep_variance', pairs);
  }
  final slope = xy / xx;
  final intercept = meanY - slope * meanX;
  final raw = meanY + slope * (feature.durationHours - meanX);
  if (!slope.isFinite || !intercept.isFinite || !raw.isFinite) {
    return _Prediction.absent('non_finite_fit', pairs);
  }
  return _Prediction.value(
    raw,
    pairs,
    fit: {'intercept': intercept, 'slope': slope},
  );
}

class _Prediction {
  _Prediction.absent(this.status, [this.training = const []])
    : raw = null,
      fit = null;
  _Prediction.value(double value, this.training, {this.fit})
    : raw = value,
      status = 'predicted';
  final String status;
  final double? raw;
  final List<Ai1DatasetRow> training;
  final Map<String, double>? fit;

  Map<String, dynamic> toJson(int? energy) {
    final prediction = raw?.clamp(1.0, 10.0).toDouble();
    final error = prediction == null || energy == null
        ? null
        : prediction - energy;
    return {
      'status': status,
      'rawPrediction': raw,
      'prediction': prediction,
      'trainingCount': training.length,
      'trainingOpportunityIds': [
        for (final row in training) row.opportunity.id,
      ],
      'fit': fit,
      'scored': error != null,
      'signedError': error,
      'absoluteError': error?.abs(),
    };
  }
}

Map<String, dynamic> _metrics(List<Map<String, dynamic>> rows, String id) {
  final predictions = rows
      .map((row) => row['methods'][id] as Map<String, dynamic>)
      .toList();
  final predicted = predictions
      .where((method) => method['prediction'] != null)
      .length;
  final errors = predictions
      .map((method) => method['signedError'])
      .whereType<double>()
      .toList();
  return {
    'opportunities': rows.length,
    'predicted': predicted,
    'scored': errors.length,
    'coverage': rows.isEmpty ? null : predicted / rows.length,
    'scoredCoverage': rows.isEmpty ? null : errors.length / rows.length,
    'mae': errors.isEmpty ? null : _mean(errors.map((error) => error.abs())),
    'meanSignedError': errors.isEmpty ? null : _mean(errors),
    'predictionStatuses': _counts(
      predictions.map((method) => method['status'] as String),
    ),
  };
}

double _mean(Iterable<double> values) {
  var mean = 0.0;
  var count = 0;
  for (final value in values) {
    mean += (value - mean) / ++count;
  }
  return mean;
}

int _compareDays(Ai1FixtureDay a, Ai1FixtureDay b) {
  final time = a.opportunity.cutoff.compareTo(b.opportunity.cutoff);
  return time == 0 ? a.opportunity.id.compareTo(b.opportunity.id) : time;
}

int _compareOutcomes(Ai1DatasetRow a, Ai1DatasetRow b) {
  var result = a.outcome!.observedAt.compareTo(b.outcome!.observedAt);
  if (result == 0) {
    result = a.outcome!.initialSavedAt.compareTo(b.outcome!.initialSavedAt);
  }
  return result == 0 ? a.opportunity.id.compareTo(b.opportunity.id) : result;
}

Map<String, int> _counts(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

Map<String, dynamic> _inputSnapshot(Ai1FixtureDay day) {
  List<dynamic> revisions(Iterable<String> fingerprints) {
    final ordered = fingerprints.toSet().toList()..sort();
    return ordered.map(jsonDecode).toList();
  }

  return {
    'opportunityId': day.opportunity.id,
    'participantKey': day.opportunity.participantKey,
    'protocolId': day.opportunity.protocolId,
    'localDate': day.opportunity.localDate,
    'timezone': day.opportunity.timezone,
    'dayStart': day.opportunity.dayStart.toIso8601String(),
    'cutoff': day.opportunity.cutoff.toIso8601String(),
    'issuanceDeadline': day.opportunity.issuanceDeadline.toIso8601String(),
    'outcomeStart': day.opportunity.outcomeStart.toIso8601String(),
    'outcomeEnd': day.opportunity.outcomeEnd.toIso8601String(),
    'synthetic': true,
    'withdrawn': day.withdrawn,
    'sleepHistoryComplete': day.sleepHistoryComplete,
    'responseHistoryComplete': day.responseHistoryComplete,
    'issuedAt': day.issuedAt?.toIso8601String(),
    'durableAt': day.durableAt?.toIso8601String(),
    'timezoneChanges':
        day.timezoneChanges
            .map((time) => time.toIso8601String())
            .toSet()
            .toList()
          ..sort(),
    'sleepRevisions': revisions(
      day.sleepRevisions.map((row) => row.fingerprint),
    ),
    'responseRevisions': revisions(
      day.responseRevisions.map((row) => row.fingerprint),
    ),
  };
}
