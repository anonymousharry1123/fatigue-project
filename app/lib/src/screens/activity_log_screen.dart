import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../activity_log_logic.dart';
import '../app.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key, this.initialLog});

  final ActivityLogEntry? initialLog;

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hydration = TextEditingController();
  final _study = TextEditingController();
  final _exercise = TextEditingController();
  final _screenTime = TextEditingController();
  String? _editingId;
  DateTime? _editingTimestamp;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initialLog = widget.initialLog;
    if (initialLog != null) _loadLog(initialLog);
  }

  @override
  void dispose() {
    _hydration.dispose();
    _study.dispose();
    _exercise.dispose();
    _screenTime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final logs = controller.activityLogs;
    final week = ActivityLogLogic.weekByCategory(logs);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Log'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          children: [
            Text(
              _editingId == null ? 'Log today’s activity' : 'Edit activity',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Fill any categories you tracked. Blank fields save as 0.',
              style: TextStyle(color: TonyoColors.muted),
            ),
            const SizedBox(height: 18),
            TonyoCard(
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _NumberField(
                      key: const Key('hydration-field'),
                      controller: _hydration,
                      type: SignalType.hydration,
                      label: 'Hydration',
                      suffix: 'liters',
                      icon: Icons.water_drop_rounded,
                      color: TonyoColors.mint,
                    ),
                    const SizedBox(height: 12),
                    _NumberField(
                      key: const Key('study-field'),
                      controller: _study,
                      type: SignalType.study,
                      label: 'Study time',
                      suffix: 'hours',
                      icon: Icons.menu_book_rounded,
                      color: TonyoColors.amber,
                    ),
                    const SizedBox(height: 12),
                    _NumberField(
                      key: const Key('exercise-field'),
                      controller: _exercise,
                      type: SignalType.exercise,
                      label: 'Exercise load',
                      suffix: 'hours',
                      icon: Icons.fitness_center_rounded,
                      color: TonyoColors.coral,
                    ),
                    const SizedBox(height: 12),
                    _NumberField(
                      key: const Key('screen-time-field'),
                      controller: _screenTime,
                      type: SignalType.screenTime,
                      label: 'Screen time',
                      suffix: 'hours',
                      icon: Icons.smartphone_rounded,
                      color: TonyoColors.violet,
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
                                  ? 'Save activity'
                                  : 'Update activity',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SectionHeader('Last 7 days by category'),
            if (!week.any((series) => series.hasData))
              const TonyoCard(
                child: Text(
                  'No activity yet this week. Save a log to see daily category charts.',
                  style: TextStyle(color: TonyoColors.muted),
                ),
              )
            else
              ...week.map(
                (series) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CategoryWeekCard(series: series),
                ),
              ),
            SectionHeader('Recent entries', action: '${logs.length} saved'),
            if (logs.isEmpty)
              const TonyoCard(
                child: Text(
                  'No manual activity logs yet. Your first saved day will appear here.',
                  style: TextStyle(color: TonyoColors.muted),
                ),
              )
            else
              ...logs
                  .take(7)
                  .map(
                    (log) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ActivityHistoryCard(
                        log: log,
                        onEdit: () => _edit(log),
                        onDelete: () =>
                            AppScope.of(context).deleteActivityLog(log.id),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final hydration = _parsed(_hydration);
    final study = _parsed(_study);
    final exercise = _parsed(_exercise);
    final screenTime = _parsed(_screenTime);
    if (!ActivityLogLogic.hasAnyLoggedValue(
      hydrationLiters: hydration,
      studyHours: study,
      exerciseHours: exercise,
      screenTimeHours: screenTime,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one activity value.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await AppScope.of(context).saveActivityLog(
        id: _editingId,
        hydrationLiters: hydration,
        studyHours: study,
        exerciseHours: exercise,
        screenTimeHours: screenTime,
        timestamp: _editingTimestamp,
      );
      if (!mounted) return;
      if (widget.initialLog != null) {
        Navigator.of(context).pop();
        return;
      }
      _clearForm();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Activity log saved.')));
    } on ArgumentError catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  void _edit(ActivityLogEntry log) {
    setState(() => _loadLog(log));
  }

  void _loadLog(ActivityLogEntry log) {
    _editingId = log.id;
    _editingTimestamp = log.timestamp;
    _hydration.text = _number(log.hydrationLiters ?? 0);
    _study.text = _number(log.studyHours ?? 0);
    _exercise.text = _number(log.exerciseHours ?? 0);
    _screenTime.text = _number(log.screenTimeHours ?? 0);
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
      _editingTimestamp = null;
      _saving = false;
      _hydration.clear();
      _study.clear();
      _exercise.clear();
      _screenTime.clear();
    });
  }

  double _parsed(TextEditingController controller) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return 0;
    return double.parse(raw);
  }

  static String _number(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    super.key,
    required this.controller,
    required this.type,
    required this.label,
    required this.suffix,
    required this.icon,
    required this.color,
  });

  final TextEditingController controller;
  final SignalType type;
  final String label;
  final String suffix;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
    ],
    decoration: InputDecoration(
      labelText: label,
      hintText: '0 if blank',
      suffixText: suffix,
      prefixIcon: Icon(icon, color: color),
    ),
    validator: (raw) {
      final text = raw?.trim() ?? '';
      if (text.isEmpty) return null;
      final value = double.tryParse(text);
      if (value == null) return 'Enter a valid number.';
      return ActivityLogEntry.validationMessage(type, value);
    },
  );
}

