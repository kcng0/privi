package com.privi.app

import android.app.Activity
import android.content.pm.ActivityInfo
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Restores the actual pre-playback request, including UNSPECIFIED. */
class OrientationHandler(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "com.privi.app/orientation")
    private var previousOrientation: Int? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "begin" -> {
                    if (previousOrientation == null) {
                        previousOrientation = activity.requestedOrientation
                    }
                    result.success(null)
                }
                "setMode" -> {
                    val orientation = when (call.argument<String>("mode")) {
                        "auto" -> ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
                        "portrait" -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                        "reversePortrait" -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT
                        "landscape" -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                        "reverseLandscape" -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                        "sensorLandscape" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                        "sensorPortrait" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
                        else -> null
                    }
                    if (orientation == null) {
                        result.error("invalid_orientation", "Unknown playback orientation", null)
                    } else {
                        if (previousOrientation == null) {
                            previousOrientation = activity.requestedOrientation
                        }
                        // API 36 large-screen policy may ignore the request. Respect
                        // that result; do not retry or force activity recreation.
                        activity.requestedOrientation = orientation
                        result.success(null)
                    }
                }
                "restore" -> {
                    restore()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun restore() {
        previousOrientation?.let { activity.requestedOrientation = it }
        previousOrientation = null
    }

    fun dispose() {
        restore()
        channel.setMethodCallHandler(null)
    }
}
