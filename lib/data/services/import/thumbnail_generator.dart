import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../core/media_thumbnail_spec.dart';
import '../../repositories/media_repository.dart';
import '../media_rename_service.dart';
import '../media_thumbnail_service.dart';
import '../vault_storage_service.dart';
import 'file_system_gateway.dart';
import 'hide_preparer.dart';
import 'import_models.dart';

class ThumbnailJob {
  const ThumbnailJob({
    required this.id,
    required this.privatePath,
    required this.isVideo,
    this.assetId,
    this.sourceThumbnailBytes,
  });

  final String id;
  final String privatePath;
  final bool isVideo;
  final String? assetId;
  final Uint8List? sourceThumbnailBytes;
}

class ThumbnailGenerator {
  const ThumbnailGenerator({
    required VaultStorageService storage,
    required MediaRepository mediaRepository,
    required MediaRenameService renamer,
    required MediaThumbnailCache thumbnailCache,
    required FileSystemGateway fileSystem,
  })  : _storage = storage,
        _media = mediaRepository,
        _renamer = renamer,
        _thumbnails = thumbnailCache,
        _files = fileSystem;

  final VaultStorageService _storage;
  final MediaRepository _media;
  final MediaRenameService _renamer;
  final MediaThumbnailCache _thumbnails;
  final FileSystemGateway _files;

  static const int concurrency = 2;

  /// Reuses posters that Visible already rendered without delaying the native
  /// transfer for uncached media. Missing posters are generated after hiding.
  Future<List<PreparedHide>> attachCachedPosters(
    List<PreparedHide> jobs,
  ) async {
    return List<PreparedHide>.unmodifiable(jobs.map(_attachCachedPoster));
  }

  PreparedHide _attachCachedPoster(PreparedHide job) {
    final assetId = job.source.assetId;
    if (assetId == null) return job;
    final bytes = _thumbnails.peek(assetId);
    if (bytes == null || bytes.isEmpty) return job;
    return job.withThumbnailBytes(bytes);
  }

  Future<void> generateDeferred(
    List<ThumbnailJob> jobs,
    ImportSession session,
  ) async {
    var next = 0;
    Future<void> worker() async {
      while (!session.isCancelled) {
        final index = next;
        if (index >= jobs.length) return;
        next = index + 1;
        final job = jobs[index];
        try {
          await generateOne(job).timeout(
            const Duration(seconds: 6),
          );
        } catch (error, stackTrace) {
          debugPrint('deferred thumb ${job.id}: $error\n$stackTrace');
        }
      }
    }

    final workers = jobs.length < concurrency ? jobs.length : concurrency;
    await Future.wait(List.generate(workers, (_) => worker()));
  }

  Future<String?> generateOne(ThumbnailJob job) async {
    final path = await makeThumbnail(job);
    if (path != null && path.isNotEmpty) {
      await _media.updateThumbnail(job.id, path);
    }
    return path;
  }

  /// Upgrades thumbnails created by earlier releases without touching media
  /// whose v2 poster is already present. Failed items remain eligible for the
  /// next launch instead of being marked complete.
  Future<int> repairOutdatedVideos() async {
    final items = await _media.listActive();
    final videos = items.where((item) => item.isVideo).toList(growable: false);
    var next = 0;
    var repaired = 0;

    Future<void> worker() async {
      while (true) {
        final index = next;
        if (index >= videos.length) return;
        next = index + 1;
        final item = videos[index];
        final oldPath = item.thumbnailPath;
        try {
          if (MediaThumbnailSpec.isCurrentPath(oldPath) &&
              oldPath != null &&
              await _files.exists(oldPath)) {
            continue;
          }
          final path = await generateOne(
            ThumbnailJob(
              id: item.id,
              privatePath: item.privatePath,
              isVideo: true,
            ),
          ).timeout(const Duration(seconds: 8));
          if (path == null) {
            debugPrint('thumbnail repair ${item.id}: no poster generated');
            continue;
          }
          repaired++;
          if (oldPath != null && oldPath.isNotEmpty && oldPath != path) {
            try {
              if (await _files.exists(oldPath)) await _files.delete(oldPath);
            } catch (error, stackTrace) {
              debugPrint(
                'delete legacy thumb ${item.id}: $error\n$stackTrace',
              );
            }
          }
        } catch (error, stackTrace) {
          debugPrint('thumbnail repair ${item.id}: $error\n$stackTrace');
        }
      }
    }

    final workers = videos.length < concurrency ? videos.length : concurrency;
    await Future.wait(List.generate(workers, (_) => worker()));
    return repaired;
  }

  Future<String?> makeThumbnail(ThumbnailJob job) async {
    final sourceThumbnailBytes = job.sourceThumbnailBytes;
    if (sourceThumbnailBytes != null && sourceThumbnailBytes.isNotEmpty) {
      final output = await _storage.thumbFileFor(job.id);
      await _files.writeBytes(output.path, sourceThumbnailBytes);
      return output.path;
    }

    final assetId = job.assetId;
    if (assetId != null) {
      try {
        final bytes = await _thumbnails.load(assetId);
        if (bytes != null && bytes.isNotEmpty) {
          final nearBlack = job.isVideo && await isNearBlackImageBytes(bytes);
          if (!nearBlack) {
            final output = await _storage.thumbFileFor(job.id);
            await _files.writeBytes(output.path, bytes);
            return output.path;
          }
          debugPrint('asset thumb rejected (near-black) for ${job.id}');
        }
      } catch (error, stackTrace) {
        debugPrint('asset thumb: $error\n$stackTrace');
      }
    }

    if (job.isVideo) {
      try {
        final output = await _storage.thumbFileFor(job.id);
        final ok = await _renamer.videoThumbnail(
          path: job.privatePath,
          destPath: output.path,
          maxSize: MediaThumbnailSpec.dimension,
        );
        if (ok &&
            await _files.exists(output.path) &&
            await _files.length(output.path) > 0) {
          return output.path;
        }
      } catch (error, stackTrace) {
        debugPrint('video thumb: $error\n$stackTrace');
      }
      return null;
    }

    try {
      if (await _files.length(job.privatePath) > 8 * 1024 * 1024) return null;
      final bytes = await _files.readBytes(job.privatePath);
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: MediaThumbnailSpec.dimension,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      if (data == null) return null;
      final output = await _storage.thumbFileFor(job.id);
      await _files.writeBytes(
        output.path,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      return output.path;
    } catch (error, stackTrace) {
      debugPrint('file thumb: $error\n$stackTrace');
      return null;
    }
  }

  /// True when average Rec.601 luma is below [threshold] (0–255).
  Future<bool> isNearBlackImageBytes(
    Uint8List bytes, {
    double threshold = 15.0,
  }) async {
    ui.Image? image;
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return false;
      final width = image.width;
      final height = image.height;
      if (width <= 0 || height <= 0) return false;

      final rgba = data.buffer.asUint8List();
      var total = 0.0;
      var samples = 0;
      final stepX = (width / 10).floor().clamp(1, width);
      final stepY = (height / 10).floor().clamp(1, height);
      for (var y = 0; y < height; y += stepY) {
        for (var x = 0; x < width; x += stepX) {
          final index = (y * width + x) * 4;
          if (index + 2 >= rgba.length) continue;
          total += 0.299 * rgba[index] +
              0.587 * rgba[index + 1] +
              0.114 * rgba[index + 2];
          samples++;
        }
      }
      return samples > 0 && (total / samples) < threshold;
    } catch (error, stackTrace) {
      debugPrint('luma check: $error\n$stackTrace');
      return false;
    } finally {
      image?.dispose();
    }
  }
}
