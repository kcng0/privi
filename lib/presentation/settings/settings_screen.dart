import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/lock/lock_controller.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../data/services/secure_window_service.dart';
import '../lock/pattern_lock.dart';

/// Full settings — security, display, playback, storage export/import.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsControllerProvider);
    final lock = ref.watch(lockControllerProvider);
    final notifier = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), centerTitle: true),
      body: ListView(
        children: [
          const _SectionHeader('Security'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Lock now'),
            onTap: () {
              ref.read(lockControllerProvider.notifier).lock();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          ListTile(
            leading: const Icon(Icons.gesture),
            title: const Text('Change pattern'),
            subtitle: const Text('Root unlock credential'),
            onTap: () => _changePattern(context, ref),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Biometric unlock'),
            subtitle: Text(
              lock.biometricAvailable
                  ? 'Fingerprint / face when available'
                  : 'Not available on this device',
            ),
            value: lock.biometricEnabled && lock.biometricAvailable,
            onChanged: !lock.biometricAvailable
                ? null
                : (v) async {
                    try {
                      final ok = await ref
                          .read(lockControllerProvider.notifier)
                          .setBiometricEnabled(v);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              v
                                  ? 'Biometric not enabled (cancelled or failed)'
                                  : 'Could not update biometric setting',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    }
                  },
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Auto-lock'),
            subtitle: Text(_autoLockLabel(s.autoLockSeconds)),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: 'Auto-lock',
                options: const {
                  'Immediately': 0,
                  '30 seconds': 30,
                  '1 minute': 60,
                  '5 minutes': 300,
                },
                current: s.autoLockSeconds,
              );
              if (v != null) await notifier.setAutoLockSeconds(v);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.screenshot_monitor_outlined),
            title: const Text('Block screenshots'),
            subtitle: const Text('FLAG_SECURE — hide content in recents'),
            value: s.flagSecure,
            onChanged: (v) async {
              await notifier.setFlagSecure(v);
              await SecureWindowService().setFlagSecure(v);
            },
          ),
          const _SectionHeader('Display'),
          ListTile(
            leading: const Icon(Icons.grid_view),
            title: const Text('Media grid columns'),
            subtitle: Text('${s.gridColumns}'),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: 'Grid columns',
                options: const {'2': 2, '3': 3, '4': 4, '5': 5},
                current: s.gridColumns,
              );
              if (v != null) await notifier.setGridColumns(v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_album_outlined),
            title: const Text('Album grid columns'),
            subtitle: Text('${s.albumColumns}'),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: 'Album columns',
                options: const {'3': 3, '4': 4},
                current: s.albumColumns,
              );
              if (v != null) await notifier.setAlbumColumns(v);
            },
          ),
          const _SectionHeader('Playback'),
          SwitchListTile(
            secondary: const Icon(Icons.open_in_new),
            title: const Text('Prefer external player'),
            subtitle: const Text('Hand off videos to VLC / system player'),
            value: s.playerExternal,
            onChanged: notifier.setPlayerExternal,
          ),
          ListTile(
            leading: const Icon(Icons.slideshow_outlined),
            title: const Text('Slideshow delay'),
            subtitle: Text('${s.slideshowSeconds}s'),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: 'Slideshow delay',
                options: const {
                  '1 second': 1,
                  '3 seconds': 3,
                  '5 seconds': 5,
                  '10 seconds': 10,
                },
                current: s.slideshowSeconds,
              );
              if (v != null) await notifier.setSlideshowSeconds(v);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.shuffle),
            title: const Text('Shuffle by default'),
            value: s.shuffleDefault,
            onChanged: notifier.setShuffleDefault,
          ),
          const _SectionHeader('Storage'),
          Consumer(
            builder: (context, ref, _) {
              final sizeAsync = ref.watch(vaultSizeBytesProvider);
              final subtitle = sizeAsync.when(
                data: (b) => _formatBytes(b),
                loading: () => 'Calculating…',
                error: (_, __) => '—',
              );
              return ListTile(
                leading: const Icon(Icons.sd_storage_outlined),
                title: const Text('Vault size'),
                subtitle: Text(subtitle),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.find_in_page_outlined),
            title: const Text('Scan orphan hidden files'),
            subtitle: const Text(
              'Re-index *.vid.pg / *.img.pg on disk without a DB row',
            ),
            onTap: () => _scanOrphans(context, ref),
          ),
          const ListTile(
            leading: Icon(Icons.visibility_off_outlined),
            title: Text('Hide verification'),
            subtitle: Text(
              'After Hide, confirm items leave Gallery / Photos on this device',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Recycle Bin retention'),
            subtitle: Text('${s.recycleRetentionDays} days'),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: 'Retention',
                options: const {
                  '1 day': 1,
                  '7 days': 7,
                  '30 days': 30,
                },
                current: s.recycleRetentionDays,
              );
              if (v != null) await notifier.setRecycleRetentionDays(v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: const Text('Empty Recycle Bin'),
            onTap: () => _emptyRecycle(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Export vault…'),
            subtitle: const Text('Media + metadata to a folder'),
            onTap: () => _export(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Import / Restore…'),
            subtitle: const Text('From a previous export folder'),
            onTap: () => _importBackup(context, ref),
          ),
          const _SectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text(AppInfo.name),
            subtitle: Text(
              'v${AppInfo.version} · ${AppInfo.licenseShort}',
            ),
            onTap: () => _showAbout(context),
          ),
          const ListTile(
            leading: Icon(Icons.person_outline),
            title: Text('Author'),
            subtitle: Text('${AppInfo.author} · ${AppInfo.authorUrl}'),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('License'),
            subtitle: const Text(AppInfo.licenseShort),
            onTap: () => _showLicense(context),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/branding/app_icon_192.png',
                width: 40,
                height: 40,
                errorBuilder: (_, __, ___) => const Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text(AppInfo.name)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppInfo.tagline,
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              Text(AppInfo.about),
              const SizedBox(height: 16),
              Text(
                'Version ${AppInfo.version}',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              Text(
                'Author: ${AppInfo.author}',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              Text(
                AppInfo.authorUrl,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                AppInfo.licenseShort,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showLicense(context);
            },
            child: const Text('License'),
          ),
        ],
      ),
    );
  }

  void _showLicense(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('License'),
        content: const SingleChildScrollView(
          child: Text(AppInfo.licenseBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _changePattern(BuildContext context, WidgetRef ref) async {
    final lock = ref.read(lockControllerProvider);
    final String? current;
    if (lock.usesPattern) {
      current = await _promptPattern(
        context,
        title: 'Current pattern',
        subtitle: 'Draw your current pattern to continue',
      );
    } else {
      current = await _promptPin(
        context,
        title: 'Current PIN',
        subtitle: 'Enter PIN, then set a new pattern',
      );
    }
    if (current == null || !context.mounted) return;
    final next = await _promptPattern(
      context,
      title: 'New pattern',
      subtitle: 'Connect at least 4 dots',
    );
    if (next == null || !context.mounted) return;
    final confirm = await _promptPattern(
      context,
      title: 'Confirm new pattern',
      subtitle: 'Draw the same pattern again',
    );
    if (confirm == null || !context.mounted) return;
    if (next != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New patterns did not match')),
      );
      return;
    }
    try {
      if (lock.usesPattern) {
        await ref.read(lockControllerProvider.notifier).changePattern(
              currentPattern: current,
              newPattern: next,
            );
      } else {
        await ref.read(lockControllerProvider.notifier).migratePinToPattern(
              currentPin: current,
              newPattern: next,
            );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pattern updated')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<String?> _promptPattern(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(subtitle, style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 16),
              PatternLock(
                size: 240,
                onCompleted: (p) => Navigator.pop(ctx, p),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptPin(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(subtitle, style: Theme.of(ctx).textTheme.bodySmall),
            TextField(
              controller: ctrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'PIN'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    return ctrl.text;
  }

  Future<void> _scanOrphans(BuildContext context, WidgetRef ref) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scanning for orphan hidden files…')),
    );
    try {
      final msg =
          await ref.read(maintenanceServiceProvider).scanOrphanHiddenFiles();
      ref.invalidate(vaultSizeBytesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  Future<void> _emptyRecycle(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty Recycle Bin?'),
        content: const Text('Permanently delete all soft-deleted items.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Empty'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final media = ref.read(mediaRepositoryProvider);
    final items = await ref.read(databaseProvider).watchRecycleBin().first;
    for (final r in items) {
      await media.purge(r.id);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purged ${items.length} items')),
      );
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Export vault to folder',
    );
    if (dir == null) return;
    try {
      final n =
          await ref.read(vaultBackupServiceProvider).exportToDirectory(dir);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported $n media files + manifest')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Import vault from folder',
    );
    if (dir == null) return;
    try {
      final n =
          await ref.read(vaultBackupServiceProvider).importFromDirectory(dir);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored $n items')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  String _autoLockLabel(int s) {
    if (s <= 0) return 'Immediately';
    if (s < 60) return '$s seconds';
    return '${s ~/ 60} minute${s >= 120 ? 's' : ''}';
  }

  Future<T?> _pick<T>(
    BuildContext context, {
    required String title,
    required Map<String, T> options,
    required T current,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final e in options.entries)
              ListTile(
                title: Text(e.key),
                trailing: e.value == current
                    ? Icon(
                        Icons.check,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(ctx, e.value),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}
