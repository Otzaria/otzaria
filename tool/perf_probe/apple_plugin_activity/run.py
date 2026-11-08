#!/usr/bin/env python3
"""Boundary-only coordinator for the actual Otzaria Apple plugin experiment."""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import platform
import re
import select
import signal
import socket
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import uuid
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
NATIVE_PIN = "124bb8e63f345ffd0b0f2ea7190c24b19e69897d"
PHASES = {"visible", "offstage", "minimize", "hide", "neverShownBackground",
          "osBackground", "idleExpiryControl"}
COMMAND_LOG_LIMIT = 64 * 1024


def now_ms():
    return time.time_ns() / 1_000_000


def save(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    temporary.replace(path)


def output(command, timeout=30):
    return subprocess.check_output(command, cwd=REPO, text=True, timeout=timeout,
                                   stderr=subprocess.STDOUT).strip()


def recorded_output(directory, label, command, timeout):
    started = time.monotonic()
    record = {"command": command, "status": "running", "startedAtMs": now_ms(),
              "timeoutSeconds": timeout, "exitCode": None}
    save(directory / f"{label}.json", record)
    process = None
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        try:
            process = subprocess.Popen(command, cwd=REPO, stdout=stdout, stderr=stderr,
                                       start_new_session=True)
            record["ownedProcessGroup"] = process.pid
            record["exitCode"] = process.wait(timeout=timeout)
            if record["exitCode"] != 0:
                raise subprocess.CalledProcessError(record["exitCode"], command)
            record["status"] = "passed"
        except subprocess.TimeoutExpired:
            record["status"] = "timedOut"
            raise
        except (OSError, subprocess.SubprocessError) as error:
            record.update(status="failed", error=str(error))
            raise
        finally:
            stop_owned(process)
            for name, stream in (("stdout", stdout), ("stderr", stderr)):
                size = stream.seek(0, os.SEEK_END)
                stream.seek(0)
                data = stream.read(COMMAND_LOG_LIMIT)
                path = directory / f"{label}.{name}.log"
                path.write_bytes(data)
                record[name] = {"path": path.name, "bytes": size,
                                "truncated": size > len(data)}
            record["elapsedMs"] = (time.monotonic() - started) * 1000
            record["processExitAfterCleanup"] = None if process is None else process.poll()
            save(directory / f"{label}.json", record)
        stdout.seek(0)
        return stdout.read(COMMAND_LOG_LIMIT).decode(errors="replace").strip()


class MacApplicationSession:
    def __init__(self, helper, pid, directory, phase):
        self.pid, self.directory = pid, directory
        self.prefix = f"mac-{phase}-controller"
        self.session_token = None
        self.executable = None
        self.failed = False
        self.record = {"hostPid": pid, "status": "running", "commands": []}
        save(directory / f"{self.prefix}.json", self.record)
        self.stderr = (directory / f"{self.prefix}.stderr.log").open("wb")
        self.process = None
        try:
            self.process = subprocess.Popen([str(helper), str(pid)], cwd=REPO,
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.stderr,
                bufsize=0, start_new_session=True)
            self.record["controllerPid"] = self.process.pid
            save(directory / f"{self.prefix}.json", self.record)
        except OSError as error:
            if self.process is not None:
                stop_owned(self.process)
                self.process.stdin.close()
                self.process.stdout.close()
            self.stderr.close()
            self.record.update(status="failed", error=str(error))
            save(directory / f"{self.prefix}.json", self.record)
            raise

    def request(self, action, timeout=10):
        sequence = len(self.record["commands"]) + 1
        entry = {"sequence": sequence, "action": action, "status": "running", "timeoutSeconds": timeout}
        self.record["commands"].append(entry)
        save(self.directory / f"{self.prefix}.json", self.record)
        started, raw = time.monotonic(), bytearray()
        try:
            self.process.stdin.write((json.dumps({"sequence": sequence, "action": action}) + "\n").encode())
            self.process.stdin.flush()
            while not raw.endswith(b"\n"):
                remaining = timeout - (time.monotonic() - started)
                if remaining <= 0 or not select.select([self.process.stdout], [], [], remaining)[0]:
                    raise TimeoutError(f"macOS {action} reply timed out; see {self.prefix} logs")
                chunk = os.read(self.process.stdout.fileno(), min(4096, COMMAND_LOG_LIMIT + 1 - len(raw)))
                if not chunk:
                    raise ValueError(f"macOS {action} controller closed its output; see {self.prefix}.stderr.log")
                raw.extend(chunk)
                if len(raw) > COMMAND_LOG_LIMIT:
                    raise ValueError("macOS controller reply exceeded the bounded log size")
            result = json.loads(raw)
            if (not isinstance(result, dict) or
                    type(result.get("pid")) is not int or result["pid"] != self.pid or
                    type(result.get("controllerPid")) is not int or result["controllerPid"] != self.process.pid or
                    type(result.get("sequence")) is not int or result["sequence"] != sequence or
                    result.get("action") != action or result.get("sameApplication") is not True or
                    result.get("identityMethod") != "NSRunningApplication.isEqual" or
                    not isinstance(result.get("executable"), str) or not os.path.isabs(result["executable"]) or
                    not isinstance(result.get("sessionToken"), str) or not result["sessionToken"]):
                raise ValueError("Invalid retained macOS application identity or command reply")
            if self.session_token is not None and self.session_token != result["sessionToken"]:
                raise ValueError("The macOS controller session changed across the interval")
            if self.executable is not None and self.executable != result["executable"]:
                raise ValueError("The macOS application executable changed across the interval")
            self.session_token = result["sessionToken"]
            self.executable = result["executable"]
            entry["status"] = "passed"
            return result
        except (OSError, ValueError, TimeoutError) as error:
            self.failed = True
            entry.update(status="failed", error=str(error))
            raise
        finally:
            path = self.directory / f"{self.prefix}-{sequence:02d}.stdout.log"
            path.write_bytes(raw[:COMMAND_LOG_LIMIT])
            entry.update(elapsedMs=(time.monotonic() - started) * 1000, stdout=path.name,
                         bytes=len(raw), truncated=len(raw) > COMMAND_LOG_LIMIT)
            save(self.directory / f"{self.prefix}.json", self.record)

    def close(self):
        try:
            if self.failed:
                stop_owned(self.process)
            self.process.stdin.close()
            code = self.process.wait(timeout=5)
            if code != 0 and not self.failed:
                raise subprocess.CalledProcessError(code, self.process.args)
        finally:
            stop_owned(self.process)
            self.process.stdout.close()
            self.stderr.close()
            path = self.directory / f"{self.prefix}.stderr.log"
            size = path.stat().st_size
            if size > COMMAND_LOG_LIMIT:
                with path.open("r+b") as stream:
                    stream.truncate(COMMAND_LOG_LIMIT)
            self.record.update(status="failed" if self.failed or self.process.returncode else "passed",
                               exitCode=self.process.returncode,
                               stderr={"path": path.name, "bytes": size,
                                       "truncated": size > COMMAND_LOG_LIMIT})
            save(self.directory / f"{self.prefix}.json", self.record)


def cpu_seconds(text):
    """Darwin ps cumulative CPU: [[dd-]hh:]mm:ss[.fraction]."""
    match = re.fullmatch(r"(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+(?:\.\d+)?)", text)
    if not match:
        raise ValueError(f"Unrecognized Darwin ps CPU time: {text!r}")
    days, hours, minutes, seconds = match.groups()
    return int(days or 0) * 86400 + int(hours or 0) * 3600 + int(minutes) * 60 + float(seconds)


def host_sample(pid, expected_executable):
    # Only the PID supplied by this app run. No process-tree search or guessed
    # WebContent PID. Physical iOS processes cannot be queried by the Mac ps.
    try:
        raw = output(["/bin/ps", "-ww", "-p", str(pid), "-o", "pid=,lstart=,time=,rss=,comm="], 5)
        parts = raw.split(None, 8)
        if len(parts) != 9 or int(parts[0]) != pid:
            raise ValueError("Missing or malformed host process row")
        executable = parts[8]
        if not expected_executable or os.path.realpath(executable) != os.path.realpath(expected_executable):
            raise ValueError("The public process path does not match the app's executable")
        return {"status": "collected", "source": "Darwin /bin/ps for the verified app PID",
                "identity": {"pid": pid, "started": " ".join(parts[1:6]), "executable": executable},
                "cpuSeconds": cpu_seconds(parts[6]), "rssBytes": int(parts[7]) * 1024,
                "atMs": now_ms(), "monotonicNs": time.monotonic_ns(),
                "cpuResolutionSeconds": 0.01}
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        return {"status": "unavailable", "reason": str(error), "atMs": now_ms()}


def cpu_envelope(before, after):
    result = {"before": before, "after": after,
              "scope": "Host app only; excludes WebContent/GPU/network services. Boundary envelope includes OS transitions and coordination; not pure quiet CPU."}
    if before["status"] != "collected" or after["status"] != "collected":
        return {**result, "status": "unavailable"}
    if before["identity"] != after["identity"]:
        raise ValueError("Host process identity changed across the interval")
    delta = after["cpuSeconds"] - before["cpuSeconds"]
    elapsed = (after["monotonicNs"] - before["monotonicNs"]) / 1e9
    if delta < 0 or elapsed <= 0:
        raise ValueError("Host CPU counters regressed")
    return {**result, "status": "collected", "cpuSeconds": delta,
            "elapsedSeconds": elapsed, "oneCoreEquivalentPercent": 100 * delta / elapsed}


class Coordinator:
    def __init__(self, directory, run_id, token, target, seconds, physical=False):
        self.directory, self.run_id, self.token = directory, run_id, token
        self.target, self.seconds = target, seconds
        self.physical = physical
        self.identity = None
        self.executable = None
        self.jobs = {}
        self.control_job = None
        self.control_ready = threading.Event()
        self.control_result = threading.Event()
        self.completed = threading.Event()
        self.lock = threading.Lock()
        self.stopping = False
        self.mac_helper = directory / "mac-application"

    def check_identity(self, body):
        identity = (body.get("runId"), body.get("hostPid"), body.get("appBootToken"))
        if identity[0] != self.run_id or type(identity[1]) is not int or identity[1] <= 0 or not identity[2]:
            raise ValueError("Invalid app run/PID/boot identity")
        if self.identity is not None and self.identity != identity:
            raise ValueError("App relaunched or PID/boot changed; cannot report resume")
        self.identity = identity

    def request(self, endpoint, body, received):
        with self.lock:
            if endpoint in {"checkpoint", "complete", "framework-complete"}:
                self.check_identity(body)
                self.executable = body.get("hostExecutable")
                save(self.directory / ("partial-app.json" if endpoint == "checkpoint" else "complete.json"), body)
                if endpoint == ("framework-complete" if self.physical else "complete"):
                    self.completed.set()
                return {}, None
            if endpoint == "arm":
                self.check_identity(body)
                if body.get("platform") != self.target or body.get("phase") not in PHASES:
                    raise ValueError("Unexpected phase/platform")
                seconds = body.get("seconds")
                if type(seconds) is not int or not 6 <= seconds <= 240:
                    raise ValueError("Quiet duration must be an integer in [6, 240]")
                if seconds != (190 if body["phase"] == "idleExpiryControl" else self.seconds):
                    raise ValueError("The app duration differs from the declared run input")
                action = body.get("action")
                if action not in {"quiet", "macAppHide", "iosHome"}:
                    raise ValueError("Unknown action")
                if action == "iosHome" and self.target != "ios" or action == "macAppHide" and self.target != "macos":
                    raise ValueError("OS action/platform mismatch")
                if any(job["status"] == "running" for job in self.jobs.values()):
                    raise ValueError("A previous quiet job is still running")
                job_id = str(uuid.uuid4())
                extra = (90 if action == "iosHome" else 30) if self.target == "ios" else 45 if action == "macAppHide" else 15
                job = {**body, "jobId": job_id, "status": "running", "armReceivedMs": received,
                       "armReplyMs": now_ms(), "waitMs": (seconds + extra) * 1000}
                # A hard external deadline ensures the app's one-shot wait
                # cannot reconnect during iOS quiet, even if Home is delayed.
                job["deadlineMonotonic"] = time.monotonic() + seconds + (60 if action == "iosHome" else 10)
                self.jobs[job_id] = job
                save(self.directory / f"driver-{body['phase']}.json", job)
                return {"jobId": job_id, "waitMs": job["waitMs"]}, lambda: self.run_job(job)
            if endpoint == "result":
                job = self.jobs.get(body.get("jobId"))
                if job is None or job["status"] == "running":
                    raise ValueError("No finished external interval; no polling/retry is allowed")
                return job, None
            if endpoint == "control-ready":
                save(self.directory / "ios-controller-environment.json", body)
                self.control_ready.set()
                return {}, None
            if endpoint == "control":
                if self.stopping or self.completed.is_set():
                    return {"stop": True}, None
                if self.control_job is None:
                    return {}, None
                job = self.control_job
                self.control_job = None
                return {"jobId": job["jobId"], "seconds": job["seconds"], "action": job["action"],
                        "remainingMs": max(0, (job["deadlineMonotonic"] - time.monotonic()) * 1000),
                        "serverReceivedMs": received, "serverReplyMs": now_ms()}, None
            if endpoint == "control-result":
                job = self.jobs.get(body.get("jobId"))
                if job is None or self.target != "ios" or "iosControl" in job:
                    raise ValueError("Unexpected or duplicate iOS controller result")
                job["iosControl"] = body
                self.control_result.set()
                return {}, None
            raise ValueError("Unknown endpoint")

    def run_job(self, job):
        controller, succeeded = None, False
        try:
            # HTTP handler has closed the arm connection. Let the reply settle
            # before the OS action; nothing reaches the WebView in this gap.
            time.sleep(0.3)
            unavailable = {"status": "unavailable", "reason": "A physical iOS host PID is not a Mac process; no remote CPU sampler was attached"}
            executable = self.executable
            if self.target == "macos":
                controller = MacApplicationSession(self.mac_helper, job["hostPid"], self.directory, job["phase"])
                job["applicationIdentityBefore"] = controller.request("info")
                executable = job["applicationIdentityBefore"]["executable"]
                job["cpuExecutableSource"] = "NSRunningApplication.executableURL for the app-reported PID"
            else:
                job["cpuExecutableSource"] = "Platform.resolvedExecutable from this app run"
            before = unavailable if self.physical else host_sample(job["hostPid"], executable)
            if self.target == "ios":
                self.control_result.clear()
                with self.lock:
                    self.control_job = job
                if not self.control_result.wait(job["seconds"] + 85):
                    raise TimeoutError("XCUITest did not return its quiet/OS boundary evidence")
                control = job["iosControl"]
                if control["status"] != "passed":
                    raise ValueError(f"XCUITest failed: {control.get('error')}")
                clock = control["controlClock"]
                offset_min = clock["serverReceivedMs"] - clock["replyMs"]
                offset_max = clock["serverReplyMs"] - clock["requestMs"]
                if offset_min > offset_max:
                    raise ValueError("Invalid XCUITest/driver clock bounds")
                job.update({"quietStartMs": control["deviceQuietStartMs"] + offset_max,
                            "quietEndMs": control["deviceQuietEndMs"] + offset_min,
                            "quietElapsedMs": control["quietElapsedMs"],
                            "controlClockUncertaintyMs": offset_max - offset_min,
                            "boundaryScope": "Conservative host-clock interior of XCUITest quiet/OS boundaries"})
            else:
                if job["action"] == "macAppHide":
                    job["applicationBeforeQuiet"] = controller.request("hide")
                job["quietStartMs"] = now_ms()
                start = time.monotonic_ns()
                # NO app IPC, HTTP, JS, command, native state query, process
                # enumeration or sampler poll in this interval.
                time.sleep(job["seconds"])
                job["quietEndMs"] = now_ms()
                job["quietElapsedMs"] = (time.monotonic_ns() - start) / 1e6
                if job["action"] == "macAppHide":
                    job["applicationAfterQuiet"] = controller.request("activate")
            after = unavailable if self.physical else host_sample(job["hostPid"], executable)
            if self.target == "macos":
                job["applicationIdentityAfter"] = controller.request("info")
            job["hostCpuEnvelope"] = cpu_envelope(before, after)
            job["engineCpu"] = {"status": "unavailable", "reason": "No verified public WKWebView-to-WebContent PID mapping"}
            if job["quietEndMs"] <= job["quietStartMs"] or job["quietElapsedMs"] < job["seconds"] * 1000:
                raise ValueError("Quiet interval is missing or shorter than requested")
            succeeded = True
        except (OSError, ValueError, KeyError, TimeoutError, subprocess.SubprocessError) as error:
            job.update(status="failed", error=str(error))
        finally:
            if controller is not None:
                try:
                    controller.close()
                except (OSError, subprocess.SubprocessError) as error:
                    job.update(status="failed", controllerCleanupError=str(error))
                    job.setdefault("error", f"macOS controller cleanup failed: {error}")
                    succeeded = False
            if succeeded:
                job["status"] = "passed"
            save(self.directory / f"driver-{job['phase']}.json", job)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def do_POST(self):
        coordinator = self.server.coordinator
        received = now_ms()
        after_close = None
        try:
            if not hmac.compare_digest(self.headers.get("X-Apple-Quiet-Token", ""), coordinator.token):
                raise ValueError("Invalid run nonce")
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 64 * 1024 * 1024:
                raise ValueError("Invalid request size")
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict):
                raise ValueError("Expected a JSON object")
            result, after_close = coordinator.request(self.path.lstrip("/"), body, received)
            code = 200
        except (ValueError, KeyError, TypeError) as error:
            code, result = 400, {"error": str(error)}
        encoded = json.dumps(result).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(encoded)
        self.wfile.flush()
        self.close_connection = True
        self.connection.shutdown(socket.SHUT_WR)
        if after_close is not None:
            threading.Thread(target=after_close, daemon=True).start()


