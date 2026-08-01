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
                            'Daily Score Models',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            'Energy v0.11 · Cognitive v0.12',
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
                    _ModelStat('${score.energy}', 'Energy', TonyoColors.mint),
                    _ModelStat(
                      '${score.cognitive}',
                      'Cognitive',
                      TonyoColors.blue,
                    ),
                    _ModelStat(
                      '${(score.cognitiveConfidence * 100).round()}%',
                      'Cognitive confidence',
                      Colors.white,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader('Energy Score factors'),
          if (drivers.isEmpty)
            const TonyoCard(
              child: Text(
                'Log sleep, activity, and a check-in to explain your estimate.',
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
                          '${entry.value.contribution >= 0 ? '+' : ''}${entry.value.contribution.round()} pts',
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
                        value: entry.value.contribution.abs().clamp(0, 20) / 20,
                        minHeight: 7,
                        color: color,
                        backgroundColor: TonyoColors.surfaceRaised,
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SectionHeader('Cognitive Score factors'),
          TonyoCard(
            key: const Key('insights-cognitive-model'),
            color: const Color(0xFF111722),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const MetricIcon(
                      icon: Icons.psychology_rounded,
                      color: TonyoColors.blue,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        '${score.cognitiveInputCount}/5 inputs · ${(score.cognitiveConfidence * 100).round()}% confidence',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 13),
                  child: Divider(color: TonyoColors.border, height: 1),
                ),
                if (score.cognitiveDrivers.isEmpty)
                  const Text(
                    'Complete a reaction test, sleep or activity log, and check-in to explain cognitive readiness.',
                    style: TextStyle(color: TonyoColors.muted, fontSize: 11),
                  )
                else
                  ...score.cognitiveDrivers.map((driver) {
                    final positive = driver.contribution >= 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Icon(
                            positive
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            color: positive
                                ? TonyoColors.mint
                                : TonyoColors.coral,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driver.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  driver.detail,
                                  style: const TextStyle(
                                    color: TonyoColors.muted,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${positive ? '+' : ''}${driver.contribution.round()} pts',
                            style: TextStyle(
                              color: positive
                                  ? TonyoColors.mint
                                  : TonyoColors.coral,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
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
            'Daily score factors are live. Longer-term trend analysis is scheduled for Version 0.21.',
            textAlign: TextAlign.center,
            style: TextStyle(color: TonyoColors.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  static IconData _driverIcon(String label) {
    if (label.contains('Sleep')) return Icons.bedtime_rounded;
    if (label.contains('Exercise')) return Icons.fitness_center_rounded;
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
