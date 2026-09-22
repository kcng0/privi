package com.privi.app

import android.content.ClipData
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Opens the system share sheet (`ACTION_SEND` + `createChooser`) without
 * copying files or reusing the last chosen destination.
 */
class ShareHandler(
    private val activity: FlutterFragmentActivity,
    messenger: BinaryMessenger,
    private val mediaStore: MediaStoreIndexHandler,
) {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                SHARE -> {
                    try {
                        result.success(
                            share(call.argument<List<*>>("items").orEmpty()),
                        )
                    } catch (error: Exception) {
                        result.error("share_failed", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun share(rawItems: List<*>): Boolean {
        val uris = ArrayList<Uri>(rawItems.size)
        val mimeTypes = ArrayList<String>(rawItems.size)
        for (entry in rawItems) {
            val map = entry as? Map<*, *> ?: continue
            val uri = resolveUri(map) ?: continue
            uris.add(uri)
            mimeTypes.add(mimeTypeOf(map))
        }
        if (uris.isEmpty()) return false

        val send = Intent().apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            if (uris.size == 1) {
                action = Intent.ACTION_SEND
                type = mimeTypes.first()
                putExtra(Intent.EXTRA_STREAM, uris.first())
            } else {
                action = Intent.ACTION_SEND_MULTIPLE
                type = reduceMimeTypes(mimeTypes)
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            }
            val clip = ClipData.newUri(activity.contentResolver, "media", uris.first())
            for (index in 1 until uris.size) {
                clip.addItem(ClipData.Item(uris[index]))
            }
            clipData = clip
        }

        val chooser = Intent.createChooser(send, null).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                putExtra(
                    Intent.EXTRA_EXCLUDE_COMPONENTS,
                    arrayOf(ComponentName(activity, MainActivity::class.java)),
                )
            }
        }
        activity.startActivity(chooser)
        return true
    }

    private fun resolveUri(map: Map<*, *>): Uri? {
        val uriString = stringArg(map, "uri")
        if (!uriString.isNullOrBlank()) return Uri.parse(uriString)

        val mediaId = mediaIdArg(map)
        if (mediaId != null) {
            val isVideo = map["isVideo"] as? Boolean ?: false
            return mediaStore.contentUriForMediaId(mediaId, isVideo)
        }

        val path = stringArg(map, "path") ?: return null
        val file = File(path)
        if (!file.isFile) return null
        return FileProvider.getUriForFile(
            activity,
            "${activity.applicationContext.packageName}.fileprovider",
            file,
        )
    }

    private fun mimeTypeOf(map: Map<*, *>): String {
        val mime = stringArg(map, "mimeType")
        return if (mime.isNullOrBlank()) "*/*" else mime
    }

    private fun reduceMimeTypes(mimeTypes: List<String>): String {
        if (mimeTypes.isEmpty()) return "*/*"
        if (mimeTypes.size == 1) return mimeTypes.first()
        var common = mimeTypes.first()
        for (index in 1 until mimeTypes.size) {
            if (common == mimeTypes[index]) continue
            common = if (mimeBase(common) == mimeBase(mimeTypes[index])) {
                mimeBase(mimeTypes[index]) + "/*"
            } else {
                return "*/*"
            }
        }
        return common
    }

    private fun mimeBase(mimeType: String): String {
        val separator = mimeType.indexOf('/')
        return if (separator <= 0) "*" else mimeType.substring(0, separator)
    }

    private fun stringArg(map: Map<*, *>, key: String): String? {
        val value = map[key] ?: return null
        val text = value.toString()
        return text.ifBlank { null }
    }

    private fun mediaIdArg(map: Map<*, *>): Long? {
        return when (val value = map["mediaId"]) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull()
            else -> null
        }
    }

    private companion object {
        const val CHANNEL_NAME = "com.privi.app/share"
        const val SHARE = "share"
    }
}
