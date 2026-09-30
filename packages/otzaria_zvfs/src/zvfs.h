/* Public C API of otzaria_zvfs: compressed page VFS, overlay writes, converter. */
#ifndef OTZARIA_ZVFS_H
#define OTZARIA_ZVFS_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define ZVFS_API __declspec(dllexport)
#else
#define ZVFS_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Result codes shared by every entry point. */
#define ZVFS_OK 0
#define ZVFS_ERR_IO 1
#define ZVFS_ERR_CORRUPT 2
#define ZVFS_ERR_NOMEM 3
#define ZVFS_ERR_UNSUPPORTED 4
#define ZVFS_ERR_INVALID 5
#define ZVFS_ERR_CANCELLED 6
#define ZVFS_ERR_NOT_ZDB 7
#define ZVFS_ERR_SHORT_READ 8
#define ZVFS_ERR_FULL 9
#define ZVFS_ERR_BUSY 10
#define ZVFS_ERR_READONLY 11

#define ZVFS_VFS_NAME "zvfs"

typedef struct zvfs_info {
  uint32_t format_major;
  uint32_t format_minor;
  uint32_t page_size;
  uint32_t frame_pages;
  uint64_t logical_size;
  uint64_t frame_count;
  uint64_t physical_size;
  uint32_t dict_id;
  uint32_t dict_length;
  uint32_t level;
  uint32_t compat_features;
  uint32_t incompat_features;
  uint32_t reserved0;
  uint64_t content_xxh64;
  uint64_t created_unix_ms;
  uint8_t file_uuid[16];
  char dict_name[32];
  /* logical_size above includes the overlay; this is the base image alone */
  uint64_t base_logical_size;
  uint64_t includes_overlay_seq;
  uint8_t derived_from_uuid[16];
  uint8_t includes_overlay_uuid[16];
} zvfs_info;

typedef struct zvfs_overlay_info {
  int32_t present;
  uint32_t reserved0;
  uint64_t seq;           /* last valid commit, 0 = none */
  uint64_t commits;       /* commit records replayed */
  uint64_t records;       /* page records replayed */
  uint64_t file_size;     /* physical sidecar size */
  uint64_t committed_end; /* end of the last valid commit */
  uint64_t logical_size;
  uint64_t mapped_pages;       /* pages served from the overlay */
  uint64_t base_visible_pages; /* leading pages still served from the base */
  uint8_t overlay_uuid[16];
} zvfs_overlay_info;

typedef struct zvfs_stats {
  int64_t frames_decoded;
  int64_t cache_hits;
  int64_t cache_misses;
  int64_t compressed_bytes_read;
  int64_t corrupt_frames;
  int64_t cache_bytes;
  int64_t open_files;
  int64_t overlay_records;
  int64_t overlay_commits;
  int64_t overlay_bytes;
  int64_t overlay_syncs;
  int64_t overlay_page_reads;
  int64_t overlay_refresh_scans;
} zvfs_stats;

ZVFS_API const char *zvfs_errstr(int code);
ZVFS_API const char *zvfs_zstd_version(void);

/* SQLite loadable-extension entry point (sqlite3_auto_extension signature). */
ZVFS_API int sqlite3_otzariazvfs_init(void *db, char **pzErrMsg,
                                      const void *pApi);
/* 1 once the "zvfs" VFS is registered in this process. */
ZVFS_API int zvfs_is_registered(void);
/* Makes "zvfs" (on) or the original VFS (off) the process default, so code
   that opens without naming a VFS reaches .zdb files too. */
ZVFS_API int zvfs_set_default(int on);

/* Byte budget of each file's shared decoded-frame LRU (0 disables it). */
ZVFS_API void zvfs_set_cache_budget(int64_t bytes);
ZVFS_API int64_t zvfs_get_cache_budget(void);
ZVFS_API void zvfs_get_stats(zvfs_stats *out);

/* 1 = .zdb magic, 0 = not a zdb (or unreadable). A path open through zvfs
   is answered from its state: on POSIX closing any fd drops SQLite's locks. */
ZVFS_API int zvfs_probe_path(const char *path_utf8);
/* 0 = not open through zvfs in this process, 1 = open (plain), 2 = open
   (.zdb), -1 = could not tell (treat as open). */
ZVFS_API int zvfs_in_use(const char *path_utf8);
/* Info of a .zdb open in this process, from its state; ZVFS_ERR_NOT_ZDB when
   it is not open as one. */
