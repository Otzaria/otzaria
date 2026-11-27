"""Lifecycle/provenance contracts; real child processes, no Flutter performance claims."""

import argparse
import contextlib
import csv
import ctypes
import hashlib
import io
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

from tool.perf_probe import posix_resources as resources
from tool.perf_probe import probe_binding as bindings
from tool.perf_probe import run_perf_probe_posix as runner
from tool.perf_probe import validate_perf_probe_smoke as smoke


def options(output, **overrides):
    values = dict(output=output, mode="profile", cache_state="cold", scenario_set="pdf-reader",
                  binding_mode="integration",
                  warmup=0, repetitions=1, launches=1, pdf_case=None, baseline=None,
                  hardware_id="test-machine", display_mode="desktop", timeout_seconds=2,
                  build_timeout_seconds=2)
    values.update(overrides)
    return argparse.Namespace(**values)


class PosixResourcesTest(unittest.TestCase):
    def linux_stat(self, *, pid=42, name="a (nested) name", state="S", user=120, system=30,
                   threads=5, start=998877, rss=12):
        fields = ["0"] * 30
        fields[0] = state
        for index, value in ((11, user), (12, system), (17, threads), (19, start), (21, rss)):
            fields[index] = str(value)
        return f"{pid} ({name}) " + " ".join(fields)

    def test_linux_units_and_parentheses_are_not_ambiguous(self):
        value = resources.parse_linux_stat(self.linux_stat(), expected_pid=42,
                                           clock_ticks=100, page_size=4096)
        self.assertEqual(value, resources.ProcessObservation(998877, 1.5, 49152, 5))

    def test_linux_rejects_dead_wrong_identity_and_malformed_metrics(self):
        for source in (self.linux_stat(pid=99), self.linux_stat(state="Z"),
                       self.linux_stat(user=-1), self.linux_stat(start=0),
                       self.linux_stat(rss=-1), "42 missing comm"):
            with self.subTest(source=source), self.assertRaises((ValueError, ProcessLookupError)):
                resources.parse_linux_stat(source, expected_pid=42, clock_ticks=100, page_size=4096)

    def test_darwin_uses_mach_timebase_and_does_not_invent_threads_or_private_commit(self):
        self.assertEqual(ctypes.sizeof(resources.RUsageInfoV0), 96)
        value = resources.RUsageInfoV0()
        value.proc_start_abstime = 1234567
        value.user_time, value.system_time = 18_000_000, 6_000_000
        value.resident_size, value.phys_footprint = 8192, 777777
        observed = resources.darwin_observation(value, 125, 3)
        self.assertEqual(observed, resources.ProcessObservation(1234567, 1.0, 8192))
        self.assertIsNone(observed.threads)
        value.proc_exit_abstime = 1
        with self.assertRaises(ProcessLookupError):
            resources.darwin_observation(value, 125, 3)
        value.proc_exit_abstime = 0
        with self.assertRaises(ValueError):
            resources.darwin_observation(value, 125, 0)

    def test_native_reader_tracks_lifetime_and_matches_the_host_cpu_clock(self):
        reader = resources.process_reader()
        before = reader.read(os.getpid())
        clock = time.process_time()
        while time.process_time() - clock < 0.08:
            sum(range(1000))
        after = reader.read(os.getpid())
        elapsed = time.process_time() - clock
        self.assertEqual(before.start_ticks, after.start_ticks)
        self.assertGreater(after.start_ticks, 0)
        self.assertGreater(after.resident_bytes, 0)
        self.assertAlmostEqual(after.cpu_seconds - before.cpu_seconds, elapsed, delta=0.03)
        self.assertGreater(after.cpu_seconds, before.cpu_seconds)



