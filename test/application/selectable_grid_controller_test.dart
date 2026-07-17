import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/media/selectable_grid_controller.dart';

void main() {
  test('enter, toggle, select all, and exit share one selection contract', () {
    final controller = SelectableGridController<String>();
    addTearDown(controller.dispose);

    controller.enter('a');
    expect(controller.isSelecting, isTrue);
    expect(controller.selected, {'a'});
    final firstSnapshot = controller.selected;

    controller.toggle('b');
    expect(controller.selected, {'a', 'b'});
    expect(firstSnapshot, {'a'});

    controller.toggle('a');
    controller.toggle('b');
    expect(controller.isSelecting, isFalse);
    expect(controller.selected, isEmpty);

    controller.selectAll(['x', 'y']);
    expect(controller.selected, {'x', 'y'});

    controller.exit();
    expect(controller.isSelecting, isFalse);
    expect(controller.selected, isEmpty);
  });
}
