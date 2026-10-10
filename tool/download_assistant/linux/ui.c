#include "ui.h"

#include <gtk/gtk.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "download.h"
#include "otz_common.h"
#include "paths.h"
#include "release.h"
#include "selection.h"
#include "texts.h"
#include "widgets.h"

typedef enum {
  PAGE_WELCOME,
  PAGE_CONNECTING,
  PAGE_MODE,
  PAGE_OTHER,
  PAGE_PRESETS,
  PAGE_CUSTOM,
  PAGE_FOLDER,
  PAGE_READY,
  PAGE_WORKING,
  PAGE_FINISHED,
  PAGE_FAILURE,
} Page;

typedef enum {
  FAIL_LOAD,    /* the list did not load */
  FAIL_OFFLINE, /* no request reached a server */
  FAIL_RUN,     /* download, joining or copying failed */
  FAIL_STOPPED, /* the user stopped: calm, not an error */
  FAIL_TLS,     /* glib-networking is missing */
} Failure;

typedef enum { MODE_THIS, MODE_OTHER } Mode;

#define CUSTOM_ID "custom"
#define SPEED_WINDOW_US (5 * G_USEC_PER_SEC)
#define MAX_SAMPLES 64

/* The opening (assistant_art.isi: AA_BOOK_*, AA_RISE_*, AA_TITLE_*), in ms. */
#define HERO_FADE_MS 250.0
#define HERO_FRAME_MS 42.0
#define HERO_RISE_START (17 * HERO_FRAME_MS)
#define HERO_RISE_MS 650.0
#define HERO_TITLE_START (HERO_RISE_START + HERO_RISE_MS)
#define HERO_TITLE_FADE_MS 400.0
#define HERO_END_MS (HERO_FADE_MS + HERO_TITLE_START + HERO_TITLE_FADE_MS)

typedef struct {
  char *platform, *architecture, *format;
} Target;

typedef struct {
  gint64 time, bytes;
} Sample;

typedef struct Ui Ui;
typedef void (*UiAction)(Ui *ui);

typedef struct {
  gboolean set;
  OtzPhase phase;
  gint64 done, total;
  guint files_done, files_total;
  char *detail;
  double speed, eta; /* -1 until measured */
} Status;

struct Ui {
  const OtzUiOptions *options;
  gboolean english;
  gboolean snapshot;

  GtkWidget *window, *overlay, *scroll, *host, *page;
  GtkWidget *shade, *dialog;
  GtkWidget *focus;
  UiAction primary, escape;
  UiAction dialog_default, dialog_cancel, dialog_confirm;
  gboolean dialog_open;
  gboolean building;

  /* Live parts of the working page. */
  GtkWidget *w_title, *w_desc, *w_percent, *w_caption, *w_bar, *w_speed, *w_bytes;
  /* The welcome page. */
  GtkWidget *hero, *hero_note, *hero_start;
  gboolean hero_played;
  gint64 hero_start_us;
  double hero_preview_ms;

  Page page_id;
  GArray *history;
  Failure failure;
  char *error_message; /* Hebrew, as the core reports it */
  char *error_technical;
  gboolean show_technical;
  gboolean failed_while_loading;

  OtzManifest *manifest;
  gboolean borrowed_manifest;
  char *pinned_tag;
  char *os_release;
  Target this_target;
  gboolean this_offered;
  GPtrArray *others; /* Target* */
  int other_index;
  Mode mode;
  GPtrArray *presets;
  char *presets_key;
  char *preset_id;
  GHashTable *custom_checked;
  GPtrArray *custom_cards;
  char *base_dir;
  gboolean fell_back;

  GCancellable *load_cancel;
  guint load_generation;

  OtzJob *job;
  GPtrArray *job_ids;
  Target job_target;
  GCancellable *cancel;
  guint tick_id;
  gint64 started_us;
  Sample samples[MAX_SAMPLES];
  int sample_count;
  GHashTable *file_names;
  Status status;
  gboolean closing;
  gboolean quit_confirmed;

  gboolean succeeded;
  char *result_dir;
  GPtrArray *result_files, *result_unjoined, *result_notes;
  gboolean reveal_when_done;
  int exit_code;
};

static void show_page(Ui *ui);
static void go(Ui *ui, Page page);
static void next(Ui *ui);
static void back(Ui *ui);
static void load(Ui *ui);

/* ------------------------------------------------------------- targets */

static void target_set(Target *target, const char *platform, const char *architecture,
                       const char *format) {
  g_free(target->platform);
  g_free(target->architecture);
  g_free(target->format);
  target->platform = g_strdup(platform != NULL ? platform : "");
  target->architecture = g_strdup(architecture != NULL ? architecture : "");
  target->format = g_strdup(format != NULL ? format : "");
}

static void target_clear(Target *target) { target_set(target, NULL, NULL, NULL); }

static Target *target_new(const char *platform, const char *architecture,
                          const char *format) {
  Target *target = g_new0(Target, 1);
  target_set(target, platform, architecture, format);
  return target;
}

static void target_free(gpointer data) {
  Target *target = data;
  target_clear(target);
  g_free(target->platform);
  g_free(target->architecture);
  g_free(target->format);
  g_free(target);
}

static OtzTarget as_otz(const Target *target) {
  OtzTarget out = {target->platform, target->architecture, target->format};
  return out;
}

static gboolean target_offered(const OtzManifest *manifest, const Target *target) {
  OtzTarget t = as_otz(target);
  for (guint i = 0; i < manifest->components->len; i++) {
    if (otz_component_is_offered(manifest, g_ptr_array_index(manifest->components, i),
                                 &t))
      return TRUE;
  }
  return FALSE;
}

static gboolean target_equal(const Target *a, const Target *b) {
  return g_strcmp0(a->platform, b->platform) == 0 &&
         g_strcmp0(a->architecture, b->architecture) == 0 &&
         g_strcmp0(a->format, b->format) == 0;
}

static const Target *current_target(Ui *ui) {
  if (ui->mode == MODE_OTHER && ui->other_index >= 0 &&
      ui->other_index < (int)ui->others->len)
    return g_ptr_array_index(ui->others, ui->other_index);
  return &ui->this_target;
}

static gboolean contains(GPtrArray *array, const char *value) {
  return array != NULL && otz_string_array_contains(array, value);
}

/* This computer: Linux, its processor, its distribution's package format. */
static void compute_targets(Ui *ui) {
  g_autoptr(GPtrArray) archs = otz_architecture_choices(ui->manifest, "linux");
  const char *machine = otz_machine_architecture();
  const char *arch = contains(archs, machine) ? machine
                     : archs->len > 0         ? g_ptr_array_index(archs, 0)
                                              : "";
  g_autoptr(GPtrArray) formats = otz_package_format_choices(ui->manifest, "linux", arch);
  g_autofree char *format = otz_default_package_format(ui->os_release, formats);
  if (ui->snapshot)
    target_set(&ui->this_target, "linux", "x64", "deb");
  else
    target_set(&ui->this_target, "linux", arch, format);
  ui->this_offered = target_offered(ui->manifest, &ui->this_target);

  g_ptr_array_set_size(ui->others, 0);
  g_autoptr(GPtrArray) platforms = otz_platform_choices(ui->manifest);
  for (guint p = 0; p < platforms->len; p++) {
    const char *platform = g_ptr_array_index(platforms, p);
    g_autoptr(GPtrArray) architectures =
        otz_architecture_choices(ui->manifest, platform);
    if (architectures->len == 0) g_ptr_array_add(architectures, g_strdup(""));
    for (guint a = 0; a < architectures->len; a++) {
      const char *architecture = g_ptr_array_index(architectures, a);
      g_autoptr(GPtrArray) package_formats =
          otz_package_format_choices(ui->manifest, platform, architecture);
      if (package_formats->len == 0) g_ptr_array_add(package_formats, g_strdup(""));
      for (guint f = 0; f < package_formats->len; f++) {
        Target *target =
            target_new(platform, architecture, g_ptr_array_index(package_formats, f));
        if (target_offered(ui->manifest, target) &&
            !(ui->this_offered && target_equal(target, &ui->this_target)))
          g_ptr_array_add(ui->others, target);
        else
          target_free(target);
      }
    }
  }
}

static const char *format_name(const char *format) {
  if (strcmp(format, "deb") == 0) return otz_tr(S_FORMAT_DEB);
  if (strcmp(format, "rpm") == 0) return otz_tr(S_FORMAT_RPM);
  if (strcmp(format, OTZ_PORTABLE_PACKAGE_FORMAT) == 0) return otz_tr(S_FORMAT_PORTABLE);
  return format;
}

/* The processor is named only when it is ARM: Intel and AMD are almost all. */
static char *target_title(const Target *target) {
  const char *name = otz_platform_display_name(target->platform);
  return strcmp(target->architecture, "arm64") == 0 ? otz_trf(S_TARGET_ARM, name, NULL)
                                                    : g_strdup(name);
}

static const char *target_hint(const Target *target) {
  if (*target->format != '\0') return format_name(target->format);
  if (strcmp(target->platform, "macos") == 0) return otz_tr(S_HINT_MAC);
  if (strcmp(target->platform, "android") == 0) return otz_tr(S_HINT_ANDROID);
  if (strcmp(target->architecture, "arm64") == 0) return otz_tr(S_HINT_ARM);
  if (strcmp(target->architecture, "x64") == 0) return otz_tr(S_HINT_X64);
  return "";
}

static char *target_icon(const Target *target) {
  if (strcmp(target->format, "deb") == 0 || strcmp(target->format, "rpm") == 0 ||
      strcmp(target->format, OTZ_PORTABLE_PACKAGE_FORMAT) == 0)
    return g_strconcat("fmt_", target->format, NULL);
  return g_strdup(target->platform);
}

static char *this_description(Ui *ui) {
  const char *format = ui->this_target.format;
  const char *kind = strcmp(format, "deb") == 0   ? otz_tr(S_THIS_DEB)
                     : strcmp(format, "rpm") == 0 ? otz_tr(S_THIS_RPM)
                                                  : otz_tr(S_THIS_PORTABLE);
  g_autofree char *what = strcmp(ui->this_target.architecture, "arm64") == 0
                              ? otz_trf(S_THIS_ARM, kind, NULL)
                              : g_strdup(kind);
  return otz_trf(S_MODE_THIS_DESC, what, NULL);
}

/* "Windows, macOS או Android" — from the list itself. */
static char *others_summary(Ui *ui) {
  g_autoptr(GPtrArray) names = g_ptr_array_new();
  for (guint i = 0; i < ui->others->len; i++) {
    const Target *target = g_ptr_array_index(ui->others, i);
    const char *name = otz_platform_display_name(target->platform);
    if (!contains(names, name)) g_ptr_array_add(names, (gpointer)name);
  }
  if (names->len == 0) return g_strdup("");
  if (names->len == 1) return g_strdup(g_ptr_array_index(names, 0));
  const char *last = g_ptr_array_index(names, names->len - 1);
  g_ptr_array_set_size(names, names->len - 1);
  g_ptr_array_add(names, NULL);
  g_autofree char *head = g_strjoinv(", ", (char **)names->pdata);
  return otz_trf(S_LIST_OR, head, last, NULL);
}

static char *version_label(Ui *ui) {
  if (ui->manifest == NULL || *ui->manifest->release_version == '\0') return NULL;
  g_autofree char *version = otz_ltr(ui->manifest->release_version);
  return otz_trf(S_OTZARIA_VERSION, version, NULL);
}

/* ------------------------------------------------------------- presets */

static const char *preset_title(const char *id) {
  if (strcmp(id, "full-indexed") == 0) return otz_tr(S_PRESET_FULL_INDEXED);
  if (strcmp(id, "full") == 0) return otz_tr(S_PRESET_FULL);
  if (strcmp(id, "basic") == 0) return otz_tr(S_PRESET_BASIC);
  if (strcmp(id, "update") == 0) return otz_tr(S_PRESET_UPDATE);
  return otz_tr(S_PRESET_CUSTOM);
}

static const char *preset_description(const char *id) {
  if (strcmp(id, "full-indexed") == 0) return otz_tr(S_PRESET_FULL_INDEXED_DESC);
  if (strcmp(id, "full") == 0) return otz_tr(S_PRESET_FULL_DESC);
  if (strcmp(id, "basic") == 0) return otz_tr(S_PRESET_BASIC_DESC);
  if (strcmp(id, "update") == 0) return otz_tr(S_PRESET_UPDATE_DESC);
  return otz_tr(S_PRESET_CUSTOM_DESC);
}

/* ico_preset_<id>, with "_" for "-", like UiOptionIcon. */
static char *preset_icon(const char *id) {
  g_autofree char *name = g_strconcat("preset_", id, NULL);
  return g_strdelimit(g_steal_pointer(&name), "-", '_');
}

static const OtzPreset *find_preset(Ui *ui, const char *id) {
  for (guint i = 0; ui->presets != NULL && i < ui->presets->len; i++) {
    const OtzPreset *preset = g_ptr_array_index(ui->presets, i);
    if (strcmp(preset->id, id) == 0) return preset;
  }
  return NULL;
}

static void build_presets(Ui *ui) {
  OtzTarget target = as_otz(current_target(ui));
  g_autofree char *key = g_strjoin("/", target.platform, target.architecture,
                                   target.package_format, NULL);
  if (g_strcmp0(key, ui->presets_key) != 0) {
    g_hash_table_remove_all(ui->custom_checked);
    g_free(ui->presets_key);
    ui->presets_key = g_strdup(key);
  }
  g_clear_pointer(&ui->presets, g_ptr_array_unref);
  ui->presets = otz_build_presets(ui->manifest, &target);
  if (ui->preset_id == NULL ||
      (strcmp(ui->preset_id, CUSTOM_ID) != 0 && find_preset(ui, ui->preset_id) == NULL)) {
    int index = otz_default_preset_index(ui->presets);
    g_free(ui->preset_id);
    ui->preset_id = g_strdup(
        index >= 0 ? ((OtzPreset *)g_ptr_array_index(ui->presets, index))->id : CUSTOM_ID);
  }
}

/* Locked, required, and in the radio group what the default preset had —
 * otherwise the installer. */
