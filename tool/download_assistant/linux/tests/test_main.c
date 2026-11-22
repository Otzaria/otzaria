/* Unit tests: the shared contract fixtures, JSON, HTTP parsing, host checks,
 * cache markers, assembly and the time-left estimate. Run with `make test`. */
#include <fcntl.h>
#include <math.h>
#include <stdlib.h>
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "assemble.h"
#include "download.h"
#include "eta.h"
#include "http.h"
#include "json.h"
#include "manifest.h"
#include "otz_common.h"
#include "paths.h"
#include "release.h"
#include "selection.h"
#include "texts.h"

/* ------------------------------------------------------------- helpers */

static char *read_fixture(const char *name, gsize *length) {
  g_autofree char *path = g_build_filename(OTZ_FIXTURES_DIR, name, NULL);
  char *data = NULL;
  g_autoptr(GError) error = NULL;
  g_assert_true(g_file_get_contents(path, &data, length, &error));
  g_assert_no_error(error);
  return data;
}

static void assert_strings(GPtrArray *actual, const OtzJson *expected,
                           const char *what) {
  guint count = otz_json_array_length(expected);
  if (actual->len != count) {
    g_test_message("%s: %u entries, expected %u", what, actual->len, count);
    g_assert_cmpuint(actual->len, ==, count);
  }
  for (guint i = 0; i < count; i++) {
    const OtzJson *item = otz_json_array_get(expected, i);
    g_assert_cmpint(item->type, ==, OTZ_JSON_STRING);
    if (strcmp(g_ptr_array_index(actual, i), item->string) != 0)
      g_test_message("%s[%u]", what, i);
    g_assert_cmpstr(g_ptr_array_index(actual, i), ==, item->string);
  }
}

static GPtrArray *json_strings(const OtzJson *array) {
  GPtrArray *result = g_ptr_array_new_with_free_func(g_free);
  for (guint i = 0; i < otz_json_array_length(array); i++)
    g_ptr_array_add(result, g_strdup(otz_json_array_get(array, i)->string));
  return result;
}

static char *temp_dir(void) {
  g_autoptr(GError) error = NULL;
  char *dir = g_dir_make_tmp("otz-test-XXXXXX", &error);
  g_assert_no_error(error);
  return dir;
}

static void write_file(const char *path, const char *data, gssize length) {
  g_autoptr(GError) error = NULL;
  g_assert_true(g_file_set_contents(path, data, length, &error));
}

/* ------------------------------------------------------------- fixtures */

/* Same samples as kOsReleaseSamples in generate_fixtures.dart. */
static const char *os_release_sample(const char *key, gboolean *known) {
  static const char *const samples[][2] = {
      {"ubuntu", "NAME=\"Ubuntu\"\nID=ubuntu\nID_LIKE=debian\nVERSION_ID=\"24.04\"\n"},
      {"linuxmint", "ID=linuxmint\nID_LIKE=\"ubuntu debian\"\n"},
      {"fedora", "NAME=\"Fedora Linux\"\nID=fedora\nVERSION_ID=40\n"},
      {"opensuse-tumbleweed", "ID=\"opensuse-tumbleweed\"\nID_LIKE=\"opensuse suse\"\n"},
      {"arch", "NAME=\"Arch Linux\"\nID=arch\n"},
      {"not-linux", NULL},
  };
  for (gsize i = 0; i < G_N_ELEMENTS(samples); i++) {
    if (strcmp(samples[i][0], key) == 0) {
      *known = TRUE;
      return samples[i][1];
    }
  }
  *known = FALSE;
  return NULL;
}

static void check_fixtures(const char *manifest_name, const char *expected_name) {
  gsize length;
  g_autofree char *manifest_text = read_fixture(manifest_name, &length);
  g_autoptr(GError) error = NULL;
  g_autoptr(OtzManifest) manifest =
      otz_manifest_parse(manifest_text, length, &error);
  g_assert_no_error(error);
  g_autofree char *expected_text = read_fixture(expected_name, &length);
  g_autoptr(OtzJson) expected = otz_json_parse(expected_text, length, &error);
  g_assert_no_error(error);

  g_autoptr(GPtrArray) platforms = otz_platform_choices(manifest);
  assert_strings(platforms, otz_json_get(expected, "platformChoices"),
                 "platformChoices");

  const OtzJson *arch = otz_json_get(expected, "architectureChoices");
  g_assert_cmpuint(arch->keys->len, >, 0);
  for (guint i = 0; i < arch->keys->len; i++) {
    const char *platform = g_ptr_array_index(arch->keys, i);
    g_autoptr(GPtrArray) actual = otz_architecture_choices(manifest, platform);
    assert_strings(actual, g_ptr_array_index(arch->items, i), platform);
  }

  const OtzJson *formats = otz_json_get(expected, "packageFormatChoices");
  g_assert_cmpuint(formats->keys->len, >, 0);
  for (guint i = 0; i < formats->keys->len; i++) {
    g_auto(GStrv) key = g_strsplit(g_ptr_array_index(formats->keys, i), "/", 2);
    g_autoptr(GPtrArray) actual =
        otz_package_format_choices(manifest, key[0], key[1]);
    assert_strings(actual, g_ptr_array_index(formats->items, i),
                   g_ptr_array_index(formats->keys, i));
  }

  g_autoptr(GPtrArray) linux_formats =
      otz_package_format_choices(manifest, "linux", "x64");
  const OtzJson *defaults = otz_json_get(expected, "defaultPackageFormat");
  g_assert_cmpuint(defaults->keys->len, >, 0);
  for (guint i = 0; i < defaults->keys->len; i++) {
    const char *key = g_ptr_array_index(defaults->keys, i);
    gboolean known;
    const char *sample = os_release_sample(key, &known);
    if (!known) g_test_message("os-release sample '%s' missing from the test", key);
    g_assert_true(known);
    g_autofree char *actual = otz_default_package_format(sample, linux_formats);
    g_assert_cmpstr(actual, ==,
                    ((const OtzJson *)g_ptr_array_index(defaults->items, i))->string);
  }

  const OtzJson *targets = otz_json_get(expected, "targets");
  g_assert_cmpuint(otz_json_array_length(targets), >, 0);
  for (guint t = 0; t < otz_json_array_length(targets); t++) {
    const OtzJson *entry = otz_json_array_get(targets, t);
    const OtzJson *target_json = otz_json_get(entry, "target");
    OtzTarget target = {otz_json_get_string(target_json, "platform"),
                        otz_json_get_string(target_json, "architecture"),
                        otz_json_get_string(target_json, "packageFormat")};
    g_autofree char *label = g_strdup_printf(
        "%s/%s/%s", target.platform, target.architecture, target.package_format);
    g_test_message("target %s", label);

    g_autoptr(GPtrArray) offered = g_ptr_array_new();
    for (guint i = 0; i < manifest->components->len; i++) {
      const OtzComponent *component = g_ptr_array_index(manifest->components, i);
      if (otz_component_is_offered(manifest, component, &target))
        g_ptr_array_add(offered, component->id);
    }
    assert_strings(offered, otz_json_get(entry, "offeredComponents"), label);

    g_autoptr(GPtrArray) custom = otz_custom_choices(manifest, &target);
    const OtzJson *expected_custom = otz_json_get(entry, "customChoices");
    g_assert_cmpuint(custom->len, ==, otz_json_array_length(expected_custom));
    for (guint c = 0; c < custom->len; c++) {
      const OtzCustomChoice *choice = g_ptr_array_index(custom, c);
      const OtzJson *want = otz_json_array_get(expected_custom, c);
      gint64 size = -1;
      g_assert_cmpstr(choice->component->id, ==, otz_json_get_string(want, "id"));
      g_assert_true(otz_json_get_int(want, "downloadSize", &size));
      g_assert_cmpint(otz_custom_choice_size(manifest, choice->component, &target), ==, size);
      const OtzJson *locked = otz_json_get(want, "locked");
      g_assert_nonnull(locked);
      g_assert_cmpint(choice->locked, ==, locked->boolean);
      g_assert_cmpstr(choice->group, ==, otz_json_get_string(want, "group"));
    }

    g_autoptr(GPtrArray) presets = otz_build_presets(manifest, &target);
    const OtzJson *expected_presets = otz_json_get(entry, "presets");
    g_assert_cmpuint(presets->len, ==, otz_json_array_length(expected_presets));
    for (guint p = 0; p < presets->len; p++) {
      const OtzPreset *preset = g_ptr_array_index(presets, p);
      const OtzJson *want = otz_json_array_get(expected_presets, p);
      g_assert_cmpstr(preset->id, ==, otz_json_get_string(want, "id"));
      assert_strings(preset->members, otz_json_get(want, "members"), preset->id);

      g_autoptr(GPtrArray) members = json_strings(otz_json_get(want, "members"));
      g_autoptr(GPtrArray) files =
          otz_planned_output_files(manifest, members, &target);
      assert_strings(files, otz_json_get(want, "outputFiles"), "outputFiles");
      g_autofree char *subfolder =
          otz_planned_output_subfolder(files, target.platform);
      g_assert_cmpstr(subfolder, ==, otz_json_get_string(want, "outputSubfolder"));
      g_autoptr(GPtrArray) notes = otz_planned_output_notes(manifest, members);
      assert_strings(notes, otz_json_get(want, "outputNotes"), "outputNotes");
    }
  }
}

static void test_fixtures(void) {
  check_fixtures("release-manifest.json", "expected-selections.json");
}

/* The Windows FULL installer reached 4 GiB: it cannot run, so "full" falls
 * back to the regular installer and the library parts it reads. */
static void test_fixtures_large_full(void) {
  check_fixtures("release-manifest-large-full.json",
                 "expected-selections-large-full.json");
}

/* The index picked on its own in the custom list comes with the library it
 * depends on and the installer that reads both, on x64 and on ARM64. */
static void test_library_brings_its_installer(void) {
  gsize length;
  g_autofree char *text = read_fixture("release-manifest.json", &length);
  g_autoptr(GError) error = NULL;
  g_autoptr(OtzManifest) manifest = otz_manifest_parse(text, length, &error);
  g_assert_no_error(error);
  g_autoptr(GPtrArray) picked = g_ptr_array_new();
  g_ptr_array_add(picked, (gpointer) "library-index");
  OtzTarget x64 = {"windows", "x64", ""};
  g_autoptr(GPtrArray) closed = otz_with_dependencies(manifest, picked, &x64);
  g_assert_cmpuint(closed->len, ==, 3);
  g_assert_cmpstr(g_ptr_array_index(closed, 0), ==, "otzaria-windows-x64");
  g_assert_cmpstr(g_ptr_array_index(closed, 1), ==, "library-full");
  g_assert_cmpstr(g_ptr_array_index(closed, 2), ==, "library-index");
  OtzTarget arm64 = {"windows", "arm64", ""};
  g_autoptr(GPtrArray) closed_arm =
      otz_with_dependencies(manifest, picked, &arm64);
  g_assert_cmpuint(closed_arm->len, ==, 3);
  g_assert_cmpstr(g_ptr_array_index(closed_arm, 0), ==, "otzaria-windows-arm64");
  OtzTarget deb = {"linux", "x64", "deb"};
  g_assert_false(otz_component_is_offered(
      manifest, otz_manifest_find(manifest, "library-full"), &deb));
}

#define TEST_ASSET(name)                                                     \
  "\"assets\":[{\"kind\":\"single\",\"repository\":\"Otzaria/otzaria\","     \
  "\"releaseTag\":\"1\",\"name\":\"" name "\",\"size\":1,\"sha256\":"         \
  "\"0000000000000000000000000000000000000000000000000000000000000000\"}]"

/* "any" is a wildcard for packageFormat exactly as for platform/architecture,
 * and is never offered as a format choice. */
static void test_package_format_any(void) {
  const char *text =
      "{\"schemaVersion\":1,\"components\":["
      "{\"id\":\"deb\",\"name\":\"n\",\"type\":\"application\",\"platform\":\"linux\","
      "\"architecture\":\"x64\",\"packageFormat\":\"deb\"," TEST_ASSET("a.deb") "},"
      "{\"id\":\"any\",\"name\":\"n\",\"type\":\"application\",\"platform\":\"linux\","
      "\"architecture\":\"x64\",\"packageFormat\":\"any\"," TEST_ASSET("b.bin") "}]}";
  g_autoptr(GError) error = NULL;
  g_autoptr(OtzManifest) manifest = otz_manifest_parse(text, strlen(text), &error);
  g_assert_no_error(error);
  const OtzComponent *any = otz_manifest_find(manifest, "any");
  const OtzComponent *deb = otz_manifest_find(manifest, "deb");
  for (gsize i = 0; i < 3; i++) {
    const char *formats[] = {"deb", "rpm", OTZ_PORTABLE_PACKAGE_FORMAT};
    OtzTarget target = {"linux", "x64", formats[i]};
    g_assert_true(otz_component_fits_target(any, &target));
    g_assert_cmpint(otz_component_fits_target(deb, &target), ==, i == 0);
  }
  g_autoptr(GPtrArray) choices = otz_package_format_choices(manifest, "linux", "x64");
  g_assert_cmpuint(choices->len, ==, 2);
  g_assert_cmpstr(g_ptr_array_index(choices, 0), ==, "deb");
  g_assert_cmpstr(g_ptr_array_index(choices, 1), ==, OTZ_PORTABLE_PACKAGE_FORMAT);
}

