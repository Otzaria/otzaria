#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zvfs_internal.h"

#define ZSTD_STATIC_LINKING_ONLY
#include "zstd.h"
#define XXH_INLINE_ALL
#include "common/xxhash.h"

#define SQLITE_HDR 100
#define MAX_THREADS 64

typedef struct batch {
  uint8_t *in;
  size_t in_len;
  uint64_t first_frame;
  uint32_t n_frames;
  uint8_t *out;
  size_t *out_len;
  uint8_t *pre; /* frame already compressed (copied by compaction) */
  volatile int64_t next;
  volatile int64_t err;
} batch;

struct zvfs_conv {
  zplat_file *out;
  char err[256];
  int failed;
  volatile int32_t *cancel;
  int level, threads;
  uint32_t frame_pages;
  uint64_t batch_bytes;
  ZSTD_CDict *cdict;
  zdb_header h;
  int uuid_from_content;

  uint8_t sqlite_hdr[SQLITE_HDR];
  size_t sqlite_hdr_len;
  uint64_t frame_bytes;
  size_t out_stride;
  uint32_t frames_per_batch;
  batch b[2];
  int fill; /* index of the batch being filled */
  int inflight;

  uint64_t *index;
  uint64_t index_cap;
  uint64_t frames_written;
  uint64_t appended;
  uint64_t write_off;
  XXH64_state_t content;
  volatile int64_t bytes_in, bytes_out;

  /* pages written as zeros (freelist leaves), bit = 0-based page */
  uint8_t *zero;
  uint64_t zero_npages, frames_copied;
  uint32_t zero_ps;
  int copy;               /* zvfs_conv_feed_frame is enabled */
  const void *copy_ddict; /* borrowed from the source */

  ZSTD_DStream *zin;
  uint8_t *zbuf;
  int zin_mid_frame;

  zplat_mutex mu;
  zplat_cond cv_work, cv_done;
  batch *job;
  uint64_t gen;
  int busy, quit;
  zplat_thread th[MAX_THREADS];
  int n_threads_started;
};

uint64_t zvfs_g_lock_byte = ZDB_LOCK_BYTE;

static int fail(zvfs_conv *c, int code, const char *msg) {
  if (!c->failed) {
    c->failed = code;
    snprintf(c->err, sizeof c->err, "%s", msg);
  }
  return c->failed;
}

static int cancelled(zvfs_conv *c) {
  return c->cancel && zplat_atomic_load32(c->cancel) != 0;
}

static int zero_page(const zvfs_conv *c, uint64_t pg);

/* A copied frame is decoded into its input slot (checking its checksum,
   for the content hash); if it holds a stale freelist leaf it is compressed. */
static int decode_copy(zvfs_conv *c, batch *b, int64_t i, uint8_t *in,
                       size_t len) {
  uint8_t *src = b->out + (size_t)i * c->out_stride;
  int rc = zdb_decode(c->copy_ddict, src, b->out_len[i], in, len);
  if (rc || !c->zero) return rc;
  const uint32_t ps = c->h.page_size;
  uint64_t first = (b->first_frame + (uint64_t)i) * c->frame_bytes / ps;
  for (size_t o = 0; o < len; o += ps) {
    if (!zero_page(c, first + o / ps)) continue;
    for (size_t k = 0; k < ps && b->pre[i]; k++)
      if (in[o + k]) b->pre[i] = 0;
    memset(in + o, 0, ps);
  }
  return ZVFS_OK;
}

static void compress_batch(zvfs_conv *c, ZSTD_CCtx *cc, batch *b) {
  for (;;) {
    int64_t i = zplat_atomic_add(&b->next, 1) - 1;
    if (i >= (int64_t)b->n_frames) break;
    if (zplat_atomic_load(&b->err)) continue;
    if (cancelled(c)) {
      zplat_atomic_store(&b->err, ZVFS_ERR_CANCELLED);
      continue;
    }
    size_t start = (size_t)i * (size_t)c->frame_bytes;
    size_t len = b->in_len - start < c->frame_bytes ? b->in_len - start
                                                     : (size_t)c->frame_bytes;
    if (b->pre[i]) {
      int rc = decode_copy(c, b, i, b->in + start, len);
      if (rc) zplat_atomic_store(&b->err, rc);
      if (rc || b->pre[i]) continue;
    }
    size_t z = ZSTD_compress2(cc, b->out + (size_t)i * c->out_stride,
                              c->out_stride, b->in + start, len);
    if (ZSTD_isError(z)) {
      zplat_atomic_store(&b->err, ZVFS_ERR_INVALID);
      continue;
    }
    b->out_len[i] = z;
  }
}

