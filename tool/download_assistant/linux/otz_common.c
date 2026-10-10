#include "otz_common.h"

#include "build_info.h"

G_DEFINE_QUARK(otzaria-download-assistant-error-quark, otz_error)

static char *allowed_owner = NULL;

const char *otz_allowed_owner(void) {
  return allowed_owner != NULL ? allowed_owner : "Otzaria";
}

void otz_set_allowed_owner(const char *owner) {
  g_free(allowed_owner);
  allowed_owner = g_strdup(owner);
}

const char *otz_embedded_release_tag(void) { return OTZ_EMBEDDED_RELEASE_TAG; }

char *otz_human_size(gint64 bytes) {
  if (bytes >= G_GINT64_CONSTANT(1073741824)) {
    gint64 tenths = (bytes * 10) / G_GINT64_CONSTANT(1073741824);
    return g_strdup_printf("%" G_GINT64_FORMAT ".%" G_GINT64_FORMAT "\xC2\xA0GB",
                           tenths / 10, tenths % 10);
  }
  if (bytes >= 1048576)
    return g_strdup_printf("%" G_GINT64_FORMAT "\xC2\xA0MB", bytes / 1048576);
  return g_strdup_printf("%" G_GINT64_FORMAT "\xC2\xA0KB", (bytes + 1023) / 1024);
}

/* Like the WinHTTP and URLSession codes the other assistants treat as offline. */
gboolean otz_error_is_offline(const GError *error) {
  if (error == NULL) return FALSE;
  if (error->domain == G_RESOLVER_ERROR) return TRUE;
  if (error->domain != G_IO_ERROR) return FALSE;
  switch (error->code) {
    case G_IO_ERROR_NETWORK_UNREACHABLE:
    case G_IO_ERROR_HOST_UNREACHABLE:
    case G_IO_ERROR_CONNECTION_REFUSED:
    case G_IO_ERROR_TIMED_OUT:
    case G_IO_ERROR_HOST_NOT_FOUND:
      return TRUE;
    default:
      return FALSE;
  }
}

gboolean otz_error_is_retryable(const GError *error) {
  if (error == NULL) return FALSE;
  if (error->domain == G_IO_ERROR)
    return error->code != G_IO_ERROR_CANCELLED;
  if (error->domain == G_RESOLVER_ERROR) return TRUE;
  if (error->domain == OTZ_ERROR)
    return error->code == OTZ_ERROR_HTTP_SERVER ||
           error->code == OTZ_ERROR_NETWORK;
  return FALSE;
}

char *otz_ltr_isolate(const char *text) {
  /* U+2066 LEFT-TO-RIGHT ISOLATE ... U+2069 POP DIRECTIONAL ISOLATE */
  return g_strconcat("\xE2\x81\xA6", text, "\xE2\x81\xA9", NULL);
}
