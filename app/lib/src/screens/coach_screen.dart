import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class CoachScreen extends StatelessWidget {
  const CoachScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final recommendations = controller.recommendations;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Coach'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          TonyoCard(
            color: const Color(0xFF171524),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    MetricIcon(
                      icon: Icons.auto_awesome_rounded,
                      color: TonyoColors.primary,
                    ),
                    SizedBox(width: 11),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tonyo Coach',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '● Reading today’s fixture signals',
                          style: TextStyle(
                            color: TonyoColors.mint,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'You logged ${_latest(controller, SignalType.sleep, '6.2')} hours of sleep and a ${_latest(controller, SignalType.exercise, '1.3')}-hour workout. This preview protects your afternoon dip with a small, practical plan.',
                  style: const TextStyle(height: 1.5),
                ),
              ],
            ),
          ),
          const SectionHeader('Today’s plan'),
          ...recommendations.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TonyoCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MetricIcon(
                      icon: _icon(item.category),
                      color: _color(item.category),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.timeLabel,
                            style: const TextStyle(
                              color: TonyoColors.violet,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            item.title,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.detail,
                            style: const TextStyle(
                              color: TonyoColors.muted,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Preview recommendation',
                            style: TextStyle(
                              color: TonyoColors.mint,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      item.status == RecommendationStatus.completed
                          ? Icons.check_circle_rounded
                          : Icons.check_box_outline_blank_rounded,
                      color: TonyoColors.mint,
                    ),
                  ],
                ),
              ),
            ),
          ),
          TonyoCard(
            color: TonyoColors.primary.withValues(alpha: .16),
            child: Row(
              children: [
                const Icon(
                  Icons.trending_up_rounded,
                  color: TonyoColors.mint,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'IF YOU FOLLOW THE PLAN',
                        style: TextStyle(
                          color: TonyoColors.muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${controller.score.energy} → ${(controller.score.energy + 14).clamp(0, 100)} estimated energy',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Coach actions become interactive in Version 0.18. This Version 0.5 screen is a fixture-backed preview.',
            textAlign: TextAlign.center,
            style: TextStyle(color: TonyoColors.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  static String _latest(dynamic controller, SignalType type, String fallback) {
    final values = controller.signals.where(
      (SignalReading item) => item.type == type,
    );
    return values.isEmpty ? fallback : values.first.value.toStringAsFixed(1);
  }

  static IconData _icon(String category) => switch (category) {
    'Study' => Icons.menu_book_rounded,
    'Training' => Icons.fitness_center_rounded,
    _ => Icons.bed_rounded,
  };
  static Color _color(String category) => switch (category) {
    'Study' => TonyoColors.amber,
    'Training' => TonyoColors.coral,
    _ => TonyoColors.mint,
  };
}
