import 'dart:convert';

import 'package:app/src/energy_residual_model.dart';
import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/benchmark_energy_model.dart' show benchmarkSnapshot;

EnergyModelFit fit(PrepSnapshot snapshot, {PrepReport? report}) =>
    EnergyResidualTrainer.train(
      snapshot: snapshot,
      report: report ?? MlPrepBuilder.build(snapshot),
      trainedAt: snapshot.fetchedAt,
    );

PrepSnapshot changed(
  PrepSnapshot source, {
  List<Map<String, dynamic>>? signals,
  List<Map<String, dynamic>>? checkIns,
  List<Map<String, dynamic>>? outcomes,
  String? uid,
}) => PrepSnapshot(
  uid: uid ?? source.uid,
  window: source.window,
  consent: source.consent,
  fetchedAt: source.fetchedAt,
  signals: signals ?? source.signals,
  checkIns: checkIns ?? source.checkIns,
  outcomes: outcomes ?? source.outcomes,
  schemaVersion: source.schemaVersion,
);

void main() {
  test('fixed ridge matches the closed-form constant-vector solution', () {
    final snapshot = benchmarkSnapshot();
    final report = MlPrepBuilder.build(snapshot);
    final result = fit(snapshot, report: report);
    expect(result.reason, 'accepted');
    final model = result.model!;
    final row = report.examples.first;
    final trainingCount = report.examples
        .where((r) => r.split == 'training')
        .length;
    final x = <double>[0];
    for (final name in EnergyResidualModel.featureNames) {
      final age = row.featureAgeHours[name];
      final freshness = age == null ? 0.0 : (1 - age / 36).clamp(0.0, 1.0);
      x[0] += freshness / 8;
      x.add((row.features[name] ?? 0) * freshness);
    }
    for (var i = 1; i < x.length; i++) {
      x[i] *= x[0];
    }
    final scale =
        trainingCount *
        8 /
        (1 + trainingCount * x.fold<double>(0, (s, v) => s + v * v));
    expect(model.intercept, closeTo(scale * x[0], 1e-9));
    for (var i = 0; i < 8; i++) {
      expect(model.weights[i], closeTo(scale * x[i + 1], 1e-9));
    }
    expect(result.candidateMae, lessThan(result.baselineMae! * .95));
    expect(result.workingBytes, lessThan(1024 * 1024));
    expect(model.ownerKey, prepFingerprint({'uid': snapshot.uid}));
  });

  test('holdout labels never change fitted weights and are not refit', () {
    final first = fit(benchmarkSnapshot());
    final second = fit(benchmarkSnapshot(holdoutResidual: 9));
    expect(first.model, isNotNull);
    expect(second.model, isNotNull);
    expect(second.model!.weights, first.model!.weights);
    expect(second.model!.intercept, first.model!.intercept);
    expect(second.candidateMae, isNot(first.candidateMae));
    expect(second.model!.fingerprint, isNot(first.model!.fingerprint));
  });

  test('opposite holdout trend and perfect deterministic reference reject', () {
    expect(
      fit(benchmarkSnapshot(holdoutResidual: -8)).reason,
      'holdout_underperformance',
    );
    expect(fit(benchmarkSnapshot(residual: 0)).model, isNull);
  });

  test('promotion uses the exact bounded and rounded deployed prediction', () {
    for (final residual in [0.1, 2.3, 25.0]) {
      final snapshot = benchmarkSnapshot(residual: residual);
      final report = MlPrepBuilder.build(snapshot);
      final result = fit(snapshot, report: report);
      if (residual == .1) {
        // An unrounded sub-half-point improvement changes no deployed score.
        expect(result.reason, 'holdout_underperformance');
        continue;
      }
      final model = result.model!;
      final holdout = report.examples
          .where((row) => row.split == 'holdout')
          .toList();
      var error = 0.0;
      for (final row in holdout) {
        final correction = model.correction(
          features: row.features,
          featureAgeHours: row.featureAgeHours,
        )!;
        expect(correction, inInclusiveRange(-10, 10));
        error +=
            (row.target! - (row.reference! + correction).round().clamp(0, 100))
                .abs();
      }
      expect(model.holdoutMae, error / holdout.length);
    }
  });

  test('Cognitive is not fitted or counted as Energy labels', () {
    final energy = fit(benchmarkSnapshot());
    final mixed = fit(benchmarkSnapshot(includeCognitive: true));
    expect(mixed.model!.labelCount, 20);
    expect(mixed.model!.weights, energy.model!.weights);
    expect(mixed.model!.intercept, energy.model!.intercept);
  });

  test('readiness rejects denied consent and fewer than 14 genuine days', () {
    expect(fit(benchmarkSnapshot(consent: false)).reason, 'consent_required');
    expect(fit(benchmarkSnapshot(days: 13)).model, isNull);
    final source = benchmarkSnapshot();
    final synthetic = changed(
      source,
      checkIns: source.checkIns.map((r) => {...r, 'synthetic': true}).toList(),
    );
    expect(fit(synthetic).model, isNull);
    expect(
      fit(
        changed(source, uid: 'different-account'),
        report: MlPrepBuilder.build(source),
      ).model?.ownerKey,
      isNot(prepFingerprint({'uid': source.uid})),
    );
  });

  test(
    'mismatched snapshot report, late recording and unknown availability reject',
    () {
      final source = benchmarkSnapshot();
      final altered = changed(
        source,
        signals: source.signals.map((r) => {...r, 'value': 3}).toList(),
      );
      expect(
        fit(altered, report: MlPrepBuilder.build(source)).reason,
        'incompatible_prep_report',
      );
      final late = changed(
        source,
        outcomes: source.outcomes
            .map(
              (r) => {
                ...r,
                'recordedAt': source.fetchedAt
                    .add(const Duration(days: 1))
                    .toIso8601String(),
              },
            )
            .toList(),
      );
      expect(fit(late).model, isNull);
      final unknown = changed(
        source,
        signals: source.signals
            .map((r) => {...r}..remove('createdAt'))
            .toList(),
      );
      expect(fit(unknown).model, isNull);
    },
  );

  test('duplicate source/outcome IDs and incompatible label units reject', () {
    final source = benchmarkSnapshot();
    expect(
      fit(
        changed(source, outcomes: [...source.outcomes, source.outcomes.first]),
      ).model,
      isNull,
    );
    expect(
      fit(
        changed(source, checkIns: [...source.checkIns, source.checkIns.first]),
      ).model,
      isNull,
    );
    final wrongUnits = changed(
      source,
      outcomes: source.outcomes.map((r) => {...r, 'unit': 'ms'}).toList(),
    );
    expect(fit(wrongUnits).model, isNull);
  });

  test(
    'artifact is small, immutable, owner-scoped and round-trips exactly',
    () {
      final model = fit(benchmarkSnapshot()).model!;
      final encoded = jsonEncode(model.toJson());
      expect(utf8.encode(encoded).length, lessThan(4096));
      expect(encoded, isNot(contains('isolated-benchmark')));
      expect(
        model.metadata.keys,
        unorderedEquals([
          'modelVersion',
          'schemaVersion',
          'window',
          'trainedAt',
          'labelCount',
          'holdoutMae',
          'deterministicMae',
          'featureCoverage',
        ]),
      );
      expect(
        EnergyResidualModel.fromJson(jsonDecode(encoded)).toJson(),
        model.toJson(),
      );
      expect(() => model.weights[0] = 100, throwsUnsupportedError);
      expect(() => model.featureCoverage['mood'] = 0, throwsUnsupportedError);
    },
  );

  test(
    'corrupt versions, coefficients, schema, units and oversize artifacts reject',
    () {
      final json = fit(benchmarkSnapshot()).model!.toJson();
      final mutations = <Map<String, dynamic>>[
        {...json, 'modelVersion': 2},
        {...json, 'schemaVersion': 2},
        {
          ...json,
          'weights': [double.nan, ...List.filled(7, 0)],
        },
        {...json, 'intercept': double.infinity},
        {...json, 'intercept': 1001},
        {...json, 'labelCount': 13},
        {...json, 'labelCount': 14.5},
        {...json, 'ownerKey': ''},
        {...json, 'fingerprint': 'wrong'},
        {...json, 'trainedAt': '2026-08-01'},
        {
          ...json,
          'features': EnergyResidualModel.featureNames.reversed.toList(),
        },
        {
          ...json,
          'weights': [1, 2],
        },
        {...json, 'holdoutMae': 100},
        {
          ...json,
          'featureCoverage': {'mood': 1},
        },
        {...json, 'extra': 'x' * 5000},
      ];
      for (final mutation in mutations) {
        mutation['artifactChecksum'] = prepFingerprint(
          {...mutation}..remove('artifactChecksum'),
        );
        expect(
          () => EnergyResidualModel.fromJson(mutation),
          throwsFormatException,
        );
      }
    },
  );

  test('a finite coefficient corruption is detected by artifact checksum', () {
    final model = fit(benchmarkSnapshot()).model!;
    expect(
      () => EnergyResidualModel.fromJson({
        ...model.toJson(),
        'intercept': model.intercept + .01,
      }),
      throwsFormatException,
    );
  });

  test('mutated feature provenance and age cannot bypass readiness', () {
    final source = benchmarkSnapshot();
    final report = MlPrepBuilder.build(source);
    report.examples.first.featureSources['movement'] = [
      'signals/not-found:manual',
    ];
    expect(fit(source, report: report).model, isNull);
    final changedAge = MlPrepBuilder.build(source);
    changedAge.examples.first.featureAgeHours['movement'] = 0;
    expect(fit(source, report: changedAge).model, isNull);
  });

  test('whole-day split membership is independently audited', () {
    final source = benchmarkSnapshot();
    final real = MlPrepBuilder.build(source);
    final rows = real.examples
        .map(
          (row) => TrainingExample(
            outcomeId: row.outcomeId,
            head: row.head,
            day: row.day,
            observedAt: row.observedAt,
            label: row.label,
            labelUnit: row.labelUnit,
            target: row.target,
            reference: row.reference,
            features: row.features,
            featureSources: row.featureSources,
            featureAgeHours: row.featureAgeHours,
            warnings: row.warnings,
            consentVersion: row.consentVersion,
            split: row == real.examples.last ? 'training' : row.split,
          ),
        )
        .toList();
    expect(fit(source, report: _AlteredReport(real, rows)).model, isNull);
  });

  test('missing and stale inputs attenuate every term including intercept', () {
    final model = fit(benchmarkSnapshot(residual: 4)).model!;
    final names = EnergyResidualModel.featureNames;
    final values = {for (final name in names) name: 0.0};
    final ages = {for (final name in names) name: 0.0};
    final fresh = model.correction(features: values, featureAgeHours: ages)!;
    final halfMissing = {
      for (var i = 0; i < names.length; i++) names[i]: i < 4 ? 0.0 : null,
    };
    expect(
      model.correction(features: halfMissing, featureAgeHours: halfMissing),
      closeTo(fresh / 2, 1e-9),
    );
    expect(
      model.correction(
        features: {for (final n in names) n: null},
        featureAgeHours: {for (final n in names) n: null},
      ),
      0,
    );
    expect(
      model.correction(
        features: values,
        featureAgeHours: {for (final n in names) n: 720},
      ),
      0,
    );
  });

  test(
    'invalid inputs fail closed and adversarial finite values stay bounded',
    () {
      final model = fit(benchmarkSnapshot()).model!;
      final names = EnergyResidualModel.featureNames;
      final ages = {for (final n in names) n: 0.0};
      final values = {for (final n in names) n: 1.0};
      for (final bad in [
        double.nan,
        double.infinity,
        -double.infinity,
        1.01,
        -1.01,
      ]) {
        expect(
          model.correction(
            features: {...values, 'mood': bad},
            featureAgeHours: ages,
          ),
          isNull,
        );
      }
      expect(
        model.correction(
          features: values,
          featureAgeHours: {...ages, 'mood': -1},
        ),
        isNull,
      );
      expect(
        model.correction(
          features: values,
          featureAgeHours: {...ages, 'mood': null},
        ),
        isNull,
      );
      expect(
        model.correction(
          features: {...values, 'unknown': 1},
          featureAgeHours: ages,
        ),
        isNull,
      );
      for (var mask = 0; mask < 256; mask++) {
        final v = {
          for (var i = 0; i < 8; i++)
            names[i]: (mask & (1 << i)) == 0 ? -1.0 : 1.0,
        };
        expect(
          model.correction(features: v, featureAgeHours: ages),
          inInclusiveRange(-10, 10),
        );
      }
    },
  );
}

class _AlteredReport implements PrepReport {
  _AlteredReport(this.original, this.examples);
  final PrepReport original;
  @override
  final List<TrainingExample> examples;
  @override
  bool get energyReady => original.energyReady;
  @override
  bool get cognitiveReady => original.cognitiveReady;
  @override
  Map<String, Object?> get identity => original.identity;
  @override
  Map<String, Object?> toJson() => original.toJson();
}