class DarwinGroupCleanupTest(unittest.TestCase):
    def child(self, body="raise SystemExit(37)"):
        process = subprocess.Popen([sys.executable, "-c", body], start_new_session=True)

        def reap():
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)

        self.addCleanup(reap)
        return process

    def exited(self):
        process = self.child()
        deadline = time.monotonic() + 5
        while runner.child_exit(process) is None and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertEqual(runner.child_exit(process), 37)
        return process

    def permission(self):
        return PermissionError(1, "Operation not permitted")

    def test_darwin_permission_on_a_real_waitable_zombie_still_reaps_its_child(self):
        process = self.exited()
        with mock.patch.object(runner.sys, "platform", "darwin"), \
             mock.patch.object(runner.os, "killpg", side_effect=self.permission()) as kill:
            runner.cleanup_group(process, grace=0)
        self.assertEqual(kill.call_args_list, [
            mock.call(process.pid, signal.SIGTERM),
            mock.call(process.pid, signal.SIGKILL),
        ])
        self.assertEqual(process.returncode, 37)
        with self.assertRaises(ChildProcessError):
            runner.child_exit(process)

    def test_darwin_permission_is_not_ignored_for_a_living_owned_child(self):
        process = self.child("import time; time.sleep(30)")
        for state in ("S", "Z"):
            clock = [100.0]
            diagnostic = io.StringIO()
            table = f"{process.pid} {os.getpid()} {process.pid} {state}\n"

            def advance(delay):
                clock[0] += delay

            with self.subTest(state=state), \
                 contextlib.redirect_stderr(diagnostic), \
                 mock.patch.object(runner.sys, "platform", "darwin"), \
                 mock.patch.object(runner.os, "killpg", side_effect=self.permission()), \
                 mock.patch.object(runner.time, "monotonic", side_effect=lambda: clock[0]), \
                 mock.patch.object(runner.time, "sleep", side_effect=advance), \
                 mock.patch.object(runner.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, table, "")) as ps:
                with self.assertRaises(PermissionError):
                    runner.cleanup_group(process, grace=0)
                ps.assert_called_once()
            self.assertEqual(clock[0], 105.0)
            evidence = json.loads(diagnostic.getvalue())["cleanupRefused"]
            self.assertEqual(evidence["pid"], process.pid)
            self.assertEqual(evidence["signal"], signal.SIGTERM)
            self.assertEqual(evidence["errno"], 1)
            self.assertIsNone(evidence["childExitCode"])
            self.assertFalse(evidence["waitableBeforeDeadline"])
            self.assertEqual(evidence["processTable"]["stdout"], table)
            self.assertIsNone(process.returncode)

    def test_darwin_permission_waits_without_reaping_until_its_child_is_waitable(self):
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary) / "exit"
            process = self.child(f"""from pathlib import Path
import time
while not Path({str(release)!r}).exists(): time.sleep(.001)
raise SystemExit(37)
""")
            real_sleep = time.sleep

            def settle(delay):
                if not release.exists():
                    self.assertIsNone(runner.child_exit(process))
                    release.touch()
                real_sleep(delay)

            with mock.patch.object(runner.sys, "platform", "darwin"), \
                 mock.patch.object(runner.os, "killpg", side_effect=self.permission()), \
                 mock.patch.object(runner.time, "sleep", side_effect=settle), \
                 mock.patch.object(process, "wait", wraps=process.wait) as reap:
                runner.cleanup_group(process, grace=0)
                reap.assert_called_once_with(timeout=5)
            self.assertTrue(release.exists())
            self.assertEqual(process.returncode, 37)
            with self.assertRaises(ChildProcessError):
                runner.child_exit(process)

    def test_darwin_exit_observed_after_deadline_is_not_accepted_or_reaped(self):
        process = self.exited()
        clock = [100.0]
        diagnostic = io.StringIO()
        table = f"{process.pid} {os.getpid()} {process.pid} Z\n"
        with contextlib.redirect_stderr(diagnostic), \
             mock.patch.object(runner.sys, "platform", "darwin"), \
             mock.patch.object(runner.os, "killpg", side_effect=self.permission()), \
             mock.patch.object(runner, "child_exit", side_effect=[None, 37]), \
             mock.patch.object(runner.time, "monotonic", side_effect=lambda: clock[0]), \
             mock.patch.object(runner.time, "sleep", side_effect=lambda _: clock.__setitem__(0, 106.0)), \
             mock.patch.object(runner.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, table, "")):
            with self.assertRaises(PermissionError):
                runner.cleanup_group(process, grace=0)
        evidence = json.loads(diagnostic.getvalue())["cleanupRefused"]
        self.assertEqual(evidence["childExitCode"], 37)
        self.assertFalse(evidence["waitableBeforeDeadline"])
        self.assertIsNone(process.returncode)
        self.assertEqual(runner.child_exit(process), 37)

    def test_darwin_permission_is_not_ignored_for_any_live_or_unknown_group_member(self):
        process = self.exited()
        for state in ("R", "S", "D", "T", "I", "?", "X"):
            table = (f"{process.pid} {os.getpid()} {process.pid} Z\n"
                     f"999999 1 {process.pid} {state}\n")
            with self.subTest(state=state), \
                 mock.patch.object(runner.sys, "platform", "darwin"), \
                 mock.patch.object(runner.os, "killpg", side_effect=self.permission()), \
                 mock.patch.object(runner.subprocess, "run",
                                   return_value=subprocess.CompletedProcess([], 0, table, "")):
                with self.assertRaises(PermissionError):
                    runner.cleanup_group(process, grace=0)
                self.assertEqual(runner.child_exit(process), 37)

    def test_missing_foreign_or_malformed_group_evidence_fails_closed(self):
        process = self.exited()
        tables = ("", "invalid", f"{process.pid} 1 {process.pid} Z\n",
                  f"{process.pid} {os.getpid()} {process.pid + 1} Z\n",
                  f"{process.pid} {os.getpid()} {process.pid} Z\nmalformed\n")
        for table in tables:
            with self.subTest(table=table), \
                 mock.patch.object(runner.sys, "platform", "darwin"), \
                 mock.patch.object(runner.os, "killpg", side_effect=self.permission()), \
                 mock.patch.object(runner.subprocess, "run",
                                   return_value=subprocess.CompletedProcess([], 0, table, "")):
                with self.assertRaises(PermissionError):
                    runner.cleanup_group(process, grace=0)

    def test_failed_ps_and_non_darwin_permissions_are_not_suppressed(self):
        process = self.exited()
        for platform, ps_code in (("darwin", 1), ("linux", 0)):
            table = f"{process.pid} {os.getpid()} {process.pid} Z\n"
            with self.subTest(platform=platform), \
                 mock.patch.object(runner.sys, "platform", platform), \
                 mock.patch.object(runner.os, "killpg", side_effect=self.permission()), \
                 mock.patch.object(runner.subprocess, "run",
                                   return_value=subprocess.CompletedProcess([], ps_code, table, "failed")):
                with self.assertRaises(PermissionError):
                    runner.cleanup_group(process, grace=0)

    def test_permission_check_keeps_the_owned_child_waitable_and_fixes_ps_locale(self):
        process = self.exited()
        table = (f"{process.pid} {os.getpid()} {process.pid} Z+\n"
                 f"999999 1 {process.pid} Z\n")
        with mock.patch.object(runner.sys, "platform", "darwin"), \
             mock.patch.object(runner.subprocess, "run",
                               return_value=subprocess.CompletedProcess([], 0, table, "")) as ps:
            self.assertTrue(runner._darwin_group_has_only_zombies(process))
            self.assertEqual(runner.child_exit(process), 37)
            self.assertEqual(ps.call_args.kwargs["env"]["LC_ALL"], "C")
            self.assertEqual(ps.call_args.args[0], ["ps", "-axo", "pid=,ppid=,pgid=,stat="])


class PosixFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="posix-probe-")
        self.root = Path(self.temporary.name)
        self.addCleanup(self.temporary.cleanup)

    def script(self, body):
        path = self.root / ("owned-" + str(len(list(self.root.iterdir()))))
        path.write_text(f"#!{sys.executable}\n" + body + "\n", encoding="utf-8")
        path.chmod(0o700)
        return path

    def app(self, extra="", *, metadata_pid="os.getpid()", finish=True):
        return self.script(f"""import json, os, pathlib, time
out = pathlib.Path(os.environ['PERF_OUTPUT_DIR'])
index = int(os.environ['PERF_LAUNCH_INDEX'])
prepare = os.environ['PERF_PREPARE_ONLY'] == '1'
while not (out / 'launch.json').exists(): time.sleep(.01)
if not prepare:
    while not (out / 'samples.csv').exists() or len((out / 'samples.csv').read_text().splitlines()) < 2:
        time.sleep(.01)
fixture_id = 'synthetic-v4-pdf-cases:' + 'a'*64
identity = {bindings.BINDINGS!r}[os.environ['PERF_BINDING_MODE']]
meta = {{'type':'meta', 'schemaVersion':2, 'protocolVersion':2, 'pid':{metadata_pid},
         'launchIndex':index, 'buildMode':'profile', 'scenarioSet':os.environ['PERF_SCENARIO_SET'],
         'preparationOnly':prepare, 'fixtureId':fixture_id}}
meta.update(bindingMode=identity['bindingMode'], probeTarget=identity['probeTarget'])
end = {{'type':'done', 'launchIndex':index, 'status':'passed'}}
{extra}
if {finish!r}:
    (out / 'phases.jsonl').write_text(json.dumps(meta)+'\\n'+json.dumps(end)+'\\n')
    result = {{'status':'passed', 'preparationOnly':prepare, 'fixtureId':fixture_id, 'error':None, 'testFailures':[]}}
    result.update(identity)
    pending = out / 'completion.pending'
    pending.write_text(json.dumps(result))
    pending.rename(out / 'completion.json')
while True: time.sleep(1)
""")


