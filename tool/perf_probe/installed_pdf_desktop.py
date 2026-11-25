"""Fail-closed evidence for real PDF tabs across desktop window transitions."""

import argparse
import json
import math
from pathlib import Path
import re

DESKTOP_ACTIONS = ("hide", "minimize", "resize", "switchSecondary", "switchPrimary", "memoryPressure")
FLAGS = ("visible", "minimized", "maximized", "fullScreen")
REPEATED_CYCLES = 50
REPEATED_DEADLINE_SECONDS = 600
REPEATED_STAGES = ("openAndReady", "nativeProof", "close")


def require(condition, detail):
    if not condition:
        raise ValueError(detail)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def integer(value, expected):
    return type(value) is int and value == expected


def bounds(value):
    return (isinstance(value, dict) and all(number(value.get(key)) for key in ("x", "y", "width", "height"))
            and value["width"] > 0 and value["height"] > 0)


def matching_bounds(actual, expected):
    return (bounds(actual) and bounds(expected)
            and all(abs(actual[key] - expected[key]) <= 2 for key in ("x", "y", "width", "height")))


def window(value, *, ready=False):
    return (isinstance(value, dict) and value.get("source") == "window_manager native window queries"
            and all(type(value.get(key)) is bool for key in FLAGS) and bounds(value.get("logicalBounds"))
            and (not ready or (value["visible"] and not value["minimized"] and value.get("ready") is True)))


def reader(value, path, page):
    return (isinstance(value, dict) and value.get("path") == path and integer(value.get("targetPage"), page)
            and value.get("targetCenterVisible") is True and value.get("visibleRenderState") == "ready"
            and value.get("documentUnchanged") is True and value.get("navigationIssued") is False
            and all(number(value.get(key)) and value[key] > 0 for key in ("viewWidth", "viewHeight")))


def interval(value):
    return (isinstance(value, dict) and type(value.get("startUs")) is int and type(value.get("endUs")) is int
            and 0 <= value["startUs"] <= value["endUs"])


def raster(value, page):
    sizes = ((240, 320), (320, 240), (200, 400), (400, 200))
    return (isinstance(value, dict) and integer(value.get("page"), page)
            and integer(value.get("width"), sizes[page - 1][0]) and integer(value.get("height"), sizes[page - 1][1])
            and value.get("contentPixelsVerified") is True and isinstance(value.get("pixelSha256"), str)
            and re.fullmatch(r"[0-9a-f]{64}", value["pixelSha256"]) is not None)


def validate_desktop_lifecycle(value):
    require(isinstance(value, dict) and value.get("status") == "passed", "Missing passed native PDF desktop lifecycle")
    require(number(value.get("durationMs")) and value["durationMs"] >= 0, "Missing desktop lifecycle timing")
    primary, secondary = value.get("primaryPath"), value.get("secondaryPath")
    require(isinstance(primary, str) and primary and isinstance(secondary, str) and secondary and primary != secondary
            and value.get("distinctDocuments") is True and value.get("secondaryNativeCloseCompleted") is True
            and integer(value.get("additionalNativeCloses"), 9),
            "PDF lifecycle requires two distinct real tabs and native close")
    cohorts = value.get("tabCohorts")
    require(isinstance(cohorts, list) and len(cohorts) == 3, "Missing native PDF tab counts 1, 5 and 10")
    for cohort, count in zip(cohorts, (1, 5, 10)):
        require(isinstance(cohort, dict), f"Missing native PDF cohort {count}")
        paths = cohort.get("paths")
        require(integer(cohort.get("tabCount"), count) and integer(cohort.get("nativeDocumentCount"), count)
                and isinstance(paths, list) and len(paths) == count and all(isinstance(path, str) and path for path in paths)
                and len(set(paths)) == count and primary in paths and reader(cohort.get("primaryReader"), primary, 2),
                f"PDF tab cohort {count} lacks distinct live documents")
    require(value.get("memoryPressureSource") == "flutter/system memoryPressure (synthetic)"
            and value.get("memoryPressureAcknowledged") is True
            and integer(value.get("documentsRetainedAfterPressure"), 10),
            "Synthetic memory pressure did not preserve all ten PDF documents")
    original, restored = value.get("originalWindow"), value.get("restoredWindow")
    require(window(original) and window(restored) and all(original[key] == restored[key] for key in FLAGS)
            and matching_bounds(original["logicalBounds"], restored["logicalBounds"])
            and value.get("windowRestored") is True, "Original native window bounds and flags were not restored")
    actions = value.get("actions")
    require(isinstance(actions, list) and len(actions) == len(DESKTOP_ACTIONS), "Missing PDF desktop transitions")
    for index, (action, name) in enumerate(zip(actions, DESKTOP_ACTIONS)):
        require(isinstance(action, dict) and action.get("name") == name and action.get("status") == "passed",
                f"PDF desktop transition missing or out of order: {name}")
        path, page = (secondary, 3) if name == "switchSecondary" else (primary, 2)
        require(window(action.get("beforeWindow"), ready=True) and window(action.get("afterWindow"), ready=True)
                and reader(action.get("reader"), path, page),
                f"PDF content did not recover without navigation after {name}")
        acknowledgement = action.get("nativeAcknowledgement")
        require(window(acknowledgement)
                and (name != "hide" or acknowledgement["visible"] is False)
                and (name != "minimize" or acknowledgement["minimized"] is True),
                f"Missing native acknowledgement for {name}")
        if name == "resize":
            before = action.get("beforeWindow")
            require(window(before) and matching_bounds(acknowledgement["logicalBounds"], action.get("requestedBounds"))
                    and not matching_bounds(before["logicalBounds"], action["requestedBounds"]),
                    "PDF window resize did not change to the requested bounds")
            before_reader = actions[index - 1]["reader"]
            require(all(action["reader"][axis] < before_reader[axis] for axis in ("viewWidth", "viewHeight")),
                    "PDF reader viewport did not shrink after the native resize")
        activity, transition = action.get("activity"), action.get("transition")
        require(interval(activity) and interval(transition) and activity["startUs"] <= transition["startUs"]
                and activity["endUs"] >= transition["startUs"] and transition["endUs"] >= activity["startUs"],
                f"No overlapping submitted native raster work for {name}")
        require(raster(activity.get("raster"), 1),
                f"Native activity raster did not verify its pixels for {name}")
    require(reader(value.get("restoredReader"), primary, 2), "Primary PDF did not remain ready after window restoration")
    return {"status": "passed", "nativeTransitions": list(DESKTOP_ACTIONS),
            "windowRestored": True, "secondaryNativeCloseCompleted": True}


