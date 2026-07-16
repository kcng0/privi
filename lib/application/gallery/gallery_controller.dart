import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../data/services/gallery_service.dart';
import '../../domain/enums.dart';
import '../providers.dart';
import '../settings/settings_controller.dart';

export '../../data/services/gallery_service.dart'
    show GalleryAsset, GalleryFolder;

final galleryServiceProvider = Provider<GalleryService>((ref) {
  return GalleryService();
});

/// Photo **or** Video mode only (no combined) — HD Smith style.
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

/// Bumped after hide so folder tiles rebuild even if Riverpod keeps prior data.
final galleryUiEpochProvider =
    NotifierProvider<GalleryUiEpoch, int>(GalleryUiEpoch.new);

class GalleryUiEpoch extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Visible-tab folder list for current photo/video mode.
///
/// Uses **fast** MediaStore counts + session hide deductions + vault-path
/// hydration (cold start). Pull-to-refresh still works via
/// [GalleryService.refreshAfterMutation].
final galleryFoldersProvider =
    FutureProvider.autoDispose<List<GalleryFolder>>((ref) async {
  ref.watch(galleryUiEpochProvider);
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
  try {
    final paths =
        await ref.read(mediaRepositoryProvider).listActivePrivatePaths();
    gallery.hydrateFromVaultPaths(paths);
  } catch (_) {
    // DB may not be ready in pure widget tests — ignore.
  }
  return gallery.listFolders(filter);
});

/// Assets inside a gallery folder (metadata only; thumbs lazy).
final galleryAssetsProvider = FutureProvider.autoDispose
    .family<List<GalleryAsset>, String>((ref, pathId) async {
  ref.watch(galleryUiEpochProvider);
  final filter = ref.watch(mediaKindFilterProvider);
  final gallery = ref.watch(galleryServiceProvider);
  try {
    final paths =
        await ref.read(mediaRepositoryProvider).listActivePrivatePaths();
    gallery.hydrateFromVaultPaths(paths);
  } catch (_) {}
  return gallery.listAssets(pathId: pathId, filter: filter);
});

final galleryPermissionProvider =
    FutureProvider.autoDispose<PermissionState>((ref) {
  return PhotoManager.getPermissionState(
    requestOption: const PermissionRequestOption(),
  );
});
