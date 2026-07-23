import 'models.dart';

/// Helpers for activity-log entry defaults and last-week category charts.
abstract final class ActivityLogLogic {
  static const categories = <SignalType>[
    SignalType.hydration,
    SignalType.study,
    SignalType.exercise,
    SignalType.screenTime,
  ];

  /// Blank / omitted fields become 0.
  static double valueOrZero(double? value) => value ?? 0;

  static bool hasAnyLoggedValue({
    required double hydrationLiters,
    required double studyHours,
    required double exerciseHours,
    required double screenTimeHours,
  }) =>
      hydrationLiters > 0 ||
      studyHours > 0 ||
      exerciseHours > 0 ||
      screenTimeHours > 0;

  static double valueFor(ActivityLogEntry entry, SignalType type) =>
      switch (type) {
        SignalType.hydration => entry.hydrationLiters ?? 0,
        SignalType.study => entry.studyHours ?? 0,
        SignalType.exercise => entry.exerciseHours ?? 0,
        SignalType.screenTime => entry.screenTimeHours ?? 0,
        _ => 0,
      };

  static String categoryTitle(SignalType type) => switch (type) {
    SignalType.hydration => 'Hydration',
    SignalType.study => 'Study',
    SignalType.exercise => 'Exercise',
    SignalType.screenTime => 'Screen time',
    _ => type.label,
  };

  static String categoryUnit(SignalType type) => switch (type) {
    SignalType.hydration => 'L',
    SignalType.study ||
    SignalType.exercise ||
    SignalType.screenTime => 'hr',
    _ => type.unit,
  };

  /// One series per category for the last [days] calendar days (oldest → newest).
  static List<CategoryWeekSeries> weekByCategory(
    List<ActivityLogEntry> logs, {
    DateTime? now,
    int days = 7,
  }) {
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final dayStarts = List.generate(
      days,
      (index) => today.subtract(Duration(days: days - 1 - index)),
    );

    double dayValue(DateTime day, SignalType type) {
      final matches = logs.where(
        (log) =>
            log.timestamp.year == day.year &&
            log.timestamp.month == day.month &&
            log.timestamp.day == day.day,
      );
      if (matches.isEmpty) return 0;
      return matches
          .map((log) => valueFor(log, type))
          .fold<double>(0, (sum, value) => sum + value);
    }

    return categories.map((type) {
      final values = dayStarts.map((day) => dayValue(day, type)).toList();
      var peakIndex = 0;
      for (var i = 1; i < values.length; i++) {
        if (values[i] > values[peakIndex]) peakIndex = i;
      }
      return CategoryWeekSeries(
        type: type,
        days: dayStarts,
        values: values,
        peakDayIndex: peakIndex,
      );
    }).toList();
  }
}

class CategoryWeekSeries {
  const CategoryWeekSeries({
    required this.type,
    required this.days,
    required this.values,
    required this.peakDayIndex,
  });

  final SignalType type;
  final List<DateTime> days;
  final List<double> values;
  final int peakDayIndex;

  double get peakValue => values.isEmpty ? 0 : values[peakDayIndex];
  DateTime get peakDay => days[peakDayIndex];
  bool get hasData => values.any((value) => value > 0);
}
