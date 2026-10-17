import 'dart:convert';

import 'ai1_dataset_builder.dart';
import 'ai1_protocol.dart';
import 'ai1_records.dart';
import 'ai_experiment_evidence.dart';
import 'ai_model_artifact.dart';

/// A synthetic split rehearsal. Candidate/output choices precede all scoring.
/// This is not a signed scientific plan or a real-data training entry point.
class Ai4FrozenManifest {
  Ai4FrozenManifest({
    required this.protocol,
    required this.experimentId,
    required this.datasetVersion,
    required DateTime historyStart,
    required DateTime fitCutoff,
    required DateTime finalStart,
    required DateTime evaluationEnd,
    required DateTime analysisAsOf,
    this.candidateId = 'M1',
    this.comparatorId = 'B0',
  }) : historyStart = historyStart.toUtc(),
       fitCutoff = fitCutoff.toUtc(),
       finalStart = finalStart.toUtc(),
       evaluationEnd = evaluationEnd.toUtc(),
       analysisAsOf = analysisAsOf.toUtc() {
    if (experimentId.trim().isEmpty ||
        datasetVersion.trim().isEmpty ||
        !historyStart.isBefore(fitCutoff) ||
        !fitCutoff.isBefore(finalStart) ||
        !finalStart.isBefore(evaluationEnd) ||
        analysisAsOf.isBefore(evaluationEnd) ||
        !_ids.contains(candidateId) ||
        !_ids.contains(comparatorId) ||
        candidateId == comparatorId) {
      throw ArgumentError('Invalid fixed synthetic experiment manifest.');
    }
  }

  final Ai1Protocol protocol;
  final String experimentId;
  final String datasetVersion;
  final DateTime historyStart;
  final DateTime fitCutoff;
  final DateTime finalStart;
  final DateTime evaluationEnd;
  final DateTime analysisAsOf;
  final String candidateId;
  final String comparatorId;

  Map<String, dynamic> toJson() => {
    'schemaVersion': 'ai4-synthetic-frozen-manifest-v1',
    'experimentId': experimentId,
    'datasetVersion': datasetVersion,
    'protocolId': protocol.id,
    'measurement': jsonDecode(protocol.measurement),
    'sleepSource': protocol.sleepSource.name,
    'historyStart': historyStart.toIso8601String(),
    'fitCutoff': fitCutoff.toIso8601String(),
    'finalStart': finalStart.toIso8601String(),
    'evaluationEnd': evaluationEnd.toIso8601String(),
    'analysisAsOf': analysisAsOf.toIso8601String(),
    'partitionRule': 'morning_cutoff_start_inclusive_end_exclusive',
    'candidateId': candidateId,
    'comparatorId': comparatorId,
    'candidateSelection': 'fixed_before_development_no_automatic_selection',
    'fittingPolicy': 'fit_personal_models_once_at_common_utc_cutoff',
    'evaluationHistoryUpdates': false,
    'baselineMeaning': 'personal_average_and_latest_rating_at_fit_cutoff',
    'outputPolicy': 'clip_1_through_10_without_rounding_retain_raw',
    'uncertaintyPolicy': 'not_estimated_pending_statistical_review',
    'evidenceKind': 'synthetic_software_fixture',
    'realDataTrainingAllowed': false,
    'modelPromotionAllowed': false,
  };
}

/// Training and development are supplied first; final observations have a
/// separate one-use entry point. Nothing in this class reads files or app data.
class Ai4FrozenExperiment {
  Ai4FrozenExperiment._(
    this.manifest,
    this._training,
    this._developmentDays,
    this._models,
    this._development,
  );

