#!/usr/bin/env python3
"""Build once and run the existing performance protocol on Linux or macOS."""

import argparse
import csv
import errno
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import signal
import subprocess
import sys
import time
import uuid

sys.dont_write_bytecode = True
if __package__:
    from .posix_engine import BundledFlutterEngine
    from .posix_resources import process_reader
    from .probe_binding import binding_identity, validate_binding_identity, validate_framework_scheduler
else:
    from posix_engine import BundledFlutterEngine
    from posix_resources import process_reader
    from probe_binding import binding_identity, validate_binding_identity, validate_framework_scheduler


FIELDS = ("epoch_ms", "pid", "name", "cpu_total_s", "ws_mb", "priv_mb",
          "identity_start_ticks", "handles", "threads", "root_pid",
          "monotonic_ms", "launch_index", "tree_age_ms")
REPOSITORY = Path(__file__).resolve().parents[2]
TARGET = "integration_test/perf_resource_probe_test.dart"


class Interrupted(Exception):
    def __init__(self, signum):
        self.signum = signum
        super().__init__(f"Interrupted by signal {signum}")


def interrupt(signum, _frame):
    raise Interrupted(signum)


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def write_json(path, value):
    temporary = path.with_name(path.name + ".pending")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def read_json(path, maximum=1024 * 1024):
    if path.is_symlink() or path.stat().st_size > maximum:
        raise RuntimeError(f"Invalid or oversized result: {path}")
    return json.loads(path.read_text(encoding="utf-8-sig"))


def capture(command, *, cwd=None, timeout=30):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                            encoding="utf-8", errors="backslashreplace", timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {command}: {result.stderr.strip()}")
    return result.stdout


def source_provenance(repository, manifest, stage):
    git = ["git", "-C", str(repository), "-c", "core.quotepath=false"]
    status = capture(git + ["status", "--porcelain=v1", "--untracked-files=all"]).splitlines()
    summary = capture(git + ["diff", "--no-ext-diff", "--no-textconv", "--stat",
                             "--summary", "HEAD", "--"]).splitlines()
    manifest.setdefault("sourceProvenance", {})[stage] = {
        "observedAtUtc": utc_now(), "statusPorcelain": status, "trackedDiffSummary": summary,
    }
    manifest["dirty"] = manifest.get("dirty") is True or bool(status)


def child_exit(process):
    # Leave the child waitable: its PID cannot be reused before group cleanup.
    result = os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
    if result is None:
        return None
    return result.si_status if result.si_code == os.CLD_EXITED else -result.si_status


def _darwin_group_has_only_zombies(process, evidence=None):
    if evidence is None:
        evidence = {}
    evidence.update(platform=sys.platform, parentPid=os.getpid())
    if sys.platform != "darwin":
        return False
    deadline = time.monotonic() + 5
    exit_code = child_exit(process)
    evidence["initialExitCode"] = exit_code
    # XNU removes exiting processes from proc_find before waitid can observe SZOMB.
    # Keep the child unreaped while its exit becomes observable.
    while exit_code is None:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        time.sleep(min(.01, remaining))
        exit_code = child_exit(process)
    waitable = exit_code is not None and time.monotonic() <= deadline
    evidence.update(childExitCode=exit_code, waitableBeforeDeadline=waitable)
    result = subprocess.run(["ps", "-axo", "pid=,ppid=,pgid=,stat="],
                            capture_output=True, text=True, encoding="utf-8",
                            env={**os.environ, "LC_ALL": "C"}, timeout=5)
    evidence["processTable"] = {"exitCode": result.returncode,
                                "stdout": result.stdout, "stderr": result.stderr}
    if not waitable or result.returncode:
        return False
    members = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if not fields:
            continue
        if len(fields) != 4 or not all(field.isdigit() for field in fields[:3]):
            return False
        pid, parent, group = map(int, fields[:3])
        if group == process.pid:
            members.append((pid, parent, fields[3]))
    leader = [item for item in members if item[0] == process.pid]
    return (len(leader) == 1 and leader[0][1] == os.getpid()
            and all(state.startswith("Z") for _, _, state in members))


def cleanup_group(process, grace=0.2):
    for signum in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, signum)
        except ProcessLookupError:
            pass
        except PermissionError as error:
            evidence = {"pid": process.pid, "signal": int(signum), "errno": error.errno}
            accepted = False
            try:
                accepted = (error.errno == errno.EPERM
                            and _darwin_group_has_only_zombies(process, evidence))
            finally:
                if not accepted:
                    print(json.dumps({"cleanupRefused": evidence}), file=sys.stderr)
            if not accepted:
                raise
        if signum == signal.SIGTERM:
            time.sleep(grace)
    process.wait(timeout=5)


