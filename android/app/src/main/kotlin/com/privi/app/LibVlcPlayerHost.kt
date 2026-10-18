package com.privi.app

import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.platform.PlatformViewRegistry
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.interfaces.IMedia
import org.videolan.libvlc.interfaces.IVLCVout
import org.videolan.libvlc.util.VLCUtil
import java.io.Closeable
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Owns media parsing, native playback, and presentation permission separately.
 * A parsed/preloaded item owns no decoder. Playback starts only with a live
 * SurfaceView and an explicit presentation grant. All Android view work stays
 * on the main thread; potentially blocking native stop/release runs serially.
 */
class LibVlcPlayerHost(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
    private val assetLookup: (String, String?) -> String,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "com.privi.app/libvlc"
        const val VIEW_TYPE = "com.privi.app/libvlc/view"
        private const val PARSE_TIMEOUT_MS = 20_000
        private const val OPEN_TIMEOUT_MS = 25_000L
        private const val ENGINE_PREPARATION_TIMEOUT_MS = 60_000L
        private const val INITIALIZATION_QUEUE_TIMEOUT_MS = 25_000L
        private const val SURFACE_FRAME_TIMEOUT_MS = 5_000L
        private const val TAG = "PriviLibVlc"

        private val scaleTypes = mapOf(
            "bestFit" to MediaPlayer.ScaleType.SURFACE_BEST_FIT,
            "fitScreen" to MediaPlayer.ScaleType.SURFACE_FIT_SCREEN,
            "fill" to MediaPlayer.ScaleType.SURFACE_FILL,
            "original" to MediaPlayer.ScaleType.SURFACE_ORIGINAL,
            "ratio16x9" to MediaPlayer.ScaleType.SURFACE_16_9,
            "ratio4x3" to MediaPlayer.ScaleType.SURFACE_4_3,
            "ratio16x10" to MediaPlayer.ScaleType.SURFACE_16_10,
            "ratio2x1" to MediaPlayer.ScaleType.SURFACE_2_1,
            "ratio221x1" to MediaPlayer.ScaleType.SURFACE_221_1,
            "ratio235x1" to MediaPlayer.ScaleType.SURFACE_235_1,
            "ratio239x1" to MediaPlayer.ScaleType.SURFACE_239_1,
            "ratio5x4" to MediaPlayer.ScaleType.SURFACE_5_4,
        )
    }

    private data class Failure(val code: String, val message: String)

    private class PlaybackStart(val generation: Long)

    private class NativeOperation(val playerId: Int?, @Volatile var stage: String) {
        val startedAt = SystemClock.elapsedRealtime()
    }

    private class Disposal {
        val results = mutableListOf<MethodChannel.Result>()
        var releaseFinished = false
        var failure: Failure? = null
    }

    private class SourceCleanupException(val stage: String, cause: Exception) : Exception(cause)

    private data class MediaRequest(val uri: String, val packageName: String?, val headers: Map<*, *>?)

    private class EnginePreparation {
        val queuedAt = SystemClock.elapsedRealtime()
        @Volatile var startedAt: Long? = null
        @Volatile var cancelled = false
        var finishedAt: Long? = null
        var timeout: Runnable? = null
        var queueTimeout: Runnable? = null
    }

    private class Source(
        val media: Media,
        val descriptor: Closeable? = null,
        val temporaryFile: File? = null,
    ) {
        fun release(stage: (String) -> Unit) {
            var failure: Exception? = null
            fun attempt(name: String, action: () -> Unit) {
                stage(name)
                try { action() } catch (error: Exception) {
                    val cleanupError = SourceCleanupException(name, error)
                    if (failure == null) failure = cleanupError else failure.addSuppressed(cleanupError)
                }
            }
            attempt("release-media") { media.release() }
            attempt("release-descriptor") { descriptor?.close() }
            attempt("release-temporary-asset") {
                temporaryFile?.let { check(!it.exists() || it.delete()) { "Temporary asset cleanup failed" } }
            }
            failure?.let { throw it }
        }
    }

    private inner class Entry(val id: Int) : EventChannel.StreamHandler {
        val eventChannel = EventChannel(messenger, "$CHANNEL/events/$id")
        var sink: EventChannel.EventSink? = null
        var source: Source? = null
        var player: MediaPlayer? = null
        var initialized: Map<String, Any?>? = null
        @Volatile var failure: Failure? = null
        var duration = 0L
        var width = 0.0
        var height = 0.0
        var tracks = emptyList<IMedia.Track>()
        val views = LinkedHashSet<LibVlcVideoView>()
        var activeView: LibVlcVideoView? = null
        var attachedView: LibVlcVideoView? = null
        @Volatile var surfacesReady = false
        var voutReady = false
        @Volatile var viewportAttached = false
        @Volatile var surfaceGeneration = 0L
        @Volatile var playbackStart: PlaybackStart? = null
        var mediaOpenPending = false
        var disposal: Disposal? = null
        var cleanupFailure: Failure? = null
        var surfaceSuspended = false
        var surfaceRecovery: Runnable? = null
        var surfaceLossCount = 0L
        var surfaceAttachCount = 0L
        var rateRequestCount = 0L
        var inputReopenCount = 0L
        var frameRequestView: LibVlcVideoView? = null
        var frameRequestGeneration: Long? = null
        var lastFrameRequestView: LibVlcVideoView? = null
        var lastFrameRequestGeneration: Long? = null
        var frameRequestTimeout: Runnable? = null
        var frameRequestTimeoutCount = 0L
        @Volatile var disposed = false
        @Volatile var allowed = false
        @Volatile var wantsPlay = false
        var playing = false
        var buffering = false
        var nativeBuffering = false
        var looping = false
        // Native EndReached must survive facade seekTo(0) until a fresh input is opened.
        @Volatile var nativeEnded = false
        var inputRestarting = false
        var mixWithOthers = false
        var preventsDisplaySleep = true
        var volume = 1.0
        var speed = 1.0
        var pendingPosition: Long? = null
        var audioDelay = 0L
        var subtitleDelay = 0L
        var selectedAudioTrack: Int? = null
        var selectedSubtitleTrack: Int? = null
        // Owned by nativeQueue and removed after queued import operations settle.
        val subtitleFiles = mutableListOf<File>()
        var abStart: Long? = null
        var abEnd: Long? = null
        var abSeeking = false
        var abSeekCount = 0L
        var openTimeout: Runnable? = null
        var queueTimeout: Runnable? = null
        var initializationStage = "waiting-engine"
        var initializationQueuedAt: Long? = null
        @Volatile var initializationStartedAt: Long? = null
        var initializationFinishedAt: Long? = null
        var playerTimeout: Runnable? = null
        var focusRequest: AudioFocusRequest? = null
        var focusListener: AudioManager.OnAudioFocusChangeListener? = null
        val voutCallback = object : IVLCVout.Callback {
            override fun onSurfacesCreated(vlcVout: IVLCVout) {
                if (disposed) return
                val view = attachedView ?: return
                if (view !== activeView) return
                voutReady = true
                updateSurfaceReadiness(this@Entry, view)
                if (!surfacesReady) requestSurfaceFrame(this@Entry, view)
                maybePlay(this@Entry)
            }

            override fun onSurfacesDestroyed(vlcVout: IVLCVout) {
                if (disposed) return
                voutReady = false
                val view = attachedView
                suspendForSurfaceLoss(this@Entry)
                if (view != null) scheduleSurfaceRecovery(this@Entry, view)
            }
        }

        init {
            eventChannel.setStreamHandler(this)
        }

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            if (disposed) return
            sink = events
            initialized?.let(events::success)
            failure?.let { events.error(it.code, it.message, null) }
            emitAdvanced(this)
            emit(this, mapOf("event" to "isPlayingStateUpdate", "isPlaying" to playing))
            frameRequestView?.let { view ->
                frameRequestGeneration?.let { generation -> emitSurfaceFrameRequest(this, view, generation, true) }
            }
        }

        override fun onCancel(arguments: Any?) {
            sink = null
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val nativeQueue = Executors.newSingleThreadExecutor { task ->
        Thread(task, "PriviLibVlc").apply { isDaemon = true }
    }
    private val channel = MethodChannel(messenger, CHANNEL)
    private val entries = LinkedHashMap<Int, Entry>()
    private val pendingDisposals = LinkedHashMap<Int, Entry>()
    private val disposalFailures = LinkedHashMap<Int, Failure>()
    @Volatile private var activeNativeOperation: NativeOperation? = null
    private var nextId = 1
    private var pendingCreations = 0
    private val engineWaiters = LinkedHashMap<Entry, MediaRequest>()
    private var enginePreparation: EnginePreparation? = null
    private var preparingEngine = false
    @Volatile private var enginePreparationStage = "idle"
    @Volatile private var enginePreparationFailure: Failure? = null
    private var queueShutdown = false
    @Volatile private var closed = false
    // Created and finally released on nativeQueue.
    private var libVlc: LibVLC? = null
    private var subtitleFonts: File? = null
    @Volatile private var fontCacheValid: Boolean? = null
    @Volatile private var fontCacheBuildMs: Long? = null
    private val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var focusOwner: Entry? = null
    private val screenOffReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF) revokePresentation()
        }
    }
    val viewFactory: PlatformViewFactory = object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val parameters = args as? Map<*, *> ?: throw IllegalArgumentException("Missing player parameters")
            val id = (parameters["id"] as? Number)?.toInt()
                ?: throw IllegalArgumentException("Missing player id")
            val fitMode = parameters["fitMode"] as? String ?: "bestFit"
            require(scaleTypes.containsKey(fitMode)) { "Unknown video fit mode" }
            require(entries.containsKey(id)) { "Unknown LibVLC player id" }
            return LibVlcVideoView(context, viewId, id, fitMode, this@LibVlcPlayerHost).also {
                entries[id]?.views?.add(it)
                it.setPresentationVisible(false)
            }
        }
    }

    init {
        channel.setMethodCallHandler(this)
        activity.registerReceiver(screenOffReceiver, IntentFilter(Intent.ACTION_SCREEN_OFF))
    }

    fun registerViewFactory(registry: PlatformViewRegistry) {
        check(registry.registerViewFactory(VIEW_TYPE, viewFactory)) { "LibVLC view factory already registered" }
    }

    /** One observable operation owns the serial worker until its SDK call returns. */
    private fun queueNative(playerId: Int?, stage: String, action: () -> Unit) {
        nativeQueue.execute {
            val operation = NativeOperation(playerId, stage)
            activeNativeOperation = operation
            val release = stage.startsWith("release-") &&
                activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
            if (release) Log.d(TAG, "Native release start id=${playerId ?: "engine"} stage=$stage")
            try {
                action()
            } finally {
                if (release) Log.d(TAG, "Native release end id=${playerId ?: "engine"} " +
                    "stage=${operation.stage} elapsedMs=${SystemClock.elapsedRealtime() - operation.startedAt}")
                if (activeNativeOperation === operation) activeNativeOperation = null
            }
        }
    }

    private fun nativeStage(stage: String) {
        activeNativeOperation?.stage = stage
    }

    private fun nativeQueueDiagnostics(): Map<String, String> {
        val operation = activeNativeOperation
        return mapOf(
            "native-queue-active-player-id" to (operation?.playerId?.toString() ?: "none"),
            "native-queue-active-stage" to (operation?.stage ?: "idle"),
            "native-queue-active-start-elapsed-ms" to (operation?.startedAt?.toString() ?: "none"),
            "native-queue-active-elapsed-ms" to (operation?.let {
                (SystemClock.elapsedRealtime() - it.startedAt).coerceAtLeast(0L).toString()
            } ?: "0"),
        )
    }

    private fun queueTimeoutMessage(message: String): String {
        val operation = activeNativeOperation ?: return "$message (native queue idle)"
        return "$message (active player=${operation.playerId ?: "engine"}, stage=${operation.stage}, " +
            "elapsedMs=${SystemClock.elapsedRealtime() - operation.startedAt})"
    }

    private fun cancelPlaybackStart(entry: Entry) {
        entry.playbackStart = null
        entry.playerTimeout?.let(main::removeCallbacks)
        entry.playerTimeout = null
    }

    /**
     * Starts shared engine/font preparation once, without opening any media.
     * Repeated requests never retry a failed preparation; a later explicit
     * media create retains its existing retry behavior after cleanup settles.
     */
    fun warmUp() {
        if (Looper.myLooper() !== main.looper) {
            main.post { warmUp() }
            return
        }
        if (closed || libVlc != null || preparingEngine || enginePreparation != null) return
        Log.i(TAG, "Engine warm-up requested")
        prepareEngine()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            result.error("disposed", "LibVLC host has been disposed", null)
            return
        }
        if (call.method == "debugReadSubtitleSurfacePixels" &&
            activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
            result.error("subtitle_probe_debug_only", "Subtitle pixel probing requires a debuggable application", null)
            return
        }
        try {
            if (call.method == "init") {
                entries.values.toList().forEach { disposeEntry(it) }
                result.success(null)
                return
            }
            if (call.method == "create") {
                create(call, result)
                return
            }
            val id = call.argument<Number>("id")?.toInt()
                ?: throw IllegalArgumentException("Missing player id")
            val entry = entries[id]
            if (entry == null) {
                if (call.method == "dispose") {
                    val pending = pendingDisposals[id]
                    if (pending != null) disposeEntry(pending, result)
                    else replyDisposed(result, disposalFailures[id])
                }
                else result.error("unknown_player", "LibVLC player $id is unavailable", null)
                return
            }
            when (call.method) {
                "dispose" -> {
                    disposeEntry(entry, result)
                }
                "setPresentationAllowed" -> {
                    val allowed = call.argument<Boolean>("allowed")
                        ?: throw IllegalArgumentException("Missing presentation permission")
                    if (allowed) {
                        // A host has one presented media item, including during route handoff.
                        entries.values.filter { it !== entry && it.allowed }.forEach(::revoke)
                        entry.allowed = true
                        updateVisibility(entry)
                        maybePlay(entry)
                    } else revoke(entry)
                    result.success(null)
                }
                "play" -> {
                    check(entry.allowed) { "Presentation permission is required before playback" }
                    check(entry.failure == null) { "Player initialization failed; recreate the player to retry" }
                    entry.wantsPlay = true
                    trace(entry, "play-request")
                    maybePlay(entry)
                    result.success(null)
                }
                "pause" -> {
                    pause(entry)
                    result.success(null)
                }
                "getPosition" -> nativeCall(entry, result, call.method) {
                    entry.pendingPosition ?: entry.player?.time?.coerceAtLeast(0L) ?: 0L
                }
                "seekTo" -> {
                    val position = requiredLong(call, "position")
                    require(position >= 0) { "Position must not be negative" }
                    entry.pendingPosition = position
                    nativeCall(entry, result, call.method) {
                        entry.player?.takeIf { !entry.nativeEnded }?.let {
                            val inputOpen = it.playerState == IMedia.State.Playing || it.playerState == IMedia.State.Paused
                            check(!inputOpen || it.isSeekable) { "LibVLC media is not seekable" }
                            if (!it.isSeekable) return@let
                            check(it.setTime(position) >= 0) { "LibVLC rejected seek" }
                            main.post { if (!entry.disposed && entry.pendingPosition == position) entry.pendingPosition = null }
                        }
                        null
                    }
                }
                "setLooping" -> {
                    entry.looping = call.argument<Boolean>("looping")
                        ?: throw IllegalArgumentException("Missing looping value")
                    result.success(null)
                }
                "setVolume" -> {
                    val volume = requiredDouble(call, "volume")
                    require(volume in 0.0..1.0) { "Volume must be between zero and one" }
                    entry.volume = volume
                    nativeCall(entry, result, call.method) {
                        entry.player?.let { check(it.setVolume((volume * 100).roundToInt()) == 0) { "LibVLC rejected volume" } }
                        null
                    }
                }
                "setPlaybackSpeed" -> {
                    val speed = requiredDouble(call, "speed")
                    require(speed > 0 && speed.toFloat().isFinite()) { "Playback speed must be finite and positive" }
                    entry.rateRequestCount++
                    entry.speed = speed
                    nativeCall(entry, result, call.method) {
                        entry.player?.let { setRate(it, speed) }
                        null
                    }
                }
                "setMixWithOthers" -> {
                    entry.mixWithOthers = call.argument<Boolean>("mixWithOthers")
                        ?: throw IllegalArgumentException("Missing mixWithOthers value")
                    if (entry.mixWithOthers) abandonFocus(entry)
                    else if (entry.playing) check(requestFocus(entry)) { "Audio focus was denied" }
                    result.success(null)
                }
                "setPreventsDisplaySleepDuringVideoPlayback" -> {
                    entry.preventsDisplaySleep = call.argument<Boolean>("preventsDisplaySleepDuringVideoPlayback")
                        ?: throw IllegalArgumentException("Missing display sleep preference")
                    updateAwake(entry)
                    result.success(null)
                }
                "getAdvancedState" -> result.success(advancedState(entry))
                "selectAudioTrack", "selectSubtitleTrack" -> {
                    val idString = call.argument<String>("trackId")
                        ?: throw IllegalArgumentException("Missing track id")
                    val trackId = idString.toIntOrNull()
                        ?: throw IllegalArgumentException("Invalid LibVLC track id")
                    val audio = call.method == "selectAudioTrack"
                    val player = entry.player
                    val type = if (audio) IMedia.Track.Type.Audio else IMedia.Track.Type.Text
                    val known = entry.tracks.any { it.type == type && it.id == trackId }
                    val nativeTracks = if (audio) player?.audioTracks else player?.spuTracks
                    require(trackId == -1 || known || nativeTracks?.any { it.id == trackId } == true) { "Unknown media track id" }
                    if (player == null || nativeTracks.isNullOrEmpty() || entry.nativeEnded) {
                        if (audio) entry.selectedAudioTrack = trackId else entry.selectedSubtitleTrack = trackId
                        emitAdvanced(entry)
                        result.success(null)
                        return
                    }
                    nativeCall(entry, result, call.method) {
                        val ok = if (audio) player.setAudioTrack(trackId)
                        else player.setSpuTrack(trackId)
                        check(ok) { "LibVLC rejected track selection" }
                        main.post {
                            if (audio) entry.selectedAudioTrack = trackId
                            else entry.selectedSubtitleTrack = trackId
                            emitAdvanced(entry)
                        }
                        null
                    }
                }
                "importSubtitle" -> {
                    val path = call.argument<String>("path")?.takeIf { it.isNotBlank() }
                        ?: throw IllegalArgumentException("Missing subtitle path")
                    val uri = Uri.parse(path).let { if (it.scheme == null) Uri.fromFile(File(path)) else it }
                    val media = entry.source?.media ?: throw IllegalStateException("Media initialization is not complete")
                    // Import explicitly selects the new subtitle, overriding a prior disable/selection intent.
                    val previousTrack = entry.selectedSubtitleTrack
                    entry.selectedSubtitleTrack = null
                    nativeCall(entry, result, call.method) {
                        try {
                            val readableUri = subtitleUri(entry, uri)
                            val encoded = VLCUtil.encodeVLCUri(readableUri)
                            entry.player?.takeIf { !entry.nativeEnded && it.playerState != IMedia.State.NothingSpecial }?.let {
                                check(it.addSlave(IMedia.Slave.Type.Subtitle, readableUri, true)) { "LibVLC rejected external subtitle" }
                            }
                            // Register on Media for first playback and every later native input.
                            media.addSlave(IMedia.Slave(IMedia.Slave.Type.Subtitle, 4, encoded))
                            check(media.slaves?.any { it.type == IMedia.Slave.Type.Subtitle && it.uri == encoded } == true) {
                                "LibVLC did not retain the external subtitle"
                            }
                        } catch (error: Exception) {
                            main.post { entry.selectedSubtitleTrack = previousTrack }
                            throw error
                        }
                        main.post { emitAdvanced(entry) }
                        null
                    }
                }
                "setAudioDelay", "setSubtitleDelay" -> {
                    val delay = requiredLong(call, "delay")
                    val audio = call.method == "setAudioDelay"
                    nativeCall(entry, result, call.method) {
                        entry.player?.let {
                            if (it.playerState == IMedia.State.Playing || it.playerState == IMedia.State.Paused) {
                                check(if (audio) it.setAudioDelay(delay) else it.setSpuDelay(delay)) { "LibVLC rejected track delay" }
                            }
                        }
                        main.post {
                            if (audio) entry.audioDelay = delay else entry.subtitleDelay = delay
                            emitAdvanced(entry)
                        }
                        null
                    }
                }
                "setAbLoop" -> {
                    val start = call.argument<Number>("start")?.toLong()
                    val end = call.argument<Number>("end")?.toLong()
                    require(start == null || start >= 0) { "A must not be negative" }
                    require(end == null || (start != null && end > start)) { "B must be after A" }
                    require(end == null || entry.duration <= 0 || end <= entry.duration) { "B exceeds media duration" }
                    entry.abStart = start
                    entry.abEnd = end
                    entry.abSeeking = false
                    emitAdvanced(entry)
                    result.success(null)
                }
                "readPlaybackDiagnostics" -> {
                    // View/holder state belongs to the Android main thread; SDK
                    // player queries remain serialized on nativeQueue.
                    val subtitleSurface = entry.activeView?.subtitleDiagnostics()
                        ?: mapOf("subtitle-surface-present" to "false", "subtitle-surface-view-id" to "none")
                    // Waiting for shared bootstrap has no player/Media to query.
                    // Keep its stage and deadline observable even if a blocking
                    // SDK preparation call currently occupies nativeQueue.
                    if (entry.source == null && entry.player == null) result.success(diagnostics(entry) + subtitleSurface)
                    else nativeCall(entry, result, call.method) { diagnostics(entry) + subtitleSurface }
                }
                "debugReadSubtitleSurfacePixels" -> debugReadSubtitleSurfacePixels(entry, result)
                "setFitMode" -> {
                    val mode = call.argument<String>("fitMode")
                        ?: throw IllegalArgumentException("Missing video fit mode")
                    val scale = scaleTypes[mode] ?: throw IllegalArgumentException("Unknown video fit mode")
                    val viewId = call.argument<Number>("viewId")?.toInt()
                        ?: throw IllegalArgumentException("Missing platform view id")
                    val view = entry.views.firstOrNull { it.platformViewId == viewId }
                        ?: throw IllegalArgumentException("Unknown platform view id")
                    view.fitMode = mode
                    if (entry.activeView === view) entry.player?.setVideoScale(scale)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            val code = if (error is IllegalArgumentException) "invalid_arguments" else "player_operation_failed"
            result.error(code, error.message, null)
        }
    }

    /** Debug-only, explicit buffer inspection; never part of copyable playback diagnostics. */
    private fun debugReadSubtitleSurfacePixels(entry: Entry, result: MethodChannel.Result) {
        val view = entry.activeView
        val generation = entry.surfaceGeneration
        fun authorized(): Boolean {
            val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            val power = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
            return !closed && !activity.isDestroyed && !activity.isFinishing &&
                entries[entry.id] === entry && !entry.disposed && entry.allowed && entry.failure == null &&
                entry.player != null && entry.activeView === view && entry.attachedView === view &&
                entry.surfaceGeneration == generation && entry.viewportAttached && entry.surfacesReady &&
                !keyguard.isKeyguardLocked && power.isInteractive
        }
        if (view == null || !authorized()) {
            result.error("subtitle_probe_unavailable", "An authorized, current subtitle surface is required", null)
            return
        }
        view.readSubtitleSurfacePixels(
            authorized = ::authorized,
            onResult = result::success,
            onError = { code, message -> result.error(code, message, null) },
        )
    }

    private fun requiredLong(call: MethodCall, name: String): Long =
        call.argument<Number>(name)?.toLong() ?: throw IllegalArgumentException("Missing $name")

    private fun requiredDouble(call: MethodCall, name: String): Double =
        (call.argument<Number>(name)?.toDouble() ?: throw IllegalArgumentException("Missing $name")).also {
            require(it.isFinite()) { "$name must be finite" }
        }

    private fun create(call: MethodCall, result: MethodChannel.Result) {
        val entry = Entry(nextId++)
        entries[entry.id] = entry
        // Always cross video_player's creation barrier, including malformed/unopenable media.
        result.success(entry.id)
        val request = try {
            MediaRequest(
                call.argument<String>("uri")?.takeIf { it.isNotBlank() }
                    ?: throw IllegalArgumentException("Missing media URI"),
                call.argument<String>("package"), call.argument<Map<*, *>>("httpHeaders"),
            )
        } catch (error: Exception) {
            fail(entry, "media_open_failed", "LibVLC could not read the media request (${error.javaClass.simpleName})")
            return
        }
        if (libVlc != null) {
            queueMediaOpen(entry, request)
            return
        }
        // A failed SDK call can still be unwinding on nativeQueue. Do not
        // enqueue another preparation behind it or leave new callers waiting.
        if (preparingEngine && enginePreparationFailure != null) {
            val failure = enginePreparationFailure!!
            fail(entry, failure.code, failure.message)
            return
        }
        engineWaiters[entry] = request
        if (!preparingEngine) prepareEngine()
    }

    private fun prepareEngine() {
        val preparation = EnginePreparation()
        enginePreparation = preparation
        preparingEngine = true
        enginePreparationFailure = null
        enginePreparationStage = "queued"
        preparation.queueTimeout = Runnable {
            if (enginePreparation === preparation && preparation.startedAt == null && !preparation.cancelled) {
                failEnginePreparation(preparation, "engine_queue_timeout", queueTimeoutMessage("LibVLC engine preparation could not start on the native queue"))
            }
        }.also { main.postDelayed(it, INITIALIZATION_QUEUE_TIMEOUT_MS) }
        queueNative(null, "engine-prepare") {
            var prepared: LibVLC? = null
            var fonts: File? = null
            var failure: Failure? = null
            try {
                if (closed || preparation.cancelled) return@queueNative
                val startedAt = SystemClock.elapsedRealtime()
                if (startedAt - preparation.queuedAt >= INITIALIZATION_QUEUE_TIMEOUT_MS) {
                    failure = Failure("engine_queue_timeout", queueTimeoutMessage("LibVLC engine preparation could not start on the native queue"))
                    return@queueNative
                }
                preparation.startedAt = startedAt
                main.post {
                    if (enginePreparation !== preparation || preparation.cancelled || closed) return@post
                    preparation.queueTimeout?.let(main::removeCallbacks)
                    preparation.queueTimeout = null
                    enginePreparationStage = "constructing-engine"
                    Log.i(TAG, "Engine preparation started")
                    preparation.timeout = Runnable {
                        failEnginePreparation(preparation, "engine_preparation_timeout", "LibVLC engine and font preparation timed out")
                    }.also {
                        val remaining = ENGINE_PREPARATION_TIMEOUT_MS -
                            (SystemClock.elapsedRealtime() - preparation.startedAt!!)
                        main.postDelayed(it, remaining.coerceAtLeast(0L))
                    }
                }
                nativeStage("engine-construct")
                prepared = LibVLC(activity.applicationContext, arrayListOf(
                    "--audio-time-stretch", "--no-video-title-show", "--stats", "--android-display-chroma=RV32",
                ).apply {
                    if (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) add("--verbose=2")
                })
                if (closed || preparation.cancelled) return@queueNative
                main.post {
                    if (enginePreparation === preparation && !preparation.cancelled && !closed)
                        enginePreparationStage = "building-font-cache"
                }
                // This SDK call is blocking and has no cancellation API. A
                // deadline cancels delivery; release waits for the call to return.
                val started = SystemClock.elapsedRealtime()
                try {
                    nativeStage("engine-font-cache")
                    fontCacheValid = prepared.buildFontCache()
                } catch (error: Exception) {
                    fontCacheValid = false
                    Log.w(TAG, "Font cache build failed (${error.javaClass.simpleName})")
                } finally {
                    fontCacheBuildMs = SystemClock.elapsedRealtime() - started
                }
                if (fontCacheValid == true) Log.i(TAG, "Font cache valid after ${fontCacheBuildMs}ms")
                else Log.w(TAG, "Font cache not valid on disk after ${fontCacheBuildMs}ms")
                if (closed || preparation.cancelled) return@queueNative
                main.post {
                    if (enginePreparation === preparation && !preparation.cancelled && !closed)
                        enginePreparationStage = "installing-subtitle-fonts"
                }
                nativeStage("engine-font-install")
                fonts = prepareSubtitleFonts()
            } catch (error: Exception) {
                failure = Failure("engine_preparation_failed", "LibVLC engine preparation failed (${error.javaClass.simpleName})")
            } catch (error: LinkageError) {
                failure = Failure("engine_unavailable", "LibVLC could not load its native engine (${error.javaClass.simpleName})")
            } catch (error: OutOfMemoryError) {
                failure = Failure("engine_resource_exhausted", "LibVLC engine preparation ran out of memory")
            } finally {
                val engine = prepared
                val installedFonts = fonts
                val error = failure
                main.post { finishEnginePreparation(preparation, engine, installedFonts, error) }
            }
        }
    }

    private fun failEnginePreparation(preparation: EnginePreparation, code: String, message: String) {
        if (enginePreparation !== preparation || !preparingEngine || preparation.cancelled || closed) return
        preparation.cancelled = true
        preparation.finishedAt = SystemClock.elapsedRealtime()
        preparation.timeout?.let(main::removeCallbacks)
        preparation.queueTimeout?.let(main::removeCallbacks)
        preparation.timeout = null
        preparation.queueTimeout = null
        enginePreparationStage = "failed"
        enginePreparationFailure = Failure(code, message)
        Log.e(TAG, "$code during shared engine preparation")
        val waiting = engineWaiters.keys.toList()
        engineWaiters.clear()
        waiting.forEach { fail(it, code, message) }
    }

    private fun finishEnginePreparation(preparation: EnginePreparation, engine: LibVLC?, fonts: File?, failure: Failure?) {
        preparation.timeout?.let(main::removeCallbacks)
        preparation.queueTimeout?.let(main::removeCallbacks)
        preparation.timeout = null
        preparation.queueTimeout = null
        if (enginePreparation === preparation && !closed && !preparation.cancelled) {
            val elapsed = preparation.startedAt?.let { SystemClock.elapsedRealtime() - it }
            when {
                elapsed != null && elapsed >= ENGINE_PREPARATION_TIMEOUT_MS ->
                    failEnginePreparation(preparation, "engine_preparation_timeout", "LibVLC engine and font preparation timed out")
                failure != null -> failEnginePreparation(preparation, failure.code, failure.message)
                engine == null || fonts == null ->
                    failEnginePreparation(preparation, "engine_preparation_failed", "LibVLC engine preparation did not complete")
            }
        }
        if (enginePreparation === preparation) {
            preparingEngine = false
            if (!closed && !preparation.cancelled && engine != null && fonts != null) {
                libVlc = engine
                subtitleFonts = fonts
                preparation.finishedAt = SystemClock.elapsedRealtime()
                enginePreparationStage = "ready"
                Log.i(TAG, "Engine preparation ready after ${preparation.finishedAt!! - preparation.startedAt!!}ms")
                val waiting = engineWaiters.toList()
                engineWaiters.clear()
                waiting.forEach { (entry, request) ->
                    if (!entry.disposed && entry.failure == null) queueMediaOpen(entry, request)
                }
                maybeShutdownQueue()
                return
            }
        }
        // A cancelled/failed preparation never publishes a usable engine, even
        // if a blocking native operation completed after its owner was gone.
        if (engine != null) queueNative(null, "release-prepared-engine") {
            try { engine.release() } catch (error: Exception) {
                Log.e(TAG, "Prepared engine cleanup failed (${error.javaClass.simpleName})")
            }
        }
        maybeShutdownQueue()
    }

    private fun queueMediaOpen(entry: Entry, request: MediaRequest) {
        entry.mediaOpenPending = true
        entry.initializationStage = "queued"
        entry.initializationQueuedAt = SystemClock.elapsedRealtime()
        entry.queueTimeout = Runnable {
            if (!entry.disposed && entry.failure == null && entry.initializationStartedAt == null)
                fail(entry, "media_queue_timeout", queueTimeoutMessage("LibVLC media opening could not start on the native queue"))
        }.also { main.postDelayed(it, INITIALIZATION_QUEUE_TIMEOUT_MS) }
        pendingCreations++
        queueNative(entry.id, "media-open") {
            var source: Source? = null
            var failure: Failure? = null
            try {
                if (entry.disposed || entry.failure != null || closed) return@queueNative
                val startedAt = SystemClock.elapsedRealtime()
                if (startedAt - entry.initializationQueuedAt!! >= INITIALIZATION_QUEUE_TIMEOUT_MS) {
                    failure = Failure("media_queue_timeout", queueTimeoutMessage("LibVLC media opening could not start on the native queue"))
                    return@queueNative
                }
                entry.initializationStartedAt = startedAt
                main.post {
                    entry.queueTimeout?.let(main::removeCallbacks)
                    entry.queueTimeout = null
                    if (entry.disposed || entry.failure != null || closed) return@post
                    entry.initializationStage = "opening"
                    trace(entry, "media-open-started")
                    entry.openTimeout = Runnable {
                        fail(entry, "initialization_timeout", "LibVLC media opening and metadata parsing timed out")
                    }.also {
                        val remaining = OPEN_TIMEOUT_MS - (SystemClock.elapsedRealtime() - entry.initializationStartedAt!!)
                        main.postDelayed(it, remaining.coerceAtLeast(0L))
                    }
                }
                val lib = checkNotNull(libVlc) { "LibVLC engine is not prepared" }
                val fonts = checkNotNull(subtitleFonts) { "LibVLC fonts are not prepared" }
                source = openSource(lib, request.uri, request.packageName)
                applyHttpHeaders(source.media, request.headers)
                source.media.addOption(":ssa-fontsdir=${fonts.absolutePath}")
                source.media.setHWDecoderEnabled(true, false)
            } catch (error: Exception) {
                val code = if (error is UnsupportedOperationException) "unsupported_http_headers" else "media_open_failed"
                failure = Failure(code, if (error is UnsupportedOperationException) error.message ?: code
                    else "LibVLC could not open media (${error.javaClass.simpleName})")
            } finally {
                val opened = source
                val error = failure
                main.post {
                    if (opened != null && (entry.disposed || entry.failure != null || closed || error != null)) {
                        releaseSource(opened, entry.id) { cleanupFailure ->
                            entry.cleanupFailure = entry.cleanupFailure ?: cleanupFailure
                            entry.mediaOpenPending = false
                            completeDisposal(entry)
                        }
                    } else {
                        entry.mediaOpenPending = false
                        if (opened != null) {
                            entry.source = opened
                            entry.initializationStage = "parsing"
                            parse(entry)
                        }
                        completeDisposal(entry)
                    }
                    if (error != null) fail(entry, error.code, error.message)
                    pendingCreations--
                    maybeShutdownQueue()
                }
            }
        }
    }

    private fun prepareSubtitleFonts(): File {
        val directory = File(activity.cacheDir, "privi-vlc-fonts")
        check(directory.isDirectory || directory.mkdirs()) { "Subtitle font directory is unavailable" }
        val destination = File(directory, "NotoSansCJKsc-Regular.ttf")
        val temporary = File.createTempFile("font-", ".tmp", directory)
        try {
            activity.assets.open(assetLookup("assets/fonts/NotoSansCJKsc-Regular.ttf", null)).use { input ->
                temporary.outputStream().use { output -> input.copyTo(output) }
            }
            check(temporary.renameTo(destination)) { "Subtitle font installation failed" }
        } finally {
            if (temporary.exists()) temporary.delete()
        }
        return directory
    }

    private fun openSource(lib: LibVLC, value: String, packageName: String?): Source {
        val uri = Uri.parse(value)
        return when (uri.scheme) {
            "asset" -> {
                val name = uri.path?.removePrefix("/")?.takeIf { it.isNotBlank() }
                    ?: throw IllegalArgumentException("Missing asset name")
                val key = assetLookup(name, packageName)
                val descriptor = try { activity.assets.openFd(key) } catch (_: java.io.FileNotFoundException) { null }
                if (descriptor != null) {
                    try { Source(Media(lib, descriptor), descriptor) } catch (error: Exception) {
                        descriptor.close()
                        throw error
                    }
                } else {
                    // Compressed APK assets cannot expose a seekable descriptor to LibVLC.
                    val file = File.createTempFile("privi-vlc-asset-", ".media", activity.cacheDir)
                    try {
                        activity.assets.open(key).use { input -> file.outputStream().use { input.copyTo(it) } }
                        Source(Media(lib, file.absolutePath), temporaryFile = file)
                    } catch (error: Exception) {
                        file.delete()
                        throw error
                    }
                }
            }
            "content" -> {
                val descriptor = activity.contentResolver.openAssetFileDescriptor(uri, "r")
                    ?: throw IllegalArgumentException("Content provider returned no media descriptor")
                try {
                    Source(Media(lib, descriptor), descriptor)
                } catch (error: Exception) {
                    descriptor.close()
                    throw error
                }
            }
            null -> Source(Media(lib, File(value).absolutePath))
            else -> Source(Media(lib, uri))
        }
    }

    private fun applyHttpHeaders(media: Media, headers: Map<*, *>?) {
        headers?.forEach { (key, value) ->
            require(key is String && value is String) { "HTTP headers must contain strings" }
            require(!key.contains('\r') && !key.contains('\n') && !value.contains('\r') && !value.contains('\n')) {
                "HTTP headers must not contain newlines"
            }
            val option = when (key.lowercase(java.util.Locale.ROOT)) {
                "user-agent" -> "http-user-agent"
                "referer" -> "http-referrer"
                else -> throw UnsupportedOperationException("LibVLC 3 supports only User-Agent and Referer overrides")
            }
            media.addOption(":$option=$value")
        }
    }

    private fun parse(entry: Entry) {
        val media = entry.source?.media ?: return
        media.setEventListener { event ->
            if (!entry.disposed && event.type == IMedia.Event.ParsedChanged) {
                when (event.parsedStatus) {
                    IMedia.ParsedStatus.Done -> parsed(entry)
                    IMedia.ParsedStatus.Timeout -> fail(entry, "metadata_timeout", "LibVLC metadata parsing timed out")
                    else -> fail(entry, "metadata_failed", "LibVLC could not parse media metadata (status ${event.parsedStatus})")
                }
            }
        }
        if (!media.parseAsync(IMedia.Parse.ParseNetwork, PARSE_TIMEOUT_MS)) {
            fail(entry, "metadata_failed", "LibVLC rejected metadata parsing")
        }
    }

    private fun parsed(entry: Entry) {
        if (entry.disposed || closed || entry.failure != null || entry.initialized != null) return
        if (entry.initializationStartedAt?.let { SystemClock.elapsedRealtime() - it >= OPEN_TIMEOUT_MS } == true) {
            fail(entry, "initialization_timeout", "LibVLC media opening and metadata parsing timed out")
            return
        }
        val media = entry.source?.media ?: return
        entry.tracks = (0 until media.trackCount).mapNotNull { media.getTrack(it) }
        val video = entry.tracks.filterIsInstance<IMedia.VideoTrack>().firstOrNull()
        if (video != null) {
            if (video.width <= 0 || video.height <= 0) {
                fail(entry, "video_dimensions_unavailable", "LibVLC returned no usable video dimensions")
                return
            }
            var width = video.width.toDouble()
            var height = video.height.toDouble()
            if (video.sarNum > 0 && video.sarDen > 0) width *= video.sarNum.toDouble() / video.sarDen
            if (video.orientation in IMedia.VideoTrack.Orientation.LeftTop..IMedia.VideoTrack.Orientation.RightBottom) {
                val oldWidth = width
                width = height
                height = oldWidth
            }
            entry.width = width
            entry.height = height
        } else if (entry.tracks.none { it is IMedia.AudioTrack }) {
            fail(entry, "media_tracks_unavailable", "LibVLC found no playable audio or video tracks")
            return
        }
        entry.duration = media.duration.coerceAtLeast(0)
        entry.openTimeout?.let(main::removeCallbacks)
        entry.openTimeout = null
        entry.initializationStage = "ready"
        entry.initializationFinishedAt = SystemClock.elapsedRealtime()
        entry.initialized = mapOf(
            "event" to "initialized", "duration" to entry.duration,
            "width" to entry.width, "height" to entry.height, "rotationCorrection" to 0,
        )
        trace(entry, "metadata-ready")
        emit(entry, entry.initialized!!)
        emitAdvanced(entry)
        maybePlay(entry)
    }

    private fun ensurePlayer(entry: Entry) {
        if (entry.player != null) return
        val media = entry.source?.media ?: return
        trace(entry, "player-creating")
        val player = MediaPlayer(media)
        entry.player = player
        trace(entry, "player-created")
        player.setUseOrientationFromBounds(true)
        player.setVideoTitleDisplay(MediaPlayer.Position.Disable, 0)
        player.setEventListener { event -> onPlayerEvent(entry, event) }
        player.vlcVout.addCallback(entry.voutCallback)
    }

    private fun maybePlay(entry: Entry) {
        if (entry.disposed || entry.failure != null || !entry.allowed || !entry.wantsPlay || entry.initialized == null) return
        val view = entry.activeView ?: return
        if (!view.presentable) {
            // Cold hybrid composition can hide its parent before any player or
            // Surface exists. Wake Flutter without opening a hidden decoder.
            requestSurfaceFrame(entry, view)
            return
        }
        try {
            ensurePlayer(entry)
            val player = entry.player ?: return
            if (entry.attachedView !== view || !player.vlcVout.areViewsAttached()) {
                attach(entry, view)
            }
            updateSurfaceReadiness(entry, view)
            if (!entry.surfacesReady || !entry.viewportAttached || !view.surfacesAvailable || entry.playing) return
            val generation = entry.surfaceGeneration
            if (entry.playbackStart?.generation == generation) return
            check(requestFocus(entry)) { "Audio focus was denied" }
            if (entry.nativeEnded && entry.pendingPosition == 0L) {
                // video_player seeks to zero before replaying an ended item.
                // The replacement input starts there already; flushing it on
                // Playing repeats the same startup seek as an automatic loop.
                // A running input still handles seekTo(0) through setTime.
                entry.pendingPosition = null
                trace(entry, "reopen-satisfies-seek-zero")
            }
            if (entry.nativeEnded) {
                // Replacing an ended input can report Stopped before its new
                // Playing event. Preserve the owner's play intent during this
                // bounded transition instead of reporting a user pause.
                entry.inputRestarting = true
                updateBuffering(entry)
            }
            if (entry.playerTimeout == null) {
                entry.playerTimeout = Runnable {
                    if (!entry.playing && entry.wantsPlay) fail(entry, "playback_timeout",
                        queueTimeoutMessage("LibVLC did not start playback in time"))
                }.also { main.postDelayed(it, OPEN_TIMEOUT_MS) }
            }
            val start = PlaybackStart(generation)
            entry.playbackStart = start
            queueNative(entry.id, "play-start") {
                try {
                    if (entry.playbackStart !== start || entry.disposed || !entry.allowed || !entry.wantsPlay || !entry.viewportAttached ||
                        !entry.surfacesReady || entry.surfaceGeneration != generation) return@queueNative
                    if (entry.nativeEnded) {
                        nativeStage("play-set-media")
                        player.media = entry.source?.media
                        entry.nativeEnded = false
                        entry.inputReopenCount++
                        trace(entry, "input-reopened")
                    }
                    nativeStage("play-set-volume")
                    check(player.setVolume((entry.volume * 100).roundToInt()) == 0) { "LibVLC rejected volume" }
                    nativeStage("play-set-rate")
                    setRate(player, entry.speed)
                    // setMedia can block while retiring the old input. A real
                    // pause, revocation, or surface handoff during that work
                    // must still prevent this queued play from starting.
                    if (entry.playbackStart !== start || entry.disposed || !entry.allowed || !entry.wantsPlay || !entry.viewportAttached ||
                        !entry.surfacesReady || entry.surfaceGeneration != generation) return@queueNative
                    trace(entry, "native-play")
                    nativeStage("play-native")
                    player.play()
                } catch (error: Exception) {
                    main.post {
                        if (entry.playbackStart === start)
                            fail(entry, "playback_failed", "LibVLC could not start playback (${error.javaClass.simpleName})")
                    }
                }
                // nativePlay returning only submits startup. Keep the identity
                // until Playing or an explicit cancellation, not worker return.
            }
        } catch (error: Exception) {
            fail(entry, "playback_failed", "LibVLC could not attach playback (${error.javaClass.simpleName})")
        }
    }

    private fun attach(entry: Entry, view: LibVlcVideoView) {
        val player = entry.player ?: return
        entry.surfaceAttachCount++
        cancelPlaybackStart(entry)
        entry.surfaceGeneration++
        entry.viewportAttached = false
        entry.voutReady = false
        entry.attachedView?.setPresentationVisible(false)
        // AWindow auto-detaches on surfaceDestroyed, but the old VideoHelper
        // still owns its layout listener until MediaPlayer.detachViews().
        player.detachViews()
        entry.surfacesReady = false
        entry.attachedView = view
        entry.viewportAttached = view.presentable
        view.setPresentationVisible(entry.allowed)
        player.attachViews(view.layout, null, true, false)
        view.configureSurfaces()
        player.setUseOrientationFromBounds(true)
        player.setVideoScale(scaleTypes.getValue(view.fitMode))
        updateVisibility(entry)
        updateSurfaceReadiness(entry, view)
        trace(entry, "surface-attached")
    }

    private fun setRate(player: MediaPlayer, speed: Double) {
        player.rate = speed.toFloat()
        check(abs(player.rate - speed.toFloat()) <= 0.001f * speed.toFloat()) { "LibVLC rejected playback speed" }
    }

    private fun onPlayerEvent(entry: Entry, event: MediaPlayer.Event) {
        if (entry.disposed || entry.failure != null) return
        when (event.type) {
            MediaPlayer.Event.Playing -> {
                trace(entry, "event-playing")
                if (!entry.allowed || !entry.wantsPlay) {
                    pause(entry)
                    return
                }
                if (!entry.viewportAttached || !entry.surfacesReady || entry.activeView?.surfacesAvailable != true) {
                    suspendForSurfaceLoss(entry, forcePause = true)
                    entry.activeView?.let { scheduleSurfaceRecovery(entry, it) }
                    return
                }
                cancelPlaybackStart(entry)
                entry.playing = true
                entry.inputRestarting = false
                entry.surfaceSuspended = false
                updateBuffering(entry)
                entry.nativeEnded = false
                updateAwake(entry)
                entry.player?.let { player ->
                    queueNative(entry.id, "apply-playback-settings") {
                        if (entry.disposed) return@queueNative
                        try {
                            if (entry.audioDelay != 0L) check(player.setAudioDelay(entry.audioDelay)) { "Audio delay rejected" }
                            if (entry.subtitleDelay != 0L) check(player.setSpuDelay(entry.subtitleDelay)) { "Subtitle delay rejected" }
                            restoreTrackIntent(entry, player)
                            entry.pendingPosition?.let { position ->
                                if (player.isSeekable) {
                                    trace(entry, "pending-seek-$position")
                                    check(player.setTime(position) >= 0) { "Pending seek rejected" }
                                    main.post { if (entry.pendingPosition == position) entry.pendingPosition = null }
                                }
                            }
                        } catch (error: Exception) {
                            main.post { advancedError(entry, "LibVLC could not apply playback settings (${error.javaClass.simpleName})") }
                        }
                    }
                }
                emit(entry, mapOf("event" to "isPlayingStateUpdate", "isPlaying" to true))
                emitAdvanced(entry)
            }
            MediaPlayer.Event.Paused, MediaPlayer.Event.Stopped -> {
                trace(entry, if (event.type == MediaPlayer.Event.Paused) "event-paused" else "event-stopped")
                entry.playing = false
                updateAwake(entry)
                val internalInputStop = event.type == MediaPlayer.Event.Stopped &&
                    entry.inputRestarting && entry.allowed && entry.wantsPlay
                if (!internalInputStop && (!entry.surfaceSuspended || !entry.allowed || !entry.wantsPlay)) {
                    emit(entry, mapOf("event" to "isPlayingStateUpdate", "isPlaying" to false))
                }
            }
            MediaPlayer.Event.EncounteredError -> fail(entry, "libvlc_error", "LibVLC encountered a fatal playback error")
            MediaPlayer.Event.EndReached -> {
                trace(entry, "event-ended")
                entry.playing = false
                cancelPlaybackStart(entry)
                entry.nativeEnded = true
                updateAwake(entry)
                val start = entry.abStart
                if ((entry.looping || (start != null && entry.abEnd != null)) && entry.allowed && entry.wantsPlay) {
                    // Reopening ordinary playback (or A=0) already starts at
                    // zero; only a nonzero A point needs a subsequent seek.
                    if (entry.pendingPosition == null) entry.pendingPosition = start?.takeIf { it > 0L }
                    maybePlay(entry)
                } else {
                    entry.wantsPlay = false
                    abandonFocus(entry)
                    emit(entry, mapOf("event" to "isPlayingStateUpdate", "isPlaying" to false))
                    emit(entry, mapOf("event" to "completed"))
                }
            }
            MediaPlayer.Event.Buffering -> {
                entry.nativeBuffering = entry.allowed && event.buffering < 100f
                updateBuffering(entry)
            }
            MediaPlayer.Event.TimeChanged -> {
                val start = entry.abStart
                val end = entry.abEnd
                if (start != null && end != null && entry.wantsPlay && entry.allowed) {
                    if (event.timeChanged < end) entry.abSeeking = false
                    else if (!entry.abSeeking) {
                        entry.abSeeking = true
                        val player = entry.player ?: return
                        queueNative(entry.id, "ab-seek") {
                            if (entry.disposed || !entry.allowed || !entry.wantsPlay) return@queueNative
                            if (entry.nativeEnded || player.playerState == IMedia.State.Ended) return@queueNative
                            if (!player.isSeekable || player.setTime(start) < 0) {
                                main.post {
                                    entry.abStart = null
                                    entry.abEnd = null
                                    entry.abSeeking = false
                                    advancedError(entry, "LibVLC could not seek the A–B loop")
                                }
                            } else {
                                entry.abSeekCount++
                                trace(entry, "ab-seek-$start")
                            }
                        }
                    }
                }
            }
            MediaPlayer.Event.LengthChanged -> {
                entry.duration = event.lengthChanged.coerceAtLeast(0)
            }
            MediaPlayer.Event.ESAdded -> {
                val player = entry.player
                if (player != null) queueNative(entry.id, "restore-track-intent") {
                    if (!entry.disposed) {
                        try { restoreTrackIntent(entry, player) } catch (error: Exception) {
                            main.post { advancedError(entry, "LibVLC could not restore track selection") }
                        }
                    }
                }
                emitAdvanced(entry)
            }
            MediaPlayer.Event.ESDeleted, MediaPlayer.Event.ESSelected, MediaPlayer.Event.Vout -> emitAdvanced(entry)
        }
    }

    private fun restoreTrackIntent(entry: Entry, player: MediaPlayer) {
        entry.selectedAudioTrack?.let { track ->
            if (player.audioTrack != track && (track == -1 || player.audioTracks?.any { it.id == track } == true)) {
                check(player.setAudioTrack(track)) { "LibVLC rejected restored audio track" }
            }
        }
        entry.selectedSubtitleTrack?.let { track ->
            if (player.spuTrack != track && (track == -1 || player.spuTracks?.any { it.id == track } == true)) {
                check(player.setSpuTrack(track)) { "LibVLC rejected restored subtitle track" }
            }
        }
    }

    private fun subtitleUri(entry: Entry, uri: Uri): Uri {
        if (uri.scheme == "file") {
            val file = File(uri.path ?: throw IllegalArgumentException("Missing subtitle path"))
            require(file.isFile && file.canRead()) { "Subtitle file is not readable" }
        }
        if (uri.scheme != "content") return uri
        val file = File.createTempFile("privi-vlc-subtitle-", ".subtitle", activity.cacheDir)
        try {
            val input = activity.contentResolver.openInputStream(uri)
                ?: throw IllegalArgumentException("Content provider returned no subtitle stream")
            input.use { source -> file.outputStream().use { source.copyTo(it) } }
            entry.subtitleFiles.add(file)
            return Uri.fromFile(file)
        } catch (error: Exception) {
            file.delete()
            throw error
        }
    }

    private fun nativeCall(entry: Entry, result: MethodChannel.Result, stage: String, action: () -> Any?) {
        queueNative(entry.id, stage) {
            try {
                check(!entry.disposed) { "Player has been disposed" }
                val value = action()
                main.post { result.success(value) }
            } catch (error: Exception) {
                main.post { result.error("native_operation_failed", error.message, null) }
            }
        }
    }

    internal fun viewAttached(view: LibVlcVideoView) {
        val entry = entries[view.playerId] ?: return
        entry.views.remove(view)
        entry.views.add(view)
        if (entry.activeView !== view) {
            finishSurfaceFrameRequest(entry)
            entry.activeView?.setPresentationVisible(false)
            entry.activeView = view
            entry.player?.let { attach(entry, view) }
        }
        updateVisibility(entry)
        maybePlay(entry)
    }

    internal fun viewDetached(view: LibVlcVideoView) {
        val entry = entries[view.playerId] ?: return
        view.setPresentationVisible(false)
        if (entry.activeView !== view) return
        finishSurfaceFrameRequest(entry)
        suspendForSurfaceLoss(entry)
        entry.viewportAttached = false
        updateAwake(entry)
        if (entry.attachedView === view) {
            entry.player?.detachViews()
            entry.attachedView = null
            entry.surfacesReady = false
            entry.voutReady = false
        }
        entry.activeView = entry.views.lastOrNull { it !== view && it.attached }
        val next = entry.activeView
        if (next != null) {
            entry.player?.let { attach(entry, next) }
            updateVisibility(entry)
            maybePlay(entry)
        } else {
            // Route/PiP owners can hand a granted player to a new view on the next
            // frame. Keep the grant and intent, but never play without a surface.
            entry.surfaceRecovery?.let(main::removeCallbacks)
            entry.surfaceRecovery = null
        }
    }

    internal fun viewDisposed(view: LibVlcVideoView) {
        viewDetached(view)
        entries[view.playerId]?.views?.remove(view)
    }

    internal fun viewResized(view: LibVlcVideoView) {
        val entry = entries[view.playerId] ?: return
        if (entry.attachedView === view) entry.player?.updateVideoSurfaces()
    }

    internal fun viewVisibilityChanged(view: LibVlcVideoView) {
        val entry = entries[view.playerId] ?: return
        if (entry.disposed || entry.activeView !== view) return
        if (!view.presentable) {
            suspendForSurfaceLoss(entry)
        } else {
            updateSurfaceReadiness(entry, view)
            scheduleSurfaceRecovery(entry, view)
        }
    }

    internal fun viewSurfacesChanged(view: LibVlcVideoView) {
        val entry = entries[view.playerId] ?: return
        if (entry.disposed || entry.activeView !== view || entry.attachedView !== view) return
        if (!view.surfacesAvailable && entry.surfacesReady) suspendForSurfaceLoss(entry)
        updateSurfaceReadiness(entry, view)
        scheduleSurfaceRecovery(entry, view)
    }

    private fun suspendForSurfaceLoss(entry: Entry, forcePause: Boolean = false) {
        if (entry.disposed) return
        val hadSurface = entry.surfacesReady || entry.viewportAttached || entry.playing || forcePause
        entry.surfacesReady = false
        entry.viewportAttached = false
        if (hadSurface) {
            entry.surfaceLossCount++
            cancelPlaybackStart(entry)
            entry.surfaceGeneration++
            pauseForMissingViewport(entry)
            trace(entry, "surface-suspended")
        }
        if (entry.allowed && entry.wantsPlay) {
            entry.surfaceSuspended = true
            updateBuffering(entry)
        }
        updateAwake(entry)
        entry.activeView?.let { requestSurfaceFrame(entry, it) }
    }

    private fun updateSurfaceReadiness(entry: Entry, view: LibVlcVideoView) {
        entry.viewportAttached = entry.activeView === view && entry.attachedView === view && view.presentable
        entry.surfacesReady = entry.viewportAttached && entry.voutReady && view.surfacesAvailable
        if (entry.surfacesReady) finishSurfaceFrameRequest(entry)
        updateAwake(entry)
    }

    private fun emitSurfaceFrameRequest(entry: Entry, view: LibVlcVideoView, generation: Long, needsFrame: Boolean) {
        emit(entry, mapOf("event" to "surfaceRecovery", "viewId" to view.platformViewId,
            "generation" to generation, "needsFrame" to needsFrame))
    }

    private fun requestSurfaceFrame(entry: Entry, view: LibVlcVideoView) {
        if (entry.disposed || !entry.allowed || entry.initialized == null ||
            (!entry.wantsPlay && entry.player == null) || entry.activeView !== view ||
            !view.windowVisible || entry.surfacesReady) return
        if (entry.frameRequestView === view && entry.frameRequestGeneration != null) return
        if (entry.lastFrameRequestView === view && entry.lastFrameRequestGeneration == entry.surfaceGeneration) return
        finishSurfaceFrameRequest(entry)
        val generation = entry.surfaceGeneration
        entry.frameRequestView = view
        entry.frameRequestGeneration = generation
        entry.lastFrameRequestView = view
        entry.lastFrameRequestGeneration = generation
        emitSurfaceFrameRequest(entry, view, generation, true)
        trace(entry, "frame-request-$generation")
        entry.frameRequestTimeout = Runnable {
            if (entry.disposed || entry.frameRequestView !== view || entry.frameRequestGeneration != generation) return@Runnable
            entry.frameRequestTimeoutCount++
            trace(entry, "frame-timeout-$generation")
            // attach() can advance generation within this same recovery episode.
            // A timeout must not immediately start another request for that work.
            entry.lastFrameRequestGeneration = entry.surfaceGeneration
            finishSurfaceFrameRequest(entry)
            advancedError(entry, "Video surface recovery timed out; the paused frame or playback picture was not restored")
        }.also { main.postDelayed(it, SURFACE_FRAME_TIMEOUT_MS) }
    }

    private fun finishSurfaceFrameRequest(entry: Entry) {
        entry.frameRequestTimeout?.let(main::removeCallbacks)
        entry.frameRequestTimeout = null
        val view = entry.frameRequestView
        val generation = entry.frameRequestGeneration
        entry.frameRequestView = null
        entry.frameRequestGeneration = null
        if (view != null && generation != null) emitSurfaceFrameRequest(entry, view, generation, false)
        if (view != null && generation != null) trace(entry, "frame-finished-$generation")
    }

    private fun scheduleSurfaceRecovery(entry: Entry, view: LibVlcVideoView) {
        if (entry.disposed || !entry.allowed || entry.activeView !== view ||
            (!entry.wantsPlay && entry.player == null)) return
        entry.surfaceRecovery?.let(main::removeCallbacks)
        val generation = entry.surfaceGeneration
        entry.surfaceRecovery = Runnable {
            entry.surfaceRecovery = null
            if (entry.disposed || !entry.allowed || entry.activeView !== view ||
                (!entry.wantsPlay && entry.player == null) || entry.surfaceGeneration != generation ||
                !view.presentable) return@Runnable
            try {
                entry.viewportAttached = true
                // A paused, already-open player also owns a frame to present. Rebind
                // its vout independently of play intent; never create a preload player.
                entry.player?.let { player ->
                    if (entry.attachedView !== view || !player.vlcVout.areViewsAttached()) attach(entry, view)
                }
                updateSurfaceReadiness(entry, view)
                // A visible ancestor can precede Surface creation. No timer/polling:
                // holder callbacks and IVLCVout.Callback complete the handoff.
                maybePlay(entry)
            } catch (error: Exception) {
                fail(entry, "surface_recovery_failed", "LibVLC could not restore video surfaces (${error.javaClass.simpleName})")
            }
        }.also(main::post)
    }

    private fun updateVisibility(entry: Entry) {
        entry.views.forEach {
            it.setPresentationVisible(entry.allowed && entry.failure == null && it === entry.activeView)
        }
        updateAwake(entry)
    }

    private fun updateAwake(entry: Entry) {
        entry.views.forEach { view ->
            view.setPlaybackAwake(entry.preventsDisplaySleep && entry.allowed && entry.playing &&
                entry.viewportAttached && entry.surfacesReady && view === entry.activeView &&
                view.presentable && view.surfacesAvailable)
        }
    }

    private fun pause(entry: Entry) {
        entry.wantsPlay = false
        entry.inputRestarting = false
        entry.surfaceSuspended = false
        updateBuffering(entry)
        entry.surfaceRecovery?.let(main::removeCallbacks)
        entry.surfaceRecovery = null
        pauseForMissingViewport(entry)
        emit(entry, mapOf("event" to "isPlayingStateUpdate", "isPlaying" to false))
        if (entry.allowed && entry.player != null) entry.activeView?.let { scheduleSurfaceRecovery(entry, it) }
    }

    private fun updateBuffering(entry: Entry) {
        val buffering = !entry.disposed && entry.failure == null && entry.allowed &&
            (entry.nativeBuffering || entry.surfaceSuspended || entry.inputRestarting)
        if (buffering != entry.buffering) {
            entry.buffering = buffering
            emit(entry, mapOf("event" to if (buffering) "bufferingStart" else "bufferingEnd"))
        }
    }

    private fun pauseForMissingViewport(entry: Entry) {
        cancelPlaybackStart(entry)
        entry.playing = false
        updateAwake(entry)
        abandonFocus(entry)
        val player = entry.player
        if (player != null) queueNative(entry.id, "pause") {
            if (!entry.disposed) {
                try {
                    if (player.isPlaying) player.pause()
                } catch (error: Exception) {
                    main.post { advancedError(entry, "LibVLC could not pause playback (${error.javaClass.simpleName})") }
                }
            }
        }
    }

    private fun revoke(entry: Entry) {
        entry.allowed = false
        entry.nativeBuffering = false
        finishSurfaceFrameRequest(entry)
        entry.views.forEach { it.setPresentationVisible(false) }
        pause(entry)
    }

    /** Called on the Android main thread before lock/PiP state is revealed to Flutter. */
    fun revokePresentation() {
        check(Looper.myLooper() == Looper.getMainLooper()) { "Presentation must be revoked on the main thread" }
        entries.values.toList().forEach(::revoke)
    }

    private fun requestFocus(entry: Entry): Boolean {
        if (entry.mixWithOthers || focusOwner === entry) return true
        focusOwner?.let(::abandonFocus)
        val listener = AudioManager.OnAudioFocusChangeListener { change ->
            if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT ||
                change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK) {
                main.post { if (!entry.disposed) pause(entry) }
            }
        }
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build())
            .setOnAudioFocusChangeListener(listener, main)
            .setWillPauseWhenDucked(true)
            .build()
        if (audioManager.requestAudioFocus(request) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) return false
        entry.focusRequest = request
        entry.focusListener = listener
        focusOwner = entry
        return true
    }

    private fun abandonFocus(entry: Entry) {
        entry.focusRequest?.let(audioManager::abandonAudioFocusRequest)
        entry.focusRequest = null
        entry.focusListener = null
        if (focusOwner === entry) focusOwner = null
    }

    private fun trackMaps(entry: Entry, audio: Boolean): List<Map<String, Any?>> {
        val type = if (audio) IMedia.Track.Type.Audio else IMedia.Track.Type.Text
        val player = entry.player
        val selected = if (audio) entry.selectedAudioTrack ?: player?.audioTrack
            else entry.selectedSubtitleTrack ?: player?.spuTrack
        val descriptions = if (audio) player?.audioTracks else player?.spuTracks
        val metadata = entry.tracks.filter { it.type == type }
        if (descriptions != null && descriptions.isNotEmpty()) {
            return descriptions.map { description ->
                val track = metadata.firstOrNull { it.id == description.id }
                mapOf("id" to description.id.toString(), "title" to (description.name ?: track?.description ?: ""),
                    "language" to (track?.language ?: ""), "isSelected" to (selected == description.id))
            }
        }
        val tracks = metadata.map { track ->
            mapOf("id" to track.id.toString(), "title" to (track.description ?: ""),
                "language" to (track.language ?: ""), "isSelected" to (selected == track.id))
        }
        return if (!audio) listOf(mapOf("id" to "-1", "title" to "Disable", "language" to "",
            "isSelected" to (selected == -1))) + tracks else tracks
    }

    private fun advancedState(entry: Entry): Map<String, Any?> = mapOf(
        "displayWidth" to entry.width, "displayHeight" to entry.height,
        "audioTracks" to trackMaps(entry, true), "subtitleTracks" to trackMaps(entry, false),
        "supportsAudioTracks" to true, "supportsSubtitles" to true,
        "supportsExternalSubtitles" to true, "supportsAudioDelay" to true,
        "supportsSubtitleDelay" to true, "supportsAbLoop" to true,
        "audioDelay" to entry.audioDelay,
        "subtitleDelay" to entry.subtitleDelay,
        "abLoopStart" to entry.abStart, "abLoopEnd" to entry.abEnd,
        "error" to entry.failure?.message,
    )

    private fun emitAdvanced(entry: Entry) {
        if (!entry.disposed) emit(entry, mapOf("event" to "advanced", "state" to advancedState(entry)))
    }

    private fun advancedError(entry: Entry, message: String) {
        if (!entry.disposed) emit(entry, mapOf("event" to "advanced", "state" to (advancedState(entry) + ("error" to message))))
    }

    private fun diagnostics(entry: Entry): Map<String, String> {
        val now = SystemClock.elapsedRealtime()
        val preparation = enginePreparation
        val result = linkedMapOf(
            "engine" to "libvlc", "engine-version" to (if (libVlc != null) LibVLC.version() else "unavailable"),
            "render-surface" to "SurfaceView", "display-width" to entry.width.toString(),
            "display-height" to entry.height.toString(),
            "playback-rate" to (entry.player?.rate?.toString() ?: entry.speed.toString()),
            // Configured rate and lifecycle counters are probes, not displayed FPS.
            "playback-rate-requested" to entry.speed.toString(),
            "rate-request-count" to entry.rateRequestCount.toString(),
            "font-cache-valid" to (fontCacheValid?.toString() ?: "not-built"),
            "font-cache-build-ms" to (fontCacheBuildMs?.toString() ?: "not-built"),
            "engine-preparation-stage" to enginePreparationStage,
            "engine-preparation-error" to (enginePreparationFailure?.code ?: "none"),
            "engine-preparation-ms" to (preparation?.startedAt?.let { (preparation.finishedAt ?: now) - it }?.toString() ?: "not-started"),
            "engine-queue-wait-ms" to (preparation?.let { (it.startedAt ?: it.finishedAt ?: now) - it.queuedAt }?.toString() ?: "not-queued"),
            "media-initialization-stage" to entry.initializationStage,
            "media-initialization-ms" to (entry.initializationStartedAt?.let { (entry.initializationFinishedAt ?: now) - it }?.toString() ?: "not-started"),
            "media-queue-wait-ms" to (entry.initializationQueuedAt?.let { (entry.initializationStartedAt ?: entry.initializationFinishedAt ?: now) - it }?.toString() ?: "not-queued"),
            "input-reopen-count" to entry.inputReopenCount.toString(),
            "input-restarting" to entry.inputRestarting.toString(),
            "pending-seek-ms" to (entry.pendingPosition?.toString() ?: "none"),
            "native-player-created" to (entry.player != null).toString(),
            "active-view-id" to (entry.activeView?.platformViewId?.toString() ?: "none"),
            "active-view-attached" to (entry.activeView?.attached == true).toString(),
            "active-view-window-visible" to (entry.activeView?.windowVisible == true).toString(),
            "active-view-presentable" to (entry.activeView?.presentable == true).toString(),
            "native-is-playing" to (entry.player?.isPlaying?.toString() ?: "false"),
            "native-is-seekable" to (entry.player?.isSeekable?.toString() ?: "unopened"),
            "native-player-state" to (entry.player?.playerState?.toString() ?: "unopened"),
            "subtitle-track-intent" to (entry.selectedSubtitleTrack?.toString() ?: "automatic"),
            "subtitle-track-actual" to (entry.player?.spuTrack?.toString() ?: "unopened"),
            "subtitle-track-ids" to (entry.player?.let { player ->
                player.spuTracks?.joinToString(prefix = "[", postfix = "]") { it.id.toString() } ?: "unavailable"
            } ?: "unopened"),
            "audio-delay-intent-us" to entry.audioDelay.toString(),
            "audio-delay-actual-us" to (entry.player?.audioDelay?.toString() ?: "unopened"),
            "subtitle-delay-intent-us" to entry.subtitleDelay.toString(),
            "subtitle-delay-actual-us" to (entry.player?.spuDelay?.toString() ?: "unopened"),
            "ab-loop-start-ms" to (entry.abStart?.toString() ?: "none"),
            "ab-loop-end-ms" to (entry.abEnd?.toString() ?: "none"),
            "ab-seek-count" to entry.abSeekCount.toString(),
            "presentation-allowed" to entry.allowed.toString(),
            "play-requested" to entry.wantsPlay.toString(),
            "viewport-presentable" to entry.viewportAttached.toString(),
            "surface-ready" to entry.surfacesReady.toString(),
            "surface-suspended" to entry.surfaceSuspended.toString(),
            "surface-generation" to entry.surfaceGeneration.toString(),
            "surface-loss-count" to entry.surfaceLossCount.toString(),
            "surface-attach-count" to entry.surfaceAttachCount.toString(),
            "surface-frame-request-active" to (entry.frameRequestGeneration != null).toString(),
            "surface-frame-request-timeouts" to entry.frameRequestTimeoutCount.toString(),
            "play-start-generation" to (entry.playbackStart?.generation?.toString() ?: "none"),
        )
        entry.tracks.filterIsInstance<IMedia.VideoTrack>().firstOrNull()?.let { track ->
            result["video-codec"] = track.codec ?: ""
            result["video-width"] = track.width.toString()
            result["video-height"] = track.height.toString()
            if (track.frameRateDen > 0) result["video-fps"] = (track.frameRateNum.toDouble() / track.frameRateDen).toString()
        }
        entry.source?.media?.stats?.let { stats ->
            result["decoded-video"] = stats.decodedVideo.toString()
            result["displayed-pictures"] = stats.displayedPictures.toString()
            result["lost-pictures"] = stats.lostPictures.toString()
            result["decoded-audio"] = stats.decodedAudio.toString()
            result["played-audio-buffers"] = stats.playedAbuffers.toString()
            result["lost-audio-buffers"] = stats.lostAbuffers.toString()
            result["demux-corrupted"] = stats.demuxCorrupted.toString()
            result["demux-discontinuity"] = stats.demuxDiscontinuity.toString()
            result["input-bitrate"] = stats.inputBitrate.toString()
            result["demux-bitrate"] = stats.demuxBitrate.toString()
        }
        return result + nativeQueueDiagnostics()
    }

    /** Lifecycle boundaries only: no file names, URIs, or per-frame logging. */
    private fun trace(entry: Entry, action: String) {
        val view = entry.activeView
        Log.i(TAG, "$action id=${entry.id} view=${view?.platformViewId} " +
            "allowed=${entry.allowed} wanted=${entry.wantsPlay} playing=${entry.playing} " +
            "created=${entry.player != null} shown=${view?.presentable} window=${view?.windowVisible} " +
            "ready=${entry.surfacesReady} generation=${entry.surfaceGeneration} " +
            "reopen=${entry.inputReopenCount} restarting=${entry.inputRestarting} pending=${entry.pendingPosition} " +
            "request=${entry.frameRequestGeneration} starting=${entry.playbackStart?.generation}")
    }

    private fun emit(entry: Entry, event: Map<String, Any?>) {
        if (!entry.disposed) entry.sink?.success(event)
    }

    private fun fail(entry: Entry, code: String, message: String) {
        if (entry.disposed || entry.failure != null) return
        Log.e(TAG, queueTimeoutMessage("$code id=${entry.id}"))
        entry.failure = Failure(code, message)
        engineWaiters.remove(entry)
        entry.queueTimeout?.let(main::removeCallbacks)
        entry.queueTimeout = null
        entry.openTimeout?.let(main::removeCallbacks)
        entry.openTimeout = null
        if (entry.initialized == null) {
            entry.initializationStage = "failed"
            entry.initializationFinishedAt = SystemClock.elapsedRealtime()
        }
        revoke(entry)
        entry.sink?.error(code, message, null)
        emitAdvanced(entry)
    }

    private fun releaseSource(source: Source, playerId: Int?, onReleased: (Failure?) -> Unit) {
        queueNative(playerId, "release-late-source") {
            val failure = safelyRelease(source)
            main.post { onReleased(failure) }
        }
    }

    private fun safelyRelease(source: Source): Failure? {
        return try {
            source.release(::nativeStage)
            null
        } catch (error: Exception) {
            val stage = (error as? SourceCleanupException)?.stage ?: "release-source"
            val type = error.cause?.javaClass?.simpleName ?: error.javaClass.simpleName
            Log.e(TAG, "Media release failed stage=$stage ($type)")
            Failure("dispose_failed", "LibVLC source cleanup failed at $stage ($type)")
        }
    }

    private fun replyDisposed(result: MethodChannel.Result, failure: Failure?) {
        if (failure == null) result.success(null)
        else result.error(failure.code, failure.message, null)
    }

    private fun completeDisposal(entry: Entry) {
        val disposal = entry.disposal ?: return
        if (!disposal.releaseFinished || entry.mediaOpenPending) return
        disposal.failure = disposal.failure ?: entry.cleanupFailure
        pendingDisposals.remove(entry.id)
        disposal.failure?.let { disposalFailures[entry.id] = it }
        val results = disposal.results.toList()
        disposal.results.clear()
        results.forEach { replyDisposed(it, disposal.failure) }
    }

    private fun disposeEntry(entry: Entry, result: MethodChannel.Result? = null) {
        val existing = entry.disposal
        if (existing != null) {
            result?.let(existing.results::add)
            completeDisposal(entry)
            return
        }
        val disposal = Disposal()
        result?.let(disposal.results::add)
        entry.disposal = disposal
        pendingDisposals[entry.id] = entry
        engineWaiters.remove(entry)
        entry.queueTimeout?.let(main::removeCallbacks)
        entry.queueTimeout = null
        entry.initializationStage = "disposed"
        entry.initializationFinishedAt = entry.initializationFinishedAt ?: SystemClock.elapsedRealtime()
        entry.allowed = false
        entry.wantsPlay = false
        entry.playing = false
        entry.inputRestarting = false
        entry.surfaceSuspended = false
        entry.nativeBuffering = false
        entry.buffering = false
        finishSurfaceFrameRequest(entry)
        entry.viewportAttached = false
        cancelPlaybackStart(entry)
        entry.surfaceGeneration++
        entry.views.forEach { it.setPresentationVisible(false) }
        entry.openTimeout?.let(main::removeCallbacks)
        entry.playerTimeout?.let(main::removeCallbacks)
        entry.surfaceRecovery?.let(main::removeCallbacks)
        abandonFocus(entry)
        entry.disposed = true
        entries.remove(entry.id)
        entry.eventChannel.setStreamHandler(null)
        entry.sink = null
        val player = entry.player
        fun detach(action: () -> Unit) {
            try { action() } catch (error: Exception) {
                Log.e(TAG, "Player detachment failed (${error.javaClass.simpleName})")
                disposal.failure = disposal.failure ?: Failure("dispose_failed",
                    "LibVLC player detachment failed (${error.javaClass.simpleName})")
            }
        }
        detach { player?.setEventListener(null) }
        detach { player?.vlcVout?.removeCallback(entry.voutCallback) }
        // detachViews must run before native release, while Android views are on main.
        detach { player?.detachViews() }
        detach { entry.source?.media?.setEventListener(null) }
        val source = entry.source
        entry.views.clear()
        entry.activeView = null
        entry.attachedView = null
        entry.player = null
        entry.source = null
        if (player == null && source == null) {
            // No source has been published, so subtitle import could not own
            // files either. A still-running open remains a separate barrier;
            // an entry merely waiting for shared fonts owns nothing to release.
            disposal.releaseFinished = true
            completeDisposal(entry)
            return
        }
        queueNative(entry.id, "release-player") {
            var failure: Failure? = null
            try {
                player?.release()
            } catch (error: Exception) {
                Log.e(TAG, "Player release failed (${error.javaClass.simpleName})")
                failure = Failure("dispose_failed", "LibVLC player release failed (${error.javaClass.simpleName})")
            } finally {
                val sourceFailure = source?.let(::safelyRelease)
                failure = failure ?: sourceFailure
                nativeStage("release-subtitle-files")
                entry.subtitleFiles.forEach { file ->
                    try {
                        check(!file.exists() || file.delete()) { "Temporary subtitle cleanup failed" }
                    } catch (error: Exception) {
                        Log.e(TAG, "Temporary subtitle cleanup failed (${error.javaClass.simpleName})")
                        failure = failure ?: Failure("dispose_failed", "Temporary subtitle cleanup failed (${error.javaClass.simpleName})")
                    }
                }
                entry.subtitleFiles.clear()
                val cleanupFailure = failure
                main.post {
                    disposal.failure = disposal.failure ?: cleanupFailure
                    disposal.releaseFinished = true
                    completeDisposal(entry)
                }
            }
        }
    }

    fun dispose() {
        if (closed) return
        closed = true
        enginePreparation?.let { preparation ->
            preparation.cancelled = true
            preparation.timeout?.let(main::removeCallbacks)
            preparation.queueTimeout?.let(main::removeCallbacks)
            preparation.timeout = null
            preparation.queueTimeout = null
            if (preparingEngine) {
                preparation.finishedAt = SystemClock.elapsedRealtime()
                enginePreparationStage = "cancelled"
            }
        }
        channel.setMethodCallHandler(null)
        activity.unregisterReceiver(screenOffReceiver)
        entries.values.toList().forEach { disposeEntry(it) }
        maybeShutdownQueue()
    }

    private fun maybeShutdownQueue() {
        // An open completing after dispose still owns a Media/descriptor. Its main-thread
        // handoff must enqueue cleanup before the final engine release and queue shutdown.
        if (!closed || preparingEngine || pendingCreations != 0 || queueShutdown) return
        queueShutdown = true
        queueNative(null, "release-engine") {
            try { libVlc?.release() } catch (error: Exception) {
                Log.e(TAG, "Engine release failed (${error.javaClass.simpleName})")
            }
            libVlc = null
        }
        nativeQueue.shutdown()
    }
}
