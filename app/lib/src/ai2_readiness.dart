import 'dart:convert';
import 'dart:math' as math;

import 'ai1_dataset_builder.dart';
import 'ai1_protocol.dart';
import 'ai1_records.dart';

/// Describes measurement coverage; it never promotes a dataset or trains a model.
abstract final class Ai2ReadinessEvaluator {
  static Ai2ReadinessReport evaluate({
    required Ai1DatasetReport dataset,
    Iterable<Ai1FixtureDay>? rawDays,
  }) {
    final raw = rawDays?.toList(growable: false);
    if (raw != null) {
      // The optional timing evidence must reproduce this exact analysis freeze.
      final rebuild = dataset.synthetic
          ? Ai1DatasetBuilder.buildSynthetic
          : Ai1DatasetBuilder.buildCaptured;
      final checked = rebuild(
        protocol: dataset.protocol,
        days: raw,
        asOf: dataset.asOf,
        datasetVersion: dataset.datasetVersion,
      );
      if (ai1CanonicalJson(checked.toJson()) !=
          ai1CanonicalJson(dataset.toJson())) {
        throw ArgumentError('Raw histories do not reproduce this dataset.');
      }
    }
    final keys =
        dataset.rows
            .map((row) => row.opportunity.participantKey)
            .toSet()
            .toList()
          ..sort();
    final active = dataset.rows
        .where((row) => row.issuanceStatus != 'withdrawn')
        .toList();
    final timing = raw == null ? null : _timing(raw, dataset.asOf);
    final reasons = <String>[
      if (dataset.synthetic) 'synthetic_evidence_only',
      if (dataset.rows.isEmpty) 'no_closed_daily_opportunities_supplied',
      if (dataset.rows.isNotEmpty && active.isEmpty)
        'no_non_withdrawn_daily_opportunities',
      if (!active.any((row) => row.outcomeStatus == 'matched'))
        'no_completed_outcomes',
      if (!active.any((row) => row.hasPair))
        'no_usable_predictor_outcome_pairs',
      if (active.any((row) => row.outcomeStatus != 'matched'))
        'incomplete_outcomes_require_review',
      if (active.any((row) => row.sleepStatus != 'eligible'))
        'sleep_eligibility_requires_review',
      if (timing == null) 'raw_response_timing_unavailable',
      if (timing != null && (timing['lateOriginalResponses'] as int) > 0)
        'late_responses_require_review',
      'questionnaire_completion_unavailable',
      'question_comprehension_not_assessed',
      'participant_protocol_review_not_established',
      'study_size_and_precision_require_statistical_review',
    ];
    final energy = _energy(active);
    if (energy['constantObservedRatings'] == true) {
      reasons.add('constant_observed_energy');
    }
    if (keys.any(
      (key) =>
          _energy(
            active
                .where((row) => row.opportunity.participantKey == key)
                .toList(),
          )['constantObservedRatings'] ==
          true,
    )) {
      reasons.add('constant_within_participant_energy');
    }
    final features = active.where((row) => row.feature != null).toList();
    final leadMinutes = features.map((row) {
      final feature = row.feature!;
      var lastDependency = feature.availableAt!;
      for (final dependency in feature.selectionDependencies) {
        if (dependency!.isAfter(lastDependency)) lastDependency = dependency;
      }
      return row.opportunity.cutoff.difference(lastDependency).inMicroseconds /
          Duration.microsecondsPerMinute;
    }).toList();
    return Ai2ReadinessReport._({
      'schemaVersion': 'ai2-measurement-readiness-v1',
      'datasetVersion': dataset.datasetVersion,
      'asOf': dataset.asOf.toIso8601String(),
      'synthetic': dataset.synthetic,
      'evidenceKind': dataset.synthetic
          ? 'synthetic_software_fixture'
          : dataset.rows.isEmpty
          ? 'no_closed_opportunities_supplied'
          : active.isEmpty
          ? 'no_non_withdrawn_opportunities'
          : 'captured_local_history',
      'modelingReady': false,
      'trainingAllowed': false,
      'status': 'not_established',
      'protocolId': dataset.protocol.id,
      'protocolVersion': dataset.protocol.version,
      'measurement': jsonDecode(dataset.protocol.measurement),
      'participantCount': keys.length,
      'participantsWithActiveOpportunities': active
          .map((row) => row.opportunity.participantKey)
          .toSet()
          .length,
      'coverage': _coverage(dataset.rows),
      'energy': energy,
      'participants': [
        for (var index = 0; index < keys.length; index++)
          {
            // Aliases are report-local and must not be used to link exports.
            'participant':
                'participant-${(index + 1).toString().padLeft(3, '0')}',
            'coverage': _coverage(
              dataset.rows
                  .where((row) => row.opportunity.participantKey == keys[index])
                  .toList(),
            ),
            'energy': _energy(
              active
                  .where((row) => row.opportunity.participantKey == keys[index])
                  .toList(),
            ),
            'responseTiming': raw == null
                ? null
                : _timing(
                    raw.where(
                      (day) => day.opportunity.participantKey == keys[index],
                    ),
                    dataset.asOf,
                  ),
          },
      ],
      'sleep': {
        'configuredSource': dataset.protocol.sleepSource.name,
        'eligibleDays': active
            .where((row) => row.sleepStatus == 'eligible')
            .length,
        'frozenFeatureCount': features.length,
        'frozenFeatureSources': _counts(
          features.map((row) => row.feature!.source.name),
        ),
        'availabilityLeadMinutes': {
          'count': leadMinutes.length,
          'minimum': leadMinutes.isEmpty ? null : leadMinutes.reduce(math.min),
          'maximum': leadMinutes.isEmpty ? null : leadMinutes.reduce(math.max),
          'definition':
              'Cutoff minus latest selected-feature availability or selection dependency; issued snapshots only.',
        },
      },
      'responseTiming': timing,
      'measurementDefinitions': _definitions(dataset, raw),
      'questionnaireCompletion': {
        'available': false,
        'scheduled': null,
        'completed': null,
        'completionRate': null,
        'reason':
            'The daily Energy dataset does not carry questionnaire schedules, all item responses, or instrument completion records.',
      },
      'reviewGaps': reasons,
      'denominatorNotes': [
        'Participants are those represented by retained daily opportunities, not an enrollment census.',
        'This assessment covers closed daily opportunities supplied to it; zero rows do not prove that no raw measurements or ongoing study days exist.',
        'One scheduled evening check-in per non-withdrawn daily opportunity; morning check-ins are outside this contract.',
        'Sleep-eligible days, completed Energy outcomes, and predictor/outcome pairs are separate counts.',
        'Outcome missingness includes unusable or excluded outcomes; no response and missing Energy have separate status counts.',
        'Withdrawn opportunities are reported separately and excluded from scheduled-check-in denominators.',
        'Exclusion counts overlap across sleep, issuance, and outcome stages; do not add stage totals.',
        'Zero denominators produce null rates, never a claimed zero-percent missingness.',
        'Energy distribution uses all matched outcomes, including outcomes without an issued predictor; missing targets are never imputed.',
        'Participant aliases are report-local; no participant, response, or sleep-record identifiers are exported.',
        'No automatic sample-size, variance, or accuracy threshold establishes readiness.',
      ],
    });
  }
}

