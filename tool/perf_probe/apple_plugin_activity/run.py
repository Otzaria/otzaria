#!/usr/bin/env python3
"""Boundary-only coordinator for the actual Otzaria Apple plugin experiment."""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import math
import os
from pathlib import Path
import platform
import plistlib
import queue
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
from urllib.parse import unquote, urljoin, urlparse

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
PHASES = {"visible", "offstage", "minimize", "hide", "neverShownBackground",
          "osBackground", "idleExpiryControl"}
COMMAND_LOG_LIMIT = 64 * 1024
RUN_BUDGET_SECONDS = 65 * 60
NATIVE_PACKAGES = {"flutter_inappwebview", "flutter_inappwebview_android",
                   "flutter_inappwebview_web", "flutter_inappwebview_ios",
                   "flutter_inappwebview_linux", "flutter_inappwebview_macos",
                   "flutter_inappwebview_platform_interface", "flutter_inappwebview_windows"}


def now_ms():
    return time.time_ns() / 1_000_000


def clock_anchor():
    return {"wallMs": now_ms(), "monotonicMs": time.monotonic_ns() / 1_000_000}


def remaining_timeout(deadline, maximum):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError("The external boundary deadline expired")
    return min(remaining, maximum)


def run_deadline(started):
    supplied = os.environ.get("APPLE_PROBE_DEADLINE_MONOTONIC")
    deadline = started + RUN_BUDGET_SECONDS if supplied is None else float(supplied)
    if not math.isfinite(deadline):
        raise ValueError("APPLE_PROBE_DEADLINE_MONOTONIC must be finite")
    return deadline


def native_source_provenance(repository=REPO, *, deadline=None):
    repository = repository.resolve()
    lock = (repository / "pubspec.lock").read_text()
    manifest = (repository / "pubspec.yaml").read_text()
    config_path = repository / ".dart_tool/package_config.json"
    packages = {entry["name"]: entry for entry in json.loads(config_path.read_text())["packages"]}
    revisions, roots, evidence = set(), {}, {}
    for name in sorted(NATIVE_PACKAGES):
        sections = []
        for index, source in enumerate([lock, manifest]):
            match = re.search(r"^  " + re.escape(name) + r":\n(.*?)(?=^  \w+:|^\S|\Z)", source, re.M | re.S)
            if index == 1 and name == "flutter_inappwebview_web" and match is None:
                continue
            if match is None or "https://github.com/Otzaria/flutter_inappwebview" not in match[1]:
                raise ValueError(f"Missing native fork declaration: {name}")
            sections.append(match[1])
        refs = [re.search(r'^\s+' + key + r':\s*"?([a-f0-9]{40})"?\s*$', source, re.M)
                for key, source in [("resolved-ref", sections[0]), *[("ref", section) for section in sections]]]
        if any(ref is None for ref in refs) or len({ref[1] for ref in refs}) != 1:
            raise ValueError(f"Unpinned or inconsistent native fork revision: {name}")
        revision = refs[0][1]
        revisions.add(revision)
        package = packages.get(name)
        if package is None or not isinstance(package.get("rootUri"), str):
            raise ValueError(f"Missing resolved native package: {name}")
        uri = urlparse(urljoin(config_path.as_uri(), package["rootUri"]))
        if uri.scheme != "file" or uri.netloc:
            raise ValueError(f"Native package source must be a local resolved checkout: {name}")
        package_root = Path(unquote(uri.path)).resolve()
        root = Path(output(["git", "-C", str(package_root), "rev-parse", "--show-toplevel"], deadline=deadline))
        relative = re.search(r'^\s+path:\s*"?([^"\n]+)"?\s*$', sections[0], re.M)
        if relative is None or (root / relative[1]).resolve() != package_root:
            raise ValueError(f"Unexpected resolved native package path: {name}")
        if root not in roots:
            roots[root] = output(["git", "-C", str(root), "rev-parse", "HEAD"], deadline=deadline)
            if output(["git", "-C", str(root), "status", "--porcelain"], deadline=deadline):
                raise ValueError("The resolved native fork source is dirty")
        if roots[root] != revision:
            raise ValueError(f"Resolved native source differs from the lockfile: {name}")
        evidence[name] = {"revision": revision, "packageRoot": str(package_root)}
    if len(revisions) != 1:
        raise ValueError("The eight native packages do not share one revision")
    return {"revision": revisions.pop(), "packages": evidence}


