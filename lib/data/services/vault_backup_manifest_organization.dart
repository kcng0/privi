part of 'vault_backup_service.dart';

final class _VaultBackupOrganizationParser {
  const _VaultBackupOrganizationParser();

  _ManifestAlbum parseAlbum(Map<String, dynamic> raw, int version) {
    final strict = version >= VaultBackupService.manifestVersion;
    final parsedIsSystem =
        _optionalManifestBool(raw['isSystem'], 'album isSystem');
    final isSystem = strict
        ? parsedIsSystem ?? _throwMalformedManifest('album isSystem')
        : parsedIsSystem ?? true;
    final id = strict
        ? _validatedBackupId(
            _requiredManifestString(raw['id'], 'album id'),
            'album id',
          )
        : switch (_optionalManifestString(raw['id'], 'album id')) {
            final value? => _validatedBackupId(value, 'album id'),
            null => null,
          };
    final name = strict
        ? _requiredManifestString(raw['name'], 'album name')
        : _optionalManifestString(raw['name'], 'album name');
    final coverMediaId =
        _optionalManifestString(raw['coverMediaId'], 'album coverMediaId');
    final groupId = _optionalManifestString(raw['groupId'], 'album groupId');
    final rating = _optionalManifestInt(raw['rating'], 'album rating');
    if (rating != null && (rating < 0 || rating > 3)) {
      _throwMalformedManifest('album rating');
    }
    if (strict && rating == null) _throwMalformedManifest('album rating');
    return _ManifestAlbum(
      id: id,
      name: name,
      isSystem: isSystem,
      coverMediaId: coverMediaId == null
          ? null
          : _validatedBackupId(coverMediaId, 'cover media id'),
      createdAt: _manifestDate(
        raw['createdAt'],
        'album createdAt',
        strict: strict,
        required: strict,
      ),
      systemKind: _optionalManifestString(raw['systemKind'], 'systemKind'),
      pinnedAt: _manifestDate(
        raw['pinnedAt'],
        'album pinnedAt',
        strict: strict,
        required: false,
      ),
      rating: rating,
      sortIndex: _optionalManifestInt(raw['sortIndex'], 'album sortIndex'),
      groupId: groupId == null ? null : _validatedBackupId(groupId, 'group id'),
    );
  }

  _ManifestGroup parseGroup(Map<String, dynamic> raw, int version) {
    final strict = version >= VaultBackupService.manifestVersion;
    final id = strict
        ? _validatedBackupId(
            _requiredManifestString(raw['id'], 'group id'),
            'group id',
          )
        : switch (_optionalManifestString(raw['id'], 'group id')) {
            final value? => _validatedBackupId(value, 'group id'),
            null => null,
          };
    return _ManifestGroup(
      id: id,
      name: strict
          ? _requiredManifestString(raw['name'], 'group name')
          : _optionalManifestString(raw['name'], 'group name'),
      createdAt: _manifestDate(
        raw['createdAt'],
        'group createdAt',
        strict: strict,
        required: strict,
      ),
      sortIndex: _optionalManifestInt(raw['sortIndex'], 'group sortIndex'),
    );
  }

  _ManifestMembership parseMembership(
    Map<String, dynamic> raw,
    int version,
  ) {
    final strict = version >= VaultBackupService.manifestVersion;
    final rawAlbumId = strict
        ? _requiredManifestString(raw['albumId'], 'album id')
        : _optionalManifestString(raw['albumId'], 'album id');
    final rawMediaId = strict
        ? _requiredManifestString(raw['mediaId'], 'media id')
        : _optionalManifestString(raw['mediaId'], 'media id');
    return _ManifestMembership(
      albumId: rawAlbumId == null
          ? null
          : _validatedBackupId(rawAlbumId, 'album id'),
      mediaId: rawMediaId == null
          ? null
          : _validatedBackupId(rawMediaId, 'media id'),
      addedAt: _manifestDate(
        raw['addedAt'],
        'membership addedAt',
        strict: strict,
        required: strict,
      ),
    );
  }
}
