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

/* Frame i of the new base equals the old one: same length, no page of it
   from the overlay. Frame 0 always goes through the SQLite header checks. */
static int frame_from_base(zdb_file *f, uint64_t i, uint64_t logical) {
  uint64_t fb = f->frame_bytes, start = i * fb;
  if (i == 0 || i >= f->h.frame_count) return 0;
  uint64_t old_len = f->h.logical_size - start, new_len = logical - start;
  if (old_len > fb) old_len = fb;
  if (new_len > fb) new_len = fb;
  if (old_len != new_len) return 0;
  uint32_t ps = f->h.page_size;
  for (uint64_t pg = start / ps; pg < (start + new_len) / ps; pg++)
    if (!zovl_page_from_base(f->ovl, pg)) return 0;
  return 1;
}

static int logical_rd(void *ctx, void *buf, size_t n, uint64_t off) {
  return zvfs_read_logical((zvfs_reader *)ctx, buf, n, off);
}

#define COMPACT_CHUNK (4u << 20)

/* Copies the run of base frames [i, j) with one read; the converter's
   workers decode them (checksum, content hash) but do not compress them. */
static int copy_frames(zvfs_reader *r, zvfs_conv *c, uint64_t i, uint64_t j,
                       uint64_t logical, uint8_t *raw, uint8_t *plain) {
  zdb_file *f = r->f;
  uint64_t a = f->index[i], e = zdb_frame_end(f, j - 1);
  size_t got = 0;
  int rc = zplat_pread(r->pf, raw, (size_t)(e - a), a, &got);
  if (!rc && got != e - a) rc = ZVFS_ERR_CORRUPT;
  for (uint64_t k = i; !rc && k < j; k++) {
    uint64_t start = k * f->frame_bytes, left = logical - start;
    size_t n = (size_t)(left < f->frame_bytes ? left : f->frame_bytes);
    const uint8_t *src = raw + (f->index[k] - a);
    size_t clen = (size_t)(zdb_frame_end(f, k) - f->index[k]);
    rc = zvfs_conv_feed_frame(c, src, clen, n);
    if (rc == ZVFS_ERR_UNSUPPORTED) {
      rc = zdb_decode(f->ddict, src, clen, plain, n);
      if (!rc) rc = zvfs_conv_feed(c, plain, n);
    }
  }
  return rc;
}

ZVFS_API int zvfs_compact(const char *path, const char *dst, int level,
                          int threads, int flags, volatile int32_t *cancel,
                          volatile int64_t *progress, zvfs_info *out,
                          zvfs_compact_stats *stats, char *err,
                          size_t err_len) {
  if (!path || !dst) return ZVFS_ERR_INVALID;
  set_err(err, err_len, "");
  if (stats) memset(stats, 0, sizeof *stats);
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
  zvfs_conv_set_copy_ddict(c, f->ddict);
  zvfs_pageset leaves = {0};
  if (!(flags & ZVFS_COMPACT_KEEP_FREELIST)) {
    rc = zvfs_freelist_leaves(logical_rd, r, logical, &leaves);
    if (!rc && stats) stats->freelist_leaves = leaves.count;
    if (!rc && leaves.bits) rc = zvfs_conv_set_zero_pages(c, &leaves);
    free(leaves.bits);
  }
  const uint64_t fb = f->frame_bytes;
  const int reuse = !(flags & ZVFS_COMPACT_RECOMPRESS);
  /* a run is at least one frame (up to 16MB) */
  size_t chunk = fb > COMPACT_CHUNK ? (size_t)fb : COMPACT_CHUNK;
  size_t raw_cap = chunk + zdb_max_frame_len(&f->h);
  uint8_t *buf = rc ? NULL : (uint8_t *)malloc(chunk);
  uint8_t *raw = rc || !reuse ? NULL : (uint8_t *)malloc(raw_cap);
  if (!rc && (!buf || (reuse && !raw))) rc = ZVFS_ERR_NOMEM;
  for (uint64_t off = 0; !rc && off < logical;) {
    uint64_t i = off / fb, j = i + 1;
    int copy = reuse && frame_from_base(f, i, logical);
    if (copy) {
      /* contiguous frames only: a read must not cross the lock-byte gap */
      while (j * fb < logical && frame_from_base(f, j, logical) &&
             zdb_frame_end(f, j - 1) == f->index[j] &&
             zdb_frame_end(f, j) - f->index[i] <= raw_cap)
        j++;
      rc = copy_frames(r, c, i, j, logical, raw, buf);
    } else {
      while (j * fb < logical && (j + 1 - i) * fb <= chunk &&
             !(reuse && frame_from_base(f, j, logical)))
        j++;
      uint64_t end = j * fb < logical ? j * fb : logical;
      rc = zvfs_read_logical(r, buf, end - off, off);
      if (!rc) rc = zvfs_conv_feed(c, buf, (size_t)(end - off));
    }
    off = j * fb < logical ? j * fb : logical;
    if (progress) zplat_atomic_store(progress, (int64_t)off);
  }
  free(buf);
  free(raw);
  if (!rc) rc = zvfs_conv_finish(c, out);
  if (!rc && stats) {
    stats->frames = (logical + fb - 1) / fb;
    stats->frames_copied = zvfs_conv_frames_copied(c);
  }
  if (rc) {
    const char *m = zvfs_conv_error(c);
    set_err(err, err_len, *m ? m : "reading the source failed");
  }
  zvfs_conv_destroy(c);
  zvfs_reader_close(r);
  return rc;
}
