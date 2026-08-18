import 'activity_sync_logic.dart';
import 'models.dart';
import 'sleep_sync_logic.dart';

enum TodayFatigueStatus { fresh, moderate, fatigued }

extension TodayFatigueStatusInfo on TodayFatigueStatus {
  String get label => switch (this) {
    TodayFatigueStatus.fresh => 'Fresh',
    TodayFatigueStatus.moderate => 'Moderate',
    TodayFatigueStatus.fatigued => 'Fatigued',
  };

  String get detail => switch (this) {
    TodayFatigueStatus.fresh =>
      'Your recovery signals support a higher-capacity day.',
    TodayFatigueStatus.moderate =>
      'Plan deliberately and leave room for a recovery break.',
    TodayFatigueStatus.fatigued =>
      'Keep the load lighter and prioritize recovery today.',
  };
}

class TodaySignalSummary {
  const TodaySignalSummary({
    required this.type,
    required this.displayValue,
    required this.recordedAt,
    required this.readingCount,
  });

  final SignalType type;
  final String displayValue;
  final DateTime? recordedAt;
  final int readingCount;

  bool get isAvailable => recordedAt != null;
}

abstract final class TodayDashboardLogic {
  static const summaryTypes = [
    SignalType.sleep,
    SignalType.hydration,
    SignalType.exercise,
    SignalType.steps,
    SignalType.study,
    SignalType.screenTime,
    SignalType.reactionTime,
  ];

  static TodayFatigueStatus statusFor(int energy) => switch (energy) {
    >= 72 => TodayFatigueStatus.fresh,
    >= 52 => TodayFatigueStatus.moderate,
    _ => TodayFatigueStatus.fatigued,
  };

  static List<TodaySignalSummary> summariesForDay(
    Iterable<SignalReading> signals, {
    required DateTime day,
    DateTime? now,
  }) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final clock = now ?? DateTime.now();
    final cutoff = !clock.isBefore(start) && clock.isBefore(end) ? clock : end;
    final readings = signals
        .where(
          (item) =>
              !item.timestamp.isBefore(start) &&
              item.timestamp.isBefore(end) &&
              !item.timestamp.isAfter(cutoff),
        )
        .toList();

    return summaryTypes
        .map((type) {
          if (ActivitySyncLogic.supportedTypes.contains(type)) {
            final aggregate = ActivitySyncLogic.aggregateForDay(
              readings,
              type: type,
              day: start,
            );
            if (aggregate == null) {
              return TodaySignalSummary(
                type: type,
                displayValue: '—',
                recordedAt: null,
                readingCount: 0,
              );
            }
            return TodaySignalSummary(
              type: type,
              displayValue: _displayValue(type, aggregate.total),
              recordedAt: aggregate.evidence.first.timestamp,
              readingCount: aggregate.evidence.length,
            );
          }
          final matches = type == SignalType.sleep
              ? SleepSyncLogic.preferredSleepReadings(readings)
              : (readings.where((item) => item.type == type).toList()
                  ..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
          if (matches.isEmpty) {
            return TodaySignalSummary(
              type: type,
              displayValue: '—',
              recordedAt: null,
              readingCount: 0,
            );
          }
          final value =
              type == SignalType.sleep || type == SignalType.reactionTime
              ? matches.first.value
              : matches.fold<double>(0, (sum, item) => sum + item.value);
          return TodaySignalSummary(
            type: type,
            displayValue: _displayValue(type, value),
            recordedAt: matches.first.timestamp,
            readingCount: matches.length,
          );
        })
        .toList(growable: false);
  }

  static String _displayValue(SignalType type, double value) => switch (type) {
    SignalType.reactionTime => '${value.round()} ms',
    SignalType.hydration => '${value.toStringAsFixed(1)} L',
    SignalType.steps => '${value.round()} steps',
    SignalType.sleep ||
    SignalType.exercise ||
    SignalType.study ||
    SignalType.screenTime => '${value.toStringAsFixed(1)} hr',
    _ => '${value.toStringAsFixed(1)} ${type.unit}',
  };
}
