import 'models.dart';

enum ScoreHead { energy, cognitive }

extension ScoreHeadInfo on ScoreHead {
  String get label => switch (this) {
    ScoreHead.energy => 'Energy',
    ScoreHead.cognitive => 'Cognitive',
  };
}

/// What the saved evidence actually establishes, not how the score was made.
/// Every score remains an estimate, even when its inputs were measured.
enum EvidenceKind { measured, selfReported, estimated, missing, demo, unknown }

extension EvidenceKindInfo on EvidenceKind {
  String get label => switch (this) {
    EvidenceKind.measured => 'Measured / imported',
    EvidenceKind.selfReported => 'Self-reported / app entry',
    EvidenceKind.estimated => 'Estimated',
    EvidenceKind.missing => 'Missing',
    EvidenceKind.demo => 'Demo / synthetic',
    EvidenceKind.unknown => 'Unverified / mixed',
  };
}

class ExplainedDriver {
  const ExplainedDriver({
    required this.driver,
    required this.kind,
    required this.sourceLabel,
    required this.freshnessLabel,
    required this.contributionLabel,
  });

  /// The original stored driver, unchanged. No new attribution is inferred.
  final ScoreDriver driver;
  final EvidenceKind kind;
  final String sourceLabel;
  final String freshnessLabel;
  final String contributionLabel;
}

class ScoreInputEvidence {
  const ScoreInputEvidence({
    required this.label,
    required this.kind,
    required this.detail,
    required this.sourceLabel,
    this.evidenceAt,
  });

  final String label;
  final EvidenceKind kind;
  final String detail;
  final String sourceLabel;
  final DateTime? evidenceAt;
}

/// A local, read-only explanation of one saved score. It never recalculates
/// the score, alters confidence, reads raw data, trains, or accesses Firebase.
class ScoreExplanation {
  const ScoreExplanation._({
    required this.head,
    required this.value,
    required this.confidence,
    required this.inputCount,
    required this.inputTotal,
    required this.freshness,
    required this.calculatedAt,
    required this.drivers,
    required this.inputs,
    required this.caveats,
  });

  final ScoreHead head;
  final int? value;
  final double confidence;

  /// Historical completeness fields, kept separate from the factor inventory.
  /// Energy's denominator is seven even though newer versions have ten factors.
  final int inputCount;
  final int inputTotal;
  final double? freshness;
  final DateTime? calculatedAt;
  final List<ExplainedDriver> drivers;
  final List<ScoreInputEvidence> inputs;
  final List<String> caveats;

  int get confidencePercent => (confidence * 100).round();
  String get confidenceLabel => confidence < .5
      ? 'Limited evidence'
      : confidence < .75
      ? 'Developing evidence'
      : 'More complete evidence';
  int get usedInputCount => inputCount;
  int get expectedEvidenceCount => inputs.length;

  /// Includes unverified, estimated and demo entries when a driver was stored;
  /// this is presence, not a claim that those entries are genuine measurements.
  int get availableEvidenceCount =>
      inputs.where((input) => input.sourceLabel != _noEvidenceSource).length;
  int get missingInputCount =>
      inputs.where((input) => input.kind == EvidenceKind.missing).length;

