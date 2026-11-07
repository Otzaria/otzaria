#!/usr/bin/env python3
"""Read-only, exact-artifact diagnosis for the installed desktop probe."""
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess
import urllib.parse
import urllib.request
import zipfile

SOURCE = "f4ac011f1b8c81d4a760eeeadfe037228fb944e3"
SOURCE_TREE = "1767f0161e11567f3d4d0eb703d1bdeb1950272b"
NATIVE_HEAD = "f4893ce470cb6f7dbdb432c2c5b98d89b10dd03f"
RUN = 42329492076
import sys
import math
CASE = sys.argv[1]
CASES = {
    "windows": {"artifact": 13556734016, "bytes": 13268,
                "sha256": "c75706d7d3dd56d55e1466d68e18a4ffcca49f194433c24adccbe6a7d76e6a8a"},
    "macos": {"artifact": 13557004468, "bytes": 67070,
              "sha256": "3202854c50fdf3e88983a1fb42cb06fd4cc8d99e506a0b03455c2c00d3d422e1"},
}
if CASE not in CASES:
    raise RuntimeError("Unknown diagnostic artifact case")
ARTIFACT = CASES[CASE]["artifact"]
EXPECTED_BYTES = CASES[CASE]["bytes"]
EXPECTED_SHA256 = CASES[CASE]["sha256"]
QA_FILES = {"tool/perf_probe/qa_4424_native_diagnostic.py",
            ".github/workflows/qa_4424_native_diagnostic.yml"}
TOKEN = os.environ.pop("QA_GITHUB_TOKEN", "")
os.environ.pop("GITHUB_TOKEN", None)
os.environ.pop("GH_TOKEN", None)
ROOT = Path.cwd().resolve()
OUT = Path(os.environ["QA_EVIDENCE_DIR"]).resolve()
OUT.mkdir(parents=True, exist_ok=False)

def sha256(data):
    return hashlib.sha256(data).hexdigest()

