import 'package:flutter/material.dart';

class GloColors {
  static const primary = Color(0xFF00A651);
  static const darkGreen = Color(0xFF006B3F);
  static const green900 = Color(0xFF064E32);
  static const lightGreen = Color(0xFFEAF8F0);
  static const mint = Color(0xFFF3FBF6);
  static const background = Color(0xFFF7F9F8);
  static const ink = Color(0xFF15231D);
  static const muted = Color(0xFF6D7A74);
  static const border = Color(0xFFE4EAE7);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFDC3545);
  static const blue = Color(0xFF2563EB);
  static const surface = Color(0xFFF7F9F8);
}

class GloTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: GloColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: GloColors.primary,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: GloColors.ink,
      outline: GloColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: GloColors.background,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: GloColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: GloColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        labelStyle: const TextStyle(color: GloColors.muted),
        prefixIconColor: GloColors.muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: GloColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: GloColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: GloColors.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: GloColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: GloColors.darkGreen,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: GloColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: GloColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: GloColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(color: GloColors.border, thickness: 1),
    );
  }
}
