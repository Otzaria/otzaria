/* SQLite VFS shim: .zdb bases + overlay sidecar; other files pass through. */
#include <stdlib.h>
#include <string.h>

#include "zvfs_internal.h"

#include "sqlite3ext.h"
SQLITE_EXTENSION_INIT1

static sqlite3_vfs *g_base;
static sqlite3_vfs g_vfs;
static volatile int64_t g_registered;
static zplat_mutex g_mu = ZPLAT_MUTEX_INIT; /* registration + g_files */
static zdb_file *g_files;

/* Main databases opened through zvfs without the zdb magic, by full path. */
typedef struct open_path {
  struct open_path *next;
  char *key;
  int count;
} open_path;
static open_path *g_plain;

typedef struct zfile {
  sqlite3_file base;
  zdb_file *z; /* NULL: passthrough */
  sqlite3_file *real;
  int writable;
  int lock; /* level held through xLock/xUnlock */
  open_path *plain;
} zfile;

static int map_rc(int rc) {
  switch (rc) {
    case ZVFS_OK: return SQLITE_OK;
    case ZVFS_ERR_CORRUPT: return SQLITE_CORRUPT;
    case ZVFS_ERR_NOMEM: return SQLITE_NOMEM;
    case ZVFS_ERR_SHORT_READ: return SQLITE_IOERR_SHORT_READ;
    case ZVFS_ERR_UNSUPPORTED: return SQLITE_CANTOPEN;
    case ZVFS_ERR_FULL: return SQLITE_FULL;
    case ZVFS_ERR_READONLY: return SQLITE_READONLY;
    default: return SQLITE_IOERR_READ;
  }
}

/* Keeps SHORT_READ/CORRUPT/FULL/NOMEM/READONLY, else the op's I/O code. */
static int map_io(int rc, int ioerr) {
  if (rc == ZVFS_OK) return SQLITE_OK;
  if (rc == ZVFS_ERR_SHORT_READ || rc == ZVFS_ERR_CORRUPT ||
      rc == ZVFS_ERR_FULL || rc == ZVFS_ERR_NOMEM || rc == ZVFS_ERR_READONLY)
    return map_rc(rc);
  return ioerr;
}

static int real_rd(void *ctx, void *buf, size_t n, uint64_t off) {
  sqlite3_file *r = (sqlite3_file *)ctx;
  uint8_t *p = (uint8_t *)buf;
  while (n) {
    int chunk = n > (1u << 30) ? (1 << 30) : (int)n;
    int rc = r->pMethods->xRead(r, p, chunk, (sqlite3_int64)off);
    if (rc == SQLITE_IOERR_SHORT_READ) return ZVFS_ERR_SHORT_READ;
    if (rc != SQLITE_OK) return ZVFS_ERR_IO;
    p += chunk;
    off += (uint64_t)chunk;
    n -= (size_t)chunk;
  }
  return ZVFS_OK;
}

/* ---- overlay sidecar through the base VFS (its retries, no locking) ---- */
typedef struct ovl_env {
  char *path; /* "<db>-zovl", double-NUL terminated; outlives the handle */
} ovl_env;

/* VFS file objects are not thread-safe (unixRead stores lastErrno even on a
   short read): one mutex per handle; a separate read handle skips fsyncs. */
typedef struct ovh {
  sqlite3_file *w; /* writes, truncate, fsync */
  sqlite3_file *r; /* reads and size; == w when a second open failed */
  zplat_mutex wmu, rmu;
} ovh;

