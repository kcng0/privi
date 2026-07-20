package com.privi.app

import android.content.Intent
import android.media.MediaMetadataRetriever
import android.os.SystemClock
import android.util.Log
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Launches external media activities and reports their actual return to Flutter. */
class ExternalPlayerHandler(
    activity: FlutterFragmentActivity,
    messenger: BinaryMessenger,
    private val vaultFiles: VaultFileHandler,
) {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var activeLaunch: ExternalLaunch? = null
    private val launcher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { activityResult ->
        val launch = activeLaunch
        activeLaunch = null
        channel.invokeMethod(
            EXTERNAL_PLAYER_RETURNED,
            externalReturnArguments(
                activityResult.resultCode,
                activityResult.data,
                launch,
            ),
        )
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                OPEN_EXTERNAL_PLAYER -> openExternalPlayer(
                    call.argument("path"),
                    call.argument<String>("mimeType") ?: "*/*",
                    result,
                )
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        activeLaunch = null
        channel.setMethodCallHandler(null)
    }

    private fun openExternalPlayer(
        path: String?,
        mimeType: String,
        result: MethodChannel.Result,
    ) {
        if (path.isNullOrBlank()) {
            result.error("bad_args", "External player path is required", null)
            return
        }
        try {
            val intent = vaultFiles.createExternalPlayerIntent(path, mimeType)
            if (intent == null) {
                result.success(false)
                return
            }
            val completionSupported = intent.`package` == VLC_PACKAGE
            activeLaunch = ExternalLaunch(
                startedAtElapsedMs = SystemClock.elapsedRealtime(),
                completionSupported = completionSupported,
                expectedDurationMs = if (completionSupported) {
                    readVideoDurationMs(path, mimeType)
                } else {
                    null
                },
            )
            launcher.launch(intent)
            result.success(true)
        } catch (error: Exception) {
            activeLaunch = null
            result.error("external_player_error", error.message, null)
        }
    }

    private fun externalReturnArguments(
        resultCode: Int,
        data: Intent?,
        launch: ExternalLaunch?,
    ): Map<String, Any?> = buildMap {
        put("resultCode", resultCode)
        put("completionSupported", launch?.completionSupported == true)
        if (data?.hasExtra(VLC_EXTRA_POSITION) == true) {
            put("positionMs", data.getLongExtra(VLC_EXTRA_POSITION, -1L))
        }
        if (data?.hasExtra(VLC_EXTRA_DURATION) == true) {
            put("durationMs", data.getLongExtra(VLC_EXTRA_DURATION, -1L))
        }
        launch?.expectedDurationMs?.let { put("expectedDurationMs", it) }
        launch?.let {
            put(
                "elapsedMs",
                (SystemClock.elapsedRealtime() - it.startedAtElapsedMs).coerceAtLeast(0L),
            )
        }
    }

    private fun readVideoDurationMs(path: String, mimeType: String): Long? {
        if (!mimeType.startsWith("video/", ignoreCase = true)) return null
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()
                ?.takeIf { it > 0L }
        } catch (error: Exception) {
            Log.w(TAG, "Could not read external video duration: $path", error)
            null
        } finally {
            retriever.release()
        }
    }

    private data class ExternalLaunch(
        val startedAtElapsedMs: Long,
        val completionSupported: Boolean,
        val expectedDurationMs: Long?,
    )

    private companion object {
        const val TAG = "ExternalPlayerHandler"
        const val CHANNEL_NAME = "com.privi.app/external_player"
        const val OPEN_EXTERNAL_PLAYER = "openExternalPlayer"
        const val EXTERNAL_PLAYER_RETURNED = "external_player_returned"
        const val VLC_EXTRA_POSITION = "extra_position"
        const val VLC_EXTRA_DURATION = "extra_duration"
        const val VLC_PACKAGE = "org.videolan.vlc"
    }
}
