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

static void set_err(char *err, size_t n, const char *msg) {
  if (err && n) snprintf(err, n, "%s", msg);
}

ZVFS_API int zvfs_compact(const char *path, const char *dst, int level,
                          int threads, volatile int32_t *cancel,
                          volatile int64_t *progress, zvfs_info *out,
                          char *err, size_t err_len) {
  if (!path || !dst) return ZVFS_ERR_INVALID;
  set_err(err, err_len, "");
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
  uint8_t zero[16] = {0};
  zvfs_conv_set_lineage(c, f->h.uuid, oi.present ? oi.overlay_uuid : zero,
                        oi.present ? oi.seq : 0);
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
