"""Drive real Android input and inspect only redistributable fixture pixels.

The app requests actions using log markers and awaits their HTTP acknowledgement.
A failed capture/assertion is returned to the integration test, never silently skipped.
"""
import argparse
import json
import os
import pathlib
import re
import signal
import subprocess
import threading
import time
import uuid
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from PIL import Image, ImageChops

OUTPUT = pathlib.Path("build/playback-validation")
SERIAL = os.environ.get("ANDROID_SERIAL", "emulator-5554")
RESULTS = {}
RECOVERY = None
HELD_POINT = None
OUTPUT.mkdir(parents=True, exist_ok=True)


def adb(*args, **kwargs):
    return subprocess.run(["adb", "-s", SERIAL, *args], check=True,
                          timeout=15, **kwargs)


def shell_text(*args):
    return adb("shell", *args, capture_output=True, text=True).stdout.strip()


def focus_from(windows):
    return next((line.strip() for line in windows.splitlines()
                 if "mCurrentFocus=" in line), "mCurrentFocus=<unavailable>")


def save_device_state(prefix):
    """Preserve the system failure; never dismiss or disable an ANR dialog."""
    commands = {
        "window": ["shell", "dumpsys", "window"],
        "activities": ["shell", "dumpsys", "activity", "activities"],
        "logcat": ["logcat", "-d", "-v", "threadtime"],
    }
    for name, arguments in commands.items():
        try:
            result = adb(*arguments, capture_output=True, text=True)
            (OUTPUT / f"{prefix}-{name}.txt").write_text(result.stdout)
        except Exception as error:
            (OUTPUT / f"{prefix}-{name}-error.txt").write_text(str(error))
    try:
        capture(f"{prefix}-screen")
    except Exception as error:
        (OUTPUT / f"{prefix}-screen-error.txt").write_text(str(error))