def run_logged(command, log, *, cwd, timeout):
    with log.open("x", encoding="utf-8") as output:
        process = subprocess.Popen(command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            deadline = time.monotonic() + timeout
            while (code := child_exit(process)) is None:
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"Command exceeded {timeout}s: {command}")
                time.sleep(0.1)
            if code:
                raise RuntimeError(f"Command failed ({code}); inspect {log}")
        finally:
            cleanup_group(process)


def binary_path(repository, system, mode):
    if system == "linux":
        architecture = {"x86_64": "x64", "aarch64": "arm64"}.get(platform.machine())
        if architecture is None:
            raise RuntimeError(f"Unsupported Linux architecture: {platform.machine()}")
        executable = repository / f"build/linux/{architecture}/{mode}/bundle/otzaria"
    else:
        products = repository / "build/macos/Build/Products" / mode.title()
        apps = list(products.glob("*.app"))
        if len(apps) != 1:
            raise RuntimeError(f"Expected one freshly built macOS app in {products}")
        with (apps[0] / "Contents/Info.plist").open("rb") as file:
            name = plistlib.load(file).get("CFBundleExecutable")
        if not isinstance(name, str) or Path(name).name != name or name in ("", ".", ".."):
            raise RuntimeError("Invalid CFBundleExecutable")
        executable = apps[0] / "Contents/MacOS" / name
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise RuntimeError(f"Built executable is missing or not executable: {executable}")
    return executable


def sha256_file(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def reject_existing_app(observations=None):
    if observations is None:
        observations = []
    locale = "en_US.UTF-8" if sys.platform == "darwin" else "C"
    for line in capture(["env", f"LC_ALL={locale}", "ps", "-ww", "-axo",
                         "pid=,ppid=,uid=,stat=,lstart=,comm="]).splitlines():
        fields = line.strip().split(maxsplit=9)
        if (len(fields) == 10 and int(fields[2]) == os.getuid()
                and Path(fields[9]).name.casefold() in {"otzaria", "אוצריא"}):
            zombie = fields[3].startswith("Z")
            observations.append({
                "pid": int(fields[0]), "parentPid": int(fields[1]), "state": fields[3],
                "startedAtLocal": " ".join(fields[4:9]), "command": fields[9],
                "decision": "ignored-exited-zombie" if zombie else "refused-live-process",
            })
            # An unreaped zombie has exited and cannot affect the measurement.
            if not zombie:
                raise RuntimeError(f"Close the existing Otzaria process {fields[0]} before measuring "
                                   f"(state={fields[3]}, parentPid={fields[1]})")


def graphics_metadata(system):
    try:
        if system == "linux":
            source = "glxinfo -B (display observation, not the app rendering route)"
            lines = capture(["glxinfo", "-B"]).splitlines()
            values = [line.strip() for line in lines if line.strip().startswith((
                "Vendor:", "Device:", "Version:", "Accelerated:", "OpenGL vendor string:",
                "OpenGL renderer string:", "OpenGL version string:", "OpenGL core profile version string:"))]
        else:
            source = "system_profiler SPDisplaysDataType (display observation, not GPU allocations)"
            displays = json.loads(capture(["system_profiler", "SPDisplaysDataType", "-json"]))
            keys = ("_name", "sppci_model", "spdisplays_vendor", "spdisplays_device-id",
                    "spdisplays_revision-id", "spdisplays_vram", "spdisplays_vram_shared", "spdisplays_metal")
            values = [{key: item[key] for key in keys if key in item}
                      for item in displays["SPDisplaysDataType"]]
        if not values:
            raise RuntimeError("No graphics identity was returned")
        return {"availability": "collected", "source": source, "values": values}
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.SubprocessError) as error:
        return {"availability": "unavailable", "reason": str(error)}


