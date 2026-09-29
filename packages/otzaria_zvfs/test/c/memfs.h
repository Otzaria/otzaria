/* In-memory VFS that simulates power loss. Registered as the default VFS
   before zvfs, so zvfs (and its overlay sidecar) sit on top of it.

   Every file keeps its durable image (as of the last xSync) and the list of
   writes/truncates since. A "crash" rebuilds each file from the durable image
   plus a policy-chosen subset of those operations. A fault point makes the
   N-th write or sync fail, after which every mutation fails (the process is
   gone); reads keep working so SQLite can unwind. */
#ifndef ZVFS_MEMFS_H
#define ZVFS_MEMFS_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sqlite3.h"

enum { MF_OP_WRITE, MF_OP_TRUNC };
enum {
  MF_LOSE_UNSYNCED, /* only synced data survives */
  MF_KEEP_SUBSET,   /* a random subset of unsynced ops survives (reorder) */
  MF_TEAR_LAST,     /* an ordered prefix survives, the next op is torn */
  MF_KEEP_ALL,      /* process kill: everything issued survives */
  MF_POLICIES
};

typedef struct mf_op {
  int kind;
  int64_t off;
  int len;
  uint8_t *data;
} mf_op;

typedef struct mf_node {
  char name[512];
  uint8_t *cur;
  int64_t cur_len, cur_cap;
  uint8_t *dur;
  int64_t dur_len;
  mf_op *ops;
  int nops, capops;
  int opens;
  /* locks */
  int shared, reserved_by, pending_by, excl_by;
  /* shm */
  uint8_t *shm[64];
  int shm_n, shm_sz, shm_users;
  int shm_shared[8], shm_excl[8];
  struct mf_node *next;
} mf_node;

typedef struct mf_file {
  sqlite3_file base;
  mf_node *n;
  int lock;
  int id;
  int shm_own_shared, shm_own_excl, shm_mapped;
} mf_file;

static struct {
  sqlite3_vfs vfs;
  sqlite3_vfs *os;
  mf_node *nodes;
  int next_id;
  /* fault injection */
  int64_t writes, syncs;
  int64_t fail_write, fail_sync; /* 1-based; 0 = off */
  int crashed;
  uint64_t rng;
  int64_t max_file;
} MF;

static uint64_t mf_rand(void) {
  MF.rng ^= MF.rng << 13;
  MF.rng ^= MF.rng >> 7;
  MF.rng ^= MF.rng << 17;
  return MF.rng;
}

static mf_node *mf_find(const char *name) {
  for (mf_node *n = MF.nodes; n; n = n->next)
    if (strcmp(n->name, name) == 0) return n;
  return NULL;
}

static mf_node *mf_create(const char *name) {
  mf_node *n = (mf_node *)calloc(1, sizeof *n);
  snprintf(n->name, sizeof n->name, "%s", name);
  n->next = MF.nodes;
  MF.nodes = n;
  return n;
}

static void mf_reserve(uint8_t **p, int64_t *cap, int64_t need) {
  if (need <= *cap) return;
  int64_t c = *cap ? *cap : 4096;
  while (c < need) c *= 2;
  *p = (uint8_t *)realloc(*p, (size_t)c);
  memset(*p + *cap, 0, (size_t)(c - *cap));
  *cap = c;
}

static void mf_apply(uint8_t **buf, int64_t *len, int64_t *cap, const mf_op *op,
                     int torn) {
  if (op->kind == MF_OP_TRUNC) {
    if (op->off > *len) {
      mf_reserve(buf, cap, op->off);
      memset(*buf + *len, 0, (size_t)(op->off - *len));
    }
    *len = op->off;
    return;
  }
  int64_t end = op->off + op->len;
  mf_reserve(buf, cap, end);
  if (end > *len) {
    if (op->off > *len) memset(*buf + *len, 0, (size_t)(op->off - *len));
    *len = end;
  }
  if (!torn) {
    memcpy(*buf + op->off, op->data, (size_t)op->len);
    return;
  }
  /* torn: each 512-byte sector independently old, new or garbage */
  for (int64_t s = 0; s < op->len; s += 512) {
    int64_t k = op->len - s < 512 ? op->len - s : 512;
    uint64_t r = mf_rand() % 4;
    if (r == 0) memcpy(*buf + op->off + s, op->data + s, (size_t)k);
    else if (r == 1) {
      int64_t cut = (int64_t)(mf_rand() % (uint64_t)k);
      memcpy(*buf + op->off + s, op->data + s, (size_t)cut);
    } else if (r == 2) {
      for (int64_t i = 0; i < k; i++) (*buf)[op->off + s + i] = (uint8_t)mf_rand();
    }
  }
}