static void default_custom_checked(Ui *ui) {
  OtzTarget target = as_otz(current_target(ui));
  g_autoptr(GPtrArray) choices = otz_custom_choices(ui->manifest, &target);
  int index = otz_default_preset_index(ui->presets);
  GPtrArray *previous =
      index >= 0 ? ((OtzPreset *)g_ptr_array_index(ui->presets, index))->members : NULL;
  const OtzCustomChoice *pick = NULL, *application = NULL, *first = NULL;
  for (guint i = 0; i < choices->len; i++) {
    const OtzCustomChoice *choice = g_ptr_array_index(choices, i);
    if (*choice->group == '\0') {
      if (choice->locked || choice->component->required)
        g_hash_table_add(ui->custom_checked, g_strdup(choice->component->id));
      continue;
    }
    if (choice->locked)
      g_hash_table_add(ui->custom_checked, g_strdup(choice->component->id));
    if (first == NULL) first = choice;
    if (application == NULL && strcmp(choice->component->type, "application") == 0)
      application = choice;
    if (pick == NULL && contains(previous, choice->component->id)) pick = choice;
  }
  if (pick == NULL) pick = application != NULL ? application : first;
  if (pick != NULL) g_hash_table_add(ui->custom_checked, g_strdup(pick->component->id));
}

/* A radio clears its group; checking pulls in dependencies (index → library),
 * clearing drops what depends on the row. */
static void set_custom(Ui *ui, const char *id, gboolean checked) {
  OtzTarget target = as_otz(current_target(ui));
  g_autoptr(GPtrArray) choices = otz_custom_choices(ui->manifest, &target);
  const OtzCustomChoice *choice = NULL;
  for (guint i = 0; i < choices->len; i++) {
    const OtzCustomChoice *candidate = g_ptr_array_index(choices, i);
    if (strcmp(candidate->component->id, id) == 0) choice = candidate;
  }
  if (choice == NULL || choice->locked) return;
  if (checked) {
    for (guint i = 0; *choice->group != '\0' && i < choices->len; i++) {
      const OtzCustomChoice *other = g_ptr_array_index(choices, i);
      if (strcmp(other->group, choice->group) == 0)
        g_hash_table_remove(ui->custom_checked, other->component->id);
    }
    g_hash_table_add(ui->custom_checked, g_strdup(id));
    for (guint i = 0; i < choices->len; i++) {
      const OtzCustomChoice *other = g_ptr_array_index(choices, i);
      if (*other->group == '\0' &&
          otz_string_array_contains(choice->component->depends_on, other->component->id))
        g_hash_table_add(ui->custom_checked, g_strdup(other->component->id));
    }
  } else if (*choice->group == '\0') {
    g_hash_table_remove(ui->custom_checked, id);
    for (guint i = 0; i < choices->len; i++) {
      const OtzCustomChoice *other = g_ptr_array_index(choices, i);
      if (otz_string_array_contains(other->component->depends_on, id))
        g_hash_table_remove(ui->custom_checked, other->component->id);
    }
  }
}

static GPtrArray *selected_ids(Ui *ui) {
  OtzTarget target = as_otz(current_target(ui));
  const OtzPreset *preset = find_preset(ui, ui->preset_id != NULL ? ui->preset_id : "");
  if (preset != NULL) return otz_with_dependencies(ui->manifest, preset->members, &target);
  g_autoptr(GPtrArray) checked = g_ptr_array_new();
  for (guint i = 0; i < ui->manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(ui->manifest->components, i);
    if (g_hash_table_contains(ui->custom_checked, component->id))
      g_ptr_array_add(checked, component->id);
  }
  return otz_with_dependencies(ui->manifest, checked, &target);
}

/* ------------------------------------------------------------- steps */

static gboolean step_of(Ui *ui, int *current, int *total) {
  *total = ui->mode == MODE_OTHER ? 6 : 5;
  switch (ui->page_id) {
    case PAGE_MODE: *current = 1; return TRUE;
    case PAGE_OTHER: *current = 2; return TRUE;
    case PAGE_PRESETS:
    case PAGE_CUSTOM: *current = ui->mode == MODE_OTHER ? 3 : 2; return TRUE;
    case PAGE_FOLDER: *current = *total - 2; return TRUE;
    case PAGE_READY: *current = *total - 1; return TRUE;
    case PAGE_WORKING: *current = *total; return TRUE;
    default: return FALSE;
  }
}

static gboolean can_go_back(Ui *ui) {
  return ui->history->len > 0 &&
         (ui->page_id == PAGE_MODE || ui->page_id == PAGE_OTHER ||
          ui->page_id == PAGE_PRESETS || ui->page_id == PAGE_CUSTOM ||
          ui->page_id == PAGE_FOLDER || ui->page_id == PAGE_READY);
}

/* ------------------------------------------------------------- dialog */

typedef struct {
  Ui *ui;
  UiAction action;
} ActionData;

static void free_action(gpointer data, GClosure *closure) { g_free(data); }

static void run_action(GtkButton *button, gpointer data) {
  ActionData *action = data;
  action->action(action->ui);
}

static GtkWidget *action_button(Ui *ui, OtzButtonKind kind, const char *text, int width,
                                int height, UiAction action) {
  GtkWidget *button = otz_button(kind, text, width, height);
  ActionData *data = g_new0(ActionData, 1);
  data->ui = ui;
  data->action = action;
  g_signal_connect_data(button, "clicked", G_CALLBACK(run_action), data,
                        free_action, 0);
  return button;
}

static void close_dialog(Ui *ui) {
  if (!ui->dialog_open) return;
  ui->dialog_open = FALSE;
  gtk_widget_destroy(ui->dialog);
  gtk_widget_destroy(ui->shade);
  ui->dialog = ui->shade = NULL;
  gtk_widget_set_sensitive(ui->scroll, TRUE);
  if (ui->focus != NULL) gtk_widget_grab_focus(ui->focus);
}

static void dialog_keep(Ui *ui) { close_dialog(ui); }

static void dialog_run(Ui *ui) {
  UiAction action = ui->dialog_confirm;
  close_dialog(ui);
  if (action != NULL) action(ui);
}

typedef struct {
  const char *text;
  OtzButtonKind kind;
  UiAction action;
} DialogButton;

/* A themed card over a 13% shade, like UiAsk; the page beneath is insensitive.
 * Buttons in reading order, at the trailing edge. */
static void show_dialog(Ui *ui, const char *title, const char *text,
                        const DialogButton *buttons, int count, int default_index,
                        UiAction cancel) {
  close_dialog(ui);
  ui->dialog_open = TRUE;
  gtk_widget_set_sensitive(ui->scroll, FALSE);
  ui->shade = otz_shade();
  gtk_overlay_add_overlay(GTK_OVERLAY(ui->overlay), ui->shade);
  ui->dialog = otz_dialog_card();
  int inset = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(ui->dialog), "otz-inset"));
  GtkWidget *content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_margin_start(content, inset - OTZ_RING);
  gtk_widget_set_margin_end(content, inset - OTZ_RING);
  gtk_widget_set_margin_top(content, inset);
  gtk_widget_set_margin_bottom(content, inset - OTZ_RING);
  int width = 336 - 48;
  GtkWidget *heading = otz_wrap_label(title, "t-dialog-title", width, 0);
  gtk_box_pack_start(GTK_BOX(content), heading, FALSE, FALSE, 0);
  GtkWidget *body = otz_wrap_label(text, "t-dialog-text", width, 0);
  gtk_widget_set_margin_top(body, 12);
  gtk_box_pack_start(GTK_BOX(content), body, FALSE, FALSE, 0);
  GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_set_margin_top(row, 24 - OTZ_RING);
  gtk_box_pack_start(GTK_BOX(row), gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0), TRUE, TRUE, 0);
  GtkWidget *focus = NULL;
  for (int i = 0; i < count; i++) {
    GtkWidget *button =
        action_button(ui, buttons[i].kind, buttons[i].text, -1, 40, buttons[i].action);
    gtk_box_pack_start(GTK_BOX(row), button, FALSE, FALSE, 0);
    if (i == default_index) focus = button;
  }
  gtk_box_pack_start(GTK_BOX(content), row, FALSE, FALSE, 0);
  gtk_container_add(GTK_CONTAINER(ui->dialog), content);
  gtk_overlay_add_overlay(GTK_OVERLAY(ui->overlay), ui->dialog);
  ui->dialog_default = buttons[default_index].action;
  ui->dialog_cancel = cancel;
  otz_accessible(ui->dialog, title, text);
  gtk_widget_show_all(ui->shade);
  gtk_widget_show_all(ui->dialog);
  if (focus != NULL) gtk_widget_grab_focus(focus);
}

static void tell(Ui *ui, const char *title, const char *text) {
  const DialogButton ok = {otz_tr(S_OK), OTZ_BUTTON_PRIMARY, dialog_keep};
  show_dialog(ui, title, text, &ok, 1, 0, dialog_keep);
}

/* When the action destroys something, "keep" is the filled default (and Esc);
 * otherwise "confirm" is, like on Windows. */
static void ask(Ui *ui, const char *title, const char *text, const char *confirm,
                const char *keep, gboolean destructive, UiAction on_confirm) {
  ui->dialog_confirm = on_confirm;
  if (destructive) {
    const DialogButton buttons[] = {{keep, OTZ_BUTTON_PRIMARY, dialog_keep},
                                    {confirm, OTZ_BUTTON_DANGER, dialog_run}};
    show_dialog(ui, title, text, buttons, 2, 0, dialog_keep);
  } else {
    const DialogButton buttons[] = {{keep, OTZ_BUTTON_GHOST, dialog_keep},
                                    {confirm, OTZ_BUTTON_PRIMARY, dialog_run}};
    show_dialog(ui, title, text, buttons, 2, 1, dialog_keep);
  }
  ui->dialog_confirm = on_confirm;
}

/* ------------------------------------------------------------- frame */

typedef struct {
  GtkWidget *page, *content, *footer;
} Frame;

static Frame frame_new(Ui *ui, const char *title, const char *desc, const char *hint,
                       gboolean scrolls) {
  Frame frame;
  frame.page = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  GtkWidget *steps = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  gtk_widget_set_size_request(steps, -1, 44);
  int current, total;
  if (step_of(ui, &current, &total)) {
    GtkWidget *dots = otz_step_dots(current, total);
    gtk_widget_set_margin_top(dots, 12);
    gtk_box_pack_start(GTK_BOX(steps), dots, FALSE, FALSE, 0);
    g_autofree char *a = g_strdup_printf("%d", current);
    g_autofree char *b = g_strdup_printf("%d", total);
    g_autofree char *text = otz_trf(S_STEP_OF, a, b, NULL);
    gtk_box_pack_start(GTK_BOX(steps), otz_label(text, "t-step"), FALSE, FALSE, 0);
  }
  gtk_box_pack_start(GTK_BOX(frame.page), steps, FALSE, FALSE, 0);

  GtkWidget *header = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_margin_top(header, 6);
  GtkWidget *title_label = otz_wrap_label(title, "t-title", OTZ_CONTENT_WIDTH, 0.5f);
  gtk_box_pack_start(GTK_BOX(header), title_label, FALSE, FALSE, 0);
  GtkWidget *desc_label = NULL;
  if (desc != NULL && *desc != '\0') {
    desc_label = otz_wrap_label(desc, "t-desc", OTZ_CONTENT_WIDTH, 0.5f);
    gtk_widget_set_margin_top(desc_label, 8);
    gtk_box_pack_start(GTK_BOX(header), desc_label, FALSE, FALSE, 0);
  }
  if (hint != NULL && *hint != '\0') {
    GtkWidget *hint_label = otz_wrap_label(hint, "t-hint", OTZ_CONTENT_WIDTH, 0.5f);
    gtk_widget_set_margin_top(hint_label, 6);
    gtk_box_pack_start(GTK_BOX(header), hint_label, FALSE, FALSE, 0);
  }
  gtk_box_pack_start(GTK_BOX(frame.page), header, FALSE, FALSE, 0);
  ui->w_title = title_label;
  ui->w_desc = desc_label;

  frame.content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10 - 2 * OTZ_RING);
  gtk_widget_set_size_request(frame.content, OTZ_CONTENT_WIDTH + 2 * OTZ_RING, -1);
  gtk_widget_set_halign(frame.content, GTK_ALIGN_CENTER);
  gtk_widget_set_margin_top(frame.content, 16 - OTZ_RING);
  gtk_widget_set_margin_bottom(frame.content, 16 - OTZ_RING);
  if (scrolls) {
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll), GTK_POLICY_NEVER,
                                   GTK_POLICY_AUTOMATIC);
    gtk_scrolled_window_set_overlay_scrolling(GTK_SCROLLED_WINDOW(scroll), FALSE);
    gtk_container_add(GTK_CONTAINER(scroll), frame.content);
    gtk_container_set_focus_vadjustment(
        GTK_CONTAINER(frame.content),
        gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(scroll)));
    gtk_box_pack_start(GTK_BOX(frame.page), scroll, TRUE, TRUE, 0);
  } else {
    gtk_box_pack_start(GTK_BOX(frame.page), frame.content, TRUE, TRUE, 0);
    gtk_widget_set_valign(frame.content, GTK_ALIGN_START);
  }
  gtk_box_pack_start(GTK_BOX(frame.page), otz_divider(), FALSE, FALSE, 0);
  frame.footer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  gtk_widget_set_size_request(frame.footer, -1, 71);
  gtk_widget_set_margin_start(frame.footer, 24 - OTZ_RING);
  gtk_widget_set_margin_end(frame.footer, 24 - OTZ_RING);
  gtk_box_pack_start(GTK_BOX(frame.page), frame.footer, FALSE, FALSE, 0);
  return frame;
}

/* "Back" where reading starts, the primary action at the other end (Return). */
static void nav_footer(Ui *ui, Frame *frame, const char *primary_text) {
  GtkWidget *back_button = action_button(ui, OTZ_BUTTON_GHOST, otz_tr(S_BACK), 120, 40, back);
  if (!can_go_back(ui)) {
    gtk_widget_set_opacity(back_button, 0);
    gtk_widget_set_sensitive(back_button, FALSE);
  }
  gtk_box_pack_start(GTK_BOX(frame->footer), back_button, FALSE, FALSE, 0);
  GtkWidget *primary = action_button(ui, OTZ_BUTTON_PRIMARY,
                                     primary_text != NULL ? primary_text : otz_tr(S_NEXT),
                                     160, 40, next);
  gtk_box_pack_end(GTK_BOX(frame->footer), primary, FALSE, FALSE, 0);
  ui->primary = next;
  ui->escape = can_go_back(ui) ? back : NULL;
  if (ui->focus == NULL) ui->focus = primary;
}

/* One tonal button at the trailing edge (stop connecting, stop download); Esc. */
static void trailing_footer(Ui *ui, Frame *frame, const char *text, UiAction action) {
  GtkWidget *button = action_button(ui, OTZ_BUTTON_TONAL, text, 120, 40, action);
  gtk_box_pack_end(GTK_BOX(frame->footer), button, FALSE, FALSE, 0);
  ui->primary = NULL;
  ui->escape = action;
  if (ui->focus == NULL) ui->focus = button;
}

static void add_content(Frame *frame, GtkWidget *child) {
  gtk_box_pack_start(GTK_BOX(frame->content), child, FALSE, FALSE, 0);
}

