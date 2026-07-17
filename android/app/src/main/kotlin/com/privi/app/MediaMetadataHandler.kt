package com.privi.app

import android.content.ContentResolver
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.provider.MediaStore
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/** Resolves capture timestamps without falling back to filesystem mtime. */
class MediaMetadataHandler(
    private val resolver: ContentResolver,
    private val mediaStore: MediaStoreIndexHandler,
) {
    fun resolveCaptureDateSec(
        path: String?,
        mediaId: Long?,
        isVideo: Boolean,
    ): Long? {
        // 1) MediaStore DATE_TAKEN by id
        if (mediaId != null) {
            val fromStore = queryDateTakenSecById(mediaId, isVideo)
            if (fromStore != null && fromStore > 0L) return fromStore
        }
        // 1b) MediaStore DATE_TAKEN by path
        if (!path.isNullOrBlank()) {
            val fromPath = queryDateTakenSecByPath(path, isVideo)
            if (fromPath != null && fromPath > 0L) return fromPath
        }
        val filePath = path?.takeIf { it.isNotBlank() }
            ?: mediaId?.let { mediaStore.resolveMediaPathById(it, isVideo) }
        if (filePath.isNullOrBlank()) return null
        val file = File(filePath)
        if (!file.exists()) return null

        // 2) Image EXIF
        if (!isVideo) {
            val exifSec = readExifDateSec(filePath)
            if (exifSec != null && exifSec > 0L) return exifSec
        }
        // 3) Video container date
        if (isVideo) {
            val vidSec = readVideoDateSec(filePath)
            if (vidSec != null && vidSec > 0L) return vidSec
        }
        // Still try EXIF for mis-tagged video=false images with odd mime.
        val exifSec = readExifDateSec(filePath)
        if (exifSec != null && exifSec > 0L) return exifSec
        return null
    }

    private fun queryDateTakenSecById(id: Long, isVideo: Boolean): Long? {
        val uris = listOf(
            mediaStore.contentUriForMediaId(id, isVideo),
            mediaStore.contentUriForMediaId(id, !isVideo),
        )
        for (uri in uris) {
            try {
                resolver.query(
                    uri,
                    arrayOf(MediaStore.MediaColumns.DATE_TAKEN),
                    null,
                    null,
                    null,
                )?.use { c ->
                    if (c.moveToFirst()) {
                        val idx = c.getColumnIndex(MediaStore.MediaColumns.DATE_TAKEN)
                        if (idx >= 0 && !c.isNull(idx)) {
                            val ms = c.getLong(idx)
                            if (ms > 0L) return ms / 1000L
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.w("PrivateHeart", "queryDateTakenSecById: $e")
            }
        }
        return null
    }

    private fun queryDateTakenSecByPath(path: String, isVideo: Boolean): Long? {
        val selection = MediaStore.MediaColumns.DATA + "=?"
        for (p in mediaStore.pathVariants(path)) {
            for (collection in mediaStore.mediaCollections(isVideo)) {
                try {
                    resolver.query(
                        collection,
                        arrayOf(MediaStore.MediaColumns.DATE_TAKEN),
                        selection,
                        arrayOf(p),
                        null,
                    )?.use { c ->
                        if (c.moveToFirst()) {
                            val idx = c.getColumnIndex(MediaStore.MediaColumns.DATE_TAKEN)
                            if (idx >= 0 && !c.isNull(idx)) {
                                val ms = c.getLong(idx)
                                if (ms > 0L) return ms / 1000L
                            }
                        }
                    }
                } catch (_: Exception) {
                }
            }
        }
        return null
    }

    private fun readExifDateSec(path: String): Long? {
        return try {
            val exif = ExifInterface(path)
            val raw = exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
                ?: exif.getAttribute(ExifInterface.TAG_DATETIME)
                ?: return null
            // EXIF: "yyyy:MM:dd HH:mm:ss" (no timezone — treat as local).
            val fmt = SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US)
            fmt.isLenient = true
            val parsed = fmt.parse(raw) ?: return null
            parsed.time / 1000L
        } catch (e: Exception) {
            android.util.Log.w("PrivateHeart", "readExifDateSec: $e")
            null
        }
    }

    private fun readVideoDateSec(path: String): Long? {
        var retriever: MediaMetadataRetriever? = null
        return try {
            retriever = MediaMetadataRetriever()
            retriever.setDataSource(path)
            val raw = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE)
                ?: return null
            // Common: "yyyyMMdd'T'HHmmss.SSS'Z'" or similar.
            val patterns = arrayOf(
                "yyyyMMdd'T'HHmmss.SSS'Z'",
                "yyyyMMdd'T'HHmmss'Z'",
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                "yyyy-MM-dd'T'HH:mm:ss'Z'",
                "yyyy:MM:dd HH:mm:ss",
            )
            for (p in patterns) {
                try {
                    val fmt = SimpleDateFormat(p, Locale.US)
                    fmt.timeZone = TimeZone.getTimeZone("UTC")
                    val parsed = fmt.parse(raw)
                    if (parsed != null) return parsed.time / 1000L
                } catch (_: Exception) {
                }
            }
            null
        } catch (e: Exception) {
            android.util.Log.w("PrivateHeart", "readVideoDateSec: $e")
            null
        } finally {
            try {
                retriever?.release()
            } catch (_: Exception) {
            }
        }
    }
}
