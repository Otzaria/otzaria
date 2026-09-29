// Benchmark of the write path (not part of CI): applies one updater-shaped
// patch to a plain copy and to a .zdb of the same database and compares.
//   dart run tool/bench_apply.dart --db <plain.db> --work <dir>
//     [--update-pct 5] [--insert-pct 2] [--delete-pct 0.5] [--level 9]
// The source is only read; <dir> gets plain.db, base.zdb(+overlay), patch.db.
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:otzaria_zvfs/otzaria_zvfs.dart';
import 'package:sqlite3/sqlite3.dart';

Map<String, String> _args(List<String> a) {
  final m = <String, String>{};
  for (var i = 0; i < a.length; i++) {
    if (!a[i].startsWith('--')) continue;
    final hasValue = i + 1 < a.length && !a[i + 1].startsWith('--');
    m[a[i].substring(2)] = hasValue ? a[++i] : 'true';
  }
  return m;
}

String _mb(int b) => '${(b / 1048576).toStringAsFixed(1)}MB';

int _size(String p) => File(p).existsSync() ? File(p).lengthSync() : 0;

void _removeAll(String p) {
  for (final s in ['', '-zovl', '-journal', '-wal', '-shm', '.new']) {
    if (File('$p$s').existsSync()) File('$p$s').deleteSync();
  }
}

String _digest(Database db, String sql) {
  final out = <int>[];
  for (final row in db.select(sql).rows) {
    out.addAll('$row'.codeUnits);
    out.add(10);
  }
  return sha256.convert(out).toString();
}

void _makePatch(String path, Database src, Map<String, String> a) {
  _removeAll(path);
  final upd = double.parse(a['update-pct'] ?? '5') / 100;
  final ins = double.parse(a['insert-pct'] ?? '2') / 100;
  final del = double.parse(a['delete-pct'] ?? '0.5') / 100;
  final lines = src
      .select('SELECT count(*) AS c, max(id) AS m FROM line')
      .single;
  final nLines = lines['c'] as int, maxId = lines['m'] as int;
  final links = src
      .select('SELECT count(*) AS c, max(id) AS m FROM link')
      .single;
  final p = sqlite3.open(path);
  p.execute('ATTACH DATABASE ? AS src', [
    src.select('PRAGMA database_list').first['file'],
  ]);
  p.execute('''
    CREATE TABLE upsert_line AS SELECT * FROM src.line WHERE 0;
    CREATE TABLE delete_line(id INTEGER PRIMARY KEY);
    CREATE TABLE upsert_link AS SELECT * FROM src.link WHERE 0;
    CREATE TABLE delete_link(id INTEGER PRIMARY KEY);
  ''');
  final r = Random(42);
  p.execute('BEGIN');
  // edited lines: a few words changed inside books, as a text fix would do
  p.execute(
    'INSERT INTO upsert_line SELECT id, bookId, lineIndex, '
    "replace(content, ' ', ' ־ ') || ' ✓', heRef, tocEntryId, charCount + 4 "
    'FROM src.line WHERE abs(random()) % 1000000 < ?',
    [(upd * 1000000).round()],
  );
  // new lines appended to existing books
  final books = [
    for (final b in src.select('SELECT id FROM book')) b['id'] as int,
  ];
  final ins1 = p.prepare('INSERT INTO upsert_line VALUES(?,?,?,?,?,?,?)');
  final text = src
      .select('SELECT content FROM line ORDER BY id LIMIT 2000')
      .map((e) => e['content'] as String)
      .toList();
  for (var i = 0; i < (nLines * ins).round(); i++) {
    final t = text[r.nextInt(text.length)];
    ins1.execute([
      maxId + 1 + i,
      books[r.nextInt(books.length)],
      1000000 + i,
      t,
      null,
      null,
      t.length,
    ]);
  }
  ins1.close();
  p.execute(
    'INSERT OR IGNORE INTO delete_line SELECT id FROM src.line WHERE abs(random()) '
    '% 1000000 < ? AND id NOT IN (SELECT id FROM upsert_line) AND id NOT IN '
    '(SELECT sourceLineId FROM src.link) AND id NOT IN (SELECT targetLineId FROM src.link)',
    [(del * 1000000).round()],
  );
  p.execute(
    'INSERT OR IGNORE INTO delete_link SELECT id FROM src.link WHERE abs(random()) '
    '% 1000000 < ?',
    [(0.03 * 1000000).round()],
  );
  p.execute(
    'INSERT INTO upsert_link SELECT ${links['m']} + rowid, sourceBookId, targetBookId, '
    'sourceLineId, targetLineId, targetLineIndex, targetBookOrderIndex, '
    'connectionTypeId, baseProvenance FROM src.link WHERE abs(random()) % 1000000 < ?',
    [(0.03 * 1000000).round()],
  );
  p.execute('COMMIT');
  p.execute('DETACH DATABASE src');
  final counts = [
    for (final t in [
      'upsert_line',
      'delete_line',
      'upsert_link',
      'delete_link',
    ])
      '$t=${p.select('SELECT count(*) AS c FROM $t').single['c']}',
  ];
  print(
    'patch: ${counts.join(', ')} (source $nLines lines, ${links['c']} links), '
    '${_mb(_size(path))}',
  );
  p.close();
}

