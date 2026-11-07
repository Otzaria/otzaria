"""Temporary read-only transport of pinned H1 evidence; never decides H1 acceptance."""
import argparse
import base64
import hashlib
import io
import json
import os
import re
import stat
import struct
import sys
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
import warnings
import zipfile
import zlib

REPO = "Otzaria/otzaria"
API = "https://api.github.com/repos/" + REPO
RUN = 42320691502
ATTEMPT = 1
HEAD = "c624f8ec9b8f7c8190e2433ccedbcbbeadf13caa"
PRODUCT = "8e02f5a89a509a983f46d8d35b624a22dc844a64"
CRATE = "7a06d2e9d03615c0f9964b73eae03da8"
WORKFLOW = ".github/workflows/report-winv-windows11-qa.yml"
WORKFLOW_ID = 409350766
PINS = {
    "server": (13553254927, 21649995,
               "588ae44aa51ac0a66706dd3fa3aafde7d795059666f409b1300bdfcb4b59a7b3"),
    "trace-on": (13553229864, 11997664,
                 "9d16fb9fe8aa0ea4f3ed1cc6e6fe7b930747ee0e4cd7ab243fc1c839524f5517"),
    "trace-off": (13553799776, 15400499,
                  "55cb8ebbb2fda1ee92c75785b7ba761721fb09f8f8b7d861e26f84a640ae0eb8"),
}
NAMES = {
    "server": f"windows-flutter-history-{RUN}-attempt-{ATTEMPT}",
    "trace-on": f"windows11-flutter-history-trace-true-{RUN}-attempt-{ATTEMPT}",
    "trace-off": f"windows11-flutter-history-trace-false-{RUN}-attempt-{ATTEMPT}",
}
MIB = 1024 * 1024
MAX_ZIP, MAX_TOTAL, MAX_MEMBER = 96 * MIB, 256 * MIB, 64 * MIB
MAX_JSON, MAX_PNG, MAX_ENTRIES = 2 * MIB, 2 * MIB, 2048
CASES = ("plain-v-focused", "alt-v-focused", "posted-v-focused", "text-focused",
         "text-unfocused", "image-focused", "image-unfocused")
SERVER_JSON = ("runner.json", "source-provenance.json", "native-clipboard-build.json",
               "server-prerequisite.json", "server-flutter-exit.json", "flutter-summary.json",
               "standalone-no-trace/flutter-summary.json",
               "standalone-no-trace/server-prerequisite.json", "widget-candidate.json",
               "clipboard-helper-smoke/smoke-result.json")
WIN_JSON = ("host.json", "qa-bundle.json", "native-clipboard-build.json",
            "server-prerequisite.json", "helper-overrides.json", "windows11-harness-source.json",
            "run/flutter-summary.json", "caret-delivery.json", "observer-disabled.json",
            "loaded-clipboard-library.json", "launcher-exit.json", "flutter-process.json",
            "activation.json", "privacy-preparation.json")
SCALARS = frozenset((
    "sourceHead", "qaHead", "productHead", "workflowHead", "bundleHead", "sourceQaHead",
    "sourceRun", "crateHash", "crateFileCount", "productPreserved", "sha256",
    "builtFromSource", "caption", "version", "buildNumber", "productType", "osArchitecture",
    "controllerArchitecture", "userInteractive", "nativeTraceRequested", "nativeTraceEnabled",
    "allTestsPassed", "allPassed", "exitCode", "expectedHistoryFailures", "historyTestsPassed",
    "reportCasesPassed", "historyCasesUnsupported", "historyCasesPassed", "rawAllTestsPassed",
    "summarySha256", "helperValidated", "failureExitCodeValidated", "historyTested",
    "nativeHelperSha256", "completionInputSimulated", "clipboardDllSha256", "executableSha256",
    "processMachine", "nativeMachine", "wowMachine", "inputSent", "completed", "success",
    "case", "negativeControl", "textFieldFocus", "reportAssertionsPassed",
    "historySelectionVerified", "controllerExitCode", "controllerTimedOut", "passed",
    "observationDisabled", "flutterTestEnvironmentAbsent", "formatSampleCount",
    "probeCompleted", "outcome", "historyWindowIdentified", "historyOpeningAttempts",
    "nativeControlInputSent", "renderer", "os", "osVersion", "imageOS", "imageVersion",
))
HISTORY_CASES = ("text-focused", "text-unfocused", "image-focused", "image-unfocused")
WIN_JSON += tuple(f"run/{case}/{name}.json" for case in CASES
                  for name in ("environment", "runtime-modules"))
