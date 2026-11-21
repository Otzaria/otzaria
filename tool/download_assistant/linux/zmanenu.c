#include "zmanenu.h"

#include <string.h>

#include "http.h"
#include "manifest.h"
#include "otz_common.h"

#define MAX_REPLY (4 * 1024 * 1024)

static void free_file(gpointer data) {
  OtzZmanenuFile *file = data;
  g_free(file->name);
  g_free(file->sha256);
  g_free(file->url);
  g_free(file);
}

void otz_zmanenu_offer_free(OtzZmanenuOffer *offer) {
  if (offer == NULL) return;
  g_free(offer->tag);
  g_ptr_array_unref(offer->downloads);
  g_clear_pointer(&offer->parts_manifest, g_bytes_unref);
  g_free(offer);
}

gboolean otz_zmanenu_is_offered(const OtzTarget *target) {
  return strcmp(target->platform, "windows") == 0 ||
         strcmp(target->platform, "macos") == 0 ||
         strcmp(target->platform, "linux") == 0;
}

char *otz_zmanenu_asset_url(const char *tag, const char *name) {
  if (*tag == '\0')
    return g_strdup_printf("https://github.com/%s/" OTZ_ZMANENU_REPOSITORY_NAME
                           "/releases/latest/download/%s",
                           otz_allowed_owner(), name);
  return g_strdup_printf("https://github.com/%s/" OTZ_ZMANENU_REPOSITORY_NAME
                         "/releases/download/%s/%s",
                         otz_allowed_owner(), tag, name);
}

static gboolean is_sha256(const char *text) {
  if (text == NULL || strlen(text) != 64) return FALSE;
  for (const char *c = text; *c != '\0'; c++)
    if (!g_ascii_isdigit(*c) && !(*c >= 'a' && *c <= 'f')) return FALSE;
  return TRUE;
}

/* The sha256 of an API asset's "digest" ("sha256:<hex>"), or NULL. */
static const char *asset_sha256(const OtzJson *asset) {
  const char *digest = otz_json_get_string(asset, "digest");
  if (digest == NULL || !g_str_has_prefix(digest, "sha256:")) return NULL;
  return is_sha256(digest + 7) ? digest + 7 : NULL;
}

static const OtzJson *find_asset(const OtzJson *release, const char *name) {
  const OtzJson *assets = otz_json_get(release, "assets");
  for (guint i = 0; i < otz_json_array_length(assets); i++) {
    const OtzJson *asset = otz_json_array_get(assets, i);
    if (g_strcmp0(otz_json_get_string(asset, "name"), name) == 0) return asset;
  }
  return NULL;
}

/* verified: only with a sha256 digest. */
static const OtzJson *whole_asset(const OtzJson *release, gboolean verified) {
  const OtzJson *assets = otz_json_get(release, "assets");
  for (guint i = 0; i < otz_json_array_length(assets); i++) {
    const OtzJson *asset = otz_json_array_get(assets, i);
    gint64 size;
    if (g_strcmp0(otz_json_get_string(asset, "name"), OTZ_ZMANENU_ARCHIVE) == 0 &&
        otz_json_get_int(asset, "size", &size) && size > 0 &&
        (!verified || asset_sha256(asset) != NULL))
      return asset;
  }
  return NULL;
}

static const char *release_tag(const OtzJson *release) {
  const char *tag = otz_json_get_string(release, "tag_name");
  return tag != NULL && otz_is_safe_token(tag) ? tag : NULL;
}

char *otz_zmanenu_parts_manifest_url(const OtzJson *release) {
  if (release == NULL) return otz_zmanenu_asset_url("", OTZ_ZMANENU_PARTS_MANIFEST);
  const char *tag = release_tag(release);
  if (tag == NULL || whole_asset(release, TRUE) != NULL ||
      find_asset(release, OTZ_ZMANENU_PARTS_MANIFEST) == NULL)
    return NULL;
  return otz_zmanenu_asset_url(tag, OTZ_ZMANENU_PARTS_MANIFEST);
}

static OtzZmanenuOffer *new_offer(const char *tag) {
  OtzZmanenuOffer *offer = g_new0(OtzZmanenuOffer, 1);
  offer->tag = g_strdup(tag);
  offer->downloads = g_ptr_array_new_with_free_func(free_file);
  return offer;
}

static void add_file(OtzZmanenuOffer *offer, const char *name, gint64 size,
                     const char *sha256) {
  OtzZmanenuFile *file = g_new0(OtzZmanenuFile, 1);
  file->name = g_strdup(name);
  file->size = size;
  file->sha256 = g_strdup(sha256);
  file->url = otz_zmanenu_asset_url(offer->tag, name);
  g_ptr_array_add(offer->downloads, file);
}

/* sha256 "" — not verified here; the app checks the signature and sha256. */
static OtzZmanenuOffer *whole_offer(const char *tag, const OtzJson *asset,
                                    const char *sha256) {
  gint64 size = 0;
  if (asset != NULL) otz_json_get_int(asset, "size", &size);
  OtzZmanenuOffer *offer = new_offer(tag);
  add_file(offer, OTZ_ZMANENU_ARCHIVE, size, sha256);
  return offer;
}

