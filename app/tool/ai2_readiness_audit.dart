import 'dart:convert';
import 'dart:io';

import 'package:app/src/ai1_dataset_builder.dart';
import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/ai2_readiness.dart';

/// No private records are accessed. Supplies an empty opportunity dataset,
/// without claiming that the user's device contains no captured measurements.
/// Run: dart run tool/ai2_readiness_audit.dart [--json]
void main(List<String> arguments) {
  if (arguments.any((argument) => argument != '--json')) {
    stderr.writeln('Usage: dart run tool/ai2_readiness_audit.dart [--json]');
    exitCode = 64;
    return;
  }
  final dataset = Ai1DatasetBuilder.buildCaptured(
    protocol: Ai1Protocol.draft(),
    days: const [],
    asOf: DateTime.utc(2026, 10, 17),
    datasetVersion: 'no-prospective-data-2026-10-17',
  );
  final report = Ai2ReadinessEvaluator.evaluate(
    dataset: dataset,
    rawDays: const [],
  );
  stdout.writeln(
    arguments.contains('--json')
        ? const JsonEncoder.withIndent('  ').convert(report.toJson())
        : report.toMarkdown(),
  );
}
