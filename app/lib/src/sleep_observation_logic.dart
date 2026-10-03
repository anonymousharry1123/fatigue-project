import 'dart:math' as math;

import 'local_day.dart';
import 'models.dart';
import 'privacy_consent.dart';
import 'sleep_sync_logic.dart';

/// Guideline interpretation is deliberately independent of score weights.
/// AASM teen advisory, cited as S1 in TONYO_BIOLOGY_UPGRADE_PLAN.md:
/// https://aasm.org/advocacy/position-statements/teen-sleep-duration-health-advisory/
enum SleepRangeComparison { unavailable, below, within, above }

class SleepDayObservation {
  const SleepDayObservation(this.day, this.mainHours, this.napHours, this.naps);
  final DateTime day;
  final double? mainHours;
  final double? napHours;
  final int naps;
}

class SleepObservations {
  SleepObservations._({
    required this.windowStart,
    required this.windowEnd,
    required this.latestMain,
    required this.totalHours,
    required this.napHours,
    required this.napCount,
    required this.days,
    required this.supportsTeenGuidance,
    required this.boundaryUncertain,
    required this.evidenceKey,
    required this.bedtimeVariationMinutes,
    required this.wakeVariationMinutes,
    required this.bedtimeObservationCount,
  });

  /// Twenty-four elapsed hours, not a calendar date (which may be 23/25 hours).
  final DateTime windowStart;
  final DateTime windowEnd;
  final SignalReading? latestMain;
  final double totalHours;
  final double napHours;
  final int napCount;
  final List<SleepDayObservation> days;
  final bool supportsTeenGuidance;
  final bool boundaryUncertain;
  final String evidenceKey;
  final double? bedtimeVariationMinutes;
  final double? wakeVariationMinutes;
  final int bedtimeObservationCount;

  int get mainObservationCount =>
      days.where((day) => day.mainHours != null).length;
  double? get usualMainHours => mainObservationCount == 0
      ? null
      : days.fold<double>(0, (sum, day) => sum + (day.mainHours ?? 0)) /
            mainObservationCount;

  /// Existing imports do not record continuous sleep-observation coverage.
  /// A record alone never proves completeness. Confirmation is for this exact
  /// window and evidence set only; it is not sensor validation or recovery.
  SleepRangeComparison compare({required bool allSleepConfirmed}) {
    if (!supportsTeenGuidance || !allSleepConfirmed || boundaryUncertain) {
      return SleepRangeComparison.unavailable;
    }
    if (totalHours < 8) return SleepRangeComparison.below;
    if (totalHours > 10) return SleepRangeComparison.above;
    return SleepRangeComparison.within;
  }

