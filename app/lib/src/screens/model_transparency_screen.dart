import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../energy_model_summary.dart';
import '../ml_prep_models.dart';
import '../model_transparency_state.dart';
import '../score_explanation.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

/// A read-only view of the displayed score and already-loaded model metadata.
/// Opening this route never refreshes data, fits a model, or changes consent.
class ModelTransparencyScreen extends StatefulWidget {
  const ModelTransparencyScreen({
    super.key,
    required this.controller,
    this.initialHead = ScoreHead.energy,
  });

  final AppController controller;
  final ScoreHead initialHead;

  @override
  State<ModelTransparencyScreen> createState() =>
      _ModelTransparencyScreenState();
}

class _ModelTransparencyScreenState extends State<ModelTransparencyScreen> {
  late ScoreHead _head = widget.initialHead;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (widget.controller.isSignedOut) {
        return Scaffold(
          appBar: AppBar(title: const Text('Score guide')),
          body: const SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: _Notice(
                key: Key('transparency-signed-out'),
                icon: Icons.lock_outline_rounded,
                text:
                    'You are signed out. Return to the welcome screen to '
                    'sign in or start a local session before viewing scores.',
              ),
            ),
          ),
        );
      }
      final state = widget.controller.modelTransparency;
      final explanation = state.explanation(_head);
      final color = _head == ScoreHead.energy
          ? TonyoColors.violet
          : TonyoColors.blue;
      return Scaffold(
        appBar: AppBar(title: const Text('Score guide')),
        body: SafeArea(
          top: false,
          child: ListView(
            key: const Key('model-transparency-scroll'),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                'How your scores work',
                style: MediaQuery.textScalerOf(context).scale(1) > 1.5
                    ? Theme.of(context).textTheme.headlineMedium
                    : Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'See what shaped this estimate, what is missing, and which '
                'model is actually being used.',
                style: TextStyle(color: TonyoColors.muted, height: 1.5),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final head in ScoreHead.values)
                    ChoiceChip(
                      key: Key('transparency-head-${head.name}'),
                      label: Text(head.label),
                      labelStyle: const TextStyle(color: TonyoColors.text),
                      avatar: Icon(
                        head == ScoreHead.energy
                            ? Icons.bolt_rounded
                            : Icons.psychology_outlined,
                        size: 20,
                        color: _head == head ? color : TonyoColors.muted,
                      ),
                      selected: _head == head,
                      selectedColor: color.withValues(alpha: .2),
                      side: BorderSide(
                        color: _head == head ? color : TonyoColors.border,
                      ),
                      onSelected: (_) => setState(() => _head = head),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      showCheckmark: false,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _ScoreOverview(
                explanation: explanation,
                head: _head,
                state: state,
                color: color,
              ),
              if (state.loading) ...[
                const SizedBox(height: 12),
                const _Notice(
                  icon: Icons.hourglass_top_rounded,
                  text:
                      'The score is updating. These details describe the '
                      'estimate currently displayed.',
                ),
              ],
              if (state.offline) ...[
                const SizedBox(height: 12),
                const _Notice(
                  icon: Icons.cloud_off_rounded,
                  text:
                      'Cloud sync is unavailable. Cached inputs and metadata '
                      'may not include changes made on another device.',
                ),
              ],
              const SizedBox(height: 24),
              const SectionHeader('How much evidence is behind it?'),
              _EvidenceQuality(explanation: explanation, color: color),
              const SizedBox(height: 24),
              const SectionHeader('What shaped this score'),
              const Text(
                'Largest point adjustments first. Tap a factor for its saved '
                'explanation and source. These are model contributions, '
                'not proof that an activity caused a change.',
                style: TextStyle(color: TonyoColors.muted, height: 1.5),
              ),
              const SizedBox(height: 12),
              if (explanation.drivers.isEmpty)
                const _Notice(
                  key: Key('transparency-no-drivers'),
                  icon: Icons.notes_rounded,
                  text:
                      'No factor details were saved for this estimate. '
                      'They cannot be reconstructed reliably from the score '
                      'alone.',
                ),
              for (var index = 0; index < explanation.drivers.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DriverTile(
                    key: ValueKey('${_head.name}-driver-$index'),
                    index: index,
                    explained: explanation.drivers[index],
                    color: color,
                  ),
                ),
              const SizedBox(height: 18),
              const SectionHeader('The evidence, at a glance'),
              Text(
                '${explanation.availableEvidenceCount} of '
                '${explanation.expectedEvidenceCount} factor categories have '
                'saved evidence. This inventory is separate from the score’s '
                'historical input counter.',
                style: const TextStyle(color: TonyoColors.muted, height: 1.5),
              ),
              const SizedBox(height: 12),
              TonyoCard(
                key: const Key('transparency-input-inventory'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var index = 0;
                      index < explanation.inputs.length;
                      index++
                    ) ...[
                      if (index != 0)
                        const Divider(height: 1, color: TonyoColors.border),
                      _EvidenceRow(input: explanation.inputs[index]),
                    ],
                    if (explanation.inputs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No input evidence was recorded.'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const SectionHeader('Model & update history'),
              _ModelDetails(state: state, head: _head),
              const SizedBox(height: 24),
              const SectionHeader('Keep in mind'),
              TonyoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (
                      var index = 0;
                      index < explanation.caveats.length;
                      index++
                    )
                      Padding(
                        padding: EdgeInsets.only(top: index == 0 ? 0 : 14),
                        child: Text(
                          explanation.caveats[index],
                          style: const TextStyle(
                            color: TonyoColors.muted,
                            height: 1.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'This page only explains information already on this device. '
                'Opening it does not fetch records, train a model, or change '
                'your settings.',
                style: TextStyle(color: TonyoColors.muted, height: 1.5),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ScoreOverview extends StatelessWidget {
  const _ScoreOverview({
    required this.explanation,
    required this.head,
    required this.state,
    required this.color,
  });

  final ScoreExplanation explanation;
  final ScoreHead head;
  final ModelTransparencyState state;
  final Color color;

  @override
  Widget build(BuildContext context) => TonyoCard(
    key: const Key('transparency-score-overview'),
    color: color.withValues(alpha: .08),
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Badge(label: '${head.label} estimate', color: color),
        const SizedBox(height: 12),
        Semantics(
          label: explanation.value == null
              ? '${head.label} score not recorded'
              : '${head.label} score ${explanation.value} out of 100',
          excludeSemantics: true,
          child: Text(
            explanation.value?.toString() ?? '—',
            key: const Key('transparency-score-value'),
            style: TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          explanation.value == null
              ? 'Not recorded in this saved snapshot'
              : 'out of 100 · higher means more estimated capacity',
          style: const TextStyle(color: TonyoColors.muted, height: 1.5),
        ),
        const SizedBox(height: 16),
        _Detail(
          label: 'Scoring mode',
          value: head == ScoreHead.energy
              ? state.modelStatusTitle
              : 'Deterministic Cognitive model',
        ),
        const SizedBox(height: 8),
        Text(
          head == ScoreHead.energy
              ? state.energyModelVersion
              : state.cognitiveModelVersion,
          style: const TextStyle(color: TonyoColors.muted, height: 1.5),
        ),
        const SizedBox(height: 16),
        Text(state.scoreSourceLabel),
        const SizedBox(height: 4),
        Text(
          'Score calculated: ${_timestamp(context, explanation.calculatedAt)}',
          style: const TextStyle(color: TonyoColors.muted, height: 1.5),
        ),
        const SizedBox(height: 14),
        const Text(
          'A wellness estimate for daily planning, not a diagnosis or '
          'a measure of your worth.',
          style: TextStyle(color: TonyoColors.muted, height: 1.5),
        ),
      ],
    ),
  );
}

class _EvidenceQuality extends StatelessWidget {
  const _EvidenceQuality({required this.explanation, required this.color});
  final ScoreExplanation explanation;
  final Color color;

  @override
  Widget build(BuildContext context) => explanation.value == null
      ? const _Notice(
          icon: Icons.help_outline_rounded,
          text:
              'Confidence and input coverage were not recorded for this '
              'missing score. They are not treated as zero.',
        )
      : TonyoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${explanation.confidencePercent}% confidence',
                key: const Key('transparency-confidence'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              Text(explanation.confidenceLabel, style: TextStyle(color: color)),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: explanation.confidencePercent / 100,
                color: color,
                backgroundColor: TonyoColors.border,
                minHeight: 5,
                borderRadius: BorderRadius.circular(5),
                semanticsLabel: 'Evidence quality',
              ),
              const SizedBox(height: 16),
              const Text(
                'Confidence describes the evidence available to the model. '
                'It is not the probability that this score is correct.',
                style: TextStyle(height: 1.5),
              ),
              const Divider(height: 32, color: TonyoColors.border),
              _Detail(
                label: 'Score inputs',
                value:
                    '${explanation.inputCount} / ${explanation.inputTotal} '
                    'in the saved completeness counter',
              ),
              const SizedBox(height: 14),
              _Detail(
                label: 'Evidence freshness when calculated',
                value: explanation.freshness == null
                    ? 'Not recorded'
                    : '${(explanation.freshness! * 100).round()}% · '
                          'freshness at the saved calculation',
              ),
              const SizedBox(height: 16),
              const Text(
                'More records alone may not raise confidence. Coverage across useful '
                'inputs, their freshness, and personal-baseline readiness matter. '
                'Refreshing the personalized model does not increase confidence.',
                style: TextStyle(color: TonyoColors.muted, height: 1.5),
              ),
            ],
          ),
        );
}

class _DriverTile extends StatelessWidget {
  const _DriverTile({
    super.key,
    required this.index,
    required this.explained,
    required this.color,
  });
  final int index;
  final ExplainedDriver explained;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final driver = explained.driver;
    return Material(
      color: TonyoColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: TonyoColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: Key('transparency-driver-$index'),
          maintainState: true,
          tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          title: Text(
            driver.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Badge(label: explained.contributionLabel, color: color),
                _Badge(
                  label: explained.kind.label,
                  color: _evidenceColor(explained.kind),
                ),
              ],
            ),
          ),
          children: [
            if (driver.detail.isNotEmpty) ...[
              Text(driver.detail, style: const TextStyle(height: 1.5)),
              const SizedBox(height: 12),
            ],
            Text(
              driver.explanation.isEmpty
                  ? 'No additional explanation was saved for this factor.'
                  : driver.explanation,
              style: const TextStyle(color: TonyoColors.muted, height: 1.5),
            ),
            const Divider(height: 28, color: TonyoColors.border),
            _Detail(label: 'Source', value: explained.sourceLabel),
            const SizedBox(height: 12),
            _Detail(label: 'Freshness', value: explained.freshnessLabel),
            const SizedBox(height: 12),
            _Detail(
              label: 'Evidence observed',
              value: _timestamp(context, driver.evidenceAt),
            ),
          ],
        ),
      ),
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.input});
  final ScoreInputEvidence input;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(input.label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _Badge(label: input.kind.label, color: _evidenceColor(input.kind)),
        const SizedBox(height: 8),
        Text(input.detail, style: const TextStyle(height: 1.5)),
        const SizedBox(height: 4),
        Text(
          input.sourceLabel,
          style: const TextStyle(color: TonyoColors.muted, height: 1.5),
        ),
        if (input.evidenceAt != null) ...[
          const SizedBox(height: 4),
          Text(
            _timestamp(context, input.evidenceAt),
            style: const TextStyle(color: TonyoColors.muted, height: 1.5),
          ),
        ],
      ],
    ),
  );
}

