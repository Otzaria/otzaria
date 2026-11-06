#!/usr/bin/env python3
"""Compare held-isolate admission; this is not a SQLite or UI benchmark."""

import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess


FIXTURE = Path("test/data_providers/db_read_admission_benchmark_test.dart")


def command(args, cwd, log):
    print(f"[{cwd.name}] {' '.join(args)}", flush=True)
    try:
        result = subprocess.run(
            args, cwd=cwd, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=600, check=False,
        )
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b""
        log.write_text(output.decode(errors="replace") if isinstance(output, bytes) else output)
        raise
    log.write_text(result.stdout)
    if result.returncode:
        print(result.stdout[-12000:], flush=True)
        raise RuntimeError(f"Command failed ({result.returncode}); see {log}")


def revision(checkout):
    return subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=checkout, text=True,
    ).strip()


def measurement(events, scenario="held_fallback_admission"):
    found = []
    for line in events.read_text().splitlines():
        event = json.loads(line)
        if event.get("type") != "print":
            continue
        for message in event.get("message", "").splitlines():
            try:
                value = json.loads(message)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict) and value.get("scenario") == scenario:
                found.append(value)
    if len(found) != 1:
        raise RuntimeError(f"Expected one {scenario} measurement in {events}")
    return found[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, type=Path)
    parser.add_argument("--head", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    base, head, out = args.base.resolve(), args.head.resolve(), args.out.resolve()
    if base == head:
        parser.error("Baseline and revised checkouts must be separate")
    out.mkdir(parents=True, exist_ok=True)
    environment = {
        "baseline": revision(base), "revised": revision(head),
        "platform": platform.platform(), "logical_cpus": os.cpu_count(),
        "measurement": "Held Dart isolates; no SQLite/FFI IO or UI frames",
        "rss_limit": "Test-process RSS/HWM includes startup/native libraries; not application memory",
        "queue_limit": "Pending futures include isolate startup before handshake",
    }
    meminfo = Path("/proc/meminfo")
    if meminfo.exists():
        environment["meminfo"] = meminfo.read_text()
    (out / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
    # Exactly the same fixture runs against each complete source checkout.
    shutil.copyfile(head / FIXTURE, base / FIXTURE)
    for label, checkout in (("baseline", base), ("revised", head)):
        command(["flutter", "pub", "get", "--enforce-lockfile"], checkout, out / f"{label}-pub.log")
        for generator in ("generate_search_index", "generate_settings_l10n"):
            command(["dart", "run", f"tool/{generator}.dart"], checkout, out / f"{label}-{generator}.log")

    results = []
    # Alternate order to expose first-run effects; counts are the safety metric.
    for label, run in (("baseline", 1), ("revised", 1), ("revised", 2), ("baseline", 2)):
        checkout = base if label == "baseline" else head
        events = out / f"{label}-{run}.events.json"
        command([
            "flutter", "test", "--no-pub", "-j", "1", "--reporter", "expanded",
            "--file-reporter", f"json:{events}",
            "--dart-define=RUN_DB_READ_ADMISSION_BENCHMARK=true",
            f"--dart-define=DB_READ_BENCHMARK_LABEL={label}", str(FIXTURE),
        ], checkout, out / f"{label}-{run}.log")
        value = measurement(events)
        if value.get("measurement") != "isolate_handshake":
            raise RuntimeError("Probe did not measure real-isolate handshakes")
        value.update(run=run, revision=environment[label])
        results.append(value)
        # Keep completed measurements if a later run or setup fails.
        (out / "samples.json").write_text(json.dumps(results, indent=2) + "\n")
        print(json.dumps(value), flush=True)

    # Baseline has no descriptor counter. Record the revised snapshot without
    # inventing a baseline estimate or presenting descriptor bytes as RSS.
    descriptor_events = out / "revised-descriptors.events.json"
    command([
        "flutter", "test", "--no-pub", "-j", "1", "--reporter", "expanded",
        "--file-reporter", f"json:{descriptor_events}",
        "--dart-define=RUN_DB_READ_ADMISSION_BENCHMARK=true",
        "--plain-name", "queue bytes reject a large backlog before the count limit",
        "test/data_providers/db_read_admission_test.dart",
    ], head, out / "revised-descriptors.log")
    descriptor = measurement(descriptor_events, "db_read_queue_descriptor_snapshot")
    (out / "queue-descriptors.json").write_text(
        json.dumps({"baseline": None, "revised": descriptor}, indent=2) + "\n"
    )

    lines = [
        "## Held-isolate admission comparison", "",
        "Real Dart isolates wait on a release port. No SQLite/FFI IO or UI frames are measured.",
        "Queue counts include startup before a ready handshake. RSS/HWM includes test-process startup and native libraries.", "",
        "| Revision | Run | Max live while held | Peak pending futures | Rejected | Recovered |",
        "| --- | ---: | ---: | ---: | ---: | --- |",
    ]
    for value in results:
        queued = max(sample["queuedFutures"] for sample in value["samples"])
        live_held = max(sample["live"] for sample in value["samples"])
        lines.append(
            f"| {value['label']} `{value['revision'][:12]}` | {value['run']} | "
            f"{live_held} | {queued} | {value['rejected']} | {value['recovered']} |"
        )
    lines.extend([
        "", "### Revised descriptor admission snapshot", "",
        f"{descriptor['queuedReads']} queued read(s), {descriptor['estimatedQueuedBytes']} "
        f"estimated descriptor bytes of a {descriptor['limitBytes']}-byte test budget; "
        f"{descriptor['activeFallbackReads']} active fallback reads.",
        "The baseline has no descriptor counter (null). This snapshot is not result-buffer or process memory.",
    ])
    summary = "\n".join(lines) + "\n"
    (out / "summary.md").write_text(summary)
    if summary_path := os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(summary_path).open("a") as stream:
            stream.write(summary)


if __name__ == "__main__":
    main()
