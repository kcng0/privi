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