def machine_metadata(system):
    if system == "linux":
        cpu = next((line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines()
                    if line.startswith(("model name", "Hardware"))), platform.machine())
        memory = os.sysconf("SC_PHYS_PAGES") * os.sysconf("SC_PAGE_SIZE")
        os_name = f"linux-{platform.release()}-{platform.machine()}"
    else:
        cpu = capture(["sysctl", "-n", "machdep.cpu.brand_string"]).strip()
        memory = int(capture(["sysctl", "-n", "hw.memsize"]).strip())
        version = capture(["sw_vers", "-productVersion"]).strip()
        build = capture(["sw_vers", "-buildVersion"]).strip()
        os_name = f"macos-{version}-{build}-{platform.machine()}"
    machine = {"cpu": cpu, "logicalProcessors": os.cpu_count(), "memoryBytes": memory,
               "architecture": platform.machine(), "graphics": graphics_metadata(system)}
    identity = json.dumps({"host": platform.node(), **machine}, sort_keys=True).encode()
    return machine, hashlib.sha256(identity).hexdigest(), os_name


def is_fixture_id(value):
    # PerfFixture._identity hashes its corpus/actions after this schema prefix.
    return isinstance(value, str) and re.fullmatch(r"synthetic-v4-pdf-cases:[0-9a-f]{64}", value) is not None


def validate_completion(directory, *, pid, index, preparation, mode, scenario,
                        binding_mode="integration"):
    completion = read_json(directory / "completion.json")
    if (not isinstance(completion, dict) or completion.get("status") != "passed"
            or completion.get("preparationOnly") is not preparation
            or completion.get("error") is not None or completion.get("testFailures") != []):
        raise RuntimeError(f"Application did not complete successfully: {directory}")
    validate_binding_identity(completion, binding_mode)
    journal = directory / "phases.jsonl"
    if journal.is_symlink() or journal.stat().st_size > 128 * 1024 * 1024:
        raise RuntimeError("Invalid or oversized phase journal")
    metadata, endings = [], []
    with journal.open(encoding="utf-8") as source:
        for line in source:
            record = json.loads(line)
            if not isinstance(record, dict):
                raise RuntimeError("Invalid phase journal record")
            if record.get("type") == "meta" and "pid" in record:
                metadata.append(record)
            if record.get("type") == "done":
                endings.append(record)
    if len(metadata) != 1 or len(endings) != 1:
        raise RuntimeError("Missing or duplicate process metadata/completion")
    meta, end = metadata[0], endings[0]
    required = {"pid": pid, "launchIndex": index, "schemaVersion": 2, "protocolVersion": 2,
                "preparationOnly": preparation, "buildMode": mode, "scenarioSet": scenario,
                "bindingMode": binding_mode, "probeTarget": binding_identity(binding_mode)["probeTarget"]}
    if any(type(meta.get(key)) is not type(value) or meta[key] != value for key, value in required.items()):
        raise RuntimeError("Application metadata does not match the owned launch")
    fixture = meta.get("fixtureId")
    if (not is_fixture_id(fixture)
            or completion.get("fixtureId") != fixture or end.get("launchIndex") != index
            or end.get("status") != "passed"):
        raise RuntimeError("Application fixture or final journal entry is inconsistent")
    return fixture


