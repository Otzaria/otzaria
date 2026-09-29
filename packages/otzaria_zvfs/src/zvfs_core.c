#include <stdlib.h>
#include <string.h>

#include "zvfs_internal.h"

#define ZSTD_STATIC_LINKING_ONLY
#include "zstd.h"
#define XXH_INLINE_ALL
#include "common/xxhash.h"

/* ---- stats ---- */
static volatile int64_t g_frames_decoded, g_cache_hits, g_cache_misses,
    g_compressed_read, g_corrupt_frames, g_cache_bytes_total, g_open_files;
volatile int64_t zvfs_g_cache_budget = 16ll << 20;

void zvfs_stat_open_files(int64_t d) { zplat_atomic_add(&g_open_files, d); }

ZVFS_API void zvfs_set_cache_budget(int64_t bytes) {
  zplat_atomic_store(&zvfs_g_cache_budget, bytes < 0 ? 0 : bytes);
}
ZVFS_API int64_t zvfs_get_cache_budget(void) {
  return zplat_atomic_load(&zvfs_g_cache_budget);
}

ZVFS_API void zvfs_get_stats(zvfs_stats *o) {
  o->frames_decoded = zplat_atomic_load(&g_frames_decoded);
  o->cache_hits = zplat_atomic_load(&g_cache_hits);
  o->cache_misses = zplat_atomic_load(&g_cache_misses);
  o->compressed_bytes_read = zplat_atomic_load(&g_compressed_read);
  o->corrupt_frames = zplat_atomic_load(&g_corrupt_frames);
  o->cache_bytes = zplat_atomic_load(&g_cache_bytes_total);
  o->open_files = zplat_atomic_load(&g_open_files);
}

ZVFS_API const char *zvfs_errstr(int code) {
  switch (code) {
    case ZVFS_OK: return "ok";
    case ZVFS_ERR_IO: return "I/O error";
    case ZVFS_ERR_CORRUPT: return "corrupt zdb file";
    case ZVFS_ERR_NOMEM: return "out of memory";
    case ZVFS_ERR_UNSUPPORTED: return "unsupported zdb format version";
    case ZVFS_ERR_INVALID: return "invalid argument or source";
    case ZVFS_ERR_CANCELLED: return "cancelled";
    case ZVFS_ERR_NOT_ZDB: return "not a zdb file";
    case ZVFS_ERR_SHORT_READ: return "short read";
    default: return "unknown error";
  }
}

ZVFS_API const char *zvfs_zstd_version(void) { return ZSTD_versionString(); }

ZVFS_API uint64_t zvfs_xxh64(const void *data, size_t len, uint64_t seed) {
  return XXH64(data, len, seed);
}

/* ---- little-endian codec ---- */
static uint32_t get32(const uint8_t *p) {
  return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 |
         (uint32_t)p[3] << 24;
}
static uint64_t get64(const uint8_t *p) {
  return (uint64_t)get32(p) | (uint64_t)get32(p + 4) << 32;
}
static void put32(uint8_t *p, uint32_t v) {
  p[0] = (uint8_t)v;
  p[1] = (uint8_t)(v >> 8);
  p[2] = (uint8_t)(v >> 16);
  p[3] = (uint8_t)(v >> 24);
}
static void put64(uint8_t *p, uint64_t v) {
  put32(p, (uint32_t)v);
  put32(p + 4, (uint32_t)(v >> 32));
}

int zdb_has_magic(const void *p, size_t n) {
  return n >= ZDB_MAGIC_LEN && memcmp(p, ZDB_MAGIC, ZDB_MAGIC_LEN) == 0;
}

uint64_t zdb_frame_bytes(const zdb_header *h) {
  return (uint64_t)h->page_size * h->frame_pages;
}

size_t zdb_max_frame_len(const zdb_header *h) {
  return ZSTD_compressBound((size_t)zdb_frame_bytes(h)) + 64;
}

