#include "selection.h"

#include <string.h>

const char *const otz_assistant_platforms[] = {"windows", "macos", "linux",
                                               "android", NULL};

static const char *const display_names[][2] = {
    {"windows", "Windows"},
    {"macos", "macOS"},
    {"linux", "Linux"},
    {"android", "Android"},
};

static const char *const deb_family[] = {
    "debian", "ubuntu", "linuxmint", "pop",    "elementary", "zorin",
    "raspbian", "kali", "neon",      "deepin", "mx",         NULL};

static const char *const rpm_family[] = {
    "fedora", "rhel", "centos", "rocky",  "almalinux",    "ol",
    "suse",   "opensuse", "sles", "mageia", "openmandriva", "nobara", NULL};

void otz_preset_free(OtzPreset *preset) {
  if (preset == NULL) return;
  g_free(preset->id);
  g_ptr_array_unref(preset->members);
  g_free(preset);
}

const char *otz_platform_display_name(const char *platform) {
  for (gsize i = 0; i < G_N_ELEMENTS(display_names); i++) {
    if (strcmp(display_names[i][0], platform) == 0) return display_names[i][1];
  }
  return platform;
}

gboolean otz_string_array_contains(GPtrArray *array, const char *value) {
  for (guint i = 0; i < array->len; i++) {
    if (strcmp(g_ptr_array_index(array, i), value) == 0) return TRUE;
  }
  return FALSE;
}

static gboolean in_list(const char *const *list, const char *value) {
  for (gsize i = 0; list[i] != NULL; i++) {
    if (strcmp(list[i], value) == 0) return TRUE;
  }
  return FALSE;
}

static gboolean is_wildcard(const char *value) {
  return *value == '\0' || strcmp(value, "any") == 0;
}

static GPtrArray *new_strings(void) {
  return g_ptr_array_new_with_free_func(g_free);
}

gboolean otz_component_fits_target(const OtzComponent *component,
                                   const OtzTarget *target) {
  if (!is_wildcard(component->platform) &&
      strcmp(component->platform, target->platform) != 0)
    return FALSE;
  if (!is_wildcard(component->architecture) &&
      strcmp(component->architecture, target->architecture) != 0)
    return FALSE;
  if (!is_wildcard(component->package_format) &&
      strcmp(component->package_format, target->package_format) != 0)
    return FALSE;
  return TRUE;
}

/* Windows refuses to run an exe of 4 GiB or more. */
static gboolean component_is_runnable(const OtzComponent *component) {
  for (guint a = 0; a < component->assets->len; a++) {
    const OtzAsset *asset = g_ptr_array_index(component->assets, a);
    g_autofree char *lower = g_ascii_strdown(asset->name, -1);
    if (g_str_has_suffix(lower, ".exe") &&
        asset->size >= OTZ_MAX_SINGLE_OUTPUT_FILE_SIZE)
      return FALSE;
  }
  return TRUE;
}

const OtzComponent *otz_installer_for(const OtzManifest *manifest,
                                      const OtzComponent *component,
                                      const OtzTarget *target) {
  for (guint i = 0; i < component->installed_by->len; i++) {
    const OtzComponent *installer = otz_manifest_find(
        manifest, g_ptr_array_index(component->installed_by, i));
    if (installer != NULL && otz_component_fits_target(installer, target) &&
        component_is_runnable(installer))
      return installer;
  }
  return NULL;
}

gboolean otz_component_is_offered(const OtzManifest *manifest,
                                  const OtzComponent *component,
                                  const OtzTarget *target) {
  if (!otz_component_fits_target(component, target) ||
      !component_is_runnable(component))
    return FALSE;
  return component->installed_by->len == 0 ||
         otz_installer_for(manifest, component, target) != NULL;
}

static gboolean is_installer_type(const char *type) {
  return strcmp(type, "application") == 0 ||
         strcmp(type, "application-bundle") == 0;
}