  static Ai4FrozenExperiment prepareSynthetic({
    required Ai4FrozenManifest manifest,
    required Iterable<Ai1FixtureDay> trainingDays,
    required Iterable<Ai1FixtureDay> developmentDays,
  }) {
    final training = _validateDays(
      manifest,
      trainingDays,
      manifest.historyStart,
      manifest.fitCutoff,
      manifest.fitCutoff,
    );
    final development = _validateDays(
      manifest,
      developmentDays,
      manifest.fitCutoff,
      manifest.finalStart,
      manifest.finalStart,
    );
    _validateZones([...training, ...development]);
    _assertNoTrainingErasure(training, development);
    final fit = Ai1DatasetBuilder.buildSynthetic(
      protocol: manifest.protocol,
      days: training,
      asOf: manifest.fitCutoff,
      datasetVersion: manifest.datasetVersion,
    );
    final byId = {for (final day in training) day.opportunity.id: day};
    final participants =
        training.map((day) => day.opportunity.participantKey).toSet().toList()
          ..sort();
    final models = <String, Map<String, AiModelArtifact>>{};
    for (final participant in participants) {
      final history =
          fit.rows
              .where(
                (row) =>
                    row.opportunity.participantKey == participant &&
                    AiExperimentEvidence.target(
                          byId[row.opportunity.id]!,
                          row,
                        ).status ==
                        'matched',
              )
              .toList()
            ..sort((a, b) {
              var order = a.outcome!.observedAt.compareTo(
                b.outcome!.observedAt,
              );
              if (order == 0) {
                order = a.outcome!.initialSavedAt.compareTo(
                  b.outcome!.initialSavedAt,
                );
              }
              return order == 0
                  ? a.opportunity.id.compareTo(b.opportunity.id)
                  : order;
            });
      final pairs = history
          .where(
            (row) =>
                row.hasPair &&
                AiExperimentEvidence.executionStatus(
                      byId[row.opportunity.id]!,
                    ) ==
                    'executed',
          )
          .toList();
      final perPerson = <String, AiModelArtifact>{};
      AiModelArtifact artifact(
        String id,
        List<Ai1DatasetRow> used, {
        double? constant,
        double? intercept,
        double? slope,
      }) => AiModelArtifact.synthetic(
        artifactId: ai1CanonicalJson([
          manifest.experimentId,
          participant,
          id,
          manifest.fitCutoff.toIso8601String(),
        ]),
        candidateId: id,
        protocol: manifest.protocol,
        ownerScope: ownerScope,
        participantKey: participant,
        timezone: used.first.opportunity.timezone,
        fittedAt: manifest.fitCutoff,
        dataCutoff: manifest.fitCutoff,
        trainingOpportunityIds: [for (final row in used) row.opportunity.id],
        constantPrediction: constant,
        intercept: intercept,
        slope: slope,
      );
      if (history.isNotEmpty) {
        perPerson['B0'] = artifact(
          'B0',
          history,
          constant: _mean(history.map((row) => row.energy!.toDouble())),
        );
        perPerson['B1'] = artifact('B1', [
          history.last,
        ], constant: history.last.energy!.toDouble());
      }
      if (pairs.length >= 2) {
        final x = _mean(pairs.map((row) => row.feature!.durationHours));
        final y = _mean(pairs.map((row) => row.energy!.toDouble()));
        var xx = 0.0;
        var xy = 0.0;
        for (final row in pairs) {
          final dx = row.feature!.durationHours - x;
          xx += dx * dx;
          xy += dx * (row.energy! - y);
        }
        if (xx > 1e-12) {
          final slope = xy / xx;
          final intercept = y - slope * x;
          if (slope.isFinite && intercept.isFinite) {
            perPerson['M1'] = artifact(
              'M1',
              pairs,
              intercept: intercept,
              slope: slope,
            );
          }
        }
      }
      models[participant] = Map.unmodifiable(perPerson);
    }
    final frozen = Map<String, Map<String, AiModelArtifact>>.unmodifiable(
      models,
    );
    return Ai4FrozenExperiment._(
      manifest,
      List.unmodifiable(training),
      List.unmodifiable(development),
      frozen,
      _evaluate(
        manifest,
        development,
        frozen,
        manifest.finalStart,
        'development',
      ),
    );
  }

  static const ownerScope = 'synthetic-ai4-frozen-evaluation';
  final Ai4FrozenManifest manifest;
  final List<Ai1FixtureDay> _training;
  final List<Ai1FixtureDay> _developmentDays;
  final Map<String, Map<String, AiModelArtifact>> _models;
  final Map<String, dynamic> _development;
  bool _finalOpened = false;
  bool _invalidated = false;

