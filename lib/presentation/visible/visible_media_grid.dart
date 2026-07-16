import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import '../../application/gallery/gallery_controller.dart';
import '../../application/import/import_controller.dart';
import '../../application/lock/lock_controller.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../data/services/intent_service.dart';
import '../../data/services/media_rename_service.dart';
import '../../domain/enums.dart';
import '../common/floating_action_capsule.dart';
import '../import/import_progress_sheet.dart';
import 'folder_cover_cache.dart';
import 'gallery_preview_screen.dart';

/// Visible folder browser (hide flow).
///
/// Tap opens media; long-press selects for Hide / Share / Delete.
class VisibleMediaGrid extends ConsumerStatefulWidget {
  const VisibleMediaGrid({
    super.key,
    required this.pathId,
    required this.title,
  });

  final String pathId;
  final String title;

  @override
  ConsumerState<VisibleMediaGrid> createState() => _VisibleMediaGridState();
}

class _VisibleMediaGridState extends ConsumerState<VisibleMediaGrid> {
  final _selected = <String>{};
  bool _selectMode = false;

  final List<GalleryAsset> _items = [];
  final _scroll = ScrollController();
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  static const _pageSize = 90;

  bool get _selecting => _selectMode;

  void _exitSelect() => setState(() {
        _selectMode = false;
        _selected.clear();
      });

