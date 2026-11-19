import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

typedef _BookFileCategory = ({List<String> parts, String path, int id});

typedef _BookFile = ({
  String path,
  String title,
  DocumentFormat format,
  _BookFileCategory category,
});

typedef _BookFileScan = ({
  List<_BookFile> files,
  Map<String, String> paths,
  Map<int, String> categoryPaths,
});

/// Library provider that loads books from the file system.
class FileSystemLibraryProvider implements LibraryProvider, LinkLinesProvider {
  late String _libraryPath;
  Map<String, String>? _keyToPath;
  Map<String, String>? _catalogKeyToPath;
  Future<_BookFileScan>? _bookScanInFlight;
  final Map<int, String> _categoryIdToPath =
      {}; // Maps hash(categoryPath) -> categoryPath
  bool _isInitialized = false;

  /// Singleton instance
  static FileSystemLibraryProvider? _instance;

  FileSystemLibraryProvider._();

  static FileSystemLibraryProvider get instance {
    _instance ??= FileSystemLibraryProvider._();
    return _instance!;
  }

  static String _generateKey(String title, int categoryId, String fileType) {
    return BookCompositeKey.create(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
    ).toStorageKey();
  }

  @override
  String get providerId => 'file_system';

  @override
  String get displayName => 'קבצים';

  @override
  String get sourceIndicator => 'ק';

  @override
  int get priority => 10;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize() async => _ensureInitialized();

  void _ensureInitialized() {
    if (_isInitialized) return;

    _libraryPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '.';
    _isInitialized = true;
    debugPrint('📁 FileSystemLibraryProvider initialized');
  }

  Future<Map<String, String>> get keyToPath async {
    final paths = await physicalKeyToPath;
    return identical(paths, _keyToPath) ? _catalogKeyToPath ?? paths : paths;
  }

  /// מפת נתיבים למנייה, עם מפתח התיקייה בפועל לכל קובץ.
  Future<Map<String, String>> get physicalKeyToPath async {
    final pending = _bookScanInFlight;
    if (pending != null) return (await pending).paths;
    return _keyToPath ?? (await _refreshBookFiles()).paths;
  }

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    final scan = await _refreshBookFiles();
    final entries =
        <
          ({
            _BookFile file,
            ({String name, String path}) display,
            String? alias,
          })
        >[];
    final aliases = <String, String>{};
    final categoryDisplays =
        <_BookFileCategory, ({String name, String path})>{};
    for (final file in scan.files) {
      final category = file.category;
      if (!kDebugMode && category.parts.contains('ספרים מספריות חיצוניות')) {
        continue;
      }
      final display = categoryDisplays.putIfAbsent(category, () {
        final parts = category.parts.map(getTitleFromPath).toList();
        return (name: parts.last, path: parts.join(', '));
      });
      final alias = display.path == category.path
          ? null
          : _generateKey(
              file.title,
              display.path.hashCode,
              file.format.extension,
            );
      // מפתח לפי שם תצוגה זמין כל עוד אינו מפתח של תיקייה בפועל.
      if (alias != null && !scan.paths.containsKey(alias)) {
        aliases[alias] = file.path;
      }
      entries.add((file: file, display: display, alias: alias));
    }

