/* Where things live on this machine, and what this machine is. */
#pragma once

#include <glib.h>

/* ${XDG_CACHE_HOME:-~/.cache}/otzaria/download-assistant */
char *otz_cache_dir(void);
/* Directory of /proc/self/exe. */
char *otz_executable_dir(void);
/* Real write test (otzaria_write_test.tmp), creating the directory if needed. */
gboolean otz_dir_is_writable(const char *dir);
/* <Documents or $HOME>/אוצריא-להתקנה ("Otzaria setup" in English) */
char *otz_fallback_output_dir(gboolean english);
/* Next to the executable when writable, else the fallback. */
char *otz_default_output_dir(gboolean english, gboolean *fell_back);
/* Free bytes on the filesystem holding path (or its nearest existing parent),
 * -1 when unknown. */
gint64 otz_free_space(const char *path);

/* "x64" or "arm64" from uname(2); x64 for anything unknown. */
const char *otz_machine_architecture(void);
/* /etc/os-release (or /usr/lib/os-release), NULL when neither is readable. */
char *otz_read_os_release(void);

/* Opens the file manager with path selected; falls back to opening the folder.
 * Best effort: the result already exists, so failures stay silent. */
void otz_reveal(const char *path, gboolean is_directory);
