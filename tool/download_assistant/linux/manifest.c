#include "manifest.h"

#include <string.h>

#include "otz_common.h"

static void free_part(gpointer data) {
  OtzPart *part = data;
  g_free(part->name);
  g_free(part->sha256);
  g_free(part);
}

static void free_asset(gpointer data) {
  OtzAsset *asset = data;
  g_free(asset->kind);
  g_free(asset->repository);
  g_free(asset->release_tag);
  g_free(asset->name);
  g_free(asset->sha256);
  g_ptr_array_unref(asset->parts);
  g_free(asset);
}

static void free_component(gpointer data) {
  OtzComponent *component = data;
  g_free(component->id);
  g_free(component->name);
  g_free(component->description);
  g_free(component->type);
  g_free(component->platform);
  g_free(component->architecture);
  g_free(component->package_format);
  g_ptr_array_unref(component->depends_on);
  g_ptr_array_unref(component->installed_by);
  g_free(component->part_of);
  g_free(component->output_folder);
  g_free(component->output_note);
  g_free(component->name_en);
  g_free(component->description_en);
  g_free(component->output_note_en);
  g_ptr_array_unref(component->assets);
  g_free(component);
}

void otz_manifest_free(OtzManifest *manifest) {
  if (manifest == NULL) return;
  g_free(manifest->release_tag);
  g_free(manifest->release_version);
  g_ptr_array_unref(manifest->components);
  g_free(manifest);
}

gboolean otz_is_safe_token(const char *text) {
  if (text == NULL || *text == '\0') return FALSE;
  if (strcmp(text, ".") == 0 || strcmp(text, "..") == 0) return FALSE;
  for (const char *p = text; *p; p++) {
    if (!g_ascii_isalnum(*p) && *p != '.' && *p != '_' && *p != '+' &&
        *p != '-')
      return FALSE;
  }
  return TRUE;
}

gboolean otz_is_safe_output_folder(const char *folder) {
  if (folder == NULL || *folder == '\0' || strchr(folder, '+') != NULL)
    return FALSE;
  g_auto(GStrv) segments = g_strsplit(folder, "/", -1);
  for (char **segment = segments; *segment != NULL; segment++) {
    if (!otz_is_safe_token(*segment)) return FALSE;
    if (strspn(*segment, ".") == strlen(*segment)) return FALSE;
  }
  return TRUE;
}

gboolean otz_is_allowed_repository(const char *repository) {
  if (repository == NULL) return FALSE;
  const char *owner = otz_allowed_owner();
  gsize owner_length = strlen(owner);
  if (strncmp(repository, owner, owner_length) != 0 ||
      repository[owner_length] != '/')
    return FALSE;
  const char *name = repository + owner_length + 1;
  if (*name == '\0') return FALSE;
  for (const char *p = name; *p; p++) {
    if (!g_ascii_isalnum(*p) && *p != '.' && *p != '_' && *p != '-')
      return FALSE;
  }
  return TRUE;
}

static gboolean is_sha256(const char *text) {
  if (text == NULL || strlen(text) != 64) return FALSE;
  for (const char *p = text; *p; p++) {
    if (!g_ascii_isxdigit(*p)) return FALSE;
  }
  return TRUE;
}

static const char *pick(const char *hebrew, const char *english, gboolean want) {
  return want && *english != '\0' ? english : hebrew;
}

const char *otz_component_name(const OtzComponent *component, gboolean english) {
  return pick(component->name, component->name_en, english);
}

const char *otz_component_description(const OtzComponent *component,
                                      gboolean english) {
  return pick(component->description, component->description_en, english);
}

const char *otz_component_output_note(const OtzComponent *component,
                                      gboolean english) {
  return pick(component->output_note, component->output_note_en, english);
}

char *otz_asset_url(const OtzAsset *asset, const char *file_name) {
  return g_strdup_printf("https://github.com/%s/releases/download/%s/%s",
                         asset->repository, asset->release_tag, file_name);
}

static char *dup_optional(const OtzJson *object, const char *key) {
  const char *value = otz_json_get_string(object, key);
  return g_strdup(value != NULL ? value : "");
}

