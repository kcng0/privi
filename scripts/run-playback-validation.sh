#!/usr/bin/env bash
set -euo pipefail
export ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
mkdir -p build/playback-validation
subtitle_trace="${SUBTITLE_TRACE:-false}"
if [[ "$subtitle_trace" != true && "$subtitle_trace" != false ]]; then
  echo 'SUBTITLE_TRACE must be true or false' >&2
  exit 2
fi
if [[ "$subtitle_trace" == true && -n "${RELEASE_RUN_ID:-}" ]]; then
  echo 'subtitle_trace cannot instrument an actual signed release smoke run' >&2
  exit 2
fi

device_actions_pid=''
trace_runner_pid=''
trace_runner_status=0
trace_drive_pid=''
trace_drive_status=''
trace_aborted_drive=false
trace_server_adb_pid=''
trace_temp=''
trace_guest=''
trace_guest_created=false
trace_forward_created=false
trace_setup_ready=false
trace_setup_stage=disabled

stop_trace_drive() {
  [[ -n "$trace_drive_pid" ]] || return 0
  if kill -0 "$trace_drive_pid" 2>/dev/null; then
    local session_id
    session_id=$(ps -o sid= -p "$trace_drive_pid" | tr -d ' ') || session_id=''
    if [[ "$session_id" == "$trace_drive_pid" ]]; then
      # setsid gives this invocation its own session and process group.
      kill -TERM -- "-$trace_drive_pid" 2>/dev/null || true
      for _ in {1..120}; do
        kill -0 "$trace_drive_pid" 2>/dev/null || break
        sleep 0.1
      done
      kill -KILL -- "-$trace_drive_pid" 2>/dev/null || true
    else
      echo 'Diagnostic drive session identity mismatch; only signalling the exact owned child PID' >&2
      kill -TERM "$trace_drive_pid" 2>/dev/null || true
    fi
  fi
  if wait "$trace_drive_pid"; then trace_drive_status=0; else trace_drive_status=$?; fi
  trace_drive_pid=''
}

