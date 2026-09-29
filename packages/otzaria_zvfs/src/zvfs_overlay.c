/* Append-only page overlay <path>-zovl over an immutable .zdb base. */
#include <stdlib.h>
#include <string.h>

#include "zvfs_internal.h"

#define ZSTD_STATIC_LINKING_ONLY
#include "zstd.h"
#define XXH_INLINE_ALL
#include "common/xxhash.h"

#define LEAF_BITS 12
#define LEAF_SIZE (1u << LEAF_BITS)
#define SCAN_BUF (1u << 20)
#define NO_PAGE 0xFFFFFFFFu

typedef struct pend {
  uint32_t pgno;
  uint64_t off;
} pend;

struct zovl {
  zplat_mutex mu;  /* everything below except the writer fields */
  zplat_mutex wmu; /* writer: CCtx and read-modify-write */
  const zovl_ops *ops;
  void *env;
  void *h; /* NULL: no (usable) sidecar */
  zdb_file *base;
  uint32_t ps;
  uint8_t hdr[ZOVL_HEADER_SIZE];
  int derived; /* bound through the base's lineage fields */

  uint64_t committed_end, committed_chain, seq, commits, records;
  uint64_t committed_logical;
  uint64_t logical;    /* includes own unsealed writes */
  uint64_t base_limit; /* pages [0, base_limit) may come from the base */

  /* own unsealed batch */
  int batch_open;
  uint64_t tail, tail_chain;
  uint32_t pending;
  uint64_t synced_end;

  /* resume point inside a batch another process has not sealed yet */
  uint64_t scan_end, scan_chain, scan_last_off, scan_last_chain, scan_seen;
  pend *sb;
  size_t sb_n, sb_cap;

  uint32_t **leaf;
  size_t nleaf;
  uint64_t mapped;

  ZSTD_CCtx *cctx;
  ZSTD_CDict *cdict;
  uint8_t *wbuf, *page_tmp;
  size_t wcap, wlen;
  /* sticky: a failed commit or fsync leaves memory and disk out of step */
  int failed;
};

#ifdef ZVFS_TEST_HOOKS
/* Test builds only: runs where another connection could seal. */
void (*zvfs_test_after_append)(zovl *o);
#define AFTER_APPEND(o)                                    \
  do {                                                     \
    if (zvfs_test_after_append) zvfs_test_after_append(o); \
  } while (0)
#else
#define AFTER_APPEND(o) ((void)0)
#endif

static uint64_t align_up(uint64_t x) {
  return (x + ZOVL_ALIGN - 1) & ~(uint64_t)(ZOVL_ALIGN - 1);
}

static size_t max_payload(uint32_t ps) { return ZSTD_compressBound(ps) + 64; }

/* ---- page map: pgno -> record offset / ZOVL_ALIGN (0 = none) ---- */
static uint32_t map_get(const zovl *o, uint64_t pg) {
  uint64_t li = pg >> LEAF_BITS;
  if (li >= o->nleaf || !o->leaf[li]) return 0;
  return o->leaf[li][pg & (LEAF_SIZE - 1)];
}

static int map_reserve(zovl *o, uint64_t pg) {
  size_t li = (size_t)(pg >> LEAF_BITS);
  if (li >= o->nleaf) {
    size_t n = o->nleaf ? o->nleaf : 16;
    while (n <= li) n *= 2;
    uint32_t **nl = (uint32_t **)realloc(o->leaf, n * sizeof *nl);
    if (!nl) return ZVFS_ERR_NOMEM;
    memset(nl + o->nleaf, 0, (n - o->nleaf) * sizeof *nl);
    o->leaf = nl;
    o->nleaf = n;
  }
  if (!o->leaf[li]) {
    o->leaf[li] = (uint32_t *)calloc(LEAF_SIZE, sizeof(uint32_t));
    if (!o->leaf[li]) return ZVFS_ERR_NOMEM;
  }
  return ZVFS_OK;
}

/* Caller reserved the leaf. */
static void map_set(zovl *o, uint64_t pg, uint64_t off) {
  uint32_t *slot = &o->leaf[pg >> LEAF_BITS][pg & (LEAF_SIZE - 1)];
  if (!*slot) o->mapped++;
  *slot = (uint32_t)(off / ZOVL_ALIGN);
}

