import 'models.dart';

class ActivitySyncMergeResult {
  const ActivitySyncMergeResult({
    required this.readings,
    required this.importedCount,
    required this.duplicateCount,
    required this.rejectedCount,
  });

  final List<SignalReading> readings;
  final int importedCount;
  final int duplicateCount;
  final int rejectedCount;
}

class ActivityDailyAggregate {
  const ActivityDailyAggregate({
    required this.type,
    required this.day,
    required this.total,
    required this.evidence,
    required this.usesManualCorrection,
  });

  final SignalType type;
  final DateTime day;
  final double total;
  final List<SignalReading> evidence;
  final bool usesManualCorrection;
}

/// Normalizes Apple Health workout, step, and hydration imports and derives the
/// manual-safe daily values used by scores, forecasts, and summaries.
abstract final class ActivitySyncLogic {
  static const manualCorrectionNote = 'Manual daily correction';
  static const blankManualValueNote = 'Blank field · imported fallback allowed';

  static const supportedTypes = {
    SignalType.exercise,
    SignalType.hydration,
    SignalType.steps,
  };

  static const duplicateWindow = Duration(minutes: 5);
  static const exerciseValueTolerance = .1;
  static const hydrationValueTolerance = .02;

  static ActivitySyncMergeResult merge({
    required Iterable<SignalReading> existing,
    required Iterable<SignalReading> imported,
  }) {
    final readings = existing.toList();
    var importedCount = 0;
    var duplicateCount = 0;
    var rejectedCount = 0;

    for (final raw in imported) {
      final candidate = _normalize(raw);
      if (candidate == null) {
        rejectedCount += 1;
        continue;
      }
      final sameIdIndex = readings.indexWhere(
        (item) => item.id == candidate.id,
      );
      if (sameIdIndex >= 0) {
        final saved = readings[sameIdIndex];
        // Daily step totals grow during the day. HealthKit gives them a stable
        // per-day ID so a refresh replaces the partial total instead of
        // double-counting it.
        if (candidate.type == SignalType.steps &&
            (saved.value - candidate.value).abs() > 1) {
          readings[sameIdIndex] = candidate;
          importedCount += 1;
        } else {
          duplicateCount += 1;
        }
        continue;
      }
      final tolerance = switch (candidate.type) {
        SignalType.exercise => exerciseValueTolerance,
        SignalType.hydration => hydrationValueTolerance,
        SignalType.steps => 1.0,
        _ => 0.0,
      };
      final duplicate = readings.any(
        (item) =>
            item.source == SignalSource.healthKit &&
            item.type == candidate.type &&
            item.timestamp
                    .difference(candidate.timestamp)
                    .inMilliseconds
                    .abs() <=
                duplicateWindow.inMilliseconds &&
            (item.value - candidate.value).abs() <= tolerance,
      );
      if (duplicate) {
        duplicateCount += 1;
        continue;
      }
      readings.add(candidate);
      importedCount += 1;
    }

    readings.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return ActivitySyncMergeResult(
      readings: readings,
      importedCount: importedCount,
      duplicateCount: duplicateCount,
      rejectedCount: rejectedCount,
    );
  }

  static ActivityDailyAggregate? aggregateForDay(
    Iterable<SignalReading> readings, {
    required SignalType type,
    required DateTime day,
  }) {
    if (!supportedTypes.contains(type)) return null;
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final all = readings.where((item) => item.type == type).toList();
    final manual = all
        .where(
          (item) =>
              item.source == SignalSource.manual &&
              !item.timestamp.isBefore(start) &&
              item.timestamp.isBefore(end),
        )
        .toList();
    final manualCorrections = manual
        .where((item) => item.note != blankManualValueNote)
        .toList();
    if (manualCorrections.isNotEmpty) {
      manualCorrections.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return ActivityDailyAggregate(
        type: type,
        day: start,
        total: manualCorrections.fold<double>(
          0,
          (sum, item) => sum + item.value,
        ),
        evidence: List.unmodifiable(manualCorrections),
        usesManualCorrection: true,
      );
    }

    if (type == SignalType.hydration || type == SignalType.steps) {
      final selected =
          all
              .where(
                (item) =>
                    item.source != SignalSource.manual &&
                    !item.timestamp.isBefore(start) &&
                    item.timestamp.isBefore(end),
              )
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (selected.isEmpty) return _blankManualFallback(type, start, manual);
      return ActivityDailyAggregate(
        type: type,
        day: start,
        total: selected.fold<double>(0, (sum, item) => sum + item.value),
        evidence: List.unmodifiable(selected),
        usesManualCorrection: false,
      );
    }

    final healthKit = all
        .where((item) => item.source == SignalSource.healthKit)
        .where((item) => _workoutOverlapsDay(item, start, end))
        .toList();
    final other = all
        .where(
          (item) =>
              item.source != SignalSource.manual &&
              item.source != SignalSource.healthKit &&
              !item.timestamp.isBefore(start) &&
              item.timestamp.isBefore(end),
        )
        .toList();
    if (healthKit.isEmpty && other.isEmpty) {
      return _blankManualFallback(type, start, manual);
    }
    final evidence = [...healthKit, ...other]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return ActivityDailyAggregate(
      type: type,
      day: start,
      total:
          _unionWorkoutHours(healthKit, start, end) +
          other.fold<double>(0, (sum, item) => sum + item.value),
      evidence: List.unmodifiable(evidence),
      usesManualCorrection: false,
    );
  }

