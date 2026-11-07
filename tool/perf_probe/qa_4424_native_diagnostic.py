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

SOURCE = "05e150d09758e0da45ca1877a4d650358f1aa17f"
SOURCE_TREE = "e43bd8f0db6d1b2a107f767c18e3261a27e15837"
NATIVE_HEAD = "54d7efd98914f2d8a8285729f62cf71a6b7622c0"
RUN = 42335402384
import sys
import math
import ntpath
import re
from datetime import datetime, timezone, timedelta
CASE = "windows"
ARTIFACT = 13559674644
EXPECTED_BYTES = 5387308
EXPECTED_SHA256 = "ea7b139e2480ff35c7ec4528c076c41ed5c5cd46eb37cc9a8a3c3fb153b6a1e9"
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
    if len(entries) > 512:
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
        if entry.file_size > 32 * 1024 * 1024 or total_bytes > 256 * 1024 * 1024:
            raise RuntimeError("Artifact exceeds its extraction limit")
        data = archive.read(entry)
        if len(data) != entry.file_size:
            raise RuntimeError("ZIP entry size is inconsistent")
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as stream:
            stream.write(data)

before = file_snapshot(extracted)
save("extracted-manifest-before.json", before)
def finite_nonnegative(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value >= 0

def installed_contract(report, kind):
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
    if not isinstance(proofs, list) or len(proofs) != 7:
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
    if not isinstance(quiet, list) or len(quiet) != 6:
        problems.append("Missing quiet windows")
        quiet = []
    for window in quiet:
        if (not isinstance(window, dict) or window.get("probeJsCalls") != 0 or
                window.get("probeNativeQueries") != 0 or not finite_nonnegative(window.get("elapsedMs")) or
                window.get("elapsedMs", 0) < window.get("requestedMs", 1000) or window.get("productionTimersDisabled") is not False):
            problems.append("Quiet window contains probe work or invalid duration")
    if report.get("policyRestored") is not True:
        problems.append("Dispatcher policy was not restored")
    for field in (("errors", "testFailures", "contractErrors") if kind == "device" else ("errors", "contractErrors")):
        if report.get(field) != []:
            problems.append("Final report field is not an empty list: " + field)
    if report.get("status") != "passed" or report.get("platform") != "windows" or report.get("buildMode") != "profile":
        problems.append("Final report is not a passing Windows profile report")
    if report.get("commit") != NATIVE_HEAD or not isinstance(report.get("pid"), int) or report["pid"] <= 0:
        problems.append("Native commit or process identity is incorrect")
    if not isinstance(report.get("runId"), str) or not report["runId"].startswith(str(report.get("pid")) + "-"):
        problems.append("Run identifier does not bind to the native PID")
    return problems


parsed = {}
decode_errors = []
for row in before:
    path = extracted / row["path"]
    if path.suffix != ".json":
        continue
    try:
        parsed[row["path"]] = json.loads(path.read_text(encoding="utf-8-sig"))
    except (UnicodeError, json.JSONDecodeError) as error:
        decode_errors.append({"path": row["path"], "error": str(error), "bytes": row["bytes"], "sha256": row["sha256"]})


# Export original runtime evidence before evaluating any acceptance condition.
# Missing, invalid, unavailable and truncated records remain distinct evidence.
runtime_names = {
    "installed-plugin-report.json", "report.json", "windows-native-exit.json",
    "windows-native-exit-start.json", "windows-device-report.json",
    "native-exit-control.json", "source-provenance.json", "run.log",
    "fixture-errors.txt", "fixture-tests.log", "source-commit.txt",
}
runtime_presence = {}
for expected_name in sorted(runtime_names):
    matches = [row for row in before if PurePosixPath(row["path"]).name == expected_name]
    runtime_presence[expected_name] = {
        "availability": "present" if matches else "notProduced",
        "count": len(matches), "files": matches,
    }
runtime_exports = []
for row in before:
    name = PurePosixPath(row["path"]).name
    if name not in runtime_names:
        continue
    data = (extracted / row["path"]).read_bytes()
    item = {**row, "originalRetainedInArtifact": True}
    try:
        content = data.decode("utf-8")
        if len(data) <= 512 * 1024:
            item.update({"textAvailability": "complete", "truncated": False, "completeText": content})
        else:
            item.update({"textAvailability": "boundedPreview", "truncated": True,
                         "prefix": content[:32768], "suffix": content[-32768:]})
    except UnicodeError as error:
        item.update({"textAvailability": "decodeError", "truncated": False, "error": str(error)})
    runtime_exports.append(item)
runtime_evidence = {
    **binding, "artifact": metadata,
    "artifactZipBytes": len(raw_zip), "artifactZipSha256": sha256(raw_zip),
    "presence": runtime_presence, "allFiles": before, "decodeErrors": decode_errors,
    "rawTextExports": runtime_exports,
    "nativeControlIsSeparateFromActualApp": True,
    "acceptanceEvaluated": False,
}
save("original-native-runtime-evidence.json", runtime_evidence)
print("BEGIN_QA4424_ORIGINAL_NATIVE_RUNTIME_EVIDENCE", flush=True)
print(json.dumps(runtime_evidence, ensure_ascii=False), flush=True)
print("END_QA4424_ORIGINAL_NATIVE_RUNTIME_EVIDENCE", flush=True)

problems = []
def require(condition, message):
    if not condition:
        problems.append(message)

def one(name, required=True, folder=None):
    matches = [(path, value) for path, value in parsed.items()
               if PurePosixPath(path).name == name and (folder is None or folder in PurePosixPath(path).parts)]
    if len(matches) != 1:
        if required:
            problems.append("Expected exactly one " + name + " in " + str(folder) + ", got " + str(len(matches)))
        return None, {}
    path, value = matches[0]
    if not isinstance(value, dict):
        problems.append("Expected JSON object in " + path + ", actual original type: " + type(value).__name__)
        return path, {}
    return path, value

def utc(value):
    if not isinstance(value, str):
        raise ValueError("Missing UTC timestamp")
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)

