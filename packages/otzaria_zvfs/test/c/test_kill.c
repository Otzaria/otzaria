/* Real process kills. A child applies deterministic patch-like transactions
   (DELETE and WAL mode, sometimes a compaction) and is killed at a random
   moment; a second child reads snapshots concurrently. After every kill the
   database must pass integrity_check and equal the reference state of the
   last or the next transaction. */
#include "test_sql.h"

#if defined(_WIN32)
#include <windows.h>
typedef struct child {
  HANDLE proc, out;
} child;
#else
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>
typedef struct child {
  pid_t pid;
  int out;
} child;
#endif

static char g_self[4096];

static int spawn(child *c, const char *args) {
#if defined(_WIN32)
  SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, TRUE};
  HANDLE rd, wr;
  if (!CreatePipe(&rd, &wr, &sa, 0)) return -1;
  SetHandleInformation(rd, HANDLE_FLAG_INHERIT, 0);
  STARTUPINFOA si;
  memset(&si, 0, sizeof si);
  si.cb = sizeof si;
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdOutput = wr;
  si.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  PROCESS_INFORMATION pi;
  char cmd[8192];
  snprintf(cmd, sizeof cmd, "\"%s\" %s", g_self, args);
  if (!CreateProcessA(NULL, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
    CloseHandle(rd);
    CloseHandle(wr);
    return -1;
  }
  CloseHandle(wr);
  CloseHandle(pi.hThread);
  c->proc = pi.hProcess;
  c->out = rd;
  return 0;
#else
  int fds[2];
  if (pipe(fds)) return -1;
  pid_t pid = fork();
  if (pid < 0) return -1;
  if (pid == 0) {
    dup2(fds[1], 1);
    close(fds[0]);
    close(fds[1]);
    char buf[8192];
    snprintf(buf, sizeof buf, "exec \"%s\" %s", g_self, args);
    execl("/bin/sh", "sh", "-c", buf, (char *)NULL);
    _exit(127);
  }
  close(fds[1]);
  c->pid = pid;
  c->out = fds[0];
  return 0;
#endif
}

static void sleep_ms(int ms) {
#if defined(_WIN32)
  Sleep((DWORD)ms);
#else
  usleep((useconds_t)ms * 1000);
#endif
}

/* Kills the child and returns everything it wrote. */
static char *kill_and_read(child *c) {
#if defined(_WIN32)
  TerminateProcess(c->proc, 9);
  WaitForSingleObject(c->proc, INFINITE);
  CloseHandle(c->proc);
#else
  kill(c->pid, SIGKILL);
  waitpid(c->pid, NULL, 0);
#endif
  size_t cap = 1 << 16, len = 0;
  char *s = (char *)malloc(cap);
  for (;;) {
    if (len + 4096 > cap) s = (char *)realloc(s, cap *= 2);
#if defined(_WIN32)
    DWORD r = 0;
    if (!ReadFile(c->out, s + len, 4096, &r, NULL) || r == 0) break;
#else
    ssize_t r = read(c->out, s + len, 4096);
    if (r <= 0) break;
#endif
    len += (size_t)r;
  }
  s[len] = 0;
#if defined(_WIN32)
  CloseHandle(c->out);
#else
  close(c->out);
#endif
  return s;
}

/* ---- the workload ---- */
static void txn_sql(char *sql, size_t cap, int i) {
  snprintf(sql, cap,
           "UPDATE schema_meta SET value='%d' WHERE key='txn';"
           "UPDATE line SET content = printf('t%d %%s', substr(content, 1, 400))"
           " WHERE id %% 97 = %d %% 97;"
           "INSERT OR REPLACE INTO line(id, bookId, lineIndex, content)"
           " WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k<120)"
           " SELECT 100000 + (%d*120 + k) %% 30000, k %% 50, k, printf('n%d-%%d %%.*c',"
           " k, (k*%d) %% 500, 'y') FROM n;"
           "DELETE FROM line WHERE id IN (SELECT id FROM line WHERE id %% 211 = %d %% 211"
           " LIMIT 40);"
           "UPDATE acct SET bal = bal - %d WHERE id = %d;"
           "UPDATE acct SET bal = bal + %d WHERE id = %d;"
           "UPDATE ver SET h = (SELECT sum(id * bal) FROM acct), n = %d;",
           i, i, i, i, i, i, i, 1 + i % 50, 1 + (i * 7) % 100, 1 + i % 50,
           1 + (i * 13) % 100, i);
}

