import 'package:pub_semver/pub_semver.dart';

/// A published, installable application release.
final class AppRelease {
  const AppRelease({required this.version, required this.uri});

  final Version version;
  final Uri uri;
}

/// Boundary for the source of full application releases.
abstract interface class AppReleaseSource {
  Future<AppRelease> readLatestRelease();
}
