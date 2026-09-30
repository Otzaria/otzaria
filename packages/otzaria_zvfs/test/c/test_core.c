/* Core unit tests: header codec, converter, reader, cache, corruption fuzz. */
#include "test_common.h"
#include "zvfs_internal.h"

#define ZSTD_STATIC_LINKING_ONLY
#include "zdict.h"
#include "zstd.h"

typedef struct {
  const uint8_t *p;
  size_t n;
} membuf;

static int mem_rd(void *ctx, void *buf, size_t n, uint64_t off) {
  membuf *m = (membuf *)ctx;
  if (off >= m->n) {
    memset(buf, 0, n);
    return ZVFS_ERR_SHORT_READ;
  }
  size_t avail = m->n - (size_t)off;
  size_t k = avail < n ? avail : n;
  memcpy(buf, m->p + off, k);
  if (k < n) {
    memset((uint8_t *)buf + k, 0, n - k);
    return ZVFS_ERR_SHORT_READ;
  }
  return ZVFS_OK;
}

static const char *k_words[] = {"alpha ", "beta ",  "gamma ", "delta ",
                                "sefer ", "perek ", "pasuk ", "halacha ",
                                "0123 ",  "<b>",    "</b> ",  "\n"};

/* Builds a fake SQLite image: valid 100-byte header + compressible pages. */
static uint8_t *make_source(uint32_t ps, uint32_t pages, int wal) {
  size_t n = (size_t)ps * pages;
  uint8_t *s = (uint8_t *)malloc(n);
  for (size_t i = 0; i < n;) {
    if (rnd() % 8 == 0) {
      s[i++] = (uint8_t)rnd();
      continue;
    }
    const char *w = k_words[rnd() % (sizeof k_words / sizeof k_words[0])];
    size_t l = strlen(w);
    for (size_t j = 0; j < l && i < n; j++) s[i++] = (uint8_t)w[j];
  }
  memset(s, 0, 100);
  memcpy(s, "SQLite format 3", 16);
  uint32_t pv = ps == 65536 ? 1 : ps;
  s[16] = (uint8_t)(pv >> 8);
  s[17] = (uint8_t)pv;
  s[18] = s[19] = (uint8_t)(wal ? 2 : 1);
  s[27] = 7;              /* change counter */
  s[28] = (uint8_t)(pages >> 24);
  s[29] = (uint8_t)(pages >> 16);
  s[30] = (uint8_t)(pages >> 8);
  s[31] = (uint8_t)pages;
  s[95] = 7;              /* version-valid-for == change counter */
  return s;
}

static int convert_buf(const char *dst, const uint8_t *src, size_t n,
                       const void *dict, size_t dict_len, int threads,
                       uint32_t frame_pages, uint64_t batch, int zstd_feed,
                       volatile int32_t *cancel, zvfs_info *info) {
  zvfs_conv *c = NULL;
  int rc = zvfs_conv_create(dst, dict, dict_len, dict ? "test" : NULL, 5,
                            threads, frame_pages, batch, cancel, &c);
  if (rc) return rc;
  const uint8_t *feed = src;
  size_t feed_n = n;
  uint8_t *zbuf = NULL;
  if (zstd_feed) {
    size_t cap = ZSTD_compressBound(n);
    zbuf = (uint8_t *)malloc(cap);
    feed_n = ZSTD_compress(zbuf, cap, src, n, 3);
    feed = zbuf;
  }
  size_t off = 0;
  while (!rc && off < feed_n) {
    size_t k = 1 + (size_t)(rnd() % 70000);
    if (k > feed_n - off) k = feed_n - off;
    rc = zstd_feed ? zvfs_conv_feed_zstd(c, feed + off, k)
                   : zvfs_conv_feed(c, feed + off, k);
    off += k;
  }
  if (!rc) rc = zvfs_conv_finish(c, info);
  if (rc && getenv("ZVFS_TEST_VERBOSE"))
    fprintf(stderr, "convert: %s\n", zvfs_conv_error(c));
  zvfs_conv_destroy(c);
  free(zbuf);
  return rc;
}

static void test_header_codec(void) {
  zdb_header h;
  memset(&h, 0, sizeof h);
  h.major = ZDB_FORMAT_MAJOR;
  h.header_size = ZDB_HEADER_SIZE;
  h.page_size = 4096;
  h.frame_pages = 1;
  h.codec = ZDB_CODEC_ZSTD_MAGICLESS;
  h.logical_size = 4096 * 10;
  h.frame_count = 10;
  h.dict_offset = ZDB_HEADER_SIZE;
  h.index_offset = ZDB_HEADER_SIZE + 100;
  h.index_length = 11 * 8;
  snprintf(h.dict_name, sizeof h.dict_name, "x");
  uint8_t raw[ZDB_HEADER_CORE];
  zdb_header_encode(&h, raw);
  zdb_header d;
  CHECK_EQ(zdb_header_decode(raw, &d), ZVFS_OK);
  CHECK_EQ(d.logical_size, h.logical_size);
  CHECK_EQ(d.index_offset, h.index_offset);

  uint8_t bad[ZDB_HEADER_CORE];
  memcpy(bad, raw, sizeof bad);
  bad[40] ^= 1;
  CHECK_EQ(zdb_header_decode(bad, &d), ZVFS_ERR_CORRUPT);

  zdb_header v = h;
  v.major = 2;
  zdb_header_encode(&v, bad);
  CHECK_EQ(zdb_header_decode(bad, &d), ZVFS_ERR_UNSUPPORTED);
  v = h;
  v.incompat = 4;
  zdb_header_encode(&v, bad);
  CHECK_EQ(zdb_header_decode(bad, &d), ZVFS_ERR_UNSUPPORTED);
  v = h;
  v.minor = 9;
  v.compat = 0x80;
  zdb_header_encode(&v, bad);
  CHECK_EQ(zdb_header_decode(bad, &d), ZVFS_OK);
  v = h;
  v.page_size = 3000;
  zdb_header_encode(&v, bad);
  CHECK_EQ(zdb_header_decode(bad, &d), ZVFS_ERR_CORRUPT);
  v = h;
  v.frame_count = 11;
  zdb_header_encode(&v, bad);
  CHECK_EQ(zdb_header_decode(bad, &d), ZVFS_ERR_CORRUPT);
  v = h;
  v.logical_size = 4096 * 10 + 1;
  zdb_header_encode(&v, bad);
  CHECK_EQ(zdb_header_decode(bad, &d), ZVFS_ERR_CORRUPT);
  memcpy(bad, raw, sizeof bad);
  bad[0] = 'X';
  CHECK_EQ(zdb_header_decode(bad, &d), ZVFS_ERR_NOT_ZDB);
}

