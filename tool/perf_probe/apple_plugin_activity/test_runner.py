import importlib.util
import json
import http.client
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

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
        controller = Mock()
        controller.request.return_value = {'executable': '/fixture'}
        with patch.object(runner.time, "sleep"), patch.object(runner, 'MacApplicationSession', return_value=controller), patch.object(runner, "host_sample", side_effect=ValueError("fixture failure")):
            work()
        report = json.loads((self.directory / "driver-visible.json").read_text())
        self.assertEqual(report["status"], "failed")
        self.assertIn("fixture failure", report["error"])
        result, _ = self.coordinator.request("result", {"jobId": response["jobId"]}, 1001)
        self.assertEqual(result["status"], "failed")

    def test_ios_controller_also_stops_polling_for_non_home_quiet_windows(self):
        self.coordinator.target = "ios"
        body = {**self.body, "platform": "ios"}
        identity = {"runId": "run-A", "controllerPid": 99, "controllerBootToken": "control-A"}
        self.coordinator.physical = True
        reply, _ = self.coordinator.request("control-ready", identity, 1000)
        identity.update(reply)
        job = {**body, "jobId": "fresh-job", "deadlineMonotonic": runner.time.monotonic() + 16}
        self.coordinator.control_job = job
        command, _ = self.coordinator.request("control", identity, 1001)
        self.assertEqual(command["action"], "quiet")
        self.assertEqual(command["jobId"], "fresh-job")
        self.assertIsNone(self.coordinator.control_job)
        self.assertGreater(command["remainingMs"], 0)

    def test_mac_controller_is_idle_during_the_unchanged_quiet_interval(self):
        for action in ['quiet', 'macAppHide']:
            with self.subTest(action=action):
                self.coordinator = runner.Coordinator(self.directory, "run-A", "nonce", "macos", 6)
                events = []
                controller = Mock()
                controller.request.side_effect = lambda value: events.append(value) or {'executable': '/fixture'}
                controller.close.side_effect = lambda: events.append('close')
                def sleeping(seconds):
                    events.append(('sleep', seconds))
                response, work = self.coordinator.request('arm', {**self.body, 'action': action}, 1000)
                with patch.object(runner, 'MacApplicationSession', return_value=controller), \
                     patch.object(runner.time, 'sleep', side_effect=sleeping), \
                     patch.object(self.coordinator.stop_event, 'wait', side_effect=lambda seconds: sleeping(seconds) or False), \
                     patch.object(runner.time, 'monotonic_ns', side_effect=[1_000_000_000, 7_000_000_000]), \
                     patch.object(runner, 'host_sample', return_value={'status': 'unavailable'}):
                    work()
                expected = [('sleep', 0.3), 'info']
                if action == 'macAppHide': expected.append('hide')
                expected.append(('sleep', 6))
                if action == 'macAppHide': expected.append('activate')
                expected.extend(['info', 'close'])
                self.assertEqual(events, expected)
                self.assertEqual(self.coordinator.jobs[response['jobId']]['status'], 'passed')

    def test_failed_controller_cleanup_cannot_publish_a_success(self):
        response, work = self.coordinator.request('arm', self.body, 1000)
        controller = Mock()
        controller.request.return_value = {'executable': '/fixture'}
        def closing():
            self.assertEqual(self.coordinator.jobs[response['jobId']]['status'], 'running')
            with self.assertRaises(ValueError):
                self.coordinator.request('result', {'jobId': response['jobId']}, 2000)
            raise subprocess.TimeoutExpired(['controller'], 5)
        controller.close.side_effect = closing
        with patch.object(runner, 'MacApplicationSession', return_value=controller), \
             patch.object(runner.time, 'sleep'), \
             patch.object(self.coordinator.stop_event, 'wait', return_value=False), \
             patch.object(runner.time, 'monotonic_ns', side_effect=[1_000_000_000, 7_000_000_000]), \
             patch.object(runner, 'host_sample', return_value={'status': 'unavailable'}):
            work()
        report = self.coordinator.jobs[response['jobId']]
        self.assertEqual(report['status'], 'failed')
        self.assertIn('controllerCleanupError', report)


class SetupEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)

    def test_setup_preserves_separate_output_and_exit(self):
        for code in [0, 37]:
            with self.subTest(exit=code):
                label = f'exit-{code}'
                command = [sys.executable, '-c', f'import sys;print("out");print("stage",file=sys.stderr);sys.exit({code})']
                if code:
                    with self.assertRaises(subprocess.CalledProcessError):
                        runner.recorded_output(self.directory, label, command, 5)
                else:
                    self.assertEqual(runner.recorded_output(self.directory, label, command, 5), 'out')
                receipt = json.loads((self.directory / f'{label}.json').read_text())
                self.assertEqual(receipt['status'], 'failed' if code else 'passed')
                self.assertEqual(receipt['exitCode'], code)
                self.assertEqual((self.directory / f'{label}.stderr.log').read_text(), 'stage\n')
                self.assertEqual((self.directory / f'{label}.stdout.log').read_text(), 'out\n')
                self.assertGreater(receipt['elapsedMs'], 0)

    def test_setup_timeout_retains_partial_stage_and_is_not_a_pass(self):
        command = [sys.executable, '-c', 'import sys,time;print("library-start",file=sys.stderr,flush=True);time.sleep(30)']
        with self.assertRaises(subprocess.TimeoutExpired):
            runner.recorded_output(self.directory, 'timeout', command, 0.2)
        receipt = json.loads((self.directory / 'timeout.json').read_text())
        self.assertEqual(receipt['status'], 'timedOut')
        self.assertIsNone(receipt['exitCode'])
        self.assertIsNotNone(receipt['processExitAfterCleanup'])
        self.assertIn('library-start', (self.directory / 'timeout.stderr.log').read_text())

    def test_setup_logs_are_bounded_and_truncation_is_explicit(self):
        command = [sys.executable, '-c', 'import sys;sys.stdout.write("x"*100000);sys.stderr.write("y"*100000)']
        runner.recorded_output(self.directory, 'large', command, 5)
        receipt = json.loads((self.directory / 'large.json').read_text())
        for name in ['stdout', 'stderr']:
            self.assertEqual(receipt[name]['bytes'], 100000)
            self.assertTrue(receipt[name]['truncated'])
            self.assertEqual((self.directory / f'large.{name}.log').stat().st_size, runner.COMMAND_LOG_LIMIT)

    def test_missing_setup_command_retains_failure_receipt(self):
        with self.assertRaises(OSError):
            runner.recorded_output(self.directory, 'missing', [str(self.directory / 'missing')], 5)
        receipt = json.loads((self.directory / 'missing.json').read_text())
        self.assertEqual(receipt['status'], 'failed')
        self.assertIsNone(receipt['processExitAfterCleanup'])

    def test_project_setup_budget_and_config_do_not_change_quiet_inputs(self):
        def generation(directory, label, command, timeout):
            self.assertEqual(label, 'create-control-project')
            self.assertEqual(timeout, 120)
            Path(command[-2]).mkdir()
        with patch.object(runner, 'recorded_output', side_effect=generation):
            control = runner.prepare_control(self.directory, 'http://localhost:1234', 'nonce', 'run-A')
        config = (control / 'ControlConfig.swift').read_text()
        self.assertIn('http://localhost:1234', config)
        self.assertIn('com.mendelg.otzaria', config)


class MacTransportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.counter = 0

    def test_missing_controller_retains_launch_failure_receipt(self):
        with self.assertRaises(OSError):
            runner.MacApplicationSession(self.directory / 'missing', 42, self.directory, 'missing')
        receipt = json.loads((self.directory / 'mac-missing-controller.json').read_text())
        self.assertEqual(receipt['status'], 'failed')
        self.assertEqual(receipt['hostPid'], 42)
        self.assertIn('error', receipt)

    def test_failed_startup_receipt_cleans_up_the_owned_controller(self):
        helper = self.directory / 'waiting-helper'
        helper.write_text('#!' + sys.executable + '\nimport sys\nfor line in sys.stdin: pass\n')
        helper.chmod(0o700)
        process = subprocess.Popen([str(helper), '42'], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, start_new_session=True)
        self.addCleanup(runner.stop_owned, process)
        real_popen = subprocess.Popen
        def spawn(command, *args, **kwargs):
            if command == [str(helper), '42']:
                return process
            return real_popen(command, *args, **kwargs)
        with patch.object(runner.subprocess, 'Popen', side_effect=spawn), \
             patch.object(runner, 'save', side_effect=[None, OSError('receipt write failed'), None]):
            with self.assertRaisesRegex(OSError, 'receipt write failed'):
                runner.MacApplicationSession(helper, 42, self.directory, 'write-failed')
        self.assertIsNotNone(process.poll())
        self.assertTrue(process.stdin.closed)
        self.assertTrue(process.stdout.closed)

    def controller(self, modification=''):
        self.counter += 1
        helper = self.directory / f'helper-{self.counter}'
        helper.write_text('#!' + sys.executable + '\n' + '''import json,os,sys,time
for line in sys.stdin:
 command=json.loads(line)
 result={"pid":int(sys.argv[1]),"controllerPid":os.getpid(),"sequence":command["sequence"],
         "action":command["action"],"sameApplication":True,"identityMethod":"NSRunningApplication.isEqual",
         "sessionToken":"held-session","executable":"/fixture/App","launchMs":None,
         "launchDateAvailability":"unavailable","applicationState":{"controllerEventLoopRunning":True},
         "returnValue":True,"isHidden":command["action"]=="hide","isActive":command["action"]!="hide"}
 ''' + modification + '''
 print(json.dumps(result),flush=True)
''')
        helper.chmod(0o700)
        controller = runner.MacApplicationSession(helper, 42, self.directory, f'case-{self.counter}')
        self.addCleanup(controller.close)
        return controller

    def test_launch_date_can_be_unavailable_without_losing_session_identity(self):
        controller = self.controller()
        first = controller.request('info')
        last = controller.request('info')
        self.assertIsNone(first['launchMs'])
        self.assertEqual(first['controllerPid'], last['controllerPid'])
        self.assertEqual(first['sessionToken'], last['sessionToken'])
        self.assertEqual(last['sequence'], 2)

    def test_false_or_missing_public_identity_proof_is_rejected(self):
        for modification in ['result["sameApplication"]=False', 'result.pop("sameApplication")',
                             'result["identityMethod"]="pid-only"', 'result["pid"]=43',
                             'result["controllerPid"]=43', 'result["sequence"]+=1',
                             'result["action"]="wrong"', 'result["sessionToken"]=""',
                             'result["executable"]="relative"', 'result=[]',
                             'result["applicationState"]["controllerEventLoopRunning"]=False',
                             'result.pop("applicationState")']:
            with self.subTest(modification=modification):
                controller = self.controller(modification)
                with self.assertRaises(ValueError): controller.request('info')

    def test_session_or_executable_cannot_change_between_boundaries(self):
        for field in ['sessionToken', 'executable']:
            with self.subTest(field=field):
                controller = self.controller(f'if command["sequence"]==2: result["{field}"]="/replacement"')
                controller.request('info')
                with self.assertRaises(ValueError): controller.request('info')

    def test_controller_error_retains_stderr_and_partial_command(self):
        controller = self.controller('print("identity: application terminated",file=sys.stderr,flush=True);sys.exit(1)')
        with self.assertRaises(ValueError): controller.request('activate')
        controller.close()
        stderr = self.directory / f'{controller.prefix}.stderr.log'
        self.assertIn('application terminated', stderr.read_text())
        receipt = json.loads((self.directory / f'{controller.prefix}.json').read_text())
        self.assertEqual(receipt['status'], 'failed')
        self.assertEqual(receipt['exitCode'], 1)

    def test_partial_reply_without_newline_cannot_escape_the_deadline(self):
        controller = self.controller('sys.stdout.write("partial");sys.stdout.flush();time.sleep(0.3);sys.exit(0)')
        with self.assertRaises(TimeoutError): controller.request('info', timeout=0.1)
        path = self.directory / f'{controller.prefix}-01.stdout.log'
        self.assertEqual(path.read_text(), 'partial')

    def test_oversized_reply_is_bounded_and_rejected(self):
        controller = self.controller('sys.stdout.write("x"*100000);sys.stdout.flush();sys.exit(0)')
        with self.assertRaises(ValueError): controller.request('info')
        path = self.directory / f'{controller.prefix}-01.stdout.log'
        self.assertEqual(path.stat().st_size, runner.COMMAND_LOG_LIMIT)


class PinTests(unittest.TestCase):
    def test_all_eight_resolved_native_packages_share_the_public_pin(self):
        lock = (runner.REPO / "pubspec.lock").read_text()
        # Split at package indentation, not at nested YAML indentation.
        import re
        native = [section for section in re.split(r"\n(?=  [a-zA-Z0-9_]+:\n)", lock)
                  if 'url: "https://github.com/Otzaria/flutter_inappwebview"' in section]
        self.assertEqual(len(native), 8)
        for section in native:
            self.assertIn('resolved-ref: "124bb8e63f345ffd0b0f2ea7190c24b19e69897d"', section)
        self.assertNotIn("c709de98711cf34350c48df4c75e24d0879d5876", (runner.REPO / "pubspec.yaml").read_text())


if __name__ == "__main__":
    unittest.main()
