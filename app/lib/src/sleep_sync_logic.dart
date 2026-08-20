import 'models.dart';

class SleepSyncMergeResult {
  const SleepSyncMergeResult({
    required this.readings,
    required this.importedNightCount,
    required this.importedSignalCount,
    required this.duplicateCount,
    required this.skippedManualNightCount,
    required this.rejectedSampleCount,
  });

  final List<SignalReading> readings;
  final int importedNightCount;
  final int importedSignalCount;
  final int duplicateCount;
  final int skippedManualNightCount;
  final int rejectedSampleCount;
}

class SleepSyncLogic {
  static const importedGroupPrefix = 'healthkit-sleep-';
  static const _maximumSessionGap = Duration(hours: 2);
  static const _minimumSleep = Duration(minutes: 30);
  static const _maximumSample = Duration(hours: 24);
  static const _maximumSessionSpan = Duration(hours: 18);

  static const stageTypes = <SignalType>{
    SignalType.sleepAwake,
    SignalType.sleepCore,
    SignalType.sleepDeep,
    SignalType.sleepRem,
    SignalType.sleepUnspecified,
  };

  static const detailedStageTypes = <SignalType>{
    SignalType.sleepCore,
    SignalType.sleepDeep,
    SignalType.sleepRem,
  };

  static SleepSyncMergeResult merge({
    required Iterable<SignalReading> existing,
    required Iterable<SignalReading> imported,
    DateTime? syncedAt,
  }) {
    final existingReadings = existing.toList();
    final intervals = <_SleepInterval>[];
    var rejectedSampleCount = 0;

    for (final reading in imported) {
      final interval = _SleepInterval.tryParse(reading);
      if (interval == null) {
        rejectedSampleCount += 1;
      } else {
        intervals.add(interval);
      }
    }

    if (intervals.isEmpty) {
      return SleepSyncMergeResult(
        readings: existingReadings,
        importedNightCount: 0,
        importedSignalCount: 0,
        duplicateCount: 0,
        skippedManualNightCount: 0,
        rejectedSampleCount: rejectedSampleCount,
      );
    }

    final candidatesByDay = <String, _ReconciledNight>{};
    for (final cluster in _cluster(intervals)) {
      final night = _reconcile(cluster);
      if (night == null ||
          night.totalSleep < _minimumSleep ||
          night.end.difference(night.bedtime) > _maximumSessionSpan) {
        rejectedSampleCount += cluster.length;
        continue;
      }
      final key = _dateKey(night.end);
      final current = candidatesByDay[key];
      if (current == null || night.totalSleep > current.totalSleep) {
        candidatesByDay[key] = night;
      }
    }

    final output = existingReadings.toList();
    var importedSignalCount = 0;
    var duplicateCount = 0;
    var skippedManualNightCount = 0;

    for (final entry in candidatesByDay.entries) {
      final groupId = '$importedGroupPrefix${entry.key}';
      final night = entry.value;
      final manual = _manualSleepForDay(existingReadings, night.end);
      final preferImported =
          manual == null ||
          _isImportedMoreComplete(
            importedHours: _hours(night.totalSleep),
            detailedRatio: night.detailedRatio,
            manualHours: manual.value,
          );
      if (!preferImported) skippedManualNightCount += 1;

      final generated = _signalsForNight(
        night,
        groupId: groupId,
        includeSummary: preferImported,
        syncedAt: syncedAt,
      );
      final previous = {
        for (final reading in output.where((item) => item.groupId == groupId))
          reading.id: reading,
      };
      output.removeWhere((item) => item.groupId == groupId);
      for (final reading in generated) {
        final old = previous[reading.id];
        if (old != null && _equivalent(old, reading)) {
          duplicateCount += 1;
        } else {
          importedSignalCount += 1;
        }
        output.add(reading);
      }
    }

    output.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return SleepSyncMergeResult(
      readings: output,
      importedNightCount: candidatesByDay.length,
      importedSignalCount: importedSignalCount,
      duplicateCount: duplicateCount,
      skippedManualNightCount: skippedManualNightCount,
      rejectedSampleCount: rejectedSampleCount,
    );
  }

