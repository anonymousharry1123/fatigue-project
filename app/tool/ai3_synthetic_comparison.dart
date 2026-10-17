import 'dart:convert';
import 'dart:io';

import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/ai1_records.dart';
import 'package:app/src/ai3_comparison_runner.dart';

/// Run: dart run tool/ai3_synthetic_comparison.dart [--apple-health]
///
/// Deterministic invented observations for software QA only. This command
/// accepts no file paths and reads no application, account or Health data.
/// October 1–5 supplies warmup history; October 6–12 supplies evaluation days.
/// The second invented person first appears in evaluation, exercising cold
/// starts. No model is selected or promoted from these invented results.
void main(List<String> arguments) {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--apple-health')) {
    stderr.writeln(
      'Usage: dart run tool/ai3_synthetic_comparison.dart [--apple-health]',
    );
    exitCode = 64;
    return;
  }
  final protocol = Ai1Protocol.draft(
    sleepSource: arguments.isEmpty
        ? Ai1SleepSource.manual
        : Ai1SleepSource.appleHealth,
  );
  final scenario = buildAi3SyntheticScenario(protocol: protocol);
  final report = Ai3ComparisonRunner.runSynthetic(
    manifest: scenario.manifest,
    days: scenario.days,
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
}

/// Shared invented scenario for the pre-data end-to-end rehearsal.
({Ai3SyntheticManifest manifest, List<Ai1FixtureDay> days})
buildAi3SyntheticScenario({required Ai1Protocol protocol}) {
  final manifest = Ai3SyntheticManifest(
    protocol: protocol,
    experimentId: 'invented-two-person-comparison-v1',
    datasetVersion: 'invented-twelve-day-history-v1',
    historyStart: DateTime.utc(2026, 10, 1, 10),
    evaluationStart: DateTime.utc(2026, 10, 6, 10),
    evaluationEnd: DateTime.utc(2026, 10, 13, 10),
    analysisAsOf: DateTime.utc(2026, 10, 13, 23),
  );

  // The invented ratings intentionally do not follow a perfect line.
  const firstSleep = [
    5.5,
    7.0,
    6.0,
    8.0,
    7.5,
    6.5,
    8.5,
    5.0,
    7.0,
    6.0,
    8.0,
    7.5,
  ];
  const firstEnergy = <int?>[3, 6, 4, 8, 5, 7, 6, null, 5, 2, 9, 6];
  const secondSleep = [6.5, 7.5, 5.0, 8.0, 6.0, 7.0, 8.5];
  const secondEnergy = <int?>[8, 5, 7, 4, 6, 3, 7];
  final days = <Ai1FixtureDay>[];
  for (var day = 1; day <= 12; day++) {
    days.add(
      _day(
        protocol: protocol,
        participant: 'invented-person-a',
        day: day,
        sleepHours: firstSleep[day - 1],
        energy: firstEnergy[day - 1],
        // Baselines still have a valid morning execution without sleep.
        missingSleep: day == 7,
        // The first unanswered Energy response cannot be replaced later.
        laterAnsweredResponse: day == 8,
        // Sleep and an outcome alone do not prove a morning prediction.
        missedExecution: day == 9,
      ),
    );
    if (day >= 6) {
      days.add(
        _day(
          protocol: protocol,
          participant: 'invented-person-b',
          day: day,
          sleepHours: secondSleep[day - 6],
          energy: secondEnergy[day - 6],
        ),
      );
    }
  }
  return (manifest: manifest, days: List.unmodifiable(days));
}

Ai1FixtureDay _day({
  required Ai1Protocol protocol,
  required String participant,
  required int day,
  required double sleepHours,
  required int? energy,
  bool missingSleep = false,
  bool laterAnsweredResponse = false,
  bool missedExecution = false,
}) {
  final opportunity = Ai1Opportunity.forDate(
    protocol: protocol,
    participantKey: participant,
    localDate: '2026-10-${day.toString().padLeft(2, '0')}',
    timezone: 'Etc/UTC',
  );
  final sleepEnd = opportunity.cutoff.subtract(const Duration(hours: 3));
  final sleepAvailable = opportunity.cutoff.subtract(const Duration(hours: 2));
  Ai1ResponseRevision response(String suffix, int minutes, int? answer) {
    final at = opportunity.outcomeStart.add(Duration(minutes: minutes));
    return Ai1ResponseRevision(
      participantKey: participant,
      sourceId: '$participant-response-$day-$suffix',
      revision: 1,
      observedAt: at,
      initialSavedAt: at.add(const Duration(seconds: 1)),
      availableAt: at.add(const Duration(seconds: 1)),
      localDate: opportunity.localDate,
      timezone: opportunity.timezone,
      measurement: protocol.measurement,
      period: 'Evening',
      energy: answer,
    );
  }

  return Ai1FixtureDay(
    opportunity: opportunity,
    synthetic: true,
    sleepHistoryComplete: true,
    responseHistoryComplete: true,
    sleepRevisions: [
      if (!missingSleep)
        Ai1SleepRevision(
          participantKey: participant,
          collection: protocol.sleepSource == Ai1SleepSource.manual
              ? 'synthetic-manual-sleep'
              : 'synthetic-health-episodes',
          sourceId: '$participant-sleep-$day',
          revision: 1,
          source: protocol.sleepSource,
          endedAt: sleepEnd,
          startedAt: sleepEnd.subtract(
            Duration(minutes: (sleepHours * 60).round()),
          ),
          durationHours: sleepHours,
          availableAt: sleepAvailable,
          selectionDependencies:
              protocol.sleepSource == Ai1SleepSource.appleHealth
              ? [sleepAvailable]
              : const [],
        ),
    ],
    responseRevisions: [
      response('first', 60, energy),
      if (laterAnsweredResponse) response('second', 120, 8),
    ],
    issuedAt: missedExecution
        ? null
        : opportunity.cutoff.add(const Duration(minutes: 3)),
    durableAt: missedExecution
        ? null
        : opportunity.cutoff.add(const Duration(minutes: 3, seconds: 1)),
  );
}
