/// Persisted double-tap seek intervals offered by the in-app video controls.
const videoSeekSecondOptions = <int>[3, 5, 10, 15];

/// Full 8cm drag distance in seconds (VLC uses 10 minutes at 8cm).
const videoDragSeekSecondOptions = <int>[120, 300, 600, 1200];

const defaultPlayerDragSeekSeconds = 600;

String formatDragSeekOption(int seconds) => '${seconds ~/ 60}m';

/// Playback speeds offered by the in-app video controls.
const videoPlaybackSpeedOptions = <double>[0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
