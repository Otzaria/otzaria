"""Build retry classes and per-count budgets; no native build is run."""
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch

import run_ios_plugin_fonts as runner

SWIFTPM_504 = """Xcode failed to resolve Swift Package Manager dependencies:
xcodebuild: error: Could not resolve package dependencies:
  failed downloading 'https://github.com/getsentry/sentry-cocoa/releases/download/8.58.4/Sentry-Dynamic.xcframework.zip' which is required by binary target 'Sentry-Dynamic': badResponseStatusCode(504)
  fatalError
"""
SWIFTPM_503 = """xcodebuild: error: Could not resolve package dependencies:
  failed downloading 'https://github.com/x/y/releases/download/1/z.zip' downloadError("HTTP 503")
"""
SQLITE_HASH = """    Unhandled exception:
    Bad state: Hash of downloaded file libsqlite3.arm64.ios_sim.dylib is bef140a1a96994029153dca8c00b1750b9a5a764fb9db2dc68d7bb40e8a29e8a, expected 6268444eeb073b6f9c5f80f4e3c7fc38fa0862e997cd2719b6058969f0f1802f.

      Building assets for package:sqlite3 failed.
      build.dart returned with exit code: 255.
"""


class TransientBuildFailureTests(unittest.TestCase):
    def test_external_downloads_before_any_app_code_are_retried(self):
        self.assertEqual(runner.transient_build_failure(SWIFTPM_504), 'swiftpm-download')
        self.assertEqual(runner.transient_build_failure(SWIFTPM_503), 'swiftpm-download')
        self.assertEqual(runner.transient_build_failure(SQLITE_HASH), 'native-asset-download')

    def test_compiler_package_and_unrelated_hash_failures_are_not_retried(self):
        for log in ['', 'error: cannot find type Foo in scope\n** BUILD FAILED **',
                    SWIFTPM_504.replace('504', '404'),
                    SWIFTPM_504.replace('badResponseStatusCode(504)', 'checksum mismatch'),
                    "failed downloading 'https://github.com/x/y.zip' badResponseStatusCode(504)",
                    SQLITE_HASH.replace('Building assets for package:sqlite3 failed.', ''),
                    'Bad state: Hash of downloaded file a is short, expected b. Building assets for package:x']:
            with self.subTest(log=log[:60]):
                self.assertIsNone(runner.transient_build_failure(log))


class Budget:
    def __init__(self, left=4000):
        self.remaining = left

    def left(self):
        return self.remaining

    def build(self):
        return 3000


class FakeCommands:
    """Each outcome is (log, timedOut); a None log is a successful build."""

    def __init__(self, output, outcomes):
        self.output, self.outcomes, self.labels = output, list(outcomes), []

    def run(self, label, command, timeout, *, env=None, check=True):
        self.labels.append(label)
        log, timed_out = self.outcomes.pop(0)
        (self.output / (label + '.log')).write_text(log or '')
        failures = [] if log is None else [{'step': 'process-exit', 'kind': 'execution',
                                            'type': 'ValueError', 'error': f'{label} failed'}]
        return '', {'label': label, 'timedOut': timed_out, 'failures': failures}


class BuildRetryTests(unittest.TestCase):
    def build(self, outcomes, budget=None):
        with tempfile.TemporaryDirectory() as name:
            commands, environment, error = FakeCommands(Path(name), outcomes), {}, None
            with patch.object(runner.time, 'sleep') as sleep:
                try:
                    runner.build_application(commands, environment, ['flutter'], budget or Budget(), {})
                except runner.CommandFailure as failure:
                    error = failure
            return commands.labels, environment, sleep.call_args_list, error

    def test_transient_failures_are_retried_twice_with_backoff(self):
        labels, environment, sleeps, error = self.build([(SWIFTPM_504, False), (SQLITE_HASH, False), (None, False)])
        self.assertIsNone(error)
        self.assertEqual(labels, ['flutter-build', 'flutter-build-retry-1', 'flutter-build-retry-2'])
        self.assertEqual([call.args[0] for call in sleeps], list(runner.BUILD_RETRY_DELAYS))
        self.assertEqual([entry['reason'] for entry in environment['buildRetries']],
                         ['swiftpm-download', 'native-asset-download'])

    def test_the_last_transient_failure_is_reported_without_a_fourth_build(self):
        labels, _, _, error = self.build([(SWIFTPM_504, False)] * 3)
        self.assertEqual(len(labels), 3)
        self.assertEqual(error.command_record['label'], 'flutter-build-retry-2')

    def test_compiler_failures_timeouts_and_short_budgets_are_not_retried(self):
        for outcome, budget in [(('error: type mismatch', False), Budget()),
                                ((SWIFTPM_504, True), Budget()),
                                ((SWIFTPM_504, False), Budget(runner.MINIMUM_COUNT_SECONDS))]:
            with self.subTest(outcome=outcome[0][:20], timed=outcome[1]):
                labels, environment, sleeps, error = self.build([outcome], budget)
                self.assertEqual(labels, ['flutter-build'])
                self.assertEqual(error.command_record['label'], 'flutter-build')
                self.assertNotIn('buildRetries', environment)
                self.assertEqual(sleeps, [])


