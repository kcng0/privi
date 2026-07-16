import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import '../../domain/enums.dart';
import 'hide_naming.dart';
import 'import_service.dart';
import 'media_store_service.dart';

class GalleryFolder {
  const GalleryFolder({
    required this.id,
    required this.name,
    required this.count,
    this.isAll = false,
    this.coverEpoch = 0,
  });

  final String id;
  final String name;
  final int count;
  final bool isAll;

  /// Bumped when cover must reload even if [count] is unchanged.
  final int coverEpoch;

  GalleryFolder copyWith({
    String? id,
    String? name,
    int? count,
    bool? isAll,
    int? coverEpoch,
  }) {
    return GalleryFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      count: count ?? this.count,
      isAll: isAll ?? this.isAll,
      coverEpoch: coverEpoch ?? this.coverEpoch,
    );
  }
}

class GalleryAsset {
  const GalleryAsset({
    required this.id,
    required this.isVideo,
    required this.title,
    this.durationMs,
  });

  final String id;
  final bool isVideo;
  final String title;
  final int? durationMs;
}

class GalleryService {
  final Map<MediaKindFilter, List<AssetPathEntity>> _pathCache = {};
  DateTime? _pathCacheAt;
  static const _cacheTtl = Duration(seconds: 45);

  /// Session deductions after hide (MediaStore still lists rename-hidden files).
  final Map<String, int> _hiddenDeduction = {};

  /// Force cover reload after hide for a path.
  final Map<String, int> _coverEpoch = {};

  /// Asset ids hidden this session (fast filter for asset grids).
  final Set<String> _hiddenAssetIds = {};

  /// Absolute paths already in the vault (cold-start count hydration).
  final Set<String> _vaultHiddenPaths = {};

  /// Basenames of vault hidden files for O(1) asset title filtering.
  final Set<String> _vaultHiddenBasenames = {};

  bool _vaultHydrated = false;

  /// Last fast folder snapshot (for optimistic patches without full I/O).
  List<GalleryFolder>? _lastFolders;
  MediaKindFilter? _lastFoldersFilter;

  RequestType _requestType(MediaKindFilter filter) {
    return switch (filter) {
      MediaKindFilter.image => RequestType.image,
      MediaKindFilter.video => RequestType.video,
    };
  }

  FilterOptionGroup get _filterOptions => FilterOptionGroup(
        imageOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        videoOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        orders: [
          const OrderOption(type: OrderOptionType.updateDate, asc: false),
        ],
      );

  Future<PermissionState> requestPermission() {
    return PhotoManager.requestPermissionExtend();
  }

