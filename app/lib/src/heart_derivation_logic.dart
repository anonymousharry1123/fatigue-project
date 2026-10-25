import 'dart:math' as math;

import 'models.dart';
import 'oura_data.dart';

enum RestingHeartRateDerivationStatus {
  native,
  existingMeasurement,
  estimated,
  insufficientSamples,
}

enum HeartRateVariabilityAvailability {
  native,
  beatIntervalsRequired,
  noHeartRateSamples,
}

/// Variation between ordinary sampled bpm observations, never beat-to-beat HRV.
class SampledHeartRateVariation {
  const SampledHeartRateVariation({
    required this.rmsSuccessiveDifferenceBpm,
    required this.sampleCount,
    required this.pairCount,
    required this.start,
    required this.end,
  });

  final double rmsSuccessiveDifferenceBpm;
  final int sampleCount;
  final int pairCount;
  final DateTime start;
  final DateTime end;
}

class HeartDerivationDay {
  const HeartDerivationDay({
    required this.localDay,
    required this.overnightSampleCount,
    required this.restingStatus,
    required this.hrvStatus,
    required this.daytimeSampleCount,
    this.variation,
  });

  final DateTime localDay;
  final int overnightSampleCount;
  final RestingHeartRateDerivationStatus restingStatus;
  final HeartRateVariabilityAvailability hrvStatus;
  final int daytimeSampleCount;
  final SampledHeartRateVariation? variation;
}

class HeartDerivationResult {
  const HeartDerivationResult({
    required this.readings,
    required this.estimatedRestingHeartRates,
    required this.days,
    required this.changed,
  });

  final List<SignalReading> readings;
  final List<SignalReading> estimatedRestingHeartRates;

  /// Most recent local date first. Includes today even when no samples exist.
  final List<HeartDerivationDay> days;
  final bool changed;
}

/// Conservative gap filling for imported heart data.
///
/// Resting HR is an explicitly labelled heuristic: the lowest median of three
/// consecutive, distinct-time overnight observations. This is not a native
/// device resting-HR measurement and is informational only: measured baselines,
/// scoring and training exclude it. Ordinary bpm samples cannot recover the
/// beat-to-beat NN intervals required by SDNN or RMSSD, regardless of how many
/// such samples exist, so this module never creates an HRV reading.
class HeartDerivationLogic {
  const HeartDerivationLogic._();

  static const restingIdPrefix = 'derived-hr-resting-';
  static const minimumOvernightSamples = 3;
  static const maximumEstimateQuality = .5;
  static const minimumVariationSamples = 6;
  static const minimumVariationSpan = Duration(hours: 2);
  static const maximumVariationGap = Duration(minutes: 45);

  static bool isEstimatedRestingHeartRate(SignalReading reading) =>
      reading.type == SignalType.restingHeartRate &&
      reading.source == SignalSource.model &&
      reading.id.startsWith(restingIdPrefix);