GPtrArray *otz_custom_choices(const OtzManifest *manifest,
                              const OtzTarget *target) {
  gboolean takes_library = FALSE;
  for (guint i = 0; i < manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(manifest->components, i);
    if (!otz_component_is_offered(manifest, component, target)) continue;
    const OtzComponent *installer =
        otz_installer_for(manifest, component, target);
    if (installer != NULL && strcmp(installer->type, "application") == 0)
      takes_library = TRUE;
  }
  GPtrArray *rows = g_ptr_array_new();
  guint installers = 0;
  for (guint i = 0; i < manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(manifest->components, i);
    if (!otz_component_is_offered(manifest, component, target) ||
        strcmp(component->type, "application-portable") == 0 ||
        *component->part_of != '\0' ||
        (takes_library &&
         strcmp(component->type, "application-bundle") == 0))
      continue;
    g_ptr_array_add(rows, (gpointer)component);
    if (is_installer_type(component->type)) installers++;
  }
  GPtrArray *choices = g_ptr_array_new_with_free_func(g_free);
  for (guint i = 0; i < rows->len; i++) {
    const OtzComponent *component = g_ptr_array_index(rows, i);
    OtzCustomChoice *choice = g_new0(OtzCustomChoice, 1);
    gboolean installer = is_installer_type(component->type);
    choice->component = component;
    choice->locked = installer && installers <= 1;
    choice->group =
        installer && installers > 1 ? OTZ_APPLICATION_CHOICE_GROUP : "";
    g_ptr_array_add(choices, choice);
  }
  g_ptr_array_unref(rows);
  return choices;
}

gint64 otz_custom_choice_size(const OtzManifest *manifest,
                              const OtzComponent *component,
                              const OtzTarget *target) {
  gint64 total = component->download_size;
  for (guint i = 0; i < manifest->components->len; i++) {
    const OtzComponent *part = g_ptr_array_index(manifest->components, i);
    if (strcmp(part->part_of, component->id) == 0 &&
        otz_component_is_offered(manifest, part, target))
      total += part->download_size;
  }
  return total;
}

GPtrArray *otz_platform_choices(const OtzManifest *manifest) {
  GPtrArray *choices = new_strings();
  for (gsize p = 0; otz_assistant_platforms[p] != NULL; p++) {
    for (guint i = 0; i < manifest->components->len; i++) {
      const OtzComponent *component = g_ptr_array_index(manifest->components, i);
      if (strcmp(component->platform, otz_assistant_platforms[p]) == 0) {
        g_ptr_array_add(choices, g_strdup(otz_assistant_platforms[p]));
        break;
      }
    }
  }
  return choices;
}

static gint compare_strings(gconstpointer a, gconstpointer b) {
  return strcmp(*(const char *const *)a, *(const char *const *)b);
}

static void add_unique(GPtrArray *array, const char *value) {
  if (!otz_string_array_contains(array, value))
    g_ptr_array_add(array, g_strdup(value));
}

GPtrArray *otz_architecture_choices(const OtzManifest *manifest,
                                    const char *platform) {
  GPtrArray *found = new_strings();
  for (guint i = 0; i < manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(manifest->components, i);
    if (strcmp(component->platform, platform) != 0) continue;
    if (!is_wildcard(component->architecture))
      add_unique(found, component->architecture);
  }
  g_ptr_array_sort(found, compare_strings);
  for (guint i = 0; i < found->len; i++) {
    if (strcmp(g_ptr_array_index(found, i), "x64") == 0) {
      char *x64 = g_ptr_array_steal_index(found, i);
      g_ptr_array_insert(found, 0, x64);
      break;
    }
  }
  return found;
}

GPtrArray *otz_package_format_choices(const OtzManifest *manifest,
                                      const char *platform,
                                      const char *architecture) {
  GPtrArray *formats = new_strings();
  gboolean portable = FALSE;
  for (guint i = 0; i < manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(manifest->components, i);
    if (strcmp(component->platform, platform) != 0) continue;
    if (!is_wildcard(component->architecture) &&
        strcmp(component->architecture, architecture) != 0)
      continue;
    if (!is_wildcard(component->package_format))
      add_unique(formats, component->package_format);
    else if (g_str_has_prefix(component->type, "application"))
      portable = TRUE;
  }
  if (formats->len == 0) return formats;
  g_ptr_array_sort(formats, compare_strings);
  if (portable) g_ptr_array_add(formats, g_strdup(OTZ_PORTABLE_PACKAGE_FORMAT));
  return formats;
}

static char *pick_format(GPtrArray *choices, const char *preferred) {
  if (otz_string_array_contains(choices, preferred)) return g_strdup(preferred);
  return g_strdup(choices->len == 0 ? "" : g_ptr_array_index(choices, 0));
}