class Ai2ReadinessReport {
  Ai2ReadinessReport._(Map<String, Object?> data) : _json = jsonEncode(data);
  final String _json;

  bool get modelingReady => false;
  bool get trainingAllowed => false;
  Map<String, dynamic> toJson() => jsonDecode(_json) as Map<String, dynamic>;

  /// Local Markdown report: aggregated counts and anonymous report-local aliases.
  String toMarkdown() {
    final data = toJson();
    final coverage = data['coverage'] as Map<String, dynamic>;
    final energy = data['energy'] as Map<String, dynamic>;
    final timing = data['responseTiming'] as Map<String, dynamic>?;
    final sleep = data['sleep'] as Map<String, dynamic>;
    final lines = <String>[
      '# Data readiness report',
      '',
      '**Modeling readiness is not established. Training remains prohibited.**',
      if (data['synthetic'] == true)
        'This is a synthetic software audit. None of its participants, outcomes, or pairs is real study evidence.'
      else if (coverage['opportunities'] == 0)
        'No closed daily opportunities were supplied for this assessment. This does not establish whether raw measurements or ongoing study days exist.'
      else if (coverage['scheduledEveningCheckIns'] == 0)
        'All supplied daily opportunities are withdrawn. No non-withdrawn opportunities are available to assess measurement readiness.'
      else
        'This report describes supplied local history; it does not establish protocol approval or measurement validity.',
      '',
      'Dataset: ${_escape(data['datasetVersion'] as String)}. Analysis freeze: ${data['asOf']} (UTC).',
      'Protocol: ${_escape(data['protocolVersion'] as String)}. Main-sleep source: ${data['sleep']['configuredSource']}.',
      '',
      '| Coverage | Count |',
      '| --- | ---: |',
      '| Participants represented in opportunities | ${data['participantCount']} |',
      '| All daily opportunities | ${coverage['opportunities']} |',
      '| Withdrawn opportunities | ${coverage['withdrawnOpportunities']} |',
      '| Scheduled evening check-ins | ${coverage['scheduledEveningCheckIns']} |',
      '| Sleep-eligible days | ${coverage['sleepEligibleDays']} |',
      '| Issued predictor snapshots | ${coverage['issuedSnapshots']} |',
      '| Completed Energy outcomes | ${coverage['completedOutcomes']} |',
      '| Predictor/outcome pairs | ${coverage['pairedOutcomes']} |',
      '| Missing or unusable outcomes | ${coverage['missingOrUnusableOutcomes']} |',
      '',
      'Outcome missingness: ${_rateText(coverage['outcomeMissingnessRate'])}; denominator: ${coverage['scheduledEveningCheckIns']} scheduled evening check-ins.',
      '',
      '| Participant (report-local alias) | Scheduled | Sleep eligible | Outcomes | Pairs | Missingness |',
      '| --- | ---: | ---: | ---: | ---: | ---: |',
      for (final participant in data['participants'] as List)
        '| ${participant['participant']} | ${participant['coverage']['scheduledEveningCheckIns']} | ${participant['coverage']['sleepEligibleDays']} | ${participant['coverage']['completedOutcomes']} | ${participant['coverage']['pairedOutcomes']} | ${_rateText(participant['coverage']['outcomeMissingnessRate'])} |',
      '',
      'Frozen main-sleep features: ${sleep['frozenFeatureCount']}; source counts: ${jsonEncode(sleep['frozenFeatureSources'])}. Availability before cutoff, including the latest selection dependency: ${sleep['availabilityLeadMinutes']['minimum'] ?? 'unavailable'}–${sleep['availabilityLeadMinutes']['maximum'] ?? 'unavailable'} minutes. Availability is assessed for issued snapshots only.',
      '',
      'Energy uses all ${energy['count']} completed outcomes. Distinct ratings: ${energy['distinctValues']}; observed range: ${energy['minimum'] ?? 'unavailable'}–${energy['maximum'] ?? 'unavailable'}; mean: ${energy['mean'] ?? 'unavailable'}; sample standard deviation: ${energy['sampleStandardDeviation'] ?? 'unavailable'}.',
      'Ratings at 1: ${energy['atOne']}; at 10: ${energy['atTen']}; endpoint fraction: ${_rateText(energy['endpointRate'])}. Constant observed ratings: ${energy['constantObservedRatings'] ?? 'unavailable (fewer than two outcomes)'}.',
      '',
      '| Energy rating | Count |',
      '| --- | ---: |',
      for (final entry in (energy['histogram'] as Map).entries)
        '| ${entry.key} | ${entry.value} |',
      '',
      '| Participant | Distinct Energy values | Range | Sample SD | Endpoints | Longest same-rating run |',
      '| --- | ---: | --- | ---: | ---: | ---: |',
      for (final participant in data['participants'] as List)
        '| ${participant['participant']} | ${participant['energy']['distinctValues']} | ${participant['energy']['minimum'] ?? 'unavailable'}–${participant['energy']['maximum'] ?? 'unavailable'} | ${participant['energy']['sampleStandardDeviation'] ?? 'unavailable'} | ${_rateText(participant['energy']['endpointRate'])} | ${participant['energy']['longestSameRatingRunAmongObservedOutcomes']} |',
      '',
      'Runs refer to consecutive observed ratings within one participant; unobserved days are not counted as repeated answers. Pooled variation can conceal constant within-participant ratings.',
      '',
      if (timing == null)
        'Response lateness is unavailable: no raw histories were supplied. Matched outcomes alone cannot estimate lateness.'
      else
        'Response timing: ${timing['originalEveningResponses']} retained original evening responses; ${timing['onTimeOriginalResponses']} on time, ${timing['lateOriginalResponses']} late, ${timing['earlyOriginalResponses']} early, and ${timing['invalidTimingResponses']} with invalid timing. Late fraction among timing-assessable responses: ${_rateText(timing['latenessRate'])}. ${timing['delayedAnalysisAvailability']} on-time responses became available for analysis after the window; these are not late local saves. Unassessable original groups: ${timing['unassessableOriginalGroups']}; deleted groups omitted: ${timing['deletedGroupsOmitted']}.',
      '',
      if (timing != null) ...[
        'Timing is response-level, attributed by recorded local date. A late response was observed or initially saved at/after 22:00 in the frozen timezone; late upload alone is not late responding.',
        '',
        '| Participant | Timing-assessable responses | Late responses | Lateness |',
        '| --- | ---: | ---: | ---: |',
        for (final participant in data['participants'] as List)
          '| ${participant['participant']} | ${participant['responseTiming']['timingAssessableResponses']} | ${participant['responseTiming']['lateOriginalResponses']} | ${_rateText(participant['responseTiming']['latenessRate'])} |',
        '',
      ],
      'Questionnaire completion and question comprehension are unavailable in this dataset. They require separate schedules, completion records, and participant feedback.',
      '',
      'Measurement definitions (${data['measurementDefinitions']['coverage']}):',
      '',
      if ((data['measurementDefinitions']['definitions'] as List).isEmpty)
        'No measurement definitions were observed in supplied responses.',
      for (final definition
          in data['measurementDefinitions']['definitions'] as List)
        '- ${definition['definition']}: version ${_escape(definition['version'] as String? ?? 'unknown')}, language ${_escape(definition['language'] as String? ?? 'unknown')}, ${definition['originalResponses']} original responses, exact protocol match ${definition['matchesProtocol']}.',
      '',
      'Exclusions by stage (overlapping counts):',
      '',
      for (final stage in [
        'sleepStatuses',
        'issuanceStatuses',
        'outcomeStatuses',
      ])
        '- $stage: ${jsonEncode(coverage[stage])}.',
      '',
      'Remaining review gaps:',
      '',
      for (final reason in data['reviewGaps'] as List) '- $reason.',
      '',
      'Denominators and interpretation:',
      '',
      for (final note in data['denominatorNotes'] as List) '- $note',
      '',
      'Use observed routines. Review timing, completion, comprehension, within-participant Energy variation, independent participant count, model complexity, and desired precision with the mentors or a statistical adviser before advancing to modeling.',
      '',
    ];
    return lines.join('\n');
  }
}

