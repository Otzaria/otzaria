/* "Also download Contemporary Authors": port of the zmanenu part of
 * tool/release/download_assistant_selection.dart. tests/test_main.c compares
 * it against tool/download_assistant/fixtures/expected-zmanenu.json. */
#pragma once

#include <gio/gio.h>

#include "json.h"
#include "selection.h"

#define OTZ_ZMANENU_REPOSITORY_NAME "zmanenu-library"
#define OTZ_ZMANENU_ARCHIVE "zmanenu-offline.tar.zst"
#define OTZ_ZMANENU_PARTS_MANIFEST OTZ_ZMANENU_ARCHIVE ".manifest.json"
/* Relative to Otzaria's data folder (defaultDropDirectory in the app). */
#define OTZ_ZMANENU_DROP_FOLDER "מסדים אישיים/להתקנה"

typedef struct {
  char *name;
  gint64 size;  /* 0: unknown */
  char *sha256; /* "": not verified by the assistant, nor taken from its cache */
  char *url;
} OtzZmanenuFile;

typedef struct {
  char *tag;              /* "" when the API did not answer */
  GPtrArray *downloads;   /* OtzZmanenuFile*: the whole archive, or its parts */
  GBytes *parts_manifest; /* written last; NULL for the whole archive */
} OtzZmanenuOffer;

void otz_zmanenu_offer_free(OtzZmanenuOffer *offer);
G_DEFINE_AUTOPTR_CLEANUP_FUNC(OtzZmanenuOffer, otz_zmanenu_offer_free)

/* Windows, macOS and Linux: on Android the folder comes through SAF, which
 * gives the app no path, so the package would never be installed. */
gboolean otz_zmanenu_is_offered(const OtzTarget *target);

/* An empty tag is the latest release's direct URL. */
char *otz_zmanenu_asset_url(const char *tag, const char *name);
/* Where to read the parts manifest, or NULL when not needed or not there.
 * release NULL means the API did not answer. */
char *otz_zmanenu_parts_manifest_url(const OtzJson *release);
/* The whole archive with a sha256 digest from the API; else the parts of the
 * parts manifest; with no parts manifest, the whole archive without a sha256. */
OtzZmanenuOffer *otz_zmanenu_offer(const OtzJson *release, GBytes *parts_manifest);

gint64 otz_zmanenu_download_size(const OtzZmanenuOffer *offer);
/* File names in the order they are written: the parts manifest last. */
GPtrArray *otz_zmanenu_output_files(const OtzZmanenuOffer *offer);

/* $HOME/.local/share/otzaria/מסדים אישיים/להתקנה — getDataRootPath in the app. */
char *otz_zmanenu_drop_dir(void);

/* Never fails: no repository, no release, or no package is NULL. */
OtzZmanenuOffer *otz_zmanenu_load(GCancellable *cancellable);
