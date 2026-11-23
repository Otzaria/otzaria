import json
from pathlib import Path
import tempfile
import unittest

from validate_ios_export import REVIEWED_SOURCES, TEST_SOURCES, sha256, validate


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "evidence"
        self.source = Path(self.temporary.name) / "source"
        (self.root / "probe").mkdir(parents=True)
        for name in REVIEWED_SOURCES:
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture\n")
        for path in TEST_SOURCES.values():
            (self.source / path).write_text("func testOwnership() {}\n")
        self.commit = "a" * 40
        files = {name: sha256(self.source / name) for name in REVIEWED_SOURCES}
        self.write("source.json", {"commit": self.commit, "tree": "b" * 40, "filesBefore": files, "filesAfter": files})
        self.write("flutter.json", {"frameworkVersion": "3.47.7", "frameworkRevision": "abaf9c523780a608bd46686fd5e53740a07077f8"})
        for stage, action in (("build", "build-for-testing"), ("tests", "test-without-building")):
            self.write(stage + ".command.json", {"exitCode": 0, "timedOut": False, "arguments": ["xcodebuild", action]})
        identifier = "AABBCCDD-1111-2222-3333-123456789012"
        self.write("simulator.json", {"udid": identifier, "runtime": {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-0"}})
        self.write("cleanup.json", {"ownedSimulatorDeleted": True, "udid": identifier})
        (self.root / "build.log").write_text("build passed\n")
        self.lines = [f"Test Case '-[{suite}.{suite} testOwnership]' passed (0.1 seconds).\n" for suite in TEST_SOURCES]
        (self.root / "tests.log").write_text("".join(self.lines))
        for index, (case_name, status) in enumerate((("files-save", "saved"), ("files-cancel", "cancelled"))):
            self.write("probe/" + case_name + ".json", {
                "schemaVersion": 1, "case": case_name, "backend": "MobilePdfExportService.instance",
                "picker": "UIDocumentPickerViewController.forExporting.asCopy",
                "passed": True, "destinationVerified": True, "stagingAbsent": True,
                "fixtureBytes": 200, "expectedSha256": "c" * 64,
                "actualSha256": "c" * 64 if index == 0 else None,
                "outcome": {"version": 1, "operationId": str(index) * 32, "status": status, "cleanupStatus": "notNeeded",
                            "documentUri": "file:///private/app/Documents/saved.pdf" if index == 0 else None,
                            "displayName": "saved.pdf" if index == 0 else None},
            })

    def write(self, name, value):
        (self.root / name).write_text(json.dumps(value))

    def update(self, name, change):
        value = json.loads((self.root / name).read_text())
        change(value)
        self.write(name, value)

    def test_complete_native_and_real_files_evidence_passes(self):
        report = validate(self.root, self.source, self.commit)
        self.assertEqual(report["nativeContractTests"], 1)
        self.assertEqual(report["realFilesUITests"], 1)
        self.assertEqual(report["status"], "passed")

    def test_missing_or_skipped_native_case_is_not_success(self):
        for log in (self.lines[0], "".join(self.lines).replace("passed", "skipped", 1), "".join(self.lines).replace("passed", "failed", 1)):
            with self.subTest(log=log):
                (self.root / "tests.log").write_text(log)
                with self.assertRaises(ValueError):
                    validate(self.root, self.source, self.commit)

    def test_retry_cannot_hide_a_failure(self):
        (self.root / "tests.log").write_text("".join(self.lines) + self.lines[0])
        with self.assertRaisesRegex(ValueError, "duplicate/retried"):
            validate(self.root, self.source, self.commit)

    def test_changed_source_and_sdk_are_rejected(self):
        (self.source / REVIEWED_SOURCES[0]).write_text("changed")
        with self.assertRaisesRegex(ValueError, "source bytes"):
            validate(self.root, self.source, self.commit)
        (self.source / REVIEWED_SOURCES[0]).write_text("fixture\n")
        self.update("flutter.json", lambda value: value.update(frameworkVersion="newer"))
        with self.assertRaisesRegex(ValueError, "Flutter version"):
            validate(self.root, self.source, self.commit)

    def test_test_timeout_is_not_a_pass(self):
        self.update("tests.command.json", lambda value: value.update(timedOut=True))
        with self.assertRaisesRegex(ValueError, "did not finish"):
            validate(self.root, self.source, self.commit)

    def test_saved_bytes_and_verified_name_are_required(self):
        self.update("probe/files-save.json", lambda value: value.update(actualSha256="d" * 64))
        with self.assertRaisesRegex(ValueError, "saved bytes"):
            validate(self.root, self.source, self.commit)
        self.update("probe/files-save.json", lambda value: value.update(actualSha256="c" * 64))
        self.update("probe/files-save.json", lambda value: value["outcome"].update(displayName="requested-but-unverified.pdf"))
        with self.assertRaisesRegex(ValueError, "saved name"):
            validate(self.root, self.source, self.commit)

    def test_missing_cancel_receipt_is_not_ui_coverage(self):
        (self.root / "probe/files-cancel.json").unlink()
        with self.assertRaises(FileNotFoundError):
            validate(self.root, self.source, self.commit)

    def test_unreleased_staging_and_unknown_cleanup_are_rejected(self):
        self.update("probe/files-save.json", lambda value: value.update(stagingAbsent=False))
        with self.assertRaisesRegex(ValueError, "staging is unverified"):
            validate(self.root, self.source, self.commit)
        self.update("probe/files-save.json", lambda value: value.update(stagingAbsent=True))
        self.update("cleanup.json", lambda value: value.update(ownedSimulatorDeleted=False))
        with self.assertRaisesRegex(ValueError, "Simulator cleanup"):
            validate(self.root, self.source, self.commit)


if __name__ == "__main__":
    unittest.main()
