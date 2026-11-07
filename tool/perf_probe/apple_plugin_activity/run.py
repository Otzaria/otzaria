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
import plistlib
import re
import select
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import uuid
from urllib.parse import unquote, urlparse

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
NATIVE_PACKAGES = {"flutter_inappwebview", *(
    f"flutter_inappwebview_{name}" for name in
    ("android", "ios", "linux", "macos", "platform_interface", "web", "windows"))}
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


def digest_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(data)
    return digest.hexdigest()


def native_source(repo=REPO):
    """Bind every resolved native package to the committed lock and Git source."""
    def git(path, *args):
        return subprocess.check_output(["git", "-C", str(path), *args], timeout=30)
    lock = git(repo, "show", "HEAD:pubspec.lock")
    pubspec = git(repo, "show", "HEAD:pubspec.yaml")
    if lock != (repo / "pubspec.lock").read_bytes() or pubspec != (repo / "pubspec.yaml").read_bytes():
        raise ValueError("Dependency manifests differ from the committed source")
    sections = dict(re.findall(r"^  ([a-zA-Z0-9_]+):\n(.*?)(?=^  [a-zA-Z0-9_]+:\n|^sdks:|\Z)",
                               lock.decode(), re.M | re.S))
    config = repo / ".dart_tool/package_config.json"
    packages = json.loads(config.read_text())["packages"]
    resolved = {item["name"]: item for item in packages}
    if len(resolved) != len(packages):
        raise ValueError("Duplicate resolved packages")
    result = {"lockSha256": hashlib.sha256(lock).hexdigest(),
              "pubspecSha256": hashlib.sha256(pubspec).hexdigest(), "packages": {}, "roots": {}}
    refs = set()
    for name in sorted(NATIVE_PACKAGES):
        section = sections.get(name, "")
        def field(key):
            values = re.findall(r"^      " + re.escape(key) + r": (.+)$", section, re.M)
            if len(values) != 1:
                raise ValueError(f"Missing or duplicate native lock field: {name}/{key}")
            return values[0].strip('"')
        ref, path = field("resolved-ref"), field("path")
        if (not re.fullmatch(r"[0-9a-f]{40}", ref) or field("ref") != ref or path != name or
                field("url") != "https://github.com/Otzaria/flutter_inappwebview" or
                not re.search(r'^    source: git$', section, re.M)):
            raise ValueError(f"Invalid native pin or source: {name}")
        refs.add(ref)
        uri = urlparse(resolved[name]["rootUri"])
        if uri.scheme not in {"", "file"} or uri.netloc not in {"", "localhost"}:
            raise ValueError(f"Non-local native source: {name}")
        package = (config.parent / unquote(uri.path)).resolve()
        root = Path(git(package, "rev-parse", "--show-toplevel").decode().strip())
        head = git(root, "rev-parse", "HEAD").decode().strip()
        if head != ref or package != root / path:
            raise ValueError(f"Resolved native source does not match committed lock: {name}")
        if str(root) not in result["roots"]:
            if git(root, "status", "--porcelain", "--untracked-files=all").strip():
                raise ValueError(f"Modified native source: {root}")
            files = {}
            for raw in git(root, "ls-tree", "-rz", "HEAD").split(b"\0"):
                if raw:
                    metadata, filename = raw.split(b"\t", 1)
                    mode, kind, blob = metadata.split()
                    if kind != b"blob" or mode not in {b"100644", b"100755", b"120000"}:
                        raise ValueError("Unsupported native source tree entry")
                    file = root / os.fsdecode(filename)
                    data = os.fsencode(os.readlink(file)) if file.is_symlink() else file.read_bytes()
                    actual_blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
                    if actual_blob != blob.decode():
                        raise ValueError(f"Native source bytes differ from the committed tree: {file}")
                    files[os.fsdecode(filename)] = hashlib.sha256(data).hexdigest()
            result["roots"][str(root)] = {"head": head,
                "tree": git(root, "rev-parse", "HEAD^{tree}").decode().strip(),
                "trackedFiles": len(files),
                "trackedSourceSha256": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()}
        result["packages"][name] = {"root": str(root), "packagePath": str(package), "resolvedRef": head}
    if len(refs) != 1:
        raise ValueError("Mixed native Git pins in the committed lock")
    result["nativeFork"] = refs.pop()
    return result


