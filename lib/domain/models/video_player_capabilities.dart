import 'package:flutter/widgets.dart';

import 'advanced_video_state.dart';
import 'video_playback_settings.dart';

/// A platform-owned advanced-control port for an existing video player.
abstract interface class AdvancedVideoPortProvider {
  AdvancedVideoPort? advancedPortFor(int playerId);
}

/// Platforms whose native video view owns display sizing and presentation.
abstract interface class NativeVideoPresentationPlatform {
  Widget buildNativeViewport(int playerId, VideoFitMode fitMode);

  Future<void> setPresentationAllowed(int playerId, bool allowed);
}
