#!/usr/bin/env python3
"""Compare only evidence that passed the same on-device native scenario.

The ABBA output is descriptive, never an automatic GO decision. A missing
metric is not zero; incomplete process enumeration is not complete coverage.
"""
import argparse
import json
import math
from pathlib import Path
import statistics
import sys

PHASES = {
    "environment", "firstOpen", "visibleIdle", "multipleOpen", "multipleIdle",
    "scroll", "activeHeartbeat", "hide", "hiddenIdle", "resume",
    "discardWidget", "recreateAndRestore", "backgroundOpen", "backgroundIdle",
    "closeWidgets", "closedIdle",
}
NOT_RUN_PHASES = {"windowMinimize", "applicationBackground", "realPluginDiscard"}
MEASURED = ("firstOpen", "multipleOpen", "hiddenIdle", "resume", "closedIdle")
ORDER = ("baseline", "candidate", "candidate", "baseline")


def need(value, message):
    if not value:
        raise ValueError(message)


def read_trial(root, index, mode, sha):
    directory = root / f"{index:02}-{mode}" / "host"
    reports = list(directory.glob("run-*/report.json"))
    need(len(reports) == 1, f"{mode}[{index}] must have exactly one host report")
    wrapper = json.loads(reports[0].read_text(encoding="utf-8-sig"))
    report = wrapper.get("webviewResourceProbe")
    need(isinstance(report, dict), "Missing native webviewResourceProbe")
    need(report.get("scenarioStatus") == "completed", f"Native scenario failed: {report.get('error')}")
    records = report.get("records")
    need(isinstance(records, list), "Missing raw records")
    phases = report.get("phases")
    need(isinstance(phases, dict) and set(phases) == (PHASES | NOT_RUN_PHASES) and
         all(phases.get(x) == "passed" for x in PHASES) and
         all(phases.get(x) == "notRun" for x in NOT_RUN_PHASES),
         "Failed, unexpected, or missing native workload phase")
    skipped = [r for r in records if r.get("type") == "phase" and
               r.get("name") in NOT_RUN_PHASES]
    need(len(skipped) == len(NOT_RUN_PHASES) and
         {r["name"] for r in skipped} == NOT_RUN_PHASES and
         all(r.get("status") == "skipped" and isinstance(r.get("reason"), str)
             and r["reason"].strip() for r in skipped),
         "Expected explicit reason for each out-of-scope phase")
    meta = [r for r in records if r.get("type") == "meta"]
    need(len(meta) == 1, "Expected one metadata record")
    meta = meta[0]
    for key, expected in (("appCommit", sha), ("os", "windows"), ("buildMode", "profile"), ("tabs", 3),
                          ("idleMs", 3000)):
        need(meta.get(key) == expected, f"Native provenance mismatch: {key}")
    need(meta.get("fixtureSha256"), "Missing immutable workload identity")
    need(isinstance(meta.get("osVersion"), str) and meta["osVersion"].strip(),
         "Missing exact host OS version")
    need(isinstance(meta.get("flutterVersion"), str) and meta["flutterVersion"].strip(),
         "Missing exact Flutter version")
    need(type(meta.get("cores")) is int and meta["cores"] > 0,
         "Missing host CPU count")
    view_records = [r.get("backend") for r in records if r.get("type") == "webviewBackend"]
    need(len(view_records) >= 3 and all(
        isinstance(v, dict) and v.get("verified") is True
        and v.get("requested") == "composition" and v.get("observed") == "composition"
        for v in view_records
    ), "Missing actual composition observations; not an A/B comparison")

    phases_data = {}
    for phase in MEASURED:
        hits = [r for r in records if r.get("type") == "webviewMemory"
                and r.get("phase") == phase and r.get("boundary") == "after"]
        need(len(hits) == 1, f"Expected one memory boundary after {phase}")
        h = hits[0]
        def metric(which):
            x = h.get(which)
            if not isinstance(x, dict) or x.get("availability") != "collected":
                return None
            need(x.get("metric") == "privateCommit" and x.get("unit") == "MiB",
                 "Incomparable memory metric")
            v = x.get("value")
            need(type(v) in (int, float) and v >= 0, "Invalid collected memory value")
            return float(v)
        observed = h.get("observedProcessCount")
        phases_data[phase] = {
            "hostPrivateCommitMiB": metric("host"),
            "engineObservedPrivateCommitMiB": metric("engineObserved"),
            "engineObservedProcesses": observed if type(observed) is int else None,
            "engineComplete": h.get("complete"),
            "memoryCoverage": h.get("memoryCoverage"),
        }
    need(phases_data["multipleOpen"]["engineObservedPrivateCommitMiB"] is not None,
         "No usable native WebView2 memory sample for multipleOpen")
    durations = {}
    for phase in PHASES:
        observed_phases = [r for r in records if r.get("type") == "phase" and r.get("name") == phase]
        need(len(observed_phases) == 1 and observed_phases[0].get("status") == "passed",
             f"Expected exactly one passed native phase: {phase}")
        duration = observed_phases[0].get("durationMs")
        need(type(duration) in (int, float) and math.isfinite(duration) and duration >= 0,
             f"Missing or invalid native phase duration: {phase}")
        durations[phase] = float(duration)
    return {"label": mode, "position": index, "commit": sha,
            "workloadSha256": meta["fixtureSha256"],
            "runtimeEnvironment": {
                "osVersion": meta.get("osVersion"),
                "flutterVersion": meta.get("flutterVersion"),
                "cores": meta.get("cores"),
            }, "phases": phases_data,
            "elapsedMs": durations, "frameSummaries": report.get("flutterFrameSummary", {})}