  Future<bool> hasPermission() async {
    final s = await PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(),
    );
    return s.isAuth || s.hasAccess;
  }

  void invalidateCache() {
    _pathCache.clear();
    _pathCacheAt = null;
  }

  /// Lightweight cache drop only — no multi-second MediaStore sweeps.
  void refreshAfterMutation() {
    invalidateCache();
  }

  /// Seed deductions from vault DB paths so Visible counts stay correct after
  /// cold start (session deductions alone only cover hides in this process).
  void hydrateFromVaultPaths(Iterable<String> privatePaths) {
    _vaultHiddenPaths.clear();
    _vaultHiddenBasenames.clear();
    for (final raw in privatePaths) {
      final path = raw.trim();
      if (path.isEmpty) continue;
      final norm = _normalizePath(path);
      _vaultHiddenPaths.add(norm);
      _vaultHiddenBasenames.add(p.basename(norm));
    }
    _vaultHydrated = true;
  }

  static String _normalizePath(String path) {
    // Android paths may differ by trailing slash / case of volume root.
    var s = path.replaceAll('\\', '/');
    if (s.length > 1 && s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }

  /// Instant UI update after a successful hide (no library-wide scan).
  ///
  /// Rename-hide leaves the file in MediaStore under a new name, so raw album
  /// counts do not drop. We deduct [hiddenCount] from [pathId] and the "All"
  /// album, bump cover epoch, and remember asset ids for the media grid.
  List<GalleryFolder>? noteHidden({
    required String pathId,
    required int hiddenCount,
    List<String> assetIds = const [],
  }) {
    if (hiddenCount <= 0) return _lastFolders;
    _hiddenDeduction[pathId] = (_hiddenDeduction[pathId] ?? 0) + hiddenCount;
    _coverEpoch[pathId] = (_coverEpoch[pathId] ?? 0) + 1;
    _hiddenAssetIds.addAll(assetIds);

    if (_lastFolders == null) return null;

    String? allId;
    for (final f in _lastFolders!) {
      if (f.isAll) {
        allId = f.id;
        break;
      }
    }
    if (allId != null && allId != pathId) {
      _hiddenDeduction[allId] = (_hiddenDeduction[allId] ?? 0) + hiddenCount;
      _coverEpoch[allId] = (_coverEpoch[allId] ?? 0) + 1;
    }

    _lastFolders = [
      for (final f in _lastFolders!)
        if (f.id == pathId || f.id == allId)
          f.copyWith(
            count: math.max(0, f.count - hiddenCount),
            coverEpoch: _coverEpoch[f.id] ?? f.coverEpoch,
          )
        else
          f,
    ]
        // Drop empty folders (except keep All if it still has items).
        .where((f) => f.count > 0)
        .toList();

    return _lastFolders;
  }

  Future<List<AssetPathEntity>> _paths(
    MediaKindFilter filter, {
    bool force = false,
  }) async {
    final now = DateTime.now();
    final cached = _pathCache[filter];
    if (!force &&
        cached != null &&
        _pathCacheAt != null &&
        now.difference(_pathCacheAt!) < _cacheTtl) {
      return cached;
    }
    // hasAll: false — do not request the virtual Recent/All album at all.
    // Visible is real device folders only (Camera, Screenshots, Downloads…).
    final list = await PhotoManager.getAssetPathList(
      type: _requestType(filter),
      hasAll: false,
      onlyAll: false,
      filterOption: _filterOptions,
    );
    _pathCache[filter] = list;
    _pathCacheAt = now;
    return list;
  }

  static bool _isHiddenAsset(AssetEntity a) {
    final title = a.title ?? '';
    if (HideNaming.isHiddenPath(title)) return true;
    final rel = a.relativePath ?? '';
    if (rel.isNotEmpty && HideNaming.isHiddenPath(rel)) return true;
    return false;
  }

  bool _isExcluded(AssetEntity a) {
    if (_hiddenAssetIds.contains(a.id)) return true;
    if (_isHiddenAsset(a)) return true;
    if (_vaultHydrated && _vaultHiddenBasenames.isNotEmpty) {
      final title = a.title;
      if (title != null &&
          title.isNotEmpty &&
          _vaultHiddenBasenames.contains(title)) {
        return true;
      }
    }
    return false;
  }

  /// Virtual/system albums we never show in Visible (real folders only).
  ///
  /// Covers OEM/locale labels for MediaStore's virtual "Recent" / "All" album.
  /// [AssetPathEntity.isAll] is also excluded in [listFolders] — on many devices
  /// that album is named "Recent", and the old `!path.isAll &&` guard left it visible.
  static bool _isExcludedFolderName(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return true;
    // English + common OEM / locale labels for "Recent" and virtual "All".
    const blocked = {
      'recent',
      'recents',
      'recently added',
      'recent photos',
      'recent videos',
      'all',
      'all photos',
      'all videos',
      'all media',
      'all images',
      'camera roll',
      '最近',
      '最近项目',
      '最近新增',
      '最近添加',
      '最近的项目',
      '最新項目',
      '最新项目',
      '全部',
      '所有照片',
      '所有视频',
      '所有相片',
    };
    if (blocked.contains(n)) return true;
    if (n.startsWith('recent')) return true;
    return false;
  }

  /// Fast folder list: MediaStore counts minus session hide deductions and a
  /// vault-path heuristic (count of vault files whose parent folder name matches).
  /// Avoids paging every asset in every album (that made hide "Refreshing…" lag).
  Future<List<GalleryFolder>> listFolders(MediaKindFilter filter) async {
    final paths = await _paths(filter);
    final rawCounts =
        await Future.wait(paths.map((path) => path.assetCountAsync));

    // Map folder display name → vault-hidden file count (best-effort cold start).
    final vaultByFolder = <String, int>{};
    for (final vp in _vaultHiddenPaths) {
      final parent = p.basename(p.dirname(vp)).toLowerCase();
      if (parent.isEmpty) continue;
      vaultByFolder[parent] = (vaultByFolder[parent] ?? 0) + 1;
    }

    final folders = <GalleryFolder>[];
    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      final folderName = path.name.isEmpty ? 'Album' : path.name;
      // Never list virtual All/Recent albums — by flag or by display name.
      // Previously `!path.isAll &&` exempted the isAll album, so devices that
      // name it "Recent" still showed it on the Visible tab.
      if (path.isAll || _isExcludedFolderName(folderName)) {
        continue;
      }
      final raw = rawCounts[i];
      final session = _hiddenDeduction[path.id] ?? 0;
      // Prefer explicit session deduction; otherwise use vault path heuristic.
      var deduct = session;
      if (session == 0 && _vaultHydrated) {
        final key = folderName.toLowerCase();
        deduct = vaultByFolder[key] ?? 0;
        // Common alias: MediaStore "Download" vs vault "Downloads".
        if (deduct == 0 && key == 'download') {
          deduct = vaultByFolder['downloads'] ?? 0;
        } else if (deduct == 0 && key == 'downloads') {
          deduct = vaultByFolder['download'] ?? 0;
        }
      }
      final count = math.max(0, raw - deduct);
      if (count <= 0) continue;
      folders.add(
        GalleryFolder(
          id: path.id,
          name: folderName,
          count: count,
          isAll: false,
          coverEpoch: _coverEpoch[path.id] ?? 0,
        ),
      );
    }

    folders.sort((a, b) {
      if (a.isAll != b.isAll) return a.isAll ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    _lastFolders = folders;
    _lastFoldersFilter = filter;
    return folders;
  }

  /// Optional: accurate visible count for one folder (pull-to-refresh / open).
  /// Only scans that album — not the whole library.
  Future<int> recountVisible({
    required String pathId,
    required MediaKindFilter filter,
  }) async {
    final paths = await _paths(filter);
    AssetPathEntity? path;
    for (final pth in paths) {
      if (pth.id == pathId) {
        path = pth;
        break;
      }
    }
    if (path == null) return 0;

    final total = await path.assetCountAsync;
    if (total <= 0) {
      _hiddenDeduction[pathId] = 0;
      return 0;
    }

    var visible = 0;
    const pageSize = 100;
    var page = 0;
    var seen = 0;
    while (seen < total) {
      final assets = await path.getAssetListPaged(page: page, size: pageSize);
      if (assets.isEmpty) break;
      for (final a in assets) {
        if (!_isExcluded(a)) visible++;
      }
      seen += assets.length;
      if (assets.length < pageSize) break;
      page++;
    }

    // Align session deduction with MediaStore so fast counts stay correct.
    _hiddenDeduction[pathId] = math.max(0, total - visible);
    return visible;
  }

  Future<Uint8List?> folderCover({
    required String pathId,
    required MediaKindFilter filter,
  }) async {
    try {
      final paths = await _paths(filter);
      AssetPathEntity? path;
      for (final pth in paths) {
        if (pth.id == pathId) {
          path = pth;
          break;
        }
      }
      if (path == null) return null;
      const pageSize = 24;
      for (var page = 0; page < 8; page++) {
        final assets = await path.getAssetListPaged(page: page, size: pageSize);
        if (assets.isEmpty) return null;
        for (final a in assets) {
          if (_isExcluded(a)) continue;
          return a.thumbnailDataWithSize(
            const ThumbnailSize.square(160),
            quality: 70,
          );
        }
        if (assets.length < pageSize) break;
      }
      return null;
    } catch (e) {
      debugPrint('folderCover: $e');
      return null;
    }
  }

  Future<List<GalleryAsset>> listAssets({
    required String pathId,
    required MediaKindFilter filter,
    int page = 0,
    int size = 120,
  }) async {
    final paths = await _paths(filter);
    AssetPathEntity? path;
    for (final pth in paths) {
      if (pth.id == pathId) {
        path = pth;
        break;
      }
    }
    if (path == null) return const [];

    // Over-fetch a bit so filtering hidden items still fills a page.
    final fetchSize = size + 40;
    final assets = await path.getAssetListPaged(page: page, size: fetchSize);
    final out = <GalleryAsset>[];
    for (final a in assets) {
      if (_isExcluded(a)) continue;
      final title = a.title ?? a.id;
      out.add(
        GalleryAsset(
          id: a.id,
          isVideo: a.type == AssetType.video,
          title: title,
          durationMs: a.type == AssetType.video ? a.duration * 1000 : null,
        ),
      );
      if (out.length >= size) break;
    }
    return out;
  }

  Future<AssetEntity?> entity(String id) => AssetEntity.fromId(id);

  List<GalleryFolder>? get cachedFolders =>
      _lastFoldersFilter == null ? null : _lastFolders;

  /// Resolve real filesystem paths for hide (not app-cache exports).
  Future<List<ImportSource>> resolveForHide(
    List<String> assetIds, {
    String? sourceFolderName,
  }) async {
    final sources = <ImportSource>[];
    final store = MediaStoreService();
    for (final id in assetIds) {
      try {
        final entity =
            await AssetEntity.fromId(id).timeout(const Duration(seconds: 5));
        if (entity == null) continue;

        final isVideo = entity.type == AssetType.video;
        final mime = entity.mimeType ?? (isVideo ? 'video/mp4' : 'image/jpeg');

        // 1) MediaStore DATA column via native (true path under DCIM/Pictures/…).
        final String? absPath =
            await store.resolveMediaPath(id: id, isVideo: isVideo);

        // 2) Fallbacks: entity.file / originFile — reject obvious cache paths.
        File? file;
        if (absPath != null &&
            absPath.isNotEmpty &&
            File(absPath).existsSync()) {
          file = File(absPath);
        } else {
          try {
            file = await entity.file.timeout(const Duration(seconds: 12));
          } catch (e) {
            debugPrint('entity.file timeout/fail $id: $e');
          }
          if (file == null || !await file.exists()) {
            try {
              file =
                  await entity.originFile.timeout(const Duration(seconds: 20));
            } catch (e) {
              debugPrint('originFile fail $id: $e');
            }
          }
        }
        if (file == null || !await file.exists()) continue;
        if (file.path.startsWith('content:')) continue;
        final path = file.path;
        // Cache / app-private exports cannot be "hidden" from Gallery (original remains).
        final lower = path.toLowerCase();
        if (lower.contains('/cache/') ||
            lower.contains('/.thumbnails/') ||
            lower.contains('/android/data/') ||
            lower.contains('/app_flutter/')) {
          debugPrint('PH_HIDE reject path $path');
          continue;
        }

        var folder = sourceFolderName?.trim();
        if (folder == null || folder.isEmpty) {
          final rel = entity.relativePath;
          if (rel != null && rel.isNotEmpty) {
            final parts = rel
                .replaceAll('\\', '/')
                .split('/')
                .where((s) => s.isNotEmpty)
                .toList();
            folder = parts.isNotEmpty ? parts.last : null;
          }
        }
        folder ??= p.basename(p.dirname(file.path));
        if (folder.isEmpty) folder = 'Imported';
        if (folder.toLowerCase() == 'download') folder = 'Downloads';

        sources.add(
          ImportSource(
            path: file.path,
            name: entity.title ?? p.basename(file.path),
            mimeType: mime,
            assetId: id,
            sourceFolderName: folder,
          ),
        );
      } catch (e) {
        debugPrint('resolve $id: $e');
      }
    }
    return sources;
  }
}
