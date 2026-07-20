import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
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
    bool usePrivateMediaStorage = false,
  })  : _db = db,
        _media = media,
        _albums = albums,
        _storage = storage,
        _uuid = uuid ?? const Uuid(),
        _usePrivateMediaStorage = usePrivateMediaStorage;

  final AppDatabase _db;
  final MediaRepository _media;
  final AlbumRepository _albums;
  final VaultStorageService _storage;
  final Uuid _uuid;
  final bool _usePrivateMediaStorage;

  String get _platformName => _usePrivateMediaStorage ? 'ios' : 'android';

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
    final groups = await _db.getAllAlbumGroups();
    final memberships = await _db.getAllMemberships();
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
        'originalPath': r.originalPath,
        'source': r.sourcePlatformId == null
            ? null
            : {
                'platform': _platformName,
                'libraryId': r.sourcePlatformId,
              },
        'sourceRemovalPending': r.sourceRemovalPending,
        'contentDigest': r.contentDigest,
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
            'pinnedAt': a.pinnedAt?.toIso8601String(),
            'rating': a.rating,
            'sortIndex': a.sortIndex,
            'groupId': a.groupId,
          },
        )
        .toList();

    final groupJson = groups
        .map(
          (group) => {
            'id': group.id,
            'name': group.name,
            'createdAt': group.createdAt.toIso8601String(),
            'sortIndex': group.sortIndex,
          },
        )
        .toList(growable: false);

    final membershipJson = memberships
        .map(
          (membership) => {
            'albumId': membership.albumId,
            'mediaId': membership.mediaId,
            'addedAt': membership.addedAt.toIso8601String(),
          },
        )
        .toList(growable: false);

    final manifest = {
      'version': 4,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'media': mediaJson,
      'albums': albumJson,
      'albumGroups': groupJson,
      'membership': membershipJson,
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
    final version = map['version'] as int? ?? 1;
    if (version < 1 || version > 4) {
      throw StateError('Unsupported vault manifest version: $version');
    }
    final mediaList =
        (map['media'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final mediaDir = Directory(p.join(srcDir, 'media'));
    var n = 0;

    final groupIdMap =
        version >= 3 ? await _restoreV3Groups(map) : const <String, String>{};
    final albumIdMap = version >= 2
        ? await _restoreV2Albums(
            map,
            groupIdMap: groupIdMap,
            restoreOrganizer: version >= 3,
          )
        : const <String, String>{};

    for (final m in mediaList) {
      final fileName = m['file'] as String?;
      if (fileName == null) continue;
      final src = await _backupFile(mediaDir, fileName);
      if (src == null) continue;

      final id = _validatedId((m['id'] as String?) ?? _uuid.v4(), 'media id');
      if (await _db.getMediaById(id) != null) continue;

      final isVideo = m['isVideo'] as bool? ?? false;
      final originalName = m['originalName'] as String? ?? fileName;
      final originalPath = version >= 2
          ? _validatedOriginalPath(m['originalPath'] as String?)
          : null;
      final source = version >= 4 ? _sourceMetadata(m['source']) : null;
      final sourceFolder = _sourceFolder(originalPath);
      final destination = await _restoreDestination(
        id: id,
        originalName: originalName,
        sourceFolder: sourceFolder,
      );
      final hidden = destination;
      if (!await hidden.exists() || await hidden.length() == 0) {
        await src.copy(hidden.path);
      }
      final restoredSize = await hidden.length();
      if (restoredSize == 0) {
        throw StateError('Restored media is empty: $fileName');
      }

      String? thumbPath;
      final thumbName = m['thumb'] as String?;
      if (thumbName != null) {
        final ts = await _backupFile(mediaDir, thumbName);
        if (ts != null) {
          final td = await _storage.thumbFileFor(id);
          await ts.copy(td.path);
          thumbPath = td.path;
        }
      }

      final item = MediaItem(
        id: id,
        privatePath: hidden.path,
        originalPath: originalPath,
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
        sizeBytes: restoredSize,
        thumbnailPath: thumbPath,
        deletedAt: DateTime.tryParse(m['deletedAt'] as String? ?? ''),
        sourcePlatformId:
            _sourceMatchesTarget(source) ? source?.libraryId : null,
        sourceRemovalPending: _sourceMatchesTarget(source) &&
            (version >= 4
                ? m['sourceRemovalPending'] as bool? ?? false
                : false),
        contentDigest: version >= 4 ? m['contentDigest'] as String? : null,
      );

      await _media.insert(item);
      n++;
    }

    if (version >= 2) {
      await _restoreMemberships(map, albumIdMap);
    } else {
      await _restoreV1Albums(map);
    }

    return n;
  }

  String _sourceFolder(String? originalPath) {
    if (originalPath == null || originalPath.trim().isEmpty) return 'Imported';
    return HideNaming.sanitizeFolder(p.basename(p.dirname(originalPath)));
  }

  Future<File> _restoreDestination({
    required String id,
    required String originalName,
    required String sourceFolder,
  }) async {
    if (_usePrivateMediaStorage) {
      return _storage.privateMediaFileFor(
        id: id,
        originalName: originalName,
        sourceFolder: sourceFolder,
      );
    }
    final path = await _storage.hiddenDestPath(
      id: id,
      originalName: originalName,
      sourceFolder: sourceFolder,
    );
    return File(path);
  }

  ({String platform, String libraryId})? _sourceMetadata(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, dynamic>) {
      throw const FormatException('source must be an object');
    }
    final platform = value['platform'] as String?;
    final libraryId = value['libraryId'] as String?;
    if (platform == null ||
        platform.trim().isEmpty ||
        libraryId == null ||
        libraryId.trim().isEmpty) {
      throw const FormatException('source requires platform and libraryId');
    }
    return (platform: platform.trim(), libraryId: libraryId.trim());
  }

  bool _sourceMatchesTarget(({String platform, String libraryId})? source) {
    return source?.platform.toLowerCase() == _platformName;
  }

  Future<Map<String, String>> _restoreV2Albums(
    Map<String, dynamic> manifest, {
    Map<String, String> groupIdMap = const {},
    bool restoreOrganizer = false,
  }) async {
    final albumList = (manifest['albums'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final restoredIds = <String, String>{};
    for (final data in albumList) {
      if (data['isSystem'] as bool? ?? true) continue;
      final rawId = data['id'] as String?;
      final name = data['name'] as String?;
      if (rawId == null || name == null || name.trim().isEmpty) {
        throw const FormatException('User album requires id and name');
      }
      final id = _validatedId(rawId, 'album id');
      final existing = await _albums.getById(id);
      if (existing != null) {
        if (existing.isSystem) {
          throw StateError('User album id collides with system album: $id');
        }
        if (existing.name.toLowerCase() != name.trim().toLowerCase()) {
          throw StateError('User album id collides with another album: $id');
        }
        restoredIds[id] = existing.id;
        continue;
      }
      final createdAt = DateTime.tryParse(data['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final pinnedAt = DateTime.tryParse(data['pinnedAt'] as String? ?? '');
      final rawGroupId = restoreOrganizer ? data['groupId'] as String? : null;
      final safeGroupId = rawGroupId == null
          ? null
          : groupIdMap[_validatedId(rawGroupId, 'group id')];
      final album = await _albums.insertWithId(
        id: id,
        name: name,
        createdAt: createdAt,
        pinnedAt: pinnedAt,
        coverMediaId: data['coverMediaId'] as String?,
        rating: restoreOrganizer ? (data['rating'] as int? ?? 0) : 0,
        sortIndex: restoreOrganizer ? data['sortIndex'] as int? : null,
        groupId: safeGroupId,
      );
      restoredIds[id] = album.id;
    }
    return Map<String, String>.unmodifiable(restoredIds);
  }

  Future<Map<String, String>> _restoreV3Groups(
    Map<String, dynamic> manifest,
  ) async {
    final groupList = (manifest['albumGroups'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final restoredIds = <String, String>{};
    final existingGroups = {
      for (final group in await _albums.listGroups()) group.id: group,
    };
    for (final data in groupList) {
      final rawId = data['id'] as String?;
      final name = data['name'] as String?;
      if (rawId == null || name == null || name.trim().isEmpty) {
        throw const FormatException('Album group requires id and name');
      }
      final id = _validatedId(rawId, 'group id');
      final existing = existingGroups[id];
      if (existing != null) {
        if (existing.name.toLowerCase() != name.trim().toLowerCase()) {
          throw StateError('Album group id collides with another group: $id');
        }
        restoredIds[id] = existing.id;
        continue;
      }
      final createdAt = DateTime.tryParse(data['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      await _db.insertAlbumGroup(
        AlbumGroupsCompanion.insert(
          id: id,
          name: name.trim(),
          createdAt: createdAt,
          sortIndex: Value(data['sortIndex'] as int?),
        ),
      );
      restoredIds[id] = id;
    }
    return Map<String, String>.unmodifiable(restoredIds);
  }

  Future<void> _restoreMemberships(
    Map<String, dynamic> manifest,
    Map<String, String> albumIdMap,
  ) async {
    final memberships = (manifest['membership'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    for (final data in memberships) {
      final manifestAlbumId = data['albumId'] as String?;
      final mediaId = data['mediaId'] as String?;
      if (manifestAlbumId == null || mediaId == null) {
        throw const FormatException('Membership requires albumId and mediaId');
      }
      final safeAlbumId = _validatedId(manifestAlbumId, 'album id');
      final safeMediaId = _validatedId(mediaId, 'media id');
      final albumId = albumIdMap[safeAlbumId];
      if (albumId == null || await _db.getMediaById(safeMediaId) == null) {
        continue;
      }
      final addedAt = DateTime.tryParse(data['addedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      await _albums.restoreMembership(albumId, safeMediaId, addedAt);
    }
  }

  Future<void> _restoreV1Albums(Map<String, dynamic> manifest) async {
    final albumList = (manifest['albums'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    for (final data in albumList) {
      if (data['isSystem'] as bool? ?? true) continue;
      final name = data['name'] as String?;
      if (name == null || name.trim().isEmpty) continue;
      try {
        await _albums.getOrCreateUserAlbumByName(name);
      } catch (e, stackTrace) {
        debugPrint('album restore: $e\n$stackTrace');
      }
    }
  }

  Future<File?> _backupFile(Directory mediaDirectory, String name) async {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains(r'\')) {
      throw FormatException('Invalid backup file name: $name');
    }
    final file = File(p.join(mediaDirectory.path, name));
    if (!await file.exists()) return null;
    final root = await mediaDirectory.resolveSymbolicLinks();
    final resolved = await file.resolveSymbolicLinks();
    if (!p.isWithin(root, resolved)) {
      throw FormatException('Backup file leaves media directory: $name');
    }
    return file;
  }

  static String _validatedId(String value, String label) {
    final valid = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
    if (!valid.hasMatch(value)) throw FormatException('Invalid $label');
    return value;
  }

  static String? _validatedOriginalPath(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = p.normalize(value.trim());
    final inStorage =
        p.isWithin('/storage', normalized) || p.isWithin('/sdcard', normalized);
    if (!p.isAbsolute(normalized) || !inStorage) {
      throw const FormatException('Invalid original media path');
    }
    return normalized;
  }
}
