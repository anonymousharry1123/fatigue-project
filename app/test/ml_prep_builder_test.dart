import 'dart:convert';

import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'consent blocks examples; check-ins never manufacture outcome labels',
    () {
      final checkIn = _checkIn(10, 20);
      final denied = MlPrepBuilder.build(
        _snapshot(
          checkIns: [checkIn],
          outcomes: [_energy(checkIn)],
          consent: false,
        ),
      );
      expect(denied.examples, isEmpty);
      expect(denied.energyReady, isFalse);
      expect(_reasons(denied), contains('consent_required'));
      final noLabels = MlPrepBuilder.build(_snapshot(checkIns: [checkIn]));
      expect(noLabels.examples, isEmpty);
      expect(_counts(noLabels)['eligibleEnergyLabels'], 0);
    },
  );

  test('synthetic and uncertain source rows cannot become training labels', () {
    final synthetic = {
      ..._checkIn(10, 20),
      'note': 'Seeded fake account history',
    };
    final uncertain = {..._checkIn(11, 20), 'id': 'unknown-check-in'};
    final real = _checkIn(12, 20);
    final report = MlPrepBuilder.build(
      _snapshot(
        signals: [
          {..._signal(12, 9, 'hydration', 2), 'note': 'Synthetic July fixture'},
        ],
        checkIns: [synthetic, uncertain, real],
        outcomes: [_energy(synthetic), _energy(uncertain), _energy(real)],
      ),
    );
    expect(report.examples, hasLength(1));
    expect(report.examples.single.features['hydration'], isNull);
    final reasons = _rejected(report);
    expect(
      reasons,
      containsAll([
        'synthetic_provenance',
        'synthetic_source',
        'uncertain_source',
      ]),
    );
    expect((report.toJson()['provenance'] as Map)['checkIns'], {
      'genuine': 1,
      'synthetic': 1,
      'uncertain': 1,
    });
  });

  test('Energy uses the fixed 1–10 scale and excludes its own check-in', () {
    final low = _checkIn(10, 10, energy: 1, mood: 10, stress: 1);
    final high = _checkIn(11, 10, energy: 10);
    final report = MlPrepBuilder.build(
      _snapshot(checkIns: [low, high], outcomes: [_energy(low), _energy(high)]),
    );
    expect(report.examples.map((row) => row.target), [0, 100]);
    expect(report.examples.first.reference, 60);
    expect(report.examples.first.features['mood'], isNull);
    expect(report.examples.first.features['stress'], isNull);
    expect(report.examples.first.missingness['hydration'], isTrue);
    expect(report.examples.first.features, hasLength(8));
    expect(jsonDecode(jsonEncode(report.toJson())), isA<Map>());
    expect(report.toJson().containsKey('uid'), isFalse);
  });

  test('future observations, late edits and end-of-day totals do not leak', () {
    final checkIn = _checkIn(10, 10);
    final report = MlPrepBuilder.build(
      _snapshot(
        signals: [
          _signal(10, 11, 'exercise', 1),
          {..._signal(10, 8, 'hydration', 3), 'updatedAt': _time(10, 12)},
          {..._signal(10, 23, 'steps', 9000), 'source': 'healthKit'},
        ],
        checkIns: [checkIn],
        outcomes: [_energy(checkIn)],
      ),
    );
    final row = report.examples.single;
    expect(row.reference, 60);
    expect(row.features['movement'], isNull);
    expect(row.features['hydration'], isNull);
    expect(row.featureSources.values.expand((ids) => ids), isEmpty);
  });

  test(
    'learned check-in context stays on the observation day while reference retains its history',
    () {
      final previous = {..._checkIn(9, 20, mood: 10, stress: 1)}
        ..remove('createdAt');
      final current = _checkIn(10, 10);
      final report = MlPrepBuilder.build(
        _snapshot(checkIns: [previous, current], outcomes: [_energy(current)]),
      );
      final row = report.examples.single;
      expect(row.features['mood'], isNull);
      expect(row.features['stress'], isNull);
      expect(row.reference, 77);
      expect(row.warnings, contains('historical_availability_unknown'));
    },
  );

  test(
    'Cognitive keeps ms with no score residual and excludes label reaction',
    () {
      final reaction = _signal(10, 10, 'reactionTime', 250);
      final historical = [
        for (var day = 2; day <= 8; day++) _signal(day, 9, 'reactionTime', 300),
      ];
      final report = MlPrepBuilder.build(
        _snapshot(
          signals: [...historical, reaction],
          outcomes: [_reaction(reaction)],
        ),
      );
      final row = report.examples.single;
      expect(row.head, 'cognitive');
      expect(row.label, 250);
      expect(row.labelUnit, 'ms');
      expect(row.target, isNull);
      expect(row.reference, isNull);
      expect(row.features, hasLength(8));
      expect(row.features['priorReactionTrend'], 0);
      expect(
        row.featureSources.values
            .expand((ids) => ids)
            .any((id) => id.contains(reaction['id'] as String)),
        isFalse,
      );
      expect(report.cognitiveReady, isFalse);
      expect(_reasons(report, 'cognitive'), contains('target_units_undefined'));
    },
  );

  test('baselines use only earlier in-window days and disclose cold-start', () {
    final cold = _checkIn(2, 20);
    final warm = _checkIn(10, 20);
    final history = <Map<String, dynamic>>[
      for (var day = 2; day <= 10; day++) ...[
        _signal(day, 7, 'sleep', 8),
        {..._signal(day, 8, 'hrv', day == 10 ? 60 : 50), 'source': 'healthKit'},
        {..._signal(day, 8, 'restingHeartRate', 60), 'source': 'healthKit'},
      ],
    ];
    PrepReport build(List<Map<String, dynamic>> signals) => MlPrepBuilder.build(
      _snapshot(
        signals: signals,
        checkIns: [cold, warm],
        outcomes: [_energy(cold), _energy(warm)],
      ),
    );
    final report = build(history);
    expect(report.examples.first.features['sleepDeviation'], isNull);
    expect(
      report.examples.first.warnings,
      contains('baseline_cold_start_or_missing'),
    );
    expect(report.examples.last.features['sleepDeviation'], 0);
    expect(
      report.examples.last.features['recoveryDeviation'],
      closeTo(.4, .0001),
    );
    final withFuture = build([
      ...history,
      {..._signal(30, 8, 'hrv', 500), 'source': 'healthKit'},
      {..._signal(1, 8, 'sleep', 1), 'source': 'healthKit'},
    ]);
    expect(withFuture.examples.last.features, report.examples.last.features);
    expect(withFuture.examples.last.reference, report.examples.last.reference);
    expect(_rejected(withFuture), contains('outside_window'));
  });

  test('whole-day chronological split keeps paired outcomes together', () {
    final signals = [for (var day = 10; day <= 23; day++) ..._context(day)];
    final checks = [
      for (var day = 10; day <= 23; day++) ...[
        _checkIn(day, 8),
        _checkIn(day, 18),
        _checkIn(day, 20),
      ],
    ];
    final outcomes = [
      for (final check in checks.where(
        (row) => !(row['timestamp'] as String).contains('T08:'),
      ))
        _energy(check),
    ];
    final report = MlPrepBuilder.build(
      _snapshot(signals: signals, checkIns: checks, outcomes: outcomes),
    );
    // This UTC fixture is ready on a UTC device; a different device zone must
    // explicitly block replay rather than silently treat remapped dates as exact.
    expect(report.energyReady, report.toJson()['hostTimezoneCompatible']);
    expect(
      _reasons(report),
      report.energyReady ? isEmpty : ['host_timezone_mismatch'],
    );
    expect(_counts(report)['energyLabeledDays'], 14);
    final status = (report.toJson()['readiness'] as Map)['energy'] as Map;
    expect(status['holdoutDays'], ['2026-07-21', '2026-07-22', '2026-07-23']);
    expect((status['trainingDays'] as List).last, '2026-07-20');
    for (var day = 10; day <= 23; day++) {
      final rows = report.examples.where((row) => row.day.endsWith('-$day'));
      expect(rows, hasLength(2));
      expect(rows.map((row) => row.split).toSet(), hasLength(1));
    }
    final changedHoldout = MlPrepBuilder.build(
      _snapshot(
        signals: [
          for (final signal in signals)
            if ((signal['timestamp'] as String).startsWith('2026-07-23') &&
                signal['type'] == 'caffeine')
              {...signal, 'value': 999}
            else
              signal,
        ],
        checkIns: checks,
        outcomes: outcomes,
      ),
    );
    expect(
      changedHoldout.examples.first.features,
      report.examples.first.features,
    );
    expect(
      changedHoldout.toJson()['normalization'],
      report.toJson()['normalization'],
    );
  });

  test('unverified availability remains inspectable but blocks readiness', () {
    final checks = [for (var day = 10; day <= 23; day++) _checkIn(day, 20)];
    final report = MlPrepBuilder.build(
      _snapshot(
        signals: [
          for (var day = 10; day <= 23; day++)
            for (final record in _context(day))
              {...record}..remove('createdAt'),
        ],
        checkIns: checks,
        outcomes: checks.map(_energy).toList(),
      ),
    );
    expect(report.examples, hasLength(14));
    expect(report.energyReady, isFalse);
    expect(_reasons(report), contains('historical_availability_unknown'));
    expect(
      report.examples.first.warnings,
      contains('historical_availability_unknown'),
    );
  });

  test(
    'missing differs from explicit zero and workouts take precedence over steps',
    () {
      final check = _checkIn(10, 20);
      final report = MlPrepBuilder.build(
        _snapshot(
          signals: [
            _signal(10, 8, 'exercise', 0),
            {..._signal(10, 9, 'steps', 10000), 'source': 'healthKit'},
            _signal(10, 9, 'caffeine', 0),
          ],
          checkIns: [check],
          outcomes: [_energy(check)],
        ),
      );
      final row = report.examples.single;
      expect(row.features['movement'], 0);
      expect(row.features['caffeine'], 0);
      expect(row.missingness['caffeine'], isFalse);
      expect(row.features['hydration'], isNull);
      expect(row.featureSources['movement']!.single, contains('exercise'));
    },
  );

  test(
    'duplicate labels, invalid units/ranges and mismatched joins are rejected',
    () {
      final check = _checkIn(10, 20);
      final outcome = _energy(check);
      final report = MlPrepBuilder.build(
        _snapshot(
          checkIns: [check],
          outcomes: [
            outcome,
            {...outcome, 'id': 'duplicate-label'},
            {...outcome, 'id': 'bad-unit', 'unit': 'ms'},
            {...outcome, 'id': 'bad-range', 'value': 11},
            {...outcome, 'id': 'bad-source', 'sourceId': 'missing'},
            {...outcome, 'id': 'bad-link', 'value': 9},
            {...outcome, 'id': 'bad-consent', 'consentVersion': 2},
          ],
        ),
      );
      expect(report.examples, hasLength(1));
      expect(
        _rejected(report),
        containsAll([
          'duplicate_source_label',
          'invalid_record',
          'missing_source',
          'source_value_or_type_mismatch',
          'consent_version_mismatch',
        ]),
      );
    },
  );

  test('hitting any document cap produces no examples', () {
    final check = _checkIn(10, 20);
    final report = MlPrepBuilder.build(
      _snapshot(
        signals: [
          for (var i = 0; i < 1500; i++)
            {
              ..._signal(10, 9, 'hydration', 1),
              'id': 'healthkit-water-$i',
              'source': 'healthKit',
            },
        ],
        checkIns: [check],
        outcomes: [_energy(check)],
      ),
    );
    expect(report.examples, isEmpty);
    expect(_reasons(report), contains('document_cap_reached'));
  });

  test('foreign account markers and unverified coach sources fail closed', () {
    final check = _checkIn(10, 20);
    final report = MlPrepBuilder.build(
      _snapshot(
        checkIns: [check],
        outcomes: [
          {..._energy(check), 'uid': 'another-account'},
          {
            ..._energy(check),
            'id': 'energy-coach-arbitrary',
            'source': 'coach',
            'sourceId': 'arbitrary',
          },
        ],
      ),
    );
    expect(report.examples, isEmpty);
    expect(
      _rejected(report),
      containsAll(['foreign_account', 'coach_source_unverified']),
    );
    expect(jsonEncode(report.toJson()), isNot(contains('another-account')));
  });

  test(
    'reference-only heart baseline history also requires known availability',
    () {
      final checks = [for (var day = 10; day <= 23; day++) _checkIn(day, 20)];
      final report = MlPrepBuilder.build(
        _snapshot(
          signals: [
            for (var day = 2; day <= 8; day++)
              {..._signal(day, 8, 'hrv', 50), 'source': 'healthKit'}
                ..remove('createdAt'),
            for (var day = 10; day <= 23; day++) ...[
              ..._context(day),
              {..._signal(day, 8, 'hrv', 60), 'source': 'healthKit'},
            ],
          ],
          checkIns: checks,
          outcomes: checks.map(_energy).toList(),
        ),
      );
      expect(report.examples.first.features['recoveryDeviation'], isNull);
      expect(
        report.examples.first.warnings,
        contains('historical_availability_unknown'),
      );
      expect(report.energyReady, isFalse);
      expect(_reasons(report), contains('historical_availability_unknown'));
    },
  );

  test('account timezone governs local day joins even on a different host', () {
    final check = {..._checkIn(10, 1), 'timestamp': '2026-07-10T01:00:00Z'};
    final signal = {
      ..._signal(9, 23, 'hydration', 2),
      'timestamp': '2026-07-09T23:00:00Z',
      'createdAt': '2026-07-09T23:00:00Z',
    };
    final report = MlPrepBuilder.build(
      _snapshot(
        window: PrepWindow.endingOn(
          DateTime(2026, 7, 31),
          timezone: 'America/Los_Angeles',
        ),
        signals: [signal],
        checkIns: [check],
        outcomes: [_energy(check)],
      ),
    );
    expect(report.examples.single.day, '2026-07-09');
    expect(report.examples.single.features['hydration'], 0);
    expect(report.examples.single.reference, 60);
  });

  test(
    'equal-timestamp ties and rejection order are stable across cache reorder',
    () {
      final observed = _checkIn(10, 20);
      final first = _checkIn(10, 8, mood: 2);
      final second = {..._checkIn(10, 8, mood: 8), 'id': '${first['id']}-b'};
      final signals = [
        _signal(10, 7, 'sleep', 6),
        {
          ..._signal(10, 7, 'sleep', 9),
          'id': '${_signal(10, 7, 'sleep', 9)['id']}-b',
        },
        {..._signal(10, 7, 'caffeine', 1), 'id': 'seed-rejected-b'},
        {..._signal(10, 7, 'hydration', 2), 'id': 'seed-rejected-a'},
      ];
      final checks = [first, second, observed];
      final original = _snapshot(
        signals: signals,
        checkIns: checks,
        outcomes: [_energy(observed)],
      );
      final reordered = _snapshot(
        signals: signals.reversed.toList(),
        checkIns: checks.reversed.toList(),
        outcomes: [_energy(observed)],
      );
      expect(original.fingerprint, reordered.fingerprint);
      expect(
        MlPrepBuilder.build(original).toJson(),
        MlPrepBuilder.build(reordered).toJson(),
      );
    },
  );

  test('mismatched historical host timezone offsets block precise replay', () {
    final hostOffset = DateTime.utc(2026, 7, 10, 12).toLocal().timeZoneOffset;
    final mismatchedZone = hostOffset == Duration.zero
        ? 'America/Los_Angeles'
        : 'UTC';
    final check = _checkIn(10, 20);
    final report = MlPrepBuilder.build(
      _snapshot(
        window: PrepWindow.endingOn(
          DateTime(2026, 7, 31),
          timezone: mismatchedZone,
        ),
        signals: _context(10),
        checkIns: [check],
        outcomes: [_energy(check)],
      ),
    );
    expect(report.toJson()['hostTimezoneCompatible'], isFalse);
    expect(report.energyReady, isFalse);
    expect(_reasons(report), contains('host_timezone_mismatch'));
    expect(_reasons(report, 'cognitive'), contains('host_timezone_mismatch'));
    expect(report.examples.single.warnings, contains('host_timezone_mismatch'));
  });

  test('timezone compatibility audits the window across a DST transition', () {
    final window = PrepWindow.endingOn(
      DateTime(2026, 3, 20),
      timezone: 'America/Phoenix',
    );
    final expectedMatch =
        List.generate(30, (i) => window.start.add(Duration(days: i))).every(
          (at) =>
              window.localTime(at).timeZoneOffset ==
              at.toLocal().timeZoneOffset,
        );
    final report = MlPrepBuilder.build(_snapshot(window: window));
    expect(report.toJson()['hostTimezoneCompatible'], expectedMatch);
    // Phoenix and Los Angeles share an offset after the March transition but
    // differ before it. Checking only the last date would miss this mismatch.
    if (DateTime(2026, 2, 20).timeZoneOffset == const Duration(hours: -8) &&
        DateTime(2026, 3, 20).timeZoneOffset == const Duration(hours: -7)) {
      expect(
        window.localTime(window.end).timeZoneOffset,
        window.end.toLocal().timeZoneOffset,
      );
      expect(report.toJson()['hostTimezoneCompatible'], isFalse);
    }
  });
}

