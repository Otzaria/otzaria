/* Crash injection: patch-shaped transactions through zvfs over memfs, killed
   at every write and every sync, with several power-loss models. After each
   crash the database must pass integrity_check and hold exactly the state
   before or after the transaction (after, once COMMIT returned under a
   durable configuration). */
#include "memfs.h"
#include "test_sql.h"


#define ZDB "/db/lib.zdb"
#define PATCH "/db/patch.db"
#define PLAIN "/db/plain.db"

enum { M_DELETE, M_WAL };
static const char *k_mode[] = {"delete", "wal"};
static const char *k_sync[] = {"off", "normal", "full"};
static const char *k_pol[] = {"lose", "subset", "tear", "keep"};

typedef struct stats {
  int64_t iterations, pre, post, double_crash, failures;
} stats;

typedef struct plan {
  const char *name;
  int ps, books, lines, up, nw, del;
  int64_t stride;
} plan;
static plan g_plan = {"", 4096, 60, 3000, 300, 120, 120, 1};
static int g_page_size = 4096;
static int g_progress;

static sqlite3 *open_z(void) {
  return ts_open(ZDB, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
}

static void build_start(int with_overlay, int books, int lines) {
  memfs_remove_all();
  sqlite3 *p = ts_open(PLAIN, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, "memfs");
  char sql[64];
  snprintf(sql, sizeof sql, "PRAGMA page_size=%d", g_page_size);
  ts_must(p, sql);
  ts_make_base(p, books, lines);
  sqlite3_close(p);
  uint8_t *bytes;
  int64_t n = memfs_get(PLAIN, &bytes);
  const char *tmp = tmp_path("crash_base.zdb");
  CHECK_EQ(ts_convert_bytes(bytes, (size_t)n, tmp), 0);
  free(bytes);
  size_t zl;
  uint8_t *z;
  CHECK_EQ(read_file(tmp, &z, &zl), 0);
  remove(tmp);
  memfs_remove(PLAIN);
  memfs_put(ZDB, z, (int64_t)zl);
  free(z);
  sqlite3 *pp = ts_open(PATCH, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, "memfs");
  if (with_overlay) {
    /* an earlier update already lives in the overlay */
    ts_make_patch(pp, 7, lines, g_plan.up / 2, g_plan.nw / 3, g_plan.del / 3);
    sqlite3_close(pp);
    sqlite3 *db = open_z();
    CHECK_EQ(ts_apply_patch(db, PATCH, 64), SQLITE_OK);
    sqlite3_close(db);
    memfs_remove(PATCH);
    pp = ts_open(PATCH, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, "memfs");
  }
  ts_make_patch(pp, 1, lines, g_plan.up, g_plan.nw, g_plan.del);
  sqlite3_close(pp);
  /* make everything durable: the start state is not under test */
  memfs_sync_all();
}

/* Returns 1 when COMMIT returned SQLITE_OK. */
static int run_txn(int mode, int sync, int chunk) {
  sqlite3 *db = open_z();
  if (!db) return 0;
  char sql[64];
  snprintf(sql, sizeof sql, "PRAGMA synchronous=%d", sync);
  ts_exec(db, sql);
  int ok = 1;
  if (mode == M_WAL) {
    sqlite3_stmt *st = NULL;
    /* the app switches to WAL for the apply and back afterwards */
    if (sqlite3_prepare_v2(db, "PRAGMA journal_mode=WAL", -1, &st, NULL) ||
        sqlite3_step(st) != SQLITE_ROW)
      ok = 0;
    sqlite3_finalize(st);
  }
  int committed = ok && ts_apply_patch(db, PATCH, chunk) == SQLITE_OK;
  if (mode == M_WAL) {
    ts_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)");
    ts_exec(db, "PRAGMA journal_mode=DELETE");
  }
  sqlite3_close(db);
  return committed;
}

static uint64_t current_hash(int *ok) {
  sqlite3 *db = open_z();
  *ok = 0;
  if (!db) return 0;
  int rc = SQLITE_OK;
  uint64_t h = ts_content_hash(db, &rc);
  *ok = rc == SQLITE_OK && ts_integrity_ok(db);
  sqlite3_close(db);
  return h;
}

/* After recovery the file must stay writable and consistent. */
static int follow_up_write(void) {
  sqlite3 *db = open_z();
  if (!db) return 0;
  int ok = ts_exec(db, "UPDATE meta SET v=v||'!' WHERE k IN ('key1','key250')") ==
           SQLITE_OK;
  sqlite3_close(db);
  sqlite3 *r = open_z();
  ok = ok && r && ts_integrity_ok(r) &&
       ts_int(r, "SELECT count(*) FROM meta WHERE v LIKE '%!'") == 2;
  sqlite3_close(r);
  return ok;
}

static void check_open_files(void) {
  zvfs_stats s;
  zvfs_get_stats(&s);
  CHECK_EQ(s.open_files, 0);
}

