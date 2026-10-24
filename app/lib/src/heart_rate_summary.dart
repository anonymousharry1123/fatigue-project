import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'heart_derivation_logic.dart';
import 'models.dart';

/// Ordinary HealthKit pulse observations only. HRV, resting HR and manual
/// measurements remain independent inputs and must not be compacted here.
bool isRawHeartRate(SignalReading reading) =>
    reading.type == SignalType.heartRate &&
    reading.source == SignalSource.healthKit;

String rawHeartRateSampleId(SignalReading reading) =>
    reading.id.trim().toLowerCase();

/// Compares the actual complete summary and both sample-set proofs. Import
/// timezone annotations may differ across devices without changing the same
/// physiological observations; they are deliberately excluded.
bool sameHeartRateSummaryStatistics(
  HeartRateDailySummary left,
  HeartRateDailySummary right,
) {
  final leftPayload = left.toJson()..remove('timezoneProvenance');
  final rightPayload = right.toJson()..remove('timezoneProvenance');
  return jsonEncode(leftPayload) == jsonEncode(rightPayload);
}

/// The device timezone at first import, not the unavailable HealthKit recording
/// timezone. Keeping this alongside raw records avoids rewriting provenance
/// when the user travels. Legacy observations explicitly remain unknown.
class HeartRateSampleProvenance {
  const HeartRateSampleProvenance({
    required this.offsetMinutes,
    this.timezoneName,
  });

  final int offsetMinutes;
  final String? timezoneName;

  Map<String, Object?> toJson() => {
    'kind': 'device-local-at-import',
    'offsetMinutes': offsetMinutes,
    if (timezoneName != null) 'timezoneName': timezoneName,
  };

  factory HeartRateSampleProvenance.fromJson(Map<String, dynamic> json) {
    final offset = json['offsetMinutes'];
    final zone = json['timezoneName'];
    if (json['kind'] != 'device-local-at-import' ||
        offset is! int ||
        offset < -840 ||
        offset > 840 ||
        (zone != null && (zone is! String || zone.length > 200))) {
      throw const FormatException('Invalid heart-rate import provenance.');
    }
    return HeartRateSampleProvenance(
      offsetMinutes: offset,
      timezoneName: zone as String?,
    );
  }
}

/// A summary is a complete snapshot of a known set of samples, never a delta.
/// Overlapping summaries from two devices must not be added together. Merge
/// raw UUIDs first, or use a cloud compare-and-replace protocol instead.
abstract final class HeartRateSummary {
  static const schemaVersion = 1;
  static const cardiacContextSchemaVersion = 2;

  static List<SignalReading> uniqueRawReadings(
    Iterable<SignalReading> readings,
  ) {
    final byId = <String, SignalReading>{};
    for (final reading in readings.where(isRawHeartRate)) {
      final id = rawHeartRateSampleId(reading);
      if (id.isEmpty ||
          id.length > 200 ||
          !reading.value.isFinite ||
          reading.value < 20 ||
          reading.value > 300 ||
          !reading.quality.isFinite ||
          reading.quality < 0 ||
          reading.quality > 1) {
        throw const FormatException('Invalid raw heart-rate observation.');
      }
      final old = byId[id];
      if (old == null || _compareRevision(reading, old) > 0) {
        byId[id] = reading;
      }
    }
    return byId.values.toList()..sort(_compareObservation);
  }

  static List<HeartRateDailySummary> build(
    Iterable<SignalReading> readings, {
    Map<String, HeartRateSampleProvenance> sampleProvenance = const {},
  }) {
    final all = readings.toList();
    final byDay = <String, List<SignalReading>>{};
    for (final sample in uniqueRawReadings(all)) {
      byDay.putIfAbsent(dayId(sample.timestamp), () => []).add(sample);
    }
    return [
      for (final entry in byDay.entries)
        HeartRateDailySummary._fromSamples(
          entry.key,
          entry.value,
          sampleProvenance,
          HeartRateCardiacContext._build(
            all.where((item) => dayId(item.timestamp) == entry.key),
            entry.value,
            sampleProvenance,
          ),
        ),
    ];
  }

  static String dayId(DateTime timestamp) =>
      timestamp.toUtc().toIso8601String().substring(0, 10);

