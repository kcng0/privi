package com.privi.app

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
    private val launcher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) {
        channel.invokeMethod(INTENT_RETURNED_CLEANLY, null)
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
            launcher.launch(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("external_player_error", error.message, null)
        }
    }

    private companion object {
        const val CHANNEL_NAME = "com.privi.app/external_player"
        const val OPEN_EXTERNAL_PLAYER = "openExternalPlayer"
        const val INTENT_RETURNED_CLEANLY = "intent_returned_cleanly"
    }
}