/* ------------------------------------------------------------- welcome */

static double ease_in_out(double value) {
  double p = CLAMP(value, 0, 1);
  return p < 0.5 ? 4 * p * p * p : 1 - pow(2 - 2 * p, 3) / 2;
}

static double ease_out(double value) {
  double p = CLAMP(value, 0, 1);
  return 1 - pow(1 - p, 3);
}

static double hero_elapsed(Ui *ui) {
  if (ui->hero_preview_ms >= 0) return ui->hero_preview_ms;
  if (ui->hero_played) return HERO_END_MS;
  if (ui->hero_start_us == 0) return 0;
  return (g_get_monotonic_time() - ui->hero_start_us) / 1000.0;
}

static void begin(Ui *ui);

static void hero_finish(Ui *ui) {
  ui->hero_played = TRUE;
  if (ui->hero == NULL) return;
  gtk_widget_queue_draw(ui->hero);
  gtk_widget_set_opacity(ui->hero_note, 1);
  gtk_widget_set_opacity(ui->hero_start, 1);
  gtk_widget_set_sensitive(ui->hero_start, TRUE);
  ui->primary = begin;
  ui->focus = ui->hero_start;
  gtk_widget_grab_focus(ui->hero_start);
}

static void draw_text(cairo_t *cr, GtkWidget *widget, const char *text, double size,
                      PangoWeight weight, double y, double r, double g, double b,
                      double alpha, double *height) {
  PangoLayout *layout = gtk_widget_create_pango_layout(widget, text);
  PangoFontDescription *font =
      pango_font_description_copy(pango_context_get_font_description(
          pango_layout_get_context(layout)));
  pango_font_description_set_absolute_size(font, size * PANGO_SCALE);
  pango_font_description_set_weight(font, weight);
  pango_layout_set_font_description(layout, font);
  pango_layout_set_width(layout, OTZ_CONTENT_WIDTH * PANGO_SCALE);
  pango_layout_set_alignment(layout, PANGO_ALIGN_CENTER);
  int w, h;
  pango_layout_get_pixel_size(layout, &w, &h);
  cairo_move_to(cr, (OTZ_WINDOW_WIDTH - OTZ_CONTENT_WIDTH) / 2.0, y);
  cairo_set_source_rgba(cr, r, g, b, alpha);
  pango_cairo_show_layout(cr, layout);
  pango_font_description_free(font);
  g_object_unref(layout);
  *height = h;
}

/* A line, a diamond and a line in gold, under the title. */
static void draw_ornament(cairo_t *cr, double y, double alpha) {
  double cx = OTZ_WINDOW_WIDTH / 2.0, cy = y + 4;
  double gold[3] = {0xB4 / 255.0, 0x8A / 255.0, 0x3E / 255.0};
  for (int side = -1; side <= 1; side += 2) {
    double inner = cx + side * 9, outer = cx + side * 35;
    cairo_pattern_t *fade = cairo_pattern_create_linear(outer, 0, inner, 0);
    cairo_pattern_add_color_stop_rgba(fade, 0, gold[0], gold[1], gold[2], 0);
    cairo_pattern_add_color_stop_rgba(fade, 1, gold[0], gold[1], gold[2], alpha);
    cairo_rectangle(cr, MIN(inner, outer), cy - 0.5, 26, 1);
    cairo_set_source(cr, fade);
    cairo_fill(cr);
    cairo_pattern_destroy(fade);
  }
  cairo_move_to(cr, cx, cy - 3.5);
  cairo_line_to(cr, cx + 3.5, cy);
  cairo_line_to(cr, cx, cy + 3.5);
  cairo_line_to(cr, cx - 3.5, cy);
  cairo_close_path(cr);
  cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], alpha);
  cairo_fill(cr);
}

static gboolean draw_hero(GtkWidget *area, cairo_t *cr, Ui *ui) {
  double elapsed = hero_elapsed(ui);
  gboolean done = elapsed >= HERO_END_MS;
  double t = elapsed - HERO_FADE_MS;
  int frame = done ? OTZ_BOOK_FRAMES - 1 : (int)CLAMP(t / HERO_FRAME_MS, 0, OTZ_BOOK_FRAMES - 1);
  double rise = done ? 1 : ease_in_out((t - HERO_RISE_START) / HERO_RISE_MS);
  cairo_surface_t *book = otz_book_frame(frame);
  if (book != NULL) {
    cairo_set_source_surface(cr, book, (OTZ_WINDOW_WIDTH - 220) / 2.0, 204 - 130 * rise);
    cairo_paint_with_alpha(cr, done ? 1 : ease_in_out(elapsed / HERO_FADE_MS));
  }
  double progress = (t - HERO_TITLE_START) / HERO_TITLE_FADE_MS;
  double alpha = done ? 1 : CLAMP(progress, 0, 1);
  if (alpha > 0) {
    double y = (book != NULL ? 325 : 230) + (done ? 0 : 8 * (1 - ease_out(progress)));
    double h;
    draw_text(cr, area, otz_tr(S_APP_TITLE), 24, PANGO_WEIGHT_SEMIBOLD, y,
              0x20 / 255.0, 0x1B / 255.0, 0x13 / 255.0, alpha, &h);
    y += h + 6;
    draw_ornament(cr, y, alpha);
    y += 8 + 6;
    draw_text(cr, area, otz_tr(S_WELCOME_SUBTITLE), 16, PANGO_WEIGHT_NORMAL, y,
              0x4F / 255.0, 0x45 / 255.0, 0x39 / 255.0, alpha, &h);
  }
  return TRUE;
}

static gboolean tick_hero(GtkWidget *area, GdkFrameClock *clock, gpointer data) {
  Ui *ui = data;
  gtk_widget_queue_draw(area);
  if (ui->hero_start_us != 0 && hero_elapsed(ui) >= HERO_END_MS) {
    hero_finish(ui);
    return G_SOURCE_REMOVE;
  }
  return ui->hero_played ? G_SOURCE_REMOVE : G_SOURCE_CONTINUE;
}

static gboolean on_hero_click(GtkWidget *area, GdkEventButton *event, Ui *ui) {
  if (!ui->hero_played) hero_finish(ui);
  return TRUE;
}

static void on_book_ready(gpointer data) {
  Ui *ui = data;
  if (!ui->hero_played && ui->hero_start_us == 0)
    ui->hero_start_us = g_get_monotonic_time();
  if (!otz_book_ready() && !ui->hero_played) hero_finish(ui);
}

static GtkWidget *welcome_page(Ui *ui) {
  GtkWidget *overlay = gtk_overlay_new();
  ui->hero = gtk_drawing_area_new();
  gtk_widget_set_size_request(ui->hero, OTZ_WINDOW_WIDTH, OTZ_CONTENT_HEIGHT);
  gtk_widget_add_events(ui->hero, GDK_BUTTON_PRESS_MASK);
  g_signal_connect(ui->hero, "draw", G_CALLBACK(draw_hero), ui);
  g_signal_connect(ui->hero, "button-press-event", G_CALLBACK(on_hero_click), ui);
  g_autofree char *name =
      g_strdup_printf("%s — %s", otz_tr(S_APP_TITLE), otz_tr(S_WELCOME_SUBTITLE));
  otz_accessible(ui->hero, name, NULL);
  gtk_container_add(GTK_CONTAINER(overlay), ui->hero);

  ui->hero_note = otz_wrap_label(otz_tr(S_WELCOME_NOTE), "t-hero-note",
                                 OTZ_CONTENT_WIDTH - 32, 0.5f);
  gtk_widget_set_valign(ui->hero_note, GTK_ALIGN_START);
  gtk_widget_set_margin_top(ui->hero_note, 496);
  gtk_overlay_add_overlay(GTK_OVERLAY(overlay), ui->hero_note);
  gtk_overlay_set_overlay_pass_through(GTK_OVERLAY(overlay), ui->hero_note, TRUE);
  ui->hero_start = action_button(ui, OTZ_BUTTON_PRIMARY, otz_tr(S_START_BUTTON),
                                 OTZ_CONTENT_WIDTH, 44, begin);
  gtk_widget_set_valign(ui->hero_start, GTK_ALIGN_START);
  gtk_widget_set_margin_top(ui->hero_start, 566 - OTZ_RING);
  gtk_overlay_add_overlay(GTK_OVERLAY(overlay), ui->hero_start);

  if (ui->hero_played) {
    ui->primary = begin;
    ui->focus = ui->hero_start;
  } else {
    gtk_widget_set_opacity(ui->hero_note, 0);
    gtk_widget_set_opacity(ui->hero_start, 0);
    gtk_widget_set_sensitive(ui->hero_start, FALSE);
    ui->primary = hero_finish;
    if (ui->hero_preview_ms < 0)
      gtk_widget_add_tick_callback(ui->hero, tick_hero, ui, NULL);
  }
  ui->escape = NULL;
  return overlay;
}

/* ------------------------------------------------------------- choices */

static void on_mode(GtkToggleButton *card, Ui *ui) {
  if (ui->building || !gtk_toggle_button_get_active(card)) return;
  ui->mode = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(card), "otz-value"));
}

static void on_other(GtkToggleButton *card, Ui *ui) {
  if (ui->building || !gtk_toggle_button_get_active(card)) return;
  ui->other_index = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(card), "otz-value"));
}

static void on_preset(GtkToggleButton *card, Ui *ui) {
  if (ui->building || !gtk_toggle_button_get_active(card)) return;
  g_free(ui->preset_id);
  ui->preset_id = g_strdup(g_object_get_data(G_OBJECT(card), "otz-id"));
}

static GtkWidget *radio_card(Ui *ui, Frame *frame, GSList **group,
                             const OtzCardSpec *spec, gboolean selected,
                             GCallback on_toggled, int value) {
  GtkWidget *card = otz_card(spec, group);
  g_object_set_data(G_OBJECT(card), "otz-value", GINT_TO_POINTER(value));
  if (selected) {
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(card), TRUE);
    ui->focus = card;
  }
  g_signal_connect(card, "toggled", on_toggled, ui);
  add_content(frame, card);
  return card;
}

/* GTK always has one radio active; this unseen one stands for "none yet". */
static GSList *unselected_group(GtkWidget *page) {
  GtkWidget *none = gtk_radio_button_new(NULL);
  g_object_ref_sink(none);
  g_object_set_data_full(G_OBJECT(page), "otz-none", none,
                         (GDestroyNotify)gtk_widget_destroy);
  return gtk_radio_button_get_group(GTK_RADIO_BUTTON(none));
}

static GtkWidget *mode_page(Ui *ui) {
  g_autofree char *version = version_label(ui);
  g_autofree char *hint =
      version != NULL ? otz_trf(S_VERSION_TO_DOWNLOAD, version, NULL) : NULL;
  Frame frame = frame_new(ui, otz_tr(S_MODE_TITLE), otz_tr(S_MODE_DESC), hint, TRUE);
  GSList *group = NULL;
  ui->building = TRUE;
  GtkWidget *first = NULL;
  if (ui->this_offered) {
    g_autofree char *desc = this_description(ui);
    OtzCardSpec spec = {.title = otz_tr(S_MODE_THIS), .desc = desc, .icon = "this_pc"};
    first = radio_card(ui, &frame, &group, &spec, ui->mode == MODE_THIS,
                       G_CALLBACK(on_mode), MODE_THIS);
  }
  g_autofree char *summary = others_summary(ui);
  g_autofree char *other_desc = otz_trf(S_MODE_OTHER_DESC, summary, NULL);
  OtzCardSpec other = {.title = otz_tr(S_MODE_OTHER), .desc = other_desc, .icon = "other_pc"};
  GtkWidget *second = radio_card(ui, &frame, &group, &other, ui->mode == MODE_OTHER,
                                 G_CALLBACK(on_mode), MODE_OTHER);
  ui->building = FALSE;
  if (ui->focus == NULL) ui->focus = first != NULL ? first : second;
  nav_footer(ui, &frame, NULL);
  return frame.page;
}

static GtkWidget *other_page(Ui *ui) {
  Frame frame = frame_new(ui, otz_tr(S_OTHER_TITLE), otz_tr(S_OTHER_DESC),
                          otz_tr(S_OTHER_HINT), TRUE);
  GSList *group = unselected_group(frame.page);
  ui->building = TRUE;
  GtkWidget *first = NULL;
  for (guint i = 0; i < ui->others->len; i++) {
    const Target *target = g_ptr_array_index(ui->others, i);
    g_autofree char *title = target_title(target);
    g_autofree char *icon = target_icon(target);
    OtzCardSpec spec = {.title = title, .desc = target_hint(target), .icon = icon};
    GtkWidget *card = radio_card(ui, &frame, &group, &spec, ui->other_index == (int)i,
                                 G_CALLBACK(on_other), (int)i);
    if (first == NULL) first = card;
  }
  ui->building = FALSE;
  if (ui->focus == NULL) ui->focus = first;
  nav_footer(ui, &frame, NULL);
  return frame.page;
}

static GtkWidget *presets_page(Ui *ui) {
  Frame frame = frame_new(ui, otz_tr(S_PRESET_TITLE), otz_tr(S_PRESET_DESC),
                          otz_tr(S_PRESET_HINT), TRUE);
  GSList *group = NULL;
  ui->building = TRUE;
  for (guint i = 0; i <= ui->presets->len; i++) {
    const OtzPreset *preset =
        i < ui->presets->len ? g_ptr_array_index(ui->presets, i) : NULL;
    const char *id = preset != NULL ? preset->id : CUSTOM_ID;
    g_autofree char *size = NULL, *side = NULL;
    if (preset != NULL) {
      size = otz_size_text(otz_members_download_size(ui->manifest, preset->members));
      side = otz_trf(S_CARD_SIZE, size, NULL);
    }
    g_autofree char *icon = preset_icon(id);
    OtzCardSpec spec = {.title = preset_title(id), .desc = preset_description(id),
                        .side = side, .icon = icon};
    GtkWidget *card = radio_card(ui, &frame, &group, &spec,
                                 g_strcmp0(ui->preset_id, id) == 0,
                                 G_CALLBACK(on_preset), (int)i);
    g_object_set_data_full(G_OBJECT(card), "otz-id", g_strdup(id), g_free);
  }
  ui->building = FALSE;
  nav_footer(ui, &frame, NULL);
  return frame.page;
}

static void sync_custom(Ui *ui) {
  ui->building = TRUE;
  for (guint i = 0; i < ui->custom_cards->len; i++) {
    GtkWidget *card = g_ptr_array_index(ui->custom_cards, i);
    const char *id = g_object_get_data(G_OBJECT(card), "otz-id");
    gboolean on = g_hash_table_contains(ui->custom_checked, id);
    if (gtk_widget_is_sensitive(card) || on)
      gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(card), on);
  }
  ui->building = FALSE;
}

