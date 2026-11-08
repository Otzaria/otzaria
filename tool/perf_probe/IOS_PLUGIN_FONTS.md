# iOS plugin-font compatibility experiment (#4122)

**Decision: keep the experiment OFF by default.** This fixture tests the iOS
file-origin boundary separately from the [macOS experiment](MACOS_PLUGIN_FONTS.md).
It does not enable a production iOS font path, change ATS, change the origin of
installed plugins, alter dependency pins, or claim a CPU/RAM reduction.

The [native Simulator workflow for #4427](https://github.com/Otzaria/otzaria/actions/runs/42332655349)
passed 54 cases across 1/5/10 views on source `ca0adb7a9`. This is historical
functional evidence; inspect the exact source and retained validator results,
and rerun the workflow when relevant sources or dependencies change.

| Coverage | Status at this checkpoint | What a future passing run establishes |
| --- | --- | --- |
| iOS Simulator debug, 1/5/10 visible WebViews | Historical PASS; see workflow above | Functional font, CSP, boot and ownership behavior on the recorded runtime |
| Physical iOS, profile | NOT_RUN | No device or performance conclusion yet |
| Physical iOS, release | NOT_RUN | No release-build conclusion yet |
| WKWebView process CPU / RAM | Unsupported by this collector | Host RSS cannot substitute for engine measurements |
| Cache sharing across views | Not measured | No shared-cache assumption |

The base macOS head `293d8e1bc2d6c287bb76f2702e0fe7a055dd3edb` passed
[run 42293498985](https://github.com/Otzaria/otzaria/actions/runs/42293498985):
data/scheme, all three CSP cases and 1/5/10 views on macOS 26.7.2. That is
functional evidence for the base Mac implementation. The extracted shared
widget also passed the [Mac workflow on #4427](https://github.com/Otzaria/otzaria/actions/runs/42332655407).
Mac results do not establish iOS compatibility or representative resource savings.

## The three routes

Each route runs both requested transports (`data` and `scheme`) under normal
CSP, `font-src data:`, and `style-src 'none'`: **18 cases per process**, with
independent workflow jobs for 1, 5 and 10 simultaneous views. Routes and their
policy diagnostics stay separate in the result.

| Route | Main document | Content blockers | Scheme registration |
| --- | --- | --- | --- |
| `file-production-policy` | The production `file://` route | Unchanged production builder with no network grants | Added by the experiment only when scheme fonts are requested |
| `file-lab-policy` | The same `file://` route | Production rules plus one exact plugin-origin exception | Added by the experiment only when scheme fonts are requested |
| `scheme-page-lab-policy` | A deliberate lab `otzaria-plugin://ios.font.probe/` document | Production rules plus the same exact exception | Added for the lab document, in both transport controls |

The lab exception is exactly `^otzaria-plugin://ios\.font\.probe/`, case
sensitive, with the `ignore-previous-rules` action. The validator checks the
entire production rule list independently; changing all baseline reports together
does not hide a widened policy. A passing lab route never establishes that the
production file route can fetch scheme fonts.

All routes use the production settings, blocker, CSP, font-bootstrap, SDK script
and resource-handler builders. `allowFileAccessFromFileURLs` and
`allowUniversalAccessFromFileURLs` remain false, `allowingReadAccessTo` remains
null, and responses add no `Access-Control-Allow-Origin`. The fixture uses
incognito views as an explicit storage control. The builders' file-server port
is 1 and the fixture starts no HTTP server. It is a visible `InAppWebView`
fixture, not the complete plugin catalog, registry and tab application flow.

The file control retains the actual production loading policy. Registering a
[`WKURLSchemeHandler`](https://developer.apple.com/documentation/webkit/wkurlschemehandler)
does not itself prove that a `file://` document may use those resources as web
fonts. Web font fetching has
[CORS requirements](https://www.w3.org/TR/css-fonts-3/#font-fetching-requirements),
and WebKit's
[file read-access API](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl(_:allowingreadaccessto:))
is a separate boundary. None of those permissions is widened to make this
experiment pass.

The report retains the observed `location.href`, `location.origin`, secure-context
flag, CSP violations, dropped-violation count, native request `Origin`, response
CSP/ACAO headers, and warning/error console messages. These are observations,
not an automatic attribution to CORS, blockers or file-origin restrictions.
A `font-load-failed` result alone does not identify the rejecting layer.

## Readiness, typography and ownership

The two transport controls share the bounded experimental verifier. Consequently,
the data control is not a benchmark of the legacy production boot. A scheme
rejection must fall back to verified embedded data fonts; a timeout, unowned face,
missing callback or incomplete operation is a failed experiment, not a negative
compatibility finding. A fully completed report classifies each route as
`scheme-loaded`, `verified-data-fallback`, `mixed-scheme-and-data`, `data-control`
or `style-blocked`. Mixed per-view behavior remains visible and is not marked
production compatible.

The fixture awaits the real SDK boot acknowledgement, checks its theme and one
boot event, then awaits `document.fonts.load()` before canvas/text measurements.
It measures bundled FrankRuhlCLM 400/700 and variable Rubik 300/700, verifies actual
loaded faces, a separate bold face, the variable weight range, nonempty canvas
ink, distinct weight hashes, and equal data/scheme widths and pixels. It awaits
both animation frames and captures native PNG screenshots. The style-denial
control explicitly reports fonts unavailable while still requiring one SDK boot.
This iOS fixture does not enumerate installed system fonts or simulate changing
user settings; the existing Mac coverage and font-service tests remain in place.

With 5 or 10 views, each normal-policy case closes the first view, waits for its
disposal, and verifies that only its lease became inactive. The survivor loads a
new FontFace after the close. Scheme delivery uses a newly registered URL and
requires positive loader/request/response/byte deltas. Data delivery uses a new
embedded face bound to the survivor's document and owner. Loading a previously
cached face is insufficient evidence for the fresh scheme check.

Every case then navigates the final surviving view to its exact replacement
fixture document. That URL is allowed only after the initial observation has
completed. Other URLs, subframes and late disposed requests are cancelled.
The old lease must become inactive; its guarded SDK source must return
`stale-document`, with no boot event or side effect in the new document.

## Deadlines and failure evidence

The shared widget preserves the base Mac six-second preparation and five-second
boot bounds, ten-second operation bound, sixty-second view-batch bound and
fullyLive frame policy. Case disposal has a separate ten-second deadline. Before
failed views are removed, the existing diagnostic snapshots run concurrently,
with two seconds per view and a 16 KiB JSON limit. They retain font/canvas/frame
progress and widget bounds while checking the original document owner.
Snapshot or cleanup errors do not replace the first framework failure or stack.
Late callbacks remain failed; they cannot turn into passing samples.

The test has a nineteen-minute overall bound and the driver waits at most twenty
minutes for the framework response. The host runner bounds Simulator boot,
metadata commands and the complete build/drive command; the latter has a
fifty-minute limit. It records command arguments, deadlines, exit status,
timeouts and logs before proceeding. The workflow has a seventy-five-minute
job limit and uploads partial artifacts with `if: always()`.

`framework-response.json` preserves Flutter's unmodified response, including its
actual verdict and failures. `report.partial.json` is saved before image
extraction. `report.json` then references individual PNG files. Malformed image
data, unsafe names or duplicate screenshot names fail extraction while retaining
the raw response. A driver or close failure returns a nonzero process status.
The validator compares the normalized data with the raw framework response and
checks PNG chunk structure, checksums and byte equality with the native payload.
A successful report cannot override failed framework or runner status.

## Reproduce the Simulator run

Use a clean checkout on macOS with Xcode and an available iPhone Simulator,
Flutter **3.47.7** (framework `abaf9c523780a608bd46686fd5e53740a07077f8`, Dart
3.13.5) and Rust. Do not use profile or release mode on a Simulator.

```sh
rustup target add aarch64-apple-ios-sim x86_64-apple-ios
flutter pub get --enforce-lockfile
python3 tool/perf_probe/run_ios_plugin_fonts.py --instances 1 --output /tmp/ios-fonts-1
python3 tool/perf_probe/run_ios_plugin_fonts.py --instances 5 --output /tmp/ios-fonts-5
python3 tool/perf_probe/run_ios_plugin_fonts.py --instances 10 --output /tmp/ios-fonts-10
```

Each output directory must be new. Existing reports are rejected before any
artifact is written; only the workflow setup logs may already be present. The runner selects an available iPhone,
records its runtime version/build/UDID, boots it if necessary and opens Simulator.
The Simulator app is built separately with the same 3,000-second build budget.
`flutter drive --debug --no-pub --use-application-binary` launches that exact app.
An authenticated, generation-specific checkpoint after its first rasterized fixture
frame must arrive within 180 seconds after launch; the existing 20-minute report
budget is separate from compilation. PID, generation and native fork are bound
to the final report, so another launch cannot certify the measured process.
Legacy artifacts without this checkpoint do not satisfy native acceptance.
No checkpoint is required by the separate manual physical-device export path.

Only a failed driver on a Simulator booted by this runner triggers a two-minute
Runner/WebKit/SpringBoard log query before shutdown. It has a ten-second deadline
and retains at most 64 KiB per stream with explicit truncation metadata. A query
failure is secondary and cannot replace the driver failure. Successful runs and
borrowed Simulators are not queried. This is failure evidence, not a fix for the
unresolved iOS initial-load timeout after controller creation. It shuts down only a Simulator that
it booted. The workflow installs both Rust Simulator targets; the validator
requires the target that matches the runner architecture.

`environment.json` records the app commit/tree and clean status before/after,
lock SHA-256, official Flutter framework/engine/Dart identities and SDK clean
status, all eight WebView package Git heads and the search-engine head, with clean
status before/after, Xcode and SDK
versions/builds, macOS/architecture, Rust compiler/toolchain/installed targets,
Simulator identity, command verdict and the generated CocoaPods lock hash.
A cancellation kills and drains the runner’s own command process group, preserves
its partial logs and leaves unrelated processes alone.
`Podfile.lock`, command logs, `comparison.json`, raw framework responses,
partial reports and PNGs are retained together. The current source locks WebView `c709de98711cf34350c48df4c75e24d0879d5876` and search engine
`2da23091237ed0f0a612de3b2d18cfc99d8b7d2a`. The committed `pubspec.lock` is
retained with `git show <source-commit>:pubspec.lock` and its Git blob ID.
It must equal the working lock; its hash and native Git pins must match the compiled report and
the actual dependency checkouts. A separate dependency upgrade requires fresh
evidence tied to that new source and lock, rather than reusing this run.

A recorded run can be rechecked with:

```sh
python3 tool/perf_probe/validate_ios_plugin_fonts.py /tmp/ios-fonts-1/reports \
  --environment /tmp/ios-fonts-1/environment.json \
  --output /tmp/ios-fonts-1/rechecked.json
```

The current artifact validator accepts the recorded debug Simulator path only.
A missing Simulator, failed build, framework failure, timeout, incomplete matrix,
changed source, missing provenance or malformed artifact produces
`invalid-or-not-run` and a nonzero exit. It does not manufacture a compatibility
verdict from unavailable evidence.

## Physical-device work still required

Physical profile and release remain **NOT_RUN**. They need an explicitly selected
signed device build, its OS/model/toolchain provenance, repeated measurements and
a physical-device artifact-validation path before any acceptance claim.
`flutter drive --profile` is a possible physical profile execution route.
Flutter Driver cannot drive release mode through a VM service.

The fixture provides opt-in `OTZARIA_IOS_FONT_PROBE_EXPORT=true` for a future
signed physical run: after the actual integration binding finishes, it writes
its raw framework response and PNGs under the application's Documents directory
`ios-font-compatibility/run-*`. An `export-complete.txt` marker is written only
after all files succeed; failures retain `export-error.txt`. Xcode's Download
Container action can retrieve that directory. This export code is not evidence
that a signed release run occurred, and these physical reports are not accepted
by the current Simulator validator.

The report's logical UTF-8 boot/argument sizes, served font bytes and font-ready
latencies are observations for the recorded fixture. Host RSS is labeled as such;
WebContent CPU/RAM remain unsupported and cache sharing remains unmeasured.
The fixed case order and a single application process per view count do not
supply representative timing distributions. Even complete Simulator success
keeps production disabled until compatibility and resource acceptance have been
established on the intended production platforms and routes.
