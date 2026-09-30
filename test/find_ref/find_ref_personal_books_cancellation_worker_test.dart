import 'dart:io';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart'
    show FindRefQueryCancelled;
import 'package:otzaria/find_ref/repository/attached_find_ref_worker.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../helpers/seforim_fixture_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final dispose in [false, true]) {
    test(
      'SQLite: חיפוש חדש מתקדם אחרי ${dispose ? 'סגירה' : 'ביטול'} באצווה של 200 ספרים',
      () async {
        await QueryLoader.initialize();
        final previousRegistry = AttachedLibraryRegistry.instance;
        final registry = AttachedLibraryRegistry(idleTimeout: null)..update([]);
        AttachedLibraryRegistry.instance = registry;
        addTearDown(() async {
          await registry.closeAll();
          AttachedLibraryRegistry.instance = previousRegistry;
        });
        final dir = await Directory.systemTemp.createTemp(
          'recheck1626-real-queue',
        );
        final path = SeforimFixtureDb.create(dir, SeforimFixtureVariant.full);
        final db = sqlite3.sqlite3.open(path);
        final seedTime = Stopwatch()..start();
        db.execute('BEGIN');
        for (var i = 1; i <= 200; i++) {
          db.execute(
            'INSERT INTO book(id,categoryId,sourceId,title,orderIndex) VALUES (?,2,1,?,?)',
            [1000 + i, i == 1 ? 'קובץייעודי אישי 1' : 'קובץ אישי $i', i],
          );
        }
        db.execute(
          "INSERT INTO tocText(id,text) VALUES (950,'פרק ב'),(951,'פרק ג')",
        );
        db.execute(
          'WITH RECURSIVE n(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i<7000) '
          "INSERT INTO line(id,bookId,lineIndex,content) SELECT 1000000+(b.id-1001)*7000+n.i,b.id,n.i,'טקסט' FROM book b CROSS JOIN n WHERE b.id BETWEEN 1001 AND 1200",
        );
        db.execute(
          'INSERT INTO tocEntry(id,bookId,parentId,textId,level,lineId) '
          'SELECT id,bookId,NULL,CASE WHEN lineIndex=88 THEN 950 ELSE 951 END,1,id FROM line WHERE bookId BETWEEN 1001 AND 1200',
        );
        db.execute('COMMIT');
        db.close();
        debugPrint('fixture seed=${seedTime.elapsedMilliseconds}ms');
        final database = MyDatabase.withPath(path);
        final userRepo = SeforimRepository(database);
        await userRepo.ensureInitialized();
        FindRefRepository makeRepo() => FindRefRepository(
          isReferenceBooksCacheLoaded: () => true,
          searchReferenceBooks: (_, {limit = 50}) => [],
          getTocEntriesForReference: (_, _, {queryTokens}) async => [],
          openUserBooksRepository: () async => userRepo,
        );
        final repo = makeRepo();
        final next = dispose ? makeRepo() : repo;
        addTearDown(() async {
          repo.dispose();
          next.dispose();
          AttachedFindRefWorker.instance.reset();
          database.close();
          await dir.delete(recursive: true);
        });
        await repo.findRefs('לא קיים', includePersonalBooks: true);
        if (dispose) await next.findRefs('לא קיים', includePersonalBooks: true);
        final oldTime = Stopwatch()..start();
        final old = repo
            .findRefs('קובץ אישי פרק ב', includePersonalBooks: true)
            .then<Object>((result) => result, onError: (Object error) => error);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final latestTime = Stopwatch()..start();
        if (dispose) repo.dispose();
        final latest = await next.findRefs(
          'קובץייעודי אישי פרק ב',
          includePersonalBooks: true,
        );
        debugPrint(
          'latest elapsed=${latestTime.elapsedMilliseconds}ms; result=${latest.map((r) => (r.bookId, r.reference, r.segment)).toList()}',
        );
        expect(latest.map((r) => (r.bookId, r.segment)), contains((1001, 88)));
        final prior = await old.timeout(const Duration(seconds: 5));
        debugPrint(
          'prior elapsed=${oldTime.elapsedMilliseconds}ms; priorType=${prior.runtimeType}',
        );
        expect(prior, isA<FindRefQueryCancelled>());
        final retry = await next.findRefs(
          'קובץייעודי אישי פרק ב',
          includePersonalBooks: true,
        );
        debugPrint(
          'retry=${retry.map((r) => (r.bookId, r.reference, r.segment)).toList()}',
        );
        expect(retry.map((r) => (r.bookId, r.segment)), contains((1001, 88)));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
