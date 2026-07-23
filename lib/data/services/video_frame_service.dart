import 'package:flutter/services.dart';

class VideoFrameService {
  static const _channel = MethodChannel('com.privi.app/mediastore');

  Future<Uint8List?> frameAtTime({
    required String path,
    required Duration position,
    int maxSize = 220,
  }) {
    return _channel.invokeMethod<Uint8List>('videoFrameAtTime', {
      'path': path,
      'timeUs': position.inMicroseconds,
      'maxSize': maxSize,
    });
  }
}
