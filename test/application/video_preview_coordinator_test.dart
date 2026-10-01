import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/player/video_preview_coordinator.dart';

void main() {
  testWidgets('two seek controls share one decoder and newest request wins',
      (tester) async {
    final requests = <Duration>[];
    final results = <Completer<Uint8List?>>[];
    final previews = VideoPreviewCoordinator(
      delay: const Duration(milliseconds: 1),
      load: (position) {
        requests.add(position);
        final result = Completer<Uint8List?>();
        results.add(result);
        return result.future;
      },
    );
    addTearDown(previews.dispose);

    final first = previews.requestFrame(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    final skipped = previews.requestFrame(const Duration(seconds: 2));
    final last = previews.requestFrame(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(requests, [const Duration(seconds: 1)]);
    expect(await first, isNull);
    expect(await skipped, isNull);

    results.first.complete(Uint8List.fromList([1]));
    await tester.pump();
    expect(previews.value, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(requests, [const Duration(seconds: 1), const Duration(seconds: 3)]);
    results.last.complete(Uint8List.fromList([3]));
    await tester.pump();
    expect(await last, [3]);
    expect(previews.value!.position, const Duration(seconds: 3));
  });

  testWidgets('nearby requests share cached frames with bounded eviction',
      (tester) async {
    var calls = 0;
    final previews = VideoPreviewCoordinator(
      cacheCapacity: 2,
      maxCacheBytes: 4,
      delay: const Duration(milliseconds: 1),
      load: (position) async {
        calls++;
        return Uint8List.fromList([position.inSeconds, 0]);
      },
    );
    addTearDown(previews.dispose);

    Future<void> decode(int milliseconds) async {
      final request =
          previews.requestFrame(Duration(milliseconds: milliseconds));
      await tester.pump(const Duration(milliseconds: 1));
      expect(await request, isNotNull);
    }

    await decode(1000);
    await decode(1100);
    expect(calls, 1);
    await decode(2000);
    await decode(3000);
    await decode(1000);
    expect(calls, 4);
  });

  testWidgets('clearing and disposing invalidates in-flight preview results',
      (tester) async {
    final decoded = Completer<Uint8List?>();
    final previews = VideoPreviewCoordinator(
      delay: const Duration(milliseconds: 1),
      load: (_) => decoded.future,
    );
    final first = previews.requestFrame(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    previews.clear();
    expect(await first, isNull);
    final pending = previews.requestFrame(const Duration(seconds: 2));
    previews.dispose();
    expect(await pending, isNull);
    decoded.complete(Uint8List.fromList([1]));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview errors are diagnosed and a later request still works',
      (tester) async {
    final errors = <Object>[];
    var calls = 0;
    final previews = VideoPreviewCoordinator(
      delay: const Duration(milliseconds: 1),
      onError: (error, _) => errors.add(error),
      load: (_) async {
        if (calls++ == 0) throw StateError('unsupported thumbnail codec');
        return Uint8List.fromList([7]);
      },
    );
    addTearDown(previews.dispose);
    final failed = previews.requestFrame(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(await failed, isNull);
    expect(errors, hasLength(1));
    final retry = previews.requestFrame(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 1));
    expect(await retry, [7]);
  });
}
