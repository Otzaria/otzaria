#include "widgets.h"

#include <math.h>
#include <string.h>

#include "texts.h"

/* The colours of the Windows assistant (assistant_art.isi), which are those of
 * Otzaria's light theme. */
enum {
  C_PAGE = 0xF6EDE5,
  C_CARD = 0xFFF8F4,
  C_CARD_SELECTED = 0xFEF0E3,
  C_CARD_SELECTED_HOVER = 0xFCEADB,
  C_CARD_HOVER = 0xF5EBE2,
  C_DIVIDER = 0xD3C4B4,
  C_OUTLINE = 0x817567,
  C_PRIMARY = 0x805610,
  C_PRIMARY_HOVER = 0x8A6423,
  C_PRIMARY_PRESSED = 0x8F6A2D,
  C_TONAL = 0xFBDEBC,
  C_TONAL_HOVER = 0xEED2B0,
  C_TONAL_PRESSED = 0xE7CCAA,
  C_GHOST_HOVER = 0xEDE1D4,
  C_GHOST_PRESSED = 0xE8DBCB,
  C_MUTED = 0x4F4539,
  C_ERROR = 0xBA1A1A,
  C_DOT_DONE = 0xBBA27A,
  C_FIELD = 0xFFFFFF,
  C_DIALOG = 0xF3E6DA,
};

#define RADIUS 8
#define DIALOG_RADIUS 14
#define DIALOG_SHADOW 16

/* Everything inside the window is reset, so no rule of the desktop theme (a
 * dark one included) reaches it; what is drawn is defined here. */
static const char *const css =
    "window.otz { background-color: #F6EDE5; color: #201B13; }\n"
    "window.otz * { all: unset; }\n"
    "window.otz.csd:not(.solid-csd) { border-radius: 8px 8px 0 0; }\n"
    "window.otz decoration { border-radius: 8px 8px 0 0; margin: 10px;"
    "  box-shadow: 0 3px 9px 1px rgba(0,0,0,0.5), 0 0 0 1px rgba(0,0,0,0.23); }\n"
    "window.otz decoration:backdrop { box-shadow: 0 3px 9px 1px transparent,"
    "  0 2px 6px 2px rgba(0,0,0,0.2), 0 0 0 1px rgba(0,0,0,0.18); }\n"
    "window.otz.solid-csd decoration, window.otz.maximized decoration,"
    "  window.otz.fullscreen decoration, window.otz.tiled decoration {"
    "  margin: 0; border-radius: 0; box-shadow: none; }\n"
    "window.otz headerbar { background-color: #F3E6DA; min-height: 31px;"
    "  border-bottom: 1px solid #E1D4C8; }\n"
    "window.otz.csd:not(.solid-csd) headerbar { border-radius: 8px 8px 0 0; }\n"
    "window.otz headerbar button.titlebutton { min-width: 46px; min-height: 31px; }\n"
    "window.otz headerbar button.titlebutton:hover { background-color: #EDE4DC; }\n"
    "window.otz headerbar button.titlebutton:active { background-color: #E5DAD0; }\n"
    "window.otz headerbar button.titlebutton image { color: #1A1918;"
    "  -gtk-icon-style: symbolic; }\n"
    "window.otz .t-wintitle { font-size: 13px; color: #201B13; }\n"
    "window.otz radio, window.otz check { min-width: 0; min-height: 0;"
    "  -gtk-icon-source: none; }\n"
    "window.otz selection { background-color: #FBDEBC; color: #201B13; }\n"
    "window.otz scrollbar { background-color: transparent; }\n"
    "window.otz scrollbar.vertical slider { min-width: 4px; min-height: 40px;"
    "  margin: 2px 3px; border-radius: 2px; background-color: #CDBFB1; }\n"
    "window.otz scrollbar.vertical slider:hover { background-color: #B3AAA0; }\n"
    "window.otz scrollbar.vertical slider:active { background-color: #817567; }\n"
    "window.otz .t-title { font-size: 20px; font-weight: 600; color: #201B13; }\n"
    "window.otz .t-desc { font-size: 14px; color: #4F4539; }\n"
    "window.otz .t-hint { font-size: 13px; color: #4F4539; }\n"
    "window.otz .t-step { font-size: 12px; color: #817567; }\n"
    "window.otz .t-card-title { font-size: 16px; color: #201B13; }\n"
    "window.otz .t-card-desc { font-size: 13px; color: #4F4539; }\n"
    "window.otz .t-card-side { font-size: 12px; color: #817567; }\n"
    "window.otz .t-btn { font-size: 14px; font-weight: 600; }\n"
    "window.otz .k-primary .t-btn { color: #FFFFFF; }\n"
    "window.otz .k-tonal .t-btn { color: #56442A; }\n"
    "window.otz .k-ghost .t-btn { color: #805610; }\n"
    "window.otz .k-danger .t-btn { color: #BA1A1A; }\n"
    "window.otz .t-link { font-size: 13px; font-weight: 600; color: #805610; }\n"
    "window.otz .t-field { font-size: 14px; color: #201B13; }\n"
    "window.otz .t-percent { font-size: 40px; font-weight: 700; color: #805610; }\n"
    "window.otz .t-caption { font-size: 14px; color: #201B13; }\n"
    "window.otz .t-detail { font-size: 13px; color: #4F4539; }\n"
    "window.otz .t-detail-faint { font-size: 13px; color: #817567; }\n"
    "window.otz .t-hero-note { font-size: 13px; color: #4F4539; }\n"
    "window.otz .t-dialog-title { font-size: 18px; font-weight: 600; color: #201B13; }\n"
    "window.otz .t-dialog-text { font-size: 14px; color: #4F4539; }\n"
    "window.otz .t-row-label { font-size: 12px; color: #817567; }\n"
    "window.otz .t-row-value { font-size: 16px; color: #201B13; }\n"
    "window.otz .t-mono { font-family: monospace; font-size: 12px; color: #201B13; }\n";