  Map<String, Map<String, AiModelArtifact>> get artifacts => _models;
  bool get finalOpened => _finalOpened;
  Map<String, dynamic> get developmentReport => _copy(_development);

  /// Upstream source erasure invalidates a frozen fit; it never silently refits.
  void invalidate() => _invalidated = true;

  Map<String, dynamic> openSyntheticFinal({
    required Iterable<Ai1FixtureDay> days,
  }) {
    if (_invalidated) {
      throw StateError('Frozen training evidence was invalidated.');
    }
    if (_finalOpened) {
      throw StateError(
        'Final partition already opened; start a new versioned experiment after redesign.',
      );
    }
    final finalDays = _validateDays(
      manifest,
      days,
      manifest.finalStart,
      manifest.evaluationEnd,
      manifest.analysisAsOf,
    );
    _validateZones([..._training, ..._developmentDays, ...finalDays]);
    try {
      _assertNoTrainingErasure(_training, finalDays);
    } on StateError {
      _invalidated = true;
      rethrow;
    }
    final evaluated = _evaluate(
      manifest,
      finalDays,
      _models,
      manifest.analysisAsOf,
      'final',
    );
    _finalOpened = true;
    return _copy({
      'schemaVersion': 'ai4-synthetic-frozen-evaluation-v1',
      'evidenceKind': 'synthetic_software_fixture',
      'manifest': manifest.toJson(),
      'trainingOpportunityIds': [
        for (final day in _training) day.opportunity.id,
      ],
      'trainingEvidence': Ai1DatasetBuilder.buildSynthetic(
        protocol: manifest.protocol,
        days: _training,
        asOf: manifest.fitCutoff,
        datasetVersion: manifest.datasetVersion,
      ).toJson(),
      'artifacts': {
        for (final person in _models.entries)
          person.key: {
            for (final model in person.value.entries)
              model.key: model.value.toJson(),
          },
      },
      'development': _development,
      'final': evaluated,
      'finalPartitionOpened': true,
      'finalAccessBoundary':
          'one_use_per_in_memory_experiment_not_attestation_of_human_blinding',
      'decision': 'blocked_no_empirical_evidence',
      'modelPromotionAllowed': false,
      'realDataTrainingAllowed': false,
      'uncertainty': {
        'status': 'not_estimated_pending_statistical_review',
        'reason':
            'Do not treat correlated daily errors as independent observations.',
        'pairedErrorSeriesAvailable': true,
      },
    });
  }
}

const _ids = ['B0', 'B1', 'M1'];

void _assertNoTrainingErasure(
  List<Ai1FixtureDay> training,
  List<Ai1FixtureDay> later,
) {
  final dependencies = <String>{
    for (final day in training) ...[
      for (final row in day.responseRevisions)
        ai1CanonicalJson(['response', row.participantKey, row.sourceId]),
      for (final row in day.sleepRevisions)
        ai1CanonicalJson(['sleep', row.participantKey, row.key]),
    ],
  };
  for (final day in later) {
    final erased = [
      for (final row in day.responseRevisions.where((row) => row.deleted))
        ai1CanonicalJson(['response', row.participantKey, row.sourceId]),
      for (final row in day.sleepRevisions.where((row) => row.deleted))
        ai1CanonicalJson(['sleep', row.participantKey, row.key]),
    ];
    if (erased.any(dependencies.contains)) {
      throw StateError(
        'Supplied tombstone invalidates frozen training evidence.',
      );
    }
  }
}