static ZSTD_CCtx *make_cctx(zvfs_conv *c) {
  ZSTD_CCtx *cc = ZSTD_createCCtx();
  if (!cc) return NULL;
  size_t r = ZSTD_CCtx_setParameter(cc, ZSTD_c_format, ZSTD_f_zstd1_magicless);
  if (!ZSTD_isError(r))
    r = ZSTD_CCtx_setParameter(cc, ZSTD_c_compressionLevel, c->level);
  if (!ZSTD_isError(r)) r = ZSTD_CCtx_setParameter(cc, ZSTD_c_checksumFlag, 1);
  if (!ZSTD_isError(r)) r = ZSTD_CCtx_setParameter(cc, ZSTD_c_dictIDFlag, 0);
  if (!ZSTD_isError(r))
    r = ZSTD_CCtx_setParameter(cc, ZSTD_c_contentSizeFlag, 1);
  if (!ZSTD_isError(r) && c->cdict) r = ZSTD_CCtx_refCDict(cc, c->cdict);
  if (ZSTD_isError(r)) {
    ZSTD_freeCCtx(cc);
    return NULL;
  }
  return cc;
}

static void worker(void *arg) {
  zvfs_conv *c = (zvfs_conv *)arg;
  ZSTD_CCtx *cc = make_cctx(c);
  uint64_t seen = 0;
  zplat_lock(&c->mu);
  for (;;) {
    while (c->gen == seen && !c->quit) zplat_cond_wait(&c->cv_work, &c->mu);
    if (c->quit) break;
    seen = c->gen;
    batch *b = c->job;
    zplat_unlock(&c->mu);
    if (cc) compress_batch(c, cc, b);
    else zplat_atomic_store(&b->err, ZVFS_ERR_NOMEM);
    zplat_lock(&c->mu);
    if (--c->busy == 0) zplat_cond_broadcast(&c->cv_done);
  }
  zplat_unlock(&c->mu);
  ZSTD_freeCCtx(cc);
}

static int write_at(zvfs_conv *c, const void *p, size_t n) {
  if (zplat_pwrite(c->out, p, n, c->write_off))
    return fail(c, ZVFS_ERR_IO, "write to destination failed");
  c->write_off += n;
  zplat_atomic_store(&c->bytes_out, (int64_t)c->write_off);
  return ZVFS_OK;
}

/* Would n bytes at `at` touch SQLite's lock bytes (mandatory on Windows)? */
static int needs_gap(const zvfs_conv *c, uint64_t at, uint64_t n) {
  uint64_t lo = zvfs_g_lock_byte, hi = lo + ZDB_LOCK_SIZE;
  return !(c->h.incompat & ZDB_INCOMPAT_LOCK_GAP) && at < hi && at + n > lo;
}

/* Pads from the write position past the lock bytes; readers never read it. */
static int write_gap(zvfs_conv *c) {
  static const uint8_t zero[4096];
  uint64_t end = zvfs_g_lock_byte + ZDB_LOCK_SIZE;
  c->h.gap_start = c->write_off;
  c->h.gap_end = end;
  c->h.incompat |= ZDB_INCOMPAT_LOCK_GAP;
  while (c->write_off < end) {
    uint64_t k = end - c->write_off;
    int rc = write_at(c, zero, k < sizeof zero ? (size_t)k : sizeof zero);
    if (rc) return rc;
  }
  return ZVFS_OK;
}

