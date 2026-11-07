#!/usr/bin/env python3
"""Read the exact Windows debug-a artifact as data; no native rerun or artifact code execution."""
import hashlib
import base64
import struct
import traceback
import io
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile

SOURCE = "05e150d09758e0da45ca1877a4d650358f1aa17f"
PARENT = SOURCE
OBSERVATION_HEAD = "6bd82f1d9b0f2d1de3cc6c2b680dcd9e414d698a"
ARTIFACT = 13561885776
RUN = 42339349730
ZIP_BYTES = 11906695
ZIP_SHA256 = "33807d051bb4b801467adf28b95022b4d4ec14cae5001b3c546ebdcae79db406"
QA_FILES = {".github/qa/4424/read_native_debug_a.py", ".github/workflows/qa_4424_native_debug_a_evidence.yml"}
MANIFEST = [["tool/perf_probe/installed_plugin_windows_lifetime.cs","050e97ca46a728986468e7cbabf4a864156a7a70","e373e8b5dcd6a17d925e52249050d9e99d0c0c1a04fa59523e8b1f86b30e4b15",19764,"100644"],["tool/perf_probe/test_installed_plugin_windows_lifetime.cs","d46736f77c8979b09ad84ca8bcce70653595e3ae","bc93f45dbbd1646dd59a08c43f7e5f1f6c3a75a69345060dea610f766c930c04",15375,"100644"],["pubspec.yaml","26054b0dfe7533a25a33dbec92f875289fb8c7f9","b900e75318dfb65333f97e8529c52dfe08df0893292e535700094da7ae8c6b51",13609,"100644"],["pubspec.lock","8a4569554fffc9ca5686633a58386d2c83487755","94bf01c88e2568424d39a7da767ecdd70356c915f8636e0ccb233121bb6ef932",66487,"100644"],["integration_test/support/installed_plugin_windows_lifetime.dart","564f27327f440d4099054456589891acbca609f4","d896f1580440e1fe726595b8d0afc64046a6480cbb0a949cf9a04c009c8a8173",3701,"100644"],[".github/workflows/installed_plugin_probe.yml","d126a4d7e11646c9d8071c8d72f32746e16cfa96","382f4f78f9b41fde647162d1058bec60d4df4ea4ad85cd48610cded77753b6d3",7040,"100644"],["tool/perf_probe/installed_plugin_windows_control.psm1","718bea8e88b1ec1c2623b5f2f12f779c66e24344","dea8243fa148fc09168e0833ac36b77fac03486e0657d478b545c672d0d23d5f",10454,"100644"],["tool/perf_probe/installed_plugin_windows_exit.psm1","61956f3c0f474f0f87c9648f9a51f593f7b9de03","5d1d26bc0adb24cc91f7ec81031daca4985233f7601a21dc30616c53ea373e96",15874,"100644"],["tool/perf_probe/test_installed_plugin_windows_runner.ps1","d2a576a91716044a5f9e2179075f11feba3cd6bc","9f732afcc8093933db9402de470a1f34d0e55289c398589efecc616e5adc8b93",12152,"100644"],["tool/perf_probe/installed_plugin_windows_runner.psm1","55d3c081c030771a923bb509db6e2bad9ea5a937","205ccece2043181621a9dae1a98db59d6df76b93b788a48e57cb3afc66c6e462",10724,"100644"],["tool/perf_probe/run_installed_plugin_windows.ps1","330129b3f178a4caecc05054ec9d2d4b515ae15b","edd23bafd7dd24ad7ffc4d090197610eed43c392e0050bc0b737fc8e4c7c0569",586,"100644"],["integration_test/installed_plugin_resource_probe_test.dart","e73166c5c7e37515501bb8f6265b38df568780dd","4f03d7f8f7a2cb94ed79590af5995b9f146077cceb7f49d688c41dceaf9d642e",53896,"100644"],["tool/perf_probe/WEBVIEW_RESOURCE_PROBE.md","5a5c69de8c717663a6777fe821521c6a9b7e629f","f97230e81069bf3799f0229999c649c0e7f4a5c4fd23890c39030f8e4ef58fc3",45250,"100644"],["test/tool/perf_probe/installed_plugin_windows_lifetime_test.dart","b439993f5a6aaa083d5c6aedf9e5def7cc9fe835","06e509186494e4a6a80a20f962a22bb92b3fb357fb7254b499db4056333443f3",6586,"100644"],["tool/perf_probe/test_installed_plugin_windows_control.ps1","ac580460a67166e47b3f7c15b71197d10fb02256","157dff260b0c608be395193a8dde2d0821b45f029e82b8315ae8db2b5fe5a1da",12208,"100644"],["tool/perf_probe/test_installed_plugin_windows_exit.ps1","fadec4e10d5e41773df39c0be5f6db93748115af","dd9f4244782b7f7043d9d66dad81b6acdf267e46e857a67ffb25f0bb518b4d0d",23197,"100644"]]
ROOT = Path.cwd().resolve()
OUT = Path(os.environ["QA_NATIVE_DEBUG_EVIDENCE_OUTPUT"]).resolve()
assert OUT != ROOT and ROOT not in OUT.parents
OUT.mkdir(parents=True, exist_ok=False)
token = os.environ.pop("DIAGNOSTIC_TOKEN")
os.environ.pop("GITHUB_TOKEN", None)
os.environ.pop("GH_TOKEN", None)
sys.dont_write_bytecode = True

