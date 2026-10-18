import 'package:flutter/material.dart';

import '../app.dart';
import '../check_in_logic.dart';
import '../check_in_measurement.dart';
import '../l10n/app_localizations.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/self_report_card.dart';
import '../widgets/translated_text.dart';
import 'reaction_test_screen.dart';
import 'sleep_log_screen.dart';

class DailyCheckInScreen extends StatefulWidget {
  const DailyCheckInScreen({super.key, this.initialCheckIn});
  final DailyCheckIn? initialCheckIn;
  @override
  State<DailyCheckInScreen> createState() => _DailyCheckInScreenState();
}

class _DailyCheckInScreenState extends State<DailyCheckInScreen> {
  final ratings = <String, double?>{
    for (final item in CheckInMeasurement.items) item.id: null,
  };
  final skipped = <String>{};
  final noteController = TextEditingController();
  CheckInPeriod? period;
  Map<String, dynamic>? _snapshot;
  String? _language;
  bool saving = false;
  String? _validationError;
  String? _pendingCreateId;
  DateTime? _pendingCreateTimestamp;
  bool get _legacy =>
      widget.initialCheckIn != null &&
      !widget.initialCheckIn!.isResearchCheckIn;

  // Earlier Morning records can contain the full questionnaire. Keep those
  // answers editable; new Morning check-ins collect only Energy.
  bool get _morningEnergyOnly =>
      !_legacy &&
      period == CheckInPeriod.morning &&
      (widget.initialCheckIn == null ||
          widget.initialCheckIn!.ratings.entries.every(
            (entry) => entry.key == 'energy' || entry.value == null,
          ));

  Map<String, double?> get _visibleRatings => {
    for (final entry in ratings.entries)
      entry.key: _morningEnergyOnly && entry.key != 'energy'
          ? null
          : entry.value,
  };

