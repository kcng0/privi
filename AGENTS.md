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