  /// Rebuilds only days for which local source samples are available. A cloud
  /// restore may have an estimate but no raw bpm data; that estimate is retained
  /// until a measurement replaces it or the caller marks its day authoritative
  /// (for example after deleting the last local raw observation for that day).
  static HeartDerivationResult reconcile({
    required Iterable<SignalReading> readings,
    required DateTime now,
    Set<DateTime> authoritativeLocalDays = const {},
  }) {
    final original = readings.toList();
    final retained = <SignalReading>[];
    final priorEstimates = <DateTime, List<SignalReading>>{};
    final rawByDay = <DateTime, List<SignalReading>>{};
    final rawObservedDays = <DateTime>{};
    final existingRestingByDay = <DateTime, List<SignalReading>>{};
    final nativeHrvDays = <DateTime>{};
    final dates = <DateTime>{localDay(now)};
    final authoritative = authoritativeLocalDays.map(localDay).toSet();
    dates.addAll(authoritative);

    for (final reading in original) {
      final day = localDay(reading.timestamp);
      if (isEstimatedRestingHeartRate(reading)) {
        if (!_available(reading, now)) {
          retained.add(reading);
          continue;
        }
        priorEstimates.putIfAbsent(day, () => []).add(reading);
        dates.add(day);
        continue;
      }
      retained.add(reading);
      if (!_available(reading, now)) continue;
      if (reading.type == SignalType.heartRate &&
          reading.source == SignalSource.healthKit) {
        rawObservedDays.add(day);
        if (_validHeartRate(reading)) {
          rawByDay.putIfAbsent(day, () => []).add(reading);
        }
        dates.add(day);
      } else if (reading.type == SignalType.restingHeartRate &&
          !OuraData.isOuraOrigin(reading) &&
          _validRestingHeartRate(reading)) {
        existingRestingByDay.putIfAbsent(day, () => []).add(reading);
        dates.add(day);
      } else if (reading.type == SignalType.hrv &&
          reading.source == SignalSource.healthKit &&
          reading.value.isFinite &&
          reading.value > 0 &&
          reading.value <= 1000) {
        nativeHrvDays.add(day);
        dates.add(day);
      }
    }

    final estimates = <SignalReading>[];
    final days = <HeartDerivationDay>[];
    final sortedDates = dates.toList()..sort((a, b) => b.compareTo(a));
    for (final day in sortedDates) {
      final raw = _distinctSamples(rawByDay[day] ?? const []);
      final overnight = raw
          .where((reading) => reading.timestamp.toLocal().hour < 8)
          .toList();
      final existingResting = existingRestingByDay[day] ?? const [];
      final prior = priorEstimates[day] ?? const [];
      final hasNativeResting = existingResting.any(
        (reading) => reading.source == SignalSource.healthKit,
      );
      var status = hasNativeResting
          ? RestingHeartRateDerivationStatus.native
          : existingResting.isNotEmpty
          ? RestingHeartRateDerivationStatus.existingMeasurement
          : RestingHeartRateDerivationStatus.insufficientSamples;

      if (existingResting.isEmpty) {
        if (overnight.length >= minimumOvernightSamples) {
          final estimate = _estimate(day, overnight, now);
          if (estimate != null) {
            final unchanged = prior.where(
              (reading) => _sameEstimate(reading, estimate),
            );
            estimates.add(unchanged.isEmpty ? estimate : unchanged.first);
            status = RestingHeartRateDerivationStatus.estimated;
          }
        } else if (!rawObservedDays.contains(day) &&
            !authoritative.contains(day)) {
          // A summary-only restore must not erase a different phone's valid
          // estimate merely because this phone does not own its raw samples.
          estimates.addAll(prior);
          if (prior.isNotEmpty) {
            status = RestingHeartRateDerivationStatus.estimated;
          }
        }
      }
      days.add(
        HeartDerivationDay(
          localDay: day,
          overnightSampleCount: overnight.length,
          restingStatus: status,
          hrvStatus: nativeHrvDays.contains(day)
              ? HeartRateVariabilityAvailability.native
              : raw.isEmpty
              ? HeartRateVariabilityAvailability.noHeartRateSamples
              : HeartRateVariabilityAvailability.beatIntervalsRequired,
          daytimeSampleCount: raw
              .where((reading) => reading.timestamp.toLocal().hour >= 8)
              .length,
          variation: sampledHeartRateVariation(raw, now: now),
        ),
      );
    }
    retained.addAll(estimates);
    retained.sort((a, b) {
      final timestamp = b.timestamp.compareTo(a.timestamp);
      return timestamp != 0 ? timestamp : a.id.compareTo(b.id);
    });
    final before = [...original]..sort((a, b) => a.id.compareTo(b.id));
    final after = [...retained]..sort((a, b) => a.id.compareTo(b.id));
    return HeartDerivationResult(
      readings: retained,
      estimatedRestingHeartRates: estimates,
      days: days,
      changed:
          before.length != after.length ||
          List.generate(
            before.length,
            (index) => index,
          ).any((index) => !_sameReading(before[index], after[index])),
    );
  }

