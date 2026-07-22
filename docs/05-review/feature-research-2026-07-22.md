# Mobile Feature Research: High-Value Next Steps

**Date:** 2026-07-22
**Scope:** Privi/PSmith local privacy media vault; mobile-first UX
**Sources:** first-party product/platform documentation only
**Access date for every web source below:** 2026-07-22

## Executive recommendation

Prioritize **verified local backup and restore preflight**. Local export/import
is Privi's only durability path when the app is reinstalled, but the current
export can silently omit a missing source file and the current restore trusts a
stored digest without checking the restored bytes. A successful message can
therefore provide confidence that the implementation has not proved.

The smallest high-value release is a checksum manifest, post-export
verification, and a read-only restore preflight with an explicit mobile status:
item count, byte count, last verified time, and any missing/corrupt item. This
is more important than duplicate cleanup or timeline browsing because those
features improve an intact library; verified backup protects the only copy and
creates a reusable digest service for duplicate management next.

## What the current repository already has

The gap is concrete, not speculative:

- D3 defines manual local export/import as the mitigation for reinstall and
  device migration: [`docs/decisions-log.md`](../decisions-log.md#L45).
- Export skips a missing source with `continue`, copies other files, and can
  still return a success count: [`lib/data/services/vault_backup_service.dart`](../../lib/data/services/vault_backup_service.dart#L61).
- Manifest v4 serializes the row's existing `contentDigest`, which may be null;
  export does not compute or verify the copied file's digest:
  [`lib/data/services/vault_backup_service.dart`](../../lib/data/services/vault_backup_service.dart#L80).
- Restore only checks that the copied destination is non-empty, then stores the
  manifest digest without comparing it to the bytes:
  [`lib/data/services/vault_backup_service.dart`](../../lib/data/services/vault_backup_service.dart#L186).
- The round-trip test deliberately stores the literal value `sha256-digest` for
  different test bytes and only checks that the string survives. It proves
  metadata round-trip, not backup integrity:
  [`test/data/vault_backup_service_test.dart`](../../test/data/vault_backup_service_test.dart#L85).
- The import design explicitly allows duplicate imports as distinct items and
  calls hash deduplication optional: [`docs/02-design/screens/06-import.md`](../02-design/screens/06-import.md#L46).
- The decision log repeats that default: [`docs/decisions-log.md`](../decisions-log.md#L304).
- `MediaItems.contentDigest` is documented as the SHA-256 of verified private
  bytes: [`lib/data/db/tables.dart`](../../lib/data/db/tables.dart#L31).
- `MediaRepository.findByContentDigest` already exists:
  [`lib/data/repositories/media_repository.dart`](../../lib/data/repositories/media_repository.dart#L174).
- The Android hide recorder currently creates a `MediaItem` without setting a
  digest, so new Android rows cannot yet participate in a complete digest
  review: [`lib/data/services/import/media_recorder.dart`](../../lib/data/services/import/media_recorder.dart#L24).
- Current grid filtering searches only `originalName` and `privatePath`; it has
  no date/content search or duplicate grouping:
  [`lib/core/utils/media_query_utils.dart`](../../lib/core/utils/media_query_utils.dart#L8).
- System albums currently include All Media, Favorites, and Recycle Bin only;
  there is no Duplicates utility album:
  [`lib/domain/models/album.dart`](../../lib/domain/models/album.dart#L34).

These observations are repository evidence. The severity ranking is a product
inference from D3 making export/import the only reinstall mitigation; no backup
failure telemetry or user telemetry was available.

## Candidate features

### 1. Verified local backup and restore preflight (recommended, P0)

**User outcome:** after export, the app reports `Verified N/N` with total bytes
and time. Before restore changes the vault, it reports whether every declared
media file is present and matches its size and SHA-256 checksum. Corrupt or
incomplete backups fail explicitly and identify the affected items.

**Smallest shippable slice:**

1. Inject one streaming `ContentDigestService` and reuse the repository's
   existing `crypto` dependency and `File.openRead()` pattern. Do not load full
   videos into memory.
2. Export every payload entry with byte length and a SHA-256 calculated from the
   exported copy. Treat a missing/unreadable source, changed byte count, or hash
   mismatch as an export failure; never silently omit it.
3. Write the final manifest only after all payload files pass verification.
   Record expected item count and bytes, then re-read and verify the finished
   export before showing success.
4. Add a read-only restore preflight that validates schema/path safety,
   completeness, sizes, and hashes before creating albums, copying media, or
   inserting rows. On any error, leave the current vault unchanged.
5. Show progress and cancellation for export, verify, and preflight. Keep a
   persistent result in the chosen backup folder; a transient snackbar is not
   sufficient proof of backup health.

**Why this UX is evidence-based:**

- Google Photos exposes both overall backup status and per-item backup status,
  and explicitly tells users how to check whether backup is complete. The
  product precedent is visible, inspectable state rather than assuming a
  background copy succeeded.
- Ente's storage optimization flow only removes device copies that have been
  successfully backed up and asks the user to review how much space will be
  freed. Its duplicate cleanup is downstream of that backup assurance.
- RFC 8493 (BagIt), a first-party preservation/transfer format specification,
  defines a complete package as one where every manifest file is present and a
  valid package as complete with every manifest checksum successfully verified.
  Privi need not adopt the full BagIt layout, but a payload manifest plus full
  checksum verification is an established solution to the same integrity
  problem.

**Truthful boundary:** “verified” means complete and checksum-correct at a
specific time. It does not mean encrypted, authenticated against a malicious
editor, or continuously healthy. Keep those claims separate in UI and docs.

### 2. Exact duplicate review (P1, next after backup verification)

**User outcome:** find byte-identical photos/videos, compare their album and
rating metadata, choose the canonical item, and move redundant records to the
existing Recycle Bin with an Undo action. Show the recoverable byte total; do
not claim storage is reclaimed until purge.

**Smallest shippable slice:**

1. Compute a streaming SHA-256 for vault files whose digest is missing. Run it
   as cancellable/background work and expose progress; never block first unlock
   or first grid paint.
2. Group active rows by non-null digest (size is a cheap pre-filter, not an
   identity rule).
3. Present one mobile review screen with one group per digest, large enough
   thumbnails to verify the match, file size/date/name, and album membership.
4. Require an explicit keep/delete decision. Union album memberships and keep
   the strongest user metadata before moving redundant rows to Recycle Bin.
5. Add an import preflight only after the review flow is stable. If an incoming
   source matches, report “already in vault” and let the user choose **keep
   both**, **keep existing**, or **cancel**. Do not remove the still-visible
   source implicitly.

**Why this UX is evidence-based:**

- Apple Photos identifies duplicates, puts them in a Duplicates collection, and
  asks the user to tap Merge; Apple describes the goal as saving space and
  cleaning the library. The collection is absent when no duplicates are found.
- Apple defers indexing until the iPhone is locked and connected to power and
  says a large library can take up to days. This supports a resumable/background
  scan with visible state rather than work hidden in the import critical path.
- Google Photos groups similar photos into stacks, chooses a “top pick,” lets the
  user inspect the stack, and provides “Keep this, delete rest.” Stack actions
  distinguish selected items from all stack items. This is a useful interaction
  precedent, but Google’s help also says stacks are for backed-up photos, so it
  is not evidence that Privi should require cloud backup.
- Ente, a privacy-focused photo product, separates exact duplicate detection
  (“same file hash”) from ML-powered similar-image review. Its mobile flow is
  explicitly “review … and confirm,” and for similar images it asks the user to
  choose what to keep and delete.

**Safety boundary:** exact equality is the only automatic match in this slice.
Perceptual similarity can be a later opt-in feature with a separate label and
separate confirmation; it must never share the exact-duplicate path.

The backup work should provide the shared streaming digest service; duplicate
review then becomes a small application/query/UI feature rather than a second
hashing implementation.

### 3. Date-first timeline and Jump to Date (P1)

**User outcome:** retrieve a private photo by when it was taken, not by a file
name the user may not remember. Add day/month section headers and a compact
date jump affordance to the existing grid. Keep the current sort/filter state
and support the existing Visible/Invisible scopes independently.

**Why it is a good low-risk follow-up:** `dateTaken` is already persisted, and the
current query layer already uses capture chronology for sorting. A timeline can
therefore be implemented without media analysis, new permissions, network, or
an encryption decision. It improves a common mobile browse path for a library
of a few thousand items while preserving the app’s simple album model.

**Official evidence:**

- Apple Photos lets users browse by a recent day, swipe to adjacent days, and
  browse by Years or Months; Months are organized around significant events.
- Google Photos’ official search supports combinations of people/pets,
  locations, things, and dates, and exposes collections such as Albums,
  Documents, Screenshots, Videos, and Favorites. Date navigation is therefore a
  baseline retrieval dimension even when content AI is unavailable.
- Ente’s search documentation offers date search by specific date, month, or
  year alongside filename search and a mobile “Jump to Date” utility.

**Suggested acceptance:** a user can jump to a month/day, see stable chronology
after hide/unhide, and return to the prior grid position without losing the
folder’s sort/filter preferences. Search remains ephemeral as required by the
existing folder-view invariant.

## Mobile interaction rule for all three candidates

Use an actionable Material snackbar for reversible, low-interruption outcomes.
Material 3 says a snackbar can contain one action, and specifically recommends
an “Undo” action to let people amend a choice; action snackbars remain until
acted on or dismissed. This fits duplicate cleanup and future hide/unhide/move
operations. The current app already reports these operations with snackbars,
but the grid actions do not currently provide an Undo action (for example,
`media_grid_screen.dart` reports restore and Recycle Bin moves without one).

Do not use a snackbar as the only access path to a core result. Keep the
Duplicates utility and Recycle Bin discoverable, and make the review decision
explicit before any source file is externalized or permanently deleted.

## Prioritization matrix

| Candidate | User value | Privacy fit | Delivery risk | Recommendation |
|---|---:|---:|---:|---|
| Verified local backup + restore preflight | Critical | High | Medium | **Do first** |
| Exact duplicate review + explicit import preflight | High | High | Low–medium after shared digest service | Do second |
| Date timeline + Jump to Date | High | High | Low | Do third |

## Primary sources and traceable claims

All links below were accessed on **2026-07-22**. The claim text is a summary of
the linked first-party page, not a third-party review.

| Source (title) | URL | Relevant fact |
|---|---|---|
| Google Photos Help — *Back up photos & videos (Android)* | <https://support.google.com/photos/answer/6193313?hl=en&co=GENIE.Platform%3DAndroid> | Google Photos exposes overall and per-item backup status and a specific “Check if backup is complete” flow; it notes completion can take time. |
| Ente Help — *Storage optimization* | <https://ente.io/help/photos/features/albums-and-organization/storage-optimization> | Device-space cleanup removes only successfully backed-up photos; exact duplicate removal is a review/confirm flow and exactness means the same file hash. |
| RFC Editor — *RFC 8493: The BagIt File Packaging Format (V1.0)* | <https://www.rfc-editor.org/rfc/rfc8493.html> | A complete bag has every manifest-listed payload file; a valid bag is complete and has every manifest checksum verified against the corresponding file. The RFC says the format is suitable for reliable storage and transfer. |
| Apple Support — *Merge duplicate photos and videos on iPhone* | <https://support.apple.com/guide/iphone/merge-duplicate-photos-and-videos-iph1978d9c23/18.0/ios/18.0> | Photos identifies duplicates in a Duplicates collection; the user taps Merge to combine a set; the page frames this as saving space and cleaning the library. |
| Apple Support — *If you can’t find the Duplicates album for duplicate photos and videos on iPhone* | <https://support.apple.com/en-us/102260> | Starting in iOS 16, Photos detects duplicates; indexing requires the phone to be locked and on power and can take up to days; the Duplicates album appears under Utilities when matches exist. |
| Google Photos Help — *Organize your Photos view and stack similar photos (Android)* | <https://support.google.com/photos/answer/14169846?hl=en&co=GENIE.Platform%3DAndroid> | Similar photos can be automatically stacked; a top pick is shown; the user can inspect a stack, select items, and use “Keep this, delete rest”; actions can target selected items or the full stack. |
| Apple Support — *Find photos and videos by date on iPhone* | <https://support.apple.com/guide/iphone/find-photos-and-videos-by-date-iph0ea0234e0/18.0/ios/18.0> | Recent Days supports day browsing and adjacent-day swipes; Years and Months provide date-based library navigation, with an All view for every item. |
| Google Photos Help — *Search by people, things & places in your photos (Android)* | <https://support.google.com/photos/answer/15235862?hl=en&co=GENIE.Platform%3DAndroid> | Search supports combinations of people/pets, locations, things, and dates, and exposes collections such as Albums, Documents, Places, Screenshots, Videos, Favorites, and Trash. |
| Ente Help — *Search and Discovery* | <https://ente.io/help/photos/features/search-and-discovery> | Basic search includes specific dates/months/years and original filenames; the product also documents on-device ML search and a Jump to Date utility. |
| Material Design 3 — *Snackbar* | <https://m3.material.io/components/snackbar/guidelines> | Snackbars may contain one action; Material explicitly gives “Undo” as the action for amending choices and says action snackbars remain until acted on or dismissed. |

## Decision and next review gate

Treat verified local backup as the next feature candidate for implementation
planning. Its delivery gate should include: missing source during export,
source mutation during export, corrupt payload, missing payload, wrong length,
wrong digest, malformed/unsupported manifest, path traversal, cancellation,
insufficient storage, and proof that restore preflight failure makes no DB or
vault mutation. Verify a real export on Android and iOS, corrupt one byte, and
confirm that both explicit Verify and restore preflight name the failed item.

After that shared digest path is stable, implement exact duplicate review. Test
same bytes with different names/albums, missing digest, Recycle Bin rows,
unreadable files, cancellation, and the “source remains visible” branch when a
user declines import deduplication. Re-evaluate perceptual similarity only after
exact matching is reliable.
