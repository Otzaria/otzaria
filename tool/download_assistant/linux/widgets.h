/* The look of the assistant: the light Otzaria theme, the pinned art, and the
 * drawn controls (cards, buttons, progress, dots, badges). Text is GtkLabel. */
#pragma once

#include <gtk/gtk.h>

#define OTZ_WINDOW_WIDTH 400
#define OTZ_CONTENT_HEIGHT 628
#define OTZ_CONTENT_WIDTH 352
/* Room around a focusable control for its focus ring (Windows: W-4, H-4). */
#define OTZ_RING 4

/* Forces the light look whatever the desktop theme is. Call before any widget. */
void otz_theme_install(void);

/* Loads a PNG from the embedded art (e.g. "ico_folder_200"); NULL when absent. */
cairo_surface_t *otz_art_load(const char *name);
/* Paints art at logical size w×h, resampled once per device scale. FALSE when
 * the art is missing. */
gboolean otz_art_paint(cairo_t *cr, const char *name, double x, double y, double w,
                       double h);
/* The 24 opening frames, resampled for scale off the main thread. */
#define OTZ_BOOK_FRAMES 24
void otz_book_prepare_async(int scale, GCallback ready, gpointer data);
void otz_book_prepare_sync(int scale);
gboolean otz_book_ready(void);
cairo_surface_t *otz_book_frame(int index);
GdkPixbuf *otz_app_icon(void);

GtkWidget *otz_label(const char *text, const char *css_class);
/* A wrapping label of a fixed width; xalign 0 is the reading start. */
GtkWidget *otz_wrap_label(const char *text, const char *css_class, int width,
                          float xalign);
void otz_label_set(GtkWidget *label, const char *text);

typedef enum {
  OTZ_BUTTON_PRIMARY,
  OTZ_BUTTON_TONAL,
  OTZ_BUTTON_GHOST,
  OTZ_BUTTON_DANGER,
  OTZ_BUTTON_LINK,
} OtzButtonKind;

/* width/height of the visible body; width -1 fits the text. */
GtkWidget *otz_button(OtzButtonKind kind, const char *text, int width, int height);
/* The folder path as a white field; clicking it is the same as "Browse". */
GtkWidget *otz_field_button(const char *path);

typedef struct {
  const char *title;
  const char *desc;
  const char *side;
  const char *icon; /* art name without ico_/_200, or NULL */
  gboolean check;   /* a check box rather than a radio */
  gboolean locked;  /* checked and cannot change */
  gboolean no_mark;
} OtzCardSpec;

/* A GtkRadioButton (sharing *group) or a GtkCheckButton drawn as a card. */
GtkWidget *otz_card(const OtzCardSpec *spec, GSList **group);

GtkWidget *otz_icon_tile(const char *icon);
/* ok, err, offline, paused */
GtkWidget *otz_badge(const char *kind);
GtkWidget *otz_step_dots(int current, int total);
/* fraction < 0 is indeterminate; the bar then animates by itself. */
GtkWidget *otz_progress_bar(double fraction);
void otz_progress_bar_set(GtkWidget *bar, double fraction);
GtkWidget *otz_divider(void);

typedef struct {
  const char *icon;
  const char *label;
  const char *value;
  gboolean is_path;
} OtzSummaryRow;

GtkWidget *otz_summary_card(const OtzSummaryRow *rows, int count);
/* Selectable LTR text on the card colour: technical details, a command. */
GtkWidget *otz_code_box(const char *text);

/* A box whose background is a rounded card of the dialog colour with a shadow. */
GtkWidget *otz_dialog_card(void);
/* The 13% black layer under an in-window dialog. */
GtkWidget *otz_shade(void);

/* Accessible name and description, without linking ATK itself. */
void otz_accessible(GtkWidget *widget, const char *name, const char *description);
/* Snapshots: a fixed time for animated parts (ms), or -1 for the clock. */
void otz_set_frozen_time(double ms);
double otz_frozen_time(void);
