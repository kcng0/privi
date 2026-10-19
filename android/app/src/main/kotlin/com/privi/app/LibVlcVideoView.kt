package com.privi.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.plugin.platform.PlatformView
import org.videolan.libvlc.util.VLCVideoLayout
import java.util.zip.CRC32

/** One clipped native viewport. The host decides which viewport owns a player. */
internal class LibVlcVideoView(
    context: Context,
    val platformViewId: Int,
    val playerId: Int,
    var fitMode: String,
    private val host: LibVlcPlayerHost,
) : PlatformView {
    val layout = VLCVideoLayout(context).apply {
        clipChildren = true
        clipToPadding = true
    }
    private var disposed = false
    private var windowAttached = false
    private var subtitleSnapshotEpoch = 0L
    private var subtitlePixelCopyPending = false
    private val surfaces = LinkedHashSet<SurfaceView>()
    private val destroyedHolders = HashSet<SurfaceHolder>()
    private val surfaceCallback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) {
            subtitleSnapshotEpoch++
            destroyedHolders.remove(holder)
            host.viewSurfacesChanged(this@LibVlcVideoView)
        }

        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            subtitleSnapshotEpoch++
            host.viewSurfacesChanged(this@LibVlcVideoView)
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) {
            subtitleSnapshotEpoch++
            // Surface.isValid can remain true until surfaceDestroyed returns.
            destroyedHolders.add(holder)
            host.viewSurfacesChanged(this@LibVlcVideoView)
        }
    }
    private val root = object : FrameLayout(context) {
        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            windowAttached = true
            host.viewAttached(this@LibVlcVideoView)
        }

        override fun onDetachedFromWindow() {
            windowAttached = false
            host.viewDetached(this@LibVlcVideoView)
            super.onDetachedFromWindow()
        }

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            clipBounds = Rect(0, 0, w, h)
            host.viewResized(this@LibVlcVideoView)
        }

        override fun onVisibilityAggregated(isVisible: Boolean) {
            super.onVisibilityAggregated(isVisible)
            host.viewVisibilityChanged(this@LibVlcVideoView)
        }

        override fun onWindowVisibilityChanged(visibility: Int) {
            super.onWindowVisibilityChanged(visibility)
            host.viewVisibilityChanged(this@LibVlcVideoView)
        }
    }.apply {
        setBackgroundColor(Color.BLACK)
        clipChildren = true
        clipToPadding = true
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
        addView(layout, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
        ))
    }

    val attached: Boolean get() = !disposed && windowAttached && root.isAttachedToWindow
    val windowVisible: Boolean get() = attached && root.windowVisibility == View.VISIBLE
    val presentable: Boolean get() = windowVisible && root.isShown
    val surfacesAvailable: Boolean get() = surfaces.isNotEmpty() && surfaces.all {
        it.holder !in destroyedHolders && it.holder.surface.isValid
    }

    override fun getView(): View = root

    /** Hide the SurfaceViews themselves, not just Flutter or an opaque sibling. */
    fun setPresentationVisible(visible: Boolean) {
        if (!visible) {
            subtitleSnapshotEpoch++
            root.keepScreenOn = false
        }
        val visibility = if (visible) View.VISIBLE else View.INVISIBLE
        visitSurfaces(layout) { it.visibility = visibility }
        layout.visibility = visibility
    }

    fun setPlaybackAwake(awake: Boolean) {
        root.keepScreenOn = awake
    }

    fun configureSurfaces() {
        // Keep SDK ordering: video uses the default below-window SurfaceView;
        // subtitles use setZOrderMediaOverlay(true), also below the window.
        // Calling setZOrderOnTop(false) here would reset subtitle ordering.
        clipGroups(layout)
        visitSurfaces(layout) { surface ->
            if (surfaces.add(surface)) surface.holder.addCallback(surfaceCallback)
        }
    }

    /** Snapshot on the main thread; do not change layout or Surface ordering. */
    internal fun subtitleDiagnostics(): Map<String, String> {
        // SDK 3.7.7 VideoHelper inflates this id from vlc_video_layout. Resolve
        // its resource name without relying on library R's generated integer.
        val subtitle = subtitleSurface()
        val result = linkedMapOf(
            "subtitle-surface-view-id" to platformViewId.toString(),
            "subtitle-surface-present" to (subtitle != null).toString(),
        )
        if (subtitle != null) {
            result["subtitle-surface-width"] = subtitle.width.toString()
            result["subtitle-surface-height"] = subtitle.height.toString()
            result["subtitle-surface-visibility"] = when (subtitle.visibility) {
                View.VISIBLE -> "visible"
                View.INVISIBLE -> "invisible"
                View.GONE -> "gone"
                else -> subtitle.visibility.toString()
            }
            result["subtitle-surface-shown"] = subtitle.isShown.toString()
            result["subtitle-surface-attached"] = subtitle.isAttachedToWindow.toString()
            result["subtitle-surface-holder-valid"] = subtitle.holder.surface.isValid.toString()
            result["subtitle-surface-holder-destroyed"] = (subtitle.holder in destroyedHolders).toString()
            result["subtitle-surface-buffer-width"] = subtitle.holder.surfaceFrame.width().toString()
            result["subtitle-surface-buffer-height"] = subtitle.holder.surfaceFrame.height().toString()
        }
        return result
    }

    private fun subtitleSurface(): SurfaceView? = surfaces.firstOrNull { surface ->
        surface.id != View.NO_ID && layout.resources.getResourceEntryName(surface.id) == "surface_subtitles"
    }

    /** Inspect the latest queued subtitle buffer without drawing, seeking, or changing surfaces. */
    internal fun readSubtitleSurfacePixels(
        authorized: () -> Boolean,
        onResult: (Map<String, String>) -> Unit,
        onError: (String, String) -> Unit,
    ) {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            onError("subtitle_probe_unsupported", "Subtitle pixel probing requires Android API 24")
            return
        }
        val subtitle = subtitleSurface()
        val epoch = subtitleSnapshotEpoch
        fun current(): Boolean = authorized() && !disposed && presentable &&
            subtitleSnapshotEpoch == epoch && subtitle != null && subtitleSurface() === subtitle &&
            subtitle.isAttachedToWindow && subtitle.isShown &&
            subtitle.holder !in destroyedHolders && subtitle.holder.surface.isValid
        if (!current() || subtitle == null) {
            onError("subtitle_probe_unavailable", "The current subtitle surface cannot be inspected")
            return
        }
        if (subtitlePixelCopyPending) {
            onError("subtitle_probe_unavailable", "A subtitle buffer copy is already pending")
            return
        }
        val width = subtitle.holder.surfaceFrame.width()
        val height = subtitle.holder.surfaceFrame.height()
        if (width <= 0 || height <= 0) {
            onError("subtitle_probe_unavailable", "The subtitle surface has no buffer dimensions")
            return
        }
        val bitmap = try {
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        } catch (error: OutOfMemoryError) {
            onError("subtitle_probe_failed", "The subtitle buffer copy could not allocate a bitmap")
            return
        } catch (error: Exception) {
            onError("subtitle_probe_failed", "The subtitle buffer copy could not allocate a bitmap (${error.javaClass.simpleName})")
            return
        }
        val handler = Handler(Looper.getMainLooper())
        var answered = false
        val timeout = Runnable {
            if (!answered) {
                answered = true
                onError("subtitle_probe_timeout", "The subtitle buffer copy did not finish within 3 seconds")
            }
            // PixelCopy owns the destination until its callback, including after
            // our response deadline. Recycle there rather than racing its writer.
        }
        subtitlePixelCopyPending = true
        handler.postDelayed(timeout, 3_000L)
        try {
            PixelCopy.request(subtitle, bitmap, { status ->
                subtitlePixelCopyPending = false
                handler.removeCallbacks(timeout)
                try {
                    if (answered) return@request
                    answered = true
                    if (!current() || subtitle.holder.surfaceFrame.width() != width ||
                        subtitle.holder.surfaceFrame.height() != height) {
                        onError("subtitle_probe_unavailable", "Subtitle presentation changed during the buffer copy")
                        return@request
                    }
                    val metadata = linkedMapOf(
                        "result" to when (status) {
                            PixelCopy.SUCCESS -> "success"
                            PixelCopy.ERROR_SOURCE_NO_DATA -> "error-source-no-data"
                            PixelCopy.ERROR_SOURCE_INVALID -> "error-source-invalid"
                            PixelCopy.ERROR_TIMEOUT -> "error-timeout"
                            PixelCopy.ERROR_DESTINATION_INVALID -> "error-destination-invalid"
                            else -> "error-unknown"
                        },
                        "width" to width.toString(), "height" to height.toString(),
                    )
                    if (status == PixelCopy.SUCCESS) {
                        try {
                            metadata.putAll(subtitlePixelMetadata(bitmap))
                        } catch (error: Exception) {
                            onError("subtitle_probe_failed", "The subtitle buffer could not be inspected (${error.javaClass.simpleName})")
                            return@request
                        } catch (error: OutOfMemoryError) {
                            onError("subtitle_probe_failed", "The subtitle buffer metadata could not be allocated")
                            return@request
                        }
                    }
                    onResult(metadata)
                } finally {
                    bitmap.recycle()
                }
            }, handler)
        } catch (error: Exception) {
            subtitlePixelCopyPending = false
            handler.removeCallbacks(timeout)
            answered = true
            bitmap.recycle()
            onError("subtitle_probe_failed", "The subtitle buffer copy could not start (${error.javaClass.simpleName})")
        }
    }

    private fun subtitlePixelMetadata(bitmap: Bitmap): Map<String, String> {
        val row = IntArray(bitmap.width)
        val bytes = ByteArray(bitmap.width * 4)
        val crc = CRC32()
        var count = 0L
        var left = bitmap.width
        var top = bitmap.height
        var right = -1
        var bottom = -1
        for (y in 0 until bitmap.height) {
            bitmap.getPixels(row, 0, row.size, 0, y, row.size, 1)
            for (x in row.indices) {
                val pixel = row[x]
                if (pixel ushr 24 != 0) {
                    count++
                    left = minOf(left, x)
                    top = minOf(top, y)
                    right = maxOf(right, x + 1)
                    bottom = maxOf(bottom, y + 1)
                }
                // Define CRC byte order independently of the device's endianness.
                for (index in 0..3) bytes[x * 4 + index] = (pixel ushr (24 - index * 8)).toByte()
            }
            crc.update(bytes)
        }
        return mapOf(
            "nonTransparentPixels" to count.toString(),
            "left" to (if (count == 0L) -1 else left).toString(),
            "top" to (if (count == 0L) -1 else top).toString(),
            "right" to right.toString(), "bottom" to bottom.toString(),
            "crc32" to java.lang.Long.toHexString(crc.value).padStart(8, '0'),
        )
    }

    private fun clipGroups(group: ViewGroup) {
        group.clipChildren = true
        group.clipToPadding = true
        for (index in 0 until group.childCount) {
            (group.getChildAt(index) as? ViewGroup)?.let(::clipGroups)
        }
    }

    private fun visitSurfaces(group: ViewGroup, action: (SurfaceView) -> Unit) {
        for (index in 0 until group.childCount) {
            when (val child = group.getChildAt(index)) {
                is SurfaceView -> action(child)
                is ViewGroup -> visitSurfaces(child, action)
            }
        }
    }

    override fun dispose() {
        if (disposed) return
        disposed = true
        root.keepScreenOn = false
        surfaces.forEach { it.holder.removeCallback(surfaceCallback) }
        surfaces.clear()
        destroyedHolders.clear()
        setPresentationVisible(false)
        host.viewDisposed(this)
    }
}
