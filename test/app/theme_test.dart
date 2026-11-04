import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/theme/app_theme.dart';

void main() {
  test('light theme uses the approved palette', () {
    final theme = AppTheme.light;
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF4F5F7));
    expect(theme.colorScheme.primary, const Color(0xFF3D6AE0));
    expect(theme.colorScheme.surface, const Color(0xFFFBFBFC));
    expect(theme.colorScheme.outlineVariant, const Color(0xFFE4E6EA));
    expect(theme.cardTheme.elevation, 0);
  });

  test('dark theme uses the approved palette', () {
    final theme = AppTheme.dark;
    expect(theme.scaffoldBackgroundColor, const Color(0xFF17181B));
    expect(theme.colorScheme.primary, const Color(0xFF7FA3FF));
    expect(theme.colorScheme.surface, const Color(0xFF1E2024));
    expect(theme.colorScheme.outlineVariant, const Color(0xFF2C2F35));
  });

  test('typography uses one role-based scale', () {
    final text = AppTheme.light.textTheme;

    expect(text.titleLarge?.fontSize, 20);
    expect(text.titleLarge?.fontWeight, FontWeight.w600);
    expect(text.titleMedium?.fontSize, 16);
    expect(text.titleMedium?.fontWeight, FontWeight.w600);
    expect(text.titleSmall?.fontSize, 14);
    expect(text.titleSmall?.fontWeight, FontWeight.w600);

    expect(text.bodyLarge?.fontSize, 15);
    expect(text.bodyLarge?.fontWeight, FontWeight.w400);
    expect(text.bodyMedium?.fontSize, 14);
    expect(text.bodyMedium?.fontWeight, FontWeight.w400);
    expect(text.bodySmall?.fontSize, 12);
    expect(text.bodySmall?.fontWeight, FontWeight.w400);
  });

  test('app bars and dialogs share the title roles', () {
    final theme = AppTheme.light;

    expect(theme.appBarTheme.titleTextStyle?.fontSize, 16);
    expect(theme.appBarTheme.titleTextStyle?.fontWeight, FontWeight.w600);
    expect(theme.dialogTheme.titleTextStyle?.fontSize, 20);
    expect(theme.dialogTheme.titleTextStyle?.fontWeight, FontWeight.w600);
  });
}
