"""Verify iOS Simulator PDF evidence against the built and installed app."""

import json
from pathlib import Path
import plistlib
import re
import struct

if __package__:
    from .installed_pdf_evidence import absolute, digest, require, validate_pdf_runtime
else:
    from installed_pdf_evidence import absolute, digest, require, validate_pdf_runtime

SYMBOLS = {
    "pdfium": ("FPDF_LoadDocument", "FPDF_RenderPageBitmap"),
    "printing": ("CGPDFDocumentCreateWithProvider", "CGContextDrawPDFPage"),
}
SOURCE = "dyld image list + dladdr of process symbols"
PRINTING = "CoreGraphics (CGPDFDocument/CGContext)"
ENVIRONMENT_SOURCE = "Dart Platform.environment (optional)"
ARCHITECTURES = {"arm64": (0x0100000C, "ios_arm64"), "x86_64": (0x01000007, "ios_x64")}
ABI_SOURCE = "Dart FFI Abi.current + Mach-O CPU type and IOSSIMULATOR build platform"
UUID = re.compile(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}")


def macho_simulator_image(path, architecture, *, executable):
    require(architecture in ARCHITECTURES, "Unsupported Simulator architecture")
    expected_cpu = ARCHITECTURES[architecture][0]
    size = path.stat().st_size
    with path.open("rb") as source:
        prefix = source.read(8)
        require(len(prefix) == 8, "Truncated Mach-O image")
        offset, limit = 0, size
        if prefix[:4] in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
            count = struct.unpack(">I", prefix[4:])[0]
            require(0 < count <= 16, "Invalid universal Mach-O slice count")
            wide = prefix[:4] == b"\xca\xfe\xba\xbf"
            length = 32 if wide else 20
            slices = []
            for _ in range(count):
                row = source.read(length)
                require(len(row) == length, "Truncated universal Mach-O header")
                cpu, _subtype, start, span, *_ = struct.unpack(">IIQQII" if wide else ">IIIII", row)
                require(start >= 8 + count * length and span >= 32 and start + span <= size,
                        "Mach-O slice points outside the binary")
                if cpu == expected_cpu:
                    slices.append((start, span))
            require(len(slices) == 1, "Missing or duplicate Simulator architecture slice")
            offset, limit = slices[0]
        source.seek(offset)
        header = source.read(32)
        require(len(header) == 32 and header[:4] == b"\xcf\xfa\xed\xfe", "Expected a 64-bit Mach-O image")
        _magic, cpu, _subtype, kind, count, commands_size, _flags, _reserved = struct.unpack("<8I", header)
        require(cpu == expected_cpu and kind == (2 if executable else 6), "Wrong Mach-O ABI or image kind")
        require(0 < count <= 16384 and 0 < commands_size <= 4 * 1024 * 1024
                and 32 + commands_size <= limit, "Invalid Mach-O load command bounds")
        commands = source.read(commands_size)
    require(len(commands) == commands_size, "Truncated Mach-O commands")
    position, platforms = 0, []
    for _ in range(count):
        require(position + 8 <= len(commands), "Truncated Mach-O command")
        command, length = struct.unpack_from("<II", commands, position)
        require(length >= 8 and length % 4 == 0 and position + length <= len(commands),
                "Invalid Mach-O command size")
        if command == 0x32:
            require(length >= 24, "Truncated LC_BUILD_VERSION")
            platform, minimum, sdk, tools = struct.unpack_from("<4I", commands, position + 8)
            require(24 + tools * 8 <= length, "Invalid LC_BUILD_VERSION tools")
            platforms.append({"platform": platform, "minimumOS": minimum, "sdk": sdk})
        position += length
    require(position == len(commands) and len(platforms) == 1 and platforms[0]["platform"] == 7,
            "Mach-O must target iOS Simulator, not macOS or an iOS device")
    return {"architecture": architecture, "cpuType": cpu, "fileType": kind, **platforms[0]}


