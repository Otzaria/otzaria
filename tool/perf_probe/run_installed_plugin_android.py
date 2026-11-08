#!/usr/bin/env python3
"""Run the real installed-plugin scenario with Android Home/resume acknowledgements."""

import argparse
import base64
from contextlib import ExitStack
import datetime as dt
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import selectors
import shutil
import signal
import subprocess
import sys
import time
import urllib.parse
import uuid

if __package__:
    from .prepare_installed_plugin_source import COMMIT as STORE_COMMIT, prepare, write_defines
else:
    from prepare_installed_plugin_source import COMMIT as STORE_COMMIT, prepare, write_defines

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = "org.otzaria.otzaria.installedprobe"
ACTIVITY = "org.otzaria.otzaria.MainActivity"
COMPONENT = f"{PACKAGE}/{ACTIVITY}"
DIRECTORY = "installed-plugin-android"
TARGET = "integration_test/installed_plugin_resource_probe_test.dart"
NATIVE_PIN = "ab6953a7d69016bcfcd6d47c301ded0d2a6d5400"
COMMAND_OUTPUT_LIMIT = 8 * 1024 * 1024
COMPLETION_TIMEOUT = 15
PACKAGES = ["flutter_inappwebview" + suffix for suffix in
            ("", "_android", "_ios", "_linux", "_macos", "_platform_interface", "_web", "_windows")]
REQUIRED_PHASES = {
    "startup", "firstOpen", "visibleIdle", "stateAndScroll", "multipleOpen", "hiddenIdle",
    "memoryPressure", "restore", "protectedControls", "countPolicy", "agePolicy", "storeRestore",
    "backgroundOpen", "backgroundIdle", "backgroundClose", "close", "closedIdle", "osBackground",
}
IDENTITY_KEYS = ("protocol", "campaignId", "runId", "pid", "package")
DOCUMENT_KEYS = ("pluginId", "instanceId", "controllerObjectId", "nativeViewId", "documentToken")
RECORD = re.compile(r"ActivityRecord\{([0-9a-f]+) u([0-9]+) ([\w.$/]+) t([0-9]+)(?: [^}]*)?\}")


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_component(value):
    require(isinstance(value, str) and re.fullmatch(r"[\w.]+/[\w.$]+", value),
            "Invalid activity component")
    package, activity = value.split("/")
    return package + "/" + (package + activity if activity.startswith(".") else activity)


def activity_records(text):
    return [dict(token=m[1], user=int(m[2]), component=normalize_component(m[3]), taskId=int(m[4]))
            for m in RECORD.finditer(text)]


def activity_snapshot(text):
    records = activity_records(text)
    targets = {json.dumps(value, sort_keys=True) for value in records if value["component"] == COMPONENT}
    require(len(targets) == 1, "Missing or ambiguous dedicated probe ActivityRecord")
    resumed = []
    for line in text.splitlines():
        if re.match(r"\s*(?:topResumedActivity|mResumedActivity)\s*[:=]", line):
            resumed.extend(activity_records(line))
    unique = {json.dumps(value, sort_keys=True) for value in resumed}
    require(len(unique) == 1, "Missing or ambiguous native resumed ActivityRecord")
    target, top = json.loads(next(iter(targets))), json.loads(next(iter(unique)))
    require(target["user"] == 0 and top["user"] == 0, "Only the emulator primary user is supported")
    return {"activity": target, "resumedActivity": top}


def process_identity(raw, expected_pid):
    match = re.fullmatch(r"([0-9]+) \(.*\) (.+)", raw.strip())
    require(match is not None and int(match[1]) == expected_pid, "Unexpected /proc stat PID")
    fields = match[2].split()
    require(len(fields) >= 20 and fields[19].isdigit() and int(fields[19]) > 0,
            "Missing /proc stat process start time")
    return {"pid": expected_pid, "startTicks": int(fields[19])}


def require_native_state(observed, original, *, foreground, launcher):
    if observed["process"] != original["process"]:
        raise RuntimeError("Probe process exited or PID was reused")
    if observed["activity"] != original["activity"]:
        raise RuntimeError("Probe activity was replaced or moved to another task")
    expected = observed["activity"] if foreground else None
    top = observed["resumedActivity"]
    require(top == expected if foreground else top["component"] == launcher and top != observed["activity"],
            "Native foreground/background acknowledgement does not match the requested state")


def verify_apk(text):
    package = re.search(r"^package: name='([^']+)'", text, re.M)
    activity = re.search(r"^launchable-activity: name='([^']+)'", text, re.M)
    require(package is not None and package[1] == PACKAGE, "Refusing an APK with a different application ID")
    require(activity is not None and activity[1] == ACTIVITY, "Unexpected APK launcher activity")
    require(re.search(r"^application-debuggable\s*$", text, re.M) is not None,
            "Only a debuggable dedicated probe APK is supported")
    return {"package": package[1], "activity": activity[1], "debuggable": True}


