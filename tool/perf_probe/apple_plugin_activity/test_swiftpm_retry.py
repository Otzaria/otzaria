import importlib.util
from pathlib import Path
import unittest

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


if __name__ == '__main__':
    unittest.main()