def ft(value):
    if not isinstance(value, str) or not value.isdigit():
        raise ValueError("FILETIME must be a decimal string")
    return datetime(1601, 1, 1, tzinfo=timezone.utc) + timedelta(microseconds=int(value) // 10)

def winpath(value):
    if not isinstance(value, str):
        return None
    return ntpath.normcase(ntpath.normpath(value))

def bytes_for(path):
    return (extracted / path).read_bytes() if path else b""

device_path, device = one("installed-plugin-report.json", folder="device")
framework_path, framework_envelope = one("report.json", folder="host")
framework = framework_envelope.get("installedPluginProbe", {}) if isinstance(framework_envelope, dict) else {}
receipt_path, receipt = one("windows-native-exit.json")
start_path, start = one("windows-native-exit-start.json")
snapshot_path, device_snapshot = one("windows-device-report.json")
control_path, native_control = one("native-exit-control.json")
provenance_path, provenance = one("source-provenance.json")
require(provenance.get("repository") == "Otzaria/otzaria-plugins-store" and provenance.get("commit") == "4517d39c4ecab632aff98e1c0e414881695961aa" and provenance.get("sha256") == {"manifest.json":"a40e4225682f948d657e94086217f8400b4d708ec1eaa958e37621113bd12feb","index.html":"c6495a41ffc31a8e4b23828b3537c40478d0aa7d45a3cf680534e4e0cd0fed2f","restore-state.js":"f0324b025009e9594135b17b911366388959ab5398c0485ac11b0316cd59332f","i18n/en.js":"54f9ec3b69a2858d2a1bb0f6d80f641397c3ff1fd286a83cdb5e751af3366ef2","background.html":"0110c549b0350222c63c098843c9b6debdcd61cebd57d91b11874f07426fc975"}, "Prepared read-only Store provenance does not match the exact five sources")
for kind, report in (("device", device), ("framework", framework)):
    if not isinstance(report, dict):
        problems.append("Invalid " + kind + " report")
        continue
    problems.extend(kind + ": " + message for message in installed_contract(report, kind))
    require(report.get("physicalDeviceAcceptance") is False, kind + " must remain controlled desktop only")
    require(report.get("flutterVersion") == "3.47.7" and str(report.get("dartVersion", "")).startswith("3.13.5 "), kind + " toolchain mismatch")
    require(report.get("observer", {}).get("developerDiagnosticsCollecting") is False, kind + " diagnostics were enabled")
    require(report.get("setupStep") == "complete", kind + " setup did not complete")
    require([p.get("scenario") for p in report.get("restorations", [])].count("pressure") == 4, kind + " needs four distinct pressure restores")
    require({q.get("name") for q in report.get("quietWindows", [])} == {"visibleIdle","minimizeIdle","hideIdle","hiddenIdle","backgroundIdle","closedIdle"}, kind + " quiet window identities mismatch")
    require(report.get("platformMatrix", {}).get("windows", {}).get("status") == "passed", kind + " Windows platform matrix not passed")
    store = report.get("pinnedStore", {})
    require(store.get("commit") == "4517d39c4ecab632aff98e1c0e414881695961aa", kind + " Store commit mismatch")
    require(store.get("sha256") == {"manifest.json":"a40e4225682f948d657e94086217f8400b4d708ec1eaa958e37621113bd12feb","index.html":"c6495a41ffc31a8e4b23828b3537c40478d0aa7d45a3cf680534e4e0cd0fed2f","restore-state.js":"f0324b025009e9594135b17b911366388959ab5398c0485ac11b0316cd59332f","i18n/en.js":"54f9ec3b69a2858d2a1bb0f6d80f641397c3ff1fd286a83cdb5e751af3366ef2","background.html":"0110c549b0350222c63c098843c9b6debdcd61cebd57d91b11874f07426fc975"}, kind + " five Store source file hashes mismatch")
    for restoration in report.get("restorations", []):
        before_id, after_id = restoration.get("before", {}), restoration.get("after", {})
        require(before_id.get("controllerObjectId") != after_id.get("controllerObjectId"), kind + " controller identity did not change")
        require(restoration.get("beforeVisibleState") == restoration.get("afterVisibleState"), kind + " restored visible state differs")
    for phase in report.get("phases", []):
        if phase.get("name") == "osBackground":
            require(phase.get("status") == "notRun", kind + " mobile OS background must not be inferred from desktop")

device_before_final_callback = dict(device)
device_before_final_callback.pop("testFailures", None)
framework_before_final_callback = dict(framework)
framework_before_final_callback.pop("testFailures", None)
require(device_before_final_callback == framework_before_final_callback, "Framework and final device scenario data or identity differ")
require("testFailures" not in framework or framework["testFailures"] == [], "Framework explicitly reports test failures")
require(device_snapshot == device and bytes_for(snapshot_path) == bytes_for(device_path), "Host snapshot is not byte-identical to final device report")
require(receipt.get("reportSha256") == sha256(bytes_for(device_path)), "Receipt device hash does not match original report bytes")
require(receipt.get("status") == "passed" and receipt.get("stepExitCode") == 0 and receipt.get("driverExitCode") == 0, "Native receipt or actual driver did not pass")
require(receipt.get("commit") == NATIVE_HEAD and start.get("commit") == NATIVE_HEAD, "Native receipt/start source binding mismatch")
for field in ("firstError","driverError","reportReadError"):
    require(receipt.get(field) is None, "Native receipt retained an error: " + field)
require(receipt.get("diagnosticErrors") == [], "Native diagnostic errors are not empty")
require(receipt.get("deviceStatus") == "passed", "Native wrapper did not read a final passing device report")
require(native_control.get("status") == "passed" and native_control.get("child", {}).get("exitCode") == 37, "Production native child37 control missing")
require(native_control.get("trace", {}).get("nativeAdapter") == "InstalledPluginProbe.WindowsProcessFactory", "Control used a fake native process adapter")

trace = receipt.get("observer") or {}
native = receipt.get("nativeExit") or {}
identity = trace.get("identity") or {}
ack = device.get("windowsLifetime") or {}
cleanup = trace.get("cleanup") or {}
require(trace.get("nativeAdapter") == "InstalledPluginProbe.WindowsProcessFactory", "Actual app did not use production native handle adapter")
require(trace.get("availability") == "collected" and trace.get("errors") == [], "Retained native handle evidence is unavailable or failed")
require(trace.get("identityVerified") is True and trace.get("bootstrapQuiescent") is True and trace.get("waitResult") == 0, "Bootstrap identity/quiescence or final native wait not verified")
require(all(cleanup.get(k) is True for k in ("handleAcquired","handleClosed","listenerStopped","channelClosed","bootstrapTaskCompleted")), "Native lifetime cleanup incomplete")
require(ack.get("version") == 1 and ack.get("kind") == "ready" and ack.get("bootstrapQuiescent") is True and "token" not in ack, "Final device acknowledgement is invalid")
require(ack.get("pid") == identity.get("pid") == device.get("pid"), "Final app PID and retained native handle mismatch")
require(ack.get("runId") == trace.get("runId") == device.get("runId") == native.get("runId"), "Native run identity mismatch")
require(ack.get("creationFileTime") == identity.get("creationFileTime") == native.get("creationFileTime"), "Native FILETIME identity mismatch")
require(ack.get("campaignId") == trace.get("campaignId") == start.get("campaignId"), "Authenticated native campaign mismatch")
require(ack.get("executable") == identity.get("executable") == native.get("executable"), "Final acknowledgement executable mismatch")
require(winpath(identity.get("executable")) == winpath(trace.get("expectedExecutable")) == winpath(start.get("expectedExecutable")), "Actual native executable differs from armed target")
require(str(identity.get("executable", "")).lower().endswith("\\build\\windows\\x64\\runner\\profile\\otzaria.exe"), "Native executable is not the actual profile Otzaria app")
require(native.get("availability") == "collected" and native.get("processId") == identity.get("pid"), "Native process exit evidence unavailable")
status = trace.get("exitStatus")
require(isinstance(status, int) and not isinstance(status, bool) and 0 <= status <= 0xffffffff, "Native exit must be actual unsigned32 status")
require(status in (0, 0xffffffff) and native.get("exitStatus") == status, "Observed native exit status violates actual app contract")
require(native.get("exitStatusHex") == ("0x%08X" % status if isinstance(status, int) else None), "Unsigned32 native exit rendering mismatch")
require(native.get("exitFileTime") == trace.get("exitFileTime"), "Native exit FILETIME mismatch")
require(isinstance(trace.get("requestBytes"), int) and 0 < trace["requestBytes"] <= 4096, "Bootstrap request length invalid")
try:
    armed, created, boot, acknowledged, exited, finished = (
        utc(trace["armedAtUtc"]), ft(identity["creationFileTime"]), utc(trace["bootstrapUtc"]),
        utc(trace["acknowledgedAtUtc"]), ft(trace["exitFileTime"]), utc(trace["finishedAtUtc"]))
    require(armed <= created <= boot <= acknowledged < exited <= finished, "Native lifetime chronology is invalid")
    require(utc(ack["acknowledgedAtUtc"]) == acknowledged and utc(start["armedAtUtc"]) == armed, "Native acknowledgement/start timestamps mismatch")
    require(all(acknowledged < utc(q["startedUtc"]) for q in device.get("quietWindows", [])), "Bootstrap was not completed before all quiet windows")
except (KeyError, TypeError, ValueError, OverflowError) as error:
    problems.append("Native timestamp evidence unavailable: " + str(error))
events = receipt.get("applicationErrors") or {}
require(events.get("availability") == "collected" and events.get("truncated") is False and events.get("events") == [] and events.get("limit") == 64, "Correlated Application Error query incomplete, truncated or has events")
fixture_errors = receipt.get("fixtureErrorLog") or {}
require(fixture_errors.get("availability") in ("notProduced", "collected") and fixture_errors.get("truncated", False) is False, "Fixture diagnostic log unavailable or truncated")

# Trusted source awaits complete socket EOF before fixture setup and quiet windows.
# Downloaded evidence is parsed only; no artifact code executes.
support = (ROOT / "integration_test/support/installed_plugin_windows_lifetime.dart").read_text(encoding="utf-8")
scenario = (ROOT / "integration_test/installed_plugin_resource_probe_test.dart").read_text(encoding="utf-8")
require("connected.fold<List<int>>" in support and "await Future.wait<Object?>" in support and "await connected.close();" in support, "Trusted source EOF/bootstrap contract changed")
require(scenario.index("report['windowsLifetime'] = await acknowledgeInstalledWindowsLifetime(") < scenario.index("await catalog.start();"), "Trusted bootstrap ordering changed")
require("binding.allTestsPassed.future.then" in scenario and "report['testFailures']" in scenario and "await finished.future;" in scenario, "Final callback source contract changed")

snapshots = {}
snapshot_receipts = {}
for mode in ("bind", "resolved", "before-native", "after"):
    path, value = one(mode + ".json", folder="qa-snapshots")
    snapshots[mode] = value
    _, row = one(mode + "-receipt.json", folder="qa-snapshots")
    snapshot_receipts[mode] = row
    require(row.get("passed") is True and row.get("qaHead") == NATIVE_HEAD and row.get("sourceCommit") == SOURCE, "Native " + mode + " snapshot did not pass exact binding")
require(snapshots["resolved"] == snapshots["before-native"] == snapshots["after"], "Native app changed source/index/SDK/Git dependency tracked bytes")
for key in ("application","flutter-sdk"):
    require(snapshots["bind"].get(key) == snapshots["after"].get(key), "Native resolution changed original " + key + " checkout")
for root, row in snapshots["after"].items():
    require(row.get("status") == "", "Modified tracked source after native app: " + root)
    require(isinstance(row.get("trackedFiles"), int) and row["trackedFiles"] > 0, "Empty tracked source snapshot: " + root)
    require(len(row.get("files", [])) == row.get("trackedFiles"), "Incomplete tracked file map: " + root)
    calculated = sha256(json.dumps(row.get("files", []), separators=(",", ":"), ensure_ascii=False).encode("utf-8"))
    require(calculated == row.get("trackedSha256"), "Tracked source digest does not match file map: " + root)
_, packages = one("resolved-git-packages-after.json", folder="qa-snapshots")
require({name: item.get("head") for name, item in packages.items()} == {"flutter_inappwebview":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_android":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_ios":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_linux":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_macos":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_platform_interface":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_web":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_windows":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_local_notifications_windows":"ad21cf2cddfa7c79ea7903ad95b38a8d716b5f85","flutter_widget_from_html_core":"57080495ee8b89aeee156a4440b6de1c5e0f7ef2","opentype_shaper":"461902c049b412d64dc4dfa7b547fedbf751211d","otzaria_ashurit":"b43b67bb706be6bc87af14658d67e16cd347fc29","otzaria_icons":"483fec355339f54f9e094994a106dad9a63b82e3","otzaria_search_engine":"2da23091237ed0f0a612de3b2d18cfc99d8b7d2a","pdfrx":"942e27bec86e8d480111517c2083eb52817ee032","printing":"3cb90fb3025553f3e9f48638c79ccf93efb326af","seforim_library_updater":"6bfd33c3bc14392c1a6bb0887fdb23209068eab5","sentry_flutter":"93e7398355e80557a342666f98b23cc9bb832848","window_manager":"88a433a7be43ed0213da12b561bf0d8d070c6d68"}, "All19 resolved Git packages do not match exact frozen lock")
require(snapshots["after"].get("application", {}).get("head") == NATIVE_HEAD, "Actual native app checkout head mismatch")
require(snapshots["after"].get("flutter-sdk", {}).get("head") == "abaf9c523780a608bd46686fd5e53740a07077f8", "Actual native SDK head mismatch")
_, resolution = one("flutter-command-resolution.json", folder="qa-snapshots")
log_paths = [row["path"] for row in before if PurePosixPath(row["path"]).name == "run.log"]
require(len(log_paths) == 1 and b"All tests passed" in bytes_for(log_paths[0]), "Actual Flutter driver success log unavailable")
node_logs = [row["path"] for row in before if PurePosixPath(row["path"]).name == "fixture-tests.log"]
require(len(node_logs) == 1, "Fresh prepared Store Node tests log is missing")
node_log = bytes_for(node_logs[0]).decode("utf-8-sig", "replace") if len(node_logs) == 1 else ""
require("# tests 10" in node_log and "# pass 10" in node_log and "# fail 0" in node_log, "Prepared Store and fixture Node ten-case gate did not pass")
source_paths = [row["path"] for row in before if PurePosixPath(row["path"]).name == "source-commit.txt"]
require(len(source_paths) == 1 and bytes_for(source_paths[0]).decode("utf-8-sig").strip() == NATIVE_HEAD, "Native source-commit record mismatch")



PUBLIC = "2aa04e69f4b6802bd376aed41f529590a6c4f9b3"
EXPECTED = json.loads(r'''[{"path":"tool/perf_probe/installed_plugin_windows_lifetime.cs"},{"path":"tool/perf_probe/test_installed_plugin_windows_lifetime.cs"},{"path":"pubspec.yaml"},{"path":"pubspec.lock"},{"path":"integration_test/support/installed_plugin_windows_lifetime.dart"},{"path":".github/workflows/installed_plugin_probe.yml"},{"path":"tool/perf_probe/installed_plugin_windows_control.psm1"},{"path":"tool/perf_probe/installed_plugin_windows_exit.psm1"},{"path":"tool/perf_probe/test_installed_plugin_windows_runner.ps1"},{"path":"tool/perf_probe/installed_plugin_windows_runner.psm1"},{"path":"tool/perf_probe/run_installed_plugin_windows.ps1"},{"path":"integration_test/installed_plugin_resource_probe_test.dart"},{"path":"tool/perf_probe/WEBVIEW_RESOURCE_PROBE.md"},{"path":"test/tool/perf_probe/installed_plugin_windows_lifetime_test.dart"},{"path":"tool/perf_probe/test_installed_plugin_windows_control.ps1"},{"path":"tool/perf_probe/test_installed_plugin_windows_exit.ps1"}]''')
PREVIOUS_MERGES = json.loads(r'''{"da73d7b3547d7341ac0b9814aca0bc33c7e3e6dc":{"head":"da73d7b3547d7341ac0b9814aca0bc33c7e3e6dc","classification":"MERGES_CLEANLY","publicResult":{"head":"2aa04e69f4b6802bd376aed41f529590a6c4f9b3","exitCode":0,"resultTree":"6a0272ad82ee6dec8538b517d088d494fb3af5b9","rawSha256":"2dbe21afb1b6723c8736ba9a8df4407703b94f2b97e4cd6985a5fb6c2d52a95a"},"candidateResult":{"head":"05e150d09758e0da45ca1877a4d650358f1aa17f","exitCode":0,"resultTree":"e43bd8f0db6d1b2a107f767c18e3261a27e15837","rawSha256":"fdac3cdb79b02efa5497338c8579d65bc4c34517f2d06c351cbcd200893f3e03"},"actualConflictContentUnchanged":true},"b07bb4b8bf3ed7c4d0ac8f34b68d5238bccc94af":{"head":"b07bb4b8bf3ed7c4d0ac8f34b68d5238bccc94af","classification":"PREEXISTING_CONFLICTS","publicResult":{"head":"2aa04e69f4b6802bd376aed41f529590a6c4f9b3","exitCode":1,"resultTree":"fbb1e680e572150aeaceb31b0605cf48a8340b15","rawSha256":"f9e1c0e0eac578dc3ac92df7b1850319e2ae1cd42a144f746fb8ff4234cf41f8"},"candidateResult":{"head":"05e150d09758e0da45ca1877a4d650358f1aa17f","exitCode":1,"resultTree":"985ad92d0f4fd5021a3b9e4419f052e76081dc7a","rawSha256":"42865ea35191d3ac08378114be5e26607a00825189c4b3a6f347bbaa86bef72c"},"actualConflictContentUnchanged":true},"8e02f5a89a509a983f46d8d35b624a22dc844a64":{"head":"8e02f5a89a509a983f46d8d35b624a22dc844a64","classification":"MERGES_CLEANLY","publicResult":{"head":"2aa04e69f4b6802bd376aed41f529590a6c4f9b3","exitCode":0,"resultTree":"d2222f5b9fde4d3b79478450effc1059afa86b7c","rawSha256":"e948d789a14ec43c05f03d80860cbc1b4037f99029ff58c144f57da97e5df033"},"candidateResult":{"head":"05e150d09758e0da45ca1877a4d650358f1aa17f","exitCode":0,"resultTree":"682adcd8e320b7106f7057b487e23a728385613f","rawSha256":"306d5fb376c17db013ca407506a9f1e9cf0cfaa4807516d900a764ebf1901bde"},"actualConflictContentUnchanged":true},"d785e69044358d4f4be3ea4a95597bf4863435e5":{"head":"d785e69044358d4f4be3ea4a95597bf4863435e5","classification":"PREEXISTING_CONFLICTS","publicResult":{"head":"2aa04e69f4b6802bd376aed41f529590a6c4f9b3","exitCode":1,"resultTree":"de43e04502aa990d4025a865794cf9efbbebda4f","rawSha256":"286169dd93302781c94b0679b307b54c7758dc811ab85e2996d3db1cc791c716"},"candidateResult":{"head":"05e150d09758e0da45ca1877a4d650358f1aa17f","exitCode":1,"resultTree":"5474206363d1548ffed289120042d9534a36be28","rawSha256":"dd1616681a92c1dbda125403250303d7279822a1bd94a83474c291ecb083bd77"},"actualConflictContentUnchanged":true},"0006cf887aff520675dc49e6d4737f1b04eb3af6":{"head":"0006cf887aff520675dc49e6d4737f1b04eb3af6","classification":"MERGES_CLEANLY","publicResult":{"head":"2aa04e69f4b6802bd376aed41f529590a6c4f9b3","exitCode":0,"resultTree":"5321dd5d6e0ed879e373f2376c9f15239fd64902","rawSha256":"fd913db42f5025b1be3a20a8f31ba5ed69666a8f65ffeecb6105e5afbfab4f80"},"candidateResult":{"head":"05e150d09758e0da45ca1877a4d650358f1aa17f","exitCode":0,"resultTree":"357c6bf237cceca44883baead33f7c7763dbd417","rawSha256":"896cfd2ada666e9147e7ded9492a8af19873ae69eec9dcfaba6b58f034e0a711"},"actualConflictContentUnchanged":true},"fa696fcc3f2212482514dfcc9e1e8bf1e5212507":{"head":"fa696fcc3f2212482514dfcc9e1e8bf1e5212507","classification":"MERGES_CLEANLY","publicResult":{"head":"2aa04e69f4b6802bd376aed41f529590a6c4f9b3","exitCode":0,"resultTree":"c753e2b5010c883df4521153be96b52279c0e51d","rawSha256":"f9a2990f96412e0571584064fe9d4df82183a407232ef48745a67683b5b9eaf8"},"candidateResult":{"head":"05e150d09758e0da45ca1877a4d650358f1aa17f","exitCode":0,"resultTree":"e6d63f2c834542819af743f722b8e991013e1fe8","rawSha256":"0e22b98a07b211dcf072788843adada0bce71cb425b2521b10561b5db15fd76f"},"actualConflictContentUnchanged":true},"26ecef7740ef766dd1264351eb0f42569b7d87cc":{"head":"26ecef7740ef766dd1264351eb0f42569b7d87cc","classification":"MERGES_CLEANLY","publicResult":{"head":"2aa04e69f4b6802bd376aed41f529590a6c4f9b3","exitCode":0,"resultTree":"670100e5dbcf1cdc109f3690a043300afd293e87","rawSha256":"ef5e1abb79069e423c6c2d435f24694a5bec1d50db10e056abaf720c1fbb6d40"},"candidateResult":{"head":"05e150d09758e0da45ca1877a4d650358f1aa17f","exitCode":0,"resultTree":"963e3bc5f94ac79839060853b9e0d7d115ed8fc0","rawSha256":"ba66995c0ebe9a158a015e29c91f5e84f66edd592a339b0e5d8d9c593aab5396"},"actualConflictContentUnchanged":true},"87c48f089197ee6450a51b8c04a563a40c81fe53":{"head":"87c48f089197ee6450a51b8c04a563a40c81fe53","classification":"MERGES_CLEANLY","publicResult":{"head":"2aa04e69f4b6802bd376aed41f529590a6c4f9b3","exitCode":0,"resultTree":"73e82cd14eb23c4fad55f65aeabbdbf8ac14942f","rawSha256":"eaf91aadd25d12eed8f87f4376917d50ff62810f2d2aa7b5f6ffa2b165ea620f"},"candidateResult":{"head":"05e150d09758e0da45ca1877a4d650358f1aa17f","exitCode":0,"resultTree":"0c91ff52c95eb08a229b53a15970bc4cff4d33f8","rawSha256":"764a90021d0dc345a2704b76ba7dbee0d9fbf4b8988f7ba980580e50f7bf04a0"},"actualConflictContentUnchanged":true},"3b9c05140f722d31fe1fb7312e9722db646335a5":{"head":"3b9c05140f722d31fe1fb7312e9722db646335a5","classification":"MERGES_CLEANLY","publicResult":{"head":"2aa04e69f4b6802bd376aed41f529590a6c4f9b3","exitCode":0,"resultTree":"f39c7a367809c301029f5adfe584171d70674400","rawSha256":"7069cba992e0bc3988ff04e46611013011f2c1518833c8c426b545d3092687b8"},"candidateResult":{"head":"05e150d09758e0da45ca1877a4d650358f1aa17f","exitCode":0,"resultTree":"9f3f7344bb2c548b6a9d7af5cb9a1ee8293008bb","rawSha256":"e12503512a5e1b5a18d87c1dd32faa7f7f7c0296e452e0a3cdbb7e4f3b6726a4"},"actualConflictContentUnchanged":true},"8417d2accbb02a65dcd8f331318c35c1c5b92946":{"head":"8417d2accbb02a65dcd8f331318c35c1c5b92946","classification":"MERGES_CLEANLY","publicResult":{"head":"2aa04e69f4b6802bd376aed41f529590a6c4f9b3","exitCode":0,"resultTree":"b774834058cb9b945f37947cf0ebb6db8ebd2919","rawSha256":"4eb36fe4014fce2618eabcfb397191270752e6634890e2be742bab2d94e6551f"},"candidateResult":{"head":"05e150d09758e0da45ca1877a4d650358f1aa17f","exitCode":0,"resultTree":"12447457e3b33dfcaf830648711a788a23c53fad","rawSha256":"4c86f7b9877f341a72406730b8c5fd0b2e6841a2a15d75823a47f62f429a081c"},"actualConflictContentUnchanged":true},"9fdc05b9dc98c732affeb91bd78062ea369387dc":{"head":"9fdc05b9dc98c732affeb91bd78062ea369387dc","classification":"MERGES_CLEANLY","publicResult":{"head":"2aa04e69f4b6802bd376aed41f529590a6c4f9b3","exitCode":0,"resultTree":"6a66102658a1de4f3e5ddc00c0a04b2356d80c0d","rawSha256":"ab1fdc32c85cff8723c472053a4ed48df2cc704a5820f5d7303226c0d1d3a82b"},"candidateResult":{"head":"05e150d09758e0da45ca1877a4d650358f1aa17f","exitCode":0,"resultTree":"bc47e2f2387aa905e5ae339bf6d5a193b726b5e3","rawSha256":"97fb3c146122b5f1cacafc1789d8b48fd8e9b1eea6e18afd6173aa69a745ca6a"},"actualConflictContentUnchanged":true},"ca0adb7a91f3dc028a41ecbf894237d6bebbc523":{"head":"ca0adb7a91f3dc028a41ecbf894237d6bebbc523","classification":"MERGES_CLEANLY","publicResult":{"head":"2aa04e69f4b6802bd376aed41f529590a6c4f9b3","exitCode":0,"resultTree":"b18ce2496502c73ead82cc2ce6b7ad0d68771831","rawSha256":"baf3c701f0a26e3a9d176b61b41d1ad887942db53118309ce74a21fd1ea59788"},"candidateResult":{"head":"05e150d09758e0da45ca1877a4d650358f1aa17f","exitCode":0,"resultTree":"77703340d178183d3c8d58ca181ff1eaff5e9659","rawSha256":"aa5926612c22450b617254830626310572b6003f17d3fd071ede44f56d095a4c"},"actualConflictContentUnchanged":true},"2497e0dde51862129fd34569290118b475a05f32":{"head":"2497e0dde51862129fd34569290118b475a05f32","classification":"MERGES_CLEANLY","publicResult":{"head":"2aa04e69f4b6802bd376aed41f529590a6c4f9b3","exitCode":0,"resultTree":"3af5f68be7056df2c1a06b5e6eea4a2b87726a7a","rawSha256":"6f0cf6b334b5f6ece1f071658c9168fec905a8b9a008e2497d5920932f8a27a5"},"candidateResult":{"head":"05e150d09758e0da45ca1877a4d650358f1aa17f","exitCode":0,"resultTree":"5f5920d05b04b9d27b8b9c035cd9030a0743f493","rawSha256":"971bfaab4550f6d558df5362edc588d9581d7cedcb0849ea48dc8223307a364d"},"actualConflictContentUnchanged":true},"b22d17645c5c4650ddf9cdb05d5b2b53af8932c9":{"head":"b22d17645c5c4650ddf9cdb05d5b2b53af8932c9","classification":"MERGES_CLEANLY","publicResult":{"head":"2aa04e69f4b6802bd376aed41f529590a6c4f9b3","exitCode":0,"resultTree":"e416df6790843b3adae70e7997cbb67db13a51cc","rawSha256":"48d3b0d1795c4edee5f27f50e8a26ab43e0d9186941532af8e93ed9b4700adcc"},"candidateResult":{"head":"05e150d09758e0da45ca1877a4d650358f1aa17f","exitCode":0,"resultTree":"7159abf4f9e7a89db004dbeceaeb4cae14783c0f","rawSha256":"639ad1bb52cd6907b223d2a62dc21dc7a4c36000e41aa512502728456f4bbe01"},"actualConflictContentUnchanged":true}}''')
PREVIOUS_MERGE_ARTIFACT = {"id": 13558796969, "bytes": 2770565, "sha256": "5e0c1a983860c3ac52ad5fdb3659d2db2c1df2788cc172f92084307d3aadf2d2",
                           "run": 42334744715, "head": "4624bb2f748740fcc3c1b8bf79a620f3a27bf4ab"}

class NoApiRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError("GitHub JSON API unexpectedly redirected")

def api(path):
    if not path.startswith("/repos/Otzaria/otzaria/"):
        raise RuntimeError("QA API path outside the repository")
    headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
               "User-Agent": "Otzaria-independent-4424-QA"}
    if TOKEN:
        headers["Authorization"] = "Bearer " + TOKEN
    request = urllib.request.Request("https://api.github.com" + path, headers=headers)
    with urllib.request.build_opener(NoApiRedirect).open(request, timeout=60) as response:
        return json.load(response)

