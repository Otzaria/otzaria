#!/usr/bin/env python3
"""Describe existing long-open/steady-scroll memory snapshots, without rerunning the app.

No retained-memory, allocation-throughput or physical peak claim. External
Windows samples are selected strictly inside each recorded action interval,
using the exact process identity. No nearest/halo sample or interpolation.
"""
import argparse
import csv
import hashlib
import json
import pathlib
import statistics

MIB = 1024 * 1024
NAMES = ("book.long.open", "book.long.steady_scroll")


def dist(values):
    a = [v for v in values if v is not None]
    return ({"count": len(a), "min": min(a), "median": statistics.median(a),
             "max": max(a), "mean": statistics.mean(a)} if a else {"count": 0})


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("artifact_root", type=pathlib.Path)
    p.add_argument("qa", type=pathlib.Path)
    p.add_argument("--output", type=pathlib.Path, required=True)
    a = p.parse_args()
    root, output = a.artifact_root.resolve(), a.output.resolve()
    if output.exists() or output == root or root in output.parents:
        p.error("Use a new output file outside the raw artifact")
    qa = read(a.qa)
    assert not qa["errors"], "Resolve raw-data QA errors first"
    observations, hashes, sampling = [], {}, {}
    sampler_intervals = {}
    for side in ("baseline", "candidate"):
        paths = {n: root / side / n for n in ("phases.jsonl", "samples.csv", "manifest.json")}
        hashes.update({f"{side}/{n}": sha(v) for n, v in paths.items()})
        sampling[side] = read(paths["manifest.json"])["sampling"]
        phases = [json.loads(line) for line in paths["phases.jsonl"].read_text(encoding="utf-8-sig").splitlines() if line.strip()]
        with paths["samples.csv"].open(encoding="utf-8-sig", newline="") as f:
            samples = list(csv.DictReader(f))
        identities = {x["launchIndex"]: x for x in qa["launches"] if x["side"] == side}
        roots = {}
        sampler_intervals[side] = {}
        for li, identity in identities.items():
            rows = [x for x in samples if int(x["launch_index"]) == li and
                    int(x["pid"]) == identity["pid"] and int(x["root_pid"]) == identity["pid"] and
                    x["identity_start_ticks"] == identity["identityStartTicks"]]
            assert rows
            roots[li] = rows
            times = [int(x["monotonic_ms"]) for x in rows]
            sampler_intervals[side][str(li)] = dist([y-x for x, y in zip(times, times[1:])])
        for phase in phases:
            if phase["type"] != "phase" or phase.get("name") not in NAMES or phase["warmup"]:
                continue
            metrics = {}
            for key in ("heapBefore", "heapAfter"):
                snap = phase[key]
                assert snap and snap["aggregation"] == "unique-application-isolate-groups"
                assert snap["measurement"] == "current-usage-without-forced-gc"
                groups = snap["isolateGroups"]
                assert len({g["id"] for g in groups}) == len(groups)
                for field in ("heapUsage", "heapCapacity", "externalUsage"):
                    assert sum(g[field] for g in groups) == snap[field]
                    metrics[key + "." + field + "MiB"] = snap[field] / MIB
            metrics["heapUsageAfterMinusBeforeMiB"] = (phase["heapAfter"]["heapUsage"] - phase["heapBefore"]["heapUsage"]) / MIB
            for field in ("rssStartBytes", "rssEndBytes", "rssPeakBytes"):
                metrics["phase." + field.replace("Bytes", "MiB")] = phase[field] / MIB
            if phase["name"] == "book.long.steady_scroll":
                assert phase["details"]["fullyLoaded"] is True
                assert phase["countersBefore"]["lines"] == phase["countersAfter"]["lines"] == 1000000
                assert phase["countersBefore"]["pendingReads"] == phase["countersAfter"]["pendingReads"] == 0
            rows = [x for x in roots[phase["launchIndex"]]
                    if phase["startMs"] <= int(x["epoch_ms"]) < phase["endMs"]]
            for source, label in (("ws_mb", "workingSet"), ("priv_mb", "private")):
                values = [float(x[source]) for x in rows if x[source].strip()]
                assert len(values) == len(rows)
                metrics["csv." + label + "ObservedMaxMiB"] = max(values) if values else None
            observations.append({
                "side": side, "name": phase["name"], "launchIndex": phase["launchIndex"],
                "iteration": phase["iteration"], "durationMs": phase["durationMs"],
                "startMs": phase["startMs"], "endMs": phase["endMs"],
                "metrics": metrics, "insideWindowSamples": [{
                    "epochMs": int(x["epoch_ms"]), "monotonicMs": int(x["monotonic_ms"]),
                    "workingSetMiB": float(x["ws_mb"]), "privateMiB": float(x["priv_mb"]),
                    "treeAgeMs": int(x["tree_age_ms"])} for x in rows],
            })
    assert len(observations) == 64
    summaries = {}
    for name in NAMES:
        result = {}
        for side in ("baseline", "candidate"):
            obs = [o for o in observations if o["name"] == name and o["side"] == side]
            assert len(obs) == 16
            labels = list(obs[0]["metrics"])
            result[side] = {
                "pooledActionDistributions": {m: dist([o["metrics"][m] for o in obs]) for m in labels},
                "coveredActionsByCsv": sum(bool(o["insideWindowSamples"]) for o in obs),
                "totalCsvSamplesInsideActions": sum(len(o["insideWindowSamples"]) for o in obs),
                "perProcess": [{
                    "launchIndex": li,
                    "csvSamplesPerIteration": [len(o["insideWindowSamples"]) for o in obs if o["launchIndex"] == li],
                    "metrics": {m: dist([o["metrics"][m] for o in obs if o["launchIndex"] == li]) for m in labels},
                } for li in range(4)],
            }
        result["candidateOverBaselineProcessMedians"] = {
            m: [result["candidate"]["perProcess"][i]["metrics"][m].get("median", 0) /
                result["baseline"]["perProcess"][i]["metrics"][m]["median"]
                if result["candidate"]["perProcess"][i]["metrics"][m]["count"] == 4 and
                   result["baseline"]["perProcess"][i]["metrics"][m]["count"] == 4 and
                   result["baseline"]["perProcess"][i]["metrics"][m]["median"] > 0 else None
                for i in range(4)] for m in labels if m != "heapUsageAfterMinusBeforeMiB"}
        summaries[name] = result
    report = {
        "runIdentity": qa["run_identity"], "comparisonDesign": qa["comparison_design"],
        "baseline": qa["expected_baseline"], "candidate": qa["expected_candidate"],
        "unit": "MiB = 1,048,576 bytes; PowerShell 1MB divisor is binary MiB",
        "sampling": sampling, "observedExternalSamplerIntervalsMsByProcess": sampler_intervals,
        "definitions": {
            "heap": "Current usage/capacity/external usage summed once per application isolate group, without forced GC. Before is before action setup; after follows the profile frame-delivery drain. Snapshot timestamps within that sampling call are not recorded.",
            "phaseRss": "ProcessInfo.currentRss start/end plus an in-process 250 ms Timer sampled maximum. Event-loop delays can delay samples; this is not an exact peak. This timer differs from the separate 250 ms frame-delivery drain.",
            "csvWorkingSet": "Windows Process.WorkingSet64 / 1MB from the external nominal 500 ms sampler. Includes the whole application process, native/runtime/profiling state.",
            "csvPrivate": "Windows Process.PrivateMemorySize64 / 1MB, private committed process memory; not equivalent to resident working set or Dart heap.",
            "csvWindow": "Exact root PID plus creation ticks and launchIndex, startMs <= epoch_ms < endMs. No halo/nearest sample or interpolation. Per-action observed maxima are summarized with equal action weights where available.",
        },
        "limitations": [
            "No allocation-throughput, retained-object, live-object-after-GC or exact process peak claim.",
            "Heap differences and deltas include natural GC timing, prior action history and instrumentation; negative deltas are retained.",
            "Long open is a partial-load state; steady_scroll follows verified full load of one million logical lines and no active content I/O.",
            "Open actions shorter than the external sampler interval may have no in-window CSV sample; absence is not zero and coverage differs by side.",
            "Repeated actions share process state. Four paired process medians describe one VM, not independent hardware replications.",
            "All raw observations are retained. Do not pool runs or attribute the whole-PR comparison solely to representation.",
        ],
        "scenarios": summaries, "observations": observations,
        "inputSha256": {**hashes, "qa": sha(a.qa), "analysisSource": sha(pathlib.Path(__file__))},
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2, allow_nan=False)
        f.write("\n")
    print(json.dumps({"output": str(output), "bytes": output.stat().st_size, "sha256": sha(output)}))


if __name__ == "__main__":
    main()
