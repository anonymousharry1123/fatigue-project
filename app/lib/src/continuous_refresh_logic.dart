import 'activity_sync_logic.dart';
import 'models.dart';
import 'sleep_sync_logic.dart';

/// Pure Version 0.26 policy for deciding when HealthKit should be queried and
/// whether an import can change a model output.
abstract final class ContinuousRefreshLogic {
  static const foregroundRefreshInterval = Duration(minutes: 15);

  static bool shouldRefresh({
    required DateTime now,
    DateTime? lastAttempt,
    Duration minimumInterval = foregroundRefreshInterval,
  }) => lastAttempt == null || now.difference(lastAttempt) >= minimumInterval;

  static bool hasMeaningfulModelChange(
    Iterable<SignalReading> before,
    Iterable<SignalReading> after,
  ) => modelInputFingerprint(before) != modelInputFingerprint(after);

  /// Sync bookkeeping is deliberately excluded. The fingerprint represents
  /// only effective score/forecast inputs, so re-reading an unchanged sample
  /// can update sync freshness without regenerating derived documents.
  static String modelInputFingerprint(Iterable<SignalReading> readings) {
    final all = readings.toList();
    final values = <String>[];

    void addSignal(SignalReading item) {
      values.add(
        '${item.type.name}|${item.id}|${item.value.toStringAsFixed(6)}|'
        '${item.timestamp.microsecondsSinceEpoch}|${item.source.name}|'
        '${item.quality.toStringAsFixed(4)}',
      );
    }

    const directTypes = {
      SignalType.study,
      SignalType.screenTime,
      SignalType.caffeine,
      SignalType.reactionTime,
      SignalType.hrv,
      SignalType.restingHeartRate,
    };
    for (final item in all.where((item) => directTypes.contains(item.type))) {
      addSignal(item);
    }
    for (final item in SleepSyncLogic.preferredSleepReadings(all)) {
      addSignal(item);
    }
    for (final item in SleepSyncLogic.preferredBedtimeReadings(all)) {
      addSignal(item);
    }

    final activityDays = all
        .where((item) => ActivitySyncLogic.supportedTypes.contains(item.type))
        .map(
          (item) => DateTime(
            item.timestamp.year,
            item.timestamp.month,
            item.timestamp.day,
          ),
        )
        .toSet();
    for (final day in activityDays) {
      for (final type in ActivitySyncLogic.supportedTypes) {
        final aggregate = ActivitySyncLogic.aggregateForDay(
          all,
          type: type,
          day: day,
        );
        if (aggregate != null) {
          values.add(
            '${type.name}|${day.toIso8601String()}|'
            '${aggregate.total.toStringAsFixed(6)}|'
            '${aggregate.usesManualCorrection}',
          );
        }
      }
    }

    values.sort();
    return values.join('\n');
  }
}
