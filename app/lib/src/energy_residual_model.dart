import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'ml_prep_builder.dart';
import 'ml_prep_models.dart';

/// A small, account-scoped artifact. Raw observations and UID are never stored
/// here. Its input schema and normalization are fixed by prep version 1.
class EnergyResidualModel {
  EnergyResidualModel._({
    required this.ownerKey,
    required this.trainedAt,
    required this.window,
    required this.fingerprint,
    required this.labelCount,
    required List<double> weights,
    required this.intercept,
    required this.holdoutMae,
    required this.deterministicMae,
    required Map<String, double> featureCoverage,
  }) : weights = List.unmodifiable(weights),
       featureCoverage = Map.unmodifiable(featureCoverage);

  static const modelVersion = 1;
  static const schemaVersion = 1;
  static const maximumArtifactBytes = 4096;
  static const maximumCorrection = 10.0;
  static const featureNames = MlPrepBuilder.energyFeatureNames;

  final String ownerKey;
  final DateTime trainedAt;
  final PrepWindow window;
  final String fingerprint;
  final int labelCount;
  final List<double> weights;
  final double intercept;
  final double holdoutMae;
  final double deterministicMae;
  final Map<String, double> featureCoverage;

  /// Only this small, non-identifying subset may be sent as cloud metadata.
  Map<String, Object?> get metadata => {
    'modelVersion': modelVersion,
    'schemaVersion': schemaVersion,
    'window': window.toJson(),
    'trainedAt': trainedAt.toUtc().toIso8601String(),
    'labelCount': labelCount,
    'holdoutMae': holdoutMae,
    'deterministicMae': deterministicMae,
    'featureCoverage': featureCoverage,
  };

  Map<String, Object?> _artifactFields() => {
    ...metadata,
    'ownerKey': ownerKey,
    'fingerprint': fingerprint,
    'features': featureNames,
    'weights': weights,
    'intercept': intercept,
  };

  Map<String, Object?> toJson() {
    final fields = _artifactFields();
    return {...fields, 'artifactChecksum': prepFingerprint(fields)};
  }

  factory EnergyResidualModel.fromJson(Map<String, dynamic> json) {
    try {
      if (utf8.encode(jsonEncode(json)).length >= maximumArtifactBytes ||
          !_sameKeys(json, const {
            'modelVersion',
            'schemaVersion',
            'window',
            'trainedAt',
            'labelCount',
            'holdoutMae',
            'deterministicMae',
            'featureCoverage',
            'ownerKey',
            'fingerprint',
            'features',
            'weights',
            'intercept',
            'artifactChecksum',
          }) ||
          json['modelVersion'] is! int ||
          json['schemaVersion'] is! int ||
          json['modelVersion'] != modelVersion ||
          json['schemaVersion'] != schemaVersion) {
        throw const FormatException('Unsupported Energy model artifact.');
      }
      final fields = {...json}..remove('artifactChecksum');
      if (json['artifactChecksum'] != prepFingerprint(fields)) {
        throw const FormatException('Energy artifact checksum mismatch.');
      }
      final features = json['features'];
      final weights = json['weights'];
      final coverage = json['featureCoverage'];
      final bounds = json['window'];
      if (features is! List ||
          features.length != featureNames.length ||
          List.generate(
            featureNames.length,
            (i) => i,
          ).any((i) => features[i] != featureNames[i]) ||
          weights is! List ||
          weights.length != featureNames.length ||
          coverage is! Map ||
          !_sameKeys(coverage, featureNames.toSet()) ||
          bounds is! Map ||
          !_sameKeys(bounds, {'start', 'end', 'timezone'})) {
        throw const FormatException('Incompatible Energy feature schema.');
      }
      final count = json['labelCount'];
      final owner = json['ownerKey'];
      final fingerprint = json['fingerprint'];
      final checksum = RegExp(r'^[0-9a-f]{16}-[0-9]{1,9}$');
      if (count is! int ||
          count < 14 ||
          count >= 100 ||
          owner is! String ||
          !checksum.hasMatch(owner) ||
          fingerprint is! String ||
          !checksum.hasMatch(fingerprint)) {
        throw const FormatException('Invalid Energy model provenance.');
      }
      final at = _utcDate(json['trainedAt']);
      final window = PrepWindow.fromJson(Map<String, dynamic>.from(bounds));
      if (at.isBefore(window.start) ||
          canonicalPrepJson(bounds) != canonicalPrepJson(window.toJson())) {
        throw const FormatException('Invalid Energy training date.');
      }
      final baseline = _boundedNumber(json['deterministicMae'], 0, 100);
      final candidate = _boundedNumber(json['holdoutMae'], 0, 100);
      if (baseline <= 0 || candidate > baseline * .95) {
        throw const FormatException('Unvalidated Energy model.');
      }
      return EnergyResidualModel._(
        ownerKey: owner,
        trainedAt: at,
        window: window,
        fingerprint: fingerprint,
        labelCount: count,
        weights: weights.map((v) => _boundedNumber(v, -1000, 1000)).toList(),
        intercept: _boundedNumber(json['intercept'], -1000, 1000),
        holdoutMae: candidate,
        deterministicMae: baseline,
        featureCoverage: {
          for (final name in featureNames)
            name: _boundedNumber(coverage[name], 0, 1),
        },
      );
    } on Object catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('Invalid Energy model artifact.');
    }
  }

  /// Missing inputs remain null, never fabricated measurements. Masked terms
  /// contribute nothing; coverage also attenuates the intercept. Same-day
  /// context fades over 36h; baseline-derived features fade over 30 days (their
  /// age includes the oldest baseline evidence). Nothing can exceed ±10 points.
  /// A runtime budget miss asks the caller to retain deterministic scoring.
  double? correction({
    required Map<String, double?> features,
    required Map<String, double?> featureAgeHours,
  }) {
    final timer = Stopwatch()..start();
    final vector = _design(features, featureAgeHours);
    if (vector == null) return null;
    final value = _predict(vector, weights, intercept);
    return timer.elapsedMicroseconds < 1000 && value.isFinite ? value : null;
  }
}

