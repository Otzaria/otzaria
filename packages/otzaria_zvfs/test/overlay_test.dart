import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:otzaria_zvfs/otzaria_zvfs.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_db.dart';

late Directory tmp;

String p(String name) => '${tmp.path}${Platform.pathSeparator}$name';

void removeAll(String path) {
  for (final s in ['', '-zovl', '-journal', '-wal', '-shm', '.new', '-zlck']) {
    final f = File('$path$s');
    if (f.existsSync()) f.deleteSync();
  }
}

/// Schema plus every table, each ordered by all of its columns.
String dbDigest(Database db) {
  final parts = <String>[
    queryDigest(
      db,
      'SELECT type, name, tbl_name, sql FROM sqlite_schema ORDER BY name',
    ),
  ];
  final tables = db.select(
    "SELECT name FROM sqlite_schema WHERE type='table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  for (final t in tables) {
    final name = t['name'] as String;
    final n =
        db.select('SELECT count(*) AS c FROM pragma_table_info(?)', [
              name,
            ]).single['c']
            as int;
    final order = [for (var i = 1; i <= n; i++) '$i'].join(',');
    parts.add(
      '$name:${queryDigest(db, 'SELECT * FROM "$name" ORDER BY $order')}',
    );
  }
  return sha256.convert(parts.join('|').codeUnits).toString();
}

String integrity(Database db) =>
    db.select('PRAGMA integrity_check').first.values.first as String;

Future<void> convert(String src, String dst) => convertToZdb(
  source: ZdbSource.file(src),
  destination: dst,
  threads: 2,
  level: 3,
);

/// Runs [sql] on both; they must agree on success or failure.
void both(Database a, Database b, String sql) {
  Object? ea, eb;
  try {
    a.execute(sql);
  } on SqliteException catch (e) {
    ea = e.resultCode;
  }
  try {
    b.execute(sql);
  } on SqliteException catch (e) {
    eb = e.resultCode;
  }
  expect(eb, ea, reason: sql);
}

String randomStatement(Random r, int step, List<int> tables) {
  final id = r.nextInt(30000);
  switch (r.nextInt(7)) {
    case 0:
      final blob = r.nextInt(8) == 0
          ? "CAST(printf('%.*c', 7000, 'x') AS BLOB)"
          : 'NULL';
      return 'INSERT OR REPLACE INTO line VALUES($id, ${1 + step % 20}, $step, '
          "printf('s$step %.*c', ${r.nextInt(3000)}, 'w'), $blob)";
    case 1:
      return "UPDATE line SET content = content || '$step' "
          'WHERE id BETWEEN $id AND ${id + r.nextInt(200)}';
    case 2:
      return 'DELETE FROM line WHERE id BETWEEN $id AND ${id + r.nextInt(300)}';
    case 3:
      return "INSERT OR REPLACE INTO meta VALUES('k${id % 2000}', "
          "printf('%.*c', ${r.nextInt(900)}, 'v'))";
    case 4:
      final k = tables[0]++;
      if (r.nextInt(3) == 0 && k > 0) {
        return 'DROP TABLE IF EXISTS extra${r.nextInt(k)}';
      }
      return r.nextBool()
          ? 'CREATE TABLE extra$k AS SELECT id, content FROM line '
                'WHERE id % ${3 + k % 11} = 0'
          : 'CREATE INDEX IF NOT EXISTS ix${k % 4} ON line(content, id)';
    case 5:
      return 'ALTER TABLE book ADD COLUMN c$step TEXT DEFAULT '
          "'${'z' * (step % 7)}'";
    default:
      return 'DELETE FROM link WHERE id % ${3 + r.nextInt(50)} = ${r.nextInt(3)}';
  }
}