Map<String, Object?> _coverage(List<Ai1DatasetRow> rows) {
  final active = rows
      .where((row) => row.issuanceStatus != 'withdrawn')
      .toList();
  final complete = active.where((row) => row.outcomeStatus == 'matched').length;
  final pairs = active.where((row) => row.hasPair).length;
  return {
    'opportunities': rows.length,
    'withdrawnOpportunities': rows.length - active.length,
    'scheduledEveningCheckIns': active.length,
    'sleepEligibleDays': active
        .where((row) => row.sleepStatus == 'eligible')
        .length,
    'issuedSnapshots': active
        .where((row) => row.issuanceStatus == 'issued')
        .length,
    'completedOutcomes': complete,
    'pairedOutcomes': pairs,
    'missingOrUnusableOutcomes': active.length - complete,
    'outcomeCompletionRate': _rate(complete, active.length),
    'outcomeMissingnessRate': _rate(active.length - complete, active.length),
    'pairCoverageRate': _rate(pairs, active.length),
    'sleepStatuses': _counts(rows.map((row) => row.sleepStatus)),
    'issuanceStatuses': _counts(rows.map((row) => row.issuanceStatus)),
    'outcomeStatuses': _counts(rows.map((row) => row.outcomeStatus)),
  };
}

Map<String, Object?> _energy(List<Ai1DatasetRow> rows) {
  final values = rows
      .where((row) => row.outcomeStatus == 'matched')
      .map((row) => row.energy!)
      .toList();
  final histogram = {for (var value = 1; value <= 10; value++) '$value': 0};
  for (final value in values) {
    histogram['$value'] = histogram['$value']! + 1;
  }
  final mean = values.isEmpty
      ? null
      : values.reduce((a, b) => a + b) / values.length;
  final squared = mean == null
      ? 0.0
      : values.fold<double>(0, (sum, value) => sum + math.pow(value - mean, 2));
  final ordered = rows.where((row) => row.outcomeStatus == 'matched').toList()
    ..sort((a, b) {
      final participant = a.opportunity.participantKey.compareTo(
        b.opportunity.participantKey,
      );
      return participant != 0
          ? participant
          : a.opportunity.localDate.compareTo(b.opportunity.localDate);
    });
  var longest = 0;
  var run = 0;
  Ai1DatasetRow? previous;
  for (final row in ordered) {
    run =
        previous != null &&
            previous.opportunity.participantKey ==
                row.opportunity.participantKey &&
            previous.energy == row.energy
        ? run + 1
        : 1;
    longest = math.max(longest, run);
    previous = row;
  }
  return {
    'count': values.length,
    'histogram': histogram,
    'distinctValues': values.toSet().length,
    'minimum': values.isEmpty ? null : values.reduce(math.min),
    'maximum': values.isEmpty ? null : values.reduce(math.max),
    'mean': mean,
    'sampleStandardDeviation': values.length < 2
        ? null
        : math.sqrt(squared / (values.length - 1)),
    'atOne': histogram['1'],
    'atTen': histogram['10'],
    'endpointRate': _rate(histogram['1']! + histogram['10']!, values.length),
    'constantObservedRatings': values.length < 2
        ? null
        : values.toSet().length == 1,
    'longestSameRatingRunAmongObservedOutcomes': longest,
    'runDefinition':
        'Chronological observed outcomes within a participant; missing days do not imply an observed repeat.',
  };
}