SCALARS |= frozenset((
    "flutterWindow", "payload", "vKeyDownDelivered", "unmappedVObserved",
    "clipboardBeforeSelection", "clipboardAfterSelection", "enableButtonInvoked",
    "controlForegroundBeforeInput", "controlForegroundAfterInput", "controlForegroundAtCompletion",
    "foreground", "foregroundBefore", "foregroundAfter", "focused", "imageCount", "state",
    "nativeControl", "nativeAlt", "nativeWin", "nativeV", "type", "physical", "logical",
    "logicalName", "character", "synthesized", "controlPressed", "stage", "key",
    "virtualKey", "scanCode", "extended", "flags", "name",
    "clipboardFormatObservationEnabled", "flutterTestEnvironmentPresent", "architecture",
))
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class AuditError(Exception):
    pass


def require(condition, code):
    if not condition:
        raise AuditError(code)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def strict_json(data):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "duplicate_json_key")
            result[key] = value
        return result

    def bad_constant(_):
        raise AuditError("invalid_json_constant")
    return json.loads(data.decode("utf-8-sig"), object_pairs_hook=pairs, parse_constant=bad_constant)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def storage_url(url):
    p = urllib.parse.urlsplit(url)
    require(p.scheme == "https" and not p.username and not p.password
            and p.port in (None, 443) and not p.fragment, "unsafe_redirect")
    host = (p.hostname or "").lower()
    require(host.endswith(".blob.core.windows.net")
            or host.endswith(".githubusercontent.com"), "unapproved_storage_host")
    return url


def request_bytes(url, token, limit):
    p = urllib.parse.urlsplit(url)
    if token is not None:
        require(p.scheme == "https" and p.netloc == "api.github.com"
                and p.path.startswith("/repos/" + REPO + "/"), "unsafe_authenticated_url")
    else:
        storage_url(url)
    headers = {"User-Agent": "Otzaria-pinned-H1-evidence-audit"}
    if token is not None:
        headers.update({"Authorization": "Bearer " + token,
                        "Accept": "application/vnd.github+json",
                        "X-GitHub-Api-Version": "2022-11-28"})
    request = urllib.request.Request(url, headers=headers)
    opener = urllib.request.build_opener(NoRedirect())
    try:
        response = opener.open(request, timeout=30)
    except urllib.error.HTTPError as error:
        code, location = error.code, error.headers.get("Location")
        error.close()
        if code in (301, 302, 303, 307, 308) and location:
            return code, location, b""
        raise AuditError("github_or_storage_http_error") from None
    except urllib.error.URLError:
        raise AuditError("network_unavailable") from None
    with response:
        require(response.status == 200, "unexpected_http_status")
        length = response.headers.get("Content-Length")
        if length is not None:
            require(length.isdecimal() and int(length) <= limit, "http_body_limit")
        chunks, size, deadline = [], 0, time.monotonic() + 90
        while True:
            block = response.read(min(65536, limit + 1 - size))
            if not block:
                break
            chunks.append(block)
            size += len(block)
            require(size <= limit and time.monotonic() <= deadline, "download_limit")
        return 200, None, b"".join(chunks)


def api_json(path, token):
    status, _, data = request_bytes(API + path, token, 2 * MIB)
    require(status == 200, "api_redirect_rejected")
    return strict_json(data)


def validate_run(run):
    require(run.get("id") == RUN and run.get("run_attempt") == ATTEMPT
            and run.get("head_sha") == HEAD and run.get("workflow_id") == WORKFLOW_ID
            and run.get("path") == WORKFLOW and run.get("event") == "pull_request"
            and run.get("repository", {}).get("full_name") == REPO
            and run.get("head_repository", {}).get("full_name") == REPO, "run_identity_mismatch")


