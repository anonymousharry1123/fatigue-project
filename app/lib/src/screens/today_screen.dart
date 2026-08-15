import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';
import '../theme.dart';
import '../today_dashboard_logic.dart';
import '../widgets/common_widgets.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final score = controller.score;
    final status = TodayDashboardLogic.statusFor(score.energy);
    final statusColor = _statusColor(status);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        key: const PageStorageKey('today-scroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            sliver: SliverList.list(
              children: [
                _Header(name: controller.profile.name),
                const SizedBox(height: 18),
                TonyoCard(
                  key: const Key('energy-score-card'),
                  padding: const EdgeInsets.all(18),
                  color: const Color(0xFF121622),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(20),
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
                                Text(
                                  status.label.toUpperCase(),
                                  key: const Key('fatigue-status'),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: .7,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            controller.scoreLoadedFromSnapshot
                                ? Icons.cloud_done_rounded
                                : Icons.auto_awesome_rounded,
                            color: TonyoColors.muted,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            controller.scoreLoadedFromSnapshot
                                ? 'Saved snapshot'
                                : 'Live estimate',
                            style: const TextStyle(
                              color: TonyoColors.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
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
                        style: const TextStyle(
                          color: TonyoColors.muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(color: TonyoColors.border, height: 1),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _ScoreTile(
                              value: score.energy,
                              label: 'Energy',
                              eyebrow: 'ESTIMATED ENERGY SCORE',
                              completeness: _confidenceLine(
                                '${score.inputCount}/7 inputs',
                                score.confidence,
                                score.freshness,
                              ),
                              color: TonyoColors.violet,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 126,
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            color: TonyoColors.border,
                          ),
                          Expanded(
                            child: _ScoreTile(
                              key: const Key('cognitive-score-card'),
                              value: score.cognitive,
                              label: 'Cognitive',
                              eyebrow: 'ESTIMATED COGNITIVE SCORE',
                              completeness: _confidenceLine(
                                '${score.cognitiveInputCount}/6 cognitive inputs',
                                score.cognitiveConfidence,
                                score.cognitiveFreshness,
                              ),
                              color: TonyoColors.blue,
                              comparison: _cognitiveComparison(score),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (controller.isScoreLoading) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(
                    minHeight: 2,
                    color: TonyoColors.primary,
                    backgroundColor: TonyoColors.surfaceRaised,
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
                    final width = (constraints.maxWidth - 10) / 2;
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
                  color: TonyoColors.violet,
                ),
                const SizedBox(height: 10),
                _DriverCard(
                  title: 'Cognitive factors',
                  subtitle: 'WHAT SHAPED THIS ESTIMATE',
                  drivers: score.cognitiveDrivers,
                  color: TonyoColors.blue,
                ),
                const SizedBox(height: 12),
                TonyoCard(
                  key: const Key('energy-score-explanation'),
                  color: const Color(0xFF111722),
                  padding: const EdgeInsets.all(14),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: TonyoColors.blue,
                        size: 19,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This wellness estimate combines recent sleep, activity, reaction, mood, and stress inputs. It supports daily planning and is not a medical assessment.',
                          style: TextStyle(
                            color: TonyoColors.muted,
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

  static Color _statusColor(TodayFatigueStatus status) => switch (status) {
    TodayFatigueStatus.fresh => TonyoColors.mint,
    TodayFatigueStatus.moderate => TonyoColors.amber,
    TodayFatigueStatus.fatigued => TonyoColors.coral,
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
  const _Header({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _dateLabel(),
              style: const TextStyle(color: TonyoColors.muted, fontSize: 12),
            ),
            Text(
              '${_greeting()}, $name',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      CircleAvatar(
        radius: 22,
        backgroundColor: TonyoColors.primary.withValues(alpha: .22),
        child: Text(
          name.trim().isEmpty
              ? 'T'
              : name.trim().characters.first.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    ],
  );

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
          fontWeight: FontWeight.w900,
          letterSpacing: .55,
        ),
      ),
      const SizedBox(height: 8),
      ScoreRing(value: value, label: label, size: 76),
      const SizedBox(height: 8),
      Text(
        completeness,
        textAlign: TextAlign.center,
        style: const TextStyle(color: TonyoColors.muted, fontSize: 8.5),
      ),
      if (comparison != null) ...[
        const SizedBox(height: 4),
        Text(
          comparison!,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: TonyoColors.mint,
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
    final color = _color(summary.type);
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TonyoColors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary.displayValue,
                  style: TextStyle(
                    color: summary.isAvailable ? TonyoColors.text : color,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  summary.isAvailable ? 'Logged today' : 'Not logged',
                  style: const TextStyle(
                    color: TonyoColors.muted,
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
    SignalType.study => Icons.menu_book_rounded,
    SignalType.screenTime => Icons.smartphone_rounded,
    SignalType.reactionTime => Icons.bolt_rounded,
    _ => Icons.insights_rounded,
  };

  static Color _color(SignalType type) => switch (type) {
    SignalType.sleep => TonyoColors.blue,
    SignalType.hydration => TonyoColors.mint,
    SignalType.exercise => TonyoColors.coral,
    SignalType.study => TonyoColors.amber,
    SignalType.screenTime => TonyoColors.violet,
    SignalType.reactionTime => TonyoColors.primary,
    _ => TonyoColors.muted,
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
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5,
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (drivers.isEmpty)
          const Text(
            'Log today’s signals to personalize this estimate.',
            style: TextStyle(color: TonyoColors.muted, fontSize: 11),
          )
        else ...[
          if (drivers.any((driver) => driver.isPositive)) ...[
            const _TodayDriverLabel(
              label: 'SUPPORTING',
              color: TonyoColors.mint,
            ),
            ...drivers
                .where((driver) => driver.isPositive)
                .take(2)
                .map(_DriverRow.new),
          ],
          if (drivers.any((driver) => driver.isNegative)) ...[
            const _TodayDriverLabel(
              label: 'REDUCING',
              color: TonyoColors.coral,
            ),
            ...drivers
                .where((driver) => driver.isNegative)
                .take(2)
                .map(_DriverRow.new),
          ],
          if (drivers.every((driver) => driver.isNeutral)) ...[
            const _TodayDriverLabel(label: 'NEUTRAL', color: TonyoColors.muted),
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
        fontWeight: FontWeight.w900,
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
        ? TonyoColors.mint
        : driver.isNegative
        ? TonyoColors.coral
        : TonyoColors.muted;
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
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  driver.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: TonyoColors.muted, fontSize: 9),
                ),
              ],
            ),
          ),
          Text(
            '${driver.isPositive ? '+' : ''}${driver.contribution.round()} pts',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
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
      const Icon(Icons.cloud_off_rounded, color: TonyoColors.amber, size: 15),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          message,
          style: const TextStyle(color: TonyoColors.muted, fontSize: 10),
        ),
      ),
    ],
  );
}
