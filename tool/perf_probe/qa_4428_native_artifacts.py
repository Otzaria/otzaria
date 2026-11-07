#!/usr/bin/env python3
"""Independent exact-artifact Android review; artifact bytes are never executed."""
import base64
import hashlib
import io
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import traceback
import urllib.error
import urllib.parse
import urllib.request
import zipfile

SOURCE = "4d627791faf270a9ab9ccee14e07a7a537cc1c97"
SOURCE_TREE = "a63d42cb87f01433c3848f7077d23b1ea3cb0854"
PUBLIC = "9fdc05b9dc98c732affeb91bd78062ea369387dc"
B9 = "b9f7c186cb240ec45ba77e3160acc78402f4e172"
FAST_HEAD = "5eff54b99e6ad7ad44d35de0525b6fe5fc4032b5"
NATIVE_HEAD = "6e7a8477f92b52966dac208672122455db24af53"
NATIVE_TREE = "d66091d31453f0ec28e9fd8c3a9a453e0e94a82a"
NATIVE_RUN = 42339733090
NATIVE_JOB = 128304534509
PACKAGE = "org.otzaria.otzaria.installedprobe"
COMPONENT = PACKAGE + "/org.otzaria.otzaria.MainActivity"
SDK_HEAD = "abaf9c523780a608bd46686fd5e53740a07077f8"
ENGINE_HEAD = "deb287481e3ce9468f3434937ced4240a70539ca"
STORE_COMMIT = "4517d39c4ecab632aff98e1c0e414881695961aa"
QA_FILES = {".github/workflows/qa_4428_native_artifacts.yml",
            "tool/perf_probe/qa_4428_native_artifacts.py"}
EXPECTED = json.loads(r'''[{"path":".github/workflows/installed_plugin_probe_android.yml","mode":"100644","blob":"f731b8607b72c4f583bee251f3c1215224f349bc","bytes":4233,"sha256":"6828b039ca7c6b09125a0e6c4cdf41c6c118f5bc93da9b862d516b7cf4415216"},{"path":"android/app/build.gradle","mode":"100644","blob":"1ea47509d93d48688a7be4e328355b777347be11","bytes":3595,"sha256":"7f4bb82fb21cf82d8b93e76551b541e13c9061cecc5075effa8e1d06c8ce91cd"},{"path":"integration_test/installed_plugin_resource_probe_test.dart","mode":"100644","blob":"3fff9055bd0f023776d65b87a79ea94656d69488","bytes":59604,"sha256":"c6de4983280a44f03215f79e781870dd30f2f7a528117188ce6f9eda3924bc8a"},{"path":"integration_test/support/installed_plugin_android_control.dart","mode":"100644","blob":"7755b10653ad65bd6e13c6aa5ab76c1799b0d51f","bytes":7847,"sha256":"f44ed3d8c2937730325dca609b6a6e81fff8d4f2210b30eaf2d3ad0309d9272f"},{"path":"pubspec.lock","mode":"100644","blob":"5e175ffefe86620541f53dcf8172b9c0f412b2bd","bytes":66487,"sha256":"7cb40007d9484e613567165ea97b2ead3426a50c60c16a7e6fa874af32a27faf"},{"path":"pubspec.yaml","mode":"100644","blob":"332081188494a74e08c57595eb01ec882c0f97e3","bytes":13609,"sha256":"70eda15deb3977c28e581205f8242f6f0ffa368ab82fc17aee0877c29e64b232"},{"path":"test/tool/perf_probe/installed_plugin_android_control_test.dart","mode":"100644","blob":"72a0868e65a85dc9df7590377f7234019ad340b4","bytes":15880,"sha256":"18123632280b024183c3b7403ff16e04d5f540eb7ed5fef7a678fe987a68df6e"},{"path":"tool/perf_probe/INSTALLED_PLUGIN_ANDROID.md","mode":"100644","blob":"0386efac664bdba1e09163d6b28f0ef8d8684a96","bytes":13242,"sha256":"f4125059d0ced6d28a24d11f2f6e90503b0642d00a0ba9c6f85c2bca627dd15e"},{"path":"tool/perf_probe/run_installed_plugin_android.py","mode":"100644","blob":"ed52fbaf1afc0c70dc554db7e922ba76b097b560","bytes":44385,"sha256":"ba03044836f876de02399220b3b6ae09b535eb23118363ee680652d692f10cc4"},{"path":"tool/perf_probe/test_installed_plugin_android.py","mode":"100644","blob":"4c1be8c609b3d5ee69b4a9be84bb1b537cc6a91c","bytes":55457,"sha256":"53da871ca89837cc62416f669c3237636a6936cfa17d29d10aa9f1f3707756e0"}]''')
GIT_PINS = json.loads(r'''{"flutter_inappwebview":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_android":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_ios":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_linux":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_macos":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_platform_interface":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_web":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_inappwebview_windows":"124bb8e63f345ffd0b0f2ea7190c24b19e69897d","flutter_local_notifications_windows":"ad21cf2cddfa7c79ea7903ad95b38a8d716b5f85","flutter_widget_from_html_core":"57080495ee8b89aeee156a4440b6de1c5e0f7ef2","opentype_shaper":"461902c049b412d64dc4dfa7b547fedbf751211d","otzaria_ashurit":"b43b67bb706be6bc87af14658d67e16cd347fc29","otzaria_icons":"483fec355339f54f9e094994a106dad9a63b82e3","otzaria_search_engine":"2da23091237ed0f0a612de3b2d18cfc99d8b7d2a","pdfrx":"942e27bec86e8d480111517c2083eb52817ee032","printing":"3cb90fb3025553f3e9f48638c79ccf93efb326af","seforim_library_updater":"6bfd33c3bc14392c1a6bb0887fdb23209068eab5","sentry_flutter":"93e7398355e80557a342666f98b23cc9bb832848","window_manager":"4f37655288ce8b803a9bd50294c5d6983850f622"}''')
STORE_HASHES = json.loads(r'''{"manifest.json":"a40e4225682f948d657e94086217f8400b4d708ec1eaa958e37621113bd12feb","index.html":"c6495a41ffc31a8e4b23828b3537c40478d0aa7d45a3cf680534e4e0cd0fed2f","restore-state.js":"f0324b025009e9594135b17b911366388959ab5398c0485ac11b0316cd59332f","i18n/en.js":"54f9ec3b69a2858d2a1bb0f6d80f641397c3ff1fd286a83cdb5e751af3366ef2","background.html":"0110c549b0350222c63c098843c9b6debdcd61cebd57d91b11874f07426fc975"}''')
ARTIFACTS = [{"role":"native","id":13561108881,"name":"installed-plugin-android-emulator-debug","run":42339733090,"head":"6e7a8477f92b52966dac208672122455db24af53","bytes":209387,"sha256":"e2cff3d48cbfc02303a93e7872425a93b489872e8618d408ca02635a89c96111"},{"role":"snapshots","id":13561796227,"name":"qa-4428-native-source-snapshots","run":42339733090,"head":"6e7a8477f92b52966dac208672122455db24af53","bytes":5359647,"sha256":"32582d5b1ef4ae2ba1f2e8bee86d34d96b25f2d4e5be69cf00aca499318e7872"},{"role":"fast","id":13560748776,"name":"qa-4428-status-fast-5eff54b99e6ad7ad44d35de0525b6fe5fc4032b5","run":42339634603,"head":"5eff54b99e6ad7ad44d35de0525b6fe5fc4032b5","bytes":37413,"sha256":"e14531a20f8130571328daac5c97b68d8a2b40b1b8841a8edd438bd289d6e76f"},{"role":"merge","id":13560663993,"name":"qa-4428-status-merge-5eff54b99e6ad7ad44d35de0525b6fe5fc4032b5","run":42339634603,"head":"5eff54b99e6ad7ad44d35de0525b6fe5fc4032b5","bytes":1350444,"sha256":"d06d0adfb5571a51f9f362c733bf4bc4f4d8202d94e327eabc9da5cdbb497131"},{"role":"prior-source","id":13559803524,"name":"qa-4428-source-hook-4f3cb2fbcf1540cba1e41691fc6c05016ca649de","run":42337261971,"head":"4f3cb2fbcf1540cba1e41691fc6c05016ca649de","bytes":92340,"sha256":"46b66533ee6bfba3ef40d553f7e826799285f9587757d405b5ac61d692c7c336"}]
ROOT = Path.cwd().resolve()
OUT = Path(os.environ["QA_4428_ARTIFACT_OUTPUT"]).resolve()
assert OUT != ROOT and ROOT not in OUT.parents
OUT.mkdir(parents=True, exist_ok=False)
TOKEN = os.environ.pop("QA_GITHUB_TOKEN")
os.environ.pop("GITHUB_TOKEN", None)
os.environ.pop("GH_TOKEN", None)
sys.dont_write_bytecode = True
CHECKS = []
ARCHIVES = {}
FILE_DATA = {}
RAW_EXPORTS = []

