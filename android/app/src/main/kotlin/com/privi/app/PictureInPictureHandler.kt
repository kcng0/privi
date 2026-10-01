package com.privi.app

import android.app.Activity
import android.app.KeyguardManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.os.Build
import android.os.PowerManager
import android.util.Rational
import android.util.Log
import android.view.View
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Explicit button-only PiP on the existing Flutter activity/engine. */
class PictureInPictureHandler(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "com.privi.app/pip")
    private val actionName = "${activity.packageName}.PIP_PLAYBACK"
    private var sessionId = 0
    private var authorized = false
    private var resumed = false
    private var exitAcknowledged = false
    private var playing = false
    private var aspect = Rational(16, 9)
    private var sourceRect: Rect? = null
    private var shield: View? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == Intent.ACTION_SCREEN_OFF) {
                if (authorized || inPip()) revokeAndNotify("screenOff")
                return
            }
            if (intent.action != actionName || !authorized || !inPip() ||
                intent.getIntExtra("sessionId", -1) != sessionId) return
            if (!screenAvailable()) {
                revokeAndNotify("screenOff")
                return
            }
            emit(if (intent.getBooleanExtra("play", false)) "play" else "pause")
        }
    }

    init {
        ContextCompat.registerReceiver(
            activity, receiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(actionName)
            },
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isSupported" -> result.success(supported())
                    "enter" -> enter(call, result)
                    "setPlaying" -> {
                        if (matches(call) && authorized) {
                            playing = call.argument<Boolean>("isPlaying") ?: false
                            updateParams()
                        }
                        result.success(null)
                    }
                    "revoke" -> {
                        if (matches(call)) {
                            authorized = false
                            exitAcknowledged = false
                            cover()
                            clearActionsAfterRevocation()
                        }
                        result.success(inPip())
                    }
                    "acknowledgeExit" -> {
                        if (matches(call)) {
                            exitAcknowledged = true
                            uncoverIfSafe()
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                authorized = false
                cover()
                if (sessionId != 0) emit("stopped")
                result.error("pip_native_error", error.message, null)
            }
        }
    }

    private fun supported() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun inPip() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
        activity.isInPictureInPictureMode

    private fun screenAvailable(): Boolean {
        val power = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return power.isInteractive && !keyguard.isKeyguardLocked
    }

    private fun matches(call: MethodCall) = call.argument<Int>("sessionId") == sessionId

    private fun enter(call: MethodCall, result: MethodChannel.Result) {
        if (!supported() || !resumed || !screenAvailable() || inPip()) {
            result.error("pip_unavailable", "PiP requires a visible, unlocked device", null)
            return
        }
        sessionId = call.argument<Int>("sessionId")
            ?: throw IllegalArgumentException("Missing PiP session")
        val ratio = call.argument<Number>("aspectRatio")?.toDouble() ?: 16.0 / 9.0
        require(ratio.isFinite() && ratio > 0) { "Invalid PiP aspect ratio" }
        // Android's supported interval is [1/2.39, 2.39]. Keep rounding inside it.
        aspect = Rational((ratio.coerceIn(1.0 / 2.39, 2.39) * 10000).toInt()
            .coerceIn(4185, 23900), 10000)
        val rect = call.argument<Map<String, Number>>("sourceRect")
        sourceRect = rect?.let {
            Rect(it["left"]!!.toInt(), it["top"]!!.toInt(),
                it["right"]!!.toInt(), it["bottom"]!!.toInt())
        }?.takeUnless { it.isEmpty }
        authorized = true
        exitAcknowledged = false
        playing = call.argument<Boolean>("isPlaying") ?: false
        val entered = activity.enterPictureInPictureMode(params())
        if (!entered) {
            authorized = false
            cover()
        }
        result.success(entered)
    }

    private fun params(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(aspect)
        sourceRect?.let { builder.setSourceRectHint(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(false)
        }
        if (authorized) {
            val intent = Intent(actionName).setPackage(activity.packageName)
                .putExtra("sessionId", sessionId).putExtra("play", !playing)
            val pending = PendingIntent.getBroadcast(
                activity, sessionId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val icon = if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
            val label = activity.getString(if (playing) R.string.pip_pause else R.string.pip_play)
            builder.setActions(listOf(RemoteAction(
                Icon.createWithResource(activity, icon), label, label, pending,
            )))
        } else {
            builder.setActions(emptyList())
        }
        return builder.build()
    }

    private fun updateParams() {
        if (supported()) activity.setPictureInPictureParams(params())
    }

    private fun clearActionsAfterRevocation() {
        try {
            updateParams()
        } catch (error: RuntimeException) {
            // The grant is already revoked and the cover is already installed.
            // A cached system action is harmless: the receiver rejects it. Do
            // not prevent the lock-frame handshake if Android rejects cleanup.
            Log.e("PriviPiP", "Could not clear revoked PiP actions", error)
        }
    }

    fun onModeChanged(active: Boolean) {
        if (active) {
            if (authorized && screenAvailable()) {
                emit("active")
            } else {
                revokeAndNotify("stopped")
            }
        } else if (sessionId != 0) {
            revokeAndNotify("exited")
        }
    }

    fun onResume() {
        resumed = true
        if (sessionId != 0 && !inPip()) {
            // onResume can precede onPictureInPictureModeChanged(false).
            revokeAndNotify("exited")
        }
        uncoverIfSafe()
    }

    fun onPause() {
        resumed = false
        if (authorized && !screenAvailable()) revokeAndNotify("screenOff")
    }

    fun onStop() {
        resumed = false
        if (authorized || inPip()) revokeAndNotify("stopped")
    }

    private fun revokeAndNotify(type: String) {
        authorized = false
        exitAcknowledged = false
        // Synchronous native cover precedes every Dart callback and survives
        // isolate suspension. FLAG_SECURE is deliberately untouched.
        cover()
        clearActionsAfterRevocation()
        emit(type)
    }

    private fun emit(type: String) {
        channel.invokeMethod("event", mapOf("type" to type, "sessionId" to sessionId))
    }

    private fun cover() {
        if (shield != null) return
        val root = activity.findViewById<ViewGroup>(android.R.id.content)
        shield = View(activity).apply {
            setBackgroundColor(Color.BLACK)
            isClickable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            root.addView(this, ViewGroup.LayoutParams(-1, -1))
        }
    }

    private fun uncoverIfSafe() {
        if (!exitAcknowledged || authorized || !resumed || inPip() || !screenAvailable()) return
        shield?.let { (it.parent as? ViewGroup)?.removeView(it) }
        shield = null
        sessionId = 0
    }

    fun dispose() {
        activity.unregisterReceiver(receiver)
        channel.setMethodCallHandler(null)
        shield?.let { (it.parent as? ViewGroup)?.removeView(it) }
        shield = null
    }
}