  /// Returns at most one total-sleep reading for each local wake date.
  ///
  /// A manual reading remains preferred until an imported night includes a
  /// substantial detailed-stage breakdown and covers roughly the same duration.
  static List<SignalReading> preferredSleepReadings(
    Iterable<SignalReading> readings,
  ) {
    final all = readings.toList();
    final totalsByDay = <String, List<SignalReading>>{};
    for (final reading in all.where((item) => item.type == SignalType.sleep)) {
      totalsByDay
          .putIfAbsent(_dateKey(reading.timestamp), () => [])
          .add(reading);
    }

    final preferred = <SignalReading>[];
    for (final totals in totalsByDay.values) {
      final imported =
          totals
              .where(
                (item) =>
                    item.groupId?.startsWith(importedGroupPrefix) ?? false,
              )
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final manual =
          totals
              .where(
                (item) =>
                    !(item.groupId?.startsWith(importedGroupPrefix) ?? false),
              )
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (imported.isEmpty) {
        if (manual.isNotEmpty) preferred.add(manual.first);
        continue;
      }
      if (manual.isEmpty) {
        preferred.add(imported.first);
        continue;
      }

      final importedReading = imported.first;
      final detailedHours = all
          .where(
            (item) =>
                item.groupId == importedReading.groupId &&
                detailedStageTypes.contains(item.type),
          )
          .fold<double>(0, (sum, item) => sum + item.value);
      final detailedRatio = importedReading.value <= 0
          ? 0.0
          : (detailedHours / importedReading.value).clamp(0.0, 1.0);
      preferred.add(
        _isImportedMoreComplete(
              importedHours: importedReading.value,
              detailedRatio: detailedRatio,
              manualHours: manual.first.value,
            )
            ? importedReading
            : manual.first,
      );
    }

    preferred.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return preferred;
  }

  static List<SignalReading> preferredBedtimeReadings(
    Iterable<SignalReading> readings,
  ) {
    final all = readings.toList();
    final selectedSleep = preferredSleepReadings(all);
    final bedtimes = all
        .where((item) => item.type == SignalType.bedtime)
        .toList();
    final preferred = <SignalReading>[];
    for (final sleep in selectedSleep) {
      final grouped = sleep.groupId == null
          ? const <SignalReading>[]
          : bedtimes.where((item) => item.groupId == sleep.groupId).toList();
      if (grouped.isNotEmpty) {
        preferred.add(grouped.first);
        continue;
      }
      final sameDay =
          bedtimes
              .where(
                (item) => _dateKey(item.timestamp) == _dateKey(sleep.timestamp),
              )
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (sameDay.isNotEmpty) preferred.add(sameDay.first);
    }
    preferred.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return preferred;
  }

  static bool _isImportedMoreComplete({
    required double importedHours,
    required double detailedRatio,
    required double manualHours,
  }) {
    if (!importedHours.isFinite || importedHours <= 0) return false;
    if (!manualHours.isFinite || manualHours <= 0) return true;
    return detailedRatio >= 0.5 && importedHours >= manualHours * 0.8;
  }

  static List<List<_SleepInterval>> _cluster(List<_SleepInterval> intervals) {
    final sorted = intervals.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final clusters = <List<_SleepInterval>>[];
    var current = <_SleepInterval>[];
    DateTime? currentEnd;
    for (final interval in sorted) {
      if (currentEnd == null ||
          interval.start.isAfter(currentEnd.add(_maximumSessionGap))) {
        if (current.isNotEmpty) clusters.add(current);
        current = <_SleepInterval>[interval];
        currentEnd = interval.end;
      } else {
        current.add(interval);
        if (interval.end.isAfter(currentEnd)) currentEnd = interval.end;
      }
    }
    if (current.isNotEmpty) clusters.add(current);
    return clusters;
  }

