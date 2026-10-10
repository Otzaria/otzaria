#include "download.h"

#include <errno.h>
#include <fcntl.h>
#include <glib/gstdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "assemble.h"
#include "http.h"
#include "otz_common.h"

#define IO_BUFFER (256 * 1024)
#define MAX_RETRIES 3

typedef struct {
  char *name;
  char *url;
  char *sha256;
  gint64 size;
  char *cache_path;
  char *partial_path; /* <name>.<sha12>.download: bound to this exact file */
  gboolean cached; /* verified in the cache */
  gboolean skip;   /* already inside a partial assembly in the output */
  gint64 progress; /* bytes of this file counted in download_done */
} Item;

typedef struct {
  gboolean assemble;
  char *dir; /* output_dir, or its outputFolder for this component */
  char *name;
  char *sha256;
  gint64 size;
  GPtrArray *items; /* Item*, borrowed; parts in order when assembling */
  guint first_part;
  char *partial_path; /* <name>.<sha12>.partial in the output folder */
} Output;

struct OtzJob {
  char *platform;
  char *cache_dir;
  char *output_dir;
  GPtrArray *items;
  GHashTable *items_by_name;
  GPtrArray *outputs;
  GPtrArray *output_files;
  GPtrArray *output_notes;
  GPtrArray *unjoined;

  GMutex lock;
  OtzProgress progress;
  OtzFailure failure;
  gint64 hashed;
  gint64 downloaded;

  GPtrArray *queue; /* Item* still to download */
  guint next;
  GError *worker_error;
  OtzFailure worker_failure;
  GCancellable *inner;
};

static void free_item(gpointer data) {
  Item *item = data;
  g_free(item->name);
  g_free(item->url);
  g_free(item->sha256);
  g_free(item->cache_path);
  g_free(item->partial_path);
  g_free(item);
}

static void free_output(gpointer data) {
  Output *output = data;
  g_free(output->dir);
  g_free(output->name);
  g_free(output->sha256);
  g_free(output->partial_path);
  g_ptr_array_unref(output->items);
  g_free(output);
}

void otz_progress_clear(OtzProgress *progress) {
  g_clear_pointer(&progress->detail, g_free);
}

void otz_job_free(OtzJob *job) {
  if (job == NULL) return;
  g_free(job->platform);
  g_free(job->cache_dir);
  g_free(job->output_dir);
  g_ptr_array_unref(job->outputs);
  g_ptr_array_unref(job->items);
  g_hash_table_unref(job->items_by_name);
  g_ptr_array_unref(job->output_files);
  g_ptr_array_unref(job->output_notes);
  g_ptr_array_unref(job->unjoined);
  g_clear_pointer(&job->queue, g_ptr_array_unref);
  g_clear_error(&job->worker_error);
  g_clear_object(&job->inner);
  otz_progress_clear(&job->progress);
  g_mutex_clear(&job->lock);
  g_free(job);
}

/* ---------------------------------------------------------------- markers */

gboolean otz_marker_write(const char *file_path, const char *sha256,
                          GError **error) {
  g_autofree char *name = g_path_get_basename(file_path);
  g_autofree char *content = g_strdup_printf("%s  %s\n", sha256, name);
  g_autofree char *marker = g_strconcat(file_path, ".sha256", NULL);
  return g_file_set_contents(marker, content, -1, error);
}

static gboolean not_newer(const struct stat *file, const struct stat *marker) {
  if (file->st_mtim.tv_sec != marker->st_mtim.tv_sec)
    return file->st_mtim.tv_sec < marker->st_mtim.tv_sec;
  return file->st_mtim.tv_nsec <= marker->st_mtim.tv_nsec;
}

gboolean otz_marker_matches(const char *file_path, const char *sha256,
                            gint64 size) {
  g_autofree char *marker = g_strconcat(file_path, ".sha256", NULL);
  struct stat file_stat, marker_stat;
  if (stat(file_path, &file_stat) != 0 || stat(marker, &marker_stat) != 0)
    return FALSE;
  if (file_stat.st_size != size || !not_newer(&file_stat, &marker_stat))
    return FALSE;
  g_autofree char *content = NULL;
  gsize length;
  if (!g_file_get_contents(marker, &content, &length, NULL) || length < 66)
    return FALSE;
  return g_ascii_strncasecmp(content, sha256, 64) == 0 && content[64] == ' ' &&
         content[65] == ' ';
}

/* ------------------------------------------------------------------- plan */

/* Asset names carry no version (otzaria-linux-full.tar.zst), so a leftover from
 * an older release must never be resumed as if it were this file. */
