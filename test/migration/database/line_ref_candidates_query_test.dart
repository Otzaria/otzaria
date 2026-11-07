import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
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

/// כותב כמו עדכון הספרייה: busy_timeout של 5 שניות ונעילה בלעדית.
Future<void> _writeExclusivelyInIsolate(String dbPath) => Isolate.run(() {
  final db = sqlite3.sqlite3.open(dbPath);
  try {
    db.execute('PRAGMA busy_timeout=5000');
    db.execute('BEGIN EXCLUSIVE');
    db.execute('COMMIT');
  } finally {
    db.close();
  }
});

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
    test('רק BUSY ו-LOCKED, כולל קודים מורחבים, הם נעילה זמנית', () {
      for (final code in [
        sqlite3.SqlError.SQLITE_BUSY,
        sqlite3.SqlExtendedError.SQLITE_BUSY_RECOVERY,
        sqlite3.SqlExtendedError.SQLITE_BUSY_SNAPSHOT,
        sqlite3.SqlExtendedError.SQLITE_BUSY_TIMEOUT,
        sqlite3.SqlError.SQLITE_LOCKED,
        sqlite3.SqlExtendedError.SQLITE_LOCKED_SHAREDCACHE,
        sqlite3.SqlExtendedError.SQLITE_LOCKED_VTAB,
      ]) {
        expect(
          isTransientExternalLinkLock(
            sqlite3.SqliteException(extendedResultCode: code, message: 'lock'),
          ),
          isTrue,
          reason: '$code',
        );
      }
      for (final code in [
        sqlite3.SqlError.SQLITE_ERROR,
        sqlite3.SqlError.SQLITE_CORRUPT,
        sqlite3.SqlError.SQLITE_CANTOPEN,
        sqlite3.SqlError.SQLITE_IOERR,
      ]) {
        expect(
          isTransientExternalLinkLock(
            sqlite3.SqliteException(extendedResultCode: code, message: 'bad'),
          ),
          isFalse,
          reason: '$code',
        );
      }
      expect(isTransientExternalLinkLock(StateError('locked')), isFalse);
    });

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
      ], readHold: const Duration(minutes: 1));
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

    test('שורת מקור פגומה משחררת קריאה שחרגה מתקציב הזמן', () {
      final sourcePath = path.join(tempDir.path, 'malformed_source.db');
      final source = sqlite3.sqlite3.open(sourcePath);
      try {
        source.execute('''
          CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT);
          CREATE TABLE external_link (sourceBookId INTEGER,
            sourceLineIndex INTEGER, targetTitle TEXT,
            targetSource TEXT, targetLineIndex INTEGER);
          INSERT INTO book VALUES (1, 'source');
        ''');
        for (final lineIndex in <Object>[0, 'invalid']) {
          source.execute('INSERT INTO external_link VALUES (1, ?, ?, ?, ?)', [
            lineIndex,
            _title,
            'official',
            10,
          ]);
        }
      } finally {
        source.close();
      }
      final writer = sqlite3.sqlite3.open(refsPath);
      try {
        var scanned = 0;
        final rows = readResolvedExternalLinks(
          source: (path: sourcePath, untrusted: true, immutable: false),
          sourceWireKey: 'd:source',
          targets: [target('o', null, untrusted: false)],
          onScanned: (_) {
            if (++scanned == 1) {
              expect(
                () => writer.execute('BEGIN EXCLUSIVE'),
                throwsA(predicate(isTransientExternalLinkLock)),
              );
              sleep(const Duration(milliseconds: 80));
            } else {
              writer.execute('BEGIN EXCLUSIVE');
              writer.execute('ROLLBACK');
            }
          },
        );
        expect(scanned, 2);
        expect(rows.single.targetLineIndex, 10);
      } finally {
        writer.close();
      }
    });

    test('כותב עם busy_timeout נכנס כשפתרון השורות איטי', () async {
      final resolver = ExternalTargetResolver([
        target('o', null, untrusted: false),
      ]);
      Future<int?> resolveSlowly() async {
        final hit = resolver.resolve(
          targetSource: 'official',
          targetTitle: _title,
          targetRef: _ref,
          targetLineIndex: null,
        );
        // עבודה איטית לכל שורה בזמן שנעילת הקריאה מוחזקת.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return hit?.lineIndex;
      }

      try {
        expect(await resolveSlowly(), 11);
        var writerDone = false;
        final writer = _writeExclusivelyInIsolate(
          refsPath,
        ).whenComplete(() => writerDone = true);
        final clock = Stopwatch()..start();
        while (!writerDone && clock.elapsed < const Duration(seconds: 10)) {
          expect(await resolveSlowly(), 11);
        }
        await writer;
      } finally {
        resolver.close();
      }
    });

    for (final missingColumn in ['id', 'title']) {
      test('שגיאת סכמה קבועה ב-$missingColumn נשמרת עד פותר חדש', () {
        final brokenPath = path.join(tempDir.path, 'missing_$missingColumn.db');
        final writer = sqlite3.sqlite3.open(brokenPath);
        writer.execute(
          missingColumn == 'id'
              ? 'CREATE TABLE book (bad INTEGER PRIMARY KEY, title TEXT)'
              : 'CREATE TABLE book (id INTEGER PRIMARY KEY, bad TEXT)',
        );
        writer.execute('INSERT INTO book VALUES (1, ?)', [_title]);
        final ExternalTargetDb brokenTarget = (
          wireKey: 'd:broken',
          slug: 'broken',
          target: (path: brokenPath, untrusted: true, immutable: false),
          version: '1',
        );
        final resolver = ExternalTargetResolver([brokenTarget]);
        ExternalTargetResolver? fresh;
        try {
          expect(AttachedLibraryProbe.probeSync(brokenPath).isOk, isTrue);
          expect(resolver.bookDatabase('broken', _title), isNull);
          resolver.releaseReads();
          writer.execute(
            'ALTER TABLE book RENAME COLUMN bad TO $missingColumn',
          );
          expect(resolver.bookDatabase('broken', _title), isNull);
          fresh = ExternalTargetResolver([brokenTarget]);
          expect(fresh.bookDatabase('broken', _title), isNotNull);
        } finally {
          fresh?.close();
          resolver.close();
          writer.close();
        }
      });
    }

    test('כותרת שנכשלה ב-BUSY אינה נשמרת כריקה', () {
      final resolver = ExternalTargetResolver([
        target('o', null, untrusted: false),
      ]);
      final writer = sqlite3.sqlite3.open(refsPath);
      try {
        // פותח את החיבור ליעד לפני הנעילה, כך שרק שאילתת הכותרת נכשלת.
        expect(resolver.bookDatabase('official', 'book 1'), isNotNull);
        resolver.releaseReads();
        writer.execute('BEGIN EXCLUSIVE');
        expect(
          () => resolver.resolve(
            targetSource: 'official',
            targetTitle: _title,
            targetRef: _ref,
            targetLineIndex: null,
          ),
          throwsA(predicate(isTransientExternalLinkLock)),
        );
        writer.execute('ROLLBACK');
        resolver.releaseReads();
        final hit = resolver.resolve(
          targetSource: 'official',
          targetTitle: _title,
          targetRef: _ref,
          targetLineIndex: null,
        );
        expect(hit?.lineIndex, 11);
      } finally {
        writer.close();
        resolver.close();
      }
    });

    test('BUSY בפתיחת מסד היעד אינו מפיל אותו עד סוף הבנייה', () {
      final resolver = ExternalTargetResolver([
        target('o', null, untrusted: false),
      ]);
      final writer = sqlite3.sqlite3.open(refsPath);
      try {
        writer.execute('BEGIN EXCLUSIVE');
        expect(
          () => resolver.bookDatabase('official', _title),
          throwsA(predicate(isTransientExternalLinkLock)),
        );
        writer.execute('ROLLBACK');
        final hit = resolver.resolve(
          targetSource: 'official',
          targetTitle: _title,
          targetRef: _ref,
          targetLineIndex: null,
        );
        expect(hit?.lineIndex, 11);
      } finally {
        writer.close();
        resolver.close();
      }
    });

    test('נעילה ביעד הראשון אינה מעבירה את הקישור למסד אחר', () {
      final otherPath = path.join(tempDir.path, 'other_target.db');
      File(refsPath).copySync(otherPath);
      final resolver = ExternalTargetResolver([
        target('o', null, untrusted: false),
        (
          wireKey: 'd:other',
          slug: 'other',
          target: (path: otherPath, untrusted: true, immutable: false),
          version: '1',
        ),
      ]);
      final writer = sqlite3.sqlite3.open(refsPath);
      try {
        writer.execute('BEGIN EXCLUSIVE');
        expect(
          () => resolver.resolve(
            targetSource: null,
            targetTitle: _title,
            targetRef: _ref,
            targetLineIndex: null,
          ),
          throwsA(predicate(isTransientExternalLinkLock)),
        );
        writer.execute('ROLLBACK');
        final hit = resolver.resolve(
          targetSource: null,
          targetTitle: _title,
          targetRef: _ref,
          targetLineIndex: null,
        );
        expect(hit?.target.wireKey, 'o');
        expect(hit?.lineIndex, 11);
      } finally {
        resolver.close();
        writer.close();
      }
    });

    test('שאילתות מוכנות מתאוששות מ-BUSY וסגירה משחררת את הנעילה', () {
      final resolver = ExternalTargetResolver([
        target('o', null, untrusted: false),
      ]);
      final writer = sqlite3.sqlite3.open(refsPath);
      int? resolve(bool byRef) => resolver
          .resolve(
            targetSource: 'official',
            targetTitle: _title,
            targetRef: byRef ? _ref : null,
            targetLineIndex: byRef ? null : 10,
          )
          ?.lineIndex;
      try {
        expect(resolve(true), 11);
        expect(resolve(false), 10);
        expect(resolver.preparedStatements, 2);
        resolver.releaseReads();
        writer.execute('BEGIN EXCLUSIVE');
        for (final byRef in [true, false]) {
          expect(
            () => resolve(byRef),
            throwsA(predicate(isTransientExternalLinkLock)),
          );
          resolver.releaseReads();
        }
        writer.execute('ROLLBACK');
        expect(resolve(true), 11);
        expect(resolve(false), 10);
        expect(resolver.preparedStatements, 2);
        resolver.close();
        writer.execute('BEGIN EXCLUSIVE');
        writer.execute('ROLLBACK');
      } finally {
        resolver.close();
        writer.close();
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
