#!/usr/bin/env python3
"""Fail-closed acceptance of the portable WKWebView native smoke report.

'unsupported' and 'notRun' are expected for explicitly out-of-scope phases,
not silently promoted to 'passed'. No CPU, RAM or OS-background claim.
"""
import argparse
import json
import math
from pathlib import Path
import re
import sys

PASSED = {
    "firstOpen", "visibleIdle", "multipleOpen", "multipleIdle", "scroll",
    "activeHeartbeat", "hide", "hiddenIdle", "resume", "discardWidget",
    "recreateAndRestore", "backgroundOpen", "backgroundIdle",
    "closeWidgets", "closedIdle",
}
UNSUPPORTED = {"environment"}
NOT_RUN = {"windowMinimize", "applicationBackground", "realPluginDiscard"}
EXPECTED = {**{key: "passed" for key in PASSED},
            **{key: "unsupported" for key in UNSUPPORTED},
            **{key: "notRun" for key in NOT_RUN}}


def require(ok, detail):
    if not ok:
        raise ValueError(detail)


def validate(report_wrapper, platform, mode, commit):
    require(platform in ("macos", "ios"), "Only Apple platforms accepted")
    require(mode == ("profile" if platform == "macos" else "debug"),
            "Unexpected build mode for Apple runner")
    report = report_wrapper.get("webviewResourceProbe")
    require(isinstance(report, dict), "Missing real webviewResourceProbe result")
    require(report.get("scenarioStatus") == "completed" and report.get("error") is None,
            "Native scenario incomplete or failed")
    require(report.get("phases") == EXPECTED, "Unexpected phase, unavailable status or skipped runnable phase")
    records = report.get("records")
    require(isinstance(records, list), "Raw native records missing")
    metadata = [r for r in records if r.get("type") == "meta"]
    require(len(metadata) == 1, "Expected one unique native metadata record")
    metadata = metadata[0]
    expected = {"os": platform, "buildMode": mode, "appCommit": commit,
                "flutterVersion": "3.47.7", "tabs": 3, "idleMs": 3000}
    for key, value in expected.items():
        require(metadata.get(key) == value, f"Native provenance mismatch: {key}")
    require(isinstance(metadata.get("osVersion"), str) and metadata["osVersion"].strip(),
            "Missing OS version")
    require(isinstance(metadata.get("runId"), str) and metadata["runId"],
            "Missing unique native run identity")
    require(re.fullmatch(r"[0-9a-f]{64}", metadata.get("fixtureSha256", "")) is not None,
            "Missing real fixture SHA-256")
    for key, state in EXPECTED.items():
        matching = [r for r in records if r.get("type") == "phase" and r.get("name") == key]
        require(len(matching) == 1, f"Missing or duplicate phase record: {key}")
        record = matching[0]
        if state == "passed":
            value = record.get("durationMs")
            require(record.get("status") == "passed" and type(value) in (float, int) and
                    math.isfinite(value) and value >= 0,
                    f"Missing verified native completion/duration: {key}")
        else:
            require(record.get("status") == "skipped" and
                    isinstance(record.get("reason"), str) and record["reason"].strip(),
                    f"Unsupported/notRun phase must preserve an explicit skip reason: {key}")
    views = [r for r in records if r.get("type") == "webviewBackend" and
             r.get("event") == "created"]
    require(len(views) >= 3 and
            len({r.get("attachmentId") for r in views}) == len(views),
            "Missing or duplicated native WebView ownership")
    require(all(r.get("runId") == metadata["runId"] and
                r.get("backend", {}).get("availability") == "unsupported" and
                r.get("backend", {}).get("verified") is False and
                r.get("backend", {}).get("observed") is None for r in views),
            "Apple backend availability must not be fabricated as Windows composition")
    windows = [r for r in records if r.get("type") == "nativeWindow"]
    require(len(windows) >= 1, "Missing OS window evidence")
    if platform == "macos":
        require(all(r.get("availability") == "collected" and r.get("ready") is True
                    for r in windows), "macOS native window never confirmed fully visible")
    else:
        require(all(r.get("availability") == "unsupported" for r in windows),
                "iOS desktop window probe must explicitly be unsupported")
    heartbeat = [r for r in records if r.get("type") == "heartbeatObservation"]
    require(len(heartbeat) == 1, "Missing one native post-resume observation")
    before = heartbeat[0].get("beforeHide", {})
    after = heartbeat[0].get("afterResume", {})
    require(all(before.get(key) == after.get(key) and before.get(key) is not None
                for key in ("schemaVersion", "revision", "draft")),
            "Resume lost or replaced live document state")
    background = [r for r in records if r.get("type") == "backgroundObservation"]
    require(len(background) == 1 and background[0].get("readAfterExplicitWake") is True,
            "Background fixture evidence missing or misrepresented as passive")
    return {"status": "passed", "scope": "synthetic native WKWebView only",
            "passedPhases": len(PASSED), "unsupportedPhases": len(UNSUPPORTED),
            "notRunPhases": len(NOT_RUN), "platform": platform, "mode": mode,
            "commit": commit, "fixtureSha256": metadata["fixtureSha256"],
            "limitations": metadata.get("limitations", [])}


def validate_directory(root, platform, mode, commit):
    matches = list(Path(root).glob("run-*/report.json"))
    require(len(matches) == 1, f"Expected one fresh native report, found {len(matches)}")
    return validate(json.loads(matches[0].read_text(encoding="utf-8-sig")),
                    platform, mode, commit)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--platform", choices=("macos", "ios"), required=True)
    parser.add_argument("--mode", choices=("profile", "debug"), required=True)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()
    try:
        outcome = validate_directory(args.root, args.platform, args.mode, args.commit)
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"NATIVE APPLE SMOKE INVALID: {exc}", file=sys.stderr)
        raise SystemExit(1)
    print(json.dumps(outcome, ensure_ascii=False, indent=2))
