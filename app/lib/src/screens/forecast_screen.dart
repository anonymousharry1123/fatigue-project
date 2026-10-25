import 'package:flutter/material.dart';

import '../app.dart';
import '../app_controller.dart';
import '../evidence_provenance.dart';
import '../l10n/app_localizations.dart';
import '../local_day.dart';
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
    final selectedDay = localDay(today, _range == 1 ? 1 : 0);
    final canEstimate = controller.score.canEstimateEnergy;
    final points = canEstimate
        ? controller.forecastDataFor(selectedDay)
        : const <ForecastPoint>[];
    final windows = _range == 2 || !canEstimate
        ? const <ForecastWindow>[]
        : controller.windowsFor(selectedDay);
    final week = canEstimate
        ? controller
              .forecastSummariesFor(today)
              .where(
                (summary) => !summary.isStaleAt(
                  today,
                  maximumAge: AppController.forecastFreshnessWindow,
                ),
              )
              .toList()
        : const <ForecastDaySummary>[];

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
                  context.tr('Energy Forecast'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton.filledTonal(
                tooltip: context.tr('Refresh forecast'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
          Text(
            context.tr(
              'Experimental hourly curve from recorded inputs and fixed timing rules.',
            ),
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<int>(
            direction: MediaQuery.textScalerOf(context).scale(1) > 1.3
                ? Axis.vertical
                : Axis.horizontal,
            segments: [
              ButtonSegment(value: 0, label: Text(context.tr('Today'))),
              ButtonSegment(value: 1, label: Text(context.tr('Tomorrow'))),
              ButtonSegment(value: 2, label: Text(context.tr('Week'))),
            ],
            selected: {_range},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() => _range = value.first),
            style: SegmentedButton.styleFrom(
              minimumSize: const Size(48, 48),
              backgroundColor: TonyoPalette.of(context).surface,
              selectedBackgroundColor: TonyoPalette.of(context).primary,
              selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          if (controller.forecastError case final error?) ...[
            const SizedBox(height: 14),
            _StatusBanner(
              icon: Icons.cloud_off_rounded,
              color: TonyoPalette.of(context).warning,
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
              windows: windows,
              loading: controller.isForecastLoading,
              sourceLabel: _sourceLabel(controller),
              onRetry: () =>
                  controller.refreshForecasts(forceRecalculate: true),
            ),
          const SizedBox(height: 14),
          Text(
            context.tr(
              'The curve and shaded bands are uncalibrated estimates, not statistical confidence intervals. They do not establish when you will feel alert or tired, or whether exercise is safe.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 10,
            ),
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
    required this.windows,
    required this.loading,
    required this.sourceLabel,
    required this.onRetry,
  });

  final DateTime day;
  final List<ForecastPoint> points;
  final List<ForecastWindow> windows;
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
    if (stale) {
      return Column(
        children: [
          _StatusBanner(
            icon: Icons.history_rounded,
            color: TonyoPalette.of(context).warning,
            title: 'Forecast is out of date',
            detail: 'Refresh to check whether current entries support a curve.',
          ),
          const SizedBox(height: 10),
          _ForecastEmptyState(loading: loading, onRetry: onRetry),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary.isLowConfidence) ...[
          _StatusBanner(
            icon: Icons.visibility_outlined,
            color: TonyoPalette.of(context).secondary,
            title: 'Limited data quality',
            detail: context.tr(
              'The displayed band averages ±{points} points. This width is a rule-based display estimate, not a calibrated error range.',
              args: {'points': summary.averageUncertainty.round()},
            ),
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
                          _dayHeading(context, day),
                          style: TextStyle(
                            color: TonyoPalette.of(context).muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          context.tr(
                            'Curve high {time}',
                            args: {'time': _time(context, summary.peakTime)},
                          ),
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
                      color: TonyoPalette.of(
                        context,
                      ).primary.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${summary.peakEnergy.round()}',
                      style: TextStyle(
                        color: TonyoPalette.of(context).primary,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
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
                    label: context.tr(
                      'Average {value}',
                      args: {'value': summary.averageEnergy.round()},
                    ),
                  ),
                  _MetricPill(
                    icon: Icons.unfold_more_rounded,
                    label: context.tr(
                      '{low}–{high} range',
                      args: {
                        'low': summary.lowEnergy.round(),
                        'high': summary.peakEnergy.round(),
                      },
                    ),
                  ),
                  _MetricPill(
                    icon: Icons.shield_outlined,
                    label: context.tr(
                      '±{points} uncalibrated band',
                      args: {'points': summary.averageUncertainty.round()},
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: TonyoPalette.of(context).border, height: 1),
              const SizedBox(height: 11),
              Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    color: TonyoPalette.of(context).muted,
                    size: 15,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${context.tr(sourceLabel)} · ${_updatedLabel(context, summary.updatedAt)}',
                      style: TextStyle(
                        color: TonyoPalette.of(context).muted,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionHeader(context.tr('Curve markers')),
        Text(
          context.tr(
            'These markers describe the formula’s curve. Their timing is not a validated prediction of focus, a crash, or recovery.',
          ),
          style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 10),
        ),
        const SizedBox(height: 10),
        ...windows.map(
          (window) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ForecastWindowCard(window: window),
          ),
        ),
        SectionHeader(context.tr('What shapes this curve')),
        TonyoCard(
          child: Column(
            children: [
              _ModelInputRow(
                icon: Icons.bedtime_outlined,
                title: 'Recorded sleep timing',
                detail:
                    'Recent wake/bed observations and your saved schedule adjust timing; they do not measure recovery.',
                color: TonyoPalette.of(context).primary,
              ),
              Divider(height: 24, color: TonyoPalette.of(context).border),
              _ModelInputRow(
                icon: Icons.wb_sunny_outlined,
                title: 'Fixed clock-time curve',
                detail:
                    'An assumed daily shape, not a measurement of your internal circadian phase.',
                color: TonyoPalette.of(context).secondary,
              ),
              Divider(height: 24, color: TonyoPalette.of(context).border),
              _ModelInputRow(
                icon: Icons.menu_book_outlined,
                title: 'Experimental Energy reference',
                detail:
                    'Current scored inputs and fixed forecast adjustments. Caffeine, fluid volume and exercise duration add no recovery rewards.',
                color: TonyoPalette.of(context).secondary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ForecastWindowCard extends StatelessWidget {
  const _ForecastWindowCard({required this.window});

  final ForecastWindow window;

  @override
  Widget build(BuildContext context) {
    final style = switch (window.type) {
      ForecastWindowType.peak => (
        title: 'Curve high',
        icon: Icons.center_focus_strong_rounded,
        color: TonyoPalette.of(context).primary,
      ),
      ForecastWindowType.crash => (
        title: 'Curve low',
        icon: Icons.trending_down_rounded,
        color: TonyoPalette.of(context).error,
      ),
      ForecastWindowType.recovery => (
        title: 'Later curve rise',
        icon: Icons.battery_charging_full_rounded,
        color: TonyoPalette.of(context).secondary,
      ),
    };
    return TonyoCard(
      key: Key('forecast-window-${window.type.name}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MetricIcon(icon: style.icon, color: style.color),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(style.title),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_time(context, window.start)}–${_time(context, window.end)}',
                      style: TextStyle(
                        color: style.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${window.energy}',
                  style: TextStyle(
                    color: style.color,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            _windowReason(context, window),
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: TonyoPalette.of(context).border, height: 1),
          const SizedBox(height: 10),
          if (window.evidence.isEmpty)
            Row(
              children: [
                Icon(
                  Icons.link_off_rounded,
                  color: TonyoPalette.of(context).muted,
                  size: 16,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    context.tr(
                      'No linked signal or check-in documents available.',
                    ),
                    style: TextStyle(
                      color: TonyoPalette.of(context).muted,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            )
          else ...[
            Text(
              context.tr('LINKED EVIDENCE'),
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 8),
            for (final evidence in window.evidence) ...[
              _ForecastEvidenceRow(evidence: evidence, accent: style.color),
              if (evidence != window.evidence.last)
                Divider(height: 18, color: TonyoPalette.of(context).border),
            ],
          ],
        ],
      ),
    );
  }
}

class _ForecastEvidenceRow extends StatelessWidget {
  const _ForecastEvidenceRow({required this.evidence, required this.accent});

  final ForecastEvidence evidence;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isSignal = evidence.kind == ForecastEvidenceKind.signal;
    final icon = evidence.signalType == null
        ? Icons.mood_rounded
        : iconForSignal(evidence.signalType!);
    final kindLabel = isSignal ? 'Linked signal' : 'Linked check-in';
    final signal = AppScope.of(
      context,
    ).signals.where((row) => row.id == evidence.id).firstOrNull;
    final isDemo =
        EvidenceProvenance.hasDemoMarker([evidence.id]) ||
        (signal != null && EvidenceProvenance.signalIsDemo(signal));
    final source = isDemo
        ? 'Demo / synthetic example'
        : switch (evidence.source) {
            SignalSource.healthKit => 'HealthKit',
            SignalSource.oura => 'Oura',
            SignalSource.appleScreenTime => 'Apple Screen Time',
            SignalSource.model => 'Model',
            SignalSource.manual => 'Manual',
            null => 'Manual',
          };
    return Row(
      key: Key('forecast-evidence-${evidence.kind.name}-${evidence.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accent, size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(evidence.label),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                context.tr(evidence.detail),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 9,
                ),
              ),
              Text(
                context.tr(
                  '{source} · {date} at {time}',
                  args: {
                    'source': context.tr(source),
                    'date': _date(context, evidence.timestamp),
                    'time': _time(context, evidence.timestamp),
                  },
                ),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 8,
                ),
              ),
              const SizedBox(height: 4),
              _evidenceTag(context, kindLabel),
            ],
          ),
        ),
      ],
    );
  }

  Widget _evidenceTag(BuildContext context, String kindLabel) => Tooltip(
    message: context.tr(
      '{kind} document {id}',
      args: {'kind': context.tr(kindLabel), 'id': evidence.id},
    ),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        context.tr(kindLabel),
        style: TextStyle(
          color: accent,
          fontSize: 7,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
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
            color: TonyoPalette.of(context).warning,
            title: 'Partial weekly forecast',
            detail: context.tr(
              '{available} of {total} days are available. Refresh to fill the missing days.',
              args: {
                'available': summaries.length,
                'total': AppController.forecastDayCount,
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
        TonyoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('7-DAY OUTLOOK'),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr(
                  'Average {value}',
                  args: {'value': weeklyAverage.round()},
                ),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                lowConfidenceDays == 0
                    ? context.tr(
                        'All displayed bands are uncalibrated estimates.',
                      )
                    : context.tr(
                        lowConfidenceDays == 1
                            ? '{days} day has a wider uncalibrated band.'
                            : '{days} days have a wider uncalibrated band.',
                        args: {'days': lowConfidenceDays},
                      ),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 18),
              _WeekChart(summaries: summaries),
            ],
          ),
        ),
        SectionHeader(context.tr('Daily summaries')),
        ...summaries.map(
          (summary) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _DaySummaryCard(summary: summary),
          ),
        ),
      ],
    );
  }
}

class _DaySummaryCard extends StatelessWidget {
  const _DaySummaryCard({required this.summary});

  final ForecastDaySummary summary;

  @override
  Widget build(BuildContext context) {
    final date = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _shortDay(context, summary.day),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          _date(context, summary.day),
          style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 9),
        ),
      ],
    );
    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(
            'Curve high {value} at {time}',
            args: {
              'value': summary.peakEnergy.round(),
              'time': _time(context, summary.peakTime),
            },
          ),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          '${context.tr('{low}–{high} range', args: {'low': summary.lowEnergy.round(), 'high': summary.peakEnergy.round()})} · ±${summary.averageUncertainty.round()}',
          style: TextStyle(
            color: summary.isLowConfidence
                ? TonyoPalette.of(context).warning
                : TonyoPalette.of(context).muted,
            fontSize: 9,
          ),
        ),
      ],
    );
    final average = Semantics(
      label: context.tr('Average estimated Energy'),
      value: context.tr(
        '{value} out of 100',
        args: {'value': summary.averageEnergy.round()},
      ),
      excludeSemantics: true,
      child: Text(
        '${summary.averageEnergy.round()}',
        style: TextStyle(
          color: TonyoPalette.of(context).primary,
          fontSize: 21,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return TonyoCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth <
              240 * MediaQuery.textScalerOf(context).scale(1)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: date),
                    average,
                  ],
                ),
                const SizedBox(height: 12),
                detail,
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 48, child: date),
              Expanded(child: detail),
              const SizedBox(width: 8),
              average,
            ],
          );
        },
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.summaries});

  final List<ForecastDaySummary> summaries;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final minimumWidth = summaries.length * 32 * scale;
      final chart = SingleChildScrollView(
        key: const Key('forecast-week-chart-scroll'),
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: minimumWidth > constraints.maxWidth
              ? minimumWidth
              : constraints.maxWidth,
          height: 180 + 45 * (scale - 1).clamp(0, double.infinity),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final summary in summaries)
                Expanded(
                  child: Semantics(
                    container: true,
                    excludeSemantics: true,
                    label: context.tr(
                      '{date}. Average estimated Energy: {value} out of 100. Uncalibrated display band: plus or minus {points} points; not a statistical confidence interval.',
                      args: {
                        'date': MaterialLocalizations.of(
                          context,
                        ).formatFullDate(summary.day),
                        'value': summary.averageEnergy.round(),
                        'points': summary.averageUncertainty.round(),
                      },
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${summary.averageEnergy.round()}',
                          style: TextStyle(
                            color: TonyoPalette.of(context).muted,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          height: summary.averageEnergy.clamp(12, 100) * 1.25,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: summary.isLowConfidence
                                ? TonyoPalette.of(context).warning
                                : TonyoPalette.of(context).primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          MaterialLocalizations.of(
                            context,
                          ).narrowWeekdays[summary.day.weekday % 7],
                          style: TextStyle(
                            color: TonyoPalette.of(context).muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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
            MetricIcon(
              icon: Icons.query_stats_rounded,
              color: TonyoPalette.of(context).secondary,
            ),
          const SizedBox(height: 14),
          Text(
            context.tr(
              loading ? 'Building your forecast…' : 'No forecast available',
            ),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(
              loading
                  ? 'Combining your recent signals and check-ins.'
                  : 'Not enough current information to estimate this range. An optional check-in can add an observation.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 11,
            ),
          ),
          if (!loading) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.tr('Build forecast')),
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
                context.tr(title),
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                context.tr(detail),
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
      color: TonyoPalette.of(context).background,
      border: Border.all(color: TonyoPalette.of(context).border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: TonyoPalette.of(context).muted, size: 13),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 9,
            ),
          ),
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
            Text(
              context.tr(title),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              context.tr(detail),
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

String _dayHeading(BuildContext context, DateTime day) {
  final now = DateTime.now();
  final today = localDay(now);
  final target = localDay(day);
  if (target == today) {
    return '${context.tr('TODAY')} · ${_date(context, day).toUpperCase()}';
  }
  if (target == localDay(today, 1)) {
    return '${context.tr('TOMORROW')} · ${_date(context, day).toUpperCase()}';
  }
  return '${_shortDay(context, day).toUpperCase()} · ${_date(context, day).toUpperCase()}';
}

String _shortDay(BuildContext context, DateTime value) => context.tr(
  const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][value.weekday - 1],
);

String _date(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatShortMonthDay(value.toLocal());

String _time(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

String _updatedLabel(BuildContext context, DateTime? updatedAt) {
  if (updatedAt == null) return context.tr('Update time unavailable');
  final elapsed = DateTime.now().difference(updatedAt);
  if (elapsed.isNegative || elapsed.inMinutes < 1) {
    return context.tr('Updated just now');
  }
  if (elapsed.inMinutes < 60) {
    return context.tr(
      'Updated {minutes}m ago',
      args: {'minutes': elapsed.inMinutes},
    );
  }
  if (elapsed.inHours < 24) {
    return context.tr('Updated {hours}h ago', args: {'hours': elapsed.inHours});
  }
  return context.tr('Updated {days}d ago', args: {'days': elapsed.inDays});
}

String _windowReason(BuildContext context, ForecastWindow window) {
  // Localize presentation only. Saved source data and deterministic rules keep
  // their original values and calculation version.
  if (window.evidence.isEmpty) return context.tr(window.reason);
  final labels = window.evidence
      .take(2)
      .map((item) => context.tr(item.label).toLowerCase())
      .toList();
  final linked = labels.length == 1
      ? labels.first
      : context.tr(
          '{first} and {second}',
          args: {'first': labels[0], 'second': labels[1]},
        );
  return context.tr(
    switch (window.type) {
      ForecastWindowType.peak =>
        'Experimental higher point in the curve, using {inputs}. Timing is unvalidated.',
      ForecastWindowType.crash =>
        'Experimental lower point in the curve, using {inputs}. A crash is not established.',
      ForecastWindowType.recovery =>
        'Experimental later rise in the curve, using {inputs}. Recovery is not established.',
    },
    args: {'inputs': linked},
  );
}
