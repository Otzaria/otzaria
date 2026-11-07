#!/usr/bin/env python3
"""Read retained #4124 native artifacts without executing artifact content."""
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess
import urllib.parse
import urllib.request
import zipfile

BASE = "8417d2accbb02a65dcd8f331318c35c1c5b92946"
MERGE = "1408b652bf522401dc16c6a17d13a87ad25cb146"
TREE = "b774834058cb9b945f37947cf0ebb6db8ebd2919"
REPO = "Otzaria/otzaria"
OUTPUT = Path(os.environ["EVIDENCE_OUTPUT"])
OUTPUT.mkdir(parents=True, exist_ok=False)
API = "https://api.github.com/repos/" + REPO

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        result = super().redirect_request(req, fp, code, msg, headers, newurl)
        if result is not None and urllib.parse.urlsplit(newurl).netloc != urllib.parse.urlsplit(req.full_url).netloc:
            result.remove_header("Authorization")
        if urllib.parse.urlsplit(newurl).scheme != "https":
            raise RuntimeError("Non-HTTPS artifact redirect")
        return result

opener = urllib.request.build_opener(SafeRedirect())
def read_api(suffix, binary=False):
    request = urllib.request.Request(API + suffix, headers={
        "Authorization": "Bearer " + os.environ["GH_TOKEN"],
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    with opener.open(request, timeout=60) as response:
        data = response.read(64 * 1024 * 1024 + 1)
    if len(data) > 64 * 1024 * 1024:
        raise RuntimeError("Oversized response")
    return data if binary else json.loads(data)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def save(name, value):
    (OUTPUT / name).write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")

def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()

changes = git("diff", "--name-only", BASE, "HEAD").splitlines()
assert sorted(changes) == [".github/workflows/qa_4124_native_evidence.yml", "tool/perf_probe/qa_4124_native_evidence.py"], changes
before = git("status", "--porcelain=v1", "--untracked-files=all")
assert not before, before
merge = read_api("/git/commits/" + MERGE)
assert merge["tree"]["sha"] == TREE
assert [p["sha"] for p in merge["parents"]] == ["2aa04e69f4b6802bd376aed41f529590a6c4f9b3", BASE]
save("linux-merge-source.json", merge)
summaries = {}
for label, artifact_id, size, digest in [
    ("linux", 13553424184, 142521, "c180767ef8ef1c98447f89c1ff7c8ca3f7f13ecd98eff428fdc9ad6d549d750b"),
    ("android-inherited-macos", 13552941650, 73142, "302f6211466c012bcdb24ab7a1c963b7b94eade3bc7c9e3edcdf0672970bb279"),
    ("android-inherited-windows", 13552290630, 10798, "f7c0ecaf87d5ce618293c10628b71fc9631f4bb48c1eff89d8fb2967583d5347"),
]:
    metadata = read_api("/actions/artifacts/" + str(artifact_id))
    assert metadata["id"] == artifact_id and not metadata["expired"]
    assert metadata["digest"] == "sha256:" + digest
    assert metadata["size_in_bytes"] == size
    raw = read_api("/actions/artifacts/" + str(artifact_id) + "/zip", binary=True)
    assert len(raw) == size and sha(raw) == digest
    archive = OUTPUT / (label + ".zip")
    archive.write_bytes(raw)
    root = OUTPUT / label
    root.mkdir()
    files = []
    with zipfile.ZipFile(archive) as z:
        names = set()
        assert len(z.infolist()) < 2000
        assert sum(info.file_size for info in z.infolist()) < 64 * 1024 * 1024
        for info in z.infolist():
            path = PurePosixPath(info.filename)
            assert not path.is_absolute() and ".." not in path.parts and "\\" not in info.filename
            assert info.filename not in names
            names.add(info.filename)
            assert not stat.S_ISLNK(info.external_attr >> 16)
            if info.is_dir():
                continue
            data = z.read(info)
            destination = root.joinpath(*path.parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            files.append({"path": info.filename, "bytes": len(data), "sha256": sha(data)})
    receipt = {"artifact": metadata, "verifiedArchiveBytes": len(raw), "verifiedSha256": digest, "files": files}
    save(label + "-receipt.json", receipt)
    reports = []
    for file in root.rglob("*.json"):
        try:
            value = json.loads(file.read_text(encoding="utf-8-sig"))
        except (ValueError, UnicodeError):
            continue
        if not isinstance(value, dict):
            continue
        report = value.get("installedPluginProbe", value)
        if isinstance(report, dict) and "platform" in report and "phases" in report and "runId" in report:
            reports.append((file, report, "installedPluginProbe" in value))
    summary = {"artifactId": artifact_id, "archiveSha256": digest, "fileCount": len(files), "reports": []}
    for file, report, wrapped in reports:
        summary["reports"].append({
            "path": str(file.relative_to(root)), "wrapped": wrapped,
            "schemaVersion": report.get("schemaVersion"), "status": report.get("status"),
            "platform": report.get("platform"), "buildMode": report.get("buildMode"),
            "pid": report.get("pid"), "runId": report.get("runId"), "commit": report.get("commit"),
            "errors": report.get("errors"), "contractErrors": report.get("contractErrors"),
            "policyRestored": report.get("policyRestored"), "phases": report.get("phases"),
            "restorations": report.get("restorations"), "protectedControls": report.get("protectedControls"),
            "quietWindows": report.get("quietWindows"),
        })
    if label == "linux":
        wrapped = [(file, report) for file, report, is_wrapped in reports if is_wrapped]
        assert len(wrapped) == 1, [str(file) for file, _ in wrapped]
        file, report = wrapped[0]
        spec = importlib.util.spec_from_file_location("trusted_linux_runner", "tool/perf_probe/run_installed_plugin_linux.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        summary["trustedLinuxValidator"] = module.require_linux_result(file.parent.parent)
        assert report["commit"] == MERGE
        assert report["flutterVersion"] == "3.47.7"
        assert report["runId"].split("-", 1)[0] == str(report["pid"])
        phases = {phase["name"]: phase for phase in report["phases"]}
        required = ["startup", "firstOpen", "visibleIdle", "stateAndScroll", "multipleOpen",
                    "hiddenIdle", "memoryPressure", "restore", "protectedControls", "countPolicy",
                    "agePolicy", "storeRestore", "backgroundOpen", "backgroundIdle", "backgroundClose",
                    "close", "closedIdle", "minimize", "hide"]
        assert all(phases[name]["status"] == "passed" for name in required)
        assert len(phases) == len(report["phases"])
        assert {proof["scenario"] for proof in report["restorations"]} >= {"pressure", "count", "age", "store"}
        for proof in report["restorations"]:
            for key in ["sameInstanceId", "releasedByDispatcher", "controllerAbsentAfterDiscard",
                        "hostWidgetRemovedBeforeRestore", "differentControllerObject",
                        "differentDocument", "sdkBooted", "visibleStateMatches"]:
                assert proof[key] is True, (proof["scenario"], key)
            for key in ["pluginId", "instanceId"]:
                assert isinstance(proof["before"][key], str) and proof["before"][key]
                assert proof["before"][key] == proof["after"][key]
            assert proof["before"]["documentToken"] and proof["after"]["documentToken"]
            assert proof["before"]["documentToken"] != proof["after"]["documentToken"]
            assert isinstance(proof["resumeMs"], (int, float)) and not isinstance(proof["resumeMs"], bool)
            assert math.isfinite(proof["resumeMs"]) and proof["resumeMs"] >= 0
        guards = report["protectedControls"]
        assert len(guards) == 4
        assert {guard["firstBlockingReason"] for guard in guards} == {"noRestoreState", "unsavedChanges", "busyRpc", "contextMenu"}
        assert len({guard["discardRequestId"] for guard in guards}) == 1 and guards[0]["discardRequestId"] is not None
        assert all(guard["sameControllerAfterRequest"] is True and guard["released"] is False for guard in guards)
        assert report["quietWindows"]
        for window in report["quietWindows"]:
            assert window["probeJsCalls"] == 0 and window["probeNativeQueries"] == 0
            assert math.isfinite(window["elapsedMs"]) and window["elapsedMs"] > 0
            assert window["productionTimersDisabled"] is False
        sessions = list(root.rglob("session.json"))
        assert len(sessions) == 1
        session = json.loads(sessions[0].read_text())
        assert session["status"] == "passed" and session["sessionExitCode"] == 0
        assert session["driveExitCode"] == 0 and session["timedOut"] is False
        assert session["scenarioResult"]["runId"] == report["runId"]
        summary["session"] = session
        summary["acceptance"] = "PASS: retained Linux profile artifact; physical-device and performance claims excluded"
    elif label == "android-inherited-macos":
        assert any(report["status"] == "failed" for _, report, _ in reports)
        summary["acceptance"] = "FAIL: retained inherited macOS run"
    else:
        summary["acceptance"] = "DIAGNOSTIC ONLY: inherited Windows failure, actual app not established"
        summary["jsonDiagnostics"] = {}
        for file in root.rglob("*.json"):
            try:
                summary["jsonDiagnostics"][str(file.relative_to(root))] = json.loads(file.read_text(encoding="utf-8-sig"))
            except (ValueError, UnicodeError):
                pass
    summaries[label] = summary
    save(label + "-summary.json", summary)
    print("BEGIN_" + label.upper().replace("-", "_") + "_SUMMARY")
    print(json.dumps(summary, ensure_ascii=False, allow_nan=False))
    print("END_" + label.upper().replace("-", "_") + "_SUMMARY")
after = git("status", "--porcelain=v1", "--untracked-files=all")
assert after == before, after
save("source-integrity.json", {"head": git("rev-parse", "HEAD"), "base": BASE, "qaOnlyChanges": changes,
                              "before": before, "after": after, "artifactContentExecuted": False})
print("REPLAY_COMPLETE: archive hashes, source identity, Linux phase/restore/quiet/guard evidence and inherited diagnostics checked")
