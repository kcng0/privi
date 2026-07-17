import 'package:flutter/foundation.dart';

import '../../core/media_thumbnail_spec.dart';
import 'import/asset_gateway.dart';

/// Shared boundary for Visible poster loading and hide-time poster reuse.
abstract interface class MediaThumbnailCache {
  Future<Uint8List?> load(String assetId);

  /// Returns only an already-rendered poster. This method never starts I/O.
  Uint8List? peek(String assetId);

  void evict(String assetId);

  void clear();
}

/// Bounded in-memory cache for the canonical MediaStore poster bytes.
class MediaThumbnailService implements MediaThumbnailCache {
  MediaThumbnailService({required AssetGateway assetGateway})
      : _assets = assetGateway;

  final AssetGateway _assets;
  final Map<String, Uint8List> _cache = {};
  final Map<String, Future<Uint8List?>> _loads = {};

  @override
  Future<Uint8List?> load(String assetId) {
    final cached = _cache[assetId];
    if (cached != null) return Future.value(cached);

    return _loads.putIfAbsent(assetId, () async {
      try {
        final bytes = await _assets
            .thumbnailBytes(
              assetId,
              size: MediaThumbnailSpec.dimension,
              quality: MediaThumbnailSpec.quality,
              frameUs: MediaThumbnailSpec.videoFrameUs,
            )
            .timeout(const Duration(seconds: 6));
        if (bytes == null || bytes.isEmpty) return null;
        _cache[assetId] = bytes;
        if (_cache.length > MediaThumbnailSpec.memoryCacheEntries) {
          _cache.remove(_cache.keys.first);
        }
        return bytes;
      } catch (error, stackTrace) {
        debugPrint('media thumbnail $assetId: $error\n$stackTrace');
        return null;
      } finally {
        final _ = _loads.remove(assetId);
      }
    });
  }

  @override
  Uint8List? peek(String assetId) => _cache[assetId];

  @override
  void evict(String assetId) => _cache.remove(assetId);

  @override
  void clear() {
    _cache.clear();
    _loads.clear();
  }
}
