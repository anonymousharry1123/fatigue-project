import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'common_widgets.dart';

class PersonalBaselineCard extends StatelessWidget {
  const PersonalBaselineCard({
    super.key,
    required this.baselines,
    this.compact = false,
  });

  final PersonalBaselines baselines;
  final bool compact;

  @override
  Widget build(BuildContext context) => TonyoCard(
    key: const Key('personal-baseline-card'),
    color: const Color(0xFF151923),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const MetricIcon(
              icon: Icons.person_search_rounded,
              color: TonyoColors.violet,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your personal baselines',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${baselines.readyCount}/4 ready · ${baselines.windowDays}-day private history',
                    style: const TextStyle(
                      color: TonyoColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${(baselines.overallReadiness * 100).round()}%',
              style: const TextStyle(
                color: TonyoColors.violet,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (var index = 0; index < baselines.metrics.length; index++) ...[
          _BaselineRow(metric: baselines.metrics[index]),
          if (index < baselines.metrics.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: TonyoColors.border, height: 1),
            ),
        ],
        if (!compact) ...[
          const SizedBox(height: 13),
          const Text(
            'Tonyo compares these signals only with your own history. Confidence stays reduced while a baseline is still building.',
            style: TextStyle(
              color: TonyoColors.muted,
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ],
      ],
    ),
  );
}

class _BaselineRow extends StatelessWidget {
  const _BaselineRow({required this.metric});

  final PersonalBaselineMetric metric;

  @override
  Widget build(BuildContext context) {
    final value = metric.value;
    final displayValue = value == null
        ? '—'
        : metric.type == PersonalBaselineType.sleep
        ? value.toStringAsFixed(1)
        : value.round().toString();
    return Row(
      children: [
        Expanded(
          child: Text(
            metric.type.label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          '$displayValue ${metric.type.unit}',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (metric.isReady ? TonyoColors.mint : TonyoColors.amber)
                .withValues(alpha: .12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            metric.isReady
                ? '${metric.sampleCount} days'
                : '${metric.sampleCount}/${metric.minimumSamples}',
            style: TextStyle(
              color: metric.isReady ? TonyoColors.mint : TonyoColors.amber,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}