def pages(path):
    result = []
    for page in range(1, 31):
        separator = "&" if "?" in path else "?"
        rows = api(path + separator + "per_page=100&page=" + str(page))
        if not isinstance(rows, list):
            raise RuntimeError("GitHub list response was not a list")
        result.extend(rows)
        if len(rows) < 100:
            return result
    raise RuntimeError("GitHub list exceeded complete pagination bound")

def public_snapshot(with_files):
    prs = pages("/repos/Otzaria/otzaria/pulls?state=open")
    mapping = []
    for pr in prs:
        row = {"number": pr["number"], "head": pr["head"]["sha"],
               "base": pr["base"]["sha"], "baseRef": pr["base"]["ref"]}
        if with_files:
            files = pages("/repos/Otzaria/otzaria/pulls/" + str(pr["number"]) + "/files")
            row["files"] = [{"path": f["filename"], "previousPath": f.get("previous_filename"),
                             "status": f["status"], "sha": f["sha"]} for f in files]
        mapping.append(row)
    dev = api("/repos/Otzaria/otzaria/git/ref/heads/dev")["object"]["sha"]
    own = [item for item in mapping if item["number"] == 4424]
    if len(own) != 1 or own[0]["head"] != PUBLIC:
        raise RuntimeError("Public PR head changed or PR is not open")
    return {"dev": dev, "prs": sorted(mapping, key=lambda row: row["number"])}

