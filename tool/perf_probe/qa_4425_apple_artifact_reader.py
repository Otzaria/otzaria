#!/usr/bin/env python3
"""Read immutable GitHub Actions artifacts as data; never execute their contents."""
import hashlib, json, os, pathlib, re, stat, subprocess, sys, traceback, urllib.request, urllib.error, zipfile
from urllib.parse import urlparse
SOURCE = "de019fc88b93a6ec58dd80d6ab40cd26fd5c06e1"
TREE = "765928640680a128e48690dff500a86911a8aeaa"
EXPECTED = [{"path":".github/workflows/apple-plugin-activity.yml","bytes":6594,"sha256":"dc08561260f17d941af5fb99cfe172f3e36ed5a60be9a96299f7ac58f9d939d2"},{"path":"integration_test/apple_plugin_activity_probe_test.dart","bytes":30720,"sha256":"44b0be6b97633b8526ce192eef75578ebb8bed6941276f9009bd548699cbe643"},{"path":"ios/Runner.xcodeproj/project.pbxproj","bytes":31892,"sha256":"cba33ded34fa00b8f1aacfc0da74126aac3085256c2e44ce06fed7ec5c81374f"},{"path":"ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme","bytes":4717,"sha256":"9fbce429f56243561dd437a527136c9f9ed77165e3b271b923faf236cfcd0484"},{"path":"lib/core/window_listener.dart","bytes":33230,"sha256":"5f8680dc146863e76e73522be736133606871d0eb14d1ac8019d1a9102722800"},{"path":"pubspec.lock","bytes":66487,"sha256":"fe731ab5452aba50c3311555016e18b868a4749dbcd5e19b86970a2981cb389c"},{"path":"pubspec.yaml","bytes":13609,"sha256":"72e41248f6afdf7831079a1c117e27a68f82f6dbfa8d87e3fed840ed772dd7d1"},{"path":"test/core/window_listener_native_visibility_test.dart","bytes":3648,"sha256":"307d75acb0d29a208f85278a2341c4ebcbaac26c3995b3a085dc8a561bb12bab"},{"path":"tool/perf_probe/apple_plugin_activity/AppleQuietControl.swift","bytes":7225,"sha256":"633d866d38943ab76581f5dd4a34c85876b8029fb94f89872e2acd06249e057f"},{"path":"tool/perf_probe/apple_plugin_activity/README.md","bytes":36945,"sha256":"d2106da0d8d3b18545a34dd0d69139fc5d8675a09b245edb00b52ea51078dd0c"},{"path":"tool/perf_probe/apple_plugin_activity/mac_application.swift","bytes":11105,"sha256":"8961aeebc55cadcf2ef74d50888cde2638fff66c128559af52d0b30c835b938e"},{"path":"tool/perf_probe/apple_plugin_activity/mac_launch_fixture.swift","bytes":4493,"sha256":"a623fc9da165e928446b4d466f234a747bf93e1d9b8a0200d8833d67319d0303"},{"path":"tool/perf_probe/apple_plugin_activity/mac_process_control.c","bytes":892,"sha256":"0c6cec86cca15bffc10df277ae5b536beba50aeaf6a650f8d2974f0f467d0dec"},{"path":"tool/perf_probe/apple_plugin_activity/mac_process_control.h","bytes":481,"sha256":"1f6a9cc7593d0f1b114758670ebfbee06883e74d2c300161daa18072170000d9"},{"path":"tool/perf_probe/apple_plugin_activity/run.py","bytes":60511,"sha256":"7200fd9013891c3e2c7daab715a7ab17e22778c69a4431b0117434061e876dab"},{"path":"tool/perf_probe/apple_plugin_activity/test_cleanup_boundaries.py","bytes":17691,"sha256":"314902daf107bc214f4620a992671b654a5f87978a79461706122638507b3851"},{"path":"tool/perf_probe/apple_plugin_activity/test_cleanup_permissions.py","bytes":11628,"sha256":"635776c77d74ac1ce63b3b0cd8e6ad90b46b82e03db576fb5b408e74f32ce560"},{"path":"tool/perf_probe/apple_plugin_activity/test_lifetime.py","bytes":21343,"sha256":"d3edb7de439cdb32536a4c7ffbe64e6c7f2752448f415ba20b9a566a0a6e22ab"},{"path":"tool/perf_probe/apple_plugin_activity/test_macos_controller.py","bytes":19043,"sha256":"71292b71e8e6fd1ea8051b2805414c630239b33b76d267874468b2e161c52781"},{"path":"tool/perf_probe/apple_plugin_activity/test_runner.py","bytes":23550,"sha256":"a2227a5e181e1de3f9229e2b82ee74d5405de0e6cf5240b26de70392e4343125"}]
GIT_PACKAGES = {"flutter_inappwebview":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_android":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_ios":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_linux":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_macos":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_platform_interface":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_web":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_windows":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_local_notifications_windows":"ad21cf2cddfa7c79ea7903ad95b38a8d716b5f85","flutter_widget_from_html_core":"57080495ee8b89aeee156a4440b6de1c5e0f7ef2","opentype_shaper":"461902c049b412d64dc4dfa7b547fedbf751211d","otzaria_ashurit":"b43b67bb706be6bc87af14658d67e16cd347fc29","otzaria_icons":"483fec355339f54f9e094994a106dad9a63b82e3","otzaria_search_engine":"2da23091237ed0f0a612de3b2d18cfc99d8b7d2a","pdfrx":"942e27bec86e8d480111517c2083eb52817ee032","printing":"3cb90fb3025553f3e9f48638c79ccf93efb326af","seforim_library_updater":"6bfd33c3bc14392c1a6bb0887fdb23209068eab5","sentry_flutter":"93e7398355e80557a342666f98b23cc9bb832848","window_manager":"88a433a7be43ed0213da12b561bf0d8d070c6d68"}
TOKEN = os.environ.pop("QA_GITHUB_TOKEN", "")
CONFIG = json.loads(os.environ["QA_ARTIFACT"])
OUT = pathlib.Path(os.environ["RUNNER_TEMP"]).resolve() / ("qa-4425-artifact-" + CONFIG["label"])
OUT.mkdir(exist_ok=False)
def save(name, value):
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
def emit(kind, value):
    print("BEGIN_QA4425_ARTIFACT_" + kind, flush=True)
    print(json.dumps(value, ensure_ascii=False), flush=True)
    print("END_QA4425_ARTIFACT_" + kind, flush=True)
