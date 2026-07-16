import 'package:flutter/material.dart';

import 'vault_colors.dart';

/// The single (dark-only) app theme. See docs/02-design/design-system.md.
abstract final class AppTheme {
  /// Material 3 dark theme with the vault color tokens.
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      surface: Color(0xFF0E0E10),
      surfaceContainer: Color(0xFF1A1A1D),
      surfaceContainerHigh: Color(0xFF232327),
      onSurface: Color(0xFFECECEE),
      onSurfaceVariant: Color(0xFFA0A0A6),
      primary: Color(0xFFB794F6),
      onPrimary: Color(0xFF1A1A1D),
      outline: Color(0xFF3A3A40),
      error: Color(0xFFFF6B6B),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      extensions: const [VaultColors.dark],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainer,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
    );
  }
}
