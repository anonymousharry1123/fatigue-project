import 'dart:convert';
import 'dart:io';

import 'package:app/src/ai1_dataset_builder.dart';
import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/ai1_records.dart';

/// Run from app/: dart run tool/ai1_synthetic_audit.dart [--apple-health]
/// Invented fixtures only; reads no application files, accounts or health data.
void main(List<String> arguments) {
  if (arguments.any((argument) => argument != '--apple-health')) {
    stderr.writeln(
      'Usage: dart run tool/ai1_synthetic_audit.dart [--apple-health]',
    );
    exitCode = 64;
    return;
  }
  final protocol = Ai1Protocol.draft(
    sleepSource: arguments.contains('--apple-health')
        ? Ai1SleepSource.appleHealth
        : Ai1SleepSource.manual,
  );
  final days = <Ai1FixtureDay>[];
  for (var index = 0; index < 4; index++) {
    final opportunity = Ai1Opportunity.forDate(
      protocol: protocol,
      participantKey: 'synthetic-person',
      localDate: '2026-10-0${index + 1}',
      timezone: 'America/Los_Angeles',
    );
    Ai1ResponseRevision response(String id, int minutes, num? energy) {
      final time = opportunity.outcomeStart.add(Duration(minutes: minutes));
      return Ai1ResponseRevision(
        participantKey: opportunity.participantKey,
        sourceId: id,
        revision: 1,
        observedAt: time,
        initialSavedAt: time,
        availableAt: time,
        localDate: opportunity.localDate,
        timezone: opportunity.timezone,
        measurement: protocol.measurement,
        period: 'Evening',
        energy: energy,
      );
    }

    days.add(
      Ai1FixtureDay(
        opportunity: opportunity,
        synthetic: true,
        sleepHistoryComplete: true,
        responseHistoryComplete: true,
        sleepRevisions: [
          if (index != 3)
            Ai1SleepRevision(
              participantKey: opportunity.participantKey,
              collection: 'synthetic-sleep',
              sourceId: 'sleep-$index',
              revision: 1,
              source: protocol.sleepSource,
              endedAt: opportunity.cutoff.subtract(const Duration(hours: 3)),
              // The late-import example cannot enter even a 10:12 issuance.
              availableAt: index == 1
                  ? opportunity.cutoff.add(const Duration(minutes: 5))
                  : opportunity.cutoff.subtract(const Duration(hours: 2)),
              durationHours: 7.5,
            ),
        ],
        responseRevisions: [
          if (index != 3) response('first-$index', 30, index == 2 ? null : 7),
          if (index == 2) response('second-$index', 120, 8),
        ],
        issuedAt: index == 3
            ? null
            : opportunity.cutoff.add(const Duration(minutes: 12)),
        durableAt: index == 3
            ? null
            : opportunity.cutoff.add(const Duration(minutes: 12, seconds: 1)),
      ),
    );
  }
  final report = Ai1DatasetBuilder.buildSynthetic(
    protocol: protocol,
    days: days,
    asOf: DateTime.utc(2026, 10, 6),
    datasetVersion: 'invented-four-day-fixture-v1',
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
}
