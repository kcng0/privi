import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart' show PermissionStateExt;

import '../../application/gallery/gallery_controller.dart';
import '../../application/import/import_controller.dart';
import '../../application/media/visible_folder_view_preferences.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../core/theme/vault_colors.dart';
import '../../data/services/import/import_models.dart';
import '../../domain/enums.dart';
import '../common/vault_sheet.dart';
import '../import/import_progress_sheet.dart';
import '../import/import_result_message.dart';
import 'folder_cover_cache.dart';
import 'visible_media_grid.dart';

export 'folder_cover_cache.dart';

/// Visible tab: system Gallery folders (photo mode XOR video mode).
class VisibleFolderGrid extends ConsumerStatefulWidget {
  const VisibleFolderGrid({super.key});

  @override
  ConsumerState<VisibleFolderGrid> createState() => _VisibleFolderGridState();
}

class _VisibleFolderGridState extends ConsumerState<VisibleFolderGrid>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Returning from the system permission dialog / Settings: re-check and
      // auto-show folders without requiring another Grant tap.
      _refreshPermissionAndFolders();
    }
  }

  void _refreshPermissionAndFolders() {
    ref.invalidate(galleryPermissionProvider);
    ref.invalidate(galleryFoldersProvider);
    ref.read(galleryServiceProvider).apply(const VisiblePermissionChanged());
  }

  Future<void> _openFolder(GalleryFolder folder) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VisibleMediaGrid(
          pathId: folder.id,
          title: folder.name,
        ),
      ),
    );
    if (mounted) ref.invalidate(galleryFoldersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final perm = ref.watch(galleryPermissionProvider);
    final folders = ref.watch(galleryFoldersProvider);
    final filter = ref.watch(mediaKindFilterProvider);
    final viewMode = ref.watch(visibleFolderViewPreferencesProvider);
    final visibleCapabilities = ref.watch(visibleLibraryProvider).capabilities;
    // Same Style setting as Invisible home mosaic (home ⋮ → Style).
    final cols = ref.watch(settingsControllerProvider).albumColumns;

    return perm.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _PermError(
        message: '$e',
        onRetry: _refreshPermissionAndFolders,
      ),
      data: (state) {
        if (!(state.isAuth || state.hasAccess)) {
          return _PermDenied(
            onRequest: () async {
              await ref.read(galleryServiceProvider).openSettings();
              // When user returns, didChangeAppLifecycleState(resumed) refreshes.
              // Also invalidate now so a fast grant without full pause still works.
              _refreshPermissionAndFolders();
            },
            onRetry: () async {
              final next =
                  await ref.read(galleryServiceProvider).requestPermission();
              _refreshPermissionAndFolders();
              // If still denied after system sheet, open Settings once.
              if (!(next.isAuth || next.hasAccess)) {
                await ref.read(galleryServiceProvider).openSettings();
              }
            },
          );
        }

        return folders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              Center(child: Text(context.l10n.couldNotLoadGallery('$e'))),
          data: (list) {
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: AppSpacing.screen,
                  child: Text(
                    filter == MediaKindFilter.video
                        ? context.l10n.noVideoFolders
                        : context.l10n.noPhotoFolders,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ),
              );
            }

            final content = viewMode == AlbumViewMode.list
                ? ListView.builder(
                    key: const ValueKey('visible-folder-list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      GridDefaults.gutter,
                      GridDefaults.gutter,
                      GridDefaults.gutter,
                      GridDefaults.bottomClearance +
                          MediaQuery.paddingOf(context).bottom,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final folder = list[i];
                      return _FolderListTile(
                        key: ValueKey('visible-folder-list-${folder.id}'),
                        folder: folder,
                        filter: filter,
                        onTap: () => _openFolder(folder),
                        onLongPress: () => _hideFolder(
                          context: context,
                          ref: ref,
                          folder: folder,
                          filter: filter,
                        ),
                      );
                    },
                  )
                : GridView.builder(
                    key: const ValueKey('visible-folder-grid'),
                    physics: const AlwaysScrollableScrollPhysics(),
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
                      final folder = list[i];
                      return _FolderTile(
                        key: ValueKey('visible-folder-grid-${folder.id}'),
                        folder: folder,
                        filter: filter,
                        onTap: () => _openFolder(folder),
                        onLongPress: () => _hideFolder(
                          context: context,
                          ref: ref,
                          folder: folder,
                          filter: filter,
                        ),
                      );
                    },
                  );

            final galleryContent = RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: () async {
                FolderCoverCache.clear();
                final gallery = ref.read(galleryServiceProvider);
                gallery.apply(const VisibleFilterChanged());
                try {
                  await gallery
                      .clearFileCache()
                      .timeout(const Duration(seconds: 2));
                } catch (_) {}
                // Accurate recount per folder (single-album scans) so counts
                // match after cold-start vault hydration + rename hides.
                try {
                  final paths = await ref
                      .read(mediaRepositoryProvider)
                      .listActiveOriginalPaths();
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
                ref.invalidate(galleryFoldersProvider);
                await ref.read(galleryFoldersProvider.future);
              },
              child: content,
            );
            if (!state.isLimited ||
                !visibleCapabilities.showsLimitedAccessNotice) {
              return galleryContent;
            }
            return Column(
              children: [
                MaterialBanner(
                  content: Text(context.l10n.limitedPhotosAccess),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          ref.read(galleryServiceProvider).openSettings(),
                      child: Text(context.l10n.openSettings),
                    ),
                  ],
                ),
                Expanded(child: galleryContent),
              ],
            );
          },
        );
      },
    );
  }
}

