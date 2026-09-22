package com.privi.app

import android.content.Intent
import android.net.Uri
import android.media.AudioManager
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
    private var shareHandler: ShareHandler? = null

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
        shareHandler = ShareHandler(this, messenger, mediaStore)

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
                    "getBrightness" -> {
                        val current = window.attributes.screenBrightness
                        result.success(
                            if (current < 0f) systemBrightness() else current.coerceIn(0f, 1f),
                        )
                    }
                    "setBrightness" -> {
                        val value = (call.argument<Number>("value")?.toFloat() ?: 0.5f)
                            .coerceIn(0f, 1f)
                        runOnUiThread { setWindowBrightness(value) }
                        result.success(null)
                    }
                    "resetBrightness" -> {
                        runOnUiThread {
                            setWindowBrightness(WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE)
                        }
                        result.success(null)
                    }
                    "getVolume" -> result.success(mediaVolume())
                    "setVolume" -> {
                        val value = (call.argument<Number>("value")?.toFloat() ?: 0.5f)
                            .coerceIn(0f, 1f)
                        setMediaVolume(value)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        externalPlayer?.dispose()
        externalPlayer = null
        shareHandler?.dispose()
        shareHandler = null
        ioExecutor.shutdown()
        super.onDestroy()
    }

    private fun setWindowBrightness(value: Float) {
        val params = window.attributes
        params.screenBrightness = value
        window.attributes = params
    }

    private fun systemBrightness(): Float {
        return try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS) / 255f
        } catch (_: Exception) {
            0.5f
        }
    }

    private fun audioManager(): AudioManager? {
        return getSystemService(AUDIO_SERVICE) as? AudioManager
    }

    private fun mediaVolume(): Float {
        val audio = audioManager() ?: return 0.5f
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        return audio.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() / max
    }

    private fun setMediaVolume(value: Float) {
        val audio = audioManager() ?: return
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val index = (value * max).toInt().coerceIn(0, max)
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
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