void otz_theme_install(void) {
  GtkSettings *settings = gtk_settings_get_default();
  /* Light only: the file chooser and anything GTK draws itself follow too. */
  g_object_set(settings, "gtk-theme-name", "Adwaita",
               "gtk-application-prefer-dark-theme", FALSE, NULL);
  GtkCssProvider *provider = gtk_css_provider_new();
  gtk_css_provider_load_from_data(provider, css, -1, NULL);
  gtk_style_context_add_provider_for_screen(
      gdk_screen_get_default(), GTK_STYLE_PROVIDER(provider),
      GTK_STYLE_PROVIDER_PRIORITY_USER + 1);
  g_object_unref(provider);
}

/* ------------------------------------------------------------- drawing */

static void set_rgb(cairo_t *cr, guint32 hex) {
  cairo_set_source_rgb(cr, ((hex >> 16) & 0xFF) / 255.0, ((hex >> 8) & 0xFF) / 255.0,
                       (hex & 0xFF) / 255.0);
}

static void set_rgba(cairo_t *cr, guint32 hex, double alpha) {
  cairo_set_source_rgba(cr, ((hex >> 16) & 0xFF) / 255.0,
                        ((hex >> 8) & 0xFF) / 255.0, (hex & 0xFF) / 255.0, alpha);
}

static void rounded(cairo_t *cr, double x, double y, double w, double h, double r) {
  r = MIN(r, MIN(w, h) / 2);
  cairo_new_sub_path(cr);
  cairo_arc(cr, x + w - r, y + r, r, -G_PI / 2, 0);
  cairo_arc(cr, x + w - r, y + h - r, r, 0, G_PI / 2);
  cairo_arc(cr, x + r, y + h - r, r, G_PI / 2, G_PI);
  cairo_arc(cr, x + r, y + r, r, G_PI, 3 * G_PI / 2);
  cairo_close_path(cr);
}

/* 2px in the primary colour, 1px outside the body (UiDrawFocusRect). */
static void focus_ring(cairo_t *cr, double x, double y, double w, double h,
                       double radius) {
  rounded(cr, x - 2, y - 2, w + 4, h + 4, radius + 2);
  set_rgb(cr, C_PRIMARY);
  cairo_set_line_width(cr, 2);
  cairo_stroke(cr);
}

static void body_rect(GtkWidget *widget, double *x, double *y, double *w, double *h) {
  *x = OTZ_RING;
  *y = OTZ_RING;
  *w = gtk_widget_get_allocated_width(widget) - 2 * OTZ_RING;
  *h = gtk_widget_get_allocated_height(widget) - 2 * OTZ_RING;
}

static double frozen_ms = -1;

void otz_set_frozen_time(double ms) { frozen_ms = ms; }

double otz_frozen_time(void) { return frozen_ms; }

/* ------------------------------------------------------------- art */

typedef struct {
  const guint8 *data;
  gsize length, position;
} PngReader;

static cairo_status_t read_png(void *closure, unsigned char *buffer,
                               unsigned int length) {
  PngReader *reader = closure;
  if (reader->position + length > reader->length) return CAIRO_STATUS_READ_ERROR;
  memcpy(buffer, reader->data + reader->position, length);
  reader->position += length;
  return CAIRO_STATUS_SUCCESS;
}

static cairo_surface_t *load_uncached(const char *name) {
  g_autofree char *path = g_strdup_printf("/org/otzaria/assistant/%s.png", name);
  g_autoptr(GBytes) bytes =
      g_resources_lookup_data(path, G_RESOURCE_LOOKUP_FLAGS_NONE, NULL);
  if (bytes == NULL) return NULL;
  PngReader reader = {0};
  reader.data = g_bytes_get_data(bytes, &reader.length);
  cairo_surface_t *surface = cairo_image_surface_create_from_png_stream(read_png, &reader);
  if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
    cairo_surface_destroy(surface);
    return NULL;
  }
  return surface;
}

static GHashTable *art_cache = NULL;

static GHashTable *cache(void) {
  if (art_cache == NULL)
    art_cache = g_hash_table_new_full(g_str_hash, g_str_equal, g_free,
                                      (GDestroyNotify)cairo_surface_destroy);
  return art_cache;
}

cairo_surface_t *otz_art_load(const char *name) {
  if (g_hash_table_contains(cache(), name)) return g_hash_table_lookup(cache(), name);
  cairo_surface_t *surface = load_uncached(name);
  g_hash_table_insert(cache(), g_strdup(name), surface);
  return surface;
}

