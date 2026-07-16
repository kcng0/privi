import 'package:flutter/widgets.dart';

import '../domain/enums.dart';
import '../domain/models/album.dart';
import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart';

/// Convenience: `context.l10n.xxx`
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Map a device [Locale] (or prefs override) to a supported app locale.
///
/// - `zh_HK` / `zh_MO` / `zh_TW` → Traditional (Hong Kong pack)
/// - other `zh*` → Simplified (China pack)
/// - everything else → English
Locale resolveAppLocale(Locale? device, {String overrideCode = ''}) {
  if (overrideCode == 'en') return const Locale('en');
  if (overrideCode == 'zh_CN') return const Locale('zh', 'CN');
  if (overrideCode == 'zh_HK') return const Locale('zh', 'HK');

  final lang = device?.languageCode.toLowerCase() ?? 'en';
  if (lang != 'zh') return const Locale('en');

  final country = (device?.countryCode ?? '').toUpperCase();
  if (country == 'HK' || country == 'MO' || country == 'TW') {
    return const Locale('zh', 'HK');
  }
  // Mainland / Singapore / generic Chinese → Simplified.
  return const Locale('zh', 'CN');
}

Locale? localeFromCode(String code) {
  return switch (code) {
    'en' => const Locale('en'),
    'zh_CN' => const Locale('zh', 'CN'),
    'zh_HK' => const Locale('zh', 'HK'),
    _ => null, // system
  };
}

/// System albums keep English names in the DB; map them for UI display.
String localizedAlbumTitle(
  AppLocalizations l10n, {
  required String name,
  SystemAlbumKind? systemKind,
  String? albumId,
}) {
  final kind = systemKind ??
      (albumId == SystemAlbumIds.all
          ? SystemAlbumKind.all
          : albumId == SystemAlbumIds.favorites
              ? SystemAlbumKind.favorites
              : albumId == SystemAlbumIds.recycle
                  ? SystemAlbumKind.recycle
                  : null);
  return switch (kind) {
    SystemAlbumKind.all => l10n.allMedia,
    SystemAlbumKind.favorites => l10n.favorites,
    SystemAlbumKind.recycle => l10n.recycleBin,
    null => name,
  };
}