def verify_bootstrap(value, campaign):
    require(isinstance(value, dict) and value.get("protocol") == 1 and value.get("campaignId") == campaign
            and value.get("package") == PACKAGE, "Stale or wrong-package control bootstrap")
    pid = value.get("pid")
    require(type(pid) is int and pid > 0 and re.fullmatch(fr"{pid}-[0-9]+", str(value.get("runId"))),
            "Bootstrap is missing its actual PID/run identity")
    require(type(value.get("port")) is int and 0 < value["port"] < 65536, "Invalid device control port")
    require(re.fullmatch(r"(?:cache|code_cache)/otzaria-installed-probe-[A-Za-z0-9_-]+/output/installed-plugin-report\.json",
                         str(value.get("reportPath"))), "Report path is not a private fresh probe output")
    return value


def verify_document(value):
    require(isinstance(value, dict), "Missing foreground plugin identity")
    for key in DOCUMENT_KEYS:
        require(type(value.get(key)) is int if key == "controllerObjectId"
                else isinstance(value.get(key), str) and bool(value[key]), f"Missing document identity: {key}")
    return value


class Protocol:
    def __init__(self, bootstrap, quiet_ms):
        self.identity = {key: bootstrap[key] for key in IDENTITY_KEYS}
        self.sequence = 0
        self.quiet_ms = quiet_ms
        self.document = None
        self.actions = []

    def accept(self, event):
        require(isinstance(event, dict) and all(event.get(key) == value for key, value in self.identity.items()),
                "Control event has stale campaign, PID, run, or package identity")
        require(event.get("sequence") == self.sequence + 1, "Duplicate or out-of-order control command")
        action = event.get("action")
        # A framework failure may complete early; it must still produce a retained failure report.
        expected = ("home", "quiet", "resume", "complete")[min(self.sequence, 3)]
        require(action == expected or action == "complete", "Unexpected lifecycle command order")
        require("complete" not in self.actions, "Control already completed")
        payload = event.get("payload")
        require(isinstance(payload, dict), "Missing control payload")
        if action in {"home", "quiet", "resume"}:
            document = verify_document(payload.get("identity"))
            if self.document is None:
                self.document = document
            require(document == self.document, "Document or instance changed between lifecycle commands")
        if action == "quiet":
            require(payload.get("name") == "osBackgroundIdle" and type(payload.get("durationMs")) is int
                    and payload["durationMs"] == self.quiet_ms, "Wrong quiet window or duration")
        self.sequence += 1
        self.actions.append(action)
        return action, payload


def verify_report(raw, complete, bootstrap, evidence, commit):
    require(complete.get("reportBytes") == len(raw)
            and complete.get("reportSha256") == hashlib.sha256(raw).hexdigest(), "Final report bytes or digest changed")
    report = json.loads(raw)
    require(complete.get("frameworkPassed") is True and report.get("frameworkPassed") is True,
            "The integration-test framework did not pass")
    for key, value in {"schemaVersion": 1, "status": "passed", "platform": "android", "buildMode": "debug",
                       "pid": bootstrap["pid"], "runId": bootstrap["runId"], "commit": commit,
                       "physicalDeviceAcceptance": False, "policyRestored": True}.items():
        require(report.get(key) == value, f"Unexpected final report field: {key}")
    for key in ("errors", "contractErrors", "testFailures"):
        require(report.get(key) == [], f"Final report contains or omits {key}")
    require(report.get("pinnedStore", {}).get("commit") == STORE_COMMIT, "Actual pinned store was not exercised")
    control = report.get("androidControl", {})
    require(all(control.get(key) == bootstrap[key] for key in IDENTITY_KEYS), "Report/control identities differ")
    require(control.get("physicalProfileRelease") == "notRun", "Physical profile/release status must remain NOT_RUN")
    matrix = report.get("platformMatrix", {})
    require(matrix.get("android", {}).get("status") == "passed", "Missing Android platform result")
    require(all(matrix.get(os_name, {}).get("status") == "notRun"
                for os_name in ("windows", "macos", "linux", "ios")), "Unexecuted platform reported as passed")
    phases = report.get("phases", [])
    by_name = {phase["name"]: phase for phase in phases}
    require(len(by_name) == len(phases) and all(by_name.get(name, {}).get("status") == "passed"
                                              for name in REQUIRED_PHASES), "Missing or failed original scenario phase")
    for name in ("minimize", "hide"):
        desktop = by_name.get(name, {})
        reason = desktop.get("reason")
        require(desktop.get("status") == "unsupported" and isinstance(reason, str) and reason.strip(),
                "Desktop visibility must be explicitly unsupported on Android with a reason")
    phase = by_name["osBackground"]
    require(phase.get("lifecycleBeforeQuiet") == "paused" and phase.get("lifecycleAfterResume") == "resumed",
            "Missing real Flutter background/resume acknowledgements")
    require(phase.get("dispatcherBeforeQuiet") == "hidden" and phase.get("shownBeforeQuiet") is False
            and phase.get("discardCandidateBeforeQuiet") is True and phase.get("dispatcherAfterResume") == "active"
            and phase.get("shownAfterResume") is True, "Missing real dispatcher background/resume acknowledgements")
    for key in ("sameControllerAfterResume", "sameDocumentAfterResume", "visibleStateMatches"):
        require(phase.get(key) is True, f"Home/resume did not preserve {key}")
    before, after = verify_document(phase.get("before")), verify_document(phase.get("after"))
    require(all(before[key] == after[key] for key in DOCUMENT_KEYS), "Home/resume recreated the plugin or document")
    for key in ("home", "hostQuiet", "resume"):
        require(phase.get(key) == evidence.get(key) and isinstance(phase.get(key), dict),
                f"App and host do not share the same native evidence: {key}")
    quiet = report.get("quietWindows", [])
    require({window["name"] for window in quiet} >=
            {"visibleIdle", "hiddenIdle", "osBackgroundIdle", "backgroundIdle", "closedIdle"},
            "Original quiet windows were not all measured")
    for window in quiet:
        require(window.get("probeJsCalls") == 0 and window.get("probeNativeQueries") == 0
                and window.get("productionTimersDisabled") is False
                and isinstance(window.get("elapsedMs"), (int, float))
                and window["elapsedMs"] >= window.get("requestedMs", 1000) >= 1000,
                "Quiet window contains probe work or insufficient elapsed time")
    proofs = report.get("restorations", [])
    require({proof.get("scenario") for proof in proofs} >= {"pressure", "count", "age", "store"},
            "Original discard policies and real store restoration were not all exercised")
    for proof in proofs:
        for key in ("sameInstanceId", "releasedByDispatcher", "controllerAbsentAfterDiscard",
                    "hostWidgetRemovedBeforeRestore", "differentControllerObject", "differentDocument",
                    "sdkBooted", "visibleStateMatches"):
            require(proof.get(key) is True, f"Incomplete real restoration: {key}")
        require(proof.get("before", {}).get("documentToken") != proof.get("after", {}).get("documentToken"),
                "A restoration reused the old document")
    guards = report.get("protectedControls", [])
    require(len(guards) == 4 and {guard.get("firstBlockingReason") for guard in guards} ==
            {"noRestoreState", "unsavedChanges", "busyRpc", "contextMenu"}, "Missing protected negative controls")
    require(len({guard.get("discardRequestId") for guard in guards}) == 1 and guards[0].get("discardRequestId")
            and all(guard.get("sameControllerAfterRequest") is True and guard.get("released") is False for guard in guards),
            "Protected controls did not survive the same discard request")
    return report


