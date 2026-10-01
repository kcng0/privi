# Privi Android disposal patch

This is the official `media_kit_video` **2.0.1** package, retained under its
original MIT license in `LICENSE`.

- Archive: <https://pub.dev/api/archives/media_kit_video-2.0.1.tar.gz>
- Archive SHA-256: `afaa509e7b7e0bf247557a3a740cde903a52c34ace9810f94500e127bd7b043d`
- Upstream: <https://github.com/media-kit/media-kit>
- Excluded from the archive: example, test, doc/docs, and repository metadata
  directories. All package libraries, plugin metadata, and platform sources are
  retained. Only the Android controller implementation is patched.

## Failure and scope

On Android, an asynchronous `videoParams` listener can still be awaiting
`VideoOutputManager.SetSurfaceSize` when `Player.dispose()` releases the video
controller. Version 2.0.1 disposes `rect` before canceling the stream subscription.
Canceling a Dart stream subscription does not wait for Futures returned by its
already-started `onData` callbacks. The pending callback then writes to the
disposed `ValueNotifier<Rect?>`. A `wid` listener can similarly call mpv after
`NativePlayer.disposed` becomes true, including during a failed hardware-decoder
attempt followed by software retry.

The patch in `lib/src/video_controller/android_video_controller/real.dart`:

1. Marks the controller closing, detaches the `wid` listener, and removes native
   message routing synchronously before the first teardown await.
2. Checks both controller ownership and `NativePlayer.disposed` at callback
   entry and after asynchronous boundaries. Canceled callbacks finish without
   changing notifiers, submitting new surface resizes, or accessing mpv.
3. Keeps notifiers alive until native output release has been attempted, and
   releases them even if native teardown fails. Teardown returns the same Future
   if invoked again; failures are propagated rather than converted to success.
4. Rechecks a queued seek after taking `NativePlayer.lock`, then calls
   `NativePlayer.seek(..., synchronized: false)` inside that lock. This preserves
   normal serialization while rejecting seeks queued behind player disposal.

Teardown deliberately does **not** drain the video-controller lock while holding
`NativePlayer.lock`: the inverse ordering would deadlock a `wid` callback waiting
to seek. Pending callbacks instead observe canceled ownership before their next
side effect. A previously submitted resize cannot recreate a released native
output: `VideoOutputManager.setSurfaceSize` only updates handles still present
in its existing output map; it does not create outputs.

The `@visibleForTesting` constructor exercises the actual controller with fake
mpv effects and a controlled platform channel, without allocating a decoder.
No production bridge, native plugin source, rendering option, or other platform
implementation is changed by this patch.

## Verification and removal

`test/data/media_kit_android_disposal_test.dart` covers a late surface reply,
queued metadata, a delayed handle, stale native resize messages, suspended
property updates, the native-disposed-before-release window, seek/dispose lock
ordering, ordinary size/seek behavior, and propagation of native teardown errors.

When upgrading, compare the upstream Android callback and disposal lifecycle
against these cases before removing the root `dependency_overrides` entry. At
the time this patch was prepared, pub.dev's latest release was still 2.0.1 and
the upstream main branch retained the same disposal ordering. Its most recent
change to this file was commit
`d310049f24196250d876efb02b9ff56fa9ef5068` (seek to current position).
