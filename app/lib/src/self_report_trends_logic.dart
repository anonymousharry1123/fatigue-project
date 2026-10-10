import 'dart:convert';

import 'check_in_measurement.dart';
import 'evidence_provenance.dart';
import 'models.dart';
import 'sleep_sync_logic.dart';

/// Raw descriptive trends and retrospective sleep pairs, not prediction
/// features, causal evidence, or an approved research matching protocol.
abstract final class SelfReportTrendsLogic {
  static const windowDays = 28;
  static const ineligibleResponseReason =
      'Check-in is not eligible for sleep pairing.';
  static const noSleepReason =
      'No eligible main sleep in the preceding 24 hours.';
  static const ambiguousSleepReason =
      'Multiple sleep summaries could match this check-in.';

  static SelfReportTrendsSummary build({
    required Iterable<DailyCheckIn> checkIns,
    required Iterable<SignalReading> signals,
    required DateTime now,
    required CheckInPeriod period,
    required String questionnaireLanguage,
    String? endDate,
  }) {
    final end = endDate == null
        ? DateTime.utc(
            now.toLocal().year,
            now.toLocal().month,
            now.toLocal().day,
          )
        : _date(endDate);
    if (end == null) throw ArgumentError.value(endDate, 'endDate');
    final start = end.subtract(const Duration(days: windowDays - 1));
    final revisions = <String, DailyCheckIn>{};
    for (final response in checkIns) {
      final previous = revisions[response.id];
      if (previous == null || _compareRevision(response, previous) > 0) {
        revisions[response.id] = response;
      }
    }
    final candidates = revisions.values.where((response) {
      final date = _date(response.localDate);
      return _genuine(response) &&
          response.period == period &&
          response.questionnaireLanguage == questionnaireLanguage &&
          _availableResponse(response, now) &&
          date != null &&
          !date.isBefore(start) &&
          !date.isAfter(end);
    }).toList()..sort(_compareSubmission);
    final definition = candidates
        .where((response) => response.isValidResearchResponse)
        .lastOrNull
        ?.questionnaireSnapshot;
    final selected = <String, DailyCheckIn>{};
    if (definition != null) {
      for (final response in candidates) {
        if (_equal(response.questionnaireSnapshot, definition)) {
          // Submission selection precedes rating validity and missingness.
          // Clearing an item or the entire report cannot revive earlier data.
          selected[response.localDate!] = response;
        }
      }
      selected.removeWhere((_, response) => !response.isValidResearchResponse);
    }
    final sleep = signals.toList();
    final days = List.generate(windowDays, (index) {
      final date = _dateText(start.add(Duration(days: index)));
      final response = selected[date];
      return SelfReportTrendDay(
        date: date,
        response: response,
        matchedSleep: response == null
            ? null
            : matchSleep(response, sleep, now),
      );
    });
    return SelfReportTrendsSummary(
      startDate: _dateText(start),
      endDate: _dateText(end),
      windowDays: windowDays,
      period: period,
      questionnaireLanguage: questionnaireLanguage,
      selectedReportCount: selected.length,
      days: days,
      series: {
        for (final id in DailyCheckIn.measurementIds)
          id: SelfReportTrendSeries(
            itemId: id,
            values: [for (final day in days) day.response?.ratings[id]],
            answeredCount: days
                .where((day) => day.response?.ratings[id] != null)
                .length,
            matchedCount: days
                .where(
                  (day) =>
                      day.response?.ratings[id] != null &&
                      day.matchedSleep?.isMatched == true,
                )
                .length,
          ),
      },
    );
  }

