import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'typography.dart';

/// Material 3 on Android stretches scroll content at the edge; disable that.
class TonyoScrollBehavior extends MaterialScrollBehavior {
  const TonyoScrollBehavior();
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

@immutable
class TonyoColorPair {
  const TonyoColorPair({required this.main, required this.secondary});
  final Color main;
  final Color secondary;
  @override
  bool operator ==(Object other) =>
      other is TonyoColorPair &&
      other.main == main &&
      other.secondary == secondary;
  @override
  int get hashCode => Object.hash(main, secondary);
}

@immutable
class TonyoThemePreset {
  const TonyoThemePreset(this.id, this.name, this.colors);
  final String id;
  final String name;
  final TonyoColorPair colors;
}

const defaultTonyoColors = TonyoColorPair(
  main: Color(0xFF315EFB),
  secondary: Color(0xFF0C8F7D),
);
const tonyoThemePresets = [
  TonyoThemePreset('classic', 'Classic', defaultTonyoColors),
  TonyoThemePreset(
    'ocean',
    'Ocean',
    TonyoColorPair(main: Color(0xFF007DB8), secondary: Color(0xFF6546DF)),
  ),
  TonyoThemePreset(
    'forest',
    'Forest',
    TonyoColorPair(main: Color(0xFF0A8552), secondary: Color(0xFFBE8115)),
  ),
  TonyoThemePreset(
    'clay',
    'Clay',
    TonyoColorPair(main: Color(0xFFC34F2D), secondary: Color(0xFF087F8C)),
  ),
  TonyoThemePreset(
    'plum',
    'Plum',
    TonyoColorPair(main: Color(0xFF8538C7), secondary: Color(0xFFD13C73)),
  ),
  TonyoThemePreset(
    'sunset',
    'Sunset',
    TonyoColorPair(main: Color(0xFFDC6B0C), secondary: Color(0xFFBB2859)),
  ),
];

double tonyoContrastRatio(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

/// Adjust lightness only as far as needed for readable labels, retaining the
/// source hue and saturation instead of washing darker accents toward grey.
Color _readableAccent(
  Color source,
  Brightness brightness,
  List<Color> surfaces,
) {
  final opaque = source.withValues(alpha: 1);
  final sourceHsl = HSLColor.fromColor(opaque);
  final targetLightness = brightness == Brightness.light ? 0.0 : 1.0;
  Color adjusted(double amount) => sourceHsl
      .withLightness(
        sourceHsl.lightness + (targetLightness - sourceHsl.lightness) * amount,
      )
      .toColor();
  bool readable(Color candidate) => surfaces.every(
    (surface) =>
        tonyoContrastRatio(candidate, surface) >= 4.5 &&
        tonyoContrastRatio(
              candidate,
              Color.alphaBlend(candidate.withValues(alpha: .24), surface),
            ) >=
            4.5,
  );
  if (readable(opaque)) return opaque;
  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 24; i++) {
    final middle = (low + high) / 2;
    if (readable(adjusted(middle))) {
      high = middle;
    } else {
      low = middle;
    }
  }
  return adjusted(high);
}

Color _onAccent(Color color) =>
    tonyoContrastRatio(Colors.white, color) >=
        tonyoContrastRatio(Colors.black, color)
    ? Colors.white
    : Colors.black;

@immutable
class TonyoPalette extends ThemeExtension<TonyoPalette> {
  const TonyoPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.primary,
    required this.secondary,
    required this.text,
    required this.muted,
    required this.success,
    required this.warning,
    required this.error,
  });

  factory TonyoPalette.resolve(Brightness brightness, TonyoColorPair colors) {
    final dark = brightness == Brightness.dark;
    final background = Color(dark ? 0xFF000000 : 0xFFEDF3FB);
    final surface = Color(dark ? 0xFF090E15 : 0xFFFFFFFF);
    final raised = Color(dark ? 0xFF131C27 : 0xFFE1EAF6);
    final surfaces = [background, surface, raised];
    Color accent(Color seed) => _readableAccent(seed, brightness, surfaces);
    return TonyoPalette(
      background: background,
      surface: surface,
      surfaceRaised: raised,
      border: Color(dark ? 0xFF344156 : 0xFFBCCCE0),
      primary: accent(colors.main),
      secondary: accent(colors.secondary),
      text: Color(dark ? 0xFFF8FAFC : 0xFF102033),
      muted: Color(dark ? 0xFFBBC6D7 : 0xFF465B74),
      success: accent(const Color(0xFF237A4B)),
      warning: accent(const Color(0xFF936000)),
      error: accent(const Color(0xFFBA3542)),
    );
  }

  static TonyoPalette of(BuildContext context) =>
      Theme.of(context).extension<TonyoPalette>() ??
      TonyoPalette.resolve(Theme.of(context).brightness, defaultTonyoColors);
  final Color background, surface, surfaceRaised, border, primary, secondary;
  final Color text, muted, success, warning, error;
  // Category aliases share two accents; status colors stay independent.
  Color get blue => primary;
  Color get mint => secondary;
  Color get violet => secondary;
  Color get coral => error;
  Color get amber => warning;

  @override
  TonyoPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? primary,
    Color? secondary,
    Color? text,
    Color? muted,
    Color? success,
    Color? warning,
    Color? error,
  }) => TonyoPalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    border: border ?? this.border,
    primary: primary ?? this.primary,
    secondary: secondary ?? this.secondary,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    error: error ?? this.error,
  );

  @override
  TonyoPalette lerp(covariant TonyoPalette? other, double t) {
    if (other == null) return this;
    return TonyoPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      border: Color.lerp(border, other.border, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }
}

