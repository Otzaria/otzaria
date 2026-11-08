import importlib.util
from contextlib import contextmanager
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

SPEC = importlib.util.spec_from_file_location("apple_native_controller_runner", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)

@contextmanager
def native_result(directory, label, **details):
    report = {"status": "running", "scope": "Owned AppKit helper control, not an Otzaria quiet measurement", **details}
    failure = None
    try:
        yield report
    except BaseException as error:
        failure = error
        report.update(status="failed", error=str(error), errorType=type(error).__name__)
        raise
    else:
        report["status"] = "passed"
    finally:
        try:
            runner.save(directory / f"{label}.json", report)
        except Exception as error:
            if failure is None:
                raise
            runner.warn_cleanup(f"Could not preserve {label} native control evidence: {error}")


def verify_open_target(snapshot, *, pid, executable, bundle, launch_id, initial_launches):
    instances = snapshot.get("instances")
    if (not isinstance(instances, list) or len(instances) != 1 or
            instances[0].get("pid") != pid or instances[0].get("executable") != executable or
            instances[0].get("bundleURL") != bundle or instances[0].get("isTerminated") is not False):
        raise ValueError("open must retain exactly the original live process in the owned bundle")
    launches = snapshot.get("launches")
    if launches != initial_launches:
        raise ValueError("open created an additional launch or changed the owned launch evidence")
    original = [entry for entry in launches if entry.get("launchId") == launch_id]
    if (len(original) != 1 or original[0].get("pid") != pid or
            original[0].get("executable") != executable or original[0].get("bundleURL") != bundle):
        raise ValueError("The original owned launch identity is missing or inconsistent")


def verify_launchservices_launch(receipt, *, owner_pid, executable, bundle, ready):
    if (receipt.get("status") != "launched" or receipt.get("source") != "NSWorkspace.openApplication" or
            receipt.get("ownerPid") != owner_pid or type(receipt.get("pid")) is not int or
            receipt["pid"] <= 0 or receipt["pid"] == owner_pid or
            not isinstance(receipt.get("sessionToken"), str) or not receipt["sessionToken"] or
            receipt.get("executable") != executable or receipt.get("bundleURL") != bundle or
            receipt.get("bundleIdentifier") != "org.otzaria.identitycontrol" or
            receipt.get("sameApplication") is not True or receipt.get("isTerminated") is not False):
        raise ValueError("LaunchServices did not return the owned live target identity")
    expected = {"createsNewApplicationInstance": True, "allowsRunningApplicationSubstitution": False,
                "hides": False, "hidesOthers": False, "arguments": [ready]}
    configuration = receipt.get("configuration")
    if (not isinstance(configuration, dict) or
            any(configuration.get(key) is not value for key, value in expected.items() if isinstance(value, bool)) or
            configuration.get("arguments") != expected["arguments"]):
        raise ValueError("LaunchServices did not use the required initial-launch configuration")


def verify_initial_launch(snapshot, previous_launches, *, pid, executable, bundle, launch_id):
    launches = snapshot.get("launches")
    if (not isinstance(launches, list) or len(launches) != len(previous_launches) + 1 or
            any(launches.count(previous) != 1 for previous in previous_launches)):
        raise ValueError("Initial LaunchServices launch must create exactly one owned launch")
    added = [entry for entry in launches if entry not in previous_launches]
    if len(added) != 1 or added[0].get("launchId") != launch_id:
        raise ValueError("Initial LaunchServices launch audit does not match fixture readiness")
    verify_open_target(snapshot, pid=pid, executable=executable, bundle=bundle,
                       launch_id=launch_id, initial_launches=launches)


def verify_launchservices_stop(receipt, launch, *, launch_id=None):
    for key in ["ownerPid", "sessionToken", "pid", "executable", "bundleURL", "bundleIdentifier", "source"]:
        if key not in launch or receipt.get(key) != launch[key]:
            raise ValueError(f"LaunchServices cleanup changed the retained identity: {key}")
    if launch_id is not None and receipt.get("launchId") != launch_id:
        raise ValueError("LaunchServices cleanup changed the fixture launch audit identity")
    if (receipt.get("status") != "passed" or receipt.get("targetExited") is not True or
            receipt.get("cleanupErrors") != [] or receipt.get("forceTerminateReturnValue") is not None):
        raise ValueError(f"LaunchServices cleanup did not complete normally: {receipt.get('error')}")