def preflight():
    """Require a usable disposable emulator before installing the tested app."""
    report = {"serial": SERIAL, "samples": [], "ready": False}
    deadline = time.monotonic() + 120
    try:
        # Preserve first-boot failures even when a later attempt becomes ready.
        save_device_state("preflight-initial")
        report["features"] = shell_text("pm", "list", "features").splitlines()
        report["pip_feature"] = shell_text("pm", "has-feature", "android.software.picture_in_picture")
        if report["pip_feature"] != "true":
            raise RuntimeError("Emulator does not expose the required real PiP feature")
        while time.monotonic() < deadline:
            boot = shell_text("getprop", "sys.boot_completed")
            animation = shell_text("getprop", "init.svc.bootanim")
            report["samples"].append({"boot_completed": boot, "boot_animation": animation})
            if boot == "1" and animation in ("", "stopped"):
                break
            time.sleep(1)
        else:
            raise TimeoutError("Android boot did not complete within preflight deadline")
        resolved = shell_text("cmd", "package", "resolve-activity", "--brief",
                              "-a", "android.intent.action.MAIN", "-c", "android.intent.category.HOME")
        component = next((line.strip() for line in reversed(resolved.splitlines())
                          if re.fullmatch(r"[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+", line.strip())), None)
        if component is None or component.startswith("android/"):
            raise RuntimeError(f"No unambiguous HOME Activity: {resolved}")
        package = component.split("/", 1)[0]
        report["home_component"] = component
        adb("shell", "input", "keyevent", "224")
        adb("shell", "wm", "dismiss-keyguard")
        report["home_start"] = shell_text("am", "start", "-W", "-a", "android.intent.action.MAIN",
                                           "-c", "android.intent.category.HOME", "-n", component)
        stable_since = None
        while time.monotonic() < deadline:
            windows = shell_text("dumpsys", "window")
            activities = shell_text("dumpsys", "activity", "activities")
            focus = focus_from(windows)
            resumed = [line.strip() for line in activities.splitlines()
                       if "mResumedActivity" in line or "topResumedActivity" in line]
            report["samples"].append({"focus": focus, "resumed": resumed})
            if "Application Not Responding:" in windows or "Application Error:" in windows:
                raise RuntimeError(f"System error dialog blocks preflight: {focus}")
            home_ready = package + "/" in focus and any(package + "/" in line for line in resumed)
            if home_ready:
                if stable_since is None:
                    stable_since = time.monotonic()
                if time.monotonic() - stable_since >= 8:
                    break
            else:
                stable_since = None
            time.sleep(1)
        else:
            raise TimeoutError("HOME did not retain focus/resume for 8 seconds before deadline")
        # A responsive accessibility hierarchy is independent of mere boot props.
        remote_xml = "/sdcard/privi-playback-preflight.xml"
        try:
            report["ui_dump"] = shell_text("uiautomator", "dump", remote_xml)
            hierarchy = shell_text("cat", remote_xml)
            (OUTPUT / "preflight-ui.xml").write_text(hierarchy)
            root = ET.fromstring(hierarchy)
            if not any(node.get("package") == package for node in root.iter("node")):
                raise RuntimeError("Responsive HOME hierarchy is missing its resolved launcher package")
        finally:
            adb("shell", "rm", "-f", remote_xml)
        # Reject a dialog or focus loss which arose while obtaining the hierarchy.
        final_windows = shell_text("dumpsys", "window")
        if package + "/" not in focus_from(final_windows) or "Application Not Responding:" in final_windows:
            raise RuntimeError("HOME lost focus or entered ANR during hierarchy inspection")
        report["ready"] = True
        print(f"Emulator preflight ready: {component}; PiP=true; stable HOME focus and responsive hierarchy", flush=True)
    except Exception as error:
        report["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        (OUTPUT / "preflight.json").write_text(json.dumps(report, indent=2))
        save_device_state("preflight-final")


def action_window(request):
    windows = shell_text("dumpsys", "window")
    (OUTPUT / f"{request['id']}-window.txt").write_text(windows)
    focus = focus_from(windows)
    if "Application Not Responding:" in windows or "Application Error:" in windows:
        capture(f"{request['id']}-blocked")
        raise RuntimeError(f"Android ANR/crash dialog is visible: {focus}")
    # Raw PiP composition intentionally has HOME focused. All touch/fullscreen
    # content assertions must target the real foreground Privi Activity.
    if request["op"] != "screenshot" and "com.privi.app/" not in focus:
        capture(f"{request['id']}-blocked")
        raise RuntimeError(f"Privi is not the focused Android window: {focus}")
    return {"android_foreground_window": focus}


def persist():
    temporary = OUTPUT / "device-evidence.tmp"
    temporary.write_text(json.dumps(RESULTS, indent=2))
    temporary.replace(OUTPUT / "device-evidence.json")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            value = {"engine": "libvlc", "capture": "adb-screencap"}
        elif self.path.startswith("/result/"):
            value = RESULTS.get(self.path.removeprefix("/result/"))
        else:
            value = None
        self.send_response(200 if value is not None else 404)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(value).encode())

    def log_message(self, *_args):
        pass


def wake_and_return():
    adb("shell", "input", "keyevent", "224")
    adb("shell", "wm", "dismiss-keyguard")
    adb("shell", "am", "start", "-n", "com.privi.app/.MainActivity")


def recover_after_failure():
    print("Screen-off acknowledgement timed out; waking for failed-test cleanup", flush=True)
    wake_and_return()


def capture(name):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", name):
        raise ValueError("Invalid screenshot name")
    path = OUTPUT / f"{name}.png"
    with path.open("wb") as target:
        adb("exec-out", "screencap", "-p", stdout=target)
    with Image.open(path) as source:
        image = source.convert("RGB")
    return path, image


def content_bounds(image, viewport):
    # testsrc2 has strongly saturated colour bars throughout its display area.
    # Black letterboxing, white HUD text and the grey navigation bar do not count.
    box = tuple(round(value) for value in viewport)
    area = image.crop(box)
    red, green, blue = area.split()
    maximum = ImageChops.lighter(ImageChops.lighter(red, green), blue)
    minimum = ImageChops.darker(ImageChops.darker(red, green), blue)
    mask = ImageChops.multiply(
        ImageChops.subtract(maximum, minimum).point(lambda value: 255 if value > 45 else 0),
        maximum.point(lambda value: 255 if value > 70 else 0),
    )
    xs = [x for x in range(mask.width)
          if mask.crop((x, 0, x + 1, mask.height)).histogram()[255] >= max(3, mask.height * .01)]
    ys = [y for y in range(mask.height)
          if mask.crop((0, y, mask.width, y + 1)).histogram()[255] >= max(3, mask.width * .01)]
    if not xs or not ys:
        raise AssertionError("No actual synthetic video pixels in native screenshot")
    return (box[0] + xs[0], box[1] + ys[0], box[0] + xs[-1] + 1, box[1] + ys[-1] + 1)