void zdb_header_encode(const zdb_header *h, uint8_t r[ZDB_HEADER_CORE]) {
  memset(r, 0, ZDB_HEADER_CORE);
  memcpy(r, ZDB_MAGIC, ZDB_MAGIC_LEN);
  r[8] = (uint8_t)h->major;
  r[9] = (uint8_t)(h->major >> 8);
  r[10] = (uint8_t)h->minor;
  r[11] = (uint8_t)(h->minor >> 8);
  put32(r + 12, h->header_size);
  put32(r + 16, h->incompat);
  put32(r + 20, h->compat);
  put32(r + 24, h->page_size);
  put32(r + 28, h->frame_pages);
  put64(r + 32, h->logical_size);
  put64(r + 40, h->frame_count);
  put32(r + 48, h->codec);
  put32(r + 52, h->level);
  put64(r + 56, h->dict_offset);
  put32(r + 64, h->dict_length);
  put32(r + 68, h->dict_id);
  put64(r + 72, h->dict_xxh64);
  put64(r + 80, h->index_offset);
  put64(r + 88, h->index_length);
  put64(r + 96, h->index_xxh64);
  put64(r + 104, h->content_xxh64);
  memcpy(r + 112, h->uuid, 16);
  put64(r + 128, h->created_ms);
  memcpy(r + 136, h->dict_name, 31);
  put64(r + 248, XXH64(r, 248, 0));
}

int zdb_header_decode(const uint8_t r[ZDB_HEADER_CORE], zdb_header *h) {
  if (!zdb_has_magic(r, ZDB_HEADER_CORE)) return ZVFS_ERR_NOT_ZDB;
  memset(h, 0, sizeof *h);
  h->major = (uint32_t)r[8] | (uint32_t)r[9] << 8;
  h->minor = (uint32_t)r[10] | (uint32_t)r[11] << 8;
  /* magic + major stay at fixed offsets across versions */
  if (h->major != ZDB_FORMAT_MAJOR) return ZVFS_ERR_UNSUPPORTED;
  if (get64(r + 248) != XXH64(r, 248, 0)) return ZVFS_ERR_CORRUPT;
  h->header_size = get32(r + 12);
  h->incompat = get32(r + 16);
  h->compat = get32(r + 20);
  h->page_size = get32(r + 24);
  h->frame_pages = get32(r + 28);
  h->logical_size = get64(r + 32);
  h->frame_count = get64(r + 40);
  h->codec = get32(r + 48);
  h->level = get32(r + 52);
  h->dict_offset = get64(r + 56);
  h->dict_length = get32(r + 64);
  h->dict_id = get32(r + 68);
  h->dict_xxh64 = get64(r + 72);
  h->index_offset = get64(r + 80);
  h->index_length = get64(r + 88);
  h->index_xxh64 = get64(r + 96);
  h->content_xxh64 = get64(r + 104);
  memcpy(h->uuid, r + 112, 16);
  h->created_ms = get64(r + 128);
  memcpy(h->dict_name, r + 136, 32);
  if (h->incompat & ~ZDB_KNOWN_INCOMPAT) return ZVFS_ERR_UNSUPPORTED;
  if (h->codec != ZDB_CODEC_ZSTD_MAGICLESS) return ZVFS_ERR_UNSUPPORTED;

  if (h->header_size != ZDB_HEADER_SIZE) return ZVFS_ERR_CORRUPT;
  if (h->page_size < 512 || h->page_size > 65536 ||
      (h->page_size & (h->page_size - 1)))
    return ZVFS_ERR_CORRUPT;
  if (h->frame_pages < 1 || h->frame_pages > ZDB_MAX_FRAME_BYTES / h->page_size)
    return ZVFS_ERR_CORRUPT;
  if (h->dict_name[31] != 0) return ZVFS_ERR_CORRUPT;
  uint64_t fb = zdb_frame_bytes(h);
  if (h->logical_size == 0 || h->logical_size > (1ull << 50) ||
      h->logical_size % h->page_size)
    return ZVFS_ERR_CORRUPT;
  if (h->frame_count != (h->logical_size + fb - 1) / fb) return ZVFS_ERR_CORRUPT;
  if (h->frame_count >= (uint64_t)(SIZE_MAX / 8) - 1) return ZVFS_ERR_CORRUPT;
  if (h->dict_offset != ZDB_HEADER_SIZE || h->dict_length > ZDB_MAX_DICT)
    return ZVFS_ERR_CORRUPT;
  if (h->index_length != (h->frame_count + 1) * 8) return ZVFS_ERR_CORRUPT;
  /* every frame is at least one byte */
  if (h->index_offset < h->dict_offset + h->dict_length + h->frame_count ||
      h->index_offset > (1ull << 60))
    return ZVFS_ERR_CORRUPT;
  return ZVFS_OK;
}