static void assert_preset(GPtrArray *presets, guint index, const char *id,
                          const char *const *members) {
  g_assert_cmpuint(index, <, presets->len);
  const OtzPreset *preset = g_ptr_array_index(presets, index);
  g_assert_cmpstr(preset->id, ==, id);
  guint count = 0;
  while (members[count] != NULL) count++;
  g_assert_cmpuint(preset->members->len, ==, count);
  for (guint i = 0; i < count; i++)
    g_assert_cmpstr(g_ptr_array_index(preset->members, i), ==, members[i]);
}

/* "full-indexed" is the bundle that installs a library, with that library;
 * both full presets carry the smart-search data. Shown basic, full-indexed,
 * full, update; pre-selected basic, else full, else the first. */
static void test_full_indexed_preset(void) {
  const char *text =
      "{\"schemaVersion\":1,\"components\":["
      "{\"id\":\"app\",\"name\":\"n\",\"type\":\"application\",\"platform\":\"windows\","
      TEST_ASSET("app.exe") "},"
      "{\"id\":\"runtime\",\"name\":\"n\",\"type\":\"dependency\",\"required\":true,"
      "\"platform\":\"windows\"," TEST_ASSET("runtime.bin") "},"
      "{\"id\":\"full\",\"name\":\"n\",\"type\":\"application-bundle\",\"downloadSize\":9,"
      "\"platform\":\"windows\"," TEST_ASSET("full.exe") "},"
      "{\"id\":\"indexed\",\"name\":\"n\",\"type\":\"application-bundle\",\"downloadSize\":1,"
      "\"platform\":\"windows\"," TEST_ASSET("indexed.exe") "},"
      "{\"id\":\"lib\",\"name\":\"n\",\"type\":\"library\",\"platform\":\"windows\","
      "\"installedBy\":[\"indexed\"]," TEST_ASSET("lib.bin") "},"
      "{\"id\":\"model\",\"name\":\"n\",\"type\":\"semantic-model\",\"platform\":\"windows\","
      TEST_ASSET("model.bin") "},"
      "{\"id\":\"vectors\",\"name\":\"n\",\"type\":\"semantic-vectors\",\"platform\":\"windows\","
      "\"dependsOn\":[\"model\"]," TEST_ASSET("vectors.bin") "}]}";
  g_autoptr(GError) error = NULL;
  g_autoptr(OtzManifest) manifest = otz_manifest_parse(text, strlen(text), &error);
  g_assert_no_error(error);
  OtzTarget x64 = {"windows", "x64", ""};
  g_autoptr(GPtrArray) presets = otz_build_presets(manifest, &x64);
  g_assert_cmpuint(presets->len, ==, 4);
  assert_preset(presets, 0, "basic", (const char *const[]){"app", "runtime", NULL});
  assert_preset(presets, 1, "full-indexed",
                (const char *const[]){"indexed", "lib", "model", "vectors", NULL});
  assert_preset(presets, 2, "full",
                (const char *const[]){"full", "model", "vectors", NULL});
  assert_preset(presets, 3, "update", (const char *const[]){"app", NULL});

  g_assert_cmpint(otz_default_preset_index(presets), ==, 0);
  g_ptr_array_remove_index(presets, 0); /* basic */
  g_assert_cmpint(otz_default_preset_index(presets), ==, 1); /* not full-indexed */
  g_ptr_array_remove_index(presets, 1); /* full */
  g_assert_cmpint(otz_default_preset_index(presets), ==, 0);
  g_ptr_array_set_size(presets, 0);
  g_assert_cmpint(otz_default_preset_index(presets), ==, -1);

  /* Android has no bundle: the APK comes with the library and the index. */
  gsize length;
  g_autofree char *fixture = read_fixture("release-manifest.json", &length);
  g_autoptr(OtzManifest) release = otz_manifest_parse(fixture, length, &error);
  g_assert_no_error(error);
  OtzTarget android = {"android", "", ""};
  g_autoptr(GPtrArray) mobile = otz_build_presets(release, &android);
  g_assert_cmpuint(mobile->len, ==, 3);
  g_assert_cmpstr(((const OtzPreset *)g_ptr_array_index(mobile, 0))->id, ==,
                  OTZ_DEFAULT_PRESET_ID);
  assert_preset(mobile, 1, "full-indexed",
                (const char *const[]){"otzaria-android", "library-full",
                                      "library-index", NULL});
  assert_preset(mobile, 2, "full",
                (const char *const[]){"otzaria-android", "library-full", NULL});
  OtzTarget portable = {"linux", "x64", OTZ_PORTABLE_PACKAGE_FORMAT};
  g_autoptr(GPtrArray) offline = otz_build_presets(release, &portable);
  g_assert_cmpuint(offline->len, ==, 1);
  g_assert_cmpint(otz_default_preset_index(offline), ==, 0);
}

static void test_manifest_rejects(void) {
  static const char *const bad[] = {
      /* schema version from the future */
      "{\"schemaVersion\":2,\"components\":[]}",
      /* repository outside the organization */
      "{\"schemaVersion\":1,\"components\":[{\"id\":\"a\",\"name\":\"n\","
      "\"assets\":[{\"kind\":\"single\",\"repository\":\"Evil/otzaria\","
      "\"releaseTag\":\"1\",\"name\":\"f\",\"size\":1,\"sha256\":"
      "\"0000000000000000000000000000000000000000000000000000000000000000\"}]}]}",
      /* no sha256 */
      "{\"schemaVersion\":1,\"components\":[{\"id\":\"a\",\"name\":\"n\","
      "\"assets\":[{\"kind\":\"single\",\"repository\":\"Otzaria/otzaria\","
      "\"releaseTag\":\"1\",\"name\":\"f\",\"size\":1}]}]}",
      /* path traversal in the name */
      "{\"schemaVersion\":1,\"components\":[{\"id\":\"a\",\"name\":\"n\","
      "\"assets\":[{\"kind\":\"single\",\"repository\":\"Otzaria/otzaria\","
      "\"releaseTag\":\"1\",\"name\":\"..\",\"size\":1,\"sha256\":"
      "\"0000000000000000000000000000000000000000000000000000000000000000\"}]}]}",
      /* outputFolder that leaves the output folder */
      "{\"schemaVersion\":1,\"components\":[{\"id\":\"a\",\"name\":\"n\","
      "\"outputFolder\":\"semantic-import/../..\","
      "\"assets\":[{\"kind\":\"single\",\"repository\":\"Otzaria/otzaria\","
      "\"releaseTag\":\"1\",\"name\":\"f\",\"size\":1,\"sha256\":"
      "\"0000000000000000000000000000000000000000000000000000000000000000\"}]}]}",
      /* dependsOn on a missing component */
      "{\"schemaVersion\":1,\"components\":[{\"id\":\"a\",\"name\":\"n\","
      "\"dependsOn\":[\"zz\"],"
      "\"assets\":[{\"kind\":\"single\",\"repository\":\"Otzaria/otzaria\","
      "\"releaseTag\":\"1\",\"name\":\"f\",\"size\":1,\"sha256\":"
      "\"0000000000000000000000000000000000000000000000000000000000000000\"}]}]}",
  };
  for (gsize i = 0; i < G_N_ELEMENTS(bad); i++) {
    g_autoptr(GError) error = NULL;
    g_autoptr(OtzManifest) manifest =
        otz_manifest_parse(bad[i], strlen(bad[i]), &error);
    g_assert_null(manifest);
    g_assert_error(error, OTZ_ERROR, OTZ_ERROR_PARSE);
  }
}

/* ------------------------------------------------------------- JSON */

static void test_json_hebrew_escapes(void) {
  const char *text =
      "{\"name\":\"\\u05d0\\u05d5\\u05e6\\u05e8\\u05d9\\u05d0 \\u05dc-Windows\","
      "\"raw\":\"אוצריא\",\"emoji\":\"\\ud83d\\ude00\",\"esc\":\"a\\\"b\\\\c\\/d\\n\"}";
  g_autoptr(GError) error = NULL;
  g_autoptr(OtzJson) json = otz_json_parse(text, strlen(text), &error);
  g_assert_no_error(error);
  g_assert_cmpstr(otz_json_get_string(json, "name"), ==, "אוצריא ל-Windows");
  g_assert_cmpstr(otz_json_get_string(json, "raw"), ==, "אוצריא");
  g_assert_cmpstr(otz_json_get_string(json, "emoji"), ==, "\xF0\x9F\x98\x80");
  g_assert_cmpstr(otz_json_get_string(json, "esc"), ==, "a\"b\\c/d\n");
}

static void test_json_values(void) {
  const char *text =
      " {\"big\": 4200000000, \"neg\": -3, \"f\": 1.5e2, \"t\": true, \"n\": null,"
      " \"arr\": [1, [2, {}], \"x\"], \"dup\": 1, \"dup\": 2} ";
  g_autoptr(GError) error = NULL;
  g_autoptr(OtzJson) json = otz_json_parse(text, strlen(text), &error);
  g_assert_no_error(error);
  gint64 value;
  g_assert_true(otz_json_get_int(json, "big", &value));
  g_assert_cmpint(value, ==, G_GINT64_CONSTANT(4200000000));
  g_assert_true(otz_json_get_int(json, "neg", &value));
  g_assert_cmpint(value, ==, -3);
  g_assert_false(otz_json_get_int(json, "f", &value));
  g_assert_cmpfloat(otz_json_get(json, "f")->number, ==, 150.0);
  g_assert_true(otz_json_get(json, "t")->boolean);
  g_assert_cmpint(otz_json_get(json, "n")->type, ==, OTZ_JSON_NULL);
  g_assert_cmpuint(otz_json_array_length(otz_json_get(json, "arr")), ==, 3);
  g_assert_true(otz_json_get_int(json, "dup", &value));
  g_assert_cmpint(value, ==, 2);
}

static void test_json_rejects(void) {
  static const char *const bad[] = {
      "{\"a\":\"\\ud83d\"}",   /* lone high surrogate */
      "{\"a\":\"\\ude00\"}",   /* lone low surrogate */
      "{\"a\":\"\\u0000\"}",   /* NUL */
      "{\"a\":\"x\ty\"}",      /* raw control character */
      "{\"a\":1} x",           /* trailing data */
      "{\"a\":01}",            /* leading zero */
      "{\"a\":\"\xC3\x28\"}",  /* invalid UTF-8 */
      "{\"a\":[1,]}",          /* trailing comma */
      "{\"a\" 1}",             /* missing colon */
      "\"unterminated",
  };
  for (gsize i = 0; i < G_N_ELEMENTS(bad); i++) {
    g_autoptr(GError) error = NULL;
    g_autoptr(OtzJson) json = otz_json_parse(bad[i], strlen(bad[i]), &error);
    g_assert_null(json);
    g_assert_error(error, OTZ_ERROR, OTZ_ERROR_PARSE);
  }
  GString *deep = g_string_new(NULL);
  for (int i = 0; i < 200; i++) g_string_append_c(deep, '[');
  for (int i = 0; i < 200; i++) g_string_append_c(deep, ']');
  g_autoptr(GError) error = NULL;
  g_autoptr(OtzJson) json = otz_json_parse(deep->str, deep->len, &error);
  g_assert_null(json);
  g_string_free(deep, TRUE);
}

/* ------------------------------------------------------------- HTTP */

typedef struct {
  GDataInputStream *in;
  OtzHttpHead head;
  OtzHttpBody body;
} Reply;

static gboolean open_reply(Reply *reply, const char *raw, GError **error) {
  GInputStream *memory = g_memory_input_stream_new_from_data(
      g_memdup2(raw, strlen(raw)), strlen(raw), g_free);
  reply->in = g_data_input_stream_new(memory);
  g_object_unref(memory);
  g_data_input_stream_set_newline_type(reply->in, G_DATA_STREAM_NEWLINE_TYPE_LF);
  reply->head.content_length = -1;
  if (!otz_http_read_head(reply->in, &reply->head, NULL, error)) return FALSE;
  otz_http_body_init(&reply->body, reply->in, &reply->head);
  return TRUE;
}