    final booksByCategory = <String, List<Book>>{};
    for (final entry in entries) {
      final file = entry.file;
      final categoryId =
          entry.alias == null || aliases[entry.alias] == file.path
          ? entry.display.path.hashCode
          : file.category.id;
      try {
        final book = _createBookFromFile(
          file,
          metadata,
          entry.display.path,
          categoryId,
        );
        booksByCategory.putIfAbsent(entry.display.name, () => []).add(book);
      } catch (_) {
        if (entry.display.path == DatabaseConstants.talmudBavliFolderName) {
          rethrow;
        }
        debugPrint('⚠️ Skipping inaccessible entity: ${file.path}');
      }
    }
    if (identical(_keyToPath, scan.paths) && aliases.isNotEmpty) {
      _catalogKeyToPath = {...scan.paths, ...aliases};
    }
    return booksByCategory;
  }

  Future<_BookFileScan> _refreshBookFiles() async {
    final pending = _bookScanInFlight;
    if (pending != null) return pending;

    final scan = _scanBookFiles();
    _bookScanInFlight = scan;
    try {
      final result = await scan;
      if (identical(_bookScanInFlight, scan)) {
        _keyToPath = result.paths;
        _catalogKeyToPath = null;
        _categoryIdToPath
          ..clear()
          ..addAll(result.categoryPaths);
      }
      return result;
    } finally {
      if (identical(_bookScanInFlight, scan)) _bookScanInFlight = null;
    }
  }

  Future<_BookFileScan> _scanBookFiles() {
    _ensureInitialized();
    final personalPath = getPersonalBooksPath();
    final folderName =
        Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
        '';
    final bundledPaths = DatabaseConstants.getTalmudBavliDirectoryPaths(
      _libraryPath,
      folderName,
    );
    return _readBookFiles(personalPath, bundledPaths);
  }

  static Future<_BookFileScan> _readBookFiles(
    String personalPath,
    List<String> bundledPaths,
  ) => Isolate.run(() async {
    final files = <_BookFile>[];
    final paths = <String, String>{};
    final categoryPaths = <int, String>{};

    void addFile(
      String path,
      DocumentFormat format,
      _BookFileCategory category,
    ) {
      final title = getTitleFromPath(path);
      files.add((path: path, title: title, format: format, category: category));
      final key = _generateKey(title, category.id, format.extension);
      paths[key] = path;
      categoryPaths[category.id] = category.path;
    }

    // הספרייה הראשית והתיקיות המותאמות נטענות ממסד הנתונים.
    final personalDir = Directory(personalPath);
    if (await personalDir.exists()) {
      final categories = <String, _BookFileCategory>{};
      // Dart מזהה קישורים מחזוריים לאורך מעבר רקורסיבי אחד.
      final entries = personalDir
          .list(recursive: true)
          .handleError(
            (Object error) =>
                debugPrint('⚠️ Skipping inaccessible entity: $error'),
            test: (error) =>
                error is FileSystemException &&
                error.path != null &&
                p.isWithin(personalPath, error.path!),
          );
      await for (final entity in entries) {
        if (entity is! File) continue;
        final path = entity.path;
        final format = documentFormatFromExtension(path);
        if (format == null || !format.isProductionSupported) continue;
        if (format.needsContentSniffing &&
            !await isSupportedBookFileByContent(path)) {
          continue;
        }
        final parent = _parentPath(path);
        final category = categories.putIfAbsent(
          parent,
          () => _personalCategory(personalPath, parent),
        );
        addFile(path, format, category);
      }
    }

    final talmudCategory = _talmudCategory();
    final bundled = await DatabaseConstants.findBundledTalmudBavliPdfs(
      bundledPaths,
    );
    for (final pdf in bundled.files) {
      addFile(pdf, DocumentFormat.pdf, talmudCategory);
    }
    return (files: files, paths: paths, categoryPaths: categoryPaths);
  });

  static String _parentPath(String path) =>
      path.substring(0, path.lastIndexOf(Platform.pathSeparator));

  static _BookFileCategory _personalCategory(String root, String parent) {
    final prefixLength = root.length + 1;
    final parts = [
      'ספרים אישיים',
      if (parent.length >= prefixLength)
        ...parent.substring(prefixLength).split(Platform.pathSeparator),
    ];
    final path = parts.join(', ');
    return (parts: parts, path: path, id: path.hashCode);
  }

  static _BookFileCategory _talmudCategory() {
    const path = DatabaseConstants.talmudBavliFolderName;
    return (parts: const [path], path: path, id: path.hashCode);
  }

  Book _createBookFromFile(
    _BookFile file,
    Map<String, Map<String, dynamic>> metadata,
    String categoryPath,
    int categoryId,
  ) {
    final path = file.path;
    final title = file.title;
    final format = file.format;
    final topics = title.contains(' על ')
        ? '$categoryPath, ${title.split(' על ')[1]}'
        : categoryPath;
    final info = metadata[title];

    if (format == DocumentFormat.pdf) {
      return PdfBook(
        title: title,
        path: path,
        author: info?['author'],
        heShortDesc: info?['heShortDesc'],
        pubDate: info?['pubDate'],
        pubPlace: info?['pubPlace'],
        order: info?['order'] ?? 999,
        topics: topics,
        categoryPath: categoryPath,
        categoryId: categoryId,
      );
    }

    return buildBookForFileType(
      fileType: format.extension,
      title: title,
      path: path,
      filePath: path,
      author: info?['author'],
      heShortDesc: info?['heShortDesc'],
      pubDate: info?['pubDate'],
      pubPlace: info?['pubPlace'],
      order: info?['order'] ?? 999,
      topics: topics,
      extraTitles: info?['extraTitles'],
      categoryPath: categoryPath,
      categoryId: categoryId,
    );
  }

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async {
    if (!_isInitialized) await initialize();
    final map = await keyToPath;
    final key = _generateKey(title, categoryId, fileType);
    return map.containsKey(key);
  }

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    if (!_isInitialized) await initialize();

    final path = await _getBookPath(title, categoryId, fileType);
    if (path == null) return null;

    final file = File(path);
    if (!await file.exists()) return null;

    // PDF מוחזר null — התוכן שלו אינו טקסט והקוראים עוברים בצנרת ה-PDF.
    return readFileBackedBookText(file, fileType, title);
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    // PDF בונה תוכן עניינים מה-outline שלו במסלול נפרד ואין ממנו טקסט.
    if (!(documentFormatFromFileType(fileType)?.isTextual ?? true)) return null;
    final text = await getBookText(
      title,
      categoryId,
      fileType,
      preferSource: preferSource,
    );
    if (text == null) return null;
    return Isolate.run(() => TocParser.parseEntriesFromContent(text));
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async {
    if (!_isInitialized) await initialize();
    final map = await keyToPath;
    return map.keys.toSet();
  }

  Future<String?> _getBookPath(
    String title,
    int categoryId,
    String fileType,
  ) async {
    final map = await keyToPath;
    final key = _generateKey(title, categoryId, fileType);
    return map[key];
  }

  /// Resets runtime state so the provider re-reads the active library path.
  void resetRuntimeState() {
    _categoryIdToPath.clear();
    _bookScanInFlight = null;
    _keyToPath = null;
    _catalogKeyToPath = null;
    _isInitialized = false;
  }

  @visibleForTesting
  void seedKeyToPathForTesting({
    required Map<String, String> keyToPath,
    Map<int, String>? categoryIdToPath,
    String? libraryPath,
  }) {
    _bookScanInFlight = null;
    _keyToPath = keyToPath;
    _catalogKeyToPath = null;
    _categoryIdToPath
      ..clear()
      ..addAll(categoryIdToPath ?? const {});
    if (libraryPath != null) {
      _libraryPath = libraryPath;
    }
    _isInitialized = true;
  }

  @visibleForTesting
  void resetForTesting() => resetRuntimeState();

  /// Gets the path to the personal books folder
  String getPersonalBooksPath() {
    return '$_libraryPath${Platform.pathSeparator}אוצריא${Platform.pathSeparator}אישי';
  }

  /// Saves text content to a book file
  Future<void> saveBookText(String title, String content) async {
    final map = await keyToPath;
    String? path;
    for (final key in map.keys) {
      if (key.startsWith('$title|')) {
        path = map[key];
        break;
      }
    }
    if (path == null) throw Exception('Book not found: $title');

    // עריכה מותרת רק בטקסט גולמי: פורמט מומר היה נשמר כ-HTML המומר ולא
    // כמקור, וההמרה הבאה הייתה מכפילה עיצוב.
    if (documentFormatFromExtension(path)?.requiresConversion ?? false) {
      throw Exception(
        'Cannot save converted book formats. Only text files are supported.',
      );
    }

    final file = File(path);
    final backupPath = '$path.backup.${DateTime.now().millisecondsSinceEpoch}';
    await file.copy(backupPath);

    try {
      await file.writeAsString(content, encoding: utf8);
      await _cleanupOldBackups(path);
    } catch (e) {
      final backupFile = File(backupPath);
      if (await backupFile.exists()) {
        await backupFile.copy(path);
      }
      rethrow;
    }
  }

  Future<void> _cleanupOldBackups(String originalPath) async {
    try {
      final directory = Directory(originalPath).parent;
      final baseName = originalPath.split(Platform.pathSeparator).last;

      final backupFiles = <File>[];
      await for (final entity in directory.list()) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          if (fileName.startsWith('$baseName.backup.')) {
            backupFiles.add(entity);
          }
        }
      }

      backupFiles.sort((a, b) {
        final aTime = _getBackupTimestamp(a.path);
        final bTime = _getBackupTimestamp(b.path);
        return bTime.compareTo(aTime);
      });

      for (int i = 3; i < backupFiles.length; i++) {
        try {
          await backupFiles[i].delete();
        } catch (e) {
          debugPrint('Failed to delete backup ${backupFiles[i].path}: $e');
        }
      }
    } catch (e) {
      debugPrint('Error during backup cleanup: $e');
    }
  }

  int _getBackupTimestamp(String backupPath) {
    try {
      final fileName = backupPath.split(Platform.pathSeparator).last;
      final timestampStr = fileName.split('.backup.').last;
      return int.parse(timestampStr);
    } catch (e) {
      return 0;
    }
  }

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    if (!_isInitialized) await initialize();

    final Library library = Library(categories: []);
    final Map<String, Category> categoryCache = {};

    // Load books from file system
    final allBooksByCategory = await loadBooks(metadata);

    // Build category hierarchy from topics/paths
    for (final entry in allBooksByCategory.entries) {
      final categoryPath = entry.key;
      final books = entry.value;

      for (final book in books) {
        // Get the full category path from book topics or use the entry key
        final fullPath = _extractCategoryPath(book, categoryPath);

        // Find or create the category hierarchy
        final category = _findOrCreateCategoryHierarchy(
          fullPath,
          library,
          categoryCache,
          metadata,
        );

        // Create book with proper category reference
        final bookWithCategory = _createBookWithCategory(
          book,
          category,
          metadata,
        );
        category.books.add(bookWithCategory);
      }
    }

    // Sort all categories and books
    _sortLibraryRecursive(library);

    debugPrint(
      '📁 FileSystem catalog built with ${library.subCategories.length} top-level categories',
    );
    return library;
  }

  /// Extracts the category path from a book's topics or uses the default category name.
  String _extractCategoryPath(Book book, String defaultCategory) {
    // If book has topics, use the first topic as the category path
    if (book.topics.isNotEmpty) {
      // Topics might be comma-separated, take the first meaningful one
      final topics = book.topics.split(',').map((t) => t.trim()).toList();
      if (topics.isNotEmpty && topics.first.isNotEmpty) {
        return topics.first;
      }
    }
    return defaultCategory;
  }

  /// Finds or creates a category hierarchy from a path string.
  Category _findOrCreateCategoryHierarchy(
    String path,
    Library library,
    Map<String, Category> categoryCache,
    Map<String, dynamic> metadata,
  ) {
    // Check cache first
    if (categoryCache.containsKey(path)) {
      return categoryCache[path]!;
    }

    // Split path into parts
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      parts.add('ללא קטגוריה');
    }

    Category currentParent = library;
    String currentPath = '';

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      currentPath = currentPath.isEmpty ? part : '$currentPath/$part';

      // Check if this level exists in cache
      if (categoryCache.containsKey(currentPath)) {
        currentParent = categoryCache[currentPath]!;
        continue;
      }

      // Check if category exists in parent's subcategories
      Category? existingCategory;
      for (final subCat in currentParent.subCategories) {
        if (subCat.title == part) {
          existingCategory = subCat;
          break;
        }
      }

      if (existingCategory != null) {
        categoryCache[currentPath] = existingCategory;
        currentParent = existingCategory;
      } else {
        // Create new category
        final newCategory = Category(
          title: part,
          description: metadata[part]?['heDesc'] ?? '',
          shortDescription: metadata[part]?['heShortDesc'] ?? '',
          order: metadata[part]?['order'] ?? 999,
          subCategories: [],
          books: [],
          parent: currentParent,
        );

        currentParent.subCategories.add(newCategory);
        categoryCache[currentPath] = newCategory;
        currentParent = newCategory;
      }
    }

    return currentParent;
  }

  /// Creates a book with proper category reference and enriched metadata.
  Book _createBookWithCategory(
    Book book,
    Category category,
    Map<String, dynamic> metadata,
  ) {
    final bookMeta = metadata[book.title];

    if (book is TextBook) {
      return TextBook(
        title: book.title,
        category: category,
        author: book.author ?? bookMeta?['author'],
        heShortDesc: book.heShortDesc ?? bookMeta?['heShortDesc'],
        pubDate: book.pubDate ?? bookMeta?['pubDate'],
        pubPlace: book.pubPlace ?? bookMeta?['pubPlace'],
        order: book.order,
        topics: book.topics,
        extraTitles: book.extraTitles ?? bookMeta?['extraTitles'],
        categoryPath: book.categoryPath,
        categoryId: book.categoryId,
      );
    } else if (book is PdfBook) {
      return PdfBook(
        title: book.title,
        category: category,
        path: book.path,
        author: book.author ?? bookMeta?['author'],
        heShortDesc: book.heShortDesc ?? bookMeta?['heShortDesc'],
        pubDate: book.pubDate ?? bookMeta?['pubDate'],
        pubPlace: book.pubPlace ?? bookMeta?['pubPlace'],
        order: book.order,
        topics: book.topics,
        categoryPath: book.categoryPath,
        categoryId: book.categoryId,
      );
    }
    return book;
  }

  /// Recursively sorts all categories and books in the library.
  void _sortLibraryRecursive(Category category) {
    category.subCategories.sort((a, b) => a.order.compareTo(b.order));
    category.books.sort((a, b) => a.order.compareTo(b.order));

    for (final subCat in category.subCategories) {
      _sortLibraryRecursive(subCat);
    }
  }

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async {
    if (!_isInitialized) await initialize();

    try {
      final linksPath =
          '$_libraryPath${Platform.pathSeparator}links${Platform.pathSeparator}${title}_links.json';
      final file = File(linksPath);

      if (!await file.exists()) {
        return [];
      }

      final jsonString = await file.readAsString();
      final jsonList = await Isolate.run(() => jsonDecode(jsonString) as List);
      return jsonList.map((json) => Link.fromJson(json)).toList();
    } catch (e) {
      debugPrint('⚠️ Error loading links for book "$title": $e');
      return [];
    }
  }

  @override
  Future<String> getLinkContent(Link link) async => (await getLinkContentLines(
    link,
  )).map((line) => line.content).join('<br>');

  @override
  Future<List<LinkContentLine>> getLinkContentLines(Link link) async {
    if (!_isInitialized) await initialize();

    try {
      if (link.path2.isEmpty) {
        return [(lineIndex: link.index2 - 1, content: 'שגיאה: נתיב ריק')];
      }

      if (link.index2 <= 0) {
        return [(lineIndex: link.index2 - 1, content: 'שגיאה: אינדקס לא תקין')];
      }

      final title = getTitleFromPath(link.path2);

      // Find path for title (fuzzy match since we don't have category/fileType)
      final map = await keyToPath;
      String? path;
      for (final key in map.keys) {
        if (key.startsWith('$title|')) {
          path = map[key];
          break;
        }
      }

      if (path == null) {
        return [(lineIndex: link.index2 - 1, content: 'שגיאה: הספר לא נמצא')];
      }

      final file = File(path);
      if (!await file.exists()) {
        return [(lineIndex: link.index2 - 1, content: 'שגיאה: הקובץ לא נמצא')];
      }

      return await _getLinesFromFile(
        path,
        link.index2,
        link.index2End,
        title,
      ).timeout(
        const Duration(seconds: 3),
        onTimeout: () => [
          (lineIndex: link.index2 - 1, content: 'שגיאה: פג זמן קריאת הקובץ'),
        ],
      );
    } catch (e) {
      return [
        (lineIndex: link.index2 - 1, content: 'שגיאה בטעינת תוכן המפרש: $e'),
      ];
    }
  }

  /// Gets a specific line from a file by index.
  ///
  /// [title] הוא כותרת הספר בקטלוג: בפורמט שדורש המרה היא שורה 1 של הפלט,
  /// ולכן היא חלק מהמיקום שהקישור מפנה אליו. הניתוב לפי פורמט הוא גם מה
  /// שמונע קריאת מכולה בינארית כטקסט — שמחזירה ג'יבריש שנראה כתוכן.
  Future<List<LinkContentLine>> _getLinesFromFile(
    String path,
    int lineIndex,
    int? lastLineIndex,
    String title,
  ) async {
    final text = await readFileBackedBookText(File(path), null, title);
    if (text == null) {
      return [
        (
          lineIndex: lineIndex - 1,
          content: 'שגיאה: לפורמט הקובץ אין תוכן טקסטואלי',
        ),
      ];
    }
    if (lineIndex < 1) {
      return [(lineIndex: lineIndex - 1, content: 'שגיאה: אינדקס מחוץ לטווח')];
    }

    final end = lastLineIndex == null || lastLineIndex < lineIndex
        ? lineIndex
        : lastLineIndex;
    final result = <LinkContentLine>[];
    var current = 0;
    for (final line in LineSplitter.split(text)) {
      current++;
      if (current >= lineIndex) {
        result.add((lineIndex: current - 1, content: line));
      }
      if (current == end) break;
    }
    if (result.isEmpty) {
      return [(lineIndex: lineIndex - 1, content: 'שגיאה: אינדקס מחוץ לטווח')];
    }
    return result;
  }
}
