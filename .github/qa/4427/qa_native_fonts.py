#!/usr/bin/env python3
"""Independent QA of the immutable #4427 candidate; artifact bytes are data only."""

import base64
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import math
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys
import tempfile
import traceback
import urllib.parse
import urllib.request
from unittest import mock
import zipfile

ROOT = Path.cwd().resolve()
OUTPUT = Path(os.environ["QA_FONT_OUTPUT"])
OUTPUT.mkdir(parents=True, exist_ok=False)
BASE = "326d693129fb36a0d8093f6107c058c1861370ac"
SOURCE = "5dcd64785d2154df33faf0def6f0f30c20f04c53"
SOURCE_TREE = "6e76b5c0c2f9f7549ea98f60a39e257315d7bd21"
EXPECTED_QA_FILES = {".github/workflows/qa_4427_independent.yml", ".github/qa/4427/qa_native_fonts.py"}
FLUTTER = "abaf9c523780a608bd46686fd5e53740a07077f8"
ENGINE = "deb287481e3ce9468f3434937ced4240a70539ca"
WEBVIEW = "c709de98711cf34350c48df4c75e24d0879d5876"
HOOK_HASH = "53b75db342d0332ae703c389562adf65a04d6127bd1ff05edaef0dde7b020097"
REPO = "Otzaria/otzaria"
GATES = []
COMMANDS = []
DETAILS = {}

SOURCE_FILES = {
  "tool/perf_probe/validate_ios_plugin_fonts.py": {
    "blob": "371060c2636c90da6f58f1ebe25818c602c5bf28",
    "sha256": "58081242bb0f8eee567fdc9c149cb43b8f94443d5087d2e2582b24369f468288",
    "bytes": 31172,
    "mode": "100644"
  },
  "integration_test/support/apple_font_probe_view.dart": {
    "blob": "40afc331e2bab483f94bfb80eaa16ede0b0c7ca8",
    "sha256": "c425da1db13672cec56ab035bf0dbf9bc0b81c0cdaffc5fcd95198c1be217ead",
    "bytes": 19438,
    "mode": "100644"
  },
  "tool/perf_probe/test_ios_plugin_fonts_report.py": {
    "blob": "3233184a26011b5d4d2c390ae132b81025af8003",
    "sha256": "21063c56e61bb853ddc9daebc2eb12b9816718d260237a1c7519e7f419c41c6f",
    "bytes": 33513,
    "mode": "100644"
  },
  "tool/perf_probe/run_ios_plugin_fonts.py": {
    "blob": "c9796cd4fe574fc654878e443895f4fd4a79e8aa",
    "sha256": "e7f80139ec72973371c566be2ec6a2459d1b9b641b659b8138f9fc73827de5c1",
    "bytes": 24115,
    "mode": "100644"
  },
  "tool/perf_probe/test_ios_plugin_fonts_runner.py": {
    "blob": "1d14e23df93dda55349ab2a651fc02790f277a2b",
    "sha256": "6926799a1ac260148a56d4a08d121c52a6b67990b2342d24dcef8d3e52de1444",
    "bytes": 42453,
    "mode": "100644"
  },
  "tool/perf_probe/test_macos_plugin_fonts.mjs": {
    "blob": "9f99d52b4ba83c90f56874c8cc8201fc451a314e",
    "sha256": "99b0adf721538a2013e79dfa2419c3ccac3e53a702b8ea7e955802fed8e4b1c0",
    "bytes": 19085,
    "mode": "100644"
  },
  "ios/Runner.xcodeproj/project.pbxproj": {
    "blob": "19aa1332b062c2bf5dbbe81d3e4b7e979a886b03",
    "sha256": "353f66335b50badad0b2697f59a526ab108483b37c4d0d8a326af5fda9437059",
    "bytes": 32682,
    "mode": "100644"
  },
  "ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme": {
    "blob": "d795332e1b7b6fbee70c8fedf32397546ece6492",
    "sha256": "bd8280840637379c0dfd9384aa3ef7d10eee7476b05ccfc2b679edfc763ca021",
    "bytes": 4567,
    "mode": "100644"
  }
}

def digest(data):
    return hashlib.sha256(data).hexdigest()

def git_blob(data):
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()

def save(name, data):
    path = OUTPUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")

def git(*args, cwd=ROOT):
    return subprocess.check_output(["git", *args], cwd=cwd, stderr=subprocess.PIPE).decode("utf-8").strip()

