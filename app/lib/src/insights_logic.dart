import 'dart:math' as math;

import 'activity_sync_logic.dart';
import 'fatigue_engine.dart';
import 'models.dart';
import 'sleep_sync_logic.dart';

enum InsightTrendMetric { energy, sleep, training, study }

enum InsightAssociationDirection { positive, negative, neutral }

class InsightDay {
  const InsightDay({
    required this.date,
    required this.sleepHours,
    required this.trainingHours,
    required this.studyHours,
    required this.estimatedEnergy,
    required this.estimatedCognitive,
    required this.recordCount,
  });

  final DateTime date;
  final double? sleepHours;
  final double? trainingHours;
  final double? studyHours;
  final int? estimatedEnergy;
  final int? estimatedCognitive;
  final int recordCount;

  bool get hasTrackedData => recordCount > 0;

  double? valueFor(InsightTrendMetric metric) => switch (metric) {
    InsightTrendMetric.energy => estimatedEnergy?.toDouble(),
    InsightTrendMetric.sleep => sleepHours,
    InsightTrendMetric.training => trainingHours,
    InsightTrendMetric.study => studyHours,
  };
}

class InsightPeriodSummary {
  const InsightPeriodSummary({
    required this.start,
    required this.end,
    required this.averageSleepHours,
    required this.trainingHours,
    required this.studyHours,
    required this.averageEstimatedEnergy,
    required this.trackedDayCount,
  });

  final DateTime start;
  final DateTime end;
  final double? averageSleepHours;
  final double? trainingHours;
  final double? studyHours;
  final double? averageEstimatedEnergy;
  final int trackedDayCount;
}

class InsightAssociation {
  const InsightAssociation({
    required this.metric,
    required this.direction,
    required this.coefficient,
    required this.sampleDays,
    required this.title,
    required this.detail,
  });

  final InsightTrendMetric metric;
  final InsightAssociationDirection direction;
  final double coefficient;
  final int sampleDays;
  final String title;
  final String detail;
}

class InsightsSnapshot {
  const InsightsSnapshot({
    required this.currentDays,
    required this.previousDays,
    required this.currentSummary,
    required this.previousSummary,
    required this.associations,
    required this.generatedAt,
    required this.sourceSignalCount,
    required this.sourceCheckInCount,
  });

  final List<InsightDay> currentDays;
  final List<InsightDay> previousDays;
  final InsightPeriodSummary currentSummary;
  final InsightPeriodSummary previousSummary;
  final List<InsightAssociation> associations;
  final DateTime generatedAt;
  final int sourceSignalCount;
  final int sourceCheckInCount;

  bool get hasCurrentData => currentSummary.trackedDayCount > 0;
}

abstract final class InsightsLogic {
  static const currentDayCount = 7;
  static const queryLookbackDays = 20;

  static const _scoreSignalTypes = {
    SignalType.sleep,
    SignalType.hydration,
    SignalType.exercise,
    SignalType.study,
    SignalType.screenTime,
    SignalType.caffeine,
    SignalType.reactionTime,
  };

  static InsightsSnapshot build({
    required DateTime now,
    required List<SignalReading> signals,
    required List<DailyCheckIn> checkIns,
  }) {
    final today = _day(now);
    final currentStart = today.subtract(
      const Duration(days: currentDayCount - 1),
    );
    final previousStart = currentStart.subtract(
      const Duration(days: currentDayCount),
    );
    final rangeEnd = today.add(const Duration(days: 1));
    final cutoff = now.isBefore(rangeEnd) ? now : rangeEnd;
    final modelStart = today.subtract(
      const Duration(days: queryLookbackDays - 1),
    );
    final scopedSignals = signals
        .where(
          (item) =>
              !item.timestamp.isBefore(modelStart) &&
              !item.timestamp.isAfter(cutoff) &&
              item.value.isFinite,
        )
        .toList(growable: false);
    final scopedCheckIns = checkIns
        .where(
          (item) =>
              !item.timestamp.isBefore(modelStart) &&
              !item.timestamp.isAfter(cutoff),
        )
        .toList(growable: false);

    final allDays = List.generate(currentDayCount * 2, (index) {
      final day = previousStart.add(Duration(days: index));
      return _buildDay(
        day: day,
        now: now,
        signals: scopedSignals,
        checkIns: scopedCheckIns,
      );
    });
    final previousDays = allDays.take(currentDayCount).toList(growable: false);
    final currentDays = allDays.skip(currentDayCount).toList(growable: false);
    final currentSummary = _summary(currentDays);
    final previousSummary = _summary(previousDays);
    final currentSignals = scopedSignals.where(
      (item) =>
          !item.timestamp.isBefore(currentStart) &&
          item.timestamp.isBefore(rangeEnd),
    );
    final currentCheckIns = scopedCheckIns.where(
      (item) =>
          !item.timestamp.isBefore(currentStart) &&
          item.timestamp.isBefore(rangeEnd),
    );

    return InsightsSnapshot(
      currentDays: List.unmodifiable(currentDays),
      previousDays: List.unmodifiable(previousDays),
      currentSummary: currentSummary,
      previousSummary: previousSummary,
      associations: List.unmodifiable(_associations(currentDays)),
      generatedAt: now,
      sourceSignalCount: currentSignals.length,
      sourceCheckInCount: currentCheckIns.length,
    );
  }

