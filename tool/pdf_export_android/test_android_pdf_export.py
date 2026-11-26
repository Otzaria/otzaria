import copy
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr

from .run_android_pdf_export import APP, ENGINE_REVISION, EXPECTED_CASES, FRAMEWORK_REVISION, finalize_run, instrumentation_report, provider_blocks, source_receipt, validate_report


def complete_report():
    cases = {name: {} for name in EXPECTED_CASES}
    for name in ("documents_ui_new_copy", "pipe_bytes_and_pdf_parity"):
        cases[name] = {
            "result": {"status": "saved", "displayName": "existing (2).pdf"},
            "source": {"sha256": "a" * 64, "length": 16 * 1024 * 1024 + 512, "exists": False, "directoryExists": False},
            "provider": {"documents": [{"id": "copy-1", "sha256": "a" * 64, "bytes": 16 * 1024 * 1024 + 512, "closed": True}], "events": []},
            "bluePixels": 6400,
            "realDocumentsUi": name == "documents_ui_new_copy",
            "pickerPackage": "com.google.android.documentsui" if name == "documents_ui_new_copy" else None,
        }
    for suffix, cleanup in (("deleted", "deleted"), ("unsupported_cleanup", "unsupported"), ("failed_cleanup", "failed")):
        cases[f"cancel_blocked_write_{suffix}"] = {
            "result": {"status": "cancelled", "cleanupStatus": cleanup, "residualDocument": None if cleanup == "deleted" else "content://fixture/new", "residualDisplayName": None if cleanup == "deleted" else "עותק.pdf"},
            "partialBytes": 65536, "sourceBytes": 16 * 1024 * 1024 + 512,
            "ack": {"accepted": True}, "sourceHeldAfterAck": True, "terminalAtAck": False,
        }
    cases["saved_before_late_cancel_delivery"] = {"ack": {"accepted": False}, "result": {"status": "saved"}}
    cases["invalid_created_document"] = {
        "result": {"status": "failed", "errorCode": "invalid_document", "cleanupStatus": "notNeeded", "residualDocument": None},
        "provider": {"events": ["create-enter"]},
    }
    for name in ("detach_before_native_acquire", "detach_while_picker_open"):
        cases[name] = {"dartFinallyUsed": False, "result": {"status": "cancelled"}}
    cases["activity_detach_during_write"] = {"dartEngineDestroyed": True, "stagingRemoved": True,
                                             "engineDestroyCallback": True, "engineStillRegistered": False, "engineId": 1}
    for kind in ("leaf", "child", "root"):
        cases[f"staging_{kind}_replacement"] = {"replacementPreserved": True, "result": {"cleanupError": "staging_cleanup_failed: changed identity"}}
    return {"schema": 1, "passed": True, "applicationId": APP, "sdk": 34,
            "cases": [{"name": name, "passed": True, "evidence": cases[name]} for name in sorted(EXPECTED_CASES)]}


