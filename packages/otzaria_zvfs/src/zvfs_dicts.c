#include <stdlib.h>
#include <string.h>

#include "zvfs_internal.h"

#define ZDICT_STATIC_LINKING_ONLY
#include "zdict.h"
#include "zstd.h"

/* .inc files come from `zvfs_cli train` (see README); never edit by hand. */
#include "dicts/seforim_v1.inc"

typedef struct {
  const char *name;
  const unsigned char *data;
  size_t len;
} builtin_dict;

static const builtin_dict k_dicts[] = {
    {"seforim-v1", k_seforim_v1, sizeof k_seforim_v1},
};

ZVFS_API int zvfs_builtin_dict_count(void) {
  return (int)(sizeof k_dicts / sizeof k_dicts[0]);
}

ZVFS_API int zvfs_builtin_dict(int i, const char **name, const void **data,
                               size_t *len, uint32_t *id) {
  if (i < 0 || i >= zvfs_builtin_dict_count()) return ZVFS_ERR_INVALID;
  if (name) *name = k_dicts[i].name;
  if (data) *data = k_dicts[i].data;
  if (len) *len = k_dicts[i].len;
  if (id) *id = ZSTD_getDictID_fromDict(k_dicts[i].data, k_dicts[i].len);
  return ZVFS_OK;
}

/* Deterministic: fixed sampler, and fastcover with explicit k/d takes no
   thread-dependent path (nbThreads only feeds the optimize* search). */
ZVFS_API int zvfs_train_dict(const char *db_path, uint32_t samples,
                             uint64_t seed, const zvfs_train_params *params,
                             void *out, size_t capacity, size_t *out_len,
                             uint32_t *out_id) {
  if (!db_path || !out || !out_len || samples == 0 || capacity < 1024 ||
      capacity > ZDB_MAX_DICT)
    return ZVFS_ERR_INVALID;
  if (params && params->fastcover &&
      (!params->k || !params->d || params->d > params->k || params->f > 31 ||
       params->accel > 10))
    return ZVFS_ERR_INVALID;
  zplat_file *pf;
  int rc = zplat_open_read(db_path, &pf);
  if (rc) return rc;
  uint8_t hd[100];
  size_t got = 0;
  uint64_t size = 0;
  rc = zplat_pread(pf, hd, sizeof hd, 0, &got);
  if (!rc) rc = zplat_size(pf, &size);
  if (!rc && (got != sizeof hd || memcmp(hd, "SQLite format 3", 16) != 0))
    rc = ZVFS_ERR_INVALID;
  uint32_t ps = (uint32_t)hd[16] << 8 | hd[17];
  if (ps == 1) ps = 65536;
  uint64_t pages = ps ? size / ps : 0;
  if (!rc && (ps < 512 || pages < 2)) rc = ZVFS_ERR_INVALID;
  uint8_t *buf = NULL;
  size_t *lens = NULL;
  if (!rc && (uint64_t)samples * ps > SIZE_MAX / 2) rc = ZVFS_ERR_NOMEM;
  if (!rc) {
    buf = (uint8_t *)malloc((size_t)samples * ps);
    lens = (size_t *)malloc(samples * sizeof(size_t));
    if (!buf || !lens) rc = ZVFS_ERR_NOMEM;
  }
  uint64_t x = seed ? seed : 0x9E3779B97F4A7C15ull;
  for (uint32_t i = 0; !rc && i < samples; i++) {
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    uint64_t pg = x % pages;
    rc = zplat_pread(pf, buf + (size_t)i * ps, ps, pg * ps, &got);
    if (!rc && got != ps) rc = ZVFS_ERR_IO;
    lens[i] = ps;
  }
  zplat_close(pf);
  if (!rc) {
    size_t dl;
    if (params && params->fastcover) {
      ZDICT_fastCover_params_t fp;
      memset(&fp, 0, sizeof fp);
      fp.k = params->k;
      fp.d = params->d;
      fp.f = params->f;
      fp.accel = params->accel;
      fp.zParams.compressionLevel = params->level;
      dl = ZDICT_trainFromBuffer_fastCover(out, capacity, buf, lens, samples, fp);
    } else {
      dl = ZDICT_trainFromBuffer(out, capacity, buf, lens, samples);
    }
    if (ZDICT_isError(dl)) {
      rc = ZVFS_ERR_INVALID;
    } else {
      *out_len = dl;
      if (out_id) *out_id = ZDICT_getDictID(out, dl);
    }
  }
  free(buf);
  free(lens);
  return rc;
}