char *otz_default_package_format(const char *os_release, GPtrArray *choices) {
  if (os_release == NULL) return pick_format(choices, "deb");

  g_autofree char *id = NULL;
  g_autofree char *id_like = NULL;
  g_auto(GStrv) lines = g_strsplit(os_release, "\n", -1);
  for (gsize i = 0; lines[i] != NULL; i++) {
    const char *eq = strchr(lines[i], '=');
    if (eq == NULL || eq == lines[i]) continue;
    g_autofree char *key = g_strstrip(g_strndup(lines[i], eq - lines[i]));
    char *value = g_strstrip(g_strdup(eq + 1));
    gsize length = strlen(value);
    if (length >= 2 && (value[0] == '"' || value[0] == '\'') &&
        value[length - 1] == value[0]) {
      memmove(value, value + 1, length - 2);
      value[length - 2] = '\0';
    }
    char *lower = g_utf8_strdown(value, -1);
    g_free(value);
    if (strcmp(key, "ID") == 0) {
      g_free(id);
      id = lower;
    } else if (strcmp(key, "ID_LIKE") == 0) {
      g_free(id_like);
      id_like = lower;
    } else {
      g_free(lower);
    }
  }

  g_autoptr(GPtrArray) tokens = new_strings();
  if (id != NULL && *id != '\0') g_ptr_array_add(tokens, g_strdup(id));
  if (id_like != NULL) {
    g_auto(GStrv) parts = g_regex_split_simple("\\s+", id_like, 0, 0);
    for (gsize i = 0; parts[i] != NULL; i++) {
      if (*parts[i] != '\0') g_ptr_array_add(tokens, g_strdup(parts[i]));
    }
  }
  for (guint i = 0; i < tokens->len; i++) {
    const char *token = g_ptr_array_index(tokens, i);
    const char *family = g_str_has_prefix(token, "opensuse") ? "opensuse" : token;
    if (in_list(deb_family, family)) return pick_format(choices, "deb");
    if (in_list(rpm_family, family)) return pick_format(choices, "rpm");
  }
  return pick_format(choices, OTZ_PORTABLE_PACKAGE_FORMAT);
}

GPtrArray *otz_with_dependencies(const OtzManifest *manifest,
                                 GPtrArray *members, const OtzTarget *target) {
  g_autoptr(GHashTable) closed = g_hash_table_new(g_str_hash, g_str_equal);
  for (guint i = 0; i < members->len; i++)
    g_hash_table_add(closed, g_ptr_array_index(members, i));
  gboolean changed = TRUE;
  while (changed) {
    changed = FALSE;
    for (guint i = 0; i < manifest->components->len; i++) {
      const OtzComponent *component = g_ptr_array_index(manifest->components, i);
      if (!g_hash_table_contains(closed, component->id)) continue;
      for (guint d = 0; d < component->depends_on->len; d++) {
        const OtzComponent *dependency = otz_manifest_find(
            manifest, g_ptr_array_index(component->depends_on, d));
        if (dependency == NULL ||
            !otz_component_is_offered(manifest, dependency, target))
          continue;
        if (g_hash_table_add(closed, dependency->id)) changed = TRUE;
      }
      gboolean installed = component->installed_by->len == 0;
      for (guint d = 0; !installed && d < component->installed_by->len; d++)
        installed = g_hash_table_contains(
            closed, g_ptr_array_index(component->installed_by, d));
      if (installed) continue;
      const OtzComponent *installer =
          otz_installer_for(manifest, component, target);
      if (installer != NULL && g_hash_table_add(closed, installer->id))
        changed = TRUE;
    }
  }
  GPtrArray *result = new_strings();
  for (guint i = 0; i < manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(manifest->components, i);
    if (g_hash_table_contains(closed, component->id))
      g_ptr_array_add(result, g_strdup(component->id));
  }
  return result;
}

static gboolean type_in(const OtzComponent *component, const char *const *types) {
  return types == NULL || in_list(types, component->type);
}

static void collect(GPtrArray *out, const OtzManifest *manifest,
                    const OtzTarget *target, const char *const *types,
                    gboolean required_only) {
  for (guint i = 0; i < manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(manifest->components, i);
    if (otz_component_is_offered(manifest, component, target) &&
        (!required_only || component->required) && type_in(component, types))
      g_ptr_array_add(out, g_strdup(component->id));
  }
}

static gboolean same_list(GPtrArray *a, GPtrArray *b) {
  if (a->len != b->len) return FALSE;
  for (guint i = 0; i < a->len; i++) {
    if (strcmp(g_ptr_array_index(a, i), g_ptr_array_index(b, i)) != 0)
      return FALSE;
  }
  return TRUE;
}

/* The bundle and every offered component that lists it in installedBy. */
static void add_with_installed(GPtrArray *out, const OtzManifest *manifest,
                               const OtzComponent *bundle,
                               const OtzTarget *target) {
  g_ptr_array_add(out, g_strdup(bundle->id));
  for (guint i = 0; i < manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(manifest->components, i);
    if (otz_string_array_contains(component->installed_by, bundle->id) &&
        otz_component_is_offered(manifest, component, target))
      g_ptr_array_add(out, g_strdup(component->id));
  }
}