static void *train_small_dict(const uint8_t *src, uint32_t ps, uint32_t pages,
                              size_t *len) {
  size_t *lens = (size_t *)malloc(pages * sizeof(size_t));
  for (uint32_t i = 0; i < pages; i++) lens[i] = ps;
  void *d = malloc(16384);
  size_t r = ZDICT_trainFromBuffer(d, 16384, src, lens, pages);
  free(lens);
  if (ZDICT_isError(r)) {
    free(d);
    return NULL;
  }
  *len = r;
  return d;
}

static void check_roundtrip(uint32_t ps, uint32_t pages, uint32_t fp,
                            int threads, uint64_t batch, int use_dict,
                            int wal, int zstd_feed) {
  uint8_t *src = make_source(ps, pages, wal);
  size_t n = (size_t)ps * pages;
  size_t dl = 0;
  void *dict = use_dict ? train_small_dict(src, ps, pages, &dl) : NULL;
  CHECK(!use_dict || dict);
  const char *dst = tmp_path("rt.zdb");
  zvfs_info info;
  int rc = convert_buf(dst, src, n, dict, dl, threads, fp, batch, zstd_feed,
                       NULL, &info);
  CHECK_EQ(rc, ZVFS_OK);
  if (rc) {
    free(src);
    free(dict);
    return;
  }
  CHECK_EQ(info.logical_size, n);
  CHECK_EQ(info.page_size, ps);
  CHECK_EQ(info.compat_features & ZDB_COMPAT_WAL_HEADER_PATCHED, wal ? 1 : 0);
  if (wal) src[18] = src[19] = 1;
  CHECK_EQ(info.content_xxh64, zvfs_xxh64(src, n, 0));

  CHECK_EQ(zvfs_probe_path(dst), 1);
  zvfs_reader *r = NULL;
  CHECK_EQ(zvfs_reader_open(dst, &r), ZVFS_OK);
  if (r) {
    CHECK_EQ(zvfs_reader_verify(r, NULL, NULL), ZVFS_OK);
    uint8_t *all = (uint8_t *)malloc(n);
    CHECK_EQ(zvfs_reader_read(r, all, (int64_t)n, 0), ZVFS_OK);
    CHECK(memcmp(all, src, n) == 0);
    for (int i = 0; i < 2000; i++) {
      uint64_t off = rnd() % n;
      uint64_t len = 1 + rnd() % (3 * (uint64_t)ps);
      if (off + len > n) len = n - off;
      CHECK_EQ(zvfs_reader_read(r, all, (int64_t)len, (int64_t)off), ZVFS_OK);
      CHECK(memcmp(all, src + off, (size_t)len) == 0);
    }
    memset(all, 0xAA, 64);
    CHECK_EQ(zvfs_reader_read(r, all, 64, (int64_t)n - 32),
             ZVFS_ERR_SHORT_READ);
    CHECK(memcmp(all, src + n - 32, 32) == 0);
    CHECK(all[32] == 0 && all[63] == 0);
    free(all);
    zvfs_reader_close(r);
  }
  remove(dst);
  free(src);
  free(dict);
}

static void test_roundtrips(void) {
  check_roundtrip(4096, 257, 1, 1, 64 << 10, 0, 0, 0);
  check_roundtrip(4096, 257, 1, 4, 64 << 10, 1, 0, 0);
  check_roundtrip(4096, 257, 3, 3, 40 << 10, 1, 0, 0);
  check_roundtrip(512, 999, 1, 8, 7 << 10, 1, 1, 0);
  check_roundtrip(16384, 64, 1, 4, 1 << 20, 1, 0, 1);
  check_roundtrip(65536, 9, 2, 2, 1, 0, 1, 1);
}