static void on_custom(GtkToggleButton *card, Ui *ui) {
  if (ui->building) return;
  gboolean active = gtk_toggle_button_get_active(card);
  if (GTK_IS_RADIO_BUTTON(card) && !active) return;
  set_custom(ui, g_object_get_data(G_OBJECT(card), "otz-id"), active);
  sync_custom(ui);
}

static GtkWidget *custom_page(Ui *ui) {
  Frame frame = frame_new(ui, otz_tr(S_PRESET_CUSTOM), otz_tr(S_CUSTOM_DESC),
                          otz_tr(S_CUSTOM_HINT), TRUE);
  OtzTarget target = as_otz(current_target(ui));
  g_autoptr(GPtrArray) choices = otz_custom_choices(ui->manifest, &target);
  g_ptr_array_set_size(ui->custom_cards, 0);
  GSList *group = NULL;
  ui->building = TRUE;
  for (guint i = 0; i < choices->len; i++) {
    const OtzCustomChoice *choice = g_ptr_array_index(choices, i);
    const OtzComponent *component = choice->component;
    gboolean radio = *choice->group != '\0';
    gboolean required = choice->locked || (component->required && !radio);
    const char *name = otz_component_name(component, ui->english);
    g_autofree char *title =
        required ? g_strconcat(name, " ", otz_tr(S_REQUIRED_TAG), NULL) : g_strdup(name);
    g_autofree char *size =
        otz_size_text(otz_custom_choice_size(ui->manifest, component, &target));
    g_autofree char *side = otz_trf(S_CARD_SIZE, size, NULL);
    OtzCardSpec spec = {.title = title,
                        .desc = otz_component_description(component, ui->english),
                        .side = side,
                        .icon = "component",
                        .check = !radio,
                        .locked = choice->locked};
    GtkWidget *card = otz_card(&spec, radio ? &group : NULL);
    g_object_set_data_full(G_OBJECT(card), "otz-id", g_strdup(component->id), g_free);
    g_ptr_array_add(ui->custom_cards, card);
    add_content(&frame, card);
  }
  ui->building = FALSE;
  sync_custom(ui);
  for (guint i = 0; i < ui->custom_cards->len; i++) {
    GtkWidget *card = g_ptr_array_index(ui->custom_cards, i);
    g_signal_connect(card, "toggled", G_CALLBACK(on_custom), ui);
    if (ui->focus == NULL && gtk_widget_is_sensitive(card)) ui->focus = card;
  }
  nav_footer(ui, &frame, NULL);
  return frame.page;
}

/* ------------------------------------------------------------- folder */

static void choose_folder(Ui *ui) {
  GtkFileChooserNative *chooser = gtk_file_chooser_native_new(
      otz_tr(S_FOLDER_TITLE), GTK_WINDOW(ui->window), GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER,
      otz_tr(S_CHOOSE), otz_tr(S_CANCEL));
  gtk_file_chooser_set_create_folders(GTK_FILE_CHOOSER(chooser), TRUE);
  if (ui->base_dir != NULL && g_file_test(ui->base_dir, G_FILE_TEST_IS_DIR))
    gtk_file_chooser_set_current_folder(GTK_FILE_CHOOSER(chooser), ui->base_dir);
  if (gtk_native_dialog_run(GTK_NATIVE_DIALOG(chooser)) == GTK_RESPONSE_ACCEPT) {
    g_autofree char *folder = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(chooser));
    if (folder != NULL) {
      g_free(ui->base_dir);
      ui->base_dir = g_steal_pointer(&folder);
      ui->fell_back = FALSE;
      show_page(ui);
    }
  }
  g_object_unref(chooser);
}

static GtkWidget *folder_page(Ui *ui) {
  if (ui->base_dir == NULL) {
    ui->base_dir = otz_default_output_dir(ui->english, &ui->fell_back);
    if (ui->options->dev_output != NULL) {
      g_free(ui->base_dir);
      ui->base_dir = g_strdup(ui->options->dev_output);
      ui->fell_back = FALSE;
    }
  }
  g_autofree char *hint =
      ui->fell_back
          ? g_strconcat(otz_tr(S_FOLDER_HINT), "\n\n", otz_tr(S_FOLDER_FALLBACK_NOTE), NULL)
          : g_strdup(otz_tr(S_FOLDER_HINT));
  Frame frame = frame_new(ui, otz_tr(S_FOLDER_TITLE), otz_tr(S_FOLDER_DESC), hint, FALSE);
  GtkWidget *field = otz_field_button(ui->base_dir);
  g_signal_connect_swapped(field, "clicked", G_CALLBACK(choose_folder), ui);
  otz_accessible(field, otz_tr(S_ROW_SAVED_IN), ui->base_dir);
  add_content(&frame, field);
  GtkWidget *browse =
      action_button(ui, OTZ_BUTTON_TONAL, otz_tr(S_BROWSE), 120, 40, choose_folder);
  gtk_widget_set_halign(browse, GTK_ALIGN_START);
  gtk_widget_set_margin_top(browse, 2);
  add_content(&frame, browse);
  nav_footer(ui, &frame, NULL);
  return frame.page;
}

static void confirm_folder(Ui *ui) {
  if (ui->snapshot || otz_dir_is_writable(ui->base_dir)) {
    go(ui, PAGE_READY);
    return;
  }
  g_autofree char *fallback = otz_fallback_output_dir(ui->english);
  if (g_strcmp0(fallback, ui->base_dir) != 0 && otz_dir_is_writable(fallback)) {
    g_free(ui->base_dir);
    ui->base_dir = g_strdup(fallback);
    show_page(ui);
    g_autofree char *path = otz_ltr(fallback);
    g_autofree char *text = otz_trf(S_FOLDER_BAD_FALLBACK, path, NULL);
    tell(ui, otz_tr(S_FOLDER_BAD_TITLE), text);
  } else {
    tell(ui, otz_tr(S_FOLDER_BAD_TITLE), otz_tr(S_FOLDER_BAD_TEXT));
  }
}

/* ------------------------------------------------------------- ready */

static char *for_text(Ui *ui) {
  const Target *target = current_target(ui);
  if (ui->mode == MODE_THIS) {
    const char *format = target->format;
    const char *kind = strcmp(format, "deb") == 0   ? "DEB"
                       : strcmp(format, "rpm") == 0 ? "RPM"
                                                    : format_name(format);
    return g_strconcat(otz_tr(S_MODE_THIS), " · ", kind, NULL);
  }
  g_autofree char *base = target_title(target);
  if (*target->format == '\0') return g_steal_pointer(&base);
  return g_strconcat(base, " · ", format_name(target->format), NULL);
}

static GtkWidget *ready_page(Ui *ui) {
  Frame frame = frame_new(ui, otz_tr(S_READY_TITLE), otz_tr(S_READY_DESC),
                          otz_tr(S_READY_HINT), TRUE);
  OtzSummaryRow rows[4];
  int count = 0;
  g_autofree char *version = version_label(ui);
  if (version != NULL)
    rows[count++] = (OtzSummaryRow){.icon = "preset_update", .label = otz_tr(S_ROW_VERSION), .value = version};
  g_autoptr(GPtrArray) ids = selected_ids(ui);
  gboolean custom = find_preset(ui, ui->preset_id) == NULL;
  g_autofree char *size = otz_size_text(otz_members_download_size(ui->manifest, ids));
  g_autofree char *what =
      g_strconcat(preset_title(custom ? CUSTOM_ID : ui->preset_id), " · ", size, NULL);
  g_autofree char *what_icon = preset_icon(custom ? CUSTOM_ID : ui->preset_id);
  rows[count++] = (OtzSummaryRow){.icon = what_icon, .label = otz_tr(S_ROW_WHAT), .value = what};
  g_autofree char *for_value = for_text(ui);
  g_autofree char *for_icon =
      ui->mode == MODE_THIS ? g_strdup("this_pc") : g_strdup(current_target(ui)->platform);
  rows[count++] = (OtzSummaryRow){.icon = for_icon, .label = otz_tr(S_ROW_FOR), .value = for_value};
  rows[count++] = (OtzSummaryRow){"folder", otz_tr(S_ROW_SAVED_IN), ui->base_dir, TRUE};
  GtkWidget *summary = otz_summary_card(rows, count);
  gtk_widget_set_margin_top(summary, OTZ_RING);
  add_content(&frame, summary);
  nav_footer(ui, &frame, otz_tr(S_START));
  return frame.page;
}

/* ------------------------------------------------------------- working */

static GtkWidget *progress_panel(Ui *ui, const char *caption, double fraction) {
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_margin_top(box, 28);
  ui->w_percent = otz_label(" ", "t-percent");
  gtk_box_pack_start(GTK_BOX(box), ui->w_percent, FALSE, FALSE, 0);
  ui->w_caption = otz_wrap_label(caption, "t-caption", OTZ_CONTENT_WIDTH, 0.5f);
  gtk_label_set_lines(GTK_LABEL(ui->w_caption), 3);
  gtk_label_set_ellipsize(GTK_LABEL(ui->w_caption), PANGO_ELLIPSIZE_END);
  gtk_widget_set_margin_top(ui->w_caption, 4);
  gtk_box_pack_start(GTK_BOX(box), ui->w_caption, FALSE, FALSE, 0);
  ui->w_bar = otz_progress_bar(fraction);
  gtk_widget_set_margin_top(ui->w_bar, 16);
  gtk_box_pack_start(GTK_BOX(box), ui->w_bar, FALSE, FALSE, 0);
  ui->w_speed = otz_label(" ", "t-detail");
  gtk_widget_set_margin_top(ui->w_speed, 16);
  gtk_box_pack_start(GTK_BOX(box), ui->w_speed, FALSE, FALSE, 0);
  ui->w_bytes = otz_label(" ", "t-detail-faint");
  gtk_widget_set_margin_top(ui->w_bytes, 4);
  gtk_box_pack_start(GTK_BOX(box), ui->w_bytes, FALSE, FALSE, 0);
  return box;
}

static void request_stop_connecting(Ui *ui);

static GtkWidget *connecting_page(Ui *ui) {
  Frame frame =
      frame_new(ui, otz_tr(S_CONNECT_TITLE), otz_tr(S_CONNECT_DESC), NULL, FALSE);
  add_content(&frame, progress_panel(ui, otz_tr(S_CONNECTING_PROGRESS), -1));
  trailing_footer(ui, &frame, otz_tr(S_CANCEL), request_stop_connecting);
  return frame.page;
}

static const char *file_display_name(Ui *ui, const char *file) {
  const char *name = ui->file_names != NULL && file != NULL
                         ? g_hash_table_lookup(ui->file_names, file)
                         : NULL;
  return name != NULL ? name : file != NULL ? file : "";
}

static void update_working(Ui *ui) {
  if (ui->w_percent == NULL) return;
  Status *s = &ui->status;
  gboolean downloading = !s->set || s->phase == OTZ_PHASE_DOWNLOAD;
  g_autofree char *version = version_label(ui);
  g_autofree char *title =
      downloading && version != NULL ? otz_trf(S_DOWNLOADING_VERSION, version, NULL)
                                     : g_strdup(otz_tr(S_WORK_TITLE));
  otz_label_set(ui->w_title, title);
  if (ui->w_desc != NULL)
    otz_label_set(ui->w_desc, otz_tr(downloading ? S_DOWNLOAD_DESC : S_WORK_DESC));
  if (!s->set) {
    otz_label_set(ui->w_percent, "0%");
    otz_label_set(ui->w_caption, otz_tr(S_PREPARING));
    otz_progress_bar_set(ui->w_bar, 0);
    return;
  }
  double fraction = s->total > 0 ? (double)s->done / (double)s->total : 0;
  g_autofree char *percent = g_strdup_printf("%d%%", (int)(CLAMP(fraction, 0, 1) * 100));
  otz_label_set(ui->w_percent, percent);
  otz_progress_bar_set(ui->w_bar, fraction);
  const char *name = file_display_name(ui, s->detail);
  g_autofree char *caption = NULL;
  switch (s->phase) {
    case OTZ_PHASE_DOWNLOAD: {
      g_autofree char *index =
          g_strdup_printf("%u", MIN(s->files_done + 1, MAX(s->files_total, 1)));
      g_autofree char *count = g_strdup_printf("%u", s->files_total);
      caption = *name != '\0' ? otz_trf(S_DOWNLOADING_ITEM, name, index, count, NULL)
                              : g_strdup(otz_tr(S_PREPARING));
      break;
    }
    case OTZ_PHASE_CHECK: caption = otz_trf(S_CHECKING_CACHED, name, NULL); break;
    case OTZ_PHASE_ASSEMBLE: caption = otz_trf(S_JOINING_FILES, name, NULL); break;
    case OTZ_PHASE_VERIFY_ASSEMBLY: caption = otz_trf(S_CHECKING_JOINED, name, NULL); break;
    case OTZ_PHASE_PLACE: caption = otz_trf(S_COPYING_TO, name, NULL); break;
    default: caption = g_strdup(otz_tr(S_PREPARING)); break;
  }
  otz_label_set(ui->w_caption, caption);
  g_autofree char *speed = NULL;
  if (s->phase == OTZ_PHASE_DOWNLOAD && s->speed > 0) {
    g_autofree char *rate = otz_speed_text(s->speed);
    if (s->eta >= 0) {
      g_autofree char *eta = otz_duration_text(s->eta);
      g_autofree char *left = otz_trf(S_TIME_LEFT, eta, NULL);
      speed = g_strconcat(rate, " · ", left, NULL);
    } else {
      speed = g_steal_pointer(&rate);
    }
  }
  otz_label_set(ui->w_speed, speed != NULL ? speed : " ");
  g_autofree char *done = otz_size_text(s->done);
  g_autofree char *total = otz_size_text(s->total);
  g_autofree char *bytes =
      s->total <= 0 ? g_strdup(" ")
      : s->phase == OTZ_PHASE_DOWNLOAD ? otz_trf(S_DOWNLOADED_OF, done, total, NULL)
                                       : otz_trf(S_SIZE_OF, done, total, NULL);
  otz_label_set(ui->w_bytes, bytes);
}

static void request_stop(Ui *ui);

static GtkWidget *working_page(Ui *ui) {
  Frame frame = frame_new(ui, otz_tr(S_WORK_TITLE), otz_tr(S_DOWNLOAD_DESC), NULL, FALSE);
  add_content(&frame, progress_panel(ui, otz_tr(S_PREPARING), 0));
  trailing_footer(ui, &frame, otz_tr(S_STOP_DOWNLOAD), request_stop);
  return frame.page;
}

/* ------------------------------------------------------------- finish */

static void quit(Ui *ui) {
  ui->quit_confirmed = TRUE;
  if (ui->window != NULL) gtk_widget_destroy(ui->window);
}

