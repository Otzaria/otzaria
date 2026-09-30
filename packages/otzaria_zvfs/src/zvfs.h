/* Public C API of otzaria_zvfs: read-only compressed page VFS + converter. */
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
#define ZVFS_ERR_BUSY 10

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
} zvfs_info;

typedef struct zvfs_stats {
  int64_t frames_decoded;
  int64_t cache_hits;
  int64_t cache_misses;
  int64_t compressed_bytes_read;
  int64_t corrupt_frames;
  int64_t cache_bytes;
  int64_t open_files;
} zvfs_stats;

ZVFS_API const char *zvfs_errstr(int code);
ZVFS_API const char *zvfs_zstd_version(void);

/* SQLite loadable-extension entry point (sqlite3_auto_extension signature). */
ZVFS_API int sqlite3_otzariazvfs_init(void *db, char **pzErrMsg,
                                      const void *pApi);
/* 1 once the "zvfs" VFS is registered in this process. */
ZVFS_API int zvfs_is_registered(void);

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

/* Standalone reader (no SQLite): validates header + index on open.
   ZVFS_ERR_BUSY when the path is open through zvfs in this process. */
typedef struct zvfs_reader zvfs_reader;
ZVFS_API int zvfs_reader_open(const char *path_utf8, zvfs_reader **out);
ZVFS_API int zvfs_reader_info(zvfs_reader *r, zvfs_info *out);
ZVFS_API int zvfs_reader_read(zvfs_reader *r, void *buf, int64_t n,
                              int64_t offset);
ZVFS_API void zvfs_reader_close(zvfs_reader *r);
/* Decodes every frame and checks content_xxh64. progress may be NULL. */
ZVFS_API int zvfs_reader_verify(zvfs_reader *r, volatile int32_t *cancel,
                                volatile int64_t *progress);

/* Streaming converter: plain SQLite bytes (or a zstd stream of them) -> .zdb. */
typedef struct zvfs_conv zvfs_conv;
ZVFS_API int zvfs_conv_create(const char *dst_path_utf8, const void *dict,
                              size_t dict_len, const char *dict_name,
                              int level, int threads, uint32_t frame_pages,
                              uint64_t batch_bytes, volatile int32_t *cancel,
                              zvfs_conv **out);
ZVFS_API int zvfs_conv_feed(zvfs_conv *c, const void *data, size_t len);
ZVFS_API int zvfs_conv_feed_zstd(zvfs_conv *c, const void *data, size_t len);
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
