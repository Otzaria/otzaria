#!/usr/bin/env python3
"""Independent, source-bound QA. This file is never part of PR 4428."""
import ast
import hashlib
import tempfile
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

SOURCE = "4d627791faf270a9ab9ccee14e07a7a537cc1c97"
SOURCE_TREE = "a63d42cb87f01433c3848f7077d23b1ea3cb0854"
PUBLIC = "9fdc05b9dc98c732affeb91bd78062ea369387dc"
HOOK_SHA256 = "53b75db342d0332ae703c389562adf65a04d6127bd1ff05edaef0dde7b020097"
EXPECTED = json.loads(r'''[{"path":".github/workflows/installed_plugin_probe_android.yml","mode":"100644","sha":"f731b8607b72c4f583bee251f3c1215224f349bc","bytes":4233,"sha256":"6828b039ca7c6b09125a0e6c4cdf41c6c118f5bc93da9b862d516b7cf4415216"},{"path":"android/app/build.gradle","mode":"100644","sha":"1ea47509d93d48688a7be4e328355b777347be11","bytes":3595,"sha256":"7f4bb82fb21cf82d8b93e76551b541e13c9061cecc5075effa8e1d06c8ce91cd"},{"path":"integration_test/installed_plugin_resource_probe_test.dart","mode":"100644","sha":"3fff9055bd0f023776d65b87a79ea94656d69488","bytes":59604,"sha256":"c6de4983280a44f03215f79e781870dd30f2f7a528117188ce6f9eda3924bc8a"},{"path":"integration_test/support/installed_plugin_android_control.dart","mode":"100644","sha":"7755b10653ad65bd6e13c6aa5ab76c1799b0d51f","bytes":7847,"sha256":"f44ed3d8c2937730325dca609b6a6e81fff8d4f2210b30eaf2d3ad0309d9272f"},{"path":"pubspec.lock","mode":"100644","sha":"5e175ffefe86620541f53dcf8172b9c0f412b2bd","bytes":66487,"sha256":"7cb40007d9484e613567165ea97b2ead3426a50c60c16a7e6fa874af32a27faf"},{"path":"pubspec.yaml","mode":"100644","sha":"332081188494a74e08c57595eb01ec882c0f97e3","bytes":13609,"sha256":"70eda15deb3977c28e581205f8242f6f0ffa368ab82fc17aee0877c29e64b232"},{"path":"test/tool/perf_probe/installed_plugin_android_control_test.dart","mode":"100644","sha":"72a0868e65a85dc9df7590377f7234019ad340b4","bytes":15880,"sha256":"18123632280b024183c3b7403ff16e04d5f540eb7ed5fef7a678fe987a68df6e"},{"path":"tool/perf_probe/INSTALLED_PLUGIN_ANDROID.md","mode":"100644","sha":"0386efac664bdba1e09163d6b28f0ef8d8684a96","bytes":13242,"sha256":"f4125059d0ced6d28a24d11f2f6e90503b0642d00a0ba9c6f85c2bca627dd15e"},{"path":"tool/perf_probe/run_installed_plugin_android.py","mode":"100644","sha":"ed52fbaf1afc0c70dc554db7e922ba76b097b560","bytes":44385,"sha256":"ba03044836f876de02399220b3b6ae09b535eb23118363ee680652d692f10cc4"},{"path":"tool/perf_probe/test_installed_plugin_android.py","mode":"100644","sha":"4c1be8c609b3d5ee69b4a9be84bb1b537cc6a91c","bytes":55457,"sha256":"53da871ca89837cc62416f669c3237636a6936cfa17d29d10aa9f1f3707756e0"}]''')
SOURCE_DELTA_PATHS = ["integration_test/installed_plugin_resource_probe_test.dart","integration_test/support/installed_plugin_android_control.dart","test/tool/perf_probe/installed_plugin_android_control_test.dart","tool/perf_probe/INSTALLED_PLUGIN_ANDROID.md","tool/perf_probe/run_installed_plugin_android.py","tool/perf_probe/test_installed_plugin_android.py"]
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

