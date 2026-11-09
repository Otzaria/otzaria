import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "apple_quiet_swiftpm_retry", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class SwiftPMRetryClassificationTests(unittest.TestCase):
    def test_retry_only_transport_errors_during_package_resolution(self):
        failures = [
            'xcodebuild: error: Could not resolve package dependencies:\n'
            "failed downloading 'https://github.com/espresso3389/pdfium-xcframework/releases/download/v158/PDFium.zip' "
            'downloadError("Could not connect to the server.")',
            'Xcode failed to resolve Swift Package Manager dependencies:\n'
            "failed downloading 'https://github.com/getsentry/sentry-cocoa/releases/download/8.58.4/asset.zip' "
            'downloadError("HTTP 503")',
            # Run 42582694810: the gateway status arrives without an "HTTP" prefix.
            'An error occurred when adding Swift Package Manager integration:\n'
            '  Error: Xcode failed to resolve Swift Package Manager dependencies:\n'
            'xcodebuild: error: Could not resolve package dependencies:\n'
            "  failed downloading 'https://github.com/getsentry/sentry-cocoa/releases/download/8.58.4/"
            "Sentry.xcframework.zip' which is required by binary target 'Sentry': "
            'badResponseStatusCode(504)\n  fatalError',
        ]
        for output in failures:
            with self.subTest(output=output):
                self.assertTrue(runner.transient_swiftpm_download_failure(output))

    def test_no_retry_for_app_failure_or_package_semantic_errors(self):
        failures = [
            '',
            'flutter drive failed with exit 1',
            'Could not resolve package dependencies: syntax error in Package.swift',
            'Xcode failed to resolve Swift Package Manager dependencies: '
            "failed downloading 'https://github.com/x/y.zip' checksum mismatch",
            'Could not resolve package dependencies: '
            "failed downloading 'https://github.com/x/y.zip' badResponseStatusCode(404)",
            'Could not resolve package dependencies: '
            "failed downloading 'https://github.com/x/y.zip' HTTP 5030",
            "failed downloading 'https://github.com/x/y.zip' HTTP 503",
            'Plugin WebView boot timed out after app checkpoint: '
            "downloadError('Could not connect to the server')",
            'Could not resolve package dependencies: fatalError',
        ]
        for output in failures:
            with self.subTest(output=output):
                self.assertFalse(runner.transient_swiftpm_download_failure(output))

    def test_preserved_logs_are_read_without_overwriting(self):
        import tempfile
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            (directory / 'build-ios-probe.stdout.log').write_text(
                "failed downloading 'https://github.com/x/y.zip' ")
            (directory / 'build-ios-probe.stderr.log').write_text(
                'Could not resolve package dependencies: HTTP 503')
            report = runner.swiftpm_log(directory, 'build-ios-probe')
            self.assertTrue(runner.transient_swiftpm_download_failure(report))
            self.assertTrue((directory / 'build-ios-probe.stderr.log').exists())


TRANSIENT = ("Could not resolve package dependencies: "
             "failed downloading 'https://github.com/x/y.zip' badResponseStatusCode(503)")


class SwiftPMBackoffTests(unittest.TestCase):
    def build(self, outcomes, *, budget=3600):
        import subprocess
        import tempfile
        calls, sleeps = [], []

        def build_ios_probe(directory, timeout, label):
            calls.append((label, timeout))
            outcome = outcomes[len(calls) - 1]
            (directory / f'{label}.stderr.log').write_text(outcome or '')
            if outcome is not None:
                raise subprocess.CalledProcessError(65, ['flutter', 'build', 'ios'])
            return directory / 'Runner.app'

        with tempfile.TemporaryDirectory() as name, \
                patch.object(runner, 'build_ios_probe', side_effect=build_ios_probe), \
                patch.object(runner.time, 'sleep', side_effect=sleeps.append):
            directory, environment = Path(name), {}
            deadline = runner.time.monotonic() + budget
            try:
                result = runner.build_ios_probe_with_retries(directory, environment, deadline)
            except subprocess.CalledProcessError as error:
                result = error
            saved = json.loads((directory / 'environment.json').read_text()) \
                if (directory / 'environment.json').exists() else {}
        return result, calls, sleeps, environment, saved

    def test_download_failures_back_off_then_succeed(self):
        result, calls, sleeps, environment, saved = self.build([TRANSIENT, TRANSIENT, None])
        self.assertEqual(result.name, 'Runner.app')
        self.assertEqual([label for label, _ in calls],
                         ['build-ios-probe', 'build-ios-probe-retry', 'build-ios-probe-retry-2'])
        self.assertEqual(sleeps, [15, 45])
        self.assertEqual([r['previousLog'] for r in environment['swiftpmRetries']],
                         ['build-ios-probe.stdout.log', 'build-ios-probe-retry.stdout.log'])
        self.assertEqual(saved, environment)

    def test_retries_are_bounded(self):
        result, calls, sleeps, environment, _ = self.build([TRANSIENT] * 4)
        self.assertIsInstance(result, Exception)
        self.assertEqual(len(calls), 3)
        self.assertEqual(sleeps, [15, 45])
        self.assertEqual(len(environment['swiftpmRetries']), 2)

    def test_build_failure_is_never_retried(self):
        result, calls, sleeps, environment, _ = self.build(['error: Swift compiler error', None])
        self.assertIsInstance(result, Exception)
        self.assertEqual(len(calls), 1)
        self.assertEqual(sleeps, [])
        self.assertNotIn('swiftpmRetries', environment)

    def test_backoff_never_outlives_the_deadline(self):
        result, calls, sleeps, _, _ = self.build([TRANSIENT, None], budget=30)
        self.assertEqual(len(calls), 2)
        self.assertLessEqual(sleeps[0], 30)
        self.assertLessEqual(calls[1][1], 30)


if __name__ == '__main__':
    unittest.main()
