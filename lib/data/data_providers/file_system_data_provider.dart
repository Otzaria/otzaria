import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:path/path.dart' as path;

/// A data provider that manages file system operations for the library.
///
/// This class handles all file system related operations including:
/// - Reading and parsing book content from every supported document format
/// - Managing the library structure (categories and books)
/// - Handling external book data from CSV files
/// - Managing book links and metadata
/// - Providing table of contents functionality
class FileSystemData {
  late String libraryPath;

  /// Future that resolves to metadata for all books and categories
  late Future<Map<String, Map<String, dynamic>>> metadata;

  Future<Map<String, String>>? _titleToPath;

  /// Library provider manager for coordinating multiple data sources
  final LibraryProviderManager _providerManager =
      LibraryProviderManager.instance;

  /// Creates a new instance of [FileSystemData] and starts loading metadata
  /// and initializing the providers.
  FileSystemData() {
    libraryPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '.';
    metadata = _getMetadata();
    _initializeProviders();
  }

  Future<Map<String, String>> get titleToPath =>
      _titleToPath ??= _getTitleToPath();

  /// Singleton instance of [FileSystemData]
  static FileSystemData instance = FileSystemData();

  /// Initializes the library providers
  Future<void> _initializeProviders() async {
    try {
      await _providerManager.initialize();
      debugPrint('Library providers initialized in FileSystemData');
    } catch (e) {
      debugPrint('Provider initialization failed: $e');
    }
  }

  Future<Map<String, String>> _getTitleToPath() async {
    await _providerManager.initialize();
    final keyToPath = await _providerManager.fileSystemProvider.keyToPath;
    final dbKeys = await _providerManager.databaseProvider
        .getDatabaseOnlyBookTitles();
    return buildTitleToPathMap(
      fileSystemKeyToPath: keyToPath,
      databaseKeys: dbKeys,
      resolveDatabaseCategoryPath: (key) {
        return _providerManager.databaseProvider.findCategoryPathForBook(
          key.title,
          categoryId: key.categoryId,
          fileType: key.fileType,
        );
      },
    );
  }

  @visibleForTesting
  static Future<Map<String, String>> buildTitleToPathMap({
    required Map<String, String> fileSystemKeyToPath,
    required Iterable<String> databaseKeys,
    required Future<String?> Function(BookCompositeKey key)
    resolveDatabaseCategoryPath,
  }) async {
    final result = <String, String>{};

    for (final entry in fileSystemKeyToPath.entries) {
      final key = BookCompositeKey.tryParse(entry.key);
      if (key == null) continue;
      result[key.title] = entry.value;
    }

    for (final rawKey in databaseKeys) {
      final key = BookCompositeKey.tryParse(rawKey);
      if (key == null) continue;
      final categoryPath = await resolveDatabaseCategoryPath(key);
      if (categoryPath == null || categoryPath.isEmpty) continue;
      result[key.title] = categoryPath;
    }

    return result;
  }

  /// Finds the category path for a book by its title.
  /// Checks in-memory cache first, then queries valid providers.
  Future<String?> findBookCategoryPath(String title, {int? categoryId}) async {
    await _providerManager.initialize();

    // 1. עם categoryId — פתרון ישיר לספר (~50ms) ולא `titleToPath` של כל
    // הספרייה (~950ms בעלייה קרה). הערך זהה: שתיהן דרך findCategoryPathForBook.
    if (categoryId != null) {
      final directPath = await _providerManager.databaseProvider
          .findCategoryPathForBook(title, categoryId: categoryId);
      if (directPath != null && directPath.isNotEmpty) return directPath;
    }

    // 2. Cached map; it may be stale if the DB loaded later, so step 3
    // re-checks the database provider.
    final path = (await titleToPath)[title];
    if (path != null && path.isNotEmpty) return path;

    // 3. Ask DatabaseProvider explicitly (covers categoryId == null too)
    final dbPath = await _providerManager.databaseProvider
        .findCategoryPathForBook(title, categoryId: categoryId);
    if (dbPath != null) return dbPath;

    return null;
  }

  /// מחזיר האם מותר למחוק את הספר דרך הספרייה.
  ///
  /// מותר רק לספרי משתמש מסוג "עותק עצמאי" (תוכנם שמור בתוכנה). ספר
  /// "קריאה מהקבצים" נמחק רק ע"י מחיקת הקובץ מהדיסק, והספרייה הרשמית אינה
  /// ניתנת למחיקה. fail-closed: מחזיר false בכל מקרה לא-ודאי.
  Future<bool> canDeleteUserBookFromLibrary({
    required String title,
    int? categoryId,
    String fileType = 'txt',
    required BookSource source,
  }) async {
    if (!source.isUser || categoryId == null) return false;
    return _providerManager.isUserBookContentInDb(title, categoryId, fileType);
  }

