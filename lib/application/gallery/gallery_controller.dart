import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../data/services/gallery_service.dart';
import '../../domain/enums.dart';
import '../providers.dart';
import '../settings/settings_controller.dart';

export '../../data/services/gallery_service.dart'
    show
        GalleryAsset,
        GalleryFolder,
        VisibleFilterChanged,
        VisibleHidden,
        VisiblePermissionChanged,
        VisibleRevealed;

final galleryServiceProvider = Provider<GalleryService>((ref) {
  final service = GalleryService(
    assetGateway: ref.watch(assetGatewayProvider),
    thumbnailCache: ref.watch(mediaThumbnailCacheProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Photo **or** Video mode only (no combined).
final mediaKindFilterProvider =
    NotifierProvider<MediaKindFilterController, MediaKindFilter>(
  MediaKindFilterController.new,
);

/// Shared photo XOR video mode for **Visible and Invisible**.
/// Backed by [settingsControllerProvider] so the last choice survives restarts.
class MediaKindFilterController extends Notifier<MediaKindFilter> {
  @override
  MediaKindFilter build() {
    // Keep in sync when prefs finish loading (or change elsewhere).
    ref.listen<AppSettings>(settingsControllerProvider, (prev, next) {
      if (state != next.mediaKindFilter) {
        state = next.mediaKindFilter;
      }
    });
    return ref.read(settingsControllerProvider).mediaKindFilter;
  }

  void set(MediaKindFilter f) {
    if (state == f) return;
    state = f;
    ref.read(galleryServiceProvider).apply(const VisibleFilterChanged());
    // ignore: discarded_futures
    ref.read(settingsControllerProvider.notifier).setMediaKindFilter(f);
  }

  /// Toggle between photos-only and videos-only (persisted).
  void toggle() {
    set(
      state == MediaKindFilter.image
          ? MediaKindFilter.video
          : MediaKindFilter.image,
    );
  }
}

/// A single mutation stream replaces caller-managed epoch bumping.
final galleryChangeProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.watch(galleryServiceProvider).changes;
});

/// Visible-tab folder list for current photo/video mode.
///
/// Uses MediaStore counts and the [VisibleLibraryState] mutation stream.
final galleryFoldersProvider =
    FutureProvider.autoDispose<List<GalleryFolder>>((ref) async {
  ref.watch(galleryChangeProvider);
  final filter = ref.watch(mediaKindFilterProvider);
  final gallery = ref.watch(galleryServiceProvider);
  final ok = await gallery.hasPermission();
  if (!ok) {
    final state = await gallery.requestPermission();
    if (!(state.isAuth || state.hasAccess)) {
      return const [];
    }
  }
  // Cold-start: subtract vault private paths so counts match after restart.
  // Cached until the Visible state receives a hide/reveal mutation.
  await gallery.ensureVaultHydrated(
    () => ref.read(mediaRepositoryProvider).listActiveOriginalPaths(),
  );
  return gallery.listFolders(filter);
});

/// Assets inside a gallery folder (metadata only; thumbs lazy).
final galleryAssetsProvider = FutureProvider.autoDispose
    .family<List<GalleryAsset>, String>((ref, pathId) async {
  ref.watch(galleryChangeProvider);
  final filter = ref.watch(mediaKindFilterProvider);
  final gallery = ref.watch(galleryServiceProvider);
  await gallery.ensureVaultHydrated(
    () => ref.read(mediaRepositoryProvider).listActiveOriginalPaths(),
  );
  return gallery.listAssets(pathId: pathId, filter: filter);
});

final galleryPermissionProvider =
    FutureProvider.autoDispose<PermissionState>((ref) {
  return ref.watch(galleryServiceProvider).permissionState();
});
