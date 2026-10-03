import 'models.dart';
import 'local_day.dart';

/// Helpers for activity-log entry defaults and last-week category charts.
abstract final class ActivityLogLogic {
  static const categories = <SignalType>[
    SignalType.hydration,
    SignalType.study,
    SignalType.exercise,
    SignalType.screenTime,
  ];

  /// Chart arithmetic only; storage and editing must keep null distinct from 0.
  static double valueOrZero(double? value) => value ?? 0;

  static bool hasAnyLoggedValue({
    double? hydrationLiters,
    double? studyHours,
    double? exerciseHours,
    double? screenTimeHours,
  }) =>
      hydrationLiters != null ||
      studyHours != null ||
      exerciseHours != null ||
      screenTimeHours != null;

  static double? observationFor(ActivityLogEntry entry, SignalType type) =>
      switch (type) {
        SignalType.hydration => entry.hydrationLiters,
        SignalType.study => entry.studyHours,
        SignalType.exercise => entry.exerciseHours,
        SignalType.screenTime => entry.screenTimeHours,
        _ => null,
      };

  static double valueFor(ActivityLogEntry entry, SignalType type) =>
      observationFor(entry, type) ?? 0;

  static String categoryTitle(SignalType type) => switch (type) {
    SignalType.hydration => 'Hydration',
    SignalType.study => 'Study',
    SignalType.exercise => 'Exercise',
    SignalType.screenTime => 'Screen time',
    _ => type.label,
  };

  static String categoryUnit(SignalType type) => switch (type) {
    SignalType.hydration => 'L',
    SignalType.study || SignalType.exercise || SignalType.screenTime => 'hr',
    _ => type.unit,
  };

  /// One series per category for the last [days] calendar days (oldest → newest).
  static List<CategoryWeekSeries> weekByCategory(
    List<ActivityLogEntry> logs, {
    DateTime? now,
    int days = 7,
  }) {
    final clock = now ?? DateTime.now();
    final today = localDay(clock);
    final dayStarts = List.generate(
      days,
      (index) => localDay(today, -(days - 1 - index)),
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
      final observed = dayStarts
          .map(
            (day) => logs.any(
              (log) =>
                  sameLocalDay(log.timestamp, day) &&
                  observationFor(log, type) != null,
            ),
          )
          .toList();
      var peakIndex = observed.indexOf(true);
      if (peakIndex < 0) peakIndex = 0;
      for (var i = 1; i < values.length; i++) {
        if (values[i] > values[peakIndex]) peakIndex = i;
      }
      return CategoryWeekSeries(
        type: type,
        days: dayStarts,
        values: values,
        observed: observed,
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
    this.observed = const [],
  });

  final SignalType type;
  final List<DateTime> days;
  final List<double> values;
  final List<bool> observed;
  bool isObserved(int index) =>
      observed.isEmpty ? values[index] > 0 : observed[index];
  final int peakDayIndex;

  double get peakValue => values.isEmpty ? 0 : values[peakDayIndex];
  DateTime get peakDay => days[peakDayIndex];
  bool get hasData => observed.isEmpty
      ? values.any((value) => value > 0)
      : observed.any((value) => value);
}
