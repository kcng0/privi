import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/gallery/gallery_controller.dart';
import '../../application/import/import_controller.dart';
import '../../application/media/media_view_preferences.dart';
import '../../application/media/rating_controller.dart';
import '../../application/media/selection_controller.dart';
import '../../application/player/external_player_coordinator.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../core/theme/vault_colors.dart';
import '../../core/utils/media_query_utils.dart';
import '../../data/services/import/import_models.dart';
import '../../domain/enums.dart';
import '../../domain/models/album.dart';
import '../../domain/models/media_item.dart';
import '../common/empty_state.dart';
import '../common/floating_action_capsule.dart';
import '../common/grid_app_menu.dart';
import '../common/media_details_sheet.dart';
import '../common/media_grid_scaffold.dart';
import '../common/quick_rating_sheet.dart';
import '../common/rating_filter_bar.dart';
import '../common/vault_sheet.dart';
import '../import/import_progress_sheet.dart';
import '../player/player_screen.dart';
import '../viewer/viewer_screen.dart';
import 'thumbnail_tile.dart';

/// Invisible vault album grid — selection + floating capsule menu.
///
/// Long-press → select + bottom-center round menu:
/// - Recycle: Restore | More (delete forever)
/// - Normal: Unhide | Rate | More (set cover, move, delete to bin)
///
/// App bar ⋮ holds Select / Style / Search / Sort.
class MediaGridScreen extends ConsumerStatefulWidget {
  const MediaGridScreen({
    super.key,
    required this.albumId,
    required this.title,
  });

  final String albumId;
  final String title;

  @override
  ConsumerState<MediaGridScreen> createState() => _MediaGridScreenState();
}

class _MediaGridScreenState extends ConsumerState<MediaGridScreen> {
  bool get _isRecycle => widget.albumId == SystemAlbumIds.recycle;
  bool get _isFavorites => widget.albumId == SystemAlbumIds.favorites;
  bool get _isUserAlbum =>
      widget.albumId != SystemAlbumIds.all &&
      widget.albumId != SystemAlbumIds.favorites &&
      widget.albumId != SystemAlbumIds.recycle;
  bool get _canSetCover => _isUserAlbum || _isFavorites;
  MediaViewScope get _viewScope => MediaViewScope.vaultAlbum(widget.albumId);

  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  final GlobalKey _overflowKey = GlobalKey();
  final GlobalKey _heartsChipKey = GlobalKey();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MediaItem> _applyQuery(
    List<MediaItem> items, {
    required MediaKindFilter kind,
    required MediaViewPreferences preferences,
  }) {
    // Shared Visible/Invisible photo XOR video preference.
    final kindFiltered = items.where((m) {
      return kind == MediaKindFilter.video ? m.isVideo : !m.isVideo;
    }).toList(growable: false);

    if (_isRecycle) {
      return MediaQueryUtils.apply(
        items: kindFiltered,
        search: _searchCtrl.text,
        sorts: preferences.sorts,
        rating: RatingFilter.all,
      );
    }
    return MediaQueryUtils.apply(
      items: kindFiltered,
      search: _searchCtrl.text,
      sorts: preferences.sorts,
      rating: preferences.ratingFilter,
      heartLevels:
          preferences.heartLevels.isEmpty ? null : preferences.heartLevels,
    );
  }

