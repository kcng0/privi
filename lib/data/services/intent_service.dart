import 'package:flutter/services.dart';

import '../../application/player/external_player_gateway.dart';

final class MethodChannelExternalPlayerGateway
    implements ExternalPlayerGateway {
  MethodChannelExternalPlayerGateway({
    MethodChannel channel = const MethodChannel(_channelName),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const channelName = _channelName;
  static const _channelName = 'com.privi.app/external_player';
  static const _returnedCleanlyMethod = 'intent_returned_cleanly';

  final MethodChannel _channel;
  bool _returnedCleanly = false;

  @override
  Future<bool> open({
    required String filePath,
    required String mimeType,
  }) async =>
      await _channel.invokeMethod<bool>('openExternalPlayer', {
        'path': filePath,
        'mimeType': mimeType,
      }) ??
      false;

  @override
  bool takeCleanReturn() {
    final returnedCleanly = _returnedCleanly;
    _returnedCleanly = false;
    return returnedCleanly;
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != _returnedCleanlyMethod) {
      throw MissingPluginException(
        'Unknown external player call: ${call.method}',
      );
    }
    _returnedCleanly = true;
  }
}
