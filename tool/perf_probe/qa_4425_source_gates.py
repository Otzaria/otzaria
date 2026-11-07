#!/usr/bin/env python3
"""Independent, source-bound QA. This file is never part of PR 4425."""
import hashlib
import io
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
import zipfile
from urllib.parse import unquote, urljoin, urlparse
import urllib.request
import urllib.error
from datetime import datetime, timezone

SOURCE = "de019fc88b93a6ec58dd80d6ab40cd26fd5c06e1"
SOURCE_TREE = "765928640680a128e48690dff500a86911a8aeaa"
PUBLIC = "3b9c05140f722d31fe1fb7312e9722db646335a5"
HOOK_SHA256 = "53b75db342d0332ae703c389562adf65a04d6127bd1ff05edaef0dde7b020097"
EXPECTED = json.loads(r'''[{"path":".github/workflows/apple-plugin-activity.yml","mode":"100644","sha":"9ec09629f9db04e4ce974c181033c3d2a1becf14","bytes":6594,"sha256":"dc08561260f17d941af5fb99cfe172f3e36ed5a60be9a96299f7ac58f9d939d2"},{"path":"integration_test/apple_plugin_activity_probe_test.dart","mode":"100644","sha":"12539d1e150832b2ae2971181612caba13d8b5f8","bytes":30720,"sha256":"44b0be6b97633b8526ce192eef75578ebb8bed6941276f9009bd548699cbe643"},{"path":"ios/Runner.xcodeproj/project.pbxproj","mode":"100644","sha":"b5f0f0c700d3933e762d38c3d706b2ce3af9d82a","bytes":31892,"sha256":"cba33ded34fa00b8f1aacfc0da74126aac3085256c2e44ce06fed7ec5c81374f"},{"path":"ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme","mode":"100644","sha":"c3fedb29c990d9c5a66b9f4ffb198b0ca3ce2ce5","bytes":4717,"sha256":"9fbce429f56243561dd437a527136c9f9ed77165e3b271b923faf236cfcd0484"},{"path":"lib/core/window_listener.dart","mode":"100644","sha":"25b13d9b31afead65b3f0ad17e7d9f7cca7167b3","bytes":33230,"sha256":"5f8680dc146863e76e73522be736133606871d0eb14d1ac8019d1a9102722800"},{"path":"pubspec.lock","mode":"100644","sha":"61f0e395ef0f048f47f46094a20cfa421a5e0178","bytes":66487,"sha256":"fe731ab5452aba50c3311555016e18b868a4749dbcd5e19b86970a2981cb389c"},{"path":"pubspec.yaml","mode":"100644","sha":"cf796836f78f63e1cea0ce2cdbaa7dca9140246f","bytes":13609,"sha256":"72e41248f6afdf7831079a1c117e27a68f82f6dbfa8d87e3fed840ed772dd7d1"},{"path":"test/core/window_listener_native_visibility_test.dart","mode":"100644","sha":"a6394e2c03a45c5a31462a5c1c4790382ed4297c","bytes":3648,"sha256":"307d75acb0d29a208f85278a2341c4ebcbaac26c3995b3a085dc8a561bb12bab"},{"path":"tool/perf_probe/apple_plugin_activity/AppleQuietControl.swift","mode":"100644","sha":"c20567565beba70d97f672a0434a8456b021fda0","bytes":7225,"sha256":"633d866d38943ab76581f5dd4a34c85876b8029fb94f89872e2acd06249e057f"},{"path":"tool/perf_probe/apple_plugin_activity/README.md","mode":"100644","sha":"6356f39386a52b7c721bfba5442a47056ace0cda","bytes":36945,"sha256":"d2106da0d8d3b18545a34dd0d69139fc5d8675a09b245edb00b52ea51078dd0c"},{"path":"tool/perf_probe/apple_plugin_activity/mac_application.swift","mode":"100644","sha":"be9acc8964ca2f8bd2478b4677b6fc06ceed0f05","bytes":11105,"sha256":"8961aeebc55cadcf2ef74d50888cde2638fff66c128559af52d0b30c835b938e"},{"path":"tool/perf_probe/apple_plugin_activity/mac_launch_fixture.swift","mode":"100644","sha":"6ee7c7f170a58ac81bc970c4d1ab0ce7ed94c0a7","bytes":4493,"sha256":"a623fc9da165e928446b4d466f234a747bf93e1d9b8a0200d8833d67319d0303"},{"path":"tool/perf_probe/apple_plugin_activity/mac_process_control.c","mode":"100644","sha":"51b1610b1fcc85d15933cd927e543ff0b4786718","bytes":892,"sha256":"0c6cec86cca15bffc10df277ae5b536beba50aeaf6a650f8d2974f0f467d0dec"},{"path":"tool/perf_probe/apple_plugin_activity/mac_process_control.h","mode":"100644","sha":"d3d9d6086493f665d09f947d27d62ee9f9f665cc","bytes":481,"sha256":"1f6a9cc7593d0f1b114758670ebfbee06883e74d2c300161daa18072170000d9"},{"path":"tool/perf_probe/apple_plugin_activity/run.py","mode":"100644","sha":"c8f2cf420610c17d3c1c5f28bf23fdd562394791","bytes":60511,"sha256":"7200fd9013891c3e2c7daab715a7ab17e22778c69a4431b0117434061e876dab"},{"path":"tool/perf_probe/apple_plugin_activity/test_cleanup_boundaries.py","mode":"100644","sha":"afa4b01aabe568ef820e3819c915ea214bf17a63","bytes":17691,"sha256":"314902daf107bc214f4620a992671b654a5f87978a79461706122638507b3851"},{"path":"tool/perf_probe/apple_plugin_activity/test_cleanup_permissions.py","mode":"100644","sha":"dabca892ebb9adbe7934cd00889e92d22958aeb6","bytes":11628,"sha256":"635776c77d74ac1ce63b3b0cd8e6ad90b46b82e03db576fb5b408e74f32ce560"},{"path":"tool/perf_probe/apple_plugin_activity/test_lifetime.py","mode":"100644","sha":"766d0a4adc06acc1f73d7c69dffc38352e194099","bytes":21343,"sha256":"d3edb7de439cdb32536a4c7ffbe64e6c7f2752448f415ba20b9a566a0a6e22ab"},{"path":"tool/perf_probe/apple_plugin_activity/test_macos_controller.py","mode":"100644","sha":"0f63966d86d891cd89d5cfbd7c317e99b49a1420","bytes":19043,"sha256":"71292b71e8e6fd1ea8051b2805414c630239b33b76d267874468b2e161c52781"},{"path":"tool/perf_probe/apple_plugin_activity/test_runner.py","mode":"100644","sha":"f1e9d6b20fcb53baee84531a4c56e85bbc5039d5","bytes":23550,"sha256":"a2227a5e181e1de3f9229e2b82ee74d5405de0e6cf5240b26de70392e4343125"}]''')
GIT_PACKAGES = json.loads(r'''{"flutter_inappwebview":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_android":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_ios":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_linux":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_macos":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_platform_interface":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_web":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_windows":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_local_notifications_windows":"ad21cf2cddfa7c79ea7903ad95b38a8d716b5f85","flutter_widget_from_html_core":"57080495ee8b89aeee156a4440b6de1c5e0f7ef2","opentype_shaper":"461902c049b412d64dc4dfa7b547fedbf751211d","otzaria_ashurit":"b43b67bb706be6bc87af14658d67e16cd347fc29","otzaria_icons":"483fec355339f54f9e094994a106dad9a63b82e3","otzaria_search_engine":"2da23091237ed0f0a612de3b2d18cfc99d8b7d2a","pdfrx":"942e27bec86e8d480111517c2083eb52817ee032","printing":"3cb90fb3025553f3e9f48638c79ccf93efb326af","seforim_library_updater":"6bfd33c3bc14392c1a6bb0887fdb23209068eab5","sentry_flutter":"93e7398355e80557a342666f98b23cc9bb832848","window_manager":"88a433a7be43ed0213da12b561bf0d8d070c6d68"}''')
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
    rows = []
    for raw in subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"]).split(b"\0"):
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
        rows.append({"path": name, "kind": kind, "bytes": len(data),
                     "mode": stat.S_IMODE(path.lstat().st_mode) if path.exists() or path.is_symlink() else None,
                     "sha256": hashlib.sha256(data).hexdigest()})
    return {"root": str(root), "head": git("rev-parse", "HEAD", cwd=root),
            "tree": git("rev-parse", "HEAD^{tree}", cwd=root), "trackedFiles": len(rows),
            "files": rows,
            "trackedSha256": hashlib.sha256(json.dumps(rows, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest(),
            "indexSha256": hashlib.sha256(subprocess.check_output(["git", "-C", str(root), "ls-files", "--stage", "-z"])).hexdigest(),
            "status": git("status", "--porcelain=v1", "--untracked-files=no", cwd=root)}

def roots():
    config_path = REPO / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    sdk = Path(shutil.which("flutter")).resolve().parent.parent
    result = {"flutter-sdk": sdk}
    packages = {}
    for package in config["packages"]:
        name = package["name"]
        if name not in GIT_PACKAGES:
            continue
        if name in packages:
            raise RuntimeError("Duplicate resolved Git package: " + name)
        uri = urlparse(urljoin(config_path.as_uri(), package["rootUri"]))
        if uri.scheme != "file":
            raise RuntimeError("Git package has unexpected URI: " + name)
        path = Path(unquote(uri.path)).resolve()
        top = Path(git("rev-parse", "--show-toplevel", cwd=path)).resolve()
        head = git("rev-parse", "HEAD", cwd=top)
        packages[name] = {"root": str(path), "gitRoot": str(top), "head": head}
        result[str(top)] = top
    save("resolved-git-packages.json", packages)
    if {name: item["head"] for name, item in packages.items()} != GIT_PACKAGES:
        raise RuntimeError("The complete resolved Git package set differs from the exact committed lock")
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
               "User-Agent": "Otzaria-independent-4425-QA"}
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
    own = [item for item in mapping if item["number"] == 4425]
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
    own = next(item for item in before["prs"] if item["number"] == 4425)
    common_paths = {f["path"] for f in own["files"]}
    delta_paths = {f["path"] for f in EXPECTED}
    result = [{"number": "dev", "head": before["dev"], "commonOverlap": [], "deltaOverlap": []}]
    for pr in before["prs"]:
        if pr["number"] == 4425:
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
        {"number": "common-proposed-05e", "head": "05e150d09758e0da45ca1877a4d650358f1aa17f", "commonOverlap": [], "deltaOverlap": [], "binding": "frozen proposed common/Windows source under independent QA"},
        {"number": "android-proposed-b9", "head": "b9f7c186cb240ec45ba77e3160acc78402f4e172", "commonOverlap": [], "deltaOverlap": [], "binding": "frozen proposed Android source under independent QA"}
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

def retained_fast_artifacts():
    run_id = 42337256358
    head = "5f5a4415113a45dce8e88e46f538591bf8dbde6a"
    expected = {
        "qa-4425-darwin-fast-linux": (13559932187, 466652, "324e6dff109579ecd9cfcf1737f60209e67a7c9cf0cd1fbaaa05eadb2ca19aa7"),
        "qa-4425-darwin-fast-macos": (13559798594, 524600, "47faa07b661b01f316c16eaa67a9403927867be2322684384f12acf6ca865aa2"),
    }
    run = api(f"/repos/Otzaria/otzaria/actions/runs/{run_id}")
    if run["head_sha"] != head or run["status"] != "completed" or run["conclusion"] != "success":
        raise RuntimeError("Fast run binding or final conclusion changed")
    items = api(f"/repos/Otzaria/otzaria/actions/runs/{run_id}/artifacts?per_page=100")
    if items["total_count"] != len(expected):
        raise RuntimeError("Unexpected fast artifact count")
    output = []
    for item in items["artifacts"]:
        name = item["name"]
        if name not in expected:
            raise RuntimeError("Unexpected fast artifact name")
        artifact_id, byte_count, digest = expected[name]
        if (item["id"], item["size_in_bytes"], item["digest"]) != (artifact_id, byte_count, "sha256:" + digest):
            raise RuntimeError("Fast archive binding changed")
        if item["expired"] or item["workflow_run"]["head_sha"] != head:
            raise RuntimeError("Expired or wrong-source fast evidence")
        headers = {"Accept": "application/vnd.github+json", "User-Agent": "Otzaria-independent-4425-QA"}
        if API_TOKEN:
            headers["Authorization"] = "Bearer " + API_TOKEN
        class CaptureRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, request, fp, code, message, response_headers, new_url):
                return None
        request = urllib.request.Request(f"https://api.github.com/repos/Otzaria/otzaria/actions/artifacts/{artifact_id}/zip", headers=headers)
        try:
            with urllib.request.build_opener(CaptureRedirect).open(request, timeout=60) as response:
                raw = response.read(10 * 1024 * 1024 + 1)
        except urllib.error.HTTPError as error:
            if error.code not in (301, 302, 303, 307, 308):
                raise
            location = error.headers.get("Location", "")
            parsed = urlparse(location)
            if parsed.scheme != "https" or parsed.username or parsed.password or not parsed.hostname:
                raise RuntimeError("Unsafe archive redirect")
            # The one-shot artifact redirect is fetched without any GitHub credential.
            with urllib.request.urlopen(urllib.request.Request(location), timeout=60) as response:
                raw = response.read(10 * 1024 * 1024 + 1)
        if len(raw) != byte_count or hashlib.sha256(raw).hexdigest() != digest:
            raise RuntimeError("Downloaded archive does not match the API digest")
        (OUT / (name + ".zip")).write_bytes(raw)
        entries = []
        json_files = {}
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            if len(archive.infolist()) > 1000 or sum(x.file_size for x in archive.infolist()) > 50 * 1024 * 1024:
                raise RuntimeError("Artifact exceeds bounded inspection scope")
            seen = set()
            for entry in archive.infolist():
                path = Path(entry.filename)
                if entry.filename in seen or path.is_absolute() or ".." in path.parts:
                    raise RuntimeError("Unsafe or duplicate archive path")
                seen.add(entry.filename)
                if entry.is_dir():
                    continue
                data = archive.read(entry)
                rows = {"path": entry.filename, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                entries.append(rows)
                # Parse data only. Never extract or execute artifact-supplied code.
                if entry.filename.endswith(".json"):
                    value = json.loads(data)
                    json_files[entry.filename] = value
                    if "source-before" not in entry.filename and "source-after" not in entry.filename:
                        print("BEGIN_QA4425_FAST_ARTIFACT_JSON", flush=True)
                        print(json.dumps({"artifact": name, **rows, "value": value}, ensure_ascii=False), flush=True)
                        print("END_QA4425_FAST_ARTIFACT_JSON", flush=True)
        before = [v for k, v in json_files.items() if "source-before" in k]
        after = [v for k, v in json_files.items() if "source-after" in k]
        if len(before) != 1 or len(after) != 1 or before != after or before[0]["head"] != head or len(before[0]["files"]) != 4200:
            raise RuntimeError("Fast full source/index snapshots do not match")
        output.append({"artifact": name, "id": artifact_id, "run": run_id, "head": head,
                       "bytes": byte_count, "sha256": digest, "files": entries,
                       "sourceAndIndexUnchanged": True, "trackedFiles": 4200,
                       "jsonFiles": len(json_files), "artifactCodeExecuted": False})
    save("fast-artifact-inventory.json", output)
    return output

QA_HEAD = git("rev-parse", "HEAD")
if git("rev-parse", SOURCE + "^{tree}") != SOURCE_TREE:
    raise RuntimeError("Candidate tree does not match the frozen source")
qa_paths = set(git("diff", "--name-only", SOURCE, QA_HEAD).splitlines())
if qa_paths != {"tool/perf_probe/qa_4425_source_gates.py", ".github/workflows/qa_4425_source_gates.yml"}:
    raise RuntimeError("QA commit must add only its two declared QA files")
if git("rev-parse", "HEAD^") != SOURCE:
    raise RuntimeError("QA commit is not a direct child of frozen source")
if git("status", "--porcelain=v1"):
    raise RuntimeError("Initial application checkout is dirty")
if git("rev-parse", SOURCE + "^") != PUBLIC:
    raise RuntimeError("Candidate is not a direct child of the unchanged public PR head")
if set(git("diff", "--name-only", PUBLIC, SOURCE).splitlines()) != {item["path"] for item in EXPECTED}:
    raise RuntimeError("Candidate delta differs from the exact twenty-file manifest")
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
            case("Apple fixture counter and identity negative controls",
                 lambda: command(["node", "--test", "tool/perf_probe/apple_plugin_activity/test_fixture.mjs"],
                                 "node-controls", timeout=180)[0])
            case("Native controller project Ruby syntax",
                 lambda: command(["ruby", "-c", "tool/perf_probe/apple_plugin_activity/create_control_project.rb"],
                                 "ruby-control", timeout=60)[0])
            case("Relevant actual Flutter contract, startup, activation and visibility tests",
                 lambda: command(["flutter", "test", "--no-pub", "--concurrency=1", "--reporter", "expanded",
                                  "test/tool/perf_probe/apple_plugin_activity_contract_test.dart",
                                  "test/tool/perf_probe/perf_fixture_test.dart",
                                  "test/tool/perf_probe/perf_fixture_startup_settings_test.dart",
                                  "test/app_scope/external_activation_service_test.dart",
                                  "test/core/external_activation_channel_test.dart",
                                  "test/core/external_activation_queue_test.dart",
                                  "test/core/window_listener_native_visibility_test.dart"], "flutter-controls", timeout=900)[0])
    finally:
        if git("rev-parse", "HEAD") != QA_HEAD:
            command(["git", "reset", "--soft", QA_HEAD], "restore-head-finally")
        if dependency_roots is not None:
            dependency_after = {key: tracked_state(root) for key, root in dependency_roots.items()}
            save("dependency-after.json", dependency_after)
            case("SDK and resolved dependency tracked sources unchanged",
                 lambda: True if dependency_before == dependency_after else (_ for _ in ()).throw(RuntimeError("SDK or dependency tracked files changed")))
        save("source-change-evidence.json", preserve_changes())

elif sys.argv[1] == "fast-artifacts":
    case("Read and bind original fast artifact data without executing code", retained_fast_artifacts)

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
case("Frozen twenty source files remain byte exact", source_bytes)
summary = {"schemaVersion": 1, "sourceCommit": SOURCE, "sourceTree": SOURCE_TREE, "qaHead": QA_HEAD,
           "mode": sys.argv[1], "cases": CASES, "passed": all(x["passed"] for x in CASES),
           "historicalLocalResultsUsed": False, "fullApplicationAcceptance": "NOT_RUN_BY_THIS_JOB"}
save("summary.json", summary)
print("BEGIN_QA_4425_SOURCE_GATES_SUMMARY", flush=True)
print(json.dumps(summary, ensure_ascii=False), flush=True)
print("END_QA_4425_SOURCE_GATES_SUMMARY", flush=True)
sys.exit(0 if summary["passed"] else 1)
