#!/usr/bin/env python3
"""Independent, source-bound QA. This file is never part of PR 4428."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import time
import traceback
from urllib.parse import unquote, urljoin, urlparse
import urllib.request
from datetime import datetime, timezone

SOURCE = "b9f7c186cb240ec45ba77e3160acc78402f4e172"
SOURCE_TREE = "4900c1eb5bbfc2f53b8d2b2273029ef9f5aba1f1"
PUBLIC = "9fdc05b9dc98c732affeb91bd78062ea369387dc"
HOOK_SHA256 = "53b75db342d0332ae703c389562adf65a04d6127bd1ff05edaef0dde7b020097"
EXPECTED = json.loads(r'''[{"path":".github/workflows/installed_plugin_probe_android.yml","mode":"100644","sha":"f731b8607b72c4f583bee251f3c1215224f349bc","bytes":4233,"sha256":"6828b039ca7c6b09125a0e6c4cdf41c6c118f5bc93da9b862d516b7cf4415216"},{"path":"android/app/build.gradle","mode":"100644","sha":"1ea47509d93d48688a7be4e328355b777347be11","bytes":3595,"sha256":"7f4bb82fb21cf82d8b93e76551b541e13c9061cecc5075effa8e1d06c8ce91cd"},{"path":"integration_test/installed_plugin_resource_probe_test.dart","mode":"100644","sha":"3fff9055bd0f023776d65b87a79ea94656d69488","bytes":59604,"sha256":"c6de4983280a44f03215f79e781870dd30f2f7a528117188ce6f9eda3924bc8a"},{"path":"integration_test/support/installed_plugin_android_control.dart","mode":"100644","sha":"7755b10653ad65bd6e13c6aa5ab76c1799b0d51f","bytes":7847,"sha256":"f44ed3d8c2937730325dca609b6a6e81fff8d4f2210b30eaf2d3ad0309d9272f"},{"path":"pubspec.lock","mode":"100644","sha":"5e175ffefe86620541f53dcf8172b9c0f412b2bd","bytes":66487,"sha256":"7cb40007d9484e613567165ea97b2ead3426a50c60c16a7e6fa874af32a27faf"},{"path":"pubspec.yaml","mode":"100644","sha":"332081188494a74e08c57595eb01ec882c0f97e3","bytes":13609,"sha256":"70eda15deb3977c28e581205f8242f6f0ffa368ab82fc17aee0877c29e64b232"},{"path":"test/tool/perf_probe/installed_plugin_android_control_test.dart","mode":"100644","sha":"72a0868e65a85dc9df7590377f7234019ad340b4","bytes":15880,"sha256":"18123632280b024183c3b7403ff16e04d5f540eb7ed5fef7a678fe987a68df6e"},{"path":"tool/perf_probe/INSTALLED_PLUGIN_ANDROID.md","mode":"100644","sha":"41f0ca27275be2aeea5d86b44b33c00eced38550","bytes":13183,"sha256":"10797de82575f5862d5c0cc7e77addca0bdef279ae5d47c1c7d8840a92030da8"},{"path":"tool/perf_probe/run_installed_plugin_android.py","mode":"100644","sha":"88e6897857a7c9c3340123edf95947baf3cbe566","bytes":44383,"sha256":"53752be7c5261469156641554c958001630b1079f8ac2762507a206cfe5389e0"},{"path":"tool/perf_probe/test_installed_plugin_android.py","mode":"100644","sha":"72dc98e88aad52135c0d694fa5e0aa3cd7a1f0f2","bytes":54170,"sha256":"e321c9130bd4bcea7491d02291dea34cd11f97aa2c3b58e7e1215e4b66759b6d"}]''')
SOURCE_DELTA_PATHS = ["integration_test/installed_plugin_resource_probe_test.dart","integration_test/support/installed_plugin_android_control.dart","test/tool/perf_probe/installed_plugin_android_control_test.dart","tool/perf_probe/INSTALLED_PLUGIN_ANDROID.md"]
GIT_PINS = json.loads(r'''{"flutter_inappwebview":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_android":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_ios":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_linux":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_macos":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_platform_interface":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_web":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_windows":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_local_notifications_windows":"ad21cf2cddfa7c79ea7903ad95b38a8d716b5f85","flutter_widget_from_html_core":"57080495ee8b89aeee156a4440b6de1c5e0f7ef2","opentype_shaper":"461902c049b412d64dc4dfa7b547fedbf751211d","otzaria_ashurit":"b43b67bb706be6bc87af14658d67e16cd347fc29","otzaria_icons":"483fec355339f54f9e094994a106dad9a63b82e3","otzaria_search_engine":"2da23091237ed0f0a612de3b2d18cfc99d8b7d2a","pdfrx":"942e27bec86e8d480111517c2083eb52817ee032","printing":"3cb90fb3025553f3e9f48638c79ccf93efb326af","seforim_library_updater":"6bfd33c3bc14392c1a6bb0887fdb23209068eab5","sentry_flutter":"93e7398355e80557a342666f98b23cc9bb832848","window_manager":"4f37655288ce8b803a9bd50294c5d6983850f622"}''')
TARGETS = []  # Determined from a fresh, complete GitHub PR/file snapshot in merge mode.
OUT = Path(os.environ["QA_EVIDENCE_DIR"]).resolve()
OUT.mkdir(parents=True, exist_ok=False)
CASES = []
REPO = Path.cwd().resolve()
API_TOKEN = os.environ.pop("QA_GITHUB_TOKEN", "")
# The read-only API credential is never inherited by subprocesses.
os.environ.pop("GITHUB_TOKEN", None)
os.environ.pop("GH_TOKEN", None)

def save(name, value):
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

def command(args, label, cwd=None, allowed=(0,), timeout=300):
    before = time.monotonic()
    log_path = OUT / (label + ".log")
    timed_out = False
    # Output is streamed directly to retained bytes, including when a child times out.
    with log_path.open("wb") as log:
        process = subprocess.Popen(args, cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=30)
        log.flush()
    raw = log_path.read_bytes()
    record = {"command": [str(x) for x in args], "cwd": str(cwd or REPO),
              "exitCode": process.returncode, "seconds": time.monotonic() - before,
              "timedOut": timed_out, "timeoutSeconds": timeout,
              "outputSha256": hashlib.sha256(raw).hexdigest(), "outputBytes": len(raw)}
    save(label + ".json", record)
    print(json.dumps(record, ensure_ascii=False), flush=True)
    if timed_out or process.returncode not in allowed:
        raise RuntimeError(f"{label} returned {process.returncode}, timedOut={timed_out}: {raw[-5000:].decode('utf-8', 'replace')}")
    return process.returncode, raw

def git(*args, cwd=None):
    result = subprocess.run(["git", *args], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(f"git failed in {cwd or REPO}: {args!r}: {result.stderr.decode('utf-8', 'replace')[:4000]}")
    return result.stdout.decode("utf-8").strip()

def case(name, fn):
    row = {"name": name, "passed": False}
    try:
        row["result"] = fn()
        row["passed"] = True
    except Exception as error:
        row["error"] = str(error)
        row["traceback"] = traceback.format_exc()
    CASES.append(row)
    save("partial-cases.json", CASES)
    print(json.dumps(row, ensure_ascii=False), flush=True)
    return row

def source_bytes():
    actual = []
    for item in EXPECTED:
        data = (REPO / item["path"]).read_bytes()
        blob = hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()
        entry = git("ls-tree", SOURCE, "--", item["path"]).split()
        if len(entry) < 4 or entry[0] != item["mode"] or entry[2] != item["sha"]:
            raise RuntimeError("Frozen tree mode or blob mismatch: " + item["path"])
        row = {"path": item["path"], "mode": entry[0], "sha": blob, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        actual.append(row)
        if row != item:
            raise RuntimeError("Frozen candidate bytes changed: " + item["path"])
    return actual

def tracked_state(root):
    root = Path(root).resolve()
    names = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"]).split(b"\0")
    digest = hashlib.sha256()
    count = 0
    for raw_name in names:
        if not raw_name:
            continue
        name = os.fsdecode(raw_name)
        path = root / name
        digest.update(raw_name + b"\0")
        if path.is_symlink():
            value = os.fsencode(os.readlink(path))
            digest.update(b"symlink\0" + value + b"\0")
        elif path.is_file():
            digest.update(b"file\0")
            with path.open("rb") as stream:
                while True:
                    chunk = stream.read(1024 * 1024)
                    if not chunk:
                        break
                    digest.update(chunk)
            digest.update(b"\0")
        else:
            digest.update(b"missing\0")
        count += 1
    return {"root": str(root), "head": git("rev-parse", "HEAD", cwd=root),
            "tree": git("rev-parse", "HEAD^{tree}", cwd=root), "trackedFiles": count,
            "trackedSha256": digest.hexdigest(),
            "indexSha256": hashlib.sha256(subprocess.check_output(["git", "-C", str(root), "ls-files", "--stage", "-z"])).hexdigest(),
            "status": git("status", "--porcelain=v1", "--untracked-files=no", cwd=root)}

def roots():
    config_path = REPO / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    sdk = Path(shutil.which("flutter")).resolve().parent.parent
    result = {"flutter-sdk": sdk}
    available = {item["name"]: item for item in config["packages"]}
    packages = {}
    for name, expected_head in GIT_PINS.items():
        package = available[name]
        uri = urlparse(urljoin(config_path.as_uri(), package["rootUri"]))
        if uri.scheme != "file":
            raise RuntimeError("Resolved Git package is not a local exact checkout: " + name)
        path = Path(unquote(uri.path)).resolve()
        top = Path(git("rev-parse", "--show-toplevel", cwd=path)).resolve()
        head = git("rev-parse", "HEAD", cwd=top)
        if head != expected_head:
            raise RuntimeError("Resolved Git package differs from the exact locked revision: " + name)
        packages[name] = {"root": str(path), "gitRoot": str(top), "head": head}
        result[str(top)] = top
    if len(packages) != 19 or set(packages) != set(GIT_PINS):
        raise RuntimeError("The nineteen locked Git packages were not all observed")
    save("resolved-git-packages.json", packages)
    return result

def preserve_changes():
    _, diff = command(["git", "diff", "--binary", QA_HEAD, "--"], "source-mutations", allowed=(0,))
    _, index_diff = command(["git", "diff", "--cached", "--binary", QA_HEAD, "--"], "index-mutations", allowed=(0,))
    changed = git("diff", "--name-only", QA_HEAD, "--").splitlines()
    for name in changed:
        path = REPO / name
        if path.is_file():
            target = OUT / "mutated-source" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
    return {"worktreeChanged": changed, "worktreeDiffSha256": hashlib.sha256(diff).hexdigest(),
            "indexDiffSha256": hashlib.sha256(index_diff).hexdigest()}


class NoApiRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError("GitHub JSON API unexpectedly redirected")

def api(path):
    if not path.startswith("/repos/Otzaria/otzaria/"):
        raise RuntimeError("QA API path outside the repository")
    headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
               "User-Agent": "Otzaria-independent-4428-QA"}
    if API_TOKEN:
        headers["Authorization"] = "Bearer " + API_TOKEN
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
    own = [item for item in mapping if item["number"] == 4428]
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
    own = next(item for item in before["prs"] if item["number"] == 4428)
    common_paths = {f["path"] for f in own["files"]}
    delta_paths = {f["path"] for f in EXPECTED}
    result = [{"number": "dev", "head": before["dev"], "commonOverlap": [], "deltaOverlap": []}]
    for pr in before["prs"]:
        if pr["number"] == 4428:
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
        {"number": "apple-proposed-de019", "head": "de019fc88b93a6ec58dd80d6ab40cd26fd5c06e1", "commonOverlap": [], "deltaOverlap": [], "binding": "unpublished Apple native-hide repair under NEW independent QA"},
        {"number": "common-proposed-05e150", "head": "05e150d09758e0da45ca1877a4d650358f1aa17f", "commonOverlap": [], "deltaOverlap": [], "binding": "unpublished Windows/common repair under independent native QA"}
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

QA_HEAD = git("rev-parse", "HEAD")
if git("rev-parse", SOURCE + "^{tree}") != SOURCE_TREE:
    raise RuntimeError("Candidate tree does not match the frozen source")
qa_paths = set(git("diff", "--name-only", SOURCE, QA_HEAD).splitlines())
if qa_paths != {"tool/perf_probe/qa_4428_source_gates.py", ".github/workflows/qa_4428_source_gates.yml"}:
    raise RuntimeError("QA commit must add only its two declared QA files")
if git("rev-list", "--parents", "-n", "1", "HEAD").split()[1:] != [SOURCE]:
    raise RuntimeError("QA commit is not the sole direct child of frozen source")
for revision in (SOURCE, QA_HEAD):
    identity = git("show", "-s", "--format=%an%x00%ae%x00%cn%x00%ce", revision).split("\0")
    if identity != ["Y-Ploni", "7353755@gmail.com", "Y-Ploni", "7353755@gmail.com"]:
        raise RuntimeError("Candidate or QA author/committer identity differs")
if git("status", "--porcelain=v1"):
    raise RuntimeError("Initial application checkout is dirty")
if git("rev-parse", SOURCE + "^") != PUBLIC:
    raise RuntimeError("Candidate is not a direct child of the unchanged public PR head")
if set(git("diff", "--name-only", PUBLIC, SOURCE).splitlines()) != set(SOURCE_DELTA_PATHS):
    raise RuntimeError("Candidate delta differs from the exact four-path public delta")
save("binding.json", {"sourceCommit": SOURCE, "sourceTree": SOURCE_TREE, "publicHead": PUBLIC,
                      "qaHead": QA_HEAD, "mode": sys.argv[1], "sourceFiles": source_bytes(),
                      "historicalLocalResultsUsed": False})
app_before = tracked_state(REPO)
save("app-before.json", app_before)
command(["git", "log", "--oneline", "-20", SOURCE], "source-history")
command(["git", "log", "--oneline", "-20", SOURCE, "--", *SOURCE_DELTA_PATHS], "changed-path-history")

if sys.argv[1] == "hook":
    dependency_roots = None
    dependency_before = None
    sdk_before = tracked_state(Path(shutil.which("flutter")).resolve().parent.parent)
    save("sdk-before-resolution.json", sdk_before)
    if sdk_before["status"]:
        raise RuntimeError("Flutter SDK is modified before dependency resolution")
    try:
        def resolve():
            command(["flutter", "pub", "get", "--enforce-lockfile"], "strict-pub-get", timeout=900)
            source_bytes()
            sdk_after_resolution = tracked_state(Path(shutil.which("flutter")).resolve().parent.parent)
            save("sdk-after-resolution.json", sdk_after_resolution)
            if sdk_before != sdk_after_resolution:
                raise RuntimeError("Strict pub get modified Flutter tracked sources")
            _, raw = command(["flutter", "--version", "--machine"], "flutter-version", timeout=120)
            version = json.loads(raw)
            if version.get("frameworkVersion") != "3.47.7" or version.get("frameworkRevision") != "abaf9c523780a608bd46686fd5e53740a07077f8" or version.get("dartSdkVersion") != "3.13.5" or version.get("engineRevision") != "deb287481e3ce9468f3434937ced4240a70539ca":
                raise RuntimeError("SDK is not the approved exact Flutter/Dart build")
            return version
        resolved = case("Strict lock and exact SDK", resolve)
        if resolved["passed"]:
            dependency_roots = roots()
            dependency_before = {key: tracked_state(root) for key, root in dependency_roots.items()}
            save("dependency-before.json", dependency_before)
            if any(item["status"] for item in dependency_before.values()):
                raise RuntimeError("Resolved Git dependency or SDK checkout is modified before QA")
            dart_delta = git("diff", "--name-only", "--diff-filter=ACM", PUBLIC, SOURCE, "--", "*.dart").splitlines()
            if not dart_delta:
                raise RuntimeError("No real staged Dart candidate delta exists")
            save("candidate-dart-delta.json", dart_delta)
            formatted = case("Non-mutating format gate on actual candidate Dart delta",
                 lambda: command(["dart", "format", "--output=none", "--set-exit-if-changed", *dart_delta], "format", timeout=180)[0])
            def original_hook():
                if not formatted["passed"]:
                    raise RuntimeError("Original hook withheld because canonical format did not pass")
                command(["dart", "run", "tool/install_git_hooks.dart"], "install-original-hook", timeout=900)
                hook = Path(git("rev-parse", "--git-path", "hooks/pre-commit")).resolve()
                hook_bytes = hook.read_bytes()
                actual_hash = hashlib.sha256(hook_bytes).hexdigest()
                (OUT / "installed-pre-commit-hook.txt").write_bytes(hook_bytes)
                if actual_hash != HOOK_SHA256:
                    raise RuntimeError("Installed original hook bytes have the wrong SHA256")
                command(["git", "reset", "--soft", PUBLIC], "stage-real-candidate")
                try:
                    staged = git("diff", "--cached", "--name-only", "--diff-filter=ACM", "--", "*.dart").splitlines()
                    if set(staged) != set(dart_delta) or not staged:
                        raise RuntimeError("Original hook lacks the exact nonempty staged Dart delta")
                    save("staged-hook-binding.json", {"hookSha256": actual_hash, "stagedDartPaths": staged,
                                                    "headDuringHook": git("rev-parse", "HEAD"), "expectedPublic": PUBLIC})
                    command([str(hook)], "original-staged-hook", timeout=1200)
                    return {"hookSha256": actual_hash, "stagedDartPaths": staged}
                finally:
                    preserve_changes()
                    # This restores HEAD only; it intentionally preserves any formatter/index mutations.
                    command(["git", "reset", "--soft", QA_HEAD], "restore-qa-head")
            case("Exact original hook with nonempty staged candidate Dart files", original_hook)
            def full_analyze():
                source_bytes()
                return command(["flutter", "analyze", "--no-pub"], "full-analyze", timeout=600)[0]
            case("Full analysis of the exact frozen source", full_analyze)
            def prepare_store():
                store_root = OUT / "verified-store"
                command(["python3", "tool/perf_probe/prepare_installed_plugin_source.py",
                         "--output", str(store_root)], "prepare-verified-store", timeout=300)
                provenance = json.loads((store_root / "source-provenance.json").read_text(encoding="utf-8"))
                if provenance["commit"] != "4517d39c4ecab632aff98e1c0e414881695961aa":
                    raise RuntimeError("Prepared Store commit differs")
                for name, expected in provenance["sha256"].items():
                    if hashlib.sha256((store_root / name).read_bytes()).hexdigest() != expected:
                        raise RuntimeError("Prepared pinned Store bytes differ: " + name)
                if len(provenance["sha256"]) != 5:
                    raise RuntimeError("Store source inventory is incomplete")
                os.environ["INSTALLED_PROBE_STORE_SOURCE"] = str(store_root)
                save("prepared-store-binding.json", provenance)
                return provenance
            store_prepared = case("Prepare and verify exact pinned Store before all Store controls", prepare_store)
            def node_controls():
                if not store_prepared["passed"]:
                    raise RuntimeError("Store preparation did not pass")
                _, raw = command(["node", "--test", "tool/perf_probe/test_installed_plugin_fixture.mjs",
                                  "tool/perf_probe/test_installed_plugin_store.mjs"], "node-controls", timeout=180)
                text = raw.decode("utf-8", "replace")
                counts = {key: int(value) for key, value in re.findall(r"^# (tests|pass|fail|skipped|cancelled) (\d+)\s*$", text, re.MULTILINE)}
                if counts != {"tests": 10, "pass": 10, "fail": 0, "skipped": 0, "cancelled": 0}:
                    raise RuntimeError("Exact Node fixture/Store test totals differ: " + json.dumps(counts))
                return counts
            case("Actual Node fixture and prepared Store controls without skips", node_controls)
            def flutter_controls(paths, expected, label):
                if not store_prepared["passed"]:
                    raise RuntimeError("Store preparation did not pass")
                _, raw = command(["flutter", "test", "--no-pub", "--concurrency=1", "--reporter=json", *paths],
                                 label, timeout=900)
                started = {}
                finished = []
                for line in raw.decode("utf-8", "replace").splitlines():
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if event.get("type") == "testStart":
                        started[event["test"]["id"]] = event["test"]
                    if event.get("type") == "testDone" and not event.get("hidden", False):
                        finished.append({**event, "name": started.get(event["testID"], {}).get("name")})
                counts = {"total": len(finished),
                          "passed": sum(row.get("result") == "success" and not row.get("skipped") for row in finished),
                          "skipped": sum(bool(row.get("skipped")) for row in finished),
                          "tests": finished}
                save(label + "-counts.json", counts)
                if counts["total"] != expected or counts["passed"] != expected or counts["skipped"]:
                    raise RuntimeError("Exact Flutter controls did not all execute successfully: " + json.dumps(counts))
                return counts
            case("All fourteen actual Android allocation and authenticated control tests",
                 lambda: flutter_controls(["test/tool/perf_probe/installed_plugin_android_control_test.dart"], 14, "android-controls"))
            case("All forty-four existing Dart contracts including both formerly skipped Store tests",
                 lambda: flutter_controls(["test/tool/perf_probe/installed_plugin_probe_test.dart",
                                           "test/tool/perf_probe/perf_fixture_startup_settings_test.dart"], 44, "existing-controls"))
            def host_controls():
                _, raw = command(["python3", "-m", "unittest", "-v", "tool/perf_probe/test_installed_plugin_android.py"],
                                 "android-host-controls", timeout=300)
                text = raw.decode("utf-8", "replace")
                match = re.search(r"Ran (\d+) tests? in", text)
                if not match or int(match.group(1)) != 45 or "skipped=" in text:
                    raise RuntimeError("Expected all forty-five Android host controls to execute")
                return {"tests": 45, "passed": 45, "skipped": 0}
            case("Actual Android host negative controls", host_controls)
            def store_unchanged():
                provenance = json.loads((OUT / "prepared-store-binding.json").read_text(encoding="utf-8"))
                root = Path(os.environ["INSTALLED_PROBE_STORE_SOURCE"])
                for name, expected in provenance["sha256"].items():
                    if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
                        raise RuntimeError("Store source changed during tests: " + name)
                return {"files": 5, "commit": provenance["commit"], "unchanged": True}
            case("Prepared pinned Store bytes unchanged after tests", store_unchanged)
    finally:
        if git("rev-parse", "HEAD") != QA_HEAD:
            command(["git", "reset", "--soft", QA_HEAD], "restore-head-finally")
        if dependency_roots is not None:
            dependency_after = {key: tracked_state(root) for key, root in dependency_roots.items()}
            save("dependency-after.json", dependency_after)
            case("SDK and resolved dependency tracked sources unchanged",
                 lambda: True if dependency_before == dependency_after else (_ for _ in ()).throw(RuntimeError("SDK or dependency tracked files changed")))
        save("source-change-evidence.json", preserve_changes())

elif sys.argv[1] == "merge":
    initial_map, TARGETS = fresh_merge_targets()
    save("merge-targets.json", TARGETS)
    merge_rows = []
    cache = {}
    for target in TARGETS:
        sha = target["head"]
        if sha not in cache:
            command(["git", "fetch", "--no-tags", "origin", sha], "fetch-" + str(target["number"]), timeout=300)
            proof = {}
            for label, left in (("public", PUBLIC), ("candidate", SOURCE)):
                exit_code, raw = command(["git", "merge-tree", "--write-tree", left, sha],
                                         "merge-" + str(target["number"]) + "-" + label, allowed=(0, 1), timeout=180)
                text = raw.decode("utf-8", "replace")
                raw_conflicts = sorted(set(re.findall(r"^CONFLICT.*$", text, flags=re.MULTILINE)))
                # Only incidental commit labels are normalized in messages.
                conflicts = sorted({message.replace(left, "<left>").replace(sha, "<right>")
                                    for message in raw_conflicts})
                result_tree = text.splitlines()[0] if text.splitlines() else None
                proof[label] = {"head": left, "exitCode": exit_code, "resultTree": result_tree,
                                "conflicts": conflicts, "rawConflictMessages": raw_conflicts,
                                "rawSha256": hashlib.sha256(raw).hexdigest(),
                                "conflictEvidence": conflict_evidence(raw, result_tree, target["number"], label)
                                    if exit_code == 1 else {"stageEntries": [], "files": [], "totalHunks": 0}}
            cache[sha] = proof
        proof = cache[sha]
        old = set(proof["public"]["conflicts"])
        new = set(proof["candidate"]["conflicts"])
        same_content = same_conflict_content(proof["public"], proof["candidate"])
        row = {**target, **proof, "actualConflictContentUnchanged": same_content,
               "additionalConflictMessages": sorted(new - old),
               "resolvedConflictMessages": sorted(old - new),
               "classification": "MERGES_CLEANLY" if proof["candidate"]["exitCode"] == 0 else
                   ("PREEXISTING_CONFLICTS" if proof["public"]["exitCode"] == 1 and new == old and same_content else "NEW_OR_CHANGED_CONFLICTS")}
        merge_rows.append(row)
        save("merge-results-partial.json", merge_rows)
        print(json.dumps(row, ensure_ascii=False), flush=True)
    save("merge-results.json", merge_rows)
    def verify_merge_result():
        counts = {"targets": len(merge_rows), "uniqueHeads": len(cache),
                  "clean": sum(x["classification"] == "MERGES_CLEANLY" for x in merge_rows),
                  "preexisting": sum(x["classification"] == "PREEXISTING_CONFLICTS" for x in merge_rows),
                  "newOrChanged": sum(x["classification"] == "NEW_OR_CHANGED_CONFLICTS" for x in merge_rows),
                  "preexistingConflictsAreNotClaimedMergeable": True}
        final_map = public_snapshot(False)
        save("open-pr-map-after-merge.json", final_map)
        if snapshot_key(initial_map) != snapshot_key(final_map):
            raise RuntimeError("Open PR map changed while merge-tree proofs ran")
        counts["stableOpenPrCount"] = len(final_map["prs"])
        counts["unchangedConflictFiles"] = sum(len(row["candidate"]["conflictEvidence"]["files"]) for row in merge_rows if row["classification"] == "PREEXISTING_CONFLICTS")
        counts["unchangedConflictHunks"] = sum(row["candidate"]["conflictEvidence"]["totalHunks"] for row in merge_rows if row["classification"] == "PREEXISTING_CONFLICTS")
        if counts["newOrChanged"]:
            raise RuntimeError("Candidate adds or changes actual conflict content or normalized messages: " + json.dumps(counts))
        return counts
    case("Actual merge-tree evidence for every current overlap and dev", verify_merge_result)
else:
    raise RuntimeError("Unknown QA mode")

app_after = tracked_state(REPO)
save("app-after.json", app_after)
case("Application tracked source and index unchanged", lambda:
     True if app_before == app_after else (_ for _ in ()).throw(RuntimeError("Application tracked bytes, HEAD, or index changed; see preserved raw diff")))
case("Frozen ten source files remain byte exact", source_bytes)
summary = {"schemaVersion": 1, "sourceCommit": SOURCE, "sourceTree": SOURCE_TREE, "qaHead": QA_HEAD,
           "mode": sys.argv[1], "cases": CASES, "passed": all(x["passed"] for x in CASES),
           "historicalLocalResultsUsed": False, "fullApplicationAcceptance": "NOT_RUN_BY_THIS_JOB"}
save("summary.json", summary)
print("BEGIN_QA_4428_SOURCE_GATES_SUMMARY", flush=True)
print(json.dumps(summary, ensure_ascii=False), flush=True)
print("END_QA_4428_SOURCE_GATES_SUMMARY", flush=True)
sys.exit(0 if summary["passed"] else 1)