  Future<void> _openViewer(List<MediaItem> items, int index) async {
    if (items.isEmpty) return;
    final item = items[index];
    final preferExternal = ref.read(settingsControllerProvider).playerExternal;

    // Videos: prefer system app chooser when setting is on (default true).
    final external = ref.read(externalPlayerCoordinatorProvider);
    if (item.isVideo && preferExternal && external.supported) {
      final ok = await external.open(
        filePath: item.privatePath,
        mimeType: item.mimeType,
      );
      if (ok) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.noExternalPlayer)),
        );
      }
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ViewerScreen(items: List.of(items), initialIndex: index),
      ),
    );
  }

  Future<void> _playAlbum(List<MediaItem> items) async {
    if (items.isEmpty) return;
    final shuffleDefault = ref.read(settingsControllerProvider).shuffleDefault;
    final shuffle = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.playPlaylist),
        content: Text(
          shuffleDefault
              ? context.l10n.playPlaylistShuffleOn
              : context.l10n.playPlaylistShuffleOff,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.inOrder),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.shuffle),
          ),
        ],
      ),
    );
    if (shuffle == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          items: List.of(items),
          shuffle: shuffle,
          title: widget.title,
        ),
      ),
    );
  }

  Future<void> _rateSelected() async {
    final ids = ref.read(selectionControllerProvider).toList();
    if (ids.isEmpty) return;
    final next = await showQuickRatingSheet(context, currentRating: 1);
    if (next == null) return;
    await ref.read(ratingControllerProvider.notifier).setRatings(ids, next);
  }

  Future<void> _restoreSelected() async {
    final ids = ref.read(selectionControllerProvider).toList();
    await ref.read(mediaRepositoryProvider).restoreMany(ids);
    ref.read(selectionControllerProvider.notifier).clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.restoredCount(ids.length))),
    );
  }

  Future<void> _softDeleteSelected() async {
    final ids = ref.read(selectionControllerProvider).toList();
    await ref.read(mediaRepositoryProvider).softDeleteMany(ids);
    ref.read(selectionControllerProvider.notifier).clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.movedToRecycleBinCount(ids.length))),
    );
  }

  Future<void> _purgeSelected() async {
    final ids = ref.read(selectionControllerProvider).toList();
    if (ids.isEmpty) return;
    final navigator = Navigator.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text(context.l10n.deleteForever),
              ],
            ),
          ),
        ),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    try {
      await ref.read(mediaRepositoryProvider).purgeMany(ids);
    } finally {
      if (navigator.canPop()) navigator.pop();
    }
    ref.read(selectionControllerProvider.notifier).clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.deletedForeverCount(ids.length))),
    );
  }

  Future<void> _setAsCover() async {
    final ids = ref.read(selectionControllerProvider).toList();
    if (ids.isEmpty) return;
    await ref.read(albumRepositoryProvider).setCover(widget.albumId, ids.first);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.coverUpdated)),
    );
  }

  Future<void> _moveToAlbum() async {
    final ids = ref.read(selectionControllerProvider).toList();
    if (ids.isEmpty) return;
    final allAlbums = await ref.read(albumRepositoryProvider).listUserAlbums();
    final albums = _isUserAlbum
        ? allAlbums
            .where((album) => album.id != widget.albumId)
            .toList(growable: false)
        : allAlbums;
    if (!mounted) return;
    if (albums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isUserAlbum
                ? context.l10n.createAnotherAlbumFirst
                : context.l10n.createUserAlbumFirst,
          ),
        ),
      );
      return;
    }
    final target = await showVaultSheet<String>(
      context,
      showDragHandle: false,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.moveToAlbum,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final a in albums)
              ListTile(
                title:
                    Text(a.name, style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, a.id),
              ),
          ],
        ),
      ),
    );
    if (target == null) return;
    final repo = ref.read(albumRepositoryProvider);
    if (_isUserAlbum) {
      await repo.moveMediaToUserAlbum(
        sourceAlbumId: widget.albumId,
        targetAlbumId: target,
        mediaIds: ids,
      );
    } else {
      for (final id in ids) {
        await repo.addMediaToUserAlbum(target, id);
      }
    }
    ref.read(selectionControllerProvider.notifier).clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.movedToAlbumCount(ids.length))),
    );
  }

  void _showMore() {
    if (_isRecycle) {
      showMoreActionsSheet(
        context,
        actions: [
          FloatingActionItem(
            icon: Icons.delete_forever,
            label: context.l10n.deleteForever,
            destructive: true,
            onTap: _purgeSelected,
          ),
        ],
      );
      return;
    }
    showMoreActionsSheet(
      context,
      actions: [
        if (_canSetCover)
          FloatingActionItem(
            icon: Icons.image_outlined,
            label: context.l10n.setAsCover,
            onTap: _setAsCover,
          ),
        FloatingActionItem(
          icon: Icons.drive_file_move_outline,
          label: context.l10n.moveToAlbum,
          onTap: _moveToAlbum,
        ),
        FloatingActionItem(
          icon: Icons.info_outline,
          label: context.l10n.details,
          onTap: _showDetails,
        ),
        FloatingActionItem(
          icon: Icons.delete_outline,
          label: context.l10n.moveToRecycleBin,
          destructive: true,
          onTap: _softDeleteSelected,
        ),
      ],
    );
  }

  Future<void> _showDetails() async {
    final ids = ref.read(selectionControllerProvider).toList();
    if (ids.isEmpty) return;
    final items = ref.read(albumMediaProvider(widget.albumId)).asData?.value;
    final item = items?.where((e) => e.id == ids.first).firstOrNull;
    if (item == null || !mounted) return;
    await showMediaDetailsSheet(context, item);
  }

  Future<void> _unhideSelected() async {
    final ids = ref.read(selectionControllerProvider).toList();
    if (ids.isEmpty) return;
    final all = ref.read(albumMediaProvider(widget.albumId)).asData?.value;
    final selected = <MediaItem>[
      for (final id in ids)
        if (all != null)
          for (final item in all)
            if (item.id == id) item,
    ];
    if (selected.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final import = ref.read(importControllerProvider.notifier);
    import.beginSession(phase: ImportPhase.unhiding);
    // ignore: unawaited_futures
    showImportProgressSheet(context, title: context.l10n.unhide);

    var n = 0;
    try {
      final summary = await import.runReveal(
        selected,
        sessionAlreadyStarted: true,
      );
      n = summary.imported;
      if (!mounted) return;
      final msg = StringBuffer();
      if (summary.cancelled && n == 0) {
        msg.write(context.l10n.cancelled);
      } else {
        msg.write(context.l10n.unhiddenItems(n));
        if (summary.cancelled && n > 0) {
          msg.write(' · ${context.l10n.cancelled}');
        }
        if (summary.failed > 0) {
          msg.write(' · ${context.l10n.failedItems(summary.failed)}');
        }
      }
      messenger.showSnackBar(SnackBar(content: Text(msg.toString())));
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotUnhideFile)),
        );
      }
    } finally {
      try {
        if (nav.canPop()) nav.pop();
      } catch (_) {}
      import.clearSummary();
      ref.read(selectionControllerProvider.notifier).clear();
    }
  }

  Future<void> _pickHeartLevels() async {
    final box = _heartsChipKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    Offset topLeft = const Offset(16, 120);
    Size chipSize = Size.zero;
    if (box != null && overlay != null) {
      topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
      chipSize = box.size;
    }

    final provider = mediaViewPreferencesProvider(_viewScope);
    final selected = Set<int>.of(ref.read(provider).heartLevels);
    final controller = ref.read(provider.notifier);

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black45,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void toggle(int level) {
              setLocal(() {
                if (!selected.add(level)) selected.remove(level);
              });
              unawaited(controller.setHeartLevels(Set.unmodifiable(selected)));
            }

            final screenW = MediaQuery.sizeOf(ctx).width;
            const menuW = 220.0;
            var left = topLeft.dx;
            if (left + menuW > screenW - 8) left = screenW - menuW - 8;
            if (left < 8) left = 8;
            final top = topLeft.dy + chipSize.height + 4;

            Widget row(int level, String label) {
              final on = selected.contains(level);
              return InkWell(
                onTap: () => toggle(level),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: on ? Colors.white : Colors.white70,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        on ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 20,
                        color: on
                            ? Theme.of(ctx).colorScheme.primary
                            : Colors.white38,
                      ),
                    ],
                  ),
                ),
              );
            }

            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: menuW,
                  child: Material(
                    color: context.vaultColors.chrome,
                    elevation: 10,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                context.l10n.hearts,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          row(1, '♥ 1'),
                          row(2, '♥ 2'),
                          row(3, '♥ 3'),
                          const Divider(height: 8, color: Colors.white12),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(context.l10n.done),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickSort() async {
    final provider = mediaViewPreferencesProvider(_viewScope);
    final preferences = ref.read(provider);
    final controller = ref.read(provider.notifier);
    await GridAppMenu.showSortPicker(
      context,
      selected: preferences.sorts,
      multiSortEnabled: preferences.multiSortEnabled,
      onChanged: (sorts, multiSortEnabled) {
        unawaited(
          controller.setSorting(
            sorts,
            multiSortEnabled: multiSortEnabled,
          ),
        );
      },
    );
  }

  Future<void> _pickStyle() async {
    final provider = mediaViewPreferencesProvider(_viewScope);
    final current = ref.read(provider).gridColumns;
    final next = await GridAppMenu.showStylePicker(
      context,
      current: current,
      options: GridAppMenu.mediaColumnOptions,
      title: context.l10n.layoutStyle,
    );
    if (next == null || !mounted) return;
    await ref.read(provider.notifier).setGridColumns(next);
  }

  void _startSelectFromMenu(List<MediaItem> items) {
    if (items.isEmpty) return;
    ref.read(selectionControllerProvider.notifier).enter(items.first.id);
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

  Future<void> _showOverflowMenu(List<MediaItem> items) async {
    final preferences = ref.read(mediaViewPreferencesProvider(_viewScope));
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
                    preferences.gridColumns,
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
                  MediaQueryUtils.sortsSummaryL10n(
                    context.l10n,
                    preferences.sorts,
                  ),
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
        _startSelectFromMenu(items);
      case 'style':
        await _pickStyle();
      case 'search':
        _toggleSearch();
      case 'sort':
        await _pickSort();
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncMedia = ref.watch(albumMediaProvider(widget.albumId));
    final selected = ref.watch(selectionControllerProvider);
    final selecting = selected.isNotEmpty;
    final viewPreferences = ref.watch(mediaViewPreferencesProvider(_viewScope));
    final cols = viewPreferences.gridColumns;
    final kind = ref.watch(mediaKindFilterProvider);
    final bottomPad = GridDefaults.bottomClearance +
        MediaQuery.paddingOf(context).bottom +
        (selecting ? GridDefaults.selectionCapsuleClearance : 0);
    final sel = ref.read(selectionControllerProvider.notifier);

    return MediaGridScaffold<MediaItem>(
      leading: selecting
          ? IconButton(
              icon: const Icon(Icons.close),
              onPressed: sel.clear,
            )
          : null,
      title: selecting
          ? Text(context.l10n.selectedCount(selected.length))
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
        if (selecting)
          IconButton(
            tooltip: context.l10n.selectAll,
            icon: const Icon(Icons.select_all),
            onPressed: () {
              asyncMedia.whenData((raw) {
                final items = _applyQuery(
                  raw,
                  kind: kind,
                  preferences: viewPreferences,
                );
                sel.selectAll(items.map((e) => e.id));
              });
            },
          )
        else ...[
          if (!_isRecycle)
            asyncMedia.maybeWhen(
              data: (items) => IconButton(
                tooltip: context.l10n.playPlaylist,
                icon: const Icon(Icons.play_arrow),
                onPressed: items.isEmpty
                    ? null
                    : () => _playAlbum(
                          _applyQuery(
                            items,
                            kind: kind,
                            preferences: viewPreferences,
                          ),
                        ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          asyncMedia.maybeWhen(
            data: (raw) {
              final items = _applyQuery(
                raw,
                kind: kind,
                preferences: viewPreferences,
              );
              return IconButton(
                key: _overflowKey,
                tooltip: context.l10n.more,
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showOverflowMenu(items),
              );
            },
            orElse: () => IconButton(
              key: _overflowKey,
              tooltip: context.l10n.more,
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showOverflowMenu(const []),
            ),
          ),
        ],
      ],
      body: asyncMedia.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(context.l10n.errorWithDetails('\$e'))),
        data: (rawItems) {
          final items = _applyQuery(
            rawItems,
            kind: kind,
            preferences: viewPreferences,
          );
          if (rawItems.isEmpty) {
            return EmptyState(
              icon: _isFavorites
                  ? Icons.favorite_border
                  : _isRecycle
                      ? Icons.delete_outline
                      : Icons.photo_outlined,
              title: _isFavorites
                  ? context.l10n.noFavoritesYet
                  : _isRecycle
                      ? context.l10n.recycleBinEmpty
                      : context.l10n.noMediaYet,
              subtitle: _isFavorites
                  ? context.l10n.noFavoritesHint
                  : _isRecycle
                      ? context.l10n.recycleEmptyHint
                      : context.l10n.noMediaHint,
              actionLabel: null,
              onAction: null,
            );
          }
          return Column(
            children: [
              if (!_isRecycle && !_isFavorites)
                RatingFilterBar(
                  value: viewPreferences.ratingFilter,
                  heartLevels: viewPreferences.heartLevels,
                  heartsKey: _heartsChipKey,
                  onChanged: (filter) => unawaited(
                    ref
                        .read(
                          mediaViewPreferencesProvider(_viewScope).notifier,
                        )
                        .setRatingFilter(filter),
                  ),
                  onHeartsPressed: _pickHeartLevels,
                ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          context.l10n.noMatches,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: Colors.white70),
                        ),
                      )
                    : Stack(
                        children: [
                          GridView.builder(
                            // Prefetch posters just beyond the viewport.
                            scrollCacheExtent:
                                const ScrollCacheExtent.pixels(1200),
                            padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              mainAxisSpacing: GridDefaults.gutter,
                              crossAxisSpacing: GridDefaults.gutter,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final isSelected = selected.contains(item.id);
                              return ThumbnailTile(
                                item: item,
                                selecting: selecting,
                                selected: isSelected,
                                onRate: selecting
                                    ? null
                                    : (n) => ref
                                        .read(ratingControllerProvider.notifier)
                                        .setRating(item.id, n),
                                onLongPress: () {
                                  // ignore: unawaited_futures
                                  HapticFeedback.mediumImpact();
                                  if (selecting) {
                                    sel.toggle(item.id);
                                  } else {
                                    sel.enter(item.id);
                                  }
                                },
                                onTap: () {
                                  if (selecting) {
                                    sel.toggle(item.id);
                                  } else {
                                    _openViewer(items, index);
                                  }
                                },
                              );
                            },
                          ),
                          if (selecting)
                            FloatingActionCapsule(
                              onDismiss: sel.clear,
                              actions: [
                                if (_isRecycle)
                                  FloatingActionItem(
                                    icon: Icons.restore,
                                    label: context.l10n.restore,
                                    onTap: _restoreSelected,
                                  )
                                else ...[
                                  FloatingActionItem(
                                    icon: Icons.visibility,
                                    label: context.l10n.unhide,
                                    onTap: _unhideSelected,
                                  ),
                                  FloatingActionItem(
                                    icon: Icons.favorite,
                                    label: context.l10n.rate,
                                    onTap: _rateSelected,
                                  ),
                                ],
                                FloatingActionItem(
                                  icon: Icons.more_horiz,
                                  label: context.l10n.more,
                                  onTap: _showMore,
                                ),
                              ],
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
