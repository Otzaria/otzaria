#ifndef OTZARIA_ZVFS_INTERNAL_H
#define OTZARIA_ZVFS_INTERNAL_H

/* Bionic hides pread() under _FILE_OFFSET_BITS=64 below API 24; the
   platform layer uses pread64 there instead. */
#if !defined(_WIN32) && !defined(__ANDROID__) && !defined(_FILE_OFFSET_BITS)
#define _FILE_OFFSET_BITS 64
#endif

#include <stddef.h>
#include <stdint.h>

#include "zvfs.h"

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
typedef SRWLOCK zplat_mutex;
typedef CONDITION_VARIABLE zplat_cond;
typedef HANDLE zplat_thread;
#define ZPLAT_MUTEX_INIT SRWLOCK_INIT
#else
#include <pthread.h>
typedef pthread_mutex_t zplat_mutex;
typedef pthread_cond_t zplat_cond;
typedef pthread_t zplat_thread;
#define ZPLAT_MUTEX_INIT PTHREAD_MUTEX_INITIALIZER
#endif

/* ---- platform ---- */
void zplat_mutex_init(zplat_mutex *m);
void zplat_mutex_destroy(zplat_mutex *m);
void zplat_lock(zplat_mutex *m);
void zplat_unlock(zplat_mutex *m);
void zplat_cond_init(zplat_cond *c);
void zplat_cond_destroy(zplat_cond *c);
void zplat_cond_wait(zplat_cond *c, zplat_mutex *m);
void zplat_cond_broadcast(zplat_cond *c);
int zplat_thread_start(zplat_thread *t, void (*fn)(void *), void *arg);
void zplat_thread_join(zplat_thread t);

int64_t zplat_atomic_add(volatile int64_t *p, int64_t v);
int64_t zplat_atomic_load(volatile int64_t *p);
void zplat_atomic_store(volatile int64_t *p, int64_t v);
int32_t zplat_atomic_load32(volatile int32_t *p);

typedef struct zplat_file zplat_file;
int zplat_open_read(const char *path_utf8, zplat_file **out);
int zplat_open_write(const char *path_utf8, zplat_file **out);
int zplat_pread(zplat_file *f, void *buf, size_t n, uint64_t off, size_t *got);
int zplat_pwrite(zplat_file *f, const void *buf, size_t n, uint64_t off);
int zplat_size(zplat_file *f, uint64_t *size);
int zplat_sync(zplat_file *f);
void zplat_close(zplat_file *f);
void zplat_random(void *buf, size_t n);
uint64_t zplat_now_ms(void);
/* 1 exists, 0 absent, <0 error. */
int zplat_exists(const char *path_utf8);
/* Durable replace: the rename is on disk before this returns. */
int zplat_rename_durable(const char *from_utf8, const char *to_utf8);
/* Delete (ZVFS_OK when absent); POSIX then syncs the directory. Windows has
   no directory flush: the delete may be lost on power loss. */
int zplat_delete_durable(const char *path_utf8);
/* Advisory lock on byte 0 of a lock file, never blocking: ZVFS_OK, ZVFS_ERR_BUSY
   (held elsewhere), ZVFS_ERR_READONLY (cannot lock there) or ZVFS_ERR_IO. */
int zplat_lockfile_open(const char *path_utf8, zplat_file **out);
int zplat_lockfile_try(zplat_file *f, int exclusive);
void zplat_lockfile_unlock(zplat_file *f);

/* ---- on-disk format (see README.md, "Format") ---- */
#define ZDB_MAGIC "OTZZDB\x1a\n"
#define ZDB_MAGIC_LEN 8
#define ZDB_HEADER_SIZE 4096u
#define ZDB_HEADER_CORE 256u
#define ZDB_FORMAT_MAJOR 1u
#define ZDB_FORMAT_MINOR 2u
#define ZDB_CODEC_ZSTD_MAGICLESS 1u
#define ZDB_COMPAT_WAL_HEADER_PATCHED 0x1u
/* 1.1: [gapStart, gapEnd) is padding over SQLite's lock bytes (see README). */
#define ZDB_INCOMPAT_LOCK_GAP 0x1u
#define ZDB_KNOWN_INCOMPAT ZDB_INCOMPAT_LOCK_GAP
/* PENDING_BYTE of SQLite's OS layers; locks cover [it, it + 512). */
#define ZDB_LOCK_BYTE 0x40000000ull
#define ZDB_LOCK_SIZE 512u
#define ZDB_MAX_DICT (1u << 20)
#define ZDB_MAX_FRAME_BYTES (16u << 20)
#define ZDB_OVERLAY_SUFFIX "-zovl"
#define ZDB_LOCKFILE_SUFFIX "-zlck"