def verify_native_source(expected, repo=REPO):
    observed = native_source(repo)
    if observed != expected:
        raise ValueError("Native source changed after the verified prebuild inputs")
    return observed


def verify_app_source(directory, expected, label):
    observed = {"commit": output(["git", "rev-parse", "HEAD"]),
                "tree": output(["git", "rev-parse", "HEAD^{tree}"]),
                "sourceStatus": output(["git", "status", "--porcelain"])}
    changed = observed["sourceStatus"] or any(observed[key] != expected[key] for key in ("commit", "tree"))
    failures = Failures({"source": observed})
    if changed:
        failures.add("verify app source", ValueError("App source differs from the exact clean prebuild commit"))
    failures.attempt("source status receipt", lambda: save(directory / f"source-{label}.json", observed))
    if changed:
        # Preserve a migration or unexpected edit without replacing its error
        # when an evidence sink also fails.
        failures.attempt("source diff evidence", lambda: recorded_output(
            directory, f"source-{label}-diff", ["git", "diff", "HEAD", "--binary"], 30))
    failures.raise_if_any()
    return observed


def simulator_bundle(bundle, defines_path):
    if not bundle.is_dir() or bundle.is_symlink() or bundle.suffix != ".app":
        raise ValueError("The Simulator prebuild did not produce an app bundle")
    info = plistlib.loads((bundle / "Info.plist").read_bytes())
    if (info.get("CFBundleIdentifier") != "com.mendelg.otzaria" or
            info.get("CFBundleSupportedPlatforms") != ["iPhoneSimulator"] or
            info.get("DTPlatformName") != "iphonesimulator"):
        raise ValueError("The prebuilt bundle is not the exact Otzaria Simulator application")
    files = {str(path.relative_to(bundle)): digest_file(path) for path in sorted(bundle.rglob("*")) if path.is_file()}
    if info.get("CFBundleExecutable") not in files:
        raise ValueError("The Simulator bundle executable is missing")
    return {"path": str(bundle), "bundleIdentifier": info["CFBundleIdentifier"],
            "executableName": info["CFBundleExecutable"],
            "definesSha256": digest_file(defines_path), "files": files,
            "bundleSha256": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()}


def prebuild_simulator(directory, defines_path, source):
    command = ["flutter", "build", "ios", "--simulator", "--debug", "--no-pub", "--no-codesign",
               "--target=integration_test/apple_plugin_activity_probe_test.dart",
               f"--dart-define-from-file={defines_path}"]
    recorded_output(directory, "simulator-prebuild", command, 1800)
    verify_native_source(source)
    return simulator_bundle(REPO / "build/ios/iphonesimulator/Runner.app", defines_path)


class Failures:
    """Keep the original exception while independently attempting owned cleanup."""
    def __init__(self, record):
        self.record, self.first = record, None

    def add(self, stage, error):
        detail = {"stage": stage, "type": type(error).__name__, "error": str(error)}
        nested = getattr(error, "apple_quiet_errors", None)
        if isinstance(nested, dict) and nested is not self.record:
            detail["nestedErrors"] = {key: nested[key] for key in
                                     ("firstError", "secondaryErrors") if key in nested}
        if self.first is None:
            self.first = error
            self.record.update(status="failed", error=str(error), firstError=detail)
        else:
            self.record.setdefault("secondaryErrors", []).append(detail)
        self.record["status"] = "failed"

    def attempt(self, stage, operation):
        try:
            return operation()
        except BaseException as error:
            self.add(stage, error)
            return None

    def raise_if_any(self):
        if self.first is not None:
            self.first.apple_quiet_errors = self.record
            # The file system itself may be the failed evidence sink. Keep a
            # bounded copy on the runner's stderr as well as on the exception.
            try:
                sys.stderr.write(json.dumps({key: self.record[key] for key in
                    ("firstError", "secondaryErrors") if key in self.record})[:COMMAND_LOG_LIMIT] + "\n")
            except BaseException as error:
                # Diagnostics are secondary even for closed streams, encoding
                # errors or serialization failures. Never replace the first error.
                try:
                    self.add("diagnostic stderr", error)
                except BaseException:
                    pass  # Preserve the first error if its diagnostic cannot be recorded.
            raise self.first