static int ov_read(void *h, void *buf, size_t n, uint64_t off) {
  ovh *o = (ovh *)h;
  zplat_mutex *m = o->r == o->w ? &o->wmu : &o->rmu;
  zplat_lock(m);
  int rc = o->r->pMethods->xRead(o->r, buf, (int)n, (sqlite3_int64)off);
  zplat_unlock(m);
  if (rc == SQLITE_IOERR_SHORT_READ) return ZVFS_ERR_SHORT_READ;
  return rc == SQLITE_OK ? ZVFS_OK : ZVFS_ERR_IO;
}
static int ov_write(void *h, const void *buf, size_t n, uint64_t off) {
  ovh *o = (ovh *)h;
  zplat_lock(&o->wmu);
  int rc = o->w->pMethods->xWrite(o->w, buf, (int)n, (sqlite3_int64)off);
  zplat_unlock(&o->wmu);
  if (rc == SQLITE_FULL) return ZVFS_ERR_FULL;
  if (rc == SQLITE_READONLY) return ZVFS_ERR_READONLY;
  return rc == SQLITE_OK ? ZVFS_OK : ZVFS_ERR_IO;
}
static int ov_truncate(void *h, uint64_t size) {
  ovh *o = (ovh *)h;
  zplat_lock(&o->wmu);
  int rc = o->w->pMethods->xTruncate(o->w, (sqlite3_int64)size);
  zplat_unlock(&o->wmu);
  return rc == SQLITE_OK ? ZVFS_OK : ZVFS_ERR_IO;
}
static int ov_sync(void *h, int flags) {
  ovh *o = (ovh *)h;
  if (!(flags & 0x0F)) flags |= SQLITE_SYNC_NORMAL;
  zplat_lock(&o->wmu);
  int rc = o->w->pMethods->xSync(o->w, flags);
  zplat_unlock(&o->wmu);
  return rc == SQLITE_OK ? ZVFS_OK : ZVFS_ERR_IO;
}
static int ov_size(void *h, uint64_t *out) {
  ovh *o = (ovh *)h;
  zplat_mutex *m = o->r == o->w ? &o->wmu : &o->rmu;
  sqlite3_int64 n = 0;
  zplat_lock(m);
  int rc = o->r->pMethods->xFileSize(o->r, &n);
  zplat_unlock(m);
  *out = n < 0 ? 0 : (uint64_t)n;
  return rc == SQLITE_OK ? ZVFS_OK : ZVFS_ERR_IO;
}
static void close_file(sqlite3_file *f) {
  if (!f) return;
  if (f->pMethods) f->pMethods->xClose(f);
  sqlite3_free(f);
}
static void ov_close(void *h) {
  ovh *o = (ovh *)h;
  if (o->r != o->w) close_file(o->r);
  close_file(o->w);
  zplat_mutex_destroy(&o->wmu);
  zplat_mutex_destroy(&o->rmu);
  sqlite3_free(o);
}
static sqlite3_file *open_file(const char *path, int flags, int *rc) {
  sqlite3_file *f = (sqlite3_file *)sqlite3_malloc(g_base->szOsFile);
  if (!f) {
    *rc = SQLITE_NOMEM;
    return NULL;
  }
  memset(f, 0, (size_t)g_base->szOsFile);
  int outf = 0;
  *rc = g_base->xOpen(g_base, path, f, flags, &outf);
  if (*rc != SQLITE_OK) {
    sqlite3_free(f);
    return NULL;
  }
  return f;
}
static int ov_open(void *env, int create, void **out) {
  ovl_env *e = (ovl_env *)env;
  *out = NULL;
  if (!create) {
    int exists = 0;
    if (g_base->xAccess(g_base, e->path, SQLITE_ACCESS_EXISTS, &exists) !=
        SQLITE_OK)
      return ZVFS_ERR_IO;
    if (!exists) return ZVFS_OK;
  }
  /* Journal type: never locked; POSIX fsyncs the directory after create. */
  int rc = SQLITE_OK;
  sqlite3_file *w = open_file(
      e->path,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_MAIN_JOURNAL |
          (create ? SQLITE_OPEN_CREATE : 0),
      &rc);
  if (!w && !create)
    w = open_file(e->path, SQLITE_OPEN_READONLY | SQLITE_OPEN_MAIN_JOURNAL, &rc);
  if (!w) {
    int exists = 1;
    if (!create) g_base->xAccess(g_base, e->path, SQLITE_ACCESS_EXISTS, &exists);
    if (!exists) return ZVFS_OK; /* removed between the two calls */
    return rc == SQLITE_READONLY ? ZVFS_ERR_READONLY
           : rc == SQLITE_NOMEM  ? ZVFS_ERR_NOMEM
                                 : ZVFS_ERR_IO;
  }
  ovh *o = (ovh *)sqlite3_malloc(sizeof *o);
  if (!o) {
    close_file(w);
    return ZVFS_ERR_NOMEM;
  }
  o->w = w;
  o->r = open_file(e->path, SQLITE_OPEN_READONLY | SQLITE_OPEN_MAIN_JOURNAL, &rc);
  if (!o->r) o->r = w;
  zplat_mutex_init(&o->wmu);
  zplat_mutex_init(&o->rmu);
  *out = o;
  return ZVFS_OK;
}
static void ov_env_free(void *env) {
  ovl_env *e = (ovl_env *)env;
  sqlite3_free(e->path);
  sqlite3_free(e);
}

