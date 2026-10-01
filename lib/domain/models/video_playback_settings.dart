/// Persisted double-tap seek intervals offered by the in-app video controls.
const videoSeekSecondOptions = <int>[3, 5, 10, 15];

/// Full 8cm drag distance in seconds (VLC uses 10 minutes at 8cm).
const videoDragSeekSecondOptions = <int>[120, 300, 600, 1200];

const defaultPlayerDragSeekSeconds = 600;

String formatDragSeekOption(int seconds) => '${seconds ~/ 60}m';

/// Playback speeds offered by the in-app video controls.
const videoPlaybackSpeedOptions = <double>[
  0.25,
  0.5,
  0.75,
  1,
  1.25,
  1.5,
  1.75,
  2,
  2.25,
  2.5,
  2.75,
  3,
  3.25,
  3.5,
  3.75,
  4,
];

/// Names are persisted; `fit` is the legacy spelling of bestFit.
enum VideoFitMode {
  bestFit,
  fitScreen,
  fill,
  original,
  ratio16x9,
  ratio4x3,
  ratio16x10,
  ratio2x1,
  ratio221x1,
  ratio235x1,
  ratio239x1,
  ratio5x4;

  static const fit = bestFit;

  static VideoFitMode fromStored(String? value) {
    if (value == 'fit') return bestFit;
    return values.where((mode) => mode.name == value).firstOrNull ?? bestFit;
  }

  double? get aspectRatio => switch (this) {
        ratio16x9 => 16 / 9,
        ratio4x3 => 4 / 3,
        ratio16x10 => 16 / 10,
        ratio2x1 => 2,
        ratio221x1 => 2.21,
        ratio235x1 => 2.35,
        ratio239x1 => 2.39,
        ratio5x4 => 5 / 4,
        _ => null,
      };
}

const videoFitQuickModes = <VideoFitMode>[
  VideoFitMode.bestFit,
  VideoFitMode.fitScreen,
  VideoFitMode.fill,
  VideoFitMode.ratio16x9,
  VideoFitMode.ratio4x3,
  VideoFitMode.original,
];

const videoDefaultOrientationOptions = <String>[
  'auto',
  'portrait',
  'landscape',
  'reverseLandscape',
  'lastLocked',
];
const videoSessionOrientationOptions = <String>[
  'auto',
  'portrait',
  'reversePortrait',
  'landscape',
  'reverseLandscape',
  'sensorLandscape',
];