def bounded_call(operation, seconds=5):
    result, completed = [], threading.Event()
    def work():
        try:
            result.append((True, operation()))
        except BaseException as error:
            result.append((False, error))
        finally:
            completed.set()
    threading.Thread(target=work, daemon=True).start()
    if not completed.wait(seconds):
        raise TimeoutError(f"Owned cleanup did not complete within {seconds} seconds")
    if not result[0][0]:
        raise result[0][1]
    return result[0][1]


def recorded_output(directory, label, command, timeout):
    started = time.monotonic()
    record = {"command": command, "status": "running", "startedAtMs": now_ms(),
              "timeoutSeconds": timeout, "exitCode": None}
    save(directory / f"{label}.json", record)
    failures = Failures(record)
    process, streams, captured = None, {}, {}
    try:
        streams["stdout"] = tempfile.TemporaryFile()
        streams["stderr"] = tempfile.TemporaryFile()
        process = subprocess.Popen(command, cwd=REPO,
            stdout=streams["stdout"], stderr=streams["stderr"], start_new_session=True)
        record["ownedProcessGroup"] = process.pid
        record["exitCode"] = process.wait(timeout=timeout)
        if record["exitCode"] != 0:
            raise subprocess.CalledProcessError(record["exitCode"], command)
        record["status"] = "passed"
    except BaseException as error:
        failures.add("command", error)
        if isinstance(error, subprocess.TimeoutExpired):
            record["status"] = "timedOut"
    finally:
        failures.attempt("stop command", lambda: stop_owned(process))
        for name, stream in streams.items():
            def capture(name=name, stream=stream):
                size = stream.seek(0, os.SEEK_END)
                stream.seek(0)
                data = stream.read(COMMAND_LOG_LIMIT)
                captured[name] = data
                path = directory / f"{label}.{name}.log"
                record[name] = {"path": path.name, "bytes": size,
                                "truncated": size > len(data)}
                path.write_bytes(data)
            failures.attempt(f"capture {name}", capture)
        # Both closes belong to the same failure accounting as the command.
        # A with-statement teardown after raise_if_any could replace its error.
        for name, stream in streams.items():
            failures.attempt(f"close {name}", stream.close)
        record["elapsedMs"] = (time.monotonic() - started) * 1000
        record["processExitAfterCleanup"] = None if process is None else process.returncode
        if process is not None:
            record["ownedGroupCleanup"] = getattr(process, "apple_quiet_cleanup", None)
        failures.attempt("command receipt", lambda: save(directory / f"{label}.json", record))
    failures.raise_if_any()
    return captured["stdout"].decode(errors="replace").strip()