  void _enterSelect(String id) {
    // ignore: unawaited_futures
    HapticFeedback.mediumImpact();
    setState(() {
      _selectMode = true;
      _selected
        ..clear()
        ..add(id);
    });
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Initial load after first frame so providers are ready.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      // ignore: discarded_futures
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 0;
      _hasMore = true;
      _items.clear();
    });
    await _loadMore(reset: true);
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loadingMore) return;
    if (!reset && !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final gallery = ref.read(galleryServiceProvider);
      final filter = ref.read(mediaKindFilterProvider);
      // Hydrate vault paths once (cached until hide/unhide invalidation).
      try {
        await gallery.ensureVaultHydrated(
          () => ref.read(mediaRepositoryProvider).listActivePrivatePaths(),
        );
      } catch (_) {}

      final page = reset ? 0 : _page;
      final batch = await gallery.listAssets(
        pathId: widget.pathId,
        filter: filter,
        page: page,
        size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(batch);
          _page = 1;
        } else {
          // Dedupe by id in case of overlaps.
          final seen = {for (final a in _items) a.id};
          for (final a in batch) {
            if (seen.add(a.id)) _items.add(a);
          }
          _page = page + 1;
        }
        _hasMore = batch.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = '$e';
      });
    }
  }

  Future<void> _openPreview(GalleryAsset a) async {
    final preferExternal = ref.read(settingsControllerProvider).playerExternal;

    if (a.isVideo && preferExternal) {
      // Resolve a real path for external players / chooser.
      final sources = await ref
          .read(galleryServiceProvider)
          .resolveForHide([a.id], sourceFolderName: widget.title);
      if (sources.isNotEmpty) {
        ref
            .read(lockControllerProvider.notifier)
            .suppressAutoLockUntilResumed();
        final ok = await IntentService().openExternal(
          filePath: sources.first.path,
          mimeType:
              sources.first.mimeType ?? (a.isVideo ? 'video/*' : 'image/*'),
          chooserTitle: 'Open with',
        );
        if (ok) return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open externally — preview in-app'),
          ),
        );
      }
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GalleryPreviewScreen(
          assetId: a.id,
          title: a.title,
          isVideo: a.isVideo,
        ),
      ),
    );
  }

  /// Hide: rename in place (e.g. `a.mp4` → `a.vid.pg.mp4`).
  Future<void> _hideSelected() async {
    if (_selected.isEmpty) return;
    final ids = _selected.toList();
    final gallery = ref.read(galleryServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final folderName = widget.title.trim().isEmpty ? 'Imported' : widget.title;
    final renamer = MediaRenameService();

    // Android 11+: File.rename needs All files access for Downloads/DCIM.
    final hasAllFiles = await renamer.isExternalStorageManager();
    if (!hasAllFiles) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Allow file access to hide'),
          content: const Text(
            'To hide media by renaming (e.g. video.mp4 → video.vid.pg.mp4), '
            'Android requires “All files access” for this app.\n\n'
            'Open settings, enable it for Privi, then try Hide again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      if (go == true) {
        await renamer.openManageAllFilesSettings();
      }
      return;
    }

    if (!mounted) return;
    // ignore: unawaited_futures
    showImportProgressSheet(context, title: 'Hiding…');

    var imported = 0;
    try {
      final sources = await gallery.resolveForHide(
        ids,
        sourceFolderName: folderName,
      );
      if (sources.isEmpty) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Could not open file paths to rename.'),
            ),
          );
        }
        return;
      }

      final summary =
          await ref.read(importControllerProvider.notifier).runImport(
                sources,
                sourceFolderName: folderName,
              );
      imported = summary.imported;

      if (!mounted) return;
      final msg = StringBuffer();
      if (summary.imported > 0) {
        msg.write(
          summary.imported == 1
              ? 'Hidden → Invisible / $folderName'
              : 'Hidden ${summary.imported} → Invisible / $folderName',
        );
      }
      if (summary.failed > 0) {
        if (msg.isNotEmpty) msg.write(' · ');
        msg.write('${summary.failed} failed');
        final err = summary.lastError;
        if (err != null && err.isNotEmpty) {
          msg.write(': $err');
        }
      }
      if (summary.skipped > 0) {
        if (msg.isNotEmpty) msg.write(' · ');
        msg.write('${summary.skipped} skipped');
      }
      if (msg.isEmpty) msg.write('Nothing hidden');

      messenger.showSnackBar(SnackBar(content: Text(msg.toString())));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Hide failed: $e')));
      }
    } finally {
      // Dismiss progress sheet immediately — no multi-second "refresh".
      if (nav.canPop()) {
        nav.pop();
      }
      ref.read(importControllerProvider.notifier).clearSummary();

      if (imported > 0) {
        // Instant folder count/cover update (no full-library scan).
        gallery.noteHidden(
          pathId: widget.pathId,
          hiddenCount: imported,
          assetIds: ids,
        );
        gallery.invalidateVaultPathCache();
        FolderCoverCache.clear(pathId: widget.pathId);
        gallery.refreshAfterMutation();
        ref.read(galleryUiEpochProvider.notifier).bump();
        ref.invalidate(galleryFoldersProvider);
        ref.invalidate(albumsProvider);
        await _reload();
      }

      if (mounted) _exitSelect();
    }
  }

  Future<void> _shareSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final paths = <XFile>[];
    for (final id in ids) {
      final entity = await AssetEntity.fromId(id);
      final file = await entity?.file;
      if (file != null) paths.add(XFile(file.path));
    }
    if (paths.isEmpty) return;
    await Share.shareXFiles(paths);
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete from device?'),
        content: Text(
          'Permanently delete ${ids.length} item(s) from the system gallery. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    var deleted = 0;
    try {
      // photo_manager: remove from MediaStore / gallery (may show system confirm).
      final result = await PhotoManager.editor.deleteWithIds(ids);
      deleted = result.length;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      return;
    }
    if (deleted == 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No items deleted')),
      );
      return;
    }

    final gallery = ref.read(galleryServiceProvider);
    gallery.noteHidden(
      pathId: widget.pathId,
      hiddenCount: deleted,
      assetIds: ids,
    );
    FolderCoverCache.clear(pathId: widget.pathId);
    gallery.refreshAfterMutation();
    ref.read(galleryUiEpochProvider.notifier).bump();
    ref.invalidate(galleryFoldersProvider);
    ref.invalidate(albumsProvider);
    await _reload();
    if (mounted) _exitSelect();
    messenger.showSnackBar(
      SnackBar(content: Text('Deleted $deleted item(s)')),
    );
  }

  void _showMore() {
    showMoreActionsSheet(
      context,
      actions: [
        FloatingActionItem(
          icon: Icons.share_outlined,
          label: 'Share',
          onTap: _shareSelected,
        ),
        FloatingActionItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: _deleteSelected,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(mediaKindFilterProvider);
    // Reload when hide epoch bumps or photo/video mode changes.
    ref.listen(galleryUiEpochProvider, (prev, next) {
      // ignore: discarded_futures
      _reload();
    });
    ref.listen(mediaKindFilterProvider, (prev, next) {
      // ignore: discarded_futures
      _reload();
    });

    final bottomPad = GridDefaults.bottomClearance +
        MediaQuery.paddingOf(context).bottom +
        (_selecting ? GridDefaults.selectionCapsuleClearance : 0);

    return Scaffold(
      backgroundColor: const Color(0xFF101412),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B3A36),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(_selecting ? Icons.close : Icons.arrow_back),
          onPressed: () {
            if (_selecting) {
              _exitSelect();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _selecting ? '${_selected.length} selected' : widget.title,
        ),
        actions: [
          if (_selecting)
            IconButton(
              tooltip: 'Select all',
              icon: const Icon(Icons.select_all),
              onPressed: () {
                if (_items.isEmpty) return;
                setState(() {
                  _selected
                    ..clear()
                    ..addAll(_items.map((e) => e.id));
                });
              },
            ),
        ],
      ),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? Center(
                      child: Text(
                        filter == MediaKindFilter.video
                            ? 'No videos in this folder'
                            : 'No photos in this folder',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  : Stack(
                      children: [
                        GridView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: GridDefaults.gutter,
                            crossAxisSpacing: GridDefaults.gutter,
                          ),
                          itemCount: _items.length +
                              (_hasMore || _loadingMore ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i >= _items.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }
                            final a = _items[i];
                            final sel = _selected.contains(a.id);
                            return _LazyThumbTile(
                              asset: a,
                              selected: sel,
                              selectMode: _selecting,
                              onTap: () {
                                if (_selecting) {
                                  _toggle(a.id);
                                } else {
                                  _openPreview(a);
                                }
                              },
                              onLongPress: () {
                                if (_selecting) {
                                  _toggle(a.id);
                                } else {
                                  _enterSelect(a.id);
                                }
                              },
                            );
                          },
                        ),
                        if (_selecting)
                          FloatingActionCapsule(
                            onDismiss: _exitSelect,
                            actions: [
                              FloatingActionItem(
                                icon: Icons.visibility_off,
                                label: 'Hide',
                                onTap: _hideSelected,
                              ),
                              FloatingActionItem(
                                icon: Icons.more_horiz,
                                label: 'More',
                                onTap: _showMore,
                              ),
                            ],
                          ),
                      ],
                    ),
    );
  }
}

