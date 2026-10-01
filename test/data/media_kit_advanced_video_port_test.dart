import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:privi/data/services/playback/media_kit_video_player_platform.dart';

void main() {
  late _NativeHarness native;
  late MediaKitAdvancedVideoPort port;

  setUp(() {
    native = _NativeHarness();
    port = native.createPort();
  });
  tearDown(() async {
    await port.close();
    await native.player.dispose();
    await port.deleteTemporarySubtitles();
  });

  test('track discovery uses actual native selection and continuously updates',
      () async {
    await port.refresh();
    expect(port.value.audioTracks.map((t) => t.id), ['1', '2']);
    expect(port.value.audioTracks.singleWhere((t) => t.isSelected).id, '1');
    expect(port.value.subtitleTracks.map((t) => t.id), ['no', '3']);
    expect(port.value.subtitleTracks.singleWhere((t) => t.isSelected).id, '3');
    await port.selectAudioTrack('2');
    expect(native.properties['aid'], '2');
    expect(port.value.audioTracks.singleWhere((t) => t.isSelected).id, '2');
    await port.selectSubtitleTrack('no');
    expect(native.properties['sid'], 'no');
    expect(port.value.subtitleTracks.singleWhere((t) => t.isSelected).id, 'no');
    native.emitDimensions(1080, 1920);
    await Future<void>.delayed(Duration.zero);
    expect(port.value.displaySize, const Size(1080, 1920));
    await expectLater(port.selectAudioTrack('missing'), throwsArgumentError);
    expect(port.value.error, contains('Unknown audio track'));
  });

  test('signed delays are written in seconds and read back before success',
      () async {
    await port.refresh();
    expect(port.value.supportsAudioDelay, isTrue);
    await port.setAudioDelay(const Duration(milliseconds: -250));
    await port.setSubtitleDelay(const Duration(milliseconds: 1500));
    expect(native.properties['audio-delay'], '-0.25');
    expect(native.properties['sub-delay'], '1.5');
    expect(port.value.audioDelay, const Duration(milliseconds: -250));
    expect(port.value.subtitleDelay, const Duration(milliseconds: 1500));
    native.ignoreWrites = true;
    await expectLater(
      port.setAudioDelay(const Duration(milliseconds: 750)),
      throwsStateError,
    );
    expect(port.value.audioDelay, const Duration(milliseconds: -250));
    expect(port.value.error, contains('read back -0.25'));
    native.ignoreWrites = false;
    await port.setAudioDelay(Duration.zero);
    expect(port.value.error, isNull);
  });

  test('unsupported native properties do not report fictitious capabilities',
      () async {
    native.properties.remove('audio-delay');
    native.properties['sub-delay'] = 'nan';
    native.properties.remove('ab-loop-b');
    await port.refresh();
    expect(port.value.supportsAudioDelay, isFalse);
    expect(port.value.supportsSubtitleDelay, isFalse);
    expect(port.value.supportsAbLoop, isFalse);
    await expectLater(
      port.setAudioDelay(Duration.zero),
      throwsUnsupportedError,
    );
  });

  test('A–B loop validates ordering, writes seconds, and fully clears',
      () async {
    await port.refresh();
    await port.setAbLoop(
      const Duration(milliseconds: 1250),
      const Duration(milliseconds: 3750),
    );
    expect(native.properties['ab-loop-a'], '1.25');
    expect(native.properties['ab-loop-b'], '3.75');
    expect(port.value.abLoopStart, const Duration(milliseconds: 1250));
    expect(port.value.abLoopEnd, const Duration(milliseconds: 3750));
    await expectLater(
      port.setAbLoop(const Duration(seconds: 3), const Duration(seconds: 2)),
      throwsArgumentError,
    );
    expect(native.properties['ab-loop-b'], '3.75');
    await port.setAbLoop(null, null);
    expect(native.properties['ab-loop-a'], 'no');
    expect(native.properties['ab-loop-b'], 'no');
    expect(port.value.abLoopStart, isNull);
    expect(port.value.abLoopEnd, isNull);
  });

  test('partial loop failure publishes the real remaining native state',
      () async {
    await port.refresh();
    native.ignoredProperty = 'ab-loop-b';
    await expectLater(
      port.setAbLoop(const Duration(seconds: 1), const Duration(seconds: 4)),
      throwsStateError,
    );
    expect(port.value.abLoopStart, const Duration(seconds: 1));
    expect(port.value.abLoopEnd, isNull);
    expect(port.value.error, contains('mpv rejected ab-loop-b'));
  });

  test('runtime failure survives later metadata and refresh', () async {
    native.emitError('decoder failed during playback');
    await Future<void>.delayed(Duration.zero);
    native.emitDimensions(1280, 720);
    await port.refresh();
    expect(port.value.error, 'decoder failed during playback');
    expect(port.value.displaySize, const Size(1280, 720));
  });

  test('subtitle copies remain private until the native player releases them',
      () async {
    final temporary = await Directory.systemTemp.createTemp('privi-port-test-');
    addTearDown(() => temporary.delete(recursive: true));
    final source = File('${temporary.path}/original.ass');
    await source.writeAsString('[Script Info]\nTitle: 中文字幕');
    await port.close();
    port = native.createPort(
      createSubtitleDirectory: () => temporary.createTemp('private-'),
    );
    final entered = Completer<void>();
    final release = Completer<void>();
    native.beforeSubtitle = () async {
      entered.complete();
      await release.future;
    };
    final imported = port.importSubtitle(source.path);
    await entered.future;
    final copied = File.fromUri(Uri.parse(native.lastSubtitle!.id));
    expect(copied.path, isNot(source.path));
    expect(await copied.readAsString(), await source.readAsString());
    var closed = false;
    final closing = port.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    await expectLater(port.refresh(), throwsStateError);
    release.complete();
    await imported;
    await closing;
    expect(await copied.exists(), isTrue);
    await port.deleteTemporarySubtitles();
    expect(await copied.exists(), isFalse);
    expect(await source.exists(), isTrue);
    expect(native.hasAdvancedListeners, isFalse);
  });

  test('a failed subtitle load retains diagnostics and cleans its private copy',
      () async {
    final temporary = await Directory.systemTemp.createTemp('privi-port-test-');
    addTearDown(() => temporary.delete(recursive: true));
    final source = File('${temporary.path}/bad.srt');
    await source.writeAsString('not a subtitle');
    await port.close();
    port = native.createPort(
      createSubtitleDirectory: () => temporary.createTemp('private-'),
    );
    native.beforeSubtitle = () async => throw StateError('Invalid subtitle');
    await expectLater(port.importSubtitle(source.path), throwsStateError);
    expect(port.value.error, contains('Invalid subtitle'));
    final copy = File.fromUri(Uri.parse(native.lastSubtitle!.id));
    await port.close();
    await port.deleteTemporarySubtitles();
    expect(await copy.exists(), isFalse);
    expect(await source.exists(), isTrue);
  });
}

