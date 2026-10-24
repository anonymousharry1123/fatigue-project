import 'cloud_schema.dart';
import 'cloud_sync.dart';
import 'local_day.dart';
import 'models.dart';

/// One calendar day's derived forecast. The point payload stays lossless so
/// evidence, model versions, uncertainty, and generation times survive restore.
Map<String, dynamic> forecastDayToCloud(
  DateTime day,
  List<ForecastPoint> points,
) {
  final start = localDay(day);
  final end = localDay(start, 1);
  if (points.any(
    (point) => point.time.isBefore(start) || !point.time.isBefore(end),
  )) {
    throw ArgumentError('Every forecast point must belong to the target day.');
  }
  final ordered = [...points]..sort((a, b) => a.time.compareTo(b.time));
  if (ordered.map((point) => point.time.toUtc()).toSet().length !=
      ordered.length) {
    throw ArgumentError('A forecast day cannot contain duplicate instants.');
  }
  return {
    'formatVersion': 1,
    'localDate': localDayKey(start),
    'day': start,
    'dayEnd': end,
    'utcOffsetMinutes': start.timeZoneOffset.inMinutes,
    'points': [for (final point in ordered) forecastPointToCloud(point)],
  };
}

List<ForecastPoint> forecastDayFromCloud(Map<String, dynamic> data) {
  if (data['formatVersion'] != 1 || data['points'] is! List) {
    throw const FormatException('Unsupported forecast day format.');
  }
  final start = cloudDateTime(data['day'], field: 'day');
  final end = cloudDateTime(data['dayEnd'], field: 'dayEnd');
  if (!end.isAfter(start)) {
    throw const FormatException('Forecast day end must follow its start.');
  }
  final points =
      (data['points'] as List)
          .map(
            (value) =>
                forecastPointFromCloud(Map<String, dynamic>.from(value as Map)),
          )
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));
  if (points.any(
        (point) => point.time.isBefore(start) || !point.time.isBefore(end),
      ) ||
      points.map((point) => point.time.toUtc()).toSet().length !=
          points.length) {
    throw const FormatException('Invalid forecast day point range.');
  }
  return points;
}

/// Generation time alone does not justify rewriting otherwise identical
/// derived data. Keep the acknowledged cloud generation time in that case.
bool sameForecastDayContent(
  Map<String, dynamic> left,
  Map<String, dynamic> right,
) {
  Map<String, dynamic> semantic(Map<String, dynamic> data) => {
    ...data,
    'points': [
      for (final point in (data['points'] as List))
        {...Map<String, dynamic>.from(point as Map)}..remove('updatedAt'),
    ],
  };
  return sameSyncValue(semantic(left), semantic(right));
}

typedef ForecastDayRangeLoader =
    Future<Map<String, Map<String, dynamic>>> Function(
      String uid,
      String firstDate,
      String lastDate,
    );
typedef ForecastDayLoader =
    Future<Map<String, dynamic>?> Function(String uid, String id);
typedef ForecastLegacyLoader =
    Future<List<ForecastPoint>> Function(
      String uid,
      DateTime start,
      DateTime end,
    );
typedef ForecastDayWriter =
    Future<void> Function(String uid, String id, Map<String, dynamic> data);

/// Coordinates the lazy migration from hourly documents. A persisted empty
/// day is intentional: it prevents repeatedly querying an absent legacy day.
/// Legacy documents are retained for rollback/export, never deleted here.
class ForecastDayStore {
  ForecastDayStore({
    required this.loadDays,
    required this.loadDay,
    required this.loadLegacy,
    required this.writeDay,
  });

  final ForecastDayRangeLoader loadDays;
  final ForecastDayLoader loadDay;
  final ForecastLegacyLoader loadLegacy;
  final ForecastDayWriter writeDay;
  final Map<String, Map<String, Map<String, dynamic>>> _known = {};
  final Map<String, int> _ownerGenerations = {};

  void clearOwner(String uid) {
    _known.remove(uid);
    _ownerGenerations[uid] = (_ownerGenerations[uid] ?? 0) + 1;
  }

  void _requireGeneration(String uid, int generation) {
    if ((_ownerGenerations[uid] ?? 0) != generation) {
      throw StateError('Forecast owner cache reset during cloud operation.');
    }
  }

  Future<List<ForecastPoint>> readRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) async {
    if (!end.isAfter(start)) {
      throw ArgumentError('Forecast range end must follow start.');
    }
    final generation = _ownerGenerations[uid] ?? 0;
    final firstDay = localDay(start);
    final lastDay = localDay(end.subtract(const Duration(microseconds: 1)));
    // Two adjacent date keys cover travel across the date line (device zones
    // can differ by up to 28 hours). Filter exact instants, not 24-hour days.
    final loaded = await loadDays(
      uid,
      localDayKey(localDay(firstDay, -2)),
      localDayKey(localDay(lastDay, 2)),
    );
    _requireGeneration(uid, generation);
    final known = _known.putIfAbsent(uid, () => {});
    final allPoints = <DateTime, ForecastPoint>{};
    for (final entry in loaded.entries) {
      final points = forecastDayFromCloud(entry.value);
      known[entry.key] = entry.value;
      for (final point in points) {
        allPoints[point.time.toUtc()] = point;
      }
    }

    final missing = <DateTime>[];
    for (var day = firstDay; !day.isAfter(lastDay); day = localDay(day, 1)) {
      if (!loaded.containsKey(localDayKey(day))) missing.add(day);
    }
    // Coalesce consecutive missing days so a first upgrade needs one legacy
    // range query, rather than one query per day or an unbounded collection read.
    for (var index = 0; index < missing.length;) {
      var next = index + 1;
      while (next < missing.length &&
          missing[next] == localDay(missing[next - 1], 1)) {
        next++;
      }
      final legacy = await loadLegacy(
        uid,
        missing[index],
        localDay(missing[next - 1], 1),
      );
      _requireGeneration(uid, generation);
      for (var dayIndex = index; dayIndex < next; dayIndex++) {
        final day = missing[dayIndex];
        final dayEnd = localDay(day, 1);
        final points = legacy
            .where(
              (point) =>
                  !point.time.isBefore(day) && point.time.isBefore(dayEnd),
            )
            .toList();
        final id = localDayKey(day);
        final data = forecastDayToCloud(day, points);
        await writeDay(uid, id, data);
        _requireGeneration(uid, generation);
        known[id] = data;
        for (final point in points) {
          allPoints[point.time.toUtc()] = point;
        }
      }
      index = next;
    }
    return allPoints.values
        .where(
          (point) => !point.time.isBefore(start) && point.time.isBefore(end),
        )
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  Future<void> replaceDay(
    String uid, {
    required DateTime day,
    required List<ForecastPoint> points,
  }) async {
    final generation = _ownerGenerations[uid] ?? 0;
    final desired = forecastDayToCloud(day, points);
    final id = localDayKey(day);
    final known = _known.putIfAbsent(uid, () => {});
    final existing = known[id] ?? await loadDay(uid, id);
    _requireGeneration(uid, generation);
    if (existing != null) {
      // Validate a cached/server document before treating it as authoritative.
      forecastDayFromCloud(existing);
      if (sameForecastDayContent(existing, desired)) {
        known[id] = existing;
        return;
      }
    }
    await writeDay(uid, id, desired);
    _requireGeneration(uid, generation);
    known[id] = desired;
  }
}