  /// Clears the book-in-database cache
  void clearBookCache() {
    _providerManager.clearCaches();
    _titleToPath = null;
    debugPrint('Book cache cleared');
  }

  /// Retrieves the complete library structure from the file system.
  ///
  /// Reads the library from the configured path and combines it with metadata
  /// to create a full [Library] object containing all categories and books.
  /// Uses LibraryProviderManager for unified catalog building.
  Future<Library> getLibrary() async {
    final tTotal = DateTime.now();
    final libraryDir = Directory(libraryPath);

    if (!libraryDir.existsSync()) {
      debugPrint('Library path does not exist: $libraryPath');
      return Library(categories: []);
    }

    // קבלת שם התיקייה מההגדרות
    final folderName =
        Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
        '';

    // בדיקה שתיקיית הספרים קיימת
    final otzariaPath = folderName.isEmpty
        ? libraryPath
        : path.join(libraryPath, folderName);
    final otzariaDir = Directory(otzariaPath);
    if (!otzariaDir.existsSync()) {
      debugPrint('Books directory does not exist: $otzariaPath');
      return Library(categories: []);
    }

    // OPTIMIZATION: Load metadata and initialize providers in parallel
    metadata = _getMetadata();
    final (metadataResult, _) = await (
      metadata,
      _providerManager.initialize(),
    ).wait;
    debugPrint(
      '⏱️ Metadata + providers init: ${DateTime.now().difference(tTotal).inMilliseconds}ms',
    );

    // Use the unified catalog builder from LibraryProviderManager
    final library = await _providerManager.buildLibraryCatalog(
      metadataResult,
      otzariaPath,
    );
    debugPrint(
      '⏱️ Total getLibrary: ${DateTime.now().difference(tTotal).inMilliseconds}ms',
    );
    return library;
  }

  /// Retrieves the list of books from Otzar HaChochma
  static Future<List<ExternalLibraryBook>> getOtzarBooks() async {
    return ExternalCatalogRepository.instance.getOtzarBooks();
  }

  /// Retrieves the list of books from HebrewBooks
  ///
  /// אם המשתמש הגדיר תיקיית ספרי היברובוקס מקומית, כל ספר שקובץ ה-PDF שלו
  /// קיים בתיקייה מוחזר כ-[PdfBook] (נפתח בצפיין המקומי) במקום כ-
  /// [ExternalLibraryBook] (שנפתח באתר היברובוקס).
  static Future<List<Book>> getHebrewBooks() async {
    final pdfFiles = await _scanHebrewBooksPdfFiles();
    final books = await ExternalCatalogRepository.instance.getHebrewBooks();
    if (pdfFiles.isEmpty) {
      return books;
    }
    return mapHebrewBooksToLocal(books, pdfFiles);
  }

  /// מחזיר רק את ספרי היברובוקס שקיים להם קובץ PDF מקומי (כ-[PdfBook]).
  ///
  /// ספרים אלו נמצאים פיזית במחשב ולכן נחשבים מקומיים — הם מוצגים בחיפוש
  /// תמיד, גם כשהגדרת "הצגת ספרים מאתרים חיצוניים" כבויה. אם לא הוגדרה
  /// תיקייה או שאין בה קבצי PDF — הקטלוג כלל אינו נטען (חיסכון ב-I/O).
  static Future<List<Book>> getLocalHebrewBooks() async {
    final pdfFiles = await _scanHebrewBooksPdfFiles();
    if (pdfFiles.isEmpty) {
      return const [];
    }
    // טוענים מהקטלוג רק את המזהים שיש להם קובץ מקומי — לא את כל הטבלה.
    final ids = extractHebrewBookIds(pdfFiles.keys);
    if (ids.isEmpty) {
      return const [];
    }
    final books = await ExternalCatalogRepository.instance.getHebrewBooksByIds(
      ids,
    );
    return mapHebrewBooksToLocal(books, pdfFiles).whereType<PdfBook>().toList();
  }