class EvidenceContracts(unittest.TestCase):
    def setUp(self):
        self.report = complete_report()

    def evidence(self, name):
        return next(row["evidence"] for row in self.report["cases"] if row["name"] == name)

    def test_complete_contract(self):
        self.assertEqual(validate_report(self.report), 21)

    def test_instrumentation_crash_is_not_masked_by_missing_json(self):
        completed = subprocess.CompletedProcess([], 0, "INSTRUMENTATION_RESULT: shortMsg=Process crashed.\nINSTRUMENTATION_CODE: 0\n", "")
        with self.assertRaisesRegex(ValueError, "Process crashed"):
            instrumentation_report(completed, "cat: native-report.json: No such file or directory\n")

    def test_normal_instrumentation_requires_a_parseable_native_report(self):
        completed = subprocess.CompletedProcess([], 0, "INSTRUMENTATION_CODE: -1\n", "")
        self.assertEqual(instrumentation_report(completed, json.dumps(self.report)), self.report)
        with self.assertRaisesRegex(ValueError, "without a JSON native report"):
            instrumentation_report(completed, "")

    def test_unowned_document_must_not_be_opened_or_deleted(self):
        for event in ("open-request:fixture-root", "delete-request:fixture-root"):
            self.report = complete_report()
            self.evidence("invalid_created_document")["provider"]["events"].append(event)
            with self.assertRaisesRegex(ValueError, "Unowned document was opened or deleted"):
                validate_report(self.report)

    def test_missing_or_duplicate_case_is_not_skipped(self):
        self.report["cases"].pop()
        with self.assertRaisesRegex(ValueError, "Missing, duplicate"):
            validate_report(self.report)
        self.report = complete_report()
        self.report["cases"].append(copy.deepcopy(self.report["cases"][0]))
        with self.assertRaisesRegex(ValueError, "Missing, duplicate"):
            validate_report(self.report)

    def test_failed_case_and_top_level_failure_cannot_pass(self):
        self.report["cases"][0]["passed"] = False
        with self.assertRaisesRegex(ValueError, "case failed"):
            validate_report(self.report)
        self.report = complete_report()
        self.report["passed"] = False
        with self.assertRaisesRegex(ValueError, "did not pass"):
            validate_report(self.report)

    def test_foreign_app_or_emulator_is_rejected(self):
        for key, value in (("applicationId", "org.otzaria.otzaria"), ("sdk", 33)):
            self.report = complete_report()
            self.report[key] = value
            with self.assertRaises(ValueError):
                validate_report(self.report)

    def test_scripted_picker_cannot_satisfy_real_ui_case(self):
        self.evidence("documents_ui_new_copy")["realDocumentsUi"] = False
        with self.assertRaisesRegex(ValueError, "Actual DocumentsUI"):
            validate_report(self.report)
        self.report = complete_report()
        self.evidence("documents_ui_new_copy")["provider"]["events"].append("test-grant")
        with self.assertRaisesRegex(ValueError, "fixture URI grant"):
            validate_report(self.report)

    def test_copy_must_have_matching_hash_and_nontrivial_render(self):
        self.evidence("pipe_bytes_and_pdf_parity")["provider"]["documents"][0]["sha256"] = "b" * 64
        with self.assertRaisesRegex(ValueError, "parity/size"):
            validate_report(self.report)
        self.report = complete_report()
        self.evidence("pipe_bytes_and_pdf_parity")["bluePixels"] = 0
        with self.assertRaisesRegex(ValueError, "visibly rendered"):
            validate_report(self.report)

    def test_cancellation_requires_positive_partial_write(self):
        evidence = self.evidence("cancel_blocked_write_deleted")
        for partial in (0, evidence["sourceBytes"]):
            evidence["partialBytes"] = partial
            with self.assertRaisesRegex(ValueError, "real partial write"):
                validate_report(self.report)

    def test_ack_cannot_release_source_or_be_terminal(self):
        for key, value in (("sourceHeldAfterAck", False), ("terminalAtAck", True)):
            self.report = complete_report()
            self.evidence("cancel_blocked_write_deleted")[key] = value
            with self.assertRaisesRegex(ValueError, "ACK released"):
                validate_report(self.report)

    def test_failed_cleanup_must_retain_residual(self):
        self.evidence("cancel_blocked_write_failed_cleanup")["result"]["residualDocument"] = None
        with self.assertRaisesRegex(ValueError, "residual"):
            validate_report(self.report)

    def test_late_cancel_cannot_override_save(self):
        self.evidence("saved_before_late_cancel_delivery")["ack"]["accepted"] = True
        with self.assertRaisesRegex(ValueError, "Late cancel"):
            validate_report(self.report)

    def test_activity_detach_must_clean_without_dart(self):
        self.evidence("activity_detach_during_write")["stagingRemoved"] = False
        with self.assertRaisesRegex(ValueError, "Activity detach"):
            validate_report(self.report)

    def test_activity_flag_alone_does_not_prove_engine_teardown(self):
        self.evidence("activity_detach_during_write")["engineStillRegistered"] = True
        with self.assertRaisesRegex(ValueError, "independently observed"):
            validate_report(self.report)

    def test_replaced_staging_must_survive(self):
        self.evidence("staging_root_replacement")["replacementPreserved"] = False
        with self.assertRaisesRegex(ValueError, "Replaced staging"):
            validate_report(self.report)

    def test_permission_parser_keeps_provider_attributes_separate(self):
        tree = """  E: application (line=1)
    E: provider (line=2)
      A: android:name="Documents"
      A: android:permission="android.permission.MANAGE_DOCUMENTS"
      E: intent-filter (line=3)
        E: action (line=4)
    E: provider (line=5)
      A: android:name="Control"
      A: android:permission="signature.permission"
    E: activity (line=6)
"""
        blocks = provider_blocks(tree)
        self.assertEqual(len(blocks), 2)
        self.assertIn("MANAGE_DOCUMENTS", blocks[0])
        self.assertNotIn("signature.permission", blocks[0])
        self.assertNotIn("MANAGE_DOCUMENTS", blocks[1])


