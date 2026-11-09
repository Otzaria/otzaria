#!/usr/bin/env python3
"""Run one isolated Android APK in fresh processes; never select the user app."""

from __future__ import annotations

import argparse
import base64
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time
import traceback
import uuid


PACKAGE = "org.otzaria.otzaria.startupprobe"
ACTIVITY = "org.otzaria.otzaria.MainActivity"
DIRECTORY = "android-webview-startup-probe"
SCENARIOS = ("noEnabled", "noOpen", "foreground", "background", "overlap")
TARGET = "integration_test/android_webview_startup_probe_test.dart"
ROOT = Path(__file__).resolve().parents[2]


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{7,63}", value):
        raise ValueError("Invalid probe identifier")
    return value


def report_path(config, filename):
    if filename not in ("ready.json", "completion.json", "sample-ack.json", "sample-ack.pending"):
        raise ValueError("Unknown probe report file")
    return "/".join(("files", DIRECTORY, identifier(config["campaignId"]), "runs",
                     identifier(config["runId"]), filename))


def encode_config(config):
    return base64.urlsafe_b64encode(json.dumps(config, separators=(",", ":")).encode()).decode()


def trial_plan(campaign, scenarios, repetitions, observation_ms, build_mode):
    identifier(campaign)
    if not scenarios or len(set(scenarios)) != len(scenarios) or any(s not in SCENARIOS for s in scenarios):
        raise ValueError("Select distinct known scenarios")
    if not 1 <= repetitions <= 10 or not 1000 <= observation_ms <= 60000:
        raise ValueError("Invalid repetition count or observation duration")
    if build_mode not in ("debug", "profile"):
        raise ValueError("Use debug for contracts or profile on a physical device")
    plan = []
    for repetition in range(repetitions):
        modes = ("bypass", "native") if repetition % 2 == 0 else ("native", "bypass")
        for scenario in scenarios:
            for mode in modes:
                plan.append({
                    "schemaVersion": 1, "campaignId": campaign,
                    "runId": uuid.uuid4().hex,
                    "fixtureId": f"fixture-{scenario}-{mode}",
                    "operation": "measure", "scenario": scenario,
                    "prewarmMode": mode,
                    "fixtureState": "prepared" if repetition == 0 else "reused",
                    "buildMode": build_mode, "observationMs": observation_ms,
                })
    return plan


def inspect_apk_badging(text):
    package = re.findall(r"^package: name='([^']+)'", text, re.MULTILINE)
    activity = re.findall(r"^launchable-activity: name='([^']+)'", text, re.MULTILINE)
    if package != [PACKAGE] or activity != [ACTIVITY]:
        raise ValueError("Refusing APK: expected the dedicated probe package and launcher")
    if not re.search(r"^application-debuggable\s*$", text, re.MULTILINE):
        raise ValueError("The supported debug/profile probe must permit its own run-as reports")
    return {"package": package[0], "activity": activity[0], "debuggable": True}


def host_pss(raw, expected_pid):
    value = {"availability": "unavailable", "metric": "proportionalSetSize",
             "unit": "KiB", "scope": "host", "source": "dumpsys meminfo: App Summary TOTAL PSS",
             "value": None, "completeEngineCoverage": None}
    headers = re.findall(r"\*\* MEMINFO in pid (\d+) \[([^\]]+)\] \*\*", raw)
    totals = re.findall(r"\bTOTAL PSS:\s*(\d+)\b", raw)
    if headers != [(str(expected_pid), PACKAGE)]:
        value["reason"] = "missing_or_mismatched_host_identity"
    elif len(totals) != 1:
        value["reason"] = "missing_or_ambiguous_total_pss"
    else:
        value.update(availability="collected", value=int(totals[0]))
    return value