PrepSnapshot _snapshot({
  List<Map<String, dynamic>> signals = const [],
  List<Map<String, dynamic>> checkIns = const [],
  List<Map<String, dynamic>> outcomes = const [],
  bool consent = true,
  PrepWindow? window,
}) => PrepSnapshot(
  uid: 'private-account',
  window: window ?? PrepWindow.endingOn(DateTime(2026, 7, 31), timezone: 'UTC'),
  consent: PrepConsent(collection: consent, trainingUse: consent, version: 1),
  fetchedAt: DateTime.utc(2026, 8, 1),
  schemaVersion: 11,
  signals: signals,
  checkIns: checkIns,
  outcomes: outcomes,
);

String _time(int day, int hour) =>
    DateTime.utc(2026, 7, day, hour).toIso8601String();

Map<String, dynamic> _signal(int day, int hour, String type, num value) => {
  'id':
      'manual-${DateTime.utc(2026, 7, day, hour).microsecondsSinceEpoch}-$type',
  'type': type,
  'value': value,
  'timestamp': _time(day, hour),
  'createdAt': _time(day, hour),
  'source': 'manual',
};

Map<String, dynamic> _checkIn(
  int day,
  int hour, {
  num energy = 7,
  num mood = 6,
  num stress = 4,
}) => {
  'id': 'checkin-${DateTime.utc(2026, 7, day, hour).microsecondsSinceEpoch}',
  'timestamp': _time(day, hour),
  'createdAt': _time(day, hour),
  'energy': energy,
  'mood': mood,
  'stress': stress,
  'period': hour < 14 ? 'morning' : 'evening',
};