  static ScoreExplanation build({
    required ScoreSnapshot snapshot,
    required ScoreHead head,
    required DateTime now,
  }) {
    final isEnergy = head == ScoreHead.energy;
    final hasScore = isEnergy || snapshot.hasCognitiveScore;
    final rawConfidence = isEnergy
        ? snapshot.confidence
        : snapshot.cognitiveConfidence;
    final rawFreshness = isEnergy
        ? snapshot.freshness
        : snapshot.cognitiveFreshness;
    final inputTotal = isEnergy ? 7 : 6;
    final rawInputCount = isEnergy
        ? snapshot.inputCount
        : snapshot.cognitiveInputCount;
    final sourceDrivers = isEnergy
        ? snapshot.drivers
        : snapshot.cognitiveDrivers;
    final sortedDrivers = sourceDrivers.indexed.toList()
      ..sort((left, right) {
        final leftSize = left.$2.contribution.isFinite
            ? left.$2.contribution.abs()
            : -1.0;
        final rightSize = right.$2.contribution.isFinite
            ? right.$2.contribution.abs()
            : -1.0;
        final magnitude = rightSize.compareTo(leftSize);
        return magnitude != 0 ? magnitude : left.$1.compareTo(right.$1);
      });
    final drivers = sortedDrivers
        .map((entry) {
          final driver = entry.$2;
          return ExplainedDriver(
            driver: driver,
            kind: _kind(driver, snapshot.calculatedAt),
            sourceLabel: _sourceLabel(driver),
            freshnessLabel: _freshnessLabel(driver, snapshot.calculatedAt),
            contributionLabel: _contributionLabel(driver.contribution),
          );
        })
        .toList(growable: false);
    final definitions = isEnergy ? _energyInputs : _cognitiveInputs;
    final legacyInventoryUnknown =
        !hasScore || (rawInputCount > 0 && sourceDrivers.isEmpty);
    final inputs = definitions
        .map((definition) {
          final matching = drivers
              .where((item) => definition.$2.contains(item.driver.label))
              .toList(growable: false);
          if (matching.isEmpty) {
            return ScoreInputEvidence(
              label: definition.$1,
              kind: legacyInventoryUnknown
                  ? EvidenceKind.unknown
                  : EvidenceKind.missing,
              detail: legacyInventoryUnknown
                  ? 'This saved score does not identify whether this input was used.'
                  : 'No driver for this input was stored. Missing does not mean zero.',
              sourceLabel: _noEvidenceSource,
            );
          }
          final times =
              matching
                  .map((item) => item.driver.evidenceAt)
                  .whereType<DateTime>()
                  .toList()
                ..sort((left, right) => right.compareTo(left));
          final kinds = matching.map((item) => item.kind).toSet();
          return ScoreInputEvidence(
            label: definition.$1,
            kind: kinds.contains(EvidenceKind.demo)
                ? EvidenceKind.demo
                : kinds.length == 1
                ? kinds.single
                : EvidenceKind.unknown,
            detail: matching.map((item) => item.driver.detail).join(' · '),
            sourceLabel: matching
                .map((item) => item.sourceLabel)
                .toSet()
                .join(' + '),
            evidenceAt: times.firstOrNull,
          );
        })
        .toList(growable: false);

    final caveats = <String>[
      'Energy and Cognitive scores are model estimates, not measurements or medical assessments.',
      'Confidence summarizes recorded coverage, freshness, source quality and baseline maturity. It is not the probability that a score is correct.',
      'Driver points describe the scoring formula, not proof that an input caused a change in how you feel. Rounding and the 0–100 limit can affect the final total.',
      if (isEnergy)
        'The saved Energy coverage count is capped at 7. The inventory shows all 10 current factor categories; extra drivers do not change that historical denominator.',
      if (!hasScore)
        'No Cognitive Score was stored for this day. Missing is not zero.',
      if (legacyInventoryUnknown && hasScore)
        'The saved coverage count has no supporting driver inventory. Which inputs were present is unknown.',
      if (snapshot.calculatedAt == null)
        'The calculation time was not saved. Evidence age at calculation and the age of this score cannot be verified.',
      if (snapshot.calculatedAt?.isAfter(now) == true)
        'The saved calculation time is in the future. Check the device clock; this score cannot be described as current.',
      if (snapshot.calculatedAt != null &&
          now.difference(snapshot.calculatedAt!) >= const Duration(hours: 24))
        'This saved score was calculated ${_age(now.difference(snapshot.calculatedAt!))} ago. Its freshness describes that calculation, not your current state.',
      if (sourceDrivers.any((driver) => driver.containsDemoEvidence == true))
        'Demo or synthetic evidence contributed to this score. It is not a verified picture of your real health data.',
      if (sourceDrivers.any((driver) => driver.containsDemoEvidence == null))
        'Some saved drivers predate provenance tracking. Their source labels do not verify that the underlying evidence was genuine.',
      if (sourceDrivers.any((driver) => driver.evidenceSources.length > 1))
        'Some drivers combine multiple sources. All recorded source types are shown; the latest source alone does not describe the whole input.',
      if (sourceDrivers.any(
        (driver) =>
            driver.source == SignalSource.healthKit ||
            driver.evidenceSources.contains(SignalSource.healthKit),
      ))
        'Apple Health identifies the import source. This saved score does not verify which device measured a value or whether it was entered manually in Health.',
      if (sourceDrivers.any(_usesHistoricalReference))
        'Source badges describe current/recent observations only. Historical comparison baselines have separate inputs whose sources and demo status were not saved here. A measured observation does not verify its baseline.',
      if (sourceDrivers.any((driver) => driver.evidenceAt == null))
        'Some driver observation times were not saved. An import or model-update time is not a substitute for an observation time.',
      if (snapshot.calculatedAt != null &&
          sourceDrivers.any(
            (driver) =>
                driver.evidenceAt?.isAfter(snapshot.calculatedAt!) == true,
          ))
        'Some evidence is dated after this score was calculated. Its timing is inconsistent, so it is shown as unverified.',
      if (isEnergy &&
          (snapshot.deterministicEnergy != null ||
              sourceDrivers.any(
                (driver) => driver.label == 'Personalized Energy adjustment',
              )))
        'The personalized Energy adjustment is capped at ±10 points. It is not another input and does not raise confidence or change Cognitive Score.',
      if (!rawConfidence.isFinite || rawConfidence < 0 || rawConfidence > 1)
        'The saved confidence value is invalid or out of range; this display uses a safe bounded value, not a recalculated confidence.',
      if (rawFreshness != null &&
          (!rawFreshness.isFinite || rawFreshness < 0 || rawFreshness > 1))
        'The saved freshness value is invalid or out of range; this display does not infer new freshness from it.',
      if (rawInputCount < 0 || rawInputCount > inputTotal)
        'The saved coverage count is out of range and is bounded for display only.',
      if (sourceDrivers.any((driver) => !driver.contribution.isFinite))
        'A saved driver has an invalid point contribution. Its impact is unavailable; the stored score has not been changed.',
      if (sourceDrivers.any(
        (driver) =>
            driver.label != 'Personalized Energy adjustment' &&
            !definitions.any(
              (definition) => definition.$2.contains(driver.label),
            ),
      ))
        'A saved driver is not in the current factor inventory. Its original detail remains visible, but no new input mapping has been inferred.',
    ];
    return ScoreExplanation._(
      head: head,
      value: !hasScore
          ? null
          : isEnergy
          ? snapshot.energy
          : snapshot.cognitive,
      confidence: _unit(rawConfidence) ?? 0,
      inputCount: hasScore ? rawInputCount.clamp(0, inputTotal) : 0,
      inputTotal: inputTotal,
      freshness: hasScore ? _unit(rawFreshness) : null,
      calculatedAt: snapshot.calculatedAt,
      drivers: List.unmodifiable(drivers),
      inputs: List.unmodifiable(inputs),
      caveats: List.unmodifiable(caveats),
    );
  }
}

