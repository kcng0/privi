import 'package:flutter/foundation.dart';

import '../../../domain/models/media_item.dart';
import '../../repositories/media_repository.dart';
import 'vault_transfer_runner.dart';

class RecordedHide {
  const RecordedHide({required this.outcome, required this.item});

  final TransferOutcome outcome;
  final MediaItem item;
}

class MediaRecorder {
  MediaRecorder({
    required MediaRepository mediaRepository,
    DateTime Function()? now,
  })  : _media = mediaRepository,
        _now = now ?? DateTime.now;

  final MediaRepository _media;
  final DateTime Function() _now;

  Future<List<RecordedHide>> record(List<TransferOutcome> outcomes) async {
    final recorded = <RecordedHide>[];
    final pending = <({MediaItem item, String? userAlbumId})>[];
    for (final outcome in outcomes) {
      if (!outcome.ok) continue;
      final job = outcome.job;
      final item = MediaItem(
        id: job.id,
        privatePath: outcome.destinationPath!,
        originalPath: job.originalPath,
        originalName: job.originalName,
        mimeType: job.mimeType,
        isVideo: job.isVideo,
        rating: 0,
        dateAdded: job.dateTaken?.toUtc() ?? _now().toUtc(),
        dateTaken: job.dateTaken?.toUtc(),
        sizeBytes: outcome.sizeBytes!,
      );
      recorded.add(RecordedHide(outcome: outcome, item: item));
      pending.add((item: item, userAlbumId: job.albumId));
    }
    if (pending.isEmpty) return const [];

    try {
      await _media.insertMany(pending);
      return List<RecordedHide>.unmodifiable(recorded);
    } catch (error, stackTrace) {
      debugPrint('batch DB insert failed: $error\n$stackTrace');
      final insertedIds = <String>{};
      for (final entry in pending) {
        try {
          await _media.insert(
            entry.item,
            userAlbumId: entry.userAlbumId,
          );
          insertedIds.add(entry.item.id);
        } catch (singleError, singleStackTrace) {
          debugPrint(
            'single DB insert failed ${entry.item.id}: '
            '$singleError\n$singleStackTrace',
          );
        }
      }
      return List<RecordedHide>.unmodifiable(
        recorded.where((record) => insertedIds.contains(record.item.id)),
      );
    }
  }
}
