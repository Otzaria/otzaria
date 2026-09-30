/* zvfs_cli: convert, verify, inspect and export .zdb files; train dictionaries. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "zvfs_internal.h"

#if defined(_WIN32)
#include <fcntl.h>
#include <io.h>
#include <windows.h>
#include <shellapi.h>
#if defined(_MSC_VER)
#pragma comment(lib, "shell32.lib")
#endif
#endif

/* Paths are UTF-8 (see main); fopen on Windows would take the ANSI code page. */
static FILE *open_utf8(const char *path, const char *mode) {
#if defined(_WIN32)
  wchar_t wp[4096], wm[8];
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wp, 4096) ||
      !MultiByteToWideChar(CP_UTF8, 0, mode, -1, wm, 8))
    return NULL;
  return _wfopen(wp, wm);
#else
  return fopen(path, mode);
#endif
}

static int usage(void) {
  fprintf(stderr,
          "usage:\n"
          "  zvfs_cli convert <in.db|-> <out.zdb> [--dict NAME | --no-dict |\n"
          "           --dict-file PATH [--dict-name NAME]] [--level N]\n"
          "           [--threads N] [--zstd] [--keep-freelist]\n"
          "           [--uuid-from-content] [--created-ms MS]\n"
          "  zvfs_cli verify <file.zdb>\n"
          "  zvfs_cli info [--json] <file.zdb>\n"
          "  zvfs_cli export <file.zdb> <out.db>\n"
          "  zvfs_cli compact <file.zdb> <out.zdb> [--level N] [--threads N]\n"
          "           [--recompress] [--keep-freelist]\n"
          "  zvfs_cli dicts\n"
          "  zvfs_cli train <db> <out.inc|out.dict> [samples=6000] [dict_kb=112]\n"
          "           [seed] [--fastcover] [--k N] [--d N] [--f N] [--accel N]\n"
          "           [--level N] [--name NAME]\n");
  return 2;
}

static int parse_i64(const char *s, long long lo, long long hi, long long *out) {
  char *end = NULL;
  errno = 0;
  long long v = strtoll(s, &end, 10);
  if (errno || end == s || *end || v < lo || v > hi) {
    fprintf(stderr, "invalid number: %s\n", s);
    return 0;
  }
  *out = v;
  return 1;
}

static char *with_suffix(const char *path, const char *sfx) {
  size_t n = strlen(path), k = strlen(sfx);
  char *p = (char *)malloc(n + k + 1);
  if (p) {
    memcpy(p, path, n);
    memcpy(p + n, sfx, k + 1);
  }
  return p;
}

static int cmd_dicts(void) {
  for (int i = 0; i < zvfs_builtin_dict_count(); i++) {
    const char *name;
    const void *data;
    size_t len;
    uint32_t id;
    zvfs_builtin_dict(i, &name, &data, &len, &id);
    printf("%s id %u bytes %zu xxh64 %016llx%s\n", name, id, len,
           (unsigned long long)zvfs_xxh64(data, len, 0), i == 0 ? " (default)" : "");
  }
  return 0;
}

static int ends_with(const char *s, const char *sfx) {
  size_t n = strlen(s), k = strlen(sfx);
  return n >= k && !strcmp(s + n - k, sfx);
}

/* Header dictName: printable ASCII, NUL-terminated in 32 bytes. */
static int valid_dict_name(const char *s) {
  size_t n = strlen(s);
  if (n == 0 || n > 31) return 0;
  for (size_t i = 0; i < n; i++)
    if (s[i] < 0x21 || s[i] > 0x7e) return 0;
  return 1;
}

