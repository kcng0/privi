package com.privi.app

import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Owns vault file transfers, rename compatibility, and file intents. */
class VaultFileHandler(
    private val context: Context,
    private val resolver: ContentResolver,
    private val mediaStore: MediaStoreIndexHandler,
) {
    private fun isAllFilesAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true
        }
    }

    /**
     * Directory hide in one call:
     * resolve real file → **atomic move** into .privateheart_vault (prefer O(1)
     * inode rename with All Files Access) → drop MediaStore index by id.
     * Byte-copy is only a fallback when rename is impossible.
     * Never scan the vault path.
     */
    fun hideToVault(
        sourcePath: String?,
        mediaId: Long?,
        destPath: String,
        isVideo: Boolean,
    ): Map<String, Any?> {
        android.util.Log.i(
            "PrivateHeart",
            "hideToVault src=$sourcePath id=$mediaId dest=$destPath video=$isVideo manage=${isAllFilesAccess()}",
        )
        try {
            val dest = File(destPath)
            dest.parentFile?.mkdirs()
            // Ensure .nomedia in dest folder + vault root
            try {
                val parent = dest.parentFile
                if (parent != null) {
                    val nm = File(parent, ".nomedia")
                    if (!nm.exists()) nm.createNewFile()
                }
            } catch (_: Exception) {
            }

            if (dest.exists()) {
                if (dest.length() > 0L) {
                    return mapOf("ok" to false, "error" to "exists")
                }
                dest.delete()
            }

            // Resolve source URI + path
            var uri: Uri? = null
            var srcFile: File? = null
            if (mediaId != null) {
                uri = mediaStore.contentUriForMediaId(mediaId, isVideo)
                val resolved = mediaStore.resolveMediaPathById(mediaId, isVideo)
                if (!resolved.isNullOrBlank()) {
                    val f = File(resolved)
                    if (f.exists() && f.length() > 0L) srcFile = f
                }
            }
            if (srcFile == null && !sourcePath.isNullOrBlank()) {
                val f = File(sourcePath)
                if (f.exists() && f.length() > 0L) {
                    srcFile = f
                }
                if (uri == null) {
                    uri = mediaStore.findMediaUri(sourcePath, isVideo)
                }
            }
            if (uri == null && mediaId != null) {
                uri = mediaStore.contentUriForMediaId(mediaId, isVideo)
            }

            var transferred = false
            // True only when we had to byte-copy (original may still exist).
            var usedByteCopy = false
            var srcLen = srcFile?.length() ?: 0L
            var method = "none"

            // 1) Atomic same-volume rename/move — O(1) metadata, not full-file IO.
            // With MANAGE_EXTERNAL_STORAGE this is the primary path for vault hide.
            if (srcFile != null && srcFile.exists()) {
                srcLen = srcFile.length()
                try {
                    Files.move(
                        srcFile.toPath(),
                        dest.toPath(),
                        StandardCopyOption.REPLACE_EXISTING,
                    )
                    if (dest.exists() && (srcLen == 0L || dest.length() > 0L)) {
                        transferred = true
                        method = "Files.move"
                        android.util.Log.i(
                            "PrivateHeart",
                            "hideToVault Files.move len=${dest.length()}",
                        )
                    }
                } catch (e: Exception) {
                    android.util.Log.w("PrivateHeart", "Files.move: $e")
                }
                if (!transferred) {
                    try {
                        if (srcFile.renameTo(dest) &&
                            dest.exists() &&
                            (srcLen == 0L || dest.length() > 0L)
                        ) {
                            transferred = true
                            method = "renameTo"
                            android.util.Log.i(
                                "PrivateHeart",
                                "hideToVault renameTo len=${dest.length()}",
                            )
                        }
                    } catch (e: Exception) {
                        android.util.Log.w("PrivateHeart", "renameTo: $e")
                    }
                }
            }

            // 2) URI stream copy only when rename is impossible (scoped / missing path).
            if (!transferred && uri != null) {
                try {
                    resolver.openInputStream(uri)?.use { input ->
                        dest.outputStream().use { output -> input.copyTo(output) }
                    }
                    if (dest.exists() && dest.length() > 0L) {
                        transferred = true
                        usedByteCopy = true
                        method = "uri-copy"
                        android.util.Log.i(
                            "PrivateHeart",
                            "hideToVault uri-copy len=${dest.length()}",
                        )
                    } else if (dest.exists()) {
                        dest.delete()
                    }
                } catch (e: Exception) {
                    android.util.Log.w("PrivateHeart", "uri-copy: $e")
                    if (dest.exists() && dest.length() == 0L) dest.delete()
                }
            }

            // 3) Filesystem byte-copy fallback.
            if (!transferred && srcFile != null && srcFile.exists()) {
                try {
                    srcFile.inputStream().use { input ->
                        dest.outputStream().use { output -> input.copyTo(output) }
                    }
                    if (dest.exists() && dest.length() > 0L) {
                        transferred = true
                        usedByteCopy = true
                        method = "fs-copy"
                        android.util.Log.i(
                            "PrivateHeart",
                            "hideToVault fs-copy len=${dest.length()}",
                        )
                    }
                } catch (e: Exception) {
                    android.util.Log.w("PrivateHeart", "fs-copy: $e")
                }
            }

            if (!transferred || !dest.exists() || dest.length() <= 0L) {
                if (dest.exists()) dest.delete()
                return mapOf(
                    "ok" to false,
                    "error" to "transfer_failed",
                    "needManageStorage" to !isAllFilesAccess(),
                    "src" to (srcFile?.absolutePath ?: sourcePath),
                    "srcLen" to srcLen,
                    "uri" to (uri?.toString() ?: ""),
                )
            }

            // After byte-copy, remove the original if it is still on disk.
            // After atomic move/rename the original path is already gone.
            if (usedByteCopy) {
                try {
                    if (srcFile != null &&
                        srcFile.exists() &&
                        srcFile.absolutePath != dest.absolutePath
                    ) {
                        srcFile.delete()
                    }
                } catch (_: Exception) {
                }
                if (!sourcePath.isNullOrBlank()) {
                    try {
                        val s = File(sourcePath)
                        if (s.exists() && s.absolutePath != dest.absolutePath) s.delete()
                    } catch (_: Exception) {
                    }
                }
            }

            // MediaStore: one targeted delete by content URI (known _ID).
            // Avoid multi-collection path walks unless the URI delete is unavailable.
            var indexDropped = false
            if (uri != null) {
                try {
                    resolver.delete(uri, null, null)
                    indexDropped = true
                } catch (e: Exception) {
                    android.util.Log.w("PrivateHeart", "delete uri index: $e")
                }
            }
            if (!indexDropped) {
                val pathForIndex = when {
                    srcFile != null -> srcFile.absolutePath
                    !sourcePath.isNullOrBlank() -> sourcePath
                    else -> null
                }
                if (!pathForIndex.isNullOrBlank()) {
                    mediaStore.hideInMediaStore(pathForIndex, isVideo)
                }
            }

            android.util.Log.i(
                "PrivateHeart",
                "hideToVault OK method=$method dest=${dest.absolutePath} len=${dest.length()}",
            )
            return mapOf(
                "ok" to true,
                "newPath" to dest.absolutePath,
                "size" to dest.length(),
                "method" to method,
            )
        } catch (e: Exception) {
            android.util.Log.e("PrivateHeart", "hideToVault fatal: $e")
            return mapOf("ok" to false, "error" to (e.message ?: "fatal"))
        }
    }

    /**
     * Batch hide: one MethodChannel call processes many items on the IO pool.
     * Each entry may include clientId for Dart-side correlation.
     */
    fun hideToVaultBatch(rawItems: List<*>): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>(rawItems.size)
        for (entry in rawItems) {
            val map = entry as? Map<*, *>
            if (map == null) {
                out.add(mapOf("ok" to false, "error" to "bad_item"))
                continue
            }
            fun str(key: String): String? {
                val v = map[key] ?: return null
                val s = v.toString()
                return s.ifEmpty { null }
            }
            val clientId = str("clientId")
            val destPath = str("newPath")
            if (destPath.isNullOrEmpty()) {
                out.add(
                    buildMap {
                        put("ok", false)
                        put("error", "bad_args")
                        if (clientId != null) put("clientId", clientId)
                    },
                )
                continue
            }
            val mediaIdStr = str("mediaId")
            val mediaId = mediaIdStr?.toLongOrNull()
            val isVideo = when (val v = map["isVideo"]) {
                is Boolean -> v
                is Number -> v.toInt() != 0
                else -> false
            }
            val result = hideToVault(
                sourcePath = str("path"),
                mediaId = mediaId,
                destPath = destPath,
                isVideo = isVideo,
            )
            if (clientId != null) {
                val withId = result.toMutableMap()
                withId["clientId"] = clientId
                out.add(withId)
            } else {
                out.add(result)
            }
        }
        return out
    }

    /**
     * Unhide one vault file: atomic move out of .privateheart_vault + MediaStore
     * re-index with optional original DATE_TAKEN / DATE_ADDED.
     */
    fun unhideFromVault(
        sourcePath: String,
        destPath: String,
        mimeType: String?,
        dateTakenSec: Long?,
        dateAddedSec: Long?,
    ): Map<String, Any?> {
        android.util.Log.i(
            "PrivateHeart",
            "unhideFromVault src=$sourcePath dest=$destPath taken=$dateTakenSec",
        )
        try {
            val src = File(sourcePath)
            val dest = File(destPath)
            if (!src.exists() || src.length() <= 0L) {
                return mapOf("ok" to false, "error" to "missing_src")
            }
            dest.parentFile?.mkdirs()
            if (dest.exists() && dest.absolutePath != src.absolutePath) {
                // Caller should have uniquified; refuse clobber.
                return mapOf("ok" to false, "error" to "exists")
            }

            var moved = false
            var method = "none"
            if (src.absolutePath == dest.absolutePath) {
                moved = true
                method = "same_path"
            } else {
                try {
                    Files.move(
                        src.toPath(),
                        dest.toPath(),
                        StandardCopyOption.REPLACE_EXISTING,
                    )
                    if (dest.exists() && dest.length() > 0L) {
                        moved = true
                        method = "Files.move"
                    }
                } catch (e: Exception) {
                    android.util.Log.w("PrivateHeart", "unhide Files.move: $e")
                }
                if (!moved) {
                    try {
                        if (src.renameTo(dest) && dest.exists() && dest.length() > 0L) {
                            moved = true
                            method = "renameTo"
                        }
                    } catch (e: Exception) {
                        android.util.Log.w("PrivateHeart", "unhide renameTo: $e")
                    }
                }
                if (!moved) {
                    try {
                        src.inputStream().use { input ->
                            dest.outputStream().use { output -> input.copyTo(output) }
                        }
                        if (dest.exists() && dest.length() > 0L) {
                            moved = true
                            method = "fs-copy"
                            try {
                                src.delete()
                            } catch (_: Exception) {
                            }
                        }
                    } catch (e: Exception) {
                        android.util.Log.w("PrivateHeart", "unhide fs-copy: $e")
                    }
                }
            }

            if (!moved || !dest.exists() || dest.length() <= 0L) {
                if (dest.exists() && dest.absolutePath != src.absolutePath) {
                    try {
                        dest.delete()
                    } catch (_: Exception) {
                    }
                }
                return mapOf(
                    "ok" to false,
                    "error" to "transfer_failed",
                    "needManageStorage" to !isAllFilesAccess(),
                )
            }

            // Re-index into MediaStore (capture dates when known).
            mediaStore.scanMediaPath(
                dest.absolutePath,
                mimeType,
                dateTakenSec = dateTakenSec,
                dateAddedSec = dateAddedSec ?: dateTakenSec,
            )

            android.util.Log.i(
                "PrivateHeart",
                "unhideFromVault OK method=$method dest=${dest.absolutePath} len=${dest.length()}",
            )
            return mapOf(
                "ok" to true,
                "newPath" to dest.absolutePath,
                "size" to dest.length(),
                "method" to method,
            )
        } catch (e: Exception) {
            android.util.Log.e("PrivateHeart", "unhideFromVault fatal: $e")
            return mapOf("ok" to false, "error" to (e.message ?: "fatal"))
        }
    }

    fun unhideFromVaultBatch(rawItems: List<*>): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>(rawItems.size)
        for (entry in rawItems) {
            val map = entry as? Map<*, *>
            if (map == null) {
                out.add(mapOf("ok" to false, "error" to "bad_item"))
                continue
            }
            fun str(key: String): String? {
                val v = map[key] ?: return null
                val s = v.toString()
                return s.ifEmpty { null }
            }
            fun longOrNull(key: String): Long? {
                val v = map[key] ?: return null
                return when (v) {
                    is Number -> v.toLong()
                    else -> v.toString().toLongOrNull()
                }
            }
            val clientId = str("clientId")
            val path = str("path")
            val newPath = str("newPath")
            if (path.isNullOrEmpty() || newPath.isNullOrEmpty()) {
                out.add(
                    buildMap {
                        put("ok", false)
                        put("error", "bad_args")
                        if (clientId != null) put("clientId", clientId)
                    },
                )
                continue
            }
            val result = unhideFromVault(
                sourcePath = path,
                destPath = newPath,
                mimeType = str("mimeType"),
                dateTakenSec = longOrNull("dateTakenSec"),
                dateAddedSec = longOrNull("dateAddedSec"),
            )
            if (clientId != null) {
                val withId = result.toMutableMap()
                withId["clientId"] = clientId
                out.add(withId)
            } else {
                out.add(result)
            }
        }
        return out
    }

    fun renameMedia(path: String, newPath: String, isVideo: Boolean): Map<String, Any?> {
        val src = File(path)
        val dest = File(newPath)
        android.util.Log.i("PrivateHeart", "renameMedia start path=$path new=$newPath video=$isVideo manage=${isAllFilesAccess()}")
        if (!src.exists()) {
            return mapOf("ok" to false, "error" to "missing", "needManageStorage" to !isAllFilesAccess())
        }
        if (dest.absolutePath == src.absolutePath) {
            mediaStore.hideInMediaStore(src.absolutePath, isVideo)
            return mapOf("ok" to true, "newPath" to src.absolutePath)
        }
        if (dest.exists()) {
            return mapOf("ok" to false, "error" to "exists")
        }

        val uri = mediaStore.findMediaUri(path, isVideo)

        // Mark pending first so pickers drop it while we rename.
        if (uri != null) {
            try {
                val pending = ContentValues().apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        put(MediaStore.MediaColumns.IS_PENDING, 1)
                    }
                }
                if (pending.size() > 0) {
                    resolver.update(uri, pending, null, null)
                }
            } catch (e: Exception) {
                android.util.Log.w("PrivateHeart", "IS_PENDING pre-rename: $e")
            }
        }

        // Move into hide vault. Verify non-empty dest when source had bytes.
        val srcLen = src.length()
        var renamed = false
        try {
            dest.parentFile?.mkdirs()
            // 1) Atomic-ish move
            try {
                Files.move(src.toPath(), dest.toPath(), StandardCopyOption.REPLACE_EXISTING)
                renamed = dest.exists() && (srcLen == 0L || dest.length() == srcLen)
                android.util.Log.i(
                    "PrivateHeart",
                    "Files.move ok=$renamed srcLen=$srcLen destLen=${if (dest.exists()) dest.length() else -1}",
                )
            } catch (e: Exception) {
                android.util.Log.w("PrivateHeart", "Files.move failed: $e")
            }
            // 2) renameTo
            if (!renamed && src.exists()) {
                try {
                    if (dest.exists()) dest.delete()
                    val ok = src.renameTo(dest)
                    renamed = ok && dest.exists() && (srcLen == 0L || dest.length() == srcLen)
                    android.util.Log.i("PrivateHeart", "renameTo ok=$renamed destLen=${if (dest.exists()) dest.length() else -1}")
                } catch (e: Exception) {
                    android.util.Log.w("PrivateHeart", "renameTo failed: $e")
                }
            }
            // 3) Byte copy from filesystem source
            if (!renamed && src.exists()) {
                try {
                    if (dest.exists()) dest.delete()
                    src.inputStream().use { input ->
                        dest.outputStream().use { output -> input.copyTo(output) }
                    }
                    renamed = dest.exists() && dest.length() == srcLen && srcLen > 0L
                    if (renamed) {
                        if (!src.delete()) {
                            android.util.Log.w("PrivateHeart", "copy ok; source delete failed path=$path")
                        }
                    } else if (dest.exists() && dest.length() == 0L) {
                        dest.delete()
                    }
                    android.util.Log.i("PrivateHeart", "fs copy+delete ok=$renamed")
                } catch (e: Exception) {
                    android.util.Log.e("PrivateHeart", "fs copy failed: $e")
                    if (dest.exists() && dest.length() == 0L) dest.delete()
                }
            }
            // 4) Byte copy from MediaStore URI (handles scoped paths better)
            if (!renamed && uri != null) {
                try {
                    if (dest.exists()) dest.delete()
                    resolver.openInputStream(uri)?.use { input ->
                        dest.outputStream().use { output -> input.copyTo(output) }
                    } ?: throw IllegalStateException("openInputStream null")
                    val destLen = if (dest.exists()) dest.length() else 0L
                    renamed = dest.exists() && destLen > 0L
                    android.util.Log.i("PrivateHeart", "uri copy ok=$renamed destLen=$destLen srcLen=$srcLen")
                    if (renamed) {
                        // Remove original file if still present
                        try {
                            if (src.exists()) src.delete()
                        } catch (_: Exception) {
                        }
                        // Remove MediaStore index for original (file should be gone).
                        try {
                            resolver.delete(uri, null, null)
                        } catch (e: Exception) {
                            android.util.Log.w("PrivateHeart", "delete index after uri copy: $e")
                        }
                    } else if (dest.exists()) {
                        dest.delete()
                    }
                } catch (e: Exception) {
                    android.util.Log.e("PrivateHeart", "uri copy failed: $e")
                    if (dest.exists() && dest.length() == 0L) dest.delete()
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("PrivateHeart", "fs rename outer: $e")
        }

        if (!renamed) {
            // MediaStore-only DISPLAY_NAME update as last resort.
            if (uri != null) {
                try {
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, dest.name)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            put(MediaStore.MediaColumns.IS_PENDING, 1)
                        }
                    }
                    val rows = resolver.update(uri, values, null, null)
                    if (rows > 0) {
                        // Try fs rename again after MediaStore granted write.
                        try {
                            if (src.exists()) {
                                Files.move(src.toPath(), dest.toPath(), StandardCopyOption.REPLACE_EXISTING)
                            }
                        } catch (_: Exception) {
                            if (src.exists()) src.renameTo(dest)
                        }
                        val finalPath = when {
                            dest.exists() -> dest.absolutePath
                            src.exists() -> src.absolutePath
                            else -> dest.absolutePath
                        }
                        mediaStore.hideInMediaStore(path, isVideo)
                        mediaStore.hideInMediaStore(finalPath, isVideo)
                        if (File(finalPath).exists()) {
                            return mapOf("ok" to true, "newPath" to finalPath)
                        }
                    }
                } catch (e: SecurityException) {
                    android.util.Log.e("PrivateHeart", "rename security: $e")
                    return mapOf(
                        "ok" to false,
                        "error" to "security",
                        "needManageStorage" to !isAllFilesAccess(),
                    )
                } catch (e: Exception) {
                    android.util.Log.e("PrivateHeart", "rename update: $e")
                    return mapOf(
                        "ok" to false,
                        "error" to (e.message ?: "update_failed"),
                        "needManageStorage" to !isAllFilesAccess(),
                    )
                }
            }
            return mapOf(
                "ok" to false,
                "error" to "rename_denied",
                "needManageStorage" to !isAllFilesAccess(),
            )
        }

        // Renamed on disk — update MediaStore to point at new path and stay pending
        // (hidden from Gallery / image-video pickers). Do not delete the row by id.
        if (uri != null) {
            try {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, dest.name)
                    // DATA still works for lookup on many OEMs with all-files access.
                    @Suppress("DEPRECATION")
                    put(MediaStore.MediaColumns.DATA, dest.absolutePath)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        put(MediaStore.MediaColumns.IS_PENDING, 1)
                    }
                }
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                android.util.Log.w("PrivateHeart", "post-rename MediaStore update: $e")
            }
        }

        // Drop stale MediaStore index for the **original** path only.
        // Do not touch the new path inside .privateheart_vault — .nomedia blocks scans.
        mediaStore.hideInMediaStore(path, isVideo)

        if (!dest.exists()) {
            android.util.Log.e("PrivateHeart", "rename ok but dest missing")
            return mapOf("ok" to false, "error" to "dest_missing")
        }
        if (srcLen > 0L && dest.length() == 0L) {
            android.util.Log.e("PrivateHeart", "dest is empty after hide")
            try { dest.delete() } catch (_: Exception) {}
            return mapOf("ok" to false, "error" to "empty_dest")
        }
        android.util.Log.i(
            "PrivateHeart",
            "renameMedia ok → ${dest.absolutePath} len=${dest.length()}",
        )
        return mapOf("ok" to true, "newPath" to dest.absolutePath)
    }

    /** Builds a result-tracked ACTION_VIEW intent for VLC/system players. */
    fun createExternalPlayerIntent(path: String, mimeType: String): Intent? {
        val file = File(path)
        if (!file.isFile) return null

        val uri = FileProvider.getUriForFile(
            context,
            "${context.applicationContext.packageName}.fileprovider",
            file,
        )
        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType.ifBlank { "*/*" })
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        val matches: List<ResolveInfo> = context.packageManager.queryIntentActivities(
            viewIntent,
            PackageManager.MATCH_DEFAULT_ONLY,
        )
        return viewIntent.takeIf { matches.isNotEmpty() }
    }
}
