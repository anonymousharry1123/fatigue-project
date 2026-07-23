import 'package:flutter/material.dart';

import '../app.dart';
import '../check_in_logic.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import 'reaction_test_screen.dart';

class DailyCheckInScreen extends StatefulWidget {
  const DailyCheckInScreen({super.key});

  @override
  State<DailyCheckInScreen> createState() => _DailyCheckInScreenState();
}

class _DailyCheckInScreenState extends State<DailyCheckInScreen> {
  late CheckInPeriod period = CheckInLogic.suggestedPeriod();
  double energy = 6;
  double mood = 6;
  double stress = 4;
  final noteController = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final history = controller.recentCheckIns();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Check-in'),
        backgroundColor: Colors.transparent,
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
                    'How are you feeling?',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Rate energy, mood, and stress on a 1–10 scale. Morning and evening check-ins help Tonyo learn your day.',
                    style: TextStyle(color: TonyoColors.muted),
                  ),
                  const SizedBox(height: 18),
                  SegmentedButton<CheckInPeriod>(
                    segments: const [
                      ButtonSegment(
                        value: CheckInPeriod.morning,
                        label: Text('Morning'),
                        icon: Icon(Icons.wb_sunny_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: CheckInPeriod.evening,
                        label: Text('Evening'),
                        icon: Icon(Icons.nights_stay_outlined, size: 16),
                      ),
                    ],
                    selected: {period},
                    onSelectionChanged: (value) =>
                        setState(() => period = value.first),
                  ),
                  const SizedBox(height: 18),
                  _RatingCard(
                    icon: Icons.bolt_rounded,
                    color: TonyoColors.mint,
                    title: 'Energy',
                    value: energy,
                    badge: CheckInLogic.energyBadge(energy),
                    low: '1 · Drained',
                    middle: '5 · OK',
                    high: '10 · Charged',
                    onChanged: (value) => setState(() => energy = value),
                  ),
                  const SizedBox(height: 12),
                  _RatingCard(
                    icon: Icons.sentiment_satisfied_alt_rounded,
                    color: TonyoColors.blue,
                    title: 'Mood',
                    value: mood,
                    badge: CheckInLogic.moodBadge(mood),
                    low: '1 · Low',
                    middle: '5 · Steady',
                    high: '10 · Great',
                    onChanged: (value) => setState(() => mood = value),
                  ),
                  const SizedBox(height: 12),
                  _RatingCard(
                    icon: Icons.psychology_alt_rounded,
                    color: TonyoColors.amber,
                    title: 'Stress',
                    value: stress,
                    badge: CheckInLogic.stressBadge(stress),
                    low: '1 · Calm',
                    middle: '5 · Moderate',
                    high: '10 · Maxed',
                    onChanged: (value) => setState(() => stress = value),
                  ),
                  const SizedBox(height: 12),
                  TonyoCard(
                    child: TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Optional note',
                        hintStyle: TextStyle(color: TonyoColors.muted),
                      ),
                    ),
                  ),
                  const SectionHeader('Cognitive tests · 30 sec'),
                  _TestCard(
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
                  const SectionHeader('Check-in history'),
                  if (history.isEmpty)
                    const TonyoCard(
                      child: Text(
                        'No check-ins saved yet. Your ratings will appear here.',
                        style: TextStyle(color: TonyoColors.muted),
                      ),
                    )
                  else
                    ...history.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _HistoryCard(checkIn: item),
                      ),
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
                  child: Text(saving ? 'Saving…' : 'Save check-in'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => saving = true);
    await AppScope.of(context).addCheckIn(
      energy: energy,
      mood: mood,
      stress: stress,
      period: period,
      note: noteController.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${period.label} check-in saved on a 1–10 scale.'),
        ),
      );
      Navigator.of(context).pop();
    }
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
          min: CheckInLogic.minRating,
          max: CheckInLogic.maxRating,
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

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.checkIn});
  final DailyCheckIn checkIn;

  @override
  Widget build(BuildContext context) {
    final stamp = checkIn.timestamp;
    final timeLabel =
        '${stamp.month}/${stamp.day} · ${_clock(stamp)} · ${checkIn.period.label}';
    return TonyoCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            timeLabel,
            style: const TextStyle(
              color: TonyoColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Chip('Energy ${checkIn.energy.round()}', TonyoColors.mint),
              const SizedBox(width: 6),
              _Chip('Mood ${checkIn.mood.round()}', TonyoColors.blue),
              const SizedBox(width: 6),
              _Chip('Stress ${checkIn.stress.round()}', TonyoColors.amber),
            ],
          ),
          if (checkIn.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              checkIn.note,
              style: const TextStyle(color: TonyoColors.muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  static String _clock(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$hour:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
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
        child: Row(
          children: [
            MetricIcon(icon: icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: TonyoColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
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