/* <out>.inc: a C array for src/dicts (named k_<name>); anything else: raw. */
static int write_dict(const char *path, const char *name, const void *dict,
                      size_t len, uint32_t id) {
  int inc = ends_with(path, ".inc");
  FILE *f = open_utf8(path, inc ? "w" : "wb");
  if (!f) {
    fprintf(stderr, "cannot create %s: %s\n", path, strerror(errno));
    return 1;
  }
  if (inc) {
    char sym[40] = "k_";
    size_t i = 0;
    for (; name[i] && i < 31; i++) {
      char ch = name[i];
      int keep = (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9');
      sym[2 + i] = keep ? ch : '_';
    }
    sym[2 + i] = 0;
    fprintf(f, "/* zstd page dictionary: %zu bytes, id %u, xxh64 %016llx. */\n",
            len, id, (unsigned long long)zvfs_xxh64(dict, len, 0));
    fprintf(f, "static const unsigned char %s[%zu] = {\n", sym, len);
    const unsigned char *p = (const unsigned char *)dict;
    for (size_t j = 0; j < len; j++)
      fprintf(f, "%u%s", p[j], j + 1 == len ? "\n" : ((j + 1) % 24 ? "," : ",\n"));
    fprintf(f, "};\n");
  } else {
    fwrite(dict, 1, len, f);
  }
  if (ferror(f) | fclose(f)) {
    fprintf(stderr, "cannot write %s\n", path);
    return 1;
  }
  return 0;
}

static int cmd_train(int argc, char **argv) {
  if (argc < 4) return usage();
  long long num[3] = {6000, 112, 0}; /* samples, dict_kb, seed */
  const long long num_lo[3] = {1, 1, 0};
  const long long num_hi[3] = {1000000, 1024, 0x7fffffffffffffffll};
  long long k = 2000, d = 8, fbits = 0, accel = 0, level = 0;
  int npos = 0, fastcover = 0;
  const char *name = "seforim-v1";
  for (int i = 4; i < argc; i++) {
    const char *a = argv[i];
    int more = i + 1 < argc;
    long long *dst = NULL, lo = 0, hi = 0;
    if (!strcmp(a, "--fastcover")) {
      fastcover = 1;
    } else if (!strcmp(a, "--name") && more) {
      name = argv[++i];
    } else if (!strcmp(a, "--k") && more) {
      dst = &k, lo = 16, hi = 1 << 20;
    } else if (!strcmp(a, "--d") && more) {
      dst = &d, lo = 6, hi = 16;
    } else if (!strcmp(a, "--f") && more) {
      dst = &fbits, lo = 8, hi = 31;
    } else if (!strcmp(a, "--accel") && more) {
      dst = &accel, lo = 1, hi = 10;
    } else if (!strcmp(a, "--level") && more) {
      dst = &level, lo = 1, hi = 22;
    } else if (a[0] != '-' && npos < 3) {
      if (!parse_i64(a, num_lo[npos], num_hi[npos], &num[npos])) return 2;
      npos++;
    } else {
      fprintf(stderr, "unknown option: %s\n", a);
      return usage();
    }
    if (dst && !parse_i64(argv[++i], lo, hi, dst)) return 2;
  }
  if (!valid_dict_name(name)) {
    fprintf(stderr, "invalid --name: printable ASCII, 1..31 bytes\n");
    return 2;
  }
  if (d > k) {
    fprintf(stderr, "--d must not exceed --k\n");
    return 2;
  }
  zvfs_train_params tp = {1, (uint32_t)k, (uint32_t)d, (uint32_t)fbits,
                          (uint32_t)accel, (int32_t)level};
  size_t cap = (size_t)num[1] * 1024;
  void *dict = malloc(cap);
  size_t len = 0;
  uint32_t id = 0;
  clock_t t0 = clock();
  int rc = dict ? zvfs_train_dict(argv[2], (uint32_t)num[0], (uint64_t)num[2],
                                 fastcover ? &tp : NULL, dict, cap, &len, &id)
                : ZVFS_ERR_NOMEM;
  if (rc) {
    fprintf(stderr, "train failed: %s\n", zvfs_errstr(rc));
    free(dict);
    return 1;
  }
  rc = write_dict(argv[3], name, dict, len, id);
  if (!rc)
    printf("dict %zu bytes id %u xxh64 %016llx in %.1fs\n", len, id,
           (unsigned long long)zvfs_xxh64(dict, len, 0),
           (double)(clock() - t0) / CLOCKS_PER_SEC);
  free(dict);
  return rc;
}

/* A dictionary file as `train` writes it (raw bytes), at most 1MB. */
static void *read_dict_file(const char *path, size_t *len) {
  FILE *f = open_utf8(path, "rb");
  if (!f) {
    fprintf(stderr, "cannot open %s\n", path);
    return NULL;
  }
  const size_t cap = (1u << 20) + 1;
  unsigned char *b = (unsigned char *)malloc(cap);
  size_t n = b ? fread(b, 1, cap, f) : 0;
  int bad = !b || ferror(f) || n == 0 || n == cap;
  fclose(f);
  if (bad) {
    fprintf(stderr, "%s: a dictionary has 1 byte .. 1MB\n", path);
    free(b);
    return NULL;
  }
  *len = n;
  return b;
}

static const char *base_name(const char *p) {
  const char *b = p;
  for (const char *s = p; *s; s++)
    if (*s == '/' || *s == '\\') b = s + 1;
  return b;
}

static int cmd_convert(int argc, char **argv) {
  if (argc < 4) return usage();
  long long level = 9, threads = 4, created = -1;
  int zstd = 0, no_dict = 0, from_content = 0, keep_freelist = 0;
  const char *want = NULL, *dict_file = NULL, *dict_name = NULL;
  for (int i = 4; i < argc; i++) {
    const char *a = argv[i];
    int more = i + 1 < argc;
    if (!strcmp(a, "--zstd")) zstd = 1;
    else if (!strcmp(a, "--no-dict")) no_dict = 1;
    else if (!strcmp(a, "--uuid-from-content")) from_content = 1;
    else if (!strcmp(a, "--keep-freelist")) keep_freelist = 1;
    else if (!strcmp(a, "--dict") && more) want = argv[++i];
    else if (!strcmp(a, "--dict-file") && more) dict_file = argv[++i];
    else if (!strcmp(a, "--dict-name") && more) dict_name = argv[++i];
    else if (!strcmp(a, "--level") && more) {
      if (!parse_i64(argv[++i], 1, 22, &level)) return 2;
    } else if (!strcmp(a, "--threads") && more) {
      if (!parse_i64(argv[++i], 1, 16, &threads)) return 2;
    } else if (!strcmp(a, "--created-ms") && more) {
      if (!parse_i64(argv[++i], 0, 253402300799999ll, &created)) return 2;
    } else {
      fprintf(stderr, "unknown option: %s\n", a);
      return usage();
    }
  }
  const char *name = NULL;
  const void *dict = NULL;
  void *owned = NULL;
  size_t dlen = 0;
  char stem[32];
  if (want && !strcmp(want, "none")) no_dict = 1;
  if (dict_file && (want || no_dict)) {
    fprintf(stderr, "--dict-file excludes --dict and --no-dict\n");
    return 2;
  }
  if (dict_name && !dict_file) {
    fprintf(stderr, "--dict-name needs --dict-file\n");
    return 2;
  }
  if (dict_file) {
    if (!dict_name) { /* the file name without its extension */
      snprintf(stem, sizeof stem, "%s", base_name(dict_file));
      char *dot = strrchr(stem, '.');
      if (dot && dot != stem) *dot = 0;
      dict_name = stem;
    }
    if (!valid_dict_name(dict_name)) {
      fprintf(stderr, "invalid dictionary name '%s': give --dict-name "
                      "(printable ASCII, 1..31 bytes)\n", dict_name);
      return 2;
    }
    if (!(owned = read_dict_file(dict_file, &dlen))) return 1;
    dict = owned;
    name = dict_name;
  } else if (!no_dict) {
    int n = zvfs_builtin_dict_count(), found = 0;
    for (int i = 0; i < n && !found; i++) {
      zvfs_builtin_dict(i, &name, &dict, &dlen, NULL);
      found = !want || !strcmp(want, name);
    }
    if (!found) {
      fprintf(stderr, "unknown dictionary: %s (see: zvfs_cli dicts)\n", want);
      return 2;
    }
  }
  FILE *in = stdin;
  if (strcmp(argv[2], "-")) in = open_utf8(argv[2], "rb");
#if defined(_WIN32)
  else _setmode(_fileno(stdin), _O_BINARY);
#endif
  if (!in) {
    fprintf(stderr, "cannot open %s\n", argv[2]);
    free(owned);
    return 1;
  }
  char *part = with_suffix(argv[3], ".part");
  zvfs_conv *c = NULL;
  int rc = part ? zvfs_conv_create(part, dict, dlen, name, (int)level,
                                   (int)threads, 1, 0, NULL, &c)
                : ZVFS_ERR_NOMEM;
  if (!rc) rc = zvfs_conv_set_identity(c, from_content, created);
  /* a stream cannot be read twice: its freelist stays as it is */
  uint64_t zeroed = 0;
  if (!rc && !keep_freelist && in != stdin && !zstd)
    rc = zvfs_conv_zero_freelist(c, argv[2], &zeroed);
  size_t cap = 4u << 20;
  unsigned char *buf = rc ? NULL : (unsigned char *)malloc(cap);
  if (!rc && !buf) rc = ZVFS_ERR_NOMEM;
  clock_t t0 = clock();
  size_t r;
  while (!rc && (r = fread(buf, 1, cap, in)) > 0)
    rc = zstd ? zvfs_conv_feed_zstd(c, buf, r) : zvfs_conv_feed(c, buf, r);
  if (!rc && ferror(in)) rc = ZVFS_ERR_IO;
  zvfs_info info;
  if (!rc) rc = zvfs_conv_finish(c, &info);
  if (!rc) rc = zplat_rename_durable(part, argv[3]);
  if (rc) {
    fprintf(stderr, "convert failed: %s (%s)\n", zvfs_errstr(rc),
            c ? zvfs_conv_error(c) : "");
  } else {
    printf("logical %.1f MB -> %.1f MB (%.3fx), %llu frames, dict %s/%u, "
           "%llu freelist pages zeroed, cpu %.0fs\n",
           info.logical_size / 1048576.0, info.physical_size / 1048576.0,
           (double)info.logical_size / info.physical_size,
           (unsigned long long)info.frame_count, name ? name : "none",
           info.dict_id, (unsigned long long)zeroed,
           (double)(clock() - t0) / CLOCKS_PER_SEC);
  }
  zvfs_conv_destroy(c);
  if (rc && part) zplat_delete_durable(part);
  free(part);
  free(buf);
  free(owned);
  if (in != stdin) fclose(in);
  return rc ? 1 : 0;
}

/* Step 1 of a compaction only: the source and its overlay stay untouched. */
static int cmd_compact(int argc, char **argv) {
  if (argc < 4) return usage();
  long long level = 9, threads = 4;
  int flags = 0;
  for (int i = 4; i < argc; i++) {
    const char *a = argv[i];
    int more = i + 1 < argc;
    if (!strcmp(a, "--recompress")) flags |= ZVFS_COMPACT_RECOMPRESS;
    else if (!strcmp(a, "--keep-freelist")) flags |= ZVFS_COMPACT_KEEP_FREELIST;
    else if (!strcmp(a, "--level") && more) {
      if (!parse_i64(argv[++i], 1, 22, &level)) return 2;
    } else if (!strcmp(a, "--threads") && more) {
      if (!parse_i64(argv[++i], 1, 16, &threads)) return 2;
    } else {
      fprintf(stderr, "unknown option: %s\n", a);
      return usage();
    }
  }
  char *part = with_suffix(argv[3], ".part");
  zvfs_info info;
  zvfs_compact_stats st;
  char err[256] = "";
  clock_t t0 = clock();
  int rc = part ? zvfs_compact(argv[2], part, (int)level, (int)threads, flags,
                               NULL, NULL, &info, &st, err, sizeof err)
                : ZVFS_ERR_NOMEM;
  if (!rc) rc = zplat_rename_durable(part, argv[3]);
  if (rc) {
    fprintf(stderr, "compact failed: %s (%s)\n", zvfs_errstr(rc), err);
    if (part) zplat_delete_durable(part);
  } else {
    printf("logical %.1f MB -> %.1f MB, %llu frames (%llu copied), "
           "%llu freelist pages zeroed, cpu %.0fs\n",
           info.logical_size / 1048576.0, info.physical_size / 1048576.0,
           (unsigned long long)st.frames, (unsigned long long)st.frames_copied,
           (unsigned long long)st.freelist_leaves,
           (double)(clock() - t0) / CLOCKS_PER_SEC);
  }
  free(part);
  return rc ? 1 : 0;
}

static void print_line(const zvfs_info *i) {
  printf("format %u.%u page %u x%u logical %llu frames %llu physical %llu "
         "dict %s/%u level %u compat %x\n",
         i->format_major, i->format_minor, i->page_size, i->frame_pages,
         (unsigned long long)i->logical_size, (unsigned long long)i->frame_count,
         (unsigned long long)i->physical_size, i->dict_name, i->dict_id, i->level,
         i->compat_features);
}

static void hex(char *out, const uint8_t *p, size_t n) {
  for (size_t i = 0; i < n; i++) snprintf(out + 2 * i, 3, "%02x", p[i]);
}

static void json_str(const char *s) {
  putchar('"');
  for (; *s; s++) {
    unsigned char ch = (unsigned char)*s;
    if (ch == '"' || ch == '\\') printf("\\%c", ch);
    else if (ch < 0x20 || ch > 0x7e) printf("\\u%04x", ch);
    else putchar(ch);
  }
  putchar('"');
}

static void print_json(zvfs_reader *r) {
  const zdb_header *h = &r->f->h;
  zvfs_info i;
  zvfs_overlay_info o;
  zvfs_reader_info(r, &i);
  zvfs_reader_overlay_info(r, &o);
  char u[33], d[33], iu[33], ou[33];
  hex(u, h->uuid, 16);
  hex(d, h->derived_from_uuid, 16);
  hex(iu, h->includes_overlay_uuid, 16);
  hex(ou, o.overlay_uuid, 16);
  typedef unsigned long long ull;
  printf("{\n  \"formatMajor\": %u,\n  \"formatMinor\": %u,\n", h->major, h->minor);
  printf("  \"headerSize\": %u,\n  \"incompatFeatures\": %u,\n"
         "  \"compatFeatures\": %u,\n  \"walHeaderPatched\": %s,\n",
         h->header_size, h->incompat, h->compat,
         h->compat & ZDB_COMPAT_WAL_HEADER_PATCHED ? "true" : "false");
  printf("  \"pageSize\": %u,\n  \"framePages\": %u,\n  \"logicalSize\": %llu,\n"
         "  \"frameCount\": %llu,\n  \"codec\": %u,\n  \"level\": %u,\n",
         h->page_size, h->frame_pages, (ull)h->logical_size, (ull)h->frame_count,
         h->codec, h->level);
  printf("  \"dictOffset\": %llu,\n  \"dictLength\": %u,\n  \"dictId\": %u,\n"
         "  \"dictXxh64\": \"%016llx\",\n  \"dictName\": ",
         (ull)h->dict_offset, h->dict_length, h->dict_id, (ull)h->dict_xxh64);
  json_str(h->dict_name);
  printf(",\n  \"indexOffset\": %llu,\n  \"indexLength\": %llu,\n"
         "  \"indexXxh64\": \"%016llx\",\n  \"contentXxh64\": \"%016llx\",\n",
         (ull)h->index_offset, (ull)h->index_length, (ull)h->index_xxh64,
         (ull)h->content_xxh64);
  printf("  \"fileUuid\": \"%s\",\n  \"createdUnixMs\": %llu,\n"
         "  \"derivedFromUuid\": \"%s\",\n  \"includesOverlayUuid\": \"%s\",\n"
         "  \"includesOverlaySeq\": %llu,\n",
         u, (ull)h->created_ms, d, iu, (ull)h->includes_overlay_seq);
  printf("  \"lockGap\": %s,\n  \"gapStart\": %llu,\n  \"gapEnd\": %llu,\n",
         h->incompat & ZDB_INCOMPAT_LOCK_GAP ? "true" : "false",
         (ull)h->gap_start, (ull)h->gap_end);
  printf("  \"headerXxh64\": \"%016llx\",\n  \"physicalSize\": %llu,\n",
         (ull)zdb_get64(r->f->raw_header + ZDB_HEADER_CORE - 8),
         (ull)i.physical_size);
  printf("  \"overlay\": {\"present\": %s, \"seq\": %llu, \"commits\": %llu, "
         "\"fileSize\": %llu, \"logicalSize\": %llu, \"mappedPages\": %llu, "
         "\"overlayUuid\": \"%s\"}\n}\n",
         o.present ? "true" : "false", (ull)o.seq, (ull)o.commits,
         (ull)o.file_size, (ull)o.logical_size, (ull)o.mapped_pages, ou);
}

static int open_reader(const char *path, zvfs_reader **r) {
  int rc = zvfs_reader_open(path, r);
  if (rc) fprintf(stderr, "open %s failed: %s\n", path, zvfs_errstr(rc));
  return rc;
}

static int cmd_verify(int argc, char **argv) {
  if (argc != 3) return usage();
  zvfs_reader *r = NULL;
  if (open_reader(argv[2], &r)) return 1;
  zvfs_info i;
  zvfs_reader_info(r, &i);
  print_line(&i);
  int rc = zvfs_reader_verify(r, NULL, NULL);
  printf("verify: %s\n", zvfs_errstr(rc));
  zvfs_reader_close(r);
  return rc ? 1 : 0;
}

static int cmd_info(int argc, char **argv) {
  int json = 0;
  const char *path = NULL;
  for (int i = 2; i < argc; i++) {
    if (!strcmp(argv[i], "--json")) json = 1;
    else if (!path) path = argv[i];
    else return usage();
  }
  if (!path) return usage();
  zvfs_reader *r = NULL;
  if (open_reader(path, &r)) return 1;
  if (json) {
    print_json(r);
  } else {
    zvfs_info i;
    zvfs_reader_info(r, &i);
    print_line(&i);
  }
  zvfs_reader_close(r);
  return 0;
}

/* The base image alone: an overlay or a pending journal/WAL is refused. */
static int cmd_export(int argc, char **argv) {
  if (argc != 4) return usage();
  const char *src = argv[2], *dst = argv[3];
  char *ov = with_suffix(src, ZDB_OVERLAY_SUFFIX);
  int e = ov ? zplat_exists(ov) : -1;
  free(ov);
  if (e != 0) {
    fprintf(stderr, "%s has an overlay (-zovl): compact it first\n", src);
    return 1;
  }
  if (zvfs_sidecars_busy(src)) {
    fprintf(stderr, "%s has a pending -journal or -wal\n", src);
    return 1;
  }
  zvfs_reader *r = NULL;
  if (open_reader(src, &r)) return 1;
  zvfs_info info;
  zvfs_reader_info(r, &info);
  if (info.compat_features & ZDB_COMPAT_WAL_HEADER_PATCHED)
    fprintf(stderr, "note: the source was in WAL mode; the export has the "
                    "rollback header (bytes 18/19 = 1)\n");
  char *part = with_suffix(dst, ".part");
  zplat_file *out = NULL;
  const size_t chunk = 4u << 20;
  uint8_t *buf = (uint8_t *)malloc(chunk);
  int rc = part && buf ? zplat_open_write(part, &out) : ZVFS_ERR_NOMEM;
  for (uint64_t off = 0; !rc && off < info.logical_size;) {
    uint64_t left = info.logical_size - off;
    size_t n = left < chunk ? (size_t)left : chunk;
    rc = zvfs_reader_read(r, buf, (int64_t)n, (int64_t)off);
    if (!rc) rc = zplat_pwrite(out, buf, n, off);
    off += n;
  }
  if (!rc) rc = zplat_sync(out);
  zplat_close(out);
  zvfs_reader_close(r);
  if (!rc) rc = zplat_rename_durable(part, dst);
  if (rc && part) zplat_delete_durable(part);
  if (rc) fprintf(stderr, "export failed: %s\n", zvfs_errstr(rc));
  else printf("exported %llu bytes\n", (unsigned long long)info.logical_size);
  free(part);
  free(buf);
  return rc ? 1 : 0;
}

static int run(int argc, char **argv) {
  if (argc < 2) return usage();
  if (!strcmp(argv[1], "convert")) return cmd_convert(argc, argv);
  if (!strcmp(argv[1], "verify")) return cmd_verify(argc, argv);
  if (!strcmp(argv[1], "info")) return cmd_info(argc, argv);
  if (!strcmp(argv[1], "export")) return cmd_export(argc, argv);
  if (!strcmp(argv[1], "compact")) return cmd_compact(argc, argv);
  if (!strcmp(argv[1], "dicts")) return cmd_dicts();
  if (!strcmp(argv[1], "train")) return cmd_train(argc, argv);
  return usage();
}

#if defined(_WIN32)
/* argv is in the ANSI code page, which cannot hold every path: use UTF-16. */
int main(void) {
  int argc = 0;
  wchar_t **wv = CommandLineToArgvW(GetCommandLineW(), &argc);
  char **argv = wv ? (char **)calloc((size_t)argc + 1, sizeof *argv) : NULL;
  for (int i = 0; argv && i < argc; i++) {
    int n = WideCharToMultiByte(CP_UTF8, 0, wv[i], -1, NULL, 0, NULL, NULL);
    if (n <= 0 || !(argv[i] = (char *)malloc((size_t)n)) ||
        !WideCharToMultiByte(CP_UTF8, 0, wv[i], -1, argv[i], n, NULL, NULL))
      argv = NULL;
  }
  if (!argv) {
    fprintf(stderr, "cannot read the command line\n");
    return 1;
  }
  LocalFree(wv);
  return run(argc, argv);
}
#else
int main(int argc, char **argv) { return run(argc, argv); }
#endif
