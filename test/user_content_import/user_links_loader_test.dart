import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_links_loader.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('טווחי מקור נטענים גם כשהחלון מתחיל באמצעם, בשני הכיוונים', () async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    final tempDir = await Directory.systemTemp.createTemp('user_link_ranges');
    final previousRoot = AppPaths.cachedDataRootPath;
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(p.join(tempDir.path, 'data'));
    addTearDown(() async {
      await UserBooksDatabaseHolder.instance.close();
      AppPaths.debugOverrideDataRootPath(previousRoot);
      await tempDir.delete(recursive: true);
    });

    final db = (await UserBooksDatabaseHolder.instance.repository).database;
    await UserContentRepository(db).upsertUserLink(
      const UserLinkRecord(
        sourceTitle: 'בסיס',
        sourceIsUserBook: false,
        sourceLineIndex: 1,
        sourceLineIndexEnd: 8,
        targetTitle: 'מפרש',
        targetIsUserBook: true,
        targetLineIndex: 3,
        targetLineIndexEnd: 10,
        connectionType: 'COMMENTARY',
      ),
    );

    final forward = await loadUserLinksForBook(
      bookTitle: 'בסיס',
      bookCategoryId: null,
      source: BookSource.official,
      startLineIndex: 5,
      endLineIndex: 6,
    );
    expect(forward.single.index1, 2);
    expect(forward.single.index1End, 9);
    expect(forward.single.overlapsSourceLines(6, 7), isTrue);

    final inverse = await loadUserLinksForBook(
      bookTitle: 'מפרש',
      bookCategoryId: null,
      source: BookSource.user,
      startLineIndex: 6,
      endLineIndex: 7,
    );
    expect(inverse.single.index1, 4);
    expect(inverse.single.index1End, 11);
    expect(inverse.single.overlapsSourceLines(7, 8), isTrue);
  });

  test(
    'קישור שצדו במסד מצורף מוצג בספר המצורף ולא בספר רשמי באותו שם',
    () async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      final tempDir = await Directory.systemTemp.createTemp(
        'user_link_attached',
      );
      final previousRoot = AppPaths.cachedDataRootPath;
      await UserBooksDatabaseHolder.instance.close();
      AppPaths.debugOverrideDataRootPath(p.join(tempDir.path, 'data'));
      addTearDown(() async {
        await UserBooksDatabaseHolder.instance.close();
        AppPaths.debugOverrideDataRootPath(previousRoot);
        await tempDir.delete(recursive: true);
      });

      final db = (await UserBooksDatabaseHolder.instance.repository).database;
      await UserContentRepository(db).upsertUserLink(
        const UserLinkRecord(
          sourceTitle: 'בסיס',
          sourceIsUserBook: false,
          sourceDb: 'my-db',
          sourceLineIndex: 2,
          targetTitle: 'מפרש',
          targetIsUserBook: true,
          targetLineIndex: 4,
          connectionType: 'COMMENTARY',
        ),
      );

      final attached = BookSource.attached('my-db');
      final forward = await loadUserLinksForBook(
        bookTitle: 'בסיס',
        bookCategoryId: 7,
        source: attached,
        startLineIndex: 0,
        endLineIndex: 10,
      );
      expect(forward.single.index1, 3);
      expect(forward.single.targetSource, BookSource.user);
      expect(
        await loadUserCommentatorTitles(
          bookTitle: 'בסיס',
          bookCategoryId: 7,
          source: attached,
        ),
        ['מפרש'],
      );

      final official = await loadUserLinksForBook(
        bookTitle: 'בסיס',
        bookCategoryId: null,
        source: BookSource.official,
        startLineIndex: 0,
        endLineIndex: 10,
      );
      expect(official, isEmpty);

      final inverse = await loadUserLinksForBook(
        bookTitle: 'מפרש',
        bookCategoryId: null,
        source: BookSource.user,
        startLineIndex: 0,
        endLineIndex: 10,
      );
      expect(inverse.single.targetSource, attached);
      expect(inverse.single.index2, 3);
    },
  );

  test('מפרשי-משתמש נקראים בחיבור נפרד, לא בחיבור הראשי', () async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    final tempDir = await Directory.systemTemp.createTemp('user_commentators');
    final previousRoot = AppPaths.cachedDataRootPath;
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(p.join(tempDir.path, 'data'));
    addTearDown(() async {
      await UserBooksDatabaseHolder.instance.close();
      AppPaths.debugOverrideDataRootPath(previousRoot);
      await tempDir.delete(recursive: true);
    });

    final db = (await UserBooksDatabaseHolder.instance.repository).database;
    final ucr = UserContentRepository(db);
    UserLinkRecord commentary(String target) => UserLinkRecord(
      sourceTitle: 'בסיס',
      sourceIsUserBook: false,
      sourceLineIndex: 1,
      targetTitle: target,
      targetIsUserBook: true,
      targetLineIndex: 1,
      connectionType: 'COMMENTARY',
    );
    await ucr.upsertUserLink(commentary('מפרש'));

    Future<List<String>> titles() => loadUserCommentatorTitles(
      bookTitle: 'בסיס',
      bookCategoryId: null,
      source: BookSource.official,
    );
    expect(await titles(), ['מפרש']);

    // רק החיבור הראשי רואה שורה שטרם נכתבה סופית.
    final connection = await db.database;
    connection.execute('BEGIN');
    try {
      await ucr.upsertUserLink(commentary('מפרש חדש'));
      expect(await titles(), ['מפרש']);
    } finally {
      connection.execute('COMMIT');
    }
    expect(await titles(), unorderedEquals(['מפרש', 'מפרש חדש']));
  });

  group('מחזור החיים של קריאות המשתמש', () {
    final holder = UserBooksDatabaseHolder.instance;
    late Directory tempDir;
    String? previousRoot;

    setUp(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      tempDir = await Directory.systemTemp.createTemp('user_links_lifecycle');
      previousRoot = AppPaths.cachedDataRootPath;
      await holder.close();
      AppPaths.debugOverrideDataRootPath(tempDir.path);
      final repo = await holder.repository;
      await UserContentRepository(repo.database).upsertUserLink(
        const UserLinkRecord(
          sourceTitle: 'בסיס',
          sourceIsUserBook: false,
          sourceLineIndex: 1,
          targetTitle: 'מפרש',
          targetIsUserBook: true,
          targetLineIndex: 1,
          connectionType: 'COMMENTARY',
        ),
      );
    });

    tearDown(() async {
      await holder.close();
      AppPaths.debugOverrideDataRootPath(previousRoot);
      await tempDir.delete(recursive: true);
    });

    for (final entry in <String, Future<List<Object>> Function()>{
      'מפרשים': () => loadUserCommentatorTitles(
        bookTitle: 'בסיס',
        bookCategoryId: null,
        source: BookSource.official,
      ),
      'קישורים': () => loadUserLinksForBook(
        bookTitle: 'בסיס',
        bookCategoryId: null,
        source: BookSource.official,
        startLineIndex: 0,
        endLineIndex: 2,
      ),
    }.entries) {
      test('close ממתין לקריאת ${entry.key} שממתינה לנעילת כותב', () async {
        final connection = await (await holder.repository).database.database;
        connection.execute('PRAGMA journal_mode=DELETE');
        final path = holder.openDbPath!;
        final ready = ReceivePort();
        final writer = _holdExclusiveLock(holder.openDbPath!, ready.sendPort);
        final release = await ready.first as SendPort;
        ready.close();
        var readFinished = false;
        final read = entry.value().whenComplete(() => readFinished = true);
        final closing = holder.close();
        bool closedBeforeRead;
        try {
          closedBeforeRead = await Future.any([
            closing.then((_) => true),
            Future<bool>.delayed(
              const Duration(milliseconds: 100),
              () => false,
            ),
          ]);
        } finally {
          release.send(null);
          await writer;
        }
        expect(await read, hasLength(1));
        await closing;
        expect(closedBeforeRead, isFalse);
        expect(readFinished, isTrue);
        expect(holder.openDbPath, isNull);
        // החלפת הקובץ אחרי close חייבת לקרות בלי קורא שיפתח אותו באיחור.
        final saved = File('$path.saved');
        await File(path).rename(saved.path);
        await saved.rename(path);
        await holder.repository;
        expect(await entry.value(), hasLength(1));
      });

      test('${entry.key} מדולגים בזמן close וחוזרים אחרי פתיחה מחדש', () async {
        final finish = Completer<void>();
        final active = holder.trackRead(() => finish.future);
        final closing = holder.close();
        try {
          expect(await entry.value(), isEmpty);
        } finally {
          finish.complete();
          await Future.wait([active, closing]);
        }
        expect(await entry.value(), isEmpty);
        expect(holder.openDbPath, isNull);
        await holder.repository;
        expect(await entry.value(), hasLength(1));
      });

      test('כשל בקריאת ${entry.key} מדווח ומשחרר את close', () async {
        final connection = await (await holder.repository).database.database;
        connection.execute('DROP TABLE user_link');
        final failed = expectLater(
          entry.value(),
          throwsA(isA<SqliteException>()),
        );
        await holder.close();
        await failed;
        expect(holder.openDbPath, isNull);
      });
    }
  });

  group('dedupeUserLinks', () {
    Link link(int i1, String p2, int i2, {String type = 'COMMENTARY'}) => Link(
      heRef: 'ref',
      index1: i1,
      path2: p2,
      index2: i2,
      connectionType: type,
    );

    test('קישור דו-כיווני (forward+inverse זהים) נשמר פעם אחת', () {
      final forward = Link(
        heRef: 'הכי גרסינן מגילה ב., א',
        index1: 3,
        path2: 'הכי גרסינן מגילה',
        index2: 5,
        connectionType: 'COMMENTARY',
        targetSource: BookSource.user,
        targetCategoryId: 7,
      );
      final inverse = Link(
        heRef: 'הכי גרסינן מגילה',
        index1: 3,
        path2: 'הכי גרסינן מגילה',
        index2: 5,
        connectionType: 'COMMENTARY',
        targetSource: BookSource.user,
        targetCategoryId: 7,
      );
      final result = dedupeUserLinks([forward, inverse]);
      expect(result, hasLength(1));
      // ה-forward ראשון — ה-heRef העשיר שלו נשמר
      expect(result.single.heRef, 'הכי גרסינן מגילה ב., א');
    });

    // ⚠️ הליבה של עוגני-המילה: שתי מילים בשורת הבסיס שמפנות לאותה שורת מפרש
    // הן שני סמנים. מפתח בלי anchorStart היה משאיר אחד מהם.
    test('עוגנים שונים באותו צמד-שורות נשמרים כשניים', () {
      Link anchored(int start) => Link(
        heRef: 'מפרש א, ב',
        index1: 3,
        path2: 'מפרש',
        index2: 5,
        connectionType: 'COMMENTARY',
        anchorStart: start,
      );

      final result = dedupeUserLinks([anchored(5), anchored(40)]);
      expect(result.map((l) => l.anchorStart), [5, 40]);
    });

    test('אותו עוגן בדיוק עדיין ממוזג לאחד', () {
      Link anchored() => Link(
        heRef: 'מפרש א, ב',
        index1: 3,
        path2: 'מפרש',
        index2: 5,
        connectionType: 'COMMENTARY',
        anchorStart: 5,
      );

      expect(dedupeUserLinks([anchored(), anchored()]), hasLength(1));
    });

    test('הצד ההפוך (בלי עוגן) נבלע ברשומה המעוגנת ואינו מוצג פעמיים', () {
      final forward = Link(
        heRef: 'מפרש א, ב',
        index1: 3,
        path2: 'מפרש',
        index2: 5,
        connectionType: 'COMMENTARY',
        anchorStart: 5,
      );
      final inverse = Link(
        heRef: 'מפרש',
        index1: 3,
        path2: 'מפרש',
        index2: 5,
        connectionType: 'COMMENTARY',
      );

      final result = dedupeUserLinks([forward, inverse]);
      expect(result, hasLength(1));
      expect(result.single.anchorStart, 5);
    });

    test('אותה כותרת אך ספר אישי/רשמי או קטגוריה שונה — לא ממוזגים', () {
      Link toBook(int i1, {required bool isUser, int? categoryId}) => Link(
        heRef: 'ref',
        index1: i1,
        path2: 'משותף',
        index2: 5,
        connectionType: 'COMMENTARY',
        targetSource: BookSource.fromUserFlag(isUser),
        targetCategoryId: categoryId,
      );
      final result = dedupeUserLinks([
        toBook(3, isUser: true, categoryId: 7),
        toBook(3, isUser: false, categoryId: 7),
        toBook(3, isUser: true, categoryId: 8),
      ]);
      expect(result, hasLength(3));
    });

    test('קישורים שונים (שורה/ספר/סוג) אינם ממוזגים', () {
      final result = dedupeUserLinks([
        link(3, 'פירוש', 5),
        link(4, 'פירוש', 5),
        link(3, 'פירוש אחר', 5),
        link(3, 'פירוש', 6),
        link(3, 'פירוש', 5, type: 'REFERENCE'),
      ]);
      expect(result, hasLength(5));
    });
  });
}

Future<void> _holdExclusiveLock(String dbPath, SendPort ready) =>
    Isolate.run(() async {
      final release = ReceivePort();
      final db = sqlite3.open(dbPath);
      try {
        db.execute('BEGIN EXCLUSIVE');
        ready.send(release.sendPort);
        await release.first;
        db.execute('COMMIT');
      } finally {
        release.close();
        db.close();
      }
    });