/* Waits for the in-flight batch and appends its frames in order. */
static int drain(zvfs_conv *c) {
  if (c->inflight < 0) return c->failed;
  batch *b = &c->b[c->inflight];
  zplat_lock(&c->mu);
  while (c->busy > 0) zplat_cond_wait(&c->cv_done, &c->mu);
  c->job = NULL;
  zplat_unlock(&c->mu);
  c->inflight = -1;
  int64_t err = zplat_atomic_load(&b->err);
  if (err == ZVFS_ERR_CANCELLED) return fail(c, ZVFS_ERR_CANCELLED, "cancelled");
  if (err == ZVFS_ERR_CORRUPT) return fail(c, ZVFS_ERR_CORRUPT, "a copied frame is corrupt");
  if (err) return fail(c, (int)err, "compression failed");
  if (c->failed) return c->failed;
  /* in order: copied frames are decoded only by the workers */
  XXH64_update(&c->content, b->in, b->in_len);
  for (uint32_t i = 0; i < b->n_frames; i++) c->frames_copied += b->pre[i];

  uint64_t need = b->first_frame + b->n_frames + 1;
  if (need > c->index_cap) {
    uint64_t cap = c->index_cap ? c->index_cap : 4096;
    while (cap < need) cap *= 2;
    uint64_t *ni = (uint64_t *)realloc(c->index, (size_t)cap * sizeof(uint64_t));
    if (!ni) return fail(c, ZVFS_ERR_NOMEM, "out of memory (index)");
    c->index = ni;
    c->index_cap = cap;
  }
  size_t packed = 0;
  for (uint32_t i = 0; i < b->n_frames; i++) {
    if (needs_gap(c, c->write_off + packed, b->out_len[i])) {
      int rc = packed ? write_at(c, b->out, packed) : ZVFS_OK;
      if (!rc) rc = write_gap(c);
      if (rc) return rc;
      packed = 0;
    }
    c->index[b->first_frame + i] = c->write_off + packed;
    memmove(b->out + packed, b->out + (size_t)i * c->out_stride, b->out_len[i]);
    packed += b->out_len[i];
  }
  c->frames_written = b->first_frame + b->n_frames;
  return write_at(c, b->out, packed);
}

static int submit_fill(zvfs_conv *c) {
  batch *b = &c->b[c->fill];
  if (b->in_len == 0) return c->failed;
  int rc = drain(c);
  if (rc) return rc;
  b->n_frames = (uint32_t)((b->in_len + c->frame_bytes - 1) / c->frame_bytes);
  b->first_frame = c->frames_written;
  zplat_atomic_store(&b->next, 0);
  zplat_atomic_store(&b->err, 0);
  zplat_lock(&c->mu);
  c->job = b;
  c->gen++;
  c->busy = c->n_threads_started;
  zplat_cond_broadcast(&c->cv_work);
  zplat_unlock(&c->mu);
  c->inflight = c->fill;
  c->fill ^= 1;
  c->b[c->fill].in_len = 0;
  memset(c->b[c->fill].pre, 0, c->frames_per_batch);
  return ZVFS_OK;
}

static uint32_t be16(const uint8_t *p) { return (uint32_t)p[0] << 8 | p[1]; }
static uint32_t be32(const uint8_t *p) {
  return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}

static int setup_from_sqlite_header(zvfs_conv *c) {
  uint8_t *hd = c->sqlite_hdr;
  if (memcmp(hd, "SQLite format 3", 16) != 0)
    return fail(c, ZVFS_ERR_INVALID, "source is not an SQLite database");
  uint32_t ps = be16(hd + 16);
  if (ps == 1) ps = 65536;
  if (ps < 512 || ps > 65536 || (ps & (ps - 1)))
    return fail(c, ZVFS_ERR_INVALID, "invalid SQLite page size");
  if (hd[18] == 2 || hd[19] == 2) {
    /* Serve a rollback-mode header so read-only opens need no -shm file. */
    hd[18] = 1;
    hd[19] = 1;
    c->h.compat |= ZDB_COMPAT_WAL_HEADER_PATCHED;
  }
  if ((uint64_t)ps * c->frame_pages > ZDB_MAX_FRAME_BYTES)
    return fail(c, ZVFS_ERR_INVALID, "frame too large");
  if (c->zero && c->zero_ps != ps)
    return fail(c, ZVFS_ERR_INVALID, "source changed after its freelist was read");
  c->h.page_size = ps;
  c->frame_bytes = (uint64_t)ps * c->frame_pages;
  c->out_stride = ZSTD_compressBound((size_t)c->frame_bytes);
  uint64_t fpb = c->batch_bytes / c->frame_bytes;
  if (fpb < 1) fpb = 1;
  if (fpb > 1u << 20) fpb = 1u << 20;
  c->frames_per_batch = (uint32_t)fpb;
  for (int i = 0; i < 2; i++) {
    batch *b = &c->b[i];
    b->in = (uint8_t *)malloc((size_t)(fpb * c->frame_bytes));
    b->out = (uint8_t *)malloc((size_t)fpb * c->out_stride);
    b->out_len = (size_t *)calloc((size_t)fpb, sizeof(size_t));
    b->pre = (uint8_t *)calloc((size_t)fpb, 1);
    if (!b->in || !b->out || !b->out_len || !b->pre)
      return fail(c, ZVFS_ERR_NOMEM, "out of memory (batch buffers)");
  }
  return ZVFS_OK;
}