static gint64 installed_size(const OtzManifest *manifest,
                             const OtzComponent *bundle,
                             const OtzTarget *target) {
  g_autoptr(GPtrArray) members = new_strings();
  add_with_installed(members, manifest, bundle, target);
  return otz_members_download_size(manifest, members);
}

/* The indexed bundle: an offered library lists it in installedBy. */
static gboolean installs_library(const OtzManifest *manifest,
                                 const OtzComponent *bundle,
                                 const OtzTarget *target) {
  for (guint i = 0; i < manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(manifest->components, i);
    if (strcmp(component->type, "library") == 0 &&
        otz_string_array_contains(component->installed_by, bundle->id) &&
        otz_component_is_offered(manifest, component, target))
      return TRUE;
  }
  return FALSE;
}

GPtrArray *otz_build_presets(const OtzManifest *manifest,
                             const OtzTarget *target) {
  static const char *const full_types[] = {"application", "library",
                                           "dependency", NULL};
  static const char *const application_types[] = {"application", NULL};
  static const char *const library_types[] = {"library", NULL};
  static const char *const index_types[] = {"library-index", NULL};
  /* Smart-search data, read by the installed app from the output folder: part
   * of "full" and "full-indexed" only. */
  static const char *const offline_data_types[] = {"semantic-model",
                                                   "semantic-vectors", NULL};
  static const char *const display_order[] = {"basic", "full-indexed", "full",
                                              "update", NULL};

  const OtzComponent *bundle = NULL;
  const OtzComponent *indexed = NULL;
  for (guint i = 0; i < manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(manifest->components, i);
    if (!otz_component_is_offered(manifest, component, target)) continue;
    if (strcmp(component->type, "application-bundle") != 0) continue;
    if (bundle == NULL || component->download_size > bundle->download_size)
      bundle = component;
    if (installs_library(manifest, component, target) &&
        (indexed == NULL || installed_size(manifest, component, target) >
                                installed_size(manifest, indexed, target)))
      indexed = component;
  }

  /* Evaluation order: a duplicate of an earlier candidate is dropped. */
  struct {
    const char *id;
    const char *caption;
    const char *description;
    GPtrArray *members;
  } candidates[4] = {
      {"full-indexed", "התקנה מלאה + אינדקס חיפוש",
       "למחשב שאין בו אינטרנט — אינדקס החיפוש מוכן, והחיפוש עובד מיד. כולל חיפוש חכם.",
       new_strings()},
      {"full", "התקנה מלאה",
       "למחשב שאין בו אינטרנט — אינדקס החיפוש ייבנה בתוכנה, וזה לוקח זמן. כולל חיפוש חכם.",
       new_strings()},
      {"basic", "התקנה בסיסית (מומלצת)",
       "למחשב שיש בו אינטרנט — הספרייה תרד מתוך התוכנה.", new_strings()},
      {"update", "עדכון התוכנה בלבד",
       "קובץ ההתקנה של הגרסה החדשה, לעדכון התקנה קיימת.", new_strings()},
  };
  if (indexed != NULL) {
    add_with_installed(candidates[0].members, manifest, indexed, target);
    collect(candidates[0].members, manifest, target, offline_data_types, FALSE);
  }
  if (bundle != NULL) {
    /* The bundle comes with whatever it installs from the folder beside it. */
    add_with_installed(candidates[1].members, manifest, bundle, target);
    collect(candidates[1].members, manifest, target, offline_data_types, FALSE);
  } else {
    g_autoptr(GPtrArray) libraries = new_strings();
    collect(libraries, manifest, target, library_types, FALSE);
    /* Without a library there is no "full" install. */
    if (libraries->len > 0) {
      collect(candidates[1].members, manifest, target, full_types, FALSE);
      collect(candidates[1].members, manifest, target, offline_data_types,
              FALSE);
    }
    /* On Android also "full-indexed": building the index on a phone is very
     * slow. */
    if (libraries->len > 0 && strcmp(target->platform, "android") == 0) {
      collect(candidates[0].members, manifest, target, full_types, FALSE);
      collect(candidates[0].members, manifest, target, index_types, FALSE);
      collect(candidates[0].members, manifest, target, offline_data_types,
              FALSE);
    }
  }
  collect(candidates[2].members, manifest, target, application_types, FALSE);
  collect(candidates[2].members, manifest, target, NULL, TRUE);
  collect(candidates[3].members, manifest, target, application_types, FALSE);

  OtzPreset *chosen[G_N_ELEMENTS(candidates)] = {NULL};
  for (gsize c = 0; c < G_N_ELEMENTS(candidates); c++) {
    GPtrArray *members = candidates[c].members;
    GPtrArray *closed = members->len == 0
                            ? NULL
                            : otz_with_dependencies(manifest, members, target);
    g_ptr_array_unref(members);
    if (closed == NULL) continue;
    gboolean duplicate = closed->len == 0;
    for (gsize p = 0; !duplicate && p < c; p++) {
      if (chosen[p] != NULL) duplicate = same_list(chosen[p]->members, closed);
    }
    if (duplicate) {
      g_ptr_array_unref(closed);
      continue;
    }
    OtzPreset *preset = g_new0(OtzPreset, 1);
    preset->id = g_strdup(candidates[c].id);
    preset->caption = candidates[c].caption;
    preset->description = candidates[c].description;
    preset->members = closed;
    chosen[c] = preset;
  }

  GPtrArray *presets =
      g_ptr_array_new_with_free_func((GDestroyNotify)otz_preset_free);
  for (gsize d = 0; display_order[d] != NULL; d++) {
    for (gsize c = 0; c < G_N_ELEMENTS(candidates); c++) {
      if (chosen[c] != NULL && strcmp(chosen[c]->id, display_order[d]) == 0)
        g_ptr_array_add(presets, chosen[c]);
    }
  }
  return presets;
}