/* Resampled once with the best filter, so drawing is 1:1 at the device scale. */
static cairo_surface_t *resample(cairo_surface_t *source, int width, int height) {
  cairo_surface_t *target = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
  cairo_t *cr = cairo_create(target);
  cairo_scale(cr, (double)width / cairo_image_surface_get_width(source),
              (double)height / cairo_image_surface_get_height(source));
  cairo_set_source_surface(cr, source, 0, 0);
  cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_BEST);
  cairo_paint(cr);
  cairo_destroy(cr);
  return target;
}

static double device_scale(cairo_t *cr) {
  double sx = 1, sy = 1, dx = 1, dy = 0;
  cairo_surface_get_device_scale(cairo_get_target(cr), &sx, &sy);
  cairo_user_to_device_distance(cr, &dx, &dy);
  return sx * sqrt(dx * dx + dy * dy);
}

gboolean otz_art_paint(cairo_t *cr, const char *name, double x, double y, double w,
                       double h) {
  cairo_surface_t *source = otz_art_load(name);
  if (source == NULL) return FALSE;
  double scale = device_scale(cr);
  int pixel_w = MAX(1, (int)lround(w * scale));
  int pixel_h = MAX(1, (int)lround(h * scale));
  g_autofree char *key = g_strdup_printf("%s@%dx%d", name, pixel_w, pixel_h);
  cairo_surface_t *scaled = g_hash_table_lookup(cache(), key);
  if (scaled == NULL) {
    scaled = resample(source, pixel_w, pixel_h);
    g_hash_table_insert(cache(), g_strdup(key), scaled);
  }
  cairo_save(cr);
  cairo_translate(cr, x, y);
  cairo_scale(cr, w / pixel_w, h / pixel_h);
  cairo_set_source_surface(cr, scaled, 0, 0);
  cairo_paint(cr);
  cairo_restore(cr);
  return TRUE;
}

static cairo_surface_t *book[OTZ_BOOK_FRAMES];
static gboolean book_ready = FALSE;

static cairo_surface_t **prepare_frames(int scale) {
  cairo_surface_t **frames = g_new0(cairo_surface_t *, OTZ_BOOK_FRAMES);
  for (int i = 0; i < OTZ_BOOK_FRAMES; i++) {
    g_autofree char *name = g_strdup_printf("book_%02d_250", i);
    cairo_surface_t *source = load_uncached(name);
    if (source == NULL) continue;
    frames[i] = resample(source, 220 * scale, 220 * scale);
    cairo_surface_set_device_scale(frames[i], scale, scale);
    cairo_surface_destroy(source);
  }
  return frames;
}

static void adopt_frames(cairo_surface_t **frames) {
  for (int i = 0; i < OTZ_BOOK_FRAMES; i++) {
    if (book[i] != NULL) cairo_surface_destroy(book[i]);
    book[i] = frames[i];
  }
  g_free(frames);
  book_ready = TRUE;
}

static void prepare_in_thread(GTask *task, gpointer source, gpointer data,
                              GCancellable *cancellable) {
  g_task_return_pointer(task, prepare_frames(GPOINTER_TO_INT(data)), NULL);
}

typedef struct {
  GCallback ready;
  gpointer data;
} BookReady;

static void on_frames(GObject *source, GAsyncResult *result, gpointer data) {
  BookReady *done = data;
  adopt_frames(g_task_propagate_pointer(G_TASK(result), NULL));
  ((void (*)(gpointer))done->ready)(done->data);
  g_free(done);
}

void otz_book_prepare_async(int scale, GCallback ready, gpointer data) {
  BookReady *done = g_new0(BookReady, 1);
  done->ready = ready;
  done->data = data;
  g_autoptr(GTask) task = g_task_new(NULL, NULL, on_frames, done);
  g_task_set_task_data(task, GINT_TO_POINTER(scale), NULL);
  g_task_run_in_thread(task, prepare_in_thread);
}

void otz_book_prepare_sync(int scale) { adopt_frames(prepare_frames(scale)); }

gboolean otz_book_ready(void) { return book_ready && book[OTZ_BOOK_FRAMES - 1] != NULL; }

cairo_surface_t *otz_book_frame(int index) {
  return book_ready ? book[CLAMP(index, 0, OTZ_BOOK_FRAMES - 1)] : NULL;
}

GdkPixbuf *otz_app_icon(void) {
  cairo_surface_t *logo = otz_art_load("app_icon");
  if (logo == NULL) return NULL;
  return gdk_pixbuf_get_from_surface(logo, 0, 0, cairo_image_surface_get_width(logo),
                                     cairo_image_surface_get_height(logo));
}

/* ------------------------------------------------------------- labels */

GtkWidget *otz_label(const char *text, const char *css_class) {
  GtkWidget *label = gtk_label_new(NULL);
  otz_label_set(label, text);
  if (css_class != NULL)
    gtk_style_context_add_class(gtk_widget_get_style_context(label), css_class);
  return label;
}

void otz_label_set(GtkWidget *label, const char *text) {
  g_autofree char *shown = otz_bidi(text != NULL ? text : "");
  gtk_label_set_text(GTK_LABEL(label), shown);
}

