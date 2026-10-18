# Development Guide

How to stand up the toolchain and work on **Privi**. Product docs that used to
live under `docs/` are kept local-only and are not part of the published repo.

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Flutter SDK | **3.44.6** | Pinned via [`.fvmrc`](./.fvmrc) → use FVM. |
| Dart | bundled with Flutter | — |
| Java (JDK) | 17+ | Needed for Android Gradle. |
| Android SDK | platform **37** + build-tools + cmdline-tools | Licenses accepted. |
| Shorebird CLI | current stable | Needed only for local base-release/patch validation. |
| A device | Android 8.0 (API 26)+ | Real device recommended; install **VLC** to test external playback. |

## Fastest path: one-shot installer

On a fresh Ubuntu/WSL2 machine:

```bash
./scripts/install-toolchain.sh   # Flutter + Android SDK + licenses + PATH
source ~/.bashrc                 # pick up PATH
./scripts/bootstrap.sh           # native scaffold + deps + codegen
make run
```

The installer is idempotent (safe to re-run) and does **not** modify project
sources.

### WSL2 + physical device

1. Install `adb` on **Windows** (Android platform-tools).
2. On Windows: `adb kill-server && adb -a -P 5037 nodaemon server` (or use a
   USBIPD / usbip bridge so Linux sees the device).
3. In WSL: `export ADB_SERVER_SOCKET=tcp:<windows-host-ip>:5037` if using a
   shared adb server, then `adb devices`.
4. Confirm with `flutter devices`.

If the device never appears, fall back to wireless debugging
(`adb connect <phone-ip>:5555`) on the same LAN.

---

## 1. Install Flutter (via FVM — recommended)

```bash
dart pub global activate fvm      # or: curl -fsSL https://fvm.app/install.sh | bash

# From the repo root — installs the pinned Flutter and links .fvm/flutter_sdk
fvm install
fvm use 3.44.6
```

Prefer a plain global Flutter? Install from
https://docs.flutter.dev/get-started and skip FVM; the `Makefile`/scripts fall
back to `flutter` automatically.

## 2. Install the Android SDK

Easiest via Android Studio (SDK Manager) or `sdkmanager` cmdline-tools:

```bash
sdkmanager "platform-tools" "platforms;android-37" "build-tools;36.0.0"
yes | sdkmanager --licenses
flutter config --android-sdk "$ANDROID_HOME"
flutter doctor            # resolve anything still red
```

## 3. Bootstrap the project

Generates native scaffolding (when needed), fetches deps, runs codegen — **safe
to re-run**:

```bash
./scripts/bootstrap.sh
# or:  make bootstrap
```

What it does:

1. `flutter create --platforms=android --org com.privi .` to produce /
   refresh the `android/` project.
2. **Restores** hand-authored files (`pubspec.yaml`, `lib/`, `test/`, …) from
   git so `flutter create` cannot clobber them.
3. `flutter pub get` + `build_runner build`.

> ⚠️ Commit (or stash) local work before bootstrap if you have uncommitted
> changes you care about — the restore step checks out owned paths from `HEAD`.

## 4. Everyday commands

```bash
make run       # launch on a connected device
make test      # run tests
make analyze   # static analysis (flutter_lints + riverpod_lint)
make format    # dart format lib test
make watch     # code generation in watch mode (drift + riverpod)
make gen       # one-shot code generation
make apk       # release APK for sideloading
make help      # list all targets
```

Without `make`, prefix with `fvm ` (or nothing), e.g. `fvm flutter test`.

## Media consistency contract

Visible and Invisible grids share `MediaThumbnailSpec`: 768 px, quality 90,
and the one-second frame for videos. Both flows use one injected, bounded poster
cache. Hide may synchronously reuse bytes already rendered by Visible, but it
must not start or await extraction before a native transfer. Cache misses move
first and generate from the vault file afterward. Invisible poster decoding
sets the 768 px width only and lets `BoxFit.cover` crop the preserved source
ratio. Versioned thumbnail paths let launch maintenance upgrade old
low-resolution video posters once and retry explicit failures on a later
launch.

