import copy
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
        "startupTimeline": {"revealMs": 120}, "registeredEnabledPlugins": entries,
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
        measurement["open"] = {"document": {
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

    def test_missing_completion_is_polled_until_published(self):
        config = sample_config()
        body = b'{"status":"passed","label":"ready"}\n'
        with tempfile.TemporaryDirectory() as directory, patch.object(probe.time, "sleep"):
            runner = self.make_runner(directory, {"completion.json": [
                (1, b"", b"cat: completion.json: No such file or directory\n"),
                (0, body, b""),
            ]})
            self.assertEqual(runner.wait_report(config, "completion.json", 10), probe.json.loads(body))
            self.assertEqual(len(runner.calls), 2)
            self.assertTrue(all(call[:2] == ("shell", "-T") for call in runner.calls))

    def test_ready_waits_while_both_atomic_reports_are_absent(self):
        config = sample_config()
        missing = (1, b"", b"cat: No such file or directory\n")
        with tempfile.TemporaryDirectory() as directory, patch.object(probe.time, "sleep"):
            runner = self.make_runner(directory, {
                "ready.json": [missing, (0, b'{"status":"awaitingHostSample"}', b"")],
                "completion.json": [missing],
            })
            self.assertEqual(runner.wait_report(config, "ready.json", 10)["status"], "awaitingHostSample")
            self.assertEqual([Path(call[-1]).name for call in runner.calls],
                             ["ready.json", "completion.json", "ready.json"])

    def test_early_completion_remains_a_failure_and_retains_the_report(self):
        config = sample_config()
        body = b'{"status":"failed","error":"SDK boot failed"}\n'
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(directory, {
                "ready.json": [(1, b"", b"cat: No such file or directory\n")],
                "completion.json": [(0, body, b"")],
            })
            with self.assertRaisesRegex(RuntimeError, "ended before the host sampling boundary"):
                runner.wait_report(config, "ready.json", 10)
            self.assertEqual((runner.output / config["runId"] / "completion.json").read_bytes(), body)

    def test_malformed_published_report_fails_without_retry_and_keeps_raw_streams(self):
        config = sample_config()
        stdout, stderr = b"not-json\xff\n", b"unexpected remote diagnostic\n"
        with tempfile.TemporaryDirectory() as directory, patch.object(probe.time, "sleep") as sleep:
            runner = self.make_runner(directory, {"completion.json": [(0, stdout, stderr)]})
            with self.assertRaises((probe.json.JSONDecodeError, UnicodeDecodeError)):
                runner.wait_report(config, "completion.json", 10)
            folder = runner.output / config["runId"]
            self.assertEqual((folder / "completion.json.read.stdout").read_bytes(), stdout)
            self.assertEqual((folder / "completion.json.read.stderr").read_bytes(), stderr)
            self.assertEqual(probe.json.loads((folder / "completion.json.read.json").read_text())["exitCode"], 0)
            sleep.assert_not_called()
            self.assertEqual(len(runner.calls), 1)

    def test_absent_report_times_out_and_preserves_remote_failure(self):
        config = sample_config()
        error = b"cat: completion.json: No such file or directory\n"
        with tempfile.TemporaryDirectory() as directory, patch.object(probe.time, "sleep"), \
                patch.object(probe.time, "monotonic", side_effect=[0, 0, 2]):
            runner = self.make_runner(directory, {"completion.json": [(1, b"", error)]})
            with self.assertRaises(TimeoutError):
                runner.wait_report(config, "completion.json", 1)
            folder = runner.output / config["runId"]
            self.assertEqual((folder / "completion.json.read.stderr").read_bytes(), error)
            self.assertEqual(probe.json.loads((folder / "completion.json.read.json").read_text())["exitCode"], 1)
            self.assertFalse((folder / "completion.json").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
