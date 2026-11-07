#!/usr/bin/env python3
"""Read the exact Windows debug-b artifact as data; no native rerun or artifact code execution."""
import hashlib
import base64
import struct
import traceback
import io
import json
import os
import re
import shutil
from pathlib import Path, PurePosixPath
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile

SOURCE = "05e150d09758e0da45ca1877a4d650358f1aa17f"
PARENT = SOURCE
OBSERVATION_HEAD = "6d66162655f89f2c7eed3b8fc9f9b114f2cd17b0"
ARTIFACT = 13562402291
RUN = 42341677104
ZIP_BYTES = 27604416
ZIP_SHA256 = "0b14273037c57ea66a90aa2fbaeb4b491f914ab3f2ce01cab5f58cdb0923102a"
QA_FILES = {".github/qa/4424/read_native_debug_b.py", ".github/workflows/qa_4424_native_debug_b_evidence.yml"}
MANIFEST = [["tool/perf_probe/installed_plugin_windows_lifetime.cs","050e97ca46a728986468e7cbabf4a864156a7a70","e373e8b5dcd6a17d925e52249050d9e99d0c0c1a04fa59523e8b1f86b30e4b15",19764,"100644"],["tool/perf_probe/test_installed_plugin_windows_lifetime.cs","d46736f77c8979b09ad84ca8bcce70653595e3ae","bc93f45dbbd1646dd59a08c43f7e5f1f6c3a75a69345060dea610f766c930c04",15375,"100644"],["pubspec.yaml","26054b0dfe7533a25a33dbec92f875289fb8c7f9","b900e75318dfb65333f97e8529c52dfe08df0893292e535700094da7ae8c6b51",13609,"100644"],["pubspec.lock","8a4569554fffc9ca5686633a58386d2c83487755","94bf01c88e2568424d39a7da767ecdd70356c915f8636e0ccb233121bb6ef932",66487,"100644"],["integration_test/support/installed_plugin_windows_lifetime.dart","564f27327f440d4099054456589891acbca609f4","d896f1580440e1fe726595b8d0afc64046a6480cbb0a949cf9a04c009c8a8173",3701,"100644"],[".github/workflows/installed_plugin_probe.yml","d126a4d7e11646c9d8071c8d72f32746e16cfa96","382f4f78f9b41fde647162d1058bec60d4df4ea4ad85cd48610cded77753b6d3",7040,"100644"],["tool/perf_probe/installed_plugin_windows_control.psm1","718bea8e88b1ec1c2623b5f2f12f779c66e24344","dea8243fa148fc09168e0833ac36b77fac03486e0657d478b545c672d0d23d5f",10454,"100644"],["tool/perf_probe/installed_plugin_windows_exit.psm1","61956f3c0f474f0f87c9648f9a51f593f7b9de03","5d1d26bc0adb24cc91f7ec81031daca4985233f7601a21dc30616c53ea373e96",15874,"100644"],["tool/perf_probe/test_installed_plugin_windows_runner.ps1","d2a576a91716044a5f9e2179075f11feba3cd6bc","9f732afcc8093933db9402de470a1f34d0e55289c398589efecc616e5adc8b93",12152,"100644"],["tool/perf_probe/installed_plugin_windows_runner.psm1","55d3c081c030771a923bb509db6e2bad9ea5a937","205ccece2043181621a9dae1a98db59d6df76b93b788a48e57cb3afc66c6e462",10724,"100644"],["tool/perf_probe/run_installed_plugin_windows.ps1","330129b3f178a4caecc05054ec9d2d4b515ae15b","edd23bafd7dd24ad7ffc4d090197610eed43c392e0050bc0b737fc8e4c7c0569",586,"100644"],["integration_test/installed_plugin_resource_probe_test.dart","e73166c5c7e37515501bb8f6265b38df568780dd","4f03d7f8f7a2cb94ed79590af5995b9f146077cceb7f49d688c41dceaf9d642e",53896,"100644"],["tool/perf_probe/WEBVIEW_RESOURCE_PROBE.md","5a5c69de8c717663a6777fe821521c6a9b7e629f","f97230e81069bf3799f0229999c649c0e7f4a5c4fd23890c39030f8e4ef58fc3",45250,"100644"],["test/tool/perf_probe/installed_plugin_windows_lifetime_test.dart","b439993f5a6aaa083d5c6aedf9e5def7cc9fe835","06e509186494e4a6a80a20f962a22bb92b3fb357fb7254b499db4056333443f3",6586,"100644"],["tool/perf_probe/test_installed_plugin_windows_control.ps1","ac580460a67166e47b3f7c15b71197d10fb02256","157dff260b0c608be395193a8dde2d0821b45f029e82b8315ae8db2b5fe5a1da",12208,"100644"],["tool/perf_probe/test_installed_plugin_windows_exit.ps1","fadec4e10d5e41773df39c0be5f6db93748115af","dd9f4244782b7f7043d9d66dad81b6acdf267e46e857a67ffb25f0bb518b4d0d",23197,"100644"]]
ROOT = Path.cwd().resolve()
OUT = Path(os.environ["QA_NATIVE_DEBUG_EVIDENCE_OUTPUT"]).resolve()
assert OUT != ROOT and ROOT not in OUT.parents
OUT.mkdir(parents=True, exist_ok=False)
token = os.environ.pop("DIAGNOSTIC_TOKEN")
os.environ.pop("GITHUB_TOKEN", None)
os.environ.pop("GH_TOKEN", None)
sys.dont_write_bytecode = True

