import importlib.util
from contextlib import contextmanager
import hashlib
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
        raise ValueError("The original Popen launch identity is missing or inconsistent")


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
        runner.recorded_output(cls.directory, "swift-version", ["xcrun", "swiftc", "--version"], 30)
        source = cls.directory / "direct_application.swift"
        source.write_text((runner.HERE / "mac_control_fixture.swift").read_text())
        bundle = cls.directory / "DirectIdentity.app"
        cls.executable = bundle / "Contents/MacOS/DirectIdentity"
        cls.executable.parent.mkdir(parents=True)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "DirectIdentity", "CFBundleIdentifier": "org.otzaria.identitycontrol",
            "CFBundleName": "DirectIdentity", "CFBundlePackageType": "APPL",
            "LSMinimumSystemVersion": "11.0", "NSHighResolutionCapable": True,
        }))
        cls.helper = cls.directory / "mac-application"
        runner.recorded_output(cls.directory, "compile-owned-application",
            ["xcrun", "swiftc", str(source), "-o", str(cls.executable)], 120)
        runner.recorded_output(cls.directory, "compile-controller",
            ["xcrun", "swiftc", str(runner.HERE / "mac_application.swift"), "-o", str(cls.helper)], 120)
        original = (runner.HERE / "mac_application.swift").read_text()
        imports = "import AppKit\nimport Foundation\n"
        assert original.startswith(imports)
        addition = "\nlet diagnosticApplication = NSApplication.shared\n"
        initialized = imports + addition + original[len(imports):]
        initialized_source = cls.directory / "initialized_controller.swift"
        initialized_source.write_text(initialized)
        cls.initialized_helper = cls.directory / "mac-application-initialized"
        runner.save(cls.directory / "initialized-variant.json", {
            "difference": addition.strip(),
            "productionSHA256": hashlib.sha256(original.encode()).hexdigest(),
            "diagnosticSHA256": hashlib.sha256(initialized.encode()).hexdigest(),
            "scope": "Separate diagnostic binary; never selected as an actual-app fallback or retry",
        })
        runner.recorded_output(cls.directory, "compile-initialized-controller",
            ["xcrun", "swiftc", str(initialized_source), "-o", str(cls.initialized_helper)], 120)
        event_loop = imports + '''
let diagnosticApplication = NSApplication.shared
let diagnosticPolicyAccepted = diagnosticApplication.setActivationPolicy(.accessory)
var diagnosticLaunchObserved = false
func serveController() throws {
''' + original[len(imports):] + '''
}
let diagnosticObserver = NotificationCenter.default.addObserver(
    forName: NSApplication.didFinishLaunchingNotification, object: diagnosticApplication, queue: nil
) { _ in
    guard !diagnosticLaunchObserved else { return }
    diagnosticLaunchObserved = true
    DispatchQueue.main.async {
        let ready: [String: Any] = [
            "didFinishLaunchingObserved": diagnosticLaunchObserved,
            "isRunning": diagnosticApplication.isRunning, "mainThread": Thread.isMainThread,
            "policyAccepted": diagnosticPolicyAccepted,
            "activationPolicy": diagnosticApplication.activationPolicy().rawValue
        ]
        let data = try! JSONSerialization.data(withJSONObject: ready, options: [.sortedKeys])
        fputs(String(decoding: data, as: UTF8.self) + "\\n", stderr)
        guard diagnosticApplication.isRunning, Thread.isMainThread,
              diagnosticApplication.activationPolicy() == .accessory else { exit(65) }
        do { try serveController(); exit(0) }
        catch { fputs(String(describing: error) + "\\n", stderr); exit(1) }
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    if !diagnosticLaunchObserved { exit(65) }
}
diagnosticApplication.run()
'''
        event_loop_source = cls.directory / "event_loop_controller.swift"
        event_loop_source.write_text(event_loop)
        cls.event_loop_helper = cls.directory / "mac-application-event-loop"
        runner.save(cls.directory / "event-loop-variant.json", {
            "productionSHA256": hashlib.sha256(original.encode()).hexdigest(),
            "diagnosticSHA256": hashlib.sha256(event_loop.encode()).hexdigest(),
            "scope": "Retained controller code after actual AppKit launch, with accessory policy; no fallback or changed hide guard",
        })
        runner.recorded_output(cls.directory, "compile-event-loop-controller",
            ["xcrun", "swiftc", str(event_loop_source), "-o", str(cls.event_loop_helper)], 120)
        assert event_loop.count(".accessory") == 2
        active = event_loop.replace(".accessory", ".regular")
        observation = '        result["controllerEventLoopRunning"] = controllerApplication.isRunning\n'
        assert active.count(observation) == 1
        active = active.replace(observation, observation + '''
        result["controllerIsActive"] = controllerApplication.isActive
        result["controllerOwnsMenuBar"] = NSRunningApplication.current.ownsMenuBar
        result["controllerBundleIdentifier"] = Bundle.main.bundleIdentifier ?? "unavailable"
        result["controllerLaunchDateAvailable"] = NSRunningApplication.current.launchDate != nil
        result["frontmostApplicationPid"] = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
''')
        hide = '    if action == "hide" {\n'
        assert active.count(hide) == 1
        active = active.replace(hide, hide + '''
        diagnosticApplication.activate(ignoringOtherApps: true)
        let activationDeadline = ProcessInfo.processInfo.systemUptime + 5
        while !diagnosticApplication.isActive && ProcessInfo.processInfo.systemUptime < activationDeadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.025))
        }
        let activation: [String: Any] = [
            "stage": "controllerActivation", "applicationState": applicationState(),
            "controllerPid": ProcessInfo.processInfo.processIdentifier
        ]
        let activationData = try JSONSerialization.data(withJSONObject: activation, options: [.sortedKeys])
        fputs(String(decoding: activationData, as: UTF8.self) + "\\n", stderr)
        guard diagnosticApplication.isActive else {
            fail("controllerActivation", "The regular controller did not become active", 66,
                 ["applicationState": applicationState()])
        }
''')
        active_source = cls.directory / "active_regular_controller.swift"
        active_source.write_text(active)
        cls.active_helper = cls.directory / "mac-application-active-regular"
        runner.save(cls.directory / "active-regular-variant.json", {
            "productionSHA256": hashlib.sha256(original.encode()).hexdigest(),
            "diagnosticSHA256": hashlib.sha256(active.encode()).hexdigest(),
            "scope": "Regular caller must become active before the unchanged hide request; separate diagnostic only",
        })
        runner.recorded_output(cls.directory, "compile-active-regular-controller",
            ["xcrun", "swiftc", str(active_source), "-o", str(cls.active_helper)], 120)
        controller_bundle = cls.directory / "IdentityController.app"
        cls.bundled_active_helper = controller_bundle / "Contents/MacOS/IdentityController"
        cls.bundled_active_helper.parent.mkdir(parents=True)
        shutil.copy2(cls.active_helper, cls.bundled_active_helper)
        (controller_bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "IdentityController", "CFBundleIdentifier": "org.otzaria.identitycontroller",
            "CFBundleName": "IdentityController", "CFBundlePackageType": "APPL",
            "LSMinimumSystemVersion": "11.0", "NSHighResolutionCapable": True,
        }))
        runner.save(cls.directory / "bundled-active-variant.json", {
            "binarySHA256": hashlib.sha256(cls.active_helper.read_bytes()).hexdigest(),
            "bundleIdentifier": "org.otzaria.identitycontroller",
            "launchMethod": "Direct Popen of the identical active-regular binary inside its own application bundle",
            "scope": "Caller bundle metadata is the only change from active-regular-execution; not a LaunchServices launch",
        })
        marker = "// Keep this object alive across quiet. readLine blocks without a run loop,\n"
        assert original.count(marker) == 1
        retained_identity = original.split(marker)[0]
        assert retained_identity.count(observation) == 1
        retained_identity = retained_identity.replace(observation, observation + '''
        result["controllerIsActive"] = controllerApplication.isActive
        result["controllerOwnsMenuBar"] = NSRunningApplication.current.ownsMenuBar
        result["controllerBundleIdentifier"] = Bundle.main.bundleIdentifier ?? "unavailable"
        result["frontmostApplicationPid"] = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
''')
        dispatch_source = cls.directory / "dispatch_controller.swift"
        dispatch = retained_identity + (runner.HERE / "mac_controller_dispatch_diagnostic.swift").read_text()
        dispatch_source.write_text(dispatch)
        cls.dispatch_helper = cls.directory / "mac-application-dispatch"
        cls.active_dispatch_helper = cls.directory / "mac-application-active-dispatch"
        for label, executable, flags in [
                ("dispatch", cls.dispatch_helper, []),
                ("active-dispatch", cls.active_dispatch_helper, ["-D", "ACTIVE_CONTROLLER"])]:
            runner.save(cls.directory / f"{label}-variant.json", {
                "productionSHA256": hashlib.sha256(original.encode()).hexdigest(),
                "diagnosticSHA256": hashlib.sha256(dispatch.encode()).hexdigest(),
                "compilerFlags": flags,
                "scope": "Worker stdin with asynchronous main-thread commands and acknowledgement continuations; retained production identity and unchanged hide/hidden gates; diagnostic only",
            })
            runner.recorded_output(cls.directory, f"compile-{label}-controller",
                ["xcrun", "swiftc", str(dispatch_source), *flags, "-o", str(executable)], 120)
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
            ["xcrun", "swiftc", str(inspector_source), "-o", str(cls.bundle_inspector)], 120)
        cls.launch_count = 0

    def owned_bundle_snapshot(self, label):
        bundle = self.executable.parents[2]
        instances = json.loads(runner.recorded_output(self.directory, label,
            [str(self.bundle_inspector), str(bundle)], 10))
        return {"instances": instances,
                "launches": [json.loads(path.read_text())
                             for path in sorted(self.directory.glob("fixture-launch-*.json"))]}

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
        self.assertEqual(startup["pid"], process.pid)
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
        return process, startup, self_hidden

    def test_direct_execution_retains_public_application_identity(self):
        self.exercise_controller(self.helper, "direct-execution")

    def test_initialized_controller_is_an_independent_diagnostic(self):
        self.exercise_controller(self.initialized_helper, "initialized-execution", initialized=True)

    def test_event_loop_controller_is_an_independent_diagnostic(self):
        self.exercise_controller(self.event_loop_helper, "event-loop-execution", initialized=True)

    def test_foreground_prepared_controller_is_an_independent_diagnostic(self):
        self.exercise_controller(self.event_loop_helper, "foreground-prepared-execution", initialized=True,
                                 prepare_foreground=True)

    def test_active_regular_controller_is_an_independent_diagnostic(self):
        self.exercise_controller(self.active_helper, "active-regular-execution", initialized=True,
                                 prepare_foreground=True, hide_timeout=15)

    def test_bundled_active_controller_is_an_independent_diagnostic(self):
        self.exercise_controller(self.bundled_active_helper, "bundled-active-execution", initialized=True,
                                 prepare_foreground=True, hide_timeout=15)

    def test_dispatching_controller_is_an_independent_diagnostic(self):
        self.exercise_controller(self.dispatch_helper, "dispatch-execution", initialized=True,
                                 prepare_foreground=True, asynchronous_dispatch=True)

    def test_active_dispatching_controller_is_an_independent_diagnostic(self):
        self.exercise_controller(self.active_dispatch_helper, "active-dispatch-execution", initialized=True,
                                 prepare_foreground=True, hide_timeout=15, asynchronous_dispatch=True)

    def test_opened_bundle_with_original_controller_is_an_independent_diagnostic(self):
        self.exercise_controller(self.helper, "opened-bundle-execution", open_bundle=True)

    def test_opened_bundle_with_dispatching_controller_is_an_independent_diagnostic(self):
        self.exercise_controller(self.dispatch_helper, "opened-bundle-dispatch-execution", initialized=True,
                                 asynchronous_dispatch=True, open_bundle=True)

    def exercise_controller(self, helper, label, initialized=False, prepare_foreground=False, hide_timeout=10,
                            asynchronous_dispatch=False, open_bundle=False):
        with native_result(self.directory, label,
                           launchMethod=("Popen, ready, then open of the same bundle, matching Flutter profile onAttached"
                                         if open_bundle else "Popen of the executable; no open/LaunchServices launch"),
                           diagnosticInitialization=initialized) as report:
            app, report["startup"], _ = self.start_owned_app()
            controller = runner.MacApplicationSession(helper, app.pid, self.directory, label)
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
            if prepare_foreground:
                report["foregroundBeforeControl"] = controller.request("activate")
            before = report["before"] = controller.request("info")
            time.sleep(0.2)
            after = report["after"] = controller.request("info")
            self.assertFalse(after["isHidden"])
            self.assertTrue(after["isActive"])
            if initialized:
                self.assertTrue(after["applicationState"]["controllerAppKitInitialized"])
            hidden = report["hidden"] = controller.request("hide", timeout=hide_timeout)
            resumed = report["resumed"] = controller.request("activate")
            for value in [*extra_observations, before, after, hidden, resumed]:
                self.assertEqual(value["pid"], app.pid)
                self.assertTrue(value["sameApplication"])
                self.assertEqual(value["identityMethod"], "NSRunningApplication.isEqual")
                self.assertEqual(value["sessionToken"], before["sessionToken"])
                self.assertEqual(value["controllerPid"], controller.process.pid)
                self.assertEqual(value["executable"], str(self.executable))
                self.assertEqual(value["applicationState"]["activationPolicy"], 0)
                self.assertFalse(value["applicationState"]["isTerminated"])
                if asynchronous_dispatch:
                    self.assertTrue(value["mainQueueTurnDelivered"])
                    self.assertEqual(value["controllerBoundaryMode"], "asynchronous-main-dispatch")
            if asynchronous_dispatch:
                self.assertTrue(hidden["hideReturnValue"])
            self.assertTrue(hidden["isHidden"])
            self.assertFalse(resumed["isHidden"])
            self.assertTrue(resumed["isActive"])
            if open_bundle:
                self.assertIsNone(app.poll(), "The original Popen process did not survive hide/resume")
                snapshot = report["bundleAfterResume"] = self.owned_bundle_snapshot(f"{label}-after-resume")
                verify_open_target(snapshot, **expected)
            controller.close()

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