static int zero_page(const zvfs_conv *c, uint64_t pg) {
  return pg < c->zero_npages && (c->zero[pg >> 3] >> (pg & 7) & 1);
}

static int append_plain(zvfs_conv *c, const uint8_t *p, size_t n) {
  const uint32_t ps = c->h.page_size;
  while (n) {
    batch *b = &c->b[c->fill];
    size_t cap = (size_t)(c->frames_per_batch * c->frame_bytes);
    size_t k = cap - b->in_len < n ? cap - b->in_len : n;
    uint8_t *dst = b->in + b->in_len;
    int zero = 0;
    if (c->zero) {
      size_t left = ps - (size_t)(c->appended % ps);
      if (k > left) k = left;
      zero = zero_page(c, c->appended / ps);
    }
    if (zero) memset(dst, 0, k);
    else memcpy(dst, p, k);
    b->in_len += k;
    c->appended += k;
    p += k;
    n -= k;
    if (b->in_len == cap) {
      int rc = submit_fill(c);
      if (rc) return rc;
    }
  }
  return ZVFS_OK;
}

static int feed_plain(zvfs_conv *c, const void *data, size_t len) {
  if (c->failed) return c->failed;
  if (cancelled(c)) return fail(c, ZVFS_ERR_CANCELLED, "cancelled");
  const uint8_t *p = (const uint8_t *)data;
  if (c->frame_bytes && c->appended % c->frame_bytes &&
      c->b[c->fill].pre[c->b[c->fill].in_len / c->frame_bytes])
    return fail(c, ZVFS_ERR_INVALID, "internal: data after a partial copied frame");
  if (c->sqlite_hdr_len < SQLITE_HDR) {
    size_t k = SQLITE_HDR - c->sqlite_hdr_len;
    if (k > len) k = len;
    memcpy(c->sqlite_hdr + c->sqlite_hdr_len, p, k);
    c->sqlite_hdr_len += k;
    p += k;
    len -= k;
    if (c->sqlite_hdr_len < SQLITE_HDR) return ZVFS_OK;
    int rc = setup_from_sqlite_header(c);
    if (!rc) rc = append_plain(c, c->sqlite_hdr, SQLITE_HDR);
    if (rc) return rc;
  }
  return len ? append_plain(c, p, len) : ZVFS_OK;
}

ZVFS_API int zvfs_conv_feed(zvfs_conv *c, const void *data, size_t len) {
  if (!c || (len && !data)) return ZVFS_ERR_INVALID;
  int rc = feed_plain(c, data, len);
  if (!rc) zplat_atomic_add(&c->bytes_in, (int64_t)len);
  return rc;
}

int zvfs_conv_feed_frame(zvfs_conv *c, const void *frame, size_t flen,
                         size_t n) {
  if (!c || !frame) return ZVFS_ERR_INVALID;
  if (c->failed) return c->failed;
  if (cancelled(c)) return fail(c, ZVFS_ERR_CANCELLED, "cancelled");
  /* frame 0 goes through the header checks */
  if (!c->copy || c->sqlite_hdr_len < SQLITE_HDR || !n ||
      n > c->frame_bytes || c->appended % c->frame_bytes ||
      flen > c->out_stride)
    return ZVFS_ERR_UNSUPPORTED;
  batch *b = &c->b[c->fill];
  size_t slot = b->in_len / (size_t)c->frame_bytes;
  memcpy(b->out + slot * c->out_stride, frame, flen);
  b->out_len[slot] = flen;
  b->pre[slot] = 1;
  b->in_len += n;
  c->appended += n;
  zplat_atomic_add(&c->bytes_in, (int64_t)n);
  if (b->in_len == (size_t)(c->frames_per_batch * c->frame_bytes))
    return submit_fill(c);
  return ZVFS_OK;
}

void zvfs_conv_set_copy_ddict(zvfs_conv *c, const void *ddict) {
  c->copy = 1;
  c->copy_ddict = ddict;
}