Map<String, dynamic> _evaluate(
  Ai4FrozenManifest manifest,
  List<Ai1FixtureDay> days,
  Map<String, Map<String, AiModelArtifact>> models,
  DateTime asOf,
  String partition,
) {
  final dataset = Ai1DatasetBuilder.buildSynthetic(
    protocol: manifest.protocol,
    days: days,
    asOf: asOf,
    datasetVersion: manifest.datasetVersion,
  );
  final byId = {for (final row in dataset.rows) row.opportunity.id: row};
  final rows = <Map<String, dynamic>>[];
  for (final day in days) {
    final opportunity = day.opportunity;
    final row = byId[opportunity.id]!;
    final execution = AiExperimentEvidence.executionStatus(day);
    final target = AiExperimentEvidence.target(day, row);
    final methods = <String, dynamic>{};
    for (final id in _ids) {
      final artifact = models[opportunity.participantKey]?[id];
      String? reason;
      double? prediction;
      double? raw;
      if (execution != 'executed') {
        reason = 'no_execution';
      } else if (artifact == null) {
        reason = 'no_frozen_model';
      } else {
        final result = artifact.predict(
          context: AiModelInferenceContext(
            ownerScope: Ai4FrozenExperiment.ownerScope,
            participantKey: opportunity.participantKey,
            protocol: manifest.protocol,
            timezone: opportunity.timezone,
            at: day.durableAt!,
            featureCutoff: opportunity.cutoff,
          ),
          sleepHours: row.feature?.durationHours,
          sleepAvailableAt: row.feature?.availableAt,
        );
        reason = result.abstentionReason;
        prediction = result.prediction;
        raw = result.rawPrediction;
      }
      final error = prediction == null || target.energy == null
          ? null
          : prediction - target.energy!;
      methods[id] = {
        'status': reason ?? 'predicted',
        'artifactId': artifact?.artifactId,
        'rawPrediction': raw,
        'prediction': prediction,
        'trainingOpportunityIds':
            artifact?.trainingOpportunityIds ?? <String>[],
        'signedError': error,
        'absoluteError': error?.abs(),
        'scored': error != null,
      };
    }
    rows.add({
      'opportunityId': opportunity.id,
      'participantKey': opportunity.participantKey,
      'localDate': opportunity.localDate,
      'cutoff': opportunity.cutoff.toIso8601String(),
      'executedAt': day.issuedAt?.toIso8601String(),
      'durableAt': day.durableAt?.toIso8601String(),
      'executionStatus': execution,
      'outcomeStatus': target.status,
      'energy': target.energy,
      'outcomeAvailableAt': row.outcome?.availableAt.toIso8601String(),
      'methods': methods,
    });
  }
  final active = rows
      .where((row) => row['executionStatus'] != 'withdrawn')
      .toList();
  final people =
      active.map((row) => row['participantKey'] as String).toSet().toList()
        ..sort();
  final methods = <String, dynamic>{};
  for (final id in _ids) {
    final perPerson = [
      for (final person in people)
        {
          'participantKey': person,
          ..._metrics(
            active.where((row) => row['participantKey'] == person).toList(),
            id,
          ),
        },
    ];
    final participantErrors = perPerson
        .map((p) => p['mae'])
        .whereType<double>()
        .toList();
    methods[id] = {
      ..._metrics(active, id),
      'perParticipant': perPerson,
      'macroParticipantMae': participantErrors.isEmpty
          ? null
          : _mean(participantErrors),
      'participantsScored': participantErrors.length,
    };
  }
  final common = active
      .where(
        (row) =>
            row['methods'][manifest.candidateId]['scored'] == true &&
            row['methods'][manifest.comparatorId]['scored'] == true,
      )
      .toList();
  final candidate = _metrics(common, manifest.candidateId);
  final comparator = _metrics(common, manifest.comparatorId);
  return {
    'partition': partition,
    'asOf': asOf.toIso8601String(),
    'evidenceKind': 'synthetic_software_fixture',
    'opportunityIds': [for (final row in rows) row['opportunityId']],
    'coverage': {
      'suppliedOpportunities': rows.length,
      'withdrawnOpportunities': rows.length - active.length,
      'activeOpportunities': active.length,
      'participants': people.length,
      'outcomeStatuses': _counts(rows.map((r) => r['outcomeStatus'] as String)),
      'executionStatuses': _counts(
        rows.map((r) => r['executionStatus'] as String),
      ),
    },
    'methods': methods,
    'selectedComparison': {
      'candidateId': manifest.candidateId,
      'comparatorId': manifest.comparatorId,
      'commonScored': common.length,
      'candidate': candidate,
      'comparator': comparator,
      'maeDifference': common.isEmpty
          ? null
          : (candidate['mae'] as double) - (comparator['mae'] as double),
      'differenceDirection':
          'candidate_minus_comparator_negative_favors_candidate',
      'pairedErrorSeries': [
        for (final row in common)
          {
            'opportunityId': row['opportunityId'],
            'participantKey': row['participantKey'],
            'localDate': row['localDate'],
            'cutoff': row['cutoff'],
            'candidateAbsoluteError':
                row['methods'][manifest.candidateId]['absoluteError'],
            'comparatorAbsoluteError':
                row['methods'][manifest.comparatorId]['absoluteError'],
          },
      ],
    },
    'rows': rows,
    'inputEvidence': dataset.toJson(),
    'interpretation': [
      'Both personal baselines and the regression are frozen at the fit cutoff.',
      'No development or final labels update any model or baseline.',
      'Missing predictions and missing targets have separate coverage counts.',
      'The denominator contains supplied opportunities; no omitted days are invented.',
      'Common-set point errors describe fixtures only; no statistical or clinical conclusion follows.',
    ],
  };
}