static void one_config(int with_overlay, int mode, int sync, stats *st,
                       int64_t stride) {
  build_start(with_overlay, g_plan.books, g_plan.lines);
  mf_snap start;
  memfs_snapshot(&start);
  int ok;
  uint64_t pre = current_hash(&ok);
  CHECK(ok);
  memfs_restore(&start);
  MF.writes = MF.syncs = 0;
  int committed = run_txn(mode, sync, 97);
  CHECK(committed);
  int64_t W = MF.writes, S = MF.syncs;
  uint64_t post = current_hash(&ok);
  CHECK(ok);
  CHECK(pre != post);
  int durable_sync = mode == M_DELETE ? sync >= 1 : sync >= 2;
  if (g_progress)
    fprintf(stderr, "config ovl=%d %s sync=%s: writes=%lld syncs=%lld\n",
            with_overlay, k_mode[mode], k_sync[sync], (long long)W, (long long)S);
  int64_t local_fail = 0, iters = 0;

  for (int kind = 0; kind < 2; kind++) {
    int64_t limit = kind == 0 ? W : S;
    for (int64_t k = 1; k <= limit; k += stride) {
      for (int pol = 0; pol < MF_POLICIES; pol++) {
        /* unsynced runs are consistent only across a process kill */
        if (sync == 0 && pol != MF_KEEP_ALL) continue;
        memfs_restore(&start);
        MF.rng = 0x1234567ull + (uint64_t)k * 7919u + (uint64_t)pol * 104729u +
                 (uint64_t)kind * 31u;
        MF.writes = MF.syncs = 0;
        if (kind == 0) MF.fail_write = k;
        else MF.fail_sync = k;
        int c = run_txn(mode, sync, 97);
        memfs_crash(pol);
        int dbl = (k % 5) == 0;
        if (dbl) {
          /* crash again while recovery (hot journal / WAL) runs */
          MF.writes = MF.syncs = 0;
          MF.fail_write = 1 + (int64_t)(mf_rand() % 12);
          int tmp;
          current_hash(&tmp);
          memfs_crash(pol == MF_KEEP_ALL ? MF_KEEP_ALL : MF_TEAR_LAST);
          st->double_crash++;
        }
        uint64_t h = current_hash(&ok);
        int must_post = c && (pol == MF_KEEP_ALL || durable_sync);
        int good = ok && (h == pre || h == post) && (!must_post || h == post);
        if (good) good = follow_up_write();
        iters++;
        if (g_progress && iters % 200 == 0)
          fprintf(stderr, "  %lld iterations\n", (long long)iters);
        if (h == pre) st->pre++;
        else if (h == post) st->post++;
        if (!good) {
          local_fail++;
          if (local_fail <= 5)
            fprintf(stderr,
                    "FAIL ovl=%d mode=%s sync=%s %s#%lld policy=%s dbl=%d "
                    "committed=%d integrity=%d state=%s\n",
                    with_overlay, k_mode[mode], k_sync[sync],
                    kind ? "sync" : "write", (long long)k, k_pol[pol], dbl, c, ok,
                    h == pre ? "pre" : h == post ? "post" : "OTHER");
        }
        check_open_files();
      }
    }
  }
  memfs_snap_free(&start);
  st->iterations += iters;
  st->failures += local_fail;
  g_failures += (int)local_fail;
  printf("  ovl=%d %-6s sync=%-6s writes=%-4lld syncs=%-3lld iterations=%-5lld "
         "failures=%lld\n",
         with_overlay, k_mode[mode], k_sync[sync], (long long)W, (long long)S,
         (long long)iters, (long long)local_fail);
  fflush(stdout);
}

int main(void) {
  memfs_register();
  sqlite3_auto_extension((void (*)(void))sqlite3_otzariazvfs_init);
  sqlite3 *m = NULL;
  sqlite3_open(":memory:", &m);
  sqlite3_close(m);
  CHECK(zvfs_is_registered());
  ts_verbose = getenv("ZVFS_VERBOSE") != NULL;
  g_progress = getenv("ZVFS_PROGRESS") != NULL;
  const char *e = getenv("ZVFS_CRASH_STRIDE");
  int64_t stride = e ? atoll(e) : 1;
  if (stride < 1) stride = 1;
  stats st;
  memset(&st, 0, sizeof st);
  /* small: every write and sync; medium: a larger patch, sampled */
  static const plan plans[] = {
      {"small, every fault point", 4096, 20, 600, 60, 20, 20, 1},
      {"medium, sampled", 4096, 60, 3000, 300, 120, 120, 7},
      {"small, page 1024", 1024, 20, 600, 60, 20, 20, 2},
  };
  const char *pm = getenv("ZVFS_CRASH_PLANS");
  int mask = pm ? atoi(pm) : 7;
  for (int pi = 0; pi < 3; pi++) {
    if (!(mask & (1 << pi))) continue;
    g_plan = plans[pi];
    g_page_size = g_plan.ps;
    printf("plan: %s (page %d, %d lines, patch %d/%d/%d)\n", g_plan.name,
           g_page_size, g_plan.lines, g_plan.up, g_plan.nw, g_plan.del);
    for (int ov = 0; ov < 2; ov++)
      for (int mode = 0; mode < 2; mode++)
        for (int sync = 0; sync < 3; sync++)
          one_config(ov, mode, sync, &st, g_plan.stride * stride);
  }
  printf("crash iterations %lld (pre %lld, post %lld, double crashes %lld), "
         "failures %lld\n",
         (long long)st.iterations, (long long)st.pre, (long long)st.post,
         (long long)st.double_crash, (long long)st.failures);
  memfs_remove_all();
  if (g_failures) {
    fprintf(stderr, "%d check(s) failed\n", g_failures);
    return 1;
  }
  printf("all crash tests passed\n");
  return 0;
}
