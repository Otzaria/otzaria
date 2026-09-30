/* SQL helpers shared by the write-path tests. */
#ifndef ZVFS_TEST_SQL_H
#define ZVFS_TEST_SQL_H

#include "sqlite3.h"
#include "test_common.h"
#include "zvfs.h"
#include "zvfs_internal.h"

static int ts_verbose;

static int ts_exec(sqlite3 *db, const char *sql) {
  char *err = NULL;
  int rc = sqlite3_exec(db, sql, NULL, NULL, &err);
  if (rc != SQLITE_OK && ts_verbose)
    fprintf(stderr, "sql rc=%d: %s\n  in: %.200s\n", rc, err ? err : "?", sql);
  sqlite3_free(err);
  return rc;
}

static void ts_must(sqlite3 *db, const char *sql) {
  char *err = NULL;
  if (sqlite3_exec(db, sql, NULL, NULL, &err) != SQLITE_OK) {
    fprintf(stderr, "sql error: %s\n  in: %.300s\n", err ? err : "?", sql);
    g_failures++;
  }
  sqlite3_free(err);
}

static sqlite3 *ts_open(const char *path, int flags, const char *vfs) {
  sqlite3 *db = NULL;
  if (sqlite3_open_v2(path, &db, flags, vfs) != SQLITE_OK) {
    sqlite3_close(db);
    return NULL;
  }
  sqlite3_busy_timeout(db, 5000);
  return db;
}

static void ts_remove_all(const char *path) {
  static const char *sfx[] = {"",     "-zovl", "-journal", "-wal",
                              "-shm", ".new",  "-zlck",    ".install"};
  char b[1100];
  for (int i = 0; i < 8; i++) {
    snprintf(b, sizeof b, "%s%s", path, sfx[i]);
    remove(b);
  }
}

static uint64_t ts_fnv(uint64_t h, const void *p, size_t n) {
  const uint8_t *b = (const uint8_t *)p;
  for (size_t i = 0; i < n; i++) {
    h ^= b[i];
    h *= 1099511628211ull;
  }
  return h;
}

/* Hash of a result set including value types. */
static uint64_t ts_hash_rows(sqlite3 *db, const char *sql, uint64_t h, int *rc_out) {
  sqlite3_stmt *st = NULL;
  int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
  while (rc == SQLITE_OK) {
    rc = sqlite3_step(st);
    if (rc != SQLITE_ROW) break;
    rc = SQLITE_OK;
    for (int i = 0; i < sqlite3_column_count(st); i++) {
      uint8_t t = (uint8_t)sqlite3_column_type(st, i);
      h = ts_fnv(h, &t, 1);
      const void *p = sqlite3_column_blob(st, i);
      int n = sqlite3_column_bytes(st, i);
      if (p && n) h = ts_fnv(h, p, (size_t)n);
      h = ts_fnv(h, "\xff", 1);
    }
  }
  if (rc == SQLITE_DONE) rc = SQLITE_OK;
  sqlite3_finalize(st);
  if (rc_out && *rc_out == SQLITE_OK) *rc_out = rc;
  return h;
}

/* Schema plus every table, each fully ordered by all of its columns. */
static uint64_t ts_content_hash(sqlite3 *db, int *rc_out) {
  int rc = SQLITE_OK;
  uint64_t h = ts_hash_rows(
      db, "SELECT type, name, tbl_name, sql FROM sqlite_schema ORDER BY name",
      1469598103934665603ull, &rc);
  sqlite3_stmt *st = NULL;
  if (rc == SQLITE_OK)
    rc = sqlite3_prepare_v2(db,
                            "SELECT name FROM sqlite_schema WHERE type='table' "
                            "AND name NOT LIKE 'sqlite_%' ORDER BY name",
                            -1, &st, NULL);
  char names[64][64];
  int nt = 0;
  while (rc == SQLITE_OK && sqlite3_step(st) == SQLITE_ROW && nt < 64)
    snprintf(names[nt++], 64, "%s", (const char *)sqlite3_column_text(st, 0));
  sqlite3_finalize(st);
  for (int t = 0; rc == SQLITE_OK && t < nt; t++) {
    char q[512];
    snprintf(q, sizeof q, "SELECT count(*) FROM pragma_table_info('%.60s')", names[t]);
    sqlite3_stmt *c = NULL;
    int ncol = 0;
    rc = sqlite3_prepare_v2(db, q, -1, &c, NULL);
    if (rc == SQLITE_OK && sqlite3_step(c) == SQLITE_ROW) ncol = sqlite3_column_int(c, 0);
    sqlite3_finalize(c);
    char sql[1024];
    int k = snprintf(sql, sizeof sql, "SELECT * FROM \"%.60s\" ORDER BY 1", names[t]);
    for (int i = 2; i <= ncol && k < (int)sizeof sql - 8; i++)
      k += snprintf(sql + k, sizeof sql - (size_t)k, ",%d", i);
    h = ts_fnv(h, names[t], strlen(names[t]));
    h = ts_hash_rows(db, sql, h, &rc);
  }
  if (rc_out) *rc_out = rc;
  return h;
}