static void test_converter_errors(void) {
  uint32_t ps = 4096, pages = 20;
  uint8_t *src = make_source(ps, pages, 0);
  size_t n = (size_t)ps * pages;
  const char *dst = tmp_path("err.zdb");
  CHECK_EQ(convert_buf(dst, src, n - 100, NULL, 0, 2, 1, 1 << 16, 0, NULL, NULL),
           ZVFS_ERR_INVALID);
  CHECK_EQ(convert_buf(dst, src, n - ps, NULL, 0, 2, 1, 1 << 16, 0, NULL, NULL),
           ZVFS_ERR_INVALID);
  uint8_t keep = src[0];
  src[0] = 'X';
  CHECK_EQ(convert_buf(dst, src, n, NULL, 0, 2, 1, 1 << 16, 0, NULL, NULL),
           ZVFS_ERR_INVALID);
  src[0] = keep;
  volatile int32_t cancel = 1;
  CHECK_EQ(convert_buf(dst, src, n, NULL, 0, 2, 1, 1 << 16, 0, &cancel, NULL),
           ZVFS_ERR_CANCELLED);

  zvfs_conv *c = NULL;
  CHECK_EQ(zvfs_conv_create(dst, NULL, 0, NULL, 3, 2, 1, 1 << 16, NULL, &c),
           ZVFS_OK);
  size_t cap = ZSTD_compressBound(n);
  uint8_t *z = (uint8_t *)malloc(cap);
  size_t zl = ZSTD_compress(z, cap, src, n, 3);
  CHECK_EQ(zvfs_conv_feed_zstd(c, z, zl - 9), ZVFS_OK);
  CHECK(zvfs_conv_finish(c, NULL) != ZVFS_OK);
  zvfs_conv_destroy(c);
  free(z);

  uint8_t junk[64];
  memset(junk, 7, sizeof junk);
  write_file(dst, junk, sizeof junk);
  CHECK_EQ(zvfs_probe_path(dst), 0);
  zvfs_reader *r = NULL;
  CHECK_EQ(zvfs_reader_open(dst, &r), ZVFS_ERR_NOT_ZDB);
  remove(dst);
  free(src);
}

/* Random mutations must never crash; accepted content must be intact. */
static void test_fuzz(int iters) {
  uint32_t ps = 1024, pages = 48;
  uint8_t *src = make_source(ps, pages, 0);
  size_t n = (size_t)ps * pages;
  for (int variant = 0; variant < 2; variant++) {
    size_t dl = 0;
    void *dict = variant ? train_small_dict(src, ps, pages, &dl) : NULL;
    const char *dst = tmp_path("fuzz.zdb");
    CHECK_EQ(convert_buf(dst, src, n, dict, dl, 2, variant ? 2 : 1, 1 << 14, 0,
                         NULL, NULL),
             ZVFS_OK);
    uint8_t *good;
    size_t good_n;
    CHECK_EQ(read_file(dst, &good, &good_n), 0);
    remove(dst);
    zdb_header h;
    CHECK_EQ(zdb_header_decode(good, &h), ZVFS_OK);
    uint8_t *m = (uint8_t *)malloc(good_n + 64);
    uint8_t *out = (uint8_t *)malloc(n);
    int opened = 0, verified = 0;
    for (int it = 0; it < iters; it++) {
      memcpy(m, good, good_n);
      size_t mn = good_n;
      int muts = 1 + (int)(rnd() % 4);
      for (int k = 0; k < muts; k++) {
        uint64_t lo = 0, hi = good_n;
        switch (rnd() % 6) {
          case 0: lo = 0; hi = ZDB_HEADER_CORE; break;
          case 1: lo = ZDB_HEADER_CORE; hi = ZDB_HEADER_SIZE; break;
          case 2: lo = h.dict_offset; hi = h.dict_offset + h.dict_length + 1; break;
          case 3: lo = h.dict_offset + h.dict_length; hi = h.index_offset; break;
          case 4: lo = h.index_offset; hi = good_n; break;
          default: break;
        }
        if (hi <= lo) hi = lo + 1;
        size_t pos = (size_t)(lo + rnd() % (hi - lo));
        if (pos >= mn) pos = mn - 1;
        switch (rnd() % 4) {
          case 0: m[pos] ^= (uint8_t)(1u << (rnd() % 8)); break;
          case 1: m[pos] = (uint8_t)rnd(); break;
          case 2: mn = pos + 1; break;
          default: {
            size_t len = 1 + rnd() % 16;
            for (size_t j = 0; j < len && pos + j < mn; j++) m[pos + j] = (uint8_t)rnd();
          }
        }
      }
      membuf mb = {m, mn};
      zdb_file *f = NULL;
      if (zdb_file_load(mem_rd, &mb, mn, &f) != ZVFS_OK) continue;
      opened++;
      zvfs_set_cache_budget((rnd() % 3) * 4096);
      int rc = zdb_file_read(f, mem_rd, &mb, out, n, 0);
      if (rc == ZVFS_OK && zvfs_xxh64(out, n, 0) == f->h.content_xxh64) {
        verified++;
        CHECK(f->h.logical_size == n && memcmp(out, src, n) == 0);
      }
      for (int j = 0; j < 8; j++) {
        uint64_t off = rnd() % (f->h.logical_size + 100);
        uint64_t len = 1 + rnd() % 5000;
        if (len > n) len = n;
        zdb_file_read(f, mem_rd, &mb, out, len, off);
      }
      zdb_file_free(f);
    }
    printf("fuzz variant %d: %d iterations, %d opened, %d fully intact\n",
           variant, iters, opened, verified);
    free(m);
    free(out);
    free(good);
    free(dict);
  }
  zvfs_set_cache_budget(16 << 20);
  free(src);
}