def validate_report(report, config, pid, *, completion):
    if not isinstance(report, dict) or report.get("schemaVersion") != 1:
        raise ValueError("Unknown report schema")
    if report.get("config") != config or report.get("package") != PACKAGE:
        raise ValueError("Report belongs to a different config or package")
    if type(report.get("pid")) is not int or report["pid"] != pid:
        raise ValueError("Report belongs to a different process")
    identifier(report.get("bootId"))
    if report.get("buildMode") != config["buildMode"]:
        raise ValueError("Requested and actual Flutter build modes differ")
    if not re.fullmatch(r"[0-9a-f]{40}", report.get("sourceRevision", "")) or not report.get("flutterVersion"):
        raise ValueError("Missing build provenance")
    if type(report.get("sourceDirty")) is not bool or report.get("physicalDeviceAcceptance") is not False:
        raise ValueError("Invalid source or device acceptance claim")
    if not re.fullmatch(r"[0-9a-f]{64}", report.get("fixtureIdentity", "")):
        raise ValueError("Missing fixture identity")
    if report.get("appSettingsInitializedBeforeMain") is not False:
        raise ValueError("Fixture preparation initialized app-isolate Settings before app.main")
    if completion:
        if report.get("integrationTestsPassed") is not True or report.get("status") != "passed":
            raise ValueError("The application integration test did not pass")
        if report.get("testFailures") or report.get("error"):
            raise ValueError("A failure was hidden behind successful status")
    elif report.get("status") != "awaitingHostSample":
        raise ValueError("The live application did not reach the sampling boundary")
    if config["operation"] == "prepare":
        if report.get("appMainCalled") is not False or type(report.get("nativePrewarmCalls")) is not int or report["nativePrewarmCalls"] != 0:
            raise ValueError("Preparation unexpectedly started the application/WebView")
        return
    prior = report.get("previousFixtureLaunches")
    if (report.get("appMainCalled") is not True or type(prior) is not int or
            (prior != 0 if config["fixtureState"] == "prepared" else prior < 1)):
        raise ValueError("Missing actual app startup or incorrect fixture launch history")
    viewport = report.get("viewport", {})
    for key in ("widthPhysical", "heightPhysical", "devicePixelRatio"):
        value = viewport.get(key)
        if type(value) not in (int, float) or not math.isfinite(value) or value <= 0:
            raise ValueError("Missing actual viewport")
    measurement = report.get("measurement")
    if not isinstance(measurement, dict):
        raise ValueError("The application did not retain measurements")
    timeline = measurement.get("startupTimeline", {})
    reveal = timeline.get("revealMs")
    if type(reveal) is not int or reveal < 0:
        raise ValueError("No observed application reveal")
    if type(measurement.get("registeredEnabledPlugins")) is not int or measurement["registeredEnabledPlugins"] != (0 if config["scenario"] == "noEnabled" else 1):
        raise ValueError("The real registry did not contain the expected fixture")
    prewarm = measurement.get("prewarm", {})
    expected_entries = 0 if config["scenario"] == "noEnabled" else 1
    expected_native = expected_entries if config["prewarmMode"] == "native" else 0
    if (type(prewarm.get("invocations")) is not int or type(prewarm.get("nativeInvocations")) is not int or
            prewarm["invocations"] != expected_entries or prewarm["nativeInvocations"] != expected_native):
        raise ValueError("Wrong prewarm invocation counts")
    attempts = prewarm.get("attempts", [])
    if len(attempts) != expected_entries or prewarm.get("attemptsTruncated") is not False:
        raise ValueError("Missing prewarm attempts")
    if any(a.get("settingsMatchAndroidDefaults") is not True for a in attempts):
        raise ValueError("Android received non-default environment settings")
    if type(prewarm.get("pending")) is not bool or any(a.get("nativeCalled") is not (config["prewarmMode"] == "native") for a in attempts):
        raise ValueError("Native execution provenance is inconsistent")
    if config["prewarmMode"] == "bypass" and any(a.get("status") != "bypassedForProbe" for a in attempts):
        raise ValueError("The no-native control must retain its explicit bypass outcome")
    if type(report.get("nativePrewarmCalls")) is not int or report["nativePrewarmCalls"] != expected_native:
        raise ValueError("Top-level native count is inconsistent")
    reveal_at_prewarm = measurement.get("revealMsAtPrewarmInvocation")
    if (not isinstance(reveal_at_prewarm, list) or len(reveal_at_prewarm) != expected_entries or
            any(v is not None and (type(v) is not int or v != reveal) for v in reveal_at_prewarm)):
        raise ValueError("Missing or inconsistent prewarm/reveal ordering")
    if config["scenario"] in ("noEnabled", "noOpen"):
        if measurement.get("open") is not None or type(measurement.get("javascriptPolls")) is not int or measurement["javascriptPolls"] != 0:
            raise ValueError("A no-open control executed WebView work")
        resources = measurement.get("resources", {})
        if any(type(resources.get(key)) is not int or resources[key] != 0 for key in ("live", "backgroundLive")):
            raise ValueError("A no-open control owns a WebView")
    else:
        opened = measurement.get("open", {})
        snapshot = opened.get("document", {})
        mode = "background" if config["scenario"] == "background" else "foreground"
        if snapshot.get("boots") != 1 or snapshot.get("sdkBooted") is not True or snapshot.get("runMode") != mode:
            raise ValueError("The real SDK did not boot exactly once in the requested host")
        if snapshot.get("pluginId") != "org.otzaria.android-startup-fixture":
            raise ValueError("Wrong plugin document")
        if mode == "background":
            if snapshot.get("eventRunId") != config["runId"] or snapshot.get("eventCount") != 1:
                raise ValueError("The real background dispatcher did not deliver this run's event")
        elif snapshot.get("twoAnimationFrames") is not True:
            raise ValueError("Foreground document did not reach its two-rAF marker")
        if mode == "foreground":
            resources = measurement.get("resources")
            counts = {"registered": 1, "live": 1, "backgroundLive": 0}
            if (not isinstance(resources, dict) or
                    any(type(resources.get(key)) is not int or resources[key] != value
                        for key, value in counts.items())):
                raise ValueError("Foreground opening must end with exactly one foreground WebView")
            instances = resources.get("instances")
            if (resources.get("detailsTruncated") is not False or not isinstance(instances, list)
                    or len(instances) != 1 or not isinstance(instances[0], dict)
                    or opened.get("host") != "PluginTabPage"
                    or not isinstance(opened.get("instanceId"), str) or not opened["instanceId"]
                    or instances[0].get("pluginId") != snapshot["pluginId"]
                    or instances[0].get("instanceId") != opened["instanceId"]
                    or instances[0].get("live") is not True):
                raise ValueError("Foreground census does not identify the requested plugin instance")
            marks = timeline.get("marks")
            if (not isinstance(marks, list)
                    or any(not isinstance(mark, dict) or not isinstance(mark.get("name"), str) for mark in marks)
                    or [mark["name"] for mark in marks if mark["name"].startswith("reveal:immediate:")]
                    != ["reveal:immediate:Null"]):
                raise ValueError("Foreground opening did not start from the empty fixture at reveal")
    for key in ("nativeMainThreadResponsiveness", "nativeCpu"):
        if measurement.get(key) != {"availability": "notCollected", "value": None}:
            raise ValueError("This probe did not collect native CPU or UI responsiveness")


