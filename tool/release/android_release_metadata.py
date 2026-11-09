#!/usr/bin/env python3
"""Describe a verified APK using Android SDK tools and its actual bytes."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


APPLICATION_ID = "org.otzaria.otzaria"
INSTALL_PERMISSION = "android.permission.REQUEST_INSTALL_PACKAGES"
SHA256 = re.compile(r"[0-9a-f]{64}")
APK_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+-]*\.apk")


class MetadataError(ValueError):
    pass


def _one_line(text: str, prefix: str) -> str:
    lines = [line for line in text.splitlines() if line.startswith(prefix)]
    if len(lines) != 1:
        raise MetadataError(f"Expected one {prefix!r} record from aapt")
    return lines[0][len(prefix):]


def _sdk_level(text: str, prefix: str) -> int:
    value = _one_line(text, prefix).strip()
    if not re.fullmatch(r"'[0-9]+'", value):
        raise MetadataError(f"{prefix} must be a released numeric SDK level")
    return int(value[1:-1])


def parse_badging(text: str) -> dict:
    package = _one_line(text, "package: ")
    fields = dict(re.findall(r"(\w+)='([^']*)'", package))
    if fields.get("name") != APPLICATION_ID:
        raise MetadataError("The APK belongs to a different application")
    version_code = fields.get("versionCode", "")
    if not version_code.isascii() or not version_code.isdecimal():
        raise MetadataError("Missing or invalid Android versionCode")
    if fields.get("versionCodeMajor", "0") != "0":
        raise MetadataError("versionCodeMajor is not supported by schema 1")
    abis = re.findall(r"'([A-Za-z0-9_-]+)'", _one_line(text, "native-code:"))
    return {
        "applicationId": fields["name"],
        "versionCode": int(version_code),
        "versionName": fields.get("versionName", ""),
        "minSdk": _sdk_level(text, "sdkVersion:"),
        "targetSdk": _sdk_level(text, "targetSdkVersion:"),
        "abis": sorted(set(abis)),
    }


def parse_signers(text: str) -> list[str]:
    # Public-key and source-stamp digests are not application signing identities.
    values = re.findall(
        r"^Signer #[1-9][0-9]* certificate SHA-256 digest: ([0-9a-fA-F]{64})\s*$",
        text,
        flags=re.MULTILINE,
    )
    if not values:
        raise MetadataError("apksigner returned no signing certificate SHA-256")
    return sorted({value.lower() for value in values})


def verify_distribution(badging: str, distribution: str, allow_debug: bool) -> None:
    permissions = set(re.findall(
        r"^uses-permission(?:-sdk-[0-9]+)?: name='([^']+)'",
        badging,
        flags=re.MULTILINE,
    ))
    if (INSTALL_PERMISSION in permissions) != (distribution == "direct"):
        raise MetadataError(f"Unexpected install permission for {distribution} APK")
    if not allow_debug and re.search(r"^application-debuggable(?:\s|$)", badging, re.MULTILINE):
        raise MetadataError("A debuggable APK cannot be published as a release")


def validate_metadata(metadata: object) -> None:
    if not isinstance(metadata, dict) or type(metadata.get("schemaVersion")) is not int:
        raise MetadataError("Invalid Android metadata schema")
    if metadata["schemaVersion"] != 1 or metadata.get("applicationId") != APPLICATION_ID:
        raise MetadataError("Unknown schema or application")
    for field in ("versionCode", "minSdk", "targetSdk"):
        if type(metadata.get(field)) is not int or not 0 < metadata[field] <= 2147483647:
            raise MetadataError(f"Invalid {field}")
    if metadata["minSdk"] > metadata["targetSdk"]:
        raise MetadataError("minSdk exceeds targetSdk")
    version = metadata.get("versionName")
    if not isinstance(version, str) or not version.strip() or len(version) > 256:
        raise MetadataError("Invalid versionName")
    abis = metadata.get("abis")
    if (not isinstance(abis, list) or not abis
            or any(not isinstance(abi, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", abi) for abi in abis)
            or len(set(abis)) != len(abis)):
        raise MetadataError("Invalid APK ABI list")
    apk = metadata.get("apk")
    if not isinstance(apk, dict) or not isinstance(apk.get("name"), str) or not APK_NAME.fullmatch(apk["name"]):
        raise MetadataError("Invalid APK filename")
    if type(apk.get("size")) is not int or apk["size"] <= 0:
        raise MetadataError("Invalid APK size")
    if not isinstance(apk.get("sha256"), str) or not SHA256.fullmatch(apk["sha256"]):
        raise MetadataError("Invalid APK SHA-256")
    signers = metadata.get("signingCertificateSha256")
    if (not isinstance(signers, list) or not signers
            or any(not isinstance(value, str) or not SHA256.fullmatch(value) for value in signers)
            or len(set(signers)) != len(signers)):
        raise MetadataError("Invalid signing certificate list")


def _run(tool: Path, *args: str) -> str:
    result = subprocess.run([str(tool), *args], capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise MetadataError(f"{tool.name} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout


def describe_apk(apk: Path, build_tools: Path, distribution: str, *, allow_debug: bool = False) -> dict:
    before = apk.stat()
    signers = parse_signers(_run(build_tools / "apksigner", "verify", "--verbose", "--print-certs", str(apk)))
    badging = _run(build_tools / "aapt", "dump", "badging", str(apk))
    verify_distribution(badging, distribution, allow_debug)
    properties = parse_badging(badging)
    digest = hashlib.sha256()
    with apk.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    after = apk.stat()
    if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
            after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
        raise MetadataError("The APK changed while its metadata was being generated")
    metadata = {
        "schemaVersion": 1,
        **properties,
        "apk": {"name": apk.name, "size": after.st_size, "sha256": digest.hexdigest()},
        "signingCertificateSha256": signers,
    }
    validate_metadata(metadata)
    return metadata


def write_metadata(output: Path, metadata: dict) -> None:
    validate_metadata(metadata)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=output.parent, delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(metadata, stream, ensure_ascii=False, sort_keys=True, indent=2)
            stream.write("\n")
        os.replace(temporary, output)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--build-tools", required=True, type=Path)
    parser.add_argument("--distribution", required=True, choices=("direct", "play"))
    parser.add_argument("--allow-debug", action="store_true", help="Only for CI validation of debug builds")
    args = parser.parse_args()
    if args.apk.resolve() == args.output.resolve():
        parser.error("Metadata output must not overwrite the APK")
    try:
        metadata = describe_apk(args.apk, args.build_tools, args.distribution, allow_debug=args.allow_debug)
        write_metadata(args.output, metadata)
    except (OSError, MetadataError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f"Android metadata: {error}\n")
    print(f"Verified {metadata['apk']['name']} (Android versionCode {metadata['versionCode']})")


if __name__ == "__main__":
    main()