/* ---- decompression context pool (DCtx objects are not thread-safe) ---- */
#define DCTX_POOL_MAX 32
static zplat_mutex g_pool_mu = ZPLAT_MUTEX_INIT;
static ZSTD_DCtx *g_pool[DCTX_POOL_MAX];
static int g_pool_n;

static ZSTD_DCtx *dctx_get(void) {
  ZSTD_DCtx *d = NULL;
  zplat_lock(&g_pool_mu);
  if (g_pool_n > 0) d = g_pool[--g_pool_n];
  zplat_unlock(&g_pool_mu);
  if (d) return d;
  d = ZSTD_createDCtx();
  if (!d) return NULL;
  if (ZSTD_isError(ZSTD_DCtx_setParameter(d, ZSTD_d_format,
                                          ZSTD_f_zstd1_magicless))) {
    ZSTD_freeDCtx(d);
    return NULL;
  }
  return d;
}

static void dctx_put(ZSTD_DCtx *d) {
  ZSTD_DCtx_refDDict(d, NULL);
  zplat_lock(&g_pool_mu);
  if (g_pool_n < DCTX_POOL_MAX) {
    g_pool[g_pool_n++] = d;
    d = NULL;
  }
  zplat_unlock(&g_pool_mu);
  if (d) ZSTD_freeDCtx(d);
}

/* ---- file load ---- */
static int rd_all(zdb_read_fn rd, void *ctx, void *buf, uint64_t n,
                  uint64_t off) {
  uint8_t *p = (uint8_t *)buf;
  while (n) {
    size_t chunk = n > (1u << 20) ? (1u << 20) : (size_t)n;
    int rc = rd(ctx, p, chunk, off);
    if (rc == ZVFS_ERR_SHORT_READ) return ZVFS_ERR_CORRUPT;
    if (rc) return rc;
    p += chunk;
    off += chunk;
    n -= chunk;
  }
  return ZVFS_OK;
}

