import importlib.util
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import subprocess
import sys
import tempfile
import time
import unittest

SPEC = importlib.util.spec_from_file_location("apple_native_controller_runner", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)

@contextmanager
def native_result(directory, label, **details):
    report = {"status": "running", "scope": "Owned AppKit helper control, not an Otzaria quiet measurement", **details}
    failures = runner.Failures(report)
    try:
        yield report
    except BaseException as error:
        failures.add("native control", error)
        report["errorType"] = type(error).__name__
    else:
        report["status"] = "passed"
    finally:
        failures.attempt("native control receipt", lambda: runner.save(directory / f"{label}.json", report))
        failures.raise_if_any()


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
            "productionControllerUsesNSApplicationRun": True,
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
        cls.launcher = cls.directory / "launch-services-fixture"
        runner.recorded_output(cls.directory, "compile-launch-services-fixture",
            ["xcrun", "swiftc", "-target", f"{platform.machine()}-apple-macos11.0",
             str(runner.HERE / "mac_launch_fixture.swift"), "-o", str(cls.launcher)], 120)
        cls.launch_count = 0

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
        self.assertIs(type(startup["policyChangeAccepted"]), bool)
        self.assertEqual(startup["activationPolicy"], 0)
        self.assertTrue(startup["windowCanHide"])
        self.assertTrue(startup["windowVisible"])
        return process, startup, self_hidden

    def test_direct_execution_retains_public_application_identity(self):
        self.exercise_controller(self.helper, "direct-execution")

    def test_same_fixture_through_launch_services(self):
        self.exercise_controller(self.helper, "launch-services-execution", launch_services=True)

    def start_launch_services(self):
        type(self).launch_count += 1
        index = type(self).launch_count
        ready = self.directory / f"ready-{index}.json"
        receipt = self.directory / f"launch-services-{index}.json"
        log = (self.directory / f"launch-services-{index}.log").open("w")
        process = subprocess.Popen([str(self.launcher), str(self.executable.parents[2]), str(ready), str(receipt)],
            stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        self.addCleanup(log.close)
        def close():
            failures = runner.Failures({})
            failures.attempt("close LaunchServices ownership pipe", process.stdin.close)
            code = failures.attempt("wait LaunchServices owned cleanup", lambda: process.wait(timeout=12))
            failures.attempt("stop LaunchServices helper", lambda: runner.stop_owned(process))
            if code != 0:
                failures.add("LaunchServices cleanup", RuntimeError(f"Owned fixture cleanup exit: {code}"))
            failures.raise_if_any()
        self.addCleanup(close)
        launch = self.wait_for_evidence(receipt, process)
        self.assertEqual(launch["stage"], "launched")
        self.assertTrue(launch["controllerEventLoopRunning"])
        startup = self.wait_for_evidence(ready, process)
        self.assertEqual(startup["pid"], launch["pid"])
        self.assertEqual(launch["executable"], str(self.executable))
        return startup, launch

    def exercise_controller(self, helper, label, launch_services=False):
        with native_result(self.directory, label,
                           launchMethod="NSWorkspace.openApplication" if launch_services else "direct executable") as report:
            if launch_services:
                report["startup"], report["launchServices"] = self.start_launch_services()
            else:
                _, report["startup"], _ = self.start_owned_app()
            target_pid = report["startup"]["pid"]
            controller = runner.MacApplicationSession(helper, target_pid, self.directory, label)
            self.addCleanup(controller.close)
            before = report["before"] = controller.request("info")
            time.sleep(0.2)
            after = report["after"] = controller.request("info")
            self.assertFalse(after["isHidden"])
            self.assertTrue(after["isActive"])
            self.assertTrue(after["applicationState"]["controllerEventLoopRunning"])
            if launch_services:
                self.assertIsNotNone(after["launchMs"])
            hidden = report["hidden"] = controller.request("hide")
            resumed = report["resumed"] = controller.request("activate")
            for value in [before, after, hidden, resumed]:
                self.assertEqual(value["pid"], target_pid)
                self.assertTrue(value["sameApplication"])
                self.assertEqual(value["identityMethod"], "NSRunningApplication.isEqual")
                self.assertEqual(value["sessionToken"], before["sessionToken"])
                self.assertEqual(value["controllerPid"], controller.process.pid)
                self.assertEqual(value["executable"], str(self.executable))
                self.assertEqual(value["applicationState"]["activationPolicy"], 0)
                self.assertFalse(value["applicationState"]["isTerminated"])
            self.assertTrue(hidden["returnValue"])
            self.assertTrue(hidden["isHidden"])
            self.assertFalse(resumed["isHidden"])
            self.assertTrue(resumed["isActive"])
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
