import '../../application/update/app_release_source.dart';

/// The Android GitHub APK feed is not an iOS release channel.
final class IosAppReleaseSource implements AppReleaseSource {
  const IosAppReleaseSource();

  @override
  bool get supported => false;

  @override
  Future<AppRelease> readLatestRelease() {
    throw UnsupportedError(
      'iOS binary updates are delivered through the configured store channel',
    );
  }
}
