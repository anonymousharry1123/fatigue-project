import 'dart:convert';

import 'models.dart';

/// Oura sleep measurements retain their original definitions. RMSSD is not
/// HealthKit SDNN, and the nightly minimum is not HealthKit resting heart rate.
abstract final class OuraData {
  static const hrvMethod = 'rmssd_sleep_average';
  static const restingMethod = 'sleep_minimum_5min';
  static const apiRestingMethod = 'sleep_minimum_api';

  static bool isOuraOrigin(SignalReading reading) {
    if (reading.source == SignalSource.oura) return true;
    if (reading.source != SignalSource.healthKit) return false;
    final bundle = reading.sourceBundleId?.trim().toLowerCase();
    final name = reading.sourceName?.trim().toLowerCase();
    return bundle == 'com.ouraring.oura' ||
        (bundle?.startsWith('com.ouraring.') ?? false) ||
        name == 'oura' ||
        name == 'oura ring';
  }

  static bool isValidOuraReading(SignalReading reading, DateTime now) {
    if (reading.source != SignalSource.oura ||
        reading.id.trim().isEmpty ||
        !reading.value.isFinite ||
        !reading.quality.isFinite ||
        reading.quality <= 0 ||
        reading.quality > 1 ||
        reading.timestamp.isAfter(now) ||
        (reading.syncedAt?.isAfter(now) ?? false) ||
        (reading.recordedAt?.isAfter(now) ?? false) ||
        sourceDate(reading.sourceDay) == null) {
      return false;
    }
    return switch (reading.type) {
      SignalType.hrv =>
        reading.measurementMethod == hrvMethod &&
            reading.value > 0 &&
            reading.value <= 1000,
      SignalType.restingHeartRate =>
        (reading.measurementMethod == restingMethod ||
                reading.measurementMethod == apiRestingMethod) &&
            reading.value >= 20 &&
            reading.value <= 250,
      _ => false,
    };
  }

  /// Hide identified HealthKit mirrors only when a valid direct Oura metric
  /// exists for the same day and quantity. Original observations stay stored.
  static List<SignalReading> withoutHealthKitMirrors(
    Iterable<SignalReading> readings, {
    required DateTime now,
  }) {
    final original = readings.toList();
    final direct = {
      for (final item in original)
        if (isValidOuraReading(item, now))
          '${item.sourceDay}:${item.type.name}',
    };
    return original.where((item) {
      if (item.source != SignalSource.healthKit || !isOuraOrigin(item)) {
        return true;
      }
      final date = sourceDate(item.sourceDay) ?? item.timestamp.toLocal();
      final day =
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      return !direct.contains('$day:${item.type.name}');
    }).toList();
  }

