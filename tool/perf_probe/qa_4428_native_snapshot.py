#!/usr/bin/env python3
"""QA-only immutable source/SDK/Git dependency snapshots for actual Android app."""
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

SOURCE = "4d627791faf270a9ab9ccee14e07a7a537cc1c97"
SOURCE_TREE = "a63d42cb87f01433c3848f7077d23b1ea3cb0854"
PUBLIC = "9fdc05b9dc98c732affeb91bd78062ea369387dc"
SDK_HEAD = "abaf9c523780a608bd46686fd5e53740a07077f8"
EXPECTED = json.loads(r'''[{"path":".github/workflows/installed_plugin_probe_android.yml","bytes":4233,"sha256":"6828b039ca7c6b09125a0e6c4cdf41c6c118f5bc93da9b862d516b7cf4415216"},{"path":"android/app/build.gradle","bytes":3595,"sha256":"7f4bb82fb21cf82d8b93e76551b541e13c9061cecc5075effa8e1d06c8ce91cd"},{"path":"integration_test/installed_plugin_resource_probe_test.dart","bytes":59604,"sha256":"c6de4983280a44f03215f79e781870dd30f2f7a528117188ce6f9eda3924bc8a"},{"path":"integration_test/support/installed_plugin_android_control.dart","bytes":7847,"sha256":"f44ed3d8c2937730325dca609b6a6e81fff8d4f2210b30eaf2d3ad0309d9272f"},{"path":"pubspec.lock","bytes":66487,"sha256":"7cb40007d9484e613567165ea97b2ead3426a50c60c16a7e6fa874af32a27faf"},{"path":"pubspec.yaml","bytes":13609,"sha256":"70eda15deb3977c28e581205f8242f6f0ffa368ab82fc17aee0877c29e64b232"},{"path":"test/tool/perf_probe/installed_plugin_android_control_test.dart","bytes":15880,"sha256":"18123632280b024183c3b7403ff16e04d5f540eb7ed5fef7a678fe987a68df6e"},{"path":"tool/perf_probe/INSTALLED_PLUGIN_ANDROID.md","bytes":13242,"sha256":"f4125059d0ced6d28a24d11f2f6e90503b0642d00a0ba9c6f85c2bca627dd15e"},{"path":"tool/perf_probe/run_installed_plugin_android.py","bytes":44385,"sha256":"ba03044836f876de02399220b3b6ae09b535eb23118363ee680652d692f10cc4"},{"path":"tool/perf_probe/test_installed_plugin_android.py","bytes":55457,"sha256":"53da871ca89837cc62416f669c3237636a6936cfa17d29d10aa9f1f3707756e0"}]''')
PUBLIC_DELTA = ["integration_test/installed_plugin_resource_probe_test.dart","integration_test/support/installed_plugin_android_control.dart","test/tool/perf_probe/installed_plugin_android_control_test.dart","tool/perf_probe/INSTALLED_PLUGIN_ANDROID.md","tool/perf_probe/run_installed_plugin_android.py","tool/perf_probe/test_installed_plugin_android.py"]
GIT_PACKAGES = json.loads(r'''{"flutter_inappwebview":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_android":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_ios":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_linux":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_macos":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_platform_interface":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_web":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_windows":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_local_notifications_windows":"ad21cf2cddfa7c79ea7903ad95b38a8d716b5f85","flutter_widget_from_html_core":"57080495ee8b89aeee156a4440b6de1c5e0f7ef2","opentype_shaper":"461902c049b412d64dc4dfa7b547fedbf751211d","otzaria_ashurit":"b43b67bb706be6bc87af14658d67e16cd347fc29","otzaria_icons":"483fec355339f54f9e094994a106dad9a63b82e3","otzaria_search_engine":"2da23091237ed0f0a612de3b2d18cfc99d8b7d2a","pdfrx":"942e27bec86e8d480111517c2083eb52817ee032","printing":"3cb90fb3025553f3e9f48638c79ccf93efb326af","seforim_library_updater":"6bfd33c3bc14392c1a6bb0887fdb23209068eab5","sentry_flutter":"93e7398355e80557a342666f98b23cc9bb832848","window_manager":"4f37655288ce8b803a9bd50294c5d6983850f622"}''')
REPO = Path.cwd().resolve()
OUT = Path(os.environ["RUNNER_TEMP"]).resolve() / "qa-4428-native-snapshots"
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
    configuration = subprocess.run(["git", "-C", str(REPO), "config", "--show-origin", "--get-regexp",
                                    r"^core\.(autocrlf|eol)$"],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
    if configuration.returncode not in (0, 1):
        raise RuntimeError("Cannot record Git checkout policy")
    (OUT / "checkout-policy.txt").write_bytes(configuration.stdout)
    save("checkout-policy-status.json", {"exitCode": configuration.returncode,
                                       "noExplicitPolicy": configuration.returncode == 1})
    actual_files = []
    if text("rev-parse", SOURCE + "^{tree}") != SOURCE_TREE or text("rev-parse", SOURCE + "^") != PUBLIC:
        raise RuntimeError("Frozen source parent or tree changed")
    qa_head = text("rev-parse", "HEAD")
    if text("rev-list", "--parents", "-n", "1", "HEAD").split()[1:] != [SOURCE]:
        raise RuntimeError("Native QA checkout is not the sole direct child of exact source")
    for revision in (SOURCE, qa_head):
        identity = text("show", "-s", "--format=%an%x00%ae%x00%cn%x00%ce", revision).split("\0")
        if identity != ["Y-Ploni", "7353755@gmail.com", "Y-Ploni", "7353755@gmail.com"]:
            raise RuntimeError("Candidate or QA author/committer differs")
    expected_additions = {".github/workflows/qa_4428_android_native.yml", "tool/perf_probe/qa_4428_native_snapshot.py"}
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
    if set(text("diff", "--name-only", PUBLIC, SOURCE).splitlines()) != set(PUBLIC_DELTA):
        raise RuntimeError("Source is not exactly the reviewed six-path public delta")
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
    print("BEGIN_QA_4428_NATIVE_SNAPSHOT_" + mode)
    print(json.dumps(receipt, ensure_ascii=False))
    print("END_QA_4428_NATIVE_SNAPSHOT_" + mode)
sys.exit(0 if receipt["passed"] else 1)