def command(label, args, *, cwd=ROOT, timeout=900, check=True):
    # The Actions API token is needed only by the data downloader, never by children.
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    env.pop("GH_TOKEN", None)
    target = OUTPUT / (label + ".log")
    with target.open("wb") as stream:
        result = subprocess.run(args, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    record = {"label": label, "command": args, "cwd": str(cwd), "exitCode": result.returncode,
              "log": target.name, "sha256": digest(target.read_bytes())}
    COMMANDS.append(record)
    save("commands.json", COMMANDS)
    if check and result.returncode != 0:
        raise AssertionError(label + " failed with exit " + str(result.returncode))
    return result.returncode

def gate(name, operation):
    try:
        value = operation()
        GATES.append({"name": name, "status": "passed", "result": value})
        return value
    except Exception as error:
        failure = {"name": name, "status": "failed", "type": type(error).__name__, "error": str(error)}
        GATES.append(failure)
        (OUTPUT / (name + "-traceback.txt")).write_text(traceback.format_exc())
        return None
    finally:
        save("gates.json", GATES)

def source_bound():
    assert git("rev-parse", SOURCE + "^{tree}") == SOURCE_TREE
    assert git("rev-parse", SOURCE + "^") == BASE
    assert set(git("diff", "--name-only", SOURCE, "HEAD").splitlines()) == EXPECTED_QA_FILES
    for path, expected in SOURCE_FILES.items():
        data = (ROOT / path).read_bytes()
        assert len(data) == expected["bytes"] and digest(data) == expected["sha256"], path
        assert git_blob(data) == expected["blob"], path
        entry = git("ls-tree", SOURCE, "--", path).split()
        assert entry[:3] == [expected["mode"], "blob", expected["blob"]], path
    assert git("status", "--porcelain=v1", "--untracked-files=all") == ""
    return {"qaHead": git("rev-parse", "HEAD"), "qaTree": git("rev-parse", "HEAD^{tree}"),
            "source": SOURCE, "sourceTree": SOURCE_TREE, "base": BASE, "files": len(SOURCE_FILES)}

def tracked_snapshot(root):
    paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).split(b"\0")
    files = []
    for raw in paths:
        if not raw:
            continue
        name = raw.decode("utf-8")
        path = root / name
        mode = path.lstat().st_mode
        data = os.readlink(path).encode("utf-8") if stat.S_ISLNK(mode) else path.read_bytes()
        files.append({"path": name, "mode": stat.S_IMODE(mode), "kind": "symlink" if stat.S_ISLNK(mode) else "file",
                      "bytes": len(data), "sha256": digest(data)})
    result = {"root": str(root), "head": git("rev-parse", "HEAD", cwd=root),
              "tree": git("rev-parse", "HEAD^{tree}", cwd=root),
              "status": git("status", "--porcelain=v1", "--untracked-files=all", cwd=root),
              "files": files}
    assert result["status"] == "", (str(root), result["status"])
    return result

def load_json(path):
    def bad(value):
        raise ValueError("Non-JSON number " + value)
    return json.loads(path.read_text(encoding="utf-8"), parse_constant=bad)

def snapshot_roots():
    sdk = Path(shutil.which("flutter")).resolve().parents[1]
    config_path = ROOT / ".dart_tool/package_config.json"
    config = load_json(config_path)
    roots = {str(ROOT): ROOT, str(sdk): sdk}
    packages = {}
    for package in config["packages"]:
        url = urllib.parse.urlparse(urllib.parse.urljoin(config_path.as_uri(), package["rootUri"]))
        assert url.scheme == "file"
        directory = Path(urllib.parse.unquote(url.path)).resolve()
        answer = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=directory,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if answer.returncode == 0:
            top = Path(answer.stdout.strip()).resolve()
            roots[str(top)] = top
            packages[package["name"]] = str(top)
        else:
            assert answer.returncode == 128 and "not a git repository" in answer.stderr.lower(), package["name"]
    snapshots = {name: tracked_snapshot(path) for name, path in sorted(roots.items())}
    assert snapshots[str(sdk)]["head"] == FLUTTER
    from validate_ios_plugin_fonts import NATIVE_PACKAGES, lock_pin
    lock = (ROOT / "pubspec.lock").read_text()
    for name in NATIVE_PACKAGES:
        pin = lock_pin(lock, name)
        expected = "2da23091237ed0f0a612de3b2d18cfc99d8b7d2a" if name == "otzaria_search_engine" else WEBVIEW
        assert pin == expected
        assert name in packages and snapshots[packages[name]]["head"] == pin, name
    return {"packages": packages, "repositories": snapshots}

def toolchain():
    command("flutter-version", ["flutter", "--version", "--machine"])
    info = load_json(OUTPUT / "flutter-version.log")
    assert info["frameworkVersion"] == "3.47.7" and info["frameworkRevision"] == FLUTTER
    assert info["engineRevision"] == ENGINE and info["dartSdkVersion"].split()[0] == "3.13.5"
    before = tracked_snapshot(ROOT)
    command("strict-pub", ["flutter", "pub", "get", "--enforce-lockfile"], timeout=900)
    assert tracked_snapshot(ROOT) == before
    return info

def original_hook():
    before = source_bound()
    index_tree = git("write-tree")
    command("install-original-hook", ["dart", "run", "tool/install_git_hooks.dart"])
    path = Path(git("rev-parse", "--git-path", "hooks/pre-commit"))
    if not path.is_absolute():
        path = ROOT / path
    assert digest(path.read_bytes()) == HOOK_HASH
    assert os.access(path, os.X_OK)
    original_head = git("rev-parse", "HEAD")
    errors = []
    try:
        git("reset", "--soft", BASE)
        staged = git("diff", "--cached", "--name-only").splitlines()
        assert "integration_test/support/apple_font_probe_view.dart" in staged
        assert any(name.endswith(".dart") for name in staged)
        save("hook-staged.json", {"headDuringHook": git("rev-parse", "HEAD"), "indexTree": index_tree, "paths": staged})
        code = command("original-hook", [str(path)], timeout=1200, check=False)
        if code != 0:
            errors.append("Original hook exit " + str(code))
        if git("write-tree") != index_tree:
            errors.append("Original hook changed staged candidate bytes")
        if git("diff", "--name-only"):
            errors.append("Original hook changed working bytes")
        (OUTPUT / "hook-index.diff").write_text(git("diff", "--cached", original_head, "--"))
        (OUTPUT / "hook-working.diff").write_text(git("diff", "--"))
    except Exception as error:
        errors.append(type(error).__name__ + ": " + str(error))
    finally:
        try:
            # Restores only the detached HEAD; never hide index/worktree changes.
            git("reset", "--soft", original_head)
        except Exception as error:
            errors.append("HEAD restoration: " + type(error).__name__ + ": " + str(error))
    assert not errors, errors
    assert source_bound() == before and git("write-tree") == index_tree
    return {"originalHookSha256": HOOK_HASH, "nonemptyDartDelta": True, "unchangedIndexAndSource": True}

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        result = super().redirect_request(req, fp, code, msg, headers, newurl)
        if result is not None and urllib.parse.urlsplit(newurl).netloc != urllib.parse.urlsplit(req.full_url).netloc:
            result.remove_header("Authorization")
        if urllib.parse.urlsplit(newurl).scheme != "https":
            raise RuntimeError("Non-HTTPS artifact redirect")
        return result