static char *versioned_path(const char *path, const char *sha256,
                            const char *suffix) {
  return g_strdup_printf("%s.%.12s%s", path, sha256, suffix);
}

/* Removes <dir>/<name>.*<suffix> left by other versions of the same file. */
static void remove_stale_siblings(const char *keep, const char *name,
                                  const char *suffix) {
  g_autofree char *dir = g_path_get_dirname(keep);
  g_autofree char *base = g_path_get_basename(keep);
  g_autofree char *prefix = g_strconcat(name, ".", NULL);
  GDir *listing = g_dir_open(dir, 0, NULL);
  if (listing == NULL) return;
  const char *entry;
  while ((entry = g_dir_read_name(listing)) != NULL) {
    if (!g_str_has_prefix(entry, prefix) || !g_str_has_suffix(entry, suffix) ||
        strcmp(entry, base) == 0 ||
        strlen(entry) != strlen(prefix) + 12 + strlen(suffix))
      continue;
    gboolean hex = TRUE;
    for (gsize i = 0; i < 12; i++)
      hex = hex && g_ascii_isxdigit(entry[strlen(prefix) + i]);
    if (!hex) continue;
    g_autofree char *path = g_build_filename(dir, entry, NULL);
    g_unlink(path);
  }
  g_dir_close(listing);
}

static Item *get_item(OtzJob *job, const OtzAsset *asset, const char *name,
                      gint64 size, const char *sha256, GError **error) {
  Item *item = g_hash_table_lookup(job->items_by_name, name);
  if (item != NULL) {
    if (item->size != size || strcmp(item->sha256, sha256) != 0) {
      g_set_error(error, OTZ_ERROR, OTZ_ERROR_PARSE,
                  "two different files are named %s", name);
      return NULL;
    }
    return item;
  }
  item = g_new0(Item, 1);
  item->name = g_strdup(name);
  item->url = otz_asset_url(asset, name);
  item->sha256 = g_strdup(sha256);
  item->size = size;
  item->cache_path = g_build_filename(job->cache_dir, name, NULL);
  item->partial_path = versioned_path(item->cache_path, sha256, ".download");
  g_ptr_array_add(job->items, item);
  g_hash_table_insert(job->items_by_name, item->name, item);
  return item;
}

static Output *add_output(OtzJob *job, const char *dir, gboolean assemble,
                          const char *name, gint64 size) {
  Output *output = g_new0(Output, 1);
  output->dir = g_strdup(dir);
  output->assemble = assemble;
  output->name = g_strdup(name);
  output->size = size;
  output->items = g_ptr_array_new();
  g_ptr_array_add(job->outputs, output);
  return output;
}

static gboolean plan_asset(OtzJob *job, const char *dir, const OtzAsset *asset,
                           GError **error) {
  gboolean split = strcmp(asset->kind, "split") == 0;
  if (!split) {
    Item *item = get_item(job, asset, asset->name, asset->size, asset->sha256, error);
    if (item == NULL) return FALSE;
    g_ptr_array_add(add_output(job, dir, FALSE, asset->name, asset->size)->items,
                    item);
    return TRUE;
  }

  if (!otz_should_assemble_split_asset(asset, job->platform)) {
    for (guint p = 0; p < asset->parts->len; p++) {
      const OtzPart *part = g_ptr_array_index(asset->parts, p);
      Item *item = get_item(job, asset, part->name, part->size, part->sha256, error);
      if (item == NULL) return FALSE;
      g_ptr_array_add(add_output(job, dir, FALSE, part->name, part->size)->items,
                      item);
    }
    if (strcmp(job->platform, "windows") != 0)
      g_ptr_array_add(job->unjoined, g_strdup(asset->name));
    return TRUE;
  }

  Output *output = add_output(job, dir, TRUE, asset->name, asset->size);
  output->sha256 = g_strdup(asset->sha256);
  g_autofree gint64 *sizes = g_new(gint64, asset->parts->len);
  for (guint p = 0; p < asset->parts->len; p++) {
    const OtzPart *part = g_ptr_array_index(asset->parts, p);
    Item *item = get_item(job, asset, part->name, part->size, part->sha256, error);
    if (item == NULL) return FALSE;
    g_ptr_array_add(output->items, item);
    sizes[p] = part->size;
  }
  /* A previous run may have joined some parts already and deleted them. */
  g_autofree char *dest = g_build_filename(dir, asset->name, NULL);
  output->partial_path = versioned_path(dest, asset->sha256, ".partial");
  struct stat st;
  if (stat(output->partial_path, &st) == 0) {
    gint64 offset;
    output->first_part =
        otz_assembled_parts(sizes, asset->parts->len, st.st_size, &offset);
    for (guint p = 0; p < output->first_part; p++)
      ((Item *)g_ptr_array_index(output->items, p))->skip = TRUE;
  }
  return TRUE;
}

