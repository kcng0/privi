import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import '../../core/media_thumbnail_spec.dart';
import '../../domain/enums.dart';
import 'hide_naming.dart';
import 'import/asset_gateway.dart';
import 'import/file_system_gateway.dart';
import 'import_service.dart';
import 'media_store_service.dart';
import 'media_thumbnail_service.dart';

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
    this.createDateMs,
  });

  final String id;
  final bool isVideo;
  final String title;
  final int? durationMs;

  /// Epoch ms from MediaStore (for client-side sort in Visible grids).
  final int? createDateMs;
}

sealed class VisibleMutation {
  const VisibleMutation();
}

class VisibleHidden extends VisibleMutation {
  const VisibleHidden({
    required this.pathId,
    required this.hiddenCount,
    this.assetIds = const [],
    this.originalPaths = const [],
  });

  final String pathId;
  final int hiddenCount;
  final List<String> assetIds;
  final List<String> originalPaths;
}

class VisibleRevealed extends VisibleMutation {
  const VisibleRevealed();
}

class VisibleFilterChanged extends VisibleMutation {
  const VisibleFilterChanged();
}

class VisiblePermissionChanged extends VisibleMutation {
  const VisiblePermissionChanged();
}

class VisibleLibrarySnapshot {
  const VisibleLibrarySnapshot({
    required this.folders,
    required this.isExcluded,
  });

  final List<GalleryFolder> folders;
  final bool Function(AssetEntity asset) isExcluded;
}

/// Single owner for Visible-library caches, exclusions, and mutations.
class VisibleLibraryState {
  final Map<MediaKindFilter, List<AssetPathEntity>> _pathCache = {};
  DateTime? _pathCacheAt;
  final Set<String> _affectedPathIds = {};
  final Map<String, int> _coverEpoch = {};
  final Set<String> _hiddenAssetIds = {};
  final Set<String> _hiddenOriginalKeys = {};
  bool _vaultHydrated = false;
  List<GalleryFolder> _folders = const [];
  MediaKindFilter? _foldersFilter;

  final _changes = StreamController<int>.broadcast();
  int _version = 0;

  Stream<int> get changes => _changes.stream;

  void dispose() => _changes.close();

  void apply(VisibleMutation mutation) {
    switch (mutation) {
      case VisibleHidden():
        _applyHidden(mutation);
      case VisibleRevealed():
        _affectedPathIds.clear();
        _hiddenAssetIds.clear();
        _hiddenOriginalKeys.clear();
        _vaultHydrated = false;
        _folders = const [];
        _foldersFilter = null;
        invalidatePaths(notify: false);
      case VisibleFilterChanged() || VisiblePermissionChanged():
        _folders = const [];
        _foldersFilter = null;
        invalidatePaths(notify: false);
    }
    _notify();
  }

  void _applyHidden(VisibleHidden mutation) {
    if (mutation.hiddenCount <= 0) return;
    if (mutation.pathId.isNotEmpty) _affectedPathIds.add(mutation.pathId);
    _coverEpoch[mutation.pathId] = (_coverEpoch[mutation.pathId] ?? 0) + 1;
    _hiddenAssetIds.addAll(mutation.assetIds);
    _hiddenOriginalKeys.addAll(
      mutation.originalPaths.map(originalPathKey).whereType<String>(),
    );

    _folders = [
      for (final folder in _folders)
        if (folder.id == mutation.pathId)
          folder.copyWith(
            count: math.max(0, folder.count - mutation.hiddenCount),
            coverEpoch: _coverEpoch[folder.id] ?? folder.coverEpoch,
          )
        else
          folder,
    ].where((folder) => folder.count > 0).toList(growable: false);
  }

  void hydrateOriginalPaths(Iterable<String> paths) {
    _hiddenOriginalKeys
      ..clear()
      ..addAll(paths.map(originalPathKey).whereType<String>());
    _vaultHydrated = true;
    _notify();
  }

  void setFolders(MediaKindFilter filter, List<GalleryFolder> value) {
    _foldersFilter = filter;
    _folders = List.unmodifiable(value);
  }

  void reconcileCount(String pathId, int visibleCount) {
    _folders = [
      for (final folder in _folders)
        if (folder.id == pathId)
          folder.copyWith(
            count: visibleCount,
            coverEpoch: _coverEpoch[pathId] ?? folder.coverEpoch,
          )
        else
          folder,
    ].where((folder) => folder.count > 0).toList(growable: false);
    _notify();
  }