static char *read_body(Reply *reply, GError **error) {
  GString *out = g_string_new(NULL);
  char buffer[3]; /* tiny on purpose: chunk and buffer edges cross */
  for (;;) {
    gssize n = otz_http_body_read(&reply->body, buffer, sizeof buffer, NULL, error);
    if (n < 0) {
      g_string_free(out, TRUE);
      return NULL;
    }
    if (n == 0) return g_string_free(out, FALSE);
    g_string_append_len(out, buffer, n);
  }
}

static void close_reply(Reply *reply) {
  otz_http_head_clear(&reply->head);
  g_clear_object(&reply->in);
}

static void test_http_content_length(void) {
  Reply reply = {0};
  g_autoptr(GError) error = NULL;
  g_assert_true(open_reply(&reply,
                           "HTTP/1.1 100 Continue\r\n\r\n"
                           "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n"
                           "X-Other: y\r\n\r\nhello world", &error));
  g_assert_cmpuint(reply.head.status, ==, 200);
  g_assert_cmpint(reply.head.content_length, ==, 11);
  g_autofree char *body = read_body(&reply, &error);
  g_assert_no_error(error);
  g_assert_cmpstr(body, ==, "hello world");
  close_reply(&reply);
}

static void test_http_chunked(void) {
  Reply reply = {0};
  g_autoptr(GError) error = NULL;
  g_assert_true(open_reply(&reply,
                           "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
                           "5;ext=1\r\nhello\r\n6\r\n world\r\nA\r\n0123456789\r\n"
                           "0\r\nX-Trailer: a\r\n\r\n", &error));
  g_assert_true(reply.head.chunked);
  g_autofree char *body = read_body(&reply, &error);
  g_assert_no_error(error);
  g_assert_cmpstr(body, ==, "hello world0123456789");
  close_reply(&reply);
}