OtzJob *otz_job_new(const OtzManifest *manifest, GPtrArray *selected_ids,
                    const OtzTarget *target, const char *cache_dir,
                    const char *base_dir, const char *subfolder_name,
                    GError **error) {
  OtzJob *job = g_new0(OtzJob, 1);
  g_mutex_init(&job->lock);
  job->platform = g_strdup(target->platform);
  job->cache_dir = g_strdup(cache_dir);
  job->items = g_ptr_array_new_with_free_func(free_item);
  job->items_by_name = g_hash_table_new(g_str_hash, g_str_equal);
  job->outputs = g_ptr_array_new_with_free_func(free_output);
  job->unjoined = g_ptr_array_new_with_free_func(g_free);
  job->output_files = otz_planned_output_files(manifest, selected_ids, target);
  job->output_notes = otz_planned_output_notes(manifest, selected_ids);
  g_autofree char *subfolder =
      otz_planned_output_subfolder(job->output_files, target->platform);
  if (*subfolder != '\0' && subfolder_name != NULL) {
    g_free(subfolder);
    subfolder = g_strdup(subfolder_name);
  }
  job->output_dir = *subfolder != '\0'
                        ? g_build_filename(base_dir, subfolder, NULL)
                        : g_strdup(base_dir);

  for (guint i = 0; i < manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(manifest->components, i);
    if (!otz_string_array_contains(selected_ids, component->id)) continue;
    g_autofree char *dir =
        g_build_filename(job->output_dir, component->output_folder, NULL);
    for (guint a = 0; a < component->assets->len; a++) {
      if (!plan_asset(job, dir, g_ptr_array_index(component->assets, a), error)) {
        otz_job_free(job);
        return NULL;
      }
    }
  }
  return job;
}

/* --------------------------------------------------------------- progress */

static void set_phase(OtzJob *job, OtzPhase phase, const char *detail,
                      gint64 total) {
  g_mutex_lock(&job->lock);
  job->progress.phase = phase;
  job->progress.phase_done = 0;
  job->progress.phase_total = total;
  g_free(job->progress.detail);
  job->progress.detail = g_strdup(detail);
  g_mutex_unlock(&job->lock);
}

static void add_phase_bytes(gint64 delta, gpointer user_data) {
  OtzJob *job = user_data;
  g_mutex_lock(&job->lock);
  job->progress.phase_done += delta;
  g_mutex_unlock(&job->lock);
}

static void set_part(guint index, gpointer user_data) {
  OtzJob *job = user_data;
  g_mutex_lock(&job->lock);
  job->progress.part_index = index;
  g_mutex_unlock(&job->lock);
}

static void begin_assembly_verify(gpointer user_data) {
  OtzJob *job = user_data;
  g_mutex_lock(&job->lock);
  job->progress.phase = OTZ_PHASE_VERIFY_ASSEMBLY;
  job->progress.phase_done = 0;
  g_mutex_unlock(&job->lock);
}

/* offset = bytes of the file now on disk; the deltas feed the counters that
 * prove single-pass hashing. */
static void account(OtzJob *job, Item *item, gint64 offset, gint64 hashed,
                    gint64 downloaded) {
  g_mutex_lock(&job->lock);
  job->progress.download_done += offset - item->progress;
  item->progress = offset;
  job->hashed += hashed;
  job->downloaded += downloaded;
  g_mutex_unlock(&job->lock);
}

void otz_job_get_progress(OtzJob *job, OtzProgress *out) {
  g_mutex_lock(&job->lock);
  *out = job->progress;
  out->detail = g_strdup(job->progress.detail);
  g_mutex_unlock(&job->lock);
}

/* ---------------------------------------------------------------- hashing */

static gboolean hash_fd(int fd, gint64 length, GChecksum *checksum,
                        OtzBytesFunc progress, gpointer user_data,
                        GCancellable *cancellable, GError **error) {
  g_autofree guint8 *buffer = g_malloc(IO_BUFFER);
  gint64 offset = 0;
  while (offset < length) {
    if (g_cancellable_set_error_if_cancelled(cancellable, error)) return FALSE;
    ssize_t n = pread(fd, buffer, (size_t)MIN(length - offset, IO_BUFFER), offset);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) {
      g_set_error(error, OTZ_ERROR, OTZ_ERROR_IO, "cannot read the cache: %s",
                  n < 0 ? g_strerror(errno) : "short file");
      return FALSE;
    }
    g_checksum_update(checksum, buffer, n);
    offset += n;
    if (progress != NULL) progress(n, user_data);
  }
  return TRUE;
}