def save(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    temporary.replace(path)


def warn_cleanup(message):
    try:
        print(message, file=sys.stderr)
    except Exception:
        # A closed diagnostic stream must not replace the original failure.
        pass


def output(command, timeout=30, *, deadline=None):
    if deadline is not None:
        timeout = remaining_timeout(deadline, timeout)
    return subprocess.check_output(command, cwd=REPO, text=True, timeout=timeout,
                                   stderr=subprocess.STDOUT).strip()


def recorded_output(directory, label, command, timeout):
    started = time.monotonic()
    record = {"command": command, "status": "running", "startedAtMs": now_ms(),
              "timeoutSeconds": timeout, "exitCode": None}
    save(directory / f"{label}.json", record)
    process = None
    failure = cleanup_failure = None
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        try:
            process = subprocess.Popen(command, cwd=REPO, stdout=stdout, stderr=stderr,
                                       start_new_session=True)
            record["ownedProcessGroup"] = process.pid
            record["exitCode"] = process.wait(timeout=timeout)
            if record["exitCode"] != 0:
                raise subprocess.CalledProcessError(record["exitCode"], command)
            record["status"] = "passed"
        except subprocess.TimeoutExpired as error:
            failure = error
            record["status"] = "timedOut"
            raise
        except BaseException as error:
            failure = error
            record.update(status="failed", error=str(error))
            raise
        finally:
            try:
                stop_owned(process, timeout=5, kill_timeout=2)
            except Exception as error:
                cleanup_failure = error
                record["cleanupError"] = str(error)
                if failure is None:
                    record.update(status="failed", error=str(error))
            try:
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
            except Exception as error:
                cleanup_failure = cleanup_failure or error
                warn_cleanup(f"Could not preserve {label} setup evidence: {error}")
            if failure is None and cleanup_failure is not None:
                raise cleanup_failure
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

    def close(self, timeout=5):
        deadline = time.monotonic() + timeout
        try:
            if self.failed:
                stop_owned(self.process, timeout=max(0, deadline - time.monotonic()), kill_timeout=0.5)
            self.process.stdin.close()
            code = self.process.wait(timeout=max(0, deadline - time.monotonic()))
            if code != 0 and not self.failed:
                raise subprocess.CalledProcessError(code, self.process.args)
        finally:
            stop_owned(self.process, timeout=max(0, deadline - time.monotonic()), kill_timeout=0.5)
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


def host_sample(pid, expected_executable, timeout=5):
    # Only the PID supplied by this app run. No process-tree search or guessed
    # WebContent PID. Physical iOS processes cannot be queried by the Mac ps.
    try:
        raw = output(["/bin/ps", "-ww", "-p", str(pid), "-o", "pid=,lstart=,time=,rss=,comm="], timeout)
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
        self.control_prepared = threading.Event()
        self.control_session = None
        self.control_challenge = None
        self.prepared_challenge = None
        self.control_process = None
        self.native_fork = None
        self.control_result = threading.Event()
        self.completed = threading.Event()
        self.terminal = queue.Queue()
        self.native_failure = None
        self.native_failure_signaled = False
        self.lock = threading.Lock()
        self.stopping = False
        self.mac_helper = directory / "mac-application"

    def _record_native_failure(self, phase, error, evidence_error=None):
        # The caller holds self.lock, including the control-result ingress.
        failure = {"phase": phase, "error": str(error)}
        if self.native_failure is None:
            self.native_failure = failure
        elif any(self.native_failure[key] != failure[key] for key in failure):
            self.native_failure.setdefault("secondaryErrors", []).append(failure)
        if evidence_error is not None:
            self.native_failure["evidenceWriteError"] = str(evidence_error)

    def _signal_native_failure(self):
        if self.native_failure is not None and not self.native_failure_signaled:
            self.native_failure_signaled = True
            self.terminal.put(("nativeFailure", self.native_failure))

    def signal_native_failure(self):
        with self.lock:
            self._signal_native_failure()

    def fail_native(self, phase, error, evidence_error=None):
        with self.lock:
            self._record_native_failure(phase, error, evidence_error)
            self._signal_native_failure()

    def check_control_process(self):
        if self.control_process is not None and self.control_process.poll() is not None:
            raise ValueError("The iOS controller exited after readiness; see xcode-control.log")
        if not self.control_ready.is_set() or self.control_session is None:
            raise ValueError("The iOS controller has not identified its live session")

    def prepare_measurement(self, body):
        with self.lock:
            self.check_identity(body)
            if self.target != "ios":
                return {}, None
            self.check_control_process()
            if any(job["status"] == "running" for job in self.jobs.values()):
                raise ValueError("Cannot prepare during a quiet interval")
            if self.control_challenge is not None:
                raise ValueError("An iOS controller preparation is already pending")
            self.control_challenge = str(uuid.uuid4())
            self.control_prepared.clear()
        if not self.control_prepared.wait(30):
            raise TimeoutError("The iOS controller did not acknowledge the measurement preparation")
        with self.lock:
            self.check_control_process()
            return {"controllerSession": self.control_session,
                    "challenge": self.prepared_challenge}, None

    def check_identity(self, body):
        identity = (body.get("runId"), body.get("hostPid"), body.get("appBootToken"))
        if identity[0] != self.run_id or type(identity[1]) is not int or identity[1] <= 0 or not identity[2]:
            raise ValueError("Invalid app run/PID/boot identity")
        if self.identity is not None and self.identity != identity:
            raise ValueError("App relaunched or PID/boot changed; cannot report resume")
        self.identity = identity

    def request(self, endpoint, body, received):
        if endpoint == "prepare":
            return self.prepare_measurement(body)
        with self.lock:
            if endpoint in {"checkpoint", "complete", "framework-complete"}:
                self.check_identity(body)
                if self.native_fork is not None and body.get("nativeFork") != self.native_fork:
                    raise ValueError("The app native fork differs from its verified build input")
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
                if self.target == "ios":
                    self.check_control_process()
                    if (self.prepared_challenge is None or
                            body.get("controllerSession") != self.control_session or
                            body.get("challenge") != self.prepared_challenge):
                        raise ValueError("A fresh iOS controller preparation is required before arm")
                    self.prepared_challenge = None
                job_id = str(uuid.uuid4())
                extra = (90 if action == "iosHome" else 30) if self.target == "ios" else 45 if action == "macAppHide" else 15
                anchor = clock_anchor()
                armed = anchor["monotonicMs"] / 1000
                job = {**body, "jobId": job_id, "status": "running", "armReceivedMs": received,
                       "armReplyMs": anchor["wallMs"], "waitMs": (seconds + extra) * 1000,
                       "driverClockAnchors": {"armReply": anchor}}
                # A hard external deadline ensures the app's one-shot wait
                # cannot reconnect during iOS quiet, even if Home is delayed.
                margin = 60 if action == "iosHome" else 30 if action == "macAppHide" else 10
                job["deadlineMonotonic"] = armed + seconds + margin
                job["resultDeadlineMonotonic"] = armed + seconds + extra - 1
                self.jobs[job_id] = job
                save(self.directory / f"driver-{body['phase']}.json", job)
                return {"jobId": job_id, "waitMs": job["waitMs"]}, lambda: self.run_job(job)
            if endpoint == "result":
                job = self.jobs.get(body.get("jobId"))
                if job is None or job["status"] == "running":
                    raise ValueError("No finished external interval; no polling/retry is allowed")
                return job, None
            if endpoint == "control-ready":
                session = body.get("controllerSession")
                if self.target != "ios" or not isinstance(session, str) or not session or self.control_session is not None:
                    raise ValueError("Invalid or replaced iOS controller session")
                self.control_session = session
                save(self.directory / "ios-controller-environment.json", body)
                self.control_ready.set()
                return {}, None
            if endpoint == "control":
                if body.get("controllerSession") != self.control_session or self.control_session is None:
                    raise ValueError("The iOS controller session changed")
                if self.stopping or self.completed.is_set():
                    return {"stop": True}, None
                if self.control_challenge is not None:
                    return {"prepare": self.control_challenge, "controllerSession": self.control_session}, None
                if self.control_job is None:
                    return {}, None
                job = self.control_job
                self.control_job = None
                anchor = clock_anchor()
                job["driverClockAnchors"]["controlReply"] = anchor
                return {"jobId": job["jobId"], "seconds": job["seconds"], "action": job["action"],
                        "remainingMs": max(0, (job["deadlineMonotonic"] - time.monotonic()) * 1000),
                        "serverReceivedMs": received, "serverReplyMs": anchor["wallMs"]}, None
            if endpoint == "control-prepared":
                if (body.get("controllerSession") != self.control_session or
                        self.control_challenge is None or body.get("challenge") != self.control_challenge):
                    raise ValueError("The iOS controller preparation is stale or belongs to another session")
                self.prepared_challenge = self.control_challenge
                self.control_challenge = None
                self.control_prepared.set()
                return {}, None
            if endpoint == "control-result":
                job = self.jobs.get(body.get("jobId"))
                if (job is None or self.target != "ios" or "iosControl" in job or
                        body.get("controllerSession") != self.control_session):
                    raise ValueError("Unexpected or duplicate iOS controller result")
                job["driverClockAnchors"]["controlResult"] = clock_anchor()
                job["iosControl"] = body
                failed = body.get("status") != "passed"
                if failed:
                    self._record_native_failure(job["phase"], f"XCUITest failed: {body.get('error')}")
                self.control_result.set()
                return {}, self.signal_native_failure if failed else None
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
                preparation_deadline = job["deadlineMonotonic"] - job["seconds"]
                controller = MacApplicationSession(self.mac_helper, job["hostPid"], self.directory, job["phase"])
                job["applicationIdentityBefore"] = controller.request("info", timeout=remaining_timeout(preparation_deadline, 10))
                executable = job["applicationIdentityBefore"]["executable"]
                job["cpuExecutableSource"] = "NSRunningApplication.executableURL for the app-reported PID"
            else:
                preparation_deadline = job["deadlineMonotonic"] - job["seconds"]
                job["cpuExecutableSource"] = "Platform.resolvedExecutable from this app run"
            before = unavailable if self.physical else host_sample(job["hostPid"], executable,
                timeout=remaining_timeout(preparation_deadline, 5))
            if self.target == "ios":
                self.check_control_process()
                self.control_result.clear()
                with self.lock:
                    self.control_job = job
                if not self.control_result.wait(remaining_timeout(job["resultDeadlineMonotonic"], job["seconds"] + 85)):
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
                    job["applicationBeforeQuiet"] = controller.request("hide", timeout=remaining_timeout(preparation_deadline, 10))
                if time.monotonic() + job["seconds"] > job["deadlineMonotonic"]:
                    raise TimeoutError("Insufficient boundary budget before the requested quiet interval")
                start = clock_anchor()
                job["driverClockAnchors"]["quietStart"] = start
                job["quietStartMs"] = start["wallMs"]
                # NO app IPC, HTTP, JS, command, native state query, process
                # enumeration or sampler poll in this interval.
                time.sleep(job["seconds"])
                end = clock_anchor()
                job["driverClockAnchors"]["quietEnd"] = end
                job["quietEndMs"] = end["wallMs"]
                job["quietElapsedMs"] = end["monotonicMs"] - start["monotonicMs"]
                if time.monotonic() > job["deadlineMonotonic"]:
                    raise TimeoutError("The quiet interval exceeded its external deadline")
                if job["action"] == "macAppHide":
                    job["applicationAfterQuiet"] = controller.request("activate", timeout=remaining_timeout(job["resultDeadlineMonotonic"], 10))
            after = unavailable if self.physical else host_sample(job["hostPid"], executable,
                timeout=remaining_timeout(job["resultDeadlineMonotonic"], 5))
            if self.target == "macos":
                job["applicationIdentityAfter"] = controller.request("info", timeout=remaining_timeout(job["resultDeadlineMonotonic"], 10))
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
                    controller.close(timeout=max(0, min(5, job["resultDeadlineMonotonic"] - time.monotonic())))
                except (OSError, subprocess.SubprocessError) as error:
                    job.update(status="failed", controllerCleanupError=str(error))
                    job.setdefault("error", f"macOS controller cleanup failed: {error}")
                    succeeded = False
            if time.monotonic() > job["resultDeadlineMonotonic"]:
                job.setdefault("error", "The external boundary work exceeded the publication deadline")
                job["status"], succeeded = "failed", False
            evidence_error = None
            try:
                save(self.directory / f"driver-{job['phase']}.json",
                     {**job, "status": "passed" if succeeded else "failed"})
            except Exception as error:
                evidence_error = error
                job["status"], succeeded = "failed", False
                job.setdefault("error", f"Native boundary evidence write failed: {error}")
            if succeeded:
                job["status"] = "passed"
            if job["status"] == "failed":
                self.fail_native(job["phase"], job["error"], evidence_error)


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
        except (ValueError, KeyError, TypeError, TimeoutError) as error:
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


def stop_owned(process, timeout=15, kill_timeout=5):
    if process is None or process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=kill_timeout)


