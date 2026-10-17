import 'dart:convert';

import 'package:app/src/ai1_dataset_builder.dart';
import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/ai1_records.dart';
import 'package:app/src/ai2_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

final _protocol = Ai1Protocol.draft();
final _freeze = DateTime.utc(2026, 10, 16);

Ai1FixtureDay _day({
  String participant = 'sensitive-person-key',
  String date = '2026-10-11',
  bool synthetic = true,
  bool withdrawn = false,
  bool issued = true,
  bool sleep = true,
  int? energy = 7,
  bool responded = true,
  int observedMinutes = 60,
  int? savedMinutes,
  int? availableMinutes,
  String? measurement,
  String? responseTimezone,
  bool duplicatedResponse = false,
  bool conflictingResponse = false,
  bool deleted = false,
  bool responseHistoryComplete = true,
  bool responseLineageComplete = true,
  String? responseId,
}) {
  final opportunity = Ai1Opportunity.forDate(
    protocol: _protocol,
    participantKey: participant,
    localDate: date,
    timezone: 'America/Los_Angeles',
  );
  final observed = opportunity.outcomeStart.add(
    Duration(minutes: observedMinutes),
  );
  final saved = opportunity.outcomeStart.add(
    Duration(minutes: savedMinutes ?? observedMinutes + 1),
  );
  final available = opportunity.outcomeStart.add(
    Duration(minutes: availableMinutes ?? savedMinutes ?? observedMinutes + 1),
  );
  Ai1ResponseRevision response({int? value, bool? tombstone}) =>
      Ai1ResponseRevision(
        participantKey: participant,
        sourceId: responseId ?? 'sensitive-response-$date',
        revision: 1,
        observedAt: observed,
        initialSavedAt: saved,
        availableAt: available,
        localDate: date,
        timezone: responseTimezone ?? opportunity.timezone,
        measurement: measurement ?? _protocol.measurement,
        period: 'Evening',
        energy: value ?? energy,
        deleted: tombstone ?? deleted,
        lineageComplete: responseLineageComplete,
      );
  return Ai1FixtureDay(
    opportunity: opportunity,
    synthetic: synthetic,
    withdrawn: withdrawn,
    sleepHistoryComplete: true,
    responseHistoryComplete: responseHistoryComplete,
    sleepRevisions: [
      if (sleep)
        Ai1SleepRevision(
          participantKey: participant,
          collection: 'sleepLogs',
          sourceId: 'sensitive-sleep-$date',
          revision: 1,
          source: Ai1SleepSource.manual,
          endedAt: opportunity.cutoff.subtract(const Duration(hours: 3)),
          availableAt: opportunity.cutoff.subtract(const Duration(hours: 2)),
          durationHours: 8,
          selectionDependencies: [
            opportunity.cutoff.subtract(const Duration(minutes: 30)),
          ],
        ),
    ],
    responseRevisions: [
      if (responded) response(),
      if (responded && duplicatedResponse) response(),
      if (responded && conflictingResponse)
        response(value: energy == 7 ? 8 : 7),
    ],
    issuedAt: issued
        ? opportunity.cutoff.add(const Duration(minutes: 1))
        : null,
    durableAt: issued
        ? opportunity.cutoff.add(const Duration(minutes: 2))
        : null,
  );
}

Ai1DatasetReport _dataset(List<Ai1FixtureDay> days, {bool synthetic = true}) {
  final build = synthetic
      ? Ai1DatasetBuilder.buildSynthetic
      : Ai1DatasetBuilder.buildCaptured;
  return build(
    protocol: _protocol,
    days: days,
    asOf: _freeze,
    datasetVersion: 'readiness-test-v1',
  );
}

Ai2ReadinessReport _report(
  List<Ai1FixtureDay> days, {
  bool raw = true,
  bool synthetic = true,
}) => Ai2ReadinessEvaluator.evaluate(
  dataset: _dataset(days, synthetic: synthetic),
  rawDays: raw ? days : null,
);