class MacApplicationSession:
    def __init__(self, helper, pid, directory, phase):
        self.pid, self.directory = pid, directory
        self.prefix = f"mac-{phase}-controller"
        self.session_token = None
        self.executable = None
        self.failed = False
        self.closed = False
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
        except BaseException as error:
            failures = Failures(self.record)
            failures.add("controller startup", error)
            if self.process is not None:
                failures.attempt("stop controller", lambda: stop_owned(self.process))
                failures.attempt("close controller stdin", self.process.stdin.close)
                failures.attempt("close controller stdout", self.process.stdout.close)
            failures.attempt("close controller stderr", self.stderr.close)
            failures.attempt("startup receipt", lambda: save(directory / f"{self.prefix}.json", self.record))
            failures.raise_if_any()

    def request(self, action, timeout=10):
        sequence = len(self.record["commands"]) + 1
        entry = {"sequence": sequence, "action": action, "status": "running", "timeoutSeconds": timeout}
        self.record["commands"].append(entry)
        started, raw = time.monotonic(), bytearray()
        failures = Failures(entry)
        result = None
        try:
            save(self.directory / f"{self.prefix}.json", self.record)
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
            if (result.get("applicationState", {}).get("controllerEventLoopRunning") is not True or
                    action == "hide" and (result.get("returnValue") is not True or result.get("isHidden") is not True) or
                    action == "activate" and (result.get("returnValue") is not True or
                        result.get("isHidden") is not False or result.get("isActive") is not True)):
                raise ValueError("Missing live AppKit event loop or native action acknowledgement")
            if self.session_token is not None and self.session_token != result["sessionToken"]:
                raise ValueError("The macOS controller session changed across the interval")
            if self.executable is not None and self.executable != result["executable"]:
                raise ValueError("The macOS application executable changed across the interval")
            self.session_token = result["sessionToken"]
            self.executable = result["executable"]
            entry["status"] = "passed"
        except BaseException as error:
            failures.add("controller request", error)
        finally:
            path = self.directory / f"{self.prefix}-{sequence:02d}.stdout.log"
            failures.attempt("controller reply evidence", lambda: path.write_bytes(raw[:COMMAND_LOG_LIMIT]))
            entry.update(elapsedMs=(time.monotonic() - started) * 1000, stdout=path.name,
                         bytes=len(raw), truncated=len(raw) > COMMAND_LOG_LIMIT)
            failures.attempt("controller request receipt", lambda: save(self.directory / f"{self.prefix}.json", self.record))
            self.failed = self.failed or failures.first is not None
        failures.raise_if_any()
        return result

    def close(self):
        if self.closed:
            return
        self.closed = True
        failures = Failures(self.record)
        if self.failed:
            failures.attempt("stop failed controller", lambda: stop_owned(self.process))
        failures.attempt("close controller stdin", self.process.stdin.close)
        code = failures.attempt("wait controller", lambda: self.process.wait(timeout=5))
        if code is not None and code != 0 and not self.failed:
            failures.add("controller exit", subprocess.CalledProcessError(code, self.process.args))
        failures.attempt("stop controller", lambda: stop_owned(self.process))
        failures.attempt("close controller stdout", self.process.stdout.close)
        failures.attempt("close controller stderr", self.stderr.close)
        def capture_stderr():
            path = self.directory / f"{self.prefix}.stderr.log"
            size = path.stat().st_size
            if size > COMMAND_LOG_LIMIT:
                with path.open("r+b") as stream:
                    stream.truncate(COMMAND_LOG_LIMIT)
            self.record["stderr"] = {"path": path.name, "bytes": size,
                                     "truncated": size > COMMAND_LOG_LIMIT}
        failures.attempt("controller stderr evidence", capture_stderr)
        self.record.update(status="failed" if self.failed or failures.first or self.process.returncode else "passed",
                           exitCode=self.process.returncode)
        failures.attempt("controller close receipt", lambda: save(self.directory / f"{self.prefix}.json", self.record))
        failures.raise_if_any()


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
        self.control_process = None
        self.control_identity = None
        self.control_session = str(uuid.uuid4())
        self.arm_challenge = None
        self.arm_acknowledged = threading.Event()
        self.native_source = None
        self.expected_binary_sha256 = None
        self.completed = threading.Event()
        self.lock = threading.Lock()
        self.stopping = False
        self.background_failures = []
        self.stop_event = threading.Event()
        self.workers = []
        self.mac_helper = directory / "mac-application"

    def check_identity(self, body):
        identity = (body.get("runId"), body.get("hostPid"), body.get("appBootToken"))
        if identity[0] != self.run_id or type(identity[1]) is not int or identity[1] <= 0 or not identity[2]:
            raise ValueError("Invalid app run/PID/boot identity")
        if self.identity is not None and self.identity != identity:
            raise ValueError("App relaunched or PID/boot changed; cannot report resume")
        self.identity = identity
        if self.native_source is not None:
            for field in ("nativeFork", "lockSha256"):
                if body.get(field) != self.native_source[field]:
                    raise ValueError(f"App {field} does not match verified native source")
        if self.expected_binary_sha256 is not None and "hostExecutable" in body:
            path = Path(body["hostExecutable"])
            if not path.is_absolute() or digest_file(path) != self.expected_binary_sha256:
                raise ValueError("The running Simulator executable differs from the prebuilt app")

    def check_control(self, body):
        identity = (body.get("runId"), body.get("controllerPid"), body.get("controllerBootToken"))
        if (self.control_identity is None or identity != self.control_identity or
                body.get("controlSession") != self.control_session):
            raise ValueError("Stale or foreign iOS controller identity")
        if not self.physical and (self.control_process is None or self.control_process.poll() is not None):
            raise ValueError("The owned XCUITest process is no longer alive")

    def arm(self, body, received):
        with self.lock:
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
            if any(job["status"] in {"arming", "running"} for job in self.jobs.values()):
                raise ValueError("A previous quiet job is still running")
            job_id = str(uuid.uuid4())
            extra = (90 if action == "iosHome" else 30) if self.target == "ios" else 45 if action == "macAppHide" else 15
            job = {**body, "jobId": job_id, "status": "arming", "armReceivedMs": received,
                   "waitMs": (seconds + extra) * 1000}
            if self.target == "ios":
                if not self.control_ready.is_set() or self.control_identity is None:
                    raise ValueError("No identified iOS controller is ready")
                self.check_control(dict(zip(("runId", "controllerPid", "controllerBootToken"), self.control_identity),
                                        controlSession=self.control_session))
                self.arm_acknowledged.clear()
                self.arm_challenge = {"jobId": job_id, "challenge": str(uuid.uuid4()), "delivered": False}
            self.jobs[job_id] = job
        try:
            if self.target == "ios":
                # A new one-shot challenge is acknowledged before arm returns.
                # The old readiness Event cannot authorize a new interval.
                if not self.arm_acknowledged.wait(5):
                    raise TimeoutError("No fresh identified iOS controller at arm")
                with self.lock:
                    self.check_control(job["controlArm"])
                    self.arm_challenge = None
            started = time.monotonic()
            job.update(status="running", armReplyMs=now_ms(),
                       deadlineMonotonic=started + seconds + (60 if action == "iosHome" else 10),
                       completionDeadlineMonotonic=started + seconds + extra - 6)
            save(self.directory / f"driver-{body['phase']}.json", job)
            return {"jobId": job_id, "waitMs": job["waitMs"]}, lambda: self.run_job(job)
        except BaseException as error:
            Failures(job).add("arm", error)
            raise

    def request(self, endpoint, body, received):
        if endpoint == "arm":
            return self.arm(body, received)
        with self.lock:
            if endpoint in {"checkpoint", "complete", "framework-complete"}:
                self.check_identity(body)
                self.executable = body.get("hostExecutable")
                save(self.directory / ("partial-app.json" if endpoint == "checkpoint" else "complete.json"), body)
                if endpoint == ("framework-complete" if self.physical else "complete"):
                    self.completed.set()
                return {}, None
            if endpoint == "result":
                job = self.jobs.get(body.get("jobId"))
                if job is None or job["status"] not in {"passed", "failed"}:
                    raise ValueError("No finished external interval; no polling/retry is allowed")
                return job, None
            if endpoint == "control-ready":
                identity = (body.get("runId"), body.get("controllerPid"), body.get("controllerBootToken"))
                if (self.target != "ios" or self.control_identity is not None or identity[0] != self.run_id or
                        type(identity[1]) is not int or identity[1] <= 0 or
                        not isinstance(identity[2], str) or not identity[2]):
                    raise ValueError("Unexpected iOS controller readiness identity")
                save(self.directory / "ios-controller-environment.json", body)
                self.control_identity = identity
                self.control_ready.set()
                return {"controlSession": self.control_session}, None
            if endpoint == "control":
                self.check_control(body)
                if self.stopping or self.completed.is_set():
                    return {"stop": True}, None
                if self.arm_challenge is not None and not self.arm_challenge["delivered"]:
                    self.arm_challenge["delivered"] = True
                    return {"armChallenge": self.arm_challenge["challenge"], "jobId": self.arm_challenge["jobId"]}, None
                if self.control_job is None:
                    return {}, None
                job = self.control_job
                self.control_job = None
                job["controlDispatched"] = {"receivedAtMs": received, "controllerPid": body["controllerPid"]}
                return {"jobId": job["jobId"], "seconds": job["seconds"], "action": job["action"],
                        "remainingMs": max(0, (job["deadlineMonotonic"] - time.monotonic()) * 1000),
                        "serverReceivedMs": received, "serverReplyMs": now_ms()}, None
            if endpoint == "control-arm":
                self.check_control(body)
                challenge = self.arm_challenge
                if (challenge is None or not challenge["delivered"] or self.arm_acknowledged.is_set() or
                        body.get("challenge") != challenge["challenge"] or body.get("jobId") != challenge["jobId"]):
                    raise ValueError("Stale or duplicate iOS arm acknowledgement")
                self.jobs[challenge["jobId"]]["controlArm"] = {**body, "receivedAtMs": received}
                self.arm_acknowledged.set()
                return {}, None
            if endpoint == "control-result":
                self.check_control(body)
                job = self.jobs.get(body.get("jobId"))
                if (job is None or self.target != "ios" or "iosControl" in job or
                        job["status"] != "running" or "controlDispatched" not in job or
                        time.monotonic() > job["completionDeadlineMonotonic"] or
                        body.get("challenge") != job["controlArm"]["challenge"]):
                    raise ValueError("Unexpected or duplicate iOS controller result")
                job["iosControl"] = body
                self.control_result.set()
                return {}, None
            raise ValueError("Unknown endpoint")

    def run_job(self, job):
        controller = None
        failures = Failures(job)
        try:
            # HTTP handler has closed the arm connection. Let the reply settle
            # before the OS action; nothing reaches the WebView in this gap.
            time.sleep(0.3)
            if self.stop_event.is_set():
                raise RuntimeError("Run stopped before the quiet job")
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
                if self.stop_event.is_set():
                    raise RuntimeError("Run stopped before dispatching the iOS quiet job")
                with self.lock:
                    self.control_job = job
                remaining = max(0, job["completionDeadlineMonotonic"] - time.monotonic())
                if not self.control_result.wait(remaining):
                    raise TimeoutError("XCUITest did not return its quiet/OS boundary evidence")
                if self.stop_event.is_set():
                    raise RuntimeError("Run stopped before the iOS boundary result")
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
                if self.stop_event.wait(job["seconds"]):
                    raise RuntimeError("Run stopped during quiet; the interval is incomplete")
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
        except BaseException as error:
            failures.add("quiet job", error)
        finally:
            if controller is not None:
                failures.attempt("controller cleanup", controller.close)
                if failures.first is not None:
                    job["controllerCleanupError"] = str(failures.first)
            final = {**job, "status": "passed" if failures.first is None else "failed"}
            failures.attempt("quiet job receipt", lambda: save(self.directory / f"driver-{job['phase']}.json", final))
            job["status"] = "passed" if failures.first is None else "failed"
            if failures.first is not None:
                failures.first.apple_quiet_errors = job
                self.background_failures.append(failures.first)

    def start_job(self, operation):
        with self.lock:
            if self.stopping:
                raise RuntimeError("The coordinator is stopping")
            worker = threading.Thread(target=operation, daemon=True)
            self.workers.append(worker)
            worker.start()

    def stop_jobs(self):
        self.stop_event.set()
        self.control_result.set()
        with self.lock:
            workers = list(self.workers)
        failures = Failures({})
        for index, worker in enumerate(workers):
            failures.attempt(f"join quiet worker {index}", lambda: worker.join(timeout=35))
            if worker.is_alive():
                failures.add(f"quiet worker {index}", TimeoutError("Owned quiet worker did not drain after cancellation"))
        failures.raise_if_any()


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
        except (ValueError, KeyError, TypeError, OSError, TimeoutError) as error:
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
            coordinator.start_job(after_close)


