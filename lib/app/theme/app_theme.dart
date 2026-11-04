import 'package:flutter/material.dart';

class AppTheme {
  static const accent = Color(0xFF3D6AE0);
  static const darkAccent = Color(0xFF7FA3FF);
  static const lightBackground = Color(0xFFF4F5F7);
  static const lightSurface = Color(0xFFFBFBFC);
  static const lightBorder = Color(0xFFE4E6EA);
  static const lightText = Color(0xFF1B1D21);
  static const lightTextSecondary = Color(0xFF6B7078);
  static const lightTextTertiary = Color(0xFF9AA0A8);
  static const lightSelection = Color(0xFFEAF0FD);
  static const darkBackground = Color(0xFF17181B);
  static const darkSurface = Color(0xFF1E2024);
  static const darkBorder = Color(0xFF2C2F35);
  static const darkText = Color(0xFFEDEEF0);
  static const darkTextSecondary = Color(0xFFA0A4AB);

  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = isDark ? darkBackground : lightBackground;
    final surface = isDark ? darkSurface : lightSurface;
    final border = isDark ? darkBorder : lightBorder;
    final text = isDark ? darkText : lightText;
    final secondary = isDark ? darkTextSecondary : lightTextSecondary;
    final primary = isDark ? darkAccent : accent;
    final selection =
        isDark ? const Color(0x297FA3FF) : lightSelection;

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: isDark ? const Color(0xFF10131A) : Colors.white,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: secondary,
      outlineVariant: border,
      secondaryContainer: selection,
      onSecondaryContainer: text,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: primary),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    );
  }
}
