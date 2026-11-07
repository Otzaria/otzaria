#!/usr/bin/env python3
"""Additive independent exact merge proof for fonts ca0 and Apple 2497."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import traceback

ROOT = Path.cwd().resolve()
OUT = Path(os.environ["QA_EVIDENCE_DIR"]).resolve()
assert OUT != ROOT and ROOT not in OUT.parents
OUT.mkdir(parents=True, exist_ok=False)
SOURCE = "ca0adb7a91f3dc028a41ecbf894237d6bebbc523"
TREE = "7ede4702b7525247e81f28278807fbd63a8e1526"
PUBLIC = "326d693129fb36a0d8093f6107c058c1861370ac"
REVIEWED = "5dcd64785d2154df33faf0def6f0f30c20f04c53"
APPLE = "2497e0dde51862129fd34569290118b475a05f32"
APPLE_TREE = "fe1051a7754b5fcc07b8afbddeded3ebade447bd"
OLD_APPLE = "0aa78eb2ab4540a100ccb9f97f5b5a773e8412cd"
OLD_APPLE_TREE = "6c7dee43f35eb0b18a0837787f48e2d332acf5bd"
APPLE_PARENT = "3b9c05140f722d31fe1fb7312e9722db646335a5"
EXPECTED_DELTA = [{"path":".github/workflows/apple-plugin-activity.yml","old":"67f8b97aa24027539e138776b7dab971063fa120","new":"9ec09629f9db04e4ce974c181033c3d2a1becf14","oldMode":"100644","newMode":"100644"},{"path":"tool/perf_probe/apple_plugin_activity/README.md","old":"540a4a9a8e65b03e8cdf9cbad659b1bebf4abf72","new":"b13ec0809bc05d14eb47e5811ae8081a52cd6ed2","oldMode":"100644","newMode":"100644"},{"path":"tool/perf_probe/apple_plugin_activity/mac_application.swift","old":"136d1c6aeb945eafdcfa2a544460840aade21094","new":"1b88798b9cc529581282f5271c3283657428195d","oldMode":"100644","newMode":"100644"},{"path":"tool/perf_probe/apple_plugin_activity/run.py","old":"0c45dd92ab016af78f6377f8a46d7be4e5d2c75d","new":"8d2dab61ce48f4dd50804e1d5d0578abb8b854e0","oldMode":"100644","newMode":"100644"},{"path":"tool/perf_probe/apple_plugin_activity/test_cleanup_permissions.py","new":"dabca892ebb9adbe7934cd00889e92d22958aeb6","newMode":"100644"},{"path":"tool/perf_probe/apple_plugin_activity/test_macos_controller.py","old":"253e3b9df116871a7f9a02ed6ac235f45b217d08","new":"ddfc41f286c2b9132fcf2e7cae346e5aae9c6565","oldMode":"100644","newMode":"100644"},{"path":"tool/perf_probe/apple_plugin_activity/test_runner.py","old":"7f22b0b1478e325be10ec089c3a83ec3843b0451","new":"ced1eb307c9c2c82012b85260f83daab6d108d8e","oldMode":"100644","newMode":"100644"}]
QA_PATHS = {".github/qa/4427/qa_apple_2497_merge.py", ".github/workflows/qa_4427_apple_2497.yml"}
CANONICAL = {"ios/Runner.xcodeproj/project.pbxproj": "b5f0f0c700d3933e762d38c3d706b2ce3af9d82a", "ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme": "c3fedb29c990d9c5a66b9f4ffb198b0ca3ce2ce5"}
summary = {"schemaVersion": 1, "source": SOURCE, "sourceTree": TREE, "appleSource": APPLE, "appleTree": APPLE_TREE, "scope": "Additive exact merge proof; no runtime gates repeated", "status": "failed"}
def sha(data):
    return hashlib.sha256(data).hexdigest()
def save(name, value):
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
def run(args, allowed=(0,), timeout=180):
    result = subprocess.run(args, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    if result.returncode not in allowed:
        raise RuntimeError(str(args) + ": " + result.stderr.decode("utf-8", "replace"))
    return result
def git(*args):
    return run(["git", *args]).stdout.decode().strip()
def ensure(sha_value):
    probe = run(["git", "cat-file", "-e", sha_value + "^{commit}"], allowed=(0, 1, 128))
    if probe.returncode:
        run(["git", "fetch", "--no-tags", "origin", sha_value], timeout=180)
    assert git("rev-parse", sha_value + "^{commit}") == sha_value
def entries(ref):
    rows = run(["git", "ls-tree", "-rz", ref]).stdout.split(b"\0")
    output = {}
    for row in rows:
        if not row:
            continue
        metadata, path = row.split(b"\t", 1)
        mode, kind, blob = metadata.decode().split()
        output[path.decode()] = {"mode": mode, "type": kind, "sha": blob}
    return output
def snapshot():
    result = {}
    for item in run(["git", "ls-files", "-z"]).stdout.split(b"\0"):
        if item:
            path = Path(item.decode())
            assert not path.is_symlink()
            result[str(path)] = sha(path.read_bytes())
    return {"status": git("status", "--porcelain=v1", "--untracked-files=all"), "files": result}
def merge(kind, left):
    result = run(["git", "-c", "core.quotepath=false", "merge-tree", "--write-tree", left, APPLE], allowed=(0, 1))
    raw = result.stdout
    (OUT / (kind + "-merge-tree.log")).write_bytes(raw)
    (OUT / (kind + "-merge-tree-stderr.log")).write_bytes(result.stderr)
    lines = raw.decode().splitlines()
    tree = lines[0]
    assert re.fullmatch("[0-9a-f]{40}", tree)
    stage_rows = []
    for line in lines:
        match = re.fullmatch(r"([0-7]{6}) ([0-9a-f]{40}) ([123])\t(.+)", line)
        if not match:
            continue
        mode, blob, stage, path = match.groups()
        value = run(["git", "cat-file", "blob", blob]).stdout
        saved = "conflicts/" + kind + "/" + str(len(stage_rows)) + "-stage-" + stage + ".bin"
        (OUT / saved).parent.mkdir(parents=True, exist_ok=True)
        (OUT / saved).write_bytes(value)
        stage_rows.append({"path": path, "stage": int(stage), "mode": mode, "blob": blob, "bytes": len(value), "sha256": sha(value), "saved": saved})
    conflict_files = []
    for path in sorted({row["path"] for row in stage_rows}):
        found = run(["git", "show", tree + ":" + path], allowed=(0, 128))
        row = {"path": path, "exists": found.returncode == 0}
        if found.returncode == 0:
            saved = "conflicts/" + kind + "/merged-" + str(len(conflict_files)) + ".bin"
            (OUT / saved).write_bytes(found.stdout)
            text = found.stdout.decode("utf-8", "replace")
            row.update(bytes=len(found.stdout), sha256=sha(found.stdout), saved=saved, markerHunks=len(re.findall(r"(?m)^<<<<<<<", text)))
        conflict_files.append(row)
    return {"source": left, "target": APPLE, "mergeBase": git("merge-base", left, APPLE), "exitCode": result.returncode, "tree": tree, "stdoutSha256": sha(raw), "stderrSha256": sha(result.stderr), "stages": stage_rows, "actualConflictFiles": conflict_files}
before = None
try:
    for ref in (SOURCE, PUBLIC, REVIEWED, APPLE, OLD_APPLE, APPLE_PARENT):
        ensure(ref)
    summary["qaHead"] = git("rev-parse", "HEAD")
    summary["qaTree"] = git("rev-parse", "HEAD^{tree}")
    assert git("rev-list", "--parents", "-n", "1", "HEAD").split()[1:] == [SOURCE]
    assert git("rev-parse", SOURCE + "^{tree}") == TREE
    assert git("rev-list", "--parents", "-n", "1", SOURCE).split()[1:] == [PUBLIC]
    for ref, tree in ((APPLE, APPLE_TREE), (OLD_APPLE, OLD_APPLE_TREE)):
        assert git("rev-parse", ref + "^{tree}") == tree
        assert git("rev-list", "--parents", "-n", "1", ref).split()[1:] == [APPLE_PARENT]
    source, qa, old, new = entries(SOURCE), entries("HEAD"), entries(OLD_APPLE), entries(APPLE)
    qa_delta = sorted(path for path in set(source) | set(qa) if source.get(path) != qa.get(path))
    assert set(qa_delta) == QA_PATHS
    assert all(qa[path]["mode"] == "100644" and path not in source for path in QA_PATHS)
    delta = []
    for path in sorted(set(old) | set(new)):
        if old.get(path) == new.get(path):
            continue
        row = {"path": path}
        if path in old:
            row.update(old=old[path]["sha"], oldMode=old[path]["mode"])
        if path in new:
            row.update(new=new[path]["sha"], newMode=new[path]["mode"])
        delta.append(row)
    assert delta == EXPECTED_DELTA
    for path, blob in CANONICAL.items():
        assert source[path] == old[path] == new[path] == {"sha": blob, "mode": "100644", "type": "blob"}
    old_base, new_base = git("merge-base", SOURCE, OLD_APPLE), git("merge-base", SOURCE, APPLE)
    assert old_base == new_base
    summary["binding"] = {"sourceEntries": len(source), "qaOnlyFiles": qa_delta, "appleDeltaFromPrior": delta, "canonicalBlobsIdentical": CANONICAL, "oldAndNewAppleSameMergeBase": old_base}
    before = snapshot()
    save("worktree-before.json", before)
    assert before["status"] == ""
    proofs = {}
    for kind, left in (("public", PUBLIC), ("reviewed", REVIEWED), ("candidate", SOURCE)):
        proofs[kind] = merge(kind, left)
        save("merge-proofs-partial.json", proofs)
    summary["proofs"] = proofs
    assert proofs["candidate"]["exitCode"] == 0, "Candidate conflict: actual stage blobs and hunk files retained"
    assert proofs["candidate"]["stages"] == []
    summary["status"] = "passed"
except Exception as error:
    summary["error"] = {"type": type(error).__name__, "message": str(error), "traceback": traceback.format_exc()}
finally:
    after = snapshot()
    save("worktree-after.json", after)
    if before is not None:
        summary["checkoutUnchanged"] = before == after
        summary["trackedFiles"] = len(after["files"])
        if before != after:
            summary["status"] = "failed"
            summary["checkoutError"] = "Tracked checkout or status changed"
    save("summary.json", summary)
    print("BEGIN_QA4427_APPLE2497_SUMMARY")
    print(json.dumps(summary, ensure_ascii=False))
    print("END_QA4427_APPLE2497_SUMMARY")
raise SystemExit(0 if summary["status"] == "passed" else 1)