  static String sampleIdDigest(Iterable<SignalReading> samples) {
    final ids = samples.map(rawHeartRateSampleId).toSet().toList()..sort();
    return _digest(ids);
  }

  static String contentDigest(Iterable<SignalReading> samples) {
    final sorted = uniqueRawReadings(samples)
      ..sort(
        (a, b) => rawHeartRateSampleId(a).compareTo(rawHeartRateSampleId(b)),
      );
    return _digest(sorted.map(_observationPayload).toList());
  }

  static int _compareRevision(SignalReading a, SignalReading b) {
    // HealthKit IDs normally describe immutable samples. If a legacy payload
    // carries a correction, prefer the newest known revision; ties resolve
    // identically regardless of import order.
    for (final times in [
      (a.recordedAt, b.recordedAt),
      (a.syncedAt, b.syncedAt),
    ]) {
      final difference = (times.$1?.microsecondsSinceEpoch ?? -1).compareTo(
        times.$2?.microsecondsSinceEpoch ?? -1,
      );
      if (difference != 0) return difference;
    }
    return jsonEncode(a.toJson()).compareTo(jsonEncode(b.toJson()));
  }

  static Map<String, Object?> _observationPayload(SignalReading sample) => {
    'id': rawHeartRateSampleId(sample),
    'value': sample.value,
    'timestamp': sample.timestamp.toUtc().toIso8601String(),
    'quality': sample.quality,
    'note': sample.note,
    'groupId': sample.groupId,
  };

  static String _digest(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();

  static String _contextDigest(
    String rawDigest,
    HeartRateCardiacContext context,
  ) => _digest({
    'rawContentDigest': rawDigest,
    'cardiacContext': context.toJson(),
  });
}

/// A descriptive average, kept separate from the exact observations consumed
/// by the model. Native and inferred resting-HR samples never share a mean.
class HeartRateContextMetric {
  const HeartRateContextMetric._({
    required this.mean,
    required this.sampleCount,
    required this.source,
    required this.unit,
  });

  final double mean;
  final int sampleCount;
  final String source;
  final String unit;

  Map<String, Object?> toJson() => {
    'mean': mean,
    'sampleCount': sampleCount,
    'source': source,
    'unit': unit,
  };

  factory HeartRateContextMetric._fromSamples(
    List<SignalReading> samples, {
    required String source,
    required String unit,
  }) => HeartRateContextMetric._(
    mean:
        samples.fold<double>(0, (sum, item) => sum + item.value) /
        samples.length,
    sampleCount: samples.length,
    source: source,
    unit: unit,
  );

  factory HeartRateContextMetric._fromJson(
    Map<String, dynamic> json, {
    required bool hrv,
  }) {
    final mean = _number(json['mean']);
    final count = _integer(json['sampleCount']);
    final source = json['source'];
    if (!_exactKeys(json, {'mean', 'sampleCount', 'source', 'unit'}) ||
        count < 1 ||
        count > 1000000 ||
        mean < (hrv ? double.minPositive : 20) ||
        mean > (hrv ? 1000 : 250) ||
        json['unit'] != (hrv ? 'ms' : 'bpm') ||
        !(hrv ? ['healthKit'] : ['healthKit', 'estimatedFromHeartRate'])
            .contains(source)) {
      throw const FormatException('Invalid daily cardiac metric.');
    }
    return HeartRateContextMetric._(
      mean: mean,
      sampleCount: count,
      source: source as String,
      unit: json['unit'] as String,
    );
  }
}

/// This is bpm variation between sparse samples, never SDNN/RMSSD in ms.
class HeartRateVariationContext {
  const HeartRateVariationContext._({
    required this.rmsSuccessiveDifferenceBpm,
    required this.sampleCount,
    required this.pairCount,
    required this.firstAt,
    required this.latestAt,
  });

  final double rmsSuccessiveDifferenceBpm;
  final int sampleCount;
  final int pairCount;
  final DateTime firstAt;
  final DateTime latestAt;