static void test_http_truncated(void) {
  Reply reply = {0};
  g_autoptr(GError) error = NULL;
  g_assert_true(open_reply(
      &reply, "HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\nshort", &error));
  g_autofree char *body = read_body(&reply, &error);
  g_assert_null(body);
  g_assert_error(error, OTZ_ERROR, OTZ_ERROR_NETWORK);
  g_assert_true(otz_error_is_retryable(error));
  close_reply(&reply);

  Reply chunked = {0};
  g_clear_error(&error);
  g_assert_true(open_reply(
      &chunked, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nA\r\nabc", &error));
  g_autofree char *partial = read_body(&chunked, &error);
  g_assert_null(partial);
  g_assert_error(error, OTZ_ERROR, OTZ_ERROR_NETWORK);
  close_reply(&chunked);
}

static void test_http_malformed(void) {
  static const char *const bad[] = {
      "HTTP/2 200\r\n\r\n",
      "HTTP/1.1 20 OK\r\n\r\n",
      "HTTP/1.1 200 OK\r\nContent-Length: 12x\r\n\r\n",
      "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\n",
      "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\n",
      "HTTP/1.1 200 OK\r\nno colon here\r\n\r\n",
  };
  for (gsize i = 0; i < G_N_ELEMENTS(bad); i++) {
    Reply reply = {0};
    g_autoptr(GError) error = NULL;
    g_assert_false(open_reply(&reply, bad[i], &error));
    g_assert_error(error, OTZ_ERROR, OTZ_ERROR_PROTOCOL);
    close_reply(&reply);
  }
}

static void test_http_range_replies(void) {
  Reply reply = {0};
  g_autoptr(GError) error = NULL;
  g_assert_true(open_reply(&reply,
                           "HTTP/1.1 206 Partial Content\r\n"
                           "Content-Range: bytes 100-199/200\r\n"
                           "Content-Length: 100\r\n\r\n", &error));
  gint64 start, end, total;
  g_assert_true(otz_http_parse_content_range(reply.head.content_range, &start, &end,
                                             &total));
  g_assert_cmpint(start, ==, 100);
  g_assert_cmpint(end, ==, 199);
  g_assert_cmpint(total, ==, 200);
  g_assert_cmpint(otz_classify_range_reply(reply.head.status, reply.head.content_range,
                                           reply.head.content_length, 100, 200),
                  ==, OTZ_RANGE_CONTINUE);
  close_reply(&reply);

  /* The filtered network answers a Range request with 200 and the whole file:
   * that body is written from 0 — no second request. */
  g_assert_cmpint(otz_classify_range_reply(200, NULL, 200, 100, 200), ==,
                  OTZ_RANGE_REWRITE);
  g_assert_cmpint(otz_classify_range_reply(200, NULL, -1, 0, 200), ==,
                  OTZ_RANGE_REWRITE);
  /* 206 for another range, another total, or a wrong length is not ours. */
  g_assert_cmpint(otz_classify_range_reply(206, "bytes 0-199/200", -1, 100, 200), ==,
                  OTZ_RANGE_DISCARD);
  g_assert_cmpint(otz_classify_range_reply(206, "bytes 100-199/300", -1, 100, 200),
                  ==, OTZ_RANGE_DISCARD);
  g_assert_cmpint(otz_classify_range_reply(206, "bytes 100-199/200", 50, 100, 200),
                  ==, OTZ_RANGE_DISCARD);
  g_assert_cmpint(otz_classify_range_reply(206, NULL, -1, 100, 200), ==,
                  OTZ_RANGE_DISCARD);
  g_assert_cmpint(otz_classify_range_reply(416, NULL, -1, 100, 200), ==,
                  OTZ_RANGE_DISCARD);
  g_assert_cmpint(otz_classify_range_reply(206, "bytes 0-199/200", -1, 0, 200), ==,
                  OTZ_RANGE_FAIL);
  g_assert_cmpint(otz_classify_range_reply(404, NULL, -1, 100, 200), ==,
                  OTZ_RANGE_FAIL);

  g_assert_false(otz_http_parse_content_range("bytes */200", &start, &end, &total));
  g_assert_false(otz_http_parse_content_range("bytes 0-9/*", &start, &end, &total));
  g_assert_false(otz_http_parse_content_range("bytes 9-0/20", &start, &end, &total));
  g_assert_false(otz_http_parse_content_range("items 0-9/20", &start, &end, &total));
}

static void test_url_hosts(void) {
  static const char *const allowed[] = {
      "https://github.com/Otzaria/otzaria/releases/download/0.10.3+143/a.deb",
      "https://api.github.com/repos/Otzaria/otzaria/releases/latest",
      "https://release-assets.githubusercontent.com/github-production-release-asset/1?sig=a%2Bb",
      "https://objects.githubusercontent.com/github-production-release-asset-2e65be/1",
      "https://GitHub.com:443/Otzaria/SeforimLibrary/releases/download/v27/x",
  };
  static const char *const blocked[] = {
      "http://github.com/Otzaria/otzaria/releases/download/1/a",
      "https://github.com/evil/otzaria/releases/download/1/a",
      "https://github.com/OtzariaEvil/otzaria/releases/download/1/a",
      "https://github.com.evil.com/Otzaria/otzaria",
      "https://evil.com/Otzaria/otzaria",
      "https://github.com:8443/Otzaria/otzaria",
      "https://user@github.com/Otzaria/otzaria",
      "https://raw.githubusercontent.com/Otzaria/otzaria/main/x",
      "ftp://github.com/Otzaria/otzaria",
  };
  for (gsize i = 0; i < G_N_ELEMENTS(allowed); i++) {
    g_autoptr(GError) error = NULL;
    if (!otz_http_check_url(allowed[i], &error)) g_test_message("%s", allowed[i]);
    g_assert_no_error(error);
  }
  for (gsize i = 0; i < G_N_ELEMENTS(blocked); i++) {
    g_autoptr(GError) error = NULL;
    if (otz_http_check_url(blocked[i], &error)) g_test_message("%s", blocked[i]);
    g_assert_error(error, OTZ_ERROR, OTZ_ERROR_BLOCKED);
  }
}

/* ------------------------------------------------------------- cache */

static void test_marker(void) {
  g_autofree char *dir = temp_dir();
  g_autofree char *file = g_build_filename(dir, "otzaria-1.deb", NULL);
  const char *sha = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824";
  write_file(file, "hello", 5);
  g_autoptr(GError) error = NULL;
  g_assert_true(otz_marker_write(file, sha, &error));

  g_autofree char *marker = g_strconcat(file, ".sha256", NULL);
  g_autofree char *content = NULL;
  g_assert_true(g_file_get_contents(marker, &content, NULL, NULL));
  g_autofree char *wanted = g_strdup_printf("%s  otzaria-1.deb\n", sha);
  g_assert_cmpstr(content, ==, wanted);

  g_assert_true(otz_marker_matches(file, sha, 5));
  g_assert_false(otz_marker_matches(file, sha, 6));
  g_assert_false(otz_marker_matches(
      file, "0000000000000000000000000000000000000000000000000000000000000000", 5));

  /* A file modified after its marker was written is not trusted. */
  struct timespec times[2] = {{0, UTIME_OMIT}, {0, 0}};
  struct stat st;
  g_assert_cmpint(stat(marker, &st), ==, 0);
  times[1].tv_sec = st.st_mtim.tv_sec + 10;
  g_assert_cmpint(utimensat(AT_FDCWD, file, times, 0), ==, 0);
  g_assert_false(otz_marker_matches(file, sha, 5));

  g_unlink(marker);
  g_assert_false(otz_marker_matches(file, sha, 5));
  g_unlink(file);
  g_rmdir(dir);
}

typedef struct {
  gboolean verifying;
  gint64 verified;
} AssemblyProgress;

static void mark_verifying(gpointer data) {
  ((AssemblyProgress *)data)->verifying = TRUE;
}

static void count_verification(gint64 bytes, gpointer data) {
  AssemblyProgress *progress = data;
  if (progress->verifying) progress->verified += bytes;
}

static void test_assembly(void) {
  g_autofree char *dir = temp_dir();
  const char *chunks[] = {"first-part-", "second-part-", "third"};
  gint64 sizes[3];
  g_autoptr(GPtrArray) paths = g_ptr_array_new_with_free_func(g_free);
  for (int i = 0; i < 3; i++) {
    char *path = g_strdup_printf("%s/archive.tar.zst.part-%03d", dir, i);
    write_file(path, chunks[i], -1);
    g_autofree char *marker = g_strconcat(path, ".sha256", NULL);
    write_file(marker, "x", -1);
    sizes[i] = (gint64)strlen(chunks[i]);
    g_ptr_array_add(paths, path);
  }
  gint64 total = sizes[0] + sizes[1] + sizes[2];
  g_autofree char *whole_sha = g_compute_checksum_for_string(
      G_CHECKSUM_SHA256, "first-part-second-part-third", -1);
  g_autofree char *dest = g_build_filename(dir, "archive.tar.zst", NULL);
  g_autofree char *tmp = g_strconcat(dest, ".partial", NULL);

  /* A previous run joined part 0, deleted it, and died midway through part 1. */
  write_file(tmp, "first-part-seco", -1);
  g_autofree char *marker0 = g_strconcat(g_ptr_array_index(paths, 0), ".sha256", NULL);
  g_unlink(g_ptr_array_index(paths, 0));
  g_unlink(marker0);
  gint64 offset;
  guint first = otz_assembled_parts(sizes, 3, 15, &offset);
  g_assert_cmpuint(first, ==, 1);
  g_assert_cmpint(offset, ==, sizes[0]);

  g_autoptr(GError) error = NULL;
  AssemblyProgress verification = {0};
  g_assert_true(otz_assemble(tmp, dest, paths, sizes, first, total, whole_sha,
                             count_verification, &verification, NULL, mark_verifying,
                             NULL, &error));
  g_assert_true(verification.verifying);
  g_assert_cmpint(verification.verified, ==, total);
  g_assert_no_error(error);
  g_autofree char *content = NULL;
  g_assert_true(g_file_get_contents(dest, &content, NULL, NULL));
  g_assert_cmpstr(content, ==, "first-part-second-part-third");
  g_assert_false(g_file_test(tmp, G_FILE_TEST_EXISTS));
  for (int i = 0; i < 3; i++) {
    g_autofree char *marker = g_strconcat(g_ptr_array_index(paths, i), ".sha256", NULL);
    g_assert_false(g_file_test(g_ptr_array_index(paths, i), G_FILE_TEST_EXISTS));
    g_assert_false(g_file_test(marker, G_FILE_TEST_EXISTS));
  }
  g_unlink(dest);

  /* A part shorter than the manifest says fails the byte count. */
  write_file(g_ptr_array_index(paths, 0), "short", -1);
  gint64 wrong[1] = {50};
  g_autoptr(GPtrArray) one = g_ptr_array_new();
  g_ptr_array_add(one, g_ptr_array_index(paths, 0));
  g_clear_error(&error);
  g_assert_false(otz_assemble(tmp, dest, one, wrong, 0, 50, whole_sha,
                              NULL, NULL, NULL, NULL, NULL,
                              &error));
  g_assert_error(error, OTZ_ERROR, OTZ_ERROR_IO);
  g_assert_false(g_file_test(dest, G_FILE_TEST_EXISTS));
  g_unlink(tmp);
  g_unlink(g_ptr_array_index(paths, 0));

  /* A resumed prefix with the right length but wrong bytes must not be published. */
  write_file(tmp, "Xirst-part-", -1);
  write_file(g_ptr_array_index(paths, 1), chunks[1], -1);
  write_file(g_ptr_array_index(paths, 2), chunks[2], -1);
  g_clear_error(&error);
  g_assert_false(otz_assemble(tmp, dest, paths, sizes, 1, total, whole_sha,
                              NULL, NULL, NULL, NULL, NULL, &error));
  g_assert_error(error, OTZ_ERROR, OTZ_ERROR_CORRUPT);
  g_assert_false(g_file_test(dest, G_FILE_TEST_EXISTS));
  g_assert_false(g_file_test(tmp, G_FILE_TEST_EXISTS));
  g_unlink(g_ptr_array_index(paths, 1));
  g_unlink(g_ptr_array_index(paths, 2));
  g_rmdir(dir);
}

static void count_bytes(gint64 delta, gpointer data) { *(gint64 *)data += delta; }

static void test_place_file(void) {
  g_autofree char *dir = temp_dir();
  g_autofree char *src = g_build_filename(dir, "cache.bin", NULL);
  g_autofree char *dest = g_build_filename(dir, "out.bin", NULL);
  write_file(src, "payload", -1);
  write_file(dest, "old", -1);
  gint64 counted = 0;
  g_autoptr(GError) error = NULL;
  g_assert_true(otz_place_file(src, dest, 7, count_bytes, &counted, NULL, &error));
  g_assert_cmpint(counted, ==, 7);
  struct stat a, b;
  g_assert_cmpint(stat(src, &a), ==, 0);
  g_assert_cmpint(stat(dest, &b), ==, 0);
  g_assert_cmpuint(a.st_ino, ==, b.st_ino);
  /* Placing it again onto itself is a no-op, not a self-unlink. */
  g_assert_true(otz_place_file(src, dest, 7, NULL, NULL, NULL, &error));
  g_assert_true(g_file_test(src, G_FILE_TEST_EXISTS));
  g_unlink(src);
  g_unlink(dest);
  g_rmdir(dir);
}

/* ------------------------------------------------------------- misc */

static void test_release_tag(void) {
  g_assert_cmpint(otz_compare_versions("0.10.4", "0.10.3+143"), ==, 1);
  g_assert_cmpint(otz_compare_versions("0.10.3", "0.10.3+143"), ==, 0);
  g_assert_cmpint(otz_compare_versions("v0.9.97", "0.10.0"), ==, -1);
  g_assert_cmpint(otz_compare_versions("0.10", "0.10.0"), ==, 0);
  g_autofree char *a = otz_pick_release_tag("0.10.3+143", "0.10.4");
  g_assert_cmpstr(a, ==, "0.10.4");
  g_autofree char *b = otz_pick_release_tag("0.10.3+143", "0.10.3");
  g_assert_cmpstr(b, ==, "0.10.3+143");
  g_autofree char *c = otz_pick_release_tag("0.10.3+143", NULL);
  g_assert_cmpstr(c, ==, "0.10.3+143");
  g_autofree char *d = otz_pick_release_tag("", "0.9.1");
  g_assert_cmpstr(d, ==, "0.9.1");
  g_autofree char *e = otz_pick_release_tag("0.10.3+143", "0.9.99");
  g_assert_cmpstr(e, ==, "0.10.3+143");
}

static void test_asset_url_and_sizes(void) {
  OtzAsset asset = {.repository = "Otzaria/otzaria", .release_tag = "0.10.3+143"};
  g_autofree char *url = otz_asset_url(&asset, "otzaria-0.10.3+143-linux.deb");
  g_assert_cmpstr(url, ==,
                  "https://github.com/Otzaria/otzaria/releases/download/0.10.3+143/"
                  "otzaria-0.10.3+143-linux.deb");
  g_assert_true(otz_http_check_url(url, NULL));
  g_autofree char *gb = otz_human_size(G_GINT64_CONSTANT(2012390081));
  g_assert_cmpstr(gb, ==, "1.8\xC2\xA0GB");
  g_autofree char *mb = otz_human_size(42127056);
  g_assert_cmpstr(mb, ==, "40\xC2\xA0MB");
  g_autofree char *kb = otz_human_size(1);
  g_assert_cmpstr(kb, ==, "1\xC2\xA0KB");
}

/* ------------------------------------------------------------- job */

#define HELLO_SHA "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
#define ONES_SHA "1111111111111111111111111111111111111111111111111111111111111111"
#define ZERO_SHA "0000000000000000000000000000000000000000000000000000000000000000"

/* Two single files (hello.bin is "hello") and one 8-byte split asset. */
static const char *job_manifest =
    "{\"schemaVersion\":1,\"components\":["
    "{\"id\":\"hello\",\"name\":\"n\",\"type\":\"application\",\"platform\":\"linux\","
    "\"assets\":[{\"kind\":\"single\",\"repository\":\"Otzaria/otzaria\","
    "\"releaseTag\":\"1\",\"name\":\"hello.bin\",\"size\":5,\"sha256\":\"" HELLO_SHA
    "\"}]},"
    "{\"id\":\"other\",\"name\":\"n\",\"type\":\"application\",\"platform\":\"linux\","
    "\"assets\":[{\"kind\":\"single\",\"repository\":\"Otzaria/otzaria\","
    "\"releaseTag\":\"1\",\"name\":\"other.bin\",\"size\":5,\"sha256\":\"" ZERO_SHA
    "\"}]},"
    "{\"id\":\"split\",\"name\":\"n\",\"type\":\"library\",\"platform\":\"linux\","
    "\"assets\":[{\"kind\":\"split\",\"repository\":\"Otzaria/otzaria\","
    "\"releaseTag\":\"1\",\"name\":\"lib.tar.zst\",\"size\":8,\"sha256\":\"" ONES_SHA
    "\",\"parts\":[{\"name\":\"lib.tar.zst.part-000\",\"size\":4,\"sha256\":\"" ZERO_SHA
    "\"},{\"name\":\"lib.tar.zst.part-001\",\"size\":4,\"sha256\":\"" ZERO_SHA
    "\"}]}]}]}";

typedef struct {
  char *root, *cache, *out;
  OtzManifest *manifest;
  GPtrArray *ids;
} JobFixture;

static void job_fixture_init(JobFixture *f, const char *const *ids) {
  f->root = temp_dir();
  f->cache = g_build_filename(f->root, "cache", NULL);
  f->out = g_build_filename(f->root, "out", NULL);
  g_mkdir_with_parents(f->cache, 0755);
  g_mkdir_with_parents(f->out, 0755);
  g_autoptr(GError) error = NULL;
  f->manifest = otz_manifest_parse(job_manifest, strlen(job_manifest), &error);
  g_assert_no_error(error);
  f->ids = g_ptr_array_new();
  for (gsize i = 0; ids[i] != NULL; i++) g_ptr_array_add(f->ids, (gpointer)ids[i]);
}

static OtzJob *job_fixture_job(JobFixture *f) {
  OtzTarget target = {"linux", "x64", ""};
  g_autoptr(GError) error = NULL;
  OtzJob *job =
      otz_job_new(f->manifest, f->ids, &target, f->cache, f->out, NULL, &error);
  g_assert_no_error(error);
  return job;
}

static void job_fixture_clear(JobFixture *f) {
  g_autofree char *command = g_strdup_printf("rm -rf '%s'", f->root);
  g_assert_cmpint(system(command), ==, 0);
  otz_manifest_free(f->manifest);
  g_ptr_array_unref(f->ids);
  g_free(f->root);
  g_free(f->cache);
  g_free(f->out);
  otz_set_allowed_owner("Otzaria");
}

/* A failing worker cancels its siblings; that must not read as "the user
 * stopped the download". The URLs are refused before any network access. */
static void test_job_failure_kind(void) {
  static const char *const ids[] = {"hello", "other", NULL};
  JobFixture f;
  job_fixture_init(&f, ids);
  otz_set_allowed_owner("SomeoneElse");
  g_autoptr(OtzJob) job = job_fixture_job(&f);
  g_autoptr(GCancellable) cancellable = g_cancellable_new();
  g_autoptr(GError) error = NULL;
  g_assert_false(otz_job_run(job, cancellable, &error));
  g_assert_error(error, OTZ_ERROR, OTZ_ERROR_BLOCKED);
  g_assert_cmpint(otz_job_failure(job), ==, OTZ_FAILURE_UNAVAILABLE);
  job_fixture_clear(&f);
}

/* A complete .download whose rename never happened is hashed once and
 * promoted, without the network; another version's leftover is removed. */
static void test_job_complete_download_promoted(void) {
  static const char *const ids[] = {"hello", NULL};
  JobFixture f;
  job_fixture_init(&f, ids);
  otz_set_allowed_owner("SomeoneElse");
  g_autofree char *good =
      g_build_filename(f.cache, "hello.bin.2cf24dba5fb0.download", NULL);
  write_file(good, "hello", 5);
  g_autofree char *stale =
      g_build_filename(f.cache, "hello.bin.abcdefabcdef.download", NULL);
  write_file(stale, "OLD", 3);

  g_autoptr(OtzJob) job = job_fixture_job(&f);
  g_autoptr(GError) error = NULL;
  g_assert_true(otz_job_run(job, NULL, &error));
  g_assert_no_error(error);
  g_autofree char *cached = g_build_filename(f.cache, "hello.bin", NULL);
  g_autofree char *placed = g_build_filename(f.out, "hello.bin", NULL);
  g_assert_true(otz_marker_matches(cached, HELLO_SHA, 5));
  g_assert_true(g_file_test(placed, G_FILE_TEST_EXISTS));
  g_assert_false(g_file_test(good, G_FILE_TEST_EXISTS));
  g_assert_false(g_file_test(stale, G_FILE_TEST_EXISTS));
  g_assert_cmpint(otz_job_downloaded_bytes(job), ==, 0);
  g_assert_cmpint(otz_job_hashed_bytes(job), ==, 5);
  OtzProgress progress;
  otz_job_get_progress(job, &progress);
  g_assert_cmpint(progress.download_done, ==, 5);
  g_assert_cmpint(progress.network_bytes, ==, 0);
  g_assert_cmpuint(progress.workers, ==, 0);
  g_assert_cmpuint(progress.waiting, ==, 0);
  otz_progress_clear(&progress);
  job_fixture_clear(&f);
}

/* A component with outputFolder lands in that folder inside the output, and
 * its outputNote reaches the finish page. */
static void test_job_output_folder(void) {
  static const char *manifest_json =
      "{\"schemaVersion\":1,\"components\":["
      "{\"id\":\"data\",\"name\":\"n\",\"type\":\"semantic-vectors\","
      "\"outputFolder\":\"semantic-import/vectors\",\"outputNote\":\"note\","
      "\"assets\":[{\"kind\":\"single\",\"repository\":\"Otzaria/SeforimLibrary\","
      "\"releaseTag\":\"vectors-v30\",\"name\":\"hello.bin\",\"size\":5,"
      "\"sha256\":\"" HELLO_SHA "\"}]}]}";
  g_autofree char *root = temp_dir();
  g_autofree char *cache = g_build_filename(root, "cache", NULL);
  g_autofree char *out = g_build_filename(root, "out", NULL);
  g_mkdir_with_parents(cache, 0755);
  g_autoptr(GError) error = NULL;
  g_autoptr(OtzManifest) manifest =
      otz_manifest_parse(manifest_json, strlen(manifest_json), &error);
  g_assert_no_error(error);
  otz_set_allowed_owner("SomeoneElse");
  g_autofree char *download =
      g_build_filename(cache, "hello.bin.2cf24dba5fb0.download", NULL);
  write_file(download, "hello", 5);
  g_autoptr(GPtrArray) ids = g_ptr_array_new();
  g_ptr_array_add(ids, (gpointer) "data");
  OtzTarget target = {"linux", "x64", "deb"};
  g_autoptr(OtzJob) job =
      otz_job_new(manifest, ids, &target, cache, out, NULL, &error);
  g_assert_no_error(error);
  g_assert_true(otz_job_run(job, NULL, &error));
  g_assert_no_error(error);

  g_autofree char *placed =
      g_build_filename(out, "semantic-import", "vectors", "hello.bin", NULL);
  g_assert_true(g_file_test(placed, G_FILE_TEST_EXISTS));
  GPtrArray *files = otz_job_output_files(job);
  g_assert_cmpuint(files->len, ==, 1);
  g_assert_cmpstr(g_ptr_array_index(files, 0), ==,
                  "semantic-import/vectors/hello.bin");
  g_assert_cmpstr(otz_job_output_dir(job), ==, out);
  GPtrArray *notes = otz_job_output_notes(job);
  g_assert_cmpuint(notes->len, ==, 1);
  g_assert_cmpstr(g_ptr_array_index(notes, 0), ==, "note");

  g_autofree char *command = g_strdup_printf("rm -rf '%s'", root);
  g_assert_cmpint(system(command), ==, 0);
  otz_set_allowed_owner("Otzaria");
}

/* A full-size .download with the wrong content is not promoted: it is hashed
 * once, dropped, and the download is attempted (refused here). */
static void test_job_complete_download_wrong(void) {
  static const char *const ids[] = {"other", NULL};
  JobFixture f;
  job_fixture_init(&f, ids);
  otz_set_allowed_owner("SomeoneElse");
  g_autofree char *wrong =
      g_build_filename(f.cache, "other.bin.000000000000.download", NULL);
  write_file(wrong, "wrong", 5);
  g_autoptr(OtzJob) job = job_fixture_job(&f);
  g_autoptr(GError) error = NULL;
  g_assert_false(otz_job_run(job, NULL, &error));
  g_assert_error(error, OTZ_ERROR, OTZ_ERROR_BLOCKED);
  g_assert_cmpint(otz_job_hashed_bytes(job), ==, 5);
  g_assert_cmpint(otz_job_failure(job), ==, OTZ_FAILURE_UNAVAILABLE);
  g_autofree char *cached = g_build_filename(f.cache, "other.bin", NULL);
  g_assert_false(g_file_test(cached, G_FILE_TEST_EXISTS));
  job_fixture_clear(&f);
}

/* The joined-file .partial carries the asset's sha256: an older version's
 * partial is neither resumed nor trusted. */
static void test_job_partial_bound_to_asset(void) {
  static const char *const ids[] = {"split", NULL};
  JobFixture f;
  job_fixture_init(&f, ids);
  gint64 cache_bytes, output_bytes;
  gboolean same;

  g_autofree char *stale =
      g_build_filename(f.out, "lib.tar.zst.222222222222.partial", NULL);
  write_file(stale, "OLD0", 4);
  OtzJob *job = job_fixture_job(&f);
  otz_job_space_needs(job, &cache_bytes, &output_bytes, &same);
  g_assert_cmpint(cache_bytes, ==, 8);
  g_assert_cmpint(output_bytes, ==, 8);
  otz_job_free(job);

  g_autofree char *current =
      g_build_filename(f.out, "lib.tar.zst.111111111111.partial", NULL);
  write_file(current, "abcd", 4);
  job = job_fixture_job(&f);
  otz_job_space_needs(job, &cache_bytes, &output_bytes, &same);
  g_assert_cmpint(cache_bytes, ==, 4);
  g_assert_cmpint(output_bytes, ==, 4);
  otz_job_free(job);
  job_fixture_clear(&f);
}

static void test_space_verdict(void) {
  static const char *const ids[] = {"hello", "other", NULL};
  JobFixture f;
  job_fixture_init(&f, ids);
  g_autoptr(OtzJob) job = job_fixture_job(&f);
  gint64 cache_bytes, output_bytes;
  gboolean same;
  otz_job_space_needs(job, &cache_bytes, &output_bytes, &same);
  g_assert_true(same);
  g_assert_cmpint(cache_bytes, ==, 10);
  g_assert_cmpint(output_bytes, ==, 0); /* hard links on one filesystem */
  job_fixture_clear(&f);

  g_assert_true(otz_space_is_enough(10, 5, TRUE, 15, 15));
  g_assert_false(otz_space_is_enough(10, 5, TRUE, 14, 1000));
  g_assert_true(otz_space_is_enough(10, 5, FALSE, 10, 5));
  g_assert_false(otz_space_is_enough(10, 5, FALSE, 1000, 4));
  g_assert_false(otz_space_is_enough(10, 5, FALSE, 9, 1000));
  g_assert_true(otz_space_is_enough(10, 5, FALSE, -1, -1));
}

static void test_api_fallback(void) {
  g_autofree char *url = otz_direct_manifest_url("0.10.3+143");
  g_assert_cmpstr(url, ==,
                  "https://github.com/Otzaria/otzaria/releases/download/"
                  "0.10.3%2B143/otzaria-release-manifest.json");
  g_assert_true(otz_http_check_url(url, NULL));
  g_autoptr(GError) limited =
      g_error_new_literal(OTZ_ERROR, OTZ_ERROR_RATE_LIMITED, "HTTP 403");
  g_autoptr(GError) missing = g_error_new_literal(OTZ_ERROR, OTZ_ERROR_HTTP, "404");
  g_autoptr(GError) network = g_error_new_literal(OTZ_ERROR, OTZ_ERROR_NETWORK, "offline");
  g_autoptr(GError) cancelled = g_error_new_literal(G_IO_ERROR, G_IO_ERROR_CANCELLED, "cancelled");
  g_assert_true(otz_api_failure_uses_direct_manifest(limited, "0.10.3+143"));
  g_assert_true(otz_api_failure_uses_direct_manifest(missing, "0.10.3+143"));
  g_assert_true(otz_api_failure_uses_direct_manifest(network, "0.10.3+143"));
  g_assert_false(otz_api_failure_uses_direct_manifest(limited, ""));
  g_assert_false(otz_api_failure_uses_direct_manifest(limited, "unsafe/tag"));
  g_assert_false(otz_api_failure_uses_direct_manifest(cancelled, "0.10.3+143"));
  g_assert_false(otz_api_failure_uses_direct_manifest(NULL, "0.10.3+143"));
}

static void test_http_long_header(void) {
  GString *raw = g_string_new("HTTP/1.1 200 OK\r\nX-Long: ");
  for (int i = 0; i < 9000; i++) g_string_append_c(raw, 'a');
  g_string_append(raw, "\r\n\r\n");
  Reply reply = {0};
  g_autoptr(GError) error = NULL;
  g_assert_false(open_reply(&reply, raw->str, &error));
  g_assert_error(error, OTZ_ERROR, OTZ_ERROR_PROTOCOL);
  close_reply(&reply);
  g_string_free(raw, TRUE);

  GString *ok = g_string_new("HTTP/1.1 200 OK\r\nX-Long: ");
  for (int i = 0; i < 7000; i++) g_string_append_c(ok, 'a');
  g_string_append(ok, "\r\nContent-Length: 2\r\n\r\nhi");
  Reply fine = {0};
  g_clear_error(&error);
  g_assert_true(open_reply(&fine, ok->str, &error));
  g_autofree char *body = read_body(&fine, &error);
  g_assert_cmpstr(body, ==, "hi");
  close_reply(&fine);
  g_string_free(ok, TRUE);
}

/* An English interface names the multi-file folder in English; Hebrew keeps
 * the contract's name. */
static void test_job_subfolder_name(void) {
  static const char *const ids[] = {"hello", "other", NULL};
  JobFixture f;
  job_fixture_init(&f, ids);
  OtzTarget target = {"linux", "x64", ""};
  g_autoptr(GError) error = NULL;
  g_autoptr(OtzJob) hebrew =
      otz_job_new(f.manifest, f.ids, &target, f.cache, f.out, NULL, &error);
  g_assert_no_error(error);
  g_autofree char *contract = g_build_filename(f.out, "אוצריא להתקנה ל-Linux", NULL);
  g_assert_cmpstr(otz_job_output_dir(hebrew), ==, contract);
  g_autoptr(OtzJob) english = otz_job_new(f.manifest, f.ids, &target, f.cache,
                                          f.out, "Otzaria setup for Linux", &error);
  g_assert_no_error(error);
  g_autofree char *named = g_build_filename(f.out, "Otzaria setup for Linux", NULL);
  g_assert_cmpstr(otz_job_output_dir(english), ==, named);

  static const char *const single_ids[] = {"hello", NULL};
  g_ptr_array_set_size(f.ids, 0);
  g_ptr_array_add(f.ids, (gpointer)single_ids[0]);
  g_autoptr(OtzJob) single = otz_job_new(f.manifest, f.ids, &target, f.cache,
                                         f.out, "Otzaria setup for Linux", &error);
  g_assert_no_error(error);
  g_assert_cmpstr(otz_job_output_dir(single), ==, f.out);
  job_fixture_clear(&f);
}

/* nameEn/descriptionEn/outputNoteEn, and the Hebrew when one is missing. */
static void test_manifest_english_text(void) {
  static const char *json =
      "{\"schemaVersion\":1,\"components\":["
      "{\"id\":\"a\",\"name\":\"א\",\"nameEn\":\"A\",\"description\":\"ב\","
      "\"outputNote\":\"ג\",\"outputNoteEn\":\"C\",\"type\":\"application\","
      "\"assets\":[{\"kind\":\"single\",\"repository\":\"Otzaria/otzaria\","
      "\"releaseTag\":\"1\",\"name\":\"hello.bin\",\"size\":5,\"sha256\":\"" HELLO_SHA
      "\"}]}]}";
  g_autoptr(GError) error = NULL;
  g_autoptr(OtzManifest) manifest = otz_manifest_parse(json, strlen(json), &error);
  g_assert_no_error(error);
  const OtzComponent *a = otz_manifest_find(manifest, "a");
  g_assert_cmpstr(otz_component_name(a, TRUE), ==, "A");
  g_assert_cmpstr(otz_component_name(a, FALSE), ==, "א");
  g_assert_cmpstr(otz_component_description(a, TRUE), ==, "ב");
  g_assert_cmpstr(otz_component_output_note(a, TRUE), ==, "C");
  g_autofree char *hebrew = otz_fallback_output_dir(FALSE);
  g_autofree char *english = otz_fallback_output_dir(TRUE);
  g_assert_true(g_str_has_suffix(hebrew, "/אוצריא-להתקנה"));
  g_assert_true(g_str_has_suffix(english, "/Otzaria setup"));
}

/* "No internet" is only a request that never reached a server. */
static void test_offline_errors(void) {
  g_autoptr(GError) dns = g_error_new_literal(G_RESOLVER_ERROR,
                                              G_RESOLVER_ERROR_NOT_FOUND, "dns");
  g_autoptr(GError) unreachable = g_error_new_literal(
      G_IO_ERROR, G_IO_ERROR_NETWORK_UNREACHABLE, "unreachable");
  g_autoptr(GError) refused = g_error_new_literal(
      G_IO_ERROR, G_IO_ERROR_CONNECTION_REFUSED, "refused");
  g_autoptr(GError) http = g_error_new_literal(OTZ_ERROR, OTZ_ERROR_HTTP, "404");
  g_autoptr(GError) limited =
      g_error_new_literal(OTZ_ERROR, OTZ_ERROR_RATE_LIMITED, "403");
  g_autoptr(GError) cancelled =
      g_error_new_literal(G_IO_ERROR, G_IO_ERROR_CANCELLED, "cancelled");
  g_assert_true(otz_error_is_offline(dns));
  g_assert_true(otz_error_is_offline(unreachable));
  g_assert_true(otz_error_is_offline(refused));
  g_assert_false(otz_error_is_offline(http));
  g_assert_false(otz_error_is_offline(limited));
  g_assert_false(otz_error_is_offline(cancelled));
  g_assert_false(otz_error_is_offline(NULL));
}

static void placeholders(const char *text, int counts[4]) {
  memset(counts, 0, sizeof(int) * 4);
  for (const char *at = strchr(text, '%'); at != NULL; at = strchr(at + 1, '%'))
    if (at[1] >= '1' && at[1] <= '3') counts[at[1] - '0']++;
}

/* Every text exists in both languages with the same %1..%3. */
static void test_texts_complete(void) {
  for (int key = 0; key < S_COUNT; key++) {
    otz_set_english(FALSE);
    const char *hebrew = otz_tr(key);
    otz_set_english(TRUE);
    const char *english = otz_tr(key);
    g_assert_cmpstr(hebrew, !=, "");
    g_assert_cmpstr(english, !=, "");
    int he[4], en[4];
    placeholders(hebrew, he);
    placeholders(english, en);
    for (int i = 1; i <= 3; i++) g_assert_cmpint(he[i] > 0, ==, en[i] > 0);
  }
  otz_set_english(FALSE);
}

static void test_texts_format(void) {
  otz_set_english(TRUE);
  g_autofree char *step = otz_trf(S_STEP_OF, "2", "5", NULL);
  g_assert_cmpstr(step, ==, "Step 2 of 5");
  g_autofree char *item = otz_trf(S_DOWNLOADING_ITEM, "A %2", "1", "3", NULL);
  g_assert_cmpstr(item, ==, "Downloading: A %2 (1 of 3)");
  g_autofree char *hours = otz_time_left_text(2 * 3600 + 21 * 60);
  g_assert_cmpstr(hours, ==, "about 2 hours 20 minutes left");
  g_autofree char *short_time = otz_time_left_text(32);
  g_assert_cmpstr(short_time, ==, "about 30 seconds left");
  g_autofree char *few = otz_time_left_text(4);
  g_assert_cmpstr(few, ==, "a few seconds left");
  g_autofree char *en_minute = otz_time_left_text(59);
  g_assert_cmpstr(en_minute, ==, "about 1 minute left");
  g_autofree char *en_hours = otz_time_left_text(2 * 3600 + 5 * 60);
  g_assert_cmpstr(en_hours, ==, "about 2 hours 5 minutes left");
  g_assert_cmpstr(otz_tr_message("לא ניתן לקרוא את רשימת הקבצים של אוצריא."), ==,
                  "Can't read the list of Otzaria files.");
  g_autofree char *plain = otz_ltr("37\xC2\xA0MB");
  g_assert_cmpstr(plain, ==, "37\xC2\xA0MB");

  otz_set_english(FALSE);
  g_autofree char *minutes = otz_time_left_text(44 * 60);
  g_assert_cmpstr(minutes, ==, "נותרו כ-44 דקות");
  g_autofree char *hour = otz_time_left_text(3600 + 15 * 60);
  g_assert_cmpstr(hour, ==, "נותרו כשעה ו-15 דקות");
  g_autofree char *minute = otz_time_left_text(94);
  g_assert_cmpstr(minute, ==, "נותרו כדקה ו-30 שניות");
  g_autofree char *two = otz_time_left_text(2 * 3600 + 60);
  g_assert_cmpstr(two, ==, "נותרו כשעתיים");
  g_autofree char *two_five = otz_time_left_text(2 * 3600 + 5 * 60);
  g_assert_cmpstr(two_five, ==, "נותרו כשעתיים ו-5 דקות");
  g_autofree char *one_minute = otz_time_left_text(59);
  g_assert_cmpstr(one_minute, ==, "נותרה כדקה");
  g_autofree char *ten = otz_time_left_text(599);
  g_assert_cmpstr(ten, ==, "נותרו כ-10 דקות");
  g_autofree char *one_hour = otz_time_left_text(3599);
  g_assert_cmpstr(one_hour, ==, "נותרה כשעה");
  g_autofree char *seconds = otz_time_left_text(44);
  g_assert_cmpstr(seconds, ==, "נותרו כ-45 שניות");
  g_autofree char *mixed = otz_time_left_text(200);
  g_assert_cmpstr(mixed, ==, "נותרו כ-3 דקות ו-20 שניות");
  g_autofree char *he_few = otz_time_left_text(0.4);
  g_assert_cmpstr(he_few, ==, "עוד כמה שניות");
  g_autofree char *isolated = otz_ltr("37\xC2\xA0MB");
  g_assert_cmpstr(isolated, ==, "\xE2\x81\xA6" "37\xC2\xA0MB\xE2\x81\xA9");
  /* RLM opens each line and follows ", ". */
  g_autofree char *bidi = otz_bidi("Windows, Linux או Android\nשורה");
  g_assert_cmpstr(bidi, ==,
                  "\xE2\x80\x8FWindows,\xE2\x80\x8F Linux או Android\n\xE2\x80\x8Fשורה");
  g_assert_cmpstr(otz_tr_message("other"), ==, "other");
}

/* ------------------------------------------------------------- ETA */
/* The scenarios of test/utils/download_eta_estimator_test.dart, driven the way
 * ui.c drives the estimator: a poll every 100 ms, as are the network chunks. */

#define MB 1000000LL
#define POLL_MS 100

static void test_eta_work_rates(void) {
  OtzWorkRates work;
  otz_work_init(&work);
  g_assert_cmpfloat(otz_work_rate(&work, OTZ_WORK_HASH), ==, 150e6);
  g_assert_cmpfloat(otz_work_rate(&work, OTZ_WORK_COPY), ==, 100e6);
  g_assert_cmpfloat_with_epsilon(otz_work_seconds(&work, 100000000, 300000000), 3,
                                 1e-9);
  otz_work_sample(&work, OTZ_WORK_COPY, 0, 0);
  otz_work_sample(&work, OTZ_WORK_COPY, 0.5, 25000000);
  g_assert_cmpfloat(otz_work_rate(&work, OTZ_WORK_COPY), ==, 100e6);
  otz_work_sample(&work, OTZ_WORK_COPY, 2, 100000000);
  g_assert_cmpfloat_with_epsilon(otz_work_rate(&work, OTZ_WORK_COPY), 50e6, 1);
  /* A new step starting lower is a new baseline, not negative work. */
  otz_work_sample(&work, OTZ_WORK_COPY, 3, 0);
  g_assert_cmpfloat_with_epsilon(otz_work_rate(&work, OTZ_WORK_COPY), 50e6, 1);
}

typedef struct {
  double t, shown;
  OtzEtaStatus status;
} EtaRecord;

/* The UI's poll loop with a fake clock, in 50 ms steps. */
typedef struct {
  OtzEta eta;
  int ms;
  long long net, total, offset, rate, true_rate;
  double post;
  gboolean paused;
  OtzEtaStatus status;
  double shown;
  GArray *records;
} Harness;

static void h_init(Harness *h, long long total) {
  memset(h, 0, sizeof *h);
  otz_eta_init(&h->eta);
  h->total = total;
  h->true_rate = 10 * MB;
  h->shown = -1;
  h->records = g_array_new(FALSE, FALSE, sizeof(EtaRecord));
}

static void h_clear(Harness *h) { g_array_unref(h->records); }

static void h_poll(Harness *h) {
  long long remaining = MAX(h->total - h->offset - h->net, 0);
  h->status = otz_eta_tick(&h->eta, h->ms / 1000.0, h->net, remaining, h->post, FALSE,
                           FALSE, h->paused, &h->shown);
  EtaRecord record = {h->ms / 1000.0, h->shown, h->status};
  g_array_append_val(h->records, record);
}

static void h_run(Harness *h, double seconds, long long rate) {
  int steps = (int)lround(seconds * 20);
  for (int i = 0; i < steps; i++) {
    h->ms += 50;
    if (rate > 0 && h->ms % 100 == 0) h->net += rate / 10;
    if (h->ms % POLL_MS == 0) h_poll(h);
  }
}

static void h_feed(Harness *h, double seconds, long long rate) {
  h->true_rate = rate;
  h_run(h, seconds, rate);
}

static double h_exact(const Harness *h) {
  return (h->total - h->offset - h->net) / (double)h->true_rate;
}

static void test_eta_warm_up(void) {
  Harness h;
  h_init(&h, 1000 * MB);
  h_feed(&h, 2.5, 10 * MB);
  g_assert_cmpint(h.status, ==, OTZ_ETA_CALCULATING);
  g_assert_cmpfloat(h.shown, ==, -1);
  h_feed(&h, 1, 10 * MB);
  g_assert_cmpint(h.status, ==, OTZ_ETA_ESTIMATING);
  g_assert_cmpfloat(fabs(h.shown - h_exact(&h)), <=, h_exact(&h) * 0.05);
  h_clear(&h);

  /* Before the first poll of the download: calculating, not the steps alone. */
  OtzEta eta;
  otz_eta_init(&eta);
  double shown;
  g_assert_cmpint(otz_eta_tick(&eta, 2, 0, 1000 * MB, 10, FALSE, FALSE, TRUE, &shown),
                  ==, OTZ_ETA_CALCULATING);
  g_assert_cmpfloat(shown, ==, -1);

  /* 100 KB/s for 5 s: under 1 MiB and under 1% of the rest. */
  h_init(&h, 1000 * MB);
  h_feed(&h, 5, 100000);
  g_assert_cmpint(h.status, ==, OTZ_ETA_CALCULATING);
  h_clear(&h);
}

static void test_eta_not_network(void) {
  /* A resumed file: 600 MB were on disk, they only shorten the rest. */
  Harness h;
  h_init(&h, 1000 * MB);
  h.offset = 600 * MB;
  h_feed(&h, 5, 10 * MB);
  g_assert_cmpfloat(fabs(h.shown - h_exact(&h)), <=, h_exact(&h) * 0.05);
  h_clear(&h);

  /* A download that starts again from 0: the rate stays, only the rest grows. */
  h_init(&h, 1000 * MB);
  h_feed(&h, 10, 10 * MB);
  h.offset = -h.net;
  h_feed(&h, 0.25, 10 * MB);
  g_assert_cmpint(h.status, ==, OTZ_ETA_ESTIMATING);
  h_feed(&h, 2, 10 * MB);
  g_assert_cmpint(h.status, ==, OTZ_ETA_ESTIMATING);
  g_assert_cmpfloat(h.shown, <=, h_exact(&h) * 1.1);
  g_assert_cmpfloat(h.shown, >, 50);
  h_clear(&h);
}

static void test_eta_known_pause(void) {
  Harness h;
  h_init(&h, 1000 * MB);
  h_feed(&h, 10, 10 * MB);
  double before = h.shown;
  h.paused = TRUE;
  guint from = h.records->len;
  h_run(&h, 60, 0);
  for (guint i = from; i < h.records->len; i++) {
    EtaRecord *r = &g_array_index(h.records, EtaRecord, i);
    g_assert_cmpint(r->status, ==, OTZ_ETA_ESTIMATING);
    g_assert_cmpfloat_with_epsilon(r->shown, before, 1e-6);
  }
  h.paused = FALSE;
  h.net += 64 * 1024;
  h_feed(&h, 2, 10 * MB);
  g_assert_cmpfloat(h.shown, <=, before);
  g_assert_cmpfloat(fabs(h.shown - h_exact(&h)), <=, h_exact(&h) * 0.1);
  h_clear(&h);
}

static EtaRecord *h_record_at(Harness *h, double t) {
  for (guint i = 0; i < h->records->len; i++) {
    EtaRecord *r = &g_array_index(h->records, EtaRecord, i);
    if (fabs(r->t - t) < 1e-6) return r;
  }
  g_assert_not_reached();
}

static void test_eta_stall_status(void) {
  Harness h;
  h_init(&h, 1000 * MB);
  h_feed(&h, 10, 10 * MB);
  h_run(&h, 6, 0);
  g_assert_cmpint(h_record_at(&h, 14)->status, ==, OTZ_ETA_ESTIMATING);
  EtaRecord *stalled = h_record_at(&h, 16);
  g_assert_cmpint(stalled->status, ==, OTZ_ETA_STALLED);
  g_assert_cmpfloat(stalled->shown, ==, -1);
  h_clear(&h);
}

/* The displayed speed is the same blended rate with tau 3 s. */
static void test_eta_speed(void) {
  Harness h;
  h_init(&h, 1000 * MB);
  h_feed(&h, 0.5, 10 * MB);
  g_assert_cmpfloat(otz_eta_speed(&h.eta), ==, 0);
  h_feed(&h, 5, 10 * MB);
  g_assert_cmpfloat(otz_eta_speed(&h.eta), ==, otz_rate_value(&h.eta.speed));
  g_assert_cmpfloat(fabs(otz_eta_speed(&h.eta) - 10 * MB), <=, 0.02 * 10 * MB);
  h_feed(&h, 10, 5 * MB);
  g_assert_cmpfloat(fabs(otz_eta_speed(&h.eta) - 5 * MB), <=, 0.25 * 5 * MB);
  h_clear(&h);
}

static void test_eta_short_silences(void) {
  Harness h;
  h_init(&h, 3000 * MB);
  h_feed(&h, 20, 10 * MB);
  double previous = h.shown;
  for (int gap = 1; gap <= 4; gap++) {
    /* Checked once a second, as the text changes at most once a second. */
    for (int second = 0; second < gap; second++) {
      h_run(&h, 1, 0);
      g_assert_cmpfloat(h.shown, <=, previous);
      previous = h.shown;
    }
    h_feed(&h, 5, 10 * MB);
    previous = h.shown;
  }
  h_clear(&h);
}

static void test_eta_stall_recovery(void) {
  Harness h;
  h_init(&h, 2000 * MB);
  h_feed(&h, 20, 10 * MB);
  guint from = h.records->len;
  h_run(&h, 12, 0);
  for (int i = 0; i < 240; i++) {
    h_feed(&h, 0.25, 10 * MB);
    g_assert_cmpfloat(h.shown, <=, (h_exact(&h) + 12) * 1.1);
  }
  /* The warm-up latches: a lone stall shows only the stall status, never
   * "calculating" again. */
  for (guint i = from; i < h.records->len; i++)
    g_assert_cmpint(g_array_index(h.records, EtaRecord, i).status, !=,
                    OTZ_ETA_CALCULATING);
  h_clear(&h);

  h_init(&h, 2000 * MB);
  h_feed(&h, 20, 10 * MB);
  h_run(&h, 45, 0);
  h_feed(&h, 0.25, 10 * MB);
  g_assert_cmpint(h.status, ==, OTZ_ETA_CALCULATING);
  while (h.status == OTZ_ETA_CALCULATING) h_feed(&h, 0.25, 10 * MB);
  g_assert_cmpfloat(fabs(h.shown - h_exact(&h)), <=, h_exact(&h) * 0.15);
  h_clear(&h);
}

static void test_eta_rate_change(void) {
  static const long long pairs[][2] = {{10, 5}, {5, 10}};
  for (gsize i = 0; i < G_N_ELEMENTS(pairs); i++) {
    Harness h;
    h_init(&h, 3000 * MB);
    h_feed(&h, 30, pairs[i][0] * MB);
    h_feed(&h, 45, pairs[i][1] * MB);
    g_assert_cmpfloat(fabs(h.shown - h_exact(&h)), <=, h_exact(&h) * 0.1);
    h_clear(&h);
  }
}

static void test_eta_planned_steps(void) {
  /* 1.5 GB to hash at the default 150 MB/s: 10 more seconds. */
  Harness h;
  h_init(&h, 1000 * MB);
  OtzWorkRates work;
  otz_work_init(&work);
  h.post = otz_work_seconds(&work, 0, 1500 * MB);
  h_feed(&h, 10, 10 * MB);
  g_assert_cmpfloat(fabs(h.shown - (h_exact(&h) + 10)), <=, h_exact(&h) * 0.05);
  h_clear(&h);

  /* A step that reports progress is measured at its live rate: 10 MB/s, four
   * times slower than assumed; 400 of 600 MB done leaves 20 s. */
  OtzEta eta;
  otz_eta_init(&eta);
  otz_work_init(&work);
  double shown = -1;
  for (int i = 1; i <= 160; i++) {
    double t = i * 0.25;
    long long done = (long long)lround(i * 2.5) * MB;
    otz_work_sample(&work, OTZ_WORK_COPY, t, done);
    double post = otz_work_seconds(&work, 600 * MB - done, 0);
    g_assert_cmpint(otz_eta_tick(&eta, t, 0, 0, post, TRUE, TRUE, FALSE, &shown), ==,
                    OTZ_ETA_PHASE);
  }
  g_assert_cmpfloat(fabs(shown - 20), <=, 5);
}

/* Bursts: `data` seconds of 100 ms samples, then a gap of `silence` between
 * samples; the rate at the end of each burst of the second half. */
static void bursty_rates(double data, double silence, double average, double bound) {
  const double interval = 0.1;
  int chunks = (int)lround(data / interval);
  double cycle = (chunks - 1) * interval + silence;
  long long chunk = llround(average * cycle / chunks);
  OtzRate rate;
  otz_rate_init(&rate, 8);
  double t = 0;
  long long bytes = 0;
  otz_rate_add(&rate, 0, 0);
  for (int c = 0; c < 40; c++) {
    for (int i = 0; i < chunks; i++) {
      t += interval;
      otz_rate_add(&rate, bytes += chunk, t);
    }
    if (c >= 20)
      g_assert_cmpfloat(fabs(otz_rate_value(&rate) - average), <=, bound * average);
    t += silence - interval;
  }
}

static void test_eta_bursty_rate(void) {
  bursty_rates(0.6, 0.4, 5.0 * MB, 0.05);
  bursty_rates(0.6, 1.9, 5.0 * MB, 0.10);
  bursty_rates(0.6, 4.9, 5.0 * MB, 0.10);
}

static double display_flow(OtzEtaDisplay *d, double raw, double from, double to) {
  double shown = 0;
  for (double t = from; t <= to + 1e-9; t += 0.1)
    shown = otz_eta_display_update(d, raw, t, TRUE);
  return shown;
}

static void test_eta_display(void) {
  /* Data once a second under noise: a steady countdown. */
  OtzEtaDisplay d = {0};
  otz_eta_display_update(&d, 300, 0, TRUE);
  double previous = 300;
  for (int t = 1; t <= 60; t++) {
    double raw = 300.0 - t + (t % 2 == 0 ? 12 : -12);
    double shown = otz_eta_display_update(&d, raw, t, TRUE);
    g_assert_cmpfloat(shown, <=, previous);
    g_assert_cmpfloat(fabs(shown - (300.0 - t)), <=, 2);
    previous = shown;
  }

  /* Continuous flow: rises slowly, falls fast. */
  OtzEtaDisplay same = {0}, up = {0}, down = {0};
  display_flow(&same, 100, 0, 3);
  display_flow(&up, 100, 0, 3);
  display_flow(&down, 100, 0, 3);
  double base = display_flow(&same, 100, 3.1, 5);
  double rose = display_flow(&up, 150, 3.1, 5) - base;
  double fell = base - display_flow(&down, 50, 3.1, 5);
  g_assert_cmpfloat(rose, >, 0);
  g_assert_cmpfloat(rose, <, 50 * 0.2);
  g_assert_cmpfloat(fell, >, rose * 2);

  /* Under half: shown at the next correction point. */
  OtzEtaDisplay snap = {0};
  display_flow(&snap, 100, 0, 3);
  g_assert_cmpfloat_with_epsilon(otz_eta_display_update(&snap, 30, 3.1, TRUE), 30, 1e-9);

  /* End of a burst corrects to the raw of its last sample, not the current. */
  OtzEtaDisplay burst = {0};
  otz_eta_display_update(&burst, 100, 0, TRUE);
  otz_eta_display_update(&burst, 30, 0.5, TRUE);
  g_assert_cmpfloat_with_epsilon(otz_eta_display_update(&burst, 500, 1, FALSE), 99, 1e-9);
  g_assert_cmpfloat_with_epsilon(otz_eta_display_update(&burst, 500, 1.5, FALSE), 30,
                                 1e-9);
  g_assert_cmpfloat_with_epsilon(otz_eta_display_update(&burst, 500, 2.5, FALSE), 29,
                                 1e-9);

  /* No correction point: countdown only. */
  OtzEtaDisplay plain = {0};
  otz_eta_display_update(&plain, 100, 0, TRUE);
  g_assert_cmpfloat(otz_eta_display_update(&plain, 200, 0.9, TRUE), ==, 99.1);
}

/* ------------------------------------------- realistic runs (chunk lists) */

typedef struct {
  int ms;
  long long bytes;
} EtaChunk;

typedef struct {
  GArray *records; /* EtaRecord per poll */
  GArray *texts;   /* (t, rounded seconds) at each change of the shown text */
  double end;
} EtaRun;

static int rounded_seconds(double seconds) {
  int h, m, s;
  otz_eta_round(seconds, &h, &m, &s);
  return h * 3600 + m * 60 + s;
}

/* The truth is the time of the last chunk; the text changes at most once a
 * second, at once on a status change (as ui.c does). */
static EtaRun eta_simulate(GArray *chunks) {
  long long total = 0;
  for (guint i = 0; i < chunks->len; i++) total += g_array_index(chunks, EtaChunk, i).bytes;
  int end_ms = g_array_index(chunks, EtaChunk, chunks->len - 1).ms;
  EtaRun run = {g_array_new(FALSE, FALSE, sizeof(EtaRecord)),
                g_array_new(FALSE, FALSE, sizeof(double) * 2), end_ms / 1000.0};
  OtzEta eta;
  otz_eta_init(&eta);
  long long net = 0;
  guint next = 0;
  double text_t = -10;
  int text_status = -1, text_value = -1;
  for (int ms = POLL_MS; ms <= end_ms + POLL_MS; ms += POLL_MS) {
    while (next < chunks->len && g_array_index(chunks, EtaChunk, next).ms <= ms)
      net += g_array_index(chunks, EtaChunk, next++).bytes;
    double t = ms / 1000.0, shown;
    OtzEtaStatus status =
        otz_eta_tick(&eta, t, net, total - net, 0, FALSE, FALSE, FALSE, &shown);
    EtaRecord record = {t, shown, status};
    g_array_append_val(run.records, record);
    if ((int)status == text_status && t - text_t < 1) continue;
    text_status = status;
    text_t = t;
    int value = shown >= 0 ? rounded_seconds(shown) : -1;
    if (value >= 0 && value != text_value) {
      double change[2] = {t, value};
      g_array_append_val(run.texts, change);
    }
    text_value = value;
  }
  g_array_unref(chunks);
  return run;
}

static void eta_run_clear(EtaRun *run) {
  g_array_unref(run->records);
  g_array_unref(run->texts);
}

static double run_error(const EtaRun *run, const EtaRecord *r) {
  return fabs(r->shown - (run->end - r->t)) / (run->end - r->t);
}

static double run_first_shown_t(const EtaRun *run) {
  for (guint i = 0; i < run->records->len; i++) {
    EtaRecord *r = &g_array_index(run->records, EtaRecord, i);
    if (r->shown >= 0) return r->t;
  }
  g_assert_not_reached();
}

static double run_first_error(const EtaRun *run) {
  for (guint i = 0; i < run->records->len; i++) {
    EtaRecord *r = &g_array_index(run->records, EtaRecord, i);
    if (r->shown >= 0) return run_error(run, r);
  }
  g_assert_not_reached();
}

/* While at least 60 s remain: in bursts the end is quantized to cycles. */
static double run_max_error(const EtaRun *run, double from) {
  double worst = 0;
  for (guint i = 0; i < run->records->len; i++) {
    EtaRecord *r = &g_array_index(run->records, EtaRecord, i);
    if (r->shown >= 0 && r->t >= from && run->end - r->t >= 60)
      worst = MAX(worst, run_error(run, r));
  }
  return worst;
}

static double run_error_at(const EtaRun *run, double t) {
  const EtaRecord *last = NULL;
  for (guint i = 0; i < run->records->len; i++) {
    EtaRecord *r = &g_array_index(run->records, EtaRecord, i);
    if (r->shown >= 0 && r->t <= t + 1e-9) last = r;
  }
  g_assert_nonnull(last);
  return run_error(run, last);
}

static int run_text_increases(const EtaRun *run, double until) {
  int count = 0;
  for (guint i = 1; i < run->texts->len; i++) {
    double *now = &g_array_index(run->texts, double, 2 * i);
    double *before = &g_array_index(run->texts, double, 2 * (i - 1));
    if (now[0] > until) break;
    if (now[1] > before[1]) count++;
  }
  return count;
}

static void add_chunk(GArray *chunks, int ms, long long bytes) {
  EtaChunk chunk = {ms, bytes};
  g_array_append_val(chunks, chunk);
}

/* A chunk every 100 ms at `rate`, with fixed-seed noise of +-jitter. */
static GArray *steady_chunks(long long total, long long rate, double jitter) {
  GArray *chunks = g_array_new(FALSE, FALSE, sizeof(EtaChunk));
  GRand *random = g_rand_new_with_seed(7);
  long long sent = 0;
  for (int ms = 100; sent < total; ms += 100) {
    double factor = 1 + jitter * (2 * g_rand_double(random) - 1);
    long long bytes = MIN(llround(rate / 10.0 * factor), total - sent);
    add_chunk(chunks, ms, bytes);
    sent += bytes;
  }
  g_rand_free(random);
  return chunks;
}

/* 5 MB/s on average: `on` chunks 100 ms apart, then the next gap of `offs`
 * (cyclic) until the following chunk. */
static GArray *bursty_chunks(const double *offs, int n_offs, int on) {
  const long long total = 2000 * MB;
  double mean = 0;
  for (int i = 0; i < n_offs; i++) mean += offs[i] / n_offs;
  long long chunk = llround(5.0 * MB * ((on - 1) * 0.1 + mean) / on);
  GArray *chunks = g_array_new(FALSE, FALSE, sizeof(EtaChunk));
  long long sent = 0;
  int ms = 0;
  for (int c = 0; sent < total; c++) {
    ms += (int)lround(offs[c % n_offs] * 1000);
    for (int i = 0; i < on && sent < total; i++) {
      if (i > 0) ms += 100;
      long long bytes = MIN(chunk, total - sent);
      add_chunk(chunks, ms, bytes);
      sent += bytes;
    }
  }
  return chunks;
}

/* (seconds, rate) segments; rate 0 is silence; the last one runs to the end. */
static GArray *segment_chunks(const long long (*segments)[2], int count, long long total) {
  GArray *chunks = g_array_new(FALSE, FALSE, sizeof(EtaChunk));
  long long sent = 0;
  int start = 0;
  for (int s = 0; s < count; s++) {
    int end = start + (int)segments[s][0] * 1000;
    for (int ms = start + 100; ms <= end && sent < total; ms += 100) {
      if (segments[s][1] == 0) continue;
      long long bytes = MIN(segments[s][1] / 10, total - sent);
      add_chunk(chunks, ms, bytes);
      sent += bytes;
    }
    start = end;
  }
  return chunks;
}

static void test_eta_sim_steady(void) {
  EtaRun run = eta_simulate(steady_chunks(3000 * MB, 5 * MB, 0.4));
  g_test_message("steady 5 MB/s +-40%%: text increases %d, max error %.1f%%",
                 run_text_increases(&run, INFINITY), run_max_error(&run, 10) * 100);
  g_assert_cmpint(run_text_increases(&run, INFINITY), ==, 0);
  g_assert_cmpfloat(run_max_error(&run, 10), <, 0.10);
  eta_run_clear(&run);
}

static void test_eta_sim_bursty(void) {
  static const double off49[] = {4.9}, off19[] = {1.9}, off20[] = {2.0};
  static const double off60[] = {6.0}, off90[] = {9.0};
  static const double mixed[] = {4.8, 5.1, 4.9, 5.3};

  EtaRun run = eta_simulate(bursty_chunks(off49, 1, 6));
  double e49 = run_max_error(&run, run_first_shown_t(&run) + 20);
  eta_run_clear(&run);
  run = eta_simulate(bursty_chunks(off19, 1, 6));
  double e19 = run_max_error(&run, run_first_shown_t(&run) + 20);
  eta_run_clear(&run);
  run = eta_simulate(bursty_chunks(off20, 1, 6));
  double first20 = run_first_error(&run);
  int up20 = run_text_increases(&run, 120);
  eta_run_clear(&run);
  run = eta_simulate(bursty_chunks(off49, 1, 30));
  int up3_49 = run_text_increases(&run, 120);
  eta_run_clear(&run);
  run = eta_simulate(bursty_chunks(off60, 1, 6));
  double e60 = run_max_error(&run, 60);
  eta_run_clear(&run);
  run = eta_simulate(bursty_chunks(off90, 1, 6));
  double e90 = run_max_error(&run, 60);
  eta_run_clear(&run);
  run = eta_simulate(bursty_chunks(mixed, 4, 6));
  double emixed = run_max_error(&run, 60);
  eta_run_clear(&run);

  g_test_message("bursty 0.6/4.9 %.1f%%, 0.6/1.9 %.1f%%, 0.6/2.0 first %.1f%% with %d "
                 "rises, 3/4.9 %d rises, 0.6/6.0 %.1f%%, 0.6/9.0 %.1f%%, mixed %.1f%%",
                 e49 * 100, e19 * 100, first20 * 100, up20, up3_49, e60 * 100, e90 * 100,
                 emixed * 100);
  g_assert_cmpfloat(e49, <, 0.15);
  g_assert_cmpfloat(e19, <, 0.10);
  g_assert_cmpfloat(first20, <, 0.20);
  g_assert_cmpint(up20, <=, 3);
  g_assert_cmpint(up3_49, <=, 3);
  g_assert_cmpfloat(e60, <, 0.15);
  g_assert_cmpfloat(e90, <, 0.15);
  g_assert_cmpfloat(emixed, <, 0.15);
}

static void test_eta_once_per_second(void) {
  const double phases[] = {0, 0.05, 0.95};
  for (int phase = 0; phase < 3; phase++) {
    for (int direction = 0; direction < 2; direction++) {
      long long from = direction ? MB : 5 * MB;
      long long to = direction ? 5 * MB : MB;
      long long total = 2000 * MB, bytes = 0;
      OtzEta eta;
      otz_eta_init(&eta);
      double shown;
      for (int second = 1; second <= 400; second++) {
        bytes += second <= 20 ? from : to;
        otz_eta_tick(&eta, second, bytes, total - bytes, 0, 0, 0, 0, &shown);
        OtzEtaStatus status = otz_eta_tick(&eta, second + phases[phase], bytes,
                                          total - bytes, 0, 0, 0, 0, &shown);
        if (second >= 120) {
          double expected = (double)(total - bytes) / to;
          g_assert_cmpint(status, ==, OTZ_ETA_ESTIMATING);
          g_assert_cmpfloat(fabs(shown - expected), <=, expected * 0.15);
        }
      }
    }
  }
}

static void test_eta_sim_rate_change(void) {
  static const long long down[][2] = {{30, 10 * MB}, {100000, 5 * MB}};
  static const long long up[][2] = {{30, 5 * MB}, {100000, 10 * MB}};
  EtaRun run = eta_simulate(segment_chunks(down, 2, 3000 * MB));
  double e_down = run_error_at(&run, 75);
  eta_run_clear(&run);
  run = eta_simulate(segment_chunks(up, 2, 3000 * MB));
  double e_up = run_error_at(&run, 75);
  eta_run_clear(&run);
  g_test_message("rate change at +45 s: 10->5 %.1f%%, 5->10 %.1f%%", e_down * 100,
                 e_up * 100);
  g_assert_cmpfloat(e_down, <, 0.10);
  g_assert_cmpfloat(e_up, <, 0.10);
}

static void test_eta_sim_stalls(void) {
  static const long long stall12[][2] = {{20, 10 * MB}, {12, 0}, {100000, 10 * MB}};
  static const long long stall45[][2] = {{20, 10 * MB}, {45, 0}, {100000, 10 * MB}};
  EtaRun run = eta_simulate(segment_chunks(stall12, 3, 2000 * MB));
  double worst = 0;
  for (guint i = 0; i < run.records->len; i++) {
    EtaRecord *r = &g_array_index(run.records, EtaRecord, i);
    if (r->t <= 32 || r->shown < 0) continue;
    worst = MAX(worst, r->shown / (run.end - r->t + 12) - 1);
    g_assert_cmpfloat(r->shown, <=, (run.end - r->t + 12) * 1.1);
  }
  eta_run_clear(&run);

  run = eta_simulate(segment_chunks(stall45, 3, 2000 * MB));
  const EtaRecord *first = NULL, *back = NULL;
  for (guint i = 0; i < run.records->len; i++) {
    EtaRecord *r = &g_array_index(run.records, EtaRecord, i);
    if (r->t <= 65.05) continue;
    if (first == NULL) first = r;
    if (back == NULL && r->shown >= 0) back = r;
  }
  g_assert_cmpint(first->status, ==, OTZ_ETA_CALCULATING);
  double error = run_error(&run, back);
  g_test_message("12 s stall: worst %+.1f%% over truth+12 s; 45 s stall: back at "
                 "%.2f s, %.1f%% from truth",
                 worst * 100, back->t, error * 100);
  g_assert_cmpfloat(error, <, 0.15);
  eta_run_clear(&run);
}

/* The bucket table of formatRemainingTimeHebrew. */
static void test_eta_format_table(void) {
  static const struct {
    double seconds;
    const char *text;
  } cases[] = {
      {0, "עוד כמה שניות"},
      {4.7, "עוד כמה שניות"},
      {4.9, "עוד כמה שניות"},
      {5, "נותרו כ-5 שניות"},
      {44, "נותרו כ-45 שניות"},
      {59, "נותרה כדקה"},
      {60, "נותרה כדקה"},
      {90, "נותרו כדקה ו-30 שניות"},
      {200, "נותרו כ-3 דקות ו-20 שניות"},
      {300, "נותרו כ-5 דקות"},
      {599, "נותרו כ-10 דקות"},
      {600, "נותרו כ-10 דקות"},
      {1830, "נותרו כ-31 דקות"},
      {3599, "נותרה כשעה"},
      {3600, "נותרה כשעה"},
      {4500, "נותרו כשעה ו-15 דקות"},
      {7200, "נותרו כשעתיים"},
      {7500, "נותרו כשעתיים ו-5 דקות"},
      {3 * 3600 + 20 * 60, "נותרו כ-3 שעות ו-20 דקות"},
  };
  otz_set_english(FALSE);
  for (gsize i = 0; i < G_N_ELEMENTS(cases); i++) {
    g_autofree char *text = otz_time_left_text(cases[i].seconds);
    g_assert_cmpstr(text, ==, cases[i].text);
  }
}

static void test_eta_round(void) {
  static const struct {
    double seconds;
    int h, m, s;
  } cases[] = {
      {0, 0, 0, 0},       {4.9, 0, 0, 0},    {5, 0, 0, 5},     {33, 0, 0, 35},
      {58, 0, 1, 0},      {60, 0, 1, 0},     {94, 0, 1, 30},   {125, 0, 2, 10},
      {599, 0, 10, 0},    {600, 0, 10, 0},   {2669, 0, 44, 0}, {3599, 1, 0, 0},
      {3600, 1, 0, 0},    {5000, 1, 25, 0},  {7190, 2, 0, 0},  {9000, 2, 30, 0},
  };
  for (gsize i = 0; i < G_N_ELEMENTS(cases); i++) {
    int h, m, s;
    otz_eta_round(cases[i].seconds, &h, &m, &s);
    g_test_message("%.1f -> %d:%d:%d", cases[i].seconds, h, m, s);
    g_assert_cmpint(h, ==, cases[i].h);
    g_assert_cmpint(m, ==, cases[i].m);
    g_assert_cmpint(s, ==, cases[i].s);
  }
}

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, NULL);
  g_test_add_func("/selection/fixtures", test_fixtures);
  g_test_add_func("/selection/fixtures-large-full", test_fixtures_large_full);
  g_test_add_func("/selection/library-brings-its-installer",
                  test_library_brings_its_installer);
  g_test_add_func("/selection/package-format-any", test_package_format_any);
  g_test_add_func("/selection/full-indexed-preset", test_full_indexed_preset);
  g_test_add_func("/manifest/rejects", test_manifest_rejects);
  g_test_add_func("/json/hebrew-escapes", test_json_hebrew_escapes);
  g_test_add_func("/json/values", test_json_values);
  g_test_add_func("/json/rejects", test_json_rejects);
  g_test_add_func("/http/content-length", test_http_content_length);
  g_test_add_func("/http/chunked", test_http_chunked);
  g_test_add_func("/http/truncated", test_http_truncated);
  g_test_add_func("/http/malformed", test_http_malformed);
  g_test_add_func("/http/range-replies", test_http_range_replies);
  g_test_add_func("/http/hosts", test_url_hosts);
  g_test_add_func("/cache/marker", test_marker);
  g_test_add_func("/output/assembly", test_assembly);
  g_test_add_func("/output/place-file", test_place_file);
  g_test_add_func("/release/tag", test_release_tag);
  g_test_add_func("/release/asset-url", test_asset_url_and_sizes);
  g_test_add_func("/release/api-fallback", test_api_fallback);
  g_test_add_func("/http/long-header", test_http_long_header);
  g_test_add_func("/job/failure-kind", test_job_failure_kind);
  g_test_add_func("/job/complete-download-promoted",
                  test_job_complete_download_promoted);
  g_test_add_func("/job/complete-download-wrong", test_job_complete_download_wrong);
  g_test_add_func("/job/output-folder", test_job_output_folder);
  g_test_add_func("/job/partial-bound-to-asset", test_job_partial_bound_to_asset);
  g_test_add_func("/job/space", test_space_verdict);
  g_test_add_func("/job/subfolder-name", test_job_subfolder_name);
  g_test_add_func("/manifest/english-text", test_manifest_english_text);
  g_test_add_func("/release/offline-errors", test_offline_errors);
  g_test_add_func("/texts/complete", test_texts_complete);
  g_test_add_func("/texts/format", test_texts_format);
  g_test_add_func("/eta/work-rates", test_eta_work_rates);
  g_test_add_func("/eta/warm-up", test_eta_warm_up);
  g_test_add_func("/eta/not-network", test_eta_not_network);
  g_test_add_func("/eta/known-pause", test_eta_known_pause);
  g_test_add_func("/eta/stall-status", test_eta_stall_status);
  g_test_add_func("/eta/speed", test_eta_speed);
  g_test_add_func("/eta/short-silences", test_eta_short_silences);
  g_test_add_func("/eta/stall-recovery", test_eta_stall_recovery);
  g_test_add_func("/eta/rate-change", test_eta_rate_change);
  g_test_add_func("/eta/planned-steps", test_eta_planned_steps);
  g_test_add_func("/eta/bursty-rate", test_eta_bursty_rate);
  g_test_add_func("/eta/display", test_eta_display);
  g_test_add_func("/eta/sim-steady", test_eta_sim_steady);
  g_test_add_func("/eta/sim-bursty", test_eta_sim_bursty);
  g_test_add_func("/eta/once-per-second", test_eta_once_per_second);
  g_test_add_func("/eta/sim-rate-change", test_eta_sim_rate_change);
  g_test_add_func("/eta/sim-stalls", test_eta_sim_stalls);
  g_test_add_func("/eta/format-table", test_eta_format_table);
  g_test_add_func("/eta/round", test_eta_round);
  return g_test_run();
}