static void map_drop_from(zovl *o, uint64_t first) {
  for (uint64_t li = first >> LEAF_BITS; li < o->nleaf; li++) {
    uint32_t *l = o->leaf[li];
    if (!l) continue;
    uint64_t i = li == (first >> LEAF_BITS) ? (first & (LEAF_SIZE - 1)) : 0;
    for (; i < LEAF_SIZE; i++) {
      if (l[i]) {
        l[i] = 0;
        o->mapped--;
      }
    }
  }
}

static void map_clear(zovl *o) {
  for (size_t i = 0; i < o->nleaf; i++) free(o->leaf[i]);
  free(o->leaf);
  o->leaf = NULL;
  o->nleaf = 0;
  o->mapped = 0;
}

/* Shared by the writer and replay so both give identical results. */
static void apply_size(zovl *o, uint64_t size) {
  map_drop_from(o, (size + o->ps - 1) / o->ps);
  uint64_t full = size / o->ps;
  if (o->base_limit > full) o->base_limit = full;
  o->logical = size;
}

static void reset_to_base(zovl *o) {
  map_clear(o);
  o->logical = o->committed_logical = o->base->h.logical_size;
  o->base_limit = o->base->h.logical_size / o->ps;
  o->seq = o->commits = o->records = 0;
  o->committed_end = o->tail = o->scan_end = o->synced_end = ZOVL_HEADER_SIZE;
  o->committed_chain = o->tail_chain = o->scan_chain = 0;
  o->scan_last_off = o->scan_last_chain = o->scan_seen = 0;
  o->sb_n = 0;
  o->pending = 0;
  o->batch_open = 0;
  o->derived = 0;
}

/* ---- header ---- */
static void hdr_encode(zovl *o, const uint8_t uuid[16]) {
  uint8_t *h = o->hdr;
  const zdb_header *b = &o->base->h;
  memset(h, 0, ZOVL_HEADER_SIZE);
  memcpy(h, ZOVL_MAGIC, 8);
  h[8] = (uint8_t)ZOVL_FORMAT_MAJOR;
  h[10] = (uint8_t)ZOVL_FORMAT_MINOR;
  zdb_put32(h + 12, ZOVL_HEADER_SIZE);
  zdb_put32(h + 24, o->ps);
  zdb_put32(h + 28, ZOVL_ALIGN);
  memcpy(h + 32, b->uuid, 16);
  zdb_put64(h + 48, b->content_xxh64);
  zdb_put64(h + 56, b->logical_size);
  memcpy(h + 64, uuid, 16);
  zdb_put64(h + 80, zplat_now_ms());
  zdb_put64(h + 120, XXH64(h, 120, 0));
}

static int all_zero(const uint8_t *p, size_t n) {
  for (size_t i = 0; i < n; i++)
    if (p[i]) return 0;
  return 1;
}

/* ZVFS_OK (bound directly or via lineage), CORRUPT or UNSUPPORTED. */
static int hdr_check(zovl *o, const uint8_t *h, int *derived) {
  const zdb_header *b = &o->base->h;
  if (memcmp(h, ZOVL_MAGIC, 8) != 0) return ZVFS_ERR_CORRUPT;
  uint32_t major = (uint32_t)h[8] | (uint32_t)h[9] << 8;
  if (major != ZOVL_FORMAT_MAJOR) return ZVFS_ERR_UNSUPPORTED;
  if (zdb_get64(h + 120) != XXH64(h, 120, 0)) return ZVFS_ERR_CORRUPT;
  if (zdb_get32(h + 16) & ~ZOVL_KNOWN_INCOMPAT) return ZVFS_ERR_UNSUPPORTED;
  if (zdb_get32(h + 12) != ZOVL_HEADER_SIZE || zdb_get32(h + 24) != o->ps ||
      zdb_get32(h + 28) != ZOVL_ALIGN)
    return ZVFS_ERR_CORRUPT;
  if (memcmp(h + 32, b->uuid, 16) == 0) {
    if (zdb_get64(h + 48) != b->content_xxh64 ||
        zdb_get64(h + 56) != b->logical_size)
      return ZVFS_ERR_CORRUPT;
    *derived = 0;
    return ZVFS_OK;
  }
  /* A compacted base names the (random, unique) overlay it includes. */
  if (!all_zero(b->includes_overlay_uuid, 16) &&
      memcmp(h + 64, b->includes_overlay_uuid, 16) == 0) {
    *derived = 1;
    return ZVFS_OK;
  }
  return ZVFS_ERR_CORRUPT;
}