  static InsightDay _buildDay({
    required DateTime day,
    required DateTime now,
    required List<SignalReading> signals,
    required List<DailyCheckIn> checkIns,
  }) {
    final end = day.add(const Duration(days: 1));
    final cutoff = _sameDay(day, now)
        ? now
        : end.subtract(const Duration(microseconds: 1));
    final daySignals = signals
        .where(
          (item) =>
              !item.timestamp.isBefore(day) &&
              item.timestamp.isBefore(end) &&
              !item.timestamp.isAfter(cutoff),
        )
        .toList(growable: false);
    final dayCheckIns = checkIns
        .where(
          (item) =>
              !item.timestamp.isBefore(day) &&
              item.timestamp.isBefore(end) &&
              !item.timestamp.isAfter(cutoff),
        )
        .toList(growable: false);

    List<SignalReading> readings(SignalType type) =>
        daySignals.where((item) => item.type == type).toList(growable: false);

    double? total(SignalType type) {
      if (ActivitySyncLogic.supportedTypes.contains(type)) {
        return ActivitySyncLogic.aggregateForDay(
          daySignals,
          type: type,
          day: day,
        )?.total;
      }
      final values = readings(type);
      return values.isEmpty
          ? null
          : values.fold<double>(0, (sum, item) => sum + item.value);
    }

    final sleepReadings = SleepSyncLogic.preferredSleepReadings(daySignals);
    final trackedSignals = daySignals
        .where((item) => _scoreSignalTypes.contains(item.type))
        .length;
    final recordCount = trackedSignals + dayCheckIns.length;
    final score = recordCount == 0
        ? null
        : FatigueEngine.score(
            signals: signals,
            checkIns: checkIns,
            now: cutoff,
            day: day,
          );
    return InsightDay(
      date: day,
      // One sleep-duration record represents a night. Use the latest record
      // rather than summing duplicate/manual replacements into impossible sleep.
      sleepHours: sleepReadings.firstOrNull?.value,
      trainingHours: total(SignalType.exercise),
      studyHours: total(SignalType.study),
      estimatedEnergy: score?.energy,
      estimatedCognitive: score?.cognitive,
      recordCount: recordCount,
    );
  }

  static InsightPeriodSummary _summary(List<InsightDay> days) {
    final sleep = days.map((item) => item.sleepHours).nonNulls.toList();
    final training = days.map((item) => item.trainingHours).nonNulls.toList();
    final study = days.map((item) => item.studyHours).nonNulls.toList();
    final energy = days
        .map((item) => item.estimatedEnergy?.toDouble())
        .nonNulls
        .toList();
    return InsightPeriodSummary(
      start: days.first.date,
      end: days.last.date,
      averageSleepHours: _average(sleep),
      trainingHours: training.isEmpty
          ? null
          : training.fold<double>(0, (sum, value) => sum + value),
      studyHours: study.isEmpty
          ? null
          : study.fold<double>(0, (sum, value) => sum + value),
      averageEstimatedEnergy: _average(energy),
      trackedDayCount: days.where((item) => item.hasTrackedData).length,
    );
  }

  static List<InsightAssociation> _associations(List<InsightDay> days) {
    final associations = <InsightAssociation>[];
    for (final metric in const [
      InsightTrendMetric.sleep,
      InsightTrendMetric.training,
      InsightTrendMetric.study,
    ]) {
      final pairs = <(double, double)>[
        for (final day in days)
          if (day.valueFor(metric) case final value?)
            if (day.estimatedEnergy case final energy?)
              (value, energy.toDouble()),
      ];
      if (pairs.length < 3) continue;
      final coefficient = _pearson(pairs);
      if (coefficient == null) continue;
      final direction = coefficient >= .2
          ? InsightAssociationDirection.positive
          : coefficient <= -.2
          ? InsightAssociationDirection.negative
          : InsightAssociationDirection.neutral;
      final metricLabel = switch (metric) {
        InsightTrendMetric.sleep => 'sleep',
        InsightTrendMetric.training => 'training',
        InsightTrendMetric.study => 'study',
        InsightTrendMetric.energy => 'energy',
      };
      final relationship = switch (direction) {
        InsightAssociationDirection.positive =>
          'Higher logged $metricLabel aligned with higher estimated energy',
        InsightAssociationDirection.negative =>
          'Higher logged $metricLabel aligned with lower estimated energy',
        InsightAssociationDirection.neutral =>
          'Logged $metricLabel had no clear linear alignment with estimated energy',
      };
      associations.add(
        InsightAssociation(
          metric: metric,
          direction: direction,
          coefficient: coefficient,
          sampleDays: pairs.length,
          title: '${_title(metricLabel)} and estimated energy',
          detail:
              '$relationship across ${pairs.length} matched days. This is an association in Tonyo’s current wellness model, not proof of cause.',
        ),
      );
    }
    associations.sort(
      (left, right) =>
          right.coefficient.abs().compareTo(left.coefficient.abs()),
    );
    return associations;
  }

  static double? _pearson(List<(double, double)> pairs) {
    final meanX = _average(pairs.map((item) => item.$1).toList())!;
    final meanY = _average(pairs.map((item) => item.$2).toList())!;
    var covariance = 0.0;
    var varianceX = 0.0;
    var varianceY = 0.0;
    for (final pair in pairs) {
      final x = pair.$1 - meanX;
      final y = pair.$2 - meanY;
      covariance += x * y;
      varianceX += x * x;
      varianceY += y * y;
    }
    final denominator = math.sqrt(varianceX * varianceY);
    if (denominator <= 1e-9) return null;
    return (covariance / denominator).clamp(-1.0, 1.0);
  }

  static double? _average(List<double> values) => values.isEmpty
      ? null
      : values.fold<double>(0, (sum, value) => sum + value) / values.length;

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  static String _title(String value) =>
      '${value[0].toUpperCase()}${value.substring(1)}';
}