def api_read(suffix, binary=False):
    request = urllib.request.Request("https://api.github.com/repos/" + REPO + suffix, headers={
        "Authorization": "Bearer " + os.environ["GH_TOKEN"],
        "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"})
    with urllib.request.build_opener(SafeRedirect()).open(request, timeout=90) as response:
        raw = response.read(64 * 1024 * 1024 + 1)
    assert len(raw) <= 64 * 1024 * 1024
    return raw if binary else json.loads(raw)

ARTIFACTS = [
    (1, 13551143009, 2620792, "767733aacadb332af4a5600095cf2db64bb4421d2a44adfcb059ee9e870015e9",
     "5549994f8e5d3f6379c2e15fa2574ca4d08e4c71ec9e1f495c6b829573b4fcbb"),
    (5, 13551950329, 9624252, "b243bf40978ff2b191e301551c38940959b20dd03846fd2ef8b1e6590a05242c",
     "26ac88605f3987a8026dbc4a51e852e9f4bda71f45e161e1fbf3cc72ab0f5dbe"),
    (10, 13551657528, 19263939, "2f73fc5e216057cea9148bf3e5dbbd68dcac6f5b6d92e975600ad10bed1d41ff",
     "c239f15926b36339cb949c0708cd416d2f56b74e69953b25ce9353e01ac2652f"),
]

def retained_hashes(root):
    return {str(path.relative_to(root)): digest(path.read_bytes()) for path in sorted(root.rglob("*")) if path.is_file()}

def original_reports():
    import validate_ios_plugin_fonts as validator
    replay_root = OUTPUT / "native-replay"
    replay_root.mkdir()
    old_source = subprocess.check_output(["git", "show", BASE + ":tool/perf_probe/validate_ios_plugin_fonts.py"])
    assert git_blob(old_source) == "e73362f1dd5bcd0a2567500d2c96fa4184de9eee"
    assert digest(old_source) == "012533d230a7d52560302605c989271e6bdf867cc3b673ed1d6b6ee48a2d6709"
    old_file = OUTPUT / "old_validator.py"
    old_file.write_bytes(old_source)
    spec = importlib.util.spec_from_file_location("old_font_validator", old_file)
    old = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(old)
    receipts, loaded = [], {}
    for count, artifact_id, expected_size, expected_sha, report_sha in ARTIFACTS:
        metadata = api_read("/actions/artifacts/" + str(artifact_id))
        assert metadata["id"] == artifact_id and not metadata["expired"]
        assert metadata["size_in_bytes"] == expected_size and metadata["digest"] == "sha256:" + expected_sha
        assert metadata["workflow_run"]["id"] == 42315077985 and metadata["workflow_run"]["head_sha"] == BASE
        archive = api_read("/actions/artifacts/" + str(artifact_id) + "/zip", binary=True)
        assert len(archive) == expected_size and digest(archive) == expected_sha
        path = replay_root / (str(count) + ".zip")
        path.write_bytes(archive)
        root = replay_root / str(count)
        root.mkdir()
        names = set()
        with zipfile.ZipFile(path) as zipped:
            assert len(zipped.infolist()) < 2000 and sum(z.file_size for z in zipped.infolist()) < 512 * 1024 * 1024
            for info in zipped.infolist():
                name = PurePosixPath(info.filename)
                assert not name.is_absolute() and ".." not in name.parts and "\\" not in info.filename
                assert info.filename not in names and not stat.S_ISLNK(info.external_attr >> 16)
                names.add(info.filename)
                if info.is_dir():
                    continue
                destination = root.joinpath(*name.parts)
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(zipped.read(info))
        hashes = retained_hashes(root)
        reports, environments = list(root.rglob("report.json")), list(root.rglob("environment.json"))
        assert len(reports) == len(environments) == 1
        report, envpath = reports[0], environments[0]
        assert digest(report.read_bytes()) == report_sha
        envelope = validator.read_json(report)
        environment = validator.read_json(envpath)
        semantics = validator.validate(envelope)
        try:
            old.validate(copy.deepcopy(envelope))
        except ValueError as error:
            assert str(error) == "SDK boot/theme/visibility failed", str(error)
        else:
            raise AssertionError("Old validator unexpectedly accepted original bridge floats")
        try:
            validator.validate_artifacts(report, environment, envpath.parent)
        except ValueError as error:
            rejected = str(error)
        else:
            raise AssertionError("Original failed source run was retroactively accepted")
        assert environment["captureStatus"] == "failed"
        assert {line.strip() for line in environment["sourceStatusAfter"].splitlines()} == {
            "M ios/Runner.xcodeproj/project.pbxproj",
            "M ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme"}
        # Validate retained screenshot bytes even though full original acceptance is rejected earlier.
        raw = validator.read_json(report.parent / "framework-response.json")
        assert raw["result"] == "true" and raw["failureDetails"] == []
        normalized = copy.deepcopy(raw["data"])
        pngs = 0
        for case in envelope["data"]["iosFontProbe"]["cases"]:
            original = next(c for c in normalized["iosFontProbe"]["cases"] if c["id"] == case["id"])
            for view in case["views"]:
                if case["scenario"] == "style-src-none":
                    continue
                old_view = next(v for v in original["views"] if v["index"] == view["index"])
                png = (report.parent / view["screenshot"]).read_bytes()
                validator.validate_png(png)
                assert png == base64.b64decode(old_view.pop("screenshotBase64"), validate=True)
                old_view["screenshot"] = view["screenshot"]
                pngs += 1
        assert normalized == envelope["data"]
        assert pngs == 12 * count
        assert retained_hashes(root) == hashes
        receipts.append({"views": count, "artifact": artifact_id, "archiveBytes": expected_size,
                         "archiveSha256": expected_sha, "reportSha256": report_sha,
                         "reportSemantics": "passed", "oldValidator": "rejected-boot-float",
                         "fullOriginalAcceptance": "rejected", "rejection": rejected,
                         "nativePngBytesVerified": pngs, "unchangedFiles": len(hashes),
                         "fileHashes": hashes})
        loaded[count] = envelope
    save("native-original-replay.json", receipts)
    environment = dict(os.environ, PYTHONPATH=str(ROOT / "tool/perf_probe"),
                       IOS_FONT_NATIVE_REPLAY_ROOT=str(replay_root), PYTHONDONTWRITEBYTECODE="1")
    environment.pop("GH_TOKEN", None)
    with (OUTPUT / "candidate-opt-in-replay.log").open("wb") as stream:
        completed = subprocess.run([sys.executable, "-m", "unittest",
            "test_ios_plugin_fonts_report.NativeReportReplayTests", "-v"],
            cwd=ROOT, env=environment, stdout=stream, stderr=subprocess.STDOUT, timeout=180)
    assert completed.returncode == 0
    for receipt in receipts:
        assert retained_hashes(replay_root / str(receipt["views"])) == receipt["fileHashes"]
    DETAILS["rawReplay"] = [{key: value for key, value in receipt.items() if key != "fileHashes"} for receipt in receipts]
    DETAILS["originalOneViewEnvelope"] = loaded[1]
    return DETAILS["rawReplay"]