/* ---- buffered scan ---- */
typedef struct rbuf {
  uint8_t *p;
  uint64_t start;
  size_t len;
} rbuf;

/* NULL at EOF; *rc set only on I/O errors. */
static const uint8_t *rb_get(zovl *o, rbuf *b, uint64_t off, size_t n,
                             uint64_t size, int *rc) {
  if (off > size || size - off < n) return NULL;
  if (off >= b->start && off + n <= b->start + b->len)
    return b->p + (off - b->start);
  uint64_t want = size - off < SCAN_BUF ? size - off : SCAN_BUF;
  int r = o->ops->read(o->h, b->p, (size_t)want, off);
  b->start = off;
  b->len = 0;
  if (r == ZVFS_ERR_SHORT_READ) return NULL; /* shrank under us */
  if (r) {
    *rc = r;
    return NULL;
  }
  b->len = (size_t)want;
  return b->p;
}

static int sb_push(zovl *o, uint32_t pgno, uint64_t off) {
  if (o->sb_n == o->sb_cap) {
    size_t n = o->sb_cap ? o->sb_cap * 2 : 256;
    pend *nb = (pend *)realloc(o->sb, n * sizeof *nb);
    if (!nb) return ZVFS_ERR_NOMEM;
    o->sb = nb;
    o->sb_cap = n;
  }
  o->sb[o->sb_n].pgno = pgno;
  o->sb[o->sb_n].off = off;
  o->sb_n++;
  return ZVFS_OK;
}

/* Validates records from the resume point; applies each valid commit and
   stops at the first invalid or incomplete record (never truncates). */
static int scan(zovl *o, uint64_t size) {
  rbuf b = {NULL, 0, 0};
  b.p = (uint8_t *)malloc(SCAN_BUF);
  if (!b.p) return ZVFS_ERR_NOMEM;
  int rc = ZVFS_OK;
  uint64_t pos = o->scan_end, chain = o->scan_chain;
  size_t maxp = max_payload(o->ps);
  zvfs_stat_add(ZST_OVL_REFRESH_SCANS, 1);
  for (;;) {
    uint8_t r[ZOVL_COMMIT_SIZE];
    const uint8_t *q = rb_get(o, &b, pos, ZOVL_PAGE_HDR, size, &rc);
    if (!q) break;
    memcpy(r, q, ZOVL_PAGE_HDR);
    uint32_t tag = zdb_get32(r);
    if (tag == ZOVL_TAG_PAGE) {
      uint32_t pgno = zdb_get32(r + 4), len = zdb_get32(r + 8);
      if (zdb_get32(r + 12) != 0 || pgno == NO_PAGE || len == 0 || len > maxp ||
          ((uint64_t)pgno + 1) * o->ps > ZOVL_MAX_LOGICAL)
        break;
      uint64_t c = XXH64(r, 24, chain);
      if (c != zdb_get64(r + 24)) break;
      const uint8_t *pl = rb_get(o, &b, pos + ZOVL_PAGE_HDR, len, size, &rc);
      if (!pl || XXH64(pl, len, 0) != zdb_get64(r + 16)) break;
      uint64_t next = align_up(pos + ZOVL_PAGE_HDR + len);
      if (next > ZOVL_MAX_SIZE) break;
      rc = map_reserve(o, pgno);
      if (!rc) rc = sb_push(o, pgno, pos);
      if (rc) break;
      o->scan_last_off = pos;
      o->scan_last_chain = c;
      chain = c;
      pos = next;
    } else if (tag == ZOVL_TAG_COMMIT) {
      q = rb_get(o, &b, pos, ZOVL_COMMIT_SIZE, size, &rc);
      if (!q) break;
      memcpy(r, q, ZOVL_COMMIT_SIZE);
      uint64_t seq = zdb_get64(r + 16), lsize = zdb_get64(r + 24);
      if (zdb_get32(r + 4) != o->sb_n || zdb_get32(r + 8) != 0 ||
          zdb_get32(r + 12) != 0 || zdb_get64(r + 32) != 0 ||
          seq != o->seq + 1 || lsize > ZOVL_MAX_LOGICAL)
        break;
      uint64_t c = XXH64(r, 40, chain);
      if (c != zdb_get64(r + 40)) break;
      for (size_t i = 0; i < o->sb_n; i++) map_set(o, o->sb[i].pgno, o->sb[i].off);
      apply_size(o, lsize);
      o->committed_logical = lsize;
      o->records += o->sb_n;
      o->sb_n = 0;
      o->seq = seq;
      o->commits++;
      pos += ZOVL_COMMIT_SIZE;
      chain = c;
      o->committed_end = o->tail = pos;
      o->committed_chain = o->tail_chain = c;
    } else {
      break;
    }
  }
  o->scan_end = pos;
  o->scan_chain = chain;
  free(b.p);
  return rc;
}

