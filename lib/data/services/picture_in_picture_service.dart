import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

enum PictureInPictureEventType {
  active,
  exited,
  stopped,
  screenOff,
  play,
  pause
}

class PictureInPictureEvent {
  const PictureInPictureEvent(this.type, this.sessionId);

  final PictureInPictureEventType type;
  final int sessionId;
}

/// Native effects only. Playback ownership and the single-media grant live in
/// PictureInPictureController, independently from the vault lock.
abstract class PictureInPictureGateway {
  Stream<PictureInPictureEvent> get events;
  Future<bool> isSupported();
  Future<bool> enter({
    required int sessionId,
    required double aspectRatio,
    required bool isPlaying,
    Rect? sourceRect,
  });
  Future<void> setPlaying(int sessionId, bool playing);

  /// Revokes native controls and covers the window before returning whether the
  /// activity is still pinned. Callers keep a black surface until this settles.
  Future<bool> revoke(int sessionId);
  Future<void> acknowledgeExit(int sessionId);
  Future<void> dispose();
}

class MethodChannelPictureInPictureGateway implements PictureInPictureGateway {
  MethodChannelPictureInPictureGateway({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.privi.app/pip') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final _events = StreamController<PictureInPictureEvent>.broadcast(sync: true);

  @override
  Stream<PictureInPictureEvent> get events => _events.stream;

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'event') return;
    final args = Map<Object?, Object?>.from(call.arguments as Map);
    final event = PictureInPictureEventType.values
        .where((type) => type.name == args['type'])
        .firstOrNull;
    final sessionId = args['sessionId'];
    if (event != null && sessionId is int && !_events.isClosed) {
      _events.add(PictureInPictureEvent(event, sessionId));
    }
  }

  @override
  Future<bool> isSupported() async =>
      Platform.isAndroid &&
      (await _channel.invokeMethod<bool>('isSupported') ?? false);

  @override
  Future<bool> enter({
    required int sessionId,
    required double aspectRatio,
    required bool isPlaying,
    Rect? sourceRect,
  }) async =>
      await _channel.invokeMethod<bool>('enter', {
        'sessionId': sessionId,
        'aspectRatio': aspectRatio,
        'isPlaying': isPlaying,
        if (sourceRect != null)
          'sourceRect': {
            'left': sourceRect.left.round(),
            'top': sourceRect.top.round(),
            'right': sourceRect.right.round(),
            'bottom': sourceRect.bottom.round(),
          },
      }) ??
      false;

  @override
  Future<void> setPlaying(int sessionId, bool playing) =>
      _channel.invokeMethod<void>('setPlaying', {
        'sessionId': sessionId,
        'isPlaying': playing,
      });

  @override
  Future<bool> revoke(int sessionId) async =>
      await _channel.invokeMethod<bool>('revoke', {'sessionId': sessionId}) ??
      false;

  @override
  Future<void> acknowledgeExit(int sessionId) =>
      _channel.invokeMethod<void>('acknowledgeExit', {'sessionId': sessionId});

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _events.close();
  }
}
