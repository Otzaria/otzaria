import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_import_library.dart';
import 'package:path/path.dart' as p;

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final holder = UserBooksDatabaseHolder.instance;
  final queue = DatabaseLibraryProvider.operationQueue;
  late Directory temp;
  late String? previousRoot;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await holder.close();
    temp = await Directory.systemTemp.createTemp('user_import_lifecycle');
    previousRoot = AppPaths.cachedDataRootPath;
    AppPaths.debugOverrideDataRootPath(p.join(temp.path, 'data'));
  });

  tearDown(() async {
    await holder.close();
    AppPaths.debugOverrideDataRootPath(previousRoot);
    await temp.delete(recursive: true);
  });

  Matcher cancelled() => throwsA(
    isA<StateError>().having(
      (error) => error.message,
      'message',
      contains('ספריית המשתמש נסגרת או הוחלפה'),
    ),
  );

  test('close ממתין לפענוח ולכתיבה של הייבוא הפעיל', () async {
    final db = (await holder.repository).database;
    final resolving = Completer<void>();
    final finish = Completer<int?>();
    final library = UserImportLibrary(
      db,
      resolveRef:
          ({
            required targetTitle,
            required targetCategoryId,
            required targetIsUserBook,
            required ref,
          }) {
            resolving.complete();
            return finish.future;
          },
      sourceExists: ({required title, categoryId, required isUserBook}) async =>
          true,
    );
    final file = File(p.join(temp.path, 'קישורים.csv'))
      ..writeAsStringSync(
        'ספר_מקור,מקור_אישי,מקור,ספר_יעד,מיקום_יעד,סוג,יעד_אישי\n'
        'ברכות,לא,3,מפרש,פרק א,הפניה,כן\n',
      );
    final importing = library.addFiles([file.path]);
    final imported = expectLater(
      importing,
      completion(
        isA<UserImportLibraryResult>().having((r) => r.ok, 'ok', true),
      ),
    );
    await resolving.future;
    final closing = holder.close();
    final closedDuringResolve = await Future.any([
      closing.then((_) => true),
      Future<bool>.delayed(const Duration(milliseconds: 100), () => false),
    ]);
    finish.complete(7);
    await Future.wait([imported, closing]);
    expect(closedDuringResolve, isFalse);
    expect(holder.openDbPath, isNull);

    final reopened = (await holder.repository).database;
    final links = await UserContentRepository(reopened).forwardUserLinks(
      'ברכות',
      sourceIsUserBook: false,
    );
    expect(links.single.targetLineIndex, 7);
    expect(await UserImportLibrary(reopened).list(), hasLength(1));
    await expectLater(library.list(), cancelled());
  });

  test('פעולה שממתינה בתור מבוטלת אם הספרייה נסגרה בינתיים', () async {
    final library = UserImportLibrary((await holder.repository).database);
    final release = Completer<void>();
    final blocking = queue.enqueue(() => release.future);
    final reading = expectLater(library.list(), cancelled());
    await holder.close();
    release.complete();
    await Future.wait([blocking, reading]);
    expect(holder.openDbPath, isNull);
  });

  test('close מתוך תור השחזור אינו ממתין לפעולה שמאחוריו', () async {
    final library = UserImportLibrary((await holder.repository).database);
    final release = Completer<void>();
    final blocking = queue.enqueue(() => release.future);
    final closing = queue.enqueue(holder.close);
    final reading = expectLater(library.list(), cancelled());
    release.complete();
    await Future.wait([blocking, closing, reading]);
    expect(holder.openDbPath, isNull);
  });

  test('פעולה חדשה בזמן סגירה מבוטלת בלי לפתוח את המסד', () async {
    final library = UserImportLibrary((await holder.repository).database);
    final finish = Completer<void>();
    final active = holder.trackRead(() => finish.future);
    final closing = holder.close();
    try {
      await expectLater(library.list(), cancelled());
    } finally {
      finish.complete();
      await Future.wait([active, closing]);
    }
    expect(holder.openDbPath, isNull);
  });
}
