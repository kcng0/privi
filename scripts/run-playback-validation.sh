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
# The first immersive-mode tutorial steals window focus and blocks PiP entry.
# This setting applies only to the disposable CI emulator.
adb -s "$ANDROID_SERIAL" shell settings --user current put secure immersive_mode_confirmations confirmed
test "$(adb -s "$ANDROID_SERIAL" shell settings --user current get secure immersive_mode_confirmations | tr -d '\r')" = confirmed
adb -s "$ANDROID_SERIAL" logcat -c
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
