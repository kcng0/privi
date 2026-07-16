import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/vault_colors.dart';

/// Root of the app. Dark theme only (docs/02-design/design-system.md).
///
/// The home is a placeholder until Phase 1 (lock gate + Home/Albums) lands.
/// See docs/04-implementation/roadmap.md.
class PrivateHeartApp extends StatelessWidget {
  const PrivateHeartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PrivateHeart Vault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const _ScaffoldPlaceholder(),
    );
  }
}

class _ScaffoldPlaceholder extends StatelessWidget {
  const _ScaffoldPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('PrivateHeart')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite, size: 48, color: context.vaultColors.heart),
            const SizedBox(height: 16),
            Text('Vault scaffold ready', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Phase 1 begins next — see docs/04-implementation/roadmap.md',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
