import 'models.dart';
import 'sleep_sync_logic.dart';

/// Builds robust rolling baselines from one user's historical signal query.
/// Current-day observations are excluded so a value is never compared with a
/// reference that already contains itself.
abstract final class PersonalBaselineLogic {
  static const windowDays = 42;

  static PersonalBaselines build({
    required Iterable<SignalReading> signals,
    required DateTime asOf,
  }) {
    final cutoff = DateTime(asOf.year, asOf.month, asOf.day);
    final start = cutoff.subtract(const Duration(days: windowDays));
    final historical = signals
        .where(
          (item) =>
              !item.timestamp.isBefore(start) &&
              item.timestamp.isBefore(cutoff),
        )
        .toList();

    return PersonalBaselines(
      generatedAt: asOf,
      windowDays: windowDays,
      metrics: [
        _metric(
          PersonalBaselineType.hrv,
          _dailyValues(historical, SignalType.hrv),
        ),
        _metric(
          PersonalBaselineType.restingHeartRate,
          _dailyValues(historical, SignalType.restingHeartRate),
        ),
        _metric(PersonalBaselineType.sleep, [
          for (final item in SleepSyncLogic.preferredSleepReadings(historical))
            (timestamp: item.timestamp, value: item.value),
        ]),
        _metric(
          PersonalBaselineType.reactionTime,
          _dailyValues(historical, SignalType.reactionTime),
          maximumSamples: 14,
        ),
      ],
    );
  }

  static double? currentValue(
    PersonalBaselineType type, {
    required Iterable<SignalReading> signals,
    required DateTime day,
  }) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final readings = signals
        .where(
          (item) =>
              !item.timestamp.isBefore(start) && item.timestamp.isBefore(end),
        )
        .toList();
    final typeReadings = switch (type) {
      PersonalBaselineType.hrv =>
        readings.where((item) => item.type == SignalType.hrv).toList(),
      PersonalBaselineType.restingHeartRate =>
        readings
            .where((item) => item.type == SignalType.restingHeartRate)
            .toList(),
      PersonalBaselineType.sleep => SleepSyncLogic.preferredSleepReadings(
        readings,
      ),
      PersonalBaselineType.reactionTime =>
        readings.where((item) => item.type == SignalType.reactionTime).toList(),
    };
    final valid = typeReadings
        .where((item) => item.value.isFinite && item.value > 0)
        .toList();
    if (valid.isEmpty) return null;
    return valid.fold<double>(0, (sum, item) => sum + item.value) /
        valid.length;
  }

  static double? differencePercent({
    required double? current,
    required PersonalBaselineMetric? baseline,
  }) {
    final reference = baseline?.value;
    if (current == null ||
        reference == null ||
        reference == 0 ||
        baseline?.isReady != true) {
      return null;
    }
    return ((current - reference) / reference) * 100;
  }

  static List<({DateTime timestamp, double value})> _dailyValues(
    Iterable<SignalReading> signals,
    SignalType type,
  ) {
    final byDay = <String, List<SignalReading>>{};
    for (final item in signals.where(
      (item) => item.type == type && item.value.isFinite && item.value > 0,
    )) {
      byDay.putIfAbsent(_dayKey(item.timestamp), () => []).add(item);
    }
    return [
      for (final values in byDay.values)
        (
          timestamp: values
              .map((item) => item.timestamp)
              .reduce((left, right) => left.isAfter(right) ? left : right),
          value:
              values.fold<double>(0, (sum, item) => sum + item.value) /
              values.length,
        ),
    ];
  }

  static PersonalBaselineMetric _metric(
    PersonalBaselineType type,
    List<({DateTime timestamp, double value})> raw, {
    int maximumSamples = 28,
  }) {
    final values =
        raw.where((item) => item.value.isFinite && item.value > 0).toList()
          ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
    final selected = values.take(maximumSamples).toList();
    if (selected.isEmpty) {
      return PersonalBaselineMetric(
        type: type,
        value: null,
        sampleCount: 0,
        minimumSamples: type.minimumSamples,
        variability: 0,
      );
    }
    final baseline = _median(selected.map((item) => item.value).toList());
    final deviations = selected
        .map((item) => (item.value - baseline).abs())
        .toList();
    return PersonalBaselineMetric(
      type: type,
      value: baseline,
      sampleCount: selected.length,
      minimumSamples: type.minimumSamples,
      variability: _median(deviations),
      latestSampleAt: selected.first.timestamp,
    );
  }

  static double _median(List<double> raw) {
    final values = [...raw]..sort();
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }

  static String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
