import 'dart:io';
import 'dart:typed_data';

import '../../domain/models/media_item.dart';
import 'thumbnail_cache.dart';

/// One producer for both grids: Visible and Invisible tiles call this, share
/// the same [ThumbnailCache] and size, and get the identical representative
/// frame. Only the byte source differs — a MediaStore asset (still visible) vs.
/// the persisted vault poster / file (already hidden) — because a hidden item
/// no longer exists in MediaStore.
class GridThumbnailService {
  GridThumbnailService({
    required ThumbnailCache cache,
    required Future<Uint8List?> Function(String assetId, int size) decodeAsset,
    required Future<String?> Function(MediaItem item) ensureVaultPoster,
  })  : _cache = cache,
        _decodeAsset = decodeAsset,
        _ensureVaultPoster = ensureVaultPoster;

  final ThumbnailCache _cache;
  final Future<Uint8List?> Function(String assetId, int size) _decodeAsset;
  final Future<String?> Function(MediaItem item) _ensureVaultPoster;

  /// Visible grid tile — MediaStore asset poster at [size].
  Future<Uint8List?> forAsset(String assetId, {required int size}) {
    return _cache.get(
      key: 'vis:$assetId',
      size: size,
      produce: () => _decodeAsset(assetId, size),
    );
  }

  /// Invisible grid tile — the same poster, sourced from the persisted vault
  /// thumbnail (generated on demand for videos that lack one).
  Future<Uint8List?> forVaultItem(MediaItem item, {required int size}) {
    return _cache.get(
      key: 'vault:${item.id}',
      size: size,
      produce: () => _produceVault(item),
    );
  }

  Future<Uint8List?> _produceVault(MediaItem item) async {
    final poster = item.thumbnailPath;
    if (poster != null && poster.isNotEmpty) {
      final file = File(poster);
      if (await file.exists()) return file.readAsBytes();
    }
    if (item.isVideo) {
      // No poster yet (e.g. hidden before generation finished) — generate now.
      final generated = await _ensureVaultPoster(item);
      if (generated != null && generated.isNotEmpty) {
        final file = File(generated);
        if (await file.exists()) return file.readAsBytes();
      }
      return null;
    }
    // Un-postered image (e.g. capped large file) — fall back to the original.
    final original = File(item.privatePath);
    if (await original.exists()) return original.readAsBytes();
    return null;
  }

  /// Drops both tabs' cached entries for an item identity.
  Future<void> evictAsset(String assetId) => _cache.evict('vis:$assetId');
  Future<void> evictVault(String id) => _cache.evict('vault:$id');
}
