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
      color: color ?? TonyoPalette.of(context).surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: TonyoPalette.of(context).border),
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
  Widget build(BuildContext context) {
    final titleWidget = Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
    final actionWidget = action == null
        ? null
        : TextButton(onPressed: onTap, child: Text(action!));
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
      child: large
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleWidget, ?actionWidget],
            )
          : Row(
              children: [
                Expanded(child: titleWidget),
                ?actionWidget,
              ],
            ),
    );
  }
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
    this.color,
  });
  final int value;
  final String label;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return Semantics(
      label: '$label score',
      value: '$value out of 100',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final extent = math.min(size * scale, constraints.maxWidth);
          return SizedBox.square(
            dimension: extent,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.square(extent),
                  painter: _RingPainter(
                    value / 100,
                    color: color ?? TonyoPalette.of(context).primary,
                    trackColor: TonyoPalette.of(context).border,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$value',
                          style: TextStyle(
                            fontSize: size * .28,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label.toUpperCase(),
                          style: TextStyle(
                            fontSize: size * .075,
                            color: TonyoPalette.of(context).muted,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(
    this.progress, {
    required this.color,
    required this.trackColor,
  });
  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * .07;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    paint.color = trackColor;
    canvas.drawArc(
      rect.deflate(stroke),
      -math.pi / 2,
      math.pi * 2,
      false,
      paint,
    );
    paint.color = color;
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
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
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
    child: CustomPaint(
      painter: ForecastPainter(
        points,
        colors: TonyoPalette.of(context),
        textStyle: Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
        compact: compact,
      ),
    ),
  );
}

class ForecastPainter extends CustomPainter {
  ForecastPainter(
    this.points, {
    required this.colors,
    this.textStyle = const TextStyle(),
    this.compact = false,
  });
  final List<ForecastPoint> points;
  final TonyoPalette colors;
  final TextStyle textStyle;
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
      ..color = colors.border
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }
    Offset offsetFor(int index, double energy) => Offset(
      chart.left + chart.width * index / (points.length - 1),
      chart.bottom - chart.height * energy.clamp(0, 100) / 110,
    );
    Offset offset(int index) => offsetFor(index, points[index].energy);
    final uncertaintyBand = Path();
    final upperBoundary = Path();
    final lowerBoundary = Path();
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final upper = offsetFor(index, point.energy + point.uncertainty);
      final lower = offsetFor(index, point.energy - point.uncertainty);
      if (index == 0) {
        uncertaintyBand.moveTo(upper.dx, upper.dy);
        upperBoundary.moveTo(upper.dx, upper.dy);
        lowerBoundary.moveTo(lower.dx, lower.dy);
      } else {
        uncertaintyBand.lineTo(upper.dx, upper.dy);
        upperBoundary.lineTo(upper.dx, upper.dy);
        lowerBoundary.lineTo(lower.dx, lower.dy);
      }
    }
    for (var index = points.length - 1; index >= 0; index--) {
      final point = points[index];
      final lower = offsetFor(index, point.energy - point.uncertainty);
      uncertaintyBand.lineTo(lower.dx, lower.dy);
    }
    uncertaintyBand.close();
    canvas.drawPath(
      uncertaintyBand,
      Paint()..color = colors.secondary.withValues(alpha: .12),
    );
    // Texture keeps uncertainty distinct even when both custom accents match.
    final boundaryPaint = Paint()
      ..color = colors.secondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final boundary in [upperBoundary, lowerBoundary]) {
      for (final metric in boundary.computeMetrics()) {
        for (var distance = 0.0; distance < metric.length; distance += 9) {
          canvas.drawPath(
            metric.extractPath(distance, math.min(distance + 5, metric.length)),
            boundaryPaint,
          );
        }
      }
    }
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
      Paint()..color = colors.primary.withValues(alpha: .06),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = colors.primary,
    );
    if (!compact) {
      final textPainter = TextPainter(textDirection: TextDirection.ltr);
      for (var i = 0; i < points.length; i += 4) {
        final hour = points[i].time.hour;
        textPainter.text = TextSpan(
          text: '${hour > 12 ? hour - 12 : hour}${hour >= 12 ? 'P' : 'A'}',
          style: textStyle.copyWith(color: colors.muted, fontSize: 9),
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
      oldDelegate.points != points ||
      oldDelegate.compact != compact ||
      oldDelegate.colors != colors ||
      oldDelegate.textStyle != textStyle;
}

IconData iconForSignal(SignalType type) => switch (type) {
  SignalType.sleep => Icons.bedtime_rounded,
  SignalType.nap => Icons.airline_seat_individual_suite_rounded,
  SignalType.bedtime => Icons.schedule_rounded,
  SignalType.hydration => Icons.water_drop_rounded,
  SignalType.study => Icons.menu_book_rounded,
  SignalType.exercise => Icons.fitness_center_rounded,
  SignalType.steps => Icons.directions_walk_rounded,
  SignalType.screenTime => Icons.smartphone_rounded,
  SignalType.caffeine => Icons.coffee_rounded,
  SignalType.reactionTime => Icons.bolt_rounded,
  SignalType.hrv => Icons.monitor_heart_rounded,
  SignalType.restingHeartRate => Icons.favorite_rounded,
  SignalType.sleepAwake => Icons.visibility_rounded,
  SignalType.sleepCore ||
  SignalType.sleepDeep ||
  SignalType.sleepRem ||
  SignalType.sleepUnspecified => Icons.nights_stay_rounded,
};

Color colorForSignal(SignalType type, TonyoPalette colors) => switch (type) {
  SignalType.sleep || SignalType.bedtime => colors.primary,
  SignalType.nap => colors.secondary,
  SignalType.hydration || SignalType.hrv => colors.secondary,
  SignalType.study => colors.primary,
  SignalType.exercise ||
  SignalType.steps ||
  SignalType.restingHeartRate => colors.secondary,
  SignalType.screenTime || SignalType.reactionTime => colors.secondary,
  SignalType.caffeine => colors.primary,
  SignalType.sleepAwake => colors.secondary,
  SignalType.sleepCore ||
  SignalType.sleepDeep ||
  SignalType.sleepRem ||
  SignalType.sleepUnspecified => colors.primary,
};

String formatHour(DateTime value) {
  value = value.toLocal();
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '$hour:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
}

String formatDate(DateTime value) {
  value = value.toLocal();
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