static void mf_clear_ops(mf_node *n) {
  for (int i = 0; i < n->nops; i++) free(n->ops[i].data);
  n->nops = 0;
}

static void mf_push_op(mf_node *n, int kind, int64_t off, const void *p, int len) {
  if (n->nops == n->capops) {
    n->capops = n->capops ? n->capops * 2 : 64;
    n->ops = (mf_op *)realloc(n->ops, (size_t)n->capops * sizeof(mf_op));
  }
  mf_op *op = &n->ops[n->nops++];
  op->kind = kind;
  op->off = off;
  op->len = len;
  op->data = NULL;
  if (len) {
    op->data = (uint8_t *)malloc((size_t)len);
    memcpy(op->data, p, (size_t)len);
  }
}

/* ---- io methods ---- */
static int mfClose(sqlite3_file *pf) {
  mf_file *f = (mf_file *)pf;
  if (f->n) f->n->opens--;
  f->n = NULL;
  return SQLITE_OK;
}

static int mfRead(sqlite3_file *pf, void *buf, int amt, sqlite3_int64 off) {
  mf_node *n = ((mf_file *)pf)->n;
  if (off >= n->cur_len) {
    memset(buf, 0, (size_t)amt);
    return SQLITE_IOERR_SHORT_READ;
  }
  int64_t have = n->cur_len - off;
  if (have >= amt) {
    memcpy(buf, n->cur + off, (size_t)amt);
    return SQLITE_OK;
  }
  memcpy(buf, n->cur + off, (size_t)have);
  memset((uint8_t *)buf + have, 0, (size_t)(amt - have));
  return SQLITE_IOERR_SHORT_READ;
}

static int mf_fault_write(void) {
  if (MF.crashed) return 1;
  MF.writes++;
  if (MF.fail_write && MF.writes >= MF.fail_write) {
    MF.crashed = 1;
    return 1;
  }
  return 0;
}

static int mfWrite(sqlite3_file *pf, const void *buf, int amt, sqlite3_int64 off) {
  mf_node *n = ((mf_file *)pf)->n;
  if (mf_fault_write()) return SQLITE_IOERR_WRITE;
  if (MF.max_file && off + amt > MF.max_file) return SQLITE_FULL;
  mf_op op = {MF_OP_WRITE, off, amt, (uint8_t *)buf};
  mf_apply(&n->cur, &n->cur_len, &n->cur_cap, &op, 0);
  mf_push_op(n, MF_OP_WRITE, off, buf, amt);
  return SQLITE_OK;
}

static int mfTruncate(sqlite3_file *pf, sqlite3_int64 size) {
  mf_node *n = ((mf_file *)pf)->n;
  if (mf_fault_write()) return SQLITE_IOERR_TRUNCATE;
  mf_op op = {MF_OP_TRUNC, size, 0, NULL};
  mf_apply(&n->cur, &n->cur_len, &n->cur_cap, &op, 0);
  mf_push_op(n, MF_OP_TRUNC, size, NULL, 0);
  return SQLITE_OK;
}

static int mfSync(sqlite3_file *pf, int flags) {
  (void)flags;
  mf_node *n = ((mf_file *)pf)->n;
  if (MF.crashed) return SQLITE_IOERR_FSYNC;
  MF.syncs++;
  if (MF.fail_sync && MF.syncs >= MF.fail_sync) {
    MF.crashed = 1;
    return SQLITE_IOERR_FSYNC;
  }
  free(n->dur);
  n->dur = (uint8_t *)malloc((size_t)(n->cur_len ? n->cur_len : 1));
  memcpy(n->dur, n->cur, (size_t)n->cur_len);
  n->dur_len = n->cur_len;
  mf_clear_ops(n);
  return SQLITE_OK;
}

static int mfFileSize(sqlite3_file *pf, sqlite3_int64 *size) {
  *size = ((mf_file *)pf)->n->cur_len;
  return SQLITE_OK;
}

static int mfLock(sqlite3_file *pf, int l) {
  mf_file *f = (mf_file *)pf;
  mf_node *n = f->n;
  if (l <= f->lock) return SQLITE_OK;
  if (l == SQLITE_LOCK_SHARED) {
    if (n->pending_by || n->excl_by) return SQLITE_BUSY;
    n->shared++;
  } else if (l == SQLITE_LOCK_RESERVED) {
    if (n->reserved_by && n->reserved_by != f->id) return SQLITE_BUSY;
    n->reserved_by = f->id;
  } else {
    if (n->pending_by && n->pending_by != f->id) return SQLITE_BUSY;
    n->pending_by = f->id;
    if (n->shared > 1) return SQLITE_BUSY;
    n->excl_by = f->id;
    l = SQLITE_LOCK_EXCLUSIVE;
  }
  f->lock = l;
  return SQLITE_OK;
}