int zdb_file_load(zdb_read_fn rd, void *ctx, uint64_t phys, zdb_file **out) {
  *out = NULL;
  if (phys < ZDB_HEADER_SIZE) return ZVFS_ERR_CORRUPT;
  zdb_file *f = (zdb_file *)calloc(1, sizeof *f);
  if (!f) return ZVFS_ERR_NOMEM;
  zplat_mutex_init(&f->mu);
  int rc = rd_all(rd, ctx, f->raw_header, ZDB_HEADER_CORE, 0);
  if (!rc) rc = zdb_header_decode(f->raw_header, &f->h);
  if (rc) goto fail;
  f->physical_size = phys;
  f->frame_bytes = zdb_frame_bytes(&f->h);
  if (f->h.index_offset + f->h.index_length != phys) {
    rc = ZVFS_ERR_CORRUPT;
    goto fail;
  }

  if (f->h.dict_length) {
    void *dict = malloc(f->h.dict_length);
    if (!dict) {
      rc = ZVFS_ERR_NOMEM;
      goto fail;
    }
    rc = rd_all(rd, ctx, dict, f->h.dict_length, f->h.dict_offset);
    if (!rc && XXH64(dict, f->h.dict_length, 0) != f->h.dict_xxh64)
      rc = ZVFS_ERR_CORRUPT;
    if (!rc && ZSTD_getDictID_fromDict(dict, f->h.dict_length) != f->h.dict_id)
      rc = ZVFS_ERR_CORRUPT;
    if (!rc) {
      f->ddict = ZSTD_createDDict(dict, f->h.dict_length);
      if (!f->ddict) rc = ZVFS_ERR_CORRUPT;
    }
    free(dict);
    if (rc) goto fail;
  } else if (f->h.dict_id != 0) {
    rc = ZVFS_ERR_CORRUPT;
    goto fail;
  }

  {
    uint64_t n = f->h.frame_count + 1;
    f->index = (uint64_t *)malloc((size_t)n * sizeof(uint64_t));
    uint8_t *chunk = (uint8_t *)malloc(1u << 16);
    if (!f->index || !chunk) {
      free(chunk);
      rc = ZVFS_ERR_NOMEM;
      goto fail;
    }
    XXH64_state_t st;
    XXH64_reset(&st, 0);
    uint64_t done = 0;
    while (done < n && !rc) {
      uint64_t k = n - done > 8192 ? 8192 : n - done;
      rc = rd_all(rd, ctx, chunk, k * 8, f->h.index_offset + done * 8);
      if (rc) break;
      XXH64_update(&st, chunk, (size_t)k * 8);
      for (uint64_t i = 0; i < k; i++) f->index[done + i] = get64(chunk + i * 8);
      done += k;
    }
    free(chunk);
    if (rc) goto fail;
    if (XXH64_digest(&st) != f->h.index_xxh64) {
      rc = ZVFS_ERR_CORRUPT;
      goto fail;
    }
    uint64_t maxlen = zdb_max_frame_len(&f->h);
    if (f->index[0] != f->h.dict_offset + f->h.dict_length ||
        f->index[f->h.frame_count] != f->h.index_offset) {
      rc = ZVFS_ERR_CORRUPT;
      goto fail;
    }
    for (uint64_t i = 0; i < f->h.frame_count; i++) {
      if (f->index[i + 1] <= f->index[i] ||
          f->index[i + 1] - f->index[i] > maxlen) {
        rc = ZVFS_ERR_CORRUPT;
        goto fail;
      }
    }
  }

  {
    int64_t budget = zplat_atomic_load(&zvfs_g_cache_budget);
    uint64_t slots = f->frame_bytes ? (uint64_t)budget / f->frame_bytes : 0;
    size_t nb = 64;
    while (nb < slots * 2 && nb < (1u << 20)) nb <<= 1;
    f->buckets = (zdb_cache_entry **)calloc(nb, sizeof(zdb_cache_entry *));
    if (!f->buckets) {
      rc = ZVFS_ERR_NOMEM;
      goto fail;
    }
    f->bucket_mask = nb - 1;
  }
  *out = f;
  return ZVFS_OK;
fail:
  zdb_file_free(f);
  return rc;
}

/* ---- LRU of decoded frames ---- */
struct zdb_cache_entry {
  uint64_t frame;
  zdb_cache_entry *hnext, *prev, *next;
  size_t len;
  uint8_t data[1];
};

static size_t bucket_of(const zdb_file *f, uint64_t frame) {
  uint64_t x = frame * 0x9E3779B97F4A7C15ull;
  return (size_t)(x >> 32) & f->bucket_mask;
}

static zdb_cache_entry *cache_find(zdb_file *f, uint64_t frame) {
  zdb_cache_entry *e = f->buckets[bucket_of(f, frame)];
  while (e && e->frame != frame) e = e->hnext;
  return e;
}

static void lru_unlink(zdb_file *f, zdb_cache_entry *e) {
  if (e->prev) e->prev->next = e->next; else f->lru_head = e->next;
  if (e->next) e->next->prev = e->prev; else f->lru_tail = e->prev;
  e->prev = e->next = NULL;
}

static void lru_push_front(zdb_file *f, zdb_cache_entry *e) {
  e->prev = NULL;
  e->next = f->lru_head;
  if (f->lru_head) f->lru_head->prev = e; else f->lru_tail = e;
  f->lru_head = e;
}

static void cache_remove(zdb_file *f, zdb_cache_entry *e) {
  zdb_cache_entry **pp = &f->buckets[bucket_of(f, e->frame)];
  while (*pp != e) pp = &(*pp)->hnext;
  *pp = e->hnext;
  lru_unlink(f, e);
  f->cache_bytes -= (int64_t)e->len;
  zplat_atomic_add(&g_cache_bytes_total, -(int64_t)e->len);
  free(e);
}

/* Takes ownership of e; caller holds f->mu. */
static void cache_insert(zdb_file *f, zdb_cache_entry *e, int64_t budget) {
  while (f->lru_tail && f->cache_bytes + (int64_t)e->len > budget)
    cache_remove(f, f->lru_tail);
  size_t b = bucket_of(f, e->frame);
  e->hnext = f->buckets[b];
  f->buckets[b] = e;
  lru_push_front(f, e);
  f->cache_bytes += (int64_t)e->len;
  zplat_atomic_add(&g_cache_bytes_total, (int64_t)e->len);
}