/* Every truncation length and one bit flip at every offset, exhaustively. */
static void test_exhaustive_damage(void) {
  uint32_t ps = 1024, pages = 24;
  uint8_t *src = make_source(ps, pages, 0);
  size_t n = (size_t)ps * pages;
  uint8_t *out = (uint8_t *)malloc(n);
  zvfs_set_cache_budget(0);
  for (int variant = 0; variant < 2; variant++) {
    size_t dl = 0;
    void *dict = variant ? train_small_dict(src, ps, pages, &dl) : NULL;
    const char *dst = tmp_path("exh.zdb");
    CHECK_EQ(convert_buf(dst, src, n, dict, dl, 2, variant ? 2 : 1, 1 << 13, 0,
                         NULL, NULL),
             ZVFS_OK);
    uint8_t *good;
    size_t good_n;
    CHECK_EQ(read_file(dst, &good, &good_n), 0);
    remove(dst);
    zdb_header h;
    CHECK_EQ(zdb_header_decode(good, &h), ZVFS_OK);
    uint8_t *m = (uint8_t *)malloc(good_n);
    int frame_benign = 0, frame_detected = 0;
    for (size_t off = 0; off < good_n; off++) {
      /* truncated file, reported size either honest or stale */
      membuf tb = {good, off};
      zdb_file *f = NULL;
      CHECK(zdb_file_load(mem_rd, &tb, off, &f) != ZVFS_OK);
      CHECK(zdb_file_load(mem_rd, &tb, good_n, &f) != ZVFS_OK);

      memcpy(m, good, good_n);
      m[off] ^= (uint8_t)(1u << (off % 8));
      membuf fb = {m, good_n};
      int in_reserved = off >= ZDB_HEADER_CORE && off < ZDB_HEADER_SIZE;
      int in_frames = off >= h.dict_offset + h.dict_length && off < h.index_offset;
      int rc = zdb_file_load(mem_rd, &fb, good_n, &f);
      if (!in_reserved && !in_frames) {
        CHECK(rc != ZVFS_OK);
        if (rc == ZVFS_OK) zdb_file_free(f);
        continue;
      }
      CHECK_EQ(rc, ZVFS_OK);
      if (rc) continue;
      rc = zdb_file_read(f, mem_rd, &fb, out, n, 0);
      CHECK(rc != ZVFS_OK || memcmp(out, src, n) == 0);
      if (in_reserved) CHECK_EQ(rc, ZVFS_OK);
      if (in_frames) {
        /* a flip zstd ignores (unused header bit, entropy slack) decodes
           to identical bytes, which the check above already proved */
        CHECK(rc == ZVFS_OK || rc == ZVFS_ERR_CORRUPT);
        if (rc == ZVFS_OK) frame_benign++;
        else frame_detected++;
      }
      zdb_file_free(f);
    }

    /* the file shrinks after a successful open */
    membuf full = {good, good_n};
    zdb_file *f = NULL;
    CHECK_EQ(zdb_file_load(mem_rd, &full, good_n, &f), ZVFS_OK);
    for (size_t off = 0; f && off < good_n; off++) {
      membuf sb = {good, off};
      int rc = zdb_file_read(f, mem_rd, &sb, out, n, 0);
      if (off < h.index_offset) CHECK_EQ(rc, ZVFS_ERR_CORRUPT);
      else CHECK(rc == ZVFS_OK && memcmp(out, src, n) == 0);
    }
    zdb_file_free(f);
    printf("exhaustive variant %d: %zu offsets, frame flips: %d detected, "
           "%d decoded identically\n",
           variant, good_n, frame_detected, frame_benign);
    free(m);
    free(good);
    free(dict);
  }
  zvfs_set_cache_budget(16 << 20);
  free(out);
  free(src);
}

/* A source compressed with a window above zstd's 128MB decoder default,
   like `zstd --long=31` (how seforim.db.zst is published). */
static void test_zstd_long_window_source(void) {
  uint32_t ps = 4096, pages = 40;
  uint8_t *src = make_source(ps, pages, 0);
  size_t n = (size_t)ps * pages;
  ZSTD_CCtx *cc = ZSTD_createCCtx();
  ZSTD_CCtx_setParameter(cc, ZSTD_c_windowLog, 28);
  ZSTD_CCtx_setParameter(cc, ZSTD_c_enableLongDistanceMatching, 1);
  size_t cap = ZSTD_compressBound(n) + 1024;
  uint8_t *z = (uint8_t *)malloc(cap);
  ZSTD_outBuffer zo = {z, cap, 0};
  ZSTD_inBuffer zi = {src, n, 0};
  /* continue-then-end keeps the size unknown, so the window stays 2^28 */
  CHECK(!ZSTD_isError(ZSTD_compressStream2(cc, &zo, &zi, ZSTD_e_continue)));
  ZSTD_inBuffer empty = {NULL, 0, 0};
  CHECK_EQ(ZSTD_compressStream2(cc, &zo, &empty, ZSTD_e_end), 0);
  ZSTD_freeCCtx(cc);
  ZSTD_frameHeader fh;
  CHECK_EQ(ZSTD_getFrameHeader(&fh, z, zo.pos), 0);
  CHECK(fh.windowSize > (1ull << 27));

  const char *dst = tmp_path("long.zdb");
  zvfs_conv *c = NULL;
  CHECK_EQ(zvfs_conv_create(dst, NULL, 0, NULL, 3, 2, 1, 1 << 16, NULL, &c),
           ZVFS_OK);
  CHECK_EQ(zvfs_conv_feed_zstd(c, z, zo.pos), ZVFS_OK);
  zvfs_info info;
  CHECK_EQ(zvfs_conv_finish(c, &info), ZVFS_OK);
  zvfs_conv_destroy(c);
  CHECK_EQ(info.content_xxh64, zvfs_xxh64(src, n, 0));
  remove(dst);
  free(z);
  free(src);
}

typedef struct {
  zdb_file *f;
  membuf *mb;
  const uint8_t *src;
  size_t n;
  int errors;
  uint64_t seed;
} thread_arg;

static void reader_thread(void *p) {
  thread_arg *a = (thread_arg *)p;
  uint8_t *buf = (uint8_t *)malloc(20000);
  uint64_t x = a->seed;
  for (int i = 0; i < 20000; i++) {
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    uint64_t off = x % a->n;
    uint64_t len = 1 + (x >> 40) % 20000;
    if (off + len > a->n) len = a->n - off;
    if (zdb_file_read(a->f, mem_rd, a->mb, buf, len, off) != ZVFS_OK ||
        memcmp(buf, a->src + off, (size_t)len) != 0)
      a->errors++;
  }
  free(buf);
}