def sha(data):
    return hashlib.sha256(data).hexdigest()

def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode().strip()

def snapshot():
    files = []
    for raw in subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).split(b"\0"):
        if not raw:
            continue
        name = os.fsdecode(raw)
        path = ROOT / name
        data = os.fsencode(os.readlink(path)) if path.is_symlink() else path.read_bytes()
        files.append({"path": name, "bytes": len(data), "sha256": sha(data),
                      "mode": path.lstat().st_mode, "symlink": path.is_symlink()})
    return {"head": git("rev-parse", "HEAD"), "indexTree": git("write-tree"),
            "status": git("status", "--porcelain=v1", "--untracked-files=all"), "files": files}

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, url):
        return None

def api(path):
    assert path.startswith("/repos/Otzaria/otzaria/actions/")
    request = urllib.request.Request("https://api.github.com" + path, headers={
        "Authorization": "Bearer " + token,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    return urllib.request.build_opener(NoRedirect).open(request, timeout=30)


# Microsoft minidump/MSVC metadata are interpreted as bounded data only.
# Layout references:
# https://learn.microsoft.com/windows/win32/api/minidumpapiset/ns-minidumpapiset-minidump_exception_stream
# https://devblogs.microsoft.com/oldnewthing/20100730-00/?p=13273
# https://devblogs.microsoft.com/oldnewthing/20160915-00/?p=94316
class PE:
    def __init__(self, data):
        self.data = data
        assert data[:2] == b"MZ"
        pe = struct.unpack_from("<I", data, 0x3c)[0]
        assert data[pe:pe + 4] == b"PE\0\0"
        machine, count, self.timestamp = struct.unpack_from("<HHI", data, pe + 4)
        assert machine == 0x8664 and 0 < count < 96
        optional_size = struct.unpack_from("<H", data, pe + 20)[0]
        opt = pe + 24
        assert struct.unpack_from("<H", data, opt)[0] == 0x20b
        self.size = struct.unpack_from("<I", data, opt + 56)[0]
        self.checksum = struct.unpack_from("<I", data, opt + 64)[0]
        self.headers = struct.unpack_from("<I", data, opt + 60)[0]
        self.sections = []
        for index in range(count):
            offset = opt + optional_size + index * 40
            name = data[offset:offset + 8].rstrip(b"\0").decode("ascii", "replace")
            virtual_size, rva, raw_size, raw_pointer = struct.unpack_from("<IIII", data, offset + 8)
            self.sections.append({"name": name, "rva": rva, "virtualSize": virtual_size,
                                  "rawSize": raw_size, "rawPointer": raw_pointer})
        self.cv = None
        debug_rva, debug_size = struct.unpack_from("<II", data, opt + 112 + 6 * 8)
        if debug_rva and debug_size:
            assert debug_size % 28 == 0 and debug_size < 1024 * 1024
            directory = self.read(debug_rva, debug_size)
            for offset in range(0, debug_size, 28):
                typ, size, address, pointer = struct.unpack_from("<IIII", directory, offset + 12)
                if typ == 2 and size <= 16384:
                    self.cv = cv_record(data[pointer:pointer + size])

    def read(self, rva, size):
        assert 0 <= rva < self.size and 0 <= size <= 1024 * 1024
        if rva + size <= self.headers:
            value = self.data[rva:rva + size]
        else:
            for section in self.sections:
                delta = rva - section["rva"]
                if 0 <= delta and delta + size <= section["rawSize"]:
                    offset = section["rawPointer"] + delta
                    value = self.data[offset:offset + size]
                    break
            else:
                raise ValueError("PE RVA is not backed by retained file: " + hex(rva))
        assert len(value) == size
        return value

def cv_record(data):
    if len(data) < 24 or data[:4] != b"RSDS":
        return {"rawHex": data.hex()}
    return {"signature": "RSDS", "guidBytesHex": data[4:20].hex(),
            "age": struct.unpack_from("<I", data, 20)[0],
            "pdb": data[24:].split(b"\0", 1)[0].decode("utf-8", "replace")}

def same_image(module, pe):
    return (module["timestamp"] == pe.timestamp and module["size"] == pe.size
            and module["checksum"] == pe.checksum
            and module["codeView"] is not None and pe.cv is not None
            and module["codeView"].get("guidBytesHex") == pe.cv.get("guidBytesHex")
            and module["codeView"].get("age") == pe.cv.get("age"))

def inspect_dump(data, binary_inputs):
    assert data[:4] == b"MDMP"
    def unpack(fmt, offset):
        size = struct.calcsize(fmt)
        assert 0 <= offset and offset + size <= len(data)
        return struct.unpack_from(fmt, data, offset)

    stream_count, directory_rva = unpack("<II", 8)
    assert 0 < stream_count <= 128
    streams = {}
    stream_entries = []
    for index in range(stream_count):
        typ, size, rva = unpack("<III", directory_rva + 12 * index)
        assert rva + size <= len(data)
        stream_entries.append({"type": typ, "bytes": size, "rva": rva})
        if typ == 0:
            continue
        assert typ not in streams
        streams[typ] = (size, rva)
    assert streams[7][0] >= 2 and unpack("<H", streams[7][1])[0] == 9, "AMD64 dump required"
    modules = []
    size, start = streams[4]
    count, = unpack("<I", start)
    assert 0 < count < 2048 and 4 + count * 108 <= size
    for index in range(count):
        offset = start + 4 + index * 108
        base, size_image, checksum, timestamp, name_rva = unpack("<QIIII", offset)
        length, = unpack("<I", name_rva)
        assert length < 32768
        name = data[name_rva + 4:name_rva + 4 + length].decode("utf-16-le")
        cv_size, cv_rva = unpack("<II", offset + 76)
        assert cv_size < 16384 and cv_rva + cv_size <= len(data)
        modules.append({"path": name, "name": name.replace("\\", "/").split("/")[-1],
                        "base": base, "size": size_image, "checksum": checksum, "timestamp": timestamp,
                        "codeView": cv_record(data[cv_rva:cv_rva + cv_size]) if cv_size else None})
    images = {}
    image_receipts = []
    for module in modules:
        name = module["name"].lower()
        candidates = list(binary_inputs.get(name, []))
        if os.name == "nt" and name in {"kernelbase.dll", "kernel32.dll", "ntdll.dll",
                                        "ucrtbase.dll", "msvcp_win.dll", "win32u.dll"}:
            system_file = Path(os.environ["SystemRoot"]) / "System32" / module["name"]
            if system_file.is_file():
                candidates.append(("runner-system-image", str(system_file), system_file.read_bytes()))
        for origin, path, content in candidates:
            receipt = {"module": module["path"], "origin": origin, "path": path,
                       "bytes": len(content), "sha256": sha(content), "matched": False}
            try:
                pe = PE(content)
                receipt["matched"] = same_image(module, pe)
                receipt["peIdentity"] = {"timestamp": pe.timestamp, "size": pe.size,
                                         "checksum": pe.checksum, "codeView": pe.cv}
                if receipt["matched"]:
                    images[module["base"]] = pe
                    assert re.fullmatch(r"[A-Za-z0-9_.-]+", module["name"])
                    image_folder = OUT / "offline-images"
                    image_folder.mkdir(exist_ok=True)
                    (image_folder / module["name"]).write_bytes(content)
            except Exception as error:
                receipt["error"] = str(error)
            image_receipts.append(receipt)
    memory = []
    if 5 in streams:
        size, start = streams[5]
        count, = unpack("<I", start)
        assert count < 100000 and 4 + count * 16 <= size
        for index in range(count):
            address, length, rva = unpack("<QII", start + 4 + index * 16)
            assert rva + length <= len(data)
            memory.append((address, length, rva))
    if 9 in streams:
        size, start = streams[9]
        count, rva = unpack("<QQ", start)
        assert count < 100000 and 16 + count * 16 <= size
        for index in range(count):
            address, length = unpack("<QQ", start + 16 + index * 16)
            assert rva + length <= len(data)
            memory.append((address, length, rva))
            rva += length
    threads = []
    size, start = streams[3]
    count, = unpack("<I", start)
    assert 0 < count < 4096 and 4 + count * 48 <= size
    for index in range(count):
        offset = start + 4 + index * 48
        tid, = unpack("<I", offset)
        address, length, rva = unpack("<QII", offset + 24)
        context_size, context_rva = unpack("<II", offset + 40)
        assert rva + length <= len(data) and context_rva + context_size <= len(data)
        memory.append((address, length, rva))
        threads.append({"tid": tid, "stackAddress": address, "stackBytes": length,
                        "contextBytes": context_size, "contextRva": context_rva})
    def module_for(address):
        return next((m for m in modules if m["base"] <= address < m["base"] + m["size"]), None)

    def read_memory(address, length):
        assert 0 < length <= 1024 * 1024
        for start, size, rva in memory:
            delta = address - start
            if 0 <= delta and delta + length <= size:
                return data[rva + delta:rva + delta + length]
        module = module_for(address)
        if module and module["base"] in images:
            return images[module["base"]].read(address - module["base"], length)
        raise ValueError("Memory unavailable at " + hex(address) + " for " + str(length) + " bytes")

    def cstring(address, maximum=512):
        value = bytearray()
        for offset in range(maximum):
            char = read_memory(address + offset, 1)[0]
            if char == 0:
                return value.decode("utf-8", "replace")
            value.append(char)
        raise ValueError("String exceeds bound")

    exception_size, exception_rva = streams[6]
    assert exception_size >= 168
    tid, = unpack("<I", exception_rva)
    code, flags, nested, address, count = unpack("<IIQQI", exception_rva + 8)
    assert count <= 15
    parameters = list(unpack("<" + "Q" * count, exception_rva + 40))
    context_size, context_rva = unpack("<II", exception_rva + 160)
    assert context_size >= 256 and context_rva + context_size <= len(data)
    context = data[context_rva:context_rva + context_size]
    names = ["rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi",
             "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip"]
    registers = {name: struct.unpack_from("<Q", context, 120 + index * 8)[0]
                 for index, name in enumerate(names)}
    result = {"streams": stream_entries,
              "modules": modules, "imageIdentityChecks": image_receipts, "threads": threads,
              "exception": {"tid": tid, "code": hex(code), "flags": flags, "nested": hex(nested),
                            "address": hex(address), "parameters": [hex(p) for p in parameters]},
              "registers": {name: hex(value) for name, value in registers.items()},
              "contextHex": context.hex(), "memoryRangeCount": len(memory),
              "stackCandidatesAreNotUnwoundFrames": True}
    if 15 in streams:
        size, start = streams[15]
        if size >= 12:
            flags = unpack("<I", start + 4)[0]
            result["miscProcessId"] = unpack("<I", start + 8)[0] if flags & 1 else None
    if code == 0xe06d7363 and count == 4:
        throwing_module = module_for(parameters[3])
        result["throwingModule"] = throwing_module
        try:
            base, throw_info = parameters[3], parameters[2]
            words = struct.unpack("<IIII", read_memory(throw_info, 16))
            array = base + words[3]
            type_count = struct.unpack("<I", read_memory(array, 4))[0]
            assert 0 < type_count <= 64
            types = []
            for index in range(type_count):
                rva = struct.unpack("<I", read_memory(array + 4 + index * 4, 4))[0]
                catchable = base + rva
                fields = struct.unpack("<IIiiiII", read_memory(catchable, 28))
                descriptor = base + fields[1]
                types.append({"catchableTypeAddress": hex(catchable), "fields": list(fields),
                              "typeDescriptorAddress": hex(descriptor),
                              "decoratedName": cstring(descriptor + 16)})
            result["cppThrow"] = {"throwInfoAddress": hex(throw_info), "throwInfoWords": list(words),
                                  "catchableTypeArray": hex(array), "types": types}
            object_bytes = read_memory(parameters[1], 64)
            result["cppThrow"]["objectAddress"] = hex(parameters[1])
            result["cppThrow"]["objectHex"] = object_bytes.hex()
            pointer_strings = []
            for offset in range(0, 64, 8):
                pointer = struct.unpack_from("<Q", object_bytes, offset)[0]
                try:
                    string = cstring(pointer, 256)
                    if string and all(char.isprintable() for char in string):
                        pointer_strings.append({"offset": offset, "pointer": hex(pointer), "text": string})
                except Exception:
                    pass
            result["cppThrow"]["objectPointerStrings"] = pointer_strings
        except Exception as error:
            result["cppThrowDecodeError"] = str(error)
    matching_thread = next(thread for thread in threads if thread["tid"] == tid)
    rsp = registers["rsp"]
    upper = matching_thread["stackAddress"] + matching_thread["stackBytes"]
    stack_size = min(max(0, upper - rsp), 16384)
    stack_data = read_memory(rsp, stack_size) if stack_size else b""
    result["exceptionStack"] = {"address": hex(rsp), "bytes": len(stack_data), "hex": stack_data.hex()}
    candidates = []
    for offset in range(0, len(stack_data) - 7, 8):
        pointer = struct.unpack_from("<Q", stack_data, offset)[0]
        module = module_for(pointer)
        if module:
            candidates.append({"stackAddress": hex(rsp + offset), "offset": offset, "pointer": hex(pointer),
                               "module": module["path"], "rva": hex(pointer - module["base"])})
    result["stackAddressCandidates"] = candidates
    return result


def offline_debugger(dump):
    folder = OUT / "offline-images"
    folder.mkdir(exist_ok=True)
    candidates = []
    if os.name == "nt":
        kits = Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "Windows Kits/10/Debuggers/x64/cdb.exe"
        if kits.is_file():
            candidates.append(("cdb", str(kits)))
    for name in ["cdb", "lldb", "lldb-20", "lldb-19", "lldb-18"]:
        location = shutil.which(name)
        if location:
            candidates.append(("cdb" if name == "cdb" else "lldb", location))
    if os.name == "nt":
        llvm = Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "LLVM/bin/lldb.exe"
        if llvm.is_file():
            candidates.append(("lldb", str(llvm)))
    if not candidates:
        return {"status": "NOT_RUN", "reason": "No installed offline debugger found"}
    kind, executable = candidates[0]
    if kind == "cdb":
        command = [executable, "-sins", "-z", str(dump), "-y", str(folder), "-i", str(folder),
                   "-c", ".ecxr; .exr -1; kP 50; lm; q"]
    else:
        def quoted(path):
            return '"' + str(path).replace("\\", "/").replace('"', '\\"') + '"'
        command = [executable, "--no-lldbinit", "--batch",
                   "-O", "settings set target.load-script-from-symbol-file false",
                   "-O", "settings set target.exec-search-paths " + quoted(folder),
                   "-o", "target create --core " + quoted(dump),
                   "-o", "thread list", "-o", "thread backtrace -c 40 all", "-o", "image list"]
    environment = os.environ.copy()
    for key in ["_NT_SYMBOL_PATH", "_NT_ALT_SYMBOL_PATH", "GITHUB_TOKEN", "GH_TOKEN", "DIAGNOSTIC_TOKEN"]:
        environment.pop(key, None)
    stdout = OUT / "offline-debugger.log"
    record = {"kind": kind, "executable": executable, "sha256": sha(Path(executable).read_bytes()),
              "command": command, "artifactCodeExecuted": False,
              "networkSymbolDownloads": False, "scope": "Existing dump only; never launches application"}
    try:
        with stdout.open("wb") as output:
            run = subprocess.run(command, cwd=OUT, env=environment, stdout=output,
                                 stderr=subprocess.STDOUT, timeout=150)
        record["returncode"] = run.returncode
        record["status"] = "completed" if run.returncode == 0 else "tool-error"
    except subprocess.TimeoutExpired:
        record["status"] = "timeout"
    except Exception as error:
        record["status"] = "tool-error"
        record["error"] = str(error)
    if stdout.exists():
        data = stdout.read_bytes()
        record.update({"bytes": len(data), "logSha256": sha(data),
                       "text": data[:512 * 1024].decode("utf-8", "replace"),
                       "logTruncatedInReport": len(data) > 512 * 1024})
    return record

before = snapshot()
report = {"scope": "Read-only exact Windows debug-b artifact; no native rerun, no artifact code execution and no application acceptance",
          "source": SOURCE, "observationHead": OBSERVATION_HEAD, "artifactId": ARTIFACT, "observationRun": RUN,
          "status": "failed", "nativeAPIExecution": "NOT_RUN", "applicationAcceptance": "NOT_RUN"}
try:
    assert git("rev-parse", "HEAD^") == PARENT
    assert git("rev-parse", SOURCE + "^{tree}") == "e43bd8f0db6d1b2a107f767c18e3261a27e15837"
    assert set(git("diff", "--name-only", PARENT, "HEAD").splitlines()) == QA_FILES
    assert not before["status"]
    for name, blob, digest, size, mode in MANIFEST:
        data = (ROOT / name).read_bytes()
        assert len(data) == size and sha(data) == digest, name
        assert hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest() == blob, name
        assert git("ls-files", "-s", "--", name).split()[0] == mode, name
    with api("/repos/Otzaria/otzaria/actions/artifacts/" + str(ARTIFACT)) as response:
        metadata = json.load(response)
    assert metadata["id"] == ARTIFACT and not metadata["expired"]
    assert metadata["size_in_bytes"] == ZIP_BYTES and metadata["digest"] == "sha256:" + ZIP_SHA256
    assert metadata["workflow_run"]["id"] == RUN and metadata["workflow_run"]["head_sha"] == OBSERVATION_HEAD
    report["artifactMetadata"] = metadata
    try:
        response = api("/repos/Otzaria/otzaria/actions/artifacts/" + str(ARTIFACT) + "/zip")
    except urllib.error.HTTPError as error:
        assert error.code in (301, 302, 303, 307, 308), error.code
        location = error.headers["Location"]
        parsed = urllib.parse.urlparse(location)
        assert parsed.scheme == "https" and parsed.hostname and not parsed.username and not parsed.password
        # No bearer token is forwarded to the signed artifact redirect.
        with urllib.request.urlopen(urllib.request.Request(location), timeout=60) as redirected:
            archive_bytes = redirected.read(ZIP_BYTES + 1)
    else:
        with response:
            archive_bytes = response.read(ZIP_BYTES + 1)
    assert len(archive_bytes) == ZIP_BYTES and sha(archive_bytes) == ZIP_SHA256
    (OUT / "original-artifact.zip").write_bytes(archive_bytes)
    report["verifiedArchive"] = {"bytes": len(archive_bytes), "sha256": sha(archive_bytes)}
    artifact_files = []
    selected_files = []
    dumps = []
    retained = {}
    binary_inputs = {}
    actual_dumps = []
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
        entries = archive.infolist()
        assert len(entries) < 1000
        assert sum(item.file_size for item in entries) < 768 * 1024 * 1024
        assert len({item.filename for item in entries}) == len(entries)
        for item in entries:
            path = PurePosixPath(item.filename)
            assert not path.is_absolute() and ".." not in path.parts and "\\" not in item.filename
            assert not item.flag_bits & 1 and item.file_size <= 512 * 1024 * 1024
            assert (item.external_attr >> 16) & 0o170000 != 0o120000
            if item.is_dir():
                continue
            data = archive.read(item)
            record = {"path": item.filename, "bytes": len(data), "sha256": sha(data)}
            artifact_files.append(record)
            if "/actual/symbols/" in item.filename and path.suffix.lower() in {".dll", ".exe", ".pdb"}:
                basename = path.name.split("-", 1)[1]
                assert re.fullmatch(r"[A-Za-z0-9_.-]+", basename)
                assert path.name.split("-", 1)[0] == sha(data)[:12]
                binary_inputs.setdefault(basename.lower(), []).append(("original-artifact", item.filename, data))
                image_folder = OUT / "offline-images"
                image_folder.mkdir(exist_ok=True)
                (image_folder / basename).write_bytes(data)
            if path.suffix == ".dmp":
                assert len(data) >= 32
                signature, version, streams, directory_rva = struct.unpack_from("<IIII", data)
                if "/actual/" in item.filename:
                    actual_dumps.append((record, data))
                    dump_folder = OUT / "dumps"
                    dump_folder.mkdir(exist_ok=True)
                    assert re.fullmatch(r"[A-Za-z0-9_.-]+", path.name)
                    (dump_folder / path.name).write_bytes(data)
                dumps.append({**record, "signatureHex": hex(signature), "versionHex": hex(version),
                              "streams": streams, "directoryRva": directory_rva,
                              "scope": "actual" if "/actual/" in item.filename else "control"})
            selected = (
                item.filename in {
                    "installed-plugin-probe/windows-native-exit.json",
                    "installed-plugin-probe/windows-native-exit-start.json",
                    "installed-plugin-probe/windows-device-report.json",
                    "installed-plugin-probe/device/installed-plugin-report.json",
                    "installed-plugin-probe/run.log",
                    "installed-plugin-probe/fixture-errors.txt",
                    "installed-plugin-probe/native-debug/control-result.json",
                    "installed-plugin-probe/native-debug/control/native-debug-summary.json",
                    "installed-plugin-probe/native-debug/finish.json",
                    "installed-plugin-probe/native-debug/raw-manifest.json",
                }
                or item.filename.startswith("installed-plugin-probe/native-debug/actual/")
                or (item.filename.startswith("installed-plugin-probe/qa-snapshots/") and path.name.endswith("-receipt.json"))
            )
            if selected and path.suffix in {".json", ".jsonl", ".txt", ".log", ""}:
                assert len(data) < 16 * 1024 * 1024
                target = OUT / "retained" / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                retained[item.filename] = data
                text = data.decode("utf-8-sig", "strict")
                selected_files.append({**record, "base64": base64.b64encode(data).decode("ascii"), "text": text})
    report["artifactFiles"] = artifact_files
    report["selectedFiles"] = selected_files
    report["minidumpHeaders"] = dumps
    native = json.loads(retained["installed-plugin-probe/windows-native-exit.json"].decode("utf-8-sig"))
    report["actualNativeReceipt"] = native
    report["actualNativeReceiptIdentifiesObservation"] = native["commit"] == OBSERVATION_HEAD
    assert native["commit"] == OBSERVATION_HEAD
    device_path = "installed-plugin-probe/windows-device-report.json"
    device_bytes = retained.get(device_path, b"")
    report["deviceReportRead"] = {"path": device_path, "bytes": len(device_bytes),
                                 "sha256": sha(device_bytes), "status": "unavailable"}
    try:
        device = json.loads(device_bytes.decode("utf-8-sig"))
        assert isinstance(device, dict), "The device report must be a JSON object"
        report["deviceReportRead"]["status"] = "decoded"
        report["partialDeviceSummary"] = {key: device.get(key) for key in [
            "commit", "runId", "pid", "status", "setupStep", "policyRestored", "errors", "testFailures", "contractErrors"
        ]}
        report["partialDeviceSummary"]["phases"] = [{key: phase.get(key) for key in ["name", "status", "error"]}
                                                   for phase in device["phases"]]
    except (ValueError, AssertionError, KeyError, TypeError) as error:
        # An empty/truncated report is original crash evidence. Preserve that
        # failure and continue the independent read-only dump interpretation.
        report["deviceReportRead"]["error"] = str(error)
        report["partialDeviceSummary"] = None
    actual_prefix = "installed-plugin-probe/native-debug/actual/"
    report["actualMonitorFiles"] = [row for row in artifact_files if row["path"].startswith(actual_prefix)]
    report["actualMonitorSummaryPresent"] = any(row["path"] == actual_prefix + "native-debug-summary.json"
                                                for row in artifact_files)
    report["actualMinidumpCount"] = sum(row["scope"] == "actual" for row in dumps)
    report["controlMinidumpCount"] = sum(row["scope"] == "control" for row in dumps)
    report["originalDriverExit"] = native["driverExitCode"]
    report["originalNativeExit"] = native["nativeExit"]
    report["causeOfApplicationExit"] = "UNPROVEN"
    assert len(actual_dumps) == 1
    record, dump_bytes = actual_dumps[0]
    report["actualDumpDecoded"] = inspect_dump(dump_bytes, binary_inputs)
    decoded = report["actualDumpDecoded"]
    assert decoded["exception"]["tid"] == 6008 and decoded["exception"]["code"] == "0xe06d7363"
    assert decoded.get("miscProcessId") == 8736
    assert native["nativeExit"]["processId"] == 8736
    assert str(native["nativeExit"]["creationFileTime"]) == "134385029219720276"
    report["offlineDebugger"] = offline_debugger(OUT / "dumps" / PurePosixPath(record["path"]).name)
    report["diagnosticExitDiffersFromUndebuggedExit"] = True
    report["artifactCodeExecuted"] = False
    report["status"] = "completed"
except Exception as error:
    report["error"] = str(error)
    report["traceback"] = traceback.format_exc()

finally:
    after = snapshot()
    report["sourceAndIndexUnchanged"] = before == after
    if before != after:
        report["status"] = "failed"
    report["trackedFiles"] = len(after["files"])
    for name, value in [("source-before.json", before), ("source-after.json", after), ("native-debug-b-evidence.json", report)]:
        (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("BEGIN_QA4424_NATIVE_DEBUG_B_EVIDENCE", flush=True)
    print(json.dumps(report, ensure_ascii=False), flush=True)
    print("END_QA4424_NATIVE_DEBUG_B_EVIDENCE", flush=True)
raise SystemExit(0 if report["status"] == "completed" else 1)
