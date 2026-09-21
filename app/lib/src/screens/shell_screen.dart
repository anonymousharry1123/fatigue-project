import 'package:flutter/material.dart';

import '../theme.dart';
import 'add_data_screen.dart';
import 'coach_screen.dart';
import 'forecast_insights_screen.dart';
import 'profile_screen.dart';
import 'today_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({
    super.key,
    this.coachOpenRequest,
    this.notificationNavigation,
  });

  /// A new request selects Coach once, leaving subsequent manual tab choices
  /// alone. The app supplies this only after authentication/privacy gates pass.
  final int? coachOpenRequest;
  final CoachNotificationNavigation? notificationNavigation;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _index = widget.coachOpenRequest == null ? 0 : 3;
    _pageController = PageController(initialPage: _index);
    if (widget.coachOpenRequest != null) _openCoachFromNotification();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.coachOpenRequest != null &&
        widget.coachOpenRequest != oldWidget.coachOpenRequest) {
      _openCoachFromNotification();
    }
  }

  void _openCoachFromNotification() {
    _index = 3;
    final request = widget.coachOpenRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.coachOpenRequest != request) return;
      if (_pageController.hasClients) _pageController.jumpToPage(3);
      // A notification may arrive while a detail page or a dialog is open.
      // Return to the existing shell instead of stacking another private page.
      widget.notificationNavigation?.revealShell(
        isCurrent: () => mounted && widget.coachOpenRequest == request,
      );
    });
  }

  late final screens = [
    TodayScreen(onOpenProfile: () => _selectTab(4)),
    const ForecastInsightsScreen(),
    const AddDataScreen(),
    const CoachScreen(embedded: true),
    const ProfileScreen(),
  ];

  void _selectTab(int index) {
    if (_index != index) setState(() => _index = index);
    // Direct navigation should reach its destination without sweeping through
    // unrelated tabs. Touch and trackpad swipes follow the drag between pages.
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageView(
      key: const Key('main-tab-pages'),
      controller: _pageController,
      onPageChanged: (index) {
        if (_index != index) setState(() => _index = index);
      },
      children: [
        for (final (index, screen) in screens.indexed)
          _PersistentTab(
            key: ValueKey('main-tab-$index'),
            child: TickerMode(
              enabled: index == _index,
              child: ExcludeFocus(excluding: index != _index, child: screen),
            ),
          ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: _selectTab,
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
              color: TonyoPalette.of(context).primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.add_rounded,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          label: 'Add',
        ),
        const NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline_rounded),
          selectedIcon: Icon(Icons.chat_bubble_rounded),
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

/// Keep each visited tab's filters, scroll position, and local state while the
/// pager removes its offscreen render objects from the viewport.
class _PersistentTab extends StatefulWidget {
  const _PersistentTab({super.key, required this.child});

  final Widget child;

  @override
  State<_PersistentTab> createState() => _PersistentTabState();
}

class _PersistentTabState extends State<_PersistentTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Tracks the root navigator so notification routing can respect PopScope and
/// legacy willPop checks instead of forcibly dismissing a save in progress.
class CoachNotificationNavigation extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index < 0) return;
    if (newRoute == null) {
      _routes.removeAt(index);
    } else {
      _routes[index] = newRoute;
    }
  }

  Future<void> revealShell({required bool Function() isCurrent}) async {
    final currentNavigator = navigator;
    if (currentNavigator == null) return;
    while (isCurrent() &&
        currentNavigator.mounted &&
        currentNavigator.canPop() &&
        _routes.isNotEmpty) {
      final previous = _routes.last;
      await currentNavigator.maybePop();
      // maybePop returns true even when PopScope handles a blocked dismissal.
      // Leave the active operation intact; Coach is ready beneath that route.
      if (_routes.isNotEmpty && identical(_routes.last, previous)) return;
    }
  }
}
