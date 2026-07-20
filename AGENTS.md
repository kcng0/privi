# Project Agent Notes

## Root lock overlay invariant

- Trigger signal: auto-lock appears only after leaving a viewer/album route, or
  unlock resets the selected Visible/Invisible tab.
- Root cause: the lock screen is rendered inside the home route, or locking
  replaces and disposes `HomeShell` while another route remains above it.
- Correct approach: render authentication above the app Navigator, keep the app
  Navigator mounted, and disable its pointer, focus, and semantics while locked.
- Verification: cover a pushed private route with the lock overlay, unlock,
  confirm the route is retained, then pop it and confirm the selected tab is
  unchanged. Keep lifecycle and biometric regression tests passing.
- Scope: all lock transitions, including background resume, screen off/on,
  biometric prompts, VLC, and external picture viewers.

## Folder view preference invariant

- Trigger signal: sort, filter, or grid style resets after reopening a folder,
  or changing one folder unexpectedly changes another folder.
- Root cause: folder UI state is kept only in a screen State object or stored in
  global `AppSettings` without a source/folder namespace.
- Correct approach: use `MediaViewScope` for Visible folders and Invisible
  albums. Keep ordered sort criteria immutable; selection order is priority.
- Verification: recreate the provider container and confirm restoration, verify
  same-id Visible/Invisible scopes remain isolated, and exercise the sort-mode
  toggle and localized filter widgets.
- Scope: folder sort mode/criteria, rating/Hearts filters, and media-grid columns.
  Search remains ephemeral; home, playback, and security settings stay global.

## External playlist completion invariant

- Trigger signal: VLC Back advances the playlist, or a naturally completed
  external video returns to Privi without opening the next item.
- Root cause: an Android Activity Result only proves that the external player
  returned. VLC reports the same result code for Back and completion, and some
  versions reset their returned position/duration to 0/0 at natural end.
- Correct approach: normalize the tracked Activity Result into a one-shot
  `completed`/`interrupted` outcome. Advance only an active playlist hand-off;
  Back and unknown external-player results must remain on the current item.
- Verification: cover near-end VLC metadata, VLC's reset-at-end 0/0 result,
  quick Back, missing metadata, unrelated external viewers, lock bypass, and
  the player screen's two-step system Back behavior.
- Scope: Android external video playlist playback. iOS continues to use the
  built-in player until it gains an explicit external hand-off contract.

## In-app video interaction invariant

- Trigger signal: system Back changes the media item, a seek gesture flips the
  Viewer page, landscape retains a top bar, or leaving playback keeps the app
  orientation locked.
- Root cause: route navigation, PageView gestures, video gestures, and system
  UI lifecycle are handled by overlapping widgets without one owner.
- Correct approach: video owns horizontal drag/double-tap seeking; dedicated
  bottom buttons own Previous/Next; system Back hides visible controls before
  exiting; landscape video hides top chrome; route disposal restores system UI
  and supported orientations.
- Verification: cover two-step system Back and immediate top-bar Back, seek
  direction/magnitude limits, narrow landscape controls, persisted seek time,
  Viewer manual navigation, and absence of the Viewer delete action.
- Scope: built-in video playback in playlist and Viewer routes on Android and
  iOS. External-player completion remains governed by the separate invariant.
