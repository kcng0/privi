"""Act only on synthetic integration-test log markers from our emulator."""
import pathlib
import signal
import subprocess
import threading


output = pathlib.Path("build/playback-validation")
recovery = None


def adb(*args):
    subprocess.run(["adb", *args], check=True, timeout=15)


def wake_and_return():
    adb("shell", "input", "keyevent", "224")
    adb("shell", "wm", "dismiss-keyguard")
    adb("shell", "am", "start", "-n", "com.privi.app/.MainActivity")


def recover_after_failure():
    print("Screen-off acknowledgement timed out; waking for failed-test cleanup", flush=True)
    wake_and_return()


log = subprocess.Popen(
    ["adb", "logcat", "-v", "raw", "flutter:I", "*:S"],
    stdout=subprocess.PIPE,
    text=True,
)


def stop(*_args):
    raise SystemExit(0)


signal.signal(signal.SIGTERM, stop)
try:
    for line in log.stdout:
        marker = line.strip()
        if marker == "PRIVI_TEST_PIP_SCREEN_OFF_REVOKED":
            if recovery:
                recovery.cancel()
            print("Screen-off revoked playback before wake", flush=True)
            wake_and_return()
        elif marker == "PRIVI_TEST_PIP_SCREEN_OFF":
            adb("shell", "input", "keyevent", "223")
            recovery = threading.Timer(12, recover_after_failure)
            recovery.start()
        elif marker == "PRIVI_TEST_PIP_EXPAND":
            adb("shell", "am", "start", "-n", "com.privi.app/.MainActivity")
        elif marker.startswith("PRIVI_TEST_PLAYER_SCREENSHOT_"):
            name = marker.removeprefix("PRIVI_TEST_PLAYER_SCREENSHOT_").lower()
            with (output / f"player-{name}-controls.png").open("wb") as screenshot:
                subprocess.run(["adb", "exec-out", "screencap", "-p"],
                               stdout=screenshot, check=True, timeout=15)
        elif marker.startswith("PRIVI_TEST_PIP_FULLSCREEN_"):
            name = marker.removeprefix("PRIVI_TEST_PIP_FULLSCREEN_").lower()
            with (output / f"native-fullscreen-{name}.png").open("wb") as screenshot:
                subprocess.run(["adb", "exec-out", "screencap", "-p"],
                               stdout=screenshot, check=True, timeout=15)
finally:
    if recovery:
        recovery.cancel()
    log.terminate()
