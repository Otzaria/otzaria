import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:fake_async/fake_async.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/data_providers/book_text_reader.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/database/journal_mode.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/migration/models/book.dart' as db_models;
import 'package:otzaria/migration/models/category.dart' as db_models;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/search/library_line_source.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../support/fake_line_source_engine.dart';
import '../test_helpers/memory_cache_provider.dart';

void _failWorkerStartup() => throw StateError('worker startup failure');

void Function() _observeWorkerExit(
  SendPort onExit,
  void Function()? setUp,
) => () {
  Isolate.current.addOnExitListener(onExit);
  setUp?.call();
};

Future<int> Function() _pausedFallback(SendPort checkpoint) => () async {
  final release = ReceivePort();
  try {
    checkpoint.send(release.sendPort);
    await release.first;
    return 1;
  } finally {
    release.close();
  }
};

Future<String> Function() _pausedDbFallback(
  String dbPath,
  SendPort checkpoint,
) =>
    () => Isolate.run(() async {
      final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
      final release = ReceivePort();
      try {
        db.select('SELECT content FROM line LIMIT 1');
        checkpoint.send(release.sendPort);
        await release.first;
        return db.select('SELECT content FROM line LIMIT 1').first['content']
            as String;
      } finally {
        db.close();
        release.close();
      }
    });