class PosixRunnerTest(PosixFixture):
    def test_owned_launch_records_real_identity_and_blanks_for_unavailable_metrics(self):
        directory = self.root / "run"
        result = runner.invoke_launch(self.app(), directory, self.root / "data",
                                      options(directory), resources.process_reader(), index=2)
        self.assertEqual(result, "synthetic-v4-pdf-cases:" + "a" * 64)
        launch = runner.read_json(directory / "launch.json")
        self.assertTrue(launch["completedBeforeTermination"])
        with (directory / "samples.csv").open() as source:
            rows = list(csv.DictReader(source))
        self.assertGreaterEqual(len(rows), 1)
        self.assertEqual(rows[0]["pid"], str(launch["pid"]))
        self.assertEqual(rows[0]["identity_start_ticks"], launch["identityStartTicks"])
        for field in ("priv_mb", "handles", "tree_age_ms"):
            self.assertEqual(rows[0][field], "")
        self.assertTrue(runner.read_json(directory / "samples.csv.status.json")["complete"])
        with self.assertRaises(ChildProcessError):
            os.waitid(os.P_PID, launch["pid"], os.WEXITED | os.WNOHANG | os.WNOWAIT)

    def test_framework_completion_is_bound_to_the_owned_target(self):
        directory = self.root / "framework"
        result = runner.invoke_launch(self.app(), directory, self.root / "data",
                                      options(directory, binding_mode="framework"),
                                      resources.process_reader(), index=0)
        self.assertEqual(result, "synthetic-v4-pdf-cases:" + "a" * 64)
        completion = runner.read_json(directory / "completion.json")
        self.assertEqual(completion["bindingClass"], "WidgetsFlutterBinding")
        bad = self.root / "wrong-binding"
        with self.assertRaisesRegex(ValueError, "binding identity"):
            runner.invoke_launch(self.app(extra="identity['bindingMode']='integration'"),
                                 bad, self.root / "data-bad",
                                 options(bad, binding_mode="framework"),
                                 resources.process_reader(), index=0)
        self.assertFalse(runner.read_json(bad / "samples.csv.status.json")["complete"])

    def test_framework_cli_cannot_silently_run_the_full_integration_workload(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            runner.arguments(["--binding-mode", "framework", "--scenario-set", "all"])
        parsed = runner.arguments(["--binding-mode", "framework", "--scenario-set", "pdf-book-view"])
        self.assertEqual(parsed.binding_mode, "framework")
        self.assertEqual(parsed.scenario_set, "pdf-book-view")
        with self.assertRaises(ValueError):
            runner.run(options(self.root / "invalid", binding_mode="framework", scenario_set="all"))

    def test_process_metadata_cannot_claim_a_different_pid(self):
        directory = self.root / "run"
        with self.assertRaisesRegex(RuntimeError, "owned launch"):
            runner.invoke_launch(self.app(metadata_pid="os.getpid()+1"), directory, self.root / "data",
                                 options(directory), resources.process_reader(), index=0)
        self.assertFalse(runner.read_json(directory / "samples.csv.status.json")["complete"])
        self.assertTrue((directory / "phases.jsonl").exists())

    def test_malformed_journal_is_a_failure_with_preserved_evidence(self):
        directory = self.root / "run"
        with self.assertRaisesRegex(RuntimeError, "Invalid phase journal"):
            runner.invoke_launch(self.app(extra="meta=[]"), directory, self.root / "data",
                                 options(directory), resources.process_reader(), index=0)
        self.assertFalse(runner.read_json(directory / "samples.csv.status.json")["complete"])

    def test_completion_and_journal_must_agree_on_success_identity_and_fixture(self):
        directory = self.root / "validation"
        directory.mkdir()
        completion = {"status": "passed", "preparationOnly": False, "error": None,
                      "testFailures": [], "fixtureId": "synthetic-v4-pdf-cases:" + "a" * 64}
        meta = {"type": "meta", "schemaVersion": 2, "protocolVersion": 2, "pid": 42,
                "launchIndex": 0, "buildMode": "profile", "scenarioSet": "pdf-reader",
                "preparationOnly": False, "fixtureId": "synthetic-v4-pdf-cases:" + "a" * 64}
        completion.update(bindings.binding_identity("integration"))
        meta.update(bindingMode="integration", probeTarget=runner.TARGET)
        end = {"type": "done", "status": "passed", "launchIndex": 0}

        def validate(result, records):
            runner.write_json(directory / "completion.json", result)
            (directory / "phases.jsonl").write_text("".join(json.dumps(row) + "\n" for row in records))
            return runner.validate_completion(directory, pid=42, index=0, preparation=False,
                                              mode="profile", scenario="pdf-reader")

        self.assertEqual(validate(completion, [meta, end]), "synthetic-v4-pdf-cases:" + "a" * 64)
        for result, records in (
            ([], [meta, end]), ({**completion, "testFailures": ["framework error"]}, [meta, end]),
            ({**completion, "preparationOnly": True}, [meta, end]),
            ({**completion, "fixtureId": "synthetic-v4-pdf-cases:" + "b" * 64}, [meta, end]),
            (completion, [{**meta, "pid": 42.0}, end]), (completion, [{**meta, "launchIndex": 1}, end]),
            (completion, [{**meta, "buildMode": "debug"}, end]), (completion, [meta]),
            (completion, [meta, end, end]), (completion, [meta, meta, end]),
            (completion, [meta, {**end, "status": "failed"}]),
        ):
            with self.subTest(result=result, records=records), self.assertRaises(RuntimeError):
                validate(result, records)
        for fixture_id in ("a" * 64, "synthetic-v3-pdf:" + "a" * 64,
                           "synthetic-v4-pdf-cases:" + "a" * 63,
                           "synthetic-v4-pdf-cases:" + "A" * 64):
            with self.subTest(fixture_id=fixture_id), self.assertRaises(RuntimeError):
                validate({**completion, "fixtureId": fixture_id}, [{**meta, "fixtureId": fixture_id}, end])

    def test_pid_reuse_stops_sampling_instead_of_combining_counters(self):
        directory = self.root / "run"
        reader = mock.Mock()
        reader.read.side_effect = [resources.ProcessObservation(11, 1, 4096),
                                   resources.ProcessObservation(12, 5, 8192)]
        with self.assertRaisesRegex(RuntimeError, "identity changed"):
            runner.invoke_launch(self.app(), directory, self.root / "data", options(directory), reader, index=0)
        status = runner.read_json(directory / "samples.csv.status.json")
        self.assertFalse(status["complete"])
        self.assertEqual(status["samples"], 0)
        self.assertEqual(status["errors"], 1)

    def test_timeout_retains_partial_evidence_and_leaves_an_unrelated_process_alone(self):
        directory = self.root / "run"
        outsider = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"],
                                    start_new_session=True)
        try:
            with self.assertRaisesRegex(TimeoutError, "exceeded"):
                runner.invoke_launch(self.app(finish=False), directory, self.root / "data",
                                     options(directory, timeout_seconds=.2), resources.process_reader(), index=0)
            self.assertIsNone(outsider.poll())
            self.assertTrue((directory / "samples.csv").exists())
            self.assertFalse(runner.read_json(directory / "launch.json")["completedBeforeTermination"])
        finally:
            outsider.terminate()
            outsider.wait(timeout=5)

    def test_sigterm_to_the_runner_closes_its_separate_app_group_and_keeps_partial_results(self):
        directory = self.root / "interrupted"
        executable = self.app(finish=False)
        code = f"""import signal, sys
from pathlib import Path
from tool.perf_probe import run_perf_probe_posix as runner
from tool.perf_probe.posix_resources import process_reader
from tool.perf_probe.test_perf_probe_posix import options
signal.signal(signal.SIGTERM, runner.interrupt)
out = Path({str(directory)!r})
try:
    runner.invoke_launch(Path({str(executable)!r}), out, out.parent / 'data',
                         options(out, timeout_seconds=30), process_reader(), index=0)
except runner.Interrupted as error:
    sys.exit(128 + error.signum)
"""
        controller = subprocess.Popen([sys.executable, "-B", "-c", code], cwd=runner.REPOSITORY,
                                      start_new_session=True)
        try:
            receipt = directory / "launch.json"
            deadline = time.monotonic() + 5
            while not receipt.exists() and controller.poll() is None and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertTrue(receipt.exists(), "Owned app did not start")
            controller.send_signal(signal.SIGTERM)
            self.assertEqual(controller.wait(timeout=5), 128 + signal.SIGTERM)
            launch = runner.read_json(receipt)
            self.assertFalse(launch["completedBeforeTermination"])
            self.assertFalse(runner.read_json(directory / "samples.csv.status.json")["complete"])
            with self.assertRaises((ProcessLookupError, FileNotFoundError)):
                resources.process_reader().read(launch["pid"])
        finally:
            if controller.poll() is None:
                controller.kill()
                controller.wait(timeout=5)

    def test_early_nonzero_exit_keeps_its_error_and_log(self):
        directory = self.root / "run"
        executable = self.script("import time; time.sleep(.05); print('actual failure', flush=True); raise SystemExit(37)")
        with self.assertRaisesRegex(RuntimeError, "before completion.*37"):
            runner.invoke_launch(executable, directory, self.root / "data",
                                 options(directory), resources.process_reader(), index=0)
        self.assertIn("actual failure", (directory / "stdout.log").read_text())
        self.assertFalse(runner.read_json(directory / "samples.csv.status.json")["complete"])

    def test_waitable_leader_is_not_reaped_before_group_cleanup(self):
        process = subprocess.Popen([sys.executable, "-c", "raise SystemExit(0)"], start_new_session=True)
        deadline = time.monotonic() + 5
        while runner.child_exit(process) is None and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertEqual(runner.child_exit(process), 0)
        original = os.killpg
        calls = []

        def inspect_owned(pid, signum):
            self.assertEqual(pid, process.pid)
            self.assertEqual(runner.child_exit(process), 0)
            calls.append(signum)
            return original(pid, signum)

        with mock.patch.object(runner.os, "killpg", side_effect=inspect_owned):
            runner.cleanup_group(process, grace=0)
        self.assertEqual(calls, [signal.SIGTERM, signal.SIGKILL])
        with self.assertRaises(ChildProcessError):
            runner.child_exit(process)

    def test_build_failure_and_timeout_keep_logs_and_stop_owned_children(self):
        log = self.root / "failure.log"
        with self.assertRaisesRegex(RuntimeError, r"\(37\)"):
            runner.run_logged([sys.executable, "-c", "print('build evidence'); raise SystemExit(37)"],
                              log, cwd=self.root, timeout=5)
        self.assertIn("build evidence", log.read_text())
        with self.assertRaises(TimeoutError):
            runner.run_logged([sys.executable, "-c", "import time; time.sleep(30)"],
                              self.root / "timeout.log", cwd=self.root, timeout=.05)

    def test_success_cleans_a_descendant_which_ignores_sigterm(self):
        pidfile = self.root / "descendant.pid"
        child = ("import os, pathlib, signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                 f"pathlib.Path({str(pidfile)!r}).write_text(str(os.getpid())); time.sleep(30)")
        parent = ("import pathlib, subprocess, sys, time; "
                  f"subprocess.Popen([sys.executable, '-c', {child!r}]); "
                  f"p=pathlib.Path({str(pidfile)!r})\n"
                  "while not p.exists(): time.sleep(.01)\n")
        runner.run_logged([sys.executable, "-c", parent], self.root / "children.log", cwd=self.root, timeout=5)
        pid = int(pidfile.read_text())
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            try:
                resources.process_reader().read(pid)
            except (ProcessLookupError, FileNotFoundError):
                return
            time.sleep(.01)
        self.fail("The owned descendant survived SIGKILL cleanup")

    def test_cold_and_warm_preparations_are_excluded_from_measured_launches(self):
        for cache in ("cold", "warm"):
            plan = list(runner.launch_plan(self.root, options(self.root, cache_state=cache, launches=3)))
            measured = [entry for entry in plan if entry[4]]
            self.assertEqual([entry[2] for entry in measured], [0, 1, 2])
            self.assertEqual(len(plan), 6 if cache == "cold" else 5)
            self.assertEqual(len({entry[1] for entry in measured}), 3 if cache == "cold" else 1)
            self.assertTrue(all(entry[2] == -1 for entry in plan if not entry[4]))

    def test_merge_omits_preparation_and_keeps_one_csv_header(self):
        launches = []
        for index in range(2):
            directory = self.root / f"launch-{index}"
            directory.mkdir()
            (directory / "phases.jsonl").write_text(json.dumps({"launchIndex": index}) + "\n")
            (directory / "samples.csv").write_text("pid,name\n" + f"{index},app\n")
            (directory / "samples.csv.errors.jsonl").write_text("")
            launches.append(directory)
        runner.merge_outputs(self.root, launches)
        self.assertEqual((self.root / "samples.csv").read_text(), "pid,name\n0,app\n1,app\n")
        self.assertEqual(len((self.root / "phases.jsonl").read_text().splitlines()), 2)

    def test_existing_output_and_symlink_are_never_reused(self):
        output = self.root / "old"
        output.mkdir()
        evidence = output / "report.json"
        evidence.write_text("previous report")
        with self.assertRaisesRegex(RuntimeError, "already exists"):
            runner.run(options(output))
        link = self.root / "link"
        link.symlink_to(output, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, "already exists"):
            runner.run(options(link))
        self.assertEqual(evidence.read_text(), "previous report")

    def test_macos_bundle_uses_plist_executable_and_rejects_escape(self):
        import plistlib
        contents = self.root / "build/macos/Build/Products/Profile/Example.app/Contents"
        (contents / "MacOS").mkdir(parents=True)
        executable = contents / "MacOS/Otzaria"
        executable.write_text("program")
        executable.chmod(0o700)
        with (contents / "Info.plist").open("wb") as file:
            plistlib.dump({"CFBundleExecutable": "Otzaria"}, file)
        self.assertEqual(runner.binary_path(self.root, "macos", "profile"), executable)
        with (contents / "Info.plist").open("wb") as file:
            plistlib.dump({"CFBundleExecutable": "../../outside"}, file)
        with self.assertRaises(RuntimeError):
            runner.binary_path(self.root, "macos", "profile")

    def test_existing_app_check_does_not_kill_or_select_other_users(self):
        uid = os.getuid()
        started = "Sun Nov 22 21:28:04 2026"
        with mock.patch.object(runner, "capture", return_value=f"19 1 {uid+1} S {started} /Applications/Otzaria\n"):
            runner.reject_existing_app()
        for state in ("R", "S+", "D", "T", "I", "?"):
            with self.subTest(state=state), mock.patch.object(
                    runner, "capture", return_value=f"20 7 {uid} {state} {started} /a spaced path/Otzaria\n"):
                observations = []
                with self.assertRaisesRegex(RuntimeError, "process 20"):
                    runner.reject_existing_app(observations)
                self.assertEqual(observations, [{
                    "pid": 20, "parentPid": 7, "state": state, "startedAtLocal": started,
                    "command": "/a spaced path/Otzaria", "decision": "refused-live-process",
                }])
        for state in ("Z", "Z+"):
            with self.subTest(state=state), mock.patch.object(
                    runner, "capture", return_value=f"20 1 {uid} {state} {started} otzaria\n"):
                observations = []
                runner.reject_existing_app(observations)
                self.assertEqual(observations[0]["decision"], "ignored-exited-zombie")

    def test_macos_guard_recognizes_native_executable_name(self):
        app = "/Applications/אוצריא.app/Contents/MacOS/אוצריא"
        line = f"20 7 {os.getuid()} S+ Sun Nov 22 21:28:04 2026 {app}\n"
        observations = []
        with (mock.patch.object(runner.sys, "platform", "darwin"),
              mock.patch.object(runner, "capture", return_value=line) as capture):
            with self.assertRaisesRegex(RuntimeError, "process 20"):
                runner.reject_existing_app(observations)
        self.assertEqual(observations[0]["command"], app)
        self.assertIn("LC_ALL=en_US.UTF-8", capture.call_args.args[0])

    def test_live_app_refusal_preserves_process_observation_in_failure_manifest(self):
        output = self.root / "blocked"
        line = f"20 7 {os.getuid()} S+ Sun Nov 22 21:28:04 2026 /Applications/Otzaria\n"
        with (mock.patch.object(runner, "capture", return_value=line),
              mock.patch.dict(os.environ, {"DISPLAY": ":test"}),
              contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO())):
            self.assertEqual(runner.run(options(output)), 1)
        manifest = runner.read_json(output / "manifest.json")
        self.assertEqual(manifest["status"], "failed")
        self.assertEqual(manifest["existingAppProcesses"][0]["state"], "S+")
        self.assertEqual(manifest["existingAppProcesses"][0]["parentPid"], 7)
        self.assertIn("state=S+", manifest["error"])

    @unittest.skipUnless(sys.platform == "linux", "prctl names the owned Linux child")
    def test_existing_app_guard_rejects_live_child_but_accepts_its_unreaped_zombie(self):
        child = subprocess.Popen([
            sys.executable, "-c",
            "import ctypes, os; "
            "assert ctypes.CDLL(None).prctl(15, b'otzaria', 0, 0, 0) == 0; "
            "os.write(1, b'ready'); os.read(0, 1); os._exit(0)",
        ], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        try:
            self.assertTrue(select.select([child.stdout], [], [], 5)[0])
            self.assertEqual(child.stdout.read(5), b"ready")
            with self.assertRaisesRegex(RuntimeError, f"process {child.pid}"):
                runner.reject_existing_app()
            self.assertIsNone(runner.child_exit(child))
            child.stdin.write(b"x")
            child.stdin.flush()
            deadline = time.monotonic() + 5
            while runner.child_exit(child) is None:
                self.assertLess(time.monotonic(), deadline)
                time.sleep(.01)
            self.assertEqual(runner.child_exit(child), 0)
            observations = []
            runner.reject_existing_app(observations)
            observed = next(item for item in observations if item["pid"] == child.pid)
            self.assertTrue(observed["state"].startswith("Z"))
            self.assertEqual(observed["parentPid"], os.getpid())
            self.assertEqual(observed["decision"], "ignored-exited-zombie")
            self.assertEqual(runner.child_exit(child), 0)
        finally:
            child.kill()
            child.wait(timeout=5)
            child.stdin.close()
            child.stdout.close()

    def test_graphics_observations_exclude_display_serial_numbers_and_do_not_invent_missing_data(self):
        data = {"SPDisplaysDataType": [{"sppci_model": "Apple test GPU", "spdisplays_vendor": "Apple",
                                         "spdisplays_ndrvs": [{"serial-number": "not-for-artifacts"}]}]}
        with mock.patch.object(runner, "capture", return_value=json.dumps(data)):
            result = runner.graphics_metadata("macos")
        self.assertEqual(result["availability"], "collected")
        self.assertNotIn("not-for-artifacts", json.dumps(result))
        with mock.patch.object(runner, "capture", side_effect=FileNotFoundError("no glxinfo")):
            result = runner.graphics_metadata("linux")
        self.assertEqual(result["availability"], "unavailable")
        self.assertNotIn("values", result)

    def test_cli_ranges_and_supported_cases_are_explicit(self):
        for arguments in (("--warmup", "-1"), ("--repetitions", "0"), ("--launches", "31"),
                          ("--timeout-seconds", "59"), ("--mode", "debug")):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                runner.arguments(arguments)
        parsed = runner.arguments(["--scenario-set", "pdf-book-view", "--pdf-case", "space name.json"])
        self.assertEqual(parsed.scenario_set, "pdf-book-view")
        self.assertTrue(parsed.pdf_case.is_absolute())


class SourceProvenanceTest(unittest.TestCase):
    def test_real_git_changes_are_visible_and_dirty_never_becomes_clean_again(self):
        with tempfile.TemporaryDirectory(prefix="posix-source-") as temporary:
            root = Path(temporary)
            git = ["git", "-C", str(root)]
            runner.capture(git + ["init", "-q"])
            tracked = root / "tracked.txt"
            tracked.write_text("baseline\n")
            (root / "modified.txt").write_text("baseline\n")
            runner.capture(git + ["add", "tracked.txt", "modified.txt"])
            runner.capture(git + ["-c", "user.name=Probe", "-c", "user.email=probe@example.invalid",
                                  "commit", "-qm", "baseline"])
            manifest = {}
            runner.source_provenance(root, manifest, "beforeBuild")
            self.assertFalse(manifest["dirty"])
            tracked.rename(root / "renamed.txt")
            (root / "modified.txt").write_text("changed content must not appear in reports\n")
            (root / "untracked.txt").write_text("untracked contents must not appear in reports")
            runner.capture(git + ["add", "-A", "--", "tracked.txt", "renamed.txt"])
            runner.source_provenance(root, manifest, "afterBuild")
            self.assertTrue(manifest["dirty"])
            status = "\n".join(manifest["sourceProvenance"]["afterBuild"]["statusPorcelain"])
            self.assertIn("tracked.txt -> renamed.txt", status)
            self.assertIn(" M modified.txt", status)
            self.assertIn("?? untracked.txt", status)
            self.assertNotIn("untracked contents", json.dumps(manifest))
            self.assertNotIn("changed content", json.dumps(manifest))
            runner.capture(git + ["reset", "--hard", "HEAD"])
            (root / "untracked.txt").unlink()
            runner.source_provenance(root, manifest, "afterRuns")
            self.assertEqual(manifest["sourceProvenance"]["afterRuns"]["statusPorcelain"], [])
            self.assertTrue(manifest["dirty"])


class OrchestrationTest(PosixFixture):
    def setUp(self):
        super().setUp()
        self.repository = self.root / "checkout"
        self.repository.mkdir()
        runner.capture(["git", "init", "-q", str(self.repository)])
        (self.repository / "source.txt").write_text("source\n")
        runner.capture(["git", "-C", str(self.repository), "add", "source.txt"])
        runner.capture(["git", "-C", str(self.repository), "-c", "user.name=Probe",
                        "-c", "user.email=probe@example.invalid", "commit", "-qm", "source"])

    def measured_run(self, *, build_fails=False, bad_report=False, missing_scheduler=False, **overrides):
        output = self.root / "result"
        args = options(output, **overrides)
        executable = self.app()
        commands = []
        actual_capture = runner.capture
        engine = mock.Mock()
        engine.identity = {"bundleSha256": "a" * 64, "bytes": 123}
        engine.path = self.root / "bundled-engine-contract"
        engine.observe_loaded.side_effect = lambda pid, **kwargs: {"pid": pid, "identity": engine.identity}
        self.engine = engine

        def capture(command, **kwargs):
            if command[0] == "flutter":
                return json.dumps({"frameworkRevision": "locked-test-sdk"})
            if command[0] == "ps":
                return ""
            return actual_capture(command, **kwargs)

        def logged(command, log, **kwargs):
            commands.append(command)
            log.write_text("tool output retained\n")
            if command[:2] == ["flutter", "build"] and build_fails:
                raise RuntimeError("build failed (37)")
            if command[:2] == ["dart", "tool/perf_probe/prepare_pdf_case.dart"]:
                Path(command[3]).write_text(Path(command[2]).read_text())
            if command[:2] == ["dart", "tool/perf_probe/analyze.dart"]:
                manifest = runner.read_json(output / "manifest.json")
                runner.write_json(output / "report.json", {
                    "complete": not bad_report, "successful": manifest["status"] == "passed" and not bad_report,
                    "metadata": {**manifest, "settings": bindings.binding_identity(args.binding_mode)},
                    "notes": [] if missing_scheduler else [{
                        "name": "framework.scheduler_contract", "launchIndex": index,
                        "frameworkScheduler": {
                            "status": "passed",
                            "source": "Timer -> SchedulerBinding.scheduleFrame -> postFrameCallback",
                            "deferredFrameDelivered": True, "nativePlatformDispatcher": True,
                            "bindingClass": "WidgetsFlutterBinding", "requestedAtUs": 25,
                            "completedAtUs": 50, "frameTimestampUs": 400,
                        },
                    } for index in range(args.launches)],
                })

        with (mock.patch.object(runner, "capture", side_effect=capture),
              mock.patch.object(runner, "run_logged", side_effect=logged),
              mock.patch.object(runner, "binary_path", return_value=executable),
              mock.patch.object(runner, "BundledFlutterEngine", return_value=engine),
              mock.patch.dict(os.environ, {"DISPLAY": ":test-contract"}),
              contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO())):
            code = runner.run(args, repository=self.repository)
        return code, runner.read_json(output / "manifest.json"), commands

    def test_complete_warm_run_builds_once_prepares_separately_and_keeps_only_measured_records(self):
        case = self.root / "case.json"
        case.write_text('{"schemaVersion":1,"source":{"kind":"generated","pageCount":600}}')
        baseline = self.root / "baseline"
        code, manifest, commands = self.measured_run(cache_state="warm", launches=2,
                                                     pdf_case=case, baseline=baseline)
        self.assertEqual(code, 0)
        self.assertEqual(manifest["status"], "passed")
        self.assertFalse(manifest["dirty"])
        self.assertEqual(manifest["sampling"]["scope"], "owned-root-process-only")
        self.assertEqual(sum(command[:2] == ["flutter", "build"] for command in commands), 1)
        self.assertEqual(sum(command[:2] == ["dart", "tool/perf_probe/prepare_pdf_case.dart"] for command in commands), 1)
        self.assertEqual(commands[-1][-2:], ["--baseline", str(baseline)])
        output = self.root / "result"
        records = [json.loads(line) for line in (output / "phases.jsonl").read_text().splitlines()]
        self.assertEqual({entry["launchIndex"] for entry in records}, {0, 1})
        self.assertTrue((output / "prepare-data/completion.json").exists())
        self.assertTrue((output / "prepare-warm/completion.json").exists())
        self.assertEqual(manifest["engineIdentity"], self.engine.identity)
        self.assertTrue(manifest["engineEvidence"]["verifiedAfterRuns"])
        self.assertEqual(self.engine.observe_loaded.call_count, 4)
        self.engine.verify_unchanged.assert_called_once_with()
        for directory in ("prepare-data", "prepare-warm", "launch-000", "launch-001"):
            launch = runner.read_json(output / directory / "launch.json")
            evidence = runner.read_json(output / directory / "engine.json")
            self.assertTrue(launch["engineVerifiedAfterCompletion"])
            self.assertEqual(launch["pid"], evidence["pid"])

    def test_framework_build_selects_the_ordinary_binding_target_once(self):
        code, manifest, commands = self.measured_run(binding_mode="framework")
        self.assertEqual(code, 0)
        self.assertEqual(manifest["bindingMode"], "framework")
        target = bindings.binding_identity("framework")["probeTarget"]
        self.assertEqual(manifest["probeTarget"], target)
        builds = [command for command in commands if command[:2] == ["flutter", "build"]]
        self.assertEqual(len(builds), 1)
        self.assertIn(f"--target={target}", builds[0])
        self.assertNotIn(f"--target={runner.TARGET}", builds[0])

    def test_framework_run_rejects_missing_scheduler_evidence(self):
        code, manifest, _ = self.measured_run(binding_mode="framework", missing_scheduler=True)
        self.assertEqual(code, 1)
        self.assertEqual(manifest["status"], "failed")
        self.assertIn("scheduling check", manifest["analysisError"])

    def test_build_failure_still_records_after_build_provenance_and_never_launches(self):
        code, manifest, commands = self.measured_run(build_fails=True)
        self.assertEqual(code, 1)
        self.assertIn("build failed (37)", manifest["error"])
        self.assertEqual(set(manifest["sourceProvenance"]), {"beforeBuild", "afterBuild"})
        self.assertFalse(any((self.root / "result").glob("launch-*")))
        self.assertFalse(any(command[:2] == ["dart", "tool/perf_probe/analyze.dart"] for command in commands))

    def test_incomplete_report_cannot_turn_successful_child_exits_into_a_passed_run(self):
        code, manifest, _ = self.measured_run(bad_report=True)
        self.assertEqual(code, 1)
        self.assertEqual(manifest["status"], "failed")
        self.assertIn("complete successful", manifest["analysisError"])


