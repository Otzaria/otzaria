import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/utils/docx_to_otzaria.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:otzaria/utils/toc_parser.dart';
import 'package:otzaria/settings/custom_folders/custom_folder.dart';
import 'package:otzaria/settings/settings_repository.dart';

/// Library provider that loads books from the file system.
class FileSystemLibraryProvider implements LibraryProvider {
  late String _libraryPath;
  late Future<Map<String, String>> _keyToPath;
  bool _isInitialized = false;

  /// Singleton instance
  static FileSystemLibraryProvider? _instance;

  FileSystemLibraryProvider._();

  static FileSystemLibraryProvider get instance {
    _instance ??= FileSystemLibraryProvider._();
    return _instance!;
  }

  String _generateKey(String title, String category, String fileType) {
    return '$title|$category|$fileType';
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
  Future<void> initialize() async {
    if (_isInitialized) return;

    _libraryPath = Settings.getValue<String>('key-library-path') ?? '.';
    _keyToPath = _buildKeyToPath();
    _isInitialized = true;
    debugPrint('📁 FileSystemLibraryProvider initialized');
  }

  String get libraryPath => _libraryPath;

  Future<Map<String, String>> get keyToPath => _keyToPath;

  @override
  Future<Map<String, List<Book>>> loadBooks(
      Map<String, Map<String, dynamic>> metadata) async {
    if (!_isInitialized) await initialize();

    final Map<String, List<Book>> booksByCategory = {};
    final otzariaPath = '$_libraryPath${Platform.pathSeparator}אוצריא';
    final otzariaDir = Directory(otzariaPath);

    if (!otzariaDir.existsSync()) {
      debugPrint('📁 Otzaria directory does not exist: $otzariaPath');
      return booksByCategory;
    }

    // We can populate the key map here as well to ensure it's accurate
    final map = await _keyToPath;

    await _loadBooksRecursively(otzariaDir, metadata, booksByCategory, [], map);

    // Load books from custom folders (those NOT marked for DB sync)
    await _loadCustomFoldersBooks(metadata, booksByCategory, map);

    debugPrint(
        '📁 FileSystem loaded ${booksByCategory.values.expand((b) => b).length} books');
    return booksByCategory;
  }

  /// Load books from custom folders that are NOT marked for DB sync
  /// These books are displayed directly from the file system
  Future<void> _loadCustomFoldersBooks(
    Map<String, Map<String, dynamic>> metadata,
    Map<String, List<Book>> booksByCategory,
    Map<String, String> keyToPath,
  ) async {
    final customFoldersJson =
        Settings.getValue<String>(SettingsRepository.keyCustomFolders);
    final customFolders = CustomFoldersManager.loadFolders(customFoldersJson);

    // Only load folders NOT marked for DB sync (those marked will be in DB)
    final foldersToLoad = customFolders.where((f) => !f.addToDatabase).toList();

    if (foldersToLoad.isEmpty) return;

    debugPrint('📁 Loading ${foldersToLoad.length} custom folders');

    for (final folder in foldersToLoad) {
      final folderDir = Directory(folder.path);
      if (!await folderDir.exists()) {
        debugPrint('⚠️ Custom folder does not exist: ${folder.path}');
        continue;
      }

      // Load books with category path: ספרים אישיים -> folder name -> subfolders
      await _loadBooksRecursively(
        folderDir,
        metadata,
        booksByCategory,
        ['ספרים אישיים', folder.name],
        keyToPath,
      );
    }
  }

  Future<void> _loadBooksRecursively(
    Directory dir,
    Map<String, Map<String, dynamic>> metadata,
    Map<String, List<Book>> booksByCategory,
    List<String> currentPath,
    Map<String, String> keyToPath,
  ) async {
    final dirName = dir.path.split(Platform.pathSeparator).last;

    // Skip special directories (except in debug mode)
    if (!kDebugMode && dirName == 'אודות התוכנה') return;

    await for (FileSystemEntity entity in dir.list()) {
      try {
        await entity.stat();

        if (entity is Directory) {
          final newPath = [...currentPath, getTitleFromPath(entity.path)];
          await _loadBooksRecursively(
              entity, metadata, booksByCategory, newPath, keyToPath);
        } else if (entity is File) {
          final book = _createBookFromFile(entity, metadata, currentPath);
          if (book != null) {
            final categoryName =
                currentPath.isNotEmpty ? currentPath.last : 'ללא קטגוריה';
            booksByCategory.putIfAbsent(categoryName, () => []);
            booksByCategory[categoryName]!.add(book);

            // Add to key map
            final key = _generateKey(
                book.title, book.categoryPath ?? '', book.fileType ?? '');
            keyToPath[key] = entity.path;
          }
        }
      } catch (e) {
        debugPrint('⚠️ Skipping inaccessible entity: ${entity.path}');
        continue;
      }
    }
  }

  Book? _createBookFromFile(
    File file,
    Map<String, Map<String, dynamic>> metadata,
    List<String> categoryPath,
  ) {
    final path = file.path.toLowerCase();
    final title = getTitleFromPath(file.path);
    final topics = categoryPath.join(', ');

    // Handle special case where title contains " על "
    String finalTopics = topics;
    if (title.contains(' על ')) {
      finalTopics = '$topics, ${title.split(' על ')[1]}';
    }

    if (path.endsWith('.pdf')) {
      return PdfBook(
        title: title,
        path: file.path,
        author: metadata[title]?['author'],
        heShortDesc: metadata[title]?['heShortDesc'],
        pubDate: metadata[title]?['pubDate'],
        pubPlace: metadata[title]?['pubPlace'],
        order: metadata[title]?['order'] ?? 999,
        topics: finalTopics,
        categoryPath: categoryPath.join(', '),
      );
    }

    if (path.endsWith('.txt') || path.endsWith('.docx')) {
      return TextBook(
        title: title,
        author: metadata[title]?['author'],
        heShortDesc: metadata[title]?['heShortDesc'],
        pubDate: metadata[title]?['pubDate'],
        pubPlace: metadata[title]?['pubPlace'],
        order: metadata[title]?['order'] ?? 999,
        topics: finalTopics,
        extraTitles: metadata[title]?['extraTitles'],
        categoryPath: categoryPath.join(', '),
      );
    }

    return null;
  }

  @override
  Future<bool> hasBook(String title, String category, String fileType) async {
    if (!_isInitialized) await initialize();
    final map = await _keyToPath;
    final key = _generateKey(title, category, fileType);
    return map.containsKey(key);
  }

  @override
  Future<String?> getBookText(String title, String category, String fileType) async {
    if (!_isInitialized) await initialize();

    final path = await _getBookPath(title, category, fileType);
    if (path == null) return null;

    final file = File(path);
    if (!await file.exists()) return null;

    // PDF content isn't plain text; callers should use the PDF flow.
    if (fileType.toLowerCase() == 'pdf' || path.toLowerCase().endsWith('.pdf')) {
      return null;
    }

    if (path.endsWith('.docx')) {
      final bytes = await file.readAsBytes();
      return Isolate.run(() => docxToText(bytes, title));
    } else {
      return file.readAsString();
    }
  }

  @override
  Future<List<TocEntry>?> getBookToc(String title, String category, String fileType) async {
    if (fileType.toLowerCase() == 'pdf') return null;
    final text = await getBookText(title, category, fileType);
    if (text == null) return null;
    return Isolate.run(() => TocParser.parseEntriesFromContent(text));
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async {
    if (!_isInitialized) await initialize();
    final map = await _keyToPath;
    return map.keys.toSet();
  }

  Future<String?> _getBookPath(String title, String category, String fileType) async {
    final map = await _keyToPath;
    final key = _generateKey(title, category, fileType);
    return map[key];
  }

  Future<Map<String, String>> _buildKeyToPath() async {
    Map<String, String> keyToPath = {};

    // Helper to add path
    void addPath(String path, String rootPath, [List<String> prefix = const []]) {
      final title = getTitleFromPath(path);
      final fileType = path.split('.').last.toLowerCase();

      // Extract category
      String relative = path;
      if (path.startsWith(rootPath)) {
        relative = path.substring(rootPath.length);
      }
      if (relative.startsWith(Platform.pathSeparator)) {
        relative = relative.substring(1);
      }

      final parts = relative.split(Platform.pathSeparator);
      // Remove filename
      if (parts.isNotEmpty) parts.removeLast();

      final categoryParts = [...prefix, ...parts];
      final category = categoryParts.join(', ');

      final key = _generateKey(title, category, fileType);
      keyToPath[key] = path;
    }

    // Load from main library path
    final otzariaPath = '$_libraryPath${Platform.pathSeparator}אוצריא';
    if (await Directory(otzariaPath).exists()) {
      List<String> paths = await _getAllBookPaths(otzariaPath);
      for (var path in paths) {
        addPath(path, otzariaPath);
      }
    }

    // Load from custom folders (those NOT marked for DB sync)
    final customFoldersJson =
        Settings.getValue<String>(SettingsRepository.keyCustomFolders);
    final customFolders = CustomFoldersManager.loadFolders(customFoldersJson);
    final foldersToLoad = customFolders.where((f) => !f.addToDatabase).toList();

    for (final folder in foldersToLoad) {
      final folderDir = Directory(folder.path);
      if (!await folderDir.exists()) continue;

      final folderPaths = await _getAllBookPaths(folder.path);
      for (var path in folderPaths) {
        addPath(path, folder.path, ['ספרים אישיים', folder.name]);
      }
    }

    return keyToPath;
  }

  static Future<List<String>> _getAllBookPaths(String path) async {
    return Isolate.run(() async {
      final results = <String>[];
      final entities = await Directory(path).list(recursive: true).toList();
      for (final entity in entities) {
        if (entity is! File) continue;
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.txt') ||
            lower.endsWith('.docx') ||
            lower.endsWith('.pdf')) {
          results.add(entity.path);
        }
      }
      return results;
    });
  }

  /// Refreshes the title to path mapping
  void refresh() {
    _keyToPath = _buildKeyToPath();
  }

  /// Checks if a book is in the personal folder or a custom folder
  Future<bool> isPersonalBook(String title, {String? category, String? fileType}) async {
    String? bookPath;
    if (category != null && fileType != null) {
      bookPath = await _getBookPath(title, category, fileType);
    } else {
      // Fuzzy search
      final map = await _keyToPath;
      for (final key in map.keys) {
        if (key.startsWith('$title|')) {
          bookPath = map[key];
          break;
        }
      }
    }

    if (bookPath == null) return false;

    // Check if in the built-in personal folder
    if (bookPath
        .contains('${Platform.pathSeparator}אישי${Platform.pathSeparator}')) {
      return true;
    }

    // Check if in any custom folder
    final customFoldersJson =
        Settings.getValue<String>(SettingsRepository.keyCustomFolders);
    final customFolders = CustomFoldersManager.loadFolders(customFoldersJson);

    for (final folder in customFolders) {
      if (bookPath.startsWith(folder.path)) {
        return true;
      }
    }

    return false;
  }

  /// Gets the path to the personal books folder
  String getPersonalBooksPath() {
    return '$_libraryPath${Platform.pathSeparator}אוצריא${Platform.pathSeparator}אישי';
  }

  /// Ensures the personal books folder exists
  Future<void> ensurePersonalFolderExists() async {
    final personalPath = getPersonalBooksPath();
    final personalDir = Directory(personalPath);

    if (!await personalDir.exists()) {
      await personalDir.create(recursive: true);
      debugPrint('📁 Created personal books folder: $personalPath');

      final readmePath = '$personalPath${Platform.pathSeparator}קרא אותי.txt';
      final readmeFile = File(readmePath);
      await readmeFile.writeAsString('''
תיקייה זו מיועדת לספרים אישיים

ספרים שנמצאים בתיקייה זו:
• לא יועברו למסד הנתונים
• לא יסונכרנו עם השרת
• נשארים תמיד כקבצים
• ניתנים לעריכה ישירה

איך להוסיף ספר אישי:
1. העתק קובץ TXT או DOCX לתיקייה זו
2. או השתמש בכפתור "הוסף ספר אישי" בתוכנה

הספרים יופיעו בספרייה עם סימון מיוחד (א)
''', encoding: utf8);
    }
  }

  /// Saves text content to a book file
  Future<void> saveBookText(String title, String content) async {
    final map = await _keyToPath;
    String? path;
    for (final key in map.keys) {
      if (key.startsWith('$title|')) {
        path = map[key];
        break;
      }
    }
    if (path == null) throw Exception('Book not found: $title');

    if (path.endsWith('.docx')) {
      throw Exception(
          'Cannot save to DOCX files. Only text files are supported.');
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
        final bookWithCategory =
            _createBookWithCategory(book, category, metadata);
        category.books.add(bookWithCategory);
      }
    }

    // Sort all categories and books
    _sortLibraryRecursive(library);

    debugPrint(
        '📁 FileSystem catalog built with ${library.subCategories.length} top-level categories');
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
  Future<List<Link>> getAllLinksForBook(String title, String category, String fileType) async {
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
  Future<String> getLinkContent(Link link) async {
    if (!_isInitialized) await initialize();

    try {
      if (link.path2.isEmpty) {
        return 'שגיאה: נתיב ריק';
      }

      if (link.index2 <= 0) {
        return 'שגיאה: אינדקס לא תקין';
      }

      final title = getTitleFromPath(link.path2);

      // Find path for title (fuzzy match since we don't have category/fileType)
      final map = await _keyToPath;
      String? path;
      for (final key in map.keys) {
        if (key.startsWith('$title|')) {
          path = map[key];
          break;
        }
      }

      if (path == null) {
        return 'שגיאה: הספר לא נמצא';
      }

      final file = File(path);
      if (!await file.exists()) {
        return 'שגיאה: הקובץ לא נמצא';
      }

      return await _getLineFromFile(path, link.index2).timeout(
        const Duration(seconds: 3),
        onTimeout: () => 'שגיאה: פג זמן קריאת הקובץ',
      );
    } catch (e) {
      debugPrint('⚠️ Error loading link content: $e');
      return 'שגיאה בטעינת תוכן המפרש: $e';
    }
  }

  /// Gets a specific line from a file by index.
  Future<String> _getLineFromFile(String path, int lineIndex) async {
    final file = File(path);
    final lines = await file.readAsLines();

    if (lineIndex < 1 || lineIndex > lines.length) {
      return 'שגיאה: אינדקס מחוץ לטווח';
    }

    return lines[lineIndex - 1];
  }
}
