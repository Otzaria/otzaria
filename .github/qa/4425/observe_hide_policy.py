#!/usr/bin/env python3
"""Observe only owned AppKit fixture/controller policies; no application acceptance."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time
import traceback
import unittest

sys.dont_write_bytecode = True
SOURCE = "2497e0dde51862129fd34569290118b475a05f32"
SOURCE_TREE = "fe1051a7754b5fcc07b8afbddeded3ebade447bd"
QA_FILES = {".github/qa/4425/observe_hide_policy.py", ".github/workflows/qa_4425_hide_policy.yml"}
MANIFEST = [["ios/Runner.xcodeproj/project.pbxproj","b5f0f0c700d3933e762d38c3d706b2ce3af9d82a","cba33ded34fa00b8f1aacfc0da74126aac3085256c2e44ce06fed7ec5c81374f",31892,"100644"],["ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme","c3fedb29c990d9c5a66b9f4ffb198b0ca3ce2ce5","9fbce429f56243561dd437a527136c9f9ed77165e3b271b923faf236cfcd0484",4717,"100644"],[".github/workflows/apple-plugin-activity.yml","9ec09629f9db04e4ce974c181033c3d2a1becf14","dc08561260f17d941af5fb99cfe172f3e36ed5a60be9a96299f7ac58f9d939d2",6594,"100644"],["integration_test/apple_plugin_activity_probe_test.dart","12539d1e150832b2ae2971181612caba13d8b5f8","44b0be6b97633b8526ce192eef75578ebb8bed6941276f9009bd548699cbe643",30720,"100644"],["lib/core/window_listener.dart","25b13d9b31afead65b3f0ad17e7d9f7cca7167b3","5f8680dc146863e76e73522be736133606871d0eb14d1ac8019d1a9102722800",33230,"100644"],["pubspec.yaml","cf796836f78f63e1cea0ce2cdbaa7dca9140246f","72e41248f6afdf7831079a1c117e27a68f82f6dbfa8d87e3fed840ed772dd7d1",13609,"100644"],["pubspec.lock","61f0e395ef0f048f47f46094a20cfa421a5e0178","fe731ab5452aba50c3311555016e18b868a4749dbcd5e19b86970a2981cb389c",66487,"100644"],["tool/perf_probe/apple_plugin_activity/AppleQuietControl.swift","c20567565beba70d97f672a0434a8456b021fda0","633d866d38943ab76581f5dd4a34c85876b8029fb94f89872e2acd06249e057f",7225,"100644"],["tool/perf_probe/apple_plugin_activity/mac_application.swift","1b88798b9cc529581282f5271c3283657428195d","aa748521f88f26b05ece941d4950f5babe014f5c79237e8a2454209819ae8531",8113,"100644"],["tool/perf_probe/apple_plugin_activity/test_runner.py","ced1eb307c9c2c82012b85260f83daab6d108d8e","675eec2bad9270cde5ffb53c49446da613a8eb1578ec6c3d08d8f002f61a2a02",20697,"100644"],["tool/perf_probe/apple_plugin_activity/test_macos_controller.py","ddfc41f286c2b9132fcf2e7cae346e5aae9c6565","5607234f32dd0e6a12651a3ad1ae84e2dff82ca729abeb9d8d6d34e02af07095",13493,"100644"],["tool/perf_probe/apple_plugin_activity/README.md","b13ec0809bc05d14eb47e5811ae8081a52cd6ed2","409f65d80aafc502f32b5d2286f057e06c575975df6fafe526647ba41e0c4017",33209,"100644"],["tool/perf_probe/apple_plugin_activity/run.py","8d2dab61ce48f4dd50804e1d5d0578abb8b854e0","dcd1f451cd9e02646f77b2aeb19e87a25505c3924dec6aa0037546ca3eddfcb8",57516,"100644"],["test/core/window_listener_native_visibility_test.dart","a6394e2c03a45c5a31462a5c1c4790382ed4297c","307d75acb0d29a208f85278a2341c4ebcbaac26c3995b3a085dc8a561bb12bab",3648,"100644"],["tool/perf_probe/apple_plugin_activity/mac_launch_fixture.swift","6ee7c7f170a58ac81bc970c4d1ab0ce7ed94c0a7","a623fc9da165e928446b4d466f234a747bf93e1d9b8a0200d8833d67319d0303",4493,"100644"],["tool/perf_probe/apple_plugin_activity/test_lifetime.py","208e6559e34e937c346d3c05d4ff9a0b49835492","e7f4af98f85edee8020f45c761a33d5eba09e2ee18c856560e0b39f8d6f9f249",21333,"100644"],["tool/perf_probe/apple_plugin_activity/test_cleanup_boundaries.py","3520002f786c8adb5d61031fca117a0b4837deab","eddd4c1cd4ab7451619ee57188bcd984e3d61eaad5395d3e1679201355f11625",17681,"100644"],["tool/perf_probe/apple_plugin_activity/test_cleanup_permissions.py","dabca892ebb9adbe7934cd00889e92d22958aeb6","635776c77d74ac1ce63b3b0cd8e6ad90b46b82e03db576fb5b408e74f32ce560",11628,"100644"]]
ROOT = Path.cwd().resolve()
OUT = Path(os.environ["QA_HIDE_POLICY_OUTPUT"]).resolve()
assert OUT != ROOT and ROOT not in OUT.parents
OUT.mkdir(parents=True, exist_ok=False)
os.environ.pop("GITHUB_TOKEN", None)
os.environ.pop("GH_TOKEN", None)
os.environ.pop("QA_GITHUB_TOKEN", None)
CONTROLS = OUT / "controls"
os.environ["APPLE_HELPER_CONTROL_OUTPUT"] = str(CONTROLS)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode().strip()

def save(name, data):
    (OUT / name).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

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

def observed_rows(pid):
    result = subprocess.run(["ps", "-p", str(pid), "-o", "pid=,pgid=,state=,comm="],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    return {"pid": pid, "psExitCode": result.returncode,
            "rows": result.stdout.decode("utf-8", "replace").splitlines(),
            "stderr": result.stderr.decode("utf-8", "replace")}

summary = {"schemaVersion": 1, "source": SOURCE, "sourceTree": SOURCE_TREE,
           "scope": "Actual owned AppKit helper observations only; no Otzaria or quiet-window acceptance",
           "status": "failed", "observations": [], "nativeApplicationAcceptance": "NOT_RUN",
           "production": "OFF", "physicalProfileRelease": "NOT_RUN"}
before = None
try:
    assert sys.platform == "darwin"
    assert git("rev-parse", "HEAD^") == SOURCE
    assert git("rev-parse", SOURCE + "^{tree}") == SOURCE_TREE
    assert set(git("diff", "--name-only", SOURCE, "HEAD").splitlines()) == QA_FILES
    for name, blob, digest, size, mode in MANIFEST:
        data = (ROOT / name).read_bytes()
        assert len(data) == size and sha(data) == digest, name
        assert hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest() == blob, name
        assert git("ls-files", "-s", "--", name).split()[0] == mode, name
    before = snapshot()
    assert not before["status"]
    save("source-before.json", before)
    summary.update(qaHead=before["head"], qaTree=before["indexTree"],
                   verifiedSourceFiles=len(MANIFEST), host=platform.platform(),
                   python=sys.version, xcode=subprocess.check_output(["xcodebuild", "-version"]).decode().strip())
    path = ROOT / "tool/perf_probe/apple_plugin_activity/test_macos_controller.py"
    spec = importlib.util.spec_from_file_location("qa4425_native_controls", path)
    native = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(native)
    runner = native.runner
    Base = native.NativeMacIdentityTests
    Base.setUpClass()
    original = (ROOT / "tool/perf_probe/apple_plugin_activity/mac_application.swift").read_text()
    assert original.count(".prohibited") == 3
    policies = [("prohibited", 2), ("accessory", 1), ("regular", 0)]
    controllers = {}
    bindings = []
    for policy, raw in policies:
        candidate = original if policy == "prohibited" else original.replace(".prohibited", "." + policy)
        source_path = OUT / ("controller-" + policy + ".swift")
        source_path.write_text(candidate)
        helper = OUT / ("controller-" + policy)
        runner.recorded_output(CONTROLS, "compile-observer-" + policy,
                               ["xcrun", "swiftc", str(source_path), "-o", str(helper)], 120)
        controllers[policy] = helper
        bindings.append({"policy": policy, "rawValue": raw,
                         "sourceSha256": sha(source_path.read_bytes()),
                         "originalSha256": sha(original.encode()),
                         "onlyChange": "Three exact .prohibited policy bindings" if raw != 2 else "Identical source",
                         "binarySha256": sha(helper.read_bytes())})
    summary["controllerVariants"] = bindings

    class ProbeCase(Base):
        def runTest(self):
            row = self.observation
            if self.launch_services:
                row["startup"], row["launchServices"] = self.start_launch_services()
                self.launch_receipt = self.directory / ("launch-services-" + str(self.launch_count) + ".json")
            else:
                self.target_process, row["startup"], _ = self.start_owned_app()
            self.target_pid = row["startup"]["pid"]
            self.controller = runner.MacApplicationSession(self.variant_helper, self.target_pid,
                                                          self.directory, self.label)
            self.addCleanup(self.controller.close)
            row["controllerPid"] = self.controller.process.pid
            row["responses"] = []
            row["operationFailures"] = []
            for action in ("info", "info", "hide", "activate"):
                try:
                    response = self.controller.request(action)
                    row["responses"].append(response)
                    if action == "info":
                        time.sleep(0.2)
                except BaseException as error:
                    row["operationFailures"].append({"action": action, "type": type(error).__name__,
                                                     "message": str(error)})
                    break
            row["allOperationsAcknowledged"] = len(row["responses"]) == 4
            row["controllerStayedInactiveAtResponses"] = all(
                x.get("applicationState", {}).get("controllerIsActive") is False for x in row["responses"]
            ) and bool(row["responses"])
            row["actualPolicyMatchesRequested"] = all(
                x.get("applicationState", {}).get("controllerActivationPolicy") == self.policy_raw for x in row["responses"]
            ) and bool(row["responses"])
            row["sameRetainedSession"] = (
                len({x["sessionToken"] for x in row["responses"]}) == 1 and
                len({x["controllerPid"] for x in row["responses"]}) == 1 and
                len({x["pid"] for x in row["responses"]}) == 1 and
                len({x["executable"] for x in row["responses"]}) == 1
            ) if row["responses"] else False

    cleanup_ok = True
    for policy, raw in policies:
        for launch in ("direct", "launch-services"):
            case = ProbeCase()
            case.policy_raw = raw
            case.variant_helper = controllers[policy]
            case.label = "observe-" + policy + "-" + launch
            case.launch_services = launch == "launch-services"
            case.target_process = None
            case.target_pid = None
            case.controller = None
            case.launch_receipt = None
            case.observation = {"policy": policy, "policyRaw": raw, "launchMethod": launch,
                                "label": case.label, "scope": "Controlled observation, not a source repair"}
            started = time.monotonic()
            result = unittest.TestResult()
            case.run(result)
            row = case.observation
            row["elapsedSeconds"] = time.monotonic() - started
            row["testFailures"] = [{"test": str(test), "traceback": trace} for test, trace in result.failures]
            row["testErrors"] = [{"test": str(test), "traceback": trace} for test, trace in result.errors]
            row["fixtureAndCleanupSucceeded"] = result.wasSuccessful()
            cleanup_ok = cleanup_ok and result.wasSuccessful()
            if case.controller is not None:
                row["controllerExitCode"] = case.controller.process.returncode
                row["controllerReceipt"] = case.controller.record
                stderr_path = CONTROLS / (case.controller.prefix + ".stderr.log")
                if stderr_path.exists():
                    data = stderr_path.read_bytes()
                    row["stderr"] = {"bytes": len(data), "sha256": sha(data),
                                     "text": data.decode("utf-8", "replace")}
            if case.target_process is not None:
                row["targetExitCode"] = case.target_process.returncode
                row["targetOwnedGroupCleanup"] = getattr(case.target_process, "apple_quiet_cleanup", None)
            if case.launch_receipt is not None and case.launch_receipt.exists():
                row["launchServicesCleanupReceipt"] = json.loads(case.launch_receipt.read_text())
            if case.target_pid is not None:
                row["targetAfterCleanup"] = observed_rows(case.target_pid)
                cleanup_ok = cleanup_ok and not row["targetAfterCleanup"]["rows"]
            summary["observations"].append(row)
            save("summary-partial.json", summary)
            print("BEGIN_QA4425_HIDE_POLICY_CASE", flush=True)
            print(json.dumps(row, ensure_ascii=False), flush=True)
            print("END_QA4425_HIDE_POLICY_CASE", flush=True)
    Base.doClassCleanups()
    summary["allOwnedFixtureCleanupSucceeded"] = cleanup_ok
    assert len(summary["observations"]) == 6
    assert cleanup_ok, "Native fixture setup/cleanup failed; evidence preserved"
    summary["status"] = "completed"
except BaseException as error:
    summary["error"] = {"type": type(error).__name__, "message": str(error),
                        "traceback": traceback.format_exc()}
finally:
    after = snapshot()
    save("source-after.json", after)
    summary["sourceAndIndexUnchanged"] = before == after if before is not None else False
    if before != after:
        summary["status"] = "failed"
    summary["trackedFiles"] = len(after["files"])
    save("summary.json", summary)
    print("BEGIN_QA4425_HIDE_POLICY_SUMMARY", flush=True)
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    print("END_QA4425_HIDE_POLICY_SUMMARY", flush=True)
raise SystemExit(0 if summary["status"] == "completed" else 1)