class NativeEvidenceTests(unittest.TestCase):
    def test_failure_preserves_partial_observations_and_original_exception(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            failure = AssertionError("owned application refused hide")
            with self.assertRaises(AssertionError) as captured:
                with native_result(directory, "failed-control") as report:
                    report["before"] = {"isHidden": False}
                    raise failure
            self.assertIs(captured.exception, failure)
            result = json.loads((directory / "failed-control.json").read_text())
            self.assertEqual(result["status"], "failed")
            self.assertEqual(result["before"], {"isHidden": False})
            self.assertEqual(result["errorType"], "AssertionError")

    def test_completed_control_is_distinct_from_a_failed_alternative(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with self.assertRaises(ValueError):
                with native_result(directory, "production"):
                    raise ValueError("hide returned false")
            with native_result(directory, "diagnostic") as report:
                report["isHidden"] = True
            self.assertEqual(json.loads((directory / "production.json").read_text())["status"], "failed")
            self.assertEqual(json.loads((directory / "diagnostic.json").read_text())["status"], "passed")

    def test_native_failure_survives_evidence_write_and_diagnostic_stream_failures(self):
        failure = ValueError('native hide refused')
        with tempfile.TemporaryDirectory() as temporary, \
             patch.object(runner, 'save', side_effect=OSError('diagnostic evidence write failed')), \
             patch.object(runner.sys, 'stderr', Mock(write=Mock(side_effect=BrokenPipeError('stderr closed')))):
            with self.assertRaises(ValueError) as captured:
                with native_result(Path(temporary), 'failed-control'):
                    raise failure
            self.assertIs(captured.exception, failure)

    def test_evidence_write_failure_alone_cannot_pass_a_native_control(self):
        failure = OSError('diagnostic evidence write failed')
        with tempfile.TemporaryDirectory() as temporary, \
             patch.object(runner, 'save', side_effect=failure):
            with self.assertRaises(OSError) as captured:
                with native_result(Path(temporary), 'completed-control') as report:
                    report['isHidden'] = True
            self.assertIs(captured.exception, failure)

    def open_snapshot(self):
        identity = {"pid": 17, "executable": "/private/Owned.app/Contents/MacOS/Owned",
                    "bundleURL": "/private/Owned.app"}
        snapshot = {"instances": [{**identity, "isTerminated": False}],
                    "launches": [{**identity, "launchId": "owned-launch", "arguments": [identity["executable"], "/private/ready.json"]}]}
        expected = {"pid": 17, "executable": identity["executable"], "bundle": identity["bundleURL"],
                    "launch_id": "owned-launch", "initial_launches": list(snapshot["launches"])}
        return snapshot, expected

    def test_open_keeps_the_same_owned_instance_and_launch(self):
        snapshot, expected = self.open_snapshot()
        verify_open_target(snapshot, **expected)

    def test_open_cannot_substitute_another_live_instance(self):
        for change in ["additional", "pid", "executable", "bundleURL", "isTerminated"]:
            snapshot, expected = self.open_snapshot()
            if change == "additional":
                snapshot["instances"].append({**snapshot["instances"][0], "pid": 18})
            else:
                snapshot["instances"][0][change] = True if change == "isTerminated" else "different"
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, "original live process"):
                verify_open_target(snapshot, **expected)

    def test_open_cannot_hide_a_second_instance_that_already_exited(self):
        snapshot, expected = self.open_snapshot()
        snapshot["launches"].append({**snapshot["launches"][0], "pid": 18, "launchId": "exited-copy"})
        # Enumeration still contains the live original process alone.
        with self.assertRaisesRegex(ValueError, "additional launch"):
            verify_open_target(snapshot, **expected)

    def launchservices_receipt(self):
        expected = {"owner_pid": 12, "executable": "/private/Owned.app/Contents/MacOS/Owned",
                    "bundle": "/private/Owned.app", "ready": "/private/ready.json"}
        receipt = {"status": "launched", "source": "NSWorkspace.openApplication", "ownerPid": 12,
                   "pid": 17, "sessionToken": "owned-session", "executable": expected["executable"],
                   "bundleURL": expected["bundle"], "bundleIdentifier": "org.otzaria.identitycontrol",
                   "sameApplication": True, "isTerminated": False,
                   "configuration": {"createsNewApplicationInstance": True,
                                     "allowsRunningApplicationSubstitution": False,
                                     "hides": False, "hidesOthers": False, "arguments": [expected["ready"]]}}
        return receipt, expected

    def test_launchservices_requires_completion_identity_and_initial_launch_options(self):
        receipt, expected = self.launchservices_receipt()
        verify_launchservices_launch(receipt, **expected)
        for field, value in [("source", "Popen"), ("ownerPid", 99), ("pid", True), ("pid", 0),
                             ("pid", 12), ("sessionToken", ""), ("sameApplication", False),
                             ("isTerminated", True), ("bundleURL", "/other.app"),
                             ("executable", "/other"), ("bundleIdentifier", "other")]:
            invalid = {**receipt, field: value}
            with self.subTest(field=field, value=value), self.assertRaisesRegex(ValueError, "owned live target"):
                verify_launchservices_launch(invalid, **expected)
        for field in receipt["configuration"]:
            invalid = {**receipt, "configuration": {**receipt["configuration"], field: None}}
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "configuration"):
                verify_launchservices_launch(invalid, **expected)

    def test_initial_launch_rejects_substitution_or_an_extra_launch_that_already_exited(self):
        snapshot, expected = self.open_snapshot()
        expected.pop("initial_launches")
        verify_initial_launch(snapshot, [], **expected)
        with self.assertRaisesRegex(ValueError, "exactly one"):
            verify_initial_launch(snapshot, snapshot["launches"], **expected)
        snapshot["launches"].append({**snapshot["launches"][0], "pid": 18, "launchId": "exited-copy"})
        with self.assertRaisesRegex(ValueError, "exactly one"):
            verify_initial_launch(snapshot, [], **expected)

    def test_launchservices_owner_cleanup_runs_once_and_requires_its_final_receipt(self):
        launch, _ = self.launchservices_receipt()
        stopped = {**launch, "status": "passed", "targetExited": True,
                   "cleanupErrors": [], "forceTerminateReturnValue": None}
        process = Mock()
        process.poll.return_value = None
        process.wait.return_value = 0
        state = {"process": process, "launch": launch, "closed": False,
                 "stopPath": Mock(read_text=Mock(return_value=json.dumps(stopped)))}
        case = NativeMacIdentityTests("test_initial_launchservices_target_uses_the_original_controller")
        self.assertEqual(case.close_launchservices_app(state), stopped)
        self.assertEqual(case.close_launchservices_app(state), stopped)
        process.stdin.write.assert_called_once_with("stop\n")
        process.stdin.close.assert_called_once_with()
        process.wait.assert_called_once_with(timeout=25)

    def test_launchservices_owner_cleanup_preserves_first_transport_error(self):
        launch, _ = self.launchservices_receipt()
        primary = BrokenPipeError("first stop write failed")
        process = Mock()
        process.poll.return_value = None
        process.stdin.write.side_effect = primary
        process.wait.side_effect = subprocess.TimeoutExpired("owner", 25)
        state = {"process": process, "launch": launch, "closed": False,
                 "stopPath": Mock(read_text=Mock(side_effect=OSError("no final receipt")))}
        case = NativeMacIdentityTests("test_initial_launchservices_target_uses_the_original_controller")
        with patch.object(runner.sys, "stderr", Mock(write=Mock(side_effect=BrokenPipeError("stderr")))):
            with self.assertRaises(BrokenPipeError) as captured:
                case.close_launchservices_app(state)
        self.assertIs(captured.exception, primary)
        process.stdin.close.assert_called_once_with()
        process.wait.assert_called_once_with(timeout=25)
        state["stopPath"].read_text.assert_called_once_with()

    def test_launchservices_cleanup_requires_original_identity_and_normal_termination(self):
        launch, _ = self.launchservices_receipt()
        stopped = {**launch, "status": "passed", "targetExited": True,
                   "cleanupErrors": [], "forceTerminateReturnValue": None}
        verify_launchservices_stop(stopped, launch)
        with self.assertRaisesRegex(ValueError, "launch audit identity"):
            verify_launchservices_stop({**stopped, "launchId": "other"}, launch, launch_id="owned-launch")
        for field, value in [("pid", 19), ("sessionToken", "other"), ("ownerPid", 99),
                             ("targetExited", False), ("cleanupErrors", ["refused"]),
                             ("status", "failed"), ("forceTerminateReturnValue", True)]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                verify_launchservices_stop({**stopped, field: value}, launch)