def sha(data):
    return hashlib.sha256(data).hexdigest()

def save(name, value):
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, timeout=90)

def gt(*args):
    return git(*args).decode("utf-8").strip()

def source_snapshot():
    files = []
    for raw in git("ls-files", "-z").split(b"\0"):
        if not raw:
            continue
        name = os.fsdecode(raw)
        path = ROOT / name
        data = os.fsencode(os.readlink(path)) if path.is_symlink() else path.read_bytes()
        files.append({"path": name, "bytes": len(data), "sha256": sha(data),
                      "mode": path.lstat().st_mode, "symlink": path.is_symlink()})
    return {"head": gt("rev-parse", "HEAD"), "tree": gt("rev-parse", "HEAD^{tree}"),
            "indexSha256": sha(git("ls-files", "--stage", "-z")),
            "status": gt("status", "--porcelain=v1", "--untracked-files=all"),
            "files": files}

def check(name, fn):
    row = {"name": name, "passed": False}
    try:
        row["result"] = fn()
        row["passed"] = True
    except Exception as error:
        row.update(error=str(error), traceback=traceback.format_exc())
    CHECKS.append(row)
    save("checks-partial.json", CHECKS)
    print(json.dumps({"check": name, "passed": row["passed"], "error": row.get("error")}), flush=True)
    return row

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, url):
        return None

