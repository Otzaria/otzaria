/* Unit tests: the shared contract fixtures, JSON, HTTP parsing, host checks,
 * cache markers and assembly. Run with `make test`. */
#include <fcntl.h>
#include <stdlib.h>
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "assemble.h"
#include "download.h"
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
  g_autofree char *hours = otz_duration_text(2 * 3600 + 20 * 60);
  g_assert_cmpstr(hours, ==, "2 hours 20 minutes");
  g_autofree char *short_time = otz_duration_text(30);
  g_assert_cmpstr(short_time, ==, "less than a minute");
  g_assert_cmpstr(otz_tr_message("לא ניתן לקרוא את רשימת הקבצים של אוצריא."), ==,
                  "Can't read the list of Otzaria files.");
  g_autofree char *plain = otz_ltr("37\xC2\xA0MB");
  g_assert_cmpstr(plain, ==, "37\xC2\xA0MB");

  otz_set_english(FALSE);
  g_autofree char *minutes = otz_duration_text(44 * 60);
  g_assert_cmpstr(minutes, ==, "44 דקות");
  g_autofree char *hour = otz_duration_text(3600 + 60);
  g_assert_cmpstr(hour, ==, "שעה ו-דקה");
  g_autofree char *isolated = otz_ltr("37\xC2\xA0MB");
  g_assert_cmpstr(isolated, ==, "\xE2\x81\xA6" "37\xC2\xA0MB\xE2\x81\xA9");
  /* RLM opens each line and follows ", ". */
  g_autofree char *bidi = otz_bidi("Windows, Linux או Android\nשורה");
  g_assert_cmpstr(bidi, ==,
                  "\xE2\x80\x8FWindows,\xE2\x80\x8F Linux או Android\n\xE2\x80\x8Fשורה");
  g_assert_cmpstr(otz_tr_message("other"), ==, "other");
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
  return g_test_run();
}