def numeric_controls():
    import validate_ios_plugin_fonts as V
    assert "originalOneViewEnvelope" in DETAILS, "Original replay must pass before independent mutations"
    original = DETAILS["originalOneViewEnvelope"]
    events = []
    def locate(envelope):
        report = envelope["data"]["iosFontProbe"]
        case = next(c for c in report["cases"] if c["id"] == "file-production-policy-data-normal")
        view = case["views"][0]
        return report, case, view
    def mutation(name, target, field, value, accepted=False):
        envelope = copy.deepcopy(original)
        report, case, view = locate(envelope)
        target(report, case, view)[field] = value
        try:
            V.validate(envelope)
        except (ValueError, KeyError, TypeError) as error:
            assert not accepted, (name, repr(value), str(error))
            outcome = "rejected"
        else:
            assert accepted, (name, repr(value), "accepted malformed input")
            outcome = "accepted"
        events.append({"name": name, "input": repr(value), "expected": outcome})
    report, case, view = locate(original)
    fields = [
        ("bootCount", lambda r, c, v: v["rendering"], "bootCount", 1.0, [True, False, 0, 2, 1.25, "1", None, float("nan"), float("inf")]),
        ("inkPixels", lambda r, c, v: v["rendering"]["samples"][0], "inkPixels", 52000.0,
         [True, False, 0, -1, 52001, 1.25, "1", None, float("nan"), float("inf")]),
        ("fallbackInk", lambda r, c, v: v["rendering"]["fallbackControl"], "inkPixels", 1.0,
         [True, False, 0, 52001, 3.5, "1", float("nan"), float("inf")]),
        ("droppedEvents", lambda r, c, v: v["rendering"]["renderingProgress"], "droppedEvents", 0.0,
         [False, True, -1, 1, 0.25, "0", None, float("nan")]),
        ("traceStart", lambda r, c, v: v["rendering"]["renderingProgress"], "startedAtEpochMilliseconds",
         float(view["rendering"]["renderingProgress"]["startedAtEpochMilliseconds"]),
         [True, 0, 2 ** 53, float(2 ** 53), view["renderingRequestedAtEpochMilliseconds"] - 1,
          view["rendering"]["renderingProgress"]["startedAtEpochMilliseconds"] + 0.5, "1", float("nan"), float("inf")]),
        ("navigationBoot", lambda r, c, v: c["navigation"]["newDocument"], "bootCount", -0.0,
         [False, True, -1, 1, 0.5, "0", None, float("nan"), float("inf")]),
        ("droppedViolations", lambda r, c, v: v["policyDiagnostics"], "droppedViolations", 0.0,
         [False, True, -1, 0.5, 2 ** 53, "0", None, float("nan")]),
    ]
    for name, target, field, good, invalid in fields:
        mutation(name + "-integral-float", target, field, good, accepted=True)
        for value in invalid:
            mutation(name, target, field, value)
    strict = [
        ("reportSchema", lambda r, c, v: r, "schemaVersion", 1.0),
        ("instances", lambda r, c, v: r, "instances", 1.0),
        ("viewIndex", lambda r, c, v: v, "index", 0.0),
        ("dartDispatchEpoch", lambda r, c, v: v, "renderingRequestedAtEpochMilliseconds", float(view["renderingRequestedAtEpochMilliseconds"])),
        ("operationStart", lambda r, c, v: v["operations"][0], "startedMicroseconds", float(view["operations"][0]["startedMicroseconds"])),
        ("operationResponse", lambda r, c, v: v["operations"][0], "responseMicroseconds", float(view["operations"][0]["responseMicroseconds"])),
        ("bootPayloadBytes", lambda r, c, v: v, "bootJavascriptUtf8Bytes", float(view["bootJavascriptUtf8Bytes"])),
        ("preparePayloadBytes", lambda r, c, v: v["preparation"], "javascriptUtf8Bytes", float(view["preparation"]["javascriptUtf8Bytes"])),
        ("nativeReadyTime", lambda r, c, v: v, "fontReadyFromViewCreationMicroseconds", float(view["fontReadyFromViewCreationMicroseconds"])),
    ]
    for name, target, field, value in strict:
        mutation(name + "-must-stay-Dart-int", target, field, value)
    for value in [False, True, 0, -1, float("nan"), float("inf"), "2"]:
        mutation("viewportDpr", lambda r, c, v: v["rendering"]["viewport"], "dpr", value)
    mutation("viewportDpr-positive-fraction", lambda r, c, v: v["rendering"]["viewport"], "dpr", 1.5, accepted=True)
    trace = view["rendering"]["renderingProgress"]
    mutation("traceEnd-mismatch", lambda r, c, v: v["rendering"]["renderingProgress"], "elapsedMilliseconds", trace["elapsedMilliseconds"] + 1)
    mutation("traceEnd-bool", lambda r, c, v: v["rendering"]["renderingProgress"], "elapsedMilliseconds", True)
    for good in [0, -0.0, 1.0, 2 ** 53 - 1, float(2 ** 53 - 1)]:
        assert V.javascript_integer(good)
    for bad in [False, True, -1, 0.5, 2 ** 53, 10 ** 400, float("nan"), float("inf"), "1", None]:
        assert not V.javascript_integer(bad), repr(bad)
    save("independent-numeric-controls.json", events)
    return {"source": "Deep copies of the exact 1-view original native report; original files unchanged",
            "mutations": len(events), "directBoundaryControls": 15,
            "accepted": sum(e["expected"] == "accepted" for e in events),
            "rejected": sum(e["expected"] == "rejected" for e in events)}

