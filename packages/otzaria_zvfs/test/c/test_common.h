#ifndef ZVFS_TEST_COMMON_H
#define ZVFS_TEST_COMMON_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_failures;

#define CHECK(cond)                                                    \
  do {                                                                 \
    if (!(cond)) {                                                     \
      fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, \
              #cond);                                                  \
      g_failures++;                                                    \
    }                                                                  \
  } while (0)

#define CHECK_EQ(a, b)                                                    \
  do {                                                                    \
    long long va_ = (long long)(a), vb_ = (long long)(b);                 \
    if (va_ != vb_) {                                                     \
      fprintf(stderr, "%s:%d: CHECK_EQ failed: %s=%lld %s=%lld\n",        \
              __FILE__, __LINE__, #a, va_, #b, vb_);                      \
      g_failures++;                                                       \
    }                                                                     \
  } while (0)

static uint64_t g_rng = 0x2545F4914F6CDD1Dull;
static uint64_t rnd(void) {
  g_rng ^= g_rng << 13;
  g_rng ^= g_rng >> 7;
  g_rng ^= g_rng << 17;
  return g_rng;
}

static const char *tmp_path(const char *name) {
  static char buf[4][1024];
  static int slot;
  const char *dir = getenv("ZVFS_TEST_TMP");
  if (!dir) dir = ".";
  char *out = buf[slot++ & 3];
  snprintf(out, 1024, "%s/%s", dir, name);
  return out;
}

static int read_file(const char *path, uint8_t **data, size_t *len) {
  FILE *f = fopen(path, "rb");
  if (!f) return -1;
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  *data = (uint8_t *)malloc((size_t)n + 1);
  *len = fread(*data, 1, (size_t)n, f);
  fclose(f);
  return *len == (size_t)n ? 0 : -1;
}

static int write_file(const char *path, const void *data, size_t len) {
  FILE *f = fopen(path, "wb");
  if (!f) return -1;
  size_t w = fwrite(data, 1, len, f);
  fclose(f);
  return w == len ? 0 : -1;
}

#endif
