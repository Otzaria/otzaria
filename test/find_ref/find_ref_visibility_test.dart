import 'dart:async';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_visibility.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

import '../helpers/memory_settings_cache.dart';

class _TestDataRepository extends DataRepository {
  _TestDataRepository(this.testLibrary);

  final Library testLibrary;
  int libraryReads = 0;

  @override
  Future<Library> get library async {
    libraryReads++;
    return testLibrary;
  }
}

/// סופר קריאות של מפתח ההסתרה — כל load() של HiddenLibraryStore קורא אותו פעם אחת.
class _CountingSettingsCache extends MemorySettingsCache {
  int hiddenBookKeyReads = 0;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    if (key == HiddenLibraryStore.bookKeysSetting) hiddenBookKeyReads++;
    return super.getValue<T>(key, defaultValue: defaultValue);
  }

  @override
  String? getString(String key, {String? defaultValue}) {
    if (key == HiddenLibraryStore.bookKeysSetting) hiddenBookKeyReads++;
    return super.getString(key, defaultValue: defaultValue);
  }
}

ReferenceBookHit _hit(int id, String title) => ReferenceBookHit(
  bookId: id,
  title: title,
  normalizedTitle: title,
  filePath: '',
  fileType: 'txt',
  matchRank: 0,
  orderIndex: id.toDouble(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = HiddenLibraryStore();
  late Library library;
  late Category category;
  late TextBook hidden;
  late TextBook visible;
  late _TestDataRepository data;

  final settingsCache = _CountingSettingsCache();

  setUpAll(() async {
    await Settings.init(cacheProvider: settingsCache);
  });

  setUp(() async {
    await store.save(const HiddenLibrarySelection());
    library = Library(categories: []);
    category = Category(
      title: 'תורה',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: library,
    );
    library.subCategories.add(category);
    hidden = TextBook(
      id: 1,
      title: 'בראשית',
      category: category,
      categoryId: 11,
    );
    visible = TextBook(
      id: 2,
      title: 'בראשית',
      category: category,
      categoryId: 12,
    );
    category.books.addAll([hidden, visible]);
    data = _TestDataRepository(library);
  });

  test('מזהה מוסתר לפי מזהה גם כשכותרת זהה נשארת גלויה', () {
    final visibility = FindRefVisibility(
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(hidden)}),
      library,
    );
    expect(visibility.allowsCandidate(BookSource.official, 1, ''), isFalse);
    expect(visibility.allowsCandidate(BookSource.official, 2, ''), isTrue);
    expect(visibility.allowsCommentator('בראשית', 1), isFalse);
    expect(visibility.allowsCommentator('בראשית', 2), isTrue);
    expect(visibility.allowsCommentator('בראשית', null), isFalse);
    expect(visibility.allowsCandidate(BookSource.user, 1, ''), isTrue);
  });

  test('קטגוריית אב מסננת מועמד מתת קטגוריה לפני איתור תוכן', () async {
    final child = Category(
      title: 'חומשים',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: category,
    );
    category.subCategories.add(child);
    final nested = TextBook(
      id: 3,
      title: 'שמות',
      category: child,
      categoryId: 13,
    );
    child.books.add(nested);
    final visibility = FindRefVisibility(
      HiddenLibrarySelection(categoryPaths: {category.path}),
      library,
    );
    expect(visibility.allowsCandidate(BookSource.official, 3, ''), isFalse);
    final sibling = Category(
      title: 'נביאים',
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: [],
      books: [TextBook(id: 4, title: 'שמות')],
      parent: library,
    );
    library.subCategories.add(sibling);
    await store.save(HiddenLibrarySelection(categoryPaths: {category.path}));
    final repository = FindRefRepository(
      dataRepository: data,
      respectHiddenLibrary: true,
      isReferenceBooksCacheLoaded: () => true,
      searchReferenceBooks: (_, {limit = 50}) => [
        _hit(3, 'שמות'),
        _hit(4, 'שמות'),
      ],
      getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
    );
    addTearDown(repository.dispose);
    expect((await repository.findRefs('שמות')).map((r) => r.bookId), [4]);
  });

  test('בחירת ההסתרה נקראת מההגדרות פעם אחת לשאילתה', () async {
    await store.save(
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(hidden)}),
    );
    final repository = FindRefRepository(
      dataRepository: data,
      respectHiddenLibrary: true,
      isReferenceBooksCacheLoaded: () => true,
      searchReferenceBooks: (_, {limit = 50}) => [
        _hit(1, 'בראשית'),
        _hit(2, 'בראשית'),
      ],
      getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
    );
    addTearDown(repository.dispose);

    settingsCache.hiddenBookKeyReads = 0;
    expect((await repository.findRefs('בראשית')).map((r) => r.bookId), [2]);
    expect(settingsCache.hiddenBookKeyReads, 1);
  });

  test('זהות המקור והנתיב שומרים על ספרים בעלי מזהה או שם משותף', () {
    final personal = TextBook(
      id: 1,
      title: 'בראשית',
      source: BookSource.user,
      category: category,
    );
    final pdf = PdfBook(
      title: 'קובץ',
      path: '/library/hidden.pdf',
      category: category,
    );
    category.books.addAll([personal, pdf]);
    final visibility = FindRefVisibility(
      HiddenLibrarySelection(
        bookKeys: {
          PerBookSettings.bookKey(hidden),
          PerBookSettings.bookKey(pdf),
        },
      ),
      library,
    );
    expect(visibility.allowsCandidate(BookSource.official, 1, ''), isFalse);
    expect(visibility.allowsCandidate(BookSource.user, 1, ''), isTrue);
    expect(
      visibility.allowsCandidate(BookSource.official, -1, pdf.path),
      isFalse,
    );
    expect(visibility.allowsCommentator('בראשית', null), isFalse);
  });

  test('הסתרת PDF של בבלי אינה מסתירה ספר טקסט ומפרשים עם אותו מזהה', () {
    final pdf = PdfBook(
      id: hidden.id,
      title: hidden.title,
      path: '/library/bavli.pdf',
      category: category,
    );
    category.books.add(pdf);
    final visibility = FindRefVisibility(
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(pdf)}),
      library,
    );
    expect(
      visibility.allowsCandidate(BookSource.official, hidden.id!, ''),
      isTrue,
    );
    expect(visibility.allowsCommentator(hidden.title, hidden.id), isTrue);
    expect(
      visibility.allowsCandidate(
        BookSource.official,
        hidden.id!,
        '',
        fileType: 'pdf',
      ),
      isFalse,
    );
    expect(
      visibility.allowsCandidate(
        BookSource.official,
        hidden.id!,
        pdf.path,
        fileType: 'pdf',
      ),
      isFalse,
    );
  });

  test('הסתרת ספר טקסט אינה מסתירה PDF בעל אותו מזהה וכותרת', () {
    final pdf = PdfBook(
      id: hidden.id,
      title: hidden.title,
      path: '/library/bavli.pdf',
      category: category,
    );
    category.books.add(pdf);
    final visibility = FindRefVisibility(
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(hidden)}),
      library,
    );
    expect(
      visibility.allowsCandidate(BookSource.official, hidden.id!, ''),
      isFalse,
    );
    expect(visibility.allowsCommentator(hidden.title, hidden.id), isFalse);
    expect(
      visibility.allowsCandidate(
        BookSource.official,
        hidden.id!,
        '',
        fileType: 'pdf',
      ),
      isTrue,
    );
    expect(
      visibility.allowsCandidate(
        BookSource.official,
        hidden.id!,
        pdf.path,
        fileType: 'pdf',
      ),
      isTrue,
    );
  });

  test('ספר אישי גלוי אינו חושף מפרש רשמי מוסתר בעל אותו שם', () {
    category.books.remove(visible);
    category.books.add(
      TextBook(
        id: 1,
        title: 'בראשית',
        source: BookSource.user,
        category: category,
      ),
    );
    final visibility = FindRefVisibility(
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(hidden)}),
      library,
    );
    expect(visibility.allowsCommentator('בראשית', null), isFalse);
  });

  test('זהויות ספרים אישיים ומסדים מצורפים אינן מתנגשות', () {
    final source = BookSource.attached('one');
    final otherSource = BookSource.attached('two');
    final personal = TextBook(
      id: 1,
      title: 'שלי',
      source: BookSource.user,
      category: category,
    );
    final attached = TextBook(
      id: 1,
      title: 'מצורף',
      source: source,
      category: category,
    );
    category.books.addAll([personal, attached]);
    final visibility = FindRefVisibility(
      HiddenLibrarySelection(
        bookKeys: {
          PerBookSettings.bookKey(personal),
          PerBookSettings.bookKey(attached),
        },
      ),
      library,
    );
    expect(visibility.allowsCandidate(BookSource.user, 1, ''), isFalse);
    expect(visibility.allowsCandidate(source, 1, ''), isFalse);
    expect(visibility.allowsCandidate(otherSource, 1, ''), isTrue);
  });

  test('סינון PDF בקאש קודם לתקרת התוצאות', () {
    final hiddenPdf = PdfBook(
      title: 'כרך',
      path: '/library/hidden.pdf',
      category: category,
    );
    final visiblePdf = PdfBook(
      title: 'כרך',
      path: '/library/visible.pdf',
      category: category,
    );
    category.books.addAll([hiddenPdf, visiblePdf]);
    final visibility = FindRefVisibility(
      HiddenLibrarySelection(
        bookKeys: {PerBookSettings.bookKey(hiddenPdf)},
      ),
      library,
    );
    final cache = ReferenceBooksCache.instance;
    cache.clear();
    cache.setFsPdfBooksForTesting([
      (
        'כרך',
        ReferenceBookHit(
          bookId: -1,
          title: 'כרך',
          normalizedTitle: 'כרך',
          filePath: hiddenPdf.path,
          fileType: 'pdf',
          matchRank: 0,
          orderIndex: 0,
        ),
      ),
      (
        'כרך',
        ReferenceBookHit(
          bookId: -1,
          title: 'כרך',
          normalizedTitle: 'כרך',
          filePath: visiblePdf.path,
          fileType: 'pdf',
          matchRank: 0,
          orderIndex: 1,
        ),
      ),
    ]);
    addTearDown(cache.clear);
    final hits = cache.search(
      'כרך',
      limit: 1,
      allowsBook: (id, path, type) => visibility.allowsCandidate(
        BookSource.official,
        id,
        path,
        fileType: type,
      ),
    );
    expect(hits.map((hit) => hit.filePath), [visiblePdf.path]);
  });

  test('קאש הייצור מסנן ספר טקסט מוסתר לפני limit ומחזיר את הגלוי', () async {
    final cache = ReferenceBooksCache.instance;
    BooksCache.instance.setBooksForTesting(const [
      BookCacheEntry(
        id: 1,
        title: 'בראשית',
        filePath: null,
        fileType: 'txt',
        categoryId: 11,
        orderIndex: 0,
      ),
      BookCacheEntry(
        id: 2,
        title: 'בראשית',
        filePath: null,
        fileType: 'txt',
        categoryId: 12,
        orderIndex: 1,
      ),
    ]);
    cache.seedForTesting(
      normalizedTitles: {1: 'בראשית', 2: 'בראשית'},
      categoryPaths: {1: 'תורה', 2: 'תורה'},
    );
    addTearDown(() {
      cache.clear();
      BooksCache.instance.clear();
    });
    await store.save(
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(hidden)}),
    );
    final visibility = FindRefVisibility(store.load(), library);
    final hits = cache.search(
      'בראשית',
      limit: 1,
      allowsBook: (id, path, type) => visibility.allowsCandidate(
        BookSource.official,
        id,
        path,
        fileType: type,
      ),
    );
    expect(hits.map((hit) => hit.bookId), [2]);

    final repository = FindRefRepository(
      dataRepository: data,
      respectHiddenLibrary: true,
      getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
      searchAltTocFlatEntries: (_, {maxRefTokens}) async => const [],
    );
    addTearDown(repository.dispose);
    expect((await repository.findRefs('בראשית')).map((r) => r.bookId), [2]);
  });

  test('קאש הייצור מבדיל בין טקסט ל־PDF שחולקים מזהה', () async {
    final pdf = PdfBook(
      id: hidden.id,
      title: hidden.title,
      path: '/library/bavli.pdf',
      category: category,
    );
    category.books.add(pdf);
    BooksCache.instance.setBooksForTesting(const [
      BookCacheEntry(
        id: 1,
        title: 'בראשית',
        filePath: null,
        fileType: 'txt',
        categoryId: 11,
        orderIndex: 0,
      ),
    ]);
    final cache = ReferenceBooksCache.instance;
    cache.seedForTesting(
      normalizedTitles: {1: 'בראשית'},
      categoryPaths: {1: 'תורה'},
    );
    cache.setFsPdfBooksForTesting([
      (
        'בראשית',
        ReferenceBookHit(
          bookId: -1,
          title: 'בראשית',
          normalizedTitle: 'בראשית',
          filePath: pdf.path,
          fileType: 'pdf',
          matchRank: 0,
          orderIndex: 1,
        ),
      ),
    ]);
    addTearDown(() {
      cache.clear();
      BooksCache.instance.clear();
    });
    final repository = FindRefRepository(
      dataRepository: data,
      respectHiddenLibrary: true,
      getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
      searchAltTocFlatEntries: (_, {maxRefTokens}) async => const [],
    );
    addTearDown(repository.dispose);

    await store.save(
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(pdf)}),
    );
    final textResults = await repository.findRefs('בראשית');
    expect(textResults.map((r) => r.bookId), [hidden.id]);
    expect(textResults.single.filePath, isEmpty);

    await store.save(
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(hidden)}),
    );
    final pdfResults = await repository.findRefs('בראשית');
    expect(pdfResults.map((r) => r.bookId), [-1]);
    expect(pdfResults.single.filePath, pdf.path);
  });

  test('מועמדים מוסתרים אינם מגיעים לדירוג או ל־AltToc', () async {
    await store.save(
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(hidden)}),
    );
    final repository = FindRefRepository(
      dataRepository: data,
      respectHiddenLibrary: true,
      isReferenceBooksCacheLoaded: () => true,
      searchReferenceBooks: (_, {limit = 50}) => [
        _hit(1, 'בראשית'),
        _hit(2, 'בראשית'),
      ],
      getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
      searchAltTocFlatEntries: (_, {maxRefTokens}) async => [
        {
          'bookId': 1,
          'bookTitle': 'בראשית',
          'reference': 'נח',
          'segment': 1,
          'level': 1,
        },
        {
          'bookId': 2,
          'bookTitle': 'בראשית',
          'reference': 'נח',
          'segment': 2,
          'level': 1,
        },
      ],
    );
    addTearDown(repository.dispose);

    final books = await repository.findRefs('בראשית');
    expect(books, isNotEmpty);
    expect(books.every((r) => r.bookId == 2), isTrue);
    final alt = await repository.findRefs('נח');
    expect(alt, isNotEmpty);
    expect(alt.every((r) => r.bookId == 2), isTrue);
  });

  test('ספר אישי מוסתר מסונן בלי להסתיר ספר רשמי בעל אותו מזהה', () async {
    final personal = TextBook(
      id: 1,
      title: 'בראשית',
      source: BookSource.user,
      category: category,
    );
    category.books.add(personal);
    await store.save(
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(personal)}),
    );
    final repository = FindRefRepository(
      dataRepository: data,
      respectHiddenLibrary: true,
      isReferenceBooksCacheLoaded: () => true,
      searchReferenceBooks: (_, {limit = 50}) => [_hit(1, 'בראשית')],
      getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
      getAllUserBooks: () async => [
        (
          id: 1,
          title: 'בראשית',
          filePath: null,
          fileType: 'txt',
          orderIndex: 0.0,
          folderTitles: <String>[],
        ),
      ],
    );
    addTearDown(repository.dispose);
    final refs = await repository.findRefs(
      'בראשית',
      includePersonalBooks: true,
    );
    expect(refs.map((r) => (r.source, r.bookId)), [
      (BookSource.official, 1),
    ]);
  });

  test('שינוי הסתרה מעדכן חיפוש חי ומטמון מפרשים', () async {
    final repository = FindRefRepository(
      dataRepository: data,
      respectHiddenLibrary: true,
      isReferenceBooksCacheLoaded: () => true,
      searchReferenceBooks: (_, {limit = 50}) => [
        _hit(1, 'בראשית'),
        _hit(2, 'בראשית'),
      ],
      getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
      fetchCommentatorRows: (_) async => [
        {'targetBookTitle': 'בראשית', 'targetBookId': 1},
        {'targetBookTitle': 'בראשית', 'targetBookId': 2},
      ],
    );
    addTearDown(repository.dispose);
    expect((await repository.findRefs('בראשית')).length, 2);
    final ref = (await repository.findRefs('בראשית')).first;
    expect((await repository.getCommentatorsForResult(ref)).length, 2);

    await store.save(
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(hidden)}),
    );
    expect((await repository.findRefs('בראשית')).map((r) => r.bookId), [2]);
    expect(
      (await repository.getCommentatorsForResult(ref)).map((e) => e.bookId),
      [2],
    );

    await store.save(const HiddenLibrarySelection());
    expect((await repository.findRefs('בראשית')).length, 2);
    expect((await repository.getCommentatorsForResult(ref)).length, 2);
  });

  test('שינוי הסתרה בזמן שליפת מפרשים אינו שומר מטמון ישן', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    var fetches = 0;
    final repository = FindRefRepository(
      dataRepository: data,
      respectHiddenLibrary: true,
      fetchCommentatorRows: (_) async {
        fetches++;
        started.complete();
        await gate.future;
        return [
          {'targetBookTitle': hidden.title, 'targetBookId': hidden.id},
          {'targetBookTitle': visible.title, 'targetBookId': visible.id},
        ];
      },
    );
    addTearDown(repository.dispose);
    final ref = DbReferenceResult(
      title: 'בראשית',
      reference: 'בראשית פרק א',
      segment: 1,
      bookId: 2,
    );
    final pending = repository.getCommentatorsForResult(ref);
    await started.future;
    await store.save(
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(hidden)}),
    );
    gate.complete();
    expect((await pending).map((e) => e.bookId), [visible.id]);
    expect(
      (await repository.getCommentatorsForResult(ref)).map((e) => e.bookId),
      [visible.id],
    );
    expect(fetches, 1);
  });

  test('ללא הסתרות לא נבנה צילום עץ בכל הקלדה', () async {
    final repository = FindRefRepository(
      dataRepository: data,
      respectHiddenLibrary: true,
      isReferenceBooksCacheLoaded: () => true,
      searchReferenceBooks: (_, {limit = 50}) => [_hit(1, 'בראשית')],
      getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
    );
    addTearDown(repository.dispose);
    await repository.findRefs('בראשית');
    await repository.findRefs('בראשית');
    expect(data.libraryReads, 0);
  });

  test('מסלול תוסף אינו מסנן ספרים מוסתרים', () async {
    await store.save(
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(hidden)}),
    );
    final repository = FindRefRepository(
      dataRepository: data,
      isReferenceBooksCacheLoaded: () => true,
      searchReferenceBooks: (_, {limit = 50}) => [
        _hit(1, 'בראשית'),
        _hit(2, 'בראשית'),
      ],
      getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
    );
    addTearDown(repository.dispose);
    expect((await repository.findRefs('בראשית')).length, 2);
  });
}