  Map<String, Object?> toJson() => {
    'rmsSuccessiveDifferenceBpm': rmsSuccessiveDifferenceBpm,
    'sampleCount': sampleCount,
    'pairCount': pairCount,
    'firstAt': firstAt.toUtc().toIso8601String(),
    'latestAt': latestAt.toUtc().toIso8601String(),
    'source': 'healthKit',
    'unit': 'bpm',
    'method': 'sampled-bpm-successive-difference-v1',
    'timezoneBasis': 'device-local-at-import',
  };

  factory HeartRateVariationContext._fromJson(
    Map<String, dynamic> json,
    String day,
  ) {
    final value = _number(json['rmsSuccessiveDifferenceBpm']);
    final samples = _integer(json['sampleCount']);
    final pairs = _integer(json['pairCount']);
    final first = _time(json['firstAt']);
    final latest = _time(json['latestAt']);
    if (!_exactKeys(json, {
          'rmsSuccessiveDifferenceBpm',
          'sampleCount',
          'pairCount',
          'firstAt',
          'latestAt',
          'source',
          'unit',
          'method',
          'timezoneBasis',
        }) ||
        value < 0 ||
        value > 280 ||
        samples < HeartDerivationLogic.minimumVariationSamples ||
        samples > 1000000 ||
        pairs < HeartDerivationLogic.minimumVariationSamples - 1 ||
        pairs >= samples ||
        HeartRateSummary.dayId(first) != day ||
        HeartRateSummary.dayId(latest) != day ||
        latest.difference(first) < HeartDerivationLogic.minimumVariationSpan ||
        json['source'] != 'healthKit' ||
        json['unit'] != 'bpm' ||
        json['method'] != 'sampled-bpm-successive-difference-v1' ||
        json['timezoneBasis'] != 'device-local-at-import') {
      throw const FormatException(
        'Invalid daily sampled heart-rate variation.',
      );
    }
    return HeartRateVariationContext._(
      rmsSuccessiveDifferenceBpm: value,
      sampleCount: samples,
      pairCount: pairs,
      firstAt: first,
      latestAt: latest,
    );
  }
}

class HeartRateCardiacContext {
  const HeartRateCardiacContext._({
    this.hrv,
    this.restingHeartRate,
    this.variation,
  });

  final HeartRateContextMetric? hrv;
  final HeartRateContextMetric? restingHeartRate;
  final HeartRateVariationContext? variation;

  Map<String, Object?> toJson() => {
    if (hrv != null) 'hrv': hrv!.toJson(),
    if (restingHeartRate != null)
      'restingHeartRate': restingHeartRate!.toJson(),
    if (variation != null) 'sampledHeartRateVariation': variation!.toJson(),
  };

