package com.privi.app

import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import io.flutter.embedding.android.FlutterImageView
import io.flutter.embedding.android.FlutterView
import java.util.IdentityHashMap

/**
 * Explicit debug-only observation of Flutter's hybrid composition pipeline.
 *
 * The pinned engine does not install ImageAvailable listeners on these readers.
 * This observer never acquires an image, invalidates a view, schedules a Flutter
 * frame, or changes a surface. Notifications and window commits are metadata,
 * not proof that a particular Flutter image reached the display.
 */
internal class FlutterCompositionDiagnostics(
    private val flutterView: FlutterView,
    private val handler: Handler,
) {
    private class ReaderRecord(val id: Int, val view: FlutterImageView, val reader: ImageReader) {
        var notifications = 0L
        var lastNotificationNs = 0L
    }

    private val startedNs = SystemClock.elapsedRealtimeNanos()
    private val readers = IdentityHashMap<FlutterImageView, ReaderRecord>()
    private val history = ArrayDeque<Map<String, Any>>()
    private val tree = flutterView.viewTreeObserver
    private var nextReaderId = 1
    private var stopped = false
    private var draws = 0L
    private var lastDrawNs = 0L
    private var commits = 0L
    private var lastCommitNs = 0L
    private var commitPending = false
    private var readerErrors = 0L

    private val committed = Runnable {
        commitPending = false
        if (!stopped) {
            commits++
            lastCommitNs = SystemClock.elapsedRealtimeNanos()
        }
    }
    private val layout = ViewTreeObserver.OnGlobalLayoutListener { refreshReaders() }
    private val draw = ViewTreeObserver.OnDrawListener {
        if (!stopped) {
            draws++
            lastDrawNs = SystemClock.elapsedRealtimeNanos()
        }
    }

    init {
        tree.addOnGlobalLayoutListener(layout)
        tree.addOnDrawListener(draw)
        refreshReaders()
        observeNextCommit()
    }

    private fun record(event: String, id: Int) {
        if (history.size == 64) history.removeFirst()
        history.addLast(mapOf(
            "event" to event,
            "reader-id" to id,
            "elapsed-ns" to SystemClock.elapsedRealtimeNanos(),
        ))
    }

    private fun observeNextCommit() {
        // This registers for the next naturally submitted window frame. It does
        // not request one. Android's contract explicitly permits it to precede
        // actual display, and it says nothing about ImageView.onDraw contents.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !commitPending && tree.isAlive &&
            flutterView.isHardwareAccelerated && !stopped) {
            commitPending = true
            tree.registerFrameCommitCallback(committed)
        }
    }

    private fun releaseReader(value: ReaderRecord) {
        try {
            value.reader.setOnImageAvailableListener(null, null)
        } catch (_: IllegalStateException) {
            // resize/detach can already have closed this reader. This counter
            // diagnoses observation loss; it never changes playback recovery.
            readerErrors++
        }
        record("reader-removed", value.id)
    }

    private fun refreshReaders() {
        if (stopped) return
        val current = ArrayList<FlutterImageView>()
        fun visit(view: View) {
            if (view is FlutterImageView) current.add(view)
            if (view is ViewGroup) {
                for (index in 0 until view.childCount) visit(view.getChildAt(index))
            }
        }
        visit(flutterView)
        val removed = readers.keys.filter { old -> current.none { it === old } }
        removed.forEach { old -> readers.remove(old)?.let(::releaseReader) }
        for (view in current) {
            val reader = view.imageReader
            val previous = readers[view]
            if (previous?.reader === reader) continue
            if (previous != null) releaseReader(previous)
            val value = ReaderRecord(nextReaderId++, view, reader)
            readers[view] = value
            try {
                reader.setOnImageAvailableListener({ notified ->
                    if (stopped || notified !== value.reader || readers[view] !== value) {
                        return@setOnImageAvailableListener
                    }
                    value.notifications++
                    value.lastNotificationNs = SystemClock.elapsedRealtimeNanos()
                    record("image-notification", value.id)
                    observeNextCommit()
                }, handler)
                record("reader-observed", value.id)
            } catch (_: IllegalStateException) {
                readerErrors++
                record("reader-unavailable", value.id)
            }
        }
    }

    fun snapshot(): Map<String, Any> {
        refreshReaders()
        return mapOf(
            "started-elapsed-ns" to startedNs,
            "snapshot-elapsed-ns" to SystemClock.elapsedRealtimeNanos(),
            "root-attached" to flutterView.isAttachedToWindow,
            "root-hardware-accelerated" to flutterView.isHardwareAccelerated,
            "window-tree-draw-count" to draws,
            "last-window-tree-draw-elapsed-ns" to lastDrawNs,
            "observed-window-commit-count" to commits,
            "last-window-commit-elapsed-ns" to lastCommitNs,
            "window-commit-pending" to commitPending,
            "reader-observation-errors" to readerErrors,
            "image-views" to readers.values.sortedBy { it.id }.map { value ->
                val view = value.view
                mapOf(
                    "reader-id" to value.id,
                    "class" to view.javaClass.simpleName,
                    "attached" to view.isAttachedToWindow,
                    "shown" to view.isShown,
                    "visibility" to view.visibility,
                    "window-visibility" to view.windowVisibility,
                    "alpha" to view.alpha.toDouble(),
                    "view-width" to view.width,
                    "view-height" to view.height,
                    "reader-width" to value.reader.width,
                    "reader-height" to value.reader.height,
                    "attached-renderer" to (view.attachedRenderer != null),
                    "image-notification-count" to value.notifications,
                    "last-image-notification-elapsed-ns" to value.lastNotificationNs,
                )
            },
            "recent-events" to history.toList(),
        )
    }

    fun stop() {
        if (stopped) return
        stopped = true
        if (tree.isAlive) {
            tree.removeOnGlobalLayoutListener(layout)
            tree.removeOnDrawListener(draw)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && commitPending) {
                tree.unregisterFrameCommitCallback(committed)
            }
        }
        commitPending = false
        readers.values.forEach(::releaseReader)
        readers.clear()
    }
}
