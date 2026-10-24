import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../app.dart';
import '../app_controller.dart';
import '../insights_logic.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/personal_baseline_card.dart';
import '../widgets/self_report_trends_card.dart';

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
                      context.tr('Insights'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      context.tr(
                        'Recorded patterns and experimental estimates',
                      ),
                      style: TextStyle(
                        color: TonyoPalette.of(context).muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: context.tr('Refresh insights'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
          const SizedBox(height: 14),
          SelfReportTrendsCard(
            checkIns: controller.checkIns,
            signals: controller.signals,
            now: controller.currentTime,
          ),
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
          if (insights.currentSummary.stagedNightCount > 0) ...[
            const SectionHeader('Sleep stages'),
            _SleepStagesCard(days: insights.currentDays),
          ],
          const SectionHeader('Model associations'),
          _AssociationsCard(associations: insights.associations),
          const SectionHeader('Today’s experimental estimates'),
          TonyoCard(
            color: TonyoPalette.of(context).surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    MetricIcon(
                      icon: Icons.analytics_rounded,
                      color: TonyoPalette.of(context).secondary,
                    ),
                    SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('Daily Score Models'),
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            context.tr(
                              'Ranked inputs · data coverage and quality',
                            ),
                            style: TextStyle(
                              color: TonyoPalette.of(context).muted,
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
                  score: score.canEstimateEnergy ? score.energy : null,
                  confidence: score.confidence,
                  completeness: score.completeness,
                  freshness: score.freshness,
                  color: TonyoPalette.of(context).primary,
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(
                    color: TonyoPalette.of(context).border,
                    height: 1,
                  ),
                ),
                _ConfidencePanel(
                  title: 'Cognitive',
                  score: score.canEstimateCognitive ? score.cognitive : null,
                  confidence: score.cognitiveConfidence,
                  completeness: score.cognitiveCompleteness,
                  freshness: score.cognitiveFreshness,
                  color: TonyoPalette.of(context).secondary,
                ),
              ],
            ),
          ),
          const SectionHeader('Personal baselines'),
          PersonalBaselineCard(baselines: controller.personalBaselines),
          const SectionHeader('Today’s Energy drivers'),
          _RankedDriversCard(
            key: const Key('insights-energy-drivers'),
            positive: score.canEstimateEnergy
                ? score.energyPositiveDrivers
                : [],
            negative: score.canEstimateEnergy
                ? score.energyNegativeDrivers
                : [],
            neutral: score.canEstimateEnergy ? score.energyNeutralDrivers : [],
            emptyMessage:
                'Not enough current information to estimate Energy. An optional check-in can add an observation.',
          ),
          const SectionHeader('Today’s Cognitive drivers'),
          _RankedDriversCard(
            key: const Key('insights-cognitive-model'),
            positive: score.canEstimateCognitive
                ? score.cognitivePositiveDrivers
                : [],
            negative: score.canEstimateCognitive
                ? score.cognitiveNegativeDrivers
                : [],
            neutral: score.canEstimateCognitive
                ? score.cognitiveNeutralDrivers
                : [],
            emptyMessage:
                'Not enough current information to estimate the experimental Cognitive score.',
          ),
          const SizedBox(height: 14),
          TonyoCard(
            color: TonyoPalette.of(context).surface,
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final summary = Row(
                  children: [
                    MetricIcon(
                      icon: Icons.psychology_rounded,
                      color: TonyoPalette.of(context).secondary,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        context.tr(
                          '${score.cognitiveInputCount} current Cognitive inputs · data quality',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                );
                final detail = Text(
                  context.tr(
                    'Data quality describes the coverage, age, source, and quality of records. It is not the probability that a score is correct. These experimental rules are not medical findings or proof of cause.',
                  ),
                  style: TextStyle(
                    color: TonyoPalette.of(context).muted,
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
                    Expanded(flex: 3, child: detail),
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
    color: TonyoPalette.of(context).surface,
    padding: const EdgeInsets.all(13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MetricIcon(
          icon: controller.insightsLoadedFromCloud
              ? Icons.lock_rounded
              : Icons.phone_iphone_rounded,
          color: TonyoPalette.of(context).secondary,
          size: 38,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  controller.insightsLoadedFromCloud
                      ? 'Your private Firestore range'
                      : 'Your on-device entries',
                ),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                context.tr(
                  '${insights.sourceSignalCount} signals · '
                  '${insights.sourceCheckInCount} check-ins · no cohort comparisons',
                ),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                context.tr(insights.calculationBasis),
                key: const Key('insights-calculation-basis'),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 10,
                  height: 1.35,
                ),
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
      color: TonyoPalette.of(context).warning.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(14),
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
            context.tr(message),
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

class _EmptyInsightsCard extends StatelessWidget {
  const _EmptyInsightsCard();

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
                context.tr('Not enough recent entries yet'),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 3),
              Text(
                context.tr(
                  'Log sleep, training, or study to build your private seven-day trends.',
                ),
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

class _WeeklyOverview extends StatelessWidget {
  const _WeeklyOverview({required this.insights});

  final InsightsSnapshot insights;

  @override
  Widget build(BuildContext context) {
    final current = insights.currentSummary;
    final previous = insights.previousSummary;
    final metrics = [
      _OverviewValue(
        label: 'Avg main sleep',
        value: _hours(current.averageSleepHours),
        comparison: _delta(
          current.averageSleepHours,
          previous.averageSleepHours,
          suffix: ' hr',
        ),
        icon: Icons.bedtime_rounded,
        color: TonyoPalette.of(context).primary,
      ),
      if (current.stagedNightCount > 0) ...[
        _OverviewValue(
          label: 'Avg deep sleep',
          value: _hours(current.averageSleepDeepHours),
          comparison: _delta(
            current.averageSleepDeepHours,
            previous.averageSleepDeepHours,
            suffix: ' hr',
          ),
          icon: Icons.nights_stay_rounded,
          color: TonyoPalette.of(context).secondary,
        ),
        _OverviewValue(
          label: 'Avg REM sleep',
          value: _hours(current.averageSleepRemHours),
          comparison: _delta(
            current.averageSleepRemHours,
            previous.averageSleepRemHours,
            suffix: ' hr',
          ),
          icon: Icons.bedtime_rounded,
          color: TonyoPalette.of(context).primary,
        ),
      ],
      _OverviewValue(
        label: 'Training',
        value: _hours(current.trainingHours),
        comparison: _delta(
          current.trainingHours,
          previous.trainingHours,
          suffix: ' hr',
        ),
        icon: Icons.fitness_center_rounded,
        color: TonyoPalette.of(context).primary,
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
        color: TonyoPalette.of(context).secondary,
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
        color: TonyoPalette.of(context).primary,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final columns = constraints.maxWidth >= 720 * scale
                ? 4
                : constraints.maxWidth >= 280 * scale
                ? 2
                : 1;
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
          context.tr(
            '${current.trackedDayCount}/7 days have entries; '
            '${insights.currentDays.where((day) => day.sleepHours != null).length} main-sleep observations; '
            '${insights.currentDays.where((day) => day.estimatedEnergy != null).length} eligible Energy estimates. '
            'Averages use recorded days only. Comparisons use the prior seven days.',
          ),
          style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 10),
        ),
        if (current.stagedNightCount > 0) ...[
          const SizedBox(height: 5),
          Text(
            context.tr(
              'Sleep stage averages use nights with that stage recorded; missing stages are not zero.',
            ),
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 10,
            ),
          ),
        ],
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
          context.tr(value.value),
          style: TextStyle(
            color: value.color,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          context.tr(value.label),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
        ),
        const SizedBox(height: 5),
        Text(
          context.tr(value.comparison),
          style: TextStyle(
            color: TonyoPalette.of(context).muted,
            fontSize: 8.5,
          ),
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
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  label: Text(context.tr(_metricLabel(value))),
                  selected: metric == value,
                  onSelected: (_) => onMetricChanged(value),
                ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final minimumWidth = days.length * (28 * scale + 6);
              final chart = SingleChildScrollView(
                key: const Key('insights-trend-chart-scroll'),
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: minimumWidth > constraints.maxWidth
                      ? minimumWidth
                      : constraints.maxWidth,
                  height: 142 + 45 * (scale - 1).clamp(0, double.infinity),
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
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  chart,
                  if (minimumWidth > constraints.maxWidth)
                    Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        context.tr('Swipe to view more days.'),
                        style: TextStyle(
                          color: TonyoPalette.of(context).muted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            context.tr(_trendCaption(metric)),
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
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
      'Daily Energy values use the current deterministic rules, without learned personalization. Experimental recomputations are not measurements; days without current supporting inputs stay blank.',
    InsightTrendMetric.sleep =>
      'Latest main sleep for each day; naps are tracked separately and missing days remain blank.',
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
    final color = _color(metric, TonyoPalette.of(context));
    final metricLabel = _DailyTrendCard._metricLabel(metric);
    final valueLabel = value == null
        ? metric == InsightTrendMetric.energy
              ? 'Not enough information to estimate'
              : 'Not logged'
        : metric == InsightTrendMetric.energy
        ? '${value.round()} out of 100, estimated'
        : '${value.toStringAsFixed(1)} hours';
    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          '${_dayLabel(day.date)}, ${formatDate(day.date)}, ${day.date.year}. '
          '${context.tr(metricLabel)}: ${context.tr(valueLabel)}',
      child: Column(
        children: [
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(18),
            child: Text(
              context.tr(_valueLabel(value, metric)),
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
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
                        ? TonyoPalette.of(context).border
                        : color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            context.tr(_dayLabel(day.date)),
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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

  static Color _color(InsightTrendMetric metric, TonyoPalette colors) =>
      switch (metric) {
        InsightTrendMetric.energy => colors.primary,
        InsightTrendMetric.sleep => colors.secondary,
        InsightTrendMetric.training => colors.primary,
        InsightTrendMetric.study => colors.secondary,
      };
}

class _SleepStagesCard extends StatelessWidget {
  const _SleepStagesCard({required this.days});

  final List<InsightDay> days;

  @override
  Widget build(BuildContext context) {
    final stagedDays = days.where((day) => day.hasSleepStages).toList();
    final maximum = stagedDays.fold<double>(
      1,
      (value, day) =>
          day.recordedStageHours > value ? day.recordedStageHours : value,
    );
    return TonyoCard(
      key: const Key('insights-sleep-stages'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
              'Recorded stages for the preferred main sleep on each wake date. Awake time is separate from sleep duration. Device estimates do not change your score.',
            ),
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          for (final day in stagedDays) ...[
            const SizedBox(height: 18),
            _SleepStageBar(day: day, maximum: maximum),
          ],
        ],
      ),
    );
  }
}

class _SleepStageBar extends StatelessWidget {
  const _SleepStageBar({required this.day, required this.maximum});

  final InsightDay day;
  final double maximum;

  @override
  Widget build(BuildContext context) {
    final colors = TonyoPalette.of(context);
    final stages = <({String name, double? hours, Color color})>[
      (name: 'Core', hours: day.sleepCoreHours, color: colors.primary),
      (name: 'Deep', hours: day.sleepDeepHours, color: colors.secondary),
      (name: 'REM', hours: day.sleepRemHours, color: colors.success),
      (name: 'Awake', hours: day.sleepAwakeHours, color: colors.warning),
    ];
    String stageValue(double? value) => value == null
        ? context.tr('Not recorded')
        : context.tr('{hours} hr', args: {'hours': value.toStringAsFixed(1)});
    final dateLabel =
        '${context.tr(_TrendBar._dayLabel(day.date))}, '
        '${formatDate(day.date)}';
    final stageLabels = [
      for (final stage in stages)
        '${context.tr(stage.name)}: ${stageValue(stage.hours)}',
    ];
    return Semantics(
      key: Key('insights-sleep-stage-${day.date.toIso8601String()}'),
      container: true,
      excludeSemantics: true,
      label: '$dateLabel, ${day.date.year}. ${stageLabels.join('. ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateLabel,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: (day.recordedStageHours / maximum).clamp(0.0, 1.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  height: 18,
                  child: Row(
                    children: [
                      for (final stage in stages)
                        if ((stage.hours ?? 0) > 0)
                          Expanded(
                            flex: (stage.hours! * 10000).round().clamp(
                              1,
                              10000000,
                            ),
                            child: ColoredBox(
                              color: stage.color,
                              child: const SizedBox.expand(),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (var index = 0; index < stages.length; index++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: stages[index].color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const SizedBox(width: 8, height: 8),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        stageLabels[index],
                        style: TextStyle(color: colors.muted, fontSize: 11),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssociationsCard extends StatelessWidget {
  const _AssociationsCard({required this.associations});

  final List<InsightAssociation> associations;

  @override
  Widget build(BuildContext context) => TonyoCard(
    key: const Key('insights-associations'),
    color: TonyoPalette.of(context).surface,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: TonyoPalette.of(context).primary,
              size: 19,
            ),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                context.tr(
                  'These compare entries with a score partly calculated from those same entries. They describe the current rules, not an independent health outcome or evidence that a behavior helps.',
                ),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 10.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (associations.isEmpty)
          Text(
            context.tr(
              'At least three matched days with varied sleep, training, or study entries are needed for an association summary.',
            ),
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 11,
            ),
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
      InsightAssociationDirection.positive => TonyoPalette.of(context).success,
      InsightAssociationDirection.negative => TonyoPalette.of(context).error,
      InsightAssociationDirection.neutral => TonyoPalette.of(context).muted,
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
                context.tr(association.title),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                context.tr(association.detail),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
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
  final int? score;
  final double confidence;
  final double completeness;
  final double? freshness;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final coverage = '${(completeness * 100).round()}% coverage';
    final age = freshness == null
        ? 'freshness unavailable'
        : '${(freshness! * 100).round()}% fresh';
    final scoreBadge = Container(
      width: 58 * scale,
      height: 58 * scale,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Text(
        context.tr(score?.toString() ?? '—'),
        style: TextStyle(
          color: color,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            Text(
              context.tr(
                '{title} data quality',
                args: {'title': context.tr(title)},
              ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              context.tr(
                score == null
                    ? 'Unavailable'
                    : '${(confidence * 100).round()}%',
              ),
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 7),
        if (score == null) ...[
          Text(
            context.tr('Not enough information to estimate'),
            style: TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 7),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: score == null ? 0 : confidence,
            minHeight: 6,
            color: color,
            backgroundColor: TonyoPalette.of(context).surfaceRaised,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '${context.tr(coverage)} · ${context.tr(age)}',
          style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 9),
        ),
      ],
    );
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: score == null
          ? context.tr(
              '{title}: Not enough information to estimate.',
              args: {'title': context.tr(title)},
            )
          : context.tr(
              '{title} experimental estimate: {score} out of 100. {quality}% data quality, not probability of correctness. {coverage}. {age}.',
              args: {
                'title': context.tr(title),
                'score': score,
                'quality': (confidence * 100).round(),
                'coverage': context.tr(coverage),
                'age': context.tr(age),
              },
            ),
      child: scale > 1.3
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [scoreBadge, const SizedBox(height: 12), detail],
            )
          : Row(
              children: [
                scoreBadge,
                const SizedBox(width: 13),
                Expanded(child: detail),
              ],
            ),
    );
  }
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
          context.tr(emptyMessage),
          style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 11),
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
              color: TonyoPalette.of(context).success,
              drivers: positive,
            ),
          if (positive.isNotEmpty && negative.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(color: TonyoPalette.of(context).border, height: 1),
            ),
          if (negative.isNotEmpty)
            _DriverGroup(
              title: 'REDUCING TODAY',
              icon: Icons.trending_down_rounded,
              color: TonyoPalette.of(context).error,
              drivers: negative,
            ),
          if (neutral.isNotEmpty &&
              (positive.isNotEmpty || negative.isNotEmpty))
            Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(color: TonyoPalette.of(context).border, height: 1),
            ),
          if (neutral.isNotEmpty)
            _DriverGroup(
              title: 'NEUTRAL',
              icon: Icons.horizontal_rule_rounded,
              color: TonyoPalette.of(context).muted,
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
          Expanded(
            child: Text(
              context.tr(title),
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: .6,
              ),
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
            context.tr('$rank'),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
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
                      context.tr(driver.label),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    context.tr(
                      '${driver.contribution > 0 ? '+' : ''}${driver.contribution.round()} pts',
                    ),
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                context.tr(driver.detail),
                style: TextStyle(
                  color: TonyoPalette.of(context).text,
                  fontSize: 10,
                ),
              ),
              if (driver.explanation.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  context.tr(driver.explanation),
                  style: TextStyle(
                    color: TonyoPalette.of(context).muted,
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
      color: TonyoPalette.of(context).surfaceRaised,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: TonyoPalette.of(context).border),
    ),
    child: Text(
      context.tr(label),
      style: TextStyle(
        color: TonyoPalette.of(context).muted,
        fontSize: 8,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
