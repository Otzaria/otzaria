import importlib.util
import json
import http.client
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("apple_quiet_runner", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class CpuTests(unittest.TestCase):
    def test_cumulative_cpu_formats(self):
        self.assertAlmostEqual(runner.cpu_seconds("01:02.34"), 62.34)
        self.assertAlmostEqual(runner.cpu_seconds("02:01:02.34"), 7262.34)
        self.assertEqual(runner.cpu_seconds("1-02:01:02"), 93662)
        with self.assertRaises(ValueError):
            runner.cpu_seconds("unknown")

    def test_verified_pid_and_executable_are_required(self):
        line = "42 Fri Nov 6 12:00:00 2026 0:01.20 100 /a/Runner.app/Runner"
        with patch.object(runner, "output", return_value=line):
            sample = runner.host_sample(42, "/a/Runner.app/Runner")
            self.assertEqual(sample["rssBytes"], 102400)
            self.assertEqual(sample["cpuSeconds"], 1.2)
            self.assertEqual(runner.host_sample(43, "/a/Runner.app/Runner")["status"], "unavailable")
            self.assertEqual(runner.host_sample(42, "/another/app")["status"], "unavailable")

    def test_unknown_is_not_zero_and_pid_reuse_is_rejected(self):
        before = {"status": "collected", "identity": {"pid": 42, "started": "A"},
                  "cpuSeconds": 1, "monotonicNs": 1_000_000_000}
        after = {**before, "cpuSeconds": 1.5, "monotonicNs": 3_000_000_000}
        envelope = runner.cpu_envelope(before, after)
        self.assertEqual(envelope["oneCoreEquivalentPercent"], 25)
        self.assertEqual(runner.cpu_envelope(before, {"status": "unavailable"})["status"], "unavailable")
        with self.assertRaises(ValueError):
            runner.cpu_envelope(before, {**after, "identity": {"pid": 42, "started": "B"}})
        with self.assertRaises(ValueError):
            runner.cpu_envelope(before, {**after, "cpuSeconds": 0.1})


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.coordinator = runner.Coordinator(self.directory, "run-A", "nonce", "macos", 6)
        self.body = {"runId": "run-A", "hostPid": 42, "appBootToken": "boot-A", "phase": "visible",
                     "platform": "macos", "action": "quiet", "seconds": 6}

    def test_relaunched_app_cannot_replace_partial_evidence(self):
        original = {**self.body, "status": "running"}
        self.coordinator.request("checkpoint", original, 1000)
        for field, new in [("hostPid", 43), ("appBootToken", "boot-B"), ("runId", "run-B")]:
            with self.assertRaises(ValueError):
                self.coordinator.request("checkpoint", {**original, field: new}, 1000)
        self.assertEqual(json.loads((self.directory / "partial-app.json").read_text()), original)

    def test_physical_completion_requires_final_framework_result(self):
        self.coordinator.physical = True
        report = {**self.body, 'status': 'passed'}
        self.coordinator.request('complete', report, 1000)
        self.assertFalse(self.coordinator.completed.is_set())
        self.coordinator.request('framework-complete', {**report, 'status': 'failed'}, 1001)
        self.assertTrue(self.coordinator.completed.is_set())
        self.assertEqual(json.loads((self.directory / 'complete.json').read_text())['status'], 'failed')

    def test_real_http_arm_finishes_and_closes_before_work(self):
        server = runner.ThreadingHTTPServer(('127.0.0.1', 0), runner.Handler)
        server.coordinator = self.coordinator
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        started = threading.Event()
        try:
            with patch.object(self.coordinator, 'run_job', side_effect=lambda _: started.set()):
                connection = http.client.HTTPConnection('localhost', server.server_port, timeout=3)
                connection.request('POST', '/arm', body=json.dumps(self.body), headers={
                    'Content-Type': 'application/json', 'X-Apple-Quiet-Token': 'nonce'})
                response = connection.getresponse()
                self.assertEqual(response.status, 200)
                self.assertEqual(response.getheader('Connection'), 'close')
                reply = json.loads(response.read())
                self.assertIn(reply['jobId'], self.coordinator.jobs)
                self.assertIsNone(connection.sock)
                self.assertTrue(started.wait(3))
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    def test_unknown_or_overlapping_intervals_cannot_be_claimed_as_finished(self):
        response, after_close = self.coordinator.request("arm", self.body, 1000)
        self.assertTrue(callable(after_close))
        with self.assertRaises(ValueError):
            self.coordinator.request("result", {"jobId": response["jobId"]}, 1001)
        with self.assertRaises(ValueError):
            self.coordinator.request("arm", self.body, 1001)
        self.assertEqual(self.coordinator.jobs[response["jobId"]]["status"], "running")

    def test_bad_duration_or_os_action_fails_before_any_side_effect(self):
        for changed in [{"seconds": 0}, {"seconds": 3.5}, {"action": "iosHome"}, {"phase": "unknown"}]:
            with self.assertRaises(ValueError):
                self.coordinator.request("arm", {**self.body, **changed}, 1000)
        self.assertFalse(self.coordinator.jobs)

    def test_boundary_failure_is_retained_and_cannot_pass(self):
        response, work = self.coordinator.request("arm", self.body, 1000)
        with patch.object(runner.time, "sleep"), patch.object(self.coordinator, 'mac', return_value={'executable': '/fixture'}), patch.object(runner, "host_sample", side_effect=ValueError("fixture failure")):
            work()
        report = json.loads((self.directory / "driver-visible.json").read_text())
        self.assertEqual(report["status"], "failed")
        self.assertIn("fixture failure", report["error"])
        result, _ = self.coordinator.request("result", {"jobId": response["jobId"]}, 1001)
        self.assertEqual(result["status"], "failed")

    def test_ios_controller_also_stops_polling_for_non_home_quiet_windows(self):
        self.coordinator.target = "ios"
        body = {**self.body, "platform": "ios"}
        response, _ = self.coordinator.request("arm", body, 1000)
        job = self.coordinator.jobs[response["jobId"]]
        self.coordinator.control_job = job
        command, _ = self.coordinator.request("control", {}, 1001)
        self.assertEqual(command["action"], "quiet")
        self.assertEqual(command["jobId"], response["jobId"])
        self.assertIsNone(self.coordinator.control_job)
        self.assertGreaterEqual(response["waitMs"], command["remainingMs"])


class PinTests(unittest.TestCase):
    def test_all_eight_resolved_native_packages_share_the_public_pin(self):
        lock = (runner.REPO / "pubspec.lock").read_text()
        # Split at package indentation, not at nested YAML indentation.
        import re
        native = [section for section in re.split(r"\n(?=  [a-zA-Z0-9_]+:\n)", lock)
                  if 'url: "https://github.com/Otzaria/flutter_inappwebview"' in section]
        self.assertEqual(len(native), 8)
        for section in native:
            self.assertIn(f'resolved-ref: "{runner.NATIVE_PIN}"', section)
        self.assertNotIn("c709de98711cf34350c48df4c75e24d0879d5876", (runner.REPO / "pubspec.yaml").read_text())


if __name__ == "__main__":
    unittest.main()
