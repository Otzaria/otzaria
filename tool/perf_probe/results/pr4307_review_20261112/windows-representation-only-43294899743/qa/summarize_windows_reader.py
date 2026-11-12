#!/usr/bin/env python3
"""Descriptive, no-filter follow-up to qa_windows_reader.py; stdlib only.

The complete raw artifact, not a selected trace subset, is needed to rerun QA.
This program retains every required measured action in observations. Frame
budget exceedances and slow-sample locations are descriptive diagnostics, not
an eligibility filter or a physical-GPU jank estimate.
"""
import argparse
import collections
import hashlib
import json
import math
import pathlib
import statistics


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def distribution(values):
    a = sorted(values)
    if not a:
        return {"count": 0}
    return {
        "count": len(a), "min": a[0], "max": a[-1],
        "mean": statistics.mean(a),
        "arithmeticMedian": statistics.median(a),
        **{f"p{p}": a[math.ceil(len(a) * p / 100) - 1]
           for p in (50, 95, 99)},
    }


def frame_stats(values):
    return {
        **distribution(values),
        "above1000Over60Ms": sum(v > 1000 / 60 for v in values),
        "above1000Over30Ms": sum(v > 1000 / 30 for v in values),
    }


def key(row):
    return (row["launchIndex"], row["name"], row["warmup"], row["iteration"])


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("artifact_root", type=pathlib.Path)
    ap.add_argument("qa", type=pathlib.Path)
    ap.add_argument("--output", required=True, type=pathlib.Path)
    args = ap.parse_args()
    if args.output.exists():
        raise SystemExit("Refusing to overwrite an existing output")
    root = args.artifact_root.resolve()
    output = args.output.resolve()
    if output == root or root in output.parents:
        raise SystemExit("Output must be outside the raw artifact")
    qa = read_json(args.qa)
    assert qa["errors"] == [], "Resolve QA errors before interpreting statistics"
    assert qa["design"]["latency_samples_per_action_and_side"] == 16
    required = set(qa["scenarios"])
    observations = []
    metrics = ("buildMs", "rasterMs", "totalMs")
    side_rows = {}
    side_manifests = {}
    input_hashes = {str(args.qa): digest(args.qa)}
    trace_catalog = []

    for side in ("baseline", "candidate"):
        source = root / side / "phases.jsonl"
        input_hashes[f"{side}/phases.jsonl"] = digest(source)
        rows = [json.loads(line) for line in
                source.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
        side_rows[side] = rows
        side_manifests[side] = read_json(root / side / "manifest.json")
        reader = {key(r): r for r in rows if r["type"] == "reader_phase"}
        reads = collections.defaultdict(list)
        for r in rows:
            if r["type"] == "reader_repository_read":
                reads[r["launchIndex"]].append(r)
        launch_dirs = {r["launchIndex"]: pathlib.PureWindowsPath(r["launchDirectory"])
                       for r in side_manifests[side]["launchDirectories"]}
        phases = [r for r in rows if r["type"] == "phase" and
                  r["name"] in required and not r["warmup"]]
        assert len(phases) == len(required) * 16
        for p in phases:
            r = reader[key(p)]
            start, end = r["startTimelineUs"], r["endTimelineUs"]
            overlap = [x for x in reads[p["launchIndex"]]
                       if x["startTimelineUs"] < end and x["endTimelineUs"] > start]
            at_start = [x for x in overlap if x["startTimelineUs"] < start]
            frames = p["frames"]
            assert all(len(frames[m]) == frames["count"] for m in metrics)
            trace_path = pathlib.Path(*launch_dirs[p["launchIndex"]].parts) / r["timelineFile"]
            observations.append({
                "side": side, "name": p["name"], "launchIndex": p["launchIndex"],
                "iteration": p["iteration"], "durationMs": p["durationMs"],
                "readerPhaseId": r["id"], "traceFile": trace_path.as_posix(),
                "frames": {"count": frames["count"],
                           **{m: frame_stats(frames[m]) for m in metrics}},
                "pipeline": {k: v for k, v in r["pipeline"].items()
                             if not k.endswith("IntervalsUs")},
                "before": r["before"], "after": r["after"],
                "details": p["details"], "smartText": r["smartText"],
                "overlappingRepositoryReads": {
                    "count": len(overlap), "startedBeforePhase": len(at_start),
                    "byOperation": dict(collections.Counter(x["operation"] for x in overlap)),
                    "durationMs": distribution([x["durationUs"] / 1000 for x in overlap]),
                    "requestIds": [x["requestId"] for x in overlap],
                    "note": "Read spans may overlap each other or phase boundaries; do not add to or subtract from latency."
                },
            })

    summaries = {}
    for name in sorted(required):
        row = {}
        for side in ("baseline", "candidate"):
            obs = [o for o in observations if o["side"] == side and o["name"] == name]
            phases = [p for p in side_rows[side] if p["type"] == "phase" and
                      p["name"] == name and not p["warmup"]]
            by_launch = []
            for li in range(4):
                po = [o for o in obs if o["launchIndex"] == li]
                pp = [p for p in phases if p["launchIndex"] == li]
                by_launch.append({
                    "launchIndex": li,
                    "latencyMs": distribution([o["durationMs"] for o in po]),
                    "latencyInRecordedOrderMs": [o["durationMs"] for o in po],
                    "frames": {m: frame_stats([v for p in pp for v in p["frames"][m]])
                               for m in metrics},
                    "pipeline": {m: distribution([o["pipeline"][m] for o in po
                                                   if o["pipeline"].get(m) is not None])
                                 for m in ("layoutTotalMs", "paintTotalMs")},
                })
            row[side] = {
                "latencyMs": distribution([o["durationMs"] for o in obs]),
                "frames": {m: frame_stats([v for p in phases for v in p["frames"][m]])
                           for m in metrics},
                "pipeline": {
                    **{m: distribution([o["pipeline"][m] for o in obs if o["pipeline"].get(m) is not None])
                       for m in ("layoutTotalMs", "paintTotalMs")},
                    "unavailableReasons": dict(collections.Counter(
                        o["pipeline"].get("unavailableReason") for o in obs
                        if o["pipeline"].get("unavailableReason"))),
                },
                "byLaunch": by_launch,
            }
            for metric in ("p50", "p95", "p99", "max"):
                assert row[side]["latencyMs"][metric] == qa["scenarios"][name][side]["latencyMs"][metric]
                for m in metrics:
                    if row[side]["frames"][m]["count"]:
                        assert row[side]["frames"][m][metric] == qa["scenarios"][name][side]["frames"][m][metric]
        row["pairedArithmeticMedianLatencyRatios"] = [
            row["candidate"]["byLaunch"][i]["latencyMs"]["arithmeticMedian"] /
            row["baseline"]["byLaunch"][i]["latencyMs"]["arithmeticMedian"] for i in range(4)]
        summaries[name] = row

    long_jump_slow = [o for o in observations
                     if o["name"] in ("book.long.jump_forward", "book.long.jump_backward")
                     and o["durationMs"] > 500]
    max_scroll = [max((o for o in observations if o["side"] == side and
                      o["name"] == "book.long.scroll"), key=lambda o: o["durationMs"])
                  for side in ("baseline", "candidate")]
    chosen = long_jump_slow + max_scroll
    for o in chosen:
        path = root / o["traceFile"]
        trace_catalog.append({
            "path": o["traceFile"], "sha256": digest(path), "bytes": path.stat().st_size,
            "selectionReason": ("long jump duration > 500 ms" if "jump_" in o["name"]
                                else "maximum long initial scroll duration on this side"),
            "side": o["side"], "name": o["name"], "launchIndex": o["launchIndex"],
            "iteration": o["iteration"], "durationMs": o["durationMs"],
        })
    incomplete = [w for w in qa["warnings"]
                  if w.get("code") == "pipeline_unavailable_incomplete_trace"]
    late_origins = [w for w in incomplete if
                    w.get("traceTimeOriginMicros", 0) > w["phaseStartTimelineUs"]]
    unavailable_counts = collections.Counter(
        (side, r["name"], r["pipeline"].get("unavailableReason"))
        for side, rows in side_rows.items() for r in rows
        if r["type"] == "reader_phase" and r["pipeline"].get("unavailableReason"))
    result = {
        "runIdentity": qa["run_identity"], "comparisonDesign": qa["comparison_design"],
        "sourceComparison": qa["source_comparison"], "metricValidity": qa["metric_validity"],
        "machine": {s: m["machine"] for s, m in side_manifests.items()},
        "counts": {"requiredScenarios": len(required), "measuredActions": len(observations),
                   "allOutliersRetained": True},
        "quantiles": "nearest rank; arithmeticMedian separately averages the two middle values for even n",
        "interpretationLimits": [
            "Whole-PR and representation-only runs must never be pooled.",
            "The four processes on each side share one VM; process medians are descriptive, not independent hardware replications.",
            "A 16-sample nearest-rank p95/p99 equals the observed maximum.",
            "Frame budget exceedances use 1000/60 and 1000/30 ms only as descriptive thresholds; no physical-GPU FPS claim.",
            "Frame arrays have unequal lengths across actions and sides; pooled percentiles weight each captured frame equally.",
            "Pipeline interval unions and repository waits overlap and have different measurement boundaries; they are not additive components of elapsed latency.",
            "Readiness polling, warmup loaded-prefix scans and profiling work can depend on representation; see observer-timing-qa.json.",
            "Slow-jump threshold 500 ms and maximum-scroll trace selection are diagnostic only; no sample is excluded from any statistic.",
        ],
        "timeline": {
            "incompleteMarkerTraces": len(incomplete), "traceOriginLaterThanPhaseStart": len(late_origins),
            "missingMarkersKeptUnavailable": True,
            "unavailableByActionIncludingWarmups": [
                {"side": k[0], "name": k[1], "reason": k[2], "count": v}
                for k, v in sorted(unavailable_counts.items())],
        },
        "scenarios": summaries,
        "diagnosticTraceCatalog": trace_catalog,
        "observations": observations,
        "inputSha256": input_hashes,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(output), "bytes": output.stat().st_size,
                      "sha256": digest(output), "observations": len(observations),
                      "diagnosticTraces": len(trace_catalog),
                      "allIncompleteTraceOriginsLater": len(late_origins) == len(incomplete)}))


if __name__ == "__main__":
    main()
