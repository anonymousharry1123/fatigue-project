import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';
import '../theme.dart';
import '../today_dashboard_logic.dart';
import '../widgets/common_widgets.dart';
import '../widgets/personal_baseline_card.dart';
import 'model_transparency_screen.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.onOpenProfile});

  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final score = controller.score;
    final status = TodayDashboardLogic.statusFor(score.energy);
    final statusColor = _statusColor(status, context);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        key: const PageStorageKey('today-scroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            sliver: SliverList.list(
              children: [
                _Header(
                  name: controller.profile.name,
                  onOpenProfile: onOpenProfile,
                ),
                const SizedBox(height: 18),
                TonyoCard(
                  key: const Key('energy-score-card'),
                  padding: const EdgeInsets.all(18),
                  color: TonyoPalette.of(context).surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: statusColor.withValues(alpha: .28),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    status.label.toUpperCase(),
                                    key: const Key('fatigue-status'),
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: .7,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                controller.scoreLoadedFromSnapshot
                                    ? Icons.cloud_done_rounded
                                    : Icons.chat_bubble_outline_rounded,
                                color: TonyoPalette.of(context).muted,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  controller.scoreLoadedFromSnapshot
                                      ? 'Saved snapshot'
                                      : 'Live estimate',
                                  style: TextStyle(
                                    color: TonyoPalette.of(context).muted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        status.label,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status.detail,
                        style: TextStyle(
                          color: TonyoPalette.of(context).muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(
                          color: TonyoPalette.of(context).border,
                          height: 1,
                        ),
                      ),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stackScores =
                              constraints.maxWidth <
                              240 * MediaQuery.textScalerOf(context).scale(1);
                          final energy = _ScoreTile(
                            value: score.energy,
                            label: 'Energy',
                            eyebrow: 'ESTIMATED ENERGY SCORE',
                            completeness: _confidenceLine(
                              '${score.inputCount}/7 inputs',
                              score.confidence,
                              score.freshness,
                            ),
                            color: TonyoPalette.of(context).primary,
                          );
                          final cognitive = _ScoreTile(
                            key: const Key('cognitive-score-card'),
                            value: score.cognitive,
                            label: 'Cognitive',
                            eyebrow: 'ESTIMATED COGNITIVE SCORE',
                            completeness: _confidenceLine(
                              '${score.cognitiveInputCount}/6 cognitive inputs',
                              score.cognitiveConfidence,
                              score.cognitiveFreshness,
                            ),
                            color: TonyoPalette.of(context).secondary,
                            comparison: _cognitiveComparison(score),
                          );
                          if (stackScores) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                energy,
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 18),
                                  child: Divider(
                                    color: TonyoPalette.of(context).border,
                                  ),
                                ),
                                cognitive,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: energy),
                              Container(
                                width: 1,
                                height: 126,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                color: TonyoPalette.of(context).border,
                              ),
                              Expanded(child: cognitive),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('today-score-transparency'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ModelTransparencyScreen(controller: controller),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: TonyoPalette.of(context).text,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.insights_rounded, size: 20),
                      SizedBox(width: 10),
                      Expanded(child: Text('Why these scores?')),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
                if (controller.isScoreLoading) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    minHeight: 2,
                    color: TonyoPalette.of(context).primary,
                    backgroundColor: TonyoPalette.of(context).surfaceRaised,
                  ),
                ],
                if (controller.scoreError case final error?) ...[
                  const SizedBox(height: 10),
                  _OfflineNotice(message: error),
                ],
                const SectionHeader('Today’s signals'),
                LayoutBuilder(
                  key: const Key('recent-signal-grid'),
                  builder: (context, constraints) {
                    final columns =
                        constraints.maxWidth >=
                            280 * MediaQuery.textScalerOf(context).scale(1)
                        ? 2
                        : 1;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 10) / columns;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: controller.todaySignalSummaries
                          .map(
                            (summary) => SizedBox(
                              width: width,
                              child: _SignalSummaryCard(summary: summary),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                const SectionHeader('Personal context'),
                PersonalBaselineCard(
                  baselines: controller.personalBaselines,
                  compact: true,
                ),
                SectionHeader(
                  'What shaped today',
                  action: controller.isScoreLoading ? 'Updating…' : 'Refresh',
                  onTap: controller.isScoreLoading
                      ? null
                      : () => controller.refreshScores(forceRecalculate: true),
                ),
                _DriverCard(
                  title: 'Energy factors',
                  subtitle: 'Today’s score factors',
                  drivers: score.drivers,
                  color: TonyoPalette.of(context).secondary,
                ),
                const SizedBox(height: 10),
                _DriverCard(
                  title: 'Cognitive factors',
                  subtitle: 'WHAT SHAPED THIS ESTIMATE',
                  drivers: score.cognitiveDrivers,
                  color: TonyoPalette.of(context).primary,
                ),
                const SizedBox(height: 12),
                TonyoCard(
                  key: const Key('energy-score-explanation'),
                  color: TonyoPalette.of(context).surface,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: TonyoPalette.of(context).primary,
                        size: 19,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This wellness estimate combines recent sleep, activity, reaction, mood, and stress inputs. It supports daily planning and is not a medical assessment.',
                          style: TextStyle(
                            color: TonyoPalette.of(context).muted,
                            fontSize: 10,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _statusColor(TodayFatigueStatus status, BuildContext context) =>
      switch (status) {
        TodayFatigueStatus.fresh => TonyoPalette.of(context).success,
        TodayFatigueStatus.moderate => TonyoPalette.of(context).warning,
        TodayFatigueStatus.fatigued => TonyoPalette.of(context).error,
      };

  static String _cognitiveComparison(ScoreSnapshot score) {
    final change = score.cognitiveChange;
    if (change == null) {
      return 'First Cognitive Score · comparison starts tomorrow';
    }
    if (change == 0) return 'No change from yesterday';
    return '${change > 0 ? '↑' : '↓'} ${change.abs()} points from yesterday';
  }

  static String _confidenceLine(
    String coverage,
    double confidence,
    double? freshness,
  ) =>
      '$coverage · ${(confidence * 100).round()}% confidence${freshness == null ? '' : ' · ${(freshness * 100).round()}% fresh'}';
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.onOpenProfile});

  final String name;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final date = Text(
      _dateLabel(),
      style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 12),
    );
    final greeting = Text(
      '${_greeting()}, $name',
      style: Theme.of(context).textTheme.headlineMedium,
    );
    final profile = IconButton(
      key: const Key('today-profile-button'),
      tooltip: 'Open profile',
      onPressed: onOpenProfile,
      padding: const EdgeInsets.all(2),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: ExcludeSemantics(
        child: CircleAvatar(
          radius: 22,
          backgroundColor: TonyoPalette.of(
            context,
          ).primary.withValues(alpha: .22),
          child: Text(
            name.trim().isEmpty
                ? 'T'
                : name.trim().characters.first.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: date),
              profile,
            ],
          ),
          const SizedBox(height: 4),
          greeting,
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [date, greeting],
          ),
        ),
        profile,
      ],
    );
  }

  static String _greeting() => switch (DateTime.now().hour) {
    < 12 => 'Morning',
    < 17 => 'Afternoon',
    _ => 'Evening',
  };

  static String _dateLabel() {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }
}