def sha(data):
    return hashlib.sha256(data).hexdigest()

def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode().strip()

def snapshot():
    files = []
    for raw in subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).split(b"\0"):
        if not raw:
            continue
        name = os.fsdecode(raw)
        path = ROOT / name
        data = os.fsencode(os.readlink(path)) if path.is_symlink() else path.read_bytes()
        files.append({"path": name, "bytes": len(data), "sha256": sha(data),
                      "mode": path.lstat().st_mode, "symlink": path.is_symlink()})
    return {"head": git("rev-parse", "HEAD"), "indexTree": git("write-tree"),
            "status": git("status", "--porcelain=v1", "--untracked-files=all"), "files": files}

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, url):
        return None

def api(path):
    assert path.startswith("/repos/Otzaria/otzaria/actions/")
    request = urllib.request.Request("https://api.github.com" + path, headers={
        "Authorization": "Bearer " + token,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    return urllib.request.build_opener(NoRedirect).open(request, timeout=30)

before = snapshot()
report = {"scope": "Read-only exact Windows debug-a artifact; no native rerun, no artifact code execution and no application acceptance",
          "source": SOURCE, "observationHead": OBSERVATION_HEAD, "artifactId": ARTIFACT, "observationRun": RUN,
          "status": "failed", "nativeAPIExecution": "NOT_RUN", "applicationAcceptance": "NOT_RUN"}
try:
    assert git("rev-parse", "HEAD^") == PARENT
    assert git("rev-parse", SOURCE + "^{tree}") == "e43bd8f0db6d1b2a107f767c18e3261a27e15837"
    assert set(git("diff", "--name-only", PARENT, "HEAD").splitlines()) == QA_FILES
    assert not before["status"]
    for name, blob, digest, size, mode in MANIFEST:
        data = (ROOT / name).read_bytes()
        assert len(data) == size and sha(data) == digest, name
        assert hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest() == blob, name
        assert git("ls-files", "-s", "--", name).split()[0] == mode, name
    with api("/repos/Otzaria/otzaria/actions/artifacts/" + str(ARTIFACT)) as response:
        metadata = json.load(response)
    assert metadata["id"] == ARTIFACT and not metadata["expired"]
    assert metadata["size_in_bytes"] == ZIP_BYTES and metadata["digest"] == "sha256:" + ZIP_SHA256
    assert metadata["workflow_run"]["id"] == RUN and metadata["workflow_run"]["head_sha"] == OBSERVATION_HEAD
    report["artifactMetadata"] = metadata
    try:
        response = api("/repos/Otzaria/otzaria/actions/artifacts/" + str(ARTIFACT) + "/zip")
    except urllib.error.HTTPError as error:
        assert error.code in (301, 302, 303, 307, 308), error.code
        location = error.headers["Location"]
        parsed = urllib.parse.urlparse(location)
        assert parsed.scheme == "https" and parsed.hostname and not parsed.username and not parsed.password
        # No bearer token is forwarded to the signed artifact redirect.
        with urllib.request.urlopen(urllib.request.Request(location), timeout=60) as redirected:
            archive_bytes = redirected.read(ZIP_BYTES + 1)
    else:
        with response:
            archive_bytes = response.read(ZIP_BYTES + 1)
    assert len(archive_bytes) == ZIP_BYTES and sha(archive_bytes) == ZIP_SHA256
    (OUT / "original-artifact.zip").write_bytes(archive_bytes)
    report["verifiedArchive"] = {"bytes": len(archive_bytes), "sha256": sha(archive_bytes)}
    artifact_files = []
    selected_files = []
    dumps = []
    retained = {}
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
        entries = archive.infolist()
        assert len(entries) < 1000
        assert sum(item.file_size for item in entries) < 256 * 1024 * 1024
        assert len({item.filename for item in entries}) == len(entries)
        for item in entries:
            path = PurePosixPath(item.filename)
            assert not path.is_absolute() and ".." not in path.parts and "\\" not in item.filename
            assert not item.flag_bits & 1 and item.file_size <= 128 * 1024 * 1024
            assert (item.external_attr >> 16) & 0o170000 != 0o120000
            if item.is_dir():
                continue
            data = archive.read(item)
            record = {"path": item.filename, "bytes": len(data), "sha256": sha(data)}
            artifact_files.append(record)
            if path.suffix == ".dmp":
                assert len(data) >= 32
                signature, version, streams, directory_rva = struct.unpack_from("<IIII", data)
                dumps.append({**record, "signatureHex": hex(signature), "versionHex": hex(version),
                              "streams": streams, "directoryRva": directory_rva,
                              "scope": "actual" if "/actual/" in item.filename else "control"})
            selected = (
                item.filename in {
                    "installed-plugin-probe/windows-native-exit.json",
                    "installed-plugin-probe/windows-native-exit-start.json",
                    "installed-plugin-probe/windows-device-report.json",
                    "installed-plugin-probe/device/installed-plugin-report.json",
                    "installed-plugin-probe/run.log",
                    "installed-plugin-probe/fixture-errors.txt",
                    "installed-plugin-probe/native-debug/control-result.json",
                    "installed-plugin-probe/native-debug/control/native-debug-summary.json",
                    "installed-plugin-probe/native-debug/finish.json",
                    "installed-plugin-probe/native-debug/raw-manifest.json",
                }
                or item.filename.startswith("installed-plugin-probe/native-debug/actual/")
                or (item.filename.startswith("installed-plugin-probe/qa-snapshots/") and path.name.endswith("-receipt.json"))
            )
            if selected and path.suffix in {".json", ".jsonl", ".txt", ".log", ""}:
                assert len(data) < 16 * 1024 * 1024
                target = OUT / "retained" / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                retained[item.filename] = data
                text = data.decode("utf-8-sig", "strict")
                selected_files.append({**record, "base64": base64.b64encode(data).decode("ascii"), "text": text})
    report["artifactFiles"] = artifact_files
    report["selectedFiles"] = selected_files
    report["minidumpHeaders"] = dumps
    native = json.loads(retained["installed-plugin-probe/windows-native-exit.json"].decode("utf-8-sig"))
    report["actualNativeReceipt"] = native
    report["actualNativeReceiptIdentifiesObservation"] = native["commit"] == OBSERVATION_HEAD
    assert native["commit"] == OBSERVATION_HEAD
    device = json.loads(retained["installed-plugin-probe/windows-device-report.json"].decode("utf-8-sig"))
    report["partialDeviceSummary"] = {key: device.get(key) for key in [
        "commit", "runId", "pid", "status", "setupStep", "policyRestored", "errors", "testFailures", "contractErrors"
    ]}
    report["partialDeviceSummary"]["phases"] = [{key: phase.get(key) for key in ["name", "status", "error"]}
                                               for phase in device["phases"]]
    actual_prefix = "installed-plugin-probe/native-debug/actual/"
    report["actualMonitorFiles"] = [row for row in artifact_files if row["path"].startswith(actual_prefix)]
    report["actualMonitorSummaryPresent"] = any(row["path"] == actual_prefix + "native-debug-summary.json"
                                                for row in artifact_files)
    report["actualMinidumpCount"] = sum(row["scope"] == "actual" for row in dumps)
    report["controlMinidumpCount"] = sum(row["scope"] == "control" for row in dumps)
    report["originalDriverExit"] = native["driverExitCode"]
    report["originalNativeExit"] = native["nativeExit"]
    report["causeOfApplicationExit"] = "UNPROVEN"
    report["causeOfMonitorDisappearance"] = "UNPROVEN"
    report["artifactCodeExecuted"] = False
    report["status"] = "completed"
except Exception as error:
    report["error"] = str(error)
    report["traceback"] = traceback.format_exc()

finally:
    after = snapshot()
    report["sourceAndIndexUnchanged"] = before == after
    if before != after:
        report["status"] = "failed"
    report["trackedFiles"] = len(after["files"])
    for name, value in [("source-before.json", before), ("source-after.json", after), ("native-debug-a-evidence.json", report)]:
        (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("BEGIN_QA4424_NATIVE_DEBUG_A_EVIDENCE", flush=True)
    print(json.dumps(report, ensure_ascii=False), flush=True)
    print("END_QA4424_NATIVE_DEBUG_A_EVIDENCE", flush=True)
raise SystemExit(0 if report["status"] == "completed" else 1)
