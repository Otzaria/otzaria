# Android PDF file export evidence

The production channel copies a completed private staging file into a newly
created Storage Access Framework document in 64 KiB blocks. It uses
`ACTION_OPEN_DOCUMENT_TREE` followed by `DocumentsContract.createDocument`; it
does not infer ownership from `ACTION_CREATE_DOCUMENT`, which can return an
existing document. Existing documents are never selected for overwrite.

The source is validated and opened on the worker before launching the picker.
The source file and its two staging directories retain their device/inode
identities. Cleanup closes handles, removes only the known source, then removes
the empty operation directory. It also runs after engine/Activity detach.
Observed replacement of a file or directory causes refusal with
`staging_cleanup_failed:`; Dart preserves that refusal. This is not an atomic
defence against malicious concurrent mutation by another actor in the same
private cache, nor a process-death cleanup journal.

Cancellation and successful completion use one atomic decision. A positive
cancel ACK requires the worker to take the cancellation/cleanup path. It does
not mean that the source is already released. A save committed after successful
copy and handle closure remains saved if cancellation arrives before the main
thread delivers its result. Provider-blocked create/write/close calls cannot be
preempted; checks occur between native operations and copy blocks.

Only a newly returned document URI is eligible for rollback. Unsupported or
failed deletion reports the owned residual URI and a provider-observed name
when available. Names are queried again after successful close. This makes no
claim of atomic publication at the remote provider, provider-internal memory
usage, immediate cancellation of a blocked provider call, or completed cloud
upload after close.

## Native CI

`.github/workflows/pdf_mobile_export_android.yml` builds a separate debug app
(`org.otzaria.otzaria.pdfexportprobe`) and test APK with the existing SDK,
Flutter 3.47.7, Kotlin and JUnit pins. The normal application does not include the
probe Activity, fixture provider or control permission. No new dependency or
production permission is required.

The first case drives the actual Android DocumentsUI accessibility tree and
selects the controlled provider. It receives no fixture URI grant. A screenshot,
the observed DocumentsUI package, byte hashes and rendered PDF pixels are
required. Both a normal file-backed destination and a nonseekable pipe receive
more than 16 MiB from `MobilePdfExportService.instance`, with matching source and
destination SHA-256 values and a real `PdfRenderer` page render.

The remaining provider cases use legitimate URI grants issued by the fixture
provider itself. `MANAGE_DOCUMENTS` continues to protect the DocumentsProvider;
the shell and probe application never receive it. A separate signature-protected
control provider configures deterministic pipe gates and failures. It runs in a
different process from the client, so stream errors and closure cross Binder/PFD
boundaries. Its `call` implementation also checks the signature permission
explicitly; the host requires an unprivileged shell call to be rejected. The
fixture does not pretend an asynchronous remote upload failure
must surface synchronously through a client's `close()`.

Timing contracts that require stopping before source acquisition use the real
channel with a controlled executor and binary messenger. These native contract
tests do not substitute for the real-service/picker cases. They verify prepare
and picker detach without Dart cleanup, duplicate/stale activity results,
the saved/cancel commit boundary, and staging identity replacement. The final
case finishes the actual Flutter Activity while a pipe write is blocked; the
worker must then close and delete both the owned partial destination and staging
after the engine is gone. The probe observes the engine lifecycle callback and
requires its public engine ID to be absent from the embedding registry after
Activity destruction; Activity destruction alone is not sufficient evidence.

The host requires every named case, all pass flags, real positive partial-write
counts, source retention after cancel ACK, and source/APK/SDK hashes. Missing
evidence fails the job. Measured files must match their exact HEAD blobs before
build, after build and after the run, including both dependency files; framework
and engine revisions must also match. Log collection and each app cleanup run
independently, without replacing an earlier failure. `native-report.json`,
`source.json`, the three checkout receipts, the DocumentsUI
screenshot, full instrumentation output and logcat are retained on CI.

## Local checks

The operation/stream tests are ordinary JUnit 4 tests and can run on a JVM
without Android or Flutter. Host validation tests use Python's standard library:

```sh
python3 -m unittest -v tool.pdf_export_android.test_android_pdf_export
```

The full APK, Gradle and emulator paths run in GitHub CI. A successful local
Kotlin compilation or JVM test is not Android runtime evidence.
