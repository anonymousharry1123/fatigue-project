import 'package:flutter/material.dart';

import '../app.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import 'reaction_test_screen.dart';

class DailyCheckInScreen extends StatefulWidget {
  const DailyCheckInScreen({super.key});

  @override
  State<DailyCheckInScreen> createState() => _DailyCheckInScreenState();
}

class _DailyCheckInScreenState extends State<DailyCheckInScreen> {
  double fatigue = 6;
  double focus = 7;
  bool saving = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Daily Check-in'),
      backgroundColor: Colors.transparent,
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 18),
          child: Center(
            child: Text(
              'Step 2 of 4',
              style: TextStyle(
                color: TonyoColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                Text(
                  'How drained do you feel?',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 7),
                const Text(
                  'Your honest rating teaches Tonyo what fatigue feels like for you.',
                  style: TextStyle(color: TonyoColors.muted),
                ),
                const SizedBox(height: 18),
                LinearProgressIndicator(
                  value: .5,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(8),
                  color: TonyoColors.amber,
                  backgroundColor: TonyoColors.border,
                ),
                const SizedBox(height: 18),
                _RatingCard(
                  icon: Icons.sentiment_dissatisfied_rounded,
                  color: TonyoColors.amber,
                  title: 'Self-rated fatigue',
                  value: fatigue,
                  badge: fatigue >= 8
                      ? 'High'
                      : fatigue >= 5
                      ? 'Moderate'
                      : 'Fresh',
                  low: '1 · Fresh',
                  middle: '5 · OK',
                  high: '10 · Wiped',
                  onChanged: (value) => setState(() => fatigue = value),
                ),
                const SizedBox(height: 12),
                _RatingCard(
                  icon: Icons.bolt_rounded,
                  color: TonyoColors.mint,
                  title: 'Focus level',
                  value: focus,
                  badge: focus >= 7
                      ? 'Sharp'
                      : focus >= 4
                      ? 'Steady'
                      : 'Foggy',
                  low: '1 · Foggy',
                  middle: '5 · OK',
                  high: '10 · Locked in',
                  onChanged: (value) => setState(() => focus = value),
                ),
                const SectionHeader('Cognitive tests · 30 sec'),
                Row(
                  children: [
                    Expanded(
                      child: _TestCard(
                        icon: Icons.timer_outlined,
                        color: TonyoColors.primary,
                        title: 'Reaction time',
                        detail: 'Tap when it flashes',
                        status: 'Try now',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ReactionTestScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: _TestCard(
                        icon: Icons.psychology_rounded,
                        color: TonyoColors.mint,
                        title: 'Memory test',
                        detail: 'Recall the sequence',
                        status: 'Preview',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: TonyoColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  saving ? 'Saving…' : 'Save check-in & update preview',
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    setState(() => saving = true);
    await AppScope.of(context).addCheckIn(
      energy: ((11 - fatigue) / 2).clamp(1, 5),
      mood: (focus / 2).clamp(1, 5),
      stress: (fatigue / 2).clamp(1, 5),
      note: 'Version 0.5 check-in preview',
    );
    if (mounted) Navigator.of(context).pop();
  }
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.badge,
    required this.low,
    required this.middle,
    required this.high,
    required this.onChanged,
  });
  final IconData icon;
  final Color color;
  final String title;
  final double value;
  final String badge;
  final String low;
  final String middle;
  final String high;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '${value.round()}',
                style: TextStyle(
                  color: color,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const TextSpan(
                text: ' / 10',
                style: TextStyle(
                  color: TonyoColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Slider(
          value: value,
          min: 1,
          max: 10,
          divisions: 9,
          activeColor: color,
          onChanged: onChanged,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(low, style: _caption),
            Text(middle, style: _caption),
            Text(high, style: _caption),
          ],
        ),
      ],
    ),
  );
  static const _caption = TextStyle(color: TonyoColors.muted, fontSize: 9);
}

class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.status,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String status;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => TonyoCard(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MetricIcon(icon: icon, color: color),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(
              detail,
              style: const TextStyle(color: TonyoColors.muted, fontSize: 10),
            ),
            const SizedBox(height: 10),
            Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
