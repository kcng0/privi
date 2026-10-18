"""Drive real Android input and inspect only redistributable fixture pixels.

The app requests actions using log markers and awaits their HTTP acknowledgement.
A failed capture/assertion is returned to the integration test, never silently skipped.
"""
import argparse
import hashlib
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

from PIL import Image, ImageChops, ImageOps, UnidentifiedImageError

OUTPUT = pathlib.Path("build/playback-validation")
SERIAL = os.environ.get("ANDROID_SERIAL", "emulator-5554")
RESULTS = {}
RECOVERY = None
HELD_POINT = None
OUTPUT.mkdir(parents=True, exist_ok=True)


def adb(*args, **kwargs):
    kwargs.setdefault("timeout", 15)
    return subprocess.run(["adb", "-s", SERIAL, *args], check=True,
                          **kwargs)


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


def save_graphics_state(prefix):
    """Observe wake/graphics state without changing renderer, power or frames."""
    commands = {
        "power": ["shell", "dumpsys", "power"],
        "display": ["shell", "dumpsys", "display"],
        "surfaceflinger": ["shell", "dumpsys", "SurfaceFlinger"],
        "threads": ["shell", "ps", "-T", "-A"],
    }
    report = {"captured_monotonic": time.monotonic(), "files": {}}
    for name, arguments in commands.items():
        path = OUTPUT / f"{prefix}-{name}.txt"
        try:
            result = adb(*arguments, capture_output=True, text=True, timeout=2)
            path.write_text(result.stdout)
            report["files"][name] = path.name
        except Exception as error:
            path.write_text(f"{type(error).__name__}: {error}")
            report["files"][name] = {"file": path.name, "error": str(error)}
    (OUTPUT / f"{prefix}-graphics.json").write_text(json.dumps(report, indent=2))


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