def git(*args):
    return subprocess.check_output(["git", *args], timeout=60).decode().strip()
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, url):
        return None
def request(path):
    if not path.startswith("/repos/Otzaria/otzaria/"):
        raise RuntimeError("Unexpected GitHub API path")
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "Otzaria-4425-independent-artifact-reader",
               "X-GitHub-Api-Version": "2022-11-28"}
    if TOKEN:
        headers["Authorization"] = "Bearer " + TOKEN
    return urllib.request.Request("https://api.github.com" + path, headers=headers)
def api(path):
    with urllib.request.build_opener(NoRedirect).open(request(path), timeout=60) as response:
        return json.load(response)
def archive():
    run = api(f"/repos/Otzaria/otzaria/actions/runs/{CONFIG['run']}")
    job = api(f"/repos/Otzaria/otzaria/actions/jobs/{CONFIG['job']}")
    if run["head_sha"] != CONFIG["head"] or job["head_sha"] != CONFIG["head"]:
        raise RuntimeError("Evidence run/job head differs")
    if job["run_id"] != CONFIG["run"] or job["status"] != "completed" or job["conclusion"] != CONFIG["conclusion"]:
        raise RuntimeError("Evidence job is unfinished or has unexpected conclusion")
    items = api(f"/repos/Otzaria/otzaria/actions/runs/{CONFIG['run']}/artifacts?per_page=100")
    if items["total_count"] > 100:
        raise RuntimeError("Artifact listing exceeded complete single-page bound")
    selected = [x for x in items["artifacts"] if x["id"] == CONFIG["id"]]
    if len(selected) != 1:
        raise RuntimeError("Evidence artifact identity is not unique")
    item = selected[0]
    if item["expired"] or item["name"] != CONFIG["name"] or item["size_in_bytes"] != CONFIG["bytes"] or item["digest"] != "sha256:" + CONFIG["sha256"] or item["workflow_run"]["head_sha"] != CONFIG["head"]:
        raise RuntimeError("Evidence archive metadata changed")
    save("provider-binding.json", {"config": CONFIG, "run": run, "job": job, "artifact": item})
    try:
        response = urllib.request.build_opener(NoRedirect).open(request(f"/repos/Otzaria/otzaria/actions/artifacts/{CONFIG['id']}/zip"), timeout=60)
    except urllib.error.HTTPError as error:
        if error.code not in (301, 302, 303, 307, 308):
            raise
        location = error.headers.get("Location", "")
        parsed = urlparse(location)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
            raise RuntimeError("Unsafe one-shot archive redirect")
        # GitHub authorization is not forwarded to the signed storage URL.
        response = urllib.request.urlopen(urllib.request.Request(location), timeout=90)
    destination = OUT / "verified-evidence.zip"
    count, digest = 0, hashlib.sha256()
    with response, destination.open("wb") as output:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            count += len(chunk)
            if count > CONFIG["bytes"] or count > 1024 * 1024 * 1024:
                raise RuntimeError("Evidence download exceeded exact declared bytes")
            digest.update(chunk)
            output.write(chunk)
    if count != CONFIG["bytes"] or digest.hexdigest() != CONFIG["sha256"]:
        raise RuntimeError("Evidence archive SHA256 mismatch")
    return destination
