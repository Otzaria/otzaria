/* Compaction step 1: base + overlay -> a new base through the logical view. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zvfs_internal.h"

/* A hot journal or a non-empty WAL means base + overlay is not the content. */
static int nonempty(const char *p) {
  int e = zplat_exists(p);
  if (e <= 0) return e < 0;
  zplat_file *f;
  uint64_t size = 1;
  if (zplat_open_read(p, &f) == ZVFS_OK) {
    zplat_size(f, &size);
    zplat_close(f);
  }
  return size != 0;
}

int zvfs_sidecars_busy(const char *path) {
  size_t n = strlen(path);
  char *b = (char *)malloc(n + 16);
  if (!b) return 1;
  memcpy(b, path, n);
  memcpy(b + n, "-journal", 9);
  int busy = nonempty(b);
  memcpy(b + n, "-wal", 5);
  busy = busy || nonempty(b);
  free(b);
  return busy;
}

/* The overlay a compacted base names. An obsolete sidecar left by an
   interrupted swap is named too, so it stays obsolete if it survives again. */
void zvfs_lineage_of(const zovl_info *oi, uint8_t uuid[16], uint64_t *seq) {
  memset(uuid, 0, 16);
  *seq = 0;
  if (oi->present) {
    memcpy(uuid, oi->overlay_uuid, 16);
    *seq = oi->seq;
  } else if (oi->stale_obsolete) {
    memcpy(uuid, oi->stale_uuid, 16);
    *seq = oi->stale_seq;
  }
}

#ifdef ZVFS_TEST_HOOKS
int (*zvfs_test_install_step)(int step);
#define INSTALL_STEP(i) (zvfs_test_install_step && zvfs_test_install_step(i))
#else
#define INSTALL_STEP(i) 0
#endif

int zvfs_install_locked(const char *path, const char *candidate) {
  size_t n = strlen(path) > strlen(candidate) ? strlen(path) : strlen(candidate);
  char *b = (char *)malloc(n + 16), *stage = (char *)malloc(n + 16);
  int rc = b && stage ? ZVFS_OK : ZVFS_ERR_NOMEM;
  const char *src = candidate;
  /* its overlay would stay behind under the old name */
  if (!rc) snprintf(b, n + 16, "%s%s", candidate, ZDB_OVERLAY_SUFFIX);
  if (!rc && zplat_exists(b) != 0) rc = ZVFS_ERR_INVALID;
  zvfs_reader *r = NULL;
  if (!rc) rc = zvfs_reader_open(candidate, &r);
  zvfs_reader_close(r);
  /* Before any delete, prove the final rename: path is replaceable and the
     candidate, staged next to it, is on its volume. */
  if (!rc) rc = zplat_replaceable(path);
  if (!rc) snprintf(stage, n + 16, "%s%s", path, ZDB_INSTALL_SUFFIX);
  if (!rc && strcmp(candidate, stage) != 0 &&
      !(rc = zplat_rename_durable(candidate, stage)))
    src = stage;
  /* journal and WAL first: replayed onto the bare old base they would corrupt it */
  static const char *const sfx[] = {"-journal", "-wal", "-shm",
                                    ZDB_OVERLAY_SUFFIX, ".new"};
  for (int i = 0; !rc && i < 5; i++) {
    snprintf(b, n + 16, "%s%s", path, sfx[i]);
    rc = zplat_delete_durable(b);
    if (!rc && INSTALL_STEP(i)) rc = ZVFS_ERR_IO;
  }
  /* NTFS logs metadata in order: the write-through rename flushes the deletes */
  if (!rc) rc = zplat_rename_durable(src, path);
  if (rc && src != candidate) zplat_rename_durable(src, candidate);
  free(b);
  free(stage);
  return rc;
}

static void set_err(char *err, size_t n, const char *msg) {
  if (err && n) snprintf(err, n, "%s", msg);
}

ZVFS_API int zvfs_compact(const char *path, const char *dst, int level,
                          int threads, volatile int32_t *cancel,
                          volatile int64_t *progress, zvfs_info *out,
                          char *err, size_t err_len) {
  if (!path || !dst) return ZVFS_ERR_INVALID;
  set_err(err, err_len, "");
  /* before any open: closing a descriptor would drop this process's locks */
  int u = zvfs_in_use(path);
  if (u) {
    set_err(err, err_len, "the database is open in this process");
    return u < 0 ? ZVFS_ERR_NOMEM : ZVFS_ERR_BUSY;
  }
  if (zvfs_sidecars_busy(path)) {
    set_err(err, err_len, "a journal or WAL file is pending; open the database first");
    return ZVFS_ERR_BUSY;
  }
  zvfs_reader *r = NULL;
  int rc = zvfs_reader_open(path, &r);
  if (rc) {
    set_err(err, err_len, "cannot open the source");
    return rc;
  }
  zdb_file *f = r->f;
  zovl_info oi;
  zovl_get_info(f->ovl, &oi);
  uint64_t logical = oi.logical_size;
  if (logical == 0 || logical % f->h.page_size) {
    zvfs_reader_close(r);
    set_err(err, err_len, "logical size is not a whole number of pages");
    return ZVFS_ERR_INVALID;
  }
  zvfs_conv *c = NULL;
  rc = zvfs_conv_create(dst, f->dict, f->h.dict_length, f->h.dict_name, level,
                        threads, f->h.frame_pages, 16u << 20, cancel, &c);
  if (rc) {
    zvfs_reader_close(r);
    set_err(err, err_len, "cannot create the destination");
    return rc;
  }
  uint8_t lin_uuid[16];
  uint64_t lin_seq;
  zvfs_lineage_of(&oi, lin_uuid, &lin_seq);
  zvfs_conv_set_lineage(c, f->h.uuid, lin_uuid, lin_seq);
  const size_t chunk = 4u << 20;
  uint8_t *buf = (uint8_t *)malloc(chunk);
  if (!buf) rc = ZVFS_ERR_NOMEM;
  for (uint64_t off = 0; !rc && off < logical;) {
    size_t n = logical - off < chunk ? (size_t)(logical - off) : chunk;
    rc = zvfs_read_logical(r, buf, n, off);
    if (!rc) rc = zvfs_conv_feed(c, buf, n);
    off += n;
    if (progress) zplat_atomic_store(progress, (int64_t)off);
  }
  free(buf);
  if (!rc) rc = zvfs_conv_finish(c, out);
  if (rc) set_err(err, err_len, zvfs_conv_error(c));
  zvfs_conv_destroy(c);
  zvfs_reader_close(r);
  return rc;
}
