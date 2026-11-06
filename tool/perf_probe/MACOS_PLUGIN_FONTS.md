# macOS plugin-font experiment (#4122)

**Decision: keep the experiment OFF by default.** No macOS performance result is
implied by this source change. iOS remains disabled and unvalidated; ATS and
plugin origins are unchanged.

A macOS build may opt in with
`--dart-define=OTZARIA_EXPERIMENTAL_MACOS_PLUGIN_FONTS=true`. Only foreground
plugin tabs already served from their exact `otzaria-plugin://<plugin-host>`
origin use this path. Localhost development pages and background plugins keep
their existing behavior. There is no product settings/debug UI for this flag.

## Transport and ownership

Each live document owns an independent lease. Its short CSS references opaque
virtual URLs below `/__otzaria_fonts__/`. Only font loaders registered by the
host can answer these URLs. Registration reads metadata, not font bytes; the
font bytes are read when WKWebView requests the corresponding face. System
paths and original filenames are never placed in these URLs. Responses use
`no-store`; the probe assumes no font-cache sharing across WebViews.

Reserved font paths, including encoded aliases and traversal, are intercepted
before normal plugin-file lookup. Missing, expired, wrong-origin or unregistered
URLs fail closed. A late read checks the lease again before returning bytes.
Navigation, controller replacement and host disposal release only that host's
lease. Closing another instance of the same plugin does not remove this one's
registrations.

The experimental font preparation has a six-second overall deadline. Each
scheme/data loading attempt has a 1.5-second font wait within that deadline.
It verifies an applied stylesheet and actual loaded FontFace objects owned by
that stylesheet. `document.fonts.load()` returning an empty array is failure.
A rejected scheme load retries embedded `data:` CSS and verifies that attempt,
too. If inline styles are blocked, both attempts report `style-blocked`; the
identified current document can still boot with fonts explicitly unavailable.
Unavailable or expired results are diagnostics, not extra product flows.

A marker installed at document start and an independent boot-attempt claim fence
queued preparation and boot JavaScript. Even if stylesheet binding times out or
throws after the identity was captured, the boot checks that document and owner.
A missing document identity never schedules boot. Old-document requests cannot
bind a new document or remove its stylesheet. A later attempt in the same
document invalidates completion from its predecessor.

Boot has its own five-second deadline and returns an acknowledgement containing
the matching document, owner and SDK event options. A skipped/null result cannot
mark the plugin ready. The Dart generation is checked before and after evaluation;
the JavaScript checks identity and deadline when the queued source actually runs.
Font families are captured from the same theme as the boot payload.
Separate bold files, variable weight ranges, selected system families, and the
embedded `fonts.resolveFamilies` SDK contract are preserved. The default Apple
path and the non-Apple font path retain their existing behavior.

## Actual WKWebView run

The `macos_plugin_font_probe.yml` workflow runs on pull requests targeting
`main`, `dev` and the campaign's stacked branches, or by manual dispatch. It
builds and launches the application with Flutter's existing integration driver
on a macOS runner. For each count (1, 5, 10), it starts separate profile-mode
application processes for a paired `data` and `scheme` run. Counts run on
separate runners; compare each pair within its own runner. The order is reversed
for the five-view pair to expose, rather than silently assume away, order effects.

Both modes use the experimental bounded pre-boot verifier. **The data control is
not the unchanged legacy Apple bootstrap timing.** This isolates transport and
readiness behavior without claiming an end-user speedup against production.

