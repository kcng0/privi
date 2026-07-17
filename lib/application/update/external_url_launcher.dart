/// Application boundary for opening trusted external web pages.
abstract interface class ExternalUrlLauncher {
  Future<void> open(Uri uri);
}
