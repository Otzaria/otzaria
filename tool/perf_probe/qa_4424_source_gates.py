#!/usr/bin/env python3
"""Independent, source-bound QA. This file is never part of PR 4424."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import time
import traceback
from urllib.parse import unquote, urljoin, urlparse
import urllib.request
from datetime import datetime, timezone

SOURCE = "f4ac011f1b8c81d4a760eeeadfe037228fb944e3"
SOURCE_TREE = "1767f0161e11567f3d4d0eb703d1bdeb1950272b"
PUBLIC = "2aa04e69f4b6802bd376aed41f529590a6c4f9b3"
HOOK_SHA256 = "53b75db342d0332ae703c389562adf65a04d6127bd1ff05edaef0dde7b020097"
EXPECTED = json.loads(r'''[{"path":"tool/perf_probe/installed_plugin_windows_lifetime.cs","mode":"100644","sha":"050e97ca46a728986468e7cbabf4a864156a7a70","bytes":19764,"sha256":"e373e8b5dcd6a17d925e52249050d9e99d0c0c1a04fa59523e8b1f86b30e4b15"},{"path":"tool/perf_probe/test_installed_plugin_windows_lifetime.cs","mode":"100644","sha":"d46736f77c8979b09ad84ca8bcce70653595e3ae","bytes":15375,"sha256":"bc93f45dbbd1646dd59a08c43f7e5f1f6c3a75a69345060dea610f766c930c04"},{"path":"pubspec.yaml","mode":"100644","sha":"26054b0dfe7533a25a33dbec92f875289fb8c7f9","bytes":13609,"sha256":"b900e75318dfb65333f97e8529c52dfe08df0893292e535700094da7ae8c6b51"},{"path":"pubspec.lock","mode":"100644","sha":"8a4569554fffc9ca5686633a58386d2c83487755","bytes":66487,"sha256":"94bf01c88e2568424d39a7da767ecdd70356c915f8636e0ccb233121bb6ef932"},{"path":"integration_test/support/installed_plugin_windows_lifetime.dart","mode":"100644","sha":"564f27327f440d4099054456589891acbca609f4","bytes":3701,"sha256":"d896f1580440e1fe726595b8d0afc64046a6480cbb0a949cf9a04c009c8a8173"},{"path":".github/workflows/installed_plugin_probe.yml","mode":"100644","sha":"d126a4d7e11646c9d8071c8d72f32746e16cfa96","bytes":7040,"sha256":"382f4f78f9b41fde647162d1058bec60d4df4ea4ad85cd48610cded77753b6d3"},{"path":"tool/perf_probe/installed_plugin_windows_control.psm1","mode":"100644","sha":"718bea8e88b1ec1c2623b5f2f12f779c66e24344","bytes":10454,"sha256":"dea8243fa148fc09168e0833ac36b77fac03486e0657d478b545c672d0d23d5f"},{"path":"tool/perf_probe/installed_plugin_windows_exit.psm1","mode":"100644","sha":"08811d95fe55e303a4b65c57d27a6aa93235c89b","bytes":15700,"sha256":"24140aa825be6d5c8b571a1798048a503a9909836222ee889843539f7ac335d7"},{"path":"tool/perf_probe/test_installed_plugin_windows_runner.ps1","mode":"100644","sha":"d2a576a91716044a5f9e2179075f11feba3cd6bc","bytes":12152,"sha256":"9f732afcc8093933db9402de470a1f34d0e55289c398589efecc616e5adc8b93"},{"path":"tool/perf_probe/installed_plugin_windows_runner.psm1","mode":"100644","sha":"55d3c081c030771a923bb509db6e2bad9ea5a937","bytes":10724,"sha256":"205ccece2043181621a9dae1a98db59d6df76b93b788a48e57cb3afc66c6e462"},{"path":"tool/perf_probe/run_installed_plugin_windows.ps1","mode":"100644","sha":"330129b3f178a4caecc05054ec9d2d4b515ae15b","bytes":586,"sha256":"edd23bafd7dd24ad7ffc4d090197610eed43c392e0050bc0b737fc8e4c7c0569"},{"path":"integration_test/installed_plugin_resource_probe_test.dart","mode":"100644","sha":"e73166c5c7e37515501bb8f6265b38df568780dd","bytes":53896,"sha256":"4f03d7f8f7a2cb94ed79590af5995b9f146077cceb7f49d688c41dceaf9d642e"},{"path":"tool/perf_probe/WEBVIEW_RESOURCE_PROBE.md","mode":"100644","sha":"5a5c69de8c717663a6777fe821521c6a9b7e629f","bytes":45250,"sha256":"f97230e81069bf3799f0229999c649c0e7f4a5c4fd23890c39030f8e4ef58fc3"},{"path":"test/tool/perf_probe/installed_plugin_windows_lifetime_test.dart","mode":"100644","sha":"069febc9ec2054e84cf9799291028ca50223ee8e","bytes":6462,"sha256":"de6b5d54e9839e8637b45e27fd48f338127eaaf0a7eac93f1952cb7eab413e15"},{"path":"tool/perf_probe/test_installed_plugin_windows_control.ps1","mode":"100644","sha":"ac580460a67166e47b3f7c15b71197d10fb02256","bytes":12208,"sha256":"157dff260b0c608be395193a8dde2d0821b45f029e82b8315ae8db2b5fe5a1da"},{"path":"tool/perf_probe/test_installed_plugin_windows_exit.ps1","mode":"100644","sha":"efbd35f85e4545718898d2a6b151cde1b2277669","bytes":19069,"sha256":"9741fb220c71af1b11580ea28a73a12abd02d3e896663fafa17c64f8c4d688c8"}]''')
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
    completed = subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    raw = completed.stdout
    (OUT / (label + ".log")).write_bytes(raw)
    record = {"command": [str(x) for x in args], "cwd": str(cwd or REPO),
              "exitCode": completed.returncode, "seconds": time.monotonic() - before,
              "outputSha256": hashlib.sha256(raw).hexdigest(), "outputBytes": len(raw)}
    save(label + ".json", record)
    print(json.dumps(record, ensure_ascii=False), flush=True)
    if completed.returncode not in allowed:
        raise RuntimeError(f"{label} returned {completed.returncode}: {raw[-5000:].decode('utf-8', 'replace')}")
    return completed.returncode, raw

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
            "status": git("status", "--porcelain=v1", "--untracked-files=no", cwd=root)}

def roots():
    config_path = REPO / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    sdk = Path(shutil.which("flutter")).resolve().parent.parent
    result = {"flutter-sdk": sdk}
    packages = {}
    required = {"flutter_inappwebview", "flutter_inappwebview_android", "flutter_inappwebview_ios",
                "flutter_inappwebview_linux", "flutter_inappwebview_macos", "flutter_inappwebview_platform_interface",
                "flutter_inappwebview_web", "flutter_inappwebview_windows"}
    webview_names = set()
    for package in config["packages"]:
        uri = urlparse(urljoin(config_path.as_uri(), package["rootUri"]))
        if uri.scheme != "file":
            continue
        path = Path(unquote(uri.path)).resolve()
        name = package["name"]
        if name in required:
            webview_names.add(name)
        if "/git/" in str(path) or name in required or name == "window_manager":
            top = Path(git("rev-parse", "--show-toplevel", cwd=path)).resolve()
            head = git("rev-parse", "HEAD", cwd=top)
            packages[name] = {"root": str(path), "gitRoot": str(top), "head": head}
            result[str(top)] = top
            if name in required and head != "c709de98711cf34350c48df4c75e24d0879d5876":
                raise RuntimeError("Unexpected WebView package commit: " + name)
            if name == "window_manager" and head != "88a433a7be43ed0213da12b561bf0d8d070c6d68":
                raise RuntimeError("Unexpected window_manager commit")
    if webview_names != required:
        raise RuntimeError(f"The eight WebView packages were not resolved exactly: {sorted(webview_names)}")
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
               "User-Agent": "Otzaria-independent-4424-QA"}
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
    own = [item for item in mapping if item["number"] == 4424]
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
    own = next(item for item in before["prs"] if item["number"] == 4424)
    common_paths = {f["path"] for f in own["files"]}
    delta_paths = {f["path"] for f in EXPECTED}
    result = [{"number": "dev", "head": before["dev"], "commonOverlap": [], "deltaOverlap": []}]
    for pr in before["prs"]:
        if pr["number"] == 4424:
            continue
        names = {f["path"] for f in pr["files"]} | {f["previousPath"] for f in pr["files"] if f["previousPath"]}
        common_overlap = sorted(names & common_paths)
        delta_overlap = sorted(names & delta_paths)
        if common_overlap or delta_overlap:
            result.append({"number": pr["number"], "head": pr["head"],
                           "commonOverlap": common_overlap, "deltaOverlap": delta_overlap})
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
if qa_paths != {"tool/perf_probe/qa_4424_source_gates.py", ".github/workflows/qa_4424_source_gates.yml", "tool/perf_probe/qa_4424_independent.ps1"}:
    raise RuntimeError("QA commit must add only its three declared QA files")
if git("rev-parse", "HEAD^") != SOURCE:
    raise RuntimeError("QA commit is not a direct child of frozen source")
if git("status", "--porcelain=v1"):
    raise RuntimeError("Initial application checkout is dirty")
if git("rev-parse", SOURCE + "^") != PUBLIC:
    raise RuntimeError("Candidate is not a direct child of the unchanged public PR head")
if set(git("diff", "--name-only", PUBLIC, SOURCE).splitlines()) != {item["path"] for item in EXPECTED}:
    raise RuntimeError("Candidate delta differs from the exact sixteen-file manifest")
save("binding.json", {"sourceCommit": SOURCE, "sourceTree": SOURCE_TREE, "publicHead": PUBLIC,
                      "qaHead": QA_HEAD, "mode": sys.argv[1], "sourceFiles": source_bytes(),
                      "historicalLocalResultsUsed": False})
app_before = tracked_state(REPO)
save("app-before.json", app_before)

if sys.argv[1] == "hook":
    dependency_roots = None
    dependency_before = None
    sdk_before = tracked_state(Path(shutil.which("flutter")).resolve().parent.parent)
    save("sdk-before-resolution.json", sdk_before)
    if sdk_before["status"]:
        raise RuntimeError("Flutter SDK is modified before dependency resolution")
    try:
        def resolve():
            command(["flutter", "pub", "get", "--enforce-lockfile"], "strict-pub-get", timeout=600)
            source_bytes()
            sdk_after_resolution = tracked_state(Path(shutil.which("flutter")).resolve().parent.parent)
            save("sdk-after-resolution.json", sdk_after_resolution)
            if sdk_before != sdk_after_resolution:
                raise RuntimeError("Strict pub get modified Flutter tracked sources")
            _, raw = command(["flutter", "--version", "--machine"], "flutter-version", timeout=120)
            version = json.loads(raw)
            if version.get("frameworkRevision") != "abaf9c523780a608bd46686fd5e53740a07077f8" or version.get("dartSdkVersion") != "3.13.5" or version.get("engineRevision") != "deb287481e3ce9468f3434937ced4240a70539ca":
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
            case("Non-mutating format gate on actual candidate Dart delta",
                 lambda: command(["dart", "format", "--output=none", "--set-exit-if-changed", *dart_delta], "format", timeout=180)[0])
            def original_hook():
                command(["dart", "run", "tool/install_git_hooks.dart"], "install-original-hook", timeout=180)
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
                    command([str(hook)], "original-staged-hook", timeout=600)
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
case("Frozen sixteen source files remain byte exact", source_bytes)
summary = {"schemaVersion": 1, "sourceCommit": SOURCE, "sourceTree": SOURCE_TREE, "qaHead": QA_HEAD,
           "mode": sys.argv[1], "cases": CASES, "passed": all(x["passed"] for x in CASES),
           "historicalLocalResultsUsed": False, "fullApplicationAcceptance": "NOT_RUN_BY_THIS_JOB"}
save("summary.json", summary)
print("BEGIN_QA_4424_SOURCE_GATES_SUMMARY", flush=True)
print(json.dumps(summary, ensure_ascii=False), flush=True)
print("END_QA_4424_SOURCE_GATES_SUMMARY", flush=True)
sys.exit(0 if summary["passed"] else 1)
