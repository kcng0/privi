import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

/// Unified in-memory + on-disk thumbnail cache shared by the Visible and
/// Invisible grids.
///
/// A single instance fronts both surfaces so grid rendering is fast and
/// persistent across restarts, independent of photo_manager/Glide's own cache.
/// Both grids call [get] with the same size and display widget; only the
/// [produce] callback differs (photo_manager for Visible, the vault poster/file
/// for Invisible), so a video's thumbnail behaves identically in either tab.
///
/// The vault's canonical poster (`vault/thumbs/<id>.jpg`) remains the source of
/// truth for the viewer/DB/export — this cache only stores decoded, grid-sized
/// bytes and regenerates them on demand.
///
/// Entries are keyed by a caller-supplied stable [key] plus the requested
/// [size], so the same asset can be cached at several dimensions without
/// collisions.
class ThumbnailCache {
  ThumbnailCache({
    required Future<Directory> Function() cacheDir,
    this.maxEntries = 256,
    this.maxBytes = 96 << 20,
  }) : _cacheDir = cacheDir;

  final Future<Directory> Function() _cacheDir;

  /// Soft ceiling on retained decoded thumbnails (LRU eviction).
  final int maxEntries;

  /// Soft ceiling on retained decoded bytes (LRU eviction).
  final int maxBytes;

  final LinkedHashMap<String, Uint8List> _mem = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _inflight = {};
  int _memBytes = 0;
  Directory? _dir;

  static String _slot(String key, int size) => '$key@$size';

  /// Stable (cross-run) FNV-1a hash so disk filenames survive restarts.
  static String _hash(String key) {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash = (hash ^ unit) & 0xffffffff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }

  static String _fileName(String key, int size) => '${_hash(key)}_$size.jpg';

  /// Returns cached bytes for [key]/[size], falling back to disk, then
  /// [produce]. Concurrent requests for the same slot share one [produce] call.
  Future<Uint8List?> get({
    required String key,
    required int size,
    required Future<Uint8List?> Function() produce,
  }) {
    final slot = _slot(key, size);
    final cached = _mem[slot];
    if (cached != null) {
      _touch(slot, cached);
      return Future.value(cached);
    }

    final pending = _inflight[slot];
    if (pending != null) return pending;

    final future = _load(key, size, slot, produce);
    _inflight[slot] = future;
    return future;
  }

  Future<Uint8List?> _load(
    String key,
    int size,
    String slot,
    Future<Uint8List?> Function() produce,
  ) async {
    try {
      final file = await _fileFor(key, size);
      if (await file.exists()) {
        try {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            _put(slot, bytes);
            return bytes;
          }
        } catch (_) {
          // Corrupt/partial cache file — regenerate below.
        }
      }

      final produced = await produce();
      if (produced == null || produced.isEmpty) return null;

      _put(slot, produced);
      try {
        await file.writeAsBytes(produced, flush: false);
      } catch (_) {
        // Disk write is best-effort; the in-memory copy still serves this run.
      }
      return produced;
    } finally {
      final _ = _inflight.remove(slot);
    }
  }

  /// Returns already-resident bytes without any I/O.
  Uint8List? peek(String key, int size) => _mem[_slot(key, size)];

  /// Drops [key] at every size from memory and disk.
  Future<void> evict(String key) async {
    final prefix = '$key@';
    _mem.keys
        .where((slot) => slot.startsWith(prefix))
        .toList(growable: false)
        .forEach((slot) {
      final bytes = _mem.remove(slot);
      if (bytes != null) _memBytes -= bytes.length;
    });

    final dir = _dir;
    if (dir == null) return;
    final hashPrefix = '${_hash(key)}_';
    try {
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith(hashPrefix)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  void clearMemory() {
    _mem.clear();
    _memBytes = 0;
  }

  Future<File> _fileFor(String key, int size) async {
    final dir = await _resolveDir();
    return File('${dir.path}${Platform.pathSeparator}${_fileName(key, size)}');
  }

  Future<Directory> _resolveDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final dir = await _cacheDir();
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  void _touch(String slot, Uint8List bytes) {
    _mem.remove(slot);
    _mem[slot] = bytes;
  }

  void _put(String slot, Uint8List bytes) {
    final prior = _mem.remove(slot);
    if (prior != null) _memBytes -= prior.length;
    _mem[slot] = bytes;
    _memBytes += bytes.length;
    _trim();
  }

  void _trim() {
    while (_mem.isNotEmpty &&
        (_mem.length > maxEntries || _memBytes > maxBytes)) {
      final oldest = _mem.keys.first;
      final bytes = _mem.remove(oldest);
      if (bytes != null) _memBytes -= bytes.length;
    }
  }
}