static void test_concurrency(void) {
  uint32_t ps = 4096, pages = 300;
  uint8_t *src = make_source(ps, pages, 0);
  size_t n = (size_t)ps * pages;
  const char *dst = tmp_path("mt.zdb");
  CHECK_EQ(convert_buf(dst, src, n, NULL, 0, 4, 1, 1 << 18, 0, NULL, NULL),
           ZVFS_OK);
  uint8_t *good;
  size_t good_n;
  CHECK_EQ(read_file(dst, &good, &good_n), 0);
  remove(dst);
  int64_t budgets[] = {0, 8 * 4096, 64 << 20};
  for (int b = 0; b < 3; b++) {
    zvfs_set_cache_budget(budgets[b]);
    membuf mb = {good, good_n};
    zdb_file *f = NULL;
    CHECK_EQ(zdb_file_load(mem_rd, &mb, good_n, &f), ZVFS_OK);
    if (!f) break;
    enum { T = 8 };
    zplat_thread th[T];
    thread_arg args[T];
    for (int i = 0; i < T; i++) {
      args[i] = (thread_arg){f, &mb, src, n, 0, 0x1234567ull * (i + 1)};
      CHECK_EQ(zplat_thread_start(&th[i], reader_thread, &args[i]), ZVFS_OK);
    }
    int errors = 0;
    for (int i = 0; i < T; i++) {
      zplat_thread_join(th[i]);
      errors += args[i].errors;
    }
    CHECK_EQ(errors, 0);
    CHECK(f->cache_bytes <= (budgets[b] > 0 ? budgets[b] : 0));
    zdb_file_free(f);
  }
  zvfs_set_cache_budget(16 << 20);
  free(good);
  free(src);
}

static void test_builtin_dict(void) {
  CHECK(zvfs_builtin_dict_count() >= 1);
  const char *name = NULL;
  const void *data = NULL;
  size_t len = 0;
  uint32_t id = 0;
  CHECK_EQ(zvfs_builtin_dict(0, &name, &data, &len, &id), ZVFS_OK);
  CHECK(name && data && len > 1024 && id != 0);
  CHECK_EQ(zvfs_builtin_dict(99, NULL, NULL, NULL, NULL), ZVFS_ERR_INVALID);
}

/* No frame and no index byte may sit in [lock, lock + 512): SQLite locks
   those bytes of the base file, and on Windows the locks are mandatory. */
static int check_gap_layout(const uint8_t *z, size_t zn, uint64_t lock,
                            const uint8_t *src, size_t n) {
  membuf mb = {z, zn};
  zdb_file *f = NULL;
  if (zdb_file_load(mem_rd, &mb, zn, &f) != ZVFS_OK) return -1;
  uint64_t hi = lock + ZDB_LOCK_SIZE;
  int gap = (f->h.incompat & ZDB_INCOMPAT_LOCK_GAP) != 0, bad = 0;
  for (uint64_t i = 0; i < f->h.frame_count; i++) {
    uint64_t a = f->index[i], e = zdb_frame_end(f, i);
    if (!(e <= lock || a >= hi)) bad++;
  }
  if (!(zn <= lock || f->h.index_offset >= hi)) bad++;
  if (gap && !(f->h.gap_start <= lock && f->h.gap_end == hi)) bad++;
  if (src) {
    uint8_t *all = (uint8_t *)malloc(n);
    if (zdb_file_read(f, mem_rd, &mb, all, n, 0) != ZVFS_OK ||
        memcmp(all, src, n) != 0)
      bad++;
    free(all);
  }
  zdb_file_free(f);
  return bad ? -1 : gap;
}

static void test_lock_gap(void) {
  uint32_t ps = 4096, pages = 300;
  uint8_t *src = make_source(ps, pages, 0);
  size_t n = (size_t)ps * pages;
  const char *dst = tmp_path("gap.zdb");
  zvfs_g_lock_byte = 1ull << 40;
  CHECK_EQ(convert_buf(dst, src, n, NULL, 0, 2, 1, 16 << 10, 0, NULL, NULL), 0);
  uint8_t *z;
  size_t zn;
  CHECK_EQ(read_file(dst, &z, &zn), 0);
  CHECK_EQ(check_gap_layout(z, zn, zvfs_g_lock_byte, src, n), 0);
  free(z);
  /* every lock position from the first frame to past the end of file */
  int gapped = 0, plain = 0, bad = 0;
  uint64_t step = zn / 700 | 1;
  for (uint64_t lock = ZDB_HEADER_SIZE + 64; lock < zn + 700; lock += step) {
    zvfs_g_lock_byte = lock;
    uint32_t fp = lock % 3 == 0 ? 2 : 1;
    int rc = convert_buf(dst, src, n, NULL, 0, 1 + (int)(lock % 3), fp,
                         (lock % 5 + 1) * 8192, 0, NULL, NULL);
    uint8_t *g;
    size_t gn;
    if (rc || read_file(dst, &g, &gn)) {
      bad++;
      continue;
    }
    int r = check_gap_layout(g, gn, lock, src, n);
    if (r < 0) {
      if (bad++ < 3) fprintf(stderr, "lock gap: bad layout at lock %llu\n",
                             (unsigned long long)lock);
    } else if (r) {
      gapped++;
      /* clearing the flag must not make the padding readable as a frame */
      uint8_t hdr[ZDB_HEADER_CORE];
      memcpy(hdr, g, sizeof hdr);
      zdb_header h;
      CHECK_EQ(zdb_header_decode(hdr, &h), ZVFS_OK);
      h.incompat &= ~ZDB_INCOMPAT_LOCK_GAP;
      zdb_header_encode(&h, g);
      membuf mb = {g, gn};
      zdb_file *f = NULL;
      CHECK(zdb_file_load(mem_rd, &mb, gn, &f) != ZVFS_OK);
      zdb_file_free(f);
    } else {
      plain++;
    }
    free(g);
  }
  zvfs_g_lock_byte = ZDB_LOCK_BYTE;
  CHECK_EQ(bad, 0);
  CHECK(gapped > 100 && plain > 0);
  printf("  lock gap: %d layouts with a gap, %d without, all readable\n", gapped,
         plain);
  remove(dst);
  free(src);
}