class EnergyModelFit {
  const EnergyModelFit({
    required this.model,
    required this.reason,
    required this.trainingMicros,
    required this.workingBytes,
    this.baselineMae,
    this.candidateMae,
  });

  final EnergyResidualModel? model;
  final String reason;
  final int trainingMicros;

  /// Conservative payload estimate for numeric kernel buffers and row
  /// references, NOT a measured VM/GC heap or OS resident-memory delta. The
  /// already-cached snapshot/report is owned by prep and is not duplicated.
  final int workingBytes;
  final double? baselineMae;
  final double? candidateMae;
}

/// Nine-parameter, fixed λ=1 ridge solve. No network, randomness, learned
/// normalization, hyperparameter search, or holdout refit exists in this path.
abstract final class EnergyResidualTrainer {
  static EnergyModelFit train({
    required PrepSnapshot snapshot,
    required PrepReport report,
    required DateTime trainedAt,
  }) {
    final timer = Stopwatch()..start();
    var workingBytes = 0;
    double? baselineMae;
    double? candidateMae;
    EnergyModelFit finish(String reason, [EnergyResidualModel? model]) =>
        EnergyModelFit(
          model: model,
          reason: reason,
          trainingMicros: timer.elapsedMicroseconds,
          workingBytes: workingBytes,
          baselineMae: baselineMae,
          candidateMae: candidateMae,
        );
    try {
      if (!snapshot.consent.allowed) return finish('consent_required');
      if (snapshot.isTruncated) return finish('document_cap_reached');
      if (snapshot.uid.trim().isEmpty ||
          snapshot.schemaVersion < 1 ||
          trainedAt.isBefore(snapshot.fetchedAt)) {
        return finish('invalid_snapshot');
      }
      final summary = report.identity;
      final fingerprint = snapshot.fingerprint;
      if (summary['fingerprint'] != fingerprint ||
          summary['schemaVersion'] != snapshot.schemaVersion ||
          summary['reportVersion'] != 1 ||
          summary['hostTimezoneCompatible'] != true ||
          canonicalPrepJson(summary['window']) !=
              canonicalPrepJson(snapshot.window.toJson())) {
        return finish('incompatible_prep_report');
      }
      if (!report.energyReady) return finish('energy_not_ready');
      final rows = report.examples.where((row) => row.head == 'energy').toList()
        ..sort((a, b) => a.observedAt.compareTo(b.observedAt));
      if (rows.length < 14 || rows.length >= 100) {
        return finish('insufficient_energy_labels');
      }
      final days = rows.map((row) => row.day).toSet().toList()..sort();
      if (days.length < 14 || days.length > 30) {
        return finish('insufficient_labeled_days');
      }
      final holdoutDays = days
          .skip(days.length - math.max(3, (days.length * .2).ceil()))
          .toSet();
      final outcomeIds = <String>{};
      final sourceIds = <String>{};
      final outcomes = <String, Map<String, dynamic>>{};
      final sources = <String, Map<String, dynamic>>{};
      final featureEvidence = <String, Map<String, dynamic>>{};
      for (final entry in {
        'signals': snapshot.signals,
        'checkIns': snapshot.checkIns,
      }.entries) {
        for (final raw in entry.value) {
          final key = '${entry.key}/${raw['id']}:${raw['source'] ?? 'manual'}';
          if (featureEvidence.containsKey(key)) {
            return finish('duplicate_or_invalid_source');
          }
          featureEvidence[key] = raw;
        }
      }
      for (final raw in snapshot.outcomes) {
        final id = raw['id'];
        if (id is! String || outcomes.containsKey(id)) {
          return finish('duplicate_or_invalid_outcome');
        }
        outcomes[id] = raw;
      }
      for (final raw in snapshot.checkIns) {
        final id = raw['id'];
        if (id is! String || sources.containsKey(id)) {
          return finish('duplicate_or_invalid_source');
        }
        sources[id] = raw;
      }
      // Validate labels, provenance, missingness and whole-day membership
      // independently of the prep readiness flag. Cognitive rows are ignored.
      for (final row in rows) {
        final raw = outcomes[row.outcomeId];
        final source = sources[raw?['sourceId']];
        if (!outcomeIds.add(row.outcomeId) ||
            raw == null ||
            source == null ||
            !sourceIds.add(raw['sourceId'] as String) ||
            !_genuine(raw, outcome: true) ||
            !_genuine(source) ||
            raw['type'] != 'observedEnergy' ||
            raw['source'] != 'checkIn' ||
            raw['value'] != row.label ||
            source['energy'] != row.label ||
            raw['consentVersion'] != 1 ||
            row.consentVersion != 1 ||
            row.labelUnit != 'rating_1_10' ||
            !row.label.isFinite ||
            row.label < 1 ||
            row.label > 10 ||
            row.target == null ||
            !row.target!.isFinite ||
            (row.target! - (row.label - 1) * 100 / 9).abs() > 1e-9 ||
            row.reference == null ||
            !row.reference!.isFinite ||
            row.reference! < 0 ||
            row.reference! > 100 ||
            !snapshot.window.contains(row.observedAt) ||
            row.observedAt.isAfter(trainedAt) ||
            row.day != snapshot.window.dayKey(row.observedAt) ||
            snapshot.window.parseTime(raw['observedAt']) != row.observedAt ||
            snapshot.window.parseTime(source['timestamp']) != row.observedAt ||
            !_availableBy(raw, trainedAt, snapshot.window) ||
            row.warnings.any(
              (warning) => warning != 'baseline_cold_start_or_missing',
            ) ||
            row.split !=
                (holdoutDays.contains(row.day) ? 'holdout' : 'training') ||
            row.features.values.whereType<double>().length < 4 ||
            _design(row.features, row.featureAgeHours) == null ||
            !_sameKeys(
              row.featureSources,
              EnergyResidualModel.featureNames.toSet(),
            ) ||
            !_historicalFeatures(
              row,
              featureEvidence,
              raw['sourceId'] as String,
              snapshot.window,
            ) ||
            row.featureSources.entries.any(
              (entry) =>
                  row.features[entry.key] != null && entry.value.isEmpty ||
                  entry.value.any(
                    (id) => id.startsWith('checkIns/${raw['sourceId']}:'),
                  ),
            )) {
          return finish('invalid_training_evidence');
        }
      }
      final training = rows.where((row) => row.split == 'training').toList();
      final holdout = rows.where((row) => row.split == 'holdout').toList();
      if (training.isEmpty ||
          holdout.isEmpty ||
          !training.last.observedAt.isBefore(holdout.first.observedAt)) {
        return finish('invalid_temporal_split');
      }
      // Fixed 9×9 matrix, RHS, coefficients and a reusable-size design vector.
      // Include conservative slots for list/map references used by validation.
      workingBytes =
          (81 +
              9 * 6 +
              rows.length * 8 +
              snapshot.outcomes.length * 8 +
              snapshot.checkIns.length * 8 +
              featureEvidence.length * 16) *
          8;
      if (workingBytes >= 1024 * 1024) return finish('memory_budget_exceeded');
      final gram = Float64List(81);
      final rhs = Float64List(9);
      for (final row in training) {
        final x = _design(row.features, row.featureAgeHours)!;
        final residual = row.target! - row.reference!;
        for (var i = 0; i < 9; i++) {
          rhs[i] += x[i] * residual;
          for (var j = 0; j < 9; j++) {
            gram[i * 9 + j] += x[i] * x[j];
          }
        }
      }
      // λ is fixed at 1. Intercept also regularized, avoiding singularity for
      // constant or entirely absent training columns without special fitting.
      for (var i = 0; i < 9; i++) {
        gram[i * 9 + i] += 1;
      }
      final coefficients = _solve(gram, rhs);
      if (coefficients == null || coefficients.any((v) => v.abs() > 1000)) {
        return finish('unsafe_coefficients');
      }
      final weights = coefficients.skip(1).toList(growable: false);
      var baselineError = 0.0;
      var candidateError = 0.0;
      for (final row in holdout) {
        final delta = _predict(
          _design(row.features, row.featureAgeHours)!,
          weights,
          coefficients[0],
        );
        // Match ScoreSnapshot's deployed integer score, including rounding.
        final prediction = (row.reference! + delta).round().clamp(0, 100);
        baselineError += (row.target! - row.reference!).abs();
        candidateError += (row.target! - prediction).abs();
      }
      baselineMae = baselineError / holdout.length;
      candidateMae = candidateError / holdout.length;
      if (!baselineMae.isFinite ||
          !candidateMae.isFinite ||
          baselineMae <= 0 ||
          candidateMae > baselineMae * .95) {
        return finish('holdout_underperformance');
      }
      final model = EnergyResidualModel._(
        ownerKey: prepFingerprint({'uid': snapshot.uid}),
        trainedAt: trainedAt.toUtc(),
        window: snapshot.window,
        fingerprint: fingerprint,
        labelCount: rows.length,
        weights: weights,
        intercept: coefficients[0],
        holdoutMae: candidateMae,
        deterministicMae: baselineMae,
        featureCoverage: {
          for (final name in EnergyResidualModel.featureNames)
            name:
                training.where((row) => row.features[name] != null).length /
                training.length,
        },
      );
      // Round-trip through the same strict validator used after app restart.
      EnergyResidualModel.fromJson(model.toJson());
      if (timer.elapsedMicroseconds >= 100000) {
        return finish('training_budget_exceeded');
      }
      return finish('accepted', model);
    } on Object {
      return finish('invalid_training_evidence');
    }
  }
}

