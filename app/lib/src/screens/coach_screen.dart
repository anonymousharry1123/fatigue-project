import 'package:flutter/material.dart';

import '../app.dart';
import '../app_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class CoachScreen extends StatelessWidget {
  const CoachScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final content = ListView(
      key: embedded ? const PageStorageKey('coach-scroll') : null,
      padding: EdgeInsets.fromLTRB(20, embedded ? 20 : 8, 20, 28),
      children: [
        if (embedded) ...[
          _CoachHeader(controller: controller),
          const SizedBox(height: 14),
        ],
        if (controller.isGuidanceLoading) ...[
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 12),
        ],
        _GuidanceSummary(controller: controller),
        const SizedBox(height: 10),
        _DailyPlanOverview(controller: controller),
        if (controller.guidanceError case final error?) ...[
          const SizedBox(height: 10),
          _GuidanceNotice(message: error),
        ],
        const SectionHeader('Wellness flags'),
        if (controller.alerts.isEmpty)
          const _NoRiskAlertsCard()
        else
          ...controller.alerts.map(
            (alert) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RiskAlertCard(controller: controller, alert: alert),
            ),
          ),
        const SectionHeader('Today\u2019s plan'),
        if (controller.recommendations.isEmpty)
          const _NoRecommendationsCard()
        else
          ...controller.recommendations.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RecommendationCard(controller: controller, item: item),
            ),
          ),
        const SizedBox(height: 14),
        const Text(
          'Guidance is based on your recent Tonyo entries and is for general '
          'wellness only. It does not diagnose a medical condition. If symptoms '
          'are severe, unusual, or persistent, talk with a qualified clinician.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: TonyoColors.muted,
            fontSize: 10,
            height: 1.45,
          ),
        ),
      ],
    );
    if (embedded) {
      return SafeArea(bottom: false, child: content);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Coach'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh guidance',
            onPressed: controller.isGuidanceLoading
                ? null
                : controller.refreshGuidance,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: content,
    );
  }
}

