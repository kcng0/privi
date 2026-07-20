import '../../application/update/app_restart_service.dart';

/// `restart_app` cannot guarantee a new iOS process. Surface the requirement
/// instead of requesting Android's process mode on another platform.
final class IosAppRestartService implements AppRestartService {
  const IosAppRestartService();

  @override
  bool get automaticRestartSupported => false;

  @override
  Future<void> restart() async {
    throw const RestartRequiredException();
  }
}
