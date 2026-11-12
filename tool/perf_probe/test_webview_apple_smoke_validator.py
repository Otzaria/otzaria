"""Fail-closed contracts for real Apple WebView fixture acceptance."""
import copy
import tempfile
from pathlib import Path
import json
import unittest

from tool.perf_probe import validate_webview_apple_smoke as subject

SHA = "a" * 40
FIXTURE_SHA = "f" * 64


def valid_wrapper(platform="macos"):
    mode = "profile" if platform == "macos" else "debug"
    records = [{"type": "meta", "os": platform, "buildMode": mode,
                "appCommit": SHA, "flutterVersion": "3.47.7", "tabs": 3,
                "idleMs": 3000, "osVersion": "native runner", "runId": "test-run",
                "fixtureSha256": FIXTURE_SHA}]
    for name, state in subject.EXPECTED.items():
        if state == "passed":
            records.append({"type": "phase", "name": name, "status": "passed",
                            "durationMs": 100.0})
        else:
            records.append({"type": "phase", "name": name, "status": "skipped",
                            "reason": "No supported host API in this fixture"})
    records.extend({"type": "webviewBackend", "event": "created", "runId": "test-run",
                    "attachmentId": f"host-{i}", "backend": {
                        "availability": "unsupported", "verified": False,
                        "observed": None}} for i in range(3))
    records.append({"type": "nativeWindow", "availability": (
        "collected" if platform == "macos" else "unsupported"),
        "ready": True if platform == "macos" else None})
    records.append({"type": "heartbeatObservation",
                    "beforeHide": {"schemaVersion": 1, "revision": 1,
                                   "draft": "עמוד טיוטה"},
                    "afterResume": {"schemaVersion": 1, "revision": 1,
                                    "draft": "עמוד טיוטה"}})
    records.append({"type": "backgroundObservation", "readAfterExplicitWake": True})
    return {"webviewResourceProbe": {
        "scenarioStatus": "completed", "error": None,
        "phases": dict(subject.EXPECTED), "records": records}}


class AppleNativeSmokeValidatorTests(unittest.TestCase):
    def accept(self, wrapper, platform="macos"):
        mode = "profile" if platform == "macos" else "debug"
        return subject.validate(wrapper, platform, mode, SHA)

    def test_native_macos_fifteen_pass_and_expected_skips(self):
        x = self.accept(valid_wrapper())
        self.assertEqual((x["passedPhases"], x["unsupportedPhases"], x["notRunPhases"]),
                         (15, 1, 3))

    def test_ios_reports_desktop_capability_as_unsupported(self):
        x = self.accept(valid_wrapper("ios"), "ios")
        self.assertEqual(x["platform"], "ios")

    def test_false_success_for_non_applicable_phase_is_rejected(self):
        x = valid_wrapper()
        x["webviewResourceProbe"]["phases"]["environment"] = "passed"
        with self.assertRaisesRegex(ValueError, "phase"):
            self.accept(x)

    def test_excluded_real_system_background_is_not_marked_passed(self):
        x = valid_wrapper("ios")
        x["webviewResourceProbe"]["phases"]["applicationBackground"] = "passed"
        with self.assertRaisesRegex(ValueError, "phase"):
            self.accept(x, "ios")

    def test_failed_native_resume_remains_failure(self):
        x = valid_wrapper()
        x["webviewResourceProbe"]["phases"]["resume"] = "failed"
        with self.assertRaisesRegex(ValueError, "phase"):
            self.accept(x)

    def test_missing_native_document_or_wrong_git_sha_rejected(self):
        x = valid_wrapper()
        next(r for r in x["webviewResourceProbe"]["records"] if r["type"] == "meta")[
            "appCommit"] = "b" * 40
        with self.assertRaisesRegex(ValueError, "appCommit"):
            self.accept(x)
        x = valid_wrapper()
        next(r for r in x["webviewResourceProbe"]["records"] if r["type"] ==
             "heartbeatObservation")["afterResume"]["draft"] = "lost draft"
        with self.assertRaisesRegex(ValueError, "Resume lost"):
            self.accept(x)

    def test_macos_native_visibility_must_be_proven(self):
        x = valid_wrapper()
        next(r for r in x["webviewResourceProbe"]["records"] if r["type"] ==
             "nativeWindow")["ready"] = False
        with self.assertRaisesRegex(ValueError, "native window"):
            self.accept(x)

    def test_unsupported_phase_must_retain_truthful_skip_reason(self):
        x = valid_wrapper()
        next(r for r in x["webviewResourceProbe"]["records"] if r.get("name") ==
             "environment")["reason"] = ""
        with self.assertRaisesRegex(ValueError, "skip reason"):
            self.accept(x)

    def test_duplicate_owner_and_backend_fabrication_rejected(self):
        for change in ("id", "backend"):
            x = valid_wrapper("ios")
            views = [r for r in x["webviewResourceProbe"]["records"] if r["type"] ==
                     "webviewBackend"]
            if change == "id":
                views[0]["attachmentId"] = views[1]["attachmentId"]
            else:
                views[0]["backend"]["availability"] = "collected"
            with self.assertRaises(ValueError):
                self.accept(x, "ios")

    def test_exactly_one_fresh_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaisesRegex(ValueError, "one fresh"):
                subject.validate_directory(root, "macos", "profile", SHA)
            directory = root / "run-one"
            directory.mkdir()
            (directory / "report.json").write_text(json.dumps(valid_wrapper()), encoding="utf-8")
            self.assertEqual(subject.validate_directory(root, "macos", "profile", SHA)[
                "passedPhases"], 15)
            second = root / "run-two"
            second.mkdir()
            (second / "report.json").write_text(json.dumps(valid_wrapper()), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "one fresh"):
                subject.validate_directory(root, "macos", "profile", SHA)


if __name__ == "__main__":
    unittest.main()