def snapshot_key(value):
    return {"dev": value["dev"], "prs": [{k: item[k] for k in ("number", "head", "base", "baseRef")}
                                         for item in value["prs"]]}

def fresh_merge_targets():
    before = public_snapshot(True)
    save("open-pr-map-before.json", before)
    after = public_snapshot(False)
    save("open-pr-map-after-read.json", after)
    if snapshot_key(before) != snapshot_key(after):
        raise RuntimeError("Open PR map changed during paginated file enumeration")
    own = next(item for item in before["prs"] if item["number"] == 4424)
    common_paths = {f["path"] for f in own["files"]}
    delta_paths = {f["path"] for f in EXPECTED}
    result = [{"number": "dev", "head": before["dev"], "commonOverlap": [], "deltaOverlap": []}]
    for pr in before["prs"]:
        if pr["number"] == 4424:
            continue
        names = {f["path"] for f in pr["files"]} | {f["previousPath"] for f in pr["files"] if f["previousPath"]}
        common_overlap = sorted(names & common_paths)
        delta_overlap = sorted(names & delta_paths)
        if common_overlap or delta_overlap:
            result.append({"number": pr["number"], "head": pr["head"],
                           "commonOverlap": common_overlap, "deltaOverlap": delta_overlap})
    result.extend([
        {"number": "public-base", "head": own["base"], "commonOverlap": [], "deltaOverlap": []},
        {"number": "font-public-ca0", "head": "ca0adb7a91f3dc028a41ecbf894237d6bebbc523", "commonOverlap": [], "deltaOverlap": [], "binding": "published font candidate"},
        {"number": "apple-proposed-de019", "head": "de019fc88b93a6ec58dd80d6ab40cd26fd5c06e1", "commonOverlap": [], "deltaOverlap": [], "binding": "unpublished source candidate under NEW independent QA"},
        {"number": "android-proposed-b9f7", "head": "b9f7c186cb240ec45ba77e3160acc78402f4e172", "commonOverlap": [], "deltaOverlap": [], "binding": "unpublished proposal under separate QA"}
    ])
    save("merge-map-binding.json", {"readAtUtc": datetime.now(timezone.utc).isoformat(),
                                  "openPrCount": len(before["prs"]), "allPagesRead": True,
                                  "commonPaths": sorted(common_paths), "candidateDeltaPaths": sorted(delta_paths)})
    return before, result


