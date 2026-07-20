import 'package:restart_app/restart_app.dart';

import '../../application/update/app_restart_service.dart';

/// Requests a cold Android process restart so the next Flutter engine loads
/// the newly downloaded Shorebird patch.
final class PlatformAppRestartService implements AppRestartService {
  const PlatformAppRestartService();

  @override
  bool get automaticRestartSupported => true;

  @override
  Future<void> restart() async {
    final result = await Restart.restartApp(mode: RestartMode.process);
    if (result.success) return;

    final details = [
      result.code,
      result.message,
    ].whereType<String>().where((value) => value.isNotEmpty).join(': ');
    throw StateError(
      details.isEmpty ? 'App restart was not accepted' : details,
    );
  }
}