class _ModelDetails extends StatelessWidget {
  const _ModelDetails({required this.state, required this.head});
  final ModelTransparencyState state;
  final ScoreHead head;

  @override
  Widget build(BuildContext context) => TonyoCard(
    key: const Key('transparency-model-details'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          head == ScoreHead.energy
              ? state.modelStatusTitle
              : 'Deterministic Cognitive model',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          head == ScoreHead.energy
              ? state.modelStatusDetail
              : 'Cognitive uses the rule-based score model. The personalized '
                    'Energy model does not change this score.',
          style: const TextStyle(color: TonyoColors.muted, height: 1.5),
        ),
        const Divider(height: 32, color: TonyoColors.border),
        _Detail(
          label: 'Score model version',
          value: head == ScoreHead.energy
              ? state.energyModelVersion
              : state.cognitiveModelVersion,
        ),
        const SizedBox(height: 16),
        _Detail(
          label: 'Firebase metadata loaded on this device',
          value: state.metadataFetchedAt == null
              ? 'Not loaded'
              : _timestamp(context, state.metadataFetchedAt),
        ),
        const SizedBox(height: 16),
        _Detail(
          label: 'Account metadata updated',
          value: _timestamp(context, state.accountUpdatedAt),
        ),
        if (head == ScoreHead.energy) ...[
          const Divider(height: 32, color: TonyoColors.border),
          if (state.localModel case final model?)
            _ModelSummary(
              key: const Key('transparency-local-model'),
              title: 'Model available on this device',
              summary: model,
              description:
                  'The model weights stay on this device. Availability '
                  'does not mean a correction was used for every score.',
            )
          else
            const _Detail(
              label: 'Model available on this device',
              value:
                  'No usable personalized model. The deterministic estimate '
                  'remains available.',
            ),
          const Divider(height: 32, color: TonyoColors.border),
          if (state.cloudModel case final summary?)
            _ModelSummary(
              key: const Key('transparency-cloud-model'),
              title: 'Firebase model summary',
              summary: summary,
              description:
                  'Summary only — not downloadable model weights. '
                  'This is the last metadata loaded, not proof that this '
                  'device is using that model.',
            )
          else
            const _Detail(
              label: 'Firebase model summary',
              value:
                  'No valid summary loaded. This does not prove that no '
                  'model exists on another device.',
            ),
        ],
        if (state.notices.isNotEmpty) ...[
          const Divider(height: 32, color: TonyoColors.border),
          Text(
            'About this saved view',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final notice in state.notices) ...[
            const SizedBox(height: 12),
            Text(
              notice,
              style: const TextStyle(color: TonyoColors.muted, height: 1.5),
            ),
          ],
        ],
      ],
    ),
  );
}

