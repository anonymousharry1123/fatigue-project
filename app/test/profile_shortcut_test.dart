import 'privacy_test_support.dart';
import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/demo_data.dart';
import 'package:app/src/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  AppController readyController() =>
      AppController(initialPrivacyConsent: testAdultPrivacyConsent)
        ..isReady = true
        ..onboardingComplete = true
        ..signals = buildDemoSignals(DateTime(2026, 7, 21, 9))
        ..checkIns = buildDemoCheckIns(DateTime(2026, 7, 21, 9));

  testWidgets(
    'Today profile shortcut is labelled and has a full touch target',
    (tester) async {
      final controller = readyController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(TonyoApp(controller: controller));

      final shortcut = find.byKey(const Key('today-profile-button'));
      expect(shortcut, findsOneWidget);
      expect(find.byTooltip('Open profile'), findsOneWidget);
      final button = tester.widget<IconButton>(shortcut);
      expect(button.onPressed, isNotNull);
      expect(tester.getSize(shortcut).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(shortcut).height, greaterThanOrEqualTo(48));
    },
  );

  testWidgets('Today avatar selects the existing Profile tab without a route', (
    tester,
  ) async {
    final controller = readyController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(TonyoApp(controller: controller));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    for (var attempt = 0; attempt < 2; attempt++) {
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await tester.tap(find.byKey(const Key('today-profile-button')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        4,
      );
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(ProfileScreen, skipOffstage: false), findsOneWidget);
      expect(find.text('Connected data sources'), findsOneWidget);
      expect(find.byKey(const Key('profile-sign-out-button')), findsOneWidget);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)),
        same(navigator),
      );
      expect(navigator.canPop(), isFalse);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Today'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('today-profile-button')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