def pair_readiness(first, second):
    reasons = []
    a, b = first["config"], second["config"]
    if {a["prewarmMode"], b["prewarmMode"]} != {"native", "bypass"}:
        reasons.append("not_a_native_bypass_pair")
    for key in ("scenario", "fixtureState", "buildMode", "observationMs"):
        if a[key] != b[key]:
            reasons.append(f"different_{key}")
    for key in ("apkSha256", "deviceIdentity", "providerAfterMeasurement"):
        if first.get(key) != second.get(key) or not first.get(key):
            reasons.append(f"missing_or_different_{key}")
    reports = [first["report"], second["report"]]
    if reports[0]["bootId"] == reports[1]["bootId"]:
        reasons.append("reused_process_boot")
    if any(not trial.get("previousProcessExitObserved") for trial in (first, second)):
        reasons.append("fresh_process_not_verified")
    for key in ("fixtureIdentity", "sourceRevision", "flutterVersion", "viewport"):
        if reports[0].get(key) != reports[1].get(key) or not reports[0].get(key):
            reasons.append(f"missing_or_different_{key}")
    if any(report.get("sourceDirty") is not False for report in reports):
        reasons.append("source_revision_does_not_identify_clean_source")
    if a["scenario"] != "noEnabled" and any(
            report["measurement"].get("revealMsAtPrewarmInvocation") != [report["measurement"]["startupTimeline"]["revealMs"]]
            for report in reports):
        reasons.append("prewarm_started_before_observed_reveal")
    native = next((r for r in reports if r["config"]["prewarmMode"] == "native"), None)
    if native and a["scenario"] != "noEnabled":
        observation = native["measurement"]["prewarm"]
        if observation.get("pending") or observation["attempts"][0].get("status") != "ok":
            reasons.append("native_prewarm_not_observed_successful_at_measurement_end")
        if a["scenario"] == "overlap" and native["measurement"].get("overlap") != "observedAtRequest":
            reasons.append("opening_did_not_overlap_real_prewarm")
    memory_reasons = list(reasons)
    if any(trial.get("hostPss", {}).get("availability") != "collected" for trial in (first, second)):
        memory_reasons.append("host_pss_not_collected_for_both_runs")
    return {"comparableInputs": not reasons, "reasons": reasons,
            "hostPssComparableInputs": not memory_reasons, "hostPssReasons": memory_reasons,
            "performanceAcceptance": False,
            "scope": "paired Dart-startup/open observations; one APK, fresh processes, shared OS/provider caches"}