/* Real lock byte: a >1GB base from incompressible synthetic pages. */
static void big_page(uint32_t ps, uint64_t pg, uint8_t *out) {
  uint64_t x = pg * 0x9E3779B97F4A7C15ull + 1;
  for (uint32_t i = 0; i < ps; i += 8) {
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    memcpy(out + i, &x, 8);
  }
}

static int file_rd(void *ctx, void *buf, size_t n, uint64_t off) {
  size_t got = 0;
  int rc = zplat_pread((zplat_file *)ctx, buf, n, off, &got);
  if (rc) return rc;
  return got == n ? ZVFS_OK : ZVFS_ERR_SHORT_READ;
}

static void test_big_lock_gap(void) {
  const uint32_t ps = 16384;
  const uint64_t pages = (ZDB_LOCK_BYTE + (96ull << 20)) / ps;
  const char *dst = tmp_path("big_gap.zdb");
  zvfs_conv *c = NULL;
  CHECK_EQ(zvfs_conv_create(dst, NULL, 0, NULL, 1, 8, 1, 16 << 20, NULL, &c), 0);
  uint8_t *pg = (uint8_t *)malloc(ps);
  for (uint64_t i = 0; c && i < pages; i++) {
    big_page(ps, i, pg);
    if (i == 0) {
      memset(pg, 0, 100);
      memcpy(pg, "SQLite format 3", 16);
      pg[16] = (uint8_t)(ps >> 8);
      pg[18] = pg[19] = 1;
    }
    if (zvfs_conv_feed(c, pg, ps)) break;
  }
  CHECK_EQ(zvfs_conv_finish(c, NULL), 0);
  zvfs_conv_destroy(c);
  zplat_file *pf = NULL;
  uint64_t size = 0;
  CHECK_EQ(zplat_open_read(dst, &pf), 0);
  zplat_size(pf, &size);
  zdb_file *f = NULL;
  CHECK_EQ(zdb_file_load(file_rd, pf, size, &f), 0);
  if (f) {
    CHECK(size > ZDB_LOCK_BYTE + ZDB_LOCK_SIZE);
    CHECK(f->h.incompat & ZDB_INCOMPAT_LOCK_GAP);
    CHECK_EQ(f->h.gap_end, ZDB_LOCK_BYTE + ZDB_LOCK_SIZE);
    int bad = 0;
    uint64_t at = 0;
    for (uint64_t i = 0; i < f->h.frame_count; i++) {
      if (!(zdb_frame_end(f, i) <= ZDB_LOCK_BYTE ||
            f->index[i] >= ZDB_LOCK_BYTE + ZDB_LOCK_SIZE))
        bad++;
      if (f->index[i + 1] == f->h.gap_end) at = i;
    }
    CHECK_EQ(bad, 0);
    /* the pages on both sides of the gap decode to their source */
    uint8_t *got = (uint8_t *)malloc(ps);
    for (uint64_t i = at - 2; i < at + 3; i++) {
      big_page(ps, i, pg);
      CHECK_EQ(zdb_file_read(f, file_rd, pf, got, ps, i * ps), 0);
      CHECK(memcmp(got, pg, ps) == 0);
    }
    free(got);
    printf("  big lock gap: %.2f GB base, gap [%llu, %llu) before page %llu\n",
           size / 1073741824.0, (unsigned long long)f->h.gap_start,
           (unsigned long long)f->h.gap_end, (unsigned long long)(at + 1));
    zdb_file_free(f);
  }
  zplat_close(pf);
  free(pg);
  remove(dst);
}

/* ---- dictionaries of any valid size, from outside the registry ---- */
static int dict_roundtrip(const uint8_t *src, size_t n, uint32_t ps,
                          const void *dict, size_t dl, uint32_t *id_out) {
  const char *dst = tmp_path("dict_any.zdb");
  zvfs_info info;
  int rc = convert_buf(dst, src, n, dict, dl, 2, 1, 1 << 16, 0, NULL, &info);
  if (rc) return rc;
  uint8_t *z;
  size_t zn;
  if (read_file(dst, &z, &zn)) return -1;
  membuf mb = {z, zn};
  zdb_file *f = NULL;
  rc = zdb_file_load(mem_rd, &mb, zn, &f);
  uint8_t *all = (uint8_t *)malloc(n);
  if (!rc) rc = zdb_file_read(f, mem_rd, &mb, all, n, 0);
  if (!rc) rc = zdb_verify_base(f, mem_rd, &mb, NULL, NULL);
  if (!rc && (memcmp(all, src, n) != 0 || f->h.dict_length != dl ||
              f->h.dict_id != info.dict_id))
    rc = -1;
  if (id_out) *id_out = info.dict_id;
  zdb_file_free(f);
  free(all);
  free(z);
  remove(dst);
  (void)ps;
  return rc;
}