def prepare_control(directory, url, token, timeout=120):
    control = directory / "control"
    recorded_output(directory, "create-control-project",
                    ["ruby", str(HERE / "create_control_project.rb"), str(control), str(HERE)], timeout)
    (control / "ControlConfig.swift").write_text(
        "enum ControlConfig {\n" +
        f"static let url = {json.dumps(url)}\nstatic let token = {json.dumps(token)}\n" +
        'static let bundleIdentifier = "com.mendelg.otzaria"\n}\n')
    return control


def build_ios_probe(directory, timeout=2400):
    command = ["flutter", "build", "ios", "--simulator", "--debug", "--no-codesign", "--no-pub",
               "--target=integration_test/apple_plugin_activity_probe_test.dart",
               f"--dart-define-from-file={directory / 'defines.json'}"]
    recorded_output(directory, "build-ios-probe", command, timeout)
    return REPO / "build/ios/iphonesimulator/Runner.app"


def ios_build_provenance(application, *, deadline):
    # flutter drive uninstalls its Simulator package before exiting. Capture
    # the exact --use-application-binary input before any runtime work starts.
    info_plist = application / "Info.plist"
    contents = info_plist.read_bytes()
    metadata = plistlib.loads(contents)
    if metadata.get("CFBundleIdentifier") != "com.mendelg.otzaria":
        raise ValueError("The prebuilt iOS probe has an unexpected application identifier")
    signed = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(application)],
                            text=True, capture_output=True, timeout=remaining_timeout(deadline, 15))
    return {
        "builtApplicationProvenance": {
            "source": "prebuiltApplication", "stage": "beforeRuntime",
            "bundle": str(application), "infoPlist": str(info_plist),
            "bundleIdentifier": metadata["CFBundleIdentifier"],
        },
        "builtInfoPlistSha256": hashlib.sha256(contents).hexdigest(),
        "builtEntitlements": {"exitCode": signed.returncode, "stdout": signed.stdout, "stderr": signed.stderr},
    }