Date sorting also crosses the Hide boundary unchanged. Visible MediaStore
pagination must query `createDate`, while vault queries use
`dateTaken ?? dateAdded` and the exact source filename as their deterministic
tie-breaker. Modified time and Hide time are not valid chronology inputs.

## Media view preference contract

Home-level preferences remain in `AppSettings`: photo/video mode, album columns,
and the default media-grid columns for a folder with no saved override. Each
Visible folder and Invisible album has a separate `MediaViewScope`, namespaced by
source and stable folder id. That scope persists grid columns, rating/Hearts
filters, single/multi sort mode, and its ordered sort criteria. Search text is
session-only and must not be persisted.

Visible and Invisible keep separate tab-level List/Mosaic choices. The selected
choice applies both to the tab's folder/album shelf and to media inside an opened
folder/album; list rows retain thumbnails, video durations, selection, and
Invisible heart ratings. Per-folder grid-column overrides remain stored even
while List mode is active and take effect again when the tab returns to Mosaic.

The first multi-sort criterion is primary. Later selections append as
tie-breakers, while changing ascending/descending within one family replaces the
criterion in place. The picker displays numeric priority badges. Switching back
to single sort keeps the primary criterion only.

`test/application/media_view_preferences_test.dart` verifies persistence and
scope isolation. `test/widget/media_preferences_ui_test.dart` verifies the
single/multi control, priority order, and localized Hearts label.

## Lock lifecycle and navigation contract

The credential UI is a root overlay above the app Navigator. Locking must keep
the app Navigator and `HomeShell` mounted so pushed media routes and the selected
Visible/Invisible tab retain their state. While locked, the underlying app is
excluded from pointer input, focus, and accessibility semantics.

Lifecycle events decide only whether the vault is locked; they must not select a
tab or replace the navigation stack. A tracked VLC or external picture-viewer
Activity Result may bypass re-authentication. Home/task switching and screen
off/on must show the root credential overlay immediately on resume. Biometric
`inactive -> resumed` transitions must preserve a successful authentication.

`test/widget/app_smoke_test.dart` verifies the root overlay and navigation-state
retention. `test/application/lock_controller_lifecycle_test.dart` verifies the
resume and biometric state machine.

## Built-in video controls contract

`PlayerScreen`, the Invisible `ViewerScreen`, and the Visible
`GalleryPreviewScreen` share the same interaction timing. Visible video controls
hide after three seconds without input; an active pointer keeps them visible,
and the countdown restarts when the final pointer is released.

The current title stays at the top; playback/Previous/Next occupy the center;
the timeline, elapsed/total time, and playback tools remain at the bottom in
both orientations. Touch lock disables gestures and tools until explicitly
unlocked. Video Back exits; an open settings/track panel is dismissed first.
Vertical swipes on the left adjust window brightness and those on the right
adjust media volume. Heart rating remains in the settings sheet.
Long press hides the regular controls and shows only a temporary 2x badge;
speed changes and restoration are serialized for that controller. The chosen
persistent speed is unchanged. Horizontal swipes keep playback running, update
only the time feedback, and submit one exact seek on release. They do not start
a second preview decoder. Timeline scrubbing retains bounded thumbnail previews,
but release cancels queued previews immediately, before awaiting the final seek;
an already-running platform decode may finish and its result is discarded.
Android exact seeking permits the decoder to drop eligible frames before the
target, rather than forcing every pre-target frame through full decoding.
An active scrub/seek suppresses automatic
playlist advancement until it settles; if a playing video naturally finishes
during a swipe, restarting at its chosen target still requires the lifecycle
owner's current playback permission.

Default orientation follows Android's `FULL_SENSOR`, independently of the
system rotation lock. The session direction menu and axis-lock control survive
media changes; global defaults and the last locked axis are stored separately.
Leaving playback restores the original orientation request. Large-screen or
multi-window restrictions may override the requested direction, so layout uses
the actual viewport rather than assuming a successful device rotation.