/// Retained originals only: no corrections or deleted answers are substituted.
({
  List<({Ai1ResponseRevision response, Ai1Opportunity opportunity})> originals,
  int unassessable,
  int deleted,
})
_originals(Iterable<Ai1FixtureDay> days, DateTime asOf) {
  final originals =
      <({Ai1ResponseRevision response, Ai1Opportunity opportunity})>[];
  final seenDays = <String>{};
  var unassessable = 0;
  var deleted = 0;
  for (final day in days) {
    if (day.withdrawn || !seenDays.add(day.opportunity.id)) continue;
    final groups = <String, List<Ai1ResponseRevision>>{};
    for (final response in day.responseRevisions) {
      if (response.participantKey == day.opportunity.participantKey) {
        (groups[response.sourceId] ??= []).add(response);
      }
    }
    for (final group in groups.values) {
      final known = group
          .where((response) => !response.availableAt.isAfter(asOf))
          .toList();
      if (known.isEmpty) continue;
      final first = known.where((response) => response.revision == 1).toList();
      final relevant = first.isEmpty ? known : first;
      if (!relevant.any(
        (response) =>
            response.localDate == day.opportunity.localDate &&
            response.period == 'Evening',
      )) {
        continue;
      }
      if (group.any((response) => response.deleted)) {
        deleted++;
        continue;
      }
      if (first.isEmpty ||
          first.map((response) => response.fingerprint).toSet().length != 1 ||
          !day.responseHistoryComplete ||
          !first.first.lineageComplete ||
          first.first.sourceId.trim().isEmpty) {
        unassessable++;
        continue;
      }
      final response = first.first;
      originals.add((response: response, opportunity: day.opportunity));
    }
  }
  return (originals: originals, unassessable: unassessable, deleted: deleted);
}

