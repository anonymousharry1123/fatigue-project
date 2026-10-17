import 'dart:convert';

import 'package:app/src/ai1_dataset_builder.dart';
import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/ai1_records.dart';
import 'package:flutter_test/flutter_test.dart';

final _protocol = Ai1Protocol.draft();

Ai1Opportunity _opportunity({
  Ai1Protocol? protocol,
  String localDate = '2026-10-11',
  String timezone = 'America/Los_Angeles',
  String participantKey = 'synthetic-person-a',
}) => Ai1Opportunity.forDate(
  protocol: protocol ?? _protocol,
  participantKey: participantKey,
  localDate: localDate,
  timezone: timezone,
);

Ai1SleepRevision _sleep(
  Ai1Opportunity opportunity, {
  String participantKey = 'synthetic-person-a',
  String collection = 'signals',
  String sourceId = 'synthetic-sleep-a',
  int revision = 1,
  Ai1SleepSource source = Ai1SleepSource.manual,
  DateTime? endedAt,
  DateTime? availableAt,
  bool availabilityKnown = true,
  double durationHours = 8,
  List<DateTime?> selectionDependencies = const [],
  bool lineageComplete = true,
  bool isMainSleep = true,
  bool deleted = false,
}) => Ai1SleepRevision(
  participantKey: participantKey,
  collection: collection,
  sourceId: sourceId,
  revision: revision,
  source: source,
  endedAt: endedAt ?? opportunity.cutoff.subtract(const Duration(hours: 3)),
  startedAt: opportunity.cutoff.subtract(const Duration(hours: 11)),
  availableAt: availabilityKnown
      ? availableAt ?? opportunity.cutoff.subtract(const Duration(hours: 2))
      : null,
  durationHours: durationHours,
  selectionDependencies: selectionDependencies,
  lineageComplete: lineageComplete,
  isMainSleep: isMainSleep,
  deleted: deleted,
);

Ai1ResponseRevision _response(
  Ai1Opportunity opportunity, {
  Ai1Protocol? protocol,
  String participantKey = 'synthetic-person-a',
  String sourceId = 'synthetic-response-a',
  int revision = 1,
  DateTime? observedAt,
  DateTime? initialSavedAt,
  DateTime? availableAt,
  num? energy = 7,
  String period = 'Evening',
  String? localDate,
  String timezone = 'America/Los_Angeles',
  String? measurement,
  bool lineageComplete = true,
  bool deleted = false,
}) {
  final observed =
      observedAt ?? opportunity.outcomeStart.add(const Duration(hours: 1));
  final saved = initialSavedAt ?? observed.add(const Duration(minutes: 1));
  return Ai1ResponseRevision(
    participantKey: participantKey,
    sourceId: sourceId,
    revision: revision,
    observedAt: observed,
    initialSavedAt: saved,
    availableAt: availableAt ?? saved,
    localDate: localDate ?? '2026-10-11',
    timezone: timezone,
    measurement: measurement ?? (protocol ?? _protocol).measurement,
    period: period,
    energy: energy,
    lineageComplete: lineageComplete,
    deleted: deleted,
  );
}

Ai1FixtureDay _day(
  Ai1Opportunity opportunity, {
  Ai1Protocol? protocol,
  List<Ai1SleepRevision>? sleepRevisions,
  List<Ai1ResponseRevision>? responseRevisions,
  bool synthetic = true,
  bool sleepHistoryComplete = true,
  bool responseHistoryComplete = true,
  bool issue = true,
  bool durableSave = true,
  DateTime? issuedAt,
  DateTime? durableAt,
  List<DateTime> timezoneChanges = const [],
  bool withdrawn = false,
}) => Ai1FixtureDay(
  opportunity: opportunity,
  synthetic: synthetic,
  sleepHistoryComplete: sleepHistoryComplete,
  responseHistoryComplete: responseHistoryComplete,
  sleepRevisions: sleepRevisions ?? [_sleep(opportunity)],
  responseRevisions:
      responseRevisions ?? [_response(opportunity, protocol: protocol)],
  issuedAt: issue
      ? issuedAt ?? opportunity.cutoff.add(const Duration(minutes: 3))
      : null,
  durableAt: issue && durableSave
      ? durableAt ?? opportunity.cutoff.add(const Duration(minutes: 4))
      : null,
  timezoneChanges: timezoneChanges,
  withdrawn: withdrawn,
);

