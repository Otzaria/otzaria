#!/usr/bin/env python3
"""Collect JIT VM live-heap statistics for the isolated range snapshot probe.

Counters are VM-reported bytes, not a word-size allocation estimate. This is NOT
an allocation-throughput measurement: recent VMs expose accumulatedSize as an
alias of bytesCurrent, even after reset. Raw before/after counters are retained
for audit, but only live-heap differences are interpreted. Timings belong in the
separately compiled AOT probe. Protocol objects are included; a separate control
sample records that source of measurement noise.
"""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import urllib.parse
import urllib.request

FIELDS = ("accumulatedSize", "bytesCurrent", "instancesAccumulated", "instancesCurrent")


def totals(profile):
    result = {}
    missing = {}
    for field in FIELDS:
        values = [member.get(field, -1) for member in profile.get("members", [])]
        missing[field] = sum(value < 0 for value in values)
        result[field] = None if missing[field] else sum(values)
    return {"values": result, "unavailable_classes": missing}


def compare(before, after):
    old = {member["class"]["id"]: member for member in before.get("members", [])}
    current = {member["class"]["id"]: member for member in after.get("members", [])}
    rows = []
    for class_id in old.keys() | current.keys():
        previous = old.get(class_id)
        present = current.get(class_id)
        values = {}
        changed = False
        for field in FIELDS:
            start = previous.get(field, -1) if previous else 0
            finish = present.get(field, -1) if present else 0
            delta = finish - start if start >= 0 and finish >= 0 else None
            values[field] = {"before": start, "after": finish, "delta": delta}
            changed |= delta is None or delta != 0
        if changed:
            member = present or previous
            rows.append({"class_id": class_id, "name": member["class"].get("name"), **values})
    rows.sort(key=lambda row: (row["name"] or "", row["class_id"]))
    start = totals(before)
    finish = totals(after)
    differences = {
        field: finish["values"][field] - start["values"][field]
        if finish["values"][field] is not None and start["values"][field] is not None
        else None
        for field in FIELDS
    }
    aliases_current = all(
        member.get("accumulatedSize", -1) == member.get("bytesCurrent", -2)
        and member.get("instancesAccumulated", -1) == member.get("instancesCurrent", -2)
        for profile in (before, after)
        for member in profile.get("members", [])
    )
    return {
        "total_allocated_bytes": None,
        "total_allocation_measurement_available": False,
        "cumulative_fields_alias_current_in_both_profiles": aliases_current,
        "before_totals": start,
        "after_totals": finish,
        "delta_totals": differences,
        "members": rows,
        "before_memory_usage": before.get("memoryUsage"),
        "after_memory_usage": after.get("memoryUsage"),
        "before_date_last_gc": before.get("dateLastServiceGC"),
        "after_date_last_gc": after.get("dateLastServiceGC"),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", default=shutil.which("dart"))
    parser.add_argument("--out", type=Path, default=Path("range_allocation_profile.jsonl"))
    parser.add_argument("--sizes", nargs="+", type=int, default=[2000, 50000, 1000000])
    parser.add_argument("--windows", nargs="+", type=int, default=[1, 2, 4, 8])
    parser.add_argument("--iterations", type=int, default=20)
    parser.add_argument("--full-resident", action="store_true",
                        help="Populate all logical lines in retained-snapshot measurements; update/control measurements still seed at most 5120 lines")
    options = parser.parse_args()
    if not options.dart:
        parser.error("dart is not on PATH; pass --dart /path/to/dart")
    if any(size < 1 for size in options.sizes) or any(window < 1 for window in options.windows) or options.iterations < 1:
        parser.error("sizes, windows and iterations must be positive")
    script = Path(__file__).resolve().with_name("range_snapshot_probe.dart")
    proc = subprocess.Popen(
        [options.dart, "--disable-dart-dev", "--enable-vm-service=0", str(script), "--allocation-worker"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, bufsize=1,
    )

    def response(until):
        while True:
            line = proc.stdout.readline()
            if not line:
                raise RuntimeError("worker ended: " + proc.stderr.read())
            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                continue
            if until(data):
                return data

    try:
        ready = response(lambda data: data.get("ready"))
        service_uri = ready["service_uri"]
        if not service_uri:
            raise RuntimeError("Dart did not start its loopback VM service")

        def rpc(method, **params):
            query = urllib.parse.urlencode({
                key: str(value).lower() if isinstance(value, bool) else value
                for key, value in params.items()
            })
            with urllib.request.urlopen(service_uri + method + "?" + query, timeout=60) as result:
                data = json.load(result)
            if "error" in data:
                raise RuntimeError(data["error"])
            return data["result"]

        vm = rpc("getVM")
        isolate = next(item["id"] for item in vm["isolates"]
                       if not item.get("isSystemIsolate") and item.get("name") != "vm-service")

        def command(**values):
            proc.stdin.write(json.dumps(values) + "\n")
            proc.stdin.flush()
            return response(lambda data: data.get("done") == values["op"])

        def profile(**params):
            return rpc("getAllocationProfile", isolateId=isolate, **params)

        options.out.parent.mkdir(parents=True, exist_ok=True)
        with options.out.open("w") as out:
            def emit(data):
                out.write(json.dumps(data, ensure_ascii=False) + "\n")
                out.flush()

            emit({
                "metadata": True,
                "vm": {key: vm.get(key) for key in ["version", "targetCPU", "architectureBits", "hostCPU"]},
                "scope": "JIT VM live object heap; preallocated string references shared; excludes Flutter/layout/I/O; NOT total allocated bytes",
                "method": "getAllocationProfile(gc=true) before and after; raw per-class deltas; reset=true included only to audit cumulative-counter behavior; GC requested outside operations but VM does not guarantee collection",
                "total_allocation_measurement_available": False,
                "cumulative_counter_warning": "accumulatedSize/instancesAccumulated may alias live counters in this VM; never interpret their differences as total allocations",
                "retained_scope": "post-GC bytesCurrent difference after clear/setup; shared text strings excluded; includes control protocol objects; not process RSS or total application memory",
                "retained_full_resident": options.full_resident,
            })
            for lines in options.sizes:
                for paged in [False, True]:
                    command(op="setup", lines=lines, paged=paged, windows=1)
                    command(op="apply", iterations=40)
                    for operation in ["control", "apply"]:
                        before = profile(gc=True, reset=True)
                        command(op=operation, iterations=options.iterations)
                        after = profile(gc=True)
                        row = {
                            "measurement": "retained_after_changed_range_updates" if operation == "apply" else "protocol_control",
                            "lines": lines, "paged": paged,
                            "iterations": options.iterations if operation == "apply" else 0,
                            **compare(before, after),
                        }
                        emit(row)
                        print(json.dumps({key: row[key] for key in ["measurement", "lines", "paged", "delta_totals"]}), flush=True)
                for windows in options.windows:
                    for paged in [False, True]:
                        command(op="clear")
                        before = profile(gc=True)
                        command(op="setup", lines=lines, paged=paged, windows=windows, full_resident=options.full_resident)
                        after = profile(gc=True)
                        row = {
                            "measurement": "retained_full_snapshots" if options.full_resident else "retained_sparse_snapshots", "lines": lines,
                            "resident_lines_per_window": lines if options.full_resident else min(lines, 5120),
                            "paged": paged, "windows": windows, **compare(before, after),
                        }
                        emit(row)
                        print(json.dumps({key: row[key] for key in ["measurement", "lines", "paged", "windows", "delta_totals"]}), flush=True)
        proc.stdin.write('{"op":"exit"}\n')
        proc.stdin.flush()
        proc.wait(timeout=60)
        print("saved", options.out, flush=True)
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=10)


if __name__ == "__main__":
    main()
