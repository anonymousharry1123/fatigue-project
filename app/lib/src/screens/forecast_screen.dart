import 'package:flutter/material.dart';

import '../app.dart';
import '../app_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  int _range = 0;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final today = DateTime.now();
    final selectedDay = today.add(Duration(days: _range == 1 ? 1 : 0));
    final points = controller.forecastDataFor(selectedDay);
    final week = controller.forecastSummariesFor(today);

    return SafeArea(
      bottom: false,
      child: ListView(
        key: const PageStorageKey('forecast-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Energy Forecast',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Refresh forecast',
                onPressed: controller.isForecastLoading
                    ? null
                    : () => controller.refreshForecasts(forceRecalculate: true),
                icon: controller.isForecastLoading
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'Hourly wellness estimates from your recent recovery and workload.',
            style: TextStyle(color: TonyoColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 14),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Today')),
              ButtonSegment(value: 1, label: Text('Tomorrow')),
              ButtonSegment(value: 2, label: Text('Week')),
            ],
            selected: {_range},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() => _range = value.first),
            style: SegmentedButton.styleFrom(
              backgroundColor: TonyoColors.surface,
              selectedBackgroundColor: TonyoColors.primary,
            ),
          ),
          if (controller.forecastError case final error?) ...[
            const SizedBox(height: 14),
            _StatusBanner(
              icon: Icons.cloud_off_rounded,
              color: TonyoColors.amber,
              title: 'Using on-device forecast',
              detail: error,
            ),
          ],
          const SizedBox(height: 14),
          if (_range == 2)
            _WeekForecast(
              summaries: week,
              loading: controller.isForecastLoading,
              onRetry: () =>
                  controller.refreshForecasts(forceRecalculate: true),
            )
          else
            _DailyForecast(
              day: selectedDay,
              points: points,
              loading: controller.isForecastLoading,
              sourceLabel: _sourceLabel(controller),
              onRetry: () =>
                  controller.refreshForecasts(forceRecalculate: true),
            ),
          const SizedBox(height: 14),
          const Text(
            'Energy forecasts are wellness estimates, not medical advice. Uncertainty expands when inputs are missing, older, or farther into the future.',
            textAlign: TextAlign.center,
            style: TextStyle(color: TonyoColors.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  static String _sourceLabel(AppController controller) {
    if (controller.forecastLoadedFromCloud) return 'Private saved forecast';
    if (controller.isCloudAuthenticated) {
      return 'Calculated and saved privately';
    }
    return 'Calculated on this device';
  }
}

class _DailyForecast extends StatelessWidget {
  const _DailyForecast({
    required this.day,
    required this.points,
    required this.loading,
    required this.sourceLabel,
    required this.onRetry,
  });

  final DateTime day;
  final List<ForecastPoint> points;
  final bool loading;
  final String sourceLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return _ForecastEmptyState(loading: loading, onRetry: onRetry);
    }
    final summary = ForecastDaySummary.fromPoints(day, points);
    final stale = summary.isStaleAt(
      DateTime.now(),
      maximumAge: AppController.forecastFreshnessWindow,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stale) ...[
          const _StatusBanner(
            icon: Icons.history_rounded,
            color: TonyoColors.amber,
            title: 'Forecast may be out of date',
            detail: 'Refresh to include the latest logged signals.',
          ),
          const SizedBox(height: 10),
        ],
        if (summary.isLowConfidence) ...[
          _StatusBanner(
            icon: Icons.visibility_outlined,
            color: TonyoColors.violet,
            title: 'Limited confidence',
            detail:
                'Typical uncertainty is ±${summary.averageUncertainty.round()} points. More recent sleep, workload, hydration, and check-in data can narrow the range.',
          ),
          const SizedBox(height: 10),
        ],
        TonyoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _dayHeading(day),
                          style: const TextStyle(
                            color: TonyoColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Peak ${formatHour(summary.peakTime)}',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: TonyoColors.mint.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${summary.peakEnergy.round()}',
                      style: const TextStyle(
                        color: TonyoColors.mint,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ForecastChart(points: points),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricPill(
                    icon: Icons.show_chart_rounded,
                    label: 'Average ${summary.averageEnergy.round()}',
                  ),
                  _MetricPill(
                    icon: Icons.unfold_more_rounded,
                    label:
                        '${summary.lowEnergy.round()}–${summary.peakEnergy.round()} range',
                  ),
                  _MetricPill(
                    icon: Icons.shield_outlined,
                    label: '±${summary.averageUncertainty.round()} uncertainty',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: TonyoColors.border, height: 1),
              const SizedBox(height: 11),
              Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: TonyoColors.muted,
                    size: 15,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '$sourceLabel · ${_updatedLabel(summary.updatedAt)}',
                      style: const TextStyle(
                        color: TonyoColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SectionHeader('What shapes this curve'),
        const TonyoCard(
          child: Column(
            children: [
              _ModelInputRow(
                icon: Icons.bedtime_outlined,
                title: 'Sleep timing & recovery',
                detail: 'Recent duration, bedtime, and wake rhythm',
                color: TonyoColors.blue,
              ),
              Divider(height: 24, color: TonyoColors.border),
              _ModelInputRow(
                icon: Icons.wb_sunny_outlined,
                title: 'Circadian rhythm',
                detail: 'Morning rise, afternoon dip, and evening decline',
                color: TonyoColors.amber,
              ),
              Divider(height: 24, color: TonyoColors.border),
              _ModelInputRow(
                icon: Icons.menu_book_outlined,
                title: 'Workload & check-ins',
                detail: 'Study, exercise, hydration, mood, and stress',
                color: TonyoColors.violet,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeekForecast extends StatelessWidget {
  const _WeekForecast({
    required this.summaries,
    required this.loading,
    required this.onRetry,
  });

  final List<ForecastDaySummary> summaries;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) {
      return _ForecastEmptyState(loading: loading, onRetry: onRetry);
    }
    final weeklyAverage =
        summaries.fold<double>(0, (sum, item) => sum + item.averageEnergy) /
        summaries.length;
    final lowConfidenceDays = summaries
        .where((summary) => summary.isLowConfidence)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summaries.length < AppController.forecastDayCount) ...[
          _StatusBanner(
            icon: Icons.calendar_view_week_rounded,
            color: TonyoColors.amber,
            title: 'Partial weekly forecast',
            detail:
                '${summaries.length} of ${AppController.forecastDayCount} days are available. Refresh to fill the missing days.',
          ),
          const SizedBox(height: 10),
        ],
        TonyoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '7-DAY OUTLOOK',
                style: TextStyle(
                  color: TonyoColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Average ${weeklyAverage.round()}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                lowConfidenceDays == 0
                    ? 'All daily forecasts have usable confidence.'
                    : '$lowConfidenceDays ${lowConfidenceDays == 1 ? 'day has' : 'days have'} wider uncertainty.',
                style: const TextStyle(color: TonyoColors.muted, fontSize: 10),
              ),
              const SizedBox(height: 18),
              _WeekChart(summaries: summaries),
            ],
          ),
        ),
        const SectionHeader('Daily summaries'),
        ...summaries.map(
          (summary) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: TonyoCard(
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _shortDay(summary.day),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          formatDate(summary.day),
                          style: const TextStyle(
                            color: TonyoColors.muted,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Peak ${summary.peakEnergy.round()} at ${formatHour(summary.peakTime)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${summary.lowEnergy.round()}–${summary.peakEnergy.round()} range · ±${summary.averageUncertainty.round()}',
                          style: TextStyle(
                            color: summary.isLowConfidence
                                ? TonyoColors.amber
                                : TonyoColors.muted,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${summary.averageEnergy.round()}',
                    style: const TextStyle(
                      color: TonyoColors.mint,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.summaries});

  final List<ForecastDaySummary> summaries;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 180,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final summary in summaries)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${summary.averageEnergy.round()}',
                  style: const TextStyle(
                    color: TonyoColors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  height: summary.averageEnergy.clamp(12, 100) * 1.25,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: summary.isLowConfidence
                          ? [TonyoColors.primary, TonyoColors.amber]
                          : [TonyoColors.primary, TonyoColors.mint],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _shortDay(summary.day).substring(0, 1),
                  style: const TextStyle(
                    color: TonyoColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _ForecastEmptyState extends StatelessWidget {
  const _ForecastEmptyState({required this.loading, required this.onRetry});

  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        children: [
          if (loading)
            const CircularProgressIndicator()
          else
            const MetricIcon(
              icon: Icons.query_stats_rounded,
              color: TonyoColors.violet,
            ),
          const SizedBox(height: 14),
          Text(
            loading ? 'Building your forecast…' : 'No forecast available',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            loading
                ? 'Combining your recent signals and check-ins.'
                : 'Tonyo could not find hourly points for this range.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: TonyoColors.muted, fontSize: 11),
          ),
          if (!loading) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Build forecast'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      border: Border.all(color: color.withValues(alpha: .25)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(color: TonyoColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: TonyoColors.background,
      border: Border.all(color: TonyoColors.border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: TonyoColors.muted, size: 13),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: TonyoColors.muted, fontSize: 9),
        ),
      ],
    ),
  );
}

class _ModelInputRow extends StatelessWidget {
  const _ModelInputRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      MetricIcon(icon: icon, color: color),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
              detail,
              style: const TextStyle(color: TonyoColors.muted, fontSize: 9),
            ),
          ],
        ),
      ),
    ],
  );
}

String _dayHeading(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(day.year, day.month, day.day);
  if (target == today) return 'TODAY · ${formatDate(day).toUpperCase()}';
  if (target == today.add(const Duration(days: 1))) {
    return 'TOMORROW · ${formatDate(day).toUpperCase()}';
  }
  return '${_shortDay(day).toUpperCase()} · ${formatDate(day).toUpperCase()}';
}

String _shortDay(DateTime value) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][value.weekday - 1];

String _updatedLabel(DateTime? updatedAt) {
  if (updatedAt == null) return 'Update time unavailable';
  final elapsed = DateTime.now().difference(updatedAt);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'Updated just now';
  if (elapsed.inMinutes < 60) return 'Updated ${elapsed.inMinutes}m ago';
  if (elapsed.inHours < 24) return 'Updated ${elapsed.inHours}h ago';
  return 'Updated ${elapsed.inDays}d ago';
}
