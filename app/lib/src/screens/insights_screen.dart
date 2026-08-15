import 'package:flutter/material.dart';

import '../app.dart';
import '../app_controller.dart';
import '../insights_logic.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  InsightTrendMetric _metric = InsightTrendMetric.energy;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final score = controller.score;
    final insights = controller.insightsSnapshot;
    return SafeArea(
      bottom: false,
      child: ListView(
        key: const PageStorageKey('insights-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Insights',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const Text(
                      'Your daily patterns and model-estimated trends',
                      style: TextStyle(color: TonyoColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Refresh insights',
                onPressed: controller.isInsightsLoading
                    ? null
                    : controller.refreshInsights,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InsightsSourceCard(controller: controller, insights: insights),
          if (controller.isInsightsLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (controller.insightsError case final error?) ...[
            const SizedBox(height: 10),
            _InsightsNotice(message: error),
          ],
          const SectionHeader('7-day overview'),
          if (insights.hasCurrentData)
            _WeeklyOverview(insights: insights)
          else
            const _EmptyInsightsCard(),
          const SectionHeader('Daily trends'),
          _DailyTrendCard(
            days: insights.currentDays,
            metric: _metric,
            onMetricChanged: (value) => setState(() => _metric = value),
          ),
          const SectionHeader('Model associations'),
          _AssociationsCard(associations: insights.associations),
          const SectionHeader('Today’s model'),
          TonyoCard(
            color: const Color(0xFF151923),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    MetricIcon(
                      icon: Icons.analytics_rounded,
                      color: TonyoColors.mint,
                    ),
                    SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily Score Models',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            'Ranked drivers · evidence-aware confidence',
                            style: TextStyle(
                              color: TonyoColors.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _ConfidencePanel(
                  title: 'Energy',
                  score: score.energy,
                  confidence: score.confidence,
                  completeness: score.completeness,
                  freshness: score.freshness,
                  color: TonyoColors.mint,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(color: TonyoColors.border, height: 1),
                ),
                _ConfidencePanel(
                  title: 'Cognitive',
                  score: score.cognitive,
                  confidence: score.cognitiveConfidence,
                  completeness: score.cognitiveCompleteness,
                  freshness: score.cognitiveFreshness,
                  color: TonyoColors.blue,
                ),
              ],
            ),
          ),
          const SectionHeader('Today’s Energy drivers'),
          _RankedDriversCard(
            key: const Key('insights-energy-drivers'),
            positive: score.energyPositiveDrivers,
            negative: score.energyNegativeDrivers,
            neutral: score.energyNeutralDrivers,
            emptyMessage:
                'Log sleep, activity, and a check-in to explain your Energy estimate.',
          ),
          const SectionHeader('Today’s Cognitive drivers'),
          _RankedDriversCard(
            key: const Key('insights-cognitive-model'),
            positive: score.cognitivePositiveDrivers,
            negative: score.cognitiveNegativeDrivers,
            neutral: score.cognitiveNeutralDrivers,
            emptyMessage:
                'Complete a reaction test, sleep or activity log, and check-in to explain cognitive readiness.',
          ),
          const SizedBox(height: 14),
          TonyoCard(
            color: const Color(0xFF111722),
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final summary = Row(
                  children: [
                    const MetricIcon(
                      icon: Icons.psychology_rounded,
                      color: TonyoColors.blue,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        '${score.cognitiveInputCount}/6 inputs · ${(score.cognitiveConfidence * 100).round()}% confidence',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                );
                const detail = Text(
                  'Confidence combines input coverage with the age, source, and quality of supporting records. Contributions are associations used by this wellness model—not medical findings or proof of cause.',
                  style: TextStyle(
                    color: TonyoColors.muted,
                    fontSize: 10,
                    height: 1.4,
                  ),
                );
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [summary, const SizedBox(height: 12), detail],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: summary),
                    const SizedBox(width: 16),
                    const Expanded(flex: 3, child: detail),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightsSourceCard extends StatelessWidget {
  const _InsightsSourceCard({required this.controller, required this.insights});

  final AppController controller;
  final InsightsSnapshot insights;

  @override
  Widget build(BuildContext context) => TonyoCard(
    color: const Color(0xFF151923),
    padding: const EdgeInsets.all(13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MetricIcon(
          icon: controller.insightsLoadedFromCloud
              ? Icons.lock_rounded
              : Icons.phone_iphone_rounded,
          color: TonyoColors.mint,
          size: 38,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                controller.insightsLoadedFromCloud
                    ? 'Your private Firestore range'
                    : 'Your on-device entries',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                '${insights.sourceSignalCount} signals · '
                '${insights.sourceCheckInCount} check-ins · no cohort comparisons',
                style: const TextStyle(color: TonyoColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InsightsNotice extends StatelessWidget {
  const _InsightsNotice({required this.message});

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

class _EmptyInsightsCard extends StatelessWidget {
  const _EmptyInsightsCard();

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
                'Not enough recent entries yet',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 3),
              Text(
                'Log sleep, training, or study to build your private seven-day trends.',
                style: TextStyle(color: TonyoColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _WeeklyOverview extends StatelessWidget {
  const _WeeklyOverview({required this.insights});

  final InsightsSnapshot insights;

  @override
  Widget build(BuildContext context) {
    final current = insights.currentSummary;
    final previous = insights.previousSummary;
    final metrics = [
      _OverviewValue(
        label: 'Avg sleep',
        value: _hours(current.averageSleepHours),
        comparison: _delta(
          current.averageSleepHours,
          previous.averageSleepHours,
          suffix: ' hr',
        ),
        icon: Icons.bedtime_rounded,
        color: TonyoColors.blue,
      ),
      _OverviewValue(
        label: 'Training',
        value: _hours(current.trainingHours),
        comparison: _delta(
          current.trainingHours,
          previous.trainingHours,
          suffix: ' hr',
        ),
        icon: Icons.fitness_center_rounded,
        color: TonyoColors.coral,
      ),
      _OverviewValue(
        label: 'Study',
        value: _hours(current.studyHours),
        comparison: _delta(
          current.studyHours,
          previous.studyHours,
          suffix: ' hr',
        ),
        icon: Icons.menu_book_rounded,
        color: TonyoColors.violet,
      ),
      _OverviewValue(
        label: 'Avg energy',
        value: current.averageEstimatedEnergy?.round().toString() ?? '—',
        comparison: _delta(
          current.averageEstimatedEnergy,
          previous.averageEstimatedEnergy,
          suffix: ' pts',
        ),
        icon: Icons.bolt_rounded,
        color: TonyoColors.mint,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720 ? 4 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width: width,
                    child: _OverviewCard(value: metric),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 9),
        Text(
          '${current.trackedDayCount}/7 days include model-input data. Comparisons use the prior seven days.',
          style: const TextStyle(color: TonyoColors.muted, fontSize: 10),
        ),
      ],
    );
  }

  static String _hours(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} hr';

  static String _delta(
    double? current,
    double? previous, {
    required String suffix,
  }) {
    if (current == null || previous == null) return 'No prior comparison';
    final difference = current - previous;
    if (difference.abs() < .05) return 'About even vs prior 7d';
    return '${difference > 0 ? '+' : ''}${difference.toStringAsFixed(1)}$suffix vs prior 7d';
  }
}

class _OverviewValue {
  const _OverviewValue({
    required this.label,
    required this.value,
    required this.comparison,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String comparison;
  final IconData icon;
  final Color color;
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.value});

  final _OverviewValue value;

  @override
  Widget build(BuildContext context) => TonyoCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(value.icon, color: value.color, size: 19),
        const SizedBox(height: 8),
        Text(
          value.value,
          style: TextStyle(
            color: value.color,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          value.label,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10),
        ),
        const SizedBox(height: 5),
        Text(
          value.comparison,
          maxLines: 2,
          style: const TextStyle(color: TonyoColors.muted, fontSize: 8.5),
        ),
      ],
    ),
  );
}

class _DailyTrendCard extends StatelessWidget {
  const _DailyTrendCard({
    required this.days,
    required this.metric,
    required this.onMetricChanged,
  });

  final List<InsightDay> days;
  final InsightTrendMetric metric;
  final ValueChanged<InsightTrendMetric> onMetricChanged;

  @override
  Widget build(BuildContext context) {
    final values = days.map((day) => day.valueFor(metric)).nonNulls.toList();
    final observedMaximum = values.isEmpty
        ? 0.0
        : values.reduce((left, right) => left > right ? left : right);
    final baselineMaximum = switch (metric) {
      InsightTrendMetric.energy => 100.0,
      InsightTrendMetric.sleep => 10.0,
      InsightTrendMetric.training => 2.0,
      InsightTrendMetric.study => 8.0,
    };
    final scaleMaximum = observedMaximum > baselineMaximum
        ? observedMaximum
        : baselineMaximum;
    return TonyoCard(
      key: const Key('insights-daily-trend'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final value in InsightTrendMetric.values)
                ChoiceChip(
                  key: Key('insight-metric-${value.name}'),
                  label: Text(_metricLabel(value)),
                  selected: metric == value,
                  onSelected: (_) => onMetricChanged(value),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 142,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final day in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _TrendBar(
                        day: day,
                        metric: metric,
                        scaleMaximum: scaleMaximum,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _trendCaption(metric),
            style: const TextStyle(
              color: TonyoColors.muted,
              fontSize: 10,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  static String _metricLabel(InsightTrendMetric value) => switch (value) {
    InsightTrendMetric.energy => 'Energy',
    InsightTrendMetric.sleep => 'Sleep',
    InsightTrendMetric.training => 'Training',
    InsightTrendMetric.study => 'Study',
  };

  static String _trendCaption(InsightTrendMetric value) => switch (value) {
    InsightTrendMetric.energy =>
      'Daily Energy values are recalculated wellness-model estimates, not measurements or diagnoses.',
    InsightTrendMetric.sleep =>
      'Latest logged sleep duration for each day; missing days remain blank.',
    InsightTrendMetric.training =>
      'Daily total of your exercise entries; missing days are not treated as zero.',
    InsightTrendMetric.study =>
      'Daily total of your study entries; missing days are not treated as zero.',
  };
}

class _TrendBar extends StatelessWidget {
  const _TrendBar({
    required this.day,
    required this.metric,
    required this.scaleMaximum,
  });

  final InsightDay day;
  final InsightTrendMetric metric;
  final double scaleMaximum;

  @override
  Widget build(BuildContext context) {
    final value = day.valueFor(metric);
    final ratio = value == null ? 0.0 : (value / scaleMaximum).clamp(0.0, 1.0);
    final color = _color(metric);
    return Column(
      children: [
        SizedBox(
          height: 18,
          child: Text(
            _valueLabel(value, metric),
            style: const TextStyle(
              color: TonyoColors.muted,
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 16,
                height: value == null
                    ? 3
                    : (constraints.maxHeight * ratio).clamp(
                        value == 0 ? 3.0 : 7.0,
                        constraints.maxHeight,
                      ),
                decoration: BoxDecoration(
                  color: value == null
                      ? TonyoColors.border
                      : color.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          _dayLabel(day.date),
          style: const TextStyle(
            color: TonyoColors.muted,
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  static String _valueLabel(double? value, InsightTrendMetric metric) {
    if (value == null) return '—';
    return metric == InsightTrendMetric.energy
        ? value.round().toString()
        : value.toStringAsFixed(1);
  }

  static String _dayLabel(DateTime value) => const [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ][value.weekday - 1];

  static Color _color(InsightTrendMetric metric) => switch (metric) {
    InsightTrendMetric.energy => TonyoColors.mint,
    InsightTrendMetric.sleep => TonyoColors.blue,
    InsightTrendMetric.training => TonyoColors.coral,
    InsightTrendMetric.study => TonyoColors.violet,
  };
}

class _AssociationsCard extends StatelessWidget {
  const _AssociationsCard({required this.associations});

  final List<InsightAssociation> associations;

  @override
  Widget build(BuildContext context) => TonyoCard(
    key: const Key('insights-associations'),
    color: const Color(0xFF111722),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: TonyoColors.blue, size: 19),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'These comparisons describe your entries and Tonyo’s current model. They do not establish that one behavior caused an outcome.',
                style: TextStyle(
                  color: TonyoColors.muted,
                  fontSize: 10.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (associations.isEmpty)
          const Text(
            'At least three matched days with varied sleep, training, or study entries are needed for an association summary.',
            style: TextStyle(color: TonyoColors.muted, fontSize: 11),
          )
        else
          ...associations.indexed.map(
            (entry) => Padding(
              padding: EdgeInsets.only(
                bottom: entry.$1 == associations.length - 1 ? 0 : 14,
              ),
              child: _AssociationRow(association: entry.$2),
            ),
          ),
      ],
    ),
  );
}

class _AssociationRow extends StatelessWidget {
  const _AssociationRow({required this.association});

  final InsightAssociation association;

  @override
  Widget build(BuildContext context) {
    final color = switch (association.direction) {
      InsightAssociationDirection.positive => TonyoColors.mint,
      InsightAssociationDirection.negative => TonyoColors.coral,
      InsightAssociationDirection.neutral => TonyoColors.muted,
    };
    final icon = switch (association.direction) {
      InsightAssociationDirection.positive => Icons.trending_up_rounded,
      InsightAssociationDirection.negative => Icons.trending_down_rounded,
      InsightAssociationDirection.neutral => Icons.trending_flat_rounded,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                association.title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                association.detail,
                style: const TextStyle(
                  color: TonyoColors.muted,
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConfidencePanel extends StatelessWidget {
  const _ConfidencePanel({
    required this.title,
    required this.score,
    required this.confidence,
    required this.completeness,
    required this.freshness,
    required this.color,
  });

  final String title;
  final int score;
  final double confidence;
  final double completeness;
  final double? freshness;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 58,
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: .3)),
        ),
        child: Text(
          '$score',
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$title confidence',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '${(confidence * 100).round()}%',
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: confidence,
                minHeight: 6,
                color: color,
                backgroundColor: TonyoColors.surfaceRaised,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '${(completeness * 100).round()}% coverage · ${freshness == null ? 'freshness unavailable' : '${(freshness! * 100).round()}% fresh'}',
              style: const TextStyle(color: TonyoColors.muted, fontSize: 9),
            ),
          ],
        ),
      ),
    ],
  );
}

class _RankedDriversCard extends StatelessWidget {
  const _RankedDriversCard({
    super.key,
    required this.positive,
    required this.negative,
    required this.neutral,
    required this.emptyMessage,
  });

  final List<ScoreDriver> positive;
  final List<ScoreDriver> negative;
  final List<ScoreDriver> neutral;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (positive.isEmpty && negative.isEmpty && neutral.isEmpty) {
      return TonyoCard(
        child: Text(
          emptyMessage,
          style: const TextStyle(color: TonyoColors.muted, fontSize: 11),
        ),
      );
    }
    return TonyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (positive.isNotEmpty)
            _DriverGroup(
              title: 'SUPPORTING TODAY',
              icon: Icons.trending_up_rounded,
              color: TonyoColors.mint,
              drivers: positive,
            ),
          if (positive.isNotEmpty && negative.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(color: TonyoColors.border, height: 1),
            ),
          if (negative.isNotEmpty)
            _DriverGroup(
              title: 'REDUCING TODAY',
              icon: Icons.trending_down_rounded,
              color: TonyoColors.coral,
              drivers: negative,
            ),
          if (neutral.isNotEmpty &&
              (positive.isNotEmpty || negative.isNotEmpty))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(color: TonyoColors.border, height: 1),
            ),
          if (neutral.isNotEmpty)
            _DriverGroup(
              title: 'NEUTRAL',
              icon: Icons.horizontal_rule_rounded,
              color: TonyoColors.muted,
              drivers: neutral,
            ),
        ],
      ),
    );
  }
}

class _DriverGroup extends StatelessWidget {
  const _DriverGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.drivers,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<ScoreDriver> drivers;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 7),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: .6,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      ...drivers.indexed.map(
        (entry) => _RankedDriverRow(
          rank: entry.$1 + 1,
          driver: entry.$2,
          color: color,
        ),
      ),
    ],
  );
}

class _RankedDriverRow extends StatelessWidget {
  const _RankedDriverRow({
    required this.rank,
    required this.driver,
    required this.color,
  });

  final int rank;
  final ScoreDriver driver;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$rank',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      driver.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '${driver.contribution > 0 ? '+' : ''}${driver.contribution.round()} pts',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                driver.detail,
                style: const TextStyle(color: TonyoColors.text, fontSize: 10),
              ),
              if (driver.explanation.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  driver.explanation,
                  style: const TextStyle(
                    color: TonyoColors.muted,
                    fontSize: 9.5,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  _EvidenceChip(label: _sourceLabel(driver)),
                  if (driver.freshness case final freshness?)
                    _EvidenceChip(label: '${(freshness * 100).round()}% fresh'),
                  if (driver.evidenceAt case final evidenceAt?)
                    _EvidenceChip(label: _dayLabel(evidenceAt)),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static String _sourceLabel(ScoreDriver driver) => switch (driver.source) {
    SignalSource.manual => 'Manual',
    SignalSource.healthKit => 'HealthKit',
    SignalSource.model => 'Model',
    null => driver.evidenceAt == null ? 'Legacy snapshot' : 'Check-in',
  };

  static String _dayLabel(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final days = today.difference(date).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return '$days days ago';
  }
}

class _EvidenceChip extends StatelessWidget {
  const _EvidenceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: TonyoColors.surfaceRaised,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: TonyoColors.border),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: TonyoColors.muted,
        fontSize: 8,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
