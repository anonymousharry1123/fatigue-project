import 'dart:convert';

import 'ml_prep_builder.dart';
import 'ml_prep_models.dart';

/// A read-only projection of the small, accepted-model summary in Firebase.
///
/// This is not an executable model: it contains no weights, examples, account
/// identifiers, or predictions, and its presence does not enable local training
/// or prove that a model is currently active on this device.
class EnergyModelSummary {
  EnergyModelSummary._({
    required this.modelVersion,
    required this.schemaVersion,
    required this.trainedAt,
    required this.windowStart,
    required this.windowEnd,
    required this.timezone,
    required this.labelCount,
    required this.holdoutMae,
    required this.deterministicMae,
    required Map<String, double> featureCoverage,
  }) : featureCoverage = Map.unmodifiable(featureCoverage);

  final int modelVersion;
  final int schemaVersion;
  final DateTime trainedAt;
  final DateTime windowStart;
  final DateTime windowEnd;
  final String timezone;
  final int labelCount;
  final double holdoutMae;
  final double deterministicMae;
  final Map<String, double> featureCoverage;

  /// Reduction in held-out Energy error, not confidence or health improvement.
  double get improvementPercent => (1 - holdoutMae / deterministicMae) * 100;

  /// Missing, unsupported, or malformed summaries are safely treated as absent.
  /// Firestore-specific timestamp conversion belongs in the repository adapter.
  static EnergyModelSummary? tryParse(Object? value) {
    if (value is! Map ||
        !_exactKeys(value, const {
          'modelVersion',
          'schemaVersion',
          'window',
          'trainedAt',
          'labelCount',
          'holdoutMae',
          'deterministicMae',
          'featureCoverage',
        }) ||
        value['modelVersion'] is! int ||
        value['modelVersion'] != 1 ||
        value['schemaVersion'] is! int ||
        value['schemaVersion'] != 1) {
      return null;
    }
    final window = value['window'];
    final coverage = value['featureCoverage'];
    final count = value['labelCount'];
    final candidate = value['holdoutMae'];
    final baseline = value['deterministicMae'];
    if (window is! Map ||
        !_exactKeys(window, const {'start', 'end', 'timezone'}) ||
        window['timezone'] is! String ||
        (window['timezone'] as String).isEmpty ||
        (window['timezone'] as String).length > 100 ||
        count is! int ||
        count < 14 ||
        count > 100 ||
        !_boundedNumber(candidate, 100) ||
        !_boundedNumber(baseline, 100) ||
        (baseline as num) <= 0 ||
        (candidate as num) > baseline * .95 ||
        coverage is! Map ||
        !_exactKeys(coverage, MlPrepBuilder.energyFeatureNames.toSet()) ||
        !coverage.values.every((entry) => _boundedNumber(entry, 1))) {
      return null;
    }
    final trainedAt = _utcDate(value['trainedAt']);
    final start = _utcDate(window['start']);
    final end = _utcDate(window['end']);
    if (trainedAt == null ||
        start == null ||
        end == null ||
        trainedAt.isBefore(start)) {
      return null;
    }
    try {
      final bounds = PrepWindow.fromJson({
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        // The timezone database uses Etc/UTC; accept the conventional UTC alias
        // on read just as PrepWindow.endingOn does when creating a window.
        'timezone': window['timezone'] == 'UTC'
            ? 'Etc/UTC'
            : window['timezone'],
      });
      final summary = EnergyModelSummary._(
        modelVersion: 1,
        schemaVersion: 1,
        trainedAt: trainedAt,
        windowStart: bounds.start,
        windowEnd: bounds.end,
        timezone: bounds.timezone,
        labelCount: count,
        holdoutMae: candidate.toDouble(),
        deterministicMae: baseline.toDouble(),
        featureCoverage: {
          for (final feature in MlPrepBuilder.energyFeatureNames)
            feature: (coverage[feature] as num).toDouble(),
        },
      );
      if (utf8.encode(jsonEncode(summary.toJson())).length > 4096) {
        return null;
      }
      return summary;
    } on Object {
      return null;
    }
  }

  Map<String, Object?> toJson() => {
    'modelVersion': modelVersion,
    'schemaVersion': schemaVersion,
    'window': {
      'start': windowStart.toIso8601String(),
      'end': windowEnd.toIso8601String(),
      'timezone': timezone,
    },
    'trainedAt': trainedAt.toIso8601String(),
    'labelCount': labelCount,
    'holdoutMae': holdoutMae,
    'deterministicMae': deterministicMae,
    'featureCoverage': Map<String, double>.of(featureCoverage),
  };

  static bool _exactKeys(Map value, Set<String> keys) =>
      value.length == keys.length && keys.every(value.containsKey);

  static bool _boundedNumber(Object? value, double maximum) =>
      value is num && value.isFinite && value >= 0 && value <= maximum;

  static DateTime? _utcDate(Object? value) {
    if (value is DateTime) value = value.toUtc().toIso8601String();
    if (value is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$',
        ).hasMatch(value)) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    // DateTime.parse normalizes impossible dates; do not display those as true.
    return parsed != null &&
            parsed.isUtc &&
            parsed.toIso8601String().substring(0, 19) == value.substring(0, 19)
        ? parsed
        : null;
  }
}