def io_controls():
    import run_ios_plugin_fonts as R
    real_commands = R.Commands
    real_open, real_read_text, real_read_bytes = Path.open, Path.read_text, Path.read_bytes
    controls = []
    for number, (driver_exit, fault, fail_pods, fail_shutdown_close) in enumerate([
        (0, None, False, False),
        (31, None, False, False),
        (31, "open", True, False),
        (0, "read", False, False),
        (31, "close", False, False),
        (31, "hash", False, True),
    ]):
        work = OUTPUT / ("io-control-" + str(number))
        repository, evidence = work / "repo", work / "evidence"
        repository.mkdir(parents=True)
        (repository / "ios").mkdir()
        (repository / "project.pbxproj").write_text("original project\n")
        (repository / "Runner.xcscheme").write_text("original scheme\n")
        (repository / "pubspec.lock").write_text("controlled lock\n")
        (repository / "ios/Podfile.lock").write_text("controlled CocoaPods lock\n")
        git("init", "-q", cwd=repository)
        git("add", ".", cwd=repository)
        git("-c", "user.name=Y-PLONI", "-c", "user.email=7353755@gmail.com",
            "commit", "-q", "-m", "Independent QA controlled source baseline", cwd=repository)
        head = git("rev-parse", "HEAD", cwd=repository)
        before_source = {name: (repository / name).read_bytes() for name in ("project.pbxproj", "Runner.xcscheme")}
        labels = []
        diff_path = evidence / "source-diffAfter.log"
        shutdown_path = evidence / "simulator-shutdown.log"

        def capture(commands, environment, *, after=False):
            suffix = "After" if after else ""
            environment["sourceStatus" + suffix] = git("status", "--porcelain", cwd=repository)
            environment["sourceCommit" + suffix] = git("rev-parse", "HEAD", cwd=repository)
            if not after:
                environment["nativeSources"] = {"controlled": {"head": head}}
                environment["lockSha256"] = digest((repository / "pubspec.lock").read_bytes())
            if after and environment["sourceStatusAfter"]:
                raise ValueError("Independent QA observed actual staged/unstaged Git source changes")

        class RoutedCommands(real_commands):
            def run(self, label, args, timeout=120, **kwargs):
                labels.append(label)
                kwargs["cwd"] = repository
                kwargs["env"] = dict(kwargs.get("env") or os.environ)
                kwargs["env"].pop("GH_TOKEN", None)
                if label == "source-diffAfter":
                    return super().run(label, args, timeout, **kwargs)
                if label == "flutter-drive":
                    program = (
                        "from pathlib import Path; import subprocess,sys;"
                        "Path('project.pbxproj').write_text('staged migration\\n');"
                        "subprocess.run(['git','add','project.pbxproj'],check=True);"
                        "Path('Runner.xcscheme').write_text('working migration\\n');"
                    )
                    if fault == "open":
                        program += "Path(sys.argv[1]).mkdir();"
                    program += "sys.exit(int(sys.argv[2]))"
                    mapped = [sys.executable, "-c", program, str(diff_path), str(driver_exit)]
                else:
                    value = "controlled " + label
                    if label == "simulator-devices":
                        value = json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-4": [
                            {"name": "iPhone independent control", "udid": "OWNED-QA-SIMULATOR",
                             "isAvailable": True, "state": "Shutdown"}]}})
                    elif label == "simulator-runtimes":
                        value = json.dumps({"runtimes": [{"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-4",
                            "isAvailable": True, "version": "26.4", "buildversion": "controlled"}]})
                    mapped = [sys.executable, "-c", "import sys; print(sys.argv[1])", value]
                return super().run(label, mapped, timeout, **kwargs)

        class CloseFault:
            def __init__(self, stream):
                self.stream = stream
            def fileno(self):
                return self.stream.fileno()
            def close(self):
                self.stream.close()
                raise OSError("Independent QA injected close failure")
            def __getattr__(self, name):
                return getattr(self.stream, name)

        def opening(path, *args, **kwargs):
            stream = real_open(path, *args, **kwargs)
            mode = args[0] if args else kwargs.get("mode", "r")
            if "w" in mode and ((fault == "close" and path == diff_path) or
                                (fail_shutdown_close and path == shutdown_path)):
                return CloseFault(stream)
            return stream

        def reading_text(path, *args, **kwargs):
            if fault == "read" and path == diff_path:
                raise OSError("Independent QA injected diff log read failure")
            return real_read_text(path, *args, **kwargs)

        def reading_bytes(path, *args, **kwargs):
            if fault == "hash" and path == diff_path:
                raise OSError("Independent QA injected diff digest read failure")
            return real_read_bytes(path, *args, **kwargs)

        original_copy = shutil.copyfile
        def copying(src, dst, *args, **kwargs):
            if fail_pods and Path(src) == repository / "ios/Podfile.lock":
                raise OSError("Independent QA injected Podfile retention failure")
            return original_copy(src, dst, *args, **kwargs)

        stdout, stderr = io.StringIO(), io.StringIO()
        with mock.patch.object(R, "ROOT", repository), mock.patch.object(R, "Commands", RoutedCommands), \
             mock.patch.object(R, "capture_sources", capture), mock.patch.object(R.platform, "system", return_value="Darwin"), \
             mock.patch.object(R, "validate_artifacts") as validation, \
             mock.patch.object(Path, "open", opening), mock.patch.object(Path, "read_text", reading_text), \
             mock.patch.object(Path, "read_bytes", reading_bytes), mock.patch.object(R.shutil, "copyfile", copying), \
             contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = R.run_probe(["--instances", "1", "--output", str(evidence)])
            assert validation.call_count == 0
        (work / "stdout.txt").write_text(stdout.getvalue())
        (work / "stderr.txt").write_text(stderr.getvalue())
        environment = load_json(evidence / "environment.json")
        comparison = load_json(evidence / "comparison.json")
        assert code == 1 and comparison["status"] == "invalid-or-not-run"
        assert environment["captureStatus"] == environment["runStatus"] == "failed"
        assert environment["drive"]["returncode"] == driver_exit
        assert environment["primaryFailure"]["step"] == ("driver" if driver_exit else "sources-after")
        if driver_exit:
            assert "exit code 31" in environment["error"]
        else:
            assert "actual staged/unstaged" in environment["error"]
        assert environment["simulatorOwnership"]["owned"] is True
        assert environment["simulatorOwnership"]["released"] is True
        assert labels.count("source-diffAfter") == labels.count("simulator-shutdown") == 1
        assert labels.index("source-diffAfter") < labels.index("simulator-shutdown")
        assert all(record["groupDrained"] for record in environment["commandRecords"])
        assert all(not R.group_alive(record["pid"]) for record in environment["commandRecords"] if record.get("started"))
        assert git("rev-parse", "HEAD", cwd=repository) == head
        assert (repository / "project.pbxproj").read_text() == "staged migration\n"
        assert (repository / "Runner.xcscheme").read_text() == "working migration\n"
        assert before_source["project.pbxproj"] != (repository / "project.pbxproj").read_bytes()
        assert git("diff", "--cached", "--name-only", cwd=repository) == "project.pbxproj"
        assert git("diff", "--name-only", cwd=repository) == "Runner.xcscheme"
        secondary = [entry["step"] for entry in environment["secondaryErrors"]]
        if fault:
            assert "source-diff" in secondary and "sourceDiffAfter" not in environment
        else:
            receipt = environment["sourceDiffAfter"]
            raw = (evidence / receipt["file"]).read_bytes()
            assert b"+staged migration" in raw and b"+working migration" in raw
            assert receipt["sha256"] == digest(raw) and receipt["baseCommit"] == head
        if fail_pods:
            assert "podfile-lock" in secondary
        else:
            assert (evidence / "Podfile.lock").read_bytes() == (repository / "ios/Podfile.lock").read_bytes()
        if fail_shutdown_close:
            assert "simulator-shutdown" in secondary
        item = {"driverExit": driver_exit, "diffFault": fault, "podFailure": fail_pods,
                "shutdownEvidenceFailure": fail_shutdown_close, "primary": environment["primaryFailure"],
                "secondarySteps": secondary, "ownedSimulatorReleased": True,
                "realChildrenDrained": sum(record.get("started") is True for record in environment["commandRecords"]),
                "actualGitChangesPreserved": True, "validationCalled": False, "exit": code}
        controls.append(item)
    class NoCommand:
        def run(self, *args, **kwargs):
            raise AssertionError("A clean or cancelled source path started a diagnostic command")
    for environment in ({"sourceStatusAfter": ""}, {"sourceStatusAfter": " M tracked", "cancelled": True}):
        R.retain_source_diff(NoCommand(), environment)
    save("independent-io-controls.json", controls)
    return {"scope": "Controlled real subprocesses/filesystem/Git; no native Simulator claim",
            "compoundControls": controls, "cleanOrCancelledSkipControls": 2}

