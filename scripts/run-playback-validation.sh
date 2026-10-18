#!/usr/bin/env bash
set -euo pipefail
export ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
mkdir -p build/playback-validation
python3 -c 'from PIL import Image, ImageChops'
cp integration_test/fixtures/SOURCE.txt integration_test/fixtures/SHA256SUMS build/playback-validation/
for fixture in integration_test/fixtures/*.mp4 integration_test/fixtures/*.mkv integration_test/fixtures/*.webm; do
  ffprobe -v error -show_streams -show_format -of json "$fixture" > "build/playback-validation/$(basename "$fixture").ffprobe.json"
done
adb -s "$ANDROID_SERIAL" shell getprop ro.build.fingerprint > build/playback-validation/emulator-build.txt
flutter --version --machine > build/playback-validation/flutter-version.json
"${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}/emulator/emulator" -version > build/playback-validation/emulator-version.txt 2>&1
adb -s "$ANDROID_SERIAL" shell getprop > build/playback-validation/emulator-properties.txt
# The first immersive-mode tutorial steals window focus and blocks PiP entry.
# This setting applies only to the disposable CI emulator.
adb -s "$ANDROID_SERIAL" shell settings --user current put secure immersive_mode_confirmations confirmed
test "$(adb -s "$ANDROID_SERIAL" shell settings --user current get secure immersive_mode_confirmations | tr -d '\r')" = confirmed
# Fail before running Privi if first-boot HOME/ANR/system state is unusable.
# Keep boot logs; never silence app errors or dismiss a system error dialog.
timeout 150s python3 scripts/playback-device-actions.py --preflight > build/playback-validation/preflight-runner.txt 2>&1
if [[ -n "${RELEASE_RUN_ID:-}" ]]; then
  trap 'adb -s "$ANDROID_SERIAL" logcat -d > build/playback-validation/logcat.txt || true' EXIT
  timeout 900s python3 scripts/playback-device-actions.py --release-smoke build/release-under-test > build/playback-validation/release-smoke-runner.txt 2>&1
  exit
fi
python3 scripts/playback-device-actions.py > build/playback-validation/device-actions.txt 2>&1 &
device_actions_pid=$!
trap 'kill "$device_actions_pid" 2>/dev/null || true; adb -s "$ANDROID_SERIAL" logcat -d > build/playback-validation/logcat.txt || true' EXIT
# Ensure the acknowledgement server is ready before the app emits any markers.
for attempt in {1..50}; do
  if curl --silent --fail http://127.0.0.1:8766/health > build/playback-validation/device-capture-backend.json; then
    break
  fi
  sleep 0.1
done
curl --silent --fail http://127.0.0.1:8766/health > /dev/null
timeout 1200s flutter drive --no-pub -d "$ANDROID_SERIAL" \
  --driver=test_driver/playback_driver.dart \
  --target=integration_test/playback_test.dart
