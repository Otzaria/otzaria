import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tool.perf_probe.compare_paragraph_style_lookup import compare_reports


def _report():
    geometry = {
        "height": 28,
        "longestLine": 400,
        "minIntrinsicWidth": 40,
        "maxIntrinsicWidth": 800,
        "exceededMaxLines": False,
        "lines": [
            [True, 0, 400, 14, 12, 12, 2],
            [True, 20, 350, 14, 26, 12, 2],
        ],
        "selectionBoxes": [[0, 0, 40, 14, "rtl"]],
        "placeholderBoxes": [[30, 0, 44, 14, "rtl"]],
    }
    ellipsis = copy.deepcopy(geometry)
    ellipsis.update(
        exceededMaxLines=True,
        lines=ellipsis["lines"][:1],
        placeholderBoxes=[],
    )
    single_run = copy.deepcopy(geometry)
    single_run["placeholderBoxes"] = []
    single_run["widthRelayout"] = copy.deepcopy(single_run)
    return {
        "geometry": [
            geometry, copy.deepcopy(geometry), ellipsis,
            single_run, copy.deepcopy(single_run),
        ],
        "scaling": [
            {
                "groups": groups,
                "characters": groups * 19,
                "letterSpacing": spacing,
                "layoutMicros": 100_000,
                "lineCount": groups // 2,
            }
            for spacing in (0.0, 0.25)
            for groups in (4_000, 8_000, 16_000)
        ],
        "singleRunScaling": {
            direction: {
                "groups": groups,
                "characters": 304_000,
                "letterSpacing": 0.0,
                "lineCount": 8_000,
                "layoutMicros": 100_000,
                "widthRelayoutLineCount": 7_500,
                "widthRelayoutMicros": 90_000,
            }
            for direction, groups in (("ltr", 16_000), ("rtl", 15_200))
        },
    }


class CompareParagraphStyleLookupTest(unittest.TestCase):
    def test_timing_changes_are_reported_instead_of_failing(self):
        baseline = _report()
        patched = copy.deepcopy(baseline)
        patched["scaling"][0]["layoutMicros"] = 2_000_000
        patched["singleRunScaling"]["rtl"]["widthRelayoutMicros"] = 25_000

        comparison = compare_reports(baseline, patched)
        self.assertEqual(comparison["geometryCases"], 5)
        self.assertEqual(comparison["scaling"][0]["baselineLayoutMicros"], 100_000)
        self.assertEqual(comparison["scaling"][0]["patchedLayoutMicros"], 2_000_000)
        rtl = comparison["singleRunScaling"]["rtl"]
        self.assertEqual(rtl["baselineWidthRelayoutMicros"], 90_000)
        self.assertEqual(rtl["patchedWidthRelayoutMicros"], 25_000)

    def test_geometry_changes_fail_with_the_changed_field(self):
        baseline = _report()
        for field, replacement, index in (
            ("lines", [[True, 0, 400, 14, 13, 12, 2]], 2),
            ("selectionBoxes", [[0, 0, 40, 14, "ltr"]], 1),
            ("placeholderBoxes", [[31, 0, 44, 14, "rtl"]], 0),
            ("maxIntrinsicWidth", 801, 0),
        ):
            with self.subTest(field=field):
                patched = copy.deepcopy(baseline)
                patched["geometry"][index][field] = replacement
                with self.assertRaisesRegex(ValueError, rf"geometry\[{index}\]\.{field} differs"):
                    compare_reports(baseline, patched)

    def test_same_incomplete_reports_cannot_pass(self):
        for index, field in (
            (2, "exceededMaxLines"), (0, "placeholderBoxes"),
            (0, "selectionBoxes"), (3, "widthRelayout"),
        ):
            with self.subTest(field=field):
                baseline = _report()
                del baseline["geometry"][index][field]
                with self.assertRaisesRegex(ValueError, r"Baseline geometry\["):
                    compare_reports(baseline, copy.deepcopy(baseline))

    def test_large_case_line_count_must_match(self):
        baseline = _report()
        patched = copy.deepcopy(baseline)
        patched["scaling"][-1]["lineCount"] += 1
        with self.assertRaisesRegex(ValueError, r"scaling\[5\]\.lineCount differs"):
            compare_reports(baseline, patched)

    def test_single_run_checks_geometry_and_line_count_after_width_relayout(self):
        baseline = _report()
        patched = copy.deepcopy(baseline)
        patched["geometry"][3]["widthRelayout"]["selectionBoxes"][0][0] = 1
        with self.assertRaisesRegex(ValueError, r"geometry\[3\]\.widthRelayout differs"):
            compare_reports(baseline, patched)

        patched = copy.deepcopy(baseline)
        patched["singleRunScaling"]["rtl"]["widthRelayoutLineCount"] += 1
        with self.assertRaisesRegex(ValueError, r"singleRunScaling\.rtl\.widthRelayoutLineCount differs"):
            compare_reports(baseline, patched)

    def test_cli_emits_json_on_success_and_fails_on_layout_mismatch(self):
        script = Path(__file__).with_name("compare_paragraph_style_lookup.py")
        with tempfile.TemporaryDirectory() as directory:
            baseline_file = Path(directory) / "baseline report.json"
            patched_file = Path(directory) / "patched report.json"
            baseline = _report()
            baseline_file.write_text(json.dumps(baseline), encoding="utf-8")
            patched_file.write_text(json.dumps(baseline), encoding="utf-8")
            command = [sys.executable, script, baseline_file, patched_file]

            result = subprocess.run(command, check=True, capture_output=True, text=True)
            self.assertEqual(json.loads(result.stdout)["geometryCases"], 5)

            baseline["geometry"][0]["height"] += 1
            patched_file.write_text(json.dumps(baseline), encoding="utf-8")
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, "")
            self.assertIn("geometry[0].height differs", result.stderr)


if __name__ == "__main__":
    unittest.main()
