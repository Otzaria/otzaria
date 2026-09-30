/* Write path: overlay codec and recovery, SQL equivalence against plain
   SQLite, compaction, and concurrent WAL readers. */
#include "test_sql.h"

#if !defined(_WIN32)
#include <sched.h>
#include <sys/stat.h>
#endif

/* ================= overlay codec on an in-memory sidecar ================= */
typedef struct memovl {
  uint8_t *p;
  size_t len, cap;
  int exists;
  int syncs;
  int fail_writes; /* >0: writes fail after this many more */
} memovl;

typedef struct { memovl *m; } mo_handle;

/* memovl reallocs on growth; real files do not, so serialize the fake. */
static zplat_mutex g_mo_mu = ZPLAT_MUTEX_INIT;

static int mo_read(void *h, void *buf, size_t n, uint64_t off) {
  memovl *m = ((mo_handle *)h)->m;
  zplat_lock(&g_mo_mu);
  size_t have = off < m->len ? m->len - (size_t)off : 0;
  size_t k = have < n ? have : n;
  if (k) memcpy(buf, m->p + off, k);
  zplat_unlock(&g_mo_mu);
  if (k == n) return ZVFS_OK;
  memset((uint8_t *)buf + k, 0, n - k);
  return ZVFS_ERR_SHORT_READ;
}
static void mo_grow(memovl *m, size_t need) {
  if (need <= m->cap) return;
  size_t c = m->cap ? m->cap : 4096;
  while (c < need) c *= 2;
  m->p = (uint8_t *)realloc(m->p, c);
  memset(m->p + m->cap, 0, c - m->cap);
  m->cap = c;
}
static int mo_write(void *h, const void *buf, size_t n, uint64_t off) {
  memovl *m = ((mo_handle *)h)->m;
  if (m->fail_writes && --m->fail_writes == 0) return ZVFS_ERR_IO;
  zplat_lock(&g_mo_mu);
  mo_grow(m, (size_t)off + n);
  if (off > m->len) memset(m->p + m->len, 0, (size_t)off - m->len);
  memcpy(m->p + off, buf, n);
  if (off + n > m->len) m->len = (size_t)off + n;
  zplat_unlock(&g_mo_mu);
  return ZVFS_OK;
}
static int mo_truncate(void *h, uint64_t size) {
  memovl *m = ((mo_handle *)h)->m;
  zplat_lock(&g_mo_mu);
  mo_grow(m, (size_t)size);
  if (size > m->len) memset(m->p + m->len, 0, (size_t)size - m->len);
  m->len = (size_t)size;
  zplat_unlock(&g_mo_mu);
  return ZVFS_OK;
}
static int mo_sync(void *h, int flags) {
  (void)flags;
  ((mo_handle *)h)->m->syncs++;
  return ZVFS_OK;
}
static int mo_size(void *h, uint64_t *out) {
  zplat_lock(&g_mo_mu);
  *out = ((mo_handle *)h)->m->len;
  zplat_unlock(&g_mo_mu);
  return ZVFS_OK;
}
static void mo_close(void *h) { free(h); }
static int mo_open(void *env, int create, void **out) {
  memovl *m = (memovl *)env;
  *out = NULL;
  if (!m->exists && !create) return ZVFS_OK;
  m->exists = 1;
  mo_handle *h = (mo_handle *)malloc(sizeof *h);
  h->m = m;
  *out = h;
  return ZVFS_OK;
}
static const zovl_ops k_mo_ops = {mo_read, mo_write, mo_truncate, mo_sync,
                                  mo_size, mo_close, mo_open,     NULL};

typedef struct membase {
  uint8_t *p;
  size_t len;
} membase;

static int mb_rd(void *ctx, void *buf, size_t n, uint64_t off) {
  membase *b = (membase *)ctx;
  if (off + n > b->len) return ZVFS_ERR_SHORT_READ;
  memcpy(buf, b->p + off, n);
  return ZVFS_OK;
}

static membase g_mb;
static uint32_t g_ps;
static uint64_t g_base_logical;
static uint8_t *g_base_plain;

