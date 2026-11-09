#!/usr/bin/env python3
"""Validate hosted package identity in a Dart pubspec.lock without dependencies.

This checks only the deterministic package-block shape emitted by Dart pub.
It is not a general YAML parser and does not replace flutter pub get.
Non-hosted packages (git/path/sdk) are deliberately outside its scope.
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path


# Match pub_semver, including the leading zeros Dart pub preserves in lockfiles.
_VERSION = re.compile(
    r"[0-9]+\.[0-9]+\.[0-9]+"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)


def validate_hosted_names(content: str) -> list[str]:
    errors: list[str] = []
    in_packages = False
    saw_packages = False
    block: list[str] = []
    package = ""
    line_number = 0

    def check_block() -> None:
        if not package:
            return
        source = None
        name = None
        version = None
        in_description = False
        for line in block:
            if line.startswith("    ") and not line.startswith("     "):
                # Only an immediate child of the package can open a description.
                in_description = line == "    description:"
                if line.startswith("    source: "):
                    source = line[len("    source: ") :].strip().strip('"')
                elif line.startswith("    version: "):
                    version = line[len("    version: ") :].strip().strip('"')
            elif in_description and line.startswith("      name: "):
                name = line[len("      name: ") :].strip().strip('"')
        if source == "hosted":
            if name != package:
                errors.append(
                    f"pubspec.lock:{line_number}: hosted package {package!r} "
                    f"has description.name {name!r}"
                )
            if not version:
                errors.append(
                    f"pubspec.lock:{line_number}: hosted package {package!r} "
                    "has no version"
                )
            elif _VERSION.fullmatch(version) is None:
                errors.append(
                    f"pubspec.lock:{line_number}: hosted package {package!r} "
                    f"has invalid version {version!r}"
                )

    for number, raw in enumerate(content.splitlines(), 1):
        if raw == "packages:":
            if saw_packages:
                errors.append(f"pubspec.lock:{number}: duplicate packages section")
            in_packages = True
            saw_packages = True
            continue
        if not in_packages:
            continue
        # Top-level keys end the package map; no other pubspec sections
        # should be accidentally interpreted as package entries.
        if raw and not raw.startswith((" ", "#")):
            check_block()
            in_packages = False
            package = ""
            block = []
            continue
        if raw.startswith("  ") and not raw.startswith("    ") and raw.endswith(":"):
            check_block()
            package = raw[2:-1].strip()
            line_number = number
            block = []
            if not package:
                errors.append(f"pubspec.lock:{number}: empty package key")
        else:
            block.append(raw)
    if in_packages:
        check_block()

    if not saw_packages:
        errors.append("pubspec.lock: missing packages: section")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lockfile", type=Path)
    args = parser.parse_args()
    errors = validate_hosted_names(args.lockfile.read_text(encoding="utf-8"))
    for error in errors:
        print(f"::error::{error}")
    if errors:
        return 1
    print("Hosted package identity metadata is consistent.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