bool _sameKeys(Map map, Set<String> keys) =>
    map.length == keys.length && keys.every(map.containsKey);

double _boundedNumber(Object? value, double lower, double upper) {
  if (value is! num || !value.isFinite || value < lower || value > upper) {
    throw const FormatException('Invalid Energy model number.');
  }
  return value.toDouble();
}

DateTime _utcDate(Object? value) {
  if (value is! String || !value.endsWith('Z')) {
    throw const FormatException('Energy model timestamps require UTC.');
  }
  final at = DateTime.parse(value).toUtc();
  if (at.toIso8601String() != value) {
    throw const FormatException('Invalid Energy model timestamp.');
  }
  return at;
}

Float64List? _design(Map<String, double?> values, Map<String, double?> ages) {
  const names = EnergyResidualModel.featureNames;
  if (!_sameKeys(values, names.toSet()) || !_sameKeys(ages, names.toSet())) {
    return null;
  }
  final x = Float64List(9);
  var coverage = 0.0;
  for (var i = 0; i < names.length; i++) {
    final value = values[names[i]];
    final age = ages[names[i]];
    if (value == null) {
      if (age != null) return null;
      continue;
    }
    if (!value.isFinite ||
        value.abs() > 1 ||
        age == null ||
        !age.isFinite ||
        age < 0) {
      return null;
    }
    final horizon =
        names[i] == 'sleepDeviation' || names[i] == 'recoveryDeviation'
        ? 30 * 24.0
        : 36.0;
    final freshness = (1 - age / horizon).clamp(0.0, 1.0);
    coverage += freshness / names.length;
    x[i + 1] = value * freshness;
  }
  // The exact same attenuated design is used in fitting, holdout and serving.
  x[0] = coverage;
  for (var i = 1; i < x.length; i++) {
    x[i] *= coverage;
  }
  return x;
}