  bool get _legacyEditable =>
      widget.initialCheckIn?.originalLegacyRatings == null &&
      ['energy', 'mood', 'stress'].every(
        (id) =>
            ratings[id] != null &&
            ratings[id]!.isFinite &&
            CheckInLogic.isValidRating(ratings[id]!),
      );

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCheckIn;
    if (initial != null) {
      ratings.addAll(selfReportRatings(initial));
      period = initial.period;
      noteController.text = initial.note;
      if (initial.isResearchCheckIn) {
        _snapshot = initial.questionnaireSnapshot;
        _language = initial.questionnaireLanguage;
        skipped.addAll(ratings.keys.where((id) => ratings[id] == null));
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_legacy && widget.initialCheckIn == null && _snapshot == null) {
      final localization = AppLocalizations.of(context);
      _language = localization.language;
      _snapshot = CheckInMeasurement.snapshot(
        language: _language!,
        translate: localization.text,
      );
    }
  }

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final history = controller.recentCheckIns();
    final snapshotItems =
        (_snapshot?['items'] as List?)?.whereType<Map>().toList() ??
        const <Map>[];
    final supported =
        (_legacy && _legacyEditable) ||
        (!_legacy &&
            _snapshot?['version'] == CheckInMeasurement.currentVersion &&
            snapshotItems.length == 6);
    return Scaffold(
      appBar: AppBar(
        title: TranslatedText(
          widget.initialCheckIn == null ? 'Daily Check-in' : 'Edit Check-in',
        ),
        backgroundColor: Colors.transparent,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: double.infinity,
              minHeight: 52,
            ),
            child: FilledButton(
              key: const Key('save-checkin'),
              onPressed: saving || !supported ? null : _save,
              child: TranslatedText(
                saving
                    ? 'Saving…'
                    : widget.initialCheckIn == null
                    ? 'Save check-in'
                    : 'Update check-in',
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: [
            TranslatedText(
              _legacy ? 'Update your check-in' : 'How do you feel right now?',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            if (_legacy && !_legacyEditable) ...[
              const TranslatedText(
                'This earlier record cannot be edited with the current scales. Its original answers are retained.',
              ),
              const SizedBox(height: 12),
              SelfReportRecordCard(checkIn: widget.initialCheckIn!),
              const SizedBox(height: 12),
            ] else if (_legacy) ...[
              const TranslatedText(
                'Editing an earlier three-item check-in. Its original measurement version and period are preserved.',
              ),
              const SizedBox(height: 12),
              Text(
                context.tr(
                  '{period} check-in',
                  args: {'period': context.tr(period!.label)},
                ),
              ),
              const SizedBox(height: 12),
              TonyoCard(
                key: const Key('checkin-outcome-status'),
                child: TranslatedText(
                  controller.outcomeConsent
                      ? 'Outcome learning is on. This energy rating will also be linked as a private observed-energy outcome.'
                      : 'Outcome learning is off. This check-in still supports today’s wellness estimates, but no training record is created.',
                ),
              ),
              const SizedBox(height: 18),
              for (final id in ['energy', 'mood', 'stress']) ...[
                _LegacyRatingCard(
                  icon: _iconFor(id),
                  color: TonyoPalette.of(context).secondary,
                  title: _labelFor(id),
                  value: ratings[id]!,
                  badge: switch (id) {
                    'energy' => CheckInLogic.energyBadge(ratings[id]!),
                    'mood' => CheckInLogic.moodBadge(ratings[id]!),
                    _ => CheckInLogic.stressBadge(ratings[id]!),
                  },
                  low: switch (id) {
                    'energy' => '1 · Drained',
                    'mood' => '1 · Low',
                    _ => '1 · Calm',
                  },
                  middle: switch (id) {
                    'energy' => '5 · OK',
                    'mood' => '5 · Steady',
                    _ => '5 · Moderate',
                  },
                  high: switch (id) {
                    'energy' => '10 · Charged',
                    'mood' => '10 · Great',
                    _ => '10 · Maxed',
                  },
                  onChanged: saving
                      ? null
                      : (value) => setState(() => ratings[id] = value),
                ),
                const SizedBox(height: 12),
              ],
            ] else ...[
              const TranslatedText(
                CheckInMeasurement.disclosure,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const TranslatedText(
                'These are draft custom self-report questions, not a validated questionnaire. Your answers stay separate from Tonyo’s experimental scores and are not used to train models.',
              ),
              const SizedBox(height: 8),
              TranslatedText(
                _morningEnergyOnly
                    ? 'Morning is a quick Energy check-in. Log sleep with your Evening check-in whenever it suits you.'
                    : 'Choose a period and answer at least one item. Other items and notes are optional; unanswered items stay missing.',
              ),
              const SizedBox(height: 12),
              if (period == CheckInPeriod.evening) ...[
                _EveningSleepCard(enabled: !saving, onOpen: _openSleep),
                const SizedBox(height: 12),
              ],
              _PeriodPicker(
                value: period,
                onChanged: saving
                    ? null
                    : (value) => setState(() => period = value),
              ),
              const SizedBox(height: 12),
              if (_language != AppLocalizations.of(context).language) ...[
                const TranslatedText(
                  'The questions below remain in their originally recorded language so this measurement is not silently changed.',
                ),
                const SizedBox(height: 12),
              ],
              if (!supported)
                const TranslatedText(
                  'This questionnaire version cannot be edited in this app version. Its saved answers are retained.',
                ),
              for (final item in snapshotItems.where(
                (item) => !_morningEnergyOnly || item['id'] == 'energy',
              )) ...[
                _ResearchRatingCard(
                  item: item,
                  value: ratings[item['id']],
                  skipped: skipped.contains(item['id']),
                  onChanged: saving || !supported
                      ? null
                      : (value) => setState(() {
                          ratings[item['id'] as String] = value;
                          if (value == null) {
                            skipped.add(item['id'] as String);
                          } else {
                            skipped.remove(item['id']);
                          }
                        }),
                ),
                const SizedBox(height: 12),
              ],
            ],
            if (_validationError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TranslatedText(
                  _validationError!,
                  key: const Key('checkin-validation'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            TonyoCard(
              child: TextField(
                key: const Key('checkin-note'),
                controller: noteController,
                enabled: !saving && supported,
                maxLines: 2,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  labelText: context.tr('Optional note'),
                ),
              ),
            ),
            if (!_morningEnergyOnly) ...[
              const SectionHeader('Cognitive tests · 30 sec'),
              _TestCard(
                icon: Icons.timer_outlined,
                color: TonyoPalette.of(context).primary,
                title: 'Reaction time',
                detail: 'Tap when it flashes',
                status: 'Try now',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReactionTestScreen()),
                ),
              ),
            ],
            const SectionHeader('Check-in history'),
            if (history.isEmpty)
              const TonyoCard(
                child: TranslatedText(
                  'No check-ins saved yet. Your ratings will appear here.',
                ),
              )
            else
              for (final item in history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SelfReportRecordCard(checkIn: item),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (saving) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final answers = _visibleRatings;
    if (period == null || answers.values.every((value) => value == null)) {
      setState(
        () => _validationError = period == null
            ? 'Choose Morning or Evening before saving.'
            : 'Select at least one rating before saving.',
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: TranslatedText(_validationError!)));
      return;
    }
    setState(() {
      saving = true;
      _validationError = null;
    });
    final controller = AppScope.of(context);
    final initial = widget.initialCheckIn;
    final when =
        initial?.timestamp ??
        (_pendingCreateTimestamp ??= controller.currentTime);
    final id =
        initial?.id ??
        (_pendingCreateId ??= 'checkin-${when.microsecondsSinceEpoch}');
    try {
      if (_legacy) {
        await controller.addCheckIn(
          id: id,
          energy: ratings['energy']!,
          mood: ratings['mood']!,
          stress: ratings['stress']!,
          period: period,
          note: noteController.text.trim(),
          timestamp: when,
        );
      } else {
        await controller.saveSelfReportCheckIn(
          id: id,
          period: period!,
          energy: answers['energy'],
          fatigue: answers['fatigue'],
          sleepiness: answers['sleepiness'],
          focus: answers['focus'],
          mood: answers['mood'],
          stress: answers['stress'],
          note: noteController.text.trim(),
          questionnaireSnapshot: _snapshot!,
          questionnaireLanguage: _language!,
          sharedHeading: context.tr('How do you feel right now?'),
          timestamp: when,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: TranslatedText(
            controller.cloudSyncError == null
                ? '${context.tr(period!.label)} check-in saved on a 1–10 scale.'
                : 'Check-in saved on this device. Cloud sync is pending.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText(
            'Could not save your check-in. Your ratings and note are still here; please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _openSleep() async {
    final controller = AppScope.of(context);
    final at = widget.initialCheckIn?.timestamp ?? controller.currentTime;
    final existing = controller.sleepLogs
        .where(
          (log) =>
              !log.isNap &&
              !log.wakeTime.isAfter(at) &&
              at.difference(log.wakeTime) <= const Duration(hours: 24),
        )
        .firstOrNull;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SleepLogScreen(
          initialLog: existing,
          initialWakeDate: at.toLocal(),
          returnAfterSave: true,
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}

class _EveningSleepCard extends StatelessWidget {
  const _EveningSleepCard({required this.enabled, required this.onOpen});
  final bool enabled;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => TonyoCard(
    key: const Key('evening-sleep-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TranslatedText(
          'Sleep for this check-in',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const TranslatedText(
          'Log your most recent main sleep here, even if you woke up late. There is no logging deadline. Sleep and Energy are saved separately.',
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('checkin-log-sleep'),
          onPressed: enabled ? onOpen : null,
          icon: const Icon(Icons.bedtime_outlined),
          label: const TranslatedText('Log or review sleep'),
        ),
      ],
    ),
  );
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.value, required this.onChanged});
  final CheckInPeriod? value;
  final ValueChanged<CheckInPeriod>? onChanged;
  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TranslatedText(
          'Check-in period',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final period in CheckInPeriod.values)
              ChoiceChip(
                key: Key('checkin-period-${period.name}'),
                label: TranslatedText(period.label),
                selected: value == period,
                onSelected: onChanged == null
                    ? null
                    : (_) => onChanged!(period),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const TranslatedText(
          'Morning: Energy after waking, whatever the time. Evening: your daily check-in and sleep log. Choose the period yourself; both can be saved at any time.',
        ),
      ],
    ),
  );
}

class _ResearchRatingCard extends StatelessWidget {
  const _ResearchRatingCard({
    required this.item,
    required this.value,
    required this.skipped,
    required this.onChanged,
  });
  final Map item;
  final double? value;
  final bool skipped;
  final ValueChanged<double?>? onChanged;
  @override
  Widget build(BuildContext context) {
    final id = item['id'] as String;
    final label = item['label'] as String;
    final prompt = item['prompt'] as String;
    final anchors = item['anchors'] as Map;
    return TonyoCard(
      key: Key('rating-$id'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (prompt.isNotEmpty) ...[const SizedBox(height: 8), Text(prompt)],
          const SizedBox(height: 8),
          Text(
            value == null
                ? context.tr(skipped ? 'Skipped' : 'Not answered')
                : context.tr(
                    '{value} out of 10',
                    args: {'value': value!.round()},
                  ),
            key: Key('rating-$id-value'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var rating = 1; rating <= 10; rating++)
                Semantics(
                  label:
                      '$label, ${context.tr('{value} out of 10', args: {'value': rating})}',
                  button: true,
                  selected: value == rating,
                  child: ExcludeSemantics(
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: OutlinedButton(
                        key: Key('rating-$id-$rating'),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: value == rating
                              ? TonyoPalette.of(
                                  context,
                                ).primary.withValues(alpha: .15)
                              : null,
                        ),
                        onPressed: onChanged == null
                            ? null
                            : () => onChanged!(rating.toDouble()),
                        child: Text('$rating'),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final anchor in ['1', '5', '10'])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '$anchor · ${anchors[anchor]}',
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 12,
                ),
              ),
            ),
          TextButton(
            key: Key('skip-$id'),
            onPressed: onChanged == null ? null : () => onChanged!(null),
            child: TranslatedText(
              value == null ? 'Skip this item' : 'Clear and skip this item',
            ),
          ),
        ],
      ),
    );
  }
}

String _labelFor(String id) =>
    CheckInMeasurement.items.firstWhere((item) => item.id == id).label;
IconData _iconFor(String id) => switch (id) {
  'energy' => Icons.bolt_rounded,
  'mood' => Icons.sentiment_satisfied_alt_rounded,
  _ => Icons.psychology_alt_rounded,
};

class _LegacyRatingCard extends StatelessWidget {
  const _LegacyRatingCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.badge,
    required this.low,
    required this.middle,
    required this.high,
    required this.onChanged,
  });
  final IconData icon;
  final Color color;
  final String title;
  final double value;
  final String badge;
  final String low;
  final String middle;
  final String high;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(icon, color: color, size: 19),
            TranslatedText(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TranslatedText(
                badge,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ExcludeSemantics(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${value.round()}',
                  style: TextStyle(
                    color: color,
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: ' / 10',
                  style: TextStyle(
                    color: TonyoPalette.of(context).muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        MergeSemantics(
          child: Semantics(
            label: context.tr(title),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                overlayShape: SliderComponentShape.noOverlay,
                trackShape: const RoundedRectSliderTrackShape(),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: _thumbRadius,
                ),
                showValueIndicator: ShowValueIndicator.never,
                // Keep the control at least 48px high, including on touch screens.
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Slider(
                value: value,
                min: CheckInLogic.minRating,
                max: CheckInLogic.maxRating,
                divisions: 9,
                semanticFormatterCallback: (rating) => context.tr(
                  '{value} out of 10',
                  args: {'value': rating.round()},
                ),
                activeColor: color,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in [low, middle, high].indexed)
              Expanded(
                child: TranslatedText(
                  entry.$2,
                  textAlign: entry.$1 == 0
                      ? TextAlign.start
                      : entry.$1 == 2
                      ? TextAlign.end
                      : TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  static const _thumbRadius = 10.0;
}

class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.status,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TonyoCard(
    padding: EdgeInsets.zero,
    child: Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              MetricIcon(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TranslatedText(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TranslatedText(
                      detail,
                      style: TextStyle(
                        color: TonyoPalette.of(context).muted,
                        fontSize: 10,
                      ),
                    ),
                    TranslatedText(
                      status,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