  static ActivityDailyAggregate? trainingLoadForDay(
    Iterable<SignalReading> readings, {
    required DateTime day,
  }) => aggregateForDay(readings, type: SignalType.exercise, day: day);

  static List<ActivityDailyAggregate> aggregatesByDay(
    Iterable<SignalReading> readings, {
    required SignalType type,
    required DateTime start,
    required DateTime end,
  }) {
    final firstDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final output = <ActivityDailyAggregate>[];
    for (
      var day = firstDay;
      day.isBefore(endDay);
      day = day.add(const Duration(days: 1))
    ) {
      final aggregate = aggregateForDay(readings, type: type, day: day);
      if (aggregate != null) output.add(aggregate);
    }
    output.sort((a, b) => b.day.compareTo(a.day));
    return output;
  }

  static SignalReading? _normalize(SignalReading reading) {
    if (!supportedTypes.contains(reading.type) ||
        reading.id.trim().isEmpty ||
        !reading.value.isFinite ||
        !_validRange(reading.type, reading.value)) {
      return null;
    }
    return SignalReading(
      id: reading.id.trim(),
      type: reading.type,
      value: reading.value,
      timestamp: reading.timestamp.toLocal(),
      source: SignalSource.healthKit,
      quality: reading.quality.isFinite
          ? reading.quality.clamp(0, 1).toDouble()
          : 1,
      note: reading.note,
    );
  }

  static ActivityDailyAggregate? _blankManualFallback(
    SignalType type,
    DateTime day,
    List<SignalReading> manual,
  ) {
    if (manual.isEmpty) return null;
    manual.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return ActivityDailyAggregate(
      type: type,
      day: day,
      total: manual.fold<double>(0, (sum, item) => sum + item.value),
      evidence: List.unmodifiable(manual),
      usesManualCorrection: false,
    );
  }

  static bool _validRange(SignalType type, double value) => switch (type) {
    SignalType.exercise => value > 0 && value <= 24,
    SignalType.hydration => value > 0 && value <= 10,
    SignalType.steps => value > 0 && value <= 200000,
    _ => false,
  };

  static bool _workoutOverlapsDay(
    SignalReading reading,
    DateTime dayStart,
    DateTime dayEnd,
  ) {
    final workoutEnd = reading.timestamp;
    final workoutStart = workoutEnd.subtract(
      Duration(
        microseconds: (reading.value * Duration.microsecondsPerHour).round(),
      ),
    );
    return workoutStart.isBefore(dayEnd) && workoutEnd.isAfter(dayStart);
  }

  static double _unionWorkoutHours(
    List<SignalReading> readings,
    DateTime dayStart,
    DateTime dayEnd,
  ) {
    final intervals =
        readings
            .map((item) {
              final end = item.timestamp.isAfter(dayEnd)
                  ? dayEnd
                  : item.timestamp;
              final rawStart = item.timestamp.subtract(
                Duration(
                  microseconds: (item.value * Duration.microsecondsPerHour)
                      .round(),
                ),
              );
              final start = rawStart.isBefore(dayStart) ? dayStart : rawStart;
              return (start: start, end: end);
            })
            .where((item) => item.end.isAfter(item.start))
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    if (intervals.isEmpty) return 0;

    var total = Duration.zero;
    var currentStart = intervals.first.start;
    var currentEnd = intervals.first.end;
    for (final interval in intervals.skip(1)) {
      if (interval.start.isAfter(currentEnd)) {
        total += currentEnd.difference(currentStart);
        currentStart = interval.start;
        currentEnd = interval.end;
      } else if (interval.end.isAfter(currentEnd)) {
        currentEnd = interval.end;
      }
    }
    total += currentEnd.difference(currentStart);
    return total.inMicroseconds / Duration.microsecondsPerHour;
  }
}
