import 'package:flutter/material.dart';

import '../app.dart';
import '../heart_metrics_logic.dart';
import '../l10n/app_localizations.dart';
import '../local_day.dart';
import '../models.dart';
import '../oura_data.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/translated_text.dart';

class HeartMetricsScreen extends StatelessWidget {
  const HeartMetricsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final now = DateTime.now();
    final days = HeartMetricsLogic.build(
      readings: controller.signals,
      now: now,
    );
    return Scaffold(
      appBar: AppBar(title: const TranslatedText('Heart metrics')),
      body: SafeArea(
        top: false,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          itemCount: days.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TranslatedText(
                      'Your heart data',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    const TranslatedText(
                      'Daily averages from your recorded readings. Dates use your local time.',
                    ),
                    if (days.any(
                      (day) =>
                          day.ouraHrv != null ||
                          day.ouraRestingHeartRate != null,
                    )) ...[
                      const SizedBox(height: 6),
                      const TranslatedText(
                        'Oura nightly measurements stay separate from Apple Health. Oura uses its original sleep date.',
                      ),
                    ],
                    const SizedBox(height: 12),
                    TranslatedText(
                      'Missing a measurement? Open Profile → Apple Health, allow access, then tap Sync now.',
                      style: TextStyle(color: TonyoPalette.of(context).muted),
                    ),
                    if (days.isEmpty) ...[
                      const SizedBox(height: 20),
                      const _HeartDayCard(day: null),
                    ],
                  ],
                ),
              );
            }
            final day = days[index - 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _HeartDayCard(
                key: ValueKey('heart-metrics-${day.date.toIso8601String()}'),
                day: day,
                isToday: localDay(now) == day.date,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeartDayCard extends StatelessWidget {
  const _HeartDayCard({super.key, required this.day, this.isToday = false});

  final HeartMetricsDay? day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final resting = day?.restingHeartRate ?? day?.estimatedRestingHeartRate;
    final estimated = day?.restingHeartRate == null && resting != null;
    return TonyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TranslatedText(
            day == null
                ? 'No heart data yet'
                : isToday
                ? 'Today · ${formatDate(day!.date)}'
                : formatDate(day!.date),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          if (isToday) ...[
            const SizedBox(height: 4),
            const TranslatedText('Today so far'),
          ],
          const SizedBox(height: 16),
          _Metric(
            label: 'Average heart rate',
            metric: day?.heartRate,
            unit: 'bpm',
          ),
          const Divider(height: 24),
          _Metric(
            label: estimated
                ? 'Estimated resting heart rate'
                : 'Resting heart rate',
            metric: resting,
            unit: 'bpm',
          ),
          if (estimated) ...[
            const SizedBox(height: 6),
            TranslatedText(
              'Resting HR estimates are informational and do not affect your score or measured baselines.',
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 12,
              ),
            ),
          ],
          const Divider(height: 24),
          _Metric(
            label: 'Heart rate variability (HRV)',
            metric: day?.hrv,
            unit: 'ms',
          ),
          if (day?.ouraHrv != null || day?.ouraRestingHeartRate != null) ...[
            const Divider(height: 28),
            const TranslatedText(
              'Oura nightly measurements',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _Metric(
              label: 'Oura HRV (RMSSD)',
              metric: day?.ouraHrv,
              unit: 'ms',
            ),
            const SizedBox(height: 12),
            _Metric(
              label:
                  day?.ouraRestingHeartRate?.measurementMethods.contains(
                        OuraData.apiRestingMethod,
                      ) ??
                      false
                  ? 'Oura lowest sleeping heart rate (API)'
                  : 'Oura resting heart rate (nightly minimum)',
              metric: day?.ouraRestingHeartRate,
              unit: 'bpm',
            ),
            const SizedBox(height: 6),
            TranslatedText(
              'Oura nighttime RMSSD and Apple Health SDNN use different HRV calculations. Their values are not averaged together.',
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 12,
              ),
            ),
            if (day?.ouraRestingHeartRate?.measurementMethods.contains(
                  OuraData.apiRestingMethod,
                ) ??
                false) ...[
              const SizedBox(height: 6),
              TranslatedText(
                'Five-minute samples were unavailable. This API minimum may differ from the resting heart rate shown in Oura.',
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 12,
                ),
              ),
            ],
          ],
          if (day?.variation != null) ...[
            const Divider(height: 24),
            const TranslatedText('Sampled heart-rate variation'),
            Text(
              '${day!.variation!.rmsSuccessiveDifferenceBpm.toStringAsFixed(1)} bpm',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            TranslatedText(
              'Variation between sampled bpm readings; separate from HRV and not used in your score.',
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.metric,
    required this.unit,
  });
  final String label;
  final HeartMetricAverage? metric;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final value = metric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TranslatedText(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          value == null ? '—' : '${value.mean.toStringAsFixed(1)} $unit',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          value == null
              ? context.tr('No readings for this day')
              : [
                  if (value.containsDemo) context.tr('Demo'),
                  for (final source in value.sources)
                    context.tr(switch (source) {
                      SignalSource.healthKit => 'Apple Health',
                      SignalSource.manual => 'Manual',
                      SignalSource.oura => 'Oura',
                      _ => 'Estimated',
                    }),
                  if (value.measurementMethods.contains('sdnn')) 'SDNN',
                  context.tr(
                    '{count} readings',
                    args: {'count': value.sampleCount},
                  ),
                ].join(' · '),
          style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 12),
        ),
      ],
    );
  }
}
