"""Owned-process permission and zombie controls; no app or quiet acceptance."""
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

SPEC = importlib.util.spec_from_file_location("apple_group_permissions", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


def group_rows(pgid):
    output = subprocess.check_output(
        ["/bin/ps", "-A", "-o", "pid=", "-o", "pgid=", "-o", "stat="],
        text=True, timeout=2)
    rows = []
    for line in output.splitlines():
        fields = line.split()
        if len(fields) != 3:
            raise ValueError("Malformed owned-group test observation")
        if int(fields[1]) == pgid:
            rows.append({"pid": int(fields[0]), "pgid": int(fields[1]), "state": fields[2]})
    return rows


def live_rows(rows):
    return [row for row in rows if row["state"][0] not in {"Z", "X"}]


@unittest.skipUnless(os.name == "posix", "Requires real POSIX process groups")
class OwnedGroupPermissionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="apple-owned-group-controls-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.children = []
        self.addCleanup(self.finish_children)

    def finish_children(self):
        for process in self.children:
            if process.poll() is None:
                self.assertEqual(os.getpgid(process.pid), process.pid)
                process.kill()  # This exact direct child, never a shared or foreign group.
            process.wait(timeout=5)
            self.assertFalse(live_rows(group_rows(process.pid)))

    def record(self, value):
        value = {"test": self._testMethodName, "platform": sys.platform,
                 "scope": "Real owned child and explicit syscall-fault control, not app acceptance",
                 **value}
        requested = os.environ.get("APPLE_CLEANUP_CONTROL_OUTPUT")
        if requested:
            directory = Path(requested)
            directory.mkdir(parents=True, exist_ok=True)
            (directory / (self._testMethodName + ".json")).write_text(
                json.dumps(value, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(value, sort_keys=True), flush=True)

    def child(self, *, exit_ready=False):
        ready = self.directory / ("ready-" + str(len(self.children)) + ".json")
        code = (
            "import json,os,pathlib,sys,time\n"
            "ready=pathlib.Path(sys.argv[1]);tmp=pathlib.Path(sys.argv[1]+'.tmp')\n"
            "tmp.write_text(json.dumps({'pid':os.getpid(),'pgid':os.getpgrp()}));tmp.replace(ready)\n"
            + ("raise SystemExit(37)\n" if exit_ready else "time.sleep(60)\n"))
        process = subprocess.Popen([sys.executable, "-c", code, str(ready)],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True)
        self.children.append(process)
        deadline = time.monotonic() + 5
        while not ready.exists():
            if time.monotonic() >= deadline:
                self.fail("The real owned child did not report readiness")
            time.sleep(.01)  # Do not poll/reap a child needed for the zombie control.
        identity = json.loads(ready.read_text())
        self.assertEqual(identity, {"pid": process.pid, "pgid": process.pid})
        self.assertNotEqual(process.pid, os.getpgrp())
        return process

    def wait_for_zombie(self, process):
        deadline = time.monotonic() + 5
        while True:
            rows = group_rows(process.pid)
            self.assertTrue(all(row["pid"] == process.pid for row in rows))
            if rows and not live_rows(rows):
                return rows
            if time.monotonic() >= deadline:
                self.fail("The un-reaped owned child did not become a zombie")
            time.sleep(.01)

    def test_reaped_group_never_receives_a_signal(self):
        process = self.child(exit_ready=True)
        self.assertEqual(process.wait(timeout=5), 37)
        self.assertEqual(group_rows(process.pid), [])
        with patch.object(runner.os, "killpg", side_effect=AssertionError("A reaped group was signalled")):
            runner.stop_owned(process)
        self.assertTrue(process.apple_quiet_group_drained)
        self.assertEqual(process.apple_quiet_cleanup["signals"], [])
        self.assertEqual(process.apple_quiet_cleanup["status"], "passed")
        self.record({"pid": process.pid, "cleanup": process.apple_quiet_cleanup})

    @unittest.skipUnless(sys.platform == "darwin", "Requires the actual Darwin zombie syscall semantics")
    def test_darwin_zombie_membership_does_not_require_signal_permission(self):
        process = self.child(exit_ready=True)
        rows = self.wait_for_zombie(process)
        probe = {}
        try:
            os.killpg(process.pid, 0)
            probe["returned"] = True
        except OSError as error:
            probe.update(type=type(error).__name__, errno=error.errno, error=str(error))
            self.assertIn(error.errno, {errno.EPERM, errno.ESRCH})
        self.assertIsNone(process.returncode, "The zombie must still await our Popen.wait")
        with patch.object(runner.os, "killpg", side_effect=AssertionError("Dead membership needs no signal")):
            self.assertEqual(runner._live_owned_group(process.pid, 1), [])
            runner.stop_owned(process)
        self.assertEqual(process.returncode, 37)
        self.assertEqual(process.apple_quiet_cleanup["status"], "passed")
        self.assertTrue(process.apple_quiet_cleanup["groupDrained"])
        self.assertEqual(process.apple_quiet_cleanup["signals"], [])
        self.assertEqual(group_rows(process.pid), [])
        self.record({"pid": process.pid, "unreapedRows": rows, "rawKillpgZero": probe,
                     "cleanup": process.apple_quiet_cleanup})

    def test_real_live_group_terminates_and_cleanup_is_idempotent(self):
        process = self.child()
        before = group_rows(process.pid)
        self.assertEqual([row["pid"] for row in live_rows(before)], [process.pid])
        runner.stop_owned(process)
        self.assertEqual(process.returncode, -signal.SIGTERM)
        self.assertEqual(process.apple_quiet_cleanup["signals"], ["SIGTERM"])
        self.assertEqual(process.apple_quiet_cleanup["status"], "passed")
        with patch.object(runner.os, "killpg", side_effect=AssertionError("Repeated cleanup signalled a stale ID")):
            runner.stop_owned(process)
        self.record({"pid": process.pid, "liveBefore": before, "cleanup": process.apple_quiet_cleanup})

    def test_member_exit_racing_eperm_requires_fresh_dead_membership(self):
        process = self.child()
        real_killpg = os.killpg
        denied = PermissionError(errno.EPERM, "controlled signal race after owned child exit")
        observations = []
        def signal_group(pgid, sig):
            self.assertEqual(pgid, process.pid)
            if sig == signal.SIGTERM:
                before = group_rows(pgid)
                self.assertEqual([row["pid"] for row in live_rows(before)], [process.pid])
                real_killpg(pgid, signal.SIGKILL)
                dead = self.wait_for_zombie(process)
                observations.append({"liveBefore": before, "deadAtDenial": dead})
                raise denied
            return real_killpg(pgid, sig)
        with patch.object(runner.os, "killpg", side_effect=signal_group):
            runner.stop_owned(process)
        self.assertEqual(len(observations), 1)
        self.assertEqual(process.returncode, -signal.SIGKILL)
        record = process.apple_quiet_cleanup
        self.assertEqual(record["status"], "passed")
        self.assertTrue(record["groupDrained"])
        self.assertNotIn("firstError", record)
        self.assertEqual(record["signalRaces"], [{
            "signal": "SIGTERM", "errno": errno.EPERM,
            "livePidsBefore": [process.pid], "livePidsAfter": [],
            "resolution": "no live group members after denied signal",
        }])
        self.record({"pid": process.pid, "controlledFault": str(denied),
                     "observations": observations, "cleanup": record})

    def denied_live_group(self, *, fail_observation):
        process = self.child()
        real_killpg, real_output = os.killpg, subprocess.check_output
        denied = PermissionError(errno.EPERM, "controlled permission denial while owned member is alive")
        state = {"denied": False, "observationFailed": False}
        observations = []
        def signal_group(pgid, sig):
            self.assertEqual(pgid, process.pid)
            if sig == signal.SIGTERM:
                before = group_rows(pgid)
                self.assertEqual([row["pid"] for row in live_rows(before)], [process.pid])
                observations.append(before)
                state["denied"] = True
                raise denied
            return real_killpg(pgid, sig)
        def observe(command, *args, **kwargs):
            if fail_observation and state["denied"] and not state["observationFailed"]:
                state["observationFailed"] = True
                # Produce a real OS error while retaining the signal failure as first.
                return real_output([str(self.directory / "missing-ps")], text=True, timeout=1)
            return real_output(command, *args, **kwargs)
        started = time.monotonic()
        with patch.object(runner.os, "killpg", side_effect=signal_group), \
             patch.object(runner.subprocess, "check_output", side_effect=observe):
            with self.assertRaises(PermissionError) as caught:
                runner.stop_owned(process)
        elapsed = time.monotonic() - started
        self.assertIs(caught.exception, denied)
        self.assertEqual(len(observations), 1)
        self.assertEqual(process.returncode, -signal.SIGKILL)
        record = process.apple_quiet_cleanup
        self.assertEqual(record["status"], "failed")
        self.assertEqual(record["firstError"]["stage"], "signal owned group TERM")
        self.assertEqual(record["firstError"]["type"], "PermissionError")
        self.assertEqual(record["signals"], ["SIGKILL"])
        self.assertNotIn("signalRaces", record)
        self.assertTrue(record["groupDrained"], "A failed TERM must not skip the bounded KILL cleanup")
        self.assertEqual(record["remainingLivePids"], [])
        self.assertLess(elapsed, 25)
        nested = record["firstError"]["nestedErrors"]
        if fail_observation:
            self.assertTrue(state["observationFailed"])
            self.assertEqual(nested["secondaryErrors"][0]["stage"], "inspect group after denied signal")
            self.assertEqual(nested["secondaryErrors"][0]["type"], "FileNotFoundError")
        else:
            self.assertNotIn("secondaryErrors", nested)
        self.record({"pid": process.pid, "controlledSignalFault": str(denied),
                     "realMissingExecutableFault": fail_observation, "liveAtDenial": observations,
                     "elapsedSeconds": elapsed, "cleanup": record})

    def test_permission_denial_with_a_live_member_remains_a_failure(self):
        self.denied_live_group(fail_observation=False)

    def test_denied_signal_and_failed_membership_observation_keep_original_error(self):
        self.denied_live_group(fail_observation=True)


if __name__ == "__main__":
    unittest.main()
