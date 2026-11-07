#!/usr/bin/env python3
"""Independent fast QA only; source is never rewritten."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse

SOURCE = "b22d17645c5c4650ddf9cdb05d5b2b53af8932c9"
SOURCE_TREE = "e416df6790843b3adae70e7997cbb67db13a51cc"
PARENT = "9fdc05b9dc98c732affeb91bd78062ea369387dc"
FRAMEWORK = "abaf9c523780a608bd46686fd5e53740a07077f8"
QA_PATHS = [".github/qa/4428/private_cache_fast.py", ".github/workflows/qa_4428_private_cache_fast.yml"]
FILES = json.loads(r'''[{"path":".github/workflows/installed_plugin_probe_android.yml","mode":"100644","blob":"f731b8607b72c4f583bee251f3c1215224f349bc","sha256":"6828b039ca7c6b09125a0e6c4cdf41c6c118f5bc93da9b862d516b7cf4415216","bytes":4233,"baseBlob":"f731b8607b72c4f583bee251f3c1215224f349bc","changed":false},{"path":"android/app/build.gradle","mode":"100644","blob":"1ea47509d93d48688a7be4e328355b777347be11","sha256":"7f4bb82fb21cf82d8b93e76551b541e13c9061cecc5075effa8e1d06c8ce91cd","bytes":3595,"baseBlob":"1ea47509d93d48688a7be4e328355b777347be11","changed":false},{"path":"integration_test/installed_plugin_resource_probe_test.dart","mode":"100644","blob":"7a6c212c09e546a8840d7b88765cbf26a27c6493","sha256":"f5ad2702c9a8bea1ab687ef273444a5ad85dc8d28839f42015223e832428a802","bytes":59589,"baseBlob":"82b65ddcfc94b8a50e058b744ff7b0eeeed233a4","changed":true},{"path":"integration_test/support/installed_plugin_android_control.dart","mode":"100644","blob":"7755b10653ad65bd6e13c6aa5ab76c1799b0d51f","sha256":"f44ed3d8c2937730325dca609b6a6e81fff8d4f2210b30eaf2d3ad0309d9272f","bytes":7847,"baseBlob":"7e00a28797ffa975a54e58617e48e72bb8cb77a7","changed":true},{"path":"pubspec.lock","mode":"100644","blob":"5e175ffefe86620541f53dcf8172b9c0f412b2bd","sha256":"7cb40007d9484e613567165ea97b2ead3426a50c60c16a7e6fa874af32a27faf","bytes":66487,"baseBlob":"5e175ffefe86620541f53dcf8172b9c0f412b2bd","changed":false},{"path":"pubspec.yaml","mode":"100644","blob":"332081188494a74e08c57595eb01ec882c0f97e3","sha256":"70eda15deb3977c28e581205f8242f6f0ffa368ab82fc17aee0877c29e64b232","bytes":13609,"baseBlob":"332081188494a74e08c57595eb01ec882c0f97e3","changed":false},{"path":"test/tool/perf_probe/installed_plugin_android_control_test.dart","mode":"100644","blob":"7704e13a4ccaabb2e09eb6aba4b31da504787332","sha256":"4f5fc90c183ca95c8bcbccad04068453f47bd51087e27c5b5b9af823e75e479f","bytes":15881,"baseBlob":"17ddba4bf82df374c02f38212191b807263b21d0","changed":true},{"path":"tool/perf_probe/INSTALLED_PLUGIN_ANDROID.md","mode":"100644","blob":"41f0ca27275be2aeea5d86b44b33c00eced38550","sha256":"10797de82575f5862d5c0cc7e77addca0bdef279ae5d47c1c7d8840a92030da8","bytes":13183,"baseBlob":"4a780663afbbb35cde67f700b0a3a6bdbae7caaf","changed":true},{"path":"tool/perf_probe/run_installed_plugin_android.py","mode":"100644","blob":"88e6897857a7c9c3340123edf95947baf3cbe566","sha256":"53752be7c5261469156641554c958001630b1079f8ac2762507a206cfe5389e0","bytes":44383,"baseBlob":"88e6897857a7c9c3340123edf95947baf3cbe566","changed":false},{"path":"tool/perf_probe/test_installed_plugin_android.py","mode":"100644","blob":"72dc98e88aad52135c0d694fa5e0aa3cd7a1f0f2","sha256":"e321c9130bd4bcea7491d02291dea34cd11f97aa2c3b58e7e1215e4b66759b6d","bytes":54170,"baseBlob":"72dc98e88aad52135c0d694fa5e0aa3cd7a1f0f2","changed":false}]''')
DART_FILES = [item["path"] for item in FILES if item["changed"] and item["path"].endswith(".dart")]
ROOT = Path.cwd()
OUT = Path(os.environ["RUNNER_TEMP"]) / "qa-4428-private-cache-fast"
OUT.mkdir(parents=True, exist_ok=True)
RESULT = {"schemaVersion": 1, "source": SOURCE, "sourceTree": SOURCE_TREE, "parent": PARENT,
          "qaKind": "fast-source-controls", "nativeAcceptance": "NOT_RUN", "gates": {}, "formatter": [],
          "counts": {}, "limits": ["Mock filesystem tests are not Android native acceptance.",
                                 "No physical profile/release/performance run."]}

def marker(name, value):
    print(name + " " + json.dumps(value, sort_keys=True, separators=(",", ":")), flush=True)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def blob(data):
    return hashlib.sha1(("blob " + str(len(data)) + "\0").encode() + data).hexdigest()

def git(*args, cwd=ROOT):
    return subprocess.check_output(["git", *args], cwd=cwd)

def save_json(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")

def snapshot(root=ROOT):
    index = git("ls-files", "--stage", "-z", cwd=root)
    entries = []
    for raw in git("ls-files", "-z", cwd=root).split(b"\0"):
        if not raw:
            continue
        name = os.fsdecode(raw)
        path = root / name
        if path.is_symlink():
            data = os.fsencode(os.readlink(path))
            kind = "symlink"
        elif path.is_file():
            data = path.read_bytes()
            kind = "file"
        else:
            data = b""
            kind = "missing"
        entries.append([name, kind, len(data), sha(data), path.lstat().st_mode if path.exists() or path.is_symlink() else None])
    packed = json.dumps(entries, ensure_ascii=True, separators=(",", ":")).encode()
    return {"head": git("rev-parse", "HEAD", cwd=root).decode().strip(), "indexSha256": sha(index),
            "trackedSha256": sha(packed), "tracked": entries,
            "status": git("status", "--porcelain=v1", "--untracked-files=no", cwd=root).decode()}

def brief(snapshot_value):
    return {key: value for key, value in snapshot_value.items() if key != "tracked"}

def run(name, command, timeout=1200):
    print("COMMAND " + json.dumps({"name": name, "argv": command, "timeoutSeconds": timeout}), flush=True)
    target = OUT / (name + ".log")
    started = time.monotonic()
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    timed_out = False
    with target.open("wb") as output:
        while selector.get_map():
            elapsed = time.monotonic() - started
            if elapsed > timeout and process.poll() is None:
                timed_out = True
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
            for key, _ in selector.select(timeout=0.5):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                output.write(chunk)
                output.flush()
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
    code = process.wait()
    result = {"status": "PASS" if code == 0 and not timed_out else "BLOCKED", "exitCode": code,
              "timedOut": timed_out, "seconds": round(time.monotonic() - started, 3),
              "log": target.name, "logBytes": target.stat().st_size, "logSha256": sha(target.read_bytes())}
    RESULT["gates"][name] = result
    save_json("partial-result.json", RESULT)
    marker("QA_GATE", {"name": name, **result})
    return result, target

def verify_source():
    assert git("rev-parse", "HEAD^").decode().strip() == SOURCE, "QA commit must have source as sole parent"
    parents = git("rev-list", "--parents", "-n", "1", "HEAD").decode().split()
    assert parents[1:] == [SOURCE], "Unexpected QA ancestry"
    assert git("rev-parse", SOURCE + "^{tree}").decode().strip() == SOURCE_TREE
    assert git("rev-list", "--parents", "-n", "1", SOURCE).decode().split()[1:] == [PARENT]
    names = git("diff", "--name-only", "-z", SOURCE, "HEAD").decode().strip("\0").split("\0")
    assert sorted(names) == sorted(QA_PATHS), names
    for revision in [SOURCE, "HEAD"]:
        author = git("show", "-s", "--format=%an%x00%ae%x00%cn%x00%ce", revision).decode().strip().split("\0")
        assert author == ["Y-Ploni", "7353755@gmail.com", "Y-Ploni", "7353755@gmail.com"], author
    expected_delta = sorted(item["path"] for item in FILES if item["changed"])
    assert sorted(git("diff", "--name-only", "-z", PARENT, SOURCE).decode().strip("\0").split("\0")) == expected_delta
    records = []
    for item in FILES:
        data = (ROOT / item["path"]).read_bytes()
        assert len(data) == item["bytes"] and sha(data) == item["sha256"] and blob(data) == item["blob"], item["path"]
        tree = git("ls-tree", SOURCE, "--", item["path"]).decode().strip().split()
        assert tree[:3] == [item["mode"], "blob", item["blob"]], tree
        records.append({**item, "verified": True})
    assert len(records) == 10 and sum(item["bytes"] for item in records) == 282977
    save_json("source-manifest-verification.json", records)
    RESULT["gates"]["source-binding"] = {"status": "PASS", "fullFiles": 10, "bytes": 282977, "deltaFiles": 4}

def sdk_snapshot():
    flutter = Path(subprocess.check_output(["which", "flutter"]).decode().strip()).resolve()
    sdk = flutter.parent.parent
    value = snapshot(sdk)
    value["root"] = str(sdk)
    return value

def git_dependency_snapshots():
    lock = (ROOT / "pubspec.lock").read_text()
    chunks = re.findall(r"^  ([A-Za-z_][A-Za-z0-9_]*):\n(.*?)(?=^  [A-Za-z_][A-Za-z0-9_]*:|\Z)", lock, re.M | re.S)
    expected = {}
    for name, body in chunks:
        if re.search(r"^    source: git$", body, re.M):
            ref = re.search(r'^      resolved-ref: "?([0-9a-f]{40})"?$', body, re.M)
            assert ref, name
            expected[name] = ref.group(1)
    config_path = ROOT / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text())
    packages = {item["name"]: item for item in config["packages"]}
    native = {"flutter_inappwebview", "flutter_inappwebview_android", "flutter_inappwebview_ios",
              "flutter_inappwebview_macos", "flutter_inappwebview_platform_interface",
              "flutter_inappwebview_web", "flutter_inappwebview_windows", "flutter_inappwebview_linux"}
    assert native <= expected.keys(), sorted(expected)
    for name in native:
        assert expected[name] == "124bb8e63f345ffd0b0f2ea7190c24b19e69897d", (name, expected[name])
    assert expected["window_manager"] == "4f37655288ce8b803a9bd50294c5d6983850f622"
    assert packages["path_provider_platform_interface"]["rootUri"], "Direct interface dependency unavailable"
    records = {}
    for name, revision in expected.items():
        uri = packages[name]["rootUri"]
        parsed = urlparse(uri)
        directory = Path(unquote(parsed.path)) if parsed.scheme == "file" else (config_path.parent / unquote(uri)).resolve()
        repository = Path(git("rev-parse", "--show-toplevel", cwd=directory).decode().strip())
        snap = snapshot(repository)
        assert snap["head"] == revision and not snap["status"], (name, brief(snap), revision)
        records[name] = {"revision": revision, "directory": str(directory), "snapshot": snap}
    save_json("git-dependencies-before.json", records)
    return records

def capture_format():
    before = snapshot()
    save_json("formatter-before.json", before)
    overall, _ = run("dart-format", ["dart", "format", "--output=none", "--set-exit-if-changed", *DART_FILES], 120)
    for number, path in enumerate(DART_FILES):
        shown = subprocess.run(["dart", "format", "--output=show", "--summary=none", path], cwd=ROOT, capture_output=True, timeout=120)
        output = OUT / ("formatter-" + str(number) + "-canonical.dart")
        output.write_bytes(shown.stdout)
        (OUT / ("formatter-" + str(number) + "-stderr.log")).write_bytes(shown.stderr)
        original = (ROOT / path).read_bytes()
        entry = {"path": path, "exitCode": shown.returncode, "bytes": len(shown.stdout),
                 "sha256": sha(shown.stdout), "gitBlob": blob(shown.stdout),
                 "originalBytes": len(original), "originalSha256": sha(original),
                 "changed": shown.stdout != original, "artifact": output.name,
                 "stderrBytes": len(shown.stderr)}
        if shown.returncode != 0:
            overall["status"] = "BLOCKED"
        RESULT["formatter"].append(entry)
        marker("QA_FORMAT_FILE", entry)
        if entry["changed"] and shown.returncode == 0:
            marker("QA_CANONICAL_BYTES", {**entry, "base64": base64.b64encode(shown.stdout).decode()})
    after = snapshot()
    save_json("formatter-after.json", after)
    RESULT["gates"]["formatter-preserved-source-and-index"] = {"status": "PASS" if before == after else "BLOCKED",
                                                              "before": brief(before), "after": brief(after)}
    if any(item["changed"] or item["exitCode"] for item in RESULT["formatter"]):
        overall["status"] = "BLOCKED"

def count_dart_tests(log):
    starts = {}
    finished = []
    for line in log.read_text(errors="replace").splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") == "testStart":
            starts[event["test"]["id"]] = event["test"]
        if event.get("type") == "testDone" and not event.get("hidden", False):
            finished.append({**event, "name": starts.get(event["testID"], {}).get("name")})
    return {"total": len(finished), "passed": sum(item.get("result") == "success" and not item.get("skipped") for item in finished),
            "skipped": sum(bool(item.get("skipped")) for item in finished), "tests": finished}

def main():
    verify_source()
    before = snapshot()
    sdk_before = sdk_snapshot()
    save_json("source-before.json", before)
    save_json("sdk-before.json", sdk_before)
    assert not before["status"] and not sdk_before["status"], "Initial source/SDK must be clean"
    version_result, version_log = run("sdk-version", ["flutter", "--version", "--machine"], 180)
    assert version_result["status"] == "PASS"
    version = json.loads(version_log.read_text())
    assert version["frameworkVersion"] == "3.47.7" and version["frameworkRevision"] == FRAMEWORK, version
    assert version["dartSdkVersion"].split()[0] == "3.13.5", version
    RESULT["sdk"] = version
    pub_result, _ = run("strict-pub", ["flutter", "pub", "get", "--enforce-lockfile"], 900)
    if pub_result["status"] != "PASS":
        raise RuntimeError("Strict pub failed; normal package configuration unavailable")
    deps_before = git_dependency_snapshots()
    capture_format()
    targeted, targeted_log = run("dart-android-controls", ["flutter", "test", "--no-pub", "--concurrency=1", "--reporter=json",
                                                        "test/tool/perf_probe/installed_plugin_android_control_test.dart"], 1800)
    counts = count_dart_tests(targeted_log)
    RESULT["counts"]["android-controls"] = counts
    if counts["total"] != 14 or counts["passed"] != 14 or counts["skipped"]:
        targeted["status"] = "BLOCKED"
    marker("QA_DART_COUNTS", {"suite": "android-controls", **counts})
    relevant, relevant_log = run("dart-existing-contracts", ["flutter", "test", "--no-pub", "--concurrency=1", "--reporter=json",
                                                           "test/tool/perf_probe/installed_plugin_probe_test.dart",
                                                           "test/tool/perf_probe/perf_fixture_startup_settings_test.dart"], 1800)
    RESULT["counts"]["existing-contracts"] = count_dart_tests(relevant_log)
    run("python-android-host-controls", ["python3", "-m", "unittest", "-v", "tool/perf_probe/test_installed_plugin_android.py"], 300)
    run("node-fixture-controls", ["node", "--test", "tool/perf_probe/test_installed_plugin_fixture.mjs"], 300)
    after = snapshot()
    sdk_after = sdk_snapshot()
    save_json("source-after.json", after)
    save_json("sdk-after.json", sdk_after)
    deps_after = {}
    for name, item in deps_before.items():
        directory = Path(item["directory"])
        repository = Path(git("rev-parse", "--show-toplevel", cwd=directory).decode().strip())
        deps_after[name] = {**item, "snapshot": snapshot(repository)}
    save_json("git-dependencies-after.json", deps_after)
    for name, identical in [("source-and-index-unchanged", before == after), ("sdk-unchanged", sdk_before == sdk_after),
                            ("git-dependencies-unchanged", deps_before == deps_after)]:
        RESULT["gates"][name] = {"status": "PASS" if identical else "BLOCKED"}
    RESULT["sourceSnapshots"] = {"before": brief(before), "after": brief(after)}
    RESULT["sdkSnapshots"] = {"before": brief(sdk_before), "after": brief(sdk_after)}

try:
    main()
except Exception as error:
    import traceback
    RESULT["exception"] = {"type": type(error).__name__, "message": str(error), "traceback": traceback.format_exc()}
    traceback.print_exc()
finally:
    try:
        final_snapshot = snapshot()
        save_json("final-source-snapshot.json", final_snapshot)
        initial_file = OUT / "source-before.json"
        if initial_file.exists():
            RESULT["gates"]["final-source-and-index-unchanged"] = {"status": "PASS" if json.loads(initial_file.read_text()) == final_snapshot else "BLOCKED"}
    except Exception as final_error:
        RESULT["finalSnapshotError"] = str(final_error)
        RESULT["gates"]["final-snapshot"] = {"status": "BLOCKED"}
    RESULT["status"] = "PASS" if not RESULT.get("exception") and RESULT["gates"] and all(item["status"] == "PASS" for item in RESULT["gates"].values()) else "BLOCKED"
    save_json("qa-result.json", RESULT)
    marker("QA_FAST_RESULT", RESULT)
sys.exit(0 if RESULT["status"] == "PASS" else 1)
