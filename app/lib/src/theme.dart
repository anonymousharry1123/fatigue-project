import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  main: Color(0xFF2563EB),
  secondary: Color(0xFF64748B),
);
const tonyoThemePresets = [
  TonyoThemePreset('classic', 'Classic', defaultTonyoColors),
  TonyoThemePreset(
    'ocean',
    'Ocean',
    TonyoColorPair(main: Color(0xFF0369A1), secondary: Color(0xFF0D9488)),
  ),
  TonyoThemePreset(
    'forest',
    'Forest',
    TonyoColorPair(main: Color(0xFF3F6B4F), secondary: Color(0xFFA07845)),
  ),
  TonyoThemePreset(
    'clay',
    'Clay',
    TonyoColorPair(main: Color(0xFFB65D43), secondary: Color(0xFF64748B)),
  ),
  TonyoThemePreset(
    'plum',
    'Plum',
    TonyoColorPair(main: Color(0xFF7C5A91), secondary: Color(0xFFB76E79)),
  ),
  TonyoThemePreset(
    'sunset',
    'Sunset',
    TonyoColorPair(main: Color(0xFFD97706), secondary: Color(0xFFC44C7A)),
  ),
];

double tonyoContrastRatio(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

/// Adjust source colors only as far as needed for labels on neutral and tinted fills.
Color _readableAccent(
  Color source,
  Brightness brightness,
  List<Color> surfaces,
) {
  final opaque = source.withValues(alpha: 1);
  final target = brightness == Brightness.light ? Colors.black : Colors.white;
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
    if (readable(Color.lerp(opaque, target, middle)!)) {
      high = middle;
    } else {
      low = middle;
    }
  }
  return Color.lerp(opaque, target, high)!;
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
    final background = Color(dark ? 0xFF121416 : 0xFFF7F7F5);
    final surface = Color(dark ? 0xFF1C1F23 : 0xFFFFFFFF);
    final raised = Color(dark ? 0xFF262A30 : 0xFFF0F1F2);
    final surfaces = [background, surface, raised];
    Color accent(Color seed) => _readableAccent(seed, brightness, surfaces);
    return TonyoPalette(
      background: background,
      surface: surface,
      surfaceRaised: raised,
      border: Color(dark ? 0xFF3D424A : 0xFFD9DDE1),
      primary: accent(colors.main),
      secondary: accent(colors.secondary),
      text: Color(dark ? 0xFFF2F3F5 : 0xFF202328),
      muted: Color(dark ? 0xFFB4BAC3 : 0xFF5B626C),
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
}) {
  final palette = TonyoPalette.resolve(brightness, colors);
  final dark = brightness == Brightness.dark;
  Color tint(Color color) =>
      Color.alphaBlend(color.withValues(alpha: .12), palette.surface);
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
    inverseSurface: dark ? const Color(0xFFF2F3F5) : const Color(0xFF202328),
    onInverseSurface: dark ? const Color(0xFF202328) : const Color(0xFFF2F3F5),
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
      contentTextStyle: TextStyle(color: palette.text),
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
