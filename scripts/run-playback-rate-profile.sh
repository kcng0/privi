#!/usr/bin/env bash
# Installs only com.privi.app.playbackprofile, isolated from the private vault.
# Example: ANDROID_SERIAL=<device serial> PROFILE_HWDEC=auto-safe bash scripts/run-playback-rate-profile.sh
# Example: PROFILE_HWDEC=auto-safe bash scripts/run-playback-rate-profile.sh
# PROFILE_HWDEC=auto runs the same scenes after an explicit mpv hwdec override.
# PROFILE_SCREENRECORD=1 adds a recording (and encoder load); default is off.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
serial="${ANDROID_SERIAL:-${1:-emulator-5554}}"
port="${PROFILE_PORT:-8766}"
[[ "$port" =~ ^[0-9]+$ ]] || { echo 'PROFILE_PORT must be numeric' >&2; exit 2; }
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
output="${PROFILE_OUTPUT:-build/playback-rate-profile}/$run_id"
mkdir -p "$output/fixtures"
output="$(cd "$output" && pwd)"
export PROFILE_OUTPUT="$output" PROFILE_SERIAL="$serial" PROFILE_RUN_ID="$run_id"
export PROFILE_SCREENRECORD="${PROFILE_SCREENRECORD:-0}"
fixture_pid=''
actions_pid=''
reverse_created=0
cleanup() {
  if [[ -n "$actions_pid" ]]; then
    kill "$actions_pid" 2>/dev/null || true
    wait "$actions_pid" 2>/dev/null || true
  fi
  if [[ -n "$fixture_pid" ]]; then
    kill "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
  fi
  if [[ "$reverse_created" == 1 ]]; then
    adb -s "$serial" reverse --remove "tcp:$port" || true
  fi
}
trap cleanup EXIT
adb -s "$serial" get-state
adb -s "$serial" shell getprop ro.build.fingerprint > "$output/device-build.txt"
adb -s "$serial" shell getprop ro.product.model > "$output/device-model.txt"
adb -s "$serial" shell wm size > "$output/device-display.txt"
adb -s "$serial" reverse --list > "$output/adb-reverse-before.txt"
if awk -v port="tcp:$port" '$2 == port { found=1 } END { exit !found }' \
    "$output/adb-reverse-before.txt"; then
  echo "ADB reverse tcp:$port is already in use; choose another PROFILE_PORT" >&2
  exit 2
fi
bash scripts/create-playback-rate-fixture.sh "$output/fixtures"
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$output/fixtures" \
  > "$output/fixture-server.log" 2>&1 &
fixture_pid=$!
python3 - "$port" <<'PY'
import sys
import time
import urllib.request
for attempt in range(30):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/SHA256SUMS", timeout=1) as r:
            assert r.status == 200
        break
    except OSError:
        if attempt == 29:
            raise
        time.sleep(0.1)
PY
kill -0 "$fixture_pid"
adb -s "$serial" reverse "tcp:$port" "tcp:$port"
reverse_created=1

# Keep the output driver separate from the existing playback-validation driver.
cat > "$output/profile_driver.dart" <<'DART'
import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory(Platform.environment['PROFILE_OUTPUT']!);
  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      final metrics = {...?data}..remove('screenshots');
      await File('${output.path}/metrics.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(metrics));
    },
  );
}
DART

# Validate the actual APK before allowing Flutter to install anything. A profile
# run must never replace or uninstall the user's release vault application.
timeout 900s "${FLUTTER_BIN:-flutter}" build apk --profile --no-pub \
  --target=integration_test/playback_rate_profile_test.dart \
  --dart-define="PROFILE_FIXTURE_BASE=http://127.0.0.1:$port" \
  --dart-define="PRIVI_PROFILE_HWDEC=${PROFILE_HWDEC:-}" \
  2>&1 | tee "$output/flutter-build.log"
profile_apk="$PWD/build/app/outputs/flutter-apk/app-profile.apk"
sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
apk_analyzer="${APK_ANALYZER:-${sdk_root}/cmdline-tools/latest/bin/apkanalyzer}"
if [[ ! -x "$apk_analyzer" ]]; then
  echo 'Set APK_ANALYZER to the Android SDK apkanalyzer executable.' >&2
  exit 2
