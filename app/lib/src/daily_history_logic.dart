import 'models.dart';

enum DailyHistoryItemKind { activity, sleep, checkIn, signal }

enum DailyCompletionCategory { activity, sleep, checkIn, reaction }

extension DailyCompletionCategoryLabel on DailyCompletionCategory {
  String get label => switch (this) {
    DailyCompletionCategory.activity => 'Activity',
    DailyCompletionCategory.sleep => 'Sleep',
    DailyCompletionCategory.checkIn => 'Check-in',
    DailyCompletionCategory.reaction => 'Reaction',
  };
}

class DailyHistoryItem {
  const DailyHistoryItem.activity(ActivityLogEntry value)
    : kind = DailyHistoryItemKind.activity,
      activity = value,
      sleep = null,
      checkIn = null,
      signal = null;

  const DailyHistoryItem.sleep(SleepLogEntry value)
    : kind = DailyHistoryItemKind.sleep,
      activity = null,
      sleep = value,
      checkIn = null,
      signal = null;

  const DailyHistoryItem.checkIn(DailyCheckIn value)
    : kind = DailyHistoryItemKind.checkIn,
      activity = null,
      sleep = null,
      checkIn = value,
      signal = null;

  const DailyHistoryItem.signal(SignalReading value)
    : kind = DailyHistoryItemKind.signal,
      activity = null,
      sleep = null,
      checkIn = null,
      signal = value;

  final DailyHistoryItemKind kind;
  final ActivityLogEntry? activity;
  final SleepLogEntry? sleep;
  final DailyCheckIn? checkIn;
  final SignalReading? signal;

  String get id => switch (kind) {
    DailyHistoryItemKind.activity => activity!.id,
    DailyHistoryItemKind.sleep => sleep!.id,
    DailyHistoryItemKind.checkIn => checkIn!.id,
    DailyHistoryItemKind.signal => signal!.id,
  };

  DateTime get timestamp => switch (kind) {
    DailyHistoryItemKind.activity => activity!.timestamp,
    DailyHistoryItemKind.sleep => sleep!.wakeTime,
    DailyHistoryItemKind.checkIn => checkIn!.timestamp,
    DailyHistoryItemKind.signal => signal!.timestamp,
  };

  bool get isFixture => id.startsWith('demo-');

  bool get isManual =>
      !isFixture &&
      switch (kind) {
        DailyHistoryItemKind.activity ||
        DailyHistoryItemKind.sleep ||
        DailyHistoryItemKind.checkIn => true,
        DailyHistoryItemKind.signal => signal!.source == SignalSource.manual,
      };

  bool get canEdit => isManual && kind != DailyHistoryItemKind.signal;

  bool get canDelete => isManual;
}

class DailyHistoryDay {
  const DailyHistoryDay({
    required this.date,
    required this.items,
    required this.completedCategories,
  });

  final DateTime date;
  final List<DailyHistoryItem> items;
  final Set<DailyCompletionCategory> completedCategories;

  int get completionCount => completedCategories.length;
  int get completionTotal => DailyCompletionCategory.values.length;
  bool get isComplete => completionCount == completionTotal;
  double get completionProgress => completionCount / completionTotal;

  bool isCompleted(DailyCompletionCategory category) =>
      completedCategories.contains(category);
}

/// Builds the Version 0.10 history without duplicating grouped signal records.
abstract final class DailyHistoryLogic {
  static List<DailyHistoryDay> build({
    required List<SignalReading> signals,
    required List<DailyCheckIn> checkIns,
    required List<ActivityLogEntry> activityLogs,
    required List<SleepLogEntry> sleepLogs,
  }) {
    final itemsByDay = <DateTime, List<DailyHistoryItem>>{};

    void add(DailyHistoryItem item) {
      final day = dayFor(item.timestamp);
      itemsByDay.putIfAbsent(day, () => []).add(item);
    }

    for (final activity in activityLogs) {
      add(DailyHistoryItem.activity(activity));
    }
    for (final sleep in sleepLogs) {
      add(DailyHistoryItem.sleep(sleep));
    }
    for (final checkIn in checkIns) {
      add(DailyHistoryItem.checkIn(checkIn));
    }
    for (final signal in signals) {
      final groupId = signal.groupId;
      final isGroupedRecord =
          groupId != null &&
          (groupId.startsWith('activity-') || groupId.startsWith('sleep-'));
      if (!isGroupedRecord) add(DailyHistoryItem.signal(signal));
    }

    final days = itemsByDay.entries.map((entry) {
      final items = entry.value
        ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
      return DailyHistoryDay(
        date: entry.key,
        items: List.unmodifiable(items),
        completedCategories: Set.unmodifiable(_completedCategories(items)),
      );
    }).toList();
    days.sort((left, right) => right.date.compareTo(left.date));
    return days;
  }

  static DateTime dayFor(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static Set<DailyCompletionCategory> _completedCategories(
    List<DailyHistoryItem> items,
  ) {
    final completed = <DailyCompletionCategory>{};
    for (final item in items) {
      switch (item.kind) {
        case DailyHistoryItemKind.activity:
          completed.add(DailyCompletionCategory.activity);
        case DailyHistoryItemKind.sleep:
          completed.add(DailyCompletionCategory.sleep);
        case DailyHistoryItemKind.checkIn:
          completed.add(DailyCompletionCategory.checkIn);
        case DailyHistoryItemKind.signal:
          final type = item.signal!.type;
          if (ActivityLogEntry.allowedTypes.contains(type)) {
            completed.add(DailyCompletionCategory.activity);
          } else if (type == SignalType.sleep) {
            completed.add(DailyCompletionCategory.sleep);
          } else if (type == SignalType.reactionTime) {
            completed.add(DailyCompletionCategory.reaction);
          }
      }
    }
    return completed;
  }
}
