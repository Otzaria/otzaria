/* Port of tool/release/download_assistant_selection.dart — the reference
 * implementation. tests/test_main.c compares this against
 * tool/download_assistant/fixtures/expected-selections.json. */
#pragma once

#include <glib.h>

#include "manifest.h"

#define OTZ_MAX_SINGLE_OUTPUT_FILE_SIZE G_GINT64_CONSTANT(4294967296)
#define OTZ_PORTABLE_PACKAGE_FORMAT "portable"
/* Pre-selected: with internet, the library downloads from inside the app. */
#define OTZ_DEFAULT_PRESET_ID "basic"

typedef struct {
  const char *platform;
  const char *architecture;   /* "" when the platform has no arch choice */
  const char *package_format; /* "" outside Linux */
} OtzTarget;

typedef struct {
  char *id;
  const char *caption;
  const char *description;
  GPtrArray *members; /* char* component ids, manifest order */
} OtzPreset;

void otz_preset_free(OtzPreset *preset);

/* Platforms in the order shown, and their display names. */
extern const char *const otz_assistant_platforms[];
const char *otz_platform_display_name(const char *platform);

gboolean otz_component_fits_target(const OtzComponent *component,
                                   const OtzTarget *target);
/* The first installedBy entry offered for the target, or NULL. */
const OtzComponent *otz_installer_for(const OtzManifest *manifest,
                                      const OtzComponent *component,
                                      const OtzTarget *target);
/* Shown in the presets and the custom list: fits, carries no unrunnable exe,
 * and when installedBy is set one of its installers is offered. */
gboolean otz_component_is_offered(const OtzManifest *manifest,
                                  const OtzComponent *component,
                                  const OtzTarget *target);

/* All the following return arrays of owned char*. */
GPtrArray *otz_platform_choices(const OtzManifest *manifest);
GPtrArray *otz_architecture_choices(const OtzManifest *manifest,
                                    const char *platform);
GPtrArray *otz_package_format_choices(const OtzManifest *manifest,
                                      const char *platform,
                                      const char *architecture);
/* os_release is the content of /etc/os-release, or NULL off Linux. */
char *otz_default_package_format(const char *os_release, GPtrArray *choices);

/* A row of the custom list. locked: always checked, cannot be cleared.
 * group: rows sharing it are one-of (radio); "" is a checkbox. */
#define OTZ_APPLICATION_CHOICE_GROUP "application"
typedef struct {
  const OtzComponent *component; /* borrowed from the manifest */
  gboolean locked;
  const char *group;
} OtzCustomChoice;

/* OtzCustomChoice* in manifest order: never the portable form; when the
 * regular installer unpacks a library beside it, no full bundle and the
 * installer locked; otherwise the installer and the bundle are one-of. */
GPtrArray *otz_custom_choices(const OtzManifest *manifest,
                              const OtzTarget *target);

/* A row's size includes its offered parts. */
gint64 otz_custom_choice_size(const OtzManifest *manifest,
                              const OtzComponent *component,
                              const OtzTarget *target);

GPtrArray *otz_with_dependencies(const OtzManifest *manifest,
                                 GPtrArray *members, const OtzTarget *target);
/* OtzPreset* in display order: basic, full-indexed, full, update. Empty ones,
 * and duplicates of one evaluated earlier (full-indexed, full, basic, update —
 * the more specific label stays), are dropped. */
GPtrArray *otz_build_presets(const OtzManifest *manifest,
                             const OtzTarget *target);
/* The pre-selected preset: "basic", else "full" (not the larger
 * "full-indexed"), else the first. -1 when there are no presets. */
int otz_default_preset_index(GPtrArray *presets);

gboolean otz_should_assemble_split_asset(const OtzAsset *asset,
                                         const char *target_platform);
char *otz_output_subfolder_name(const char *target_platform);
GPtrArray *otz_planned_output_files(const OtzManifest *manifest,
                                    GPtrArray *selected_ids,
                                    const OtzTarget *target);
/* The outputNote of each selected component, manifest order, no repeats. */
GPtrArray *otz_planned_output_notes(const OtzManifest *manifest,
                                    GPtrArray *selected_ids);
/* "" for a single file, otherwise the subfolder name. */
char *otz_planned_output_subfolder(GPtrArray *files,
                                   const char *target_platform);

gint64 otz_members_download_size(const OtzManifest *manifest,
                                 GPtrArray *members);
gboolean otz_string_array_contains(GPtrArray *array, const char *value);