def normalize_conflict_blob(raw):
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw, "binary", None
    # Normalize only Git conflict marker labels, not any side's source content.
    normalized = re.sub(r"^(<{7}|>{7}|\|{7})(?: [^\r\n]*)?$", r"\1",
                        text, flags=re.MULTILINE).encode("utf-8")
    hunks = len(re.findall(r"^<{7}(?: |$)", text, flags=re.MULTILINE))
    return normalized, "utf-8", hunks

def conflict_evidence(raw, result_tree, target, label):
    text = raw.decode("utf-8", "strict")
    entries = []
    for line in text.splitlines()[1:]:
        match = re.match(r"^([0-7]{6}) ([0-9a-f]{40}) ([123])\t(.+)$", line)
        if match:
            mode, blob, stage, path = match.groups()
            if path.startswith('"') or Path(path).is_absolute() or ".." in Path(path).parts:
                raise RuntimeError("Unexpected conflict path quoting: " + path)
            entries.append({"path": path, "stage": int(stage), "mode": mode, "blob": blob})
    if not entries:
        raise RuntimeError("A conflicted merge must retain parseable stage entries; empty evidence is not accepted")
    files = []
    for path in sorted({item["path"] for item in entries}):
        entry = git("ls-tree", result_tree, "--", path).split()
        if not entry:
            files.append({"path": path, "exists": False})
            continue
        if len(entry) < 4:
            raise RuntimeError("Unexpected conflict tree entry")
        data = subprocess.check_output(["git", "show", result_tree + ":" + path])
        normalized, kind, hunks = normalize_conflict_blob(data)
        destination = OUT / "conflict-files" / str(target) / label / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        normalized_path = destination.with_name(destination.name + ".normalized")
        normalized_path.write_bytes(normalized)
        files.append({"path": path, "exists": True, "mode": entry[0], "blob": entry[2],
                      "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                      "kind": kind, "conflictHunks": hunks, "normalizedBytes": len(normalized),
                      "normalizedSha256": hashlib.sha256(normalized).hexdigest()})
    return {"stageEntries": sorted(entries, key=lambda item: (item["path"], item["stage"])),
            "files": files, "totalHunks": sum(item.get("conflictHunks") or 0 for item in files)}