  static _ReconciledNight? _reconcile(List<_SleepInterval> intervals) {
    final boundaries = <int>{};
    for (final interval in intervals) {
      boundaries
        ..add(interval.start.microsecondsSinceEpoch)
        ..add(interval.end.microsecondsSinceEpoch);
    }
    final sortedBoundaries = boundaries.toList()..sort();
    if (sortedBoundaries.length < 2) return null;

    final sourceScores = <String, _SourceScore>{};
    for (final sourceKey in intervals.map((item) => item.sourceKey).toSet()) {
      sourceScores[sourceKey] = _coverageScore(
        intervals.where((item) => item.sourceKey == sourceKey).toList(),
      );
    }

    final totals = <SignalType, int>{};
    DateTime? bedtime;
    DateTime? end;
    for (var index = 0; index < sortedBoundaries.length - 1; index += 1) {
      final segmentStart = DateTime.fromMicrosecondsSinceEpoch(
        sortedBoundaries[index],
      );
      final segmentEnd = DateTime.fromMicrosecondsSinceEpoch(
        sortedBoundaries[index + 1],
      );
      if (!segmentEnd.isAfter(segmentStart)) continue;
      final active = intervals
          .where(
            (item) =>
                item.start.isBefore(segmentEnd) &&
                item.end.isAfter(segmentStart),
          )
          .toList();
      if (active.isEmpty) continue;
      active.sort((a, b) {
        final sourceComparison = sourceScores[b.sourceKey]!.compareTo(
          sourceScores[a.sourceKey]!,
        );
        if (sourceComparison != 0) return sourceComparison;
        final stageComparison = _stagePriority(
          b.type,
        ).compareTo(_stagePriority(a.type));
        if (stageComparison != 0) return stageComparison;
        return a.id.compareTo(b.id);
      });
      final winner = active.first;
      final micros = segmentEnd.difference(segmentStart).inMicroseconds;
      totals[winner.type] = (totals[winner.type] ?? 0) + micros;
      if (winner.type != SignalType.sleepAwake) {
        if (bedtime == null || segmentStart.isBefore(bedtime)) {
          bedtime = segmentStart;
        }
      }
      if (end == null || segmentEnd.isAfter(end)) end = segmentEnd;
    }

    if (bedtime == null || end == null) return null;
    final sleepMicros = totals.entries
        .where((entry) => entry.key != SignalType.sleepAwake)
        .fold<int>(0, (sum, entry) => sum + entry.value);
    final detailedMicros = totals.entries
        .where((entry) => detailedStageTypes.contains(entry.key))
        .fold<int>(0, (sum, entry) => sum + entry.value);
    if (sleepMicros <= 0) return null;
    return _ReconciledNight(
      bedtime: bedtime,
      end: end,
      stageMicroseconds: totals,
      totalSleep: Duration(microseconds: sleepMicros),
      detailedRatio: (detailedMicros / sleepMicros).clamp(0.0, 1.0),
      sourceCount: intervals.map((item) => item.sourceKey).toSet().length,
    );
  }

  static List<SignalReading> _signalsForNight(
    _ReconciledNight night, {
    required String groupId,
    required bool includeSummary,
    DateTime? syncedAt,
  }) {
    final note =
        'Reconciled ${night.sourceCount} Apple Health '
        '${night.sourceCount == 1 ? 'source' : 'sources'} · '
        '${(night.detailedRatio * 100).round()}% staged';
    final quality = (0.65 + night.detailedRatio * 0.35).clamp(0.0, 1.0);
    final output = <SignalReading>[];
    if (includeSummary) {
      output.addAll([
        SignalReading(
          id: '$groupId-duration',
          type: SignalType.sleep,
          value: _hours(night.totalSleep),
          timestamp: night.end,
          source: SignalSource.healthKit,
          quality: quality,
          note: note,
          groupId: groupId,
          syncedAt: syncedAt ?? DateTime.now().toUtc(),
        ),
        SignalReading(
          id: '$groupId-bedtime',
          type: SignalType.bedtime,
          value: night.bedtime.hour + night.bedtime.minute / 60,
          timestamp: night.bedtime,
          source: SignalSource.healthKit,
          quality: quality,
          note: note,
          groupId: groupId,
          syncedAt: syncedAt ?? DateTime.now().toUtc(),
        ),
      ]);
    }

    for (final type in stageTypes) {
      final microseconds = night.stageMicroseconds[type] ?? 0;
      if (microseconds <= 0) continue;
      output.add(
        SignalReading(
          id: '$groupId-${type.name}',
          type: type,
          value: microseconds / Duration.microsecondsPerHour,
          timestamp: night.end,
          source: SignalSource.healthKit,
          quality: quality,
          note: note,
          groupId: groupId,
          syncedAt: syncedAt ?? DateTime.now().toUtc(),
        ),
      );
    }
    return output;
  }