/// The library updater's statement shape: ATTACH, one transaction of
/// chunked upserts and deletes, foreign-key check, COMMIT, DETACH.
void applyPatchLikeUpdater(Database db, String patchPath, {int chunk = 500}) {
  db.execute('PRAGMA foreign_keys = ON');
  db.execute('ATTACH DATABASE ? AS patch', [patchPath]);
  final preFk = db.select('PRAGMA foreign_key_check').length;
  db.execute('BEGIN');
  try {
    db.execute('PRAGMA defer_foreign_keys = ON');
    for (final m in db.select(
      'SELECT sql FROM patch.migrations ORDER BY version',
    )) {
      db.execute(m['sql'] as String);
    }
    void chunked(String table, String Function(String range) sql) {
      final hi = db
          .select('SELECT max(rowid) AS m FROM patch."$table"')
          .single['m'];
      if (hi is! int) return;
      for (var lo = 0; lo < hi; lo += chunk) {
        db.execute(sql('rowid > $lo AND rowid <= ${lo + chunk}'));
      }
    }

    chunked(
      'upsert_book',
      (r) =>
          'INSERT INTO book(id,title,cat) SELECT id,title,cat FROM patch.upsert_book '
          'WHERE $r ON CONFLICT(id) DO UPDATE SET title=excluded.title, '
          'cat=excluded.cat',
    );
    chunked(
      'upsert_line',
      (r) =>
          'INSERT INTO line(id,bookId,lineIndex,content,extra) SELECT '
          'id,bookId,lineIndex,content,extra FROM patch.upsert_line WHERE $r '
          'ON CONFLICT(id) DO UPDATE SET bookId=excluded.bookId, '
          'lineIndex=excluded.lineIndex, content=excluded.content, '
          'extra=excluded.extra',
    );
    chunked(
      'delete_link',
      (r) =>
          'DELETE FROM link WHERE id IN (SELECT id FROM patch.delete_link WHERE $r)',
    );
    chunked(
      'delete_line',
      (r) =>
          'DELETE FROM line WHERE id IN (SELECT id FROM patch.delete_line WHERE $r)',
    );
    expect(
      db.select('PRAGMA foreign_key_check').length,
      lessThanOrEqualTo(preFk),
    );
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  } finally {
    db.execute('DETACH DATABASE patch');
  }
}

void createPatch(
  String path,
  int seed, {
  int updates = 4000,
  int inserts = 3000,
}) {
  removeAll(path);
  final db = sqlite3.open(path);
  try {
    db.execute('''
      CREATE TABLE migrations(version INT, sql TEXT);
      INSERT INTO migrations VALUES(1,
        'CREATE INDEX IF NOT EXISTS idx_link_kind ON link(kind)');
      CREATE TABLE upsert_book(id INTEGER PRIMARY KEY, title TEXT, cat INT);
      CREATE TABLE upsert_line(id INTEGER PRIMARY KEY, bookId INT,
        lineIndex INT, content TEXT, extra BLOB);
      CREATE TABLE delete_line(id INTEGER PRIMARY KEY);
      CREATE TABLE delete_link(id INTEGER PRIMARY KEY);
    ''');
    final r = Random(seed);
    db.execute('BEGIN');
    final up = db.prepare(
      'INSERT OR REPLACE INTO upsert_line VALUES(?,?,?,?,?)',
    );
    for (var i = 0; i < updates; i++) {
      up.execute([
        1 + r.nextInt(15000),
        1 + r.nextInt(150),
        i,
        'patched $seed/$i ${'ש' * r.nextInt(300)}',
        null,
      ]);
    }
    for (var i = 0; i < inserts; i++) {
      up.execute([
        20000 + seed * 10000 + i,
        1 + r.nextInt(150),
        i,
        'new $i ${'ת' * r.nextInt(200)}',
        i % 50 == 0 ? Uint8List(6000) : null,
      ]);
    }
    up.close();
    db.execute(
      'INSERT OR IGNORE INTO delete_line SELECT id FROM (SELECT abs(random()) '
      '% 15000 + 1 AS id FROM upsert_line LIMIT 500) '
      'WHERE id NOT IN (SELECT id FROM upsert_line)',
    );
    db.execute(
      'INSERT OR IGNORE INTO delete_link SELECT abs(random()) % 8000 + 1 '
      'FROM upsert_line LIMIT 800',
    );
    db.execute(
      "INSERT INTO upsert_book VALUES(3, 'renamed $seed', 1), (${1000 + seed}, "
      "'new book', 2)",
    );
    db.execute('COMMIT');
  } finally {
    db.close();
  }
}