/* Replays the open sidecar from scratch. *present = 0: torn creation or
   obsolete after compaction, i.e. serve the base alone. */
static int load(zovl *o, int *present) {
  reset_to_base(o);
  *present = 0;
  uint64_t size = 0;
  int rc = o->ops->size(o->h, &size);
  if (rc) return rc;
  /* Records follow only a synced header: a file this short holds no commit,
     whatever its bytes say (a torn creation). */
  if (size <= ZOVL_HEADER_SIZE) return ZVFS_OK;
  uint8_t h[ZOVL_HEADER_SIZE];
  rc = o->ops->read(o->h, h, sizeof h, 0);
  if (rc) return rc == ZVFS_ERR_SHORT_READ ? ZVFS_OK : rc;
  int derived = 0;
  rc = hdr_check(o, h, &derived);
  if (rc) return rc;
  memcpy(o->hdr, h, sizeof h);
  o->derived = derived;
  o->committed_chain = o->tail_chain = o->scan_chain = XXH64(h, sizeof h, 0);
  rc = scan(o, size);
  if (rc) return rc;
  o->scan_seen = size;
  if (derived && o->seq <= o->base->h.includes_overlay_seq) {
    reset_to_base(o);
    return ZVFS_OK;
  }
  *present = 1;
  return ZVFS_OK;
}

static void close_file(zovl *o) {
  if (o->h) o->ops->close(o->h);
  o->h = NULL;
}

int zovl_create(const zovl_ops *ops, void *env, zdb_file *base, zovl **out) {
  *out = NULL;
  zovl *o = (zovl *)calloc(1, sizeof *o);
  if (!o) return ZVFS_ERR_NOMEM;
  zplat_mutex_init(&o->mu);
  zplat_mutex_init(&o->wmu);
  o->ops = ops;
  o->base = base;
  o->ps = base->h.page_size;
  reset_to_base(o);
  int rc = ops->open(env, 0, &o->h);
  if (!rc && o->h) {
    o->env = env;
    int present = 0;
    rc = load(o, &present);
    if (rc || !present) close_file(o);
  }
  if (rc) {
    o->env = NULL; /* the caller keeps ownership on failure */
    zovl_free(o);
    return rc;
  }
  o->env = env;
  *out = o;
  return ZVFS_OK;
}

void zovl_free(zovl *o) {
  if (!o) return;
  close_file(o);
  map_clear(o);
  free(o->sb);
  if (o->cctx) ZSTD_freeCCtx(o->cctx);
  if (o->cdict) ZSTD_freeCDict(o->cdict);
  free(o->wbuf);
  free(o->page_tmp);
  if (o->env && o->ops->env_free) o->ops->env_free(o->env);
  zplat_mutex_destroy(&o->mu);
  zplat_mutex_destroy(&o->wmu);
  free(o);
}

/* Is the record that ends the known unsealed prefix still the same? */
static int resume_point_valid(zovl *o) {
  if (o->scan_end == o->committed_end) return 1;
  uint8_t r[ZOVL_PAGE_HDR];
  if (o->ops->read(o->h, r, sizeof r, o->scan_last_off) != ZVFS_OK) return 0;
  return zdb_get32(r) == ZOVL_TAG_PAGE && zdb_get64(r + 24) == o->scan_last_chain;
}

static void rewind_scan(zovl *o) {
  o->scan_end = o->committed_end;
  o->scan_chain = o->committed_chain;
  o->sb_n = 0;
  o->scan_seen = 0;
}

