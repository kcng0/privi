import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/update/app_update_service.dart';
import '../../core/l10n.dart';

class AppUpdateTile extends ConsumerStatefulWidget {
  const AppUpdateTile({super.key});

  @override
  ConsumerState<AppUpdateTile> createState() => _AppUpdateTileState();
}

class _AppUpdateTileState extends ConsumerState<AppUpdateTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.system_update_alt),
      title: Text(context.l10n.checkUpdates),
      trailing: _busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _busy ? null : _checkForUpdates,
    );
  }

  Future<void> _checkForUpdates() async {
    if (_busy) return;
    setState(() => _busy = true);

    final service = ref.read(appUpdateServiceProvider);
    try {
      final status = await service.checkForUpdate();
      if (!mounted) return;

      switch (status) {
        case AppUpdateStatus.upToDate:
          _showMessage(context.l10n.upToDate);
        case AppUpdateStatus.updateAvailable:
          await _confirmAndDownload(service);
        case AppUpdateStatus.restartRequired:
          _showMessage(context.l10n.updateReadyRestart);
        case AppUpdateStatus.unavailable:
          _showMessage(context.l10n.updatesUnavailable);
      }
    } catch (error, stackTrace) {
      debugPrint('update check failed: $error\n$stackTrace');
      if (mounted) _showMessage(context.l10n.updateCheckFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmAndDownload(AppUpdateService service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.updateAvailableTitle),
        content: Text(context.l10n.updateDownloadPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.later),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.updateAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await service.downloadUpdate();
      if (mounted) _showMessage(context.l10n.updateReadyRestart);
    } catch (error, stackTrace) {
      debugPrint('update download failed: $error\n$stackTrace');
      if (mounted) _showMessage(context.l10n.updateDownloadFailed);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