static int ts_integrity_ok(sqlite3 *db) {
  sqlite3_stmt *st = NULL;
  int ok = 0;
  if (sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &st, NULL) == SQLITE_OK &&
      sqlite3_step(st) == SQLITE_ROW) {
    const char *v = (const char *)sqlite3_column_text(st, 0);
    ok = v && strcmp(v, "ok") == 0;
    if (!ok && ts_verbose) fprintf(stderr, "integrity: %s\n", v ? v : "?");
    ok = ok && sqlite3_step(st) == SQLITE_DONE;
  }
  sqlite3_finalize(st);
  return ok;
}

static int64_t ts_int(sqlite3 *db, const char *sql) {
  sqlite3_stmt *st = NULL;
  int64_t v = -1;
  if (sqlite3_prepare_v2(db, sql, -1, &st, NULL) == SQLITE_OK &&
      sqlite3_step(st) == SQLITE_ROW)
    v = sqlite3_column_int64(st, 0);
  sqlite3_finalize(st);
  return v;
}

static int ts_convert_bytes(const uint8_t *data, size_t n, const char *dst) {
  const char *name;
  const void *dict;
  size_t dl;
  zvfs_builtin_dict(0, &name, &dict, &dl, NULL);
  zvfs_conv *c = NULL;
  int rc = zvfs_conv_create(dst, dict, dl, name, 3, 2, 1, 1 << 20, NULL, &c);
  if (!rc) rc = zvfs_conv_feed(c, data, n);
  if (!rc) rc = zvfs_conv_finish(c, NULL);
  zvfs_conv_destroy(c);
  return rc;
}

static int ts_convert(const char *src, const char *dst) {
  uint8_t *data;
  size_t n;
  if (read_file(src, &data, &n)) return -1;
  int rc = ts_convert_bytes(data, n, dst);
  free(data);
  return rc;
}

/* Deterministic library-like schema: no random(), so runs are repeatable. */
static void ts_make_base(sqlite3 *db, int books, int lines) {
  char sql[4096];
  ts_must(db,
          "CREATE TABLE schema_meta(key TEXT PRIMARY KEY, value TEXT);"
          "CREATE TABLE book(id INTEGER PRIMARY KEY, title TEXT NOT NULL, cat INT);"
          "CREATE TABLE line(id INTEGER PRIMARY KEY, bookId INT REFERENCES book(id),"
          " lineIndex INT, content TEXT, extra BLOB);"
          "CREATE INDEX idx_line_book ON line(bookId, lineIndex);"
          "CREATE TABLE link(id INTEGER PRIMARY KEY, src INT, dst INT, kind TEXT);"
          "CREATE INDEX idx_link_src ON link(src);"
          "CREATE TABLE meta(k TEXT PRIMARY KEY, v) WITHOUT ROWID;"
          "INSERT INTO schema_meta VALUES('db_version','1'),('db_schema_version','5');");
  snprintf(sql, sizeof sql,
           "BEGIN;"
           "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<%d)"
           " INSERT INTO book SELECT i, printf('book %%d %%s', i, substr("
           "'sefer perek pasuk halacha mishna gemara rashi tosafot', 1+i%%40, 12)),"
           " i%%9 FROM n;"
           "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<%d)"
           " INSERT INTO line SELECT i, 1+i%%%d, i/%d, printf('line %%d: %%s %%.*c', i,"
           " substr('alpha beta gamma delta epsilon zeta eta theta iota kappa', 1+i%%50,"
           " 10+i%%30), (i*7)%%120, 'q'), CASE WHEN i%%61=0 THEN CAST(printf('%%.*c',"
           " 3000+(i*37)%%9000, 'z') AS BLOB) END FROM n;"
           "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<%d)"
           " INSERT INTO link SELECT i, 1+(i*7919)%%%d, 1+(i*104729)%%%d, 'k'||(i%%5) FROM n;"
           "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<500)"
           " INSERT INTO meta SELECT 'key'||i, printf('v%%.*c', i%%200, 'm') FROM n;"
           "COMMIT;",
           books, lines, books, books, lines / 2, lines, lines);
  ts_must(db, sql);
}