static const zovl_ops g_ovl_ops = {ov_read, ov_write, ov_truncate, ov_sync,
                                   ov_size, ov_close,  ov_open,     ov_env_free};

static char *with_suffix(const char *path, const char *suffix) {
  size_t n = strlen(path), k = strlen(suffix);
  char *p = (char *)sqlite3_malloc64(n + k + 2);
  if (!p) return NULL;
  memcpy(p, path, n);
  memcpy(p + n, suffix, k);
  p[n + k] = p[n + k + 1] = 0;
  return p;
}

static ovl_env *make_env(const char *db_path) {
  ovl_env *e = (ovl_env *)sqlite3_malloc(sizeof *e);
  if (!e) return NULL;
  e->path = with_suffix(db_path, ZDB_OVERLAY_SUFFIX);
  if (!e->path) {
    sqlite3_free(e);
    return NULL;
  }
  return e;
}

/* ---- io methods ---- */
static int zRead(sqlite3_file *pf, void *buf, int amt, sqlite3_int64 off) {
  zfile *f = (zfile *)pf;
  if (!f->z) return f->real->pMethods->xRead(f->real, buf, amt, off);
  if (amt < 0 || off < 0) return SQLITE_IOERR_READ;
  return map_io(zovl_read(f->z->ovl, real_rd, f->real, (uint8_t *)buf,
                          (uint64_t)amt, (uint64_t)off),
                SQLITE_IOERR_READ);
}

static int zWrite(sqlite3_file *pf, const void *b, int amt, sqlite3_int64 off) {
  zfile *f = (zfile *)pf;
  if (!f->z) return f->real->pMethods->xWrite(f->real, b, amt, off);
  if (!f->writable) return SQLITE_READONLY;
  if (amt < 0 || off < 0) return SQLITE_IOERR_WRITE;
  return map_io(zovl_write(f->z->ovl, real_rd, f->real, (const uint8_t *)b,
                           (uint64_t)amt, (uint64_t)off),
                SQLITE_IOERR_WRITE);
}

static int zTruncate(sqlite3_file *pf, sqlite3_int64 size) {
  zfile *f = (zfile *)pf;
  if (!f->z) return f->real->pMethods->xTruncate(f->real, size);
  if (!f->writable) return SQLITE_READONLY;
  if (size < 0) return SQLITE_IOERR_TRUNCATE;
  return map_io(zovl_truncate(f->z->ovl, real_rd, f->real, (uint64_t)size),
                SQLITE_IOERR_TRUNCATE);
}

static int zSync(sqlite3_file *pf, int flags) {
  zfile *f = (zfile *)pf;
  if (!f->z) return f->real->pMethods->xSync(f->real, flags);
  return map_io(zovl_commit(f->z->ovl, flags ? flags : SQLITE_SYNC_NORMAL),
                SQLITE_IOERR_FSYNC);
}

static int zFileSize(sqlite3_file *pf, sqlite3_int64 *size) {
  zfile *f = (zfile *)pf;
  if (f->z) {
    *size = (sqlite3_int64)zovl_logical_size(f->z->ovl);
    return SQLITE_OK;
  }
  return f->real->pMethods->xFileSize(f->real, size);
}

