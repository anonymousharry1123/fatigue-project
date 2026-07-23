import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hydration = TextEditingController();
  final _study = TextEditingController();
  final _exercise = TextEditingController();
  final _screenTime = TextEditingController();
  final _none = <SignalType, bool>{
    SignalType.hydration: false,
    SignalType.study: false,
    SignalType.exercise: false,
    SignalType.screenTime: false,
  };
  String? _editingId;
  bool _saving = false;

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
    final logs = AppScope.of(context).activityLogs;
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
              'Add the daily behaviors that shape your energy forecast.',
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
                      isNone: _none[SignalType.hydration]!,
                      onNoneChanged: (value) =>
                          _setNone(SignalType.hydration, value),
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
                      isNone: _none[SignalType.study]!,
                      onNoneChanged: (value) =>
                          _setNone(SignalType.study, value),
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
                      isNone: _none[SignalType.exercise]!,
                      onNoneChanged: (value) =>
                          _setNone(SignalType.exercise, value),
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
                      isNone: _none[SignalType.screenTime]!,
                      onNoneChanged: (value) =>
                          _setNone(SignalType.screenTime, value),
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
            SectionHeader('Recent activity', action: '${logs.length} saved'),
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
    if (_none.values.every((value) => value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one activity to save.')),
      );
      return;
    }
    setState(() => _saving = true);
    await AppScope.of(context).saveActivityLog(
      id: _editingId,
      hydrationLiters: _value(SignalType.hydration, _hydration),
      studyHours: _value(SignalType.study, _study),
      exerciseHours: _value(SignalType.exercise, _exercise),
      screenTimeHours: _value(SignalType.screenTime, _screenTime),
    );
    if (!mounted) return;
    _clearForm();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Activity log saved.')));
  }

  void _edit(ActivityLogEntry log) {
    setState(() {
      _editingId = log.id;
      _setEditingValue(SignalType.hydration, _hydration, log.hydrationLiters);
      _setEditingValue(SignalType.study, _study, log.studyHours);
      _setEditingValue(SignalType.exercise, _exercise, log.exerciseHours);
      _setEditingValue(SignalType.screenTime, _screenTime, log.screenTimeHours);
    });
  }

  void _clearForm() {
    setState(() {
      _editingId = null;
      _saving = false;
      _hydration.clear();
      _study.clear();
      _exercise.clear();
      _screenTime.clear();
      for (final type in _none.keys) {
        _none[type] = false;
      }
    });
  }

  void _setNone(SignalType type, bool value) {
    setState(() {
      _none[type] = value;
      if (value) _controllerFor(type).clear();
    });
  }

  void _setEditingValue(
    SignalType type,
    TextEditingController controller,
    double? value,
  ) {
    _none[type] = value == null;
    controller.text = value == null ? '' : _number(value);
  }

  double? _value(SignalType type, TextEditingController controller) =>
      _none[type]! ? null : double.parse(controller.text);

  TextEditingController _controllerFor(SignalType type) => switch (type) {
    SignalType.hydration => _hydration,
    SignalType.study => _study,
    SignalType.exercise => _exercise,
    SignalType.screenTime => _screenTime,
    _ => throw ArgumentError.value(type, 'type'),
  };

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
    required this.isNone,
    required this.onNoneChanged,
  });

  final TextEditingController controller;
  final SignalType type;
  final String label;
  final String suffix;
  final IconData icon;
  final Color color;
  final bool isNone;
  final ValueChanged<bool> onNoneChanged;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextFormField(
          controller: controller,
          enabled: !isNone,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          decoration: InputDecoration(
            labelText: isNone ? '$label (not logged)' : label,
            suffixText: isNone ? null : suffix,
            prefixIcon: Icon(icon, color: isNone ? TonyoColors.muted : color),
          ),
          validator: (raw) {
            if (isNone) return null;
            final value = double.tryParse(raw?.trim() ?? '');
            if (value == null) return 'Enter a number or choose None.';
            return ActivityLogEntry.validationMessage(type, value);
          },
        ),
      ),
      const SizedBox(width: 8),
      FilterChip(
        key: Key('${type.name}-none-button'),
        label: const Text('None'),
        selected: isNone,
        showCheckmark: false,
        onSelected: onNoneChanged,
        selectedColor: TonyoColors.primary.withValues(alpha: .25),
      ),
    ],
  );
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
            if (log.hydrationLiters case final value?)
              _metric(Icons.water_drop_rounded, '$value L'),
            if (log.studyHours case final value?)
              _metric(Icons.menu_book_rounded, '$value hr study'),
            if (log.exerciseHours case final value?)
              _metric(Icons.fitness_center_rounded, '$value hr exercise'),
            if (log.screenTimeHours case final value?)
              _metric(Icons.smartphone_rounded, '$value hr screen'),
          ],
        ),
      ],
    ),
  );

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