static void make_start(const char *plain) {
  ts_remove_all(plain);
  sqlite3 *p = ts_open(plain, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  ts_make_base(p, 50, 20000);
  ts_must(p, "INSERT INTO schema_meta VALUES('txn','0');"
             "CREATE TABLE acct(id INTEGER PRIMARY KEY, bal INT);"
             "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<100)"
             " INSERT INTO acct SELECT i, 0 FROM n;"
             "CREATE TABLE ver(h INT, n INT); INSERT INTO ver VALUES(0, 0);");
  sqlite3_close(p);
}

static int child_writer(const char *zdb, int start, int compact) {
  char sql[4096];
  for (int i = start;; i++) {
    /* other processes must have closed the file (see README), so only
       without the concurrent reader */
    if (compact && i % 25 == 0) {
      char dst[4200];
      snprintf(dst, sizeof dst, "%s.new", zdb);
      if (zvfs_compact(zdb, dst, 3, 2, NULL, NULL, NULL, NULL, 0) == ZVFS_OK &&
          zvfs_compact_swap(zdb, dst) == ZVFS_OK)
        printf("K %d\n", i);
      fflush(stdout);
    }
    sqlite3 *db = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
    if (!db) return 3;
    int wal = i % 3 == 0;
    if (i % 4 == 1) ts_exec(db, "PRAGMA synchronous=NORMAL");
    if (wal) ts_exec(db, "PRAGMA journal_mode=WAL");
    txn_sql(sql, sizeof sql, i);
    char full[4200];
    snprintf(full, sizeof full, "BEGIN; %s COMMIT;", sql);
    int rc = ts_exec(db, full);
    if (rc) {
      ts_exec(db, "ROLLBACK");
      sqlite3_close(db);
      i--;
      sleep_ms(5);
      continue;
    }
    printf("C %d\n", i);
    fflush(stdout);
    if (wal) {
      ts_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)");
      ts_exec(db, "PRAGMA journal_mode=DELETE");
    }
    sqlite3_close(db);
  }
}

static int child_reader(const char *zdb) {
  int reads = 0;
  for (;;) {
    sqlite3 *db = ts_open(zdb, SQLITE_OPEN_READONLY, ZVFS_VFS_NAME);
    if (!db) {
      sleep_ms(2);
      continue;
    }
    for (int k = 0; k < 20; k++) {
      if (ts_exec(db, "BEGIN") != SQLITE_OK) break;
      int64_t sum = ts_int(db, "SELECT sum(bal) FROM acct");
      int64_t h = ts_int(db, "SELECT sum(id * bal) FROM acct");
      int64_t stored = ts_int(db, "SELECT h FROM ver");
      int64_t n = ts_int(db, "SELECT n FROM ver");
      int64_t txn = ts_int(db, "SELECT value FROM schema_meta WHERE key='txn'");
      int rc = ts_exec(db, "COMMIT");
      if (rc == SQLITE_OK && sum != -1 && stored != -1 &&
          (sum != 0 || h != stored || n != txn)) {
        printf("BAD sum=%lld h=%lld stored=%lld n=%lld txn=%lld\n", (long long)sum,
               (long long)h, (long long)stored, (long long)n, (long long)txn);
        fflush(stdout);
      }
      reads++;
    }
    sqlite3_close(db);
    if (reads % 200 == 0) {
      printf("R %d\n", reads);
      fflush(stdout);
    }
  }
}

static int last_marker(const char *out, char tag) {
  int v = -1;
  for (const char *p = out; *p; p++) {
    if ((p == out || p[-1] == '\n') && p[0] == tag && p[1] == ' ') v = atoi(p + 2);
  }
  return v;
}

