# Personal-book scan / UI GC probe (#4532, follow-up to #4542)

The regression tests in
`test/utils/file/convert_document_file_async_io_test.dart` use a gated
`IOOverrides` file. They **fail deterministically** if the converter uses a
synchronous file read, even on a fast CI disk. They also cover asynchronous
read errors, file-handle cleanup (particularly Windows), and multi-MiB input.

The separate benchmark below is **opt-in** because the original 93-second
freeze involved slow Windows I/O, paging, 4 GB RAM and about 16,700 personal
books. Ordinary CI storage does not reproduce it.

## Reproduce on the affected Windows machine

From the repository root, with Flutter dependencies installed:

```powershell
flutter pub get
flutter test --reporter expanded `
  "--dart-define=OTZARIA_GC_PROBE_FOLDER=D:\\MyBooks" `
  --dart-define=OTZARIA_GC_PROBE_RUNS=2 `
  --dart-define=OTZARIA_GC_PROBE_MAX_FILES=20000 `
  --dart-define=OTZARIA_GC_PROBE_MAX_FILE_MIB=128 `
  test/tool/perf_probe/external_books_gc_probe_test.dart |
    Tee-Object -FilePath personal-books-gc-results.log
```

For a single problem file on a slow/cloud/network volume:

```powershell
flutter test --reporter expanded `
  "--dart-define=OTZARIA_GC_PROBE_FILE=D:\\MyBooks\\very-slow.docx" `
  --dart-define=OTZARIA_GC_PROBE_RUNS=2 `
  --dart-define=OTZARIA_GC_PROBE_MAX_FILE_MIB=512 `
  test/tool/perf_probe/external_books_gc_probe_test.dart
```

Run the probe via the **Flutter test engine**, not `dart run`: production
document converters transitively import `dart:ui`, which is not provided by a
standalone Dart VM. Omitting file/folder defines runs one synthetic smoke book.

The limit is **per book**, not total corpus size. Use the same source files
for both modes; do not copy them to a fast SSD before measurement.

The probe runs two comparable paths serially inside a worker isolate:

- `sync-baseline`: the old `readAsBytesSync` call plus the same
  byte converter and TOC parser.
- `async-read`: the production `convertDocumentFile` path plus the same
  TOC parser.

Each pass outputs JSON with wall time, event-loop heartbeat p95/p99/maximum
gap in milliseconds (nominal interval: 16 ms), peak process RSS in MiB,
processed/failed counts, TOC count, character count and a lightweight output
fingerprint. The caller isolate allocates a **bounded 4 MiB rolling window**
to encourage GC while worker I/O is active; stored heartbeat samples are
capped at 50,000. With two passes, mode order is reversed to reduce page
cache bias. Output mismatch sets a nonzero exit code.

This measures the **conversion and TOC-preparation phase**, not the entire
DB-writing scan, a native Flutter frame benchmark, or a deterministic GC
safepoint trace. A fast local disk may produce no measurable difference.
For conclusive Windows QA, compare the JSON results with the original
slow-storage reproduction while collecting a VM/native hang trace.

## Residual risks, outside this focused follow-up

- HTML linked local images still use `readAsBytesSync` inside
  `html_to_otzaria.dart`, even when `embedImages: false`. Removing this
  read outright would change whether the image row exists when an image
  is unreadable and could shift TOC and annotation line indexes. A separate
  parity-preserving async resolver is needed.
- The general `PersonalBooksOperationQueue` is serial but has no bound on
  **pending operations**; the changed converter did not add any fan-out.
- No explicit cancellation token exists for an in-flight file read; callers
  currently await it rather than launching untracked work.
- Other pre-existing synchronous reads in `docx_cache.dart` and the
  plain-text runtime converter remain separate work.

## Focused CI / local verification

```powershell
flutter test test/utils/file/convert_document_file_async_io_test.dart test/data/data_providers/scan_external_books_db_cleanup_test.dart test/utils/file/convert_document_file_test.dart test/data/data_providers/scan_external_books_test.dart
flutter test test/tool/perf_probe/external_books_gc_probe_test.dart
flutter analyze
```
