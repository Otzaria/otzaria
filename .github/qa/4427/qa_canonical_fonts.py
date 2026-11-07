#!/usr/bin/env python3
"""Independent source-bound canonical iOS QA; artifact contents are data only."""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import time
import traceback
import urllib.parse
import urllib.request
import zipfile

sys.dont_write_bytecode = True
ROOT = Path.cwd().resolve()
OUT = Path(os.environ["QA_EVIDENCE_DIR"]).resolve()
OUT.mkdir(parents=True, exist_ok=False)
TOKEN = os.environ.pop("QA_GITHUB_TOKEN", "")
os.environ.pop("GH_TOKEN", None)
os.environ.pop("GITHUB_TOKEN", None)
REPO = "Otzaria/otzaria"
SOURCE = "ca0adb7a91f3dc028a41ecbf894237d6bebbc523"
TREE = "7ede4702b7525247e81f28278807fbd63a8e1526"
PUBLIC = "326d693129fb36a0d8093f6107c058c1861370ac"
PREVIOUS = "5dcd64785d2154df33faf0def6f0f30c20f04c53"
PREVIOUS_TREE = "6e76b5c0c2f9f7549ea98f60a39e257315d7bd21"
NATIVE_HEAD = "f3a5e876dd5a5b83d19943e59787980c55986a60"
NATIVE_TREE = "3a2e1e13acd29c94f2734daa44ff0c859046d48f"
NATIVE_RUN = 42330160207
MAC_HEAD = "0db2a3b77f1bb812a2743efd7ae5a9a6549e81a5"
MAC_TREE = "1c9f0dcf2005cf98ef049350c584cd02d33cbf61"
MAC_RUN = 42324522366
REPAIR_PATHS = {
    "ios/Runner.xcodeproj/project.pbxproj",
    "ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme",
}
QA_PATHS = {".github/qa/4427/qa_canonical_fonts.py", ".github/workflows/qa_4427_canonical.yml"}
FILES = [{"path":"tool/perf_probe/validate_ios_plugin_fonts.py","sha":"371060c2636c90da6f58f1ebe25818c602c5bf28","sha256":"58081242bb0f8eee567fdc9c149cb43b8f94443d5087d2e2582b24369f468288","bytes":31172,"mode":"100644"},{"path":"integration_test/support/apple_font_probe_view.dart","sha":"40afc331e2bab483f94bfb80eaa16ede0b0c7ca8","sha256":"c425da1db13672cec56ab035bf0dbf9bc0b81c0cdaffc5fcd95198c1be217ead","bytes":19438,"mode":"100644"},{"path":"tool/perf_probe/test_ios_plugin_fonts_report.py","sha":"3233184a26011b5d4d2c390ae132b81025af8003","sha256":"21063c56e61bb853ddc9daebc2eb12b9816718d260237a1c7519e7f419c41c6f","bytes":33513,"mode":"100644"},{"path":"tool/perf_probe/run_ios_plugin_fonts.py","sha":"c9796cd4fe574fc654878e443895f4fd4a79e8aa","sha256":"e7f80139ec72973371c566be2ec6a2459d1b9b641b659b8138f9fc73827de5c1","bytes":24115,"mode":"100644"},{"path":"tool/perf_probe/test_ios_plugin_fonts_runner.py","sha":"1d14e23df93dda55349ab2a651fc02790f277a2b","sha256":"6926799a1ac260148a56d4a08d121c52a6b67990b2342d24dcef8d3e52de1444","bytes":42453,"mode":"100644"},{"path":"tool/perf_probe/test_macos_plugin_fonts.mjs","sha":"9f99d52b4ba83c90f56874c8cc8201fc451a314e","sha256":"99b0adf721538a2013e79dfa2419c3ccac3e53a702b8ea7e955802fed8e4b1c0","bytes":19085,"mode":"100644"},{"path":"ios/Runner.xcodeproj/project.pbxproj","sha":"b5f0f0c700d3933e762d38c3d706b2ce3af9d82a","sha256":"cba33ded34fa00b8f1aacfc0da74126aac3085256c2e44ce06fed7ec5c81374f","bytes":31892,"mode":"100644"},{"path":"ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme","sha":"c3fedb29c990d9c5a66b9f4ffb198b0ca3ce2ce5","sha256":"9fbce429f56243561dd437a527136c9f9ed77165e3b271b923faf236cfcd0484","bytes":4717,"mode":"100644"}]
GATES = []
DETAILS = {}
QA_HEAD = None

