#!/usr/bin/env python3
"""QA-only immutable source/SDK/Git dependency snapshots for actual Apple app."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import traceback
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname

SOURCE = "de019fc88b93a6ec58dd80d6ab40cd26fd5c06e1"
SOURCE_TREE = "765928640680a128e48690dff500a86911a8aeaa"
PUBLIC = "3b9c05140f722d31fe1fb7312e9722db646335a5"
SDK_HEAD = "abaf9c523780a608bd46686fd5e53740a07077f8"
EXPECTED = json.loads(r'''[{"path":".github/workflows/apple-plugin-activity.yml","mode":"100644","sha":"9ec09629f9db04e4ce974c181033c3d2a1becf14","bytes":6594,"sha256":"dc08561260f17d941af5fb99cfe172f3e36ed5a60be9a96299f7ac58f9d939d2"},{"path":"integration_test/apple_plugin_activity_probe_test.dart","mode":"100644","sha":"12539d1e150832b2ae2971181612caba13d8b5f8","bytes":30720,"sha256":"44b0be6b97633b8526ce192eef75578ebb8bed6941276f9009bd548699cbe643"},{"path":"ios/Runner.xcodeproj/project.pbxproj","mode":"100644","sha":"b5f0f0c700d3933e762d38c3d706b2ce3af9d82a","bytes":31892,"sha256":"cba33ded34fa00b8f1aacfc0da74126aac3085256c2e44ce06fed7ec5c81374f"},{"path":"ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme","mode":"100644","sha":"c3fedb29c990d9c5a66b9f4ffb198b0ca3ce2ce5","bytes":4717,"sha256":"9fbce429f56243561dd437a527136c9f9ed77165e3b271b923faf236cfcd0484"},{"path":"lib/core/window_listener.dart","mode":"100644","sha":"25b13d9b31afead65b3f0ad17e7d9f7cca7167b3","bytes":33230,"sha256":"5f8680dc146863e76e73522be736133606871d0eb14d1ac8019d1a9102722800"},{"path":"pubspec.lock","mode":"100644","sha":"61f0e395ef0f048f47f46094a20cfa421a5e0178","bytes":66487,"sha256":"fe731ab5452aba50c3311555016e18b868a4749dbcd5e19b86970a2981cb389c"},{"path":"pubspec.yaml","mode":"100644","sha":"cf796836f78f63e1cea0ce2cdbaa7dca9140246f","bytes":13609,"sha256":"72e41248f6afdf7831079a1c117e27a68f82f6dbfa8d87e3fed840ed772dd7d1"},{"path":"test/core/window_listener_native_visibility_test.dart","mode":"100644","sha":"a6394e2c03a45c5a31462a5c1c4790382ed4297c","bytes":3648,"sha256":"307d75acb0d29a208f85278a2341c4ebcbaac26c3995b3a085dc8a561bb12bab"},{"path":"tool/perf_probe/apple_plugin_activity/AppleQuietControl.swift","mode":"100644","sha":"c20567565beba70d97f672a0434a8456b021fda0","bytes":7225,"sha256":"633d866d38943ab76581f5dd4a34c85876b8029fb94f89872e2acd06249e057f"},{"path":"tool/perf_probe/apple_plugin_activity/README.md","mode":"100644","sha":"6356f39386a52b7c721bfba5442a47056ace0cda","bytes":36945,"sha256":"d2106da0d8d3b18545a34dd0d69139fc5d8675a09b245edb00b52ea51078dd0c"},{"path":"tool/perf_probe/apple_plugin_activity/mac_application.swift","mode":"100644","sha":"be9acc8964ca2f8bd2478b4677b6fc06ceed0f05","bytes":11105,"sha256":"8961aeebc55cadcf2ef74d50888cde2638fff66c128559af52d0b30c835b938e"},{"path":"tool/perf_probe/apple_plugin_activity/mac_launch_fixture.swift","mode":"100644","sha":"6ee7c7f170a58ac81bc970c4d1ab0ce7ed94c0a7","bytes":4493,"sha256":"a623fc9da165e928446b4d466f234a747bf93e1d9b8a0200d8833d67319d0303"},{"path":"tool/perf_probe/apple_plugin_activity/mac_process_control.c","mode":"100644","sha":"51b1610b1fcc85d15933cd927e543ff0b4786718","bytes":892,"sha256":"0c6cec86cca15bffc10df277ae5b536beba50aeaf6a650f8d2974f0f467d0dec"},{"path":"tool/perf_probe/apple_plugin_activity/mac_process_control.h","mode":"100644","sha":"d3d9d6086493f665d09f947d27d62ee9f9f665cc","bytes":481,"sha256":"1f6a9cc7593d0f1b114758670ebfbee06883e74d2c300161daa18072170000d9"},{"path":"tool/perf_probe/apple_plugin_activity/run.py","mode":"100644","sha":"c8f2cf420610c17d3c1c5f28bf23fdd562394791","bytes":60511,"sha256":"7200fd9013891c3e2c7daab715a7ab17e22778c69a4431b0117434061e876dab"},{"path":"tool/perf_probe/apple_plugin_activity/test_cleanup_boundaries.py","mode":"100644","sha":"afa4b01aabe568ef820e3819c915ea214bf17a63","bytes":17691,"sha256":"314902daf107bc214f4620a992671b654a5f87978a79461706122638507b3851"},{"path":"tool/perf_probe/apple_plugin_activity/test_cleanup_permissions.py","mode":"100644","sha":"dabca892ebb9adbe7934cd00889e92d22958aeb6","bytes":11628,"sha256":"635776c77d74ac1ce63b3b0cd8e6ad90b46b82e03db576fb5b408e74f32ce560"},{"path":"tool/perf_probe/apple_plugin_activity/test_lifetime.py","mode":"100644","sha":"766d0a4adc06acc1f73d7c69dffc38352e194099","bytes":21343,"sha256":"d3edb7de439cdb32536a4c7ffbe64e6c7f2752448f415ba20b9a566a0a6e22ab"},{"path":"tool/perf_probe/apple_plugin_activity/test_macos_controller.py","mode":"100644","sha":"0f63966d86d891cd89d5cfbd7c317e99b49a1420","bytes":19043,"sha256":"71292b71e8e6fd1ea8051b2805414c630239b33b76d267874468b2e161c52781"},{"path":"tool/perf_probe/apple_plugin_activity/test_runner.py","mode":"100644","sha":"f1e9d6b20fcb53baee84531a4c56e85bbc5039d5","bytes":23550,"sha256":"a2227a5e181e1de3f9229e2b82ee74d5405de0e6cf5240b26de70392e4343125"}]''')
GIT_PACKAGES = json.loads(r'''{"flutter_inappwebview":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_android":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_ios":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_linux":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_macos":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_platform_interface":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_web":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_windows":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_local_notifications_windows":"ad21cf2cddfa7c79ea7903ad95b38a8d716b5f85","flutter_widget_from_html_core":"57080495ee8b89aeee156a4440b6de1c5e0f7ef2","opentype_shaper":"461902c049b412d64dc4dfa7b547fedbf751211d","otzaria_ashurit":"b43b67bb706be6bc87af14658d67e16cd347fc29","otzaria_icons":"483fec355339f54f9e094994a106dad9a63b82e3","otzaria_search_engine":"2da23091237ed0f0a612de3b2d18cfc99d8b7d2a","pdfrx":"942e27bec86e8d480111517c2083eb52817ee032","printing":"3cb90fb3025553f3e9f48638c79ccf93efb326af","seforim_library_updater":"6bfd33c3bc14392c1a6bb0887fdb23209068eab5","sentry_flutter":"93e7398355e80557a342666f98b23cc9bb832848","window_manager":"88a433a7be43ed0213da12b561bf0d8d070c6d68"}''')
REPO = Path.cwd().resolve()
OUT = Path(os.environ["RUNNER_TEMP"]).resolve() / "qa-4425-native-snapshots"
OUT.mkdir(parents=True, exist_ok=True)

def save(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

def git(*args, root=REPO):
    result = subprocess.run(["git", "-C", str(root), *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
    if result.returncode:
        raise RuntimeError(f"git {args!r} failed: {result.stderr.decode('utf-8', 'replace')[:2000]}")
    return result.stdout

def text(*args, root=REPO):
    return git(*args, root=root).decode("utf-8").strip()

def snapshot(root):
    root = Path(root).resolve()
    rows = []
    for raw in git("ls-files", "-z", root=root).split(b"\0"):
        if not raw:
            continue
        name = os.fsdecode(raw)
        path = root / name
        row = {"path": name}
        if path.is_symlink():
            data = os.fsencode(os.readlink(path))
            row["kind"] = "symlink"
        elif path.is_file():
            data = path.read_bytes()
            row["kind"] = "file"
        else:
            data = b""
            row["kind"] = "missing"
        row.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                   mode=stat.S_IMODE(path.lstat().st_mode) if path.exists() or path.is_symlink() else None)
        rows.append(row)
    result = {
        "root": str(root), "head": text("rev-parse", "HEAD", root=root),
        "tree": text("rev-parse", "HEAD^{tree}", root=root),
        "indexSha256": hashlib.sha256(git("ls-files", "--stage", "-z", root=root)).hexdigest(),
        "status": text("status", "--porcelain=v1", "--untracked-files=no", root=root),
        "trackedFiles": len(rows), "files": rows,
        "trackedSha256": hashlib.sha256(json.dumps(rows, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest(),
    }
    return result

def preserve_mutations(label, root):
    for kind, args in (("worktree", ["diff", "--binary", "HEAD", "--"]), ("index", ["diff", "--cached", "--binary", "HEAD", "--"])):
        (OUT / (label + "-" + kind + ".diff")).write_bytes(git(*args, root=root))
    names = text("diff", "--name-only", "HEAD", "--", root=root).splitlines()
    for name in names:
        original = Path(root) / name
        if original.is_file():
            target = OUT / "mutated-files" / label / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(original, target)

def verify_source():
    (OUT / "checkout-line-endings.txt").write_bytes(git("ls-files", "--eol"))
    policy = subprocess.run(["git", "config", "--show-origin", "--get-regexp", r"^core\.(autocrlf|eol)$"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    if policy.returncode not in (0, 1):
        raise RuntimeError("Unable to inspect checkout line-ending policy")
    (OUT / "checkout-policy.txt").write_bytes(policy.stdout + policy.stderr)
    actual_files = []
    if text("rev-parse", SOURCE + "^{tree}") != SOURCE_TREE or text("rev-parse", SOURCE + "^") != PUBLIC:
        raise RuntimeError("Frozen source parent or tree changed")
    qa_head = text("rev-parse", "HEAD")
    if text("rev-parse", "HEAD^") != SOURCE:
        raise RuntimeError("Native QA checkout is not a direct child of exact source")
    expected_additions = {".github/workflows/qa_4425_apple_native.yml", "tool/perf_probe/qa_4425_native_snapshot.py"}
    if set(text("diff", "--name-only", SOURCE, "HEAD").splitlines()) != expected_additions:
        raise RuntimeError("Native QA checkout changes application source")
    for item in EXPECTED:
        data = (REPO / item["path"]).read_bytes()
        tree_entry = text("ls-tree", SOURCE, "--", item["path"]).split()
        blob = hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()
        actual_files.append({"path": item["path"], "mode": tree_entry[0], "sha": blob, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        save("source-actual-files-" + mode + ".json", actual_files)
        if actual_files[-1] != item or tree_entry[2] != item["sha"]:
            target = OUT / "mismatched-source" / item["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            save("source-mismatch-" + mode + ".json", {"expected": item, "actual": actual_files[-1]})
            raise RuntimeError("Frozen source mismatch: " + item["path"])
    if set(text("diff", "--name-only", PUBLIC, SOURCE).splitlines()) != {x["path"] for x in EXPECTED}:
        raise RuntimeError("Source is not exactly the reviewed twenty-file PR delta")
    return qa_head

def sdk_root():
    command = shutil.which("flutter")
    if not command:
        raise RuntimeError("Flutter command is unavailable")
    root = Path(command).resolve().parent.parent
    return root

def dependency_roots():
    config_path = REPO / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    rows = {}
    roots = {}
    for package in config["packages"]:
        name = package["name"]
        if name not in GIT_PACKAGES:
            continue
        uri = urlparse(urljoin(config_path.as_uri(), package["rootUri"]))
        if uri.scheme != "file":
            raise RuntimeError("Git package has unexpected URI: " + name)
        path = Path(url2pathname(uri.path)).resolve()
        root = Path(text("rev-parse", "--show-toplevel", root=path)).resolve()
        head = text("rev-parse", "HEAD", root=root)
        if name in rows:
            raise RuntimeError("Duplicate resolved Git dependency: " + name)
        rows[name] = {"root": str(path), "gitRoot": str(root), "head": head}
        roots[str(root)] = root
    if set(rows) != set(GIT_PACKAGES):
        raise RuntimeError("Resolved Git package enumeration is incomplete")
    save("resolved-git-packages-" + sys.argv[1] + ".json", rows)
    return roots

def equivalent(before, after):
    return before == after

def summary(value):
    return {key: {k: row[k] for k in ("head", "tree", "trackedFiles", "trackedSha256", "indexSha256", "status")} for key, row in value.items()}

mode = sys.argv[1]
receipt = {"mode": mode, "passed": False, "sourceCommit": SOURCE, "sourceTree": SOURCE_TREE}
try:
    roots = {"application": REPO, "flutter-sdk": sdk_root()}
    if mode in ("resolved", "before-native", "after"):
        roots.update(dependency_roots())
    current = {key: snapshot(root) for key, root in roots.items()}
    save(mode + ".json", current)
    receipt["snapshots"] = summary(current)
    for index, (key, root) in enumerate(roots.items()):
        preserve_mutations(str(index), root)
    receipt["qaHead"] = verify_source()
    if current["flutter-sdk"]["head"] != SDK_HEAD:
        raise RuntimeError("Flutter SDK commit is not the exact approved 3.47.7")
    dart_version = (roots["flutter-sdk"] / "bin/cache/dart-sdk/version").read_text(encoding="utf-8").strip()
    if dart_version != "3.13.5":
        raise RuntimeError("Dart SDK is not exactly 3.13.5: " + dart_version)
    if mode != "bind":
        packages = json.loads((OUT / ("resolved-git-packages-" + mode + ".json")).read_text(encoding="utf-8"))
        if {name: item["head"] for name, item in packages.items()} != GIT_PACKAGES:
            raise RuntimeError("Actual resolved Git dependency heads differ from the exact lock")
    if any(row["status"] for row in current.values()):
        raise RuntimeError("A source, SDK or Git dependency checkout has tracked modifications; retained without reset")
    if mode == "bind":
        if text("status", "--porcelain=v1"):
            raise RuntimeError("Native QA checkout starts dirty")
    else:
        initial = json.loads((OUT / "bind.json").read_text(encoding="utf-8"))
        if any(not equivalent(initial[key], current[key]) for key in ("application", "flutter-sdk")):
            raise RuntimeError("Application, index or SDK bytes changed since initial snapshot")
        if mode in ("before-native", "after"):
            baseline = json.loads((OUT / "resolved.json").read_text(encoding="utf-8"))
            if not equivalent(baseline, current):
                raise RuntimeError("Resolved Git dependency, application or SDK bytes changed")
    receipt["passed"] = True
except Exception as error:
    receipt["error"] = str(error)
    receipt["traceback"] = traceback.format_exc()
    # Keep even incomplete/mutated evidence. No checkout reset is permitted.
    try:
        preserve_mutations("failure-application", REPO)
        save(mode + "-failure-application.json", snapshot(REPO))
    except Exception as nested:
        receipt["preservationError"] = str(nested)
finally:
    save(mode + "-receipt.json", receipt)
    print("BEGIN_QA_4425_NATIVE_SNAPSHOT_" + mode)
    print(json.dumps(receipt, ensure_ascii=False))
    print("END_QA_4425_NATIVE_SNAPSHOT_" + mode)
sys.exit(0 if receipt["passed"] else 1)