@unittest.skipUnless(sys.platform == "darwin", "Requires real AppKit; not native evidence on other hosts")
class NativeMacIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        requested = os.environ.get("APPLE_HELPER_CONTROL_OUTPUT")
        if requested:
            cls.directory = Path(requested).absolute()
            for path in [cls.directory, *cls.directory.parents]:
                if path.is_symlink():
                    raise ValueError("Native control output must not traverse a symlink")
            cls.directory.mkdir(parents=True, exist_ok=True)
            if any(cls.directory.iterdir()):
                raise ValueError("Native controls require a fresh output directory")
        else:
            cls.temporary = tempfile.TemporaryDirectory(prefix="apple-identity-controls-")
            cls.addClassCleanup(cls.temporary.cleanup)
            cls.directory = Path(cls.temporary.name).resolve()
        runner.save(cls.directory / "environment.json", {
            "platform": platform.platform(), "python": sys.version,
            "controllerScope": "Owned fixture processes only; all controls are outside app quiet intervals",
            "productionControllerExplicitlyInitializesAppKit": False,
        })
        runner.recorded_output(cls.directory, "swift-version", [*runner.macos_swift_command(), "--version"], 30)
        source = cls.directory / "direct_application.swift"
        source.write_text((runner.HERE / "mac_control_fixture.swift").read_text())
        bundle = cls.directory / "DirectIdentity.app"
        cls.executable = bundle / "Contents/MacOS/DirectIdentity"
        cls.executable.parent.mkdir(parents=True)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "DirectIdentity", "CFBundleIdentifier": "org.otzaria.identitycontrol",
            "CFBundleName": "DirectIdentity", "CFBundlePackageType": "APPL",
            "LSMinimumSystemVersion": runner.macos_swift_command()[-1].split("macosx", 1)[1], "NSHighResolutionCapable": True,
        }))
        cls.helper = cls.directory / "mac-application"
        runner.recorded_output(cls.directory, "compile-owned-application",
            [*runner.macos_swift_command(), str(source), "-o", str(cls.executable)], 120)
        runner.recorded_output(cls.directory, "compile-controller",
            [*runner.macos_swift_command(), str(runner.HERE / "mac_application.swift"), "-o", str(cls.helper)], 120)
        original = (runner.HERE / "mac_application.swift").read_text()
        cls.rejected_helpers = {}
        for name, change in [
                ("untrusted", ("let trusted = AXIsProcessTrusted()", "let trusted = false")),
                ("rejected", ("AXUIElementSetAttributeValue(\n        AXUIElementCreateApplication(pid), kAXHiddenAttribute as CFString, kCFBooleanTrue)", "AXError.cannotComplete"))]:
            negative = original.replace("let appKitAccepted = app.hide()", "let appKitAccepted = false")
            assert negative.count(change[0]) == 1
            negative = negative.replace(*change)
            if name == "rejected":
                negative = negative.replace("let trusted = AXIsProcessTrusted()", "let trusted = true")
            source = cls.directory / f"{name}_controller.swift"
            source.write_text(negative)
            helper = cls.directory / f"mac-application-{name}"
            runner.recorded_output(cls.directory, f"compile-{name}-controller",
                [*runner.macos_swift_command(), str(source), "-o", str(helper)], 120)
            cls.rejected_helpers[name] = helper
        inspector_source = cls.directory / "owned_bundle_instances.swift"
        inspector_source.write_text('''import AppKit
import Foundation
guard CommandLine.arguments.count == 2, CommandLine.arguments[1].hasPrefix("/") else { exit(64) }
let bundle = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
guard let identifier = Bundle(url: bundle)?.bundleIdentifier else { exit(64) }
let instances: [[String: Any]] = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
    .filter { $0.bundleURL?.standardizedFileURL == bundle && !$0.isTerminated }
    .map { ["pid": $0.processIdentifier, "executable": $0.executableURL?.path ?? "unavailable",
            "bundleURL": $0.bundleURL?.path ?? "unavailable", "isTerminated": $0.isTerminated] }
let data = try JSONSerialization.data(withJSONObject: instances, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
''')
        cls.bundle_inspector = cls.directory / "owned-bundle-instances"
        runner.recorded_output(cls.directory, "compile-bundle-inspector",
            [*runner.macos_swift_command(), str(inspector_source), "-o", str(cls.bundle_inspector)], 120)
        cls.launchservices_helper = cls.directory / "launchservices-fixture"
        runner.recorded_output(cls.directory, "compile-launchservices-fixture",
            [*runner.macos_swift_command(), str(runner.HERE / "mac_launchservices_fixture.swift"),
             "-o", str(cls.launchservices_helper)], 120)
        cls.launch_count = 0

    def owned_bundle_snapshot(self, label, *, bundle=None, launch_prefix="fixture"):
        bundle = self.executable.parents[2] if bundle is None else bundle
        instances = json.loads(runner.recorded_output(self.directory, label,
            [str(self.bundle_inspector), str(bundle)], 10))
        return {"instances": instances,
                "launches": [json.loads(path.read_text())
                             for path in sorted(self.directory.glob(f"{launch_prefix}-launch-*.json"))]}

    def wait_for_evidence(self, path, process):
        deadline = time.monotonic() + 15
        while not path.exists():
            self.assertIsNone(process.poll(), f"The owned AppKit application exited before {path.name}")
            if time.monotonic() >= deadline:
                self.fail(f"The owned AppKit application did not produce {path.name}")
            time.sleep(0.05)
        return json.loads(path.read_text())

    def start_owned_app(self, self_hide=False):
        type(self).launch_count += 1
        index = type(self).launch_count
        ready = self.directory / f"ready-{index}.json"
        self_hidden = self.directory / f"self-hidden-{index}.json"
        stream = (self.directory / f"application-{index}.log").open("w")
        command = [str(self.executable), str(ready)]
        if self_hide:
            command.append(str(self_hidden))
        process = subprocess.Popen(command, stdout=stream,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        self.addCleanup(stream.close)
        self.addCleanup(runner.stop_owned, process)
        startup = self.wait_for_evidence(ready, process)
        self.verify_fixture_ready(startup, process.pid)
        return process, startup, self_hidden

    def verify_fixture_ready(self, startup, pid):
        self.assertEqual(startup["pid"], pid)
        self.assertEqual(startup["stage"], "ready")
        self.assertTrue(startup["didFinishLaunchingObserved"])
        self.assertTrue(startup["isRunning"])
        self.assertTrue(startup["mainThread"])
        self.assertTrue(startup["isFinishedLaunching"])
        self.assertGreater(startup["screenCount"], 0)
        self.assertIs(type(startup["policyChangeAccepted"]), bool)
        self.assertEqual(startup["activationPolicy"], 0)
        self.assertTrue(startup["windowCanHide"])
        self.assertTrue(startup["windowVisible"])

    def start_launchservices_app(self):
        type(self).launch_count += 1
        index = type(self).launch_count
        ready = self.directory / f"ready-{index}.json"
        launch_path = self.directory / f"launchservices-{index}-launch.json"
        stop_path = self.directory / f"launchservices-{index}-stop.json"
        stream = (self.directory / f"launchservices-{index}.log").open("w")
        self.addCleanup(stream.close)
        bundle = self.executable.parents[2]
        process = subprocess.Popen([str(self.launchservices_helper), str(bundle), str(ready),
                                    str(launch_path), str(stop_path)], stdin=subprocess.PIPE,
                                   stdout=stream, stderr=subprocess.STDOUT, text=True, start_new_session=True)
        state = {"process": process, "launch": None, "stopPath": stop_path, "closed": False}
        # The retained NSRunningApplication owner cleans its target first. This
        # process-group cleanup belongs only to that owner, never the target PID.
        self.addCleanup(runner.stop_owned, process)
        self.addCleanup(self.close_launchservices_app, state)
        launch = state["launch"] = self.wait_for_evidence(launch_path, process)
        verify_launchservices_launch(launch, owner_pid=process.pid, executable=str(self.executable),
                                     bundle=str(bundle), ready=str(ready))
        startup = self.wait_for_evidence(ready, process)
        self.verify_fixture_ready(startup, launch["pid"])
        state["launchId"] = startup["launchId"]
        return state, startup

    def close_launchservices_app(self, state):
        if state["closed"]:
            return state.get("stop")
        state["closed"] = True
        process = state["process"]
        failure = None
        traceback = None

        def remember(error):
            nonlocal failure, traceback
            if failure is None:
                failure, traceback = error, error.__traceback__
            else:
                runner.warn_cleanup(f"Additional LaunchServices owner cleanup error: {error}")

        try:
            if process.poll() is None:
                process.stdin.write("stop\n")
                process.stdin.flush()
        except Exception as error:
            remember(error)
        try:
            process.stdin.close()
        except Exception as error:
            remember(error)
        try:
            code = process.wait(timeout=25)
            if code != 0:
                raise ValueError(f"LaunchServices owner exited {code}; inspect its stop receipt and log")
        except Exception as error:
            remember(error)
        try:
            stopped = state["stop"] = json.loads(state["stopPath"].read_text())
            verify_launchservices_stop(stopped, state["launch"] or {}, launch_id=state.get("launchId"))
        except Exception as error:
            remember(error)
        if failure is not None:
            raise failure.with_traceback(traceback)
        return state["stop"]

    def test_direct_execution_retains_public_application_identity(self):
        self.exercise_controller(self.helper, "direct-execution")

    def test_opened_bundle_retains_the_original_controller_and_target(self):
        self.exercise_controller(self.helper, "opened-bundle-execution", open_bundle=True)

    def test_missing_ax_trust_or_rejected_request_cannot_report_hidden(self):
        for name, helper in self.rejected_helpers.items():
            with self.subTest(name=name), native_result(self.directory, f"negative-{name}") as report:
                app, report["startup"], _ = self.start_owned_app()
                controller = runner.MacApplicationSession(helper, app.pid, self.directory, f"negative-{name}")
                self.addCleanup(controller.close)
                report["before"] = controller.request("info")
                self.assertFalse(report["before"]["isHidden"])
                with self.assertRaises(ValueError):
                    controller.request("hide")
                controller.close()
                failure = json.loads((self.directory / f"{controller.prefix}.stderr.log").read_text())
                self.assertEqual(failure["stage"], "hide")
                self.assertFalse(failure["hideRequest"]["primaryAccepted"])
                self.assertFalse(failure["applicationState"]["isHidden"])
                if name == "untrusted":
                    self.assertFalse(failure["hideRequest"]["accessibilityTrusted"])
                    self.assertNotIn("fallbackAPI", failure["hideRequest"])
                else:
                    self.assertNotEqual(failure["hideRequest"]["fallbackError"], 0)
                report["rejectedRequest"] = failure

    def test_initial_launchservices_target_uses_the_original_controller(self):
        self.exercise_controller(self.helper, "initial-launchservices-target", launchservices_target=True)

    def exercise_controller(self, helper, label, open_bundle=False, launchservices_target=False):
        with native_result(self.directory, label,
                           targetLaunchMethod=("Initial NSWorkspace.openApplication of the owned target bundle"
                                               if launchservices_target else
                                               "Popen, ready, then open of the same target bundle, matching Flutter profile onAttached"
                                               if open_bundle else "Popen of the target executable"),
                           controllerLaunchMethod="Popen of the controller executable") as report:
            launchservices = None
            if launchservices_target:
                self.assertFalse(open_bundle, "Isolate initial target launch as the only changed variable")
                prior = report["bundleBeforeLaunch"] = self.owned_bundle_snapshot(f"{label}-before-launch")
                self.assertEqual(prior["instances"], [], "The private target bundle is already running")
                launchservices, report["startup"] = self.start_launchservices_app()
                report["launchServices"] = launchservices["launch"]
                target_pid = launchservices["launch"]["pid"]
                snapshot = report["bundleAfterLaunch"] = self.owned_bundle_snapshot(f"{label}-after-launch")
                expected_launch = {"pid": target_pid, "executable": str(self.executable),
                                   "bundle": str(self.executable.parents[2]),
                                   "launch_id": report["startup"]["launchId"]}
                verify_initial_launch(snapshot, prior["launches"], **expected_launch)
                expected_launch["initial_launches"] = snapshot["launches"]
            else:
                app, report["startup"], _ = self.start_owned_app()
                target_pid = app.pid
            controller = runner.MacApplicationSession(helper, target_pid, self.directory, label)
            self.addCleanup(controller.close)
            extra_observations = []
            if open_bundle:
                self.assertIsNone(app.poll(), "The original Popen process exited before open")
                original = report["beforeOpen"] = controller.request("info")
                extra_observations.append(original)
                self.assertFalse(original["isHidden"])
                snapshot = report["bundleBeforeOpen"] = self.owned_bundle_snapshot(f"{label}-before-open")
                expected = {"pid": app.pid, "executable": str(self.executable),
                            "bundle": str(self.executable.parents[2]), "launch_id": report["startup"]["launchId"],
                            "initial_launches": snapshot["launches"]}
                report["openCommandEvidence"] = f"{label}-open.json"
                runner.recorded_output(self.directory, f"{label}-open", ["open", expected["bundle"]], 10)
                self.assertIsNone(app.poll(), "open replaced or terminated the original Popen process")
                snapshot = report["bundleAfterOpen"] = self.owned_bundle_snapshot(f"{label}-after-open")
                verify_open_target(snapshot, **expected)
            before = report["before"] = controller.request("info")
            time.sleep(0.2)
            after = report["after"] = controller.request("info")
            self.assertFalse(after["isHidden"])
            self.assertTrue(after["isActive"])
            hidden = report["hidden"] = controller.request("hide")
            resumed = report["resumed"] = controller.request("activate")
            for value in [*extra_observations, before, after, hidden, resumed]:
                self.assertEqual(value["pid"], target_pid)
                self.assertTrue(value["sameApplication"])
                self.assertEqual(value["identityMethod"], "NSRunningApplication.isEqual")
                self.assertEqual(value["sessionToken"], before["sessionToken"])
                self.assertEqual(value["controllerPid"], controller.process.pid)
                self.assertEqual(value["executable"], str(self.executable))
                self.assertEqual(value["applicationState"]["activationPolicy"], 0)
                self.assertFalse(value["applicationState"]["isTerminated"])
            request = hidden["hideRequest"]
            self.assertEqual(request["primaryAPI"], "NSRunningApplication.hide")
            if not request["primaryAccepted"]:
                self.assertTrue(request["accessibilityTrusted"])
                self.assertEqual(request["fallbackAPI"], "AXUIElementSetAttributeValue(kAXHiddenAttribute)")
                self.assertEqual(request["fallbackError"], 0)
            self.assertTrue(hidden["isHidden"])
            self.assertFalse(resumed["isHidden"])
            self.assertTrue(resumed["isActive"])
            if open_bundle:
                self.assertIsNone(app.poll(), "The original Popen process did not survive hide/resume")
                snapshot = report["bundleAfterResume"] = self.owned_bundle_snapshot(f"{label}-after-resume")
                verify_open_target(snapshot, **expected)
            if launchservices_target:
                self.assertIsNone(launchservices["process"].poll(), "The retained LaunchServices owner exited early")
                snapshot = report["bundleAfterResume"] = self.owned_bundle_snapshot(f"{label}-after-resume")
                verify_open_target(snapshot, **expected_launch)
            controller.close()
            if launchservices_target:
                report["launchServicesCleanup"] = self.close_launchservices_app(launchservices)

    def test_owned_application_can_hide_itself(self):
        with native_result(self.directory, "self-hide", action="NSApplication.hide(nil)") as report:
            app, report["startup"], hidden_path = self.start_owned_app(self_hide=True)
            hidden = report["selfHidden"] = self.wait_for_evidence(hidden_path, app)
            self.assertEqual(hidden["pid"], app.pid)
            self.assertEqual(hidden["stage"], "didHide")
            self.assertTrue(hidden["isHidden"])
            controller = runner.MacApplicationSession(self.helper, app.pid, self.directory, "native-self-hide")
            self.addCleanup(controller.close)
            observation = report["externalObservation"] = controller.request("info")
            self.assertTrue(observation["isHidden"])
            self.assertEqual(observation["executable"], str(self.executable))
            controller.close()

    def test_dead_application_cannot_be_replaced_by_another_process(self):
        with native_result(self.directory, "terminated-identity",
                           identityScope="Two owned AppKit processes, not a forced PID-reuse test") as report:
            app, report["originalStartup"], _ = self.start_owned_app()
            controller = runner.MacApplicationSession(self.helper, app.pid, self.directory, "native-death")
            self.addCleanup(controller.close)
            report["original"] = controller.request("info")
            runner.stop_owned(app)
            replacement, report["replacementStartup"], _ = self.start_owned_app()
            self.assertNotEqual(app.pid, replacement.pid)
            with self.assertRaises(ValueError):
                controller.request("activate")
            controller.close()
            self.assertIsNone(replacement.poll(), "The replacement process was affected by the old controller")
            stderr = (self.directory / "mac-native-death-controller.stderr.log").read_text()
            self.assertIn('"identity"', stderr)
            report.update(originalPid=app.pid, replacementPid=replacement.pid, rejectedOldIdentity=True)


if __name__ == "__main__":
    unittest.main()