def select_artifact(listing, role, run):
    artifacts = listing.get("artifacts")
    require(isinstance(artifacts, list) and listing.get("total_count") == len(artifacts)
            and len(artifacts) <= 20, "incomplete_artifact_listing")
    matches = [a for a in artifacts if a.get("name") == NAMES[role]]
    require(len(matches) == 1, "artifact_missing_or_ambiguous")
    a = matches[0]
    source = a.get("workflow_run", {})
    require(source.get("id") == RUN and source.get("head_sha") == HEAD
            and source.get("repository_id") == run["repository"]["id"]
            and source.get("head_repository_id") == run["head_repository"]["id"],
            "artifact_run_identity_mismatch")
    require(a.get("expired") is False and type(a.get("id")) is int
            and type(a.get("size_in_bytes")) is int
            and 0 < a["size_in_bytes"] <= MAX_ZIP, "artifact_size_or_expiration")
    require(re.fullmatch(r"sha256:[0-9a-f]{64}", a.get("digest", "")) is not None,
            "artifact_digest_missing")
    require(a.get("archive_download_url") == f"{API}/actions/artifacts/{a['id']}/zip",
            "artifact_download_url_mismatch")
    expected_id, expected_size, expected_digest = PINS[role]
    require(a["id"] == expected_id and a["size_in_bytes"] == expected_size
            and a["digest"] == "sha256:" + expected_digest, "artifact_not_pinned")
    return a


def download(a, token):
    url, auth = a["archive_download_url"], token
    for _ in range(4):
        status, location, data = request_bytes(url, auth, MAX_ZIP)
        if status == 200:
            require(len(data) == a["size_in_bytes"] and "sha256:" + sha(data) == a["digest"],
                    "artifact_size_or_digest_mismatch")
            return data
        require(location is not None, "missing_artifact_redirect")
        url, auth = storage_url(location), None
    raise AuditError("too_many_redirects")


def safe_member(info):
    name = info.filename
    require(info.orig_filename == name, "zip_filename_was_normalized")
    require(name and len(name) <= 512 and "\\" not in name and ":" not in name
            and not name.startswith("/") and all(ord(c) >= 32 and ord(c) != 127 for c in name),
            "unsafe_zip_path")
    parts = name[:-1].split("/") if info.is_dir() else name.split("/")
    require(all(p and p not in (".", "..") and not p.endswith((" ", ".")) for p in parts),
            "unsafe_zip_component")
    mode = stat.S_IFMT(info.external_attr >> 16)
    require(mode in (0, stat.S_IFREG, stat.S_IFDIR) and not (info.flag_bits & 1),
            "zip_link_special_or_encrypted")
    require(info.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED),
            "unsupported_zip_compression")
    require(0 <= info.file_size <= MAX_MEMBER and 0 <= info.compress_size <= MAX_ZIP,
            "zip_member_limit")
    require(info.file_size <= max(1, info.compress_size) * 200 + 16384, "zip_ratio_limit")
    return name.rstrip("/").casefold()


def open_zip(data):
    require(len(data) <= MAX_ZIP, "zip_limit")
    end = data.rfind(b"PK\x05\x06", max(0, len(data) - 65557))
    require(end >= 0 and end + 22 <= len(data), "zip_eocd_missing")
    _, disk, start_disk, disk_count, count, central_size, offset, comment = struct.unpack_from(
        "<4s4H2LH", data, end)
    require(disk == start_disk == 0 and disk_count == count and 0 < count <= MAX_ENTRIES
            and central_size <= 4 * MIB and offset + central_size == end
            and end + 22 + comment == len(data), "zip_central_directory_limit")
    archive = zipfile.ZipFile(io.BytesIO(data))
    infos = archive.infolist()
    require(len(infos) == count, "zip_entry_count_mismatch")
    seen, total = set(), 0
    for info in infos:
        key = safe_member(info)
        require(key not in seen, "duplicate_zip_path")
        seen.add(key)
        require(0 <= info.header_offset < offset, "zip_header_out_of_bounds")
        total += info.file_size
        require(total <= MAX_TOTAL, "zip_total_limit")
    return archive


def member_bytes(archive, path, limit):
    info = archive.getinfo(path)
    require(not info.is_dir() and info.file_size <= limit, "selected_member_limit")
    with archive.open(info) as entry:
        data = entry.read(limit + 1)
        require(len(data) == info.file_size and len(data) <= limit and not entry.read(1),
                "selected_member_length")
    return data