  /// Pairs raw main-sleep totals with a later report at viewing time. Known
  /// availability must be <= [asOf], but may be after the report. Unknown save/
  /// import time remains explicitly unknown; observation time is not a proxy.
  static SelfReportSleepMatch matchSleep(
    DailyCheckIn response,
    Iterable<SignalReading> signals,
    DateTime asOf,
  ) {
    if (!_genuine(response) ||
        !response.isValidResearchResponse ||
        !_availableResponse(response, asOf)) {
      return const SelfReportSleepMatch.unavailable(ineligibleResponseReason);
    }
    final revisions = <String, SignalReading>{};
    for (final signal in signals) {
      final prior = revisions[signal.id];
      if (prior == null || _compareSignalRevision(signal, prior) > 0) {
        revisions[signal.id] = signal;
      }
    }
    final rows = revisions.values
        .where((signal) => _usableSignal(signal, asOf))
        .toList();
    final candidates =
        rows.where((signal) {
          if (signal.type != SignalType.sleep ||
              (signal.groupId?.startsWith(
                    SleepSyncLogic.importedNapGroupPrefix,
                  ) ??
                  false) ||
              signal.value < 0.5 ||
              signal.value > 16 ||
              signal.timestamp.isAfter(response.timestamp)) {
            return false;
          }
          return response.timestamp.difference(signal.timestamp) <=
              const Duration(hours: 24);
        }).toList()..sort((a, b) {
          final instant = b.timestamp.compareTo(a.timestamp);
          return instant != 0 ? instant : b.id.compareTo(a.id);
        });
    if (candidates.isEmpty) {
      return const SelfReportSleepMatch.unavailable(noSleepReason);
    }

    final distinct = <SignalReading>[];
    for (final candidate in candidates) {
      if (!distinct.any(
        (other) =>
            candidate.source == other.source &&
            candidate.timestamp.isAtSameMomentAs(other.timestamp) &&
            candidate.value == other.value &&
            candidate.groupId == other.groupId,
      )) {
        distinct.add(candidate);
      }
    }
    final latest = distinct.first;
    final latestBedtime = _savedBedtime(latest, rows);
    final competing = <SignalReading>[latest];
    final timingDependencies = <SignalReading>[];
    for (final earlier in distinct.skip(1)) {
      // Only an actual saved bedtime can prove separate sessions. A main-
      // sleep total can exclude awake intervals; never subtract it from wake
      // time to invent a bedtime or establish non-overlap.
      if (latestBedtime != null &&
          !earlier.timestamp.isAfter(latestBedtime.timestamp)) {
        timingDependencies.add(latestBedtime);
      } else {
        competing.add(earlier);
      }
    }

    var chosen = latest;
    final dependencies = <SignalReading>[...timingDependencies];
    if (competing.length > 1) {
      if (competing.length != 2) {
        return const SelfReportSleepMatch.unavailable(ambiguousSleepReason);
      }
      final manual = competing
          .where((row) => row.source == SignalSource.manual)
          .firstOrNull;
      final health = competing
          .where((row) => row.source == SignalSource.healthKit)
          .firstOrNull;
      if (manual == null ||
          health == null ||
          !(health.groupId?.startsWith(SleepSyncLogic.importedGroupPrefix) ??
              false)) {
        return const SelfReportSleepMatch.unavailable(ambiguousSleepReason);
      }
      final manualBedtime = _savedBedtime(manual, rows);
      final healthBedtime = _savedBedtime(health, rows);
      final sameFinish = manual.timestamp.isAtSameMomentAs(health.timestamp);
      final savedOverlap =
          manualBedtime != null &&
          healthBedtime != null &&
          manualBedtime.timestamp.isBefore(health.timestamp) &&
          healthBedtime.timestamp.isBefore(manual.timestamp);
      if (!sameFinish && !savedOverlap) {
        return const SelfReportSleepMatch.unavailable(ambiguousSleepReason);
      }
      if (!sameFinish) dependencies.addAll([manualBedtime!, healthBedtime!]);
      final stages = rows
          .where(
            (row) =>
                row.groupId == health.groupId &&
                row.source == SignalSource.healthKit &&
                row.timestamp.isAtSameMomentAs(health.timestamp) &&
                SleepSyncLogic.detailedStageTypes.contains(row.type) &&
                row.value > 0 &&
                row.value <= 16,
          )
          .toList();
      final detailedHours = stages.fold<double>(
        0,
        (sum, row) => sum + row.value,
      );
      final validStages =
          stages.map((row) => row.type).toSet().length == stages.length &&
          detailedHours <= health.value + 0.000001;
      // Same completeness preference as SleepSyncLogic, applied only after
      // establishing a single competing manual/Health session. Do not use its
      // device-local wake-date grouping for historical travel observations.
      final preferHealth =
          validStages &&
          detailedHours / health.value >= 0.5 &&
          health.value >= manual.value * 0.8;
      chosen = preferHealth ? health : manual;
      if (preferHealth) dependencies.addAll(stages);
    }
    dependencies.add(chosen);
    final availabilityKnown = dependencies.every(
      (row) => _signalAvailability(row) != null,
    );
    DateTime? availableAt;
    if (availabilityKnown) {
      for (final row in dependencies) {
        final at = _signalAvailability(row)!;
        if (availableAt == null || at.isAfter(availableAt)) availableAt = at;
      }
    }
    return SelfReportSleepMatch.matched(
      chosen,
      availableAt: availableAt,
      availabilityKnown: availabilityKnown,
    );
  }

  static SignalReading? _savedBedtime(
    SignalReading sleep,
    List<SignalReading> rows,
  ) {
    if (sleep.groupId == null) return null;
    final bedtimes =
        rows
            .where(
              (row) =>
                  row.type == SignalType.bedtime &&
                  row.value >= 0 &&
                  row.value < 24 &&
                  row.groupId == sleep.groupId &&
                  row.source == sleep.source &&
                  row.timestamp.isBefore(sleep.timestamp) &&
                  sleep.timestamp.difference(row.timestamp) <=
                      const Duration(hours: 18) &&
                  sleep.value <=
                      sleep.timestamp.difference(row.timestamp).inMicroseconds /
                              Duration.microsecondsPerHour +
                          0.000001,
            )
            .toList()
          ..sort((a, b) => _compareSignalRevision(b, a));
    return bedtimes.isNotEmpty &&
            bedtimes.every(
              (row) => row.timestamp.isAtSameMomentAs(bedtimes.first.timestamp),
            )
        ? bedtimes.first
        : null;
  }

