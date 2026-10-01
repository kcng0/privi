import 'package:flutter/services.dart';

/// Android orientation requests scoped to one in-app playback session.
/// iOS orientation is managed by the presentation session with SystemChrome.
class PlaybackOrientationService {
  PlaybackOrientationService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.privi.app/orientation');

  static PlaybackOrientationService instance = PlaybackOrientationService();

  final MethodChannel _channel;

  Future<void> begin() => _channel.invokeMethod<void>('begin');

  Future<void> setMode(String mode) =>
      _channel.invokeMethod<void>('setMode', {'mode': mode});

  Future<void> restore() => _channel.invokeMethod<void>('restore');
}
