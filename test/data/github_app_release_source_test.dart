import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privi/data/services/github_app_release_source.dart';

void main() {
  test('reads and validates the latest published GitHub release', () async {
    late http.Request capturedRequest;
    final source = GithubAppReleaseSource(
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          '{"tag_name":"v1.0.8","html_url":'
          '"https://github.com/kcng0/privi/releases/tag/v1.0.8"}',
          200,
        );
      }),
    );

    final release = await source.readLatestRelease();

    expect(capturedRequest.url, GithubAppReleaseSource.latestReleaseUri);
    expect(
      capturedRequest.headers['Accept'],
      'application/vnd.github+json',
    );
    expect(capturedRequest.headers['X-GitHub-Api-Version'], '2026-03-10');
    expect(release.version.toString(), '1.0.8');
    expect(
      release.uri,
      Uri.parse('https://github.com/kcng0/privi/releases/tag/v1.0.8'),
    );
  });

  test('non-success responses fail explicitly', () async {
    final source = GithubAppReleaseSource(
      client: MockClient((_) async => http.Response('rate limited', 403)),
    );

    await expectLater(
      source.readLatestRelease(),
      throwsA(
        isA<GithubReleaseException>().having(
          (error) => error.statusCode,
          'statusCode',
          403,
        ),
      ),
    );
  });

  test('malformed tags and non-GitHub release links fail explicitly', () async {
    final malformedTag = GithubAppReleaseSource(
      client: MockClient(
        (_) async => http.Response(
          '{"tag_name":"latest","html_url":'
          '"https://github.com/kcng0/privi/releases/latest"}',
          200,
        ),
      ),
    );
    final unsafeLink = GithubAppReleaseSource(
      client: MockClient(
        (_) async => http.Response(
          '{"tag_name":"v1.0.8","html_url":"https://example.com/app.apk"}',
          200,
        ),
      ),
    );

    await expectLater(malformedTag.readLatestRelease(), throwsFormatException);
    await expectLater(unsafeLink.readLatestRelease(), throwsFormatException);
  });
}
