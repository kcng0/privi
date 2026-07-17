import 'package:flutter/material.dart';

/// App-specific colors that are not part of the Material [ColorScheme].
///
/// The heart accent is intentionally distinct from `ColorScheme.primary` so
/// favorites stay legible even when a primary-colored control is on screen.
/// See docs/02-design/design-system.md.
@immutable
class VaultColors extends ThemeExtension<VaultColors> {
  const VaultColors({
    required this.heart,
    required this.heartOutline,
    required this.scrim,
    required this.chrome,
    required this.surface,
    required this.surfaceAlt,
  });

  /// Filled heart glyph.
  final Color heart;

  /// Empty (outline) heart glyph.
  final Color heartOutline;

  /// Semi-transparent overlay used behind the thumbnail rating bar and viewer
  /// chrome so content stays readable over any image.
  final Color scrim;

  /// Teal app bars, sheets, and floating chrome.
  final Color chrome;

  /// Primary dark page surface.
  final Color surface;

  /// Raised/selected teal surface.
  final Color surfaceAlt;

  static const dark = VaultColors(
    heart: Color(0xFFFF4D6D),
    heartOutline: Color(0xFF8A8A90),
    scrim: Color(0x8C000000), // black @ ~55%
    chrome: Color(0xFF1B3A36),
    surface: Color(0xFF101412),
    surfaceAlt: Color(0xFF244842),
  );

  @override
  VaultColors copyWith({
    Color? heart,
    Color? heartOutline,
    Color? scrim,
    Color? chrome,
    Color? surface,
    Color? surfaceAlt,
  }) {
    return VaultColors(
      heart: heart ?? this.heart,
      heartOutline: heartOutline ?? this.heartOutline,
      scrim: scrim ?? this.scrim,
      chrome: chrome ?? this.chrome,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    );
  }

  @override
  VaultColors lerp(ThemeExtension<VaultColors>? other, double t) {
    if (other is! VaultColors) return this;
    return VaultColors(
      heart: Color.lerp(heart, other.heart, t)!,
      heartOutline: Color.lerp(heartOutline, other.heartOutline, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      chrome: Color.lerp(chrome, other.chrome, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
    );
  }
}

/// Convenience accessor: `context.vaultColors.heart`.
extension VaultColorsX on BuildContext {
  VaultColors get vaultColors => Theme.of(this).extension<VaultColors>()!;
}