`VideoViewport` selects one sizing owner. Android delegates the entire bounded
viewport to LibVLC's native `VLCVideoLayout`; Flutter does not also scale its
SurfaceViews. iOS retains the Flutter viewport. Best fit contains; Fit screen
covers and crops; Fill stretches; Original uses physical video pixels. Explicit
ratios apply in display coordinates. LibVLC applies rotation/SAR to output once;
the bridge reports corrected display dimensions with rotationCorrection zero.
Unknown dimensions never initialize as an invented 16:9 image. Native layout uses
the actual view bounds, independently of the Activity's requested orientation.

Android production playback uses `org.videolan.android:libvlc-all:3.7.7` with
`MediaPlayer.attachViews(..., subtitles=true, textureView=false)`. Flutter hybrid
composition embeds the actual video/subtitle SurfaceViews; neither mpv copy-back
nor a Flutter video Texture is on this production path. iOS keeps AVFoundation.
`video_player` remains the public controller facade. Optional advanced ports
expose tracks, local subtitles, audio/subtitle delays, A–B repeat and diagnostics.
LibVLC enables audio time stretching and automatic hardware decoding with its
software fallback; speed changes update the existing player's native rate.
Android explicitly uses the fixed Flutter version's supported Skia UI renderer.
Its Impeller GLES teardown can leave a context current on the former merged
thread after a PiP ImageReader is abandoned on screen-off. This is a UI renderer
compatibility choice; video and subtitles remain native SurfaceViews. Reassess
the opt-out when upgrading Flutter: it is deprecated upstream and must not hide
rendering failures. Native recovery and the final signed APK require real
screen-off/return acceptance before publishing.
The bundled Noto CJK font is made available to native subtitle rendering.
The first LibVLC initialization builds the system font cache on its background
queue, before playback. Cache validity and elapsed time are diagnostic values;
an unwritable cache warns and leaves rendering available, matching the SDK's
contract. ASS uses `ssa-fontsdir`; other text uses the SDK's platform font family.
Shared engine/font preparation has its own 60-second deadline, starting when
that work actually starts on the native queue. Each media's 25-second open/parse
deadline starts when its own open task begins; waiting for shared preparation
does not consume it. Queue starvation has a separate 25-second error. A blocking
SDK font-cache call has no cancellation API: cancellation rejects its delivery
and releases a late engine after the call returns, without concurrently freeing
native code still in use. Initialization diagnostics expose these stages even
while that queue is busy. These failure bounds are not startup performance goals;
the actual release smoke retains its independent 30-second first-picture gate.

Creation returns a disposable id before asynchronous parsing can fail. Parsed
metadata initializes the facade without opening a decoder. A preloaded item owns
metadata, not an active MediaPlayer: decoding starts only after play is requested,
a native viewport is attached and the playback permission owner grants
presentation. Fatal LibVLC player events propagate as video_player errors; SDK
logs are not treated as fatal events. Failed media can be disposed and retried.
All stop/release work is serialized; stale surfaces cannot detach a newer PiP
surface. Each viewport retains its own fit mode during PiP reparenting.

All local-file playback owners use `VaultVideoPlayerController.file`. Position
queries returning after release are cancelled as null, matching video_player's
disposed-position contract. Already accepted play/seek commands finish before
controller disposal so they cannot create a timer or update disposed state.
New commands are cancelled after release starts; active errors and release
failures remain observable. Native presentation permission is still owned by
the root lock/PiP lifecycle, independently of controller cleanup.
Reopening an ended input already starts at zero; it must not also inject a
startup seek to zero, including video_player's explicit replay seek. Running
seeks to zero and nonzero pending seeks/A–B starts remain native seeks.
An ended input replacement keeps its play intent through LibVLC's intermediate
Stopped event until the new input reaches Playing. This bounded native transition
is buffering, rather than a user pause; explicit pause, revoked presentation and
failures still stop playback. The existing playback timeout reports a replacement
that cannot start.

