#!/usr/bin/env bash
#
# install-toolchain.sh — one-shot installer for the Flutter + Android toolchain
# on Ubuntu / WSL2. Idempotent and re-runnable: each step is skipped if already
# done. See docs/toolchain-setup.md for gotchas, options, and device setup.
#
# Usage:
#   ./scripts/install-toolchain.sh              # install everything
#   ./scripts/install-toolchain.sh --doctor     # just run `flutter doctor -v`
#
# Override defaults with env vars, e.g.:
#   CMDLINE_TOOLS_VERSION=13114758 ANDROID_PLATFORM=android-37 ./scripts/install-toolchain.sh
#
# NON-goals: this does NOT install a device/emulator (impractical on WSL2 —
# use a physical phone; see the guide) and does NOT run the project bootstrap
# (run ./scripts/bootstrap.sh afterwards).

set -euo pipefail

# ----------------------------------------------------------------------------
# Config (override via environment)
# ----------------------------------------------------------------------------
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
CMDLINE_TOOLS_VERSION="${CMDLINE_TOOLS_VERSION:-11076708}" # see guide to update
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-37}" # match compileSdk in android/app
BUILD_TOOLS="${BUILD_TOOLS:-36.0.0}"

APT_PKGS=(curl git unzip xz-utils zip libglu1-mesa)

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
# ANSI-C quoting so the escapes render in plain `cat`/heredoc too, not just echo -e.
c_blue=$'\033[1;34m'; c_green=$'\033[1;32m'; c_yellow=$'\033[1;33m'; c_reset=$'\033[0m'
step() { echo -e "\n${c_blue}==>${c_reset} $*"; }
ok()   { echo -e "${c_green}  ✓${c_reset} $*"; }
warn() { echo -e "${c_yellow}  !${c_reset} $*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Make freshly-installed tools visible within THIS run.
export PATH="$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
export ANDROID_HOME

if [[ "${1:-}" == "--doctor" ]]; then
  flutter doctor -v
  exit 0
fi

# ----------------------------------------------------------------------------
# 1. System packages
# ----------------------------------------------------------------------------
step "System packages (${APT_PKGS[*]})"
missing=()
for p in "${APT_PKGS[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
if ((${#missing[@]})); then
  sudo apt-get update -y
  sudo apt-get install -y "${missing[@]}"
  ok "installed: ${missing[*]}"
else
  ok "all present"
fi

if ! have java; then
  warn "No JDK found. Installing OpenJDK 17..."
  sudo apt-get install -y openjdk-17-jdk
else
  ok "JDK present: $(java -version 2>&1 | head -1)"
fi

# ----------------------------------------------------------------------------
# 2. Flutter SDK (direct git clone — simplest/robust; FVM is optional, see guide)
# ----------------------------------------------------------------------------
step "Flutter SDK ($FLUTTER_CHANNEL)"
if [[ -x "$FLUTTER_HOME/bin/flutter" ]]; then
  ok "already at $FLUTTER_HOME"
else
  git clone --depth 1 -b "$FLUTTER_CHANNEL" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  ok "cloned to $FLUTTER_HOME"
fi
git config --global --add safe.directory "$FLUTTER_HOME" 2>/dev/null || true
flutter --version
flutter config --no-analytics >/dev/null 2>&1 || true

# ----------------------------------------------------------------------------
# 3. Android command-line tools
# ----------------------------------------------------------------------------
step "Android command-line tools"
if [[ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]]; then
  ok "already installed at $ANDROID_HOME"
else
  tmp="$(mktemp -d)"
  url="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"
  echo "  downloading $url"
  curl -fL -o "$tmp/cmdline-tools.zip" "$url"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  unzip -q "$tmp/cmdline-tools.zip" -d "$tmp"
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mv "$tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rm -rf "$tmp"
  ok "installed to $ANDROID_HOME/cmdline-tools/latest"
fi

# ----------------------------------------------------------------------------
# 4. Android SDK packages + licenses
# ----------------------------------------------------------------------------
step "Android SDK packages (platform-tools, $ANDROID_PLATFORM, build-tools;$BUILD_TOOLS)"
yes | sdkmanager --licenses >/dev/null || true
sdkmanager --install "platform-tools" "platforms;${ANDROID_PLATFORM}" "build-tools;${BUILD_TOOLS}"
ok "SDK packages installed"

# ----------------------------------------------------------------------------
# 5. Persist environment in ~/.bashrc
# ----------------------------------------------------------------------------
step "Persist environment in ~/.bashrc"
MARKER_BEGIN="# >>> privateheart flutter/android toolchain >>>"
MARKER_END="# <<< privateheart flutter/android toolchain <<<"
if grep -qF "$MARKER_BEGIN" "$HOME/.bashrc" 2>/dev/null; then
  ok "already present (edit the block manually to change paths)"
else
  {
    echo ""
    echo "$MARKER_BEGIN"
    echo "export ANDROID_HOME=\"$ANDROID_HOME\""
    echo "export PATH=\"$FLUTTER_HOME/bin:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH\""
    echo "$MARKER_END"
  } >> "$HOME/.bashrc"
  ok "appended (run: source ~/.bashrc)"
fi

# ----------------------------------------------------------------------------
# 6. Wire Flutter to the SDK + accept licenses
# ----------------------------------------------------------------------------
step "Configure Flutter → Android SDK"
flutter config --android-sdk "$ANDROID_HOME" >/dev/null
yes | flutter doctor --android-licenses >/dev/null || true
ok "configured"

# ----------------------------------------------------------------------------
# Done
# ----------------------------------------------------------------------------
step "flutter doctor"
flutter doctor || true

cat <<EOF

${c_green}Toolchain install complete.${c_reset}

Next:
  1. source ~/.bashrc          # (or open a new shell) to pick up PATH
  2. Connect a phone           # WSL2 device setup → docs/toolchain-setup.md §Devices
  3. ./scripts/bootstrap.sh    # generate android/, deps, codegen
  4. make run                  # launch the app

Gotchas, optional extras, and troubleshooting: docs/toolchain-setup.md
EOF
