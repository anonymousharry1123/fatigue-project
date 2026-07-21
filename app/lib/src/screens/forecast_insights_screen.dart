import 'package:flutter/material.dart';

import '../theme.dart';
import 'forecast_screen.dart';
import 'insights_screen.dart';

class ForecastInsightsScreen extends StatefulWidget {
  const ForecastInsightsScreen({super.key});

  @override
  State<ForecastInsightsScreen> createState() => _ForecastInsightsScreenState();
}

class _ForecastInsightsScreenState extends State<ForecastInsightsScreen> {
  int _section = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.show_chart_rounded),
                  label: Text('Forecast'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.insights_rounded),
                  label: Text('Insights'),
                ),
              ],
              selected: {_section},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _section = value.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: TonyoColors.surface,
                selectedBackgroundColor: TonyoColors.primary,
              ),
            ),
          ),
        ),
      ),
      Expanded(
        child: IndexedStack(
          index: _section,
          children: const [ForecastScreen(), InsightsScreen()],
        ),
      ),
    ],
  );
}