  static HeartRateCardiacContext? _build(
    Iterable<SignalReading> readings,
    List<SignalReading> rawSamples,
    Map<String, HeartRateSampleProvenance> provenance,
  ) {
    final unique = <String, SignalReading>{};
    for (final reading in readings) {
      final id = rawHeartRateSampleId(reading);
      if (id.isEmpty ||
          !reading.quality.isFinite ||
          reading.quality <= 0 ||
          reading.quality > 1 ||
          !reading.value.isFinite) {
        continue;
      }
      final old = unique[id];
      if (old == null || HeartRateSummary._compareRevision(reading, old) > 0) {
        unique[id] = reading;
      }
    }
    final ordered = unique.values.toList()..sort(_compareObservation);
    final hrv = ordered
        .where(
          (reading) =>
              reading.type == SignalType.hrv &&
              reading.source == SignalSource.healthKit &&
              reading.value > 0 &&
              reading.value <= 1000,
        )
        .toList();
    final resting = ordered
        .where(
          (reading) =>
              reading.type == SignalType.restingHeartRate &&
              reading.source == SignalSource.healthKit &&
              reading.value >= 20 &&
              reading.value <= 250,
        )
        .toList();
    final estimated = ordered
        .where(
          (reading) =>
              HeartDerivationLogic.isEstimatedRestingHeartRate(reading) &&
              reading.quality <= HeartDerivationLogic.maximumEstimateQuality &&
              reading.value >= 20 &&
              reading.value <= 250,
        )
        .toList();
    final restingSamples = resting.isNotEmpty ? resting : estimated;

    // This summary describes committed observations. Strip import/save times
    // only from this temporary projection, so historical import churn cannot
    // change the descriptive statistic. Model as-of inputs remain untouched.
    final knownTimezoneSamples = rawSamples
        .where((sample) => provenance.containsKey(rawHeartRateSampleId(sample)))
        .map(
          (sample) => SignalReading(
            id: sample.id,
            type: sample.type,
            value: sample.value,
            timestamp: sample.timestamp,
            source: sample.source,
            quality: sample.quality,
          ),
        );
    final variation = HeartDerivationLogic.sampledHeartRateVariation(
      knownTimezoneSamples,
      now: rawSamples.last.timestamp,
      localTimestamp: (sample) => sample.timestamp.toUtc().add(
        Duration(
          minutes: provenance[rawHeartRateSampleId(sample)]!.offsetMinutes,
        ),
      ),
    );
    if (hrv.isEmpty && restingSamples.isEmpty && variation == null) return null;
    return HeartRateCardiacContext._(
      hrv: hrv.isEmpty
          ? null
          : HeartRateContextMetric._fromSamples(
              hrv,
              source: 'healthKit',
              unit: 'ms',
            ),
      restingHeartRate: restingSamples.isEmpty
          ? null
          : HeartRateContextMetric._fromSamples(
              restingSamples,
              source: resting.isNotEmpty
                  ? 'healthKit'
                  : 'estimatedFromHeartRate',
              unit: 'bpm',
            ),
      variation: variation == null
          ? null
          : HeartRateVariationContext._(
              rmsSuccessiveDifferenceBpm: variation.rmsSuccessiveDifferenceBpm,
              sampleCount: variation.sampleCount,
              pairCount: variation.pairCount,
              firstAt: variation.start.toUtc(),
              latestAt: variation.end.toUtc(),
            ),
    );
  }

  factory HeartRateCardiacContext._fromJson(
    Map<String, dynamic> json,
    String day,
  ) {
    if (json.isEmpty ||
        !json.keys.every(
          {'hrv', 'restingHeartRate', 'sampledHeartRateVariation'}.contains,
        )) {
      throw const FormatException('Invalid daily cardiac context.');
    }
    Map<String, dynamic> metric(String key) {
      final value = json[key];
      if (value is! Map) {
        throw const FormatException('Invalid daily cardiac context metric.');
      }
      return Map<String, dynamic>.from(value);
    }

    return HeartRateCardiacContext._(
      hrv: json.containsKey('hrv')
          ? HeartRateContextMetric._fromJson(metric('hrv'), hrv: true)
          : null,
      restingHeartRate: json.containsKey('restingHeartRate')
          ? HeartRateContextMetric._fromJson(
              metric('restingHeartRate'),
              hrv: false,
            )
          : null,
      variation: json.containsKey('sampledHeartRateVariation')
          ? HeartRateVariationContext._fromJson(
              metric('sampledHeartRateVariation'),
              day,
            )
          : null,
    );
  }
}

class HeartRateAggregate {
  const HeartRateAggregate({
    required this.count,
    required this.sum,
    required this.min,
    required this.max,
    required this.firstAt,
    required this.latestAt,
    required this.latestValue,
    required this.qualitySum,
    required this.qualityMin,
    required this.zeroQualityCount,
  });

  final int count;
  final double sum;
  final double min;
  final double max;
  final DateTime firstAt;
  final DateTime latestAt;
  final double latestValue;

  /// Zero-quality observations remain counted for faithful history. The
  /// quality fields make that explicit; this summary is not a scored input.
  final double qualitySum;
  final double qualityMin;
  final int zeroQualityCount;

  double get mean => sum / count;

  factory HeartRateAggregate._fromSamples(List<SignalReading> samples) {
    final sorted = [...samples]..sort(_compareObservation);
    final first = sorted.first;
    var sum = 0.0;
    var min = first.value;
    var max = first.value;
    var qualitySum = 0.0;
    var qualityMin = first.quality;
    var zeroQualityCount = 0;
    for (final sample in sorted) {
      sum += sample.value;
      if (sample.value < min) min = sample.value;
      if (sample.value > max) max = sample.value;
      qualitySum += sample.quality;
      if (sample.quality < qualityMin) qualityMin = sample.quality;
      if (sample.quality == 0) zeroQualityCount += 1;
    }
    return HeartRateAggregate(
      count: sorted.length,
      sum: sum,
      min: min,
      max: max,
      firstAt: first.timestamp.toUtc(),
      latestAt: sorted.last.timestamp.toUtc(),
      latestValue: sorted.last.value,
      qualitySum: qualitySum,
      qualityMin: qualityMin,
      zeroQualityCount: zeroQualityCount,
    );
  }

