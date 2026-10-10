#include "paths.h"

#include <gio/gio.h>
#include <glib/gstdio.h>
#include <string.h>
#include <sys/utsname.h>

char *otz_cache_dir(void) {
  return g_build_filename(g_get_user_cache_dir(), "otzaria", "download-assistant",
                          NULL);
}

char *otz_executable_dir(void) {
  g_autofree char *exe = g_file_read_link("/proc/self/exe", NULL);
  if (exe == NULL) return g_get_current_dir();
  return g_path_get_dirname(exe);
}

gboolean otz_dir_is_writable(const char *dir) {
  if (g_mkdir_with_parents(dir, 0755) != 0) return FALSE;
  g_autofree char *probe = g_build_filename(dir, "otzaria_write_test.tmp", NULL);
  gboolean ok = g_file_set_contents(probe, "ok", 2, NULL);
  g_unlink(probe);
  return ok;
}

char *otz_fallback_output_dir(gboolean english) {
  const char *documents = g_get_user_special_dir(G_USER_DIRECTORY_DOCUMENTS);
  if (documents == NULL) documents = g_get_home_dir();
  return g_build_filename(documents, english ? "Otzaria setup" : "אוצריא-להתקנה",
                          NULL);
}

char *otz_default_output_dir(gboolean english, gboolean *fell_back) {
  char *dir = otz_executable_dir();
  if (otz_dir_is_writable(dir)) {
    *fell_back = FALSE;
    return dir;
  }
  g_free(dir);
  *fell_back = TRUE;
  return otz_fallback_output_dir(english);
}

gint64 otz_free_space(const char *path) {
  g_autoptr(GFile) file = g_file_new_for_path(path);
  while (file != NULL && !g_file_query_exists(file, NULL)) {
    GFile *parent = g_file_get_parent(file);
    g_object_unref(file);
    file = parent;
  }
  if (file == NULL) return -1;
  g_autoptr(GFileInfo) info = g_file_query_filesystem_info(
      file, G_FILE_ATTRIBUTE_FILESYSTEM_FREE, NULL, NULL);
  if (info == NULL ||
      !g_file_info_has_attribute(info, G_FILE_ATTRIBUTE_FILESYSTEM_FREE))
    return -1;
  return (gint64)g_file_info_get_attribute_uint64(
      info, G_FILE_ATTRIBUTE_FILESYSTEM_FREE);
}

const char *otz_machine_architecture(void) {
  struct utsname name;
  if (uname(&name) == 0 &&
      (strcmp(name.machine, "aarch64") == 0 || strcmp(name.machine, "arm64") == 0))
    return "arm64";
  return "x64";
}

char *otz_read_os_release(void) {
  char *content = NULL;
  if (g_file_get_contents("/etc/os-release", &content, NULL, NULL)) return content;
  if (g_file_get_contents("/usr/lib/os-release", &content, NULL, NULL))
    return content;
  return NULL;
}

void otz_reveal(const char *path, gboolean is_directory) {
  g_autofree char *uri = g_filename_to_uri(path, NULL, NULL);
  if (uri == NULL) return;
  g_autoptr(GDBusConnection) bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL);
  if (bus != NULL) {
    const char *uris[] = {uri, NULL};
    g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
        bus, "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
        "org.freedesktop.FileManager1", "ShowItems",
        g_variant_new("(^ass)", uris, ""), NULL, G_DBUS_CALL_FLAGS_NONE, 5000,
        NULL, NULL);
    if (reply != NULL) return;
  }
  g_autofree char *folder =
      is_directory ? g_strdup(path) : g_path_get_dirname(path);
  g_autofree char *folder_uri = g_filename_to_uri(folder, NULL, NULL);
  if (folder_uri != NULL)
    g_app_info_launch_default_for_uri(folder_uri, NULL, NULL);
}
