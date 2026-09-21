import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/demo_data.dart';
import 'package:app/src/screens/activity_log_screen.dart';
import 'package:app/src/screens/appearance_screen.dart';
import 'package:app/src/theme.dart';
import 'package:app/src/theme_controller.dart';
import 'package:app/src/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'navigation_test_support.dart';
import 'privacy_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('appearance changes retain Profile and its pushed route', (
    tester,
  ) async {
    final app = _readyController();
    final appearance = ThemeController(store: _MemoryThemeStore());
    addTearDown(app.dispose);
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      TonyoApp(controller: app, themeController: appearance),
    );
    await tester.pumpAndSettle();
    await _selectTab(tester, 'Profile');
    await tester.scrollUntilVisible(
      find.byKey(const Key('appearance-setting')),
      200,
      scrollable: activeVerticalScrollable(),
    );
    await tester.tap(find.byKey(const Key('appearance-setting')));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    await appearance.setMode(ThemeMode.dark);
    await appearance.setPreset('forest');
    await tester.pumpAndSettle();
    expect(find.byType(AppearanceScreen), findsOneWidget);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)),
      same(navigator),
    );
    expect(
      Theme.of(tester.element(find.byType(AppearanceScreen))).brightness,
      Brightness.dark,
    );
    navigator.pop();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      4,
    );
    expect(find.byKey(const Key('appearance-setting')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme changes retain an activity draft and the selected tab', (
    tester,
  ) async {
    final app = _readyController();
    final appearance = ThemeController(store: _MemoryThemeStore());
    addTearDown(app.dispose);
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      TonyoApp(controller: app, themeController: appearance),
    );
    await tester.pumpAndSettle();
    await _selectTab(tester, 'Add');
    await tester.tap(find.text('Activity log'));
    await tester.pumpAndSettle();
    final activityState = tester.state(find.byType(ActivityLogScreen));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '2.5');
    await tester.enterText(fields.at(1), '3');

    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      await appearance.setMode(mode);
      await appearance.setFont(
        mode == ThemeMode.dark ? TonyoFont.inter : TonyoFont.sourceSans3,
      );
      await appearance.setCustomColors(
        const TonyoColorPair(main: Colors.white, secondary: Colors.white),
      );
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ActivityLogScreen)), same(activityState));
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text,
        '2.5',
      );
      expect(tester.widget<TextFormField>(fields.at(1)).controller!.text, '3');
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .style
            .fontFamily,
        appearance.preferences.font.family,
      );
      expect(
        Theme.of(tester.element(find.byType(ActivityLogScreen))).brightness,
        mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
  });

  test(
    'persisted appearance survives account sign-out and local reset',
    () async {
      final app = _readyController();
      final appearance = ThemeController();
      addTearDown(app.dispose);
      addTearDown(appearance.dispose);
      const pair = TonyoColorPair(
        main: Color(0xff123456),
        secondary: Color(0xff987654),
      );
      await appearance.setMode(ThemeMode.dark);
      await appearance.setCustomColors(pair);
      await appearance.setFont(TonyoFont.lato);
      final expected = appearance.preferences;

      await app.signOut();
      expect(appearance.preferences, expected);
      final afterSignOut = ThemeController();
      addTearDown(afterSignOut.dispose);
      await afterSignOut.load();
      expect(afterSignOut.preferences, expected);

      await app.reset();
      expect(appearance.preferences, expected);
      final afterReset = ThemeController();
      addTearDown(afterReset.dispose);
      await afterReset.load();
      expect(afterReset.preferences, expected);
    },
  );
}

AppController _readyController() =>
    AppController(initialPrivacyConsent: testAdultPrivacyConsent)
      ..isReady = true
      ..onboardingComplete = true
      ..signals = buildDemoSignals(DateTime.now())
      ..checkIns = buildDemoCheckIns(DateTime.now());

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

class _MemoryThemeStore implements ThemePreferencesStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}