/* max-width-chars keeps the natural width from growing the fixed window. */
GtkWidget *otz_wrap_label(const char *text, const char *css_class, int width,
                          float xalign) {
  GtkWidget *label = otz_label(text, css_class);
  gtk_label_set_line_wrap(GTK_LABEL(label), TRUE);
  gtk_label_set_line_wrap_mode(GTK_LABEL(label), PANGO_WRAP_WORD_CHAR);
  gtk_label_set_max_width_chars(GTK_LABEL(label), 1);
  gtk_label_set_xalign(GTK_LABEL(label), xalign);
  gtk_label_set_justify(GTK_LABEL(label),
                        xalign == 0.5f ? GTK_JUSTIFY_CENTER : GTK_JUSTIFY_LEFT);
  gtk_widget_set_size_request(label, width, -1);
  gtk_widget_set_halign(label, GTK_ALIGN_CENTER);
  return label;
}

/* ------------------------------------------------------------- buttons */

static gboolean draw_button(GtkWidget *widget, cairo_t *cr, gpointer data) {
  OtzButtonKind kind = GPOINTER_TO_INT(data);
  GtkStateFlags state = gtk_widget_get_state_flags(widget);
  gboolean pressed = (state & GTK_STATE_FLAG_ACTIVE) != 0;
  gboolean hover = (state & GTK_STATE_FLAG_PRELIGHT) != 0;
  double x, y, w, h;
  body_rect(widget, &x, &y, &w, &h);
  guint32 fill = 0;
  gboolean filled = TRUE;
  switch (kind) {
    case OTZ_BUTTON_PRIMARY:
      fill = pressed ? C_PRIMARY_PRESSED : hover ? C_PRIMARY_HOVER : C_PRIMARY;
      break;
    case OTZ_BUTTON_TONAL:
      fill = pressed ? C_TONAL_PRESSED : hover ? C_TONAL_HOVER : C_TONAL;
      break;
    case OTZ_BUTTON_GHOST:
    case OTZ_BUTTON_DANGER:
      fill = pressed ? C_GHOST_PRESSED : C_GHOST_HOVER;
      filled = pressed || hover;
      break;
    case OTZ_BUTTON_LINK:
      filled = FALSE;
      break;
  }
  double radius = kind == OTZ_BUTTON_LINK ? 4 : RADIUS;
  if (filled) {
    rounded(cr, x, y, w, h, radius);
    set_rgb(cr, fill);
    cairo_fill(cr);
  }
  if (gtk_widget_has_visible_focus(widget)) focus_ring(cr, x, y, w, h, radius);
  return FALSE;
}

GtkWidget *otz_button(OtzButtonKind kind, const char *text, int width, int height) {
  static const char *const classes[] = {"k-primary", "k-tonal", "k-ghost", "k-danger",
                                        "k-link"};
  GtkWidget *button = gtk_button_new();
  GtkWidget *label =
      otz_label(text, kind == OTZ_BUTTON_LINK ? "t-link" : "t-btn");
  gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_END);
  gtk_container_add(GTK_CONTAINER(button), label);
  gtk_style_context_add_class(gtk_widget_get_style_context(button), classes[kind]);
  int pad = kind == OTZ_BUTTON_LINK ? 6 : 16;
  if (width > 0) {
    gtk_widget_set_size_request(button, width + 2 * OTZ_RING, height + 2 * OTZ_RING);
    gtk_widget_set_margin_start(label, pad + OTZ_RING);
    gtk_widget_set_margin_end(label, pad + OTZ_RING);
  } else {
    gtk_widget_set_margin_start(label, pad + OTZ_RING);
    gtk_widget_set_margin_end(label, pad + OTZ_RING);
    gtk_widget_set_size_request(button, -1, height + 2 * OTZ_RING);
  }
  gtk_widget_set_halign(button, GTK_ALIGN_CENTER);
  gtk_widget_set_valign(button, GTK_ALIGN_CENTER);
  gtk_widget_set_focus_on_click(button, FALSE);
  g_signal_connect(button, "draw", G_CALLBACK(draw_button), GINT_TO_POINTER(kind));
  return button;
}

static gboolean draw_field(GtkWidget *widget, cairo_t *cr, gpointer data) {
  double x, y, w, h;
  body_rect(widget, &x, &y, &w, &h);
  rounded(cr, x + 0.5, y + 0.5, w - 1, h - 1, RADIUS);
  set_rgb(cr, C_FIELD);
  cairo_fill_preserve(cr);
  GtkStateFlags state = gtk_widget_get_state_flags(widget);
  set_rgb(cr, state & GTK_STATE_FLAG_PRELIGHT ? C_MUTED : C_OUTLINE);
  cairo_set_line_width(cr, 1);
  cairo_stroke(cr);
  if (gtk_widget_has_visible_focus(widget)) focus_ring(cr, x, y, w, h, RADIUS);
  return FALSE;
}

GtkWidget *otz_field_button(const char *path) {
  GtkWidget *button = gtk_button_new();
  GtkWidget *label = gtk_label_new(path);
  gtk_style_context_add_class(gtk_widget_get_style_context(label), "t-field");
  gtk_widget_set_direction(label, GTK_TEXT_DIR_LTR);
  gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_MIDDLE);
  gtk_label_set_xalign(GTK_LABEL(label), 0);
  gtk_widget_set_margin_start(label, 12 + OTZ_RING);
  gtk_widget_set_margin_end(label, 12 + OTZ_RING);
  gtk_container_add(GTK_CONTAINER(button), label);
  gtk_widget_set_size_request(button, OTZ_CONTENT_WIDTH + 2 * OTZ_RING, 44 + 2 * OTZ_RING);
  gtk_widget_set_focus_on_click(button, FALSE);
  g_signal_connect(button, "draw", G_CALLBACK(draw_field), NULL);
  return button;
}