int main(int argc, char **argv) {
  setvbuf(stdout, NULL, _IONBF, 0); /* progress stays visible in logs */
  sqlite3_auto_extension((void (*)(void))sqlite3_otzariazvfs_init);
  sqlite3 *m = NULL;
  sqlite3_open(":memory:", &m);
  sqlite3_close(m);
  if (argc >= 5 && strcmp(argv[1], "writer") == 0)
    return child_writer(argv[2], atoi(argv[3]), atoi(argv[4]));
  if (argc >= 3 && strcmp(argv[1], "reader") == 0) return child_reader(argv[2]);

#if defined(_WIN32)
  GetModuleFileNameA(NULL, g_self, sizeof g_self);
#else
  snprintf(g_self, sizeof g_self, "%s", argv[0]);
#endif
  const char *e = getenv("ZVFS_KILL_ITERS");
  int iters = e ? atoi(e) : 300;
  const char *plain = tmp_path("kill_ref.db");
  const char *zdb = tmp_path("kill.zdb");
  make_start(plain);
  ts_remove_all(zdb);
  CHECK_EQ(ts_convert(plain, zdb), 0);
  sqlite3 *ref = ts_open(plain, SQLITE_OPEN_READWRITE, NULL);
  int ref_at = 0;
  uint64_t *ref_hash = (uint64_t *)calloc(100000, sizeof(uint64_t));
  int rc0 = 0;
  ref_hash[0] = ts_content_hash(ref, &rc0);
  char sql[4096], args[8192];
  int next = 1, bad = 0, readers_bad = 0, compactions = 0, mid = 0;
  int64_t reads = 0;
  srand(12345);
  for (int it = 0; it < iters && !bad; it++) {
    child w, r;
    int with_reader = it % 3 == 1;
    snprintf(args, sizeof args, "writer \"%s\" %d %d", zdb, next, !with_reader);
    CHECK_EQ(spawn(&w, args), 0);
    if (with_reader) {
      snprintf(args, sizeof args, "reader \"%s\"", zdb);
      CHECK_EQ(spawn(&r, args), 0);
    }
    sleep_ms(30 + rand() % 400);
    char *out = kill_and_read(&w);
    if (with_reader) {
      char *rout = kill_and_read(&r);
      if (strstr(rout, "BAD")) {
        readers_bad++;
        fprintf(stderr, "reader saw: %.300s\n", strstr(rout, "BAD"));
      }
      int n = last_marker(rout, 'R');
      if (n > 0) reads += n;
      free(rout);
    }
    int k = last_marker(out, 'C');
    if (strstr(out, "K ")) compactions++;
    free(out);
    /* recover and check */
    sqlite3 *db = ts_open(zdb, SQLITE_OPEN_READWRITE, ZVFS_VFS_NAME);
    int ok = db && ts_integrity_ok(db);
    int64_t mk = db ? ts_int(db, "SELECT value FROM schema_meta WHERE key='txn'") : -1;
    int rc = SQLITE_OK;
    uint64_t h = db ? ts_content_hash(db, &rc) : 0;
    sqlite3_close(db);
    while (ok && ref_at < mk) {
      ref_at++;
      txn_sql(sql, sizeof sql, ref_at);
      char full[4200];
      snprintf(full, sizeof full, "BEGIN; %s COMMIT;", sql);
      ts_must(ref, full);
      int r2 = 0;
      ref_hash[ref_at] = ts_content_hash(ref, &r2);
    }
    int lo = k < 0 ? next - 1 : k;
    int good = ok && rc == SQLITE_OK && mk >= lo && mk <= lo + 1 &&
               mk <= ref_at && h == ref_hash[mk];
    if (mk == lo + 1) mid++;
    if (!good) {
      bad++;
      fprintf(stderr,
              "iteration %d: integrity=%d marker=%lld last-committed=%d hash-ok=%d\n",
              it, ok, (long long)mk, k, mk >= 0 && mk <= ref_at && h == ref_hash[mk]);
    }
    next = (int)mk + 1;
  }
  sqlite3_close(ref);
  zvfs_reader *zr;
  zvfs_overlay_info oi;
  memset(&oi, 0, sizeof oi);
  if (zvfs_reader_open(zdb, &zr) == ZVFS_OK) {
    zvfs_reader_overlay_info(zr, &oi);
    CHECK_EQ(zvfs_reader_verify(zr, NULL, NULL), 0);
    zvfs_reader_close(zr);
  }
  printf("kill harness: %d kills, %d transactions committed, %d kills between "
         "commit and ack, %d compactions, %lld concurrent reads, reader "
         "violations %d, failures %d (overlay now %llu bytes)\n",
         iters, next - 1, mid, compactions, (long long)reads, readers_bad, bad,
         (unsigned long long)oi.file_size);
  CHECK_EQ(bad, 0);
  CHECK_EQ(readers_bad, 0);
  free(ref_hash);
  ts_remove_all(plain);
  ts_remove_all(zdb);
  if (g_failures) {
    fprintf(stderr, "%d check(s) failed\n", g_failures);
    return 1;
  }
  printf("all kill tests passed\n");
  return 0;
}