class ReportSignals:
    """One idle connection across measurement; bounded messages only at boundaries."""

    def __init__(self, runner, config):
        self.runner = runner
        self.config = config
        self.listener = None
        self.connection = None
        self.remote = None
        self.local = None
        self.buffer = b""
        self.identity = None
        self.events = []

    def open(self):
        for _ in range(8):
            self.listener = socket.socket()
            self.listener.bind(("127.0.0.1", 0))
            self.listener.listen(1)
            self.local = f"tcp:{self.listener.getsockname()[1]}"
            # Use the same explicit port on both ends: ADB's host allow-list
            # retains tcp:0 after removal of its resolved device port.
            result = self.runner.adb("reverse", "--no-rebind", self.local, self.local,
                                     check=lambda result: not self._port_collision(result),
                                     on_success=self._own_reverse)
            if result.returncode == 0:
                return self.config
            self.listener.close()
            self.listener = None
        raise RuntimeError("Startup signal ports remained occupied after 8 attempts: " +
                           result.stderr.decode(errors="replace")[-3000:])

    @staticmethod
    def _port_collision(result):
        return any(message in result.stderr for message in (
            b"cannot rebind existing socket",
            b"cannot bind listener: Address already in use",
        ))

    def _own_reverse(self, _):
        # Record the allocation before command-log I/O can fail. The caller's
        # cleanup owns only this successfully bound, explicit device port.
        self.remote = self.local
        self.config = dict(self.config, signalPort=int(self.remote[4:]))

    def receive(self, timeout):
        deadline = time.monotonic() + timeout
        if self.connection is None:
            self.listener.settimeout(timeout)
            self.connection, _ = self.listener.accept()
            self.listener.close()
            self.listener = None
        while b"\n" not in self.buffer:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("Timed out waiting for startup probe signal")
            self.connection.settimeout(remaining)
            block = self.connection.recv(4097 - len(self.buffer))
            if not block:
                raise EOFError("Startup probe signal channel closed before its next signal")
            self.buffer += block
            newline = self.buffer.find(b"\n")
            if newline > 4096 or (newline < 0 and len(self.buffer) > 4096):
                raise ValueError("Oversized startup probe signal")
        line, self.buffer = self.buffer.split(b"\n", 1)
        signal = json.loads(line)
        keys = {"schemaVersion", "campaignId", "runId", "bootId", "pid", "event",
                "reportAvailable", "error"}
        if (not isinstance(signal, dict) or set(signal) != keys or
                type(signal["schemaVersion"]) is not int or signal["schemaVersion"] != 1):
            raise ValueError("Invalid startup probe signal schema")
        if any(signal[key] != self.config[key] for key in ("campaignId", "runId")):
            raise ValueError("Startup probe signal belongs to another run")
        if not isinstance(signal["bootId"], str):
            raise ValueError("Invalid startup probe signal boot")
        identifier(signal["bootId"])
        if type(signal["pid"]) is not int or signal["pid"] <= 0:
            raise ValueError("Invalid startup probe signal process")
        identity = (signal["pid"], signal["bootId"])
        if self.identity is not None and identity != self.identity:
            raise ValueError("Startup probe signal process or boot changed")
        if type(signal["reportAvailable"]) is not bool or not (
                signal["error"] is None or isinstance(signal["error"], str)):
            raise ValueError("Invalid startup probe signal outcome")
        event = signal["event"]
        expected = ("connected",) if not self.events else (
            ("ready", "completion") if self.events == ["connected"] and
            self.config["operation"] == "measure" else ("completion",))
        if event not in expected or event in self.events:
            raise ValueError("Duplicate or out-of-order startup probe signal")
        if event == "connected" and (signal["reportAvailable"] or signal["error"] is not None):
            raise ValueError("Invalid connected signal")
        if event == "ready" and (not signal["reportAvailable"] or signal["error"] is not None):
            raise ValueError("Invalid ready signal")
        self.identity = identity
        self.events.append(event)
        return signal

    def finish(self, timeout=5):
        if not self.events or self.events[-1] != "completion":
            raise ValueError("The signal channel has not completed")
        self.connection.settimeout(timeout)
        if self.buffer or self.connection.recv(1):
            raise ValueError("Extra data after startup probe completion signal")

    def close(self):
        for stream in (self.connection, self.listener):
            if stream is not None:
                stream.close()

    def remove_reverse(self):
        if self.remote is not None:
            # Inspect/remove before receipt writes, so a broken command log
            # cannot skip resource cleanup after a successful ADB operation.
            self.runner.adb("reverse", "--list", on_success=self._remove_owned_reverse)

    def _remove_owned_reverse(self, result):
        mappings = [line.split() for line in result.stdout.decode(errors="replace").splitlines()]
        matches = [entry for entry in mappings if len(entry) == 3 and entry[1] == self.remote]
        if not matches:
            self.remote = None
            return
        if len(matches) != 1 or matches[0][2] != self.local:
            raise RuntimeError("Startup probe reverse mapping was replaced; leaving it intact")
        self.runner.adb("reverse", "--remove", self.remote,
                        on_success=lambda _: setattr(self, "remote", None))