double _predict(Float64List x, List<double> weights, double intercept) {
  var raw = x[0] * intercept;
  for (var i = 0; i < weights.length; i++) {
    raw += x[i + 1] * weights[i];
  }
  return raw
      .clamp(
        -EnergyResidualModel.maximumCorrection,
        EnergyResidualModel.maximumCorrection,
      )
      .toDouble();
}

/// Cholesky solve in place; fixed positive ridge makes X'X + I SPD.
Float64List? _solve(Float64List matrix, Float64List rhs) {
  for (var i = 0; i < 9; i++) {
    for (var j = 0; j <= i; j++) {
      var value = matrix[i * 9 + j];
      for (var k = 0; k < j; k++) {
        value -= matrix[i * 9 + k] * matrix[j * 9 + k];
      }
      if (!value.isFinite || i == j && value <= 0) return null;
      matrix[i * 9 + j] = i == j ? math.sqrt(value) : value / matrix[j * 9 + j];
    }
  }
  final answer = Float64List(9);
  for (var i = 0; i < 9; i++) {
    var value = rhs[i];
    for (var j = 0; j < i; j++) {
      value -= matrix[i * 9 + j] * answer[j];
    }
    answer[i] = value / matrix[i * 9 + i];
  }
  for (var i = 8; i >= 0; i--) {
    var value = answer[i];
    for (var j = i + 1; j < 9; j++) {
      value -= matrix[j * 9 + i] * answer[j];
    }
    answer[i] = value / matrix[i * 9 + i];
  }
  return answer.every((value) => value.isFinite) ? answer : null;
}