Map<String, Object?> _timing(Iterable<Ai1FixtureDay> days, DateTime asOf) {
  final evidence = _originals(days, asOf);
  var onTime = 0;
  var late = 0;
  var early = 0;
  var invalid = 0;
  var delayed = 0;
  for (final entry in evidence.originals) {
    final response = entry.response;
    final opportunity = entry.opportunity;
    if (response.initialSavedAt.isBefore(response.observedAt) ||
        response.availableAt.isBefore(response.initialSavedAt) ||
        response.timezone != opportunity.timezone) {
      invalid++;
    } else if (!response.observedAt.isBefore(opportunity.outcomeEnd) ||
        !response.initialSavedAt.isBefore(opportunity.outcomeEnd)) {
      late++;
    } else if (response.observedAt.isBefore(opportunity.outcomeStart) ||
        response.initialSavedAt.isBefore(opportunity.outcomeStart)) {
      early++;
    } else {
      onTime++;
      if (!response.availableAt.isBefore(opportunity.outcomeEnd)) delayed++;
    }
  }
  return {
    'originalEveningResponses': evidence.originals.length,
    'onTimeOriginalResponses': onTime,
    'lateOriginalResponses': late,
    'earlyOriginalResponses': early,
    'invalidTimingResponses': invalid,
    'timingAssessableResponses': onTime + late + early,
    'latenessRate': _rate(late, onTime + late + early),
    'delayedAnalysisAvailability': delayed,
    'unassessableOriginalGroups': evidence.unassessable,
    'deletedGroupsOmitted': evidence.deleted,
    'definition':
        'Original retained evening responses attributed by recorded local date; late means observed or initially saved at/after 22:00 in the frozen zone. This response-level denominator is not scheduled days. Duplicate copies collapse; corrections are not substituted; late analysis availability alone is not late responding.',
  };
}

