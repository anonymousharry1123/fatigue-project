import 'package:flutter/material.dart';

import '../app.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final score = controller.score;
    final drivers = score.drivers.isEmpty ? const [] : score.drivers;
    return SafeArea(
      bottom: false,
      child: ListView(
        key: const PageStorageKey('insights-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        children: [
          Text('Insights', style: Theme.of(context).textTheme.headlineMedium),
          const Text(
            'What your personal model will learn',
            style: TextStyle(color: TonyoColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TonyoCard(
            color: const Color(0xFF151923),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    MetricIcon(
                      icon: Icons.memory_rounded,
                      color: TonyoColors.mint,
                    ),
                    SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Fatigue Model',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            'Fixture model · Version 0.5',
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
                Row(
                  children: [
                    _ModelStat(
                      '${(score.confidence * 100).round()}%',
                      'Data confidence',
                      TonyoColors.mint,
                    ),
                    _ModelStat(
                      '${controller.checkIns.length}',
                      'Check-ins',
                      Colors.white,
                    ),
                    _ModelStat(
                      '${controller.signals.map((item) => item.type).toSet().length}',
                      'Signals tracked',
                      Colors.white,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader('What drives your fatigue'),
          if (drivers.isEmpty)
            const TonyoCard(
              child: Text(
                'No fixture drivers are available. Reset the demo from Profile.',
                style: TextStyle(color: TonyoColors.muted),
              ),
            )
          else
            ...drivers.take(5).toList().asMap().entries.map((entry) {
              final colors = [
                TonyoColors.blue,
                TonyoColors.mint,
                TonyoColors.coral,
                TonyoColors.violet,
                TonyoColors.amber,
              ];
              final color = colors[entry.key];
              final importance = (34 - entry.key * 5).clamp(10, 40);
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        MetricIcon(
                          icon: _driverIcon(entry.value.label),
                          color: color,
                          size: 34,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.value.label,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          '$importance%',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        value: importance / 40,
                        minHeight: 7,
                        color: color,
                        backgroundColor: TonyoColors.surfaceRaised,
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SectionHeader('Patterns preview'),
          const _PatternCard(
            icon: Icons.trending_down_rounded,
            color: TonyoColors.coral,
            title: 'Late screens → higher fatigue',
            detail:
                'A sample pattern showing how learned insights will appear.',
          ),
          const SizedBox(height: 10),
          const _PatternCard(
            icon: Icons.trending_up_rounded,
            color: TonyoColors.mint,
            title: 'Consistent bedtime → steadier focus',
            detail:
                'Associations will only appear after enough real observations.',
          ),
          const SizedBox(height: 10),
          const _PatternCard(
            icon: Icons.fitness_center_rounded,
            color: TonyoColors.primary,
            title: 'Morning movement + sleep → peak day',
            detail: 'Fixture example — not a claim about your current data.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Trend analysis is scheduled for Version 0.21. Version 0.5 persists the profile and fixture state needed to preview this screen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: TonyoColors.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  static IconData _driverIcon(String label) {
    if (label.contains('Sleep')) return Icons.bedtime_rounded;
    if (label.contains('Training')) return Icons.fitness_center_rounded;
    if (label.contains('Screen')) return Icons.smartphone_rounded;
    if (label.contains('Hydration')) return Icons.water_drop_rounded;
    return Icons.auto_awesome_rounded;
  }
}

class _ModelStat extends StatelessWidget {
  const _ModelStat(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: TonyoColors.muted, fontSize: 9),
        ),
      ],
    ),
  );
}

class _PatternCard extends StatelessWidget {
  const _PatternCard({
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
  Widget build(BuildContext context) => TonyoCard(
    child: Row(
      children: [
        MetricIcon(icon: icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
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
