# Report attachment contract

New application reports are built and validated with `schema: 2`. Each image or uncompressed minidump
may contain at most 10 MiB (10 × 1,024 × 1,024 bytes). All attachments together
may contain at most 20 MiB. The total includes the original image bytes, the
uncompressed minidump, UTF-8 bytes of compact JSON diagnostics, and UTF-8 bytes
of the error log. Diagnostics and logs also have a 10 MiB per-file limit. Schema 2 preserves their
complete content and rejects excess bytes before sending; only schema 1 retains
its previous truncation policy. GIF bytes are preserved, including animation.

The 128 MiB JSON request envelope includes base64 expansion, gzip overhead and the text
fields. A request at the attachment limit must not be rejected by a smaller
HTTP body limit. The website deployment must accept schema 1 and 2 and increase
its upload limit before a client that produces schema 2 is released.

Before the first HTTP request, `forCompatibleTransport()` can select schema 1
when its encoder preserves the entire payload. It checks the old 5 MiB image
and 15 MiB image-total limits and compares the complete text encoding, including
the old encoder's stricter 300,000-byte diagnostics, 250,000-byte log and
700,000-byte escaped-JSON limits. It never truncates content to make a new report
fit. A server error cannot trigger a schema downgrade. The canonical report
remains unchanged for retries, identity conflicts and failed submissions.

An explicit queue handoff stores a lossless small report without a minidump as
schema 1 in `app_reports_queue/pending_reports`. Reports that require the new
limits, and all new reports with a minidump, stay schema 2 in the protected
`app_reports_queue/pending_reports_v2` kind. The published v0.28.0 updater can
discard a rejected legacy minidump, so new dump reports must not enter its
collection path even when a direct schema 1 HTTP request would be lossless.
A stored report without `schema` is a legacy schema 1 report and retains its
previous policy. Existing records are not bulk-migrated. An explicit edit
validates against the new limits and updates the payload and queue kind together.

Older offline updaters do not select the protected kind, even if the capability
file is missing or overwritten by an older client. Queue capability version
remains 1 because adding a kind does not change the established queue layout:
old updaters continue collecting books, plugins and compatible application
reports. New databases and layout-1 databases retain `PRAGMA user_version = 1`;
the separate draft tables are additive. A database already marked 2 or a future
version is not silently downgraded, and v0.28.0 will still refuse that database.

For the full 10/20 MiB path and offline collection of new dump reports, deploy
the compatible website first, then publish an updater accepting both kinds and
schemas. An unreleased updater commit does not provide compatibility for users
of v0.28.0. The client keeps unsupported reports intact and explains when the
server or offline updater needs an update. Portable backups and generated send
scripts preserve attachments; backup version 3 protects schema 2 payloads from
older restorers.

Drafts remain in their own local tables. They are not sendable reports and
must not be included by queue exporters or offline collectors.

`test/fixtures/app_report_schema2.json` contains an actual Dart-generated
payload with Hebrew, an animated GIF, a gzip minidump and 200 attachment bytes.
The same fixture is checked by the website and the offline updater so changes
to serialization or byte accounting cannot silently diverge.
