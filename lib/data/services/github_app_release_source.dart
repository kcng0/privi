import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import '../../application/update/app_release_source.dart';

final class GithubReleaseException implements Exception {
  const GithubReleaseException({required this.statusCode});

  final int statusCode;

  @override
  String toString() => 'GitHub release request failed ($statusCode)';
}

/// Reads the latest stable release published by the official GitHub repository.
final class GithubAppReleaseSource implements AppReleaseSource {
  const GithubAppReleaseSource({required http.Client client})
      : _client = client;

  static final Uri latestReleaseUri = Uri.https(
    'api.github.com',
    '/repos/kcng0/privi/releases/latest',
  );

  final http.Client _client;

  @override
  bool get supported => true;

  @override
  Future<AppRelease> readLatestRelease() async {
    final response = await _client.get(
      latestReleaseUri,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2026-03-10',
        'User-Agent': 'Privi-Android',
      },
    );
    if (response.statusCode != 200) {
      throw GithubReleaseException(statusCode: response.statusCode);
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('GitHub release response must be an object');
    }
    final tag = payload['tag_name'];
    final releaseUrl = payload['html_url'];
    if (tag is! String || tag.isEmpty || releaseUrl is! String) {
      throw const FormatException('GitHub release response is incomplete');
    }

    final version = Version.parse(
      tag.startsWith('v') || tag.startsWith('V') ? tag.substring(1) : tag,
    );
    final uri = Uri.parse(releaseUrl);
    if (uri.scheme != 'https' || uri.host != 'github.com') {
      throw const FormatException('GitHub release URL is not trusted');
    }
    return AppRelease(version: version, uri: uri);
  }
}
