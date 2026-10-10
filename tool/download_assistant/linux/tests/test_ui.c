#include "../ui.c"

static void assert_visible(Ui *ui, GtkWidget *widget) {
  int x, y;
  g_assert_true(gtk_widget_translate_coordinates(widget, ui->overlay, 0, 0, &x, &y));
  g_assert_cmpint(x, >=, 0);
  g_assert_cmpint(x + gtk_widget_get_allocated_width(widget), <=,
                  gtk_widget_get_allocated_width(ui->overlay));
  g_assert_cmpint(y, >=, 0);
  g_assert_cmpint(y + gtk_widget_get_allocated_height(widget), <=,
                  gtk_widget_get_allocated_height(ui->overlay));
}

static void check_controls(GtkWidget *widget, gpointer data) {
  Ui *ui = data;
  if (!gtk_widget_is_sensitive(widget) || !gtk_widget_get_visible(widget)) return;
  if (GTK_IS_BUTTON(widget)) {
    gtk_window_set_focus(GTK_WINDOW(ui->window), NULL);
    gtk_widget_grab_focus(widget);
    settle();
    settle();
    g_assert_true(gtk_widget_has_focus(widget));
    assert_visible(ui, widget);
  }
  if (GTK_IS_CONTAINER(widget))
    gtk_container_foreach(GTK_CONTAINER(widget), check_controls, ui);
}

static Ui *test_ui(const OtzUiOptions *options) {
  Ui *ui = g_new0(Ui, 1);
  ui_init(ui, options);
  ui->snapshot = TRUE;
  ui->hero_preview_ms = 0;
  ui->base_dir = g_strdup("/home/user/Downloads");
  build_window(ui);
  g_signal_connect(ui->window, "destroy", G_CALLBACK(gtk_widget_destroyed), &ui->window);
  gtk_widget_show_all(ui->window);
  gtk_window_present(GTK_WINDOW(ui->window));
  settle();
  hero_finish(ui);
  settle();
  assert_visible(ui, ui->hero_start);
  return ui;
}

static void test_layout(void) {
  g_autoptr(GError) error = NULL;
  g_autofree char *fixture =
      g_build_filename(OTZ_FIXTURES_DIR, "release-manifest.json", NULL);
  snapshot_manifest = otz_load_manifest_file(fixture, &error);
  g_assert_no_error(error);
  OtzUiOptions options = {.tls_ok = TRUE};
  GdkRectangle workarea;
  for (int language = 0; language < 2; language++) {
    otz_set_english(language == 1);
    gtk_widget_set_default_direction(language == 1 ? GTK_TEXT_DIR_LTR : GTK_TEXT_DIR_RTL);
    for (gsize i = 0; i < G_N_ELEMENTS(scenarios); i++) {
      g_test_message("language=%s scale=%s screen=%s", language == 1 ? "en" : "he",
                       g_getenv("GDK_SCALE"), scenarios[i].name);
      Ui *ui = test_ui(&options);
      scenarios[i].build(ui);
      gtk_window_present(GTK_WINDOW(ui->window));
      settle();
      gdk_monitor_get_workarea(
          gdk_display_get_monitor_at_window(gdk_display_get_default(),
                                            gtk_widget_get_window(ui->window)),
          &workarea);
      g_assert_cmpint(gtk_widget_get_allocated_height(ui->window), <=, workarea.height);
      g_assert_cmpint(gtk_widget_get_allocated_width(ui->window), <=, workarea.width);
      if (workarea.height >= 700)
        g_assert_cmpint(gtk_widget_get_allocated_height(ui->overlay), ==,
                         OTZ_CONTENT_HEIGHT);
      if (ui->focus != NULL && !ui->dialog_open) assert_visible(ui, ui->focus);
      check_controls(ui->dialog_open ? ui->dialog : ui->page, ui);
      if (ui->dialog_open) {
        g_assert_false(gtk_widget_is_sensitive(ui->host));
        for (int tab = 0; tab < 4; tab++) {
          gtk_widget_child_focus(ui->window, GTK_DIR_TAB_FORWARD);
          settle();
          GtkWidget *focus = gtk_window_get_focus(GTK_WINDOW(ui->window));
          g_assert_true(gtk_widget_is_ancestor(focus, ui->dialog));
          assert_visible(ui, focus);
        }
        GdkEventKey escape = {.keyval = GDK_KEY_Escape};
        g_assert_true(on_key(ui->window, &escape, ui));
        g_assert_false(ui->dialog_open);
        g_assert_true(gtk_widget_is_sensitive(ui->host));
      }
      snapshot_done(ui);
    }
    Ui *ui = test_ui(&options);
    s_loaded(ui);
    gtk_window_present(GTK_WINDOW(ui->window));
    settle();
    GdkEventKey enter = {.keyval = GDK_KEY_Return};
    GdkEventKey escape = {.keyval = GDK_KEY_Escape};
    g_assert_true(on_key(ui->window, &enter, ui));
    g_assert_cmpint(ui->page_id, ==, PAGE_PRESETS);
    g_assert_true(on_key(ui->window, &escape, ui));
    g_assert_cmpint(ui->page_id, ==, PAGE_MODE);
    tell(ui, otz_tr(S_NO_TARGET_TITLE), otz_tr(S_NO_TARGET_TEXT));
    settle();
    g_assert_false(on_key(ui->window, &enter, ui));
    g_assert_true(gtk_window_activate_focus(GTK_WINDOW(ui->window)));
    settle();
    settle();
    g_assert_false(ui->dialog_open);
    g_assert_true(gtk_widget_is_sensitive(ui->host));
    g_autofree char *technical = g_strnfill(1024, 'x');
    show_failure(ui, FAIL_RUN, otz_tr_hebrew(S_ERR_COPY), technical);
    toggle_technical(ui);
    settle();
    g_assert_cmpint(gtk_widget_get_allocated_height(ui->window), <=, workarea.height);
    check_controls(ui->page, ui);
    snapshot_done(ui);
  }
  otz_manifest_free(snapshot_manifest);
  snapshot_manifest = NULL;
}

int main(int argc, char **argv) {
  gtk_init(&argc, &argv);
  g_test_init(&argc, &argv, NULL);
  otz_theme_install();
  otz_set_frozen_time(1000);
  g_test_add_func("/ui/workarea-and-actions", test_layout);
  return g_test_run();
}
