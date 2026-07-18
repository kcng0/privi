import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/services/thumbnail_cache.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('thumb_cache_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ThumbnailCache cacheFor({int maxEntries = 256}) => ThumbnailCache(
        cacheDir: () async => dir,
        maxEntries: maxEntries,
      );

  Uint8List bytes(List<int> b) => Uint8List.fromList(b);

  test('produces once, then serves from memory', () async {
    final cache = cacheFor();
    var calls = 0;
    Future<Uint8List?> produce() async {
      calls++;
      return bytes([1, 2, 3]);
    }

    expect(await cache.get(key: 'a', size: 512, produce: produce), [1, 2, 3]);
    expect(await cache.get(key: 'a', size: 512, produce: produce), [1, 2, 3]);
    expect(calls, 1);
    expect(cache.peek('a', 512), isNotNull);
  });

  test('persists to disk across instances (no reproduce)', () async {
    final first = cacheFor();
    await first.get(key: 'a', size: 512, produce: () async => bytes([9, 9]));

    final second = cacheFor();
    var calls = 0;
    final result = await second.get(
      key: 'a',
      size: 512,
      produce: () async {
        calls++;
        return bytes([0]);
      },
    );
    expect(result, [9, 9]);
    expect(calls, 0);
  });

  test('separate sizes do not collide', () async {
    final cache = cacheFor();
    await cache.get(key: 'a', size: 512, produce: () async => bytes([5]));
    var calls = 0;
    final big = await cache.get(
      key: 'a',
      size: 768,
      produce: () async {
        calls++;
        return bytes([7]);
      },
    );
    expect(big, [7]);
    expect(calls, 1);
    expect(cache.peek('a', 512), [5]);
    expect(cache.peek('a', 768), [7]);
  });

  test('evict clears memory and disk for all sizes', () async {
    final cache = cacheFor();
    await cache.get(key: 'a', size: 512, produce: () async => bytes([1]));
    await cache.get(key: 'a', size: 768, produce: () async => bytes([2]));

    await cache.evict('a');
    expect(cache.peek('a', 512), isNull);
    expect(cache.peek('a', 768), isNull);
    expect(dir.listSync().whereType<File>(), isEmpty);

    var calls = 0;
    await cache.get(
      key: 'a',
      size: 512,
      produce: () async {
        calls++;
        return bytes([1]);
      },
    );
    expect(calls, 1);
  });

  test('concurrent requests share a single produce', () async {
    final cache = cacheFor();
    final gate = Completer<void>();
    var calls = 0;
    Future<Uint8List?> produce() async {
      calls++;
      await gate.future;
      return bytes([4, 2]);
    }

    final a = cache.get(key: 'x', size: 512, produce: produce);
    final b = cache.get(key: 'x', size: 512, produce: produce);
    gate.complete();
    expect(await a, [4, 2]);
    expect(await b, [4, 2]);
    expect(calls, 1);
  });

  test('LRU trims oldest beyond maxEntries', () async {
    final cache = cacheFor(maxEntries: 2);
    await cache.get(key: 'a', size: 1, produce: () async => bytes([1]));
    await cache.get(key: 'b', size: 1, produce: () async => bytes([2]));
    // Touch 'a' so 'b' becomes least-recently-used.
    await cache.get(key: 'a', size: 1, produce: () async => bytes([9]));
    await cache.get(key: 'c', size: 1, produce: () async => bytes([3]));

    expect(cache.peek('b', 1), isNull); // evicted
    expect(cache.peek('a', 1), isNotNull);
    expect(cache.peek('c', 1), isNotNull);
  });
}