void zdb_file_free(zdb_file *f) {
  if (!f) return;
  if (f->buckets) {
    while (f->lru_tail) cache_remove(f, f->lru_tail);
    free(f->buckets);
  }
  free(f->index);
  if (f->ddict) ZSTD_freeDDict((ZSTD_DDict *)f->ddict);
  zplat_mutex_destroy(&f->mu);
  free(f->key);
  free(f);
}

/* ---- frame decode ---- */
static size_t frame_len(const zdb_file *f, uint64_t frame) {
  uint64_t start = frame * f->frame_bytes;
  uint64_t left = f->h.logical_size - start;
  return (size_t)(left < f->frame_bytes ? left : f->frame_bytes);
}

static int decode_frame(zdb_file *f, zdb_read_fn rd, void *ctx, uint64_t frame,
                        uint8_t *dst) {
  uint64_t a = f->index[frame];
  size_t clen = (size_t)(f->index[frame + 1] - a);
  size_t want = frame_len(f, frame);
  uint8_t *src = (uint8_t *)malloc(clen);
  if (!src) return ZVFS_ERR_NOMEM;
  int rc = rd(ctx, src, clen, a);
  if (rc == ZVFS_ERR_SHORT_READ) rc = ZVFS_ERR_CORRUPT;
  if (rc) {
    free(src);
    return rc;
  }
  zplat_atomic_add(&g_compressed_read, (int64_t)clen);

  /* The frame must carry its content size and checksum, or the decoder
     would accept a header whose checksum flag was flipped off. */
  ZSTD_frameHeader zfh;
  size_t hr = ZSTD_getFrameHeader_advanced(&zfh, src, clen,
                                           ZSTD_f_zstd1_magicless);
  if (hr != 0 || zfh.frameType != ZSTD_frame || !zfh.checksumFlag ||
      zfh.frameContentSize != (unsigned long long)want || zfh.dictID != 0) {
    free(src);
    zplat_atomic_add(&g_corrupt_frames, 1);
    return ZVFS_ERR_CORRUPT;
  }
  ZSTD_DCtx *d = dctx_get();
  if (!d) {
    free(src);
    return ZVFS_ERR_NOMEM;
  }
  size_t z = ZSTD_DCtx_refDDict(d, (const ZSTD_DDict *)f->ddict);
  if (!ZSTD_isError(z)) z = ZSTD_decompressDCtx(d, dst, want, src, clen);
  dctx_put(d);
  free(src);
  if (ZSTD_isError(z) || z != want) {
    zplat_atomic_add(&g_corrupt_frames, 1);
    return ZVFS_ERR_CORRUPT;
  }
  zplat_atomic_add(&g_frames_decoded, 1);
  return ZVFS_OK;
}

