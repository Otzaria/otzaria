#!/usr/bin/env python3
"""Implementation self-check only; retained input replay is not native acceptance."""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch

ROOT = Path.cwd()
OUT = Path(os.environ["CLOCK_SELF_OUTPUT"]).resolve()
OUT.mkdir(parents=True, exist_ok=False)
SOURCE_TREE = "dcac8bf18d2cd7f489fa5b89d78de9f7b2a6a425"
PUBLIC_PARENT = "3b9c05140f722d31fe1fb7312e9722db646335a5"
PAYLOAD = [".github/workflows/qa_4425_clock_implementation.yml","tool/perf_probe/qa_4425_clock_implementation.py","tool/perf_probe/qa_4425_clock_replay.dart","tool/perf_probe/qa_4425_clock_source_manifest.json","tool/perf_probe/qa_4425_retained_mac_evidence.json","tool/perf_probe/qa_4425_retained_ios_evidence.json"]
def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode().strip()

def digest(data):
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "blob": hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()}

def snapshot():
    files = {}
    for raw in subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).split(b"\0"):
        if not raw:
            continue
        path = ROOT / os.fsdecode(raw)
        data = os.fsencode(os.readlink(path)) if path.is_symlink() else path.read_bytes()
        files[os.fsdecode(raw)] = {**digest(data), "mode": path.lstat().st_mode}
    return {"head": git("rev-parse", "HEAD"), "index": git("write-tree"),
            "status": git("status", "--porcelain=v1", "--untracked-files=all"), "files": files}

source = git("rev-parse", "HEAD^")
assert git("rev-parse", source + "^{tree}") == SOURCE_TREE
assert git("show", "-s", "--format=%P", source) == PUBLIC_PARENT
assert git("show", "-s", "--format=%P", "HEAD") == source
assert set(git("diff", "--name-only", source, "HEAD").splitlines()) == set(PAYLOAD)
assert git("show", "-s", "--format=%ae%x00%ce", source).split("\0") == ["7353755@gmail.com"] * 2
assert git("show", "-s", "--format=%ae%x00%ce", "HEAD").split("\0") == ["7353755@gmail.com"] * 2
manifest_path = ROOT / "tool/perf_probe/qa_4425_clock_source_manifest.json"
assert digest(manifest_path.read_bytes()) == {"bytes":19584,"blob":"1f9a0cc4a02ef00ccc37f54cc717e5fdac71a38a","sha256":"3a13004b585714f58cc009a33bc9b489ad18726bebda100ef76ad1674a13c2fd"}
manifest = json.loads(manifest_path.read_text())
assert manifest["expectedCandidateTree"] == SOURCE_TREE
for entry in manifest["fullManifest"]["files"]:
    data = (ROOT / entry["path"]).read_bytes()
    assert digest(data) == {key: entry[key] for key in ("bytes", "sha256", "blob")}, entry["path"]
    assert git("ls-files", "-s", "--", entry["path"]).split()[0] == entry["mode"]