class _LazyThumbTile extends StatefulWidget {
  const _LazyThumbTile({
    required this.asset,
    required this.selected,
    required this.selectMode,
    required this.onTap,
    required this.onLongPress,
  });

  final GalleryAsset asset;
  final bool selected;
  final bool selectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_LazyThumbTile> createState() => _LazyThumbTileState();
}

class _LazyThumbTileState extends State<_LazyThumbTile> {
  static final _cache = <String, ImageProvider>{};
  ImageProvider? _provider;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _LazyThumbTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      _provider = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.asset.id;
    final cached = _cache[id];
    if (cached != null) {
      if (mounted) {
        setState(() {
          _provider = cached;
          _loading = false;
        });
      }
      return;
    }
    try {
      final entity = await AssetEntity.fromId(id);
      final bytes = await entity?.thumbnailDataWithSize(
        const ThumbnailSize.square(200),
        quality: 70,
      );
      if (bytes == null || !mounted) return;
      final provider = MemoryImage(bytes);
      _cache[id] = provider;
      if (_cache.length > 400) _cache.remove(_cache.keys.first);
      setState(() {
        _provider = provider;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_provider != null)
            Image(image: _provider!, fit: BoxFit.cover, gaplessPlayback: true)
          else
            ColoredBox(
              color: const Color(0xFF244842),
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Icon(
                      a.isVideo ? Icons.videocam : Icons.image_outlined,
                      color: Colors.white38,
                    ),
            ),
          if (a.isVideo)
            const Positioned(
              top: 4,
              left: 4,
              child: Icon(
                Icons.play_circle_fill,
                size: 18,
                color: Colors.white70,
              ),
            ),
          if (widget.selectMode)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                widget.selected ? Icons.check_circle : Icons.circle_outlined,
                size: 22,
                color:
                    widget.selected ? const Color(0xFF5ECFBA) : Colors.white70,
              ),
            ),
          if (widget.selected)
            Container(color: Colors.black.withValues(alpha: 0.35)),
        ],
      ),
    );
  }
}