  static bool _usableSignal(SignalReading signal, DateTime asOf) =>
      signal.id.isNotEmpty &&
      signal.source != SignalSource.model &&
      signal.value.isFinite &&
      signal.quality.isFinite &&
      signal.quality > 0 &&
      signal.quality <= 1 &&
      !signal.id.toLowerCase().startsWith('syn-') &&
      !(signal.groupId?.toLowerCase().startsWith('syn-') ?? false) &&
      !EvidenceProvenance.signalIsDemo(signal) &&
      !signal.timestamp.isAfter(asOf) &&
      [signal.recordedAt, signal.syncedAt].whereType<DateTime>().every(
        (time) => !time.isAfter(asOf) && !time.isBefore(signal.timestamp),
      );

  static DateTime? _signalAvailability(SignalReading signal) {
    final recorded = signal.recordedAt;
    final synced = signal.syncedAt;
    if (recorded == null) return synced;
    if (synced == null) return recorded;
    return recorded.isAfter(synced) ? recorded : synced;
  }

  static bool _genuine(DailyCheckIn response) =>
      response.questionnaireVersion == CheckInMeasurement.currentVersion &&
      response.source == 'selfReport' &&
      response.id.isNotEmpty &&
      !response.id.toLowerCase().startsWith('syn-') &&
      !EvidenceProvenance.hasDemoMarker([response.id, response.note]);

  static bool _availableResponse(DailyCheckIn response, DateTime now) =>
      !response.timestamp.isAfter(now) &&
      response.recordedAt != null &&
      !response.recordedAt!.isAfter(now);

  static int _compareRevision(DailyCheckIn a, DailyCheckIn b) {
    final revision = (a.recordedAt ?? a.timestamp).compareTo(
      b.recordedAt ?? b.timestamp,
    );
    return revision != 0 ? revision : _compareSubmission(a, b);
  }

  static int _compareSubmission(DailyCheckIn a, DailyCheckIn b) {
    for (final result in [
      a.timestamp.compareTo(b.timestamp),
      (a.recordedAt ?? a.timestamp).compareTo(b.recordedAt ?? b.timestamp),
      a.id.compareTo(b.id),
      b.answeredItemCount.compareTo(a.answeredItemCount),
    ]) {
      if (result != 0) return result;
    }
    return _canonical(_reportKey(a)).compareTo(_canonical(_reportKey(b)));
  }

  static Map<String, Object?> _reportKey(DailyCheckIn response) => {
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
  };

  static int _compareSignalRevision(SignalReading a, SignalReading b) {
    final revision = (_signalAvailability(a) ?? a.timestamp).compareTo(
      _signalAvailability(b) ?? b.timestamp,
    );
    if (revision != 0) return revision;
    final instant = a.timestamp.compareTo(b.timestamp);
    return instant != 0
        ? instant
        : _canonical(a.toJson()).compareTo(_canonical(b.toJson()));
  }

  static DateTime? _date(String? value) {
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

  static bool _equal(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((key) => b.containsKey(key) && _equal(a[key], b[key]));
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_equal(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

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
    return '${value.runtimeType}:${jsonEncode(value?.toString())}';
  }
}

class SelfReportTrendsSummary {
  SelfReportTrendsSummary({
    required this.startDate,
    required this.endDate,
    required this.windowDays,
    required this.period,
    required this.questionnaireLanguage,
    required this.selectedReportCount,
    required List<SelfReportTrendDay> days,
    required Map<String, SelfReportTrendSeries> series,
  }) : days = List.unmodifiable(days),
       series = Map.unmodifiable(series);

  final String startDate;
  final String endDate;
  final int windowDays;
  final CheckInPeriod period;
  final String questionnaireLanguage;
  final int selectedReportCount;
  final List<SelfReportTrendDay> days;
  final Map<String, SelfReportTrendSeries> series;
}

class SelfReportTrendDay {
  const SelfReportTrendDay({
    required this.date,
    required this.response,
    required this.matchedSleep,
  });
  final String date;
  final DailyCheckIn? response;
  final SelfReportSleepMatch? matchedSleep;
}

class SelfReportTrendSeries {
  SelfReportTrendSeries({
    required this.itemId,
    required List<double?> values,
    required this.answeredCount,
    required this.matchedCount,
  }) : values = List.unmodifiable(values);

  final String itemId;
  final List<double?> values;
  final int answeredCount;
  final int matchedCount;
}

class SelfReportSleepMatch {
  const SelfReportSleepMatch.unavailable(this.reason)
    : reading = null,
      availableAt = null,
      availabilityKnown = false;

  const SelfReportSleepMatch.matched(
    SignalReading this.reading, {
    required this.availableAt,
    required this.availabilityKnown,
  }) : reason = null;

  final SignalReading? reading;

  /// Latest known save/import time of evidence needed to select the pair;
  /// null if any necessary availability time was not recorded.
  final DateTime? availableAt;
  final bool availabilityKnown;
  final String? reason;
  bool get isMatched => reading != null;
  double? get durationHours => reading?.value;
  DateTime? get endTime => reading?.timestamp;
  SignalSource? get source => reading?.source;
}
