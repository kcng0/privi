import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/gallery/gallery_controller.dart';
import '../../application/import/import_controller.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../core/theme/vault_colors.dart';
import '../../domain/enums.dart';
import '../../domain/models/album_view.dart';
import '../grid/media_grid_screen.dart';
import '../import/import_progress_sheet.dart';
import '../settings/settings_screen.dart';
import '../visible/visible_folder_grid.dart';

/// HD Smith home: safe top chrome + Visible (gallery folders) | Invisible (vault).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  static const _chrome = Color(0xFF1B3A36);

  @override
  void initState() {
    super.initState();
    // Default Invisible after unlock (vault) — same as HD Smith.
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

  Future<void> _import({String? albumId}) async {
    final messenger = ScaffoldMessenger.of(context);
    // ignore: unawaited_futures
    showImportProgressSheet(context);
    final summary = await ref
        .read(importControllerProvider.notifier)
        .pickAndImport(targetUserAlbumId: albumId);
    if (mounted) Navigator.of(context).pop();
    if (summary == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Hidden ${summary.imported} items')),
    );
    ref.read(importControllerProvider.notifier).clearSummary();
  }

  Future<void> _newAlbum() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New album'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Album name'),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final album =
        await ref.read(albumRepositoryProvider).createUserAlbum(name);
    if (!mounted) return;
    _openAlbum(album.id, album.name);
  }

  void _openAlbum(String id, String name) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaGridScreen(albumId: id, title: name),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  void _menu() {
    final onVisible = _tabs.index == 0;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!onVisible)
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('Import files'),
                subtitle: const Text('File picker · fallback to Visible hide'),
                onTap: () {
                  Navigator.pop(ctx);
                  _import();
                },
              ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New vault album'),
              onTap: () {
                Navigator.pop(ctx);
                _newAlbum();
              },
            ),
            ListTile(
              leading: const Icon(Icons.grid_view),
              title: const Text('Album columns'),
              subtitle: const Text('3 or 4 columns on Invisible'),
              onTap: () {
                Navigator.pop(ctx);
                _cycleAlbumColumns();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(ctx);
                _openSettings();
              },
            ),
          ],
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
          f == MediaKindFilter.image ? 'Photos only' : 'Videos only',
        ),
        duration: const Duration(milliseconds: 800),
      ),
    );
    ref.read(galleryServiceProvider).invalidateCache();
    ref.read(galleryUiEpochProvider.notifier).bump();
    ref.invalidate(galleryFoldersProvider);
  }

  Future<void> _cycleAlbumColumns() async {
    final s = ref.read(settingsControllerProvider);
    final next = s.albumColumns >= 4 ? 3 : 4;
    await ref.read(settingsControllerProvider.notifier).setAlbumColumns(next);
    if (!mounted) return;
    // ignore: unawaited_futures
    HapticFeedback.selectionClick();
  }

  IconData _filterIcon(MediaKindFilter f) {
    return f == MediaKindFilter.image
        ? Icons.image_outlined
        : Icons.videocam_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(mediaKindFilterProvider);
    // Status bar + notch: MediaQuery padding, never hug the physical top edge.
    final topInset = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF101412),
        // Do NOT use SafeArea alone — chrome paints into status area deliberately
        // but content starts below it with generous padding (HD Smith feel).
        body: Column(
          children: [
            // ── Top chrome ──────────────────────────────────────
            ColoredBox(
              color: _chrome,
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
                          tabs: const [
                            Tab(
                              height: 52,
                              icon: Icon(Icons.photo_camera_outlined, size: 18),
                              text: 'Visible',
                              iconMargin: EdgeInsets.only(bottom: 2),
                            ),
                            Tab(
                              height: 52,
                              icon: Icon(Icons.lock, size: 18),
                              text: 'Invisible',
                              iconMargin: EdgeInsets.only(bottom: 2),
                            ),
                          ],
                        ),
                      ),
                      // Photo XOR video mode — same control on Visible & Invisible.
                      IconButton(
                        tooltip: filter == MediaKindFilter.image
                            ? 'Photos only · tap for videos'
                            : 'Videos only · tap for photos',
                        icon: Icon(_filterIcon(filter), size: 22),
                        color: Colors.white70,
                        onPressed: _toggleMediaFilter,
                      ),
                      IconButton(
                        tooltip: 'More',
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

  final void Function(String id, String name) onOpenAlbum;
  final VoidCallback onNewAlbum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumsAsync = ref.watch(albumsProvider);
    final cols = ref.watch(settingsControllerProvider).albumColumns;

    return albumsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (views) {
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
          _Cell.action(
            label: 'New album',
            icon: Icons.add,
            onTap: onNewAlbum,
          ),
          ...user.map(_Cell.album),
          if (recycle != null)
            _Cell.special(view: recycle, icon: Icons.delete_outline),
        ];

        return RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          onRefresh: () async {
            // Force album views to re-query counts/covers from Drift.
            ref.invalidate(albumsProvider);
            await ref.read(albumsProvider.future);
          },
          child: GridView.builder(
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
              // Key includes count + cover path so Image.file rebuilds after hide.
              final tileKey = v == null
                  ? ValueKey('action-${c.label}')
                  : ValueKey(
                      '${v.album.id}-${v.count}-${v.cover?.displayPath ?? ''}-${v.cover?.id ?? ''}',
                    );
              return _MosaicTile(
                key: tileKey,
                cell: c,
                onTap: () {
                  if (c.onTap != null) {
                    c.onTap!();
                    return;
                  }
                  if (v != null) onOpenAlbum(v.album.id, v.album.name);
                },
                onLongPress: v != null && v.album.systemKind == null
                    ? () => _albumMenu(context, ref, v)
                    : null,
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _albumMenu(
    BuildContext context,
    WidgetRef ref,
    AlbumView view,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(view.album.name),
              subtitle: Text('${view.count} items'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete album'),
              subtitle: const Text('Media stays in All Media'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'delete') {
      await ref.read(albumRepositoryProvider).deleteUserAlbum(view.album.id);
      return;
    }
    if (action == 'rename') {
      final c = TextEditingController(text: view.album.name);
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename album'),
          content: TextField(controller: c, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (name != null && name.trim().isNotEmpty) {
        await ref.read(albumRepositoryProvider).rename(view.album.id, name);
      }
    }
  }
}

class _Cell {
  _Cell._({
    this.view,
    this.icon,
    this.accent = false,
    this.preferCover = false,
    this.action = false,
    this.label,
    this.onTap,
  });

  factory _Cell.album(AlbumView view) => _Cell._(view: view);

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
  final IconData? icon;
  final bool accent;
  final bool preferCover;
  final bool action;
  final String? label;
  final VoidCallback? onTap;
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
    final coverPath = view?.cover?.displayPath;
    final useCover = coverPath != null &&
        coverPath.isNotEmpty &&
        File(coverPath).existsSync() &&
        (cell.preferCover || cell.icon == null);

    return Material(
      color: const Color(0xFF1B3A36),
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
                    const ColoredBox(color: Color(0xFF1B3A36)),
              )
            else if (cell.action || cell.icon != null)
              ColoredBox(
                color: const Color(0xFF1B3A36),
                child: Center(
                  child: Icon(
                    cell.icon,
                    size: 40,
                    color: cell.accent
                        ? heart
                        : Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              )
            else
              const ColoredBox(
                color: Color(0xFF244842),
                child: Center(
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
                      colors: [Colors.transparent, Color(0xCC000000)],
                    ),
                  ),
                ),
              ),
            if (view != null)
              Positioned(
                top: (cell.icon != null && !useCover) ? 6 : null,
                right: 6,
                bottom: (cell.icon != null && !useCover) ? null : 6,
                child: _Badge('${view.count}'),
              ),
            Positioned(
              left: 6,
              right: 36,
              bottom: 6,
              child: Text(
                cell.action
                    ? (cell.label ?? '')
                    : (view?.album.name ?? cell.label ?? ''),
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
