import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/off_ui_deletion.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserBooksDatabaseHolder', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-uddh-');
      await Settings.init(cacheProvider: MemoryCacheProvider());
      await UserBooksDatabaseHolder.instance.close();
      AppPaths.debugOverrideDataRootPath(tempDir.path);
    });

    tearDown(() async {
      await UserBooksDatabaseHolder.instance.close();
      AppPaths.debugOverrideDataRootPath(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('close מודיע למאזינים פעם אחת לכל מאזין', () async {
      var calls = 0;
      void listener() => calls++;
      UserBooksDatabaseHolder.instance
        ..addCloseListener(listener)
        ..addCloseListener(listener);

      await UserBooksDatabaseHolder.instance.close();
      expect(calls, 1);
    });

    test('close ממתין גם לקריאה שטרם פתחה את המסד', () async {
      final holder = UserBooksDatabaseHolder.instance;
      final ready = Completer<void>();
      final finish = Completer<void>();
      final read = holder.trackRead(() async {
        await ready.future;
        await holder.repository;
        await finish.future;
      });
      var closed = false;
      final closing = holder.close().then((_) => closed = true);
      ready.complete();
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      finish.complete();
      await Future.wait([read, closing]);
      expect(holder.openDbPath, isNull);
    });

    test('קריאה שמתחילה במהלך close אינה פותחת חיבור נוסף', () async {
      final holder = UserBooksDatabaseHolder.instance;
      final finish = Completer<void>();
      final read = holder.trackRead(() => finish.future);
      final closing = holder.close();
      var started = false;
      await holder.trackRead(() async {
        started = true;
        await holder.repository;
      });
      expect(started, isFalse);
      expect(holder.openDbPath, isNull);
      finish.complete();
      await Future.wait([read, closing]);
      await holder.trackRead(() async {
        started = true;
        await holder.repository;
      });
      expect(started, isTrue);
      expect(holder.openDbPath, isNotNull);
    });

    test('כשל בקריאה מדווח לקורא ומשחרר את ההמתנה לסגירה', () async {
      final holder = UserBooksDatabaseHolder.instance;
      final finish = Completer<void>();
      final read = holder.trackRead(() => finish.future);
      final failed = expectLater(read, throwsStateError);
      final closing = holder.close();
      finish.completeError(StateError('read failed'));
      await Future.wait([failed, closing]);
      expect(holder.openDbPath, isNull);
    });

    Future<int> addBook(SeforimRepository repository) async {
      final categoryId = await repository.insertCategory(
        const Category(title: 'אישי'),
      );
      final sourceId = await repository.insertSource('personal', -1);
      return repository.insertBook(
        Book(
          categoryId: categoryId,
          sourceId: sourceId,
          title: 'יישאר',
          fileType: 'txt',
        ),
      );
    }

    test('close ממתין למחיקה ברקע ומשאיר את החיבור חי עד לסיומה', () async {
      final holder = UserBooksDatabaseHolder.instance;
      final repository = await holder.repository;
      final bookId = await addBook(repository);
      final writer = sqlite3.open(repository.database.path);
      writer.execute('BEGIN IMMEDIATE');
      var closed = false;
      var reachedCloseListeners = false;
      var observing = true;
      holder.addCloseListener(() {
        if (observing) reachedCloseListeners = true;
      });
      final deletion = deleteOffUi(
        repository,
        bookIds: [bookId],
        cleanupOrphans: false,
      );
      final closing = holder.close().then((_) => closed = true);
      try {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(closed, isFalse);
        expect(reachedCloseListeners, isFalse);
        expect(
          repository.database.isOpen,
          isTrue,
          reason: 'retirement מתחיל רק אחרי שהחיבור הזמני סיים לכתוב',
        );
      } finally {
        writer.execute('ROLLBACK');
        writer.close();
        await Future.wait([deletion, closing]);
        observing = false;
      }
      expect((await holder.repository).getBook(bookId), completion(isNull));
    });

    test('מחיקה שמתחילה בזמן close מסורבת ואינה פותחת כותב', () async {
      final holder = UserBooksDatabaseHolder.instance;
      final repository = await holder.repository;
      final bookId = await addBook(repository);
      final finish = Completer<void>();
      final active = holder.trackRead(() => finish.future);
      final closing = holder.close();
      try {
        await expectLater(
          deleteOffUi(repository, bookIds: [bookId], cleanupOrphans: false),
          throwsStateError,
        );
        expect(await repository.getBook(bookId), isNotNull);
      } finally {
        finish.complete();
        await Future.wait([active, closing]);
      }
    });

    test('repository פרוש אינו מוחק ספרים מהמסד שנפתח מחדש', () async {
      final holder = UserBooksDatabaseHolder.instance;
      final repository = await holder.repository;
      final bookId = await addBook(repository);
      await holder.close();
      final reopened = await holder.repository;
      await expectLater(
        deleteOffUi(repository, bookIds: [bookId], cleanupOrphans: false),
        throwsStateError,
      );
      expect(await reopened.getBook(bookId), isNotNull);
      expect(repository.database.isOpen, isFalse);
    });

    test('close ממתין לאתחול שכבר התחיל ולא משאיר חיבור פתוח', () async {
      final holder = UserBooksDatabaseHolder.instance;
      final initializing = holder.repository;
      final closing = holder.close();
      await Future.wait([initializing, closing]);
      expect(holder.openDbPath, isNull);
      expect(holder.repositoryIfInitialized, isNull);
    });

    test('repository מאותחל פעם אחת ומוחזק במטמון (אותו instance)', () async {
      final first = await UserBooksDatabaseHolder.instance.repository;
      final second = await UserBooksDatabaseHolder.instance.repository;

      expect(
        identical(first, second),
        isTrue,
        reason: 'הקריאה השנייה חייבת להחזיר את אותו repository, בלי לאתחל מחדש',
      );
    });

    test('close() משחרר את ה-state — אתחול עוקב יוצר instance חדש', () async {
      final first = await UserBooksDatabaseHolder.instance.repository;

      await UserBooksDatabaseHolder.instance.close();

      final second = await UserBooksDatabaseHolder.instance.repository;

      expect(
        identical(first, second),
        isFalse,
        reason: 'אחרי close, האתחול הבא מייצר repository חדש',
      );
    });

    test('close() ממזג את ה-WAL גם כשחיבור אחר עדיין פתוח', () async {
      final repo = await UserBooksDatabaseHolder.instance.repository;
      final db = await repo.database.database;
      db.execute('CREATE TABLE wal_probe(x INTEGER)');
      db.execute('INSERT INTO wal_probe VALUES (1)');

      final dbPath = await UserBooksDatabaseHolder.resolveDbPath();
      // חיבור של חלון מוסתר: בזכותו הסגירה אינה האחרונה.
      final other = sqlite3.open(dbPath);
      addTearDown(other.close);
      other.select('SELECT 1');

      await UserBooksDatabaseHolder.instance.close();

      final wal = File('$dbPath-wal');
      expect(
        !wal.existsSync() || wal.lengthSync() == 0,
        isTrue,
        reason: 'השינויים חייבים להיכנס לקובץ הראשי בסגירה',
      );
    });

    test('close() אינו חוסם את ה-isolate כשכותב אחר מחזיק את המסד', () async {
      final repo = await UserBooksDatabaseHolder.instance.repository;
      final db = await repo.database.database;
      db.execute('CREATE TABLE wal_probe(x INTEGER)');
      db.execute('INSERT INTO wal_probe VALUES (1)');

      final dbPath = await UserBooksDatabaseHolder.resolveDbPath();
      // כותב מקביל (סנכרון התיקיות ב-isolate) מחזיק את נעילת הכתיבה.
      final writer = sqlite3.open(dbPath)..execute('BEGIN IMMEDIATE');
      addTearDown(writer.close);

      final stopwatch = Stopwatch()..start();
      final closing = UserBooksDatabaseHolder.instance.close();
      final timerDelay = await Future<Duration>.delayed(
        const Duration(milliseconds: 100),
        () => stopwatch.elapsed,
      );
      // בקשה בזמן הסגירה ממתינה לסופה ולא פותחת את הקובץ מחדש באמצע.
      final reopening = UserBooksDatabaseHolder.instance.repository;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      writer.execute('ROLLBACK');
      await closing;
      expect(UserBooksDatabaseHolder.instance.openDbPath, isNull);
      final wal = File('$dbPath-wal');
      expect(!wal.existsSync() || wal.lengthSync() == 0, isTrue);
      expect(timerDelay, lessThan(const Duration(seconds: 2)));
      await reopening;
    });

    test('מאגר ישן אינו פותח את הקובץ במהלך הסגירה או אחריה', () async {
      final holder = UserBooksDatabaseHolder.instance;
      final repo = await holder.repository;
      final db = await repo.database.database;
      db.execute('CREATE TABLE stale_repository_probe(x INTEGER)');
      db.execute('INSERT INTO stale_repository_probe VALUES (1)');
      final dbPath = await UserBooksDatabaseHolder.resolveDbPath();
      final writer = sqlite3.open(dbPath)..execute('BEGIN IMMEDIATE');
      var closed = false;
      final closing = holder.close().then((_) => closed = true);
      try {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(closed, isFalse);
        await expectLater(repo.getAllBooks(), throwsStateError);
      } finally {
        writer.execute('ROLLBACK');
        writer.close();
        await closing;
      }
      expect(repo.database.isOpen, isFalse);
      await expectLater(repo.getAllBooks(), throwsStateError);
      expect(holder.openDbPath, isNull);
      expect(identical(await holder.repository, repo), isFalse);
    });

    test('שחרור לצמיתות מבטל גם פתיחה שממתינה לטעינת שאילתות', () async {
      final database = MyDatabase.withPath(
        path.join(tempDir.path, 'pending-open.db'),
      );
      addTearDown(database.close);
      final opening = database.database;
      final failed = expectLater(opening, throwsStateError);
      await database.retireInBackground();
      await failed;
      expect(database.isOpen, isFalse);
      expect(File(database.path).existsSync(), isFalse);
    });

    test('פתיחה שממתינה לסגירה קוראת את הקובץ שהוחלף מיד אחריה', () async {
      final holder = UserBooksDatabaseHolder.instance;
      final repo = await holder.repository;
      final db = await repo.database.database;
      db.execute('CREATE TABLE replacement_probe(value TEXT)');
      db.execute("INSERT INTO replacement_probe VALUES ('old')");
      final dbPath = await UserBooksDatabaseHolder.resolveDbPath();
      final staged = File('$dbPath.restore');
      final replacement = sqlite3.open(staged.path);
      replacement.execute('CREATE TABLE replacement_probe(value TEXT)');
      replacement.execute("INSERT INTO replacement_probe VALUES ('new')");
      replacement.close();
      final writer = sqlite3.open(dbPath)..execute('BEGIN IMMEDIATE');
      var writerOpen = true;
      final closing = holder.close();
      try {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        // נרשם לפני await closing, כמו קורא שמגיע במהלך השחזור.
        final reopening = holder.repository;
        writer.execute('ROLLBACK');
        writer.close();
        writerOpen = false;
        await closing;
        expect(holder.openDbPath, isNull);
        // בדיוק כמו השחזור: אין await בין הסגירה להחלפה.
        for (final suffix in const ['-wal', '-shm']) {
          final sidecar = File('$dbPath$suffix');
          if (sidecar.existsSync()) sidecar.deleteSync();
        }
        staged.renameSync(dbPath);
        final reopened = await reopening;
        final reopenedDb = await reopened.database.database;
        expect(
          reopenedDb
              .select('SELECT value FROM replacement_probe')
              .single['value'],
          'new',
        );
      } finally {
        if (writerOpen) writer.close();
        await closing;
      }
    });

    test(
      'resolveDbPath מחזיר נתיב legacy קיים תחת data_root/databases',
      () async {
        await Directory(
          path.join(tempDir.path, 'databases'),
        ).create(recursive: true);

        final dbPath = await UserBooksDatabaseHolder.resolveDbPath();

        expect(dbPath, path.join(tempDir.path, 'databases', 'user_books.db'));
      },
    );

    test('resolveDbPath ממקם התקנה חדשה ליד תיקיית הספרייה', () async {
      final libraryRoot = await Directory.systemTemp.createTemp(
        'otzaria-uddh-library-',
      );
      addTearDown(() async {
        if (await libraryRoot.exists()) {
          await libraryRoot.delete(recursive: true);
        }
      });

      await Settings.setValue(
        SettingsRepository.keyLibraryPath,
        path.join(libraryRoot.path, 'books'),
      );

      final dbPath = await UserBooksDatabaseHolder.resolveDbPath();

      expect(dbPath, path.join(libraryRoot.path, 'databases', 'user_books.db'));
    });

    test(
      'recovery: כישלון אתחול מאפס את _initFuture כדי לאפשר ניסיון חוזר',
      () async {
        // יוצרים _קובץ_ בשם "databases" במקום שאמורה להיות תיקייה — זה גורם
        // ל-`Directory.create` לזרוק כי הנתיב כבר תפוס. ה-DB לא מצליח להיפתח.
        final blocker = File(path.join(tempDir.path, 'databases'));
        await blocker.writeAsString('blocker');

        Object? firstError;
        try {
          await UserBooksDatabaseHolder.instance.repository;
        } catch (e) {
          firstError = e;
        }
        expect(
          firstError,
          isNotNull,
          reason: 'יצירת התיקייה אמורה להיכשל כי הנתיב הוא קובץ',
        );

        // מסירים את החסימה ויוצרים תיקייה תקינה במקום
        await blocker.delete();

        // ניסיון חוזר חייב להצליח, כי _initFuture אופס לאחר השגיאה.
        final repo = await UserBooksDatabaseHolder.instance.repository;
        expect(repo, isNotNull);

        // וידוא נוסף שה-DB אכן נפתח בקובץ הנכון
        final dbPath = await UserBooksDatabaseHolder.resolveDbPath();
        expect(await File(dbPath).exists(), isTrue);
      },
    );
  });
}