def app_identity(bundle):
    bundle = Path(bundle).resolve(strict=True)
    require(bundle.is_dir() and bundle.name.endswith(".app"), "Expected an actual app container")
    metadata = bundle / "Info.plist"
    require(metadata.resolve(strict=True) == metadata, "App metadata is a symlink")
    with metadata.open("rb") as source:
        info = plistlib.load(source)
    name, identifier = info.get("CFBundleExecutable"), info.get("CFBundleIdentifier")
    require(isinstance(name, str) and name not in ("", ".", "..") and "/" not in name
            and isinstance(identifier, str) and re.fullmatch(r"[A-Za-z0-9.-]+", identifier),
            "Missing iOS bundle identity")
    require(info.get("CFBundleSupportedPlatforms") == ["iPhoneSimulator"]
            and info.get("DTPlatformName") == "iphonesimulator", "App was not built for iOS Simulator")
    return bundle, name, identifier


def verify_simulator(receipt):
    require(isinstance(receipt, dict) and type(receipt.get("schemaVersion")) is int and receipt["schemaVersion"] == 1
            and isinstance(receipt.get("udid"), str) and UUID.fullmatch(receipt["udid"])
            and isinstance(receipt.get("campaign"), str) and receipt["campaign"], "Missing owned Simulator identity")
    require(isinstance(receipt.get("runtimeIdentifier"), str)
            and receipt["runtimeIdentifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
            and isinstance(receipt.get("runtimeVersion"), str)
            and re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", receipt["runtimeVersion"])
            and isinstance(receipt.get("runtimeBuild"), str) and receipt["runtimeBuild"],
            "Missing selected iOS runtime version/build")
    require(absolute(receipt.get("runtimeRoot"))
            and receipt["runtimeRoot"].endswith(".simruntime/Contents/Resources/RuntimeRoot")
            and isinstance(receipt.get("model"), str)
            and re.fullmatch(r"iPhone[0-9]+,[0-9]+", receipt["model"]), "Missing Simulator runtime root/model")
    require(receipt.get("stateBefore") == receipt.get("stateAfter") == "Booted"
            and receipt.get("runtimeBefore") == receipt.get("runtimeAfter") == receipt["runtimeIdentifier"],
            "The owned Simulator changed runtime or stopped during the scenario")


def verify_owned_container(path, receipt, kind):
    path = Path(path).resolve(strict=True)
    require(kind in ("Bundle", "Data"), "Unknown Simulator container kind")
    marker = ("Devices", receipt["udid"], "data", "Containers", kind, "Application")
    parts = path.parts
    matches = [index for index in range(len(parts) - len(marker) + 1)
               if parts[index:index + len(marker)] == marker]
    require(len(matches) == 1, "Container does not belong to the owned Simulator UDID")
    tail = parts[matches[0] + len(marker):]
    require(len(tail) == (2 if kind == "Bundle" else 1) and UUID.fullmatch(tail[0]),
            "Unexpected owned Simulator container layout")
    return path


def verify_optional_environment(record, receipt):
    values = record.get("simulator")
    expected = {"udid": receipt["udid"], "model": receipt["model"], "runtimeRoot": receipt["runtimeRoot"]}
    require(record.get("simulatorEnvironmentSource") == ENVIRONMENT_SOURCE
            and isinstance(values, dict) and set(values).issubset(expected),
            "Missing or malformed optional Simulator environment evidence")
    availability = "unavailable" if not values else "collected" if len(values) == 3 else "partial"
    require(record.get("simulatorEnvironmentAvailability") == availability,
            "Optional Simulator environment availability contradicts its values")
    require(all(type(value) is str and value == expected[key] for key, value in values.items()),
            "Optional environment identifies another Simulator/runtime")


def verify_images(record, built, installed, receipt, pid):
    require(isinstance(record, dict) and record.get("source") == SOURCE
            and type(record.get("pid")) is int and record["pid"] == pid,
            "Missing dyld evidence from the scenario process")
    built, name, bundle_id = app_identity(built)
    installed = verify_owned_container(installed, receipt, "Bundle")
    installed, installed_name, installed_id = app_identity(installed)
    require((name, bundle_id) == (installed_name, installed_id), "Built and installed app identities differ")
    architectures = [name for name, (_cpu, abi) in ARCHITECTURES.items() if record.get("abi") == abi]
    require(len(architectures) == 1, "Missing or unsupported running iOS ABI")
    architecture = architectures[0]
    require(record.get("bundle") == str(installed) and record.get("executable") == str(installed / name),
            "Loaded app differs from the installed Simulator app")
    verify_optional_environment(record, receipt)
    require("configuredPdfrxModule" in record and record["configuredPdfrxModule"] is None
            and record.get("printingBackend") == PRINTING, "PDFium loader or printing backend was replaced")
    images, symbols = record.get("images"), record.get("symbols")
    require(isinstance(images, list) and images and all(absolute(x) for x in images)
            and len(set(images)) == len(images) and isinstance(symbols, dict), "Missing dyld image owners")
    executable, pdfium = installed / name, set()
    for role, names in SYMBOLS.items():
        for symbol in names:
            owner = symbols.get(symbol)
            require(isinstance(owner, dict) and absolute(owner.get("image"))
                    and owner["image"] in images and absolute(owner.get("canonicalImage")),
                    f"Missing loaded owner of {symbol}")
            for key in ("address", "imageBase"):
                require(isinstance(owner.get(key), str)
                        and re.fullmatch(r"0x[0-9a-f]*[1-9a-f][0-9a-f]*", owner[key]), "Missing native symbol address")
            image = Path(owner["canonicalImage"])
            if role == "pdfium":
                require(Path(owner["image"]).resolve(strict=True) == image
                        and image.resolve(strict=True) == image
                        and (image in (executable, installed / (name + ".debug.dylib"))
                             or image.is_relative_to(installed / "Frameworks")), "PDFium is outside the installed app")
                pdfium.add(image)
            else:
                roots = (Path("/"), Path(receipt["runtimeRoot"]))
                require(owner["canonicalImage"] == owner["image"]
                        and any(image.is_relative_to(root)
                                and re.fullmatch(r"System/Library/Frameworks/CoreGraphics\.framework/"
                                                 r"(?:Versions/[^/]+/)?CoreGraphics",
                                                 image.relative_to(root).as_posix())
                                for root in roots),
                        "Printing symbols are outside CoreGraphics in the selected Apple runtime")
    require(len(pdfium) == 1, "PDFium entry points came from different loaded images")
    expected, observed, evidence = {executable, *pdfium}, set(), []
    files = record.get("bundledFiles")
    require(isinstance(files, list), "Missing installed binary hashes")
    for entry in files:
        require(isinstance(entry, dict) and absolute(entry.get("path")), "Invalid hashed image")
        path = Path(entry["path"])
        require(path in expected and path not in observed and path.resolve(strict=True) == path,
                "Foreign, duplicate or symlinked app image")
        observed.add(path)
        relative = path.relative_to(installed)
        original = (built / relative).resolve(strict=True)
        require(original.is_relative_to(built), "Built image escapes the app bundle")
        require(type(entry.get("bytes")) is int and entry["bytes"] > 0
                and entry["bytes"] == path.stat().st_size == original.stat().st_size
                and entry.get("sha256") == digest(path) == digest(original),
                "Built, installed and mapped image bytes do not match")
        evidence.append({**entry, "relativePath": str(relative), "builtPath": str(original),
                         "macho": macho_simulator_image(original, architecture, executable=path == executable)})
    require(observed == expected, "Executable or PDFium binary proof is missing")
    return evidence


def device_output(report, data_container):
    data = Path(data_container).resolve(strict=True)
    paths = report.get("isolatedPaths")
    require(isinstance(paths, dict) and all(absolute(paths.get(key)) for key in ("root", "fixture", "output")),
            "Missing isolated Simulator paths")
    root = Path(paths["root"])
    require(root.resolve(strict=True) == root and root.is_relative_to(data / "tmp")
            and root.name.startswith("otzaria-pdf-ios-"), "Output does not belong to the owned app data container")
    require(paths["output"] == str(root / "output") and paths["fixture"] == str(root / "fixture"),
            "Unexpected Simulator fixture/output paths")
    output = root / "output"
    require(output.resolve(strict=True) == output, "Simulator output is a symlink")
    for path in output.iterdir():
        require(path.is_file() and not path.is_symlink(), "Unexpected directory or symlink in device artifacts")
    return output


def validate(wrapper, built, installed, data_container, receipt, commit):
    verify_simulator(receipt)
    verify_owned_container(installed, receipt, "Bundle")
    verify_owned_container(data_container, receipt, "Data")
    report = wrapper.get("installedPdfIosProbe")
    require(isinstance(report, dict), "Missing standalone iOS PDF report")
    expected = {"schemaVersion": 1, "scenario": "installed-pdf-ios-simulator-v1", "status": "passed",
                "platform": "ios", "buildMode": "debug", "flutterVersion": "3.47.7", "commit": commit,
                "campaign": receipt["campaign"], "errors": [], "contractErrors": [], "testFailures": [],
                "frameworkPassed": True, "physicalDeviceAcceptance": False, "physicalPrinter": "notRun",
                "appUnmounted": True}
    for key, value in expected.items():
        require(type(report.get(key)) is type(value) and report[key] == value, f"Incomplete iOS PDF result: {key}")
    require(report.get("webViewScenario", {}).get("status") == "notRun", "Unexecuted WKWebView scenario marked passed")
    pid, run_id = report.get("pid"), report.get("runId")
    require(type(pid) is int and pid > 0 and isinstance(run_id, str)
            and re.fullmatch(rf"{pid}-[0-9]+", run_id), "Missing scenario process identity")
    require(isinstance(report.get("osVersion"), str) and report["osVersion"].strip(), "Missing device OS version")
    bootstrap = report.get("bootstrap", {})
    require(bootstrap.get("status") == "passed"
            and type(bootstrap.get("startupTimeline", {}).get("revealMs")) in (int, float), "Real app bootstrap did not reveal")
    require(isinstance(bootstrap.get("fixtureSha256"), str)
            and re.fullmatch(r"synthetic-v4-pdf-cases:[0-9a-f]{64}", bootstrap["fixtureSha256"]),
            "Unexpected bootstrap fixture identity")
    require(report.get("bundleIdentifier") == app_identity(installed)[2], "Report belongs to another application")
    output = device_output(report, data_container)
    pdf = report.get("pdfRuntime")
    pngs = validate_pdf_runtime(pdf, "ios", output)
    loaded = pdf["steps"]["loadedModules"]
    binaries = verify_images(loaded, built, installed, receipt, pid)
    artifact = json.loads((output / "bundle-runtime-ios-images.json").read_text(encoding="utf-8"))
    require(artifact == {k: v for k, v in loaded.items() if k not in ("status", "durationMs")},
            "Loaded-image artifact differs from the driver report")
    device_report = json.loads((output / "installed-pdf-ios-report.json").read_text(encoding="utf-8"))
    require(device_report == report, "Final device report differs from the integration driver")
    return {"status": "passed", "platform": "ios", "buildMode": "debug", "commit": commit,
            "runId": run_id, "simulator": receipt, "bundledFiles": binaries, "pngArtifacts": pngs,
            "abiEvidence": {"source": ABI_SOURCE, "abi": loaded["abi"],
                            "architecture": binaries[0]["macho"]["architecture"]},
            "simulatorIdentityEvidence": {
                "source": "owned simctl containers + native image paths, hashes and IOSSIMULATOR Mach-O",
                "udid": receipt["udid"], "environmentAvailability": loaded["simulatorEnvironmentAvailability"]},
            "physicalDeviceAcceptance": False, "physicalPrinter": "notRun", "webViewScenario": "notRun"}
