/* Standalone reader (no SQLite): base + read-only overlay replay. */
#include <stdlib.h>
#include <string.h>

#include "zvfs_internal.h"

static int reader_rd(void *ctx, void *buf, size_t n, uint64_t off) {
  size_t got = 0;
  int rc = zplat_pread((zplat_file *)ctx, buf, n, off, &got);
  if (rc) return rc;
  return got == n ? ZVFS_OK : ZVFS_ERR_SHORT_READ;
}

/* ---- read-only overlay env over zplat ---- */
static int rv_read(void *h, void *buf, size_t n, uint64_t off) {
  size_t got = 0;
  int rc = zplat_pread((zplat_file *)h, buf, n, off, &got);
  if (rc) return rc;
  if (got == n) return ZVFS_OK;
  memset((uint8_t *)buf + got, 0, n - got);
  return ZVFS_ERR_SHORT_READ;
}
static int rv_write(void *h, const void *b, size_t n, uint64_t off) {
  (void)h, (void)b, (void)n, (void)off;
  return ZVFS_ERR_READONLY;
}
static int rv_truncate(void *h, uint64_t size) {
  (void)h, (void)size;
  return ZVFS_ERR_READONLY;
}
static int rv_sync(void *h, int flags) {
  (void)h, (void)flags;
  return ZVFS_ERR_READONLY;
}
static int rv_size(void *h, uint64_t *out) {
  return zplat_size((zplat_file *)h, out);
}
static void rv_close(void *h) { zplat_close((zplat_file *)h); }
static int rv_open(void *env, int create, void **out) {
  *out = NULL;
  if (create) return ZVFS_ERR_READONLY;
  int e = zplat_exists((const char *)env);
  if (e < 0) return ZVFS_ERR_IO;
  if (!e) return ZVFS_OK;
  zplat_file *f = NULL;
  int rc = zplat_open_read((const char *)env, &f);
  if (rc) return zplat_exists((const char *)env) == 0 ? ZVFS_OK : rc;
  *out = f;
  return ZVFS_OK;
}
static void rv_env_free(void *env) { free(env); }

static const zovl_ops k_ro_ops = {rv_read, rv_write, rv_truncate, rv_sync,
                                  rv_size, rv_close, rv_open,     rv_env_free};

ZVFS_API int zvfs_probe_path(const char *path) {
  zplat_file *pf;
  if (!path) return 0;
  int u = zvfs_in_use(path);
  if (u) return u == 2;
  if (zplat_open_read(path, &pf)) return 0;
  uint8_t m[ZDB_MAGIC_LEN];
  size_t got = 0;
  int ok = zplat_pread(pf, m, sizeof m, 0, &got) == ZVFS_OK &&
           zdb_has_magic(m, got);
  zplat_close(pf);
  return ok;
}

ZVFS_API int zvfs_reader_open(const char *path, zvfs_reader **out) {
  if (!path || !out) return ZVFS_ERR_INVALID;
  *out = NULL;
  if (zvfs_in_use(path)) return ZVFS_ERR_BUSY;
  zvfs_reader *r = (zvfs_reader *)calloc(1, sizeof *r);
  if (!r) return ZVFS_ERR_NOMEM;
  int rc = zplat_open_read(path, &r->pf);
  uint64_t size = 0;
  if (!rc) rc = zplat_size(r->pf, &size);
  if (!rc) {
    uint8_t m[ZDB_MAGIC_LEN];
    size_t got = 0;
    rc = zplat_pread(r->pf, m, sizeof m, 0, &got);
    if (!rc && !zdb_has_magic(m, got)) rc = ZVFS_ERR_NOT_ZDB;
  }
  if (!rc) rc = zdb_file_load(reader_rd, r->pf, size, &r->f);
  if (!rc) {
    size_t n = strlen(path);
    char *ov = (char *)malloc(n + sizeof ZDB_OVERLAY_SUFFIX);
    if (!ov) {
      rc = ZVFS_ERR_NOMEM;
    } else {
      memcpy(ov, path, n);
      memcpy(ov + n, ZDB_OVERLAY_SUFFIX, sizeof ZDB_OVERLAY_SUFFIX);
      rc = zovl_create(&k_ro_ops, ov, r->f, &r->f->ovl);
      if (rc) free(ov);
    }
  }
  if (rc) {
    zdb_file_free(r->f);
    zplat_close(r->pf);
    free(r);
    return rc;
  }
  *out = r;
  return ZVFS_OK;
}

ZVFS_API int zvfs_reader_info(zvfs_reader *r, zvfs_info *out) {
  if (!r || !out) return ZVFS_ERR_INVALID;
  zdb_fill_info(r->f, out);
  out->logical_size = zovl_logical_size(r->f->ovl);
  return ZVFS_OK;
}

void zvfs_fill_overlay_info(zovl *o, zvfs_overlay_info *out) {
  zovl_info i;
  zovl_get_info(o, &i);
  memset(out, 0, sizeof *out);
  out->present = i.present;
  out->seq = i.seq;
  out->commits = i.commits;
  out->records = i.records;
  out->file_size = i.file_size;
  out->committed_end = i.committed_end;
  out->logical_size = i.logical_size;
  out->mapped_pages = i.mapped_pages;
  out->base_visible_pages = i.base_visible_pages;
  memcpy(out->overlay_uuid, i.overlay_uuid, 16);
}

ZVFS_API int zvfs_reader_overlay_info(zvfs_reader *r, zvfs_overlay_info *out) {
  if (!r || !out) return ZVFS_ERR_INVALID;
  zvfs_fill_overlay_info(r->f->ovl, out);
  return ZVFS_OK;
}

int zvfs_read_logical(zvfs_reader *r, void *buf, uint64_t n, uint64_t off) {
  return zovl_read(r->f->ovl, reader_rd, r->pf, (uint8_t *)buf, n, off);
}

ZVFS_API int zvfs_reader_read(zvfs_reader *r, void *buf, int64_t n,
                              int64_t off) {
  if (!r || !buf || n < 0 || off < 0) return ZVFS_ERR_INVALID;
  return zvfs_read_logical(r, buf, (uint64_t)n, (uint64_t)off);
}

ZVFS_API void zvfs_reader_close(zvfs_reader *r) {
  if (!r) return;
  zdb_file_free(r->f);
  zplat_close(r->pf);
  free(r);
}

ZVFS_API int zvfs_reader_verify(zvfs_reader *r, volatile int32_t *cancel,
                                volatile int64_t *progress) {
  if (!r) return ZVFS_ERR_INVALID;
  int rc = zdb_verify_base(r->f, reader_rd, r->pf, cancel, progress);
  if (!rc) rc = zovl_verify(r->f->ovl, cancel);
  return rc;
}
