import 'package:flutter/material.dart';

import '../app.dart';
import '../daily_history_logic.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import 'activity_log_screen.dart';
import 'daily_checkin_screen.dart';
import 'sleep_log_screen.dart';

class DailyHistoryScreen extends StatelessWidget {
  const DailyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = AppScope.of(context).dailyHistory;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily History'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: history.isEmpty
            ? const _EmptyHistory()
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                children: [
                  Text(
                    'Your daily record',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Review saved signals by date and fill the gaps in your daily model.',
                    style: TextStyle(color: TonyoColors.muted),
                  ),
                  const SizedBox(height: 18),
                  _HistorySummary(history: history),
                  const SectionHeader('Recent days'),
                  ...history.map(
                    (day) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _HistoryDayCard(
                        key: Key('history-day-${_dateKey(day.date)}'),
                        day: day,
                        onEdit: (item) => _edit(context, item),
                        onDelete: (item) => _delete(context, item),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, DailyHistoryItem item) async {
    final screen = switch (item.kind) {
      DailyHistoryItemKind.activity => ActivityLogScreen(
        initialLog: item.activity,
      ),
      DailyHistoryItemKind.sleep => SleepLogScreen(initialLog: item.sleep),
      DailyHistoryItemKind.checkIn => DailyCheckInScreen(
        initialCheckIn: item.checkIn,
      ),
      DailyHistoryItemKind.signal => null,
    };
    if (screen == null) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _delete(BuildContext context, DailyHistoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete history entry?'),
        content: Text(
          '${_title(item)} will be permanently removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final controller = AppScope.of(context);
    switch (item.kind) {
      case DailyHistoryItemKind.activity:
        await controller.deleteActivityLog(item.id);
      case DailyHistoryItemKind.sleep:
        await controller.deleteSleepLog(item.id);
      case DailyHistoryItemKind.checkIn:
        await controller.deleteCheckIn(item.id);
      case DailyHistoryItemKind.signal:
        await controller.deleteSignal(item.id);
    }
  }

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const MetricIcon(
          icon: Icons.calendar_month_rounded,
          color: TonyoColors.primary,
          size: 64,
        ),
        const SizedBox(height: 18),
        Text(
          'No history yet',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        const Text(
          'Save an activity, sleep, check-in, or reaction entry to start your daily history.',
          textAlign: TextAlign.center,
          style: TextStyle(color: TonyoColors.muted),
        ),
      ],
    ),
  );
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({required this.history});

  final List<DailyHistoryDay> history;

  @override
  Widget build(BuildContext context) {
    final completeDays = history.where((day) => day.isComplete).length;
    return TonyoCard(
      child: Row(
        children: [
          const MetricIcon(
            icon: Icons.fact_check_outlined,
            color: TonyoColors.mint,
            size: 48,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${history.length} days recorded',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$completeDays complete · Activity, Sleep, Check-in, and Reaction',
                  style: const TextStyle(
                    color: TonyoColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryDayCard extends StatelessWidget {
  const _HistoryDayCard({
    super.key,
    required this.day,
    required this.onEdit,
    required this.onDelete,
  });

  final DailyHistoryDay day;
  final ValueChanged<DailyHistoryItem> onEdit;
  final ValueChanged<DailyHistoryItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final statusColor = day.isComplete
        ? TonyoColors.mint
        : day.completionCount >= 2
        ? TonyoColors.amber
        : TonyoColors.coral;
    return TonyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _dayLabel(day.date),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                key: Key('completion-${DailyHistoryScreen._dateKey(day.date)}'),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  day.isComplete
                      ? 'Complete'
                      : '${day.completionCount} of ${day.completionTotal}',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: day.completionProgress,
              minHeight: 5,
              color: statusColor,
              backgroundColor: TonyoColors.border,
            ),
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: DailyCompletionCategory.values
                .map(
                  (category) => _CompletionChip(
                    category: category,
                    completed: day.isCompleted(category),
                  ),
                )
                .toList(),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: TonyoColors.border),
          ),
          ...day.items.map(
            (item) => _HistoryItemRow(
              key: Key('history-item-${item.id}'),
              item: item,
              onEdit: () => onEdit(item),
              onDelete: () => onDelete(item),
            ),
          ),
        ],
      ),
    );
  }

  static String _dayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(date).inDays;
    if (difference == 0) return 'Today · ${formatDate(date)}';
    if (difference == 1) return 'Yesterday · ${formatDate(date)}';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[date.weekday - 1]} · ${formatDate(date)}';
  }
}