ZVFS_API int zvfs_state_info(const char *path_utf8, zvfs_info *out);

/* Standalone reader (no SQLite): validates header + index on open and
   replays <path>-zovl read-only, so reads are logical. ZVFS_ERR_BUSY
   when the path is open through zvfs in this process. */
typedef struct zvfs_reader zvfs_reader;
ZVFS_API int zvfs_reader_open(const char *path_utf8, zvfs_reader **out);
ZVFS_API int zvfs_reader_info(zvfs_reader *r, zvfs_info *out);
ZVFS_API int zvfs_reader_read(zvfs_reader *r, void *buf, int64_t n,
                              int64_t offset);
ZVFS_API void zvfs_reader_close(zvfs_reader *r);
/* Decodes every base frame, checks content_xxh64, then decodes every
   overlay page. progress may be NULL. */
ZVFS_API int zvfs_reader_verify(zvfs_reader *r, volatile int32_t *cancel,
                                volatile int64_t *progress);
ZVFS_API int zvfs_reader_overlay_info(zvfs_reader *r, zvfs_overlay_info *out);
/* Overlay info of a .zdb open in this process, from its state. */
ZVFS_API int zvfs_state_overlay_info(const char *path_utf8,
                                     zvfs_overlay_info *out);

/* Compaction step 1: writes the logical content of path (base + overlay) to
   dst as a new base that records the overlay it includes. */
ZVFS_API int zvfs_compact(const char *path_utf8, const char *dst_utf8,
                          int level, int threads, volatile int32_t *cancel,
                          volatile int64_t *progress, zvfs_info *out,
                          char *err, size_t err_len);
/* Compaction step 2: durably replaces path by new_path, then deletes the
   overlay. ZVFS_ERR_BUSY when path is open in this process or a journal or
   non-empty WAL exists; other processes must have closed it (see README). */
ZVFS_API int zvfs_compact_swap(const char *path_utf8, const char *new_path_utf8);
/* Installs a downloaded .zdb as the base of path: deletes path's -journal,
   -wal, -shm, -zovl and .new, then durably renames candidate over path.
   ZVFS_ERR_BUSY while any process has path open (swap lock, see README). */
ZVFS_API int zvfs_install(const char *path_utf8, const char *candidate_utf8);

/* Streaming converter: plain SQLite bytes (or a zstd stream of them) -> .zdb. */
typedef struct zvfs_conv zvfs_conv;
ZVFS_API int zvfs_conv_create(const char *dst_path_utf8, const void *dict,
                              size_t dict_len, const char *dict_name,
                              int level, int threads, uint32_t frame_pages,
                              uint64_t batch_bytes, volatile int32_t *cancel,
                              zvfs_conv **out);
ZVFS_API int zvfs_conv_feed(zvfs_conv *c, const void *data, size_t len);
ZVFS_API int zvfs_conv_feed_zstd(zvfs_conv *c, const void *data, size_t len);
/* Reproducible output: fileUuid hashed from the other header fields, and a
   fixed createdUnixMs (< 0 keeps the current time). Before finish. */
ZVFS_API int zvfs_conv_set_identity(zvfs_conv *c, int uuid_from_content,
                                    int64_t created_unix_ms);
ZVFS_API int zvfs_conv_finish(zvfs_conv *c, zvfs_info *out);
ZVFS_API void zvfs_conv_progress(zvfs_conv *c, uint64_t *bytes_in,
                                 uint64_t *bytes_out);
ZVFS_API const char *zvfs_conv_error(zvfs_conv *c);
ZVFS_API void zvfs_conv_destroy(zvfs_conv *c);

/* Built-in frozen dictionaries (index 0 = newest). */
ZVFS_API int zvfs_builtin_dict_count(void);
ZVFS_API int zvfs_builtin_dict(int index, const char **name, const void **data,
                               size_t *len, uint32_t *id);

/* Build-time tool: trains a page dictionary from random pages of a DB. */
ZVFS_API int zvfs_train_dict(const char *db_path_utf8, uint32_t samples,
                             uint64_t seed, void *out, size_t capacity,
                             size_t *out_len, uint32_t *out_id);

ZVFS_API uint64_t zvfs_xxh64(const void *data, size_t len, uint64_t seed);

#ifdef __cplusplus
}
#endif
#endif
