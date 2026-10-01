#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/playback-validation
adb -s emulator-5554 shell getprop ro.build.fingerprint > build/playback-validation/emulator-build.txt
# The first immersive-mode tutorial steals window focus and blocks PiP entry.
# This setting applies only to the disposable CI emulator.
adb -s emulator-5554 shell settings --user current put secure immersive_mode_confirmations confirmed
test "$(adb -s emulator-5554 shell settings --user current get secure immersive_mode_confirmations | tr -d '\r')" = confirmed
adb logcat -c
python3 scripts/playback-device-actions.py > build/playback-validation/device-actions.txt 2>&1 &
device_actions_pid=$!
trap 'kill "$device_actions_pid" 2>/dev/null || true; adb logcat -d > build/playback-validation/logcat.txt || true' EXIT
timeout 1200s flutter drive --no-pub -d emulator-5554 \
  --driver=test_driver/playback_driver.dart \
  --target=integration_test/playback_test.dart