int otz_default_preset_index(GPtrArray *presets) {
  static const char *const preferred[] = {OTZ_DEFAULT_PRESET_ID, "full", NULL};
  for (gsize p = 0; preferred[p] != NULL; p++) {
    for (guint i = 0; i < presets->len; i++) {
      const OtzPreset *preset = g_ptr_array_index(presets, i);
      if (strcmp(preset->id, preferred[p]) == 0) return (int)i;
    }
  }
  return presets->len > 0 ? 0 : -1;
}

gboolean otz_should_assemble_split_asset(const OtzAsset *asset,
                                         const char *target_platform) {
  if (asset->size >= OTZ_MAX_SINGLE_OUTPUT_FILE_SIZE) return FALSE;
  if (strcmp(target_platform, "windows") == 0) {
    g_autofree char *lower = g_ascii_strdown(asset->name, -1);
    return g_str_has_suffix(lower, ".exe");
  }
  return TRUE;
}

char *otz_output_subfolder_name(const char *target_platform) {
  return g_strconcat("אוצריא להתקנה ל-",
                     otz_platform_display_name(target_platform), NULL);
}

GPtrArray *otz_planned_output_files(const OtzManifest *manifest,
                                    GPtrArray *selected_ids,
                                    const OtzTarget *target) {
  GPtrArray *files = new_strings();
  for (guint i = 0; i < manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(manifest->components, i);
    if (!otz_string_array_contains(selected_ids, component->id)) continue;
    const char *folder = component->output_folder;
    const char *slash = *folder != '\0' ? "/" : "";
    for (guint a = 0; a < component->assets->len; a++) {
      const OtzAsset *asset = g_ptr_array_index(component->assets, a);
      if (strcmp(asset->kind, "split") == 0 &&
          !otz_should_assemble_split_asset(asset, target->platform)) {
        for (guint p = 0; p < asset->parts->len; p++) {
          const OtzPart *part = g_ptr_array_index(asset->parts, p);
          g_ptr_array_add(files, g_strconcat(folder, slash, part->name, NULL));
        }
      } else {
        g_ptr_array_add(files, g_strconcat(folder, slash, asset->name, NULL));
      }
    }
  }
  return files;
}

GPtrArray *otz_planned_output_notes(const OtzManifest *manifest,
                                    GPtrArray *selected_ids) {
  GPtrArray *notes = new_strings();
  for (guint i = 0; i < manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(manifest->components, i);
    if (!otz_string_array_contains(selected_ids, component->id)) continue;
    if (*component->output_note == '\0' ||
        otz_string_array_contains(notes, component->output_note))
      continue;
    g_ptr_array_add(notes, g_strdup(component->output_note));
  }
  return notes;
}

char *otz_planned_output_subfolder(GPtrArray *files,
                                   const char *target_platform) {
  return files->len > 1 ? otz_output_subfolder_name(target_platform)
                        : g_strdup("");
}

gint64 otz_members_download_size(const OtzManifest *manifest,
                                 GPtrArray *members) {
  gint64 total = 0;
  for (guint i = 0; i < members->len; i++) {
    const OtzComponent *component =
        otz_manifest_find(manifest, g_ptr_array_index(members, i));
    if (component != NULL) total += component->download_size;
  }
  return total;
}
