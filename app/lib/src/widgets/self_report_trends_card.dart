import 'package:flutter/material.dart';

import '../check_in_measurement.dart';
import '../l10n/app_localizations.dart';
import '../language_preference.dart';
import '../models.dart';
import '../self_report_trends_logic.dart';
import '../theme.dart';
import 'common_widgets.dart';

/// Descriptive raw-data views. Neither painter supplies model inputs or scores.
class SelfReportTrendsCard extends StatefulWidget {
  const SelfReportTrendsCard({
    super.key,
    required this.checkIns,
    required this.signals,
    required this.now,
  });

  final List<DailyCheckIn> checkIns;
  final List<SignalReading> signals;
  final DateTime now;

  @override
  State<SelfReportTrendsCard> createState() => _SelfReportTrendsCardState();
}

class _SelfReportTrendsCardState extends State<SelfReportTrendsCard> {
  String _measure = 'energy';
  CheckInPeriod _period = CheckInPeriod.morning;
  String? _language;

  @override
  Widget build(BuildContext context) {
    final language = _language ?? AppLocalizations.of(context).language;
    final summary = SelfReportTrendsLogic.build(
      checkIns: widget.checkIns,
      signals: widget.signals,
      now: widget.now,
      period: _period,
      questionnaireLanguage: language,
    );
    final series = summary.series[_measure]!;
    final measureLabel = context.tr(
      CheckInMeasurement.items.firstWhere((item) => item.id == _measure).label,
    );
    final pairs = [
      for (var index = 0; index < summary.days.length; index++)
        if (series.values[index] != null &&
            summary.days[index].matchedSleep?.isMatched == true)
          (
            day: summary.days[index],
            value: series.values[index]!,
            hours: summary.days[index].matchedSleep!.durationHours!,
          ),
    ];
    final pairVariation =
        pairs.map((pair) => (pair.hours, pair.value)).toSet().length > 1;
    final muted = TextStyle(
      color: TonyoPalette.of(context).muted,
      fontSize: 12,
    );
    return TonyoCard(
      key: const Key('self-report-trends'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Self-report trends'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('Your raw reports and preceding main sleep'),
            style: muted,
          ),
          const SizedBox(height: 16),
          _SelectorLabel('Measure'),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final item in CheckInMeasurement.items)
                ChoiceChip(
                  key: Key('self-report-trend-measure-${item.id}'),
                  label: Text(context.tr(item.label)),
                  selected: _measure == item.id,
                  onSelected: (_) => setState(() => _measure = item.id),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _SelectorLabel('Reported period'),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final period in CheckInPeriod.values)
                ChoiceChip(
                  key: Key('self-report-trend-period-${period.name}'),
                  label: Text(context.tr(period.label)),
                  selected: _period == period,
                  onSelected: (_) => setState(() => _period = period),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _SelectorLabel('Questionnaire language'),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final choice in supportedLanguagePreferences)
                ChoiceChip(
                  key: Key('self-report-trend-language-$choice'),
                  label: Text(languageDisplayName(choice)),
                  selected: language == choice,
                  onSelected: (_) => setState(() => _language = choice),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            context.tr(
              '{start} to {end} · {days} captured dates',
              args: {
                'start': summary.startDate,
                'end': summary.endDate,
                'days': summary.windowDays,
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(
              'Source: reports and sleep records saved on this device.',
            ),
            style: muted,
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(
              'Latest compatible report per date and period. Only the current draft version with matching questions and language is included. Demo records are excluded.',
            ),
            style: muted,
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              '{reports} of {days} dates have a report · {answered} answers · {missing} missing',
              args: {
                'reports': summary.selectedReportCount,
                'days': summary.windowDays,
                'answered': series.answeredCount,
                'missing': summary.windowDays - series.answeredCount,
              },
            ),
            key: const Key('self-report-trend-counts'),
          ),
          const SizedBox(height: 18),
          _SelectorLabel('Ratings over time'),
          if (series.answeredCount >= 8)
            _ChartFrame(
              semanticsLabel: context.tr(
                'Raw {measure} ratings, 1–10. {count} answered dates. Gaps are missing answers. Exact values are in the per-date records.',
                args: {'measure': measureLabel, 'count': series.answeredCount},
              ),
              leftLabel: summary.startDate.substring(5),
              rightLabel: summary.endDate.substring(5),
              axisLabel: context.tr('Captured date'),
              painter: _RatingTrendPainter(
                values: series.values,
                color: TonyoPalette.of(context).primary,
                grid: TonyoPalette.of(context).border,
              ),
              chartKey: const Key('self-report-rating-chart'),
            )
          else ...[
            Text(
              context.tr(
                summary.selectedReportCount == 0
                    ? 'No matching self-reports in this window.'
                    : series.answeredCount == 0
                    ? 'No answers for this measure in this window.'
                    : 'Charts appear after 8 answered dates. Available answers are shown below.',
              ),
            ),
            for (var index = 0; index < summary.days.length; index++)
              if (series.values[index] case final value?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.tr(
                      '{date}: {value} / 10',
                      args: {
                        'date': summary.days[index].date,
                        'value': value.toInt(),
                      },
                    ),
                    key: Key('self-report-sparse-${summary.days[index].date}'),
                  ),
                ),
          ],
          const SizedBox(height: 20),
          _SelectorLabel('Ratings and preceding main sleep'),
          Text(
            context.tr(
              '{pairs} paired answers · {unpaired} answers without a sleep match',
              args: {
                'pairs': series.matchedCount,
                'unpaired': series.answeredCount - series.matchedCount,
              },
            ),
            key: const Key('self-report-sleep-counts'),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(
              'Sleep ends before the report within 24 hours. Only one eligible main sleep is paired; naps and ambiguous matches are excluded. These paired records do not show cause or medical significance.',
            ),
            style: muted,
          ),
          const SizedBox(height: 10),
          Text(
            context.tr(
              'Pairs use records available now; later edits can change them.',
            ),
            style: muted,
          ),
          const SizedBox(height: 10),
          if (pairs.length >= 8 && pairVariation)
            _ChartFrame(
              semanticsLabel: context.tr(
                '{count} paired records. Horizontal axis: preceding main sleep in hours. Vertical axis: raw {measure} rating, 1–10. Exact pairs and sources are in the per-date records.',
                args: {'count': pairs.length, 'measure': measureLabel},
              ),
              leftLabel: '0',
              rightLabel: _number(
                context,
                _sleepAxisMaximum(pairs.map((pair) => pair.hours)),
              ),
              axisLabel: context.tr('Preceding main sleep (hours)'),
              painter: _SleepRatingPainter(
                points: [
                  for (final pair in pairs) Offset(pair.hours, pair.value),
                ],
                maximumHours: _sleepAxisMaximum(
                  pairs.map((pair) => pair.hours),
                ),
                color: TonyoPalette.of(context).primary,
                grid: TonyoPalette.of(context).border,
              ),
              chartKey: const Key('self-report-sleep-chart'),
            )
          else ...[
            Text(
              context.tr(
                pairs.isEmpty
                    ? 'No paired answers in this window.'
                    : pairs.length >= 8 && !pairVariation
                    ? 'These paired records have no variation to compare.'
                    : 'A sleep chart appears after 8 paired answers. Available pairs are shown below.',
              ),
            ),
            for (final pair in pairs)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(
                        '{date}: {value} / 10 · {hours} hours of sleep',
                        args: {
                          'date': pair.day.date,
                          'value': pair.value.toInt(),
                          'hours': _exactNumber(context, pair.hours),
                        },
                      ),
                    ),
                    Text(
                      _sleepProvenance(context, pair.day.matchedSleep!),
                      style: muted,
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 14),
          ExpansionTile(
            key: PageStorageKey(
              'self-report-trend-records-$_measure-${_period.name}-$language',
            ),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text(context.tr('Per-date records and missing answers')),
            subtitle: Text(
              context.tr('Exact values, sleep sources and unmatched reasons'),
              style: muted,
            ),
            children: [
              for (var index = 0; index < summary.days.length; index++)
                _DateRecord(
                  key: Key(
                    'self-report-trend-record-${summary.days[index].date}',
                  ),
                  day: summary.days[index],
                  value: series.values[index],
                  measure: measureLabel,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectorLabel extends StatelessWidget {
  const _SelectorLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      context.tr(label),
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
  );
}

class _DateRecord extends StatelessWidget {
  const _DateRecord({
    super.key,
    required this.day,
    required this.value,
    required this.measure,
  });
  final SelfReportTrendDay day;
  final double? value;
  final String measure;

  @override
  Widget build(BuildContext context) {
    final sleep = day.matchedSleep;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(day.date, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              day.response == null
                  ? context.tr('No matching self-report on this date.')
                  : context.tr(
                      '{measure}: {value}',
                      args: {
                        'measure': measure,
                        'value': value == null
                            ? context.tr('Not answered')
                            : '${value!.toInt()} / 10',
                      },
                    ),
            ),
            if (sleep?.isMatched == true) ...[
              Text(
                context.tr(
                  'Preceding main sleep: {hours} hours',
                  args: {'hours': _exactNumber(context, sleep!.durationHours!)},
                ),
              ),
              Text(_sleepProvenance(context, sleep)),
            ] else if (sleep?.reason case final reason?)
              Text(context.tr(reason)),
          ],
        ),
      ),
    );
  }
}

