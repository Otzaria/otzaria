#!/usr/bin/env python3
"""Run the real PDF app in one owned iOS Simulator and preserve native evidence."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

if __package__:
    from .installed_pdf_ios import UUID, app_identity, device_output, require, validate
else:
    from installed_pdf_ios import UUID, app_identity, device_output, require, validate


def command(arguments, *, timeout=120):
    result = subprocess.run(arguments, text=True, capture_output=True, timeout=timeout, check=False)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {arguments}\n{result.stdout}\n{result.stderr}")
    return result.stdout.strip()


def simctl(*arguments, timeout=120):
    return command(["xcrun", "simctl", *arguments], timeout=timeout)


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def simulator_entry(receipt, devices):
    found = [(runtime, entry) for runtime, entries in devices.items() for entry in entries
             if entry.get("udid") == receipt["udid"]]
    require(len(found) == 1, "Owned Simulator is missing or ambiguous")
    runtime, entry = found[0]
    require(runtime == receipt["runtimeIdentifier"] and entry.get("name") == receipt["name"]
            and entry.get("deviceTypeIdentifier") == receipt["deviceTypeIdentifier"],
            "Owned Simulator identity changed")
    return runtime, entry


def choose_simulator(runtimes, devices):
    choices = []
    for runtime in runtimes:
        if not runtime.get("isAvailable") or not runtime.get("identifier", "").startswith(
                "com.apple.CoreSimulator.SimRuntime.iOS-"):
            continue
        for device in devices.get(runtime["identifier"], []):
            if device.get("isAvailable") and device.get("deviceTypeIdentifier", "").startswith(
                    "com.apple.CoreSimulator.SimDeviceType.iPhone-"):
                choices.append((runtime, device))
    require(choices, "No available iOS runtime with a compatible iPhone Simulator")
    return max(choices, key=lambda pair: tuple(int(part) for part in pair[0]["version"].split(".")))


def create_simulator(campaign):
    runtimes = json.loads(simctl("list", "-j", "runtimes"))["runtimes"]
    devices = json.loads(simctl("list", "-j", "devices"))["devices"]
    runtime, prototype = choose_simulator(runtimes, devices)
    name = "otzaria-pdf-" + campaign
    receipt = {"schemaVersion": 1, "campaign": campaign, "name": name,
               "deviceTypeIdentifier": prototype["deviceTypeIdentifier"],
               "runtimeIdentifier": runtime["identifier"], "runtimeVersion": runtime["version"],
               "runtimeBuild": runtime["buildversion"], "runtimeBundle": runtime["bundlePath"]}
    udid = simctl("create", name, prototype["deviceTypeIdentifier"], runtime["identifier"])
    require(UUID.fullmatch(udid), "simctl did not return an owned Simulator UUID")
    receipt["udid"] = udid
    return receipt


def boot_simulator(receipt):
    udid = receipt["udid"]
    simctl("boot", udid)
    try:
        simctl("bootstatus", udid, "-b", timeout=300)
    except subprocess.TimeoutExpired:
        print("Simulator boot status timed out; attempting a fresh boot", file=sys.stderr, flush=True)
        _, device = simulator_entry(receipt, json.loads(simctl("list", "-j", "devices"))["devices"])
        if device.get("state") != "Shutdown":
            simctl("shutdown", udid)
        simctl("boot", udid)
        simctl("bootstatus", udid, "-b", timeout=300)
    runtime, device = simulator_entry(receipt, json.loads(simctl("list", "-j", "devices"))["devices"])
    require(device.get("state") == "Booted", "Owned Simulator did not boot")
    runtime_root = Path(simctl("getenv", udid, "SIMULATOR_ROOT")).resolve(strict=True)
    expected_root = (Path(receipt["runtimeBundle"]) / "Contents/Resources/RuntimeRoot").resolve(strict=True)
    require(runtime_root == expected_root, "Native Simulator root differs from the selected runtime")
    receipt.update(runtimeRoot=str(runtime_root), model=simctl("getenv", udid, "SIMULATOR_MODEL_IDENTIFIER"),
                   runtimeBefore=runtime, stateBefore=device["state"])


def cleanup_simulator(receipt):
    require(isinstance(receipt, dict) and isinstance(receipt.get("udid"), str) and UUID.fullmatch(receipt["udid"])
            and receipt.get("name") == "otzaria-pdf-" + receipt.get("campaign", ""), "Invalid owned Simulator receipt")
    devices = json.loads(simctl("list", "-j", "devices"))["devices"]
    if not any(entry.get("udid") == receipt["udid"] for entries in devices.values() for entry in entries):
        receipt.setdefault("cleanup", "alreadyAbsent")
        return
    _runtime, device = simulator_entry(receipt, devices)
    if device.get("state") != "Shutdown":
        simctl("shutdown", receipt["udid"])
    simctl("delete", receipt["udid"])
    remaining = json.loads(simctl("list", "-j", "devices"))["devices"]
    require(not any(entry.get("udid") == receipt["udid"] for entries in remaining.values() for entry in entries),
            "Owned Simulator was not deleted")
    receipt["cleanup"] = "deletedOwnedSimulator"


def run_driver(root, receipt, commit):
    environment = {**os.environ, "INSTALLED_PROBE_REPORTS": str(root / "host")}
    args = ["flutter", "drive", "--verbose", "--debug", "-d", receipt["udid"], "--no-dds", "--no-pub",
            "--keep-app-running",
            "--driver=test_driver/installed_plugin_resource_probe.dart",
            "--target=integration_test/installed_pdf_ios_probe_test.dart",
            "--dart-define=INSTALLED_PROBE_FLUTTER_VERSION=3.47.7",
            "--dart-define=INSTALLED_PROBE_COMMIT=" + commit,
            "--dart-define=INSTALLED_PDF_IOS_CAMPAIGN=" + receipt["campaign"]]
    save(root / "driver-command.json", args)
    print("Running actual iOS PDF app on", receipt["udid"], flush=True)
    with (root / "run.log").open("w", encoding="utf-8") as log:
        result = subprocess.run(args, stdout=log, stderr=subprocess.STDOUT, env=environment,
                                text=True, timeout=35 * 60, check=False)
    print("\n".join((root / "run.log").read_text(encoding="utf-8").splitlines()[-100:]), flush=True)
    return result.returncode


def collect_and_validate(root, receipt, commit, exit_code):
    products = Path("build/ios/iphonesimulator").resolve(strict=True)
    bundles = list(products.glob("*.app"))
    require(len(bundles) == 1, "Expected one built iOS Simulator app")
    built, _name, identifier = app_identity(bundles[0])
    installed = Path(simctl("get_app_container", receipt["udid"], identifier, "app")).resolve(strict=True)
    data = Path(simctl("get_app_container", receipt["udid"], identifier, "data")).resolve(strict=True)
    save(root / "app-containers.json", {"udid": receipt["udid"], "bundleIdentifier": identifier,
                                       "built": str(built), "installed": str(installed), "data": str(data)})
    runtime, device = simulator_entry(receipt, json.loads(simctl("list", "-j", "devices"))["devices"])
    receipt.update(runtimeAfter=runtime, stateAfter=device.get("state"), flutterExitCode=exit_code)
    save(root / "simulator.json", receipt)
    reports = list((root / "host").glob("run-*/report.json"))
    require(len(reports) == 1, "Expected one fresh integration-driver report")
    wrapper = json.loads(reports[0].read_text(encoding="utf-8"))
    report = wrapper.get("installedPdfIosProbe")
    require(isinstance(report, dict), "Missing PDF app report")
    output = device_output(report, data)
    shutil.copytree(output, root / "device-output")
    require(exit_code == 0, "Native iOS integration driver failed")
    return validate(wrapper, built, installed, data, receipt, commit)


def preserve_partial_output(root, receipt):
    if (root / "device-output").exists():
        return
    bundles = list(Path("build/ios/iphonesimulator").glob("*.app"))
    if len(bundles) != 1:
        return
    _built, _name, identifier = app_identity(bundles[0])
    data = Path(simctl("get_app_container", receipt["udid"], identifier, "data")).resolve(strict=True)
    candidates = list((data / "tmp").glob("otzaria-pdf-ios-*/output/installed-pdf-ios-report.json"))
    require(len(candidates) <= 8, "Unexpected number of partial PDF reports")
    for path in candidates:
        require(path.resolve(strict=True) == path and path.is_relative_to(data / "tmp"), "Partial report is a symlink")
        report = json.loads(path.read_text(encoding="utf-8"))
        if report.get("campaign") == receipt["campaign"]:
            output = device_output(report, data)
            require(path.resolve(strict=True) == output / "installed-pdf-ios-report.json", "Partial report escapes its output")
            shutil.copytree(output, root / "partial-device-output")


def run(root, commit):
    root = root.absolute()
    require(not root.exists(), "Use a fresh iOS PDF evidence directory")
    root.mkdir(parents=True)
    root = root.resolve(strict=True)
    save(root / "host.json", {"os": command(["sw_vers"]), "machine": command(["uname", "-a"]),
                              "xcode": command(["xcodebuild", "-version"]),
                              "commit": command(["git", "rev-parse", "HEAD"]),
                              "tree": command(["git", "rev-parse", "HEAD^{tree}"])})
    require(command(["git", "rev-parse", "HEAD"]) == commit, "Checkout differs from the requested source commit")
    campaign = uuid.uuid4().hex
    receipt = None
    try:
        receipt = create_simulator(campaign)
        save(root / "simulator.json", receipt)
        boot_simulator(receipt)
        save(root / "simulator.json", receipt)
        exit_code = run_driver(root, receipt, commit)
        require(exit_code == 0,
                f"Native iOS integration driver failed (exit={exit_code}); see run.log")
        result = collect_and_validate(root, receipt, commit, exit_code)
    finally:
        if receipt is not None:
            try:
                try:
                    preserve_partial_output(root, receipt)
                except (ValueError, OSError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
                    save(root / "partial-output-error.json", {"error": str(error)})
            finally:
                try:
                    cleanup_simulator(receipt)
                finally:
                    save(root / "simulator.json", receipt)
    save(root / "verified-result.json", result)
    print(json.dumps(result, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--commit")
    parser.add_argument("--cleanup", action="store_true")
    options = parser.parse_args()
    try:
        if options.cleanup:
            path = options.root / "simulator.json"
            if path.exists():
                receipt = json.loads(path.read_text(encoding="utf-8"))
                cleanup_simulator(receipt)
                save(path, receipt)
        else:
            require(isinstance(options.commit, str) and len(options.commit) == 40, "Provide the exact checkout commit")
            run(options.root, options.commit)
    except (ValueError, OSError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"IOS PDF RUNTIME INVALID: {error}", file=sys.stderr)
        if options.root.is_dir():
            save(options.root / "failure.json", {"status": "failed", "error": str(error)})
        raise SystemExit(1)