Map<String, dynamic> _metrics(List<Map<String, dynamic>> rows, String id) {
  final entries = rows
      .map((row) => row['methods'][id] as Map<String, dynamic>)
      .toList();
  final predicted = entries.where((row) => row['prediction'] != null).length;
  final errors = entries
      .map((row) => row['signedError'])
      .whereType<double>()
      .toList();
  return {
    'opportunities': rows.length,
    'predicted': predicted,
    'scored': errors.length,
    'coverage': rows.isEmpty ? null : predicted / rows.length,
    'scoredCoverage': rows.isEmpty ? null : errors.length / rows.length,
    'mae': errors.isEmpty ? null : _mean(errors.map((e) => e.abs())),
    'meanSignedError': errors.isEmpty ? null : _mean(errors),
    'statuses': _counts(entries.map((e) => e['status'] as String)),
  };
}

Map<String, int> _counts(Iterable<String> values) {
  final result = <String, int>{};
  for (final value in values) {
    result.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  return result;
}

List<Ai1FixtureDay> _validateDays(
  Ai4FrozenManifest manifest,
  Iterable<Ai1FixtureDay> input,
  DateTime start,
  DateTime end,
  DateTime asOf,
) {
  final days = input.toList();
  for (final day in days) {
    if (!day.synthetic ||
        day.opportunity.cutoff.isBefore(start) ||
        !day.opportunity.cutoff.isBefore(end)) {
      throw ArgumentError(
        'Only synthetic opportunities in the specified partition are accepted.',
      );
    }
  }
  Ai1DatasetBuilder.buildSynthetic(
    protocol: manifest.protocol,
    days: days,
    asOf: asOf,
    datasetVersion: manifest.datasetVersion,
  );
  final unique =
      {for (final day in days) day.opportunity.id: day}.values.toList()
        ..sort((a, b) {
          final result = a.opportunity.cutoff.compareTo(b.opportunity.cutoff);
          return result == 0
              ? a.opportunity.id.compareTo(b.opportunity.id)
              : result;
        });
  return unique;
}

void _validateZones(Iterable<Ai1FixtureDay> days) {
  final zones = <String, String>{};
  for (final day in days) {
    final old = zones[day.opportunity.participantKey];
    if (old != null && old != day.opportunity.timezone) {
      throw ArgumentError(
        'A fixed personal experiment cannot change timezone.',
      );
    }
    zones[day.opportunity.participantKey] = day.opportunity.timezone;
  }
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(ai1CanonicalJson(value)) as Map<String, dynamic>;

double _mean(Iterable<double> values) {
  var total = 0.0;
  var count = 0;
  for (final value in values) {
    total += (value - total) / ++count;
  }
  return total;
}
