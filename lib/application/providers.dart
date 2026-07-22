import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_build_info.dart';
import '../core/utils/album_query_utils.dart';
import '../data/db/database.dart';
import '../data/repositories/album_repository.dart';
import '../data/repositories/media_repository.dart';
import '../data/services/biometric_service.dart';
import '../data/services/grid_thumbnail_service.dart';
import '../data/services/import/asset_gateway.dart';
import '../data/services/import/file_system_gateway.dart';
import '../data/services/import_service.dart';
import '../data/services/intent_service.dart';
import '../data/services/maintenance_service.dart';
import '../data/services/media_rename_service.dart';
import '../data/services/media_store_service.dart';
import '../data/services/media_thumbnail_service.dart';
import '../data/services/platform/android_privacy_shield_adapter.dart';
import '../data/services/platform/android_share_source_stager.dart';
import '../data/services/platform/android_vault_access_adapter.dart';
import '../data/services/platform/android_vault_workflow_adapter.dart';
import '../data/services/platform/android_visible_library_adapter.dart';
import '../data/services/platform/ios_photos_vault_workflow_adapter.dart';
import '../data/services/platform/ios_photos_visible_library_adapter.dart';
import '../data/services/platform/ios_privacy_shield_adapter.dart';
import '../data/services/platform/ios_share_source_stager.dart';
import '../data/services/platform/ios_vault_access_adapter.dart';
import '../data/services/platform/unsupported_external_player_gateway.dart';
import '../data/services/security_service.dart';
import '../data/services/thumbnail_cache.dart';
import '../data/services/vault_backup_service.dart';
import '../data/services/vault_storage_service.dart';
import '../domain/enums.dart';
import '../domain/models/album_view.dart';
import '../domain/models/group_view.dart';
import '../domain/models/media_item.dart';
import '../domain/models/shelf_entry.dart';
import 'gallery/gallery_controller.dart';
import 'media/album_list_preferences.dart';
import 'platform/privacy_shield.dart';
import 'platform/share_source_stager.dart';
import 'platform/vault_access.dart';
import 'platform/vault_workflow.dart';
import 'platform/visible_library.dart';
import 'player/external_player_gateway.dart';
import 'update/app_restart_service.dart';
import 'update/app_update_service.dart';
import 'update/external_url_launcher.dart';

/// Core DI graph. Manual providers for Phase 1 (codegen can replace later).

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

typedef VaultBackupDirectoryPicker = Future<String?> Function(
  String dialogTitle,
);

final vaultBackupDirectoryPickerProvider = Provider<VaultBackupDirectoryPicker>(
  (ref) => (dialogTitle) => FilePicker.platform.getDirectoryPath(
        dialogTitle: dialogTitle,
      ),
);

final appBuildInfoProvider = Provider<AppBuildInfo>((ref) {
  throw UnimplementedError('appBuildInfoProvider must be overridden');
});

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  throw UnimplementedError('appUpdateServiceProvider must be overridden');
});

final appRestartServiceProvider = Provider<AppRestartService>((ref) {
  throw UnimplementedError('appRestartServiceProvider must be overridden');
});

final externalUrlLauncherProvider = Provider<ExternalUrlLauncher>((ref) {
  throw UnimplementedError('externalUrlLauncherProvider must be overridden');
});

final externalPlayerGatewayProvider = Provider<ExternalPlayerGateway>((ref) {
  if (Platform.isIOS) return const UnsupportedExternalPlayerGateway();
  final gateway = MethodChannelExternalPlayerGateway();
  ref.onDispose(gateway.dispose);
  return gateway;
});

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final vaultStorageProvider = Provider<VaultStorageService>((ref) {
  return VaultStorageService(initializeSharedRoot: !Platform.isIOS);
});

final shareSourceStagerProvider = Provider<ShareSourceStager>((ref) {
  if (Platform.isIOS) {
    return IosShareSourceStager(storage: ref.watch(vaultStorageProvider));
  }
  return const AndroidShareSourceStager();
});