def full_snapshot_check(before, after):
    if before != after:
        raise RuntimeError("Full tracked source/index snapshot differs")
    if before.get("status"):
        raise RuntimeError("Snapshot was already dirty")
    if len(before.get("files", [])) != before["trackedFiles"]:
        raise RuntimeError("Full tracked file enumeration is missing")
    if len({x["path"] for x in before["files"]}) != before["trackedFiles"]:
        raise RuntimeError("Duplicate tracked snapshot path")
    return {key: before[key] for key in ("head", "tree", "trackedFiles", "trackedSha256", "indexSha256", "status")}
def check_packages(packages):
    if {key: value["head"] for key, value in packages.items()} != GIT_PACKAGES:
        raise RuntimeError("Resolved Git dependency enumeration or exact pin differs")
    return {value["gitRoot"] for value in packages.values()}
def inspect(files, inventory):
    def raw(suffix):
        matching = [name for name in files if name == suffix or name.endswith("/" + suffix)]
        if len(matching) != 1:
            raise RuntimeError("Artifact member is missing or ambiguous: " + suffix)
        return files[matching[0]]
    def data(suffix):
        return json.loads(raw(suffix))
    kind = CONFIG["kind"]
    result = {"source": SOURCE, "tree": TREE, "artifact": CONFIG, "artifactCodeExecuted": False}
    if kind == "source":
        summary = data("summary.json")
        if not summary["passed"] or summary["sourceCommit"] != SOURCE or summary["qaHead"] != CONFIG["head"]:
            raise RuntimeError("Source gate did not pass on exact source")
        result["application"] = full_snapshot_check(data("app-before.json"), data("app-after.json"))
        if result["application"]["head"] != CONFIG["head"]:
            raise RuntimeError("Application snapshot is bound to a different QA head")
        sdk0, sdk1 = data("sdk-before-resolution.json"), data("sdk-after-resolution.json")
        result["sdkResolution"] = full_snapshot_check(sdk0, sdk1)
        before, after = data("dependency-before.json"), data("dependency-after.json")
        roots = check_packages(data("resolved-git-packages.json"))
        if set(before) != roots | {"flutter-sdk"} or set(after) != set(before):
            raise RuntimeError("Dependency snapshot roots are incomplete")
        result["dependencies"] = {key: full_snapshot_check(value, after[key]) for key, value in before.items()}
        if sdk1 != before["flutter-sdk"]:
            raise RuntimeError("SDK baseline changed before source gates")
        hook = raw("installed-pre-commit-hook.txt")
        hook_sha = hashlib.sha256(hook).hexdigest()
        if hook_sha != "53b75db342d0332ae703c389562adf65a04d6127bd1ff05edaef0dde7b020097":
            raise RuntimeError("Not the exact original repository hook")
        binding = data("staged-hook-binding.json")
        expected_dart = sorted(git("diff", "--name-only", "--diff-filter=ACM", SOURCE + "^", SOURCE, "--", "*.dart").splitlines())
        if sorted(binding["stagedDartPaths"]) != expected_dart or len(expected_dart) != 3:
            raise RuntimeError("Original hook was not run on the exact nonempty staged Dart")
        for name, timeout in (("install-original-hook", 900), ("original-staged-hook", 1200)):
            receipt = data(name + ".json")
            if receipt["exitCode"] != 0 or receipt["timedOut"] or receipt["timeoutSeconds"] != timeout:
                raise RuntimeError("Original installer/hook result or budget differs")
        if raw("source-mutations.log") or raw("index-mutations.log"):
            raise RuntimeError("Application or index mutations were retained")
        result.update(summary=summary, hookBinding=binding, gitPackages=19, applicationAcceptance="NOT_RUN_BY_SOURCE_GATE")
    elif kind == "merge":
        summary, results = data("summary.json"), data("merge-results.json")
        if not summary["passed"] or summary["sourceCommit"] != SOURCE:
            raise RuntimeError("Merge gate is not bound and passing")
        def key(mapping):
            return {"dev": mapping["dev"], "prs": [{k: row[k] for k in ("number", "head", "base", "baseRef")} for row in mapping["prs"]]}
        before = data("open-pr-map-before.json")
        if key(before) != key(data("open-pr-map-after-read.json")) or key(before) != key(data("open-pr-map-after-merge.json")):
            raise RuntimeError("Full open PR map was not stable")
        result.update(prCount=len(before["prs"]), fileRows=sum(len(x["files"]) for x in before["prs"]), summary=summary,
                      targets=[{"number": x["number"], "head": x["head"], "classification": x["classification"]} for x in results])
        required = {"05e150d09758e0da45ca1877a4d650358f1aa17f", "b9f7c186cb240ec45ba77e3160acc78402f4e172", "ca0adb7a91f3dc028a41ecbf894237d6bebbc523", before["dev"]}
        if not required <= {x["head"] for x in results}:
            raise RuntimeError("Required concurrent sources were omitted")
        proofs = []
        for row in results:
            if row["classification"] == "NEW_OR_CHANGED_CONFLICTS":
                raise RuntimeError("Candidate changed actual conflict content")
            if row["classification"] != "PREEXISTING_CONFLICTS":
                continue
            first, second = row["public"]["conflictEvidence"], row["candidate"]["conflictEvidence"]
            if first["stageEntries"] != second["stageEntries"]:
                raise RuntimeError("Conflict stages changed")
            for entry in second["files"]:
                if not entry["exists"]:
                    continue
                path = entry["path"]
                prefix = "conflict-files/" + str(row["number"])
                public = raw(prefix + "/public/" + path + ".normalized")
                candidate = raw(prefix + "/candidate/" + path + ".normalized")
                original = raw(prefix + "/candidate/" + path)
                if public != candidate or hashlib.sha256(candidate).hexdigest() != entry["normalizedSha256"] or hashlib.sha256(original).hexdigest() != entry["sha256"]:
                    raise RuntimeError("Retained actual conflict bytes differ: " + path)
                text = candidate.decode("utf-8") if entry["kind"] == "utf-8" else ""
                hunks = re.findall(r"^<{7}\n.*?^>{7}(?:\n|$)", text, re.M | re.S)
                if len(hunks) != (entry["conflictHunks"] or 0):
                    raise RuntimeError("Actual conflict hunk extraction differs")
                proof = {"target": row["number"], "path": path, "stageEntries": [x for x in second["stageEntries"] if x["path"] == path],
                         "sha256": entry["sha256"], "normalizedSha256": entry["normalizedSha256"],
                         "bytes": entry["bytes"], "hunks": hunks, "identicalToPublic": True}
                proofs.append(proof)
                emit("CONFLICT_HUNKS", proof)
        result["actualUnchangedConflictFiles"] = len(proofs)
        result["actualUnchangedConflictHunks"] = sum(len(x["hunks"]) for x in proofs)
        result["application"] = full_snapshot_check(data("app-before.json"), data("app-after.json"))
    elif kind == "native":
        binding = data("qa-4425-native-snapshots/bind.json")
        resolved = data("qa-4425-native-snapshots/resolved.json")
        pre = data("qa-4425-native-snapshots/before-native.json")
        final = data("qa-4425-native-snapshots/after.json")
        packages = data("qa-4425-native-snapshots/resolved-git-packages-resolved.json")
        roots = check_packages(packages)
        if set(resolved) != roots | {"application", "flutter-sdk"} or set(pre) != set(resolved) or set(final) != set(resolved):
            raise RuntimeError("Native snapshot roots are incomplete")
        if resolved["application"]["head"] != CONFIG["head"] or resolved["flutter-sdk"]["head"] != "abaf9c523780a608bd46686fd5e53740a07077f8":
            raise RuntimeError("Native source or SDK snapshot head differs")
        for key in ("application", "flutter-sdk"):
            full_snapshot_check(binding[key], resolved[key])
        for key in resolved:
            full_snapshot_check(resolved[key], pre[key])
        result["snapshots"] = {key: full_snapshot_check(value, final[key]) for key, value in resolved.items()}
        for mode in ("bind", "resolved", "before-native", "after"):
            receipt = data("qa-4425-native-snapshots/" + mode + "-receipt.json")
            if receipt["passed"] is not True or receipt["sourceCommit"] != SOURCE or receipt["qaHead"] != CONFIG["head"]:
                raise RuntimeError("Native snapshot receipt did not pass on exact source")
        for mode in ("resolved", "before-native", "after"):
            if data("qa-4425-native-snapshots/resolved-git-packages-" + mode + ".json") != packages:
                raise RuntimeError("Resolved Git dependency paths/heads changed")
        environment = data("apple-plugin-activity/environment.json")
        if environment["commit"] != CONFIG["head"] or environment["sourceStatus"] or environment["physicalDevice"]:
            raise RuntimeError("Wrong native source binding or mode")
        if environment["flutter"]["frameworkVersion"] != "3.47.7" or environment["flutter"]["dartSdkVersion"] != "3.13.5" or environment["nativeFork"] != "124bb8e63f345ffd0b0f2ea7190c24b19e69897d":
            raise RuntimeError("Native SDK or source pin differs")
        if environment["nativeSourceBefore"] != environment["nativeSourceAfter"]:
            raise RuntimeError("Original runner native source receipts differ")
        if environment["appSourceAfter"]["sourceStatus"] or environment["appSourceAfter"]["commit"] != CONFIG["head"]:
            raise RuntimeError("Original runner source receipt differs")
        result.update(environment=environment, gitPackages=19,
                      sourceCleanupReceiptStatus=environment["status"],
                      sourceAcceptance="NOT_PASSED" if environment["status"] != "passed" else "REQUIRES_RAW_FRAMEWORK_AND_PHASE_REVIEW")
        if environment["status"] == "passed":
            complete = data("apple-plugin-activity/complete.json")
            framework = data("apple-plugin-activity/app-report.json")["applePluginActivity"]
            if environment["appExitCode"] != 0 or complete["status"] != "passed" or framework["status"] != "passed" or framework.get("testFailures") or complete["errors"] or framework["errors"]:
                raise RuntimeError("Native source or final Flutter framework failed")
            if complete["phases"] != framework["phases"]:
                raise RuntimeError("Framework final phases differ from source completion")
            for key in ("runId", "hostPid", "appBootToken", "commit", "nativeFork", "lockSha256", "platform", "buildMode"):
                if complete[key] != framework[key]:
                    raise RuntimeError("Final framework binding differs: " + key)
            result["finalFramework"] = {key: framework[key] for key in ("runId", "hostPid", "appBootToken", "commit", "nativeFork", "lockSha256", "platform", "buildMode", "status", "testFailures")}
            result["phases"] = [{"name": x["name"], "status": x["status"]} for x in framework["phases"]]
        else:
            if not environment.get("firstError"):
                raise RuntimeError("Failed native source lost its original first error")
            result["firstErrorPreserved"] = environment["firstError"]
        workflow_cleanup = [name for name in files if name.endswith("qa-4425-workflow-simulator-cleanup.json")]
        if workflow_cleanup:
            result["workflowOwnedSimulatorCleanup"] = json.loads(files[workflow_cleanup[0]])
            result["workflowSimulatorCleanupIsSeparateFromSourceAcceptance"] = True
        result["preWorkflowCleanupProcesses"] = data("qa-4425-processes-before-workflow-cleanup.json")
    else:
        raise RuntimeError("Unknown inspection kind")
    return result

