import 'package:app/src/screens/appearance_screen.dart';
import 'package:app/src/theme.dart';
import 'package:app/src/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements ThemePreferencesStore {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('Save failed');
    this.value = value;
  }
}

Widget _app(ThemeController controller, {double textScale = 1}) => ThemeScope(
  controller: controller,
  child: ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      theme: buildTonyoTheme(colors: controller.preferences.colors),
      darkTheme: buildTonyoTheme(
        brightness: Brightness.dark,
        colors: controller.preferences.colors,
      ),
      themeMode: controller.preferences.mode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const AppearanceScreen(),
    ),
  ),
);

Future<void> _show(WidgetTester tester, Key key) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final finder = find.byKey(key);
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _openCustom(WidgetTester tester) async {
  const key = Key('appearance-preset-custom');
  await _show(tester, key);
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a failed lower preset shows a visible Retry without scrolling', (
    tester,
  ) async {
    final store = _Store()..fail = true;
    final controller = ThemeController(store: store);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await _show(tester, const Key('appearance-preset-sunset'));
    await tester.tap(find.byKey(const Key('appearance-preset-sunset')));
    await tester.pumpAndSettle();
    expect(controller.preferences.presetId, 'classic');
    final retry = find.descendant(
      of: find.byType(SnackBar),
      matching: find.text('Retry'),
    );
    expect(retry.hitTestable(), findsOneWidget);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(retry.hitTestable(), findsOneWidget);
    store.fail = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(controller.preferences.presetId, 'sunset');
    expect(controller.error, isNull);
  });

  testWidgets(
    'mode and preset choices apply immediately without replacing the navigator',
    (tester) async {
      final controller = ThemeController(store: _Store());
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(
        tester
            .getSize(
              find.byKey(const Key('appearance-preset-classic-preview-chart')),
            )
            .height,
        greaterThan(0),
      );
      await tester.tap(find.byKey(const Key('appearance-mode-dark')));
      await tester.pumpAndSettle();
      expect(controller.preferences.mode, ThemeMode.dark);
      expect(
        Theme.of(tester.element(find.text('Appearance'))).brightness,
        Brightness.dark,
      );
      await _show(tester, const Key('appearance-preset-ocean'));
      await tester.tap(find.byKey(const Key('appearance-preset-ocean')));
      await tester.pumpAndSettle();
      expect(controller.preferences.presetId, 'ocean');
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)),
        same(navigator),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom edits preview locally and Cancel or back discard the draft',
    (tester) async {
      final controller = ThemeController(store: _Store());
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      for (final cancelButton in [true, false]) {
        await _openCustom(tester);
        final hex = find.byKey(const Key('appearance-main-hex'));
        expect(tester.widget<TextFormField>(hex).controller!.text, '#2563EB');
        await tester.enterText(hex, '#FFFFFF');
        await tester.pumpAndSettle();
        expect(controller.preferences, const ThemePreferences());
        expect(find.byKey(const Key('appearance-main-red')), findsOneWidget);
        if (cancelButton) {
          await _show(tester, const Key('appearance-custom-cancel'));
          await tester.tap(find.byKey(const Key('appearance-custom-cancel')));
        } else {
          await tester.pageBack();
        }
        await tester.pumpAndSettle();
        expect(controller.preferences, const ThemePreferences());
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed Apply retains draft and Retry saves the custom pair', (
    tester,
  ) async {
    final store = _Store()..fail = true;
    final controller = ThemeController(store: store);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await _openCustom(tester);
    await tester.enterText(
      find.byKey(const Key('appearance-main-hex')),
      '#FFFFFF',
    );
    await _show(tester, const Key('appearance-secondary-hex'));
    await tester.enterText(
      find.byKey(const Key('appearance-secondary-hex')),
      '#FFFFFF',
    );
    await _show(tester, const Key('appearance-custom-apply'));
    await tester.tap(find.byKey(const Key('appearance-custom-apply')));
    await tester.pumpAndSettle();
    expect(controller.preferences, const ThemePreferences());
    expect(find.text('Custom theme'), findsOneWidget);
    expect(
      find.text('Could not save appearance. Please retry.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    store.fail = false;
    await tester.tap(find.byKey(const Key('appearance-custom-apply')));
    await tester.pumpAndSettle();
    expect(controller.preferences.presetId, 'custom');
    expect(
      controller.preferences.customColors,
      const TonyoColorPair(main: Colors.white, secondary: Colors.white),
    );
    expect(find.text('Custom theme'), findsNothing);
    await _openCustom(tester);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('appearance-main-hex')))
          .controller!
          .text,
      '#FFFFFF',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid hex prevents Apply and sliders produce valid hex', (
    tester,
  ) async {
    final controller = ThemeController(store: _Store());
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await _openCustom(tester);
    await tester.enterText(
      find.byKey(const Key('appearance-main-hex')),
      'invalid',
    );
    await _show(tester, const Key('appearance-custom-apply'));
    await tester.tap(find.byKey(const Key('appearance-custom-apply')));
    await tester.pumpAndSettle();
    expect(controller.preferences, const ThemePreferences());
    expect(find.text('Custom theme'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('appearance-main-red')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    final slider = tester.widget<Slider>(
      find.byKey(const Key('appearance-main-red')),
    );
    slider.onChanged!(255);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('appearance-main-hex')))
          .controller!
          .text,
      '#FF63EB',
    );
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'Appearance and custom editor fit 320px at 200% text in ${mode.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = ThemeController(
          store: _Store(),
          initialPreferences: ThemePreferences(mode: mode),
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(_app(controller, textScale: 2));
        await _openCustom(tester);
        await _show(tester, const Key('appearance-custom-apply'));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('appearance-custom-cancel')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
