import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/gallery/gallery_controller.dart';
import '../../application/import/import_controller.dart';
import '../../application/media/album_list_preferences.dart';
import '../../application/media/visible_folder_view_preferences.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../core/theme/vault_colors.dart';
import '../../core/utils/album_query_utils.dart';
import '../../data/services/import/import_models.dart';
import '../../domain/enums.dart';
import '../../domain/models/album.dart';
import '../../domain/models/album_group.dart';
import '../../domain/models/album_view.dart';
import '../../domain/models/group_view.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/shelf_entry.dart';
import '../common/grid_app_menu.dart';
import '../common/quick_rating_sheet.dart';
import '../common/vault_sheet.dart';
import '../grid/media_grid_screen.dart';
import '../import/import_progress_sheet.dart';
import '../player/player_screen.dart';
import '../settings/settings_screen.dart';
import '../visible/visible_folder_grid.dart';
import 'arrange_albums_screen.dart';
import 'group_screen.dart';

/// Home: safe top chrome + Visible (gallery folders) | Invisible (vault).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    // Default Invisible after unlock (vault).
    _tabs = TabController(length: 2, vsync: this, initialIndex: 1);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _newAlbum() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.newAlbum),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: context.l10n.albumNameHint),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(context.l10n.create),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final album = await ref.read(albumRepositoryProvider).createUserAlbum(name);
    if (!mounted) return;
    _openAlbum(album.id, album.name);
  }

  Future<void> _newGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.newGroup),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: context.l10n.groupNameHint),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(context.l10n.create),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(albumRepositoryProvider).createGroup(name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.newGroupCreated)),
    );
  }

  void _openAlbum(String id, String name, {SystemAlbumKind? systemKind}) {
    final title = localizedAlbumTitle(
      context.l10n,
      name: name,
      systemKind: systemKind,
      albumId: id,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaGridScreen(albumId: id, title: title),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  /// Home actions. Album organization actions are only available on Invisible.
  Future<void> _menu() async {
    final cols = ref.read(settingsControllerProvider).albumColumns;
    final invisible = _tabs.index == 1;
    final choice = await showVaultSheet<String>(
      context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (invisible)
              ListTile(
                leading: const Icon(Icons.sort, color: Colors.white70),
                title: Text(
                  context.l10n.sort,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  AlbumQueryUtils.sortsSummaryL10n(
                    context.l10n,
                    ref.read(albumListPreferencesProvider).sorts,
                  ),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'album_sort'),
              ),
            if (invisible)
              ListTile(
                leading: const Icon(Icons.drag_handle, color: Colors.white70),
                title: Text(
                  context.l10n.arrangeOrder,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, 'arrange'),
              ),
            ListTile(
              leading: const Icon(Icons.grid_view, color: Colors.white70),
              title: Text(
                context.l10n.style,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                context.l10n.columnsCount(cols),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 'style'),
            ),
            ListTile(
              leading: const Icon(
                Icons.create_new_folder_outlined,
                color: Colors.white70,
              ),
              title: Text(
                context.l10n.newVaultAlbum,
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'new_album'),
            ),
            if (invisible)
              ListTile(
                leading: const Icon(
                  Icons.layers_outlined,
                  color: Colors.white70,
                ),
                title: Text(
                  context.l10n.newGroup,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, 'new_group'),
              ),
            ListTile(
              leading:
                  const Icon(Icons.settings_outlined, color: Colors.white70),
              title: Text(
                context.l10n.settings,
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'settings'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'style':
        await _pickHomeStyle();
      case 'album_sort':
        await _pickAlbumSort();
      case 'arrange':
        await _openArrange();
      case 'new_album':
        await _newAlbum();
      case 'new_group':
        await _newGroup();
      case 'settings':
        _openSettings();
    }
  }

  Future<void> _pickAlbumSort() async {
    final preferences = ref.read(albumListPreferencesProvider);
    await GridAppMenu.showAlbumSortPicker(
      context,
      selected: preferences.sorts,
      multiSortEnabled: preferences.multiSortEnabled,
      options: AlbumSort.values,
      onChanged: (sorts, multiSortEnabled) {
        // The sheet reports changes immediately, while the controller keeps
        // writes serialized in the same manner as media preferences.
        ref
            .read(albumListPreferencesProvider.notifier)
            .setSorting(sorts, multiSortEnabled: multiSortEnabled);
      },
    );
  }

  Future<void> _pickHomeStyle() async {
    if (_tabs.index == 1) {
      await _pickInvisibleStyle();
      return;
    }
    final current = ref.read(settingsControllerProvider).albumColumns;
    final next = await GridAppMenu.showStylePicker(
      context,
      current: current,
      options: GridAppMenu.albumColumnOptions,
      title: context.l10n.layoutStyle,
    );
    if (next == null || !mounted) return;
    await ref.read(settingsControllerProvider.notifier).setAlbumColumns(next);
    // ignore: unawaited_futures
    HapticFeedback.selectionClick();
  }

  Future<void> _pickInvisibleStyle() async {
    final preferences = ref.read(albumListPreferencesProvider);
    final choice = await showVaultSheet<String>(
      context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final columns in GridAppMenu.albumColumnOptions)
              ListTile(
                leading: const Icon(Icons.grid_view, color: Colors.white70),
                title: Text(context.l10n.columnsCount(columns)),
                trailing: preferences.viewMode == AlbumViewMode.mosaic &&
                        ref.read(settingsControllerProvider).albumColumns ==
                            columns
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, 'mosaic-$columns'),
              ),
            ListTile(
              leading: const Icon(Icons.view_list, color: Colors.white70),
              title: Text(context.l10n.listView),
              trailing: preferences.viewMode == AlbumViewMode.list
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(ctx, 'list'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice.startsWith('mosaic-')) {
      final columns = int.parse(choice.substring('mosaic-'.length));
      await ref
          .read(settingsControllerProvider.notifier)
          .setAlbumColumns(columns);
    }
    await ref.read(albumListPreferencesProvider.notifier).setViewMode(
          choice == 'list' ? AlbumViewMode.list : AlbumViewMode.mosaic,
        );
  }

  Future<void> _openArrange() async {
    final shelf = ref.read(albumShelfProvider);
    if (!shelf.hasValue) return;
    final views = shelf.requireValue.entries
        .whereType<AlbumEntry>()
        .map((entry) => entry.view)
        .toList(growable: false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArrangeAlbumsScreen(
          initialViews: views,
          initialEntries: shelf.requireValue.entries,
        ),
      ),
    );
  }

  void _toggleMediaFilter() {
    ref.read(mediaKindFilterProvider.notifier).toggle();
    // ignore: unawaited_futures
    HapticFeedback.selectionClick();
    final f = ref.read(mediaKindFilterProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          f == MediaKindFilter.image
              ? context.l10n.photosOnly
              : context.l10n.videosOnly,
        ),
        duration: const Duration(milliseconds: 800),
      ),
    );
    ref.invalidate(galleryFoldersProvider);
  }

  Future<void> _toggleHomeView() async {
    final invisible = _tabs.index == 1;
    final current = invisible
        ? ref.read(albumListPreferencesProvider).viewMode
        : ref.read(visibleFolderViewPreferencesProvider);
    final next = current == AlbumViewMode.list
        ? AlbumViewMode.mosaic
        : AlbumViewMode.list;
    if (invisible) {
      await ref.read(albumListPreferencesProvider.notifier).setViewMode(next);
    } else {
      await ref
          .read(visibleFolderViewPreferencesProvider.notifier)
          .setViewMode(next);
    }
    if (!mounted) return;
    await HapticFeedback.selectionClick();
  }

  IconData _filterIcon(MediaKindFilter f) {
    return f == MediaKindFilter.image
        ? Icons.image_outlined
        : Icons.videocam_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(mediaKindFilterProvider);
    final albumPreferences = ref.watch(albumListPreferencesProvider);
    final visibleFolderViewMode =
        ref.watch(visibleFolderViewPreferencesProvider);
    final invisible = _tabs.index == 1;
    final homeViewMode =
        invisible ? albumPreferences.viewMode : visibleFolderViewMode;
    // Status bar + notch: MediaQuery padding, never hug the physical top edge.
    final topInset = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: context.vaultColors.surface,
        // Do NOT use SafeArea alone — chrome paints into status area deliberately
        // but content starts below it with generous padding.
        body: Column(
          children: [
            // ── Top chrome ──────────────────────────────────────
            ColoredBox(
              color: context.vaultColors.chrome,
              child: Padding(
                // Extra breathing room under status bar / camera cutout.
                padding: EdgeInsets.only(top: topInset + 6),
                child: SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      Expanded(
                        child: TabBar(
                          controller: _tabs,
                          indicatorColor: Colors.white,
                          indicatorWeight: 2.5,
                          indicatorSize: TabBarIndicatorSize.label,
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white54,
                          dividerColor: Colors.transparent,
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          labelStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.1,
                          ),
                          tabs: [
                            Tab(
                              height: 52,
                              icon: const Icon(
                                Icons.photo_camera_outlined,
                                size: 18,
                              ),
                              text: context.l10n.visible,
                              iconMargin: const EdgeInsets.only(bottom: 2),
                            ),
                            Tab(
                              height: 52,
                              icon: const Icon(
                                Icons.lock,
                                size: 18,
                              ),
                              text: context.l10n.invisible,
                              iconMargin: const EdgeInsets.only(bottom: 2),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: homeViewMode == AlbumViewMode.list
                            ? context.l10n.mosaicView
                            : context.l10n.listView,
                        icon: Icon(
                          homeViewMode == AlbumViewMode.list
                              ? Icons.grid_view
                              : Icons.view_list,
                          size: 22,
                        ),
                        color: Colors.white70,
                        onPressed: _toggleHomeView,
                      ),
                      // Photo XOR video mode — same control on Visible & Invisible.
                      IconButton(
                        tooltip: filter == MediaKindFilter.image
                            ? context.l10n.photosOnlyTapVideos
                            : context.l10n.videosOnlyTapPhotos,
                        icon: Icon(_filterIcon(filter), size: 22),
                        color: Colors.white70,
                        onPressed: _toggleMediaFilter,
                      ),
                      IconButton(
                        tooltip: context.l10n.more,
                        icon: const Icon(Icons.more_vert, size: 22),
                        color: Colors.white70,
                        onPressed: _menu,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  const VisibleFolderGrid(),
                  _InvisibleTab(
                    onOpenAlbum: _openAlbum,
                    onNewAlbum: _newAlbum,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvisibleTab extends ConsumerWidget {
  const _InvisibleTab({
    required this.onOpenAlbum,
    required this.onNewAlbum,
  });

  final void Function(String id, String name, {SystemAlbumKind? systemKind})
      onOpenAlbum;
  final VoidCallback onNewAlbum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelfAsync = ref.watch(albumShelfProvider);
    final cols = ref.watch(settingsControllerProvider).albumColumns;
    final preferences = ref.watch(albumListPreferencesProvider);
    final kind = ref.watch(mediaKindFilterProvider);

    return shelfAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(context.l10n.errorWithDetails('$e'))),
      data: (shelf) {
        final views = shelf.systemViews;
        AlbumView? favorites;
        AlbumView? allMedia;
        AlbumView? recycle;
        final user = <AlbumView>[];

        for (final v in views) {
          switch (v.album.systemKind) {
            case SystemAlbumKind.favorites:
              favorites = v;
            case SystemAlbumKind.all:
              allMedia = v;
            case SystemAlbumKind.recycle:
              recycle = v;
            case null:
              // Hide empty user albums (no images/videos after filter/hide).
              if (v.count > 0) user.add(v);
          }
        }

        final cells = <_Cell>[
          if (allMedia != null)
            _Cell.special(
              view: allMedia,
              icon: Icons.photo_library_outlined,
            ),
          if (favorites != null)
            _Cell.special(
              view: favorites,
              icon: Icons.favorite_border,
              accent: true,
              preferCover: true,
            ),
          // User albums first; "+ New" sits just above Recycle Bin (second last).
          ...shelf.entries.map(
            (entry) => switch (entry) {
              AlbumEntry(:final view) => _Cell.album(view),
              GroupEntry(:final view) => _Cell.group(view),
            },
          ),
          _Cell.action(
            label: context.l10n.newAlbum,
            icon: Icons.add,
            onTap: onNewAlbum,
          ),
          if (recycle != null)
            _Cell.special(view: recycle, icon: Icons.delete_outline),
        ];

        final content = preferences.viewMode == AlbumViewMode.list
            ? ListView.builder(
                key: const ValueKey('invisible-album-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  GridDefaults.gutter,
                  GridDefaults.gutter,
                  GridDefaults.gutter,
                  GridDefaults.bottomClearance +
                      MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: cells.length,
                itemBuilder: (context, i) {
                  final c = cells[i];
                  final v = c.view;
                  final tile = _ShelfListTile(
                    key: ValueKey('list-${c.id}'),
                    cell: c,
                    onTap: () {
                      if (c.onTap != null) {
                        c.onTap!();
                      } else if (v != null) {
                        onOpenAlbum(
                          v.album.id,
                          v.album.name,
                          systemKind: v.album.systemKind,
                        );
                      } else if (c.group != null) {
                        _openGroup(context, c.group!.group.id);
                      }
                    },
                    onLongPress: c.group != null
                        ? () => _groupMenu(context, ref, c.group!)
                        : v != null
                            ? () => _albumMenu(context, ref, v)
                            : null,
                  );
                  if (c.group == null) return tile;
                  return _CollectionSwipeTile(
                    key: ValueKey('swipe-${c.group!.group.id}'),
                    onManage: () => _groupMenu(context, ref, c.group!),
                    child: tile,
                  );
                },
              )
            : GridView.builder(
                key: const ValueKey('invisible-album-grid'),
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
                itemCount: cells.length,
                itemBuilder: (context, i) {
                  final c = cells[i];
                  final v = c.view;
                  final tileKey = v == null && c.group == null
                      ? ValueKey('action-${c.label}')
                      : ValueKey(
                          '${c.id}-${kind.name}-${v?.album.isPinned}-${v?.album.rating}-${v?.count}-${c.group?.totalCount}-${v?.cover?.displayPath ?? c.group?.cover?.cover?.displayPath ?? ''}',
                        );
                  return _MosaicTile(
                    key: tileKey,
                    cell: c,
                    onTap: () {
                      if (c.onTap != null) {
                        c.onTap!();
                        return;
                      }
                      if (v != null) {
                        onOpenAlbum(
                          v.album.id,
                          v.album.name,
                          systemKind: v.album.systemKind,
                        );
                      } else if (c.group != null) {
                        _openGroup(context, c.group!.group.id);
                      }
                    },
                    onLongPress: c.group != null
                        ? () => _groupMenu(context, ref, c.group!)
                        : v != null
                            ? () => _albumMenu(context, ref, v)
                            : null,
                  );
                },
              );

        return RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          onRefresh: () async {
            // Force album views to re-query counts/covers from Drift.
            ref.invalidate(albumsProvider);
            await ref.read(albumsProvider.future);
          },
          child: content,
        );
      },
    );
  }

  Future<void> _albumMenu(
    BuildContext context,
    WidgetRef ref,
    AlbumView view,
  ) async {
    final album = view.album;
    final isUser = album.systemKind == null;
    final canShuffle = album.systemKind != SystemAlbumKind.recycle;
    final canRestore = album.systemKind != SystemAlbumKind.recycle;
    final pinned = album.isPinned;

    final action = await showVaultSheet<String>(
      context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.55;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localizedAlbumTitle(
                            context.l10n,
                            name: album.name,
                            systemKind: album.systemKind,
                            albumId: album.id,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          context.l10n.itemsCount(view.count),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (canShuffle)
                        ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading:
                              const Icon(Icons.shuffle, color: Colors.white70),
                          title: Text(
                            context.l10n.shuffle,
                            style: const TextStyle(color: Colors.white),
                          ),
                          onTap: () => Navigator.pop(ctx, 'shuffle'),
                        ),
                      if (canRestore)
                        ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: const Icon(
                            Icons.unarchive_outlined,
                            color: Colors.white70,
                          ),
                          title: Text(
                            context.l10n.restore,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            context.l10n.unhideAllInAlbum,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () => Navigator.pop(ctx, 'restore'),
                        ),
                      if (isUser)
                        ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: const Icon(
                            Icons.favorite_border,
                            color: Colors.white70,
                          ),
                          title: Text(
                            context.l10n.rate,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            List.filled(album.rating, '♥').join(),
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                          onTap: () => Navigator.pop(ctx, 'rate'),
                        ),
                      if (isUser)
                        ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: const Icon(
                            Icons.layers_outlined,
                            color: Colors.white70,
                          ),
                          title: Text(
                            context.l10n.addToGroup,
                            style: const TextStyle(color: Colors.white),
                          ),
                          onTap: () => Navigator.pop(ctx, 'add_group'),
                        ),
                      if (isUser)
                        ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: const Icon(
                            Icons.drive_file_rename_outline,
                            color: Colors.white70,
                          ),
                          title: Text(
                            context.l10n.rename,
                            style: const TextStyle(color: Colors.white),
                          ),
                          onTap: () => Navigator.pop(ctx, 'rename'),
                        ),
                      if (isUser)
                        ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(
                            pinned ? Icons.push_pin : Icons.push_pin_outlined,
                            color: Colors.white70,
                          ),
                          title: Text(
                            pinned ? context.l10n.unpin : context.l10n.pinToTop,
                            style: const TextStyle(color: Colors.white),
                          ),
                          onTap: () =>
                              Navigator.pop(ctx, pinned ? 'unpin' : 'pin'),
                        ),
                      if (isUser)
                        ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          title: Text(
                            context.l10n.deleteAlbum,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            context.l10n.deleteAlbumSubtitle,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () => Navigator.pop(ctx, 'delete'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case 'shuffle':
        await _shuffleAlbum(context, ref, album);
      case 'restore':
        await _restoreAlbum(context, ref, album);
      case 'rate':
        final rating = await showQuickRatingSheet(
          context,
          currentRating: album.rating,
        );
        if (rating != null) {
          await ref.read(albumRepositoryProvider).setRating(album.id, rating);
        }
      case 'add_group':
        await _addAlbumToGroup(context, ref, album.id);
      case 'rename':
        await _renameAlbum(context, ref, album);
      case 'pin':
        await ref
            .read(albumRepositoryProvider)
            .setPinned(album.id, pinned: true);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.pinnedToTop)),
          );
        }
      case 'unpin':
        await ref
            .read(albumRepositoryProvider)
            .setPinned(album.id, pinned: false);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.unpinned)),
          );
        }
      case 'delete':
        await ref.read(albumRepositoryProvider).deleteUserAlbum(album.id);
    }
  }

  Future<void> _addAlbumToGroup(
    BuildContext context,
    WidgetRef ref,
    String albumId,
  ) async {
    final groups = await ref.read(albumRepositoryProvider).listGroups();
    if (!context.mounted) return;
    final choice = await showVaultSheet<String>(
      context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final group in groups)
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: Text(group.name),
                onTap: () => Navigator.pop(ctx, group.id),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(context.l10n.newGroup),
              onTap: () => Navigator.pop(ctx, '__new__'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    AlbumGroup group;
    if (choice == '__new__') {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.l10n.newGroup),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: context.l10n.groupNameHint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(context.l10n.create),
            ),
          ],
        ),
      );
      if (name == null || name.trim().isEmpty) return;
      group = await ref.read(albumRepositoryProvider).createGroup(name);
    } else {
      group = groups.firstWhere((item) => item.id == choice);
    }
    await ref.read(albumRepositoryProvider).addToGroup(albumId, group.id);
  }

  void _openGroup(BuildContext context, String groupId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupScreen(groupId: groupId),
      ),
    );
  }

  Future<void> _groupMenu(
    BuildContext context,
    WidgetRef ref,
    GroupView group,
  ) async {
    final action = await showVaultSheet<String>(
      context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(context.l10n.manageGroup),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(context.l10n.renameGroup),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.drag_handle),
              title: Text(context.l10n.arrangeOrder),
              onTap: () => Navigator.pop(ctx, 'arrange'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: Text(context.l10n.dissolveGroup),
              onTap: () => Navigator.pop(ctx, 'dissolve'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'open':
        _openGroup(context, group.group.id);
      case 'rename':
        final controller = TextEditingController(text: group.group.name);
        final name = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(context.l10n.renameGroup),
            content: TextField(controller: controller, autofocus: true),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: Text(context.l10n.save),
              ),
            ],
          ),
        );
        if (name != null && name.trim().isNotEmpty) {
          await ref.read(albumRepositoryProvider).renameGroup(
                group.group.id,
                name,
              );
        }
      case 'arrange':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ArrangeAlbumsScreen(
              initialViews: group.members,
              groupId: group.group.id,
            ),
          ),
        );
      case 'dissolve':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(context.l10n.dissolveGroup),
            content: Text(context.l10n.dissolveGroupBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(context.l10n.dissolveGroup),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await ref.read(albumRepositoryProvider).dissolveGroup(group.group.id);
        }
    }
  }

  Future<List<MediaItem>> _mediaForAlbum(WidgetRef ref, Album album) async {
    final kind = ref.read(mediaKindFilterProvider);
    final items =
        await ref.read(albumRepositoryProvider).listMediaForAlbum(album.id);
    return items
        .where((m) => kind == MediaKindFilter.video ? m.isVideo : !m.isVideo)
        .toList(growable: false);
  }

  Future<void> _shuffleAlbum(
    BuildContext context,
    WidgetRef ref,
    Album album,
  ) async {
    final items = await _mediaForAlbum(ref, album);
    if (!context.mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noMediaToPlay)),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          items: List.of(items),
          shuffle: true,
          title: localizedAlbumTitle(
            context.l10n,
            name: album.name,
            systemKind: album.systemKind,
            albumId: album.id,
          ),
        ),
      ),
    );
  }

  Future<void> _restoreAlbum(
    BuildContext context,
    WidgetRef ref,
    Album album,
  ) async {
    final items = await _mediaForAlbum(ref, album);
    if (!context.mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.nothingToRestore)),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.restoreAlbumTitle),
        content: Text(
          context.l10n.restoreAlbumBody(
            items.length,
            localizedAlbumTitle(
              context.l10n,
              name: album.name,
              systemKind: album.systemKind,
              albumId: album.id,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.restore),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final import = ref.read(importControllerProvider.notifier);
    import.beginSession(phase: ImportPhase.unhiding);
    // ignore: unawaited_futures
    showImportProgressSheet(context, title: context.l10n.unhide);

    var n = 0;
    try {
      final result = await import.restoreAlbum(album.id);
      final summary = result.summary;
      n = summary.imported;
      if (!context.mounted) return;
      final msg = StringBuffer();
      if (summary.cancelled && n == 0) {
        msg.write(context.l10n.cancelled);
      } else {
        msg.write(context.l10n.restoredItems(n));
        if (summary.cancelled && n > 0) {
          msg.write(' · ${context.l10n.cancelled}');
        }
        if (summary.failed > 0) {
          msg.write(
            ' · ${context.l10n.failedItems(summary.failed)}',
          );
        }
      }
      messenger.showSnackBar(SnackBar(content: Text(msg.toString())));
    } catch (_) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotUnhideFile)),
        );
      }
    } finally {
      try {
        if (nav.canPop()) nav.pop();
      } catch (_) {}
      import.clearSummary();
    }
  }

  Future<void> _renameAlbum(
    BuildContext context,
    WidgetRef ref,
    Album album,
  ) async {
    final c = TextEditingController(text: album.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.renameAlbum),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(albumRepositoryProvider).rename(album.id, name);
    }
  }
}

