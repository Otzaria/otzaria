"""Evidence/host contracts only; actual desktop actions run in the native jobs."""

import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import installed_pdf_desktop as subject

FIXTURES = Path(__file__).resolve().parents[2] / "test/tool/perf_probe/fixtures"


def fixture(name="desktop"):
    return json.loads((FIXTURES / f"installed_pdf_{name}.json").read_text())


class DesktopPdfEvidence(unittest.TestCase):
    def test_native_transitions_and_fifty_cycle_receipts_are_complete(self):
        self.assertEqual(subject.validate_desktop_lifecycle(fixture())["status"], "passed")
        self.assertEqual(subject.validate_repeated_lifecycle(fixture("repeated"))["completedCycles"], 50)

    def test_missing_and_skipped_evidence_does_not_pass(self):
        for value in (None, [], {}, {"status": "notRun"}, {"status": "passed"}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                subject.validate_desktop_lifecycle(value)
            with self.subTest(cycles=value), self.assertRaises(ValueError):
                subject.validate_repeated_lifecycle(value)

    def test_boolean_or_fractional_cycle_and_tab_counts_are_not_native_evidence(self):
        for invalid in (True, 1.0):
            report = fixture()
            report["tabCohorts"][0]["tabCount"] = invalid
            with self.subTest(count=invalid), self.assertRaises(ValueError):
                subject.validate_desktop_lifecycle(report)
            report = fixture()
            report["actions"][0]["activity"]["raster"]["page"] = invalid
            with self.subTest(page=invalid), self.assertRaises(ValueError):
                subject.validate_desktop_lifecycle(report)
            for key in ("cycle", "targetPage"):
                report = fixture("repeated")
                report["cycles"][0][key] = invalid
                with self.subTest(cycle=invalid, key=key), self.assertRaises(ValueError):
                    subject.validate_repeated_lifecycle(report)

    def test_each_native_transition_and_target_must_be_observed(self):
        for index, name in enumerate(subject.DESKTOP_ACTIONS):
            for key, value in (("documentUnchanged", False), ("navigationIssued", True),
                               ("targetCenterVisible", False), ("targetPage", 4), ("visibleRenderState", "loading"),
                               ("viewWidth", 0), ("path", "/another/document.pdf")):
                report = fixture()
                report["actions"][index]["reader"][key] = value
                with self.subTest(name=name, key=key), self.assertRaises(ValueError):
                    subject.validate_desktop_lifecycle(report)
            report = fixture()
            report["actions"][index]["status"] = "notRun"
            with self.subTest(name=name), self.assertRaises(ValueError):
                subject.validate_desktop_lifecycle(report)

    def test_window_acknowledgements_are_native_and_original_bounds_return(self):
        for index in (0, 1, 2):
            report = fixture()
            report["actions"][index]["nativeAcknowledgement"] = report["originalWindow"]
            with self.subTest(index=index), self.assertRaises(ValueError):
                subject.validate_desktop_lifecycle(report)
        for flag in subject.FLAGS:
            report = fixture()
            report["restoredWindow"][flag] = not report["originalWindow"][flag]
            with self.subTest(flag=flag), self.assertRaises(ValueError):
                subject.validate_desktop_lifecycle(report)
        for value in (None, "1000", 0, float("nan"), float("inf"), 1003):
            report = fixture()
            report["restoredWindow"]["logicalBounds"]["width"] = value
            with self.subTest(width=value), self.assertRaises(ValueError):
                subject.validate_desktop_lifecycle(report)

    def test_rounding_tolerance_does_not_accept_an_unchanged_resize(self):
        report = fixture()
        report["restoredWindow"]["logicalBounds"]["width"] = 1002
        self.assertEqual(subject.validate_desktop_lifecycle(report)["status"], "passed")
        report = fixture()
        action = report["actions"][2]
        action["requestedBounds"] = report["originalWindow"]["logicalBounds"]
        action["nativeAcknowledgement"] = report["originalWindow"]
        with self.assertRaisesRegex(ValueError, "resize"):
            subject.validate_desktop_lifecycle(report)

    def test_native_resize_requires_a_smaller_reader_viewport(self):
        for axis in ("viewWidth", "viewHeight"):
            report = fixture()
            report["actions"][2]["reader"][axis] = report["actions"][1]["reader"][axis]
            with self.subTest(axis=axis), self.assertRaisesRegex(ValueError, "viewport"):
                subject.validate_desktop_lifecycle(report)

    def test_one_five_ten_tabs_and_synthetic_pressure_cannot_be_skipped(self):
        for key, value in (("additionalNativeCloses", 8), ("tabCohorts", []),
                           ("memoryPressureSource", "physical OS pressure"),
                           ("memoryPressureAcknowledged", None), ("memoryPressureAcknowledged", False),
                           ("memoryPressureAcknowledged", 1), ("documentsRetainedAfterPressure", 9)):
            report = fixture()
            report[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                subject.validate_desktop_lifecycle(report)
        for index in range(3):
            report = fixture()
            report["tabCohorts"][index]["nativeDocumentCount"] -= 1
            with self.subTest(cohort=index), self.assertRaises(ValueError):
                subject.validate_desktop_lifecycle(report)
        report = fixture()
        report["tabCohorts"][2]["paths"][3] = report["primaryPath"]
        with self.assertRaisesRegex(ValueError, "distinct"):
            subject.validate_desktop_lifecycle(report)

    def test_submitted_activity_must_overlap_and_verify_real_raster_pixels(self):
        for index in range(len(subject.DESKTOP_ACTIONS)):
            report = fixture()
            report["actions"][index]["activity"]["endUs"] = 0
            with self.subTest(index=index), self.assertRaisesRegex(ValueError, "overlapping"):
                subject.validate_desktop_lifecycle(report)
            report = fixture()
            report["actions"][index]["activity"]["raster"]["contentPixelsVerified"] = False
            with self.subTest(index=index), self.assertRaisesRegex(ValueError, "pixels"):
                subject.validate_desktop_lifecycle(report)

    def test_last_native_close_must_finish_before_the_cycle_deadline(self):
        for elapsed in (None, -1, 600000, 600001):
            report = fixture("repeated")
            report["cyclesElapsedMs"] = elapsed
            with self.subTest(elapsed=elapsed), self.assertRaisesRegex(ValueError, "deadline"):
                subject.validate_repeated_lifecycle(report)

    def test_slower_software_rendered_cycles_retain_every_acceptance_check(self):
        report = fixture("repeated")
        report["cyclesElapsedMs"] = 322000
        for cycle in report["cycles"]:
            cycle["durationMs"] = 6400
            cycle["stageDurationMs"] = {"openAndReady": 5100, "nativeProof": 100, "close": 1200}
        self.assertEqual(subject.validate_repeated_lifecycle(report)["completedCycles"], 50)
        report["cycles"][-1]["nativeCloseCompleted"] = False
        with self.assertRaises(ValueError):
            subject.validate_repeated_lifecycle(report)

    def test_stages_are_finite_nonnegative_and_within_reported_wall_duration(self):
        for stage in subject.REPEATED_STAGES:
            for invalid in (None, -1, True, float("nan"), float("inf"), 801):
                report = fixture("repeated")
                report["cycles"][0]["stageDurationMs"][stage] = invalid
                with self.subTest(stage=stage, invalid=invalid), self.assertRaises(ValueError):
                    subject.validate_repeated_lifecycle(report)
        report = fixture("repeated")
        del report["cycles"][-1]["stageDurationMs"]
        with self.assertRaises(ValueError):
            subject.validate_repeated_lifecycle(report)
        report = fixture("repeated")
        report["cyclesElapsedMs"] = 39999
        with self.assertRaisesRegex(ValueError, "wall duration"):
            subject.validate_repeated_lifecycle(report)

    def test_all_fifty_cycles_need_rendered_content_and_completed_native_close(self):
        for index in range(50):
            for key, value in (("differentDocument", False), ("nativeCloseCompleted", False),
                               ("targetCenterVisible", False), ("raster", None), ("ownedTabsRemaining", 1)):
                report = fixture("repeated")
                report["cycles"][index][key] = value
                with self.subTest(index=index, key=key), self.assertRaises(ValueError):
                    subject.validate_repeated_lifecycle(report)
        report = fixture("repeated")
        report["cycles"].pop()
        with self.assertRaisesRegex(ValueError, "receipts"):
            subject.validate_repeated_lifecycle(report)

    def test_cli_rejects_missing_or_wrong_platform_receipts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report_path = root / "run-example/report.json"
            report_path.parent.mkdir()
            report = {"installedPluginProbe": {"status": "passed", "platform": "windows",
                      "pdfRuntime": {"steps": {"desktopLifecycle": fixture(), "repeatedLifecycle": fixture("repeated")}}}}
            command = [sys.executable, str(Path(subject.__file__)), "--reports", str(root), "--platform", "windows"]
            report_path.write_text(json.dumps(report))
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            missing = copy.deepcopy(report)
            del missing["installedPluginProbe"]["pdfRuntime"]["steps"]["repeatedLifecycle"]
            report_path.write_text(json.dumps(missing))
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            report["installedPluginProbe"]["platform"] = "macos"
            report_path.write_text(json.dumps(report))
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