const _noEvidenceSource = 'No source evidence stored';

const _energyInputs = <(String, Set<String>)>[
  ('Sleep', {'Sleep'}),
  ('HRV vs baseline', {'HRV vs baseline'}),
  ('Resting HR vs baseline', {'Resting HR vs baseline'}),
  ('Hydration', {'Hydration'}),
  ('Movement', {'Exercise', 'Movement'}),
  ('Workload', {'Workload'}),
  ('Screen time', {'Screen time'}),
  ('Caffeine', {'Caffeine'}),
  ('Mood', {'Mood'}),
  ('Stress', {'Stress'}),
];

const _cognitiveInputs = <(String, Set<String>)>[
  ('Reaction time', {'Reaction time'}),
  ('Sleep', {'Sleep'}),
  ('Study load', {'Study load'}),
  ('Screen time', {'Screen time'}),
  ('Mood', {'Mood'}),
  ('Stress', {'Stress'}),
];

double? _unit(double? value) =>
    value == null || !value.isFinite ? null : value.clamp(0, 1);

EvidenceKind _kind(ScoreDriver driver, DateTime? calculatedAt) {
  if (driver.containsDemoEvidence == true) return EvidenceKind.demo;
  if (calculatedAt != null &&
      driver.evidenceAt?.isAfter(calculatedAt) == true) {
    return EvidenceKind.unknown;
  }
  final sources = driver.evidenceSources.toSet();
  // A recorded model source establishes that this is an estimate even if old
  // snapshots lack the newer provenance fields. It never establishes a real
  // measured input or genuine training evidence.
  if (sources.contains(SignalSource.model) ||
      driver.source == SignalSource.model) {
    return EvidenceKind.estimated;
  }
  if (driver.containsDemoEvidence == null || sources.length != 1) {
    return EvidenceKind.unknown;
  }
  return switch (sources.single) {
    SignalSource.healthKit => EvidenceKind.measured,
    SignalSource.manual => EvidenceKind.selfReported,
    SignalSource.model => EvidenceKind.estimated,
  };
}

