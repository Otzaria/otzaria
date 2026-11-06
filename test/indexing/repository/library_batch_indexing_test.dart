import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/models/index_commit_policy.dart';
import 'package:otzaria/indexing/models/indexing_resource_policy.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/indexing/utils/pending_reindex_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/library_line_source.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import 'package:path/path.dart' as p;

import '../../support/fake_line_source_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('IndexingRepository.engineBookSource', () {
    LibraryBookSource? source(
      Book book, {
      bool ready = true,
      bool userBooks = true,
    }) => IndexingRepository.engineBookSource(
      book,
      hostApiReady: ready,
      userBooksConfigured: userBooks,
    );

    TextBook personal({String? filePath}) => TextBook(
      id: 5,
      title: 'א',
      categoryId: 2,
      source: BookSource.user,
      filePath: filePath,
    );

    test('ספר רשמי מהמסד נקרא במנוע מ-seforim.db', () {
      expect(
        source(TextBook(id: 5, title: 'א', categoryId: 2)),
        LibraryBookSource.library_,
      );
    });

    test('ספר אישי משורות המסד נקרא במנוע מ-user_books.db', () {
      expect(source(personal()), LibraryBookSource.userBooks);
      expect(source(personal(filePath: '  ')), LibraryBookSource.userBooks);
    });

    test('ספר אישי כשמקור הספרים האישיים אינו מוגדר — במסלול הרגיל', () {
      expect(source(personal(), userBooks: false), isNull);
    });

    test('ספר אישי מקובץ — במסלול הרגיל', () {
      expect(source(personal(filePath: r'C:ooks.txt')), isNull);
    });

    test('ספר ממסד מצורף שמוגדר במנוע נקרא ממנו', () {
      final attached = TextBook(
        id: 5,
        title: 'א',
        categoryId: 2,
        source: BookSource.attached('slug'),
      );
      LibraryBookSource? attachedSource(Set<String> configured) =>
          IndexingRepository.engineBookSource(
            attached,
            hostApiReady: true,
            userBooksConfigured: false,
            attachedConfigured: configured.contains,
          );

      expect(attachedSource({'slug'}), LibraryBookSource.attached);
      expect(attachedSource({'other'}), isNull);
      expect(attachedSource({}), isNull);
    });

    test('כל השאר נשארים במסלול הרגיל', () {
      expect(
        source(TextBook(id: 5, title: 'א', categoryId: 2), ready: false),
        isNull,
      );
      expect(source(personal(), ready: false), isNull);
      expect(source(TextBook(id: 5, title: 'א')), isNull);
      expect(source(TextBook(title: 'א', categoryId: 2)), isNull);
      // מזהה חיצוני: הטקסט נשמר באינדקס, כמו היום.
      expect(
        source(
          TextBook(id: 5, title: 'א', categoryId: 2, externalLibraryId: 'x'),
        ),
        isNull,
      );
      expect(
        source(
          TextBook(
            id: 5,
            title: 'א',
            categoryId: 2,
            source: BookSource.attached('slug'),
          ),
        ),
        isNull,
      );
      expect(
        source(PdfBook(id: 5, title: 'א', path: r'C:.pdf', categoryId: 2)),
        isNull,
      );
    });
  });

  group('IndexingRepository.textStorageFor — מסד מצורף', () {
    TextStorage decide(String key, int? id, Set<String> configured) =>
        IndexingRepository.textStorageFor(
          filePath: key,
          libraryDbBookId: null,
          userBooksDbBookId: null,
          attachedDbBookId: id,
          hostApiReady: true,
          userBooksConfigured: false,
          attachedConfigured: configured.contains,
        );

    test('שורות ממסד שמוגדר במנוע — הטקסט לא נשמר באינדקס', () {
      expect(decide('db:s:5', 5, {'s'}), TextStorage.libraryDb);
    });

    test('מסד שאינו מוגדר, id אחר או מפתח אחר — הטקסט נשמר', () {
      expect(decide('db:s:5', 5, {}), TextStorage.inIndex);
      expect(decide('db:s:5', 6, {'s'}), TextStorage.inIndex);
      expect(decide('db:s:5', null, {'s'}), TextStorage.inIndex);
      expect(decide('id:5', 5, {'s'}), TextStorage.inIndex);
    });
  });

  group('IndexCommitPolicy', () {
    late DateTime now;
    IndexCommitPolicy policy() => IndexCommitPolicy(
      maxDocs: 100,
      maxInterval: const Duration(seconds: 60),
      clock: () => now,
    );

    setUp(() => now = DateTime(2026));

    test('בלי ספרים אין commit, גם אחרי זמן רב', () {
      final p = policy();
      now = now.add(const Duration(hours: 1));
      expect(p.isDue, isFalse);
    });

    test('נפח המסמכים מכריע לפני הזמן', () {
      final p = policy()..recordBook(docs: 60);
      expect(p.isDue, isFalse);
      p.recordBook(docs: 40);
      expect(p.isDue, isTrue);
      expect(p.pendingBooks, 2);
    });

    test('הזמן מכריע כשהנפח קטן', () {
      final p = policy()..recordBook(docs: 1);
      now = now.add(const Duration(seconds: 59));
      expect(p.isDue, isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(p.isDue, isTrue);
    });

    test('commit מאפס נפח וזמן', () {
      final p = policy()..recordBook(docs: 500);
      now = now.add(const Duration(minutes: 5));
      p.committed();
      expect(p.pendingBooks, 0);
      p.recordBook(docs: 1);
      expect(p.isDue, isFalse);
    });
  });

  group('LibraryBatchSizer', () {
    test('מכוון לזמן היעד בגבולות', () {
      final sizer = LibraryBatchSizer(
        target: const Duration(seconds: 2),
        minBooks: 8,
        maxBooks: 256,
      );
      sizer.recordBatch(16, const Duration(seconds: 1));
      expect(sizer.size, 32);
      sizer.recordBatch(32, const Duration(seconds: 32));
      expect(sizer.size, 8);
      sizer.recordBatch(8, Duration.zero);
      expect(sizer.size, 256);
    });
  });

  group('אינדוקס ספרי הספרייה במנוע', () {
    late _BatchEngine engine;
    late _Provider provider;
    late _Repository repository;

    setUp(() {
      LibraryLineSource.debugReset(engine: FakeLineSourceEngine());
      LibraryLineSource.debugHostApiReady = true;
      IndexingRepository.newCancellationToken = _FakeToken.new;
      engine = _BatchEngine();
      provider = _Provider(engine);
      repository = _Repository(provider);
    });

    tearDown(() {
      LibraryLineSource.debugReset();
      IndexingRepository.newCancellationToken = IndexingCancellationToken.new;
      IndexingRepository.libraryFingerprint = libraryBookContentFingerprint;
    });

    List<TextBook> officialBooks(int count, {int firstId = 1}) => [
      for (var i = 0; i < count; i++)
        TextBook(id: firstId + i, title: 'ספר ${firstId + i}', categoryId: 1),
    ];

    Library libraryOf(List<Book> books) =>
        Library(categories: [])..books.addAll(books);

    test(
      'ספרים רשמיים נשלחים למנוע באצווה, ואחרים בקריאת הטקסט ב-Dart',
      () async {
        final official = officialBooks(3);
        final personal = TextBook(
          id: 9,
          title: 'אישי',
          source: BookSource.user,
        );
        final books = [...official, personal];
        final progress = <int>[];

        final result = await repository.indexAllBooks(
          libraryOf(books),
          onProgress: (processed, _) => progress.add(processed),
        );

        expect(result.completed, isTrue);
        expect(result.indexedBooks, 4);
        expect(engine.batches, [
          ['id:1', 'id:2', 'id:3'],
        ]);
        expect(engine.batchStorage['id:1'], TextStorage.libraryDb);
        expect(engine.batchDbTitles['id:2'], 'ספר 2');
        expect(engine.bytesFilePaths, ['uid:9']);
        expect(repository.loadedTitles, ['אישי']);
        expect(provider.indexedFilePaths, {'id:1', 'id:2', 'id:3', 'uid:9'});
        expect(progress.last, 4);
        expect(progress, containsAllInOrder([1, 2, 3, 4]));
        expect(engine.openWriterCalls, 1);
      },
    );

    test(
      'ספר שהשתנה באצווה: מסמכיו הישנים נמחקים לפני האצווה, באותו commit',
      () async {
        final books = officialBooks(3);
        provider.indexedFilePaths.addAll(['id:1', 'id:2', 'id:3']);
        engine.committedFilePaths.addAll(['id:1', 'id:2', 'id:3']);
        List<String>? removedBeforeBatch;
        engine.duringBatch = (_, inputs) {
          removedBeforeBatch = [...engine.removedFilePaths];
          return inputs.length;
        };

        final result = await repository.runIndexing(
          libraryOf(books),
          changedBooks: [books[1]],
          onProgress: (_, _) {},
        );

        expect(result.completed, isTrue);
        expect(engine.batches, [
          ['id:2'],
        ]);
        expect(removedBeforeBatch, ['id:2']);
        expect(engine.commitCount, 1);
        expect(provider.indexedFilePaths, {'id:1', 'id:2', 'id:3'});
      },
    );

    test('ספר אישי משורות המסד נשלח באותה אצווה מ-user_books.db', () async {
      await LibraryLineSource.configureUserBooks('/db/user_books.db');
      final official = TextBook(id: 1, title: 'רשמי', categoryId: 1);
      final personal = TextBook(
        id: 4,
        title: 'אישי',
        categoryId: 1,
        source: BookSource.user,
      );
      final fromFile = TextBook(
        id: 6,
        title: 'מקובץ',
        categoryId: 1,
        source: BookSource.user,
        filePath: r'C:ooks.txt',
      );

      await repository.indexAllBooks(
        libraryOf([official, personal, fromFile]),
        onProgress: (_, _) {},
      );

      expect(engine.batches, [
        ['id:1', 'uid:4'],
      ]);
      expect(engine.batchSources, {
        'id:1': LibraryBookSource.library_,
        'uid:4': LibraryBookSource.userBooks,
      });
      expect(engine.batchStorage['uid:4'], TextStorage.libraryDb);
      expect(engine.bytesFilePaths, ['uid:6']);
    });

    test('ספר ממסד מצורף מוגדר נשלח לאצווה עם ה-slug', () async {
      final registry = AttachedLibraryRegistry(idleTimeout: null);
      final previous = AttachedLibraryRegistry.instance;
      AttachedLibraryRegistry.instance = registry;
      addTearDown(() => AttachedLibraryRegistry.instance = previous);
      AttachedLibraryRegistry.configureEngineSource =
          ({required slug, dbPath, required immutable}) async {};
      addTearDown(
        () => AttachedLibraryRegistry.configureEngineSource =
            configureAttachedLineSource,
      );
      registry.update([
        AttachedLibrary(
          slug: 's',
          displayName: 's',
          path: 'C:/s.db',
          addedAt: DateTime(2026),
        ),
      ]);
      await registry.enableEngineSources();
      final attached = TextBook(
        id: 3,
        title: 'מצורף',
        categoryId: 1,
        source: BookSource.attached('s'),
      );
      engine.statusById[3] = LibraryBookStatus.unavailable;

      final result = await repository.indexAllBooks(
        libraryOf([attached]),
        onProgress: (_, _) {},
      );

      expect(engine.batches, [
        ['db:s:3'],
      ]);
      expect(engine.batchSources['db:s:3'], LibraryBookSource.attached);
      expect(engine.batchSlugs['db:s:3'], 's');
      // לא זמין במנוע — נקרא במסלול הרגיל, כמו ספר רשמי.
      expect(result.completed, isTrue);
      expect(engine.bytesFilePaths, ['db:s:3']);
    });

    test('ספר שהמנוע לא מצא חוזר למסלול הרגיל', () async {
      final books = officialBooks(3);
      engine.statusById[2] = LibraryBookStatus.missing;
      engine.statusById[3] = LibraryBookStatus.unavailable;

      final result = await repository.indexAllBooks(
        libraryOf(books),
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      expect(result.indexedBooks, 3);
      expect(engine.batches, [
        ['id:1', 'id:2', 'id:3'],
      ]);
      expect(engine.bytesFilePaths, ['id:2', 'id:3']);
      expect(provider.indexedFilePaths, {'id:1', 'id:2', 'id:3'});
    });

    test('ביטול בזמן דגימת משאבים אינו פותח writer או מתחיל אצווה', () async {
      repository = _Repository(
        provider,
        sampleResources: () async {
          repository.cancelIndexing();
          return const IndexingResourcePolicy(cpuCount: 2, mobile: false);
        },
      );
      final result = await repository.indexAllBooks(
        libraryOf(officialBooks(2)),
        onProgress: (_, _) {},
      );

      expect(result.cancelled, isTrue);
      expect(engine.batches, isEmpty);
      expect(engine.openWriterCalls, 0);
    });

    test('ביטול בזמן קבלת המנוע אינו מתחיל אצווה חדשה', () async {
      final result = await repository.indexAllBooks(
        libraryOf(officialBooks(2)),
        onProgress: (_, _) {
          provider.beforeEngine = () async => repository.cancelIndexing();
        },
      );

      expect(result.cancelled, isTrue);
      expect(engine.batches, isEmpty);
      expect(engine.bytesFilePaths, isEmpty);
      expect(engine.openWriterCalls, 0);
    });

    test('השהיה בזמן קבלת המנוע ממתינה להמשך לפני תחילת אצווה', () async {
      var pausedOnce = false;
      engine.duringBatch = (token, inputs) {
        expect(repository.isPaused, isFalse);
        expect(token.isCancelled, isFalse);
        return inputs.length;
      };
      final result = await repository.indexAllBooks(
        libraryOf(officialBooks(2)),
        onProgress: (_, _) {
          if (pausedOnce) return;
          pausedOnce = true;
          provider.beforeEngine = () async {
            repository.pauseIndexing();
            Future<void>.delayed(
              const Duration(milliseconds: 20),
              repository.resumeIndexing,
            );
          };
        },
      );

      expect(result.completed, isTrue);
      expect(engine.batches, [
        ['id:1', 'id:2'],
      ]);
    });

    test('ביטול באמצע אצווה: מה שנוסף נחתם ונרשם, השאר לא נקרא', () async {
      final books = officialBooks(4);
      engine.duringBatch = (token, inputs) {
        repository.cancelIndexing();
        expect(token.isCancelled, isTrue);
        return 2;
      };

      final result = await repository.indexAllBooks(
        libraryOf(books),
        onProgress: (_, _) {},
      );

      expect(result.completed, isFalse);
      expect(engine.batches.length, 1);
      expect(engine.bytesFilePaths, isEmpty);
      expect(provider.indexedFilePaths, {'id:1', 'id:2'});
      expect(engine.committedFilePaths, {'id:1', 'id:2'});
      expect(engine.removedFilePaths, isEmpty);
    });

    test(
      'ביטול באמצע אצווה עם ספר שהשתנה — נשאר בסימון ונכתב בריצה הבאה',
      () async {
        final indexDir = await Directory.systemTemp.createTemp('batch_replace');
        addTearDown(() async {
          PendingReindexStore.resetMemoryForTesting();
          await indexDir.delete(recursive: true);
        });
        PendingReindexStore.resetMemoryForTesting();
        provider.activeIndexPath = indexDir.path;
        final books = officialBooks(3);
        provider.indexedFilePaths.add('id:2');
        engine.committedFilePaths.add('id:2');
        engine.duringBatch = (token, inputs) {
          repository.cancelIndexing();
          return 1;
        };

        final cancelled = await repository.runIndexing(
          libraryOf(books),
          books: [books[0], books[2]],
          changedBooks: [books[1]],
          onProgress: (_, _) {},
        );
        expect(cancelled.completed, isFalse);
        // המסמכים הישנים נמחקו לפני האצווה, והספר לא נכתב בה.
        expect(engine.removedFilePaths, contains('id:2'));
        expect(provider.indexedFilePaths, isNot(contains('id:2')));
        expect(
          await PendingReindexStore.forIndex(indexDir.path)!.load(),
          {'id:2'},
        );

        engine.duringBatch = null;
        final resumed = await repository.runIndexing(
          libraryOf(books),
          books: [books[2]],
          onProgress: (_, _) {},
        );
        expect(resumed.completed, isTrue);
        expect(
          provider.indexedFilePaths,
          containsAll(['id:1', 'id:2', 'id:3']),
        );
        expect(
          await PendingReindexStore.forIndex(indexDir.path)!.load(),
          isEmpty,
        );
      },
    );

    test('השהיה באמצע אצווה: שאר הספרים נשלחים באצווה הבאה', () async {
      final books = officialBooks(4);
      engine.duringBatch = (token, inputs) {
        if (engine.batches.length == 1) {
          repository.pauseIndexing();
          expect(token.isCancelled, isTrue);
          Future<void>.delayed(
            const Duration(milliseconds: 20),
            repository.resumeIndexing,
          );
          return 1;
        }
        return inputs.length;
      };

      final result = await repository.indexAllBooks(
        libraryOf(books),
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      expect(result.indexedBooks, 4);
      expect(engine.batches, [
        ['id:1', 'id:2', 'id:3', 'id:4'],
        ['id:2', 'id:3', 'id:4'],
      ]);
      expect(engine.bytesFilePaths, isEmpty);
    });

    test('כשל writer באצווה: ספריה נמחקים ונכתבים ספר-ספר', () async {
      final books = officialBooks(2);
      engine.batchError = StateError('writer failed');

      final result = await repository.indexAllBooks(
        libraryOf(books),
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      expect(engine.removedFilePaths, ['id:1', 'id:2']);
      expect(engine.bytesFilePaths, ['id:1', 'id:2']);
      expect(engine.batches.length, 1);
    });

    for (final specificBooks in [false, true]) {
      test('כשל בניקוי אצווה משליך את כל החוצץ ועוצר '
          '(${specificBooks ? 'indexBooks' : 'indexAllBooks'})', () async {
        final previous = TextBook(
          id: 9,
          title: 'קודם',
          source: BookSource.user,
        );
        final existing = officialBooks(1, firstId: 99).single;
        final books = [previous, ...officialBooks(2), existing];
        final library = libraryOf(books);
        provider.indexedFilePaths.add('id:99');
        engine.committedFilePaths.add('id:99');
        engine.batchError = StateError('writer failed after partial batch');
        engine.partialBatchBooks = 2;
        engine.batchDeleteError = StateError('batch cleanup failed');

        Future<IndexingRunResult> run() => specificBooks
            ? repository.runIndexing(
                library,
                books: books,
                onProgress: (_, _) {},
              )
            : repository.indexAllBooks(library, onProgress: (_, _) {});

        final result = await run();

        expect(result.cancelled, isTrue);
        expect(result.failures.single.kind, IndexingFailureKind.engineWrite);
        expect(result.failures.single.isRetryable, isTrue);
        expect(engine.rollbackCount, 1);
        expect(provider.reopenCount, 1);
        expect(engine.commitCount, 0);
        expect(engine.pending, isEmpty);
        expect(engine.committedFilePaths, {'id:99'});
        expect(provider.indexedFilePaths, {'id:99'});
        expect(engine.bytesFilePaths, ['uid:9']);
        await IndexingRepository.whenIdle();

        engine.batchError = null;
        engine.batchDeleteError = null;
        final retried = await run();
        expect(retried.isClean, isTrue);
        expect(engine.committedFilePaths, {'uid:9', 'id:1', 'id:2', 'id:99'});
        expect(provider.indexedFilePaths, engine.committedFilePaths);
        expect(engine.duplicateWrites, isEmpty);
      });
    }

    test('שני ספרים עם אותו מפתח — הספר נשלח לאצווה פעם אחת', () async {
      final books = [
        TextBook(id: 1, title: 'ספר', categoryId: 1),
        TextBook(id: 1, title: 'ספר', categoryId: 2),
        TextBook(id: 2, title: 'אחר', categoryId: 1),
      ];

      await repository.indexAllBooks(libraryOf(books), onProgress: (_, _) {});

      expect(engine.batches, [
        ['id:1', 'id:2'],
      ]);
      expect(provider.indexedFilePaths, {'id:1', 'id:2'});
    });

    test('ספרים מעבר לגודל האצווה נשלחים באצוות נוספות', () async {
      final books = officialBooks(20);

      await repository.indexAllBooks(libraryOf(books), onProgress: (_, _) {});

      expect(engine.batches.first.length, 16);
      expect(engine.batches.expand((batch) => batch).length, 20);
      expect(provider.indexedFilePaths.length, 20);
    });

    test('אחרי קריסה באמצע אינדוקס — ספר אחד לכל אצווה', () async {
      final dir = await Directory.systemTemp.createTemp('batch_canary');
      addTearDown(() => dir.delete(recursive: true));
      provider.activeIndexPath = p.join(dir.path, 'index');
      File(
        '${provider.activeIndexPath}.in_flight.json',
      ).writeAsStringSync(jsonEncode({'id:2': 1}));
      final books = officialBooks(3);

      await repository.indexAllBooks(libraryOf(books), onProgress: (_, _) {});

      expect(engine.batches, [
        ['id:1'],
        ['id:2'],
        ['id:3'],
      ]);
    });

    test('ספרי האצווה רשומים בקובץ הקריסות לפני המנוע (issue #3330)', () async {
      final dir = await Directory.systemTemp.createTemp('batch_canary');
      addTearDown(() => dir.delete(recursive: true));
      provider.activeIndexPath = p.join(dir.path, 'index');
      final file = File('${provider.activeIndexPath}.in_flight.json');
      Object? duringBatch;
      engine.duringBatch = (_, inputs) {
        duringBatch = jsonDecode(file.readAsStringSync());
        return inputs.length;
      };

      await repository.indexAllBooks(
        libraryOf(officialBooks(3)),
        onProgress: (_, _) {},
      );

      expect(duringBatch, {'id:1': 1, 'id:2': 1, 'id:3': 1});
      expect(jsonDecode(file.readAsStringSync()), isEmpty);
    });

    test('indexBooks משתמש באותה אצווה', () async {
      final books = officialBooks(2);

      final result = await repository.runIndexing(
        libraryOf(books),
        books: books,
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      expect(result.indexedBooks, 2);
      expect(engine.batches, [
        ['id:1', 'id:2'],
      ]);
      expect(engine.commitCount, 1);
    });

    group('textBookContentMatchesIndex', () {
      test('ספר רשמי נחתם במנוע בלי לטעון את הטקסט ל-Dart', () async {
        final calls = <int>[];
        IndexingRepository.libraryFingerprint =
            ({required source, required bookId, dbTitle, attachedSlug}) async {
              expect(source, LibraryBookSource.library_);
              calls.add(bookId);
              return BigInt.from(42);
            };
        final book = TextBook(id: 7, title: 'ז', categoryId: 1);

        expect(
          await repository.textBookContentMatchesIndex(book, BigInt.from(42)),
          isTrue,
        );
        expect(
          await repository.textBookContentMatchesIndex(book, BigInt.from(41)),
          isFalse,
        );
        expect(calls, [7, 7]);
        expect(repository.loadedTitles, isEmpty);
      });

      test('ספר שהמנוע לא מצא נבדק דרך Dart כמו קודם', () async {
        IndexingRepository.libraryFingerprint =
            ({required source, required bookId, dbTitle, attachedSlug}) async =>
                null;
        final book = TextBook(id: 7, title: 'ז', categoryId: 1);

        await repository.textBookContentMatchesIndex(book, BigInt.from(1));

        expect(repository.loadedTitles, ['ז']);
      });
    });
  });
}

Future<IndexingResourcePolicy> _testResources() async =>
    const IndexingResourcePolicy(
      cpuCount: 8,
      mobile: false,
      totalRamMb: 8192,
      availableRamMb: 4096,
    );

class _Repository extends IndexingRepository {
  _Repository(super.provider, {super.sampleResources = _testResources});

  final loadedTitles = <String>[];

  @override
  Future<
    ({
      Uint8List? bytes,
      String? text,
      int? libraryDbBookId,
      int? userBooksDbBookId,
      int? attachedDbBookId,
      Uint32List? dataUriLines,
    })
  >
  loadTextBookSource(TextBook book) async {
    loadedTitles.add(book.title);
    return (
      bytes: Uint8List.fromList([0xD7, 0x90]),
      text: null,
      libraryDbBookId: null,
      userBooksDbBookId: null,
      attachedDbBookId: null,
      dataUriLines: null,
    );
  }
}

class _FakeToken implements IndexingCancellationToken {
  bool _cancelled = false;

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isCancelled => _cancelled;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: $invocation');
}

class _Provider implements TantivyDataProvider {
  @override
  bool isEconomyIndexing = false;

  @override
  Future<void> setEconomyIndexing(bool enabled) async {
    isEconomyIndexing = enabled;
  }

  _Provider(this._engine);

  final _BatchEngine _engine;
  int reopenCount = 0;
  Future<void> Function()? beforeEngine;

  @override
  Future<bool> reopenIndex({bool force = false}) async {
    expect(force, isTrue);
    reopenCount++;
    indexedFilePaths
      ..clear()
      ..addAll(await _engine.getIndexedFilePaths());
    return true;
  }

  @override
  bool isTempFallback = false;

  @override
  final Set<String> indexedFilePaths = {};

  @override
  String? activeIndexPath;

  @override
  final ValueNotifier<bool> isIndexing = ValueNotifier<bool>(false);

  @override
  bool get requiresManualReindex => false;

  @override
  Future<SearchEngine> get engine async {
    final before = beforeEngine;
    beforeEngine = null;
    await before?.call();
    return _engine;
  }

  @override
  set engine(Future<SearchEngine> value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: $invocation');
}

/// כמו writer: commit חותם את מה שנוסף ולא נמחק עד אליו.
class _BatchEngine implements SearchEngine {
  final batches = <List<String>>[];
  final batchStorage = <String, TextStorage>{};
  final batchDbTitles = <String, String?>{};
  final batchSources = <String, LibraryBookSource>{};
  final batchSlugs = <String, String?>{};
  final statusById = <int, LibraryBookStatus>{};
  final bytesFilePaths = <String>[];
  final removedFilePaths = <String>[];
  final pending = <String>{};
  final committedFilePaths = <String>{};
  int commitCount = 0;
  int openWriterCalls = 0;
  Object? batchError;
  Object? batchDeleteError;
  int partialBatchBooks = 1;
  int rollbackCount = 0;
  final duplicateWrites = <String>[];

  /// נקרא בתוך האצווה; מחזיר כמה ספרים נוספו לפני העצירה.
  int Function(IndexingCancellationToken token, List<LibraryBookInput> inputs)?
  duringBatch;

  @override
  Future<void> openIndexWriter() async => openWriterCalls++;

  @override
  Future<BigInt> setBookOrder({required List<BookOrderEntry> entries}) async =>
      BigInt.one;

  @override
  Future<List<LibraryBookResult>> addLibraryBooks({
    required List<LibraryBookInput> books,
    required IndexingCancellationToken cancel,
  }) async {
    batches.add([for (final book in books) book.filePath]);
    final error = batchError;
    if (error != null) {
      pending.addAll(
        books.take(partialBatchBooks).map((book) => book.filePath),
      );
      throw error;
    }
    final addedBeforeStop = duringBatch?.call(cancel, books) ?? books.length;
    return [
      for (final (i, book) in books.indexed)
        _result(
          book,
          i < addedBeforeStop
              ? statusById[book.bookId] ?? LibraryBookStatus.indexed
              : LibraryBookStatus.cancelled,
        ),
    ];
  }

  LibraryBookResult _result(LibraryBookInput book, LibraryBookStatus status) {
    batchSources[book.filePath] = book.source;
    batchSlugs[book.filePath] = book.attachedSlug;
    if (status == LibraryBookStatus.indexed) {
      pending.add(book.filePath);
      batchStorage[book.filePath] = book.textStorage;
      batchDbTitles[book.filePath] = book.dbTitle;
    }
    return LibraryBookResult(
      bookId: book.bookId,
      status: status,
      docs: status == LibraryBookStatus.indexed ? 3 : 0,
      textStorage: book.textStorage,
      contentHash: BigInt.zero,
      textHash: BigInt.zero,
      bookNumber: 1,
      metadataHash: BigInt.zero,
      sourceHash: book.sourceHash ?? BigInt.zero,
    );
  }

  @override
  Future<int> addTextBookBytes({
    required String title,
    required String topics,
    required String filePath,
    required List<int> text,
    BigInt? sourceHash,
    List<String>? extraFacets,
    required TextStorage textStorage,
    Uint32List? storedLines,
  }) async {
    if (pending.contains(filePath)) duplicateWrites.add(filePath);
    bytesFilePaths.add(filePath);
    pending.add(filePath);
    return 1;
  }

  @override
  Future<void> deleteDocumentsByFilePaths({
    required List<String> filePaths,
  }) async {
    if (filePaths.length > 1 && batchDeleteError != null) {
      throw batchDeleteError!;
    }
    removedFilePaths.addAll(filePaths);
    pending.removeAll(filePaths);
  }

  @override
  Future<void> commit() async {
    commitCount++;
    committedFilePaths.addAll(pending);
    pending.clear();
  }

  @override
  Future<void> optimize() async {}

  @override
  Future<void> rollback() async {
    rollbackCount++;
    pending.clear();
  }

  @override
  Future<List<String>> getIndexedFilePaths() async =>
      committedFilePaths.toList();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: $invocation');
}
