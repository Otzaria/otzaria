/* VFS tests against a statically linked SQLite (optional CMake target). */
#include "sqlite3.h"
#include "test_common.h"
#include "zvfs.h"
#include "zvfs_internal.h"

static void remove_all(const char *path) {
  static const char *sfx[] = {"", "-zovl", "-journal", "-wal", "-shm"};
  char b[1100];
  for (int i = 0; i < 5; i++) {
    snprintf(b, sizeof b, "%s%s", path, sfx[i]);
    remove(b);
  }
}

static sqlite3 *open_db(const char *path, int flags, const char *vfs) {
  sqlite3 *db = NULL;
  int rc = sqlite3_open_v2(path, &db, flags, vfs);
  if (rc != SQLITE_OK) {
    sqlite3_close(db);
    return NULL;
  }
  return db;
}

static void exec(sqlite3 *db, const char *sql) {
  char *err = NULL;
  if (sqlite3_exec(db, sql, NULL, NULL, &err) != SQLITE_OK) {
    fprintf(stderr, "sql error: %s\n", err ? err : "?");
    g_failures++;
  }
  sqlite3_free(err);
}

static void make_db(const char *path, int page_size, int wal) {
  remove_all(path);
  sqlite3 *db = open_db(path, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  char sql[256];
  snprintf(sql, sizeof sql, "PRAGMA page_size=%d;", page_size);
  exec(db, sql);
  exec(db, wal ? "PRAGMA journal_mode=WAL;" : "PRAGMA journal_mode=DELETE;");
  exec(db,
       "CREATE TABLE book(id INTEGER PRIMARY KEY, title TEXT, cat INT);"
       "CREATE TABLE line(id INTEGER PRIMARY KEY, bookId INT, idx INT, "
       "content TEXT, blob BLOB);"
       "CREATE INDEX idx_line_book ON line(bookId, idx);"
       "CREATE TABLE kv(k TEXT PRIMARY KEY, v) WITHOUT ROWID;"
       "BEGIN;"
       "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE "
       "i<200) INSERT INTO book SELECT i, 'book ' || i, i % 7 FROM n;"
       "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE "
       "i<20000) INSERT INTO line SELECT i, i % 200 + 1, i / 200, "
       "printf('line %d of book %d: %s', i, i % 200 + 1, "
       "substr(hex(randomblob(40)), 1, abs(random()) % 80)), "
       "CASE WHEN i % 97 = 0 THEN randomblob(9000) END FROM n;"
       "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE "
       "i<3000) INSERT INTO kv SELECT 'key' || i, randomblob(i % 50) FROM n;"
       "COMMIT;");
  sqlite3_close(db);
}

static int convert_file(const char *src, const char *dst) {
  remove_all(dst);
  uint8_t *data;
  size_t n;
  if (read_file(src, &data, &n)) return -1;
  const char *name;
  const void *dict;
  size_t dl;
  zvfs_builtin_dict(0, &name, &dict, &dl, NULL);
  zvfs_conv *c = NULL;
  int rc = zvfs_conv_create(dst, dict, dl, name, 6, 4, 1, 1 << 20, NULL, &c);
  for (size_t off = 0; !rc && off < n;) {
    size_t k = 1 + rnd() % 100000;
    if (k > n - off) k = n - off;
    rc = zvfs_conv_feed(c, data + off, k);
    off += k;
  }
  if (!rc) rc = zvfs_conv_finish(c, NULL);
  zvfs_conv_destroy(c);
  free(data);
  return rc;
}

static uint64_t query_hash(sqlite3 *db, const char *sql, int *rc_out) {
  sqlite3_stmt *st = NULL;
  uint64_t h = 1469598103934665603ull;
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  while (rc == SQLITE_OK || rc == SQLITE_ROW) {
    if ((rc = sqlite3_step(st)) != SQLITE_ROW) break;
    for (int i = 0; i < sqlite3_column_count(st); i++) {
      const unsigned char *p = (const unsigned char *)sqlite3_column_blob(st, i);
      int n = sqlite3_column_bytes(st, i);
      h ^= (uint64_t)sqlite3_column_type(st, i);
      h *= 1099511628211ull;
      for (int j = 0; j < n; j++) {
        h ^= p[j];
        h *= 1099511628211ull;
      }
    }
  }
  if (rc == SQLITE_DONE) rc = SQLITE_OK;
  sqlite3_finalize(st);
  if (rc_out) *rc_out = rc;
  return h;
}

static const char *k_queries[] = {
    "SELECT * FROM book ORDER BY id",
    "SELECT * FROM line ORDER BY id",
    "SELECT bookId, count(*), sum(length(content)), max(idx) FROM line GROUP BY 1",
    "SELECT l.content, b.title FROM line l JOIN book b ON b.id=l.bookId WHERE "
    "l.bookId BETWEEN 10 AND 20 AND l.idx < 30 ORDER BY l.bookId, l.idx",
    "SELECT * FROM kv ORDER BY k",
    "SELECT hex(blob) FROM line WHERE blob IS NOT NULL",
    "PRAGMA integrity_check",
};
#define NQ (int)(sizeof k_queries / sizeof k_queries[0])

static void test_roundtrip(int page_size, int wal) {
  const char *plain = tmp_path("vfs_plain.db");
  const char *zdb = tmp_path("vfs.zdb");
  make_db(plain, page_size, wal);
  remove_all(zdb);
  CHECK_EQ(convert_file(plain, zdb), 0);
  sqlite3 *a = open_db(plain, SQLITE_OPEN_READONLY, NULL);
  sqlite3 *b = open_db(zdb, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  CHECK(a && b);
  if (!a || !b) return;
  for (int q = 0; q < NQ; q++) {
    int ra, rb;
    uint64_t ha = query_hash(a, k_queries[q], &ra);
    uint64_t hb = query_hash(b, k_queries[q], &rb);
    CHECK_EQ(ra, SQLITE_OK);
    CHECK_EQ(rb, SQLITE_OK);
    CHECK(ha == hb);
  }
  int rc;
  query_hash(b, "PRAGMA quick_check", &rc);
  CHECK_EQ(rc, SQLITE_OK);
  sqlite3_close(a);
  sqlite3_close(b);

  /* Opened read-only the pager refuses writes; read-write goes to the overlay. */
  sqlite3 *ro = open_db(zdb, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  CHECK(ro && sqlite3_db_readonly(ro, "main") == 1);
  if (ro) {
    CHECK(sqlite3_exec(ro, "INSERT INTO book VALUES(9999,'x',1)", 0, 0, 0) ==
          SQLITE_READONLY);
    sqlite3_close(ro);
  }
  sqlite3 *w = open_db(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
  CHECK(w != NULL);
  if (w) {
    CHECK(sqlite3_db_readonly(w, "main") == 0);
    CHECK_EQ(sqlite3_exec(w, "INSERT INTO book VALUES(9999,'x',1)", 0, 0, 0),
             SQLITE_OK);
    sqlite3_close(w);
  }
  a = open_db(zdb, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  if (a) {
    int rc;
    CHECK(query_hash(a, "SELECT title FROM book WHERE id=9999", &rc) !=
          query_hash(a, "SELECT 1 WHERE 0", NULL));
    CHECK_EQ(rc, SQLITE_OK);
    sqlite3_close(a);
  }
  remove(plain);
  remove_all(zdb);
}

static void test_passthrough(void) {
  const char *p = tmp_path("vfs_pass.db");
  remove(p);
  sqlite3 *db = open_db(p, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, ZVFS_VFS_NAME);
  CHECK(db != NULL);
  exec(db, "PRAGMA journal_mode=WAL; CREATE TABLE t(x); INSERT INTO t VALUES(42);");
  int rc;
  uint64_t h1 = query_hash(db, "SELECT x FROM t", &rc);
  CHECK_EQ(rc, SQLITE_OK);
  sqlite3_close(db);
  db = open_db(p, SQLITE_OPEN_READONLY, NULL);
  CHECK(db && query_hash(db, "SELECT x FROM t", &rc) == h1);
  sqlite3_close(db);
  char wal[1100];
  snprintf(wal, sizeof wal, "%s-wal", p);
  remove(wal);
  snprintf(wal, sizeof wal, "%s-shm", p);
  remove(wal);
  remove(p);
}

static void test_corrupt_and_overlay(void) {
  const char *plain = tmp_path("vfs_c.db");
  const char *zdb = tmp_path("vfs_c.zdb");
  make_db(plain, 4096, 0);
  CHECK_EQ(convert_file(plain, zdb), 0);
  uint8_t *d;
  size_t n;
  CHECK_EQ(read_file(zdb, &d, &n), 0);
  zdb_header h;
  zdb_header_decode(d, &h);
  /* damage a frame in the middle: open works, reads report corruption */
  size_t pos = (size_t)(h.dict_offset + h.dict_length +
                        (h.index_offset - h.dict_offset - h.dict_length) / 2);
  d[pos] ^= 0x5A;
  write_file(zdb, d, n);
  sqlite3 *b = open_db(zdb, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  CHECK(b != NULL);
  if (b) {
    int rc;
    query_hash(b, "SELECT * FROM line ORDER BY id", &rc);
    CHECK(rc == SQLITE_CORRUPT || rc == SQLITE_IOERR);
    sqlite3_close(b);
  }
  d[pos] ^= 0x5A;
  d[100] ^= 1; /* header checksum */
  write_file(zdb, d, n);
  sqlite3 *c = NULL;
  int rc = sqlite3_open_v2(zdb, &c, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  CHECK_EQ(rc, SQLITE_CORRUPT);
  sqlite3_close(c);
  d[100] ^= 1;
  write_file(zdb, d, n);
  char ov[1100];
  snprintf(ov, sizeof ov, "%s%s", zdb, ZDB_OVERLAY_SUFFIX);
  /* a sidecar no longer than its header is a torn creation: ignored */
  write_file(ov, "x", 1);
  c = NULL;
  rc = sqlite3_open_v2(zdb, &c, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  CHECK_EQ(rc, SQLITE_OK);
  sqlite3_close(c);
  /* longer than a header but not bound to this base: refused */
  uint8_t junk[300];
  memset(junk, 0x33, sizeof junk);
  write_file(ov, junk, sizeof junk);
  c = NULL;
  rc = sqlite3_open_v2(zdb, &c, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  CHECK_EQ(rc, SQLITE_CORRUPT);
  sqlite3_close(c);
  remove(ov);
  free(d);
  remove(plain);
  remove(zdb);
}

typedef struct {
  const char *path;
  uint64_t expect[NQ];
  int errors;
} mt_arg;

static void mt_reader(void *p) {
  mt_arg *a = (mt_arg *)p;
  for (int i = 0; i < 12; i++) {
    sqlite3 *db = open_db(a->path, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
    if (!db) {
      a->errors++;
      continue;
    }
    for (int q = 0; q < NQ - 1; q++) {
      int rc;
      if (query_hash(db, k_queries[q], &rc) != a->expect[q] || rc) a->errors++;
    }
    sqlite3_close(db);
  }
}

static void test_threads(void) {
  const char *plain = tmp_path("vfs_mt.db");
  const char *zdb = tmp_path("vfs_mt.zdb");
  make_db(plain, 16384, 0);
  CHECK_EQ(convert_file(plain, zdb), 0);
  sqlite3 *a = open_db(plain, SQLITE_OPEN_READONLY, NULL);
  enum { T = 8 };
  mt_arg args[T];
  for (int q = 0; q < NQ; q++) args[0].expect[q] = query_hash(a, k_queries[q], NULL);
  sqlite3_close(a);
  zplat_thread th[T];
  zvfs_set_cache_budget(64 * 16384);
  for (int i = 0; i < T; i++) {
    args[i] = args[0];
    args[i].path = zdb;
    args[i].errors = 0;
    zplat_thread_start(&th[i], mt_reader, &args[i]);
  }
  for (int i = 0; i < T; i++) {
    zplat_thread_join(th[i]);
    CHECK_EQ(args[i].errors, 0);
  }
  zvfs_set_cache_budget(16 << 20);
  remove(plain);
  remove(zdb);
}

#if defined(_WIN32)
#include <windows.h>
/* A writer's RESERVED/PENDING/SHARED locks sit on [1GB, 1GB + 512) of the base
   and are mandatory on Windows: with the gap no page read may touch them. */
static void test_windows_lock_bytes(void) {
  const char *plain = tmp_path("wl_plain.db");
  const char *zdb = tmp_path("wl.zdb");
  remove(plain);
  remove(zdb);
  sqlite3 *db = open_db(plain, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  exec(db, "PRAGMA page_size=16384; CREATE TABLE t(id INTEGER PRIMARY KEY, b BLOB);"
           "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE "
           "i<70000) INSERT INTO t SELECT i, randomblob(16000) FROM n;");
  sqlite3_close(db);
  zvfs_conv *c = NULL;
  CHECK_EQ(zvfs_conv_create(zdb, NULL, 0, NULL, 1, 8, 1, 16 << 20, NULL, &c), 0);
  FILE *in = fopen(plain, "rb");
  static uint8_t buf[1 << 20];
  size_t k;
  while (c && in && (k = fread(buf, 1, sizeof buf, in)) > 0)
    if (zvfs_conv_feed(c, buf, k)) break;
  if (in) fclose(in);
  CHECK_EQ(zvfs_conv_finish(c, NULL), 0);
  zvfs_conv_destroy(c);
  remove(plain);
  HANDLE h = CreateFileA(zdb, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                         NULL, OPEN_EXISTING, 0, NULL);
  /* a writer's RESERVED byte: readers stay allowed, as in SQLite */
  OVERLAPPED ov;
  memset(&ov, 0, sizeof ov);
  ov.Offset = (DWORD)ZDB_LOCK_BYTE + 1;
  CHECK(LockFileEx(h, LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY, 0, 1,
                   0, &ov));
  zvfs_set_cache_budget(0);
  sqlite3 *r = open_db(zdb, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  int rc;
  query_hash(r, "SELECT count(*), sum(length(b)) FROM t", &rc);
  CHECK_EQ(rc, SQLITE_OK);
  sqlite3_close(r);
  zvfs_set_cache_budget(16 << 20);
  UnlockFileEx(h, 0, 1, 0, &ov);
  CloseHandle(h);
  printf("windows lock bytes: full scan while RESERVED is held: rc=%d\n", rc);
  remove(zdb);
}
#endif

/* ---- probe/reader must not drop this process's locks (POSIX: closing any
   fd of a file releases all of the process's fcntl locks on it) ---- */
#if defined(_WIN32)
#include <process.h>
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

static const char *g_self;

/* Child: exclusive lock on SQLite's SHARED range; 0 = acquired. */
static int child_lockprobe(const char *path) {
#if defined(_WIN32)
  HANDLE h = CreateFileA(path, GENERIC_READ | GENERIC_WRITE,
                         FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                         NULL, OPEN_EXISTING, 0, NULL);
  if (h == INVALID_HANDLE_VALUE) return 2;
  OVERLAPPED ov;
  memset(&ov, 0, sizeof ov);
  ov.Offset = (DWORD)(ZDB_LOCK_BYTE + 2);
  BOOL ok = LockFileEx(h, LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY, 0,
                       ZDB_LOCK_SIZE - 2, 0, &ov);
  if (ok) UnlockFileEx(h, 0, ZDB_LOCK_SIZE - 2, 0, &ov);
  CloseHandle(h);
  return ok ? 0 : 1;
#else
  int fd = open(path, O_RDWR);
  if (fd < 0) return 2;
  struct flock fl;
  memset(&fl, 0, sizeof fl);
  fl.l_type = F_WRLCK;
  fl.l_whence = SEEK_SET;
  fl.l_start = (off_t)(ZDB_LOCK_BYTE + 2);
  fl.l_len = ZDB_LOCK_SIZE - 2;
  int ok = fcntl(fd, F_SETLK, &fl) == 0;
  close(fd);
  return ok ? 0 : 1;
#endif
}

static int run_lockprobe(const char *path) {
#if defined(_WIN32)
  return (int)_spawnl(_P_WAIT, g_self, g_self, "lockprobe", path, NULL);
#else
  char cmd[4200];
  snprintf(cmd, sizeof cmd, "'%s' lockprobe '%s'", g_self, path);
  int st = system(cmd);
  return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
#endif
}

static void test_probe_keeps_locks(void) {
  const char *plain = tmp_path("lk_plain.db");
  const char *zdb = tmp_path("lk.zdb");
  make_db(plain, 4096, 0);
  CHECK_EQ(convert_file(plain, zdb), 0);
  const char *files[] = {plain, zdb};
  for (int fi = 0; fi < 2; fi++) {
    for (int action = 0; action < 4; action++) {
      sqlite3 *db = open_db(files[fi], SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
      sqlite3_stmt *st = NULL;
      exec(db, "BEGIN");
      sqlite3_prepare_v2(db, "SELECT count(*) FROM book", -1, &st, NULL);
      CHECK_EQ(sqlite3_step(st), SQLITE_ROW); /* SHARED is now held */
      CHECK_EQ(zvfs_in_use(files[fi]), fi ? 2 : 1);
      if (action == 1) CHECK_EQ(zvfs_probe_path(files[fi]), fi);
      if (action == 2) {
        zvfs_reader *r = NULL;
        CHECK_EQ(zvfs_reader_open(files[fi], &r), ZVFS_ERR_BUSY);
        zvfs_info info;
        CHECK_EQ(zvfs_state_info(files[fi], &info), fi ? ZVFS_OK : ZVFS_ERR_NOT_ZDB);
      }
      if (action == 3) {
        char dst[1100];
        snprintf(dst, sizeof dst, "%s.new", files[fi]);
        CHECK_EQ(zvfs_compact(files[fi], dst, 3, 1, 0, NULL, NULL, NULL, NULL, NULL, 0),
                 ZVFS_ERR_BUSY);
        CHECK_EQ(zvfs_compact_swap(files[fi], dst), ZVFS_ERR_BUSY);
        CHECK(zplat_exists(dst) == 0);
      }
      /* another process must not get a write lock over our SHARED */
      int child = run_lockprobe(files[fi]);
      if (child != 1)
        fprintf(stderr, "lock kept? file %d action %d: child %d\n", fi, action, child);
      CHECK_EQ(child, 1);
      sqlite3_finalize(st);
      exec(db, "COMMIT");
      sqlite3_close(db);
    }
    CHECK_EQ(zvfs_in_use(files[fi]), 0);
  }
  remove(plain);
  remove(zdb);
  printf("probe/reader/compaction of an open file keep its locks\n");
}

#if !defined(_WIN32)
/* A path through a symlink names the same file (xFullPathname resolves it). */
static void test_symlink_path(void) {
  const char *plain = tmp_path("sl_plain.db");
  const char *zdb = tmp_path("sl.zdb");
  char link_path[4200];
  snprintf(link_path, sizeof link_path, "%s.lnk", zdb);
  make_db(plain, 4096, 0);
  CHECK_EQ(convert_file(plain, zdb), 0);
  unlink(link_path);
  CHECK_EQ(symlink(zdb, link_path), 0);
  CHECK_EQ(zvfs_in_use(link_path), 0);
  CHECK_EQ(zvfs_probe_path(link_path), 1);
  zvfs_reader *r = NULL;
  CHECK_EQ(zvfs_reader_open(link_path, &r), ZVFS_OK);
  zvfs_reader_close(r);
  const char *opened[] = {zdb, link_path};
  for (int i = 0; i < 2; i++) {
    sqlite3 *db = open_db(opened[i], SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
    sqlite3_stmt *st = NULL;
    exec(db, "BEGIN");
    sqlite3_prepare_v2(db, "SELECT count(*) FROM book", -1, &st, NULL);
    CHECK_EQ(sqlite3_step(st), SQLITE_ROW);
    CHECK_EQ(zvfs_in_use(link_path), 2);
    CHECK_EQ(zvfs_in_use(zdb), 2);
    CHECK_EQ(zvfs_probe_path(opened[1 - i]), 1);
    r = NULL;
    CHECK_EQ(zvfs_reader_open(opened[1 - i], &r), ZVFS_ERR_BUSY);
    CHECK_EQ(run_lockprobe(zdb), 1);
    sqlite3_finalize(st);
    exec(db, "COMMIT");
    sqlite3_close(db);
  }
  CHECK_EQ(zvfs_in_use(link_path), 0);
  unlink(link_path);
  remove(plain);
  remove(zdb);
  printf("a path through a symlink is the same file\n");
}
#endif

/* A connection of another VFS keeps its locks when zvfs opens the file. */
static void test_other_vfs_keeps_locks(void) {
  const char *plain = tmp_path("ov_plain.db");
  make_db(plain, 4096, 0);
  sqlite3 *d = open_db(plain, SQLITE_OPEN_READONLY, NULL);
  sqlite3_stmt *st = NULL;
  exec(d, "BEGIN");
  sqlite3_prepare_v2(d, "SELECT count(*) FROM book", -1, &st, NULL);
  CHECK_EQ(sqlite3_step(st), SQLITE_ROW);
  sqlite3 *z = open_db(plain, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
  sqlite3_stmt *zs = NULL;
  sqlite3_prepare_v2(z, "SELECT count(*) FROM book", -1, &zs, NULL);
  CHECK_EQ(sqlite3_step(zs), SQLITE_ROW);
  sqlite3_finalize(zs);
  sqlite3_close(z);
  CHECK_EQ(run_lockprobe(plain), 1);
  sqlite3_finalize(st);
  exec(d, "COMMIT");
  sqlite3_close(d);
  remove(plain);
  printf("a connection of another VFS keeps its locks\n");
}

int main(int argc, char **argv) {
  if (argc == 3 && strcmp(argv[1], "lockprobe") == 0) return child_lockprobe(argv[2]);
  g_self = argv[0];
  sqlite3_auto_extension((void (*)(void))sqlite3_otzariazvfs_init);
  sqlite3 *m = NULL;
  sqlite3_open(":memory:", &m);
  sqlite3_close(m);
  CHECK(zvfs_is_registered());
  CHECK(sqlite3_vfs_find(ZVFS_VFS_NAME) != NULL);
  test_passthrough();
  test_roundtrip(4096, 0);
  test_roundtrip(16384, 1);
  test_roundtrip(65536, 0);
  test_corrupt_and_overlay();
  test_threads();
  test_probe_keeps_locks();
  test_other_vfs_keeps_locks();
#if !defined(_WIN32)
  test_symlink_path();
#endif
#if defined(_WIN32)
  if (getenv("ZVFS_BIG_TESTS")) test_windows_lock_bytes();
#endif
  zvfs_stats s;
  zvfs_get_stats(&s);
  printf("stats: frames %lld hits %lld misses %lld corrupt %lld open %lld\n",
         (long long)s.frames_decoded, (long long)s.cache_hits,
         (long long)s.cache_misses, (long long)s.corrupt_frames,
         (long long)s.open_files);
  CHECK_EQ(s.open_files, 0);
  if (g_failures) {
    fprintf(stderr, "%d check(s) failed\n", g_failures);
    return 1;
  }
  printf("all vfs tests passed (sqlite %s)\n", sqlite3_libversion());
  return 0;
}
