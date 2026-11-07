"""Real-child/filesystem controls; these are not Apple device measurements."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("apple_lifetime", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class CleanupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)

    def test_command_error_survives_two_real_output_failures(self):
        for stream in ("stdout", "stderr"):
            (self.directory / f"failure.{stream}.log").mkdir()
        with self.assertRaises(subprocess.CalledProcessError) as caught:
            runner.recorded_output(self.directory, "failure", [sys.executable, "-c", "raise SystemExit(37)"], 3)
        self.assertEqual(caught.exception.returncode, 37)
        record = json.loads((self.directory / "failure.json").read_text())
        self.assertEqual([e["stage"] for e in record["secondaryErrors"]], ["capture stdout", "capture stderr"])
        self.assertEqual(record["status"], "failed")
        self.assertEqual(record["processExitAfterCleanup"], 37)
        outer = runner.Failures({})
        outer.add("outer operation", caught.exception)
        with self.assertRaises(subprocess.CalledProcessError) as wrapped:
            outer.raise_if_any()
        self.assertIs(wrapped.exception, caught.exception)
        nested = wrapped.exception.apple_quiet_errors["firstError"]["nestedErrors"]
        self.assertEqual(nested["firstError"]["stage"], "command")
        self.assertEqual([e["stage"] for e in nested["secondaryErrors"]], ["capture stdout", "capture stderr"])

    def test_evidence_only_failure_fails_successful_command(self):
        (self.directory / "ok.stdout.log").mkdir()
        with self.assertRaises(IsADirectoryError):
            runner.recorded_output(self.directory, "ok", [sys.executable, "-c", "print('ok')"], 3)
        record = json.loads((self.directory / "ok.json").read_text())
        self.assertEqual(record["exitCode"], 0)
        self.assertEqual(record["status"], "failed")

    def test_timeout_drains_real_child_even_when_every_final_sink_fails(self):
        child = self.directory / "pid"
        code = ("import os,time;from pathlib import Path;"
                f"Path({str(child)!r}).write_text(str(os.getpid()));"
                f"Path({str(self.directory / 'timeout.json.tmp')!r}).mkdir();"
                "time.sleep(30)")
        for stream in ("stdout", "stderr"):
            (self.directory / f"timeout.{stream}.log").mkdir()
        with self.assertRaises(subprocess.TimeoutExpired) as caught:
            runner.recorded_output(self.directory, "timeout", [sys.executable, "-c", code], 0.2)
        with self.assertRaises(ProcessLookupError):
            os.kill(int(child.read_text()), 0)
        record = caught.exception.apple_quiet_errors
        self.assertEqual([e["stage"] for e in record["secondaryErrors"]],
                         ["capture stdout", "capture stderr", "command receipt"])

    def test_main_closes_real_server_before_failing_receipt(self):
        destination = self.directory / "output"
        servers = []
        real_server = runner.ThreadingHTTPServer
        def create(*args, **kwargs):
            server = real_server(*args, **kwargs)
            servers.append(server)
            return server
        original = RuntimeError("original metadata failure")
        def fail_metadata(*_):
            (destination / "environment.json.tmp").mkdir()
            raise original
        args = ["run.py", "--platform", "macos", "--device", "macos", "--mode", "profile", "--output", str(destination)]
        with patch.object(sys, "argv", args), patch.object(runner.platform, "system", return_value="Darwin"), \
             patch.object(runner, "ThreadingHTTPServer", side_effect=create), \
             patch.object(runner, "output", side_effect=fail_metadata):
            with self.assertRaises(RuntimeError) as caught:
                runner.main()
        self.assertIs(caught.exception, original)
        self.assertEqual(servers[0].fileno(), -1)
        self.assertEqual(original.apple_quiet_errors["secondaryErrors"][0]["stage"], "environment receipt")

    def test_failed_owned_cleanup_does_not_skip_the_next_child(self):
        children = [subprocess.Popen([sys.executable, "-c", "import time;time.sleep(30)"], start_new_session=True) for _ in range(2)]
        for child in children:
            self.addCleanup(runner.stop_owned, child)
        first = RuntimeError("original operation")
        failures = runner.Failures({})
        failures.add("operation", first)
        def first_cleanup():
            runner.stop_owned(children[0])
            (self.directory / "missing" / "receipt").write_text("fail")
        failures.attempt("first owned cleanup", first_cleanup)
        failures.attempt("second owned cleanup", lambda: runner.stop_owned(children[1]))
        with self.assertRaises(RuntimeError) as caught:
            failures.raise_if_any()
        self.assertIs(caught.exception, first)
        self.assertTrue(all(child.poll() is not None for child in children))

    def controller(self):
        helper = self.directory / "helper"
        helper.write_text("#!" + sys.executable + "\nimport sys\nfor line in sys.stdin: print('broken',flush=True)\n")
        helper.chmod(0o700)
        session = runner.MacApplicationSession(helper, 42, self.directory, "io")
        self.addCleanup(session.close)
        return session

    def test_mac_reply_error_survives_real_evidence_failure(self):
        session = self.controller()
        (self.directory / "mac-io-controller-01.stdout.log").mkdir()
        with self.assertRaises(json.JSONDecodeError) as caught:
            session.request("info")
        self.assertEqual(caught.exception.apple_quiet_errors["secondaryErrors"][0]["stage"], "controller reply evidence")
        session.close()
        self.assertIsNotNone(session.process.poll())
        self.assertTrue(session.process.stdin.closed and session.process.stdout.closed and session.stderr.closed)

    def test_mac_close_storage_error_still_reaps_and_closes_streams(self):
        session = self.controller()
        (self.directory / "mac-io-controller.json.tmp").mkdir()
        with self.assertRaises(IsADirectoryError):
            session.close()
        self.assertIsNotNone(session.process.poll())
        self.assertTrue(session.process.stdin.closed and session.process.stdout.closed and session.stderr.closed)
        session.close()  # Idempotent; cleanup does not create another error.

    def test_cancelled_quiet_drains_its_real_owned_controller(self):
        session = self.controller()
        coordinator = runner.Coordinator(self.directory, "run-A", "token", "macos", 6)
        ready = threading.Event()
        def info(_):
            ready.set()
            return {"executable": "/fixture"}
        session.request = info
        body = {"runId": "run-A", "hostPid": 42, "appBootToken": "boot-A", "platform": "macos",
                "phase": "visible", "seconds": 6, "action": "quiet"}
        reply, work = coordinator.request("arm", body, runner.now_ms())
        (self.directory / "driver-visible.json.tmp").mkdir()
        with patch.object(runner, "MacApplicationSession", return_value=session), \
             patch.object(runner, "host_sample", return_value={"status": "unavailable"}):
            coordinator.start_job(work)
            self.assertTrue(ready.wait(2))
            coordinator.stop_jobs()
        self.assertTrue(all(not thread.is_alive() for thread in coordinator.workers))
        self.assertIsNotNone(session.process.poll())
        self.assertEqual(coordinator.jobs[reply["jobId"]]["status"], "failed")
        self.assertNotIn("quietEndMs", coordinator.jobs[reply["jobId"]])
        error = coordinator.background_failures[0]
        self.assertEqual(error.apple_quiet_errors["secondaryErrors"][0]["stage"], "quiet job receipt")


class NativeSourceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.repo = self.directory / "app"
        self.native = self.directory / "native"
        for path in (self.repo, self.native):
            path.mkdir()
            self.git(path, "init", "-q")
        for name in runner.NATIVE_PACKAGES:
            path = self.native / name
            path.mkdir()
            (path / "source").write_text(name)
        self.commit(self.native)
        self.ref = self.git(self.native, "rev-parse", "HEAD")
        self.write_lock()
        config = self.repo / ".dart_tool/package_config.json"
        config.parent.mkdir()
        config.write_text(json.dumps({"packages": [{"name": name, "rootUri": (self.native / name).as_uri()}
                                                   for name in sorted(runner.NATIVE_PACKAGES)]}))
        (self.repo / ".gitignore").write_text(".dart_tool/\n")
        self.commit(self.repo)

    def git(self, path, *args):
        return subprocess.check_output(["git", "-C", str(path), *args], stderr=subprocess.STDOUT, text=True).strip()

    def commit(self, path):
        self.git(path, "add", ".")
        env = {**os.environ, "GIT_AUTHOR_NAME": "Y-PLONI", "GIT_AUTHOR_EMAIL": "7353755@gmail.com",
               "GIT_COMMITTER_NAME": "Y-PLONI", "GIT_COMMITTER_EMAIL": "7353755@gmail.com"}
        subprocess.run(["git", "-C", str(path), "commit", "-qm", "owned source control"], env=env, check=True)

    def write_lock(self):
        (self.repo / "pubspec.yaml").write_text("name: source_control\n")
        (self.repo / "pubspec.lock").write_text("packages:\n" + "".join(
            f'  {name}:\n    description:\n      path: {name}\n      ref: "{self.ref}"\n'
            f'      resolved-ref: "{self.ref}"\n      url: "https://github.com/Otzaria/flutter_inappwebview"\n'
            '    source: git\n    version: "1.0.0"\n' for name in sorted(runner.NATIVE_PACKAGES)) + "sdks:\n  dart: any\n")

    def test_all_eight_packages_are_bound_to_real_committed_git_source(self):
        source = runner.native_source(self.repo)
        self.assertEqual(source["nativeFork"], self.ref)
        self.assertEqual(len(source["packages"]), 8)
        self.assertEqual(len(source["roots"]), 1)
        self.assertEqual(runner.verify_native_source(source, self.repo), source)

    def test_uncommitted_lock_is_rejected(self):
        lock = self.repo / "pubspec.lock"
        lock.write_text(lock.read_text() + "# changed\n")
        with self.assertRaisesRegex(ValueError, "committed"):
            runner.native_source(self.repo)

    def test_stale_resolved_checkout_is_rejected(self):
        (self.native / "flutter_inappwebview/source").write_text("changed revision")
        self.commit(self.native)
        with self.assertRaisesRegex(ValueError, "does not match"):
            runner.native_source(self.repo)

    def test_mixed_committed_pin_is_rejected(self):
        lock = self.repo / "pubspec.lock"
        lock.write_text(lock.read_text().replace(f'ref: "{self.ref}"', 'ref: "' + "a" * 40 + '"', 1))
        self.commit(self.repo)
        with self.assertRaisesRegex(ValueError, "Invalid native pin"):
            runner.native_source(self.repo)

    def test_two_individually_valid_native_revisions_cannot_be_mixed(self):
        second = self.directory / "other-native"
        self.git(self.directory, "clone", "-q", str(self.native), str(second))
        (second / "flutter_inappwebview/source").write_text("second valid revision")
        self.commit(second)
        ref = self.git(second, "rev-parse", "HEAD")
        lock = self.repo / "pubspec.lock"
        lock.write_text(lock.read_text().replace(self.ref, ref, 2))
        self.commit(self.repo)
        config = self.repo / ".dart_tool/package_config.json"
        value = json.loads(config.read_text())
        value["packages"][0]["rootUri"] = (second / value["packages"][0]["name"]).as_uri()
        config.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, "Mixed native Git pins"):
            runner.native_source(self.repo)

    def test_post_run_source_mutation_is_rejected(self):
        source = runner.native_source(self.repo)
        (self.native / "flutter_inappwebview_ios/source").write_text("modified")
        with self.assertRaisesRegex(ValueError, "Modified native"):
            runner.verify_native_source(source, self.repo)

    def test_relocated_or_duplicate_resolved_package_is_rejected(self):
        config = self.repo / ".dart_tool/package_config.json"
        original = json.loads(config.read_text())
        duplicate = {"packages": original["packages"] + [original["packages"][0]]}
        config.write_text(json.dumps(duplicate))
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            runner.native_source(self.repo)
        original["packages"][0]["rootUri"] = (self.native / "flutter_inappwebview_windows").as_uri()
        config.write_text(json.dumps(original))
        with self.assertRaisesRegex(ValueError, "does not match"):
            runner.native_source(self.repo)

    def test_changed_app_source_survives_status_and_diff_sink_failures(self):
        expected = {"commit": self.git(self.repo, "rev-parse", "HEAD"),
                    "tree": self.git(self.repo, "rev-parse", "HEAD^{tree}")}
        (self.repo / "pubspec.yaml").write_text("name: unexpected_source_change\n")
        (self.directory / "source-after.json.tmp").mkdir()
        (self.directory / "source-after-diff.stdout.log").mkdir()
        with patch.object(runner, "REPO", self.repo):
            with self.assertRaisesRegex(ValueError, "exact clean prebuild commit") as caught:
                runner.verify_app_source(self.directory, expected, "after")
        errors = caught.exception.apple_quiet_errors
        self.assertEqual(errors["firstError"]["stage"], "verify app source")
        self.assertEqual([item["stage"] for item in errors["secondaryErrors"]],
                         ["source status receipt", "source diff evidence"])
        nested = errors["secondaryErrors"][1]["nestedErrors"]
        self.assertEqual(nested["firstError"]["stage"], "capture stdout")
        self.assertEqual((self.repo / "pubspec.yaml").read_text(), "name: unexpected_source_change\n")

    def test_bundle_is_exact_simulator_target_with_run_specific_defines(self):
        bundle = self.directory / "Runner.app"
        bundle.mkdir()
        info = {"CFBundleIdentifier": "com.mendelg.otzaria", "CFBundleExecutable": "Runner",
                "CFBundleSupportedPlatforms": ["iPhoneSimulator"], "DTPlatformName": "iphonesimulator"}
        (bundle / "Info.plist").write_bytes(plistlib.dumps(info))
        (bundle / "Runner").write_bytes(b"test only: not an application")
        defines = self.directory / "defines.json"
        defines.write_text('{"run":"one"}')
        before = runner.simulator_bundle(bundle, defines)
        defines.write_text('{"run":"two"}')
        self.assertNotEqual(runner.simulator_bundle(bundle, defines), before)
        info["CFBundleSupportedPlatforms"] = ["iPhoneOS"]
        (bundle / "Info.plist").write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "Simulator"):
            runner.simulator_bundle(bundle, defines)


class ControllerLifetimeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.coordinator = runner.Coordinator(self.directory, "run-A", "nonce", "ios", 6)
        self.body = {"runId": "run-A", "hostPid": 42, "appBootToken": "boot-A", "platform": "ios",
                     "phase": "visible", "seconds": 6, "action": "quiet"}
        self.child = subprocess.Popen([sys.executable, "-c", "import time;time.sleep(30)"], start_new_session=True)
        self.addCleanup(runner.stop_owned, self.child)
        self.coordinator.control_process = self.child
        self.identity = {"runId": "run-A", "controllerPid": self.child.pid, "controllerBootToken": "live-control"}
        reply, _ = self.coordinator.request("control-ready", self.identity, runner.now_ms())
        self.identity.update(reply)

    def test_ready_event_cannot_authorize_a_dead_real_process(self):
        runner.stop_owned(self.child)
        self.assertTrue(self.coordinator.control_ready.is_set())
        with self.assertRaisesRegex(ValueError, "no longer alive"):
            self.coordinator.request("arm", self.body, runner.now_ms())
        self.assertFalse(self.coordinator.jobs)

    def fresh_arm(self):
        result, failures = [], []
        def arm():
            try:
                result.append(self.coordinator.request("arm", self.body, runner.now_ms()))
            except BaseException as error:
                failures.append(error)
        thread = threading.Thread(target=arm)
        thread.start()
        deadline = time.monotonic() + 2
        command = {}
        while "armChallenge" not in command and time.monotonic() < deadline:
            command, _ = self.coordinator.request("control", self.identity, runner.now_ms())
            time.sleep(0.01)  # Before arm completes; never inside quiet.
        self.assertIn("armChallenge", command)
        ack = {**self.identity, "jobId": command["jobId"], "challenge": command["armChallenge"]}
        self.coordinator.request("control-arm", ack, runner.now_ms())
        thread.join(2)
        self.assertFalse(thread.is_alive())
        self.assertFalse(failures, failures)
        return result[0], ack

    def test_fresh_challenge_binds_each_arm_and_rejects_replay(self):
        (reply, _), ack = self.fresh_arm()
        job = self.coordinator.jobs[reply["jobId"]]
        self.assertEqual(job["controlArm"]["controllerPid"], self.child.pid)
        self.assertEqual(job["controlArm"]["challenge"], ack["challenge"])
        with self.assertRaisesRegex(ValueError, "Stale or duplicate"):
            self.coordinator.request("control-arm", ack, runner.now_ms())
        with self.assertRaisesRegex(ValueError, "Stale or foreign"):
            self.coordinator.request("control", {**self.identity, "controllerBootToken": "replacement"}, runner.now_ms())

    def test_no_fresh_ack_is_bounded_and_cannot_start_quiet(self):
        with patch.object(self.coordinator.arm_acknowledged, "wait", return_value=False):
            with self.assertRaisesRegex(TimeoutError, "No fresh"):
                self.coordinator.request("arm", self.body, runner.now_ms())
        self.assertIsNone(self.coordinator.control_job)
        self.assertEqual(next(iter(self.coordinator.jobs.values()))["status"], "failed")

    def test_result_requires_same_arm_and_one_terminal_response(self):
        (reply, _), ack = self.fresh_arm()
        with self.assertRaisesRegex(ValueError, "Unexpected"):
            self.coordinator.request("control-result", ack, runner.now_ms())
        self.coordinator.control_job = self.coordinator.jobs[reply["jobId"]]
        self.coordinator.request("control", self.identity, runner.now_ms())
        with self.assertRaisesRegex(ValueError, "Unexpected"):
            self.coordinator.request("control-result", {**ack, "challenge": "stale"}, runner.now_ms())
        self.coordinator.request("control-result", {**ack, "status": "failed", "error": "owned control"}, runner.now_ms())
        with self.assertRaisesRegex(ValueError, "duplicate"):
            self.coordinator.request("control-result", ack, runner.now_ms())
        self.assertTrue(self.coordinator.control_result.is_set())
        self.assertLess(self.coordinator.jobs[reply["jobId"]]["completionDeadlineMonotonic"], time.monotonic() + reply["waitMs"] / 1000)

    def test_cancellation_before_dispatch_does_not_lose_its_wakeup(self):
        (reply, work), _ = self.fresh_arm()
        def sample(*_):
            self.coordinator.stop_event.set()
            self.coordinator.control_result.set()
            return {"status": "unavailable"}
        with patch.object(runner, "host_sample", side_effect=sample), patch.object(runner.time, "sleep"):
            work()
        job = self.coordinator.jobs[reply["jobId"]]
        self.assertEqual(job["status"], "failed")
        self.assertIn("before dispatching", job["error"])
        self.assertIsNone(self.coordinator.control_job)

    def test_app_report_cannot_claim_stale_or_mixed_native_identity(self):
        self.coordinator.native_source = {"nativeFork": "a" * 40, "lockSha256": "b" * 64}
        for fields in ({}, {"nativeFork": "c" * 40, "lockSha256": "b" * 64},
                       {"nativeFork": "a" * 40, "lockSha256": "d" * 64}):
            with self.assertRaisesRegex(ValueError, "verified native"):
                self.coordinator.request("checkpoint", {**self.body, **fields}, runner.now_ms())
        self.assertFalse((self.directory / "partial-app.json").exists())


if __name__ == "__main__":
    unittest.main()
