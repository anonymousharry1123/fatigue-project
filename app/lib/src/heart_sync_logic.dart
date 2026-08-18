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

/// Normalizes and merges Version 0.23 Apple Health heart samples.
class HeartSyncLogic {
  const HeartSyncLogic._();

  static const duplicateWindow = Duration(minutes: 2);
  static const duplicateValueTolerance = .1;

  static const supportedTypes = {SignalType.hrv, SignalType.restingHeartRate};

  static HeartSyncMergeResult merge({
    required Iterable<SignalReading> existing,
    required Iterable<SignalReading> imported,
  }) {
    final readings = [...existing];
    var importedCount = 0;
    var duplicateCount = 0;
    var rejectedCount = 0;

    for (final raw in imported) {
      final candidate = _normalize(raw);
      if (candidate == null) {
        rejectedCount += 1;
        continue;
      }
      final duplicate = readings.any(
        (item) =>
            item.id == candidate.id ||
            (item.type == candidate.type &&
                item.timestamp
                        .difference(candidate.timestamp)
                        .inMilliseconds
                        .abs() <=
                    duplicateWindow.inMilliseconds &&
                (item.value - candidate.value).abs() <=
                    duplicateValueTolerance),
      );
      if (duplicate) {
        duplicateCount += 1;
        continue;
      }
      readings.add(candidate);
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

  static SignalReading? _normalize(SignalReading reading) {
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
    );
  }

  static bool _validRange(SignalType type, double value) => switch (type) {
    SignalType.hrv => value > 0 && value <= 1000,
    SignalType.restingHeartRate => value >= 20 && value <= 250,
    _ => false,
  };
}
