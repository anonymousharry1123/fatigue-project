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
              child: _RecommendationCard(item: item),
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
              'Grounded daily guidance from your recent patterns',
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
                  'Grounded daily guidance',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '$recommendationCount timed actions \u00b7 $alertCount active '
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
  const _RecommendationCard({required this.item});

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
            if (item.windowType case final window?)
              _SmallTag(label: '${_windowLabel(window).toUpperCase()} WINDOW'),
          ],
        ),
        const SizedBox(height: 10),
        _EvidenceSummary(evidence: item.evidence),
      ],
    ),
  );
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
  'Study' => Icons.menu_book_rounded,
  'Hydration' => Icons.water_drop_rounded,
  'Nap' => Icons.bedtime_rounded,
  'Training' => Icons.fitness_center_rounded,
  _ => Icons.spa_rounded,
};

Color _recommendationColor(String category) => switch (category) {
  'Study' => TonyoColors.amber,
  'Hydration' => TonyoColors.blue,
  'Training' => TonyoColors.coral,
  'Nap' => TonyoColors.violet,
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