ZVFS_API int zvfs_conv_feed_zstd(zvfs_conv *c, const void *data, size_t len) {
  if (!c || (len && !data)) return ZVFS_ERR_INVALID;
  if (c->failed) return c->failed;
  if (!c->zin) {
    c->zin = ZSTD_createDStream();
    c->zbuf = (uint8_t *)malloc(ZSTD_DStreamOutSize());
    if (!c->zin || !c->zbuf) return fail(c, ZVFS_ERR_NOMEM, "out of memory");
    ZSTD_initDStream(c->zin);
    /* seforim.db.zst is made with --long=31; the default cap is 2^27 */
    if (ZSTD_isError(ZSTD_DCtx_setParameter(c->zin, ZSTD_d_windowLogMax,
                                            ZSTD_WINDOWLOG_MAX)))
      return fail(c, ZVFS_ERR_INVALID, "zstd window limit rejected");
  }
  ZSTD_inBuffer in = {data, len, 0};
  for (;;) {
    ZSTD_outBuffer out = {c->zbuf, ZSTD_DStreamOutSize(), 0};
    size_t in_before = in.pos;
    size_t r = ZSTD_decompressStream(c->zin, &out, &in);
    if (ZSTD_isError(r))
      return fail(c, ZVFS_ERR_INVALID, "invalid zstd source stream");
    /* an empty call after a finished frame returns the next header hint */
    if (r == 0) c->zin_mid_frame = 0;
    else if (in.pos > in_before || out.pos > 0) c->zin_mid_frame = 1;
    if (out.pos) {
      int rc = feed_plain(c, c->zbuf, out.pos);
      if (rc) return rc;
    }
    /* a full output buffer may leave decoded bytes pending */
    if (in.pos == in.size && out.pos < out.size) break;
  }
  zplat_atomic_add(&c->bytes_in, (int64_t)len);
  return ZVFS_OK;
}

ZVFS_API int zvfs_conv_create(const char *dst, const void *dict,
                              size_t dict_len, const char *dict_name,
                              int level, int threads, uint32_t frame_pages,
                              uint64_t batch_bytes, volatile int32_t *cancel,
                              zvfs_conv **out) {
  if (!dst || !out || dict_len > ZDB_MAX_DICT || (dict_len && !dict))
    return ZVFS_ERR_INVALID;
  *out = NULL;
  if (level < 1) level = 1;
  if (level > ZSTD_maxCLevel()) level = ZSTD_maxCLevel();
  if (threads < 1) threads = 1;
  if (threads > MAX_THREADS) threads = MAX_THREADS;
  if (frame_pages < 1) frame_pages = 1;
  if (batch_bytes == 0) batch_bytes = 16ull << 20;
  /* keeps the batch buffer math inside size_t on 32-bit targets */
  if (batch_bytes > (256ull << 20)) batch_bytes = 256ull << 20;
  zvfs_conv *c = (zvfs_conv *)calloc(1, sizeof *c);
  if (!c) return ZVFS_ERR_NOMEM;
  c->cancel = cancel;
  c->level = level;
  c->threads = threads;
  c->frame_pages = frame_pages;
  c->batch_bytes = batch_bytes;
  c->inflight = -1;
  zplat_mutex_init(&c->mu);
  zplat_cond_init(&c->cv_work);
  zplat_cond_init(&c->cv_done);
  XXH64_reset(&c->content, 0);

  c->h.major = ZDB_FORMAT_MAJOR;
  c->h.minor = ZDB_FORMAT_MINOR;
  c->h.header_size = ZDB_HEADER_SIZE;
  c->h.frame_pages = frame_pages;
  c->h.codec = ZDB_CODEC_ZSTD_MAGICLESS;
  c->h.level = (uint32_t)level;
  c->h.dict_offset = ZDB_HEADER_SIZE;
  c->h.dict_length = (uint32_t)dict_len;
  if (dict_name) snprintf(c->h.dict_name, sizeof c->h.dict_name, "%s", dict_name);
  zplat_random(c->h.uuid, sizeof c->h.uuid);
  c->h.created_ms = zplat_now_ms();

  int rc = ZVFS_OK;
  if (dict_len) {
    c->h.dict_id = ZSTD_getDictID_fromDict(dict, dict_len);
    c->h.dict_xxh64 = XXH64(dict, dict_len, 0);
    c->cdict = ZSTD_createCDict(dict, dict_len, level);
    if (!c->cdict) rc = ZVFS_ERR_INVALID;
  }
  if (!rc) rc = zplat_open_write(dst, &c->out);
  if (!rc) {
    uint8_t zero[ZDB_HEADER_SIZE];
    memset(zero, 0, sizeof zero);
    rc = write_at(c, zero, sizeof zero);
    if (!rc && dict_len) rc = write_at(c, dict, dict_len);
  }
  for (int i = 0; !rc && i < threads; i++) {
    if (zplat_thread_start(&c->th[i], worker, c)) {
      if (i == 0) rc = ZVFS_ERR_NOMEM;
      break;
    }
    c->n_threads_started++;
  }
  if (rc) {
    zvfs_conv_destroy(c);
    return rc;
  }
  *out = c;
  return ZVFS_OK;
}

