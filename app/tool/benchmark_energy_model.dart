// Isolated generated benchmark data, never read from or written to an account.
// Run in release AOT, for example:
// dart compile exe tool/benchmark_energy_model.dart -o /tmp/energy-model-bench
// TZ=UTC /tmp/energy-model-bench
import 'dart:convert';
import 'dart:io';

import 'package:app/src/energy_residual_model.dart';
import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/ml_prep_models.dart';

void main(List<String> arguments) {
  final snapshot = benchmarkSnapshot(
    days: 30,
    maximumWindow: arguments.contains('--maximum-window'),
  );
  final report = MlPrepBuilder.build(snapshot);
  final at = snapshot.fetchedAt;
  for (var i = 0; i < 10; i++) {
    EnergyResidualTrainer.train(
      snapshot: snapshot,
      report: report,
      trainedAt: at,
    );
  }
  final rssBefore = ProcessInfo.currentRss;
  final peakBefore = ProcessInfo.maxRss;
  final timings = <int>[];
  EnergyModelFit? fit;
  for (var i = 0; i < 200; i++) {
    fit = EnergyResidualTrainer.train(
      snapshot: snapshot,
      report: report,
      trainedAt: at,
    );
    timings.add(fit.trainingMicros);
  }
  timings.sort();
  final model = fit!.model;
  if (model == null) {
    throw StateError('Benchmark candidate rejected: ${fit.reason}');
  }
  final row = report.examples.last;
  final timer = Stopwatch()..start();
  var nullResults = 0;
  for (var i = 0; i < 100000; i++) {
    if (model.correction(
          features: row.features,
          featureAgeHours: row.featureAgeHours,
        ) ==
        null) {
      nullResults++;
    }
  }
  timer.stop();
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'data': 'generated isolated benchmark; no account access',
      'runtime': Platform.version,
      'labels': model.labelCount,
      'snapshotCounts': snapshot.counts,
      'timingScope':
          'Training includes validation, ridge solve, holdout evaluation and artifact validation; excludes cached prep construction. Inference times only the correction kernel, not feature preparation or deterministic scoring.',
      'artifactUtf8Bytes': utf8.encode(jsonEncode(model.toJson())).length,
      'trainingMicros': {
        'p50': timings[100],
        'p95': timings[190],
        'max': timings.last,
      },
      'inferenceMeanMicros': timer.elapsedMicroseconds / 100000,
      'inferenceBudgetFallbacks': nullResults,
      'kernelWorkingPayloadEstimatedBytes': fit.workingBytes,
      'processCurrentRssBefore': rssBefore,
      'processCurrentRssAfter': ProcessInfo.currentRss,
      'processPeakRssBefore': peakBefore,
      'processPeakRssAfter': ProcessInfo.maxRss,
      'memoryCaveat':
          'Numeric working payload is estimated, not measured VM heap. Process RSS includes Dart runtime, cached prep, repeated validation/JSON and GC; it is not a per-fit allocation measurement.',
      'deterministicMae': fit.baselineMae,
      'holdoutMae': fit.candidateMae,
    }),
  );
}