bool _genuine(Map<String, dynamic> raw, {bool outcome = false}) {
  if (raw['_prepForeignAccount'] == true ||
      raw['synthetic'] == true ||
      raw['isSynthetic'] == true ||
      raw['source'] == 'model') {
    return false;
  }
  final marker = [
    'id',
    'sourceId',
    'groupId',
    'note',
    'provenance',
  ].map((key) => raw[key]?.toString() ?? '').join(' ').toLowerCase();
  if (RegExp(
    r'(^|[^a-z])(seed(?:ed)?|synthetic|fake|demo|fixture|cohort)([^a-z]|$)',
  ).hasMatch(marker)) {
    return false;
  }
  return outcome ||
      ['observed', 'real'].contains(raw['provenance']) ||
      raw['source'] == 'healthKit' ||
      RegExp(
        r'^(manual|checkin|activity|sleep)-\d{10,}',
      ).hasMatch(raw['id']?.toString() ?? '');
}

bool _historicalFeatures(
  TrainingExample row,
  Map<String, Map<String, dynamic>> evidence,
  String excludedId,
  PrepWindow window,
) {
  for (final name in EnergyResidualModel.featureNames) {
    final sources = row.featureSources[name]!;
    if (row.features[name] == null) {
      if (sources.isNotEmpty) return false;
      continue;
    }
    var maximumAge = 0.0;
    for (final key in sources) {
      final raw = evidence[key];
      if (raw == null || raw['id'] == excludedId || !_genuine(raw)) {
        return false;
      }
      final observed = window.parseTime(raw['timestamp']);
      if (observed == null ||
          !window.contains(observed) ||
          observed.isAfter(row.observedAt)) {
        return false;
      }
      var hasAvailability = false;
      for (final field in [
        'recordedAt',
        'createdAt',
        'updatedAt',
        'syncedAt',
      ]) {
        if (raw[field] == null) continue;
        hasAvailability = true;
        final at = window.parseTime(raw[field]);
        if (at == null || at.isAfter(row.observedAt)) return false;
      }
      if (!hasAvailability) return false;
      maximumAge = math.max(
        maximumAge,
        row.observedAt.difference(observed).inMinutes / 60,
      );
    }
    if (row.featureAgeHours[name] != maximumAge) return false;
  }
  return true;
}

bool _availableBy(Map<String, dynamic> raw, DateTime at, PrepWindow window) {
  final recorded = window.parseTime(raw['recordedAt']);
  final observed = window.parseTime(raw['observedAt']);
  if (recorded == null ||
      observed == null ||
      recorded.isBefore(observed) ||
      recorded.isAfter(at)) {
    return false;
  }
  for (final field in ['createdAt', 'updatedAt', 'syncedAt']) {
    if (raw[field] == null) continue;
    final timestamp = window.parseTime(raw[field]);
    if (timestamp == null || timestamp.isAfter(at)) return false;
  }
  return true;
}
