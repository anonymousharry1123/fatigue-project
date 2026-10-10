import 'package:flutter/material.dart';

import '../check_in_measurement.dart';
import '../l10n/app_localizations.dart';
import '../models.dart';
import '../self_report_reference_logic.dart';
import '../theme.dart';

/// A read-only description of saved self-reports, separate from model inputs.
class SelfReportReferenceCard extends StatelessWidget {
  const SelfReportReferenceCard({
    super.key,
    required this.current,
    required this.checkIns,
    required this.now,
  });

  final DailyCheckIn current;
  final List<DailyCheckIn> checkIns;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final summary = SelfReportReferenceLogic.build(
      checkIns: checkIns,
      current: current,
      asOf: now,
    );
    final muted = TextStyle(
      color: TonyoPalette.of(context).muted,
      fontSize: 12,
    );
    return ExpansionTile(
      key: PageStorageKey('self-report-reference-${current.id}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(context.tr('Recent personal averages')),
      subtitle: Text(
        context.tr(
          'Your previous {period} reports',
          args: {'period': context.tr(current.period.label)},
        ),
        style: muted,
      ),
      children: [
        if (!summary.currentCompatible)
          Text(
            context.tr(
              'Comparison is unavailable for this questionnaire format.',
            ),
          )
        else ...[
          Text(
            context.tr(
              'Each measure stays separate. Personal averages describe your reports, not a healthy or normal range.',
            ),
            style: muted,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Previous {days} days · {start} to {end} · Excludes today',
              args: {
                'days': summary.windowDays,
                'start': summary.startDate,
                'end': summary.endDate,
              },
            ),
            style: muted,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
              'Same questionnaire language: {language}',
              args: {'language': current.questionnaireLanguage},
            ),
            style: muted,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Averages need at least {minimum} days per measure. Only matching questions and language count; the latest report per day is used. Missing answers stay missing.',
              args: {'minimum': summary.minimumDays},
            ),
            style: muted,
          ),
          for (final item in CheckInMeasurement.items) ...[
            const SizedBox(height: 14),
            _ReferenceMetric(
              key: Key('self-report-reference-${current.id}-${item.id}'),
              label: context.tr(item.label),
              metric: summary.metrics[item.id]!,
              minimumDays: summary.minimumDays,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            context.tr(
              'Based on saved reports available now; edits can change these averages.',
            ),
            style: muted,
          ),
        ],
      ],
    );
  }
}

class _ReferenceMetric extends StatelessWidget {
  const _ReferenceMetric({
    super.key,
    required this.label,
    required this.metric,
    required this.minimumDays,
  });

  final String label;
  final SelfReportReferenceMetric metric;
  final int minimumDays;

  @override
  Widget build(BuildContext context) {
    final average = metric.average;
    final currentValue = metric.currentValue;
    final difference = metric.difference;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          average == null
              ? context.tr(
                  '{measure}: Not enough history',
                  args: {'measure': label},
                )
              : context.tr(
                  '{measure} average: {value} / 10',
                  args: {'measure': label, 'value': _number(context, average)},
                ),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          average == null
              ? context.tr(
                  '{count} of {minimum} days needed',
                  args: {'count': metric.sampleCount, 'minimum': minimumDays},
                )
              : context.tr(
                  '{count} days with an answer',
                  args: {'count': metric.sampleCount},
                ),
        ),
        Text(
          currentValue == null
              ? context.tr('Today’s answer is missing; no comparison.')
              : context.tr(
                  'Today: {value} / 10',
                  args: {'value': currentValue.toInt()},
                ),
        ),
        if (difference != null)
          Text(
            context.tr(
              difference > 0
                  ? 'Higher than your recent average'
                  : difference < 0
                  ? 'Lower than your recent average'
                  : 'Matches your recent average',
            ),
          ),
      ],
    );
  }

  String _number(BuildContext context, double value) {
    // With at most 28 integer answers, two decimals keep a nonzero difference
    // from today's integer visible. Retain at least one decimal for averages.
    final formatted = value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
    return AppLocalizations.of(context).language == 'es'
        ? formatted.replaceAll('.', ',')
        : formatted;
  }
}
