# Report attachment contract

New application reports use `schema: 2`. Each image or uncompressed minidump
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

`schema` is stored locally and preserved through retries, queue restoration and
offline collection. A stored report without `schema` is a legacy schema 1
report and retains the old image/minidump policy. Editing a legacy report into
a new submission may explicitly change its schema after validating it again.

Schema 2 app reports are queued under
`app_reports_queue/pending_reports_v2`. Older offline updaters do not select
that kind, even if the capability file is missing or overwritten by an older
client. The compatible updater accepts both pending kinds and report schemas;
deploy it after the server and before the new client. Queue capability version
2 advertises support but is not the storage protection by itself.

Drafts remain in their own local tables. They are not sendable reports and
must not be included by queue exporters or offline collectors.

`test/fixtures/app_report_schema2.json` contains an actual Dart-generated
payload with Hebrew, an animated GIF, a gzip minidump and 200 attachment bytes.
The same fixture is checked by the website and the offline updater so changes
to serialization or byte accounting cannot silently diverge.