static void reveal_result(Ui *ui) {
  if (ui->result_dir == NULL || ui->snapshot) return;
  if (ui->result_files != NULL && ui->result_files->len == 1) {
    g_autofree char *file =
        g_build_filename(ui->result_dir, g_ptr_array_index(ui->result_files, 0), NULL);
    otz_reveal(file, FALSE);
  } else {
    otz_reveal(ui->result_dir, TRUE);
  }
}

static void finish(Ui *ui) {
  if (ui->mode == MODE_OTHER && ui->reveal_when_done) reveal_result(ui);
  quit(ui);
}

static void on_reveal_toggled(GtkToggleButton *card, Ui *ui) {
  ui->reveal_when_done = gtk_toggle_button_get_active(card);
}

static const char *open_hint(const char *name) {
  g_autofree char *lower = g_ascii_strdown(name, -1);
  if (g_str_has_suffix(lower, ".exe")) return otz_tr(S_OPEN_HINT_EXE);
  if (g_str_has_suffix(lower, ".dmg")) return otz_tr(S_OPEN_HINT_DMG);
  if (g_str_has_suffix(lower, ".deb") || g_str_has_suffix(lower, ".rpm"))
    return otz_tr(S_OPEN_HINT_PACKAGE);
  if (g_str_has_suffix(lower, ".apk")) return otz_tr(S_OPEN_HINT_APK);
  return otz_tr(S_OPEN_HINT_ARCHIVE);
}

static void paragraph(GtkWidget *box, const char *text, int top) {
  GtkWidget *label = otz_wrap_label(text, "t-hint", OTZ_CONTENT_WIDTH, 0.5f);
  gtk_widget_set_margin_top(label, top);
  gtk_box_pack_start(GTK_BOX(box), label, FALSE, FALSE, 0);
}

/* A file name inside a sentence: no-break hyphens keep it on one line. */
static char *unbreakable(const char *name) {
  GString *text = g_string_new(NULL);
  for (const char *c = name; *c != '\0'; c++) {
    if (*c == '-')
      g_string_append(text, "\xE2\x80\x91");
    else
      g_string_append_c(text, *c);
  }
  g_autofree char *joined = g_string_free(text, FALSE);
  return otz_ltr(joined);
}

/* The wording follows what was produced, like PrepareOutput on Windows. */
static void finish_guide(Ui *ui, GtkWidget *box) {
  GPtrArray *files = ui->result_files;
  const char *platform = otz_platform_display_name(current_target(ui)->platform);
  if (files->len == 1) {
    if (ui->mode == MODE_THIS) {
      paragraph(box, otz_tr(S_GUIDE_THIS_FILE), 14);
    } else {
      g_autofree char *copy = otz_trf(S_GUIDE_OTHER_FILE, platform, NULL);
      g_autofree char *text =
          g_strconcat(copy, " ", open_hint(g_ptr_array_index(files, 0)), NULL);
      paragraph(box, text, 14);
    }
  } else {
    if (ui->mode == MODE_THIS) {
      paragraph(box, otz_tr(S_GUIDE_THIS_FOLDER), 14);
    } else {
      const char *exe = NULL;
      for (guint i = 0; exe == NULL && i < files->len; i++) {
        g_autofree char *lower = g_ascii_strdown(g_ptr_array_index(files, i), -1);
        if (g_str_has_suffix(lower, ".exe")) exe = g_ptr_array_index(files, i);
      }
      g_autofree char *copy = otz_trf(S_GUIDE_OTHER_FOLDER, platform, NULL);
      g_autofree char *exe_name = exe != NULL ? unbreakable(exe) : NULL;
      g_autofree char *run =
          exe != NULL && strcmp(current_target(ui)->platform, "windows") == 0
              ? otz_trf(S_GUIDE_RUN_EXE, exe_name, NULL)
              : NULL;
      g_autofree char *text = run != NULL ? g_strconcat(copy, " ", run, NULL)
                                          : g_strdup(copy);
      paragraph(box, text, 14);
    }
    for (guint i = 0; i < ui->result_unjoined->len; i++) {
      if (i == 0) paragraph(box, otz_tr(S_GUIDE_JOIN), 8);
      const char *name = g_ptr_array_index(ui->result_unjoined, i);
      g_autofree char *command = g_strdup_printf("cat %s.part-* > %s", name, name);
      GtkWidget *code = otz_code_box(command);
      gtk_widget_set_margin_top(code, 8);
      gtk_box_pack_start(GTK_BOX(box), code, FALSE, FALSE, 0);
    }
    paragraph(box, otz_tr(S_PREPARED_FILES), 8);
    GString *list = g_string_new(NULL);
    for (guint i = 0; i < files->len; i++)
      g_string_append_printf(list, "%s• %s", i > 0 ? "\n" : "",
                             (const char *)g_ptr_array_index(files, i));
    GtkWidget *names = gtk_label_new(list->str);
    g_string_free(list, TRUE);
    gtk_style_context_add_class(gtk_widget_get_style_context(names), "t-hint");
    gtk_widget_set_direction(names, GTK_TEXT_DIR_LTR);
    gtk_label_set_xalign(GTK_LABEL(names), 0);
    gtk_label_set_line_wrap(GTK_LABEL(names), TRUE);
    gtk_label_set_line_wrap_mode(GTK_LABEL(names), PANGO_WRAP_CHAR);
    gtk_label_set_max_width_chars(GTK_LABEL(names), 1);
    gtk_label_set_selectable(GTK_LABEL(names), TRUE);
    gtk_widget_set_size_request(names, OTZ_CONTENT_WIDTH, -1);
    gtk_widget_set_margin_top(names, 4);
    gtk_box_pack_start(GTK_BOX(box), names, FALSE, FALSE, 0);
  }
  for (guint i = 0; i < ui->result_notes->len; i++)
    paragraph(box, g_ptr_array_index(ui->result_notes, i), 8);
}

static void open_output(Ui *ui) { reveal_result(ui); }

static GtkWidget *finished_page(Ui *ui) {
  GtkWidget *page = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll), GTK_POLICY_NEVER,
                                 GTK_POLICY_AUTOMATIC);
  gtk_scrolled_window_set_overlay_scrolling(GTK_SCROLLED_WINDOW(scroll), FALSE);
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_size_request(box, OTZ_CONTENT_WIDTH, -1);
  gtk_widget_set_halign(box, GTK_ALIGN_CENTER);
  gtk_widget_set_margin_bottom(box, 12);
  GtkWidget *badge = otz_badge("ok");
  gtk_widget_set_margin_top(badge, 36);
  gtk_box_pack_start(GTK_BOX(box), badge, FALSE, FALSE, 0);
  GtkWidget *title = otz_wrap_label(otz_tr(S_FINISHED_TITLE), "t-title",
                                    OTZ_CONTENT_WIDTH, 0.5f);
  gtk_widget_set_margin_top(title, 16);
  gtk_box_pack_start(GTK_BOX(box), title, FALSE, FALSE, 0);
  gboolean single = ui->result_files != NULL && ui->result_files->len == 1;
  if (ui->result_dir != NULL) {
    OtzSummaryRow rows[3];
    int count = 0;
    g_autofree char *version = version_label(ui);
    if (version != NULL)
      rows[count++] = (OtzSummaryRow){.icon = "preset_update", .label = otz_tr(S_ROW_VERSION), .value = version};
    if (single)
      rows[count++] = (OtzSummaryRow){"component", otz_tr(S_ROW_FILE),
                                      g_ptr_array_index(ui->result_files, 0), TRUE};
    rows[count++] = (OtzSummaryRow){"folder", otz_tr(S_ROW_FOLDER), ui->result_dir, TRUE};
    GtkWidget *summary = otz_summary_card(rows, count);
    gtk_widget_set_margin_top(summary, 24);
    gtk_box_pack_start(GTK_BOX(box), summary, FALSE, FALSE, 0);
    finish_guide(ui, box);
  }
  gtk_container_add(GTK_CONTAINER(scroll), box);
  gtk_box_pack_start(GTK_BOX(page), scroll, TRUE, TRUE, 0);

  GtkWidget *actions = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8 - 2 * OTZ_RING);
  gtk_widget_set_margin_top(actions, 8 - OTZ_RING);
  gtk_widget_set_margin_bottom(actions, 18 - OTZ_RING);
  if (ui->mode == MODE_OTHER) {
    OtzCardSpec spec = {.title = otz_tr(single ? S_REVEAL_FILE : S_REVEAL_FOLDER),
                        .check = TRUE};
    GtkWidget *reveal = otz_card(&spec, NULL);
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(reveal), ui->reveal_when_done);
    g_signal_connect(reveal, "toggled", G_CALLBACK(on_reveal_toggled), ui);
    gtk_box_pack_start(GTK_BOX(actions), reveal, FALSE, FALSE, 0);
    GtkWidget *done = action_button(ui, OTZ_BUTTON_PRIMARY, otz_tr(S_FINISH),
                                    OTZ_CONTENT_WIDTH, 40, finish);
    gtk_box_pack_start(GTK_BOX(actions), done, FALSE, FALSE, 0);
    ui->primary = finish;
    ui->focus = done;
  } else {
    GtkWidget *open = action_button(ui, OTZ_BUTTON_PRIMARY, otz_tr(S_OPEN_FOLDER),
                                    OTZ_CONTENT_WIDTH, 40, open_output);
    gtk_box_pack_start(GTK_BOX(actions), open, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(actions),
                       action_button(ui, OTZ_BUTTON_GHOST, otz_tr(S_CLOSE),
                                     OTZ_CONTENT_WIDTH, 40, quit),
                       FALSE, FALSE, 0);
    ui->primary = open_output;
    ui->focus = open;
  }
  ui->escape = NULL;
  gtk_box_pack_start(GTK_BOX(page), actions, FALSE, FALSE, 0);
  return page;
}

/* ------------------------------------------------------------- failure */

static void retry(Ui *ui);

static void open_downloads(Ui *ui) {
  g_autofree char *url =
      g_strdup_printf("https://github.com/%s/otzaria/releases", otz_allowed_owner());
  if (!ui->snapshot) g_app_info_launch_default_for_uri(url, NULL, NULL);
}

static void toggle_technical(Ui *ui) {
  ui->show_technical = !ui->show_technical;
  show_page(ui);
}

static char *failure_title(Ui *ui) {
  switch (ui->failure) {
    case FAIL_OFFLINE: return g_strdup(otz_tr(S_OFFLINE_TITLE));
    case FAIL_STOPPED: return g_strdup(otz_tr(S_STOPPED_TITLE));
    case FAIL_TLS: return g_strdup(otz_tr(S_TLS_TITLE));
    default: break;
  }
  const char *message =
      otz_tr_message(ui->error_message != NULL ? ui->error_message
                                               : otz_tr(S_ERR_CANNOT_PREPARE));
  gsize length = strlen(message);
  return length > 0 && message[length - 1] == '.' ? g_strndup(message, length - 1)
                                                   : g_strdup(message);
}

static char *failure_body(Ui *ui) {
  switch (ui->failure) {
    case FAIL_OFFLINE: return g_strdup(otz_tr(S_OFFLINE_BODY));
    case FAIL_LOAD: return g_strdup(otz_tr(S_LOAD_FAILED_BODY));
    case FAIL_RUN: return g_strdup(otz_tr(S_RUN_FAILED_BODY));
    case FAIL_STOPPED: return g_strdup(otz_tr(S_STOPPED_BODY));
    case FAIL_TLS: {
      g_autofree char *command = otz_ltr("sudo apt install glib-networking");
      return otz_trf(S_TLS_BODY, command, NULL);
    }
  }
  return g_strdup("");
}

static GtkWidget *failure_page(Ui *ui) {
  GtkWidget *page = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_size_request(page, OTZ_CONTENT_WIDTH + 2 * OTZ_RING, -1);
  gtk_widget_set_halign(page, GTK_ALIGN_CENTER);
  const char *badge = ui->failure == FAIL_OFFLINE   ? "offline"
                      : ui->failure == FAIL_STOPPED ? "paused"
                                                    : "err";
  GtkWidget *badge_area = otz_badge(badge);
  gtk_widget_set_margin_top(badge_area, 52);
  gtk_box_pack_start(GTK_BOX(page), badge_area, FALSE, FALSE, 0);
  g_autofree char *title_text = failure_title(ui);
  GtkWidget *title = otz_wrap_label(title_text, "t-title", OTZ_CONTENT_WIDTH, 0.5f);
  gtk_widget_set_margin_top(title, 20);
  gtk_box_pack_start(GTK_BOX(page), title, FALSE, FALSE, 0);
  g_autofree char *body_text = failure_body(ui);
  GtkWidget *body = otz_wrap_label(body_text, "t-desc", OTZ_CONTENT_WIDTH, 0.5f);
  gtk_widget_set_margin_top(body, 10);
  gtk_box_pack_start(GTK_BOX(page), body, FALSE, FALSE, 0);
  if (ui->failure != FAIL_STOPPED && ui->error_technical != NULL) {
    GtkWidget *link = action_button(ui, OTZ_BUTTON_LINK, otz_tr(S_TECH_DETAILS), -1, 24,
                                    toggle_technical);
    gtk_widget_set_margin_top(link, 14 - OTZ_RING);
    otz_accessible(link, otz_tr(S_TECH_DETAILS),
                   ui->show_technical ? ui->error_technical : NULL);
    gtk_box_pack_start(GTK_BOX(page), link, FALSE, FALSE, 0);
    if (ui->show_technical) {
      GtkWidget *code = otz_code_box(ui->error_technical);
      gtk_widget_set_margin_top(code, 10 - OTZ_RING);
      gtk_box_pack_start(GTK_BOX(page), code, FALSE, FALSE, 0);
      ui->focus = link;
    }
  }
  GtkWidget *actions = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8 - 2 * OTZ_RING);
  gtk_widget_set_margin_bottom(actions, 18 - OTZ_RING);
  GtkWidget *primary;
  if (ui->failure == FAIL_TLS) {
    primary = action_button(ui, OTZ_BUTTON_PRIMARY, otz_tr(S_OPEN_DOWNLOADS),
                            OTZ_CONTENT_WIDTH, 40, open_downloads);
    ui->primary = open_downloads;
  } else {
    primary = action_button(ui, OTZ_BUTTON_PRIMARY,
                            otz_tr(ui->failure == FAIL_STOPPED ? S_RESUME : S_RETRY),
                            OTZ_CONTENT_WIDTH, 40, retry);
    ui->primary = retry;
  }
  gtk_box_pack_start(GTK_BOX(actions), primary, FALSE, FALSE, 0);
  if (ui->failure != FAIL_STOPPED && ui->failure != FAIL_TLS)
    gtk_box_pack_start(GTK_BOX(actions),
                       action_button(ui, OTZ_BUTTON_TONAL, otz_tr(S_OPEN_DOWNLOADS),
                                     OTZ_CONTENT_WIDTH, 40, open_downloads),
                       FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(actions),
                     action_button(ui, OTZ_BUTTON_GHOST, otz_tr(S_CLOSE),
                                   OTZ_CONTENT_WIDTH, 40, quit),
                     FALSE, FALSE, 0);
  gtk_box_pack_end(GTK_BOX(page), actions, FALSE, FALSE, 0);
  if (ui->focus == NULL) ui->focus = primary;
  ui->escape = NULL;
  return page;
}

