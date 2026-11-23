"""Identify the bundled Flutter engine and the image mapped by an owned process."""

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess


def binary_identity(path):
    with path.open("rb") as source:
        before = os.fstat(source.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_size <= 0:
            raise RuntimeError("The bundled Flutter engine is not a nonempty regular file")
        digest = hashlib.file_digest(source, "sha256").hexdigest()
        after = os.fstat(source.fileno())
    for field in ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns"):
        if getattr(before, field) != getattr(after, field):
            raise RuntimeError("The bundled Flutter engine changed while hashing it")
    return {"bytes": after.st_size, "bundleSha256": digest}


def linux_engine_images(source, name):
    images = []
    for line in source.splitlines():
        fields = line.split(maxsplit=5)
        if len(fields) != 6:
            continue
        path = fields[5]
        deleted = path.endswith(" (deleted)")
        if PurePosixPath(path.removesuffix(" (deleted)")).name != name:
            continue
        if deleted or not PurePosixPath(path).is_absolute():
            raise RuntimeError("The mapped Flutter engine was deleted or has no absolute path")
        device = fields[3].split(":")
        if len(device) != 2:
            raise RuntimeError("The mapped Flutter engine has no device identity")
        images.append({"path": path, "inode": int(fields[4]),
                       "device": tuple(int(part, 16) for part in device)})
    return images


def darwin_engine_images(source, pid, name):
    # -F0 separates fields with NUL; newline separates process/file records.
    process_seen, descriptor, paths = False, None, []
    for raw in source.split("\0"):
        field = raw.removeprefix("\n")
        if not field:
            continue
        kind, value = field[0], field[1:]
        if kind == "p":
            if process_seen or value != str(pid):
                raise RuntimeError("The mapped-image observation belongs to another process")
            process_seen, descriptor = True, None
        elif kind == "f":
            descriptor = value
        elif kind == "n":
            if not process_seen or descriptor != "txt":
                raise RuntimeError("The mapped-image observation is not a process text mapping")
            if PurePosixPath(value).name == name:
                if not PurePosixPath(value).is_absolute():
                    raise RuntimeError("The mapped Flutter engine has no absolute path")
                paths.append({"path": value})
    if not process_seen:
        raise RuntimeError("Missing process identity in the mapped-image observation")
    return paths


class BundledFlutterEngine:
    def __init__(self, executable, system, mode):
        executable = executable.resolve(strict=True)
        if system == "linux":
            self.bundle = executable.parent
            self.entry = self.bundle / "lib/libflutter_linux_gtk.so"
        elif system == "macos":
            self.bundle = executable.parents[2]
            if (executable.parent.name != "MacOS" or executable.parent.parent.name != "Contents"
                    or self.bundle.suffix != ".app"):
                raise RuntimeError("The measured executable is not inside a macOS app bundle")
            self.entry = self.bundle / "Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS"
        else:
            raise ValueError("Bundled Flutter engine evidence requires Linux or macOS")
        self.system = system
        self.path = self.entry.resolve(strict=True)
        if not self.path.is_relative_to(self.bundle):
            raise RuntimeError("The bundled Flutter engine points outside the measured app bundle")
        self.identity = {"schemaVersion": 1, "platform": system, "buildMode": mode,
                         "binaryName": self.path.name, **binary_identity(self.path)}

    def verify_unchanged(self):
        if self.entry.resolve(strict=True) != self.path:
            raise RuntimeError("The bundled Flutter engine path changed during measurement")
        actual = binary_identity(self.path)
        if any(actual[key] != self.identity[key] for key in actual):
            raise RuntimeError("The bundled Flutter engine bytes changed during measurement")

    def observe_loaded(self, pid, *, raw_path=None):
        self.verify_unchanged()
        error, exit_code = "", 0
        if self.system == "linux":
            origin = f"/proc/{pid}/maps"
            output = Path(origin).read_text(encoding="utf-8")
        else:
            command = ["lsof", "-a", "-p", str(pid), "-d", "txt", "-Fpcfn0"]
            result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", timeout=30)
            origin, output = "lsof -a -p <owned PID> -d txt -Fpcfn0", result.stdout
            error, exit_code = result.stderr, result.returncode
        if raw_path is not None:
            raw_path.write_text(json.dumps({"source": origin, "pid": pid, "stdout": output,
                                           "stderr": error, "exitCode": exit_code}) + "\n", encoding="utf-8")
        if exit_code or error.strip():
            raise RuntimeError(f"Cannot observe the owned process's engine mappings: {error.strip()}")
        images = (linux_engine_images(output, self.path.name) if self.system == "linux"
                  else darwin_engine_images(output, pid, self.path.name))
        paths = {Path(image["path"]).resolve(strict=True) for image in images}
        if paths != {self.path}:
            raise RuntimeError("The owned process did not map exactly its bundled Flutter engine")
        if self.system == "linux":
            observed = self.path.stat()
            if any(image["inode"] != observed.st_ino
                   or image["device"] != (os.major(observed.st_dev), os.minor(observed.st_dev))
                   for image in images):
                raise RuntimeError("The mapped Flutter engine inode differs from the bundled file")
        self.verify_unchanged()
        return {"source": origin, "pid": pid, "canonicalPath": str(self.path),
                "bundleRelativePath": str(self.path.relative_to(self.bundle)),
                "identity": self.identity, "rawObservation": output}