String _sleepProvenance(BuildContext context, SelfReportSleepMatch sleep) =>
    context.tr(
      '{source} · {availability}',
      args: {
        'source': context.tr(
          sleep.source == SignalSource.healthKit
              ? 'Apple Health'
              : 'Manual entry',
        ),
        'availability': context.tr(
          sleep.availabilityKnown
              ? 'Recording time available'
              : 'Availability time unknown',
        ),
      },
    );

String _number(BuildContext context, double value) {
  final text = value.toStringAsFixed(1);
  return AppLocalizations.of(context).language == 'es'
      ? text.replaceAll('.', ',')
      : text;
}

String _exactNumber(BuildContext context, double value) {
  final text = value == value.roundToDouble() ? '${value.toInt()}' : '$value';
  return AppLocalizations.of(context).language == 'es'
      ? text.replaceAll('.', ',')
      : text;
}

double _sleepAxisMaximum(Iterable<double> values) {
  final maximum = values.fold<double>(
    16,
    (current, value) => value > current ? value : current,
  );
  return maximum.ceilToDouble();
}

class _ChartFrame extends StatelessWidget {
  const _ChartFrame({
    required this.semanticsLabel,
    required this.leftLabel,
    required this.rightLabel,
    required this.axisLabel,
    required this.painter,
    required this.chartKey,
  });
  final String semanticsLabel;
  final String leftLabel;
  final String rightLabel;
  final String axisLabel;
  final CustomPainter painter;
  final Key chartKey;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    image: true,
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('Raw rating (1–10)')),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 38,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final tick in [10, 5, 1])
                        Positioned(
                          top: _ratingY(tick.toDouble(), const Size(0, 200)),
                          left: 0,
                          child: FractionalTranslation(
                            translation: const Offset(0, -.5),
                            child: Text('$tick'),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: CustomPaint(key: chartKey, painter: painter),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Row(
              children: [
                Expanded(child: Text(leftLabel)),
                Expanded(child: Text(rightLabel, textAlign: TextAlign.end)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(axisLabel),
        ],
      ),
    ),
  );
}