# Keep the original drive/smoke failure. Diagnostic failure only changes an
# otherwise successful exit, and cleanup touches this invocation's resources.
cleanup() {
  local original_status=$? trace_status=$trace_runner_status remote_pid=''
  trap - EXIT INT TERM
  set +e
  stop_trace_drive
  if [[ -n "$trace_runner_pid" ]]; then
    kill -TERM "$trace_runner_pid" 2>/dev/null
    # GNU timeout forwards TERM and kills its own group after ten seconds.
    for _ in {1..120}; do
      kill -0 "$trace_runner_pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$trace_runner_pid" 2>/dev/null; then
      kill -KILL -- "-$trace_runner_pid" 2>/dev/null
    fi
    wait "$trace_runner_pid"
    trace_status=$?
  fi
  if [[ "$trace_forward_created" == true ]]; then
    timeout 5s adb -s "$ANDROID_SERIAL" forward --remove tcp:27043
  fi
  if [[ "$trace_guest_created" == true ]]; then
    remote_pid=$(timeout 5s adb -s "$ANDROID_SERIAL" shell cat "$trace_guest/pid" 2>/dev/null | tr -d '\r')
    if [[ "$remote_pid" =~ ^[0-9]+$ ]]; then
      # A PID file alone is insufficient: never signal a reused/foreign PID.
      timeout 5s adb -s "$ANDROID_SERIAL" shell "[ \"\$(readlink /proc/$remote_pid/exe)\" != '$trace_guest/server' ] || kill '$remote_pid'"
      sleep 0.2
      timeout 5s adb -s "$ANDROID_SERIAL" shell "[ \"\$(readlink /proc/$remote_pid/exe)\" != '$trace_guest/server' ] || kill -9 '$remote_pid'"
    fi
    timeout 5s adb -s "$ANDROID_SERIAL" shell rm -rf "$trace_guest"
  fi
  if [[ -n "$trace_server_adb_pid" ]]; then
    kill -TERM "$trace_server_adb_pid" 2>/dev/null
    for _ in {1..20}; do
      kill -0 "$trace_server_adb_pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL "$trace_server_adb_pid" 2>/dev/null
    wait "$trace_server_adb_pid" 2>/dev/null
  fi
  if [[ -n "$trace_temp" ]]; then rm -rf -- "$trace_temp"; fi
  if [[ -n "$device_actions_pid" ]]; then kill "$device_actions_pid" 2>/dev/null; fi
  timeout 15s adb -s "$ANDROID_SERIAL" logcat -d > build/playback-validation/logcat.txt
  if [[ "$subtitle_trace" == true ]]; then
    python3 - "$trace_setup_stage" "$trace_setup_ready" "$trace_status" "$original_status" "$trace_aborted_drive" "$trace_drive_status" <<'TRACE_CLEANUP'
import json
from pathlib import Path
import sys
stage, ready, trace_status, original_status, aborted_drive, drive_status = sys.argv[1:]
Path("build/playback-validation/subtitle-trace-run.json").write_text(json.dumps({
    "instrumented": True, "performance_measurement": False, "business_assertions": False,
    "setup_stage": stage, "setup_ready": ready == "true", "trace_exit_code": int(trace_status),
    "original_validation_exit_code": int(original_status),
    "validation_aborted_by_diagnostic": aborted_drive == "true",
    "drive_exit_code": int(drive_status) if drive_status else None,
}, indent=2) + "\n")
TRACE_CLEANUP
    if [[ "$trace_setup_ready" != true ]]; then
      echo "Subtitle diagnostic setup failed at $trace_setup_stage; see subtitle-trace-setup.log" >&2
      [[ "$original_status" -ne 0 ]] || original_status=1
    elif [[ "$trace_status" -ne 0 ]]; then
      echo 'Subtitle diagnostic failed; see subtitle-trace-summary.json and subtitle-trace-runner.log' >&2
      [[ "$original_status" -ne 0 ]] || original_status=1
    fi
  fi
  exit "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

setup_subtitle_trace() {
  echo 'Instrumented metadata diagnostic: this run is not a performance measurement.'
  trace_setup_stage=emulator-check
  [[ "$(timeout 10s adb -s "$ANDROID_SERIAL" shell getprop ro.kernel.qemu | tr -d '\r')" == 1 ]]
  [[ "$(timeout 10s adb -s "$ANDROID_SERIAL" shell getprop ro.product.cpu.abi | tr -d '\r')" == x86_64 ]]
  trace_temp=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/privi-subtitle-trace.XXXXXXXX")
  trace_guest="/data/local/tmp/$(basename "$trace_temp")"
  trace_setup_stage=client-install
  timeout 180s python3 -m pip install --disable-pip-version-check --no-compile --no-deps \
    --only-binary=:all: --target "$trace_temp/client" frida==17.24.2
  trace_setup_stage=server-download
  timeout 190s curl --fail --location --retry 2 --connect-timeout 15 --max-time 180 \
    --output "$trace_temp/server.xz" \
    https://github.com/frida/frida/releases/download/17.24.2/frida-server-17.24.2-android-x86_64.xz
  printf '%s  %s\n' 2447b5985d210f4add5019aff22b02a3740de18ef985f504b5b70b0b29cf7b0f "$trace_temp/server.xz" | sha256sum --check
  timeout 60s xz --decompress --stdout "$trace_temp/server.xz" > "$trace_temp/server"
  trace_setup_stage=adb-root
  timeout 20s adb -s "$ANDROID_SERIAL" root
  timeout 45s adb -s "$ANDROID_SERIAL" wait-for-device
  [[ "$(timeout 10s adb -s "$ANDROID_SERIAL" shell id -u | tr -d '\r')" == 0 ]]
  timeout 10s adb -s "$ANDROID_SERIAL" shell mkdir "$trace_guest"
  trace_guest_created=true
  timeout 20s adb -s "$ANDROID_SERIAL" push "$trace_temp/server" "$trace_guest/server"
  timeout 10s adb -s "$ANDROID_SERIAL" shell chmod 700 "$trace_guest/server"
  [[ "$(timeout 10s adb -s "$ANDROID_SERIAL" shell "$trace_guest/server" --version | tr -d '\r')" == 17.24.2 ]]
  trace_setup_stage=server-start
  # The remote shell writes its PID, then exec replaces only that shell.
  adb -s "$ANDROID_SERIAL" shell "echo \$\$ > $trace_guest/pid; exec $trace_guest/server --listen=127.0.0.1:27042" \
    > build/playback-validation/subtitle-trace-server.log 2>&1 &
  trace_server_adb_pid=$!
  timeout 10s adb -s "$ANDROID_SERIAL" forward --no-rebind tcp:27043 tcp:27042
  trace_forward_created=true
  trace_setup_stage=server-handshake
  PYTHONPATH="$trace_temp/client" timeout 25s python3 - <<'TRACE_HANDSHAKE'
import frida
import threading
import time
manager = frida.get_device_manager()
deadline = time.monotonic() + 20
while time.monotonic() < deadline:
    cancellable = frida.Cancellable()
    timer = threading.Timer(min(3, deadline - time.monotonic()), cancellable.cancel)
    timer.daemon = True
    timer.start()
    try:
        with cancellable:
            remote = manager.add_remote_device("127.0.0.1:27043")
            parameters = remote.query_system_parameters()
        if parameters.get("arch") != "x64":
            raise SystemExit("Diagnostic server architecture mismatch")
        print("Frida 17.24.2 remote handshake ready")
        break
    except (frida.TransportError, frida.ServerNotRunningError,
            frida.OperationCancelledError, frida.TimedOutError) as error:
        print("Server startup handshake not ready: " + type(error).__name__, flush=True)
        time.sleep(0.2)
    finally:
        timer.cancel()
else:
    raise SystemExit("Diagnostic server handshake deadline expired")
TRACE_HANDSHAKE
  trace_setup_stage=server-process-check
  kill -0 "$trace_server_adb_pid"
  local server_pid
  server_pid=$(timeout 5s adb -s "$ANDROID_SERIAL" shell cat "$trace_guest/pid" | tr -d '\r')
  [[ "$server_pid" =~ ^[0-9]+$ ]]
  [[ "$(timeout 5s adb -s "$ANDROID_SERIAL" shell readlink "/proc/$server_pid/exe" | tr -d '\r')" == "$trace_guest/server" ]]
  trace_setup_stage=runner-start
  PYTHONPATH="$trace_temp/client" timeout --signal=TERM --kill-after=10s 1480s \
    python3 scripts/trace-libvlc-subtitles.py --serial "$ANDROID_SERIAL" \
    --output build/playback-validation/subtitle-trace.jsonl \
    --summary build/playback-validation/subtitle-trace-summary.json \
    > build/playback-validation/subtitle-trace-runner.log 2>&1 &
  trace_runner_pid=$!
  trace_setup_ready=true
  trace_setup_stage=ready
}
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
  # Compile the temporary no-idle snapshot helper against the actual API33
  # public SDK. Missing tooling is a setup failure, never a slow-dump fallback.
  snapshot_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
  snapshot_platform="$snapshot_sdk/platforms/android-33"
  if [[ ! -f "$snapshot_platform/android.jar" ]]; then
    timeout 180s "$snapshot_sdk/cmdline-tools/latest/bin/sdkmanager" 'platforms;android-33' \
      > build/playback-validation/release-ui-sdk-setup.log 2>&1
  fi
  test -f "$snapshot_platform/android.jar"
  timeout 900s python3 scripts/playback-device-actions.py --release-smoke build/release-under-test > build/playback-validation/release-smoke-runner.txt 2>&1
  exit
fi
if [[ "$subtitle_trace" == true ]]; then
  echo 'Subtitle metadata instrumentation enabled: timing/fps from this run are not performance results.'
  setup_subtitle_trace > build/playback-validation/subtitle-trace-setup.log 2>&1
fi
python3 scripts/playback-device-actions.py > build/playback-validation/device-actions.txt 2>&1 &
device_actions_pid=$!
# Ensure the acknowledgement server is ready before the app emits any markers.
for attempt in {1..50}; do
  if curl --silent --fail http://127.0.0.1:8766/health > build/playback-validation/device-capture-backend.json; then
    break
  fi
  sleep 0.1
done
curl --silent --fail http://127.0.0.1:8766/health > /dev/null
if [[ "$subtitle_trace" == true ]]; then
  # Keep the same business command/deadline. Its owned session lets a failed
  # diagnostic terminate only this drive, instead of waiting on a stale VM.
  set +m
  setsid timeout --foreground --kill-after=10s 1200s flutter drive --no-pub -d "$ANDROID_SERIAL" \
    --driver=test_driver/playback_driver.dart \
    --target=integration_test/playback_test.dart &
  trace_drive_pid=$!
  # Poll only our two child PIDs. This also handles a diagnostic that exited
  # before wait began, which Bash wait -n does not reliably return as a job.
  while kill -0 "$trace_runner_pid" 2>/dev/null && kill -0 "$trace_drive_pid" 2>/dev/null; do
    sleep 0.2
  done
  if ! kill -0 "$trace_drive_pid" 2>/dev/null; then
    if wait "$trace_drive_pid"; then completed_status=0; else completed_status=$?; fi
    trace_drive_status=$completed_status
    trace_drive_pid=''
    exit "$completed_status"
  fi
  if wait "$trace_runner_pid"; then completed_status=0; else completed_status=$?; fi
  trace_runner_status=$completed_status
  trace_runner_pid=''
  if [[ "$completed_status" -ne 0 ]]; then
    echo 'Subtitle diagnostic failed; aborting this instrumented drive without restarting the app.' >&2
    if kill -0 "$trace_drive_pid" 2>/dev/null; then trace_aborted_drive=true; fi
    stop_trace_drive
    # If drive had already failed independently, retain its actual exit code.
    if [[ "$trace_aborted_drive" != true && "$trace_drive_status" -ne 0 ]]; then
      exit "$trace_drive_status"
    fi
    exit "$completed_status"
  fi
  # A complete bounded trace may finish before the unchanged playback script.
  if wait "$trace_drive_pid"; then trace_drive_status=0; else trace_drive_status=$?; fi
  trace_drive_pid=''
  exit "$trace_drive_status"
else
  timeout 1200s flutter drive --no-pub -d "$ANDROID_SERIAL" \
    --driver=test_driver/playback_driver.dart \
    --target=integration_test/playback_test.dart
fi
