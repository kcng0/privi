# Subtitle corrections for the fixed 3.7.7 source

Apply these patches after the 20 official JNI patches, in the order fixed by
`../source-lock.json`. Each entry explicitly targets VLC or JNI (VLC is the
default); the fourth patch changes JNI rather than the VLC repository. Rebuild core, all bundled modules and JNI for every ABI;
the added subpicture state changes the internal native ABI.

`0001` separates raw cue validity from converted system dates. Applying an ES
delay before the old `> 0` check lost valid early cues, including a cue starting
at 2 us with a -250 ms delay. The new subtitle conversion applies delay before
rate scaling and accepts successful zero/negative system dates. Known stops,
same-date ephemeral cues, pause offsets and the existing OSD time domain remain
explicit. Audio/video retain their existing clock-conversion entry point.

Portable wide intermediate arithmetic preserves representable results on
armv7 as well as 64-bit targets. An unrepresentable stored date, interval or
buffering value reports a timing error through the existing fatal playback
event. It does not clamp a delay or silently drop a failed conversion. A
temporarily unavailable clock reference retains the existing nonfatal behavior.
The form also checks milliseconds-to-microseconds conversion before `Duration`
can wrap an input. No new subtitle filter is enabled.

`0002` invalidates the Android subtitle preparation cache after clearing the
surface, changing its format or failing a buffer lock. It records a reusable
order/region only after successful buffer preparation. This keeps the existing
cache for unchanged captions and permits the same caption to be drawn again
after a track transition. It is a preparation cache, not a presentation ack.

`0003` aligns external slave seek selection with the delayed subtitle timeline.
It restores every active overlapping cue and the latest unknown-stop group;
seek replay skips expired history before queuing it. Ordinary future cues keep
their normal order. A seek that precedes the first slave-time declaration is
resolved when that declaration arrives. Standalone subtitle playback retains
its original clock scheduling. SPU packet preroll compares known delayed ends
with the master seek target; zero/unknown durations are not proof of expiry.
Audio/video and the decoder's existing preroll filter remain in place. New
unrepresentable demux dates report a dedicated input timing error using the
actual demux input owner; ordinary EOF/old slave read errors are unchanged.

`0004` matches JNI nativeSetTime's C return type to the existing Java `long`
signature. It returns the contemporaneous SDK position, or -1 without an owner.
That query can still report the old position: it is not a seek acceptance or
completion acknowledgement. The app submits seeks after identity/seekability
checks, ignores this return value and judges recovery by actual playback.

`0005` completes decoder buffering when a paused seek reaches master EOF
before the normal cache threshold. It invokes the existing forced-buffering
completion path and ignores its empty result; the input stays paused, without
ending, repeating, reopening or submitting another seek. Without a usable clock
reference it retains buffering rather than inventing a ready frame.

`0006` grants the paused video/SPU seek frame after the decoder flush callback
returns. MediaCodec output that is still arriving during the pending flush can
otherwise consume the new seek's single-frame allowance, leaving the old image
on screen. The flush branch already runs before the paused/countdown gate;
existing positive frame-step counts remain intact. MediaCodec flush waits for
its output thread, and software decoders submit from the decoder thread. This
is not a claim that every optional codec implements a synchronous output flush.

Local checks use the actual patched functions with external Python integer
oracles, comparison against the official legacy selection implementation and
temporary C/UBSan probes. The arithmetic helper compiles for Android armv7,
arm64 and x86_64. These checks do not establish Android presentation success.
The final SDK and signed APK must still show the expected embedded/external
Chinese ASS captions during playback, paused seeks, track disable/reselect,
negative/positive delay, overlapping cue seeks and A/B loops in the existing native acceptance path.

User entry: open a video with the built-in player, then use **Audio tracks and
subtitles / Advanced playback → Subtitle delay**. The original reproduction
uses a -250 ms delay; paused track reselect is a separate display case.