void zvfs_conv_set_lineage(zvfs_conv *c, const uint8_t derived_from[16],
                           const uint8_t overlay_uuid[16], uint64_t seq) {
  memcpy(c->h.derived_from_uuid, derived_from, 16);
  memcpy(c->h.includes_overlay_uuid, overlay_uuid, 16);
  c->h.includes_overlay_seq = seq;
}

ZVFS_API int zvfs_conv_set_identity(zvfs_conv *c, int uuid_from_content,
                                    int64_t created_unix_ms) {
  if (!c || c->failed) return ZVFS_ERR_INVALID;
  c->uuid_from_content = uuid_from_content != 0;
  if (created_unix_ms >= 0) c->h.created_ms = (uint64_t)created_unix_ms;
  return ZVFS_OK;
}

static void put64le(uint8_t *p, uint64_t v) {
  for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (8 * i));
}

/* Hash of every other header field (created_ms excluded), so equal inputs
   and settings give equal files. */
static void uuid_from_header(zdb_header *h) {
  zdb_header t = *h;
  memset(t.uuid, 0, sizeof t.uuid);
  t.created_ms = 0;
  uint8_t raw[ZDB_HEADER_CORE];
  zdb_header_encode(&t, raw);
  put64le(h->uuid, XXH64(raw, ZDB_HEADER_CORE - 8, 1));
  put64le(h->uuid + 8, XXH64(raw, ZDB_HEADER_CORE - 8, 2));
}