static void count_hashed(gint64 delta, gpointer user_data) {
  OtzJob *job = user_data;
  g_mutex_lock(&job->lock);
  job->hashed += delta;
  job->progress.phase_done += delta;
  g_mutex_unlock(&job->lock);
}

/* A cached file without a marker (older cache) is hashed once, then marked. */
static gboolean check_cache(OtzJob *job, GCancellable *cancellable,
                            GError **error) {
  g_autoptr(GPtrArray) unmarked = g_ptr_array_new();
  gint64 total = 0;
  for (guint i = 0; i < job->items->len; i++) {
    Item *item = g_ptr_array_index(job->items, i);
    if (item->skip) continue;
    if (otz_marker_matches(item->cache_path, item->sha256, item->size)) {
      item->cached = TRUE;
      continue;
    }
    struct stat st;
    if (stat(item->cache_path, &st) == 0 && st.st_size == item->size) {
      g_ptr_array_add(unmarked, item);
      total += item->size;
    } else {
      g_unlink(item->cache_path);
    }
  }
  if (unmarked->len == 0) return TRUE;

  set_phase(job, OTZ_PHASE_CHECK, NULL, total);
  for (guint i = 0; i < unmarked->len; i++) {
    Item *item = g_ptr_array_index(unmarked, i);
    g_mutex_lock(&job->lock);
    g_free(job->progress.detail);
    job->progress.detail = g_strdup(item->name);
    g_mutex_unlock(&job->lock);
    int fd = open(item->cache_path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) continue;
    g_autoptr(GChecksum) checksum = g_checksum_new(G_CHECKSUM_SHA256);
    gboolean ok = hash_fd(fd, item->size, checksum, count_hashed, job,
                          cancellable, error);
    close(fd);
    if (!ok) return FALSE;
    if (strcmp(g_checksum_get_string(checksum), item->sha256) == 0 &&
        otz_marker_write(item->cache_path, item->sha256, NULL)) {
      item->cached = TRUE;
    } else {
      g_unlink(item->cache_path);
    }
  }
  return TRUE;
}

/* --------------------------------------------------------------- download */

static gboolean write_all(int fd, const guint8 *data, gsize length, GError **error) {
  while (length > 0) {
    ssize_t n = write(fd, data, length);
    if (n < 0 && errno == EINTR) continue;
    if (n < 0) {
      g_set_error(error, OTZ_ERROR, OTZ_ERROR_IO, "cannot write the cache: %s",
                  g_strerror(errno));
      return FALSE;
    }
    data += n;
    length -= (gsize)n;
  }
  return TRUE;
}

static gboolean truncate_partial(int fd, GError **error) {
  if (ftruncate(fd, 0) == 0 && lseek(fd, 0, SEEK_SET) == 0) return TRUE;
  g_set_error(error, OTZ_ERROR, OTZ_ERROR_IO, "cannot truncate the cache: %s",
              g_strerror(errno));
  return FALSE;
}

OtzRangeReply otz_classify_range_reply(guint status, const char *content_range,
                                       gint64 content_length, gint64 from,
                                       gint64 size) {
  if (status == 200) return OTZ_RANGE_REWRITE;
  if (status == 416) return from > 0 ? OTZ_RANGE_DISCARD : OTZ_RANGE_FAIL;
  if (status != 206) return OTZ_RANGE_FAIL;
  if (from <= 0) return OTZ_RANGE_FAIL;
  gint64 start, end, total;
  if (otz_http_parse_content_range(content_range, &start, &end, &total) &&
      start == from && end == size - 1 && total == size &&
      (content_length < 0 || content_length == size - from))
    return OTZ_RANGE_CONTINUE;
  return OTZ_RANGE_DISCARD;
}

typedef struct {
  OtzJob *job;
  Item *item;
} PrefixContext;

static void count_prefix(gint64 delta, gpointer user_data) {
  PrefixContext *context = user_data;
  account(context->job, context->item, context->item->progress + delta, delta, 0);
}

/* Opens the response, deciding what happens to an existing partial file:
 * a matching 206 continues it, a 200 rewrites it from byte 0 with the same
 * body (filtered networks ignore Range), anything else discards it. */