final securityServiceProvider = Provider<SecurityService>((ref) {
  return SecurityService();
});

final privacyShieldProvider = Provider<PrivacyShield>((ref) {
  if (Platform.isIOS) return IosPrivacyShieldAdapter();
  return AndroidPrivacyShieldAdapter();
});

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

final mediaStoreServiceProvider = Provider<MediaStoreService>((ref) {
  return MediaStoreService();
});

/// Shared-storage permission is an Android-only capability. Presentation code
/// uses this seam instead of constructing MediaRenameService directly.
final vaultAccessProvider = Provider<VaultAccess>((ref) {
  if (Platform.isIOS) return const IosVaultAccessAdapter();
  return AndroidVaultAccessAdapter(MediaRenameService());
});

final assetGatewayProvider = Provider<AssetGateway>((ref) {
  return const PhotoManagerAssetGateway();
});

/// Read-only system-library adapter selected once at the composition root.
final visibleLibraryProvider = Provider<VisibleLibrary>((ref) {
  final assets = ref.watch(assetGatewayProvider);
  if (Platform.isIOS) {
    return IosPhotosVisibleLibraryAdapter(assets: assets);
  }
  return AndroidVisibleLibraryAdapter(
    assets: assets,
    files: const IoFileSystemGateway(),
    mediaStore: ref.watch(mediaStoreServiceProvider),
  );
});

final mediaThumbnailCacheProvider = Provider<MediaThumbnailCache>((ref) {
  final cache = MediaThumbnailService(
    assetGateway: ref.watch(assetGatewayProvider),
  );
  ref.onDispose(cache.clear);
  return cache;
});

/// Unified mem+disk cache fronting both grids' thumbnail rendering.
final thumbnailCacheProvider = Provider<ThumbnailCache>((ref) {
  final cache = ThumbnailCache(
    cacheDir: () async {
      final tmp = await getTemporaryDirectory();
      return Directory(p.join(tmp.path, 'grid_thumbs'));
    },
  );
  ref.onDispose(cache.clearMemory);
  return cache;
});

/// Single producer both grids call — same cache, size, and representative
/// frame; only the byte source differs (asset vs. vault poster).
final gridThumbnailServiceProvider = Provider<GridThumbnailService>((ref) {
  return GridThumbnailService(
    cache: ref.watch(thumbnailCacheProvider),
    decodeAsset: (assetId, size) =>
        ref.read(galleryServiceProvider).decodeThumbnail(assetId, size),
    ensureVaultPoster: (item) =>
        ref.read(importServiceProvider).ensureThumbnail(item),
  );
});

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(
    ref.watch(databaseProvider),
    ref.watch(vaultStorageProvider),
  );
});

final albumRepositoryProvider = Provider<AlbumRepository>((ref) {
  return AlbumRepository(ref.watch(databaseProvider));
});

final vaultWorkflowProvider = Provider<VaultWorkflow>((ref) {
  final storage = ref.watch(vaultStorageProvider);
  final media = ref.watch(mediaRepositoryProvider);
  final albums = ref.watch(albumRepositoryProvider);
  if (Platform.isIOS) {
    return IosPhotosVaultWorkflowAdapter(
      storage: storage,
      media: media,
      albums: albums,
      thumbnailCache: ref.watch(mediaThumbnailCacheProvider),
    );
  }
  final android = ImportService(
    storage: storage,
    mediaRepository: media,
    albumRepository: albums,
    assetGateway: ref.watch(assetGatewayProvider),
    thumbnailCache: ref.watch(mediaThumbnailCacheProvider),
  );
  return AndroidVaultWorkflowAdapter(android);
});

/// Backward-compatible provider name used by existing controllers. The value
/// is the platform workflow, never an Android concrete implementation.
final importServiceProvider = Provider<VaultWorkflow>((ref) {
  return ref.watch(vaultWorkflowProvider);
});

