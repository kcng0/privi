#!/usr/bin/env bash
# Bootstrap the PrivateHeart Vault dev environment.
#
# Safe to re-run. It:
#   1. Verifies Flutter is available (prefers FVM).
#   2. Generates the native Android scaffolding (android/) that `flutter create`
#      owns — WITHOUT clobbering our hand-authored files (we restore them from
#      git afterwards).
#   3. Fetches dependencies and runs code generation.
#
# Prereqs (see DEVELOPMENT.md): Flutter SDK + Android SDK (cmdline-tools,
# platform, build-tools) with licenses accepted. Java 17+.
set -euo pipefail

cd "$(dirname "$0")/.."

# Prefer FVM if present so the pinned Flutter version is used.
if command -v fvm >/dev/null 2>&1; then
  FLUTTER="fvm flutter"
  echo "==> Using FVM. Ensuring pinned Flutter is installed..."
  fvm install
else
  FLUTTER="flutter"
fi

if ! command -v flutter >/dev/null 2>&1 && [ "$FLUTTER" = "flutter" ]; then
  echo "ERROR: Flutter not found. Install it (see DEVELOPMENT.md) and re-run." >&2
  exit 1
fi

ORG="com.privateheart"
NAME="privateheart_vault"

# Files we own and must NOT let `flutter create` overwrite.
OWNED=(
  pubspec.yaml
  analysis_options.yaml
  README.md
  .gitignore
  .metadata
  lib
  test
)

echo "==> Generating native Android scaffolding (won't touch our sources)..."
# Snapshot owned files so we can restore any that flutter create regenerates.
if git rev-parse --git-dir >/dev/null 2>&1 && git diff --quiet 2>/dev/null; then
  CLEAN_TREE=1
else
  CLEAN_TREE=0
fi

$FLUTTER create \
  --platforms=android \
  --org "$ORG" \
  --project-name "$NAME" \
  --overwrite \
  .

# Restore our authored files if git can (only the ones that existed & changed).
if git rev-parse --git-dir >/dev/null 2>&1; then
  echo "==> Restoring hand-authored files clobbered by 'flutter create'..."
  for f in "${OWNED[@]}"; do
    if git cat-file -e "HEAD:$f" 2>/dev/null; then
      git checkout -- "$f" 2>/dev/null || true
    fi
  done
else
  echo "WARN: no git repo — review android/ vs our pubspec.yaml/lib manually." >&2
fi

echo "==> Fetching dependencies..."
$FLUTTER pub get

echo "==> Running code generation (drift + riverpod)..."
$FLUTTER pub run build_runner build --delete-conflicting-outputs

echo ""
echo "Bootstrap complete."
echo "  make run     # launch on a device"
echo "  make test    # run tests"
echo "  make watch   # codegen in watch mode"