Presentation is denied by default. The existing root lock/PiP owner grants the
current controller before play, and hides its native video/subtitle surfaces
when locking, backgrounding or releasing it. Native screen-off and PiP revoke
callbacks also hide/pause before returning to Dart. A normal user pause retains
the visible paused frame. Granting visibility does not automatically resume.
The Navigator and underlying playback route remain mounted across locking.

The blocked mpv direct-decoding experiment is not advertised by LibVLC. The old
adapter remains available to historical probes; it is not installed by `main`.
`media_kit_libs_video` is a development dependency, so its native libraries are
excluded from release APKs by Flutter. The old patched media_kit_video widget
remains solely for those probes; its removal requires retiring the old harness.
SDK HTTP overrides support User-Agent/Referer; other custom headers produce an
explicit initialization error. Current product sources are local files/content.

GitHub's universal APK compresses native libraries with
`android.packaging.jniLibs.useLegacyPackaging=true`. Android extracts the current
device ABI during installation; installed size includes those native libraries.
Compression preserves every shipped ABI, codec and subtitle module. This changes
APK packaging, not the app's update destination, and requires a full new APK.

The native video view is display-only (`PlatformViewHitTestBehavior.transparent`):
Flutter owns taps, double taps, long press and seeking, including letterboxing.
A translucent native gesture team can otherwise capture a single tap while
Flutter waits for a possible second tap.

Timeline preview extraction remains serialized with a bounded session cache;
Android API 27+ decodes bounded preview frames directly. Preview callbacks belong
to their controller so a late scrub cannot request frames from the next video.
Horizontal swipes continue playing and commit one seek on release.

The advanced playback sheet offers an explicit Copy playback diagnostics action
on supported backends. It reads an allowlist of technical native properties once,
with unknown counters preserved as unknown. Reports contain no source names,
paths, URLs, subtitle text or device names. No polling, persistence or automatic
upload is attached to playback; clipboard writes require the requesting sheet to
remain current. Diagnostics share the port's operation/disposal queue.

Android PiP is opt-in for the current video only. It reuses the existing player
and Activity, locks the vault, and displays a video-only root layer while the
app Navigator remains mounted and inaccessible. Normal backgrounding pauses.
PiP closure, screen-off, and fullscreen return revoke the grant and pause; a
native shield prevents a private frame appearing before the root lock returns.
PiP does not advance to the next media item or use the external-player unlock
bypass. Returning to the retained playback route requires authentication.
The same permission owner guards initial playback before widget binding, seek
resume, and completion. Late initialization/completion while locked or in the
background must neither start playback nor advance the playlist. PiP's entry
deadline includes its first-frame wait, so leaving before that frame revokes
the grant without waiting for rendering to resume.

`.github/workflows/player-validation.yml` now runs the production LibVLC
adapter with the existing synthetic codec/rotation/SAR/ASS fixtures. The device
action worker captures actual Android SurfaceView screenshots. Its host-side
image checks use fixture metadata for proportions and compare the video content
ROI while excluding controls/HUD; a configured rate or moving Flutter overlay
cannot establish video motion. Blank taps, sustained native DOWN/UP, pause with
controls/rotation, 100 controller handoffs, and PiP/lock return are covered.
Artifacts retain PNGs, diagnostics, ffprobe fixture facts and the image verdicts.
Failures remain failures; no private user media is used.
The integration binding accepts application-requested frames without LiveTest's
automatic frame loop. Native input/capture waits do not pump Flutter: otherwise
the harness itself could conceal a platform view waiting for an overlay image.
Each action converts logical coordinates with the current FlutterView screen
offset. The AOSP emulator must expose PiP and pass a bounded foreground HOME/UI
readiness check. ANR/crash dialogs fail with saved evidence; they are not closed.
The actual release-APK smoke uses the normal first-run UI and permissions. Its
first PlayerScreen entry has a 30-second, real-PNG readiness window starting at
the In order tap: metadata and controls do not prove a decoded frame. Waiting
never connects UIAutomator or repeats playback commands; the first real fixture
frame must meet the unchanged geometry rules. Later hold/recovery checks do not
reuse this startup allowance.
For subtitle diagnosis, debug builds expose an explicit
`debugReadSubtitleSurfacePixels{id}` call on the existing LibVLC channel. It uses
PixelCopy only to return buffer status, dimensions, nontransparent bounds/count
and CRC, never pixels, text or paths. Release builds refuse the method. Both
request and callback require the same authorized, current surface; a changed
view, holder, presentation or device lock rejects the observation. Copy errors
remain diagnostic failures, and a successful copy does not prove visible glyphs.
These values are separate from the user's copyable playback diagnostics.
The existing PiP integration scenario can explicitly start/stop a debug-only
Flutter composition observer on `com.privi.app/window`. Window diagnostics then
include reader identity/geometry, ImageAvailable notification timestamps and
whole-window draw/commit metadata. It neither acquires images nor requests
frames. A tree draw is not a particular ImageView's draw, and a window commit
does not prove display or identify an unlocked buffer. Release builds reject
starting this observer. It is removed before the scene and at Activity disposal.

