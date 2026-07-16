// Domain enums. See docs/03-architecture/data-model.md and security.md.

/// Tags for the three always-present system albums.
enum SystemAlbumKind {
  all('all'),
  favorites('favorites'),
  recycle('recycle');

  const SystemAlbumKind(this.storageValue);
  final String storageValue;

  static SystemAlbumKind? fromStorage(String? value) {
    if (value == null) return null;
    for (final k in SystemAlbumKind.values) {
      if (k.storageValue == value) return k;
    }
    return null;
  }
}

/// App lock gate state.
enum LockStatus {
  /// Pattern (or legacy PIN) not yet configured — show setup flow.
  needsSetup,

  /// Vault is locked; require pattern (or biometric if enabled).
  locked,

  /// Vault is unlocked for this session.
  unlocked,
}

/// Filter for Visible gallery (photo XOR video).
enum MediaKindFilter {
  image,
  video,
}

/// Sort criteria for Invisible media grids (multi-select, ordered).
enum MediaSort {
  dateAddedDesc,
  dateAddedAsc,
  nameAsc,
  nameDesc,
  ratingDesc,
  ratingAsc,
}

/// Rating filter for Invisible grids (`null` / all = no filter).
enum RatingFilter {
  all,
  unrated,
  hearts1,
  hearts2,
  hearts3,
  favorites,
}