  Map<String, Object?> toJson({String countKey = 'count'}) => {
    countKey: count,
    'sum': sum,
    'min': min,
    'max': max,
    'firstAt': firstAt.toUtc().toIso8601String(),
    'latestAt': latestAt.toUtc().toIso8601String(),
    'latestValue': latestValue,
    'qualitySum': qualitySum,
    'qualityMin': qualityMin,
    'zeroQualityCount': zeroQualityCount,
  };

  factory HeartRateAggregate.fromJson(
    Map<String, dynamic> json, {
    String countKey = 'count',
  }) {
    final count = _integer(json[countKey]);
    final sum = _number(json['sum']);
    final min = _number(json['min']);
    final max = _number(json['max']);
    final firstAt = _time(json['firstAt']);
    final latestAt = _time(json['latestAt']);
    final latestValue = _number(json['latestValue']);
    final qualitySum = _number(json['qualitySum']);
    final qualityMin = _number(json['qualityMin']);
    final zeroCount = _integer(json['zeroQualityCount']);
    if (count < 1 ||
        min < 20 ||
        max > 300 ||
        min > max ||
        latestValue < min ||
        latestValue > max ||
        sum < min * count - .000001 ||
        sum > max * count + .000001 ||
        latestAt.isBefore(firstAt) ||
        qualitySum < 0 ||
        qualitySum > count ||
        qualityMin < 0 ||
        qualityMin > 1 ||
        zeroCount < 0 ||
        zeroCount > count) {
      throw const FormatException('Invalid heart-rate aggregate.');
    }
    return HeartRateAggregate(
      count: count,
      sum: sum,
      min: min,
      max: max,
      firstAt: firstAt,
      latestAt: latestAt,
      latestValue: latestValue,
      qualitySum: qualitySum,
      qualityMin: qualityMin,
      zeroQualityCount: zeroCount,
    );
  }
}

class HeartRateHourSummary {
  const HeartRateHourSummary({required this.hour, required this.aggregate});
  final int hour;
  final HeartRateAggregate aggregate;

  int get count => aggregate.count;
  double get sum => aggregate.sum;
  double get min => aggregate.min;
  double get max => aggregate.max;
  DateTime get latestAt => aggregate.latestAt;
  double get latestValue => aggregate.latestValue;

  Map<String, Object?> toJson() => {'hour': hour, ...aggregate.toJson()};
}

class HeartRateDailySummary {
  const HeartRateDailySummary._({
    required this.day,
    required this.aggregate,
    required this.sampleIdDigest,
    required this.contentDigest,
    required this.rawContentDigest,
    required this.hours,
    required this.timezoneProvenance,
    this.cardiacContext,
  });

  final String day;
  final HeartRateAggregate aggregate;
  final String sampleIdDigest;
  final String contentDigest;
  final String rawContentDigest;
  final HeartRateCardiacContext? cardiacContext;
  final List<HeartRateHourSummary> hours;
  final Map<String, Object?> timezoneProvenance;

  String get id => day;
  int get schemaVersion => cardiacContext == null
      ? HeartRateSummary.schemaVersion
      : HeartRateSummary.cardiacContextSchemaVersion;
  int get sampleCount => aggregate.count;
  DateTime get firstAt => aggregate.firstAt;
  DateTime get latestAt => aggregate.latestAt;
  double get latestValue => aggregate.latestValue;
  double get sum => aggregate.sum;
  double get min => aggregate.min;
  double get max => aggregate.max;
  double get mean => aggregate.mean;

