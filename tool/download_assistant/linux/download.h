/* Preparing the selection: cache check, download, assemble/place. */
#pragma once

#include <gio/gio.h>

#include "manifest.h"
#include "selection.h"

#define OTZ_MAX_CONNECTIONS 3

typedef enum {
  OTZ_PHASE_CHECK,    /* hashing a cached file that has no marker */
  OTZ_PHASE_DOWNLOAD,
  OTZ_PHASE_ASSEMBLE,
  OTZ_PHASE_VERIFY_ASSEMBLY,
  OTZ_PHASE_PLACE,    /* link or copy into the chosen folder */
  OTZ_PHASE_DONE,
} OtzPhase;

/* What the UI says when the job fails; the GError carries the technical text. */
typedef enum {
  OTZ_FAILURE_NONE,
  OTZ_FAILURE_UNAVAILABLE, /* network, HTTP, blocked redirect */
  OTZ_FAILURE_CORRUPT,     /* size or sha256 mismatch */
  OTZ_FAILURE_CACHE,       /* cannot write the cache */
  OTZ_FAILURE_ASSEMBLE,    /* cannot write the joined file */
  OTZ_FAILURE_PLACE,       /* cannot write the chosen folder */
  OTZ_FAILURE_CANCELLED,
} OtzFailure;

typedef struct {
  OtzPhase phase;
  gint64 phase_done, phase_total;       /* bytes of the current non-download step */
  gint64 download_done, download_total; /* bytes */
  guint files_done, files_total;        /* downloads */
  guint part_index, part_count;         /* while assembling */
  char *detail;                         /* file name; owned by the snapshot */
} OtzProgress;

typedef struct OtzJob OtzJob;

/* selected_ids must already include the dependsOn closure. subfolder_name
 * replaces the contract's name for a multi-file result (NULL keeps it). */
OtzJob *otz_job_new(const OtzManifest *manifest, GPtrArray *selected_ids,
                    const OtzTarget *target, const char *cache_dir,
                    const char *base_dir, const char *subfolder_name,
                    GError **error);
void otz_job_free(OtzJob *job);
G_DEFINE_AUTOPTR_CLEANUP_FUNC(OtzJob, otz_job_free)

gboolean otz_job_run(OtzJob *job, GCancellable *cancellable, GError **error);
void otz_job_run_async(OtzJob *job, GCancellable *cancellable,
                       GAsyncReadyCallback callback, gpointer user_data);
gboolean otz_job_run_finish(OtzJob *job, GAsyncResult *result, GError **error);

void otz_job_get_progress(OtzJob *job, OtzProgress *out);
void otz_progress_clear(OtzProgress *progress);

/* Bytes the run still writes to the cache and to the output folder (a hard
 * link on the same filesystem costs nothing). */
void otz_job_space_needs(OtzJob *job, gint64 *cache_bytes, gint64 *output_bytes,
                         gboolean *same_filesystem);

/* Free-space verdict; -1 free means unknown and never blocks. */
gboolean otz_space_is_enough(gint64 cache_bytes, gint64 output_bytes,
                             gboolean same_filesystem, gint64 cache_free,
                             gint64 output_free);

OtzFailure otz_job_failure(OtzJob *job);
/* The folder that holds the result (base dir, or its subfolder). */
const char *otz_job_output_dir(OtzJob *job);
/* Names of the files produced in the output dir, manifest order. */
GPtrArray *otz_job_output_files(OtzJob *job);
/* outputNote texts of the selection, for the finish page. */
GPtrArray *otz_job_output_notes(OtzJob *job);
/* Split assets left as parts for a non-Windows target (4 GiB and up). */
GPtrArray *otz_job_unjoined_assets(OtzJob *job);
/* Bytes this run fed into SHA-256 and bytes it downloaded — equal when every
 * byte was hashed exactly once. */
gint64 otz_job_hashed_bytes(OtzJob *job);
gint64 otz_job_downloaded_bytes(OtzJob *job);

/* What a reply means for an existing partial file of `from` bytes. */
typedef enum {
  OTZ_RANGE_CONTINUE, /* 206 whose Content-Range is exactly from-(size-1)/size */
  OTZ_RANGE_REWRITE,  /* 200: the server ignored Range; write this body from 0 */
  OTZ_RANGE_DISCARD,  /* 206 that does not match, or 416: drop and ask again */
  OTZ_RANGE_FAIL,     /* any other status */
} OtzRangeReply;

OtzRangeReply otz_classify_range_reply(guint status, const char *content_range,
                                       gint64 content_length, gint64 from,
                                       gint64 size);

/* The cache marker "<hex>  <name>\n" (sha256sum format) next to a file. */
gboolean otz_marker_write(const char *file_path, const char *sha256,
                          GError **error);
/* TRUE when the marker matches sha256, the file has size bytes, and the file
 * is not newer than the marker. */
gboolean otz_marker_matches(const char *file_path, const char *sha256,
                            gint64 size);
