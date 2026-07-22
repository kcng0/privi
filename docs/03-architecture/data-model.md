# Data Model

Metadata lives in a local **Drift** (SQLite) database. Media **bytes** live on
disk in the vault directory (see
[storage-and-hiding.md](./storage-and-hiding.md)); the DB stores only the path
and attributes.

## Entities

### `MediaItem`

From the spec, mapped to a Drift table.

| Field | Type | Notes |
|-------|------|-------|
| `id` | `String` (UUID) PK | Generated with `uuid`. |
| `privatePath` | `String` | Absolute path inside `…/vault/`. |
| `originalName` | `String` | Source filename at import. |
| `mimeType` | `String` | e.g. `image/jpeg`, `video/mp4`. |
| `isVideo` | `bool` | Derived from mime; stored for fast filtering. |
| `width` | `int?` | Pixels. |
| `height` | `int?` | Pixels. |
| `durationMs` | `int?` | Videos only. |
| `rating` | `int` | **0–3**, default `0`. Invariant enforced. |
| `dateAdded` | `DateTime` | Capture/create time when known; import time fallback for legacy compatibility. |
| `dateTaken` | `DateTime?` | Original capture/create time from source metadata when available. |
| `sizeBytes` | `int` | File size. |
| `thumbnailPath` | `String?` | Cached thumbnail path. |
| `deletedAt` | `DateTime?` | **Soft delete** marker (null = active). *Added to spec model for Recycle Bin.* |

> The spec's `MediaItem.albumIds: List<String>` is **normalized** into a join
> table (`AlbumMedia`) rather than a serialized list — cleaner queries and
> integrity. See relationships below.

### `Album`

| Field | Type | Notes |
|-------|------|-------|
| `id` | `String` (UUID) PK | |
| `name` | `String` | |
| `isSystem` | `bool` | True for All Media, Favorites, Recycle Bin. |
| `coverMediaId` | `String?` | FK → `MediaItem.id` (nullable). |
| `createdAt` | `DateTime` | |
| `systemKind` | `String?` | Enum-ish tag for system albums: `all` / `favorites` / `recycle`. Null for user albums. *Added for clarity.* |

### `AlbumMedia` (join table)

Explicit membership for **user albums only**.

| Field | Type | Notes |
|-------|------|-------|
| `albumId` | `String` FK | → `Album.id` |
| `mediaId` | `String` FK | → `MediaItem.id` |
| `addedAt` | `DateTime` | |
| PK | (`albumId`, `mediaId`) | composite |

## Virtual (computed) system albums

Not stored as membership — computed by query:

| Album | Query |
|-------|-------|
| **All Media** | `WHERE deletedAt IS NULL` |
| **Favorites** | `WHERE deletedAt IS NULL AND rating >= 1` |
| **Recycle Bin** | `WHERE deletedAt IS NOT NULL` |

This is decision **A6** — computing them avoids membership-sync bugs (e.g. an
item's Favorites membership can never drift out of step with its rating).

## Relationships

```
Album 1───* AlbumMedia *───1 MediaItem     (user-album membership)
Album *───0..1 MediaItem                   (coverMediaId)
Favorites / All / Recycle  ── computed ──> MediaItem (no rows)
```

## Backup representation

A current export is a self-contained directory with `privi_manifest.json` and
one required payload under `media/` for every active or recycled `MediaItem`.
Optional thumbnails remain rebuildable cache and do not affect media success
counts.

Manifest v5 records:

- `itemCount`, `totalBytes`, export/verification timestamps, and a platform
  source descriptor;
- each media ID, payload filename, byte length, SHA-256, metadata, and optional
  thumbnail name;
- albums, album groups, covers, and user-album membership as explicit IDs.

The exporter reads media and organization rows in one Drift transaction, then
preflights every source. Payloads are copied and hashed as streams in a staging
directory. The manifest is committed last and re-read together with every
payload before the operation can report `verified`.

Restore treats the manifest as untrusted input. It validates path containment,
field types, IDs, summary totals, unique filenames, cover/group/membership
references, payload lengths, and SHA-256 before creating albums, copying media,
or inserting DB rows. An existing media ID is reusable only when its vault file
has the declared length and digest; otherwise restore reports a destination
conflict.

Versions v1–v4 remain importable. Their missing checksum fields cannot be
reconstructed as historical proof, so restore still checks safe paths,
existence, non-empty bytes, and copy stability but reports that checksums were
not verified. Unknown newer manifest versions are rejected.

`verified` is an integrity statement for one point in time, not encryption,
authentication against a malicious editor, or continuous backup monitoring.

## Invariants

- `0 <= rating <= 3` — enforced at repository boundary and (optionally) a DB
  `CHECK` constraint.
- `isVideo == mimeType.startsWith('video/')`.
- An item in Recycle Bin (`deletedAt != null`) is excluded from All Media,
  Favorites, and user-album *display* (but its `AlbumMedia` rows may remain until
  purge).
- Deleting an album (user) removes its `AlbumMedia` rows, **not** the media.
- Purging a media item removes: the file, its thumbnail, its row, and its
  `AlbumMedia` rows; nulls any album `coverMediaId` pointing to it.

## Reactivity

Drift `.watch()` streams back grids and counts. Rating writes and imports emit
new stream values → UI updates without manual refresh (see
[state-management.md](./state-management.md)).

## Media chronology

Date ordering is stable across the Visible → Hide → Invisible transition:

- Visible MediaStore pages are queried by `createDate` rather than modified
  time, then use the source filename as a deterministic tie-breaker.
- Vault queries order by `COALESCE(dateTaken, dateAdded) DESC,
  originalName ASC`; album covers use the same expression.
- Client-side date sorts use the same `dateTaken ?? dateAdded` rule.
- `idx_media_items_original_date` covers the active-item chronology query.

Hide time and file modified time must not reshuffle media. When source capture
metadata cannot be resolved, the stored `dateAdded` fallback remains explicit.

## Preferences (not in the media DB)

Non-media settings (grid columns, slideshow delay, player preference, shuffle
default, auto-lock timeout) are simple key-values (`shared_preferences`).
Security values (PIN hash, biometric flag) are in `flutter_secure_storage`
(see [security.md](./security.md)). Keeping these out of the relational DB keeps
the schema focused on media.

## Migrations

Drift schema versioning from v1. Adding columns/tables later uses Drift's
migration steps. Keep v1 minimal.