  /// מחלץ מזהי ספרי היברובוקס משמות קבצי PDF (lowercase).
  ///
  /// תומך בשתי תבניות השמות: `hebrewbooks_org_<id>.pdf` ו-`<id>.pdf`.
  /// שמות שאינם תואמים מתעלמים מהם.
  @visibleForTesting
  static Set<int> extractHebrewBookIds(Iterable<String> pdfFileNames) {
    final pattern = RegExp(r'^(?:hebrewbooks_org_)?(\d+)\.pdf$');
    final ids = <int>{};
    for (final name in pdfFileNames) {
      final match = pattern.firstMatch(name);
      if (match == null) {
        continue;
      }
      final id = int.tryParse(match.group(1)!);
      if (id != null) {
        ids.add(id);
      }
    }
    return ids;
  }

  /// סורק את תיקיית ספרי היברובוקס המוגדרת ובונה מפת שמות-קבצים.
  ///
  /// מחזיר מפה משם הקובץ (lowercase) לנתיב המלא, או מפה ריקה אם לא הוגדרה
  /// תיקייה או שאינה קיימת. סורק פעם אחת בלבד כדי להימנע מבדיקת קיום קובץ
  /// נפרדת לכל ספר בקטלוג.
  static Future<Map<String, String>> _scanHebrewBooksPdfFiles() async {
    final hebrewBooksPath = Settings.getValue<String>(
      SettingsRepository.keyHebrewBooksPath,
    );
    if (hebrewBooksPath == null || hebrewBooksPath.isEmpty) {
      return const {};
    }

    return scanHebrewBooksPdfFilesAtPath(hebrewBooksPath);
  }