static gboolean invalid(GError **error, const char *component_id,
                        const char *what) {
  g_set_error(error, OTZ_ERROR, OTZ_ERROR_PARSE,
              "manifest: component '%s': %s",
              component_id != NULL ? component_id : "?", what);
  return FALSE;
}

static gboolean parse_asset(const OtzJson *json, const char *component_id,
                            OtzAsset **out, GError **error) {
  OtzAsset *asset = g_new0(OtzAsset, 1);
  asset->parts = g_ptr_array_new_with_free_func(free_part);
  *out = asset;
  asset->kind = dup_optional(json, "kind");
  asset->repository = dup_optional(json, "repository");
  asset->release_tag = dup_optional(json, "releaseTag");
  asset->name = dup_optional(json, "name");
  asset->sha256 = g_ascii_strdown(otz_json_get_string(json, "sha256") != NULL
                                      ? otz_json_get_string(json, "sha256")
                                      : "",
                                  -1);
  if (!otz_json_get_int(json, "size", &asset->size) || asset->size <= 0)
    return invalid(error, component_id, "asset without a size");
  if (!is_sha256(asset->sha256))
    return invalid(error, component_id, "asset without a sha256");
  if (!otz_is_allowed_repository(asset->repository))
    return invalid(error, component_id, "repository outside the organization");
  if (!otz_is_safe_token(asset->release_tag) || !otz_is_safe_token(asset->name))
    return invalid(error, component_id, "unsafe tag or asset name");

  if (strcmp(asset->kind, "single") == 0) return TRUE;
  if (strcmp(asset->kind, "split") != 0)
    return invalid(error, component_id, "unknown asset kind");

  const OtzJson *parts = otz_json_get(json, "parts");
  guint count = otz_json_array_length(parts);
  if (count == 0) return invalid(error, component_id, "split asset without parts");
  gint64 total = 0;
  for (guint i = 0; i < count; i++) {
    const OtzJson *item = otz_json_array_get(parts, i);
    OtzPart *part = g_new0(OtzPart, 1);
    g_ptr_array_add(asset->parts, part);
    part->name = dup_optional(item, "name");
    const char *sha = otz_json_get_string(item, "sha256");
    part->sha256 = g_ascii_strdown(sha != NULL ? sha : "", -1);
    if (!otz_json_get_int(item, "size", &part->size) || part->size <= 0 ||
        !is_sha256(part->sha256) || !otz_is_safe_token(part->name))
      return invalid(error, component_id, "bad part");
    total += part->size;
  }
  if (total != asset->size)
    return invalid(error, component_id, "parts do not add up to the asset size");
  return TRUE;
}