def stop_owned(process):
    if process is None or process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=5)


def prepare_control(directory, url, token):
    control = directory / "control"
    recorded_output(directory, "create-control-project",
                    ["ruby", str(HERE / "create_control_project.rb"), str(control), str(HERE)], 120)
    (control / "ControlConfig.swift").write_text(
        "enum ControlConfig {\n" +
        f"static let url = {json.dumps(url)}\nstatic let token = {json.dumps(token)}\n" +
        'static let bundleIdentifier = "com.mendelg.otzaria"\n}\n')
    return control


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["macos", "ios"], required=True)
    parser.add_argument("--device", required=True, help="macos or an already booted iOS Simulator UDID")
    parser.add_argument("--mode", choices=["profile", "debug", "release"], required=True)
    parser.add_argument("--seconds", type=int, default=12)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--serve-only", action="store_true", help="Physical-device lab coordinator; signing/install/launch are separate commands")
    parser.add_argument("--public-url", help="Existing trusted HTTPS lab endpoint forwarding to this loopback coordinator")
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("Runtime collection requires a Mac; contract tests run elsewhere")
    if not 6 <= args.seconds <= 60 or not 0 <= args.port <= 65535:
        parser.error("Use 6..60 seconds and a valid local port")
    if args.serve_only:
        public = urlparse(args.public_url or "")
        if args.platform != "ios" or args.mode not in {"profile", "release"} or public.scheme != "https" or not public.hostname or public.username or public.password or public.path not in {"", "/"} or public.query or public.fragment:
            parser.error("Physical lab mode requires iOS profile/release and an existing trusted HTTPS origin")
    elif (args.platform, args.mode) not in {("macos", "profile"), ("ios", "debug")} or args.public_url:
        parser.error("Use macOS profile or iOS Simulator debug, with 6..60 seconds")
    directory = args.output.absolute()
    for path in [directory, *directory.parents]:
        if path.is_symlink():
            parser.error("Report paths must not pass through symbolic links")
    directory.mkdir(parents=True, exist_ok=True)
    if any(directory.iterdir()):
        parser.error("Use a fresh empty output directory")
    run_id, token = str(uuid.uuid4()), str(uuid.uuid4())
    coordinator = Coordinator(directory, run_id, token, args.platform, args.seconds, physical=args.serve_only)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.coordinator = coordinator
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    # Apple permits unqualified local names by default. Do not change ATS to
    # make a raw IP URL work on iOS 17+/macOS 14+.
    url = args.public_url.rstrip("/") if args.serve_only else f"http://localhost:{server.server_port}"
    environment = {"runId": run_id, "status": "running", "platform": args.platform,
                   "mode": args.mode, "device": args.device, "nativeFork": NATIVE_PIN,
                   "physicalDevice": args.serve_only, "physicalDeviceAcceptance": False, "hostOS": platform.platform(),
                   "startedAtMs": now_ms(),
                   "observerLimit": "Fixture and XCUITest overhead remain. Physical release has no attached driver; automated runs include Flutter driver/VM service. Simulator debug is functional evidence only."}
    app_process = control_process = None
    try:
        environment.update(commit=output(["git", "rev-parse", "HEAD"]),
                           tree=output(["git", "rev-parse", "HEAD^{tree}"]),
                           sourceStatus=output(["git", "status", "--porcelain"]),
                           xcode=output(["xcodebuild", "-version"]),
                           sdk=output(["xcrun", "--sdk", "macosx" if args.platform == "macos" else "iphoneos" if args.serve_only else "iphonesimulator", "--show-sdk-version"]),
                           flutter=json.loads(output(["flutter", "--version", "--machine"])))
        entitlements = REPO / "macos/Runner/DebugProfile.entitlements"
        environment["macProfileEntitlementsSource"] = entitlements.read_text()
        environment["macProfileEntitlementsSha256"] = hashlib.sha256(entitlements.read_bytes()).hexdigest()
        save(directory / "environment.json", environment)
        if args.platform == "macos":
            recorded_output(directory, "compile-mac-controller",
                            ["xcrun", "swiftc", str(HERE / "mac_application.swift"), "-o", str(coordinator.mac_helper)], 120)
        elif not args.serve_only:
            # Verify this is a Simulator. Never silently use a physical device
            # with debug and call that background/profile acceptance.
            devices = json.loads(output(["xcrun", "simctl", "list", "devices", "--json"]))
            chosen = [d for items in devices["devices"].values() for d in items if d["udid"] == args.device and d["state"] == "Booted"]
            if len(chosen) != 1:
                raise ValueError("--device must be an already booted iOS Simulator UDID")
            environment["simulator"] = chosen[0]
            control = prepare_control(directory, url, token)
            with (directory / "xcode-control.log").open("w") as log:
                control_process = subprocess.Popen([
                    "xcodebuild", "test", "-project", str(control / "Control.xcodeproj"),
                    "-scheme", "AppleQuietControl", "-destination", f"platform=iOS Simulator,id={args.device}",
                    "-derivedDataPath", str(directory / "control-build"),
                    "-resultBundlePath", str(directory / "control.xcresult"),
                    "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO"],
                    cwd=REPO, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                if not coordinator.control_ready.wait(180):
                    raise TimeoutError("The independent XCUITest controller did not become ready; see xcode-control.log")
        defines = {
            "APPLE_QUIET_COORDINATOR": url, "APPLE_QUIET_TOKEN": token,
            "APPLE_QUIET_RUN_ID": run_id, "APPLE_QUIET_SECONDS": args.seconds,
            "APPLE_QUIET_COMMIT": environment["commit"],
            "APPLE_QUIET_FLUTTER": environment["flutter"]["frameworkVersion"],
            "APPLE_QUIET_EXTERNAL": args.serve_only,
        }
        save(directory / "defines.json", defines)
        if args.serve_only:
            prepare_control(directory, url, token)
            print(f"Lab inputs ready at {directory}. Run the documented signed XCUITest and physical {args.mode} app commands.", flush=True)
            if not coordinator.completed.wait(3600):
                raise TimeoutError("No final framework report from the physical-device run")
            complete = json.loads((directory / "complete.json").read_text())
            if complete["status"] != "passed" or complete["buildMode"] != args.mode:
                raise RuntimeError("Physical-device report failed or used the wrong build mode")
            environment["status"] = "passed"
            environment["builtEntitlements"] = {"status": "unavailable", "reason": "Capture codesign output from the separately signed physical app as documented"}
            return
        command = ["flutter", "drive", "--no-pub", f"--{args.mode}", "-d", args.device,
                   "--driver=test_driver/apple_plugin_activity.dart",
                   "--target=integration_test/apple_plugin_activity_probe_test.dart",
                   f"--dart-define-from-file={directory / 'defines.json'}"]
        environment["command"] = command
        save(directory / "environment.json", environment)
        with (directory / "flutter-drive.log").open("w") as log:
            app_process = subprocess.Popen(command, cwd=REPO,
                env={**os.environ, "APPLE_QUIET_OUTPUT": str(directory)},
                stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            code = app_process.wait(timeout=2400)
        if code != 0:
            raise RuntimeError(f"flutter drive failed with exit {code}; partial reports are retained")
        if not coordinator.completed.wait(10):
            raise RuntimeError("The app never sent a final completed report")
        complete = json.loads((directory / "complete.json").read_text())
        if complete["status"] != "passed":
            raise RuntimeError("The actual-app report failed")
        if control_process is not None and control_process.wait(timeout=60) != 0:
            raise RuntimeError("XCUITest failed; inspect control.xcresult")
        if coordinator.executable:
            bundle = next((p for p in Path(coordinator.executable).parents if p.suffix == ".app"), None)
            if bundle is not None:
                environment["builtInfoPlistSha256"] = hashlib.sha256((bundle / ("Contents/Info.plist" if args.platform == "macos" else "Info.plist")).read_bytes()).hexdigest()
                signed = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(bundle)],
                                        text=True, capture_output=True, timeout=15)
                environment["builtEntitlements"] = {"exitCode": signed.returncode, "stdout": signed.stdout, "stderr": signed.stderr}
        environment["status"] = "passed"
    except (OSError, ValueError, RuntimeError, TimeoutError, subprocess.SubprocessError) as error:
        environment.update(status="failed", error=str(error))
        raise
    finally:
        coordinator.stopping = True
        save(directory / "environment.json", environment)
        stop_owned(app_process)
        stop_owned(control_process)
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
