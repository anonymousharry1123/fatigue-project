import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/demo_data.dart';
import 'package:app/src/screens/activity_log_screen.dart';
import 'package:app/src/screens/appearance_screen.dart';
import 'package:app/src/screens/coach_screen.dart';
import 'package:app/src/screens/forecast_screen.dart';
import 'package:app/src/screens/onboarding_screen.dart';
import 'package:app/src/screens/profile_screen.dart';
import 'package:app/src/screens/shell_screen.dart';
import 'package:app/src/theme.dart';
import 'package:app/src/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

const _renderScreenshots = bool.fromEnvironment('THEME_SCREENSHOTS');
const _captureKey = Key('theme-review-capture');

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  if (!_renderScreenshots) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/theme-review')
      ..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    if (!_renderScreenshots) return;
    // Use the installed SDK font for review artifacts; no host-specific paths.
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    final flutter = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((package) => package['name'] == 'flutter');
    final sdk = Directory.fromUri(
      configFile.uri.resolve(flutter['rootUri'] as String),
    ).parent.parent;
    final fonts = FontLoader('Roboto');
    for (final name in [
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
    ]) {
      fonts.addFont(
        File(
          '${sdk.path}/bin/cache/artifacts/material_fonts/$name',
        ).readAsBytes().then((value) => ByteData.sublistView(value)),
      );
    }
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File(
          '${sdk.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then((value) => ByteData.sublistView(value)),
      );
    await icons.load();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'representative screens, dialog and custom editor render in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final now = DateTime(2026, 9, 20, 9);
        final controller =
            AppController(initialPrivacyConsent: testAdultPrivacyConsent)
              ..isReady = true
              ..onboardingComplete = true
              ..signals = buildDemoSignals(now)
              ..checkIns = buildDemoCheckIns(now);
        final appearance = ThemeController(
          initialPreferences: ThemePreferences(
            mode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
          ),
        );
        addTearDown(controller.dispose);
        addTearDown(appearance.dispose);
        await controller.refreshForecasts();
        await controller.refreshInsights();

        Future<void> show(Widget screen) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            ThemeScope(
              controller: appearance,
              child: AppScope(
                controller: controller,
                child: MaterialApp(
                  theme: buildTonyoTheme(brightness: brightness),
                  builder: (context, child) =>
                      RepaintBoundary(key: _captureKey, child: child!),
                  home: screen,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        for (final (name, screen) in <(String, Widget)>[
          ('today', const ShellScreen()),
          ('forecast', const Scaffold(body: ForecastScreen())),
          ('coach', const CoachScreen()),
          ('profile', const Scaffold(body: ProfileScreen())),
          ('onboarding', const OnboardingScreen()),
          ('form', const ActivityLogScreen()),
          ('appearance', const AppearanceScreen()),
        ]) {
          await show(screen);
          await _capture(tester, '${brightness.name}-$name');
        }
        await tester.scrollUntilVisible(
          find.byKey(const Key('appearance-preset-custom')).hitTestable(),
          300,
        );
        await tester.pumpAndSettle();
        await _capture(tester, '${brightness.name}-presets');
        await tester.tap(find.byKey(const Key('appearance-preset-custom')));
        await tester.pumpAndSettle();
        await _capture(tester, '${brightness.name}-custom');
        await tester.scrollUntilVisible(
          find.byKey(const Key('appearance-custom-apply')).hitTestable(),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await _capture(tester, '${brightness.name}-preview');
        final context = tester.element(find.byType(Scaffold).last);
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Theme preview'),
            content: const Text(
              'Buttons, text and dialogs follow your appearance.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await _capture(tester, '${brightness.name}-dialog');
      },
    );
  }
}
