import 'package:flutter/widgets.dart';

/// Product branding (display name, author, license).
abstract final class AppInfo {
  static const String name = 'Privi';
  static const String fullName = 'Privi';
  static const String version = '0.1.0';
  static const String author = 'kcng0';
  static const String authorUrl = 'https://github.com/kcng0';
  static const String tagline =
      'Personal offline media vault — hide, rate, and play privately.';
  static const String about =
      'Privi is a personal, offline Android media vault. '
      'Hide photos and videos from the system gallery, rate them with hearts, '
      'organize into albums, and play them back with a PIN/pattern lock.\n\n'
      'Sideload-only. No cloud, no accounts, no analytics.';
  static const String licenseShort = 'Non-commercial personal use only';
  static const String licenseBody =
      'Copyright (c) 2026 kcng0 (https://github.com/kcng0)\n\n'
      'Non-Commercial License\n\n'
      'Permission is granted to use, copy, and modify this software for '
      'personal, non-commercial purposes only.\n\n'
      'You may NOT sell, sublicense, or use this software (or derivatives) '
      'for any commercial purpose without prior written permission from the author.\n\n'
      'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.\n\n'
      'Author: kcng0 — https://github.com/kcng0';
}

/// App-wide constants. Tuned to dense gallery look.
abstract final class AppSpacing {
  static const double unit = 4;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  static const EdgeInsets screen = EdgeInsets.all(lg);
}

abstract final class AppRadii {
  /// album tiles are nearly square with tiny corners.
  static const double thumbnail = 2;
  static const double albumTile = 4;
  static const double card = 12;
  static const double badge = 10;
}

abstract final class GridDefaults {
  /// Home: 3-column album mosaic.
  static const int albumColumns = 3;

  /// Media grid default (d9).
  static const int columns = 3;
  static const double gutter = 2;
  static const double ratingBarHeight = 22;

  /// Space under last row so thumbs clear the system nav bar.
  static const double bottomClearance = 24;

  /// Extra when floating selection capsule is visible.
  static const double selectionCapsuleClearance = 100;
}

abstract final class VaultPaths {
  /// App-private thumbs/metadata (documents dir).
  static const String vaultDir = 'vault';
  static const String thumbsDir = 'thumbs';
  static const String nomedia = '.nomedia';

  /// Shared-storage hide root (dot folder + .nomedia).
  /// Lives on primary external storage so moves are renames, not copies.
  static const String hiddenRootName = '.privateheart_vault';
}

abstract final class RatingRules {
  static const int min = 0;
  static const int max = 3;
  static const int favoriteThreshold = 1;
}