def identities(records, role):
    if role == "server":
        runner = records.get("runner.json")
        require(isinstance(runner, dict) and runner.get("sourceHead") == PRODUCT
                and runner.get("qaHead") == HEAD, "server_source_identity")
        source = records.get("source-provenance.json")
        require(isinstance(source, dict) and source.get("sourceHead") == PRODUCT
                and source.get("qaHead") == HEAD and source.get("crateHash") == CRATE
                and source.get("productPreserved") is True, "server_source_provenance")
    else:
        host = records.get("host.json")
        require(isinstance(host, dict) and host.get("sourceQaHead") == HEAD
                and host.get("productHead") == PRODUCT and str(host.get("sourceRun")) == str(RUN)
                and host.get("nativeTraceRequested") == ("true" if role == "trace-on" else "false"),
                "windows_source_identity")
    native = records.get("native-clipboard-build.json")
    if native is not None:
        require(isinstance(native, dict) and native.get("sourceHead") == PRODUCT
                and native.get("qaHead") == HEAD and native.get("crateHash") == CRATE
                and native.get("builtFromSource") is True
                and re.fullmatch(r"[0-9a-fA-F]{64}", native.get("sha256", "")) is not None,
                "native_build_identity")
    require(role != "server" or native is not None, "missing_server_native_identity")
    for path, record in records.items():
        if path.endswith("flutter-summary.json"):
            trace = (path == "flutter-summary.json") if role == "server" else role == "trace-on"
            require(record.get("sourceHead") == PRODUCT and record.get("qaHead") == HEAD
                    and record.get("nativeTraceEnabled") is trace, "flutter_summary_identity")
    return native is not None


def scalar_projection(record):
    output = {}
    for key in sorted(SCALARS & record.keys()):
        value = record[key]
        if value is None or type(value) in (bool, int):
            output[key] = value
        elif isinstance(value, str) and len(value) <= 256 and re.fullmatch(r"[A-Za-z0-9 _.:()/+\-]*", value):
            output[key] = value
        else:
            output[key + "Sha256"] = sha(json.dumps(value, ensure_ascii=True).encode())
    return output


def fixed_events(rows):
    require(isinstance(rows, list) and len(rows) <= 256
            and all(isinstance(row, dict) for row in rows), "event_list_limit")
    result = []
    for row in rows:
        item = scalar_projection(row)
        if isinstance(row.get("key"), dict):
            item["key"] = scalar_projection(row["key"])
        result.append(item)
    return result


def project_row(row):
    output = scalar_projection(row)
    for source in ("before", "after", "inputBeforeCleanup"):
        record = row.get(source)
        if not isinstance(record, dict):
            continue
        item = scalar_projection(record)
        if "title" in record:
            title = record["title"]
            require(isinstance(title, str) and len(title) <= 4096, "title_limit")
            start = "Title preserved: \u05de\u05e7\u05d5\u05e8 "
            expected = {start, start + "v", start + "V"} | {
                start + "OTZARIA-HISTORY-QA-A-" + case for case in CASES}
            item["titleSha256"] = sha(title.encode("utf-8"))
            item["titleCharacters"] = len(title)
            item["titleIsKnownFixture"] = title in expected
            if title in expected:
                item["title"] = title
        for key in ("imageBytes", "flutterKeys"):
            if key in record:
                values = record[key]
                require(isinstance(values, list) and len(values) <= 32, "state_list_limit")
                require(all(type(value) is int and 0 <= value <= MAX_MEMBER
                            if key == "imageBytes" else
                            isinstance(value, str) and re.fullmatch(r"0x[0-9a-f]+", value)
                            for value in values), "state_list_value")
                item[key] = values
        output[source] = item
    controller = row.get("controller")
    if isinstance(controller, dict):
        output["controller"] = scalar_projection(controller)
        output["controller"]["errorPresent"] = controller.get("error") is not None
        for key in ("caretPreparations", "clipboardFormatSamples"):
            if key in controller:
                output["controller"][key] = fixed_events(controller[key])
    for key in ("nativeRequests", "actualFlutterEndEvents", "keyEvents"):
        if key in row:
            output[key] = fixed_events(row[key])
            output[key + "Count"] = len(row[key])
    library = row.get("library")
    if isinstance(library, dict):
        output["library"] = scalar_projection(library)
    return output