def _live_owned_group(pgid, timeout):
    """Cleanup-only group observation; never called inside a quiet interval."""
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return []
    rows = subprocess.check_output(
        ["/bin/ps", "-A", "-o", "pid=", "-o", "pgid=", "-o", "stat="],
        text=True, timeout=timeout)
    live = []
    for row in rows.splitlines():
        fields = row.split()
        if len(fields) != 3:
            raise ValueError("Malformed process-group cleanup observation")
        pid, group = int(fields[0]), int(fields[1])
        # A zombie is already dead and cannot be killed. Only its parent can
        # reap it; it must not turn successful termination into a timeout.
        if group == pgid and fields[2][0] not in {"Z", "X"}:
            live.append(pid)
    return sorted(live)


def stop_owned(process):
    if process is None or getattr(process, "apple_quiet_group_drained", False) is True:
        return
    pgid = process.pid
    if type(pgid) is not int or pgid <= 1 or pgid == os.getpgrp():
        raise ValueError("Cleanup requires an owned separate process group")
    try:
        if os.getpgid(pgid) != pgid:
            raise ValueError("The owned leader no longer belongs to its recorded process group")
    except ProcessLookupError:
        pass  # Its descendants can still hold the original owned group.
    record = {"processGroup": pgid, "status": "running", "groupDrained": False,
              "signals": [], "remainingLivePids": []}
    process.apple_quiet_cleanup = record
    failures = Failures(record)

    def send(sig):
        try:
            os.killpg(pgid, sig)
            record["signals"].append(sig.name)
        except ProcessLookupError:
            pass

    def drain(deadline):
        while True:
            process.poll()  # Reap our direct child; its exit does not drain the group.
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return False
            live = _live_owned_group(pgid, min(1.0, remaining))
            record["remainingLivePids"] = live
            if not live:
                return True
            time.sleep(min(0.05, max(0, deadline - time.monotonic())))

    deadline = time.monotonic() + 15
    failures.attempt("signal owned group TERM", lambda: send(signal.SIGTERM))
    drained = failures.attempt("drain owned group TERM", lambda: drain(deadline))
    if drained is not True:
        deadline = time.monotonic() + 5
        failures.attempt("signal owned group KILL", lambda: send(signal.SIGKILL))
        drained = failures.attempt("drain owned group KILL", lambda: drain(deadline))
    if drained is not True:
        failures.add("owned group deadline", TimeoutError("Owned process group did not drain within its TERM/KILL bounds"))
    failures.attempt("reap owned leader", lambda: process.wait(timeout=max(0, deadline - time.monotonic())))
    record["leaderExitCode"] = process.returncode
    record["groupDrained"] = drained is True and process.returncode is not None
    record["status"] = "passed" if failures.first is None else "failed"
    process.apple_quiet_group_drained = record["groupDrained"]
    failures.raise_if_any()

