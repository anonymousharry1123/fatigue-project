import 'package:flutter/material.dart';

abstract final class TonyoColors {
  static const background = Color(0xFF080910);
  static const surface = Color(0xFF13141E);
  static const surfaceRaised = Color(0xFF1A1B28);
  static const border = Color(0xFF262837);
  static const primary = Color(0xFF7567FF);
  static const blue = Color(0xFF55A7FF);
  static const mint = Color(0xFF5FE0C4);
  static const coral = Color(0xFFFF716E);
  static const amber = Color(0xFFFFB54A);
  static const violet = Color(0xFFA56BFF);
  static const text = Color(0xFFF7F7FB);
  static const muted = Color(0xFF9A9CAD);
}

ThemeData buildTonyoTheme() {
  const scheme = ColorScheme.dark(
    primary: TonyoColors.primary,
    secondary: TonyoColors.mint,
    surface: TonyoColors.surface,
    error: TonyoColors.coral,
    onPrimary: Colors.white,
    onSecondary: TonyoColors.background,
    onSurface: TonyoColors.text,
    onError: Colors.white,
  );
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: TonyoColors.background,
    useMaterial3: true,
    fontFamily: 'SF Pro Display',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -.6,
      ),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(fontSize: 15, height: 1.45),
      bodyMedium: TextStyle(fontSize: 13, height: 1.4),
      labelLarge: TextStyle(fontWeight: FontWeight.w800),
    ),
    cardTheme: CardThemeData(
      color: TonyoColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: TonyoColors.border),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TonyoColors.surfaceRaised,
      labelStyle: const TextStyle(color: TonyoColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TonyoColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TonyoColors.primary, width: 1.5),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: TonyoColors.surfaceRaised,
      contentTextStyle: TextStyle(color: TonyoColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      height: 72,
      backgroundColor: TonyoColors.surface,
      indicatorColor: Color(0x337567FF),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
