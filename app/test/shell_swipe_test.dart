import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/demo_data.dart';
import 'package:app/src/notification_service.dart';
import 'package:app/src/screens/forecast_insights_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'swipes visit every main tab in both directions and stop at edges',
    (tester) async {
      await _showApp(tester);
      _expectTab(tester, 0);
      await _swipe(tester, forward: false);
      _expectTab(tester, 0);

      for (var index = 1; index <= 4; index++) {
        await _swipe(tester);
        _expectTab(tester, index);
      }
      await _swipe(tester);
      _expectTab(tester, 4);

      for (var index = 3; index >= 0; index--) {
        await _swipe(tester, forward: false);
        _expectTab(tester, index);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bottom navigation and swipes stay synchronized after distant taps',
    (tester) async {
      await _showApp(tester);
      await _selectTab(tester, 'Coach');
      _expectTab(tester, 3);
      await _swipe(tester, forward: false);
      _expectTab(tester, 2);

      await _selectTab(tester, 'Today');
      _expectTab(tester, 0);
      await _swipe(tester);
      _expectTab(tester, 1);
      await _selectTab(tester, 'Profile');
      _expectTab(tester, 4);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Today profile shortcut moves the page and supports swiping back',
    (tester) async {
      await _showApp(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await tester.tap(find.byKey(const Key('today-profile-button')));
      await tester.pumpAndSettle();
      _expectTab(tester, 4);
      expect(navigator.canPop(), isFalse);
      await _swipe(tester, forward: false);
      _expectTab(tester, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Forecast keeps its selected Insights section and scroll position',
    (tester) async {
      await _showApp(tester);
      await _selectTab(tester, 'Forecast');
      final forecast = find.byType(ForecastInsightsScreen);
      final initialState = tester.state(forecast);
      await tester.tap(
        find.descendant(of: forecast, matching: find.text('Insights')).first,
      );
      await tester.pumpAndSettle();

      final insights = find.byKey(const PageStorageKey('insights-scroll'));
      await tester.drag(insights, const Offset(0, -340));
      await tester.pumpAndSettle();
      _expectTab(tester, 1);
      final position = _scrollPosition(tester, insights);
      final savedOffset = position.pixels;
      expect(savedOffset, greaterThan(100));

      await _selectTab(tester, 'Profile');
      for (var index = 3; index >= 1; index--) {
        await _swipe(tester, forward: false);
        _expectTab(tester, index);
      }
      expect(tester.state(forecast), same(initialState));
      final section = find
          .descendant(of: forecast, matching: find.byType(SegmentedButton<int>))
          .first;
      expect(tester.widget<SegmentedButton<int>>(section).selected, {1});
      expect(
        _scrollPosition(tester, insights).pixels,
        closeTo(savedOffset, .1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'vertical content scroll and horizontal charts keep their gestures',
    (tester) async {
      // At this width/text scale the seven-day chart is wider than its viewport.
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _showApp(tester, size: const Size(320, 932));
      final today = find.byKey(const PageStorageKey('today-scroll'));
      await tester.drag(today, const Offset(0, -320));
      await tester.pumpAndSettle();
      expect(_scrollPosition(tester, today).pixels, greaterThan(100));
      _expectTab(tester, 0);

      await _selectTab(tester, 'Forecast');
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      final chart = find.byKey(const Key('forecast-week-chart-scroll'));
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      final chartPosition = _scrollPosition(tester, chart);
      expect(chartPosition.maxScrollExtent, greaterThan(0));
      await tester.drag(chart, const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(chartPosition.pixels, greaterThan(0));
      _expectTab(tester, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Coach notification selects its page before subsequent swipes', (
    tester,
  ) async {
    final notifications = _TapNotifications();
    await _showApp(tester, notifications: notifications);
    await _swipe(tester);
    notifications.tap('tonyo-guidance:coach:test-plan');
    await tester.pumpAndSettle();
    _expectTab(tester, 3);
    await _swipe(tester);
    _expectTab(tester, 4);
    await _selectTab(tester, 'Today');
    _expectTab(tester, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _showApp(
  WidgetTester tester, {
  Size size = const Size(430, 932),
  _TapNotifications? notifications,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller =
      AppController(
          initialPrivacyConsent: testAdultPrivacyConsent,
          notificationService: notifications ?? _TapNotifications(),
        )
        ..isReady = true
        ..onboardingComplete = true
        ..signals = buildDemoSignals(DateTime.now())
        ..checkIns = buildDemoCheckIns(DateTime.now());
  addTearDown(controller.dispose);
  await tester.pumpWidget(TonyoApp(controller: controller));
  await tester.pumpAndSettle();
}

void _expectTab(WidgetTester tester, int index) {
  expect(
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
    index,
  );
  final pages = tester.widget<PageView>(
    find.byKey(const Key('main-tab-pages')),
  );
  expect(pages.controller!.page, closeTo(index.toDouble(), .001));
}

Future<void> _swipe(WidgetTester tester, {bool forward = true}) async {
  final bounds = tester.getRect(find.byKey(const Key('main-tab-pages')));
  // Begin in the page header, away from horizontally scrolling charts.
  final start = Offset(
    forward ? bounds.right - 30 : bounds.left + 30,
    bounds.top + 85,
  );
  await tester.timedDragFrom(
    start,
    Offset(bounds.width * (forward ? -.8 : .8), 0),
    const Duration(milliseconds: 300),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _scrollPosition(WidgetTester tester, Finder scrollView) => tester
    .state<ScrollableState>(
      find.descendant(of: scrollView, matching: find.byType(Scrollable)).first,
    )
    .position;

class _TapNotifications
    implements NotificationService, NotificationResponseSource {
  void Function(String)? _onTap;

  void tap(String payload) => _onTap?.call(payload);

  @override
  Future<void> initializeResponses(void Function(String payload) onTap) async {
    _onTap = onTap;
  }

  @override
  bool get supportsScheduling => false;
  @override
  Future<void> cancelGuidance() async {}
  @override
  Future<NotificationPermissionState> permissionStatus() async =>
      NotificationPermissionState.unavailable;
  @override
  Future<NotificationPermissionState> requestPermission() async =>
      NotificationPermissionState.unavailable;
  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {}
}
