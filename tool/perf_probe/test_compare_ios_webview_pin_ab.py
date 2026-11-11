"""Fail-closed controls for a 4-trial old/new/new/old native iOS comparison."""
import json
from pathlib import Path
import tempfile
import unittest

from tool.perf_probe import compare_ios_webview_pin_ab as ab

OLD = "a" * 40
NEW = "b" * 40
FINGERPRINT = "c" * 64


def report(sha, identity, restore_failure=False):
    phases = {p: "passed" for p in ab.RUNNABLE}
    phases.update({p: "notRun" for p in ab.OUT_OF_SCOPE})
    phases["environment"] = "unsupported"
    if restore_failure:
        phases["recreateAndRestore"] = "failed"
        for p in ("backgroundOpen", "backgroundIdle", "closeWidgets", "closedIdle"):
            phases[p] = "notRun"
    records = [{
        "type": "meta", "os": "ios", "osVersion": "iOS 26.5", "runId": identity,
        "buildMode": "debug", "flutterVersion": "3.47.7", "tabs": 3,
        "idleMs": 3000, "appCommit": sha, "fixtureSha256": FINGERPRINT,
    }]
    for name, state in phases.items():
        record = {"type": "phase", "name": name,
                  "status": "skipped" if state in ("notRun", "unsupported") else state}
        if state == "passed":
            record["durationMs"] = 120.0
        elif state == "failed":
            record["error"] = "Expected 1440 actual 0"
        else:
            record["reason"] = "Not a supported scenario"
        records.append(record)
    for i in range(3):
        records.append({
            "type": "webviewBackend", "event": "created", "runId": identity,
            "attachmentId": f"host-{i}",
            "backend": {"availability": "unsupported", "verified": False},
        })
    records.append({"type": "heartbeatObservation",
                    "beforeHide": {"schemaVersion": 1, "revision": 2,
                                   "draft": "טיוטה", "scrollY": 1440},
                    "afterResume": {"schemaVersion": 1, "revision": 2,
                                    "draft": "טיוטה", "scrollY": 1440}})
    return {"webviewResourceProbe": {
        "scenarioStatus": "failed" if restore_failure else "completed",
        "error": "Expected 1440 actual 0" if restore_failure else None,
        "phases": phases, "records": records,
    }}


class NativeIOSSuite(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for i, label in enumerate(ab.ORDER, 1):
            self.write_trial(i, label, OLD if label == "old" else NEW)

    def write_trial(self, i, label, sha, fail=False):
        directory = self.root / f"{i:02}-{label}"
        report_directory = directory / "host" / "run-one"
        report_directory.mkdir(parents=True, exist_ok=True)
        (directory / "trial.json").write_text(json.dumps({
            "index": i, "label": label, "commit": sha,
            "simulatorId": f"0000000{i}-1111-2222-3333-444444444444",
            "cleanup": "deleted",
            "driveExitCode": 1 if fail else 0,
            "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        }))
        (report_directory / "report.json").write_text(
            json.dumps(report(sha, f"identity-{i}", restore_failure=fail)))

    def update(self, i, patch):
        label = ab.ORDER[i-1]
        path = self.root / f"{i:02}-{label}" / "host" / "run-one" / "report.json"
        contents = json.loads(path.read_text())
        patch(contents["webviewResourceProbe"])
        path.write_text(json.dumps(contents))

    def test_four_passes_only_mean_no_failure_observed(self):
        value = ab.compare(self.root, OLD, NEW)
        self.assertEqual(value["status"], "descriptiveOnly")
        self.assertEqual(value["summary"]["old"]["passed"], 2)
        self.assertEqual(value["summary"]["new"]["passed"], 2)
        self.assertFalse(value["newOnlyRestoreFailureObserved"])

    def test_candidate_failure_is_recorded_and_not_waived(self):
        self.write_trial(2, "new", NEW, fail=True)
        value = ab.compare(self.root, OLD, NEW)
        self.assertEqual(value["summary"]["new"]["restoreFailed"], 1)
        self.assertTrue(value["newOnlyRestoreFailureObserved"])
        self.assertEqual(value["trials"][1]["status"], "failed")

    def test_old_failure_is_not_called_new_regression(self):
        self.write_trial(4, "old", OLD, fail=True)
        value = ab.compare(self.root, OLD, NEW)
        self.assertFalse(value["newOnlyRestoreFailureObserved"])
        self.assertTrue(value["oldRestoreFailureObserved"])

    def test_wrong_resolved_source_is_rejected(self):
        self.write_trial(3, "new", OLD)
        with self.assertRaisesRegex(ValueError, "source identity"):
            ab.compare(self.root, OLD, NEW)

    def test_wrong_backend_and_fabricated_ios_background_rejected(self):
        self.update(2, lambda r: r["phases"].__setitem__("applicationBackground", "passed"))
        with self.assertRaisesRegex(ValueError, "fabricate"):
            ab.compare(self.root, OLD, NEW)
        self.write_trial(2, "new", NEW)
        self.update(2, lambda r: next(x for x in r["records"]
                                     if x.get("type") == "webviewBackend")[
                                         "backend"].__setitem__("availability", "collected"))
        with self.assertRaisesRegex(ValueError, "backend"):
            ab.compare(self.root, OLD, NEW)

    def test_disagreeing_driver_and_report_cannot_pass(self):
        p = self.root / "01-old" / "trial.json"
        value = json.loads(p.read_text())
        value["driveExitCode"] = 1
        p.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, "contradict"):
            ab.compare(self.root, OLD, NEW)

    def test_missing_report_or_cleanup_receipt_fatal(self):
        (self.root / "04-old" / "host" / "run-one" / "report.json").unlink()
        with self.assertRaisesRegex(ValueError, "native report"):
            ab.compare(self.root, OLD, NEW)
        self.write_trial(4, "old", OLD)
        p = self.root / "04-old" / "trial.json"
        x = json.loads(p.read_text())
        x["cleanup"] = "failed"
        p.write_text(json.dumps(x))
        with self.assertRaisesRegex(ValueError, "cleanup"):
            ab.compare(self.root, OLD, NEW)

    def test_duplicate_simulator_or_fixture_mismatch_fatal(self):
        p = self.root / "01-old" / "trial.json"
        x = json.loads(p.read_text())
        x["simulatorId"] = "00000002-1111-2222-3333-444444444444"
        p.write_text(json.dumps(x))
        with self.assertRaisesRegex(ValueError, "Simulator was reused"):
            ab.compare(self.root, OLD, NEW)
        self.write_trial(1, "old", OLD)
        self.update(1, lambda r: next(x for x in r["records"] if x["type"] == "meta").update(
            fixtureSha256="f" * 64))
        with self.assertRaisesRegex(ValueError, "fixtureSha256"):
            ab.compare(self.root, OLD, NEW)


if __name__ == "__main__":
    unittest.main()