/* Unsealed writes are committed before a lock release publishes them. */
static int seal(zfile *f) {
  return f->z ? zovl_commit(f->z->ovl, 0) : ZVFS_OK;
}

static int zLock(sqlite3_file *pf, int l) {
  zfile *f = (zfile *)pf;
  int rc = f->real->pMethods->xLock(f->real, l);
  if (rc == SQLITE_OK && f->z) {
    /* another process may have committed while we held no lock */
    int zr = zovl_refresh(f->z->ovl);
    if (zr) {
      f->real->pMethods->xUnlock(f->real, f->lock);
      return map_io(zr, SQLITE_IOERR_LOCK);
    }
  }
  if (rc == SQLITE_OK) f->lock = l;
  return rc;
}
static int zUnlock(sqlite3_file *pf, int l) {
  zfile *f = (zfile *)pf;
  int zr = seal(f);
  int rc = f->real->pMethods->xUnlock(f->real, l);
  if (rc == SQLITE_OK) f->lock = l;
  if (rc == SQLITE_OK && zr) rc = map_io(zr, SQLITE_IOERR_UNLOCK);
  return rc;
}
static int zCheckReserved(sqlite3_file *pf, int *out) {
  zfile *f = (zfile *)pf;
  return f->real->pMethods->xCheckReservedLock(f->real, out);
}

static int zFileControl(sqlite3_file *pf, int op, void *arg) {
  zfile *f = (zfile *)pf;
  if (f->z) {
    switch (op) {
      case SQLITE_FCNTL_MMAP_SIZE:
        *(sqlite3_int64 *)arg = 0;
        return SQLITE_OK;
      case SQLITE_FCNTL_SIZE_HINT:
      case SQLITE_FCNTL_CHUNK_SIZE:
        return SQLITE_OK;
      case SQLITE_FCNTL_CKPT_DONE: {
        /* nBackfill is published after this, possibly without an xSync */
        int zr = seal(f);
        if (zr) return map_io(zr, SQLITE_IOERR_WRITE);
        break;
      }
      default:
        break;
    }
  }
  int rc = f->real->pMethods->xFileControl(f->real, op, arg);
  if (op == SQLITE_FCNTL_VFSNAME && rc == SQLITE_OK) {
    char *inner = *(char **)arg;
    *(char **)arg = sqlite3_mprintf("%s/%s", f->z ? "zvfs(zdb)" : "zvfs",
                                    inner ? inner : "");
    sqlite3_free(inner);
  }
  return rc;
}

static int zSectorSize(sqlite3_file *pf) {
  zfile *f = (zfile *)pf;
  return f->real->pMethods->xSectorSize(f->real);
}
static int zDeviceChar(sqlite3_file *pf) {
  zfile *f = (zfile *)pf;
  return f->real->pMethods->xDeviceCharacteristics(f->real);
}

static int zShmMap(sqlite3_file *pf, int pg, int sz, int ext, void volatile **pp) {
  zfile *f = (zfile *)pf;
  if (f->real->pMethods->iVersion < 2) return SQLITE_IOERR_SHMMAP;
  return f->real->pMethods->xShmMap(f->real, pg, sz, ext, pp);
}
static int zShmLock(sqlite3_file *pf, int off, int n, int flags) {
  zfile *f = (zfile *)pf;
  if (f->real->pMethods->iVersion < 2) return SQLITE_IOERR_SHMLOCK;
  int unlock = (flags & SQLITE_SHM_UNLOCK) != 0;
  int zr = f->z && unlock ? seal(f) : ZVFS_OK;
  int rc = f->real->pMethods->xShmLock(f->real, off, n, flags);
  if (rc != SQLITE_OK || !f->z) return rc;
  if (unlock) return zr ? map_io(zr, SQLITE_IOERR_SHMLOCK) : SQLITE_OK;
  /* WAL readers and checkpointers learn of new db pages through the shm */
  zr = zovl_refresh(f->z->ovl);
  if (zr) {
    int mode = flags & (SQLITE_SHM_SHARED | SQLITE_SHM_EXCLUSIVE);
    f->real->pMethods->xShmLock(f->real, off, n, SQLITE_SHM_UNLOCK | mode);
    return map_io(zr, SQLITE_IOERR_SHMLOCK);
  }
  return SQLITE_OK;
}
static void zShmBarrier(sqlite3_file *pf) {
  zfile *f = (zfile *)pf;
  if (f->real->pMethods->iVersion >= 2) f->real->pMethods->xShmBarrier(f->real);
}
static int zShmUnmap(sqlite3_file *pf, int del) {
  zfile *f = (zfile *)pf;
  if (f->real->pMethods->iVersion < 2) return SQLITE_OK;
  return f->real->pMethods->xShmUnmap(f->real, del);
}

