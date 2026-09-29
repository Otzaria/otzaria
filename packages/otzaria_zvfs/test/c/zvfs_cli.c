/* Developer CLI: train the frozen dictionary, convert, verify, info. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "zvfs.h"

#if defined(_WIN32)
#include <fcntl.h>
#include <io.h>
#endif

static int usage(void) {
  fprintf(stderr,
          "usage:\n"
          "  zvfs_cli train <db> <out.inc> [samples=6000] [dict_kb=112] [seed]\n"
          "  zvfs_cli convert <src.db|-> <dst.zdb> [level=9] [threads=8] [--zstd]"
          " [--no-dict]\n"
          "  zvfs_cli verify <file.zdb>\n"
          "  zvfs_cli info <file.zdb>\n");
  return 2;
}

static int cmd_train(int argc, char **argv) {
  if (argc < 4) return usage();
  uint32_t samples = argc > 4 ? (uint32_t)atoi(argv[4]) : 6000;
  size_t cap = (size_t)(argc > 5 ? atoi(argv[5]) : 112) * 1024;
  uint64_t seed = argc > 6 ? strtoull(argv[6], NULL, 10) : 0;
  void *dict = malloc(cap);
  size_t len = 0;
  uint32_t id = 0;
  clock_t t0 = clock();
  int rc = zvfs_train_dict(argv[2], samples, seed, dict, cap, &len, &id);
  if (rc) {
    fprintf(stderr, "train failed: %s\n", zvfs_errstr(rc));
    return 1;
  }
  FILE *f = fopen(argv[3], "w");
  if (!f) return 1;
  fprintf(f, "/* zstd page dictionary: %zu bytes, id %u, xxh64 %016llx. */\n",
          len, id, (unsigned long long)zvfs_xxh64(dict, len, 0));
  fprintf(f, "static const unsigned char k_seforim_v1[%zu] = {\n", len);
  const unsigned char *p = (const unsigned char *)dict;
  for (size_t i = 0; i < len; i++)
    fprintf(f, "%u%s", p[i], i + 1 == len ? "\n" : ((i + 1) % 24 ? "," : ",\n"));
  fprintf(f, "};\n");
  fclose(f);
  printf("dict %zu bytes id %u in %.1fs\n", len, id,
         (double)(clock() - t0) / CLOCKS_PER_SEC);
  free(dict);
  return 0;
}

static int cmd_convert(int argc, char **argv) {
  if (argc < 4) return usage();
  int level = argc > 4 && argv[4][0] != '-' ? atoi(argv[4]) : 9;
  int threads = argc > 5 && argv[5][0] != '-' ? atoi(argv[5]) : 8;
  int zstd = 0, no_dict = 0;
  for (int i = 4; i < argc; i++) {
    if (!strcmp(argv[i], "--zstd")) zstd = 1;
    if (!strcmp(argv[i], "--no-dict")) no_dict = 1;
  }
  const char *name = NULL;
  const void *dict = NULL;
  size_t dlen = 0;
  if (!no_dict) zvfs_builtin_dict(0, &name, &dict, &dlen, NULL);
  FILE *in = stdin;
  if (strcmp(argv[2], "-")) in = fopen(argv[2], "rb");
#if defined(_WIN32)
  else _setmode(_fileno(stdin), _O_BINARY);
#endif
  if (!in) return 1;
  zvfs_conv *c = NULL;
  int rc = zvfs_conv_create(argv[3], dict, dlen, name, level, threads, 1, 0,
                            NULL, &c);
  if (rc) {
    fprintf(stderr, "create failed: %s\n", zvfs_errstr(rc));
    return 1;
  }
  size_t cap = 4u << 20;
  unsigned char *buf = (unsigned char *)malloc(cap);
  clock_t t0 = clock();
  size_t r;
  while (!rc && (r = fread(buf, 1, cap, in)) > 0)
    rc = zstd ? zvfs_conv_feed_zstd(c, buf, r) : zvfs_conv_feed(c, buf, r);
  zvfs_info info;
  if (!rc) rc = zvfs_conv_finish(c, &info);
  if (rc) {
    fprintf(stderr, "convert failed: %s (%s)\n", zvfs_errstr(rc),
            zvfs_conv_error(c));
  } else {
    printf("logical %.1f MB -> %.1f MB (%.3fx), %llu frames, cpu %.0fs\n",
           info.logical_size / 1048576.0, info.physical_size / 1048576.0,
           (double)info.logical_size / info.physical_size,
           (unsigned long long)info.frame_count,
           (double)(clock() - t0) / CLOCKS_PER_SEC);
  }
  zvfs_conv_destroy(c);
  free(buf);
  if (in != stdin) fclose(in);
  return rc ? 1 : 0;
}

static int cmd_verify_info(int argc, char **argv, int verify) {
  if (argc < 3) return usage();
  zvfs_reader *r = NULL;
  int rc = zvfs_reader_open(argv[2], &r);
  if (rc) {
    fprintf(stderr, "open failed: %s\n", zvfs_errstr(rc));
    return 1;
  }
  zvfs_info i;
  zvfs_reader_info(r, &i);
  printf("format %u.%u page %u x%u logical %llu frames %llu physical %llu "
         "dict %s/%u level %u compat %x\n",
         i.format_major, i.format_minor, i.page_size, i.frame_pages,
         (unsigned long long)i.logical_size, (unsigned long long)i.frame_count,
         (unsigned long long)i.physical_size, i.dict_name, i.dict_id, i.level,
         i.compat_features);
  if (verify) {
    rc = zvfs_reader_verify(r, NULL, NULL);
    printf("verify: %s\n", zvfs_errstr(rc));
  }
  zvfs_reader_close(r);
  return rc ? 1 : 0;
}

int main(int argc, char **argv) {
  if (argc < 2) return usage();
  if (!strcmp(argv[1], "train")) return cmd_train(argc, argv);
  if (!strcmp(argv[1], "convert")) return cmd_convert(argc, argv);
  if (!strcmp(argv[1], "verify")) return cmd_verify_info(argc, argv, 1);
  if (!strcmp(argv[1], "info")) return cmd_verify_info(argc, argv, 0);
  return usage();
}
