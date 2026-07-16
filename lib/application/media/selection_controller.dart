import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Multi-select set for the media grid (selection + action bar).
class SelectionController extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  bool get isSelecting => state.isNotEmpty;

  void enter(String id) => state = {id};

  void toggle(String id) {
    final next = Set<String>.from(state);
    if (!next.add(id)) next.remove(id);
    state = next;
  }

  void clear() => state = {};

  void selectAll(Iterable<String> ids) => state = ids.toSet();
}

final selectionControllerProvider =
    NotifierProvider<SelectionController, Set<String>>(
  SelectionController.new,
);