def verify_completion(receipt, event, preliminary):
    require(isinstance(receipt, dict)
            and all(receipt.get(key) == event[key] for key in (*IDENTITY_KEYS, "sequence")),
            "Final completion has stale campaign, process, or command identity")
    require(receipt.get("controlClosed") is True, "Device control cleanup did not complete")
    require(all(receipt.get(key) == preliminary[key]
                for key in ("frameworkPassed", "reportBytes", "reportSha256")),
            "Report changed after its completion acknowledgement")


class Runner:
    def __init__(self, args):
        self.args = args
        self.output = args.output.absolute()
        require(self.output.is_absolute() and not any(path.is_symlink() for path in (self.output, *self.output.parents)),
                "Output cannot traverse a symlink")
        require(not self.output.exists() or not any(self.output.iterdir()), "Output must be a fresh empty directory")
        self.output.mkdir(parents=True, exist_ok=True)
        self.raw = self.output / "raw"
        self.raw.mkdir()
        self.campaign = "campaign-" + uuid.uuid4().hex
        self.token = secrets.token_hex(32)
        self.commands = []
        self.quiet_active = False
        self.stage = "setup"
        self.forward = None
        self.installed = False
        self.bootstrap = None
        self.original = None
        self.event_connection = None
        self.deadline = None
        self.action_deadline = None
        self.launched_pid = None
        self.evidence = {}
        self.first_error = None
        self.recorded_errors = []
        self.report_sequence = 0
        self.cleaning_up = False
        self.result = {"schemaVersion": 1, "status": "running", "campaignId": self.campaign,
                       "startedUtc": utc_now(), "serial": args.device, "mode": "debug", "emulator": True,
                       "scope": "Actual app, installed store, native Home/resume and lifecycle contracts; emulator debug only",
                       "physicalProfileRelease": {"status": "notRun"},
                       "performanceAcceptance": {"status": "notRun"}, "evidence": self.evidence,
                       "cleanup": [], "bootstrapPolling": "Only before app.main and the first quiet window"}
        self.save()

    def failure(self, error, source):
        if any(previous is error for previous in self.recorded_errors):
            return
        self.recorded_errors.append(error)
        detail = {"order": len(self.recorded_errors), "source": source,
                  "error": f"{type(error).__name__}: {error}"}
        if self.first_error is None:
            self.first_error = error
            self.result.update(status="failed", error=detail["error"], primaryFailure=detail)
        else:
            self.result.setdefault("secondaryErrors", []).append(detail)

    def evidence_failure(self, error, source):
        self.failure(error, source)
        try:
            diagnostic = {"type": "installedPluginEvidenceError", "campaignId": self.campaign,
                          "source": source[:512], "error": str(error)[:2048],
                          "primaryError": self.result["error"][:2048], "order": len(self.recorded_errors)}
            sys.stderr.write(json.dumps(diagnostic) + "\n")
            sys.stderr.flush()
        except BaseException as fallback_error:
            self.failure(fallback_error, "stderr fallback")

    def save(self, *, best_effort=False):
        pending = self.output / f"host-report-{self.report_sequence:04d}.pending.json"
        self.report_sequence += 1
        try:
            with pending.open("x", encoding="utf-8") as stream:
                stream.write(json.dumps(self.result, indent=2) + "\n")
            pending.replace(self.output / "host-report.json")
        except BaseException as error:
            self.evidence_failure(error, f"host-report.json from {pending.name}")
            if not best_effort:
                raise self.first_error

    def drain_failed_command(self, child, error, number):
        for sig, grace in ((signal.SIGTERM, 5), (signal.SIGKILL, 5)):
            try:
                os.killpg(child.pid, sig)
            except ProcessLookupError:
                pass
            except BaseException as stop_error:
                self.failure(error, f"command {number}")
                self.failure(stop_error, f"command {number} termination")
            try:
                child.wait(timeout=grace)
            except subprocess.TimeoutExpired:
                continue
            except BaseException as wait_error:
                self.failure(error, f"command {number}")
                self.failure(wait_error, f"command {number} termination wait")

    def capture_cleanup(self, child, timeout, buffers):
        end = min(bound for bound in (time.monotonic() + timeout, self.deadline, self.action_deadline)
                  if bound is not None)
        with selectors.DefaultSelector() as ready:
            for name in buffers:
                stream = getattr(child, name)
                os.set_blocking(stream.fileno(), False)
                ready.register(stream, selectors.EVENT_READ, name)
            while ready.get_map():
                remaining = end - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(child.args, timeout)
                events = ready.select(remaining)
                if not events:
                    raise subprocess.TimeoutExpired(child.args, timeout)
                for key, _ in events:
                    target = buffers[key.data]
                    available = COMMAND_OUTPUT_LIMIT - len(target)
                    try:
                        chunk = os.read(key.fd, min(64 * 1024, available + 1))
                    except BlockingIOError:
                        continue
                    if not chunk:
                        ready.unregister(key.fileobj)
                        continue
                    target.extend(chunk[:available])
                    require(len(chunk) <= available, f"Cleanup {key.data} exceeds the {COMMAND_OUTPUT_LIMIT}-byte limit")
            return child.wait(timeout=max(0, end - time.monotonic()))

    def command(self, argv, *, check=True, timeout=60, env=None, capture=True, on_success=None):
        require(not self.quiet_active, "Host command attempted inside a quiet window")
        require(not self.cleaning_up or on_success is None, "Cleanup cannot allocate new owned resources")
        for deadline in (self.deadline, self.action_deadline):
            if deadline is None:
                continue
            timeout = min(timeout, deadline - time.monotonic())
            require(timeout > 0, "Host scenario deadline expired")
        number = len(self.commands)
        record = {"number": number, "stage": self.stage, "argv": list(map(str, argv)),
                  "startedUtc": utc_now(), "startedMonotonic": time.monotonic()}
        self.commands.append(record)
        stdout, stderr = self.raw / f"command-{number:04d}.stdout", self.raw / f"command-{number:04d}.stderr"
        record.update(stdout=str(stdout.relative_to(self.output)), stderr=str(stderr.relative_to(self.output)))
        command_error = None
        buffers = {"stdout": bytearray(), "stderr": bytearray()} if self.cleaning_up else None
        captured = False
        try:
            with ExitStack() as streams:
                if buffers is None:
                    out = streams.enter_context(stdout.open("xb"))
                    err = streams.enter_context(stderr.open("xb"))
                else:
                    out = err = subprocess.PIPE
                child = subprocess.Popen(argv, cwd=ROOT, env=env, stdout=out, stderr=err,
                                         stdin=subprocess.DEVNULL, start_new_session=True)
                record["ownedProcessGroup"] = child.pid
                if buffers is not None:
                    streams.enter_context(child.stdout)
                    streams.enter_context(child.stderr)
                try:
                    if buffers is None:
                        code = child.wait(timeout=timeout)
                    else:
                        code = self.capture_cleanup(child, timeout, buffers)
                        captured = True
                except BaseException as error:
                    self.drain_failed_command(child, error, number)
                    raise
                record["exitCode"] = code
                if code == 0 and on_success is not None:
                    on_success(stdout)
            if check and code:
                raise RuntimeError(f"Command {number} failed ({code}); see {record['stderr']}")
            if buffers is not None:
                return subprocess.CompletedProcess(argv, code, bytes(buffers["stdout"]) if capture else b"",
                                                   bytes(buffers["stderr"]) if capture else b"")
            require(not capture or max(stdout.stat().st_size, stderr.stat().st_size) <= COMMAND_OUTPUT_LIMIT,
                    "Command response exceeds limit")
            return subprocess.CompletedProcess(argv, code, stdout.read_bytes() if capture else b"",
                                               stderr.read_bytes() if capture else b"")
        except BaseException as error:
            command_error = error
            record["error"] = str(error)
            raise
        finally:
            record["finishedMonotonic"] = time.monotonic()
            if buffers is not None:
                record["cleanupCapture"] = {"transport": "pipes", "complete": captured,
                                            "limitBytesPerStream": COMMAND_OUTPUT_LIMIT,
                                            "bytes": {name: len(data) for name, data in buffers.items()}}
                for name, data in buffers.items():
                    try:
                        with (self.output / record[name]).open("xb") as stream:
                            stream.write(data)
                    except BaseException as error:
                        if command_error is not None:
                            self.failure(command_error, f"command {number}")
                        record.setdefault("captureWriteErrors", []).append(
                            {"stream": name, "error": f"{type(error).__name__}: {error}"})
                        record[name + "Fallback"] = {"encoding": "base64", "bytes": len(data),
                                                     "data": base64.b64encode(data).decode("ascii")}
                        self.result["commandReceiptFallback"] = self.commands
                        self.evidence_failure(error, f"command {number} {record[name]}")
            try:
                with (self.output / "commands.jsonl").open("a", encoding="utf-8") as stream:
                    stream.write(json.dumps(record) + "\n")
            except BaseException as error:
                if command_error is not None:
                    self.failure(command_error, f"command {number}")
                record["evidenceError"] = f"{type(error).__name__}: {error}"
                self.result["commandReceiptFallback"] = self.commands
                self.evidence_failure(error, f"commands.jsonl command {number}")
                if command_error is None and not self.cleaning_up:
                    raise self.first_error

    def adb(self, *args, **kwargs):
        return self.command([self.args.adb, "-s", self.args.device, *args], **kwargs)

    def text(self, *args, **kwargs):
        return self.adb(*args, **kwargs).stdout.decode("utf-8", errors="replace").strip()

    def resolve_home(self):
        # Android's --brief also emits ResolveInfo metadata; --components emits only the component.
        component = normalize_component(self.text("shell", "cmd", "package", "resolve-activity", "--components", "--user", "0",
                                                 "-a", "android.intent.action.MAIN", "-c", "android.intent.category.HOME"))
        require(not component.startswith(PACKAGE + "/"), "HOME cannot resolve to the probe")
        return component

    def read_process(self):
        value = self.text("shell", "pidof", PACKAGE)
        if not value.isdigit() or int(value) != self.bootstrap["pid"]:
            raise RuntimeError("Expected exactly the bootstrapped app PID")
        raw = self.text("shell", "-T", "run-as", PACKAGE, "cat", f"/proc/{value}/stat")
        return process_identity(raw, int(value))

    def snapshot(self):
        first = len(self.commands)
        process = self.read_process()
        observed = activity_snapshot(self.text("shell", "dumpsys", "activity", "activities"))
        return {**observed, "process": process, "serial": self.args.device, "package": PACKAGE,
                "atUtc": utc_now(), "monotonic": time.monotonic(), "commands": list(range(first, len(self.commands)))}

    def wait_native(self, *, foreground):
        end = time.monotonic() + 30
        for deadline in (self.deadline, self.action_deadline):
            if deadline is not None:
                end = min(end, deadline)
        last = None
        while time.monotonic() < end:
            try:
                observed = self.snapshot()
                original = self.original or observed
                require_native_state(observed, original, foreground=foreground, launcher=self.launcher)
                return observed
            except ValueError as error:
                last = error
                time.sleep(0.1)
        raise TimeoutError(f"Native activity acknowledgement timed out: {last}")

    def build(self):
        require(self.text("get-state") == "device", "Selected ADB serial is not available")
        self.result["adbVersion"] = self.text("version")
        require(self.text("shell", "getprop", "ro.kernel.qemu") == "1", "This functional runner requires an emulator")
        require(self.text("shell", "am", "get-current-user") == "0", "Use the emulator primary user")
        existing = self.adb("shell", "pm", "path", PACKAGE, check=False)
        require(not existing.stdout.strip(), "Dedicated probe package already exists; use a fresh emulator")
        abi = self.text("shell", "getprop", "ro.product.cpu.abi")
        require(abi == "x86_64", "This CI probe supports the x86_64 Android emulator")
        self.launcher = self.resolve_home()
        self.result["device"] = {"abi": abi, "sdk": self.text("shell", "getprop", "ro.build.version.sdk"),
                                 "fingerprint": self.text("shell", "getprop", "ro.build.fingerprint"),
                                 "display": self.text("shell", "wm", "size"),
                                 "density": self.text("shell", "wm", "density"), "home": self.launcher,
                                 "webViewProvider": self.text("shell", "dumpsys", "webviewupdate")}
        version = json.loads(self.command([self.args.flutter, "--version", "--machine"]).stdout)
        require(version.get("frameworkVersion") == "3.47.7", "Use the reviewed Flutter 3.47.7 toolchain")
        executable = shutil.which(self.args.flutter)
        require(executable is not None, "Flutter executable is unavailable")
        sdk_root = Path(executable).resolve().parent.parent
        sdk_head = self.command(["git", "-C", str(sdk_root), "rev-parse", "HEAD"]).stdout.decode().strip()
        require(sdk_head == version.get("frameworkRevision") and not self.command(
            ["git", "-C", str(sdk_root), "status", "--porcelain", "--untracked-files=no"]).stdout.strip(),
            "Flutter SDK sources differ from their reported revision")
        commit = self.command(["git", "rev-parse", "HEAD"]).stdout.decode().strip()
        require(not self.command(["git", "status", "--porcelain", "--untracked-files=no"]).stdout.strip(),
                "Commit tracked probe changes before building")
        self.result["sourceCommit"] = commit
        self.result["sourceTree"] = self.command(["git", "rev-parse", "HEAD^{tree}"]).stdout.decode().strip()
        self.result["flutter"] = version
        lock_before = (ROOT / "pubspec.lock").read_bytes()
        self.command([self.args.flutter, "pub", "get", "--enforce-lockfile"], timeout=600)
        require(lock_before == (ROOT / "pubspec.lock").read_bytes(), "Strict pub changed the lockfile")
        config = json.loads((ROOT / ".dart_tool/package_config.json").read_text())
        packages = {entry["name"]: entry for entry in config["packages"]}
        pins = {}
        for name in PACKAGES:
            uri = urllib.parse.urlparse(packages[name]["rootUri"])
            require(uri.scheme in ("", "file"), "Unsupported resolved package URI")
            path = Path(urllib.parse.unquote(uri.path))
            if not path.is_absolute():
                path = (ROOT / ".dart_tool" / path).resolve()
            observed = self.command(["git", "-C", str(path), "rev-parse", "HEAD"]).stdout.decode().strip()
            require(observed == NATIVE_PIN, f"Mixed or unexpected native pin: {name}")
            require(not self.command(["git", "-C", str(path), "status", "--porcelain", "--untracked-files=no"]).stdout.strip(),
                    f"Resolved native package contains modified sources: {name}")
            pins[name] = observed
        self.result["dependencies"] = {"lockSha256": hashlib.sha256(lock_before).hexdigest(), "nativePins": pins}
        source = self.output / "store-source"
        defines_file = self.output / "defines.json"
        prepare(source)
        write_defines(source, defines_file)
        defines = json.loads(defines_file.read_text())
        defines.update(INSTALLED_PROBE_ANDROID_CONTROL="true", INSTALLED_PROBE_ANDROID_CAMPAIGN=self.campaign,
                       INSTALLED_PROBE_ANDROID_TOKEN=self.token, INSTALLED_PROBE_IDLE_MS=str(self.args.quiet_ms),
                       INSTALLED_PROBE_FLUTTER_VERSION=version["frameworkVersion"], INSTALLED_PROBE_COMMIT=commit,
                       INSTALLED_PROBE_MACHINE_ID=self.args.device,
                       INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE="false")
        defines_file.write_text(json.dumps(defines) + "\n", encoding="utf-8")
        env = dict(os.environ, ORG_GRADLE_PROJECT_otzariaInstalledProbe="true", CARGO_NET_GIT_FETCH_WITH_CLI="true")
        env.pop("ORG_GRADLE_PROJECT_otzariaStartupProbe", None)
        self.command([self.args.flutter, "build", "apk", "--debug", "--no-pub", "--flavor", "direct", "--target", TARGET,
                      "--target-platform", "android-x64", "--dart-define-from-file", str(defines_file)],
                     env=env, timeout=3600, capture=False)
        require(not self.command(["git", "status", "--porcelain", "--untracked-files=no"]).stdout.strip()
                and lock_before == (ROOT / "pubspec.lock").read_bytes(), "Build changed tracked source or the lockfile")
        apk = ROOT / "build/app/outputs/flutter-apk/app-direct-debug.apk"
        sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
        candidates = sorted(Path(sdk).glob("build-tools/*/aapt2")) if sdk else []
        aapt = shutil.which("aapt2") or (str(candidates[-1]) if candidates else None)
        require(aapt, "aapt2 is needed to verify the dedicated APK before installation")
        badging = self.command([aapt, "dump", "badging", str(apk)]).stdout.decode()
        self.result["apk"] = {**verify_apk(badging), "sha256": file_sha256(apk),
                              "bytes": apk.stat().st_size}
        self.save()
        self.install(apk)

    def install(self, apk):
        def accepted(_):
            self.installed = True

        self.adb("install", str(apk), timeout=180, capture=False, on_success=accepted)

    def allocate_forward(self):
        def accepted(stdout):
            require(stdout.stat().st_size <= 32, "Oversized ADB forwarding port reply")
            port = stdout.read_text(encoding="ascii").strip()
            require(port.isdigit() and 0 < int(port) < 65536, "ADB did not allocate an owned forwarding port")
            self.forward = int(port)

        self.adb("forward", "tcp:0", f"tcp:{self.bootstrap['port']}", on_success=accepted)

    def connect(self):
        self.adb("shell", "am", "start", "-W", "-n", COMPONENT, "-a", "android.intent.action.MAIN")
        launched = self.text("shell", "pidof", PACKAGE)
        require(launched.isdigit(), "Initial launch did not yield exactly one probe PID")
        self.launched_pid = int(launched)
        bootstrap_path = f"files/{DIRECTORY}/{self.campaign}/bootstrap.json"
        end = time.monotonic() + 120
        while time.monotonic() < end:
            result = self.adb("shell", "-T", "run-as", PACKAGE, "cat", bootstrap_path, check=False)
            if result.returncode == 0:
                self.bootstrap = verify_bootstrap(json.loads(result.stdout), self.campaign)
                require(self.bootstrap["pid"] == self.launched_pid, "Probe process changed during setup")
                break
            time.sleep(0.25)
        require(self.bootstrap is not None, "App did not produce its bounded setup bootstrap")
        self.original = self.wait_native(foreground=True)
        self.allocate_forward()
        self.result.update(bootstrap=self.bootstrap, originalNative=self.original)
        self.save()
        self.event_connection = http.client.HTTPConnection("127.0.0.1", self.forward, timeout=1200)
        self.event_connection.request("GET", "/events", headers={"X-Installed-Probe": self.token})
        events = self.event_connection.getresponse()
        require(events.status == 200, "Device control stream did not connect")
        hello = self.read_event(events)
        require(all(hello.get(key) == self.bootstrap[key] for key in IDENTITY_KEYS)
                and hello.get("sequence") == 0 and hello.get("action") == "connected", "Wrong control stream identity")
        self.deadline = time.monotonic() + 1200
        return events

    def read_event(self, events):
        if self.deadline is not None:
            remaining = self.deadline - time.monotonic()
            require(remaining > 0, "Host scenario deadline expired")
            self.event_connection.sock.settimeout(remaining)
        line = events.readline(64 * 1024 + 1)
        require(line.endswith(b"\n") and len(line) <= 64 * 1024, "Truncated or oversized control event")
        return json.loads(line)

    def wait_completion(self, events, event, preliminary):
        self.stage = "finalizing"
        end = min(value for value in (time.monotonic() + COMPLETION_TIMEOUT,
                                     self.deadline, self.action_deadline) if value is not None)
        self.action_deadline = end
        remaining = end - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("Final completion deadline expired")
        if self.event_connection is not None:
            self.event_connection.sock.settimeout(remaining)
        try:
            trailing = events.read(1)
        except http.client.IncompleteRead as error:
            trailing = error.partial
        require(trailing == b"", "Unexpected control data after completion")
        # This bounded receipt read starts only after the measured scenario and stream closure.
        path = f"files/{DIRECTORY}/{self.campaign}/completion.json"
        while time.monotonic() < end:
            result = self.adb("shell", "-T", "run-as", PACKAGE, "cat", path, check=False)
            if result.returncode == 0:
                require(len(result.stdout) <= 64 * 1024, "Oversized final completion receipt")
                (self.output / "device-completion.json").write_bytes(result.stdout)
                receipt = json.loads(result.stdout)
                self.result["completionReceipt"] = receipt
                self.save()
                verify_completion(receipt, event, preliminary)
                raw = self.adb("shell", "-T", "run-as", PACKAGE, "cat", self.bootstrap["reportPath"]).stdout
                (self.output / "installed-plugin-report.json").write_bytes(raw)
                verify_report(raw, receipt, self.bootstrap, self.evidence, self.result["sourceCommit"])
                return
            time.sleep(min(0.1, max(0, end - time.monotonic())))
        raise TimeoutError("Device did not publish its final completion receipt after control close")

    def reply(self, event, result, *, ok=True):
        connection = http.client.HTTPConnection("127.0.0.1", self.forward, timeout=10)
        try:
            value = {key: event[key] for key in (*IDENTITY_KEYS, "sequence", "action")}
            value.update(ok=ok, result=result)
            connection.request("POST", "/reply", body=json.dumps(value),
                               headers={"X-Installed-Probe": self.token, "Content-Type": "application/json"})
            response = connection.getresponse()
            require(response.status == 204, "Device rejected a stale or mismatched host acknowledgement")
            response.read(1024)
        finally:
            connection.close()

    def quiet(self, milliseconds):
        start = time.monotonic()
        before = len(self.commands)
        self.quiet_active = True
        try:
            time.sleep(milliseconds / 1000)
        finally:
            self.quiet_active = False
        end = time.monotonic()
        require(before == len(self.commands), "A host command overlapped quiet")
        return {"startedMonotonic": start, "finishedMonotonic": end, "elapsedMs": (end - start) * 1000,
                "requestedMs": milliseconds, "hostCommands": 0,
                "transport": "One pushed request/reply at the boundaries; no ADB, JS or native polling"}

    def serve(self, events):
        protocol = Protocol(self.bootstrap, self.args.quiet_ms)
        while True:
            self.stage = "waitingForPush"
            event = self.read_event(events)
            action, payload = protocol.accept(event)
            self.stage = action
            self.action_deadline = time.monotonic() + (self.args.quiet_ms / 1000 + 35 if action == "quiet" else 35)
            acknowledged = False
            try:
                if action == "home":
                    before = self.wait_native(foreground=True)
                    # Emulator provisioning may replace its initial HOME handler
                    # during the APK build. Resolve independently at this boundary,
                    # then keep the expectation fixed through Home/quiet/resume.
                    self.launcher = self.resolve_home()
                    resolution = {"component": self.launcher, "command": self.commands[-1]["number"]}
                    self.result["homeResolution"] = resolution
                    self.save()
                    self.adb("shell", "input", "keyevent", "KEYCODE_HOME")
                    result = {"resolvedHome": resolution, "before": before,
                              "after": self.wait_native(foreground=False)}
                    self.evidence["home"] = result
                elif action == "quiet":
                    result = self.quiet(payload["durationMs"])
                    self.evidence["hostQuiet"] = result
                elif action == "resume":
                    before = self.wait_native(foreground=False)
                    self.adb("shell", "am", "start", "-W", "--activity-single-top", "--activity-reorder-to-front",
                             "-n", COMPONENT, "-a", "android.intent.action.MAIN")
                    result = {"before": before, "after": self.wait_native(foreground=True)}
                    self.evidence["resume"] = result
                else:
                    raw = self.adb("shell", "-T", "run-as", PACKAGE, "cat", self.bootstrap["reportPath"]).stdout
                    (self.output / "preliminary-installed-plugin-report.json").write_bytes(raw)
                    self.result["completion"] = payload
                    self.save()
                    verify_report(raw, payload, self.bootstrap, self.evidence, self.result["sourceCommit"])
                    require(protocol.actions == ["home", "quiet", "resume", "complete"], "Missing OS background phase")
                    quiet = self.evidence["hostQuiet"]
                    require(all(command["finishedMonotonic"] <= quiet["startedMonotonic"]
                                or command["startedMonotonic"] >= quiet["finishedMonotonic"] for command in self.commands),
                            "Recorded host command overlaps quiet")
                    self.result["finalNative"] = self.wait_native(foreground=True)
                    result = {"reportVerified": True}
                self.save()
                self.reply(event, result)
                acknowledged = True
                if action == "complete":
                    self.wait_completion(events, event, payload)
                    self.result["status"] = "passed"
                    self.action_deadline = None
                    return
                self.action_deadline = None
            except BaseException as error:
                if not acknowledged:
                    try:
                        self.reply(event, {"error": str(error)}, ok=False)
                    except Exception as reply_error:
                        self.result["replyError"] = str(reply_error)
                raise

    def cleanup(self):
        errors = []
        self.deadline = None
        self.action_deadline = None
        self.stage = "afterOutcome"
        self.cleaning_up = True

        def attempt(name, seconds, action, *, required=False):
            self.deadline = time.monotonic() + seconds
            try:
                action()
            except BaseException as error:
                self.result["cleanup"].append({name + "Error": str(error)})
                if required or not isinstance(error, Exception):
                    self.failure(error, "cleanup " + name)
                    errors.append(str(error))
            finally:
                self.deadline = None

        def partial_report():
            result = self.adb("shell", "-T", "run-as", PACKAGE, "cat", self.bootstrap["reportPath"], check=False)
            if result.returncode:
                return
            try:
                with (self.output / "partial-installed-plugin-report.json").open("xb") as stream:
                    stream.write(result.stdout)
            except BaseException as error:
                self.evidence_failure(error, "partial-installed-plugin-report.json")
                raise

        def remove_forward():
            local = f"tcp:{self.forward}"
            entries = [line.split() for line in self.text("forward", "--list").splitlines()]
            matching = [entry for entry in entries if len(entry) == 3 and entry[1] == local]
            expected = [self.args.device, local, f"tcp:{self.bootstrap['port']}"]
            require(not matching or matching == [expected], "Forward port belongs to another device or endpoint")
            if matching:
                self.adb("forward", "--remove", local)
            self.result["cleanup"].append({"ownedForward": self.forward, "removed": bool(matching),
                                           "alreadyAbsent": not matching})

        def stop_package():
            self.adb("shell", "am", "force-stop", PACKAGE)
            end = time.monotonic() + 5
            while True:
                observed = self.adb("shell", "pidof", PACKAGE, check=False, timeout=5)
                if observed.returncode == 1 and not observed.stdout.strip() and not observed.stderr.strip():
                    break
                require(observed.returncode == 0 and observed.stdout.decode().strip().isdigit(),
                        "Dedicated process exit is unavailable after cleanup")
                require(time.monotonic() < end, "Dedicated process did not exit after cleanup")
                time.sleep(0.1)
            self.result["cleanup"].append({"stoppedOwnedPackageAfterOutcome": PACKAGE,
                                           "reason": "Scenario already completed or failed; never a resume mechanism"})

        try:
            if self.event_connection is not None:
                attempt("connection", 1, self.event_connection.close, required=True)
            log_pid = self.bootstrap["pid"] if self.bootstrap is not None else self.launched_pid
            if log_pid is not None:
                attempt("logcat", 5, lambda: self.adb("logcat", "-d", "-t", "2000", "--pid", str(log_pid),
                                                       "-v", "threadtime", capture=False))
            if self.bootstrap is not None and not (self.output / "installed-plugin-report.json").exists():
                attempt("partialReport", 5, partial_report)
            if self.forward is not None:
                attempt("forward", 10, remove_forward, required=True)
            if self.installed:
                attempt("stop", 10, stop_package, required=True)
        finally:
            self.deadline = None
            self.action_deadline = None
            self.cleaning_up = False
        return errors

    def run(self):
        try:
            self.build()
            self.serve(self.connect())
        except BaseException as error:
            self.failure(error, "scenario")
            self.save(best_effort=True)
        finally:
            try:
                self.cleanup()
            except BaseException as error:
                self.failure(error, "cleanup")
            self.result["finishedUtc"] = utc_now()
            self.save(best_effort=True)
        if self.first_error is not None:
            raise self.first_error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Exact fresh x86_64 emulator serial")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--quiet-ms", type=int, default=1500)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--flutter", default="flutter")
    args = parser.parse_args()
    require(os.name == "posix", "This runner requires a POSIX host for bounded process-group cleanup")
    require(re.fullmatch(r"emulator-[0-9]+", args.device), "Use an explicit emulator serial")
    require(1000 <= args.quiet_ms <= 60000, "Quiet duration must be between 1000 and 60000 ms")
    def terminate(signum, frame):
        raise KeyboardInterrupt(f"Host controller received signal {signum}")

    signal.signal(signal.SIGTERM, terminate)
    Runner(args).run()


if __name__ == "__main__":
    main()