/// Fabricated, isolated inputs solely for kernel tests/benchmarks. The explicit
/// observed provenance exercises the positive path; do not import these rows
/// into account data or interpret the validation result as a real trained user.
PrepSnapshot benchmarkSnapshot({
  int days = 20,
  double residual = 8,
  double? holdoutResidual,
  bool consent = true,
  bool includeCognitive = false,
  bool maximumWindow = false,
}) {
  final zone = DateTime(2026, 7, 15).timeZoneOffset.inHours == -7
      ? 'America/Los_Angeles'
      : 'Etc/UTC';
  final window = PrepWindow.endingOn(DateTime(2026, 7, 31), timezone: zone);
  String time(int day, int hour) =>
      window.start.add(Duration(days: day, hours: hour)).toIso8601String();
  final signals = <Map<String, dynamic>>[];
  final checks = <Map<String, dynamic>>[];
  final outcomes = <Map<String, dynamic>>[];
  for (var day = 0; day < days; day++) {
    for (final entry in {
      'exercise': 1,
      'hydration': 2,
      'study': 2,
      'screenTime': 2,
      'caffeine': 1,
    }.entries) {
      signals.add({
        'id': 'observed-$day-${entry.key}',
        'provenance': 'observed',
        'timestamp': time(day, maximumWindow ? 6 : 9),
        'createdAt': time(day, maximumWindow ? 6 : 9),
        'type': entry.key,
        'value': entry.value,
        'source': 'manual',
      });
    }
    for (final hour in [8, 20]) {
      checks.add({
        'id': 'observed-$day-check-$hour',
        'provenance': 'observed',
        'timestamp': time(day, hour),
        'createdAt': time(day, hour),
        'energy': 7.0,
        'mood': 6.0,
        'stress': 4.0,
      });
    }
    outcomes.add({
      'id': 'energy-$day',
      'type': 'observedEnergy',
      'value': 7.0,
      'unit': 'rating_1_10',
      'observedAt': time(day, 20),
      'recordedAt': time(day, 20),
      'source': 'checkIn',
      'sourceId': 'observed-$day-check-20',
      'consentVersion': 1,
    });
    if (includeCognitive) {
      signals.add({
        'id': 'reaction-$day',
        'provenance': 'observed',
        'timestamp': time(day, 19),
        'createdAt': time(day, 19),
        'type': 'reactionTime',
        'value': 250.0,
        'source': 'manual',
      });
      outcomes.add({
        'id': 'reaction-outcome-$day',
        'type': 'cognitiveReaction',
        'value': 250.0,
        'unit': 'ms',
        'observedAt': time(day, 19),
        'recordedAt': time(day, 19),
        'source': 'reactionSignal',
        'sourceId': 'reaction-$day',
        'consentVersion': 1,
      });
    }
  }
  if (maximumWindow) {
    // Stay one document below each hard cap, with 99 Energy labels. No caps
    // are bypassed; reaching even one would correctly block training.
    for (var day = 0; day < days; day++) {
      checks.add({
        'id': 'extra-$day-check',
        'provenance': 'observed',
        'timestamp': time(day, 21),
        'createdAt': time(day, 21),
        'energy': 7.0,
        'mood': 6.0,
        'stress': 4.0,
      });
      outcomes.add({
        'id': 'extra-energy-$day',
        'type': 'observedEnergy',
        'value': 7.0,
        'unit': 'rating_1_10',
        'observedAt': time(day, 21),
        'recordedAt': time(day, 21),
        'source': 'checkIn',
        'sourceId': 'extra-$day-check',
        'consentVersion': 1,
      });
      outcomes.add({
        'id': 'morning-energy-$day',
        'type': 'observedEnergy',
        'value': 7.0,
        'unit': 'rating_1_10',
        'observedAt': time(day, 8),
        'recordedAt': time(day, 8),
        'source': 'checkIn',
        'sourceId': 'observed-$day-check-8',
        'consentVersion': 1,
      });
    }
    for (var i = 0; outcomes.length < 99; i++) {
      checks.add({
        'id': 'load-check-$i',
        'provenance': 'observed',
        'timestamp': time(i % days, 22),
        'createdAt': time(i % days, 22),
        'energy': 7.0,
        'mood': 6.0,
        'stress': 4.0,
      });
      outcomes.add({
        'id': 'load-energy-$i',
        'type': 'observedEnergy',
        'value': 7.0,
        'unit': 'rating_1_10',
        'observedAt': time(i % days, 22),
        'recordedAt': time(i % days, 22),
        'source': 'checkIn',
        'sourceId': 'load-check-$i',
        'consentVersion': 1,
      });
    }
    for (var i = 0; signals.length < 1499; i++) {
      signals.add({
        'id': 'load-bedtime-$i',
        'provenance': 'observed',
        'timestamp': time(i % days, 0),
        'createdAt': time(i % days, 0),
        'type': 'bedtime',
        'value': 23.0,
        'source': 'manual',
      });
    }
  }
  PrepSnapshot build() => PrepSnapshot(
    uid: 'isolated-benchmark',
    window: window,
    consent: PrepConsent(collection: consent, trainingUse: consent, version: 1),
    fetchedAt: window.end.add(const Duration(days: 1)),
    schemaVersion: 11,
    signals: signals,
    checkIns: checks,
    outcomes: outcomes,
  );
  // Targets use deterministic references only to construct this benchmark's
  // known mathematical residual. Production labels are never constructed so.
  final initial = MlPrepBuilder.build(build());
  for (final row in initial.examples.where((r) => r.head == 'energy')) {
    final desired = row.split == 'holdout'
        ? holdoutResidual ?? residual
        : residual;
    final value = ((row.reference! + desired).clamp(0, 100) * 9 / 100) + 1;
    outcomes.firstWhere((o) => o['id'] == row.outcomeId)['value'] = value;
    checks.firstWhere(
      (c) =>
          c['id'] ==
          outcomes.firstWhere((o) => o['id'] == row.outcomeId)['sourceId'],
    )['energy'] = value;
  }
  return build();
}