Map<String, Object?> _definitions(
  Ai1DatasetReport dataset,
  List<Ai1FixtureDay>? raw,
) {
  final responses = raw == null
      ? dataset.rows
            .where((row) => row.outcome != null)
            .map((row) => row.outcome!)
      : _originals(raw, dataset.asOf).originals.map((entry) => entry.response);
  final counts = _counts(responses.map((response) => response.measurement));
  final definitions = counts.keys.toList()..sort();
  return {
    'coverage': raw == null
        ? 'matched_outcomes_only'
        : 'retained_original_evening_responses',
    'definitions': [
      for (var index = 0; index < definitions.length; index++)
        {
          'definition': 'measurement-${index + 1}',
          ..._definitionMetadata(definitions[index]),
          'originalResponses': counts[definitions[index]],
          'matchesProtocol': definitions[index] == dataset.protocol.measurement,
        },
    ],
  };
}

Map<String, Object?> _definitionMetadata(String definition) {
  try {
    final decoded = jsonDecode(definition);
    if (decoded is Map) {
      return {
        'version': decoded['version'] is String ? decoded['version'] : null,
        'language': decoded['language'] is String ? decoded['language'] : null,
      };
    }
  } on FormatException {
    // Unknown metadata remains unknown; do not infer a measurement version.
  }
  return {'version': null, 'language': null};
}

Map<String, int> _counts(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  return {for (final key in counts.keys.toList()..sort()) key: counts[key]!};
}

double? _rate(int numerator, int denominator) =>
    denominator == 0 ? null : numerator / denominator;
String _rateText(Object? value) => value == null
    ? 'unavailable (zero denominator)'
    : '${((value as num) * 100).toStringAsFixed(1)}%';
String _escape(String text) =>
    text.replaceAll('|', '\\|').replaceAll('\n', ' ').replaceAll('\r', ' ');
