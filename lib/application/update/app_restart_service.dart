/// Application boundary for relaunching into a fresh process after an update.
abstract interface class AppRestartService {
  Future<void> restart();
}