static int zFetch(sqlite3_file *pf, sqlite3_int64 off, int amt, void **pp) {
  zfile *f = (zfile *)pf;
  *pp = NULL;
  if (f->z || f->real->pMethods->iVersion < 3) return SQLITE_OK;
  return f->real->pMethods->xFetch(f->real, off, amt, pp);
}
static int zUnfetch(sqlite3_file *pf, sqlite3_int64 off, void *p) {
  zfile *f = (zfile *)pf;
  if (f->z || f->real->pMethods->iVersion < 3) return SQLITE_OK;
  return f->real->pMethods->xUnfetch(f->real, off, p);
}

static void release_shared(zdb_file *z) {
  zplat_lock(&g_mu);
  int last = --z->refs == 0;
  if (last) {
    zdb_file **pp = &g_files;
    while (*pp && *pp != z) pp = &(*pp)->next;
    if (*pp) *pp = z->next;
  }
  zplat_unlock(&g_mu);
  if (last) {
    zdb_file_free(z);
    zvfs_stat_open_files(-1);
  }
}

static void release_plain(open_path *op) {
  zplat_lock(&g_mu);
  int last = --op->count == 0;
  if (last) {
    open_path **pp = &g_plain;
    while (*pp && *pp != op) pp = &(*pp)->next;
    if (*pp) *pp = op->next;
  }
  zplat_unlock(&g_mu);
  if (last) {
    free(op->key);
    free(op);
  }
}

/* Best effort: a failed registration only weakens the in-use answer. */
static void register_plain(zfile *f, const char *path) {
  zplat_lock(&g_mu);
  open_path *op = g_plain;
  while (op && strcmp(op->key, path) != 0) op = op->next;
  if (!op && (op = (open_path *)calloc(1, sizeof *op)) != NULL) {
    size_t n = strlen(path) + 1;
    op->key = (char *)malloc(n);
    if (op->key) {
      memcpy(op->key, path, n);
      op->next = g_plain;
      g_plain = op;
    } else {
      free(op);
      op = NULL;
    }
  }
  if (op) op->count++;
  f->plain = op;
  zplat_unlock(&g_mu);
}

static int zClose(sqlite3_file *pf) {
  zfile *f = (zfile *)pf;
  if (f->z) seal(f);
  int rc = f->real->pMethods ? f->real->pMethods->xClose(f->real) : SQLITE_OK;
  if (f->z) release_shared(f->z);
  if (f->plain) release_plain(f->plain);
  f->z = NULL;
  f->plain = NULL;
  return rc;
}

static const sqlite3_io_methods g_methods = {
    3,           zClose,       zRead,          zWrite,        zTruncate,
    zSync,       zFileSize,    zLock,          zUnlock,       zCheckReserved,
    zFileControl, zSectorSize, zDeviceChar,    zShmMap,       zShmLock,
    zShmBarrier, zShmUnmap,    zFetch,         zUnfetch};

static zdb_file *find_shared(const char *path, uint64_t phys,
                             const uint8_t *raw) {
  for (zdb_file *z = g_files; z; z = z->next)
    if (z->physical_size == phys && strcmp(z->key, path) == 0 &&
        memcmp(z->raw_header, raw, ZDB_HEADER_CORE) == 0)
      return z;
  return NULL;
}