int zovl_refresh(zovl *o) {
  int rc = ZVFS_OK;
  zplat_lock(&o->mu);
  if (o->failed) {
    rc = ZVFS_ERR_IO;
    goto out;
  }
  if (o->batch_open) goto out; /* we are the writer: nobody else appends */
  if (!o->h) {
    rc = o->ops->open(o->env, 0, &o->h);
    if (!rc && o->h) {
      int present = 0;
      rc = load(o, &present);
      if (rc || !present) close_file(o);
    }
    goto out;
  }
  uint64_t size = 0;
  rc = o->ops->size(o->h, &size);
  if (rc) goto out;
  if (size < o->scan_end || !resume_point_valid(o)) rewind_scan(o);
  if (size > o->scan_end && size != o->scan_seen) {
    rc = scan(o, size);
    o->scan_seen = size;
  }
out:
  zplat_unlock(&o->mu);
  return rc;
}

/* ---- writer ---- */
static int ensure_file(zovl *o) {
  if (o->h) return ZVFS_OK;
  int rc = o->ops->open(o->env, 1, &o->h);
  if (rc) return rc;
  if (!o->h) return ZVFS_ERR_READONLY;
  int present = 0;
  rc = load(o, &present);
  if (rc) {
    close_file(o);
    return rc;
  }
  if (present) return ZVFS_OK;
  uint8_t uuid[16];
  zplat_random(uuid, sizeof uuid);
  hdr_encode(o, uuid);
  rc = o->ops->truncate(o->h, 0);
  if (!rc) rc = o->ops->write(o->h, o->hdr, ZOVL_HEADER_SIZE, 0);
  /* SQLITE_SYNC_NORMAL; records may only follow a durable header */
  if (!rc) rc = o->ops->sync(o->h, 2);
  if (rc) {
    close_file(o);
    reset_to_base(o);
    return rc;
  }
  o->committed_chain = o->tail_chain = o->scan_chain =
      XXH64(o->hdr, ZOVL_HEADER_SIZE, 0);
  return ZVFS_OK;
}

/* Caller holds mu. The first record of a batch drops any torn tail. */
static int begin_batch(zovl *o) {
  if (o->batch_open) return ZVFS_OK;
  int rc = ensure_file(o);
  if (rc) return rc;
  uint64_t size = 0;
  rc = o->ops->size(o->h, &size);
  if (!rc && size > o->committed_end)
    rc = o->ops->truncate(o->h, o->committed_end);
  if (rc) return rc;
  o->tail = o->committed_end;
  o->tail_chain = o->committed_chain;
  rewind_scan(o);
  o->batch_open = 1;
  return ZVFS_OK;
}

static int append(zovl *o, const uint8_t *rec, size_t n) {
  if (o->tail + n > ZOVL_MAX_SIZE) return ZVFS_ERR_FULL;
  int rc = o->ops->write(o->h, rec, n, o->tail);
  if (rc) return rc;
  o->tail += n;
  zvfs_stat_add(ZST_OVL_BYTES, (int64_t)n);
  return ZVFS_OK;
}

static int writer_init(zovl *o) {
  if (o->cctx) return ZVFS_OK;
  o->wcap = (size_t)align_up(ZOVL_PAGE_HDR + max_payload(o->ps));
  o->wbuf = (uint8_t *)malloc(o->wcap);
  o->page_tmp = (uint8_t *)malloc(o->ps);
  if (!o->wbuf || !o->page_tmp) return ZVFS_ERR_NOMEM;
  if (o->base->h.dict_length) {
    o->cdict = ZSTD_createCDict(o->base->dict, o->base->h.dict_length, ZOVL_LEVEL);
    if (!o->cdict) return ZVFS_ERR_NOMEM;
  }
  ZSTD_CCtx *cc = ZSTD_createCCtx();
  if (!cc) return ZVFS_ERR_NOMEM;
  size_t r = ZSTD_CCtx_setParameter(cc, ZSTD_c_format, ZSTD_f_zstd1_magicless);
  if (!ZSTD_isError(r))
    r = ZSTD_CCtx_setParameter(cc, ZSTD_c_compressionLevel, ZOVL_LEVEL);
  if (!ZSTD_isError(r)) r = ZSTD_CCtx_setParameter(cc, ZSTD_c_checksumFlag, 1);
  if (!ZSTD_isError(r)) r = ZSTD_CCtx_setParameter(cc, ZSTD_c_dictIDFlag, 0);
  if (!ZSTD_isError(r)) r = ZSTD_CCtx_setParameter(cc, ZSTD_c_contentSizeFlag, 1);
  if (!ZSTD_isError(r) && o->cdict) r = ZSTD_CCtx_refCDict(cc, o->cdict);
  if (ZSTD_isError(r)) {
    ZSTD_freeCCtx(cc);
    return ZVFS_ERR_NOMEM;
  }
  o->cctx = cc;
  return ZVFS_OK;
}

