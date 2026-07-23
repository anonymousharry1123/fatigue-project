import 'package:flutter/material.dart';

import '../theme.dart';
import 'add_data_screen.dart';
import 'coach_screen.dart';
import 'forecast_insights_screen.dart';
import 'profile_screen.dart';
import 'today_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  static const screens = [
    TodayScreen(),
    ForecastInsightsScreen(),
    AddDataScreen(),
    CoachScreen(embedded: true),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: screens),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.today_outlined),
          selectedIcon: Icon(Icons.today_rounded),
          label: 'Today',
        ),
        const NavigationDestination(
          icon: Icon(Icons.show_chart_rounded),
          label: 'Forecast',
        ),
        NavigationDestination(
          icon: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [TonyoColors.primary, TonyoColors.blue],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: Color(0x667567FF), blurRadius: 18),
              ],
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white),
          ),
          label: 'Add',
        ),
        const NavigationDestination(
          icon: Icon(Icons.auto_awesome_outlined),
          selectedIcon: Icon(Icons.auto_awesome_rounded),
          label: 'Coach',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'Profile',
        ),
      ],
    ),
  );
}
