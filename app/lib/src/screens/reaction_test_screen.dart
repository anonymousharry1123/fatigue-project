import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

enum _ReactionPhase { idle, waiting, ready, result, complete }

class ReactionTestScreen extends StatefulWidget {
  const ReactionTestScreen({super.key});

  @override
  State<ReactionTestScreen> createState() => _ReactionTestScreenState();
}

class _ReactionTestScreenState extends State<ReactionTestScreen> {
  _ReactionPhase phase = _ReactionPhase.idle;
  final results = <int>[];
  Timer? timer;
  DateTime? started;
  int earlyTaps = 0;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final latest = results.isEmpty ? 248 : results.last;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reaction Test'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton.filledTonal(
            onPressed: _help,
            icon: const Icon(Icons.question_mark_rounded, size: 16),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          GestureDetector(
            onTap: _tap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 276,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: phase == _ReactionPhase.ready
                      ? [const Color(0xFF1ABF8F), TonyoColors.mint]
                      : phase == _ReactionPhase.waiting
                      ? [const Color(0xFF352F4C), const Color(0xFF1B1A29)]
                      : [TonyoColors.primary, const Color(0xFF5140C9)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _instruction,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .8,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .45),
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child:
                          phase == _ReactionPhase.result ||
                              phase == _ReactionPhase.complete
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$latest',
                                  style: const TextStyle(
                                    fontSize: 43,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const Text(
                                  'ms',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            )
                          : Icon(_phaseIcon, size: 54, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _footer,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.timer_outlined,
                  color: TonyoColors.violet,
                  title: 'Reaction time',
                  value: '$latest ms',
                  detail: results.isEmpty
                      ? 'Complete a round'
                      : '${results.length} valid round${results.length == 1 ? '' : 's'}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.warning_amber_rounded,
                  color: TonyoColors.amber,
                  title: 'Early taps',
                  value: '$earlyTaps',
                  detail: earlyTaps == 0 ? 'Stay sharp' : 'Wait for green',
                ),
              ),
            ],
          ),
          const SectionHeader('Reaction time · last 7 days'),
          TonyoCard(
            child: Column(
              children: [
                SizedBox(
                  height: 115,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [286, 272, 334, 280, 275, 248, latest]
                        .asMap()
                        .entries
                        .map((entry) {
                          final height = (380 - entry.value)
                              .clamp(35, 120)
                              .toDouble();
                          return Expanded(
                            child: Container(
                              height: height,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: entry.key >= 5
                                      ? [TonyoColors.amber, TonyoColors.coral]
                                      : [TonyoColors.blue, TonyoColors.primary],
                                ),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                            ),
                          );
                        })
                        .toList(),
                  ),
                ),
                const SizedBox(height: 9),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text('W', style: _day),
                    Text('T', style: _day),
                    Text('F', style: _day),
                    Text('S', style: _day),
                    Text('S', style: _day),
                    Text('M', style: _day),
                    Text('T', style: _day),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'This Version 0.5 preview stores completed results locally. Trend interpretation arrives in Version 0.21.',
                  style: TextStyle(color: TonyoColors.muted, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _day = TextStyle(color: TonyoColors.muted, fontSize: 9);

  String get _instruction => switch (phase) {
    _ReactionPhase.idle => 'TAP TO BEGIN',
    _ReactionPhase.waiting => 'WAIT FOR GREEN',
    _ReactionPhase.ready => 'TAP NOW',
    _ReactionPhase.result => 'NICE — TAP FOR NEXT ROUND',
    _ReactionPhase.complete => 'TEST COMPLETE',
  };
  String get _footer => switch (phase) {
    _ReactionPhase.idle => 'Three quick rounds',
    _ReactionPhase.waiting => 'Hold steady…',
    _ReactionPhase.ready => 'Go!',
    _ReactionPhase.result =>
      '${3 - results.length} round${3 - results.length == 1 ? '' : 's'} left',
    _ReactionPhase.complete => 'Saved to this device',
  };
  IconData get _phaseIcon => switch (phase) {
    _ReactionPhase.idle => Icons.touch_app_rounded,
    _ReactionPhase.waiting => Icons.more_horiz_rounded,
    _ReactionPhase.ready => Icons.bolt_rounded,
    _ReactionPhase.result || _ReactionPhase.complete => Icons.check_rounded,
  };

  void _tap() {
    switch (phase) {
      case _ReactionPhase.idle:
      case _ReactionPhase.result:
        _startRound();
      case _ReactionPhase.waiting:
        timer?.cancel();
        setState(() {
          earlyTaps++;
          phase = _ReactionPhase.idle;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Too soon — wait until the panel turns green.'),
          ),
        );
      case _ReactionPhase.ready:
        final elapsed = DateTime.now().difference(started!).inMilliseconds;
        setState(() {
          results.add(elapsed);
          phase = results.length == 3
              ? _ReactionPhase.complete
              : _ReactionPhase.result;
        });
        if (results.length == 3) {
          final average = results.reduce((a, b) => a + b) / results.length;
          AppScope.of(context).addSignal(
            SignalType.reactionTime,
            average,
            note: 'Three-round reaction test',
          );
        }
      case _ReactionPhase.complete:
        Navigator.of(context).pop();
    }
  }

  void _startRound() {
    timer?.cancel();
    setState(() => phase = _ReactionPhase.waiting);
    timer = Timer(Duration(milliseconds: 900 + Random().nextInt(1500)), () {
      if (!mounted) return;
      setState(() {
        phase = _ReactionPhase.ready;
        started = DateTime.now();
      });
    });
  }

  void _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('How it works'),
      content: const Text(
        'Start a round, wait for the panel to turn green, then tap as quickly as you can. Early taps do not count.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.detail,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String detail;
  @override
  Widget build(BuildContext context) => TonyoCard(
    padding: const EdgeInsets.all(13),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: TonyoColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        Text(
          detail,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
