import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../application/gallery/gallery_controller.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../domain/enums.dart';
import 'folder_cover_cache.dart';
import 'visible_media_grid.dart';

export 'folder_cover_cache.dart';

/// dense gallery **Visible** tab: system Gallery folders (photo mode XOR video mode).
class VisibleFolderGrid extends ConsumerWidget {
  const VisibleFolderGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perm = ref.watch(galleryPermissionProvider);
    final folders = ref.watch(galleryFoldersProvider);
    final filter = ref.watch(mediaKindFilterProvider);
    // Same Style setting as Invisible home mosaic (home ⋮ → Style).
    final cols = ref.watch(settingsControllerProvider).albumColumns;

    return perm.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _PermError(
        message: '$e',
        onRetry: () {
          ref.invalidate(galleryPermissionProvider);
          ref.invalidate(galleryFoldersProvider);
        },
      ),
      data: (state) {
        if (!(state.isAuth || state.hasAccess)) {
          return _PermDenied(
            onRequest: () async {
              await PhotoManager.openSetting();
              ref.invalidate(galleryPermissionProvider);
              ref.invalidate(galleryFoldersProvider);
            },
            onRetry: () async {
              await ref.read(galleryServiceProvider).requestPermission();
              ref.invalidate(galleryPermissionProvider);
              ref.invalidate(galleryFoldersProvider);
            },
          );
        }

        return folders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load gallery: $e')),
          data: (list) {
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: AppSpacing.screen,
                  child: Text(
                    filter == MediaKindFilter.video
                        ? 'No video folders found'
                        : 'No photo folders found',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ),
              );
            }

            return RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: () async {
                FolderCoverCache.clear();
                final gallery = ref.read(galleryServiceProvider);
                gallery.refreshAfterMutation();
                // Accurate recount per folder (single-album scans) so counts
                // match after cold-start vault hydration + rename hides.
                try {
                  final paths = await ref
                      .read(mediaRepositoryProvider)
                      .listActivePrivatePaths();
                  gallery.hydrateFromVaultPaths(paths);
                } catch (_) {}
                final current = list;
                for (final f in current) {
                  try {
                    await gallery.recountVisible(
                      pathId: f.id,
                      filter: filter,
                    );
                  } catch (_) {}
                }
                ref.read(galleryUiEpochProvider.notifier).bump();
                ref.invalidate(galleryFoldersProvider);
                await ref.read(galleryFoldersProvider.future);
              },
              child: GridView.builder(
                padding: EdgeInsets.fromLTRB(
                  GridDefaults.gutter,
                  GridDefaults.gutter,
                  GridDefaults.gutter,
                  GridDefaults.bottomClearance +
                      MediaQuery.paddingOf(context).bottom,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: GridDefaults.gutter,
                  crossAxisSpacing: GridDefaults.gutter,
                  childAspectRatio: 1,
                ),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final f = list[i];
                  return _FolderTile(
                    folder: f,
                    filter: filter,
                    onTap: () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => VisibleMediaGrid(
                            pathId: f.id,
                            title: f.name,
                          ),
                        ),
                      );
                      // Back from folder: ensure list reflects any hide work
                      // (optimistic path already updated; cheap re-list).
                      if (context.mounted) {
                        ref.invalidate(galleryFoldersProvider);
                      }
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _FolderTile extends ConsumerWidget {
  const _FolderTile({
    required this.folder,
    required this.filter,
    required this.onTap,
  });

  final GalleryFolder folder;
  final MediaKindFilter filter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: const Color(0xFF1B3A36),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Lazy cover — reloads when count or coverEpoch changes after hide.
            _LazyFolderCover(
              pathId: folder.id,
              filter: filter,
              contentVersion: Object.hash(folder.count, folder.coverEpoch),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 44,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${folder.count}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              right: 36,
              bottom: 6,
              child: Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LazyFolderCover extends ConsumerStatefulWidget {
  const _LazyFolderCover({
    required this.pathId,
    required this.filter,
    required this.contentVersion,
  });
  final String pathId;
  final MediaKindFilter filter;

  /// Folder visible count (or other stamp) — changes force a new cover load.
  final int contentVersion;

  @override
  ConsumerState<_LazyFolderCover> createState() => _LazyFolderCoverState();
}

class _LazyFolderCoverState extends ConsumerState<_LazyFolderCover> {
  ImageProvider? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _LazyFolderCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pathId != widget.pathId ||
        oldWidget.filter != widget.filter ||
        oldWidget.contentVersion != widget.contentVersion) {
      // Count/version change after hide → drop stale cover for this folder.
      FolderCoverCache.clear(pathId: widget.pathId);
      if (oldWidget.pathId != widget.pathId) {
        FolderCoverCache.clear(pathId: oldWidget.pathId);
      }
      _image = null;
      _load();
    }
  }

  Future<void> _load() async {
    final version = widget.contentVersion;
    final key = FolderCoverCache.key(widget.filter, widget.pathId);
    final cached = FolderCoverCache.get(key);
    if (cached != null) {
      if (mounted) setState(() => _image = cached);
      return;
    }

    final bytes = await ref.read(galleryServiceProvider).folderCover(
          pathId: widget.pathId,
          filter: widget.filter,
        );
    if (!mounted || version != widget.contentVersion) return;
    if (bytes == null) {
      setState(() => _image = null);
      return;
    }
    final img = MemoryImage(bytes);
    FolderCoverCache.put(key, img);
    setState(() => _image = img);
  }

  @override
  Widget build(BuildContext context) {
    if (_image != null) {
      return Image(image: _image!, fit: BoxFit.cover, gaplessPlayback: true);
    }
    return ColoredBox(
      color: const Color(0xFF244842),
      child: Icon(
        widget.filter == MediaKindFilter.video
            ? Icons.videocam_outlined
            : Icons.folder_outlined,
        color: Colors.white54,
        size: 36,
      ),
    );
  }
}

class _PermDenied extends StatelessWidget {
  const _PermDenied({required this.onRequest, required this.onRetry});
  final VoidCallback onRequest;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.screen,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_library_outlined,
              size: 56,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            Text(
              'Allow gallery access',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Visible lists your photo or video folders. '
              'Grant permission to browse and hide them.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Grant permission'),
            ),
            TextButton(
              onPressed: onRequest,
              child: const Text('Open system settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermError extends StatelessWidget {
  const _PermError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: Colors.white70)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