def inspect_capture(request):
    path, image = capture(request["name"])
    if request["op"] == "screenshot":
        return {"screenshot": path.name, "screen_size": image.size,
                "inspection": "raw-composition-for-review"}
    if request.get("expectNoVideo"):
        # The lock UI may contain one accent colour. The synthetic source has
        # several vivid hue bands; do not confuse a lock button with a leak.
        area = image.crop(tuple(round(v) for v in request["viewport"]))
        hues = [0] * 12
        for hue, saturation, value in area.convert("HSV").resize((120, 120)).getdata():
            if saturation > 60 and value > 70:
                hues[min(11, hue * 12 // 256)] += 1
        bands = sum(count > 120 * 120 * .008 for count in hues)
        if bands >= 4:
            raise AssertionError(f"Locked screen still contains synthetic video colours ({bands} hue bands)")
        return {"screenshot": path.name, "visible_vivid_hue_bands": bands,
                "private_fixture_hidden": True}
    bounds = content_bounds(image, request.get("viewport", [0, 0, *image.size]))
    left, top, right, bottom = bounds
    width, height = right - left, bottom - top
    result = {"screenshot": path.name, "screen_size": image.size, "video_bounds": bounds,
              "video_aspect_ratio": width / height, "captured_monotonic": time.monotonic()}
    if "aspect" in request:
        expected = request["aspect"]
        if abs(width / height - expected) > max(.02, expected * .025):
            raise AssertionError(f"Native content ratio {width / height:.4f}, fixture expects {expected:.4f}")
    if "physicalSize" in request:
        expected_width, expected_height = request["physicalSize"]
        if abs(width - expected_width) > 4 or abs(height - expected_height) > 4:
            raise AssertionError(f"Original video is {width}x{height} physical pixels; fixture expects {expected_width}x{expected_height}")
    if "compareTo" in request:
        prior = RESULTS[request["compareTo"]]
        if not prior["ok"]:
            raise AssertionError("Previous frame capture failed")
        if tuple(prior["video_bounds"]) != bounds:
            # A 2px decoder border fluctuation is harmless; a layout change is not motion.
            if max(abs(a - b) for a, b in zip(prior["video_bounds"], bounds)) > 2:
                raise AssertionError("Video bounds changed between motion samples")
        with Image.open(OUTPUT / prior["screenshot"]) as source:
            previous = source.convert("RGB")
        # Keep only the central video interior: no 2x badge, top bar, seek bar,
        # bottom controls or subtitle band can satisfy the frame-change check.
        roi = (round(left + width * .12), round(top + height * .28),
               round(right - width * .12), round(top + height * .70))
        before, after = previous.crop(roi), image.crop(roi)
        difference = ImageChops.difference(before, after)
        changed = ImageChops.lighter(ImageChops.lighter(*difference.split()[:2]),
                                    difference.split()[2]).point(lambda value: 255 if value > 18 else 0)
        fraction = changed.histogram()[255] / (changed.width * changed.height)
        cells = 0
        for x in range(4):
            for y in range(4):
                tile = changed.crop((x * changed.width // 4, y * changed.height // 4,
                                     (x + 1) * changed.width // 4, (y + 1) * changed.height // 4))
                if tile.histogram()[255] / (tile.width * tile.height) > .005:
                    cells += 1
        result.update({"content_roi": roi, "changed_fraction": fraction,
                       "changed_tiles_of_16": cells,
                       "sample_interval_seconds": result["captured_monotonic"] - prior["captured_monotonic"]})
        expectation = request.get("expect", "motion")
        if expectation == "motion" and (fraction < .005 or cells < 3):
            raise AssertionError(f"Native video appears frozen: {fraction:.5f} changed, {cells}/16 content tiles")
        if expectation == "static" and fraction > .002:
            raise AssertionError(f"Paused native video moved: {fraction:.5f} changed")
    return result


def perform(request):
    global HELD_POINT
    operation = request["op"]
    if operation in ("capture", "screenshot"):
        return inspect_capture(request)
    x, y = (round(value) for value in request["point"])
    if operation == "tap":
        adb("shell", "input", "tap", str(x), str(y))
    elif operation == "down":
        if HELD_POINT is not None:
            raise AssertionError("An earlier Android DOWN is still held")
        adb("shell", "input", "motionevent", "DOWN", str(x), str(y))
        HELD_POINT = (x, y)
    elif operation == "up":
        if HELD_POINT is None:
            raise AssertionError("Android UP has no matching DOWN")
        adb("shell", "input", "motionevent", "UP", str(x), str(y))
        HELD_POINT = None
    else:
        raise ValueError(f"Unknown native action {operation}")
    return {"android_input": operation, "physical_point": [x, y], "monotonic": time.monotonic()}


def stop(*_args):
    raise SystemExit(0)


def main():
    global RECOVERY, HELD_POINT
    server = ThreadingHTTPServer(("0.0.0.0", 8766), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    log = subprocess.Popen(["adb", "-s", SERIAL, "logcat", "-v", "raw",
                            "flutter:I", "PriviPlaybackValidation:I", "*:S"],
                           stdout=subprocess.PIPE, text=True)
    # Keep old/boot logs for diagnosis, but never execute their test markers.
    # A device-written fence remains in the buffer even if logcat connects late.
    fence = f"PRIVI_TEST_SESSION_{uuid.uuid4().hex}"
    (OUTPUT / "device-action-session.json").write_text(json.dumps({"fence": fence}))
    armed = False
    signal.signal(signal.SIGTERM, stop)
    try:
        adb("shell", "log", "-p", "i", "-t", "PriviPlaybackValidation", fence)
        for line in log.stdout:
            marker = line.strip()
            if marker == fence:
                armed = True
                print(f"Live Android actions armed at {fence}", flush=True)
                continue
            if not armed:
                continue
            if marker.startswith("PRIVI_TEST_DEVICE "):
                request = json.loads(marker.removeprefix("PRIVI_TEST_DEVICE "))
                identifier = request["id"]
                try:
                    window = action_window(request)
                    value = {"ok": True, "request": request, **window, **perform(request)}
                except Exception as error:
                    value = {"ok": False, "request": request, "error": f"{type(error).__name__}: {error}"}
                    if request["op"] == "up" and HELD_POINT is not None:
                        # Release our held input even if an ANR/focus assertion
                        # failed; do not dismiss the dialog or turn failure green.
                        try:
                            adb("shell", "input", "motionevent", "UP", *(str(v) for v in HELD_POINT))
                            HELD_POINT = None
                        except Exception as cleanup_error:
                            value["release_error"] = str(cleanup_error)
                RESULTS[identifier] = value
                persist()
                print(json.dumps({"id": identifier, **value}), flush=True)
            elif marker == "PRIVI_TEST_PIP_SCREEN_OFF_REVOKED":
                if RECOVERY:
                    RECOVERY.cancel()
                print("Screen-off revoked playback before wake", flush=True)
                wake_and_return()
            elif marker == "PRIVI_TEST_PIP_SCREEN_OFF":
                adb("shell", "input", "keyevent", "223")
                RECOVERY = threading.Timer(12, recover_after_failure)
                RECOVERY.start()
            elif marker == "PRIVI_TEST_PIP_EXPAND":
                adb("shell", "am", "start", "-n", "com.privi.app/.MainActivity")
    finally:
        if RECOVERY:
            RECOVERY.cancel()
        if HELD_POINT is not None:
            adb("shell", "input", "motionevent", "UP", *(str(v) for v in HELD_POINT))
        log.terminate()
        server.shutdown()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight", action="store_true")
    arguments = parser.parse_args()
    if arguments.preflight:
        preflight()
    else:
        main()
