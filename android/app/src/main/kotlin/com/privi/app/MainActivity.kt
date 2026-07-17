package com.privi.app

import android.content.ContentUris
import android.content.pm.ResolveInfo
import android.content.pm.PackageManager
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
// FlutterFragmentActivity is required by local_auth (BiometricPrompt needs a FragmentActivity).
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors

/// Host activity: FileProvider, FLAG_SECURE, MediaStore rename for directory hide.
/// Extends [FlutterFragmentActivity] so [local_auth] can show BiometricPrompt.
class MainActivity : FlutterFragmentActivity() {
    private val mediaStoreChannel = "com.privi.app/mediastore"
    private val filesChannel = "com.privi.app/files"
    private val windowChannel = "com.privi.app/window"

    // IO for hide/thumbnail so concurrent Dart workers can overlap.
    private val ioExecutor = Executors.newFixedThreadPool(3)
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun <T> runIo(result: MethodChannel.Result, block: () -> T) {
        ioExecutor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("io_error", e.message, null)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaStoreChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "removeOriginal" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString.isNullOrEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(removeOriginal(uriString))
                    }
                    "purgeMediaStorePath" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(purgeMediaStoreByPath(path) > 0)
                    }
                    "scanMediaPath" -> {
                        val path = call.argument<String>("path")
                        val mime = call.argument<String>("mimeType")
                        // Optional original capture/create epochs (seconds).
                        val dateTakenSec = call.argument<Number>("dateTakenSec")?.toLong()
                        val dateAddedSec = call.argument<Number>("dateAddedSec")?.toLong()
                        if (path.isNullOrEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(
                            scanMediaPath(
                                path,
                                mime,
                                dateTakenSec = dateTakenSec,
                                dateAddedSec = dateAddedSec,
                            ),
                        )
                    }
                    "resolveMediaPath" -> {
                        val idStr = call.argument<String>("id")
                        val isVideo = call.argument<Boolean>("isVideo") ?: false
                        if (idStr.isNullOrEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val id = idStr.toLongOrNull()
                        if (id == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        result.success(resolveMediaPathById(id, isVideo))
                    }
                    "resolveCaptureDate" -> {
                        // Capture/taken time only — never DATE_MODIFIED / mtime.
                        val path = call.argument<String>("path")
                        val mediaId = call.argument<String>("mediaId")?.toLongOrNull()
                        val isVideo = call.argument<Boolean>("isVideo") ?: false
                        runIo(result) {
                            resolveCaptureDateSec(path, mediaId, isVideo)
                        }
                    }
                    "isExternalStorageManager" -> {
                        result.success(isAllFilesAccess())
                    }
                    "openManageAllFilesSettings" -> {
                        openAllFilesSettings()
                        result.success(null)
                    }
                    "renameMedia" -> {
                        val path = call.argument<String>("path")
                        val newPath = call.argument<String>("newPath")
                        val isVideo = call.argument<Boolean>("isVideo") ?: false
                        if (path.isNullOrEmpty() || newPath.isNullOrEmpty()) {
                            result.success(mapOf("ok" to false, "error" to "bad_args"))
                            return@setMethodCallHandler
                        }
                        result.success(renameMedia(path, newPath, isVideo))
                    }
                    "hideToVault" -> {
                        val path = call.argument<String>("path")
                        val newPath = call.argument<String>("newPath")
                        val isVideo = call.argument<Boolean>("isVideo") ?: false
                        val mediaId = call.argument<String>("mediaId")
                        if (newPath.isNullOrEmpty()) {
                            result.success(mapOf("ok" to false, "error" to "bad_args"))
                            return@setMethodCallHandler
                        }
                        runIo(result) {
                            hideToVault(
                                sourcePath = path,
                                mediaId = mediaId?.toLongOrNull(),
                                destPath = newPath,
                                isVideo = isVideo,
                            )
                        }
                    }
                    "hideToVaultBatch" -> {
                        val rawItems = call.argument<List<*>>("items")
                        if (rawItems.isNullOrEmpty()) {
                            result.success(emptyList<Map<String, Any?>>())
                            return@setMethodCallHandler
                        }
                        runIo(result) {
                            hideToVaultBatch(rawItems)
                        }
                    }
                    "unhideFromVault" -> {
                        val path = call.argument<String>("path")
                        val newPath = call.argument<String>("newPath")
                        val mime = call.argument<String>("mimeType")
                        val dateTakenSec = call.argument<Number>("dateTakenSec")?.toLong()
                        val dateAddedSec = call.argument<Number>("dateAddedSec")?.toLong()
                        if (path.isNullOrEmpty() || newPath.isNullOrEmpty()) {
                            result.success(mapOf("ok" to false, "error" to "bad_args"))
                            return@setMethodCallHandler
                        }
                        runIo(result) {
                            unhideFromVault(
                                sourcePath = path,
                                destPath = newPath,
                                mimeType = mime,
                                dateTakenSec = dateTakenSec,
                                dateAddedSec = dateAddedSec,
                            )
                        }
                    }
                    "unhideFromVaultBatch" -> {
                        val rawItems = call.argument<List<*>>("items")
                        if (rawItems.isNullOrEmpty()) {
                            result.success(emptyList<Map<String, Any?>>())
                            return@setMethodCallHandler
                        }
                        runIo(result) {
                            unhideFromVaultBatch(rawItems)
                        }
                    }
                    "videoThumbnail" -> {
                        val path = call.argument<String>("path")
                        val destPath = call.argument<String>("destPath")
                        val maxSize = call.argument<Int>("maxSize") ?: 256
                        if (path.isNullOrEmpty() || destPath.isNullOrEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        runIo(result) {
                            extractVideoThumbnail(path, destPath, maxSize)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, filesChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "contentUriForPath" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        result.success(contentUriForPath(path))
                    }
                    "openWithChooser" -> {
                        val path = call.argument<String>("path")
                        val mime = call.argument<String>("mimeType") ?: "*/*"
                        val title = call.argument<String>("title") ?: "Open with"
                        if (path.isNullOrEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(openWithChooser(path, mime, title))
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, windowChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setFlagSecure" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isAllFilesAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true
        }
    }

    private fun openAllFilesSettings() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                intent.data = Uri.parse("package:$packageName")
                startActivity(intent)
            } else {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                intent.data = Uri.parse("package:$packageName")
                startActivity(intent)
            }
        } catch (_: Exception) {
            val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
            startActivity(intent)
        }
    }

    /**
     * rename-based directory hide.
     *
     * Acceptance: item must disappear from system Gallery / image-video pickers
     * (媒体浏览器). Strategy:
     * 1) Rename file on disk (marker in name).
     * 2) Update MediaStore row: new DATA/DISPLAY_NAME + IS_PENDING=1 so galleries
     *    and pickers skip it.
     * 3) NEVER ContentResolver.delete on the media URI after rename — with
     *    MANAGE_EXTERNAL_STORAGE that often **deletes the file** and caused
     *    "1 failed" on image hide.
     */

    /**
     * Directory hide in one call:
     * resolve real file → **atomic move** into .privateheart_vault (prefer O(1)
     * inode rename with All Files Access) → drop MediaStore index by id.
     * Byte-copy is only a fallback when rename is impossible.
     * Never scan the vault path.
     */
    private fun hideToVault(
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
                uri = contentUriForMediaId(mediaId, isVideo)
                val resolved = resolveMediaPathById(mediaId, isVideo)
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
                    uri = findMediaUri(sourcePath, isVideo)
                }
            }
            if (uri == null && mediaId != null) {
                uri = contentUriForMediaId(mediaId, isVideo)
            }

            var transferred = false
            // True only when we had to byte-copy (original may still exist).
            var usedByteCopy = false
            var srcLen = srcFile?.length() ?: 0L
            var method = "none"

            // 1) Atomic same-volume rename/move — O(1) metadata, not full-file IO.
            // With MANAGE_EXTERNAL_STORAGE this is the primary path for vault hide.
            if (srcFile != null && srcFile!!.exists()) {
                srcLen = srcFile!!.length()
                try {
                    Files.move(
                        srcFile!!.toPath(),
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
                        if (srcFile!!.renameTo(dest) &&
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
                    contentResolver.openInputStream(uri)?.use { input ->
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
            if (!transferred && srcFile != null && srcFile!!.exists()) {
                try {
                    srcFile!!.inputStream().use { input ->
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
                        srcFile!!.exists() &&
                        srcFile!!.absolutePath != dest.absolutePath
                    ) {
                        srcFile!!.delete()
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
                    contentResolver.delete(uri, null, null)
                    indexDropped = true
                } catch (e: Exception) {
                    android.util.Log.w("PrivateHeart", "delete uri index: $e")
                }
            }
            if (!indexDropped) {
                val pathForIndex = when {
                    srcFile != null -> srcFile!!.absolutePath
                    !sourcePath.isNullOrBlank() -> sourcePath
                    else -> null
                }
                if (!pathForIndex.isNullOrBlank()) {
                    hideInMediaStore(pathForIndex, isVideo)
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
    private fun hideToVaultBatch(rawItems: List<*>): List<Map<String, Any?>> {
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
    private fun unhideFromVault(
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
            scanMediaPath(
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

    private fun unhideFromVaultBatch(rawItems: List<*>): List<Map<String, Any?>> {
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

    private fun contentUriForMediaId(id: Long, isVideo: Boolean): Uri {
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

    private fun renameMedia(path: String, newPath: String, isVideo: Boolean): Map<String, Any?> {
        val src = File(path)
        val dest = File(newPath)
        android.util.Log.i("PrivateHeart", "renameMedia start path=$path new=$newPath video=$isVideo manage=${isAllFilesAccess()}")
        if (!src.exists()) {
            return mapOf("ok" to false, "error" to "missing", "needManageStorage" to !isAllFilesAccess())
        }
        if (dest.absolutePath == src.absolutePath) {
            hideInMediaStore(src.absolutePath, isVideo)
            return mapOf("ok" to true, "newPath" to src.absolutePath)
        }
        if (dest.exists()) {
            return mapOf("ok" to false, "error" to "exists")
        }

        val uri = findMediaUri(path, isVideo)

        // Mark pending first so pickers drop it while we rename.
        if (uri != null) {
            try {
                val pending = ContentValues().apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        put(MediaStore.MediaColumns.IS_PENDING, 1)
                    }
                }
                if (pending.size() > 0) {
                    contentResolver.update(uri, pending, null, null)
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
                    contentResolver.openInputStream(uri)?.use { input ->
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
                            contentResolver.delete(uri, null, null)
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
                    val rows = contentResolver.update(uri, values, null, null)
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
                        hideInMediaStore(path, isVideo)
                        hideInMediaStore(finalPath, isVideo)
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
                contentResolver.update(uri, values, null, null)
            } catch (e: Exception) {
                android.util.Log.w("PrivateHeart", "post-rename MediaStore update: $e")
            }
        }

        // Drop stale MediaStore index for the **original** path only.
        // Do not touch the new path inside .privateheart_vault — .nomedia blocks scans.
        hideInMediaStore(path, isVideo)

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

    /**
     * Hide path from galleries/pickers by setting IS_PENDING=1 on matching rows.
     * Does **not** ContentResolver.delete (that deletes the file with all-files access).
     */
    /** Channel helper: soft-hide index for both image and video collections. */
    private fun purgeMediaStoreByPath(path: String): Int {
        return hideInMediaStore(path, isVideo = false) + hideInMediaStore(path, isVideo = true)
    }

    private fun hideInMediaStore(path: String, isVideo: Boolean): Int {
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
                    updated += contentResolver.update(collection, values, selection, arrayOf(p))
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
                        updated += contentResolver.delete(collection, selection, arrayOf(p))
                    } catch (e: Exception) {
                        android.util.Log.w("PrivateHeart", "delete index: $e")
                    }
                }
            }
        }
        return updated
    }

    private fun mediaCollections(preferVideo: Boolean): List<Uri> {
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

    private fun pathVariants(path: String): List<String> {
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
    private fun scanMediaPath(
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
                        revived += contentResolver.update(collection, values, selection, arrayOf(p))
                    } catch (_: Exception) {
                    }
                }
            }
            // Always scan so missing rows are recreated.
            MediaScannerConnection.scanFile(
                this,
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
                        contentResolver.update(uri, fix, null, null)
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
                                contentResolver.update(collection, fix, sel, arrayOf(scannedPath))
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


    /**
     * Capture / taken time in **Unix seconds**.
     *
     * Priority (never DATE_MODIFIED / filesystem mtime):
     * 1) MediaStore DATE_TAKEN (ms) for mediaId
     * 2) Image EXIF DateTimeOriginal / DateTime
     * 3) Video MediaMetadataRetriever METADATA_KEY_DATE
     *
     * Returns null when unknown — callers must not invent "now".
     */
    private fun resolveCaptureDateSec(
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
            ?: mediaId?.let { resolveMediaPathById(it, isVideo) }
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
            contentUriForMediaId(id, isVideo),
            contentUriForMediaId(id, !isVideo),
        )
        for (uri in uris) {
            try {
                contentResolver.query(
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
        for (p in pathVariants(path)) {
            for (collection in mediaCollections(isVideo)) {
                try {
                    contentResolver.query(
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

    /** Absolute filesystem path for a MediaStore / photo_manager asset id. */
    private fun resolveMediaPathById(id: Long, isVideo: Boolean): String? {
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
                val path = contentResolver.query(
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

    private fun findMediaUri(path: String, isVideo: Boolean): Uri? {
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
            contentResolver.query(collection, projection, selection, arrayOf(path), null)?.use { c ->
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

    private fun queryDataColumn(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)
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

    private fun rescan(paths: List<String>) {
        try {
            MediaScannerConnection.scanFile(this, paths.toTypedArray(), null, null)
        } catch (_: Exception) {
        }
    }


    /**
     * Open media with a normal ACTION_VIEW Intent (Android native resolver).
     *
     * - If no preferred app is set: system shows the disambiguation sheet with
     *   **Just once** / **Always** (createChooser deliberately omits those).
     * - If the user already chose Always for this type: opens that app directly.
     * - Grants temporary read URI permission to all matching targets.
     *
     * [title] is unused for plain VIEW (kept for channel API stability).
     */
    private fun openWithChooser(path: String, mimeType: String, title: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false

            val uri = try {
                FileProvider.getUriForFile(
                    this,
                    "${applicationContext.packageName}.fileprovider",
                    file,
                )
            } catch (_: Exception) {
                android.util.Log.e("PrivateHeart", "FileProvider failed for $path")
                return false
            }

            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType.ifBlank { "*/*" })
                // Do NOT use createChooser — that hides Always / Just once on modern Android.
                // Do NOT force NEW_TASK from our Activity — start in the normal task.
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }

            // Grant URI permission to every matching app so the sheet targets work.
            val resInfo: List<ResolveInfo> = packageManager.queryIntentActivities(
                viewIntent,
                PackageManager.MATCH_DEFAULT_ONLY,
            )
            if (resInfo.isEmpty()) {
                android.util.Log.w("PrivateHeart", "No apps resolve ACTION_VIEW for $mimeType")
                return false
            }
            for (info in resInfo) {
                val pkg = info.activityInfo?.packageName ?: continue
                try {
                    grantUriPermission(
                        pkg,
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                } catch (_: Exception) {
                }
            }

            startActivity(viewIntent)
            true
        } catch (e: Exception) {
            android.util.Log.e("PrivateHeart", "openWithChooser failed: $e")
            false
        }
    }

    private fun contentUriForPath(path: String): String? {
        return try {
            val file = File(path)
            if (!file.exists()) return null
            val uri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                file,
            )
            uri.toString()
        } catch (_: Exception) {
            null
        }
    }

    private fun removeOriginal(uriString: String): Boolean {
        return try {
            val uri = Uri.parse(uriString)
            val rows = contentResolver.delete(uri, null, null)
            rows > 0
        } catch (_: SecurityException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Extract a JPEG still from a local video file for vault grid thumbnails.
     * Uses MediaMetadataRetriever — works on vault paths (.nomedia) that MediaStore
     * no longer indexes after hide.
     */
    private fun extractVideoThumbnail(path: String, destPath: String, maxSize: Int): Boolean {
        val src = File(path)
        if (!src.exists() || src.length() <= 0L) return false
        val dest = File(destPath)
        dest.parentFile?.mkdirs()
        if (dest.exists()) {
            try {
                dest.delete()
            } catch (_: Exception) {
            }
        }

        var retriever: MediaMetadataRetriever? = null
        return try {
            retriever = MediaMetadataRetriever()
            retriever.setDataSource(path)
            // Prefer a near-start frame; fall back to first embedded frame.
            var frame: Bitmap? = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    retriever.getScaledFrameAtTime(
                        1_000_000L, // 1s
                        MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                        maxSize,
                        maxSize,
                    )
                } else {
                    null
                }
            } catch (_: Exception) {
                null
            }
            if (frame == null) {
                frame = retriever.getFrameAtTime(
                    1_000_000L,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                ) ?: retriever.frameAtTime
            }
            if (frame == null) return false

            val scaled = scaleDown(frame, maxSize)
            if (scaled !== frame) {
                try {
                    frame.recycle()
                } catch (_: Exception) {
                }
            }

            FileOutputStream(dest).use { out ->
                scaled.compress(Bitmap.CompressFormat.JPEG, 78, out)
                out.flush()
            }
            try {
                scaled.recycle()
            } catch (_: Exception) {
            }
            dest.exists() && dest.length() > 0L
        } catch (e: Exception) {
            android.util.Log.w("PrivateHeart", "videoThumbnail: $e")
            if (dest.exists() && dest.length() == 0L) {
                try {
                    dest.delete()
                } catch (_: Exception) {
                }
            }
            false
        } finally {
            try {
                retriever?.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun scaleDown(src: Bitmap, maxSize: Int): Bitmap {
        val w = src.width
        val h = src.height
        if (w <= 0 || h <= 0) return src
        val longest = maxOf(w, h)
        if (longest <= maxSize) return src
        val scale = maxSize.toFloat() / longest.toFloat()
        val nw = (w * scale).toInt().coerceAtLeast(1)
        val nh = (h * scale).toInt().coerceAtLeast(1)
        return try {
            Bitmap.createScaledBitmap(src, nw, nh, true)
        } catch (_: Exception) {
            src
        }
    }
}