/* ------------------------------------------------------------- pages */

static void show_page(Ui *ui) {
  close_dialog(ui);
  if (ui->page != NULL) gtk_widget_destroy(ui->page);
  ui->page = NULL;
  ui->focus = NULL;
  ui->primary = ui->escape = NULL;
  ui->w_title = ui->w_desc = ui->w_percent = ui->w_caption = NULL;
  ui->w_bar = ui->w_speed = ui->w_bytes = NULL;
  ui->hero = ui->hero_note = ui->hero_start = NULL;
  switch (ui->page_id) {
    case PAGE_WELCOME: ui->page = welcome_page(ui); break;
    case PAGE_CONNECTING: ui->page = connecting_page(ui); break;
    case PAGE_MODE: ui->page = mode_page(ui); break;
    case PAGE_OTHER: ui->page = other_page(ui); break;
    case PAGE_PRESETS: ui->page = presets_page(ui); break;
    case PAGE_CUSTOM: ui->page = custom_page(ui); break;
    case PAGE_FOLDER: ui->page = folder_page(ui); break;
    case PAGE_READY: ui->page = ready_page(ui); break;
    case PAGE_WORKING: ui->page = working_page(ui); break;
    case PAGE_FINISHED: ui->page = finished_page(ui); break;
    case PAGE_FAILURE: ui->page = failure_page(ui); break;
  }
  gtk_box_pack_start(GTK_BOX(ui->host), ui->page, TRUE, TRUE, 0);
  gtk_widget_show_all(ui->page);
  if (ui->page_id == PAGE_WORKING) update_working(ui);
  if (ui->focus != NULL) gtk_widget_grab_focus(ui->focus);
}

static void go(Ui *ui, Page page) {
  g_array_append_val(ui->history, ui->page_id);
  ui->page_id = page;
  show_page(ui);
}

static void back(Ui *ui) {
  if (!can_go_back(ui)) return;
  ui->page_id = g_array_index(ui->history, Page, ui->history->len - 1);
  g_array_set_size(ui->history, ui->history->len - 1);
  show_page(ui);
}

static void go_presets(Ui *ui) {
  build_presets(ui);
  go(ui, PAGE_PRESETS);
}

static void prepare_and_start(Ui *ui);

static void next(Ui *ui) {
  if (ui->manifest == NULL) return;
  switch (ui->page_id) {
    case PAGE_MODE:
      if (ui->mode == MODE_THIS)
        go_presets(ui);
      else
        go(ui, PAGE_OTHER);
      break;
    case PAGE_OTHER:
      if (ui->other_index < 0)
        tell(ui, otz_tr(S_NO_TARGET_TITLE), otz_tr(S_NO_TARGET_TEXT));
      else
        go_presets(ui);
      break;
    case PAGE_PRESETS:
      if (g_strcmp0(ui->preset_id, CUSTOM_ID) == 0) {
        if (g_hash_table_size(ui->custom_checked) == 0) default_custom_checked(ui);
        go(ui, PAGE_CUSTOM);
      } else {
        go(ui, PAGE_FOLDER);
      }
      break;
    case PAGE_CUSTOM: {
      g_autoptr(GPtrArray) ids = selected_ids(ui);
      if (ids->len == 0)
        tell(ui, otz_tr(S_NOTHING_TITLE), otz_tr(S_NOTHING_TEXT));
      else
        go(ui, PAGE_FOLDER);
      break;
    }
    case PAGE_FOLDER: confirm_folder(ui); break;
    case PAGE_READY: prepare_and_start(ui); break;
    default: break;
  }
}

/* ------------------------------------------------------------- loading */

typedef struct {
  OtzManifest *manifest;
  char *tag;
  const char *user_message;
  GError *error;
} LoadResult;

static void free_load_result(gpointer data) {
  LoadResult *result = data;
  otz_manifest_free(result->manifest);
  g_free(result->tag);
  g_clear_error(&result->error);
  g_free(result);
}

/* Runs off the main thread and sees only its own copy of the input. */
static void load_in_thread(GTask *task, gpointer source, gpointer task_data,
                           GCancellable *cancellable) {
  const char *dev_manifest = task_data;
  LoadResult *result = g_new0(LoadResult, 1);
  if (dev_manifest != NULL && *dev_manifest != '\0') {
    result->user_message = "לא ניתן לקרוא את רשימת הקבצים של אוצריא.";
    result->manifest = otz_load_manifest_file(dev_manifest, &result->error);
    if (result->manifest != NULL) result->tag = g_strdup(result->manifest->release_tag);
  } else {
    result->manifest = otz_load_release_manifest(&result->tag, &result->user_message,
                                                 cancellable, &result->error);
  }
  g_task_return_pointer(task, result, free_load_result);
}

static void show_failure(Ui *ui, Failure failure, const char *message,
                         const char *technical) {
  if (technical != NULL) g_printerr("otzaria-download-assistant: %s\n", technical);
  g_free(ui->error_message);
  g_free(ui->error_technical);
  ui->error_message = g_strdup(message);
  ui->error_technical = g_strdup(technical);
  ui->failure = failure;
  ui->show_technical = FALSE;
  ui->page_id = PAGE_FAILURE;
  show_page(ui);
}

static void auto_run(Ui *ui);

static void loaded(Ui *ui, OtzManifest *manifest) {
  ui->manifest = manifest;
  compute_targets(ui);
  ui->mode = ui->this_offered ? MODE_THIS : MODE_OTHER;
  ui->other_index = -1;
  g_array_set_size(ui->history, 0);
  Page welcome = PAGE_WELCOME;
  g_array_append_val(ui->history, welcome);
  ui->page_id = PAGE_MODE;
  show_page(ui);
}

static void auto_report_failure(Ui *ui, const char *message) {
  if (ui->options->dev_auto_preset == NULL) return;
  printf("result: failed\nerror: %s\n", message);
  fflush(stdout);
  ui->exit_code = 1;
  quit(ui);
}

static void on_manifest_loaded(GObject *source, GAsyncResult *async, gpointer data) {
  Ui *ui = data;
  GTask *task = G_TASK(async);
  if (GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(task), "otz-generation")) !=
      ui->load_generation)
    return;
  g_autoptr(GError) error = NULL;
  LoadResult *result = g_task_propagate_pointer(task, &error);
  if (result != NULL && result->manifest != NULL) {
    g_free(ui->pinned_tag);
    ui->pinned_tag = g_steal_pointer(&result->tag);
    OtzManifest *manifest = g_steal_pointer(&result->manifest);
    free_load_result(result);
    loaded(ui, manifest);
    if (ui->options->dev_auto_preset != NULL) auto_run(ui);
    return;
  }
  const char *message = "לא ניתן לקרוא את רשימת הקבצים של אוצריא.";
  if (result != NULL) {
    if (result->user_message != NULL) message = result->user_message;
    error = g_steal_pointer(&result->error);
    free_load_result(result);
  }
  if (error == NULL) error = g_error_new_literal(OTZ_ERROR, OTZ_ERROR_PARSE, "no manifest");
  if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED)) return;
  ui->failed_while_loading = TRUE;
  show_failure(ui, otz_error_is_offline(error) ? FAIL_OFFLINE : FAIL_LOAD, message,
               error->message);
  auto_report_failure(ui, error->message);
}

static void load(Ui *ui) {
  ui->load_generation++;
  ui->page_id = PAGE_CONNECTING;
  show_page(ui);
  g_clear_object(&ui->load_cancel);
  ui->load_cancel = g_cancellable_new();
  g_autoptr(GTask) task = g_task_new(NULL, ui->load_cancel, on_manifest_loaded, ui);
  g_object_set_data(G_OBJECT(task), "otz-generation",
                    GUINT_TO_POINTER(ui->load_generation));
  g_task_set_task_data(task, g_strdup(ui->options->dev_manifest), g_free);
  g_task_run_in_thread(task, load_in_thread);
}

/* "Let's get started". The tag is pinned after a load, so there is no second. */
static void begin(Ui *ui) {
  ui->hero_played = TRUE;
  if (!ui->options->tls_ok && ui->options->dev_manifest == NULL) {
    ui->failed_while_loading = TRUE;
    show_failure(ui, FAIL_TLS, NULL,
                 "g_tls_backend_supports_tls() is FALSE: the glib-networking GIO "
                 "module is not installed");
    return;
  }
  if (ui->manifest != NULL) {
    g_array_set_size(ui->history, 0);
    Page welcome = PAGE_WELCOME;
    g_array_append_val(ui->history, welcome);
    ui->page_id = PAGE_MODE;
    show_page(ui);
    return;
  }
  load(ui);
}

static void stop_connecting(Ui *ui) {
  if (ui->page_id != PAGE_CONNECTING) return;
  ui->load_generation++;
  if (ui->load_cancel != NULL) g_cancellable_cancel(ui->load_cancel);
  ui->page_id = PAGE_WELCOME;
  show_page(ui);
}

static void request_stop_connecting(Ui *ui) {
  ask(ui, otz_tr(S_CONNECT_STOP_TITLE), otz_tr(S_CONNECT_STOP_TEXT),
      otz_tr(S_CONNECT_STOP_YES), otz_tr(S_CONNECT_STOP_NO), FALSE, stop_connecting);
}

/* ------------------------------------------------------------- job */

static double current_speed(Ui *ui, gint64 now, gint64 bytes) {
  if (ui->sample_count == MAX_SAMPLES) {
    memmove(ui->samples, ui->samples + 1, sizeof(Sample) * (MAX_SAMPLES - 1));
    ui->sample_count--;
  }
  ui->samples[ui->sample_count++] = (Sample){now, bytes};
  int oldest = 0;
  while (oldest < ui->sample_count - 1 && now - ui->samples[oldest].time > SPEED_WINDOW_US)
    oldest++;
  gint64 span = now - ui->samples[oldest].time;
  if (span < G_USEC_PER_SEC) return -1;
  return (double)(bytes - ui->samples[oldest].bytes) * G_USEC_PER_SEC / span;
}

static gboolean on_tick(gpointer data) {
  Ui *ui = data;
  if (ui->job == NULL) return G_SOURCE_REMOVE;
  OtzProgress p;
  otz_job_get_progress(ui->job, &p);
  Status *s = &ui->status;
  g_free(s->detail);
  s->set = TRUE;
  s->phase = p.phase;
  s->detail = g_strdup(p.detail);
  s->files_done = p.files_done;
  s->files_total = p.files_total;
  s->speed = s->eta = -1;
  if (p.phase == OTZ_PHASE_DOWNLOAD) {
    s->done = p.download_done;
    s->total = p.download_total;
    s->speed = current_speed(ui, g_get_monotonic_time(), p.download_done);
    if (s->speed > 0) s->eta = (p.download_total - p.download_done) / s->speed;
  } else {
    s->done = p.phase_done;
    s->total = p.phase_total;
  }
  otz_progress_clear(&p);
  update_working(ui);
  return G_SOURCE_CONTINUE;
}

static void auto_report(Ui *ui, const char *technical) {
  if (ui->options->dev_auto_preset == NULL) return;
  double seconds = (g_get_monotonic_time() - ui->started_us) / 1e6;
  if (ui->succeeded) {
    gint64 downloaded = otz_job_downloaded_bytes(ui->job);
    printf("result: ok\ndir: %s\nfiles: %u\ndownloaded: %" G_GINT64_FORMAT
           "\nhashed: %" G_GINT64_FORMAT "\nseconds: %.1f\nMB/s: %.2f\n",
           otz_job_output_dir(ui->job), otz_job_output_files(ui->job)->len, downloaded,
           otz_job_hashed_bytes(ui->job), seconds,
           seconds > 0 ? downloaded / seconds / 1e6 : 0.0);
    fflush(stdout);
    ui->exit_code = 0;
    quit(ui);
  } else {
    auto_report_failure(ui, technical);
  }
}

static void copy_strings(GPtrArray **out, GPtrArray *in) {
  g_clear_pointer(out, g_ptr_array_unref);
  *out = g_ptr_array_new_with_free_func(g_free);
  for (guint i = 0; in != NULL && i < in->len; i++)
    g_ptr_array_add(*out, g_strdup(g_ptr_array_index(in, i)));
}

static void collect_result(Ui *ui) {
  g_free(ui->result_dir);
  ui->result_dir = g_strdup(otz_job_output_dir(ui->job));
  copy_strings(&ui->result_files, otz_job_output_files(ui->job));
  copy_strings(&ui->result_unjoined, otz_job_unjoined_assets(ui->job));
  g_clear_pointer(&ui->result_notes, g_ptr_array_unref);
  ui->result_notes = g_ptr_array_new_with_free_func(g_free);
  for (guint i = 0; i < ui->manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(ui->manifest->components, i);
    if (!contains(ui->job_ids, component->id)) continue;
    const char *note = otz_component_output_note(component, ui->english);
    if (*note != '\0' && !contains(ui->result_notes, note))
      g_ptr_array_add(ui->result_notes, g_strdup(note));
  }
}

static OtzString failure_message(OtzFailure failure) {
  switch (failure) {
    case OTZ_FAILURE_CORRUPT: return S_ERR_DAMAGED;
    case OTZ_FAILURE_CACHE: return S_ERR_SAVE;
    case OTZ_FAILURE_ASSEMBLE: return S_ERR_WRITE_JOINED;
    case OTZ_FAILURE_PLACE: return S_ERR_COPY;
    default: return S_ERR_FILE_UNAVAILABLE;
  }
}

static void on_job_done(GObject *source, GAsyncResult *result, gpointer data) {
  Ui *ui = data;
  g_autoptr(GError) error = NULL;
  ui->succeeded = otz_job_run_finish(ui->job, result, &error);
  if (ui->tick_id != 0) {
    on_tick(ui);
    g_source_remove(ui->tick_id);
    ui->tick_id = 0;
  }
  if (ui->closing) {
    quit(ui);
    return;
  }
  if (ui->succeeded) {
    collect_result(ui);
    ui->page_id = PAGE_FINISHED;
    show_page(ui);
  } else if (otz_job_failure(ui->job) == OTZ_FAILURE_CANCELLED) {
    show_failure(ui, FAIL_STOPPED, NULL, NULL);
  } else {
    const char *hebrew_message = otz_tr_hebrew(failure_message(otz_job_failure(ui->job)));
    show_failure(ui, FAIL_RUN, hebrew_message, error != NULL ? error->message : NULL);
  }
  auto_report(ui, error != NULL ? error->message : NULL);
}

