import 'dart:convert';

import 'check_in_measurement.dart';
import 'evidence_provenance.dart';
import 'models.dart';
import 'self_report_trends_logic.dart';

/// Explicit, device-only analysis export. No account details or notes enter it.
abstract final class ResearchExport {
  static const version = 'tonyo-measurement-export-v1';

  static bool validStudyCode(String value) =>
      RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,31}$').hasMatch(value);

  static ResearchExportBundle build({
    required Iterable<DailyCheckIn> checkIns,
    required Iterable<SignalReading> signals,
    required String studyCode,
    required DateTime generatedAt,
  }) {
    if (!validStudyCode(studyCode)) {
      throw ArgumentError(
        'Use a study code of 1–32 letters, numbers, - or _, starting with a letter.',
      );
    }
    final exclusions = <String, int>{};
    final ambiguous = <String>{};
    void exclude(String reason) =>
        exclusions.update(reason, (n) => n + 1, ifAbsent: () => 1);
    final unique = <String, DailyCheckIn>{};
    for (final report in checkIns) {
      final old = unique[report.id];
      if (old == null) {
        unique[report.id] = report;
      } else {
        exclude('duplicate_id');
        final order = (report.recordedAt ?? report.timestamp).compareTo(
          old.recordedAt ?? old.timestamp,
        );
        // Conflicting equal-time copies have no authoritative revision. Exclude
        // their identity, rather than export an arbitrarily chosen answer.
        if (order > 0) {
          unique[report.id] = report;
          ambiguous.remove(report.id);
        }
        if (order == 0 && _reportKey(report) != _reportKey(old)) {
          ambiguous.add(report.id);
        }
      }
    }
    final reports = <DailyCheckIn>[];
    for (final report in unique.values) {
      if (ambiguous.contains(report.id)) {
        exclude('conflicting_duplicate_id');
      } else if (_syntheticReport(report)) {
        exclude('synthetic');
      } else if (!report.isResearchCheckIn) {
        exclude('legacy');
      } else if (!report.isValidResearchResponse) {
        exclude('invalid');
      } else if (report.questionnaireVersion !=
          CheckInMeasurement.currentVersion) {
        exclude('unsupported_version');
      } else if (report.timestamp.isAfter(generatedAt) ||
          report.recordedAt!.isAfter(generatedAt)) {
        exclude('future_or_unavailable');
      } else {
        reports.add(report);
      }
    }
    reports.sort((a, b) {
      final order = a.timestamp.compareTo(b.timestamp);
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
    final sourceSignals = signals.toList(growable: false);
    final definitions = <String, Map<String, dynamic>>{};
    final definitionKeys = <String, String>{};
    final sleepRows = <String, Map<String, Object?>>{};
    final rows = <Map<String, Object?>>[];
    for (final report in reports) {
      final key = _canonical(report.questionnaireSnapshot);
      final definitionId = definitionKeys.putIfAbsent(
        key,
        () => 'definition-${definitionKeys.length + 1}',
      );
      definitions[definitionId] = report.questionnaireSnapshot!;
      final sleep = SelfReportTrendsLogic.matchSleep(
        report,
        sourceSignals,
        generatedAt,
      );
      final reading = sleep.reading;
      String? sleepId;
      if (sleep.isMatched && reading != null) {
        final times = [
          reading.recordedAt,
          reading.syncedAt,
        ].whereType<DateTime>().toList()..sort();
        final availableAt = times.lastOrNull;
        final row = sleepRows.putIfAbsent(
          reading.id,
          () => {
            'sleep_ref': 'sleep-${sleepRows.length + 1}',
            'sleep_end_at_utc': reading.timestamp.toUtc().toIso8601String(),
            'duration_hours': sleep.durationHours,
            'source': reading.source.name,
            'record_available_at_utc': availableAt?.toUtc().toIso8601String(),
            'availability_known': availableAt != null,
            'recorded_at_utc': reading.recordedAt?.toUtc().toIso8601String(),
            'synced_at_utc': reading.syncedAt?.toUtc().toIso8601String(),
            'quality': reading.quality,
          },
        );
        sleepId = row['sleep_ref'] as String;
      }
      rows.add({
        'study_code': studyCode,
        'response_ref': 'response-${rows.length + 1}',
        'observed_at_utc': report.timestamp.toUtc().toIso8601String(),
        'recorded_at_utc': report.recordedAt!.toUtc().toIso8601String(),
        'local_date': report.localDate,
        'timezone': report.timezone,
        'utc_offset_minutes': report.utcOffsetMinutes,
        'period': report.period.name,
        'questionnaire_version': report.questionnaireVersion,
        'questionnaire_language': report.questionnaireLanguage,
        'definition_ref': definitionId,
        'source': report.source,
        'completion_status': report.completionStatus,
        'answered_item_count': report.answeredItemCount,
        for (final entry in report.ratings.entries)
          '${entry.key}_1_to_10': entry.value,
        'sleep_ref': sleepId,
        'sleep_hours': sleep.durationHours,
        'sleep_match_status': sleep.isMatched ? 'matched' : sleep.reason,
        'sleep_pair_available_at_utc': sleep.availableAt
            ?.toUtc()
            .toIso8601String(),
        'sleep_pair_availability_known': sleep.isMatched
            ? sleep.availabilityKnown
            : null,
      });
    }
    final columns = _dictionary.keys.toList(growable: false);
    final csv = [
      columns.map(_csv).join(','),
      for (final row in rows) columns.map((name) => _csv(row[name])).join(','),
    ].join('\r\n');
    final payload = {
      'exportVersion': version,
      'generatedAtUtc': generatedAt.toUtc().toIso8601String(),
      'scope':
          'Saved device observations, including pending local edits; not a fresh cloud export.',
      'studyCode': studyCode,
      'researchProtocolApproved': false,
      'rowPolicy':
          'One row per retained valid current-format submission, including partial responses. Repeated dates are retained; rows are not independent participants or scheduled outcomes.',
      'missingness':
          'JSON null / empty CSV field means unanswered or unavailable, never zero or midpoint.',
      'privacy':
          'Sensitive pseudonymized data, not anonymous. Names, account IDs, emails, notes and original record IDs are excluded. Export-local references are not stable identifiers across exports.',
      'sleepPairingPolicy':
          'Descriptive retrospective match: unambiguous main sleep ending within 24 hours before the response. Saved records available at export time may include later edits. Not a reviewed research join or a historical prediction feature snapshot.',
      'excludedCounts': exclusions,
      'dataDictionary': _dictionary,
      'sleepObservationDictionary': {
        'sleep_ref':
            'Export-local reference shared by response rows that select this raw sleep record.',
        'sleep_end_at_utc':
            'Recorded main-sleep end instant in ISO-8601 UTC. No bedtime is inferred from duration.',
        'duration_hours':
            'Raw recorded main-sleep duration in hours; not a 24-hour total.',
        'source':
            'manual estimate or healthKit import, preserved from the selected record.',
        'record_available_at_utc':
            'Latest known raw recorded_at_utc/synced_at_utc; null when both are unknown. Pair dependencies are described separately on each response.',
        'availability_known':
            'Whether the selected raw record has a known save/import time.',
        'recorded_at_utc':
            'Original manual save/edit time, or null when unknown.',
        'synced_at_utc':
            'Original import availability time, or null when unknown.',
        'quality':
            'Stored engineering source-quality field, not a clinical accuracy probability.',
      },
      'questionnaireDefinitions': definitions,
      'sleepObservations': sleepRows.values.toList(),
      'responses': rows,
    };
    return ResearchExportBundle(
      json: const JsonEncoder.withIndent('  ').convert(payload),
      csv: '$csv\r\n',
      responseCount: rows.length,
      partialCount: rows
          .where((row) => row['completion_status'] == 'partial')
          .length,
      pairedCount: rows.where((row) => row['sleep_ref'] != null).length,
      excludedCount: exclusions.values.fold(0, (sum, count) => sum + count),
    );
  }

  static bool _syntheticReport(DailyCheckIn row) =>
      row.id.toLowerCase().startsWith('syn-') ||
      EvidenceProvenance.hasDemoMarker([row.id, row.note]);

  static String _reportKey(DailyCheckIn row) => _canonical({
    'timestamp': row.timestamp.toUtc().toIso8601String(),
    'recordedAt': row.recordedAt?.toUtc().toIso8601String(),
    'ratings': row.ratings,
    'period': row.period.name,
    'localDate': row.localDate,
    'offset': row.utcOffsetMinutes,
    'timezone': row.timezone,
    'version': row.questionnaireVersion,
    'language': row.questionnaireLanguage,
    'definition': row.questionnaireSnapshot,
    'source': row.source,
    'note': row.note,
    'legacyRatings': row.originalLegacyRatings,
    'legacyPeriodMissing': row.legacyPeriodMissing,
  });

  static String _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_canonical(value[key])}').join(',')}}';
    }
    if (value is List) return '[${value.map(_canonical).join(',')}]';
    if (value is num && !value.isFinite) return 'invalid:${value.toString()}';
    return jsonEncode(value);
  }

  static String _csv(Object? value) {
    if (value == null) return '';
    var text = value is num && value == value.roundToDouble()
        ? '${value.toInt()}'
        : '$value';
    if (value is String && RegExp(r'^[\s]*[=+\-@]').hasMatch(text)) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }

  static const _dictionary = <String, String>{
    'study_code': 'User-supplied pseudonymous study code; not an account ID.',
    'response_ref':
        'Export-local response reference. Not stable across exports.',
    'observed_at_utc': 'Actual observation instant, ISO-8601 UTC.',
    'recorded_at_utc': 'Save/edit availability instant, ISO-8601 UTC.',
    'local_date':
        'Captured local calendar date, YYYY-MM-DD; not reassigned during travel.',
    'timezone': 'Captured IANA identifier; null when unknown.',
    'utc_offset_minutes': 'Captured offset from UTC in minutes.',
    'period':
        'Explicitly selected morning/evening; not inferred from clock time.',
    'questionnaire_version':
        'Technical wording version, not protocol approval.',
    'questionnaire_language':
        'Captured wording language, not current UI preference.',
    'definition_ref': 'Exact wording/anchors in questionnaireDefinitions.',
    'source':
        'selfReport; excludes legacy, demo and model-derived observations.',
    'completion_status': 'complete (six answers) or partial (one to five).',
    'answered_item_count': 'Number of retained non-null responses, 1–6.',
    'energy_1_to_10': 'Raw Energy integer 1–10; null if unanswered.',
    'fatigue_1_to_10': 'Raw Fatigue integer 1–10; null if unanswered.',
    'sleepiness_1_to_10': 'Raw Sleepiness integer 1–10; null if unanswered.',
    'focus_1_to_10': 'Raw Focus integer 1–10; null if unanswered.',
    'mood_1_to_10': 'Raw Mood integer 1–10; null if unanswered.',
    'stress_1_to_10': 'Raw Stress integer 1–10; null if unanswered.',
    'sleep_ref': 'Export-local link into sleepObservations; null if unmatched.',
    'sleep_hours':
        'Matched recorded main-sleep duration in hours; manual estimate or Health import, not 24-hour total or nap recovery.',
    'sleep_match_status':
        'matched or explicit exclusion/unavailability reason; see sleepPairingPolicy.',
    'sleep_pair_available_at_utc':
        'Latest known availability among the records needed for this particular match. Null if any dependency has unknown availability or the row is unmatched.',
    'sleep_pair_availability_known':
        'True only when all matching dependencies have a known save/import time; false when any are unknown; null when unmatched. Separate from the raw sleep record availability.',
  };
}

class ResearchExportBundle {
  const ResearchExportBundle({
    required this.json,
    required this.csv,
    required this.responseCount,
    required this.partialCount,
    required this.pairedCount,
    required this.excludedCount,
  });
  final String json;
  final String csv;
  final int responseCount;
  final int partialCount;
  final int pairedCount;
  final int excludedCount;
}