/* One state per (path, header): a replaced base never reuses a stale index,
   and all connections of a process share one overlay page map. */
static int attach_shared(zfile *f, const char *path, uint64_t phys) {
  uint8_t raw[ZDB_HEADER_CORE];
  int rc = real_rd(f->real, raw, sizeof raw, 0);
  if (rc) return rc == ZVFS_ERR_SHORT_READ ? ZVFS_ERR_CORRUPT : rc;
  zplat_lock(&g_mu);
  zdb_file *z = find_shared(path, phys, raw);
  if (z) {
    z->refs++;
    f->z = z;
  }
  zplat_unlock(&g_mu);
  if (f->z) return ZVFS_OK;

  zdb_file *nz = NULL;
  rc = zdb_file_load(real_rd, f->real, phys, &nz);
  if (rc) return rc;
  size_t n = strlen(path) + 1;
  nz->key = (char *)malloc(n);
  ovl_env *env = make_env(path);
  if (!nz->key || !env) {
    if (env) ov_env_free(env);
    zdb_file_free(nz);
    return ZVFS_ERR_NOMEM;
  }
  memcpy(nz->key, path, n);
  rc = zovl_create(&g_ovl_ops, env, nz, &nz->ovl);
  if (rc) {
    ov_env_free(env);
    zdb_file_free(nz);
    return rc;
  }
  nz->refs = 1;
  zplat_lock(&g_mu);
  z = find_shared(path, phys, nz->raw_header);
  if (z) {
    z->refs++;
    f->z = z;
  } else {
    nz->next = g_files;
    g_files = nz;
    f->z = nz;
    nz = NULL;
  }
  zplat_unlock(&g_mu);
  if (nz) zdb_file_free(nz);
  else zvfs_stat_open_files(1);
  return ZVFS_OK;
}

static int zOpen(sqlite3_vfs *vfs, sqlite3_filename name, sqlite3_file *pf,
                 int flags, int *out_flags) {
  (void)vfs;
  zfile *f = (zfile *)pf;
  memset(f, 0, sizeof *f);
  f->real = (sqlite3_file *)((char *)f + ((sizeof(zfile) + 7) & ~(size_t)7));
  int inner_flags = 0;
  int rc = g_base->xOpen(g_base, name, f->real, flags, &inner_flags);
  if (rc != SQLITE_OK) {
    f->base.pMethods = NULL;
    return rc;
  }
  f->base.pMethods = &g_methods;
  if ((flags & SQLITE_OPEN_MAIN_DB) && name) {
    uint8_t magic[ZDB_MAGIC_LEN];
    sqlite3_int64 size = 0;
    int zr = f->real->pMethods->xFileSize(f->real, &size);
    if (zr == SQLITE_OK && size >= ZDB_MAGIC_LEN)
      zr = f->real->pMethods->xRead(f->real, magic, sizeof magic, 0);
    else
      size = 0;
    if (zr == SQLITE_OK && size > 0 && zdb_has_magic(magic, sizeof magic)) {
      int err = attach_shared(f, name, (uint64_t)size);
      if (err) {
        f->real->pMethods->xClose(f->real);
        f->base.pMethods = NULL;
        return map_rc(err);
      }
      /* The base is never written; writes go to the overlay. */
      f->writable = (inner_flags & SQLITE_OPEN_READWRITE) != 0;
    } else {
      register_plain(f, name);
    }
  }
  if (out_flags) *out_flags = inner_flags;
  return SQLITE_OK;
}