typedef struct zdb_header {
  uint32_t major, minor, header_size, incompat, compat;
  uint32_t page_size, frame_pages, codec, level;
  uint64_t logical_size, frame_count;
  uint64_t dict_offset;
  uint32_t dict_length, dict_id;
  uint64_t dict_xxh64;
  uint64_t index_offset, index_length, index_xxh64;
  uint64_t content_xxh64;
  uint8_t uuid[16];
  uint64_t created_ms;
  char dict_name[32];
  /* 1.2: set by compaction (all zero otherwise) */
  uint8_t derived_from_uuid[16];
  uint8_t includes_overlay_uuid[16];
  uint64_t includes_overlay_seq;
  uint64_t gap_start, gap_end; /* only with ZDB_INCOMPAT_LOCK_GAP */
} zdb_header;

int zdb_has_magic(const void *p, size_t n);
/* Parses + validates the 256-byte core; ZVFS_ERR_CORRUPT/UNSUPPORTED. */
int zdb_header_decode(const uint8_t raw[ZDB_HEADER_CORE], zdb_header *h);
void zdb_header_encode(const zdb_header *h, uint8_t raw[ZDB_HEADER_CORE]);
uint64_t zdb_frame_bytes(const zdb_header *h);
size_t zdb_max_frame_len(const zdb_header *h);

/* Reads n bytes at off from the physical file: ZVFS_OK/ERR_IO/ERR_SHORT_READ. */
typedef int (*zdb_read_fn)(void *ctx, void *buf, size_t n, uint64_t off);

typedef struct zdb_cache_entry zdb_cache_entry;

typedef struct zovl zovl;

typedef struct zdb_file {
  zdb_header h;
  uint8_t raw_header[ZDB_HEADER_CORE];
  uint64_t frame_bytes;
  uint64_t physical_size;
  uint64_t *index; /* frame_count + 1 absolute offsets */
  void *ddict;     /* ZSTD_DDict*, NULL when dict_length == 0 */
  void *dict;      /* raw dictionary bytes (overlay writes build a CDict) */
  zplat_mutex mu;
  zdb_cache_entry **buckets;
  size_t bucket_mask;
  zdb_cache_entry *lru_head, *lru_tail;
  int64_t cache_bytes;
  zovl *ovl; /* NULL when opened without overlay support */
  /* process-wide sharing (owned by the VFS registry) */
  struct zdb_file *next;
  char *key;
  int refs;
} zdb_file;

int zdb_file_load(zdb_read_fn rd, void *ctx, uint64_t physical_size,
                  zdb_file **out);
void zdb_file_free(zdb_file *f);
/* Reads the base image only; bytes past its size are zero-filled (SHORT_READ). */
int zdb_file_read(zdb_file *f, zdb_read_fn rd, void *ctx, void *buf,
                  uint64_t n, uint64_t off);
void zdb_fill_info(const zdb_file *f, zvfs_info *out);
/* End of frame i's bytes; the frame before a lock gap ends at gapStart. */
uint64_t zdb_frame_end(const zdb_file *f, uint64_t i);

/* Converter test seam: where the lock-byte gap goes (ZDB_LOCK_BYTE). */
extern uint64_t zvfs_g_lock_byte;
/* Decodes every base frame and checks content_xxh64. */
int zdb_verify_base(zdb_file *f, zdb_read_fn rd, void *ctx,
                    volatile int32_t *cancel, volatile int64_t *progress);
/* Decodes one magicless frame of exactly `want` bytes (header checks included). */
int zdb_decode(const void *ddict, const uint8_t *src, size_t clen, uint8_t *dst,
               size_t want);
/* Shared decoded-page LRU; keys with bit 63 set belong to overlay records. */
int zdb_cache_get(zdb_file *f, uint64_t key, uint8_t *dst, size_t inner,
                  size_t part);
void zdb_cache_put(zdb_file *f, uint64_t key, const uint8_t *data, size_t len);
uint32_t zdb_get32(const uint8_t *p);
uint64_t zdb_get64(const uint8_t *p);
void zdb_put32(uint8_t *p, uint32_t v);
void zdb_put64(uint8_t *p, uint64_t v);

