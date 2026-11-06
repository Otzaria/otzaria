import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/repository/external_link_core.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/daos/line_ref_dao.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/utils/text/ref_key.dart';
import 'package:path/path.dart' as path;

const _books = [1, 2, 3, 4, 5];
const _linesPerBook = 300;
const _hashes = 12;

/// השאילתה שמסד לא רשמי חייב לקבל בדיוק.
String _originalSql(String ids) =>
    'SELECT lr.bookId, lr.lineIndex, l.id AS lineId, l.heRef '
    'FROM line_ref lr '
    'JOIN line l ON l.bookId = lr.bookId AND l.lineIndex = lr.lineIndex '
    'WHERE lr.refKeyHash = ? AND lr.bookId IN ($ids) '
    'ORDER BY lr.bookId, lr.lineIndex';

/// צורת seforim.db: line עם האינדקסים שלו ו-line_ref WITHOUT ROWID, בלי sqlite_stat1.
void _buildFixture(sqlite3.Database db) {
  db.execute('''
    CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER);
    CREATE TABLE line (id INTEGER PRIMARY KEY NOT NULL, bookId INTEGER NOT NULL,
      lineIndex INTEGER NOT NULL, content TEXT NOT NULL, heRef TEXT,
      tocEntryId INTEGER, charCount INTEGER NOT NULL DEFAULT 0);
    CREATE INDEX idx_line_book_index ON line(bookId, lineIndex);
    CREATE INDEX idx_line_toc ON line(tocEntryId);
    CREATE INDEX idx_line_heref ON line(heRef);
    CREATE TABLE line_ref (bookId INTEGER NOT NULL,
      refKeyHash INTEGER NOT NULL, lineIndex INTEGER NOT NULL,
      PRIMARY KEY (bookId, refKeyHash, lineIndex)) WITHOUT ROWID;
  ''');
  db.execute('BEGIN');
  for (final bookId in _books) {
    db.execute('INSERT INTO book VALUES (?, ?, 1)', [bookId, 'book $bookId']);
    for (var i = 0; i < _linesPerBook; i++) {
      db.execute(
        'INSERT INTO line (id, bookId, lineIndex, content, heRef) '
        'VALUES (?, ?, ?, ?, ?)',
        [bookId * 10000 + i, bookId, i, 'c', i.isEven ? 'ref $i' : null],
      );
      // כמה שורות לכל hash (התנגשות/מפתח חלקי), וספר 5 בלי שורות לחלק מה-hash-ים.
      final hash = (i * 7 + bookId) % _hashes - 6;
      if (bookId == 5 && hash > 0) continue;
      db.execute('INSERT INTO line_ref VALUES (?, ?, ?)', [bookId, hash, i]);
    }
    // שורת אינדקס בלי שורה ב-line — שתי הצורות חייבות להשמיט אותה.
    db.execute('INSERT INTO line_ref VALUES (?, 0, ?)', [
      bookId,
      _linesPerBook + 5,
    ]);
  }
  db.execute('COMMIT');
}

const _title = 'ישעיהו';
const _ref = 'ישעיהו לב, יא';

/// ספר 3 בשם אמיתי עם מפתחות line_ref אמיתיים, לפתרון מקצה לקצה.
void _buildRefsFixture(sqlite3.Database db) {
  _buildFixture(db);
  db.execute("UPDATE book SET title = '$_title' WHERE id = 3");
  for (final (lineIndex, heRef) in [(10, 'ישעיהו לב, י'), (11, _ref)]) {
    db.execute(
      'UPDATE line SET heRef = ? WHERE bookId = 3 AND lineIndex = ?',
      [heRef, lineIndex],
    );
    db.execute('INSERT OR IGNORE INTO line_ref VALUES (3, ?, ?)', [
      refKeyHash(buildLineRefKey(heRef, [_title])!),
      lineIndex,
    ]);
  }
}