static int vDelete(sqlite3_vfs *v, const char *n, int s) {
  (void)v;
  return g_base->xDelete(g_base, n, s);
}
static int vAccess(sqlite3_vfs *v, const char *n, int fl, int *o) {
  (void)v;
  return g_base->xAccess(g_base, n, fl, o);
}
static int vFullPathname(sqlite3_vfs *v, const char *n, int no, char *o) {
  (void)v;
  return g_base->xFullPathname(g_base, n, no, o);
}
static void *vDlOpen(sqlite3_vfs *v, const char *n) {
  (void)v;
  return g_base->xDlOpen(g_base, n);
}
static void vDlError(sqlite3_vfs *v, int n, char *m) {
  (void)v;
  g_base->xDlError(g_base, n, m);
}
static void (*vDlSym(sqlite3_vfs *v, void *p, const char *s))(void) {
  (void)v;
  return g_base->xDlSym(g_base, p, s);
}
static void vDlClose(sqlite3_vfs *v, void *p) {
  (void)v;
  g_base->xDlClose(g_base, p);
}
static int vRandomness(sqlite3_vfs *v, int n, char *o) {
  (void)v;
  return g_base->xRandomness(g_base, n, o);
}
static int vSleep(sqlite3_vfs *v, int us) {
  (void)v;
  return g_base->xSleep(g_base, us);
}
static int vCurrentTime(sqlite3_vfs *v, double *o) {
  (void)v;
  return g_base->xCurrentTime(g_base, o);
}
static int vGetLastError(sqlite3_vfs *v, int n, char *o) {
  (void)v;
  return g_base->xGetLastError ? g_base->xGetLastError(g_base, n, o) : 0;
}
static int vCurrentTimeInt64(sqlite3_vfs *v, sqlite3_int64 *o) {
  (void)v;
  if (g_base->iVersion >= 2 && g_base->xCurrentTimeInt64)
    return g_base->xCurrentTimeInt64(g_base, o);
  double d = 0;
  int rc = g_base->xCurrentTime(g_base, &d);
  *o = (sqlite3_int64)(d * 86400000.0);
  return rc;
}

ZVFS_API int zvfs_is_registered(void) {
  return zplat_atomic_load(&g_registered) != 0;
}

ZVFS_API int sqlite3_otzariazvfs_init(void *db, char **pzErrMsg,
                                      const void *pApi) {
  (void)db;
  (void)pzErrMsg;
  if (zplat_atomic_load(&g_registered)) return SQLITE_OK;
  zplat_lock(&g_mu);
  int rc = SQLITE_OK;
  if (!g_registered) {
    SQLITE_EXTENSION_INIT2((const sqlite3_api_routines *)pApi);
    g_base = sqlite3_vfs_find(NULL);
    if (!g_base) {
      rc = SQLITE_ERROR;
    } else {
      memset(&g_vfs, 0, sizeof g_vfs);
      g_vfs.iVersion = 2;
      g_vfs.szOsFile =
          (int)((sizeof(zfile) + 7) & ~(size_t)7) + g_base->szOsFile;
      g_vfs.mxPathname = g_base->mxPathname;
      g_vfs.zName = ZVFS_VFS_NAME;
      g_vfs.xOpen = zOpen;
      g_vfs.xDelete = vDelete;
      g_vfs.xAccess = vAccess;
      g_vfs.xFullPathname = vFullPathname;
      g_vfs.xDlOpen = vDlOpen;
      g_vfs.xDlError = vDlError;
      g_vfs.xDlSym = vDlSym;
      g_vfs.xDlClose = vDlClose;
      g_vfs.xRandomness = vRandomness;
      g_vfs.xSleep = vSleep;
      g_vfs.xCurrentTime = vCurrentTime;
      g_vfs.xGetLastError = vGetLastError;
      g_vfs.xCurrentTimeInt64 = vCurrentTimeInt64;
      rc = sqlite3_vfs_register(&g_vfs, 0);
      if (rc == SQLITE_OK) zplat_atomic_store(&g_registered, 1);
    }
  }
  zplat_unlock(&g_mu);
  return rc;
}

/* ---- in-use queries (probe, reader and compaction must not open the file:
   closing any fd drops the process's POSIX locks on it) ---- */
static char *full_path(const char *path) {
  int n = g_base->mxPathname + 1;
  char *full = (char *)sqlite3_malloc(n);
  /* unix returns SQLITE_OK_SYMLINK for a path through a symlink */
  if (full &&
      (g_base->xFullPathname(g_base, path, n, full) & 0xff) != SQLITE_OK) {
    sqlite3_free(full);
    full = NULL;
  }
  return full;
}