static OtzHttpResponse *open_body(OtzJob *job, Item *item, int fd,
                                  gint64 *offset, GChecksum *checksum,
                                  GError **error) {
  for (int pass = 0; pass < 2; pass++) {
    gint64 from = *offset;
    OtzHttpResponse *response =
        otz_http_get(item->url, from > 0 ? from : -1, NULL, job->inner, error);
    if (response == NULL) return NULL;
    const OtzHttpHead *head = otz_http_response_head(response);
    g_debug("%s: HTTP %u (range from %" G_GINT64_FORMAT ", content-range %s)",
            item->name, head->status, from,
            head->content_range != NULL ? head->content_range : "-");

    OtzRangeReply reply = otz_classify_range_reply(
        head->status, head->content_range, head->content_length, from, item->size);
    if (reply == OTZ_RANGE_CONTINUE) {
      PrefixContext context = {job, item};
      account(job, item, 0, 0, 0);
      if (!hash_fd(fd, from, checksum, count_prefix, &context, job->inner, error) ||
          lseek(fd, from, SEEK_SET) != from) {
        otz_http_response_free(response);
        return NULL;
      }
      return response;
    }
    if (reply == OTZ_RANGE_REWRITE) {
      if (from > 0)
        g_debug("%s: server ignored Range; writing the same body from 0",
                item->name);
      if (head->content_length >= 0 && head->content_length != item->size) {
        g_set_error(error, OTZ_ERROR, OTZ_ERROR_CORRUPT,
                    "%s: server size %" G_GINT64_FORMAT " != %" G_GINT64_FORMAT,
                    item->name, head->content_length, item->size);
        otz_http_response_free(response);
        return NULL;
      }
      if (!truncate_partial(fd, error)) {
        otz_http_response_free(response);
        return NULL;
      }
      *offset = 0;
      account(job, item, 0, 0, 0);
      return response;
    }

    guint status = head->status;
    otz_http_response_free(response);
    if (!truncate_partial(fd, error)) return NULL;
    *offset = 0;
    account(job, item, 0, 0, 0);
    if (reply == OTZ_RANGE_DISCARD) continue;
    g_set_error(error, OTZ_ERROR,
                status >= 500 ? OTZ_ERROR_HTTP_SERVER : OTZ_ERROR_HTTP,
                "HTTP %u for %s", status, item->name);
    return NULL;
  }
  g_set_error(error, OTZ_ERROR, OTZ_ERROR_HTTP, "unexpected partial reply for %s",
              item->name);
  return NULL;
}

static gboolean promote(Item *item, GError **error) {
  if (g_rename(item->partial_path, item->cache_path) != 0) {
    g_set_error(error, OTZ_ERROR, OTZ_ERROR_IO, "cannot rename %s: %s",
                item->partial_path, g_strerror(errno));
    return FALSE;
  }
  return otz_marker_write(item->cache_path, item->sha256, error);
}

/* *resumed tells the caller whether this attempt continued an existing prefix. */
static gboolean fetch_once(OtzJob *job, Item *item, gboolean *resumed,
                           GError **error) {
  const char *partial = item->partial_path;
  *resumed = FALSE;
  remove_stale_siblings(partial, item->name, ".download");
  int fd = open(partial, O_RDWR | O_CREAT | O_CLOEXEC, 0644);
  if (fd < 0) {
    g_set_error(error, OTZ_ERROR, OTZ_ERROR_IO, "cannot create %s: %s", partial,
                g_strerror(errno));
    return FALSE;
  }
  gboolean ok = FALSE;
  gboolean corrupt = FALSE;
  g_autoptr(GChecksum) checksum = g_checksum_new(G_CHECKSUM_SHA256);
  g_autofree guint8 *buffer = g_malloc(IO_BUFFER);
  OtzHttpResponse *response = NULL;

  struct stat st;
  gint64 offset = fstat(fd, &st) == 0 ? st.st_size : 0;
  if (offset == item->size) {
    /* A complete download whose rename never happened: hash it once instead of
     * fetching it again. */
    PrefixContext context = {job, item};
    if (!hash_fd(fd, offset, checksum, count_prefix, &context, job->inner, error))
      goto out;
    if (strcmp(g_checksum_get_string(checksum), item->sha256) == 0) {
      close(fd);
      fd = -1;
      ok = promote(item, error);
      goto out;
    }
    g_checksum_reset(checksum);
    account(job, item, 0, 0, 0);
  }
  if (offset >= item->size) {
    if (!truncate_partial(fd, error)) goto out;
    offset = 0;
  }
  response = open_body(job, item, fd, &offset, checksum, error);
  if (response == NULL) goto out;
  *resumed = offset > 0;

  for (;;) {
    gssize n = otz_http_response_read(response, buffer, IO_BUFFER, job->inner,
                                      error);
    if (n < 0) goto out;
    if (n == 0) break;
    if (offset + n > item->size) {
      g_set_error(error, OTZ_ERROR, OTZ_ERROR_CORRUPT, "%s is longer than expected",
                  item->name);
      corrupt = TRUE;
      goto out;
    }
    if (!write_all(fd, buffer, (gsize)n, error)) goto out;
    g_checksum_update(checksum, buffer, n);
    offset += n;
    account(job, item, offset, n, n);
  }
  if (offset != item->size) {
    g_set_error(error, OTZ_ERROR, OTZ_ERROR_NETWORK,
                "%s ended at %" G_GINT64_FORMAT " of %" G_GINT64_FORMAT " bytes",
                item->name, offset, item->size);
    goto out;
  }
  if (strcmp(g_checksum_get_string(checksum), item->sha256) != 0) {
    g_set_error(error, OTZ_ERROR, OTZ_ERROR_CORRUPT, "%s: sha256 mismatch",
                item->name);
    corrupt = TRUE;
    goto out;
  }
  if (close(fd) != 0) {
    fd = -1;
    g_set_error(error, OTZ_ERROR, OTZ_ERROR_IO, "cannot write the cache: %s",
                g_strerror(errno));
    goto out;
  }
  fd = -1;
  ok = promote(item, error);

out:
  otz_http_response_free(response);
  if (fd >= 0) close(fd);
  if (corrupt) {
    g_unlink(partial);
    account(job, item, 0, 0, 0);
  } else if (!ok && stat(partial, &st) == 0 && st.st_size == 0) {
    g_unlink(partial);
  }
  return ok;
}

