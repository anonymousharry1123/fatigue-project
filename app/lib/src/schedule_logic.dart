import 'local_day.dart';
import 'models.dart';

/// Saved local-clock scheduling preferences, not observed sleep duration.
abstract final class ScheduleLogic {
  static bool validHours(double wakeHour, double bedHour) =>
      wakeHour.isFinite &&
      bedHour.isFinite &&
      wakeHour >= 0 &&
      wakeHour < 24 &&
      bedHour >= 0 &&
      bedHour < 24 &&
      wakeHour != bedHour;

  static double sleepOpportunity(double wakeHour, double bedHour) =>
      (wakeHour - bedHour + 24) % 24;

  static String? validationError(UserProfile previous, UserProfile proposed) {
    if (!validHours(proposed.wakeHour, proposed.bedHour)) {
      return 'Choose different wake and bed times between 00:00 and 23:59.';
    }
    return null;
  }

  static ({DateTime wake, DateTime bed})? wakingWindow(
    DateTime day,
    UserProfile profile,
  ) {
    if (!validHours(profile.wakeHour, profile.bedHour)) return null;
    final date = localDay(day);
    final wake = atHour(date, profile.wakeHour);
    var bed = atHour(date, profile.bedHour);
    if (!bed.isAfter(wake)) bed = atHour(localDay(date, 1), profile.bedHour);
    return (wake: wake, bed: bed);
  }

  // Construct local clock times instead of adding 24 elapsed hours over DST.
  static DateTime atHour(DateTime day, double hour) =>
      DateTime(day.year, day.month, day.day, 0, (hour * 60).round());
}
