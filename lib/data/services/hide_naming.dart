import 'package:path/path.dart' as p;

import '../../core/constants.dart';

/// HD Smith–style concealment:
/// **move into a dot-prefixed folder with `.nomedia`** so MediaScanner skips it.
///
/// Legacy in-place markers (`.vid.pg` / `.img.pg`) remain recognized for older
/// rows, but new hides use the vault directory.
abstract final class HideNaming {
  static const videoMarker = '.vid.pg';
  static const imageMarker = '.img.pg';

  static bool isLegacyMarkerPath(String path) {
    final base = p.basenameWithoutExtension(path);
    return base.endsWith(videoMarker) || base.endsWith(imageMarker);
  }

  static bool isHiddenVaultPath(String path) {
    final norm = path.replaceAll('\\', '/');
    return norm.contains('/${VaultPaths.hiddenRootName}/') ||
        norm.endsWith('/${VaultPaths.hiddenRootName}');
  }

  static bool isHiddenPath(String path) =>
      isHiddenVaultPath(path) || isLegacyMarkerPath(path);

  /// Legacy: `…/clip.mp4` → `…/clip.vid.pg.mp4`
  static String toLegacyHiddenPath(String path, {required bool isVideo}) {
    if (isLegacyMarkerPath(path)) return path;
    final dir = p.dirname(path);
    final base = p.basenameWithoutExtension(path);
    final ext = p.extension(path);
    final marker = isVideo ? videoMarker : imageMarker;
    return p.join(dir, '$base$marker$ext');
  }

  /// Reverse legacy marker rename.
  static String fromLegacyHiddenPath(String path) {
    if (!isLegacyMarkerPath(path)) return path;
    final dir = p.dirname(path);
    var base = p.basenameWithoutExtension(path);
    final ext = p.extension(path);
    if (base.endsWith(videoMarker)) {
      base = base.substring(0, base.length - videoMarker.length);
    } else if (base.endsWith(imageMarker)) {
      base = base.substring(0, base.length - imageMarker.length);
    }
    return p.join(dir, '$base$ext');
  }

  /// Back-compat aliases used by sniffers / backup.
  static String toHiddenPath(String path, {required bool isVideo}) =>
      toLegacyHiddenPath(path, isVideo: isVideo);

  static String toVisiblePath(String path) => fromLegacyHiddenPath(path);

  /// Display-friendly original-looking name for UI.
  static String displayName(String pathOrName) {
    final name = p.basename(pathOrName);
    if (isLegacyMarkerPath(name)) {
      return p.basename(fromLegacyHiddenPath(name));
    }
    return name;
  }

  /// Mirror folder segment under the hidden root (e.g. Downloads).
  static String sanitizeFolder(String? folder) {
    var f = (folder ?? 'Imported').trim();
    if (f.isEmpty) f = 'Imported';
    if (f.toLowerCase() == 'download') f = 'Downloads';
    // Strip path separators / dots that could escape the vault root.
    f = f.replaceAll(RegExp(r'[\\/]+'), '_').replaceAll('..', '_');
    if (f.startsWith('.')) f = f.substring(1);
    if (f.isEmpty) f = 'Imported';
    return f;
  }

  /// Primary external storage root used for restore targets.
  static const String publicStorageRoot = '/storage/emulated/0';

  /// Default public folder when mirror is missing / unknown / Imported.
  static const String defaultRestoreDir = '$publicStorageRoot/Download';

  /// Mirror folder segment under `.privateheart_vault/<Folder>/…`, or null.
  static String? vaultMirrorFolder(String privatePath) {
    final norm = privatePath.replaceAll('\\', '/');
    const marker = '/${VaultPaths.hiddenRootName}/';
    final idx = norm.indexOf(marker);
    if (idx < 0) return null;
    final rest = norm.substring(idx + marker.length);
    if (rest.isEmpty) return null;
    final folder = rest.split('/').firstWhere(
      (s) => s.isNotEmpty,
      orElse: () => '',
    );
    return folder.isEmpty ? null : folder;
  }

  /// Map a vault mirror folder name to a public restore directory (pure).
  ///
  /// - `Downloads` / `Download` → `/storage/emulated/0/Download`
  /// - `Camera` → `/storage/emulated/0/DCIM/Camera`
  /// - `Imported` / empty / null → Download fallback
  /// - other → `/storage/emulated/0/<Folder>`
  static String publicRestoreDirForVaultFolder(String? folder) {
    if (folder == null || folder.trim().isEmpty) return defaultRestoreDir;
    final f = folder.trim();
    final lower = f.toLowerCase();
    if (lower == 'imported') return defaultRestoreDir;
    if (lower == 'download' || lower == 'downloads') {
      return '$publicStorageRoot/Download';
    }
    if (lower == 'camera') return '$publicStorageRoot/DCIM/Camera';
    return '$publicStorageRoot/$f';
  }

  /// Pure path resolution for unhide (no filesystem I/O).
  ///
  /// Preference order:
  /// 1. Non-empty [originalPath]
  /// 2. Legacy marker reverse of [privatePath]
  /// 3. Vault mirror folder → public folder + [originalName]
  /// 4. Download + [originalName]
  static String resolveUnhidePath({
    required String privatePath,
    String? originalPath,
    required String originalName,
  }) {
    final orig = originalPath?.trim() ?? '';
    if (orig.isNotEmpty) return orig;

    if (isLegacyMarkerPath(privatePath)) {
      return fromLegacyHiddenPath(privatePath);
    }

    final fileName = originalName.trim().isNotEmpty
        ? p.basename(originalName.trim())
        : p.basename(privatePath);

    if (isHiddenVaultPath(privatePath)) {
      final folder = vaultMirrorFolder(privatePath);
      return p.join(publicRestoreDirForVaultFolder(folder), fileName);
    }

    return p.join(defaultRestoreDir, fileName);
  }
}