def summary(items, key, phase):
    values = [x[key].get(phase) if key == "elapsedMs"
              else x["phases"][phase].get(key) for x in items]
    usable = [float(x) for x in values if type(x) in (float, int)]
    return {"values": values, "median": statistics.median(usable) if usable else None,
            "observations": len(usable)}


def compare(root, baseline, candidate):
    root = Path(root)
    trials = [read_trial(root, i+1, mode, baseline if mode == "baseline" else candidate)
              for i, mode in enumerate(ORDER)]
    need(len({x["workloadSha256"] for x in trials}) == 1,
         "Different fixture sources: invalid before/after")
    need(len({json.dumps(x["runtimeEnvironment"], sort_keys=True) for x in trials}) == 1,
         "OS, Flutter or CPU count changed between ABBA trials")
    result = {
        "schemaVersion": 1,
        "status": "descriptiveOnly",
        "scope": "Synthetic three-view native WebView2 profile, four ABBA trials on one runner",
        "limitation": [
            "Not a physical multi-GPU experiment or a real installed-plugin workload",
            "Only two observations per revision; no significance or product default decision",
            "Order is ABBA, but OS and WebView2 disk/process caches are not cold",
            "Observed WebView2 processes may not cover the full engine footprint",
            "Private commit is not RSS/PSS or GPU memory; do not add these values",
            "Flutter frame latency is not WebView paint or input-to-photon time",
        ],
        "baseline": baseline, "candidate": candidate,
        "order": list(ORDER), "workloadSha256": trials[0]["workloadSha256"],
        "trials": trials,
        "summaries": {}
    }
    for phase in MEASURED:
        stats = {}
        for key in ("hostPrivateCommitMiB", "engineObservedPrivateCommitMiB", "engineObservedProcesses"):
            left = summary([x for x in trials if x["label"] == "baseline"], key, phase)
            right = summary([x for x in trials if x["label"] == "candidate"], key, phase)
            stats[key] = {
                "baseline": left,
                "candidate": right,
                "candidateMinusBaselineMedian": right["median"] - left["median"]
                if left["observations"] == 2 and right["observations"] == 2 else None,
            }
        stats["elapsedMs"] = {
            "baseline": summary([x for x in trials if x["label"] == "baseline"], "elapsedMs", phase),
            "candidate": summary([x for x in trials if x["label"] == "candidate"], "elapsedMs", phase),
        }
        result["summaries"][phase] = stats
    dest = root / "comparison.json"
    dest.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--candidate", required=True)
    args = ap.parse_args()
    try:
        outcome = compare(args.root, args.baseline, args.candidate)
    except (ValueError, OSError, json.JSONDecodeError) as e:
        print(f"INCOMPLETE/INVALID A/B: {e}", file=sys.stderr)
        raise SystemExit(1)
    print(json.dumps({
        "status": outcome["status"],
        "trials": len(outcome["trials"]),
        "workloadSha256": outcome["workloadSha256"],
        "multipleOpen": outcome["summaries"]["multipleOpen"],
    }, ensure_ascii=False))
