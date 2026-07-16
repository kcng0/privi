# Development Guide

How to stand up the toolchain and work on **Privi**. Product docs that used to
live under `docs/` are kept local-only and are not part of the published repo.

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Flutter SDK | latest **stable** (≥ 3.24) | Pinned via [`.fvmrc`](./.fvmrc) → use FVM. |
| Dart | bundled with Flutter | — |
| Java (JDK) | 17+ | Needed for Android Gradle. |
| Android SDK | platform **36** + build-tools + cmdline-tools | Licenses accepted. |
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
fvm use stable
```

Prefer a plain global Flutter? Install from
https://docs.flutter.dev/get-started and skip FVM; the `Makefile`/scripts fall
back to `flutter` automatically.

## 2. Install the Android SDK

Easiest via Android Studio (SDK Manager) or `sdkmanager` cmdline-tools:

```bash
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
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

1. `flutter create --platforms=android --org com.privateheart .` to produce /
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

Drift tables and Riverpod providers use `build_runner`. After changing any
`@DriftDatabase`, table, or `@riverpod` provider, run `make gen` (or keep
`make watch` running). Generated `*.g.dart` files are git-ignored and rebuilt
in CI.

## Dependency versions

`pubspec.yaml` holds version constraints; **`pubspec.lock` is committed** so
CI and release builds stay reproducible. After intentional upgrades:

```bash
flutter pub upgrade
# or major bumps: flutter pub upgrade --major-versions
git add pubspec.yaml pubspec.lock
```

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
android/         # Android host (package com.privateheart.privateheart_vault)
assets/branding/ # launcher / about icons
scripts/         # bootstrap + toolchain installer
.github/workflows/
  ci.yaml        # PR / main: format, analyze, test, debug APK
  release.yml    # tag v* / manual: release APK + GitHub Release
```

## Branching, CI, releases

- Default branch: **`main`**. Feature work on branches; open PRs into `main`.
- **CI** (`.github/workflows/ci.yaml`) on push/PR to `main`: format check,
  codegen, analyze, test, debug APK artifact.
- **Release** (`.github/workflows/release.yml`) on tag `v*` (or
  `workflow_dispatch`): builds a release APK, renames it to
  `privi-<version>.apk`, and attaches it to a GitHub Release.

Cut a release:

```bash
# 1. Bump version in pubspec.yaml (name+build, e.g. 0.1.0+1 → 0.1.1+2)
# 2. Commit on main
git tag v0.1.1
git push origin main --tags
```

Or **Actions → Release APK → Run workflow** and enter a tag name.

Release APKs use the **debug signing config** until a real upload keystore is
configured (`android/key.properties` is git-ignored — never commit keystores).

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
