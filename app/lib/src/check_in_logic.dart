import 'models.dart';

/// Pure helpers for Version 0.8 mood / stress check-ins (1–10 scale).
abstract final class CheckInLogic {
  static const minRating = 1.0;
  static const maxRating = 10.0;

  static bool isValidRating(double value) =>
      value >= minRating && value <= maxRating;

  static double clampRating(double value) =>
      value.clamp(minRating, maxRating).toDouble();

  /// Morning before 14:00 local time; evening at/after 14:00.
  static CheckInPeriod periodFor([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    return hour < 14 ? CheckInPeriod.morning : CheckInPeriod.evening;
  }

  static String energyBadge(double value) {
    if (value >= 8) return 'Strong';
    if (value >= 5) return 'Steady';
    return 'Low';
  }

  static String moodBadge(double value) {
    if (value >= 8) return 'Great';
    if (value >= 5) return 'Okay';
    return 'Low';
  }

  static String stressBadge(double value) {
    if (value >= 8) return 'High';
    if (value >= 5) return 'Moderate';
    return 'Calm';
  }

  static List<DailyCheckIn> historyForDay(
    List<DailyCheckIn> checkIns,
    DateTime day,
  ) {
    return checkIns
        .where(
          (item) =>
              item.timestamp.year == day.year &&
              item.timestamp.month == day.month &&
              item.timestamp.day == day.day,
        )
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  static List<DailyCheckIn> recentHistory(
    List<DailyCheckIn> checkIns, {
    int limit = 8,
  }) {
    final sorted = checkIns.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(limit).toList();
  }
}
