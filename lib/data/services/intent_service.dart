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
  static const _returnedMethod = 'external_player_returned';
  static const _androidResultOk = -1;
  static const _completionToleranceMs = 750;
  static const _minimumCompletionPercent = 95;

  final MethodChannel _channel;
  ExternalPlayerReturn? _pendingReturn;

  @override
  bool get supported => true;

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
  ExternalPlayerReturn? takeReturn() {
    final result = _pendingReturn;
    _pendingReturn = null;
    return result;
  }

  void dispose() {
    _pendingReturn = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != _returnedMethod) {
      throw MissingPluginException(
        'Unknown external player call: ${call.method}',
      );
    }
    final rawArguments = call.arguments;
    if (rawArguments is! Map<Object?, Object?>) {
      throw PlatformException(
        code: 'invalid_external_player_result',
        message: 'External player result must be a map',
      );
    }
    final resultCode = _requiredInt(rawArguments, 'resultCode');
    final completionSupported = _requiredBool(
      rawArguments,
      'completionSupported',
    );
    final positionMs = _optionalInt(rawArguments, 'positionMs');
    final durationMs = _optionalInt(rawArguments, 'durationMs');
    final expectedDurationMs = _optionalInt(rawArguments, 'expectedDurationMs');
    final elapsedMs = _optionalInt(rawArguments, 'elapsedMs');
    _pendingReturn = _isCompleted(
      resultCode: resultCode,
      completionSupported: completionSupported,
      positionMs: positionMs,
      durationMs: durationMs,
      expectedDurationMs: expectedDurationMs,
      elapsedMs: elapsedMs,
    )
        ? ExternalPlayerReturn.completed
        : ExternalPlayerReturn.interrupted;
  }

  static bool _requiredBool(Map<Object?, Object?> arguments, String key) {
    final value = arguments[key];
    if (value is! bool) {
      throw PlatformException(
        code: 'invalid_external_player_result',
        message: 'External player result field "$key" must be a boolean',
      );
    }
    return value;
  }

  static int _requiredInt(Map<Object?, Object?> arguments, String key) {
    final value = arguments[key];
    if (value is! int) {
      throw PlatformException(
        code: 'invalid_external_player_result',
        message: 'External player result field "$key" must be an integer',
      );
    }
    return value;
  }

  static int? _optionalInt(Map<Object?, Object?> arguments, String key) {
    final value = arguments[key];
    if (value == null) return null;
    if (value is! int) {
      throw PlatformException(
        code: 'invalid_external_player_result',
        message: 'External player result field "$key" must be an integer',
      );
    }
    return value;
  }

  static bool _isCompleted({
    required int resultCode,
    required bool completionSupported,
    required int? positionMs,
    required int? durationMs,
    required int? expectedDurationMs,
    required int? elapsedMs,
  }) {
    if (!completionSupported || resultCode != _androidResultOk) return false;

    if (positionMs != null &&
        durationMs != null &&
        positionMs > 0 &&
        durationMs > 0) {
      final remainingMs = durationMs - positionMs;
      final minimumPositionMs = (durationMs * _minimumCompletionPercent) ~/ 100;
      if (remainingMs <= _completionToleranceMs &&
          positionMs >= minimumPositionMs) {
        return true;
      }
    }

    // VLC resets its internal player before emitting the natural-end Activity
    // result on some versions, producing 0/0 despite a completed video. Only
    // accept that signature after the tracked session reached the file's
    // independently-read duration, so a quick Back during startup stays an
    // interruption.
    if (positionMs != 0 ||
        durationMs != 0 ||
        expectedDurationMs == null ||
        elapsedMs == null ||
        expectedDurationMs <= 0) {
      return false;
    }
    final minimumElapsedMs =
        (expectedDurationMs * _minimumCompletionPercent) ~/ 100;
    return elapsedMs >= minimumElapsedMs;
  }
}