class _CategoryWeekCard extends StatelessWidget {
  const _CategoryWeekCard({required this.series});
  final CategoryWeekSeries series;

  @override
  Widget build(BuildContext context) {
    final color = _color(series.type);
    final unit = ActivityLogLogic.categoryUnit(series.type);
    final peakLabel = series.hasData
        ? 'Most on ${_weekday(series.peakDay)} · ${_format(series.peakValue)} $unit'
        : 'No data this week';
    return TonyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon(series.type), color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ActivityLogLogic.categoryTitle(series.type),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                peakLabel,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 124,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: series.values.asMap().entries.map((entry) {
                final max = series.values.fold<double>(
                  0,
                  (peak, value) => value > peak ? value : peak,
                );
                final height = max <= 0
                    ? 10.0
                    : (10 + (entry.value / max) * 78).clamp(10, 88).toDouble();
                final isPeak =
                    series.hasData && entry.key == series.peakDayIndex;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 14,
                          child: entry.value > 0
                              ? Text(
                                  _format(entry.value),
                                  style: TextStyle(
                                    color: isPeak ? color : TonyoColors.muted,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: height,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: isPeak
                                  ? [color, color.withValues(alpha: .65)]
                                  : [
                                      color.withValues(alpha: .35),
                                      color.withValues(alpha: .18),
                                    ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: series.days
                .map(
                  (day) => Expanded(
                    child: Text(
                      _weekday(day),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: TonyoColors.muted,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  static IconData _icon(SignalType type) => switch (type) {
    SignalType.hydration => Icons.water_drop_rounded,
    SignalType.study => Icons.menu_book_rounded,
    SignalType.exercise => Icons.fitness_center_rounded,
    SignalType.screenTime => Icons.smartphone_rounded,
    _ => Icons.insights_rounded,
  };

  static Color _color(SignalType type) => switch (type) {
    SignalType.hydration => TonyoColors.mint,
    SignalType.study => TonyoColors.amber,
    SignalType.exercise => TonyoColors.coral,
    SignalType.screenTime => TonyoColors.violet,
    _ => TonyoColors.primary,
  };

  static String _weekday(DateTime day) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[day.weekday - 1];
  }

  static String _format(double value) => value == value.roundToDouble()
      ? '${value.round()}'
      : value.toStringAsFixed(1);
}

class _ActivityHistoryCard extends StatelessWidget {
  const _ActivityHistoryCard({
    required this.log,
    required this.onEdit,
    required this.onDelete,
  });

  final ActivityLogEntry log;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              formatDate(log.timestamp),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Edit activity',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Delete activity',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            _metric(
              Icons.water_drop_rounded,
              '${_format(log.hydrationLiters)} L',
            ),
            _metric(
              Icons.menu_book_rounded,
              '${_format(log.studyHours)} hr study',
            ),
            _metric(
              Icons.fitness_center_rounded,
              '${_format(log.exerciseHours)} hr exercise',
            ),
            _metric(
              Icons.smartphone_rounded,
              '${_format(log.screenTimeHours)} hr screen',
            ),
          ],
        ),
      ],
    ),
  );

  String _format(double? value) {
    final amount = value ?? 0;
    return amount == amount.roundToDouble()
        ? '${amount.round()}'
        : amount.toStringAsFixed(1);
  }

  Widget _metric(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: TonyoColors.muted),
      const SizedBox(width: 4),
      Text(
        text,
        style: const TextStyle(color: TonyoColors.muted, fontSize: 11),
      ),
    ],
  );
}
