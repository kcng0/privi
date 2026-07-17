import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import '../../application/gallery/gallery_controller.dart';
import '../../application/import/import_controller.dart';
import '../../application/lock/lock_controller.dart';
import '../../application/media/selectable_grid_controller.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../core/theme/vault_colors.dart';
import '../../core/utils/media_chronology.dart';
import '../../core/utils/media_query_utils.dart';
import '../../data/services/import_service.dart';
import '../../data/services/intent_service.dart';
import '../../data/services/media_rename_service.dart';
import '../../domain/enums.dart';
import '../common/floating_action_capsule.dart';
import '../common/grid_app_menu.dart';
import '../common/media_grid_scaffold.dart';
import '../common/vault_sheet.dart';
import '../common/video_duration_badge.dart';
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
  final _selection = SelectableGridController<String>();

  final List<GalleryAsset> _items = [];
  final _scroll = ScrollController();
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  static const _pageSize = 90;

  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();

  /// Visible grids: date + name only (no ratings).
  final List<MediaSort> _sorts = [MediaSort.dateAddedDesc];

  bool get _selecting => _selection.isSelecting;
  Set<String> get _selected => _selection.selected;

  void _exitSelect() => _selection.exit();

  void _enterSelect(String id) {
    // ignore: unawaited_futures
    HapticFeedback.mediumImpact();
    _selection.enter(id);
  }

  void _toggle(String id) => _selection.toggle(id);

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelectionChanged);
    _scroll.addListener(_onScroll);
    // Initial load after first frame so providers are ready.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _selection
      ..removeListener(_onSelectionChanged)
      ..dispose();
    _searchCtrl.dispose();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
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
          () => ref.read(mediaRepositoryProvider).listActiveOriginalPaths(),
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
      final openWith = context.l10n.openWith;
      final couldNotOpen = context.l10n.couldNotOpenExternally;
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
          chooserTitle: openWith,
        );
        if (ok) return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(couldNotOpen)),
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

  List<GalleryAsset> get _visibleItems {
    var list = List<GalleryAsset>.of(_items);
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((a) => a.title.toLowerCase().contains(q))
          .toList(growable: false);
    }
    // Client-side sort on loaded page(s). Rating sorts ignored for Visible.
    final sorts = _sorts.isEmpty ? [MediaSort.dateAddedDesc] : _sorts;
    list.sort((a, b) {
      for (final s in sorts) {
        final c = switch (s) {
          MediaSort.dateAddedDesc => MediaChronology.compare(
              leftDate: MediaChronology.fromEpochMs(a.createDateMs),
              leftName: a.title,
              rightDate: MediaChronology.fromEpochMs(b.createDateMs),
              rightName: b.title,
              ascending: false,
            ),
          MediaSort.dateAddedAsc => MediaChronology.compare(
              leftDate: MediaChronology.fromEpochMs(a.createDateMs),
              leftName: a.title,
              rightDate: MediaChronology.fromEpochMs(b.createDateMs),
              rightName: b.title,
              ascending: true,
            ),
          MediaSort.nameAsc =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          MediaSort.nameDesc =>
            b.title.toLowerCase().compareTo(a.title.toLowerCase()),
          MediaSort.ratingDesc || MediaSort.ratingAsc => 0,
        };
        if (c != 0) return c;
      }
      return MediaChronology.compare(
        leftDate: MediaChronology.fromEpochMs(a.createDateMs),
        leftName: a.title,
        rightDate: MediaChronology.fromEpochMs(b.createDateMs),
        rightName: b.title,
        ascending: false,
      );
    });
    return list;
  }

  void _toggleSearch() {
    setState(() {
      if (_searchOpen) {
        _searchOpen = false;
        _searchCtrl.clear();
      } else {
        _searchOpen = true;
      }
    });
  }

  Future<void> _pickSort() async {
    await GridAppMenu.showSortPicker(
      context,
      selected: _sorts,
      options: const [
        MediaSort.dateAddedDesc,
        MediaSort.dateAddedAsc,
        MediaSort.nameAsc,
        MediaSort.nameDesc,
      ],
      onChanged: (next) {
        setState(() {
          _sorts
            ..clear()
            ..addAll(next.isEmpty ? [MediaSort.dateAddedDesc] : next);
        });
      },
    );
  }

  Future<void> _pickStyle() async {
    final current = ref.read(settingsControllerProvider).gridColumns;
    final next = await GridAppMenu.showStylePicker(
      context,
      current: current,
      options: GridAppMenu.mediaColumnOptions,
      title: context.l10n.layoutStyle,
    );
    if (next == null || !mounted) return;
    await ref.read(settingsControllerProvider.notifier).setGridColumns(next);
  }

  void _startSelectFromMenu() {
    final items = _visibleItems;
    if (items.isEmpty) return;
    _enterSelect(items.first.id);
  }

  Future<void> _showOverflowMenu() async {
    final choice = await showVaultSheet<String>(
      context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.checklist_rtl, color: Colors.white70),
                title: Text(
                  context.l10n.select,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  context.l10n.multiSelectItems,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'select'),
              ),
              ListTile(
                leading: const Icon(Icons.grid_view, color: Colors.white70),
                title: Text(
                  context.l10n.style,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  context.l10n.columnsCount(
                    ref.read(settingsControllerProvider).gridColumns,
                  ),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'style'),
              ),
              ListTile(
                leading: Icon(
                  _searchOpen ? Icons.search_off : Icons.search,
                  color: Colors.white70,
                ),
                title: Text(
                  _searchOpen ? context.l10n.closeSearch : context.l10n.search,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, 'search'),
              ),
              ListTile(
                leading: const Icon(Icons.sort, color: Colors.white70),
                title: Text(
                  context.l10n.sort,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  MediaQueryUtils.sortsSummaryL10n(context.l10n, _sorts),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'sort'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'select':
        _startSelectFromMenu();
      case 'style':
        await _pickStyle();
      case 'search':
        _toggleSearch();
      case 'sort':
        await _pickSort();
    }
  }

  Future<void> _hideSelected() async {
    if (_selected.isEmpty) return;
    final ids = _selected.toList();
    final gallery = ref.read(galleryServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final folderName = widget.title.trim().isEmpty ? 'Imported' : widget.title;
    final renamer = MediaRenameService();

    // Android 11+: hide needs broader storage access on many folders.
    final hasAllFiles = await renamer.isExternalStorageManager();
    if (!hasAllFiles) {
      if (!mounted) return;
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
      if (go == true) {
        await renamer.openManageAllFilesSettings();
      }
      return;
    }

    if (!mounted) return;
    final import = ref.read(importControllerProvider.notifier);
    // Session starts before path resolve so Cancel is live immediately.
    import.beginSession();
    // ignore: unawaited_futures
    showImportProgressSheet(context, title: null);

    var imported = 0;
    List<ImportSource> resolvedSources = const [];
    try {
      final sources = await gallery.resolveForHide(
        ids,
        sourceFolderName: folderName,
      );
      resolvedSources = sources;
      if (import.isCancelRequested) {
        // User cancelled during resolve.
        return;
      }
      if (sources.isEmpty) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(context.l10n.couldNotOpenPathsToRename)),
          );
        }
        return;
      }

      final summary = await import.runImport(
        sources,
        sourceFolderName: folderName,
        sessionAlreadyStarted: true,
      );
      imported = summary.imported;

      if (!mounted) return;
      final msg = StringBuffer();
      if (summary.cancelled && summary.imported == 0) {
        msg.write(context.l10n.cancelled);
      } else if (summary.imported > 0) {
        msg.write(
          summary.imported == 1
              ? context.l10n.hiddenToAlbum(folderName)
              : context.l10n.hiddenCountToAlbum(summary.imported, folderName),
        );
        if (summary.cancelled) {
          msg.write(' · ${context.l10n.cancelled}');
        }
      }
      if (summary.failed > 0 || summary.skipped > 0) {
        if (msg.isNotEmpty) msg.write(' · ');
        msg.write(
          context.l10n.progressOkSkipFail(
            summary.imported,
            summary.skipped,
            summary.failed,
          ),
        );
        if (summary.errorCode == ImportErrorCode.needManageStorage) {
          msg.write(' · ${context.l10n.permissionNeeded}');
        }
      }
      if (msg.isEmpty) msg.write(context.l10n.nothingHidden);

      messenger.showSnackBar(SnackBar(content: Text(msg.toString())));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(_friendlyHideError(e))),
        );
      }
    } finally {
      // Always dismiss sheet + clear running state (cancel / fail / success).
      try {
        if (nav.canPop()) {
          nav.pop();
        }
      } catch (_) {}
      import.clearSummary();

      // Refresh UI for any partial success so Visible isn't stuck stale.
      if (imported > 0) {
        await gallery.recordHidden(
          pathId: widget.pathId,
          hiddenCount: imported,
          filter: ref.read(mediaKindFilterProvider),
          assetIds: ids,
          originalPaths: resolvedSources.map((source) => source.path).toList(),
        );
        FolderCoverCache.clear(pathId: widget.pathId);
        ref.invalidate(galleryFoldersProvider);
        ref.invalidate(albumsProvider);
        try {
          await _reload();
        } catch (_) {}
      }

      if (mounted) _exitSelect();
    }
  }

  bool _looksLikePermissionError(String err) {
    final lower = err.toLowerCase();
    return lower.contains('permission') ||
        lower.contains('all files') ||
        lower.contains('manage') ||
        lower.contains('needallfiles') ||
        lower.contains('need_manage');
  }

  String _friendlyHideError(Object e) {
    final s = e.toString();
    if (_looksLikePermissionError(s)) {
      return context.l10n.permissionNeededBody;
    }
    return context.l10n.couldNotHideMedia;
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
        title: Text(context.l10n.deleteFromDeviceTitle),
        content: Text(
          context.l10n.deleteFromDeviceBody(ids.length),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    var deleted = 0;
    try {
      // photo_manager: remove from MediaStore / gallery (may show system confirm).
      final result = await PhotoManager.editor.deleteWithIds(ids);
      deleted = result.length;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.deleteFailed('$e'))),
      );
      return;
    }
    if (deleted == 0) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.noItemsDeleted)),
      );
      return;
    }

    final gallery = ref.read(galleryServiceProvider);
    await gallery.recordHidden(
      pathId: widget.pathId,
      hiddenCount: deleted,
      filter: ref.read(mediaKindFilterProvider),
      assetIds: ids,
    );
    FolderCoverCache.clear(pathId: widget.pathId);
    ref.invalidate(galleryFoldersProvider);
    ref.invalidate(albumsProvider);
    await _reload();
    if (mounted) _exitSelect();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.deletedItems(deleted))),
    );
  }

  void _showMore() {
    showMoreActionsSheet(
      context,
      actions: [
        FloatingActionItem(
          icon: Icons.share_outlined,
          label: context.l10n.share,
          onTap: _shareSelected,
        ),
        FloatingActionItem(
          icon: Icons.delete_outline,
          label: context.l10n.delete,
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
    ref.listen(galleryChangeProvider, (prev, next) {
      // ignore: discarded_futures
      _reload();
    });
    ref.listen(mediaKindFilterProvider, (prev, next) {
      // ignore: discarded_futures
      _reload();
    });

    final cols = ref.watch(settingsControllerProvider).gridColumns;
    final visible = _visibleItems;
    final bottomPad = GridDefaults.bottomClearance +
        MediaQuery.paddingOf(context).bottom +
        (_selecting ? GridDefaults.selectionCapsuleClearance : 0);

    return MediaGridScaffold<GalleryAsset>(
      leading: IconButton(
        icon: Icon(_selecting ? Icons.close : Icons.arrow_back),
        onPressed: () {
          if (_selecting) {
            _exitSelect();
          } else if (_searchOpen) {
            setState(() {
              _searchOpen = false;
              _searchCtrl.clear();
            });
          } else {
            Navigator.pop(context);
          }
        },
      ),
      title: _selecting
          ? Text(context.l10n.selectedCount(_selected.length))
          : _searchOpen
              ? TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: context.l10n.searchNameHint,
                    hintStyle: const TextStyle(color: Colors.white54),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                )
              : Text(widget.title),
      actions: [
        if (_selecting)
          IconButton(
            tooltip: context.l10n.selectAll,
            icon: const Icon(Icons.select_all),
            onPressed: () {
              final items = _visibleItems;
              if (items.isEmpty) return;
              _selection.selectAll(items.map((item) => item.id));
            },
          )
        else
          IconButton(
            tooltip: context.l10n.more,
            icon: const Icon(Icons.more_vert),
            onPressed: _showOverflowMenu,
          ),
      ],
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? Center(
                      child: Text(
                        filter == MediaKindFilter.video
                            ? context.l10n.noVideosInFolder
                            : context.l10n.noPhotosInFolder,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  : visible.isEmpty
                      ? Center(
                          child: Text(
                            context.l10n.noMatches,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        )
                      : Stack(
                          children: [
                            GridView.builder(
                              controller: _scroll,
                              padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: GridDefaults.gutter,
                                crossAxisSpacing: GridDefaults.gutter,
                              ),
                              itemCount: visible.length +
                                  (_hasMore || _loadingMore ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (i >= visible.length) {
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
                                final a = visible[i];
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
                                    label: context.l10n.hide,
                                    onTap: _hideSelected,
                                  ),
                                  FloatingActionItem(
                                    icon: Icons.more_horiz,
                                    label: context.l10n.more,
                                    onTap: _showMore,
                                  ),
                                ],
                              ),
                          ],
                        ),
    );
  }
}

class _LazyThumbTile extends ConsumerStatefulWidget {
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
  ConsumerState<_LazyThumbTile> createState() => _LazyThumbTileState();
}

class _LazyThumbTileState extends ConsumerState<_LazyThumbTile> {
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
    try {
      final bytes = await ref.read(galleryServiceProvider).mediaThumbnail(id);
      if (!mounted || id != widget.asset.id) return;
      if (bytes == null) {
        setState(() => _loading = false);
        return;
      }
      final provider = MemoryImage(bytes);
      setState(() {
        _provider = provider;
        _loading = false;
      });
    } catch (_) {
      if (mounted && id == widget.asset.id) {
        setState(() => _loading = false);
      }
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
              color: context.vaultColors.surfaceAlt,
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
            Positioned(
              top: 4,
              left: 4,
              child: VideoDurationBadge(durationMs: a.durationMs),
            ),
          if (widget.selectMode)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                widget.selected ? Icons.check_circle : Icons.circle_outlined,
                size: 22,
                color: widget.selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white70,
              ),
            ),
          if (widget.selected)
            Container(color: Colors.black.withValues(alpha: 0.35)),
        ],
      ),
    );
  }
}