The old rate-profile harness still explicitly installs a MediaKit subclass and
uses mpv-only properties. It is manual-only historical diagnostics, never a
LibVLC acceptance result. Existing host tests remain regression probes for
controls, playlist ownership and lock/PiP policy.

Hybrid composition may hide the platform view's parent without detaching it.
The native view observes both ancestor visibility and actual video/subtitle
surfaces. Vout restoration is distinct from permission and play intent: an
already paused player can restore its surface without starting playback. An
internal surface suspension is buffering, not an explicit user pause.
If hybrid composition is waiting for an overlay image, native requests paint
from that specific Flutter viewport. A short-lived ticker stops at surface-ready,
revocation or viewport replacement. Native diagnoses recovery after 5 seconds;
Dart has a 6-second guard for a missing acknowledgement. This avoids a permanent
UI animation/repaint loop and never grants playback or creates a preload decoder.
Initial playback can request that frame before creating its decoder: requiring
both an already-created player and a visible Surface would deadlock cold hybrid
composition. An initialized, authorized current view with play intent may wake
Flutter; an unplayed preload still cannot allocate a decoder.

True acceptance must open a video through Privi's built-in player, compare the
same Samsung A52 clip with VLC at 1×/2×/back to 1× (menu and hold), exercise drag
release, all fit modes, rotation/SAR, audio/subtitle tracks, ASS/CJK text, A–B and
errors/Retry, then enter PiP, switch it back, lock/screen-off and authenticate.
Record actual visible output and sound; media-clock progress, decoder counters
and Flutter frame timings are not display FPS. This checkout has no connected
Android device or KVM; remote emulator evidence and physical A52 evidence must
be distinguished. Missing true-path evidence remains unverified.
LibVLC first ships in `v1.1.2+40`; its two-round independent implementation review
resolved replay/keep-screen-on counterexamples, with physical acceptance pending.
Primary-source research and the historical diagnostic limitations are recorded in
`docs/05-review/video-performance-practices-2026-10-18.md`.

## Code generation

Drift tables use `build_runner`; localization resources use `flutter gen-l10n`.
After changing an `@DriftDatabase`, Drift table, or ARB resource, run
`make gen`. Generated `*.g.dart` files are git-ignored and rebuilt in CI.

## Dependency versions

`pubspec.yaml` holds version constraints; **`pubspec.lock` is committed** so
CI and release builds stay reproducible. After intentional upgrades:

```bash
flutter pub upgrade
# or major bumps: flutter pub upgrade --major-versions
git add pubspec.yaml pubspec.lock
```

### Flutter SDK upgrades

Keep local, CI, and release builds on the same SDK. A Flutter upgrade changes
all three pins in one change:

1. Update `.fvmrc`.
2. Update `flutter-version` in `.github/workflows/ci.yaml` and
   `.github/workflows/release.yml`.
