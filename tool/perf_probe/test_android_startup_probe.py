import copy
import hashlib
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import socket
import threading
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("android_startup", Path(__file__).with_name("android_startup_probe.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def sample_config(scenario="noOpen", mode="native"):
    return next(c for c in probe.trial_plan("campaign-testing", [scenario], 1, 5000, "profile") if c["prewarmMode"] == mode)


def sample_report(config):
    entries = 0 if config["scenario"] == "noEnabled" else 1
    native = entries if config["prewarmMode"] == "native" else 0
    measurement = {
        "startupTimeline": {"revealMs": 120, "marks": [{"name": "reveal:immediate:Null", "atMs": 100}]},
        "registeredEnabledPlugins": entries,
        "revealMsAtPrewarmInvocation": [120] if entries else [],
        "prewarm": {"invocations": entries, "nativeInvocations": native, "pending": False,
                    "attemptsTruncated": False,
                    "attempts": [{"status": "ok" if native else "bypassedForProbe",
                                  "nativeCalled": bool(native), "settingsMatchAndroidDefaults": True}] if entries else []},
        "open": None, "javascriptPolls": 0, "resources": {"live": 0, "backgroundLive": 0},
        "nativeMainThreadResponsiveness": {"availability": "notCollected", "value": None},
        "nativeCpu": {"availability": "notCollected", "value": None},
        "overlap": "notRequested",
    }
    if config["scenario"] in ("foreground", "background", "overlap"):
        background = config["scenario"] == "background"
        measurement["javascriptPolls"] = 3
        instance = "instance-" + config["runId"]
        measurement["resources"] = {
            "registered": 0 if background else 1, "live": 0 if background else 1,
            "backgroundLive": 1 if background else 0, "detailsTruncated": False,
            "instances": [] if background else [{"pluginId": "org.otzaria.android-startup-fixture",
                                                 "instanceId": instance, "live": True}],
        }
        measurement["open"] = {"instanceId": instance,
                               "host": "PluginBackgroundHost" if background else "PluginTabPage", "document": {
            "boots": 1, "sdkBooted": True, "runMode": "background" if background else "foreground",
            "pluginId": "org.otzaria.android-startup-fixture", "twoAnimationFrames": not background,
            "eventRunId": config["runId"] if background else None, "eventCount": 1 if background else 0,
        }}
    return {"schemaVersion": 1, "config": config, "package": probe.PACKAGE, "pid": 123,
            "bootId": "boot-" + config["runId"], "buildMode": config["buildMode"],
            "sourceRevision": "a" * 40, "sourceDirty": False, "flutterVersion": "3.47.7",
            "fixtureIdentity": "b" * 64, "physicalDeviceAcceptance": False,
            "viewport": {"widthPhysical": 1080, "heightPhysical": 1920, "devicePixelRatio": 3},
            "nativePrewarmCalls": native, "appMainCalled": True,
            "appSettingsInitializedBeforeMain": False,
            "previousFixtureLaunches": 0 if config["fixtureState"] == "prepared" else 1,
            "measurement": measurement, "status": "passed", "integrationTestsPassed": True,
            "error": None, "testFailures": []}


def sample_trial(config):
    return {"config": config, "report": sample_report(config), "apkSha256": "c" * 64,
            "deviceIdentity": {"fingerprint": "test-device"},
            "providerAfterMeasurement": "test.provider, 123", "previousProcessExitObserved": True}


class AndroidStartupContracts(unittest.TestCase):
    def test_plan_uses_one_fixture_per_mode_and_alternates_pairs(self):
        plan = probe.trial_plan("campaign-testing", ["noOpen", "overlap"], 3, 5000, "profile")
        self.assertEqual(len(plan), 12)
        for scenario in ("noOpen", "overlap"):
            runs = [c for c in plan if c["scenario"] == scenario]
            self.assertEqual([c["prewarmMode"] for c in runs], ["bypass", "native", "native", "bypass", "bypass", "native"])
            self.assertEqual([c["fixtureState"] for c in runs], ["prepared", "prepared", "reused", "reused", "reused", "reused"])
            self.assertEqual(len({c["fixtureId"] for c in runs}), 2)
        self.assertEqual(len({c["runId"] for c in plan}), len(plan))

    def test_only_valid_identifiers_and_report_names_reach_adb(self):
        config = sample_config()
        path = probe.report_path(config, "completion.json")
        self.assertTrue(path.startswith("files/android-webview-startup-probe/"))
        for value in ("../escape", "/absolute", "x;touch bad", "x$(id)xx", "x\nunsafe", "x" * 65):
            with self.subTest(value=value), self.assertRaises(ValueError):
                probe.report_path(dict(config, runId=value), "completion.json")
        with self.assertRaises(ValueError):
            probe.report_path(config, "../../preferences")
        for scenarios in (["foreground", "foreground"], ["arbitrary"], []):
            with self.assertRaises(ValueError):
                probe.trial_plan("campaign-testing", scenarios, 1, 5000, "profile")

    def test_production_apk_is_rejected_before_installation(self):
        valid = f"package: name='{probe.PACKAGE}' versionCode='1'\nlaunchable-activity: name='{probe.ACTIVITY}'\napplication-debuggable\n"
        self.assertEqual(probe.inspect_apk_badging(valid)["package"], probe.PACKAGE)
        for invalid in (valid.replace(probe.PACKAGE, "org.otzaria.otzaria"),
                        valid.replace(probe.ACTIVITY, "another.Activity"),
                        valid.replace("application-debuggable", ""),
                        valid + "package: name='another.package'\n"):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                probe.inspect_apk_badging(invalid)

    def test_runner_never_installs_or_touches_device_when_apk_package_is_wrong(self):
        class FakeRunner(probe.Runner):
            def command(self, argv, **kwargs):
                if argv[1:3] == ["--version", "--machine"]:
                    out = b'{"frameworkVersion":"3.47.7"}'
                elif argv[:2] == ["git", "rev-parse"]:
                    out = b"a" * 40
                elif argv[1:3] == ["dump", "badging"]:
                    out = f"package: name='org.otzaria.otzaria'\nlaunchable-activity: name='{probe.ACTIVITY}'\napplication-debuggable\n".encode()
                else:
                    out = b""
                return probe.subprocess.CompletedProcess(argv, 0, out, b"")

            def adb(self, *args, **kwargs):
                raise AssertionError(f"Unsafe device action: {args}")

        with tempfile.TemporaryDirectory() as directory:
            args = probe.argparse.Namespace(output=Path(directory) / "reports", flutter="flutter", mode="profile")
            runner = FakeRunner(args)
            runner.target = "android-arm64"
            with patch.object(probe.shutil, "which", return_value="aapt2"), self.assertRaises(ValueError):
                runner.build()

    def test_runner_installs_the_direct_flavor_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "build/app/outputs/flutter-apk/app-direct-profile.apk"
            apk.parent.mkdir(parents=True)
            apk.write_bytes(b"direct probe APK")
            apk.with_name("app-profile.apk").write_bytes(b"stale unflavored APK")
            calls = []

            class FakeRunner(probe.Runner):
                def command(self, argv, **kwargs):
                    calls.append(argv)
                    if argv[1:3] == ["--version", "--machine"]:
                        out = b'{"frameworkVersion":"3.47.7"}'
                    elif argv[:2] == ["git", "rev-parse"]:
                        out = b"a" * 40
                    elif argv[1:3] == ["dump", "badging"]:
                        out = (f"package: name='{probe.PACKAGE}'\n"
                               f"launchable-activity: name='{probe.ACTIVITY}'\n"
                               "application-debuggable\n").encode()
                    else:
                        out = b""
                    return probe.subprocess.CompletedProcess(argv, 0, out, b"")

                def adb(self, *args, **kwargs):
                    calls.append(["adb", *args])
                    return probe.subprocess.CompletedProcess(args, 0, b"", b"")

            args = probe.argparse.Namespace(output=root / "reports", flutter="flutter", mode="profile")
            runner = FakeRunner(args)
            runner.target = "android-arm64"
            with patch.object(probe, "ROOT", root), patch.object(probe.shutil, "which", return_value="aapt2"):
                runner.build()
            build = next(argv for argv in calls if argv[:3] == ["flutter", "build", "apk"])
            self.assertEqual(build[build.index("--flavor") + 1], "direct")
            self.assertIn(["aapt2", "dump", "badging", str(apk)], calls)
            self.assertIn(["adb", "install", "-r", str(apk)], calls)
            self.assertEqual(runner.apk_hash, probe.hashlib.sha256(apk.read_bytes()).hexdigest())

    def test_host_pss_requires_exact_process_and_preserves_measured_zero(self):
        raw = f"** MEMINFO in pid 123 [{probe.PACKAGE}] **\nTOTAL PSS: 0 TOTAL RSS: 8192\n"
        self.assertEqual(probe.host_pss(raw, 123)["value"], 0)
        self.assertEqual(probe.host_pss(raw, 123)["availability"], "collected")
        for invalid in (raw.replace("123", "124"), raw.replace(probe.PACKAGE, "renderer"),
                        raw.replace("TOTAL PSS:", "TOTAL SWAP PSS:"),
                        raw + "TOTAL PSS: 42\n", "TOTAL PSS: 42\n"):
            result = probe.host_pss(invalid, 123)
            self.assertEqual(result["availability"], "unavailable")
            self.assertIsNone(result["value"])
            self.assertIsNone(result["completeEngineCoverage"])

    def test_complete_actual_contract_accepts_every_scenario_and_mode(self):
        for scenario in probe.SCENARIOS:
            for mode in ("native", "bypass"):
                config = sample_config(scenario, mode)
                report = sample_report(config)
                probe.validate_report(report, config, 123, completion=True)
                report["status"] = "awaitingHostSample"
                probe.validate_report(report, config, 123, completion=False)

    def test_real_reused_foreground_report_with_restored_controller_is_rejected(self):
        # Original device bytes: run 42412886014, artifact 13591145642, trial dd8c997f1a694e8189e9bf8c24429112.
        raw = Path(__file__).with_name("fixtures").joinpath("android_startup_foreground_reused.json").read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),
                         "c99e72642d9315af1c1fc683906be1eca7e079c744c72f02d9b4377cf4de119b")
        report = probe.json.loads(raw)
        self.assertEqual(report["status"], "passed")
        self.assertEqual(report["config"]["fixtureState"], "reused")
        self.assertEqual(report["measurement"]["resources"]["live"], 2)
        with self.assertRaisesRegex(ValueError, "exactly one foreground WebView"):
            probe.validate_report(report, report["config"], report["pid"], completion=True)

    def test_clean_foreground_and_overlap_accept_prepared_and_reused_fixtures(self):
        for scenario in ("foreground", "overlap"):
            for mode in ("native", "bypass"):
                for state in ("prepared", "reused"):
                    config = dict(sample_config(scenario, mode), fixtureState=state)
                    report = sample_report(config)
                    with self.subTest(scenario=scenario, mode=mode, state=state):
                        probe.validate_report(report, config, 123, completion=True)
                        report["status"] = "awaitingHostSample"
                        probe.validate_report(report, config, 123, completion=False)

    def test_foreground_census_must_identify_only_the_requested_instance(self):
        changes = [
            lambda m: m.update(resources=None),
            lambda m: m["resources"].pop("registered"),
            lambda m: m["resources"].update(registered=2),
            lambda m: m["resources"].update(registered=True),
            lambda m: m["resources"].update(live=0),
            lambda m: m["resources"].update(live=2),
            lambda m: m["resources"].update(live=1.0),
            lambda m: m["resources"].update(backgroundLive=1),
            lambda m: m["resources"].update(backgroundLive=False),
            lambda m: m["resources"].update(detailsTruncated=True),
            lambda m: m["resources"].update(instances=[]),
            lambda m: m["resources"]["instances"].append(copy.deepcopy(m["resources"]["instances"][0])),
            lambda m: m["resources"]["instances"][0].update(instanceId="another-instance"),
            lambda m: m["resources"]["instances"][0].update(pluginId="another.plugin"),
            lambda m: m["resources"]["instances"][0].update(live=False),
            lambda m: m["open"].pop("instanceId"),
            lambda m: m["open"].update(host="PluginBackgroundHost"),
        ]
        for scenario in ("foreground", "overlap"):
            config = sample_config(scenario)
            for completion in (False, True):
                for index, change in enumerate(changes):
                    report = sample_report(config)
                    report["status"] = "passed" if completion else "awaitingHostSample"
                    change(report["measurement"])
                    with self.subTest(scenario=scenario, completion=completion, change=index), self.assertRaises(ValueError):
                        probe.validate_report(report, config, 123, completion=completion)

    def test_foreground_requires_the_empty_fixture_at_startup_reveal(self):
        invalid = [None, [], [{"name": "reveal:immediate:ToolTab"}],
                   [{"name": "reveal:immediate:Null"}, {"name": "reveal:immediate:ToolTab"}],
                   [{"name": "reveal:immediate:Null"}, {"name": "reveal:immediate:Null"}],
                   [{"name": 17}], ["reveal:immediate:Null"]]
        for scenario in ("foreground", "overlap"):
            config = sample_config(scenario)
            for completion in (False, True):
                for marks in invalid:
                    report = sample_report(config)
                    report["status"] = "passed" if completion else "awaitingHostSample"
                    report["measurement"]["startupTimeline"]["marks"] = marks
                    with self.subTest(scenario=scenario, completion=completion, marks=marks), self.assertRaises(ValueError):
                        probe.validate_report(report, config, 123, completion=completion)

    def test_false_success_and_cross_run_reports_are_rejected(self):
        config = sample_config()
        changes = [
            lambda r: r.update(pid=124), lambda r: r.update(pid=True),
            lambda r: r.update(package="org.otzaria.otzaria"),
            lambda r: r.update(config=dict(config, runId="another-run")),
            lambda r: r.update(buildMode="debug"), lambda r: r.update(status="failed"),
            lambda r: r.update(integrationTestsPassed=False), lambda r: r.update(error="native error"),
            lambda r: r.update(testFailures=["lost SDK callback"]), lambda r: r.update(physicalDeviceAcceptance=True),
            lambda r: r.update(sourceRevision=""), lambda r: r.update(fixtureIdentity=""),
            lambda r: r.update(appMainCalled=False), lambda r: r.update(previousFixtureLaunches=2),
            lambda r: r.update(appSettingsInitializedBeforeMain=True),
            lambda r: r["viewport"].update(devicePixelRatio=float("nan")),
            lambda r: r["measurement"].update(javascriptPolls=1),
            lambda r: r["measurement"]["resources"].update(backgroundLive=1),
            lambda r: r["measurement"]["prewarm"].update(nativeInvocations=2),
            lambda r: r["measurement"]["prewarm"].update(invocations=True),
            lambda r: r["measurement"]["prewarm"]["attempts"][0].update(settingsMatchAndroidDefaults=False),
            lambda r: r["measurement"].update(nativeCpu={"availability": "collected", "value": 0}),
        ]
        for index, change in enumerate(changes):
            report = sample_report(config)
            change(report)
            with self.subTest(index=index), self.assertRaises(ValueError):
                probe.validate_report(report, config, 123, completion=True)

    def test_background_requires_own_targeted_event_and_real_sdk(self):
        config = sample_config("background")
        for change in ({"eventRunId": "stale-run"}, {"eventCount": 2}, {"boots": 0},
                       {"sdkBooted": False}, {"runMode": "foreground"}):
            report = sample_report(config)
            report["measurement"]["open"]["document"].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                probe.validate_report(report, config, 123, completion=True)

    def test_comparison_rejects_fallback_unknown_provenance_and_missed_overlap(self):
        a, b = [sample_trial(c) for c in probe.trial_plan("campaign-testing", ["noOpen"], 1, 5000, "profile")]
        self.assertTrue(probe.pair_readiness(a, b)["comparableInputs"])
        self.assertFalse(probe.pair_readiness(a, b)["performanceAcceptance"])
        mutations = [lambda x: x.update(apkSha256="d" * 64),
                     lambda x: x.update(providerAfterMeasurement=None),
                     lambda x: x.update(previousProcessExitObserved=False),
                     lambda x: x["report"].update(sourceDirty=True),
                     lambda x: x["report"].update(bootId=a["report"]["bootId"]),
                     lambda x: x["report"]["measurement"].update(revealMsAtPrewarmInvocation=[None]),
                     lambda x: x["report"]["measurement"]["prewarm"].update(pending=True),
                     lambda x: x["report"]["measurement"]["prewarm"]["attempts"][0].update(status="timeout")]
        for change in mutations:
            altered = copy.deepcopy(b)
            change(altered)
            self.assertFalse(probe.pair_readiness(a, altered)["comparableInputs"])
        a, b = [sample_trial(c) for c in probe.trial_plan("campaign-testing", ["overlap"], 1, 5000, "profile")]
        b["report"]["measurement"]["overlap"] = "notObserved"
        self.assertIn("opening_did_not_overlap_real_prewarm", probe.pair_readiness(a, b)["reasons"])
        b["report"]["measurement"]["overlap"] = "observedAtRequest"
        self.assertTrue(probe.pair_readiness(a, b)["comparableInputs"])

    def test_missing_pss_does_not_become_a_zero_memory_comparison(self):
        a, b = [sample_trial(c) for c in probe.trial_plan("campaign-testing", ["noOpen"], 1, 5000, "profile")]
        self.assertFalse(probe.pair_readiness(a, b)["hostPssComparableInputs"])
        for trial in (a, b):
            trial["hostPss"] = {"availability": "collected", "value": 0}
        self.assertTrue(probe.pair_readiness(a, b)["hostPssComparableInputs"])
        b["hostPss"] = {"availability": "unavailable", "value": None}
        self.assertFalse(probe.pair_readiness(a, b)["hostPssComparableInputs"])

    def test_existing_output_is_not_modified(self):
        class Args:
            pass
        with tempfile.TemporaryDirectory() as directory:
            sentinel = Path(directory) / "keep.txt"
            sentinel.write_text("original")
            args = Args()
            args.output = Path(directory)
            with self.assertRaises(ValueError):
                probe.Runner(args)
            self.assertEqual(sentinel.read_text(), "original")
            self.assertEqual(list(Path(directory).iterdir()), [sentinel])


