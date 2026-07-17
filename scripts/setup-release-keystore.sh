#!/usr/bin/env bash
# Generate (or re-use) a permanent release keystore for Privi, write local
# android/key.properties, and print the GitHub Actions secrets you need so
# release APKs are never debug-signed (Play Protect flags unknown/debug keys).
#
# Usage (from repo root):
#   ./scripts/setup-release-keystore.sh
#   ./scripts/setup-release-keystore.sh --print-secrets   # only re-print base64
#
# Secrets written to GitHub (Settings → Secrets and variables → Actions):
#   ANDROID_KEYSTORE_BASE64
#   ANDROID_KEYSTORE_PASSWORD
#   ANDROID_KEY_ALIAS
#   ANDROID_KEY_PASSWORD
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

KEYSTORE_PATH="${KEYSTORE_PATH:-$ROOT/android/app/upload-keystore.jks}"
KEY_PROPS="$ROOT/android/key.properties"
KEY_ALIAS="${KEY_ALIAS:-privi}"
VALIDITY_DAYS="${VALIDITY_DAYS:-10000}"
PRINT_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --print-secrets) PRINT_ONLY=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
  esac
done

if ! command -v keytool >/dev/null 2>&1; then
  echo "error: keytool not found (install JDK 17+)" >&2
  exit 1
fi
if ! command -v base64 >/dev/null 2>&1; then
  echo "error: base64 not found" >&2
  exit 1
fi

if [[ "$PRINT_ONLY" -eq 1 ]]; then
  if [[ ! -f "$KEYSTORE_PATH" ]]; then
    echo "error: no keystore at $KEYSTORE_PATH — run without --print-secrets first" >&2
    exit 1
  fi
  if [[ ! -f "$KEY_PROPS" ]]; then
    echo "error: missing $KEY_PROPS (needed for passwords/alias)" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  storePassword=$(grep '^storePassword=' "$KEY_PROPS" | cut -d= -f2-)
  keyPassword=$(grep '^keyPassword=' "$KEY_PROPS" | cut -d= -f2-)
  keyAlias=$(grep '^keyAlias=' "$KEY_PROPS" | cut -d= -f2-)
else
  if [[ -f "$KEYSTORE_PATH" ]]; then
    echo "Keystore already exists: $KEYSTORE_PATH"
    echo "Refusing to overwrite (Play Protect reputation depends on a stable key)."
    echo "Use --print-secrets to re-export base64 for GitHub Secrets."
    exit 1
  fi

  echo "=== Privi release keystore setup ==="
  echo "This creates a permanent signing key. Back it up offline."
  echo "Losing it means users cannot update without uninstalling."
  echo

  read -r -s -p "Keystore password (store + key will use the same unless you edit later): " STORE_PASSWORD
  echo
  if [[ -z "$STORE_PASSWORD" ]]; then
    echo "error: password cannot be empty" >&2
    exit 1
  fi
  read -r -s -p "Confirm password: " STORE_PASSWORD2
  echo
  if [[ "$STORE_PASSWORD" != "$STORE_PASSWORD2" ]]; then
    echo "error: passwords do not match" >&2
    exit 1
  fi
  KEY_PASSWORD="$STORE_PASSWORD"

  read -r -p "Key alias [$KEY_ALIAS]: " ALIAS_IN
  KEY_ALIAS="${ALIAS_IN:-$KEY_ALIAS}"

  read -r -p "Distinguished name CN [Privi]: " CN_IN
  CN="${CN_IN:-Privi}"
  DNAME="CN=${CN}, OU=Mobile, O=Privi, L=Unknown, ST=Unknown, C=US"

  mkdir -p "$(dirname "$KEYSTORE_PATH")"
  keytool -genkeypair \
    -v \
    -storetype JKS \
    -keystore "$KEYSTORE_PATH" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 2048 \
    -validity "$VALIDITY_DAYS" \
    -storepass "$STORE_PASSWORD" \
    -keypass "$KEY_PASSWORD" \
    -dname "$DNAME"

  # storeFile path is relative to android/app/ (where build.gradle.kts lives).
  cat > "$KEY_PROPS" <<EOF
storePassword=${STORE_PASSWORD}
keyPassword=${KEY_PASSWORD}
keyAlias=${KEY_ALIAS}
storeFile=upload-keystore.jks
EOF
  chmod 600 "$KEY_PROPS" "$KEYSTORE_PATH"

  storePassword="$STORE_PASSWORD"
  keyPassword="$KEY_PASSWORD"
  keyAlias="$KEY_ALIAS"
  echo
  echo "Wrote $KEYSTORE_PATH"
  echo "Wrote $KEY_PROPS (git-ignored)"
fi

# Portable base64 (no wrap): GNU uses -w0, BSD has no -w.
if base64 -w0 /dev/null >/dev/null 2>&1; then
  B64=$(base64 -w0 "$KEYSTORE_PATH")
else
  B64=$(base64 "$KEYSTORE_PATH" | tr -d '\n')
fi

echo
echo "=== GitHub Actions secrets (repo → Settings → Secrets and variables → Actions) ==="
echo
echo "ANDROID_KEYSTORE_BASE64="
echo "$B64"
echo
echo "ANDROID_KEYSTORE_PASSWORD=${storePassword}"
echo "ANDROID_KEY_ALIAS=${keyAlias}"
echo "ANDROID_KEY_PASSWORD=${keyPassword}"
echo
echo "=== Local release build ==="
echo "  make apk"
echo "  # or: flutter build apk --release"
echo
echo "=== After first signed release ==="
echo "1. Upload APK to https://www.virustotal.com and confirm clean."
echo "2. File a Play Protect appeal if installs still warn:"
echo "   https://support.google.com/googleplay/android-developer/contact/protectappeals"
echo "3. On install prompts, leave 'Improve harmful app detection' on so Google"
echo "   can whitelist this signature over time."
echo
echo "IMPORTANT: back up upload-keystore.jks + passwords offline. Do not commit them."
