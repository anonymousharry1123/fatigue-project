import 'package:app/src/demo_data.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/models.dart';
import 'package:app/src/personal_baseline_logic.dart';
import 'package:app/src/score_explanation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 7, 14);

  ScoreDriver measured(String label, double points, {DateTime? evidenceAt}) =>
      ScoreDriver(
        label,
        points,
        'A stored observation',
        source: SignalSource.healthKit,
        evidenceSources: const [SignalSource.healthKit],
        containsDemoEvidence: false,
        evidenceAt: evidenceAt ?? now.subtract(const Duration(hours: 2)),
        freshness: .9,
      );

  ScoreSnapshot snapshot({
    List<ScoreDriver> drivers = const [],
    List<ScoreDriver> cognitiveDrivers = const [],
    double confidence = .8,
    double cognitiveConfidence = .4,
    double? freshness = .9,
    int inputCount = 0,
    int cognitiveInputCount = 0,
    bool hasCognitiveScore = true,
    DateTime? calculatedAt,
  }) => ScoreSnapshot(
    energy: 72,
    cognitive: 63,
    confidence: confidence,
    cognitiveConfidence: cognitiveConfidence,
    drivers: drivers,
    cognitiveDrivers: cognitiveDrivers,
    inputCount: inputCount,
    cognitiveInputCount: cognitiveInputCount,
    hasCognitiveScore: hasCognitiveScore,
    freshness: freshness,
    cognitiveFreshness: .35,
    calculatedAt: calculatedAt ?? now,
  );

  ScoreExplanation explain(
    ScoreSnapshot score, {
    ScoreHead head = ScoreHead.energy,
    DateTime? clock,
  }) => ScoreExplanation.build(snapshot: score, head: head, now: clock ?? now);

  test('explains saved score unchanged and ranks all impacts by magnitude', () {
    final positive = measured('Sleep', 4);
    final negative = measured('Hydration', -12);
    final neutral = measured('Caffeine', 0);
    final raw = [positive, negative, neutral];
    final score = snapshot(drivers: raw, inputCount: 3);
    final result = explain(score);

    expect(result.value, 72);
    expect(result.confidence, .8);
    expect(result.drivers.map((item) => item.driver), [
      negative,
      positive,
      neutral,
    ]);
    expect(raw, [positive, negative, neutral]);
    expect(identical(result.drivers.first.driver, negative), isTrue);
    expect(result.drivers.map((item) => item.contributionLabel), [
      '−12 points',
      '+4 points',
      '0 points · neutral',
    ]);
    expect(result.caveats.join(' '), contains('not proof'));
    expect(() => result.drivers.clear(), throwsUnsupportedError);
    expect(() => result.inputs.clear(), throwsUnsupportedError);
    expect(() => result.caveats.clear(), throwsUnsupportedError);
  });

  test('distinguishes actual Energy inventory from saved seven-input cap', () {
    final labels = [
      'Sleep',
      'HRV vs baseline',
      'Resting HR vs baseline',
      'Hydration',
      'Exercise',
      'Workload',
      'Screen time',
      'Caffeine',
      'Mood',
      'Stress',
    ];
    final result = explain(
      snapshot(
        drivers: labels.map((label) => measured(label, 1)).toList(),
        inputCount: 7,
      ),
    );

    expect(result.inputTotal, 7);
    expect(result.inputCount, 7);
    expect(result.usedInputCount, 7);
    expect(result.expectedEvidenceCount, 10);
    expect(result.availableEvidenceCount, 10);
    expect(result.missingInputCount, 0);
    expect(result.inputs.map((input) => input.label), [
      'Sleep',
      'HRV vs baseline',
      'Resting HR vs baseline',
      'Hydration',
      'Movement',
      'Workload',
      'Screen time',
      'Caffeine',
      'Mood',
      'Stress',
    ]);
    expect(result.caveats.join(' '), contains('capped at 7'));
  });

  test('Cognitive uses its own stored score, confidence and six factors', () {
    final result = explain(
      snapshot(
        drivers: [measured('Hydration', 9)],
        cognitiveDrivers: [
          measured('Reaction time', -7),
          measured('Study load', 0),
        ],
        inputCount: 1,
        cognitiveInputCount: 2,
      ),
      head: ScoreHead.cognitive,
    );

    expect(result.head, ScoreHead.cognitive);
    expect(result.head.label, 'Cognitive');
    expect(result.value, 63);
    expect(result.confidence, .4);
    expect(result.freshness, .35);
    expect(result.inputTotal, 6);
    expect(result.inputCount, 2);
    expect(result.expectedEvidenceCount, 6);
    expect(result.availableEvidenceCount, 2);
    expect(result.missingInputCount, 4);
    expect(result.inputs.map((input) => input.label), [
      'Reaction time',
      'Sleep',
      'Study load',
      'Screen time',
      'Mood',
      'Stress',
    ]);
    expect(result.drivers.map((item) => item.driver.label), [
      'Reaction time',
      'Study load',
    ]);
  });

  test('missing legacy Cognitive score is null rather than invented zero', () {
    final result = explain(
      snapshot(hasCognitiveScore: false),
      head: ScoreHead.cognitive,
    );
    expect(result.value, isNull);
    expect(result.freshness, isNull);
    expect(result.inputCount, 0);
    expect(
      result.inputs.every((item) => item.kind == EvidenceKind.unknown),
      isTrue,
    );
    expect(result.availableEvidenceCount, 0);
    expect(result.caveats.join(' '), contains('Missing is not zero'));
  });

  test('zero-contribution observed input is present, unlike missing input', () {
    final result = explain(
      snapshot(drivers: [measured('Caffeine', 0)], inputCount: 1),
    );
    final caffeine = result.inputs.singleWhere(
      (item) => item.label == 'Caffeine',
    );
    final hydration = result.inputs.singleWhere(
      (item) => item.label == 'Hydration',
    );
    expect(caffeine.kind, EvidenceKind.measured);
    expect(hydration.kind, EvidenceKind.missing);
    expect(hydration.detail, contains('does not mean zero'));
    expect(result.availableEvidenceCount, 1);
    expect(result.missingInputCount, 9);
    expect(result.caveats.join(' '), contains('import source'));
  });

  test('source-free legacy driver never becomes a verified observation', () {
    const mood = ScoreDriver('Mood', 2, '7/10');
    final result = explain(snapshot(drivers: [mood], inputCount: 1));
    expect(result.drivers.single.kind, EvidenceKind.unknown);
    expect(result.drivers.single.sourceLabel, contains('Source not recorded'));
    expect(
      result.drivers.single.freshnessLabel,
      'Observation time unavailable',
    );
    expect(
      result.inputs.singleWhere((item) => item.label == 'Mood').kind,
      EvidenceKind.unknown,
    );
    expect(result.caveats.join(' '), contains('predate provenance tracking'));
  });

  test(
    'legacy latest source alone does not establish aggregate provenance',
    () {
      final result = explain(
        snapshot(
          drivers: [
            ScoreDriver(
              'Sleep',
              2,
              '8 hr',
              source: SignalSource.healthKit,
              evidenceAt: now,
            ),
          ],
        ),
      );
      expect(result.drivers.single.kind, EvidenceKind.unknown);
      expect(result.drivers.single.sourceLabel, contains('Apple Health'));
      expect(
        result.drivers.single.sourceLabel,
        contains('latest saved source only'),
      );
      expect(
        result.drivers.single.sourceLabel,
        contains('provenance not recorded'),
      );
    },
  );

  test('manual check-ins and app entries are not labeled measured', () {
    final result = explain(
      snapshot(
        drivers: [
          ScoreDriver(
            'Mood',
            0,
            '5.5/10',
            source: SignalSource.manual,
            evidenceSources: const [SignalSource.manual],
            containsDemoEvidence: false,
            evidenceAt: now,
          ),
        ],
      ),
    );
    expect(result.drivers.single.kind, EvidenceKind.selfReported);
    expect(result.drivers.single.sourceLabel, 'App entry / check-in');
  });

  test('blended measured and manual evidence shows every source', () {
    final result = explain(
      snapshot(
        drivers: [
          ScoreDriver(
            'Sleep',
            2,
            '3-night average',
            source: SignalSource.healthKit,
            evidenceSources: const [
              SignalSource.healthKit,
              SignalSource.manual,
              SignalSource.healthKit,
            ],
            containsDemoEvidence: false,
            evidenceAt: now,
          ),
        ],
      ),
    );
    expect(result.drivers.single.kind, EvidenceKind.unknown);
    expect(
      result.drivers.single.sourceLabel,
      'Current/recent observations: App entry / check-in + Apple Health · mixed sources',
    );
    expect(result.caveats.join(' '), contains('combine multiple sources'));
  });

  test('model evidence remains an estimate including blended evidence', () {
    final result = explain(
      snapshot(
        drivers: [
          ScoreDriver(
            'Sleep',
            2,
            '8 hr',
            source: SignalSource.healthKit,
            evidenceSources: const [SignalSource.healthKit, SignalSource.model],
            containsDemoEvidence: false,
            evidenceAt: now,
          ),
          const ScoreDriver(
            'Legacy adjustment',
            -1,
            'Prior model',
            source: SignalSource.model,
          ),
        ],
      ),
    );
    expect(
      result.drivers.every((item) => item.kind == EvidenceKind.estimated),
      isTrue,
    );
    expect(
      result.drivers.first.sourceLabel,
      contains('Apple Health + Model estimate'),
    );
  });

  test('synthetic provenance overrides measured or model source labels', () {
    final result = explain(
      snapshot(
        drivers: [
          ScoreDriver(
            'Sleep',
            2,
            'Synthetic sleep',
            source: SignalSource.healthKit,
            evidenceSources: const [SignalSource.healthKit, SignalSource.model],
            containsDemoEvidence: true,
            evidenceAt: now,
          ),
        ],
      ),
    );
    expect(result.drivers.single.kind, EvidenceKind.demo);
    expect(result.drivers.single.sourceLabel, contains('demo / synthetic'));
    expect(result.caveats.join(' '), contains('not a verified picture'));
  });

  test('real engine demo data stays distinguishable in both score heads', () {
    final score = FatigueEngine.score(
      signals: buildDemoSignals(now),
      checkIns: buildDemoCheckIns(now),
      now: now,
    );
    for (final head in ScoreHead.values) {
      final result = explain(score, head: head);
      expect(result.drivers, isNotEmpty);
      expect(
        result.drivers.every((item) => item.kind == EvidenceKind.demo),
        isTrue,
      );
    }
  });

  test('measured current data never verifies its historical baseline', () {
    final signals = [
      for (var day = 1; day <= 7; day++)
        SignalReading(
          id: 'demo-hrv-$day',
          type: SignalType.hrv,
          value: 40,
          timestamp: now.subtract(Duration(days: day)),
          source: SignalSource.healthKit,
        ),
      SignalReading(
        id: 'health-hrv-current',
        type: SignalType.hrv,
        value: 50,
        timestamp: now,
        source: SignalSource.healthKit,
      ),
    ];
    final score = FatigueEngine.score(
      signals: signals,
      checkIns: const [],
      now: now,
      personalBaselines: PersonalBaselineLogic.build(
        signals: signals,
        asOf: now,
      ),
    );
    final result = explain(score);
    final driver = result.drivers.single;
    // Saved source tags describe the current observation, not the historical
    // synthetic reference. Explanation must not promote that limited fact
    // into a claim that all evidence used by this driver was measured/genuine.
    expect(driver.driver.label, 'HRV vs baseline');
    expect(driver.driver.contribution, greaterThan(0));
    expect(driver.kind, EvidenceKind.measured);
    expect(driver.sourceLabel, 'Current/recent observations: Apple Health');
    expect(
      result.caveats.join(' '),
      contains('sources and demo status were not saved'),
    );
    expect(result.caveats.join(' '), contains('does not verify its baseline'));
  });

  test('freshness is relative to calculation, not time the panel opened', () {
    final score = snapshot(drivers: [measured('Sleep', 1)]);
    final result = explain(score, clock: now.add(const Duration(days: 3)));
    expect(
      result.drivers.single.freshnessLabel,
      '2 hr old at calculation · 90% freshness then',
    );
    expect(result.freshness, .9);
    expect(result.caveats.join(' '), contains('calculated 3 days ago'));
    expect(result.caveats.join(' '), contains('not your current state'));
  });

  test('future-dated evidence is unverified, never fresh', () {
    final result = explain(
      snapshot(
        drivers: [
          measured('Sleep', 1, evidenceAt: now.add(const Duration(minutes: 1))),
        ],
      ),
    );
    expect(result.drivers.single.kind, EvidenceKind.unknown);
    expect(
      result.drivers.single.freshnessLabel,
      contains('Future-dated evidence'),
    );
    expect(result.drivers.single.freshnessLabel, isNot(contains('90%')));
    expect(result.caveats.join(' '), contains('timing is inconsistent'));
  });

  test(
    'future calculation time is surfaced rather than described as current',
    () {
      final result = explain(
        snapshot(calculatedAt: now.add(const Duration(hours: 1))),
      );
      expect(
        result.caveats.join(' '),
        contains('calculation time is in the future'),
      );
      expect(result.caveats.join(' '), isNot(contains('ago.')));
    },
  );

  test('missing calculation time never substitutes now or snapshot day', () {
    final score = ScoreSnapshot(
      energy: 70,
      cognitive: 60,
      confidence: .8,
      drivers: [measured('Sleep', 1)],
      day: now,
    );
    final result = explain(score);
    expect(result.calculatedAt, isNull);
    expect(
      result.drivers.single.freshnessLabel,
      'Age at calculation unavailable',
    );
    expect(
      result.caveats.join(' '),
      contains('calculation time was not saved'),
    );
  });

  test('missing observation time is explicit even when source is known', () {
    final result = explain(
      snapshot(
        drivers: const [
          ScoreDriver(
            'Sleep',
            1,
            '8 hr',
            source: SignalSource.healthKit,
            evidenceSources: [SignalSource.healthKit],
            containsDemoEvidence: false,
            freshness: .9,
          ),
        ],
      ),
    );
    expect(result.drivers.single.kind, EvidenceKind.measured);
    expect(
      result.drivers.single.freshnessLabel,
      'Observation time unavailable',
    );
    expect(result.inputs.first.evidenceAt, isNull);
  });

  test('legacy count without drivers leaves evidence inventory unknown', () {
    final result = explain(snapshot(inputCount: 7));
    expect(result.inputCount, 7);
    expect(result.availableEvidenceCount, 0);
    expect(result.missingInputCount, 0);
    expect(
      result.inputs.every((item) => item.kind == EvidenceKind.unknown),
      isTrue,
    );
    expect(
      result.caveats.join(' '),
      contains('no supporting driver inventory'),
    );
  });

  test(
    'personalization stays separate and cannot increase reported confidence',
    () {
      final original = snapshot(drivers: [measured('Sleep', 1)], inputCount: 1);
      final score = original.withEnergyCorrection(5, '1');
      final result = explain(score);
      expect(result.value, 77);
      expect(result.confidence, original.confidence);
      expect(result.inputCount, 1);
      expect(result.inputs, hasLength(10));
      expect(result.availableEvidenceCount, 1);
      expect(
        result.drivers.first.driver.label,
        'Personalized Energy adjustment',
      );
      expect(result.drivers.first.kind, EvidenceKind.estimated);
      expect(result.caveats.join(' '), contains('does not raise confidence'));
      expect(
        explain(score, head: ScoreHead.cognitive).value,
        original.cognitive,
      );
    },
  );

  test(
    'confidence and freshness display safely bounds invalid saved values',
    () {
      for (final value in [double.nan, double.infinity, -2.0, 4.0]) {
        final result = explain(
          snapshot(confidence: value, freshness: value, inputCount: 99),
        );
        expect(result.confidence, inInclusiveRange(0, 1));
        expect(result.confidencePercent, inInclusiveRange(0, 100));
        expect(result.inputCount, 7);
        if (value.isFinite) {
          expect(result.freshness, inInclusiveRange(0, 1));
        } else {
          expect(result.freshness, isNull);
        }
        expect(
          result.caveats.join(' '),
          contains('saved confidence value is invalid'),
        );
      }
      expect(explain(snapshot(inputCount: -5)).inputCount, 0);
    },
  );

  test('confidence labels describe evidence instead of accuracy', () {
    expect(
      explain(snapshot(confidence: .2)).confidenceLabel,
      'Limited evidence',
    );
    expect(
      explain(snapshot(confidence: .6)).confidenceLabel,
      'Developing evidence',
    );
    expect(
      explain(snapshot(confidence: .9)).confidenceLabel,
      'More complete evidence',
    );
    expect(
      explain(snapshot()).caveats.join(' '),
      contains('not the probability'),
    );
  });

  test('invalid driver freshness never becomes a fresh observation', () {
    final result = explain(
      snapshot(
        drivers: [
          ScoreDriver(
            'Sleep',
            2,
            '8 hr',
            source: SignalSource.healthKit,
            evidenceSources: const [SignalSource.healthKit],
            containsDemoEvidence: false,
            evidenceAt: now,
            freshness: 12,
          ),
        ],
      ),
    );
    expect(
      result.drivers.single.freshnessLabel,
      contains('invalid saved value'),
    );
    expect(result.drivers.single.freshnessLabel, isNot(contains('100%')));
  });

  test('invalid impacts sort last and are not formatted as real points', () {
    final result = explain(
      snapshot(
        drivers: [
          measured('Sleep', double.nan),
          measured('Hydration', 2),
          measured('Caffeine', double.infinity),
          measured('Workload', -.25),
        ],
      ),
    );
    expect(result.drivers.map((item) => item.driver.label), [
      'Hydration',
      'Workload',
      'Sleep',
      'Caffeine',
    ]);
    expect(result.drivers[1].contributionLabel, '−0.25 points');
    expect(result.drivers.last.contributionLabel, 'Impact unavailable');
    expect(result.value, 72);
    expect(result.caveats.join(' '), contains('invalid point contribution'));
  });

  test('unknown future factor is retained without inventing input mapping', () {
    final result = explain(snapshot(drivers: [measured('Future factor', 9)]));
    expect(result.drivers.single.driver.label, 'Future factor');
    expect(result.inputs, hasLength(10));
    expect(result.availableEvidenceCount, 0);
    expect(result.caveats.join(' '), contains('no new input mapping'));
  });
}