def signal_bytes(config, boundary, **changes):
    value = {"schemaVersion": 1, "campaignId": config["campaignId"], "runId": config["runId"],
             "bootId": "boot-" + config["runId"], "pid": 123, "event": boundary,
             "reportAvailable": boundary != "connected", "error": None, **changes}
    return probe.json.dumps(value).encode() + b"\n"


@contextmanager
def signal_channel(runner, config, *, connected=True):
    signals = probe.ReportSignals(runner, config)
    signals.connection, device = socket.socketpair()
    try:
        if connected:
            device.sendall(signal_bytes(config, "connected"))
            signals.receive(1)
        yield signals, device
    finally:
        device.close()
        signals.close()


class ReportReadContracts(unittest.TestCase):
    def make_runner(self, directory, replies):
        class WireRunner(probe.Runner):
            def adb(self, *args, **kwargs):
                self.calls.append(args)
                filename = Path(args[-1]).name
                code, stdout, stderr = replies[filename].pop(0)
                # ADB's raw exec service has no remote exit-status framing.
                if args[0] == "exec-out":
                    return probe.subprocess.CompletedProcess(args, 0, stdout + stderr, b"")
                return probe.subprocess.CompletedProcess(args, code, stdout, stderr)

        runner = WireRunner(probe.argparse.Namespace(output=Path(directory) / "reports"))
        runner.calls = []
        return runner

    def test_wait_is_idle_until_ready_signal_then_reads_exactly_once(self):
        config = sample_config()
        body = probe.json.dumps(sample_report(config)).encode()
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(directory, {"ready.json": [(0, body, b"")]})
            with signal_channel(runner, config) as (signals, device), ThreadPoolExecutor() as pool:
                entered = threading.Event()
                def wait():
                    entered.set()
                    return runner.wait_report(config, "ready.json", 2, signals)
                future = pool.submit(wait)
                try:
                    self.assertTrue(entered.wait(1))
                    with self.assertRaises(TimeoutError):
                        future.result(timeout=0.05)
                    self.assertEqual(runner.calls, [])
                finally:
                    device.sendall(signal_bytes(config, "ready"))
                self.assertEqual(future.result(timeout=1), probe.json.loads(body))
            self.assertEqual(len(runner.calls), 1)
            self.assertEqual(runner.calls[0][:2], ("shell", "-T"))

    def test_preparation_completes_without_a_ready_report(self):
        config = dict(sample_config(), operation="prepare")
        body = probe.json.dumps(sample_report(config)).encode()
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(directory, {"completion.json": [(0, body, b"")]})
            with signal_channel(runner, config) as (signals, device):
                device.sendall(signal_bytes(config, "completion"))
                device.shutdown(socket.SHUT_WR)
                self.assertEqual(runner.wait_report(config, "completion.json", 1, signals), probe.json.loads(body))
                signals.finish()
            self.assertEqual(len(runner.calls), 1)

    def test_early_completion_remains_a_failure_and_retains_the_report(self):
        config = sample_config()
        body = probe.json.dumps(dict(sample_report(config), status="failed", error="SDK boot failed")).encode()
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(directory, {"completion.json": [(0, body, b"")]})
            with signal_channel(runner, config) as (signals, device):
                device.sendall(signal_bytes(config, "completion"))
                with self.assertRaisesRegex(RuntimeError, "ended before the host sampling boundary"):
                    runner.wait_report(config, "ready.json", 1, signals)
            self.assertEqual((runner.output / config["runId"] / "completion.json").read_bytes(), body)
            self.assertEqual([Path(call[-1]).name for call in runner.calls], ["completion.json"])

    def test_malformed_published_report_fails_without_retry_and_keeps_raw_streams(self):
        config = sample_config()
        stdout, stderr = b"not-json\xff\n", b"unexpected remote diagnostic\n"
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(directory, {"completion.json": [(0, stdout, stderr)]})
            with signal_channel(runner, config) as (signals, device):
                device.sendall(signal_bytes(config, "completion"))
                with self.assertRaises((probe.json.JSONDecodeError, UnicodeDecodeError)):
                    runner.wait_report(config, "completion.json", 1, signals)
            folder = runner.output / config["runId"]
            self.assertEqual((folder / "completion.json.read.stdout").read_bytes(), stdout)
            self.assertEqual((folder / "completion.json.read.stderr").read_bytes(), stderr)
            self.assertEqual(probe.json.loads((folder / "completion.json.read.json").read_text())["exitCode"], 0)
            self.assertEqual(len(runner.calls), 1)

    def test_signalled_missing_report_is_an_error_and_retains_remote_exit_status(self):
        config = sample_config()
        error = b"cat: completion.json: No such file or directory\n"
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(directory, {"completion.json": [(1, b"", error)]})
            with signal_channel(runner, config) as (signals, device):
                device.sendall(signal_bytes(config, "completion"))
                with self.assertRaisesRegex(RuntimeError, r"could not be read \(1\)"):
                    runner.wait_report(config, "completion.json", 1, signals)
            folder = runner.output / config["runId"]
            self.assertEqual((folder / "completion.json.read.stderr").read_bytes(), error)
            self.assertEqual(probe.json.loads((folder / "completion.json.read.json").read_text())["exitCode"], 1)
            self.assertEqual(len(runner.calls), 1)

    def test_timeout_eof_and_unpublished_failure_do_not_probe_report_files(self):
        config = sample_config()
        for mode in ("timeout", "eof", "failure"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                runner = self.make_runner(directory, {})
                with signal_channel(runner, config) as (signals, device):
                    if mode == "eof":
                        device.shutdown(socket.SHUT_WR)
                    elif mode == "failure":
                        device.sendall(signal_bytes(config, "completion", reportAvailable=False, error="original native error"))
                    error = {"timeout": TimeoutError, "eof": EOFError, "failure": RuntimeError}[mode]
                    with self.assertRaises(error) as raised:
                        runner.wait_report(config, "ready.json", 0.01, signals)
                    if mode == "failure":
                        self.assertIn("original native error", str(raised.exception))
                self.assertEqual(runner.calls, [])

    def test_report_must_match_signalled_run_and_boot_even_for_failed_completion(self):
        config = sample_config()
        for change in ({"config": dict(config, runId="another-run")}, {"bootId": "another-boot"},
                       {"pid": 124}, {"package": "org.otzaria.otzaria"}):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                body = probe.json.dumps(dict(sample_report(config), status="failed", **change)).encode()
                runner = self.make_runner(directory, {"completion.json": [(0, body, b"")]})
                with signal_channel(runner, config) as (signals, device):
                    device.sendall(signal_bytes(config, "completion"))
                    with self.assertRaisesRegex(ValueError, "does not match"):
                        runner.wait_report(config, "ready.json", 1, signals)


class SignalContracts(unittest.TestCase):
    def test_fragmented_messages_share_one_connection_and_require_terminal_eof(self):
        config = sample_config()
        with signal_channel(None, config, connected=False) as (signals, device):
            combined = signal_bytes(config, "connected") + signal_bytes(config, "ready") + signal_bytes(config, "completion")
            device.sendall(combined[:11])
            device.sendall(combined[11:])
            device.shutdown(socket.SHUT_WR)
            self.assertEqual([signals.receive(1)["event"] for _ in range(3)], ["connected", "ready", "completion"])
            signals.finish()

    def test_invalid_schema_identity_and_sequence_are_rejected(self):
        config = sample_config()
        changes = [{"schemaVersion": True}, {"schemaVersion": 2}, {"extra": 1},
                   {"campaignId": "other-campaign"}, {"runId": "other-run"},
                   {"bootId": "../escape"}, {"bootId": None}, {"pid": True}, {"pid": 0},
                   {"event": "ready"}, {"reportAvailable": True}, {"error": "early error"}]
        for change in changes:
            with self.subTest(change=change), signal_channel(None, config, connected=False) as (signals, device):
                device.sendall(signal_bytes(config, "connected", **change))
                with self.assertRaises(ValueError):
                    signals.receive(1)
        for body in (b"not-json\n", b"[]\n", b"x" * 4097):
            with self.subTest(body=body[:10]), signal_channel(None, config, connected=False) as (signals, device):
                device.sendall(body)
                with self.assertRaises(ValueError):
                    signals.receive(1)

    def test_duplicate_stale_and_out_of_order_boundaries_are_rejected(self):
        config = sample_config()
        for event, changes in (("connected", {}), ("ready", {"reportAvailable": False}),
                               ("ready", {"pid": 456}), ("ready", {"bootId": "another-boot"})):
            with self.subTest(event=event, changes=changes), signal_channel(None, config) as (signals, device):
                device.sendall(signal_bytes(config, event, **changes))
                with self.assertRaises(ValueError):
                    signals.receive(1)
        with signal_channel(None, config) as (signals, device):
            device.sendall(signal_bytes(config, "ready") * 2)
            signals.receive(1)
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                signals.receive(1)
        for extra in (b"extra", signal_bytes(config, "completion")):
            with self.subTest(extra=extra[:10]), signal_channel(None, config) as (signals, device):
                device.sendall(signal_bytes(config, "completion") + extra)
                signals.receive(1)
                with self.assertRaisesRegex(ValueError, "Extra data"):
                    signals.finish()

    def test_reverse_owns_only_one_ephemeral_port_and_closes_on_timeout(self):
        calls = []
        class Adb:
            def adb(self, *args, on_success=None, **_):
                calls.append(args)
                output = (f"(reverse) {signals.local} {signals.local}\n".encode()
                          if args == ("reverse", "--list") else b"")
                result = probe.subprocess.CompletedProcess(args, 0, output, b"")
                if on_success:
                    on_success(result)
                return result
        config = sample_config()
        signals = probe.ReportSignals(Adb(), config)
        try:
            runtime = signals.open()
            port = signals.listener.getsockname()[1]
            self.assertEqual(runtime, dict(config, signalPort=port))
            self.assertNotIn("signalPort", config)
            self.assertEqual(signals.listener.getsockname()[0], "127.0.0.1")
            self.assertEqual(calls[0], ("reverse", "--no-rebind", f"tcp:{port}", f"tcp:{port}"))
            with self.assertRaises(TimeoutError):
                signals.receive(0.01)
        finally:
            signals.close()
            signals.remove_reverse()
        self.assertEqual(calls[-1], ("reverse", "--remove", f"tcp:{port}"))
        self.assertEqual(signals.listener.fileno(), -1)


    def test_reverse_cleanup_respects_missing_replaced_or_ambiguous_mappings(self):
        for mappings, fails in (("", False),
                                ("(reverse) tcp:24680 tcp:9999\n", True),
                                ("(reverse) tcp:24680 tcp:12345\n" * 2, True)):
            with self.subTest(mappings=mappings):
                calls = []
                class Adb:
                    def adb(self, *args, on_success=None):
                        calls.append(args)
                        if on_success:
                            on_success(probe.subprocess.CompletedProcess(args, 0, mappings.encode(), b""))
                signals = probe.ReportSignals(Adb(), sample_config())
                signals.remote, signals.local = "tcp:24680", "tcp:12345"
                if fails:
                    with self.assertRaisesRegex(RuntimeError, "replaced"):
                        signals.remove_reverse()
                else:
                    signals.remove_reverse()
                    self.assertIsNone(signals.remote)
                self.assertEqual(calls, [("reverse", "--list")])

    def test_reverse_is_reclaimed_when_every_command_receipt_write_fails(self):
        calls = []
        receipt_error = OSError("command log disk full")
        with tempfile.TemporaryDirectory() as directory:
            runner = probe.Runner(probe.argparse.Namespace(
                output=Path(directory) / "reports", adb="adb", device="selected-device"))
            signals = probe.ReportSignals(runner, sample_config())
            def adb_result(argv, **_):
                args = tuple(argv[3:])
                calls.append(args)
                output = (f"(reverse) {signals.local} {signals.local}\n".encode()
                          if args == ("reverse", "--list") else b"")
                return probe.subprocess.CompletedProcess(argv, 0, output, b"")
            with patch.object(probe.subprocess, "run", side_effect=adb_result), \
                    patch.object(Path, "open", side_effect=receipt_error):
                with self.assertRaises(OSError) as raised:
                    with runner.cleanup(sample_config(), [("close_signal", signals.close),
                                                         ("remove_reverse", signals.remove_reverse)]):
                        signals.open()
            self.assertIs(raised.exception, receipt_error)
            self.assertEqual(calls[0], ("reverse", "--no-rebind", signals.local, signals.local))
            self.assertEqual(calls[1:], [("reverse", "--list"), ("reverse", "--remove", signals.local)])
            self.assertIsNone(signals.remote)
            self.assertEqual(signals.listener.fileno(), -1)

    def test_failed_allocation_never_claims_a_mapping(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = probe.Runner(probe.argparse.Namespace(
                output=Path(directory) / "reports", adb="adb", device="selected-device"))
            signals = probe.ReportSignals(runner, sample_config())
            failed = probe.subprocess.CompletedProcess([], 1, b"", b"reverse failed")
            with patch.object(probe.subprocess, "run", return_value=failed) as command:
                with self.assertRaisesRegex(RuntimeError, "reverse failed"):
                    with runner.cleanup(sample_config(), [("close_signal", signals.close),
                                                         ("remove_reverse", signals.remove_reverse)]):
                        signals.open()
            self.assertEqual(command.call_count, 1)
            self.assertIsNone(signals.remote)
            self.assertEqual(signals.listener.fileno(), -1)


class ReverseAllocationContracts(unittest.TestCase):
    class Listener:
        def __init__(self, port):
            self.port, self.closed = port, False
        def bind(self, address):
            assert address == ("127.0.0.1", 0)
        def listen(self, backlog):
            assert backlog == 1
        def getsockname(self):
            return ("127.0.0.1", self.port)
        def close(self):
            self.closed = True

    class Adb:
        # ADB's host allow-list uses the requested remote address, while adbd
        # stores tcp:0 allocations under the actual device port. Keep both.
        def __init__(self):
            self.allowed, self.mappings, self.occupied, self.calls = {}, {}, set(), []
            self.next_port = 46000
        def process(self, argv, **_):
            args = tuple(argv[3:])
            self.calls.append(args)
            output, error = b"", b""
            if args[:2] == ("reverse", "--no-rebind"):
                remote, local = args[2:]
                self.allowed.setdefault(remote, local)
                actual = remote
                if remote == "tcp:0":
                    actual = f"tcp:{self.next_port}"
                    self.next_port += 1
                    output = f"{actual[4:]}\n".encode()
                if actual in self.mappings:
                    error = b"adb: error: cannot rebind existing socket"
                elif actual in self.occupied:
                    error = b"adb: error: cannot bind listener: Address already in use"
                else:
                    self.mappings[actual] = local
            elif args == ("reverse", "--list"):
                output = "".join(f"(reverse) {remote} {local}\n"
                                 for remote, local in self.mappings.items()).encode()
            elif args[:2] == ("reverse", "--remove"):
                self.allowed.pop(args[2], None)
                self.mappings.pop(args[2])
            else:
                raise AssertionError(args)
            return probe.subprocess.CompletedProcess(argv, 1 if error else 0, output, error)
        def connect(self, port):
            local = self.mappings[f"tcp:{port}"]
            if local not in self.allowed.values():
                raise ConnectionResetError("ADB host rejects the new reverse target")

    def test_repeated_channels_remain_allowed_after_owned_mapping_cleanup(self):
        adb = self.Adb()
        adb.allowed["tcp:31000"] = adb.mappings["tcp:31000"] = "tcp:32000"
        listeners = [self.Listener(41001), self.Listener(41002)]
        with tempfile.TemporaryDirectory() as directory:
            runner = probe.Runner(probe.argparse.Namespace(
                output=Path(directory) / "reports", adb="adb", device="selected-device"))
            with patch.object(probe.subprocess, "run", side_effect=adb.process), \
                    patch.object(probe.socket, "socket", side_effect=listeners):
                for listener in listeners:
                    signals = probe.ReportSignals(runner, sample_config())
                    try:
                        config = signals.open()
                        adb.connect(config["signalPort"])
                    finally:
                        signals.close()
                        signals.remove_reverse()
                    self.assertTrue(listener.closed)
                    self.assertIsNone(signals.remote)
        self.assertEqual(adb.mappings, {"tcp:31000": "tcp:32000"})
        self.assertEqual(adb.allowed, {"tcp:31000": "tcp:32000"})

    def test_collisions_preserve_foreign_ports_and_retry_before_launch(self):
        for collision in ("mapping", "bound socket"):
            with self.subTest(collision=collision), tempfile.TemporaryDirectory() as directory:
                adb = self.Adb()
                if collision == "mapping":
                    adb.allowed["tcp:41001"] = adb.mappings["tcp:41001"] = "tcp:32000"
                else:
                    adb.occupied.add("tcp:41001")
                listeners = [self.Listener(41001), self.Listener(41002)]
                runner = probe.Runner(probe.argparse.Namespace(
                    output=Path(directory) / "reports", adb="adb", device="selected-device"))
                signals = probe.ReportSignals(runner, sample_config())
                with patch.object(probe.subprocess, "run", side_effect=adb.process), \
                        patch.object(probe.socket, "socket", side_effect=listeners):
                    try:
                        config = signals.open()
                        self.assertTrue(listeners[0].closed)
                        self.assertEqual(config["signalPort"], 41002)
                        adb.connect(config["signalPort"])
                    finally:
                        signals.close()
                        signals.remove_reverse()
                self.assertTrue(all(listener.closed for listener in listeners))
                self.assertNotIn(("reverse", "--remove", "tcp:41001"), adb.calls)
                self.assertEqual(adb.mappings, {"tcp:41001": "tcp:32000"} if collision == "mapping" else {})
                if collision == "bound socket":
                    # A rejected bind may leave a host allow-list entry; reusing
                    # the same explicit port still targets the same listener.
                    adb.occupied.clear()
                    reused = probe.ReportSignals(runner, sample_config())
                    with patch.object(probe.subprocess, "run", side_effect=adb.process), \
                            patch.object(probe.socket, "socket", return_value=self.Listener(41001)):
                        try:
                            adb.connect(reused.open()["signalPort"])
                        finally:
                            reused.close()
                            reused.remove_reverse()
                    self.assertEqual(adb.allowed, {})

    def test_collision_retries_are_bounded_and_close_every_listener(self):
        adb = self.Adb()
        listeners = [self.Listener(41000 + i) for i in range(8)]
        adb.occupied.update(f"tcp:{listener.port}" for listener in listeners)
        with tempfile.TemporaryDirectory() as directory:
            runner = probe.Runner(probe.argparse.Namespace(
                output=Path(directory) / "reports", adb="adb", device="selected-device"))
            signals = probe.ReportSignals(runner, sample_config())
            with patch.object(probe.subprocess, "run", side_effect=adb.process), \
                    patch.object(probe.socket, "socket", side_effect=listeners):
                with self.assertRaisesRegex(RuntimeError, "8 attempts.*Address already in use"):
                    with runner.cleanup(sample_config(), [("close_signal", signals.close),
                                                         ("remove_reverse", signals.remove_reverse)]):
                        signals.open()
            self.assertIsNone(signals.remote)
        self.assertEqual(len(adb.calls), 8)
        self.assertTrue(all(listener.closed for listener in listeners))
        self.assertEqual(adb.mappings, {})

    def test_collision_receipt_failure_does_not_retry_or_remove_foreign_mapping(self):
        adb, listener = self.Adb(), self.Listener(41001)
        adb.allowed["tcp:41001"] = adb.mappings["tcp:41001"] = "tcp:32000"
        receipt = OSError("command receipt unavailable")
        with tempfile.TemporaryDirectory() as directory:
            runner = probe.Runner(probe.argparse.Namespace(
                output=Path(directory) / "reports", adb="adb", device="selected-device"))
            signals = probe.ReportSignals(runner, sample_config())
            with patch.object(probe.subprocess, "run", side_effect=adb.process), \
                    patch.object(probe.socket, "socket", return_value=listener), \
                    patch.object(Path, "open", side_effect=receipt):
                with self.assertRaises(OSError) as raised:
                    with runner.cleanup(sample_config(), [("close_signal", signals.close),
                                                         ("remove_reverse", signals.remove_reverse)]):
                        signals.open()
            self.assertIs(raised.exception, receipt)
            self.assertIsNone(signals.remote)
        self.assertTrue(listener.closed)
        self.assertEqual(len(adb.calls), 1)
        self.assertEqual(adb.mappings, {"tcp:41001": "tcp:32000"})

    def test_non_collision_failure_remains_primary_when_receipt_also_fails(self):
        listener = self.Listener(41001)
        failed = probe.subprocess.CompletedProcess([], 1, b"", b"device offline")
        with tempfile.TemporaryDirectory() as directory:
            runner = probe.Runner(probe.argparse.Namespace(
                output=Path(directory) / "reports", adb="adb", device="selected-device"))
            signals = probe.ReportSignals(runner, sample_config())
            with patch.object(probe.subprocess, "run", return_value=failed) as command, \
                    patch.object(probe.socket, "socket", return_value=listener), \
                    patch.object(Path, "open", side_effect=OSError("receipt unavailable")):
                with self.assertRaisesRegex(RuntimeError, "device offline"):
                    with runner.cleanup(sample_config(), [("close_signal", signals.close),
                                                         ("remove_reverse", signals.remove_reverse)]):
                        signals.open()
            self.assertEqual(command.call_count, 1)
            self.assertIsNone(signals.remote)
        self.assertTrue(listener.closed)


class CleanupContracts(unittest.TestCase):
    def test_adb_version_is_retained_before_a_device_failure(self):
        version = "Android Debug Bridge version 1.0.41\nVersion test-build"
        calls = []
        class UnavailableDevice(probe.Runner):
            def text(self, *args):
                calls.append(args)
                if args == ("version",):
                    return version
                raise RuntimeError("device unavailable")
        with tempfile.TemporaryDirectory() as directory:
            runner = UnavailableDevice(probe.argparse.Namespace(output=Path(directory) / "reports"))
            with self.assertRaisesRegex(RuntimeError, "device unavailable"):
                runner.run()
            self.assertEqual((runner.output / "adb-version.txt").read_text(), version + "\n")
            campaign = probe.json.loads((runner.output / "campaign.json").read_text())
            self.assertEqual(campaign["hostAdbVersion"], version)
            self.assertEqual(calls, [("version",), ("get-state",)])

    def test_launch_retains_original_exception_and_traceback_when_stop_also_fails(self):
        original = RuntimeError("original measurement failure")
        class FailedRunner(probe.Runner):
            def _launch(self, *_):
                raise original
            def stop_probe(self):
                raise OSError("cleanup force-stop failed")
        with tempfile.TemporaryDirectory() as directory:
            runner = FailedRunner(probe.argparse.Namespace(output=Path(directory) / "reports"))
            try:
                runner.launch(sample_config())
            except RuntimeError as error:
                self.assertIs(error, original)
                self.assertIn("_launch", [entry.name for entry in probe.traceback.extract_tb(error.__traceback__)])
            else:
                self.fail("Expected the original error")
            self.assertEqual([error["phase"] for error in runner.cleanup_errors], ["stop_probe"])

    def test_all_cleanup_actions_run_and_first_failure_wins(self):
        original = RuntimeError("native SDK failed")
        secondary = OSError("logcat failed")
        attempted = []
        def cleanup(name, error=None):
            def action():
                attempted.append(name)
                if error:
                    raise error
            return name, action
        for primary in (original, None):
            with self.subTest(primary=primary), tempfile.TemporaryDirectory() as directory:
                attempted.clear()
                runner = probe.Runner(probe.argparse.Namespace(output=Path(directory) / "reports"))
                with self.assertRaises(Exception) as raised:
                    with runner.cleanup(sample_config(), [cleanup("logcat", secondary), cleanup("stop", ValueError("stop failed")), cleanup("reverse")]):
                        if primary:
                            raise primary
                self.assertIs(raised.exception, primary or secondary)
                self.assertEqual(attempted, ["logcat", "stop", "reverse"])
                self.assertEqual([item["phase"] for item in runner.cleanup_errors], ["logcat", "stop"])
                self.assertTrue(all(item["traceback"] for item in runner.cleanup_errors))

    def test_campaign_keeps_first_error_and_cleanup_diagnostics(self):
        original = RuntimeError("native SDK failed")
        class FailedRunner(probe.Runner):
            def text(self, *args):
                return "device" if args == ("get-state",) else "x86_64"
            def build(self):
                def bad_log():
                    raise OSError("logcat failed")
                with self.cleanup(sample_config(), [("collect_log", bad_log)]):
                    raise original
        with tempfile.TemporaryDirectory() as directory:
            runner = FailedRunner(probe.argparse.Namespace(output=Path(directory) / "reports", mode="debug"))
            with self.assertRaises(RuntimeError) as raised:
                runner.run()
            self.assertIs(raised.exception, original)
            campaign = probe.json.loads((runner.output / "campaign.json").read_text())
            self.assertEqual(campaign["error"], "RuntimeError: native SDK failed")
            self.assertIn("raise original", campaign["errorTraceback"])
            self.assertEqual(campaign["cleanupErrors"][0]["phase"], "collect_log")
            self.assertEqual(campaign["hostReportTransport"], "persistentAdbReverseSocket")
            self.assertIsNone(campaign["hostReportPollIntervalMs"])
            write_text = Path.write_text
            def fail_campaign_write(path, *args, **kwargs):
                if path.name == "campaign.json":
                    raise OSError("disk full")
                return write_text(path, *args, **kwargs)
            with patch.object(Path, "write_text", fail_campaign_write):
                with self.assertRaises(RuntimeError) as raised:
                    runner.run()
            self.assertIs(raised.exception, original)
            self.assertEqual(runner.cleanup_errors[-1]["phase"], "write_campaign")


    def test_primary_survives_stop_stderr_and_campaign_write_failures_together(self):
        original = RuntimeError("original native failure")
        class FailedRunner(probe.Runner):
            def text(self, *args):
                return "device" if args == ("get-state",) else "x86_64"
            def build(self):
                self.launch(sample_config())
            def _launch(self, *_):
                raise original
            def stop_probe(self):
                raise OSError("force-stop failed")
        with tempfile.TemporaryDirectory() as directory:
            runner = FailedRunner(probe.argparse.Namespace(output=Path(directory) / "reports", mode="debug"))
            write_text = Path.write_text
            def fail_campaign(path, *args, **kwargs):
                if path.name == "campaign.json":
                    raise OSError("campaign disk full")
                return write_text(path, *args, **kwargs)
            with patch.object(Path, "write_text", fail_campaign), \
                    patch.object(probe.sys.stderr, "write", side_effect=BrokenPipeError("stderr closed")):
                try:
                    runner.run()
                except RuntimeError as error:
                    self.assertIs(error, original)
                    self.assertIn("_launch", [entry.name for entry in probe.traceback.extract_tb(error.__traceback__)])
                else:
                    self.fail("Expected the original failure")
            self.assertEqual([entry["phase"] for entry in runner.cleanup_errors],
                             ["stop_probe", "stop_probe:stderr", "write_campaign", "write_campaign:stderr"])
            self.assertTrue(all(entry["traceback"] for entry in runner.cleanup_errors))

    def test_command_failure_survives_broken_receipt_and_stderr(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = probe.Runner(probe.argparse.Namespace(output=Path(directory) / "reports"))
            failed = probe.subprocess.CompletedProcess([], 7, b"", b"original adb failure")
            with patch.object(probe.subprocess, "run", return_value=failed), \
                    patch.object(Path, "open", side_effect=OSError("receipt full")), \
                    patch.object(probe.sys.stderr, "write", side_effect=BrokenPipeError("stderr closed")):
                with self.assertRaisesRegex(RuntimeError, "original adb failure"):
                    runner.command(["adb", "version"])
            self.assertEqual([entry["phase"] for entry in runner.cleanup_errors],
                             ["write_command_log", "write_command_log:stderr"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