  /// Reconcile only a fully fetched inclusive Oura date window. A missing or
  /// null metric removes its previous value, while other sources and dates are
  /// retained. Validation completes before any replacement. Unchanged records
  /// retain their original syncedAt, avoiding writes on every automatic sync.
  static List<SignalReading> reconcile(
    Iterable<SignalReading> existing,
    Iterable<Map<String, dynamic>> records, {
    required DateTime syncedAt,
    required String startDay,
    required String endDay,
  }) {
    final start = sourceDate(startDay);
    final end = sourceDate(endDay);
    if (start == null || end == null || end.isBefore(start)) {
      throw const FormatException('Invalid Oura sync date window.');
    }
    final normalized = normalizeSleep(records, syncedAt: syncedAt)
        .where(
          (item) =>
              item.sourceDay!.compareTo(startDay) >= 0 &&
              item.sourceDay!.compareTo(endDay) <= 0,
        )
        .toList();
    final previous = <String, SignalReading>{};
    final retained = <SignalReading>[];
    for (final item in existing) {
      final day = item.sourceDay;
      if (item.source == SignalSource.oura &&
          sourceDate(day) != null &&
          day!.compareTo(startDay) >= 0 &&
          day.compareTo(endDay) <= 0) {
        final prior = previous[item.id];
        if (prior == null ||
            (item.syncedAt ?? item.timestamp).isAfter(
              prior.syncedAt ?? prior.timestamp,
            )) {
          previous[item.id] = item;
        }
      } else {
        retained.add(item);
      }
    }
    for (final item in normalized) {
      final prior = previous[item.id];
      final value = item.toJson()..remove('syncedAt');
      final oldValue = prior?.toJson()?..remove('syncedAt');
      retained.add(
        prior != null && jsonEncode(value) == jsonEncode(oldValue)
            ? prior
            : item,
      );
    }
    return retained..sort((a, b) {
      final time = b.timestamp.compareTo(a.timestamp);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
  }

  /// Converts a complete, paginated Oura /sleep response. Select the longest
  /// completed long_sleep on each Oura calendar day before inspecting metrics.
  /// Stable daily IDs replace revisions and a changed primary sleep session.
  /// A caller must replace its Oura records for the successfully fetched window
  /// (including missing/deleted metrics); it must never replace Apple records.
  static List<SignalReading> normalizeSleep(
    Iterable<Map<String, dynamic>> records, {
    required DateTime syncedAt,
  }) {
    final sessions = <String, _OuraSleep>{};
    final originals = <String, String>{};
    for (final record in records) {
      final session = _OuraSleep.parse(record, syncedAt);
      if (session == null) continue;
      // The API supplies current sessions, not an ordered revision history.
      // Conflicting duplicate IDs cannot be resolved by response/page order.
      final canonical = jsonEncode({
        for (final key in record.keys.toList()..sort()) key: record[key],
      });
      if (originals[session.id] case final previous?) {
        if (previous != canonical) {
          throw const FormatException('Conflicting Oura sleep records.');
        }
        continue;
      }
      originals[session.id] = canonical;
      sessions[session.id] = session;
    }
    final selected = <String, _OuraSleep>{};
    for (final session in sessions.values) {
      final previous = selected[session.day];
      if (previous == null || session.compareTo(previous) < 0) {
        selected[session.day] = session;
      }
    }
    final output = <SignalReading>[];
    for (final session in selected.values) {
      void add(SignalType type, double value, String method) {
        output.add(
          SignalReading(
            id: 'oura-${type.name}-${session.day}',
            type: type,
            value: value,
            timestamp: session.end,
            source: SignalSource.oura,
            groupId: 'oura-sleep-${session.id}',
            syncedAt: syncedAt,
            sourceName: 'Oura',
            sourceRecordId: session.id,
            sourceDay: session.day,
            measurementMethod: method,
          ),
        );
      }

      final hrv = _number(session.raw['average_hrv'], 0, 1000);
      if (hrv != null && hrv > 0) add(SignalType.hrv, hrv, hrvMethod);
      final sampledResting = session.minimumFiveMinuteHeartRate();
      if (sampledResting != null) {
        add(SignalType.restingHeartRate, sampledResting, restingMethod);
      } else {
        final apiResting = _number(session.raw['lowest_heart_rate'], 20, 250);
        if (apiResting != null) {
          add(SignalType.restingHeartRate, apiResting, apiRestingMethod);
        }
      }
    }
    return output..sort((a, b) => a.id.compareTo(b.id));
  }

  /// Returns the Oura date without shifting it when the phone changes zones.
  static DateTime? sourceDate(String? value) {
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        '${parsed.year.toString().padLeft(4, '0')}-'
                '${parsed.month.toString().padLeft(2, '0')}-'
                '${parsed.day.toString().padLeft(2, '0')}' !=
            value) {
      return null;
    }
    return parsed;
  }

  static double? _number(Object? value, double minimum, double maximum) {
    if (value is! num) return null;
    final number = value.toDouble();
    return number.isFinite && number >= minimum && number <= maximum
        ? number
        : null;
  }
}

class _OuraSleep {
  const _OuraSleep(this.id, this.day, this.start, this.end, this.raw);
  final String id;
  final String day;
  final DateTime start;
  final DateTime end;
  final Map<String, dynamic> raw;

  static _OuraSleep? parse(Map<String, dynamic> raw, DateTime syncedAt) {
    final id = raw['id'];
    final day = raw['day'];
    if (id is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
        day is! String ||
        OuraData.sourceDate(day) == null) {
      throw const FormatException('Invalid Oura sleep identity or date.');
    }
    if (const {'deleted', 'sleep', 'late_nap', 'rest'}.contains(raw['type'])) {
      return null;
    }
    if (raw['type'] != 'long_sleep') {
      throw const FormatException('Unknown Oura sleep period type.');
    }
    final start = _instant(raw['bedtime_start']);
    final end = _instant(raw['bedtime_end']);
    if (start == null ||
        end == null ||
        !end.isAfter(start) ||
        end.difference(start) > const Duration(hours: 24) ||
        end.isAfter(syncedAt)) {
      throw const FormatException('Invalid Oura sleep interval.');
    }
    for (final entry in {
      'average_hrv': (minimum: 0.0, maximum: 1000.0),
      'lowest_heart_rate': (minimum: 20.0, maximum: 250.0),
    }.entries) {
      if (raw[entry.key] != null &&
          OuraData._number(
                raw[entry.key],
                entry.value.minimum,
                entry.value.maximum,
              ) ==
              null) {
        throw const FormatException('Invalid Oura heart measurement.');
      }
    }
    return _OuraSleep(id, day, start, end, raw);
  }

  /// Longest interval first, then latest end, then stable record ID. Metric
  /// completeness or a more favorable HRV value never selects a different sleep.
  int compareTo(_OuraSleep other) {
    final duration = other.end
        .difference(other.start)
        .compareTo(end.difference(start));
    if (duration != 0) return duration;
    final time = other.end.compareTo(end);
    return time != 0 ? time : id.compareTo(other.id);
  }

  double? minimumFiveMinuteHeartRate() {
    final samples = raw['heart_rate'];
    if (samples is! Map || samples['interval'] != 300) return null;
    final items = samples['items'];
    final sampleStart = _instant(samples['timestamp']);
    if (items is! List || items.length > 300 || sampleStart == null) {
      return null;
    }
    double? minimum;
    for (var index = 0; index < items.length; index++) {
      final time = sampleStart.add(Duration(minutes: 5 * index));
      if (time.isBefore(start) || !time.isBefore(end)) continue;
      final value = OuraData._number(items[index], 20, 250);
      if (value != null && (minimum == null || value < minimum)) {
        minimum = value;
      }
    }
    return minimum;
  }

  static DateTime? _instant(Object? value) {
    if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}