fi
application_id="$("$apk_analyzer" manifest application-id "$profile_apk" | tr -d '\r\n')"
if [[ "$application_id" != com.privi.app.playbackprofile ]]; then
  echo "Refusing installation: unexpected profile applicationId $application_id" >&2
  exit 2
fi
printf '%s\n' "$application_id" > "$output/application-id.txt"

# Only this runner's markers cause device actions. Use -s on every ADB call;
# do not clear logs, change global settings, or interfere with other recordings.
cat > "$output/device_actions.py" <<'PY'
import concurrent.futures
import json
import os
import pathlib
import re
import signal
import subprocess
import time

output = pathlib.Path(os.environ["PROFILE_OUTPUT"])
adb = ["adb", "-s", os.environ["PROFILE_SERIAL"]]
remote = f"/sdcard/privi-rate-profile-{os.environ['PROFILE_RUN_ID']}.mp4"
pidfile = f"/data/local/tmp/privi-rate-profile-{os.environ['PROFILE_RUN_ID']}.pid"
events = []
errors = []
pool = concurrent.futures.ThreadPoolExecutor(max_workers=2)
recording = None
recordlog = None
record_status = {"requested": os.environ["PROFILE_SCREENRECORD"] == "1"}

def event(kind, **data):
    item = {"event": kind, "host_monotonic_ns": time.monotonic_ns(), **data}
    events.append(item)
    print(json.dumps(item), flush=True)

def run(*args, **kwargs):
    return subprocess.run(adb + list(args), check=True, timeout=kwargs.pop("timeout", 15), **kwargs)

def hold(name, x, y, duration):
    try:
        event("hold_start", scene=name, x=x, y=y, duration_ms=duration)
        run("shell", "input", "touchscreen", "swipe", str(x), str(y), str(x), str(y), str(duration),
            timeout=duration / 1000 + 10)
        event("hold_end", scene=name)
    except Exception as error:
        errors.append(f"hold {name}: {error}")

def capture(name):
    ack = output / "fixtures" / f"capture-{name}.done"
    try:
        with (output / f"{name}.png").open("wb") as png:
            run("exec-out", "screencap", "-p", stdout=png)
        ack.write_text("ok")
        event("screenshot", scene=name)
    except Exception as error:
        errors.append(f"capture {name}: {error}")
        ack.write_text(f"error: {error}")

def start_recording():
    global recording, recordlog
    if not record_status["requested"] or recording is not None:
        return
    recordlog = (output / "screenrecord.log").open("w")
    # The pid belongs only to the screenrecord started here. All names contain
    # this runner's generated timestamp/PID, rather than user-supplied shell text.
    command = f"screenrecord --bit-rate 4000000 --time-limit 150 {remote} & echo $! > {pidfile}; wait"
    recording = subprocess.Popen(adb + ["shell", command], stdout=recordlog, stderr=subprocess.STDOUT)
    event("screenrecord_start")

def stop_recording():
    global recording, recordlog
    if recording is None:
        return
    try:
        pid = subprocess.check_output(adb + ["shell", "cat", pidfile], text=True, timeout=5).strip()
        if not pid.isdecimal():
            raise ValueError(f"Invalid task-owned screenrecord PID: {pid!r}")
        if recording.poll() is None:
            run("shell", "kill", "-2", pid)
        recording.wait(timeout=15)
        run("pull", remote, str(output / "screenrecord.mp4"), timeout=30)
        record_status.update(status="captured", command_returncode=recording.returncode)
    except Exception as error:
        record_status.update(status="error", error=str(error))
        print(f"Optional screenrecord failed: {error}", flush=True)
    finally:
        if recording.poll() is None:
            recording.terminate()
            recording.wait(timeout=5)
        subprocess.run(adb + ["shell", "rm", "-f", remote, pidfile], timeout=10, check=False)
        recordlog.close()
        recording = None

def stop(*_):
    raise SystemExit(0)

signal.signal(signal.SIGTERM, stop)
log = subprocess.Popen(adb + ["logcat", "-T", "1", "-v", "raw", "flutter:I", "*:S"],
                       stdout=subprocess.PIPE, text=True)