class _ModelSummary extends StatelessWidget {
  const _ModelSummary({
    super.key,
    required this.title,
    required this.summary,
    required this.description,
  });
  final String title;
  final EnergyModelSummary summary;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        description,
        style: const TextStyle(color: TonyoColors.muted, height: 1.5),
      ),
      const SizedBox(height: 16),
      _Detail(
        label: 'Model version',
        value: 'Energy residual v${summary.modelVersion}',
      ),
      const SizedBox(height: 14),
      _Detail(
        label: 'Model trained',
        value: _timestamp(context, summary.trainedAt),
      ),
      const SizedBox(height: 14),
      _Detail(
        label: 'Training evidence',
        value:
            '${summary.labelCount} eligible outcomes · '
            '30-day window (${summary.timezone})',
      ),
      const SizedBox(height: 14),
      _Detail(
        label: 'Training window',
        value: _trainingWindow(context, summary),
      ),
      const SizedBox(height: 14),
      _Detail(
        label: 'Held-out error',
        value:
            '${summary.holdoutMae.toStringAsFixed(1)} points, compared with '
            '${summary.deterministicMae.toStringAsFixed(1)} for the baseline. '
            'This describes the held-out days, not a guarantee for today.',
      ),
      const SizedBox(height: 14),
      _Detail(
        label: 'Held-out error reduction',
        value:
            '${summary.improvementPercent.toStringAsFixed(1)}% lower '
            'error in the held-out days. Not an increase in confidence.',
      ),
    ],
  );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: TonyoColors.muted, height: 1.5),
      ),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(height: 1.5)),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: TonyoColors.blue, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, height: 1.35),
    ),
  );
}