def prepare_control(directory, url, token, run_id):
    control = directory / "control"
    recorded_output(directory, "create-control-project",
                    ["ruby", str(HERE / "create_control_project.rb"), str(control), str(HERE)], 120)
    (control / "ControlConfig.swift").write_text(
        "enum ControlConfig {\n" +
        f"static let url = {json.dumps(url)}\nstatic let token = {json.dumps(token)}\n" +
        f"static let runId = {json.dumps(run_id)}\n" +
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
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    # Apple permits unqualified local names by default. Do not change ATS to
    # make a raw IP URL work on iOS 17+/macOS 14+.
    url = args.public_url.rstrip("/") if args.serve_only else f"http://localhost:{server.server_port}"
    environment = {"runId": run_id, "status": "running", "platform": args.platform,
                   "mode": args.mode, "device": args.device,
                   "physicalDevice": args.serve_only, "physicalDeviceAcceptance": False, "hostOS": platform.platform(),
                   "startedAtMs": now_ms(),
                   "observerLimit": "Fixture and XCUITest overhead remain. Physical release has no attached driver; automated runs include Flutter driver/VM service. Simulator debug is functional evidence only."}
    app_process = control_process = None
    app_log = control_log = None
    failures = Failures(environment)
    try:
        environment.update(commit=output(["git", "rev-parse", "HEAD"]),
                           tree=output(["git", "rev-parse", "HEAD^{tree}"]),
                           sourceStatus=output(["git", "status", "--porcelain"]),
                           xcode=output(["xcodebuild", "-version"]),
                           sdk=output(["xcrun", "--sdk", "macosx" if args.platform == "macos" else "iphoneos" if args.serve_only else "iphonesimulator", "--show-sdk-version"]),
                           flutter=json.loads(output(["flutter", "--version", "--machine"])))
        if environment["sourceStatus"]:
            raise ValueError("Runtime acceptance requires the exact clean committed source")
        source = coordinator.native_source = native_source()
        environment.update(nativeFork=source["nativeFork"], nativeSourceBefore=source)
        defines = {
            "APPLE_QUIET_COORDINATOR": url, "APPLE_QUIET_TOKEN": token,
            "APPLE_QUIET_RUN_ID": run_id, "APPLE_QUIET_SECONDS": args.seconds,
            "APPLE_QUIET_COMMIT": environment["commit"],
            "APPLE_QUIET_FLUTTER": environment["flutter"]["frameworkVersion"],
            "APPLE_QUIET_EXTERNAL": args.serve_only,
            "APPLE_QUIET_NATIVE_FORK": source["nativeFork"], "APPLE_QUIET_LOCK_SHA256": source["lockSha256"],
        }
        defines_path = directory / "defines.json"
        save(defines_path, defines)
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
            # The exact run-specific DEBUG app is built before the controller
            # begins its finite test lifetime. Drive consumes this same bundle.
            environment["simulatorPrebuild"] = prebuild_simulator(directory, defines_path, source)
            verify_app_source(directory, environment, "after-prebuild")
            prebuild = environment["simulatorPrebuild"]
            coordinator.expected_binary_sha256 = prebuild["files"][prebuild["executableName"]]
            save(directory / "environment.json", environment)
            control = prepare_control(directory, url, token, run_id)
            control_log = (directory / "xcode-control.log").open("w")
            control_process = subprocess.Popen([
                "xcodebuild", "test", "-project", str(control / "Control.xcodeproj"),
                "-scheme", "AppleQuietControl", "-destination", f"platform=iOS Simulator,id={args.device}",
                "-derivedDataPath", str(directory / "control-build"),
                "-resultBundlePath", str(directory / "control.xcresult"),
                "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO"],
                cwd=REPO, stdout=control_log, stderr=subprocess.STDOUT, start_new_session=True)
            coordinator.control_process = control_process
            if not coordinator.control_ready.wait(180):
                raise TimeoutError("The independent XCUITest controller did not become ready; see xcode-control.log")
            if control_process.poll() is not None:
                raise RuntimeError("The XCUITest process exited after readiness")
        if args.serve_only:
            prepare_control(directory, url, token, run_id)
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
        if args.platform == "ios":
            prebuild = environment["simulatorPrebuild"]
            if simulator_bundle(Path(prebuild["path"]), defines_path) != prebuild:
                raise ValueError("Simulator app or run-specific defines changed after prebuild")
            command.append(f"--use-application-binary={prebuild['path']}")
        environment["command"] = command
        save(directory / "environment.json", environment)
        app_log = (directory / "flutter-drive.log").open("w")
        app_process = subprocess.Popen(command, cwd=REPO,
            env={**os.environ, "APPLE_QUIET_OUTPUT": str(directory)},
            stdout=app_log, stderr=subprocess.STDOUT, start_new_session=True)
        code = app_process.wait(timeout=2400)
        environment["appExitCode"] = code
        if code != 0:
            raise RuntimeError(f"flutter drive failed with exit {code}; partial reports are retained")
        if not coordinator.completed.wait(10):
            raise RuntimeError("The app never sent a final completed report")
        complete = json.loads((directory / "complete.json").read_text())
        if complete["status"] != "passed" or complete["buildMode"] != args.mode:
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
    except BaseException as error:
        failures.add("run", error)
    finally:
        coordinator.stopping = True
        coordinator.stop_event.set()
        coordinator.control_result.set()
        failures.attempt("stop app", lambda: stop_owned(app_process))
        failures.attempt("stop iOS controller", lambda: stop_owned(control_process))
        failures.attempt("drain owned quiet workers", coordinator.stop_jobs)
        for name, stream in (("app log", app_log), ("iOS control log", control_log)):
            if stream is not None:
                failures.attempt(f"close {name}", stream.close)
        failures.attempt("stop coordinator server", lambda: bounded_call(server.shutdown))
        failures.attempt("close coordinator server", lambda: bounded_call(server.server_close))
        failures.attempt("join coordinator server", lambda: bounded_call(server_thread.join))
        for error in coordinator.background_failures:
            if error is not failures.first:
                failures.add("background job", error)
        if coordinator.native_source is not None:
            environment["nativeSourceAfter"] = failures.attempt("verify final native source",
                lambda: verify_native_source(coordinator.native_source))
            environment["appSourceAfter"] = failures.attempt("verify final source",
                lambda: verify_app_source(directory, environment, "after"))
        failures.attempt("environment receipt", lambda: save(directory / "environment.json", environment))
        failures.raise_if_any()


if __name__ == "__main__":
    main()
