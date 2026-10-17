import 'dart:convert';
import 'dart:io';

import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/ai4_frozen_evaluation.dart';
import 'package:app/src/ai_model_artifact.dart';
import 'package:app/src/ai_predata_gate.dart';
import 'package:app/src/ai_shadow_evaluation.dart';

import 'ai3_synthetic_comparison.dart' show buildAi3SyntheticScenario;

/// A deterministic, fixture-only end-to-end rehearsal. No input file, real
/// account, local app journal, Health store, network or native write is read.
Future<void> main(List<String> arguments) async {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--apple-health')) {
    stderr.writeln(
      'Usage: dart run tool/ai_predata_rehearsal.dart [--apple-health]',
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
  final manifest = Ai4FrozenManifest(
    protocol: protocol,
    experimentId: 'invented-pre-data-frozen-v1',
    datasetVersion: 'invented-twelve-day-history-v1',
    historyStart: DateTime.utc(2026, 10, 1, 10),
    fitCutoff: DateTime.utc(2026, 10, 6, 10),
    finalStart: DateTime.utc(2026, 10, 9, 10),
    evaluationEnd: DateTime.utc(2026, 10, 13, 10),
    analysisAsOf: DateTime.utc(2026, 10, 13, 23),
  );
  final experiment = Ai4FrozenExperiment.prepareSynthetic(
    manifest: manifest,
    trainingDays: scenario.days.where(
      (day) => day.opportunity.cutoff.isBefore(manifest.fitCutoff),
    ),
    developmentDays: scenario.days.where(
      (day) =>
          !day.opportunity.cutoff.isBefore(manifest.fitCutoff) &&
          day.opportunity.cutoff.isBefore(manifest.finalStart),
    ),
  );
  final finalDays = scenario.days
      .where((day) => !day.opportunity.cutoff.isBefore(manifest.finalStart))
      .toList();
  final evaluation = experiment.openSyntheticFinal(days: finalDays);

  final model = experiment.artifacts['invented-person-a']!['M1']!;
  final restoredModel = AiModelArtifact.fromJson(model.toJson());
  final personalDays = finalDays
      .where((day) => day.opportunity.participantKey == model.participantKey)
      .toList();
  var now = personalDays.first.opportunity.dayStart.subtract(
    const Duration(hours: 1),
  );
  final store = _MemorySimulationStore(() => now);
  final block = AiShadowBlock(
    blockId: 'invented-shadow-block-v1',
    artifact: restoredModel,
    protocol: protocol,
    opportunities: personalDays.map((day) => day.opportunity).toList(),
  );
  final shadow = AiShadowHarness(store: store, clock: () => now);
  await shadow.start(scope: model.ownerScope, block: block);
  for (final day in personalDays) {
    now = day.opportunity.cutoff.add(const Duration(minutes: 3));
    if (day.issuedAt != null) await shadow.recordMorning(day);
    now = day.opportunity.outcomeEnd.add(const Duration(minutes: 1));
    await shadow.linkOutcome(day);
  }
  now = manifest.analysisAsOf;
  final shadowReport = shadow.report();
  await shadow.signOut();
  final reopened = AiShadowHarness(store: store, clock: () => now);
  await reopened.start(scope: model.ownerScope, block: block);
  final restartMatches =
      ai1CanonicalJson(shadowReport) == ai1CanonicalJson(reopened.report());
  await reopened.optOut();
  if (!restartMatches ||
      store.snapshots.isNotEmpty ||
      model.fingerprint != restoredModel.fingerprint) {
    throw StateError('Synthetic lifecycle rehearsal failed.');
  }
  final gate = AiPredataGate.assess(
    settings: AiPredataSettings.preparation(protocol: protocol),
    evidence: const [],
    asOf: manifest.analysisAsOf,
  );
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 'tonyo-pre-data-rehearsal-v1',
      'evidenceKind': 'synthetic_software_fixture',
      'realDataUsed': false,
      'realDataTrainingAllowed': false,
      'appModelActivationAllowed': false,
      'frozenEvaluation': evaluation,
      'shadowSimulation': shadowReport,
      'lifecycleRehearsal': {
        'artifactRoundTripMatched': true,
        'simulatedStoreReopenMatched': restartMatches,
        'optOutClearedSimulatedStore': store.snapshots.isEmpty,
        'nativeDurabilityTestedByThisCommand': false,
      },
      'predataReview': gate.toJson(),
    }),
  );
}

class _MemorySimulationStore implements AiShadowSimulatedStore {
  _MemorySimulationStore(this.clock);
  final DateTime Function() clock;
  final Map<String, Map<String, dynamic>> snapshots = {};
  Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  @override
  Future<Map<String, dynamic>?> read(String scope) async =>
      snapshots[scope] == null ? null : _copy(snapshots[scope]!);
  @override
  Future<DateTime> write(String scope, Map<String, dynamic> snapshot) async {
    snapshots[scope] = _copy(snapshot);
    return clock().toUtc();
  }

  @override
  Future<void> clear(String scope) async => snapshots.remove(scope);
}