3. Run `flutter --version`, code generation, analysis, and the full test suite.

CI prints the resolved Flutter version so drift is visible in build logs.

## Project layout

```
lib/
  application/   # Riverpod controllers / use-cases
  core/          # theme, constants, shared utils
  data/          # Drift DB, repositories, platform services
  domain/        # pure models & enums
  presentation/  # screens & widgets
  app.dart
  main.dart
test/            # unit + widget tests (mirror lib/ where useful)
android/         # Android host (package com.privi.app)
assets/branding/ # launcher / about icons
scripts/         # bootstrap + toolchain installer
.github/workflows/
  ci.yaml        # PR / main: format, analyze, test, debug APK
  release.yml    # tag v* / manual: Shorebird base APK + GitHub Release
  patch.yml      # manual: signed Dart patch for an existing release
```

## Branching, CI, releases

- Default branch: **`main`**. Feature work on branches; open PRs into `main`.
- **CI** (`.github/workflows/ci.yaml`) on push/PR to `main`: format check,
  codegen, analyze, test. **No APK build** — that is release-only.
- **Release** (`.github/workflows/release.yml`) on tag `v*` only (or
  `workflow_dispatch`): creates a Shorebird base release APK, publishes
  `privi-<version>.apk` plus SHA-256/SHA-512 checksum files, and creates a
  GitHub Release. GitHub also auto-attaches **Source code (zip/tar.gz)** for
  the tag. A normal commit to `main` never triggers this workflow.
- **Patch** (`.github/workflows/patch.yml`) is manual and only runs from
  `main`. It analyzes and tests the current code, rejects native or asset
  differences, signs the Dart patch, and publishes it to the selected
  Shorebird track.

Cut a release:

```bash
# 1. Bump version in pubspec.yaml (name+build, e.g. 0.1.0+1 → 0.1.1+2)
# 2. Commit on main
git tag v0.1.1
git push origin main --tags
```

Or **Actions → Release APK → Run workflow** and enter a tag name. The tag must
match the `pubspec.yaml` version name (`1.0.5+6` uses tag `v1.0.5`), which keeps
the GitHub release and About version aligned.

When native changes need acceptance of the signed APK, use the manual workflow
with `stage_only=true` first, without pushing a version tag. It registers/builds
the Shorebird base and uploads `privi-<version>-release` as an Actions artifact,
but creates no GitHub tag or public release. The native validation workflow can
install that artifact using its `release_run_id` input. After real APK acceptance,
run the release workflow at the same commit with `publish_run_id` set to the
successful staged run, `stage_only=false`, and optional `release_notes`. This
checks the source workflow/repository/commit and checksums, rejects an existing
tag pointing to another commit, then publishes the same APK without rebuilding.
Before publishing, match the successful native validation report's
`release_run_id` and APK SHA-256 to this staged artifact; a successful build or
publish job is not playback acceptance. Keep the verified source ref fixed; if app code
changes after a Shorebird base has been registered, increment the build number
and validate the new base rather than overwriting it.

### Shorebird hot updates

The first Shorebird-capable base was v1.0.3. v1.0.4 disables Shorebird's
automatic updater: the app makes no update request until the user selects
`Settings → Check updates`. The manual flow first calls GitHub's latest-release
endpoint. When a newer stable APK release exists, the app asks before opening
that exact GitHub Release page; otherwise it checks Shorebird and asks again
before downloading an available patch. Starting with v1.0.5, a successful
patch download triggers a full Android process restart so the new Flutter
engine loads the patch. `Settings → About` displays the package version/build
plus the active patch number.

`AppUpdateCoordinator` owns this ordering. `GithubAppReleaseSource` validates
the release tag as SemVer and accepts only HTTPS links on `github.com`; response
and parsing failures remain visible as update-check failures rather than
silently skipping the full-release check.

Android's `INTERNET` permission is a normal install-time permission and has no
runtime system dialog. The manual action and download confirmation are Privi's
application-level consent boundary.

