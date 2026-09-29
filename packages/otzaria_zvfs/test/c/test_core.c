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

int main(void) {
  const char *it = getenv("ZVFS_FUZZ_ITERS");
  int iters = it ? atoi(it) : 20000;
  test_header_codec();
  test_builtin_dict();
  test_roundtrips();
  test_converter_errors();
  test_concurrency();
  test_fuzz(iters);
  if (g_failures) {
    fprintf(stderr, "%d check(s) failed\n", g_failures);
    return 1;
  }
  printf("all core tests passed (zstd %s)\n", zvfs_zstd_version());
  return 0;
}