ZVFS_API int zvfs_in_use(const char *path) {
  if (!path) return 0;
  if (!zvfs_is_registered()) return 0;
  char *full = full_path(path);
  if (!full) return -1;
  int kind = 0;
  zplat_lock(&g_mu);
  for (zdb_file *z = g_files; z && !kind; z = z->next)
    if (strcmp(z->key, full) == 0) kind = 2;
  for (open_path *op = g_plain; op && !kind; op = op->next)
    if (strcmp(op->key, full) == 0) kind = 1;
  zplat_unlock(&g_mu);
  sqlite3_free(full);
  return kind;
}

ZVFS_API int zvfs_state_info(const char *path, zvfs_info *out) {
  if (!path || !out) return ZVFS_ERR_INVALID;
  if (!zvfs_is_registered()) return ZVFS_ERR_NOT_ZDB;
  char *full = full_path(path);
  if (!full) return ZVFS_ERR_NOMEM;
  int rc = ZVFS_ERR_NOT_ZDB;
  zplat_lock(&g_mu);
  for (zdb_file *z = g_files; z; z = z->next) {
    if (strcmp(z->key, full) == 0) {
      zdb_fill_info(z, out);
      if (z->ovl) out->logical_size = zovl_logical_size(z->ovl);
      rc = ZVFS_OK;
      break;
    }
  }
  zplat_unlock(&g_mu);
  sqlite3_free(full);
  return rc;
}

ZVFS_API int zvfs_set_default(int on) {
  if (!zvfs_is_registered()) return ZVFS_ERR_INVALID;
  zplat_lock(&g_mu);
  int rc = sqlite3_vfs_register(on ? &g_vfs : g_base, 1);
  zplat_unlock(&g_mu);
  return rc == SQLITE_OK ? ZVFS_OK : ZVFS_ERR_INVALID;
}

/* ---- compaction swap ---- */
ZVFS_API int zvfs_compact_swap(const char *path, const char *new_path) {
  if (!path || !new_path || strlen(path) > 4000) return ZVFS_ERR_INVALID;
  int u = zvfs_in_use(path);
  if (u) return u < 0 ? ZVFS_ERR_NOMEM : ZVFS_ERR_BUSY;
  if (zvfs_sidecars_busy(path)) return ZVFS_ERR_BUSY;
  zvfs_reader *cur = NULL, *nw = NULL;
  int rc = zvfs_reader_open(path, &cur);
  if (!rc) rc = zvfs_reader_open(new_path, &nw);
  if (!rc) {
    zvfs_info ci, ni;
    zvfs_overlay_info co;
    zvfs_reader_info(cur, &ci);
    zvfs_reader_info(nw, &ni);
    zvfs_reader_overlay_info(cur, &co);
    uint8_t zero[16] = {0};
    const uint8_t *ovl_uuid = co.present ? co.overlay_uuid : zero;
    uint64_t seq = co.present ? co.seq : 0;
    /* the new base must contain exactly what path serves right now */
    if (memcmp(ni.derived_from_uuid, ci.file_uuid, 16) != 0 ||
        memcmp(ni.includes_overlay_uuid, ovl_uuid, 16) != 0 ||
        ni.includes_overlay_seq != seq || ni.logical_size != ci.logical_size)
      rc = ZVFS_ERR_BUSY;
  }
  zvfs_reader_close(cur);
  zvfs_reader_close(nw);
  if (rc) return rc;
  rc = zplat_rename_durable(new_path, path);
  if (rc) return rc;
  /* Until this delete lands the old sidecar is obsolete by lineage. */
  char ov[4096];
  size_t n = strlen(path);
  memcpy(ov, path, n);
  memcpy(ov + n, ZDB_OVERLAY_SUFFIX, sizeof ZDB_OVERLAY_SUFFIX);
  return zplat_delete_durable(ov);
}