class FinalizationContracts(unittest.TestCase):
    def test_secondary_logcat_failure_preserves_primary_and_stops_both_apps(self):
        original = ValueError("original native failure")
        calls = []

        def broken_logcat():
            raise subprocess.TimeoutExpired("adb logcat", 60)

        with redirect_stderr(io.StringIO()), self.assertRaisesRegex(ValueError, "original native failure"):
            try:
                raise original
            finally:
                finalize_run([
                    ("logcat", broken_logcat),
                    ("source", lambda: calls.append("source")),
                    ("app", lambda: calls.append("app")),
                    ("fixture", lambda: calls.append("fixture")),
                ], original)
        self.assertEqual(calls, ["source", "app", "fixture"])

    def test_cleanup_failures_cannot_turn_an_incomplete_receipt_green(self):
        calls = []

        def cannot_write():
            raise OSError("disk full")

        with redirect_stderr(io.StringIO()), self.assertRaisesRegex(RuntimeError, "disk full"):
            finalize_run([("receipt", cannot_write), ("stop app", lambda: calls.append("app")),
                          ("stop fixture", lambda: calls.append("fixture"))])
        self.assertEqual(calls, ["app", "fixture"])


class SourceContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.name", "PDF export contract")
        self.git("config", "user.email", "contract@example.invalid")
        self.service = self.root / "lib/utils/file/mobile_pdf_export_service.dart"
        self.service.parent.mkdir(parents=True)
        self.service.write_text("service fixture\n")
        (self.root / "pubspec.yaml").write_text("name: fixture\n")
        (self.root / "pubspec.lock").write_text("locked fixture\n")
        self.git("add", "lib", "pubspec.yaml", "pubspec.lock")
        self.git("commit", "-qm", "source fixture")
        self.sdk = self.root / "sdk.json"
        self.sdk.write_text(json.dumps({"frameworkVersion": "3.47.7", "dartSdkVersion": "3.13.5",
                                       "frameworkRevision": FRAMEWORK_REVISION, "engineRevision": ENGINE_REVISION}))

    def git(self, *arguments):
        return subprocess.run(["git", *arguments], cwd=self.root, capture_output=True, text=True, check=True).stdout.strip()

    def test_clean_receipt_matches_exact_head_blobs_and_pins(self):
        receipt = source_receipt(self.root, self.sdk)
        self.assertEqual(receipt["commit"], self.git("rev-parse", "HEAD"))
        self.assertEqual(receipt["blobs"]["lib/utils/file/mobile_pdf_export_service.dart"],
                         self.git("rev-parse", "HEAD:lib/utils/file/mobile_pdf_export_service.dart"))
        self.assertIn("pubspec.yaml", receipt["files"])
        self.assertIn("pubspec.lock", receipt["files"])

    def test_uncommitted_source_or_lock_cannot_be_attributed_to_head(self):
        self.service.write_text("different implementation\n")
        with self.assertRaisesRegex(ValueError, "source is dirty"):
            source_receipt(self.root, self.sdk)
        self.git("restore", "lib")
        (self.root / "pubspec.lock").write_text("different dependency\n")
        with self.assertRaisesRegex(ValueError, "source is dirty"):
            source_receipt(self.root, self.sdk)

    def test_untracked_native_source_is_rejected(self):
        unexpected = self.root / "android/app/src/main/kotlin/Injected.kt"
        unexpected.parent.mkdir(parents=True)
        unexpected.write_text("untracked native source\n")
        with self.assertRaisesRegex(ValueError, "source is dirty"):
            source_receipt(self.root, self.sdk)

    def test_same_sdk_version_with_other_revision_is_rejected(self):
        data = json.loads(self.sdk.read_text())
        data["frameworkRevision"] = "0" * 40
        self.sdk.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "framework/engine revision"):
            source_receipt(self.root, self.sdk)


if __name__ == "__main__":
    unittest.main()