final vaultBackupServiceProvider = Provider<VaultBackupOperations>((ref) {
  return VaultBackupService(
    db: ref.watch(databaseProvider),
    media: ref.watch(mediaRepositoryProvider),
    albums: ref.watch(albumRepositoryProvider),
    storage: ref.watch(vaultStorageProvider),
    usePrivateMediaStorage: Platform.isIOS,
  );
});

final maintenanceServiceProvider = Provider<MaintenanceService>((ref) {
  return MaintenanceService(
    db: ref.watch(databaseProvider),
    media: ref.watch(mediaRepositoryProvider),
    storage: ref.watch(vaultStorageProvider),
    albums: ref.watch(albumRepositoryProvider),
    import: ref.watch(importServiceProvider),
    sharedStorageEnabled: !Platform.isIOS,
  );
});

/// Total vault media bytes (active + recycle) for Settings.
final vaultSizeBytesProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(mediaRepositoryProvider).totalBytes();
});

/// Home album cards (system + user) with live counts/covers.
/// Respects the shared photo XOR video mode so Invisible matches Visible.
final albumsProvider = StreamProvider<List<AlbumView>>((ref) {
  final kind = ref.watch(mediaKindFilterProvider);
  final isVideo = kind == MediaKindFilter.video;
  return ref
      .watch(albumRepositoryProvider)
      .watchAlbumViewsReactive(isVideo: isVideo);
});

/// Home shelf derived from album facts and global album-list preferences.
final albumShelfProvider = Provider<AsyncValue<AlbumShelf>>((ref) {
  final albums = ref.watch(albumsProvider);
  final preferences = ref.watch(albumListPreferencesProvider);
  final repository = ref.watch(albumRepositoryProvider);
  return albums.whenData((views) {
    final groups = repository.groupSnapshot;
    final byGroup = <String, List<AlbumView>>{};
    for (final view in views) {
      final groupId = view.album.groupId;
      if (groupId != null) (byGroup[groupId] ??= []).add(view);
    }
    final groupViews = <GroupView>[];
    final visibleGroupViews = <GroupView>[];
    for (final group in groups) {
      final members = List<AlbumView>.of(byGroup[group.id] ?? const [])
        ..sort(
          (left, right) => AlbumQueryUtils.compare(
            left.album,
            right.album,
            sorts: const [AlbumSort.custom],
          ),
        );
      final totalCount =
          members.fold<int>(0, (sum, member) => sum + member.count);
      final cover = members.cast<AlbumView?>().firstWhere(
            (member) => member?.cover != null,
            orElse: () => null,
          );
      final groupView = GroupView(
        group: group,
        members: List.unmodifiable(members),
        totalCount: totalCount,
        maxRating: members.fold<int>(
          0,
          (max, member) =>
              member.album.rating > max ? member.album.rating : max,
        ),
        cover: cover,
      );
      groupViews.add(groupView);
      if (members.isEmpty || totalCount > 0) visibleGroupViews.add(groupView);
    }
    final entries = <ShelfEntry>[];
    for (final view in views) {
      if (!view.album.isSystem &&
          view.album.groupId == null &&
          view.count > 0) {
        entries.add(AlbumEntry(view));
      }
    }
    entries.addAll(visibleGroupViews.map(GroupEntry.new));
    entries.sort(
      (left, right) => AlbumQueryUtils.compareEntries(
        left,
        right,
        sorts: preferences.sorts,
      ),
    );
    final systemViews = views.where((view) => view.album.isSystem).toList();
    return AlbumShelf(
      systemViews: List.unmodifiable(systemViews),
      entries: List.unmodifiable(entries),
      groups: List.unmodifiable(groupViews),
    );
  });
});

/// Media stream for a given album id (system virtual or user).
final albumMediaProvider =
    StreamProvider.family<List<MediaItem>, String>((ref, albumId) {
  return ref.watch(mediaRepositoryProvider).watchForAlbum(albumId);
});
