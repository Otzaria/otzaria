import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/journal_mode.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/search/library_line_source.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../support/fake_line_source_engine.dart';
import '../test_helpers/memory_cache_provider.dart';
import 'library_release_test_support.dart';

/// issue #4490, סעיף 3: החלפת הספרייה כשתור הבקרה של worker אמיתי מלא.
/// המשתמש מקבל הודעת כישלון ברורה, שום כתיבה לא מתחילה, והניסיון החוזר
/// אחרי שהתור התרוקן מצליח.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const signalTimeout = Duration(seconds: 10);
  late Directory tempDir;

  Future<String> seedWorkerDb() async {
    final dbPath = path.join(tempDir.path, 'worker.db');
    final database = MyDatabase.withPath(dbPath);
    await SeforimRepository(database).ensureInitialized();
    final db = await database.database;
    db.execute("INSERT INTO category (id, title, level) VALUES (7, 'תנך', 0)");
    db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
    db.execute(
      'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
      "totalLines) VALUES (1, 7, 1, 'בראשית', 1, 1), "
      "(3, 7, 1, 'ספר גדול', 2, 4097)",
    );
    db.execute(
      'INSERT INTO line (id, bookId, lineIndex, content) '
      "VALUES (100, 1, 0, 'שורה')",
    );
    db.execute(
      'INSERT INTO line (id, bookId, lineIndex, content) '
      'WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n '
      "WHERE i < 4096) SELECT 1000 + i, 3, i, printf('%0200d', i) FROM n",
    );
    database.close();
    await normalizeJournalModeForReadOnly(dbPath);
    return dbPath;
  }

  /// קריאת ספר שעוצרת בנקודת ה-checkpoint של ה-worker, ואחריה ארבע פקודות
  /// open שממלאות את מכסת תור הבקרה.
  Future<({Future<Object?> result, SendPort release})> fillControlQueue(
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
    final release = await checkpoint.first.timeout(signalTimeout) as SendPort;
    for (var i = 0; i < 4; i++) {
      DbReadWorker.allowReopen();
    }
    return (result: result, release: release);
  }

  late Duration previousLifecycleTimeout;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-busy-4490-');
    EmptyLibraryBloc.tempRootOverride = tempDir.path;
    await Settings.init(cacheProvider: MemoryCacheProvider());
    previousLifecycleTimeout = DbReadWorker.lifecycleCommandTimeout;
    // ה-resume שנדחה להתאוששות ממתין לקריאה העצורה; בלי תקרה קצרה הוא היה
    // מחכה לה עד סוף הבדיקה.
    DbReadWorker.lifecycleCommandTimeout = const Duration(milliseconds: 10);
  });

  tearDown(() async {
    DbReadWorker.lifecycleCommandTimeout = previousLifecycleTimeout;
    EmptyLibraryBloc.tempRootOverride = null;
    await DbReadWorker.resumeAfterExternalWrite();
    DbReadWorker.disposeForTesting();
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // ב-Windows שחרור ה-handle אחרי kill אינו מיידי; ה-temp אינו הנבדק.
    }
  });

  test(
    'הורדה מחדש כשתור הבקרה מלא: הודעה ברורה, בלי כתיבה, וניסיון חוזר מצליח',
    () async {
      final lineSource = FakeLineSourceEngine();
      LibraryLineSource.debugReset(engine: lineSource);
      addTearDown(LibraryLineSource.debugReset);
      final workerDb = await seedWorkerDb();
      final libDir = Directory(path.join(tempDir.path, 'library'))
        ..createSync();
      final dbFile = File(
        path.join(libDir.path, DatabaseConstants.databaseFileName),
      );
      await dbFile.writeAsString('old-db');
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        libDir.path,
      );

      var fileRequests = 0;
      final inner = fakeLibraryReleaseClient(() => 'new-db');
      final bloc = EmptyLibraryBloc(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('.zst') ||
              request.url.path.endsWith('.db')) {
            fileRequests++;
          }
          return http.Response.fromStream(
            await inner.send(
              http.Request(request.method, request.url)
                ..headers.addAll(request.headers),
            ),
          );
        }),
        verifyDatabase: verifyFixtureDatabase,
        extractCompressedDatabase: copyAsExtracted,
        extractTarArchive: ignoreTarArchive,
      );
      addTearDown(bloc.close);

      final full = await fillControlQueue(workerDb);
      final EmptyLibraryError failed;
      try {
        final error = bloc.stream.firstWhere((s) => s is EmptyLibraryError);
        bloc.add(
          UpdateLibraryRequested(
            targetPath: libDir.path,
            existingLibraryPath: libDir.path,
          ),
        );
        failed = await error.timeout(signalTimeout) as EmptyLibraryError;
      } finally {
        full.release.send(null);
      }

      expect(failed.errorMessage, isNot(contains('Bad state')));
      expect(failed.errorMessage, contains('לנסות שוב'));
      expect(fileRequests, 0, reason: 'no download starts without a release');
      expect(await dbFile.readAsString(), 'old-db');
      expect(lineSource.depth, 0, reason: 'the line source hold is gone');
      expect(await full.result, isA<DbReadWorkerSuspended>());
      // קריאה שעוברת אחרי ההתאוששות מוכיחה שהתור התרוקן.
      DbReadWorker.allowReopen();
      expect(
        await DbReadWorker.request('bookText', {
          'dbPath': workerDb,
          'bookId': 1,
          'title': 'בראשית',
        }).timeout(signalTimeout),
        'שורה',
      );

      final selected = bloc.stream.firstWhere(
        (s) => s is EmptyLibraryDirectorySelected,
      );
      bloc.add(
        UpdateLibraryRequested(
          targetPath: libDir.path,
          existingLibraryPath: libDir.path,
        ),
      );
      await selected.timeout(signalTimeout);
      expect(await dbFile.readAsString(), 'new-db');
      // המצב הסופי נפלט לפני שה-finally משחרר את ה-hold.
      final deadline = DateTime.now().add(signalTimeout);
      while (lineSource.depth != 0) {
        if (DateTime.now().isAfter(deadline)) fail('the hold was not released');
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'השגיאה שנזרקת כשהתור מלא מוצגת בייבוא ובעדכון בלי טקסט חריגה גולמי',
    () async {
      final lineSource = FakeLineSourceEngine();
      LibraryLineSource.debugReset(engine: lineSource);
      addTearDown(LibraryLineSource.debugReset);
      final workerDb = await seedWorkerDb();
      final full = await fillControlQueue(workerDb);
      Object? thrown;
      try {
        await SqliteDataProvider.instance.closeForExternalWrite();
      } catch (error) {
        thrown = error;
      } finally {
        full.release.send(null);
      }
      expect(thrown, isA<DbReadWorkerNotReleased>());
      expect('$thrown', isNot(contains('Bad state')));
      expect('$thrown', contains('לנסות שוב'));
      expect(
        EmptyLibraryBloc.packageImportErrorMessage(thrown!),
        isNot(contains('Bad state')),
      );
      expect(await full.result, isA<DbReadWorkerSuspended>());
      // קריאה שעוברת אחרי ההתאוששות מוכיחה שהתור התרוקן.
      DbReadWorker.allowReopen();
      expect(
        await DbReadWorker.request('bookText', {
          'dbPath': workerDb,
          'bookId': 1,
          'title': 'בראשית',
        }).timeout(signalTimeout),
        'שורה',
      );

      // אחרי שהתור התרוקן, אותה כתיבה חיצונית מקבלת אישור שחרור.
      await SqliteDataProvider.instance.closeForExternalWrite();
      await SqliteDataProvider.instance.reopenAfterExternalWrite(
        reopenDatabase: false,
      );
      expect(lineSource.depth, 0);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