def merge_proofs():
    before = api_read("/pulls?state=open&per_page=100")
    assert len(before) < 100, "Pagination required for open PR collection"
    snapshots = []
    for pull in before:
        files, page = [], 1
        while True:
            part = api_read("/pulls/" + str(pull["number"]) + "/files?per_page=100&page=" + str(page))
            files.extend(item["filename"] for item in part)
            if len(part) < 100:
                break
            page += 1
            assert page < 50
        snapshots.append({"number": pull["number"], "head": pull["head"]["sha"], "base": pull["base"]["sha"],
                          "baseRef": pull["base"]["ref"], "files": files})
    after = api_read("/pulls?state=open&per_page=100")
    identify = lambda rows: sorted((p["number"], p["head"]["sha"], p["base"]["sha"]) for p in rows)
    assert identify(before) == identify(after), "PR heads/bases changed while collecting overlap map"
    own = next(p for p in snapshots if p["number"] == 4427)
    assert own["head"] == BASE
    dev = api_read("/branches/dev")["commit"]["sha"]
    scope = set(git("diff", "--name-only", own["base"], SOURCE).splitlines())
    targets = [{"label": "dev", "sha": dev}]
    targets.extend({"label": "PR-" + str(p["number"]), "sha": p["head"],
                    "overlap": sorted(scope.intersection(p["files"]))}
                   for p in snapshots if p["number"] != 4427 and scope.intersection(p["files"]))
    apple = next(p for p in snapshots if p["number"] == 4425)
    targets.extend([
        {"label": "Apple-public-4425", "sha": apple["head"]},
        {"label": "Apple-candidate-4425", "sha": "b122cb1abcccc2305df18ddf18ce1723d1124f30",
         "scope": "Concurrent frozen candidate contains the identical two SwiftPM migration blobs"},
    ])
    save("current-open-pr-map.json", {"count": len(snapshots), "stableDuringReads": True, "pulls": snapshots,
                                    "candidateScope": sorted(scope), "targets": targets})
    results = []
    for target in targets:
        sha = target["sha"]
        probe = subprocess.run(["git", "cat-file", "-e", sha + "^{commit}"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if probe.returncode:
            command("fetch-" + target["label"], ["git", "fetch", "--no-tags", "origin", sha], timeout=180)
        pair = {}
        for label, ours in (("baseline", BASE), ("candidate", SOURCE)):
            output = OUTPUT / ("merge-" + target["label"] + "-" + label + ".txt")
            completed = subprocess.run(["git", "-c", "core.quotepath=false", "merge-tree", "--write-tree",
                                        "--name-only", "--messages", ours, sha],
                                       text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
            output.write_text(completed.stdout)
            assert completed.returncode in (0, 1), completed.stdout
            lines = completed.stdout.splitlines()
            assert lines and len(lines[0]) == 40 and all(c in "0123456789abcdef" for c in lines[0])
            conflicts = []
            if completed.returncode == 1:
                for line in lines[1:]:
                    if not line:
                        break
                    conflicts.append(line)
                assert conflicts
            pair[label] = {"source": ours, "other": sha, "exitCode": completed.returncode,
                           "tree": lines[0], "conflicts": conflicts, "log": output.name,
                           "sha256": digest(output.read_bytes())}
        assert set(pair["candidate"]["conflicts"]) <= set(pair["baseline"]["conflicts"]), pair
        results.append({"target": target, "proof": pair,
                        "status": "clean" if not pair["candidate"]["conflicts"] else "preexisting-conflicts"})
    save("merge-proofs.json", results)
    return {"openPrCount": len(snapshots), "stableMap": True, "comparisons": len(results) * 2,
            "newConflicts": 0, "results": results}


def native_failure_diagnostic():
    import validate_ios_plugin_fonts as V
    artifact_id = 13554198897
    metadata = api_read("/actions/artifacts/" + str(artifact_id))
    expected_sha = "965f2b73ff8b4ca2c6f8b1148da1c9e4bda5917b5c549aefafaf0c00f2922d48"
    assert metadata["size_in_bytes"] == 9618457 and metadata["digest"] == "sha256:" + expected_sha
    assert not metadata["expired"] and metadata["workflow_run"]["id"] == 42324522422
    assert metadata["workflow_run"]["head_sha"] == "0db2a3b77f1bb812a2743efd7ae5a9a6549e81a5"
    archive = api_read("/actions/artifacts/" + str(artifact_id) + "/zip", binary=True)
    assert len(archive) == 9618457 and digest(archive) == expected_sha
    archive_path = OUTPUT / "native-failed-5.zip"
    archive_path.write_bytes(archive)
    root = OUTPUT / "native-failed-5"
    root.mkdir()
    names = set()
    with zipfile.ZipFile(archive_path) as zipped:
        assert len(zipped.infolist()) < 2000 and sum(f.file_size for f in zipped.infolist()) < 512 * 1024 * 1024
        for info in zipped.infolist():
            path = PurePosixPath(info.filename)
            assert not path.is_absolute() and ".." not in path.parts and "\\" not in info.filename
            assert info.filename not in names and not stat.S_ISLNK(info.external_attr >> 16)
            names.add(info.filename)
            if info.is_dir():
                continue
            output = root.joinpath(*path.parts)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(zipped.read(info))
    hashes = retained_hashes(root)
    environments, reports = list(root.rglob("environment.json")), list(root.rglob("report.json"))
    assert len(environments) == len(reports) == 1
    environment_path, report_path = environments[0], reports[0]
    environment, envelope = V.read_json(environment_path), V.read_json(report_path)
    assert environment["sourceCommit"] == "0db2a3b77f1bb812a2743efd7ae5a9a6549e81a5"
    assert environment["sourceTree"] == "1c9f0dcf2005cf98ef049350c584cd02d33cbf61"
    diff = environment["sourceDiffAfter"]
    assert diff["file"] == "source-diffAfter.log"
    diff_path = environment_path.parent / diff["file"]
    data = diff_path.read_bytes()
    assert len(data) <= 256 * 1024 and digest(data) == diff["sha256"]
    try:
        semantic = {"status": "passed", "summary": V.validate(envelope)}
    except (ValueError, KeyError, TypeError) as error:
        semantic = {"status": "failed", "reason": str(error)}
    try:
        V.validate_artifacts(report_path, environment, environment_path.parent)
    except ValueError as error:
        rejection = str(error)
    else:
        raise AssertionError("Failed native run unexpectedly passed full acceptance")
    result = {
        "artifactId": artifact_id, "archiveBytes": len(archive), "archiveSha256": expected_sha,
        "sourceCommit": environment["sourceCommit"], "sourceTree": environment["sourceTree"],
        "sourceStatus": environment["sourceStatus"], "sourceStatusAfter": environment["sourceStatusAfter"],
        "flutterSourceStatus": environment["flutterSourceStatus"],
        "flutterSourceStatusAfter": environment["flutterSourceStatusAfter"],
        "primaryFailure": environment.get("primaryFailure"), "secondaryErrors": environment.get("secondaryErrors"),
        "driver": environment.get("drive"), "simulatorOwnership": environment.get("simulatorOwnership"),
        "semanticValidation": semantic, "fullNativeAcceptance": "REJECTED", "rejection": rejection,
        "reportSha256": digest(report_path.read_bytes()), "diffReceipt": diff, "sourceDiffText": data.decode("utf-8"),
        "unchangedArtifactFiles": len(hashes),
    }
    assert retained_hashes(root) == hashes
    save("native-failure-diagnostic.json", result)
    save("native-failure-file-hashes.json", hashes)
    print("BEGIN_QA4427_NATIVE_FAILURE_DIAGNOSTIC")
    print(json.dumps(result, ensure_ascii=False, allow_nan=False))
    print("END_QA4427_NATIVE_FAILURE_DIAGNOSTIC")
    return result

def main():
    sys.path.insert(0, str(ROOT / "tool/perf_probe"))
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    sys.dont_write_bytecode = True
    if sys.argv[1:] == ["--native-failure-diagnostic"]:
        source_bound()
        native_failure_diagnostic()
        return 0
    initial = gate("source-binding", source_bound)
    baseline = None
    if initial is not None:
        tool = gate("toolchain-and-strict-pub", toolchain)
        if tool is not None:
            baseline = gate("source-sdk-dependency-baseline", snapshot_roots)
            if baseline is not None:
                save("source-before.json", baseline)
            gate("original-hook", original_hook)
            gate("source-after-hook", source_bound)
            gate("full-analyze", lambda: command("full-analyze", ["flutter", "analyze", "--no-pub"], timeout=1200))
        else:
            GATES.append({"name": "hook-and-analyze", "status": "blocked", "reason": "strict toolchain/pub gate failed"})
        # Python review, original artifact replay and Git proofs are independent of build availability.
        gate("source-before-independent-controls", source_bound)
        replay = gate("original-artifact-replay", original_reports)
        if replay is not None:
            gate("independent-numeric-controls", numeric_controls)
        else:
            GATES.append({"name": "independent-numeric-controls", "status": "blocked", "reason": "original report replay failed"})
        gate("independent-io-controls", io_controls)
        gate("overlap-merge-proofs", merge_proofs)
        if baseline is not None:
            def unchanged():
                after = snapshot_roots()
                save("source-after.json", after)
                assert after == baseline, "App, Flutter SDK or dependency Git source changed"
                return {"repositories": len(after["repositories"]),
                        "trackedFiles": sum(len(r["files"]) for r in after["repositories"].values()),
                        "packages": len(after["packages"]), "identical": True}
            gate("source-sdk-dependency-unchanged", unchanged)
        gate("final-source-binding", source_bound)
    status = "passed" if GATES and all(g["status"] == "passed" for g in GATES) else "failed"
    summary = {"schemaVersion": 1, "status": status, "sourceCommit": SOURCE, "sourceTree": SOURCE_TREE,
               "qaHead": git("rev-parse", "HEAD"), "base": BASE,
               "scope": "Independent controlled QA and immutable original artifact replay; new native acceptance is separate",
               "gates": GATES, "originalFullNativeAcceptance": "REJECTED",
               "newNativeIOS": "SEPARATE_WORKFLOW", "newNativeMacOS": "SEPARATE_WORKFLOW",
               "production": "OFF", "artifactCodeExecuted": False}
    save("summary.json", summary)
    hashes = retained_hashes(OUTPUT)
    save("evidence-file-manifest.json", hashes)
    print("BEGIN_QA4427_INDEPENDENT_SUMMARY")
    print(json.dumps(summary, ensure_ascii=False, allow_nan=False))
    print("END_QA4427_INDEPENDENT_SUMMARY")
    return 0 if status == "passed" else 1

if __name__ == "__main__":
    sys.exit(main())
