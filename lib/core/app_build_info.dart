import 'package:flutter/foundation.dart';

/// Immutable package version metadata supplied by the composition root.
@immutable
class AppBuildInfo {
  AppBuildInfo({required String version, required String buildNumber})
      : version = _requireValue(version, 'version'),
        buildNumber = _requireValue(buildNumber, 'buildNumber');

  final String version;
  final String buildNumber;

  String get versionAndBuild => '$version ($buildNumber)';

  static String _requireValue(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return normalized;
  }
}