extern volatile int64_t zvfs_g_cache_budget;
void zvfs_stat_open_files(int64_t delta);
void zvfs_stat_add(int which, int64_t delta);
enum {
  ZST_OVL_RECORDS,
  ZST_OVL_COMMITS,
  ZST_OVL_BYTES,
  ZST_OVL_SYNCS,
  ZST_OVL_PAGE_READS,
  ZST_OVL_REFRESH_SCANS
};

/* ---- overlay sidecar <path>-zovl (S5b, see README "Overlay") ---- */
#define ZOVL_MAGIC "OTZZOVL\n"
#define ZOVL_HEADER_SIZE 128u
#define ZOVL_FORMAT_MAJOR 1u
#define ZOVL_FORMAT_MINOR 0u
#define ZOVL_KNOWN_INCOMPAT 0x0u
#define ZOVL_ALIGN 16u
#define ZOVL_PAGE_HDR 32u
#define ZOVL_COMMIT_SIZE 48u
#define ZOVL_TAG_PAGE 0x4750564Fu   /* "OVPG" */
#define ZOVL_TAG_COMMIT 0x4D43564Fu /* "OVCM" */
/* The page map stores offset / ZOVL_ALIGN in 32 bits. */
#define ZOVL_MAX_SIZE ((uint64_t)ZOVL_ALIGN << 32)
#define ZOVL_MAX_LOGICAL (1ull << 50)
#define ZOVL_LEVEL 3

/* File operations on the sidecar (SQLite base VFS or zplat). */
typedef struct zovl_ops {
  /* ZVFS_OK, ZVFS_ERR_SHORT_READ (tail zero-filled) or ZVFS_ERR_IO */
  int (*read)(void *h, void *buf, size_t n, uint64_t off);
  int (*write)(void *h, const void *buf, size_t n, uint64_t off);
  int (*truncate)(void *h, uint64_t size);
  int (*sync)(void *h, int flags);
  int (*size)(void *h, uint64_t *out);
  void (*close)(void *h);
  /* *h = NULL (and ZVFS_OK) when absent and !create; create never truncates */
  int (*open)(void *env, int create, void **h);
  void (*env_free)(void *env);
} zovl_ops;

typedef struct zovl_info {
  int present;
  uint64_t seq, commits, records, file_size, committed_end, logical_size;
  uint64_t mapped_pages, base_visible_pages;
  uint8_t overlay_uuid[16];
  /* an obsolete sidecar left by an interrupted compaction swap */
  int stale_obsolete;
  uint8_t stale_uuid[16];
  uint64_t stale_seq;
} zovl_info;

/* Binds to base; opens and replays an existing sidecar. Owns env on success. */
int zovl_create(const zovl_ops *ops, void *env, zdb_file *base, zovl **out);
void zovl_free(zovl *o);
/* Picks up commits appended by other processes (no-op while writing). */
int zovl_refresh(zovl *o);
/* Logical read through overlay + base; past EOF zero-fill + SHORT_READ. */
int zovl_read(zovl *o, zdb_read_fn rd, void *ctx, uint8_t *buf, uint64_t n,
              uint64_t off);
int zovl_write(zovl *o, zdb_read_fn rd, void *ctx, const uint8_t *buf,
               uint64_t n, uint64_t off);
int zovl_truncate(zovl *o, zdb_read_fn rd, void *ctx, uint64_t size);
/* Seals pending records with a commit record; sync_flags != 0 also fsyncs. */
int zovl_commit(zovl *o, int sync_flags);
uint64_t zovl_logical_size(zovl *o);
void zovl_get_info(zovl *o, zovl_info *out);
int zovl_is_present(zovl *o);
/* Decodes every mapped overlay page. */
int zovl_verify(zovl *o, volatile int32_t *cancel);

/* Standalone reader (zvfs_reader_*): base + read-only overlay replay. */
struct zvfs_reader {
  zplat_file *pf;
  zdb_file *f;
};
int zvfs_read_logical(zvfs_reader *r, void *buf, uint64_t n, uint64_t off);
void zvfs_fill_overlay_info(zovl *o, zvfs_overlay_info *out);
void zvfs_lineage_of(const zovl_info *oi, uint8_t uuid[16], uint64_t *seq);

int zvfs_sidecars_busy(const char *path);

/* Compaction output records what it includes (zdb minor 1 fields). */
void zvfs_conv_set_lineage(zvfs_conv *c, const uint8_t derived_from[16],
                           const uint8_t overlay_uuid[16], uint64_t seq);

#endif