static int mfUnlock(sqlite3_file *pf, int l) {
  mf_file *f = (mf_file *)pf;
  mf_node *n = f->n;
  if (f->lock <= l) return SQLITE_OK;
  if (n->excl_by == f->id) n->excl_by = 0;
  if (n->pending_by == f->id) n->pending_by = 0;
  if (n->reserved_by == f->id) n->reserved_by = 0;
  if (l == SQLITE_LOCK_NONE && f->lock >= SQLITE_LOCK_SHARED) n->shared--;
  f->lock = l;
  return SQLITE_OK;
}

static int mfCheckReserved(sqlite3_file *pf, int *out) {
  mf_node *n = ((mf_file *)pf)->n;
  *out = n->reserved_by || n->pending_by || n->excl_by;
  return SQLITE_OK;
}

static int mfFileControl(sqlite3_file *pf, int op, void *arg) {
  (void)pf;
  (void)op;
  (void)arg;
  return SQLITE_NOTFOUND;
}
static int mfSectorSize(sqlite3_file *pf) {
  (void)pf;
  return 512;
}
static int mfDeviceChar(sqlite3_file *pf) {
  (void)pf;
  return 0; /* no atomic/safe-append promises: SQLite must be fully careful */
}

static int mfShmMap(sqlite3_file *pf, int pg, int sz, int ext, void volatile **pp) {
  mf_node *n = ((mf_file *)pf)->n;
  *pp = NULL;
  if (pg >= 64) return SQLITE_IOERR_SHMMAP;
  if (pg >= n->shm_n) {
    if (!ext) return SQLITE_OK;
    while (n->shm_n <= pg) n->shm[n->shm_n++] = (uint8_t *)calloc(1, (size_t)sz);
  }
  n->shm_sz = sz;
  if (!((mf_file *)pf)->shm_mapped) {
    ((mf_file *)pf)->shm_mapped = 1;
    n->shm_users++;
  }
  *pp = n->shm[pg];
  return SQLITE_OK;
}

static int mfShmLock(sqlite3_file *pf, int off, int cnt, int flags) {
  mf_file *f = (mf_file *)pf;
  mf_node *n = f->n;
  for (int i = off; i < off + cnt; i++) {
    int bit = 1 << i;
    if (flags & SQLITE_SHM_UNLOCK) continue;
    if (flags & SQLITE_SHM_SHARED) {
      if (f->shm_own_shared & bit) continue;
      if (n->shm_excl[i] && !(f->shm_own_excl & bit)) return SQLITE_BUSY;
    } else {
      if (f->shm_own_excl & bit) continue;
      int others = n->shm_shared[i] - ((f->shm_own_shared & bit) ? 1 : 0);
      if (n->shm_excl[i] || others > 0) return SQLITE_BUSY;
    }
  }
  for (int i = off; i < off + cnt; i++) {
    int bit = 1 << i;
    if (flags & SQLITE_SHM_UNLOCK) {
      if (f->shm_own_shared & bit) n->shm_shared[i]--;
      if (f->shm_own_excl & bit) n->shm_excl[i] = 0;
      f->shm_own_shared &= ~bit;
      f->shm_own_excl &= ~bit;
    } else if (flags & SQLITE_SHM_SHARED) {
      if (!(f->shm_own_shared & bit)) n->shm_shared[i]++;
      f->shm_own_shared |= bit;
    } else {
      n->shm_excl[i] = 1;
      f->shm_own_excl |= bit;
    }
  }
  return SQLITE_OK;
}

static void mfShmBarrier(sqlite3_file *pf) { (void)pf; }

/* Like the DMS lock of the OS VFSes: the last user resets the wal-index. */
static int mfShmUnmap(sqlite3_file *pf, int del) {
  mf_file *f = (mf_file *)pf;
  mf_node *n = f->n;
  (void)del;
  mfShmLock(pf, 0, 8, SQLITE_SHM_UNLOCK | SQLITE_SHM_SHARED);
  if (f->shm_mapped) {
    f->shm_mapped = 0;
    if (--n->shm_users == 0) {
      for (int i = 0; i < n->shm_n; i++) free(n->shm[i]);
      n->shm_n = 0;
    }
  }
  return SQLITE_OK;
}