class Runner:
    def __init__(self, args):
        self.args = args
        self.output = args.output.resolve()
        if self.output.exists() and any(self.output.iterdir()):
            raise ValueError("Output directory must be new or empty")
        self.output.mkdir(parents=True, exist_ok=True)
        self.campaign = "campaign-" + uuid.uuid4().hex
        self.trials = []
        self.command_log = self.output / "commands.jsonl"
        self.current_pid = None
        self.cleanup_errors = []
        self.adb_version = None

    @contextmanager
    def cleanup(self, config, actions, primary=None):
        try:
            yield
        except BaseException as error:
            primary = error
            raise
        finally:
            first_cleanup = None
            for phase, action in actions:
                try:
                    action()
                except Exception as error:
                    self.cleanup_errors.append({
                        "runId": config.get("runId"), "phase": phase,
                        "error": f"{type(error).__name__}: {error}",
                        "traceback": traceback.format_exc(),
                    })
                    if first_cleanup is None:
                        first_cleanup = (error, error.__traceback__)
                    try:
                        print(f"Probe cleanup failed [{phase}]: {type(error).__name__}: {error}", file=sys.stderr)
                    except Exception as diagnostic_error:
                        self.cleanup_errors.append({
                            "runId": config.get("runId"), "phase": f"{phase}:stderr",
                            "error": f"{type(diagnostic_error).__name__}: {diagnostic_error}",
                            "traceback": traceback.format_exc(),
                        })
            if primary is None and first_cleanup is not None:
                error, stack = first_cleanup
                raise error.with_traceback(stack)

    def command(self, argv, *, check=True, timeout=60, data=None, env=None, on_success=None):
        started = time.monotonic()
        result = subprocess.run(argv, cwd=ROOT, env=env, input=data, capture_output=True, timeout=timeout)
        def record():
            with self.command_log.open("a") as stream:
                stream.write(json.dumps({"atUtc": utc_now(), "argv": list(map(str, argv)),
                                         "exitCode": result.returncode,
                                         "elapsedMs": round((time.monotonic() - started) * 1000, 3)}) + "\n")
        with self.cleanup({}, [("write_command_log", record)]):
            if result.returncode == 0 and on_success is not None:
                on_success(result)
            if result.returncode and (check(result) if callable(check) else check):
                raise RuntimeError(f"Command failed ({result.returncode}): {argv[0]}\n{result.stderr.decode(errors='replace')[-3000:]}")
        return result

    def adb(self, *args, **kwargs):
        return self.command([self.args.adb, "-s", self.args.device, *args], **kwargs)

    def text(self, *args, **kwargs):
        return self.adb(*args, **kwargs).stdout.decode(errors="replace").strip()

    def stop_probe(self):
        self.adb("shell", "am", "force-stop", PACKAGE)
        deadline = time.monotonic() + 10
        while self.text("shell", "pidof", PACKAGE, check=False):
            if time.monotonic() > deadline:
                raise RuntimeError("The previous probe process did not exit")
            time.sleep(0.1)
        self.current_pid = None

    def read_report_file(self, config, filename):
        # exec-out has no remote exit status; shell -T keeps that status and separates stderr.
        result = self.adb("shell", "-T", "run-as", PACKAGE, "cat", report_path(config, filename), check=False)
        folder = self.output / config["runId"]
        folder.mkdir(exist_ok=True)
        (folder / f"{filename}.read.stdout").write_bytes(result.stdout)
        (folder / f"{filename}.read.stderr").write_bytes(result.stderr)
        (folder / f"{filename}.read.json").write_text(json.dumps({
            "atUtc": utc_now(), "exitCode": result.returncode,
        }) + "\n")
        return result

    def wait_report(self, config, filename, timeout, signals):
        signal = signals.receive(timeout)
        actual = f"{signal['event']}.json"
        if actual not in (filename, "completion.json"):
            raise ValueError("Unexpected startup probe report signal")
        if not signal["reportAvailable"]:
            raise RuntimeError(f"Probe could not publish its report: {signal['error']}")
        result = self.read_report_file(config, actual)
        if result.returncode:
            raise RuntimeError(f"Signalled {actual} could not be read ({result.returncode})")
        report = json.loads(result.stdout)
        if (not isinstance(report, dict) or report.get("config") != config or
                report.get("package") != PACKAGE or
                (report.get("pid"), report.get("bootId")) != signals.identity):
            raise ValueError("Report does not match its startup probe signal")
        if actual != filename:
            (self.output / config["runId"] / actual).write_bytes(result.stdout)
            raise RuntimeError("The integration test ended before the host sampling boundary; see completion.json")
        if signal["error"] is not None:
            (self.output / config["runId"] / actual).write_bytes(result.stdout)
            raise RuntimeError(f"Probe reported failure: {signal['error']}")
        return report

    def build(self):
        env = dict(os.environ, ORG_GRADLE_PROJECT_otzariaStartupProbe="true")
        version = json.loads(self.command([self.args.flutter, "--version", "--machine"]).stdout)
        revision = self.command(["git", "rev-parse", "HEAD"]).stdout.decode().strip()
        dirty = bool(self.command(["git", "status", "--porcelain", "--untracked-files=normal"]).stdout)
        self.command([self.args.flutter, "pub", "get", "--enforce-lockfile"], timeout=600, env=env)
        argv = [self.args.flutter, "build", "apk", f"--{self.args.mode}", "--no-pub",
                "--flavor", "direct", "--target", TARGET, "--target-platform", self.target,
                "--dart-define=OTZARIA_ANDROID_STARTUP_PROBE=true",
                "--dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false",
                f"--dart-define=OTZARIA_PROBE_SOURCE_REVISION={revision}",
                f"--dart-define=OTZARIA_PROBE_SOURCE_DIRTY={'true' if dirty else 'false'}",
                f"--dart-define=OTZARIA_PROBE_FLUTTER_VERSION={version['frameworkVersion']}"]
        result = self.command(argv, timeout=3600, env=env, check=False)
        (self.output / "build.log").write_bytes(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError("Probe APK build failed; see build.log")
        apk = ROOT / "build/app/outputs/flutter-apk" / f"app-direct-{self.args.mode}.apk"
        aapt = shutil.which("aapt2")
        if not aapt:
            sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
            matches = list(Path(sdk).glob("build-tools/*/aapt2")) if sdk else []
            if not matches:
                raise RuntimeError("aapt2 is required to verify the APK before installation")
            aapt = str(sorted(matches)[-1])
        badging = self.command([aapt, "dump", "badging", str(apk)]).stdout.decode()
        (self.output / "apk-badging.txt").write_text(badging)
        self.apk_metadata = inspect_apk_badging(badging)
        with apk.open("rb") as stream:
            self.apk_hash = hashlib.file_digest(stream, "sha256").hexdigest()
        self.build_metadata = {"sourceRevision": revision, "sourceDirty": dirty,
                               "flutter": version, "apkSha256": self.apk_hash, **self.apk_metadata}
        (self.output / "build.json").write_text(json.dumps(self.build_metadata, indent=2) + "\n")
        self.adb("install", "-r", str(apk), timeout=180)
        self.adb("shell", "run-as", PACKAGE, "pwd")

    def collect_log(self, folder, pid, since):
        raw = self.text("logcat", "-d", "--pid", str(pid), "-v", "epoch", "-t", "2000", check=False)
        lines = []
        for line in raw.splitlines():
            match = re.match(r"\s*(\d+\.\d+)\s", line)
            if match and float(match[1]) >= since:
                lines.append(line)
        (folder / "process-logcat.txt").write_text("\n".join(lines) + "\n")

    def launch(self, config):
        signals = ReportSignals(self, config)
        with self.cleanup(config, [
            ("stop_probe", self.stop_probe),
            ("close_signal", signals.close),
            ("remove_reverse", signals.remove_reverse),
        ]):
            self._launch(config, signals)

    def _launch(self, config, signals):
        folder = self.output / config["runId"]
        folder.mkdir()
        self.stop_probe()
        config = signals.open()
        (folder / "config.json").write_text(json.dumps(config, indent=2) + "\n")
        since = float(self.text("shell", "date", "+%s"))
        started = time.monotonic()
        launch = self.adb("shell", "am", "start", "-W", "-n", f"{PACKAGE}/{ACTIVITY}",
                          "-a", "android.intent.action.MAIN", "--esal", "dart_entrypoint_args", encode_config(config))
        (folder / "am-start.txt").write_bytes(launch.stdout + launch.stderr)
        connected = signals.receive(30)
        self.current_pid = process_id = connected["pid"]
        process = str(process_id)
        sample = None
        with self.cleanup(config, [("collect_log", lambda: self.collect_log(folder, process_id, since))]):
            if config["operation"] == "measure":
                ready = self.wait_report(config, "ready.json", 240, signals)
                (folder / "ready.json").write_text(json.dumps(ready, indent=2) + "\n")
                validate_report(ready, config, process_id, completion=False)
                if self.text("shell", "pidof", PACKAGE) != process:
                    raise RuntimeError("Probe process changed before the memory sample")
                at = utc_now()
                sample_start = time.monotonic()
                raw = self.text("shell", "dumpsys", "meminfo", "-d", process, check=False)
                (folder / "host-meminfo.txt").write_text(raw)
                sample = host_pss(raw, process_id)
                if self.text("shell", "pidof", PACKAGE) != process:
                    sample.update(availability="unavailable", value=None, reason="process_changed_during_sample")
                sample.update(startedAtUtc=at, elapsedMs=round((time.monotonic() - sample_start) * 1000, 3),
                              hostElapsedSinceLaunchMs=round((time.monotonic() - started) * 1000, 3))
                self.adb("shell", "-T", "run-as", PACKAGE, "tee", report_path(config, "sample-ack.pending"),
                         data=json.dumps({"runId": config["runId"], "bootId": ready["bootId"]}).encode())
                self.adb("shell", "run-as", PACKAGE, "mv", report_path(config, "sample-ack.pending"),
                         report_path(config, "sample-ack.json"))
            report = self.wait_report(config, "completion.json", 240 if config["operation"] == "prepare" else 30, signals)
            (folder / "completion.json").write_text(json.dumps(report, indent=2) + "\n")
            validate_report(report, config, process_id, completion=True)
            signals.finish()
            if config["operation"] == "prepare":
                return
            if report["bootId"] != ready["bootId"]:
                raise ValueError("The process boot identity changed during host sampling")
            provider = self.text("shell", "dumpsys", "webviewupdate", check=False)
            (folder / "provider-after-measurement.txt").write_text(provider)
            current = re.search(r"Current WebView package \(name, version\):\s*\(([^)]+)\)", provider)
            trial = {"config": config, "report": report, "hostPss": sample,
                     "engineMemory": {"availability": "unavailable", "value": None, "complete": None,
                                      "reason": "renderer_process_association_not_collected"},
                     "previousProcessExitObserved": True, "apkSha256": self.apk_hash,
                     "deviceIdentity": self.device_identity,
                     "providerAfterMeasurement": current[1] if current else None,
                     "elapsedMs": round((time.monotonic() - started) * 1000, 3)}
            self.trials.append(trial)
            (folder / "trial.json").write_text(json.dumps(trial, indent=2) + "\n")

    def run(self):
        failure = None
        failure_stack = None
        try:
            self.adb_version = self.text("version")
            (self.output / "adb-version.txt").write_text(self.adb_version + "\n")
            if self.text("get-state") != "device":
                raise RuntimeError("The selected adb device is unavailable")
            emulator = self.text("shell", "getprop", "ro.kernel.qemu") == "1"
            abi = self.text("shell", "getprop", "ro.product.cpu.abi")
            if self.args.mode == "profile" and emulator:
                raise ValueError("Use debug contract mode on an emulator; profile measurements need a physical device")
            targets = {"arm64-v8a": "android-arm64", "armeabi-v7a": "android-arm", "x86_64": "android-x64"}
            if abi not in targets:
                raise ValueError("Unsupported Android ABI for this probe")
            self.target = targets[abi]
            self.device_identity = {
                "fingerprint": self.text("shell", "getprop", "ro.build.fingerprint"),
                "sdk": self.text("shell", "getprop", "ro.build.version.sdk"),
                "abi": abi, "emulator": emulator,
                "display": self.text("shell", "wm", "size"),
                "density": self.text("shell", "wm", "density"),
            }
            (self.output / "device.json").write_text(json.dumps(self.device_identity, indent=2) + "\n")
            self.build()
            plan = trial_plan(self.campaign, self.args.scenarios, self.args.repetitions,
                              self.args.observation_ms, self.args.mode)
            (self.output / "plan.json").write_text(json.dumps(plan, indent=2) + "\n")
            for config in plan:
                if config["fixtureState"] == "prepared":
                    self.launch(dict(config, operation="prepare", runId=uuid.uuid4().hex))
                self.launch(config)
        except BaseException as error:
            failure = f"{type(error).__name__}: {error}"
            failure_stack = traceback.format_exc()
            raise
        finally:
            result = {"schemaVersion": 1, "campaignId": self.campaign, "finishedAtUtc": utc_now(),
                      "status": "failed" if failure else "passed", "error": failure,
                      "errorTraceback": failure_stack, "cleanupErrors": self.cleanup_errors,
                      "hostAdbVersion": self.adb_version,
                      "hostReportTransport": "persistentAdbReverseSocket",
                      "hostReportPollIntervalMs": None,
                      "trials": self.trials,
                      "pairs": [pair_readiness(a, b) for a, b in zip(self.trials[::2], self.trials[1::2])],
                      "physicalDeviceAcceptance": False,
                      "limits": ["Fresh app processes do not imply cold OS or WebView provider caches.",
                                 "Prepared/reused labels describe the isolated fixture's launch history only.",
                                 "Fixture validation reads its files before app.main and warms those file caches.",
                                 "An idle ADB reverse socket is connected before measurement; report reads follow boundary signals.",
                                 "Host PSS is sampled after the app's measurement boundary, while it waits for an ack.",
                                 "Dart heartbeat/Flutter frames do not establish Android main-thread or WebView render responsiveness.",
                                 "No automatic performance threshold or default change; native CPU/renderer association are not collected."]}
            with self.cleanup({}, [("write_campaign", lambda: (self.output / "campaign.json").write_text(
                    json.dumps(result, indent=2) + "\n"))], primary=failure):
                pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Explicit adb serial; only the dedicated probe package is modified")
    parser.add_argument("--output", type=Path, required=True, help="New or empty output directory")
    parser.add_argument("--mode", choices=("profile", "debug"), default="profile")
    parser.add_argument("--repetitions", type=int, choices=range(1, 11), default=3)
    parser.add_argument("--observation-ms", type=int, default=5000)
    parser.add_argument("--scenarios", nargs="+", choices=SCENARIOS, default=list(SCENARIOS))
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--flutter", default="flutter")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9._:-]{1,128}", args.device):
        parser.error("Invalid adb serial")
    trial_plan("validate-only", args.scenarios, args.repetitions, args.observation_ms, args.mode)
    Runner(args).run()


if __name__ == "__main__":
    main()