def fixture_signature(image, bounds):
    # The external testsrc2 corpus contains broad vivid colour bands. Sparse
    # pink/teal lock controls are not video, even when their bounding box is tall.
    area = image.crop(bounds).convert("HSV").resize((160, 160))
    hues = [0] * 12
    coloured = 0
    for hue, saturation, value in area.getdata():
        if saturation > 60 and value > 70:
            coloured += 1
            hues[min(11, hue * 12 // 256)] += 1
    total = area.width * area.height
    return {"vivid_fraction": coloured / total,
            "vivid_hue_bands": sum(count > total * .01 for count in hues)}


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
    bounds = (box[0] + xs[0], box[1] + ys[0], box[0] + xs[-1] + 1, box[1] + ys[-1] + 1)
    signature = fixture_signature(image, bounds)
    if signature["vivid_fraction"] < .20 or signature["vivid_hue_bands"] < 4:
        raise AssertionError(f"No actual testsrc video: insufficient broad fixture colours {signature}")
    return bounds


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
              "video_aspect_ratio": width / height, "captured_monotonic": time.monotonic(),
              "fixture_signature": fixture_signature(image, bounds)}
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
        if request.get("graphicsDiagnostics"):
            save_graphics_state(request["id"] + "-before-capture")
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


class ReleaseSmoke:
    """Public APK UI only: no VM service, private files or credential bypass."""

    def __init__(self):
        self.sequence = 0
        self.events = []
        self.last_video = None
        self.screenshots_required = False

    def note(self, event, **values):
        self.events.append({"event": event, "monotonic": time.monotonic(), **values})
        (OUTPUT / "release-smoke-events.json").write_text(json.dumps(self.events, indent=2))
        print(json.dumps(self.events[-1]), flush=True)

    def ui(self, label):
        self.sequence += 1
        prefix = f"release-ui-{self.sequence:03d}-{label}"
        remote = "/sdcard/privi-release-smoke-ui.xml"
        try:
            shell_text("uiautomator", "dump", remote)
            source = shell_text("cat", remote)
            (OUTPUT / f"{prefix}.xml").write_text(source)
            root = ET.fromstring(source)
        finally:
            adb("shell", "rm", "-f", remote)
        windows = shell_text("dumpsys", "window")
        (OUTPUT / f"{prefix}-window.txt").write_text(windows)
        if "Application Not Responding:" in windows or "Application Error:" in windows:
            raise RuntimeError(f"Android error dialog during {label}: {focus_from(windows)}")
        self.ui_capture(prefix, windows)
        return root

    @staticmethod
    def secure_window(windows):
        blocks = [block for block in re.split(r"(?m)^  Window #", windows)[1:]
                  if "com.privi.app/" in block.splitlines()[0]]
        flags = [re.search(r"(?m)^\s+fl=([^\n]+)", block) for block in blocks]
        if not flags or any(match is None for match in flags):
            raise RuntimeError("Actual Privi window flags are unavailable")
        return any(re.search(r"\bSECURE\b", match.group(1)) for match in flags)

    def ui_capture(self, prefix, windows):
        if self.screenshots_required:
            capture(prefix)
            return
        # First-run FLAG_SECURE can make screencap return zero bytes. Preserve
        # its actual output, but use the actual accessibility tree for setup.
        # This exception ends permanently after the user disables protection.
        raw = OUTPUT / f"{prefix}-screencap.bin"
        with raw.open("wb") as target:
            result = adb("exec-out", "screencap", "-p", stdout=target, stderr=subprocess.PIPE)
        (OUTPUT / f"{prefix}-screencap-stderr.txt").write_bytes(result.stderr)
        try:
            with Image.open(raw) as image:
                image.load()
                if image.format != "PNG":
                    raise UnidentifiedImageError("screencap did not return PNG")
        except UnidentifiedImageError as error:
            if not self.secure_window(windows):
                raise
            evidence = {"status": "unavailable-while-flag-secure", "raw": raw.name,
                        "raw_bytes": raw.stat().st_size, "native_secure": True,
                        "error": f"{type(error).__name__}: {error}"}
            (OUTPUT / f"{prefix}-capture-unavailable.json").write_text(json.dumps(evidence, indent=2))
            self.note("protected-setup-capture-unavailable", **evidence)
            return
        raw.replace(OUTPUT / f"{prefix}.png")

    def require_screenshots(self):
        if self.secure_window(shell_text("dumpsys", "window")):
            raise AssertionError("Block screenshots UI is off but native FLAG_SECURE remains set")
        self.screenshots_required = True
        self.ui("screenshots-unblocked")
        self.note("strict-native-png-required")

    @staticmethod
    def bounds(node):
        values = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
        if values is None:
            raise RuntimeError(f"UI node has no physical bounds: {node.attrib}")
        return tuple(int(value) for value in values.groups())

    @staticmethod
    def matches(root, label):
        return [node for node in root.iter("node")
                if node.get("enabled") != "false" and any(
                    value == label or value.startswith(label + "\n")
                    for value in (node.get("text", ""), node.get("content-desc", "")))]

    def find(self, label, *, timeout=20, scroll=False):
        deadline = time.monotonic() + timeout
        swipes = 0
        while True:
            root = self.ui("find")
            nodes = self.matches(root, label)
            if nodes:
                clickable = [node for node in nodes if node.get("clickable") == "true"]
                candidates = clickable or nodes
                by_bounds = {self.bounds(node): node for node in candidates}
                if len(by_bounds) != 1:
                    raise RuntimeError(f"Ambiguous UI label {label!r}: {list(by_bounds)}")
                return root, next(iter(by_bounds.values()))
            if time.monotonic() >= deadline:
                raise TimeoutError(f"Release UI did not expose {label!r}")
            if scroll and swipes < 6:
                frame = root.find("node")
                left, top, right, bottom = self.bounds(frame)
                x = str((left + right) // 2)
                adb("shell", "input", "swipe", x, str(round(top + (bottom - top) * .8)),
                    x, str(round(top + (bottom - top) * .4)), "350")
                swipes += 1
            time.sleep(.3)

    def tap(self, label, **kwargs):
        _, node = self.find(label, **kwargs)
        left, top, right, bottom = self.bounds(node)
        adb("shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))
        self.note("tap", label=label, bounds=[left, top, right, bottom])

    def switch(self, label, enabled, *, scroll=False):
        def control_for(root, node):
            parents = {child: parent for parent in root.iter() for child in parent}
            candidate = node
            while candidate is not None:
                controls = [item for item in candidate.iter("node") if item.get("checkable") == "true"]
                if len(controls) == 1:
                    return controls[0]
                candidate = parents.get(candidate)
            raise RuntimeError(f"UI switch state is unavailable for {label!r}")

        root, node = self.find(label, scroll=scroll)
        control = control_for(root, node)
        previous = control.get("checked") == "true"
        if previous != enabled:
            left, top, right, bottom = self.bounds(control)
            adb("shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))
            root, node = self.find(label)
            if (control_for(root, node).get("checked") == "true") != enabled:
                raise AssertionError(f"Actual UI switch did not change {label!r} to {enabled}")
        self.note("switch", label=label, requested=enabled, previous=previous)

    def pattern(self, title):
        root, _ = self.find(title)
        frame_left, _, frame_right, _ = self.bounds(root.find("node"))
        width = frame_right - frame_left
        candidates = []
        for node in root.iter("node"):
            if node.get("package") != "com.privi.app" or node.get("scrollable") != "true":
                continue
            left, top, right, bottom = self.bounds(node)
            if .35 * width < right - left < .95 * width and .90 < (right - left) / max(1, bottom - top) < 1.10:
                candidates.append((left, top, right, bottom))
        if len(set(candidates)) != 1:
            raise RuntimeError(f"Pattern grid is not uniquely exposed in actual accessibility bounds: {candidates}")
        left, top, right, bottom = candidates[0]
        # The public 3x3 gesture widget places dots at 12%, 50%, 88% of
        # its actual accessible square. This is input geometry, not a video oracle.
        points = [(round(left + (right - left) * x), round(top + (bottom - top) * y))
                  for x, y in [(.12, .12), (.50, .12), (.50, .50), (.50, .88)]]
        commands = [f"input motionevent DOWN {points[0][0]} {points[0][1]}"]
        for start, end in zip(points, points[1:]):
            for step in range(1, 13):
                x = round(start[0] + (end[0] - start[0]) * step / 12)
                y = round(start[1] + (end[1] - start[1]) * step / 12)
                commands.append(f"input motionevent MOVE {x} {y}")
        commands.append(f"input motionevent UP {points[-1][0]} {points[-1][1]}")
        adb("shell", "; ".join(commands))
        self.note("real-pattern-input", title=title, grid_bounds=candidates[0])

    def unlock_if_needed(self):
        if self.matches(self.ui("possible-lock"), "Draw your pattern"):
            self.pattern("Draw your pattern")

    def sample(self, label, *, compare_to=None, hidden=False):
        identifier = f"release-action-{len(RESULTS) + 1}"
        request = {"id": identifier, "op": "capture", "name": label}
        if hidden:
            _, image = capture(label + "-raw")
            request.update({"expectNoVideo": True, "viewport": [0, 0, *image.size]})
        else:
            request["aspect"] = 180 / 320
        if compare_to:
            request["compareTo"] = compare_to
        window = action_window(request)
        try:
            result = {"ok": True, "request": request, **window, **inspect_capture(request)}
        except Exception as error:
            RESULTS[identifier] = {"ok": False, "request": request, "error": str(error)}
            persist()
            raise
        RESULTS[identifier] = result
        persist()
        if not hidden:
            self.last_video = result["video_bounds"]
        return identifier

    def blank(self):
        if self.last_video is None:
            raise RuntimeError("Blank input requires actual fixture video bounds")
        left, top, right, bottom = self.last_video
        return round((left + right) / 2), round(top + (bottom - top) * .45)

    def controls(self, visible):
        root = self.ui("controls-before")
        if bool(self.matches(root, "Player settings")) != visible:
            x, y = self.blank()
            adb("shell", "input", "tap", str(x), str(y))
        deadline = time.monotonic() + 8
        while bool(self.matches(self.ui("controls-after"), "Player settings")) != visible:
            if time.monotonic() >= deadline:
                raise AssertionError(f"Real blank tap did not make controls visible={visible}")
            time.sleep(.2)
        self.note("blank-tap-controls", visible=visible)

    def motion(self, label):
        first = self.sample(label + "-first")
        time.sleep(2.1)
        second = self.sample(label + "-second", compare_to=first)
        return first, second

    def badge(self, identifier, expected):
        path = OUTPUT / RESULTS[identifier]["screenshot"]
        with Image.open(path) as image:
            width, height = image.size
            # Read only the actual top-centre badge pixels. Host OCR does not
            # connect accessibility or request an application rendering frame.
            area = ImageOps.invert(image.crop((width // 4, 0, width * 3 // 4,
                                               height * 3 // 10)).convert("L"))
            area = area.resize((width, height * 6 // 10))
        crop = OUTPUT / (path.stem + "-badge.png")
        area.save(crop)
        result = subprocess.run(["tesseract", str(crop), "stdout", "--psm", "11"],
                                check=True, capture_output=True, text=True, timeout=10)
        (OUTPUT / (path.stem + "-badge-ocr.txt")).write_text(result.stdout)
        visible = bool(re.search(r"(?<![A-Za-z0-9])2\s*[xX×](?![A-Za-z0-9])", result.stdout))
        if visible != expected:
            raise AssertionError(f"Actual PNG 2x badge visible={visible}, expected={expected}: {path.name}")
        self.note("native-png-2x-badge", screenshot=path.name, visible=visible)

    def hold(self, label):
        self.controls(False)
        x, y = self.blank()
        try:
            adb("shell", "input", "motionevent", "DOWN", str(x), str(y))
            time.sleep(.7)
            held_frames = self.motion(label + "-2x")
        finally:
            adb("shell", "input", "motionevent", "UP", str(x), str(y))
        for frame in held_frames:
            self.badge(frame, True)
        time.sleep(.4)
        for frame in self.motion(label + "-released"):
            self.badge(frame, False)

    def power(self, awake):
        deadline = time.monotonic() + 12
        while True:
            power = shell_text("dumpsys", "power")
            if ("mWakefulness=Awake" if awake else "mWakefulness=Asleep") in power:
                self.note("physical-power-state", awake=awake)
                return
            if time.monotonic() >= deadline:
                raise TimeoutError(f"Physical power did not become awake={awake}")
            time.sleep(.2)

    def pip_return(self, label, screen_off):
        self.controls(True)
        self.tap("Picture in picture")
        deadline = time.monotonic() + 10
        while True:
            activities = shell_text("dumpsys", "activity", "activities")
            if re.search(r"(?:mode=pinned|windowingMode=2|mWindowingMode=2)", activities, re.I):
                (OUTPUT / f"{label}-pip-activities.txt").write_text(activities)
                break
            if time.monotonic() >= deadline:
                raise TimeoutError("Actual Activity did not enter pinned/PiP mode")
            time.sleep(.2)
        capture(label + "-pip")
        if screen_off:
            adb("shell", "input", "keyevent", "223")
            self.power(False)
            save_graphics_state(label + "-asleep")
            capture(label + "-asleep")
            adb("shell", "input", "keyevent", "224")
            self.power(True)
            adb("shell", "wm", "dismiss-keyguard")
        adb("shell", "am", "start", "-n", "com.privi.app/.MainActivity")
        self.find("Draw your pattern")
        save_graphics_state(label + "-locked-fullscreen")
        self.sample(label + "-locked-fullscreen", hidden=True)
        self.pattern("Draw your pattern")
        self.controls(True)
        self.tap("Play")
        self.controls(False)
        save_graphics_state(label + "-unlocked")
        self.motion(label + "-restored")
        self.controls(True)
        self.controls(False)


def release_smoke(artifact_directory):
    smoke = ReleaseSmoke()
    report = {"passed": False, "release_run_id": os.environ.get("RELEASE_RUN_ID"),
              "repository": os.environ.get("RELEASE_REPOSITORY")}
    try:
        apks = list(pathlib.Path(artifact_directory).rglob("*.apk"))
        if len(apks) != 1:
            raise RuntimeError(f"Expected exactly one release APK artifact, found {len(apks)}")
        apk = apks[0]
        digest = hashlib.sha256(apk.read_bytes()).hexdigest()
        expected = pathlib.Path(str(apk) + ".sha256").read_text().split()[0].lower()
        if digest != expected:
            raise AssertionError("Downloaded release APK does not match its supplied SHA-256")
        report.update({"apk": str(apk), "apk_sha256": digest})
        if shell_text("pm", "list", "packages", "com.privi.app"):
            raise RuntimeError("Release smoke requires a fresh emulator without an existing Privi installation")
        installed = adb("install", "--no-streaming", str(apk), capture_output=True, text=True, timeout=120)
        (OUTPUT / "release-apk-install.txt").write_text(installed.stdout + installed.stderr)
        package = shell_text("dumpsys", "package", "com.privi.app")
        (OUTPUT / "release-installed-package.txt").write_text(package)
        if re.search(r"(?:pkgFlags|flags)=\[[^\]]*\bDEBUGGABLE\b", package):
            raise AssertionError("Selected APK is debuggable rather than an actual release APK")
        # Extend the verified 3s source by stream copying, so real setup/PiP UI
        # cannot reach EOF while the smoke is still navigating. Geometry and
        # motion expectations remain those of the external 180x320 source.
        video = OUTPUT / "PriviReleaseSmoke.mp4"
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                        "-stream_loop", "-1", "-i", "integration_test/fixtures/portrait.mp4",
                        "-t", "600", "-map", "0:v:0", "-map", "0:a:0", "-c", "copy",
                        "-movflags", "+faststart", str(video)], check=True, timeout=45)
        probe = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format",
                                "-of", "json", str(video)], check=True, capture_output=True,
                               text=True, timeout=15)
        (OUTPUT / "release-synthetic-video.ffprobe.json").write_text(probe.stdout)
        report["synthetic_video_sha256"] = hashlib.sha256(video.read_bytes()).hexdigest()
        remote = "/sdcard/Movies/PriviReleaseSmoke/PriviReleaseSmoke.mp4"
        adb("shell", "mkdir", "-p", "/sdcard/Movies/PriviReleaseSmoke")
        adb("push", str(video), remote, capture_output=True, timeout=60)
        adb("shell", "am", "broadcast", "-a", "android.intent.action.MEDIA_SCANNER_SCAN_FILE",
            "-d", "file://" + remote, capture_output=True)
        media_deadline = time.monotonic() + 15
        while True:
            media = shell_text("content", "query", "--uri", "content://media/external/video/media",
                               "--projection", "_id:_display_name:relative_path")
            (OUTPUT / "release-synthetic-mediastore.txt").write_text(media)
            if "PriviReleaseSmoke.mp4" in media:
                break
            if time.monotonic() >= media_deadline:
                raise TimeoutError("Synthetic video was not actually registered in MediaStore")
            time.sleep(.3)
        adb("shell", "am", "start", "-W", "-n", "com.privi.app/.MainActivity")
        smoke.pattern("Draw a pattern")
        smoke.pattern("Confirm pattern")
        if smoke.matches(smoke.ui("after-pattern-setup"), "Not now"):
            smoke.tap("Not now")
        smoke.tap("More")
        smoke.tap("Settings")
        smoke.switch("Block screenshots", False)
        smoke.require_screenshots()
        smoke.switch("Prefer external player", False, scroll=True)
        adb("shell", "input", "keyevent", "4")
        smoke.tap("Visible")
        root = smoke.ui("media-filter")
        if smoke.matches(root, "Photos only · tap for videos"):
            smoke.tap("Photos only · tap for videos")
        root = smoke.ui("gallery-permission")
        if smoke.matches(root, "Grant permission"):
            smoke.tap("Grant permission")
            smoke.tap("Allow")
            smoke.unlock_if_needed()
        _, folder = smoke.find("PriviReleaseSmoke")
        left, top, right, bottom = smoke.bounds(folder)
        adb("shell", "input", "swipe", str((left + right) // 2), str((top + bottom) // 2),
            str((left + right) // 2), str((top + bottom) // 2), "1000")
        smoke.tap("Hide")
        root = smoke.ui("hide-access")
        if smoke.matches(root, "Open settings"):
            smoke.tap("Open settings")
            smoke.switch("Allow access to manage all files", True)
            adb("shell", "input", "keyevent", "4")
            smoke.unlock_if_needed()
            _, folder = smoke.find("PriviReleaseSmoke")
            left, top, right, bottom = smoke.bounds(folder)
            adb("shell", "input", "swipe", str((left + right) // 2), str((top + bottom) // 2),
                str((left + right) // 2), str((top + bottom) // 2), "1000")
            smoke.tap("Hide")
        smoke.find("Hide folder?")
        smoke.tap("Hide")
        smoke.tap("Invisible")
        smoke.tap("PriviReleaseSmoke", timeout=40)
        smoke.tap("Play playlist")
        smoke.tap("In order")
        smoke.find("Player settings")
        _, initial_image = capture("release-player-initial-controls")
        # Only bootstrap the blank-input point from observed content. The
        # strict geometry/motion assertion follows with the real controls hidden.
        smoke.last_video = content_bounds(initial_image, [0, 0, *initial_image.size])
        smoke.controls(False)
        smoke.sample("release-player-initial")
        for cycle in range(1, 3):
            smoke.hold(f"release-{cycle}-hold")
            smoke.pip_return(f"release-{cycle}-expand", False)
            smoke.pip_return(f"release-{cycle}-screen-off", True)
        report["passed"] = True
        report["completed_cycles"] = 2
    except Exception as error:
        report["error"] = f"{type(error).__name__}: {error}"
        save_device_state("release-smoke-failed")
        save_graphics_state("release-smoke-failed")
        try:
            smoke.ui("failure")
        except Exception as diagnostic_error:
            report["ui_diagnostic_error"] = str(diagnostic_error)
        raise
    finally:
        (OUTPUT / "release-smoke-result.json").write_text(json.dumps(report, indent=2))
        save_device_state("release-smoke-final")
        save_graphics_state("release-smoke-final")


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
                    if request["op"] in ("capture", "screenshot") and not request.get("graphicsDiagnostics"):
                        save_graphics_state(identifier + "-failed-capture")
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
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--preflight", action="store_true")
    modes.add_argument("--release-smoke", metavar="ARTIFACT_DIRECTORY")
    arguments = parser.parse_args()
    if arguments.preflight:
        preflight()
    elif arguments.release_smoke:
        release_smoke(arguments.release_smoke)
    else:
        main()