List<String> _plan(sqlite3.Database db, String sql, List<Object?> params) => db
    .select('EXPLAIN QUERY PLAN $sql', params)
    .map((r) => r['detail'] as String)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;
  late String refsPath;

  setUpAll(() async {
    await QueryLoader.initialize();
    tempDir = await Directory.systemTemp.createTemp('line_ref_candidates');
    dbPath = path.join(tempDir.path, 'seforim.db');
    final db = sqlite3.sqlite3.open(dbPath);
    try {
      _buildFixture(db);
    } finally {
      db.close();
    }
    refsPath = path.join(tempDir.path, 'refs.db');
    final refs = sqlite3.sqlite3.open(refsPath);
    try {
      _buildRefsFixture(refs);
    } finally {
      refs.close();
    }
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  const bookSets = [
    [1],
    [5],
    [2, 4],
    [1, 2, 3, 4, 5],
    [5, 3, 1],
    [9],
  ];

  Future<List<LineRefCandidate>> viaDao(
    MyDatabase database,
    List<int> bookIds,
    int hash,
  ) async {
    return database.lineRefDao.candidatesForBooks(bookIds, hash);
  }

  Future<void> expectDaoParity() async {
    final official = MyDatabase.withPath(
      dbPath,
      readOnly: true,
      official: true,
    );
    final plain = MyDatabase.withPath(dbPath, readOnly: true);
    final attached = MyDatabase.untrusted(dbPath);
    try {
      var nonEmpty = 0;
      for (final ids in bookSets) {
        for (var hash = -7; hash < _hashes - 5; hash++) {
          final expected = await viaDao(plain, ids, hash);
          if (expected.isNotEmpty) nonEmpty++;
          expect(
            await viaDao(official, ids, hash),
            expected,
            reason: '$ids / $hash',
          );
          expect(await viaDao(attached, ids, hash), expected);
        }
      }
      expect(nonEmpty, greaterThan(20));
    } finally {
      official.close();
      plain.close();
      attached.close();
    }
  }

  test('מסד לא רשמי מקבל את שאילתת המועמדים המקורית בדיוק', () {
    for (final ids in bookSets) {
      expect(
        LineRefDao.candidatesSql(ids, official: false),
        _originalSql(ids.join(',')),
      );
    }
  });

  test(
    'המועמדים ב-seforim.db זהים לשאילתה המקורית, עם sqlite_stat1 ובלעדיה',
    () async {
      final db = sqlite3.sqlite3.open(dbPath);
      try {
        void expectSqlParity() {
          for (final ids in bookSets) {
            for (var hash = -7; hash < _hashes - 5; hash++) {
              expect(
                db.select(LineRefDao.candidatesSql(ids, official: true), [
                  hash,
                ]),
                db.select(_originalSql(ids.join(',')), [hash]),
                reason: '$ids / $hash',
              );
            }
          }
        }

        expectSqlParity();
        await expectDaoParity();
        db.execute('ANALYZE');
        expectSqlParity();
        await expectDaoParity();
      } finally {
        db.execute('DROP TABLE IF EXISTS sqlite_stat1');
        db.close();
      }
    },
  );

  test('ב-seforim.db התוכנית מתחילה ממפתח line_ref ולא משורות הספר', () {
    final db = sqlite3.sqlite3.open(dbPath);
    try {
      void expectKeyFirst() {
        for (final ids in [
          [1],
          [1, 2, 3, 4, 5],
        ]) {
          final plan = _plan(
            db,
            LineRefDao.candidatesSql(ids, official: true),
            [
              0,
            ],
          );
          expect(
            plan.first,
            contains('SEARCH lr USING PRIMARY KEY (bookId=? AND refKeyHash=?)'),
            reason: plan.join('\n'),
          );
          expect(
            plan[1],
            contains('idx_line_book_index (bookId=? AND lineIndex=?)'),
            reason: plan.join('\n'),
          );
        }
      }

      // בלי סטטיסטיקה השאילתה המקורית סורקת את כל שורות הספר — זה מה שנכפה.
      expect(
        _plan(db, _originalSql('1'), [0]).first,
        startsWith('SEARCH l USING INDEX idx_line_book_index (bookId=?)'),
      );
      expectKeyFirst();
      db.execute('ANALYZE');
      expectKeyFirst();
    } finally {
      db.execute('DROP TABLE IF EXISTS sqlite_stat1');
      db.close();
    }
  });

  group('יעד קישור חיצוני (_byRef)', () {
    String originalByRefSql(String ids) =>
        'SELECT lr.bookId, lr.lineIndex, l.heRef FROM line_ref lr '
        'JOIN line l ON l.bookId = lr.bookId AND l.lineIndex = lr.lineIndex '
        'WHERE lr.refKeyHash = ? AND lr.bookId IN ($ids) '
        'ORDER BY lr.bookId, lr.lineIndex';

    test('יעד מצורף מקבל את השאילתה המקורית; הרשמי זהה בתוצאות', () {
      final db = sqlite3.sqlite3.open(dbPath);
      try {
        for (final ids in bookSets) {
          expect(
            ExternalTargetResolver.refCandidatesSql(ids, official: false),
            originalByRefSql(ids.join(',')),
          );
          for (var hash = -7; hash < _hashes - 5; hash++) {
            expect(
              db.select(
                ExternalTargetResolver.refCandidatesSql(ids, official: true),
                [hash],
              ),
              db.select(originalByRefSql(ids.join(',')), [hash]),
              reason: '$ids / $hash',
            );
          }
        }
      } finally {
        db.close();
      }
    });

    test('ביעד הרשמי התוכנית מתחילה ממפתח line_ref', () {
      final db = sqlite3.sqlite3.open(dbPath);
      try {
        void expectKeyFirst() {
          final plan = _plan(
            db,
            ExternalTargetResolver.refCandidatesSql(_books, official: true),
            [0],
          );
          expect(
            plan.first,
            contains('SEARCH lr USING PRIMARY KEY (bookId=? AND refKeyHash=?)'),
            reason: plan.join('\n'),
          );
        }

        expectKeyFirst();
        db.execute('ANALYZE');
        expectKeyFirst();
      } finally {
        db.execute('DROP TABLE IF EXISTS sqlite_stat1');
        db.close();
      }
    });

    ExternalTargetDb target(
      String wireKey,
      String? slug, {
      required bool untrusted,
    }) => (
      wireKey: wireKey,
      slug: slug,
      target: (path: refsPath, untrusted: untrusted, immutable: false),
      version: '1',
    );

    String? sentSql(ExternalTargetDb db, String? source) {
      final resolver = ExternalTargetResolver([db]);
      try {
        final hit = resolver.resolve(
          targetSource: source,
          targetTitle: _title,
          targetRef: _ref,
          targetLineIndex: null,
        );
        expect(hit?.bookId, 3, reason: db.wireKey);
        expect(hit?.lineIndex, 11, reason: db.wireKey);
        return resolver.lastRefCandidatesSql;
      } finally {
        resolver.close();
      }
    }

    test('פתרון שורות רבות מכין כל שאילתה פעם אחת ובטרנזקציית קריאה', () {
      final resolver = ExternalTargetResolver([
        target('o', null, untrusted: false),
      ]);
      final writer = sqlite3.sqlite3.open(refsPath);
      try {
        for (var i = 0; i < 50; i++) {
          final byRef = resolver.resolve(
            targetSource: 'official',
            targetTitle: _title,
            targetRef: _ref,
            targetLineIndex: null,
          );
          expect(byRef?.lineIndex, 11);
          final byIndex = resolver.resolve(
            targetSource: 'official',
            targetTitle: _title,
            targetRef: null,
            targetLineIndex: 10,
          );
          expect(byIndex?.heRef, 'ישעיהו לב, י');
        }
        expect(resolver.preparedStatements, 2);
        // נעילת הקריאה מוחזקת בין שורות, ומשתחררת לפני המתנה.
        expect(() => writer.execute('BEGIN EXCLUSIVE'), throwsA(anything));
        resolver.releaseReads();
        writer.execute('BEGIN EXCLUSIVE');
        writer.execute('ROLLBACK');
      } finally {
        writer.close();
        resolver.close();
      }
    });

    test('רק יעד רשמי מהימן (slug null) מקבל את הנוסח הכפוי', () {
      expect(
        sentSql(target('o', null, untrusted: false), 'official'),
        ExternalTargetResolver.refCandidatesSql([3], official: true),
      );
      for (final (db, source) in [
        (target('d:x', 'x', untrusted: true), 'x'),
        (target('d:y', 'y', untrusted: false), 'y'),
        (target('o', null, untrusted: true), null),
      ]) {
        expect(
          sentSql(db, source),
          originalByRefSql('3'),
          reason: db.wireKey,
        );
      }
    });
  });

  test('seforim.db רשמי שולח את הנוסח הכפוי במסלול הקריאה של המאגר', () async {
    final key = buildLineRefKey(_ref, [_title])!;
    for (final official in [true, false]) {
      final database = MyDatabase.withPath(
        refsPath,
        readOnly: true,
        official: official,
      );
      final repo = SeforimRepository(database);
      try {
        final resolved = await repo.resolveRefKeyInBooks([3, 1], key);
        expect(resolved[3]?.lineIndex, 11);
        final expected = official
            ? LineRefDao.candidatesSql([3, 1], official: true)
            : _originalSql('3,1');
        expect(database.lineRefDao.lastCandidatesSql, expected);
        database.lineRefDao.lastCandidatesSql = null;
        await repo.resolvePartialRefKeyInBooks([3, 1], 'לב יא');
        expect(database.lineRefDao.lastCandidatesSql, expected);
      } finally {
        database.close();
      }
    }
  });
}
