package com.privi.app

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.File
import java.io.FileOutputStream

/** Extracts representative, non-black video poster frames for vault grids. */
class ThumbnailHandler {
    /**
     * Extract a JPEG still from a local video file for vault grid thumbnails.
     * Uses MediaMetadataRetriever — works on vault paths (.nomedia) that MediaStore
     * no longer indexes after hide.
     *
     * Strategy (industry-standard for non-black posters):
     *  - Dynamic % seek: min(2s, 15% duration), then 25%/50% candidates
     *  - Sampled Rec.601 luminance; accept first frame with Y > threshold
     *  - Else keep the brightest candidate (never prefer a pure black intro)
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

        var retriever: MediaMetadataRetriever? = null
        return try {
            retriever = MediaMetadataRetriever()
            retriever.setDataSource(path)

            val durationMs =
                retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull()
                    ?: 0L
            val durationUs = (durationMs * 1000L).coerceAtLeast(0L)

            val candidateTimesUs = buildVideoThumbSeekTimesUs(durationUs)

            var bestFrame: Bitmap? = null
            var bestLuma = -1.0
            // Early-accept threshold (0–255 Rec.601). Below this is likely black/fade.
            val goodLuma = 20.0

            for (timeUs in candidateTimesUs) {
                val frame = decodeFrameAt(retriever, timeUs, maxSize) ?: continue
                val luma = averageLuminance(frame)
                if (luma >= goodLuma) {
                    // Prefer first clearly non-black frame (near-start candidates first).
                    try {
                        bestFrame?.recycle()
                    } catch (_: Exception) {
                    }
                    bestFrame = frame
                    bestLuma = luma
                    break
                }
                if (luma > bestLuma) {
                    try {
                        bestFrame?.recycle()
                    } catch (_: Exception) {
                    }
                    bestFrame = frame
                    bestLuma = luma
                } else {
                    try {
                        frame.recycle()
                    } catch (_: Exception) {
                    }
                }
            }

            var frame = bestFrame
            if (frame == null) {
                frame = try {
                    retriever.frameAtTime
                } catch (_: Exception) {
                    null
                }
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
            android.util.Log.w("Privi", "videoThumbnail: $e")
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

    /**
     * Candidate seek times (µs), ordered near-start → deeper into the clip.
     * Primary: min(2s, 15% duration) — past most fade-ins without going mid-roll.
     */
    private fun buildVideoThumbSeekTimesUs(durationUs: Long): List<Long> {
        if (durationUs <= 0L) {
            return listOf(1_000_000L, 500_000L, 0L)
        }
        val t15 = minOf(2_000_000L, (durationUs * 0.15).toLong())
        val t25 = minOf(3_000_000L, (durationUs * 0.25).toLong())
        val t50 = (durationUs * 0.50).toLong()
        val t10 = minOf(1_500_000L, (durationUs * 0.10).toLong())
        val last = (durationUs - 1_000L).coerceAtLeast(0L)
        return linkedSetOf(t15, t25, t50, t10, 1_000_000L, 0L)
            .map { it.coerceIn(0L, last) }
            .distinct()
            .toList()
    }

    private fun decodeFrameAt(
        retriever: MediaMetadataRetriever,
        timeUs: Long,
        maxSize: Int,
    ): Bitmap? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                retriever.getScaledFrameAtTime(
                    timeUs,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    maxSize,
                    maxSize,
                ) ?: retriever.getFrameAtTime(
                    timeUs,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                )
            } else {
                retriever.getFrameAtTime(
                    timeUs,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                )
            }
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Average Rec.601 luma on a coarse grid (~100 samples) — cheap black-frame detect.
     * Y = 0.299R + 0.587G + 0.114B, range 0–255.
     */
    private fun averageLuminance(bitmap: Bitmap): Double {
        val width = bitmap.width
        val height = bitmap.height
        if (width <= 0 || height <= 0) return 0.0

        var total = 0.0
        var samples = 0
        val stepX = (width / 10).coerceAtLeast(1)
        val stepY = (height / 10).coerceAtLeast(1)

        var x = 0
        while (x < width) {
            var y = 0
            while (y < height) {
                val pixel = bitmap.getPixel(x, y)
                val r = (pixel shr 16) and 0xFF
                val g = (pixel shr 8) and 0xFF
                val b = pixel and 0xFF
                total += (0.299 * r) + (0.587 * g) + (0.114 * b)
                samples++
                y += stepY
            }
            x += stepX
        }
        return if (samples > 0) total / samples else 0.0
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