void main() {
  test('no prospective data has unknown rates and never readiness', () {
    final report = _report([], synthetic: false);
    final json = report.toJson();
    expect(json['evidenceKind'], 'no_closed_opportunities_supplied');
    expect(json['participantCount'], 0);
    expect(json['coverage']['scheduledEveningCheckIns'], 0);
    expect(json['coverage']['outcomeMissingnessRate'], isNull);
    expect(json['responseTiming']['latenessRate'], isNull);
    expect(json['energy']['mean'], isNull);
    expect(json['energy']['sampleStandardDeviation'], isNull);
    expect(json['energy']['constantObservedRatings'], isNull);
    expect(json['questionnaireCompletion']['completed'], isNull);
    expect(report.modelingReady, isFalse);
    expect(report.trainingAllowed, isFalse);
    expect(
      report.toMarkdown(),
      contains('No closed daily opportunities were supplied'),
    );
  });

  test('synthetic success is never real evidence or permission to train', () {
    final report = _report([_day()]);
    expect(report.toJson()['coverage']['pairedOutcomes'], 1);
    expect(report.toJson()['evidenceKind'], 'synthetic_software_fixture');
    expect(report.toJson()['reviewGaps'], contains('synthetic_evidence_only'));
    expect(report.toJson()['modelingReady'], isFalse);
    expect(report.toJson()['trainingAllowed'], isFalse);
    expect(
      report.toMarkdown(),
      contains(
        'None of its participants, outcomes, or pairs is real study evidence',
      ),
    );
  });

  test('outcomes without predictors count as outcomes but never pairs', () {
    final json = _report([
      _day(),
      _day(date: '2026-10-12', issued: false, energy: 1),
      _day(date: '2026-10-13', responded: false),
      _day(date: '2026-10-14', sleep: false, energy: 10),
    ]).toJson();
    expect(json['coverage']['scheduledEveningCheckIns'], 4);
    expect(json['coverage']['sleepEligibleDays'], 3);
    expect(json['coverage']['completedOutcomes'], 3);
    expect(json['coverage']['pairedOutcomes'], 1);
    expect(json['coverage']['outcomeMissingnessRate'], 0.25);
    expect(json['energy']['count'], 3);
    expect(json['energy']['histogram']['1'], 1);
    expect(json['energy']['histogram']['10'], 1);
  });

  test(
    'withdrawal leaves a count but does not distort scheduled denominator',
    () {
      final json = _report([
        _day(),
        _day(participant: 'withdrawn-person', withdrawn: true),
      ]).toJson();
      expect(json['participantCount'], 2);
      expect(json['participantsWithActiveOpportunities'], 1);
      expect(json['coverage']['opportunities'], 2);
      expect(json['coverage']['withdrawnOpportunities'], 1);
      expect(json['coverage']['scheduledEveningCheckIns'], 1);
      expect(json['coverage']['outcomeMissingnessRate'], 0);
      expect(json['coverage']['outcomeStatuses']['withdrawn'], 1);
      final withdrawn = (json['participants'] as List).last;
      expect(withdrawn['coverage']['outcomeMissingnessRate'], isNull);
      expect(withdrawn['energy']['count'], 0);
    },
  );

  test(
    'per participant variation differs from misleading pooled variation',
    () {
      final json = _report([
        _day(energy: 1),
        _day(date: '2026-10-12', energy: 1),
        _day(participant: 'second-person', energy: 10),
        _day(participant: 'second-person', date: '2026-10-12', energy: 10),
      ]).toJson();
      expect(json['energy']['distinctValues'], 2);
      expect(json['energy']['constantObservedRatings'], isFalse);
      expect(json['energy']['endpointRate'], 1);
      for (final participant in json['participants'] as List) {
        expect(participant['energy']['constantObservedRatings'], isTrue);
        expect(participant['energy']['sampleStandardDeviation'], 0);
        expect(
          participant['energy']['longestSameRatingRunAmongObservedOutcomes'],
          2,
        );
      }
    },
  );

  test('late save is late but delayed analysis upload is not', () {
    final json = _report([
      _day(availableMinutes: 360),
      _day(date: '2026-10-12', observedMinutes: 239, savedMinutes: 240),
      _day(date: '2026-10-13', observedMinutes: -1, savedMinutes: 0),
      _day(date: '2026-10-14', observedMinutes: 0, savedMinutes: 0),
    ]).toJson();
    final timing = json['responseTiming'];
    expect(timing['originalEveningResponses'], 4);
    expect(timing['onTimeOriginalResponses'], 2);
    expect(timing['lateOriginalResponses'], 1);
    expect(timing['earlyOriginalResponses'], 1);
    expect(timing['delayedAnalysisAvailability'], 1);
    expect(timing['latenessRate'], 0.25);
    expect(json['coverage']['completedOutcomes'], 2);
  });

  test('invalid chronology and timezone do not enter lateness denominator', () {
    final timing = _report([
      _day(observedMinutes: 60, savedMinutes: 59),
      _day(date: '2026-10-12', responseTimezone: 'UTC'),
    ]).toJson()['responseTiming'];
    expect(timing['invalidTimingResponses'], 2);
    expect(timing['timingAssessableResponses'], 0);
    expect(timing['latenessRate'], isNull);
  });

  test(
    'duplicate copies collapse and conflicting originals remain unavailable',
    () {
      final json = _report([
        _day(duplicatedResponse: true),
        _day(date: '2026-10-12', conflictingResponse: true),
        _day(date: '2026-10-13', deleted: true),
      ]).toJson();
      expect(json['responseTiming']['originalEveningResponses'], 1);
      expect(json['responseTiming']['unassessableOriginalGroups'], 1);
      expect(json['responseTiming']['deletedGroupsOmitted'], 1);
      expect(
        json['coverage']['outcomeStatuses']['conflicting_response_revision'],
        1,
      );
      expect(
        json['coverage']['outcomeStatuses']['selected_response_deleted'],
        1,
      );
    },
  );

  test('measurement versions include excluded original definitions', () {
    final other = jsonDecode(_protocol.measurement) as Map<String, dynamic>;
    other['version'] = 'another-draft-v2';
    final json = _report([
      _day(),
      _day(date: '2026-10-12', measurement: ai1CanonicalJson(other)),
    ]).toJson();
    expect(json['coverage']['completedOutcomes'], 1);
    final definitions = json['measurementDefinitions']['definitions'] as List;
    expect(definitions.length, 2);
    expect(
      definitions
          .where((item) => item['matchesProtocol'] == false)
          .single['version'],
      'another-draft-v2',
    );
    expect(json['responseTiming']['originalEveningResponses'], 2);
  });

  test(
    'without raw histories timing stays unavailable, never inferred from matches',
    () {
      final report = _report([_day()], raw: false);
      expect(report.toJson()['responseTiming'], isNull);
      expect(
        report.toJson()['measurementDefinitions']['coverage'],
        'matched_outcomes_only',
      );
      expect(
        report.toMarkdown(),
        contains('Matched outcomes alone cannot estimate lateness'),
      );
    },
  );

  test('unrelated timing evidence fails rather than changing denominators', () {
    final days = [_day()];
    expect(
      () => Ai2ReadinessEvaluator.evaluate(
        dataset: _dataset(days),
        rawDays: [_day(energy: 3)],
      ),
      throwsArgumentError,
    );
    expect(
      () => Ai2ReadinessEvaluator.evaluate(
        dataset: _dataset(days),
        rawDays: [_day(synthetic: false)],
      ),
      throwsArgumentError,
    );
  });

  test(
    'reports use anonymous aliases and preserve availability dependency lead',
    () {
      final report = _report([_day()]);
      final json = report.toJson();
      final serialized = jsonEncode(json);
      for (final text in [serialized, report.toMarkdown()]) {
        expect(text, isNot(contains('sensitive-person-key')));
        expect(text, isNot(contains('sensitive-response')));
        expect(text, isNot(contains('sensitive-sleep')));
      }
      expect(json['participants'][0]['participant'], 'participant-001');
      expect(json['sleep']['availabilityLeadMinutes']['minimum'], 30);
      expect(json['sleep']['frozenFeatureSources']['manual'], 1);
      json['coverage']['pairedOutcomes'] = 100;
      expect(report.toJson()['coverage']['pairedOutcomes'], 1);
    },
  );

  test(
    'a missing Energy answer stays missing and cannot become a neutral rating',
    () {
      final json = _report([_day(energy: null)]).toJson();
      expect(json['coverage']['completedOutcomes'], 0);
      expect(json['coverage']['outcomeMissingnessRate'], 1);
      expect(json['coverage']['outcomeStatuses']['missing_energy'], 1);
      expect(json['energy']['count'], 0);
      expect(json['energy']['histogram']['5'], 0);
    },
  );

  test(
    'withdrawn opportunities are not described as absent prospective data',
    () {
      final report = _report([
        _day(synthetic: false, withdrawn: true),
      ], synthetic: false);
      expect(report.toJson()['evidenceKind'], 'no_non_withdrawn_opportunities');
      expect(report.toJson()['coverage']['opportunities'], 1);
      expect(report.toJson()['coverage']['outcomeMissingnessRate'], isNull);
      expect(
        report.toMarkdown(),
        contains('All supplied daily opportunities are withdrawn'),
      );
      expect(
        report.toMarkdown(),
        isNot(contains('No closed daily opportunities')),
      );
    },
  );

  test(
    'raw data unavailable at freeze cannot inflate timing or version counts',
    () {
      final json = _report([_day(availableMinutes: 7 * 24 * 60)]).toJson();
      expect(json['coverage']['completedOutcomes'], 0);
      expect(json['responseTiming']['originalEveningResponses'], 0);
      expect(json['responseTiming']['latenessRate'], isNull);
      expect(json['measurementDefinitions']['definitions'], isEmpty);
    },
  );

  test(
    'unproven history remains unassessable and duplicate days do not inflate it',
    () {
      final day = _day(responseHistoryComplete: false);
      final json = _report([day, day]).toJson();
      expect(json['coverage']['opportunities'], 1);
      expect(json['coverage']['completedOutcomes'], 0);
      expect(json['responseTiming']['originalEveningResponses'], 0);
      expect(json['responseTiming']['unassessableOriginalGroups'], 1);
      expect(json['responseTiming']['latenessRate'], isNull);
      expect(json['measurementDefinitions']['definitions'], isEmpty);
      final unproven = _report([_day(responseLineageComplete: false)]).toJson();
      expect(unproven['responseTiming']['originalEveningResponses'], 0);
      expect(unproven['responseTiming']['unassessableOriginalGroups'], 1);
      final unidentified = _report([_day(responseId: '')]).toJson();
      expect(unidentified['responseTiming']['originalEveningResponses'], 0);
      expect(unidentified['responseTiming']['unassessableOriginalGroups'], 1);
    },
  );
}