Map<String, dynamic> _energy(Map<String, dynamic> checkIn) => {
  'id': 'energy-${checkIn['id']}',
  'type': 'observedEnergy',
  'value': checkIn['energy'],
  'unit': 'rating_1_10',
  'observedAt': checkIn['timestamp'],
  'recordedAt': checkIn['timestamp'],
  'source': 'checkIn',
  'sourceId': checkIn['id'],
  'consentVersion': 1,
};

Map<String, dynamic> _reaction(Map<String, dynamic> signal) => {
  'id': 'reaction-${signal['id']}',
  'type': 'cognitiveReaction',
  'value': signal['value'],
  'unit': 'ms',
  'observedAt': signal['timestamp'],
  'recordedAt': signal['timestamp'],
  'source': 'reactionSignal',
  'sourceId': signal['id'],
  'consentVersion': 1,
};

List<Map<String, dynamic>> _context(int day) => [
  _signal(day, 9, 'exercise', 1),
  _signal(day, 9, 'hydration', 2),
  _signal(day, 9, 'study', 2),
  _signal(day, 9, 'screenTime', 2),
  _signal(day, 9, 'caffeine', 1),
];

Map _counts(PrepReport report) => report.toJson()['counts'] as Map;
List _reasons(PrepReport report, [String head = 'energy']) =>
    ((report.toJson()['readiness'] as Map)[head] as Map)['reasons'] as List;
List<String> _rejected(PrepReport report) =>
    (report.toJson()['rejectedRows'] as List)
        .map((row) => (row as Map)['reason'] as String)
        .toList();