def same_conflict_content(public, candidate):
    first = public["conflictEvidence"]
    second = candidate["conflictEvidence"]
    if first["stageEntries"] != second["stageEntries"]:
        return False
    fields = ("path", "exists", "mode", "kind", "conflictHunks", "normalizedBytes", "normalizedSha256")
    before = [{key: item.get(key) for key in fields} for item in first["files"]]
    after = [{key: item.get(key) for key in fields} for item in second["files"]]
    return before == after


AUXILIARY = {
    "fast": {"id": 13558717955, "bytes": 1008202, "sha256": "53427fe419257f7a7d330c49238124724615cb4a36a352a11ee38ddb2665fd40",
             "run": 42335189188, "head": "cac2be6ecd0f053feb12e771d8d976dd7b76bfb9"},
    "mac": {"id": 13557004468, "bytes": 67070, "sha256": "3202854c50fdf3e88983a1fb42cb06fd4cc8d99e506a0b03455c2c00d3d422e1",
            "run": 42329492076, "head": "f4893ce470cb6f7dbdb432c2c5b98d89b10dd03f"},
    "source": {"id": 13558953150, "bytes": 31869, "sha256": "1117a294bce0a7c35eb71f41aef3c57ac022b7a3979094d77f036e3148a2800a",
               "run": 42334744715, "head": "4624bb2f748740fcc3c1b8bf79a620f3a27bf4ab"},
}
auxiliary_proofs = {}
def review_auxiliary(label, frozen):
    metadata = json.loads(read_api("/repos/Otzaria/otzaria/actions/artifacts/" + str(frozen["id"]), 65536))
    require(metadata.get("id") == frozen["id"] and metadata.get("size_in_bytes") == frozen["bytes"] and
            metadata.get("digest") == "sha256:" + frozen["sha256"] and metadata.get("expired") is False and
            metadata.get("workflow_run", {}).get("id") == frozen["run"] and
            metadata.get("workflow_run", {}).get("head_sha") == frozen["head"], label + " auxiliary artifact metadata mismatch")
    raw = read_api("/repos/Otzaria/otzaria/actions/artifacts/" + str(frozen["id"]) + "/zip", frozen["bytes"] + 1)
    if len(raw) != frozen["bytes"] or sha256(raw) != frozen["sha256"]:
        raise RuntimeError("Auxiliary artifact ZIP bytes do not match exact binding: " + label)
    (OUT / (label + "-original-artifact.zip")).write_bytes(raw)
    files = {}
    total = 0
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        if len(archive.infolist()) > 256:
            raise RuntimeError("Auxiliary ZIP too many entries")
        for entry in archive.infolist():
            name = entry.filename
            path = PurePosixPath(name)
            if (not name or name.startswith("/") or "\\" in name or ":" in name or ".." in path.parts or
                    name in files or stat.S_ISLNK(entry.external_attr >> 16)):
                raise RuntimeError("Unsafe auxiliary archive path")
            if entry.is_dir():
                continue
            total += entry.file_size
            if entry.file_size > 16 * 1024 * 1024 or total > 64 * 1024 * 1024:
                raise RuntimeError("Auxiliary extraction limit exceeded")
            data = archive.read(entry)
            if len(data) != entry.file_size:
                raise RuntimeError("Auxiliary archive size mismatch")
            files[name] = data
    def get(name):
        found = [data for path, data in files.items() if PurePosixPath(path).name == name]
        if len(found) != 1:
            raise RuntimeError("Expected one auxiliary file " + name)
        return found[0]
    def decoded(name):
        return json.loads(get(name).decode("utf-8-sig"))
    if label == "mac":
        device_bytes = get("installed-plugin-report.json")
        framework_bytes = get("report.json")
        require(sha256(device_bytes) == "55755787d892b354d57a858ac9c4840e4744d6cc3f365f476e8b3a58c42b0899" and
                sha256(framework_bytes) == "a031d6aeec49b6eb430e77d851c4b9bcfeab1cfb79fa23684c4544fc9d691e0b",
                "Original Mac artifact reports differ from independently reviewed exact raw blobs")
        mac_device = json.loads(device_bytes.decode("utf-8-sig"))
        mac_framework = json.loads(framework_bytes.decode("utf-8-sig"))["installedPluginProbe"]
        comparable = dict(mac_device)
        comparable.pop("testFailures", None)
        require(comparable == mac_framework and mac_device.get("testFailures") == [] and
                "testFailures" not in mac_framework, "Original Mac final callback fields or scenario identity differ")
        require(mac_device.get("commit") == frozen["head"] and mac_device.get("status") == "passed" and
                mac_device.get("platform") == "macos" and mac_device.get("buildMode") == "profile",
                "Original Mac report source/platform/status mismatch")
        require(b"All tests passed" in get("run.log") and get("source-commit.txt").decode("utf-8-sig").strip() == frozen["head"],
                "Original Mac native driver/source record unavailable")
        provenance = decoded("source-provenance.json")
        require(provenance.get("commit") == "4517d39c4ecab632aff98e1c0e414881695961aa" and
                provenance.get("sha256") == mac_device.get("pinnedStore", {}).get("sha256"), "Original Mac verified Store provenance mismatch")
        auxiliary_proofs[label] = {"artifact": frozen, "fileCount": len(files), "extractedBytes": total,
                                  "deviceSha256": sha256(device_bytes), "frameworkSha256": sha256(framework_bytes),
                                  "previouslyIndependentlyReviewedRawBlobsMatch": sha256(device_bytes) == "55755787d892b354d57a858ac9c4840e4744d6cc3f365f476e8b3a58c42b0899" and sha256(framework_bytes) == "a031d6aeec49b6eb430e77d851c4b9bcfeab1cfb79fa23684c4544fc9d691e0b",
                                  "executedSource": "f4ac011f1b8c81d4a760eeeadfe037228fb944e3",
                                  "executedQaHead": frozen["head"],
                                  "newMacExecutionClaimed": False,
                                  "finalDeviceStatus": mac_device.get("status"),
                                  "deviceFinalTestFailures": mac_device.get("testFailures"),
                                  "frameworkTestFailuresFieldPresent": "testFailures" in mac_framework}
        save(label + "-auxiliary-review.json", auxiliary_proofs[label])
        return
    summary = decoded("summary.json")
    require(summary.get("sourceCommit") == SOURCE and summary.get("sourceTree") == SOURCE_TREE and summary.get("qaHead") == frozen["head"], label + " source binding mismatch")
    report = {"artifact": frozen, "fileCount": len(files), "extractedBytes": total,
              "files": [{"path": path, "bytes": len(data), "sha256": sha256(data)} for path, data in sorted(files.items())],
              "summary": summary}
    if label == "fast":
        before_state, after_state = decoded("before.json"), decoded("after.json")
        fast_unchanged = before_state.get("index") == after_state.get("index") and before_state.get("allTracked") == after_state.get("allTracked")
        require(fast_unchanged, "Fast Windows source/index changed")
        require(len(before_state.get("allTracked", [])) == 4200 and len(after_state.get("allTracked", [])) == 4200, "Fast full tracked maps are incomplete")
        require(before_state.get("status") == [] and after_state.get("status") == [], "Fast Windows source worktree not clean")
        require(summary.get("sourceUnchanged") is True and len(summary.get("cases", [])) == 13 and all(c.get("passed") is True for c in summary.get("cases", [])), "Fast thirteen-case gate did not pass")
        old = decoded("old-resolution.json")
        require(len(old.get("candidates", [])) >= 2 and old.get("result", {}).get("exitCode") is None and
                bool(old.get("result", {}).get("error")) and old.get("markerExists") is False, "Actual old module collision was not reproduced")
        require(old.get("frozenOldSha256") == "24140aa825be6d5c8b571a1798048a503a9909836222ee889843539f7ac335d7", "Old negative-control source binding wrong")
        old_bytes = get("qa_old_windows_exit.psm1")
        require(sha256(old_bytes) == old["frozenOldSha256"], "Copied old module bytes differ")
        report["oldResolution"] = old
        fixed = []
        for name in ("PATH-selects-cmd", "reversed-PATH-selects-bat", "explicit-cmd-bypasses-reversed-PATH", "explicit-bat-bypasses-original-PATH"):
            row = decoded(name + ".json")
            require(row.get("result", {}).get("exitCode") == row.get("control", {}).get("code") and
                    row.get("result", {}).get("error") is None and row.get("result", {}).get("logTruncated") is False and
                    row.get("childMarker") == row.get("control", {}).get("marker"), "Real fixed native command control failed: " + name)
            require(sha256(get(name + ".log")) == row.get("logSha256"), "Fixed native stdout/stderr bytes mismatch")
            fixed.append(row)
        report["fixedResolution"] = fixed
        compound = decoded("compound-io.json")
        require(compound.get("result", {}).get("exitCode") == 37 and bool(compound.get("result", {}).get("error")) and
                compound.get("consoleAttempts", 0) >= 3 and compound.get("childMarker") == "completed before exit 37", "Compound native I/O regression lost first error, real exit or drain")
        report["compoundIo"] = compound
        traces = {}
        for mode in ("exact-native-lifetime", "wrong-native-tick", "wrong-authentication"):
            trace = decoded(mode + "-trace.json")
            child = decoded(mode + "-child.json")
            require(trace.get("nativeAdapter") == "InstalledPluginProbe.WindowsProcessFactory", "Fast independent control did not use real native handle")
            if mode == "exact-native-lifetime":
                require(trace.get("availability") == "collected" and trace.get("exitStatus") == 37 and
                        trace.get("identity", {}).get("pid") == child.get("pid") and
                        trace.get("identity", {}).get("creationFileTime") == child.get("actualCreationFileTime") and child.get("acknowledged") is True,
                        "Exact independent PID/FILETIME child37 control failed")
            else:
                require(trace.get("availability") == "unavailable" and trace.get("exitStatus") is None and
                        bool(trace.get("errors")) and child.get("acknowledged") is False, "Invalid bootstrap received acceptance")
                if mode == "wrong-native-tick":
                    require(trace.get("identity", {}).get("creationFileTime") == child.get("actualCreationFileTime") and
                            trace.get("cleanup", {}).get("handleAcquired") is True and trace.get("cleanup", {}).get("handleClosed") is True,
                            "Wrong FILETIME did not read/release actual handle")
                else:
                    require(trace.get("cleanup", {}).get("handleAcquired") is False, "False authentication opened native handle")
            traces[mode] = {"trace": trace, "child": child}
        report["independentNativeTraces"] = traces
        report["fullTrackedSourceAndIndexUnchanged"] = fast_unchanged
    elif label == "source":
        failed = [c for c in summary.get("cases", []) if c.get("passed") is not True]
        require(summary.get("passed") is False and len(failed) == 1 and failed[0].get("name") == "Independent fixture and Store negative controls" and
                "Set INSTALLED_PROBE_STORE_SOURCE" in failed[0].get("error", ""), "Source job historical setup failure changed or contains other failures")
        source_unchanged = decoded("app-before.json") == decoded("app-after.json")
        deps_unchanged = decoded("dependency-before.json") == decoded("dependency-after.json")
        sdk_unchanged = decoded("sdk-before-resolution.json") == decoded("sdk-after-resolution.json")
        require(source_unchanged, "Source gate changed application/index bytes")
        require(deps_unchanged, "Source gate changed SDK or Git dependency bytes")
        require(sdk_unchanged, "Strict resolution changed SDK bytes")
        require({name: item.get("head") for name, item in decoded("resolved-git-packages.json").items()} == {"flutter_inappwebview":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_android":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_ios":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_linux":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_macos":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_platform_interface":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_web":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_windows":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_local_notifications_windows":"ad21cf2cddfa7c79ea7903ad95b38a8d716b5f85","flutter_widget_from_html_core":"57080495ee8b89aeee156a4440b6de1c5e0f7ef2","opentype_shaper":"461902c049b412d64dc4dfa7b547fedbf751211d","otzaria_ashurit":"b43b67bb706be6bc87af14658d67e16cd347fc29","otzaria_icons":"483fec355339f54f9e094994a106dad9a63b82e3","otzaria_search_engine":"2da23091237ed0f0a612de3b2d18cfc99d8b7d2a","pdfrx":"942e27bec86e8d480111517c2083eb52817ee032","printing":"3cb90fb3025553f3e9f48638c79ccf93efb326af","seforim_library_updater":"6bfd33c3bc14392c1a6bb0887fdb23209068eab5","sentry_flutter":"93e7398355e80557a342666f98b23cc9bb832848","window_manager":"88a433a7be43ed0213da12b561bf0d8d070c6d68"}, "Source gate all19 Git package binding mismatch")
        require(get("source-mutations.log") == b"" and get("index-mutations.log") == b"", "Hook source/index mutations were retained")
        hook = decoded("original-staged-hook.json")
        installer = decoded("install-original-hook.json")
        staged = decoded("staged-hook-binding.json")
        expected_dart = {"integration_test/installed_plugin_resource_probe_test.dart",
                         "integration_test/support/installed_plugin_windows_lifetime.dart",
                         "test/tool/perf_probe/installed_plugin_windows_lifetime_test.dart"}
        require(sha256(get("installed-pre-commit-hook.txt")) == "53b75db342d0332ae703c389562adf65a04d6127bd1ff05edaef0dde7b020097", "Actual generated original hook bytes mismatch")
        require(set(staged.get("stagedDartPaths", [])) == expected_dart and staged.get("headDuringHook") == "2aa04e69f4b6802bd376aed41f529590a6c4f9b3", "Real original hook staged input mismatch")
        require(hook.get("exitCode") == 0 and hook.get("timedOut") is False and hook.get("timeoutSeconds") == 1200 and
                installer.get("exitCode") == 0 and installer.get("timedOut") is False and installer.get("timeoutSeconds") == 900, "Actual installer/hook execution did not pass")
        for name in ("strict-pub-get","format","full-analyze","flutter-controls"):
            command = decoded(name + ".json")
            require(command.get("exitCode") == 0 and command.get("timedOut") is False, "Successful source gate not verified: " + name)
            require(sha256(get(name + ".log")) == command.get("outputSha256"), "Source gate raw output hash mismatch: " + name)
        report["originalHook"] = {"installer": installer, "execution": hook, "staged": staged,
                                  "completeStdout": get("original-staged-hook.log").decode("utf-8"),
                                  "hookBytesSha256": sha256(get("installed-pre-commit-hook.txt"))}
        report["flutterTestOutput"] = get("flutter-controls.log").decode("utf-8")
        report["sourceGitSdkAndIndexUnchanged"] = source_unchanged and deps_unchanged and sdk_unchanged
        report["overallOriginalJobFailurePreserved"] = True
    auxiliary_proofs[label] = report
    save(label + "-auxiliary-review.json", report)

