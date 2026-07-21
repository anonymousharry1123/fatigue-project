import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

class TonyoCard extends StatelessWidget {
  const TonyoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? TonyoColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: TonyoColors.border),
    ),
    child: child,
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
      ],
    ),
  );
}

class MetricIcon extends StatelessWidget {
  const MetricIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 42,
  });
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(size * .32),
    ),
    child: Icon(icon, color: color, size: size * .52),
  );
}

class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.value,
    required this.label,
    this.size = 116,
  });
  final int value;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: Size.square(size),
          painter: _RingPainter(value / 100),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: size * .28,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: size * .075,
                color: TonyoColors.muted,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * .07;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    paint.color = TonyoColors.border;
    canvas.drawArc(
      rect.deflate(stroke),
      -math.pi / 2,
      math.pi * 2,
      false,
      paint,
    );
    paint.shader = const SweepGradient(
      colors: [TonyoColors.blue, TonyoColors.mint, TonyoColors.primary],
      stops: [0, .55, 1],
      transform: GradientRotation(-math.pi / 2),
    ).createShader(rect);
    canvas.drawArc(
      rect.deflate(stroke),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class ForecastChart extends StatelessWidget {
  const ForecastChart({
    super.key,
    required this.points,
    this.height = 190,
    this.compact = false,
  });
  final List<ForecastPoint> points;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: ForecastPainter(points, compact: compact)),
  );
}

class ForecastPainter extends CustomPainter {
  ForecastPainter(this.points, {this.compact = false});
  final List<ForecastPoint> points;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final chart = Rect.fromLTWH(
      0,
      8,
      size.width,
      size.height - (compact ? 12 : 30),
    );
    final gridPaint = Paint()
      ..color = TonyoColors.border
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }
    Offset offset(int index) => Offset(
      chart.left + chart.width * index / (points.length - 1),
      chart.bottom - chart.height * points[index].energy / 110,
    );
    final path = Path()..moveTo(offset(0).dx, offset(0).dy);
    for (var i = 1; i < points.length; i++) {
      final previous = offset(i - 1);
      final current = offset(i);
      path.cubicTo(
        (previous.dx + current.dx) / 2,
        previous.dy,
        (previous.dx + current.dx) / 2,
        current.dy,
        current.dx,
        current.dy,
      );
    }
    final area = Path.from(path)
      ..lineTo(chart.right, chart.bottom)
      ..lineTo(chart.left, chart.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x665FE0C4), Color(0x005FE0C4)],
        ).createShader(chart),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [
            TonyoColors.blue,
            TonyoColors.mint,
            TonyoColors.amber,
            TonyoColors.coral,
          ],
        ).createShader(chart),
    );
    if (!compact) {
      final textPainter = TextPainter(textDirection: TextDirection.ltr);
      for (var i = 0; i < points.length; i += 4) {
        final hour = points[i].time.hour;
        textPainter.text = TextSpan(
          text: '${hour > 12 ? hour - 12 : hour}${hour >= 12 ? 'P' : 'A'}',
          style: const TextStyle(color: TonyoColors.muted, fontSize: 9),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(offset(i).dx - textPainter.width / 2, size.height - 14),
        );
      }
    }
  }

  @override
  bool shouldRepaint(ForecastPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.compact != compact;
}

IconData iconForSignal(SignalType type) => switch (type) {
  SignalType.sleep => Icons.bedtime_rounded,
  SignalType.bedtime => Icons.schedule_rounded,
  SignalType.hydration => Icons.water_drop_rounded,
  SignalType.study => Icons.menu_book_rounded,
  SignalType.exercise => Icons.fitness_center_rounded,
  SignalType.screenTime => Icons.smartphone_rounded,
  SignalType.reactionTime => Icons.bolt_rounded,
  SignalType.hrv => Icons.monitor_heart_rounded,
  SignalType.restingHeartRate => Icons.favorite_rounded,
  SignalType.sleepCore ||
  SignalType.sleepDeep ||
  SignalType.sleepRem => Icons.nights_stay_rounded,
};

Color colorForSignal(SignalType type) => switch (type) {
  SignalType.sleep || SignalType.bedtime => TonyoColors.blue,
  SignalType.hydration || SignalType.hrv => TonyoColors.mint,
  SignalType.study => TonyoColors.amber,
  SignalType.exercise || SignalType.restingHeartRate => TonyoColors.coral,
  SignalType.screenTime || SignalType.reactionTime => TonyoColors.violet,
  SignalType.sleepCore ||
  SignalType.sleepDeep ||
  SignalType.sleepRem => TonyoColors.primary,
};

String formatHour(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '$hour:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
}

String formatDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}';
}