String _sourceName(SignalSource source) => switch (source) {
  SignalSource.healthKit => 'Apple Health',
  SignalSource.manual => 'App entry / check-in',
  SignalSource.model => 'Model estimate',
};

bool _usesHistoricalReference(ScoreDriver driver) => const {
  'Sleep',
  'HRV vs baseline',
  'Resting HR vs baseline',
  'Reaction time',
}.contains(driver.label);

String _sourceLabel(ScoreDriver driver) {
  final sources = driver.evidenceSources.toSet();
  final String label;
  if (sources.isNotEmpty) {
    label = SignalSource.values
        .where(sources.contains)
        .map(_sourceName)
        .join(' + ');
  } else {
    label = driver.source == null
        ? 'Source not recorded'
        : '${_sourceName(driver.source!)} · latest saved source only';
  }
  final scopedLabel = _usesHistoricalReference(driver)
      ? 'Current/recent observations: $label'
      : label;
  if (driver.containsDemoEvidence == true) {
    return '$scopedLabel · demo / synthetic';
  }
  if (driver.containsDemoEvidence == null) {
    return '$scopedLabel · provenance not recorded';
  }
  return sources.length > 1 ? '$scopedLabel · mixed sources' : scopedLabel;
}

String _freshnessLabel(ScoreDriver driver, DateTime? calculatedAt) {
  final evidenceAt = driver.evidenceAt;
  if (evidenceAt == null) return 'Observation time unavailable';
  if (calculatedAt == null) return 'Age at calculation unavailable';
  final age = calculatedAt.difference(evidenceAt);
  if (age.isNegative) return 'Future-dated evidence · timing unverified';
  final freshness = _unit(driver.freshness);
  final time = '${_age(age)} old at calculation';
  if (driver.freshness != null &&
      (!driver.freshness!.isFinite ||
          driver.freshness! < 0 ||
          driver.freshness! > 1)) {
    return '$time · freshness unavailable (invalid saved value)';
  }
  return freshness == null
      ? '$time · freshness unavailable'
      : '$time · ${(freshness * 100).round()}% freshness then';
}

String _age(Duration age) {
  if (age.inMinutes < 1) return 'Less than 1 min';
  if (age.inHours < 1) return '${age.inMinutes} min';
  if (age.inDays < 1) return '${age.inHours} hr';
  return '${age.inDays} ${age.inDays == 1 ? 'day' : 'days'}';
}

String _contributionLabel(double value) {
  if (!value.isFinite) return 'Impact unavailable';
  if (value.abs() <= .01) return '0 points · neutral';
  final magnitude = value.abs();
  final number = magnitude == magnitude.roundToDouble()
      ? magnitude.toStringAsFixed(0)
      : magnitude
            .toStringAsFixed(magnitude < 1 ? 2 : 1)
            .replaceFirst(RegExp(r'\.?0+$'), '');
  return '${value < 0 ? '−' : '+'}$number ${magnitude == 1 ? 'point' : 'points'}';
}