HOST_SUITE_SOURCE = json.loads(r'''"import copy\nimport json\nfrom pathlib import Path\nimport re\nimport sys\nimport unittest\n\nsys.dont_write_bytecode = True\nROOT = Path(sys.argv[1]).resolve()\nOUT = Path(sys.argv[2]).resolve()\nsys.path.insert(0, str(ROOT))\nfrom tool.perf_probe import test_installed_plugin_android as tests\n\ndart = (ROOT / \"integration_test/installed_plugin_resource_probe_test.dart\").read_text(encoding=\"utf-8\")\nassert \"await desktopVisibility(first);\\n    await androidVisibility(first);\" in dart\nstart = dart.index(\"  Future<void> desktopVisibility(ToolTab tab)\")\nend = dart.index(\"  Future<void> androidVisibility(ToolTab tab)\", start)\nbranch = dart[start:end].split(\"if (!_desktop.contains(os)) {\", 1)[1].split(\"return;\", 1)[0]\nnames = re.search(r\"for \\(final name in \\[([^]]+)\\]\\)\", branch)\nstatus = re.search(r\"'status': '([^']+)'\", branch)\nassert names and status\nproduced = {name: status.group(1) for name in re.findall(r\"'([^']+)'\", names.group(1))}\nassert produced == {\"minimize\": \"unsupported\", \"hide\": \"unsupported\"}\nplatforms = re.search(r\"const _desktop = \\{([^}]+)\\};\", dart)\nassert platforms and \"android\" not in re.findall(r\"'([^']+)'\", platforms.group(1))\ncase = tests.ReportTests(\"test_complete_controlled_report_is_accepted\")\ncase.setUp()\nfor phase in case.report[\"phases\"]:\n    if phase[\"name\"] in produced:\n        phase[\"status\"] = produced[phase[\"name\"]]\naccepted = case.validate()\nassert accepted[\"status\"] == \"passed\"\nmatrix_controls = []\nfor platform in (\"windows\", \"macos\", \"linux\", \"ios\"):\n    changed = copy.deepcopy(case.report)\n    changed[\"platformMatrix\"][platform][\"status\"] = \"unsupported\"\n    try:\n        case.validate(changed)\n    except ValueError as error:\n        assert str(error) == \"Unexecuted platform reported as passed\", str(error)\n        matrix_controls.append({\"platform\": platform, \"rejectedStatus\": \"unsupported\", \"error\": str(error)})\n    else:\n        raise AssertionError(\"Unexecuted platform matrix accepted unsupported: \" + platform)\n\nclass RecordedResult(unittest.TextTestResult):\n    def __init__(self, *args, **kwargs):\n        super().__init__(*args, **kwargs)\n        self.success_ids = []\n        self.subtests = []\n    def addSuccess(self, test):\n        self.success_ids.append(test.id())\n        super().addSuccess(test)\n    def addSubTest(self, test, subtest, err):\n        self.subtests.append({\"test\": test.id(), \"case\": str(subtest), \"passed\": err is None})\n        super().addSubTest(test, subtest, err)\n\nsuite = unittest.defaultTestLoader.loadTestsFromModule(tests)\ndiscovered = suite.countTestCases()\nresult = unittest.TextTestRunner(verbosity=2, stream=sys.stdout, resultclass=RecordedResult).run(suite)\nregression_names = {\n    \"tool.perf_probe.test_installed_plugin_android.ReportTests.test_desktop_visibility_requires_explicit_unsupported_status\",\n    \"tool.perf_probe.test_installed_plugin_android.ReportTests.test_missing_desktop_visibility_phase_or_status_is_rejected\",\n}\nregressions = [row for row in result.subtests if row[\"test\"] in regression_names]\nsummary = {\n    \"source\": \"4d627791faf270a9ab9ccee14e07a7a537cc1c97\",\n    \"actualDartProducerStatuses\": produced,\n    \"currentConsumerAcceptedActualProducerStatuses\": True,\n    \"unexecutedPlatformMatrixNegatives\": matrix_controls,\n    \"discovered\": discovered, \"testsRun\": result.testsRun,\n    \"successes\": result.success_ids,\n    \"skipped\": [(test.id(), reason) for test, reason in result.skipped],\n    \"failures\": [(test.id(), detail) for test, detail in result.failures],\n    \"errors\": [(test.id(), detail) for test, detail in result.errors],\n    \"newRegressionSubcases\": regressions,\n    \"allSubtests\": result.subtests,\n    \"nativeApplicationExecuted\": False,\n}\n(OUT / \"host-tests-summary.json\").write_text(json.dumps(summary, indent=2) + \"\\n\", encoding=\"utf-8\")\nprint(\"BEGIN_QA4428_STATUS_HOST_TESTS\")\nprint(json.dumps(summary, sort_keys=True))\nprint(\"END_QA4428_STATUS_HOST_TESTS\")\nassert discovered == result.testsRun == 47\nassert len(regressions) == 20 and all(row[\"passed\"] for row in regressions)\nassert len(matrix_controls) == 4\nassert result.wasSuccessful() and not result.skipped and len(result.success_ids) == 47\n"''')
B9_REPRO_SOURCE = json.loads(r'''"#!/usr/bin/env python3\n\"\"\"Read-only reproduction of the frozen b9 Android report-contract blocker.\"\"\"\nimport hashlib\nimport json\nfrom pathlib import Path\nimport sys\n\nsys.dont_write_bytecode = True\nROOT = Path.cwd().resolve()\nSOURCE = \"b9f7c186cb240ec45ba77e3160acc78402f4e172\"\nEXPECTED = {\n    \"integration_test/installed_plugin_resource_probe_test.dart\": \"c6de4983280a44f03215f79e781870dd30f2f7a528117188ce6f9eda3924bc8a\",\n    \"tool/perf_probe/run_installed_plugin_android.py\": \"53752be7c5261469156641554c958001630b1079f8ac2762507a206cfe5389e0\",\n    \"tool/perf_probe/test_installed_plugin_android.py\": \"e321c9130bd4bcea7491d02291dea34cd11f97aa2c3b58e7e1215e4b66759b6d\",\n}\nfor name, digest in EXPECTED.items():\n    if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest:\n        raise RuntimeError(\"Reproduction requires the exact reviewed b9 source: \" + name)\nsource = (ROOT / \"integration_test/installed_plugin_resource_probe_test.dart\").read_text(encoding=\"utf-8\")\nassert \"await desktopVisibility(first);\\n    await androidVisibility(first);\" in source\ndesktop_start = source.index(\"  Future<void> desktopVisibility(ToolTab tab)\")\ndesktop_end = source.index(\"  Future<void> androidVisibility(ToolTab tab)\", desktop_start)\ndesktop = source[desktop_start:desktop_end]\nunsupported_branch = \"\"\"if (!_desktop.contains(os)) {\n      for (final name in ['minimize', 'hide']) {\n        phaseRecord(name).addAll({\n          'status': 'unsupported',\"\"\"\nassert unsupported_branch in desktop\nassert \"const _desktop = {'windows', 'macos', 'linux'};\" in source\n\n# Only reviewed repository modules are imported. No artifact code is executed.\nsys.path.insert(0, str(ROOT))\nfrom tool.perf_probe.test_installed_plugin_android import ReportTests\n\ncase = ReportTests(methodName=\"test_complete_controlled_report_is_accepted\")\ncase.setUp()\nbaseline = case.validate()\nassert baseline[\"status\"] == \"passed\"\ndesktop_phases = [phase for phase in case.report[\"phases\"] if phase[\"name\"] in (\"minimize\", \"hide\")]\nassert len(desktop_phases) == 2 and all(phase[\"status\"] == \"notRun\" for phase in desktop_phases)\nfor phase in desktop_phases:\n    phase[\"status\"] = \"unsupported\"\ntry:\n    case.validate()\nexcept ValueError as error:\n    expected = \"Desktop visibility cannot be claimed by Android Home\"\n    assert str(error) == expected, str(error)\n    print(json.dumps({\n        \"schemaVersion\": 1,\n        \"classification\": \"BLOCKED_SOURCE_CONTRACT_MISMATCH\",\n        \"sourceCommit\": SOURCE,\n        \"baselineSyntheticNotRunAccepted\": True,\n        \"actualDartDesktopStatuses\": {phase[\"name\"]: phase[\"status\"] for phase in desktop_phases},\n        \"productionStatusesRejectedByOriginalConsumer\": True,\n        \"error\": str(error),\n        \"nativeApplicationExecuted\": False,\n        \"sourceModified\": False,\n        \"meaning\": \"Successful reproduction of a defect; not application acceptance.\"\n    }, sort_keys=True))\nelse:\n    raise AssertionError(\"The frozen b9 consumer unexpectedly accepted the producer statuses\")\n"''')

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
    raise RuntimeError("Candidate delta differs from the exact six-path public delta")
