import 'dart:convert';

import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/ai1_records.dart';
import 'package:app/src/ai3_comparison_runner.dart';
import 'package:flutter_test/flutter_test.dart';

final _protocol = Ai1Protocol.draft();

DateTime _time(int day, [int hour = 10, int minute = 0]) =>
    DateTime.utc(2026, 1, day, hour, minute);

Ai3SyntheticManifest _manifest({
  String experimentId = 'independent-synthetic-comparison-v1',
  String datasetVersion = 'invented-data-v1',
  DateTime? historyStart,
  DateTime? evaluationStart,
  DateTime? evaluationEnd,
  DateTime? analysisAsOf,
}) => Ai3SyntheticManifest(
  protocol: _protocol,
  experimentId: experimentId,
  datasetVersion: datasetVersion,
  historyStart: historyStart ?? _time(1),
  evaluationStart: evaluationStart ?? _time(3),
  evaluationEnd: evaluationEnd ?? _time(5),
  analysisAsOf: analysisAsOf ?? _time(6),
);

Ai1FixtureDay _day(
  int day, {
  String participant = 'invented-person-a',
  double sleep = 7,
  num? energy = 6,
  bool hasSleep = true,
  bool issued = true,
  bool durable = true,
  bool responded = true,
  bool synthetic = true,
  bool withdrawn = false,
  String timezone = 'Etc/UTC',
  DateTime? issuedAt,
  DateTime? durableAt,
  DateTime? availableAt,
  DateTime? revisedAt,
  DateTime? responseDeletedAt,
  DateTime? sleepAvailableAt,
  DateTime? sleepDeletedAt,
  num revisedEnergy = 10,
  List<DateTime> timezoneChanges = const [],
}) {
  final date = '2026-01-${day.toString().padLeft(2, '0')}';
  final opportunity = Ai1Opportunity.forDate(
    protocol: _protocol,
    participantKey: participant,
    localDate: date,
    timezone: timezone,
  );
  Ai1ResponseRevision response(
    int revision,
    DateTime availability,
    num? value, {
    bool deleted = false,
  }) => Ai1ResponseRevision(
    participantKey: participant,
    sourceId: 'response-$participant-$day',
    revision: revision,
    observedAt: _time(day, 19),
    initialSavedAt: _time(day, 19, 1),
    availableAt: availability,
    localDate: date,
    timezone: opportunity.timezone,
    measurement: _protocol.measurement,
    period: 'Evening',
    energy: value,
    deleted: deleted,
  );
  return Ai1FixtureDay(
    opportunity: opportunity,
    synthetic: synthetic,
    sleepHistoryComplete: true,
    responseHistoryComplete: true,
    sleepRevisions: [
      if (hasSleep)
        Ai1SleepRevision(
          participantKey: participant,
          collection: 'invented-sleep',
          sourceId: 'sleep-$participant-$day',
          revision: 1,
          source: Ai1SleepSource.manual,
          endedAt: _time(day, 7),
          startedAt: _time(
            day,
            7,
          ).subtract(Duration(minutes: (sleep * 60).round())),
          durationHours: sleep,
          availableAt: sleepAvailableAt ?? _time(day, 8),
        ),
      if (hasSleep && sleepDeletedAt != null)
        Ai1SleepRevision(
          participantKey: participant,
          collection: 'invented-sleep',
          sourceId: 'sleep-$participant-$day',
          revision: 2,
          source: Ai1SleepSource.manual,
          endedAt: _time(day, 7),
          startedAt: _time(
            day,
            7,
          ).subtract(Duration(minutes: (sleep * 60).round())),
          durationHours: sleep,
          availableAt: sleepDeletedAt,
          deleted: true,
        ),
    ],
    responseRevisions: [
      if (responded) response(1, availableAt ?? _time(day, 19, 1), energy),
      if (responded && revisedAt != null) response(2, revisedAt, revisedEnergy),
      if (responded && responseDeletedAt != null)
        response(2, responseDeletedAt, energy, deleted: true),
    ],
    issuedAt: issued ? issuedAt ?? _time(day, 10, 1) : null,
    durableAt: issued && durable ? durableAt ?? _time(day, 10, 2) : null,
    timezoneChanges: timezoneChanges,
    withdrawn: withdrawn,
  );
}

Map<String, dynamic> _run(
  List<Ai1FixtureDay> days, {
  Ai3SyntheticManifest? manifest,
}) => Ai3ComparisonRunner.runSynthetic(
  manifest: manifest ?? _manifest(),
  days: days,
).toJson();