static gboolean sleep_cancellable(GCancellable *cancellable, int seconds) {
  for (int i = 0; i < seconds * 10; i++) {
    if (g_cancellable_is_cancelled(cancellable)) return FALSE;
    g_usleep(100 * 1000);
  }
  return !g_cancellable_is_cancelled(cancellable);
}

static gboolean fetch_item(OtzJob *job, Item *item, GError **error) {
  static const int waits[MAX_RETRIES] = {2, 5, 10};
  gboolean restarted = FALSE;
  for (int attempt = 0;; attempt++) {
    GError *local = NULL;
    gboolean resumed = FALSE;
    if (fetch_once(job, item, &resumed, &local)) return TRUE;
    /* A bad resumed prefix is already deleted; one clean pass from byte 0. */
    if (resumed && !restarted &&
        g_error_matches(local, OTZ_ERROR, OTZ_ERROR_CORRUPT)) {
      g_debug("%s: resumed file was corrupt, downloading from 0", item->name);
      restarted = TRUE;
      g_error_free(local);
      attempt--;
      continue;
    }
    if (attempt >= MAX_RETRIES || !otz_error_is_retryable(local) ||
        g_cancellable_is_cancelled(job->inner)) {
      g_propagate_error(error, local);
      return FALSE;
    }
    g_debug("%s: retry %d in %ds after: %s", item->name, attempt + 1,
            waits[attempt], local->message);
    g_error_free(local);
    if (!sleep_cancellable(job->inner, waits[attempt])) {
      g_cancellable_set_error_if_cancelled(job->inner, error);
      return FALSE;
    }
  }
}

static OtzFailure classify(const GError *error) {
  if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
    return OTZ_FAILURE_CANCELLED;
  if (g_error_matches(error, OTZ_ERROR, OTZ_ERROR_CORRUPT))
    return OTZ_FAILURE_CORRUPT;
  if (g_error_matches(error, OTZ_ERROR, OTZ_ERROR_IO)) return OTZ_FAILURE_CACHE;
  return OTZ_FAILURE_UNAVAILABLE;
}

static gpointer download_worker(gpointer data) {
  OtzJob *job = data;
  for (;;) {
    g_mutex_lock(&job->lock);
    if (job->worker_error != NULL || job->next >= job->queue->len) {
      g_mutex_unlock(&job->lock);
      return NULL;
    }
    Item *item = g_ptr_array_index(job->queue, job->next++);
    g_free(job->progress.detail);
    job->progress.detail = g_strdup(item->name);
    g_mutex_unlock(&job->lock);

    gint64 started = g_get_monotonic_time();
    GError *error = NULL;
    if (!fetch_item(job, item, &error)) {
      g_mutex_lock(&job->lock);
      /* The first failure explains the stop; the others are its cancellation. */
      if (job->worker_error == NULL) {
        job->worker_failure = classify(error);
        job->worker_error = error;
      } else {
        g_error_free(error);
      }
      g_mutex_unlock(&job->lock);
      g_cancellable_cancel(job->inner);
      return NULL;
    }
    double seconds = (g_get_monotonic_time() - started) / 1e6;
    g_debug("%s: done, %" G_GINT64_FORMAT " bytes in %.1fs (%.2f MB/s)",
            item->name, item->size, seconds,
            seconds > 0 ? item->size / seconds / 1e6 : 0.0);
    g_mutex_lock(&job->lock);
    job->progress.files_done++;
    g_mutex_unlock(&job->lock);
  }
}