save("binding.json", {"sourceCommit": SOURCE, "sourceTree": SOURCE_TREE, "publicHead": PUBLIC,
                      "qaHead": QA_HEAD, "mode": sys.argv[1], "sourceFiles": source_bytes(),
                      "historicalLocalResultsUsed": False})
app_before = tracked_state(REPO)
save("app-before.json", app_before)
command(["git", "log", "--oneline", "-20", SOURCE], "source-history")
command(["git", "log", "--oneline", "-20", SOURCE, "--", *SOURCE_DELTA_PATHS], "changed-path-history")


if sys.argv[1] == "fast":
    B9 = "b9f7c186cb240ec45ba77e3160acc78402f4e172"
    B9_TREE = "4900c1eb5bbfc2f53b8d2b2273029ef9f5aba1f1"
    STATUS_PATHS = {
        "tool/perf_probe/INSTALLED_PLUGIN_ANDROID.md",
        "tool/perf_probe/run_installed_plugin_android.py",
        "tool/perf_probe/test_installed_plugin_android.py",
    }
    command(["git", "fetch", "--no-tags", "origin", B9], "fetch-frozen-b9", timeout=300)
    def byte_scope():
        if git("rev-parse", B9 + "^{tree}") != B9_TREE:
            raise RuntimeError("Prior source tree is not exact b9")
        def entries(revision):
            raw = subprocess.check_output(["git", "ls-tree", "-rz", "--full-tree", revision])
            rows = {}
            for item in raw.split(b"\0"):
                if not item:
                    continue
                metadata, name = item.split(b"\t", 1)
                mode, kind, digest = metadata.decode("ascii").split()
                rows[name.decode("utf-8")] = {"mode": mode, "type": kind, "sha": digest}
            return raw, rows
        old_raw, old_entries = entries(B9)
        new_raw, new_entries = entries(SOURCE)
        delta = sorted(name for name in old_entries.keys() | new_entries.keys()
                       if old_entries.get(name) != new_entries.get(name))
        if set(delta) != STATUS_PATHS or len(old_entries) != 4198 or len(new_entries) != 4198:
            raise RuntimeError("Candidate changed a source path outside the three-file status repair")
        dart = [name for name in new_entries if name.endswith(".dart")]
        if len(dart) != 3595 or any(old_entries[name] != new_entries[name] for name in dart):
            raise RuntimeError("Dart source changed; prior native-source gate reuse is invalid")
        def old_text(path):
            return subprocess.check_output(["git", "show", B9 + ":" + path]).decode("utf-8")
        runner_path = "tool/perf_probe/run_installed_plugin_android.py"
        before = old_text(runner_path)
        after = (REPO / runner_path).read_text(encoding="utf-8")
        old_predicate = 'require(all(by_name.get(name, {}).get("status") == "notRun" for name in ("minimize", "hide")),\n            "Desktop visibility cannot be claimed by Android Home")'
        new_predicate = 'require(all(by_name.get(name, {}).get("status") == "unsupported" for name in ("minimize", "hide")),\n            "Desktop visibility must be unsupported on Android")'
        if before.count(old_predicate) != 1 or before.replace(old_predicate, new_predicate) != after:
            raise RuntimeError("Host runner differs outside the exact two-line predicate/message repair")
        test_path = "tool/perf_probe/test_installed_plugin_android.py"
        old_tests = old_text(test_path)
        new_tests = (REPO / test_path).read_text(encoding="utf-8")
        old_ast, new_ast = ast.parse(old_tests), ast.parse(new_tests)
        old_names = [node.name for node in ast.walk(old_ast)
                     if isinstance(node, ast.FunctionDef) and node.name.startswith("test_")]
        new_nodes = [node for node in ast.walk(new_ast)
                     if isinstance(node, ast.FunctionDef) and node.name.startswith("test_")]
        if len(old_names) != 45 or len(new_nodes) != 47:
            raise RuntimeError("Original/current test counts differ from 45/47")
        repaired = new_tests
        new_names = {"test_desktop_visibility_requires_explicit_unsupported_status",
                     "test_missing_desktop_visibility_phase_or_status_is_rejected"}
        for name in new_names:
            matches = [node for node in new_nodes if node.name == name]
            if len(matches) != 1:
                raise RuntimeError("Missing focused status regression: " + name)
            segment = "    " + ast.get_source_segment(new_tests, matches[0])
            if repaired.count("\n" + segment + "\n") != 1:
                raise RuntimeError("Focused method source boundary is ambiguous: " + name)
            repaired = repaired.replace("\n" + segment + "\n", "", 1)
        repaired = repaired.replace('phases.extend({"name": name, "status": "unsupported"} for name in ("minimize", "hide"))',
                                    'phases.extend({"name": name, "status": "notRun"} for name in ("minimize", "hide"))', 1)
        if repaired != old_tests:
            raise RuntimeError("An original test body changed or an undeclared test edit exists")
        document = "tool/perf_probe/INSTALLED_PLUGIN_ANDROID.md"
        old_line = "| Windows, macOS, Linux and iOS | Remain **NOT_RUN** in this Android report. Desktop minimize/hide are also **NOT_RUN** here. |"
        new_line = "| Windows, macOS, Linux and iOS | Remain **NOT_RUN** in the platform matrix. Desktop minimize/hide phase records are `unsupported` because these window actions do not apply on Android. |"
        if old_text(document).replace(old_line, new_line) != (REPO / document).read_text(encoding="utf-8"):
            raise RuntimeError("Documentation changed outside the exact status clarification")
        result = {"source": SOURCE, "sourceTree": SOURCE_TREE, "priorSource": B9,
                  "priorTree": B9_TREE, "files": len(new_entries), "delta": delta,
                  "unchangedFiles": 4195, "unchangedDartFiles": len(dart),
                  "allOld45TestBodiesPreserved": True, "newMethods": sorted(new_names),
                  "oldTreeListingSha256": hashlib.sha256(old_raw).hexdigest(),
                  "newTreeListingSha256": hashlib.sha256(new_raw).hexdigest(),
                  "unchangedGateScope": ["Dart formatter", "original staged Dart hook", "full Flutter analyze",
                                         "14 Android Dart tests", "44 other Dart tests",
                                         "10 Node fixture/Store tests", "all 19 Git dependency pins", "SDK pin"],
                  "currentPythonTestsMustRunAgain": True, "nativeAcceptance": "NOT_RUN"}
        save("full-source-reuse-scope.json", result)
        return result
    case("Full tree scope and exact preservation of all old test bodies", byte_scope)

    def original_failure():
        parent = Path(tempfile.mkdtemp(prefix="qa-4428-frozen-b9-", dir=os.environ["RUNNER_TEMP"]))
        worktree = parent / "source"
        command(["git", "worktree", "add", "--detach", str(worktree), B9], "old-source-worktree", timeout=180)
        before = tracked_state(worktree)
        if before["head"] != B9 or before["tree"] != B9_TREE or before["status"]:
            raise RuntimeError("Original regression worktree is not the exact clean b9 source")
        script = OUT / "frozen-b9-status-reproducer.py"
        data = B9_REPRO_SOURCE.encode("utf-8")
        if hashlib.sha256(data).hexdigest() != "4249107550b65b6bd6452ce025ca9766cdc16e8468ec430617a977c41f01350f":
            raise RuntimeError("Original frozen regression script changed")
        script.write_bytes(data)
        _, raw = command([sys.executable, str(script)], "original-b9-status-reproduction",
                         cwd=worktree, timeout=120)
        record = json.loads(raw)
        if not record.get("productionStatusesRejectedByOriginalConsumer") or record.get("nativeApplicationExecuted") is not False:
            raise RuntimeError("Original consumer mismatch was not reproduced")
        after = tracked_state(worktree)
        if before != after:
            raise RuntimeError("Original reproduction mutated the b9 source/index")
        save("old-source-before-after.json", {"before": before, "after": after, "unchanged": True})
        save("old-source-status-reproduction.json", record)
        command(["git", "worktree", "remove", str(worktree)], "remove-owned-b9-worktree", timeout=180)
        return record
    case("Actual reproduction of frozen b9 consumer rejecting real producer statuses", original_failure)

    def current_controls():
        script = OUT / "run-current-host-controls.py"
        script.write_text(HOST_SUITE_SOURCE, encoding="utf-8")
        command([sys.executable, str(script), str(REPO), str(OUT)], "actual-host-tests", timeout=600)
        result = json.loads((OUT / "host-tests-summary.json").read_text(encoding="utf-8"))
        if result.get("testsRun") != 47 or result.get("failures") or result.get("errors") or result.get("skipped"):
            raise RuntimeError("Current host suite did not execute all 47 tests without failures or skips")
        return result
    case("Actual producer statuses, four platform-matrix negatives and all 47 host tests", current_controls)

    def reused_gate_binding():
        prior_run = api("/repos/Otzaria/otzaria/actions/runs/42337261971")
        prior_job = api("/repos/Otzaria/otzaria/actions/jobs/128296881826")
        if prior_run["head_sha"] != "4f3cb2fbcf1540cba1e41691fc6c05016ca649de" or prior_run["conclusion"] != "success":
            raise RuntimeError("Prior source gate run binding changed")
        if prior_job["run_id"] != 42337261971 or prior_job["conclusion"] != "success" or prior_job["status"] != "completed":
            raise RuntimeError("Prior source gate job is not the completed passing original")
        result = {"priorSource": B9, "priorTree": B9_TREE,
                  "runId": 42337261971, "jobId": 128296881826, "runHead": prior_run["head_sha"],
                  "fullJobLogBytes": 163183,
                  "fullJobLogSha256": "132f4087f7384b34e47c07e5450c23af96083a96cb8e10d7bbd070f0f139c13a",
                  "sourceArtifactId": 13559803524,
                  "sourceArtifactSha256": "46b66533ee6bfba3ef40d553f7e826799285f9587757d405b5ac61d692c7c336",
                  "reuseOnlyAfterCompleteTreeScopeProof": True,
                  "newSourceDartOrFlutterExecutionInThisJob": False,
                  "newPythonExecutionRequired": True, "nativeAcceptance": "NOT_RUN_BY_THIS_JOB"}
        save("prior-source-run.json", prior_run)
        save("prior-source-job.json", prior_job)
        save("prior-source-gate-binding.json", result)
        return result
    case("Bind reused exact unchanged Dart and SDK source gates to actual prior CI", reused_gate_binding)
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