/* ------------------------------------------------------------- cards */

static gboolean draw_card(GtkWidget *widget, cairo_t *cr, gpointer data) {
  gboolean locked = GPOINTER_TO_INT(data);
  GtkStateFlags state = gtk_widget_get_state_flags(widget);
  gboolean on = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(widget));
  gboolean hover = !locked && (state & (GTK_STATE_FLAG_PRELIGHT | GTK_STATE_FLAG_ACTIVE));
  double x, y, w, h;
  body_rect(widget, &x, &y, &w, &h);
  rounded(cr, x, y, w, h, RADIUS);
  set_rgb(cr, on ? (hover ? C_CARD_SELECTED_HOVER : C_CARD_SELECTED)
                 : (hover ? C_CARD_HOVER : C_CARD));
  cairo_fill(cr);
  if (gtk_widget_has_visible_focus(widget)) focus_ring(cr, x, y, w, h, RADIUS);
  return FALSE;
}

/* The 20px radio or check box of radio_on/check_on, drawn. */
static gboolean draw_mark(GtkWidget *area, cairo_t *cr, gpointer data) {
  GtkWidget *card = data;
  gboolean on = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(card));
  if (GTK_IS_RADIO_BUTTON(card)) {
    cairo_arc(cr, 10, 10, 9, 0, 2 * G_PI);
    set_rgb(cr, on ? C_PRIMARY : C_MUTED);
    cairo_set_line_width(cr, 2);
    cairo_stroke(cr);
    if (on) {
      cairo_arc(cr, 10, 10, 5, 0, 2 * G_PI);
      cairo_fill(cr);
    }
    return TRUE;
  }
  if (on) {
    rounded(cr, 0, 0, 20, 20, 3);
    set_rgb(cr, C_PRIMARY);
    cairo_fill(cr);
    cairo_move_to(cr, 4.5, 10);
    cairo_line_to(cr, 8.5, 14);
    cairo_line_to(cr, 15.5, 6);
    cairo_set_source_rgb(cr, 1, 1, 1);
    cairo_set_line_width(cr, 2);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
    cairo_stroke(cr);
  } else {
    rounded(cr, 1, 1, 18, 18, 2);
    set_rgb(cr, C_MUTED);
    cairo_set_line_width(cr, 2);
    cairo_stroke(cr);
  }
  return TRUE;
}

static void redraw_card(GtkToggleButton *card, gpointer data) {
  gtk_widget_queue_draw(GTK_WIDGET(card));
}

GtkWidget *otz_card(const OtzCardSpec *spec, GSList **group) {
  GtkWidget *card;
  if (spec->check) {
    card = gtk_check_button_new();
  } else {
    card = gtk_radio_button_new(group != NULL ? *group : NULL);
    if (group != NULL) *group = gtk_radio_button_get_group(GTK_RADIO_BUTTON(card));
  }
  GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 14);
  gtk_widget_set_margin_start(row, 16 + OTZ_RING);
  gtk_widget_set_margin_end(row, 16 + OTZ_RING);
  gtk_widget_set_margin_top(row, 15 + OTZ_RING);
  gtk_widget_set_margin_bottom(row, 15 + OTZ_RING);
  int text_width = OTZ_CONTENT_WIDTH - 32;
  if (!spec->no_mark) {
    GtkWidget *mark = gtk_drawing_area_new();
    gtk_widget_set_size_request(mark, 20, 20);
    gtk_widget_set_valign(mark, GTK_ALIGN_CENTER);
    g_signal_connect(mark, "draw", G_CALLBACK(draw_mark), card);
    gtk_box_pack_start(GTK_BOX(row), mark, FALSE, FALSE, 0);
    text_width -= 20 + 14;
  }
  if (spec->icon != NULL) {
    GtkWidget *tile = otz_icon_tile(spec->icon);
    gtk_widget_set_valign(tile, GTK_ALIGN_CENTER);
    gtk_box_pack_start(GTK_BOX(row), tile, FALSE, FALSE, 0);
    text_width -= 40 + 14;
  }
  GtkWidget *texts = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_valign(texts, GTK_ALIGN_CENTER);
  GtkWidget *title = otz_wrap_label(spec->title, "t-card-title", text_width, 0);
  gtk_box_pack_start(GTK_BOX(texts), title, FALSE, FALSE, 0);
  if (spec->desc != NULL && *spec->desc != '\0') {
    GtkWidget *desc = otz_wrap_label(spec->desc, "t-card-desc", text_width, 0);
    gtk_widget_set_margin_top(desc, 3);
    gtk_box_pack_start(GTK_BOX(texts), desc, FALSE, FALSE, 0);
  }
  if (spec->side != NULL && *spec->side != '\0') {
    GtkWidget *side = otz_wrap_label(spec->side, "t-card-side", text_width, 0);
    gtk_widget_set_margin_top(side, 4);
    gtk_box_pack_start(GTK_BOX(texts), side, FALSE, FALSE, 0);
  }
  gtk_box_pack_start(GTK_BOX(row), texts, TRUE, TRUE, 0);
  gtk_container_add(GTK_CONTAINER(card), row);
  gtk_widget_set_size_request(card, OTZ_CONTENT_WIDTH + 2 * OTZ_RING, 68 + 2 * OTZ_RING);
  gtk_widget_set_halign(card, GTK_ALIGN_CENTER);
  gtk_widget_set_focus_on_click(card, FALSE);
  g_signal_connect(card, "draw", G_CALLBACK(draw_card), GINT_TO_POINTER(spec->locked));
  g_signal_connect(card, "toggled", G_CALLBACK(redraw_card), NULL);
  if (spec->locked) {
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(card), TRUE);
    gtk_widget_set_sensitive(card, FALSE);
  }
  g_autofree char *description =
      g_strjoin(spec->side != NULL && *spec->side != '\0' ? ". " : "",
                spec->desc != NULL ? spec->desc : "", spec->side != NULL ? spec->side : "",
                NULL);
  otz_accessible(card, spec->title, description);
  return card;
}