/* Caller holds wmu: compresses into wbuf, outside mu. */
static int build_page_record(zovl *o, uint64_t pg, const uint8_t *page) {
  if (pg >= NO_PAGE) return ZVFS_ERR_FULL;
  size_t z = ZSTD_compress2(o->cctx, o->wbuf + ZOVL_PAGE_HDR,
                            o->wcap - ZOVL_PAGE_HDR, page, o->ps);
  if (ZSTD_isError(z)) return ZVFS_ERR_NOMEM;
  o->wlen = (size_t)align_up(ZOVL_PAGE_HDR + z);
  memset(o->wbuf + ZOVL_PAGE_HDR + z, 0, o->wlen - ZOVL_PAGE_HDR - z);
  uint8_t *r = o->wbuf;
  zdb_put32(r, ZOVL_TAG_PAGE);
  zdb_put32(r + 4, (uint32_t)pg);
  zdb_put32(r + 8, (uint32_t)z);
  zdb_put32(r + 12, 0);
  zdb_put64(r + 16, XXH64(r + ZOVL_PAGE_HDR, z, 0));
  return ZVFS_OK;
}

/* Caller holds wmu and mu. Record, map entry and size change in one step:
   a seal from another connection must never split them. */
static int append_page_locked(zovl *o, uint64_t pg, uint64_t end) {
  int rc = o->failed ? ZVFS_ERR_IO : begin_batch(o);
  if (!rc) rc = map_reserve(o, pg);
  if (rc) return rc;
  uint8_t *r = o->wbuf;
  uint64_t c = XXH64(r, 24, o->tail_chain);
  zdb_put64(r + 24, c);
  uint64_t at = o->tail;
  rc = append(o, r, o->wlen);
  if (rc) return rc;
  o->tail_chain = c;
  o->pending++;
  map_set(o, pg, at);
  if (end > o->logical) o->logical = end;
  zvfs_stat_add(ZST_OVL_RECORDS, 1);
  return ZVFS_OK;
}

/* ---- reads ---- */
static int read_record(zovl *o, uint64_t pg, uint64_t off, uint8_t *dst) {
  size_t maxp = max_payload(o->ps);
  size_t first = ZOVL_PAGE_HDR + o->ps;
  uint8_t *buf = (uint8_t *)malloc(ZOVL_PAGE_HDR + maxp);
  if (!buf) return ZVFS_ERR_NOMEM;
  int rc = o->ops->read(o->h, buf, first, off);
  if (rc == ZVFS_ERR_SHORT_READ) rc = ZVFS_OK; /* last record; checked below */
  uint32_t len = rc ? 0 : zdb_get32(buf + 8);
  if (!rc && (zdb_get32(buf) != ZOVL_TAG_PAGE || zdb_get32(buf + 4) != pg ||
              len == 0 || len > maxp))
    rc = ZVFS_ERR_CORRUPT;
  if (!rc && ZOVL_PAGE_HDR + len > first) {
    rc = o->ops->read(o->h, buf + first, ZOVL_PAGE_HDR + len - first,
                      off + first);
    if (rc == ZVFS_ERR_SHORT_READ) rc = ZVFS_ERR_CORRUPT;
  }
  if (!rc && XXH64(buf + ZOVL_PAGE_HDR, len, 0) != zdb_get64(buf + 16))
    rc = ZVFS_ERR_CORRUPT;
  if (!rc) rc = zdb_decode(o->base->ddict, buf + ZOVL_PAGE_HDR, len, dst, o->ps);
  free(buf);
  zvfs_stat_add(ZST_OVL_PAGE_READS, 1);
  return rc;
}