  VisibleLibrarySnapshot snapshot(MediaKindFilter filter) {
    final assetIds = Set<String>.unmodifiable(_hiddenAssetIds);
    final originalKeys = Set<String>.unmodifiable(_hiddenOriginalKeys);
    final hydrated = _vaultHydrated;
    return VisibleLibrarySnapshot(
      folders: _foldersFilter == filter
          ? List<GalleryFolder>.unmodifiable(_folders)
          : const [],
      isExcluded: (asset) {
        if (assetIds.contains(asset.id) ||
            GalleryService.isHiddenAsset(asset)) {
          return true;
        }
        if (!hydrated) return false;
        final key = assetKey(asset.relativePath, asset.title);
        return key != null && originalKeys.contains(key);
      },
    );
  }

  bool isExcluded(AssetEntity asset) {
    return isExcludedKey(
      assetId: asset.id,
      relativePath: asset.relativePath,
      title: asset.title,
      hasHiddenMarker: GalleryService.isHiddenAsset(asset),
    );
  }

  @visibleForTesting
  bool isExcludedKey({
    required String assetId,
    required String? relativePath,
    required String? title,
    bool hasHiddenMarker = false,
  }) {
    if (_hiddenAssetIds.contains(assetId) || hasHiddenMarker) return true;
    if (!_vaultHydrated) return false;
    final key = assetKey(relativePath, title);
    return key != null && _hiddenOriginalKeys.contains(key);
  }

  void invalidatePaths({bool notify = true}) {
    _pathCache.clear();
    _pathCacheAt = null;
    if (notify) _notify();
  }

  void _notify() => _changes.add(++_version);

  static String? assetKey(String? relativePath, String? title) {
    if (relativePath == null || title == null || title.isEmpty) return null;
    final rel = _normalize(relativePath).replaceAll(RegExp(r'^/+|/+$'), '');
    if (rel.isEmpty) return null;
    return '${rel.toLowerCase()}/${title.toLowerCase()}';
  }

  static String? originalPathKey(String path) {
    var normalized = _normalize(path.trim());
    if (normalized.isEmpty) return null;
    for (final prefix in const ['/storage/emulated/0/', '/sdcard/']) {
      if (normalized.toLowerCase().startsWith(prefix)) {
        normalized = normalized.substring(prefix.length);
        break;
      }
    }
    final directory = p.dirname(normalized).replaceAll(RegExp(r'^/+|/+$'), '');
    final name = p.basename(normalized);
    if (directory.isEmpty || name.isEmpty) return null;
    return '${directory.toLowerCase()}/${name.toLowerCase()}';
  }

  static String _normalize(String path) => path.replaceAll('\\', '/');
}

class GalleryService {
  GalleryService({
    AssetGateway? assetGateway,
    MediaThumbnailCache? thumbnailCache,
    FileSystemGateway? fileSystem,
    MediaStoreService? mediaStore,
    VisibleLibraryState? visibleState,
  })  : _assets = assetGateway ?? const PhotoManagerAssetGateway(),
        _thumbnails = thumbnailCache ??
            MediaThumbnailService(
              assetGateway: assetGateway ?? const PhotoManagerAssetGateway(),
            ),
        _ownsThumbnailCache = thumbnailCache == null,
        _files = fileSystem ?? const IoFileSystemGateway(),
        _mediaStore = mediaStore ?? MediaStoreService(),
        _visibleState = visibleState ?? VisibleLibraryState();

  final AssetGateway _assets;
  final MediaThumbnailCache _thumbnails;
  final bool _ownsThumbnailCache;
  final FileSystemGateway _files;
  final MediaStoreService _mediaStore;
  final VisibleLibraryState _visibleState;

  static const _cacheTtl = Duration(seconds: 45);

  Stream<int> get changes => _visibleState.changes;