int zdb_file_read(zdb_file *f, zdb_read_fn rd, void *ctx, void *buf,
                  uint64_t n, uint64_t off) {
  uint8_t *out = (uint8_t *)buf;
  uint64_t end = off + n;
  int rc = ZVFS_OK;
  while (off < end && off < f->h.logical_size) {
    uint64_t frame = off / f->frame_bytes;
    size_t inner = (size_t)(off - frame * f->frame_bytes);
    size_t flen = frame_len(f, frame);
    size_t part = flen - inner;
    if ((uint64_t)part > end - off) part = (size_t)(end - off);

    zplat_lock(&f->mu);
    zdb_cache_entry *e = cache_find(f, frame);
    if (e) {
      lru_unlink(f, e);
      lru_push_front(f, e);
      memcpy(out, e->data + inner, part);
    }
    zplat_unlock(&f->mu);
    if (e) {
      zplat_atomic_add(&g_cache_hits, 1);
    } else {
      zplat_atomic_add(&g_cache_misses, 1);
      int64_t budget = zplat_atomic_load(&zvfs_g_cache_budget);
      if (budget >= (int64_t)flen) {
        zdb_cache_entry *ne =
            (zdb_cache_entry *)malloc(offsetof(zdb_cache_entry, data) + flen);
        if (!ne) return ZVFS_ERR_NOMEM;
        rc = decode_frame(f, rd, ctx, frame, ne->data);
        if (rc) {
          free(ne);
          break;
        }
        memcpy(out, ne->data + inner, part);
        ne->frame = frame;
        ne->len = flen;
        ne->prev = ne->next = ne->hnext = NULL;
        zplat_lock(&f->mu);
        if (cache_find(f, frame)) {
          zplat_unlock(&f->mu);
          free(ne);
        } else {
          cache_insert(f, ne, budget);
          zplat_unlock(&f->mu);
        }
      } else if (inner == 0 && part == flen) {
        rc = decode_frame(f, rd, ctx, frame, out);
        if (rc) break;
      } else {
        uint8_t *tmp = (uint8_t *)malloc(flen);
        if (!tmp) return ZVFS_ERR_NOMEM;
        rc = decode_frame(f, rd, ctx, frame, tmp);
        if (!rc) memcpy(out, tmp + inner, part);
        free(tmp);
        if (rc) break;
      }
    }
    out += part;
    off += part;
  }
  if (rc) return rc;
  if (off < end) {
    memset(out, 0, (size_t)(end - off));
    return ZVFS_ERR_SHORT_READ;
  }
  return ZVFS_OK;
}

void zdb_fill_info(const zdb_file *f, zvfs_info *o) {
  memset(o, 0, sizeof *o);
  o->format_major = f->h.major;
  o->format_minor = f->h.minor;
  o->page_size = f->h.page_size;
  o->frame_pages = f->h.frame_pages;
  o->logical_size = f->h.logical_size;
  o->frame_count = f->h.frame_count;
  o->physical_size = f->physical_size;
  o->dict_id = f->h.dict_id;
  o->dict_length = f->h.dict_length;
  o->level = f->h.level;
  o->compat_features = f->h.compat;
  o->incompat_features = f->h.incompat;
  o->content_xxh64 = f->h.content_xxh64;
  o->created_unix_ms = f->h.created_ms;
  memcpy(o->file_uuid, f->h.uuid, 16);
  memcpy(o->dict_name, f->h.dict_name, 32);
}

/* ---- standalone reader ---- */
struct zvfs_reader {
  zplat_file *pf;
  zdb_file *f;
};

static int reader_rd(void *ctx, void *buf, size_t n, uint64_t off) {
  size_t got = 0;
  int rc = zplat_pread((zplat_file *)ctx, buf, n, off, &got);
  if (rc) return rc;
  return got == n ? ZVFS_OK : ZVFS_ERR_SHORT_READ;
}

ZVFS_API int zvfs_probe_path(const char *path) {
  zplat_file *pf;
  if (!path || zplat_open_read(path, &pf)) return 0;
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
  if (rc) {
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
  return ZVFS_OK;
}

ZVFS_API int zvfs_reader_read(zvfs_reader *r, void *buf, int64_t n,
                              int64_t off) {
  if (!r || !buf || n < 0 || off < 0) return ZVFS_ERR_INVALID;
  return zdb_file_read(r->f, reader_rd, r->pf, buf, (uint64_t)n, (uint64_t)off);
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
  zdb_file *f = r->f;
  uint8_t *buf = (uint8_t *)malloc((size_t)f->frame_bytes);
  if (!buf) return ZVFS_ERR_NOMEM;
  XXH64_state_t st;
  XXH64_reset(&st, 0);
  int rc = ZVFS_OK;
  for (uint64_t i = 0; i < f->h.frame_count; i++) {
    if (cancel && zplat_atomic_load32(cancel)) {
      rc = ZVFS_ERR_CANCELLED;
      break;
    }
    rc = decode_frame(f, reader_rd, r->pf, i, buf);
    if (rc) break;
    size_t len = frame_len(f, i);
    XXH64_update(&st, buf, len);
    if (progress) zplat_atomic_store(progress, (int64_t)((i + 1) * f->frame_bytes));
  }
  free(buf);
  if (!rc && XXH64_digest(&st) != f->h.content_xxh64) rc = ZVFS_ERR_CORRUPT;
  return rc;
}