  factory SleepObservations.build({
    required Iterable<SignalReading> signals,
    required DateTime now,
    required PrivacyAgeBand? ageBand,
  }) {
    // Minute precision keeps a user confirmation stable during a rebuild,
    // while expiring it when the window moves or any relevant record changes.
    final end = DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch ~/
          Duration.millisecondsPerMinute *
          Duration.millisecondsPerMinute,
      isUtc: true,
    );
    final start = end.subtract(const Duration(hours: 24));
    final rows = signals
        .where(
          (row) =>
              row.source != SignalSource.model &&
              row.quality.isFinite &&
              row.quality > 0 &&
              !row.timestamp.isAfter(now),
        )
        .toList();
    final mains = SleepSyncLogic.preferredSleepReadings(rows);
    final naps = SleepSyncLogic.preferredNapReadings(rows);
    final intervals = <(int, int)>[];
    final napIntervals = <(int, int)>[];
    var uncertain = false;
    var napCount = 0;
    for (final row in [...mains, ...naps]) {
      final finish = row.timestamp.toUtc();
      final duration = Duration(
        microseconds: (row.value * Duration.microsecondsPerHour).round(),
      );
      final begin = finish.subtract(duration);
      final bed = rows
          .where(
            (candidate) =>
                row.groupId != null &&
                candidate.groupId == row.groupId &&
                candidate.type == SignalType.bedtime &&
                candidate.timestamp.isBefore(finish),
          )
          .firstOrNull
          ?.timestamp
          .toUtc();
      // Health summaries retain stage totals, not each stage's interval. At a
      // clipped boundary their precise allocation is unknown: show an estimate
      // but suppress the recommendation comparison, even after confirmation.
      if (bed != null &&
          bed.isBefore(start) &&
          finish.isAfter(start) &&
          finish.difference(bed) != duration) {
        uncertain = true;
      }
      if (row.source == SignalSource.healthKit &&
          (begin.isBefore(start) && finish.isAfter(start) ||
              finish.isAfter(end)) &&
          (bed == null || finish.difference(bed) != duration)) {
        uncertain = true;
      }
      final lo = math.max(
        begin.microsecondsSinceEpoch,
        start.microsecondsSinceEpoch,
      );
      final hi = math.min(
        finish.microsecondsSinceEpoch,
        end.microsecondsSinceEpoch,
      );
      if (hi <= lo) continue;
      intervals.add((lo, hi));
      if (row.type == SignalType.nap) {
        napIntervals.add((lo, hi));
        napCount++;
      }
    }
    final today = localDay(now);
    final recentMains = mains
        .where((row) => !row.timestamp.isBefore(localDay(today, -6)))
        .toList();
    final bedtimeClocks = <DateTime>[];
    for (final main in recentMains) {
      final bed = rows
          .where(
            (row) =>
                main.groupId != null &&
                row.groupId == main.groupId &&
                row.type == SignalType.bedtime &&
                row.timestamp.isBefore(main.timestamp) &&
                main.timestamp.difference(row.timestamp) <=
                    const Duration(hours: 18),
          )
          .firstOrNull;
      // An aggregated sleep total cannot reconstruct bedtime when awake gaps
      // or the original interval are unknown. Only paired timing is observed.
      if (bed != null) bedtimeClocks.add(bed.timestamp);
    }
    final days = List.generate(7, (index) {
      final day = localDay(today, index - 6);
      final main = mains
          .where((row) => sameLocalDay(row.timestamp, day))
          .firstOrNull;
      final dailyNaps = naps
          .where((row) => sameLocalDay(row.timestamp, day))
          .toList();
      return SleepDayObservation(
        day,
        main?.value,
        dailyNaps.isEmpty
            ? null
            : dailyNaps.fold<double>(0, (sum, row) => sum + row.value),
        dailyNaps.length,
      );
    });
    final relevant =
        rows
            .where(
              (row) =>
                  row.type == SignalType.sleep ||
                  row.type == SignalType.nap ||
                  row.type == SignalType.bedtime ||
                  SleepSyncLogic.stageTypes.contains(row.type),
            )
            .map(
              (row) =>
                  '${row.id}:${row.value}:${row.timestamp.toUtc()}:${row.source.name}:${row.groupId}',
            )
            .toList()
          ..sort();
    return SleepObservations._(
      windowStart: start,
      windowEnd: end,
      latestMain: mains.firstOrNull,
      totalHours: _unionMicros(intervals) / Duration.microsecondsPerHour,
      napHours: _unionMicros(napIntervals) / Duration.microsecondsPerHour,
      napCount: napCount,
      days: List.unmodifiable(days),
      supportsTeenGuidance:
          ageBand == PrivacyAgeBand.age13to15 ||
          ageBand == PrivacyAgeBand.age16to17,
      boundaryUncertain: uncertain,
      evidenceKey:
          '${end.microsecondsSinceEpoch}:$ageBand:${relevant.join('|')}',
      bedtimeVariationMinutes: circularVariationMinutes(bedtimeClocks),
      wakeVariationMinutes: circularVariationMinutes(
        recentMains.map((row) => row.timestamp),
      ),
      bedtimeObservationCount: bedtimeClocks.length,
    );
  }

  /// Mean absolute shortest-clock distance from the circular mean, in minutes.
  /// This describes recorded timing, not a clinical regularity cutoff. Across
  /// DST, these clock patterns intentionally use local wall time; duration
  /// totals above use elapsed instants. A flat/ambiguous circle has no mean.
  static double? circularVariationMinutes(Iterable<DateTime> values) {
    final minutes = values.map((value) {
      final local = value.toLocal();
      return local.hour * 60.0 + local.minute + local.second / 60;
    }).toList();
    if (minutes.length < 2) return null;
    final x = minutes.fold<double>(
      0,
      (sum, value) => sum + math.cos(value * 2 * math.pi / 1440),
    );
    final y = minutes.fold<double>(
      0,
      (sum, value) => sum + math.sin(value * 2 * math.pi / 1440),
    );
    if (math.sqrt(x * x + y * y) < 1e-8) return null;
    final center = (math.atan2(y, x) * 1440 / (2 * math.pi) + 1440) % 1440;
    return minutes.fold<double>(
          0,
          (sum, value) => sum + ((value - center + 2160) % 1440 - 720).abs(),
        ) /
        minutes.length;
  }

  static int _unionMicros(List<(int, int)> intervals) {
    intervals.sort((a, b) => a.$1.compareTo(b.$1));
    var total = 0;
    int? from;
    var to = 0;
    for (final interval in intervals) {
      if (from == null) {
        from = interval.$1;
        to = interval.$2;
      } else if (interval.$1 > to) {
        total += to - from;
        from = interval.$1;
        to = interval.$2;
      } else {
        to = math.max(to, interval.$2);
      }
    }
    return total + (from == null ? 0 : to - from);
  }
}
