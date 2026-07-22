import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

part 'vault_backup_export.dart';
part 'vault_backup_manifest.dart';
part 'vault_backup_manifest_organization.dart';
part 'vault_backup_manifest_parser.dart';
part 'vault_backup_manifest_validation.dart';
part 'vault_backup_models.dart';
part 'vault_backup_restore.dart';
part 'vault_backup_restore_install.dart';
part 'vault_backup_restore_preflight.dart';
part 'vault_backup_support.dart';

/// Local export/import durability (D3) - no cloud.
class VaultBackupService implements VaultBackupOperations {
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

  static const manifestName = 'privi_manifest.json';
  static const manifestVersion = 5;

  final AppDatabase _db;
  final MediaRepository _media;
  final AlbumRepository _albums;
  final VaultStorageService _storage;
  final Uuid _uuid;
  final bool _usePrivateMediaStorage;

  String get _platformName => _usePrivateMediaStorage ? 'ios' : 'android';

  @override
  Future<VaultBackupResult> exportToDirectory(
    String destinationDirectory, {
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  }) {
    return _VaultBackupExporter(
      db: _db,
      uuid: _uuid,
      platformName: _platformName,
    ).run(
      destinationDirectory,
      session: session,
      onProgress: onProgress,
    );
  }

  @override
  Future<VaultBackupResult> importFromDirectory(
    String sourceDirectory, {
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  }) {
    return _VaultBackupRestorer(
      db: _db,
      media: _media,
      albums: _albums,
      storage: _storage,
      uuid: _uuid,
      platformName: _platformName,
      usePrivateMediaStorage: _usePrivateMediaStorage,
    ).run(
      sourceDirectory,
      session: session,
      onProgress: onProgress,
    );
  }
}
