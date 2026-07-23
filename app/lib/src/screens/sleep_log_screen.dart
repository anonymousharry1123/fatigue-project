import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class SleepLogScreen extends StatefulWidget {
  const SleepLogScreen({super.key});

  @override
  State<SleepLogScreen> createState() => _SleepLogScreenState();
}

class _SleepLogScreenState extends State<SleepLogScreen> {
  late DateTime _bedtime;
  late DateTime _wakeTime;
  double _quality = 3;
  String? _editingId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _resetTimes();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final logs = controller.sleepLogs;
    final previewEnd = _normalizedWakeTime;
    final previewDuration = previewEnd.difference(_bedtime);
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
              'Log sleep timing and quality to build a more useful nightly pattern.',
              style: TextStyle(color: TonyoColors.muted),
            ),
            const SizedBox(height: 18),
            TonyoCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _TimeButton(
                          key: const Key('bedtime-button'),
                          label: 'Bedtime',
                          time: _bedtime,
                          icon: Icons.bedtime_rounded,
                          onTap: () => _pickTime(isBedtime: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TimeButton(
                          key: const Key('wake-time-button'),
                          label: 'Wake time',
                          time: previewEnd,
                          icon: Icons.wb_sunny_rounded,
                          onTap: () => _pickTime(isBedtime: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Text(
                        'Sleep quality',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      Text(
                        '${_quality.round()} / 5',
                        style: const TextStyle(
                          color: TonyoColors.blue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    key: const Key('sleep-quality-slider'),
                    value: _quality,
                    min: 1,
                    max: 5,
                    divisions: 4,
                    activeColor: TonyoColors.blue,
                    onChanged: (value) => setState(() => _quality = value),
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
                            onPressed: _saving ? null : _clearForm,
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
                                ? 'Save sleep'
                                : 'Update sleep',
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
                          logs.length < 2
                              ? 'Add 2 nights to calculate'
                              : '±${controller.bedtimeConsistencyMinutes.round()} min',
                          key: const Key('bedtime-consistency'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          'Average bedtime variation across your 7 most recent manual entries.',
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
                  'No manual sleep entries yet. Saved nights will appear here.',
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
                        onEdit: () => _edit(log),
                        onDelete: () =>
                            AppScope.of(context).deleteSleepLog(log.id),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  DateTime get _normalizedWakeTime => _wakeTime.isAfter(_bedtime)
      ? _wakeTime
      : _wakeTime.add(const Duration(days: 1));

  Future<void> _pickTime({required bool isBedtime}) async {
    final current = isBedtime ? _bedtime : _wakeTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return;
    setState(() {
      final updated = DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      );
      if (isBedtime) {
        _bedtime = updated;
      } else {
        _wakeTime = updated;
      }
    });
  }

  Future<void> _save() async {
    final end = _normalizedWakeTime;
    final validation = SleepLogEntry.validationMessage(
      bedtime: _bedtime,
      wakeTime: end,
      quality: _quality,
    );
    if (validation != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validation)));
      return;
    }
    setState(() => _saving = true);
    await AppScope.of(context).addSleep(
      id: _editingId,
      bedtime: _bedtime,
      wakeTime: end,
      quality: _quality,
    );
    if (!mounted) return;
    _clearForm();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sleep log saved.')));
  }

  void _edit(SleepLogEntry log) {
    setState(() {
      _editingId = log.id;
      _bedtime = log.bedtime;
      _wakeTime = log.wakeTime;
      _quality = log.quality;
    });
  }

  void _clearForm() {
    setState(() {
      _editingId = null;
      _saving = false;
      _resetTimes();
      _quality = 3;
    });
  }

  void _resetTimes() {
    final now = DateTime.now();
    _bedtime = DateTime(now.year, now.month, now.day - 1, 23);
    _wakeTime = DateTime(now.year, now.month, now.day, 7);
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
  final VoidCallback onTap;

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
            Text(label, style: const TextStyle(fontSize: 11)),
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
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Row(
      children: [
        const MetricIcon(icon: Icons.bedtime_rounded, color: TonyoColors.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${formatDate(log.wakeTime)} · ${_SleepLogScreenState._durationLabel(log.duration)}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                '${formatHour(log.bedtime)}–${formatHour(log.wakeTime)} · quality ${log.quality.round()}/5',
                style: const TextStyle(color: TonyoColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Edit sleep',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Delete sleep',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    ),
  );
}
