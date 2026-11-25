"""Bind Android PDF runtime evidence to the exact APK installed by the runner."""

import hashlib
from pathlib import PurePosixPath
import re
import struct
import zipfile

PDFIUM_ENTRY = "lib/x86_64/libpdfium.so"
PDF_RUNTIME_STEPS = ("view", "concurrentWork", "cancelAndRecover", "reopen", "loadedModules", "teardown")
SYSTEM_ROOTS = ("/system/", "/system_ext/", "/apex/", "/product/", "/vendor/")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def apk_pdfium_module(apk):
    with zipfile.ZipFile(apk) as archive:
        entries = [entry for entry in archive.infolist() if entry.filename == PDFIUM_ENTRY]
        require(len(entries) == 1, "APK must contain exactly one x86_64 PDFium entry")
        entry = entries[0]
        require(64 <= entry.file_size <= 128 * 1024 * 1024 and not entry.is_dir(),
                "APK PDFium entry has an invalid size")
        require(entry.compress_type == zipfile.ZIP_DEFLATED,
                "Android PDF proof requires the configured legacy native-library extraction")
        with archive.open(entry) as stream:
            header = stream.read(64)
            require(header[:7] == b"\x7fELF\x02\x01\x01"
                    and struct.unpack_from("<HH", header, 16) == (3, 62),
                    "APK PDFium must be a little-endian ELF64 x86_64 shared library")
            digest = hashlib.sha256(header)
            count = len(header)
            for chunk in iter(lambda: stream.read(256 * 1024), b""):
                digest.update(chunk)
                count += len(chunk)
            require(count == entry.file_size, "APK PDFium entry changed while being read")
    return {"entry": PDFIUM_ENTRY, "abi": "x86_64", "bytes": count, "sha256": digest.hexdigest()}


def installed_apk_path(output, package):
    lines = output.strip().splitlines()
    require(len(lines) == 1 and lines[0].startswith("package:"),
            "Expected one installed base APK, not missing or split-package evidence")
    path = lines[0].removeprefix("package:")
    require(re.fullmatch(r"/data/app/(?:[A-Za-z0-9_~+=-]+/)?" + re.escape(package)
                         + r"-[A-Za-z0-9_~+=-]+/base\.apk", path) is not None,
            "Package manager returned an unexpected dedicated APK path")
    return path


def installed_module_path(apk_path):
    return str(PurePosixPath(apk_path).parent / PDFIUM_ENTRY)


def sha256_receipt(output, expected_path):
    match = re.fullmatch(r"([a-f0-9]{64})  (.+)\n?", output)
    require(match is not None and match[2] == expected_path, "Missing or mismatched device SHA-256 receipt")
    return match[1]


def pdfium_mapped_paths(maps, *, executable_only=False):
    paths = set()
    for line in maps.splitlines():
        match = re.fullmatch(r"\S+\s+(\S+)\s+\S+\s+\S+\s+\S+\s+(/.+)", line)
        if match is None or executable_only and "x" not in match[1]:
            continue
        path = match[2]
        if PurePosixPath(path.removesuffix(" (deleted)")).name == "libpdfium.so":
            paths.add(path)
    return paths


def _system_path(path):
    return (isinstance(path, str) and path.startswith(SYSTEM_ROOTS)
            and not path.endswith(" (deleted)") and str(PurePosixPath(path)) == path
            and PurePosixPath(path).name == "libpdfium.so"
            and ".." not in PurePosixPath(path).parts)


def verify_pdf_runtime(pdf, apk, host_maps, *, package, process_id):
    require(isinstance(pdf, dict) and all(type(pdf.get(key)) is type(value) and pdf[key] == value for key, value in (
        ("status", "passed"), ("platform", "android"), ("bundlePathsVerified", True),
        ("ownedDocumentsRemaining", 0), ("ownedTabsRemaining", 0), ("indexingActiveAfter", False),
        ("physicalPrinter", "notRun"),
    )), "Android PDF runtime and teardown must pass")
    steps = pdf.get("steps")
    require(isinstance(steps, dict) and all(isinstance(steps.get(name), dict)
            and steps[name].get("status") == "passed" for name in PDF_RUNTIME_STEPS),
            "Every Android PDF runtime step must pass")
    require(isinstance(apk, dict) and apk.get("package") == package and apk.get("debuggable") is True,
            "Android PDF runtime requires the verified dedicated APK")
    source, installed = apk.get("pdfium"), apk.get("installed")
    require(isinstance(source, dict) and source.get("entry") == PDFIUM_ENTRY and source.get("abi") == "x86_64"
            and type(source.get("bytes")) is int and 64 <= source["bytes"] <= 128 * 1024 * 1024
            and re.fullmatch(r"[a-f0-9]{64}", str(source.get("sha256"))) is not None
            and re.fullmatch(r"[a-f0-9]{64}", str(apk.get("sha256"))) is not None
            and isinstance(installed, dict), "Missing APK PDFium or installation evidence")
    apk_path = installed_apk_path("package:" + str(installed.get("apkPath")), package)
    expected = installed_module_path(apk_path)
    require(installed.get("modulePath") == expected and installed.get("apkSha256") == apk.get("sha256")
            and installed.get("moduleSha256") == source.get("sha256"),
            "Installed APK or PDFium differs from the built APK")
    loaded = steps["loadedModules"]
    require(all(loaded.get(key) == value for key, value in (
        ("source", "/proc/self/maps"), ("package", package), ("abi", "x86_64"),
        ("processId", process_id), ("printingBackend", "android.graphics.pdf.PdfRenderer"),
    )) and "configuredPdfrxModule" in loaded and loaded["configuredPdfrxModule"] is None,
            "Android PDF runtime module identity or printing backend changed")
    module = loaded.get("appModule")
    require(isinstance(module, dict) and all(module.get(key) == value for key, value in (
        ("name", "libpdfium.so"), ("path", expected), ("bytes", source.get("bytes")),
        ("sha256", source.get("sha256")),
    )), "Mapped app PDFium bytes or path differ from the installed APK entry")
    require(isinstance(host_maps, dict) and host_maps.get("pid") == process_id,
            "Missing PDF maps from the same live app process")
    for observed in (loaded, host_maps):
        paths, executable = observed.get("observedModulePaths"), observed.get("executableModulePaths")
        require(isinstance(paths, list) and all(isinstance(path, str) for path in paths)
                and len(paths) == len(set(paths)) and paths.count(expected) == 1
                and all(path == expected or _system_path(path) for path in paths)
                and isinstance(executable, list) and expected in executable
                and all(isinstance(path, str) for path in executable) and len(executable) == len(set(executable))
                and all(path in paths for path in executable),
                "Android PDF runtime is missing its executable mapping or has foreign PDFium maps")
    system = loaded.get("systemModulePaths")
    require(isinstance(system, list) and all(_system_path(path) for path in system)
            and sorted(system) == sorted(path for path in loaded["observedModulePaths"] if path != expected),
            "System PdfRenderer libraries must be recorded separately from app PDFium")
    return {"apkSha256": apk["sha256"], "apkEntry": PDFIUM_ENTRY, "path": expected,
            "sha256": source["sha256"], "abi": "x86_64", "processId": process_id,
            "printingBackend": "android.graphics.pdf.PdfRenderer"}
