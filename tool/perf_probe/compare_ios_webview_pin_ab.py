#!/usr/bin/env python3
"""Inspect four real, isolated iOS WKWebView trials (old/new/new/old).

A failed native test is evidence, never an accepted result. No CPU/RAM/speed
improvements are inferred from two debug Simulator runs per revision.
"""
import argparse
import json
import math
from pathlib import Path
import re
import sys

ORDER = ("old", "new", "new", "old")
RUNNABLE = frozenset(("firstOpen", "visibleIdle", "multipleOpen",
    "multipleIdle", "scroll", "activeHeartbeat", "hide", "hiddenIdle",
    "resume", "discardWidget", "recreateAndRestore", "backgroundOpen",
    "backgroundIdle", "closeWidgets", "closedIdle"))
OUT_OF_SCOPE = frozenset(("windowMinimize", "applicationBackground",
                          "realPluginDiscard"))
ALL_PHASES = RUNNABLE | OUT_OF_SCOPE | {"environment"}


def require(test, why):
    if not test:
        raise ValueError(why)


def examine(root, index, label, expected_sha):
    folder = root / f"{index:02}-{label}"
    receipt = json.loads((folder / "trial.json").read_text())
    require(receipt.get("index") == index and receipt.get("label") == label and
            receipt.get("commit") == expected_sha, f"Wrong source identity: {folder.name}")
    require(re.fullmatch("[0-9A-Fa-f-]{36}", receipt.get("simulatorId", "")),
            f"Missing owned Simulator UUID: {folder.name}")
    require(receipt.get("cleanup") == "deleted", f"Simulator cleanup failed: {folder.name}")
    require(type(receipt.get("driveExitCode")) is int,
            f"Missing native exit code: {folder.name}")
    reports = list((folder / "host").glob("run-*/report.json"))
    require(len(reports) == 1, f"Missing/duplicate native report: {folder.name}")
    result = json.loads(reports[0].read_text(encoding="utf-8-sig"))
    report = result.get("webviewResourceProbe")
    require(isinstance(report, dict), f"No real WebView report: {folder.name}")
    records = report.get("records")
    require(isinstance(records, list), "Missing raw native records")
    metas = [r for r in records if r.get("type") == "meta"]
    require(len(metas) == 1, "No unique native report metadata")
    meta = metas[0]
    for field, expected in (("os", "ios"), ("buildMode", "debug"),
                            ("flutterVersion", "3.47.7"), ("tabs", 3),
                            ("idleMs", 3000), ("appCommit", expected_sha)):
        require(meta.get(field) == expected, f"Wrong native {field}: {folder.name}")
    require(re.fullmatch("[0-9a-f]{64}", meta.get("fixtureSha256", "")),
            "Missing original fixture hash")
    require(meta.get("runId") and meta.get("osVersion"),
            "Missing runId or iOS version")
    phases = report.get("phases")
    require(isinstance(phases, dict) and set(phases) == ALL_PHASES,
            "Missing, extra or duplicate phase statuses")
    require(phases.get("environment") == "unsupported" and
            all(phases.get(p) == "notRun" for p in OUT_OF_SCOPE),
            "Cannot fabricate OS-only actions or WebView2 environment")
    phase_records = {}
    for name in ALL_PHASES:
        found = [r for r in records if r.get("type") == "phase" and r.get("name") == name]
        require(len(found) == 1, f"Missing/duplicate raw phase {name}")
        item = found[0]
        phase_records[name] = item
        status = phases[name]
        require(status in (("passed", "failed", "notRun") if name in RUNNABLE
                           else ("notRun",) if name in OUT_OF_SCOPE
                           else ("unsupported",)),
                f"Unexpected phase status: {name}={status}")
        require(item.get("status") == ("skipped" if status in ("notRun", "unsupported")
                                      else status), f"Phase verdict mismatch: {name}")
        if status in ("notRun", "unsupported"):
            require(isinstance(item.get("reason"), str) and item["reason"].strip(),
                    f"Missing skip reason: {name}")
        elif status == "failed":
            require(isinstance(item.get("error"), str) and item["error"],
                    f"Missing failure evidence: {name}")
        else:
            value = item.get("durationMs")
            require(type(value) in (float, int) and math.isfinite(value) and value >= 0,
                    f"Invalid measured phase duration: {name}")
    views = [r for r in records if r.get("type") == "webviewBackend"
             and r.get("event") == "created"]
    require(len(views) >= 3 and
            len({r.get("attachmentId") for r in views}) == len(views)
            and all(r.get("runId") == meta["runId"] for r in views),
            "Missing, stale or reused native WebView ownership")
    require(all(r.get("backend", {}).get("availability") == "unsupported"
                for r in views), "Apple backend must not invent Windows mode")
    heartbeats = [r for r in records if r.get("type") == "heartbeatObservation"]
    require(len(heartbeats) == 1, "No original-document resume evidence")
    before = heartbeats[0].get("beforeHide", {})
    after = heartbeats[0].get("afterResume", {})
    require(all(before.get(k) == after.get(k) and before.get(k) is not None
                for k in ("schemaVersion", "draft", "revision", "scrollY")),
            "Original document failed hide/resume")
    ok = report.get("scenarioStatus") == "completed"
    failed = report.get("scenarioStatus") == "failed"
    require((ok and receipt["driveExitCode"] == 0 and
             all(phases[p] == "passed" for p in RUNNABLE) and report.get("error") is None)
            or (failed and receipt["driveExitCode"] != 0 and
                any(phases[p] == "failed" for p in RUNNABLE) and
                isinstance(report.get("error"), str) and report["error"]),
            "Native driver and report contradict each other")
    return {
        "trial": index, "pin": label, "commit": expected_sha,
        "simulatorId": receipt["simulatorId"], "runtime": receipt.get("runtime"),
        "osVersion": meta["osVersion"], "runId": meta["runId"],
        "fixtureSha256": meta["fixtureSha256"],
        "status": "passed" if ok else "failed", "error": report.get("error"),
        "restoreStatus": phases["recreateAndRestore"],
        "durationMs": {k: phase_records[k].get("durationMs")
                       if phases[k] == "passed" else None
                       for k in ("firstOpen", "resume", "recreateAndRestore")},
        "phaseStatuses": phases,
    }


