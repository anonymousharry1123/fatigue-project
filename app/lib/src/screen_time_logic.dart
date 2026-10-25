import 'models.dart';
import 'screen_time_service.dart';

/// Manual corrections take priority on the same local calendar day. Apple's
/// authorized daily totals replace previous snapshots rather than adding up.
class ScreenTimeLogic {
  const ScreenTimeLogic._();

  static List<SignalReading> modelReadings(Iterable<SignalReading> readings) {
    final screenReadings = readings
        .where((item) => item.type == SignalType.screenTime)
        .toList();
    final manualDays = screenReadings
        .where((item) => item.source == SignalSource.manual)
        .map((item) => dayKey(item.timestamp))
        .toSet();
    final measured = screenReadings
        .where((item) => item.source != SignalSource.model)
        .where(
          (item) =>
              item.source == SignalSource.manual ||
              !manualDays.contains(dayKey(item.timestamp)),
        )
        .toList();
    return measured.isNotEmpty ? measured : screenReadings;
  }

  static String dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static List<SignalReading> merge({
    required List<SignalReading> existing,
    required List<ScreenTimeDailyTotal> totals,
    required DateTime now,
  }) {
    final result = [...existing];
    for (final total in totals) {
      final day = total.day;
      final end = DateTime(day.year, day.month, day.day + 1);
      if (day.isAfter(now) ||
          total.updatedAt.isAfter(now) ||
          total.updatedAt.isBefore(day) ||
          !total.seconds.isFinite ||
          total.seconds < 0 ||
          total.seconds > end.difference(day).inSeconds) {
        continue;
      }
      final id = 'apple-screen-time-${dayKey(day)}';
      final index = result.indexWhere((item) => item.id == id);
      final value = total.seconds / 3600;
      if (index >= 0 && total.updatedAt.isBefore(result[index].timestamp)) {
        continue;
      }
      // Unchanged totals generate neither new signals nor cloud writes.
      if (index >= 0 && result[index].value == value) continue;
      final timestamp = total.updatedAt.isBefore(end)
          ? total.updatedAt
          : end.subtract(const Duration(microseconds: 1));
      final reading = SignalReading(
        id: id,
        type: SignalType.screenTime,
        value: value,
        timestamp: timestamp,
        source: SignalSource.appleScreenTime,
        syncedAt: now,
        note: 'Apple Screen Time daily total',
      );
      if (index >= 0) {
        result[index] = reading;
      } else {
        result.add(reading);
      }
    }
    return result;
  }
}
