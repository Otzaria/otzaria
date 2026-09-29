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

/* ---- on-disk format (see README.md, "Format") ---- */
#define ZDB_MAGIC "OTZZDB\x1a\n"
#define ZDB_MAGIC_LEN 8
#define ZDB_HEADER_SIZE 4096u
#define ZDB_HEADER_CORE 256u
#define ZDB_FORMAT_MAJOR 1u
#define ZDB_FORMAT_MINOR 1u
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

typedef struct zdb_file {
  zdb_header h;
  uint8_t raw_header[ZDB_HEADER_CORE];
  uint64_t frame_bytes;
  uint64_t physical_size;
  uint64_t *index; /* frame_count + 1 absolute offsets */
  void *ddict;     /* ZSTD_DDict*, NULL when dict_length == 0 */
  zplat_mutex mu;
  zdb_cache_entry **buckets;
  size_t bucket_mask;
  zdb_cache_entry *lru_head, *lru_tail;
  int64_t cache_bytes;
  /* process-wide sharing (owned by the VFS registry) */
  struct zdb_file *next;
  char *key;
  int refs;
} zdb_file;

int zdb_file_load(zdb_read_fn rd, void *ctx, uint64_t physical_size,
                  zdb_file **out);
void zdb_file_free(zdb_file *f);
/* Logical read; bytes past logical_size are zero-filled (ERR_SHORT_READ). */
int zdb_file_read(zdb_file *f, zdb_read_fn rd, void *ctx, void *buf,
                  uint64_t n, uint64_t off);
void zdb_fill_info(const zdb_file *f, zvfs_info *out);
/* End of frame i's bytes; the frame before a lock gap ends at gapStart. */
uint64_t zdb_frame_end(const zdb_file *f, uint64_t i);

/* Converter test seam: where the lock-byte gap goes (ZDB_LOCK_BYTE). */
extern uint64_t zvfs_g_lock_byte;

extern volatile int64_t zvfs_g_cache_budget;
void zvfs_stat_open_files(int64_t delta);

#endif