def project(path, record):
    output = scalar_projection(record)
    for key in ("nativeClipboard", "expected"):
        if isinstance(record.get(key), dict):
            output[key] = scalar_projection(record[key])
    if "error" in record:
        output["errorPresent"] = record["error"] is not None
    if "cases" in record:
        rows = record["cases"]
        require(isinstance(rows, list) and len(rows) <= 7, "case_count_invalid")
        names, projected = [], []
        for row in rows:
            require(isinstance(row, dict) and row.get("case") in CASES, "case_name_invalid")
            names.append(row["case"])
            projected.append(project_row(row))
        output.update(cases=projected, distinctCaseCount=len(set(names)),
                      missingExpectedCases=[name for name in CASES if name not in names])
    for key in ("failedTests", "failureDetails", "reportedFailureDetails"):
        if key in record:
            rows = record[key]
            require(isinstance(rows, list) and len(rows) <= 64, "failure_list_limit")
            output[key + "Count"] = len(rows)
            output[key + "Sha256"] = sha(json.dumps(rows, sort_keys=True).encode())
            methods = [row.get("methodName") if isinstance(row, dict) else row for row in rows]
            output[key + "Methods"] = [
                value if value in {"real Windows history selection in report: " + case for case in CASES}
                else "unrecognized-test-name" for value in methods]
    return output

def choose_png(names, slot, requested_case=None):
    candidates = (requested_case,) if requested_case else HISTORY_CASES
    for case in candidates:
        before = (f"run/{case}/04-history-A-after-B-0.png", f"run/{case}/01-flutter-report-focused.png")
        after = (f"run/{case}/05-after-real-history-selection.png", f"run/{case}/98-error.png",
                 f"run/{case}/02-negative-control-result.png")
        left, right = next((p for p in before if p in names), None), next((p for p in after if p in names), None)
        if left and right:
            return (left if slot == "before" else right), case
    for path in ("privacy-error.png", "99-wrapper-error.png", "00-before-launch.png"):
        if path in names:
            return path, "preparation-diagnostic"
    return None, None


def png_dimensions(data):
    require(data.startswith(PNG_SIGNATURE), "png_signature")
    pos, count, width, height, saw_idat = 8, 0, None, None, False
    while pos < len(data):
        require(pos + 12 <= len(data), "png_chunk_truncated")
        size = struct.unpack_from(">I", data, pos)[0]
        kind = data[pos + 4:pos + 8]
        require(pos + 12 + size <= len(data) and count < 1000, "png_chunk_limit")
        payload = data[pos + 8:pos + 8 + size]
        crc = struct.unpack_from(">I", data, pos + 8 + size)[0]
        require(zlib.crc32(kind + payload) & 0xffffffff == crc, "png_crc")
        if count == 0:
            require(kind == b"IHDR" and size == 13, "png_ihdr")
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">II5B", payload)
            require(0 < width <= 8192 and 0 < height <= 8192 and width * height <= 16_777_216
                    and depth in {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8),
                                  4: (8, 16), 6: (8, 16)}.get(color, ())
                    and compression == filtering == 0 and interlace in (0, 1), "png_dimensions")
        elif kind == b"IHDR":
            raise AuditError("duplicate_png_ihdr")
        saw_idat |= kind == b"IDAT"
        pos += 12 + size
        count += 1
        if kind == b"IEND":
            require(size == 0 and pos == len(data) and saw_idat, "png_iend")
            return width, height
    raise AuditError("png_iend_missing")


