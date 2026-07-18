import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/gallery/gallery_controller.dart';
import '../../application/import/import_controller.dart';
import '../../application/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme/vault_colors.dart';
import '../../data/services/import/import_models.dart';
import '../../domain/enums.dart';
import '../../domain/models/album_view.dart';
import '../../domain/models/group_view.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/shelf_entry.dart';
import '../common/quick_rating_sheet.dart';
import '../common/vault_sheet.dart';
import '../grid/media_grid_screen.dart';
import '../import/import_progress_sheet.dart';
import '../player/player_screen.dart';
import 'arrange_albums_screen.dart';

class GroupScreen extends ConsumerWidget {
  const GroupScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelf = ref.watch(albumShelfProvider);
    GroupView? group;
    shelf.whenData((value) {
      for (final entry in value.entries) {
        if (entry is GroupEntry && entry.view.group.id == groupId) {
          group = entry.view;
          break;
        }
      }
    });
    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.emptyGroup)),
        body: Center(child: Text(context.l10n.emptyGroup)),
      );
    }
    return _GroupContent(group: group!);
  }
}

class _GroupContent extends ConsumerWidget {
  const _GroupContent({required this.group});

  final GroupView group;

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final action = await showVaultSheet<String>(
      context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.shuffle),
              title: Text(context.l10n.shuffle),
              onTap: () => Navigator.pop(ctx, 'shuffle'),
            ),
            ListTile(
              leading: const Icon(Icons.unarchive_outlined),
              title: Text(context.l10n.restore),
              onTap: () => Navigator.pop(ctx, 'restore'),
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
          await ref
              .read(albumRepositoryProvider)
              .renameGroup(group.group.id, name);
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
          if (context.mounted) Navigator.of(context).pop();
        }
    }
  }

  Future<void> _memberMenu(
    BuildContext context,
    WidgetRef ref,
    int index,
  ) async {
    final view = group.members[index];
    final action = await showVaultSheet<String>(
      context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: Text(context.l10n.rate),
              onTap: () => Navigator.pop(ctx, 'rate'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(context.l10n.rename),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: Icon(
                view.album.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              title: Text(
                view.album.isPinned
                    ? context.l10n.unpin
                    : context.l10n.pinToTop,
              ),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: Text(context.l10n.removeFromGroup),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text(context.l10n.deleteAlbum),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'shuffle') {
      await _shuffle(context, ref, view);
    } else if (action == 'restore') {
      await _restore(context, ref, view);
    } else if (action == 'rate') {
      final rating = await showQuickRatingSheet(
        context,
        currentRating: view.album.rating,
      );
      if (rating != null) {
        await ref
            .read(albumRepositoryProvider)
            .setRating(view.album.id, rating);
      }
    } else if (action == 'rename') {
      final controller = TextEditingController(text: view.album.name);
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.l10n.renameAlbum),
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
        await ref.read(albumRepositoryProvider).rename(view.album.id, name);
      }
    } else if (action == 'pin') {
      await ref.read(albumRepositoryProvider).setPinned(
            view.album.id,
            pinned: !view.album.isPinned,
          );
    } else if (action == 'remove') {
      await ref.read(albumRepositoryProvider).removeFromGroup(view.album.id);
    } else if (action == 'delete') {
      await ref.read(albumRepositoryProvider).deleteUserAlbum(view.album.id);
    }
  }

  Future<List<MediaItem>> _mediaForAlbum(WidgetRef ref, String albumId) async {
    final kind = ref.read(mediaKindFilterProvider);
    final items =
        await ref.read(albumRepositoryProvider).listMediaForAlbum(albumId);
    return items
        .where(
          (item) =>
              kind == MediaKindFilter.video ? item.isVideo : !item.isVideo,
        )
        .toList(growable: false);
  }

  Future<void> _shuffle(
    BuildContext context,
    WidgetRef ref,
    AlbumView view,
  ) async {
    final items = await _mediaForAlbum(ref, view.album.id);
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
          title: view.album.name,
        ),
      ),
    );
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    AlbumView view,
  ) async {
    final items = await _mediaForAlbum(ref, view.album.id);
    if (!context.mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.nothingToRestore)),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.restoreAlbumTitle),
        content: Text(
          context.l10n.restoreAlbumBody(items.length, view.album.name),
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
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final import = ref.read(importControllerProvider.notifier);
    import.beginSession(phase: ImportPhase.unhiding);
    // ignore: unawaited_futures
    showImportProgressSheet(context, title: context.l10n.unhide);
    try {
      final result = await import.restoreAlbum(view.album.id);
      if (!context.mounted) return;
      final summary = result.summary;
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.restoredItems(summary.imported))),
      );
    } catch (_) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotUnhideFile)),
        );
      }
    } finally {
      if (navigator.canPop()) navigator.pop();
      import.clearSummary();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(group.group.name),
        actions: [
          IconButton(
            tooltip: context.l10n.more,
            onPressed: () => _menu(context, ref),
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: group.members.isEmpty
          ? Center(child: Text(context.l10n.emptyGroup))
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: group.members.length,
              itemBuilder: (context, index) {
                final view = group.members[index];
                final path = view.cover?.displayPath;
                return Material(
                  color: context.vaultColors.chrome,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MediaGridScreen(
                          albumId: view.album.id,
                          title: view.album.name,
                        ),
                      ),
                    ),
                    onLongPress: () => _memberMenu(context, ref, index),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (path != null && path.isNotEmpty)
                          Image.file(File(path), fit: BoxFit.cover)
                        else
                          const Icon(Icons.photo_album_outlined),
                        Positioned(
                          left: 6,
                          right: 6,
                          bottom: 6,
                          child: Text(
                            view.album.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              shadows: [Shadow(blurRadius: 5)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
