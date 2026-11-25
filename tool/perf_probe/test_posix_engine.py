"""Bundled-engine ownership contracts, including a real Linux mapped library."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from tool.perf_probe.posix_engine import BundledFlutterEngine, darwin_engine_images, linux_engine_images


class EngineIdentityTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="pdf engine ownership ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()

    def bundle(self, name="candidate", system="linux"):
        root = self.root / name
        if system == "linux":
            executable, image = root / "otzaria", root / "lib/libflutter_linux_gtk.so"
        else:
            app = root / "אוצריא.app"
            executable = app / "Contents/MacOS/otzaria"
            framework = app / "Contents/Frameworks/FlutterMacOS.framework"
            image = framework / "Versions/A/FlutterMacOS"
            image.parent.mkdir(parents=True)
            (framework / "Versions/Current").symlink_to("A")
            (framework / "FlutterMacOS").symlink_to("Versions/Current/FlutterMacOS")
        executable.parent.mkdir(parents=True, exist_ok=True)
        image.parent.mkdir(parents=True, exist_ok=True)
        executable.write_bytes(b"owned executable fixture")
        image.write_bytes(b"engine bytes, identical between snapshots")
        return executable, image

    def test_identity_compares_bytes_not_checkout_paths(self):
        for system in ("linux", "macos"):
            with self.subTest(system=system):
                left, _ = self.bundle("baseline-" + system, system)
                right, _ = self.bundle("candidate-" + system, system)
                first = BundledFlutterEngine(left, system, "profile")
                second = BundledFlutterEngine(right, system, "profile")
                self.assertNotEqual(first.path, second.path)
                self.assertEqual(first.identity, second.identity)
                self.assertNotIn(str(self.root), str(first.identity))
                first.verify_unchanged()

    def test_changed_bytes_and_retargeted_framework_are_rejected(self):
        executable, image = self.bundle()
        engine = BundledFlutterEngine(executable, "linux", "profile")
        image.write_bytes(b"a different engine")
        with self.assertRaisesRegex(RuntimeError, "bytes changed"):
            engine.verify_unchanged()
        executable, image = self.bundle("apple", "macos")
        engine = BundledFlutterEngine(executable, "macos", "profile")
        other = image.parent.parent / "B"
        other.mkdir()
        (other / image.name).write_bytes(image.read_bytes())
        current = image.parent.parent / "Current"
        current.unlink()
        current.symlink_to("B")
        with self.assertRaisesRegex(RuntimeError, "path changed"):
            engine.verify_unchanged()

    def test_missing_empty_and_external_engine_are_rejected(self):
        executable, image = self.bundle()
        image.write_bytes(b"")
        with self.assertRaisesRegex(RuntimeError, "nonempty"):
            BundledFlutterEngine(executable, "linux", "profile")
        image.unlink()
        with self.assertRaises(FileNotFoundError):
            BundledFlutterEngine(executable, "linux", "profile")
        foreign = self.root / "foreign-engine"
        foreign.write_bytes(b"same filename is not bundle ownership")
        image.symlink_to(foreign)
        with self.assertRaisesRegex(RuntimeError, "outside"):
            BundledFlutterEngine(executable, "linux", "profile")

    def test_linux_maps_keep_spaces_device_and_inode_and_reject_deleted_image(self):
        source = "1230-4560 r-xp 0 08:0f 789 /a path/libflutter_linux_gtk.so\n"
        self.assertEqual(linux_engine_images(source, "libflutter_linux_gtk.so"), [
            {"path": "/a path/libflutter_linux_gtk.so", "inode": 789, "device": (8, 15)}])
        with self.assertRaisesRegex(RuntimeError, "deleted"):
            linux_engine_images(source.rstrip() + " (deleted)\n", "libflutter_linux_gtk.so")

    def test_darwin_machine_output_keeps_full_framework_path_and_process_identity(self):
        path = "/a path/אוצריא.app/Contents/Frameworks/FlutterMacOS.framework/Versions/A/FlutterMacOS"
        output = f"p42\0cotzaria\0\nftext\0n/ignored/file\0\nftxt\0n{path}\0\n"
        # A non-text file is rejected even if its name is unrelated to the engine.
        with self.assertRaisesRegex(RuntimeError, "text mapping"):
            darwin_engine_images(output, 42, "FlutterMacOS")
        output = f"p42\0cotzaria\0\nftxt\0n{path}\0\n"
        self.assertEqual(darwin_engine_images(output, 42, "FlutterMacOS"), [{"path": path}])
        for invalid in ("", output.replace("p42", "p24"), output + "p42\0", output.replace("ftxt", "f3")):
            with self.subTest(output=invalid), self.assertRaises(RuntimeError):
                darwin_engine_images(invalid, 42, "FlutterMacOS")

    @unittest.skipUnless(sys.platform == "linux", "The live /proc mapping test requires Linux")
    def test_live_owned_library_is_verified_and_another_bundle_is_rejected(self):
        executable, image = self.bundle()
        # A copy is a distinct inode, so the loader cannot reuse Python's own libm mapping.
        paths = [line.split(maxsplit=5)[5] for line in Path("/proc/self/maps").read_text().splitlines()
                 if len(line.split(maxsplit=5)) == 6 and "/libm.so." in line]
        self.assertTrue(paths, "The Python process must expose its native math library")
        shutil.copyfile(paths[0], image)
        engine = BundledFlutterEngine(executable, "linux", "profile")
        child = subprocess.Popen([sys.executable, "-u", "-c",
            "import ctypes,sys; library=ctypes.CDLL(sys.argv[1]); print('loaded'); sys.stdin.read()", str(image)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertEqual(child.stdout.readline().strip(), "loaded")
            proof = engine.observe_loaded(child.pid)
            self.assertEqual(proof["pid"], child.pid)
            self.assertEqual(proof["canonicalPath"], str(image))
            self.assertEqual(proof["identity"], engine.identity)
            foreign_executable, foreign_image = self.bundle("another bundle")
            shutil.copyfile(image, foreign_image)
            foreign = BundledFlutterEngine(foreign_executable, "linux", "profile")
            with self.assertRaisesRegex(RuntimeError, "exactly its bundled"):
                foreign.observe_loaded(child.pid)
        finally:
            child.stdin.close()
            child.wait(timeout=5)
            child.stdout.close()
            child.stderr.close()


if __name__ == "__main__":
    unittest.main()
