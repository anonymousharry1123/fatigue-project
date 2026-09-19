import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';
import '../sleep_sync_logic.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class SleepLogScreen extends StatefulWidget {
  const SleepLogScreen({super.key, this.initialLog});

  final SleepLogEntry? initialLog;

  @override
  State<SleepLogScreen> createState() => _SleepLogScreenState();
}

class _SleepLogScreenState extends State<SleepLogScreen> {
  late DateTime _bedtime;
  late DateTime _wakeTime;
  double _quality = 3;
  SleepKind _kind = SleepKind.mainSleep;
  String? _editingId;
  String? _pendingCreateId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initialLog = widget.initialLog;
    if (initialLog == null) {
      _resetTimes();
    } else {
      _loadLog(initialLog);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    final logs = controller.sleepLogs;
    final mainSleepLogs = logs.where((log) => !log.isNap).toList();
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day - 6);
    final recentNaps = SleepSyncLogic.preferredNapReadings(controller.signals)
        .where(
          (reading) =>
              !reading.timestamp.isBefore(weekStart) &&
              !reading.timestamp.isAfter(now),
        );
    final napMinutes = recentNaps.fold<int>(
      0,
      (total, reading) => total + (reading.value * 60).round(),
    );
    final normalized = SleepLogEntry.normalizeOvernightPair(
      bedtime: _bedtime,
      wakeTime: _wakeTime,
    );
    final previewBedtime = normalized.$1;
    final previewWake = normalized.$2;
    final previewDuration = previewWake.difference(previewBedtime);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sleep Log'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          children: [
            Text(
              _editingId == null ? 'How did you sleep?' : 'Edit sleep',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Keep main sleep and naps separate to preserve your nightly average.',
              style: TextStyle(color: TonyoColors.muted),
            ),
            const SizedBox(height: 18),
            TonyoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<SleepKind>(
                    key: const Key('sleep-kind-selector'),
                    direction: largeText ? Axis.vertical : Axis.horizontal,
                    segments: const [
                      ButtonSegment(
                        value: SleepKind.mainSleep,
                        label: Text('Main sleep'),
                        icon: Icon(Icons.bedtime_rounded),
                      ),
                      ButtonSegment(
                        value: SleepKind.nap,
                        label: Text('Nap'),
                        icon: Icon(Icons.airline_seat_individual_suite_rounded),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: _saving
                        ? null
                        : (selection) => _selectKind(selection.single),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _kind == SleepKind.nap
                        ? 'Naps add daytime rest without changing your main-sleep average or bedtime consistency.'
                        : 'Your longest planned sleep, including daytime sleep for shift schedules.',
                    style: const TextStyle(
                      color: TonyoColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = largeText
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 10) / 2;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          SizedBox(
                            width: width,
                            child: _TimeButton(
                              key: const Key('bedtime-button'),
                              label: _kind == SleepKind.nap
                                  ? 'Nap start'
                                  : 'Bedtime',
                              time: _bedtime,
                              icon: Icons.bedtime_rounded,
                              onTap: _saving
                                  ? null
                                  : () => _pickTime(isBedtime: true),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _TimeButton(
                              key: const Key('wake-time-button'),
                              label: _kind == SleepKind.nap
                                  ? 'Nap end'
                                  : 'Wake time',
                              time: previewWake,
                              icon: Icons.wb_sunny_rounded,
                              onTap: _saving
                                  ? null
                                  : () => _pickTime(isBedtime: false),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Sleep quality',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_quality.round()} / 5',
                        style: const TextStyle(
                          color: TonyoColors.blue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  MergeSemantics(
                    child: Semantics(
                      label: 'Sleep quality',
                      child: Slider(
                        key: const Key('sleep-quality-slider'),
                        value: _quality,
                        min: 1,
                        max: 5,
                        divisions: 4,
                        activeColor: TonyoColors.blue,
                        semanticFormatterCallback: (value) =>
                            '${value.round()} out of 5',
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _quality = value),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const MetricIcon(
                        icon: Icons.schedule_rounded,
                        color: TonyoColors.violet,
                        size: 36,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Calculated duration: ${_durationLabel(previewDuration)}',
                          key: const Key('sleep-duration-preview'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (_editingId != null) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving ? null : _cancelEdit,
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.check_rounded),
                          label: Text(
                            _saving
                                ? 'Saving…'
                                : _editingId == null
                                ? (_kind == SleepKind.nap
                                      ? 'Save nap'
                                      : 'Save sleep')
                                : (_kind == SleepKind.nap
                                      ? 'Update nap'
                                      : 'Update sleep'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SectionHeader('Bedtime consistency'),
            TonyoCard(
              child: Row(
                children: [
                  const MetricIcon(
                    icon: Icons.timeline_rounded,
                    color: TonyoColors.mint,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mainSleepLogs.length < 2
                              ? 'Add 2 main sleeps to calculate'
                              : '±${controller.bedtimeConsistencyMinutes.round()} min',
                          key: const Key('bedtime-consistency'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          'Average start-time variation across your 7 most recent main sleeps. Naps are excluded.',
                          style: TextStyle(
                            color: TonyoColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SectionHeader('Naps · last 7 days'),
            TonyoCard(
              key: const Key('nap-summary'),
              child: Row(
                children: [
                  const MetricIcon(
                    icon: Icons.airline_seat_individual_suite_rounded,
                    color: TonyoColors.violet,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${recentNaps.length} ${recentNaps.length == 1 ? 'nap' : 'naps'} · ${_durationLabel(Duration(minutes: napMinutes))} total',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const Text(
                          'Tracked separately from main sleep.',
                          style: TextStyle(
                            color: TonyoColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SectionHeader('Recent sleep', action: '${logs.length} saved'),
            if (logs.isEmpty)
              const TonyoCard(
                child: Text(
                  'No sleep entries yet. Main sleep and naps will appear here.',
                  style: TextStyle(color: TonyoColors.muted),
                ),
              )
            else
              ...logs
                  .take(7)
                  .map(
                    (log) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SleepHistoryCard(
                        log: log,
                        onEdit: _saving ? null : () => _edit(log),
                        onDelete: _saving ? null : () => _delete(log),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime({required bool isBedtime}) async {
    final current = isBedtime ? _bedtime : _wakeTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null || !mounted || _saving) return;
    setState(() {
      final updated = DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      );
      final nextBedtime = isBedtime ? updated : _bedtime;
      final nextWake = isBedtime ? _wakeTime : updated;
      final normalized = SleepLogEntry.normalizeOvernightPair(
        bedtime: nextBedtime,
        wakeTime: nextWake,
      );
      _bedtime = normalized.$1;
      _wakeTime = normalized.$2;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final normalized = SleepLogEntry.normalizeOvernightPair(
      bedtime: _bedtime,
      wakeTime: _wakeTime,
    );
    final start = normalized.$1;
    final end = normalized.$2;
    final validation = SleepLogEntry.validationMessage(
      bedtime: start,
      wakeTime: end,
      quality: _quality,
      kind: _kind,
    );
    if (validation != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validation)));
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _saving = true);
    final controller = AppScope.of(context);
    final id =
        _editingId ??
        (_pendingCreateId ??= 'sleep-${DateTime.now().microsecondsSinceEpoch}');
    final savedNap = _kind == SleepKind.nap;
    try {
      await controller.addSleep(
        id: id,
        bedtime: start,
        wakeTime: end,
        quality: _quality,
        kind: _kind,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            controller.cloudSyncError != null
                ? '${savedNap ? 'Nap' : 'Sleep'} saved on this device. Cloud sync is pending.'
                : savedNap
                ? 'Nap saved.'
                : 'Sleep log saved.',
          ),
        ),
      );
      if (widget.initialLog != null) {
        Navigator.of(context).pop();
        return;
      }
      _clearForm();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save sleep. Your times and quality rating are still here; please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(SleepLogEntry log) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await AppScope.of(context).deleteSleepLog(log.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete sleep. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _edit(SleepLogEntry log) {
    setState(() => _loadLog(log));
  }

  void _loadLog(SleepLogEntry log) {
    _pendingCreateId = null;
    _editingId = log.id;
    _bedtime = log.bedtime.toLocal();
    _wakeTime = log.wakeTime.toLocal();
    _quality = log.quality;
    _kind = log.kind;
  }

  void _cancelEdit() {
    if (widget.initialLog != null) {
      Navigator.of(context).pop();
    } else {
      _clearForm();
    }
  }

  void _clearForm() {
    setState(() {
      _editingId = null;
      _pendingCreateId = null;
      _saving = false;
      _resetTimes();
      _quality = 3;
    });
  }

  void _selectKind(SleepKind kind) {
    setState(() {
      _kind = kind;
      // Preserve saved times when correcting an existing entry's kind.
      if (_editingId == null) _resetTimes();
    });
  }

  void _resetTimes() {
    final now = DateTime.now();
    if (_kind == SleepKind.nap) {
      _wakeTime = DateTime(now.year, now.month, now.day, now.hour, now.minute);
      _bedtime = _wakeTime.subtract(const Duration(minutes: 30));
    } else {
      _bedtime = DateTime(now.year, now.month, now.day - 1, 23);
      _wakeTime = DateTime(now.year, now.month, now.day, 7);
    }
  }

  static String _durationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    super.key,
    required this.label,
    required this.time,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final DateTime time;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      alignment: Alignment.centerLeft,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 5),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          formatHour(time),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _SleepHistoryCard extends StatelessWidget {
  const _SleepHistoryCard({
    required this.log,
    required this.onEdit,
    required this.onDelete,
  });

  final SleepLogEntry log;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Row(
      children: [
        MetricIcon(
          icon: log.isNap
              ? Icons.airline_seat_individual_suite_rounded
              : Icons.bedtime_rounded,
          color: log.isNap ? TonyoColors.violet : TonyoColors.blue,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${log.isNap ? 'Nap' : 'Main sleep'} · ${_SleepLogScreenState._durationLabel(log.duration)}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                '${formatDate(log.wakeTime)} · ${formatHour(log.bedtime)}–${formatHour(log.wakeTime)} · quality ${log.quality.round()}/5',
                style: const TextStyle(color: TonyoColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: log.isNap ? 'Edit nap' : 'Edit sleep',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: log.isNap ? 'Delete nap' : 'Delete sleep',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    ),
  );
}
