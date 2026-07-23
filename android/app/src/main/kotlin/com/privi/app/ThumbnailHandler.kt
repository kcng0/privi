package com.privi.app

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.os.Build
import android.util.Size
import java.io.File
import java.io.ByteArrayOutputStream
import java.io.FileOutputStream

/** Extracts video poster frames using the same platform API as the system gallery. */
class ThumbnailHandler {
    fun extractVideoFrame(path: String, timeUs: Long, maxSize: Int): ByteArray? {
        val src = File(path)
        if (!src.exists() || src.length() <= 0L) return null
        var retriever: MediaMetadataRetriever? = null
        return try {
            retriever = MediaMetadataRetriever()
            retriever.setDataSource(path)
            val frame = retriever.getFrameAtTime(
                timeUs,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            ) ?: return null
            val scaled = scaleDown(frame, maxSize.coerceAtLeast(1))
            val output = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 78, output)
            if (scaled !== frame) scaled.recycle()
            frame.recycle()
            output.toByteArray()
        } catch (e: Exception) {
            android.util.Log.w("Privi", "videoFrameAtTime: $e")
            null
        } finally {
            try { retriever?.release() } catch (_: Exception) {}
        }
    }
    /**
     * Extract a JPEG still from a local video file for vault grid thumbnails.
     *
     * Defers frame selection to the platform so the poster matches the built-in
     * system gallery/media browser (representative frame, or the video's embedded
     * thumbnail) instead of a custom seek heuristic:
     *  - API 29+: `ThumbnailUtils.createVideoThumbnail(File, Size, null)`
     *  - API 26–28: `MediaMetadataRetriever.getFrameAtTime()` (representative frame)
     *
     * Works on vault paths (.nomedia) that MediaStore no longer indexes after hide.
     */
    fun extractVideoThumbnail(path: String, destPath: String, maxSize: Int): Boolean {
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

        return try {
            val frame = decodeRepresentativeFrame(path, src, maxSize) ?: return false
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
            android.util.Log.w("Privi", "videoThumbnail: $e")
            if (dest.exists() && dest.length() == 0L) {
                try {
                    dest.delete()
                } catch (_: Exception) {
                }
            }
            false
        }
    }

    /**
     * The platform's representative frame — identical to what the system gallery
     * generates. `ThumbnailUtils.createVideoThumbnail` also prefers an embedded
     * thumbnail when the container has one.
     */
    private fun decodeRepresentativeFrame(path: String, src: File, maxSize: Int): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return try {
                ThumbnailUtils.createVideoThumbnail(src, Size(maxSize, maxSize), null)
            } catch (e: Exception) {
                android.util.Log.w("Privi", "createVideoThumbnail: $e")
                null
            }
        }
        var retriever: MediaMetadataRetriever? = null
        return try {
            retriever = MediaMetadataRetriever()
            retriever.setDataSource(path)
            // No-arg getFrameAtTime() — the representative frame the system uses.
            retriever.frameAtTime
        } catch (_: Exception) {
            null
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