def shutdown_server(server, timeout=5):
    failures = []
    def shutdown():
        try:
            server.shutdown()
        except Exception as error:
            failures.append(error)
    thread = threading.Thread(target=shutdown, daemon=True)
    thread.start()
    thread.join(timeout)
    if thread.is_alive():
        raise TimeoutError("The coordinator server did not stop within its cleanup budget")
    if failures:
        raise failures[0]


def wait_for_drive(process, coordinator, timeout):
    def wait_app():
        try:
            coordinator.terminal.put(("drive", process.wait()))
        except Exception as error:
            coordinator.terminal.put(("waitError", error))

    def wait_controller():
        try:
            code = coordinator.control_process.wait()
            if not coordinator.stopping and (code != 0 or not coordinator.completed.is_set()):
                coordinator.fail_native("controller exit", f"XCUITest exited with {code} before successful completion; inspect control.xcresult")
        except Exception as error:
            if not coordinator.stopping:
                coordinator.fail_native("controller wait", error)

    # Blocking child waits and the coordinator's existing boundary response are
    # the only signals. No process/OS/app polling is added during quiet windows.
    threading.Thread(target=wait_app, daemon=True).start()
    if coordinator.control_process is not None:
        threading.Thread(target=wait_controller, daemon=True).start()
    try:
        kind, result = coordinator.terminal.get(timeout=timeout)
    except queue.Empty:
        raise subprocess.TimeoutExpired(process.args, timeout) from None
    if coordinator.native_failure is not None:
        failure = coordinator.native_failure
        raise RuntimeError(f"Native boundary {failure['phase']} failed: {failure['error']}")
    if kind == "waitError":
        raise result
    return result