List<Ai1FixtureDay> _linearDays() => [
  _day(1, sleep: 6, energy: 4),
  _day(2, sleep: 8, energy: 8),
  _day(3, sleep: 7, energy: 6),
  _day(4, sleep: 9, energy: 9),
];

Map<String, dynamic> _row(
  Map<String, dynamic> report,
  int day, {
  String participant = 'invented-person-a',
}) => Map<String, dynamic>.from(
  (report['rows'] as List).singleWhere(
    (row) =>
        row['participantKey'] == participant &&
        row['localDate'] == '2026-01-${day.toString().padLeft(2, '0')}',
  ),
);

Map<String, dynamic> _method(
  Map<String, dynamic> report,
  int day,
  String method, {
  String participant = 'invented-person-a',
}) => Map<String, dynamic>.from(
  _row(report, day, participant: participant)['methods'][method] as Map,
);

void main() {
  test(
    'withdrawn and erased history is unavailable even in earlier replays',
    () {
      for (final erased in [
        _day(1, sleep: 6, energy: 4, withdrawn: true),
        _day(1, sleep: 6, energy: 4, responseDeletedAt: _time(5, 12)),
      ]) {
        final report = _run([erased, _day(2, sleep: 8, energy: 8), _day(3)]);
        expect(_method(report, 3, 'B0')['prediction'], 8);
        expect(_method(report, 3, 'B1')['prediction'], 8);
        expect(_method(report, 3, 'M1')['status'], 'insufficient_pairs');
        for (final method in ['B0', 'B1', 'M1']) {
          expect(
            _method(report, 3, method)['trainingOpportunityIds'],
            isNot(contains(erased.opportunity.id)),
          );
        }
      }
      final deletedSleep = _run([
        _day(1, sleep: 6, energy: 4, sleepDeletedAt: _time(5, 12)),
        _day(2, sleep: 8, energy: 8),
        _day(3),
      ]);
      expect(_method(deletedSleep, 3, 'B0')['prediction'], 6);
      expect(_method(deletedSleep, 3, 'M1')['status'], 'insufficient_pairs');
      expect(_method(deletedSleep, 3, 'M1')['trainingCount'], 1);
    },
  );

  test('late and subsequently erased current sleep never enters the model', () {
    for (final current in [
      _day(3, sleepAvailableAt: _time(3, 10, 1)),
      _day(3, sleepDeletedAt: _time(5, 12)),
    ]) {
      final report = _run([
        _day(1, sleep: 6, energy: 4),
        _day(2, sleep: 8, energy: 8),
        current,
      ]);
      expect(_method(report, 3, 'B0')['prediction'], 6);
      expect(_method(report, 3, 'M1')['status'], 'no_sleep_feature');
      expect(_method(report, 3, 'M1')['prediction'], isNull);
    }
  });

  test('one participant cannot switch the fixed planned timezone', () {
    expect(
      () => _run([_day(1), _day(3, timezone: 'America/Los_Angeles')]),
      throwsArgumentError,
    );
  });

  test(
    'independently calculated expanding means, latest values and OLS agree',
    () {
      final days = _linearDays();
      final report = _run(days);
      final b0 = _method(report, 3, 'B0');
      final b1 = _method(report, 3, 'B1');
      final m1 = _method(report, 3, 'M1');
      expect((report['rows'] as List).length, 2);
      expect(_row(report, 3)['executionStatus'], 'executed');
      expect(b0['prediction'], 6);
      expect(b0['trainingCount'], 2);
      expect(b1['prediction'], 8);
      expect(b1['trainingCount'], 1);
      expect(b1['trainingOpportunityIds'], [days[1].opportunity.id]);
      expect(m1['status'], 'predicted');
      expect(m1['fit']['intercept'], closeTo(-8, 1e-12));
      expect(m1['fit']['slope'], closeTo(2, 1e-12));
      expect(m1['rawPrediction'], closeTo(6, 1e-12));
      expect(m1['prediction'], closeTo(6, 1e-12));
      expect(m1['trainingCount'], 2);
      expect(m1['trainingOpportunityIds'], [
        days[0].opportunity.id,
        days[1].opportunity.id,
      ]);
      expect(_method(report, 4, 'B0')['prediction'], 6);
      expect(_method(report, 4, 'B1')['prediction'], 6);
      expect(_method(report, 4, 'M1')['trainingCount'], 3);
      expect(_method(report, 4, 'M1')['prediction'], closeTo(10, 1e-12));
    },
  );

  test('own and future labels cannot alter an earlier morning prediction', () {
    final baseline = _run(_linearDays());
    final changed = _run([
      _day(1, sleep: 6, energy: 4),
      _day(2, sleep: 8, energy: 8),
      _day(3, sleep: 7, energy: 1),
      _day(4, sleep: 9, energy: 10),
    ]);
    for (final method in ['B0', 'B1', 'M1']) {
      final before = _method(baseline, 3, method);
      final after = _method(changed, 3, method);
      expect(after['prediction'], before['prediction']);
      expect(after['trainingOpportunityIds'], before['trainingOpportunityIds']);
    }
    expect(_method(changed, 4, 'B0')['prediction'], closeTo(13 / 3, 1e-12));
    expect(_method(changed, 4, 'B1')['prediction'], 1);
  });

  test('late availability enters only subsequent morning history', () {
    final report = _run([
      _day(1, sleep: 6, energy: 4),
      _day(2, sleep: 8, energy: 8, availableAt: _time(3, 12)),
      _day(3, sleep: 7, energy: 6),
      _day(4, sleep: 9, energy: 9),
    ]);
    expect(_method(report, 3, 'B0')['prediction'], 4);
    expect(_method(report, 3, 'B1')['prediction'], 4);
    expect(_method(report, 3, 'M1')['status'], 'insufficient_pairs');
    expect(_method(report, 4, 'B0')['prediction'], 6);
    expect(_method(report, 4, 'M1')['trainingCount'], 3);
  });

  test(
    'a later historical correction cannot retroactively change a prediction',
    () {
      final days = [
        _day(1, sleep: 6, energy: 4, revisedAt: _time(3, 12)),
        _day(2, sleep: 8, energy: 8),
        _day(3, sleep: 7, energy: 6),
        _day(4, sleep: 9, energy: 9),
      ];
      final report = _run(days);
      expect(_method(report, 3, 'B0')['prediction'], 6);
      expect(_method(report, 3, 'M1')['prediction'], closeTo(6, 1e-12));
      expect(
        _method(report, 3, 'M1')['trainingOpportunityIds'],
        contains(days[0].opportunity.id),
      );
      expect(_method(report, 4, 'B0')['prediction'], 7);
      expect(
        _method(report, 4, 'M1')['trainingOpportunityIds'],
        isNot(contains(days[0].opportunity.id)),
      );
    },
  );

  test(
    'final target correction excludes scoring without deleting earlier knowledge',
    () {
      final days = [
        _day(1, sleep: 6, energy: 4),
        _day(2, sleep: 8, energy: 8),
        _day(3, sleep: 7, energy: 6, revisedAt: _time(4, 12)),
        _day(4, sleep: 9, energy: 9),
      ];
      final report = _run(days);
      expect(_row(report, 3)['outcomeStatus'], 'selected_response_revised');
      expect(_row(report, 3)['energy'], isNull);
      expect(_method(report, 3, 'M1')['scored'], isFalse);
      expect(_method(report, 4, 'B0')['prediction'], 6);
      expect(
        _method(report, 4, 'M1')['trainingOpportunityIds'],
        contains(days[2].opportunity.id),
      );
    },
  );

  test('sleep coefficient can be negative without an imposed sign', () {
    final report = _run([
      _day(1, sleep: 6, energy: 8),
      _day(2, sleep: 8, energy: 4),
      _day(3, sleep: 7, energy: 6),
    ]);
    final method = _method(report, 3, 'M1');
    expect(method['fit']['intercept'], closeTo(20, 1e-12));
    expect(method['fit']['slope'], closeTo(-2, 1e-12));
    expect(method['prediction'], closeTo(6, 1e-12));
  });

  test(
    'constant or numerically degenerate sleep abstains instead of fitting',
    () {
      for (final secondSleep in [7.0, 7.0 + 1e-7]) {
        final report = _run([
          _day(1, sleep: 7, energy: 4),
          _day(2, sleep: secondSleep, energy: 8),
          _day(3),
        ]);
        final method = _method(report, 3, 'M1');
        expect(method['status'], 'degenerate_sleep_variance');
        expect(method['prediction'], isNull);
        expect(method['rawPrediction'], isNull);
        expect(method['fit'], isNull);
        expect(method['scored'], isFalse);
      }
    },
  );

  test(
    'raw estimates are retained while actual evaluated output clips to 1–10',
    () {
      final report = _run([
        _day(1, sleep: 5, energy: 1),
        _day(2, sleep: 6, energy: 3),
        _day(3, sleep: 10, energy: null),
        _day(4, sleep: 0.5, energy: 1),
      ]);
      expect(_method(report, 3, 'M1')['rawPrediction'], closeTo(11, 1e-12));
      expect(_method(report, 3, 'M1')['prediction'], 10);
      expect(_method(report, 4, 'M1')['rawPrediction'], closeTo(-8, 1e-12));
      expect(_method(report, 4, 'M1')['prediction'], 1);
      expect(_method(report, 4, 'M1')['absoluteError'], 0);
    },
  );

  test(
    'personal histories are isolated even at identical calendar cutoffs',
    () {
      final days = [
        _day(1, sleep: 6, energy: 4),
        _day(2, sleep: 8, energy: 8),
        _day(3, sleep: 7, energy: 6),
        _day(1, participant: 'invented-person-b', sleep: 6, energy: 1),
        _day(2, participant: 'invented-person-b', sleep: 8, energy: 3),
        _day(3, participant: 'invented-person-b', sleep: 7, energy: 2),
      ];
      final report = _run(days);
      expect(_method(report, 3, 'M1')['prediction'], closeTo(6, 1e-12));
      expect(
        _method(
          report,
          3,
          'M1',
          participant: 'invented-person-b',
        )['prediction'],
        closeTo(2, 1e-12),
      );
      expect(
        _method(
          report,
          3,
          'B0',
          participant: 'invented-person-b',
        )['prediction'],
        2,
      );
      expect(
        _method(
          report,
          3,
          'B1',
          participant: 'invented-person-b',
        )['prediction'],
        3,
      );
      final ids =
          _method(
                report,
                3,
                'M1',
                participant: 'invented-person-b',
              )['trainingOpportunityIds']
              as List;
      expect(ids.toSet(), {days[3].opportunity.id, days[4].opportunity.id});
    },
  );

  test(
    'baselines execute without current sleep while M1 reports feature absence',
    () {
      final report = _run([
        _day(1, sleep: 6, energy: 4),
        _day(2, sleep: 8, energy: 8),
        _day(3, hasSleep: false, energy: 6),
      ]);
      expect(_row(report, 3)['executionStatus'], 'executed');
      expect(_method(report, 3, 'B0')['prediction'], 6);
      expect(_method(report, 3, 'B1')['prediction'], 8);
      expect(_method(report, 3, 'M1')['status'], 'no_sleep_feature');
      expect(_method(report, 3, 'B0')['scored'], isTrue);
      expect(report['methods']['B0']['coverage'], 1);
      expect(report['methods']['M1']['coverage'], 0);
    },
  );

  test(
    'baseline history may use prior outcomes with no sleep and no execution',
    () {
      final report = _run([
        _day(1, hasSleep: false, issued: false, energy: 4),
        _day(2, hasSleep: false, issued: false, energy: 8),
        _day(3),
      ]);
      expect(_method(report, 3, 'B0')['prediction'], 6);
      expect(_method(report, 3, 'B1')['prediction'], 8);
      expect(_method(report, 3, 'M1')['status'], 'insufficient_pairs');
    },
  );

  test(
    'travel excludes baseline scoring even when no sleep snapshot exists',
    () {
      final report = _run([
        _day(1, sleep: 6, energy: 4),
        _day(2, sleep: 8, energy: 8),
        _day(3, hasSleep: false, timezoneChanges: [_time(3, 11)]),
      ]);
      expect(_row(report, 3)['outcomeStatus'], 'timezone_changed');
      expect(_method(report, 3, 'B0')['prediction'], 6);
      expect(_method(report, 3, 'B0')['scored'], isFalse);
      expect(_method(report, 3, 'B1')['scored'], isFalse);
    },
  );

  test('travel-invalid historical outcomes cannot enter baseline history', () {
    final report = _run([
      _day(1, hasSleep: false, energy: 4),
      _day(2, hasSleep: false, energy: 8, timezoneChanges: [_time(2, 11)]),
      _day(3),
    ]);
    expect(_method(report, 3, 'B0')['prediction'], 4);
    expect(_method(report, 3, 'B1')['prediction'], 4);
  });

  test('cold start has explicit abstentions without population fallback', () {
    final report = _run([_day(3)]);
    expect(_method(report, 3, 'B0')['status'], 'no_personal_history');
    expect(_method(report, 3, 'B1')['status'], 'no_personal_history');
    expect(_method(report, 3, 'M1')['status'], 'insufficient_pairs');
    for (final method in ['B0', 'B1', 'M1']) {
      expect(_method(report, 3, method)['prediction'], isNull);
      expect(report['methods'][method]['scored'], 0);
      expect(report['methods'][method]['mae'], isNull);
    }
  });

  test(
    'unexecuted, unsaved and deadline-missed days cannot receive predictions',
    () {
      for (final evaluation in [
        _day(3, issued: false),
        _day(3, durable: false),
        _day(3, durableAt: _time(3, 10, 15)),
        _day(3, issuedAt: _time(3, 9, 59)),
        _day(3, issuedAt: _time(3, 10, 3), durableAt: _time(3, 10, 2)),
      ]) {
        final report = _run([
          _day(1, sleep: 6, energy: 4),
          _day(2, sleep: 8, energy: 8),
          evaluation,
        ]);
        expect(_row(report, 3)['executionStatus'], isNot('executed'));
        for (final method in ['B0', 'B1', 'M1']) {
          expect(_method(report, 3, method)['status'], 'no_execution');
          expect(_method(report, 3, method)['prediction'], isNull);
          expect(_method(report, 3, method)['scored'], isFalse);
        }
      }
    },
  );

  test(
    'missing target is never imputed and prediction coverage keeps its denominator',
    () {
      final report = _run([
        _day(1, sleep: 6, energy: 4),
        _day(2, sleep: 8, energy: 8),
        _day(3, energy: null),
      ]);
      expect(_row(report, 3)['energy'], isNull);
      expect(_row(report, 3)['outcomeStatus'], 'missing_energy');
      for (final method in ['B0', 'B1', 'M1']) {
        final result = _method(report, 3, method);
        expect(result['prediction'], isNotNull);
        expect(result['scored'], isFalse);
        expect(result['signedError'], isNull);
        expect(result['absoluteError'], isNull);
        expect(report['methods'][method]['opportunities'], 1);
        expect(report['methods'][method]['predicted'], 1);
        expect(report['methods'][method]['scored'], 0);
        expect(report['methods'][method]['coverage'], 1);
        expect(report['methods'][method]['mae'], isNull);
      }
    },
  );

  test(
    'summary errors and head-to-head differences use explicit common rows',
    () {
      final report = _run(_linearDays());
      expect(report['methods']['B0']['mae'], closeTo(1.5, 1e-12));
      expect(report['methods']['B0']['meanSignedError'], closeTo(-1.5, 1e-12));
      expect(report['methods']['B1']['mae'], closeTo(2.5, 1e-12));
      expect(report['methods']['B1']['meanSignedError'], closeTo(-0.5, 1e-12));
      expect(report['methods']['M1']['mae'], closeTo(0.5, 1e-12));
      expect(report['methods']['M1']['meanSignedError'], closeTo(0.5, 1e-12));
      final comparison = (report['pairwise'] as List).singleWhere(
        (row) => row['left'] == 'B0' && row['right'] == 'M1',
      );
      expect(comparison['commonScored'], 2);
      expect(comparison['maeDifference'], closeTo(1, 1e-12));
      expect((comparison['opportunityIds'] as List).length, 2);
      expect(
        report['methods']['M1']['macroParticipantMae'],
        closeTo(0.5, 1e-12),
      );
    },
  );

  test(
    'head-to-head sample excludes baseline-only rows without hiding coverage',
    () {
      final report = _run([
        _day(1, sleep: 6, energy: 4),
        _day(2, sleep: 8, energy: 8),
        _day(3, hasSleep: false, energy: 1),
        _day(4, sleep: 7, energy: 6),
      ]);
      expect(report['methods']['B0']['scored'], 2);
      expect(report['methods']['M1']['scored'], 1);
      expect(report['methods']['M1']['coverage'], 0.5);
      final comparison = (report['pairwise'] as List).singleWhere(
        (row) => row['left'] == 'B0' && row['right'] == 'M1',
      );
      expect(comparison['commonScored'], 1);
      expect(comparison['leftMae'], closeTo(5 / 3, 1e-12));
      expect(comparison['rightMae'], closeTo(0, 1e-12));
      expect(comparison['maeDifference'], closeTo(5 / 3, 1e-12));
    },
  );

  test('participant macro MAE gives each scored participant equal weight', () {
    final report = _run([
      ..._linearDays(),
      _day(1, participant: 'invented-person-b', sleep: 6, energy: 1),
      _day(2, participant: 'invented-person-b', sleep: 8, energy: 3),
      _day(3, participant: 'invented-person-b', sleep: 7, energy: 10),
    ]);
    final summary = report['methods']['M1'];
    expect(summary['scored'], 3);
    expect(summary['mae'], closeTo(3, 1e-12));
    expect(summary['macroParticipantMae'], closeTo(4.25, 1e-12));
    final participants = summary['perParticipant'] as List;
    final a = participants.singleWhere(
      (row) => row['participantKey'] == 'invented-person-a',
    );
    final b = participants.singleWhere(
      (row) => row['participantKey'] == 'invented-person-b',
    );
    expect(a['scored'], 2);
    expect(a['mae'], closeTo(0.5, 1e-12));
    expect(b['scored'], 1);
    expect(b['mae'], closeTo(8, 1e-12));
  });

  test(
    'cutoff availability and execution are inclusive; pre-execution travel abstains',
    () {
      final history = [
        _day(1, sleep: 6, energy: 4),
        _day(2, sleep: 8, energy: 8, availableAt: _time(3)),
      ];
      final boundary = _run([
        ...history,
        _day(3, issuedAt: _time(3), durableAt: _time(3)),
      ]);
      expect(_row(boundary, 3)['executionStatus'], 'executed');
      expect(_method(boundary, 3, 'M1')['trainingCount'], 2);
      expect(_method(boundary, 3, 'M1')['prediction'], closeTo(6, 1e-12));
      final travel = _run([
        ...history,
        _day(3, timezoneChanges: [_time(3, 9)]),
      ]);
      expect(_row(travel, 3)['executionStatus'], isNot('executed'));
      for (final method in ['B0', 'B1', 'M1']) {
        expect(_method(travel, 3, method)['status'], 'no_execution');
        expect(_method(travel, 3, method)['scored'], isFalse);
      }
    },
  );

  test(
    'fixture success never authorizes real-data training or app activation',
    () {
      final report = _run(_linearDays());
      expect(report['synthetic'], isTrue);
      expect(report['evidenceKind'], 'synthetic_software_fixture');
      expect(report['modelingReadinessEstablished'], isFalse);
      expect(report['realDataTrainingAllowed'], isFalse);
      expect(report['appModelActivationAllowed'], isFalse);
      expect(report['manifest']['finalHoldout'], isFalse);
      expect(report['manifest']['tuningBudget'], 0);
    },
  );

  test('empty and withdrawn evaluation samples have null rates and errors', () {
    for (final days in [
      <Ai1FixtureDay>[],
      [_day(3, withdrawn: true)],
    ]) {
      final report = _run(days);
      for (final method in ['B0', 'B1', 'M1']) {
        expect(report['methods'][method]['opportunities'], 0);
        expect(report['methods'][method]['coverage'], isNull);
        expect(report['methods'][method]['mae'], isNull);
        expect(report['methods'][method]['macroParticipantMae'], isNull);
      }
      for (final comparison in report['pairwise'] as List) {
        expect(comparison['commonScored'], 0);
        expect(comparison['maeDifference'], isNull);
      }
    }
  });

  test(
    'exact retries and shuffled input produce identical serialized reports',
    () {
      final days = _linearDays();
      expect(
        jsonEncode(_run([days[3], days[1], days[0], days[2], days[1]])),
        jsonEncode(_run(days)),
      );
    },
  );

  test(
    'conflicting duplicate opportunities and captured records fail closed',
    () {
      expect(
        () => _run([..._linearDays(), _day(1, sleep: 6, energy: 5)]),
        throwsArgumentError,
      );
      expect(() => _run([_day(3, synthetic: false)]), throwsArgumentError);
      expect(
        () => _run([_day(1), _day(3, synthetic: false)]),
        throwsArgumentError,
      );
    },
  );

  test(
    'manifest chronology, nonempty identities and raw cutoff bounds are enforced',
    () {
      for (final create in <Ai3SyntheticManifest Function()>[
        () => _manifest(experimentId: ' '),
        () => _manifest(datasetVersion: ''),
        () => _manifest(historyStart: _time(4)),
        () => _manifest(evaluationEnd: _time(3)),
        () => _manifest(evaluationEnd: _time(2)),
        () => _manifest(analysisAsOf: _time(3)),
      ]) {
        expect(
          () => _run(_linearDays(), manifest: create()),
          throwsArgumentError,
        );
      }
      expect(() => _run([_day(5)]), throwsArgumentError);
      expect(
        () => _run([_day(1)], manifest: _manifest(historyStart: _time(2))),
        throwsArgumentError,
      );
    },
  );
}
