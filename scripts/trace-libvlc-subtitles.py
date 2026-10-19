#!/usr/bin/env python3
"""Observe LibVLC subtitle metadata on the disposable Android CI emulator.

This is an optional diagnostic tool, not a playback test or a performance run.
It only waits for com.privi.app, attaches once, and records the embedded agent's
bounded metadata. It never drives input, changes playback, or reads cue text,
file paths, image bytes, or other applications' processes.

Requires the official frida==17.24.2 client and matching loopback server.
Supports only the x86_64 fixed-source SDK from build 39158862339, source commit
e344a6cf7c78b75f48b62819c89fd264ff1ec4e9. Other native builds fail closed.
Its libvlc.so SHA256 is
850f6c822b8c46bb342b20ff6e75b268a4971b89c83c40c8fdb055600d3e183a.
The embedded JS is frozen at SHA256
 3655009d5f401127365ec399978bf3c4d03c8a46863f2cfed3292ef6e69897e9.
Frida 17 API: Process.attachModuleObserver, setImmediate, module.enumerateExports;
Python: DeviceManager.add_remote_device, Device.attach, Session.create_script.
Official JS reference: https://frida.re/docs/javascript-api/
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import threading
import time


FRIDA_VERSION = "17.24.2"
PACKAGE = "com.privi.app"
ENDPOINT = "127.0.0.1:27043"
AGENT_SHA256 = "3655009d5f401127365ec399978bf3c4d03c8a46863f2cfed3292ef6e69897e9"
AGENT_SOURCE = r'''
'use strict';
/*
 * Diagnostic only. Frida 17.24.2, Android x86_64, fixed-source SDK 39158862339.
 * Only observes public exports. Never reads cue text, image bytes or file paths;
 * never changes arguments, return values, clocks, track state or playback.
 * Send payloads are bounded JSON metadata. Device UTC is measured at each hook.
 */
(() => {
  // Taken from the actual AAR's ELF note and dynamic function symbols.
  const BUILD_ID = '4bf536e8ca511fca34235e315b22156fba5f182e';
  const OFFSETS = {
    decoder_NewSubpicture: 0xea31e0,
    input_DecoderFlush: 0xea4270,
    ass_process_chunk: 0x162bbc0,
    ass_render_frame: 0x162fb90,
    vout_PutSubpicture: 0xebb6b0,
    spu_PutSubpicture: 0xec36b0,
    spu_ClearChannel: 0xec39b0,
    spu_Render: 0xec3a60,
    subpicture_Delete: 0xedf7f0,
  };
  const LIMIT = { waitForCueMs: 600000, traceMs: 240000,
    events: 8000, actors: 1024, subpictures: 2048, regions: 64, sampleMs: 500 };
  let stopped = false, installed = false, eventCount = 0, firstCueAt = 0;
  let observer = null, waitTimer = null, traceTimer = null, pendingInstall = null;
  let nextActor = 0, nextSubpicture = 0;
  const listeners = [], actors = new Map(), subpictures = new Map();
  const lastByThread = new Map(), sampleState = new Map(), counters = {};

  function raw(event, fields = {}) {
    send(Object.assign({ probe: 'libvlc-spu-public-v1', event,
      device_utc_ms: Date.now(), sequence: ++eventCount }, fields));
  }
  function stop(reason) {
    if (stopped) return;
    stopped = true;
    if (pendingInstall !== null) clearImmediate(pendingInstall);
    if (waitTimer !== null) clearTimeout(waitTimer);
    if (traceTimer !== null) clearTimeout(traceTimer);
    if (observer !== null) observer.detach();
    for (const listener of listeners) listener.detach();
    raw('stopped', { reason, counters, first_cue_utc_ms: firstCueAt || null,
      tracked_subpictures: subpictures.size });
    subpictures.clear(); lastByThread.clear(); sampleState.clear(); actors.clear();
  }
  function emit(event, fields = {}) {
    if (stopped) return;
    if (eventCount >= LIMIT.events) { stop('event-limit'); return; }
    raw(event, fields);
  }
  function fail(code, hook) {
    // Do not serialize exception messages: native addresses or paths may leak.
    emit('probe-error', { code, hook: hook || null });
    stop(code);
  }
  function guarded(hook, fn) {
    return function (...args) {
      if (stopped) return;
      counters[hook] = (counters[hook] || 0) + 1;
      try { return fn.apply(this, args); }
      catch (_) { fail('metadata-read-or-hook-error', hook); }
    };
  }
  function actor(kind, address) {
    if (address.isNull()) return null;
    const key = kind + ':' + address.toString();
    if (!actors.has(key)) {
      if (actors.size >= LIMIT.actors) throw new Error('actor-limit');
      actors.set(key, kind + (++nextActor));
    }
    return actors.get(key);
  }
  function signedArg(value) {
    // NativePointer formats all 64 bits as unsigned hex. Frida's int64(string)
    // saturates that positive magnitude instead of interpreting two's complement.
    // Keep conversion in UInt64 operations; JS Number would lose timestamp bits.
    const bits = uint64(value.toString());
    return bits.compare(uint64('0x7fffffffffffffff')) > 0
      ? '-' + uint64(0).sub(bits).toString() : bits.toString();
  }
  function snapshot(address, countRegions) {
    if (address.isNull()) return null;
    // Fixed-source header layout, cross-compiled for x64 and matched to ELF
    // accesses: sizeof(subpicture_t) = 112; sizeof(subpicture_region_t) = 240.
    const result = { channel: address.readS32(),
      order: address.add(8).readS64().toString(),
      start_us: address.add(32).readS64().toString(),
      stop_us: address.add(40).readS64().toString(),
      is_subtitle: address.add(50).readU8() !== 0,
      system_dates_valid: address.add(104).readU8() !== 0,
      stop_known: address.add(105).readU8() !== 0 };
    if (countRegions) {
      let region = address.add(24).readPointer(), count = 0;
      const seen = new Set();
      while (!region.isNull()) {
        const key = region.toString();
        if (seen.has(key)) throw new Error('region-cycle');
        seen.add(key);
        if (++count > LIMIT.regions) throw new Error('region-limit');
        // Only follows links; never reads region text, bitmap or picture bytes.
        region = region.add(224).readPointer();
      }
      result.region_count = count;
    }
    return result;
  }
  function track(address, decoder, threadId) {
    if (address.isNull()) return;
    const key = address.toString();
    if (subpictures.has(key)) throw new Error('live-subpicture-address-reuse');
    if (subpictures.size >= LIMIT.subpictures) throw new Error('subpicture-limit');
    const item = { id: 'sub' + (++nextSubpicture), address: ptr(key),
      decoder, isAss: false, queued: false };
    subpictures.set(key, item);
    lastByThread.set(threadId, key);
  }
  function sampled(key, state) {
    const now = Date.now(), previous = sampleState.get(key);
    if (previous && previous.state === state && now - previous.at < LIMIT.sampleMs)
      return false;
    sampleState.set(key, { state, at: now });
    return true;
  }
  function hook(module, exports, name, callbacks) {
    const address = exports.get(name);
    if (address === undefined) { emit('missing-hook', { hook: name }); return false; }
    if (!address.equals(module.base.add(OFFSETS[name]))) {
      emit('export-offset-mismatch', { hook: name }); return false;
    }
    const wrapped = {};
    for (const [phase, callback] of Object.entries(callbacks))
      wrapped[phase] = guarded(name + ':' + phase, callback);
    listeners.push(Interceptor.attach(address, wrapped));
    emit('hook-attached', { hook: name });
    return true;
  }
  function install(module) {
    if (installed || stopped || module.name !== 'libvlc.so') return;
    installed = true;
    try {
      // ELF64, little endian, ET_DYN, EM_X86_64. Reject ABI mismatches before
      // interpreting the pinned GNU note or any subtitle structure.
      if (module.base.readU32() !== 0x464c457f ||
          module.base.add(4).readU8() !== 2 || module.base.add(5).readU8() !== 1 ||
          module.base.add(16).readU16() !== 3 || module.base.add(18).readU16() !== 62) {
        fail('unsupported-elf-abi'); return;
      }
      const note = module.base.add(0x2d0);
      if (note.readU32() !== 4 || note.add(4).readU32() !== 20 ||
          note.add(8).readU32() !== 3 || note.add(12).readU32() !== 0x00554e47) {
        fail('unsupported-build-id-note'); return;
      }
      const bytes = new Uint8Array(note.add(16).readByteArray(20));
      const buildId = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
      if (buildId !== BUILD_ID) { fail('unsupported-build-id'); return; }
      emit('build-accepted', { build_id: buildId, architecture: Process.arch,
        pointer_size: Process.pointerSize });
      // Frida 17.24.2's findExportByName lazily obtains a dlopen handle on
      // Android. That reenters the loader when called from onAdded and can
      // abort bionic before ELF Load has completed. Enumerating this non-linker
      // module uses Gum's in-memory ELF parser, without taking a module handle.
      const exports = new Map();
      try {
        for (const entry of module.enumerateExports()) {
          if (entry.type === 'function' && Object.prototype.hasOwnProperty.call(OFFSETS, entry.name))
            exports.set(entry.name, entry.address);
        }
      } catch (_) { fail('export-enumeration-error'); return; }
      const required = (name, callbacks) => {
        if (!hook(module, exports, name, callbacks)) throw new Error('required-hook-missing');
      };
      required('decoder_NewSubpicture', {
        onEnter(args) { this.decoder = actor('decoder', args[0]); },
        onLeave(retval) { track(retval, this.decoder, this.threadId); },
      });
      required('input_DecoderFlush', {
        onEnter(args) {
          if (firstCueAt) emit('decoder-flush', { decoder: actor('decoder', args[0]) });
        },
      });
      required('ass_process_chunk', {
        onEnter(args) {
          if (!firstCueAt) {
            firstCueAt = Date.now();
            if (waitTimer !== null) clearTimeout(waitTimer);
            traceTimer = setTimeout(() => stop('trace-window-elapsed'), LIMIT.traceMs);
            emit('cue-window-started', { trace_ms: LIMIT.traceMs });
          }
          const key = lastByThread.get(this.threadId), item = subpictures.get(key);
          if (!item || item.isAss) { fail('ass-cue-subpicture-correlation-missing'); return; }
          item.isAss = true;
          emit('ass-cue', { track: actor('track', args[0]), decoder: item.decoder,
            subpicture: item.id, pts_ms: signedArg(args[3]), duration_ms: signedArg(args[4]),
            subpicture_before_clock: snapshot(item.address, false) });
        },
      });
      required('vout_PutSubpicture', {
        onEnter(args) {
          const item = subpictures.get(args[1].toString());
          if (!item || !item.isAss) return;
          item.queued = true;
          emit('vout-put', { vout: actor('vout', args[0]), subpicture: item.id,
            decoder: item.decoder, subpicture_after_clock: snapshot(args[1], false) });
        },
      });
      required('spu_PutSubpicture', {
        onEnter(args) {
          const item = subpictures.get(args[1].toString());
          if (!item || !item.isAss) return;
          emit('spu-put', { spu: actor('spu', args[0]), subpicture: item.id,
            decoder: item.decoder, subpicture_state: snapshot(args[1], false) });
        },
      });
      required('subpicture_Delete', {
        onEnter(args) {
          const key = args[0].toString(), item = subpictures.get(key);
          if (!item) return;
          if (item.isAss) emit('ass-subpicture-delete', { subpicture: item.id,
            decoder: item.decoder, reached_vout_put: item.queued,
            final_state: snapshot(args[0], false) });
          subpictures.delete(key);
          for (const [thread, last] of lastByThread)
            if (last === key) lastByThread.delete(thread);
        },
      });
      required('spu_ClearChannel', {
        onEnter(args) {
          if (firstCueAt) emit('spu-clear-channel', { spu: actor('spu', args[0]),
            channel: args[1].toInt32() });
        },
      });
      required('ass_render_frame', {
        onEnter(args) {
          if (!firstCueAt) return;
          this.renderer = actor('renderer', args[0]);
          this.track = actor('track', args[1]);
          this.renderTime = signedArg(args[2]);
          this.changed = ptr(args[3].toString());
        },
        onLeave(retval) {
          if (this.renderer === undefined) return;
          const hasImages = !retval.isNull();
          const changed = this.changed.isNull() ? null : this.changed.readS32();
          if (sampled('ass:' + this.renderer, String(hasImages) + ':' + changed))
            emit('ass-render', { renderer: this.renderer, track: this.track,
              render_time_ms: this.renderTime, has_images: hasImages, changed });
        },
      });
      required('spu_Render', {
        onEnter(args) {
          if (!firstCueAt) return;
          this.spu = actor('spu', args[0]);
          this.subtitleDate = signedArg(args[4]); this.osdDate = signedArg(args[5]);
        },
        onLeave(retval) {
          if (this.spu === undefined) return;
          // The return object is alive here. No pointer survives the callback.
          const output = snapshot(retval, true);
          // Timestamps vary each frame; sample by content identity/region count.
          const signature = output === null ? 'null' :
            output.channel + ':' + output.order + ':' + output.region_count;
          if (sampled('spu:' + this.spu, signature))
            emit('spu-render', { spu: this.spu, subtitle_date_us: this.subtitleDate,
              osd_date_us: this.osdDate, output });
        },
      });
      emit('hooks-ready', { hooks: Object.keys(OFFSETS), limits: LIMIT,
        private_hooks: false, data_mutation: false, pre_ready_calls_covered: false,
        installation: 'deferred-elf-export-enumeration',
        warning: 'instrumented-run-is-not-a-performance-measurement' });
    } catch (_) { fail('install-or-abi-error'); }
  }

  function scheduleInstall(module) {
    if (module.name !== 'libvlc.so' || installed || stopped || pendingInstall !== null) return;
    const base = ptr(module.base.toString()), size = module.size;
    emit('module-observed', { pre_ready_calls_covered: false });
    // This callback returns to the native loader without resolving or binding.
    // setImmediate executes on Frida's JS thread, rather than the loading thread.
    pendingInstall = setImmediate(() => {
      pendingInstall = null;
      if (stopped) return;
      try {
        const current = Process.findModuleByAddress(base);
        if (current === null || current.name !== 'libvlc.so' ||
            !current.base.equals(base) || current.size !== size) {
          fail('module-identity-changed-before-install'); return;
        }
        install(current); // Rechecks the exact build ID before reading exports.
      } catch (_) { fail('deferred-install-error'); }
    });
  }

  raw('started', { frida_version: Frida.version, architecture: Process.arch,
    pointer_size: Process.pointerSize });
  if (Process.arch !== 'x64' || Process.pointerSize !== 8) {
    fail('unsupported-architecture'); return;
  }
  if (Frida.version.split('.')[0] !== '17') { fail('unsupported-frida-major'); return; }
  waitTimer = setTimeout(() => stop('first-cue-timeout'), LIMIT.waitForCueMs);
  observer = Process.attachModuleObserver({ onAdded: scheduleInstall,
    onRemoved(module) { if (module.name === 'libvlc.so') stop('module-unloaded'); } });
  if (stopped && observer !== null) observer.detach();
  // Explicit termination is optional. It never invokes a VLC playback API.
  rpc.exports = { stop() { stop('host-request'); return { stopped: true }; } };
})();
'''.lstrip("\n")


class DiagnosticFailure(Exception):
    """A fixed metadata error code; never contains native messages or paths."""


def bounded_seconds(value):
    seconds = int(value)
    if not 1 <= seconds <= 900:
        raise argparse.ArgumentTypeError("duration must be within 1..900 seconds")
    return seconds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", default=os.environ.get("ANDROID_SERIAL", "emulator-5554"))
    parser.add_argument("--output", type=Path, required=True, help="Metadata JSONL output")
    parser.add_argument("--summary", type=Path, required=True, help="Diagnostic status JSON")
    parser.add_argument("--app-wait-seconds", type=bounded_seconds, default=600)
    parser.add_argument("--session-seconds", type=bounded_seconds, default=870)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.:-]+", args.serial):
        parser.error("invalid Android serial")
    if args.output.resolve() == args.summary.resolve():
        parser.error("output and summary must be different files")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.summary.parent.mkdir(parents=True, exist_ok=True)
    lock = threading.RLock()
    done = threading.Event()
    requested_stop = threading.Event()
    active_call = None
    session = script = None
    closing = False
    session_detached = False
    hook_ready_deadline = None
    state = {"diagnostic_status": "starting", "performance_measurement": False,
             "business_assertions": False, "package": PACKAGE,
             "agent_sha256": AGENT_SHA256, "hooks_ready": False,
             "pre_ready_calls_covered": False, "module_observed": False,
             "hooks_ready_guest_utc_ms": None, "session_detach_reason": None,
             "cue_window_started": False, "agent_stopped": None,
             "error_codes": [], "records": 0, "attached_pid": None}
    stream = args.output.open("w", encoding="utf-8")

    def record(event, metadata=None, guest_utc_ms=None):
        with lock:
            if stream.closed:
                return
            # Agent has its own 8000-record cap; this also bounds transport errors.
            if state["records"] >= 8020:
                if "host-record-limit" not in state["error_codes"]:
                    state["error_codes"].append("host-record-limit")
                done.set()
                return
            state["records"] += 1
            stream.write(json.dumps({"source": "frida-agent" if event == "agent" else "runner",
                                     "event": event, "host_utc_ms": time.time_ns() // 1_000_000,
                                     "guest_utc_ms": guest_utc_ms,
                                     "metadata": metadata or {}}, separators=(",", ":")) + "\n")
            stream.flush()

    def failure(code):
        with lock:
            if code not in state["error_codes"]:
                state["error_codes"].append(code)
                record("diagnostic-error", {"code": code})
        done.set()

    def adb(*arguments, allow_absent=False):
        try:
            result = subprocess.run(["adb", "-s", args.serial, *arguments],
                                    capture_output=True, text=True, timeout=5, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise DiagnosticFailure("adb-" + type(error).__name__) from None
        if result.returncode != 0 and not (allow_absent and result.returncode == 1
                                          and not result.stdout.strip() and not result.stderr.strip()):
            raise DiagnosticFailure("adb-command-failed")
        return result.stdout.strip()

    def frida_call(operation, callback, seconds=15):
        nonlocal active_call
        cancellable = frida.Cancellable()
        active_call = cancellable
        timer = threading.Timer(seconds, cancellable.cancel)
        timer.daemon = True
        timer.start()
        try:
            with cancellable:
                return callback()
        except Exception as error:
            # Exception class and fixed operation are sufficient; no stack/path dump.
            raise DiagnosticFailure(operation + "-" + type(error).__name__) from None
        finally:
            timer.cancel()
            active_call = None

    def on_signal(_signum, _frame):
        requested_stop.set()
        if active_call is not None:
            active_call.cancel()

    def on_message(message, data):
        nonlocal hook_ready_deadline
        if data is not None:
            failure("unexpected-binary-payload")
            return
        if message.get("type") != "send":
            # Never persist Frida exception stacks/native addresses.
            failure("frida-script-error")
            return
        payload = message.get("payload")
        if not isinstance(payload, dict) or payload.get("probe") != "libvlc-spu-public-v1":
            failure("unexpected-agent-payload")
            return
        try:
            if len(json.dumps(payload)) > 16384:
                failure("agent-payload-size-limit")
                return
        except (TypeError, ValueError):
            failure("invalid-agent-json")
            return
        with lock:
            record("agent", payload, payload.get("device_utc_ms"))
            event = payload.get("event")
            if event == "module-observed":
                state["module_observed"] = True
                hook_ready_deadline = time.monotonic() + 30
            elif event == "hooks-ready":
                state["hooks_ready"] = True
                state["hooks_ready_guest_utc_ms"] = payload.get("device_utc_ms")
                hook_ready_deadline = None
            elif event == "cue-window-started":
                state["cue_window_started"] = True
            elif event in ("probe-error", "missing-hook", "export-offset-mismatch"):
                failure("agent-" + event)
            elif event == "stopped":
                state["agent_stopped"] = payload
                if payload.get("reason") not in ("trace-window-elapsed", "host-request"):
                    failure("agent-stop-" + str(payload.get("reason", "unknown")))
                done.set()

    def on_detached(reason, _crash=None):
        nonlocal session_detached
        session_detached = True
        safe_reason = reason if reason in ("application-requested", "process-replaced",
                                          "process-terminated", "connection-terminated", "device-lost") else "unknown"
        state["session_detach_reason"] = safe_reason
        record("session-detached", {"reason": safe_reason})
        if not closing and state["agent_stopped"] is None:
            failure("unexpected-session-detach")

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)
    started = time.monotonic()
    try:
        record("started", {"instrumented_run_is_not_a_performance_measurement": True})
        if hashlib.sha256(AGENT_SOURCE.encode()).hexdigest() != AGENT_SHA256:
            raise DiagnosticFailure("embedded-agent-hash-mismatch")
        try:
            import frida
        except ImportError:
            raise DiagnosticFailure("frida-client-missing") from None
        if frida.__version__ != FRIDA_VERSION:
            raise DiagnosticFailure("frida-client-version-mismatch")
        record("client-ready", {"version": frida.__version__})
        guest_seconds = adb("shell", "date", "+%s")
        if not guest_seconds.isdigit():
            raise DiagnosticFailure("guest-clock-unavailable")
        record("guest-clock-anchor", {"precision_ms": 1000}, int(guest_seconds) * 1000)
        manager = frida.get_device_manager()
        remote = frida_call("remote-connect", lambda: manager.add_remote_device(ENDPOINT))
        # This reads system metadata, never enumerates processes/applications.
        parameters = frida_call("server-handshake", remote.query_system_parameters)
        if parameters.get("arch") != "x64":
            raise DiagnosticFailure("server-architecture-mismatch")
        record("server-ready", {"architecture": "x64"})
        state["diagnostic_status"] = "waiting-app"
        deadline = time.monotonic() + args.app_wait_seconds
        pid = None
        while time.monotonic() < deadline and not requested_stop.is_set():
            text = adb("shell", "pidof", "-s", PACKAGE, allow_absent=True)
            if text:
                if not text.isdigit() or int(text) <= 0:
                    raise DiagnosticFailure("unexpected-app-pid-output")
                pid = int(text)
                break
            requested_stop.wait(0.2)
        if pid is None:
            raise DiagnosticFailure("stopped-before-app" if requested_stop.is_set() else "app-start-timeout")
        session = frida_call("attach", lambda: remote.attach(pid))
        state["attached_pid"] = pid
        session.on("detached", on_detached)
        record("attached", {"pid": pid})
        script = frida_call("create-script", lambda: session.create_script(
            AGENT_SOURCE, name="privi-libvlc-spu-metadata", runtime="qjs"))
        script.on("message", on_message)
        frida_call("load-script", script.load)
        state["diagnostic_status"] = "observing"
        deadline = time.monotonic() + args.session_seconds
        while not done.wait(0.2):
            if requested_stop.is_set():
                record("host-stop-requested")
                break
            if hook_ready_deadline is not None and time.monotonic() >= hook_ready_deadline:
                raise DiagnosticFailure("hook-installation-deadline")
            if time.monotonic() >= deadline:
                raise DiagnosticFailure("session-deadline")
    except DiagnosticFailure as error:
        failure(str(error))
    except Exception as error:
        failure("runner-" + type(error).__name__)
    finally:
        # All teardown operations have their own cancellable deadline. The shell
        # additionally bounds the entire process and preserves the drive status.
        closing = True
        if script is not None and not session_detached:
            if state["agent_stopped"] is None:
                try:
                    frida_call("stop-script", lambda: script.exports_sync.stop(), seconds=3)
                except DiagnosticFailure as error:
                    failure(str(error))
            try:
                frida_call("unload-script", script.unload, seconds=3)
            except DiagnosticFailure as error:
                failure(str(error))
        if session is not None and not session_detached:
            try:
                frida_call("detach", session.detach, seconds=3)
            except DiagnosticFailure as error:
                failure(str(error))
        if not state["hooks_ready"]:
            failure("hooks-never-ready")
        if not state["cue_window_started"]:
            failure("no-ass-cue-observed")
        if state["agent_stopped"] is None:
            failure("agent-stop-not-confirmed")
        state["diagnostic_status"] = "failed" if state["error_codes"] else "captured"
        state["coverage_status"] = ("not-started" if not state["hooks_ready"] else
                                    "partial" if state["error_codes"] else "captured")
        state["elapsed_seconds"] = round(time.monotonic() - started, 3)
        record("finished", {"diagnostic_status": state["diagnostic_status"],
                            "error_codes": state["error_codes"]})
        with lock:
            args.summary.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
            stream.close()
        print(json.dumps({"diagnostic_status": state["diagnostic_status"],
                          "hooks_ready": state["hooks_ready"], "error_codes": state["error_codes"],
                          "performance_measurement": False}), flush=True)
    return 1 if state["error_codes"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
