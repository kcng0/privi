package com.privi.app

import android.content.Context
import android.graphics.Color
import android.graphics.Rect
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
    private val root = object : FrameLayout(context) {
        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            host.viewAttached(this@LibVlcVideoView)
        }

        override fun onDetachedFromWindow() {
            host.viewDetached(this@LibVlcVideoView)
            super.onDetachedFromWindow()
        }

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            clipBounds = Rect(0, 0, w, h)
            host.viewResized(this@LibVlcVideoView)
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

    val attached: Boolean get() = !disposed && root.isAttachedToWindow

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
        setPresentationVisible(false)
        host.viewDisposed(this)
    }
}