class SmokeEvidenceTest(PosixFixture):
    def fixture(self, platform="linux"):
        sampling = {"scope": "owned-root-process-only", "descendantsObserved": False,
                    "displayMode": "xvfb" if platform == "linux" else "desktop",
                    "processReader": {"source": "/proc/<pid>/stat" if platform == "linux"
                                      else "proc_pid_rusage(RUSAGE_INFO_V0) + mach_timebase_info"}}
        metadata = {"schemaVersion": 2, "protocolVersion": 2, "status": "passed", "commit": "c" * 40,
                    "buildMode": "profile", "cacheState": "cold", "scenarioSet": "pdf-reader",
                    "bindingMode": "integration", "probeTarget": runner.TARGET,
                    "launchCount": 1, "warmup": 0, "repetitions": 1, "dirty": False,
                    "fixtureId": "synthetic-v4-pdf-cases:" + "f" * 64, "sampling": sampling,
                    "settings": {**bindings.binding_identity("integration"), "pdfReaderCase": smoke.CASE, "pdfPageCount": 600,
                                 "pdfLayout": "regularView", "scenarioSet": "pdf-reader",
                                 "resourceObservationVersion": 1, "pdfPostCloseIdleMs": 3000}}
        manifest = {**metadata, "sourceProvenance": {
            stage: {"statusPorcelain": [], "trackedDiffSummary": []}
            for stage in ("beforeBuild", "afterBuild", "afterRuns")}}
        scenarios = [{"name": f"pdf.reader.{name}", "status": "passed", "measured": 1,
                      "resources": {"treePrivatePeakBytes": None, "handlesPeak": None},
                      "imageBudget": {side: {"complete": True} for side in ("before", "after")}}
                     for name in ("open", "jump_forward", "jump_backward", "zoom", "close", "idle_after_close")]
        scenarios[0]["checkpointsMs"] = {"controller_ready": {"count": 1, "p50": 12.5},
                                         "final_image_ready": {"count": 1, "p50": 34.5}}
        scenarios[-1].update(measurementKind="resource-observation", observationWindowMs=3000, latencyMs=None)
        scenarios[-1]["resources"].update(sampledTicks=6, cpuIntervalCount=5, cpuCoveredMs=2500.0,
                                           treeWorkingSetPeakBytes=8192.0, cpuAverageCorePercent=0.0)
        scenarios.append({"name": "pdf.reader.first_preview_image", "status": "skipped", "measured": 0})
        report = {"complete": True, "successful": True, "comparisonEligibility": [],
                  "metadata": metadata, "scenarios": scenarios}
        runner.write_json(self.root / "manifest.json", manifest)
        runner.write_json(self.root / "report.json", report)
        runner.write_json(self.root / "pdf-case.json", {
            **smoke.CASE, "navigation": {key: value for key, value in smoke.CASE["navigation"].items()
                                        if key not in ("zoomPage", "zoomAnchor")}})
        # Only contract input: actual PDF decoding happens in the profile app smoke.
        pdf = self.root / "data/cold-0/pdf/reader-mixed.pdf"
        pdf.parent.mkdir(parents=True, exist_ok=True)
        pdf.write_bytes(b"synthetic contract bytes, not a native rendering test")
        primary = {"type": "meta", "pid": 42, "fixtureId": metadata["fixtureId"], "fixturePdf": {
            "source": "generated", "pages": 600, "mixedPageSizes": True,
            "sha256": hashlib.sha256(pdf.read_bytes()).hexdigest()}}
        (self.root / "phases.jsonl").write_text(json.dumps(primary) + "\n")
        return report, manifest

    def validate(self, platform="linux"):
        return smoke.validate(self.root, commit="c" * 40, platform=platform)

    def test_complete_linux_and_macos_evidence_preserves_unavailable_metrics(self):
        for platform in ("linux", "macos"):
            with self.subTest(platform=platform):
                self.fixture(platform)
                result = self.validate(platform)
                self.assertEqual(result["status"], "passed")
                self.assertEqual(result["checkpointsMs"]["final_image_ready"]["p50"], 34.5)
                self.assertIn("not performed", result["comparison"])

    def test_framework_smoke_requires_real_scheduler_identity_and_per_launch_evidence(self):
        report, manifest = self.fixture()
        identity = bindings.binding_identity("framework")
        for source in (report["metadata"], manifest):
            source.update(bindingMode=identity["bindingMode"], probeTarget=identity["probeTarget"])
        report["metadata"]["settings"].update(identity)
        note = {"type": "note", "name": "framework.scheduler_contract", "launchIndex": 0,
                "frameworkScheduler": {
                    "status": "passed",
                    "source": "Timer -> SchedulerBinding.scheduleFrame -> postFrameCallback",
                    "deferredFrameDelivered": True, "nativePlatformDispatcher": True,
                    "bindingClass": "WidgetsFlutterBinding",
                    "requestedAtUs": 25000, "completedAtUs": 30000, "frameTimestampUs": 45000}}
        report["notes"] = [note]
        runner.write_json(self.root / "manifest.json", manifest)
        runner.write_json(self.root / "report.json", report)
        self.assertEqual(smoke.validate(self.root, commit="c" * 40, platform="linux",
                                        binding_mode="framework")["bindingMode"], "framework")
        with self.assertRaises(ValueError):
            self.validate()
        for notes in ([], [note, note], [{**note, "launchIndex": True}],
                      [{**note, "launchIndex": 1}]):
            with self.subTest(notes=notes), self.assertRaises(ValueError):
                bindings.validate_framework_scheduler(notes, 1)
        for key in note["frameworkScheduler"]:
            invalid = json.loads(json.dumps(note))
            invalid["frameworkScheduler"].pop(key)
            with self.subTest(missing=key), self.assertRaises(ValueError):
                bindings.validate_framework_scheduler([invalid], 1)
        for key, value in (("completedAtUs", 1), ("requestedAtUs", True),
                           ("deferredFrameDelivered", 1), ("nativePlatformDispatcher", False)):
            invalid = json.loads(json.dumps(note))
            invalid["frameworkScheduler"][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                bindings.validate_framework_scheduler([invalid], 1)
        for key in identity:
            invalid = dict(identity)
            invalid.pop(key)
            with self.subTest(identity=key), self.assertRaises(ValueError):
                bindings.validate_binding_identity(invalid, "framework")

    def test_dirty_missing_or_wrong_source_evidence_is_rejected(self):
        mutations = (
            lambda report, manifest: manifest.update(dirty=True),
            lambda report, manifest: report["metadata"].update(dirty=True),
            lambda report, manifest: report.update(comparisonEligibility=["unverified_worktree"]),
            lambda report, manifest: manifest.update(commit="d" * 40),
            lambda report, manifest: manifest.update(warmup=False),
            lambda report, manifest: manifest["sourceProvenance"].pop("afterRuns"),
            lambda report, manifest: manifest["sourceProvenance"]["afterBuild"].update(statusPorcelain=[" M code.dart"]),
        )
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                report, manifest = self.fixture()
                mutate(report, manifest)
                runner.write_json(self.root / "report.json", report)
                runner.write_json(self.root / "manifest.json", manifest)
                with self.assertRaises((ValueError, KeyError)):
                    self.validate()

    def test_changed_pdf_bytes_and_wrong_case_actions_are_rejected(self):
        self.fixture()
        (self.root / "data/cold-0/pdf/reader-mixed.pdf").write_bytes(b"different corpus")
        with self.assertRaisesRegex(ValueError, "PDF hash"):
            self.validate()
        self.fixture()
        case = runner.read_json(self.root / "pdf-case.json")
        case["navigation"]["forwardPage"] = 449
        runner.write_json(self.root / "pdf-case.json", case)
        with self.assertRaisesRegex(ValueError, "Prepared PDF case"):
            self.validate()

    def test_missing_or_different_binding_frame_policy_is_rejected(self):
        for policy in (None, "benchmark", "benchmarkLive"):
            with self.subTest(policy=policy):
                report, _ = self.fixture()
                settings = report["metadata"]["settings"]
                if policy is None:
                    settings.pop("framePolicy")
                else:
                    settings["framePolicy"] = policy
                runner.write_json(self.root / "report.json", report)
                with self.assertRaisesRegex(ValueError, "binding identity"):
                    self.validate()

    def test_missing_skipped_duplicate_actions_or_incomplete_budget_are_rejected(self):
        mutations = (
            lambda rows: rows.pop(1),
            lambda rows: rows.append(rows[0]),
            lambda rows: rows[1].update(status="skipped"),
            lambda rows: rows[2].update(measured=0),
            lambda rows: rows[3]["imageBudget"]["after"].update(complete=False),
        )
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                report, _ = self.fixture()
                mutate(report["scenarios"])
                runner.write_json(self.root / "report.json", report)
                with self.assertRaises(ValueError):
                    self.validate()

    def test_reversed_checkpoints_invented_private_bytes_and_idle_latency_are_rejected(self):
        mutations = (
            lambda rows: rows[0]["checkpointsMs"]["final_image_ready"].update(p50=1),
            lambda rows: rows[0]["checkpointsMs"]["controller_ready"].update(p50=float("nan")),
            lambda rows: rows[0]["resources"].update(treePrivatePeakBytes=0),
            lambda rows: rows[0]["resources"].update(handlesPeak=0),
            lambda rows: rows[-2].update(latencyMs={"p50": 3000}),
            lambda rows: rows[-2].update(observationWindowMs=1000),
        )
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                report, _ = self.fixture()
                mutate(report["scenarios"])
                runner.write_json(self.root / "report.json", report)
                with self.assertRaises(ValueError):
                    self.validate()

    def test_idle_requires_actual_cpu_and_rss_samples_but_allows_measured_zero_cpu(self):
        self.fixture()
        self.assertEqual(self.validate()["idleResources"]["cpuAverageCorePercent"], 0.0)
        for field, value in (("sampledTicks", 0), ("sampledTicks", 1), ("cpuIntervalCount", 0),
                             ("cpuCoveredMs", 0), ("treeWorkingSetPeakBytes", None),
                             ("cpuAverageCorePercent", None), ("cpuAverageCorePercent", float("nan"))):
            with self.subTest(field=field, value=value):
                report, _ = self.fixture()
                report["scenarios"][-2]["resources"][field] = value
                runner.write_json(self.root / "report.json", report)
                with self.assertRaisesRegex(ValueError, "idle window"):
                    self.validate()



class MultiWindowBindingContractTest(unittest.TestCase):
    def test_native_windows_require_framework_at_both_entrypoints(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "native-output"
            cli = ["--output", str(output), "--scenario-set", "pdf-multi-window"]
            with self.assertRaises(SystemExit):
                runner.arguments(cli)
            self.assertFalse(output.exists())
            args = runner.arguments([*cli, "--binding-mode", "framework"])
            self.assertEqual(args.scenario_set, "pdf-multi-window")
            self.assertEqual(args.binding_mode, "framework")
            args.binding_mode = "integration"
            with self.assertRaisesRegex(ValueError, "requires the framework"):
                runner.run(args)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
