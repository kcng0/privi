package com.privi.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Registers Flutter channels and owns their executor lifecycle.
 *
 * File, MediaStore, metadata, and thumbnail behavior lives in focused handlers.
 */
class MainActivity : FlutterFragmentActivity() {
    private val ioExecutor = Executors.newFixedThreadPool(3)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var externalPlayer: ExternalPlayerHandler? = null

    private fun <T> runIo(result: MethodChannel.Result, block: () -> T) {
        ioExecutor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("io_error", e.message, null) }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val mediaStore = MediaStoreIndexHandler(this, contentResolver)
        val vaultFiles = VaultFileHandler(this, contentResolver, mediaStore)
        val metadata = MediaMetadataHandler(contentResolver, mediaStore)
        val thumbnails = ThumbnailHandler()
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        externalPlayer = ExternalPlayerHandler(this, messenger, vaultFiles)

        MethodChannel(messenger, "com.privi.app/mediastore")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "removeOriginal" -> {
                        val uri = call.argument<String>("uri")
                        result.success(!uri.isNullOrEmpty() && mediaStore.removeOriginal(uri))
                    }
                    "purgeMediaStorePath" -> {
                        val path = call.argument<String>("path")
                        result.success(
                            !path.isNullOrEmpty() && mediaStore.purgeMediaStoreByPath(path) > 0,
                        )
                    }
                    "scanMediaPath" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.success(false)
                        } else {
                            result.success(
                                mediaStore.scanMediaPath(
                                    path,
                                    call.argument("mimeType"),
                                    call.argument<Number>("dateTakenSec")?.toLong(),
                                    call.argument<Number>("dateAddedSec")?.toLong(),
                                ),
                            )
                        }
                    }
                    "resolveMediaPath" -> {
                        val id = call.argument<String>("id")?.toLongOrNull()
                        val isVideo = call.argument<Boolean>("isVideo") ?: false
                        result.success(
                            if (id == null) null else mediaStore.resolveMediaPathById(id, isVideo),
                        )
                    }
                    "resolveCaptureDate" -> runIo(result) {
                        metadata.resolveCaptureDateSec(
                            call.argument("path"),
                            call.argument<String>("mediaId")?.toLongOrNull(),
                            call.argument<Boolean>("isVideo") ?: false,
                        )
                    }
                    "isExternalStorageManager" -> result.success(isAllFilesAccess())
                    "openManageAllFilesSettings" -> {
                        openAllFilesSettings()
                        result.success(null)
                    }
                    "renameMedia" -> {
                        val path = call.argument<String>("path")
                        val newPath = call.argument<String>("newPath")
                        if (path.isNullOrEmpty() || newPath.isNullOrEmpty()) {
                            result.success(mapOf("ok" to false, "error" to "bad_args"))
                        } else {
                            result.success(
                                vaultFiles.renameMedia(
                                    path,
                                    newPath,
                                    call.argument<Boolean>("isVideo") ?: false,
                                ),
                            )
                        }
                    }
                    "hideToVault" -> {
                        val newPath = call.argument<String>("newPath")
                        if (newPath.isNullOrEmpty()) {
                            result.success(mapOf("ok" to false, "error" to "bad_args"))
                        } else {
                            runIo(result) {
                                vaultFiles.hideToVault(
                                    call.argument("path"),
                                    call.argument<String>("mediaId")?.toLongOrNull(),
                                    newPath,
                                    call.argument<Boolean>("isVideo") ?: false,
                                )
                            }
                        }
                    }
                    "hideToVaultBatch" -> {
                        val items = call.argument<List<*>>("items")
                        if (items.isNullOrEmpty()) {
                            result.success(emptyList<Map<String, Any?>>())
                        } else {
                            runIo(result) { vaultFiles.hideToVaultBatch(items) }
                        }
                    }
                    "unhideFromVault" -> {
                        val path = call.argument<String>("path")
                        val newPath = call.argument<String>("newPath")
                        if (path.isNullOrEmpty() || newPath.isNullOrEmpty()) {
                            result.success(mapOf("ok" to false, "error" to "bad_args"))
                        } else {
                            runIo(result) {
                                vaultFiles.unhideFromVault(
                                    path,
                                    newPath,
                                    call.argument("mimeType"),
                                    call.argument<Number>("dateTakenSec")?.toLong(),
                                    call.argument<Number>("dateAddedSec")?.toLong(),
                                )
                            }
                        }
                    }
                    "unhideFromVaultBatch" -> {
                        val items = call.argument<List<*>>("items")
                        if (items.isNullOrEmpty()) {
                            result.success(emptyList<Map<String, Any?>>())
                        } else {
                            runIo(result) { vaultFiles.unhideFromVaultBatch(items) }
                        }
                    }
                    "videoThumbnail" -> {
                        val path = call.argument<String>("path")
                        val destPath = call.argument<String>("destPath")
                        if (path.isNullOrEmpty() || destPath.isNullOrEmpty()) {
                            result.success(false)
                        } else {
                            runIo(result) {
                                thumbnails.extractVideoThumbnail(
                                    path,
                                    destPath,
                                    call.argument<Int>("maxSize") ?: 256,
                                )
                            }
                        }
                    }
                    "videoFrameAtTime" -> {
                        val path = call.argument<String>("path")
                        val timeUs = call.argument<Number>("timeUs")?.toLong()
                        if (path.isNullOrEmpty() || timeUs == null) {
                            result.success(null)
                        } else {
                            runIo(result) {
                                thumbnails.extractVideoFrame(
                                    path,
                                    timeUs,
                                    call.argument<Int>("maxSize") ?: 220,
                                )
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(messenger, "com.privi.app/window")
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

    override fun onDestroy() {
        externalPlayer?.dispose()
        externalPlayer = null
        ioExecutor.shutdown()
        super.onDestroy()
    }

    private fun isAllFilesAccess(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
            Environment.isExternalStorageManager()
    }

    private fun openAllFilesSettings() {
        try {
            val action = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION
            } else {
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS
            }
            startActivity(Intent(action, Uri.parse("package:$packageName")))
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
    }
}