  static DateTime localDay(DateTime timestamp) {
    final local = timestamp.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// RMS of successive changes in bpm, with no conversion or clamp to ms.
  ///
  /// Each eligible run has at least six distinct daytime samples across two
  /// hours, with no gap above 45 minutes. Pairs across gaps or local dates are
  /// excluded. This descriptive metric is not a physiological HRV measurement
  /// and must not be passed to the HRV baseline or fatigue score.
  static SampledHeartRateVariation? sampledHeartRateVariation(
    Iterable<SignalReading> readings, {
    required DateTime now,
    DateTime Function(SignalReading)? localTimestamp,
  }) {
    final localTime =
        localTimestamp ??
        (SignalReading reading) => reading.timestamp.toLocal();
    final samples = _distinctSamples(
      readings
          .where(
            (reading) =>
                reading.type == SignalType.heartRate &&
                reading.source == SignalSource.healthKit &&
                _available(reading, now) &&
                _validHeartRate(reading) &&
                localTime(reading).hour >= 8,
          )
          .toList(),
    );
    final runs = <List<SignalReading>>[];
    var run = <SignalReading>[];
    for (final sample in samples) {
      if (run.isNotEmpty &&
          (!_sameCalendarDay(localTime(sample), localTime(run.last)) ||
              sample.timestamp.difference(run.last.timestamp) >
                  maximumVariationGap)) {
        runs.add(run);
        run = [];
      }
      run.add(sample);
    }
    if (run.isNotEmpty) runs.add(run);
    final eligible = runs.where(
      (items) =>
          items.length >= minimumVariationSamples &&
          items.last.timestamp.difference(items.first.timestamp) >=
              minimumVariationSpan,
    );
    var squaredChanges = 0.0;
    var pairs = 0;
    var count = 0;
    DateTime? start;
    DateTime? end;
    for (final items in eligible) {
      start ??= items.first.timestamp;
      end = items.last.timestamp;
      count += items.length;
      for (var index = 1; index < items.length; index += 1) {
        final change = items[index].value - items[index - 1].value;
        squaredChanges += change * change;
        pairs += 1;
      }
    }
    if (pairs == 0) return null;
    return SampledHeartRateVariation(
      rmsSuccessiveDifferenceBpm: math.sqrt(squaredChanges / pairs),
      sampleCount: count,
      pairCount: pairs,
      start: start!,
      end: end!,
    );
  }

  static bool _sameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _available(SignalReading reading, DateTime now) =>
      !reading.timestamp.isAfter(now) &&
      !(reading.syncedAt?.isAfter(now) ?? false) &&
      !(reading.recordedAt?.isAfter(now) ?? false);

  static bool _validHeartRate(SignalReading reading) =>
      reading.id.trim().isNotEmpty &&
      reading.value.isFinite &&
      reading.value >= 20 &&
      reading.value <= 300 &&
      reading.quality.isFinite &&
      reading.quality > 0;

  static bool _validRestingHeartRate(SignalReading reading) =>
      reading.value.isFinite && reading.value >= 20 && reading.value <= 250;

  static List<SignalReading> _distinctSamples(List<SignalReading> readings) {
    final sorted = [...readings]
      ..sort((a, b) {
        final timestamp = a.timestamp.compareTo(b.timestamp);
        return timestamp != 0 ? timestamp : a.id.compareTo(b.id);
      });
    final ids = <String>{};
    final timestamps = <int>{};
    return sorted.where((reading) {
      final id = reading.id.trim().toLowerCase();
      final timestamp = reading.timestamp.microsecondsSinceEpoch;
      if (ids.contains(id) || timestamps.contains(timestamp)) return false;
      ids.add(id);
      timestamps.add(timestamp);
      return true;
    }).toList();
  }

  static SignalReading? _estimate(
    DateTime day,
    List<SignalReading> overnight,
    DateTime now,
  ) {
    var minimum = double.infinity;
    List<SignalReading>? selected;
    for (var index = 0; index <= overnight.length - 3; index += 1) {
      final window = overnight.sublist(index, index + 3);
      final values = window.map((reading) => reading.value).toList()..sort();
      if (values[1] < minimum) {
        minimum = values[1];
        selected = window;
      }
    }
    if (selected == null || minimum > 250) return null;
    final sourceNotes =
        selected
            .map((reading) => reading.note?.trim())
            .whereType<String>()
            .where((note) => note.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final provenance = sourceNotes.isEmpty
        ? 'Apple Health'
        : sourceNotes.join(' / ');
    final sourceQuality = selected
        .map((reading) => reading.quality.clamp(0, 1).toDouble())
        .reduce(math.min);
    return SignalReading(
      id: '$restingIdPrefix${_dateId(day)}',
      type: SignalType.restingHeartRate,
      value: minimum,
      timestamp: selected.last.timestamp,
      source: SignalSource.model,
      quality: math.min(maximumEstimateQuality, sourceQuality * .5),
      note: 'Estimated resting HR from overnight heart rate · $provenance',
      recordedAt: now,
    );
  }

  static bool _sameEstimate(SignalReading a, SignalReading b) =>
      a.id == b.id &&
      a.type == b.type &&
      a.value == b.value &&
      a.timestamp.isAtSameMomentAs(b.timestamp) &&
      a.source == b.source &&
      a.quality == b.quality &&
      a.note == b.note;

  static bool _sameReading(SignalReading a, SignalReading b) =>
      identical(a, b) ||
      (_sameEstimate(a, b) &&
          a.groupId == b.groupId &&
          a.recordedAt == b.recordedAt &&
          a.syncedAt == b.syncedAt);

  static String _dateId(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
