import 'package:video_player/video_player.dart';

/// Commit a speed preference only after the active engine accepted it.
/// video_player updates its value optimistically, so a rejected native call
/// must restore both the facade value and the engine's previous speed.
Future<void> updateVideoPlaybackSpeed({
  required VideoPlayerController controller,
  required double speed,
  required double previousSpeed,
  required bool Function() isCurrent,
  required Future<void> Function() persist,
}) async {
  if (!isCurrent()) throw StateError('The active video has changed.');
  try {
    await controller.setPlaybackSpeed(speed);
    if (!isCurrent()) throw StateError('The active video has changed.');
    await persist();
  } catch (error, stack) {
    try {
      await controller.setPlaybackSpeed(previousSpeed);
    } catch (rollbackError) {
      Error.throwWithStackTrace(
        StateError(
          'Playback speed change failed: $error. '
          'Restoring ${previousSpeed}x also failed: $rollbackError',
        ),
        stack,
      );
    }
    Error.throwWithStackTrace(error, stack);
  }
}