def emit(record):
    text = json.dumps(record, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    require(len(text.encode()) <= 128 * 1024, "summary_output_limit")
    token = os.environ.get("GITHUB_TOKEN", "")
    require(not token or token not in text, "credential_in_output")
    print("AUDIT_JSON " + text, flush=True)


def audit(role, slot, requested_case):
    token = os.environ.get("GITHUB_TOKEN")
    require(bool(token), "missing_read_only_token")
    run = api_json(f"/actions/runs/{RUN}", token)
    validate_run(run)
    listing = api_json(f"/actions/runs/{RUN}/artifacts?per_page=100&page=1", token)
    artifact = select_artifact(listing, role, run)
    data = download(artifact, token)
    with open_zip(data) as archive:
        names = set(archive.namelist())
        allowed = SERVER_JSON if role == "server" else WIN_JSON
        records, projected = {}, {}
        for path in allowed:
            if path in names:
                raw = member_bytes(archive, path, MAX_JSON)
                record = strict_json(raw)
                require(isinstance(record, dict), "json_record_not_object")
                records[path] = record
                projected[path] = {"sha256": sha(raw), "bytes": len(raw), "fields": project(path, record)}
        native_verified = identities(records, role)
        envelope = {"diagnosticOnly": True, "h1Acceptance": "not-evaluated",
                    "sourceRun": RUN, "sourceAttempt": ATTEMPT, "sourceHead": HEAD, "productHead": PRODUCT,
                    "runStatus": run.get("status"), "runConclusion": run.get("conclusion"),
                    "role": role, "requestedCase": requested_case, "artifactId": artifact["id"], "artifactName": NAMES[role],
                    "artifactSha256": sha(data), "artifactBytes": len(data),
                    "nativeBuildIdentityVerified": native_verified}
        if slot == "summary":
            emit({**envelope, "records": projected, "missingAllowedJson": [p for p in allowed if p not in names]})
            return
        require(role != "server", "server_images_not_requested")
        path, pair_case = choose_png(names, slot, requested_case)
        if path is None or not native_verified:
            emit({**envelope, "slot": slot, "pngAvailable": False,
                  "reason": "missing_verified_native_build" if not native_verified else "no_allowlisted_png"})
            return
        png = member_bytes(archive, path, MAX_PNG)
        width, height = png_dimensions(png)
        encoded = base64.b64encode(png).decode("ascii")
        parts = [encoded[i:i + 16384] for i in range(0, len(encoded), 16384)]
        emit({**envelope, "slot": slot, "pngAvailable": True, "path": path, "pairCase": pair_case,
              "pngSha256": sha(png), "pngBytes": len(png), "width": width, "height": height,
              "base64Parts": len(parts), "pixelsEdited": False})
        for index, part in enumerate(parts):
            print(f"AUDIT_PNG_BASE64 {index + 1}/{len(parts)} {part}", flush=True)
        print("AUDIT_PNG_END " + sha(png), flush=True)


class SelfChecks(unittest.TestCase):
    def archive(self, entries):
        output = io.BytesIO()
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as z:
                for name, value in entries:
                    z.writestr(name, value)
        return output.getvalue()

    def run_record(self):
        return {"id": RUN, "run_attempt": ATTEMPT, "head_sha": HEAD, "workflow_id": WORKFLOW_ID,
                "path": WORKFLOW, "event": "pull_request", "repository": {"id": 1, "full_name": REPO},
                "head_repository": {"id": 1, "full_name": REPO}, "conclusion": "failure"}

    def artifact(self, data):
        return {"id": 7, "name": NAMES["trace-on"], "expired": False, "size_in_bytes": len(data),
                "digest": "sha256:" + sha(data), "archive_download_url": API + "/actions/artifacts/7/zip",
                "workflow_run": {"id": RUN, "head_sha": HEAD, "repository_id": 1, "head_repository_id": 1}}

    def test_run_identity_and_failed_run_remain_diagnostic(self):
        r = self.run_record()
        validate_run(r)
        for key, value in (("id", 1), ("run_attempt", 2), ("head_sha", PRODUCT), ("path", "other.yml")):
            with self.subTest(key=key), self.assertRaises(AuditError):
                validate_run({**r, key: value})

    def test_artifact_selection_is_exact_and_unique(self):
        a = self.artifact(b"zip")
        pinned_id, pinned_size, pinned_digest = PINS["trace-on"]
        a.update(id=pinned_id, size_in_bytes=pinned_size, digest="sha256:" + pinned_digest,
                 archive_download_url=f"{API}/actions/artifacts/{pinned_id}/zip")
        listing = {"total_count": 1, "artifacts": [a]}
        self.assertEqual(select_artifact(listing, "trace-on", self.run_record()), a)
        for change in ({"name": "windows-flutter-history-bundle"}, {"expired": True},
                       {"id": 7}, {"size_in_bytes": pinned_size + 1},
                       {"digest": "missing"}, {"workflow_run": {}}):
            with self.subTest(change=change), self.assertRaises(AuditError):
                select_artifact({"total_count": 1, "artifacts": [{**a, **change}]}, "trace-on", self.run_record())
        with self.assertRaises(AuditError):
            select_artifact({"total_count": 2, "artifacts": [a, a]}, "trace-on", self.run_record())

    def test_download_digest_and_token_do_not_follow_redirect(self):
        from unittest.mock import patch
        payload, calls = b"exact zip bytes", []
        a = self.artifact(payload)
        def fake(url, token, limit):
            calls.append((url, token))
            if len(calls) == 1:
                return 302, "https://test.blob.core.windows.net/file?sig=fixture", b""
            return 200, None, payload
        with patch(__name__ + ".request_bytes", side_effect=fake):
            self.assertEqual(download(a, "fixture-token"), payload)
        self.assertEqual([c[1] for c in calls], ["fixture-token", None])
        with patch(__name__ + ".request_bytes", return_value=(200, None, b"corrupted")):
            with self.assertRaises(AuditError):
                download(a, "fixture-token")
        self.assertIsNone(NoRedirect().redirect_request(None, None, 302, "", {}, "https://example.org"))
        for bad in ("http://test.blob.core.windows.net/f", "https://api.github.com/f",
                    "https://user:secret@test.blob.core.windows.net/f", "https://evil.example/f"):
            with self.subTest(url=bad), self.assertRaises(AuditError):
                storage_url(bad)

    def test_zip_paths_duplicates_links_and_limits(self):
        with open_zip(self.archive([("host.json", b"{}")])) as z:
            self.assertEqual(member_bytes(z, "host.json", MAX_JSON), b"{}")
        for bad in ("../host.json", "/host.json", "C:/host.json", "a\\host.json", "a//host.json", "a/./host.json"):
            with self.subTest(path=bad), self.assertRaises(AuditError):
                open_zip(self.archive([(bad, b"{}")]))
        for entries in ([("host.json", b"{}"), ("HOST.JSON", b"{}")], [("a.txt", b"0" * 500000)]):
            with self.assertRaises(AuditError):
                open_zip(self.archive(entries))
        with self.assertRaises(AuditError):
            safe_member(zipfile.ZipInfo("host.json\x00hidden"))
        info = zipfile.ZipInfo("link")
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaises(AuditError):
            safe_member(info)
        info = zipfile.ZipInfo("large")
        info.file_size = MAX_MEMBER + 1
        with self.assertRaises(AuditError):
            safe_member(info)
        data = bytearray(self.archive([("a", b"x")]))
        at = data.rfind(b"PK\x05\x06")
        struct.pack_into("<H", data, at + 10, MAX_ENTRIES + 1)
        with self.assertRaises(AuditError):
            open_zip(bytes(data))

    def test_duplicate_json_and_projection_do_not_forward_unknown_fields(self):
        with self.assertRaises(AuditError):
            strict_json(b'{"allTestsPassed":false,"allTestsPassed":true}')
        result = project("gate.json", {"allPassed": False, "password": "not-for-output",
                                     "cases": [{"case": "text-focused", "passed": False, "secret": "hidden"}]})
        self.assertNotIn("password", result)
        self.assertNotIn("secret", result["cases"][0])
        self.assertIs(result["allPassed"], False)

    def test_nested_projection_keeps_only_fixture_and_input_evidence(self):
        title = "Title preserved: \u05de\u05e7\u05d5\u05e8 "
        row = {"case": "text-focused", "reportAssertionsPassed": True,
               "before": {"title": title, "imageCount": 0, "focused": True, "private": "omit"},
               "after": {"title": title + "OTZARIA-HISTORY-QA-A-text-focused", "imageCount": 0},
               "inputBeforeCleanup": {"nativeControl": False, "foreground": 123, "flutterKeys": []},
               "controller": {"clipboardBeforeSelection": "B", "clipboardAfterSelection": "A",
                              "error": None, "caretPreparations": [{"inputSent": True}]},
               "keyEvents": [{"type": "KeyDownEvent", "physical": "0x7004d",
                              "logicalName": "End", "synthesized": False, "private": "omit"}]}
        result = project_row(row)
        self.assertEqual(result["before"]["title"], title)
        self.assertTrue(result["after"]["titleIsKnownFixture"])
        self.assertNotIn("private", result["before"])
        self.assertIs(result["inputBeforeCleanup"]["nativeControl"], False)
        self.assertEqual(result["controller"]["clipboardBeforeSelection"], "B")
        self.assertFalse(result["controller"]["errorPresent"])
        self.assertEqual(result["keyEventsCount"], 1)
        self.assertNotIn("private", result["keyEvents"][0])
        unknown = project_row({"after": {"title": "unrelated-private-text"}})
        self.assertNotIn("title", unknown["after"])
        self.assertFalse(unknown["after"]["titleIsKnownFixture"])
        names = {f"run/{case}/{stage}.png" for case in HISTORY_CASES
                 for stage in ("04-history-A-after-B-0", "05-after-real-history-selection")}
        for case in HISTORY_CASES:
            for slot, stage in (("before", "04-history-A-after-B-0"),
                                ("after", "05-after-real-history-selection")):
                self.assertEqual(choose_png(names, slot, case), (f"run/{case}/{stage}.png", case))

    def test_identity_checks_allow_missing_failed_win11_summary(self):
        host = {"sourceQaHead": HEAD, "productHead": PRODUCT, "sourceRun": str(RUN), "nativeTraceRequested": "true"}
        self.assertFalse(identities({"host.json": host}, "trace-on"))
        for change in ({"productHead": HEAD}, {"sourceQaHead": PRODUCT}, {"nativeTraceRequested": "false"}):
            with self.assertRaises(AuditError):
                identities({"host.json": {**host, **change}}, "trace-on")
        with self.assertRaises(AuditError):
            identities({"host.json": host, "native-clipboard-build.json": {"crateHash": "wrong"}}, "trace-on")

    def test_png_pair_selection_remains_useful_after_failure(self):
        before, after = "run/image-focused/04-history-A-after-B-0.png", "run/image-focused/98-error.png"
        self.assertEqual(choose_png({before, after}, "before"), (before, "image-focused"))
        self.assertEqual(choose_png({before, after}, "after"), (after, "image-focused"))
        self.assertEqual(choose_png({"privacy-error.png"}, "after"), ("privacy-error.png", "preparation-diagnostic"))
        self.assertEqual(choose_png({"private/dump.png"}, "before"), (None, None))

    def test_png_dimensions_crc_and_original_bytes(self):
        def chunk(kind, payload):
            return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
        def png(width):
            return (PNG_SIGNATURE + chunk(b"IHDR", struct.pack(">II5B", width, 1, 8, 6, 0, 0, 0))
                    + chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00\xff")) + chunk(b"IEND", b""))
        data = png(1)
        self.assertEqual(png_dimensions(data), (1, 1))
        self.assertEqual(base64.b64decode(base64.b64encode(data)), data)
        for invalid in (data[:-1], data[:-1] + bytes([data[-1] ^ 1]), png(9000)):
            with self.assertRaises(AuditError):
                png_dimensions(invalid)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--role", choices=tuple(NAMES))
    parser.add_argument("--slot", choices=("summary", "before", "after"), default="summary")
    parser.add_argument("--case", choices=("none",) + HISTORY_CASES, default="none")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.loadTestsFromTestCase(SelfChecks))
        emit({"selfChecksRun": result.testsRun, "selfChecksPassed": result.wasSuccessful(),
              "diagnosticOnly": True, "h1Acceptance": "not-evaluated"})
        return 0 if result.wasSuccessful() else 1
    require(args.role is not None, "role_required")
    require((args.slot == "summary") == (args.case == "none"), "case_slot_mismatch")
    audit(args.role, args.slot, None if args.case == "none" else args.case)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        code = str(error) if isinstance(error, AuditError) else type(error).__name__
        emit({"diagnosticOnly": True, "h1Acceptance": "not-evaluated", "auditError": code})
        sys.exit(1)
