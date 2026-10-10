/* Shared error domain and small helpers for the Linux download assistant. */
#pragma once

#include <gio/gio.h>
#include <glib.h>

#define OTZ_ERROR (otz_error_quark())
GQuark otz_error_quark(void);

typedef enum {
  OTZ_ERROR_PARSE,       /* JSON or manifest is invalid */
  OTZ_ERROR_PROTOCOL,    /* malformed HTTP reply */
  OTZ_ERROR_HTTP,        /* non-success HTTP status, not worth retrying */
  OTZ_ERROR_HTTP_SERVER, /* 5xx */
  OTZ_ERROR_NETWORK,     /* connection closed before the body ended */
  OTZ_ERROR_BLOCKED,     /* URL or redirect outside the allowed hosts */
  OTZ_ERROR_CORRUPT,     /* size or sha256 mismatch */
  OTZ_ERROR_IO,
  OTZ_ERROR_RATE_LIMITED, /* 403/429 — the GitHub API limit, often a shared IP */
} OtzErrorCode;

/* The GitHub organization every URL must belong to. Only a dev-only CLI flag
 * changes it (to test against a fork); the default is fixed by the contract. */
const char *otz_allowed_owner(void);
void otz_set_allowed_owner(const char *owner);

/* Release tag baked in at build time ("" for a local build). */
const char *otz_embedded_release_tag(void);

/* "1.8 GB", "40 MB", "1 KB" with a no-break space — the units of the app and
 * the other assistants. */
char *otz_human_size(gint64 bytes);

/* Network errors and 5xx replies are retried; anything else fails at once. */
gboolean otz_error_is_retryable(const GError *error);
/* The request never reached a server: no network, no DNS, refused, timed out. */
gboolean otz_error_is_offline(const GError *error);

/* Wraps a path in Unicode LTR isolation marks for display in RTL text. */
char *otz_ltr_isolate(const char *text);
