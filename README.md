# Privi

Personal, offline **Android media vault**. Hide photos & videos from the system
gallery, rate them **1–3 hearts**, favorite, play playlists (built-in or
**VLC**), and lock the app with **pattern / PIN + biometric**. Dark theme only.
Sideload-only — no cloud, no accounts, no analytics.

**Author:** [kcng0](https://github.com/kcng0) · **License:** [MIT](./LICENSE).

UI takes reference from the HideSomething / “HD Smith” style. This is a personal
project; simplicity is favored over features.

---

## Install (APK)

Privi is not on Google Play. Download a release APK and sideload it:

1. Open the latest **[Release](https://github.com/kcng0/privi/releases/latest)**.
2. Download `privi-<version>.apk` (and optionally `SHA256SUMS`).
3. Verify the download (desktop):
   ```bash
   sha256sum -c SHA256SUMS
   ```
4. On your phone, allow install from your browser/file manager if prompted.
5. Open the APK and install.

Each release includes:

| Asset | Purpose |
|-------|---------|
| `privi-<version>.apk` | Sideload install |
| `SHA256SUMS` / `.sha256` / `CHECKSUMS.txt` | Integrity check |
| **Source code (zip / tar.gz)** | Auto-attached by GitHub for the tag |

**Requirements:** Android 8.0+ (API 26). Optional: [VLC](https://www.videolan.org/)
for external video playback. All media stays on-device.

> Release APKs are currently **debug-signed** (convenient for sideload builds).
> Treat them as personal-use builds, not store-ready signed packages.

---

## Features

- **Visible | Invisible** home — browse system gallery albums or the private vault
- **Directory hide** — media removed from the system gallery while kept on disk
- **Hearts (0–3)** + favorites, albums, and playlists
- **Built-in player** + open-in-VLC
- **Pattern / PIN + biometric** lock, optional `FLAG_SECURE` (block screenshots)
- **Share-to-Privi** import intents for images and videos
- Fully offline — no `INTERNET` permission

### Keywords / search terms

`android photo vault` · `hide photos from gallery` · `private gallery app` ·
`video vault` · `offline media locker` · `pattern lock gallery` ·
`biometric photo lock` · `sideload apk vault` · `flutter media vault` ·
`hide videos android` · `no cloud gallery` · `vlc private player`

GitHub topics: `flutter` `android` `photo-vault` `video-vault` `private-gallery`
`hide-photos` `biometric-lock` `privacy` `offline` `sideload` `apk` `vlc` `mit-license`

---

## Develop

### Prerequisites

| Tool | Notes |
|------|--------|
| Flutter stable (≥ 3.24) | Prefer [FVM](https://fvm.app/) (`.fvmrc` pins `stable`) |
| JDK 17+ | Android Gradle |
| Android SDK | platform **36**, build-tools, cmdline-tools, licenses accepted |
| Device / emulator | Android 8.0+ (API 26) |

### One-shot setup (Ubuntu / WSL2)

```bash
git clone https://github.com/kcng0/privi.git
cd privi

# Optional: install Flutter + Android SDK + licenses
./scripts/install-toolchain.sh && source ~/.bashrc

# Generate native scaffold (if needed), deps, codegen
./scripts/bootstrap.sh

# Run on a connected device
make run
```

### Everyday commands

```bash
make run       # launch on a connected device
make test      # unit + widget tests
make analyze   # static analysis
make format    # dart format lib test
make gen       # build_runner (Drift + Riverpod)
make watch     # codegen in watch mode
make apk       # release APK for sideloading
make help      # list targets
```

Without `make`, use `fvm flutter …` (or plain `flutter` if FVM is not installed).

Full environment notes, troubleshooting, and CI details:
**[DEVELOPMENT.md](./DEVELOPMENT.md)**.

### Repository layout

```
├── lib/           # Dart source (feature-first)
├── test/          # unit + widget tests
├── android/       # Android host project
├── assets/        # branding / icons
├── scripts/       # bootstrap + toolchain installer
├── .github/       # CI + release workflows
├── pubspec.yaml
├── Makefile
└── DEVELOPMENT.md
```

---

## Releases & CI

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| [CI](./.github/workflows/ci.yaml) | push / PR to `main` | format, codegen, analyze, test only |
| [Release](./.github/workflows/release.yml) | tag `v*` or manual dispatch | release APK + checksums (+ GitHub source zip/tar) |

To cut a release from a clean `main`:

```bash
# bump version in pubspec.yaml (e.g. 0.1.0+1 → 0.1.1+2), commit, then:
git tag v0.1.1
git push origin v0.1.1
```

Or run **Actions → Release APK → Run workflow**.

---

## License

[MIT](./LICENSE) — Copyright (c) 2026 [kcng0](https://github.com/kcng0).
