# Real installed plugins on Android

`run_installed_plugin_android.py` executes
`integration_test/installed_plugin_resource_probe_test.dart` in a dedicated
Android **emulator debug** APK. The test calls the real Otzaria `main`, installs
the verified Store sources at `4517d39c4ecab632aff98e1c0e414881695961aa`, and uses
the real `PluginTabPage`, `PluginBackgroundHost` and runtime dispatcher.
Controlled installed plugins supply the restore-state and protected-state
negative controls. No replacement app or `Offstage` transition represents an
Android OS background event.

The common scenario still requires visible and hidden idle windows, multiple
instances, memory-pressure/count/age discard, actual controller removal, a new
document and real SDK boot on restoration, the Store's restored visible state,
and the four protected first-blocker controls under one discard request. It
also opens, observes and disposes the actual background plugin host and checks
that dispatcher policy overrides are restored.

Home/resume operates on the installed controlled foreground plugin. The pinned
Store's discard/restoration and the background-host open/idle/close checks run
as distinct later phases in the same real app process.

## Run

Use the reviewed Flutter 3.47.7 SDK, Java 17, Android SDK/NDK, `aapt2`, Rust with
the `x86_64-linux-android` target, and a fresh x86_64 Android emulator. The CI
workflow uses API 34. Commit tracked changes before running:

```sh
python3 tool/perf_probe/run_installed_plugin_android.py \
  --device emulator-5554 --quiet-ms 1500 \
  --output build/installed-plugin-android
```

The exact serial is mandatory. The runner checks the emulator property and
primary Android user, and refuses an existing
`org.otzaria.otzaria.installedprobe` installation. It verifies the APK's dedicated
application ID, real `org.otzaria.otzaria.MainActivity` launcher and debuggable
flag before installing it. The Dart test checks the package again before
writing probe data. The Gradle application ID suffix applies only to debug
builds with `otzariaInstalledProbe=true`.

The runner performs strict lockfile resolution, verifies all eight resolved
WebView packages at `124bb8e63f345ffd0b0f2ea7190c24b19e69897d`, and records the
source commit, lockfile digest, Flutter/engine identity, verified APK digest,
device fingerprint, API, ABI, display, density and WebView provider. The Store
payload is hash-checked before compilation and again when materialized by the
test. `CARGO_NET_GIT_FETCH_WITH_CLI=true` selects Cargo's documented Git CLI
transport without altering TLS verification or dependency pins.

## Private cache allocation

Android probe roots come from `getTemporaryDirectory()` in the pinned
`path_provider_android` package, which returns `Context.getCacheDir()`.
The Dart VM's `Directory.systemTemp` can instead point to `code_cache`.
The allocator resolves the platform cache to its canonical path and creates a
new `otzaria-installed-probe-` directory for each run. Missing platform paths
or filesystem failures remain failures; there is no fallback to a different
directory.

The existing controller still accepts only
`cache/otzaria-installed-probe-<fresh>/output/installed-plugin-report.json`
relative to the dedicated app's private data directory. Canonical report
resolution rejects a sibling cache, another app root, traversal to
`code_cache`, or an output link that escapes this boundary. The integration
scenario retains its symlink rejection and fresh-empty-output check, and waits
for the authenticated host stream before preparing the app. Other platforms
keep the existing system-temp allocation path.

The Dart controls use the actual allocator and real temporary directories with
a mocked platform path provider. They reproduce the VM/app-cache mismatch,
check fresh roots and retained old evidence, and exercise missing cache paths,
canonical aliases and rejected escapes. These controls do not replace the
native Android lifecycle job.

## Native transition and quiet-window boundaries

The controller starts **after the APK build**. A long build cannot leave an old
controller readiness event armed. Each APK contains a fresh campaign ID and
random control capability. After the single initial launch, the host reads a
private bootstrap file while the test waits before `app.main`. It checks the
launch PID, run ID, package, fresh private output path and actual device port,
then establishes one explicit-serial ADB forward and an authenticated loopback
push stream. The live stream handshake must match that bootstrap. Every
command and acknowledgement also carries the campaign, PID, run, package,
monotonic sequence number and action. A stale file or readiness indication
cannot acknowledge a later command.

| Boundary | Required observation |
| --- | --- |
| Before Home | The original native activity is resumed. Its ActivityRecord token, task, user, PID and `/proc/PID/stat` process start ticks match the launch. The real plugin's instance, controller, native view, document and visible state are captured. |
| After Home | `KEYCODE_HOME` has made the resolved Android HOME activity the resumed activity. The original app activity and process remain. Flutter reports `paused`, and the real dispatcher reports `hidden` after its Android native pause call completes, with the selected plugin eligible as a discard candidate. |
| Background quiet | A single pushed request starts a bounded host wait. The host executes **zero commands** until that wait ends. The app performs no JS/bridge reads, native window queries or process sampling during its quiet window. |
| After quiet, before resume | A fresh native observation still finds the same app process/activity behind the resolved HOME activity. This query occurs after the quiet interval. |
| After resume | `am start` with single-top/reorder-to-front flags resumes the **same** ActivityRecord and task. PID and process start time remain equal. Flutter and the dispatcher acknowledge resumed/active, and the controller, document and visible state are preserved. |

PID reuse, activity recreation, a different task, ambiguous resumed activities,
or an unexpected HOME component fail the phase. The runner never force-stops
or relaunches the app as a substitute for resume. Its only force-stop is cleanup
of the dedicated installation after the overall scenario has completed or
failed; that action is labeled separately in the command record.

