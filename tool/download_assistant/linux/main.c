/* Otzaria Download Assistant for Linux (docs/download_assistant.md). */
#include <gtk/gtk.h>
#include <locale.h>
#include <stdio.h>

#include "otz_common.h"
#include "texts.h"
#include "ui.h"

static gboolean self_test = FALSE;
static char *dev_owner = NULL;
static char *dev_manifest = NULL;
static char *dev_auto_preset = NULL;
static char *dev_platform = NULL;
static char *dev_output = NULL;
static char *dev_screenshot = NULL;

static GOptionEntry entries[] = {
    {"self-test", 0, 0, G_OPTION_ARG_NONE, &self_test,
     "Open the window briefly and exit (CI smoke test)", NULL},
    {"dev-owner", 0, 0, G_OPTION_ARG_STRING, &dev_owner,
     "DEV ONLY: GitHub organization to trust instead of Otzaria (fork testing)",
     "OWNER"},
    {"dev-manifest", 0, 0, G_OPTION_ARG_FILENAME, &dev_manifest,
     "DEV ONLY: read the release manifest from a local file", "FILE"},
    {"dev-auto-preset", 0, 0, G_OPTION_ARG_STRING, &dev_auto_preset,
     "DEV ONLY: walk the pages with their defaults, pick this preset "
     "(basic/full-indexed/full/update), print a report and exit",
     "ID"},
    {"dev-platform", 0, 0, G_OPTION_ARG_STRING, &dev_platform,
     "DEV ONLY: preselect this target platform", "PLATFORM"},
    {"dev-output", 0, 0, G_OPTION_ARG_FILENAME, &dev_output,
     "DEV ONLY: output folder", "DIR"},
    {"dev-screenshot", 0, 0, G_OPTION_ARG_FILENAME, &dev_screenshot,
     "DEV ONLY: render every screen in Hebrew and English to PNG files in DIR "
     "(needs --dev-manifest) and exit",
     "DIR"},
    {NULL},
};

int main(int argc, char **argv) {
  setlocale(LC_ALL, "");
  /* Light only: GTK_THEME=Adwaita:dark would win over the forced setting. */
  g_unsetenv("GTK_THEME");
  g_autoptr(GOptionContext) context =
      g_option_context_new("- Otzaria Download Assistant");
  g_option_context_add_main_entries(context, entries, NULL);
  g_option_context_add_group(context, gtk_get_option_group(TRUE));
  g_autoptr(GError) error = NULL;
  if (!g_option_context_parse(context, &argc, &argv, &error)) {
    g_printerr("%s\n", error->message);
    return 2;
  }
  if (dev_owner != NULL) otz_set_allowed_owner(dev_owner);
  otz_set_english(otz_detect_english());

  gboolean tls = g_tls_backend_supports_tls(g_tls_backend_get_default());
  if (self_test) {
    printf("self-test: tls=%s tag=%s lang=%s\n", tls ? "yes" : "no",
           otz_embedded_release_tag(), otz_english() ? "en" : "he");
    fflush(stdout);
  }

  OtzUiOptions options = {
      .self_test = self_test,
      .tls_ok = tls,
      .dev_manifest = dev_manifest,
      .dev_auto_preset = dev_auto_preset,
      .dev_platform = dev_platform,
      .dev_output = dev_output,
      .dev_screenshot = dev_screenshot,
  };
  int code = otz_ui_run(&options);
  if (self_test && code == 0) printf("self-test: ok\n");
  return code;
}