  static SignalReading? _manualSleepForDay(
    List<SignalReading> readings,
    DateTime day,
  ) {
    final key = _dateKey(day);
    final matches =
        readings
            .where(
              (item) =>
                  item.type == SignalType.sleep &&
                  !(item.groupId?.startsWith(importedGroupPrefix) ?? false) &&
                  _dateKey(item.timestamp) == key,
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return matches.isEmpty ? null : matches.first;
  }

  static bool _equivalent(SignalReading a, SignalReading b) {
    return a.type == b.type &&
        (a.value - b.value).abs() < 0.001 &&
        a.timestamp == b.timestamp &&
        a.source == b.source &&
        (a.quality - b.quality).abs() < 0.001 &&
        a.note == b.note &&
        a.groupId == b.groupId;
  }

  static int _stagePriority(SignalType type) => switch (type) {
    SignalType.sleepCore || SignalType.sleepDeep || SignalType.sleepRem => 3,
    SignalType.sleepAwake => 2,
    SignalType.sleepUnspecified => 1,
    _ => 0,
  };

  static _SourceScore _coverageScore(List<_SleepInterval> intervals) {
    final boundaries =
        intervals
            .expand(
              (item) => [
                item.start.microsecondsSinceEpoch,
                item.end.microsecondsSinceEpoch,
              ],
            )
            .toSet()
            .toList()
          ..sort();
    final score = _SourceScore();
    for (var index = 0; index < boundaries.length - 1; index += 1) {
      final start = DateTime.fromMicrosecondsSinceEpoch(boundaries[index]);
      final end = DateTime.fromMicrosecondsSinceEpoch(boundaries[index + 1]);
      final active = intervals.where(
        (item) => item.start.isBefore(end) && item.end.isAfter(start),
      );
      if (active.isEmpty) continue;
      final microseconds = end.difference(start).inMicroseconds;
      score.total += microseconds;
      if (active.any((item) => detailedStageTypes.contains(item.type))) {
        score.detailed += microseconds;
      }
    }
    return score;
  }

  static double _hours(Duration duration) =>
      duration.inMicroseconds / Duration.microsecondsPerHour;

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class _SleepInterval {
  const _SleepInterval({
    required this.id,
    required this.type,
    required this.start,
    required this.end,
    required this.sourceKey,
  });

  static _SleepInterval? tryParse(SignalReading reading) {
    if (!SleepSyncLogic.stageTypes.contains(reading.type) ||
        !reading.value.isFinite ||
        reading.value <= 0) {
      return null;
    }
    final microseconds = (reading.value * Duration.microsecondsPerHour).round();
    final duration = Duration(microseconds: microseconds);
    if (duration <= Duration.zero || duration > SleepSyncLogic._maximumSample) {
      return null;
    }
    final end = reading.timestamp.toLocal();
    final start = end.subtract(duration);
    return _SleepInterval(
      id: reading.id,
      type: reading.type,
      start: start,
      end: end,
      sourceKey: reading.groupId ?? reading.note ?? reading.id,
    );
  }

  final String id;
  final SignalType type;
  final DateTime start;
  final DateTime end;
  final String sourceKey;

  Duration get duration => end.difference(start);
}

class _SourceScore implements Comparable<_SourceScore> {
  int detailed = 0;
  int total = 0;

  @override
  int compareTo(_SourceScore other) {
    final detailedComparison = detailed.compareTo(other.detailed);
    if (detailedComparison != 0) return detailedComparison;
    return total.compareTo(other.total);
  }
}

class _ReconciledNight {
  const _ReconciledNight({
    required this.bedtime,
    required this.end,
    required this.stageMicroseconds,
    required this.totalSleep,
    required this.detailedRatio,
    required this.sourceCount,
  });

  final DateTime bedtime;
  final DateTime end;
  final Map<SignalType, int> stageMicroseconds;
  final Duration totalSleep;
  final double detailedRatio;
  final int sourceCount;
}