static void build_file_names(Ui *ui) {
  g_clear_pointer(&ui->file_names, g_hash_table_unref);
  ui->file_names = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);
  for (guint i = 0; i < ui->manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(ui->manifest->components, i);
    if (!contains(ui->job_ids, component->id)) continue;
    const char *name = otz_component_name(component, ui->english);
    for (guint a = 0; a < component->assets->len; a++) {
      const OtzAsset *asset = g_ptr_array_index(component->assets, a);
      g_hash_table_insert(ui->file_names, g_strdup(asset->name), g_strdup(name));
      for (guint p = 0; p < asset->parts->len; p++)
        g_hash_table_insert(ui->file_names,
                            g_strdup(((OtzPart *)g_ptr_array_index(asset->parts, p))->name),
                            g_strdup(name));
    }
  }
}

static char *subfolder_name(Ui *ui, const Target *target) {
  if (!ui->english) return NULL;
  return otz_trf(S_OUTPUT_SUBFOLDER, otz_platform_display_name(target->platform), NULL);
}

static OtzJob *new_job(Ui *ui, GError **error) {
  OtzTarget target = as_otz(&ui->job_target);
  g_autofree char *cache = otz_cache_dir();
  g_autofree char *subfolder = subfolder_name(ui, &ui->job_target);
  return otz_job_new(ui->manifest, ui->job_ids, &target, cache, ui->base_dir, subfolder,
                     error);
}

static void start(Ui *ui) {
  g_array_set_size(ui->history, 0);
  ui->page_id = PAGE_WORKING;
  g_free(ui->status.detail);
  memset(&ui->status, 0, sizeof ui->status);
  ui->failed_while_loading = FALSE;
  ui->started_us = g_get_monotonic_time();
  ui->sample_count = 0;
  build_file_names(ui);
  show_page(ui);
  g_clear_object(&ui->cancel);
  ui->cancel = g_cancellable_new();
  ui->tick_id = g_timeout_add(250, on_tick, ui);
  otz_job_run_async(ui->job, ui->cancel, on_job_done, ui);
}

static gboolean plan_job(Ui *ui) {
  g_autoptr(GError) error = NULL;
  if (ui->job != NULL) otz_job_free(ui->job);
  ui->job = new_job(ui, &error);
  if (ui->job != NULL) return TRUE;
  ui->failed_while_loading = FALSE;
  g_set_object(&ui->cancel, NULL);
  show_failure(ui, FAIL_RUN, otz_tr_hebrew(S_ERR_CANNOT_PREPARE), error->message);
  auto_report_failure(ui, error->message);
  return FALSE;
}

static void prepare_and_start(Ui *ui) {
  g_clear_pointer(&ui->job_ids, g_ptr_array_unref);
  GPtrArray *ids = selected_ids(ui);
  copy_strings(&ui->job_ids, ids);
  g_ptr_array_unref(ids);
  const Target *target = current_target(ui);
  target_set(&ui->job_target, target->platform, target->architecture, target->format);
  if (!plan_job(ui)) return;
  gint64 cache_bytes = 0, output_bytes = 0;
  gboolean same = FALSE;
  otz_job_space_needs(ui->job, &cache_bytes, &output_bytes, &same);
  g_autofree char *cache = otz_cache_dir();
  if (!otz_space_is_enough(cache_bytes, output_bytes, same, otz_free_space(cache),
                           otz_free_space(otz_job_output_dir(ui->job)))) {
    g_autofree char *size = otz_size_text(cache_bytes + output_bytes);
    g_autofree char *text = otz_trf(S_SPACE_TEXT, size, NULL);
    ask(ui, otz_tr(S_SPACE_TITLE), text, otz_tr(S_SPACE_YES), otz_tr(S_CANCEL), FALSE,
        start);
    return;
  }
  start(ui);
}

/* "Try again" / "Continue": the same pinned tag, selection and cache. */
static void retry(Ui *ui) {
  if (ui->failed_while_loading || ui->manifest == NULL) {
    load(ui);
  } else if (ui->job_ids != NULL) {
    if (plan_job(ui)) start(ui);
  } else {
    ui->page_id = PAGE_READY;
    show_page(ui);
  }
}

static void stop_job(Ui *ui) {
  if (ui->cancel != NULL) g_cancellable_cancel(ui->cancel);
}

static void request_stop(Ui *ui) {
  ask(ui, otz_tr(S_STOP_TITLE), otz_tr(S_STOP_TEXT), otz_tr(S_STOP_YES),
      otz_tr(S_STOP_NO), FALSE, stop_job);
}

/* The window closes once the download threads have stopped writing. */
static void exit_now(Ui *ui) {
  ui->quit_confirmed = TRUE;
  if (ui->tick_id != 0 && ui->cancel != NULL) {
    ui->closing = TRUE;
    g_cancellable_cancel(ui->cancel);
    gtk_widget_set_sensitive(ui->window, FALSE);
    return;
  }
  quit(ui);
}

static gboolean on_delete(GtkWidget *window, GdkEvent *event, Ui *ui) {
  if (ui->quit_confirmed ||
      (ui->page_id != PAGE_WORKING && ui->page_id != PAGE_CONNECTING) ||
      ui->closing)
    return ui->closing;
  ask(ui, otz_tr(S_EXIT_TITLE), otz_tr(S_EXIT_MESSAGE), otz_tr(S_EXIT_YES),
      otz_tr(S_EXIT_NO), TRUE, exit_now);
  return TRUE;
}

static gboolean on_key(GtkWidget *window, GdkEventKey *event, Ui *ui) {
  guint key = event->keyval;
  if (key == GDK_KEY_Escape) {
    UiAction action = ui->dialog_open ? ui->dialog_cancel : ui->escape;
    if (action == NULL) return FALSE;
    action(ui);
    return TRUE;
  }
  if (key == GDK_KEY_Return || key == GDK_KEY_KP_Enter || key == GDK_KEY_ISO_Enter) {
    GtkWidget *focus = gtk_window_get_focus(GTK_WINDOW(window));
    if (focus != NULL && GTK_IS_BUTTON(focus) && !GTK_IS_TOGGLE_BUTTON(focus) &&
        gtk_widget_is_sensitive(focus))
      return FALSE;
    UiAction action = ui->dialog_open ? ui->dialog_default : ui->primary;
    if (action == NULL) return FALSE;
    action(ui);
    return TRUE;
  }
  return FALSE;
}

/* --dev-auto-preset: the defaults of every page, the named preset, no window
 * interaction; prints a report and exits. */
static void auto_run(Ui *ui) {
  const char *platform = ui->options->dev_platform;
  if (platform != NULL && strcmp(platform, "linux") != 0) {
    ui->mode = MODE_OTHER;
    for (guint i = 0; ui->other_index < 0 && i < ui->others->len; i++) {
      const Target *target = g_ptr_array_index(ui->others, i);
      if (strcmp(target->platform, platform) == 0) ui->other_index = (int)i;
    }
    if (ui->other_index < 0) {
      auto_report_failure(ui, "no target for this platform");
      return;
    }
  } else if (!ui->this_offered) {
    auto_report_failure(ui, "this computer is not offered");
    return;
  }
  build_presets(ui);
  if (find_preset(ui, ui->options->dev_auto_preset) == NULL) {
    g_autofree char *message =
        g_strdup_printf("no preset '%s' for this target", ui->options->dev_auto_preset);
    auto_report_failure(ui, message);
    return;
  }
  g_free(ui->preset_id);
  ui->preset_id = g_strdup(ui->options->dev_auto_preset);
  g_free(ui->base_dir);
  ui->base_dir = ui->options->dev_output != NULL
                     ? g_strdup(ui->options->dev_output)
                     : otz_default_output_dir(ui->english, &ui->fell_back);
  g_mkdir_with_parents(ui->base_dir, 0755);
  g_clear_pointer(&ui->job_ids, g_ptr_array_unref);
  GPtrArray *ids = selected_ids(ui);
  copy_strings(&ui->job_ids, ids);
  g_ptr_array_unref(ids);
  const Target *target = current_target(ui);
  target_set(&ui->job_target, target->platform, target->architecture, target->format);
  if (plan_job(ui)) start(ui);
}

/* ------------------------------------------------------------- window */

static void build_window(Ui *ui) {
  ui->window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_style_context_add_class(gtk_widget_get_style_context(ui->window), "otz");
  /* Set before the title bar, or GtkWindow copies it there as a centred bold title. */
  gtk_window_set_title(GTK_WINDOW(ui->window), otz_tr(S_APP_TITLE));
  GtkWidget *bar = gtk_header_bar_new();
  gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(bar), TRUE);
  gtk_header_bar_set_has_subtitle(GTK_HEADER_BAR(bar), FALSE);
  g_object_set(bar, "spacing", 0, NULL);
  /* At the reading start, regular weight: on the right in Hebrew. */
  GtkWidget *title = otz_label(otz_tr(S_APP_TITLE), "t-wintitle");
  gtk_label_set_ellipsize(GTK_LABEL(title), PANGO_ELLIPSIZE_END);
  gtk_widget_set_margin_start(title, 12);
  gtk_widget_set_margin_end(title, 12);
  gtk_header_bar_pack_start(GTK_HEADER_BAR(bar), title);
  gtk_window_set_titlebar(GTK_WINDOW(ui->window), bar);
  gtk_header_bar_set_title(GTK_HEADER_BAR(bar), NULL);
  gtk_window_set_resizable(GTK_WINDOW(ui->window), FALSE);
  gtk_window_set_position(GTK_WINDOW(ui->window), GTK_WIN_POS_CENTER);
  g_autoptr(GdkPixbuf) icon = otz_app_icon();
  if (icon != NULL) gtk_window_set_icon(GTK_WINDOW(ui->window), icon);

  GdkDisplay *display = gdk_display_get_default();
  GdkDevice *pointer = gdk_seat_get_pointer(gdk_display_get_default_seat(display));
  int x = 0, y = 0;
  if (pointer != NULL) gdk_device_get_position(pointer, NULL, &x, &y);
  GdkMonitor *monitor = gdk_display_get_monitor_at_point(display, x, y);
  GdkRectangle workarea;
  gdk_monitor_get_workarea(monitor, &workarea);
  /* Leave room for the title bar and window decorations. */
  int height = MIN(OTZ_CONTENT_HEIGHT, MAX(1, workarea.height - 64));
  ui->overlay = gtk_overlay_new();
  gtk_widget_set_size_request(ui->overlay, OTZ_WINDOW_WIDTH, height);
  ui->scroll = gtk_scrolled_window_new(NULL, NULL);
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(ui->scroll), GTK_POLICY_NEVER,
                                 GTK_POLICY_AUTOMATIC);
  ui->host = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_container_add(GTK_CONTAINER(ui->scroll), ui->host);
  gtk_container_add(GTK_CONTAINER(ui->overlay), ui->scroll);
  gtk_container_add(GTK_CONTAINER(ui->window), ui->overlay);
  g_signal_connect(ui->window, "key-press-event", G_CALLBACK(on_key), ui);
  g_signal_connect(ui->window, "delete-event", G_CALLBACK(on_delete), ui);
  show_page(ui);
}

static void ui_init(Ui *ui, const OtzUiOptions *options) {
  memset(ui, 0, sizeof *ui);
  ui->options = options;
  ui->english = otz_english();
  ui->hero_preview_ms = -1;
  ui->history = g_array_new(FALSE, FALSE, sizeof(Page));
  ui->others = g_ptr_array_new_with_free_func(target_free);
  ui->other_index = -1;
  ui->custom_checked = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
  ui->custom_cards = g_ptr_array_new();
  ui->reveal_when_done = TRUE;
  ui->os_release = otz_read_os_release();
  ui->page_id = PAGE_WELCOME;
  target_clear(&ui->this_target);
  target_clear(&ui->job_target);
}

static void ui_clear(Ui *ui) {
  if (ui->window != NULL) gtk_widget_destroy(ui->window);
  if (ui->job != NULL) otz_job_free(ui->job);
  g_clear_object(&ui->cancel);
  g_clear_object(&ui->load_cancel);
  if (!ui->borrowed_manifest) otz_manifest_free(ui->manifest);
  g_free(ui->pinned_tag);
  g_free(ui->os_release);
  g_free(ui->error_message);
  g_free(ui->error_technical);
  g_free(ui->preset_id);
  g_free(ui->presets_key);
  g_free(ui->base_dir);
  g_free(ui->result_dir);
  g_free(ui->status.detail);
  g_array_unref(ui->history);
  g_ptr_array_unref(ui->others);
  g_ptr_array_unref(ui->custom_cards);
  g_hash_table_unref(ui->custom_checked);
  g_clear_pointer(&ui->presets, g_ptr_array_unref);
  g_clear_pointer(&ui->job_ids, g_ptr_array_unref);
  g_clear_pointer(&ui->file_names, g_hash_table_unref);
  g_clear_pointer(&ui->result_files, g_ptr_array_unref);
  g_clear_pointer(&ui->result_unjoined, g_ptr_array_unref);
  g_clear_pointer(&ui->result_notes, g_ptr_array_unref);
  target_set(&ui->this_target, NULL, NULL, NULL);
  g_free(ui->this_target.platform);
  g_free(ui->this_target.architecture);
  g_free(ui->this_target.format);
  g_free(ui->job_target.platform);
  g_free(ui->job_target.architecture);
  g_free(ui->job_target.format);
}

static void on_destroy(GtkWidget *window, Ui *ui) {
  ui->window = NULL;
  gtk_main_quit();
}

static gboolean quit_self_test(gpointer data) {
  quit(data);
  return G_SOURCE_REMOVE;
}

static gboolean animations_enabled(void) {
  gboolean enabled = TRUE;
  g_object_get(gtk_settings_get_default(), "gtk-enable-animations", &enabled, NULL);
  return enabled;
}

/* ------------------------------------------------------------- snapshots */

typedef struct {
  const char *name;
  void (*build)(Ui *ui);
} Scenario;

static OtzManifest *snapshot_manifest = NULL;

static void s_loaded(Ui *ui) {
  ui->borrowed_manifest = TRUE;
  loaded(ui, snapshot_manifest);
}

static void s_to_other(Ui *ui, const char *platform, const char *arch, const char *format) {
  s_loaded(ui);
  ui->mode = MODE_OTHER;
  next(ui);
  for (guint i = 0; i < ui->others->len; i++) {
    const Target *target = g_ptr_array_index(ui->others, i);
    if (strcmp(target->platform, platform) == 0 &&
        strcmp(target->architecture, arch) == 0 && strcmp(target->format, format) == 0)
      ui->other_index = (int)i;
  }
  show_page(ui);
}

