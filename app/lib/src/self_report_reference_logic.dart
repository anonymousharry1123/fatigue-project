import 'dart:convert';

import 'check_in_measurement.dart';
import 'evidence_provenance.dart';
import 'models.dart';

/// A descriptive, display-only comparison with the person's own recent reports.
/// These engineering defaults are not an approved research protocol, a clinical
/// range, or input to the energy model.
abstract final class SelfReportReferenceLogic {
  static const windowDays = 28;
  static const minimumDays = 7;

  static SelfReportReferenceSummary build({
    required Iterable<DailyCheckIn> checkIns,
    required DailyCheckIn current,
    required DateTime asOf,
  }) {
    // Calendar arithmetic uses the date captured with the response, never the
    // device's present timezone or 24-hour differences between observations.
    final currentDate = _capturedDate(current.localDate);
    final firstDate = currentDate?.subtract(const Duration(days: windowDays));
    final lastDate = currentDate?.subtract(const Duration(days: 1));
    final currentCompatible =
        _genuineCurrentFormat(current) &&
        current.isValidResearchResponse &&
        !current.timestamp.isAfter(asOf) &&
        !current.recordedAt!.isAfter(asOf);
    final samples = <String, List<double>>{
      for (final id in DailyCheckIn.measurementIds) id: [],
    };

    if (currentCompatible) {
      // Resolve identity before eligibility. An invalid, cleared, or not-yet-
      // available revision must not resurrect an older copy of that response.
      final revisions = <String, DailyCheckIn>{};
      for (final response in checkIns) {
        final previous = revisions[response.id];
        if (previous == null || _compareRevision(response, previous) > 0) {
          revisions[response.id] = response;
        }
      }

      final days = <String, DailyCheckIn>{};
      for (final response in revisions.values) {
        if (response.id == current.id ||
            !_genuineCurrentFormat(response) ||
            response.period != current.period ||
            response.questionnaireLanguage != current.questionnaireLanguage ||
            !_deepEqual(
              response.questionnaireSnapshot,
              current.questionnaireSnapshot,
            ) ||
            response.recordedAt == null ||
            response.recordedAt!.isAfter(asOf) ||
            response.timestamp.isAfter(asOf) ||
            !response.timestamp.isBefore(current.timestamp)) {
          continue;
        }
        final date = _capturedDate(response.localDate);
        if (date == null ||
            date.isBefore(firstDate!) ||
            !date.isBefore(currentDate!)) {
          continue;
        }
        final previous = days[response.localDate!];
        if (previous == null || _compareSubmission(response, previous) > 0) {
          days[response.localDate!] = response;
        }
      }

      // Select a single submission for the day before examining its answers.
      // A later cleared or invalid response never falls back to an earlier
      // answered value on that day.
      for (final response in days.values) {
        if (!response.isValidResearchResponse) continue;
        for (final entry in response.ratings.entries) {
          if (entry.value != null) samples[entry.key]!.add(entry.value!);
        }
      }
    }

    return SelfReportReferenceSummary(
      windowDays: windowDays,
      minimumDays: minimumDays,
      startDate: firstDate == null ? '' : _dateText(firstDate),
      endDate: lastDate == null ? '' : _dateText(lastDate),
      currentCompatible: currentCompatible,
      metrics: {
        for (final id in DailyCheckIn.measurementIds)
          id: _metric(
            samples[id]!,
            currentCompatible ? current.ratings[id] : null,
          ),
      },
    );
  }

  static SelfReportReferenceMetric _metric(
    List<double> samples,
    double? currentValue,
  ) {
    final average = samples.length < minimumDays
        ? null
        : samples.reduce((a, b) => a + b) / samples.length;
    return SelfReportReferenceMetric(
      average: average,
      sampleCount: samples.length,
      currentValue: currentValue,
      difference: average == null || currentValue == null
          ? null
          : currentValue - average,
    );
  }

  static bool _genuineCurrentFormat(DailyCheckIn response) =>
      response.questionnaireVersion == CheckInMeasurement.currentVersion &&
      response.source == 'selfReport' &&
      response.id.isNotEmpty &&
      !response.id.toLowerCase().startsWith('syn-') &&
      !EvidenceProvenance.hasDemoMarker([response.id, response.note]);

  static DateTime? _capturedDate(String? value) {
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final date = DateTime.tryParse('${value}T00:00:00Z');
    return date != null && _dateText(date) == value ? date : null;
  }

  static String _dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static int _compareRevision(DailyCheckIn a, DailyCheckIn b) {
    final saved = (a.recordedAt ?? a.timestamp).compareTo(
      b.recordedAt ?? b.timestamp,
    );
    return saved != 0 ? saved : _compareSubmission(a, b);
  }

  static int _compareSubmission(DailyCheckIn a, DailyCheckIn b) {
    final observed = a.timestamp.compareTo(b.timestamp);
    if (observed != 0) return observed;
    final saved = (a.recordedAt ?? a.timestamp).compareTo(
      b.recordedAt ?? b.timestamp,
    );
    if (saved != 0) return saved;
    final identity = a.id.compareTo(b.id);
    if (identity != 0) return identity;
    // Exact metadata ties lack an authoritative revision order. Prefer the
    // less complete copy, then a canonical content key, independent of input
    // iteration order. This never creates a rating from a cleared answer.
    final completeness = b.answeredItemCount.compareTo(a.answeredItemCount);
    return completeness != 0
        ? completeness
        : _contentKey(a).compareTo(_contentKey(b));
  }

  static bool _deepEqual(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every(
            (key) => b.containsKey(key) && _deepEqual(a[key], b[key]),
          );
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEqual(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  static String _contentKey(DailyCheckIn response) => _canonical({
    'ratings': response.ratings,
    'period': response.period.name,
    'note': response.note,
    'localDate': response.localDate,
    'timezone': response.timezone,
    'utcOffsetMinutes': response.utcOffsetMinutes,
    'questionnaireVersion': response.questionnaireVersion,
    'questionnaireLanguage': response.questionnaireLanguage,
    'source': response.source,
    'questionnaireSnapshot': response.questionnaireSnapshot,
    'originalLegacyRatings': response.originalLegacyRatings,
    'legacyPeriodMissing': response.legacyPeriodMissing,
  });

  static String _canonical(Object? value) {
    if (value is Map) {
      final entries =
          value.entries
              .map(
                (entry) =>
                    '${_canonical(entry.key)}:${_canonical(entry.value)}',
              )
              .toList()
            ..sort();
      return '{${entries.join(',')}}';
    }
    if (value is List) return '[${value.map(_canonical).join(',')}]';
    // toString also handles malformed non-finite ratings without invoking the
    // validated wire serializer while resolving duplicate identities.
    return '${value.runtimeType}:${jsonEncode(value?.toString())}';
  }
}

class SelfReportReferenceSummary {
  SelfReportReferenceSummary({
    required Map<String, SelfReportReferenceMetric> metrics,
    required this.windowDays,
    required this.minimumDays,
    required this.startDate,
    required this.endDate,
    required this.currentCompatible,
  }) : metrics = Map.unmodifiable(metrics);

  final Map<String, SelfReportReferenceMetric> metrics;
  final int windowDays;
  final int minimumDays;

  /// Inclusive captured calendar-date bounds; empty for an invalid date.
  final String startDate;
  final String endDate;
  final bool currentCompatible;
}

class SelfReportReferenceMetric {
  const SelfReportReferenceMetric({
    required this.average,
    required this.sampleCount,
    required this.currentValue,
    required this.difference,
  });

  final double? average;
  final int sampleCount;
  final double? currentValue;
  final double? difference;
}