ThemeData buildTonyoTheme({
  Brightness brightness = Brightness.light,
  TonyoColorPair colors = defaultTonyoColors,
  TonyoFont font = TonyoFont.system,
}) {
  final palette = TonyoPalette.resolve(brightness, colors);
  final dark = brightness == Brightness.dark;
  Color tint(Color color) =>
      Color.alphaBlend(color.withValues(alpha: .18), palette.surface);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: palette.primary,
    onPrimary: _onAccent(palette.primary),
    primaryContainer: tint(palette.primary),
    onPrimaryContainer: palette.primary,
    secondary: palette.secondary,
    onSecondary: _onAccent(palette.secondary),
    secondaryContainer: tint(palette.secondary),
    onSecondaryContainer: palette.secondary,
    tertiary: palette.secondary,
    onTertiary: _onAccent(palette.secondary),
    tertiaryContainer: tint(palette.secondary),
    onTertiaryContainer: palette.secondary,
    surface: palette.surface,
    onSurface: palette.text,
    surfaceDim: palette.background,
    surfaceBright: palette.surfaceRaised,
    surfaceContainerLowest: palette.background,
    surfaceContainerLow: palette.surface,
    surfaceContainer: palette.surface,
    surfaceContainerHigh: palette.surfaceRaised,
    surfaceContainerHighest: palette.surfaceRaised,
    onSurfaceVariant: palette.muted,
    error: palette.error,
    onError: _onAccent(palette.error),
    errorContainer: tint(palette.error),
    onErrorContainer: palette.error,
    outline: palette.muted,
    outlineVariant: palette.border,
    inverseSurface: dark ? const Color(0xFFF8FAFC) : const Color(0xFF102033),
    onInverseSurface: dark ? const Color(0xFF102033) : const Color(0xFFF8FAFC),
    inversePrimary: TonyoPalette.resolve(
      dark ? Brightness.light : Brightness.dark,
      colors,
    ).primary,
    surfaceTint: Colors.transparent,
  );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: font.family,
    scaffoldBackgroundColor: palette.background,
    extensions: [palette],
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -.6,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -.3,
      ),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 15, height: 1.45),
      bodyMedium: TextStyle(fontSize: 13, height: 1.4),
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      foregroundColor: palette.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: tonyoSystemOverlay(brightness, palette),
    ),
    cardTheme: CardThemeData(
      color: palette.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(color: palette.border),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceRaised,
      labelStyle: TextStyle(color: palette.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: rounded,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: rounded,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: rounded,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surfaceRaised,
      contentTextStyle: TextStyle(color: palette.text, fontFamily: font.family),
      actionTextColor: palette.primary,
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? palette.primary
              : palette.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: font.family,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? palette.primary
              : palette.muted,
        ),
      ),
    ),
  );
}

SystemUiOverlayStyle tonyoSystemOverlay(
  Brightness brightness,
  TonyoPalette palette,
) {
  final dark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: brightness,
    systemNavigationBarColor: palette.surface,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
  );
}
