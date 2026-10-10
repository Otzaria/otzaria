/* The release manifest (docs/download_assistant.md, "הסכמה"). */
#pragma once

#include <glib.h>

#include "json.h"

#define OTZ_MANIFEST_SCHEMA_VERSION 1

typedef struct {
  char *name;
  gint64 size;
  char *sha256;
} OtzPart;

typedef struct {
  char *kind; /* "single" | "split" */
  char *repository;
  char *release_tag;
  char *name;
  gint64 size;
  char *sha256;
  GPtrArray *parts; /* OtzPart*, empty for "single" */
} OtzAsset;

typedef struct {
  char *id;
  char *name;
  char *description;
  char *type;
  gboolean required;
  char *platform;       /* "" when absent */
  char *architecture;   /* "" when absent */
  char *package_format; /* "" when absent */
  gint64 download_size;
  GPtrArray *depends_on;   /* char* */
  GPtrArray *installed_by; /* char*: components that install this one */
  char *part_of;           /* "" when absent: shown and picked as part of it */
  char *output_folder;     /* "" when absent: relative folder in the output */
  char *output_note;       /* "" when absent: said on the finish page */
  char *name_en, *description_en, *output_note_en; /* "" when absent */
  GPtrArray *assets;       /* OtzAsset* */
} OtzComponent;

typedef struct {
  gint64 schema_version;
  char *release_tag;
  char *release_version;
  GPtrArray *components; /* OtzComponent*, manifest order */
} OtzManifest;

/* Parses and validates. Every downloadable file must carry a size and sha256,
 * and every URL piece must be safe, or the whole manifest is rejected. */
OtzManifest *otz_manifest_parse(const char *data, gsize length, GError **error);
OtzManifest *otz_manifest_from_json(const OtzJson *root, GError **error);
void otz_manifest_free(OtzManifest *manifest);
G_DEFINE_AUTOPTR_CLEANUP_FUNC(OtzManifest, otz_manifest_free)

/* The English text when asked for and present, otherwise the Hebrew. */
const char *otz_component_name(const OtzComponent *component, gboolean english);
const char *otz_component_description(const OtzComponent *component,
                                      gboolean english);
const char *otz_component_output_note(const OtzComponent *component,
                                      gboolean english);

const OtzComponent *otz_manifest_find(const OtzManifest *manifest,
                                      const char *id);

/* ^[A-Za-z0-9._+-]+$ and not "." or ".." — safe as a URL segment and file name. */
gboolean otz_is_safe_token(const char *text);
/* Segments of [A-Za-z0-9._-] joined by '/', none empty or dots only. */
gboolean otz_is_safe_output_folder(const char *folder);
/* ^<owner>/[A-Za-z0-9._-]+$ with the allowed owner. */
gboolean otz_is_allowed_repository(const char *repository);

/* https://github.com/<repository>/releases/download/<tag>/<file_name> */
char *otz_asset_url(const OtzAsset *asset, const char *file_name);