int zovl_read(zovl *o, zdb_read_fn rd, void *ctx, uint8_t *out, uint64_t n,
              uint64_t off) {
  uint64_t end = off + n;
  const uint64_t ps = o->ps;
  while (off < end) {
    uint64_t pg = off / ps;
    size_t inner = (size_t)(off - pg * ps);
    size_t part = (size_t)(ps - inner);
    if ((uint64_t)part > end - off) part = (size_t)(end - off);
    zplat_lock(&o->mu);
    uint64_t logical = o->logical;
    uint32_t slot = map_get(o, pg);
    int from_base = pg < o->base_limit;
    int failed = o->failed;
    zplat_unlock(&o->mu);
    if (failed) return ZVFS_ERR_IO;
    if (off >= logical) break;
    if ((uint64_t)part > logical - off) part = (size_t)(logical - off);
    int rc = ZVFS_OK;
    if (slot) {
      uint64_t roff = (uint64_t)slot * ZOVL_ALIGN;
      uint64_t key = (1ull << 63) | roff;
      if (!zdb_cache_get(o->base, key, out, inner, part)) {
        uint8_t *tmp = (uint8_t *)malloc((size_t)ps);
        if (!tmp) return ZVFS_ERR_NOMEM;
        rc = read_record(o, pg, roff, tmp);
        if (!rc) {
          memcpy(out, tmp + inner, part);
          zdb_cache_put(o->base, key, tmp, (size_t)ps);
        }
        free(tmp);
      }
    } else if (from_base) {
      rc = zdb_file_read(o->base, rd, ctx, out, part, off);
    } else {
      memset(out, 0, part);
    }
    if (rc) return rc;
    out += part;
    off += part;
  }
  if (off < end) {
    memset(out, 0, (size_t)(end - off));
    return ZVFS_ERR_SHORT_READ;
  }
  return ZVFS_OK;
}

/* Current logical content of page pg, zero past EOF. Caller holds wmu. */
static int read_page(zovl *o, zdb_read_fn rd, void *ctx, uint64_t pg,
                     uint8_t *dst) {
  int rc = zovl_read(o, rd, ctx, dst, o->ps, pg * o->ps);
  return rc == ZVFS_ERR_SHORT_READ ? ZVFS_OK : rc;
}

int zovl_write(zovl *o, zdb_read_fn rd, void *ctx, const uint8_t *buf,
               uint64_t n, uint64_t off) {
  if (off + n > ZOVL_MAX_LOGICAL) return ZVFS_ERR_FULL;
  const uint64_t ps = o->ps;
  zplat_lock(&o->wmu);
  int rc = writer_init(o);
  uint64_t end = off + n;
  while (!rc && off < end) {
    uint64_t pg = off / ps;
    size_t inner = (size_t)(off - pg * ps);
    size_t part = (size_t)(ps - inner);
    if ((uint64_t)part > end - off) part = (size_t)(end - off);
    const uint8_t *page = buf;
    if (part != ps) {
      rc = read_page(o, rd, ctx, pg, o->page_tmp);
      if (rc) break;
      memcpy(o->page_tmp + inner, buf, part);
      page = o->page_tmp;
    }
    rc = build_page_record(o, pg, page);
    if (rc) break;
    zplat_lock(&o->mu);
    rc = append_page_locked(o, pg, off + part);
    zplat_unlock(&o->mu);
    if (rc) break;
    AFTER_APPEND(o);
    buf += part;
    off += part;
  }
  zplat_unlock(&o->wmu);
  return rc;
}

static int commit_locked(zovl *o) {
  if (o->failed) return ZVFS_ERR_IO;
  if (!o->pending && o->logical == o->committed_logical) {
    /* a batch whose only append failed must not block refreshes */
    o->batch_open = 0;
    return ZVFS_OK;
  }
  int rc = begin_batch(o);
  if (rc) return rc;
  uint8_t r[ZOVL_COMMIT_SIZE];
  memset(r, 0, sizeof r);
  zdb_put32(r, ZOVL_TAG_COMMIT);
  zdb_put32(r + 4, o->pending);
  zdb_put64(r + 16, o->seq + 1);
  zdb_put64(r + 24, o->logical);
  uint64_t c = XXH64(r, 40, o->tail_chain);
  zdb_put64(r + 40, c);
  rc = append(o, r, sizeof r);
  if (rc) {
    o->failed = rc;
    return rc;
  }
  o->seq++;
  o->commits++;
  o->records += o->pending;
  o->pending = 0;
  o->batch_open = 0;
  o->committed_end = o->scan_end = o->tail;
  o->committed_chain = o->scan_chain = o->tail_chain = c;
  o->committed_logical = o->logical;
  o->sb_n = 0;
  zvfs_stat_add(ZST_OVL_COMMITS, 1);
  return ZVFS_OK;
}