/* A patch.db in the updater's shape (upsert_/delete_ tables, patch_meta). */
static void ts_make_patch(sqlite3 *p, int seed, int lines, int n_up, int n_new,
                          int n_del) {
  char sql[4096];
  ts_must(p,
          "CREATE TABLE patch_meta(key TEXT PRIMARY KEY, value TEXT);"
          "CREATE TABLE migrations(version INT, sql TEXT);"
          "CREATE TABLE upsert_book(id INTEGER PRIMARY KEY, title TEXT, cat INT);"
          "CREATE TABLE upsert_line(id INTEGER PRIMARY KEY, bookId INT, lineIndex INT,"
          " content TEXT, extra BLOB);"
          "CREATE TABLE delete_line(id INTEGER PRIMARY KEY);"
          "CREATE TABLE delete_link(id INTEGER PRIMARY KEY);"
          "CREATE TABLE upsert_schema_meta(key TEXT PRIMARY KEY, value TEXT);"
          "INSERT INTO patch_meta VALUES('schema_version','1'),('from_version','1'),"
          "('to_version','2');"
          "INSERT INTO upsert_schema_meta VALUES('db_version','2');"
          "INSERT INTO migrations VALUES(1,"
          "'CREATE INDEX IF NOT EXISTS idx_link_kind ON link(kind)');");
  snprintf(sql, sizeof sql,
           "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<%d)"
           " INSERT OR REPLACE INTO upsert_line SELECT 1+(i*2654435761+%d)%%%d, 1+i%%7, i,"
           " printf('patched %%d/%%d %%.*c', i, %d, (i*13)%%700, 'p'), NULL FROM n;"
           "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<%d)"
           " INSERT INTO upsert_line SELECT %d+i, 1+i%%5, i, printf('new line %%d %%.*c',"
           " i, i%%300, 'n'), CASE WHEN i%%40=0 THEN CAST(printf('%%.*c', 5000, 'b') AS BLOB)"
           " END FROM n;"
           "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<%d)"
           " INSERT OR IGNORE INTO delete_line SELECT 1+(i*40503+%d)%%%d FROM n"
           " WHERE 1+(i*40503+%d)%%%d NOT IN (SELECT id FROM upsert_line);"
           "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<%d)"
           " INSERT OR IGNORE INTO delete_link SELECT 1+(i*31+%d)%%%d FROM n;"
           "INSERT INTO upsert_book VALUES(3, 'renamed %d', 1), (1000000+%d, 'new', 2);",
           n_up, seed, lines, seed, n_new, lines + 1000 + seed * 100000, n_del, seed,
           lines, seed, lines, n_del, seed, lines / 2, seed, seed);
  ts_must(p, sql);
}

/* The PatchApplier's statement sequence, chunked by rowid like _runChunked. */
static int ts_apply_patch(sqlite3 *db, const char *patch_path, int chunk) {
  char sql[1024];
  int rc = ts_exec(db, "PRAGMA foreign_keys=ON");
  snprintf(sql, sizeof sql, "ATTACH DATABASE '%s' AS patch", patch_path);
  if (!rc) rc = ts_exec(db, sql);
  if (rc) return rc;
  rc = ts_exec(db, "BEGIN");
  if (!rc) rc = ts_exec(db, "PRAGMA defer_foreign_keys=ON");
  if (!rc) rc = ts_exec(db, "CREATE INDEX IF NOT EXISTS idx_link_kind ON link(kind)");
  static const char *ups[] = {
      "INSERT INTO book(id,title,cat) SELECT id,title,cat FROM patch.upsert_book"
      " WHERE rowid > %lld AND rowid <= %lld ON CONFLICT(id) DO UPDATE SET"
      " title=excluded.title, cat=excluded.cat",
      "INSERT INTO line(id,bookId,lineIndex,content,extra) SELECT"
      " id,bookId,lineIndex,content,extra FROM patch.upsert_line WHERE rowid > %lld"
      " AND rowid <= %lld ON CONFLICT(id) DO UPDATE SET bookId=excluded.bookId,"
      " lineIndex=excluded.lineIndex, content=excluded.content, extra=excluded.extra",
      "DELETE FROM link WHERE id IN (SELECT id FROM patch.delete_link WHERE"
      " rowid > %lld AND rowid <= %lld)",
      "DELETE FROM line WHERE id IN (SELECT id FROM patch.delete_line WHERE"
      " rowid > %lld AND rowid <= %lld)",
  };
  static const char *tabs[] = {"upsert_book", "upsert_line", "delete_link",
                               "delete_line"};
  for (int t = 0; !rc && t < 4; t++) {
    char q[256];
    snprintf(q, sizeof q, "SELECT coalesce(max(rowid),0) FROM patch.%s", tabs[t]);
    int64_t hi = ts_int(db, q);
    for (int64_t lo = 0; !rc && lo < hi; lo += chunk) {
      snprintf(sql, sizeof sql, ups[t], (long long)lo, (long long)(lo + chunk));
      rc = ts_exec(db, sql);
    }
  }
  if (!rc)
    rc = ts_exec(db, "INSERT INTO schema_meta(key,value) SELECT key,value FROM"
                     " patch.upsert_schema_meta WHERE true ON CONFLICT(key) DO UPDATE"
                     " SET value=excluded.value");
  if (!rc) rc = ts_exec(db, "COMMIT");
  if (rc) ts_exec(db, "ROLLBACK");
  ts_exec(db, "DETACH DATABASE patch");
  return rc;
}

#endif
