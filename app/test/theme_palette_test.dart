import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pairs = [
    for (final preset in tonyoThemePresets) (preset.name, preset.colors),
    (
      'black',
      const TonyoColorPair(main: Colors.black, secondary: Colors.black),
    ),
    (
      'white',
      const TonyoColorPair(main: Colors.white, secondary: Colors.white),
    ),
    (
      'pale',
      const TonyoColorPair(
        main: Color(0xFFFFF5A0),
        secondary: Color(0xFFFFE4F2),
      ),
    ),
    (
      'opposites',
      const TonyoColorPair(main: Colors.black, secondary: Colors.white),
    ),
  ];
  for (final brightness in Brightness.values) {
    for (final (name, pair) in pairs) {
      test(
        '$name ${brightness.name} preserves readable text, controls and charts',
        () {
          final theme = buildTonyoTheme(brightness: brightness, colors: pair);
          final palette = theme.extension<TonyoPalette>()!;
          final scheme = theme.colorScheme;
          expect(theme.brightness, brightness);
          for (final background in [
            palette.background,
            palette.surface,
            palette.surfaceRaised,
          ]) {
            for (final foreground in [
              palette.text,
              palette.muted,
              palette.primary,
              palette.secondary,
              palette.success,
              palette.warning,
              palette.error,
            ]) {
              expect(
                tonyoContrastRatio(foreground, background),
                greaterThanOrEqualTo(4.5),
                reason: '$foreground must be readable on $background',
              );
            }
            for (final accent in [
              palette.primary,
              palette.secondary,
              palette.success,
              palette.warning,
              palette.error,
            ]) {
              final tinted = Color.alphaBlend(
                accent.withValues(alpha: .24),
                background,
              );
              expect(
                tonyoContrastRatio(accent, tinted),
                greaterThanOrEqualTo(4.5),
              );
            }
          }
          for (final (foreground, background) in [
            (scheme.onPrimary, scheme.primary),
            (scheme.onSecondary, scheme.secondary),
            (scheme.onPrimaryContainer, scheme.primaryContainer),
            (scheme.onSecondaryContainer, scheme.secondaryContainer),
            (scheme.onError, scheme.error),
            (scheme.onErrorContainer, scheme.errorContainer),
          ]) {
            expect(
              tonyoContrastRatio(foreground, background),
              greaterThanOrEqualTo(4.5),
            );
          }
        },
      );
    }
    test(
      '${brightness.name} custom colors do not recolor neutrals or status meanings',
      () {
        final reference = TonyoPalette.resolve(brightness, defaultTonyoColors);
        for (final (_, pair) in pairs) {
          final palette = TonyoPalette.resolve(brightness, pair);
          expect(palette.background, reference.background);
          expect(palette.text, reference.text);
          expect(palette.success, reference.success);
          expect(palette.warning, reference.warning);
          expect(palette.error, reference.error);
        }
      },
    );
  }
  test('system bar icon contrast follows the selected brightness', () {
    for (final brightness in Brightness.values) {
      final style = tonyoSystemOverlay(
        brightness,
        TonyoPalette.resolve(brightness, defaultTonyoColors),
      );
      final icons = brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark;
      expect(style.statusBarIconBrightness, icons);
      expect(style.systemNavigationBarIconBrightness, icons);
      expect(style.statusBarBrightness, brightness);
    }
  });
}
