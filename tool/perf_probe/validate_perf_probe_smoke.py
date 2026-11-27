#!/usr/bin/env python3
"""Require the actual POSIX profile reader smoke; this is not a latency gate."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
if __package__:
    from .run_perf_probe_posix import is_fixture_id, read_json
    from .probe_binding import binding_identity, validate_binding_identity, validate_framework_scheduler
else:
    from run_perf_probe_posix import is_fixture_id, read_json
    from probe_binding import binding_identity, validate_binding_identity, validate_framework_scheduler


CASE = {"schemaVersion": 1,
        "source": {"kind": "generated", "pageCount": 600, "mixedPageSizes": True},
        "navigation": {"initialPage": 1, "forwardPage": 450, "backwardPage": 60,
                       "zoomFactor": 2, "zoomPage": 60, "zoomAnchor": "pageCenter"}}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(root, *, commit, platform, binding_mode="integration"):
    require(re.fullmatch(r"[0-9a-f]{40}", commit) is not None, "Expected a source commit SHA")
    report = read_json(root / "report.json", maximum=128 * 1024 * 1024)
    manifest = read_json(root / "manifest.json")
    require(report.get("complete") is True and report.get("successful") is True,
            "The actual app report must be complete and successful")
    require(report.get("comparisonEligibility") == [], "Source and measurement identity must be verified")
    metadata = report["metadata"]
    require(is_fixture_id(metadata.get("fixtureId")), "Invalid fixture schema/digest identity")
    for source in (manifest, metadata):
        expected = {"schemaVersion": 2, "protocolVersion": 2, "status": "passed", "commit": commit,
                    "buildMode": "profile", "cacheState": "cold", "scenarioSet": "pdf-reader",
                    "bindingMode": binding_mode, "probeTarget": binding_identity(binding_mode)["probeTarget"],
                    "launchCount": 1, "warmup": 0, "repetitions": 1, "dirty": False}
        for key, value in expected.items():
            require(type(source.get(key)) is type(value) and source[key] == value,
                    f"Unexpected smoke {key}: {source.get(key)!r}")
    for stage in ("beforeBuild", "afterBuild", "afterRuns"):
        value = manifest["sourceProvenance"][stage]
        require(value.get("statusPorcelain") == [] and value.get("trackedDiffSummary") == [],
                f"Source changed at {stage}")
    sampling = metadata["sampling"]
    require(sampling == manifest["sampling"], "Sampling identity differs between manifest and report")
    require(sampling.get("scope") == "owned-root-process-only"
            and sampling.get("descendantsObserved") is False, "Unexpected process observation scope")
    expected_source = "/proc/" if platform == "linux" else "proc_pid_rusage(RUSAGE_INFO_V0)"
    require(sampling["processReader"]["source"].startswith(expected_source), "Wrong native process reader")
    require(sampling.get("displayMode") == ("xvfb" if platform == "linux" else "desktop"),
            "Wrong display conditions for this smoke")
    settings = metadata["settings"]
    validate_binding_identity(settings, binding_mode)
    if binding_mode == "framework":
        validate_framework_scheduler(report.get("notes"), metadata["launchCount"])
    require(settings.get("pdfReaderCase") == CASE and settings.get("pdfPageCount") == 600
            and settings.get("pdfLayout") == "regularView"
            and settings.get("scenarioSet") == "pdf-reader", "The default PDF case/actions changed")
    require(settings.get("resourceObservationVersion") == 1
            and settings.get("pdfPostCloseIdleMs") == 3000, "Budget/idle observations are missing")
    case = read_json(root / "pdf-case.json")
    expected_case = {**CASE, "navigation": {key: value for key, value in CASE["navigation"].items()
                                          if key not in ("zoomPage", "zoomAnchor")}}
    require(case == expected_case, "Prepared PDF case differs from the recorded case")

    journal = root / "phases.jsonl"
    require(not journal.is_symlink() and journal.stat().st_size < 128 * 1024 * 1024,
            "Invalid phase journal")
    records = [json.loads(line) for line in journal.read_text(encoding="utf-8").splitlines() if line.strip()]
    primary = [row for row in records if row.get("type") == "meta" and "pid" in row]
    require(len(primary) == 1 and primary[0].get("fixtureId") == metadata.get("fixtureId"),
            "Expected one measured fixture identity")
    pdf = root / "data/cold-0/pdf/reader-mixed.pdf"
    require(pdf.is_file() and not pdf.is_symlink(), "Measured fixture PDF is missing")
    with pdf.open("rb") as source:
        pdf_hash = hashlib.file_digest(source, "sha256").hexdigest()
    require(primary[0].get("fixturePdf") == {"pages": 600, "mixedPageSizes": True,
                                            "source": "generated", "sha256": pdf_hash},
            "Measured PDF hash/count/source do not match the prepared file")

    def scenario(name):
        rows = [row for row in report["scenarios"] if row.get("name") == f"pdf.reader.{name}"]
        require(len(rows) == 1, f"Missing or duplicate PDF action: {name}")
        return rows[0]

    for name in ("open", "jump_forward", "jump_backward", "zoom", "close", "idle_after_close"):
        row = scenario(name)
        require(row.get("status") == "passed" and row.get("measured") == 1,
                f"PDF action was not measured successfully: {name}")
        for side in ("before", "after"):
            require(row["imageBudget"][side].get("complete") is True, f"Missing {name} budget {side}")
        for field in ("treePrivatePeakBytes", "handlesPeak"):
            require(field in row["resources"] and row["resources"][field] is None,
                    f"Unavailable POSIX {field} must not be reported as a number")
    idle = scenario("idle_after_close")
    require(idle.get("measurementKind") == "resource-observation" and idle.get("observationWindowMs") == 3000
            and "latencyMs" in idle and idle["latencyMs"] is None, "Idle must not become a latency measurement")
    resources = idle["resources"]
    for name, minimum in (("sampledTicks", 2), ("cpuIntervalCount", 1)):
        require(type(resources.get(name)) is int and resources[name] >= minimum,
                f"The fixed idle window has no usable process samples: {name}")
    for name in ("cpuCoveredMs", "treeWorkingSetPeakBytes", "cpuAverageCorePercent"):
        value = resources.get(name)
        require(type(value) in (int, float) and math.isfinite(value)
                and (value >= 0 if name == "cpuAverageCorePercent" else value > 0),
                f"The fixed idle window has no measured resource value: {name}")
    checkpoints = scenario("open")["checkpointsMs"]
    values = []
    for name in ("controller_ready", "final_image_ready"):
        point = checkpoints[name]
        value = point.get("p50")
        require(point.get("count") == 1 and type(value) in (int, float)
                and math.isfinite(value) and value >= 0, f"Missing measured checkpoint: {name}")
        values.append(value)
    require(values[0] <= values[1], "Final image cannot precede controller readiness")
    require(scenario("first_preview_image").get("status") == "skipped",
            "Unsupported preview signal must remain explicit")
    return {"status": "passed", "platform": platform, "commit": commit, "fixtureId": metadata["fixtureId"],
            "bindingMode": binding_mode,
            "pdfSha256": pdf_hash, "pdfReaderCase": CASE, "checkpointsMs": checkpoints,
            "idleResources": resources,
            "scope": sampling["scope"], "comparison": "not performed; one functional smoke launch"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--platform", choices=("linux", "macos"), required=True)
    parser.add_argument("--binding-mode", choices=("integration", "framework"), default="integration")
    args = parser.parse_args()
    try:
        print(json.dumps(validate(args.root, commit=args.commit, platform=args.platform,
                                  binding_mode=args.binding_mode), indent=2))
        return 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
        print(f"Incomplete POSIX PDF reader smoke: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