class _Cell {
  _Cell._({
    this.view,
    this.group,
    this.icon,
    this.accent = false,
    this.preferCover = false,
    this.action = false,
    this.label,
    this.onTap,
  });

  factory _Cell.album(AlbumView view) => _Cell._(view: view);

  factory _Cell.group(GroupView group) => _Cell._(group: group);

  factory _Cell.special({
    required AlbumView view,
    required IconData icon,
    bool accent = false,
    bool preferCover = false,
  }) =>
      _Cell._(
        view: view,
        icon: icon,
        accent: accent,
        preferCover: preferCover,
      );

  factory _Cell.action({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) =>
      _Cell._(action: true, label: label, icon: icon, onTap: onTap);

  final AlbumView? view;
  final GroupView? group;
  final IconData? icon;
  final bool accent;
  final bool preferCover;
  final bool action;
  final String? label;
  final VoidCallback? onTap;

  String get id => view?.album.id ?? group?.group.id ?? 'action-$label';
}

class _MosaicTile extends StatelessWidget {
  const _MosaicTile({
    super.key,
    required this.cell,
    required this.onTap,
    this.onLongPress,
  });

  final _Cell cell;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final heart = context.vaultColors.heart;
    final view = cell.view;
    final group = cell.group;
    final coverPath =
        view?.cover?.displayPath ?? group?.cover?.cover?.displayPath;
    final useCover = coverPath != null &&
        coverPath.isNotEmpty &&
        (cell.preferCover || cell.icon == null || group != null);

