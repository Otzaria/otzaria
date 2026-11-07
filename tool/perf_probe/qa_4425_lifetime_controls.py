#!/usr/bin/env python3
"""Independent QA controls for candidate 2497e0d; no native acceptance."""
from __future__ import annotations
import contextlib
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

SOURCE = "2497e0dde51862129fd34569290118b475a05f32"
SOURCE_TREE = "fe1051a7754b5fcc07b8afbddeded3ebade447bd"
RUNNER_SHA256 = "dcd1f451cd9e02646f77b2aeb19e87a25505c3924dec6aa0037546ca3eddfcb8"
ROOT = Path.cwd()
OUT = Path(os.environ["QA_EVIDENCE_DIR"])
OUT.mkdir(parents=True, exist_ok=False)
EVENTS = []
def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()
def save(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
def error_record(error):
    return {"type": type(error).__name__, "message": str(error),
            "returncode": getattr(error, "returncode", None),
            "orderedErrors": getattr(error, "apple_quiet_errors", None)}
source = ROOT / "tool/perf_probe/apple_plugin_activity/run.py"
assert git("rev-parse", SOURCE + "^{tree}") == SOURCE_TREE
assert hashlib.sha256(source.read_bytes()).hexdigest() == RUNNER_SHA256
qa_paths = sorted(git("diff", "--name-only", SOURCE, "HEAD").splitlines())
assert qa_paths == [".github/workflows/qa_4425_independent.yml", "tool/perf_probe/qa_4425_lifetime_controls.py"], qa_paths
before = git("status", "--porcelain=v1", "--untracked-files=all")
assert not before, before
spec = importlib.util.spec_from_file_location("qa_subject_apple_activity", source)
subject = importlib.util.module_from_spec(spec)
spec.loader.exec_module(subject)

def live(pid):
    try:
        state = Path("/proc", str(pid), "stat").read_text().rsplit(")", 1)[1].split()[0]
        return state not in {"Z", "X"}
    except FileNotFoundError:
        return False

def stop_test_group(pgid, child):
    # pgid was returned by this runner for its newly created session. Bind the
    # cleanup to the child that the test itself spawned inside that group.
    if live(child):
        if os.getpgid(child) != pgid:
            raise RuntimeError("Controlled child left its owned process group")
        try:
            os.killpg(pgid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 3
    while live(child) and time.monotonic() < deadline:
        time.sleep(.02)
    if live(child):
        raise RuntimeError("QA-owned child was not drained")
    return {"childRunningAfterQaCleanup": False, "ownedProcessGroup": pgid, "childPid": child}

class BadDescriptorOnClose:
    """Real owned temporary file; only its final close gets an EBADF."""
    def __init__(self, factory, *args, **kwargs):
        self.stream = factory(*args, **kwargs)
        self.closed_once = False
    def __getattr__(self, name):
        return getattr(self.stream, name)
    def __enter__(self):
        return self
    def __exit__(self, *args):
        self.close()
    def close(self):
        if self.closed_once:
            return
        self.closed_once = True
        os.close(self.stream.fileno())
        self.stream.close()

class IndependentLifetimeControls(unittest.TestCase):
    def test_closed_stderr_does_not_replace_an_existing_driver_failure(self):
        first = subprocess.CalledProcessError(37, ["controlled-driver"])
        record = {}
        failures = subject.Failures(record)
        failures.add("driver", first)
        with tempfile.TemporaryFile(mode="w+") as closed:
            closed.close()
            caught = None
            with contextlib.redirect_stderr(closed):
                try:
                    failures.raise_if_any()
                except BaseException as error:
                    caught = error
        EVENTS.append({"case": self._testMethodName, "caught": error_record(caught),
                       "record": record, "sameFirstException": caught is first})
        self.assertIs(caught, first, "A closed diagnostic stderr replaced the first driver failure")

    def test_real_temporary_stream_close_failure_preserves_driver_exit(self):
        factory = tempfile.TemporaryFile
        with tempfile.TemporaryDirectory(prefix="qa-4425-close-") as temporary:
            directory = Path(temporary)
            caught = None
            with mock.patch.object(subject.tempfile, "TemporaryFile",
                                   side_effect=lambda *a, **kw: BadDescriptorOnClose(factory, *a, **kw)):
                try:
                    subject.recorded_output(directory, "driver",
                        [sys.executable, "-c", "import sys; print('owned output'); sys.exit(37)"], 5)
                except BaseException as error:
                    caught = error
            receipt = json.loads((directory / "driver.json").read_text())
            save("temporary-stream-close-receipt.json", receipt)
            EVENTS.append({"case": self._testMethodName, "caught": error_record(caught),
                           "commandExit": receipt["exitCode"],
                           "processExitAfterCleanup": receipt["processExitAfterCleanup"]})
            self.assertIsInstance(caught, subprocess.CalledProcessError,
                                  "Temporary stream close replaced the first command failure")
            self.assertEqual(caught.returncode, 37)
            self.assertEqual(receipt["processExitAfterCleanup"], 37)

    def test_exited_group_leader_does_not_leave_its_real_child_running(self):
        child = pgid = None
        with tempfile.TemporaryDirectory(prefix="qa-4425-descendant-") as temporary:
            directory = Path(temporary)
            pid_file = directory / "child.pid"
            child_code = "import os,pathlib,sys,time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(60)"
            parent_code = (
                "import pathlib,subprocess,sys,time\n"
                "p=subprocess.Popen([sys.executable,'-c',sys.argv[1],sys.argv[2]])\n"
                "deadline=time.monotonic()+5\n"
                "while not pathlib.Path(sys.argv[2]).exists():\n"
                " if time.monotonic()>deadline: raise RuntimeError('child readiness timeout')\n"
                " time.sleep(.01)\n"
                "sys.exit(37)\n"
            )
            caught = None
            try:
                try:
                    subject.recorded_output(directory, "driver",
                        [sys.executable, "-c", parent_code, child_code, str(pid_file)], 10)
                except BaseException as error:
                    caught = error
                receipt = json.loads((directory / "driver.json").read_text())
                pgid = receipt["ownedProcessGroup"]
                child = int(pid_file.read_text())
                running = live(child)
                EVENTS.append({"case": self._testMethodName, "caught": error_record(caught),
                               "ownedProcessGroup": pgid, "childPid": child,
                               "childRunningAfterSubjectCleanup": running})
                save("exited-leader-receipt.json", receipt)
                self.assertIsInstance(caught, subprocess.CalledProcessError)
                self.assertEqual(caught.returncode, 37)
                self.assertFalse(running, "The command leader exited but its owned child remains alive")
            finally:
                if child is None and pid_file.exists():
                    child = int(pid_file.read_text())
                receipt_file = directory / "driver.json"
                if pgid is None and receipt_file.exists():
                    pgid = json.loads(receipt_file.read_text()).get("ownedProcessGroup")
                if child is not None and pgid is not None:
                    EVENTS.append({"case": self._testMethodName, "qaCleanup": stop_test_group(pgid, child)})
                elif child is not None:
                    raise RuntimeError("Owned child existed without the runner's process-group receipt")

    def test_nested_cleanup_reports_keep_the_same_first_exception(self):
        first = subprocess.CalledProcessError(37, ["controlled-driver"])
        with tempfile.TemporaryFile(mode="w+") as diagnostics, contextlib.redirect_stderr(diagnostics):
            inner = subject.Failures({})
            inner.add("driver", first)
            inner.add("first sink", OSError("sink A"))
            try:
                inner.raise_if_any()
            except subprocess.CalledProcessError as original:
                self.assertIs(original, first)
            outer = subject.Failures({})
            outer.add("nested command", first)
            outer.add("independent cleanup", OSError("cleanup B"))
            caught = None
            try:
                outer.raise_if_any()
            except BaseException as error:
                caught = error
        self.assertIs(caught, first)
        record = first.apple_quiet_errors
        self.assertEqual(record["firstError"]["nestedErrors"]["firstError"]["stage"], "driver")
        self.assertEqual(record["firstError"]["nestedErrors"]["secondaryErrors"][0]["error"], "sink A")
        self.assertEqual(record["secondaryErrors"][0]["error"], "cleanup B")
        EVENTS.append({"case": self._testMethodName, "sameFirstException": True, "record": record})

    def test_ios_result_rejects_pre_dispatch_foreign_expired_and_duplicate_inputs(self):
        with tempfile.TemporaryDirectory(prefix="qa-4425-protocol-") as temporary:
            directory = Path(temporary)
            control = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"],
                                       start_new_session=True)
            try:
                coordinator = subject.Coordinator(directory, "qa-run", "qa-nonce", "ios", 6)
                coordinator.control_process = control
                identity = {"runId": "qa-run", "controllerPid": control.pid, "controllerBootToken": "qa-boot"}
                response, _ = coordinator.request("control-ready", identity, subject.now_ms())
                identity["controlSession"] = response["controlSession"]
                job = {"jobId": "qa-job", "phase": "visible", "status": "running", "seconds": 6,
                       "controlArm": {**identity, "challenge": "qa-challenge"},
                       "completionDeadlineMonotonic": time.monotonic() + 30}
                coordinator.jobs[job["jobId"]] = job
                result = {**identity, "jobId": job["jobId"], "challenge": "qa-challenge", "status": "passed"}
                rejected = []
                with self.assertRaises(ValueError):
                    coordinator.request("control-result", result, subject.now_ms())
                rejected.append("before dispatch")
                job["controlDispatched"] = {"controllerPid": control.pid}
                with self.assertRaises(ValueError):
                    coordinator.request("control-result", {**result, "challenge": "old-challenge"}, subject.now_ms())
                rejected.append("foreign challenge")
                job["completionDeadlineMonotonic"] = time.monotonic() - .001
                with self.assertRaises(ValueError):
                    coordinator.request("control-result", result, subject.now_ms())
                rejected.append("after completion deadline")
                job["completionDeadlineMonotonic"] = time.monotonic() + 30
                coordinator.request("control-result", result, subject.now_ms())
                with self.assertRaises(ValueError):
                    coordinator.request("control-result", result, subject.now_ms())
                rejected.append("duplicate terminal result")
                EVENTS.append({"case": self._testMethodName, "rejected": rejected,
                               "scope": "Protocol gate only, no quiet/native acceptance"})
            finally:
                os.killpg(control.pid, signal.SIGTERM)
                control.wait(timeout=5)

if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(IndependentLifetimeControls)
    with (OUT / "unittest.log").open("w") as log:
        result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite)
    after = git("status", "--porcelain=v1", "--untracked-files=all")
    integrity = {"source": SOURCE, "sourceTree": SOURCE_TREE, "qaHead": git("rev-parse", "HEAD"),
                 "qaOnlyChanges": qa_paths, "runnerSha256": RUNNER_SHA256, "before": before,
                 "after": after, "unchanged": before == after}
    save("source-integrity.json", integrity)
    save("events.json", EVENTS)
    summary = {"source": SOURCE, "testsRun": result.testsRun,
               "failures": [{"test": str(test), "traceback": trace} for test, trace in result.failures],
               "errors": [{"test": str(test), "traceback": trace} for test, trace in result.errors],
               "sourceUnchanged": before == after,
               "scope": "New independent failure and protocol controls; native acceptance excluded"}
    save("summary.json", summary)
    print("BEGIN_QA_4425_SUMMARY")
    print(json.dumps(summary))
    print("END_QA_4425_SUMMARY")
    print("BEGIN_QA_4425_EVENTS")
    print(json.dumps(EVENTS))
    print("END_QA_4425_EVENTS")
    sys.exit(0 if result.wasSuccessful() and before == after else 1)
