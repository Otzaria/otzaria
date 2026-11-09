"""Controlled host/protocol negatives; these are not Android device results."""

import argparse
import base64
from contextlib import redirect_stderr
import copy
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
import tracemalloc
import unittest
from unittest.mock import patch

from tool.perf_probe import run_installed_plugin_android as probe


CAMPAIGN = "campaign-" + "a" * 32
BOOTSTRAP = {"protocol": 1, "campaignId": CAMPAIGN, "runId": "123-456", "pid": 123,
             "package": probe.PACKAGE, "port": 12345,
             "reportPath": "cache/otzaria-installed-probe-test/output/installed-plugin-report.json"}
DOCUMENT = {"pluginId": "controlled", "instanceId": "same-instance", "controllerObjectId": 7,
            "nativeViewId": "9", "documentToken": "same-document"}
LAUNCHER = "com.android.launcher3/com.android.launcher3.uioverrides.QuickstepLauncher"
COMMIT = "c" * 40


def dumpsys(*, foreground=True, token="abc", task=42):
    target = f"ActivityRecord{{{token} u0 {probe.COMPONENT} t{task}}}"
    home = f"ActivityRecord{{def u0 {LAUNCHER} t1}}"
    top = target if foreground else home
    return f"  * Hist #0: {target}\n  * Hist #0: {home}\n  topResumedActivity={top}\n  mResumedActivity: {top}\n"


def stat(*, ticks=1000):
    return "123 (process (name)) S " + " ".join(["0"] * 18 + [str(ticks)] + ["0"] * 10)


def event(sequence, action, payload=None):
    return {**{key: BOOTSTRAP[key] for key in probe.IDENTITY_KEYS},
            "sequence": sequence, "action": action,
            "payload": payload if payload is not None else {"identity": DOCUMENT}}


def report_fixture(evidence):
    phases = [{"name": name, "status": "passed"} for name in probe.REQUIRED_PHASES]
    phases.extend({"name": name, "status": "unsupported",
                   "reason": "Desktop window_manager action does not apply on android."}
                  for name in ("minimize", "hide"))
    background = next(phase for phase in phases if phase["name"] == "osBackground")
    background.update(before=dict(DOCUMENT), after=dict(DOCUMENT), lifecycleBeforeQuiet="paused", lifecycleAfterResume="resumed",
                      dispatcherBeforeQuiet="hidden", shownBeforeQuiet=False, discardCandidateBeforeQuiet=True,
                      dispatcherAfterResume="active", shownAfterResume=True,
                      sameControllerAfterResume=True, sameDocumentAfterResume=True, visibleStateMatches=True,
                      **evidence)
    return {"schemaVersion": 1, "status": "passed", "platform": "android", "buildMode": "debug",
            "pid": 123, "runId": "123-456", "commit": COMMIT, "physicalDeviceAcceptance": False,
            "policyRestored": True, "frameworkPassed": True, "testFailures": [], "errors": [], "contractErrors": [],
            "pinnedStore": {"commit": probe.STORE_COMMIT},
            "androidControl": {**{key: BOOTSTRAP[key] for key in probe.IDENTITY_KEYS}, "physicalProfileRelease": "notRun"},
            "platformMatrix": {os_name: {"status": "passed" if os_name == "android" else "notRun"}
                               for os_name in ("windows", "macos", "linux", "android", "ios")},
            "phases": phases,
            "quietWindows": [{"name": name, "probeJsCalls": 0, "probeNativeQueries": 0,
                              "productionTimersDisabled": False, "requestedMs": 1000, "elapsedMs": 1001.5}
                             for name in ("visibleIdle", "hiddenIdle", "osBackgroundIdle", "backgroundIdle", "closedIdle")],
            "restorations": [{"scenario": name, "sameInstanceId": True, "releasedByDispatcher": True,
                              "controllerAbsentAfterDiscard": True, "hostWidgetRemovedBeforeRestore": True,
                              "differentControllerObject": True, "differentDocument": True, "sdkBooted": True,
                              "visibleStateMatches": True, "before": {"documentToken": "old"},
                              "after": {"documentToken": "new"}}
                             for name in ("pressure", "count", "age", "store")],
            "protectedControls": [{"firstBlockingReason": name, "discardRequestId": "same-pressure-request",
                                   "sameControllerAfterRequest": True, "released": False}
                                  for name in ("noRestoreState", "unsavedChanges", "busyRpc", "contextMenu")]}


def completion(raw):
    return {"frameworkPassed": True, "reportBytes": len(raw), "reportSha256": hashlib.sha256(raw).hexdigest()}


def final_completion(raw):
    return {**{key: BOOTSTRAP[key] for key in probe.IDENTITY_KEYS}, "sequence": 4,
            "controlClosed": True, **completion(raw)}


