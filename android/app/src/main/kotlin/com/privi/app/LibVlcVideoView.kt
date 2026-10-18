package com.privi.app

import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.plugin.platform.PlatformView
import org.videolan.libvlc.util.VLCVideoLayout

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
    private val surfaces = LinkedHashSet<SurfaceView>()
    private val destroyedHolders = HashSet<SurfaceHolder>()
    private val surfaceCallback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) {
            destroyedHolders.remove(holder)
            host.viewSurfacesChanged(this@LibVlcVideoView)
        }

        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            host.viewSurfacesChanged(this@LibVlcVideoView)
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) {
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
        if (!visible) root.keepScreenOn = false
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
        val subtitle = surfaces.firstOrNull { surface ->
            surface.id != View.NO_ID && layout.resources.getResourceEntryName(surface.id) == "surface_subtitles"
        }
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
