import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'vault_colors.dart';

/// Dark theme tuned to feel like HD Smith / Hide Something:
/// deep teal chrome, near-black surfaces, pink hearts as the only accent.
/// See docs/02-design/design-system.md + Play Store screenshots.
abstract final class AppTheme {
  static ThemeData get dark {
    // Teal chrome taken from HD Smith app bars / segmented control.
    const tealChrome = Color(0xFF1B3A36);
    const tealChromeHigh = Color(0xFF244842);
    const surface = Color(0xFF101412);
    const surfaceContainer = Color(0xFF161C1A);
    const onSurface = Color(0xFFE8ECEA);
    const onVariant = Color(0xFF9AA6A2);

    const scheme = ColorScheme.dark(
      surface: surface,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: tealChromeHigh,
      surfaceContainerHighest: tealChrome,
      onSurface: onSurface,
      onSurfaceVariant: onVariant,
      primary: Color(0xFF5ECFBA), // soft teal accent for buttons/FAB
      onPrimary: Color(0xFF06221E),
      secondary: Color(0xFFFF4D6D), // heart family
      onSecondary: Colors.white,
      outline: Color(0xFF2E3C38),
      error: Color(0xFFFF6B6B),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      extensions: const [VaultColors.dark],
      appBarTheme: const AppBarTheme(
        backgroundColor: tealChrome,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: tealChromeHigh,
        contentTextStyle: TextStyle(color: onSurface),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return tealChromeHigh;
            }
            return tealChrome;
          }),
          foregroundColor: WidgetStateProperty.all(onSurface),
        ),
      ),
    );
  }
}
