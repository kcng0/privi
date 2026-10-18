# Subtitle corrections for the fixed 3.7.7 source

Apply these patches after the 20 official JNI patches, in the order fixed by
`../source-lock.json`. Rebuild core, all bundled modules and JNI for every ABI;
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

Local checks use the actual patched functions with external Python integer
oracles, comparison against the official legacy selection implementation and
temporary C/UBSan probes. The arithmetic helper compiles for Android armv7,
arm64 and x86_64. These checks do not establish Android presentation success.
The final SDK and signed APK must still show the expected embedded/external
Chinese ASS captions during playback, paused seeks, track disable/reselect,
negative delay and A/B loops in the existing native acceptance path.

User entry: open a video with the built-in player, then use **Audio tracks and
subtitles / Advanced playback → Subtitle delay**. The original reproduction
uses a -250 ms delay; paused track reselect is a separate display case.