OtzZmanenuOffer *otz_zmanenu_offer(const OtzJson *release, GBytes *parts_manifest) {
  const char *tag = "";
  if (release != NULL) {
    tag = release_tag(release);
    if (tag == NULL) return NULL;
    const OtzJson *whole = whole_asset(release, TRUE);
    if (whole != NULL) return whole_offer(tag, whole, asset_sha256(whole));
  }
  if (parts_manifest == NULL) {
    if (release == NULL) return whole_offer(tag, NULL, "");
    const OtzJson *unverified = whole_asset(release, FALSE);
    return unverified != NULL ? whole_offer(tag, unverified, "") : NULL;
  }
  gsize length;
  const char *data = g_bytes_get_data(parts_manifest, &length);
  g_autoptr(OtzJson) manifest = otz_json_parse(data, length, NULL);
  if (manifest == NULL ||
      g_strcmp0(otz_json_get_string(manifest, "archive"), OTZ_ZMANENU_ARCHIVE) != 0)
    return NULL;
  const OtzJson *parts = otz_json_get(manifest, "parts");
  guint count = otz_json_array_length(parts);
  if (count == 0) return NULL;
  g_autoptr(OtzZmanenuOffer) offer = new_offer(tag);
  gint64 total = 0;
  for (guint i = 0; i < count; i++) {
    const OtzJson *part = otz_json_array_get(parts, i);
    const char *name = otz_json_get_string(part, "name");
    const char *sha256 = otz_json_get_string(part, "sha256");
    gint64 size;
    g_autofree char *expected = g_strdup_printf(OTZ_ZMANENU_ARCHIVE ".part-%03u", i);
    if (g_strcmp0(name, expected) != 0 || !otz_json_get_int(part, "size", &size) ||
        size <= 0 || !is_sha256(sha256))
      return NULL;
    /* The part must be an asset of the same release, of the same size. */
    if (release != NULL) {
      const OtzJson *asset = find_asset(release, name);
      gint64 listed;
      if (asset == NULL || !otz_json_get_int(asset, "size", &listed) || listed != size)
        return NULL;
    }
    add_file(offer, name, size, sha256);
    total += size;
  }
  gint64 size;
  if (!otz_json_get_int(manifest, "size", &size) || size != total) return NULL;
  offer->parts_manifest = g_bytes_ref(parts_manifest);
  return g_steal_pointer(&offer);
}

gint64 otz_zmanenu_download_size(const OtzZmanenuOffer *offer) {
  gint64 total = 0;
  for (guint i = 0; i < offer->downloads->len; i++)
    total += ((OtzZmanenuFile *)g_ptr_array_index(offer->downloads, i))->size;
  return total;
}

GPtrArray *otz_zmanenu_output_files(const OtzZmanenuOffer *offer) {
  GPtrArray *files = g_ptr_array_new_with_free_func(g_free);
  for (guint i = 0; i < offer->downloads->len; i++) {
    const OtzZmanenuFile *file = g_ptr_array_index(offer->downloads, i);
    g_ptr_array_add(files, g_strdup(file->name));
  }
  if (offer->parts_manifest != NULL)
    g_ptr_array_add(files, g_strdup(OTZ_ZMANENU_PARTS_MANIFEST));
  return files;
}

char *otz_zmanenu_drop_dir(void) {
  const char *home = g_getenv("HOME");
  if (home == NULL || *home == '\0') home = g_get_home_dir();
  return g_build_filename(home, ".local", "share", "otzaria", OTZ_ZMANENU_DROP_FOLDER,
                          NULL);
}

/* *not_found: HTTP 404 — there is no repository or no release. */
static GBytes *fetch(const char *url, const char *accept, gboolean *not_found,
                     GCancellable *cancellable) {
  g_autoptr(GError) error = NULL;
  GBytes *bytes = otz_http_fetch(url, accept, MAX_REPLY, cancellable, &error);
  if (bytes == NULL && error != NULL) {
    if (not_found != NULL)
      *not_found = g_error_matches(error, OTZ_ERROR, OTZ_ERROR_HTTP) &&
                   g_str_has_prefix(error->message, "HTTP 404 ");
    g_debug("zmanenu: %s", error->message);
  }
  return bytes;
}

OtzZmanenuOffer *otz_zmanenu_load(GCancellable *cancellable) {
  g_autofree char *api =
      g_strdup_printf("https://api.github.com/repos/%s/" OTZ_ZMANENU_REPOSITORY_NAME
                      "/releases/latest",
                      otz_allowed_owner());
  gboolean not_found = FALSE;
  g_autoptr(GBytes) reply =
      fetch(api, "application/vnd.github+json", &not_found, cancellable);
  if (not_found || g_cancellable_is_cancelled(cancellable)) return NULL;
  g_autoptr(OtzJson) release = NULL;
  if (reply != NULL) {
    gsize length;
    const char *data = g_bytes_get_data(reply, &length);
    release = otz_json_parse(data, length, NULL);
    if (release == NULL) return NULL;
  }
  g_autofree char *url = otz_zmanenu_parts_manifest_url(release);
  g_autoptr(GBytes) manifest = url != NULL ? fetch(url, NULL, NULL, cancellable) : NULL;
  return otz_zmanenu_offer(release, manifest);
}