  void dispose() {
    if (_ownsThumbnailCache) _thumbnails.clear();
    _visibleState.dispose();
  }

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
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      );

  /// Loads the canonical poster used before and after a hide operation.
  Future<Uint8List?> mediaThumbnail(String assetId) =>
      _thumbnails.load(assetId);

  /// Decodes a fresh Visible poster at [size] (representative frame), bypassing
  /// the 768 hide-reuse cache. The unified grid cache owns caching.
  Future<Uint8List?> decodeThumbnail(String assetId, int size) =>
      _assets.thumbnailBytes(
        assetId,
        size: size,
        quality: MediaThumbnailSpec.quality,
        frameUs: MediaThumbnailSpec.videoFrameUs,
      );

  Future<PermissionState> requestPermission() {
    return PhotoManager.requestPermissionExtend();
  }

  Future<bool> hasPermission() async {
    final s = await permissionState();
    return s.isAuth || s.hasAccess;
  }

  Future<PermissionState> permissionState() {
    return PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(),
    );
  }

  Future<void> clearFileCache() => _assets.clearFileCache();

  /// Hydrate once per process until a reveal or permission/filter mutation.
  Future<void> ensureVaultHydrated(
    Future<List<String>> Function() loadPaths,
  ) async {
    if (_visibleState._vaultHydrated) return;
    hydrateFromVaultPaths(await loadPaths());
  }

  /// Seed deductions from vault DB paths so Visible counts stay correct after
  /// cold start (session deductions alone only cover hides in this process).
  void hydrateFromVaultPaths(Iterable<String> originalPaths) {
    _visibleState.hydrateOriginalPaths(originalPaths);
  }

  void apply(VisibleMutation mutation) => _visibleState.apply(mutation);

  VisibleLibrarySnapshot snapshot(MediaKindFilter filter) =>
      _visibleState.snapshot(filter);

  /// Apply an optimistic hide, then reconcile the affected folder precisely.
  Future<void> recordHidden({
    required String pathId,
    required int hiddenCount,
    required MediaKindFilter filter,
    List<String> assetIds = const [],
    List<String> originalPaths = const [],
  }) async {
    _visibleState.apply(
      VisibleHidden(
        pathId: pathId,
        hiddenCount: hiddenCount,
        assetIds: assetIds,
        originalPaths: originalPaths,
      ),
    );
    _visibleState.invalidatePaths();
    for (final assetId in assetIds) {
      _thumbnails.evict(assetId);
    }
    final count = await recountVisible(pathId: pathId, filter: filter);
    _visibleState.reconcileCount(pathId, count);
  }

  Future<List<AssetPathEntity>> _paths(
    MediaKindFilter filter, {
    bool force = false,
  }) async {
    final now = DateTime.now();
    final cached = _visibleState._pathCache[filter];
    if (!force &&
        cached != null &&
        _visibleState._pathCacheAt != null &&
        now.difference(_visibleState._pathCacheAt!) < _cacheTtl) {
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
    _visibleState._pathCache[filter] = list;
    _visibleState._pathCacheAt = now;
    return list;
  }

  static bool isHiddenAsset(AssetEntity a) {
    final title = a.title ?? '';
    if (HideNaming.isHiddenPath(title)) return true;
    final rel = a.relativePath ?? '';
    if (rel.isNotEmpty && HideNaming.isHiddenPath(rel)) return true;
    return false;
  }

  bool _isExcluded(AssetEntity a) {
    return _visibleState.isExcluded(a);
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

  /// Fast folder list based on MediaStore counts and reconciled session state.
  Future<List<GalleryFolder>> listFolders(MediaKindFilter filter) async {
    final paths = await _paths(filter);
    final rawCounts =
        await Future.wait(paths.map((path) => path.assetCountAsync));

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
      final count = _visibleState._affectedPathIds.contains(path.id)
          ? await recountVisible(pathId: path.id, filter: filter)
          : raw;
      if (count <= 0) continue;
      folders.add(
        GalleryFolder(
          id: path.id,
          name: folderName,
          count: count,
          isAll: false,
          coverEpoch: _visibleState._coverEpoch[path.id] ?? 0,
        ),
      );
    }

    folders.sort((a, b) {
      if (a.isAll != b.isAll) return a.isAll ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    _visibleState.setFolders(filter, folders);
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
    if (total <= 0) return 0;

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
          final bytes = await mediaThumbnail(a.id);
          if (bytes != null) return bytes;
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
          createDateMs: (a.createDateSecond ?? 0) * 1000,
        ),
      );
      if (out.length >= size) break;
    }
    return out;
  }

  Future<AssetEntity?> entity(String id) => AssetEntity.fromId(id);

  /// Resolve real filesystem paths for hide (not app-cache exports).
  Future<List<ImportSource>> resolveForHide(
    List<String> assetIds, {
    String? sourceFolderName,
  }) async {
    if (assetIds.isEmpty) return const [];
    const concurrency = 6;
    final out = <ImportSource?>[];

    Future<ImportSource?> one(String id) async {
      try {
        final info = await _assets.info(id).timeout(const Duration(seconds: 3));
        if (info == null) return null;

        final isVideo = info.isVideo;
        final mime = info.mimeType ?? (isVideo ? 'video/mp4' : 'image/jpeg');

        // Prefer native MediaStore DATA path (fast, no full file open).
        final String? absPath =
            await _mediaStore.resolveMediaPath(id: id, isVideo: isVideo);

        String? resolvedPath;
        if (absPath != null &&
            absPath.isNotEmpty &&
            await _files.exists(absPath)) {
          resolvedPath = absPath;
        } else {
          // Short timeouts — skip rather than stall the batch.
          try {
            resolvedPath = (await _assets
                    .entityFile(id)
                    .timeout(const Duration(seconds: 4)))
                ?.path;
          } catch (e) {
            debugPrint('entity.file timeout/fail $id: $e');
          }
          if (resolvedPath == null || !await _files.exists(resolvedPath)) {
            try {
              resolvedPath = (await _assets
                      .originFile(id)
                      .timeout(const Duration(seconds: 6)))
                  ?.path;
            } catch (e) {
              debugPrint('originFile fail $id: $e');
            }
          }
        }
        if (resolvedPath == null || !await _files.exists(resolvedPath)) {
          return null;
        }
        if (resolvedPath.startsWith('content:')) return null;
        final path = resolvedPath;
        final lower = path.toLowerCase();
        if (lower.contains('/cache/') ||
            lower.contains('/.thumbnails/') ||
            lower.contains('/android/data/') ||
            lower.contains('/app_flutter/')) {
          debugPrint('PH_HIDE reject path $path');
          return null;
        }

        var folder = sourceFolderName?.trim();
        if (folder == null || folder.isEmpty) {
          final rel = info.relativePath;
          if (rel != null && rel.isNotEmpty) {
            final parts = rel
                .replaceAll('\\', '/')
                .split('/')
                .where((s) => s.isNotEmpty)
                .toList();
            folder = parts.isNotEmpty ? parts.last : null;
          }
        }
        folder ??= p.basename(p.dirname(path));
        if (folder.isEmpty) folder = 'Imported';
        if (folder.toLowerCase() == 'download') folder = 'Downloads';

        // Capture/create time only — never modified time (hide/unhide must not
        // reshuffle "Newest first" vs system Gallery).
        DateTime? dateTaken;
        final createSec = await _assets.createDateSecond(id);
        if (createSec != null && createSec > 0) {
          dateTaken = DateTime.fromMillisecondsSinceEpoch(
            createSec * 1000,
            isUtc: true,
          );
        }
        // Prefer native DATE_TAKEN / EXIF when photo_manager create is missing.
        if (dateTaken == null) {
          try {
            final sec = await _mediaStore.resolveCaptureDateSec(
              path: path,
              mediaId: id,
              isVideo: isVideo,
            );
            if (sec != null && sec > 0) {
              dateTaken = DateTime.fromMillisecondsSinceEpoch(
                sec * 1000,
                isUtc: true,
              );
            }
          } catch (error, stackTrace) {
            debugPrint('resolve capture date $id: $error\n$stackTrace');
          }
        }

        return ImportSource(
          path: path,
          name: info.title ?? p.basename(path),
          mimeType: mime,
          assetId: id,
          sourceFolderName: folder,
          dateTaken: dateTaken,
        );
      } catch (e) {
        debugPrint('resolve $id: $e');
        return null;
      }
    }

    // Bounded parallelism keeps MediaStore responsive.
    for (var i = 0; i < assetIds.length; i += concurrency) {
      final chunk = assetIds.sublist(
        i,
        i + concurrency > assetIds.length ? assetIds.length : i + concurrency,
      );
      final part = await Future.wait(chunk.map(one));
      out.addAll(part);
    }
    return [
      for (final s in out)
        if (s != null) s,
    ];
  }
}