for label, frozen in AUXILIARY.items():
    try:
        review_auxiliary(label, frozen)
    except Exception as error:
        problems.append("Auxiliary evidence unavailable or invalid for " + label + ": " + str(error))
        auxiliary_proofs[label] = {"error": str(error), "artifact": frozen}


def merge_command(arguments, label, allowed=(0,)):
    path = OUT / (label + ".log")
    with path.open("wb") as output:
        try:
            result = subprocess.run(arguments, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=240)
        except subprocess.TimeoutExpired:
            save(label + "-timeout.json", {"command": arguments, "timeoutSeconds": 240, "outputRetained": True})
            raise
    raw = path.read_bytes()
    save(label + ".json", {"command": arguments, "exitCode": result.returncode, "outputBytes": len(raw), "outputSha256": sha256(raw)})
    if result.returncode not in allowed:
        raise RuntimeError("Additive merge command failed: " + label + ": " + raw[-3000:].decode("utf-8", "replace"))
    return result.returncode, raw

def additive_merges():
    initial, targets = fresh_merge_targets()
    proof_rows = []
    reused = []
    known = {}
    old = PREVIOUS_MERGE_ARTIFACT
    metadata = json.loads(read_api("/repos/Otzaria/otzaria/actions/artifacts/" + str(old["id"]), 65536))
    old_artifact_verified = (metadata.get("digest") == "sha256:" + old["sha256"] and metadata.get("size_in_bytes") == old["bytes"] and
                             metadata.get("workflow_run", {}).get("id") == old["run"] and metadata.get("workflow_run", {}).get("head_sha") == old["head"])
    require(old_artifact_verified, "Previously completed merge artifact binding changed")
    for target in targets:
        head = target["head"]
        if head in PREVIOUS_MERGES:
            reused.append({**target, "existingProof": PREVIOUS_MERGES[head],
                           "reusedOnlyForIdenticalSourceAndTargetHeads": True})
            continue
        if head not in known:
            merge_command(["git", "fetch", "--no-tags", "origin", head], "additive-fetch-" + str(target["number"]))
            proof = {}
            for label, left in (("public", PUBLIC), ("candidate", SOURCE)):
                code, raw = merge_command(["git", "merge-tree", "--write-tree", left, head],
                                           "additive-merge-" + str(target["number"]) + "-" + label, allowed=(0, 1))
                value = raw.decode("utf-8", "strict")
                result_tree = value.splitlines()[0]
                if not re.fullmatch(r"[0-9a-f]{40}", result_tree):
                    raise RuntimeError("Actual merge-tree did not return a valid result tree")
                raw_messages = sorted(set(re.findall(r"^CONFLICT.*$", value, flags=re.MULTILINE)))
                normalized = sorted({line.replace(left, "<left>").replace(head, "<right>") for line in raw_messages})
                proof[label] = {"head": left, "exitCode": code, "resultTree": result_tree,
                                "rawSha256": sha256(raw), "conflicts": normalized, "rawConflictMessages": raw_messages,
                                "conflictEvidence": conflict_evidence(raw, result_tree, target["number"], label)
                                  if code == 1 else {"stageEntries": [], "files": [], "totalHunks": 0}}
            known[head] = proof
        proof = known[head]
        content_same = same_conflict_content(proof["public"], proof["candidate"])
        same_messages = proof["public"]["conflicts"] == proof["candidate"]["conflicts"]
        classification = ("MERGES_CLEANLY" if proof["candidate"]["exitCode"] == 0 else
                          "PREEXISTING_CONFLICTS" if proof["public"]["exitCode"] == 1 and content_same and same_messages else
                          "NEW_OR_CHANGED_CONFLICTS")
        proof_rows.append({**target, **proof, "classification": classification, "actualConflictContentUnchanged": content_same})
        require(classification != "NEW_OR_CHANGED_CONFLICTS", "Current source adds or changes conflict content against " + str(target["number"]))
        save("additive-merge-results-partial.json", proof_rows)
    final = public_snapshot(False)
    save("open-pr-map-after-additive-merges.json", final)
    map_stable = snapshot_key(initial) == snapshot_key(final)
    require(map_stable, "Current public PR heads/bases changed during additive merge review")
    for head in ("de019fc88b93a6ec58dd80d6ab40cd26fd5c06e1","b9f7c186cb240ec45ba77e3160acc78402f4e172"):
        require(head in known, "A newly frozen external candidate lacks an actual fresh merge-tree proof: " + head)
    report = {"source": SOURCE, "sourceTree": SOURCE_TREE, "stableOpenPrCount": len(final["prs"]),
              "currentPublicSnapshot": snapshot_key(final), "newActualComparisons": 2 * len(known),
              "freshProofs": proof_rows, "reusedExactHeadProofs": reused, "previousArtifact": old,
              "preexistingConflictsNotClaimedMergeable": True,
              "allCurrentOverlapsCovered": map_stable and old_artifact_verified}
    save("additive-merge-summary.json", report)
    return report