  factory HeartRateDailySummary._fromSamples(
    String day,
    List<SignalReading> samples,
    Map<String, HeartRateSampleProvenance> provenance,
    HeartRateCardiacContext? cardiacContext,
  ) {
    final byHour = <int, List<SignalReading>>{};
    final zones = <String>{};
    final offsets = <int>{};
    var unknown = 0;
    for (final sample in samples) {
      byHour.putIfAbsent(sample.timestamp.toUtc().hour, () => []).add(sample);
      final origin = provenance[rawHeartRateSampleId(sample)];
      if (origin == null) {
        unknown += 1;
      } else {
        offsets.add(origin.offsetMinutes);
        if (origin.timezoneName != null) zones.add(origin.timezoneName!);
      }
    }
    final rawDigest = HeartRateSummary.contentDigest(samples);
    return HeartRateDailySummary._(
      day: day,
      aggregate: HeartRateAggregate._fromSamples(samples),
      sampleIdDigest: HeartRateSummary.sampleIdDigest(samples),
      contentDigest: cardiacContext == null
          ? rawDigest
          : HeartRateSummary._contextDigest(rawDigest, cardiacContext),
      rawContentDigest: rawDigest,
      cardiacContext: cardiacContext,
      hours: List.unmodifiable([
        for (final entry in byHour.entries)
          HeartRateHourSummary(
            hour: entry.key,
            aggregate: HeartRateAggregate._fromSamples(entry.value),
          ),
      ]),
      timezoneProvenance: Map.unmodifiable({
        'kind': unknown == samples.length
            ? 'unknown'
            : 'device-local-at-import',
        'zoneNames': zones.toList()..sort(),
        'offsetMinutes': offsets.toList()..sort(),
        'unknownSampleCount': unknown,
      }),
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'aggregation': 'utc-day-v1',
    'day': day,
    'source': 'healthKit',
    ...aggregate.toJson(countKey: 'sampleCount'),
    'sampleIdDigest': sampleIdDigest,
    'contentDigest': contentDigest,
    if (cardiacContext != null) ...{
      'rawContentDigest': rawContentDigest,
      'cardiacContext': cardiacContext!.toJson(),
    },
    'hours': hours.map((hour) => hour.toJson()).toList(),
    'timezoneProvenance': timezoneProvenance,
  };

  factory HeartRateDailySummary.fromJson(Map<String, dynamic> json) {
    final day = json['day'];
    final sampleDigest = json['sampleIdDigest'];
    final contentDigest = json['contentDigest'];
    final version = json['schemaVersion'];
    final aggregate = HeartRateAggregate.fromJson(
      json,
      countKey: 'sampleCount',
    );
    if (![
          HeartRateSummary.schemaVersion,
          HeartRateSummary.cardiacContextSchemaVersion,
        ].contains(version) ||
        json['aggregation'] != 'utc-day-v1' ||
        json['source'] != 'healthKit' ||
        day is! String ||
        day != HeartRateSummary.dayId(aggregate.firstAt) ||
        day != HeartRateSummary.dayId(aggregate.latestAt) ||
        !_isDigest(sampleDigest) ||
        !_isDigest(contentDigest)) {
      throw const FormatException('Invalid daily heart-rate summary.');
    }
    HeartRateCardiacContext? context;
    var rawContentDigest = contentDigest as String;
    if (version == HeartRateSummary.cardiacContextSchemaVersion) {
      final rawContext = json['cardiacContext'];
      final rawDigest = json['rawContentDigest'];
      if (rawContext is! Map || !_isDigest(rawDigest)) {
        throw const FormatException('Missing daily cardiac context proof.');
      }
      context = HeartRateCardiacContext._fromJson(
        Map<String, dynamic>.from(rawContext),
        day,
      );
      rawContentDigest = rawDigest as String;
      final variation = context.variation;
      if (HeartRateSummary._contextDigest(rawContentDigest, context) !=
              contentDigest ||
          (variation != null &&
              (variation.sampleCount > aggregate.count ||
                  variation.firstAt.isBefore(aggregate.firstAt) ||
                  variation.latestAt.isAfter(aggregate.latestAt)))) {
        throw const FormatException(
          'Daily cardiac context digest does not match.',
        );
      }
    } else if (json.containsKey('cardiacContext') ||
        json.containsKey('rawContentDigest')) {
      throw const FormatException(
        'Cardiac context requires a version 2 summary.',
      );
    }
    final rawHours = json['hours'];
    if (rawHours is! List || rawHours.isEmpty || rawHours.length > 24) {
      throw const FormatException('Invalid hourly heart-rate summaries.');
    }
    final hours = <HeartRateHourSummary>[];
    for (final raw in rawHours) {
      final data = Map<String, dynamic>.from(raw as Map);
      final hour = _integer(data['hour']);
      final value = HeartRateAggregate.fromJson(data);
      if (hour < 0 ||
          hour > 23 ||
          (hours.isNotEmpty && hour <= hours.last.hour) ||
          value.firstAt.hour != hour ||
          value.latestAt.hour != hour ||
          HeartRateSummary.dayId(value.firstAt) != day ||
          HeartRateSummary.dayId(value.latestAt) != day) {
        throw const FormatException('Invalid hourly heart-rate summary.');
      }
      hours.add(HeartRateHourSummary(hour: hour, aggregate: value));
    }
    if (hours.fold<int>(0, (total, h) => total + h.count) != aggregate.count ||
        (hours.fold<double>(0, (total, h) => total + h.sum) - aggregate.sum)
                .abs() >
            .000001 ||
        hours.map((h) => h.min).reduce((a, b) => a < b ? a : b) !=
            aggregate.min ||
        hours.map((h) => h.max).reduce((a, b) => a > b ? a : b) !=
            aggregate.max ||
        hours.first.aggregate.firstAt != aggregate.firstAt ||
        hours.last.latestAt != aggregate.latestAt ||
        hours.last.latestValue != aggregate.latestValue ||
        (hours.fold<double>(0, (total, h) => total + h.aggregate.qualitySum) -
                    aggregate.qualitySum)
                .abs() >
            .000001 ||
        hours
                .map((h) => h.aggregate.qualityMin)
                .reduce((a, b) => a < b ? a : b) !=
            aggregate.qualityMin ||
        hours.fold<int>(
              0,
              (total, h) => total + h.aggregate.zeroQualityCount,
            ) !=
            aggregate.zeroQualityCount) {
      throw const FormatException('Inconsistent heart-rate totals.');
    }
    final provenance = Map<String, Object?>.from(
      json['timezoneProvenance'] as Map,
    );
    final unknown = provenance['unknownSampleCount'];
    final zones = provenance['zoneNames'];
    final offsets = provenance['offsetMinutes'];
    if (!['unknown', 'device-local-at-import'].contains(provenance['kind']) ||
        unknown is! int ||
        unknown < 0 ||
        unknown > aggregate.count ||
        zones is! List ||
        zones.any((z) => z is! String || z.length > 200) ||
        offsets is! List ||
        offsets.any((o) => o is! int || o < -840 || o > 840)) {
      throw const FormatException('Invalid heart-rate timezone provenance.');
    }
    return HeartRateDailySummary._(
      day: day,
      aggregate: aggregate,
      sampleIdDigest: sampleDigest as String,
      contentDigest: contentDigest,
      rawContentDigest: rawContentDigest,
      cardiacContext: context,
      hours: List.unmodifiable(hours),
      timezoneProvenance: Map.unmodifiable(provenance),
    );
  }
}

int _compareObservation(SignalReading a, SignalReading b) {
  final time = a.timestamp.compareTo(b.timestamp);
  return time != 0
      ? time
      : rawHeartRateSampleId(a).compareTo(rawHeartRateSampleId(b));
}

bool _isDigest(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

bool _exactKeys(Map<String, dynamic> json, Set<String> keys) =>
    json.length == keys.length && json.keys.every(keys.contains);

double _number(Object? value) {
  if (value is! num || !value.isFinite) {
    throw const FormatException('Invalid heart-rate summary number.');
  }
  return value.toDouble();
}

int _integer(Object? value) {
  if (value is! int) {
    throw const FormatException('Invalid heart-rate summary count.');
  }
  return value;
}

DateTime _time(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null || !parsed.isUtc || !value.toString().endsWith('Z')) {
    throw const FormatException('Invalid heart-rate summary time.');
  }
  return parsed;
}