static void test_any_dict(void) {
  uint32_t ps = 4096, pages = 200;
  uint8_t *src = make_source(ps, pages, 0);
  size_t n = (size_t)ps * pages;
  /* a finalized (ZDICT) 1MB dictionary: the id comes from its header */
  const size_t max = ZDB_MAX_DICT;
  uint8_t *content = (uint8_t *)malloc(max);
  for (size_t i = 0; i < max; i++) content[i] = src[(i * 7919) % n];
  size_t *lens = (size_t *)malloc(pages * sizeof(size_t));
  for (uint32_t i = 0; i < pages; i++) lens[i] = ps;
  uint8_t *dict = (uint8_t *)malloc(max);
  ZDICT_params_t zp;
  memset(&zp, 0, sizeof zp);
  size_t dl = ZDICT_finalizeDictionary(dict, max, content, max - 4096, src,
                                       lens, pages, zp);
  CHECK(!ZDICT_isError(dl) && dl > max - 8192 && dl <= max);
  uint32_t id = 0;
  if (!ZDICT_isError(dl)) {
    CHECK_EQ(dict_roundtrip(src, n, ps, dict, dl, &id), 0);
    CHECK(id != 0 && id == ZDICT_getDictID(dict, dl));
  }
  /* raw content of exactly 1MB: zstd has no id for it, so dictId is 0 */
  CHECK_EQ(dict_roundtrip(src, n, ps, content, max, &id), 0);
  CHECK_EQ(id, 0);
  /* over the format limit, or a zstd dictionary with broken tables */
  zvfs_conv *c = NULL;
  CHECK_EQ(zvfs_conv_create(tmp_path("dict_big.zdb"), content, max + 1,
                            "x", 3, 1, 1, 0, NULL, &c),
           ZVFS_ERR_INVALID);
  if (!ZDICT_isError(dl)) {
    memset(dict + 8, 0xff, 64);
    CHECK(zvfs_conv_create(tmp_path("dict_bad.zdb"), dict, dl, "x", 3, 1, 1, 0,
                           NULL, &c) != ZVFS_OK);
  }
  remove(tmp_path("dict_big.zdb"));
  remove(tmp_path("dict_bad.zdb"));
  printf("  any dictionary: 1MB zdict (id %u) and 1MB raw content roundtrip\n",
         ZDICT_isError(dl) ? 0 : ZDICT_getDictID(dict, dl));
  free(content);
  free(lens);
  free(dict);
  free(src);
}

/* ---- trainer: the same bytes for the same inputs ---- */
static void test_train_deterministic(void) {
  uint32_t ps = 4096, pages = 600;
  uint8_t *src = make_source(ps, pages, 0);
  const char *db = tmp_path("train_src.db");
  CHECK_EQ(write_file(db, src, (size_t)ps * pages), 0);
  zvfs_train_params fc = {1, 256, 8, 16, 1, 0};
  const zvfs_train_params *modes[2] = {NULL, &fc};
  size_t cap = 32 << 10;
  uint8_t *a = (uint8_t *)malloc(cap), *b = (uint8_t *)malloc(cap);
  for (int m = 0; m < 2; m++) {
    size_t la = 0, lb = 0;
    uint32_t ia = 0, ib = 0;
    CHECK_EQ(zvfs_train_dict(db, 500, 11, modes[m], a, cap, &la, &ia), 0);
    CHECK_EQ(zvfs_train_dict(db, 500, 11, modes[m], b, cap, &lb, &ib), 0);
    CHECK(la > 1024 && la == lb && ia == ib && memcmp(a, b, la) == 0);
    CHECK(ia != 0 && ia == ZSTD_getDictID_fromDict(a, la));
    CHECK_EQ(dict_roundtrip(src, (size_t)ps * pages, ps, a, la, NULL), 0);
  }
  /* explicit parameters are checked */
  size_t l = 0;
  zvfs_train_params bad = {1, 8, 16, 0, 0, 0};
  CHECK_EQ(zvfs_train_dict(db, 500, 11, &bad, a, cap, &l, NULL), ZVFS_ERR_INVALID);
  CHECK_EQ(zvfs_train_dict(db, 500, 11, NULL, a, ZDB_MAX_DICT + 1, &l, NULL),
           ZVFS_ERR_INVALID);
  printf("  train: legacy and fastcover reproducible\n");
  remove(db);
  free(a);
  free(b);
  free(src);
}

/* ---- SQLite freelist: trunk chain parsing and zeroed leaf pages ---- */
static void put_be32(uint8_t *p, uint32_t v) {
  p[0] = (uint8_t)(v >> 24);
  p[1] = (uint8_t)(v >> 16);
  p[2] = (uint8_t)(v >> 8);
  p[3] = (uint8_t)v;
}

/* Trunks at pages 5 and 40 (1-based); leaves: 7..(7+n1), 60..(60+n2). */
static void make_freelist(uint8_t *s, uint32_t ps, uint32_t n1, uint32_t n2) {
  put_be32(s + 32, 5);
  put_be32(s + 36, 2 + n1 + n2);
  uint8_t *t = s + (size_t)4 * ps;
  put_be32(t, 40);
  put_be32(t + 4, n1);
  for (uint32_t i = 0; i < n1; i++) put_be32(t + 8 + 4 * i, 7 + i);
  t = s + (size_t)39 * ps;
  put_be32(t, 0);
  put_be32(t + 4, n2);
  for (uint32_t i = 0; i < n2; i++) put_be32(t + 8 + 4 * i, 60 + i);
}

static int is_leaf(uint32_t pg1, uint32_t n1, uint32_t n2) {
  return (pg1 >= 7 && pg1 < 7 + n1) || (pg1 >= 60 && pg1 < 60 + n2);
}

