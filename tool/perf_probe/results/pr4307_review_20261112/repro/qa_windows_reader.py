#!/usr/bin/env python3
"""Independent, read-only QA of a complete reader-profile artifact directory.

Uses only Python's standard library and optional read-only git commands. Outputs
JSON, retains every recorded observation, and never executes artifact content.
The expected candidate must be supplied explicitly; no old run is a substitute.
"""
import argparse
import collections
import csv
import datetime as dt
import gzip
import hashlib
import io
import json
import math
from pathlib import Path
import re
import statistics
import subprocess
import sys

BASELINE = "8d24d26f6b7eef04ad9eda1f30eb9ea0e53cf546"
SIDES = ("baseline", "candidate")
ACTIONS = ("open", "scroll", "jump_forward", "jump_backward",
           "warmup_complete", "steady_scroll", "close")
KINDS = ("short", "medium", "long")
SCENARIOS = tuple(f"book.{k}.{a}" for k in KINDS for a in ACTIONS)
HARNESS = (
    "integration_test/perf_resource_probe_test.dart",
    "integration_test/support/perf_fixture.dart",
    "integration_test/support/perf_recorder.dart",
    "integration_test/support/perf_reader_probe.dart",
    "integration_test/support/perf_reader_scroll.dart",
    "test/helpers/seforim_fixture_db.dart",
    "tool/perf_probe/analyze.dart", "tool/perf_probe/src/report.dart",
    "tool/perf_probe/lockfile_quoting.ps1", "tool/perf_probe/runner.ps1",
    "tool/perf_probe/run_perf_probe.ps1", "tool/perf_probe/sample_resources.ps1",
    "tool/perf_probe/run_reader_comparison.ps1",
)
COMPARABLE = ("protocolVersion", "fixtureId", "buildMode", "cacheState",
              "hardwareId", "os", "flutterVersion", "warmup", "repetitions",
              "launchCount", "viewport", "settings", "sampling")
SAME_BUILD = ("commit", "binarySha256", "buildMode", "hardwareId", "os",
              "flutterVersion", "warmup", "repetitions", "sampling",
              "machine", "bundleHashes")
FRAME_KEYS = ("buildMs", "rasterMs", "totalMs")