Future<void> _hideFolder({
  required BuildContext context,
  required WidgetRef ref,
  required GalleryFolder folder,
  required MediaKindFilter filter,
}) async {
  // ignore: unawaited_futures
  HapticFeedback.mediumImpact();

  final choice = await showVaultSheet<String>(
    context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              folder.name,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              context.l10n.itemsCount(folder.count),
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.visibility_off_outlined,
              color: Colors.white70,
            ),
            title: Text(
              context.l10n.hide,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              context.l10n.moveFolderToVault,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            onTap: () => Navigator.pop(ctx, 'hide'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice != 'hide' || !context.mounted) return;

  final vaultAccess = ref.read(vaultAccessProvider);
  final vaultReady = await vaultAccess.isReady();
  if (!vaultReady && vaultAccess.requiresUserGrant) {
    if (!context.mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.permissionNeeded),
        content: Text(context.l10n.permissionNeededBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.openSettings),
          ),
        ],
      ),
    );
    if (go == true) await vaultAccess.openSettings();
    return;
  }
  if (!context.mounted) return;

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.hideFolderTitle),
      content: Text(
        context.l10n.hideFolderBody(folder.name, folder.count),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(context.l10n.hide),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;

  final gallery = ref.read(galleryServiceProvider);
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);
  final import = ref.read(importControllerProvider.notifier);
  // Session before listing/resolve so Cancel is live immediately.
  import.beginSession();
  // ignore: unawaited_futures
  showImportProgressSheet(context);

  var imported = 0;
  List<ImportSource> resolvedSources = const [];
  try {
    final ids = <String>[];
    var page = 0;
    while (true) {
      if (import.isCancelRequested) break;
      final batch = await gallery.listAssets(
        pathId: folder.id,
        filter: filter,
        page: page,
        size: 200,
      );
      if (batch.isEmpty) break;
      ids.addAll(batch.map((a) => a.id));
      if (batch.length < 200) break;
      page++;
      if (page > 200) break; // safety
    }
    if (import.isCancelRequested) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.cancelled)),
        );
      }
      return;
    }
    if (ids.isEmpty) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.noMediaToHide)),
        );
      }
      return;
    }

    final sources = await gallery.resolveForHide(
      ids,
      sourceFolderName: folder.name,
    );
    resolvedSources = sources;
    if (import.isCancelRequested) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.cancelled)),
        );
      }
      return;
    }
    if (sources.isEmpty) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotOpenFilesToHide)),
        );
      }
      return;
    }

    final summary = await import.runImport(
      sources,
      sourceFolderName: folder.name,
      sessionAlreadyStarted: true,
    );
    imported = summary.imported;
    if (context.mounted) {
      final msg = StringBuffer();
      if (summary.cancelled && imported == 0) {
        msg.write(context.l10n.cancelled);
      } else if (imported == 0) {
        msg.write(context.l10n.nothingHidden);
      } else if (imported == 1) {
        msg.write(context.l10n.hiddenToAlbum(folder.name));
      } else {
        msg.write(context.l10n.hiddenCountToAlbum(imported, folder.name));
      }
      if (summary.cancelled && imported > 0) {
        msg.write(' · ${context.l10n.cancelled}');
      }
      if (summary.failed > 0) {
        msg.write(' · ${context.l10n.failedItems(summary.failed)}');
      }
      if (summary.errorCode == ImportErrorCode.needManageStorage) {
        msg.write(' · ${context.l10n.permissionNeeded}');
      } else {
        final detail = importOutcomeDetail(context, summary.errorCode);
        if (detail != null) msg.write(' · $detail');
      }
      messenger.showSnackBar(SnackBar(content: Text(msg.toString())));
    }
  } catch (e) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.couldNotHideMedia)),
      );
    }
  } finally {
    try {
      if (nav.canPop()) nav.pop();
    } catch (_) {}
    import.clearSummary();
    // Partial success still refreshes Visible so UI is not stuck stale.
    if (imported > 0) {
      await gallery.recordHidden(
        pathId: folder.id,
        hiddenCount: imported,
        filter: filter,
        originalPaths: resolvedSources.map((source) => source.path).toList(),
      );
      FolderCoverCache.clear(pathId: folder.id);
      ref.invalidate(galleryFoldersProvider);
      ref.invalidate(albumsProvider);
    }
  }
}

class _FolderTile extends ConsumerWidget {
  const _FolderTile({
    super.key,
    required this.folder,
    required this.filter,
    required this.onTap,
    required this.onLongPress,
  });

  final GalleryFolder folder;
  final MediaKindFilter filter;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: context.vaultColors.chrome,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
                    colors: [Colors.transparent, Colors.black87],
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

class _FolderListTile extends StatelessWidget {
  const _FolderListTile({
    super.key,
    required this.folder,
    required this.filter,
    required this.onTap,
    required this.onLongPress,
  });

  final GalleryFolder folder;
  final MediaKindFilter filter;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: SizedBox.square(
          dimension: 52,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.albumTile),
            child: _LazyFolderCover(
              pathId: folder.id,
              filter: filter,
              contentVersion: Object.hash(folder.count, folder.coverEpoch),
            ),
          ),
        ),
        title: Text(
          folder.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          context.l10n.itemsCount(folder.count),
          style: const TextStyle(color: Colors.white54),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        onLongPress: onLongPress,
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
      color: context.vaultColors.surfaceAlt,
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
              context.l10n.allowGalleryAccess,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.allowGalleryAccessBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRetry,
              child: Text(context.l10n.grantPermission),
            ),
            TextButton(
              onPressed: onRequest,
              child: Text(context.l10n.openSystemSettings),
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
          TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
        ],
      ),
    );
  }
}