def invoke_launch(executable, directory, data, args, reader, *, index, preparation=False,
                  pdf_case="", sampler_interval=0.5, engine=None):
    directory.mkdir()
    environment = dict(os.environ, PERF_OUTPUT_DIR=str(directory), PERF_DATA_DIR=str(data),
                       PERF_CACHE_STATE="cold" if preparation or index < 0 else args.cache_state,
                       PERF_LAUNCH_INDEX=str(index), PERF_WARMUP=str(args.warmup),
                       PERF_REPETITIONS=str(args.repetitions), PERF_SCENARIO_SET=args.scenario_set,
                       PERF_BINDING_MODE=args.binding_mode,
                       PERF_PDF_CASE=str(pdf_case), PERF_PREPARE_ONLY="1" if preparation else "0")
    launch = {"launchIndex": index, "preparationOnly": preparation, "startedAtUtc": utc_now()}
    count, errors, success = 0, [], False
    with (directory / "stdout.log").open("x") as stdout, (directory / "stderr.log").open("x") as stderr:
        process = subprocess.Popen([str(executable)], cwd=executable.parent, env=environment,
                                   stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            observed = reader.read(process.pid)
            launch.update(pid=process.pid, identityStartTicks=str(observed.start_ticks))
            write_json(directory / "launch.json", launch)
            began = time.monotonic()
            next_sample = began
            with (directory / "samples.csv").open("x", newline="", encoding="utf-8") as stream:
                writer = csv.DictWriter(stream, fieldnames=FIELDS, lineterminator="\n")
                writer.writeheader()
                while True:
                    exit_code = child_exit(process)
                    if (directory / "completion.json").exists():
                        fixture = validate_completion(directory, pid=process.pid, index=index,
                                                      preparation=preparation, mode=args.mode,
                                                      scenario=args.scenario_set, binding_mode=args.binding_mode)
                        exit_code = child_exit(process)
                        if exit_code not in (None, 0):
                            raise RuntimeError(f"Application exited unsuccessfully ({exit_code})")
                        if engine is not None:
                            if exit_code is not None or reader.read(process.pid).start_ticks != observed.start_ticks:
                                raise RuntimeError("The owned process exited before engine verification")
                            # The phase journal is complete: this inspection is outside measured actions.
                            evidence = engine.observe_loaded(process.pid, raw_path=directory / "engine-observation.json")
                            evidence["observedAfterCompletion"] = True
                            write_json(directory / "engine.json", evidence)
                            launch["engineVerifiedAfterCompletion"] = True
                        success = True
                        return fixture
                    if exit_code is not None:
                        raise RuntimeError(f"Application exited before completion ({exit_code})")
                    now = time.monotonic()
                    if now - began >= args.timeout_seconds:
                        raise TimeoutError(f"Application exceeded {args.timeout_seconds}s")
                    if not preparation and now >= next_sample:
                        try:
                            value = reader.read(process.pid)
                            if value.start_ticks != observed.start_ticks:
                                raise RuntimeError("Owned process identity changed")
                            writer.writerow({
                                "epoch_ms": time.time_ns() // 1_000_000, "pid": process.pid,
                                "name": executable.name, "cpu_total_s": value.cpu_seconds,
                                "ws_mb": value.resident_bytes / 1048576,
                                "identity_start_ticks": str(value.start_ticks), "threads": value.threads,
                                "root_pid": process.pid, "monotonic_ms": (time.monotonic() - began) * 1000,
                                "launch_index": index,
                            })
                            stream.flush()
                            count += 1
                            next_sample = time.monotonic() + sampler_interval
                        except (OSError, ValueError, RuntimeError) as error:
                            errors.append({"atUtc": utc_now(), "kind": "owned_process", "error": str(error)})
                            raise
                    time.sleep(min(0.05, max(0.001, next_sample - now)) if not preparation else 0.05)
        finally:
            cleanup_group(process)
            late_failure = success and process.returncode not in (0, -signal.SIGTERM, -signal.SIGKILL)
            if late_failure:
                success = False
            launch.update(endedAtUtc=utc_now(), completedBeforeTermination=success,
                          cleanup="SIGTERM/SIGKILL of the owned group, then wait/reap")
            write_json(directory / "launch.json", launch)
            (directory / "samples.csv.errors.jsonl").write_text(
                "".join(json.dumps(item) + "\n" for item in errors), encoding="utf-8")
            write_json(directory / "samples.csv.status.json", {
                "complete": success and not errors and (preparation or count > 0),
                "samples": count, "errors": len(errors), "launchIndex": index,
                "scope": "owned-root-process-only", "descendantsObserved": False,
            })
            if late_failure:
                raise RuntimeError(f"Application exited unsuccessfully ({process.returncode})")


def merge_outputs(output, launches):
    for name in ("phases.jsonl", "samples.csv", "samples.csv.errors.jsonl"):
        with (output / name).open("w", encoding="utf-8", newline="") as target:
            has_header = False
            for directory in launches:
                path = directory / name
                if not path.exists():
                    continue
                with path.open(encoding="utf-8", newline="") as source:
                    for index, line in enumerate(source):
                        if name != "samples.csv" or index != 0 or not has_header:
                            target.write(line)
                    if name == "samples.csv":
                        has_header = True


def launch_plan(output, args):
    warm_data = output / "data/warm"
    if args.cache_state == "warm":
        yield output / "prepare-data", warm_data, -1, True, False
        yield output / "prepare-warm", warm_data, -1, False, False
    for index in range(args.launches):
        data = warm_data if args.cache_state == "warm" else output / f"data/cold-{index}"
        if args.cache_state == "cold":
            yield output / f"prepare-data-{index}", data, -1, True, False
        yield output / f"launch-{index:03d}", data, index, False, True


def run(args, *, repository=REPOSITORY):
    probe_binding = binding_identity(args.binding_mode)
    if args.binding_mode == "framework" and args.scenario_set == "all":
        raise ValueError("The framework target accepts pdf-reader, pdf-book-view or pdf-multi-window")
    if args.scenario_set == "pdf-multi-window" and args.binding_mode != "framework":
        raise ValueError("The multi-window scenario requires the framework binding")
    output = args.output
    if output.exists() or output.is_symlink():
        raise RuntimeError(f"Output directory already exists: {output}")
    output.mkdir(parents=True, exist_ok=False)
    manifest = {"schemaVersion": 2, "protocolVersion": 2, "status": "running",
                "startedAtUtc": utc_now(), "buildMode": args.mode, "cacheState": args.cache_state,
                "scenarioSet": args.scenario_set, "warmup": args.warmup,
                "bindingMode": args.binding_mode, "probeTarget": probe_binding["probeTarget"],
                "repetitions": args.repetitions, "launchCount": args.launches,
                "coldDefinition": "fresh application data; OS file cache is not flushed",
                "startupOrigin": "Dart main; fixture preparation and native pre-main are excluded"}
    launches, failure = [], None
    try:
        system = "macos" if sys.platform == "darwin" else "linux"
        if (sys.platform not in ("linux", "darwin") or not hasattr(os, "waitid")
                or not hasattr(os, "WNOWAIT")):
            raise RuntimeError("Linux or macOS with waitid/WNOWAIT is required (macOS: Python 3.13+)")
        if system == "linux" and not (os.getenv("DISPLAY") or os.getenv("WAYLAND_DISPLAY")):
            raise RuntimeError("A Linux desktop session is required; CI uses Xvfb, DBus and Openbox")
        manifest["existingAppProcesses"] = []
        reject_existing_app(manifest["existingAppProcesses"])
        reader = process_reader()
        machine, identity, os_name = machine_metadata(system)
        sdk = json.loads(capture(["flutter", "--version", "--machine"], cwd=repository, timeout=60))
        commit = capture(["git", "rev-parse", "HEAD"], cwd=repository).strip()
        manifest.update(commit=commit, flutterVersion=sdk["frameworkRevision"],
                        hardwareId=args.hardware_id or identity, machine=machine, os=os_name)
        manifest["sampling"] = {
            "intervalMs": 500, "treeRefreshMs": None, "heap": args.mode != "release",
            "scope": "owned-root-process-only", "descendantsObserved": False,
            "displayMode": args.display_mode, "processReader": reader.metadata(),
            "rendererEnvironment": {key: os.environ.get(key) for key in (
                "GDK_BACKEND", "XDG_SESSION_TYPE", "LIBGL_ALWAYS_SOFTWARE", "GDK_SCALE", "GDK_DPI_SCALE")},
            "unavailable": ["private commit", "handles", "GPU allocation", "descendant CPU/RSS"],
        }
        run_logged(["flutter", "pub", "get", "--enforce-lockfile"], output / "pub-get.log",
                   cwd=repository, timeout=args.build_timeout_seconds)
        pdf_case = ""
        if args.pdf_case:
            pdf_case = output / "pdf-case.json"
            run_logged(["dart", "tool/perf_probe/prepare_pdf_case.dart", str(args.pdf_case), str(pdf_case)],
                       output / "pdf-case.log", cwd=repository, timeout=120)
        source_provenance(repository, manifest, "beforeBuild")
        write_json(output / "manifest.json", manifest)
        try:
            run_logged(["flutter", "build", system, f"--{args.mode}", "--no-pub", f"--target={probe_binding['probeTarget']}",
                        "--dart-define=SENTRY_DSN=",
                        "--dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false"],
                       output / "build.log", cwd=repository, timeout=args.build_timeout_seconds)
        finally:
            source_provenance(repository, manifest, "afterBuild")
            write_json(output / "manifest.json", manifest)
        if capture(["git", "rev-parse", "HEAD"], cwd=repository).strip() != commit:
            raise RuntimeError("HEAD changed during the build")
        executable = binary_path(repository, system, args.mode)
        manifest["binarySha256"] = sha256_file(executable)
        engine = BundledFlutterEngine(executable, system, args.mode)
        manifest["engineIdentity"] = engine.identity
        manifest["engineEvidence"] = {"canonicalPath": str(engine.path), "verifiedAfterRuns": False}
        write_json(output / "manifest.json", manifest)
        fixture = None
        for directory, data, index, preparation, measured in launch_plan(output, args):
            if measured:
                launches.append(directory)
            actual_fixture = invoke_launch(executable, directory, data, args, reader, index=index,
                                           preparation=preparation, pdf_case=pdf_case, engine=engine)
            if fixture is not None and fixture != actual_fixture:
                raise RuntimeError("Fixture identity changed across preparation/launches")
            fixture = actual_fixture
            if not read_json(directory / "samples.csv.status.json")["complete"]:
                raise RuntimeError(f"Resource sampling was incomplete: {directory}")
        engine.verify_unchanged()
        manifest["engineEvidence"]["verifiedAfterRuns"] = True
        if sha256_file(executable) != manifest["binarySha256"]:
            raise RuntimeError("The measured executable changed during the run")
        if capture(["git", "rev-parse", "HEAD"], cwd=repository).strip() != commit:
            raise RuntimeError("HEAD changed during the run")
        source_provenance(repository, manifest, "afterRuns")
        manifest["status"] = "passed"
    except (OSError, ValueError, KeyError, RuntimeError, Interrupted, subprocess.SubprocessError) as error:
        failure = error
        manifest.update(status="failed", error=str(error))
    finally:
        manifest["endedAtUtc"] = utc_now()
        write_json(output / "manifest.json", manifest)
        merge_outputs(output, launches)
        if (output / "phases.jsonl").stat().st_size:
            try:
                command = ["dart", "tool/perf_probe/analyze.dart", str(output)]
                if args.baseline:
                    command += ["--baseline", str(args.baseline)]
                run_logged(command, output / "analyze.log", cwd=repository, timeout=120)
                report = read_json(output / "report.json", maximum=128 * 1024 * 1024)
                if report.get("complete") is not True or report.get("successful") is not True:
                    raise RuntimeError("Analysis did not confirm a complete successful run")
                if args.binding_mode == "framework":
                    metadata = report.get("metadata", {})
                    validate_binding_identity(metadata.get("settings"), args.binding_mode)
                    validate_framework_scheduler(report.get("notes"), args.launches)
            except (OSError, ValueError, RuntimeError, Interrupted) as error:
                failure = failure or error
                manifest.update(status="failed", analysisError=str(error))
                write_json(output / "manifest.json", manifest)
        print(f"Results: {output}")
    if failure is not None:
        print(str(failure), file=sys.stderr)
        return 128 + failure.signum if isinstance(failure, Interrupted) else 1
    return 0


def arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("profile", "release"), default="profile")
    parser.add_argument("--cache-state", choices=("cold", "warm"), default="cold")
    parser.add_argument("--scenario-set", choices=("all", "pdf-reader", "pdf-book-view", "pdf-multi-window"), default="pdf-reader")
    parser.add_argument("--binding-mode", choices=("integration", "framework"), default="integration")
    parser.add_argument("--pdf-case", type=Path)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--repetitions", type=int, default=5)
    parser.add_argument("--launches", type=int, default=3)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--hardware-id", default="")
    parser.add_argument("--timeout-seconds", type=int, default=1200)
    parser.add_argument("--build-timeout-seconds", type=int, default=2400)
    parser.add_argument("--display-mode", choices=("desktop", "xvfb"), default="desktop")
    args = parser.parse_args(argv)
    if args.binding_mode == "framework" and args.scenario_set == "all":
        parser.error("--binding-mode framework accepts pdf-reader, pdf-book-view or pdf-multi-window")
    if args.scenario_set == "pdf-multi-window" and args.binding_mode != "framework":
        parser.error("--scenario-set pdf-multi-window requires --binding-mode framework")
    for key, low, high in (("warmup", 0, 10), ("repetitions", 1, 100), ("launches", 1, 30),
                           ("timeout_seconds", 60, 7200), ("build_timeout_seconds", 60, 7200)):
        if not low <= getattr(args, key) <= high:
            parser.error(f"--{key.replace('_', '-')} must be between {low} and {high}")
    if args.display_mode == "xvfb" and sys.platform != "linux":
        parser.error("--display-mode xvfb is Linux-only")
    if args.output is None:
        args.output = REPOSITORY / "build/perf_probe" / ("run_" + uuid.uuid4().hex[:12])
    for key in ("output", "baseline", "pdf_case"):
        value = getattr(args, key)
        if value is not None:
            setattr(args, key, value.absolute())
    return args


def main():
    args = arguments()
    signal.signal(signal.SIGTERM, interrupt)
    signal.signal(signal.SIGINT, interrupt)
    try:
        return run(args)
    except (OSError, RuntimeError, Interrupted) as error:
        print(str(error), file=sys.stderr)
        return 128 + error.signum if isinstance(error, Interrupted) else 1


if __name__ == "__main__":
    sys.exit(main())
