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
}