There is no host polling while waiting for pushed commands. This also leaves
the common visible, hidden, background-host and closed-idle windows free from
host ADB queries. The app-side OS quiet interval includes the two control
message boundaries; the narrower host wait records its own monotonic times.
The final validator checks the actual command intervals against that host wait.
Control transport is disclosed observer work. Production timers, normal
platform lifecycle work and passive Flutter frame callbacks stay enabled;
zero probe queries is not a claim of zero application work or energy use.

## Final verdict and failures

`host-report.json` and `installed-plugin-report.json` belong to the same
campaign and process. The app sends completion only after
`IntegrationTestWidgetsFlutterBinding.allTestsPassed` supplies its final
framework verdict and the final report has been flushed. Completion includes
the exact report byte count and SHA-256. The host reads that private file once,
checks the digest, framework verdict, full original scenario contract and the
native evidence returned during the transition, then acknowledges completion.
An early framework failure is retained and rejected, including one that occurs
before the Home phase. An app report alone is not a successful host run.

Setup and each lifecycle action have deadlines, every subprocess has a bounded
timeout, and timed-out subprocess groups are terminated. The app test has an
18-minute deadline and the host scenario a 20-minute deadline. Failure artifacts
include the partial host report, raw command stdout/stderr and timestamps,
available private app report, and bounded logcat for the exact launch PID.
The failure verdict is checkpointed before cleanup. Logcat and partial-report
retrieval each have a separate five-second command budget. Owned-forward
removal and owned-package stop each receive a fresh ten-second command budget,
even if an earlier diagnostic or cleanup stage fails. A timed-out command also
has bounded TERM/KILL draining, at most five seconds per signal stage. Cleanup
verifies the serial and endpoint before removing a forward and stops only the
dedicated installation created by this run, with a process-exit acknowledgement.

Cleanup commands read stdout and stderr concurrently from the live child pipes,
with an eight-MiB limit per stream and the existing action deadline. Opening,
writing or reading a raw diagnostic file is not a prerequisite for executing
cleanup or checking the forward's owner. Raw receipts are written exclusively
after capture; failed writes preserve existing files and retain the exact
captured bytes as base64 in the command record. Incomplete or oversized output
fails the command, so a partial forward list cannot authorize removal. The next
owned resource still receives its own cleanup attempt. Setup commands retain
their exclusive raw-file preflight before they can allocate new resources.

Successful installation and forward allocation are recorded in memory before
the command journal is written. A receipt-write failure cannot erase that
ownership or prevent later owned-cleanup attempts. The first command/scenario
failure stays primary; later write and required-cleanup errors are retained in
order. A receipt-write failure on its own still fails the host verdict.
If the command journal is unavailable, the in-memory command receipts are also
included in the host report.
Report checkpoints use atomic replacement. Failed replacements retain their
numbered pending receipts and leave the last successful report intact; a
bounded stderr record supplies the primary and write errors when report output
is unavailable. Pending receipts are diagnostic output, not final success.

The private data remains available for diagnosis until the emulator is
discarded. There is no `adb kill-server`, shared emulator shutdown or production
app data clearing in the runner.

## Evidence scope

| Result | Scope |
| --- | --- |
| Python controlled-process and Dart loopback tests | Host protocol, bounded failure handling, stale identity, lifecycle replacement, quiet guards and final report validation. These are not device executions. |
| `Installed plugin Android lifecycle` native job | Actual app and installed plugins on an Android API 34 x86_64 emulator, debug build. Success requires real OS transition and all original scenario phases. |
| Physical Android profile/release and performance acceptance | **NOT_RUN** by this runner. No memory, CPU, energy, frame-rate or user-interaction performance threshold is accepted from emulator debug output. |
| Windows, macOS, Linux and iOS | Remain **NOT_RUN** in this Android report. Desktop minimize/hide are also **NOT_RUN** here. |

The host tests include a controlled subprocess that ignores SIGTERM to verify
bounded descendant termination, and an executable Android response fixture
that changes the ActivityRecord while retaining its PID. That negative must
fail before successful completion. The prior Android report with OS background
marked `notRun` is explicitly rejected by the new gate. Existing discard,
restoration, protected-state and quiet-window negatives remain required.
Additional real-child/filesystem controls exercise simultaneous command,
journal, report and cleanup failures, independent cleanup deadlines, ownership
after successful install/forward commands, and retention of existing receipts.
They also cover an unusable raw directory, collisions in both stream receipts,
a stale receipt claiming ownership of a borrowed forward, concurrent binary
output, the output-size limit, a real file-size write failure, and a descendant
that keeps a pipe open after its parent exits.

Primary references: [ADB commands and activity flags](https://developer.android.com/tools/adb),
[Android 14 ActivityRecord source](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android14-release/services/core/java/com/android/server/wm/ActivityRecord.java),
[Android 14 component-only HOME resolution](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android14-release/services/core/java/com/android/server/pm/PackageManagerShellCommand.java),
[Cargo Git transport configuration](https://doc.rust-lang.org/cargo/reference/config.html#netgit-fetch-with-cli),
[locked Android path provider](https://github.com/flutter/packages/blob/path_provider_android-v2.2.23/packages/path_provider/path_provider_android/android/src/main/java/io/flutter/plugins/pathprovider/PathProviderPlugin.java),
and [the exact Flutter VM temp-directory setup](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/android/io/flutter/util/PathUtils.java).
