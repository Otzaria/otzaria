import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

/// Builds a multi-table database with indexes, overflow pages and blobs.
void createTestDb(String path, {int pageSize = 4096, bool wal = false}) {
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final f = File('$path$suffix');
    if (f.existsSync()) f.deleteSync();
  }
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA page_size=$pageSize');
    db.execute(wal ? 'PRAGMA journal_mode=WAL' : 'PRAGMA journal_mode=DELETE');
    db.execute('''
      CREATE TABLE book(id INTEGER PRIMARY KEY, title TEXT NOT NULL, cat INT);
      CREATE TABLE line(id INTEGER PRIMARY KEY, bookId INT, lineIndex INT,
                        content TEXT, extra BLOB);
      CREATE INDEX idx_line_book ON line(bookId, lineIndex);
      CREATE TABLE link(id INTEGER PRIMARY KEY, src INT, dst INT, kind TEXT);
      CREATE INDEX idx_link_src ON link(src);
      CREATE TABLE meta(k TEXT PRIMARY KEY, v) WITHOUT ROWID;
    ''');
    db.execute('BEGIN');
    final words = [
      'sefer',
      'perek',
      'pasuk',
      'halacha',
      'mishna',
      'gemara',
      'rashi',
      'tosafot',
      'שלום',
      'תורה',
    ];
    final insBook = db.prepare('INSERT INTO book VALUES(?,?,?)');
    for (var i = 1; i <= 150; i++) {
      insBook.execute([i, 'book $i ${words[i % words.length]}', i % 9]);
    }
    insBook.close();
    final insLine = db.prepare('INSERT INTO line VALUES(?,?,?,?,?)');
    var seed = 12345;
    int next() => seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    for (var i = 1; i <= 15000; i++) {
      final n = 3 + next() % 40;
      final text = List.generate(
        n,
        (_) => words[next() % words.length],
      ).join(' ');
      Uint8List? blob;
      if (i % 131 == 0) {
        blob = Uint8List.fromList(
          List.generate(6000 + next() % 9000, (_) => next() & 0xff),
        );
      }
      insLine.execute([i, i % 150 + 1, i ~/ 150, text, blob]);
    }
    insLine.close();
    final insLink = db.prepare('INSERT INTO link VALUES(?,?,?,?)');
    for (var i = 1; i <= 8000; i++) {
      insLink.execute([
        i,
        1 + next() % 15000,
        1 + next() % 15000,
        'k${next() % 5}',
      ]);
    }
    insLink.close();
    final insMeta = db.prepare('INSERT INTO meta VALUES(?,?)');
    for (var i = 0; i < 2000; i++) {
      insMeta.execute(['key$i', 'value ${'x' * (i % 300)}']);
    }
    insMeta.close();
    db.execute('COMMIT');
    if (wal) db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  } finally {
    db.close();
  }
}

const testQueries = [
  'SELECT * FROM book ORDER BY id',
  'SELECT * FROM line ORDER BY id',
  'SELECT bookId, count(*), sum(length(content)), max(lineIndex) FROM line '
      'GROUP BY bookId ORDER BY bookId',
  'SELECT l.content, b.title FROM line l JOIN book b ON b.id = l.bookId '
      'WHERE l.bookId BETWEEN 10 AND 30 AND l.lineIndex < 40 '
      'ORDER BY l.bookId, l.lineIndex',
  'SELECT s.content, d.content, k.kind FROM link k JOIN line s ON s.id = k.src '
      'JOIN line d ON d.id = k.dst WHERE k.src < 3000 ORDER BY k.id',
  'SELECT * FROM meta ORDER BY k',
  'SELECT hex(extra) FROM line WHERE extra IS NOT NULL ORDER BY id',
];

/// Digest of a result set, including value types.
String queryDigest(Database db, String sql) {
  final rs = db.select(sql);
  final out = AccumulatorSink<Digest>();
  final sink = sha256.startChunkedConversion(out);
  for (final row in rs.rows) {
    for (final v in row) {
      final bytes = switch (v) {
        null => const [0],
        final Uint8List b => [1, ...b],
        final Object o => [2, ...utf8.encode('${o.runtimeType}:$o')],
      };
      sink.add(bytes);
      sink.add(const [0xff]);
    }
    sink.add(const [0xfe]);
  }
  sink.close();
  return out.events.single.toString();
}

class AccumulatorSink<T> implements Sink<T> {
  final events = <T>[];
  @override
  void add(T event) => events.add(event);
  @override
  void close() {}
}