void main() {
  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('zvfs_ovl_');
    ZVfs.register();
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  for (final pageSize in [4096, 1024]) {
    test('random workloads (page $pageSize) equal a plain database, byte for '
        'byte', () async {
      final plain = p('eq_$pageSize.db');
      final zdb = p('eq_$pageSize.zdb');
      createTestDb(plain, pageSize: pageSize);
      removeAll(zdb);
      await convert(plain, zdb);
      final a = sqlite3.open(plain);
      final b = sqlite3.open(zdb, vfs: ZVfs.name);
      final r = Random(pageSize);
      final tables = [0];
      var wal = false;
      try {
        for (var step = 0; step < 250; step++) {
          final kind = r.nextInt(20);
          if (kind == 0) {
            wal = !wal;
            both(a, b, 'PRAGMA journal_mode=${wal ? 'WAL' : 'DELETE'}');
          } else if (kind == 1 && wal) {
            both(a, b, 'PRAGMA wal_checkpoint(TRUNCATE)');
          } else {
            both(a, b, 'BEGIN');
            for (var i = 0, n = 1 + r.nextInt(12); i < n; i++) {
              both(a, b, randomStatement(r, step, tables));
            }
            both(a, b, r.nextInt(9) == 0 ? 'ROLLBACK' : 'COMMIT');
          }
          if (step % 25 == 24) {
            expect(dbDigest(b), dbDigest(a), reason: 'step $step');
          }
        }
        // one transaction of 100K rows
        both(a, b, 'BEGIN');
        both(
          a,
          b,
          'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n '
          'WHERE i<100000) INSERT OR REPLACE INTO line SELECT 50000+i, i%40, i, '
          "printf('bulk %d %.*c', i, i%90, 'b'), NULL FROM n",
        );
        both(
          a,
          b,
          'UPDATE line SET lineIndex = lineIndex + 1 WHERE id % 3 = 0',
        );
        both(a, b, 'COMMIT');
        both(a, b, 'PRAGMA journal_mode=DELETE');
        expect(dbDigest(b), dbDigest(a));
        expect(integrity(b), 'ok');
      } finally {
        a.close();
        b.close();
      }
      final bytes = File(plain).readAsBytesSync();
      expect(readZdbInfo(zdb).logicalSize, bytes.length);
      expect(readZdbBytes(zdb, 0, bytes.length), bytes);
      final ro = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
      final plainRo = sqlite3.open(plain, mode: OpenMode.readOnly);
      expect(dbDigest(ro), dbDigest(plainRo));
      ro.close();
      plainRo.close();
      await verifyZdb(zdb);
      final ovl = readZdbOverlayInfo(zdb);
      expect(ovl.present, isTrue);
      expect(ovl.uncommittedBytes, 0);
      print(
        'page $pageSize: base ${readZdbInfo(zdb).physicalSize} B, overlay '
        '${ovl.fileSize} B (${ovl.commits} commits), plain ${bytes.length} B',
      );
      removeAll(plain);
      removeAll(zdb);
    }, timeout: const Timeout(Duration(minutes: 10)));
  }

  test(
    'an updater-shaped patch in WAL mode, checkpointed back to DELETE',
    () async {
      final plain = p('upd.db');
      final zdb = p('upd.zdb');
      final patch = p('upd_patch.db');
      createTestDb(plain);
      removeAll(zdb);
      await convert(plain, zdb);
      createPatch(patch, 1);
      for (final path in [plain, zdb]) {
        final db = path == zdb
            ? sqlite3.open(path, vfs: ZVfs.name)
            : sqlite3.open(path);
        try {
          expect(
            db.select('PRAGMA journal_mode=WAL').single.columnAt(0),
            'wal',
          );
          applyPatchLikeUpdater(db, patch);
          db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
          expect(
            db.select('PRAGMA journal_mode=DELETE').single.columnAt(0),
            'delete',
          );
        } finally {
          db.close();
        }
      }
      expect(File('$zdb-wal').existsSync(), isFalse);
      final a = sqlite3.open(plain, mode: OpenMode.readOnly);
      final b = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
      expect(dbDigest(b), dbDigest(a));
      expect(integrity(b), 'ok');
      a.close();
      b.close();
      final bytes = File(plain).readAsBytesSync();
      expect(readZdbBytes(zdb, 0, bytes.length), bytes);
    },
  );

  test('isolate readers see only committed snapshots during a WAL apply', () async {
    final plain = p('mt.db');
    final zdb = p('mt.zdb');
    createTestDb(plain, pageSize: 4096);
    final setup = sqlite3.open(plain);
    setup.execute('''
      CREATE TABLE acct(id INTEGER PRIMARY KEY, bal INT);
      WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<300)
        INSERT INTO acct SELECT i, 0 FROM n;
      CREATE TABLE ver(d TEXT, n INT);
    ''');
    setup.execute('INSERT INTO ver VALUES(?, 0)', [
      queryDigest(setup, 'SELECT id, bal FROM acct ORDER BY id'),
    ]);
    setup.close();
    removeAll(zdb);
    await convert(plain, zdb);

    Future<(int, int)> reader(int seed) => Isolate.run(() {
      ZVfs.register();
      var ok = 0, bad = 0;
      final db = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
      try {
        db.execute('PRAGMA busy_timeout=5000');
        for (var i = 0; i < 300; i++) {
          db.execute('BEGIN');
          try {
            final d = queryDigest(db, 'SELECT id, bal FROM acct ORDER BY id');
            final v = db.select('SELECT d, n FROM ver').single;
            final sum = db.select('SELECT sum(bal) AS s FROM acct').single['s'];
            final lines = db
                .select(
                  "SELECT count(*) AS c FROM line WHERE content LIKE 'mt %'",
                )
                .single['c'];
            if (d == v['d'] && sum == 0 && lines == v['n']) {
              ok++;
            } else {
              bad++;
            }
          } finally {
            db.execute('COMMIT');
          }
        }
      } finally {
        db.close();
      }
      return (ok, bad);
    });

    Future<int> writer() => Isolate.run(() {
      ZVfs.register();
      final db = sqlite3.open(zdb, vfs: ZVfs.name);
      final r = Random(5);
      var lines = 0;
      try {
        db.execute('PRAGMA busy_timeout=5000');
        db.execute('PRAGMA journal_mode=WAL');
        db.execute('PRAGMA wal_autocheckpoint=64');
        for (var t = 0; t < 150; t++) {
          db.execute('BEGIN IMMEDIATE');
          for (var k = 0; k < 30; k++) {
            final amt = r.nextInt(1000);
            db.execute('UPDATE acct SET bal = bal - ? WHERE id = ?', [
              amt,
              1 + r.nextInt(300),
            ]);
            db.execute('UPDATE acct SET bal = bal + ? WHERE id = ?', [
              amt,
              1 + r.nextInt(300),
            ]);
          }
          final add = 1 + r.nextInt(80);
          db.execute(
            'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE '
            "i<$add) INSERT INTO line(bookId, lineIndex, content) SELECT 1, i, "
            "printf('mt %d %.*c', i, i*7, 'x') FROM n",
          );
          lines += add;
          db.execute('UPDATE ver SET d = ?, n = ?', [
            queryDigest(db, 'SELECT id, bal FROM acct ORDER BY id'),
            lines,
          ]);
          db.execute('COMMIT');
          if (t % 30 == 29) db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        }
        db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      } finally {
        db.close();
      }
      return lines;
    });

    final results = await Future.wait([
      writer(),
      for (var i = 0; i < 4; i++) reader(i).then((r) => r.$1 * 100000 + r.$2),
    ]);
    for (final r in results.skip(1)) {
      expect(r % 100000, 0, reason: 'torn or mixed snapshots');
      expect(r ~/ 100000, 300);
    }
    final db = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
    expect(integrity(db), 'ok');
    expect(
      db
          .select("SELECT count(*) AS c FROM line WHERE content LIKE 'mt %'")
          .single['c'],
      results[0],
    );
    db.close();
    // per path: other suites run in the same process
    expect(ZVfs.isOpen(zdb), isFalse);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test(
    'compactZdb keeps the content, drops the overlay, records lineage',
    () async {
      final plain = p('cz.db');
      final zdb = p('cz.zdb');
      final patch = p('cz_patch.db');
      createTestDb(plain);
      removeAll(zdb);
      await convert(plain, zdb);
      createPatch(patch, 2);
      final w = sqlite3.open(zdb, vfs: ZVfs.name);
      applyPatchLikeUpdater(w, patch);
      final want = dbDigest(w);
      final before = readZdbInfo(zdb);
      final ovl = readZdbOverlayInfo(zdb);
      await expectLater(
        compactZdb(zdb, level: 3),
        throwsA(
          isA<ZdbException>().having((e) => e.code, 'code', ZdbException.busy),
        ),
      );
      w.close();
      expect(File('$zdb.new').existsSync(), isFalse);
      final progress = <int>[];
      final res = await compactZdb(
        zdb,
        level: 3,
        onProgress: (d, t) => progress.add(d),
      );
      expect(File('$zdb-zovl').existsSync(), isFalse);
      expect(File('$zdb.new').existsSync(), isFalse);
      expect(res.info.derivedFromUuid, before.fileUuid);
      expect(res.info.includesOverlayUuid, ovl.overlayUuid);
      expect(res.info.includesOverlaySeq, ovl.seq);
      expect(res.info.formatMinor, 2);
      expect(res.bytesAfter, lessThan(res.bytesBefore));
      expect(progress.last, res.info.logicalSize);
      final r = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
      expect(dbDigest(r), want);
      r.close();
      // writes after compaction bind a new overlay to the new base
      final w2 = sqlite3.open(zdb, vfs: ZVfs.name);
      w2.execute("UPDATE meta SET v = 'after' WHERE k = 'key7'");
      w2.close();
      final r2 = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
      expect(
        r2.select("SELECT v FROM meta WHERE k = 'key7'").single.columnAt(0),
        'after',
      );
      expect(integrity(r2), 'ok');
      r2.close();
      print(
        'compaction: ${res.bytesBefore} -> ${res.bytesAfter} bytes in '
        '${res.elapsed.inMilliseconds} ms',
      );
    },
  );

  test('the swap window: new base next to its obsolete overlay', () async {
    final plain = p('sw.db');
    final zdb = p('sw.zdb');
    createTestDb(plain);
    removeAll(zdb);
    await convert(plain, zdb);
    final w = sqlite3.open(zdb, vfs: ZVfs.name);
    w.execute('DELETE FROM line WHERE id % 5 = 0');
    final want = dbDigest(w);
    w.close();
    final oldOverlay = File('$zdb-zovl').readAsBytesSync();
    await compactZdb(zdb, level: 3);
    // as if the overlay delete never reached the disk
    File('$zdb-zovl').writeAsBytesSync(oldOverlay);
    expect(readZdbOverlayInfo(zdb).present, isFalse);
    final r = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
    expect(dbDigest(r), want);
    r.close();
    final w2 = sqlite3.open(zdb, vfs: ZVfs.name);
    w2.execute("UPDATE meta SET v = 'x' WHERE k = 'key1'");
    w2.close();
    expect(readZdbOverlayInfo(zdb).present, isTrue);
    final r2 = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
    expect(
      r2.select("SELECT v FROM meta WHERE k = 'key1'").single.columnAt(0),
      'x',
    );
    expect(integrity(r2), 'ok');
    r2.close();
  });

  test('installZdb swaps in a download and drops the old sidecars', () async {
    final plain = p('in.db');
    final plain2 = p('in2.db');
    final zdb = p('in.zdb');
    final cand = p('in_download.zdb');
    createTestDb(plain);
    createTestDb(plain2);
    final d2 = sqlite3.open(plain2);
    d2.execute("UPDATE meta SET v = 'installed' WHERE k = 'key3'");
    final want = dbDigest(d2);
    d2.close();
    removeAll(zdb);
    removeAll(cand);
    await convert(plain, zdb);
    await convert(plain2, cand);
    final w = sqlite3.open(zdb, vfs: ZVfs.name);
    w.execute('DELETE FROM line WHERE id % 5 = 0');
    final busy = throwsA(
      isA<ZdbException>().having((e) => e.code, 'code', ZdbException.busy),
    );
    await expectLater(installZdb(zdb, cand), busy);
    w.close();

    // another window: an isolate of this same process holding a connection
    final events = ReceivePort();
    final stream = events.asBroadcastStream();
    await Isolate.spawn((SendPort out) async {
      final db = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
      db.select('SELECT count(*) FROM book');
      final ctl = ReceivePort();
      out.send(ctl.sendPort);
      await ctl.first;
      db.close();
      out.send('closed');
    }, events.sendPort);
    final ctl = await stream.first as SendPort;
    await expectLater(installZdb(zdb, cand), busy);
    ctl.send(null);
    await stream.firstWhere((e) => e == 'closed');
    events.close();

    await expectLater(
      installZdb(zdb, plain),
      throwsA(
        isA<ZdbException>().having((e) => e.code, 'code', ZdbException.notZdb),
      ),
    );
    expect(File('$zdb-zovl').existsSync(), isTrue);

    // a flipped byte inside a frame passes the open checks, not the verify
    final good = File(cand).readAsBytesSync();
    final bad = Uint8List.fromList(good);
    bad[bad.length ~/ 2] ^= 0x5A;
    File(cand).writeAsBytesSync(bad);
    await expectLater(
      installZdb(zdb, cand),
      throwsA(
        isA<ZdbException>().having((e) => e.code, 'code', ZdbException.corrupt),
      ),
    );
    expect(File('$zdb-zovl').existsSync(), isTrue);
    expect(File('$zdb.install').existsSync(), isFalse);
    File(cand).writeAsBytesSync(good);

    File('$zdb.new').writeAsBytesSync([1, 2, 3]);
    final info = await installZdb(zdb, cand);
    expect(info.includesOverlaySeq, 0);
    for (final s in ['-zovl', '.new', '-journal', '-wal']) {
      expect(File('$zdb$s').existsSync(), isFalse, reason: s);
    }
    expect(File(cand).existsSync(), isFalse);
    expect(File('$zdb-zlck').existsSync(), isTrue);
    final r = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
    expect(dbDigest(r), want);
    expect(integrity(r), 'ok');
    r.close();
  });

  test(
    'overlay fuzz: never crashes, serves a committed state or refuses',
    () async {
      final plain = p('fz.db');
      final zdb = p('fz.zdb');
      createTestDb(plain, pageSize: 4096);
      removeAll(zdb);
      await convert(plain, zdb);
      final states = <String>{};
      final seed = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
      states.add(dbDigest(seed));
      seed.close();
      final w = sqlite3.open(zdb, vfs: ZVfs.name);
      final r = Random(11);
      for (var t = 0; t < 8; t++) {
        w.execute('BEGIN');
        for (var k = 0; k < 20; k++) {
          try {
            w.execute(randomStatement(r, t, [100 + t]));
          } on SqliteException {
            // e.g. a repeated ALTER; the transaction goes on
          }
        }
        w.execute('COMMIT');
        states.add(dbDigest(w));
      }
      w.close();
      final good = File('$zdb-zovl').readAsBytesSync();
      final iters =
          int.tryParse(Platform.environment['ZVFS_FUZZ_ITERS'] ?? '') ?? 300;
      var opened = 0, refused = 0;
      for (var it = 0; it < iters; it++) {
        final m = Uint8List.fromList(good);
        var len = m.length;
        for (var k = 0, n = 1 + r.nextInt(4); k < n; k++) {
          final pos = r.nextInt(len);
          switch (r.nextInt(4)) {
            case 0:
              m[pos] ^= 1 << r.nextInt(8);
            case 1:
              m[pos] = r.nextInt(256);
            case 2:
              len = pos;
            default:
              for (var j = 0; j < 24 && pos + j < len; j++) {
                m[pos + j] = r.nextInt(256);
              }
          }
        }
        File('$zdb-zovl').writeAsBytesSync(Uint8List.sublistView(m, 0, len));
        Database db;
        try {
          db = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
        } on SqliteException {
          refused++;
          continue;
        }
        try {
          final d = dbDigest(db);
          expect(states.contains(d), isTrue, reason: 'iteration $it');
          opened++;
        } on SqliteException {
          refused++;
        } finally {
          db.close();
        }
      }
      print(
        'overlay fuzz: $iters mutations, $opened committed states, $refused refused',
      );
      File('$zdb-zovl').writeAsBytesSync(good);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'makeDefault routes VFS-less opens (like the updater) to zvfs',
    () async {
      final plain = p('def.db');
      final zdb = p('def.zdb');
      createTestDb(plain);
      removeAll(zdb);
      await convert(plain, zdb);
      ZVfs.register(makeDefault: true);
      try {
        final db = sqlite3.open(zdb);
        try {
          db.execute("INSERT INTO book VALUES (4242, 'via default', 1)");
        } finally {
          db.close();
        }
        final pl = sqlite3.open(plain);
        pl.execute('CREATE TABLE IF NOT EXISTS t(x)');
        pl.close();
      } finally {
        ZVfs.register(makeDefault: false);
      }
      expect(readZdbOverlayInfo(zdb).present, isTrue);
      final r = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
      expect(
        r.select('SELECT title FROM book WHERE id = 4242').single.columnAt(0),
        'via default',
      );
      r.close();
    },
  );

  test(
    'compaction zeroes freelist leaves and copies untouched frames',
    () async {
      final plain = p('fl.db');
      final zdb = p('fl.zdb');
      createTestDb(plain);
      removeAll(zdb);
      await convert(plain, zdb);
      final w = sqlite3.open(zdb, vfs: ZVfs.name);
      w.execute('DELETE FROM line WHERE id BETWEEN 3000 AND 9000');
      w.execute("UPDATE meta SET v = 'changed' WHERE k = 'key12'");
      final freePages =
          w.select('PRAGMA freelist_count').single.columnAt(0) as int;
      final want = dbDigest(w);
      w.close();
      expect(freePages, greaterThan(50));
      final res = await compactZdb(zdb, level: 3);
      expect(res.freelistPagesZeroed, greaterThan(0));
      expect(res.freelistPagesZeroed, lessThan(freePages)); // minus trunks
      expect(res.framesCopied, greaterThan(0));
      expect(res.framesCopied, lessThan(res.frames));
      expect(res.frames, res.info.frameCount);
      final r = sqlite3.open(zdb, vfs: ZVfs.name);
      expect(dbDigest(r), want);
      expect(integrity(r), 'ok');
      expect(r.select('PRAGMA freelist_count').single.columnAt(0), freePages);
      // SQLite takes the zeroed pages back from the freelist
      r.execute(
        'INSERT INTO line SELECT id + 100000, bookId, lineIndex, content, '
        'extra FROM line WHERE id < 2500',
      );
      expect(integrity(r), 'ok');
      r.close();
      // nothing changed since: only frame 0 is compressed again
      final again = await compactZdb(zdb, level: 3);
      expect(again.framesCopied, greaterThan(again.frames ~/ 2));
      await verifyZdb(zdb);
      print(
        'compaction: ${res.framesCopied} of ${res.frames} frames copied, '
        '${res.freelistPagesZeroed} freelist pages zeroed',
      );
      removeAll(plain);
      removeAll(zdb);
    },
  );

  test('convertToZdb zeroes the freelist of a file source', () async {
    final plain = p('flc.db');
    final zdb = p('flc.zdb');
    final keep = p('flc_keep.zdb');
    createTestDb(plain);
    final db = sqlite3.open(plain);
    db.execute('DELETE FROM line WHERE id > 7000');
    final freePages =
        db.select('PRAGMA freelist_count').single.columnAt(0) as int;
    db.close();
    expect(freePages, greaterThan(50));
    removeAll(zdb);
    removeAll(keep);
    final res = await convertToZdb(
      source: ZdbSource.file(plain),
      destination: zdb,
      level: 3,
    );
    final kept = await convertToZdb(
      source: ZdbSource.file(plain),
      destination: keep,
      level: 3,
      zeroFreelist: false,
    );
    expect(res.freelistPagesZeroed, greaterThan(0));
    expect(kept.freelistPagesZeroed, 0);
    expect(res.info.physicalSize, lessThan(kept.info.physicalSize));
    final bytes = File(plain).readAsBytesSync();
    expect(readZdbBytes(keep, 0, bytes.length), bytes);
    final a = sqlite3.open(plain, mode: OpenMode.readOnly);
    final b = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
    expect(dbDigest(b), dbDigest(a));
    expect(integrity(b), 'ok');
    a.close();
    b.close();
    print(
      'convert: ${res.freelistPagesZeroed} freelist pages zeroed, '
      '${kept.info.physicalSize} -> ${res.info.physicalSize} bytes',
    );
    removeAll(plain);
    removeAll(zdb);
    removeAll(keep);
  });

  test('a custom 1MB dictionary is carried and read back', () async {
    final plain = p('dict.db');
    final zdb = p('dict.zdb');
    createTestDb(plain);
    removeAll(zdb);
    final src = File(plain).readAsBytesSync();
    final raw = Uint8List(ZdbDictionary.maxBytes);
    for (var i = 0; i < raw.length; i++) {
      raw[i] = src[(i * 7919) % src.length];
    }
    final res = await convertToZdb(
      source: ZdbSource.file(plain),
      destination: zdb,
      dictionary: ZdbDictionary.custom('raw-1mb', raw),
      level: 3,
    );
    final info = readZdbInfo(zdb);
    expect(info.dictLength, ZdbDictionary.maxBytes);
    expect(info.dictName, 'raw-1mb');
    expect(info.dictId, 0); // raw content has no zstd id
    expect(res.info.dictLength, ZdbDictionary.maxBytes);
    await verifyZdb(zdb);
    final a = sqlite3.open(plain, mode: OpenMode.readOnly);
    final b = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
    expect(dbDigest(b), dbDigest(a));
    a.close();
    b.close();
    expect(
      () => ZdbDictionary.custom('big', Uint8List(ZdbDictionary.maxBytes + 1)),
      throwsArgumentError,
    );
    removeAll(plain);
    removeAll(zdb);
  });
}