static const char *component_asset(const char *id) {
  const OtzComponent *component = otz_manifest_find(snapshot_manifest, id);
  if (component == NULL || component->assets->len == 0) return "";
  return ((OtzAsset *)g_ptr_array_index(component->assets, 0))->name;
}

static void s_status(Ui *ui, OtzPhase phase, const char *id, gint64 done, gint64 total,
                     double speed, double eta) {
  g_clear_pointer(&ui->job_ids, g_ptr_array_unref);
  ui->job_ids = g_ptr_array_new_with_free_func(g_free);
  g_ptr_array_add(ui->job_ids, g_strdup(id));
  build_file_names(ui);
  ui->status = (Status){TRUE, phase, done, total, 0, 4, g_strdup(component_asset(id)),
                        speed, eta};
  ui->page_id = PAGE_WORKING;
  show_page(ui);
}

static void s_result(Ui *ui, const char *folder, const char *const *files,
                     const char *unjoined, const char *note_id) {
  g_free(ui->result_dir);
  ui->result_dir = g_strdup(folder);
  ui->result_files = g_ptr_array_new_with_free_func(g_free);
  for (int i = 0; files[i] != NULL; i++)
    g_ptr_array_add(ui->result_files, g_strdup(files[i]));
  ui->result_unjoined = g_ptr_array_new_with_free_func(g_free);
  if (unjoined != NULL) g_ptr_array_add(ui->result_unjoined, g_strdup(unjoined));
  ui->result_notes = g_ptr_array_new_with_free_func(g_free);
  const OtzComponent *noted =
      note_id != NULL ? otz_manifest_find(snapshot_manifest, note_id) : NULL;
  if (noted != NULL && *otz_component_output_note(noted, ui->english) != '\0')
    g_ptr_array_add(ui->result_notes,
                    g_strdup(otz_component_output_note(noted, ui->english)));
  ui->page_id = PAGE_FINISHED;
  show_page(ui);
}

static char *s_folder(Ui *ui, const char *platform) {
  g_autofree char *name =
      ui->english ? otz_trf(S_OUTPUT_SUBFOLDER, otz_platform_display_name(platform), NULL)
                  : otz_output_subfolder_name(platform);
  return g_build_filename(ui->base_dir, name, NULL);
}

static void sc_welcome(Ui *ui) {
  ui->hero_played = TRUE;
  show_page(ui);
}
static void sc_connecting(Ui *ui) {
  ui->page_id = PAGE_CONNECTING;
  show_page(ui);
}
static void sc_mode(Ui *ui) { s_loaded(ui); }
static void sc_other(Ui *ui) {
  s_loaded(ui);
  ui->mode = MODE_OTHER;
  next(ui);
}
static void sc_presets(Ui *ui) {
  s_loaded(ui);
  next(ui);
}
static void sc_presets_windows(Ui *ui) {
  s_to_other(ui, "windows", "x64", "");
  next(ui);
}
static void sc_custom(Ui *ui) {
  sc_presets(ui);
  g_free(ui->preset_id);
  ui->preset_id = g_strdup(CUSTOM_ID);
  next(ui);
}
static void sc_custom_windows(Ui *ui) {
  sc_presets_windows(ui);
  g_free(ui->preset_id);
  ui->preset_id = g_strdup(CUSTOM_ID);
  next(ui);
}
static void sc_folder(Ui *ui) {
  sc_presets(ui);
  next(ui);
}
static void sc_folder_fallback(Ui *ui) {
  ui->fell_back = TRUE;
  sc_folder(ui);
  ui->fell_back = TRUE;
  show_page(ui);
}
static void sc_ready(Ui *ui) {
  sc_folder(ui);
  next(ui);
}
static void sc_downloading(Ui *ui) {
  s_loaded(ui);
  s_status(ui, OTZ_PHASE_DOWNLOAD, "otzaria-linux-full-x64", G_GINT64_CONSTANT(1288490188),
           G_GINT64_CONSTANT(3758096384), 7654604, 44 * 60);
}
static void sc_joining(Ui *ui) {
  s_loaded(ui);
  s_status(ui, OTZ_PHASE_ASSEMBLE, "otzaria-linux-full-x64", G_GINT64_CONSTANT(1073741824),
           G_GINT64_CONSTANT(1986422374), -1, -1);
}
static void sc_finished_this(Ui *ui) {
  s_loaded(ui);
  static const char *const files[] = {"otzaria-0.10.3+143-linux.deb", NULL};
  s_result(ui, ui->base_dir, files, NULL, NULL);
}
static void sc_finished_other(Ui *ui) {
  s_to_other(ui, "windows", "x64", "");
  static const char *const files[] = {"otzaria-0.10.3-windows.exe",
                                      "otzaria-0.10.3-library.tar.zst.part-000",
                                      "otzaria-0.10.3-library.tar.zst.part-001", NULL};
  g_autofree char *folder = s_folder(ui, "windows");
  s_result(ui, folder, files, NULL, "library-full");
}
static void sc_finished_parts(Ui *ui) {
  s_to_other(ui, "linux", "arm64", "deb");
  static const char *const files[] = {"otzaria-linux-full-arm64.tar.zst.part-000",
                                      "otzaria-linux-full-arm64.tar.zst.part-001", NULL};
  g_autofree char *folder = s_folder(ui, "linux");
  s_result(ui, folder, files, "otzaria-linux-full-arm64.tar.zst", NULL);
}
static void sc_error_offline(Ui *ui) {
  show_failure(ui, FAIL_OFFLINE, "לא ניתן להתחבר לאתר ההורדות של אוצריא.",
               "api.github.com: Error resolving \xE2\x80\x9C" "api.github.com"
               "\xE2\x80\x9D: Name or service not known");
}
static void sc_error_list(Ui *ui) {
  show_failure(ui, FAIL_LOAD, "לא ניתן לקרוא את רשימת הקבצים של אוצריא.",
               "manifest: unsupported schemaVersion 2");
}
static void sc_error_file(Ui *ui) {
  s_loaded(ui);
  show_failure(ui, FAIL_RUN, "לא ניתן להכין את ההתקנה משום שאחד הקבצים הדרושים אינו זמין.",
               "HTTP 404 for otzaria-linux-full.tar.zst");
  ui->show_technical = TRUE;
  show_page(ui);
}
static void sc_stopped(Ui *ui) {
  s_loaded(ui);
  show_failure(ui, FAIL_STOPPED, NULL, NULL);
}
static void sc_tls(Ui *ui) {
  show_failure(ui, FAIL_TLS, NULL, "g_tls_backend_supports_tls() is FALSE");
}
static void sc_dialog_stop(Ui *ui) {
  s_loaded(ui);
  s_status(ui, OTZ_PHASE_DOWNLOAD, "otzaria-linux-deb-x64", 40000000, 90177536, 5000000,
           10);
  request_stop(ui);
}
static void sc_dialog_exit(Ui *ui) {
  s_loaded(ui);
  s_status(ui, OTZ_PHASE_DOWNLOAD, "otzaria-linux-deb-x64", 40000000, 90177536, 5000000,
           10);
  on_delete(ui->window, NULL, ui);
}
static void sc_dialog_no_target(Ui *ui) {
  sc_other(ui);
  next(ui);
}
static void sc_dialog_space(Ui *ui) {
  sc_ready(ui);
  g_autofree char *size = otz_size_text(G_GINT64_CONSTANT(128849018880));
  g_autofree char *text = otz_trf(S_SPACE_TEXT, size, NULL);
  ask(ui, otz_tr(S_SPACE_TITLE), text, otz_tr(S_SPACE_YES), otz_tr(S_CANCEL), FALSE,
      NULL);
}
static void sc_keyboard(Ui *ui) {
  sc_presets(ui);
  gtk_window_set_focus_visible(GTK_WINDOW(ui->window), TRUE);
}

static const Scenario scenarios[] = {
    {"welcome", sc_welcome},
    {"connecting", sc_connecting},
    {"mode", sc_mode},
    {"other", sc_other},
    {"presets", sc_presets},
    {"presets_windows", sc_presets_windows},
    {"custom", sc_custom},
    {"custom_windows", sc_custom_windows},
    {"folder", sc_folder},
    {"folder_fallback", sc_folder_fallback},
    {"ready", sc_ready},
    {"downloading", sc_downloading},
    {"joining", sc_joining},
    {"finished_this", sc_finished_this},
    {"finished_other", sc_finished_other},
    {"finished_parts", sc_finished_parts},
    {"error_offline", sc_error_offline},
    {"error_list", sc_error_list},
    {"error_file", sc_error_file},
    {"stopped", sc_stopped},
    {"tls", sc_tls},
    {"dialog_stop", sc_dialog_stop},
    {"dialog_exit", sc_dialog_exit},
    {"dialog_no_target", sc_dialog_no_target},
    {"dialog_space", sc_dialog_space},
    {"keyboard", sc_keyboard},
};

static void settle(void) {
  for (int round = 0; round < 30; round++) {
    while (gtk_events_pending()) gtk_main_iteration_do(FALSE);
    g_usleep(5000);
  }
}

static gboolean capture(GtkWidget *window, const char *path) {
  int width = gtk_widget_get_allocated_width(window);
  int height = gtk_widget_get_allocated_height(window);
  int scale = gtk_widget_get_scale_factor(window);
  cairo_surface_t *surface =
      cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width * scale, height * scale);
  cairo_surface_set_device_scale(surface, scale, scale);
  cairo_t *cr = cairo_create(surface);
  gtk_widget_draw(window, cr);
  cairo_destroy(cr);
  gboolean ok = cairo_surface_write_to_png(surface, path) == CAIRO_STATUS_SUCCESS;
  cairo_surface_destroy(surface);
  return ok;
}

static Ui *snapshot_ui(const OtzUiOptions *options) {
  Ui *ui = g_new0(Ui, 1);
  ui_init(ui, options);
  ui->snapshot = TRUE;
  ui->hero_played = TRUE;
  ui->base_dir = g_strdup("/home/user/Downloads");
  build_window(ui);
  g_signal_connect(ui->window, "destroy", G_CALLBACK(gtk_widget_destroyed), &ui->window);
  gtk_window_move(GTK_WINDOW(ui->window), 540, 0);
  gtk_widget_show_all(ui->window);
  gtk_window_set_focus_visible(GTK_WINDOW(ui->window), FALSE);
  return ui;
}

static void snapshot_done(Ui *ui) {
  ui_clear(ui);
  g_free(ui);
}

/* Fixture sizes are in bytes; as MiB the screens look like a real release. */
static void scale_sizes(OtzManifest *manifest) {
  for (guint i = 0; i < manifest->components->len; i++) {
    OtzComponent *component = g_ptr_array_index(manifest->components, i);
    component->download_size *= 1048576;
    for (guint a = 0; a < component->assets->len; a++) {
      OtzAsset *asset = g_ptr_array_index(component->assets, a);
      asset->size *= 1048576;
      for (guint p = 0; p < asset->parts->len; p++)
        ((OtzPart *)g_ptr_array_index(asset->parts, p))->size *= 1048576;
    }
  }
}

static int run_snapshots(const OtzUiOptions *options) {
  g_autoptr(GError) error = NULL;
  snapshot_manifest =
      options->dev_manifest != NULL ? otz_load_manifest_file(options->dev_manifest, &error)
                                    : NULL;
  if (snapshot_manifest == NULL) {
    g_printerr("--dev-screenshot needs --dev-manifest: %s\n",
               error != NULL ? error->message : "missing");
    return 2;
  }
  scale_sizes(snapshot_manifest);
  g_mkdir_with_parents(options->dev_screenshot, 0755);
  otz_set_frozen_time(1000);
  gboolean book = FALSE;
  for (int language = 0; language < 2; language++) {
    gboolean english = language == 1;
    otz_set_english(english);
    gtk_widget_set_default_direction(english ? GTK_TEXT_DIR_LTR : GTK_TEXT_DIR_RTL);
    const char *tag = english ? "en" : "he";
    for (gsize i = 0; i < G_N_ELEMENTS(scenarios); i++) {
      Ui *ui = snapshot_ui(options);
      if (!book) {
        otz_book_prepare_sync(gtk_widget_get_scale_factor(ui->window));
        book = TRUE;
      }
      scenarios[i].build(ui);
      settle();
      g_autofree char *file = g_strdup_printf("%s/%s_%02d_%s.png", options->dev_screenshot,
                                              tag, (int)i + 1, scenarios[i].name);
      if (!capture(ui->window, file)) {
        g_printerr("capture failed: %s\n", file);
        return 1;
      }
      printf("wrote %s\n", file);
      snapshot_done(ui);
    }
    g_autofree char *hero_dir = g_strdup_printf("%s/hero_%s", options->dev_screenshot, tag);
    g_mkdir_with_parents(hero_dir, 0755);
    int index = 0;
    for (double ms = 0; ms < HERO_END_MS + 84; ms += 84, index++) {
      Ui *ui = snapshot_ui(options);
      ui->hero_played = FALSE;
      ui->hero_preview_ms = MIN(ms, HERO_END_MS);
      show_page(ui);
      if (ms >= HERO_END_MS) hero_finish(ui);
      settle();
      g_autofree char *file =
          g_strdup_printf("%s/frame_%03d_%04d.png", hero_dir, index, (int)ms);
      capture(ui->window, file);
      snapshot_done(ui);
    }
    printf("wrote hero frames for %s\n", tag);
  }
  otz_manifest_free(snapshot_manifest);
  return 0;
}

/* ------------------------------------------------------------- run */

int otz_ui_run(const OtzUiOptions *options) {
  otz_theme_install();
  if (options->dev_screenshot != NULL) return run_snapshots(options);

  Ui ui;
  ui_init(&ui, options);
  gtk_widget_set_default_direction(ui.english ? GTK_TEXT_DIR_LTR : GTK_TEXT_DIR_RTL);
  gboolean animate = animations_enabled() && options->dev_auto_preset == NULL &&
                     otz_art_load("book_23_250") != NULL;
  ui.hero_played = !animate;
  build_window(&ui);
  g_signal_connect(ui.window, "destroy", G_CALLBACK(on_destroy), &ui);
  gtk_widget_show_all(ui.window);
  if (animate)
    otz_book_prepare_async(gtk_widget_get_scale_factor(ui.window),
                           G_CALLBACK(on_book_ready), &ui);

  if (options->self_test)
    g_timeout_add(500, quit_self_test, &ui);
  else if (options->dev_auto_preset != NULL)
    load(&ui);
  gtk_main();

  int code = ui.exit_code;
  if (ui.load_cancel != NULL) g_cancellable_cancel(ui.load_cancel);
  ui_clear(&ui);
  return code;
}