def main():
    started = time.monotonic()
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
    try:
        deadline = run_deadline(started)
    except ValueError as error:
        parser.error(str(error))
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
                   "mode": args.mode, "device": args.device,
                   "physicalDevice": args.serve_only, "physicalDeviceAcceptance": False, "hostOS": platform.platform(),
                   "startedAtMs": now_ms(), "deadlineMonotonic": deadline,
                   "remainingBudgetAtStartSeconds": max(0, deadline - time.monotonic()),
                   "observerLimit": "Fixture and XCUITest overhead remain. Physical release has no attached driver; automated runs include Flutter driver/VM service. Simulator debug is functional evidence only."}
    app_process = control_process = None
    failure = None
    try:
        environment.update(commit=output(["git", "rev-parse", "HEAD"], deadline=deadline),
                           tree=output(["git", "rev-parse", "HEAD^{tree}"], deadline=deadline),
                           sourceStatus=output(["git", "status", "--porcelain"], deadline=deadline),
                           xcode=output(["xcodebuild", "-version"], deadline=deadline),
                           sdk=output(["xcrun", "--sdk", "macosx" if args.platform == "macos" else "iphoneos" if args.serve_only else "iphonesimulator", "--show-sdk-version"], deadline=deadline),
                           flutter=json.loads(output(["flutter", "--version", "--machine"], deadline=deadline)))
        provenance = native_source_provenance(deadline=deadline)
        environment["nativeSources"] = provenance["packages"]
        environment["nativeFork"] = coordinator.native_fork = provenance["revision"]
        entitlements = REPO / "macos/Runner/DebugProfile.entitlements"
        environment["macProfileEntitlementsSource"] = entitlements.read_text()
        environment["macProfileEntitlementsSha256"] = hashlib.sha256(entitlements.read_bytes()).hexdigest()
        save(directory / "environment.json", environment)
        if args.platform == "macos":
            recorded_output(directory, "compile-mac-controller",
                            ["xcrun", "swiftc", str(HERE / "mac_application.swift"), "-o", str(coordinator.mac_helper)], remaining_timeout(deadline, 120))
        elif not args.serve_only:
            # Verify this is a Simulator. Never silently use a physical device
            # with debug and call that background/profile acceptance.
            devices = json.loads(output(["xcrun", "simctl", "list", "devices", "--json"], deadline=deadline))
            chosen = [d for items in devices["devices"].values() for d in items if d["udid"] == args.device and d["state"] == "Booted"]
            if len(chosen) != 1:
                raise ValueError("--device must be an already booted iOS Simulator UDID")
            environment["simulator"] = chosen[0]
        defines = {
            "APPLE_QUIET_COORDINATOR": url, "APPLE_QUIET_TOKEN": token,
            "APPLE_QUIET_RUN_ID": run_id, "APPLE_QUIET_SECONDS": args.seconds,
            "APPLE_QUIET_COMMIT": environment["commit"],
            "APPLE_QUIET_FLUTTER": environment["flutter"]["frameworkVersion"],
            "APPLE_QUIET_NATIVE_FORK": provenance["revision"],
            "APPLE_QUIET_EXTERNAL": args.serve_only,
        }
        save(directory / "defines.json", defines)
        if args.serve_only:
            prepare_control(directory, url, token, timeout=remaining_timeout(deadline, 120))
            print(f"Lab inputs ready at {directory}. Run the documented signed XCUITest and physical {args.mode} app commands.", flush=True)
            if not coordinator.completed.wait(remaining_timeout(deadline, 3600)):
                raise TimeoutError("No final framework report from the physical-device run")
            complete = json.loads((directory / "complete.json").read_text())
            if complete["status"] != "passed" or complete["buildMode"] != args.mode:
                raise RuntimeError("Physical-device report failed or used the wrong build mode")
            environment["status"] = "passed"
            environment["builtEntitlements"] = {"status": "unavailable", "reason": "Capture codesign output from the separately signed physical app as documented"}
            return
        application = None
        if args.platform == "ios":
            application = build_ios_probe(directory, timeout=remaining_timeout(deadline, 2400))
            if native_source_provenance(deadline=deadline) != provenance:
                raise ValueError("The resolved native source changed during the app build")
            environment["prebuiltApplication"] = str(application)
            environment.update(ios_build_provenance(application, deadline=deadline))
            save(directory / "environment.json", environment)
            control = prepare_control(directory, url, token, timeout=remaining_timeout(deadline, 120))
            with (directory / "xcode-control.log").open("w") as log:
                remaining_timeout(deadline, 180)
                control_process = subprocess.Popen([
                    "xcodebuild", "test", "-project", str(control / "Control.xcodeproj"),
                    "-scheme", "AppleQuietControl", "-destination", f"platform=iOS Simulator,id={args.device}",
                    "-derivedDataPath", str(directory / "control-build"),
                    "-resultBundlePath", str(directory / "control.xcresult"),
                    "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO"],
                    cwd=REPO, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                coordinator.control_process = control_process
                if not coordinator.control_ready.wait(remaining_timeout(deadline, 180)):
                    raise TimeoutError("The independent XCUITest controller did not become ready; see xcode-control.log")
                coordinator.check_control_process()
        command = ["flutter", "drive", "--no-pub", f"--{args.mode}", "-d", args.device,
                   "--driver=test_driver/apple_plugin_activity.dart",
                   "--target=integration_test/apple_plugin_activity_probe_test.dart",
                   f"--dart-define-from-file={directory / 'defines.json'}"]
        if application is not None:
            command.append(f"--use-application-binary={application}")
        environment["command"] = command
        save(directory / "environment.json", environment)
        with (directory / "flutter-drive.log").open("w") as log:
            remaining_timeout(deadline, 2400)
            app_process = subprocess.Popen(command, cwd=REPO,
                env={**os.environ, "APPLE_QUIET_OUTPUT": str(directory)},
                stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            code = wait_for_drive(app_process, coordinator, timeout=remaining_timeout(deadline, 2400))
        if code != 0:
            raise RuntimeError(f"flutter drive failed with exit {code}; partial reports are retained")
        if not coordinator.completed.wait(remaining_timeout(deadline, 10)):
            raise RuntimeError("The app never sent a final completed report")
        complete = json.loads((directory / "complete.json").read_text())
        if complete["status"] != "passed":
            raise RuntimeError("The actual-app report failed")
        if control_process is not None and control_process.wait(timeout=remaining_timeout(deadline, 60)) != 0:
            raise RuntimeError("XCUITest failed; inspect control.xcresult")
        if args.platform == "macos" and coordinator.executable:
            bundle = next((p for p in Path(coordinator.executable).parents if p.suffix == ".app"), None)
            if bundle is not None:
                environment["builtInfoPlistSha256"] = hashlib.sha256((bundle / "Contents/Info.plist").read_bytes()).hexdigest()
                signed = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(bundle)],
                                        text=True, capture_output=True, timeout=remaining_timeout(deadline, 15))
                environment["builtEntitlements"] = {"exitCode": signed.returncode, "stdout": signed.stdout, "stderr": signed.stderr}
        environment["status"] = "passed"
    except BaseException as error:
        failure = error
        if coordinator.native_failure is not None:
            environment["nativeFailure"] = coordinator.native_failure
        environment.update(status="failed", error=str(error))
        raise
    finally:
        coordinator.stopping = True
        cleanup_failure = None
        for name, action in [
            # Preserve the XCTest result bundle after its reported failure.
            ("controller result", lambda: control_process.wait(timeout=45)
                if coordinator.native_failure is not None and control_process is not None else None),
            ("app", lambda: stop_owned(app_process, timeout=5, kill_timeout=2)),
            ("controller", lambda: stop_owned(control_process, timeout=5, kill_timeout=2)),
            ("server shutdown", lambda: shutdown_server(server)),
            ("server close", server.server_close),
        ]:
            try:
                action()
            except Exception as error:
                cleanup_failure = cleanup_failure or error
                environment.setdefault("cleanupErrors", []).append({"stage": name, "error": str(error)})
                environment["status"] = "failed"
                environment.setdefault("error", str(error))
        try:
            save(directory / "environment.json", environment)
        except Exception as error:
            cleanup_failure = cleanup_failure or error
            warn_cleanup(f"Could not save the final environment report: {error}")
        if failure is None and cleanup_failure is not None:
            raise cleanup_failure


if __name__ == "__main__":
    main()
