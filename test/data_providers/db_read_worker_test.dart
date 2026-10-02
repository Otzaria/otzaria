import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/book_text_reader.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/database/journal_mode.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/search/library_line_source.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../support/fake_line_source_engine.dart';
import '../test_helpers/memory_cache_provider.dart';

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
    await DbReadWorker.resumeAfterExternalWrite();
    DbReadWorker.disposeForTesting();
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // אחרי kill שחרור ה-handle ב-Windows אינו מיידי; ה-temp אינו הנבדק.
    }
  });

  test('תוכן קישור ונתיב כותרות מה-worker זהים למסלול הישיר', () async {
    final dbPath = await seedDb('seforim');

    final direct = await onDirectConnection(dbPath, (repo) async {
      return [
        await linkContentFromDbLines(repo, 2, 1, null),
        await linkContentFromDbLines(repo, 2, 1, 3),
        await linkContentFromDbLines(repo, 2, 99, null),
        await repo.getLineBreadcrumb(1, 3),
        await repo.getLineBreadcrumb(1, 0),
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
    ]);
    expect([
      for (final r in viaWorker.take(3)) (r! as Map)['content'],
      ...viaWorker.skip(3),
    ], direct);
  });

  test('ספר שאינו ברשמי מוחזר למסלול הישיר ולא כשגיאה', () async {
    final dbPath = await seedDb('seforim');
    expect(
      await DbReadWorker.batched('linkContent', linkArgs(dbPath, 'אין', 1)),
      {'fallback': true},
    );
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
      [
        'פירוש 0',
        'פירוש 1',
        'פירוש 2',
      ],
    );
  });

  test(
    'timeout של אצווה קורא תוכן וכותרת מחוץ ל-worker ומשחרר את הקובץ',
    () async {
      final dbPath = await seedDb('seforim');
      final expectedBreadcrumb = await onDirectConnection(
        dbPath,
        (repo) => repo.getLineBreadcrumb(1, 3),
      );
      DbReadWorker.stallTimeout = Duration.zero;

      final results = await Future.wait([
        DbReadWorker.batched('linkContent', linkArgs(dbPath, 'מפרש', 2)),
        DbReadWorker.batched('breadcrumb', {
          'dbPath': dbPath,
          'bookId': 1,
          'lineIndex': 3,
        }),
      ]);

      expect((results.first as Map)['content'], 'פירוש 1');
      expect(results.last, expectedBreadcrumb);
      expect(await DbReadWorker.suspendForExternalWrite(), isTrue);
      await File(dbPath).delete();
    },
  );

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
    DbReadWorker.stallTimeout = const Duration(milliseconds: 50);
    final full = await pausedBookRead(dbPath);
    await DbReadWorker.closeConnectionIfRunning(wait: false);
    DbReadWorker.allowReopen();
    expect(await full.result, isA<DbReadWorkerSuspended>());
    DbReadWorker.stallTimeout = const Duration(seconds: 10);
    full.release.send(null);
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

  test('השהיה ממתינה לחיבור RO של fallback טווח רשמי', () async {
    final dbPath = await seedDb('seforim');
    final checkpoint = ReceivePort();
    addTearDown(checkpoint.close);
    DbReadWorker.stallTimeout = Duration.zero;
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
          await DbReadWorker.batched('linkContent', linkArgs(second, 'מפרש', 2))
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
      'an unreleased worker stays suspended when releaseOnFailure is false',
      () async {
        final lineSource = FakeLineSourceEngine();
        LibraryLineSource.debugReset(engine: lineSource);
        addTearDown(LibraryLineSource.debugReset);
        final provider = DatabaseLibraryProvider.instance;
        expect(await provider.getLinkContent(link('מפרש', 2)), isNotEmpty);

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

    test(
      'a failed close releases the line source exactly once by default',
      () async {
        final lineSource = FakeLineSourceEngine();
        LibraryLineSource.debugReset(engine: lineSource);
        addTearDown(LibraryLineSource.debugReset);
        final provider = DatabaseLibraryProvider.instance;
        expect(await provider.getLinkContent(link('מפרש', 2)), isNotEmpty);

        DbReadWorker.lifecycleCommandTimeout = Duration.zero;
        try {
          await expectLater(
            SqliteDataProvider.instance.closeForExternalWrite(),
            throwsA(isA<DbReadWorkerNotReleased>()),
          );
        } finally {
          DbReadWorker.lifecycleCommandTimeout = const Duration(seconds: 4);
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