ZVFS_API int zvfs_conv_finish(zvfs_conv *c, zvfs_info *info) {
  if (!c) return ZVFS_ERR_INVALID;
  if (c->failed) return c->failed;
  if (cancelled(c)) return fail(c, ZVFS_ERR_CANCELLED, "cancelled");
  if (c->zin && c->zin_mid_frame)
    return fail(c, ZVFS_ERR_INVALID, "zstd source stream is truncated");
  if (c->sqlite_hdr_len < SQLITE_HDR)
    return fail(c, ZVFS_ERR_INVALID, "source is too short");
  uint64_t logical = c->appended;
  if (logical % c->h.page_size)
    return fail(c, ZVFS_ERR_INVALID, "source size is not a multiple of the page size");
  const uint8_t *hd = c->sqlite_hdr;
  uint32_t hdr_pages = be32(hd + 28);
  if (hdr_pages && be32(hd + 92) == be32(hd + 24) &&
      logical < (uint64_t)hdr_pages * c->h.page_size)
    return fail(c, ZVFS_ERR_INVALID, "source is shorter than its SQLite header says");

  int rc = submit_fill(c);
  if (!rc) rc = drain(c);
  if (rc) return rc;

  uint64_t n = c->frames_written;
  c->h.logical_size = logical;
  c->h.frame_count = n;
  if (n + 1 > c->index_cap) {
    uint64_t *ni = (uint64_t *)realloc(c->index, (size_t)(n + 1) * sizeof(uint64_t));
    if (!ni) return fail(c, ZVFS_ERR_NOMEM, "out of memory (index)");
    c->index = ni;
    c->index_cap = n + 1;
  }
  if (needs_gap(c, c->write_off, (n + 1) * 8)) {
    rc = write_gap(c);
    if (rc) return rc;
  }
  c->index[n] = c->write_off;
  c->h.index_offset = c->write_off;
  c->h.index_length = (n + 1) * 8;
  c->h.content_xxh64 = XXH64_digest(&c->content);

  XXH64_state_t ih;
  XXH64_reset(&ih, 0);
  uint8_t chunk[8 * 4096];
  for (uint64_t i = 0; i <= n;) {
    uint64_t k = n + 1 - i > 4096 ? 4096 : n + 1 - i;
    for (uint64_t j = 0; j < k; j++) put64le(chunk + j * 8, c->index[i + j]);
    XXH64_update(&ih, chunk, (size_t)k * 8);
    rc = write_at(c, chunk, (size_t)k * 8);
    if (rc) return rc;
    i += k;
  }
  c->h.index_xxh64 = XXH64_digest(&ih);
  if (c->uuid_from_content) uuid_from_header(&c->h);

  uint8_t raw[ZDB_HEADER_CORE];
  zdb_header_encode(&c->h, raw);
  zdb_header check;
  if (zdb_header_decode(raw, &check) != ZVFS_OK)
    return fail(c, ZVFS_ERR_INVALID, "internal: produced an invalid header");
  if (zplat_pwrite(c->out, raw, sizeof raw, 0))
    return fail(c, ZVFS_ERR_IO, "writing header failed");
  if (zplat_sync(c->out)) return fail(c, ZVFS_ERR_IO, "fsync failed");
  if (info) {
    memset(info, 0, sizeof *info);
    info->format_major = c->h.major;
    info->format_minor = c->h.minor;
    info->page_size = c->h.page_size;
    info->frame_pages = c->h.frame_pages;
    info->logical_size = c->h.logical_size;
    info->frame_count = c->h.frame_count;
    info->physical_size = c->write_off;
    info->dict_id = c->h.dict_id;
    info->dict_length = c->h.dict_length;
    info->level = c->h.level;
    info->compat_features = c->h.compat;
    info->content_xxh64 = c->h.content_xxh64;
    info->created_unix_ms = c->h.created_ms;
    memcpy(info->file_uuid, c->h.uuid, 16);
    memcpy(info->dict_name, c->h.dict_name, 32);
    info->base_logical_size = c->h.logical_size;
    info->includes_overlay_seq = c->h.includes_overlay_seq;
    memcpy(info->derived_from_uuid, c->h.derived_from_uuid, 16);
    memcpy(info->includes_overlay_uuid, c->h.includes_overlay_uuid, 16);
  }
  zplat_close(c->out);
  c->out = NULL;
  c->failed = ZVFS_ERR_INVALID; /* finished: further feeds are rejected */
  snprintf(c->err, sizeof c->err, "converter already finished");
  return ZVFS_OK;
}

ZVFS_API void zvfs_conv_progress(zvfs_conv *c, uint64_t *in, uint64_t *out) {
  if (!c) return;
  if (in) *in = (uint64_t)zplat_atomic_load(&c->bytes_in);
  if (out) *out = (uint64_t)zplat_atomic_load(&c->bytes_out);
}

ZVFS_API const char *zvfs_conv_error(zvfs_conv *c) {
  return c && c->failed ? c->err : "";
}

ZVFS_API void zvfs_conv_destroy(zvfs_conv *c) {
  if (!c) return;
  if (c->inflight >= 0) {
    zplat_lock(&c->mu);
    while (c->busy > 0) zplat_cond_wait(&c->cv_done, &c->mu);
    zplat_unlock(&c->mu);
  }
  zplat_lock(&c->mu);
  c->quit = 1;
  zplat_cond_broadcast(&c->cv_work);
  zplat_unlock(&c->mu);
  for (int i = 0; i < c->n_threads_started; i++) zplat_thread_join(c->th[i]);
  for (int i = 0; i < 2; i++) {
    free(c->b[i].in);
    free(c->b[i].out);
    free(c->b[i].out_len);
    free(c->b[i].pre);
  }
  free(c->zero);
  zplat_close(c->out);
  if (c->cdict) ZSTD_freeCDict(c->cdict);
  if (c->zin) ZSTD_freeDStream(c->zin);
  free(c->zbuf);
  free(c->index);
  zplat_cond_destroy(&c->cv_work);
  zplat_cond_destroy(&c->cv_done);
  zplat_mutex_destroy(&c->mu);
  free(c);
}

/* ---- SQLite freelist (see the file format: trunk and leaf pages) ---- */
#define BIT_GET(m, i) ((m)[(i) >> 3] >> ((i) & 7) & 1)
#define BIT_SET(m, i) ((m)[(i) >> 3] |= (uint8_t)(1u << ((i) & 7)))