/// The updater's shape: WAL for the apply, chunked upserts/deletes in one
/// transaction, checkpoint(TRUNCATE), back to DELETE.
Duration _apply(Database db, String patch) {
  final sw = Stopwatch()..start();
  db.execute('PRAGMA journal_mode=WAL');
  db.execute('ATTACH DATABASE ? AS patch', [patch]);
  db.execute('BEGIN');
  void chunked(String table, String Function(String) sql) {
    final hi = db
        .select('SELECT max(rowid) AS m FROM patch.$table')
        .single['m'];
    if (hi is! int) return;
    for (var lo = 0; lo < hi; lo += 50000) {
      db.execute(sql('rowid > $lo AND rowid <= ${lo + 50000}'));
    }
  }

  String upsert(String t, List<String> cols) =>
      'INSERT INTO $t(${cols.join(',')}) SELECT ${cols.join(',')} FROM patch.upsert_$t '
      'WHERE %R ON CONFLICT(id) DO UPDATE SET '
      '${cols.skip(1).map((c) => '$c=excluded.$c').join(',')}';
  final lineCols = [
    'id',
    'bookId',
    'lineIndex',
    'content',
    'heRef',
    'tocEntryId',
    'charCount',
  ];
  final linkCols = [
    'id',
    'sourceBookId',
    'targetBookId',
    'sourceLineId',
    'targetLineId',
    'targetLineIndex',
    'targetBookOrderIndex',
    'connectionTypeId',
    'baseProvenance',
  ];
  chunked('upsert_line', (r) => upsert('line', lineCols).replaceFirst('%R', r));
  chunked('upsert_link', (r) => upsert('link', linkCols).replaceFirst('%R', r));
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
  db.execute("UPDATE schema_meta SET value='2' WHERE key='db_version'");
  db.execute('COMMIT');
  db.execute('DETACH DATABASE patch');
  final commit = sw.elapsed;
  db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  db.execute('PRAGMA journal_mode=DELETE');
  print(
    '  commit ${commit.inMilliseconds} ms, checkpoint + DELETE '
    '${(sw.elapsed - commit).inMilliseconds} ms',
  );
  return sw.elapsed;
}

Future<void> main(List<String> argv) async {
  final a = _args(argv);
  final src = a['db']!, work = a['work']!;
  Directory(work).createSync(recursive: true);
  final plain = '$work${Platform.pathSeparator}plain.db';
  final zdb = '$work${Platform.pathSeparator}base.zdb';
  final patch = '$work${Platform.pathSeparator}patch.db';
  ZVfs.register();
  _removeAll(plain);
  _removeAll(zdb);
  File(src).copySync(plain);
  final level = int.parse(a['level'] ?? '9');
  var sw = Stopwatch()..start();
  await convertToZdb(
    source: ZdbSource.file(src),
    destination: zdb,
    level: level,
  );
  print(
    'base: ${_mb(_size(src))} plain -> ${_mb(_size(zdb))} zdb (level $level) in '
    '${sw.elapsedMilliseconds} ms',
  );
  final s = sqlite3.open(src, mode: OpenMode.readOnly);
  _makePatch(patch, s, a);
  s.close();

  print('apply to plain:');
  var db = sqlite3.open(plain);
  final tp = _apply(db, patch);
  db.close();
  print('apply to zdb:');
  final st0 = ZVfs.stats;
  db = sqlite3.open(zdb, vfs: ZVfs.name);
  final tz = _apply(db, patch);
  db.close();
  final st1 = ZVfs.stats;
  final ovl = readZdbOverlayInfo(zdb);
  final plainGrowth = _size(plain) - _size(src);
  print(
    'time: plain ${tp.inMilliseconds} ms, zdb ${tz.inMilliseconds} ms '
    '(x${(tz.inMicroseconds / tp.inMicroseconds).toStringAsFixed(2)})',
  );
  print(
    'overlay: ${_mb(ovl.fileSize)} after ${ovl.commits} commits, '
    '${ovl.mappedPages} pages mapped (${_mb(ovl.mappedPages * readZdbInfo(zdb).pageSize)} '
    'logical), ${st1.overlayRecords - st0.overlayRecords} records, '
    '${st1.overlaySyncs - st0.overlaySyncs} fsyncs; plain file grew ${_mb(plainGrowth)}',
  );
  print(
    'on disk: plain ${_mb(_size(plain))}, zdb base ${_mb(_size(zdb))} + overlay '
    '${_mb(ovl.fileSize)} = ${_mb(_size(zdb) + ovl.fileSize)}',
  );

  sw = Stopwatch()..start();
  final r = sqlite3.open(zdb, vfs: ZVfs.name, mode: OpenMode.readOnly);
  r.select('SELECT count(*) FROM schema_meta');
  print(
    'first open after the patch (overlay replay): ${sw.elapsedMilliseconds} ms',
  );
  final p = sqlite3.open(plain, mode: OpenMode.readOnly);
  for (final q in [
    'SELECT * FROM line ORDER BY id',
    'SELECT * FROM link ORDER BY id',
  ]) {
    if (_digest(p, q) != _digest(r, q)) {
      print('MISMATCH: $q');
      exitCode = 1;
    }
  }
  final ic = r.select('PRAGMA quick_check').first.values.first;
  print('content equal to plain: ${exitCode == 0}, quick_check: $ic');
  p.close();
  r.close();
  final bytes = File(plain).readAsBytesSync();
  final same = readZdbBytes(zdb, 0, bytes.length);
  var eq = same.length == bytes.length;
  for (var i = 0; eq && i < bytes.length; i++) {
    eq = same[i] == bytes[i];
  }
  print('logical bytes equal to the plain file: $eq');

  sw = Stopwatch()..start();
  final c = await compactZdb(zdb, level: level);
  print(
    'compaction: ${_mb(c.bytesBefore)} -> ${_mb(c.bytesAfter)} in '
    '${sw.elapsedMilliseconds} ms',
  );
}
