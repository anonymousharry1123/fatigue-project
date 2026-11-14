import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../l10n/app_localizations.dart';
import '../sleep_energy_experiment.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

/// Opening this screen loads saved experiment state. Training and prediction
/// capture always require separate, explicit actions.
class SleepEnergyScreen extends StatefulWidget {
  const SleepEnergyScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SleepEnergyScreen> createState() => _SleepEnergyScreenState();
}

class _SleepEnergyScreenState extends State<SleepEnergyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.refreshSleepEnergyExperiment();
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('Sleep & Energy experiment'))),
        body: SafeArea(
          top: false,
          child: !controller.sleepEnergyCanInspect
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: _Notice(
                    key: const Key('sleep-energy-unavailable'),
                    text: context.tr(
                      controller.sleepEnergyStatus ?? 'Your private device data is unavailable for this session. Return to your account and enable Outcome learning in Profile before viewing this experiment.',
                    ),
                  ),
                )
              : _content(context, controller),
        ),
      );
    },
  );

  Widget _content(BuildContext context, AppController controller) {
    final readiness = controller.sleepEnergyReadiness;
    final run = controller.sleepEnergyRun;
    final changed =
        run != null && run.readinessFingerprint != readiness.fingerprint;
    return ListView(
      key: const Key('sleep-energy-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text(
          context.tr('Learning from your days'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(
            'Test whether your recorded sleep helps predict your evening Energy rating. This personal experiment stays separate from your daily scores.',
          ),
          style: TextStyle(color: TonyoPalette.of(context).muted, height: 1.4),
        ),
        const SizedBox(height: 20),
        _ReadinessCard(readiness: readiness),
        const SizedBox(height: 16),
        _NextStepCard(readiness: readiness, changed: changed),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('sleep-energy-train'),
          onPressed:
              controller.sleepEnergyBusy ||
                  !controller.sleepEnergyAvailable ||
                  !readiness.canTrain
              ? null
              : () => _runAction(
                  controller.trainSleepEnergyModel,
                  'Could not save the training result. Please try again.',
                ),
          icon: const Icon(Icons.science_outlined),
          label: Text(context.tr('Train experimental model')),
        ),
        if (controller.sleepEnergyBusy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(key: Key('sleep-energy-busy')),
        ],
        if (controller.sleepEnergyStatus case final status?) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              context.tr(status),
              key: const Key('sleep-energy-status'),
            ),
          ),
        ],
        const SizedBox(height: 24),
        const SectionHeader('Saved training results'),
        if (run == null)
          _Notice(
            key: const Key('sleep-energy-no-run'),
            text: context.tr(
              'No model has been trained here yet. When enough paired days are available, use the training button to save a result.',
            ),
          )
        else ...[
          Text(
            context.tr('Trained {date}', args: {'date': _date(run.trainedAt)}),
          ),
          if (changed) ...[
            const SizedBox(height: 8),
            _Notice(
              key: const Key('sleep-energy-data-changed'),
              text: context.tr(
                'Data changed since this run. These saved results describe the earlier records; train again to include new days, edits or removals.',
              ),
            ),
          ],
          const SizedBox(height: 12),
          for (final fit in run.fits) ...[
            _FitCard(fit: fit),
            const SizedBox(height: 12),
          ],
        ],
        const SizedBox(height: 12),
        const SectionHeader('Can activity help too?'),
        _ActivityCard(readiness: readiness, run: run),
        const SizedBox(height: 24),
        const SectionHeader('Predictions before check-in'),
        _PredictionControls(
          controller: controller,
          onLoggingChanged: (value) => _runAction(
            () => controller.setSleepEnergyLoggingEnabled(value),
            'Could not change prediction logging. Please try again.',
          ),
          onRecord: () => _runAction(
            controller.recordSleepEnergyPrediction,
            'Could not save the prediction. Please try again.',
          ),
        ),
        const SizedBox(height: 24),
        const SectionHeader('Results on future days'),
        _ProspectiveResults(results: controller.sleepEnergyProspectiveResults),
        const SizedBox(height: 20),
        TextButton.icon(
          key: const Key('sleep-energy-clear'),
          onPressed: controller.sleepEnergyBusy ? null : _clearHistory,
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(context.tr('Remove experiment history')),
        ),
      ],
    );
  }

  Future<void> _clearHistory() async {
    final controller = widget.controller;
    final revision = controller.sessionRevision;
    final owner = controller.cloudUid;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Remove experiment history?')),
        content: Text(
          context.tr(
            'This removes this device’s saved experiment models, results and prediction history, and turns prediction logging off. Your sleep, activity logs and check-ins are kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            key: const Key('sleep-energy-clear-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('Remove history')),
          ),
        ],
      ),
    );
    if (confirmed == true &&
        mounted &&
        controller.sleepEnergyCanInspect &&
        controller.sessionRevision == revision &&
        controller.cloudUid == owner) {
      await _runAction(
        controller.clearSleepEnergyHistory,
        'Could not remove experiment history. Please try again.',
      );
    }
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String failureMessage,
  ) async {
    final controller = widget.controller;
    final revision = controller.sessionRevision;
    try {
      await action();
    } on Object {
      if (!mounted ||
          controller.sessionRevision != revision ||
          !controller.sleepEnergyCanInspect) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr(failureMessage))));
    }
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.readiness});
  final SleepEnergyReadiness readiness;

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(context.tr('Saved records')),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Count(label: 'Sleep', count: readiness.savedSleepCount),
            _Count(label: 'Check-ins', count: readiness.savedCheckInCount),
            _Count(label: 'Activity logs', count: readiness.savedActivityCount),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          context.tr(
            '{count} usable sleep–Energy days',
            args: {'count': readiness.pairCount},
          ),
          key: const Key('sleep-energy-pair-count'),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: TonyoPalette.of(context).primary),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(
            'Saved records are not all training days. Each usable day needs an Energy answer in its first compatible evening check-in and a valid earlier main-sleep record.',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(
            'Sleep sources, questionnaire wording and time zones are kept separate. A sleep record can be used only once.',
          ),
          style: TextStyle(color: TonyoPalette.of(context).muted),
        ),
        for (final cohort in readiness.cohorts) ...[
          const Divider(height: 28),
          _Title(_source(context, cohort.sleepSource)),
          Text(cohort.timezone),
          const SizedBox(height: 6),
          Text(
            context.tr(
              'Paired days: {count} · {status}',
              args: {
                'count': cohort.pairCount,
                'status': context.tr(
                  cohort.canTrain
                      ? 'Can fit an early model'
                      : 'More data needed',
                ),
              },
            ),
          ),
          if (cohort.blocker case final blocker?)
            Text(context.tr(_blocker(blocker))),
        ],
      ],
    ),
  );
}

