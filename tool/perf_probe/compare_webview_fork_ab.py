#!/usr/bin/env python3
"""Compare only evidence that passed the same on-device native scenario.

The ABBA output is descriptive, never an automatic GO decision. A missing
metric is not zero; incomplete process enumeration is not complete coverage.
"""
import argparse
import json
from pathlib import Path
import statistics
import sys

PHASES = {
    "environment", "firstOpen", "visibleIdle", "multipleOpen", "multipleIdle",
    "scroll", "activeHeartbeat", "hide", "hiddenIdle", "resume",
    "discardWidget", "recreateAndRestore", "backgroundOpen", "backgroundIdle",
    "closeWidgets", "closedIdle",
}
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
    phases = report.get("phases")
    need(isinstance(phases, dict) and all(phases.get(x) == "passed" for x in PHASES),
         "Failed or missing native workload phase")
    records = report.get("records")
    need(isinstance(records, list), "Missing raw records")
    meta = [r for r in records if r.get("type") == "meta"]
    need(len(meta) == 1, "Expected one metadata record")
    meta = meta[0]
    for key, expected in (("appCommit", sha), ("os", "windows"), ("buildMode", "profile"), ("tabs", 3),
                          ("idleMs", 3000)):
        need(meta.get(key) == expected, f"Native provenance mismatch: {key}")
    need(meta.get("fixtureSha256"), "Missing immutable workload identity")
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
    durations = {r.get("name"): r.get("elapsedMs")
                 for r in records if r.get("type") == "phase" and r.get("name") in PHASES}
    return {"label": mode, "position": index, "commit": sha,
            "workloadSha256": meta["fixtureSha256"], "phases": phases_data,
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