Color _evidenceColor(EvidenceKind kind) => switch (kind) {
  EvidenceKind.measured => TonyoColors.mint,
  EvidenceKind.selfReported => TonyoColors.blue,
  EvidenceKind.estimated => TonyoColors.violet,
  EvidenceKind.missing => TonyoColors.muted,
  EvidenceKind.demo => TonyoColors.amber,
  EvidenceKind.unknown => TonyoColors.amber,
};

String _timestamp(BuildContext context, DateTime? value) {
  if (value == null) return 'Not recorded';
  final local = value.toLocal();
  final formats = MaterialLocalizations.of(context);
  final date = '${formats.formatMediumDate(local)}, ${local.year}';
  final time = formats.formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '$date · $time ${local.timeZoneName}'.trim();
}

String _trainingWindow(BuildContext context, EnergyModelSummary summary) {
  final window = PrepWindow.fromJson({
    'start': summary.windowStart.toIso8601String(),
    'end': summary.windowEnd.toIso8601String(),
    'timezone': summary.timezone,
  });
  final formats = MaterialLocalizations.of(context);
  final first = formats.formatShortDate(window.localTime(window.start));
  final last = formats.formatShortDate(
    window.localTime(window.end.subtract(const Duration(microseconds: 1))),
  );
  return '$first – $last (${summary.timezone})';
}