static void test_freelist(void) {
  uint32_t ps = 1024, pages = 200, n1 = 20, n2 = 30;
  size_t n = (size_t)ps * pages;
  uint8_t *src = make_source(ps, pages, 0);
  make_freelist(src, ps, n1, n2);
  membuf mb = {src, n};
  zvfs_pageset set;
  CHECK_EQ(zvfs_freelist_leaves(mem_rd, &mb, n, &set), 0);
  CHECK(set.bits && set.count == n1 + n2 && set.page_size == ps);
  int wrong = 0;
  for (uint32_t pg = 0; set.bits && pg < pages; pg++)
    wrong += ((set.bits[pg >> 3] >> (pg & 7)) & 1) != is_leaf(pg + 1, n1, n2);
  CHECK_EQ(wrong, 0);
  free(set.bits);

  /* an inconsistent list is not touched */
  static const struct {
    uint32_t off, val;
  } breaks[] = {
      {36, 51},                      /* count too small */
      {36, 53},                      /* count too large */
      {32, 1},                       /* page 1 as trunk */
      {32, 201},                     /* trunk past the end */
      {4 * 1024 + 8, 40},            /* a leaf that is also a trunk */
      {4 * 1024 + 12, 7},            /* a leaf listed twice */
      {39 * 1024, 5},                /* the chain loops */
      {4 * 1024 + 4, 1024 / 4 - 1},  /* more leaves than fit in a trunk */
  };
  uint8_t *bad = (uint8_t *)malloc(n);
  for (size_t i = 0; i < sizeof breaks / sizeof breaks[0]; i++) {
    memcpy(bad, src, n);
    put_be32(bad + breaks[i].off, breaks[i].val);
    membuf bm = {bad, n};
    CHECK_EQ(zvfs_freelist_leaves(mem_rd, &bm, n, &set), 0);
    if (set.bits) fprintf(stderr, "freelist break %zu accepted\n", i);
    CHECK(set.bits == NULL);
    free(set.bits);
  }
  free(bad);

  /* convert with the leaves zeroed: everything else identical, hash valid */
  const char *db = tmp_path("fl_src.db");
  const char *dst = tmp_path("fl.zdb");
  CHECK_EQ(write_file(db, src, n), 0);
  for (uint32_t fp = 1; fp <= 3; fp += 2) {
    zvfs_conv *c = NULL;
    uint64_t leaves = 0;
    CHECK_EQ(zvfs_conv_create(dst, NULL, 0, NULL, 3, 2, fp, 1 << 14, NULL, &c), 0);
    CHECK_EQ(zvfs_conv_zero_freelist(c, db, &leaves), 0);
    CHECK_EQ(leaves, n1 + n2);
    for (size_t off = 0; off < n;) {
      size_t k = 1 + (size_t)(rnd() % 5000);
      if (k > n - off) k = n - off;
      CHECK_EQ(zvfs_conv_feed(c, src + off, k), 0);
      off += k;
    }
    CHECK_EQ(zvfs_conv_finish(c, NULL), 0);
    zvfs_conv_destroy(c);
    uint8_t *z;
    size_t zn;
    CHECK_EQ(read_file(dst, &z, &zn), 0);
    membuf zm = {z, zn};
    zdb_file *f = NULL;
    CHECK_EQ(zdb_file_load(mem_rd, &zm, zn, &f), 0);
    uint8_t *all = (uint8_t *)malloc(n);
    CHECK_EQ(zdb_file_read(f, mem_rd, &zm, all, n, 0), 0);
    CHECK_EQ(zdb_verify_base(f, mem_rd, &zm, NULL, NULL), 0);
    int diff = 0;
    for (uint32_t pg = 0; pg < pages; pg++) {
      const uint8_t *got = all + (size_t)pg * ps;
      if (is_leaf(pg + 1, n1, n2)) {
        for (uint32_t i = 0; i < ps; i++) diff += got[i] != 0;
      } else {
        diff += memcmp(got, src + (size_t)pg * ps, ps) != 0;
      }
    }
    CHECK_EQ(diff, 0);
    zdb_file_free(f);
    free(all);
    free(z);
  }
  /* the source's page size must not change between the scan and the feed */
  zvfs_conv *c = NULL;
  CHECK_EQ(zvfs_conv_create(dst, NULL, 0, NULL, 3, 1, 1, 0, NULL, &c), 0);
  CHECK_EQ(zvfs_conv_zero_freelist(c, db, NULL), 0);
  uint8_t *other = make_source(2048, 100, 0);
  CHECK_EQ(zvfs_conv_feed(c, other, 2048 * 100), ZVFS_ERR_INVALID);
  zvfs_conv_destroy(c);
  free(other);
  printf("  freelist: %u leaves found, zeroed on convert (framePages 1 and 3), "
         "8 broken chains left alone\n", n1 + n2);
  remove(db);
  remove(dst);
  free(src);
}

int main(void) {
  setvbuf(stdout, NULL, _IONBF, 0);
  const char *it = getenv("ZVFS_FUZZ_ITERS");
  int iters = it ? atoi(it) : 20000;
  test_header_codec();
  test_builtin_dict();
  test_roundtrips();
  test_converter_errors();
  test_concurrency();
  test_zstd_long_window_source();
  test_exhaustive_damage();
  test_lock_gap();
  test_any_dict();
  test_train_deterministic();
  test_freelist();
  if (getenv("ZVFS_BIG_TESTS")) test_big_lock_gap();
  test_fuzz(iters);
  if (g_failures) {
    fprintf(stderr, "%d check(s) failed\n", g_failures);
    return 1;
  }
  printf("all core tests passed (zstd %s)\n", zvfs_zstd_version());
  return 0;
}
