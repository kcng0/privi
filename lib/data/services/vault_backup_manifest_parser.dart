part of 'vault_backup_service.dart';

final class _VaultBackupManifestParser {
  const _VaultBackupManifestParser();

  static const _organization = _VaultBackupOrganizationParser();

  _BackupManifest parse(Map<String, dynamic> raw) {
    final version =
        raw['version'] == null ? 1 : _manifestInt(raw['version'], 'version');
    if (version < 1 || version > VaultBackupService.manifestVersion) {
      throw const VaultBackupException(
        VaultBackupErrorCode.unsupportedManifestVersion,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    final strict = version >= VaultBackupService.manifestVersion;
    return _BackupManifest(
      version: version,
      exportedAt: _manifestDate(
        raw['exportedAt'],
        'exportedAt',
        strict: strict,
        required: strict,
      ),
      verifiedAt: _manifestDate(
        raw['verifiedAt'],
        'verifiedAt',
        strict: strict,
        required: strict,
      ),
      declaredItemCount: strict
          ? _manifestInt(raw['itemCount'], 'itemCount')
          : _optionalManifestInt(raw['itemCount'], 'itemCount'),
      declaredTotalBytes: strict
          ? _manifestInt(raw['totalBytes'], 'totalBytes')
          : _optionalManifestInt(raw['totalBytes'], 'totalBytes'),
      media: List.unmodifiable(
        _manifestObjects(raw['media'], 'media', required: strict).map(
          (entry) => _parseMedia(entry, version),
        ),
      ),
      albums: List.unmodifiable(
        _manifestObjects(raw['albums'], 'albums', required: strict).map(
          (entry) => _organization.parseAlbum(entry, version),
        ),
      ),
      groups: List.unmodifiable(
        _manifestObjects(
          raw['albumGroups'],
          'albumGroups',
          required: strict,
        ).map(
          (entry) => _organization.parseGroup(entry, version),
        ),
      ),
      memberships: List.unmodifiable(
        _manifestObjects(
          raw['membership'],
          'membership',
          required: strict,
        ).map(
          (entry) => _organization.parseMembership(entry, version),
        ),
      ),
    );
  }

  _ManifestMedia _parseMedia(Map<String, dynamic> raw, int version) {
    final strict = version >= VaultBackupService.manifestVersion;
    final fileName = _requiredManifestString(raw['file'], 'file');
    _validateBackupName(fileName);
    final id = strict
        ? _validatedBackupId(
            _requiredManifestString(raw['id'], 'media id'),
            'media id',
          )
        : switch (_optionalManifestString(raw['id'], 'media id')) {
            final value? => _validatedBackupId(value, 'media id'),
            null => null,
          };
    final thumbnailName = _optionalManifestString(raw['thumb'], 'thumb');
    if (thumbnailName != null) _validateBackupName(thumbnailName);
    final byteLength = strict
        ? _manifestInt(raw['byteLength'], 'byteLength')
        : _optionalManifestInt(raw['byteLength'], 'byteLength');
    if (byteLength != null && byteLength <= 0) {
      throw VaultBackupException(
        VaultBackupErrorCode.payloadEmpty,
        fileName: fileName,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    final sha256 = strict
        ? _requiredManifestString(raw['sha256'], 'sha256')
        : _optionalManifestString(raw['sha256'], 'sha256');
    if (sha256 != null && !_isSha256Digest(sha256)) {
      throw VaultBackupException(
        VaultBackupErrorCode.payloadDigestMismatch,
        fileName: fileName,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    final originalName = strict
        ? _requiredManifestString(raw['originalName'], 'originalName')
        : _optionalManifestString(raw['originalName'], 'originalName');
    final mimeType = strict
        ? _requiredManifestString(raw['mimeType'], 'mimeType')
        : _optionalManifestString(raw['mimeType'], 'mimeType');
    final isVideo = strict
        ? _optionalManifestBool(raw['isVideo'], 'isVideo') ??
            (throw const VaultBackupException(
              VaultBackupErrorCode.malformedManifest,
              fileName: 'isVideo',
              stage: VaultBackupStage.checkingBackup,
            ))
        : _optionalManifestBool(raw['isVideo'], 'isVideo');
    final rating = strict
        ? _optionalManifestInt(raw['rating'], 'rating') ??
            (throw const VaultBackupException(
              VaultBackupErrorCode.malformedManifest,
              fileName: 'rating',
              stage: VaultBackupStage.checkingBackup,
            ))
        : _optionalManifestInt(raw['rating'], 'rating');
    if (rating != null && (rating < 0 || rating > 3)) {
      throw const VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: 'rating',
        stage: VaultBackupStage.checkingBackup,
      );
    }
    final sizeBytes = strict
        ? _manifestInt(raw['sizeBytes'], 'sizeBytes')
        : _optionalManifestInt(raw['sizeBytes'], 'sizeBytes');
    if (sizeBytes != null && sizeBytes < 0) {
      throw const VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: 'sizeBytes',
        stage: VaultBackupStage.checkingBackup,
      );
    }
    if (strict && sizeBytes != byteLength) {
      _throwMalformedManifest('sizeBytes');
    }
    final contentDigest =
        _optionalManifestString(raw['contentDigest'], 'contentDigest');
    if (strict && contentDigest != null && !_isSha256Digest(contentDigest)) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: originalName,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    if (strict && contentDigest != null && contentDigest != sha256) {
      _throwMalformedManifest(originalName ?? fileName);
    }
    final sourceRemovalPending = _optionalManifestBool(
      raw['sourceRemovalPending'],
      'sourceRemovalPending',
    );
    if (strict && sourceRemovalPending == null) {
      _throwMalformedManifest('sourceRemovalPending');
    }
    return _ManifestMedia(
      id: id,
      fileName: fileName,
      thumbnailName: thumbnailName,
      sha256: sha256,
      byteLength: byteLength,
      originalPath: _optionalManifestString(
        raw['originalPath'],
        'originalPath',
      ),
      source: version >= 4 ? _parseSource(raw['source']) : null,
      sourceRemovalPending:
          version >= 4 ? sourceRemovalPending ?? false : false,
      contentDigest: version >= 4 ? contentDigest : null,
      originalName: originalName,
      mimeType: mimeType,
      isVideo: isVideo,
      width: _nonNegativeInt(raw['width'], 'width'),
      height: _nonNegativeInt(raw['height'], 'height'),
      durationMs: _nonNegativeInt(raw['durationMs'], 'durationMs'),
      rating: rating,
      dateAdded: _manifestDate(
        raw['dateAdded'],
        'dateAdded',
        strict: strict,
        required: strict,
      ),
      dateTaken: _manifestDate(
        raw['dateTaken'],
        'dateTaken',
        strict: strict,
        required: false,
      ),
      sizeBytes: sizeBytes,
      deletedAt: _manifestDate(
        raw['deletedAt'],
        'deletedAt',
        strict: strict,
        required: false,
      ),
    );
  }

  _ManifestSource? _parseSource(Object? value) {
    if (value == null) return null;
    if (value is! Map) {
      throw const VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: 'source',
        stage: VaultBackupStage.checkingBackup,
      );
    }
    return _ManifestSource(
      platform: _requiredManifestString(value['platform'], 'source.platform'),
      libraryId:
          _requiredManifestString(value['libraryId'], 'source.libraryId'),
    );
  }

  int? _nonNegativeInt(Object? value, String label) {
    final parsed = _optionalManifestInt(value, label);
    if (parsed != null && parsed < 0) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: label,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    return parsed;
  }

  List<Map<String, dynamic>> _manifestObjects(
    Object? value,
    String label, {
    required bool required,
  }) {
    if (value == null) {
      if (required) _throwMalformedManifest(label);
      return const [];
    }
    if (value is! List) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: label,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    try {
      return value.map((entry) {
        if (entry is! Map) {
          throw VaultBackupException(
            VaultBackupErrorCode.malformedManifest,
            fileName: label,
            stage: VaultBackupStage.checkingBackup,
          );
        }
        return Map<String, dynamic>.from(entry);
      }).toList(growable: false);
    } on VaultBackupException {
      rethrow;
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: label,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
  }
}