before = snapshot()
assert not before["status"]
assert len(before["files"]) == 4204, len(before["files"])
(OUT / "source-before.json").write_text(json.dumps(before, sort_keys=True))
spec = importlib.util.spec_from_file_location("clock_subject", ROOT / "tool/perf_probe/apple_plugin_activity/run.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
summary = {"classification": "IMPLEMENTATION_SELF_CHECK_ONLY", "source": source, "sourceTree": SOURCE_TREE,
           "nativeExecution": "NOT_RUN", "independentQA": "NOT_RUN", "fullProjectAnalyze": "NOT_RUN",
           "originalGitHook": "NOT_RUN", "sourceManifestFiles": len(manifest["fullManifest"]["files"]),
           "stages": [], "status": "running"}
def command(label, args, cwd=ROOT, timeout=180):
    succeeded = False
    try:
        with patch.object(runner, "REPO", cwd):
            result = runner.recorded_output(OUT, label, [str(value) for value in args], timeout)
        succeeded = True
    finally:
        if not succeeded:
            for suffix in (".json", ".stdout.log", ".stderr.log"):
                path = OUT / (label + suffix)
                if path.is_file():
                    data = path.read_bytes()
                    print("SELF_FAILED_COMMAND_FILE " + json.dumps({
                        "path": path.name, **digest(data),
                        "base64": base64.b64encode(data).decode()}), flush=True)
    record = json.loads((OUT / (label + ".json")).read_text())
    assert record["exitCode"] == 0 and record["ownedGroupCleanup"]["groupDrained"]
    for key in ("stdout", "stderr"):
        assert not record[key]["truncated"], label
    summary["stages"].append({"label": label, "exit": 0, "cleanup": record["ownedGroupCleanup"]})
    print("SELF_STAGE " + json.dumps({"label": label, "exit": 0, "stdout": result}), flush=True)
    return result

try:
    version = json.loads(command("flutter-version", ["flutter", "--version", "--machine"]))
    assert version["frameworkVersion"] == "3.47.7", version
    assert version["frameworkRevision"] == "abaf9c523780a608bd46686fd5e53740a07077f8", version
    assert version["dartSdkVersion"].split()[0] == "3.13.5", version
    summary["sdk"] = version
    with tempfile.TemporaryDirectory(prefix="clock-contract-") as temporary:
        package = Path(temporary).resolve()
        (package / "pubspec.yaml").write_text(
            "name: clock_contract_implementation_selfcheck\n"
            "environment:\n  sdk: '>=3.12.0 <4.0.0'\n"
            "dev_dependencies:\n  flutter_test:\n    sdk: flutter\n")
        source_options = (ROOT / "analysis_options.yaml").read_text()
        assert source_options.endswith("formatter:\n  trailing_commas: preserve\n")
        (package / "analysis_options.yaml").write_text("formatter:\n  trailing_commas: preserve\n")
        dart_paths = ["tool/perf_probe/apple_plugin_activity/contract.dart",
                      "test/tool/perf_probe/apple_plugin_activity_contract_test.dart"]
        for name in dart_paths:
            target = package / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        command("isolated-test-pub", ["flutter", "pub", "get"], cwd=package, timeout=300)
        configuration = json.loads((package / ".dart_tool/package_config.json").read_text())
        own_package = next(item for item in configuration["packages"]
                           if item["name"] == "clock_contract_implementation_selfcheck")
        assert own_package["languageVersion"] == "3.12", own_package
        command("dart-format-copies", ["dart", "format", *(package / name for name in dart_paths)], cwd=package)
        formatted = []
        for name in dart_paths:
            data = (package / name).read_bytes()
            target = OUT / ("formatted-" + Path(name).name)
            target.write_bytes(data)
            item = {"path": name, **digest(data), "changedByFormatter": data != (ROOT / name).read_bytes(),
                    "base64": base64.b64encode(data).decode()}
            formatted.append({key: value for key, value in item.items() if key != "base64"})
            print("SELF_FORMATTED_FILE " + json.dumps(item), flush=True)
        summary["formattedFiles"] = formatted
        command("isolated-contract-analyze", ["flutter", "analyze", "--no-pub"], cwd=package, timeout=300)
        command("isolated-contract-tests", ["flutter", "test", "--no-pub", "--reporter=expanded",
                "test/tool/perf_probe/apple_plugin_activity_contract_test.dart"], cwd=package, timeout=300)
        command("python-focused", [sys.executable, "-m", "unittest", "discover", "-s",
                "tool/perf_probe/apple_plugin_activity", "-p", "test_runner.py", "-v"], timeout=180)
        mac_path = ROOT / "tool/perf_probe/qa_4425_retained_mac_evidence.json"
        ios_path = ROOT / "tool/perf_probe/qa_4425_retained_ios_evidence.json"
        assert digest(mac_path.read_bytes()) == {
            "bytes": 2715803, "blob": "2a3ce51227e0a9e5fab36728eb0b32efd30ed3a5",
            "sha256": "03731e39488536b8969ed05252e5a75e34f93f44315a586e08ab69c805b2b0cc"}
        assert digest(ios_path.read_bytes()) == {
            "bytes": 3352407, "blob": "32722845cc92d8d9f774e85454955f11a926ed68",
            "sha256": "8f6e8250978ea58dd4adf0912b3b59f028ea00d87cc54911196e2b8bc5b4724a"}
        evidence = json.loads(ios_path.read_text())
        old_job = next(entry["value"] for entry in evidence["iosRetry"]["originalSourceJson"]
                       if entry["path"] == "driver-visible.json")
        job = json.loads(json.dumps(old_job))
        replay_dir = OUT / "ios-controller-replay"
        replay_dir.mkdir()
        coordinator = runner.Coordinator(replay_dir, job["runId"], "local-replay-only", "ios", 12, physical=True)
        with patch.object(runner.time, "sleep"), patch.object(coordinator.control_result, "wait", return_value=True):
            coordinator.run_job(job)
        assert job["status"] == "passed" and not coordinator.background_failures
        replay_driver = dict(old_job)
        for key in ("quietStartMs", "quietEndMs", "quietElapsedMs", "controlClockUncertaintyMs", "controlTimestampMarginMs"):
            replay_driver[key] = job[key]
        driver_path = OUT / "ios-repaired-driver-replay.json"
        driver_path.write_text(json.dumps(replay_driver))
        (package / "new_contract.dart").write_bytes((ROOT / dart_paths[0]).read_bytes())
        old_contract = subprocess.check_output(["git", "show", PUBLIC_PARENT + ":" + dart_paths[0]], cwd=ROOT)
        assert digest(old_contract)["blob"] == "72ee860815155f68cc5448da4838c518c8eff593"
        (package / "old_contract.dart").write_bytes(old_contract)
        shutil.copyfile(ROOT / "tool/perf_probe/qa_4425_clock_replay.dart", package / "replay.dart")
        command("retained-input-replay", ["dart", package / "replay.dart", mac_path, ios_path,
                driver_path, OUT / "retained-input-replay.json"], timeout=180)
    summary["status"] = "passed"
except BaseException as error:
    summary.update(status="failed", error=repr(error))
    raise
finally:
    after = snapshot()
    summary["sourceUnchanged"] = before == after
    (OUT / "source-after.json").write_text(json.dumps(after, sort_keys=True))
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print("SELF_CLOCK_SUMMARY " + json.dumps(summary), flush=True)
    if before != after:
        raise RuntimeError("Tracked source/index changed during implementation self-check")
