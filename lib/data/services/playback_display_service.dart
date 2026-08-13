import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Window brightness and system media volume for in-player swipe gestures.
abstract class VideoDisplayControls {
  Future<double> getBrightness();
  Future<void> setBrightness(double value);
  Future<void> resetBrightness();
  Future<double> getVolume();
  Future<void> setVolume(double value);
}

class PlaybackDisplayService implements VideoDisplayControls {
  PlaybackDisplayService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.privi.app/window');

  static PlaybackDisplayService instance = PlaybackDisplayService();

  final MethodChannel _channel;

  @override
  Future<double> getBrightness() => _readUnit('getBrightness');

  @override
  Future<void> setBrightness(double value) {
    return _writeUnit('setBrightness', value);
  }

  @override
  Future<void> resetBrightness() async {
    try {
      await _channel.invokeMethod<void>('resetBrightness');
    } catch (error, stackTrace) {
      debugPrint('resetBrightness: $error\n$stackTrace');
    }
  }

  @override
  Future<double> getVolume() => _readUnit('getVolume');

  @override
  Future<void> setVolume(double value) => _writeUnit('setVolume', value);

  Future<double> _readUnit(String method) async {
    try {
      final value = await _channel.invokeMethod<num>(method);
      return (value?.toDouble() ?? 0.5).clamp(0.0, 1.0);
    } catch (error, stackTrace) {
      debugPrint('$method: $error\n$stackTrace');
      return 0.5;
    }
  }

  Future<void> _writeUnit(String method, double value) async {
    try {
      await _channel.invokeMethod<void>(method, {
        'value': value.clamp(0.0, 1.0),
      });
    } catch (error, stackTrace) {
      debugPrint('$method: $error\n$stackTrace');
    }
  }
}