class _NextStepCard extends StatelessWidget {
  const _NextStepCard({required this.readiness, required this.changed});
  final SleepEnergyReadiness readiness;
  final bool changed;

  @override
  Widget build(BuildContext context) {
    final exclusions =
        readiness.exclusions.entries.where((entry) => entry.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final energyMissing =
        readiness.exclusions['selected_first_response_missing_energy'] ?? 0;
    final sleepMissing =
        readiness.exclusions['selected_response_sleep_unmatched'] ?? 0;
    return TonyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Title(context.tr('What to work on next')),
          const SizedBox(height: 8),
          Text(
            context.tr(
              readiness.canTrain
                  ? changed
                        ? 'Train again to refresh the saved comparison with your current paired days.'
                        : 'You can fit an early model. Keep recording new days to test whether it predicts better than simple averages.'
                  : 'Keep saving your main sleep and an evening Energy answer on the same day. Training needs enough paired days with different recorded sleep durations.',
            ),
          ),
          if (energyMissing > 0) ...[
            const SizedBox(height: 8),
            Text(
              context.tr(
                'Include Energy in your first evening check-in. Later submissions on the same day do not replace a missing first answer.',
              ),
            ),
          ],
          if (sleepMissing > 0) ...[
            const SizedBox(height: 8),
            Text(
              context.tr(
                'Sync or save your main sleep before recording a prediction. A matched sleep must end within the 24 hours before the evening check-in.',
              ),
            ),
          ],
          if (exclusions.isNotEmpty) ...[
            const SizedBox(height: 10),
            ExpansionTile(
              key: const Key('sleep-energy-exclusions'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(context.tr('Why some check-ins are left out')),
              children: [
                for (final entry in exclusions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.tr(
                          '{count} · {reason}',
                          args: {
                            'count': entry.value,
                            'reason': context.tr(_exclusion(entry.key)),
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FitCard extends StatelessWidget {
  const _FitCard({required this.fit});
  final SleepEnergyFit fit;

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(_source(context, fit.sleepSource)),
        Text(fit.timezone),
        const SizedBox(height: 10),
        Text(context.tr('Historical test · saved past days')),
        const SizedBox(height: 8),
        if (!fit.fitted)
          Text(context.tr(_blocker(fit.blocker)))
        else ...[
          Text(
            context.tr(
              'Earlier training days: {train} · later held-out days: {test}',
              args: {'train': fit.trainingCount, 'test': fit.holdoutCount},
            ),
          ),
          if (fit.holdoutStartDate != null && fit.holdoutEndDate != null)
            Text('${fit.holdoutStartDate} – ${fit.holdoutEndDate}'),
          const SizedBox(height: 16),
          _Errors(
            rows: [
              ('Sleep model', fit.modelMae),
              ('Training-days average', fit.meanMae),
              ('Last training rating', fit.previousMae),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'All three methods use the same held-out days. The average and last-rating comparisons are fixed using only the training days.',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              fit.holdoutCount < 5
                  ? 'This test has very few days. A lower error here is not enough to show that the model will help on future days.'
                  : 'This is a test on past records. Future predictions provide a separate check of how the model performs as new days happen.',
            ),
            style: TextStyle(color: TonyoPalette.of(context).muted),
          ),
        ],
      ],
    ),
  );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.readiness, required this.run});
  final SleepEnergyReadiness readiness;
  final SleepEnergyRun? run;

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(
            'Compare sleep alone with sleep plus the previous day’s manually logged workout hours. For this historical comparison, the activity log must already have been saved when the paired sleep became available. Missing activity stays missing; it is never counted as zero.',
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.tr(
            'This comparison starts at 25 complete paired days in one matching group, including at least 5 test days. That is a minimum for running the test, not proof of enough evidence.',
          ),
        ),
        if (readiness.cohorts.isEmpty) ...[
          const SizedBox(height: 14),
          Text(context.tr('0 / 25 complete paired days')),
        ],
        for (final cohort in readiness.cohorts) ...[
          const Divider(height: 28),
          _Title(_source(context, cohort.sleepSource)),
          Text(cohort.timezone),
          const SizedBox(height: 6),
          Text(
            context.tr(
              '{count} / 25 complete paired days',
              args: {'count': cohort.activityPairCount},
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (cohort.activityPairCount / 25).clamp(0.0, 1.0),
            semanticsLabel: context.tr('Activity comparison readiness'),
          ),
          if (cohort.activityPairCount < 25) ...[
            const SizedBox(height: 8),
            Text(
              context.tr(
                'Keep logging workout hours on the day they happen, including an explicit zero on rest days. Save them before the following sleep is saved or synced.',
              ),
            ),
          ],
          for (final comparison
              in run?.activityComparisons ??
                  const <SleepEnergyActivityComparison>[])
            if (comparison.cohortKey == cohort.key) ...[
              const SizedBox(height: 12),
              if (comparison.blocker != null)
                Text(context.tr(_blocker(comparison.blocker)))
              else ...[
                Text(
                  context.tr(
                    'Saved comparison · {train} training days · {test} held-out days',
                    args: {
                      'train': comparison.trainingCount,
                      'test': comparison.holdoutCount,
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _Errors(
                  rows: [
                    ('Sleep alone', comparison.sleepOnlyMae),
                    (
                      'Sleep + previous-day activity',
                      comparison.sleepActivityMae,
                    ),
                    ('Training-days average', comparison.meanMae),
                    ('Last training rating', comparison.previousMae),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'Every method is tested on the same complete days.',
                  ),
                ),
              ],
            ],
        ],
      ],
    ),
  );
}

class _PredictionControls extends StatelessWidget {
  const _PredictionControls({
    required this.controller,
    required this.onLoggingChanged,
    required this.onRecord,
  });
  final AppController controller;
  final ValueChanged<bool> onLoggingChanged;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          key: const Key('sleep-energy-logging'),
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('Enable prediction logging')),
          value: controller.sleepEnergyLoggingEnabled,
          onChanged:
              controller.sleepEnergyBusy || !controller.sleepEnergyAvailable
              ? null
              : onLoggingChanged,
        ),
        Text(
          context.tr(
            'While enabled, Tonyo can save predictions when the app is open and after records are saved. Prediction capture pauses while a check-in form is open.',
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.tr(
            'You can also record one now, after sleep is available and before your first evening check-in. The model uses only earlier days and records already saved at that moment.',
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.tr(
            'The predicted rating stays hidden until you answer, so it does not influence your check-in.',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(
            'Turning logging off pauses new predictions and keeps your saved history. Use Remove experiment history to erase these results.',
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('sleep-energy-record-prediction'),
          onPressed:
              controller.sleepEnergyBusy ||
                  !controller.sleepEnergyAvailable ||
                  !controller.sleepEnergyLoggingEnabled
              ? null
              : onRecord,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(context.tr('Record prediction now')),
        ),
        const SizedBox(height: 10),
        Text(
          context.tr(controller.sleepEnergyPredictionStatus),
          key: const Key('sleep-energy-prediction-status'),
        ),
      ],
    ),
  );
}

class _ProspectiveResults extends StatelessWidget {
  const _ProspectiveResults({required this.results});
  final List<SleepEnergyPredictionEvaluation> results;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<SleepEnergyPredictionEvaluation>>{};
    for (final result in results) {
      groups.putIfAbsent(result.prediction.cohortKey, () => []).add(result);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (results.isEmpty)
          _Notice(
            key: const Key('sleep-energy-no-predictions'),
            text: context.tr(
              'No future-day predictions have been saved. Record one before an evening check-in to start a separate test on new days.',
            ),
          ),
        for (final group in groups.values) ...[
          _ProspectiveGroup(results: group),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ProspectiveGroup extends StatelessWidget {
  const _ProspectiveGroup({required this.results});
  final List<SleepEnergyPredictionEvaluation> results;

  @override
  Widget build(BuildContext context) {
    final scored = results.where((result) => result.scored).toList();
    final waiting = results
        .where((result) => result.status == 'awaiting_evening')
        .length;
    final ordered = results.toList()
      ..sort(
        (a, b) => b.prediction.localDate.compareTo(a.prediction.localDate),
      );
    final recent = ordered.take(7).toList();
    double? average(double? Function(SleepEnergyPredictionEvaluation) read) {
      if (scored.isEmpty) return null;
      final values = scored.map(read).whereType<double>().toList();
      if (values.length != scored.length) return null;
      return values.reduce((a, b) => a + b) / values.length;
    }

    return TonyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Title(_source(context, results.first.prediction.source)),
          Text(results.first.prediction.timezone),
          Text(context.tr('Recorded before the answer')),
          const SizedBox(height: 8),
          Text(
            context.tr(
              '{saved} saved · {scored} scored · {waiting} awaiting a check-in',
              args: {
                'saved': results.length,
                'scored': scored.length,
                'waiting': waiting,
              },
            ),
          ),
          if (scored.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Errors(
              rows: [
                ('Sleep model', average((result) => result.modelAbsoluteError)),
                (
                  'Training-days average',
                  average((result) => result.meanAbsoluteError),
                ),
                (
                  'Last training rating',
                  average((result) => result.lastAbsoluteError),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'All methods are compared on these same scored predictions. These comparison values are fixed from the training days. More future days are needed to judge consistency.',
              ),
            ),
          ],
          const Divider(height: 28),
          Text(context.tr('Recent prediction records')),
          for (final result in recent) ...[
            const SizedBox(height: 12),
            Text(
              result.prediction.localDate,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (result.scored) ...[
              Text(
                context.tr(
                  'Predicted Energy: {predicted} / 10 · evening answer: {actual} / 10',
                  args: {
                    'predicted': _number(result.prediction.modelPrediction),
                    'actual': _number(result.actual),
                  },
                ),
              ),
            ] else if (result.status == 'awaiting_evening')
              Text(
                context.tr('Prediction saved before check-in'),
                key: Key('sleep-energy-hidden-${result.prediction.id}'),
              )
            else if (result.status == 'pending_receipt')
              Text(
                context.tr('Waiting for the prediction save to be confirmed.'),
              )
            else
              Text(
                context.tr(
                  'Not scored: the required records are missing, changed or do not form a valid later check-in.',
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Errors extends StatelessWidget {
  const _Errors({required this.rows});
  final List<(String, double?)> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.tr('Average error · Energy points (1–10) · lower is better'),
        style: TextStyle(color: TonyoPalette.of(context).muted),
      ),
      const SizedBox(height: 8),
      for (final (label, value) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${context.tr(label)}: '),
                TextSpan(
                  text: _number(value),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: TonyoPalette.of(context).surfaceRaised,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$count ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: context.tr(label)),
        ],
      ),
    ),
  );
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(
    headingLevel: 2,
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => TonyoCard(child: Text(text));
}

String _source(BuildContext context, String source) =>
    context.tr(switch (source) {
      'healthKit' => 'Apple Health sleep',
      'manual' => 'Manually recorded sleep',
      _ => 'Recorded sleep',
    });

String _number(double? value) =>
    value != null && value.isFinite ? value.toStringAsFixed(2) : '—';

String _date(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String _blocker(String? reason) => switch (reason) {
  'fewer_than_two_training_rows' => 'Add more paired days so some can be used for training and a later day can be reserved for testing.',
  'no_sleep_variation_in_training' || 'unresolvable_training_sleep_variation' => 'The training days have the same sleep duration. Keep recording what actually happens; variation is needed to fit this model.',
  'fewer_than_25_complete_pairs' => 'Activity results will appear after at least 25 complete paired days and a new training run.',
  'fewer_than_five_holdout_rows' =>
    'At least five later days must be available for the activity test.',
  'insufficient_training_variation' => 'There is not enough independent variation in sleep and activity to fit this comparison yet.',
  _ => 'This group is not ready to train. Keep recording sleep and evening Energy on new days.',
};

String _exclusion(String reason) => switch (reason) {
  'incompatible_measurement_source_or_period' => 'Morning check-ins or responses with an unsupported question language or format',
  'later_compatible_response_same_date' =>
    'Later evening check-ins on a day already selected',
  'selected_first_response_missing_energy' =>
    'First evening check-in has no Energy answer',
  'selected_response_sleep_unmatched' => 'No matching main-sleep record',
  'sleep_availability_unknown' => 'Sleep save or import time is unknown',
  'invalid_response_date_timezone_or_timing' =>
    'Check-in date, time zone or save time cannot be verified',
  'sleep_already_selected_by_earlier_response' =>
    'Sleep record already used for an earlier day',
  'missing_or_invalid_definition' =>
    'Saved question wording is missing or unsupported',
  'selected_response_invalid_ratings_or_completeness' =>
    'Answer values or completion details are invalid',
  'selected_response_invalid_sleep' =>
    'Sleep source, duration or quality is unsupported',
  'selected_response_invalid_sleep_timing' =>
    'Sleep timing does not form a valid earlier match',
  'invalid_sleep_availability_metadata' =>
    'Sleep save or import time cannot be verified',
  'sleep_ended_after_response' => 'Sleep ended after the check-in',
  'sleep_ended_more_than_24_hours_before_response' =>
    'Sleep ended more than 24 hours before the check-in',
  'export_synthetic' => 'Demo or generated check-ins',
  'export_legacy' => 'Older check-ins without the required measurement details',
  'export_duplicate_id' => 'Repeated copies of a saved check-in',
  'export_conflicting_duplicate_id' =>
    'Conflicting copies of the same check-in',
  'export_invalid' => 'Incomplete or invalid measurement details',
  'export_unsupported_version' => 'Unsupported check-in version',
  'export_future_or_unavailable' =>
    'Check-in is not yet available at this time',
  _ => 'Records without all the required matching details',
};
