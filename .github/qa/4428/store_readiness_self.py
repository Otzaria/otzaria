#!/usr/bin/env python3
"""Implementation-only Store readiness checks; independent native QA remains required."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
import traceback
import urllib.parse

SOURCE = "51e623bdfe1ec14f3cdfcbe5db3ed5841d30613b"
SOURCE_TREE = "e06157cf2b63f4f16d70b6739cf503aa747ec18a"
PUBLIC_PARENT = "9fdc05b9dc98c732affeb91bd78062ea369387dc"
SDK_HEAD = "abaf9c523780a608bd46686fd5e53740a07077f8"
QA_FILES = {
    ".github/qa/4428/store_readiness_self.py",
    ".github/workflows/qa_4428_store_readiness_self.yml",
}
MANIFEST = [{"path":".github/workflows/installed_plugin_probe_android.yml","mode":"100644","blob":"f731b8607b72c4f583bee251f3c1215224f349bc","bytes":4233,"sha256":"6828b039ca7c6b09125a0e6c4cdf41c6c118f5bc93da9b862d516b7cf4415216"},{"path":"android/app/build.gradle","mode":"100644","blob":"1ea47509d93d48688a7be4e328355b777347be11","bytes":3595,"sha256":"7f4bb82fb21cf82d8b93e76551b541e13c9061cecc5075effa8e1d06c8ce91cd"},{"path":"integration_test/installed_plugin_resource_probe_test.dart","mode":"100644","blob":"bef08c312b5c044ab4d76737fe382a66083ed90e","bytes":59960,"sha256":"81374ad5154cd8a21d3c325014d921eed34af689dc9db92a75cac4e49a0a57e4"},{"path":"integration_test/support/installed_plugin_android_control.dart","mode":"100644","blob":"7755b10653ad65bd6e13c6aa5ab76c1799b0d51f","bytes":7847,"sha256":"f44ed3d8c2937730325dca609b6a6e81fff8d4f2210b30eaf2d3ad0309d9272f"},{"path":"pubspec.lock","mode":"100644","blob":"5e175ffefe86620541f53dcf8172b9c0f412b2bd","bytes":66487,"sha256":"7cb40007d9484e613567165ea97b2ead3426a50c60c16a7e6fa874af32a27faf"},{"path":"pubspec.yaml","mode":"100644","blob":"332081188494a74e08c57595eb01ec882c0f97e3","bytes":13609,"sha256":"70eda15deb3977c28e581205f8242f6f0ffa368ab82fc17aee0877c29e64b232"},{"path":"test/tool/perf_probe/installed_plugin_android_control_test.dart","mode":"100644","blob":"72a0868e65a85dc9df7590377f7234019ad340b4","bytes":15880,"sha256":"18123632280b024183c3b7403ff16e04d5f540eb7ed5fef7a678fe987a68df6e"},{"path":"test/tool/perf_probe/installed_plugin_probe_test.dart","mode":"100644","blob":"cd30175b5e92fff596f8da3cc6afbb812be86f27","bytes":27307,"sha256":"96e05a02904cb443fc40904fc89aab3088e50c5cc353d8efe408b04725c594f7"},{"path":"tool/perf_probe/INSTALLED_PLUGIN_ANDROID.md","mode":"100644","blob":"9c5be90320135c020c0293fea22eaa61143d9dfa","bytes":14275,"sha256":"2c11dba1246b870ae494ab5b871c978e1cbe1a3be738b130119bcc3180d64f6f"},{"path":"tool/perf_probe/run_installed_plugin_android.py","mode":"100644","blob":"ed52fbaf1afc0c70dc554db7e922ba76b097b560","bytes":44385,"sha256":"ba03044836f876de02399220b3b6ae09b535eb23118363ee680652d692f10cc4"},{"path":"tool/perf_probe/src/installed_plugin_contract.dart","mode":"100644","blob":"0a4d8ed175ffb75cb90490a47d610af25f949cf5","bytes":7245,"sha256":"7b413cd5967448dc157aa026a7853fac4f73bcbe41f255b7b4cc465affc26693"},{"path":"tool/perf_probe/test_installed_plugin_android.py","mode":"100644","blob":"4c1be8c609b3d5ee69b4a9be84bb1b537cc6a91c","bytes":55457,"sha256":"53da871ca89837cc62416f669c3237636a6936cfa17d29d10aa9f1f3707756e0"},{"path":"tool/perf_probe/test_installed_plugin_store.mjs","mode":"100644","blob":"4b189beafe0a3acadaf0e075ae48f1e6232b7652","bytes":14054,"sha256":"aa46acb9fc3458d8a7c86ba6a4da396bd87df529862be454957db450a68c24bf"}]
GIT_PINS = {"flutter_inappwebview":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_android":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_ios":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_linux":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_macos":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_platform_interface":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_web":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_windows":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_local_notifications_windows":"ad21cf2cddfa7c79ea7903ad95b38a8d716b5f85","flutter_widget_from_html_core":"57080495ee8b89aeee156a4440b6de1c5e0f7ef2","opentype_shaper":"461902c049b412d64dc4dfa7b547fedbf751211d","otzaria_ashurit":"b43b67bb706be6bc87af14658d67e16cd347fc29","otzaria_icons":"483fec355339f54f9e094994a106dad9a63b82e3","otzaria_search_engine":"2da23091237ed0f0a612de3b2d18cfc99d8b7d2a","pdfrx":"942e27bec86e8d480111517c2083eb52817ee032","printing":"3cb90fb3025553f3e9f48638c79ccf93efb326af","seforim_library_updater":"6bfd33c3bc14392c1a6bb0887fdb23209068eab5","sentry_flutter":"93e7398355e80557a342666f98b23cc9bb832848","window_manager":"4f37655288ce8b803a9bd50294c5d6983850f622"}
FORMAT_PATHS = [
    "integration_test/installed_plugin_resource_probe_test.dart",
    "tool/perf_probe/src/installed_plugin_contract.dart",
    "test/tool/perf_probe/installed_plugin_probe_test.dart",
]
ROOT = Path.cwd().resolve()
OUT = Path(os.environ["ANDROID_STORE_SELF_OUTPUT"]).resolve()
assert OUT != ROOT and ROOT not in OUT.parents
OUT.mkdir(parents=True, exist_ok=False)
(OUT / "logs").mkdir()
os.environ.pop("GITHUB_TOKEN", None)
os.environ.pop("GH_TOKEN", None)
os.environ.pop("DIAGNOSTIC_TOKEN", None)
os.environ.pop("ACTIONS_RUNTIME_TOKEN", None)
os.environ.pop("ACTIONS_ID_TOKEN_REQUEST_TOKEN", None)
sys.dont_write_bytecode = True

report = {
    "scope": "Implementation self-check on exact draft source; not independent QA or native acceptance",
    "source": SOURCE,
    "sourceTree": SOURCE_TREE,
    "publicParent": PUBLIC_PARENT,
    "status": "running",
    "nativeExecution": "NOT_RUN",
    "independentQA": "REQUIRED",
    "publicationApproved": False,
    "commands": [],
    "formatted": [],
    "firstError": None,
    "secondaryErrors": [],
}
stage = "bind"
source_before = None
resolved_before = None

def sha(data):
    return hashlib.sha256(data).hexdigest()

def write_json(name, value):
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

def git(*args, cwd=ROOT):
    return subprocess.check_output(["git", *args], cwd=cwd, stderr=subprocess.PIPE, timeout=60).decode("utf-8").strip()

def tracked_snapshot(root):
    files = []
    raw = subprocess.check_output(["git", "ls-files", "-s", "-z"], cwd=root, timeout=60)
    for item in raw.split(b"\0"):
        if not item:
            continue
        header, name = item.split(b"\t", 1)
        mode, blob, index_stage = header.decode("ascii").split()
        assert index_stage == "0"
        path = root / os.fsdecode(name)
        data = os.fsencode(os.readlink(path)) if path.is_symlink() else path.read_bytes()
        files.append({"path": os.fsdecode(name), "mode": mode, "indexBlob": blob,
                      "bytes": len(data), "sha256": sha(data),
                      "diskMode": path.lstat().st_mode, "symlink": path.is_symlink()})
    return {
        "head": git("rev-parse", "HEAD", cwd=root),
        "tree": git("rev-parse", "HEAD^{tree}", cwd=root),
        "indexTree": git("write-tree", cwd=root),
        "status": git("status", "--porcelain=v1", "--untracked-files=all", cwd=root),
        "files": files,
    }

def error_record(error):
    return {"stage": stage, "type": type(error).__name__, "error": str(error),
            "traceback": traceback.format_exc()}

def record_failure(error):
    value = error_record(error)
    if report["firstError"] is None:
        report["firstError"] = value
    else:
        report["secondaryErrors"].append(value)

def export_log(name, path):
    data = path.read_bytes()
    value = {"name": name, "path": str(path.relative_to(OUT)),
             "bytes": len(data), "sha256": sha(data),
             "tail": data[-65536:].decode("utf-8", "replace")}
    if len(data) <= 2 * 1024 * 1024:
        value["encoding"] = "base64"
        value["data"] = base64.b64encode(data).decode("ascii")
    else:
        value["encoding"] = "full-artifact-and-tail"
    print("BEGIN_IMPL4428_RAW", flush=True)
    print(json.dumps(value, ensure_ascii=False), flush=True)
    print("END_IMPL4428_RAW", flush=True)
    return {key: value[key] for key in ("name", "path", "bytes", "sha256", "encoding")}

def command(name, args, timeout, *, env=None):
    row = {"name": name, "argv": args, "timeoutSeconds": timeout, "status": "running",
           "startedMonotonic": time.monotonic()}
    report["commands"].append(row)
    print(json.dumps({"commandStarted": name, "argv": args, "timeoutSeconds": timeout}), flush=True)
    stdout_path = OUT / "logs" / (name + ".stdout")
    stderr_path = OUT / "logs" / (name + ".stderr")
    command_error = None
    process = None
    try:
        with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
            process = subprocess.Popen(args, cwd=ROOT, env=env, stdout=stdout, stderr=stderr,
                                       start_new_session=True)
            row["pid"] = process.pid
            try:
                row["exitCode"] = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired as error:
                command_error = error
                row["timedOut"] = True
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
                finally:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                row["exitCode"] = process.wait(timeout=10)
            row["status"] = "passed" if command_error is None and row["exitCode"] == 0 else "failed"
    except BaseException as error:
        if command_error is None:
            command_error = error
        else:
            row.setdefault("cleanupErrors", []).append(str(error))
        row["status"] = "failed"
    finally:
        row["finishedMonotonic"] = time.monotonic()
        row["elapsedMs"] = (row["finishedMonotonic"] - row["startedMonotonic"]) * 1000
        row["streams"] = []
        for label, path in (("stdout", stdout_path), ("stderr", stderr_path)):
            if not path.exists():
                path.write_bytes(b"")
            try:
                row["streams"].append(export_log(name + "." + label, path))
            except BaseException as error:
                row.setdefault("evidenceErrors", []).append(str(error))
                if command_error is None:
                    command_error = error
        write_json("commands.json", report["commands"])
    if command_error is not None:
        raise command_error
    if row["exitCode"] != 0:
        raise RuntimeError(f"{name} exited {row['exitCode']}; full stdout/stderr retained and exported")
    return stdout_path.read_bytes()

def resolved_snapshot():
    config_path = ROOT / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text())
    by_name = {item["name"]: item for item in config["packages"]}
    assert by_name["otzaria"]["languageVersion"] == "3.12"
    package_roots = {}
    roots = {}
    for name, pin in GIT_PINS.items():
        entry = by_name[name]
        uri = urllib.parse.urlparse(urllib.parse.urljoin(config_path.as_uri(), entry["rootUri"]))
        assert uri.scheme == "file" and not uri.netloc
        package = Path(urllib.parse.unquote(uri.path)).resolve()
        root = Path(git("rev-parse", "--show-toplevel", cwd=package)).resolve()
        assert git("rev-parse", "HEAD", cwd=root) == pin, name
        package_roots[name] = {"root": str(root), "packageRoot": str(package), "head": pin}
        if str(root) not in roots:
            roots[str(root)] = tracked_snapshot(root)
            assert roots[str(root)]["status"] == "", name
    assert len(package_roots) == 19
    flutter = Path(shutil.which("flutter")).resolve()
    sdk_root = flutter.parent.parent
    sdk = tracked_snapshot(sdk_root)
    assert sdk["head"] == SDK_HEAD and sdk["status"] == ""
    return {
        "packageConfigBytes": len(config_path.read_bytes()),
        "packageConfigSha256": sha(config_path.read_bytes()),
        "languageVersion": by_name["otzaria"]["languageVersion"],
        "sdkRoot": str(sdk_root),
        "sdk": sdk,
        "gitPackages": package_roots,
        "gitRoots": roots,
    }

try:
    assert git("rev-parse", "HEAD^") == SOURCE
    assert git("rev-parse", SOURCE + "^{tree}") == SOURCE_TREE
    assert git("show", "-s", "--format=%P", SOURCE) == PUBLIC_PARENT
    assert set(git("diff", "--name-only", SOURCE, "HEAD").splitlines()) == QA_FILES
    assert git("show", "-s", "--format=%an <%ae>%n%cn <%ce>", SOURCE) == \
        "Y-Ploni <7353755@gmail.com>\nY-Ploni <7353755@gmail.com>"
    source_before = tracked_snapshot(ROOT)
    assert not source_before["status"]
    assert len(source_before["files"]) == 4200
    for row in MANIFEST:
        data = (ROOT / row["path"]).read_bytes()
        assert len(data) == row["bytes"] and sha(data) == row["sha256"], row["path"]
        assert hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest() == row["blob"]
        assert git("ls-files", "-s", "--", row["path"]).split()[0] == row["mode"]
    write_json("source-before.json", source_before)
    report["manifest"] = MANIFEST

    stage = "SDK identity"
    version = json.loads(command("flutter-version", ["flutter", "--version", "--machine"], 120))
    assert version["frameworkVersion"] == "3.47.7"
    assert version["dartSdkVersion"].startswith("3.13.5")
    assert version["frameworkRevision"] == SDK_HEAD
    report["flutterVersion"] = version

    stage = "strict dependency resolution"
    command("pub-get", ["flutter", "pub", "get", "--enforce-lockfile"], 900)
    assert tracked_snapshot(ROOT) == source_before
    assert 'sdk: ">=3.12.0 <4.0.0"' in (ROOT / "pubspec.yaml").read_text()
    options = (ROOT / "analysis_options.yaml").read_bytes()
    assert hashlib.sha1(b"blob " + str(len(options)).encode() + b"\0" + options).hexdigest() == \
        "167d246684ae7893489320d8946cc29f2ec40ab2"
    assert re.search(r"(?m)^formatter:\n  trailing_commas: preserve$", options.decode())
    resolved_before = resolved_snapshot()
    write_json("resolved-before.json", resolved_before)
    report["formatContext"] = {
        "sdkConstraint": ">=3.12.0 <4.0.0",
        "languageVersion": "3.12",
        "analysisOptionsBlob": "167d246684ae7893489320d8946cc29f2ec40ab2",
        "trailingCommas": "preserve",
        "sourceMode": "Original checkout paths and real package_config; --output=show only",
    }

    stage = "canonical formatter output"
    for index, path in enumerate(FORMAT_PATHS):
        before = (ROOT / path).read_bytes()
        formatted = command(f"format-{index}", ["dart", "format", "--output=show", "--summary=none", path], 120)
        assert (ROOT / path).read_bytes() == before, path
        target = OUT / "formatted" / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(formatted)
        record = {
            "path": path, "originalBytes": len(before), "originalSha256": sha(before),
            "bytes": len(formatted), "sha256": sha(formatted),
            "blob": hashlib.sha1(b"blob " + str(len(formatted)).encode() + b"\0" + formatted).hexdigest(),
            "alreadyCanonical": before == formatted,
            "encoding": "base64", "data": base64.b64encode(formatted).decode("ascii"),
        }
        report["formatted"].append({key: value for key, value in record.items() if key != "data"})
        print("BEGIN_IMPL4428_FORMATTED", flush=True)
        print(json.dumps(record), flush=True)
        print("END_IMPL4428_FORMATTED", flush=True)

    stage = "full analyze"
    command("flutter-analyze", ["flutter", "analyze", "--no-pub"], 1200)

    stage = "pinned Store source"
    store_source = OUT / "store-source"
    command("prepare-store", ["python3", "tool/perf_probe/prepare_installed_plugin_source.py",
                              "--output", str(store_source)], 300)
    prepared = {}
    for name in ("manifest.json", "index.html", "restore-state.js", "i18n/en.js", "background.html"):
        data = (store_source / name).read_bytes()
        prepared[name] = {"bytes": len(data), "sha256": sha(data)}
    report["preparedStore"] = prepared
    child_env = dict(os.environ, INSTALLED_PROBE_STORE_SOURCE=str(store_source))

    stage = "actual Node Store regressions"
    command("node-store-tests", ["node", "--test", "tool/perf_probe/test_installed_plugin_store.mjs"],
            180, env=child_env)

    stage = "actual Dart contract regressions"
    command("flutter-store-tests", ["flutter", "test", "--no-pub", "--concurrency=1", "--reporter", "expanded",
                                    "test/tool/perf_probe/installed_plugin_probe_test.dart"],
            1200, env=child_env)
    report["status"] = "IMPLEMENTATION_SELF_CHECK_PASSED"
except BaseException as error:
    record_failure(error)
    report["status"] = "FAILED"
finally:
    stage = "source and index preservation"
    try:
        after = tracked_snapshot(ROOT)
        write_json("source-after.json", after)
        report["sourceAndIndexUnchanged"] = source_before is not None and after == source_before
        assert report["sourceAndIndexUnchanged"], "Tracked source or index changed; not restored or hidden"
    except BaseException as error:
        record_failure(error)
        report["status"] = "FAILED"
    if resolved_before is not None:
        stage = "SDK and Git dependency preservation"
        try:
            resolved_after = resolved_snapshot()
            write_json("resolved-after.json", resolved_after)
            report["sdkAnd19GitPackagesUnchanged"] = resolved_before == resolved_after
            assert report["sdkAnd19GitPackagesUnchanged"], "Resolved SDK or Git dependency changed"
        except BaseException as error:
            record_failure(error)
            report["status"] = "FAILED"
    report["canonicalSourceStillRequired"] = any(not row["alreadyCanonical"] for row in report["formatted"])
    write_json("implementation-self-check.json", report)
    print("BEGIN_IMPL4428_SELF_CHECK", flush=True)
    print(json.dumps(report, ensure_ascii=False), flush=True)
    print("END_IMPL4428_SELF_CHECK", flush=True)

raise SystemExit(0 if report["status"] == "IMPLEMENTATION_SELF_CHECK_PASSED" else 1)
