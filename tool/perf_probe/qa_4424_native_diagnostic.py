#!/usr/bin/env python3
"""Read-only, exact-artifact diagnosis for the installed Windows probe."""
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess
import urllib.parse
import urllib.request
import zipfile

SOURCE = "f4ac011f1b8c81d4a760eeeadfe037228fb944e3"
SOURCE_TREE = "1767f0161e11567f3d4d0eb703d1bdeb1950272b"
NATIVE_HEAD = "f4893ce470cb6f7dbdb432c2c5b98d89b10dd03f"
RUN = 42329492076
ARTIFACT = 13556734016
EXPECTED_BYTES = 13268
EXPECTED_SHA256 = "c75706d7d3dd56d55e1466d68e18a4ffcca49f194433c24adccbe6a7d76e6a8a"
QA_FILES = {"tool/perf_probe/qa_4424_native_diagnostic.py",
            ".github/workflows/qa_4424_native_diagnostic.yml"}
TOKEN = os.environ.pop("QA_GITHUB_TOKEN", "")
os.environ.pop("GITHUB_TOKEN", None)
os.environ.pop("GH_TOKEN", None)
ROOT = Path.cwd().resolve()
OUT = Path(os.environ["QA_EVIDENCE_DIR"]).resolve()
OUT.mkdir(parents=True, exist_ok=False)

def sha256(data):
    return hashlib.sha256(data).hexdigest()

