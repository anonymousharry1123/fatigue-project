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
    setState(() => _saving = true);
    await AppScope.of(context).saveActivityLog(
      id: _editingId,
      hydrationLiters: double.parse(_hydration.text),
      studyHours: double.parse(_study.text),
      exerciseHours: double.parse(_exercise.text),
      screenTimeHours: double.parse(_screenTime.text),
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
      _hydration.text = _number(log.hydrationLiters);
      _study.text = _number(log.studyHours);
      _exercise.text = _number(log.exerciseHours);
      _screenTime.text = _number(log.screenTimeHours);
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
    });
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
      suffixText: suffix,
      prefixIcon: Icon(icon, color: color),
    ),
    validator: (raw) {
      final value = double.tryParse(raw?.trim() ?? '');
      if (value == null) return 'Enter a number.';
      return ActivityLogEntry.validationMessage(type, value);
    },
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
            _metric(Icons.water_drop_rounded, '${log.hydrationLiters} L'),
            _metric(Icons.menu_book_rounded, '${log.studyHours} hr study'),
            _metric(
              Icons.fitness_center_rounded,
              '${log.exerciseHours} hr exercise',
            ),
            _metric(
              Icons.smartphone_rounded,
              '${log.screenTimeHours} hr screen',
            ),
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
