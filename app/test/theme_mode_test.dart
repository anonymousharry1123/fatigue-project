import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/screens/shell_screen.dart';
import 'package:app/src/theme.dart';
import 'package:app/src/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'privacy_test_support.dart';

class _Store implements ThemePreferencesStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Follow device responds live; explicit Light and Dark stay fixed',
    (tester) async {
      final controller =
          AppController(initialPrivacyConsent: testAdultPrivacyConsent)
            ..isReady = true
            ..onboardingComplete = true;
      final appearance = ThemeController(store: _Store());
      addTearDown(controller.dispose);
      addTearDown(appearance.dispose);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpWidget(
        TonyoApp(controller: controller, themeController: appearance),
      );
      await tester.pumpAndSettle();
      Brightness current() =>
          Theme.of(tester.element(find.byType(ShellScreen))).brightness;
      expect(current(), Brightness.dark);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(current(), Brightness.light);
      await appearance.setMode(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(current(), Brightness.dark);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      await appearance.setMode(ThemeMode.light);
      await tester.pumpAndSettle();
      expect(current(), Brightness.light);
      await appearance.setMode(ThemeMode.system);
      await tester.pumpAndSettle();
      expect(current(), Brightness.dark);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved appearance is present on the first Flutter frame', (
    tester,
  ) async {
    final store = _Store()
      ..value = const ThemePreferences(
        mode: ThemeMode.dark,
        presetId: 'forest',
      ).encode();
    final appearance = ThemeController(store: store);
    await appearance.load();
    final controller = AppController(
      initialPrivacyConsent: testAdultPrivacyConsent,
    )..isReady = true;
    addTearDown(controller.dispose);
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      TonyoApp(controller: controller, themeController: appearance),
    );
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(
      TonyoPalette.of(context).primary,
      TonyoPalette.resolve(
        Brightness.dark,
        tonyoThemePresets.firstWhere((p) => p.id == 'forest').colors,
      ).primary,
    );
    await tester.pumpAndSettle();
  });
}
