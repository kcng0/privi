import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/backup/vault_backup_controller.dart';
import '../../application/lock/biometric_ui.dart';
import '../../application/lock/lock_controller.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../data/services/maintenance_service.dart';
import '../../data/services/vault_backup_service.dart';
import '../lock/pattern_lock.dart';
import 'app_update_tile.dart';
import 'vault_backup_progress_dialog.dart';

/// Full settings — security, display, playback, storage export/import.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsControllerProvider);
    final lock = ref.watch(lockControllerProvider);
    final privacyShield = ref.watch(privacyShieldProvider);
    final externalPlaybackSupported =
        ref.watch(externalPlayerGatewayProvider).supported;
    final appBuildInfo = ref.watch(appBuildInfoProvider);
    final backupBusy = ref.watch(
      vaultBackupControllerProvider.select((state) => state.busy),
    );
    final versionAndPatch = [
      appBuildInfo.versionAndBuild,
      if (appBuildInfo.patchNumber case final patchNumber?)
        context.l10n.patchLabel(patchNumber),
    ].join(' · ');
    final notifier = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settings), centerTitle: true),
      body: ListView(
        children: [
          _SectionHeader(context.l10n.sectionSecurity),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(context.l10n.lockNow),
            onTap: () {
              ref.read(lockControllerProvider.notifier).lock();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          ListTile(
            leading: const Icon(Icons.gesture),
            title: Text(context.l10n.changePattern),
            subtitle: Text(context.l10n.rootUnlockCredential),
            onTap: () => _changePattern(context, ref),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: Text(context.l10n.biometricUnlock),
            subtitle: Text(
              lock.biometricAvailable
                  ? context.l10n.biometricAvailable
                  : context.l10n.biometricUnavailable,
            ),
            value: lock.biometricEnabled && lock.biometricAvailable,
            onChanged: !lock.biometricAvailable
                ? null
                : (v) async {
                    try {
                      final ok = await ref.setBiometricEnabledUi(context, v);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              v
                                  ? context.l10n.biometricCancelled
                                  : context.l10n.biometricUpdateFailed,
                            ),
                          ),
                        );
                      }
                    } catch (e, stackTrace) {
                      debugPrint('biometric setting update: $e\n$stackTrace');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.l10n.biometricUpdateFailed),
                          ),
                        );
                      }
                    }
                  },
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(context.l10n.autoLock),
            subtitle: Text(_autoLockLabel(context, s.autoLockSeconds)),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: context.l10n.autoLock,
                options: {
                  context.l10n.autoLockImmediately: 0,
                  context.l10n.autoLockSeconds(30): 30,
                  context.l10n.autoLockMinutes(1): 60,
                  context.l10n.autoLockMinutesPlural(5): 300,
                },
                current: s.autoLockSeconds,
              );
              if (v != null) await notifier.setAutoLockSeconds(v);
            },
          ),
          SwitchListTile(
            secondary: Icon(
              privacyShield.capabilities.screenshotsBlocked
                  ? Icons.screenshot_monitor_outlined
                  : Icons.privacy_tip_outlined,
            ),
            title: Text(
              privacyShield.capabilities.screenshotsBlocked
                  ? context.l10n.blockScreenshots
                  : context.l10n.protectAppPreview,
            ),
            subtitle: privacyShield.capabilities.screenshotsBlocked
                ? null
                : Text(context.l10n.protectAppPreviewSubtitle),
            value: s.flagSecure,
            onChanged: (v) async {
              try {
                await ref.read(privacyShieldProvider).apply(v);
                await notifier.setFlagSecure(v);
              } catch (e, stackTrace) {
                debugPrint('privacy shield setting: $e\n$stackTrace');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        privacyShield.capabilities.screenshotsBlocked
                            ? context.l10n.screenshotSettingFailed
                            : context.l10n.privacySettingFailed,
                      ),
                    ),
                  );
                }
              }
            },
          ),
          _SectionHeader(context.l10n.sectionDisplay),
          ListTile(
            leading: const Icon(Icons.grid_view),
            title: Text(context.l10n.mediaGridColumns),
            subtitle: Text('${s.gridColumns}'),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: context.l10n.mediaGridColumns,
                options: const {'2': 2, '3': 3, '4': 4, '5': 5},
                current: s.gridColumns,
              );
              if (v != null) await notifier.setGridColumns(v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_album_outlined),
            title: Text(context.l10n.albumColumns),
            subtitle: Text('${s.albumColumns}'),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: context.l10n.albumColumns,
                options: const {'3': 3, '4': 4},
                current: s.albumColumns,
              );
              if (v != null) await notifier.setAlbumColumns(v);
            },
          ),
          _SectionHeader(context.l10n.sectionPlayback),
          if (externalPlaybackSupported)
            SwitchListTile(
              secondary: const Icon(Icons.open_in_new),
              title: Text(context.l10n.preferExternalPlayer),
              subtitle: Text(context.l10n.preferExternalPlayer),
              value: s.playerExternal,
              onChanged: notifier.setPlayerExternal,
            )
          else
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(context.l10n.inAppPlayback),
              subtitle: Text(context.l10n.externalPlaybackUnsupported),
            ),
          ListTile(
            leading: const Icon(Icons.slideshow_outlined),
            title: Text(context.l10n.slideshowDelay),
            subtitle: Text('${s.slideshowSeconds}s'),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: context.l10n.slideshowDelay,
                options: {
                  context.l10n.secondCount(1): 1,
                  context.l10n.secondsCount(3): 3,
                  context.l10n.secondsCount(5): 5,
                  context.l10n.secondsCount(10): 10,
                },
                current: s.slideshowSeconds,
              );
              if (v != null) await notifier.setSlideshowSeconds(v);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.shuffle),
            title: Text(context.l10n.shuffleByDefault),
            value: s.shuffleDefault,
            onChanged: notifier.setShuffleDefault,
          ),
          _SectionHeader(context.l10n.sectionStorage),
          Consumer(
            builder: (context, ref, _) {
              final sizeAsync = ref.watch(vaultSizeBytesProvider);
              final subtitle = sizeAsync.when(
                data: (b) => _formatBytes(b),
                loading: () => context.l10n.calculating,
                error: (_, __) => '—',
              );
              return ListTile(
                leading: const Icon(Icons.sd_storage_outlined),
                title: Text(context.l10n.vaultSize),
                subtitle: Text(subtitle),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.find_in_page_outlined),
            title: Text(context.l10n.scanOrphans),
            subtitle: Text(context.l10n.scanOrphansSubtitle),
            onTap: () => _scanOrphans(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.event_available_outlined),
            title: Text(context.l10n.repairCaptureDates),
            subtitle: Text(context.l10n.repairCaptureDatesSubtitle),
            onTap: () => _repairCaptureDates(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.restore_page_outlined),
            title: Text(context.l10n.recoverVault),
            subtitle: Text(context.l10n.recoverVaultSubtitle),
            onTap: () => _recoverVault(context, ref, alsoUnhide: false),
          ),
          ListTile(
            leading: const Icon(Icons.unarchive_outlined),
            title: Text(context.l10n.recoverAndUnhide),
            subtitle: Text(context.l10n.recoverAndUnhideSubtitle),
            onTap: () => _recoverVault(context, ref, alsoUnhide: true),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: Text(context.l10n.recycleRetention),
            subtitle: Text(context.l10n.retentionDays(s.recycleRetentionDays)),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: context.l10n.retention,
                options: {
                  context.l10n.retention1Day: 1,
                  context.l10n.retentionDays(7): 7,
                  context.l10n.retentionDays(30): 30,
                },
                current: s.recycleRetentionDays,
              );
              if (v != null) await notifier.setRecycleRetentionDays(v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: Text(context.l10n.emptyRecycleBin),
            onTap: () => _emptyRecycle(context, ref),
          ),
          ListTile(
            key: const ValueKey('settings-export-vault'),
            leading: const Icon(Icons.upload_file_outlined),
            title: Text(context.l10n.exportVault),
            subtitle: Text(context.l10n.exportVaultSubtitle),
            onTap: backupBusy
                ? null
                : () => _startBackup(
                      context,
                      ref,
                      VaultBackupOperation.export,
                    ),
          ),
          ListTile(
            key: const ValueKey('settings-restore-vault'),
            leading: const Icon(Icons.download_outlined),
            title: Text(context.l10n.importVault),
            subtitle: Text(context.l10n.importVaultSubtitle),
            onTap: backupBusy
                ? null
                : () => _startBackup(
                      context,
                      ref,
                      VaultBackupOperation.restore,
                    ),
          ),
          _SectionHeader(context.l10n.sectionAbout),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(context.l10n.language),
            subtitle: Text(_localeLabel(context, s.localeCode)),
            onTap: () async {
              final v = await _pick<String>(
                context,
                title: context.l10n.language,
                options: {
                  context.l10n.languageSystem: '',
                  context.l10n.languageEnglish: 'en',
                  context.l10n.languageZhCn: 'zh_CN',
                  context.l10n.languageZhHk: 'zh_HK',
                },
                current: s.localeCode,
              );
              if (v != null) await notifier.setLocaleCode(v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text(AppInfo.name),
            subtitle: Text(
              'v$versionAndPatch · ${AppInfo.licenseShort}',
            ),
            onTap: () => _showAbout(context, ref, versionAndPatch),
          ),
          const AppUpdateTile(),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(context.l10n.author),
            subtitle: const Text(AppInfo.author),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openAuthorUrl(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text(context.l10n.license),
            subtitle: const Text(AppInfo.licenseShort),
            onTap: () => _showLicense(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openAuthorUrl(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(externalUrlLauncherProvider).open(
            Uri.parse(AppInfo.authorUrl),
          );
    } catch (e) {
      debugPrint('open author url: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotOpenBrowser)),
        );
      }
    }
  }

  void _showAbout(
    BuildContext context,
    WidgetRef ref,
    String versionAndBuild,
  ) {
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
              const Text(AppInfo.about),
              const SizedBox(height: 16),
              Text(
                context.l10n.versionLabel(versionAndBuild),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.authorLabel(AppInfo.author),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _openAuthorUrl(context, ref);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    AppInfo.authorUrl,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                  ),
                ),
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
            child: Text(context.l10n.close),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showLicense(context);
            },
            child: Text(context.l10n.license),
          ),
        ],
      ),
    );
  }

  void _showLicense(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.license),
        content: const SingleChildScrollView(
          child: Text(AppInfo.licenseBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.close),
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
        title: context.l10n.currentPattern,
        subtitle: context.l10n.drawCurrentPattern,
      );
    } else {
      current = await _promptPin(
        context,
        title: context.l10n.currentPin,
        subtitle: context.l10n.enterPinThenPattern,
      );
    }
    if (current == null || !context.mounted) return;
    final next = await _promptPattern(
      context,
      title: context.l10n.newPattern,
      subtitle: context.l10n.connectAtLeast4Dots,
    );
    if (next == null || !context.mounted) return;
    final confirm = await _promptPattern(
      context,
      title: context.l10n.confirmNewPattern,
      subtitle: context.l10n.drawSamePatternAgain,
    );
    if (confirm == null || !context.mounted) return;
    if (next != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.newPatternsDidNotMatch)),
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
          SnackBar(content: Text(context.l10n.patternUpdated)),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('change pattern: $e\n$stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lock.usesPattern
                  ? context.l10n.wrongPattern
                  : context.l10n.wrongPin,
            ),
          ),
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
              child: Text(context.l10n.cancel),
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
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.continueAction),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    return ctrl.text;
  }

  Future<void> _scanOrphans(BuildContext context, WidgetRef ref) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.scanningOrphans)),
    );
    try {
      final result = await ref
          .read(maintenanceServiceProvider)
          .recoverVaultFiles(alsoUnhide: false);
      ref.invalidate(vaultSizeBytesProvider);
      ref.invalidate(albumsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_recoverySummary(context, result))),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('orphan scan: $e\n$stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.scanFailedShort)),
        );
      }
    }
  }

  Future<void> _repairCaptureDates(BuildContext context, WidgetRef ref) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.repairingCaptureDates)),
    );
    try {
      final result =
          await ref.read(maintenanceServiceProvider).repairCaptureDates();
      ref.invalidate(albumsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_captureDateSummary(context, result))),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('capture date repair: $e\n$stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.scanFailedShort)),
        );
      }
    }
  }

  /// Reinstall recovery: re-index files still under `.privateheart_vault`.
  ///
  /// [alsoUnhide] restores them to the public Gallery after indexing.
  Future<void> _recoverVault(
    BuildContext context,
    WidgetRef ref, {
    required bool alsoUnhide,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          alsoUnhide
              ? context.l10n.recoverAndUnhide
              : context.l10n.recoverVault,
        ),
        content: Text(
          alsoUnhide
              ? context.l10n.recoverAndUnhideBody
              : context.l10n.recoverVaultBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.continueAction),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.recoveringVault)),
    );
    try {
      final result = await ref
          .read(maintenanceServiceProvider)
          .recoverVaultFiles(alsoUnhide: alsoUnhide);
      ref.invalidate(vaultSizeBytesProvider);
      ref.invalidate(albumsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_recoverySummary(context, result))),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('vault recovery: $e\n$stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.scanFailedShort)),
        );
      }
    }
  }

  static String _recoverySummary(
    BuildContext context,
    VaultRecoveryResult result,
  ) {
    return switch (result.status) {
      VaultRecoveryStatus.noFiles => context.l10n.noOrphanVaultFiles,
      VaultRecoveryStatus.reindexed => context.l10n.recoveryResult(
          result.reindexed,
          result.skipped,
          result.failed,
        ),
      VaultRecoveryStatus.restoredToGallery =>
        context.l10n.galleryRecoveryResult(
          result.reindexed,
          result.skipped,
          result.failed,
        ),
    };
  }

  static String _captureDateSummary(
    BuildContext context,
    CaptureDateRepairResult result,
  ) {
    if (!result.hadMedia) return context.l10n.noVaultMediaToRepair;
    return context.l10n.captureDateRepairResult(
      result.fixed,
      result.skipped,
      result.failed,
    );
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
        title: Text(context.l10n.emptyRecycleBinTitle),
        content: Text(context.l10n.emptyRecycleBinBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.empty),
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
        SnackBar(content: Text(context.l10n.purgedItems(items.length))),
      );
    }
  }

  Future<void> _startBackup(
    BuildContext context,
    WidgetRef ref,
    VaultBackupOperation operation,
  ) async {
    final controller = ref.read(vaultBackupControllerProvider.notifier);
    final restoring = operation == VaultBackupOperation.restore;
    final pickerTitle = restoring
        ? context.l10n.backupRestorePickerTitle
        : context.l10n.backupExportPickerTitle;
    final bool started;
    try {
      final selectDirectory = ref.read(vaultBackupDirectoryPickerProvider);
      started = await controller.selectDirectoryAndStart(
        operation: operation,
        selectDirectory: () => selectDirectory(pickerTitle),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'vault backup directory selection failed: $error\n$stackTrace',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backupFolderSelectionFailed)),
      );
      return;
    }
    if (!started || !context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Consumer(
        builder: (context, dialogRef, _) {
          final state = dialogRef.watch(vaultBackupControllerProvider);
          final notifier =
              dialogRef.read(vaultBackupControllerProvider.notifier);
          return VaultBackupProgressDialog(
            state: state,
            text: _backupDialogText(context, restoring: restoring),
            onCancel: notifier.cancel,
            onRetry: notifier.retry,
            onClose: () => Navigator.pop(dialogContext),
          );
        },
      ),
    );
    if (!ref.read(vaultBackupControllerProvider).busy) controller.dismiss();
  }

  VaultBackupDialogText _backupDialogText(
    BuildContext context, {
    required bool restoring,
  }) {
    final l10n = context.l10n;
    return VaultBackupDialogText(
      operationTitle: restoring
          ? l10n.backupRestoreProgressTitle
          : l10n.backupExportProgressTitle,
      completedTitle: restoring
          ? l10n.backupRestoreCompleteTitle
          : l10n.backupExportCompleteTitle,
      cancelledTitle: l10n.backupCancelledTitle,
      cancelledBody: l10n.backupCancelledBody,
      errorTitle: restoring
          ? l10n.backupRestoreErrorTitle
          : l10n.backupExportErrorTitle,
      cancel: l10n.cancel,
      cancelling: l10n.backupCancelling,
      close: l10n.close,
      retry: l10n.retry,
      checksumVerified: l10n.backupChecksumVerified,
      checkedWithoutChecksum: l10n.backupCheckedWithoutChecksum,
      progressLabel: l10n.backupProgressLabel,
      stageLabel: (stage) => switch (stage) {
        VaultBackupStage.preparing => l10n.backupStagePreparing,
        VaultBackupStage.checkingSource => l10n.backupStageCheckingSource,
        VaultBackupStage.copying => l10n.backupStageCopying,
        VaultBackupStage.writingManifest => l10n.backupStageWritingManifest,
        VaultBackupStage.checkingBackup => l10n.backupStageCheckingBackup,
        VaultBackupStage.restoring => l10n.backupStageRestoring,
        VaultBackupStage.completed => l10n.backupStageComplete,
      },
      itemCount: l10n.backupItemCount,
      totalSize: _formatBytes,
      progressCount: l10n.backupProgressCount,
      errorMessage: (error) => _backupErrorMessage(
        context,
        error,
        restoring: restoring,
      ),
    );
  }

  String _backupErrorMessage(
    BuildContext context,
    Object error, {
    required bool restoring,
  }) {
    final l10n = context.l10n;
    if (error is! VaultBackupException) {
      return restoring
          ? l10n.backupRestoreFailedGeneric
          : l10n.backupExportFailedGeneric;
    }
    final item = error.fileName ?? l10n.backupUnknownItem;
    return switch (error.code) {
      VaultBackupErrorCode.manifestMissing => l10n.backupManifestMissing,
      VaultBackupErrorCode.malformedManifest => error.fileName == null
          ? l10n.backupManifestMalformed
          : l10n.backupManifestMalformedItem(item),
      VaultBackupErrorCode.unsupportedManifestVersion =>
        l10n.backupVersionUnsupported,
      VaultBackupErrorCode.sourceMissing => l10n.backupSourceMissing(item),
      VaultBackupErrorCode.sourceUnreadable =>
        l10n.backupSourceUnreadable(item),
      VaultBackupErrorCode.sourceEmpty => l10n.backupSourceEmpty(item),
      VaultBackupErrorCode.sourceChanged => l10n.backupSourceChanged(item),
      VaultBackupErrorCode.payloadMissing => l10n.backupPayloadMissing(item),
      VaultBackupErrorCode.payloadUnreadable =>
        l10n.backupPayloadUnreadable(item),
      VaultBackupErrorCode.payloadEmpty => l10n.backupPayloadEmpty(item),
      VaultBackupErrorCode.payloadLengthMismatch =>
        l10n.backupPayloadLengthMismatch(item),
      VaultBackupErrorCode.payloadDigestMismatch =>
        l10n.backupPayloadDigestMismatch(item),
      VaultBackupErrorCode.unsafePath => l10n.backupUnsafePath(item),
      VaultBackupErrorCode.destinationConflict =>
        l10n.backupDestinationConflict(item),
      VaultBackupErrorCode.destinationWriteFailed ||
      VaultBackupErrorCode.databaseWriteFailed =>
        restoring
            ? l10n.backupRestoreWriteFailed
            : l10n.backupExportWriteFailed,
    };
  }

  String _localeLabel(BuildContext context, String code) {
    final l10n = context.l10n;
    return switch (code) {
      'en' => l10n.languageEnglish,
      'zh_CN' => l10n.languageZhCn,
      'zh_HK' => l10n.languageZhHk,
      _ => l10n.languageSystem,
    };
  }

  String _autoLockLabel(BuildContext context, int s) {
    final l10n = context.l10n;
    if (s <= 0) return l10n.autoLockImmediately;
    if (s < 60) return l10n.autoLockSeconds(s);
    final m = s ~/ 60;
    return m == 1 ? l10n.autoLockMinutes(m) : l10n.autoLockMinutesPlural(m);
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
