"""Strict negative and positive contracts for the 4-run native WebView A/B validator."""
import json
from pathlib import Path
import tempfile
import unittest

from tool.perf_probe import compare_webview_fork_ab as probe

OLD = "a" * 40
NEW = "b" * 40


class CompareWebViewForkAbTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for index, mode in enumerate(probe.ORDER, 1):
            self.make_trial(index, mode, OLD if mode == "baseline" else NEW)

    def make_trial(self, index, mode, commit):
        records = [{
            "type": "meta", "appCommit": commit, "os": "windows",
            "osVersion": "Windows test 26100", "flutterVersion": "3.47.7",
            "cores": 4, "buildMode": "profile", "tabs": 3, "idleMs": 3000,
            "fixtureSha256": "identical-workload-sha256"
        }]
        records.extend({
            "type": "webviewBackend", "backend": {
                "verified": True, "requested": "composition", "observed": "composition"
            }
        } for _ in range(3))
        for phase in probe.PHASES:
            records.append({"type": "phase", "name": phase, "status": "passed",
                            "durationMs": float(20+index)})
        for phase in probe.NOT_RUN_PHASES:
            records.append({"type": "phase", "name": phase, "status": "skipped",
                            "reason": "Requires real OS background and plugin host"})
        for phase in probe.MEASURED:
            records.append({
                "type": "webviewMemory", "phase": phase, "boundary": "after",
                "host": {"availability": "collected", "metric": "privateCommit",
                         "unit": "MiB", "value": 90+index},
                "engineObserved": {"availability": "collected", "metric": "privateCommit",
                                   "unit": "MiB", "value": 140+index},
                "observedProcessCount": 7, "complete": None,
                "memoryCoverage": "allObserved"
            })
        payload = {"webviewResourceProbe": {
            "scenarioStatus": "completed", "error": None,
            "phases": {**{x: "passed" for x in probe.PHASES},
                       **{x: "notRun" for x in probe.NOT_RUN_PHASES}},
            "records": records, "flutterFrameSummary": {}
        }}
        output = self.root / f"{index:02}-{mode}" / "host" / "run-unique" / "report.json"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(payload), encoding="utf-8")
        return output

    def edit_report(self, index, fn):
        mode = probe.ORDER[index-1]
        path = self.root / f"{index:02}-{mode}" / "host" / "run-unique" / "report.json"
        data = json.loads(path.read_text())
        fn(data["webviewResourceProbe"])
        path.write_text(json.dumps(data), encoding="utf-8")

    def compare(self):
        return probe.compare(self.root, OLD, NEW)

    def test_valid_abba_uses_actual_duration_ms_and_never_claims_savings(self):
        result = self.compare()
        self.assertEqual(result["status"], "descriptiveOnly")
        self.assertEqual(result["order"], list(probe.ORDER))
        self.assertEqual(result["summaries"]["firstOpen"]["elapsedMs"]["baseline"]["values"], [21.0, 24.0])
        self.assertEqual(result["summaries"]["firstOpen"]["elapsedMs"]["candidate"]["values"], [22.0, 23.0])
        self.assertEqual(result["summaries"]["multipleOpen"]["hostPrivateCommitMiB"][
            "candidateMinusBaselineMedian"], 0.0)
        self.assertIsNone(result["trials"][0]["phases"]["firstOpen"]["engineComplete"])
        self.assertTrue((self.root / "comparison.json").exists())

    def test_rejects_failed_incomplete_and_added_phases(self):
        for edit in [
            lambda p: p["phases"].__setitem__("hide", "notRun"),
            lambda p: p["phases"].pop("resume"),
            lambda p: p["phases"].__setitem__("invented", "passed"),
        ]:
            self.edit_report(2, edit)
            with self.assertRaisesRegex(ValueError, "native workload phase"):
                self.compare()
            self.make_trial(2, "candidate", NEW)

    def test_does_not_fabricate_os_background_or_real_plugin_discard(self):
        self.edit_report(2, lambda p: p["phases"].__setitem__(
            "realPluginDiscard", "passed"))
        with self.assertRaisesRegex(ValueError, "native workload phase"):
            self.compare()
        self.make_trial(2, "candidate", NEW)
        def drop_reason(p):
            next(r for r in p["records"] if r.get("name") == "applicationBackground")[
                "reason"] = ""
        self.edit_report(2, drop_reason)
        with self.assertRaisesRegex(ValueError, "out-of-scope phase"):
            self.compare()
        self.make_trial(2, "candidate", NEW)

    def test_rejects_wrong_backend_and_missing_backend_observations(self):
        for edit in [
            lambda p: p["records"][1]["backend"].__setitem__("observed", "hwnd"),
            lambda p: p["records"].__delitem__(1),
        ]:
            self.edit_report(3, edit)
            with self.assertRaisesRegex(ValueError, "composition"):
                self.compare()
            self.make_trial(3, "candidate", NEW)

    def test_rejects_different_workload_and_environment(self):
        for change in [
            ("fixtureSha256", "different-fixture"),
            ("osVersion", "different-OS"),
            ("flutterVersion", "3.99.0"),
            ("cores", 8),
        ]:
            key, value = change
            self.edit_report(4, lambda p: next(r for r in p["records"] if
                                                     r["type"] == "meta").__setitem__(key, value))
            with self.assertRaisesRegex(ValueError, "Different fixture|OS, Flutter|CPU count"):
                self.compare()
            self.make_trial(4, "baseline", OLD)

    def test_rejects_missing_duplicate_or_invalid_phase_duration(self):
        for change in [
            lambda p: next(r for r in p["records"] if r.get("name") == "firstOpen").pop("durationMs"),
            lambda p: next(r for r in p["records"] if r.get("name") == "firstOpen").__setitem__("durationMs", -1),
            lambda p: p["records"].append({"type": "phase", "name": "firstOpen", "status": "passed", "durationMs": 1}),
        ]:
            self.edit_report(1, change)
            with self.assertRaisesRegex(ValueError, "phase|duration"):
                self.compare()
            self.make_trial(1, "baseline", OLD)

    def test_unavailable_memory_stays_null_not_zero(self):
        def edit(p):
            r = next(x for x in p["records"] if x.get("type") == "webviewMemory"
                     and x.get("phase") == "firstOpen")
            r["host"] = {"availability": "unavailable", "value": None}
        self.edit_report(3, edit)
        result = self.compare()
        self.assertEqual(result["summaries"]["firstOpen"]["hostPrivateCommitMiB"][
            "candidate"]["values"], [92.0, None])
        self.assertIsNone(result["summaries"]["firstOpen"]["hostPrivateCommitMiB"][
            "candidateMinusBaselineMedian"])

    def test_rejects_wrong_memory_metric_not_cross_platform_comparable(self):
        def edit(p):
            r = next(x for x in p["records"] if x.get("type") == "webviewMemory"
                     and x.get("phase") == "multipleOpen")
            r["engineObserved"]["metric"] = "anonymousRss"
        self.edit_report(2, edit)
        with self.assertRaisesRegex(ValueError, "Incomparable memory metric"):
            self.compare()


if __name__ == "__main__":
    unittest.main()
