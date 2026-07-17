import 'package:flutter/material.dart';

import '../../core/theme/vault_colors.dart';

/// Shared page chrome for Visible and Invisible media grids.
class MediaGridScaffold<T> extends StatelessWidget {
  const MediaGridScaffold({
    super.key,
    required this.title,
    required this.body,
    this.leading,
    this.actions = const [],
    this.floatingAction,
  });

  final Widget title;
  final Widget body;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? floatingAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vaultColors.surface,
      appBar: AppBar(
        backgroundColor: context.vaultColors.chrome,
        centerTitle: true,
        leading: leading,
        title: title,
        actions: actions,
      ),
      body: body,
      floatingActionButton: floatingAction,
    );
  }
}
