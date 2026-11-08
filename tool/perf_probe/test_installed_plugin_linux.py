"""Process and evidence checks; these do not execute Flutter, WPE or X11."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

from run_installed_plugin_linux import (
    observe, require_fresh_reports, require_linux_result, run, run_owned,
)


class LinuxSessionTest(unittest.TestCase):
    def assert_process_stopped(self, pid):
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            status = Path(f"/proc/{pid}/stat")
            if not status.exists() or status.read_text().split(") ", 1)[1][0] == "Z":
                return
            time.sleep(0.02)
        self.fail("A process in the owned group survived cleanup")

    def test_command_failure_is_preserved(self):
        self.assertEqual(run_owned([sys.executable, "-c", "raise SystemExit(37)"],
                                   5, os.environ), 37)

    def test_timeout_terminates_only_the_owned_process_group(self):
        with tempfile.TemporaryDirectory() as name:
            pidfile = Path(name) / "child.pid"
            outsider = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"],
                                        start_new_session=True)
            child = (
                "import os, signal, time; "
                "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                f"open({str(pidfile)!r}, 'w').write(str(os.getpid())); time.sleep(30)"
            )
            parent = (
                "import subprocess, sys, time; "
                f"subprocess.Popen([sys.executable, '-c', {child!r}]); time.sleep(30)"
            )
            try:
                self.assertEqual(run_owned([sys.executable, "-c", parent], 1, os.environ), 124)
                self.assertIsNone(outsider.poll())
                owned_pid = int(pidfile.read_text())
                self.assert_process_stopped(owned_pid)
            finally:
                outsider.terminate()
                outsider.wait(timeout=5)

    def test_success_also_cleans_a_child_that_outlives_its_parent(self):
        with tempfile.TemporaryDirectory() as name:
            pidfile = Path(name) / "child.pid"
            child = "import signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)"
            parent = (
                "import subprocess, sys; "
                f"p = subprocess.Popen([sys.executable, '-c', {child!r}]); "
                f"open({str(pidfile)!r}, 'w').write(str(p.pid))"
            )
            try:
                self.assertEqual(run_owned([sys.executable, "-c", parent], 5, os.environ), 0)
                self.assert_process_stopped(int(pidfile.read_text()))
            finally:
                if pidfile.exists():
                    try:
                        os.kill(int(pidfile.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_interruption_cleans_the_owned_group_and_preserves_the_signal_exit(self):
        with tempfile.TemporaryDirectory() as name:
            pidfile = Path(name) / "child.pid"
            child = (
                "import os, signal, time; "
                "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                f"open({str(pidfile)!r}, 'w').write(str(os.getpid())); time.sleep(30)"
            )
            parent = (
                "import subprocess, sys, time; "
                f"subprocess.Popen([sys.executable, '-c', {child!r}]); time.sleep(30)"
            )
            wrapper = (
                "import os, signal, sys\n"
                "from run_installed_plugin_linux import Interrupted, interrupt, run_owned\n"
                "signal.signal(signal.SIGTERM, interrupt)\n"
                "try:\n"
                f"    code = run_owned([sys.executable, '-c', {parent!r}], 15, os.environ)\n"
                "except Interrupted as error:\n"
                "    code = 128 + error.signum\n"
                "sys.exit(code)\n"
            )
            outsider = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"],
                                        start_new_session=True)
            controller = subprocess.Popen([sys.executable, "-c", wrapper],
                                          cwd=Path(__file__).resolve().parent,
                                          start_new_session=True)
            try:
                deadline = time.monotonic() + 5
                while not pidfile.exists() and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue(pidfile.exists(), "Owned child did not start")
                controller.send_signal(signal.SIGTERM)
                self.assertEqual(controller.wait(timeout=5), 128 + signal.SIGTERM)
                self.assertIsNone(outsider.poll())
                self.assert_process_stopped(int(pidfile.read_text()))
            finally:
                if controller.poll() is None:
                    controller.kill()
                    controller.wait(timeout=5)
                if pidfile.exists():
                    try:
                        os.kill(int(pidfile.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                outsider.terminate()
                outsider.wait(timeout=5)

    def test_missing_tool_is_explicitly_unavailable(self):
        result = observe(["/missing-linux-probe-observation"])
        self.assertEqual(result["availability"], "unavailable")
        self.assertIn("reason", result)

    def test_report_root_must_be_absent_or_empty_without_removing_existing_evidence(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name) / "host reports"
            require_fresh_reports(root)
            self.assertFalse(root.exists())
            root.mkdir()
            require_fresh_reports(root)
            for index, filename in enumerate(("run-old/report.json", "partial.log")):
                with self.subTest(filename=filename):
                    host = Path(name) / f"host-{index}"
                    evidence = host / filename
                    evidence.parent.mkdir(parents=True, exist_ok=True)
                    evidence.write_bytes(b"previous evidence\n")
                    os.utime(evidence, (946684800, 946684800))
                    before = evidence.stat()
                    with self.assertRaisesRegex(RuntimeError, "absent or empty"):
                        require_fresh_reports(host)
                    self.assertEqual(evidence.read_bytes(), b"previous evidence\n")
                    self.assertEqual(evidence.stat().st_mtime_ns, before.st_mtime_ns)
            existing_file = Path(name) / "file instead of host"
            existing_file.write_text("existing evidence")
            with self.assertRaisesRegex(RuntimeError, "absent or empty"):
                require_fresh_reports(existing_file)
            self.assertEqual(existing_file.read_text(), "existing evidence")

    def test_failed_preflight_preserves_a_failed_partial_report(self):
        with tempfile.TemporaryDirectory() as name:
            output = Path(name) / "session"
            self.assertEqual(run(output, Path(name) / "missing-bundle/otzaria", 5), 1)
            report = json.loads((output / "session.json").read_text())
            self.assertEqual(report["status"], "failed")
            self.assertEqual(report["nativeRuntimeVersion"]["availability"], "unavailable")
            self.assertEqual(report["appGpuAndSoftwareRoute"]["availability"], "unavailable")
            self.assertNotIn("scenarioResult", report)
            self.assertIn("Missing bundled runtime", report["error"])
            with self.assertRaises(FileExistsError):
                run(output, Path(name) / "missing-bundle/otzaria", 5)

    def test_success_requires_a_real_passed_linux_report_and_window_phases(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            with self.assertRaises(RuntimeError):
                require_linux_result(root)
            path = root / "run-example" / "report.json"
            path.parent.mkdir()
            report = {"status": "passed", "platform": "linux", "buildMode": "profile",
                      "errors": [], "contractErrors": [], "policyRestored": True,
                      "runId": "unit-test-fixture", "phases": [
                          {"name": "minimize", "status": "passed"},
                          {"name": "hide", "status": "passed"}]}

            def save():
                path.write_text(json.dumps({"installedPluginProbe": report}))

            save()
            self.assertEqual(require_linux_result(root)["runId"], "unit-test-fixture")
            for field, value in (("status", "running"), ("platform", "windows"),
                                 ("buildMode", "debug"), ("errors", ["framework error"]),
                                 ("contractErrors", ["audit failed"]), ("policyRestored", False)):
                old = report[field]
                report[field] = value
                save()
                with self.subTest(field=field), self.assertRaises(RuntimeError):
                    require_linux_result(root)
                report[field] = old
            for phase in report["phases"]:
                phase["status"] = "unsupported"
                save()
                with self.subTest(phase=phase["name"]), self.assertRaises(RuntimeError):
                    require_linux_result(root)
                phase["status"] = "passed"

    def test_report_rejects_invalid_run_identity_and_duplicate_phase_names(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            path = root / "run-current" / "report.json"
            path.parent.mkdir()
            report = {"status": "passed", "platform": "linux", "buildMode": "profile",
                      "errors": [], "contractErrors": [], "policyRestored": True,
                      "runId": "current-run", "phases": [
                          {"name": "minimize", "status": "passed"},
                          {"name": "hide", "status": "passed"}]}

            def save():
                path.write_text(json.dumps({"installedPluginProbe": report}))

            save()
            self.assertEqual(require_linux_result(root)["runId"], "current-run")
            for run_id in ("", " \t\n", None, 1, False, [], {}):
                report["runId"] = run_id
                save()
                with self.subTest(run_id=run_id), self.assertRaisesRegex(RuntimeError, "runId"):
                    require_linux_result(root)
            del report["runId"]
            save()
            with self.assertRaisesRegex(RuntimeError, "runId"):
                require_linux_result(root)
            report["runId"] = "current-run"
            for phase_name, status, index in (("minimize", "failed", 0), ("hide", "failed", 0),
                                              ("minimize", "passed", 2), ("hide", "failed", 2)):
                report["phases"].insert(index, {"name": phase_name, "status": status})
                save()
                with self.subTest(name=phase_name, status=status, index=index):
                    with self.assertRaisesRegex(RuntimeError, "duplicate phase"):
                        require_linux_result(root)
                report["phases"].pop(index)


if __name__ == "__main__":
    unittest.main()
