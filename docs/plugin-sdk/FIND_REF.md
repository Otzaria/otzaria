# External references in the native FindRef dialog

Since 0.9.99, a startup `libraryBooks` provider can opt in with
`referenceSearch: true` (boolean, default false). Its `when` condition and
startup-contribution permissions still apply. Existing providers remain unchanged.
Without an opted-in provider, the dialog retains its native row presentation,
query restoration and result cache. Native result tiles also retain their original
presentation when external references are present.

The host targets `findRef.external.requested` to the provider's plugin with
`{requestId, provider, query, limit}`. Respond using `reader.respondFindRef`:
`{requestId, results: [{reference, choiceIndex}], error?}`. Only the owning plugin
can answer; requests expire after 115 seconds. Duplicate responses and expired or
cancelled request IDs are rejected. Results are bounded to 100 and deduplicated.
Providers arrive independently and never replace local results.

Register these event handlers in both the background entry point and any restored
foreground entry point. Background delivery is preferred, but the host can select
the foreground runtime when no background controller is available. Each event is
sent to one controller, not broadcast to every instance of the plugin.
Search and cancellation never launch a plugin page. With no live runtime and no
background activation permission, search is skipped until the plugin is running.
An unavailable provider finishes immediately without keeping the dialog loading.
Requests cancelled or revoked before background boot are not delivered afterward.

`findRef.external.cancelled` carries `{requestId}` when a dialog supersedes or
clears its search. Drop queued work. A running native parse may finish, but its
response is no longer accepted. Cancellation is scoped to the requesting dialog.

`findRef.external.openRequested` carries
`{provider, query, choiceIndex, expectedChoice}` only after user selection.
Verify the exact title again before opening; the index alone is insufficient.
External references have no local `bookId` and never use the local book opener.
Passive searches must neither open a result nor launch the external application.