class IdentityTests(unittest.TestCase):
    def test_native_records_and_process_start_time_are_observed(self):
        foreground = probe.activity_snapshot(dumpsys())
        background = probe.activity_snapshot(dumpsys(foreground=False))
        self.assertEqual(foreground["activity"], background["activity"])
        self.assertEqual(background["resumedActivity"]["component"], LAUNCHER)
        self.assertEqual(probe.process_identity(stat(), 123), {"pid": 123, "startTicks": 1000})
        self.assertEqual(probe.normalize_component("a.b/.Activity"), "a.b/a.b.Activity")

    def test_missing_ambiguous_activity_and_bad_proc_identity_fail(self):
        invalid = ["", dumpsys() + dumpsys(token="aaa"), dumpsys().replace("topResumedActivity=", "old=")
                   .replace("mResumedActivity:", "old=")]
        for raw in invalid:
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                probe.activity_snapshot(raw)
        for raw in ("", stat().replace("123 ", "124 ", 1), stat(ticks=0)):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                probe.process_identity(raw, 123)

    def test_pid_reuse_new_activity_and_new_task_cannot_masquerade_as_resume(self):
        original = {**probe.activity_snapshot(dumpsys()), "process": probe.process_identity(stat(), 123)}
        probe.require_native_state(original, original, foreground=True, launcher=LAUNCHER)
        background = {**probe.activity_snapshot(dumpsys(foreground=False)), "process": original["process"]}
        probe.require_native_state(background, original, foreground=False, launcher=LAUNCHER)
        for changed in ({**original, "process": {"pid": 123, "startTicks": 2000}},
                        {**original, **probe.activity_snapshot(dumpsys(token="ddd"))},
                        {**original, **probe.activity_snapshot(dumpsys(task=43))}):
            with self.subTest(changed=changed), self.assertRaises(RuntimeError):
                probe.require_native_state(changed, original, foreground=True, launcher=LAUNCHER)
        with self.assertRaises(ValueError):
            probe.require_native_state(original, original, foreground=False, launcher=LAUNCHER)
        with self.assertRaises(ValueError):
            probe.require_native_state(background, original, foreground=False, launcher="another/.Home")

    def test_apk_guard_rejects_production_and_non_debuggable_apks(self):
        raw = f"package: name='{probe.PACKAGE}' versionCode='1'\nlaunchable-activity: name='{probe.ACTIVITY}'\napplication-debuggable\n"
        self.assertTrue(probe.verify_apk(raw)["debuggable"])
        for invalid in (raw.replace(probe.PACKAGE, "org.otzaria.otzaria"),
                        raw.replace("application-debuggable", ""), raw.replace(probe.ACTIVITY, "another.Activity")):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                probe.verify_apk(invalid)

    def test_bootstrap_rejects_wrong_run_pid_or_private_path(self):
        self.assertEqual(probe.verify_bootstrap(BOOTSTRAP, CAMPAIGN), BOOTSTRAP)
        for key, value in (("pid", 124), ("runId", "old"), ("package", "org.otzaria.otzaria"),
                           ("campaignId", "old"), ("reportPath", "files/private.json"),
                           ("reportPath", "cache/../files/private.json"), ("port", 70000)):
            with self.subTest(key=key), self.assertRaises(ValueError):
                probe.verify_bootstrap({**BOOTSTRAP, key: value}, CAMPAIGN)

    def test_bootstrap_accepts_only_the_two_private_android_cache_roots(self):
        suffix = "otzaria-installed-probe-test/output/installed-plugin-report.json"
        for cache in ("cache", "code_cache"):
            valid = {**BOOTSTRAP, "reportPath": f"{cache}/{suffix}"}
            self.assertEqual(probe.verify_bootstrap(valid, CAMPAIGN), valid)
        for path in (f"/code_cache/{suffix}", f"files/{suffix}", f"external/code_cache/{suffix}",
                     f"code_cache/../cache/{suffix}", f"code_cache/./{suffix}",
                     f"code_cache/{suffix}/extra", f"code_cache/{suffix}\n",
                     f"code_cache\\{suffix}", "code_cache/otzaria-installed-probe-/output/installed-plugin-report.json"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                probe.verify_bootstrap({**BOOTSTRAP, "reportPath": path}, CAMPAIGN)


class ApkDigestTests(unittest.TestCase):
    def test_file_digest_is_exact_with_bounded_reads_and_closes_the_file(self):
        class BoundedFile(io.BytesIO):
            def read(self, size=-1):
                if size <= 0 or size > 1024 * 1024:
                    raise AssertionError("APK reads must have a bounded chunk size")
                return super().read(size)

        for data in (b"", b"small apk", bytes(range(256)) * 9000 + b"partial final chunk"):
            stream = BoundedFile(data)
            with self.subTest(size=len(data)), patch.object(Path, "open", return_value=stream) as opened, \
                    patch.object(Path, "read_bytes", side_effect=AssertionError("Unbounded APK read")):
                self.assertEqual(probe.file_sha256(Path("dedicated.apk")), hashlib.sha256(data).hexdigest())
                opened.assert_called_once_with("rb")
            self.assertTrue(stream.closed)

    def test_large_file_digest_has_bounded_python_memory(self):
        with tempfile.TemporaryDirectory() as temporary:
            apk = Path(temporary) / "large.apk"
            chunk = bytes(range(256)) * 4096
            expected = hashlib.sha256()
            with apk.open("wb") as stream:
                for _ in range(32):
                    stream.write(chunk)
                    expected.update(chunk)
            tracemalloc.start()
            try:
                actual = probe.file_sha256(apk)
                _, peak = tracemalloc.get_traced_memory()
            finally:
                tracemalloc.stop()
            self.assertEqual(actual, expected.hexdigest())
            self.assertLess(peak, 4 * 1024 * 1024)

    def test_file_digest_does_not_hide_read_errors(self):
        failure = OSError("APK read failed")
        with patch.object(Path, "open", side_effect=failure):
            with self.assertRaises(OSError) as result:
                probe.file_sha256(Path("dedicated.apk"))
        self.assertIs(result.exception, failure)


class ProtocolTests(unittest.TestCase):
    def test_identity_order_and_duration_are_bound_to_one_real_document(self):
        protocol = probe.Protocol(BOOTSTRAP, 1000)
        for invalid in (event(2, "home"), event(1, "resume"), {**event(1, "home"), "pid": 124},
                        event(1, "home", {"identity": {**DOCUMENT, "documentToken": ""}})):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                protocol.accept(invalid)
        protocol.accept(event(1, "home"))
        quiet = {"identity": DOCUMENT, "name": "osBackgroundIdle", "durationMs": 1000}
        for invalid in (event(1, "home"), event(2, "quiet", {**quiet, "durationMs": 999}),
                        event(2, "quiet", {**quiet, "identity": {**DOCUMENT, "documentToken": "replacement"}})):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                protocol.accept(invalid)
        protocol.accept(event(2, "quiet", quiet))
        protocol.accept(event(3, "resume"))
        protocol.accept(event(4, "complete", {}))
        with self.assertRaises(ValueError):
            protocol.accept(event(5, "complete", {}))

    def test_early_completion_is_retained_for_failure_validation(self):
        protocol = probe.Protocol(BOOTSTRAP, 1000)
        protocol.accept(event(1, "complete", {"frameworkPassed": False}))
        self.assertEqual(protocol.actions, ["complete"])


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.evidence = {"home": {"fixture": "home"}, "hostQuiet": {"fixture": "quiet"}, "resume": {"fixture": "resume"}}
        self.report = report_fixture(self.evidence)

    def validate(self, report=None, **overrides):
        raw = json.dumps(self.report if report is None else report).encode()
        return probe.verify_report(raw, {**completion(raw), **overrides}, BOOTSTRAP, self.evidence, COMMIT)

    def test_complete_controlled_report_is_accepted(self):
        self.assertEqual(self.validate()["status"], "passed")

    def test_desktop_visibility_requires_explicit_unsupported_with_a_reason(self):
        for name in ("minimize", "hide"):
            for key, value in (("status", "passed"), ("status", "failed"), ("status", "notRun"),
                               ("status", None), ("reason", None), ("reason", ""),
                               ("reason", "  \n\t"), ("reason", True), ("reason", [])):
                report = copy.deepcopy(self.report)
                phase = next(item for item in report["phases"] if item["name"] == name)
                phase[key] = value
                with self.subTest(phase=name, key=key, value=value), self.assertRaisesRegex(ValueError, "Desktop visibility"):
                    self.validate(report)
            report = copy.deepcopy(self.report)
            report["phases"] = [item for item in report["phases"] if item["name"] != name]
            with self.subTest(missing=name), self.assertRaisesRegex(ValueError, "Desktop visibility"):
                self.validate(report)

    def test_old_android_not_run_report_cannot_pass_the_new_gate(self):
        original = copy.deepcopy(self.report)
        original.pop("androidControl")
        next(phase for phase in original["phases"] if phase["name"] == "osBackground")["status"] = "notRun"
        with self.assertRaises(ValueError):
            self.validate(original)

    def test_framework_failure_and_report_byte_replacement_are_not_success(self):
        for changes in ({"frameworkPassed": False}, {"reportBytes": 1}, {"reportSha256": "0" * 64}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.validate(**changes)

    def test_final_completion_requires_same_identity_command_closed_control_and_digest(self):
        raw = json.dumps(self.report).encode()
        preliminary = completion(raw)
        message = event(4, "complete", preliminary)
        receipt = final_completion(raw)
        probe.verify_completion(receipt, message, preliminary)
        for key, value in (("campaignId", "previous"), ("pid", 124), ("runId", "123-stale"),
                           ("package", "org.otzaria.otzaria"), ("protocol", 2), ("sequence", 3),
                           ("controlClosed", False), ("frameworkPassed", False),
                           ("reportBytes", len(raw) + 1), ("reportSha256", "0" * 64)):
            with self.subTest(key=key), self.assertRaises(ValueError):
                probe.verify_completion({**receipt, key: value}, message, preliminary)

    def test_android_hidden_state_and_observed_identity_cannot_be_replaced_by_claimed_booleans(self):
        for key, value in (("dispatcherBeforeQuiet", "suspendedConfirmed"), ("shownBeforeQuiet", True),
                           ("lifecycleBeforeQuiet", "resumed"), ("dispatcherAfterResume", "hidden"),
                           ("home", {"unrelated": "old observation"}),
                           ("after", {**DOCUMENT, "documentToken": "new document"})):
            report = copy.deepcopy(self.report)
            phase = next(value for value in report["phases"] if value["name"] == "osBackground")
            phase[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.validate(report)

    def test_original_restoration_protected_state_quiet_and_platform_gates_remain_required(self):
        mutations = [
            lambda r: r.update(status="failed"),
            lambda r: r.update(frameworkPassed=False),
            lambda r: r.update(runId="123-stale"),
            lambda r: r.update(physicalDeviceAcceptance=True),
            lambda r: r.update(policyRestored=False),
            lambda r: r["pinnedStore"].update(commit="wrong"),
            lambda r: r["platformMatrix"]["ios"].update(status="passed"),
            lambda r: r["androidControl"].update(physicalProfileRelease="passed"),
            lambda r: r["restorations"].pop(),
            lambda r: r["restorations"][0].update(differentDocument=False),
            lambda r: r["restorations"][0]["after"].update(documentToken="old"),
            lambda r: r["protectedControls"][0].update(released=True),
            lambda r: r["protectedControls"][0].update(discardRequestId="other"),
            lambda r: r["quietWindows"][0].update(probeJsCalls=1),
            lambda r: r["quietWindows"][0].update(probeNativeQueries=1),
            lambda r: r["quietWindows"][0].update(elapsedMs=999),
            lambda r: r["quietWindows"][0].update(productionTimersDisabled=True),
        ]
        for mutate in mutations:
            report = copy.deepcopy(self.report)
            mutate(report)
            with self.subTest(mutation=mutations.index(mutate)), self.assertRaises(ValueError):
                self.validate(report)


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="android-installed-host-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.fake_adb = self.directory / "adb"
        self.fake_adb.write_text(f"#!{sys.executable}\n" + textwrap.dedent('''
            import json
            from pathlib import Path
            import sys
            root = Path(__file__).parent
            state = json.loads((root / 'state.json').read_text())
            args = sys.argv[1:]
            assert args[:2] == ['-s', 'emulator-5554'], args
            args = args[2:]
            package = 'org.otzaria.otzaria.installedprobe'
            component = package + '/org.otzaria.otzaria.MainActivity'
            home = 'com.android.launcher3/com.android.launcher3.uioverrides.QuickstepLauncher'
            if args == ['shell', 'pidof', package]:
                print('123')
            elif args[:4] == ['shell', 'cmd', 'package', 'resolve-activity']:
                assert ['--user', '0'] == args[5:7]
                if state.get('homeMissing'):
                    print('No activity found')
                else:
                    if '--components' not in args:
                        print('priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=true')
                    print(state.get('resolvedHome', home))
            elif args == ['shell', '-T', 'run-as', package, 'cat', '/proc/123/stat']:
                print('123 (probe) S ' + ' '.join(['0'] * 18 + ['1000'] + ['0'] * 10))
            elif args == ['shell', 'dumpsys', 'activity', 'activities']:
                target = 'ActivityRecord{' + state['token'] + ' u0 ' + component + ' t42}'
                launcher = 'ActivityRecord{def u0 ' + state.get('actualHome', home) + ' t1}'
                print('* Hist #0: ' + target)
                print('* Hist #0: ' + launcher)
                print('topResumedActivity=' + (target if state['foreground'] else launcher))
            elif args == ['shell', 'input', 'keyevent', 'KEYCODE_HOME']:
                report = root / 'output/host-report.json'
                state['resolutionAtHome'] = json.loads(report.read_text()).get('homeResolution') if report.exists() else None
                state['foreground'] = False
            elif args[:4] == ['shell', 'am', 'start', '-W']:
                if '--activity-single-top' in args:
                    assert '--activity-reorder-to-front' in args
                else:
                    assert args == ['shell', 'am', 'start', '-W', '-n', component, '-a', 'android.intent.action.MAIN']
                state['foreground'] = True
                if state.get('replaceOnResume'):
                    state['token'] = 'bbb'
            elif args[:5] == ['shell', '-T', 'run-as', package, 'cat'] and args[-1].endswith('/completion.json'):
                receipt = root / 'completion.json'
                if not receipt.exists():
                    sys.exit(1)
                sys.stdout.buffer.write(receipt.read_bytes())
            elif args[:5] == ['shell', '-T', 'run-as', package, 'cat']:
                sys.stdout.buffer.write((root / 'report.json').read_bytes())
            elif args == ['forward', '--list']:
                print(state.get('forward', ''))
            elif args[:2] == ['forward', '--remove']:
                assert state.get('forward', '').split()[1] == args[2]
                state['forward'] = ''
            else:
                raise AssertionError(args)
            (root / 'state.json').write_text(json.dumps(state))
        '''))
        self.fake_adb.chmod(0o700)
        (self.directory / "state.json").write_text(json.dumps({"foreground": True, "token": "abc"}))
        self.runner = probe.Runner(argparse.Namespace(output=self.directory / "output", device="emulator-5554",
                                                      adb=str(self.fake_adb), quiet_ms=1000, flutter="unused"))
        self.runner.bootstrap = BOOTSTRAP
        self.runner.campaign = CAMPAIGN
        self.runner.launcher = LAUNCHER
        self.runner.result["sourceCommit"] = COMMIT
        self.runner.original = self.runner.wait_native(foreground=True)

    def test_build_verifies_and_installs_the_direct_flavor_output(self):
        root = self.directory / "source"
        (root / ".dart_tool").mkdir(parents=True)
        (root / "pubspec.lock").write_bytes(b"controlled lockfile\n")
        (root / ".dart_tool/package_config.json").write_text(json.dumps({"packages": [
            {"name": name, "rootUri": (root / "native" / name).as_uri()} for name in probe.PACKAGES
        ]}))
        sdk = self.directory / "flutter-sdk"
        flutter = str(sdk / "bin/flutter")
        self.runner.args.flutter = flutter
        apk = root / "build/app/outputs/flutter-apk/app-direct-debug.apk"
        apk.parent.mkdir(parents=True)
        stale = apk.with_name("app-debug.apk")
        stale.write_bytes(b"stale unflavored APK")
        payload = b"new direct installed-probe APK"
        badging = (f"package: name='{probe.PACKAGE}'\n"
                   f"launchable-activity: name='{probe.ACTIVITY}'\napplication-debuggable\n").encode()
        device = {("get-state",): "device", ("shell", "getprop", "ro.kernel.qemu"): "1",
                  ("shell", "am", "get-current-user"): "0",
                  ("shell", "getprop", "ro.product.cpu.abi"): "x86_64"}
        calls = []

        def command(argv, **kwargs):
            calls.append(argv)
            out = b""
            if argv == [flutter, "--version", "--machine"]:
                out = json.dumps({"frameworkVersion": "3.47.7", "frameworkRevision": COMMIT}).encode()
            elif argv[:3] == [flutter, "build", "apk"]:
                self.assertIn("--flavor", argv)
                self.assertEqual(argv[argv.index("--flavor") + 1], "direct")
                self.assertEqual(kwargs["env"]["ORG_GRADLE_PROJECT_otzariaInstalledProbe"], "true")
                self.assertNotIn("ORG_GRADLE_PROJECT_otzariaStartupProbe", kwargs["env"])
                apk.write_bytes(payload)
            elif argv == ["git", "rev-parse", "HEAD"]:
                out = COMMIT.encode()
            elif argv == ["git", "rev-parse", "HEAD^{tree}"]:
                out = b"d" * 40
            elif argv[:2] == ["git", "-C"] and argv[3:] == ["rev-parse", "HEAD"]:
                out = (COMMIT if argv[2] == str(sdk) else probe.NATIVE_PIN).encode()
            elif argv[:3] == ["aapt2", "dump", "badging"]:
                self.assertEqual(argv[3], str(apk))
                self.assertEqual(apk.read_bytes(), payload)
                out = badging
            elif argv == [flutter, "pub", "get", "--enforce-lockfile"]:
                pass
            elif argv[:1] == ["git"] and argv[-3:] == ["status", "--porcelain", "--untracked-files=no"]:
                pass
            else:
                self.fail(f"Unexpected build command: {argv}")
            return subprocess.CompletedProcess(argv, 0, out, b"")

        with patch.object(probe, "ROOT", root), \
                patch.object(probe.shutil, "which", side_effect=lambda name: flutter if name == flutter else "aapt2"), \
                patch.dict(probe.os.environ, {"ORG_GRADLE_PROJECT_otzariaStartupProbe": "true"}), \
                patch.object(probe, "prepare"), \
                patch.object(probe, "write_defines", side_effect=lambda source, path: path.write_text("{}")), \
                patch.object(self.runner, "text", side_effect=lambda *args: device.get(args, "controlled-device")), \
                patch.object(self.runner, "adb", return_value=subprocess.CompletedProcess([], 0, b"", b"")), \
                patch.object(self.runner, "resolve_home", return_value=LAUNCHER), \
                patch.object(self.runner, "command", side_effect=command), \
                patch.object(self.runner, "install") as install:
            self.runner.build()

        self.assertIn(["aapt2", "dump", "badging", str(apk)], calls)
        self.assertEqual(self.runner.result["apk"], {
            "package": probe.PACKAGE, "activity": probe.ACTIVITY, "debuggable": True,
            "sha256": hashlib.sha256(payload).hexdigest(), "bytes": len(payload),
        })
        self.assertEqual(stale.read_bytes(), b"stale unflavored APK")
        install.assert_called_once_with(apk)


    def event_stream(self, *, close_error=False, changed_after_receipt=False):
        runner, directory = self.runner, self.directory

        class Events:
            sequence = 0

            def readline(self, maximum):
                self.sequence += 1
                action = ("home", "quiet", "resume", "complete")[self.sequence - 1]
                payload = {"identity": DOCUMENT}
                if action == "quiet":
                    payload.update(name="osBackgroundIdle", durationMs=1000)
                if action == "complete":
                    raw = json.dumps(report_fixture(runner.evidence)).encode()
                    (directory / "report.json").write_bytes(raw)
                    payload = completion(raw)
                data = json.dumps(event(self.sequence, action, payload)).encode() + b"\n"
                assert len(data) < maximum
                return data

            def read(self, maximum):
                assert maximum == 1 and self.sequence == 4
                assert runner.result["status"] != "passed"
                if close_error:
                    report = report_fixture(runner.evidence)
                    report.update(status="failed", frameworkPassed=False, errors=["Android control cleanup failed"])
                    (directory / "report.json").write_text(json.dumps(report))
                else:
                    raw = (directory / "report.json").read_bytes()
                    (directory / "completion.json").write_text(json.dumps(final_completion(raw)))
                    if changed_after_receipt:
                        (directory / "report.json").write_bytes(raw + b"\n")
                return b""

        return Events()

    def replies(self):
        observed = []
        token = self.runner.token

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                assert self.path == "/reply" and self.headers["X-Installed-Probe"] == token
                observed.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
                self.send_response(204)
                self.end_headers()

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.runner.forward = server.server_port
        return observed

    def test_push_orchestration_uses_real_subprocess_boundaries_and_no_command_during_quiet(self):
        replies = self.replies()
        self.runner.serve(self.event_stream())
        self.assertEqual(self.runner.result["status"], "passed")
        self.assertEqual([reply["action"] for reply in replies], ["home", "quiet", "resume", "complete"])
        self.assertTrue(all(reply["ok"] for reply in replies))
        quiet = self.runner.evidence["hostQuiet"]
        self.assertGreaterEqual(quiet["elapsedMs"], 1000)
        self.assertTrue(all(command["finishedMonotonic"] <= quiet["startedMonotonic"] or
                            command["startedMonotonic"] >= quiet["finishedMonotonic"]
                            for command in self.runner.commands))
        self.assertFalse(any("force-stop" in command["argv"] for command in self.runner.commands))
        self.assertTrue((self.runner.output / "installed-plugin-report.json").exists())
        self.assertTrue((self.runner.output / "preliminary-installed-plugin-report.json").exists())
        self.assertTrue(self.runner.result["completionReceipt"]["controlClosed"])

    def test_complete_ack_does_not_hide_a_later_device_close_failure(self):
        replies = self.replies()
        with patch.object(self.runner, "build"), \
                patch.object(self.runner, "connect", return_value=self.event_stream(close_error=True)), \
                patch.object(probe, "COMPLETION_TIMEOUT", 0.5, create=True), \
                self.assertRaises((TimeoutError, subprocess.TimeoutExpired)) as caught:
            self.runner.run()
        self.assertEqual(replies[-1]["action"], "complete")
        self.assertTrue(replies[-1]["ok"])
        self.assertEqual(len(replies), 4)
        self.assertEqual(self.runner.result["status"], "failed")
        self.assertIs(self.runner.first_error, caught.exception)
        self.assertFalse((self.runner.output / "installed-plugin-report.json").exists())
        preliminary = json.loads((self.runner.output / "preliminary-installed-plugin-report.json").read_text())
        late = json.loads((self.runner.output / "partial-installed-plugin-report.json").read_text())
        self.assertEqual(preliminary["status"], "passed")
        self.assertEqual(late["status"], "failed")
        self.assertIn("Android control cleanup failed", late["errors"])

    def test_final_receipt_revalidates_report_bytes_after_control_close(self):
        replies = self.replies()
        with self.assertRaisesRegex(ValueError, "bytes or digest"):
            self.runner.serve(self.event_stream(changed_after_receipt=True))
        self.assertEqual(replies[-1]["action"], "complete")
        self.assertTrue(replies[-1]["ok"])
        self.assertEqual(len(replies), 4)
        self.assertNotEqual(self.runner.result["status"], "passed")

    def test_home_resolution_uses_android_component_output_instead_of_brief_metadata(self):
        self.assertEqual(self.runner.resolve_home(), LAUNCHER)
        (self.directory / "state.json").write_text(json.dumps({"foreground": True, "token": "abc", "homeMissing": True}))
        with self.assertRaisesRegex(ValueError, "component"):
            self.runner.resolve_home()

    def short_native_waits(self):
        wait_native = self.runner.wait_native

        def wait(*, foreground):
            self.runner.action_deadline = min(self.runner.action_deadline or float("inf"), time.monotonic() + 2)
            return wait_native(foreground=foreground)

        return patch.object(self.runner, "wait_native", side_effect=wait)

    def test_home_is_resolved_again_after_emulator_setup_and_before_keypress(self):
        # The native API-34 run resolved the setup wizard before its APK build,
        # while KEYCODE_HOME later resumed the now-provisioned Nexus launcher.
        self.runner.launcher = "com.google.android.googlesdksetup/com.google.android.googlesdksetup.DefaultActivity"
        nexus = "com.google.android.apps.nexuslauncher/com.google.android.apps.nexuslauncher.NexusLauncherActivity"
        (self.directory / "state.json").write_text(json.dumps(
            {"foreground": True, "token": "abc", "resolvedHome": nexus, "actualHome": nexus}))
        replies = self.replies()
        with self.short_native_waits():
            self.runner.serve(self.event_stream())
        self.assertEqual(self.runner.result["status"], "passed")
        self.assertTrue(all(reply["ok"] for reply in replies))
        resolution = self.runner.result["homeResolution"]
        self.assertEqual(resolution["component"], nexus)
        self.assertEqual(json.loads((self.directory / "state.json").read_text())["resolutionAtHome"], resolution)
        command = self.runner.commands[resolution["command"]]
        self.assertIn("resolve-activity", command["argv"])
        self.assertEqual(command["stage"], "home")
        keypress = next(command for command in self.runner.commands if "KEYCODE_HOME" in command["argv"])
        self.assertLessEqual(command["finishedMonotonic"], keypress["startedMonotonic"])
        home = self.runner.evidence["home"]
        self.assertEqual(home["resolvedHome"], resolution)
        self.assertEqual(home["before"]["process"], home["after"]["process"])
        self.assertEqual(home["before"]["activity"], home["after"]["activity"])

    def test_home_refuses_missing_or_probe_resolution_before_sending_keypress(self):
        replies = self.replies()
        for state in ({"homeMissing": True}, {"resolvedHome": probe.PACKAGE + "/.MainActivity"}):
            with self.subTest(state=state):
                (self.directory / "state.json").write_text(json.dumps(
                    {"foreground": True, "token": "abc", **state}))
                with self.short_native_waits(), self.assertRaisesRegex(ValueError, "component|HOME"):
                    self.runner.serve(self.event_stream())
                self.assertFalse(replies[-1]["ok"])
                self.assertFalse(any("KEYCODE_HOME" in command["argv"] for command in self.runner.commands))

    def test_home_cannot_adopt_an_unexpected_resumed_activity_as_its_expectation(self):
        (self.directory / "state.json").write_text(json.dumps(
            {"foreground": True, "token": "abc", "actualHome": "other.package/other.package.Activity"}))
        replies = self.replies()
        with self.short_native_waits(), self.assertRaises((TimeoutError, subprocess.TimeoutExpired)):
            self.runner.serve(self.event_stream())
        self.assertEqual(self.runner.launcher, LAUNCHER)
        self.assertEqual(self.runner.result["homeResolution"]["component"], LAUNCHER)
        self.assertEqual(replies[-1]["action"], "home")
        self.assertFalse(replies[-1]["ok"])
        self.assertNotEqual(self.runner.result["status"], "passed")
        self.assertNotIn("hostQuiet", self.runner.evidence)

    def test_same_pid_but_new_activity_fails_before_any_successful_completion(self):
        replies = self.replies()
        (self.directory / "state.json").write_text(json.dumps(
            {"foreground": True, "token": "abc", "replaceOnResume": True}))
        with self.assertRaisesRegex(RuntimeError, "activity was replaced"):
            self.runner.serve(self.event_stream())
        self.assertEqual(replies[-1]["action"], "resume")
        self.assertFalse(replies[-1]["ok"])
        self.assertNotEqual(self.runner.result["status"], "passed")

    def test_quiet_guard_refuses_even_a_successful_native_command(self):
        count = len(self.runner.commands)
        self.runner.quiet_active = True
        with self.assertRaisesRegex(ValueError, "quiet"):
            self.runner.adb("shell", "pidof", probe.PACKAGE)
        self.assertEqual(len(self.runner.commands), count)

    def test_stale_bootstrap_cannot_start_the_controller_after_build(self):
        self.runner.campaign = CAMPAIGN
        self.runner.bootstrap = None
        (self.directory / "report.json").write_text(json.dumps({**BOOTSTRAP, "campaignId": "previous-campaign"}))
        with self.assertRaisesRegex(ValueError, "Stale"):
            self.runner.connect()
        self.assertIsNone(self.runner.forward)
        self.assertFalse(any("forward" in command["argv"] for command in self.runner.commands))

    def test_closed_oversized_or_expired_stream_cannot_supply_a_live_command(self):
        for raw in (b"", b"x" * (64 * 1024 + 1) + b"\n"):
            with self.subTest(size=len(raw)), self.assertRaises(ValueError):
                self.runner.read_event(io.BytesIO(raw))
        self.runner.deadline = time.monotonic() - 1
        with self.assertRaisesRegex(ValueError, "deadline"):
            self.runner.read_event(io.BytesIO(json.dumps(event(1, "home")).encode() + b"\n"))

    def test_unacknowledged_transition_obeys_the_action_deadline(self):
        start = time.monotonic()
        self.runner.action_deadline = start + 0.3
        with self.assertRaises((TimeoutError, subprocess.TimeoutExpired)):
            self.runner.wait_native(foreground=False)
        self.assertLess(time.monotonic() - start, 2)

    def test_command_timeout_retains_output_and_stops_owned_descendants(self):
        listener = socket.socket()
        self.addCleanup(listener.close)
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        listener.settimeout(2)
        child = "import signal,socket,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); " \
                f"s=socket.create_connection(('127.0.0.1',{listener.getsockname()[1]})); " \
                "s.sendall(b'1'); time.sleep(60)"
        parent = "import subprocess,sys,time; " \
                 f"p=subprocess.Popen([sys.executable,'-c',{child!r}]); " \
                 "print('partial',flush=True); time.sleep(60)"
        with self.assertRaises(subprocess.TimeoutExpired):
            self.runner.command([sys.executable, "-c", parent], timeout=0.7)
        connection, _ = listener.accept()
        self.addCleanup(connection.close)
        connection.settimeout(2)
        self.assertEqual(connection.recv(1), b"1")
        self.assertEqual(connection.recv(1), b"", "Timed-out command left a live owned descendant")
        last = self.runner.commands[-1]
        self.assertIn("error", last)
        self.assertEqual((self.runner.output / last["stdout"]).read_text(), "partial\n")

    def test_prelaunch_failure_is_saved_as_failed_and_does_not_stop_unowned_app(self):
        self.runner.bootstrap = None
        with patch.object(self.runner, "build", side_effect=RuntimeError("build failed")), self.assertRaises(RuntimeError):
            self.runner.run()
        final = json.loads((self.runner.output / "host-report.json").read_text())
        self.assertEqual(final["status"], "failed")
        self.assertIn("build failed", final["error"])
        self.assertFalse(any("force-stop" in command["argv"] for command in self.runner.commands))

    def test_failed_owned_cleanup_cannot_leave_a_successful_host_verdict(self):
        self.runner.installed = True
        with patch.object(self.runner, "build"), patch.object(self.runner, "connect"), \
                patch.object(self.runner, "serve", side_effect=lambda _: self.runner.result.update(status="passed")), \
                self.assertRaisesRegex(RuntimeError, r"Command \d+ failed \(1\)"):
            self.runner.run()
        saved = json.loads((self.runner.output / "host-report.json").read_text())
        self.assertEqual(saved["status"], "failed")
        self.assertTrue(any("stopError" in record for record in saved["cleanup"]))

    def test_early_failure_is_flushed_before_cleanup_can_be_interrupted(self):
        self.runner.bootstrap = None
        cleanup = self.runner.cleanup

        def observe_cleanup():
            saved = json.loads((self.runner.output / "host-report.json").read_text())
            self.assertEqual(saved["status"], "failed")
            self.assertIn("early controller failure", saved["error"])
            return cleanup()

        with patch.object(self.runner, "build", side_effect=RuntimeError("early controller failure")), \
                patch.object(self.runner, "cleanup", side_effect=observe_cleanup), self.assertRaises(RuntimeError):
            self.runner.run()

    def test_cleanup_leaves_a_replaced_forward_owned_by_another_serial(self):
        self.runner.forward = 34567
        state = {"foreground": True, "token": "abc", "forward": "emulator-5556 tcp:34567 tcp:12345"}
        (self.directory / "state.json").write_text(json.dumps(state))
        self.assertTrue(self.runner.cleanup())
        self.assertEqual(json.loads((self.directory / "state.json").read_text())["forward"], state["forward"])
        self.assertFalse(any("--remove" in command["argv"] for command in self.runner.commands))

    def test_cleanup_removes_only_the_exact_owned_forward(self):
        self.runner.forward = 34567
        state = {"foreground": True, "token": "abc", "forward": "emulator-5554 tcp:34567 tcp:12345"}
        (self.directory / "state.json").write_text(json.dumps(state))
        self.assertEqual(self.runner.cleanup(), [])
        self.assertEqual(json.loads((self.directory / "state.json").read_text())["forward"], "")
        removals = [command["argv"] for command in self.runner.commands if "--remove" in command["argv"]]
        self.assertEqual(len(removals), 1)
        self.assertEqual(removals[0][-1], "tcp:34567")


class FailureBoundaryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="android-installed-failure-test-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.adb = self.directory / "adb"
        self.adb.write_text(f"#!{sys.executable}\n" + textwrap.dedent('''
            import json
            from pathlib import Path
            import sys
            import time
            root = Path(__file__).parent
            args = sys.argv[1:]
            assert args[:2] == ['-s', 'emulator-5554'], args
            args = args[2:]
            with (root / 'calls.jsonl').open('a') as stream:
                stream.write(json.dumps(args) + '\\n')
            state = json.loads((root / 'state.json').read_text())
            package = 'org.otzaria.otzaria.installedprobe'
            phase, code = None, 0
            if args[:1] == ['install']:
                assert len(args) == 2 and Path(args[1]).is_file()
                state['installed'] = True
                phase = 'install'
                print('Success')
            elif args == ['forward', 'tcp:0', 'tcp:12345']:
                state['ownedForward'] = True
                phase = 'allocate'
                print('34567')
            elif args[:3] == ['shell', 'am', 'start']:
                state['ownedProcess'] = True
                print('Status: ok')
            elif args[:1] == ['logcat']:
                if state.get('failLogcat'):
                    print('optional logcat failure', file=sys.stderr)
                    code = 18
                else:
                    print('owned logcat')
            elif args[:5] == ['shell', '-T', 'run-as', package, 'cat']:
                if state.get('stallPartial'):
                    time.sleep(60)
                print('{"status":"failed","from":"controlled-child"}')
            elif args == ['forward', '--list']:
                if state.get('stallForward'):
                    time.sleep(60)
                if state.get('floodList'):
                    sys.stdout.buffer.write(b'x' * (8 * 1024 * 1024 + 65536))
                    sys.stdout.buffer.flush()
                    time.sleep(60)
                if state['ownedForward']:
                    print(state.get('forwardSerial', 'emulator-5554') + ' tcp:34567 tcp:12345')
                if state['borrowedForward']:
                    print('emulator-5556 tcp:34568 tcp:54321')
            elif args == ['forward', '--remove', 'tcp:34567']:
                assert state.get('forwardSerial', 'emulator-5554') == 'emulator-5554'
                if state.get('failRemove'):
                    print('owned forward removal failure', file=sys.stderr)
                    code = 27
                else:
                    state['ownedForward'] = False
            elif args == ['shell', 'am', 'force-stop', package]:
                phase = 'stop'
                if state.get('failStop'):
                    print('owned stop failure', file=sys.stderr)
                    code = 28
                else:
                    state['ownedProcess'] = False
            elif args == ['shell', 'pidof', package]:
                if state['ownedProcess']:
                    print('123')
                else:
                    code = 1
            else:
                raise AssertionError(args)
            (root / 'state.json').write_text(json.dumps(state))
            if phase is not None and state.get('faultAt') == phase:
                for fault in state['faults']:
                    path = root / 'output' / ('commands.jsonl' if fault == 'journal' else 'host-report.json')
                    if path.is_file():
                        path.rename(path.with_name(path.name + '.before-fault'))
                    path.mkdir()
                    (path / 'marker').write_text('retain this marker')
            sys.exit(code)
        '''))
        self.adb.chmod(0o700)
        self.state(installed=True, ownedForward=True, ownedProcess=True, borrowedForward=True)
        self.runner = probe.Runner(argparse.Namespace(output=self.directory / "output", device="emulator-5554",
                                                      adb=str(self.adb), quiet_ms=1000, flutter="unused"))
        self.runner.bootstrap = dict(BOOTSTRAP)
        self.runner.installed = True
        self.runner.forward = 34567
        self.runner.build = lambda: None
        self.runner.connect = lambda: None
        self.runner.serve = lambda _: self.runner.result.update(status="passed")

    def state(self, **changes):
        path = self.directory / "state.json"
        value = json.loads(path.read_text()) if path.exists() else {}
        value.update(changes)
        path.write_text(json.dumps(value))
        return value

    def calls(self):
        path = self.directory / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def obstruct(self, filename):
        path = self.runner.output / filename
        original = path.read_bytes() if path.is_file() else None
        if original is not None:
            path.rename(path.with_name(path.name + ".before-fault"))
        path.mkdir()
        (path / "marker").write_text("retain this marker")
        return original

    def failed_run(self, expected):
        diagnostics = io.StringIO()
        with redirect_stderr(diagnostics), self.assertRaises(expected) as caught:
            self.runner.run()
        self.assertEqual(self.runner.result["status"], "failed")
        self.assertTrue(self.state()["borrowedForward"])
        return caught.exception, diagnostics.getvalue()

    def command_failure(self):
        self.runner.build = lambda: self.runner.command(
            [sys.executable, "-c", 'import sys; print("primary command exit", file=sys.stderr); sys.exit(23)'])

    def provision(self):
        self.state(installed=False, ownedForward=False, ownedProcess=False)
        self.runner.bootstrap = None
        self.runner.installed = False
        self.runner.forward = None
        apk = self.directory / "owned-control.apk"
        apk.write_bytes(b"host boundary fixture, not an Android APK")

        def prepare():
            self.runner.install(apk)
            self.runner.bootstrap = {**BOOTSTRAP, "campaignId": self.runner.campaign}
            self.runner.allocate_forward()
            self.runner.adb("shell", "am", "start", "-W", "-n", probe.COMPONENT)
            self.runner.launched_pid = 123

        self.runner.build = prepare

    def obstruct_raw(self):
        self.runner.raw.rename(self.directory / "raw-before-fault")
        self.runner.raw.write_text("retain raw-path marker")

    def assert_released(self):
        state = self.state()
        self.assertFalse(state["ownedForward"])
        self.assertFalse(state["ownedProcess"])
        self.assertTrue(state["borrowedForward"])
        removals = [args for args in self.calls() if args[:2] == ["forward", "--remove"]]
        self.assertTrue(all(args == ["forward", "--remove", "tcp:34567"] for args in removals))

    def test_command_and_secondary_write_failures_survive_owned_cleanup(self):
        self.command_failure()
        self.obstruct("commands.jsonl")
        previous_report = self.obstruct("host-report.json")
        error, diagnostics = self.failed_run(RuntimeError)
        self.assertEqual(str(error), "Command 0 failed (23); see raw/command-0000.stderr")
        self.assert_released()
        self.assertEqual((self.runner.raw / "command-0000.stderr").read_text(), "primary command exit\n")
        self.assertEqual((self.runner.output / "host-report.json.before-fault").read_bytes(), previous_report)
        self.assertEqual((self.runner.output / "host-report.json/marker").read_text(), "retain this marker")
        secondary = self.runner.result["secondaryErrors"]
        self.assertEqual([entry["order"] for entry in secondary], list(range(2, len(secondary) + 2)))
        self.assertEqual(secondary[0]["source"], "commands.jsonl command 0")
        self.assertTrue(secondary[1]["source"].startswith("host-report.json from "))
        pending = sorted(self.runner.output.glob("host-report-*.pending.json"))
        self.assertEqual(len(pending), 2)
        self.assertTrue(all(json.loads(path.read_text())["error"].endswith(str(error)) for path in pending))
        self.assertEqual(json.loads(pending[-1].read_text())["commandReceiptFallback"][0]["exitCode"], 23)
        self.assertTrue(all(json.loads(line)["primaryError"].endswith(str(error)) for line in diagnostics.splitlines()))

    def test_native_cleanup_failures_and_receipt_failures_preserve_first_command_error(self):
        self.state(failRemove=True, failStop=True)
        self.command_failure()
        self.obstruct("commands.jsonl")
        self.obstruct("host-report.json")
        error, _ = self.failed_run(RuntimeError)
        self.assertIn("failed (23)", str(error))
        self.assertTrue(self.state()["ownedForward"])
        self.assertTrue(self.state()["ownedProcess"])
        cleanup_commands = [entry for entry in self.runner.commands if entry.get("exitCode") in (27, 28)]
        self.assertEqual([entry["exitCode"] for entry in cleanup_commands], [27, 28])
        secondary = self.runner.result["secondaryErrors"]
        self.assertEqual([entry["order"] for entry in secondary], list(range(2, len(secondary) + 2)))
        self.assertEqual(sum("failed (27)" in entry["error"] for entry in secondary), 1)
        self.assertEqual(sum("failed (28)" in entry["error"] for entry in secondary), 1)
        self.assertTrue(any("forwardError" in entry for entry in self.runner.result["cleanup"]))
        self.assertTrue(any("stopError" in entry for entry in self.runner.result["cleanup"]))

    def test_successful_install_owns_cleanup_before_journal_write(self):
        self.state(installed=False, ownedForward=False, ownedProcess=False, faultAt="install", faults=["journal"])
        self.runner.bootstrap = None
        self.runner.installed = False
        self.runner.forward = None
        apk = self.directory / "controlled.apk"
        apk.write_bytes(b"controlled install boundary; not an Android APK")
        self.runner.build = lambda: self.runner.install(apk)
        self.failed_run(IsADirectoryError)
        self.assertTrue(self.runner.installed)
        self.assertTrue(self.state()["installed"])
        self.assert_released()
        self.assertEqual(self.runner.commands[0]["exitCode"], 0)
        self.assertEqual((self.runner.raw / "command-0000.stdout").read_text(), "Success\n")
        self.assertIn(["shell", "am", "force-stop", probe.PACKAGE], self.calls())
        self.assertEqual(apk.read_bytes(), b"controlled install boundary; not an Android APK")

    def test_successful_forward_allocation_owns_cleanup_before_journal_write(self):
        self.state(ownedForward=False, faultAt="allocate", faults=["journal"])
        self.runner.forward = None
        self.runner.connect = self.runner.allocate_forward
        self.failed_run(IsADirectoryError)
        self.assertEqual(self.runner.forward, 34567)
        self.assertEqual(self.runner.commands[0]["exitCode"], 0)
        self.assertEqual((self.runner.raw / "command-0000.stdout").read_text(), "34567\n")
        self.assert_released()
        self.assertEqual(self.calls().count(["forward", "--remove", "tcp:34567"]), 1)

    def test_precommand_receipt_fault_never_runs_or_claims_install(self):
        self.state(installed=False, ownedForward=False, ownedProcess=False)
        self.runner.bootstrap = None
        self.runner.installed = False
        self.runner.forward = None
        receipt = self.runner.raw / "command-0000.stderr"
        receipt.write_bytes(b"retain preexisting receipt")
        self.runner.build = lambda: self.runner.install(self.directory / "unused.apk")
        self.failed_run(FileExistsError)
        self.assertFalse(self.runner.installed)
        self.assertFalse(self.state()["installed"])
        self.assertEqual(self.calls(), [])
        self.assertNotIn("ownedProcessGroup", self.runner.commands[0])
        self.assertEqual(receipt.read_bytes(), b"retain preexisting receipt")

    def test_optional_timeout_and_forward_timeout_leave_stop_an_independent_budget(self):
        self.state(stallPartial=True, stallForward=True)
        primary = RuntimeError("scenario failed before cleanup")

        def fail(_):
            raise primary

        self.runner.serve = fail
        started = time.monotonic()
        error, _ = self.failed_run(RuntimeError)
        elapsed = time.monotonic() - started
        self.assertIs(error, primary)
        self.assertGreaterEqual(elapsed, 14)
        self.assertLess(elapsed, 25)
        self.assertTrue(self.state()["ownedForward"])
        self.assertFalse(self.state()["ownedProcess"])
        self.assertIn(["forward", "--list"], self.calls())
        self.assertIn(["shell", "am", "force-stop", probe.PACKAGE], self.calls())
        self.assertTrue(any("partialReportError" in entry for entry in self.runner.result["cleanup"]))
        self.assertTrue(any("forwardError" in entry for entry in self.runner.result["cleanup"]))
        self.assertTrue(any("stoppedOwnedPackageAfterOutcome" in entry for entry in self.runner.result["cleanup"]))

    def test_evidence_only_failure_during_cleanup_cannot_report_success(self):
        self.obstruct("commands.jsonl")
        error, _ = self.failed_run(IsADirectoryError)
        self.assert_released()
        self.assertEqual(self.runner.commands[0]["exitCode"], 0)
        saved = json.loads((self.runner.output / "host-report.json").read_text())
        self.assertEqual(saved["status"], "failed")
        self.assertEqual(saved["error"], f"IsADirectoryError: {error}")
        self.assertEqual(saved["commandReceiptFallback"], self.runner.commands)

    def test_final_report_failure_retains_last_receipt_and_fails_after_cleanup(self):
        previous = (self.runner.output / "host-report.json").read_bytes()
        self.state(faultAt="stop", faults=["report"])
        error, diagnostics = self.failed_run(IsADirectoryError)
        self.assert_released()
        self.assertEqual((self.runner.output / "host-report.json.before-fault").read_bytes(), previous)
        self.assertEqual((self.runner.output / "host-report.json/marker").read_text(), "retain this marker")
        self.assertEqual(len(list(self.runner.output.glob("host-report-*.pending.json"))), 1)
        self.assertEqual(json.loads(diagnostics.splitlines()[-1])["primaryError"], f"IsADirectoryError: {error}")

    def test_partial_receipt_collision_retains_both_source_and_previous_receipt(self):
        receipt = self.runner.output / "partial-installed-plugin-report.json"
        receipt.write_bytes(b"retain previous partial receipt")
        self.failed_run(FileExistsError)
        self.assert_released()
        self.assertEqual(receipt.read_bytes(), b"retain previous partial receipt")
        source = next(entry for entry in self.runner.commands if "run-as" in entry["argv"])
        captured = json.loads((self.runner.output / source["stdout"]).read_text())
        self.assertEqual(captured, {"status": "failed", "from": "controlled-child"})

    def test_broken_stderr_fallback_does_not_replace_original_exit(self):
        self.command_failure()
        self.obstruct("commands.jsonl")
        self.runner.bootstrap = None
        self.runner.installed = False
        self.runner.forward = None
        target = self.directory / "readonly-stderr"
        target.write_text("retain stderr target")
        with target.open("r") as readonly, redirect_stderr(readonly), self.assertRaises(RuntimeError) as caught:
            self.runner.run()
        self.assertIn("failed (23)", str(caught.exception))
        saved = json.loads((self.runner.output / "host-report.json").read_text())
        self.assertIn("failed (23)", saved["error"])
        self.assertEqual([entry["source"] for entry in saved["secondaryErrors"]],
                         ["commands.jsonl command 0", "stderr fallback"])
        self.assertEqual(target.read_text(), "retain stderr target")

    def test_optional_logcat_failure_still_collects_partial_receipt_and_owned_cleanup(self):
        self.state(failLogcat=True)
        self.runner.run()
        self.assertEqual(self.runner.result["status"], "passed")
        self.assert_released()
        receipt = json.loads((self.runner.output / "partial-installed-plugin-report.json").read_text())
        self.assertEqual(receipt, {"status": "failed", "from": "controlled-child"})
        self.assertTrue(any("logcatError" in entry for entry in self.runner.result["cleanup"]))

    def test_raw_parent_failure_still_runs_owned_cleanup_and_keeps_live_receipts(self):
        self.provision()
        primary = RuntimeError("scenario failed before raw-path fault")

        def fail(_):
            self.obstruct_raw()
            raise primary

        self.runner.serve = fail
        error, _ = self.failed_run(RuntimeError)
        self.assertIs(error, primary)
        self.assert_released()
        self.assertEqual(self.runner.raw.read_text(), "retain raw-path marker")
        self.assertEqual((self.directory / "raw-before-fault/command-0001.stdout").read_text(), "34567\n")
        cleanup = self.runner.commands[3:]
        self.assertTrue(all("ownedProcessGroup" in command for command in cleanup))
        self.assertTrue(all(command["cleanupCapture"]["complete"] for command in cleanup))
        listing = next(command for command in cleanup if command["argv"][-2:] == ["forward", "--list"])
        self.assertEqual(base64.b64decode(listing["stdoutFallback"]["data"]),
                         b"emulator-5554 tcp:34567 tcp:12345\nemulator-5556 tcp:34568 tcp:54321\n")
        saved = json.loads((self.runner.output / "host-report.json").read_text())
        self.assertEqual(saved["commandReceiptFallback"], self.runner.commands)

    def test_both_forward_raw_receipt_collisions_leave_owned_cleanup_executable(self):
        self.provision()
        markers = []

        def fail(_):
            number = len(self.runner.commands) + 2
            for name in ("stdout", "stderr"):
                path = self.runner.raw / f"command-{number:04d}.{name}"
                path.write_bytes(b"retain colliding receipt")
                markers.append(path)
            raise RuntimeError("scenario failed with receipt collisions")

        self.runner.serve = fail
        self.failed_run(RuntimeError)
        self.assert_released()
        self.assertTrue(all(path.read_bytes() == b"retain colliding receipt" for path in markers))
        listing = next(command for command in self.runner.commands if command["argv"][-2:] == ["forward", "--list"])
        self.assertEqual({entry["stream"] for entry in listing["captureWriteErrors"]}, {"stdout", "stderr"})
        self.assertIn(["shell", "am", "force-stop", probe.PACKAGE], self.calls())

    def test_stale_raw_receipt_cannot_authorize_removal_of_a_borrowed_forward(self):
        self.provision()
        marker = None

        def fail(_):
            nonlocal marker
            self.state(forwardSerial="emulator-5556")
            marker = self.runner.raw / f"command-{len(self.runner.commands) + 2:04d}.stdout"
            marker.write_text("emulator-5554 tcp:34567 tcp:12345\n")
            raise RuntimeError("scenario failed after mapping replacement")

        self.runner.serve = fail
        self.failed_run(RuntimeError)
        self.assertTrue(self.state()["ownedForward"])
        self.assertEqual(self.state()["forwardSerial"], "emulator-5556")
        self.assertFalse(self.state()["ownedProcess"])
        self.assertNotIn(["forward", "--remove", "tcp:34567"], self.calls())
        self.assertEqual(marker.read_text(), "emulator-5554 tcp:34567 tcp:12345\n")
        listing = next(command for command in self.runner.commands if command["argv"][-2:] == ["forward", "--list"])
        self.assertTrue(base64.b64decode(listing["stdoutFallback"]["data"]).startswith(b"emulator-5556 tcp:34567"))
        self.assertTrue(any("forwardError" in entry for entry in self.runner.result["cleanup"]))

    def test_cleanup_reads_both_live_pipes_and_keeps_exact_binary_fallback(self):
        self.obstruct_raw()
        self.runner.cleaning_up = True
        program = "import sys,threading; " \
                  "a=threading.Thread(target=lambda:sys.stdout.buffer.write(bytes(range(256))*4096)); " \
                  "b=threading.Thread(target=lambda:sys.stderr.buffer.write(bytes(reversed(range(256)))*4096)); " \
                  "a.start(); b.start(); a.join(); b.join()"
        with redirect_stderr(io.StringIO()):
            result = self.runner.command([sys.executable, "-c", program], timeout=5)
        self.runner.cleaning_up = False
        expected = {"stdout": bytes(range(256)) * 4096, "stderr": bytes(reversed(range(256))) * 4096}
        for name, data in expected.items():
            self.assertEqual(getattr(result, name), data)
            fallback = self.runner.commands[-1][name + "Fallback"]
            self.assertEqual(fallback["bytes"], len(data))
            self.assertEqual(base64.b64decode(fallback["data"]), data)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.runner.result["status"], "failed")
        self.assertEqual(self.runner.raw.read_text(), "retain raw-path marker")

    def test_oversized_forward_output_is_bounded_and_stop_still_runs(self):
        self.provision()
        self.state(floodList=True)
        children = []
        real_popen = subprocess.Popen

        def observe(*args, **kwargs):
            child = real_popen(*args, **kwargs)
            children.append(child)
            return child

        def fail(_):
            raise RuntimeError("scenario failed before overflowing output")

        self.runner.serve = fail
        started = time.monotonic()
        with patch.object(probe.subprocess, "Popen", side_effect=observe):
            self.failed_run(RuntimeError)
        self.assertLess(time.monotonic() - started, 12)
        self.assertTrue(all(child.poll() is not None for child in children))
        self.assertTrue(self.state()["ownedForward"])
        self.assertFalse(self.state()["ownedProcess"])
        self.assertNotIn(["forward", "--remove", "tcp:34567"], self.calls())
        listing = next(command for command in self.runner.commands if command["argv"][-2:] == ["forward", "--list"])
        self.assertIn("exceeds", listing["error"])
        self.assertFalse(listing["cleanupCapture"]["complete"])
        self.assertEqual(listing["cleanupCapture"]["bytes"]["stdout"], probe.COMMAND_OUTPUT_LIMIT)
        self.assertEqual((self.runner.output / listing["stdout"]).stat().st_size, probe.COMMAND_OUTPUT_LIMIT)

    def test_cleanup_deadline_drains_descendant_holding_pipe_after_parent_exit(self):
        listener = socket.socket()
        self.addCleanup(listener.close)
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        listener.settimeout(2)
        child = "import signal,socket,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); " \
                f"s=socket.create_connection(('127.0.0.1',{listener.getsockname()[1]})); " \
                "s.sendall(b'1'); time.sleep(60)"
        parent = "import subprocess,sys; " \
                 f"subprocess.Popen([sys.executable,'-c',{child!r}]); print('partial',flush=True)"
        self.obstruct_raw()
        self.runner.cleaning_up = True
        with redirect_stderr(io.StringIO()), self.assertRaises(subprocess.TimeoutExpired) as caught:
            self.runner.command([sys.executable, "-c", parent], timeout=0.7)
        self.runner.cleaning_up = False
        connection, _ = listener.accept()
        self.addCleanup(connection.close)
        connection.settimeout(2)
        self.assertEqual(connection.recv(1), b"1")
        self.assertEqual(connection.recv(1), b"", "An owned descendant retained the output pipes after timeout")
        self.assertIs(self.runner.first_error, caught.exception)
        record = self.runner.commands[-1]
        self.assertFalse(record["cleanupCapture"]["complete"])
        self.assertEqual(base64.b64decode(record["stdoutFallback"]["data"]), b"partial\n")

    def test_raw_capture_write_failure_alone_fails_after_owned_resources_are_released(self):
        self.provision()

        def complete(_):
            self.obstruct_raw()
            self.runner.result["status"] = "passed"

        self.runner.serve = complete
        error, _ = self.failed_run(NotADirectoryError)
        self.assert_released()
        self.assertEqual(self.runner.commands[3]["exitCode"], 0)
        saved = json.loads((self.runner.output / "host-report.json").read_text())
        self.assertEqual(saved["error"], f"NotADirectoryError: {error}")
        self.assertEqual(saved["status"], "failed")

    def test_failed_cleanup_command_keeps_its_exit_and_stderr_when_raw_writes_fail(self):
        self.obstruct_raw()
        self.runner.cleaning_up = True
        with redirect_stderr(io.StringIO()), self.assertRaisesRegex(RuntimeError, "failed \\(23\\)") as caught:
            self.runner.command([sys.executable, "-c", 'import sys; print("native exit23", file=sys.stderr); sys.exit(23)'])
        self.runner.cleaning_up = False
        self.assertIs(self.runner.first_error, caught.exception)
        record = self.runner.commands[-1]
        self.assertEqual(record["exitCode"], 23)
        self.assertTrue(record["cleanupCapture"]["complete"])
        self.assertEqual(base64.b64decode(record["stderrFallback"]["data"]), b"native exit23\n")
        self.assertEqual([entry["stream"] for entry in record["captureWriteErrors"]], ["stdout", "stderr"])

    def test_cleanup_mid_write_filesize_failure_does_not_truncate_live_output(self):
        program = textwrap.dedent('''
            import argparse, base64, errno, json, resource, signal, sys
            from pathlib import Path
            from tool.perf_probe import run_installed_plugin_android as probe
            runner = probe.Runner(argparse.Namespace(output=Path(sys.argv[1]), device='emulator-5554',
                                                     quiet_ms=1000, adb='unused', flutter='unused'))
            runner.cleaning_up = True
            signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
            _, hard = resource.getrlimit(resource.RLIMIT_FSIZE)
            resource.setrlimit(resource.RLIMIT_FSIZE, (1024, hard))
            result = runner.command([sys.executable, '-c', "import sys; sys.stdout.buffer.write(b'x'*4096)"], timeout=5)
            record = runner.commands[-1]
            print(json.dumps({'returncode':result.returncode, 'stdoutMatches':result.stdout == b'x'*4096,
                              'fallbackMatches':base64.b64decode(record['stdoutFallback']['data']) == result.stdout,
                              'rawBytes':(runner.raw/'command-0000.stdout').stat().st_size,
                              'writeError':runner.first_error.errno, 'expectedError':errno.EFBIG,
                              'status':runner.result['status'], 'captureComplete':record['cleanupCapture']['complete']}))
        ''')
        result = subprocess.run([sys.executable, "-c", program, str(self.directory / "limited-output")],
                                cwd=probe.ROOT, capture_output=True, timeout=10, check=True)
        observed = json.loads(result.stdout)
        self.assertEqual(observed["returncode"], 0)
        self.assertTrue(observed["stdoutMatches"] and observed["fallbackMatches"] and observed["captureComplete"])
        self.assertLessEqual(observed["rawBytes"], 1024)
        self.assertEqual(observed["writeError"], observed["expectedError"])
        self.assertEqual(observed["status"], "failed")


if __name__ == "__main__":
    unittest.main()