static gboolean parse_component(const OtzJson *json, OtzComponent **out,
                                GError **error) {
  OtzComponent *component = g_new0(OtzComponent, 1);
  component->depends_on = g_ptr_array_new_with_free_func(g_free);
  component->installed_by = g_ptr_array_new_with_free_func(g_free);
  component->assets = g_ptr_array_new_with_free_func(free_asset);
  *out = component;
  if (json == NULL || json->type != OTZ_JSON_OBJECT)
    return invalid(error, NULL, "not an object");
  component->id = dup_optional(json, "id");
  component->name = dup_optional(json, "name");
  component->description = dup_optional(json, "description");
  component->type = dup_optional(json, "type");
  component->platform = dup_optional(json, "platform");
  component->architecture = dup_optional(json, "architecture");
  component->package_format = dup_optional(json, "packageFormat");
  component->part_of = dup_optional(json, "partOf");
  component->output_folder = dup_optional(json, "outputFolder");
  component->output_note = dup_optional(json, "outputNote");
  component->name_en = dup_optional(json, "nameEn");
  component->description_en = dup_optional(json, "descriptionEn");
  component->output_note_en = dup_optional(json, "outputNoteEn");
  const OtzJson *required = otz_json_get(json, "required");
  component->required =
      required != NULL && required->type == OTZ_JSON_BOOL && required->boolean;
  if (!otz_json_get_int(json, "downloadSize", &component->download_size))
    component->download_size = 0;
  if (*component->id == '\0' || *component->name == '\0')
    return invalid(error, component->id, "missing id or name");
  if (*component->output_folder != '\0' &&
      !otz_is_safe_output_folder(component->output_folder))
    return invalid(error, component->id, "unsafe outputFolder");

  const OtzJson *depends = otz_json_get(json, "dependsOn");
  for (guint i = 0; i < otz_json_array_length(depends); i++) {
    const OtzJson *dependency = otz_json_array_get(depends, i);
    if (dependency->type != OTZ_JSON_STRING)
      return invalid(error, component->id, "bad dependsOn");
    g_ptr_array_add(component->depends_on, g_strdup(dependency->string));
  }

  const OtzJson *installers = otz_json_get(json, "installedBy");
  for (guint i = 0; i < otz_json_array_length(installers); i++) {
    const OtzJson *installer = otz_json_array_get(installers, i);
    if (installer->type != OTZ_JSON_STRING)
      return invalid(error, component->id, "bad installedBy");
    g_ptr_array_add(component->installed_by, g_strdup(installer->string));
  }

  const OtzJson *assets = otz_json_get(json, "assets");
  guint count = otz_json_array_length(assets);
  if (count == 0) return invalid(error, component->id, "no assets");
  for (guint i = 0; i < count; i++) {
    OtzAsset *asset = NULL;
    gboolean ok =
        parse_asset(otz_json_array_get(assets, i), component->id, &asset, error);
    g_ptr_array_add(component->assets, asset);
    if (!ok) return FALSE;
  }
  return TRUE;
}

OtzManifest *otz_manifest_from_json(const OtzJson *root, GError **error) {
  g_autoptr(OtzManifest) manifest = g_new0(OtzManifest, 1);
  manifest->components = g_ptr_array_new_with_free_func(free_component);
  if (root == NULL || root->type != OTZ_JSON_OBJECT) {
    g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_PARSE,
                        "manifest: not an object");
    return NULL;
  }
  if (!otz_json_get_int(root, "schemaVersion", &manifest->schema_version) ||
      manifest->schema_version != OTZ_MANIFEST_SCHEMA_VERSION) {
    g_set_error(error, OTZ_ERROR, OTZ_ERROR_PARSE,
                "manifest: unsupported schemaVersion %" G_GINT64_FORMAT,
                manifest->schema_version);
    return NULL;
  }
  manifest->release_tag = dup_optional(root, "releaseTag");
  manifest->release_version = dup_optional(root, "releaseVersion");

  const OtzJson *components = otz_json_get(root, "components");
  guint count = otz_json_array_length(components);
  if (count == 0) {
    g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_PARSE,
                        "manifest: no components");
    return NULL;
  }
  for (guint i = 0; i < count; i++) {
    OtzComponent *component = NULL;
    gboolean ok =
        parse_component(otz_json_array_get(components, i), &component, error);
    g_ptr_array_add(manifest->components, component);
    if (!ok) return NULL;
  }
  for (guint i = 0; i < count; i++) {
    const OtzComponent *component = g_ptr_array_index(manifest->components, i);
    for (guint d = 0; d < component->depends_on->len; d++) {
      if (otz_manifest_find(manifest,
                            g_ptr_array_index(component->depends_on, d)) == NULL) {
        invalid(error, component->id, "dependsOn points at a missing component");
        return NULL;
      }
    }
  }
  return g_steal_pointer(&manifest);
}

OtzManifest *otz_manifest_parse(const char *data, gsize length, GError **error) {
  g_autoptr(OtzJson) root = otz_json_parse(data, length, error);
  if (root == NULL) return NULL;
  return otz_manifest_from_json(root, error);
}

const OtzComponent *otz_manifest_find(const OtzManifest *manifest,
                                      const char *id) {
  for (guint i = 0; i < manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(manifest->components, i);
    if (strcmp(component->id, id) == 0) return component;
  }
  return NULL;
}