class _CoachHeader extends StatelessWidget {
  const _CoachHeader({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AI Coach', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 5),
            const Text(
              'A prioritized morning-to-evening plan from your recent patterns',
              style: TextStyle(color: TonyoColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      IconButton.filledTonal(
        tooltip: 'Refresh guidance',
        onPressed: controller.isGuidanceLoading
            ? null
            : controller.refreshGuidance,
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
  );
}

class _GuidanceSummary extends StatelessWidget {
  const _GuidanceSummary({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final recommendationCount = controller.recommendations.length;
    final alertCount = controller.alerts.length;
    final source = controller.guidanceSavedToCloud
        ? 'Private guidance saved to your account'
        : 'Calculated privately on this device';
    return TonyoCard(
      color: const Color(0xFF171524),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MetricIcon(
            icon: Icons.auto_awesome_rounded,
            color: TonyoColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Generated daily plan',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '$recommendationCount plan blocks \u00b7 $alertCount active '
                  '${alertCount == 1 ? 'flag' : 'flags'}',
                  style: const TextStyle(
                    color: TonyoColors.muted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Icon(
                      controller.guidanceSavedToCloud
                          ? Icons.lock_rounded
                          : Icons.phone_iphone_rounded,
                      size: 13,
                      color: TonyoColors.mint,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        source,
                        style: const TextStyle(
                          color: TonyoColors.mint,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyPlanOverview extends StatelessWidget {
  const _DailyPlanOverview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final plan = controller.recommendations;
    final feedbackCount = controller.recommendationFeedbackHistoryCount;
    final confidence = plan.firstOrNull?.planConfidence;
    final range = plan.isEmpty
        ? 'Waiting for grounded forecast windows'
        : '${plan.first.timeLabel}–${plan.last.timeLabel}';
    return TonyoCard(
      key: const Key('coach-daily-plan-summary'),
      color: TonyoColors.violet.withValues(alpha: .07),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.view_timeline_rounded,
                color: TonyoColors.violet,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Morning-to-evening plan · $range',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _SmallTag(
                label: controller.profile.coachPriority.label.toUpperCase(),
              ),
              if (confidence != null)
                _SmallTag(
                  label: '${(confidence * 100).round()}% PLAN CONFIDENCE',
                ),
              if (feedbackCount > 0)
                _SmallTag(label: '$feedbackCount PAST RESPONSES'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            controller.profile.coachPriority.detail,
            style: const TextStyle(color: TonyoColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 5),
          Text(
            feedbackCount == 0
                ? 'Complete or dismiss blocks and share what helped. Future plans will learn from those responses.'
                : 'Past responses now adjust each block’s feedback rank and importance; the timeline stays chronological.',
            style: const TextStyle(color: TonyoColors.mint, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _GuidanceNotice extends StatelessWidget {
  const _GuidanceNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: TonyoColors.amber.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: TonyoColors.amber.withValues(alpha: .3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_rounded, color: TonyoColors.amber, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: TonyoColors.amber, fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _NoRiskAlertsCard extends StatelessWidget {
  const _NoRiskAlertsCard();

  @override
  Widget build(BuildContext context) => const TonyoCard(
    child: Row(
      children: [
        MetricIcon(icon: Icons.shield_rounded, color: TonyoColors.mint),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No sustained pattern flagged',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 3),
              Text(
                'Tonyo checks the last seven days for recurring sleep, training, '
                'energy, and stress patterns.',
                style: TextStyle(color: TonyoColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RiskAlertCard extends StatelessWidget {
  const _RiskAlertCard({required this.controller, required this.alert});

  final AppController controller;
  final RiskAlert alert;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(alert.severity);
    return TonyoCard(
      key: ValueKey('risk-alert-${alert.id}'),
      color: color.withValues(alpha: .07),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MetricIcon(
                icon: _riskIcon(alert.category),
                color: color,
                size: 38,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _riskLabel(alert.category).toUpperCase(),
                      style: TextStyle(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            alert.detail,
            style: const TextStyle(color: TonyoColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _EvidenceSummary(evidence: alert.evidence)),
              const SizedBox(width: 8),
              TextButton.icon(
                key: ValueKey('dismiss-risk-${alert.id}'),
                onPressed: () => controller.dismissRiskAlert(alert.id),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoRecommendationsCard extends StatelessWidget {
  const _NoRecommendationsCard();

  @override
  Widget build(BuildContext context) => const TonyoCard(
    child: Row(
      children: [
        MetricIcon(icon: Icons.insights_rounded, color: TonyoColors.violet),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add recent entries to build your plan',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 3),
              Text(
                'Recommendations appear only when they can be linked to your '
                'forecast and supporting data.',
                style: TextStyle(color: TonyoColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.controller, required this.item});

  final AppController controller;
  final Recommendation item;

  @override
  Widget build(BuildContext context) => TonyoCard(
    key: ValueKey('recommendation-${item.id}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MetricIcon(
              icon: _recommendationIcon(item.category),
              color: _recommendationColor(item.category),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.timeLabel,
                          style: const TextStyle(
                            color: TonyoColors.violet,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (item.priority == RecommendationPriority.important)
                        const _SmallTag(label: 'PRIORITY'),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          item.detail,
          style: const TextStyle(color: TonyoColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _SmallTag(label: item.category.toUpperCase()),
            if (item.planPhase case final phase?)
              _SmallTag(label: _phaseLabel(phase).toUpperCase()),
            if (item.durationMinutes case final duration?)
              _SmallTag(label: '$duration MIN'),
            if (item.windowType case final window?)
              _SmallTag(label: '${_windowLabel(window).toUpperCase()} WINDOW'),
          ],
        ),
        const SizedBox(height: 10),
        if (item.decisionReason case final reason?) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: TonyoColors.violet.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.balance_rounded,
                  size: 14,
                  color: TonyoColors.violet,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reason,
                    style: const TextStyle(
                      color: TonyoColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        _EvidenceSummary(evidence: item.evidence),
        const SizedBox(height: 12),
        _RecommendationActions(controller: controller, item: item),
      ],
    ),
  );
}

class _RecommendationActions extends StatelessWidget {
  const _RecommendationActions({required this.controller, required this.item});

  final AppController controller;
  final Recommendation item;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (item.status) {
      RecommendationStatus.suggested => 'SUGGESTED',
      RecommendationStatus.accepted => 'ACCEPTED',
      RecommendationStatus.completed => 'COMPLETED',
      RecommendationStatus.dismissed => 'DISMISSED',
    };
    final canRate =
        item.status == RecommendationStatus.completed ||
        item.status == RecommendationStatus.dismissed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _SmallTag(label: statusLabel),
            if (item.feedbackSampleCount > 0)
              _SmallTag(
                label: item.feedbackRank == 1
                    ? 'TOP FEEDBACK MATCH'
                    : '#${item.feedbackRank} FEEDBACK MATCH',
              ),
            if (item.feedbackSampleCount > 0)
              _SmallTag(
                label:
                    '${(item.feedbackScore * 100).round()}% · ${item.feedbackSampleCount} ${item.feedbackSampleCount == 1 ? 'RESPONSE' : 'RESPONSES'}',
              ),
          ],
        ),
        if (item.status == RecommendationStatus.suggested) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                key: ValueKey('accept-recommendation-${item.id}'),
                onPressed: () async {
                  await controller.setRecommendationStatus(
                    item.id,
                    RecommendationStatus.accepted,
                  );
                },
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Accept'),
              ),
              TextButton.icon(
                key: ValueKey('dismiss-recommendation-${item.id}'),
                onPressed: () async {
                  await controller.setRecommendationStatus(
                    item.id,
                    RecommendationStatus.dismissed,
                  );
                },
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Dismiss'),
              ),
            ],
          ),
        ] else if (item.status == RecommendationStatus.accepted) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                key: ValueKey('complete-recommendation-${item.id}'),
                onPressed: () async {
                  await controller.setRecommendationStatus(
                    item.id,
                    RecommendationStatus.completed,
                  );
                },
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: const Text('Complete'),
              ),
              TextButton.icon(
                key: ValueKey('dismiss-recommendation-${item.id}'),
                onPressed: () async {
                  await controller.setRecommendationStatus(
                    item.id,
                    RecommendationStatus.dismissed,
                  );
                },
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Dismiss'),
              ),
            ],
          ),
        ],
        if (canRate) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Was this advice helpful?',
                  style: TextStyle(
                    color: TonyoColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton.filledTonal(
                key: ValueKey('helpful-recommendation-${item.id}'),
                tooltip: 'Helpful',
                isSelected: item.helpful == true,
                onPressed: () =>
                    controller.setRecommendationFeedback(item.id, true),
                icon: const Icon(Icons.thumb_up_alt_outlined, size: 17),
                selectedIcon: const Icon(Icons.thumb_up_alt_rounded, size: 17),
              ),
              const SizedBox(width: 5),
              IconButton.filledTonal(
                key: ValueKey('not-helpful-recommendation-${item.id}'),
                tooltip: 'Not helpful',
                isSelected: item.helpful == false,
                onPressed: () =>
                    controller.setRecommendationFeedback(item.id, false),
                icon: const Icon(Icons.thumb_down_alt_outlined, size: 17),
                selectedIcon: const Icon(
                  Icons.thumb_down_alt_rounded,
                  size: 17,
                ),
              ),
            ],
          ),
        ],
        if (item.status == RecommendationStatus.completed) ...[
          const SizedBox(height: 9),
          if (!controller.outcomeConsent)
            const Text(
              'Outcome learning is off. No training record will be created.',
              key: Key('coach-outcome-consent-off'),
              style: TextStyle(color: TonyoColors.muted, fontSize: 10),
            )
          else if (controller.outcomeForRecommendation(item.id)
              case final outcome?)
            Container(
              key: ValueKey('recommendation-outcome-${item.id}'),
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: TonyoColors.mint.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                'Observed energy ${outcome.value.round()}/10 saved privately',
                style: const TextStyle(
                  color: TonyoColors.mint,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else
            OutlinedButton.icon(
              key: ValueKey('record-outcome-${item.id}'),
              onPressed: () => _recordObservedEnergy(context, controller, item),
              icon: const Icon(Icons.bolt_rounded, size: 16),
              label: const Text('Log observed energy'),
            ),
        ],
      ],
    );
  }

  static Future<void> _recordObservedEnergy(
    BuildContext context,
    AppController controller,
    Recommendation item,
  ) async {
    var energy = 6.0;
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Observed energy'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Optional: how energized did you feel after this completed block?',
              ),
              const SizedBox(height: 12),
              Text(
                '${energy.round()}/10',
                key: const Key('observed-energy-value'),
                style: const TextStyle(
                  color: TonyoColors.mint,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Slider(
                key: const Key('observed-energy-slider'),
                value: energy,
                min: 1,
                max: 10,
                divisions: 9,
                label: energy.round().toString(),
                onChanged: (value) => setState(() => energy = value),
              ),
              const Text(
                'Saved only because outcome learning is on. This release does not train a personalized model.',
                style: TextStyle(color: TonyoColors.muted, fontSize: 10),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Skip'),
            ),
            FilledButton(
              key: const Key('save-observed-energy'),
              onPressed: () => Navigator.pop(dialogContext, energy),
              child: const Text('Save outcome'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await controller.recordObservedEnergy(result, recommendationId: item.id);
  }
}

class _EvidenceSummary extends StatelessWidget {
  const _EvidenceSummary({required this.evidence});

  final List<ForecastEvidence> evidence;

  @override
  Widget build(BuildContext context) {
    if (evidence.isEmpty) {
      return const Text(
        'Linked to recent private data',
        style: TextStyle(
          color: TonyoColors.mint,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    final labels = evidence
        .take(2)
        .map((item) => item.label)
        .toList(growable: true);
    if (evidence.length > 2) labels.add('+${evidence.length - 2} more');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.link_rounded, color: TonyoColors.mint, size: 13),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            labels.join(' \u00b7 '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: TonyoColors.mint,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _SmallTag extends StatelessWidget {
  const _SmallTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: TonyoColors.surfaceRaised,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: TonyoColors.border),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: TonyoColors.muted,
        fontSize: 8,
        fontWeight: FontWeight.w900,
        letterSpacing: .35,
      ),
    ),
  );
}

IconData _recommendationIcon(String category) => switch (category) {
  'Deep work' => Icons.menu_book_rounded,
  'Morning' => Icons.wb_sunny_outlined,
  'Hydration' => Icons.water_drop_rounded,
  'Nap' => Icons.bedtime_rounded,
  'Taper' => Icons.bedtime_outlined,
  'Evening' => Icons.nightlight_round,
  'Training' => Icons.fitness_center_rounded,
  _ => Icons.spa_rounded,
};

Color _recommendationColor(String category) => switch (category) {
  'Deep work' => TonyoColors.amber,
  'Morning' => TonyoColors.amber,
  'Hydration' => TonyoColors.blue,
  'Training' => TonyoColors.coral,
  'Nap' => TonyoColors.violet,
  'Taper' || 'Evening' => TonyoColors.violet,
  _ => TonyoColors.mint,
};

IconData _riskIcon(RiskAlertCategory category) => switch (category) {
  RiskAlertCategory.sleepDebt => Icons.bedtime_rounded,
  RiskAlertCategory.trainingLoad => Icons.monitor_heart_rounded,
  RiskAlertCategory.fatigueStress => Icons.psychology_alt_rounded,
};

String _riskLabel(RiskAlertCategory category) => switch (category) {
  RiskAlertCategory.sleepDebt => 'Sleep pattern',
  RiskAlertCategory.trainingLoad => 'Training pattern',
  RiskAlertCategory.fatigueStress => 'Energy and stress pattern',
};

Color _severityColor(AlertSeverity severity) => switch (severity) {
  AlertSeverity.info => TonyoColors.blue,
  AlertSeverity.caution => TonyoColors.amber,
  AlertSeverity.high => TonyoColors.coral,
};

String _windowLabel(ForecastWindowType type) => switch (type) {
  ForecastWindowType.peak => 'Peak',
  ForecastWindowType.crash => 'Crash',
  ForecastWindowType.recovery => 'Recovery',
};

String _phaseLabel(CoachPlanPhase phase) => switch (phase) {
  CoachPlanPhase.morning => 'Morning',
  CoachPlanPhase.deepWork => 'Deep work',
  CoachPlanPhase.midday => 'Midday',
  CoachPlanPhase.nap => 'Nap',
  CoachPlanPhase.training => 'Training',
  CoachPlanPhase.recovery => 'Recovery',
  CoachPlanPhase.taper => 'Taper',
  CoachPlanPhase.evening => 'Evening',
};
