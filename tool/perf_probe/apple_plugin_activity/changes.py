#!/usr/bin/env python3
"""Decide which Apple plugin activity jobs a pull request needs."""
from __future__ import annotations

import argparse
import fnmatch
import os
from pathlib import Path
import re
import subprocess

WORKFLOW = ".github/workflows/apple-plugin-activity.yml"
PUBSPEC_FILES = {"pubspec.yaml", "pubspec.lock"}

# Native or harness code the actual-app scenario runs on Apple: the WebView hosts,
# window transitions, startup crash SDK, SwiftPM binary targets, plugin boot and
# registry, and the iOS VM service connection.
SCENARIO_PACKAGES = (
    "flutter_inappwebview*",
    "window_manager*",
    "screen_retriever*",
    "sentry*",
    "pdfrx*",
    "pdfium*",
    "package_info_plus*",
    "sqlite3",
    "vm_service",
)

# Checked by the Ubuntu contracts job; the Mac jobs add nothing for these.
CONTRACTS_ONLY = (
    "test/**",
    "tool/perf_probe/test_ios_simulator_driver.py",
    "tool/perf_probe/apple_plugin_activity/README.md",
    "tool/perf_probe/apple_plugin_activity/changes.py",
    "tool/perf_probe/apple_plugin_activity/test_changes.py",
    "tool/perf_probe/apple_plugin_activity/test_fixture.mjs",
    "tool/perf_probe/apple_plugin_activity/test_runner.py",
    "tool/perf_probe/apple_plugin_activity/test_swiftpm_retry.py",
    # The scenario uses only its report finalizer, covered by the completion tests.
    "integration_test/support/installed_plugin_completion.dart",
)


def glob_matches(pattern, path):
    """GitHub path filter semantics: `**` crosses directories, `*` does not."""
    expression = ""
    index = 0
    while index < len(pattern):
        if pattern.startswith("**", index):
            expression += ".*"
            index += 2
        elif pattern[index] == "*":
            expression += "[^/]*"
            index += 1
        elif pattern[index] == "?":
            expression += "[^/]"
            index += 1
        else:
            expression += re.escape(pattern[index])
            index += 1
    return re.fullmatch(expression, path) is not None


def trigger_paths(workflow_text):
    """The `paths` list under `on.pull_request` of the workflow."""
    paths, inside = [], False
    for line in workflow_text.splitlines():
        stripped = line.strip()
        if stripped == "paths:":
            inside = True
            continue
        if inside and not stripped.startswith("#"):
            match = re.fullmatch(r"-\s*['\"]?([^'\"]+)['\"]?", stripped)
            if match is None:
                break
            paths.append(match.group(1))
    if not paths:
        raise ValueError("The workflow has no pull_request paths filter")
    return paths


def lock_packages(text):
    """Map each locked package to its resolved description, source and version."""
    packages, name, section = {}, None, None
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        if indent == 0:
            section, name = line.strip(), None
        elif section == "packages:" and indent == 2:
            name = line.strip().rstrip(":")
            packages[name] = []
        elif section == "packages:" and name is not None and not line.strip().startswith("dependency:"):
            packages[name].append(line.strip())
    return {key: "\n".join(value) for key, value in packages.items()}


def top_level_block(text, key):
    lines, inside = [], False
    for line in text.splitlines():
        if line and not line[0].isspace() and not line.startswith("#"):
            inside = line.split(":", 1)[0] == key
        if inside:
            lines.append(line)
    return "\n".join(lines)


def changed_packages(base_lock, head_lock):
    base, head = lock_packages(base_lock), lock_packages(head_lock)
    return {name for name in base.keys() | head.keys() if base.get(name) != head.get(name)}


def scenario_packages(names):
    return sorted(name for name in names
                  if any(fnmatch.fnmatchcase(name, pattern) for pattern in SCENARIO_PACKAGES))


def decide(changed_files, workflow_text, read_base, read_head):
    """Return (contracts, apple, reasons) for one pull request diff."""
    triggers = trigger_paths(workflow_text)
    reasons = []
    contracts = apple = False
    for path in sorted(changed_files):
        if path in PUBSPEC_FILES or not any(glob_matches(p, path) for p in triggers):
            continue
        contracts = True
        if not any(glob_matches(p, path) for p in CONTRACTS_ONLY):
            apple = True
            reasons.append(f"probe or app file: {path}")
    if changed_files & PUBSPEC_FILES:
        packages = scenario_packages(changed_packages(read_base("pubspec.lock"), read_head("pubspec.lock")))
        if packages:
            reasons.append("scenario packages: " + ", ".join(packages))
        hooks = (top_level_block(read_base("pubspec.yaml"), "hooks")
                 != top_level_block(read_head("pubspec.yaml"), "hooks"))
        if hooks:
            reasons.append("native build hook settings in pubspec.yaml")
        if packages or hooks:
            contracts = apple = True
    return contracts, apple, reasons


def git(*args):
    return subprocess.run(["git", *args], check=True, text=True, capture_output=True).stdout


def git_file(revision, path):
    result = subprocess.run(["git", "show", f"{revision}:{path}"], text=True, capture_output=True)
    return result.stdout if result.returncode == 0 else ""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)
    args = parser.parse_args()
    files = set(git("diff", "--name-only", args.base, args.head).split())
    contracts, apple, reasons = decide(
        files, Path(WORKFLOW).read_text(),
        lambda path: git_file(args.base, path), lambda path: git_file(args.head, path))
    for reason in reasons or ["no change the Apple scenario depends on"]:
        print(reason)
    print(f"contracts={str(contracts).lower()} apple={str(apple).lower()}")
    if "GITHUB_OUTPUT" in os.environ:
        with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
            stream.write(f"contracts={str(contracts).lower()}\napple={str(apple).lower()}\n")


if __name__ == "__main__":
    main()
