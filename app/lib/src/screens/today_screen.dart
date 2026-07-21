import 'package:flutter/material.dart';

import '../app.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import 'coach_screen.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final score = controller.score;
    final firstAlert = controller.alerts.firstOrNull;
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        key: const PageStorageKey('today-scroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _dateLabel(),
                            style: const TextStyle(
                              color: TonyoColors.muted,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'Morning, ${controller.profile.name}',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ],
                      ),
                    ),
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: TonyoColors.primary.withValues(
                        alpha: .25,
                      ),
                      child: Text(
                        controller.profile.name.characters.first.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TonyoCard(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      ScoreRing(value: score.energy, label: 'Energy'),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AI ENERGY FORECAST',
                              style: TextStyle(
                                color: TonyoColors.violet,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .7,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _status(score.energy),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _statusDetail(score.energy),
                              style: const TextStyle(
                                color: TonyoColors.muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: TonyoColors.mint.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${(score.confidence * 100).round()}% data confidence',
                                style: const TextStyle(
                                  color: TonyoColors.mint,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (firstAlert != null) ...[
                  const SizedBox(height: 12),
                  TonyoCard(
                    color: const Color(0xFF26191C),
                    child: Row(
                      children: [
                        const MetricIcon(
                          icon: Icons.battery_alert_rounded,
                          color: TonyoColors.coral,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'PREDICTED DIP',
                                style: TextStyle(
                                  color: TonyoColors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                firstAlert.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                firstAlert.detail,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: TonyoColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SectionHeader('Today’s drivers'),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = (constraints.maxWidth - 10) / 2;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: score.drivers
                          .take(4)
                          .map(
                            (driver) => SizedBox(
                              width: width,
                              child: TonyoCard(
                                padding: const EdgeInsets.all(13),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        MetricIcon(
                                          icon: _driverIcon(driver.label),
                                          color: driver.contribution >= 0
                                              ? TonyoColors.mint
                                              : TonyoColors.coral,
                                          size: 32,
                                        ),
                                        const Spacer(),
                                        Text(
                                          '${driver.contribution >= 0 ? '+' : ''}${driver.contribution.round()}',
                                          style: TextStyle(
                                            color: driver.contribution >= 0
                                                ? TonyoColors.mint
                                                : TonyoColors.coral,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 11),
                                    Text(
                                      driver.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      driver.detail,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: TonyoColors.muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 6),
                SectionHeader(
                  'Top recommendation',
                  action: 'Coach',
                  onTap: () => _openCoach(context),
                ),
                _RecommendationPreview(onTap: () => _openCoach(context)),
                const SectionHeader('Cognitive readiness'),
                TonyoCard(
                  child: Row(
                    children: [
                      ScoreRing(
                        value: score.cognitive,
                        label: 'Focus',
                        size: 82,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              score.cognitive >= 70
                                  ? 'Ready for deep work'
                                  : 'Keep tasks lighter',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'This preview uses your reaction, sleep, stress, and study fixtures.',
                              style: TextStyle(
                                color: TonyoColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openCoach(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const CoachScreen()));

  static String _status(int value) => value >= 72
      ? 'You’re Fresh'
      : value >= 52
      ? 'Steady energy'
      : 'Recovery first';
  static String _statusDetail(int value) => value >= 72
      ? 'Energy should hold into early afternoon.'
      : value >= 52
      ? 'Protect the afternoon dip with a lighter block.'
      : 'Your fixture signals favor a lower-load day.';

  static IconData _driverIcon(String label) {
    if (label.contains('Sleep')) return Icons.bedtime_rounded;
    if (label.contains('Training')) return Icons.fitness_center_rounded;
    if (label.contains('Screen')) return Icons.smartphone_rounded;
    if (label.contains('Hydration')) return Icons.water_drop_rounded;
    return Icons.auto_awesome_rounded;
  }

  static String _dateLabel() {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }
}

class _RecommendationPreview extends StatelessWidget {
  const _RecommendationPreview({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final item = AppScope.of(context).recommendations.first;
    return TonyoCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            const MetricIcon(
              icon: Icons.bed_rounded,
              color: TonyoColors.primary,
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
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    item.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TonyoColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: TonyoColors.muted),
          ],
        ),
      ),
    );
  }
}
