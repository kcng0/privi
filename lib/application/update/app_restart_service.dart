final class RestartRequiredException implements Exception {
  const RestartRequiredException();

  @override
  String toString() => 'A manual application relaunch is required';
}

/// Application boundary for relaunching into a fresh process after an update.
abstract interface class AppRestartService {
  bool get automaticRestartSupported;

  Future<void> restart();
}
