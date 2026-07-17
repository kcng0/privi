import 'package:flutter/foundation.dart';

/// Reusable selection state for Visible and Invisible media grids.
class SelectableGridController<T> extends ChangeNotifier {
  final Set<T> _selected = <T>{};
  bool _isSelecting = false;

  bool get isSelecting => _isSelecting;
  Set<T> get selected => Set<T>.unmodifiable(_selected);

  void enter(T item) {
    _isSelecting = true;
    _selected
      ..clear()
      ..add(item);
    notifyListeners();
  }

  void toggle(T item) {
    if (!_selected.add(item)) _selected.remove(item);
    _isSelecting = _selected.isNotEmpty;
    notifyListeners();
  }

  void exit() {
    if (!_isSelecting && _selected.isEmpty) return;
    _isSelecting = false;
    _selected.clear();
    notifyListeners();
  }

  void selectAll(Iterable<T> items) {
    _selected
      ..clear()
      ..addAll(items);
    _isSelecting = _selected.isNotEmpty;
    notifyListeners();
  }
}