class _CompletionChip extends StatelessWidget {
  const _CompletionChip({required this.category, required this.completed});

  final DailyCompletionCategory category;
  final bool completed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: completed
          ? TonyoColors.mint.withValues(alpha: .12)
          : TonyoColors.surfaceRaised,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: completed ? TonyoColors.mint : TonyoColors.border,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          completed ? Icons.check_rounded : Icons.remove_rounded,
          size: 12,
          color: completed ? TonyoColors.mint : TonyoColors.muted,
        ),
        const SizedBox(width: 3),
        Text(
          category.label,
          style: TextStyle(
            color: completed ? TonyoColors.mint : TonyoColors.muted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _HistoryItemRow extends StatelessWidget {
  const _HistoryItemRow({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final DailyHistoryItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = _color(item);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          MetricIcon(icon: _icon(item), color: color, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(item),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  _detail(item),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TonyoColors.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (item.canEdit)
            IconButton(
              tooltip: 'Edit ${_title(item)}',
              onPressed: onEdit,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 19),
            ),
          if (item.canDelete)
            IconButton(
              tooltip: 'Delete ${_title(item)}',
              onPressed: onDelete,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline_rounded, size: 19),
            ),
        ],
      ),
    );
  }
}

String _title(DailyHistoryItem item) => switch (item.kind) {
  DailyHistoryItemKind.activity => 'Activity log',
  DailyHistoryItemKind.sleep => 'Sleep log',
  DailyHistoryItemKind.checkIn => '${item.checkIn!.period.label} check-in',
  DailyHistoryItemKind.signal => item.signal!.type.label,
};

String _detail(DailyHistoryItem item) => switch (item.kind) {
  DailyHistoryItemKind.activity => _activityDetail(item.activity!),
  DailyHistoryItemKind.sleep =>
    '${_duration(item.sleep!.duration)} · quality ${item.sleep!.quality.round()}/5',
  DailyHistoryItemKind.checkIn =>
    'Energy ${item.checkIn!.energy.round()} · Mood ${item.checkIn!.mood.round()} · Stress ${item.checkIn!.stress.round()}',
  DailyHistoryItemKind.signal =>
    '${_number(item.signal!.value)} ${item.signal!.type.unit} · ${_source(item.signal!.source)}',
};

String _activityDetail(ActivityLogEntry log) {
  final values = <String>[];
  if ((log.hydrationLiters ?? 0) > 0) {
    values.add('${_number(log.hydrationLiters!)} L water');
  }
  if ((log.studyHours ?? 0) > 0) {
    values.add('${_number(log.studyHours!)} hr study');
  }
  if ((log.exerciseHours ?? 0) > 0) {
    values.add('${_number(log.exerciseHours!)} hr exercise');
  }
  if ((log.screenTimeHours ?? 0) > 0) {
    values.add('${_number(log.screenTimeHours!)} hr screen');
  }
  return values.join(' · ');
}

IconData _icon(DailyHistoryItem item) => switch (item.kind) {
  DailyHistoryItemKind.activity => Icons.directions_run_rounded,
  DailyHistoryItemKind.sleep => Icons.bedtime_rounded,
  DailyHistoryItemKind.checkIn => Icons.sentiment_satisfied_alt_rounded,
  DailyHistoryItemKind.signal => iconForSignal(item.signal!.type),
};

Color _color(DailyHistoryItem item) => switch (item.kind) {
  DailyHistoryItemKind.activity => TonyoColors.amber,
  DailyHistoryItemKind.sleep => TonyoColors.blue,
  DailyHistoryItemKind.checkIn => TonyoColors.mint,
  DailyHistoryItemKind.signal => colorForSignal(item.signal!.type),
};

String _duration(Duration duration) =>
    '${duration.inHours}h ${duration.inMinutes.remainder(60).toString().padLeft(2, '0')}m';

String _number(double value) => value == value.roundToDouble()
    ? '${value.round()}'
    : value.toStringAsFixed(1);

String _source(SignalSource source) => switch (source) {
  SignalSource.manual => 'Manual',
  SignalSource.healthKit => 'HealthKit',
  SignalSource.model => 'Model',
};