def git(*args):
    result = subprocess.run(["git", *args], cwd=ROOT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError("Git binding command failed: " + repr(args))
    return result.stdout.strip()

def save(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        target = urllib.parse.urlparse(newurl)
        if target.scheme != "https":
            raise RuntimeError("Artifact redirect must use HTTPS")
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if redirected is not None:
            for name in list(redirected.headers):
                if name.lower() == "authorization":
                    redirected.remove_header(name)
            for name in list(redirected.unredirected_hdrs):
                if name.lower() == "authorization":
                    redirected.remove_header(name)
        return redirected

def read_api(path, max_bytes):
    if not path.startswith("/repos/Otzaria/otzaria/actions/artifacts/"):
        raise RuntimeError("Unexpected artifact API path")
    headers = {"Accept": "application/vnd.github+json",
               "X-GitHub-Api-Version": "2022-11-28",
               "User-Agent": "Otzaria-read-only-4424-QA"}
    if TOKEN:
        headers["Authorization"] = "Bearer " + TOKEN
    request = urllib.request.Request("https://api.github.com" + path, headers=headers)
    opener = urllib.request.build_opener(SafeRedirect)
    data = bytearray()
    with opener.open(request, timeout=60) as response:
        while True:
            chunk = response.read(65536)
            if not chunk:
                break
            data.extend(chunk)
            if len(data) > max_bytes:
                raise RuntimeError("Bounded artifact response exceeded its byte limit")
    return bytes(data)

def file_snapshot(directory):
    files = []
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise RuntimeError("Unexpected extracted symlink")
        if path.is_file():
            data = path.read_bytes()
            files.append({"path": path.relative_to(directory).as_posix(),
                          "bytes": len(data), "sha256": sha256(data)})
    return files

qa_head = git("rev-parse", "HEAD")
if git("rev-parse", "HEAD^") != SOURCE or git("rev-parse", SOURCE + "^{tree}") != SOURCE_TREE:
    raise RuntimeError("QA is not a direct child of the frozen source")
if set(git("diff", "--name-only", SOURCE, qa_head).splitlines()) != QA_FILES:
    raise RuntimeError("QA commit contains undeclared files")
if git("status", "--porcelain=v1"):
    raise RuntimeError("QA checkout is initially modified")
binding = {"source": SOURCE, "sourceTree": SOURCE_TREE, "qaHead": qa_head,
           "nativeHead": NATIVE_HEAD, "runId": RUN, "artifactId": ARTIFACT}
save("binding.json", binding)

metadata = json.loads(read_api("/repos/Otzaria/otzaria/actions/artifacts/" + str(ARTIFACT), 65536))
save("artifact-metadata.json", metadata)
if (metadata.get("id") != ARTIFACT or metadata.get("size_in_bytes") != EXPECTED_BYTES or
        metadata.get("digest") != "sha256:" + EXPECTED_SHA256 or metadata.get("expired") is not False or
        metadata.get("workflow_run", {}).get("id") != RUN or
        metadata.get("workflow_run", {}).get("head_sha") != NATIVE_HEAD):
    raise RuntimeError("Artifact metadata does not match the frozen native run")
raw_zip = read_api("/repos/Otzaria/otzaria/actions/artifacts/" + str(ARTIFACT) + "/zip", EXPECTED_BYTES + 1)
if len(raw_zip) != EXPECTED_BYTES or sha256(raw_zip) != EXPECTED_SHA256:
    raise RuntimeError("Downloaded artifact bytes or SHA256 differ")
(OUT / "original-native-artifact.zip").write_bytes(raw_zip)
extracted = OUT / "native-artifact"
extracted.mkdir()
names = set()
total_bytes = 0
with zipfile.ZipFile(io.BytesIO(raw_zip)) as archive:
    entries = archive.infolist()
    if len(entries) > 128:
        raise RuntimeError("Artifact contains too many entries")
    for entry in entries:
        name = entry.filename
        path = PurePosixPath(name)
        if (not name or name.startswith("/") or "\\" in name or ":" in name or
                ".." in path.parts or name in names or stat.S_ISLNK(entry.external_attr >> 16)):
            raise RuntimeError("Unsafe or duplicate ZIP entry")
        names.add(name)
        target = extracted.joinpath(*path.parts)
        if not target.resolve().is_relative_to(extracted):
            raise RuntimeError("ZIP target escaped its fresh root")
        if entry.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        total_bytes += entry.file_size
        if entry.file_size > 16 * 1024 * 1024 or total_bytes > 64 * 1024 * 1024:
            raise RuntimeError("Artifact exceeds its extraction limit")
        data = archive.read(entry)
        if len(data) != entry.file_size:
            raise RuntimeError("ZIP entry size is inconsistent")
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as stream:
            stream.write(data)

before = file_snapshot(extracted)
save("extracted-manifest-before.json", before)
selected_names = {"windows-native-exit.json", "windows-native-exit-start.json",
                  "windows-device-report.json", "native-exit-control.json",
                  "run.log", "fixture-errors.txt", "source-commit.txt",
                  "flutter.json", "source-provenance.json"}
selected = []
for item in before:
    path = extracted / item["path"]
    if path.name not in selected_names:
        continue
    data = path.read_bytes()
    row = dict(item)
    if len(data) <= 512 * 1024:
        row["completeText"] = data.decode("utf-8-sig", "strict")
        if path.suffix == ".json":
            row["json"] = json.loads(row["completeText"])
    else:
        row["textTruncated"] = True
        row["prefix"] = data[:32768].decode("utf-8", "replace")
        row["suffix"] = data[-32768:].decode("utf-8", "replace")
    selected.append(row)
receipts = [item for item in selected if PurePosixPath(item["path"]).name == "windows-native-exit.json"]
if len(receipts) > 1:
    raise RuntimeError("Ambiguous native exit receipts")
receipt = receipts[0].get("json", {}) if receipts else {}
if receipt and receipt.get("commit") != NATIVE_HEAD:
    raise RuntimeError("Native receipt commit does not match the retained run")
receipt_availability = "collected" if receipt else "notProducedOrNotComplete"
after = file_snapshot(extracted)
save("extracted-manifest-after.json", after)
if before != after or git("status", "--porcelain=v1"):
    raise RuntimeError("Read-only diagnosis changed artifact or app source")
summary = {**binding, "diagnosticStatus": "COMPLETED", "nativeAcceptance": "FAILED",
           "artifactZip": {"bytes": len(raw_zip), "sha256": sha256(raw_zip)},
           "fileCount": len(before), "extractedBytes": sum(item["bytes"] for item in before),
           "artifactBytesUnchanged": True, "applicationSourceUnchanged": True,
           "allFiles": before, "selectedFiles": selected,
           "receiptAvailability": receipt_availability, "firstError": receipt.get("firstError"),
           "driverExitCode": receipt.get("driverExitCode"),
           "driverError": receipt.get("driverError"),
           "diagnosticErrors": receipt.get("diagnosticErrors"),
           "observer": receipt.get("observer"),
           "stepExitCode": receipt.get("stepExitCode"),
           "artifactCodeExecuted": False}
save("diagnostic-summary.json", summary)
print("BEGIN_QA4424_NATIVE_DIAGNOSTIC", flush=True)
print(json.dumps(summary, ensure_ascii=False), flush=True)
print("END_QA4424_NATIVE_DIAGNOSTIC", flush=True)
