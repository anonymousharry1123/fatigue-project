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
        const SizedBox(height: 10),
        _DailyPlanReminders(controller: controller),
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
        Text(
          'Guidance is based on your recent Tonyo entries and is for general '
          'wellness only. It does not diagnose a medical condition. If symptoms '
          'are severe, unusual, or persistent, talk with a qualified clinician.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: TonyoPalette.of(context).muted,
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
            Text(
              'A prioritized morning-to-evening plan from your recent patterns',
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 12,
              ),
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
      color: TonyoPalette.of(context).surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MetricIcon(
            icon: Icons.chat_bubble_outline_rounded,
            color: TonyoPalette.of(context).primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Generated daily plan',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '$recommendationCount plan blocks \u00b7 $alertCount active '
                  '${alertCount == 1 ? 'flag' : 'flags'}',
                  style: TextStyle(
                    color: TonyoPalette.of(context).muted,
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
                      color: TonyoPalette.of(context).secondary,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        source,
                        style: TextStyle(
                          color: TonyoPalette.of(context).secondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
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
      color: TonyoPalette.of(context).secondary.withValues(alpha: .07),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.view_timeline_rounded,
                color: TonyoPalette.of(context).secondary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Morning-to-evening plan · $range',
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            feedbackCount == 0
                ? 'Follow the timeline with optional reminders, and share what helped to shape future plans.'
                : 'Your feedback helps prioritize future advice. Today’s blocks stay in time order.',
            style: TextStyle(
              color: TonyoPalette.of(context).secondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyPlanReminders extends StatefulWidget {
  const _DailyPlanReminders({required this.controller});
  final AppController controller;

  @override
  State<_DailyPlanReminders> createState() => _DailyPlanRemindersState();
}

class _DailyPlanRemindersState extends State<_DailyPlanReminders> {
  bool _saving = false;
  String? _error;

  Future<void> _change(bool enabled) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.setCoachPlanNotifications(enabled);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not update reminders. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final busy = _saving || controller.isNotificationSyncing;
    final supported = controller.notificationSchedulingSupported;
    final enabled = controller.coachPlanNotificationsEnabled;
    final count = controller.scheduledCoachNotificationCount;
    final error = _error ?? controller.notificationError;
    final status = !supported
        ? 'Scheduled reminders are unavailable on this device.'
        : busy
        ? 'Updating today’s reminders…'
        : error ??
              (!enabled
                  ? 'Daily plan reminders are off.'
                  : !controller.notificationsEnabled
                  ? 'Notifications are off. Enable them to receive your plan reminders.'
                  : count == 0
                  ? 'No upcoming plan reminders are scheduled.'
                  : '$count ${count == 1 ? 'reminder' : 'reminders'} scheduled for today.');
    return TonyoCard(
      key: const Key('coach-plan-reminders'),
      color: TonyoPalette.of(context).primary.withValues(alpha: .07),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const Key('coach-plan-reminder-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Daily plan reminders',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'A notification when each upcoming plan block starts.',
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 11,
                ),
              ),
              value: enabled,
              onChanged: supported && !busy ? _change : null,
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              status,
              key: const Key('coach-plan-reminder-summary'),
              style: TextStyle(
                color: error != null
                    ? TonyoPalette.of(context).warning
                    : TonyoPalette.of(context).muted,
                fontSize: 11,
              ),
            ),
          ),
          if (enabled && !controller.notificationsEnabled && supported) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('coach-enable-notifications'),
              onPressed: busy ? null : () => _change(true),
              icon: const Icon(Icons.notifications_outlined, size: 18),
              label: const Text('Enable notifications'),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Open Tonyo each day to refresh your plan and schedule today’s reminders. Notification permission is requested when you turn reminders on. Manage forecast alerts in Profile → Notifications.',
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 10,
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
      color: TonyoPalette.of(context).warning.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: TonyoPalette.of(context).warning.withValues(alpha: .3),
      ),
    ),
    child: Row(
      children: [
        Icon(
          Icons.cloud_off_rounded,
          color: TonyoPalette.of(context).warning,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: TonyoPalette.of(context).warning,
              fontSize: 11,
            ),
          ),
        ),
      ],
    ),
  );
}