static void build_membase(uint32_t ps) {
  const char *plain = tmp_path("ovl_base.db");
  const char *zdb = tmp_path("ovl_base.zdb");
  ts_remove_all(plain);
  sqlite3 *db = ts_open(plain, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  char sql[64];
  snprintf(sql, sizeof sql, "PRAGMA page_size=%u", ps);
  ts_must(db, sql);
  ts_make_base(db, 20, 800);
  sqlite3_close(db);
  size_t n;
  free(g_base_plain);
  CHECK_EQ(read_file(plain, &g_base_plain, &n), 0);
  CHECK_EQ(ts_convert(plain, zdb), 0);
  free(g_mb.p);
  CHECK_EQ(read_file(zdb, &g_mb.p, &g_mb.len), 0);
  g_ps = ps;
  g_base_logical = n;
  remove(plain);
  ts_remove_all(zdb);
}

static zdb_file *load_base(void) {
  zdb_file *f = NULL;
  CHECK_EQ(zdb_file_load(mb_rd, &g_mb, g_mb.len, &f), 0);
  return f;
}

/* Opens an overlay over a fresh base state; returns the zovl rc. */
static int ovl_open(memovl *m, zdb_file **bf, zovl **o) {
  *bf = load_base();
  int rc = zovl_create(&k_mo_ops, m, *bf, o);
  if (rc) {
    zdb_file_free(*bf);
    *bf = NULL;
    *o = NULL;
  } else {
    (*bf)->ovl = *o;
  }
  return rc;
}

static void ovl_close(zdb_file *bf) { zdb_file_free(bf); }

/* A reference image of the logical file. */
typedef struct image {
  uint8_t *p;
  uint64_t len;
} image;

static void img_from_base(image *im) {
  im->p = (uint8_t *)malloc((size_t)g_base_logical);
  memcpy(im->p, g_base_plain, (size_t)g_base_logical);
  im->len = g_base_logical;
}
static void img_copy(image *dst, const image *src) {
  dst->p = (uint8_t *)malloc((size_t)(src->len ? src->len : 1));
  memcpy(dst->p, src->p, (size_t)src->len);
  dst->len = src->len;
}
static void img_write(image *im, const uint8_t *b, uint64_t n, uint64_t off) {
  if (off + n > im->len) {
    im->p = (uint8_t *)realloc(im->p, (size_t)(off + n));
    memset(im->p + im->len, 0, (size_t)(off + n - im->len));
    im->len = off + n;
  }
  memcpy(im->p + off, b, (size_t)n);
}
static void img_truncate(image *im, uint64_t size) {
  if (size > im->len) {
    im->p = (uint8_t *)realloc(im->p, (size_t)size);
    memset(im->p + im->len, 0, (size_t)(size - im->len));
  }
  im->len = size;
}

static int ovl_matches(zovl *o, const image *im) {
  if (zovl_logical_size(o) != im->len) return 0;
  uint8_t *buf = (uint8_t *)malloc((size_t)im->len + 1);
  int rc = zovl_read(o, mb_rd, &g_mb, buf, im->len, 0);
  int ok = rc == ZVFS_OK && memcmp(buf, im->p, (size_t)im->len) == 0;
  /* one byte past EOF reads as a zero-filled short read */
  uint8_t z = 0xAA;
  ok = ok && zovl_read(o, mb_rd, &g_mb, &z, 1, im->len) == ZVFS_ERR_SHORT_READ &&
       z == 0;
  free(buf);
  return ok;
}

typedef struct history {
  image st[256];
  uint64_t end[256]; /* committed_end after commit i; st[0] = base */
  int n;
} history;

static void hist_push(history *h, const image *im, uint64_t end) {
  img_copy(&h->st[h->n], im);
  h->end[h->n] = end;
  h->n++;
}
static void hist_free(history *h) {
  for (int i = 0; i < h->n; i++) free(h->st[i].p);
  h->n = 0;
}

static void push_if_committed(history *h, zovl *o, const image *im) {
  zovl_info oi;
  zovl_get_info(o, &oi);
  if (oi.seq + 1 > (uint64_t)h->n && h->n < 256) hist_push(h, im, oi.committed_end);
}

/* Random writes, partial writes, growth, truncates, duplicate pages. */
static void random_session(memovl *m, history *h, int commits, uint64_t seed) {
  g_rng = seed;
  zdb_file *bf;
  zovl *o;
  CHECK_EQ(ovl_open(m, &bf, &o), 0);
  image im;
  img_from_base(&im);
  hist_push(h, &im, 0);
  uint8_t *buf = (uint8_t *)malloc(g_ps * 3);
  for (int c = 0; c < commits; c++) {
    int ops = 1 + (int)(rnd() % 6);
    for (int k = 0; k < ops; k++) {
      int what = (int)(rnd() % 10);
      uint64_t pages = (im.len + g_ps - 1) / g_ps;
      if (what < 6) {
        uint64_t pg = rnd() % (pages + 3);
        uint32_t n = what == 0 ? 1 + (uint32_t)(rnd() % (g_ps * 2)) : g_ps;
        uint64_t off = what == 0 ? pg * g_ps + rnd() % g_ps : pg * g_ps;
        for (uint32_t i = 0; i < n; i++) buf[i] = (uint8_t)(rnd() >> 13);
        if (rnd() % 3 == 0) memset(buf, 0, n / 2); /* compressible halves */
        CHECK_EQ(zovl_write(o, mb_rd, &g_mb, buf, n, off), 0);
        img_write(&im, buf, n, off);
        if (rnd() % 4 == 0) { /* duplicate page in the same batch */
          buf[0] ^= 0x5A;
          CHECK_EQ(zovl_write(o, mb_rd, &g_mb, buf, n, off), 0);
          img_write(&im, buf, n, off);
        }
      } else if (what < 8) {
        uint64_t size = im.len > g_ps ? im.len - rnd() % (im.len / 2) : im.len;
        if (rnd() % 2) size -= size % g_ps; /* page-aligned or partial */
        CHECK_EQ(zovl_truncate(o, mb_rd, &g_mb, size), 0);
        img_truncate(&im, size);
      } else {
        uint64_t size = im.len + g_ps * (1 + rnd() % 4) + (rnd() % 2 ? 100 : 0);
        CHECK_EQ(zovl_truncate(o, mb_rd, &g_mb, size), 0);
        img_truncate(&im, size);
      }
      push_if_committed(h, o, &im); /* a truncate commits at once */
    }
    CHECK_EQ(zovl_commit(o, c % 2 ? 2 : 0), 0);
    CHECK(ovl_matches(o, &im));
    push_if_committed(h, o, &im);
  }
  /* an unsealed tail is dropped on reopen */
  for (uint32_t i = 0; i < g_ps; i++) buf[i] = (uint8_t)i;
  CHECK_EQ(zovl_write(o, mb_rd, &g_mb, buf, g_ps, 0), 0);
  free(buf);
  free(im.p);
  ovl_close(bf);
}

/* Expected state for a sidecar holding the first `len` bytes (or damaged
   at `bad`): the last commit that ends at or before the cut. */
static int expected_state(const history *h, uint64_t cut) {
  int s = 0;
  for (int i = 1; i < h->n; i++)
    if (h->end[i] <= cut) s = i;
  return s;
}

/* 1 = every offset; sanitizer runs sample (ZVFS_TORN_STRIDE). */
static size_t torn_stride(void) {
  const char *e = getenv("ZVFS_TORN_STRIDE");
  int v = e ? atoi(e) : 1;
  return v < 1 ? 1 : (size_t)v;
}

static void test_ovl_roundtrip_and_torn(uint32_t ps) {
  build_membase(ps);
  memovl m;
  memset(&m, 0, sizeof m);
  history h;
  memset(&h, 0, sizeof h);
  random_session(&m, &h, 12, 0xC0FFEE + ps);
  uint8_t *good = (uint8_t *)malloc(m.len);
  memcpy(good, m.p, m.len);
  size_t glen = m.len;

  /* reopen: the last commit's state */
  zdb_file *bf;
  zovl *o;
  CHECK_EQ(ovl_open(&m, &bf, &o), 0);
  CHECK(ovl_matches(o, &h.st[h.n - 1]));
  ovl_close(bf);

  /* torn at every byte offset */
  int bad = 0;
  const size_t stride = torn_stride();
  for (size_t cut = 0; cut <= glen; cut += stride) {
    memovl t;
    memset(&t, 0, sizeof t);
    t.exists = 1;
    mo_grow(&t, glen);
    memcpy(t.p, good, cut);
    t.len = cut;
    int rc = ovl_open(&t, &bf, &o);
    int want = cut <= ZOVL_HEADER_SIZE ? 0 : expected_state(&h, cut);
    if (rc || !ovl_matches(o, &h.st[want])) {
      if (bad++ < 3) fprintf(stderr, "torn cut=%zu rc=%d want=%d\n", cut, rc, want);
    }
    if (!rc) {
      /* the next writer drops the torn tail and appends cleanly */
      if (cut % 97 == 0) {
        uint8_t pg[65536];
        memset(pg, (int)cut, sizeof pg);
        CHECK_EQ(zovl_write(o, mb_rd, &g_mb, pg, ps, 0), 0);
        CHECK_EQ(zovl_commit(o, 2), 0);
        image im;
        img_copy(&im, &h.st[want]);
        img_write(&im, pg, ps, 0);
        ovl_close(bf);
        CHECK_EQ(ovl_open(&t, &bf, &o), 0);
        CHECK(ovl_matches(o, &im));
        free(im.p);
      }
      ovl_close(bf);
    }
    free(t.p);
  }
  CHECK_EQ(bad, 0);

  /* one flipped bit at every offset: header -> refused, else a prefix */
  int flips = 0, refused = 0;
  for (size_t pos = 0; pos < glen; pos += pos < ZOVL_HEADER_SIZE ? 1 : stride) {
    memovl t;
    memset(&t, 0, sizeof t);
    t.exists = 1;
    mo_grow(&t, glen);
    memcpy(t.p, good, glen);
    t.len = glen;
    t.p[pos] ^= (uint8_t)(1u << (pos % 8));
    int rc = ovl_open(&t, &bf, &o);
    if (pos < ZOVL_HEADER_SIZE) {
      /* magic/major/incompat damage may read as "unsupported" */
      if (rc != ZVFS_ERR_CORRUPT && rc != ZVFS_ERR_UNSUPPORTED) {
        if (flips++ < 3) fprintf(stderr, "header flip %zu accepted\n", pos);
        if (!rc) ovl_close(bf);
      } else {
        refused++;
      }
    } else {
      /* state = last commit that ends before the damaged byte (padding
         bytes are not covered, so the damage may also be harmless) */
      int want = expected_state(&h, pos);
      int alt = expected_state(&h, glen);
      if (rc || (!ovl_matches(o, &h.st[want]) && !ovl_matches(o, &h.st[alt]))) {
        if (flips++ < 3) fprintf(stderr, "flip %zu rc=%d want=%d\n", pos, rc, want);
      }
      if (!rc) ovl_close(bf);
    }
    free(t.p);
  }
  CHECK_EQ(flips, 0);
  CHECK_EQ(refused, ZOVL_HEADER_SIZE);
  printf("  overlay ps=%u: %zu bytes, %d commits, torn/flip ok (every %zu. offset)\n",
         ps, glen, h.n - 1, stride);
  free(good);
  free(m.p);
  hist_free(&h);
}

/* Hand-built records: a commit with no data, bad checksums, wrong seq. */
static void put_commit(memovl *m, uint64_t *chain, uint32_t count, uint64_t seq,
                       uint64_t size) {
  uint8_t r[ZOVL_COMMIT_SIZE];
  memset(r, 0, sizeof r);
  zdb_put32(r, ZOVL_TAG_COMMIT);
  zdb_put32(r + 4, count);
  zdb_put64(r + 16, seq);
  zdb_put64(r + 24, size);
  *chain = zvfs_xxh64(r, 40, *chain);
  zdb_put64(r + 40, *chain);
  mo_handle hh = {m};
  mo_write(&hh, r, sizeof r, m->len);
}

static void test_ovl_handmade(void) {
  build_membase(4096);
  memovl m;
  memset(&m, 0, sizeof m);
  zdb_file *bf;
  zovl *o;
  CHECK_EQ(ovl_open(&m, &bf, &o), 0);
  uint8_t pg[4096];
  memset(pg, 7, sizeof pg);
  CHECK_EQ(zovl_write(o, mb_rd, &g_mb, pg, 4096, 4096), 0);
  CHECK_EQ(zovl_commit(o, 2), 0);
  zovl_info oi;
  zovl_get_info(o, &oi);
  CHECK_EQ(oi.seq, 1);
  CHECK(m.syncs >= 2); /* header + commit */
  ovl_close(bf);
  uint8_t *p = m.p;
  uint64_t chain = zvfs_xxh64(p, ZOVL_HEADER_SIZE, 0);
  /* recompute the chain up to the first commit */
  size_t pos = ZOVL_HEADER_SIZE;
  while (zdb_get32(p + pos) == ZOVL_TAG_PAGE) {
    chain = zdb_get64(p + pos + 24);
    pos += (32 + zdb_get32(p + pos + 8) + 15) & ~(size_t)15;
  }
  chain = zdb_get64(p + pos + 40);
  size_t after1 = m.len;

  /* a commit without data (only a size change) is a valid commit */
  put_commit(&m, &chain, 0, 2, g_base_logical + 8192);
  CHECK_EQ(ovl_open(&m, &bf, &o), 0);
  zovl_get_info(o, &oi);
  CHECK_EQ(oi.seq, 2);
  CHECK_EQ(zovl_logical_size(o), g_base_logical + 8192);
  ovl_close(bf);

  /* wrong seq, wrong count, bad chain: each stops the scan there */
  size_t after2 = m.len;
  uint64_t c2 = chain;
  put_commit(&m, &c2, 0, 5, g_base_logical);
  CHECK_EQ(ovl_open(&m, &bf, &o), 0);
  zovl_get_info(o, &oi);
  CHECK_EQ(oi.seq, 2);
  ovl_close(bf);
  m.len = after2;
  c2 = chain;
  put_commit(&m, &c2, 3, 3, g_base_logical);
  CHECK_EQ(ovl_open(&m, &bf, &o), 0);
  zovl_get_info(o, &oi);
  CHECK_EQ(oi.seq, 2);
  ovl_close(bf);
  m.len = after2;
  c2 = chain ^ 1;
  put_commit(&m, &c2, 0, 3, g_base_logical);
  CHECK_EQ(ovl_open(&m, &bf, &o), 0);
  zovl_get_info(o, &oi);
  CHECK_EQ(oi.seq, 2);
  /* the next writer truncates the invalid tail before appending */
  CHECK_EQ(zovl_truncate(o, mb_rd, &g_mb, g_base_logical), 0);
  CHECK_EQ(m.len, after2 + ZOVL_COMMIT_SIZE);
  ovl_close(bf);
  CHECK_EQ(ovl_open(&m, &bf, &o), 0);
  zovl_get_info(o, &oi);
  CHECK_EQ(oi.seq, 3);
  CHECK_EQ(zovl_logical_size(o), g_base_logical);
  ovl_close(bf);
  (void)after1;

  /* foreign overlay (other base uuid) and unknown major */
  memovl f;
  memset(&f, 0, sizeof f);
  f.exists = 1;
  mo_grow(&f, m.len);
  memcpy(f.p, m.p, m.len);
  f.len = m.len;
  f.p[40] ^= 1;
  zdb_put64(f.p + 120, zvfs_xxh64(f.p, 120, 0));
  CHECK_EQ(ovl_open(&f, &bf, &o), ZVFS_ERR_CORRUPT);
  memcpy(f.p, m.p, 128);
  f.p[8] = 2;
  CHECK_EQ(ovl_open(&f, &bf, &o), ZVFS_ERR_UNSUPPORTED);
  memcpy(f.p, m.p, 128);
  zdb_put32(f.p + 16, 1); /* unknown incompat bit */
  zdb_put64(f.p + 120, zvfs_xxh64(f.p, 120, 0));
  CHECK_EQ(ovl_open(&f, &bf, &o), ZVFS_ERR_UNSUPPORTED);
  free(f.p);
  free(m.p);
}

/* Two instances on one sidecar behave like two processes. */
static void test_ovl_two_processes(void) {
  build_membase(4096);
  memovl m;
  memset(&m, 0, sizeof m);
  zdb_file *ba, *bb, *bc;
  zovl *a, *b, *c;
  CHECK_EQ(ovl_open(&m, &ba, &a), 0);
  CHECK_EQ(ovl_open(&m, &bb, &b), 0);
  image im;
  img_from_base(&im);
  uint8_t pg[4096];
  for (int round = 0; round < 20; round++) {
    zovl *w = round % 2 ? b : a, *r = round % 2 ? a : b;
    CHECK_EQ(zovl_refresh(w), 0); /* lock acquisition */
    for (int k = 0; k < 5; k++) {
      memset(pg, round * 16 + k, sizeof pg);
      uint64_t off = (uint64_t)((round * 7 + k * 3) % 40) * 4096;
      CHECK_EQ(zovl_write(w, mb_rd, &g_mb, pg, 4096, off), 0);
      img_write(&im, pg, 4096, off);
      /* the reader sees nothing unsealed */
      CHECK_EQ(zovl_refresh(r), 0);
    }
    CHECK_EQ(zovl_commit(w, 0), 0);
    CHECK_EQ(zovl_refresh(r), 0);
    CHECK(ovl_matches(r, &im));
    CHECK(ovl_matches(w, &im));
  }
  /* a writer dies mid-batch; a third process scans its garbage, then a new
     writer overwrites it: the resumed scan must not trust the old prefix */
  CHECK_EQ(ovl_open(&m, &bc, &c), 0);
  CHECK_EQ(zovl_refresh(a), 0);
  for (int k = 0; k < 6; k++) {
    memset(pg, 0xE0 + k, sizeof pg);
    CHECK_EQ(zovl_write(a, mb_rd, &g_mb, pg, 4096, (uint64_t)k * 4096), 0);
  }
  ovl_close(ba); /* died: no commit */
  CHECK_EQ(zovl_refresh(c), 0);
  CHECK(ovl_matches(c, &im));
  CHECK_EQ(zovl_refresh(b), 0);
  g_rng = 99;
  for (int k = 0; k < 2; k++) {
    /* incompressible: the new tail outgrows the garbage, so c resumes */
    for (int i = 0; i < 4096; i++) pg[i] = (uint8_t)rnd();
    CHECK_EQ(zovl_write(b, mb_rd, &g_mb, pg, 4096, (uint64_t)(k + 3) * 4096), 0);
    img_write(&im, pg, 4096, (uint64_t)(k + 3) * 4096);
  }
  CHECK_EQ(zovl_commit(b, 0), 0);
  CHECK_EQ(zovl_refresh(c), 0);
  CHECK(ovl_matches(c, &im));
  /* c's only append fails: after its unlock it must still see b's commits */
  m.fail_writes = 1;
  CHECK(zovl_write(c, mb_rd, &g_mb, pg, 4096, 0) != 0);
  CHECK_EQ(zovl_commit(c, 0), 0);
  memset(pg, 0x77, sizeof pg);
  CHECK_EQ(zovl_write(b, mb_rd, &g_mb, pg, 4096, 8192), 0);
  img_write(&im, pg, 4096, 8192);
  CHECK_EQ(zovl_commit(b, 0), 0);
  CHECK_EQ(zovl_refresh(c), 0);
  CHECK(ovl_matches(c, &im));
  ovl_close(bb);
  ovl_close(bc);
  free(im.p);
  free(m.p);
}

/* Seals from other connections race with a growing writer: a replay of what
   they committed must equal the writer's live view. */
typedef struct seal_arg {
  zovl *o;
  volatile int64_t stop;
  int seals;
} seal_arg;

static void sealer(void *p) {
  seal_arg *a = (seal_arg *)p;
  /* yield: a spinning sealer starves the writer (TSan livelocked on it) */
  while (!zplat_atomic_load(&a->stop) && a->seals < 200000) {
    zovl_commit(a->o, 0);
    a->seals++;
#if defined(_WIN32)
    SwitchToThread();
#else
    sched_yield();
#endif
  }
}

extern void (*zvfs_test_after_append)(zovl *o);
static void seal_now(zovl *o) { CHECK_EQ(zovl_commit(o, 0), 0); }

static void test_ovl_concurrent_seal(void) {
  build_membase(4096);
  memovl m;
  memset(&m, 0, sizeof m);
  zdb_file *bf;
  zovl *o;
  CHECK_EQ(ovl_open(&m, &bf, &o), 0);
  image im;
  img_from_base(&im);
  seal_arg a = {o, 0, 0};
  zplat_thread th;
  zplat_thread_start(&th, sealer, &a);
  uint8_t pg[4096];
  for (int i = 0; i < 3000; i++) {
    memset(pg, i, sizeof pg);
    uint64_t off = im.len + (i % 3 == 0 ? 100 : 0); /* growth, sometimes partial */
    uint32_t n = i % 3 == 0 ? 3000 : 4096;
    CHECK_EQ(zovl_write(o, mb_rd, &g_mb, pg, n, off), 0);
    img_write(&im, pg, n, off);
  }
  zplat_atomic_store(&a.stop, 1);
  zplat_thread_join(th);
  /* deterministic: a seal right after every page append */
  zvfs_test_after_append = seal_now;
  static uint8_t two[8192];
  for (int i = 0; i < 200; i++) {
    memset(two, 0x80 + i, sizeof two);
    uint64_t off = im.len + (i % 2 ? 777 : 0);
    CHECK_EQ(zovl_write(o, mb_rd, &g_mb, two, 5096, off), 0);
    img_write(&im, two, 5096, off);
  }
  zvfs_test_after_append = NULL;
  CHECK_EQ(zovl_commit(o, 0), 0);
  CHECK(ovl_matches(o, &im));
  zovl_info oi;
  zovl_get_info(o, &oi);
  ovl_close(bf);
  CHECK_EQ(ovl_open(&m, &bf, &o), 0);
  CHECK(ovl_matches(o, &im));
  zovl_info ri;
  zovl_get_info(o, &ri);
  CHECK_EQ(ri.mapped_pages, oi.mapped_pages);
  ovl_close(bf);
  printf("  concurrent seals: %d seal calls, %llu commits, replay equals live\n",
         a.seals, (unsigned long long)oi.commits);
  free(im.p);
  free(m.p);
}

static void test_ovl_sparse_and_failures(void) {
  build_membase(4096);
  memovl m;
  memset(&m, 0, sizeof m);
  zdb_file *bf;
  zovl *o;
  CHECK_EQ(ovl_open(&m, &bf, &o), 0);
  uint8_t pg[4096];
  memset(pg, 0x11, sizeof pg);
  /* a page far beyond EOF: holes read as zeros, map stays sparse */
  uint64_t far_off = (1ull << 31) * 4096;
  CHECK_EQ(zovl_write(o, mb_rd, &g_mb, pg, 4096, far_off), 0);
  CHECK_EQ(zovl_commit(o, 0), 0);
  CHECK_EQ(zovl_logical_size(o), far_off + 4096);
  uint8_t z[4096];
  CHECK_EQ(zovl_read(o, mb_rd, &g_mb, z, 4096, far_off - 4096 * 1000), 0);
  CHECK(z[0] == 0 && z[4095] == 0);
  CHECK_EQ(zovl_read(o, mb_rd, &g_mb, z, 4096, far_off), 0);
  CHECK(z[0] == 0x11);
  ovl_close(bf);
  CHECK_EQ(ovl_open(&m, &bf, &o), 0);
  CHECK_EQ(zovl_logical_size(o), far_off + 4096);
  /* a failed commit write poisons the state until reopened */
  m.fail_writes = 2;
  CHECK_EQ(zovl_write(o, mb_rd, &g_mb, pg, 4096, 0), 0);
  CHECK(zovl_commit(o, 0) != 0);
  CHECK(zovl_read(o, mb_rd, &g_mb, z, 16, 0) != 0);
  CHECK(zovl_write(o, mb_rd, &g_mb, pg, 4096, 0) != 0);
  ovl_close(bf);
  m.fail_writes = 0;
  CHECK_EQ(ovl_open(&m, &bf, &o), 0);
  CHECK_EQ(zovl_logical_size(o), far_off + 4096);
  CHECK_EQ(zovl_read(o, mb_rd, &g_mb, z, 4096, 0), 0);
  CHECK(memcmp(z, g_base_plain, 4096) == 0);
  ovl_close(bf);
  free(m.p);
}

static void test_ovl_fuzz(int iters) {
  build_membase(4096);
  memovl m;
  memset(&m, 0, sizeof m);
  history h;
  memset(&h, 0, sizeof h);
  random_session(&m, &h, 10, 0xF00D);
  int opened = 0, refused = 0, wrong = 0;
  g_rng = 0xBADC0DE;
  for (int it = 0; it < iters; it++) {
    memovl t;
    memset(&t, 0, sizeof t);
    t.exists = 1;
    mo_grow(&t, m.len + 4096);
    memcpy(t.p, m.p, m.len);
    t.len = m.len;
    for (int k = 0, n = 1 + (int)(rnd() % 4); k < n; k++) {
      size_t pos = (size_t)(rnd() % t.len);
      switch (rnd() % 6) {
        case 0: t.p[pos] ^= (uint8_t)(1u << (rnd() % 8)); break;
        case 1: t.p[pos] = (uint8_t)rnd(); break;
        case 2: t.len = pos; break;
        case 3:
          for (int j = 0; j < 32 && pos + j < t.len; j++) t.p[pos + j] = (uint8_t)rnd();
          break;
        case 4: { /* duplicate a range (replayed record) */
          size_t src = (size_t)(rnd() % t.len), n2 = (size_t)(rnd() % 256);
          if (src + n2 <= t.len && pos + n2 <= t.len) memmove(t.p + pos, t.p + src, n2);
          break;
        }
        default: /* append junk */
          for (int j = 0; j < 64; j++) t.p[t.len++] = (uint8_t)rnd();
      }
    }
    zdb_file *bf;
    zovl *o;
    int rc = ovl_open(&t, &bf, &o);
    if (rc) {
      refused++;
    } else {
      opened++;
      int match = 0;
      for (int i = 0; i < h.n && !match; i++) match = ovl_matches(o, &h.st[i]);
      if (!match) wrong++;
      ovl_close(bf);
    }
    free(t.p);
  }
  CHECK_EQ(wrong, 0);
  printf("  overlay fuzz: %d mutations, %d opened (all a committed state), "
         "%d refused\n",
         iters, opened, refused);
  hist_free(&h);
  free(m.p);
}

/* ================= SQL equivalence: plain file vs zdb + overlay ================= */
static int same_logical_bytes(const char *plain, const char *zdb) {
  uint8_t *a;
  size_t na;
  if (read_file(plain, &a, &na)) return 0;
  zvfs_reader *r = NULL;
  int ok = zvfs_reader_open(zdb, &r) == ZVFS_OK;
  zvfs_info info;
  if (ok) zvfs_reader_info(r, &info);
  ok = ok && info.logical_size == na;
  uint8_t *b = (uint8_t *)malloc(na ? na : 1);
  ok = ok && zvfs_reader_read(r, b, (int64_t)na, 0) == ZVFS_OK;
  /* header bytes 18/19 differ only if the source was converted from WAL */
  ok = ok && memcmp(a, b, na) == 0;
  if (!ok && r && na) {
    size_t i = 0;
    while (i < na && a[i] == b[i]) i++;
    if (ts_verbose) fprintf(stderr, "first difference at %zu of %zu\n", i, na);
  }
  zvfs_reader_close(r);
  free(a);
  free(b);
  return ok;
}

static int buf_rd(void *ctx, void *buf, size_t n, uint64_t off) {
  const uint8_t *const *m = (const uint8_t *const *)ctx;
  size_t size = (size_t)(m[1] - m[0]);
  if (off + n > size) return ZVFS_ERR_SHORT_READ;
  memcpy(buf, m[0] + off, n);
  return ZVFS_OK;
}

static uint8_t *logical_bytes(const char *zdb, size_t *n) {
  zvfs_reader *r = NULL;
  if (zvfs_reader_open(zdb, &r)) return NULL;
  zvfs_info info;
  zvfs_reader_info(r, &info);
  uint8_t *b = (uint8_t *)malloc((size_t)info.logical_size + 1);
  if (zvfs_reader_read(r, b, (int64_t)info.logical_size, 0)) {
    free(b);
    b = NULL;
  }
  *n = (size_t)info.logical_size;
  zvfs_reader_close(r);
  return b;
}

/* The logical bytes of zdb equal plain, except that plain's freelist leaf
   pages are zeros; returns that leaf count, or -1. */
static int64_t same_live_bytes(const char *plain, const char *zdb) {
  uint8_t *a, *b;
  size_t na, nb;
  if (read_file(plain, &a, &na)) return -1;
  b = logical_bytes(zdb, &nb);
  const uint8_t *m[2] = {a, a + na};
  zvfs_pageset set = {0};
  int64_t leaves = -1;
  if (b && nb == na && !zvfs_freelist_leaves(buf_rd, (void *)m, na, &set)) {
    uint32_t ps = (uint32_t)a[16] << 8 | a[17];
    if (ps == 1) ps = 65536;
    leaves = (int64_t)set.count;
    for (size_t pg = 0; leaves >= 0 && pg < na / ps; pg++) {
      const uint8_t *pa = a + pg * ps, *pb = b + pg * ps;
      int leaf = set.bits && (set.bits[pg >> 3] >> (pg & 7) & 1);
      if (leaf) {
        for (uint32_t i = 0; i < ps; i++)
          if (pb[i]) leaves = -1;
      } else if (memcmp(pa, pb, ps) != 0) {
        if (ts_verbose) fprintf(stderr, "live page %zu differs\n", pg);
        leaves = -1;
      }
    }
  }
  free(set.bits);
  free(a);
  free(b);
  return leaves;
}

static void random_statement(char *sql, size_t cap, int step, int *tables) {
  uint64_t r = rnd();
  int t = (int)(r % 6);
  int64_t id = (int64_t)(rnd() % 30000);
  switch (t) {
    case 0:
      snprintf(sql, cap,
               "INSERT OR REPLACE INTO line VALUES(%lld, %d, %d, printf('s%d %%.*c', "
               "%d, 'w'), %s)",
               (long long)id, 1 + step % 20, step, step, (int)(rnd() % 3000),
               rnd() % 7 == 0 ? "CAST(printf('%.*c', 7000, 'x') AS BLOB)" : "NULL");
      break;
    case 1:
      snprintf(sql, cap,
               "UPDATE line SET content = content || '%d' WHERE id BETWEEN %lld AND "
               "%lld",
               step, (long long)id, (long long)(id + (int64_t)(rnd() % 200)));
      break;
    case 2:
      snprintf(sql, cap, "DELETE FROM line WHERE id BETWEEN %lld AND %lld",
               (long long)id, (long long)(id + (int64_t)(rnd() % 300)));
      break;
    case 3:
      snprintf(sql, cap,
               "INSERT OR REPLACE INTO meta VALUES('k%lld', printf('%%.*c', %d, 'v'))",
               (long long)(id % 2000), (int)(rnd() % 900));
      break;
    case 4: {
      int k = (*tables)++;
      if (rnd() % 3 == 0 && k > 0)
        snprintf(sql, cap, "DROP TABLE IF EXISTS extra%d", (int)(rnd() % k));
      else if (rnd() % 2)
        snprintf(sql, cap,
                 "CREATE TABLE extra%d AS SELECT id, content FROM line WHERE id %% %d = 0",
                 k, 3 + k % 11);
      else
        snprintf(sql, cap, "CREATE INDEX IF NOT EXISTS ix%d ON line(content, id)",
                 k % 4);
      break;
    }
    default:
      snprintf(sql, cap, "DELETE FROM link WHERE id %% %d = %d", 3 + (int)(rnd() % 50),
               (int)(rnd() % 3));
  }
}

static void test_sql_equivalence(int page_size, int steps) {
  const char *plain = tmp_path("eq_plain.db");
  const char *zdb = tmp_path("eq.zdb");
  ts_remove_all(plain);
  ts_remove_all(zdb);
  sqlite3 *p = ts_open(plain, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  char sql[1024];
  snprintf(sql, sizeof sql, "PRAGMA page_size=%d", page_size);
  ts_must(p, sql);
  ts_make_base(p, 40, 12000);
  sqlite3_close(p);
  CHECK_EQ(ts_convert(plain, zdb), 0);
  p = ts_open(plain, SQLITE_OPEN_READWRITE, NULL);
  sqlite3 *z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  CHECK(p && z);
  g_rng = 0xE9 + (uint64_t)page_size;
  int tables = 0, wal = 0, mismatches = 0;
  for (int step = 0; step < steps; step++) {
    int kind = (int)(rnd() % 20);
    if (kind == 0) {
      /* journal mode switch, as the updater does around an apply */
      wal = !wal;
      const char *q = wal ? "PRAGMA journal_mode=WAL" : "PRAGMA journal_mode=DELETE";
      ts_must(p, q);
      ts_must(z, q);
    } else if (kind == 1 && wal) {
      ts_must(p, "PRAGMA wal_checkpoint(TRUNCATE)");
      ts_must(z, "PRAGMA wal_checkpoint(TRUNCATE)");
    } else {
      int n = 1 + (int)(rnd() % 12);
      int rollback = rnd() % 9 == 0;
      ts_must(p, "BEGIN");
      ts_must(z, "BEGIN");
      for (int i = 0; i < n; i++) {
        random_statement(sql, sizeof sql, step, &tables);
        int ra = ts_exec(p, sql), rb = ts_exec(z, sql);
        if (ra != rb) {
          fprintf(stderr, "rc mismatch %d/%d: %s\n", ra, rb, sql);
          g_failures++;
        }
      }
      const char *end = rollback ? "ROLLBACK" : "COMMIT";
      ts_must(p, end);
      ts_must(z, end);
    }
    if (step % 25 == 24 || step == steps - 1) {
      int ra = 0, rb = 0;
      uint64_t ha = ts_content_hash(p, &ra), hb = ts_content_hash(z, &rb);
      if (ha != hb || ra || rb) mismatches++;
    }
  }
  /* one transaction of 100K rows */
  ts_must(p, "BEGIN");
  ts_must(z, "BEGIN");
  const char *big =
      "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<100000)"
      " INSERT OR REPLACE INTO line SELECT 50000+i, i%40, i, printf('bulk %d %.*c',"
      " i, i%90, 'b'), NULL FROM n";
  ts_must(p, big);
  ts_must(z, big);
  ts_must(p, "UPDATE line SET lineIndex = lineIndex + 1 WHERE id % 3 = 0");
  ts_must(z, "UPDATE line SET lineIndex = lineIndex + 1 WHERE id % 3 = 0");
  ts_must(p, "COMMIT");
  ts_must(z, "COMMIT");
  ts_must(p, "PRAGMA journal_mode=DELETE");
  ts_must(z, "PRAGMA journal_mode=DELETE");
  int ra = 0, rb = 0;
  uint64_t ha = ts_content_hash(p, &ra), hb = ts_content_hash(z, &rb);
  CHECK(ha == hb && !ra && !rb);
  CHECK(ts_integrity_ok(p));
  CHECK(ts_integrity_ok(z));
  sqlite3_close(p);
  sqlite3_close(z);
  CHECK_EQ(mismatches, 0);
  /* SQLite is deterministic, so the logical file equals the plain file */
  CHECK(same_logical_bytes(plain, zdb));
  z = ts_open(zdb, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  CHECK(z && ts_integrity_ok(z));
  rb = 0;
  CHECK(ts_content_hash(z, &rb) == ha);
  sqlite3_close(z);
  zvfs_reader *r;
  CHECK_EQ(zvfs_reader_open(zdb, &r), 0);
  CHECK_EQ(zvfs_reader_verify(r, NULL, NULL), 0);
  zvfs_overlay_info oi;
  zvfs_reader_overlay_info(r, &oi);
  zvfs_info bi;
  zvfs_reader_info(r, &bi);
  printf("  equivalence ps=%d: %d steps + 100K-row txn, overlay %llu bytes "
         "(%llu commits, %llu pages mapped), base %llu bytes, plain %llu bytes\n",
         page_size, steps, (unsigned long long)oi.file_size,
         (unsigned long long)oi.commits, (unsigned long long)oi.mapped_pages,
         (unsigned long long)bi.physical_size, (unsigned long long)bi.logical_size);
  zvfs_reader_close(r);

  /* compaction: same logical bytes, overlay gone, lineage recorded */
  char dst[1100];
  snprintf(dst, sizeof dst, "%s.new", zdb);
  zvfs_info ci;
  char err[256];
  CHECK_EQ(zvfs_compact(zdb, dst, 3, 2, 0, NULL, NULL, &ci, NULL, err, sizeof err), 0);
  CHECK(ci.includes_overlay_seq == oi.seq);
  CHECK_EQ(zvfs_compact_swap(zdb, dst), 0);
  char ov[1100];
  snprintf(ov, sizeof ov, "%s-zovl", zdb);
  CHECK(zplat_exists(ov) == 0);
  /* compaction writes the freelist leaves as zeros */
  CHECK(same_live_bytes(plain, zdb) >= 0);
  ts_remove_all(plain);
  ts_remove_all(zdb);
}

/* ================= compaction crash windows ================= */
static int copy_file(const char *a, const char *b) {
  uint8_t *d;
  size_t n;
  if (read_file(a, &d, &n)) return -1;
  int rc = write_file(b, d, n);
  free(d);
  return rc;
}

static uint64_t open_hash(const char *zdb, int *ok) {
  sqlite3 *db = ts_open(zdb, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  int rc = SQLITE_OK;
  uint64_t h = db ? ts_content_hash(db, &rc) : 0;
  *ok = db && rc == SQLITE_OK && ts_integrity_ok(db);
  sqlite3_close(db);
  return h;
}

/* ---- sidecar left by a crash between the compaction rename and delete ---- */
static int64_t refresh_scans(void) {
  zvfs_stats s;
  zvfs_get_stats(&s);
  return s.overlay_refresh_scans;
}

static void test_stale_sidecar(void) {
  const char *plain = tmp_path("st_plain.db");
  const char *zdb = tmp_path("st.zdb");
  char ov[1100], dst[1100];
  snprintf(ov, sizeof ov, "%s-zovl", zdb);
  snprintf(dst, sizeof dst, "%s.new", zdb);
  ts_remove_all(plain);
  ts_remove_all(zdb);
  sqlite3 *p = ts_open(plain, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  ts_make_base(p, 30, 20000);
  sqlite3_close(p);
  CHECK_EQ(ts_convert(plain, zdb), 0);
  sqlite3 *z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  for (int i = 0; i < 20; i++)
    ts_must(z, "UPDATE line SET content = content || 'x' WHERE id % 3 = 0");
  sqlite3_close(z);
  int ok;
  uint64_t want = open_hash(zdb, &ok);
  CHECK(ok);
  /* rename landed, the sidecar delete did not */
  CHECK_EQ(zvfs_compact(zdb, dst, 3, 2, 0, NULL, NULL, NULL, NULL, NULL, 0), 0);
  CHECK_EQ(zplat_rename_durable(dst, zdb), 0);
  CHECK(zplat_exists(ov) == 1);
  CHECK(open_hash(zdb, &ok) == want && ok);
  /* a stale sidecar is scanned once, not on every lock */
  z = ts_open(zdb, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  int64_t before = refresh_scans();
  for (int i = 0; i < 200; i++) ts_int(z, "SELECT count(*) FROM book");
  int64_t scans = refresh_scans() - before;
  sqlite3_close(z);
  CHECK(scans < 3);
  /* compacting again and crashing at the same point: still readable */
  CHECK_EQ(zvfs_compact(zdb, dst, 3, 2, 0, NULL, NULL, NULL, NULL, NULL, 0), 0);
  CHECK_EQ(zplat_rename_durable(dst, zdb), 0);
  CHECK(zplat_exists(ov) == 1);
  CHECK(open_hash(zdb, &ok) == want && ok);
  /* three more crashes there, then a write, then one more */
  for (int k = 0; k < 3; k++) {
    CHECK_EQ(zvfs_compact(zdb, dst, 3, 2, 0, NULL, NULL, NULL, NULL, NULL, 0), 0);
    CHECK_EQ(zplat_rename_durable(dst, zdb), 0);
    CHECK(open_hash(zdb, &ok) == want && ok);
  }
  z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  ts_must(z, "UPDATE meta SET v='between' WHERE k='key4'");
  sqlite3_close(z);
  uint64_t want2 = open_hash(zdb, &ok);
  CHECK(ok && want2 != want);
  CHECK_EQ(zvfs_compact(zdb, dst, 3, 2, 0, NULL, NULL, NULL, NULL, NULL, 0), 0);
  CHECK_EQ(zplat_rename_durable(dst, zdb), 0);
  CHECK(open_hash(zdb, &ok) == want2 && ok);
  /* and a full swap, then a write, then reopen */
  CHECK_EQ(zvfs_compact(zdb, dst, 3, 2, 0, NULL, NULL, NULL, NULL, NULL, 0), 0);
  CHECK_EQ(zvfs_compact_swap(zdb, dst), 0);
  CHECK(zplat_exists(ov) == 0);
  CHECK(open_hash(zdb, &ok) == want2 && ok);
  z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  ts_must(z, "UPDATE meta SET v='later' WHERE k='key2'");
  sqlite3_close(z);
  z = ts_open(zdb, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  CHECK(z && ts_integrity_ok(z) &&
        ts_int(z, "SELECT count(*) FROM meta WHERE v='later'") == 1);
  sqlite3_close(z);
  printf("  stale sidecar: %lld scans for 200 queries, second compaction ok\n",
         (long long)scans);
  ts_remove_all(plain);
  ts_remove_all(zdb);
}

/* A derived overlay that moved on past includesOverlaySeq replays on top. */
static void test_derived_newer(void) {
  const char *plain = tmp_path("dn_plain.db");
  const char *zdb = tmp_path("dn.zdb");
  char dst[1100];
  snprintf(dst, sizeof dst, "%s.new", zdb);
  ts_remove_all(plain);
  ts_remove_all(zdb);
  sqlite3 *p = ts_open(plain, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  ts_make_base(p, 30, 8000);
  sqlite3_close(p);
  CHECK_EQ(ts_convert(plain, zdb), 0);
  sqlite3 *z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  ts_must(z, "UPDATE line SET content = upper(content) WHERE id % 4 = 0;"
             "DELETE FROM link WHERE id % 3 = 0;");
  sqlite3_close(z);
  CHECK_EQ(zvfs_compact(zdb, dst, 3, 2, 0, NULL, NULL, NULL, NULL, NULL, 0), 0);
  z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  ts_must(z, "DELETE FROM line WHERE id > 6000; VACUUM;"
             "UPDATE meta SET v='after' WHERE k='key9';");
  sqlite3_close(z);
  int ok;
  uint64_t want = open_hash(zdb, &ok);
  CHECK(ok);
  /* the swap refuses; emulate the unguarded race of another process */
  CHECK_EQ(zvfs_compact_swap(zdb, dst), ZVFS_ERR_BUSY);
  CHECK_EQ(zplat_rename_durable(dst, zdb), 0);
  CHECK(open_hash(zdb, &ok) == want && ok);
  printf("  derived overlay newer than the compacted base: replayed on top\n");
  ts_remove_all(plain);
  ts_remove_all(zdb);
}

/* ================= compaction: freelist zeroing and frame copies ================= */
static int convert_fp(const char *src, const char *dst, uint32_t fp) {
  uint8_t *data;
  size_t n;
  if (read_file(src, &data, &n)) return -1;
  const char *name;
  const void *dict;
  size_t dl;
  zvfs_builtin_dict(0, &name, &dict, &dl, NULL);
  zvfs_conv *c = NULL;
  int rc = zvfs_conv_create(dst, dict, dl, name, 3, 2, fp, 1 << 20, NULL, &c);
  if (!rc) rc = zvfs_conv_feed(c, data, n);
  if (!rc) rc = zvfs_conv_finish(c, NULL);
  zvfs_conv_destroy(c);
  free(data);
  return rc;
}

/* Frames of the new base that are byte-identical to a frame of the old one. */
static uint64_t shared_frames(const char *a, const char *b) {
  uint8_t *x, *y;
  size_t nx, ny;
  if (read_file(a, &x, &nx) || read_file(b, &y, &ny)) return 0;
  const uint8_t *mx[2] = {x, x + nx}, *my[2] = {y, y + ny};
  zdb_file *fa = NULL, *fb = NULL;
  uint64_t same = 0;
  if (!zdb_file_load(buf_rd, (void *)mx, nx, &fa) &&
      !zdb_file_load(buf_rd, (void *)my, ny, &fb)) {
    for (uint64_t i = 0; i < fb->h.frame_count && i < fa->h.frame_count; i++) {
      uint64_t la = zdb_frame_end(fa, i) - fa->index[i];
      uint64_t lb = zdb_frame_end(fb, i) - fb->index[i];
      same += la == lb && !memcmp(x + fa->index[i], y + fb->index[i], (size_t)la);
    }
  }
  zdb_file_free(fa);
  zdb_file_free(fb);
  free(x);
  free(y);
  return same;
}

static void test_compact_freelist(uint32_t fp, uint64_t lock_byte) {
  const char *plain = tmp_path("cf_plain.db");
  const char *zdb = tmp_path("cf.zdb");
  const char *patch = tmp_path("cf_patch.db");
  const char *out = tmp_path("cf_out.zdb");
  char alt[1100]; /* tmp_path has only four slots */
  snprintf(alt, sizeof alt, "%s.alt", out);
  ts_remove_all(plain);
  ts_remove_all(zdb);
  ts_remove_all(patch);
  ts_remove_all(out);
  zvfs_g_lock_byte = lock_byte;
  sqlite3 *p = ts_open(plain, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  ts_must(p, "PRAGMA page_size=4096");
  ts_make_base(p, 40, 30000);
  sqlite3_close(p);
  CHECK_EQ(convert_fp(plain, zdb, fp), 0);
  char base_copy[1100];
  snprintf(base_copy, sizeof base_copy, "%s.base", zdb);
  CHECK_EQ(copy_file(zdb, base_copy), 0);
  sqlite3 *pp = ts_open(patch, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  ts_make_patch(pp, 3, 30000, 2000, 1500, 2500);
  sqlite3_close(pp);
  /* the same patch and a large delete on both: freelist pages appear */
  static const char *more =
      "DELETE FROM line WHERE id BETWEEN 9000 AND 17000;"
      "DELETE FROM link WHERE id % 2 = 0;";
  p = ts_open(plain, SQLITE_OPEN_READWRITE, NULL);
  sqlite3 *z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  CHECK_EQ(ts_apply_patch(p, patch, 700), 0);
  CHECK_EQ(ts_apply_patch(z, patch, 700), 0);
  ts_must(p, more);
  ts_must(z, more);
  int64_t free_pages = ts_int(p, "PRAGMA freelist_count");
  CHECK(free_pages > 50 && free_pages == ts_int(z, "PRAGMA freelist_count"));
  int ra = 0;
  uint64_t want = ts_content_hash(p, &ra);
  CHECK(!ra);
  sqlite3_close(p);
  sqlite3_close(z);
  CHECK(same_logical_bytes(plain, zdb));

  /* every flag combination: valid, and logically what it promises */
  uint8_t *ref = NULL;
  size_t nref = 0;
  for (int flags = 0; flags < 4; flags++) {
    zvfs_compact_stats st;
    zvfs_info ci;
    char err[256];
    const char *dst = flags ? alt : out;
    CHECK_EQ(zvfs_compact(zdb, dst, 3, 2, flags, NULL, NULL, &ci, &st, err,
                          sizeof err), 0);
    zvfs_reader *r = NULL;
    CHECK_EQ(zvfs_reader_open(dst, &r), 0);
    CHECK_EQ(zvfs_reader_verify(r, NULL, NULL), 0);
    zvfs_reader_close(r);
    int keep = (flags & ZVFS_COMPACT_KEEP_FREELIST) != 0;
    int recompress = (flags & ZVFS_COMPACT_RECOMPRESS) != 0;
    if (keep) {
      CHECK(same_logical_bytes(plain, dst));
      CHECK_EQ(st.freelist_leaves, 0);
    } else {
      int64_t leaves = same_live_bytes(plain, dst);
      CHECK(leaves > 0 && leaves < free_pages);
      CHECK_EQ(st.freelist_leaves, leaves);
    }
    if (recompress) CHECK_EQ(st.frames_copied, 0);
    else CHECK(st.frames_copied > 0 && st.frames_copied < st.frames);
    /* copied frames are the old base's bytes; recompressed ones mostly not */
    uint64_t shared = shared_frames(base_copy, dst);
    if (!recompress) CHECK(shared >= st.frames_copied);
    size_t nb = 0;
    uint8_t *b = logical_bytes(dst, &nb);
    if (flags == 0) {
      ref = b;
      nref = nb;
    } else {
      /* reuse and recompress give the same logical bytes */
      if (flags == ZVFS_COMPACT_RECOMPRESS) CHECK(b && nb == nref && !memcmp(b, ref, nb));
      free(b);
    }
    printf("  compact fp=%u flags=%d: %llu frames, %llu copied (%llu shared), "
           "%llu leaves zeroed, %llu bytes\n",
           fp, flags, (unsigned long long)st.frames,
           (unsigned long long)st.frames_copied, (unsigned long long)shared,
           (unsigned long long)st.freelist_leaves,
           (unsigned long long)ci.physical_size);
    remove(alt);
  }
  free(ref);

  /* the zeroed base in place: integrity, same content, freelist reusable */
  CHECK_EQ(zvfs_compact_swap(zdb, out), 0);
  int ok;
  CHECK(open_hash(zdb, &ok) == want && ok);
  z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  CHECK_EQ(ts_int(z, "PRAGMA freelist_count"), free_pages);
  ts_must(z, "INSERT INTO line SELECT id + 1000000, bookId, lineIndex, content, extra"
             " FROM line WHERE id < 6000");
  CHECK(ts_int(z, "PRAGMA freelist_count") < free_pages);
  CHECK(ts_integrity_ok(z));
  sqlite3_close(z);
  /* compacting it again copies the already-zero leaves too */
  zvfs_compact_stats st2;
  CHECK_EQ(zvfs_compact(zdb, out, 3, 2, 0, NULL, NULL, NULL, &st2, NULL, 0), 0);
  CHECK_EQ(zvfs_compact_swap(zdb, out), 0);
  z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  CHECK(z && ts_integrity_ok(z));
  ts_must(z, "VACUUM");
  CHECK(ts_integrity_ok(z));
  CHECK_EQ(ts_int(z, "PRAGMA freelist_count"), 0);
  sqlite3_close(z);
  zvfs_compact_stats st3;
  CHECK_EQ(zvfs_compact(zdb, out, 3, 2, 0, NULL, NULL, NULL, &st3, NULL, 0), 0);
  CHECK_EQ(st3.freelist_leaves, 0);
  remove(out);
  /* no overlay at all: everything but frame 0 is copied */
  zvfs_compact_stats st4;
  CHECK_EQ(zvfs_compact(base_copy, out, 3, 2, 0, NULL, NULL, NULL, &st4, NULL, 0), 0);
  CHECK_EQ(st4.frames_copied, st4.frames - 1);
  CHECK_EQ(shared_frames(base_copy, out), st4.frames);
  printf("  recompact: %llu of %llu frames copied; after VACUUM no leaves\n",
         (unsigned long long)st2.frames_copied, (unsigned long long)st2.frames);
  zvfs_g_lock_byte = ZDB_LOCK_BYTE;
  remove(base_copy);
  ts_remove_all(plain);
  ts_remove_all(zdb);
  ts_remove_all(patch);
  ts_remove_all(out);
}

static void test_compaction_windows(void) {
  const char *plain = tmp_path("cw_plain.db");
  const char *zdb = tmp_path("cw.zdb");
  const char *keep_base = tmp_path("cw_keep.zdb");
  const char *keep_ovl = tmp_path("cw_keep.zovl");
  ts_remove_all(plain);
  ts_remove_all(zdb);
  sqlite3 *p = ts_open(plain, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  ts_make_base(p, 30, 5000);
  sqlite3_close(p);
  CHECK_EQ(ts_convert(plain, zdb), 0);
  sqlite3 *z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  ts_must(z, "UPDATE line SET content = upper(content) WHERE id % 4 = 0;"
             "DELETE FROM link WHERE id % 3 = 0;");
  sqlite3_close(z);
  int ok;
  uint64_t want = open_hash(zdb, &ok);
  CHECK(ok);
  char ov[1100], dst[1100];
  snprintf(ov, sizeof ov, "%s-zovl", zdb);
  snprintf(dst, sizeof dst, "%s.new", zdb);
  CHECK_EQ(copy_file(zdb, keep_base), 0);
  CHECK_EQ(copy_file(ov, keep_ovl), 0);

  /* busy: open in this process (refused before any open), stale output */
  z = ts_open(zdb, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  CHECK_EQ(zvfs_compact(zdb, dst, 3, 2, 0, NULL, NULL, NULL, NULL, NULL, 0), ZVFS_ERR_BUSY);
  CHECK_EQ(zvfs_compact_swap(zdb, dst), ZVFS_ERR_BUSY);
  sqlite3_close(z);
  CHECK_EQ(zvfs_compact(zdb, dst, 3, 2, 0, NULL, NULL, NULL, NULL, NULL, 0), 0);
  z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  ts_must(z, "UPDATE meta SET v='later' WHERE k='key3'");
  sqlite3_close(z);
  CHECK_EQ(zvfs_compact_swap(zdb, dst), ZVFS_ERR_BUSY); /* overlay moved on */
  CHECK_EQ(copy_file(keep_base, zdb), 0);
  CHECK_EQ(copy_file(keep_ovl, ov), 0);

  /* step 1 crashed: a partial .new next to the intact pair */
  CHECK_EQ(zvfs_compact(zdb, dst, 3, 2, 0, NULL, NULL, NULL, NULL, NULL, 0), 0);
  uint8_t *nd;
  size_t nn;
  CHECK_EQ(read_file(dst, &nd, &nn), 0);
  for (size_t cut = 0; cut < nn; cut += nn / 7 + 1) {
    write_file(dst, nd, cut);
    CHECK(open_hash(zdb, &ok) == want && ok);
    CHECK(zvfs_compact_swap(zdb, dst) != ZVFS_OK);
    CHECK(open_hash(zdb, &ok) == want && ok);
  }
  /* rename landed, overlay delete did not: the sidecar is obsolete */
  write_file(dst, nd, nn);
  free(nd);
  CHECK_EQ(copy_file(dst, zdb), 0);
  remove(dst);
  CHECK(zplat_exists(ov) == 1);
  CHECK(open_hash(zdb, &ok) == want && ok);
  /* the obsolete sidecar is replaced by the first write */
  z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  ts_must(z, "UPDATE meta SET v='after' WHERE k='key9'");
  sqlite3_close(z);
  sqlite3 *pl = ts_open(plain, SQLITE_OPEN_READWRITE, NULL);
  ts_must(pl, "UPDATE line SET content = upper(content) WHERE id % 4 = 0;"
              "DELETE FROM link WHERE id % 3 = 0;"
              "UPDATE meta SET v='after' WHERE k='key9'");
  int rc = SQLITE_OK;
  uint64_t want2 = ts_content_hash(pl, &rc);
  sqlite3_close(pl);
  CHECK(open_hash(zdb, &ok) == want2 && ok);
  /* and compacting again finishes cleanly */
  CHECK_EQ(zvfs_compact(zdb, dst, 3, 2, 0, NULL, NULL, NULL, NULL, NULL, 0), 0);
  CHECK_EQ(zvfs_compact_swap(zdb, dst), 0);
  CHECK(zplat_exists(ov) == 0);
  CHECK(open_hash(zdb, &ok) == want2 && ok);
  CHECK(same_logical_bytes(plain, zdb));
  ts_remove_all(plain);
  ts_remove_all(zdb);
  remove(keep_base);
  remove(keep_ovl);
  printf("  compaction: busy/stale refusals, partial output and swap window ok\n");
}

/* ================= swap lock across processes ================= */
#if defined(_WIN32)
#include <process.h>
#include <windows.h>
typedef intptr_t proc_t;
#else
#include <sys/wait.h>
#include <unistd.h>
typedef pid_t proc_t;
#endif

static char g_self[1100];

static void sleep_ms(int ms) {
#if defined(_WIN32)
  Sleep((DWORD)ms);
#else
  usleep((useconds_t)ms * 1000);
#endif
}

static void touch(const char *p) {
  FILE *f = fopen(p, "wb");
  if (f) fclose(f);
}

/* Children: hold a read transaction, or <zdb>-zlck exclusively, for ms. */
static int child_zlck(const char *mode, const char *zdb, int ms) {
  char ready[1100];
  snprintf(ready, sizeof ready, "%s.ready", zdb);
  if (strcmp(mode, "hold") == 0) {
    sqlite3 *db = ts_open(zdb, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
    if (!db || ts_exec(db, "BEGIN") || ts_int(db, "SELECT count(*) FROM book") < 0)
      return 2;
    touch(ready);
    sleep_ms(ms);
    ts_exec(db, "COMMIT");
    sqlite3_close(db);
    return 0;
  }
  char lp[1100];
  snprintf(lp, sizeof lp, "%s-zlck", zdb);
  zplat_file *f = NULL;
  if (zplat_lockfile_open(lp, &f) || zplat_lockfile_try(f, 1)) return 2;
  touch(ready);
  sleep_ms(ms);
  zplat_lockfile_unlock(f);
  zplat_close(f);
  return 0;
}

static proc_t spawn_zlck(const char *mode, const char *zdb, int ms) {
  char ready[1100], msb[16];
  snprintf(ready, sizeof ready, "%s.ready", zdb);
  snprintf(msb, sizeof msb, "%d", ms);
  remove(ready);
#if defined(_WIN32)
  char q[1200];
  snprintf(q, sizeof q, "\"%s\"", zdb);
  proc_t p = _spawnl(_P_NOWAIT, g_self, g_self, "zlck", mode, q, msb, NULL);
#else
  proc_t p = fork();
  if (p == 0) {
    execl(g_self, g_self, "zlck", mode, zdb, msb, (char *)NULL);
    _exit(127);
  }
#endif
  for (int i = 0; i < 1000 && zplat_exists(ready) != 1; i++) sleep_ms(10);
  CHECK(zplat_exists(ready) == 1);
  return p;
}

static int wait_proc(proc_t p) {
#if defined(_WIN32)
  int st = -1;
  _cwait(&st, p, 0);
  return st;
#else
  int st = 0;
  waitpid(p, &st, 0);
  return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
#endif
}

static void test_swap_lock(void) {
  const char *plain = tmp_path("sl_plain.db");
  const char *zdb = tmp_path("sl.zdb");
  char dst[1100], ready[1100];
  snprintf(dst, sizeof dst, "%s.new", zdb);
  snprintf(ready, sizeof ready, "%s.ready", zdb);
  ts_remove_all(plain);
  ts_remove_all(zdb);
  sqlite3 *p = ts_open(plain, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  ts_make_base(p, 30, 5000);
  sqlite3_close(p);
  CHECK_EQ(ts_convert(plain, zdb), 0);
  sqlite3 *z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  ts_must(z, "UPDATE line SET content = upper(content) WHERE id % 4 = 0");
  sqlite3_close(z);
  int ok;
  uint64_t want = open_hash(zdb, &ok);
  CHECK(ok);

  /* another process reads: the swap must refuse, not rename under it */
  proc_t c = spawn_zlck("hold", zdb, 1500);
  CHECK_EQ(zvfs_compact(zdb, dst, 3, 2, 0, NULL, NULL, NULL, NULL, NULL, 0), 0);
  int busy = zvfs_compact_swap(zdb, dst);
  CHECK_EQ(busy, ZVFS_ERR_BUSY);
  CHECK_EQ(wait_proc(c), 0);
  CHECK_EQ(zvfs_compact_swap(zdb, dst), 0);
  CHECK(open_hash(zdb, &ok) == want && ok);

  /* a swap in progress elsewhere: an open waits for it */
  c = spawn_zlck("excl", zdb, 400);
  uint64_t t0 = zplat_now_ms();
  CHECK(open_hash(zdb, &ok) == want && ok);
  uint64_t waited = zplat_now_ms() - t0;
  CHECK_EQ(wait_proc(c), 0);
  CHECK(waited >= 200);

  /* and gives up with SQLITE_BUSY when it does not end */
  c = spawn_zlck("excl", zdb, 7000);
  sqlite3 *db = NULL;
  t0 = zplat_now_ms();
  int orc = sqlite3_open_v2(zdb, &db, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  uint64_t gave_up = zplat_now_ms() - t0;
  sqlite3_close(db);
  CHECK_EQ(orc, SQLITE_BUSY);
  CHECK_EQ(wait_proc(c), 0);
  CHECK(open_hash(zdb, &ok) == want && ok);
  printf("  swap lock: busy under another process's reader, open waited %llu ms,"
         " gave up after %llu ms\n",
         (unsigned long long)waited, (unsigned long long)gave_up);
  remove(ready);
  ts_remove_all(plain);
  ts_remove_all(zdb);
}

/* An open waiting for a swap elsewhere does not stall other files. */
typedef struct opener {
  const char *path;
  int rc;
  uint64_t ms;
} opener;

static void opener_main(void *p) {
  opener *o = (opener *)p;
  uint64_t t = zplat_now_ms();
  sqlite3 *db = NULL;
  o->rc = sqlite3_open_v2(o->path, &db, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  o->ms = zplat_now_ms() - t;
  sqlite3_close(db);
}

static void test_lock_wait_isolated(void) {
  const char *plain = tmp_path("lw_plain.db");
  const char *x = tmp_path("lw_x.zdb");
  const char *y = tmp_path("lw_y.zdb");
  ts_remove_all(plain);
  ts_remove_all(x);
  ts_remove_all(y);
  sqlite3 *p = ts_open(plain, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  ts_make_base(p, 5, 300);
  sqlite3_close(p);
  CHECK_EQ(ts_convert(plain, x), 0);
  CHECK_EQ(ts_convert(plain, y), 0);
  sqlite3 *yd = ts_open(y, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  CHECK(ts_int(yd, "SELECT count(*) FROM book") > 0);
  proc_t c = spawn_zlck("excl", x, 2500);
  opener o = {x, -1, 0};
  zplat_thread th;
  CHECK_EQ(zplat_thread_start(&th, opener_main, &o), 0);
  sleep_ms(300);
  uint64_t t = zplat_now_ms();
  sqlite3_close(yd);
  sqlite3 *pd = ts_open(plain, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  CHECK(ts_int(pd, "SELECT count(*) FROM book") > 0);
  sqlite3_close(pd);
  uint64_t other = zplat_now_ms() - t;
  zplat_thread_join(th);
  CHECK_EQ(wait_proc(c), 0);
  CHECK_EQ(o.rc, SQLITE_OK);
  CHECK(o.ms >= 1500);
  CHECK(other < 1000);
  printf("  lock wait: open of x waited %llu ms, other files meanwhile %llu ms\n",
         (unsigned long long)o.ms, (unsigned long long)other);
  ts_remove_all(plain);
  ts_remove_all(x);
  ts_remove_all(y);
}

/* ================= install of a downloaded base ================= */
static int g_install_stop = -1;
static int install_stop(int step) { return step == g_install_stop; }

static void test_install(void) {
  char plain[1024], zdb[1024], cand[1024], master[1024], kb[1024], ko[1024];
  char ov[1100], lck[1100], nw[1100], sh[1100], jr[1100], cov[1100], stg[1100];
  snprintf(plain, sizeof plain, "%s", tmp_path("in_plain.db"));
  snprintf(zdb, sizeof zdb, "%s", tmp_path("in.zdb"));
  snprintf(cand, sizeof cand, "%s", tmp_path("in_cand.zdb"));
  snprintf(master, sizeof master, "%s", tmp_path("in_master.zdb"));
  snprintf(kb, sizeof kb, "%s", tmp_path("in_keep.zdb"));
  snprintf(ko, sizeof ko, "%s", tmp_path("in_keep.zovl"));
  snprintf(ov, sizeof ov, "%s-zovl", zdb);
  snprintf(lck, sizeof lck, "%s-zlck", zdb);
  snprintf(nw, sizeof nw, "%s.new", zdb);
  snprintf(sh, sizeof sh, "%s-shm", zdb);
  snprintf(jr, sizeof jr, "%s-journal", zdb);
  snprintf(cov, sizeof cov, "%s-zovl", cand);
  snprintf(stg, sizeof stg, "%s.install", zdb);
  const char *all[] = {plain, zdb, cand, master};
  for (int i = 0; i < 4; i++) ts_remove_all(all[i]);
  remove(kb);
  remove(ko);

  sqlite3 *p = ts_open(plain, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  ts_make_base(p, 30, 5000);
  sqlite3_close(p);
  CHECK_EQ(ts_convert(plain, zdb), 0);
  int ok;
  uint64_t old_base = open_hash(zdb, &ok);
  CHECK(ok);
  sqlite3 *z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  ts_must(z, "UPDATE line SET content = upper(content) WHERE id % 4 = 0;"
             "DELETE FROM link WHERE id % 3 = 0;");
  sqlite3_close(z);
  uint64_t old_logical = open_hash(zdb, &ok);
  CHECK(ok && old_logical != old_base);
  CHECK_EQ(copy_file(zdb, kb), 0);
  CHECK_EQ(copy_file(ov, ko), 0);
  p = ts_open(plain, SQLITE_OPEN_READWRITE, NULL);
  ts_must(p, "DELETE FROM line WHERE id % 7 = 0; UPDATE meta SET v='new' WHERE k='key5'");
  sqlite3_close(p);
  CHECK_EQ(ts_convert(plain, master), 0);
  uint64_t new_hash = open_hash(master, &ok);
  CHECK(ok && new_hash != old_base && new_hash != old_logical);

  /* busy: open here, or in another process; nothing is touched */
  CHECK_EQ(copy_file(master, cand), 0);
  z = ts_open(zdb, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  CHECK_EQ(zvfs_install(zdb, cand, 0), ZVFS_ERR_BUSY);
  sqlite3_close(z);
  proc_t c = spawn_zlck("hold", zdb, 1500);
  CHECK_EQ(zvfs_install(zdb, cand, 0), ZVFS_ERR_BUSY);
  CHECK_EQ(wait_proc(c), 0);
  CHECK(zplat_exists(cand) == 1 && zplat_exists(ov) == 1);
  /* refusals before any delete: not a zdb, itself, a candidate with an overlay */
  CHECK_EQ(zvfs_install(zdb, plain, 0), ZVFS_ERR_NOT_ZDB);
  CHECK_EQ(zvfs_install(zdb, zdb, 0), ZVFS_ERR_INVALID);
  touch(cov);
  CHECK_EQ(zvfs_install(zdb, cand, 0), ZVFS_ERR_INVALID);
  remove(cov);
  CHECK(zplat_exists(ov) == 1 && open_hash(zdb, &ok) == old_logical && ok);

  /* the reverse order (rename, then delete) leaves a base that refuses to open */
  CHECK_EQ(zplat_rename_durable(cand, zdb), 0);
  open_hash(zdb, &ok);
  CHECK(!ok);

  /* a crash after each delete: the old content, or the old base alone */
  zvfs_test_install_step = install_stop;
  for (int stop = 0; stop < 5; stop++) {
    CHECK_EQ(copy_file(kb, zdb), 0);
    CHECK_EQ(copy_file(ko, ov), 0);
    CHECK_EQ(copy_file(master, cand), 0);
    touch(nw);
    touch(sh);
    touch(jr);
    g_install_stop = stop;
    CHECK_EQ(zvfs_install(zdb, cand, 0), ZVFS_ERR_IO);
    uint64_t h = open_hash(zdb, &ok);
    CHECK(ok && h == (stop < 3 ? old_logical : old_base));
    CHECK(zplat_exists(cand) == 1 && zplat_exists(stg) == 0);
    CHECK_EQ(zplat_exists(ov), stop < 3);
    CHECK_EQ(zplat_exists(nw), stop < 4);
    /* the retry completes it */
    g_install_stop = -1;
    CHECK_EQ(zvfs_install(zdb, cand, 0), 0);
    CHECK(open_hash(zdb, &ok) == new_hash && ok);
    CHECK(zplat_exists(cand) == 0 && zplat_exists(ov) == 0 && zplat_exists(nw) == 0);
    CHECK(zplat_exists(sh) == 0 && zplat_exists(jr) == 0 && zplat_exists(lck) == 1);
  }
  zvfs_test_install_step = NULL;

  /* first install, next to a foreign overlay (bound to another base) */
  remove(zdb);
  CHECK_EQ(copy_file(ko, ov), 0);
  CHECK_EQ(copy_file(master, cand), 0);
  CHECK_EQ(zvfs_install(zdb, cand, 0), 0);
  CHECK(zplat_exists(ov) == 0);
  CHECK(open_hash(zdb, &ok) == new_hash && ok);
  z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  ts_must(z, "UPDATE meta SET v='after' WHERE k='key9'");
  CHECK(ts_integrity_ok(z));
  sqlite3_close(z);
  printf("  install: busy here and in another process, refusals, 5 crash points,"
         " reverse order corrupt, foreign overlay removed\n");
  for (int i = 0; i < 4; i++) ts_remove_all(all[i]);
  remove(kb);
  remove(ko);
  snprintf(nw, sizeof nw, "%s.ready", zdb);
  remove(nw);
}

/* ---- install and compaction swap against openers and foreign handles ---- */
typedef struct swap_opener {
  const char *path;
  uint64_t hash;
  int ok;
} swap_opener;

static void swap_opener_main(void *p) {
  swap_opener *o = (swap_opener *)p;
  o->hash = open_hash(o->path, &o->ok);
}

static swap_opener g_so;
static zplat_thread g_so_th;

/* An isolate opening mid-swap: it must wait without holding the base. */
static void start_opener(void) {
  zvfs_test_swap_locked = NULL;
  CHECK_EQ(zplat_thread_start(&g_so_th, swap_opener_main, &g_so), 0);
  sleep_ms(300);
}

#if defined(_WIN32)
/* What SQLite's win32 VFS, antivirus or an indexer hold: no FILE_SHARE_DELETE. */
static HANDLE g_foreign;
static void close_foreign(void *p) {
  sleep_ms(*(int *)p);
  CloseHandle(g_foreign);
}
static void open_foreign(const char *path) {
  g_foreign = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                          NULL, OPEN_EXISTING, 0, NULL);
  CHECK(g_foreign != INVALID_HANDLE_VALUE);
}
#endif

/* A directory on another file system than tmp_path, or NULL. */
static const char *other_volume(void) {
  const char *d = getenv("ZVFS_TEST_OTHER_VOLUME");
  if (d && *d) return d;
#if defined(__linux__)
  struct stat a, b;
  if (stat("/dev/shm", &a) == 0 && stat(tmp_path("."), &b) == 0 &&
      a.st_dev != b.st_dev)
    return "/dev/shm";
#endif
  return NULL;
}

static void test_install_failures(void) {
  char plain[1024], zdb[1024], cand[1024], master[1024], kb[1024], ko[1024];
  char ov[1100], nw[1100], stg[1100], xv[1100];
  snprintf(plain, sizeof plain, "%s", tmp_path("if_plain.db"));
  snprintf(zdb, sizeof zdb, "%s", tmp_path("if.zdb"));
  snprintf(cand, sizeof cand, "%s", tmp_path("if_cand.zdb"));
  snprintf(master, sizeof master, "%s", tmp_path("if_master.zdb"));
  snprintf(kb, sizeof kb, "%s", tmp_path("if_keep.zdb"));
  snprintf(ko, sizeof ko, "%s", tmp_path("if_keep.zovl"));
  snprintf(ov, sizeof ov, "%s-zovl", zdb);
  snprintf(nw, sizeof nw, "%s.new", zdb);
  snprintf(stg, sizeof stg, "%s.install", zdb);
  const char *all[] = {plain, zdb, cand, master};
  for (int i = 0; i < 4; i++) ts_remove_all(all[i]);
  sqlite3 *p = ts_open(plain, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  ts_make_base(p, 30, 5000);
  sqlite3_close(p);
  CHECK_EQ(ts_convert(plain, zdb), 0);
  sqlite3 *z = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  ts_must(z, "UPDATE line SET content = upper(content) WHERE id % 5 = 0");
  sqlite3_close(z);
  int ok;
  uint64_t old_logical = open_hash(zdb, &ok);
  CHECK(ok);
  CHECK_EQ(copy_file(zdb, kb), 0);
  CHECK_EQ(copy_file(ov, ko), 0);
  p = ts_open(plain, SQLITE_OPEN_READWRITE, NULL);
  ts_must(p, "DELETE FROM line WHERE id % 6 = 0");
  sqlite3_close(p);
  CHECK_EQ(ts_convert(plain, master), 0);
  uint64_t new_hash = open_hash(master, &ok);
  CHECK(ok && new_hash != old_logical);
#define RESET_PAIR()                        \
  do {                                      \
    CHECK_EQ(copy_file(kb, zdb), 0);        \
    CHECK_EQ(copy_file(ko, ov), 0);         \
    CHECK_EQ(copy_file(master, cand), 0);   \
  } while (0)
#define UNTOUCHED()                                                       \
  CHECK(zplat_exists(ov) == 1 && zplat_exists(cand) == 1 &&               \
        zplat_exists(stg) == 0 && open_hash(zdb, &ok) == old_logical && ok)

  /* an open that meets the install waits for it and gets the new base */
  RESET_PAIR();
  g_so.path = zdb;
  zvfs_test_swap_locked = start_opener;
  CHECK_EQ(zvfs_install(zdb, cand, 0), 0);
  zvfs_test_swap_locked = NULL;
  zplat_thread_join(g_so_th);
  CHECK(g_so.ok && g_so.hash == new_hash);
  CHECK(zplat_exists(ov) == 0 && open_hash(zdb, &ok) == new_hash && ok);

  /* the same for the compaction swap */
  RESET_PAIR();
  CHECK_EQ(zvfs_compact(zdb, nw, 3, 2, 0, NULL, NULL, NULL, NULL, NULL, 0), 0);
  zvfs_test_swap_locked = start_opener;
  CHECK_EQ(zvfs_compact_swap(zdb, nw), 0);
  zvfs_test_swap_locked = NULL;
  zplat_thread_join(g_so_th);
  CHECK(g_so.ok && g_so.hash == old_logical);
  CHECK(zplat_exists(ov) == 0 && zplat_exists(nw) == 0);

  /* a corrupt frame passes the open checks; the full verify refuses it */
  RESET_PAIR();
  uint8_t *d;
  size_t n;
  CHECK_EQ(read_file(cand, &d, &n), 0);
  d[n / 2] ^= 0x5A;
  CHECK_EQ(write_file(cand, d, n), 0);
  free(d);
  CHECK_EQ(zvfs_install(zdb, cand, ZVFS_INSTALL_VERIFY), ZVFS_ERR_CORRUPT);
  UNTOUCHED();
  CHECK_EQ(copy_file(master, cand), 0);
  CHECK_EQ(zvfs_install(zdb, cand, ZVFS_INSTALL_VERIFY), 0);
  CHECK(open_hash(zdb, &ok) == new_hash && ok);
  int checks = 3;

#if defined(_WIN32)
  /* a foreign handle that outlasts the retries: busy before any delete */
  RESET_PAIR();
  open_foreign(zdb);
  uint64_t t0 = zplat_now_ms();
  CHECK_EQ(zvfs_install(zdb, cand, 0), ZVFS_ERR_BUSY);
  uint64_t waited = zplat_now_ms() - t0;
  CloseHandle(g_foreign);
  CHECK(waited >= ZPLAT_RETRY_MS / 2);
  UNTOUCHED();
  /* and one that goes away while retrying */
  open_foreign(zdb);
  int ms = 300;
  zplat_thread th;
  CHECK_EQ(zplat_thread_start(&th, close_foreign, &ms), 0);
  CHECK_EQ(zvfs_install(zdb, cand, 0), 0);
  zplat_thread_join(th);
  CHECK(zplat_exists(ov) == 0 && open_hash(zdb, &ok) == new_hash && ok);
  checks += 2;
#endif

  /* a candidate on another volume fails at staging, before any delete */
  const char *other = other_volume();
  if (other) {
    RESET_PAIR();
    snprintf(xv, sizeof xv, "%s/if_xv_cand.zdb", other);
    CHECK_EQ(copy_file(master, xv), 0);
    CHECK_EQ(zvfs_install(zdb, xv, 0), ZVFS_ERR_IO);
    CHECK(zplat_exists(xv) == 1);
    UNTOUCHED();
    remove(xv);
    checks++;
  }
  printf("  install failures: %d scenarios (opener mid-install and mid-compaction,"
         " corrupt frame%s%s)\n",
         checks,
#if defined(_WIN32)
         ", foreign handle held and released",
#else
         "",
#endif
         other ? ", other volume" : ", other volume skipped");
#undef RESET_PAIR
#undef UNTOUCHED
  for (int i = 0; i < 4; i++) ts_remove_all(all[i]);
  remove(kb);
  remove(ko);
}

/* ================= concurrency: WAL writer + reader threads ================= */
typedef struct cc_arg {
  const char *path;
  volatile int64_t *stop;
  int reads, errors, busy;
} cc_arg;

/* acct holds 200 balances summing to 0; ver.h is the hash of acct. */
static uint64_t acct_hash(sqlite3 *db, int *rc) {
  return ts_hash_rows(db, "SELECT id, bal FROM acct ORDER BY id", 99, rc);
}

static void cc_reader(void *p) {
  cc_arg *a = (cc_arg *)p;
  sqlite3 *db = ts_open(a->path, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  if (!db) {
    a->errors++;
    return;
  }
  while (!zplat_atomic_load(a->stop)) {
    if (ts_exec(db, "BEGIN") != SQLITE_OK) {
      a->busy++;
      continue;
    }
    int rc = SQLITE_OK;
    uint64_t h = acct_hash(db, &rc);
    int64_t sum = ts_int(db, "SELECT sum(bal) FROM acct");
    int64_t stored = ts_int(db, "SELECT h FROM ver");
    int64_t n = ts_int(db, "SELECT count(*) FROM line WHERE content LIKE 'cc%'");
    int64_t want_n = ts_int(db, "SELECT n FROM ver");
    ts_exec(db, "COMMIT");
    if (rc == SQLITE_BUSY) {
      a->busy++;
      continue;
    }
    if (rc || sum != 0 || (int64_t)(h & 0x7fffffffffffffffll) != stored ||
        n != want_n)
      a->errors++;
    a->reads++;
  }
  sqlite3_close(db);
}

static void test_concurrent_wal(int readers, int txns) {
  const char *plain = tmp_path("cc_plain.db");
  const char *zdb = tmp_path("cc.zdb");
  ts_remove_all(plain);
  ts_remove_all(zdb);
  sqlite3 *p = ts_open(plain, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  ts_make_base(p, 30, 6000);
  ts_must(p, "CREATE TABLE acct(id INTEGER PRIMARY KEY, bal INT);"
             "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<200)"
             " INSERT INTO acct SELECT i, 0 FROM n;"
             "CREATE TABLE ver(h INT, n INT); INSERT INTO ver VALUES(0, 0);");
  int rc = SQLITE_OK;
  uint64_t h0 = acct_hash(p, &rc);
  char sql[512];
  snprintf(sql, sizeof sql, "UPDATE ver SET h=%lld",
           (long long)(h0 & 0x7fffffffffffffffll));
  ts_must(p, sql);
  sqlite3_close(p);
  CHECK_EQ(ts_convert(plain, zdb), 0);
  sqlite3 *w = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  ts_must(w, "PRAGMA journal_mode=WAL");
  ts_must(w, "PRAGMA wal_autocheckpoint=50");
  volatile int64_t stop = 0;
  cc_arg args[8];
  zplat_thread th[8];
  for (int i = 0; i < readers; i++) {
    memset(&args[i], 0, sizeof args[i]);
    args[i].path = zdb;
    args[i].stop = &stop;
    zplat_thread_start(&th[i], cc_reader, &args[i]);
  }
  g_rng = 77;
  int64_t lines = 0;
  for (int t = 0; t < txns; t++) {
    if (ts_exec(w, "BEGIN IMMEDIATE") != SQLITE_OK) {
      t--;
      continue;
    }
    for (int k = 0; k < 20; k++) {
      int a = 1 + (int)(rnd() % 200), b = 1 + (int)(rnd() % 200);
      int amt = (int)(rnd() % 1000);
      snprintf(sql, sizeof sql,
               "UPDATE acct SET bal=bal-%d WHERE id=%d; UPDATE acct SET bal=bal+%d "
               "WHERE id=%d",
               amt, a, amt, b);
      ts_must(w, sql);
    }
    int add = 1 + (int)(rnd() % 50);
    snprintf(sql, sizeof sql,
             "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<%d)"
             " INSERT INTO line(bookId, lineIndex, content) SELECT 1, i, printf('cc %d"
             " %%.*c', i, 'c') FROM n",
             add, t);
    ts_must(w, sql);
    lines += add;
    rc = SQLITE_OK;
    uint64_t h = acct_hash(w, &rc);
    snprintf(sql, sizeof sql, "UPDATE ver SET h=%lld, n=%lld",
             (long long)(h & 0x7fffffffffffffffll), (long long)lines);
    ts_must(w, sql);
    ts_must(w, "COMMIT");
    if (t % 40 == 39) ts_exec(w, "PRAGMA wal_checkpoint(TRUNCATE)");
  }
  zplat_atomic_store(&stop, 1);
  int reads = 0, errors = 0, busy = 0;
  for (int i = 0; i < readers; i++) {
    zplat_thread_join(th[i]);
    reads += args[i].reads;
    errors += args[i].errors;
    busy += args[i].busy;
  }
  ts_exec(w, "PRAGMA wal_checkpoint(TRUNCATE)");
  ts_must(w, "PRAGMA journal_mode=DELETE");
  CHECK(ts_integrity_ok(w));
  rc = SQLITE_OK;
  uint64_t live = ts_content_hash(w, &rc);
  sqlite3_close(w);
  /* a fresh state replays only what the seals committed */
  sqlite3 *fresh = ts_open(zdb, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  CHECK(fresh && ts_integrity_ok(fresh));
  rc = SQLITE_OK;
  CHECK(ts_content_hash(fresh, &rc) == live);
  sqlite3_close(fresh);
  CHECK_EQ(errors, 0);
  CHECK(reads > 0);
  zvfs_stats s;
  zvfs_get_stats(&s);
  printf("  concurrency: %d readers, %d txns, %d consistent snapshots, %d busy, "
         "%d errors\n",
         readers, txns, reads, busy, errors);
  ts_remove_all(plain);
  ts_remove_all(zdb);
}

int main(int argc, char **argv) {
  setvbuf(stdout, NULL, _IONBF, 0); /* progress stays visible in logs */
  sqlite3_auto_extension((void (*)(void))sqlite3_otzariazvfs_init);
  sqlite3 *m = NULL;
  sqlite3_open(":memory:", &m);
  sqlite3_close(m);
  if (argc == 5 && strcmp(argv[1], "zlck") == 0)
    return child_zlck(argv[2], argv[3], atoi(argv[4]));
#if defined(_WIN32)
  GetModuleFileNameA(NULL, g_self, sizeof g_self);
#else
  snprintf(g_self, sizeof g_self, "%s", argv[0]);
#endif
  CHECK(zvfs_is_registered());
  ts_verbose = getenv("ZVFS_VERBOSE") != NULL;
  const char *fz = getenv("ZVFS_FUZZ_ITERS");
  int fuzz = fz ? atoi(fz) : 3000;
  printf("overlay codec\n");
  test_ovl_handmade();
  test_ovl_two_processes();
  test_ovl_concurrent_seal();
  test_ovl_sparse_and_failures();
  test_ovl_roundtrip_and_torn(4096);
  test_ovl_roundtrip_and_torn(1024);
  test_ovl_fuzz(fuzz);
  printf("sql equivalence\n");
  test_sql_equivalence(4096, 400);
  test_sql_equivalence(1024, 200);
  test_sql_equivalence(65536, 30);
  test_compaction_windows();
  test_stale_sidecar();
  test_derived_newer();
  test_compact_freelist(1, ZDB_LOCK_BYTE);
  test_compact_freelist(4, ZDB_LOCK_BYTE);
  test_compact_freelist(1, 700u << 10); /* runs of copies end at the gap */
  test_swap_lock();
  test_lock_wait_isolated();
  test_install();
  test_install_failures();
  printf("concurrency\n");
  test_concurrent_wal(4, 400);
  free(g_mb.p);
  free(g_base_plain);
  zvfs_stats s;
  zvfs_get_stats(&s);
  CHECK_EQ(s.open_files, 0);
  if (g_failures) {
    fprintf(stderr, "%d check(s) failed\n", g_failures);
    return 1;
  }
  printf("all write tests passed\n");
  return 0;
}
