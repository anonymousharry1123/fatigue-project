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
    this.color = TonyoColors.mint,
    this.height = 180,
  });

  final List<CohortScatterPoint> points;
  final String xLabel;
  final String yLabel;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$yLabel vs $xLabel',
          style: const TextStyle(
            color: TonyoColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _ScatterPainter(points: points, color: color),
          ),
        ),
      ],
    );
  }
}

class _ScatterPainter extends CustomPainter {
  _ScatterPainter({required this.points, required this.color});

  final List<CohortScatterPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTWH(28, 8, size.width - 36, size.height - 28);
    final grid = Paint()
      ..color = TonyoColors.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
    }

    if (points.isEmpty) return;

    var minX = points.first.x;
    var maxX = points.first.x;
    var minY = points.first.y;
    var maxY = points.first.y;
    for (final point in points) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }
    if (maxX <= minX) maxX = minX + 1;
    if (maxY <= minY) maxY = minY + 1;

    final paint = Paint()..color = color.withValues(alpha: .55);
    for (final point in points) {
      final dx = chart.left + chart.width * (point.x - minX) / (maxX - minX);
      final dy = chart.bottom - chart.height * (point.y - minY) / (maxY - minY);
      canvas.drawCircle(Offset(dx, dy), 2.2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScatterPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
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
