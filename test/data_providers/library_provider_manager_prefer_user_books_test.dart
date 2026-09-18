import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';

/// Provider פיקטיבי שמחזיר ערכי tag לפי דגל isUserBook של ה-key.
class _FakeProvider implements LibraryProvider {
  final String _providerId;
  final String _displayName;
  final String _sourceIndicator;
  final Map<BookCompositeKey, String> _bookTextByKey;
  final Map<BookCompositeKey, List<TocEntry>> _bookTocByKey;

  _FakeProvider({
    required this._providerId,
    required this._displayName,
    required this._sourceIndicator,
    Map<BookCompositeKey, String>? bookTextByKey,
    Map<BookCompositeKey, List<TocEntry>>? bookTocByKey,
  }) : _bookTextByKey = bookTextByKey ?? {},
       _bookTocByKey = bookTocByKey ?? {};

  @override
  String get providerId => _providerId;

  @override
  String get displayName => _displayName;

  @override
  String get sourceIndicator => _sourceIndicator;

  @override
  int get priority => 1;

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    return {};
  }

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async {
    return _bookTextByKey.keys.any(
      (k) =>
          k.title == title &&
          k.categoryId == categoryId &&
          k.fileType == fileType,
    );
  }

  /// מדמה את ההתנהגות של DatabaseLibraryProvider: קודם מנסה את הוריאנט
  /// המועדף (לפי `preferSource`), ואז fallback לוריאנט השני.
  T? _lookupPreferred<T>(
    Map<BookCompositeKey, T> map,
    String title,
    int categoryId,
    String fileType,
    BookSource preferSource,
  ) {
    final preferred = BookCompositeKey.create(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      source: preferSource,
    );
    if (map.containsKey(preferred)) return map[preferred];

    final fallback = BookCompositeKey.create(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      source: preferSource.isUser ? BookSource.official : BookSource.user,
    );
    return map[fallback];
  }

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    return _lookupPreferred(
      _bookTextByKey,
      title,
      categoryId,
      fileType,
      preferSource,
    );
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    return _lookupPreferred(
      _bookTocByKey,
      title,
      categoryId,
      fileType,
      preferSource,
    );
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async {
    return _bookTextByKey.keys.map((k) => k.toStorageKey()).toSet();
  }

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    return Library(categories: []);
  }

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async {
    return const [];
  }

  @override
  Future<String> getLinkContent(Link link) async {
    return '';
  }
}