Ai1DatasetReport _build(
  List<Ai1FixtureDay> days, {
  Ai1Protocol? protocol,
  DateTime? asOf,
}) => Ai1DatasetBuilder.buildSynthetic(
  protocol: protocol ?? _protocol,
  days: days,
  asOf: asOf ?? DateTime.utc(2026, 10, 13),
  datasetVersion: 'synthetic-test-v1',
);

void main() {
  group('AI-1 synthetic dataset boundary', () {
    test('a valid fixture pairs raw Energy without authorizing training', () {
      final opportunity = _opportunity();
      final report = _build([_day(opportunity)]);
      final row = report.rows.single;

      expect(row.sleepStatus, 'eligible');
      expect(row.issuanceStatus, 'issued');
      expect(row.outcomeStatus, 'matched');
      expect(row.feature?.durationHours, 8);
      expect(row.energy, 7);
      expect(row.hasPair, isTrue);
      expect(report.fixturePairCount, 1);
      expect(report.trainingEligibleCount, 0);
      expect(report.toJson(), isNotEmpty);
    });

    test('real-data inputs are rejected, including within a mixed batch', () {
      final opportunity = _opportunity();
      expect(
        () => _build([_day(opportunity, synthetic: false)]),
        throwsArgumentError,
      );
      expect(
        () => _build([
          _day(opportunity),
          _day(_opportunity(localDate: '2026-10-12'), synthetic: false),
        ]),
        throwsArgumentError,
      );
    });

    test('an outcome window must be complete at the analysis cutoff', () {
      final opportunity = _opportunity();
      expect(
        () => _build(
          [_day(opportunity)],
          asOf: opportunity.outcomeEnd.subtract(
            const Duration(microseconds: 1),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        _build([
          _day(opportunity),
        ], asOf: opportunity.outcomeEnd).fixturePairCount,
        1,
      );
    });

    test(
      'conflicting copies of one daily opportunity cannot become two rows',
      () {
        final opportunity = _opportunity();
        expect(
          () => _build([
            _day(opportunity),
            _day(
              opportunity,
              responseRevisions: [_response(opportunity, energy: 3)],
            ),
          ]),
          throwsArgumentError,
        );
      },
    );

    test('identical daily opportunities collapse to one auditable row', () {
      final opportunity = _opportunity();
      final report = _build([_day(opportunity), _day(opportunity)]);
      expect(report.rows, hasLength(1));
      expect(report.fixturePairCount, 1);
      expect(report.trainingEligibleCount, 0);
    });

    test(
      'a different timezone cannot create a second opportunity on one date',
      () {
        final losAngeles = _opportunity();
        final newYork = _opportunity(timezone: 'America/New_York');
        expect(losAngeles.id, newYork.id);
        expect(
          () => _build([_day(losAngeles), _day(newYork)]),
          throwsArgumentError,
        );
      },
    );

    test('caller-owned lists cannot mutate retained inputs or report rows', () {
      final opportunity = _opportunity();
      final knownAt = opportunity.cutoff.subtract(const Duration(hours: 1));
      final dependencies = <DateTime?>[knownAt];
      final sleep = _sleep(opportunity, selectionDependencies: dependencies);
      final sleeps = [sleep];
      final responses = [_response(opportunity)];
      final changes = <DateTime>[];
      final day = _day(
        opportunity,
        sleepRevisions: sleeps,
        responseRevisions: responses,
        timezoneChanges: changes,
      );
      final report = _build([day]);

      dependencies[0] = null;
      sleeps.clear();
      responses.clear();
      changes.add(opportunity.cutoff.add(const Duration(hours: 1)));

      expect(day.sleepRevisions, hasLength(1));
      expect(day.responseRevisions, hasLength(1));
      expect(day.timezoneChanges, isEmpty);
      expect(sleep.selectionDependencies, [knownAt]);
      expect(report.rows.single.feature?.selectionDependencies, [knownAt]);
      expect(report.rows.single.hasPair, isTrue);
      expect(_build([day]).fixturePairCount, 1);
      expect(() => day.sleepRevisions.clear(), throwsUnsupportedError);
      expect(() => day.responseRevisions.clear(), throwsUnsupportedError);
      expect(() => day.timezoneChanges.clear(), throwsUnsupportedError);
      expect(
        () => sleep.selectionDependencies[0] = null,
        throwsUnsupportedError,
      );
      expect(() => report.rows.clear(), throwsUnsupportedError);
    });
  });

  group('prospective sleep and issuance', () {
    test(
      'availability at cutoff is included; one microsecond later is not',
      () {
        final opportunity = _opportunity();
        final atCutoff = _build([
          _day(
            opportunity,
            sleepRevisions: [
              _sleep(opportunity, availableAt: opportunity.cutoff),
            ],
          ),
        ]).rows.single;
        final afterCutoff = _build([
          _day(
            opportunity,
            sleepRevisions: [
              _sleep(
                opportunity,
                availableAt: opportunity.cutoff.add(
                  const Duration(microseconds: 1),
                ),
              ),
            ],
          ),
        ]).rows.single;

        expect(atCutoff.hasPair, isTrue);
        expect(afterCutoff.sleepStatus, 'no_eligible_sleep');
        expect(afterCutoff.issuanceStatus, 'no_eligible_sleep');
        expect(afterCutoff.feature, isNull);
      },
    );

    test('sleep must end on the event morning and no later than cutoff', () {
      final opportunity = _opportunity();
      for (final end in [
        opportunity.dayStart.subtract(const Duration(microseconds: 1)),
        opportunity.cutoff.add(const Duration(microseconds: 1)),
      ]) {
        final row = _build([
          _day(
            opportunity,
            sleepRevisions: [_sleep(opportunity, endedAt: end)],
          ),
        ]).rows.single;
        expect(row.sleepStatus, 'no_eligible_sleep');
        expect(row.feature, isNull);
      }
    });

    test('both actual issuance and durable save precede the deadline', () {
      final opportunity = _opportunity();
      final timely = _build([
        _day(
          opportunity,
          issuedAt: opportunity.cutoff,
          durableAt: opportunity.issuanceDeadline.subtract(
            const Duration(microseconds: 1),
          ),
        ),
      ]).rows.single;
      expect(timely.issuanceStatus, 'issued');
      for (final day in [
        _day(
          opportunity,
          issuedAt: opportunity.issuanceDeadline,
          durableAt: opportunity.issuanceDeadline,
        ),
        _day(opportunity, durableAt: opportunity.issuanceDeadline),
      ]) {
        final row = _build([day]).rows.single;
        expect(row.issuanceStatus, 'missed_cutoff');
        expect(row.feature, isNull);
        expect(row.hasPair, isFalse);
      }
    });

    test('missing durability evidence prevents an issued snapshot', () {
      final opportunity = _opportunity();
      final row = _build([_day(opportunity, durableSave: false)]).rows.single;
      expect(row.issuanceStatus, 'save_not_proven');
      expect(row.feature, isNull);
      expect(row.hasPair, isFalse);
    });

    test('durable completion cannot precede the attempted issuance', () {
      final opportunity = _opportunity();
      final row = _build([
        _day(
          opportunity,
          issuedAt: opportunity.cutoff.add(const Duration(minutes: 3)),
          durableAt: opportunity.cutoff.add(const Duration(minutes: 2)),
        ),
      ]).rows.single;
      expect(row.issuanceStatus, 'save_not_proven');
      expect(row.feature, isNull);
      expect(row.hasPair, isFalse);
    });

    test('an unissued opportunity retains observed outcome completion', () {
      final opportunity = _opportunity();
      final report = _build([_day(opportunity, issue: false)]);
      final row = report.rows.single;
      expect(row.issuanceStatus, 'not_issued');
      expect(row.outcomeStatus, 'matched');
      expect(row.energy, 7);
      expect(row.feature, isNull);
      expect(row.hasPair, isFalse);
      expect(report.fixturePairCount, 0);
    });

    test('later sleep corrections cannot improve a frozen earlier feature', () {
      final opportunity = _opportunity();
      final row = _build([
        _day(
          opportunity,
          sleepRevisions: [
            _sleep(opportunity),
            _sleep(
              opportunity,
              revision: 2,
              durationHours: 6,
              availableAt: opportunity.cutoff.add(const Duration(hours: 3)),
            ),
          ],
        ),
      ]).rows.single;
      expect(row.feature?.revision, 1);
      expect(row.feature?.durationHours, 8);
      expect(row.hasPair, isTrue);
    });

    test('the latest known pre-cutoff revision supplies the feature', () {
      final opportunity = _opportunity();
      final row = _build([
        _day(
          opportunity,
          sleepRevisions: [
            _sleep(opportunity),
            _sleep(
              opportunity,
              revision: 2,
              durationHours: 6,
              availableAt: opportunity.cutoff.subtract(
                const Duration(minutes: 1),
              ),
            ),
          ],
        ),
      ]).rows.single;
      expect(row.feature?.revision, 2);
      expect(row.feature?.durationHours, 6);
    });

    test(
      'exact sleep duplicates collapse but conflicting revisions abstain',
      () {
        final opportunity = _opportunity();
        final duplicate = _sleep(opportunity);
        expect(
          _build([
            _day(opportunity, sleepRevisions: [duplicate, duplicate]),
          ]).rows.single.hasPair,
          isTrue,
        );
        final conflict = _build([
          _day(
            opportunity,
            sleepRevisions: [duplicate, _sleep(opportunity, durationHours: 6)],
          ),
        ]).rows.single;
        expect(conflict.sleepStatus, 'conflicting_sleep_revision');
        expect(conflict.feature, isNull);
      },
    );

    test('identical source IDs in different collections remain distinct', () {
      final opportunity = _opportunity();
      final row = _build([
        _day(
          opportunity,
          sleepRevisions: [
            _sleep(opportunity, collection: 'manual-a'),
            _sleep(opportunity, collection: 'manual-b'),
          ],
        ),
      ]).rows.single;
      expect(row.sleepStatus, 'ambiguous_sleep');
      expect(row.feature, isNull);
    });

    test('the frozen source policy never falls back to a different source', () {
      final opportunity = _opportunity();
      final health = _sleep(opportunity, source: Ai1SleepSource.appleHealth);
      final manualOnly = _build([
        _day(opportunity, sleepRevisions: [health]),
      ]).rows.single;
      expect(manualOnly.sleepStatus, 'no_eligible_sleep');

      final healthProtocol = Ai1Protocol.draft(
        sleepSource: Ai1SleepSource.appleHealth,
      );
      final healthOpportunity = _opportunity(protocol: healthProtocol);
      final healthOnly = _build([
        _day(
          healthOpportunity,
          protocol: healthProtocol,
          sleepRevisions: [
            _sleep(healthOpportunity, source: Ai1SleepSource.appleHealth),
          ],
        ),
      ], protocol: healthProtocol).rows.single;
      expect(healthOnly.hasPair, isTrue);
      expect(healthOnly.feature?.source, Ai1SleepSource.appleHealth);
      expect(
        _build([
          _day(healthOpportunity, protocol: healthProtocol),
        ], protocol: healthProtocol).rows.single.sleepStatus,
        'no_eligible_sleep',
      );
    });

    test('availability includes source-selection dependencies', () {
      final opportunity = _opportunity();
      for (final dependencies in <List<DateTime?>>[
        [null],
        [opportunity.cutoff.add(const Duration(microseconds: 1))],
      ]) {
        final row = _build([
          _day(
            opportunity,
            sleepRevisions: [
              _sleep(opportunity, selectionDependencies: dependencies),
            ],
          ),
        ]).rows.single;
        expect(row.feature, isNull);
        expect(row.hasPair, isFalse);
      }
      expect(
        _build([
          _day(
            opportunity,
            sleepRevisions: [_sleep(opportunity, availabilityKnown: false)],
          ),
        ]).rows.single.sleepStatus,
        'unknown_sleep_availability',
      );
    });

    test(
      'incomplete sleep history or revision lineage cannot certify inputs',
      () {
        final opportunity = _opportunity();
        for (final day in [
          _day(opportunity, sleepHistoryComplete: false),
          _day(
            opportunity,
            sleepRevisions: [_sleep(opportunity, lineageComplete: false)],
          ),
          _day(opportunity, sleepRevisions: [_sleep(opportunity, revision: 2)]),
        ]) {
          final row = _build([day]).rows.single;
          expect(row.sleepStatus, 'sleep_lineage_incomplete');
          expect(row.feature, isNull);
        }
      },
    );

    test('naps and invalid durations cannot become main-sleep features', () {
      final opportunity = _opportunity();
      expect(
        _build([
          _day(
            opportunity,
            sleepRevisions: [_sleep(opportunity, isMainSleep: false)],
          ),
        ]).rows.single.sleepStatus,
        'no_eligible_sleep',
      );
      for (final hours in [0.0, 16.01, double.nan, double.infinity]) {
        final row = _build([
          _day(
            opportunity,
            sleepRevisions: [_sleep(opportunity, durationHours: hours)],
          ),
        ]).rows.single;
        expect(row.sleepStatus, 'invalid_sleep');
        expect(row.feature, isNull);
      }
    });

    test('sleep deletion invalidates even a previously available feature', () {
      final opportunity = _opportunity();
      final row = _build([
        _day(
          opportunity,
          sleepRevisions: [
            _sleep(opportunity),
            _sleep(
              opportunity,
              revision: 2,
              availableAt: opportunity.outcomeEnd.add(const Duration(days: 2)),
              deleted: true,
            ),
          ],
        ),
      ]).rows.single;
      expect(row.sleepStatus, 'sleep_deleted');
      expect(row.feature, isNull);
      expect(row.hasPair, isFalse);
    });

    test(
      'deletion cannot hide a former candidate by changing its kind or day',
      () {
        final opportunity = _opportunity();
        for (final deletion in [
          _sleep(opportunity, revision: 2, isMainSleep: false, deleted: true),
          _sleep(
            opportunity,
            revision: 2,
            endedAt: opportunity.dayStart.subtract(const Duration(hours: 1)),
            deleted: true,
          ),
        ]) {
          final row = _build([
            _day(
              opportunity,
              sleepRevisions: [
                _sleep(opportunity),
                deletion,
                _sleep(opportunity, sourceId: 'synthetic-fallback-sleep'),
              ],
            ),
          ]).rows.single;
          expect(row.sleepStatus, 'sleep_deleted');
          expect(row.feature, isNull);
          expect(row.hasPair, isFalse);
        }
      },
    );
  });

  group('prospective outcome matching', () {
    test('18:00 is inclusive and 22:00 is exclusive', () {
      final opportunity = _opportunity();
      final start = _build([
        _day(
          opportunity,
          responseRevisions: [
            _response(
              opportunity,
              observedAt: opportunity.outcomeStart,
              initialSavedAt: opportunity.outcomeStart,
            ),
          ],
        ),
      ]).rows.single;
      final end = _build([
        _day(
          opportunity,
          responseRevisions: [
            _response(
              opportunity,
              observedAt: opportunity.outcomeEnd,
              initialSavedAt: opportunity.outcomeEnd,
            ),
          ],
        ),
      ]).rows.single;
      expect(start.outcomeStatus, 'matched');
      expect(end.outcomeStatus, 'no_response_in_window');
      expect(end.energy, isNull);
    });

    test('a response observed in-window but saved at 22:00 is late', () {
      final opportunity = _opportunity();
      final row = _build([
        _day(
          opportunity,
          responseRevisions: [
            _response(
              opportunity,
              observedAt: opportunity.outcomeEnd.subtract(
                const Duration(minutes: 1),
              ),
              initialSavedAt: opportunity.outcomeEnd,
            ),
          ],
        ),
      ]).rows.single;
      expect(row.outcomeStatus, 'no_response_in_window');
      expect(row.hasPair, isFalse);
    });

    test('delayed upload retains a proven in-window original durable save', () {
      final opportunity = _opportunity();
      final uploadedAt = opportunity.outcomeEnd.add(const Duration(hours: 1));
      final row = _build([
        _day(
          opportunity,
          responseRevisions: [_response(opportunity, availableAt: uploadedAt)],
        ),
      ], asOf: uploadedAt).rows.single;
      expect(row.outcomeStatus, 'matched');
      expect(row.energy, 7);
      expect(row.hasPair, isTrue);
    });

    test(
      'the first missing or invalid Energy never falls through to a later answer',
      () {
        final opportunity = _opportunity();
        for (final energy in <num?>[null, 0, 11, 5.5, double.nan]) {
          final row = _build([
            _day(
              opportunity,
              responseRevisions: [
                _response(opportunity, energy: energy),
                _response(
                  opportunity,
                  sourceId: 'synthetic-later-response',
                  observedAt: opportunity.outcomeStart.add(
                    const Duration(hours: 2),
                  ),
                  energy: 8,
                ),
              ].reversed.toList(),
            ),
          ]).rows.single;
          expect(
            row.outcomeStatus,
            energy == null ? 'missing_energy' : 'invalid_energy',
          );
          expect(row.responseId, 'synthetic-response-a');
          expect(row.energy, isNull);
          expect(row.hasPair, isFalse);
        }
      },
    );

    test(
      'selection uses times then source ID without reading rating values',
      () {
        final opportunity = _opportunity();
        final early = _response(
          opportunity,
          sourceId: 'synthetic-a',
          energy: 2,
        );
        final tied = _response(opportunity, sourceId: 'synthetic-z', energy: 9);
        for (final responses in [
          [tied, early],
          [early, tied],
        ]) {
          final row = _build([
            _day(opportunity, responseRevisions: responses),
          ]).rows.single;
          expect(row.responseId, 'synthetic-a');
          expect(row.energy, 2);
        }
      },
    );

    test(
      'known answer revisions exclude the selected target without replacement',
      () {
        final opportunity = _opportunity();
        final row = _build([
          _day(
            opportunity,
            responseRevisions: [
              _response(opportunity),
              _response(
                opportunity,
                revision: 2,
                availableAt: opportunity.outcomeEnd.add(
                  const Duration(hours: 1),
                ),
                energy: 4,
              ),
              _response(
                opportunity,
                sourceId: 'synthetic-later-response',
                observedAt: opportunity.outcomeStart.add(
                  const Duration(hours: 2),
                ),
                energy: 8,
              ),
            ],
          ),
        ]).rows.single;
        expect(row.outcomeStatus, 'selected_response_revised');
        expect(row.responseId, 'synthetic-response-a');
        expect(row.energy, isNull);
        expect(row.hasPair, isFalse);
      },
    );

    test(
      'a future correction is ignored at asOf, while deletion still applies',
      () {
        final opportunity = _opportunity();
        final asOf = opportunity.outcomeEnd;
        final future = asOf.add(const Duration(hours: 1));
        final corrected = _build([
          _day(
            opportunity,
            responseRevisions: [
              _response(opportunity),
              _response(
                opportunity,
                revision: 2,
                availableAt: future,
                energy: 4,
              ),
            ],
          ),
        ], asOf: asOf).rows.single;
        expect(corrected.outcomeStatus, 'matched');
        expect(corrected.energy, 7);

        final deleted = _build([
          _day(
            opportunity,
            responseRevisions: [
              _response(opportunity),
              _response(
                opportunity,
                revision: 2,
                availableAt: future,
                deleted: true,
              ),
            ],
          ),
        ], asOf: asOf).rows.single;
        expect(deleted.outcomeStatus, 'selected_response_deleted');
        expect(deleted.energy, isNull);
        expect(deleted.hasPair, isFalse);
      },
    );

    test(
      'exact response duplicates collapse and contradictory originals abstain',
      () {
        final opportunity = _opportunity();
        final response = _response(opportunity);
        expect(
          _build([
            _day(opportunity, responseRevisions: [response, response]),
          ]).rows.single.hasPair,
          isTrue,
        );
        final conflict = _build([
          _day(
            opportunity,
            responseRevisions: [response, _response(opportunity, energy: 4)],
          ),
        ]).rows.single;
        expect(conflict.outcomeStatus, 'conflicting_response_revision');
        expect(conflict.energy, isNull);
      },
    );

    test(
      'incomplete response history or missing original revisions are explicit',
      () {
        final opportunity = _opportunity();
        for (final day in [
          _day(opportunity, responseHistoryComplete: false),
          _day(
            opportunity,
            responseRevisions: [_response(opportunity, lineageComplete: false)],
          ),
          _day(
            opportunity,
            responseRevisions: [_response(opportunity, revision: 2)],
          ),
        ]) {
          final row = _build([day]).rows.single;
          expect(row.outcomeStatus, 'response_lineage_incomplete');
          expect(row.energy, isNull);
          expect(row.hasPair, isFalse);
        }
      },
    );

    test(
      'Morning and incompatible definitions cannot label an Evening event',
      () {
        final opportunity = _opportunity();
        for (final response in [
          _response(opportunity, period: 'Morning'),
          _response(opportunity, measurement: 'different-definition'),
          _response(opportunity, participantKey: 'synthetic-person-b'),
        ]) {
          final row = _build([
            _day(opportunity, responseRevisions: [response]),
          ]).rows.single;
          expect(row.outcomeStatus, 'no_response_in_window');
          expect(row.energy, isNull);
        }
      },
    );

    test(
      'matching requires the complete snapshot despite equal version strings',
      () {
        final opportunity = _opportunity();
        final changes = <void Function(Map<String, dynamic>)>[
          (snapshot) => snapshot['sharedHeading'] = 'How did you feel today?',
          (snapshot) =>
              ((snapshot['items'] as List)[1]['anchors'] as Map)['5'] =
                  'different fatigue anchor',
          (snapshot) => snapshot['language'] = 'es',
          (snapshot) {
            final items = snapshot['items'] as List;
            final first = items[0];
            items[0] = items[1];
            items[1] = first;
          },
        ];
        final original =
            jsonDecode(_protocol.measurement) as Map<String, dynamic>;
        for (final change in changes) {
          final snapshot =
              jsonDecode(_protocol.measurement) as Map<String, dynamic>;
          change(snapshot);
          expect(snapshot['version'], original['version']);
          final row = _build([
            _day(
              opportunity,
              responseRevisions: [
                _response(
                  opportunity,
                  measurement: Ai1Protocol.canonicalMeasurement(snapshot),
                ),
              ],
            ),
          ]).rows.single;
          expect(row.outcomeStatus, 'no_response_in_window');
          expect(row.energy, isNull);
          expect(row.hasPair, isFalse);
        }
      },
    );
  });

  group('calendar and privacy boundaries', () {
    test(
      'invalid dates and unknown, skipped or ambiguous zone boundaries reject',
      () {
        expect(
          () => _opportunity(localDate: '2026-02-30'),
          throwsFormatException,
        );
        expect(
          () => _opportunity(timezone: 'Unknown/Nowhere'),
          throwsFormatException,
        );
        expect(
          () => _opportunity(localDate: '2011-12-30', timezone: 'Pacific/Apia'),
          throwsFormatException,
        );
        // Havana's autumn rollback repeats local midnight on this date.
        expect(
          () =>
              _opportunity(localDate: '2026-11-01', timezone: 'America/Havana'),
          throwsFormatException,
        );
      },
    );

    test('a timezone change after issuance excludes the primary target', () {
      final opportunity = _opportunity();
      final row = _build([
        _day(
          opportunity,
          timezoneChanges: [opportunity.cutoff.add(const Duration(hours: 2))],
        ),
      ]).rows.single;
      expect(row.outcomeStatus, 'timezone_changed');
      expect(row.energy, isNull);
      expect(row.hasPair, isFalse);
    });

    test(
      'DST calendar days use real zone boundaries rather than 24-hour shifts',
      () {
        final spring = _opportunity(localDate: '2026-03-08');
        final autumn = _opportunity(localDate: '2026-11-01');
        expect(spring.dayStart, DateTime.utc(2026, 3, 8, 8));
        expect(spring.cutoff, DateTime.utc(2026, 3, 8, 17));
        expect(spring.cutoff.difference(spring.dayStart).inHours, 9);
        expect(spring.outcomeStart, DateTime.utc(2026, 3, 9, 1));
        expect(autumn.dayStart, DateTime.utc(2026, 11, 1, 7));
        expect(autumn.cutoff, DateTime.utc(2026, 11, 1, 18));
        expect(autumn.cutoff.difference(autumn.dayStart).inHours, 11);
        expect(autumn.outcomeStart, DateTime.utc(2026, 11, 2, 2));
        for (final entry in [(spring, '2026-03-08'), (autumn, '2026-11-01')]) {
          final report = _build([
            _day(
              entry.$1,
              responseRevisions: [_response(entry.$1, localDate: entry.$2)],
            ),
          ], asOf: entry.$1.outcomeEnd);
          expect(report.fixturePairCount, 1);
        }
      },
    );

    test('withdrawal removes derived features and targets', () {
      final opportunity = _opportunity();
      final report = _build([_day(opportunity, withdrawn: true)]);
      final row = report.rows.single;
      expect(row.issuanceStatus, 'withdrawn');
      expect(row.outcomeStatus, 'withdrawn');
      expect(row.feature, isNull);
      expect(row.energy, isNull);
      expect(row.hasPair, isFalse);
      expect(report.trainingEligibleCount, 0);
      expect(report.fixturePairCount, 0);
    });
  });
}
