"""Compare the JSON reports produced by paragraph_style_lookup_probe.dart."""

import argparse
import json
from math import isfinite
from pathlib import Path


_DIMENSIONS = ("height", "longestLine", "minIntrinsicWidth", "maxIntrinsicWidth")
_BOX_LISTS = ("selectionBoxes", "placeholderBoxes")
_SCALE_FIELDS = ("groups", "characters", "letterSpacing", "lineCount")
_DIRECTIONS = ("ltr", "rtl")


def _is_number(value):
    return type(value) is int or (type(value) is float and isfinite(value))


def _validate_geometry(case, name, *, ellipsis=False, placeholders=False):
    if not isinstance(case, dict):
        raise ValueError(f"{name} is not an object.")
    for field in _DIMENSIONS:
        if not _is_number(case.get(field)):
            raise ValueError(f"{name}.{field} must be a finite number.")
    lines = case.get("lines")
    if not isinstance(lines, list) or not lines or any(
        not isinstance(line, list)
        or len(line) != 7
        or type(line[0]) is not bool
        or not all(map(_is_number, line[1:]))
        for line in lines
    ):
        raise ValueError(f"{name}.lines must contain line metrics.")
    if case.get("exceededMaxLines") is not ellipsis or (len(lines) == 1) != ellipsis:
        raise ValueError(f"{name} does not exercise the expected line limit.")
    for field in _BOX_LISTS:
        boxes = case.get(field)
        if not isinstance(boxes, list) or any(
            not isinstance(box, list)
            or len(box) != 5
            or not all(map(_is_number, box[:4]))
            or box[4] not in _DIRECTIONS
            for box in boxes
        ):
            raise ValueError(f"{name}.{field} must contain text boxes.")
        if not boxes and (field == "selectionBoxes" or placeholders):
            raise ValueError(f"{name}.{field} is empty.")


def _geometry_cases(report, label):
    cases = report.get("geometry")
    if not isinstance(cases, list) or len(cases) != 5:
        raise ValueError(f"{label} report must contain the five geometry cases.")
    for index, case in enumerate(cases):
        name = f"{label} geometry[{index}]"
        _validate_geometry(case, name, ellipsis=index == 2, placeholders=index < 2)
        if index >= 3:
            _validate_geometry(case.get("widthRelayout"), f"{name}.widthRelayout")
    return cases


def _validate_scaling(case, name, *, relayout=False):
    if not isinstance(case, dict):
        raise ValueError(f"{name} is not an object.")
    fields = ("groups", "characters", "lineCount", "layoutMicros")
    if relayout:
        fields += ("widthRelayoutLineCount", "widthRelayoutMicros")
    for field in fields:
        value = case.get(field)
        if type(value) is not int or value <= 0:
            raise ValueError(f"{name}.{field} must be a positive integer.")
    if not _is_number(case.get("letterSpacing")):
        raise ValueError(f"{name}.letterSpacing must be a finite number.")


def _scaling_cases(report, label):
    cases = report.get("scaling")
    if not isinstance(cases, list) or len(cases) != 6:
        raise ValueError(f"{label} report must contain the six scaling cases.")
    for index, case in enumerate(cases):
        _validate_scaling(case, f"{label} scaling[{index}]")
    return cases


def _single_run_scaling(report, label):
    cases = report.get("singleRunScaling")
    if not isinstance(cases, dict) or set(cases) != set(_DIRECTIONS):
        raise ValueError(f"{label} report must contain LTR and RTL single-run scaling.")
    for direction, case in cases.items():
        _validate_scaling(case, f"{label} singleRunScaling.{direction}", relayout=True)
    return cases


def _compare_scaling(before, after, name, *, relayout=False):
    fields = _SCALE_FIELDS + (("widthRelayoutLineCount",) if relayout else ())
    for field in fields:
        if before[field] != after[field]:
            raise ValueError(f"{name}.{field} differs.")
    result = {
        **{field: before[field] for field in fields},
        "baselineLayoutMicros": before["layoutMicros"],
        "patchedLayoutMicros": after["layoutMicros"],
    }
    if relayout:
        result.update(
            baselineWidthRelayoutMicros=before["widthRelayoutMicros"],
            patchedWidthRelayoutMicros=after["widthRelayoutMicros"],
        )
    return result


def compare_reports(baseline, patched):
    if not isinstance(baseline, dict) or not isinstance(patched, dict):
        raise ValueError("Both reports must be JSON objects.")

    baseline_geometry = _geometry_cases(baseline, "Baseline")
    patched_geometry = _geometry_cases(patched, "Patched")
    for index, (before, after) in enumerate(zip(baseline_geometry, patched_geometry)):
        if before.keys() != after.keys():
            raise ValueError(f"geometry[{index}] fields differ.")
        for field in before:
            if before[field] != after[field]:
                raise ValueError(f"geometry[{index}].{field} differs.")

    baseline_scaling = _scaling_cases(baseline, "Baseline")
    patched_scaling = _scaling_cases(patched, "Patched")
    baseline_single = _single_run_scaling(baseline, "Baseline")
    patched_single = _single_run_scaling(patched, "Patched")
    return {
        "geometryCases": len(baseline_geometry),
        "scaling": [
            _compare_scaling(before, after, f"scaling[{index}]")
            for index, (before, after) in enumerate(zip(baseline_scaling, patched_scaling))
        ],
        "singleRunScaling": {
            direction: _compare_scaling(
                baseline_single[direction], patched_single[direction],
                f"singleRunScaling.{direction}", relayout=True,
            )
            for direction in _DIRECTIONS
        },
    }


def main():
    parser = argparse.ArgumentParser(
        description="Check identical paragraph geometry and report both layout timings."
    )
    parser.add_argument("baseline", type=Path, help="Probe report from the baseline engine")
    parser.add_argument("patched", type=Path, help="Probe report from the patched engine")
    args = parser.parse_args()

    try:
        baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
        patched = json.loads(args.patched.read_text(encoding="utf-8"))
        comparison = compare_reports(baseline, patched)
    except (OSError, ValueError) as error:
        parser.exit(1, f"{parser.prog}: {error}\n")
    print(json.dumps(comparison, indent=2))


if __name__ == "__main__":
    main()
