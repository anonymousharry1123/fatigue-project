import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  int _range = 0;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final day = DateTime.now().add(Duration(days: _range == 1 ? 1 : 0));
    final points = controller.forecastFor(day);
    final windows = controller.windows;
    final peak = points.reduce((a, b) => a.energy > b.energy ? a : b);
    return SafeArea(
      bottom: false,
      child: ListView(
        key: const PageStorageKey('forecast-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Energy Forecast',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton.filledTonal(
                onPressed: () {},
                icon: const Icon(Icons.tune_rounded, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Today')),
              ButtonSegment(value: 1, label: Text('Tomorrow')),
              ButtonSegment(value: 2, label: Text('Week')),
            ],
            selected: {_range},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() => _range = value.first),
            style: SegmentedButton.styleFrom(
              backgroundColor: TonyoColors.surface,
              selectedBackgroundColor: TonyoColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          TonyoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Predicted energy curve',
                  style: TextStyle(color: TonyoColors.muted, fontSize: 11),
                ),
                const SizedBox(height: 3),
                Text(
                  _range == 2
                      ? '7-day outlook'
                      : 'Peak ${formatHour(peak.time)} · ${peak.energy.round()}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 14),
                if (_range == 2)
                  _WeekPreview(base: controller.score.energy)
                else
                  ForecastChart(points: points),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      color: TonyoColors.violet,
                      size: 16,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '${(controller.score.confidence * 100).round()}% fixture confidence',
                      style: const TextStyle(
                        color: TonyoColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader('Key windows'),
          ...windows.map(
            (window) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TonyoCard(
                child: Row(
                  children: [
                    MetricIcon(
                      icon: _icon(window.type),
                      color: _color(window.type),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${formatHour(window.start)} – ${formatHour(window.end)}',
                            style: const TextStyle(
                              color: TonyoColors.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _title(window.type),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            window.reason,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: TonyoColors.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${window.energy}',
                      style: TextStyle(
                        color: _color(window.type),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Forecasting becomes data-driven in Version 0.15. This preview demonstrates the planned interface using persisted fixture data.',
            textAlign: TextAlign.center,
            style: TextStyle(color: TonyoColors.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  static String _title(ForecastWindowType type) => switch (type) {
    ForecastWindowType.peak => 'Peak focus window',
    ForecastWindowType.crash => 'Predicted crash',
    ForecastWindowType.recovery => 'Recovery rebound',
  };
  static IconData _icon(ForecastWindowType type) => switch (type) {
    ForecastWindowType.peak => Icons.bolt_rounded,
    ForecastWindowType.crash => Icons.trending_down_rounded,
    ForecastWindowType.recovery => Icons.nights_stay_rounded,
  };
  static Color _color(ForecastWindowType type) => switch (type) {
    ForecastWindowType.peak => TonyoColors.mint,
    ForecastWindowType.crash => TonyoColors.coral,
    ForecastWindowType.recovery => TonyoColors.blue,
  };
}

class _WeekPreview extends StatelessWidget {
  const _WeekPreview({required this.base});
  final int base;
  @override
  Widget build(BuildContext context) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const shifts = [0, 5, -8, 3, -4, 9, 4];
    return SizedBox(
      height: 190,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (index) {
          final value = (base + shifts[index]).clamp(20, 95);
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 10,
                    color: TonyoColors.muted,
                  ),
                ),
                const SizedBox(height: 5),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: value * 1.35,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [TonyoColors.primary, TonyoColors.mint],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  labels[index],
                  style: const TextStyle(
                    color: TonyoColors.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
