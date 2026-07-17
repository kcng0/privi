import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'selectable_grid_controller.dart';

/// Multi-select set for the media grid (selection + action bar).
class SelectionController extends Notifier<Set<String>> {
  final _selection = SelectableGridController<String>();

  @override
  Set<String> build() {
    void sync() => state = Set.unmodifiable(_selection.selected);
    _selection.addListener(sync);
    ref.onDispose(() {
      _selection
        ..removeListener(sync)
        ..dispose();
    });
    return const {};
  }

  bool get isSelecting => _selection.isSelecting;

  void enter(String id) => _selection.enter(id);

  void toggle(String id) => _selection.toggle(id);

  void clear() => _selection.exit();

  void selectAll(Iterable<String> ids) => _selection.selectAll(ids);
}

final selectionControllerProvider =
    NotifierProvider<SelectionController, Set<String>>(
  SelectionController.new,
);
