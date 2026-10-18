import 'models.dart';

class HeartSyncMergeResult {
  const HeartSyncMergeResult({
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

/// Normalizes and merges Apple Health heart samples.
class HeartSyncLogic {
  const HeartSyncLogic._();

  static const duplicateWindow = Duration(minutes: 2);
  static const duplicateValueTolerance = .1;

  static const supportedTypes = {
    SignalType.hrv,
    SignalType.restingHeartRate,
    SignalType.heartRate,
  };

  static HeartSyncMergeResult merge({
    required Iterable<SignalReading> existing,
    required Iterable<SignalReading> imported,
    DateTime? syncedAt,
  }) {
    final readings = [...existing];
    final ids = readings.map((item) => item.id).toSet();
    // Regular heart rate can arrive many times per minute. Its stable HealthKit
    // sample ID is the identity; equal bpm nearby can be distinct observations.
    // Keep the historical proximity rule only for HRV and resting heart rate,
    // without scanning dense regular-heart-rate history for each imported row.
    final comparableReadings = <SignalType, List<SignalReading>>{
      for (final type in [SignalType.hrv, SignalType.restingHeartRate])
        type: readings.where((item) => item.type == type).toList(),
    };
    var importedCount = 0;
    var duplicateCount = 0;
    var rejectedCount = 0;

    for (final raw in imported) {
      final candidate = _normalize(raw, syncedAt: syncedAt);
      if (candidate == null) {
        rejectedCount += 1;
        continue;
      }
      final duplicate =
          ids.contains(candidate.id) ||
          (comparableReadings[candidate.type]?.any(
                (item) =>
                    item.timestamp
                            .difference(candidate.timestamp)
                            .inMilliseconds
                            .abs() <=
                        duplicateWindow.inMilliseconds &&
                    (item.value - candidate.value).abs() <=
                        duplicateValueTolerance,
              ) ??
              false);
      if (duplicate) {
        duplicateCount += 1;
        continue;
      }
      readings.add(candidate);
      ids.add(candidate.id);
      comparableReadings[candidate.type]?.add(candidate);
      importedCount += 1;
    }

    readings.sort((left, right) => right.timestamp.compareTo(left.timestamp));
    return HeartSyncMergeResult(
      readings: readings,
      importedCount: importedCount,
      duplicateCount: duplicateCount,
      rejectedCount: rejectedCount,
    );
  }

  static SignalReading? _normalize(
    SignalReading reading, {
    DateTime? syncedAt,
  }) {
    if (!supportedTypes.contains(reading.type) ||
        !reading.value.isFinite ||
        !_validRange(reading.type, reading.value) ||
        reading.id.trim().isEmpty) {
      return null;
    }
    final quality = reading.quality.isFinite
        ? reading.quality.clamp(0, 1).toDouble()
        : 1.0;
    return SignalReading(
      id: reading.id.trim(),
      type: reading.type,
      value: reading.value,
      timestamp: reading.timestamp.toLocal(),
      source: SignalSource.healthKit,
      quality: quality,
      note: reading.note,
      syncedAt: syncedAt ?? reading.syncedAt ?? DateTime.now().toUtc(),
    );
  }

  static bool _validRange(SignalType type, double value) => switch (type) {
    SignalType.hrv => value > 0 && value <= 1000,
    SignalType.restingHeartRate => value >= 20 && value <= 250,
    SignalType.heartRate => value >= 20 && value <= 300,
    _ => false,
  };
}