/* ------------------------------------------------------------- tiles */

static gboolean draw_tile(GtkWidget *area, cairo_t *cr, gpointer data) {
  const char *icon = data;
  g_autofree char *name = g_strdup_printf("ico_%s_200", icon);
  if (!otz_art_paint(cr, name, 0, 0, 40, 40)) {
    rounded(cr, 0, 0, 40, 40, RADIUS);
    set_rgb(cr, C_TONAL);
    cairo_fill(cr);
  }
  return TRUE;
}

GtkWidget *otz_icon_tile(const char *icon) {
  GtkWidget *area = gtk_drawing_area_new();
  gtk_widget_set_size_request(area, 40, 40);
  char *name = g_strdup(icon);
  g_object_set_data_full(G_OBJECT(area), "otz-icon", name, g_free);
  g_signal_connect(area, "draw", G_CALLBACK(draw_tile), name);
  return area;
}

static gboolean draw_badge(GtkWidget *area, cairo_t *cr, gpointer data) {
  const char *kind = data;
  g_autofree char *name = g_strdup_printf("badge_%s_200", kind);
  if (otz_art_paint(cr, name, 0, 0, 72, 72)) return TRUE;
  gboolean ok = strcmp(kind, "ok") == 0, err = strcmp(kind, "err") == 0;
  cairo_arc(cr, 36, 36, 36, 0, 2 * G_PI);
  set_rgba(cr, err ? C_ERROR : ok ? C_PRIMARY : C_MUTED, 0.11);
  cairo_fill(cr);
  cairo_arc(cr, 36, 36, 26, 0, 2 * G_PI);
  set_rgb(cr, err ? C_ERROR : ok ? C_PRIMARY : C_TONAL);
  cairo_fill(cr);
  return TRUE;
}

GtkWidget *otz_badge(const char *kind) {
  GtkWidget *area = gtk_drawing_area_new();
  gtk_widget_set_size_request(area, 72, 72);
  gtk_widget_set_halign(area, GTK_ALIGN_CENTER);
  g_signal_connect(area, "draw", G_CALLBACK(draw_badge), (gpointer)kind);
  return area;
}

/* ------------------------------------------------------------- steps */

static gboolean draw_dots(GtkWidget *area, cairo_t *cr, gpointer data) {
  int packed = GPOINTER_TO_INT(data);
  int current = packed >> 8, total = packed & 0xFF;
  double width = (total - 1) * 6 + 20 + (total - 1) * 6;
  double x = (gtk_widget_get_allocated_width(area) - width) / 2;
  gboolean rtl = gtk_widget_get_direction(area) == GTK_TEXT_DIR_RTL;
  for (int step = 1; step <= total; step++) {
    int index = rtl ? total + 1 - step : step;
    double w = index == current ? 20 : 6;
    rounded(cr, x, 0, w, 6, 3);
    set_rgb(cr, index == current ? C_PRIMARY : index < current ? C_DOT_DONE : C_DIVIDER);
    cairo_fill(cr);
    x += w + 6;
  }
  return TRUE;
}

GtkWidget *otz_step_dots(int current, int total) {
  GtkWidget *area = gtk_drawing_area_new();
  gtk_widget_set_size_request(area, OTZ_CONTENT_WIDTH, 6);
  gtk_widget_set_halign(area, GTK_ALIGN_CENTER);
  g_signal_connect(area, "draw", G_CALLBACK(draw_dots),
                   GINT_TO_POINTER((current << 8) | (total & 0xFF)));
  return area;
}

/* ------------------------------------------------------------- progress */

static double now_ms(void) {
  return frozen_ms >= 0 ? frozen_ms : g_get_monotonic_time() / 1000.0;
}