(output / "device-actions.ready").touch()
try:
    with (output / "flutter-device.log").open("w") as logfile:
        for line in log.stdout:
            marker = line.strip()
            if not marker.startswith("PRIVI_RATE_"):
                continue
            logfile.write(line)
            logfile.flush()
            if marker == "PRIVI_RATE_RUN_START":
                event("run_start")
                start_recording()
            elif marker == "PRIVI_RATE_RUN_END":
                event("run_end")
                stop_recording()
            else:
                match = re.fullmatch(r"PRIVI_RATE_HOLD ([a-z0-9_]+) (\d+) (\d+) (\d+)", marker)
                if match:
                    name, x, y, duration = match.groups()
                    pool.submit(hold, name, int(x), int(y), int(duration))
                match = re.fullmatch(r"PRIVI_RATE_CAPTURE ([a-z0-9_]+)", marker)
                if match:
                    pool.submit(capture, match.group(1))
finally:
    pool.shutdown(wait=True)
    stop_recording()
    log.terminate()
    log.wait(timeout=5)
    (output / "device-actions.json").write_text(json.dumps(
        {"events": events, "errors": errors, "screenrecord": record_status}, indent=2))
    if errors:
        raise SystemExit(1)
PY
python3 "$output/device_actions.py" > "$output/device-actions.log" 2>&1 &
actions_pid=$!
for attempt in {1..50}; do
  [[ -f "$output/device-actions.ready" ]] && break
  kill -0 "$actions_pid"
  sleep 0.1
done
test -f "$output/device-actions.ready"
set +e
timeout 1200s "${FLUTTER_BIN:-flutter}" drive --profile --no-pub -d "$serial" \
  --use-application-binary="$profile_apk" \
  --driver="$output/profile_driver.dart" \
  --target=integration_test/playback_rate_profile_test.dart \
  --dart-define="PROFILE_FIXTURE_BASE=http://127.0.0.1:$port" \
  --dart-define="PRIVI_PROFILE_HWDEC=${PROFILE_HWDEC:-}" \
  2>&1 | tee "$output/flutter-drive.log"
drive_status=${PIPESTATUS[0]}
set -e
kill "$actions_pid" 2>/dev/null || true
actions_status=0
wait "$actions_pid" || actions_status=$?
actions_pid=''

# Optional recording evidence: capture PTS and decoded hashes are left raw.
# Encoder duplicates/noise and UI changes prevent treating either as player FPS.
if [[ -f "$output/screenrecord.mp4" ]]; then
  timeout 60s ffprobe -v error -select_streams v:0 \
    -show_streams -show_frames -show_entries \
    'stream=width,height,r_frame_rate,avg_frame_rate:frame=best_effort_timestamp_time,pkt_duration_time' \
    -of json "$output/screenrecord.mp4" > "$output/screenrecord-pts.json"
  timeout 120s ffmpeg -hide_banner -loglevel error -i "$output/screenrecord.mp4" \
    -an -f framemd5 "$output/screenrecord.framemd5"
fi
printf 'Profile artifacts: %s\n' "$output"
if [[ "$drive_status" != 0 ]]; then exit "$drive_status"; fi
if [[ "$actions_status" != 0 ]]; then exit "$actions_status"; fi
python3 - "$output" <<'PY'
import json
import pathlib
import sys
output = pathlib.Path(sys.argv[1])
metrics = json.loads((output / "metrics.json").read_text())
actions = json.loads((output / "device-actions.json").read_text())
assert metrics.get("completed") is True, "Profile did not complete all scenes"
assert not actions["errors"], actions["errors"]
assert len(metrics["scenes"]) == 6, "All six independent measurement windows are required"
assert len([e for e in actions["events"] if e["event"] == "hold_end"]) == 2
print("scene | native rate | media seconds / wall second | VO / decoder / delayed drops")
for scene in metrics["scenes"]:
    drops = [scene["counter_deltas"][p]["delta"] for p in
             ("frame-drop-count", "decoder-frame-drop-count", "vo-delayed-frame-count")]
    rate = scene["end"]["speed"]["value"]
    progress = scene["media_seconds_per_wall_second"]
    print(f"{scene['name']} | {rate} | {progress} | {drops}")
    assert (output / f"{scene['name']}.png").is_file()
print("No performance threshold applied. Progress ratios and source FPS are NOT video output FPS.")
PY