class _ScoreTile extends StatelessWidget {
  const _ScoreTile({
    super.key,
    required this.value,
    required this.label,
    required this.eyebrow,
    required this.completeness,
    required this.color,
    this.comparison,
  });

  final int value;
  final String label;
  final String eyebrow;
  final String completeness;
  final Color color;
  final String? comparison;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        eyebrow,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: .55,
        ),
      ),
      const SizedBox(height: 8),
      ScoreRing(value: value, label: label, size: 76, color: color),
      const SizedBox(height: 8),
      Text(
        completeness,
        textAlign: TextAlign.center,
        style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 8.5),
      ),
      if (comparison != null) ...[
        const SizedBox(height: 4),
        Text(
          comparison!,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: TonyoPalette.of(context).secondary,
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ],
  );
}

class _SignalSummaryCard extends StatelessWidget {
  const _SignalSummaryCard({required this.summary});

  final TodaySignalSummary summary;

  @override
  Widget build(BuildContext context) {
    final color = _color(summary.type, context);
    return TonyoCard(
      key: Key('today-signal-${summary.type.name}'),
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          MetricIcon(icon: _icon(summary.type), color: color, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.type.label,
                  style: TextStyle(
                    color: TonyoPalette.of(context).muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary.displayValue,
                  style: TextStyle(
                    color: summary.isAvailable
                        ? TonyoPalette.of(context).text
                        : color,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  summary.isAvailable ? 'Logged today' : 'Not logged',
                  style: TextStyle(
                    color: TonyoPalette.of(context).muted,
                    fontSize: 8.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _icon(SignalType type) => switch (type) {
    SignalType.sleep => Icons.bedtime_rounded,
    SignalType.hydration => Icons.water_drop_rounded,
    SignalType.exercise => Icons.fitness_center_rounded,
    SignalType.steps => Icons.directions_walk_rounded,
    SignalType.study => Icons.menu_book_rounded,
    SignalType.screenTime => Icons.smartphone_rounded,
    SignalType.reactionTime => Icons.bolt_rounded,
    _ => Icons.insights_rounded,
  };

  static Color _color(SignalType type, BuildContext context) => switch (type) {
    SignalType.sleep => TonyoPalette.of(context).primary,
    SignalType.hydration => TonyoPalette.of(context).secondary,
    SignalType.exercise => TonyoPalette.of(context).primary,
    SignalType.steps => TonyoPalette.of(context).primary,
    SignalType.study => TonyoPalette.of(context).secondary,
    SignalType.screenTime => TonyoPalette.of(context).secondary,
    SignalType.reactionTime => TonyoPalette.of(context).primary,
    _ => TonyoPalette.of(context).muted,
  };
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({
    required this.title,
    required this.subtitle,
    required this.drivers,
    required this.color,
  });

  final String title;
  final String subtitle;
  final List<ScoreDriver> drivers;
  final Color color;

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            MetricIcon(icon: Icons.insights_rounded, color: color, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: color,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .5,
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (drivers.isEmpty)
          Text(
            'Log today’s signals to personalize this estimate.',
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 11,
            ),
          )
        else ...[
          if (drivers.any((driver) => driver.isPositive)) ...[
            _TodayDriverLabel(
              label: 'SUPPORTING',
              color: TonyoPalette.of(context).success,
            ),
            ...drivers
                .where((driver) => driver.isPositive)
                .take(2)
                .map(_DriverRow.new),
          ],
          if (drivers.any((driver) => driver.isNegative)) ...[
            _TodayDriverLabel(
              label: 'REDUCING',
              color: TonyoPalette.of(context).error,
            ),
            ...drivers
                .where((driver) => driver.isNegative)
                .take(2)
                .map(_DriverRow.new),
          ],
          if (drivers.every((driver) => driver.isNeutral)) ...[
            _TodayDriverLabel(
              label: 'NEUTRAL',
              color: TonyoPalette.of(context).muted,
            ),
            ...drivers.take(2).map(_DriverRow.new),
          ],
        ],
      ],
    ),
  );
}

class _TodayDriverLabel extends StatelessWidget {
  const _TodayDriverLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 8,
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
      ),
    ),
  );
}

class _DriverRow extends StatelessWidget {
  const _DriverRow(this.driver);

  final ScoreDriver driver;

  @override
  Widget build(BuildContext context) {
    final color = driver.isPositive
        ? TonyoPalette.of(context).success
        : driver.isNegative
        ? TonyoPalette.of(context).error
        : TonyoPalette.of(context).muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driver.label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  driver.detail,
                  style: TextStyle(
                    color: TonyoPalette.of(context).muted,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${driver.isPositive ? '+' : ''}${driver.contribution.round()} pts',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        Icons.cloud_off_rounded,
        color: TonyoPalette.of(context).warning,
        size: 15,
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          message,
          style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 10),
        ),
      ),
    ],
  );
}