class CountBudgetTests(unittest.TestCase):
    def test_without_a_deadline_the_standalone_budgets_are_unchanged(self):
        budget = runner.CountBudget(clock=lambda: 0.0)
        self.assertEqual(budget.build(), runner.BUILD_SECONDS)
        self.assertEqual(budget.report(), runner.FONT_REPORT_SECONDS)

    def test_a_deadline_shrinks_the_count_but_keeps_its_cleanup_reserve(self):
        budget = runner.CountBudget(10_000 + 1500, clock=lambda: 0.0, wall=lambda: 10_000.0)
        self.assertEqual(budget.left(), 1500 - runner.CLEANUP_RESERVE_SECONDS)
        self.assertEqual(budget.build(), budget.left() - runner.LAUNCH_SECONDS)
        self.assertEqual(budget.report(), min(runner.FONT_REPORT_SECONDS, budget.left()))

    def test_an_exhausted_step_budget_is_not_run_instead_of_killed(self):
        with self.assertRaisesRegex(ValueError, 'NOT_RUN'):
            runner.CountBudget(10_000 + runner.CLEANUP_RESERVE_SECONDS + 599, wall=lambda: 10_000.0)

    def test_expired_build_and_report_windows_are_failures(self):
        clock = [0.0]
        budget = runner.CountBudget(clock=lambda: clock[0])
        clock[0] = budget.end - runner.LAUNCH_SECONDS
        with self.assertRaisesRegex(ValueError, 'build'):
            budget.build()
        clock[0] = budget.end
        with self.assertRaisesRegex(ValueError, 'report'):
            budget.report()

    def test_three_observed_counts_fit_the_workflow_step(self):
        # Observed worst counts without cache misses: build, Simulator preparation, drive.
        observed = [(928 + 300 + 180), (398 + 330 + 160), (300 + 380 + 180)]
        step_seconds = 95 * 60
        self.assertLess(sum(observed) + 3 * runner.CLEANUP_RESERVE_SECONDS, step_seconds)


class BuildIdentityTests(unittest.TestCase):
    def test_a_checkpoint_from_another_build_cannot_disarm_startup(self):
        with tempfile.TemporaryDirectory() as name:
            startup = runner.FontProbeStartup(Path(name), '3' * 40, 'this-build')
            startup.start()
            try:
                process = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(1)'],
                                           start_new_session=True)
                self.addCleanup(process.wait, timeout=3)
                self.addCleanup(runner.signal_group, process.pid, signal.SIGTERM)
                launch = startup.launch_environment(5)
                self.assertEqual(launch['OTZARIA_FONT_PROBE_INSTANCES'], '5')
                self.assertNotIn('IOS_FONT_PROBE_TOKEN', startup.defines)
                for build, accepted in [('another-build', False), (None, False), ('this-build', True)]:
                    body = {'runId': launch['IOS_FONT_PROBE_GENERATION'], 'hostPid': process.pid,
                            'appBootToken': 'boot', 'hostExecutable': sys.executable,
                            'nativeFork': '3' * 40, 'firstFrameRasterized': True, 'buildId': build}
                    request = urllib.request.Request(
                        launch['IOS_FONT_PROBE_COORDINATOR'] + '/checkpoint', data=json.dumps(body).encode(),
                        headers={'X-Apple-Quiet-Token': launch['IOS_FONT_PROBE_TOKEN']})
                    with self.subTest(build=build):
                        if accepted:
                            urllib.request.urlopen(request, timeout=3).close()
                            self.assertIsNotNone(startup.coordinator.app_checkpoint_at)
                        else:
                            with self.assertRaises(urllib.error.HTTPError) as rejected:
                                urllib.request.urlopen(request, timeout=3)
                            rejected.exception.close()
                            self.assertIsNone(startup.coordinator.app_checkpoint_at)
            finally:
                runner.shutdown_server(startup.server)
                startup.server.server_close()


if __name__ == '__main__':
    unittest.main()