class _NoRiskAlertsCard extends StatelessWidget {
  const _NoRiskAlertsCard();

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Row(
      children: [
        MetricIcon(
          icon: Icons.shield_rounded,
          color: TonyoPalette.of(context).secondary,
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No sustained pattern flagged',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 3),
              Text(
                'Tonyo checks the last seven days for recurring sleep, training, '
                'energy, and stress patterns.',
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 11,
                ),
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
    final color = _severityColor(alert.severity, context);
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
                        fontWeight: FontWeight.w700,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            alert.detail,
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EvidenceSummary(evidence: alert.evidence),
              const SizedBox(height: 8),
              TextButton.icon(
                key: ValueKey('dismiss-risk-${alert.id}'),
                onPressed: () => _saveCoachAction(
                  context,
                  () => controller.dismissRiskAlert(alert.id),
                ),
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
  Widget build(BuildContext context) => TonyoCard(
    child: Row(
      children: [
        MetricIcon(
          icon: Icons.insights_rounded,
          color: TonyoPalette.of(context).secondary,
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add recent entries to build your plan',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 3),
              Text(
                'Recommendations appear only when they can be linked to your '
                'forecast and supporting data.',
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 11,
                ),
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
              color: _recommendationColor(item.category, context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        item.timeLabel,
                        style: TextStyle(
                          color: TonyoPalette.of(context).secondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (item.priority == RecommendationPriority.important)
                        const _SmallTag(label: 'PRIORITY'),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          item.detail,
          style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 11),
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
              color: TonyoPalette.of(context).secondary.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.balance_rounded,
                  size: 14,
                  color: TonyoPalette.of(context).secondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reason,
                    style: TextStyle(
                      color: TonyoPalette.of(context).muted,
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

class _RecommendationActions extends StatefulWidget {
  const _RecommendationActions({required this.controller, required this.item});
  final AppController controller;
  final Recommendation item;

  @override
  State<_RecommendationActions> createState() => _RecommendationActionsState();
}

class _RecommendationActionsState extends State<_RecommendationActions> {
  bool _saving = false;

  Future<void> _save(bool helpful) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _saveCoachAction(
        context,
        () => widget.controller.setRecommendationFeedback(
          widget.item.id,
          helpful,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PlanReminderStatus(controller: widget.controller, item: item),
        const SizedBox(height: 12),
        Text(
          'Was this advice helpful? (optional)',
          style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              key: ValueKey('helpful-recommendation-${item.id}'),
              onPressed: _saving ? null : () => _save(true),
              icon: Icon(
                item.helpful == true
                    ? Icons.thumb_up_alt_rounded
                    : Icons.thumb_up_alt_outlined,
                size: 17,
              ),
              label: Text(item.helpful == true ? 'Helpful · saved' : 'Helpful'),
            ),
            OutlinedButton.icon(
              key: ValueKey('not-helpful-recommendation-${item.id}'),
              onPressed: _saving ? null : () => _save(false),
              icon: Icon(
                item.helpful == false
                    ? Icons.thumb_down_alt_rounded
                    : Icons.thumb_down_alt_outlined,
                size: 17,
              ),
              label: Text(
                item.helpful == false ? 'Not helpful · saved' : 'Not helpful',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlanReminderStatus extends StatelessWidget {
  const _PlanReminderStatus({required this.controller, required this.item});
  final AppController controller;
  final Recommendation item;

  @override
  Widget build(BuildContext context) {
    final scheduled = controller.notificationForRecommendation(item.id);
    final past =
        item.scheduledAt != null &&
        !item.scheduledAt!.isAfter(controller.currentTime);
    final String text;
    final bool active;
    if (past) {
      text = 'Time passed';
      active = false;
    } else if (!controller.notificationSchedulingSupported) {
      text = 'Reminders unavailable on this device';
      active = false;
    } else if (!controller.coachPlanNotificationsEnabled ||
        !controller.notificationsEnabled) {
      text = 'Reminders off';
      active = false;
    } else if (controller.isNotificationSyncing) {
      text = 'Updating reminder…';
      active = false;
    } else if (controller.notificationError != null) {
      text = 'Reminder not scheduled · check reminder settings';
      active = false;
    } else if (scheduled != null &&
        scheduled.scheduledAt.isAfter(controller.currentTime)) {
      text = 'Reminder scheduled · ${formatHour(scheduled.scheduledAt)}';
      active = true;
    } else {
      text = 'No reminder scheduled';
      active = false;
    }
    return Row(
      key: ValueKey('plan-reminder-status-${item.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          past
              ? Icons.history_rounded
              : active
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          color: active
              ? TonyoPalette.of(context).success
              : TonyoPalette.of(context).muted,
          size: 18,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: active
                  ? TonyoPalette.of(context).success
                  : TonyoPalette.of(context).muted,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _EvidenceSummary extends StatelessWidget {
  const _EvidenceSummary({required this.evidence});

  final List<ForecastEvidence> evidence;

  @override
  Widget build(BuildContext context) {
    if (evidence.isEmpty) {
      return Text(
        'Linked to recent private data',
        style: TextStyle(
          color: TonyoPalette.of(context).secondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
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
        Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.link_rounded,
            color: TonyoPalette.of(context).secondary,
            size: 13,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            labels.join(' \u00b7 '),
            style: TextStyle(
              color: TonyoPalette.of(context).secondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _saveCoachAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not save this change. Please try again.'),
      ),
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
      color: TonyoPalette.of(context).surfaceRaised,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: TonyoPalette.of(context).border),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: TonyoPalette.of(context).muted,
        fontSize: 8,
        fontWeight: FontWeight.w700,
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

Color _recommendationColor(String category, BuildContext context) =>
    switch (category) {
      'Deep work' => TonyoPalette.of(context).secondary,
      'Morning' => TonyoPalette.of(context).secondary,
      'Hydration' => TonyoPalette.of(context).primary,
      'Training' => TonyoPalette.of(context).primary,
      'Nap' => TonyoPalette.of(context).secondary,
      'Taper' || 'Evening' => TonyoPalette.of(context).secondary,
      _ => TonyoPalette.of(context).secondary,
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

Color _severityColor(AlertSeverity severity, BuildContext context) =>
    switch (severity) {
      AlertSeverity.info => TonyoPalette.of(context).primary,
      AlertSeverity.caution => TonyoPalette.of(context).warning,
      AlertSeverity.high => TonyoPalette.of(context).error,
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
