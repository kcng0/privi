import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/media/album_list_preferences.dart';
import '../../application/providers.dart';
import '../../core/l10n.dart';
import '../../domain/enums.dart';
import '../../domain/models/album_view.dart';
import '../../domain/models/shelf_entry.dart';

class ArrangeAlbumsScreen extends ConsumerStatefulWidget {
  const ArrangeAlbumsScreen({
    super.key,
    this.initialViews = const [],
    this.groupId,
    this.initialEntries,
    this.onSave,
  });

  final List<AlbumView> initialViews;
  final String? groupId;
  final List<ShelfEntry>? initialEntries;
  final Future<void> Function(Map<String, int> indexes)? onSave;

  @override
  ConsumerState<ArrangeAlbumsScreen> createState() =>
      _ArrangeAlbumsScreenState();
}

class _ArrangeAlbumsScreenState extends ConsumerState<ArrangeAlbumsScreen> {
  late List<ShelfEntry> _working;
  late final List<String> _initialIds;
  var _saving = false;
  var _allowPop = false;

  bool get _dirty {
    final current = _working.map((entry) => entry.id).toList();
    if (current.length != _initialIds.length) return true;
    for (var i = 0; i < current.length; i++) {
      if (current[i] != _initialIds[i]) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _working = List<ShelfEntry>.of(
      widget.initialEntries ?? widget.initialViews.map(AlbumEntry.new),
    );
    _initialIds = _working.map((entry) => entry.id).toList(growable: false);
  }

  Future<void> _save() async {
    if (!_dirty || _saving) return;
    setState(() => _saving = true);
    try {
      final albumIndexes = <String, int>{};
      final groupIndexes = <String, int>{};
      for (var i = 0; i < _working.length; i++) {
        final entry = _working[i];
        if (entry is AlbumEntry) albumIndexes[entry.view.album.id] = i;
        if (entry is GroupEntry) groupIndexes[entry.view.group.id] = i;
      }
      if (widget.onSave != null && groupIndexes.isEmpty) {
        await widget.onSave!(albumIndexes);
      } else if (widget.groupId == null) {
        await ref.read(albumRepositoryProvider).setShelfSortIndexes(
              albumIndexes: albumIndexes,
              groupIndexes: groupIndexes,
            );
      } else {
        await ref.read(albumRepositoryProvider).setSortIndexes(albumIndexes);
      }
      if (widget.groupId == null) {
        await ref.read(albumListPreferencesProvider.notifier).setSorting(
          const [AlbumSort.custom],
          multiSortEnabled: false,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.orderSaved)),
      );
      _allowPop = true;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.errorWithDetails('$error'))),
      );
    }
  }

  Future<void> _confirmPop(bool didPop) async {
    if (didPop || _allowPop) return;
    if (!_dirty) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.unsavedChanges),
        content: Text(context.l10n.unsavedChangesBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.discardChanges),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) => _confirmPop(didPop),
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.arrangeOrder),
          actions: [
            TextButton(
              onPressed: _dirty && !_saving ? _save : null,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.l10n.save),
            ),
          ],
        ),
        body: ReorderableListView.builder(
          itemCount: _working.length,
          onReorderItem: (oldIndex, newIndex) {
            setState(() {
              final item = _working.removeAt(oldIndex);
              _working.insert(newIndex, item);
            });
          },
          itemBuilder: (context, index) {
            final entry = _working[index];
            final title = switch (entry) {
              AlbumEntry(:final view) => view.album.name,
              GroupEntry(:final view) => view.group.name,
            };
            final count = switch (entry) {
              AlbumEntry(:final view) => context.l10n.itemsCount(view.count),
              GroupEntry(:final view) =>
                context.l10n.albumsCount(view.members.length),
            };
            return ListTile(
              key: ValueKey(entry.id),
              leading: Icon(
                entry is GroupEntry
                    ? Icons.layers_outlined
                    : Icons.photo_album_outlined,
              ),
              title: Text(title),
              subtitle: Text(count),
              trailing: ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

typedef ArrangeScreen = ArrangeAlbumsScreen;
