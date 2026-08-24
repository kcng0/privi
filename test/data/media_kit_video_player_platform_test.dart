import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/services/playback/media_kit_video_player_platform.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  test('maps file, network, content, and asset URIs for mpv', () {
    expect(
      mediaUriForDataSource(
        DataSource(
          sourceType: DataSourceType.file,
          uri: '/tmp/clip.mp4',
        ),
      ),
      'file:///tmp/clip.mp4',
    );
    expect(
      mediaUriForDataSource(
        DataSource(
          sourceType: DataSourceType.file,
          uri: 'file:///tmp/clip.mp4',
        ),
      ),
      'file:///tmp/clip.mp4',
    );
    expect(
      mediaUriForDataSource(
        DataSource(
          sourceType: DataSourceType.network,
          uri: 'https://example.com/a.mkv',
        ),
      ),
      'https://example.com/a.mkv',
    );
    expect(
      mediaUriForDataSource(
        DataSource(
          sourceType: DataSourceType.contentUri,
          uri: 'content://media/external/video/1',
        ),
      ),
      'content://media/external/video/1',
    );
    expect(
      mediaUriForDataSource(
        DataSource(
          sourceType: DataSourceType.asset,
          asset: 'videos/demo.mp4',
        ),
      ),
      'asset:///videos/demo.mp4',
    );
  });

  test('detects MediaCodec capability errors that ExoPlayer used to surface',
      () {
    const message =
        'Video player had error b1.k: MediaCodecVideoRenderer error, index=0, '
        'avc.1.640034, 4946019, und, [2560, 1440, 120.0, ColorInfo(Unset color '
        'space, Unset color range, Unset color transfer, false, 8bit Luma, 8bit '
        'Chrome)].  [-1, -1]), format_supported=NO_EXCEEDS_CAPABILITIES, null, '
        'null)';
    expect(isDecoderCapabilityError(message), isTrue);
    expect(isDecoderCapabilityError('Failed to open file'), isFalse);
  });
}