// Painters contain marks only; axes, summaries and exact records are widgets.
const _plotInset = 12.0;
double _ratingY(double rating, Size size) =>
    _plotInset + (10 - rating) / 9 * (size.height - _plotInset * 2);

void _drawGrid(Canvas canvas, Size size, Color color) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = 1;
  for (final tick in [1.0, 5.0, 10.0]) {
    final y = _ratingY(tick, size);
    canvas.drawLine(
      Offset(_plotInset, y),
      Offset(size.width - _plotInset, y),
      paint,
    );
  }
}

class _RatingTrendPainter extends CustomPainter {
  _RatingTrendPainter({
    required this.values,
    required this.color,
    required this.grid,
  });
  final List<double?> values;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size, grid);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    Offset? previous;
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      if (value == null) {
        previous = null;
        continue;
      }
      final point = Offset(
        _plotInset +
            index / (values.length - 1) * (size.width - _plotInset * 2),
        _ratingY(value, size),
      );
      if (previous != null) canvas.drawLine(previous, point, paint);
      canvas.drawCircle(point, 3.5, paint);
      previous = point;
    }
  }

  @override
  bool shouldRepaint(_RatingTrendPainter oldDelegate) =>
      values != oldDelegate.values ||
      color != oldDelegate.color ||
      grid != oldDelegate.grid;
}

class _SleepRatingPainter extends CustomPainter {
  _SleepRatingPainter({
    required this.points,
    required this.maximumHours,
    required this.color,
    required this.grid,
  });
  final List<Offset> points;
  final double maximumHours;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size, grid);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final pair in points) {
      canvas.drawCircle(
        Offset(
          _plotInset + pair.dx / maximumHours * (size.width - _plotInset * 2),
          _ratingY(pair.dy, size),
        ),
        4,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SleepRatingPainter oldDelegate) =>
      points != oldDelegate.points ||
      maximumHours != oldDelegate.maximumHours ||
      color != oldDelegate.color ||
      grid != oldDelegate.grid;
}
