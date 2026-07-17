import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../domain/models/media_item.dart';
import '../db/database.dart';
import '../repositories/album_repository.dart';
import '../repositories/media_repository.dart';
import 'hide_naming.dart';
import 'vault_storage_service.dart';

/// Local export/import durability (D3) — no cloud.
class VaultBackupService {
  VaultBackupService({
    required AppDatabase db,
    required MediaRepository media,
    required AlbumRepository albums,
    required VaultStorageService storage,
    Uuid? uuid,
  })  : _db = db,
        _media = media,
        _albums = albums,
        _storage = storage,
        _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final MediaRepository _media;
  final AlbumRepository _albums;
  final VaultStorageService _storage;
  final Uuid _uuid;

  static const manifestName = 'privi_manifest.json';

  /// Write media + JSON manifest into [destDir].
  Future<int> exportToDirectory(String destDir) async {
    final dir = Directory(destDir);
    if (!await dir.exists()) await dir.create(recursive: true);

    final mediaDir = Directory(p.join(destDir, 'media'));
    if (!await mediaDir.exists()) await mediaDir.create();

    final rows = await _db.watchActiveMedia().first;
    final deleted = await _db.watchRecycleBin().first;
    final all = [...rows, ...deleted];

    final albums = await _db.getAllAlbums();
    final mediaJson = <Map<String, dynamic>>[];
    var copied = 0;

    for (final r in all) {
      final src = File(r.privatePath);
      if (!await src.exists()) continue;
      final ext = p.extension(r.privatePath);
      final destName = '${r.id}$ext';
      final dest = File(p.join(mediaDir.path, destName));
      await src.copy(dest.path);
      copied++;

      String? thumbDest;
      if (r.thumbnailPath != null && r.thumbnailPath!.isNotEmpty) {
        final t = File(r.thumbnailPath!);
        if (await t.exists()) {
          final td = File(p.join(mediaDir.path, '${r.id}.thumb.png'));
          await t.copy(td.path);
          thumbDest = p.basename(td.path);
        }
      }

      mediaJson.add({
        'id': r.id,
        'file': destName,
        'thumb': thumbDest,
        'originalName': r.originalName,
        'mimeType': r.mimeType,
        'isVideo': r.isVideo,
        'width': r.width,
        'height': r.height,
        'durationMs': r.durationMs,
        'rating': r.rating,
        'dateAdded': r.dateAdded.toIso8601String(),
        'dateTaken': r.dateTaken?.toIso8601String(),
        'sizeBytes': r.sizeBytes,
        'deletedAt': r.deletedAt?.toIso8601String(),
      });
    }

    final albumJson = albums
        .map(
          (a) => {
            'id': a.id,
            'name': a.name,
            'isSystem': a.isSystem,
            'coverMediaId': a.coverMediaId,
            'createdAt': a.createdAt.toIso8601String(),
            'systemKind': a.systemKind,
          },
        )
        .toList();

    final manifest = {
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'media': mediaJson,
      'albums': albumJson,
    };

    final man = File(p.join(destDir, manifestName));
    await man
        .writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
    return copied;
  }

  /// Restore from a previously exported folder. Returns items imported.
  Future<int> importFromDirectory(String srcDir) async {
    final man = File(p.join(srcDir, manifestName));
    if (!await man.exists()) {
      throw StateError('No $manifestName in folder');
    }
    final map = jsonDecode(await man.readAsString()) as Map<String, dynamic>;
    final mediaList =
        (map['media'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final mediaDir = Directory(p.join(srcDir, 'media'));
    var n = 0;

    for (final m in mediaList) {
      final fileName = m['file'] as String?;
      if (fileName == null) continue;
      final src = File(p.join(mediaDir.path, fileName));
      if (!await src.exists()) continue;

      final isVideo = m['isVideo'] as bool? ?? false;
      final originalName = m['originalName'] as String? ?? fileName;
      // Place restored files under app external-ish thumbs parent then hide-name
      // Prefer keeping exported relative layout: copy beside export into a
      // dedicated restore folder under app documents, then mark hidden name.
      final restoreRoot = await _storage.ensureVault();
      final restoredDir = Directory(p.join(restoreRoot.path, 'restored'));
      if (!await restoredDir.exists()) await restoredDir.create();

      final baseVisible = HideNaming.displayName(originalName);
      final destVisible = File(p.join(restoredDir.path, baseVisible));
      // Avoid clobber
      final unique = await _uniquePath(destVisible);
      await src.copy(unique.path);

      final hiddenPath = HideNaming.toHiddenPath(unique.path, isVideo: isVideo);
      final hidden =
          unique.path == hiddenPath ? unique : await unique.rename(hiddenPath);

      final id = (m['id'] as String?) ?? _uuid.v4();
      String? thumbPath;
      final thumbName = m['thumb'] as String?;
      if (thumbName != null) {
        final ts = File(p.join(mediaDir.path, thumbName));
        if (await ts.exists()) {
          final td = await _storage.thumbFileFor(id);
          await ts.copy(td.path);
          thumbPath = td.path;
        }
      }

      final item = MediaItem(
        id: id,
        privatePath: hidden.path,
        originalName: originalName,
        mimeType:
            m['mimeType'] as String? ?? (isVideo ? 'video/mp4' : 'image/jpeg'),
        isVideo: isVideo,
        width: m['width'] as int?,
        height: m['height'] as int?,
        durationMs: m['durationMs'] as int?,
        rating: (m['rating'] as int?) ?? 0,
        dateAdded: DateTime.tryParse(m['dateAdded'] as String? ?? '') ??
            DateTime.now().toUtc(),
        dateTaken: DateTime.tryParse(m['dateTaken'] as String? ?? ''),
        sizeBytes: (m['sizeBytes'] as int?) ?? await hidden.length(),
        thumbnailPath: thumbPath,
        deletedAt: DateTime.tryParse(m['deletedAt'] as String? ?? ''),
      );

      // Skip if id already exists
      final existing = await _db.getMediaById(id);
      if (existing != null) continue;

      await _media.insert(item);
      if (item.deletedAt != null) {
        await _media.softDelete(item.id);
      }
      n++;
    }

    // User albums from manifest (optional, best-effort).
    final albumList =
        (map['albums'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    for (final a in albumList) {
      final isSystem = a['isSystem'] as bool? ?? true;
      if (isSystem) continue;
      final name = a['name'] as String?;
      if (name == null || name.isEmpty) continue;
      try {
        await _albums.createUserAlbum(name);
      } catch (e) {
        debugPrint('album restore: $e');
      }
    }

    return n;
  }

  Future<File> _uniquePath(File desired) async {
    if (!await desired.exists()) return desired;
    final dir = p.dirname(desired.path);
    final base = p.basenameWithoutExtension(desired.path);
    final ext = p.extension(desired.path);
    for (var i = 1; i < 1000; i++) {
      final f = File(p.join(dir, '${base}_$i$ext'));
      if (!await f.exists()) return f;
    }
    return File(p.join(dir, '${base}_${_uuid.v4()}$ext'));
  }
}
