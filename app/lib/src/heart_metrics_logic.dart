import 'heart_derivation_logic.dart';
import 'evidence_provenance.dart';
import 'local_day.dart';
import 'models.dart';

class HeartMetricAverage {
  HeartMetricAverage(List<SignalReading> readings)
    : mean =
          readings.fold<double>(0, (sum, item) => sum + item.value) /
          readings.length,
      sampleCount = readings.length,
      containsDemo = readings.any(EvidenceProvenance.signalIsDemo),
      sources = Set.unmodifiable(readings.map((item) => item.source));

  final double mean;
  final int sampleCount;
  final bool containsDemo;
  final Set<SignalSource> sources;
}

class HeartMetricsDay {
  const HeartMetricsDay({
    required this.date,
    this.heartRate,
    this.restingHeartRate,
    this.estimatedRestingHeartRate,
    this.hrv,
    this.variation,
  });

  final DateTime date;
  final HeartMetricAverage? heartRate;
  final HeartMetricAverage? restingHeartRate;
  final HeartMetricAverage? estimatedRestingHeartRate;
  final HeartMetricAverage? hrv;
  final SampledHeartRateVariation? variation;
}

/// Presentation-only averages. Original observations remain unchanged.
abstract final class HeartMetricsLogic {
  static List<HeartMetricsDay> build({
    required Iterable<SignalReading> readings,
    required DateTime now,
    bool includeDerivations = true,
  }) {
    final unique = <String, SignalReading>{};
    for (final reading in readings) {
      if (!_valid(reading, now)) continue;
      final key =
          '${reading.type.name}:${reading.source.name}:'
          '${reading.id.trim().toLowerCase()}';
      final previous = unique[key];
      final revision =
          reading.syncedAt ?? reading.recordedAt ?? reading.timestamp;
      final previousRevision =
          previous?.syncedAt ?? previous?.recordedAt ?? previous?.timestamp;
      if (previousRevision == null || revision.isAfter(previousRevision)) {
        unique[key] = reading;
      }
    }
    final derivation = includeDerivations
        ? HeartDerivationLogic.reconcile(readings: unique.values, now: now)
        : null;
    final byDay = <DateTime, List<SignalReading>>{};
    for (final reading in derivation?.readings ?? unique.values) {
      if (!_valid(reading, now)) continue;
      byDay.putIfAbsent(localDay(reading.timestamp), () => []).add(reading);
    }
    final variations = {
      for (final day in derivation?.days ?? <HeartDerivationDay>[])
        if (day.variation != null) day.localDay: day.variation!,
    };
    HeartMetricAverage? average(Iterable<SignalReading> values) {
      final samples = values.toList();
      return samples.isEmpty ? null : HeartMetricAverage(samples);
    }

    return [
      for (final entry in byDay.entries)
        HeartMetricsDay(
          date: entry.key,
          heartRate: average(
            entry.value.where((r) => r.type == SignalType.heartRate),
          ),
          restingHeartRate: average(
            entry.value.where(
              (r) =>
                  r.type == SignalType.restingHeartRate &&
                  !HeartDerivationLogic.isEstimatedRestingHeartRate(r),
            ),
          ),
          estimatedRestingHeartRate: average(
            entry.value.where(HeartDerivationLogic.isEstimatedRestingHeartRate),
          ),
          hrv: average(entry.value.where((r) => r.type == SignalType.hrv)),
          variation: variations[entry.key],
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));
  }

  static bool _valid(SignalReading reading, DateTime now) {
    if (reading.id.trim().isEmpty ||
        !reading.value.isFinite ||
        !reading.quality.isFinite ||
        reading.quality <= 0 ||
        reading.quality > 1 ||
        reading.timestamp.isAfter(now) ||
        (reading.syncedAt?.isAfter(now) ?? false) ||
        (reading.recordedAt?.isAfter(now) ?? false)) {
      return false;
    }
    final measured =
        reading.source == SignalSource.healthKit ||
        reading.source == SignalSource.manual;
    return switch (reading.type) {
      SignalType.heartRate =>
        measured && reading.value >= 20 && reading.value <= 300,
      SignalType.restingHeartRate =>
        (measured ||
                HeartDerivationLogic.isEstimatedRestingHeartRate(reading)) &&
            reading.value >= 20 &&
            reading.value <= 250,
      SignalType.hrv => measured && reading.value > 0 && reading.value <= 1000,
      _ => false,
    };
  }
}