static gboolean download_missing(OtzJob *job, GError **error) {
  job->queue = g_ptr_array_new();
  gint64 total = 0;
  for (guint i = 0; i < job->items->len; i++) {
    Item *item = g_ptr_array_index(job->items, i);
    if (item->skip || item->cached) continue;
    g_ptr_array_add(job->queue, item);
    total += item->size;
  }
  if (job->queue->len == 0) return TRUE;

  g_mutex_lock(&job->lock);
  job->progress.phase = OTZ_PHASE_DOWNLOAD;
  job->progress.download_total = total;
  job->progress.files_total = job->queue->len;
  g_mutex_unlock(&job->lock);

  guint count = MIN(job->queue->len, OTZ_MAX_CONNECTIONS);
  GThread *threads[OTZ_MAX_CONNECTIONS];
  for (guint i = 0; i < count; i++)
    threads[i] = g_thread_new("otz-download", download_worker, job);
  for (guint i = 0; i < count; i++) g_thread_join(threads[i]);

  if (job->worker_error != NULL) {
    job->failure = job->worker_failure;
    g_propagate_error(error, g_steal_pointer(&job->worker_error));
    return FALSE;
  }
  return TRUE;
}

/* ----------------------------------------------------------------- output */

static gboolean produce_outputs(OtzJob *job, GError **error) {
  if (g_mkdir_with_parents(job->output_dir, 0755) != 0) {
    job->failure = OTZ_FAILURE_PLACE;
    g_set_error(error, OTZ_ERROR, OTZ_ERROR_IO, "cannot create %s: %s",
                job->output_dir, g_strerror(errno));
    return FALSE;
  }
  for (guint i = 0; i < job->outputs->len; i++) {
    Output *output = g_ptr_array_index(job->outputs, i);
    if (g_mkdir_with_parents(output->dir, 0755) != 0) {
      job->failure = OTZ_FAILURE_PLACE;
      g_set_error(error, OTZ_ERROR, OTZ_ERROR_IO, "cannot create %s: %s",
                  output->dir, g_strerror(errno));
      return FALSE;
    }
    g_autofree char *dest = g_build_filename(output->dir, output->name, NULL);
    if (!output->assemble) {
      Item *item = g_ptr_array_index(output->items, 0);
      set_phase(job, OTZ_PHASE_PLACE, output->name, output->size);
      if (!otz_place_file(item->cache_path, dest, item->size, add_phase_bytes, job,
                          job->inner, error)) {
        job->failure = OTZ_FAILURE_PLACE;
        return FALSE;
      }
      continue;
    }

    g_autoptr(GPtrArray) paths = g_ptr_array_new();
    g_autofree gint64 *sizes = g_new(gint64, output->items->len);
    gint64 already = 0;
    for (guint p = 0; p < output->items->len; p++) {
      Item *item = g_ptr_array_index(output->items, p);
      g_ptr_array_add(paths, item->cache_path);
      sizes[p] = item->size;
      if (p < output->first_part) already += item->size;
    }
    set_phase(job, OTZ_PHASE_ASSEMBLE, output->name, output->size);
    g_mutex_lock(&job->lock);
    job->progress.phase_done = already;
    job->progress.part_count = output->items->len;
    g_mutex_unlock(&job->lock);
    remove_stale_siblings(output->partial_path, output->name, ".partial");
    if (!otz_assemble(output->partial_path, dest, paths, sizes, output->first_part, output->size,
                      output->sha256,
                      add_phase_bytes, job, set_part, begin_assembly_verify,
                      job->inner, error)) {
      job->failure = g_error_matches(*error, OTZ_ERROR, OTZ_ERROR_CORRUPT)
                         ? OTZ_FAILURE_CORRUPT : OTZ_FAILURE_ASSEMBLE;
      return FALSE;
    }
  }
  return TRUE;
}

static void cancel_inner(GCancellable *outer, gpointer inner) {
  g_cancellable_cancel(G_CANCELLABLE(inner));
}