additional_merge_proof = {}
try:
    additional_merge_proof = additive_merges()
except Exception as error:
    problems.append("Fresh PR map/additive merge proof unavailable or invalid: " + str(error))
    additional_merge_proof = {"error": str(error)}

after = file_snapshot(extracted)
save("extracted-manifest-after.json", after)
require(before == after, "Read-only diagnostic mutated original artifact bytes")
require(git("status", "--porcelain=v1") == "", "Read-only diagnostic mutated source checkout")
exports = []
for path in (device_path, framework_path, receipt_path, start_path, control_path, provenance_path):
    if path:
        data = bytes_for(path)
        exports.append({"path": path, "bytes": len(data), "sha256": sha256(data), "completeText": data.decode("utf-8")})
summary = {**binding, "diagnosticStatus": "COMPLETED", "nativeAcceptance": "PASSED" if not problems else "BLOCKED",
           "problems": problems, "decodeErrors": decode_errors, "artifactBytesUnchanged": before == after,
           "applicationSourceUnchanged": git("status", "--porcelain=v1") == "", "artifactCodeExecuted": False,
           "artifactZip": {"bytes": len(raw_zip), "sha256": sha256(raw_zip)}, "allFiles": before,
           "nativeReceipt": receipt, "snapshotReceipts": snapshot_receipts, "resolvedGitPackages": packages,
           "actualFlutterCommandCandidates": resolution,
           "deviceIdentity": {k: device.get(k) for k in ("commit","pid","runId","platform","buildMode","machineId")},
           "frameworkTestFailuresFieldPresent": "testFailures" in framework,
           "deviceFinalTestFailures": device.get("testFailures"),
           "rawTextExports": exports, "auxiliaryProofs": auxiliary_proofs, "additionalMergeProof": additional_merge_proof,
           "preparedStoreNodeGateClosed": "# tests 10" in node_log and "# pass 10" in node_log and "# fail 0" in node_log}
save("diagnostic-summary.json", summary)
print("BEGIN_QA4424_NATIVE_DIAGNOSTIC", flush=True)
print(json.dumps(summary, ensure_ascii=False), flush=True)
print("END_QA4424_NATIVE_DIAGNOSTIC", flush=True)
sys.exit(0 if not problems else 1)
