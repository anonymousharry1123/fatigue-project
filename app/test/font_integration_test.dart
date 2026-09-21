import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/demo_data.dart';
import 'package:app/src/theme_controller.dart';
import 'package:app/src/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'navigation_test_support.dart';
import 'privacy_test_support.dart';
import 'font_test_support.dart';

const _screenshots = bool.fromEnvironment('FONT_SCREENSHOTS');
const _captureKey = Key('font-review-capture');

class _Store implements ThemePreferencesStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  if (!_screenshots) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/font-review')
      ..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapChoice(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: activeVerticalScrollable(),
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String? _renderedFamily(WidgetTester tester, Finder text) => tester
    .widget<RichText>(
      find.descendant(of: text, matching: find.byType(RichText)),
    )
    .text
    .style!
    .fontFamily;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(loadAppearanceFonts);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'font picker updates actual app text and retains routes in ${mode.name}',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app =
            AppController(initialPrivacyConsent: testAdultPrivacyConsent)
              ..isReady = true
              ..onboardingComplete = true
              ..signals = buildDemoSignals(DateTime(2026, 9, 20, 9))
              ..checkIns = buildDemoCheckIns(DateTime(2026, 9, 20, 9));
        final store = _Store();
        final appearance = ThemeController(
          store: store,
          initialPreferences: ThemePreferences(mode: mode),
        );
        addTearDown(app.dispose);
        addTearDown(appearance.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: _captureKey,
            child: TonyoApp(controller: app, themeController: appearance),
          ),
        );
        await tester.pumpAndSettle();
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        final systemFamily = Theme.of(
          tester.element(find.byType(NavigationBar)),
        ).textTheme.bodyMedium!.fontFamily;

        for (final font in [...TonyoFont.values.skip(1), TonyoFont.system]) {
          await _selectTab(tester, 'Profile');
          await _tapChoice(tester, const Key('appearance-setting'));
          await _tapChoice(tester, const Key('appearance-font-picker'));
          await _tapChoice(tester, Key('appearance-font-${font.name}'));
          expect(appearance.preferences.font, font);
          expect(ThemePreferences.decode(store.value).font, font);
          expect(find.text('Font'), findsOneWidget);
          expect(
            _renderedFamily(tester, find.text('Font')),
            font.family ?? systemFamily,
          );
          expect(
            tester.state<NavigatorState>(find.byType(Navigator)),
            same(navigator),
          );
          expect(
            Theme.of(tester.element(find.text('Font'))).brightness,
            mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
          );
          tester
              .state<ScrollableState>(activeVerticalScrollable())
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          await _capture(tester, '${mode.name}-${font.name}-picker');
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(
            _renderedFamily(tester, find.text('Appearance')),
            font.family ?? systemFamily,
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            4,
          );
          await _selectTab(tester, 'Today');
          final label = find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Today'),
          );
          expect(_renderedFamily(tester, label), font.family ?? systemFamily);
          await _capture(tester, '${mode.name}-${font.name}-today');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