gboolean otz_job_run(OtzJob *job, GCancellable *cancellable, GError **error) {
  job->inner = g_cancellable_new();
  gulong handler = 0;
  if (cancellable != NULL)
    handler = g_cancellable_connect(cancellable, G_CALLBACK(cancel_inner),
                                    job->inner, NULL);
  gboolean ok = FALSE;

  if (g_mkdir_with_parents(job->cache_dir, 0755) != 0) {
    job->failure = OTZ_FAILURE_CACHE;
    g_set_error(error, OTZ_ERROR, OTZ_ERROR_IO, "cannot create %s: %s",
                job->cache_dir, g_strerror(errno));
    goto out;
  }
  if (!check_cache(job, job->inner, error)) {
    job->failure = OTZ_FAILURE_CACHE;
    goto out;
  }
  if (!download_missing(job, error)) goto out;
  if (!produce_outputs(job, error)) goto out;
  set_phase(job, OTZ_PHASE_DONE, NULL, 0);
  ok = TRUE;

out:
  /* A failing worker cancels job->inner to stop the others; only the caller's
   * cancellable means the user stopped the run. */
  if (!ok && cancellable != NULL && g_cancellable_is_cancelled(cancellable))
    job->failure = OTZ_FAILURE_CANCELLED;
  if (handler != 0) g_cancellable_disconnect(cancellable, handler);
  return ok;
}

static void run_in_thread(GTask *task, gpointer source, gpointer task_data,
                          GCancellable *cancellable) {
  GError *error = NULL;
  if (otz_job_run(task_data, cancellable, &error))
    g_task_return_boolean(task, TRUE);
  else
    g_task_return_error(task, error);
}

void otz_job_run_async(OtzJob *job, GCancellable *cancellable,
                       GAsyncReadyCallback callback, gpointer user_data) {
  g_autoptr(GTask) task = g_task_new(NULL, cancellable, callback, user_data);
  g_task_set_task_data(task, job, NULL);
  g_task_set_return_on_cancel(task, FALSE);
  g_task_run_in_thread(task, run_in_thread);
}

gboolean otz_job_run_finish(OtzJob *job, GAsyncResult *result, GError **error) {
  return g_task_propagate_boolean(G_TASK(result), error);
}

static gboolean nearest_device(const char *path, dev_t *device) {
  g_autofree char *current = g_strdup(path);
  for (;;) {
    struct stat st;
    if (stat(current, &st) == 0) {
      *device = st.st_dev;
      return TRUE;
    }
    char *parent = g_path_get_dirname(current);
    gboolean top = strcmp(parent, current) == 0;
    g_free(current);
    current = parent;
    if (top) return FALSE;
  }
}

void otz_job_space_needs(OtzJob *job, gint64 *cache_bytes, gint64 *output_bytes,
                         gboolean *same_filesystem) {
  dev_t cache_dev = 0, output_dev = 0;
  *same_filesystem = nearest_device(job->cache_dir, &cache_dev) &&
                     nearest_device(job->output_dir, &output_dev) &&
                     cache_dev == output_dev;
  *cache_bytes = 0;
  for (guint i = 0; i < job->items->len; i++) {
    Item *item = g_ptr_array_index(job->items, i);
    if (!item->skip && !otz_marker_matches(item->cache_path, item->sha256, item->size))
      *cache_bytes += item->size;
  }
  *output_bytes = 0;
  for (guint i = 0; i < job->outputs->len; i++) {
    Output *output = g_ptr_array_index(job->outputs, i);
    if (output->assemble) {
      *output_bytes += output->size;
      for (guint p = 0; p < output->first_part; p++)
        *output_bytes -= ((Item *)g_ptr_array_index(output->items, p))->size;
    } else if (!*same_filesystem) {
      /* On one filesystem the file is hard-linked and takes no extra space. */
      *output_bytes += output->size;
    }
  }
}

gboolean otz_space_is_enough(gint64 cache_bytes, gint64 output_bytes,
                             gboolean same_filesystem, gint64 cache_free,
                             gint64 output_free) {
  if (same_filesystem) return cache_free < 0 || cache_free >= cache_bytes + output_bytes;
  return (cache_free < 0 || cache_free >= cache_bytes) &&
         (output_free < 0 || output_free >= output_bytes);
}

OtzFailure otz_job_failure(OtzJob *job) { return job->failure; }
const char *otz_job_output_dir(OtzJob *job) { return job->output_dir; }
GPtrArray *otz_job_output_files(OtzJob *job) { return job->output_files; }
GPtrArray *otz_job_output_notes(OtzJob *job) { return job->output_notes; }
GPtrArray *otz_job_unjoined_assets(OtzJob *job) { return job->unjoined; }

gint64 otz_job_hashed_bytes(OtzJob *job) {
  g_mutex_lock(&job->lock);
  gint64 value = job->hashed;
  g_mutex_unlock(&job->lock);
  return value;
}

gint64 otz_job_downloaded_bytes(OtzJob *job) {
  g_mutex_lock(&job->lock);
  gint64 value = job->downloaded;
  g_mutex_unlock(&job->lock);
  return value;
}