static const sqlite3_io_methods mf_methods = {
    2,          mfClose,       mfRead,       mfWrite,      mfTruncate,
    mfSync,     mfFileSize,    mfLock,       mfUnlock,     mfCheckReserved,
    mfFileControl, mfSectorSize, mfDeviceChar, mfShmMap,   mfShmLock,
    mfShmBarrier, mfShmUnmap,  NULL,         NULL};

static int mfOpen(sqlite3_vfs *v, sqlite3_filename name, sqlite3_file *pf,
                  int flags, int *out) {
  (void)v;
  mf_file *f = (mf_file *)pf;
  memset(f, 0, sizeof *f);
  char tmp[64];
  if (!name) {
    snprintf(tmp, sizeof tmp, "/tmp/mf-%d", ++MF.next_id);
    name = tmp;
  }
  mf_node *n = mf_find(name);
  if (!n) {
    if (!(flags & SQLITE_OPEN_CREATE)) return SQLITE_CANTOPEN;
    n = mf_create(name);
  }
  n->opens++;
  f->n = n;
  f->id = ++MF.next_id;
  f->base.pMethods = &mf_methods;
  if (out) *out = flags;
  return SQLITE_OK;
}

static int mfDelete(sqlite3_vfs *v, const char *name, int dirsync) {
  (void)v;
  (void)dirsync;
  if (MF.crashed) return SQLITE_IOERR_DELETE;
  mf_node **pp = &MF.nodes;
  while (*pp && strcmp((*pp)->name, name) != 0) pp = &(*pp)->next;
  if (!*pp) return SQLITE_IOERR_DELETE_NOENT;
  mf_node *n = *pp;
  /* an open handle keeps the node alive in real OSes; tests never do that */
  *pp = n->next;
  mf_clear_ops(n);
  free(n->ops);
  free(n->cur);
  free(n->dur);
  for (int i = 0; i < n->shm_n; i++) free(n->shm[i]);
  free(n);
  return SQLITE_OK;
}

static int mfAccess(sqlite3_vfs *v, const char *name, int flags, int *out) {
  (void)v;
  (void)flags;
  *out = mf_find(name) != NULL;
  return SQLITE_OK;
}

static int mfFullPathname(sqlite3_vfs *v, const char *name, int n, char *out) {
  (void)v;
  snprintf(out, (size_t)n, "%s", name);
  return SQLITE_OK;
}
static void *mfDlOpen(sqlite3_vfs *v, const char *n) {
  (void)v;
  (void)n;
  return NULL;
}
static void mfDlError(sqlite3_vfs *v, int n, char *m) {
  (void)v;
  if (n) m[0] = 0;
}
static void (*mfDlSym(sqlite3_vfs *v, void *p, const char *s))(void) {
  (void)v;
  (void)p;
  (void)s;
  return NULL;
}
static void mfDlClose(sqlite3_vfs *v, void *p) {
  (void)v;
  (void)p;
}
static int mfRandomness(sqlite3_vfs *v, int n, char *out) {
  (void)v;
  for (int i = 0; i < n; i++) out[i] = (char)mf_rand();
  return n;
}
static int mfSleep(sqlite3_vfs *v, int us) {
  (void)v;
  return us;
}
static int mfCurrentTime(sqlite3_vfs *v, double *t) {
  (void)v;
  *t = 2461000.5;
  return SQLITE_OK;
}

static void memfs_register(void) {
  memset(&MF, 0, sizeof MF);
  MF.rng = 0x9E3779B97F4A7C15ull;
  MF.vfs.iVersion = 1;
  MF.vfs.szOsFile = sizeof(mf_file);
  MF.vfs.mxPathname = 511;
  MF.vfs.zName = "memfs";
  MF.vfs.xOpen = mfOpen;
  MF.vfs.xDelete = mfDelete;
  MF.vfs.xAccess = mfAccess;
  MF.vfs.xFullPathname = mfFullPathname;
  MF.vfs.xDlOpen = mfDlOpen;
  MF.vfs.xDlError = mfDlError;
  MF.vfs.xDlSym = mfDlSym;
  MF.vfs.xDlClose = mfDlClose;
  MF.vfs.xRandomness = mfRandomness;
  MF.vfs.xSleep = mfSleep;
  MF.vfs.xCurrentTime = mfCurrentTime;
  sqlite3_vfs_register(&MF.vfs, 1);
}