receipt = {"source": SOURCE, "tree": TREE, "artifact": CONFIG, "readerStatus": "failed",
           "artifactCodeExecuted": False, "physicalIOSProfileRelease": "NOT_RUN", "productionExperiment": "OFF"}
try:
    if git("rev-parse", "HEAD^") != SOURCE or git("rev-parse", SOURCE + "^{tree}") != TREE:
        raise RuntimeError("Reader must be a direct QA child of the exact frozen source")
    if set(git("diff", "--name-only", SOURCE, "HEAD").splitlines()) != {".github/workflows/qa_4425_apple_artifact_reader.yml", "tool/perf_probe/qa_4425_apple_artifact_reader.py"}:
        raise RuntimeError("Reader changes application sources")
    if git("status", "--porcelain=v1"):
        raise RuntimeError("Reader source checkout is dirty")
    for item in EXPECTED:
        data = pathlib.Path(item["path"]).read_bytes()
        if len(data) != item["bytes"] or hashlib.sha256(data).hexdigest() != item["sha256"]:
            raise RuntimeError("Reader frozen source byte mismatch")
    path = archive()
    files, inventory = {}, []
    with zipfile.ZipFile(path) as value:
        entries = value.infolist()
        if len(entries) > 30000 or sum(x.file_size for x in entries) > 4 * 1024 * 1024 * 1024:
            raise RuntimeError("Evidence archive exceeds bounded inspection")
        seen = set()
        for entry in entries:
            name = entry.filename
            parts = pathlib.PurePosixPath(name)
            if name in seen or parts.is_absolute() or ".." in parts.parts:
                raise RuntimeError("Unsafe or duplicate archive path")
            seen.add(name)
            if entry.is_dir():
                continue
            if name.endswith((".json", ".log", ".diff", ".normalized", ".txt")) or name.startswith("conflict-files/"):
                if entry.file_size > 128 * 1024 * 1024:
                    raise RuntimeError("Evidence member exceeds bounded inspection")
                data = value.read(entry)
                files[name] = data
                row = {"path": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                inventory.append(row)
                # Only data files are copied, and no artifact-supplied program is run.
                target = OUT / "retained-data" / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
    save("inventory.json", inventory)
    for row in inventory:
        name = row["path"]
        skip_snapshot = any(name.endswith("/" + x) or name == x for x in (
            "app-before.json", "app-after.json", "dependency-before.json", "dependency-after.json",
            "sdk-before-resolution.json", "sdk-after-resolution.json", "bind.json", "resolved.json", "before-native.json", "after.json",
            "open-pr-map-before.json", "open-pr-map-after-read.json", "open-pr-map-after-merge.json", "defines.json", "partial-app.json", "complete.json"))
        if name.endswith(".json") and not skip_snapshot:
            emit("JSON", {**row, "value": json.loads(files[name])})
        elif name.endswith(".log") and not name.startswith("conflict-files/"):
            data = files[name]
            emit("LOG", {**row, "tailTruncated": len(data) > 300000,
                         "fullBytesRetainedInVerifiedArtifact": True, "text": data[-300000:].decode("utf-8", "replace")})
    receipt["inspection"] = inspect(files, inventory)
    if git("status", "--porcelain=v1"):
        raise RuntimeError("Artifact reader changed source checkout")
    receipt["readerStatus"] = "passed"
except BaseException as error:
    receipt["error"] = str(error)
    receipt["traceback"] = traceback.format_exc()
finally:
    save("inspection-summary.json", receipt)
    emit("SUMMARY", receipt)
sys.exit(0 if receipt["readerStatus"] == "passed" else 1)