/// ה-worker הקבוע חייב להחזיר בדיוק את מה שהמסלול הישיר מחזיר, לאגד בקשות
/// של אותו סבב, לשחרר את הקובץ בהשהיה ובסגירה, וליפול למסלול הישיר כשנתקע.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Future<String> seedDb(String name, {int bigBookLines = 0}) async {
    final dbPath = path.join(tempDir.path, '$name.db');
    final database = MyDatabase.withPath(dbPath);
    await SeforimRepository(database).ensureInitialized();
    final db = await database.database;
    db.execute("INSERT INTO category (id, title, level) VALUES (7, 'תנך', 0)");
    db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
    db.execute(
      'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
      "totalLines) VALUES (1, 7, 1, 'בראשית', 1, 5), "
      "(2, 7, 1, 'מפרש', 2, 3), (3, 7, 1, 'ספר גדול', 3, $bigBookLines)",
    );
    for (var i = 0; i < 5; i++) {
      db.execute(
        'INSERT INTO line (id, bookId, lineIndex, content, heRef) '
        'VALUES (?, 1, ?, ?, ?)',
        [100 + i, i, 'שורה $i', 'בראשית א, ${i + 1}'],
      );
    }
    for (var i = 0; i < 3; i++) {
      db.execute(
        'INSERT INTO line (id, bookId, lineIndex, content, heRef) '
        'VALUES (?, 2, ?, ?, ?)',
        [200 + i, i, 'פירוש $i', 'מפרש א, ${i + 1}'],
      );
    }
    if (bigBookLines > 0) {
      db.execute(
        'INSERT INTO line (id, bookId, lineIndex, content) '
        'WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n '
        'WHERE i < ?) SELECT 1000 + i, 3, i, printf(\'%0200d\', i) FROM n',
        [bigBookLines - 1],
      );
    }
    db.execute(
      "INSERT INTO tocText (id, text) VALUES (1, 'בראשית'), (2, 'פרק א')",
    );
    db.execute(
      'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineIndex) '
      'VALUES (1, 1, NULL, 1, 0, 0), (2, 1, 1, 2, 1, 1)',
    );
    db.execute('INSERT INTO line_toc (lineId, tocEntryId) VALUES (103, 2)');
    db.execute(
      'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, '
      'targetBookId, connectionTypeId) VALUES (1, 102, 200, 2, 5)',
    );
    database.close();
    // כמו ב-SqliteDataProvider: מסד WAL בלי -shm גורם לשני קוראי RO מקבילים
    // להתנגש ב-recovery (SQLITE_BUSY_RECOVERY).
    await normalizeJournalModeForReadOnly(dbPath);
    return dbPath;
  }

  void addCommentaryLink(String dbPath) {
    final db = sqlite3.sqlite3.open(dbPath);
    try {
      db.execute(
        "INSERT INTO connection_type (name) SELECT 'COMMENTARY' WHERE NOT "
        "EXISTS (SELECT 1 FROM connection_type WHERE name = 'COMMENTARY')",
      );
      db.execute(
        'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, '
        'targetBookId, connectionTypeId) SELECT 1, 101, 201, 2, id '
        "FROM connection_type WHERE name = 'COMMENTARY'",
      );
    } finally {
      db.close();
    }
  }

  Future<T> onDirectConnection<T>(
    String dbPath,
    Future<T> Function(SeforimRepository repo) body,
  ) async {
    final database = MyDatabase.withPath(dbPath, readOnly: true);
    try {
      return await body(SeforimRepository(database));
    } finally {
      database.close();
    }
  }

  Map<String, Object?> linkArgs(
    String dbPath,
    String title,
    int index2, [
    int? index2End,
  ]) => {
    'dbPath': dbPath,
    'title': title,
    'categoryId': 7,
    'index2': index2,
    'index2End': index2End,
  };

  Map<String, Object?> textRangeArgs(String dbPath, String title) => {
    'dbPath': dbPath,
    'title': title,
    'categoryId': 7,
    'fileType': 'txt',
    'startLine': 1,
    'endLine': 3,
    'versionTitle': null,
  };

  Future<({Future<Object?> result, SendPort release})> pausedBookRead(
    String dbPath,
  ) async {
    final checkpoint = ReceivePort();
    addTearDown(checkpoint.close);
    DbReadWorker.bookReadCheckpointPort = checkpoint.sendPort;
    final result = DbReadWorker.request('bookTextBytes', {
      'dbPath': dbPath,
      'bookId': 3,
      'title': 'ספר גדול',
    }).then<Object?>((value) => value, onError: (Object error) => error);
    return (result: result, release: await checkpoint.first as SendPort);
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_db_read_worker');
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(() async {
    DbReadWorker.stallTimeout = const Duration(seconds: 10);
    DbReadWorker.admissionTimeout = const Duration(seconds: 10);
    DbReadWorker.maxPendingWorkerReads = 64;
    DbReadWorker.maxPendingRequestBytes = 512 * 1024;
    await DbReadWorker.resumeAfterExternalWrite();
    DbReadWorker.disposeForTesting();
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // אחרי kill שחרור ה-handle ב-Windows אינו מיידי; ה-temp אינו הנבדק.
    }
  });

  test('תוכן קישור, נתיב כותרות ו-heRef מה-worker זהים למסלול הישיר', () async {
    final dbPath = await seedDb('seforim');

    final direct = await onDirectConnection(dbPath, (repo) async {
      return [
        await linkContentFromDbLines(repo, 2, 1, null),
        await linkContentFromDbLines(repo, 2, 1, 3),
        await linkContentFromDbLines(repo, 2, 99, null),
        await repo.getLineBreadcrumb(1, 3),
        await repo.getLineBreadcrumb(1, 0),
        await repo.getLineHeRef(1, 3),
      ];
    });
    expect(direct.take(3), [
      'פירוש 0',
      'פירוש 0<br>פירוש 1<br>פירוש 2',
      'שגיאה: אינדקס מחוץ לטווח',
    ]);

    final viaWorker = await Future.wait([
      DbReadWorker.batched('linkContent', linkArgs(dbPath, 'מפרש', 1)),
      DbReadWorker.batched('linkContent', linkArgs(dbPath, 'מפרש', 1, 3)),
      DbReadWorker.batched('linkContent', linkArgs(dbPath, 'מפרש', 99)),
      DbReadWorker.batched('breadcrumb', {
        'dbPath': dbPath,
        'bookId': 1,
        'lineIndex': 3,
      }),
      DbReadWorker.batched('breadcrumb', {
        'dbPath': dbPath,
        'bookId': 1,
        'lineIndex': 0,
      }),
      DbReadWorker.batched('heRef', {
        'dbPath': dbPath,
        'bookId': 1,
        'lineIndex': 3,
      }),
    ]);
    expect([
      for (final r in viaWorker.take(3)) (r! as Map)['content'],
      ...viaWorker.skip(3),
    ], direct);
  });

  test('מפרשי ספר מה-worker זהים לשאילתה הישירה', () async {
    final dbPath = await seedDb('seforim');
    addCommentaryLink(dbPath);
    final direct = await onDirectConnection(
      dbPath,
      (repo) => repo.database.linkDao.selectCommentatorsByBook(1),
    );
    expect([for (final row in direct) row['targetBookTitle']], ['מפרש']);

    expect(
      await DbReadWorker.request('commentatorsByBook', {
        'dbPath': dbPath,
        'bookId': 1,
      }),
      direct,
    );
  });

  test('קטלוג הספרים מה-worker זהה לשאילתה הישירה', () async {
    final dbPath = await seedDb('seforim');
    final direct = await onDirectConnection(
      dbPath,
      (repo) async => (
        books: await repo.getAllBooksLean(),
        categories: await repo.getAllCategories(),
      ),
    );
    expect(direct.books.map((b) => b.title), ['בראשית', 'מפרש', 'ספר גדול']);

    final viaWorker =
        await DbReadWorker.request('bookCatalog', {
              'dbPath': dbPath,
            })
            as ({
              List<db_models.Book> books,
              List<db_models.Category> categories,
            });
    expect(viaWorker.books, direct.books);
    expect(viaWorker.categories, direct.categories);
  });

  test('מפרשים נוספים על שורה מה-worker זהים לשאילתה הישירה', () async {
    final dbPath = await seedDb('seforim');
    addCommentaryLink(dbPath);
    final args = {
      'bookId': 1,
      'bookTitle': 'בראשית',
      'lineIndex': 2,
      'excludeBookId': -1,
    };
    final direct = await onDirectConnection(
      dbPath,
      (repo) => repo.getSiblingCommentaryLinkRowsForLine(
        bookId: 1,
        bookTitle: 'בראשית',
        lineIndex: 2,
        excludeBookId: -1,
      ),
    );
    expect([for (final row in direct) row['targetBookTitle']], ['מפרש']);

    expect(
      await DbReadWorker.request('siblingCommentaryRows', {
        ...args,
        'dbPath': dbPath,
      }),
      direct,
    );
  });

  for (final (lineIndex, expectedPlan) in [(2, 'range'), (0, 'book')]) {
    test(
      'fallback שומר את בחירת שאילתת הטווח של המסד הרשמי ($expectedPlan)',
      () async {
        final dbPath = await seedDb('seforim');
        addCommentaryLink(dbPath);
        final db = sqlite3.sqlite3.open(dbPath);
        try {
          db.execute("INSERT INTO tocText (id, text) VALUES (3, 'פרק ב')");
          db.execute(
            'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineIndex) '
            'VALUES (3, 1, 1, 3, 1, 4)',
          );
        } finally {
          db.close();
        }
        final originalQueries = QueryLoader.cacheSnapshot;
        final markedQueries = QueryLoader.cacheSnapshot;
        final links = markedQueries['LinkQueries.sq']!;
        for (final suffix in ['', 'Official']) {
          final name = 'selectCommentaryLinksByLineRange$suffix';
          // מזהים את ה-SQL שנבחר בלי לשנות את הסינון או למדוד זמן ריצה.
          links[name] = links[name]!.replaceFirst(
            'SELECT ',
            "SELECT '${suffix.isEmpty ? 'book' : 'range'}' AS queryPlan, ",
          );
        }
        QueryLoader.seedCache(markedQueries);
        try {
          final args = <String, Object?>{
            'dbPath': dbPath,
            'bookId': 1,
            'bookTitle': 'בראשית',
            'lineIndex': lineIndex,
            'excludeBookId': -1,
          };
          final workerRows =
              await DbReadWorker.request('siblingCommentaryRows', args) as List;
          expect(workerRows.single['queryPlan'], expectedPlan);
          expect(workerRows.single['targetBookTitle'], 'מפרש');

          DbReadWorker.stallTimeout = Duration.zero;
          final fallbackRows =
              await DbReadWorker.batched('siblingCommentaryRows', args) as List;
          expect(fallbackRows, workerRows);
        } finally {
          QueryLoader.seedCache(originalQueries);
        }
      },
    );
  }

  test('ספר שאינו ברשמי מוחזר למסלול הישיר ולא כשגיאה', () async {
    final dbPath = await seedDb('seforim');
    expect(
      await DbReadWorker.batched('linkContent', linkArgs(dbPath, 'אין', 1)),
      {'fallback': true},
    );
  });

  test('כשל ב-worker נרשם ב-errors.txt פעם אחת לכל סוג, עם stack', () async {
    final dbPath = await seedDb('seforim');
    AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data'));
    DbReadWorker.logFailuresInDebug = true;
    DbReadWorker.resetLoggedFailuresForTesting();
    addTearDown(() {
      DbReadWorker.logFailuresInDebug = false;
      DbReadWorker.resetLoggedFailuresForTesting();
      AppPaths.debugOverrideDataRootPath(null);
    });
    final badCommentators = {'dbPath': dbPath, 'bookId': 'x'};
    final badLink = {...linkArgs(dbPath, 'מפרש', 1), 'index2': 'x'};

    for (var i = 0; i < 2; i++) {
      await expectLater(
        DbReadWorker.request('commentatorsByBook', badCommentators),
        throwsStateError,
      );
      await expectLater(
        DbReadWorker.batched('linkContent', badLink),
        throwsStateError,
      );
    }

    final log = await ErrorLogFile.resolveFile().readAsString();
    expect('DB read worker failure'.allMatches(log), hasLength(2));
    expect(log, contains('Method: commentatorsByBook'));
    expect(log, contains('Connection: db_read_worker'));
    expect(log, contains('Method: linkContent'));
    expect(log, contains('Connection: one-shot isolate'));
    expect(log, contains('Database: $dbPath'));
    expect(log, contains('bookId=x'));
    expect('Stack:'.allMatches(log), hasLength(2));
  });

  test('פתיחה מחדש משמרת סימון פגימה', () async {
    final validPath = await seedDb('seforim');
    final corruptPath = await seedDb('corrupt');
    // דף הכותרת נשאר שלם, וכל שאר הדפים נדרסים.
    final bytes = File(corruptPath).readAsBytesSync();
    final pageSize = bytes[16] << 8 | bytes[17];
    bytes.fillRange(pageSize, bytes.length, 0xA5);
    File(corruptPath).writeAsBytesSync(bytes);
    addTearDown(() => DbReadWorker.corruptDatabaseDetected.value = false);

    await expectLater(
      DbReadWorker.request('commentatorsByBook', {
        'dbPath': validPath,
        'bookId': 'x',
      }),
      throwsStateError,
    );
    expect(DbReadWorker.corruptDatabaseDetected.value, isFalse);

    await expectLater(
      DbReadWorker.request('commentatorsByBook', {
        'dbPath': corruptPath,
        'bookId': 1,
      }),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('SqliteException(11)'),
        ),
      ),
    );
    expect(DbReadWorker.corruptDatabaseDetected.value, isTrue);

    await DbReadWorker.suspendForExternalWrite();
    await DbReadWorker.resumeAfterExternalWrite();
    expect(DbReadWorker.corruptDatabaseDetected.value, isTrue);
  });

  test('בקשות של אותו סבב נשלחות ל-worker כהודעה אחת', () async {
    final dbPath = await seedDb('seforim');
    // מעלה את ה-worker, כדי שה-spawn לא ייספר.
    await DbReadWorker.batched('linkContent', linkArgs(dbPath, 'מפרש', 1));

    final before = DbReadWorker.sentMessageCount;
    final results = await Future.wait([
      for (var i = 1; i <= 3; i++)
        DbReadWorker.batched('linkContent', linkArgs(dbPath, 'מפרש', i)),
    ]);
    expect(DbReadWorker.sentMessageCount - before, 1);
    expect(
      [for (final r in results) (r! as Map)['content']],
      ['פירוש 0', 'פירוש 1', 'פירוש 2'],
    );
  });

  test(
    'timeout של אצווה קורא תוכן, כותרת ו-heRef מחוץ ל-worker ומשחרר את הקובץ',
    () async {
      final dbPath = await seedDb('seforim');
      final expectedBreadcrumb = await onDirectConnection(
        dbPath,
        (repo) => repo.getLineBreadcrumb(1, 3),
      );
      final expectedHeRef = await onDirectConnection(
        dbPath,
        (repo) => repo.getLineHeRef(1, 3),
      );
      DbReadWorker.stallTimeout = Duration.zero;

      final results = await Future.wait([
        DbReadWorker.batched('linkContent', linkArgs(dbPath, 'מפרש', 2)),
        DbReadWorker.batched('breadcrumb', {
          'dbPath': dbPath,
          'bookId': 1,
          'lineIndex': 3,
        }),
        DbReadWorker.batched('heRef', {
          'dbPath': dbPath,
          'bookId': 1,
          'lineIndex': 3,
        }),
      ]);

      expect((results.first as Map)['content'], 'פירוש 1');
      expect(results[1], expectedBreadcrumb);
      expect(results.last, expectedHeRef);
      expect(await DbReadWorker.suspendForExternalWrite(), isTrue);
      await File(dbPath).delete();
    },
  );

  test('כשל בהחלפת מסד באצוות fallback אינו מזהם את הפריט הבא', () async {
    final dbPath = await seedDb('seforim');
    final missingPath = path.join(tempDir.path, 'missing.db');
    final results = await Future.wait([
      for (final targetPath in [dbPath, missingPath, dbPath])
        DbReadWorker.batched('heRef', {
          'dbPath': targetPath,
          'bookId': 1,
          'lineIndex': 3,
        }).then<Object?>((value) => value, onError: (Object error) => error),
    ]);

    expect(results.first, 'בראשית א, 4');
    expect(results[1], isA<StateError>());
    expect(results.last, 'בראשית א, 4');
    expect(await DbReadWorker.suspendForExternalWrite(), isTrue);
    await File(dbPath).delete();
  });

  test('טווחי טקסט וקישורים מה-worker זהים לפונקציה על חיבור חדש', () async {
    final dbPath = await seedDb('seforim');
    final linksArgs = {
      'dbPath': dbPath,
      'title': 'בראשית',
      'categoryId': 7,
      'fileType': 'txt',
      'startLineIndex': 0,
      'endLineIndex': 4,
      'targetBookTitles': null,
    };

    final direct = await onDirectConnection(dbPath, (repo) async {
      final db = await repo.database.database;
      final connection = (db: db, capabilities: DbCapabilities.probe(db));
      return (
        text: runRangeRequestOnConnection(
          'textRange',
          textRangeArgs(dbPath, 'בראשית'),
          connection,
        ),
        links: runRangeRequestOnConnection('linksRange', linksArgs, connection),
      );
    });

    final text =
        await DbReadWorker.request(
              'textRange',
              textRangeArgs(dbPath, 'בראשית'),
            )
            as ({
              int startLine,
              int endLine,
              int totalLines,
              List<String> lines,
            });
    final expected =
        direct.text!
            as ({
              int startLine,
              int endLine,
              int totalLines,
              List<String> lines,
            });
    expect(text.lines, ['שורה 1', 'שורה 2', 'שורה 3']);
    expect(text.lines, expected.lines);
    expect(
      (text.startLine, text.endLine, text.totalLines),
      (expected.startLine, expected.endLine, expected.totalLines),
    );

    final links = await DbReadWorker.request('linksRange', linksArgs);
    expect(links, hasLength(1));
    expect(links, direct.links);
  });

  test('טווח וקישור מתקדמים בזמן שקריאת ספר שלם ממתינה', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 4097);
    final full = await pausedBookRead(dbPath);
    var finished = false;
    final result = full.result.whenComplete(() => finished = true);
    try {
      expect(
        await DbReadWorker.request(
          'textRange',
          textRangeArgs(dbPath, 'בראשית'),
        ),
        isNotNull,
      );
      expect(
        await DbReadWorker.batched('linkContent', linkArgs(dbPath, 'מפרש', 2)),
        {'content': 'פירוש 1'},
      );
      expect(finished, isFalse);
    } finally {
      full.release.send(null);
    }
    expect(await result, isA<TransferableBookContent>());
  });

  test('dispose מסיים קריאת SQLite פעילה ו-worker חדש יכול לקרוא', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 4097);
    final exitPort = ReceivePort();
    final exits = StreamIterator<Object?>(exitPort);
    final previousSetUp = DbReadWorker.workerSetUpForTesting;
    final previousCheckpoint = DbReadWorker.bookReadCheckpointPort;
    addTearDown(() async {
      DbReadWorker.disposeForTesting();
      DbReadWorker.workerSetUpForTesting = previousSetUp;
      DbReadWorker.bookReadCheckpointPort = previousCheckpoint;
      await exits.cancel();
      exitPort.close();
    });
    DbReadWorker.workerSetUpForTesting = _observeWorkerExit(
      exitPort.sendPort,
      previousSetUp,
    );

    // המחסום מגיע מתוך קריאת הספר, אחרי פתיחת SQLite וקריאת 4096 שורות.
    // לא משחררים אותו: היציאה חייבת להגיע מה-dispose, ולא מסיום הקריאה.
    final full = await pausedBookRead(dbPath);
    expect(DbReadWorker.resourceUsage.pendingWorkerReads, 1);
    final stopped = exits.moveNext();
    DbReadWorker.disposeForTesting();

    expect(await full.result, isA<DbReadWorkerSuspended>());
    expect(await stopped, isTrue);
    expect(DbReadWorker.resourceUsage.liveWorkers, 0);
    expect(DbReadWorker.resourceUsage.pendingWorkerReads, 0);

    expect(
      await DbReadWorker.request('bookText', {
        'dbPath': dbPath,
        'bookId': 1,
        'title': 'בראשית',
      }),
      List.generate(5, (i) => 'שורה $i').join('\n'),
    );
    final restartedStopped = exits.moveNext();
    DbReadWorker.disposeForTesting();
    expect(await restartedStopped, isTrue);
  });

  test('תור worker מוגבל לפני שליחה ואינו מונע פקודת סגירה', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 4097);
    DbReadWorker.maxPendingWorkerReads = 3;
    final full = await pausedBookRead(dbPath);
    final queued = [
      for (var i = 0; i < 2; i++)
        DbReadWorker.request('bookText', {
          'dbPath': dbPath,
          'bookId': 1,
          'title': 'בראשית',
        }).then<Object?>((value) => value, onError: (Object error) => error),
    ];
    try {
      await expectLater(
        DbReadWorker.request('bookText', {
          'dbPath': dbPath,
          'bookId': 1,
          'title': 'בראשית',
        }),
        throwsA(isA<DbReadWorkerBusy>()),
      );
      expect(DbReadWorker.resourceUsage.pendingWorkerReads, 3);
      expect(DbReadWorker.resourceUsage.queuedReads, 2);
      expect(DbReadWorker.resourceUsage.estimatedQueuedBytes, greaterThan(0));
      final closing = DbReadWorker.closeConnectionIfRunning();
      full.release.send(null);
      await closing;
      expect(await full.result, isA<DbReadWorkerSuspended>());
      expect(
        await Future.wait(queued),
        everyElement(isA<DbReadWorkerSuspended>()),
      );
      expect(DbReadWorker.resourceUsage.pendingWorkerReads, 0);
      expect(DbReadWorker.resourceUsage.estimatedQueuedBytes, 0);
    } finally {
      full.release.send(null);
    }
  });

  test('תקרת בייטים נבדקת לפני מילוי תור ה-worker', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 4097);
    final full = await pausedBookRead(dbPath);
    DbReadWorker.maxPendingRequestBytes = 4096;
    final args = {
      'dbPath': dbPath,
      'bookId': 1,
      'title': 'בראשית',
      'padding': 'x' * 1000,
    };
    final queued = DbReadWorker.request(
      'bookText',
      args,
    ).then<Object?>((value) => value, onError: (Object error) => error);
    try {
      await expectLater(
        DbReadWorker.request('bookText', args),
        throwsA(isA<DbReadWorkerBusy>()),
      );
      expect(DbReadWorker.resourceUsage.pendingWorkerReads, 2);
      expect(
        DbReadWorker.resourceUsage.estimatedQueuedBytes,
        lessThanOrEqualTo(4096),
      );
    } finally {
      full.release.send(null);
    }
    expect(await full.result, isA<TransferableBookContent>());
    expect(await queued, List.generate(5, (i) => 'שורה $i').join('\n'));
  });

  test('פקודות פינוי חוזרות אינן נערמות אחרי timeout של פקודת בקרה', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 4097);
    final full = await pausedBookRead(dbPath);
    final previousTimeout = DbReadWorker.lifecycleCommandTimeout;
    DbReadWorker.lifecycleCommandTimeout = const Duration(milliseconds: 10);
    final before = DbReadWorker.sentMessageCount;
    try {
      int? firstCount;
      for (var i = 0; i < 4; i++) {
        expect(await DbReadWorker.shrinkMemoryIfRunning(), isFalse);
        DbReadWorker.clearBookCacheIfRunning();
        firstCount ??= DbReadWorker.sentMessageCount - before;
        expect(DbReadWorker.sentMessageCount - before, firstCount);
      }
      expect(firstCount, inInclusiveRange(1, 2));
    } finally {
      DbReadWorker.lifecycleCommandTimeout = previousTimeout;
      full.release.send(null);
    }
    expect(await full.result, isA<TransferableBookContent>());
    await DbReadWorker.cacheSizeForTesting(dbPath, books: true);
    expect(await DbReadWorker.shrinkMemoryIfRunning(), isTrue);
  });

  test(
    'lifecycle admission stays bounded and recovers the latest state',
    () async {
      final dbPath = await seedDb('seforim', bigBookLines: 4097);
      final full = await pausedBookRead(dbPath);
      final previousTimeout = DbReadWorker.lifecycleCommandTimeout;
      DbReadWorker.lifecycleCommandTimeout = const Duration(milliseconds: 10);
      final before = DbReadWorker.sentMessageCount;
      try {
        for (var i = 0; i < 20; i++) {
          await DbReadWorker.closeConnectionIfRunning(wait: false);
          DbReadWorker.allowReopen();
        }
        expect(
          DbReadWorker.sentMessageCount - before,
          lessThanOrEqualTo(4),
          reason:
              'DB_LIFECYCLE_CONTROL_BOUND: a held worker must retain at most '
              'four sent lifecycle commands.',
        );
        await expectLater(
          DbReadWorker.closeConnectionIfRunning(),
          throwsA(isA<DbReadWorkerBusy>()),
        );
        expect(await DbReadWorker.suspendForExternalWrite(), isFalse);
        await DbReadWorker.resumeAfterExternalWrite();
        DbReadWorker.allowReopen();
        final reading = DbReadWorker.request('bookText', {
          'dbPath': dbPath,
          'bookId': 1,
          'title': 'בראשית',
        });
        full.release.send(null);
        expect(await full.result, isA<DbReadWorkerSuspended>());
        expect(await reading, List.generate(5, (i) => 'שורה $i').join('\n'));
        expect(DbReadWorker.resourceUsage.pendingWorkerReads, 0);
      } finally {
        DbReadWorker.lifecycleCommandTimeout = previousTimeout;
        full.release.send(null);
        await full.result;
      }
    },
  );

  test('repeated lifecycle recovery waits share their timeout', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 4097);
    final full = await pausedBookRead(dbPath);
    final previousTimeout = DbReadWorker.lifecycleCommandTimeout;
    const controlTimeout = Duration(milliseconds: 37);
    DbReadWorker.lifecycleCommandTimeout = controlTimeout;
    final clock = FakeAsync();
    final timerZone = clock.run((_) => Zone.current);
    final waits = <Future<void>>[];
    Future<void> resume() => runZoned(
      DbReadWorker.resumeAfterExternalWrite,
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) =>
            duration == controlTimeout
            ? timerZone.createTimer(duration, callback)
            : parent.createTimer(zone, duration, callback),
      ),
    );
    try {
      for (var i = 0; i < 4; i++) {
        DbReadWorker.allowReopen();
      }
      for (var i = 0; i < 20; i++) {
        waits.add(resume());
      }
      expect(clock.nonPeriodicTimerCount, 1);
      clock.elapse(controlTimeout);
      await Future.wait(waits);
      waits.clear();
      for (var i = 0; i < 20; i++) {
        waits.add(resume());
      }
      await Future.wait(waits);
      expect(clock.nonPeriodicTimerCount, 0);
      full.release.send(null);
      expect(await full.result, isA<TransferableBookContent>());
      expect(
        await DbReadWorker.request('bookText', {
          'dbPath': dbPath,
          'bookId': 1,
          'title': 'בראשית',
        }),
        isNotNull,
      );
    } finally {
      clock.elapse(controlTimeout);
      DbReadWorker.lifecycleCommandTimeout = previousTimeout;
      full.release.send(null);
      await Future.wait(waits);
      await full.result;
    }
  });

  test('fallback drain waits stay bounded and recover after timeout', () async {
    final previousTimeout = DbReadWorker.lifecycleCommandTimeout;
    const controlTimeout = Duration(milliseconds: 43);
    DbReadWorker.lifecycleCommandTimeout = controlTimeout;
    final clock = FakeAsync();
    final timerZone = clock.run((_) => Zone.current);
    final releases = List.generate(3, (_) => Completer<void>());
    final reads = <Future<Object?>>[];
    Future<void> startRead(int index) async {
      reads.add(
        DbReadWorker.trackTemporaryRead(
          () => releases[index].future,
        ).then<Object?>((_) => null, onError: (Object error) => error),
      );
      await Future<void>.delayed(Duration.zero);
    }

    Future<bool> drain() => runZoned(
      DbReadWorker.suspendForExternalWrite,
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) =>
            duration == controlTimeout
            ? timerZone.createTimer(duration, callback)
            : parent.createTimer(zone, duration, callback),
      ),
    );
    try {
      await startRead(0);
      final waiting = [for (var i = 0; i < 20; i++) drain()];
      expect(clock.nonPeriodicTimerCount, 1);
      clock.elapse(controlTimeout);
      expect(await Future.wait(waiting), everyElement(isFalse));
      expect(clock.nonPeriodicTimerCount, 0);

      await DbReadWorker.resumeAfterExternalWrite();
      await startRead(1);
      DbReadWorker.disposeForTesting();
      expect(DbReadWorker.resourceUsage.activeFallbackReads, 2);
      releases[0].complete();
      await reads[0];
      expect(DbReadWorker.resourceUsage.activeFallbackReads, 1);
      final waitingAgain = [for (var i = 0; i < 20; i++) drain()];
      expect(clock.nonPeriodicTimerCount, 1);
      var completed = false;
      waitingAgain.first.then((_) => completed = true).ignore();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      releases[1].complete();
      await reads[1];
      expect(await Future.wait(waitingAgain), everyElement(isTrue));
      expect(clock.nonPeriodicTimerCount, 0);
      expect(DbReadWorker.resourceUsage.activeFallbackReads, 0);
      await DbReadWorker.resumeAfterExternalWrite();
      await startRead(2);
      final recovered = drain();
      expect(clock.nonPeriodicTimerCount, 1);
      releases[2].complete();
      await reads[2];
      expect(await recovered, isTrue);
      expect(clock.nonPeriodicTimerCount, 0);
    } finally {
      clock.elapse(controlTimeout);
      DbReadWorker.lifecycleCommandTimeout = previousTimeout;
      for (final release in releases) {
        if (!release.isCompleted) release.complete();
      }
      await Future.wait(reads);
    }
  });

  test('lifecycle admission preserves close open close ordering', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 4097);
    final full = await pausedBookRead(dbPath);
    try {
      await DbReadWorker.closeConnectionIfRunning(wait: false);
      DbReadWorker.allowReopen();
      final closing = DbReadWorker.closeConnectionIfRunning();
      full.release.send(null);
      await closing;
      expect(await full.result, isA<DbReadWorkerSuspended>());
      await expectLater(
        DbReadWorker.cacheSizeForTesting(dbPath, books: true),
        throwsA(isA<DbReadWorkerSuspended>()),
      );
      DbReadWorker.allowReopen();
      expect(
        await DbReadWorker.request('bookText', {
          'dbPath': dbPath,
          'bookId': 1,
          'title': 'בראשית',
        }),
        List.generate(5, (i) => 'שורה $i').join('\n'),
      );
    } finally {
      full.release.send(null);
      await full.result;
    }
  });

  test(
    'lifecycle recovery waiters are released when the worker exits',
    () async {
      final dbPath = await seedDb('seforim', bigBookLines: 4097);
      final full = await pausedBookRead(dbPath);
      try {
        for (var i = 0; i < 4; i++) {
          await DbReadWorker.closeConnectionIfRunning(wait: false);
          DbReadWorker.allowReopen();
        }
        final resuming = DbReadWorker.resumeAfterExternalWrite();
        final reading = DbReadWorker.request('bookText', {
          'dbPath': dbPath,
          'bookId': 1,
          'title': 'בראשית',
        }).then<Object?>((value) => value, onError: (Object error) => error);
        await Future<void>.delayed(Duration.zero);
        DbReadWorker.disposeForTesting();
        await resuming.timeout(const Duration(seconds: 1));
        expect(await reading, isA<DbReadWorkerSuspended>());
        expect(await full.result, isA<DbReadWorkerSuspended>());
        expect(
          await DbReadWorker.request('bookText', {
            'dbPath': dbPath,
            'bookId': 1,
            'title': 'בראשית',
          }),
          List.generate(5, (i) => 'שורה $i').join('\n'),
        );
      } finally {
        full.release.send(null);
        await full.result;
      }
    },
  );

  test(
    'overflow close open close leaves the worker connection closed',
    () async {
      final dbPath = await seedDb('seforim', bigBookLines: 4097);
      final full = await pausedBookRead(dbPath);
      try {
        for (var i = 0; i < 4; i++) {
          DbReadWorker.allowReopen();
        }
        await DbReadWorker.closeConnectionIfRunning(wait: false);
        DbReadWorker.allowReopen();
        await DbReadWorker.closeConnectionIfRunning(wait: false);
        full.release.send(null);
        expect(await full.result, isA<DbReadWorkerSuspended>());
        for (var i = 0; i < 100 && DbReadWorker.hasPendingReads; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(DbReadWorker.hasPendingReads, isFalse);
        await expectLater(
          DbReadWorker.cacheSizeForTesting(dbPath, books: true),
          throwsA(isA<DbReadWorkerSuspended>()),
        );
        DbReadWorker.allowReopen();
        expect(
          await DbReadWorker.request('bookText', {
            'dbPath': dbPath,
            'bookId': 1,
            'title': 'בראשית',
          }),
          isNotNull,
        );
      } finally {
        full.release.send(null);
        await full.result;
      }
    },
  );

  test(
    'overflow close open closes the old connection before recovery',
    () async {
      final dbPath = await seedDb('seforim', bigBookLines: 4097);
      final full = await pausedBookRead(dbPath);
      try {
        for (var i = 0; i < 4; i++) {
          DbReadWorker.allowReopen();
        }
        await DbReadWorker.closeConnectionIfRunning(wait: false);
        DbReadWorker.allowReopen();
        final resuming = DbReadWorker.resumeAfterExternalWrite();
        full.release.send(null);
        await resuming;
        expect(await full.result, isA<DbReadWorkerSuspended>());
        // רק open/resume התקבלו לפני ההצפה; ההתאוששות חייבת לסגור בעצמה.
        expect(await DbReadWorker.shrinkMemoryIfRunning(), isFalse);
        expect(
          await DbReadWorker.request('bookText', {
            'dbPath': dbPath,
            'bookId': 1,
            'title': 'בראשית',
          }),
          isNotNull,
        );
      } finally {
        full.release.send(null);
        await full.result;
      }
    },
  );

  test('אצווה גדולה מפוצלת להודעות מוגבלות ושומרת את כל התוצאות', () async {
    final dbPath = await seedDb('seforim');
    await DbReadWorker.batched('heRef', {
      'dbPath': dbPath,
      'bookId': 1,
      'lineIndex': 1,
    });
    final before = DbReadWorker.sentMessageCount;
    final results = await Future.wait([
      for (var i = 0; i < 130; i++)
        DbReadWorker.batched('heRef', {
          'dbPath': dbPath,
          'bookId': 1,
          'lineIndex': i % 5,
        }),
    ]);
    expect(results, List.generate(130, (i) => 'בראשית א, ${i % 5 + 1}'));
    expect(DbReadWorker.sentMessageCount - before, 3);
  });

  test('השהיה קוטעת ספר שלם וסוגרת את שני החיבורים לפני החלפת DB', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 4097);
    await DbReadWorker.request('textRange', textRangeArgs(dbPath, 'בראשית'));
    final full = await pausedBookRead(dbPath);
    final suspending = DbReadWorker.suspendForExternalWrite();
    full.release.send(null);
    expect(await suspending, isTrue);
    expect(await full.result, isA<DbReadWorkerSuspended>());
    for (final method in ['textRange', 'bookText']) {
      await expectLater(
        DbReadWorker.request(method, {'dbPath': dbPath}),
        throwsA(isA<DbReadWorkerSuspended>()),
      );
    }

    await File(dbPath).rename('$dbPath.old');
    final replacement = await seedDb('replacement');
    final database = MyDatabase.withPath(replacement);
    (await database.database).execute(
      "UPDATE line SET content = 'replacement' WHERE bookId = 1",
    );
    database.close();
    await File(replacement).rename(dbPath);
    await DbReadWorker.resumeAfterExternalWrite();
    expect(
      await DbReadWorker.request('bookText', {
        'dbPath': dbPath,
        'bookId': 1,
        'title': 'בראשית',
      }),
      List.filled(5, 'replacement').join('\n'),
    );
    final range =
        await DbReadWorker.request(
              'textRange',
              textRangeArgs(dbPath, 'בראשית'),
            )
            as ({
              int startLine,
              int endLine,
              int totalLines,
              List<String> lines,
            });
    expect(range.lines, List.filled(3, 'replacement'));
    await DbReadWorker.closeConnectionIfRunning();
    await File(dbPath).delete();
  });

  test('סגירה ופתיחה מחדש דוחות timeout ישן של ספר בלי fallback', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 4097);
    const readTimeout = Duration(milliseconds: 50);
    DbReadWorker.stallTimeout = readTimeout;
    final clock = FakeAsync();
    final timerZone = clock.run((_) => Zone.current);
    final full = await runZoned(
      () => pausedBookRead(dbPath),
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) =>
            duration == readTimeout
            ? timerZone.createTimer(duration, callback)
            : parent.createTimer(zone, duration, callback),
      ),
    );
    try {
      expect(clock.nonPeriodicTimerCount, 1);
      await DbReadWorker.closeConnectionIfRunning(wait: false);
      DbReadWorker.allowReopen();
      // הקריאה והמחסום נשארים אמיתיים; רק ה-timeout הישן מופעל אחרי הסגירה.
      clock.elapse(readTimeout);
      expect(await full.result, isA<DbReadWorkerSuspended>());
    } finally {
      DbReadWorker.stallTimeout = const Duration(seconds: 10);
      full.release.send(null);
    }
    expect(
      await DbReadWorker.request('bookText', {
        'dbPath': dbPath,
        'bookId': 1,
        'title': 'בראשית',
      }),
      List.generate(5, (i) => 'שורה $i').join('\n'),
    );
  });

  test(
    'סגירה בזמן spawn של שני ה-workers דוחה בקשות גם אחרי פתיחה מחדש',
    () async {
      final dbPath = await seedDb('seforim');
      final pending =
          [
                DbReadWorker.request(
                  'textRange',
                  textRangeArgs(dbPath, 'בראשית'),
                ),
                DbReadWorker.request('bookText', {
                  'dbPath': dbPath,
                  'bookId': 1,
                  'title': 'בראשית',
                }),
              ]
              .map(
                (read) =>
                    read.then<Object?>((v) => v, onError: (Object e) => e),
              )
              .toList();
      await DbReadWorker.closeConnectionIfRunning();
      DbReadWorker.allowReopen();
      expect(
        await Future.wait(pending),
        everyElement(isA<DbReadWorkerSuspended>()),
      );
      expect(
        await DbReadWorker.request('bookText', {
          'dbPath': dbPath,
          'bookId': 1,
          'title': 'בראשית',
        }),
        isNotNull,
      );
    },
  );

  test('dispose בזמן spawn אינו משאיר worker ישן פתוח', () async {
    final dbPath = await seedDb('seforim');
    final first = DbReadWorker.request('bookText', {
      'dbPath': dbPath,
      'bookId': 1,
      'title': 'בראשית',
    }).then<Object?>((v) => v, onError: (Object e) => e);
    DbReadWorker.disposeForTesting();
    expect(await first, isA<DbReadWorkerSuspended>());
    expect(
      await DbReadWorker.request('bookText', {
        'dbPath': dbPath,
        'bookId': 1,
        'title': 'בראשית',
      }),
      isNotNull,
    );
    expect(await DbReadWorker.suspendForExternalWrite(), isTrue);
    await File(dbPath).delete();
  });

  test('fallback שהסתיים אחרי סגירה ופתיחה מחדש אינו מחזיר תוכן ישן', () async {
    final checkpoint = ReceivePort();
    addTearDown(checkpoint.close);
    final read = DbReadWorker.runOnFreshIsolate(
      _pausedFallback(checkpoint.sendPort),
    ).then<Object?>((v) => v, onError: (Object e) => e);
    final release = await checkpoint.first as SendPort;
    await DbReadWorker.closeConnectionIfRunning(wait: false);
    DbReadWorker.allowReopen();
    release.send(null);
    expect(await read, isA<DbReadWorkerSuspended>());
  });

  Future<int> expectAtMostTwoFallbacks(int count) async {
    var running = 0;
    var maxRunning = 0;
    final gates = <Completer<void>>[];
    final reads = [
      for (var i = 0; i < count; i++)
        DbReadWorker.trackFallbackRead(() async {
          running++;
          maxRunning = running > maxRunning ? running : maxRunning;
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
          running--;
          return i;
        }),
    ];
    for (var released = 0; released < count; released++) {
      await pumpEventQueue();
      expect(gates.length, released + (count - released).clamp(0, 2));
      gates[released].complete();
    }
    expect(await Future.wait(reads), List.generate(count, (i) => i));
    return maxRunning;
  }

  test('קריאות fallback במקביל רצות לכל היותר שתיים יחד (#4017)', () async {
    expect(await expectAtMostTwoFallbacks(5), 2);
  });

  test('קריאת קטלוג חד-פעמית ממתינה בתור וחוזרת אחרי שחרור חיבור', () async {
    final gates = [Completer<void>(), Completer<void>()];
    final active = [
      for (final gate in gates)
        DbReadWorker.trackFallbackRead(() => gate.future),
    ];
    addTearDown(() async {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
      await Future.wait(active);
    });
    final catalog = DbReadWorker.runOnFreshIsolate(() => 7);
    await pumpEventQueue();
    expect(DbReadWorker.resourceUsage.activeFallbackReads, 2);
    expect(DbReadWorker.resourceUsage.queuedReads, 1);
    gates.first.complete();
    expect(await catalog, 7);
    expect(DbReadWorker.resourceUsage.queuedReads, 0);
  });

  test('השהיה מכשילה מיד fallback שבתור, גם כשהפעילות תקועות', () async {
    final gates = [Completer<void>(), Completer<void>()];
    final active = [
      for (final gate in gates)
        DbReadWorker.trackFallbackRead(
          () => gate.future,
        ).then<Object?>((v) => v, onError: (Object e) => e),
    ];
    var queuedStarted = false;
    final queued = DbReadWorker.trackFallbackRead(() async {
      queuedStarted = true;
    }).then<Object?>((v) => v, onError: (Object e) => e);
    await pumpEventQueue();
    final suspending = DbReadWorker.suspendForExternalWrite();
    expect(
      await queued.timeout(const Duration(milliseconds: 200)),
      isA<DbReadWorkerSuspended>(),
    );
    expect(queuedStarted, isFalse);
    for (final gate in gates) {
      gate.complete();
    }
    expect(await suspending, isTrue);
    expect(
      await Future.wait(active),
      everyElement(isA<DbReadWorkerSuspended>()),
    );
  });

  test('fallback תקוע שומר מקום עד סיום הקריאה ולא עד timeout', () async {
    DbReadWorker.stallTimeout = const Duration(milliseconds: 5);
    DbReadWorker.admissionTimeout = const Duration(milliseconds: 30);
    final gates = [Completer<void>(), Completer<void>()];
    final active = <Future<void>>[];
    for (final gate in gates) {
      active.add(DbReadWorker.trackFallbackRead(() => gate.future));
    }
    var queuedStarted = false;
    try {
      await expectLater(
        DbReadWorker.trackFallbackRead(() async {
          queuedStarted = true;
        }),
        throwsA(isA<DbReadWorkerBusy>()),
      );
      expect(queuedStarted, isFalse);
      expect(DbReadWorker.resourceUsage.activeFallbackReads, 2);
      expect(DbReadWorker.resourceUsage.queuedReads, 0);
    } finally {
      for (final gate in gates) {
        gate.complete();
      }
      await Future.wait(active);
    }
    DbReadWorker.admissionTimeout = const Duration(seconds: 10);
    expect(await expectAtMostTwoFallbacks(4), 2);
  });

  test('השהיה ממתינה לחיבור RO של fallback טווח רשמי', () async {
    final dbPath = await seedDb('seforim');
    final checkpoint = ReceivePort();
    addTearDown(checkpoint.close);
    DbReadWorker.workerSetUpForTesting = _failWorkerStartup;
    addTearDown(() => DbReadWorker.workerSetUpForTesting = null);
    final read = DatabaseLibraryProvider.loadOnReadWorkerForTesting(
      trustedDbTarget(dbPath),
      'textRange',
      textRangeArgs(dbPath, 'בראשית'),
      _pausedDbFallback(dbPath, checkpoint.sendPort),
    ).then<Object?>((v) => v, onError: (Object e) => e);
    final release = await checkpoint.first as SendPort;
    final suspending = DbReadWorker.suspendForExternalWrite();
    try {
      await expectLater(
        suspending.timeout(const Duration(milliseconds: 30)),
        throwsA(isA<TimeoutException>()),
      );
    } finally {
      release.send(null);
    }
    expect(await suspending, isTrue);
    expect(await read, isA<DbReadWorkerSuspended>());
    await File(dbPath).delete();
  });

  test(
    'השהיה משחררת את הקובץ ודוחה בקשות; השחרור נפתח על הנתיב החדש',
    () async {
      final first = await seedDb('seforim');
      expect(
        await DbReadWorker.request('textRange', textRangeArgs(first, 'בראשית')),
        isNotNull,
      );

      expect(await DbReadWorker.suspendForExternalWrite(), isTrue);
      // ב-Windows מחיקה עם handle פתוח נכשלת — זו ההוכחה לשחרור.
      await File(first).delete();

      await expectLater(
        DbReadWorker.batched('linkContent', linkArgs(first, 'מפרש', 1)),
        throwsA(isA<DbReadWorkerSuspended>()),
      );
      await expectLater(
        DbReadWorker.request('textRange', textRangeArgs(first, 'בראשית')),
        throwsA(isA<DbReadWorkerSuspended>()),
      );

      final second = await seedDb('replacement');
      await DbReadWorker.resumeAfterExternalWrite();
      final after =
          await DbReadWorker.batched(
                'linkContent',
                linkArgs(second, 'מפרש', 2),
              )
              as Map;
      expect(after['content'], 'פירוש 1');
    },
  );

  test('סגירת החיבור הראשי סוגרת גם את חיבור ה-worker', () async {
    final dbPath = await seedDb('seforim');
    await DbReadWorker.request('textRange', textRangeArgs(dbPath, 'בראשית'));

    await DbReadWorker.closeConnectionIfRunning();
    await File(dbPath).delete();
  });

  test('shrinkMemory רץ על חיבור ה-worker ולא פותח חיבור סגור', () async {
    final dbPath = await seedDb('seforim');
    final sentBefore = DbReadWorker.sentMessageCount;
    expect(await DbReadWorker.shrinkMemoryIfRunning(), isFalse);
    expect(
      DbReadWorker.sentMessageCount,
      sentBefore,
      reason: 'לא מפעיל worker',
    );

    await DbReadWorker.request('textRange', textRangeArgs(dbPath, 'בראשית'));
    expect(await DbReadWorker.shrinkMemoryIfRunning(), isTrue);

    await DbReadWorker.closeConnectionIfRunning();
    expect(await DbReadWorker.shrinkMemoryIfRunning(), isFalse);
    await File(dbPath).delete();
    DbReadWorker.allowReopen();
  });

  test('shrinkMemory רץ גם על worker הספרים השלמים', () async {
    final dbPath = await seedDb('seforim');
    await DbReadWorker.request('bookText', {
      'dbPath': dbPath,
      'bookId': 1,
      'title': 'בראשית',
    });
    expect(await DbReadWorker.shrinkMemoryIfRunning(), isTrue);

    await DbReadWorker.closeConnectionIfRunning();
    await File(dbPath).delete();
    DbReadWorker.allowReopen();
  });

  test('worker שלא עונה בזמן נרשם ב-errors.txt (issue #3325)', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 200000);
    await DbReadWorker.request('textRange', textRangeArgs(dbPath, 'בראשית'));
    AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data'));
    DbReadWorker.logFailuresInDebug = true;
    DbReadWorker.resetLoggedFailuresForTesting();
    addTearDown(() {
      DbReadWorker.logFailuresInDebug = false;
      DbReadWorker.resetLoggedFailuresForTesting();
      AppPaths.debugOverrideDataRootPath(null);
    });

    DbReadWorker.stallTimeout = Duration.zero;
    await expectLater(
      DbReadWorker.request('textRange', {
        ...textRangeArgs(dbPath, 'ספר גדול'),
        'startLine': 0,
        'endLine': 199999,
      }),
      throwsA(isA<DbReadWorkerUnavailable>()),
    );

    final file = ErrorLogFile.resolveFile();
    var log = '';
    for (var i = 0; i < 100 && !log.contains('stalled'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (file.existsSync()) log = file.readAsStringSync();
    }
    expect(log, contains('DB read worker stalled'));
    expect(log, contains('Method: textRange'));
    expect(log, contains('endLine=199999'));
    expect(log, isNot(contains(dbPath)));
  });

  test('worker שלא עונה בזמן נופל למסלול הישיר עד שיענה', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 200000);
    // חיבור פתוח מראש — כדי שהבקשה האיטית תהיה השאילתה עצמה.
    await DbReadWorker.request('textRange', textRangeArgs(dbPath, 'בראשית'));

    DbReadWorker.stallTimeout = Duration.zero;
    final slowArgs = {
      ...textRangeArgs(dbPath, 'ספר גדול'),
      'startLine': 0,
      'endLine': 199999,
    };
    await expectLater(
      DbReadWorker.request('textRange', slowArgs),
      throwsA(isA<DbReadWorkerUnavailable>()),
    );
    // בזמן התקיעה בקשה חדשה אינה נכנסת לתור — היא נופלת מיד.
    await expectLater(
      DbReadWorker.request('textRange', textRangeArgs(dbPath, 'בראשית')),
      throwsA(isA<DbReadWorkerUnavailable>()),
    );

    DbReadWorker.stallTimeout = const Duration(seconds: 10);
    Object? recovered;
    for (var i = 0; i < 100 && recovered == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      try {
        recovered = await DbReadWorker.request(
          'textRange',
          textRangeArgs(dbPath, 'בראשית'),
        );
      } on DbReadWorkerUnavailable {
        // עדיין תקוע.
      }
    }
    expect(recovered, isNotNull);
  });

  Map<String, Object?> slowTextArgs(String dbPath) => {
    ...textRangeArgs(dbPath, 'ספר גדול'),
    'startLine': 0,
    'endLine': 199999,
  };

  test('suspend jumps ahead of queued requests and fails them', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 200000);
    await DbReadWorker.request('textRange', textRangeArgs(dbPath, 'בראשית'));

    final queued = [
      for (var i = 0; i < 6; i++)
        DbReadWorker.request(
          'textRange',
          slowTextArgs(dbPath),
        ).then<Object?>((result) => result, onError: (Object e) => e),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(await DbReadWorker.suspendForExternalWrite(), isTrue);

    final results = await Future.wait(queued);
    expect(
      results.whereType<DbReadWorkerSuspended>().length,
      greaterThanOrEqualTo(5),
    );
  });

  test('a stalled worker never bypasses a suspension', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 200000);
    await DbReadWorker.request('textRange', textRangeArgs(dbPath, 'בראשית'));

    DbReadWorker.stallTimeout = Duration.zero;
    await expectLater(
      DbReadWorker.request('textRange', slowTextArgs(dbPath)),
      throwsA(isA<DbReadWorkerUnavailable>()),
    );
    DbReadWorker.stallTimeout = const Duration(seconds: 10);

    final suspending = DbReadWorker.suspendForExternalWrite();
    await expectLater(
      DbReadWorker.request('textRange', textRangeArgs(dbPath, 'בראשית')),
      throwsA(isA<DbReadWorkerSuspended>()),
    );
    await suspending;
  });

  test('closing without waiting does not block on a busy worker', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 200000);
    await DbReadWorker.request('textRange', textRangeArgs(dbPath, 'בראשית'));

    var slowDone = false;
    final slow = DbReadWorker.request(
      'textRange',
      slowTextArgs(dbPath),
    ).whenComplete(() => slowDone = true);
    await Future<void>.delayed(Duration.zero);
    await DbReadWorker.closeConnectionIfRunning(wait: false);
    expect(slowDone, isFalse);
    await slow.then<Object?>((result) => result, onError: (Object e) => e);
  });

  test('close fails queued requests and never reopens until allowed', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 200000);
    await DbReadWorker.request('textRange', textRangeArgs(dbPath, 'בראשית'));

    final queued = [
      for (var i = 0; i < 6; i++)
        DbReadWorker.request(
          'textRange',
          slowTextArgs(dbPath),
        ).then<Object?>((result) => result, onError: (Object e) => e),
    ];
    await Future<void>.delayed(Duration.zero);
    final closing = DbReadWorker.closeConnectionIfRunning();
    final results = await Future.wait(queued);
    await closing;
    expect(
      results.whereType<DbReadWorkerSuspended>().length,
      greaterThanOrEqualTo(5),
    );
    await expectLater(
      DbReadWorker.request('textRange', textRangeArgs(dbPath, 'בראשית')),
      throwsA(isA<DbReadWorkerSuspended>()),
    );
    // אילו בקשה בתור הייתה פותחת מחדש את החיבור, המחיקה הייתה נכשלת ב-Windows.
    await File(dbPath).delete();

    final replacement = await seedDb('replacement');
    DbReadWorker.allowReopen();
    expect(
      await DbReadWorker.request(
        'textRange',
        textRangeArgs(replacement, 'בראשית'),
      ),
      isNotNull,
    );
  });

  test('close during the first spawn keeps the file closed', () async {
    final dbPath = await seedDb('seforim');
    final first = DbReadWorker.request(
      'textRange',
      textRangeArgs(dbPath, ''),
    ).then<Object?>((result) => result, onError: (Object e) => e);
    await DbReadWorker.closeConnectionIfRunning();

    expect(await first, isA<DbReadWorkerSuspended>());
    await File(dbPath).delete();
    DbReadWorker.allowReopen();
  });

  test('suspend stops a batch that is already running', () async {
    final dbPath = await seedDb('seforim', bigBookLines: 200000);
    await DbReadWorker.request('textRange', textRangeArgs(dbPath, 'בראשית'));

    final batch = [
      for (var i = 0; i < 6; i++)
        DbReadWorker.batched(
          'textRange',
          slowTextArgs(dbPath),
        ).then<Object?>((result) => result, onError: (Object e) => e),
    ];
    // הבקשה כבר נשלחה כהודעת batch אחת, כך שה-suspend אינו מוצא אותה בתור.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(await DbReadWorker.suspendForExternalWrite(), isTrue);
    await File(dbPath).delete();

    final results = await Future.wait(batch);
    expect(
      results.whereType<DbReadWorkerSuspended>().length,
      greaterThanOrEqualTo(5),
    );
  });

  test('only the book worker runs with an 8MB page cache', () async {
    final dbPath = await seedDb('seforim');
    final defaultCacheSize = await onDirectConnection(dbPath, (repo) async {
      await repo.ensureInitialized();
      final db = await repo.database.database;
      return db.select('PRAGMA cache_size').single.values.single;
    });
    expect(defaultCacheSize, isNot(-8000));

    Future<void> expectCacheSizes() async {
      expect(
        await DbReadWorker.cacheSizeForTesting(dbPath, books: true),
        -8000,
      );
      expect(
        await DbReadWorker.cacheSizeForTesting(dbPath, books: false),
        defaultCacheSize,
      );
    }

    await expectCacheSizes();
    expect(await DbReadWorker.shrinkMemoryIfRunning(), isTrue);
    await expectCacheSizes();
    expect(await DbReadWorker.suspendForExternalWrite(), isTrue);
    await DbReadWorker.resumeAfterExternalWrite();
    await expectCacheSizes();
    await DbReadWorker.closeConnectionIfRunning();
    DbReadWorker.allowReopen();
    await expectCacheSizes();
  });

  group('DatabaseLibraryProvider דרך ה-worker', () {
    late String dbPath;

    setUp(() async {
      dbPath = await seedDb('seforim');
      AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data'));
      await UserBooksDatabaseHolder.instance.close();
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        dbPath,
      );
      await SqliteDataProvider.instance.dispose();
      await SqliteDataProvider.instance.initialize();
    });

    tearDown(() async {
      await SqliteDataProvider.instance.dispose();
      await UserBooksDatabaseHolder.instance.close();
      AppPaths.debugOverrideDataRootPath(null);
    });

    Link link(String title, int index2, {int? index2End}) => Link(
      heRef: title,
      index1: 1,
      path2: title,
      index2: index2,
      index2End: index2End,
      connectionType: 'commentary',
      targetCategoryId: 7,
    );

    Future<void> shadowMainBookTable() async {
      final mainDb =
          await SqliteDataProvider.instance.repository!.database.database;
      mainDb.execute('PRAGMA query_only=OFF');
      mainDb.execute('CREATE TEMP TABLE book AS SELECT * FROM main.book');
      mainDb.execute('DELETE FROM temp.book');
    }

    test('שורות קישור שומרות br פנימי בשאילתת טווח', () async {
      final db = sqlite3.sqlite3.open(dbPath);
      db.execute(
        "UPDATE line SET content = ? WHERE bookId = ? AND lineIndex = ?",
        ['פירוש<br>המשך', 2, 0],
      );
      db.close();
      expect(
        await DatabaseLibraryProvider.instance.getLinkContentLines(
          link('מפרש', 1, index2End: 2),
        ),
        [
          (lineIndex: 0, content: 'פירוש<br>המשך'),
          (lineIndex: 1, content: 'פירוש 1'),
        ],
      );
    });

    test('טווח דליל שומר את האינדקסים המקוריים ולא מזיז נתוני הערות', () async {
      final db = sqlite3.sqlite3.open(dbPath);
      db.execute('DELETE FROM line WHERE bookId = 2 AND lineIndex = 1');
      db.close();
      final lines = await DatabaseLibraryProvider.instance.getLinkContentLines(
        link('מפרש', 1, index2End: 3),
      );
      expect(lines, [
        (lineIndex: 0, content: 'פירוש 0'),
        (lineIndex: 2, content: 'פירוש 2'),
      ]);
      expect(
        await DatabaseLibraryProvider.instance.getLinkContent(
          link('מפרש', 2, index2End: 3),
        ),
        'שגיאה: אינדקס מחוץ לטווח',
      );
    });

    test('getLinkContent מחזיר את אותן מחרוזות כמו קודם', () async {
      final provider = DatabaseLibraryProvider.instance;
      expect(await provider.getLinkContent(link('מפרש', 2)), 'פירוש 1');
      expect(
        await provider.getLinkContent(link('מפרש', 1, index2End: 2)),
        'פירוש 0<br>פירוש 1',
      );
      expect(
        await provider.getLinkContent(link('מפרש', 9)),
        'שגיאה: אינדקס מחוץ לטווח',
      );
      expect(
        await provider.getLinkContent(link('לא קיים', 1)),
        'שגיאה: הספר לא נמצא במסד הנתונים',
      );
    });
    test('getLinkContent שומר על התוכן אחרי timeout של ה-worker', () async {
      DbReadWorker.stallTimeout = Duration.zero;
      final provider = DatabaseLibraryProvider.instance;
      expect(await provider.getLinkContent(link('מפרש', 2)), 'פירוש 1');
    });

    test('רשימת המפרשים בפתיחת ספר נשלפת ב-worker', () async {
      addCommentaryLink(dbPath);
      await shadowMainBookTable();
      final repository = TextBookRepository(
        fileSystem: FileSystemData.instance,
      );
      final before = DbReadWorker.sentMessageCount;
      final detailed = await repository.getCommentatorsDetailed(
        TextBook(id: 1, title: 'בראשית', categoryId: 7),
      );
      expect([for (final c in detailed.commentators) c.title], ['מפרש']);
      expect(detailed.commentators.single.linkCount, 1);
      expect(
        DbReadWorker.sentMessageCount - before,
        2,
        reason: 'גם איתור הספר וגם שליפת המפרשים רצים ב-worker',
      );
    });

    test('רשימת המפרשים לא רצה על ה-UI isolate כשה-worker אינו זמין', () async {
      addCommentaryLink(dbPath);
      final repository = TextBookRepository(
        fileSystem: FileSystemData.instance,
      );
      // טבלת temp מסתירה את link בחיבור הראשי בלבד: שאילתה עליו מחזירה ריק.
      final mainDb =
          await SqliteDataProvider.instance.repository!.database.database;
      mainDb.execute('PRAGMA query_only=OFF');
      mainDb.execute('CREATE TEMP TABLE link AS SELECT * FROM main.link');
      mainDb.execute('DELETE FROM temp.link');
      DbReadWorker.stallTimeout = Duration.zero;

      final detailed = await repository.getCommentatorsDetailed(
        TextBook(id: 1, title: 'בראשית', categoryId: 7),
      );
      expect([for (final c in detailed.commentators) c.title], ['מפרש']);
    });

    test('heRef של ספר רשמי נקרא ב-worker, לא בחיבור הראשי', () async {
      // טבלת temp מסתירה את line בחיבור הראשי בלבד: שאילתה עליו מחזירה null.
      final mainDb =
          await SqliteDataProvider.instance.repository!.database.database;
      mainDb.execute('PRAGMA query_only=OFF');
      mainDb.execute('CREATE TEMP TABLE line AS SELECT * FROM main.line');
      mainDb.execute('DELETE FROM temp.line');
      final before = DbReadWorker.sentMessageCount;

      final book = TextBook(id: 1, title: 'בראשית', categoryId: 7);
      expect(await heRefFromDbLine(book, 3), 'בראשית א, 4');
      expect(DbReadWorker.sentMessageCount - before, 1);
    });

    test('כותרות ספרי המסד נטענות ב-worker', () async {
      final provider = DatabaseLibraryProvider.instance..clearCache();
      final before = DbReadWorker.sentMessageCount;
      final keys = await provider.getDatabaseOnlyBookTitles();
      expect(keys, hasLength(3));
      expect(keys.any((key) => key.contains('בראשית')), isTrue);
      expect(DbReadWorker.sentMessageCount - before, 1);
    });

    test('המפרשים הנוספים על שורה נשלפים ב-worker', () async {
      addCommentaryLink(dbPath);
      await shadowMainBookTable();
      final repository = TextBookRepository(
        fileSystem: FileSystemData.instance,
      );
      final before = DbReadWorker.sentMessageCount;
      final links = await repository.getSiblingCommentaries(
        sourceBookTitle: 'בראשית',
        sourceCategoryId: 7,
        sourceLineIndex: 1,
        currentBookTitle: 'אחר',
        currentCategoryId: 7,
      );
      expect([for (final link in links) link.path2], ['מפרש']);
      expect(links.single.index2, 2);
      expect(
        DbReadWorker.sentMessageCount - before,
        4,
        reason: 'איתור המקור, שני נסיונות לאיתור הספר החסר ושאילתת הקישורים',
      );
    });

    test(
      'המפרשים הנוספים לא רצים על ה-UI isolate כשה-worker אינו זמין',
      () async {
        addCommentaryLink(dbPath);
        final repository = TextBookRepository(
          fileSystem: FileSystemData.instance,
        );
        // טבלת temp מסתירה את link בחיבור הראשי בלבד: שאילתה עליו מחזירה ריק.
        final mainDb =
            await SqliteDataProvider.instance.repository!.database.database;
        mainDb.execute('PRAGMA query_only=OFF');
        mainDb.execute('CREATE TEMP TABLE link AS SELECT * FROM main.link');
        mainDb.execute('DELETE FROM temp.link');
        DbReadWorker.stallTimeout = Duration.zero;

        final links = await repository.getSiblingCommentaries(
          sourceBookTitle: 'בראשית',
          sourceCategoryId: 7,
          sourceLineIndex: 1,
          currentBookTitle: 'אחר',
          currentCategoryId: 7,
        );
        expect([for (final link in links) link.path2], ['מפרש']);
      },
    );

    test('מפרשים נוספים: התצוגה המקדימה מציגה את כל קטעי המפרש על שורת המקור '
        '(issue #3026)', () async {
      final db = sqlite3.sqlite3.open(dbPath);
      for (var i = 3; i < 12; i++) {
        db.execute(
          'INSERT INTO line (id, bookId, lineIndex, content) '
          'VALUES (?, 2, ?, ?)',
          [200 + i, i, 'פירוש $i'],
        );
      }
      db.execute(
        "INSERT INTO connection_type (name) SELECT 'COMMENTARY' WHERE NOT "
        "EXISTS (SELECT 1 FROM connection_type WHERE name = 'COMMENTARY')",
      );
      // שורת מקור 1: ס"ק צמודים, ביניהם שורת הפרדה. שורת מקור 2: בין שני ס"ק
      // שלה ס"ק של שורה 3. שורת מקור 4: ס"ק ועוד אחד רחוק ממנו.
      for (final (sourceLine, targetLine) in [
        (101, 200),
        (101, 201),
        (101, 203),
        (102, 204),
        (102, 206),
        (103, 205),
        (104, 207),
        (104, 211),
      ]) {
        db.execute(
          'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, '
          'targetBookId, connectionTypeId) SELECT 1, ?, ?, 2, id '
          "FROM connection_type WHERE name = 'COMMENTARY'",
          [sourceLine, targetLine],
        );
      }
      db.close();
      final repository = TextBookRepository(
        fileSystem: FileSystemData.instance,
      );

      Future<String> preview(int sourceLineIndex) async {
        final links = await repository.getSiblingCommentaries(
          sourceBookTitle: 'בראשית',
          sourceCategoryId: 7,
          sourceLineIndex: sourceLineIndex,
          currentBookTitle: 'אחר',
          currentCategoryId: 7,
        );
        return DatabaseLibraryProvider.instance.getLinkContent(links.single);
      }

      expect(await preview(1), 'פירוש 0<br>פירוש 1<br>פירוש 2<br>פירוש 3');
      expect(await preview(2), 'פירוש 4');
      expect(await preview(4), 'פירוש 7');
    });

    test('טווחי טקסט וקישורים נטענים דרך ה-worker', () async {
      final provider = DatabaseLibraryProvider.instance;
      final before = DbReadWorker.sentMessageCount;
      final range = await provider.getBookTextRange(
        'בראשית',
        7,
        'txt',
        startLine: 0,
        endLine: 1,
      );
      expect(range?.lines, ['שורה 0', 'שורה 1']);
      final links = await provider.getLinksForBookRange(
        'בראשית',
        7,
        'txt',
        startLineIndex: 0,
        endLineIndex: 4,
      );
      expect(links.single.path2, 'מפרש');
      expect(links.single.index1, 3);
      expect(DbReadWorker.sentMessageCount - before, greaterThanOrEqualTo(2));
    });

    test(
      'השהיה לכתיבה חיצונית סוגרת את ה-worker יחד עם החיבור הראשי',
      () async {
        final provider = DatabaseLibraryProvider.instance;
        expect(await provider.getLinkContent(link('מפרש', 2)), 'פירוש 1');

        await SqliteDataProvider.instance.closeForExternalWrite();
        await File(dbPath).delete();
        await SqliteDataProvider.instance.reopenAfterExternalWrite(
          reopenDatabase: false,
        );
      },
    );

    test(
      'an unreleased read stays suspended when releaseOnFailure is false',
      () async {
        final lineSource = FakeLineSourceEngine();
        LibraryLineSource.debugReset(engine: lineSource);
        addTearDown(LibraryLineSource.debugReset);
        final provider = DatabaseLibraryProvider.instance;
        expect(await provider.getLinkContent(link('מפרש', 2)), isNotEmpty);

        // גם כשל ב-assert לא ישאיר שער כתיבה סגור לבדיקות הבאות.
        addTearDown(
          () => SqliteDataProvider.instance.reopenAfterExternalWrite(
            reopenDatabase: false,
          ),
        );
        final release = Completer<void>();
        final reading = DbReadWorker.trackTemporaryRead(
          () => release.future,
        ).then<Object?>((_) => null, onError: (Object error) => error);
        DbReadWorker.lifecycleCommandTimeout = Duration.zero;
        try {
          await expectLater(
            SqliteDataProvider.instance.closeForExternalWrite(
              releaseOnFailure: false,
            ),
            throwsA(isA<DbReadWorkerNotReleased>()),
          );
        } finally {
          DbReadWorker.lifecycleCommandTimeout = const Duration(seconds: 4);
          release.complete();
          await reading;
        }
        await expectLater(
          DbReadWorker.request('textRange', textRangeArgs(dbPath, 'בראשית')),
          throwsA(isA<DbReadWorkerSuspended>()),
        );
        expect(lineSource.depth, 1, reason: 'גם מקור השורות נשאר מושהה');

        await SqliteDataProvider.instance.reopenAfterExternalWrite();
        expect(
          await DbReadWorker.request(
            'textRange',
            textRangeArgs(dbPath, 'בראשית'),
          ),
          isNotNull,
        );
        expect(lineSource.depth, 0);
        expect(lineSource.resumes, 1);
      },
    );

    test('קטלוג אחרי timeout אינו חוזר לחיבור ה-UI', () async {
      final provider = DatabaseLibraryProvider.instance;
      provider.clearCache();
      final mainDb =
          await SqliteDataProvider.instance.repository!.database.database;
      mainDb.execute('PRAGMA query_only=OFF');
      mainDb.execute('CREATE TEMP TABLE book AS SELECT * FROM main.book');
      mainDb.execute('DELETE FROM temp.book');
      DbReadWorker.stallTimeout = Duration.zero;
      final keys = await provider.getAvailableBookKeys();
      expect(keys.map((key) => key.title), containsAll(['בראשית', 'מפרש']));
      provider.clearCache();
    });

    test('עומס זמני אינו ספר ריק ואינו עוקף admission בקריאה ישירה', () async {
      final provider = DatabaseLibraryProvider.instance;
      addTearDown(provider.clearCache);
      final sqlite = SqliteDataProvider.instance;
      final repository = TextBookRepository(
        fileSystem: FileSystemData.instance,
      );
      final book = TextBook(id: 1, title: 'בראשית', categoryId: 7);
      final reads = <Future<Object?> Function()>[
        () => provider.getBookTextRange(
          'בראשית',
          7,
          'txt',
          startLine: 0,
          endLine: 2,
        ),
        () => repository.getBookContentRange(book, startLine: 0, endLine: 2),
        () => sqlite.getBookTextRangeFromDb(
          'בראשית',
          startLine: 0,
          endLine: 2,
          categoryId: 7,
          fileType: 'txt',
        ),
        () => sqlite.getBookTextFromDb('בראשית', 7, 'txt'),
        () => sqlite.getBookTextBytesFromDb('בראשית', 7, 'txt'),
        () => provider.getBookText('בראשית', 7, 'txt'),
        () => provider.getLinkContent(link('מפרש', 2)),
        () => provider.getLinkContentLines(link('מפרש', 2)),
        () => provider.getAvailableBookKeys(),
        () => provider.getDatabaseOnlyBookTitles(),
      ];
      for (final read in reads) {
        provider.clearCache();
        DbReadWorker.maxPendingWorkerReads = 0;
        await expectLater(read(), throwsA(isA<DbReadWorkerBusy>()));
        expect(DbReadWorker.resourceUsage.activeFallbackReads, 0);
        DbReadWorker.maxPendingWorkerReads = 64;
        expect(await read(), isNotNull);
      }
    });

    test(
      'a failed close releases the line source exactly once by default',
      () async {
        final lineSource = FakeLineSourceEngine();
        LibraryLineSource.debugReset(engine: lineSource);
        addTearDown(LibraryLineSource.debugReset);
        final provider = DatabaseLibraryProvider.instance;
        expect(await provider.getLinkContent(link('מפרש', 2)), isNotEmpty);

        final release = Completer<void>();
        final reading = DbReadWorker.trackTemporaryRead(
          () => release.future,
        ).then<Object?>((_) => null, onError: (Object error) => error);
        DbReadWorker.lifecycleCommandTimeout = Duration.zero;
        try {
          await expectLater(
            SqliteDataProvider.instance.closeForExternalWrite(),
            throwsA(isA<DbReadWorkerNotReleased>()),
          );
        } finally {
          DbReadWorker.lifecycleCommandTimeout = const Duration(seconds: 4);
          release.complete();
          await reading;
        }
        expect(lineSource.suspends, 1);
        expect(lineSource.resumes, 1);
        expect(lineSource.depth, 0);

        // reopen עודף אינו מחדש בלי השעיה תואמת.
        await SqliteDataProvider.instance.reopenAfterExternalWrite();
        expect(lineSource.resumes, 1);
        expect(lineSource.depth, 0);
      },
    );
  });
}
