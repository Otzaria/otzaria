import 'package:bloc_test/bloc_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';

import '../helpers/memory_settings_cache.dart';

class _FakeRepository implements FindRefRepository {
  @override
  bool get respectHiddenLibrary => false;

  @override
  Stream<void> get userBooksChanges => const Stream.empty();

  _FakeRepository(this._error);

  final Object _error;

  @override
  void cancelPendingSearch() {}

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async => throw _error;

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _book = BookCacheEntry(
  id: 1,
  title: 'בראשית',
  filePath: '',
  fileType: 'txt',
  categoryId: 2,
  orderIndex: 0.0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // בקשה בלי ערך מפורש לספרים אישיים קוראת את ההגדרה השמורה.
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    ReferenceBooksCache.instance.clear();
    BooksCache.instance.clear();
    AcronymsCache.instance.clear();
    ReferenceBooksCache.instance.categoriesProviderOverride = null;
  });

  tearDown(() {
    ReferenceBooksCache.instance.clear();
    BooksCache.instance.clear();
    AcronymsCache.instance.clear();
    ReferenceBooksCache.instance.categoriesProviderOverride = null;
  });

  group('ReferenceBooksCache — זמינות הספרייה', () {
    test('מטמון הספרים לא נטען → isLoaded נשאר false', () async {
      final cache = ReferenceBooksCache.instance;

      await cache.warmUp();

      expect(
        cache.isLoaded,
        isFalse,
        reason: 'כשל זמני אינו נשמר כטעינה מוצלחת',
      );
    });

    test('ספרייה תקינה וריקה מסומנת כטעונה', () async {
      final cache = ReferenceBooksCache.instance;
      BooksCache.instance.setBooksForTesting(const []);

      await cache.warmUp();

      expect(cache.isLoaded, isTrue);
    });

    test('ה-DB עולה מאוחר יותר → ה-warmUp הבא מצליח', () async {
      final cache = ReferenceBooksCache.instance;

      await cache.warmUp();
      expect(cache.isLoaded, isFalse);

      // ה-DB חזר לאיתנו והספרים נטענו.
      BooksCache.instance.setBooksForTesting(const [_book]);
      await cache.warmUp();

      expect(
        cache.isLoaded,
        isTrue,
        reason: 'כשל זמני לא נשמר — אין צורך בהפעלה מחדש של התוכנה',
      );
    });
  });

  group('FindRefRepository — מבדיל בין "לא מוכן" ל"לא נמצא"', () {
    test(
      'קאש שלא נטען אחרי warmUp → ReferenceLibraryNotReadyException',
      () async {
        final repository = FindRefRepository(
          isReferenceBooksCacheLoaded: () => false,
          warmUpReferenceBooksCache: () async {}, // warmUp שנכשל בשקט
          libraryDatabaseExists: () async => true,
        );

        await expectLater(
          repository.findRefs('בראשית פרק א'),
          throwsA(isA<ReferenceLibraryNotReadyException>()),
        );
      },
    );

    test('אין קובץ ספרייה → ReferenceLibraryMissingException', () async {
      final repository = FindRefRepository(
        isReferenceBooksCacheLoaded: () => false,
        warmUpReferenceBooksCache: () async {},
        libraryDatabaseExists: () async => false,
      );

      await expectLater(
        repository.findRefs('בראשית פרק א'),
        throwsA(isA<ReferenceLibraryMissingException>()),
      );
    });

    test(
      'אין קובץ ספרייה גם כשפונקציית TOC מוזרקת (כמו ב-factory) → Missing',
      () async {
        final repository = FindRefRepository(
          isReferenceBooksCacheLoaded: () => false,
          warmUpReferenceBooksCache: () async {},
          libraryDatabaseExists: () async => false,
          getTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async =>
              const <Map<String, dynamic>>[],
        );

        await expectLater(
          repository.findRefs('בראשית פרק א'),
          throwsA(isA<ReferenceLibraryMissingException>()),
        );
      },
    );

    test(
      'קאש טעון → אין חריגה, מוחזרת רשימה (ריקה = באמת אין תוצאות)',
      () async {
        var warmUpCalls = 0;
        final repository = FindRefRepository(
          isReferenceBooksCacheLoaded: () => true,
          warmUpReferenceBooksCache: () async => warmUpCalls++,
          searchReferenceBooks: (query, {int limit = 50}) =>
              const <ReferenceBookHit>[],
          getTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async =>
              const <Map<String, dynamic>>[],
        );

        await expectLater(repository.findRefs('ספר שאינו קיים'), completes);
        expect(warmUpCalls, 0, reason: 'קאש טעון לא מפעיל warmUp מיותר');
      },
    );
  });

  group('FindRefBloc — מצב "לא מוכן" נפרד משגיאה', () {
    blocTest<FindRefBloc, FindRefState>(
      'ReferenceLibraryNotReadyException → FindRefNotReady',
      build: () => FindRefBloc(
        findRefRepository: _FakeRepository(
          const ReferenceLibraryNotReadyException(),
        ),
      ),
      act: (bloc) => bloc.add(const SearchRefRequested('בראשית')),
      wait: const Duration(milliseconds: 400),
      expect: () => [isA<FindRefLoading>(), isA<FindRefNotReady>()],
    );

    blocTest<FindRefBloc, FindRefState>(
      'ReferenceLibraryMissingException → FindRefLibraryMissing',
      build: () => FindRefBloc(
        findRefRepository: _FakeRepository(
          const ReferenceLibraryMissingException(),
        ),
      ),
      act: (bloc) => bloc.add(const SearchRefRequested('בראשית')),
      wait: const Duration(milliseconds: 400),
      expect: () => [isA<FindRefLoading>(), isA<FindRefLibraryMissing>()],
    );

    blocTest<FindRefBloc, FindRefState>(
      'חריגה אחרת עדיין מגיעה כ-FindRefError',
      build: () =>
          FindRefBloc(findRefRepository: _FakeRepository(Exception('boom'))),
      act: (bloc) => bloc.add(const SearchRefRequested('בראשית')),
      wait: const Duration(milliseconds: 400),
      expect: () => [isA<FindRefLoading>(), isA<FindRefError>()],
    );
  });
}