class _NativeHarness extends PlatformPlayer {
  _NativeHarness() : super(configuration: const PlayerConfiguration()) {
    state = const PlayerState(
      width: 1920,
      height: 1080,
      tracks: Tracks(
        audio: [
          AudioTrack('auto', null, null),
          AudioTrack('no', null, null),
          AudioTrack('1', 'English', 'en'),
          AudioTrack('2', '中文', 'zh'),
        ],
        subtitle: [
          SubtitleTrack('auto', null, null),
          SubtitleTrack('no', null, null),
          SubtitleTrack('3', 'ASS', 'zh'),
        ],
      ),
    );
    player = Player(platformPlayer: this);
  }

  late final Player player;
  final properties = <String, String>{
    'audio-delay': '0',
    'sub-delay': '0',
    'ab-loop-a': 'no',
    'ab-loop-b': 'no',
    'aid': '1',
    'sid': '3',
  };
  bool ignoreWrites = false;
  String? ignoredProperty;
  SubtitleTrack? lastSubtitle;
  Future<void> Function()? beforeSubtitle;

  MediaKitAdvancedVideoPort createPort({
    Future<Directory> Function()? createSubtitleDirectory,
  }) =>
      MediaKitAdvancedVideoPort(
        player,
        readProperty: (name) async => properties[name] ?? '',
        writeProperty: (name, value) async {
          if (!ignoreWrites && ignoredProperty != name) {
            properties[name] = value;
          }
        },
        createSubtitleDirectory: createSubtitleDirectory,
      );

  void emitDimensions(int width, int height) {
    state = state.copyWith(width: width, height: height);
    widthController.add(width);
    heightController.add(height);
  }

  void emitError(String error) => errorController.add(error);

  bool get hasAdvancedListeners =>
      widthController.hasListener ||
      heightController.hasListener ||
      trackController.hasListener ||
      tracksController.hasListener ||
      errorController.hasListener;

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    properties['aid'] = track.id;
    state = state.copyWith(track: state.track.copyWith(audio: track));
    trackController.add(state.track);
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    lastSubtitle = track;
    await beforeSubtitle?.call();
    properties['sid'] = track.uri ? '4' : track.id;
    state = state.copyWith(track: state.track.copyWith(subtitle: track));
    trackController.add(state.track);
  }
}
