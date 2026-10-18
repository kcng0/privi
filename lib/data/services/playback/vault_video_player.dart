import 'dart:io';

import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'libvlc_video_player_platform.dart';

/// Android renders through LibVLC's native surfaces; iOS keeps AVFoundation.
void installVaultVideoPlayer() {
  if (Platform.isAndroid) {
    VideoPlayerPlatform.instance = LibVlcVideoPlayerPlatform();
  }
}
