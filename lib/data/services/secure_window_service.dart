import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// FLAG_SECURE — block screenshots / recents preview (optional hardening).
class SecureWindowService {
  static const _channel = MethodChannel('com.privateheart.vault/window');

  Future<void> setFlagSecure(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setFlagSecure', {'enabled': enabled});
    } catch (e) {
      debugPrint('FLAG_SECURE: $e');
    }
  }
}
