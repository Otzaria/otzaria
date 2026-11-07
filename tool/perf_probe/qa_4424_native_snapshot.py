#!/usr/bin/env python3
"""QA-only immutable source/SDK/Git dependency snapshots for actual Windows app."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import traceback
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname

SOURCE = "05e150d09758e0da45ca1877a4d650358f1aa17f"
SOURCE_TREE = "e43bd8f0db6d1b2a107f767c18e3261a27e15837"
PUBLIC = "2aa04e69f4b6802bd376aed41f529590a6c4f9b3"
SDK_HEAD = "abaf9c523780a608bd46686fd5e53740a07077f8"
EXPECTED = json.loads(r'''[{"path":"tool/perf_probe/installed_plugin_windows_lifetime.cs","bytes":19764,"sha256":"e373e8b5dcd6a17d925e52249050d9e99d0c0c1a04fa59523e8b1f86b30e4b15"},{"path":"tool/perf_probe/test_installed_plugin_windows_lifetime.cs","bytes":15375,"sha256":"bc93f45dbbd1646dd59a08c43f7e5f1f6c3a75a69345060dea610f766c930c04"},{"path":"pubspec.yaml","bytes":13609,"sha256":"b900e75318dfb65333f97e8529c52dfe08df0893292e535700094da7ae8c6b51"},{"path":"pubspec.lock","bytes":66487,"sha256":"94bf01c88e2568424d39a7da767ecdd70356c915f8636e0ccb233121bb6ef932"},{"path":"integration_test/support/installed_plugin_windows_lifetime.dart","bytes":3701,"sha256":"d896f1580440e1fe726595b8d0afc64046a6480cbb0a949cf9a04c009c8a8173"},{"path":".github/workflows/installed_plugin_probe.yml","bytes":7040,"sha256":"382f4f78f9b41fde647162d1058bec60d4df4ea4ad85cd48610cded77753b6d3"},{"path":"tool/perf_probe/installed_plugin_windows_control.psm1","bytes":10454,"sha256":"dea8243fa148fc09168e0833ac36b77fac03486e0657d478b545c672d0d23d5f"},{"path":"tool/perf_probe/installed_plugin_windows_exit.psm1","bytes":15874,"sha256":"5d1d26bc0adb24cc91f7ec81031daca4985233f7601a21dc30616c53ea373e96"},{"path":"tool/perf_probe/test_installed_plugin_windows_runner.ps1","bytes":12152,"sha256":"9f732afcc8093933db9402de470a1f34d0e55289c398589efecc616e5adc8b93"},{"path":"tool/perf_probe/installed_plugin_windows_runner.psm1","bytes":10724,"sha256":"205ccece2043181621a9dae1a98db59d6df76b93b788a48e57cb3afc66c6e462"},{"path":"tool/perf_probe/run_installed_plugin_windows.ps1","bytes":586,"sha256":"edd23bafd7dd24ad7ffc4d090197610eed43c392e0050bc0b737fc8e4c7c0569"},{"path":"integration_test/installed_plugin_resource_probe_test.dart","bytes":53896,"sha256":"4f03d7f8f7a2cb94ed79590af5995b9f146077cceb7f49d688c41dceaf9d642e"},{"path":"tool/perf_probe/WEBVIEW_RESOURCE_PROBE.md","bytes":45250,"sha256":"f97230e81069bf3799f0229999c649c0e7f4a5c4fd23890c39030f8e4ef58fc3"},{"path":"test/tool/perf_probe/installed_plugin_windows_lifetime_test.dart","bytes":6586,"sha256":"06e509186494e4a6a80a20f962a22bb92b3fb357fb7254b499db4056333443f3"},{"path":"tool/perf_probe/test_installed_plugin_windows_control.ps1","bytes":12208,"sha256":"157dff260b0c608be395193a8dde2d0821b45f029e82b8315ae8db2b5fe5a1da"},{"path":"tool/perf_probe/test_installed_plugin_windows_exit.ps1","bytes":23197,"sha256":"dd9f4244782b7f7043d9d66dad81b6acdf267e46e857a67ffb25f0bb518b4d0d"}]''')
GIT_PACKAGES = json.loads(r'''{"flutter_inappwebview":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_android":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_ios":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_linux":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_macos":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_platform_interface":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_web":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_inappwebview_windows":"c709de98711cf34350c48df4c75e24d0879d5876","flutter_local_notifications_windows":"ad21cf2cddfa7c79ea7903ad95b38a8d716b5f85","flutter_widget_from_html_core":"57080495ee8b89aeee156a4440b6de1c5e0f7ef2","opentype_shaper":"461902c049b412d64dc4dfa7b547fedbf751211d","otzaria_ashurit":"b43b67bb706be6bc87af14658d67e16cd347fc29","otzaria_icons":"483fec355339f54f9e094994a106dad9a63b82e3","otzaria_search_engine":"2da23091237ed0f0a612de3b2d18cfc99d8b7d2a","pdfrx":"942e27bec86e8d480111517c2083eb52817ee032","printing":"3cb90fb3025553f3e9f48638c79ccf93efb326af","seforim_library_updater":"6bfd33c3bc14392c1a6bb0887fdb23209068eab5","sentry_flutter":"93e7398355e80557a342666f98b23cc9bb832848","window_manager":"88a433a7be43ed0213da12b561bf0d8d070c6d68"}''')
REPO = Path.cwd().resolve()
OUT = Path(os.environ["RUNNER_TEMP"]) / "installed-plugin-probe" / "qa-snapshots"
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
        row.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
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
    (OUT / "checkout-policy.txt").write_bytes(git("config", "--show-origin", "--get-regexp", r"^core\.(autocrlf|eol)$"))
    actual_files = []
    if text("rev-parse", SOURCE + "^{tree}") != SOURCE_TREE or text("rev-parse", SOURCE + "^") != PUBLIC:
        raise RuntimeError("Frozen source parent or tree changed")
    qa_head = text("rev-parse", "HEAD")
    if text("rev-parse", "HEAD^") != SOURCE:
        raise RuntimeError("Native QA checkout is not a direct child of exact source")
    expected_additions = {".github/workflows/qa_4424_windows_native_debug.yml", "tool/perf_probe/qa_4424_native_snapshot.py", "tool/perf_probe/qa_4424_native_debugger.cpp", "tool/perf_probe/qa_4424_native_debug.ps1"}
    if set(text("diff", "--name-only", SOURCE, "HEAD").splitlines()) != expected_additions:
        raise RuntimeError("Native QA checkout changes application source")
    for item in EXPECTED:
        data = (REPO / item["path"]).read_bytes()
        actual_files.append({"path": item["path"], "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        save("source-actual-files-" + mode + ".json", actual_files)
        if len(data) != item["bytes"] or hashlib.sha256(data).hexdigest() != item["sha256"]:
            target = OUT / "mismatched-source" / item["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            save("source-mismatch-" + mode + ".json", {"expected": item, "actual": actual_files[-1]})
            raise RuntimeError("Frozen source mismatch: " + item["path"])
    if set(text("diff", "--name-only", PUBLIC, SOURCE).splitlines()) != {x["path"] for x in EXPECTED}:
        raise RuntimeError("Source is not exactly the reviewed sixteen-file PR delta")
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
    print("BEGIN_QA_4424_NATIVE_SNAPSHOT_" + mode)
    print(json.dumps(receipt, ensure_ascii=False))
    print("END_QA_4424_NATIVE_SNAPSHOT_" + mode)
sys.exit(0 if receipt["passed"] else 1)
