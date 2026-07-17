package com.privi.app

import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import java.io.File

/**
 * Owns MediaStore lookups, index visibility, scans, and path reconciliation.
 */
class MediaStoreIndexHandler(
    private val context: Context,
    private val resolver: ContentResolver,
) {
    fun contentUriForMediaId(id: Long, isVideo: Boolean): Uri {
        val collection = if (isVideo) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            } else {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            }
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
        }
        return ContentUris.withAppendedId(collection, id)
    }

    fun purgeMediaStoreByPath(path: String): Int {
        return hideInMediaStore(path, isVideo = false) + hideInMediaStore(path, isVideo = true)
    }

    fun hideInMediaStore(path: String, isVideo: Boolean): Int {
        if (path.isBlank()) return 0
        var updated = 0
        // Only mark pending when the file is still at [path]. Never delete by URI
        // while a rename target may still share the row.
        val stillThere = File(path).exists()
        val values = ContentValues().apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }
        if (values.size() == 0) return 0
        val selection = MediaStore.MediaColumns.DATA + "=?"
        for (p in pathVariants(path)) {
            for (collection in mediaCollections(isVideo)) {
                try {
                    updated += resolver.update(collection, values, selection, arrayOf(p))
                } catch (e: Exception) {
                    android.util.Log.w("PrivateHeart", "hideInMediaStore: $e")
                }
            }
        }
        if (!stillThere) {
            // Original path gone after move into .nomedia vault — delete stale index rows.
            // ContentResolver.delete by DATA when file is missing only drops the index.
            for (p in pathVariants(path)) {
                for (collection in mediaCollections(isVideo)) {
                    try {
                        updated += resolver.delete(collection, selection, arrayOf(p))
                    } catch (e: Exception) {
                        android.util.Log.w("PrivateHeart", "delete index: $e")
                    }
                }
            }
        }
        return updated
    }

    fun mediaCollections(preferVideo: Boolean): List<Uri> {
        val list = mutableListOf<Uri>()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (preferVideo) {
                    list.add(MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL))
                    list.add(MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL))
                } else {
                    list.add(MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL))
                    list.add(MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL))
                }
                list.add(MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL))
            } else {
                list.add(if (preferVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
                list.add(if (preferVideo) MediaStore.Images.Media.EXTERNAL_CONTENT_URI else MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
                list.add(MediaStore.Files.getContentUri("external"))
            }
        } catch (_: Exception) {
            list.add(MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
            list.add(MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
        }
        return list
    }

    fun pathVariants(path: String): List<String> {
        val variants = linkedSetOf(path)
        if (path.startsWith("/storage/emulated/0/")) {
            variants.add(path.replaceFirst("/storage/emulated/0/", "/sdcard/"))
        }
        if (path.startsWith("/sdcard/")) {
            variants.add(path.replaceFirst("/sdcard/", "/storage/emulated/0/"))
        }
        return variants.toList()
    }

    /**
     * Re-index a visible file into MediaStore (unhide).
     * Clears IS_PENDING and restores a real mime type so pickers show it.
     *
     * When [dateTakenSec] / [dateAddedSec] are provided (Unix seconds), they are
     * written so Gallery "Newest first" keeps the original capture order instead
     * of the unhide/scan time.
     */
    fun scanMediaPath(
        path: String,
        mimeType: String?,
        dateTakenSec: Long? = null,
        dateAddedSec: Long? = null,
    ): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val mime = when {
                !mimeType.isNullOrBlank() -> mimeType
                path.endsWith(".mp4", true) -> "video/mp4"
                path.endsWith(".jpg", true) || path.endsWith(".jpeg", true) -> "image/jpeg"
                path.endsWith(".png", true) -> "image/png"
                path.endsWith(".webp", true) -> "image/webp"
                path.endsWith(".gif", true) -> "image/gif"
                path.endsWith(".mkv", true) -> "video/x-matroska"
                path.endsWith(".webm", true) -> "video/webm"
                else -> null
            }
            val isVideo = mime?.startsWith("video/") == true

            // If a pending/hidden row exists for this path, revive it.
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
                @Suppress("DEPRECATION")
                put(MediaStore.MediaColumns.DATA, file.absolutePath)
                if (mime != null) put(MediaStore.MediaColumns.MIME_TYPE, mime)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                // Original capture/create — not scan time.
                if (dateTakenSec != null && dateTakenSec > 0L) {
                    put(MediaStore.MediaColumns.DATE_TAKEN, dateTakenSec * 1000L)
                    // DATE_ADDED is seconds since epoch on MediaStore.
                    put(MediaStore.MediaColumns.DATE_ADDED, dateTakenSec)
                }
                if (dateAddedSec != null && dateAddedSec > 0L) {
                    put(MediaStore.MediaColumns.DATE_ADDED, dateAddedSec)
                }
            }
            val selection = MediaStore.MediaColumns.DATA + "=?"
            var revived = 0
            for (p in pathVariants(path)) {
                for (collection in mediaCollections(isVideo)) {
                    try {
                        revived += resolver.update(collection, values, selection, arrayOf(p))
                    } catch (_: Exception) {
                    }
                }
            }
            // Always scan so missing rows are recreated.
            MediaScannerConnection.scanFile(
                context,
                arrayOf(path),
                if (mime == null) null else arrayOf(mime),
            ) { scannedPath, uri ->
                // After scan, force DATE_TAKEN / DATE_ADDED again — scanners often
                // stamp "now" which reshuffles Gallery order after unhide.
                if (uri != null && dateTakenSec != null && dateTakenSec > 0L) {
                    try {
                        val fix = ContentValues().apply {
                            put(MediaStore.MediaColumns.DATE_TAKEN, dateTakenSec * 1000L)
                            put(
                                MediaStore.MediaColumns.DATE_ADDED,
                                dateAddedSec ?: dateTakenSec,
                            )
                        }
                        resolver.update(uri, fix, null, null)
                    } catch (e: Exception) {
                        android.util.Log.w("PrivateHeart", "scan date fix: $e")
                    }
                } else if (scannedPath != null && dateTakenSec != null && dateTakenSec > 0L) {
                    try {
                        val fix = ContentValues().apply {
                            put(MediaStore.MediaColumns.DATE_TAKEN, dateTakenSec * 1000L)
                            put(
                                MediaStore.MediaColumns.DATE_ADDED,
                                dateAddedSec ?: dateTakenSec,
                            )
                            @Suppress("DEPRECATION")
                            put(MediaStore.MediaColumns.DATA, scannedPath)
                        }
                        val sel = MediaStore.MediaColumns.DATA + "=?"
                        for (collection in mediaCollections(isVideo)) {
                            try {
                                resolver.update(collection, fix, sel, arrayOf(scannedPath))
                            } catch (_: Exception) {
                            }
                        }
                    } catch (e: Exception) {
                        android.util.Log.w("PrivateHeart", "scan path date fix: $e")
                    }
                }
            }
            true
        } catch (e: Exception) {
            android.util.Log.e("PrivateHeart", "scanMediaPath: $e")
            false
        }
    }


    /** Absolute filesystem path for a MediaStore / photo_manager asset id. */
    fun resolveMediaPathById(id: Long, isVideo: Boolean): String? {
        val collections = mutableListOf<Uri>()
        // Prefer the declared type first, then the other, then Files.
        collections.add(contentUriForMediaId(id, isVideo))
        collections.add(contentUriForMediaId(id, !isVideo))
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                collections.add(
                    ContentUris.withAppendedId(
                        MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL),
                        id,
                    ),
                )
            } else {
                collections.add(
                    ContentUris.withAppendedId(MediaStore.Files.getContentUri("external"), id),
                )
            }
        } catch (_: Exception) {
        }

        for (uri in collections) {
            try {
                @Suppress("DEPRECATION")
                val path = resolver.query(
                    uri,
                    arrayOf(
                        MediaStore.MediaColumns.DATA,
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        MediaStore.MediaColumns.DISPLAY_NAME,
                    ),
                    null,
                    null,
                    null,
                )?.use { c ->
                    if (!c.moveToFirst()) return@use null
                    val dataIdx = c.getColumnIndex(MediaStore.MediaColumns.DATA)
                    if (dataIdx >= 0) {
                        val data = c.getString(dataIdx)
                        if (!data.isNullOrBlank() && File(data).exists() && File(data).length() > 0L) {
                            return@use data
                        }
                    }
                    val relIdx = c.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
                    val nameIdx = c.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                    val rel = if (relIdx >= 0) c.getString(relIdx) else null
                    val name = if (nameIdx >= 0) c.getString(nameIdx) else null
                    if (!rel.isNullOrBlank() && !name.isNullOrBlank()) {
                        val candidate = "/storage/emulated/0/" + rel.trimEnd('/') + "/" + name
                        if (File(candidate).exists() && File(candidate).length() > 0L) {
                            return@use candidate
                        }
                    }
                    null
                }
                if (!path.isNullOrBlank()) {
                    android.util.Log.i("PrivateHeart", "resolveMediaPathById id=$id → $path")
                    return path
                }
            } catch (e: Exception) {
                android.util.Log.w("PrivateHeart", "resolveMediaPathById $uri: $e")
            }
        }
        android.util.Log.w("PrivateHeart", "resolveMediaPathById id=$id not found")
        return null
    }

    fun findMediaUri(path: String, isVideo: Boolean): Uri? {
        val collection = if (isVideo) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            } else {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            }
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
        }
        val projection = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DATA)
        // DATA is deprecated but still the practical lookup for path-based hide.
        val selection = MediaStore.MediaColumns.DATA + "=?"
        return try {
            resolver.query(collection, projection, selection, arrayOf(path), null)?.use { c ->
                if (c.moveToFirst()) {
                    val id = c.getLong(c.getColumnIndexOrThrow(MediaStore.MediaColumns._ID))
                    ContentUris.withAppendedId(collection, id)
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    fun queryDataColumn(uri: Uri): String? {
        return try {
            resolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)
                ?.use { c ->
                    if (c.moveToFirst()) {
                        val idx = c.getColumnIndex(MediaStore.MediaColumns.DATA)
                        if (idx >= 0) c.getString(idx) else null
                    } else {
                        null
                    }
                }
        } catch (_: Exception) {
            null
        }
    }

    fun rescan(paths: List<String>) {
        try {
            MediaScannerConnection.scanFile(context, paths.toTypedArray(), null, null)
        } catch (_: Exception) {
        }
    }


    fun removeOriginal(uriString: String): Boolean {
        return try {
            val uri = Uri.parse(uriString)
            val rows = resolver.delete(uri, null, null)
            rows > 0
        } catch (_: SecurityException) {
            false
        } catch (_: Exception) {
            false
        }
    }
}