  /// סורק תיקיית PDF ישירה או את שורש נתוני HebrewBooks שמכיל `Books`.
  @visibleForTesting
  static Future<Map<String, String>> scanHebrewBooksPdfFilesAtPath(
    String configuredPath,
  ) async {
    final configuredDir = Directory(configuredPath);
    final booksDir = Directory(path.join(configuredPath, 'Books'));
    final directories = [configuredDir, booksDir];
    final visited = <String>{};
    final pdfFiles = <String, String>{};

    for (final directory in directories) {
      final normalized = path.normalize(directory.absolute.path);
      if (!visited.add(normalized)) continue;
      // ב-Windows כונן לא מוכן זורק ב-exists() במקום להחזיר false.
      try {
        if (!await directory.exists()) continue;
        await for (final entity in directory.list()) {
          if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
            pdfFiles.putIfAbsent(
              path.basename(entity.path).toLowerCase(),
              () => entity.path,
            );
          }
        }
      } on FileSystemException {
        continue;
      }
    }
    return pdfFiles;
  }

  /// בדיקה נקודתית: אילו מהמזהים המבוקשים קיימים כקובצי PDF בתיקייה המוגדרת.
  ///
  /// בניגוד ל-[_scanHebrewBooksPdfFiles] שסורק את כל התיקייה ונשמר במטמון,
  /// כאן נבדקים רק המזהים המבוקשים — זול מספיק לקריאה בעת פתיחת ספר, ולכן
  /// מזהה גם קובץ שירד אחרי הסריקה האחרונה (הורדות שרצות ברקע).
  static Future<Map<String, String>> probeHebrewBooksPdfFilesByIds(
    Set<int> ids,
  ) async {
    final hebrewBooksPath = Settings.getValue<String>(
      SettingsRepository.keyHebrewBooksPath,
    );
    if (hebrewBooksPath == null || hebrewBooksPath.isEmpty || ids.isEmpty) {
      return const {};
    }
    final roots = [hebrewBooksPath, path.join(hebrewBooksPath, 'Books')];
    final pdfFiles = <String, String>{};
    try {
      for (final id in ids) {
        for (final name in ['$id.pdf', 'hebrewbooks_org_$id.pdf']) {
          for (final root in roots) {
            final file = File(path.join(root, name));
            if (await file.exists()) {
              pdfFiles.putIfAbsent(name, () => file.path);
              break;
            }
          }
        }
      }
    } on FileSystemException {
      // כונן לא זמין - מחזירים את מה שנמצא עד כה.
    }
    return pdfFiles;
  }

  /// ממיר ספרי קטלוג ל-[PdfBook] עבור אלו שיש להם קובץ PDF מקומי.
  ///
  /// [pdfFilesByLowerName] - מפה משם קובץ (lowercase) לנתיב מלא.
  /// תומך בשתי תבניות שמות: `Hebrewbooks_org_<id>.pdf` ו-`<id>.pdf`.
  /// ספר ללא [Book.id] או ללא קובץ תואם מוחזר כמות שהוא.
  static List<Book> mapHebrewBooksToLocal(
    List<Book> books,
    Map<String, String> pdfFilesByLowerName,
  ) {
    return books.map((book) {
      final id = book.id;
      if (id == null) {
        return book;
      }
      final localPath =
          pdfFilesByLowerName['hebrewbooks_org_$id.pdf'] ??
          pdfFilesByLowerName['$id.pdf'];
      if (localPath == null) {
        return book;
      }
      return PdfBook(
        id: id,
        title: book.title,
        path: localPath,
        author: book.author,
        pubPlace: book.pubPlace,
        pubDate: book.pubDate,
        topics: book.topics,
        heShortDesc: book.heShortDesc,
        // שימור המזהה החיצוני (למשל 'hb:1') כדי שהספר יישאר עקבי לזיהוי
        // בחיפוש/סימניות/אינדוקס — בדומה לשימור המזהים ב-DocxBook.toTextBook.
        // הפתיחה המקומית מנותבת לפי טיפוס (PdfBook), ולכן אינה מושפעת מכך.
        externalLibraryId: book.externalLibraryId,
      );
    }).toList();
  }

  /// Retrieves the text content of a book.
  ///
  /// Uses LibraryProviderManager to get text from the appropriate provider.
  Future<String> getBookText(
    String title, {
    int? categoryId,
    String? fileType,
  }) async {
    final text = await _providerManager.getBookText(
      title,
      categoryId: categoryId,
      fileType: fileType ?? 'txt',
    );
    if (text != null) {
      return text;
    }

    // Fallback to direct file system access
    debugPrint(
      '⚠️ Provider manager failed, falling back to direct file access for "$title"',
    );
    final path = await _getBookPath(
      title,
      categoryId: categoryId,
      fileType: fileType,
    );
    if (path.startsWith('error:')) {
      throw Exception('Book not found: $title');
    }

    // ניתוב לפי פורמט ולא קריאה עיוורת כטקסט: פירוש מכולה בינארית (ZIP/OLE)
    // כ-Windows-1255 מייצר ג'יבריש עברי שנראה כספר תקין לגמרי.
    return await readFileBackedBookText(File(path), fileType, title) ?? '';
  }

  /// Saves text content to a book file.
  ///
  /// Supports both plain-text extensions (.txt and legacy .text); a converted
  /// format has no source to write back to.
  /// Creates a backup of the original file before saving.
  Future<void> saveBookText(String title, String content) async {
    await _providerManager.fileSystemProvider.saveBookText(title, content);
  }

  /// Loads and parses the metadata for all books in the library.
  ///
  /// Reads metadata from a JSON file and creates a structured mapping of
  /// book titles to their metadata information.
  Future<Map<String, Map<String, dynamic>>> _getMetadata() async {
    if (!Settings.isInitialized) {
      await Settings.init(cacheProvider: HiveCache());
    }
    String metadataString = '';
    Map<String, Map<String, dynamic>> metadata = {};
    try {
      File file = File(
        '${Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '.'}${Platform.pathSeparator}metadata.json',
      );
      metadataString = await file.readAsString();
    } catch (e) {
      return {};
    }
    final tempMetadata = await Isolate.run(
      () => jsonDecode(metadataString) as List,
    );

    for (int i = 0; i < tempMetadata.length; i++) {
      final row = tempMetadata[i] as Map<String, dynamic>;
      metadata[row['title'].replaceAll('"', '')] = {
        'author': row['author'] ?? '',
        'heCategories': row['heCategories'] is List
            ? (row['heCategories'] as List).join(', ')
            : row['heCategories'] ?? '',
        'heEra': row['heEra'] ?? '',
        'compDateStringHe': row['compDateStringHe'] ?? '',
        'compPlaceStringHe': row['compPlaceStringHe'] ?? '',
        'pubDateStringHe': row['pubDateStringHe'] ?? '',
        'pubPlaceStringHe': row['pubPlaceStringHe'] ?? '',
        'heDesc': row['heDesc'] ?? '',
        'heShortDesc': row['heShortDesc'] ?? '',
        'pubDate': row['pubDate'] ?? '',
        'pubPlace': row['pubPlace'] ?? '',
        'extraTitles': row['extraTitles'] == null
            ? [row['title'].toString()]
            : row['extraTitles'].map<String>((e) => e.toString()).toList()
                  as List<String>,
        'extraTitlesHe': row['extraTitlesHe'] is List
            ? (row['extraTitlesHe'] as List)
                  .map<String>((e) => e.toString())
                  .toList()
            : [],
        'order': row['order'] == null || row['order'] == ''
            ? 999
            : row['order'].runtimeType == double
            ? row['order'].toInt()
            : row['order'] as int,
      };
    }
    return metadata;
  }

  /// Retrieves the file system path for a book with the given title.
  Future<String> _getBookPath(
    String title, {
    int? categoryId,
    String? fileType,
  }) async {
    await _providerManager.initialize();
    final keyToPath = await _providerManager.fileSystemProvider.keyToPath;

    if (categoryId != null && fileType != null) {
      final key = BookCompositeKey.create(
        title: title,
        categoryId: categoryId,
        fileType: fileType,
      ).toStorageKey();
      final resolvedPath = keyToPath[key];
      if (resolvedPath != null) return resolvedPath;
    }

    if (categoryId != null) {
      for (final entry in keyToPath.entries) {
        final parsed = BookCompositeKey.tryParse(entry.key);
        if (parsed == null) continue;
        if (parsed.title == title && parsed.categoryId == categoryId) {
          return entry.value;
        }
      }
    }

    // Fallback: fuzzy search by title
    for (final entry in keyToPath.entries) {
      final parsed = BookCompositeKey.tryParse(entry.key);
      if (parsed == null) continue;
      if (parsed.title == title) {
        return entry.value;
      }
    }

    return 'error: book path not found: $title';
  }

  /// Returns true if the book belongs to Tanach (Torah, Neviim or Ketuvim).
  ///
  /// The check is performed by examining the book path and verifying that it
  /// resides under one of the Tanach directories.
  Future<bool> isTanachBook(
    String title, {
    int? categoryId,
    String? fileType,
  }) async {
    final categoryPath = await findBookCategoryPath(
      title,
      categoryId: categoryId,
    );
    if (categoryPath != null && categoryPath.isNotEmpty) {
      return isTanachPathForTesting(categoryPath);
    }

    final path = await _getBookPath(
      title,
      categoryId: categoryId,
      fileType: fileType,
    );
    return isTanachPathForTesting(path);
  }

  @visibleForTesting
  static bool isTanachPathForTesting(String path) {
    final segments = _normalizeContinuousPathSegments(path);
    if (segments.isEmpty) {
      return false;
    }
    return _isTanachSegments(segments);
  }

  /// בודק אם הספר תומך במצב טקסט רציף.
  ///
  /// מצב זה זמין רק לספרי תנ"ך (תורה/נביאים/כתובים) ולמסכתות
  /// תלמוד בבלי/ירושלמי בתוך אחד מהסדרים. מפרשים, אחרונים, ראשונים
  /// ושאר ספרים נלווים אינם נכללים.
  Future<bool> supportsContinuousReadingMode(
    String title, {
    int? categoryId,
    String? fileType,
  }) async {
    final categoryPath = await findBookCategoryPath(
      title,
      categoryId: categoryId,
    );
    if (categoryPath != null && categoryPath.isNotEmpty) {
      return supportsContinuousReadingPathForTesting(categoryPath);
    }

    final path = await _getBookPath(
      title,
      categoryId: categoryId,
      fileType: fileType,
    );
    return supportsContinuousReadingPathForTesting(path);
  }

  @visibleForTesting
  static bool supportsContinuousReadingPathForTesting(String path) {
    final segments = _normalizeContinuousPathSegments(path);
    if (segments.isEmpty) {
      return false;
    }
    return _isTanachSegments(segments) || _isTalmudSegments(segments);
  }

  static List<String> _normalizeContinuousPathSegments(String path) {
    if (path.isEmpty || path.startsWith('error:')) {
      return const [];
    }

    return path
        .replaceAll('\\', '/')
        .split(RegExp(r'[/,]'))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .map(_normalizeTanachSegment)
        .toList();
  }

  static bool _isTanachSegments(List<String> segments) {
    for (var i = 0; i < segments.length; i++) {
      if (segments[i] != 'תנך') {
        continue;
      }

      if (i + 1 >= segments.length) {
        return true;
      }

      final nextSegment = segments[i + 1];
      if (nextSegment == 'תורה' ||
          nextSegment == 'נביאים' ||
          nextSegment == 'כתובים') {
        return true;
      }
    }

    return false;
  }

  static bool _isTalmudSegments(List<String> segments) {
    for (var i = 0; i < segments.length - 1; i++) {
      final current = segments[i];
      final isTalmudRoot =
          current == 'תלמוד בבלי' || current == 'תלמוד ירושלמי';
      if (!isTalmudRoot) {
        continue;
      }

      final next = segments[i + 1];
      if (next.startsWith('סדר ')) {
        return true;
      }
    }

    return false;
  }

  static String _normalizeTanachSegment(String segment) {
    return segment.replaceAll(RegExp(r'''["'׳״]'''), '');
  }
}
