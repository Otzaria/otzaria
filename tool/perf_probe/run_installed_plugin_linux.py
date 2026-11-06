#!/usr/bin/env python3
"""Run the installed-plugin profile binary in an owned X11/DBus/WM session."""

import argparse
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time


class Interrupted(Exception):
    def __init__(self, signum):
        self.signum = signum


def interrupt(signum, _frame):
    raise Interrupted(signum)


def write_report(directory, report):
    path = directory / "session.json"
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def observe(command, timeout=10):
    try:
        result = subprocess.run(command, capture_output=True, text=True,
                                timeout=timeout, check=False)
        return {"command": command, "exitCode": result.returncode,
                "availability": "collected" if result.returncode == 0 else "unavailable",
                "stdout": result.stdout, "stderr": result.stderr}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"command": command, "availability": "unavailable", "reason": str(error)}


def require_observation(observation):
    if observation["availability"] != "collected":
        raise RuntimeError(f"Required session observation failed: {observation}")


def signal_owned_group(pid, signum):
    try:
        os.killpg(pid, signum)
    except ProcessLookupError:
        pass


def run_owned(command, seconds, environment):
    process = subprocess.Popen(command, env=environment, start_new_session=True)
    try:
        return process.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        return 124
    finally:
        # The group was created by this runner; never match unrelated process names.
        signal_owned_group(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass
        finally:
            signal_owned_group(process.pid, signal.SIGKILL)
            process.wait(timeout=5)


def inspect_bundle(binary):
    library = binary.parent / "lib"
    required = [binary, library / "WPEWebProcess", library / "WPENetworkProcess",
                library / "libWPEInjectedBundle.so"]
    for pattern in ("libWPEWebKit-2.0.so*", "libWPEPlatform-2.0.so*", "libwpe-1.0.so*"):
        matches = sorted(library.glob(pattern))
        if not matches:
            raise RuntimeError(f"Missing bundled runtime: {pattern}")
        required.append(matches[0])
    gpu = library / "WPEGPUProcess"
    if gpu.exists():
        required.append(gpu)
    result = []
    for path in required:
        mode = stat.S_IMODE(path.stat().st_mode)
        if (path == binary or path.name.endswith("Process")) and not mode & 0o111:
            raise RuntimeError(f"Bundled executable has no execute bit: {path}")
        dependencies = observe(["ldd", str(path)])
        result.append({"path": str(path), "mode": oct(mode), "dependencies": dependencies})
        require_observation(dependencies)
        if "not found" in dependencies["stdout"]:
            raise RuntimeError(f"Unresolved bundled dependencies: {path}: {dependencies['stdout']}")
    return result


def require_fresh_reports(root):
    if root.exists() and (not root.is_dir() or any(root.iterdir())):
        raise RuntimeError("Host report directory must be absent or empty; existing evidence is preserved")


def require_linux_result(root):
    reports = sorted(root.glob("run-*/report.json"))
    if len(reports) != 1:
        raise RuntimeError("Expected one fresh driver report for the Linux scenario")
    report = json.loads(reports[0].read_text(encoding="utf-8"))["installedPluginProbe"]
    if any(report.get(key) != value for key, value in (
        ("status", "passed"), ("platform", "linux"), ("buildMode", "profile"),
        ("errors", []), ("contractErrors", []), ("policyRestored", True),
    )):
        raise RuntimeError("Driver report does not confirm a passed Linux profile scenario")
    run_id = report.get("runId")
    if not isinstance(run_id, str) or not run_id.strip():
        raise RuntimeError("Driver report must have a nonempty runId string")
    phases = {}
    for phase in report["phases"]:
        name = phase["name"]
        if name in phases:
            raise RuntimeError(f"Driver report has a duplicate phase name: {name}")
        phases[name] = phase["status"]
    if any(phases.get(name) != "passed" for name in ("minimize", "hide")):
        raise RuntimeError("Linux minimize and hide must pass with native acknowledgements")
    return {"path": str(reports[0]), "runId": run_id, "status": "passed"}


def session(directory, binary):
    report = json.loads((directory / "session.json").read_text(encoding="utf-8"))
    wm = None
    try:
        with (directory / "openbox.log").open("w", encoding="utf-8") as log:
            wm = subprocess.Popen(["openbox", "--sm-disable"], stdout=log,
                                  stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 20
        while True:
            manager = observe(["wmctrl", "-m"], timeout=2)
            if manager.get("exitCode") == 0 and "Name: Openbox" in manager["stdout"]:
                break
            if wm.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError(f"Openbox did not acquire the X11 display: {manager}")
            time.sleep(0.1)
        report["windowManager"] = manager
        report["environment"] = {key: os.environ.get(key) for key in (
            "DISPLAY", "XDG_RUNTIME_DIR", "XDG_SESSION_TYPE", "GDK_BACKEND",
            "LANG", "LC_ALL", "LD_LIBRARY_PATH", "PKG_CONFIG_PATH",
            "LIBGL_ALWAYS_SOFTWARE", "FLUTTER_INAPPWEBVIEW_SKIP_DMABUF_CHECK",
            "WPE_BACKEND_LIBRARY", "WEBKIT_EXEC_PATH", "WEBKIT_INJECTED_BUNDLE_PATH")}
        report["displayAndDpi"] = observe(["xdpyinfo"])
        report["wmRootProperty"] = observe(["xprop", "-root", "_NET_SUPPORTING_WM_CHECK"])
        report["dbus"] = observe([
            "dbus-send", "--session", "--print-reply", "--dest=org.freedesktop.DBus",
            "/org/freedesktop/DBus", "org.freedesktop.DBus.ListNames"])
        report["xrandr"] = observe(["xrandr", "--current"])
        report["displayGlx"] = observe(["glxinfo", "-B"])
        report["sdkVersions"] = {module: observe(["pkg-config", "--modversion", module])
                                 for module in ("wpe-webkit-2.0", "wpe-platform-2.0",
                                                "wpe-platform-headless-2.0", "wpe-1.0")}
        write_report(directory, report)
        for field in ("displayAndDpi", "wmRootProperty", "dbus"):
            require_observation(report[field])
        for version in report["sdkVersions"].values():
            require_observation(version)
        reports = Path(os.environ["INSTALLED_PROBE_REPORTS"])
        require_fresh_reports(reports)
        command = ["flutter", "drive", "--profile", "-d", "linux", "--no-dds", "--no-pub",
                   f"--use-application-binary={binary}",
                   "--driver=test_driver/installed_plugin_resource_probe.dart",
                   "--target=integration_test/installed_plugin_resource_probe_test.dart"]
        report.update(status="running", command=command)
        write_report(directory, report)
        code = subprocess.call(command)
        report["driveExitCode"] = code
        if code == 0:
            report["scenarioResult"] = require_linux_result(reports)
        if wm.poll() is not None:
            raise RuntimeError("Openbox exited before the scenario completed")
        return code
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, Interrupted) as error:
        report["error"] = str(error)
        return 128 + error.signum if isinstance(error, Interrupted) else 1
    finally:
        write_report(directory, report)
        if wm is not None and wm.poll() is None:
            wm.terminate()
            try:
                wm.wait(timeout=5)
            except subprocess.TimeoutExpired:
                wm.kill()
                wm.wait(timeout=5)


def run(directory, binary, seconds):
    directory.mkdir(parents=True, exist_ok=False)
    runtime = directory / "xdg-runtime"
    runtime.mkdir(mode=0o700)
    report = {
        "schemaVersion": 1, "status": "preparing", "physicalDevice": False,
        "scope": "Linux profile scenario in an isolated hosted Xvfb session",
        "requestedXvfb": {"screen": "1440x1000x24", "dpi": 96},
        "nativeRenderMode": {"availability": "unavailable", "reason":
            "The current Linux controller exposes no native render-mode observation API."},
        "nativeRuntimeVersion": {"availability": "unavailable", "reason":
            "pkg-config describes the SDK; navigator.userAgent is in the scenario report."},
        "appGpuAndSoftwareRoute": {"availability": "unavailable", "reason":
            "Display GLX and inherited environment do not establish the app/WPE rendering route."},
        "metricLimits": "Host RssAnon and observed partial engine memory remain separate; "
                        "no per-tab renderer attribution, CPU/GPU usage or savings claim.",
    }
    write_report(directory, report)
    code = 1
    try:
        report["bundleLinkerInspection"] = inspect_bundle(binary)
        write_report(directory, report)
        environment = dict(os.environ, XDG_RUNTIME_DIR=str(runtime),
                           XDG_SESSION_TYPE="x11", GDK_BACKEND="x11")
        command = ["xvfb-run", "--auto-servernum", f"--error-file={directory / 'xvfb.log'}",
                   "--server-args=-screen 0 1440x1000x24 -dpi 96 -nolisten tcp",
                   "dbus-run-session", "--", sys.executable, str(Path(__file__).resolve()),
                   "--inside-session", "--output", str(directory), "--binary", str(binary)]
        code = run_owned(command, seconds, environment)
    except (OSError, RuntimeError, Interrupted) as error:
        report["error"] = str(error)
        code = 128 + error.signum if isinstance(error, Interrupted) else 1
    finally:
        latest = json.loads((directory / "session.json").read_text(encoding="utf-8"))
        if "error" in report:
            latest["error"] = report["error"]
        latest.update(status="passed" if code == 0 else "failed", sessionExitCode=code,
                      deadlineSeconds=seconds, timedOut=code == 124)
        write_report(directory, latest)
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--binary", type=Path, default=Path("build/linux/x64/profile/bundle/otzaria"))
    parser.add_argument("--seconds", type=int, default=1320)
    parser.add_argument("--inside-session", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not args.output.is_absolute() or args.output.is_symlink():
        parser.error("--output must be a fresh absolute directory without a symlink")
    if not 1 <= args.seconds <= 2700:
        parser.error("--seconds must be between 1 and 2700")
    signal.signal(signal.SIGTERM, interrupt)
    signal.signal(signal.SIGINT, interrupt)
    if args.inside_session:
        return session(args.output, args.binary.resolve())
    return run(args.output, args.binary.resolve(), args.seconds)


if __name__ == "__main__":
    sys.exit(main())