def number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def equivalent(a, b):
    if number(a) and number(b):
        return math.isclose(a, b, rel_tol=1e-9, abs_tol=1e-7)
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(equivalent(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(equivalent(x, y) for x, y in zip(a, b))
    return type(a) is type(b) and a == b


def distribution(values):
    values = list(values)
    if not values:
        return None
    if any(not number(v) for v in values):
        raise ValueError("Nonfinite or nonnumeric observation")
    s = sorted(values)
    return {"count": len(s), "min": s[0], "mean": sum(s) / len(s),
            "p50": s[math.ceil(.50 * len(s)) - 1],
            "p95": s[math.ceil(.95 * len(s)) - 1],
            "p99": s[math.ceil(.99 * len(s)) - 1], "max": s[-1]}


def ratio(a, b):
    return b / a if number(a) and number(b) and a != 0 else None


def difference(a, b):
    available = number(a) and number(b)
    return {"baseline": a, "candidate": b, "available": available,
            "delta": b - a if available else None,
            "deltaPercent": (b - a) / a * 100 if available and a else None}


def at(value, path):
    for key in path.split("."):
        value = value.get(key) if isinstance(value, dict) else None
    return value


def phase_key(row):
    return (row.get("launchIndex"), row.get("name"), row.get("warmup"), row.get("iteration"))


def pipeline_from_trace(trace, reader_id, start, end):
    """Recompute complete LAYOUT/PAINT intervals and union each thread.

    Boundary-crossing and incomplete calls are not silently interpreted as zero.
    This independently parses Chrome trace B/E/X events; no Dart report is used.
    """
    events = [e for e in trace.get("traceEvents", []) if isinstance(e, dict)]
    markers = {name: sum(e.get("name") == name and
                        (e.get("args") or {}).get("id") == reader_id for e in events)
               for name in ("reader.phase.begin", "reader.phase.end")}
    if not all(markers.values()):
        return {"unavailableReason": "Missing phase markers; the timeline may be truncated."}, markers
    stacks = collections.defaultdict(list)
    spans = {"layout": collections.defaultdict(list), "paint": collections.defaultdict(list)}

    def add(event, finish):
        begin, name = event.get("ts"), event.get("name")
        if not number(begin) or not isinstance(name, str) or not start <= begin <= finish <= end:
            return
        kind = next((k for k in spans if name == k.upper() or name.startswith(k.upper() + " (")), None)
        if kind:
            spans[kind][f'{event.get("pid")}:{event.get("tid")}'].append((begin, finish))

    for _, event in sorted(enumerate(events), key=lambda x: (x[1].get("ts") or 0, x[0])):
        time = event.get("ts")
        if not number(time):
            continue
        thread = (event.get("pid"), event.get("tid"))
        if event.get("ph") == "B":
            stacks[thread].append(event)
        elif event.get("ph") == "E" and stacks[thread]:
            add(stacks[thread].pop(), time)
        elif event.get("ph") == "X" and number(event.get("dur")):
            add(event, time + event["dur"])
    for stack in stacks.values():
        if any(number(e.get("ts")) and start <= e["ts"] <= end and
               isinstance(e.get("name"), str) and e["name"].startswith(("LAYOUT", "PAINT")) for e in stack):
            return {"unavailableReason": "An incomplete layout/paint interval remains in the trace."}, markers
    result = {}
    for kind, threads in spans.items():
        merged = []
        for thread, intervals in threads.items():
            union = []
            for begin, finish in sorted(intervals):
                if not union or begin > union[-1][1]:
                    union.append([begin, finish])
                else:
                    union[-1][1] = max(union[-1][1], finish)
            merged.extend({"thread": thread, "startUs": a, "endUs": b} for a, b in union)
        result[kind + "IntervalsUs"] = merged
        result[kind + "TotalMs"] = sum(x["endUs"] - x["startUs"] for x in merged) / 1000 if merged else None
    result["unavailableReason"] = ("No complete layout/paint calls inside the action window."
                                    if not any(spans.values()) else None)
    return result, markers


class Audit:
    def __init__(self, args):
        self.args, self.root = args, Path(args.artifact_root).resolve()
        self.errors, self.warnings, self.hashes = [], [], {}
        self.plan = []
        indices = dict.fromkeys(SIDES, 0)
        for cycle in range(args.cycles):
            for side in ("baseline", "candidate", "candidate", "baseline"):
                self.plan.append({"side": side, "launchIndex": indices[side], "cycle": cycle})
                indices[side] += 1
        self.launch_count = args.cycles * 2
        self.records, self.manifests, self.reports = {}, {}, {}
        self.timeline, self.launches, self.metrics = {}, [], {}

    def check(self, ok, code, **detail):
        if not ok:
            self.errors.append({"code": code, **detail})
        return bool(ok)

    def warn(self, code, **detail):
        self.warnings.append({"code": code, **detail})

    def path(self, relative):
        relative = str(relative).replace("\\", "/")
        p = (self.root / relative).resolve()
        if not p.is_relative_to(self.root):
            raise ValueError("Artifact path escapes supplied root")
        return p

    def text(self, relative, optional=False):
        p = self.path(relative)
        if not p.is_file() and self.path(str(relative) + ".gz").is_file():
            p = self.path(str(relative) + ".gz")
        if not p.is_file():
            if not optional:
                self.check(False, "missing_file", path=str(relative))
            return None
        raw = p.read_bytes()
        self.hashes[p.relative_to(self.root).as_posix()] = hashlib.sha256(raw).hexdigest()
        return (gzip.decompress(raw) if p.suffix == ".gz" else raw).decode("utf-8-sig")

    def json(self, relative, optional=False):
        raw = self.text(relative, optional)
        if raw is None:
            return {}
        try:
            value = json.loads(raw)
            if not isinstance(value, dict):
                raise ValueError("Expected JSON object")
            return value
        except (ValueError, TypeError) as error:
            self.check(False, "invalid_json", path=str(relative), error=str(error))
            return {}

    def jsonl(self, relative, optional=False):
        raw = self.text(relative, optional)
        result = []
        for line_index, line in enumerate((raw or "").splitlines(), 1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
                if not isinstance(row, dict):
                    raise ValueError("Expected object")
                result.append(row)
            except (ValueError, TypeError) as error:
                self.check(False, "invalid_jsonl", path=str(relative), line=line_index, error=str(error))
        return result

    def csv(self, relative):
        raw = self.text(relative)
        if raw is None:
            return []
        reader = csv.DictReader(io.StringIO(raw))
        self.check(reader.fieldnames is not None and len(reader.fieldnames) == len(set(reader.fieldnames)),
                   "csv_header", path=str(relative))
        return list(reader)

    def same(self, a, b, code, **detail):
        def compact(value):
            encoded = json.dumps(value, sort_keys=True, ensure_ascii=False, default=str)
            if len(encoded) <= 1500:
                return value
            return {"summary_only": True, "type": type(value).__name__,
                    "count": len(value) if isinstance(value, (dict, list, str)) else None,
                    "canonical_sha256": hashlib.sha256(encoded.encode()).hexdigest()}
        ok = equivalent(a, b)
        if not ok:
            self.check(False, code, expected=compact(b), observed=compact(a), **detail)
        return ok

    def metadata(self, manifest, records, label):
        meta = dict(manifest)
        for row in records:
            if row.get("type") != "meta":
                continue
            for key in COMPARABLE + ("schemaVersion",):
                if row.get(key) is not None:
                    if meta.get(key) is not None:
                        self.same(row[key], meta[key], "metadata_conflict", label=label, key=key)
                    else:
                        meta[key] = row[key]
        return meta

    def provenance(self):
        p = self.json("provenance.json")
        self.prov = p
        for key, expected in {"baselineSourceCommit": self.args.expected_baseline,
                              "candidateSourceCommit": self.args.expected_candidate,
                              "candidateMeasuredCommit": self.args.expected_candidate,
                              "harnessSourceCommit": self.args.expected_candidate,
                              "cycles": self.args.cycles, "bookLines": self.args.book_lines,
                              "status": "passed", "launchOrder": self.plan}.items():
            self.same(p.get(key), expected, "provenance", key=key)
        self.check(bool(re.fullmatch(r"[0-9a-f]{40}", str(p.get("baselineMeasuredCommit")))), "baseline_overlay_sha")
        entries = p.get("harnessEntries", [])
        parsed = [re.fullmatch(r"100(?:644|755) blob [0-9a-f]{40}\t(.+)", e) for e in entries if isinstance(e, str)]
        self.check(len(parsed) == 13 and all(parsed) and sorted(m.group(1) for m in parsed if m) == sorted(HARNESS),
                   "harness_whitelist")
        digest = hashlib.sha256(("\n".join(entries) + "\n").encode()).hexdigest()
        self.same(digest, p.get("harnessSha256"), "harness_digest")
        if self.args.repo:
            try:
                actual = subprocess.check_output(["git", "-C", self.args.repo, "ls-tree",
                                                  self.args.expected_candidate, "--", *HARNESS],
                                                 text=True, stderr=subprocess.PIPE).splitlines()
                self.same(entries, sorted(actual), "harness_vs_candidate_git_objects")
                merge_base = subprocess.check_output(["git", "-C", self.args.repo, "merge-base",
                                                       self.args.expected_baseline, self.args.expected_candidate],
                                                      text=True, stderr=subprocess.PIPE).strip()
                self.same(merge_base, self.args.expected_baseline, "candidate_does_not_include_expected_base")
            except subprocess.CalledProcessError as e:
                self.check(False, "candidate_git_objects_unavailable", error=e.stderr)
        else:
            self.warn("source_git_identity_not_checked", reason="Supply --repo for independent candidate harness blob verification.")

    def heap(self, snap, label):
        if snap is None:
            return
        groups = snap.get("isolateGroups", [])
        ids = [g.get("id") for g in groups]
        isolates = [i for g in groups for i in g.get("isolateIds", [])]
        self.check(bool(groups) and len(ids) == len(set(ids)) and len(isolates) == len(set(isolates)),
                   "heap_duplicate_or_missing_groups", label=label)
        for key in ("heapUsage", "heapCapacity", "externalUsage"):
            values = [g.get(key) for g in groups]
            self.check(all(number(v) and v >= 0 for v in values), "heap_invalid_value", label=label, key=key)
            if all(number(v) for v in values):
                self.same(snap.get(key), sum(values), "heap_aggregation", label=label, key=key)
        for key, expected in {"isolateCount": len(isolates), "isolateGroupCount": len(groups),
                              "aggregation": "unique-application-isolate-groups",
                              "measurement": "current-usage-without-forced-gc"}.items():
            self.same(snap.get(key), expected, "heap_schema", label=label, key=key)

    def launch(self, side, mapping, build):
        index = mapping.get("launchIndex")
        directory = str(mapping.get("launchDirectory", "")).replace("\\", "/")
        step = str(mapping.get("stepDirectory", "")).replace("\\", "/")
        label = f"{side}:{index}"
        step_meta = self.json(f"{step}/manifest.json")
        identity = self.json(f"{directory}/launch.json")
        completion = self.json(f"{directory}/completion.json")
        sampler = self.json(f"{directory}/samples.csv.status.json")
        records = self.jsonl(f"{directory}/phases.jsonl")
        csv_rows = self.csv(f"{directory}/samples.csv")
        self.same(self.jsonl(f"{step}/phases.jsonl"), records, "step_journal_not_exact", label=label)
        self.same(self.csv(f"{step}/samples.csv"), csv_rows, "step_csv_not_exact", label=label)
        for key in SAME_BUILD:
            self.same(step_meta.get(key), build.get(key), "build_identity_changed", label=label, key=key)
        for key, expected in {"status": "passed", "dirty": False, "launchCount": 1,
                              "launchIndexOffset": index, "cacheState": "cold"}.items():
            self.same(step_meta.get(key), expected, "launch_manifest", label=label, key=key)
        self.same(identity.get("launchIndex"), index, "launch_identity_index", label=label)
        for key, expected in {"status": "passed", "preparationOnly": False, "testFailures": []}.items():
            self.same(completion.get(key), expected, "completion", label=label, key=key)
        for key, expected in {"complete": True, "errors": 0, "launchIndex": index,
                              "samples": len(csv_rows), "reason": "stopped"}.items():
            self.same(sampler.get(key), expected, "sampler_status", label=label, key=key)
        for error_file in (f"{directory}/samples.csv.errors.jsonl", f"{step}/samples.csv.errors.jsonl"):
            self.check(not self.jsonl(error_file, optional=True), "sampler_errors", path=error_file)
        self.check(bool(csv_rows), "no_external_samples", label=label)
        previous, seen = None, set()
        saw_root = False
        for row in csv_rows:
            try:
                current = (int(row["epoch_ms"]), float(row["monotonic_ms"]))
                key = (current[0], row["pid"], row["identity_start_ticks"])
                valid = (int(row["launch_index"]) == index and int(row["root_pid"]) == identity.get("pid")
                         and (previous is None or (current[0] >= previous[0] and current[1] >= previous[1]))
                         and key not in seen)
                self.check(valid, "csv_identity_or_order", label=label, key=key)
                saw_root |= int(row["pid"]) == identity.get("pid") and row["identity_start_ticks"] == identity.get("identityStartTicks")
                previous = current
                seen.add(key)
            except (KeyError, TypeError, ValueError) as error:
                self.check(False, "invalid_csv_record", label=label, error=str(error))
        self.check(saw_root, "root_process_not_sampled", label=label)
        self.check(all(r.get("launchIndex") == index for r in records), "journal_launch_index", label=label)
        done = [r for r in records if r.get("type") == "done"]
        meta = [r for r in records if r.get("type") == "meta"]
        self.check(len(done) == 1 and done[0].get("status") == "passed", "done_record", label=label)
        process_meta = [r for r in meta if "pid" in r]
        self.check(len(process_meta) == 1, "process_meta_count", label=label)
        if process_meta:
            m = process_meta[0]
            for key, expected in {"pid": identity.get("pid"), "preparationOnly": False, "readerOnly": True,
                                  "schemaVersion": 2, "protocolVersion": 2,
                                  "warmup": self.args.warmup, "repetitions": self.args.repetitions}.items():
                self.same(m.get(key), expected, "process_meta", label=label, key=key)
            self.same(sorted(m.get("fixtureBooks", {}).values()), sorted(map(int, self.args.book_lines.split(","))),
                      "book_sizes", label=label)
            self.same(completion.get("fixtureId"), m.get("fixtureId"), "completion_fixture", label=label)
        phases = [r for r in records if r.get("type") == "phase"]
        readers = [r for r in records if r.get("type") == "reader_phase"]
        reads = [r for r in records if r.get("type") == "reader_repository_read"]
        keys = [phase_key(p) for p in phases]
        self.check(len(keys) == len(set(keys)), "duplicate_phase", label=label)
        reader_keys = [phase_key(r) for r in readers]
        self.check(len(reader_keys) == len(set(reader_keys)), "duplicate_reader_phase", label=label)
        self.check(len({r.get("id") for r in readers}) == len(readers), "duplicate_reader_id", label=label)
        self.check(len({r.get("requestId") for r in reads}) == len(reads), "duplicate_request_id", label=label)
        self.check(all(r.get("status") == "passed" for r in reads), "failed_content_request", label=label)
        phase_map = {phase_key(p): p for p in phases}
        reader_map = {phase_key(r): r for r in readers}
        for name in SCENARIOS:
            expected = {(index, name, w, i) for w, count in ((True, self.args.warmup), (False, self.args.repetitions)) for i in range(count)}
            self.check({k for k in keys if k[1] == name} == expected, "scenario_repetition_layout", label=label, scenario=name)
            self.check({k for k in reader_keys if k[1] == name} == expected, "reader_repetition_layout", label=label, scenario=name)
        for p in phases:
            name, key = p.get("name"), phase_key(p)
            where = f"{label}:{name}:{p.get('warmup')}:{p.get('iteration')}"
            self.check(p.get("status") == "passed", "phase_not_passed", label=where, status=p.get("status"))
            self.check(number(p.get("durationMs")) and p["durationMs"] >= 0, "invalid_duration", label=where)
            if all(number(p.get(k)) for k in ("startMs", "endMs", "durationMs")):
                self.check(p["endMs"] >= p["startMs"] and abs(p["endMs"] - p["startMs"] - p["durationMs"]) <= 51.001,
                           "phase_wallclock_drift", label=where)
            f = p.get("frames") or {}
            if name in SCENARIOS:
                self.same(f.get("attribution"), "build-start-wall-time", "frame_attribution", label=where)
                self.check(f.get("truncated") is False and f.get("droppedFrames") == 0, "frame_truncation", label=where)
                for frame in FRAME_KEYS:
                    values = f.get(frame, [])
                    self.check(isinstance(values, list) and len(values) == f.get("count") and
                               all(number(v) and v >= 0 for v in values), "frame_array", label=where, metric=frame)
                if name.endswith((".scroll", ".steady_scroll")):
                    self.check(number(f.get("count")) and f["count"] > 0, "empty_scroll_frame_sample", label=where)
            for point in ("Before", "After"):
                self.heap(p.get("heap" + point), where + ":" + point)
        for r in readers:
            key, name = phase_key(r), r.get("name")
            self.check(key in phase_map, "orphan_reader_phase", label=label, phase=list(key))
            start, end = r.get("startTimelineUs"), r.get("endTimelineUs")
            self.check(number(start) and number(end) and end >= start, "reader_timeline_bounds", label=label, phase=list(key))
            if name and name.endswith(".steady_scroll"):
                before, after = r.get("before") or {}, r.get("after") or {}
                expected_lines = dict(zip(KINDS, map(int, self.args.book_lines.split(",")))).get(name.split(".")[1])
                self.same(before.get("lines"), expected_lines, "steady_scroll_line_count_before", label=label)
                self.same(after.get("lines"), expected_lines, "steady_scroll_line_count_after", label=label)
                self.check(before.get("pendingReads") == after.get("pendingReads") == 0 and
                           number(before.get("requestsStarted")) and before.get("requestsStarted") == after.get("requestsStarted"),
                           "steady_scroll_io_counters", label=label, phase=list(key))
                overlaps = [q.get("requestId") for q in reads if
                            (q.get("phase") or {}).get("id") == r.get("id") or
                            (all(number(v) for v in (q.get("startTimelineUs"), q.get("endTimelineUs"), start, end)) and
                             q["startTimelineUs"] < end and q["endTimelineUs"] > start)]
                self.check(not overlaps, "steady_scroll_content_reads", label=label, phase=list(key), requests=overlaps)
                self.same(at(phase_map.get(key, {}), "details.fullyLoaded"), True, "steady_scroll_not_ready", label=label)
            filename = r.get("timelineFile")
            info = {"captured": bool(filename), "pipeline_available": (r.get("pipeline") or {}).get("unavailableReason") is None and bool(r.get("pipeline")),
                    "layout_available": number(at(r, "pipeline.layoutTotalMs")),
                    "paint_available": number(at(r, "pipeline.paintTotalMs")),
                    "reason": r.get("timelineUnavailableReason")}
            if filename:
                trace = self.json(f"{directory}/{filename}")
                if number(start) and number(end) and trace:
                    recomputed, markers = pipeline_from_trace(trace, r.get("id"), start, end)
                    info["phase_markers_present"] = all(markers.values())
                    self.same(r.get("pipeline"), recomputed, "pipeline_from_raw_trace", label=label, phase=list(key))
                    self.check(all(v == 1 for v in markers.values()), "trace_marker_count", label=label, phase=list(key), markers=markers)
            self.timeline[(side, *key)] = info
        self.launches.append({"side": side, "launchIndex": index, "directory": directory,
                              "pid": identity.get("pid"), "identityStartTicks": identity.get("identityStartTicks"),
                              "processStartEpochMs": identity.get("processStartEpochMs"),
                              "doneEpochMs": done[0].get("endedAt") if done else None,
                              "journal_records": len(records), "external_sample_rows": len(csv_rows)})
        return records, csv_rows

    def side(self, side):
        manifest = self.json(f"{side}/manifest.json")
        records = self.jsonl(f"{side}/phases.jsonl")
        samples = self.csv(f"{side}/samples.csv")
        report = self.json(f"{side}/report.json")
        build = self.json(f"build-{side}/manifest.json")
        self.records[side], self.reports[side] = records, report
        expected_commit = self.prov.get(side + "MeasuredCommit")
        for source, obj in (("build", build), ("merged", manifest)):
            for key, expected in {"commit": expected_commit, "dirty": False, "schemaVersion": 2,
                                  "protocolVersion": 2, "buildMode": "profile", "cacheState": "cold",
                                  "warmup": self.args.warmup, "repetitions": self.args.repetitions,
                                  "status": "built" if source == "build" else "passed"}.items():
                self.same(obj.get(key), expected, "source_manifest", side=side, source=source, key=key)
            self.check(bool(re.fullmatch(r"[0-9a-f]{64}", str(obj.get("binarySha256")))), "binary_hash_format", side=side, source=source)
        for key in SAME_BUILD:
            self.same(manifest.get(key), build.get(key), "merged_build_identity", side=side, key=key)
        for key, expected in {"sourceCommit": self.args.expected_baseline if side == "baseline" else self.args.expected_candidate,
                              "baseCommit": self.args.expected_baseline, "harnessCommit": self.args.expected_candidate,
                              "harnessSha256": self.prov.get("harnessSha256"), "launchOrder": self.plan,
                              "launchCount": self.launch_count}.items():
            self.same(manifest.get(key), expected, "merged_manifest", side=side, key=key)
        for ending in ("status.txt", "diff.patch"):
            raw = self.text(f"{side}-{ending}")
            self.check(raw is not None and not raw.strip(), "unclean_final_checkout", side=side, file=ending)
        head = self.text(f"{side}-head.txt")
        self.same(head.strip() if head else None, expected_commit, "final_checkout_head", side=side)
        maps = manifest.get("launchDirectories", [])
        self.same([m.get("launchIndex") for m in maps], list(range(self.launch_count)), "launch_mapping", side=side)
        merged_records, merged_csv = [], []
        for mapping in maps:
            rec, rows = self.launch(side, mapping, build)
            merged_records.extend(rec)
            merged_csv.extend(rows)
        self.same(records, merged_records, "merged_journal_not_exact", side=side)
        self.same(samples, merged_csv, "merged_csv_not_exact", side=side)
        self.check(not self.jsonl(f"{side}/samples.csv.errors.jsonl", optional=True), "merged_sampler_errors", side=side)
        meta = self.metadata(manifest, records, side)
        self.manifests[side] = meta
        for key in COMPARABLE:
            self.same(at(report, "metadata." + key), meta.get(key), "report_metadata", side=side, key=key)
        for key, expected in {"complete": True, "successful": True, "schemaVersion": 2,
                              "sourceSchemaVersion": 2, "comparisonEligibility": []}.items():
            self.same(report.get(key), expected, "report_status", side=side, key=key)
        rows = {r.get("name"): r for r in report.get("scenarios", [])}
        grouped = collections.defaultdict(list)
        for record in records:
            if record.get("type") == "phase":
                grouped[record.get("name")].append(record)
        self.check(set(rows) == set(grouped) and len(rows) == len(report.get("scenarios", [])), "report_scenario_inventory", side=side)
        for name, phases in grouped.items():
            measured = [p for p in phases if p.get("status") == "passed" and p.get("warmup") is False]
            all_values = [p.get("durationMs") for p in measured]
            if not all(number(v) for v in all_values):
                continue
            fvalues = {k: [v for p in measured for v in (p.get("frames") or {}).get(k, [])] for k in FRAME_KEYS}
            truncated = sum((p.get("frames") or {}).get("truncated") is True or (p.get("frames") or {}).get("droppedFrames", 0) > 0 for p in measured)
            metric = {"latencyMs": distribution(all_values), "frames": {"count": len(fvalues["buildMs"]),
                      "truncatedIterations": truncated, **{k: None if truncated else distribution(v) for k, v in fvalues.items()}}}
            self.metrics[(side, name)] = metric
            report_row = rows.get(name, {})
            self.same(report_row.get("latencyMs"), metric["latencyMs"], "latency_distribution", side=side, scenario=name)
            self.same(report_row.get("frames"), metric["frames"], "frame_distribution", side=side, scenario=name)
            for key, expected in {"measured": len(measured), "warmupExcluded": sum(p.get("warmup") is True for p in phases),
                                  "failures": sum(p.get("status") == "failed" for p in phases),
                                  "skipped": sum(p.get("status") == "skipped" for p in phases)}.items():
                self.same(report_row.get(key), expected, "report_count", side=side, scenario=name, key=key)
            reported_samples = report_row.get("samples")
            all_samples = [{k: v for k, v in p.items() if k not in ("frames", "type", "name")} for p in phases]
            self.same(reported_samples, all_samples, "report_samples_omitted_or_changed", side=side, scenario=name)
            if name in SCENARIOS:
                self.same(len(measured), self.launch_count * self.args.repetitions, "pooled_sample_count", side=side, scenario=name)
            metric["latency_by_launch"] = []
            for index in range(self.launch_count):
                samples_for_launch = [p for p in measured if p.get("launchIndex") == index]
                values = [p["durationMs"] for p in samples_for_launch]
                metric["latency_by_launch"].append({"launchIndex": index, "distribution": distribution(values),
                    "arithmetic_median": statistics.median(values) if values else None,
                    "samples_in_recorded_order": values,
                    "frames_totalMs": distribution(v for p in samples_for_launch for v in (p.get("frames") or {}).get("totalMs", [])),
                    "frame_counts_per_iteration": [(p.get("frames") or {}).get("count") for p in samples_for_launch]})

    def comparisons(self):
        before, after = (self.manifests[s] for s in SIDES)
        for key in COMPARABLE + ("machine",):
            self.check(before.get(key) is not None and after.get(key) is not None, "missing_comparison_metadata", key=key)
            self.same(after.get(key), before.get(key), "comparison_metadata_mismatch", key=key)
        if self.args.expected_hardware_id:
            self.same(after.get("hardwareId"), self.args.expected_hardware_id, "unexpected_hardware_id")
        if self.args.expected_flutter_revision:
            self.same(after.get("flutterVersion"), self.args.expected_flutter_revision, "unexpected_flutter_revision")
        comp = self.reports["candidate"].get("comparison", {})
        self.same(comp.get("comparable"), True, "report_not_comparable")
        self.same(comp.get("reasons"), [], "comparison_reasons")
        for side in SIDES:
            self.same(comp.get(side + "Commit"), self.prov.get(side + "MeasuredCommit"), "comparison_commit", side=side)
        comp_rows = {r.get("name"): r for r in comp.get("scenarios", [])}
        self.summaries = {}
        for name in SCENARIOS:
            if any((s, name) not in self.metrics for s in SIDES):
                self.check(False, "missing_comparison_scenario", scenario=name)
                continue
            a, b = (self.metrics[(s, name)] for s in SIDES)
            row = comp_rows.get(name, {})
            self.same(row.get("status"), "compared", "comparison_scenario_status", scenario=name)
            metrics = row.get("metrics", {})
            paths = [f"latencyMs.{q}" for q in ("p50", "p95", "p99")]
            paths += [f"frames.{f}.{q}" for f in FRAME_KEYS for q in ("p50", "p95", "p99")]
            for path in paths:
                self.same(metrics.get(path), difference(at(a, path), at(b, path)), "comparison_statistic", scenario=name, metric=path)
            paired = []
            for index in range(self.launch_count):
                av, bv = a["latency_by_launch"][index], b["latency_by_launch"][index]
                paired.append({"launchIndex": index,
                    "p50_candidate_over_baseline": ratio(at(av, "distribution.p50"), at(bv, "distribution.p50")),
                    "arithmetic_median_candidate_over_baseline": ratio(av["arithmetic_median"], bv["arithmetic_median"]),
                    "frames_total_p95_candidate_over_baseline": ratio(at(av, "frames_totalMs.p95"), at(bv, "frames_totalMs.p95"))})
            ratios = [v["p50_candidate_over_baseline"] for v in paired if number(v["p50_candidate_over_baseline"])]
            timeline = {}
            for side in SIDES:
                entries = [(k, v) for k, v in self.timeline.items() if k[0] == side and k[2] == name and k[3] is False]
                timeline[side] = {"samples": len(entries), **{key: sum(v.get(key) is True for _, v in entries) for key in
                    ("captured", "phase_markers_present", "pipeline_available", "layout_available", "paint_available")},
                    "reasons": dict(collections.Counter(str(v["reason"]) for _, v in entries if v.get("reason"))),
                    "captured_per_launch": [sum(k[1] == index and v["captured"] for k, v in entries)
                                            for index in range(self.launch_count)]}
            asymmetry = []
            for index in range(self.launch_count):
                for warm, count in ((True, self.args.warmup), (False, self.args.repetitions)):
                    for iteration in range(count):
                        av = self.timeline.get(("baseline", index, name, warm, iteration), {})
                        bv = self.timeline.get(("candidate", index, name, warm, iteration), {})
                        if av.get("captured") != bv.get("captured"):
                            asymmetry.append({"launchIndex": index, "warmup": warm, "iteration": iteration,
                                              "baseline": av, "candidate": bv})
            if asymmetry:
                self.warn("timeline_capture_asymmetry_review_required", scenario=name, samples=asymmetry)
            if timeline["baseline"]["captured"] == timeline["candidate"]["captured"] == 0:
                self.warn("timeline_unavailable_both_sides", scenario=name)
            self.summaries[name] = {"baseline": a, "candidate": b,
                "pooled_p50_candidate_over_baseline": ratio(at(a, "latencyMs.p50"), at(b, "latencyMs.p50")),
                "paired_launch_ratios": paired,
                "paired_launch_p50_ratio_range": [min(ratios), max(ratios)] if ratios else None,
                "timeline": timeline, "timeline_capture_symmetric": not asymmetry}
        identities = [(x["pid"], x["identityStartTicks"]) for x in self.launches]
        self.check(len(identities) == len(self.plan) and len(set(identities)) == len(self.plan), "eight_distinct_processes")
        ordered = sorted(self.launches, key=lambda x: x.get("processStartEpochMs") or 0)
        self.same([(x["side"], x["launchIndex"]) for x in ordered], [(x["side"], x["launchIndex"]) for x in self.plan], "actual_launch_order")
        for left, right in zip(ordered, ordered[1:]):
            self.check(number(left["doneEpochMs"]) and number(right["processStartEpochMs"]) and
                       left["doneEpochMs"] <= right["processStartEpochMs"], "overlapping_measured_processes")

    def run(self):
        self.provenance()
        for side in SIDES:
            self.side(side)
        self.comparisons()
        return {"audited_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "artifact_root": str(self.root), "expected_baseline": self.args.expected_baseline,
            "expected_candidate": self.args.expected_candidate, "passed_structural_and_statistical_checks": not self.errors,
            "errors": self.errors, "warnings": self.warnings,
            "design": {"cycles": self.args.cycles, "launches_per_side": self.launch_count,
                       "warmups_per_launch": self.args.warmup, "measured_repetitions_per_launch": self.args.repetitions,
                       "latency_samples_per_action_and_side": self.launch_count * self.args.repetitions,
                       "quantile_method": "nearest-rank; arithmetic_median is separately labeled",
                       "outlier_filter": "none; exact aggregate-versus-leaf equality and report sample retention checked",
                       "pairing": "same launchIndex pairs adjacent AB/BA runs within each ABBA cycle, not the same process"},
            "provenance": self.prov, "launches": self.launches, "scenarios": self.summaries,
            "limitations": [
                "16 latency samples per action are descriptive; p95 and p99 are both the observed maximum.",
                "Four processes on one machine are not independent machines; individual repetitions share process state.",
                "The candidate is the integrated PR, not only the representation change.",
                "Candidate harness blobs are independently checked with --repo. Baseline overlay identity relies on runner assertions and preserved provenance; its local commit object is not packaged.",
                "Binary and bundle declared hashes are cross-checked, not independently recomputed: build bundles are excluded from the artifact.",
                "Latency and frame quantiles are independently recalculated. CPU and process-tree derived resource summaries are not recalculated here.",
                "RSS is sampled and current heap is without forced GC; neither is an exact retained-object measurement.",
                "A nonzero frame count checks recorded coverage, not proof that every engine frame was delivered.",
                "Timeline capture asymmetry is a manual comparison-validity flag, not an application correctness or Draft-state gate."
            ], "input_file_sha256": self.hashes}


def self_test():
    d = distribution(range(1, 17))
    assert (d["count"], d["p50"], d["p95"], d["p99"]) == (16, 8, 16, 16)
    assert distribution([1, 2, 3, 1000000])["max"] == 1000000
    trace = {"traceEvents": [
        {"name": "reader.phase.begin", "args": {"id": "x"}, "ts": 0},
        {"name": "LAYOUT", "pid": 1, "tid": 2, "ph": "X", "ts": 100, "dur": 300},
        {"name": "LAYOUT (nested)", "pid": 1, "tid": 2, "ph": "X", "ts": 200, "dur": 400},
        {"name": "PAINT", "pid": 1, "tid": 2, "ph": "X", "ts": 900, "dur": 200},
        {"name": "reader.phase.end", "args": {"id": "x"}, "ts": 1000}]}
    p, markers = pipeline_from_trace(trace, "x", 0, 1000)
    assert p["layoutTotalMs"] == .5 and p["paintTotalMs"] is None and all(markers.values())
    assert difference(10, 15)["deltaPercent"] == 50
    assert not equivalent([1, 2, 100], [1, 2])
    print(json.dumps({"self_test": "passed", "uses_measurement_results": False}))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("artifact_root", nargs="?", help="Directory containing provenance.json, baseline/, candidate/, build-*/, step-*/")
    p.add_argument("--expected-candidate")
    p.add_argument("--expected-baseline", default=BASELINE)
    p.add_argument("--repo", help="Read-only local repository with the exact expected candidate commit")
    p.add_argument("--expected-hardware-id")
    p.add_argument("--expected-flutter-revision")
    p.add_argument("--cycles", type=int, default=2)
    p.add_argument("--warmup", type=int, default=1)
    p.add_argument("--repetitions", type=int, default=4)
    p.add_argument("--book-lines", default="2000,50000,1000000")
    p.add_argument("--output", help="JSON evidence destination outside the artifact input directory")
    p.add_argument("--self-test", action="store_true")
    args = p.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not args.artifact_root or not args.output or not args.expected_candidate:
        p.error("artifact_root, --expected-candidate and --output are required")
    for value in (args.expected_baseline, args.expected_candidate):
        if not re.fullmatch(r"[0-9a-f]{40}", value):
            p.error("Expected SHAs must be full lowercase 40-character commit IDs")
    if args.cycles < 1 or args.warmup < 0 or args.repetitions < 1:
        p.error("Invalid repetition design")
    destination = Path(args.output).resolve()
    if destination.is_relative_to(Path(args.artifact_root).resolve()):
        p.error("Keep QA output outside the raw artifact directory")
    audit = Audit(args)
    try:
        result = audit.run()
    except (ValueError, TypeError, KeyError, OSError, IndexError, AttributeError) as error:
        result = {"passed_structural_and_statistical_checks": False,
                  "errors": audit.errors + [{"code": "audit_could_not_complete", "error": repr(error)}],
                  "warnings": audit.warnings, "input_file_sha256": audit.hashes}
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
    print(json.dumps({"output": str(destination), "passed": result["passed_structural_and_statistical_checks"],
                      "errors": len(result["errors"]), "warnings": len(result["warnings"])}))
    return 0 if result["passed_structural_and_statistical_checks"] else 1


if __name__ == "__main__":
    sys.exit(main())