    return Material(
      color: context.vaultColors.chrome,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (useCover)
              Image.file(
                File(coverPath),
                key: ValueKey(coverPath),
                fit: BoxFit.cover,
                gaplessPlayback: false,
                cacheWidth: 512,
                errorBuilder: (_, __, ___) =>
                    ColoredBox(color: context.vaultColors.chrome),
              )
            else if (cell.action || cell.icon != null || group != null)
              ColoredBox(
                color: context.vaultColors.chrome,
                child: Center(
                  child: Icon(
                    group != null ? Icons.layers_outlined : cell.icon,
                    size: 40,
                    color: cell.accent
                        ? heart
                        : Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              )
            else
              ColoredBox(
                color: context.vaultColors.surfaceAlt,
                child: const Center(
                  child: Icon(
                    Icons.photo_album_outlined,
                    color: Colors.white54,
                  ),
                ),
              ),
            if (useCover)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 48,
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
            if (view != null && view.album.isPinned)
              const Positioned(
                top: 6,
                left: 6,
                child: Icon(
                  Icons.push_pin,
                  size: 16,
                  color: Colors.white70,
                ),
              ),
            if (view != null || group != null)
              Positioned(
                top: (cell.icon != null && !useCover) ? 6 : null,
                right: 6,
                bottom: (cell.icon != null && !useCover) ? null : 6,
                child: _Badge('${group?.members.length ?? view?.count ?? 0}'),
              ),
            if (view != null && view.album.rating > 0)
              Positioned(
                left: 6,
                right: 36,
                bottom: 22,
                child: Text(
                  List.filled(view.album.rating, '♥').join(),
                  maxLines: 1,
                  style: TextStyle(
                    color: heart,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    shadows: const [
                      Shadow(blurRadius: 6, color: Colors.black87),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 6,
              right: 36,
              bottom: 6,
              child: Text(
                cell.action
                    ? (cell.label ?? '')
                    : (view == null && group == null
                        ? (cell.label ?? '')
                        : group != null
                            ? group.group.name
                            : localizedAlbumTitle(
                                context.l10n,
                                name: view!.album.name,
                                systemKind: view.album.systemKind,
                                albumId: view.album.id,
                              )),
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

class _CollectionSwipeTile extends StatelessWidget {
  const _CollectionSwipeTile({
    super.key,
    required this.child,
    required this.onManage,
  });

  final Widget child;
  final Future<void> Function() onManage;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: key ?? ValueKey(child),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: ColoredBox(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Icon(Icons.tune),
          ),
        ),
      ),
      confirmDismiss: (_) async {
        await onManage();
        return false;
      },
      child: child,
    );
  }
}

class _ShelfListTile extends StatelessWidget {
  const _ShelfListTile({
    super.key,
    required this.cell,
    required this.onTap,
    this.onLongPress,
  });

  final _Cell cell;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final view = cell.view;
    final group = cell.group;
    final coverPath =
        view?.cover?.displayPath ?? group?.cover?.cover?.displayPath;
    final title = cell.action
        ? cell.label ?? ''
        : view == null && group == null
            ? cell.label ?? ''
            : group != null
                ? group.group.name
                : localizedAlbumTitle(
                    context.l10n,
                    name: view!.album.name,
                    systemKind: view.album.systemKind,
                    albumId: view.album.id,
                  );
    final hearts = view == null || view.album.rating == 0
        ? ''
        : List.filled(view.album.rating, '♥').join();
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: SizedBox.square(
          dimension: 52,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: coverPath != null && coverPath.isNotEmpty
                ? Image.file(
                    File(coverPath),
                    fit: BoxFit.cover,
                    cacheWidth: 192,
                    errorBuilder: (_, __, ___) => _ListIcon(cell: cell),
                  )
                : _ListIcon(cell: cell),
          ),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          group != null
              ? context.l10n.albumsCount(group.members.length)
              : hearts.isEmpty
                  ? context.l10n.itemsCount(view?.count ?? 0)
                  : '$hearts  ${context.l10n.itemsCount(view?.count ?? 0)}',
          style: TextStyle(color: context.vaultColors.heart),
        ),
        trailing: view == null && group == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (view?.album.isPinned == true)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.push_pin, size: 16),
                    ),
                  Text('${group?.members.length ?? view?.count ?? 0}'),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

class _ListIcon extends StatelessWidget {
  const _ListIcon({required this.cell});

  final _Cell cell;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.vaultColors.chrome,
      child: Icon(
        cell.group != null
            ? Icons.layers_outlined
            : cell.icon ?? Icons.photo_album_outlined,
        color: cell.accent
            ? context.vaultColors.heart
            : Colors.white.withValues(alpha: 0.75),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