int zovl_truncate(zovl *o, zdb_read_fn rd, void *ctx, uint64_t size) {
  if (size > ZOVL_MAX_LOGICAL) return ZVFS_ERR_FULL;
  zplat_lock(&o->wmu);
  int rc = writer_init(o);
  zplat_lock(&o->mu);
  uint64_t logical = o->logical;
  zplat_unlock(&o->mu);
  if (!rc && o->failed) rc = ZVFS_ERR_IO;
  if (!rc && size != logical) {
    uint64_t pg = size / o->ps;
    size_t keep = (size_t)(size % o->ps);
    /* bytes cut from a partial last page must read as zeros if regrown */
    int rmw = keep && size < logical;
    if (rmw) {
      rc = read_page(o, rd, ctx, pg, o->page_tmp);
      if (!rc) {
        memset(o->page_tmp + keep, 0, o->ps - keep);
        rc = build_page_record(o, pg, o->page_tmp);
      }
    }
    if (!rc) {
      zplat_lock(&o->mu);
      rc = rmw ? append_page_locked(o, pg, 0) : begin_batch(o);
      if (!rc) {
        apply_size(o, size);
        rc = commit_locked(o);
      }
      zplat_unlock(&o->mu);
    }
  }
  zplat_unlock(&o->wmu);
  return rc;
}

int zovl_commit(zovl *o, int sync_flags) {
  zplat_lock(&o->mu);
  int rc = commit_locked(o);
  uint64_t target = o->committed_end;
  int need_sync = !rc && sync_flags && o->h && o->synced_end < target;
  void *h = o->h;
  zplat_unlock(&o->mu);
  if (!need_sync) return rc;
  /* only the writer appends, so fsync outside the lock covers target */
  rc = o->ops->sync(h, sync_flags);
  zplat_lock(&o->mu);
  if (rc) {
    o->failed = rc;
    zplat_unlock(&o->mu);
    return rc;
  }
  zvfs_stat_add(ZST_OVL_SYNCS, 1);
  if (o->synced_end < target) o->synced_end = target;
  zplat_unlock(&o->mu);
  return ZVFS_OK;
}

int zovl_verify(zovl *o, volatile int32_t *cancel) {
  uint8_t *page = (uint8_t *)malloc(o->ps);
  if (!page) return ZVFS_ERR_NOMEM;
  int rc = ZVFS_OK;
  zplat_lock(&o->mu);
  for (size_t li = 0; !rc && li < o->nleaf; li++) {
    for (size_t i = 0; !rc && o->leaf[li] && i < LEAF_SIZE; i++) {
      uint32_t slot = o->leaf[li][i];
      if (!slot) continue;
      if (cancel && zplat_atomic_load32(cancel)) rc = ZVFS_ERR_CANCELLED;
      else rc = read_record(o, ((uint64_t)li << LEAF_BITS) | i,
                            (uint64_t)slot * ZOVL_ALIGN, page);
    }
  }
  zplat_unlock(&o->mu);
  free(page);
  return rc;
}

uint64_t zovl_logical_size(zovl *o) {
  zplat_lock(&o->mu);
  uint64_t v = o->logical;
  zplat_unlock(&o->mu);
  return v;
}

int zovl_is_present(zovl *o) {
  zplat_lock(&o->mu);
  int v = o->h != NULL;
  zplat_unlock(&o->mu);
  return v;
}

void zovl_get_info(zovl *o, zovl_info *out) {
  memset(out, 0, sizeof *out);
  zplat_lock(&o->mu);
  out->present = o->h != NULL;
  out->seq = o->seq;
  out->commits = o->commits;
  out->records = o->records;
  out->committed_end = o->h ? o->committed_end : 0;
  out->logical_size = o->logical;
  out->mapped_pages = o->mapped;
  out->base_visible_pages = o->base_limit;
  if (o->h) {
    memcpy(out->overlay_uuid, o->hdr + 64, 16);
    o->ops->size(o->h, &out->file_size);
  }
  zplat_unlock(&o->mu);
}