def api_response(path):
    if not path.startswith("/repos/Otzaria/otzaria/"):
        raise RuntimeError("API path is outside the reviewed repository")
    request = urllib.request.Request("https://api.github.com" + path, headers={
        "Authorization": "Bearer " + TOKEN, "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "Otzaria-independent-4428-artifact-QA"})
    return urllib.request.build_opener(NoRedirect).open(request, timeout=60)

def api_json(path):
    with api_response(path) as response:
        raw = response.read(16 * 1024 * 1024 + 1)
    assert len(raw) <= 16 * 1024 * 1024
    return json.loads(raw)

def download(spec):
    metadata = api_json("/repos/Otzaria/otzaria/actions/artifacts/" + str(spec["id"]))
    assert metadata["id"] == spec["id"] and metadata["name"] == spec["name"] and not metadata["expired"]
    assert metadata["size_in_bytes"] == spec["bytes"] and metadata["digest"] == "sha256:" + spec["sha256"]
    assert metadata["workflow_run"]["id"] == spec["run"]
    assert metadata["workflow_run"]["head_sha"] == spec["head"]
    assert 0 < spec["bytes"] <= 256 * 1024 * 1024
    try:
        response = api_response("/repos/Otzaria/otzaria/actions/artifacts/" + str(spec["id"]) + "/zip")
    except urllib.error.HTTPError as error:
        assert error.code in (301, 302, 303, 307, 308), error.code
        location = error.headers["Location"]
        parsed = urllib.parse.urlparse(location)
        assert parsed.scheme == "https" and parsed.hostname and not parsed.username and not parsed.password
        assert parsed.port in (None, 443)
        # A fresh request strips the API bearer token from the signed redirect.
        response = urllib.request.build_opener(NoRedirect).open(urllib.request.Request(location), timeout=120)
    with response:
        archive_bytes = response.read(spec["bytes"] + 1)
    assert len(archive_bytes) == spec["bytes"] and sha(archive_bytes) == spec["sha256"]
    (OUT / (spec["role"] + "-original.zip")).write_bytes(archive_bytes)
    data, files = {}, []
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
        entries = archive.infolist()
        assert len(entries) <= 25000
        assert sum(item.file_size for item in entries) <= 512 * 1024 * 1024
        for item in entries:
            path = PurePosixPath(item.filename)
            assert not path.is_absolute() and ".." not in path.parts and "\\" not in item.filename
            assert str(path) == item.filename.rstrip("/") and not item.flag_bits & 1
            kind = stat.S_IFMT(item.external_attr >> 16)
            assert kind in (0, stat.S_IFREG, stat.S_IFDIR)
            if item.is_dir():
                continue
            assert item.filename not in data and item.file_size <= 128 * 1024 * 1024
            content = archive.read(item)
            assert len(content) == item.file_size
            data[item.filename] = content
            files.append({"path": item.filename, "bytes": len(content), "sha256": sha(content)})
    FILE_DATA[spec["role"]] = data
    record = {"binding": spec, "metadata": metadata, "files": files,
              "originalZipRetained": True, "artifactCodeExecuted": False}
    ARCHIVES[spec["role"]] = record
    save(spec["role"] + "-archive-manifest.json", record)
    return {"role": spec["role"], "id": spec["id"], "bytes": len(archive_bytes),
            "sha256": sha(archive_bytes), "files": len(files), "artifactCodeExecuted": False}

def one(role, name):
    data = FILE_DATA[role]
    matches = [path for path in data if PurePosixPath(path).name == name]
    assert len(matches) == 1, (role, name, matches)
    return matches[0], data[matches[0]]

def jone(role, name):
    path, raw = one(role, name)
    return path, json.loads(raw)

def native_file(relative):
    host_path, _ = one("native", "host-report.json")
    parent = PurePosixPath(host_path).parent
    path = str(parent / relative)
    assert path in FILE_DATA["native"], path
    return FILE_DATA["native"][path]

def export_raw(role, name):
    path, raw = one(role, name)
    assert len(raw) <= 4 * 1024 * 1024
    record = {"role": role, "path": path, "bytes": len(raw), "sha256": sha(raw)}
    target = OUT / "raw-evidence" / role / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(raw)
    RAW_EXPORTS.append(record)
    print("BEGIN_QA4428_RAW_EVIDENCE", flush=True)
    print(json.dumps({**record, "encoding": "base64", "data": base64.b64encode(raw).decode("ascii")}), flush=True)
    print("END_QA4428_RAW_EVIDENCE", flush=True)
    return record

def number(value):
    return type(value) in (int, float) and math.isfinite(value)

def command_rows():
    _, raw = one("native", "commands.jsonl")
    assert raw.endswith(b"\n")
    rows = [json.loads(line) for line in raw.splitlines() if line]
    assert [row["number"] for row in rows] == list(range(len(rows)))
    for row in rows:
        assert number(row["startedMonotonic"]) and number(row["finishedMonotonic"])
        assert row["startedMonotonic"] <= row["finishedMonotonic"]
        assert row.get("evidenceError") is None and not row.get("captureWriteErrors")
        for stream in ("stdout", "stderr"):
            path = row[stream]
            assert isinstance(path, str) and path.startswith("raw/") and ".." not in PurePosixPath(path).parts
            native_file(path)
        if row["argv"][0].replace("\\", "/").split("/")[-1] == "adb":
            assert row["argv"][1:3] == ["-s", "emulator-5554"], row["argv"]
    return rows

def verify_checkout():
    assert gt("rev-parse", SOURCE + "^{tree}") == SOURCE_TREE
    assert gt("rev-parse", SOURCE + "^") == PUBLIC
    head = gt("rev-parse", "HEAD")
    assert gt("rev-list", "--parents", "-n", "1", head).split()[1:] == [SOURCE]
    assert set(gt("diff", "--name-only", SOURCE, head).splitlines()) == QA_FILES
    for revision in (SOURCE, head):
        assert gt("show", "-s", "--format=%an%x00%ae%x00%cn%x00%ce", revision).split("\0") == [
            "Y-Ploni", "7353755@gmail.com", "Y-Ploni", "7353755@gmail.com"]
    actual = []
    for item in EXPECTED:
        raw = (ROOT / item["path"]).read_bytes()
        assert len(raw) == item["bytes"] and sha(raw) == item["sha256"], item["path"]
        assert hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest() == item["blob"]
        assert gt("ls-files", "-s", "--", item["path"]).split()[0] == item["mode"]
        actual.append({key: item[key] for key in ("path", "blob", "bytes", "sha256", "mode")})
    delta = gt("diff", "--name-only", B9, SOURCE).splitlines()
    assert set(delta) == {"tool/perf_probe/run_installed_plugin_android.py",
                          "tool/perf_probe/test_installed_plugin_android.py",
                          "tool/perf_probe/INSTALLED_PLUGIN_ANDROID.md"}
    assert not gt("diff", "--name-only", B9, SOURCE, "--", "*.dart", "pubspec.yaml", "pubspec.lock")
    return {"source": SOURCE, "tree": SOURCE_TREE, "qaHead": head, "files": actual,
            "onlyThreeHostAndDocumentationPathsChangedFromB9": True,
            "allDartAndDependencySourceUnchanged": True}

def source_gate_evidence():
    _, summary = jone("prior-source", "summary.json")
    assert summary["sourceCommit"] == B9 and summary["sourceTree"] == "4900c1eb5bbfc2f53b8d2b2273029ef9f5aba1f1"
    assert summary["qaHead"] == "4f3cb2fbcf1540cba1e41691fc6c05016ca649de"
    assert summary["passed"] is True and len(summary["cases"]) == 13
    assert all(case["passed"] is True for case in summary["cases"])
    cases = {case["name"]: case["result"] for case in summary["cases"]}
    hook = cases["Exact original hook with nonempty staged candidate Dart files"]
    assert hook["hookSha256"] == "53b75db342d0332ae703c389562adf65a04d6127bd1ff05edaef0dde7b020097"
    assert set(hook["stagedDartPaths"]) == {
        "integration_test/installed_plugin_resource_probe_test.dart",
        "integration_test/support/installed_plugin_android_control.dart",
        "test/tool/perf_probe/installed_plugin_android_control_test.dart"}
    for name, timeout in (("install-original-hook", 900), ("original-staged-hook", 1200)):
        _, receipt = jone("prior-source", name + ".json")
        _, raw = one("prior-source", name + ".log")
        assert receipt["exitCode"] == 0 and receipt["timedOut"] is False
        assert receipt["timeoutSeconds"] == timeout
        assert receipt["outputBytes"] == len(raw) and receipt["outputSha256"] == sha(raw)
    before = jone("prior-source", "app-before.json")[1]
    after = jone("prior-source", "app-after.json")[1]
    assert before == after and not before["status"]
    dependency_before = jone("prior-source", "dependency-before.json")[1]
    dependency_after = jone("prior-source", "dependency-after.json")[1]
    assert dependency_before == dependency_after
    assert all(not record["status"] for record in dependency_before.values())
    packages = jone("prior-source", "resolved-git-packages.json")[1]
    assert {key: value["head"] for key, value in packages.items()} == GIT_PINS
    assert cases["All fourteen actual Android allocation and authenticated control tests"]["passed"] == 14
    assert cases["All fourteen actual Android allocation and authenticated control tests"]["skipped"] == 0
    assert cases["All forty-four existing Dart contracts including both formerly skipped Store tests"]["passed"] == 44
    assert cases["All forty-four existing Dart contracts including both formerly skipped Store tests"]["skipped"] == 0
    assert cases["Actual Node fixture and prepared Store controls without skips"]["pass"] == 10
    assert cases["Actual Node fixture and prepared Store controls without skips"]["skipped"] == 0
    assert cases["Actual Android host negative controls"]["passed"] == 45
    return {"source": B9, "sourceGatePassed": True, "originalHook": hook,
            "dartTests": 58, "nodeTests": 10, "oldPythonTests": 45,
            "reuseScope": "Only unchanged Dart, fixture/Store Node, SDK/dependency source; current Python freshly tested separately.",
            "newFlutterOrDartRunClaimed": False, "all19DependenciesAndSourceUnchanged": True}

def fast_evidence():
    summary = jone("fast", "summary.json")[1]
    assert summary["sourceCommit"] == SOURCE and summary["sourceTree"] == SOURCE_TREE
    assert summary["qaHead"] == FAST_HEAD and summary["passed"] is True
    assert len(summary["cases"]) == 6 and all(case["passed"] is True for case in summary["cases"])
    scope = jone("fast", "full-source-reuse-scope.json")[1]
    assert scope["source"] == SOURCE and scope["priorSource"] == B9
    assert scope["unchangedFiles"] == 4195 and scope["unchangedDartFiles"] == 3595
    assert scope["allOld45TestBodiesPreserved"] is True
    assert sha(git("ls-tree", "-rz", "--full-tree", B9)) == scope["oldTreeListingSha256"]
    assert sha(git("ls-tree", "-rz", "--full-tree", SOURCE)) == scope["newTreeListingSha256"]
    old = jone("fast", "old-source-status-reproduction.json")[1]
    assert old["sourceCommit"] == B9 and old["productionStatusesRejectedByOriginalConsumer"] is True
    assert old["actualDartDesktopStatuses"] == {"minimize": "unsupported", "hide": "unsupported"}
    assert old["nativeApplicationExecuted"] is False
    original_scope = jone("fast", "old-source-before-after.json")[1]
    assert original_scope["unchanged"] is True and original_scope["before"] == original_scope["after"]
    tests = jone("fast", "host-tests-summary.json")[1]
    assert tests["source"] == SOURCE and tests["discovered"] == tests["testsRun"] == 47
    assert len(tests["successes"]) == 47 and not tests["skipped"] and not tests["errors"] and not tests["failures"]
    assert tests["currentConsumerAcceptedActualProducerStatuses"] is True
    assert len(tests["newRegressionSubcases"]) == 20 and all(row["passed"] for row in tests["newRegressionSubcases"])
    assert len(tests["unexecutedPlatformMatrixNegatives"]) == 4
    assert jone("fast", "app-before.json")[1] == jone("fast", "app-after.json")[1]
    return {"passed": True, "newTests": 47, "newNegativeSubcases": 20,
            "platformMatrixNegatives": 4, "oldDefectActuallyReproduced": True,
            "all45OldTestBodiesUnchanged": True, "allOther4195SourceEntriesUnchanged": True}

def merge_evidence():
    summary = jone("merge", "summary.json")[1]
    assert summary["sourceCommit"] == SOURCE and summary["sourceTree"] == SOURCE_TREE
    assert summary["qaHead"] == FAST_HEAD and summary["passed"] is True
    assert all(case["passed"] is True for case in summary["cases"])
    rows = jone("merge", "merge-results.json")[1]
    assert len(rows) == 12
    clean, preexisting = [], []
    for row in rows:
        assert row["candidate"]["head"] == SOURCE and row["public"]["head"] == PUBLIC
        assert not row["additionalConflictMessages"] and not row["resolvedConflictMessages"]
        if row["classification"] == "MERGES_CLEANLY":
            assert row["candidate"]["exitCode"] == 0 and not row["candidate"]["conflicts"]
            clean.append({"number": row["number"], "head": row["head"],
                          "tree": row["candidate"]["resultTree"],
                          "rawSha256": row["candidate"]["rawSha256"]})
        else:
            assert row["classification"] == "PREEXISTING_CONFLICTS" and row["number"] == 4269
            assert row["actualConflictContentUnchanged"] is True
            old = row["public"]["conflictEvidence"]
            new = row["candidate"]["conflictEvidence"]
            assert old["stageEntries"] == new["stageEntries"] and len(new["stageEntries"]) == 86
            fields = ("path", "exists", "mode", "kind", "conflictHunks", "normalizedBytes", "normalizedSha256")
            assert [{key: value.get(key) for key in fields} for value in old["files"]] == [
                {key: value.get(key) for key in fields} for value in new["files"]]
            assert len(new["files"]) == 30 and new["totalHunks"] == 62
            preexisting.append({"number": 4269, "files": 30, "hunks": 62, "stageEntries": 86,
                                "conflictsRemain": True})
    assert len(clean) == 11 and len(preexisting) == 1
    before = jone("merge", "open-pr-map-before.json")[1]
    after = jone("merge", "open-pr-map-after-merge.json")[1]
    key = lambda value: {"dev": value["dev"], "prs": [
        {field: row[field] for field in ("number", "head", "base", "baseRef")} for row in value["prs"]]}
    assert key(before) == key(after) and len(after["prs"]) == 32
    assert jone("merge", "app-before.json")[1] == jone("merge", "app-after.json")[1]
    return {"targets": len(rows), "clean": clean, "preexisting": preexisting,
            "stablePublicPrCount": 32, "sourceUnchanged": True}

def snapshots_evidence():
    values = {}
    receipts = {}
    for mode in ("bind", "resolved", "before-native", "after"):
        values[mode] = jone("snapshots", mode + ".json")[1]
        receipt = jone("snapshots", mode + "-receipt.json")[1]
        receipts[mode] = receipt
        assert receipt["passed"] is True and receipt["sourceCommit"] == SOURCE
        assert receipt["sourceTree"] == SOURCE_TREE and receipt["qaHead"] == NATIVE_HEAD
        for label, item in values[mode].items():
            assert not item["status"]
            assert len(item["files"]) == item["trackedFiles"]
            rendered = json.dumps(item["files"], separators=(",", ":"), ensure_ascii=False).encode("utf-8")
            assert sha(rendered) == item["trackedSha256"], (mode, label)
        app = values[mode]["application"]
        assert app["head"] == NATIVE_HEAD and app["tree"] == NATIVE_TREE and app["trackedFiles"] == 4200
        table = {entry["path"]: entry for entry in app["files"]}
        for item in EXPECTED:
            assert table[item["path"]]["bytes"] == item["bytes"]
            assert table[item["path"]]["sha256"] == item["sha256"]
        assert values[mode]["flutter-sdk"]["head"] == SDK_HEAD
        if mode != "bind":
            packages = jone("snapshots", "resolved-git-packages-" + mode + ".json")[1]
            assert {name: item["head"] for name, item in packages.items()} == GIT_PINS
            for name, item in packages.items():
                assert values[mode][item["gitRoot"]]["head"] == GIT_PINS[name]
    for label in ("application", "flutter-sdk"):
        assert values["bind"][label] == values["resolved"][label]
    assert values["resolved"] == values["before-native"] == values["after"]
    _, analyze = one("snapshots", "qa-full-analyze.log")
    assert "No issues found!" in analyze.decode("utf-8", "strict")
    native_job = api_json("/repos/Otzaria/otzaria/actions/jobs/" + str(NATIVE_JOB))
    assert native_job["run_id"] == NATIVE_RUN and native_job["status"] == "completed"
    by_name = {step["name"]: step for step in native_job["steps"]}
    for name in ("Full analysis on exact native candidate",
                 "Bind exact source and SDK before strict resolution",
                 "Snapshot immediately before native emulator app",
                 "Preserve source, SDK and all Git dependencies after native execution"):
        assert by_name[name]["conclusion"] == "success", name
    save("native-job.json", native_job)
    return {"allFourSnapshotsPassed": True, "sourceFilesWithQa": 4200,
            "allTrackedSourceIndexSdkAndDependenciesUnchanged": True,
            "gitPackageCount": len(GIT_PINS), "sdk": SDK_HEAD,
            "currentCandidateFullAnalyze": "PASS", "analyzeLogBytes": len(analyze),
            "analyzeLogSha256": sha(analyze),
            "allPins": GIT_PINS, "nativeJobConclusion": native_job["conclusion"]}

def final_app_evidence():
    host_path, host_raw = one("native", "host-report.json")
    device_path, device_raw = one("native", "installed-plugin-report.json")
    host, device = json.loads(host_raw), json.loads(device_raw)
    assert host["status"] == "passed", host.get("primaryFailure", host.get("error", host["status"]))
    assert host.get("primaryFailure") is None and not host.get("secondaryErrors")
    assert host.get("error") is None and host.get("replyError") is None
    assert host["sourceCommit"] == NATIVE_HEAD and host["sourceTree"] == NATIVE_TREE
    assert host["mode"] == "debug" and host["emulator"] is True
    assert host["physicalProfileRelease"]["status"] == host["performanceAcceptance"]["status"] == "notRun"
    assert host["serial"] == "emulator-5554"
    assert host["device"]["abi"] == "x86_64" and host["device"]["sdk"] == "34"
    assert host["flutter"]["frameworkRevision"] == SDK_HEAD
    assert host["flutter"]["frameworkVersion"] == "3.47.7" and host["flutter"]["dartSdkVersion"] == "3.13.5"
    assert host["flutter"]["engineRevision"] == ENGINE_HEAD
    expected_native = {name: value for name, value in GIT_PINS.items() if name.startswith("flutter_inappwebview")}
    assert len(expected_native) == 8 and host["dependencies"]["nativePins"] == expected_native
    lock = next(item for item in EXPECTED if item["path"] == "pubspec.lock")
    assert host["dependencies"]["lockSha256"] == lock["sha256"]
    assert host["apk"]["package"] == PACKAGE and host["apk"]["activity"] == "org.otzaria.otzaria.MainActivity"
    assert host["apk"]["debuggable"] is True and type(host["apk"]["bytes"]) is int and host["apk"]["bytes"] > 0
    assert re.fullmatch(r"[0-9a-f]{64}", host["apk"]["sha256"])
    bootstrap = host["bootstrap"]
    assert type(bootstrap["protocol"]) is int and bootstrap["protocol"] == 1
    assert bootstrap["package"] == PACKAGE and bootstrap["campaignId"] == host["campaignId"]
    assert re.fullmatch(r"campaign-[0-9a-f]{32}", host["campaignId"])
    assert type(bootstrap["pid"]) is int and bootstrap["pid"] > 0
    assert re.fullmatch(str(bootstrap["pid"]) + r"-[0-9]+", bootstrap["runId"])
    assert type(bootstrap["port"]) is int and 0 < bootstrap["port"] < 65536
    assert re.fullmatch(r"cache/otzaria-installed-probe-[A-Za-z0-9_-]+/output/installed-plugin-report\.json",
                        bootstrap["reportPath"])
    complete = host["completion"]
    assert complete["frameworkPassed"] is True and complete["reportBytes"] == len(device_raw)
    assert complete["reportSha256"] == sha(device_raw)
    for key, expected in {
        "schemaVersion": 1, "status": "passed", "platform": "android", "buildMode": "debug",
        "pid": bootstrap["pid"], "runId": bootstrap["runId"], "commit": NATIVE_HEAD,
        "machineId": "emulator-5554", "physicalDeviceAcceptance": False,
        "frameworkPassed": True, "policyRestored": True, "setupStep": "complete",
    }.items():
        assert device.get(key) == expected, (key, device.get(key))
    assert device["frameworkPassed"] is True and device["physicalDeviceAcceptance"] is False
    assert device["flutterVersion"] == "3.47.7" and device["dartVersion"].startswith("3.13.5")
    for name in ("errors", "contractErrors", "testFailures"):
        assert device.get(name) == [], (name, device.get(name))
    for key in ("protocol", "campaignId", "runId", "pid", "package"):
        assert device["androidControl"][key] == bootstrap[key], key
    assert device["androidControl"]["physicalProfileRelease"] == "notRun"
    assert device["platformMatrix"]["android"]["status"] == "passed"
    assert all(device["platformMatrix"][platform]["status"] == "notRun"
               for platform in ("windows", "macos", "linux", "ios"))
    assert device["isolatedPaths"]["allocatedPrivateTemp"] is True
    assert device["isolatedPaths"]["output"].endswith("/" + bootstrap["reportPath"].rsplit("/", 1)[0])
    assert device["pinnedStore"]["commit"] == STORE_COMMIT and device["pinnedStore"]["sha256"] == STORE_HASHES
    assert device["pinnedStore"]["otherCommonPlugins"]["status"] == "notRun"
    assert device["observer"]["developerDiagnosticsCollecting"] is False
    provenance = json.loads(native_file("store-source/source-provenance.json"))
    assert provenance["commit"] == STORE_COMMIT and provenance["sha256"] == STORE_HASHES
    for name, expected in STORE_HASHES.items():
        assert sha(native_file("store-source/" + name)) == expected, name
    return {"hostFile": host_path, "hostBytes": len(host_raw), "hostSha256": sha(host_raw),
            "deviceFile": device_path, "deviceBytes": len(device_raw), "deviceSha256": sha(device_raw),
            "frameworkPassed": True, "frameworkEvidence": "Final device JSON after allTestsPassed, bound by the completion payload digest and length; no separate Flutter-drive report exists.",
            "campaignId": host["campaignId"], "pid": bootstrap["pid"], "runId": bootstrap["runId"],
            "privateCacheReportPath": bootstrap["reportPath"], "apk": host["apk"],
            "apkRawBytesIncludedInArtifact": False, "pinnedStoreFilesVerified": 5,
            "deviceMetadata": host["device"], "webViewRuntime": device.get("webViewRuntime"),
            "physicalProfileRelease": "NOT_RUN", "performanceAcceptance": "NOT_RUN"}

def scenario_evidence():
    device = jone("native", "installed-plugin-report.json")[1]
    host = jone("native", "host-report.json")[1]
    required = {"startup", "firstOpen", "visibleIdle", "stateAndScroll", "multipleOpen", "hiddenIdle",
                "memoryPressure", "restore", "protectedControls", "countPolicy", "agePolicy", "storeRestore",
                "backgroundOpen", "backgroundIdle", "backgroundClose", "close", "closedIdle", "osBackground"}
    phases = {phase["name"]: phase for phase in device["phases"]}
    assert len(phases) == len(device["phases"]) == 20 and set(phases) == required | {"minimize", "hide"}
    assert all(phases[name]["status"] == "passed" for name in required)
    assert phases["minimize"]["status"] == phases["hide"]["status"] == "unsupported"
    policy = device["defaultPolicy"]
    assert type(policy["maxLiveSuspended"]) is int and policy["maxLiveSuspended"] > 0
    # The accepted count follows the actual platform policy, not a desktop fixture count.
    eligible = phases["multipleOpen"]["eligibleCount"]
    assert type(eligible) is int and eligible == policy["maxLiveSuspended"] + 1
    assert phases["multipleOpen"]["platformThreshold"] == policy["maxLiveSuspended"]
    assert phases["multipleOpen"]["guardCount"] == 4 and phases["multipleOpen"]["keeperCount"] == 1
    assert policy == {"maxLiveSuspended": 2, "maxSuspendedAgeMs": 900000}, policy
    proofs = device["restorations"]
    grouped = {name: [proof for proof in proofs if proof["scenario"] == name]
               for name in ("pressure", "count", "age", "store")}
    assert len(grouped["pressure"]) == eligible
    assert all(len(grouped[name]) == 1 for name in ("count", "age", "store"))
    assert len(proofs) == eligible + 3
    restored_instances = set()
    for proof in proofs:
        for flag in ("sameInstanceId", "releasedByDispatcher", "controllerAbsentAfterDiscard",
                     "hostWidgetRemovedBeforeRestore", "differentControllerObject", "differentDocument",
                     "sdkBooted", "visibleStateMatches"):
            assert proof[flag] is True, (proof["scenario"], flag)
        before, after = proof["before"], proof["after"]
        for key in ("pluginId", "instanceId"):
            assert isinstance(before[key], str) and before[key] and before[key] == after[key]
        assert type(before["controllerObjectId"]) is int and type(after["controllerObjectId"]) is int
        for value in (before["documentToken"], after["documentToken"]):
            assert isinstance(value, str) and value
        assert before["documentToken"] != after["documentToken"]
        assert number(proof["resumeMs"]) and proof["resumeMs"] >= 0
        previous, current = dict(proof["beforeVisibleState"]), dict(proof["afterVisibleState"])
        left_scroll, right_scroll = previous.pop("scrollTop"), current.pop("scrollTop")
        assert number(left_scroll) and number(right_scroll) and abs(left_scroll - right_scroll) <= 2
        assert previous == current
        if proof["scenario"] != "store":
            assert proof["receivedBootRestore"]["reason"] == "discarded"
            assert proof["receivedBootRestore"]["state"] == proof["acceptedRestoreStateBeforeDiscard"]
        else:
            assert proof["receivedBootRestore"]["availability"] == "unavailable"
        if proof["scenario"] == "pressure":
            restored_instances.add((before["pluginId"], before["instanceId"]))
    assert len(restored_instances) == eligible
    guards = device["protectedControls"]
    assert len(guards) == 4
    assert {guard["firstBlockingReason"] for guard in guards} == {"noRestoreState", "unsavedChanges", "busyRpc", "contextMenu"}
    assert len({guard["discardRequestId"] for guard in guards}) == 1 and guards[0]["discardRequestId"]
    assert all(guard["sameControllerAfterRequest"] is True and guard["released"] is False for guard in guards)
    assert guards[0]["discardRequestId"] == phases["memoryPressure"]["discardRequestId"]
    store = phases["storeRestore"]
    assert store["readyBeforeScroll"]["rendering"]["pendingScroll"] is None
    scroll = store["scrollAssignment"]
    assert scroll["requestedScrollTop"] == 420 and scroll["actualScrollTop"] > 200
    os_phase = phases["osBackground"]
    assert os_phase["lifecycleBeforeQuiet"] == "paused" and os_phase["lifecycleAfterResume"] == "resumed"
    assert os_phase["dispatcherBeforeQuiet"] == "hidden" and os_phase["dispatcherAfterResume"] == "active"
    assert os_phase["shownBeforeQuiet"] is False and os_phase["shownAfterResume"] is True
    assert os_phase["discardCandidateBeforeQuiet"] is True
    for flag in ("sameControllerAfterResume", "sameDocumentAfterResume", "visibleStateMatches"):
        assert os_phase[flag] is True, flag
    keys = ("pluginId", "instanceId", "controllerObjectId", "nativeViewId", "documentToken")
    assert all(os_phase["before"][key] == os_phase["after"][key] for key in keys)
    for key in ("home", "hostQuiet", "resume"):
        assert os_phase[key] == host["evidence"][key]
    assert device["policyRestored"] is True
    return {"passedPhaseCount": len(required), "unsupportedDesktopPhaseCount": 2,
            "platformPolicy": policy, "eligiblePressureCandidates": eligible,
            "restoreFormula": "pressure = maxLiveSuspended + 1; total = pressure + count + age + Store",
            "restorations": len(proofs), "restorationsByScenario": {key: len(value) for key, value in grouped.items()},
            "protectedControls": len(guards), "policyRestored": True,
            "sameControllerDocumentAndVisibleStateAfterActualHomeResume": True}

def native_boundary_evidence():
    host = jone("native", "host-report.json")[1]
    commands = command_rows()
    original = host["originalNative"]
    bootstrap = host["bootstrap"]
    home, resume = host["evidence"]["home"], host["evidence"]["resume"]
    records = [("original", original, True), ("home-before", home["before"], True),
               ("home-after", home["after"], False), ("resume-before", resume["before"], False),
               ("resume-after", resume["after"], True), ("final", host["finalNative"], True)]
    launcher = host["device"]["home"]
    record_re = re.compile(r"ActivityRecord\{([A-Za-z0-9]+)\s+u([0-9]+)\s+([\w.$/]+)\s+t([0-9]+)")
    def normalize(value):
        package, activity = value.split("/")
        return package + "/" + (package + activity if activity.startswith(".") else activity)
    def activities(raw):
        found = []
        for match in record_re.finditer(raw):
            found.append((match[1], int(match[2]), normalize(match[3]), int(match[4])))
        return found
    def as_tuple(value):
        return (value["token"], value["user"], value["component"], value["taskId"])
    observed_rows = []
    for name, value, foreground in records:
        assert value["process"] == original["process"] and value["process"]["pid"] == bootstrap["pid"]
        assert type(value["process"]["startTicks"]) is int and value["process"]["startTicks"] > 0
        assert value["activity"] == original["activity"] and value["activity"]["component"] == COMPONENT
        assert value["activity"]["user"] == 0 and value["resumedActivity"]["user"] == 0
        assert value["serial"] == "emulator-5554" and value["package"] == PACKAGE
        assert value["resumedActivity"] == value["activity"] if foreground else (
            value["resumedActivity"]["component"] == launcher and value["resumedActivity"] != value["activity"])
        indexes = value["commands"]
        assert len(indexes) == 3 and indexes == list(range(indexes[0], indexes[0] + 3))
        pid_cmd, stat_cmd, activity_cmd = [commands[index] for index in indexes]
        for command in (pid_cmd, stat_cmd, activity_cmd):
            assert command["exitCode"] == 0 and not command.get("error")
        assert pid_cmd["argv"][3:] == ["shell", "pidof", PACKAGE]
        assert stat_cmd["argv"][3:] == ["shell", "-T", "run-as", PACKAGE, "cat", "/proc/" + str(bootstrap["pid"]) + "/stat"]
        assert activity_cmd["argv"][3:] == ["shell", "dumpsys", "activity", "activities"]
        raw_pid = native_file(pid_cmd["stdout"]).decode("ascii").strip()
        assert raw_pid == str(bootstrap["pid"])
        raw_stat = native_file(stat_cmd["stdout"]).decode("utf-8").strip()
        end_name = raw_stat.rfind(")")
        assert raw_stat.split(" ", 1)[0] == raw_pid and end_name > 0
        stat_fields = raw_stat[end_name + 1:].split()
        assert len(stat_fields) >= 20 and int(stat_fields[19]) == original["process"]["startTicks"]
        raw_activity = native_file(activity_cmd["stdout"]).decode("utf-8")
        target_records = {entry for entry in activities(raw_activity) if entry[2] == COMPONENT}
        top_records = set()
        for line in raw_activity.splitlines():
            if re.match(r"\s*(topResumedActivity|mResumedActivity)\s*[:=]", line):
                top_records.update(activities(line))
        assert target_records == {as_tuple(value["activity"])}
        assert top_records == {as_tuple(value["resumedActivity"])}
        observed_rows.append({"name": name, "foreground": foreground, "process": value["process"],
                              "activity": value["activity"], "resumedActivity": value["resumedActivity"],
                              "commands": indexes, "atMonotonic": value["monotonic"]})
    homes = [row for row in commands if row["argv"][3:] == ["shell", "input", "keyevent", "KEYCODE_HOME"]]
    resumes = [row for row in commands if row["argv"][3:] == [
        "shell", "am", "start", "-W", "--activity-single-top", "--activity-reorder-to-front",
        "-n", COMPONENT, "-a", "android.intent.action.MAIN"]]
    assert len(homes) == len(resumes) == 1 and homes[0]["exitCode"] == resumes[0]["exitCode"] == 0
    assert homes[0]["stage"] == "home" and resumes[0]["stage"] == "resume"
    assert homes[0]["finishedMonotonic"] <= home["after"]["monotonic"]
    assert home["before"]["monotonic"] <= homes[0]["startedMonotonic"]
    assert resume["before"]["monotonic"] <= resumes[0]["startedMonotonic"]
    assert resumes[0]["finishedMonotonic"] <= resume["after"]["monotonic"]
    return {"observedBoundaryCount": len(records), "boundaries": observed_rows,
            "sameNativeProcessStartTicksAndActivityTask": True,
            "oneActualHomeCommand": homes[0]["number"], "oneSameActivityResumeCommand": resumes[0]["number"],
            "rawPidProcStatAndDumpsysValidated": True}

def quiet_cleanup_evidence():
    host = jone("native", "host-report.json")[1]
    device = jone("native", "installed-plugin-report.json")[1]
    commands = command_rows()
    quiet = host["evidence"]["hostQuiet"]
    start, finish = quiet["startedMonotonic"], quiet["finishedMonotonic"]
    assert number(start) and number(finish) and finish > start
    assert quiet["requestedMs"] == 1500 and quiet["elapsedMs"] >= 1500 and quiet["hostCommands"] == 0
    assert abs(quiet["elapsedMs"] - (finish - start) * 1000) < 0.001
    assert all(row["finishedMonotonic"] <= start or row["startedMonotonic"] >= finish for row in commands)
    windows = device["quietWindows"]
    expected = {"visibleIdle", "hiddenIdle", "osBackgroundIdle", "backgroundIdle", "closedIdle"}
    assert len(windows) == 5 and {window["name"] for window in windows} == expected
    for window in windows:
        assert window["probeJsCalls"] == window["probeNativeQueries"] == 0
        assert window["productionTimersDisabled"] is False
        assert window["requestedMs"] == 1500 and number(window["elapsedMs"]) and window["elapsedMs"] >= 1500
    cleanup = host["cleanup"]
    forward = [record for record in cleanup if "ownedForward" in record]
    stop = [record for record in cleanup if "stoppedOwnedPackageAfterOutcome" in record]
    assert len(forward) == len(stop) == 1
    assert (forward[0]["removed"] is True and forward[0]["alreadyAbsent"] is False) or (
        forward[0]["removed"] is False and forward[0]["alreadyAbsent"] is True)
    assert stop[0]["stoppedOwnedPackageAfterOutcome"] == PACKAGE
    stop_commands = [row for row in commands if row["argv"][3:6] == ["shell", "am", "force-stop"]]
    assert len(stop_commands) == 1 and stop_commands[0]["argv"][6:] == [PACKAGE]
    assert stop_commands[0]["stage"] == "afterOutcome" and stop_commands[0]["exitCode"] == 0
    assert stop_commands[0]["startedMonotonic"] >= host["finalNative"]["monotonic"]
    gone = [row for row in commands if row["number"] > stop_commands[0]["number"]
            and row["argv"][3:] == ["shell", "pidof", PACKAGE] and row["exitCode"] == 1]
    assert gone and not native_file(gone[-1]["stdout"]).strip() and not native_file(gone[-1]["stderr"]).strip()
    assert all("kill-server" not in row["argv"] for row in commands)
    expected_forward = ["emulator-5554", "tcp:" + str(forward[0]["ownedForward"]), "tcp:" + str(host["bootstrap"]["port"])]
    lists = [row for row in commands if row["stage"] == "afterOutcome" and row["argv"][3:] == ["forward", "--list"]]
    assert len(lists) == 1 and lists[0]["exitCode"] == 0
    table = [line.split() for line in native_file(lists[0]["stdout"]).decode("utf-8").splitlines()]
    matching = [row for row in table if len(row) == 3 and row[1] == expected_forward[1]]
    assert matching == [expected_forward] if forward[0]["removed"] else not matching
    removed = [row for row in commands if row["argv"][3:] == ["forward", "--remove", expected_forward[1]]]
    if forward[0]["removed"]:
        assert len(removed) == 1 and removed[0]["exitCode"] == 0 and removed[0]["stage"] == "afterOutcome"
    else:
        assert not removed
    optional_errors = [row for row in cleanup if "logcatError" in row or "partialReportError" in row]
    assert all(not any(key.endswith("Error") for key in row) or row in optional_errors for row in cleanup)
    return {"quietWindowCount": len(windows), "quietNames": sorted(expected),
            "hostQuietMs": quiet["elapsedMs"], "hostCommandsDuringQuiet": 0,
            "probeJsOrNativeQueriesDuringQuiet": 0, "productionTimersRemainEnabled": True,
            "ownedForward": forward[0], "ownedPackageCleanup": stop[0], "processExitObserved": True,
            "optionalDiagnosticErrors": optional_errors, "commandsChecked": len(commands)}

def export_native_diagnostics():
    """Preserve first, then read only; no imported/executed artifact content."""
    files = FILE_DATA["native"]
    summaries = {}
    for name in ("host-report.json", "installed-plugin-report.json",
                 "partial-installed-plugin-report.json"):
        matches = [path for path in files if PurePosixPath(path).name == name]
        if len(matches) == 1:
            value = json.loads(files[matches[0]])
            keys = ("status", "stage", "primaryFailure", "error", "secondaryErrors",
                    "replyError", "completion", "bootstrap", "frameworkPassed",
                    "testFailures", "errors", "contractErrors", "setupStep",
                    "phases", "defaultPolicy", "restores", "guardResults",
                    "cleanup", "evidence")
            summaries[name] = {key: value[key] for key in keys if key in value}
    # The control token is not needed for diagnosis and must never reach the log.
    secrets = []
    for path, data in files.items():
        if PurePosixPath(path).name == "defines.json":
            definitions = json.loads(data)
            for key, value in definitions.items():
                if "TOKEN" in key.upper() and isinstance(value, str) and value:
                    secrets.append(value.encode())
    receipt_paths = [path for path in files if PurePosixPath(path).name == "commands.jsonl"]
    diagnostics, budget = [], 8 * 1024 * 1024
    if len(receipt_paths) == 1:
        receipts = [json.loads(line) for line in files[receipt_paths[0]].splitlines() if line]
        native_root = PurePosixPath(receipt_paths[0]).parent
        for row in receipts:
            diagnostic = {key: row.get(key) for key in
                          ("number", "stage", "argv", "exitCode", "error",
                           "startedMonotonic", "finishedMonotonic")}
            diagnostic["streams"] = []
            for stream in ("stdout", "stderr"):
                relative = row.get(stream)
                if not isinstance(relative, str):
                    continue
                path = str(native_root / relative)
                if path not in files:
                    diagnostic["streams"].append({"path": path, "availability": "missing"})
                    continue
                raw = files[path]
                record = {"path": path, "bytes": len(raw), "sha256": sha(raw)}
                diagnostic["streams"].append(record)
                if any(secret in raw for secret in secrets):
                    record["logExport"] = "withheld: contains ephemeral control token"
                elif len(raw) > 1024 * 1024 or len(raw) > budget:
                    record["logExport"] = "withheld: bounded output; exact ZIP retained"
                elif raw:
                    export_raw("native", PurePosixPath(path).name)
                    budget -= len(raw)
                    record["logExport"] = "exact bytes exported"
                else:
                    record["logExport"] = "empty stream"
            diagnostics.append(diagnostic)
    result = {"originalRun": NATIVE_RUN, "originalJob": NATIVE_JOB,
              "nativeHead": NATIVE_HEAD, "reports": summaries,
              "commands": diagnostics, "diagnosisOnly": True,
              "doesNotOverrideOriginalFailure": True}
    encoded = json.dumps(result, ensure_ascii=False)
    assert not any(secret.decode() in encoded for secret in secrets)
    save("native-failure-diagnostic.json", result)
    print("BEGIN_QA4428_NATIVE_DIAGNOSTIC", flush=True)
    print(encoded, flush=True)
    print("END_QA4428_NATIVE_DIAGNOSTIC", flush=True)
    return {"reports": list(summaries), "commandReceipts": len(diagnostics),
            "diagnosisOnly": True}

before = source_snapshot()
report = {"schemaVersion": 1, "source": SOURCE, "sourceTree": SOURCE_TREE,
          "qaHead": gt("rev-parse", "HEAD"), "nativeHead": NATIVE_HEAD,
          "nativeRun": NATIVE_RUN, "nativeJob": NATIVE_JOB,
          "status": "BLOCKED", "nativeAcceptance": "PENDING",
          "artifactCodeExecuted": False, "nativeCodeExecutedByReader": False,
          "physicalProfileRelease": "NOT_RUN", "performanceAcceptance": "NOT_RUN",
          "frameworkContract": "Android stores its final allTestsPassed verdict and testFailures in the device report, authenticated by complete bytes/SHA; no separate Flutter-drive report is expected.",
          "priorFailuresRemainFailures": [
              {"run": 42317101114, "status": "FAILED_BEFORE_APP_MAIN",
               "reason": "Original VM code_cache report root rejected before authenticated bootstrap",
               "artifactId": 13551678210, "artifactBytes": 302912,
               "artifactSha256": "73b1d2ccc6922c0cd0d67701b13a7ca21a61350cef6a7d75504b1cc88dcf989b"},
              {"run": 42334734084, "status": "BLOCKED_FORMATTER", "source": "b22d17645c5c4650ddf9cdb05d5b2b53af8932c9"},
              {"source": B9, "status": "BLOCKED_DESKTOP_STATUS_CONTRACT", "nativeRun": "NOT_RUN"}],
          "limits": [
              "Functional evidence from an API 34 x86_64 emulator DEBUG build only.",
              "No memory, CPU, energy, GPU or physical profile/release acceptance.",
              "APK bytes are not retained in the artifact; exact build/install command receipts and the runtime APK digest/badging are retained.",
              "Raw control stream envelopes are not logged by the original runner; final complete digest, device/host identities and the observed native boundaries are independently verified from retained data."
          ]}
try:
    assert not before["status"], before["status"]
    check("Exact candidate source, identity and unchanged Dart/dependency scope", verify_checkout)
    assert {spec["role"] for spec in ARTIFACTS} == {"native", "snapshots", "fast", "merge", "prior-source"}
    for spec in ARTIFACTS:
        check("Exact retained archive " + spec["role"], lambda spec=spec: download(spec))
    # Export original native evidence before acceptance checks so partial failures survive.
    if "native" in FILE_DATA:
        for name in ("host-report.json", "installed-plugin-report.json",
                     "partial-installed-plugin-report.json", "commands.jsonl"):
            matches = [path for path in FILE_DATA["native"] if PurePosixPath(path).name == name]
            if len(matches) == 1:
                export_raw("native", name)
            else:
                RAW_EXPORTS.append({"role": "native", "name": name, "matches": matches,
                                    "availability": "missing" if not matches else "ambiguous"})
    check("Read original native failure and bounded raw command streams", export_native_diagnostics)
    check("Original b9 source, hook and all19 dependency evidence for exact unchanged scope", source_gate_evidence)
    check("Independent current host regressions and actual old consumer rejection", fast_evidence)
    check("Full fresh PR map and actual merge stage and hunk evidence", merge_evidence)
    check("Native source, index, SDK and all19 Git snapshots and fresh full analyze", snapshots_evidence)
    check("Actual final framework verdict, private cache, complete digest, APK and Store", final_app_evidence)
    check("All actual scenario phases, platform-derived restorations, guards and policy", scenario_evidence)
    check("Raw native PID, process start time, activity, Home and same-activity resume", native_boundary_evidence)
    check("Quiet command intervals and strictly owned forward/package cleanup", quiet_cleanup_evidence)
    def workflow_outcome():
        run = api_json("/repos/Otzaria/otzaria/actions/runs/" + str(NATIVE_RUN))
        job = api_json("/repos/Otzaria/otzaria/actions/jobs/" + str(NATIVE_JOB))
        assert run["head_sha"] == NATIVE_HEAD and run["status"] == "completed"
        assert job["run_id"] == NATIVE_RUN and job["status"] == "completed"
        save("native-run.json", run)
        save("native-job.json", job)
        assert run["conclusion"] == job["conclusion"] == "success", (run["conclusion"], job["conclusion"])
        return {"run": NATIVE_RUN, "job": NATIVE_JOB, "head": NATIVE_HEAD, "conclusion": "success"}
    check("Actual native workflow completed successfully", workflow_outcome)
except Exception as error:
    report["readerFailure"] = {"error": str(error), "traceback": traceback.format_exc()}
finally:
    after = source_snapshot()
    source_clean = before == after
    report.update(checks=CHECKS, artifacts=ARCHIVES, rawExports=RAW_EXPORTS,
                  sourceAndIndexUnchanged=source_clean, trackedReaderCheckoutFiles=len(after["files"]))
    passed = bool(CHECKS) and all(row["passed"] for row in CHECKS) and not report.get("readerFailure") and source_clean
    report["status"] = "PASS" if passed else "BLOCKED"
    report["nativeAcceptance"] = report["status"]
    report["publicationAllowedByThisReadOnlyGate"] = passed
    save("source-before.json", before)
    save("source-after.json", after)
    save("android-independent-artifact-review.json", report)
    print("BEGIN_QA4428_ANDROID_ARTIFACT_REVIEW", flush=True)
    print(json.dumps(report, ensure_ascii=False), flush=True)
    print("END_QA4428_ANDROID_ARTIFACT_REVIEW", flush=True)
raise SystemExit(0 if report["status"] == "PASS" else 1)
