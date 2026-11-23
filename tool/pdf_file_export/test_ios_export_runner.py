import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import ios_export_runner as runner


class RunnerCleanupTests(unittest.TestCase):
    def test_native_tests_run_once_without_xcode_repetition_options(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary).resolve()
            (source / "native.swift").write_text("reviewed source")
            root = source / "evidence"
            commit = "a" * 40
            receipt = {"udid": "12345678-1234-1234-1234-123456789ABC"}
            commands = []

            def output(arguments, **_):
                if arguments == ["git", "rev-parse", "HEAD"]:
                    return commit
                if arguments == ["git", "rev-parse", "HEAD^{tree}"]:
                    return "b" * 40
                if arguments == ["flutter", "--version", "--machine"]:
                    return "{}"
                return ""

            def run_logged(arguments, *_args, **_kwargs):
                commands.append(arguments)
                if "-test-iterations" in arguments:
                    if arguments[arguments.index("-test-iterations") + 1] == "1":
                        raise RuntimeError("Must specify -test-iterations with more than 1 iteration.")

            previous = Path.cwd()
            try:
                with (
                    patch.object(runner, "SOURCE_FILES", ("native.swift",)),
                    patch.object(runner, "output", side_effect=output),
                    patch.object(runner, "create_simulator", return_value=receipt),
                    patch.object(runner, "run_logged", side_effect=run_logged),
                    patch.object(runner, "collect_probe_receipts"),
                    patch.object(runner, "cleanup_simulator") as cleanup,
                    patch.object(runner, "validate", return_value={"status": "passed"}),
                ):
                    runner.run(root, source, commit)
                    tests = [c for c in commands if c[:2] == ["xcodebuild", "test-without-building"]]
                    self.assertEqual(len(tests), 1)
                    self.assertFalse(set(tests[0]) & {
                        "-test-iterations", "-retry-tests-on-failure",
                        "-run-tests-until-failure", "-test-repetition-relaunch-enabled",
                    })
                    self.assertEqual(tests[0][tests[0].index("-parallel-testing-enabled") + 1], "NO")
                    self.assertIn("-only-testing:PdfFileExportTests", tests[0])
                    self.assertIn("-only-testing:PdfFileExportUITests", tests[0])
                    cleanup.assert_called_once_with(receipt)
            finally:
                os.chdir(previous)

    def test_flutter_configuration_owns_dependency_installation(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary).resolve()
            (source / "native.swift").write_text("reviewed source")
            root = source / "evidence"
            commit = "a" * 40
            receipt = {"udid": "12345678-1234-1234-1234-123456789ABC"}
            commands = []

            def output(arguments, **_):
                if arguments == ["git", "rev-parse", "HEAD"]:
                    return commit
                if arguments == ["git", "rev-parse", "HEAD^{tree}"]:
                    return "b" * 40
                if arguments == ["flutter", "--version", "--machine"]:
                    return "{}"
                return ""

            def run_logged(arguments, *_args, **_kwargs):
                commands.append(arguments)
                if arguments[0] == "pod":
                    raise RuntimeError("No podspec found for SPM-only sentry_flutter")

            previous = Path.cwd()
            try:
                with (
                    patch.object(runner, "SOURCE_FILES", ("native.swift",)),
                    patch.object(runner, "output", side_effect=output),
                    patch.object(runner, "create_simulator", return_value=receipt),
                    patch.object(runner, "run_logged", side_effect=run_logged),
                    patch.object(runner, "collect_probe_receipts"),
                    patch.object(runner, "cleanup_simulator") as cleanup,
                    patch.object(runner, "validate", return_value={"status": "passed"}),
                ):
                    runner.run(root, source, commit)
                    configure = next(i for i, c in enumerate(commands) if c[:3] == ["flutter", "build", "ios"])
                    build = next(i for i, c in enumerate(commands) if c[:2] == ["xcodebuild", "build-for-testing"])
                    self.assertIn("--config-only", commands[configure])
                    self.assertLess(configure, build)
                    self.assertFalse(any(c[0] == "pod" for c in commands))
                    cleanup.assert_called_once_with(receipt)
            finally:
                os.chdir(previous)

    def test_source_evidence_failure_still_cleans_owned_simulator(self):
        self._run_with_evidence_failure(primary=None)

    def test_secondary_evidence_failure_preserves_build_failure(self):
        self._run_with_evidence_failure(primary=RuntimeError("native build failed"))

    def _run_with_evidence_failure(self, primary):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary).resolve()
            (source / "native.swift").write_text("reviewed source")
            root = source / "evidence"
            commit = "a" * 40
            evidence_error = OSError("reviewed source could not be read after build")
            receipt = {"udid": "12345678-1234-1234-1234-123456789ABC"}

            def output(arguments, **_):
                if arguments == ["git", "rev-parse", "HEAD"]:
                    return commit
                if arguments == ["git", "rev-parse", "HEAD^{tree}"]:
                    return "b" * 40
                if arguments == ["flutter", "--version", "--machine"]:
                    return "{}"
                return ""

            def run_logged(arguments, *_args, **_kwargs):
                if primary is not None and arguments[:2] == ["xcodebuild", "build-for-testing"]:
                    raise primary

            previous = Path.cwd()
            try:
                with (
                    patch.object(runner, "SOURCE_FILES", ("native.swift",)),
                    patch.object(runner, "digest", side_effect=["c" * 64, evidence_error]),
                    patch.object(runner, "output", side_effect=output),
                    patch.object(runner, "create_simulator", return_value=receipt),
                    patch.object(runner, "run_logged", side_effect=run_logged),
                    patch.object(runner, "collect_probe_receipts") as collect,
                    patch.object(runner, "cleanup_simulator") as cleanup,
                    patch.object(runner, "validate") as validate,
                ):
                    with self.assertRaises(type(primary or evidence_error)) as caught:
                        runner.run(root, source, commit)
                    self.assertIs(caught.exception, primary or evidence_error)
                    collect.assert_called_once_with(root, receipt)
                    cleanup.assert_called_once_with(receipt)
                    validate.assert_not_called()
                    self.assertTrue(json.loads((root / "cleanup.json").read_text())["ownedSimulatorDeleted"])
            finally:
                os.chdir(previous)

    def test_receipt_write_failure_cleans_the_newly_created_simulator(self):
        runtime = {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-1", "version": "26.1", "isAvailable": True}
        device_type = "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
        device = {"deviceTypeIdentifier": device_type, "isAvailable": True}
        identifier = "12345678-1234-1234-1234-123456789ABC"
        error = OSError("cannot persist receipt")
        with (
            patch.dict(os.environ, {"GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1"}),
            patch.object(runner, "output", side_effect=[
                json.dumps({"runtimes": [runtime]}),
                json.dumps({"devices": {runtime["identifier"]: [device]}}),
                identifier,
            ]),
            patch.object(runner, "save", side_effect=error),
            patch.object(runner, "cleanup_simulator") as cleanup,
        ):
            with self.assertRaises(OSError) as caught:
                runner.create_simulator(Path("unused"))
            self.assertIs(caught.exception, error)
            cleanup.assert_called_once_with({
                "udid": identifier, "name": "otzaria-pdf-export-123-1",
                "runtime": runtime, "deviceType": device_type,
            })

    def test_foreign_simulator_receipt_is_never_deleted(self):
        receipt = {"udid": "12345678-1234-1234-1234-123456789ABC", "name": "someone-elses-device"}
        with (
            patch.dict(os.environ, {"GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1"}),
            patch.object(runner, "output") as output,
        ):
            with self.assertRaisesRegex(RuntimeError, "invalid Simulator receipt"):
                runner.cleanup_simulator(receipt)
            output.assert_not_called()

    def test_changed_simulator_identity_is_never_deleted(self):
        identifier = "12345678-1234-1234-1234-123456789ABC"
        runtime = "com.apple.CoreSimulator.SimRuntime.iOS-26-1"
        device_type = "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
        receipt = {"udid": identifier, "name": "otzaria-pdf-export-123-1", "runtime": {"identifier": runtime}, "deviceType": device_type}
        with (
            patch.dict(os.environ, {"GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1"}),
            patch.object(runner, "output", return_value=json.dumps({"devices": {runtime: [{
                "udid": identifier, "name": receipt["name"], "deviceTypeIdentifier": "a-different-model", "state": "Booted",
            }]}})) as output,
        ):
            with self.assertRaisesRegex(RuntimeError, "identity changed"):
                runner.cleanup_simulator(receipt)
            output.assert_called_once_with(["xcrun", "simctl", "list", "-j", "devices"])


if __name__ == "__main__":
    unittest.main()