Both modes use Flutter's `fullyLive` frame policy so asynchronous native resize
and snapshot callbacks receive ordinary framework-requested frames. The
[default `fadePointers` policy](https://api.flutter.dev/flutter/flutter_test/LiveTestWidgetsFlutterBindingFramePolicy.html)
suppresses those ordinary framework-requested frames. This is a visible rendering
probe, not an idle-CPU measurement. Every report records the selected policy.
The visible scene is mounted once and updated through a `ValueNotifier`.
The sixty-second deadline applies to native result futures, without wrapping
`WidgetTester.pump` in a timeout: a timeout does not cancel the guarded pump.
Closing a view waits for its widget-disposal notification. Cleanup has a separate
ten-second bound; a cleanup failure is retained alongside the original case error.

The probe uses the production tab settings builder, content-blocker builder,
CSP builder, font owner, font bootstrap and SDK scripts in visible Flutter-hosted
`InAppWebView` instances, not headless ones. It does not instantiate the full
`PluginTabPage`/registry/BLoC application flow. It verifies the native window is visible, not minimized, opaque and sized,
and checks each document's visibility. All views fit within the requested
1000x700 logical window. It uses a readable installed Hebrew system font chosen
by the app's real system-font scanner, a bundled regular/bold pair and a bundled
variable font. System-font discovery time is reported separately.

The tab settings enable the native navigation-decision callback. The fixture
answers it explicitly: only the exact current scenario's main document receives
`ALLOW`; other navigation is cancelled and fails the case. Each decision is
recorded. An omitted callback returns `null` through the pinned macOS Dart
controller, which the native decoder maps to `CANCEL` before document loading.
The unit regression exercises the fixture's actual widget parameters and the
macOS package's Dart method channel; it does not instantiate WKWebView on Linux.

Three cases run in each fresh process, in this order:

1. Normal exact-origin font permission.
2. `font-src data:`: the scheme variant must fall back to verified embedded fonts.
3. `style-src 'none'`: the outcome must be unavailable with a concrete reason,
   while the SDK still boots exactly once within the bound.

The report captures text widths, loaded FontFace states, canvas ink/hash samples,
WKWebView screenshots, regular/bold and variable-weight rendering, the boot theme,
and font-ready time from view creation. It compares the data/scheme widths and
canvas pixels in both loadable cases. With multiple instances it closes the
first, verifies only that instance's lease was released, and checks a surviving
same-plugin instance. For a successful scheme survivor, it then registers a new
opaque allowlisted URL and loads a new FontFace. The URL did not exist before
peer disposal: positive loader, request, response and returned-byte deltas are
required, so a previously cached FontFace cannot satisfy this check. These
post-close counters are recorded separately in `freshSchemeAfterClosingFirst`.
The data control and a normal-scheme fallback explicitly report this fresh-scheme
check as `not-run`, with a reason; neither claims scheme lifecycle evidence.
If the normal scheme attempt falls back, the report records that outcome and
`normalSchemeVerified` is false; fallback success does not establish scheme
support.

Run one pair locally on a Mac from the repository root:

```bash
export PLUGIN_FONT_PROBE_REPORTS="$PWD/build/macos-font-pair"
for mode in data scheme; do
  flutter drive --profile -d macos \
    --driver=test_driver/macos_plugin_fonts.dart \
    --target=integration_test/macos_plugin_font_probe_test.dart \
    --dart-define=OTZARIA_EXPERIMENTAL_MACOS_PLUGIN_FONTS=true \
    --dart-define=OTZARIA_FONT_PROBE_TRANSPORT="$mode" \
    --dart-define=OTZARIA_FONT_PROBE_INSTANCES=5
done
python3 tool/perf_probe/compare_macos_plugin_fonts.py \
  "$PLUGIN_FONT_PROBE_REPORTS" --output "$PLUGIN_FONT_PROBE_REPORTS/comparison.json"
```

Use an empty output directory for each pair. `report.json`, screenshots, paired
`comparison.json` and complete build/run logs are retained as CI artifacts for
14 days. Failures retain partial reports and logs; they do not manufacture a
successful measurement. The Python validator has negative controls for missing
faces, rendering differences, false CSP success, a reused app process, unsupported
CPU reported as zero, a missing boot acknowledgement, and a claimed scheme success
without returned font bytes. A cached survivor or zero fresh-request deltas also
fails validation.

Each case and view is recorded before mounting or waiting. Bounded lifecycle
events retain controller creation, navigation, custom-scheme requests/responses,
font preparation, guarded boot, rendering and screenshot progress. A native
operation has a ten-second bound, in addition to the unchanged preparation and
boot deadlines; the view batch retains its sixty-second overall deadline. The
first failed view ends the batch and fences its peers. A late response after
timeout or disposal stays incomplete and cannot become a passing sample.
Run, case, view, operation and cleanup completion are all required by the
validator, together with explicit allowance of the expected document and
observed widget disposal.
Window visibility alone does not establish canvas or typography success.

### Rendering failure diagnostics

[Native run 42277391417](https://github.com/Otzaria/otzaria/actions/runs/42277391417)
passed both transports and all three CSP cases with one and five views. With ten
views, both transports failed the normal case's ten-second rendering operation
after every view had completed font preparation and boot. Later CSP cases were
not run. The one/five-view runners used macOS 26.7.2, while the ten-view runner
used 26.6.2, so these runs do not isolate view count as the cause. The cause is
unresolved; a late native reply near disposal does not prove completed rendering.
The `Resize timed out` warning also appears in all four passing run logs.

The unchanged rendering operation now keeps at most forty in-document timing
events around each font load, canvas sample, and both animation-frame callbacks.
It still waits for both frames and checks all six samples. There are no progress
messages across the native channel or additional timers during the measurement.
Successful results include the trace. Its timings start after font preparation
and boot; the instrumentation does not extend the font-ready measurement.
The Dart rendering dispatch and JavaScript entry also record wall-clock timestamps
to help distinguish native queuing from time within the script. Stage durations
use the document's monotonic performance clock.

After a case fails, all view snapshots are requested concurrently before widget
disposal, with a separate two-second bound per request. Each snapshot records the
current stage, visibility, viewport and font states; Flutter widget bounds are
also recorded when the request starts. The JavaScript checks the original
document marker and boot owner before reading the trace. Snapshot JSON is capped
at 16 KiB. A missing callback, stale document, native error or diagnostic timeout
is retained explicitly. Snapshot errors never replace the original case error,
and a late successful snapshot cannot repair a failed rendering operation.
Snapshot timestamps describe capture after failure, not the exact timeout instant.
The original ten-second operation, sixty-second batch and cleanup deadlines are
unchanged. Linux contract tests exercise these diagnostic boundaries; the next
macOS run is still required to locate the native stall.

## Measurement boundaries and enablement

The exact UTF-8 boot source is counted separately from the font-install function
bodies and JSON arguments actually submitted to the controller. CSS bytes are a
subset of argument bytes and must not be added twice. Scheme counters sum the
font byte arrays returned to custom-scheme callbacks, with a separate snapshot
at boot and another after rendering checks. These are logical payload sizes,
not a measurement of native IPC envelopes, string copies, CPU or engine memory.

The report includes the Flutter host's RSS, platform, user agent, window geometry
and processor count. WKWebView child-process memory and CPU are explicitly
unsupported. The physical display, GPU path, complete WebKit process topology
and persistent OS caches are unmeasured. A new app PID does not establish a cold
OS font or WebKit cache. Linux unit/Node tests validate contracts and negative
cases; they do not validate WKWebView, Apple builds or actual CSP enforcement.

The decision remains default-OFF even after a green CI run. Enabling production
needs successful normal scheme delivery, no typography/SDK/lifecycle regression,
repeated representative Mac measurements, and complete enough resource evidence
to assess the extra scheme requests. A smaller bootstrap or argument payload
alone is insufficient evidence of lower CPU or RAM. Evaluate iOS separately.
