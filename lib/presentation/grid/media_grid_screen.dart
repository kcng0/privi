import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/gallery/gallery_controller.dart';
import '../../application/lock/lock_controller.dart';
import '../../application/media/rating_controller.dart';
import '../../application/media/selection_controller.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../core/utils/media_query_utils.dart';
import '../../data/services/intent_service.dart';
import '../../domain/enums.dart';
import '../../domain/models/album.dart';
import '../../domain/models/media_item.dart';
import '../common/empty_state.dart';
import '../common/floating_action_capsule.dart';
import '../common/grid_app_menu.dart';
import '../common/media_details_sheet.dart';
import '../common/quick_rating_sheet.dart';
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

  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  final List<MediaSort> _sorts = [MediaSort.dateAddedDesc];
  final GlobalKey _overflowKey = GlobalKey();
  RatingFilter _rating = RatingFilter.all;
  final Set<int> _heartLevels = {}; // multi-select ♥1/2/3 when Hearts chip used
  final GlobalKey _heartsChipKey = GlobalKey();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MediaItem> _applyQuery(
    List<MediaItem> items, {
    required MediaKindFilter kind,
  }) {
    // Shared Visible/Invisible photo XOR video preference.
    final kindFiltered = items.where((m) {
      return kind == MediaKindFilter.video ? m.isVideo : !m.isVideo;
    }).toList(growable: false);

    if (_isRecycle) {
      return MediaQueryUtils.apply(
        items: kindFiltered,
        search: _searchCtrl.text,
        sorts: List.of(_sorts),
        rating: RatingFilter.all,
      );
    }
    return MediaQueryUtils.apply(
      items: kindFiltered,
      search: _searchCtrl.text,
      sorts: List.of(_sorts),
      rating: _rating,
      heartLevels: _heartLevels.isEmpty ? null : Set.of(_heartLevels),
    );
  }


  Future<void> _openViewer(List<MediaItem> items, int index) async {
    if (items.isEmpty) return;
    final item = items[index];
    final preferExternal = ref.read(settingsControllerProvider).playerExternal;

    // Videos: prefer system app chooser when setting is on (default true).
    if (item.isVideo && preferExternal) {
      ref.read(lockControllerProvider.notifier).suppressAutoLockUntilResumed();
      final ok = await IntentService().openExternal(
        filePath: item.privatePath,
        mimeType: item.mimeType,
        chooserTitle: 'Play video with',
      );
      if (ok) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No external player found — opening in-app'),
          ),
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
        title: const Text('Play playlist'),
        content: Text(
          shuffleDefault
              ? 'Start with shuffle on?'
              : 'Start with shuffle off? You can toggle in the player.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('In order'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Shuffle'),
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
      SnackBar(content: Text('Restored ${ids.length}')),
    );
  }

  Future<void> _softDeleteSelected() async {
    final ids = ref.read(selectionControllerProvider).toList();
    await ref.read(mediaRepositoryProvider).softDeleteMany(ids);
    ref.read(selectionControllerProvider.notifier).clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Moved ${ids.length} to Recycle Bin')),
    );
  }

  Future<void> _purgeSelected() async {
    final ids = ref.read(selectionControllerProvider).toList();
    await ref.read(mediaRepositoryProvider).purgeMany(ids);
    ref.read(selectionControllerProvider.notifier).clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted ${ids.length} forever')),
    );
  }

  Future<void> _setAsCover() async {
    final ids = ref.read(selectionControllerProvider).toList();
    if (ids.isEmpty) return;
    if (widget.albumId == SystemAlbumIds.all ||
        widget.albumId == SystemAlbumIds.favorites ||
        widget.albumId == SystemAlbumIds.recycle) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open a user album to set its cover'),
        ),
      );
      return;
    }
    await ref.read(albumRepositoryProvider).setCover(widget.albumId, ids.first);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cover updated')),
    );
  }

  Future<void> _moveToAlbum() async {
    final ids = ref.read(selectionControllerProvider).toList();
    if (ids.isEmpty) return;
    final albums = await ref.read(albumRepositoryProvider).listUserAlbums();
    if (!mounted) return;
    if (albums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a user album first')),
      );
      return;
    }
    final target = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1B3A36),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Move to album',
                style: TextStyle(
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
    for (final id in ids) {
      await repo.addMediaToUserAlbum(target, id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Moved ${ids.length} to album')),
    );
  }

  void _showMore() {
    if (_isRecycle) {
      showMoreActionsSheet(
        context,
        actions: [
          FloatingActionItem(
            icon: Icons.delete_forever,
            label: 'Delete forever',
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
        FloatingActionItem(
          icon: Icons.image_outlined,
          label: 'Set as cover',
          onTap: _setAsCover,
        ),
        FloatingActionItem(
          icon: Icons.drive_file_move_outline,
          label: 'Move to album',
          onTap: _moveToAlbum,
        ),
        FloatingActionItem(
          icon: Icons.info_outline,
          label: 'Details',
          onTap: _showDetails,
        ),
        FloatingActionItem(
          icon: Icons.delete_outline,
          label: 'Move to Recycle Bin',
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
    final import = ref.read(importServiceProvider);
    final items = ref.read(albumMediaProvider(widget.albumId)).asData?.value;
    var n = 0;
    for (final id in ids) {
      final item = items?.where((e) => e.id == id).firstOrNull;
      if (item == null) continue;
      try {
        if (await import.reveal(item)) n++;
      } catch (_) {}
    }
    if (n > 0) {
      final gallery = ref.read(galleryServiceProvider);
      gallery.invalidateVaultPathCache();
      gallery.refreshAfterMutation();
      ref.read(galleryUiEpochProvider.notifier).bump();
      ref.invalidate(galleryFoldersProvider);
    }
    ref.read(selectionControllerProvider.notifier).clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Unhidden $n item(s)')),
    );
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

    final selected = Set<int>.of(_heartLevels);

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
              setState(() {
                _heartLevels
                  ..clear()
                  ..addAll(selected);
                if (_heartLevels.isEmpty) {
                  _rating = RatingFilter.all;
                } else {
                  // heartLevels drives the filter; favorites is a non-all sentinel.
                  _rating = RatingFilter.favorites;
                }
              });
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
                    color: const Color(0xFF1B3A36),
                    elevation: 10,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(14, 8, 14, 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Hearts',
                                style: TextStyle(
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
                            child: const Text('Done'),
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
    await GridAppMenu.showSortPicker(
      context,
      selected: _sorts,
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
      title: 'Layout style',
    );
    if (next == null || !mounted) return;
    await ref.read(settingsControllerProvider.notifier).setGridColumns(next);
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
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1B3A36),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.checklist_rtl, color: Colors.white70),
                title: const Text('Select', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Multi-select items',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'select'),
              ),
              ListTile(
                leading: const Icon(Icons.grid_view, color: Colors.white70),
                title: const Text('Style', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  '${ref.read(settingsControllerProvider).gridColumns} columns',
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
                  _searchOpen ? 'Close search' : 'Search',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, 'search'),
              ),
              ListTile(
                leading: const Icon(Icons.sort, color: Colors.white70),
                title: const Text('Sort', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  MediaQueryUtils.sortsSummary(_sorts),
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
    final cols = ref.watch(settingsControllerProvider).gridColumns;
    final kind = ref.watch(mediaKindFilterProvider);
    final bottomPad = GridDefaults.bottomClearance +
        MediaQuery.paddingOf(context).bottom +
        (selecting ? GridDefaults.selectionCapsuleClearance : 0);
    final sel = ref.read(selectionControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: sel.clear,
              )
            : null,
        title: selecting
            ? Text('${selected.length} selected')
            : _searchOpen
                ? TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Search name…',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  )
                : Text(widget.title),
        actions: [
          if (selecting)
            IconButton(
              tooltip: 'Select all',
              icon: const Icon(Icons.select_all),
              onPressed: () {
                asyncMedia.whenData((raw) {
                  final items = _applyQuery(raw, kind: kind);
                  sel.selectAll(items.map((e) => e.id));
                });
              },
            )
          else ...[
            if (!_isRecycle)
              asyncMedia.maybeWhen(
                data: (items) => IconButton(
                  tooltip: 'Play playlist',
                  icon: const Icon(Icons.play_arrow),
                  onPressed: items.isEmpty
                      ? null
                      : () => _playAlbum(_applyQuery(items, kind: kind)),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            asyncMedia.maybeWhen(
              data: (raw) {
                final items = _applyQuery(raw, kind: kind);
                return IconButton(
                  key: _overflowKey,
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showOverflowMenu(items),
                );
              },
              orElse: () => IconButton(
                key: _overflowKey,
                tooltip: 'More',
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showOverflowMenu(const []),
              ),
            ),
          ],
        ],
      ),
      body: asyncMedia.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rawItems) {
          final items = _applyQuery(rawItems, kind: kind);
          if (rawItems.isEmpty) {
            return EmptyState(
              icon: _isFavorites
                  ? Icons.favorite_border
                  : _isRecycle
                      ? Icons.delete_outline
                      : Icons.photo_outlined,
              title: _isFavorites
                  ? 'No favorites yet'
                  : _isRecycle
                      ? 'Recycle Bin is empty'
                      : 'No media yet',
              subtitle: _isFavorites
                  ? 'Long-press media and Rate with hearts.'
                  : _isRecycle
                      ? 'Soft-deleted items appear here.'
                      : 'Hide media from the Visible tab.',
              actionLabel: null,
              onAction: null,
            );
          }
          return Column(
            children: [
              if (!_isRecycle && !_isFavorites)
                _RatingChips(
                  value: _rating,
                  heartLevels: _heartLevels,
                  heartsKey: _heartsChipKey,
                  onChanged: (v) => setState(() {
                    _rating = v;
                    // Non-heart chips clear multi heart selection.
                    if (v == RatingFilter.all ||
                        v == RatingFilter.unrated ||
                        v == RatingFilter.favorites) {
                      _heartLevels.clear();
                    }
                  }),
                  onHeartsPressed: _pickHeartLevels,
                ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          'No matches',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: Colors.white70),
                        ),
                      )
                    : Stack(
                        children: [
                          GridView.builder(
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
                                    label: 'Restore',
                                    onTap: _restoreSelected,
                                  )
                                else ...[
                                  FloatingActionItem(
                                    icon: Icons.visibility,
                                    label: 'Unhide',
                                    onTap: _unhideSelected,
                                  ),
                                  FloatingActionItem(
                                    icon: Icons.favorite,
                                    label: 'Rate',
                                    onTap: _rateSelected,
                                  ),
                                ],
                                FloatingActionItem(
                                  icon: Icons.more_horiz,
                                  label: 'More',
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

class _RatingChips extends StatelessWidget {
  const _RatingChips({
    required this.value,
    required this.heartLevels,
    required this.onChanged,
    required this.onHeartsPressed,
    this.heartsKey,
  });

  final RatingFilter value;
  final Set<int> heartLevels;
  final ValueChanged<RatingFilter> onChanged;
  final VoidCallback onHeartsPressed;
  final Key? heartsKey;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      Key? key,
      Widget? avatar,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          key: key,
          avatar: avatar,
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: primary.withValues(alpha: 0.35),
          checkmarkColor: Colors.white,
          labelStyle: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 12,
          ),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    final heartsSelected = heartLevels.isNotEmpty;
    final heartsLabel = heartsSelected
        ? '♥ ${([1, 2, 3].where(heartLevels.contains).join(','))}'
        : 'Hearts';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          chip(
            label: 'All',
            selected: value == RatingFilter.all && !heartsSelected,
            onTap: () => onChanged(RatingFilter.all),
          ),
          chip(
            key: heartsKey,
            label: heartsLabel,
            selected: heartsSelected,
            avatar: Icon(
              Icons.favorite,
              size: 16,
              color: heartsSelected ? primary : Colors.white54,
            ),
            onTap: onHeartsPressed,
          ),
          chip(
            label: 'Favorites',
            selected: value == RatingFilter.favorites && !heartsSelected,
            onTap: () => onChanged(RatingFilter.favorites),
          ),
          chip(
            label: 'Unrated',
            selected: value == RatingFilter.unrated && !heartsSelected,
            onTap: () => onChanged(RatingFilter.unrated),
          ),
        ],
      ),
    );
  }
}
