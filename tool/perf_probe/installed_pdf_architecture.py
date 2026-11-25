"""Verify native x64/ARM64 executable and loaded PDF libraries in a Q02 bundle."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

MODULES = {
    "linux": ("libpdfium.so", "libpdfium_printing.so", "libprinting_plugin.so"),
    "windows": ("pdfium.dll", "pdfium_printing.dll", "printing_plugin.dll"),
}
MACHINES = {
    "ELF": {62: "x64", 183: "arm64"},
    "PE": {0x8664: "x64", 0xAA64: "arm64"},
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def binary_architecture(path):
    """Read the executable format, without executing an untrusted binary."""
    with path.open("rb") as source:
        header = source.read(64)
        require(len(header) == 64, f"Truncated native header: {path}")
        if header[:4] == b"\x7fELF":
            require(header[4:7] == b"\x02\x01\x01",
                    f"Expected a little-endian ELF64 binary: {path}")
            kind, machine, version = struct.unpack_from("<HHI", header, 16)
            require(kind in (2, 3) and version == 1
                    and struct.unpack_from("<H", header, 52)[0] == 64,
                    f"Invalid ELF64 executable/shared-library header: {path}")
            format_name = "ELF"
        elif header[:2] == b"MZ":
            offset = struct.unpack_from("<I", header, 60)[0]
            require(64 <= offset <= 1024 * 1024, f"Invalid PE offset: {path}")
            source.seek(offset)
            pe = source.read(26)
            require(len(pe) == 26 and pe[:4] == b"PE\x00\x00",
                    f"Missing PE signature: {path}")
            machine, sections = struct.unpack_from("<HH", pe, 4)
            optional_size = struct.unpack_from("<H", pe, 20)[0]
            require(sections > 0 and optional_size >= 112
                    and struct.unpack_from("<H", pe, 24)[0] == 0x20B
                    and path.stat().st_size >= offset + 24 + optional_size,
                    f"Expected a complete PE32+ binary: {path}")
            format_name = "PE"
        else:
            raise ValueError(f"Unsupported native binary format: {path}")
    architecture = MACHINES[format_name].get(machine)
    require(architecture is not None,
            f"Unsupported {format_name} machine 0x{machine:x}: {path}")
    return {"format": format_name, "machine": machine, "architecture": architecture}


def absolute_file(value):
    require(isinstance(value, str) and value and Path(value).is_absolute(),
            "Native evidence path must be absolute")
    path = Path(value).resolve(strict=True)
    require(path.is_file(), f"Native evidence is not a regular file: {path}")
    return path


def binary_receipt(path, *, platform, architecture):
    identity = binary_architecture(path)
    require(identity["format"] == ("PE" if platform == "windows" else "ELF"),
            f"Wrong native binary format for {platform}: {path}")
    require(identity["architecture"] == architecture,
            f"Expected native {architecture}, got {identity['architecture']}: {path}")
    return {"path": str(path), "bytes": path.stat().st_size,
            "sha256": digest(path), **identity}


def validate_bundle(report, *, executable, platform, architecture, commit):
    require(platform in MODULES and architecture in ("x64", "arm64"),
            "Unsupported desktop architecture")
    require(re.fullmatch(r"[0-9a-f]{40}", commit) is not None,
            "Expected a full source commit")
    require(isinstance(report, dict) and report.get("status") == "passed"
            and report.get("platform") == platform and report.get("buildMode") == "profile"
            and report.get("commit") == commit and report.get("flutterVersion") == "3.47.7"
            and report.get("errors") == [] and report.get("contractErrors") == [],
            "Missing successful current-commit installed-app report")
    require(type(report.get("pid")) is int and report["pid"] > 0
            and isinstance(report.get("runId"), str) and report["runId"],
            "Missing native launch identity")
    pdf = report.get("pdfRuntime")
    require(isinstance(pdf, dict) and pdf.get("status") == "passed"
            and pdf.get("platform") == platform and pdf.get("bundlePathsVerified") is True,
            "Missing passed native PDF runtime")
    require(all(type(pdf.get(key)) is int and pdf[key] == 0
                for key in ("ownedTabsRemaining", "ownedDocumentsRemaining"))
            and pdf.get("indexingActiveAfter") is False,
            "Native PDF ownership remained after teardown")
    executable = executable.resolve(strict=True)
    require(absolute_file(pdf.get("executable")) == executable,
            "Native report does not belong to the expected bundled executable")
    executable_proof = binary_receipt(executable, platform=platform, architecture=architecture)
    steps = pdf.get("steps")
    loaded = steps.get("loadedModules") if isinstance(steps, dict) else None
    require(isinstance(loaded, dict) and loaded.get("status") == "passed",
            "Loaded PDF modules were not observed")
    modules, observed = loaded.get("modules"), loaded.get("observedModulePaths")
    require(isinstance(modules, list) and len(modules) == len(MODULES[platform])
            and all(isinstance(item, dict) for item in modules),
            "Expected exactly three native PDF module receipts")
    require(isinstance(observed, list) and all(isinstance(path, str) for path in observed),
            "Missing actual mapped PDF module paths")
    names = [item.get("name") for item in modules]
    require(all(isinstance(name, str) for name in names)
            and sorted(names) == sorted(MODULES[platform]),
            "Missing, duplicate or unexpected PDF library")
    directory = executable.parent if platform == "windows" else executable.parent / "lib"
    receipts = []
    for name in MODULES[platform]:
        expected = directory / name
        require(expected.resolve(strict=True) == expected,
                f"PDF module escapes the actual bundle: {name}")
        module = next(item for item in modules if item["name"] == name)
        require(absolute_file(module.get("path")) == expected,
                f"PDF module report points outside the bundle: {name}")
        matching = [path for path in observed
                    if Path(path.removesuffix(" (deleted)")).name.lower() == name]
        require(len(matching) == 1 and not matching[0].endswith(" (deleted)")
                and absolute_file(matching[0]) == expected,
                f"PDF library was not uniquely loaded from the bundle: {name}")
        receipt = binary_receipt(expected, platform=platform, architecture=architecture)
        require(type(module.get("bytes")) is int and module["bytes"] == receipt["bytes"]
                and module.get("sha256") == receipt["sha256"],
                f"Bundled PDF library differs from the native receipt: {name}")
        receipts.append({"name": name, **receipt})
    require(receipts[0]["sha256"] != receipts[1]["sha256"],
            "pdfrx and printing must retain their separate PDFium binaries")
    return {"schemaVersion": 1, "status": "passed", "platform": platform,
            "architecture": architecture, "commit": commit, "pid": report["pid"],
            "runId": report["runId"], "executable": executable_proof, "modules": receipts,
            "scope": "Native file headers and mapped PDF modules from the completed Q02 run"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reports", type=Path, required=True)
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--platform", choices=tuple(MODULES), required=True)
    parser.add_argument("--architecture", choices=("x64", "arm64"), required=True)
    parser.add_argument("--commit", required=True)
    arguments = parser.parse_args()
    files = list(arguments.reports.glob("run-*/report.json"))
    require(len(files) == 1, "Expected exactly one fresh installed-app driver report")
    raw = json.loads(files[0].read_text(encoding="utf-8-sig"))
    require(isinstance(raw, dict), "Expected an installed-app report object")
    result = validate_bundle(raw.get("installedPluginProbe"), executable=arguments.executable,
                             platform=arguments.platform, architecture=arguments.architecture,
                             commit=arguments.commit)
    result.update(report=str(files[0].resolve()), reportSha256=digest(files[0]))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
