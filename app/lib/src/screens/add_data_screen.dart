import 'package:flutter/material.dart';

import '../app.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import 'coach_screen.dart';
import 'daily_checkin_screen.dart';
import 'reaction_test_screen.dart';

class AddDataScreen extends StatelessWidget {
  const AddDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        children: [
          Text(
            'Add & Explore',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 5),
          const Text(
            'Preview the daily tools that will feed your personal model.',
            style: TextStyle(color: TonyoColors.muted),
          ),
          const SectionHeader('Daily inputs'),
          _LaunchCard(
            icon: Icons.tune_rounded,
            color: TonyoColors.amber,
            title: 'Daily check-in',
            detail: 'Fatigue and focus self-ratings',
            badge: '${controller.checkIns.length} saved',
            onTap: () => _push(context, const DailyCheckInScreen()),
          ),
          const SizedBox(height: 10),
          _LaunchCard(
            icon: Icons.bolt_rounded,
            color: TonyoColors.primary,
            title: 'Reaction test',
            detail: 'Three quick reaction rounds',
            badge: '30 sec',
            onTap: () => _push(context, const ReactionTestScreen()),
          ),
          const SectionHeader('Plan preview'),
          _LaunchCard(
            icon: Icons.auto_awesome_rounded,
            color: TonyoColors.mint,
            title: 'AI Coach',
            detail: 'A fixture-backed day plan using your saved profile',
            badge: 'Preview',
            onTap: () => _push(context, const CoachScreen()),
          ),
          const SizedBox(height: 18),
          TonyoCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MetricIcon(
                  icon: Icons.storage_rounded,
                  color: TonyoColors.blue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Version 0.5.1 local storage',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${controller.signals.length} fixture signals and ${controller.checkIns.length} check-ins are persisted on this device.',
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
      ),
    );
  }

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

class _LaunchCard extends StatelessWidget {
  const _LaunchCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.badge,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String badge;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TonyoCard(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            MetricIcon(icon: icon, color: color, size: 48),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: TonyoColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: TonyoColors.muted),
          ],
        ),
      ),
    ),
  );
}
