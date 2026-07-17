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

### Shorebird hot updates

The first Shorebird-capable base was v1.0.3. v1.0.4 disables Shorebird's
automatic updater: the app makes no update request until the user selects
`Settings → Check updates`, then asks again before downloading an available
patch. Starting with v1.0.5, a successful download triggers a full Android
process restart so the new Flutter engine loads the patch. `Settings → About`
displays the package version/build plus the active patch number.

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
| External player test fails | Ensure VLC is installed on the test device. |
| bootstrap overwrote a file | It restores owned files from git — commit first. |
| Device not listed under WSL2 | Share adb from Windows or use wireless `adb connect`. |
| Release workflow failed on permissions | Repo needs `contents: write` for the `GITHUB_TOKEN` (set in the workflow). |
| Release workflow: missing ANDROID_* secrets | Run `./scripts/setup-release-keystore.sh` and add the four secrets under repo Settings → Secrets. |
| Release/patch workflow: missing SHOREBIRD_* secret | Add the CI token and patch private key under repo Settings → Secrets and variables → Actions. |
| Shorebird rejects native or asset diffs | Publish a new base APK; do not use `--allow-native-diffs` or `--allow-asset-diffs`. |
| Play Protect “Unsafe” on sideload | Ensure CI uses the permanent release keystore (not debug). Submit VirusTotal + Play Protect appeal for new signatures. |
| `make apk` still debug-signed | Create `android/key.properties` via `./scripts/setup-release-keystore.sh`. |
