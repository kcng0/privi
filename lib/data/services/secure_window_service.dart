import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// FLAG_SECURE — block screenshots / recents preview (optional hardening).
class SecureWindowService {
  static const _channel = MethodChannel('com.privi.app/window');

  Future<void> setFlagSecure(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setFlagSecure', {'enabled': enabled});
    } catch (e, stackTrace) {
      debugPrint('FLAG_SECURE: $e\n$stackTrace');
      Error.throwWithStackTrace(e, stackTrace);
    }
  }
}