def digest(data):
    return hashlib.sha256(data).hexdigest()

def blob_hash(data):
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()

def save(name, value):
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n")

def read_json(path):
    def invalid(value):
        raise ValueError("Non-JSON number: " + value)
    return json.loads(path.read_text(), parse_constant=invalid)

def command(label, args, timeout=180, allowed=(0,)):
    started = time.monotonic()
    result = subprocess.run(args, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    (OUT / (label + ".log")).write_bytes(result.stdout)
    receipt = {"command": [str(a) for a in args], "returncode": result.returncode,
               "seconds": time.monotonic() - started, "outputSha256": digest(result.stdout),
               "outputBytes": len(result.stdout)}
    save(label + ".json", receipt)
    if result.returncode not in allowed:
        raise RuntimeError(label + " failed: " + result.stdout[-5000:].decode("utf-8", "replace"))
    return result.returncode, result.stdout

def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode().strip()

def gate(name, operation):
    result = {"name": name, "status": "failed"}
    try:
        result["result"] = operation()
        result["status"] = "passed"
    except Exception as error:
        result["error"] = {"type": type(error).__name__, "message": str(error), "traceback": traceback.format_exc()}
    GATES.append(result)
    save("partial-gates.json", GATES)
    print(json.dumps({"gate": name, "status": result["status"], "error": result.get("error")}), flush=True)
    return result

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urllib.parse.urlsplit(newurl).scheme != "https":
            raise RuntimeError("Artifact redirect is not HTTPS")
        result = super().redirect_request(req, fp, code, msg, headers, newurl)
        if result is not None and urllib.parse.urlsplit(newurl).netloc != urllib.parse.urlsplit(req.full_url).netloc:
            result.remove_header("Authorization")
        return result

def api(path, binary=False):
    if not path.startswith("/") or path.startswith("//"):
        raise RuntimeError("Invalid repository API path")
    headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"}
    if TOKEN:
        headers["Authorization"] = "Bearer " + TOKEN
    request = urllib.request.Request("https://api.github.com/repos/" + REPO + path, headers=headers)
    with urllib.request.build_opener(SafeRedirect()).open(request, timeout=60) as response:
        raw = response.read(64 * 1024 * 1024 + 1)
    if len(raw) > 64 * 1024 * 1024:
        raise RuntimeError("Bounded API response exceeded")
    return raw if binary else json.loads(raw)

def pages(path, key=None):
    values = []
    for page in range(1, 51):
        separator = "&" if "?" in path else "?"
        value = api(path + separator + "per_page=100&page=" + str(page))
        rows = value[key] if key else value
        if not isinstance(rows, list):
            raise RuntimeError("Expected paginated list")
        values.extend(rows)
        if len(rows) < 100:
            return values
    raise RuntimeError("Pagination bound exceeded")

def ensure_commit(sha, label):
    result = subprocess.run(["git", "cat-file", "-e", sha + "^{commit}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if result.returncode:
        command("fetch-" + label, ["git", "fetch", "--no-tags", "origin", sha], timeout=240)

def tree_entries(sha):
    raw = subprocess.check_output(["git", "ls-tree", "-r", "-z", sha], cwd=ROOT)
    result = {}
    for item in raw.split(b"\0"):
        if not item:
            continue
        info, name = item.split(b"\t", 1)
        mode, kind, blob = info.decode().split()
        result[name.decode()] = {"mode": mode, "type": kind, "sha": blob}
    return result

def worktree_snapshot():
    files = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).split(b"\0")
    result = {}
    for raw in files:
        if not raw:
            continue
        name = os.fsdecode(raw)
        path = ROOT / name
        if path.is_symlink():
            data, kind = os.fsencode(os.readlink(path)), "symlink"
        else:
            data, kind = path.read_bytes(), "file"
        result[name] = {"kind": kind, "bytes": len(data), "sha256": digest(data)}
    return {"head": git("rev-parse", "HEAD"), "tree": git("rev-parse", "HEAD^{tree}"),
            "status": git("status", "--porcelain=v1", "--untracked-files=all"), "files": result}

def source_binding():
    global QA_HEAD
    QA_HEAD = git("rev-parse", "HEAD")
    assert git("rev-parse", "HEAD^") == SOURCE
    assert git("rev-parse", SOURCE + "^{tree}") == TREE
    assert git("rev-parse", SOURCE + "^") == PUBLIC
    assert set(git("diff", "--name-only", SOURCE, QA_HEAD).splitlines()) == QA_PATHS
    assert not git("status", "--porcelain=v1", "--untracked-files=all")
    ensure_commit(PREVIOUS, "previous-source")
    assert git("rev-parse", PREVIOUS + "^{tree}") == PREVIOUS_TREE
    old, new = tree_entries(PREVIOUS), tree_entries(SOURCE)
    ensure_commit(MAC_HEAD, "prior-mac-native-qa")
    ensure_commit(NATIVE_HEAD, "current-ios-native-qa")
    assert git("rev-parse", MAC_HEAD + "^{tree}") == MAC_TREE
    assert git("rev-parse", MAC_HEAD + "^") == PREVIOUS
    assert git("rev-parse", NATIVE_HEAD + "^{tree}") == NATIVE_TREE
    assert git("rev-parse", NATIVE_HEAD + "^") == SOURCE
    mac_tree, native_tree = tree_entries(MAC_HEAD), tree_entries(NATIVE_HEAD)
    mac_extra = {p for p in old.keys() | mac_tree.keys() if old.get(p) != mac_tree.get(p)}
    native_extra = {p for p in new.keys() | native_tree.keys() if new.get(p) != native_tree.get(p)}
    assert mac_extra == {".github/workflows/qa_4427_ios_fonts.yml", ".github/workflows/qa_4427_macos_fonts.yml"}
    assert mac_tree[".github/workflows/qa_4427_ios_fonts.yml"]["sha"] == "58ffa595e7a3aee1e838b365f133a41fbdb9a0ea"
    assert mac_tree[".github/workflows/qa_4427_macos_fonts.yml"]["sha"] == "e63a6f01ca9b149c6bc8bb10a09eb115507a75c4"
    assert native_extra == {".github/workflows/qa_4427_ios_fonts.yml"}
    assert native_tree[".github/workflows/qa_4427_ios_fonts.yml"]["sha"] == "0ec3882e6f834440af3e9b5cc08d9073e5dd324d"
    changed = {path for path in old.keys() | new.keys() if old.get(path) != new.get(path)}
    assert changed == REPAIR_PATHS, sorted(changed)
    checked = []
    for item in FILES:
        data = (ROOT / item["path"]).read_bytes()
        actual = {"path": item["path"], "mode": new[item["path"]]["mode"], "sha": blob_hash(data),
                  "sha256": digest(data), "bytes": len(data)}
        assert actual == item, actual
        assert new[item["path"]]["sha"] == item["sha"]
        checked.append(actual)
    result = {"source": SOURCE, "tree": TREE, "publicParent": PUBLIC, "qaHead": QA_HEAD,
              "sourceFiles": checked, "allTreeEntries": len(new),
              "onlyChangedSincePrevious": sorted(changed), "allOtherEntriesExact": True}
    save("source-binding.json", result)
    DETAILS["binding"] = result
    return result

def snapshot_prs(include_files):
    pulls = pages("/pulls?state=open")
    result = []
    for pull in pulls:
        row = {"number": pull["number"], "head": pull["head"]["sha"], "base": pull["base"]["sha"],
               "baseRef": pull["base"]["ref"]}
        if include_files:
            row["files"] = [{"path": p["filename"], "previousPath": p.get("previous_filename"), "status": p["status"]}
                            for p in pages("/pulls/" + str(pull["number"]) + "/files")]
        result.append(row)
    dev = api("/git/ref/heads/dev")["object"]["sha"]
    own = [row for row in result if row["number"] == 4427]
    assert len(own) == 1 and own[0]["head"] == PUBLIC, "Public PR changed during QA"
    return {"dev": dev, "prs": sorted(result, key=lambda item: item["number"])}

def map_identity(snapshot):
    return {"dev": snapshot["dev"], "prs": [{k: p[k] for k in ("number", "head", "base", "baseRef")} for p in snapshot["prs"]]}

def conflict_details(raw, tree, label):
    text = raw.decode("utf-8")
    entries = []
    for line in text.splitlines()[1:]:
        match = re.fullmatch(r"([0-7]{6}) ([0-9a-f]{40}) ([123])\t(.+)", line)
        if match:
            mode, sha, stage, path = match.groups()
            assert not path.startswith('"'), "Quoted path requires explicit diagnosis"
            entries.append({"path": path, "mode": mode, "sha": sha, "stage": int(stage)})
    assert entries, "Conflicted merge has no parseable stage evidence"
    files = []
    for path in sorted({item["path"] for item in entries}):
        assert not PurePosixPath(path).is_absolute() and ".." not in PurePosixPath(path).parts
        row = git("ls-tree", tree, "--", path)
        if not row:
            files.append({"path": path, "exists": False})
            continue
        info, observed_path = row.split("\t", 1)
        mode, kind, sha = info.split()
        assert kind == "blob" and observed_path == path
        data = subprocess.check_output(["git", "cat-file", "blob", sha], cwd=ROOT)
        try:
            content = data.decode("utf-8")
            normalized = re.sub(r"^(<{7}|>{7}|\|{7})(?: [^\r\n]*)?$", r"\1", content, flags=re.MULTILINE).encode()
            hunks = len(re.findall(r"^<{7}(?: |$)", content, re.MULTILINE))
        except UnicodeDecodeError:
            normalized, hunks = data, None
        output = OUT / "conflicts" / label / path
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(data)
        output.with_name(output.name + ".normalized").write_bytes(normalized)
        files.append({"path": path, "exists": True, "mode": mode, "bytes": len(data), "sha": sha,
                      "normalizedSha256": digest(normalized), "normalizedBytes": len(normalized), "hunks": hunks})
    return {"stages": sorted(entries, key=lambda row: (row["path"], row["stage"])), "files": files}

def merge_proofs():
    before = snapshot_prs(True)
    after = snapshot_prs(False)
    save("open-pr-map-before.json", before)
    assert map_identity(before) == map_identity(after), "PR map changed during file reads"
    own = next(row for row in before["prs"] if row["number"] == 4427)
    ensure_commit(own["base"], "public-stack-base")
    scope = set(git("diff", "--name-only", own["base"], SOURCE).splitlines())
    targets = {"dev": before["dev"], "public-stack-base": own["base"]}
    overlaps = []
    for row in before["prs"]:
        if row["number"] == 4427:
            continue
        names = {f["path"] for f in row["files"]} | {f["previousPath"] for f in row["files"] if f["previousPath"]}
        overlap = sorted(scope & names)
        if overlap:
            targets["PR-" + str(row["number"])] = row["head"]
            overlaps.append({"number": row["number"], "head": row["head"], "paths": overlap})
        if row["number"] in (4421, 4425):
            targets["public-" + str(row["number"])] = row["head"]
    targets["proposed-Apple-0aa78"] = "0aa78eb2ab4540a100ccb9f97f5b5a773e8412cd"
    targets["proposed-common-f4ac"] = "f4ac011f1b8c81d4a760eeeadfe037228fb944e3"
    save("merge-scope.json", {"scope": sorted(scope), "targets": targets, "overlaps": overlaps})
    rows, cache = [], {}
    for label, sha in targets.items():
        ensure_commit(sha, label)
        if sha not in cache:
            proofs = {}
            for kind, left in (("public", PUBLIC), ("reviewed", PREVIOUS), ("candidate", SOURCE)):
                code, raw = command("merge-" + label + "-" + kind,
                                    ["git", "-c", "core.quotepath=false", "merge-tree", "--write-tree", left, sha],
                                    allowed=(0, 1))
                tree = raw.decode().splitlines()[0]
                assert re.fullmatch("[0-9a-f]{40}", tree)
                conflicts = sorted({line.replace(left, "<left>").replace(sha, "<right>")
                                    for line in raw.decode().splitlines() if line.startswith("CONFLICT")})
                proofs[kind] = {"source": left, "exitCode": code, "tree": tree, "rawSha256": digest(raw),
                                "messages": conflicts, "details": conflict_details(raw, tree, label + "-" + kind) if code else None}
            cache[sha] = proofs
        proofs = cache[sha]
        accepted = proofs["candidate"]["exitCode"] == 0
        classification = "clean" if accepted else "changed-conflicts-require-review"
        if not accepted:
            for baseline in ("public", "reviewed"):
                b, c = proofs[baseline], proofs["candidate"]
                if b["exitCode"] != 1 or b["messages"] != c["messages"]:
                    continue
                fields = ("path", "exists", "mode", "normalizedSha256", "normalizedBytes", "hunks")
                simplify = lambda value: {"stages": value["stages"], "files": [
                    {k: f[k] for k in fields if k in f} for f in value["files"]]}
                if simplify(b["details"]) == simplify(c["details"]):
                    accepted, classification = True, "exact-preexisting-conflicts-vs-" + baseline
                    break
        rows.append({"label": label, "head": sha, "accepted": accepted, "classification": classification, "proofs": proofs})
        save("merge-proof-partial.json", rows)
    final = snapshot_prs(False)
    save("open-pr-map-after.json", final)
    assert map_identity(before) == map_identity(final), "PR map changed during merge proofs"
    save("merge-proofs.json", rows)
    assert all(row["accepted"] for row in rows), "A candidate merge has new or changed actual conflicts"
    return {"openPrCount": len(before["prs"]), "stableMap": True, "targets": len(rows),
            "uniqueHeads": len(cache), "actualComparisons": 3 * len(cache),
            "results": [{"label": row["label"], "head": row["head"], "classification": row["classification"]} for row in rows],
            "preexistingConflictsNotClaimedMergeable": True}

def hashes(root):
    return {str(path.relative_to(root)): digest(path.read_bytes())
            for path in sorted(root.rglob("*")) if path.is_file()}

def extract_artifact(metadata, run, head, label, fixed=None):
    assert metadata["workflow_run"]["id"] == run and metadata["workflow_run"]["head_sha"] == head
    assert not metadata["expired"] and 0 < metadata["size_in_bytes"] <= 64 * 1024 * 1024
    expected = metadata["digest"]
    assert re.fullmatch(r"sha256:[0-9a-f]{64}", expected)
    if fixed:
        assert (metadata["id"], metadata["size_in_bytes"], expected) == fixed
    raw = api("/actions/artifacts/" + str(metadata["id"]) + "/zip", binary=True)
    assert len(raw) == metadata["size_in_bytes"] and "sha256:" + digest(raw) == expected
    archive = OUT / (label + ".zip")
    archive.write_bytes(raw)
    root = OUT / label
    root.mkdir()
    names = set()
    with zipfile.ZipFile(archive) as zipped:
        assert len(zipped.infolist()) < 2000 and sum(f.file_size for f in zipped.infolist()) < 512 * 1024 * 1024
        for item in zipped.infolist():
            path = PurePosixPath(item.filename)
            assert not path.is_absolute() and ".." not in path.parts and "\\" not in item.filename
            assert item.filename not in names and not stat.S_ISLNK(item.external_attr >> 16)
            names.add(item.filename)
            if item.is_dir():
                continue
            target = root.joinpath(*path.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(zipped.read(item))
    before = hashes(root)
    save(label + "-hashes-before.json", before)
    return root, before

def source_api(sha, tree, parent):
    commit = api("/git/commits/" + sha)
    assert commit["sha"] == sha and commit["tree"]["sha"] == tree
    assert [p["sha"] for p in commit["parents"]] == [parent]
    return {"head": sha, "tree": tree, "parent": parent}

def native_artifacts():
    sys.path.insert(0, str(ROOT / "tool/perf_probe"))
    import validate_ios_plugin_fonts as V
    import compare_macos_plugin_fonts as M
    assert digest((ROOT / "tool/perf_probe/compare_macos_plugin_fonts.py").read_bytes()) == "d94749c424ba645b5377d61b79764205075154143fcf06dcf02caa28d8d63e82"
    source_api(NATIVE_HEAD, NATIVE_TREE, SOURCE)
    source_api(MAC_HEAD, MAC_TREE, PREVIOUS)
    mac_results = []
    mac_specs = [
        (1, 13554393922, 102254, "5b292b185d206dc740277023683e79cd3a629c40236d888cd244d0e6d196cd2c"),
        (5, 13555405832, 443383, "d8b7430ffb24b69f0aeca61172b1d36c6121f6d021b5406e3a1e647fa2c4b676"),
        (10, 13555492309, 871027, "0b10113431058c9f6f9cb0f9bf6b67679cbc658b9a1cb970347982d532b55523"),
    ]
    mac_run = api("/actions/runs/" + str(MAC_RUN))
    assert mac_run["head_sha"] == MAC_HEAD and mac_run["status"] == "completed" and mac_run["conclusion"] == "success"
    mac_jobs = pages("/actions/runs/" + str(MAC_RUN) + "/jobs", key="jobs")
    assert len(mac_jobs) == 4 and all(j["conclusion"] == "success" for j in mac_jobs)
    save("mac-run-jobs.json", mac_jobs)
    for count, artifact_id, size, sha in mac_specs:
        metadata = api("/actions/artifacts/" + str(artifact_id))
        label = "macos-" + str(count)
        root, before = extract_artifact(metadata, MAC_RUN, MAC_HEAD, label, (artifact_id, size, "sha256:" + sha))
        paths = list(root.rglob("report.json"))
        assert len(paths) == 2
        reports, png_count, pngs, report_hashes = {}, 0, {}, {}
        for path in paths:
            envelope = read_json(path)
            report = envelope["fontProbe"]
            mode = report["requestedTransport"]
            assert mode not in reports and report["instances"] == count
            reports[mode] = report
            report_hashes[mode] = digest(path.read_bytes())
            for case in report["cases"]:
                for view in case["views"]:
                    if case["scenario"] == "style-src-none":
                        continue
                    filename = view["screenshot"]
                    assert filename == str(case["scenario"]) + "-" + str(view["index"]) + ".png"
                    assert re.fullmatch(r"[a-z0-9-]+\.png", filename)
                    data = (path.parent / filename).read_bytes()
                    V.validate_png(data)
                    pngs[str((path.parent / filename).relative_to(root))] = digest(data)
                    png_count += 1
        assert set(reports) == {"data", "scheme"}
        result = M.validate_pair(reports["data"], reports["scheme"])
        assert png_count == 4 * count
        assert hashes(root) == before
        row = {"views": count, "artifactId": artifact_id, "zipBytes": size, "zipSha256": sha,
               "sourceCandidate": PREVIOUS, "sourceQaHead": MAC_HEAD, "sourceQaTree": MAC_TREE,
               "evidenceReuse": "All 4203 non-repaired tree entries, including every macOS/runtime/validator/dependency file, are byte-and-mode identical",
               "reports": report_hashes, "caseViews": 6 * count, "nativePngCount": png_count, "pngHashes": pngs,
               "rawFrameworkScreenshotComparison": "NOT_AVAILABLE_IN_MAC_ARTIFACT; CRC and report-named PNG bytes verified",
               "semanticValidation": result, "unchangedArtifactFiles": len(before)}
        save(label + "-validation.json", row)
        mac_results.append(row)
    DETAILS["macos"] = mac_results
    save("macos-validation.json", mac_results)
    deadline = time.monotonic() + 55 * 60
    while True:
        run = api("/actions/runs/" + str(NATIVE_RUN))
        assert run["head_sha"] == NATIVE_HEAD
        if run["status"] == "completed":
            break
        assert time.monotonic() < deadline, "Fresh native run did not complete within bounded QA wait"
        print(json.dumps({"waitingForNativeRun": NATIVE_RUN, "status": run["status"]}), flush=True)
        time.sleep(20)
    jobs = pages("/actions/runs/" + str(NATIVE_RUN) + "/jobs", key="jobs")
    artifacts = pages("/actions/runs/" + str(NATIVE_RUN) + "/artifacts", key="artifacts")
    save("ios-run-final.json", run)
    save("ios-jobs-final.json", jobs)
    save("ios-artifacts-final.json", artifacts)
    ios_results = []
    for count in (1, 5, 10):
        name = "ios-plugin-fonts-debug-" + str(count) + "-views"
        matches = [a for a in artifacts if a["name"] == name]
        if len(matches) != 1:
            ios_results.append({"views": count, "status": "failed", "error": "Missing or duplicate native artifact"})
            continue
        metadata = matches[0]
        label = "ios-" + str(count)
        root, before = extract_artifact(metadata, NATIVE_RUN, NATIVE_HEAD, label)
        row = {"views": count, "artifactId": metadata["id"], "zipBytes": metadata["size_in_bytes"],
               "zipSha256": metadata["digest"].removeprefix("sha256:"), "status": "failed"}
        try:
            env_paths, report_paths = list(root.rglob("environment.json")), list(root.rglob("report.json"))
            assert len(env_paths) == 1, "Exactly one environment is required"
            env_path = env_paths[0]
            environment = V.read_json(env_path)
            diagnostic_keys = ("captureStatus", "runStatus", "sourceCommit", "sourceTree", "sourceStatus", "sourceStatusAfter",
                               "flutterSourceStatus", "flutterSourceStatusAfter", "primaryFailure", "secondaryErrors",
                               "error", "simulatorOwnership", "drive", "sourceDiffAfter")
            row["environmentDiagnostic"] = {k: environment.get(k) for k in diagnostic_keys}
            diffs = []
            for path in root.rglob("*"):
                if path.is_file() and "diff" in path.name.lower() and path.suffix == ".log":
                    data = path.read_bytes()
                    assert len(data) <= 256 * 1024
                    diffs.append({"path": str(path.relative_to(root)), "sha256": digest(data), "text": data.decode("utf-8", "replace")})
            row["sourceDiffs"] = diffs
            assert environment["sourceCommit"] == environment["sourceCommitAfter"] == NATIVE_HEAD
            assert environment["sourceTree"] == environment["sourceTreeAfter"] == NATIVE_TREE
            assert environment["webviewPin"] == "c709de98711cf34350c48df4c75e24d0879d5876"
            assert environment["enginePin"] == "2da23091237ed0f0a612de3b2d18cfc99d8b7d2a"
            assert not environment.get("error") and not environment.get("primaryFailure") and not environment.get("secondaryErrors")
            assert len(report_paths) == 1, "Exactly one completed native framework report is required"
            report_path = report_paths[0]
            envelope = V.read_json(report_path)
            result = V.validate_artifacts(report_path, environment, env_path.parent)
            probe = envelope["data"]["iosFontProbe"]
            assert probe["instances"] == count and len(probe["cases"]) == 18
            assert environment["lockSourceBlob"] == git("rev-parse", SOURCE + ":pubspec.lock")
            ownership = environment["simulatorOwnership"]
            assert ownership["device"] == environment["runtime"]["device"]["udid"]
            if ownership["owned"]:
                assert ownership["released"] is True and ownership["bootReturncode"] == 0 and ownership["shutdownReturncode"] == 0
            else:
                assert environment["runtime"]["device"]["state"] == "Booted" and ownership["released"] is False
            pngs = {}
            for case in probe["cases"]:
                assert len(case["views"]) == count
                for view in case["views"]:
                    if case["scenario"] == "style-src-none":
                        continue
                    path = report_path.parent / view["screenshot"]
                    pngs[str(path.relative_to(root))] = digest(path.read_bytes())
            assert len(pngs) == 12 * count
            job_matches = [j for j in jobs if j["name"] == "Actual iOS Simulator debug (" + str(count) + " views)"]
            assert len(job_matches) == 1 and job_matches[0]["conclusion"] == "success"
            row.update(status="passed", jobId=job_matches[0]["id"], sourceCandidate=SOURCE, sourceQaHead=NATIVE_HEAD,
                       sourceQaTree=NATIVE_TREE, reportSha256=digest(report_path.read_bytes()),
                       frameworkSha256=digest((report_path.parent / "framework-response.json").read_bytes()),
                       cases=18, caseViews=18 * count, nativePngCount=len(pngs), pngHashes=pngs,
                       nativePngBytesMatchRawFramework=True, semanticValidation=result,
                       sourceCleanBeforeAfter=True, sdkAndNineNativeSourcesCleanBeforeAfter=True,
                       simulatorOwnership=ownership, production="OFF", physicalProfileRelease="NOT_RUN")
        except Exception as error:
            row["error"] = {"type": type(error).__name__, "message": str(error), "traceback": traceback.format_exc()}
        finally:
            after = hashes(root)
            assert after == before, "Artifact files changed during independent validation"
            row["unchangedArtifactFiles"] = len(after)
            save(label + "-validation.json", row)
            ios_results.append(row)
            DETAILS["ios"] = ios_results
            save("ios-validation-partial.json", ios_results)
            print("BEGIN_QA4427_CANONICAL_NATIVE_CASE")
            print(json.dumps(row, ensure_ascii=False, allow_nan=False))
            print("END_QA4427_CANONICAL_NATIVE_CASE")
    save("ios-validation.json", ios_results)
    assert run["conclusion"] == "success" and len(jobs) == 4 and all(j["conclusion"] == "success" for j in jobs)
    assert len(ios_results) == 3 and all(r["status"] == "passed" for r in ios_results), "Fresh native iOS acceptance failed"
    return {"ios": ios_results, "macosUnchangedSource": mac_results,
            "iosCases": 54, "iosCaseViews": 288, "iosNativePngs": 192,
            "macosCases": 18, "macosCaseViews": 96, "macosNativePngs": 64,
            "artifactCodeExecuted": False, "originalFailedRunsRemainRejected": True}

def main():
    binding = gate("exact-source-and-reuse-binding", source_binding)
    before = worktree_snapshot()
    save("worktree-before.json", before)
    assert before["status"] == ""
    if binding["status"] == "passed":
        if sys.argv[1] == "merges":
            gate("fresh-complete-overlap-map-and-actual-merge-proofs", merge_proofs)
        elif sys.argv[1] == "artifacts":
            gate("immutable-native-artifact-validation", native_artifacts)
        else:
            raise ValueError("Unknown QA mode")
    after = worktree_snapshot()
    save("worktree-after.json", after)
    gate("qa-checkout-unchanged", lambda: {"trackedFiles": len(after["files"]), "identical": True}
         if before == after else (_ for _ in ()).throw(RuntimeError("QA checkout changed")))
    summary = {"schemaVersion": 1, "status": "passed" if all(g["status"] == "passed" for g in GATES) else "failed",
               "source": SOURCE, "sourceTree": TREE, "qaHead": QA_HEAD, "mode": sys.argv[1],
               "gates": GATES, "details": DETAILS, "production": "OFF", "physicalProfileRelease": "NOT_RUN",
               "artifactCodeExecuted": False, "scope": "Independent exact-source, merge and immutable native artifact QA"}
    save("summary.json", summary)
    print("BEGIN_QA4427_CANONICAL_SUMMARY")
    print(json.dumps(summary, ensure_ascii=False, allow_nan=False))
    print("END_QA4427_CANONICAL_SUMMARY")
    return 0 if summary["status"] == "passed" else 1

if __name__ == "__main__":
    raise SystemExit(main())
