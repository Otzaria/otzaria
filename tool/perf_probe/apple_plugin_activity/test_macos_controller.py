import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time
import unittest

SPEC = importlib.util.spec_from_file_location("apple_native_controller_runner", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)

FIXTURE = '''import AppKit
import Foundation
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 200, height: 100),
                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "Owned identity control"
window.makeKeyAndOrderFront(nil)
app.finishLaunching()
app.activate(ignoringOtherApps: true)
try "ready".write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
app.run()
'''


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
        source = cls.directory / "direct_application.swift"
        source.write_text(FIXTURE)
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
        cls.launch_count = 0

    def start_owned_app(self):
        type(self).launch_count += 1
        index = type(self).launch_count
        ready = self.directory / f"ready-{index}.txt"
        stream = (self.directory / f"application-{index}.log").open("w")
        process = subprocess.Popen([str(self.executable), str(ready)], stdout=stream,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        self.addCleanup(stream.close)
        self.addCleanup(runner.stop_owned, process)
        deadline = time.monotonic() + 15
        while not ready.exists():
            self.assertIsNone(process.poll(), "The owned AppKit application exited before readiness")
            if time.monotonic() >= deadline:
                self.fail("The owned AppKit application did not become ready")
            time.sleep(0.05)
        return process

    def test_direct_execution_retains_public_application_identity(self):
        app = self.start_owned_app()
        controller = runner.MacApplicationSession(self.helper, app.pid, self.directory, "native-direct")
        self.addCleanup(controller.close)
        before = controller.request("info")
        time.sleep(0.2)
        after = controller.request("info")
        hidden = controller.request("hide")
        resumed = controller.request("activate")
        for value in [before, after, hidden, resumed]:
            self.assertEqual(value["pid"], app.pid)
            self.assertTrue(value["sameApplication"])
            self.assertEqual(value["identityMethod"], "NSRunningApplication.isEqual")
            self.assertEqual(value["sessionToken"], before["sessionToken"])
            self.assertEqual(value["controllerPid"], controller.process.pid)
            self.assertEqual(value["executable"], str(self.executable))
        self.assertTrue(hidden["isHidden"])
        self.assertFalse(resumed["isHidden"])
        self.assertTrue(resumed["isActive"])
        runner.save(self.directory / "direct-execution.json", {
            "status": "passed", "launchMethod": "Popen of the executable; no open/LaunchServices launch",
            "scope": "Owned AppKit helper control, not an Otzaria quiet measurement",
            "before": before, "after": after, "hidden": hidden, "resumed": resumed,
        })

    def test_dead_application_cannot_be_replaced_by_another_process(self):
        app = self.start_owned_app()
        controller = runner.MacApplicationSession(self.helper, app.pid, self.directory, "native-death")
        self.addCleanup(controller.close)
        before = controller.request("info")
        runner.stop_owned(app)
        replacement = self.start_owned_app()
        self.assertNotEqual(app.pid, replacement.pid)
        with self.assertRaises(ValueError):
            controller.request("activate")
        controller.close()
        self.assertIsNone(replacement.poll(), "The replacement process was affected by the old controller")
        stderr = (self.directory / "mac-native-death-controller.stderr.log").read_text()
        self.assertIn('"identity"', stderr)
        runner.save(self.directory / "terminated-identity.json", {
            "status": "passed", "original": before, "replacementPid": replacement.pid,
            "originalPid": app.pid, "rejectedOldIdentity": True,
            "scope": "Two owned AppKit processes, not a forced PID-reuse test",
        })


if __name__ == "__main__":
    unittest.main()
