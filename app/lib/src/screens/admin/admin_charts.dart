import 'package:flutter/material.dart';

import '../../synthetic/cohort_stats.dart';
import '../../theme.dart';

class CohortHistogramChart extends StatelessWidget {
  const CohortHistogramChart({
    super.key,
    required this.bins,
    required this.color,
    this.height = 140,
  });

  final List<CohortHistogramBin> bins;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (bins.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'No distribution yet',
            style: TextStyle(color: TonyoColors.muted, fontSize: 12),
          ),
        ),
      );
    }
    final maxCount = bins
        .map((bin) => bin.count)
        .fold<int>(1, (a, b) => a > b ? a : b);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final bin in bins)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: bin.count / maxCount,
                          widthFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: .85),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bin.label.split('–').first,
                      style: const TextStyle(
                        color: TonyoColors.muted,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CohortScatterChart extends StatelessWidget {
  const CohortScatterChart({
    super.key,
    required this.points,
    required this.xLabel,
    required this.yLabel,
    this.badge,
    this.color = TonyoColors.mint,
    this.height = 200,
    this.fixedMinX,
    this.fixedMaxX,
    this.fixedMinY,
    this.fixedMaxY,
  });

  final List<CohortScatterPoint> points;
  final String xLabel;
  final String yLabel;
  final String? badge;
  final Color color;
  final double height;
  final double? fixedMinX;
  final double? fixedMaxX;
  final double? fixedMinY;
  final double? fixedMaxY;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$yLabel vs $xLabel',
                style: const TextStyle(
                  color: TonyoColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (badge != null)
              Text(
                badge!,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          width: double.infinity,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 18,
                child: Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      yLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TonyoColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: CustomPaint(
                        painter: _ScatterPainter(
                          points: points,
                          color: color,
                          fixedMinX: fixedMinX,
                          fixedMaxX: fixedMaxX,
                          fixedMinY: fixedMinY,
                          fixedMaxY: fixedMaxY,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      xLabel,
                      style: const TextStyle(
                        color: TonyoColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static ({double minX, double maxX, double minY, double maxY}) sharedDomain(
    List<CohortScatterPoint> a,
    List<CohortScatterPoint> b,
  ) {
    final all = [...a, ...b];
    if (all.isEmpty) {
      return (minX: 0, maxX: 1, minY: 0, maxY: 1);
    }
    var minX = all.first.x;
    var maxX = all.first.x;
    var minY = all.first.y;
    var maxY = all.first.y;
    for (final point in all) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }
    if (maxX <= minX) maxX = minX + 1;
    if (maxY <= minY) maxY = minY + 1;
    return (minX: minX, maxX: maxX, minY: minY, maxY: maxY);
  }
}

class _ScatterPainter extends CustomPainter {
  _ScatterPainter({
    required this.points,
    required this.color,
    this.fixedMinX,
    this.fixedMaxX,
    this.fixedMinY,
    this.fixedMaxY,
  });

  final List<CohortScatterPoint> points;
  final Color color;
  final double? fixedMinX;
  final double? fixedMaxX;
  final double? fixedMinY;
  final double? fixedMaxY;

  static const _tickStyle = TextStyle(
    color: TonyoColors.muted,
    fontSize: 9,
    fontWeight: FontWeight.w600,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTWH(36, 10, size.width - 44, size.height - 26);
    final grid = Paint()
      ..color = TonyoColors.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
    }

    if (points.isEmpty &&
        (fixedMinX == null ||
            fixedMaxX == null ||
            fixedMinY == null ||
            fixedMaxY == null)) {
      return;
    }

    late double minX;
    late double maxX;
    late double minY;
    late double maxY;
    if (fixedMinX != null &&
        fixedMaxX != null &&
        fixedMinY != null &&
        fixedMaxY != null) {
      minX = fixedMinX!;
      maxX = fixedMaxX!;
      minY = fixedMinY!;
      maxY = fixedMaxY!;
    } else if (points.isEmpty) {
      return;
    } else {
      minX = points.first.x;
      maxX = points.first.x;
      minY = points.first.y;
      maxY = points.first.y;
      for (final point in points) {
        if (point.x < minX) minX = point.x;
        if (point.x > maxX) maxX = point.x;
        if (point.y < minY) minY = point.y;
        if (point.y > maxY) maxY = point.y;
      }
      if (maxX <= minX) maxX = minX + 1;
      if (maxY <= minY) maxY = minY + 1;
    }

    for (var i = 0; i <= 3; i++) {
      final t = i / 3;
      final xValue = minX + (maxX - minX) * t;
      final yValue = maxY - (maxY - minY) * t;
      final x = chart.left + chart.width * t;
      final y = chart.top + chart.height * t;
      _drawTick(
        canvas,
        _formatTick(xValue),
        Offset(x, chart.bottom + 2),
        align: Alignment.topCenter,
      );
      _drawTick(
        canvas,
        _formatTick(yValue),
        Offset(chart.left - 4, y),
        align: Alignment.centerRight,
      );
    }

    final paint = Paint()..color = color.withValues(alpha: .55);
    for (final point in points) {
      final dx = chart.left + chart.width * (point.x - minX) / (maxX - minX);
      final dy = chart.bottom - chart.height * (point.y - minY) / (maxY - minY);
      canvas.drawCircle(Offset(dx, dy), 2.2, paint);
    }
  }

  static String _formatTick(double value) {
    if (value.abs() >= 100) return value.round().toString();
    if (value.abs() >= 10) return value.toStringAsFixed(1);
    return value.toStringAsFixed(1);
  }

  static void _drawTick(
    Canvas canvas,
    String text,
    Offset anchor, {
    required Alignment align,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _tickStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final offset = switch (align) {
      Alignment.topCenter => Offset(
        anchor.dx - painter.width / 2,
        anchor.dy,
      ),
      Alignment.centerRight => Offset(
        anchor.dx - painter.width,
        anchor.dy - painter.height / 2,
      ),
      _ => anchor,
    };
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ScatterPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.fixedMinX != fixedMinX ||
      oldDelegate.fixedMaxX != fixedMaxX ||
      oldDelegate.fixedMinY != fixedMinY ||
      oldDelegate.fixedMaxY != fixedMaxY;
}

class CohortGroupBars extends StatelessWidget {
  const CohortGroupBars({
    super.key,
    required this.groups,
    required this.valueOf,
    required this.color,
  });

  final List<CohortGroupStat> groups;
  final double Function(CohortGroupStat) valueOf;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const Text(
        'No groups',
        style: TextStyle(color: TonyoColors.muted, fontSize: 12),
      );
    }
    final maxValue = groups
        .map(valueOf)
        .fold<double>(1, (a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final group in groups.take(6)) ...[
          Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  group.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (valueOf(group) / maxValue).clamp(0, 1),
                    minHeight: 10,
                    backgroundColor: TonyoColors.border,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${valueOf(group).round()} · n=${group.count}',
                style: const TextStyle(
                  color: TonyoColors.muted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