int zvfs_freelist_leaves(zdb_read_fn rd, void *ctx, uint64_t size,
                         zvfs_pageset *out) {
  memset(out, 0, sizeof *out);
  uint8_t hd[SQLITE_HDR];
  int rc = rd(ctx, hd, sizeof hd, 0);
  if (rc) return rc == ZVFS_ERR_SHORT_READ ? ZVFS_OK : rc;
  if (memcmp(hd, "SQLite format 3", 16) != 0) return ZVFS_OK;
  uint32_t ps = be16(hd + 16);
  if (ps == 1) ps = 65536;
  if (ps < 512 || ps > 65536 || (ps & (ps - 1))) return ZVFS_OK;
  uint64_t pages = size / ps;
  uint32_t trunk = be32(hd + 32), total = be32(hd + 36);
  uint32_t usable = ps - hd[20];
  if (!trunk || !total || total >= pages || usable < 480) return ZVFS_OK;
  size_t nb = (size_t)((pages + 7) / 8);
  uint8_t *seen = (uint8_t *)calloc(nb, 1), *leaf = (uint8_t *)calloc(nb, 1);
  uint8_t *page = (uint8_t *)malloc(ps);
  if (!seen || !leaf || !page) rc = ZVFS_ERR_NOMEM;
  uint64_t count = 0, leaves = 0;
  int ok = !rc;
  /* page numbers are 1-based, bits 0-based */
  while (ok && trunk) {
    if (trunk < 2 || trunk > pages || BIT_GET(seen, trunk - 1) || ++count > total) {
      ok = 0;
      break;
    }
    BIT_SET(seen, trunk - 1);
    rc = rd(ctx, page, ps, (uint64_t)(trunk - 1) * ps);
    if (rc) {
      if (rc == ZVFS_ERR_SHORT_READ) rc = ZVFS_OK;
      ok = 0;
      break;
    }
    uint32_t n = be32(page + 4);
    if (n > usable / 4 - 2 || count + n > total) {
      ok = 0;
      break;
    }
    for (uint32_t i = 0; ok && i < n; i++) {
      uint32_t p = be32(page + 8 + 4 * i);
      if (p < 2 || p > pages || BIT_GET(seen, p - 1)) {
        ok = 0;
      } else {
        BIT_SET(seen, p - 1);
        BIT_SET(leaf, p - 1);
      }
    }
    count += n;
    leaves += n;
    trunk = be32(page);
  }
  /* an inconsistent list is left as it is: nothing is zeroed */
  if (ok && !rc && count == total && leaves) {
    out->bits = leaf;
    out->npages = pages;
    out->count = leaves;
    out->page_size = ps;
    leaf = NULL;
  }
  free(seen);
  free(leaf);
  free(page);
  return rc;
}

int zvfs_conv_set_zero_pages(zvfs_conv *c, zvfs_pageset *set) {
  if (c->failed) return c->failed;
  if (c->sqlite_hdr_len || c->zero) return fail(c, ZVFS_ERR_INVALID, "already fed");
  c->zero = set->bits;
  c->zero_npages = set->npages;
  c->zero_ps = set->page_size;
  set->bits = NULL;
  return ZVFS_OK;
}

uint64_t zvfs_conv_frames_copied(const zvfs_conv *c) { return c->frames_copied; }

static int file_rd(void *ctx, void *buf, size_t n, uint64_t off) {
  size_t got = 0;
  int rc = zplat_pread((zplat_file *)ctx, buf, n, off, &got);
  if (rc) return rc;
  return got == n ? ZVFS_OK : ZVFS_ERR_SHORT_READ;
}

ZVFS_API int zvfs_conv_zero_freelist(zvfs_conv *c, const char *src_path,
                                     uint64_t *leaf_pages) {
  if (!c || !src_path) return ZVFS_ERR_INVALID;
  if (leaf_pages) *leaf_pages = 0;
  zplat_file *pf;
  uint64_t size = 0;
  int rc = zplat_open_read(src_path, &pf);
  if (rc) return rc;
  zvfs_pageset set;
  rc = zplat_size(pf, &size);
  if (!rc) rc = zvfs_freelist_leaves(file_rd, pf, size, &set);
  zplat_close(pf);
  if (rc) return rc;
  if (!set.bits) return ZVFS_OK;
  if (leaf_pages) *leaf_pages = set.count;
  rc = zvfs_conv_set_zero_pages(c, &set);
  free(set.bits);
  return rc;
}
