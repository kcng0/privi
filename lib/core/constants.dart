import 'package:flutter/widgets.dart';

/// App-wide constants. See docs/02-design/design-system.md.
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
  static const double thumbnail = 8;
  static const double card = 16;
}

abstract final class GridDefaults {
  static const int columns = 3; // default (d9)
  static const double gutter = 2;
  static const double ratingBarHeight = 24;
}

abstract final class VaultPaths {
  /// Subdirectory (under app documents) that holds all hidden media.
  static const String vaultDir = 'vault';
  static const String thumbsDir = 'thumbs';
  static const String nomedia = '.nomedia';
}

abstract final class RatingRules {
  static const int min = 0;
  static const int max = 3;
  static const int favoriteThreshold = 1; // rating >= 1 => favorite
}
