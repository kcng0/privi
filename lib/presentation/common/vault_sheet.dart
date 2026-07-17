import 'package:flutter/material.dart';

import '../../core/theme/vault_colors.dart';

/// Shared dark sheet shell used across gallery and vault actions.
Future<T?> showVaultSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool showDragHandle = true,
  bool isScrollControlled = false,
  ShapeBorder? shape,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: showDragHandle,
    isScrollControlled: isScrollControlled,
    backgroundColor: context.vaultColors.chrome,
    shape: shape,
    builder: builder,
  );
}