def compare(output, old, new):
    root = Path(output)
    trials = [examine(root, i + 1, label, old if label == "old" else new)
              for i, label in enumerate(ORDER)]
    for field in ("fixtureSha256", "runtime", "osVersion"):
        require(len({t[field] for t in trials}) == 1, f"Different {field}: incomparable")
    require(len({t["simulatorId"].lower() for t in trials}) == 4,
            "A Simulator was reused")
    require(len({t["runId"] for t in trials}) == 4, "A stale report was reused")
    summary = {}
    for label in ("old", "new"):
        selected = [t for t in trials if t["pin"] == label]
        summary[label] = {
            "runs": len(selected),
            "passed": sum(t["status"] == "passed" for t in selected),
            "failed": sum(t["status"] == "failed" for t in selected),
            "restoreFailed": sum(t["restoreStatus"] == "failed" for t in selected),
            "restoreDurationsMs": [t["durationMs"]["recreateAndRestore"]
                                   for t in selected],
        }
    output_data = {
        "status": "descriptiveOnly", "order": list(ORDER),
        "scope": "Same iOS runtime, same fixture source, separate fresh Simulators",
        "limitations": [
            "Two debug-Simulator trials per pin do not prove or exclude intermittent failures",
            "No representative CPU, GPU, RAM, energy or physical-device results",
            "A failed native scenario remains a failed test, not a waiver",
        ],
        "old": old, "new": new, "summary": summary, "trials": trials,
        "newOnlyRestoreFailureObserved":
            summary["old"]["restoreFailed"] == 0 and
            summary["new"]["restoreFailed"] > 0,
        "oldRestoreFailureObserved": summary["old"]["restoreFailed"] > 0,
    }
    (root / "comparison.json").write_text(
        json.dumps(output_data, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8")
    return output_data


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--root", type=Path, required=True)
    p.add_argument("--old", required=True)
    p.add_argument("--new", required=True)
    x = p.parse_args()
    try:
        require(all(re.fullmatch("[0-9a-f]{40}", sha) for sha in (x.old, x.new)),
                "Exact source SHA required for each pin")
        report = compare(x.root, x.old, x.new)
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"INVALID iOS A/B EVIDENCE: {exc}", file=sys.stderr)
        raise SystemExit(2)
    print(json.dumps({k: report[k] for k in
          ("status", "order", "summary", "newOnlyRestoreFailureObserved",
           "oldRestoreFailureObserved")}, indent=2))
    # Any confirmed native failure must keep CI red.
    raise SystemExit(0 if all(t["status"] == "passed" for t in report["trials"])
                     else 1)


if __name__ == "__main__":
    main()