static gboolean draw_bar(GtkWidget *bar, cairo_t *cr, gpointer data) {
  double w = gtk_widget_get_allocated_width(bar);
  double h = 8;
  double y = (gtk_widget_get_allocated_height(bar) - h) / 2;
  gboolean rtl = gtk_widget_get_direction(bar) == GTK_TEXT_DIR_RTL;
  rounded(cr, 0, y, w, h, h / 2);
  set_rgb(cr, C_TONAL);
  cairo_fill_preserve(cr);
  cairo_clip(cr);
  set_rgb(cr, C_PRIMARY);
  if (g_object_get_data(G_OBJECT(bar), "otz-indeterminate") != NULL) {
    double segment = w * 0.3;
    double phase = fmod(now_ms(), 1600.0) / 1600.0;
    double start = -segment + (w + segment) * phase;
    rounded(cr, rtl ? w - start - segment : start, y, segment, h, h / 2);
  } else {
    double fraction = CLAMP(gtk_progress_bar_get_fraction(GTK_PROGRESS_BAR(bar)), 0, 1);
    double fill = MAX(h, w * fraction);
    rounded(cr, rtl ? w - fill : 0, y, fill, h, h / 2);
  }
  cairo_fill(cr);
  return TRUE;
}

static gboolean tick_bar(GtkWidget *bar, GdkFrameClock *clock, gpointer data) {
  gtk_widget_queue_draw(bar);
  return G_SOURCE_CONTINUE;
}

GtkWidget *otz_progress_bar(double fraction) {
  GtkWidget *bar = gtk_progress_bar_new();
  gtk_widget_set_size_request(bar, OTZ_CONTENT_WIDTH, 8);
  gtk_widget_set_halign(bar, GTK_ALIGN_CENTER);
  g_signal_connect(bar, "draw", G_CALLBACK(draw_bar), NULL);
  if (fraction < 0) {
    g_object_set_data(G_OBJECT(bar), "otz-indeterminate", GINT_TO_POINTER(1));
    if (frozen_ms < 0) gtk_widget_add_tick_callback(bar, tick_bar, NULL, NULL);
  } else {
    gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(bar), fraction);
  }
  return bar;
}

void otz_progress_bar_set(GtkWidget *bar, double fraction) {
  gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(bar), CLAMP(fraction, 0, 1));
}

static gboolean draw_divider(GtkWidget *area, cairo_t *cr, gpointer data) {
  set_rgb(cr, C_DIVIDER);
  cairo_paint(cr);
  return TRUE;
}

GtkWidget *otz_divider(void) {
  GtkWidget *area = gtk_drawing_area_new();
  gtk_widget_set_size_request(area, -1, 1);
  g_signal_connect(area, "draw", G_CALLBACK(draw_divider), NULL);
  return area;
}

/* ------------------------------------------------------------- summary */

/* One card for all the rows, with a strip of the page colour between them
 * (UiPlaceSummary). */
static gboolean draw_summary(GtkWidget *box, cairo_t *cr, gpointer data) {
  double w = gtk_widget_get_allocated_width(box);
  double h = gtk_widget_get_allocated_height(box);
  rounded(cr, 0, 0, w, h, RADIUS);
  cairo_clip(cr);
  set_rgb(cr, C_CARD);
  cairo_paint(cr);
  g_autoptr(GList) rows = gtk_container_get_children(GTK_CONTAINER(box));
  GtkAllocation box_alloc;
  gtk_widget_get_allocation(box, &box_alloc);
  set_rgb(cr, C_PAGE);
  for (GList *item = rows != NULL ? rows->next : NULL; item != NULL; item = item->next) {
    GtkAllocation a;
    gtk_widget_get_allocation(item->data, &a);
    double top = a.y - box_alloc.y - gtk_widget_get_margin_top(item->data) - 2;
    cairo_rectangle(cr, 0, top, w, 2);
    cairo_fill(cr);
  }
  return FALSE;
}

static GtkWidget *path_line(const char *text, int width) {
  GtkWidget *label = gtk_label_new(text);
  gtk_style_context_add_class(gtk_widget_get_style_context(label), "t-row-value");
  gtk_widget_set_direction(label, GTK_TEXT_DIR_LTR);
  gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_START);
  gtk_label_set_max_width_chars(GTK_LABEL(label), 1);
  gboolean rtl = gtk_widget_get_default_direction() == GTK_TEXT_DIR_RTL;
  gtk_label_set_xalign(GTK_LABEL(label), rtl ? 1 : 0);
  gtk_widget_set_size_request(label, width, -1);
  return label;
}

/* A long path shows its folder on a line of its own, never cut: a cut Hebrew
 * folder name inside an LTR path reads scrambled. */
static GtkWidget *path_value(const char *path, int width) {
  g_autofree char *parent = g_path_get_dirname(path);
  g_autofree char *name = g_path_get_basename(path);
  if (g_utf8_strlen(path, -1) <= 28 || strcmp(parent, "/") == 0 ||
      strcmp(parent, ".") == 0)
    return path_line(path, width);
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  g_autofree char *head = g_strconcat(parent, "/", NULL);
  gtk_box_pack_start(GTK_BOX(box), path_line(head, width), FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(box), otz_wrap_label(name, "t-row-value", width, 0), FALSE,
                     FALSE, 0);
  return box;
}