/* Puts a durable file (e.g. a .zdb made on disk) into the filesystem. */
static void memfs_put(const char *name, const uint8_t *data, int64_t len) {
  mf_node *n = mf_find(name);
  if (!n) n = mf_create(name);
  mf_clear_ops(n);
  n->cur_len = 0;
  mf_reserve(&n->cur, &n->cur_cap, len ? len : 1);
  memcpy(n->cur, data, (size_t)len);
  n->cur_len = len;
  free(n->dur);
  n->dur = (uint8_t *)malloc((size_t)(len ? len : 1));
  memcpy(n->dur, data, (size_t)len);
  n->dur_len = len;
}

static int64_t memfs_get(const char *name, uint8_t **data) {
  mf_node *n = mf_find(name);
  if (!n) return -1;
  *data = (uint8_t *)malloc((size_t)(n->cur_len ? n->cur_len : 1));
  memcpy(*data, n->cur, (size_t)n->cur_len);
  return n->cur_len;
}

static int memfs_exists(const char *name) { return mf_find(name) != NULL; }

static void memfs_remove(const char *name) { mfDelete(&MF.vfs, name, 0); }

static void memfs_remove_all(void) {
  while (MF.nodes) memfs_remove(MF.nodes->name);
}

static void memfs_sync_all(void) {
  for (mf_node *n = MF.nodes; n; n = n->next) {
    free(n->dur);
    n->dur = (uint8_t *)malloc((size_t)(n->cur_len ? n->cur_len : 1));
    memcpy(n->dur, n->cur, (size_t)n->cur_len);
    n->dur_len = n->cur_len;
    mf_clear_ops(n);
  }
}

/* Power loss: every file becomes durable image + policy(unsynced ops). */
static void memfs_crash(int policy) {
  for (mf_node *n = MF.nodes; n; n = n->next) {
    uint8_t *buf = NULL;
    int64_t len = 0, cap = 0;
    mf_reserve(&buf, &cap, n->dur_len ? n->dur_len : 1);
    memcpy(buf, n->dur, (size_t)n->dur_len);
    len = n->dur_len;
    int keep = n->nops;
    int torn = -1;
    if (policy == MF_LOSE_UNSYNCED) keep = 0;
    if (policy == MF_TEAR_LAST && n->nops) {
      keep = (int)(mf_rand() % (uint64_t)(n->nops + 1));
      if (keep < n->nops) torn = keep;
    }
    for (int i = 0; i < n->nops; i++) {
      int apply = i < keep;
      if (policy == MF_KEEP_SUBSET) apply = mf_rand() & 1;
      if (apply) mf_apply(&buf, &len, &cap, &n->ops[i], 0);
      else if (i == torn) mf_apply(&buf, &len, &cap, &n->ops[i], 1);
    }
    free(n->cur);
    n->cur = buf;
    n->cur_len = len;
    n->cur_cap = cap;
    free(n->dur);
    n->dur = (uint8_t *)malloc((size_t)(len ? len : 1));
    memcpy(n->dur, buf, (size_t)len);
    n->dur_len = len;
    mf_clear_ops(n);
    for (int i = 0; i < n->shm_n; i++) free(n->shm[i]);
    n->shm_n = 0;
    n->shm_users = 0;
    memset(n->shm_shared, 0, sizeof n->shm_shared);
    memset(n->shm_excl, 0, sizeof n->shm_excl);
    n->shared = n->reserved_by = n->pending_by = n->excl_by = 0;
  }
  MF.crashed = 0;
  MF.fail_write = MF.fail_sync = 0;
}

/* Snapshot/restore of durable images, for repeatable iterations. */
typedef struct mf_snap {
  int n;
  char names[16][512];
  uint8_t *data[16];
  int64_t len[16];
} mf_snap;

static void memfs_snapshot(mf_snap *s) {
  memset(s, 0, sizeof *s);
  for (mf_node *n = MF.nodes; n && s->n < 16; n = n->next) {
    snprintf(s->names[s->n], 512, "%s", n->name);
    s->len[s->n] = n->cur_len;
    s->data[s->n] = (uint8_t *)malloc((size_t)(n->cur_len ? n->cur_len : 1));
    memcpy(s->data[s->n], n->cur, (size_t)n->cur_len);
    s->n++;
  }
}

static void memfs_restore(const mf_snap *s) {
  memfs_remove_all();
  for (int i = 0; i < s->n; i++) memfs_put(s->names[i], s->data[i], s->len[i]);
  MF.crashed = 0;
  MF.fail_write = MF.fail_sync = 0;
}

static void memfs_snap_free(mf_snap *s) {
  for (int i = 0; i < s->n; i++) free(s->data[i]);
  s->n = 0;
}

#endif