def validate_repeated_lifecycle(value):
    require(isinstance(value, dict) and value.get("status") == "passed"
            and integer(value.get("requiredCycles"), REPEATED_CYCLES)
            and integer(value.get("completedCycles"), REPEATED_CYCLES)
            and integer(value.get("deadlineSeconds"), REPEATED_DEADLINE_SECONDS)
            and number(value.get("cyclesElapsedMs"))
            and 0 <= value["cyclesElapsedMs"] < REPEATED_DEADLINE_SECONDS * 1000,
            "Missing fifty completed native PDF open/render/close cycles within the deadline")
    cycles = value.get("cycles")
    require(isinstance(cycles, list) and len(cycles) == REPEATED_CYCLES, "Missing native PDF cycle receipts")
    cycles_duration_ms = 0
    for index, cycle in enumerate(cycles):
        page = index % 4 + 1
        require(isinstance(cycle, dict) and integer(cycle.get("cycle"), index + 1) and integer(cycle.get("targetPage"), page)
                and cycle.get("differentDocument") is True and cycle.get("visibleRenderState") == "ready"
                and cycle.get("targetCenterVisible") is True and raster(cycle.get("raster"), page)
                and cycle.get("nativeCloseCompleted") is True and type(cycle.get("ownedTabsRemaining")) is int
                and cycle["ownedTabsRemaining"] == 0 and number(cycle.get("durationMs")) and cycle["durationMs"] >= 0,
                f"Native PDF cycle {index + 1} lacks content or completed teardown")
        stages = cycle.get("stageDurationMs")
        require(isinstance(stages, dict)
                and all(number(stages.get(stage)) and stages[stage] >= 0 for stage in REPEATED_STAGES)
                and sum(stages[stage] for stage in REPEATED_STAGES) <= cycle["durationMs"] + 0.001,
                f"Native PDF cycle {index + 1} lacks bounded stage timings")
        cycles_duration_ms += cycle["durationMs"]
    require(cycles_duration_ms <= value["cyclesElapsedMs"] + 0.001,
            "Native PDF cycles exceed their reported wall duration")
    return {"status": "passed", "completedCycles": REPEATED_CYCLES}


def validate_desktop_steps(steps):
    require(isinstance(steps, dict), "Missing native PDF desktop steps")
    return {"desktopLifecycle": validate_desktop_lifecycle(steps.get("desktopLifecycle")),
            "repeatedLifecycle": validate_repeated_lifecycle(steps.get("repeatedLifecycle"))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reports", type=Path, required=True)
    parser.add_argument("--platform", choices=("linux", "windows", "macos"), required=True)
    arguments = parser.parse_args()
    reports = list(arguments.reports.glob("run-*/report.json"))
    require(len(reports) == 1, "Expected one fresh installed-app driver report")
    report = json.loads(reports[0].read_text(encoding="utf-8-sig"))["installedPluginProbe"]
    require(isinstance(report, dict) and report.get("platform") == arguments.platform and report.get("status") == "passed",
            "Wrong platform or failed installed-app report")
    pdf = report.get("pdfRuntime")
    require(isinstance(pdf, dict), "Missing native PDF runtime")
    result = validate_desktop_steps(pdf.get("steps"))
    print(json.dumps({"report": str(reports[0]), **result}))


if __name__ == "__main__":
    main()