Use a patch only when the change is Dart code and the base version remains
unchanged:

1. Make the Dart-only change on a branch and merge it through a PR.
2. Run **Actions → Shorebird Patch** from `main`.
3. Enter the exact Shorebird base version, such as `1.0.5+6`.
4. Publish to `staging` first; after verification, publish the reviewed commit
   to `stable`.

Do not override Shorebird's native/asset diff checks. Changes to Android code,
the manifest, plugins, assets, or Flutter itself cannot be delivered by a Dart
patch; bump `pubspec.yaml` and publish a new base APK instead. This is a
technical platform boundary, not a fallback path.

For local validation, install the official Shorebird CLI, authenticate, and run:

```bash
shorebird release android --flutter-version 3.44.6 --artifact apk \
  --public-key-path shorebird_public.pem --dry-run
```

Patch signing uses the committed public key (`shorebird_public.pem`) and the
private key stored only in GitHub Actions secrets. Back up the private key
offline; never commit it.

### Release signing (Play Protect)

Release APKs must use a **permanent keystore**, not `debug.keystore`. Play
Protect flags unknown / debug signatures on sideloaded CI builds.

One-time local setup:

```bash
./scripts/setup-release-keystore.sh
# Creates android/app/upload-keystore.jks + android/key.properties (git-ignored)
# Prints the four GitHub Actions secrets to paste into the repo
```

Required repository secrets:

| Secret | Value |
|--------|--------|
| `ANDROID_KEYSTORE_BASE64` | `base64` of `upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias (default `privi`) |
| `ANDROID_KEY_PASSWORD` | key password |
| `SHOREBIRD_TOKEN` | Shorebird CI authentication token |
| `SHOREBIRD_PATCH_PRIVATE_KEY` | PEM private key used to sign patches |

Local `make apk` picks up `android/key.properties` automatically. CI decodes the
keystore from secrets before the Shorebird release/patch build and fails if the
resulting APK is still debug-signed.

Also enabled on release builds: R8 minify + resource shrink
(`android/app/proguard-rules.pro`).

After the first signed release:

1. Scan the APK on [VirusTotal](https://www.virustotal.com) (aim for clean).
2. If installs still warn, file a [Play Protect appeal](https://support.google.com/googleplay/android-developer/contact/protectappeals).
3. Keep “Improve harmful app detection” on when installing so Google can
   whitelist the signature over time.

**Back up** `upload-keystore.jks` and passwords offline. Losing the key means
users cannot update without uninstalling. Never commit keystores.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `flutter: command not found` | Install Flutter / FVM; reopen shell / `source ~/.bashrc`. |
| Analyzer errors on `*.g.dart` | Run `make gen`; generated files are excluded from lints. |
| `flutter doctor` Android license issues | `flutter doctor --android-licenses`. |
| External media test fails | Ensure VLC and a picture viewer are installed. Their Back action returns unlocked; Home → Privi and screen-off → unlock both show the credential screen. |
| bootstrap overwrote a file | It restores owned files from git — commit first. |
| Device not listed under WSL2 | Share adb from Windows or use wireless `adb connect`. |
| Release workflow failed on permissions | Repo needs `contents: write` for the `GITHUB_TOKEN` (set in the workflow). |
| Release workflow: missing ANDROID_* secrets | Run `./scripts/setup-release-keystore.sh` and add the four secrets under repo Settings → Secrets. |
| Release/patch workflow: missing SHOREBIRD_* secret | Add the CI token and patch private key under repo Settings → Secrets and variables → Actions. |
| Shorebird rejects native or asset diffs | Publish a new base APK; do not use `--allow-native-diffs` or `--allow-asset-diffs`. |
| Play Protect “Unsafe” on sideload | Ensure CI uses the permanent release keystore (not debug). Submit VirusTotal + Play Protect appeal for new signatures. |
| `make apk` still debug-signed | Create `android/key.properties` via `./scripts/setup-release-keystore.sh`. |