GtkWidget *otz_summary_card(const OtzSummaryRow *rows, int count) {
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
  gtk_widget_set_size_request(box, OTZ_CONTENT_WIDTH, -1);
  gtk_widget_set_halign(box, GTK_ALIGN_CENTER);
  int value_width = OTZ_CONTENT_WIDTH - 32 - 40 - 14;
  for (int i = 0; i < count; i++) {
    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 14);
    gtk_widget_set_margin_start(row, 16);
    gtk_widget_set_margin_end(row, 16);
    gtk_widget_set_margin_top(row, i == 0 ? 18 : 14);
    gtk_widget_set_margin_bottom(row, i == count - 1 ? 18 : 14);
    GtkWidget *tile = otz_icon_tile(rows[i].icon);
    gtk_widget_set_valign(tile, GTK_ALIGN_CENTER);
    gtk_box_pack_start(GTK_BOX(row), tile, FALSE, FALSE, 0);
    GtkWidget *texts = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_set_valign(texts, GTK_ALIGN_CENTER);
    gtk_box_pack_start(GTK_BOX(texts),
                       otz_wrap_label(rows[i].label, "t-row-label", value_width, 0),
                       FALSE, FALSE, 0);
    GtkWidget *value;
    if (rows[i].is_path) {
      value = path_value(rows[i].value, value_width);
    } else {
      value = otz_wrap_label(rows[i].value, "t-row-value", value_width, 0);
    }
    gtk_box_pack_start(GTK_BOX(texts), value, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(row), texts, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(box), row, FALSE, FALSE, 0);
    otz_accessible(row, rows[i].label, rows[i].value);
  }
  g_signal_connect(box, "draw", G_CALLBACK(draw_summary), NULL);
  return box;
}

static gboolean draw_code(GtkWidget *widget, cairo_t *cr, gpointer data) {
  rounded(cr, 0, 0, gtk_widget_get_allocated_width(widget),
          gtk_widget_get_allocated_height(widget), 4);
  set_rgb(cr, C_CARD);
  cairo_fill(cr);
  return FALSE;
}

GtkWidget *otz_code_box(const char *text) {
  GtkWidget *label = gtk_label_new(text);
  gtk_style_context_add_class(gtk_widget_get_style_context(label), "t-mono");
  gtk_widget_set_direction(label, GTK_TEXT_DIR_LTR);
  gtk_label_set_selectable(GTK_LABEL(label), TRUE);
  gtk_label_set_line_wrap(GTK_LABEL(label), TRUE);
  gtk_label_set_line_wrap_mode(GTK_LABEL(label), PANGO_WRAP_CHAR);
  gtk_label_set_max_width_chars(GTK_LABEL(label), 1);
  gtk_label_set_xalign(GTK_LABEL(label), 0);
  gtk_widget_set_size_request(label, OTZ_CONTENT_WIDTH - 16, -1);
  gtk_widget_set_margin_start(label, 8);
  gtk_widget_set_margin_end(label, 8);
  gtk_widget_set_margin_top(label, 8);
  gtk_widget_set_margin_bottom(label, 8);
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_size_request(box, OTZ_CONTENT_WIDTH, -1);
  gtk_widget_set_halign(box, GTK_ALIGN_CENTER);
  gtk_box_pack_start(GTK_BOX(box), label, FALSE, FALSE, 0);
  g_signal_connect(box, "draw", G_CALLBACK(draw_code), NULL);
  return box;
}

/* ------------------------------------------------------------- dialog */

static gboolean draw_dialog_card(GtkWidget *box, cairo_t *cr, gpointer data) {
  double s = DIALOG_SHADOW;
  double w = gtk_widget_get_allocated_width(box) - 2 * s;
  double h = gtk_widget_get_allocated_height(box) - 2 * s;
  for (int i = 1; i <= 14; i++) {
    rounded(cr, s - i, s - i + 6, w + 2 * i, h + 2 * i, DIALOG_RADIUS + i);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.012);
    cairo_fill(cr);
  }
  rounded(cr, s, s, w, h, DIALOG_RADIUS);
  set_rgb(cr, C_DIALOG);
  cairo_fill(cr);
  return FALSE;
}

GtkWidget *otz_dialog_card(void) {
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_size_request(box, 336 + 2 * DIALOG_SHADOW, -1);
  gtk_widget_set_halign(box, GTK_ALIGN_CENTER);
  gtk_widget_set_valign(box, GTK_ALIGN_CENTER);
  g_signal_connect(box, "draw", G_CALLBACK(draw_dialog_card), NULL);
  /* The content sits 24px inside the card, which sits DIALOG_SHADOW inside. */
  g_object_set_data(G_OBJECT(box), "otz-inset", GINT_TO_POINTER(24 + DIALOG_SHADOW));
  return box;
}

static gboolean draw_shade(GtkWidget *area, cairo_t *cr, gpointer data) {
  cairo_set_source_rgba(cr, 0, 0, 0, 0.133);
  cairo_paint(cr);
  return TRUE;
}

GtkWidget *otz_shade(void) {
  GtkWidget *area = gtk_drawing_area_new();
  g_signal_connect(area, "draw", G_CALLBACK(draw_shade), NULL);
  return area;
}

void otz_accessible(GtkWidget *widget, const char *name, const char *description) {
  GObject *accessible = G_OBJECT(gtk_widget_get_accessible(widget));
  if (name != NULL) g_object_set(accessible, "accessible-name", name, NULL);
  if (description != NULL && *description != '\0')
    g_object_set(accessible, "accessible-description", description, NULL);
}
