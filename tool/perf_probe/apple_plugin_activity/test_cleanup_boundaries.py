"""Real I/O and owned-process regression controls; no Apple acceptance claims."""
import contextlib
import errno
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
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("apple_cleanup_boundaries", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class BadDescriptorClose:
    """Preserve real I/O until close, then produce a real OS EBADF."""
    def __init__(self, stream):
        self.stream = stream
        self.attempts = 0

    def __getattr__(self, name):
        return getattr(self.stream, name)

    def close(self):
        self.attempts += 1
        os.close(self.stream.fileno())
        self.stream.close()


def live(pid):
    if sys.platform.startswith("linux"):
        try:
            state = Path("/proc", str(pid), "stat").read_text().rsplit(")", 1)[1].split()[0]
        except FileNotFoundError:
            return False
    else:
        result = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "stat="],
                                text=True, capture_output=True, timeout=2)
        state = result.stdout.strip()
        if result.returncode not in {0, 1}:
            raise RuntimeError("Cannot inspect the test-owned process")
    return bool(state) and state[0] not in {"Z", "X"}


class CleanupBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="apple-cleanup-controls-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)

    def command(self, exit_code):
        return [sys.executable, "-c",
                "import sys;print('owned stdout',flush=True);"
                "print('owned stderr',file=sys.stderr,flush=True);"
                f"raise SystemExit({exit_code})"]

    def broken_streams(self):
        factory = tempfile.TemporaryFile
        streams = []
        def create(*args, **kwargs):
            stream = BadDescriptorClose(factory(*args, **kwargs))
            streams.append(stream)
            return stream
        return streams, patch.object(runner.tempfile, "TemporaryFile", side_effect=create)

    def test_real_closed_stderr_preserves_the_command_failure(self):
        with tempfile.TemporaryFile(mode="w+") as closed:
            closed.close()
            with contextlib.redirect_stderr(closed):
                with self.assertRaises(subprocess.CalledProcessError) as caught:
                    runner.recorded_output(self.directory, "closed-stderr", self.command(37), 5)
        self.assertEqual(caught.exception.returncode, 37)
        errors = caught.exception.apple_quiet_errors
        self.assertEqual(errors["firstError"]["stage"], "command")
        self.assertEqual(errors["secondaryErrors"][-1]["stage"], "diagnostic stderr")
        self.assertEqual(errors["secondaryErrors"][-1]["type"], "ValueError")

    def test_diagnostic_serialization_cannot_replace_the_first_error(self):
        first = RuntimeError("original operation")
        errors = runner.Failures({})
        errors.add("operation", first)
        errors.record["firstError"]["unserializableEvidence"] = object()
        with self.assertRaises(RuntimeError) as caught:
            errors.raise_if_any()
        self.assertIs(caught.exception, first)
        self.assertEqual(errors.record["secondaryErrors"][-1]["stage"], "diagnostic stderr")
        self.assertEqual(errors.record["secondaryErrors"][-1]["type"], "TypeError")

    def test_both_real_stream_close_errors_remain_secondary_to_exit_37(self):
        streams, fault = self.broken_streams()
        with fault:
            with self.assertRaises(subprocess.CalledProcessError) as caught:
                runner.recorded_output(self.directory, "failed", self.command(37), 5)
        self.assertEqual(caught.exception.returncode, 37)
        record = json.loads((self.directory / "failed.json").read_text())
        self.assertEqual(record["exitCode"], 37)
        self.assertEqual(record["processExitAfterCleanup"], 37)
        self.assertEqual([e["stage"] for e in record["secondaryErrors"]], ["close stdout", "close stderr"])
        self.assertTrue(record["ownedGroupCleanup"]["groupDrained"])
        self.assertEqual((self.directory / "failed.stdout.log").read_text(), "owned stdout\n")
        self.assertEqual((self.directory / "failed.stderr.log").read_text(), "owned stderr\n")
        self.assertEqual([s.attempts for s in streams], [1, 1])
        self.assertTrue(all(s.closed for s in streams))

    def test_a_real_close_error_fails_a_successful_command(self):
        streams, fault = self.broken_streams()
        with fault:
            with self.assertRaises(OSError) as caught:
                runner.recorded_output(self.directory, "zero", self.command(0), 5)
        self.assertEqual(caught.exception.errno, errno.EBADF)
        record = json.loads((self.directory / "zero.json").read_text())
        self.assertEqual(record["exitCode"], 0)
        self.assertEqual(record["status"], "failed")
        self.assertEqual(record["firstError"]["stage"], "close stdout")
        self.assertEqual(record["secondaryErrors"][0]["stage"], "close stderr")
        self.assertEqual([s.attempts for s in streams], [1, 1])

    def test_success_returns_the_captured_stdout_after_both_streams_close(self):
        factory = tempfile.TemporaryFile
        streams = []
        def create(*args, **kwargs):
            stream = factory(*args, **kwargs)
            streams.append(stream)
            return stream
        with patch.object(runner.tempfile, "TemporaryFile", side_effect=create):
            result = runner.recorded_output(self.directory, "positive", self.command(0), 5)
        self.assertEqual(result, "owned stdout")
        self.assertTrue(all(s.closed for s in streams))
        self.assertEqual(json.loads((self.directory / "positive.json").read_text())["status"], "passed")

    def group_case(self, *, ignore_term, timeout):
        ready = self.directory / "child.json"
        child_code = (
            "import json,os,signal,sys,time\n"
            + ("signal.signal(signal.SIGTERM,signal.SIG_IGN)\n" if ignore_term else "")
            + "from pathlib import Path\n"
              "ready=Path(sys.argv[1]);temporary=Path(sys.argv[1]+'.tmp')\n"
              "temporary.write_text(json.dumps({'pid':os.getpid(),'pgid':os.getpgrp()}));temporary.replace(ready)\n"
              "time.sleep(60)\n")
        parent_code = (
            "import pathlib,subprocess,sys,time\n"
            "subprocess.Popen([sys.executable,'-c',sys.argv[1],sys.argv[2]])\n"
            "deadline=time.monotonic()+5\n"
            "while not pathlib.Path(sys.argv[2]).exists():\n"
            " if time.monotonic()>deadline: raise RuntimeError('owned child readiness timeout')\n"
            " time.sleep(.01)\n"
            + ("time.sleep(60)\n" if timeout else "raise SystemExit(37)\n"))
        factory = subprocess.Popen
        owned = []
        def spawn(*args, **kwargs):
            process = factory(*args, **kwargs)
            if kwargs.get("start_new_session") is True:
                owned.append(process)
            return process
        sentinel = factory([sys.executable, "-c", "import time;time.sleep(60)"], start_new_session=True)
        child = None
        started = time.monotonic()
        try:
            with patch.object(runner.subprocess, "Popen", side_effect=spawn):
                kind = subprocess.TimeoutExpired if timeout else subprocess.CalledProcessError
                with self.assertRaises(kind) as caught:
                    runner.recorded_output(self.directory, "group",
                        [sys.executable, "-c", parent_code, child_code, str(ready)], 2 if timeout else 10)
            self.assertEqual(len(owned), 1)
            child = json.loads(ready.read_text())
            self.assertEqual(child["pgid"], owned[0].pid)
            self.assertFalse(live(child["pid"]), "An owned descendant survived cleanup")
            self.assertIsNotNone(owned[0].poll())
            self.assertIsNone(sentinel.poll(), "Cleanup affected the independent control group")
            record = json.loads((self.directory / "group.json").read_text())
            self.assertTrue(record["ownedGroupCleanup"]["groupDrained"])
            self.assertEqual(record["ownedGroupCleanup"]["remainingLivePids"], [])
            if ignore_term:
                self.assertIn("SIGKILL", record["ownedGroupCleanup"]["signals"])
            if not timeout:
                self.assertEqual(caught.exception.returncode, 37)
                self.assertEqual(record["processExitAfterCleanup"], 37)
            self.assertLess(time.monotonic() - started, 28)
            # The same Popen can be cleaned twice without signaling a stale ID.
            with patch.object(runner.os, "killpg", side_effect=AssertionError("Repeated cleanup signaled a group")):
                runner.stop_owned(owned[0])
        finally:
            if child is None and ready.exists():
                child = json.loads(ready.read_text())
            for process in owned:
                child_live = child is not None and child["pgid"] == process.pid and live(child["pid"])
                if process.poll() is None or child_live:
                    if child_live and os.getpgid(child["pid"]) != process.pid:
                        raise RuntimeError("Test child left its recorded owned group")
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                process.wait(timeout=5)
            if sentinel.poll() is None:
                os.killpg(sentinel.pid, signal.SIGKILL)
            sentinel.wait(timeout=5)
            if child is not None:
                deadline = time.monotonic() + 5
                while live(child["pid"]) and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertFalse(live(child["pid"]), "The test failed to drain its own descendant")

    def test_exited_leader_does_not_leave_its_real_descendant(self):
        self.group_case(ignore_term=False, timeout=False)

    def test_exited_leader_does_not_leave_a_descendant_ignoring_term(self):
        self.group_case(ignore_term=True, timeout=False)

    def test_timeout_and_leader_exit_on_term_still_drain_an_ignoring_child(self):
        self.group_case(ignore_term=True, timeout=True)

    def test_cleanup_refuses_a_child_in_the_callers_group(self):
        process = subprocess.Popen([sys.executable, "-c", "import time;time.sleep(60)"])
        try:
            self.assertEqual(os.getpgid(process.pid), os.getpgrp())
            with self.assertRaisesRegex(ValueError, "recorded process group"):
                runner.stop_owned(process)
            self.assertIsNone(process.poll())
        finally:
            process.kill()  # Exactly this directly owned test child, never its shared group.
            process.wait(timeout=5)

    def main_log_case(self, target, exit_code):
        # Only build/device metadata is substituted. The HTTP server, commands,
        # log descriptors, command exit and cleanup are real. No Apple result.
        directory = self.directory / f"{target}-{exit_code}"
        repo = self.directory / f"repo-{target}-{exit_code}"
        entitlements = repo / "macos/Runner/DebugProfile.entitlements"
        entitlements.parent.mkdir(parents=True)
        entitlements.write_text("<plist/>")
        mode = "profile" if target == "macos" else "debug"
        source = {"nativeFork": "a" * 40, "lockSha256": "b" * 64}
        prebuild = {"path": str(repo / "Runner.app"), "executableName": "Runner", "files": {"Runner": "c" * 64}}
        real_open, real_popen = Path.open, subprocess.Popen
        real_coordinator, real_server = runner.Coordinator, runner.ThreadingHTTPServer
        logs, processes, servers = {}, [], []

        def open_file(path, *args, **kwargs):
            stream = real_open(path, *args, **kwargs)
            if path.name in {"flutter-drive.log", "xcode-control.log"} and args and args[0] == "w":
                stream = BadDescriptorClose(stream)
                logs[path.name] = stream
            return stream

        def spawn(command, *args, **kwargs):
            if command[0] == "flutter":
                command = [sys.executable, "-c", f"print('real app command',flush=True);raise SystemExit({exit_code})"]
            elif command[0] == "xcodebuild":
                command = [sys.executable, "-c", "import time;print('real control command',flush=True);time.sleep(60)"]
            process = real_popen(command, *args, **kwargs)
            if kwargs.get("start_new_session") is True:
                processes.append(process)
            return process

        def coordinator(*args, **kwargs):
            value = real_coordinator(*args, **kwargs)
            value.completed.set()
            value.control_ready.set()
            (directory / "complete.json").write_text(json.dumps({"status": "passed", "buildMode": mode}))
            return value

        def server(*args, **kwargs):
            value = real_server(*args, **kwargs)
            servers.append(value)
            return value

        def metadata(command, *_):
            if command[:2] == ["git", "status"]:
                return ""
            if command[0] == "git":
                return "d" * 40
            if command[0] == "flutter":
                return json.dumps({"frameworkVersion": "metadata-only"})
            if command[:2] == ["xcrun", "simctl"]:
                return json.dumps({"devices": {"test": [{"udid": "owned-test-device", "state": "Booted"}]}})
            return "metadata-only"

        args = ["run.py", "--platform", target, "--mode", mode,
                "--device", "macos" if target == "macos" else "owned-test-device", "--output", str(directory)]
        caught = None
        try:
            with contextlib.ExitStack() as stack:
                for context in (
                    patch.object(sys, "argv", args),
                    patch.object(runner.platform, "system", return_value="Darwin"),
                    patch.object(runner, "REPO", repo),
                    patch.object(runner, "output", side_effect=metadata),
                    patch.object(runner, "native_source", return_value=source),
                    patch.object(runner, "verify_native_source", return_value=source),
                    patch.object(runner, "verify_app_source", return_value={}),
                    patch.object(runner, "prebuild_simulator", return_value=prebuild),
                    patch.object(runner, "simulator_bundle", return_value=prebuild),
                    patch.object(runner, "prepare_control", return_value=directory / "control"),
                    patch.object(runner, "recorded_output", return_value=""),
                    patch.object(runner, "Coordinator", side_effect=coordinator),
                    patch.object(runner, "ThreadingHTTPServer", side_effect=server),
                    patch.object(runner.subprocess, "Popen", side_effect=spawn),
                    patch.object(Path, "open", new=open_file),
                ):
                    stack.enter_context(context)
                try:
                    runner.main()
                except BaseException as error:
                    caught = error
            self.assertIsNotNone(caught, "A real log close error must fail main")
            record = json.loads((directory / "environment.json").read_text())
            self.assertEqual(record["appExitCode"], exit_code)
            self.assertEqual(record["status"], "failed")
            stages = [record["firstError"]["stage"]] + [e["stage"] for e in record.get("secondaryErrors", [])]
            self.assertIn("close app log", stages)
            if target == "ios":
                self.assertIn("close iOS control log", stages)
                self.assertLess(stages.index("close app log"), stages.index("close iOS control log"))
            if exit_code:
                self.assertIsInstance(caught, RuntimeError)
                self.assertIn(f"exit {exit_code}", str(caught))
                self.assertEqual(record["firstError"]["stage"], "run")
            else:
                self.assertIsInstance(caught, OSError)
                self.assertEqual(caught.errno, errno.EBADF)
                self.assertEqual(record["firstError"]["stage"], "close app log")
            self.assertTrue(all(p.poll() is not None for p in processes))
            self.assertTrue(all(p.apple_quiet_group_drained for p in processes))
            self.assertTrue(all(stream.closed and stream.attempts == 1 for stream in logs.values()))
            self.assertTrue(all(s.fileno() == -1 for s in servers))
        finally:
            for process in processes:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
            for server in servers:
                if server.fileno() != -1:
                    server.shutdown()
                    server.server_close()

    def test_main_nonzero_exit_precedes_both_real_log_close_errors(self):
        for target in ("macos", "ios"):
            with self.subTest(platform=target):
                self.main_log_case(target, 37)

    def test_main_log_close_alone_fails_a_zero_exit(self):
        self.main_log_case("macos", 0)


if __name__ == "__main__":
    unittest.main()