def git(*args):
    result = subprocess.run(["git", *args], cwd=ROOT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError("Git binding command failed: " + repr(args))
    return result.stdout.strip()

def save(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        target = urllib.parse.urlparse(newurl)
        if target.scheme != "https":
            raise RuntimeError("Artifact redirect must use HTTPS")
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if redirected is not None:
            for name in list(redirected.headers):
                if name.lower() == "authorization":
                    redirected.remove_header(name)
            for name in list(redirected.unredirected_hdrs):
                if name.lower() == "authorization":
                    redirected.remove_header(name)
        return redirected

def read_api(path, max_bytes):
    if not path.startswith("/repos/Otzaria/otzaria/actions/artifacts/"):
        raise RuntimeError("Unexpected artifact API path")
    headers = {"Accept": "application/vnd.github+json",
               "X-GitHub-Api-Version": "2022-11-28",
               "User-Agent": "Otzaria-read-only-4424-QA"}
    if TOKEN:
        headers["Authorization"] = "Bearer " + TOKEN
    request = urllib.request.Request("https://api.github.com" + path, headers=headers)
    opener = urllib.request.build_opener(SafeRedirect)
    data = bytearray()
    with opener.open(request, timeout=60) as response:
        while True:
            chunk = response.read(65536)
            if not chunk:
                break
            data.extend(chunk)
            if len(data) > max_bytes:
                raise RuntimeError("Bounded artifact response exceeded its byte limit")
    return bytes(data)

def file_snapshot(directory):
    files = []
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise RuntimeError("Unexpected extracted symlink")
        if path.is_file():
            data = path.read_bytes()
            files.append({"path": path.relative_to(directory).as_posix(),
                          "bytes": len(data), "sha256": sha256(data)})
    return files

qa_head = git("rev-parse", "HEAD")
if git("rev-parse", "HEAD^") != SOURCE or git("rev-parse", SOURCE + "^{tree}") != SOURCE_TREE:
    raise RuntimeError("QA is not a direct child of the frozen source")
if set(git("diff", "--name-only", SOURCE, qa_head).splitlines()) != QA_FILES:
    raise RuntimeError("QA commit contains undeclared files")
if git("status", "--porcelain=v1"):
    raise RuntimeError("QA checkout is initially modified")
binding = {"source": SOURCE, "sourceTree": SOURCE_TREE, "qaHead": qa_head,
           "nativeHead": NATIVE_HEAD, "runId": RUN, "artifactId": ARTIFACT, "platformCase": CASE}
save("binding.json", binding)

metadata = json.loads(read_api("/repos/Otzaria/otzaria/actions/artifacts/" + str(ARTIFACT), 65536))
save("artifact-metadata.json", metadata)
if (metadata.get("id") != ARTIFACT or metadata.get("size_in_bytes") != EXPECTED_BYTES or
        metadata.get("digest") != "sha256:" + EXPECTED_SHA256 or metadata.get("expired") is not False or
        metadata.get("workflow_run", {}).get("id") != RUN or
        metadata.get("workflow_run", {}).get("head_sha") != NATIVE_HEAD):
    raise RuntimeError("Artifact metadata does not match the frozen native run")
raw_zip = read_api("/repos/Otzaria/otzaria/actions/artifacts/" + str(ARTIFACT) + "/zip", EXPECTED_BYTES + 1)
if len(raw_zip) != EXPECTED_BYTES or sha256(raw_zip) != EXPECTED_SHA256:
    raise RuntimeError("Downloaded artifact bytes or SHA256 differ")
(OUT / "original-native-artifact.zip").write_bytes(raw_zip)
extracted = OUT / "native-artifact"
extracted.mkdir()
names = set()
total_bytes = 0
with zipfile.ZipFile(io.BytesIO(raw_zip)) as archive:
    entries = archive.infolist()
    if len(entries) > 128:
        raise RuntimeError("Artifact contains too many entries")
    for entry in entries:
        name = entry.filename
        path = PurePosixPath(name)
        if (not name or name.startswith("/") or "\\" in name or ":" in name or
                ".." in path.parts or name in names or stat.S_ISLNK(entry.external_attr >> 16)):
            raise RuntimeError("Unsafe or duplicate ZIP entry")
        names.add(name)
        target = extracted.joinpath(*path.parts)
        if not target.resolve().is_relative_to(extracted):
            raise RuntimeError("ZIP target escaped its fresh root")
        if entry.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        total_bytes += entry.file_size
        if entry.file_size > 16 * 1024 * 1024 or total_bytes > 64 * 1024 * 1024:
            raise RuntimeError("Artifact exceeds its extraction limit")
        data = archive.read(entry)
        if len(data) != entry.file_size:
            raise RuntimeError("ZIP entry size is inconsistent")
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as stream:
            stream.write(data)

before = file_snapshot(extracted)
save("extracted-manifest-before.json", before)
selected_names = {"windows-native-exit.json", "windows-native-exit-start.json",
                  "windows-device-report.json", "native-exit-control.json",
                  "run.log", "fixture-errors.txt", "source-commit.txt",
                  "flutter.json", "source-provenance.json"}
selected = []
parsed_files = {}
for item in before:
    path = extracted / item["path"]
    if path.name not in selected_names and not (CASE == "macos" and path.suffix == ".json"):
        continue
    data = path.read_bytes()
    row = dict(item)
    if len(data) <= 2 * 1024 * 1024:
        row["completeText"] = data.decode("utf-8-sig", "strict")
        if path.suffix == ".json":
            try:
                parsed = json.loads(row["completeText"])
                parsed_files[item["path"]] = parsed
                if CASE == "windows":
                    row["json"] = parsed
            except json.JSONDecodeError as error:
                row["jsonDecodeError"] = {"file": item["path"], "message": error.msg,
                                          "line": error.lineno, "column": error.colno, "position": error.pos}
    else:
        row["textTruncated"] = True
        row["prefix"] = data[:32768].decode("utf-8", "replace")
        row["suffix"] = data[-32768:].decode("utf-8", "replace")
    selected.append(row)
receipts = [item for item in selected if PurePosixPath(item["path"]).name == "windows-native-exit.json"]
if len(receipts) > 1:
    raise RuntimeError("Ambiguous native exit receipts")
receipt = receipts[0].get("json", {}) if receipts else {}
if receipt and receipt.get("commit") != NATIVE_HEAD:
    raise RuntimeError("Native receipt commit does not match the retained run")
receipt_availability = "collected" if receipt else "notProducedOrNotComplete"

def finite_nonnegative(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value >= 0

def installed_contract(report):
    problems = []
    required = {"startup", "firstOpen", "visibleIdle", "stateAndScroll", "multipleOpen",
                "hiddenIdle", "memoryPressure", "restore", "protectedControls", "countPolicy",
                "agePolicy", "storeRestore", "backgroundOpen", "backgroundIdle", "backgroundClose",
                "close", "closedIdle", "minimize", "hide"}
    phases = report.get("phases")
    by_name = {}
    if not isinstance(phases, list):
        problems.append("Missing phase records")
        phases = []
    for phase in phases:
        if not isinstance(phase, dict) or phase.get("name") in by_name:
            problems.append("Invalid or duplicate phase")
            continue
        by_name[phase.get("name")] = phase
    for name in sorted(required):
        if by_name.get(name, {}).get("status") != "passed":
            problems.append("Required desktop phase did not pass: " + name)
    proofs = report.get("restorations")
    scenarios = set()
    required_bools = ("sameInstanceId", "releasedByDispatcher", "controllerAbsentAfterDiscard",
                      "hostWidgetRemovedBeforeRestore", "differentControllerObject", "differentDocument",
                      "sdkBooted", "visibleStateMatches")
    if not isinstance(proofs, list) or len(proofs) < 4:
        problems.append("Missing policy restoration proofs")
        proofs = []
    for proof in proofs:
        if not isinstance(proof, dict):
            problems.append("Invalid restoration")
            continue
        scenarios.add(proof.get("scenario"))
        for key in required_bools:
            if proof.get(key) is not True:
                problems.append("Restore proof requires " + key)
        before_id, after_id = proof.get("before"), proof.get("after")
        if not isinstance(before_id, dict) or not isinstance(after_id, dict):
            problems.append("Missing restoration identities")
            continue
        for key in ("pluginId", "instanceId"):
            if not isinstance(before_id.get(key), str) or not before_id[key] or before_id[key] != after_id.get(key):
                problems.append("Restoration identity mismatch: " + key)
        if (not isinstance(before_id.get("documentToken"), str) or not before_id["documentToken"] or
                not isinstance(after_id.get("documentToken"), str) or not after_id["documentToken"] or
                before_id["documentToken"] == after_id["documentToken"]):
            problems.append("Restored document did not change")
        if not finite_nonnegative(proof.get("resumeMs")):
            problems.append("Invalid measured resume duration")
    if not {"pressure", "count", "age", "store"}.issubset(scenarios):
        problems.append("Not all discard policies were exercised")
    guards = report.get("protectedControls")
    blockers, requests = set(), set()
    if not isinstance(guards, list) or len(guards) != 4:
        problems.append("Four protected controls are required")
        guards = []
    for guard in guards:
        if not isinstance(guard, dict):
            problems.append("Invalid protected control")
            continue
        blockers.add(guard.get("firstBlockingReason"))
        requests.add(guard.get("discardRequestId"))
        if guard.get("sameControllerAfterRequest") is not True or guard.get("released") is not False:
            problems.append("Protected instance was released or replaced")
    if blockers != {"noRestoreState", "unsavedChanges", "busyRpc", "contextMenu"} or len(requests) != 1 or None in requests:
        problems.append("Protected controls do not share the required request/blockers")
    quiet = report.get("quietWindows")
    if not isinstance(quiet, list) or not quiet:
        problems.append("Missing quiet windows")
        quiet = []
    for window in quiet:
        if (not isinstance(window, dict) or window.get("probeJsCalls") != 0 or
                window.get("probeNativeQueries") != 0 or not finite_nonnegative(window.get("elapsedMs")) or
                window.get("elapsedMs", 0) <= 0):
            problems.append("Quiet window contains probe work or invalid duration")
    if report.get("policyRestored") is not True:
        problems.append("Dispatcher policy was not restored")
    for field in ("errors", "testFailures", "contractErrors"):
        if report.get(field) != []:
            problems.append("Final report field is not an empty list: " + field)
    if report.get("status") != "passed" or report.get("platform") != "macos" or report.get("buildMode") != "profile":
        problems.append("Final report is not a passing macOS profile report")
    if report.get("commit") != NATIVE_HEAD or not isinstance(report.get("pid"), int) or report["pid"] <= 0:
        problems.append("Native commit or process identity is incorrect")
    if not isinstance(report.get("runId"), str) or not report["runId"].startswith(str(report.get("pid")) + "-"):
        problems.append("Run identifier does not bind to the native PID")
    return problems

mac_reports = []
if CASE == "macos":
    for path, value in parsed_files.items():
        name = PurePosixPath(path).name
        report = None
        kind = None
        if name == "installed-plugin-report.json" and isinstance(value, dict):
            report, kind = value, "device"
        elif name == "report.json" and isinstance(value, dict):
            report, kind = value.get("installedPluginProbe"), "framework"
        if not isinstance(report, dict):
            continue
        problems = installed_contract(report)
        mac_reports.append({"path": path, "kind": kind, "validationErrors": problems,
                            "commit": report.get("commit"), "runId": report.get("runId"),
                            "pid": report.get("pid"), "status": report.get("status"),
                            "platform": report.get("platform"), "buildMode": report.get("buildMode"),
                            "errors": report.get("errors"), "testFailures": report.get("testFailures"),
                            "contractErrors": report.get("contractErrors"),
                            "phases": [{"name": phase.get("name"), "status": phase.get("status"),
                                        "error": phase.get("error")} for phase in report.get("phases", [])],
                            "restorations": report.get("restorations"),
                            "protectedControls": report.get("protectedControls"),
                            "quietWindows": report.get("quietWindows"),
                            "policyRestored": report.get("policyRestored"),
                            "pinnedStore": report.get("pinnedStore"),
                            "platformMatrix": report.get("platformMatrix"),
                            "fixtureSha256": report.get("fixtureSha256"),
                            "catalogFixture": report.get("catalogFixture")})
    kinds = {item["kind"] for item in mac_reports}
    identity_set = {(item["commit"], item["runId"], item["pid"]) for item in mac_reports}
    mac_acceptance = (kinds == {"device", "framework"} and len(mac_reports) == 2 and
                      len(identity_set) == 1 and all(not item["validationErrors"] for item in mac_reports))
else:
    mac_acceptance = False

after = file_snapshot(extracted)
save("extracted-manifest-after.json", after)
if before != after or git("status", "--porcelain=v1"):
    raise RuntimeError("Read-only diagnosis changed artifact or app source")
summary = {**binding, "diagnosticStatus": "COMPLETED", "nativeAcceptance": ("PASSED" if mac_acceptance else "FAILED") if CASE == "macos" else "FAILED",
           "artifactZip": {"bytes": len(raw_zip), "sha256": sha256(raw_zip)},
           "fileCount": len(before), "extractedBytes": sum(item["bytes"] for item in before),
           "artifactBytesUnchanged": True, "applicationSourceUnchanged": True,
           "allFiles": before, "selectedFiles": selected, "macReports": mac_reports,
           "macAcceptanceValidated": mac_acceptance if CASE == "macos" else None,
           "receiptAvailability": receipt_availability, "firstError": receipt.get("firstError"),
           "driverExitCode": receipt.get("driverExitCode"),
           "driverError": receipt.get("driverError"),
           "diagnosticErrors": receipt.get("diagnosticErrors"),
           "observer": receipt.get("observer"),
           "stepExitCode": receipt.get("stepExitCode"),
           "artifactCodeExecuted": False}
save("diagnostic-summary.json", summary)
print("BEGIN_QA4424_NATIVE_DIAGNOSTIC", flush=True)
print(json.dumps(summary, ensure_ascii=False), flush=True)
print("END_QA4424_NATIVE_DIAGNOSTIC", flush=True)