void main() {
  final manager = LibraryProviderManager.instance;

  tearDown(() {
    manager.resetForTesting();
    DatabaseLibraryProvider.instance.clearCache();
    FileSystemLibraryProvider.instance.resetForTesting();
  });

  group('LibraryProviderManager — preferSource routing', () {
    test(
      'getBookText: מקור מצורף מועדף מחזיר את הוריאנט שלו, ואינו נופל לרשמי',
      () async {
        final attached = BookSource.attached('lib');
        final officialKey = BookCompositeKey.create(
          title: 'משותף',
          categoryId: 7,
          fileType: 'txt',
        );
        final attachedKey = BookCompositeKey.create(
          title: 'משותף',
          categoryId: 7,
          fileType: 'txt',
          source: attached,
        );
        final provider = _FakeProvider(
          providerId: 'db',
          displayName: 'DB',
          sourceIndicator: 'DB',
          bookTextByKey: {officialKey: 'תוכן רשמי', attachedKey: 'תוכן מצורף'},
        );
        manager.seedMappingsForTesting(
          mapping: {officialKey: provider, attachedKey: provider},
          providers: [provider],
        );

        expect(
          await manager.getBookText(
            'משותף',
            categoryId: 7,
            fileType: 'txt',
            preferSource: attached,
          ),
          'תוכן מצורף',
        );
        expect(
          await manager.getBookText('משותף', categoryId: 7, fileType: 'txt'),
          'תוכן רשמי',
        );
        expect(
          await manager.getBookText(
            'משותף',
            fileType: 'txt',
            preferSource: BookSource.attached('other'),
          ),
          isNull,
        );
      },
    );

    test(
      'getBookText: אותם title+categoryId+fileType בשני וריאנטים → '
      'preferUserBooks=true מחזיר את ה-user_books, false את ה-seforim',
      () async {
        // אותו 3-tuple (title, categoryId, fileType) רשום פעמיים, פעם עם
        // isUserBook=true ופעם false. ה-resolver של המנהל חייב להחזיר את
        // הוריאנט הנכון לפי הדגל.
        final officialKey = BookCompositeKey.create(
          title: 'משותף',
          categoryId: 7,
          fileType: 'txt',
          source: BookSource.official,
        );
        final userBookKey = BookCompositeKey.create(
          title: 'משותף',
          categoryId: 7,
          fileType: 'txt',
          source: BookSource.user,
        );
        final provider = _FakeProvider(
          providerId: 'db',
          displayName: 'DB',
          sourceIndicator: 'DB',
          bookTextByKey: {
            officialKey: 'תוכן רשמי',
            userBookKey: 'תוכן משתמש',
          },
        );

        manager.seedMappingsForTesting(
          mapping: {
            officialKey: provider,
            userBookKey: provider,
          },
          providers: [provider],
        );

        final official = await manager.getBookText(
          'משותף',
          categoryId: 7,
          fileType: 'txt',
        );
        final userBook = await manager.getBookText(
          'משותף',
          categoryId: 7,
          fileType: 'txt',
          preferSource: BookSource.user,
        );

        expect(official, 'תוכן רשמי');
        expect(userBook, 'תוכן משתמש');
      },
    );

    test(
      'getBookText: כשרשום רק וריאנט user_books, preferUserBooks=false עדיין מוצא אותו',
      () async {
        // אם הקורא לא ביקש user_books, אבל מה שיש זה רק user_books — המנהל
        // צריך עדיין למצוא את הספר במעבר השני (fallback ל-!preferUserBooks).
        final userBookKey = BookCompositeKey.create(
          title: 'רק-משתמש',
          categoryId: 9,
          fileType: 'txt',
          source: BookSource.user,
        );
        final provider = _FakeProvider(
          providerId: 'db',
          displayName: 'DB',
          sourceIndicator: 'DB',
          bookTextByKey: {userBookKey: 'תוכן משתמש'},
        );

        manager.seedMappingsForTesting(
          mapping: {userBookKey: provider},
          providers: [provider],
        );

        final text = await manager.getBookText(
          'רק-משתמש',
          categoryId: 9,
          fileType: 'txt',
          // ברירת מחדל — לא ביקש user_books, אבל נתון יחיד שיש לנו
        );

        expect(
          text,
          'תוכן משתמש',
          reason: 'fallback למפתח user_books כשאין וריאנט רשמי תואם',
        );
      },
    );

    test(
      'getBookText: כשרשום רק וריאנט רשמי, preferUserBooks=true עדיין מוצא אותו',
      () async {
        final officialKey = BookCompositeKey.create(
          title: 'רק-רשמי',
          categoryId: 9,
          fileType: 'txt',
          source: BookSource.official,
        );
        final provider = _FakeProvider(
          providerId: 'db',
          displayName: 'DB',
          sourceIndicator: 'DB',
          bookTextByKey: {officialKey: 'תוכן רשמי'},
        );

        manager.seedMappingsForTesting(
          mapping: {officialKey: provider},
          providers: [provider],
        );

        final text = await manager.getBookText(
          'רק-רשמי',
          categoryId: 9,
          fileType: 'txt',
          preferSource: BookSource.user,
        );

        expect(
          text,
          'תוכן רשמי',
          reason: 'fallback למפתח רשמי כשאין וריאנט user_books תואם',
        );
      },
    );

    test(
      'getBookText: ללא categoryId — preferUserBooks מעדיף וריאנט user_books לפי כותרת בלבד',
      () async {
        // נכניס שני מפתחות עם categoryId שונה: אחד isUserBook=true, אחד false.
        // ה-manager צריך לבחור את ה-user_books כשמבוקש.
        final officialKey = BookCompositeKey.create(
          title: 'כותרת בלבד',
          categoryId: 100,
          fileType: 'txt',
          source: BookSource.official,
        );
        final userBookKey = BookCompositeKey.create(
          title: 'כותרת בלבד',
          categoryId: 200,
          fileType: 'txt',
          source: BookSource.user,
        );
        final provider = _FakeProvider(
          providerId: 'db',
          displayName: 'DB',
          sourceIndicator: 'DB',
          bookTextByKey: {
            officialKey: 'תוכן רשמי',
            userBookKey: 'תוכן משתמש',
          },
        );

        manager.seedMappingsForTesting(
          mapping: {
            officialKey: provider,
            userBookKey: provider,
          },
          providers: [provider],
        );

        final official = await manager.getBookText(
          'כותרת בלבד',
          fileType: 'txt',
        );
        final userBook = await manager.getBookText(
          'כותרת בלבד',
          fileType: 'txt',
          preferSource: BookSource.user,
        );

        // בלי categoryId, ה-resolver עובר ב-findIn לפי הסדר — וכש-preferUserBooks
        // אמת, הוא מסנן רק user_books בקריאה הראשונה.
        expect(
          userBook,
          'תוכן משתמש',
          reason:
              'preferUserBooks=true בוחר את הוריאנט המתאים גם בלי categoryId',
        );
        // ולהפך — בלי preferUserBooks, יכול לחזור כל מפתח שתואם. כאן עם
        // findIn((_) => true) המעבר עובר על המפתחות לפי סדר המפה — בלי דרישה
        // מי הראשון. הנקודה היא שלפחות אחד מהם חוזר ולא null.
        expect(
          official,
          anyOf('תוכן רשמי', 'תוכן משתמש'),
          reason: 'בלי דגל, כל וריאנט תואם הוא קביל',
        );
      },
    );

    test('getBookToc: אותה לוגיקת ניתוב כמו getBookText', () async {
      final officialKey = BookCompositeKey.create(
        title: 'משותף',
        categoryId: 5,
        fileType: 'txt',
        source: BookSource.official,
      );
      final userBookKey = BookCompositeKey.create(
        title: 'משותף',
        categoryId: 5,
        fileType: 'txt',
        source: BookSource.user,
      );
      final officialToc = <TocEntry>[TocEntry(text: 'רשמי', index: 0)];
      final userToc = <TocEntry>[TocEntry(text: 'משתמש', index: 0)];
      final provider = _FakeProvider(
        providerId: 'db',
        displayName: 'DB',
        sourceIndicator: 'DB',
        bookTocByKey: {
          officialKey: officialToc,
          userBookKey: userToc,
        },
      );

      manager.seedMappingsForTesting(
        mapping: {
          officialKey: provider,
          userBookKey: provider,
        },
        providers: [provider],
      );

      final official = await manager.getBookToc(
        'משותף',
        categoryId: 5,
        fileType: 'txt',
      );
      final userBook = await manager.getBookToc(
        'משותף',
        categoryId: 5,
        fileType: 'txt',
        preferSource: BookSource.user,
      );

      expect(official?.first.text, 'רשמי');
      expect(userBook?.first.text, 'משתמש');
    });
  });

  group('LibraryProviderManager — מיפוי ספרים לספקים', () {
    test(
      'ספרי קבצים אישיים (EPUB/DOCX) ממופים ל-DB provider ולא ל-FS',
      () async {
        final userEpub = EpubBook(
          title: 'ספר אישי',
          path: r'C:\books\a.epub',
          filePath: r'C:\books\a.epub',
          categoryId: 7,
          source: BookSource.user,
        );
        final officialPdf = PdfBook(
          title: 'ספר רשמי',
          path: r'C:\lib\b.pdf',
          categoryId: 8,
        );
        final category = Category(
          title: 'קטגוריה',
          description: '',
          shortDescription: '',
          subCategories: [],
          books: [userEpub, officialPdf],
          parent: null,
          order: 0,
        );
        final userEpubKey = BookCompositeKey.fromBook(userEpub)!;
        final officialPdfKey = BookCompositeKey.fromBook(officialPdf)!;

        manager.seedMappingsForTesting(mapping: {}, providers: []);
        manager.mapBooksForTesting(category, {userEpubKey});

        expect(
          manager.providerForKeyForTesting(userEpubKey),
          same(DatabaseLibraryProvider.instance),
          reason:
              'ספר משתמש file-backed חייב את ה-DB provider — '
              'ה-FS provider מכיר רק את הספרייה הראשית',
        );
        expect(
          manager.providerForKeyForTesting(officialPdfKey),
          same(FileSystemLibraryProvider.instance),
        );
      },
    );
  });
}
