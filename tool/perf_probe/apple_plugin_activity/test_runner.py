import importlib.util
from contextlib import nullcontext
import errno
import hashlib
import json
import http.client
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, call, patch

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
        self.assertEqual(self.coordinator.terminal.get_nowait(), ('nativeFailure', {
            'phase': 'visible', 'error': 'fixture failure'}))

    def test_native_failure_is_signaled_even_when_its_evidence_write_fails(self):
        response, work = self.coordinator.request('arm', self.body, 1000)
        controller = Mock()
        controller.request.side_effect = ValueError('original native boundary failed')
        with patch.object(runner, 'MacApplicationSession', return_value=controller), \
             patch.object(runner.time, 'sleep'), \
             patch.object(runner, 'save', side_effect=OSError('report write failed')):
            work()
        result, _ = self.coordinator.request('result', {'jobId': response['jobId']}, 2000)
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['error'], 'original native boundary failed')
        kind, failure = self.coordinator.terminal.get_nowait()
        self.assertEqual(kind, 'nativeFailure')
        self.assertEqual(failure, {'phase': 'visible', 'error': 'original native boundary failed',
                                   'evidenceWriteError': 'report write failed'})

    def test_a_phase_cannot_publish_success_before_its_final_evidence_is_saved(self):
        response, work = self.coordinator.request('arm', self.body, 1000)
        controller = Mock()
        controller.request.return_value = {'executable': '/fixture'}
        original_save = runner.save
        def saving(path, report):
            self.assertEqual(report['status'], 'passed')
            with self.assertRaisesRegex(ValueError, 'No finished external interval'):
                self.coordinator.request('result', {'jobId': response['jobId']}, 2000)
            original_save(path, report)
        with patch.object(runner, 'MacApplicationSession', return_value=controller), \
             patch.object(runner.time, 'sleep'), \
             patch.object(runner.time, 'monotonic_ns', side_effect=[1_000_000_000, 7_000_000_000]), \
             patch.object(runner, 'host_sample', return_value={'status': 'unavailable'}), \
             patch.object(runner, 'save', side_effect=saving):
            work()
        result, _ = self.coordinator.request('result', {'jobId': response['jobId']}, 2001)
        self.assertEqual(result['status'], 'passed')
        self.assertEqual(json.loads((self.directory / 'driver-visible.json').read_text())['status'], 'passed')

    def test_ios_controller_also_stops_polling_for_non_home_quiet_windows(self):
        self.coordinator.target = "ios"
        self.coordinator.request('control-ready', {'controllerSession': 'controller-A'}, 900)
        self.coordinator.prepared_challenge = 'fresh-boundary'
        body = {**self.body, "platform": "ios", 'controllerSession': 'controller-A', 'challenge': 'fresh-boundary'}
        response, _ = self.coordinator.request("arm", body, 1000)
        job = self.coordinator.jobs[response["jobId"]]
        self.coordinator.control_job = job
        command, _ = self.coordinator.request("control", {'controllerSession': 'controller-A'}, 1001)
        self.assertEqual(command["action"], "quiet")
        self.assertEqual(command["jobId"], response["jobId"])
        self.assertIsNone(self.coordinator.control_job)
        self.assertGreaterEqual(response["waitMs"], command["remainingMs"])

    def test_mac_controller_is_idle_during_the_unchanged_quiet_interval(self):
        for action in ['quiet', 'macAppHide']:
            with self.subTest(action=action):
                self.coordinator = runner.Coordinator(self.directory, "run-A", "nonce", "macos", 6)
                events = []
                controller = Mock()
                controller.request.side_effect = lambda value, **_: events.append(value) or {'executable': '/fixture'}
                controller.close.side_effect = lambda **_: events.append('close')
                def sleeping(seconds):
                    events.append(('sleep', seconds))
                response, work = self.coordinator.request('arm', {**self.body, 'action': action}, 1000)
                with patch.object(runner, 'MacApplicationSession', return_value=controller), \
                     patch.object(runner.time, 'sleep', side_effect=sleeping), \
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
        def closing(**_):
            self.assertEqual(self.coordinator.jobs[response['jobId']]['status'], 'running')
            with self.assertRaises(ValueError):
                self.coordinator.request('result', {'jobId': response['jobId']}, 2000)
            raise subprocess.TimeoutExpired(['controller'], 5)
        controller.close.side_effect = closing
        with patch.object(runner, 'MacApplicationSession', return_value=controller), \
             patch.object(runner.time, 'sleep'), \
             patch.object(runner.time, 'monotonic_ns', side_effect=[1_000_000_000, 7_000_000_000]), \
             patch.object(runner, 'host_sample', return_value={'status': 'unavailable'}):
            work()
        report = self.coordinator.jobs[response['jobId']]
        self.assertEqual(report['status'], 'failed')
        self.assertIn('controllerCleanupError', report)

    def test_dead_ios_controller_cannot_reuse_its_earlier_readiness(self):
        self.coordinator.target = 'ios'
        process = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(0.05)'], start_new_session=True)
        self.addCleanup(runner.stop_owned, process)
        self.coordinator.control_process = process
        self.coordinator.request('control-ready', {'controllerSession': 'controller-A'}, 900)
        process.wait(timeout=3)
        with self.assertRaisesRegex(ValueError, 'exited after readiness'):
            self.coordinator.request('arm', {**self.body, 'platform': 'ios'}, 1000)
        with self.assertRaisesRegex(ValueError, 'exited after readiness'):
            self.coordinator.request('prepare', self.body, 1000)
        self.assertFalse(self.coordinator.jobs)

    def test_ios_preparation_requires_a_fresh_reply_from_the_same_session(self):
        self.coordinator.target = 'ios'
        self.coordinator.request('control-ready', {'controllerSession': 'controller-A'}, 900)
        prepared, errors = [], []
        def prepare():
            try:
                prepared.append(self.coordinator.request('prepare', self.body, 1000)[0])
            except Exception as error:
                errors.append(error)
        thread = threading.Thread(target=prepare)
        thread.start()
        try:
            deadline = time.monotonic() + 3
            while self.coordinator.control_challenge is None and time.monotonic() < deadline:
                time.sleep(0.001)
            command, _ = self.coordinator.request('control', {'controllerSession': 'controller-A'}, 1001)
            self.assertIn('prepare', command)
            with self.assertRaises(ValueError):
                self.coordinator.request('control-prepared', {
                    'controllerSession': 'another-controller', 'challenge': command['prepare']}, 1002)
            self.assertFalse(self.coordinator.control_prepared.is_set())
            self.coordinator.request('control-prepared', {
                'controllerSession': 'controller-A', 'challenge': command['prepare']}, 1002)
            thread.join(timeout=3)
            self.assertFalse(thread.is_alive())
            self.assertFalse(errors)
            body = {**self.body, 'platform': 'ios', **prepared[0]}
            reply, _ = self.coordinator.request('arm', body, 1003)
            self.assertIsNone(self.coordinator.prepared_challenge)
            self.coordinator.jobs[reply['jobId']]['status'] = 'failed'
            with self.assertRaisesRegex(ValueError, 'fresh iOS controller preparation'):
                self.coordinator.request('arm', body, 1004)
        finally:
            self.coordinator.control_prepared.set()
            thread.join(timeout=3)

    def test_slow_macos_preparation_fails_before_quiet_and_before_result(self):
        elapsed, events = [0.0], []
        controller = Mock()
        def request(action, **_):
            events.append(action)
            elapsed[0] += 8
            return {'executable': '/fixture'}
        def sample(*_, **__):
            elapsed[0] += 4
            return {'status': 'unavailable'}
        def sleeping(seconds):
            events.append(('sleep', seconds))
            elapsed[0] += seconds
        controller.request.side_effect = request
        with patch.object(runner.time, 'monotonic', side_effect=lambda: elapsed[0]), \
             patch.object(runner.time, 'monotonic_ns', side_effect=lambda: int(elapsed[0] * 1e9)), \
             patch.object(runner.time, 'sleep', side_effect=sleeping), \
             patch.object(runner, 'MacApplicationSession', return_value=controller), \
             patch.object(runner, 'host_sample', side_effect=sample):
            response, work = self.coordinator.request('arm', self.body, 1000)
            work()
            report, _ = self.coordinator.request('result', {'jobId': response['jobId']}, 21000)
        self.assertEqual(report['status'], 'failed')
        self.assertIn('Insufficient boundary budget', report['error'])
        self.assertNotIn(('sleep', 6), events)
        self.assertLess(elapsed[0], response['waitMs'] / 1000)

    def test_macos_boundary_timeouts_share_the_arm_budget(self):
        elapsed, limits = [0.0], []
        controller = Mock()
        def request(action, timeout):
            limits.append((action, elapsed[0], timeout))
            elapsed[0] += 1
            return {'executable': '/fixture'}
        def sample(*_, timeout):
            limits.append(('sample', elapsed[0], timeout))
            elapsed[0] += 1
            return {'status': 'unavailable'}
        controller.request.side_effect = request
        with patch.object(runner.time, 'monotonic', side_effect=lambda: elapsed[0]), \
             patch.object(runner.time, 'monotonic_ns', side_effect=lambda: int(elapsed[0] * 1e9)), \
             patch.object(runner, 'now_ms', side_effect=lambda: 1000 + elapsed[0] * 1000), \
             patch.object(runner.time, 'sleep', side_effect=lambda seconds: elapsed.__setitem__(0, elapsed[0] + seconds)), \
             patch.object(runner, 'MacApplicationSession', return_value=controller), \
             patch.object(runner, 'host_sample', side_effect=sample):
            response, work = self.coordinator.request('arm', self.body, 1000)
            work()
            report = self.coordinator.jobs[response['jobId']]
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(report['quietElapsedMs'], 6000)
        for _, started, limit in limits[:2]:
            self.assertLessEqual(started + limit, report['deadlineMonotonic'] - 6)
        for _, started, limit in limits[2:]:
            self.assertLessEqual(started + limit, report['resultDeadlineMonotonic'])
        self.assertLess(elapsed[0], response['waitMs'] / 1000)
        self.assertEqual(set(report['driverClockAnchors']), {'armReply', 'quietStart', 'quietEnd'})


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

    def test_setup_cleanup_retains_the_original_timeout_and_partial_evidence(self):
        original = subprocess.TimeoutExpired(['build'], 2)
        process = Mock(pid=42)
        process.wait.side_effect = original
        process.poll.return_value = None
        with patch.object(runner.subprocess, 'Popen', return_value=process), \
             patch.object(runner, 'stop_owned', side_effect=RuntimeError('cleanup failed')):
            with self.assertRaises(subprocess.TimeoutExpired) as failure:
                runner.recorded_output(self.directory, 'original', ['build'], 2)
        self.assertIs(failure.exception, original)
        receipt = json.loads((self.directory / 'original.json').read_text())
        self.assertEqual(receipt['status'], 'timedOut')
        self.assertEqual(receipt['cleanupError'], 'cleanup failed')
        self.assertTrue((self.directory / 'original.stderr.log').exists())

    def test_setup_evidence_and_diagnostic_write_failures_preserve_the_original_timeout(self):
        original = subprocess.TimeoutExpired(['build'], 2)
        process = Mock(pid=42)
        process.wait.side_effect = original
        process.poll.return_value = None
        with patch.object(runner.subprocess, 'Popen', return_value=process), \
             patch.object(runner, 'stop_owned'), \
             patch.object(runner.sys, 'stderr', Mock(write=Mock(side_effect=BrokenPipeError('stderr closed')))), \
             patch.object(runner, 'save', side_effect=[None, OSError('evidence write failed')]):
            with self.assertRaises(subprocess.TimeoutExpired) as failure:
                runner.recorded_output(self.directory, 'original', ['build'], 2)
        self.assertIs(failure.exception, original)

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
            control = runner.prepare_control(self.directory, 'http://localhost:1234', 'nonce')
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
        with patch.object(runner.subprocess, 'Popen', return_value=process), \
             patch.object(runner, 'save', side_effect=[None, OSError('receipt write failed'), None]):
            with self.assertRaisesRegex(OSError, 'receipt write failed'):
                runner.MacApplicationSession(helper, 42, self.directory, 'write-failed')
        self.assertIsNotNone(process.poll())
        self.assertTrue(process.stdin.closed)
        self.assertTrue(process.stdout.closed)

    def test_startup_failure_survives_signal_receipt_and_stderr_errors(self):
        helper = self.directory / 'startup-waiting-helper'
        helper.write_text('#!' + sys.executable + '\nimport sys\nfor line in sys.stdin: pass\n')
        helper.chmod(0o700)
        process = subprocess.Popen([str(helper), '42'], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, start_new_session=True)
        self.addCleanup(runner.stop_owned, process)
        failure = OSError('initial startup receipt failed')
        with patch.object(runner.subprocess, 'Popen', return_value=process) as launch, \
             patch.object(runner, 'save', side_effect=[None, failure, OSError('final startup receipt failed')]) as saving, \
             patch.object(runner, 'stop_owned', side_effect=PermissionError('signal denied')) as stop, \
             patch.object(runner.sys, 'stderr', Mock(write=Mock(side_effect=BrokenPipeError('stderr closed')))):
            with self.assertRaises(OSError) as captured:
                runner.MacApplicationSession(helper, 42, self.directory, 'startup-failed')
        self.assertIs(captured.exception, failure)
        self.assertEqual(stop.call_count, 1)
        self.assertTrue(process.stdin.closed)
        self.assertTrue(process.stdout.closed)
        self.assertTrue(launch.call_args.kwargs['stderr'].closed)
        self.assertEqual(process.wait(timeout=3), 0)
        receipt = saving.call_args.args[1]
        self.assertEqual(receipt['error'], str(failure))
        self.assertEqual(receipt['cleanupErrors'], [{'stage': 'controller', 'error': 'signal denied'}])
        self.assertEqual(receipt['evidenceWriteError'], 'final startup receipt failed')
        self.assertEqual(receipt['status'], 'failed')

    def controller(self, modification=''):
        self.counter += 1
        helper = self.directory / f'helper-{self.counter}'
        helper.write_text('#!' + sys.executable + '\n' + '''import json,os,sys,time
for line in sys.stdin:
 command=json.loads(line)
 result={"pid":int(sys.argv[1]),"controllerPid":os.getpid(),"sequence":command["sequence"],
         "action":command["action"],"sameApplication":True,"identityMethod":"NSRunningApplication.isEqual",
         "sessionToken":"held-session","executable":"/fixture/App","launchMs":None,
         "launchDateAvailability":"unavailable"}
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
                             'result["executable"]="relative"', 'result=[]']:
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

    def test_request_preserves_native_failure_when_command_evidence_and_stderr_fail(self):
        for failing_write in ['receipt', 'stdout']:
            with self.subTest(failing_write=failing_write):
                controller = self.controller('print("native hide refused",file=sys.stderr,flush=True);sys.exit(2)')
                saving = (patch.object(runner, 'save', side_effect=[None, OSError('command receipt failed')])
                          if failing_write == 'receipt' else nullcontext())
                stdout = (patch.object(Path, 'write_bytes', side_effect=OSError('command stdout failed'))
                          if failing_write == 'stdout' else nullcontext())
                with saving, stdout, patch.object(runner.sys, 'stderr',
                        Mock(write=Mock(side_effect=BrokenPipeError('stderr closed')))):
                    with self.assertRaisesRegex(ValueError, 'hide controller closed its output'):
                        controller.request('hide')
                self.assertEqual(controller.record['commands'][0]['status'], 'failed')
                self.assertIn('evidenceWriteError', controller.record['commands'][0])

    def test_command_evidence_failure_alone_cannot_pass(self):
        controller = self.controller()
        failure = OSError('command receipt failed')
        with patch.object(runner, 'save', side_effect=[None, failure]):
            with self.assertRaises(OSError) as captured:
                controller.request('info')
        self.assertIs(captured.exception, failure)
        self.assertTrue(controller.failed)
        self.assertEqual(controller.record['commands'][0]['status'], 'failed')

    def test_denied_controller_cleanup_is_not_retried_and_still_closes_streams(self):
        controller = self.controller()
        controller.failed = True
        denied = PermissionError(errno.EPERM, 'owned process group signal denied')
        with patch.object(runner.os, 'killpg', side_effect=denied) as stop:
            with self.assertRaises(PermissionError) as captured:
                controller.close()
        self.assertIs(captured.exception, denied)
        self.assertEqual(stop.call_count, 1)
        self.assertTrue(controller.process.stdin.closed)
        self.assertTrue(controller.process.stdout.closed)
        self.assertTrue(controller.stderr.closed)
        # The real child receives EOF; no permission fallback or second signal.
        self.assertEqual(controller.process.wait(timeout=3), 0)
        receipt = json.loads((self.directory / f'{controller.prefix}.json').read_text())
        self.assertEqual(receipt['status'], 'failed')
        self.assertEqual(receipt['error'], str(denied))
        observation = receipt['cleanupProcess']
        self.assertEqual(observation['pid'], controller.process.pid)
        self.assertEqual(observation['expectedPgid'], controller.process.pid)
        self.assertEqual(observation['observedPgid'], controller.process.pid)
        self.assertIsNone(observation['returnCodeBeforeStop'])
        self.assertEqual(observation['failure']['errno'], errno.EPERM)
        self.assertEqual(observation['failure']['stage'], 'SIGTERM')

    def test_close_preserves_wait_failure_over_signal_receipt_and_stderr_errors(self):
        controller = self.controller()
        failure = subprocess.TimeoutExpired('owned-controller', 5)
        with patch.object(controller.process, 'wait', side_effect=failure), \
             patch.object(runner, 'stop_owned', side_effect=PermissionError('signal denied')) as stop, \
             patch.object(runner, 'save', side_effect=OSError('cleanup receipt failed')), \
             patch.object(runner.sys, 'stderr', Mock(write=Mock(side_effect=BrokenPipeError('stderr closed')))):
            with self.assertRaises(subprocess.TimeoutExpired) as captured:
                controller.close()
        self.assertIs(captured.exception, failure)
        self.assertEqual(stop.call_count, 1)
        self.assertEqual(controller.record['cleanupErrors'], [{'stage': 'controller', 'error': 'signal denied'}])
        self.assertEqual(controller.record['status'], 'failed')
        self.assertEqual(controller.process.wait(timeout=3), 0)

    def test_cleanup_receipt_failure_alone_cannot_pass(self):
        controller = self.controller()
        failure = OSError('cleanup receipt failed')
        with patch.object(runner, 'save', side_effect=failure), patch.object(runner, 'warn_cleanup'):
            with self.assertRaises(OSError) as captured:
                controller.close()
        self.assertIs(captured.exception, failure)
        self.assertTrue(controller.failed)
        self.assertEqual(controller.record['status'], 'failed')
        self.assertEqual(controller.process.poll(), 0)

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
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.native = self.directory / 'native'
        self.native.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.native)], check=True)
        for name in runner.NATIVE_PACKAGES:
            package = self.native / name
            package.mkdir()
            (package / 'pubspec.yaml').write_text(f'name: {name}\n')
        subprocess.run(['git', '-C', str(self.native), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.native), '-c', 'user.name=Fixture',
                        '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture source'], check=True)
        self.revision = runner.output(['git', '-C', str(self.native), 'rev-parse', 'HEAD'])
        declarations, locked, packages = [], [], []
        for name in sorted(runner.NATIVE_PACKAGES):
            location = f'      path: {name}\n      ref: "{self.revision}"\n      url: "https://github.com/Otzaria/flutter_inappwebview"\n'
            if name != 'flutter_inappwebview_web':
                declarations.append(f'  {name}:\n    git:\n{location}')
            locked.append(f'  {name}:\n    description:\n{location}      resolved-ref: "{self.revision}"\n    source: git\n')
            packages.append({'name': name, 'rootUri': (self.native / name).as_uri()})
        (self.directory / 'pubspec.yaml').write_text('dependencies:\n' + ''.join(declarations))
        (self.directory / 'pubspec.lock').write_text('packages:\n' + ''.join(locked))
        (self.directory / '.dart_tool').mkdir()
        self.config = self.directory / '.dart_tool/package_config.json'
        self.config.write_text(json.dumps({'packages': packages}))

    def test_all_eight_lock_and_resolved_source_revisions_are_verified(self):
        proof = runner.native_source_provenance(self.directory)
        self.assertEqual(proof['revision'], self.revision)
        self.assertEqual(set(proof['packages']), runner.NATIVE_PACKAGES)
        self.assertEqual(len(proof['packages']), 8)
        for package in proof['packages'].values():
            self.assertEqual(package['revision'], self.revision)
        coordinator = runner.Coordinator(self.directory, 'run-A', 'token', 'ios', 6)
        coordinator.native_fork = proof['revision']
        report = {'runId': 'run-A', 'hostPid': 42, 'appBootToken': 'boot', 'nativeFork': proof['revision']}
        coordinator.request('checkpoint', report, 1000)
        with self.assertRaisesRegex(ValueError, 'app native fork differs'):
            coordinator.request('checkpoint', {**report, 'nativeFork': '0' * 40}, 1001)
        self.assertEqual(json.loads((self.directory / 'partial-app.json').read_text())['nativeFork'], self.revision)

    def test_a_single_inconsistent_pin_is_rejected(self):
        path = self.directory / 'pubspec.lock'
        path.write_text(path.read_text().replace('resolved-ref: "' + self.revision, 'resolved-ref: "' + '0' * 40, 1))
        with self.assertRaisesRegex(ValueError, 'inconsistent native fork'):
            runner.native_source_provenance(self.directory)

    def test_matching_manifests_cannot_hide_a_different_resolved_checkout(self):
        for name in ['pubspec.yaml', 'pubspec.lock']:
            path = self.directory / name
            path.write_text(path.read_text().replace(self.revision, '0' * 40))
        with self.assertRaisesRegex(ValueError, 'source differs from the lockfile'):
            runner.native_source_provenance(self.directory)

    def test_dirty_resolved_native_source_is_rejected(self):
        (self.native / 'flutter_inappwebview_ios/pubspec.yaml').write_text('changed\n')
        with self.assertRaisesRegex(ValueError, 'source is dirty'):
            runner.native_source_provenance(self.directory)

    def test_package_config_cannot_redirect_a_package_to_a_sibling(self):
        config = json.loads(self.config.read_text())
        config['packages'][0]['rootUri'] = config['packages'][1]['rootUri']
        self.config.write_text(json.dumps(config))
        with self.assertRaisesRegex(ValueError, 'resolved native package path'):
            runner.native_source_provenance(self.directory)


class OwnedCleanupEvidenceTests(unittest.TestCase):
    def test_denied_signal_keeps_known_target_and_single_pre_stop_observation(self):
        process = Mock(pid=42)
        process.poll.return_value = None
        failure = PermissionError(errno.EPERM, 'signal denied')
        evidence = {}
        with patch.object(runner, 'clock_anchor', return_value={'wallMs': 1234, 'monotonicMs': 56}), \
             patch.object(runner.os, 'getpgid', return_value=41) as observed, \
             patch.object(runner.os, 'killpg', side_effect=failure) as signal:
            with self.assertRaises(PermissionError) as captured:
                runner.stop_owned(process, evidence=evidence)
        self.assertIs(captured.exception, failure)
        self.assertEqual(evidence['pid'], 42)
        self.assertEqual(evidence['expectedPgid'], 42)
        self.assertEqual(evidence['observedPgid'], 41)
        self.assertIsNone(evidence['returnCodeBeforeStop'])
        self.assertEqual((evidence['wallMs'], evidence['monotonicMs']), (1234, 56))
        self.assertEqual(evidence['failure']['stage'], 'SIGTERM')
        self.assertEqual(evidence['failure']['errno'], errno.EPERM)
        observed.assert_called_once_with(42)
        process.poll.assert_called_once_with()
        signal.assert_called_once_with(42, runner.signal.SIGTERM)
        process.wait.assert_not_called()

    def test_observation_error_cannot_replace_denied_signal(self):
        process = Mock(pid=42)
        process.poll.return_value = None
        failure = PermissionError(errno.EPERM, 'signal denied')
        evidence = {}
        with patch.object(runner.os, 'getpgid', side_effect=OSError(errno.ESRCH, 'no group')), \
             patch.object(runner.os, 'killpg', side_effect=failure) as signal:
            with self.assertRaises(PermissionError) as captured:
                runner.stop_owned(process, evidence=evidence)
        self.assertIs(captured.exception, failure)
        self.assertEqual(evidence['observationError']['errno'], errno.ESRCH)
        self.assertEqual(evidence['failure']['errno'], errno.EPERM)
        self.assertEqual(evidence['failure']['stage'], 'SIGTERM')
        signal.assert_called_once_with(42, runner.signal.SIGTERM)
        process.wait.assert_not_called()

    def test_second_signal_failure_retains_stage_without_another_observation(self):
        process = Mock(pid=42)
        process.poll.return_value = None
        process.wait.side_effect = subprocess.TimeoutExpired('owned-process', 2)
        failure = PermissionError(errno.EPERM, 'second signal denied')
        evidence = {}
        with patch.object(runner.os, 'getpgid', return_value=42) as observed, \
             patch.object(runner.os, 'killpg', side_effect=[None, failure]) as signal:
            with self.assertRaises(PermissionError) as captured:
                runner.stop_owned(process, timeout=2, evidence=evidence)
        self.assertIs(captured.exception, failure)
        self.assertEqual(evidence['failure']['stage'], 'SIGKILL')
        self.assertEqual(evidence['failure']['errno'], errno.EPERM)
        observed.assert_called_once_with(42)
        process.poll.assert_called_once_with()
        process.wait.assert_called_once_with(timeout=2)
        self.assertEqual(signal.call_args_list,
                         [call(42, runner.signal.SIGTERM), call(42, runner.signal.SIGKILL)])


class DriveCompletionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.coordinator = runner.Coordinator(Path(temporary.name), 'run-A', 'nonce', 'ios', 6)

    def process(self, *, delay=30, code=0):
        process = subprocess.Popen([sys.executable, '-c',
            f'import time;time.sleep({delay});raise SystemExit({code})'], start_new_session=True)
        self.addCleanup(runner.stop_owned, process, timeout=1, kill_timeout=1)
        return process

    def test_native_failure_releases_a_blocking_drive_wait_without_polling(self):
        process = self.process()
        signal = threading.Timer(0.05, lambda: self.coordinator.fail_native('osBackground', 'quiet.homeFailed'))
        signal.start()
        self.addCleanup(signal.join)
        started = time.monotonic()
        with self.assertRaisesRegex(RuntimeError, 'osBackground.*quiet.homeFailed'):
            runner.wait_for_drive(process, self.coordinator, timeout=3)
        self.assertLess(time.monotonic() - started, 2)
        self.assertIsNone(process.poll())

    def test_early_controller_exit_is_a_failure_even_while_drive_is_alive(self):
        process = self.process()
        self.coordinator.control_process = self.process(delay=0.05, code=37)
        with self.assertRaisesRegex(RuntimeError, 'controller exit.*37'):
            runner.wait_for_drive(process, self.coordinator, timeout=3)
        self.assertIsNone(process.poll())

    def test_controller_exit_does_not_replace_the_first_native_failure(self):
        process = self.process()
        self.coordinator.fail_native('osBackground', 'quiet.homeFailed')
        self.coordinator.control_process = self.process(delay=0, code=37)
        with self.assertRaisesRegex(RuntimeError, 'osBackground.*quiet.homeFailed'):
            runner.wait_for_drive(process, self.coordinator, timeout=3)
        self.coordinator.control_process.wait(timeout=3)
        self.assertEqual(self.coordinator.native_failure['phase'], 'osBackground')
        self.assertEqual(self.coordinator.native_failure['error'], 'quiet.homeFailed')

    def test_failed_control_receipt_wins_over_exit_before_phase_file_publication(self):
        process = self.process()
        self.coordinator.control_session = 'controller-A'
        self.coordinator.jobs['job-A'] = {'phase': 'osBackground', 'driverClockAnchors': {}, 'status': 'running'}
        _, after_close = self.coordinator.request('control-result', {
            'jobId': 'job-A', 'controllerSession': 'controller-A',
            'status': 'failed', 'error': 'quiet.homeFailed'}, 1000)
        self.assertTrue(self.coordinator.terminal.empty())
        self.coordinator.control_process = self.process(delay=0, code=37)
        with self.assertRaisesRegex(RuntimeError, 'osBackground.*quiet.homeFailed'):
            runner.wait_for_drive(process, self.coordinator, timeout=3)
        self.assertEqual(self.coordinator.native_failure['phase'], 'osBackground')
        self.assertEqual(self.coordinator.native_failure['error'], 'XCUITest failed: quiet.homeFailed')
        self.assertIn('37', self.coordinator.native_failure['secondaryErrors'][0]['error'])
        after_close()
        self.assertTrue(self.coordinator.terminal.empty())

    def test_normal_controller_completion_does_not_end_the_drive_early(self):
        process = self.process(delay=0.1, code=37)
        self.coordinator.completed.set()
        self.coordinator.control_process = self.process(delay=0)
        self.assertEqual(runner.wait_for_drive(process, self.coordinator, timeout=3), 37)
        self.assertIsNone(self.coordinator.native_failure)

    def test_missing_terminal_signal_expires_with_the_drive_command(self):
        process = self.process()
        with self.assertRaises(subprocess.TimeoutExpired) as failure:
            runner.wait_for_drive(process, self.coordinator, timeout=0.05)
        self.assertEqual(failure.exception.cmd, process.args)


class RunBudgetTests(unittest.TestCase):
    def test_local_budget_and_finite_ci_deadline(self):
        with patch.dict(runner.os.environ, {}, clear=True):
            self.assertEqual(runner.run_deadline(1000), 4900)
        for invalid in ['nan', 'inf', '-inf', 'not-a-clock']:
            with self.subTest(invalid=invalid), \
                 patch.dict(runner.os.environ, {'APPLE_PROBE_DEADLINE_MONOTONIC': invalid}):
                with self.assertRaises(ValueError):
                    runner.run_deadline(1000)
        with patch.dict(runner.os.environ, {'APPLE_PROBE_DEADLINE_MONOTONIC': '1234.5'}):
            self.assertEqual(runner.run_deadline(1000), 1234.5)

    def test_metadata_command_uses_only_the_remaining_budget(self):
        with patch.object(runner.time, 'monotonic', return_value=1000), \
             patch.object(runner.subprocess, 'check_output', return_value='ok') as command:
            self.assertEqual(runner.output(['fixture'], deadline=1005), 'ok')
            self.assertEqual(command.call_args.kwargs['timeout'], 5)
            command.reset_mock()
            with self.assertRaises(TimeoutError):
                runner.output(['fixture'], deadline=1000)
            command.assert_not_called()


class BuildOrderingTests(unittest.TestCase):
    def run_probe(self, *, budget=3900, build_seconds=0, readiness_seconds=0,
                  drive_seconds=0, completion_seconds=0, control_seconds=0,
                  expected_error=None, cleanup_error=None, final_save_error=None,
                  diagnostic_error=None, uninstall_on_exit=False,
                  info_plist=plistlib.dumps({'CFBundleIdentifier': 'com.mendelg.otzaria'}),
                  codesign_error=None, server_close_error=None):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = root / 'repo'
            entitlements = repository / 'macos/Runner/DebugProfile.entitlements'
            entitlements.parent.mkdir(parents=True)
            entitlements.write_text('<plist/>')
            directory = root / 'output'
            application = repository / 'build/ios/iphonesimulator/Runner.app'
            installed = root / 'Simulator/installed/Runner.app'
            coordinator = runner.Coordinator(directory, 'run-A', 'token', 'ios', 6)
            calls = []
            limits = {}
            elapsed = [1000.0]
            original_save = runner.save
            def saving(path, value):
                if final_save_error is not None and coordinator.stopping and path.name == 'environment.json':
                    raise final_save_error
                original_save(path, value)
            def output(command, **_):
                if command[:2] == ['flutter', '--version']:
                    return json.dumps({'frameworkVersion': '3.47.7'})
                if command[:3] == ['xcrun', 'simctl', 'list']:
                    return json.dumps({'devices': {'iOS': [{'udid': 'device-A', 'state': 'Booted'}]}})
                return 'fixture'
            def recorded(_, label, command, timeout):
                calls.append(command)
                limits[label] = timeout
                if label == 'build-ios-probe':
                    elapsed[0] += build_seconds
                    application.mkdir(parents=True)
                    if info_plist is not None:
                        (application / 'Info.plist').write_bytes(info_plist)
                elif label == 'create-control-project':
                    Path(command[-2]).mkdir()
            def codesign(command, **kwargs):
                calls.append(command)
                limits['codesign'] = kwargs['timeout']
                self.assertEqual(command, ['codesign', '-d', '--entitlements', ':-', str(application)])
                if codesign_error is not None:
                    raise codesign_error
                return subprocess.CompletedProcess(command, 0, '<plist/>', 'fixture signature')
            def ready(timeout):
                limits['readiness'] = timeout
                elapsed[0] += readiness_seconds
                return True
            def complete(timeout):
                limits['completion'] = timeout
                elapsed[0] += completion_seconds
                return True
            def cleanup(process, **_):
                if process is not None:
                    if cleanup_error is not None:
                        raise cleanup_error
                    process.returncode = 0
            class Process:
                returncode = None
                def __init__(self, command, **_):
                    calls.append(command)
                    self.command = command
                    if command[0] == 'xcodebuild':
                        coordinator.control_session = 'controller-A'
                        coordinator.control_ready.set()
                    elif uninstall_on_exit and command[:2] == ['flutter', 'drive']:
                        installed.mkdir(parents=True)
                        (installed / 'Info.plist').write_bytes((application / 'Info.plist').read_bytes())
                        coordinator.executable = str(installed / 'Runner')
                def poll(self):
                    return self.returncode
                def wait(self, timeout):
                    self.returncode = 0
                    if self.command[:2] == ['flutter', 'drive']:
                        limits['drive'] = timeout
                        elapsed[0] += drive_seconds
                        runner.save(directory / 'complete.json', {'status': 'passed'})
                        coordinator.completed.set()
                        if uninstall_on_exit:
                            (installed / 'Info.plist').unlink()
                            installed.rmdir()
                    else:
                        limits['control completion'] = timeout
                        elapsed[0] += control_seconds
                    return 0
            server = Mock(server_port=12345)
            server.server_close.side_effect = server_close_error
            with patch.object(sys, 'argv', ['run.py', '--platform', 'ios', '--device', 'device-A', '--mode', 'debug', '--seconds', '6', '--output', str(directory)]), \
                 patch.dict(runner.os.environ, {'APPLE_PROBE_DEADLINE_MONOTONIC': str(1000 + budget)}), \
                 patch.object(runner.time, 'monotonic', side_effect=lambda: elapsed[0]), \
                 patch.object(runner.platform, 'system', return_value='Darwin'), \
                 patch.object(runner.platform, 'platform', return_value='fixture-Mac'), \
                 patch.object(runner, 'REPO', repository), \
                 patch.object(runner, 'Coordinator', return_value=coordinator), \
                 patch.object(coordinator.control_ready, 'wait', side_effect=ready), \
                 patch.object(coordinator.completed, 'wait', side_effect=complete), \
                 patch.object(runner, 'ThreadingHTTPServer', return_value=server), \
                 patch.object(runner, 'native_source_provenance', return_value={'revision': 'a' * 40, 'packages': {}}), \
                 patch.object(runner, 'output', side_effect=output), \
                 patch.object(runner, 'recorded_output', side_effect=recorded), \
                 patch.object(runner, 'save', side_effect=saving), \
                 (patch.object(runner.sys, 'stderr', Mock(write=Mock(side_effect=diagnostic_error))) if diagnostic_error else nullcontext()), \
                 patch.object(runner, 'stop_owned', side_effect=cleanup), \
                 patch.object(runner, 'wait_for_drive', side_effect=lambda process, _, timeout: process.wait(timeout=timeout)), \
                 patch.object(runner.subprocess, 'run', side_effect=codesign), \
                 patch.object(runner.subprocess, 'Popen', Process):
                with self.assertRaises(expected_error) if expected_error else nullcontext():
                    runner.main()
            defines = json.loads((directory / 'defines.json').read_text())
            environment = json.loads((directory / 'environment.json').read_text())
            self.assertEqual(defines['APPLE_QUIET_NATIVE_FORK'], environment['nativeFork'])
            self.assertEqual(defines['APPLE_QUIET_NATIVE_FORK'], 'a' * 40)
            server.server_close.assert_called_once()
            return calls, limits, environment

    def test_controller_starts_after_the_ios_build_and_drive_reuses_the_binary(self):
        calls, _, _ = self.run_probe()
        build = next(i for i, command in enumerate(calls) if command[:3] == ['flutter', 'build', 'ios'])
        control = next(i for i, command in enumerate(calls) if command[0] == 'xcodebuild')
        drive = next(i for i, command in enumerate(calls) if command[:2] == ['flutter', 'drive'])
        self.assertLess(build, control)
        self.assertLess(control, drive)
        self.assertTrue(any(value.endswith('/build/ios/iphonesimulator/Runner.app')
                            and value.startswith('--use-application-binary=') for value in calls[drive]))

    def test_prebuilt_metadata_survives_the_driver_uninstalling_its_simulator_bundle(self):
        calls, _, report = self.run_probe(uninstall_on_exit=True)
        build = next(i for i, command in enumerate(calls) if command[:3] == ['flutter', 'build', 'ios'])
        signed = next(i for i, command in enumerate(calls) if command[0] == 'codesign')
        control = next(i for i, command in enumerate(calls) if command[0] == 'xcodebuild')
        self.assertLess(build, signed)
        self.assertLess(signed, control)
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(report['builtApplicationProvenance'], {
            'source': 'prebuiltApplication', 'stage': 'beforeRuntime',
            'bundle': report['prebuiltApplication'],
            'infoPlist': report['prebuiltApplication'] + '/Info.plist',
            'bundleIdentifier': 'com.mendelg.otzaria',
        })
        self.assertEqual(report['builtInfoPlistSha256'], hashlib.sha256(
            plistlib.dumps({'CFBundleIdentifier': 'com.mendelg.otzaria'})).hexdigest())
        self.assertEqual(report['builtEntitlements'], {
            'exitCode': 0, 'stdout': '<plist/>', 'stderr': 'fixture signature'})

    def test_missing_or_invalid_prebuilt_metadata_cannot_start_runtime(self):
        for contents, error in [(None, FileNotFoundError), (b'not a plist', plistlib.InvalidFileException),
                                (plistlib.dumps({'CFBundleIdentifier': 'another.app'}), ValueError)]:
            with self.subTest(contents=contents):
                calls, _, report = self.run_probe(info_plist=contents, expected_error=error)
                self.assertFalse(any(command[0] in {'xcodebuild', 'codesign'} for command in calls))
                self.assertFalse(any(command[:2] == ['flutter', 'drive'] for command in calls))
                self.assertEqual(report['status'], 'failed')

    def test_metadata_collection_failure_survives_cleanup_and_starts_no_runtime(self):
        calls, _, report = self.run_probe(codesign_error=OSError('codesign failed to start'),
            server_close_error=RuntimeError('server close failed'), expected_error=OSError)
        self.assertFalse(any(command[0] == 'xcodebuild' for command in calls))
        self.assertFalse(any(command[:2] == ['flutter', 'drive'] for command in calls))
        self.assertEqual(report['status'], 'failed')
        self.assertEqual(report['error'], 'codesign failed to start')
        self.assertEqual(report['cleanupErrors'], [{'stage': 'server close', 'error': 'server close failed'}])

    def test_build_readiness_drive_and_completion_share_one_deadline(self):
        _, limits, report = self.run_probe(budget=2500, build_seconds=2390,
            readiness_seconds=100, drive_seconds=3, completion_seconds=2, control_seconds=2)
        self.assertEqual(limits, {'build-ios-probe': 2400, 'codesign': 15, 'create-control-project': 110,
            'readiness': 110, 'drive': 10, 'completion': 7, 'control completion': 5})
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(report['deadlineMonotonic'], 3500)
        self.assertEqual(report['remainingBudgetAtStartSeconds'], 2500)

    def test_expired_build_cannot_start_a_controller(self):
        calls, _, report = self.run_probe(budget=2400, build_seconds=2400, expected_error=TimeoutError)
        self.assertFalse(any(command[0] == 'xcodebuild' for command in calls))
        self.assertFalse(any(command[:2] == ['flutter', 'drive'] for command in calls))
        self.assertEqual(report['status'], 'failed')

    def test_expired_readiness_cannot_start_drive_and_cleanup_keeps_the_timeout(self):
        calls, _, report = self.run_probe(budget=2410, build_seconds=2400,
            readiness_seconds=10, expected_error=TimeoutError, cleanup_error=RuntimeError('stop failed'))
        self.assertFalse(any(command[:2] == ['flutter', 'drive'] for command in calls))
        self.assertIn('deadline expired', report['error'])
        self.assertEqual(report['cleanupErrors'], [{'stage': 'controller', 'error': 'stop failed'}])

    def test_expired_drive_cannot_accept_even_an_already_available_completion(self):
        _, limits, report = self.run_probe(budget=2500, build_seconds=2390,
            readiness_seconds=100, drive_seconds=10, expected_error=TimeoutError)
        self.assertNotIn('completion', limits)
        self.assertEqual(report['status'], 'failed')

    def test_cleanup_only_failure_cannot_publish_a_success(self):
        _, _, report = self.run_probe(expected_error=RuntimeError, cleanup_error=RuntimeError('stop failed'))
        self.assertEqual(report['status'], 'failed')
        self.assertEqual(report['error'], 'stop failed')
        self.assertEqual([item['stage'] for item in report['cleanupErrors']], ['app', 'controller'])

    def test_final_save_and_closed_stderr_cannot_replace_the_run_timeout(self):
        self.run_probe(budget=2410, build_seconds=2400, readiness_seconds=10,
            expected_error=TimeoutError, final_save_error=OSError('environment write failed'),
            diagnostic_error=BrokenPipeError('stderr closed'))


if __name__ == "__main__":
    unittest.main()
