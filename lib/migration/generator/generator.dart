import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:pdfrx/pdfrx.dart';

import '../core/models/book.dart';
import '../core/models/category.dart';
import '../core/models/line.dart';
import '../core/models/toc_entry.dart';
import '../core/models/topic.dart';
import '../dao/repository/seforim_repository.dart';
import '../shared/link_processor.dart';
import 'hebrew_text_utils.dart' as hebrew_text_utils;
import 'package:otzaria/utils/docx_to_otzaria.dart';

/// DatabaseGenerator is responsible for generating the Otzaria database from source files.
/// It processes directories, books, and links to create a structured database.
///
/// This is a Dart conversion of the original Kotlin DatabaseGenerator.
class DatabaseGenerator {
  static final _log = Logger('DatabaseGenerator');

  /// The path to the source directory containing the data files
  final String sourceDirectory;

  /// The repository used to store the generated data
  final SeforimRepository repository;

  /// Callback for progress updates
  final void Function(double progress, String message)? onProgress;

  /// Callback to handle duplicate books. Returns true to replace, false to skip.
  /// If null, duplicates will be skipped by default.
  /// Parameters: bookTitle, categoryId
  Future<bool> Function(String bookTitle, int categoryId)? onDuplicateBook;

  /// Library root path for relative path computations
  late String _libraryRoot;

  /// Cache of source name -> id from DB
  final Map<String, int> _sourceNameToId = {};

  /// Tracks books processed from priority list to avoid double insertion
  final Set<String> _processedPriorityBookKeys = {};

  /// Overall progress across books
  int _totalBooksToProcess = 0;
  int _processedBooksCount = 0;

  /// Getter for total books to process (for subclasses)
  int get totalBooksToProcess => _totalBooksToProcess;

  /// Book contents cache: maps library-relative key -> list of lines
  final Map<String, List<String>> _bookContentCache = {};

  DatabaseGenerator(this.sourceDirectory, this.repository,
      {this.onDuplicateBook, this.onProgress})
      : _libraryRoot = sourceDirectory;

  /// Sets the total books to process for progress reporting.
  void setTotalBooksToProcess(int total) {
    _totalBooksToProcess = total;
  }

  /// Initializes the generator for sync operations where generate() is not called.
  /// [libraryRoot] Optional root path for library-relative calculations.
  void initializeForSync({String? libraryRoot}) {
    _libraryRoot = libraryRoot ?? sourceDirectory;
  }

  /// Generates the database by processing metadata, directories, and links.
  /// This is the main entry point for the database generation process.
  Future<void> generate() async {
    try {
      // Disable foreign keys for better performance
      await _disableForeignKeys();

      // Set maximum performance mode for bulk generation
      await repository.setMaxPerformanceMode();

      // Process hierarchy - expect sourceDirectory to be the parent folder containing "אוצריא"
      final libraryPath = path.join(sourceDirectory, 'אוצריא');

      final libraryDir = Directory(libraryPath);
      if (!await libraryDir.exists()) {
        throw StateError(
            'התיקייה "אוצריא" לא נמצאה בתיקייה שנבחרה. נא לבחור את תיקיית האב של אוצריא.');
      }

      _libraryRoot = libraryPath;

      // Estimate total number of books for progress tracking
      _totalBooksToProcess = await _countFiles(libraryPath);

      // Preload all book contents into RAM
      await processDirectory(libraryPath, null, 0);

      // Process links
      await processLinks();

      // Build category closure table
      await repository.rebuildCategoryClosure();

      // Restore PRAGMAs
      await _enableForeignKeys();
      await repository.restoreNormalMode();
    } catch (e, stackTrace) {
      // Restore settings on error
      try {
        await _enableForeignKeys();
        await repository.restoreNormalMode();
      } catch (innerEx) {
        _log.warning(
            'Error restoring database settings after failure', innerEx);
      }

      _log.severe('Error during generation', e, stackTrace);
      rethrow;
    }
  }

  /// Processes a directory recursively, creating categories and books.
  ///
  /// [directory] The directory to process
  /// [parentCategoryId] The ID of the parent category, if any
  /// [level] The current level in the directory hierarchy
  /// [metadata] The metadata for books
  Future<void> processDirectory(
      String directory, int? parentCategoryId, int level) async {
    final dir = Directory(directory);
    final entities = await dir.list().toList();
    final sortedEntities = entities
      ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

    for (final entity in sortedEntities) {
      if (entity is Directory) {
        final categoryId =
            await createCategory(entity.path, parentCategoryId, level);
        await processDirectory(entity.path, categoryId, level + 1);
      } else if (entity is File &&
          ['.txt', '.pdf', '.docx']
              .contains(path.extension(entity.path).toLowerCase())) {
        // Skip if already processed from priority list
        final key = _toLibraryRelativeKey(entity.path);
        if (_processedPriorityBookKeys.contains(key)) {
          continue;
        }

        if (parentCategoryId == null) {
          continue;
        }
        await createAndProcessBook(entity.path, parentCategoryId);
      }
    }

    // Delete directory if it became empty after processing
    await _deleteIfEmpty(dir);
  }

  /// Creates a category in the database.
  ///
  /// [path] The path representing the category
  /// [parentId] The ID of the parent category, if any
  /// [level] The level in the category hierarchy
  /// Returns the ID of the created category
  Future<int> createCategory(
    String categoryPath,
    int? parentId,
    int level,
  ) async {
    final title = path.basename(categoryPath);

    final category = Category(
      parentId: parentId,
      title: title,
      level: level,
    );

    final insertedId = await repository.insertCategory(category);
    return insertedId;
  }

  /// Finds or creates a chain of categories from a list of names.
  /// Returns the ID of the leaf (deepest) category and count of newly created categories.
  ///
  /// [categoryNames] List of category names from root to leaf
  /// Returns a record with categoryId and categoriesCreated count
  Future<({int categoryId, int categoriesCreated})> findOrCreateCategoryChain(
    List<String> categoryNames,
  ) async {
    int? currentParentId;
    int categoriesCreated = 0;

    for (int i = 0; i < categoryNames.length; i++) {
      final categoryName = categoryNames[i];
      final level = i;

      // Try to find existing category with same name and parent
      final existingCategory = await _findCategoryByNameAndParent(
        categoryName,
        currentParentId,
      );

      if (existingCategory != null) {
        currentParentId = existingCategory.id;
      } else {
        // Create new category - repository handles ID generation and duplicate check
        final category = Category(
          parentId: currentParentId,
          title: categoryName,
          level: level,
        );

        final insertedId = await repository.insertCategory(category);
        currentParentId = insertedId;
        categoriesCreated++;

        _log.info('Created new category: $categoryName (id: $insertedId)');
      }
    }

    return (categoryId: currentParentId!, categoriesCreated: categoriesCreated);
  }

  /// Finds a category by name and parent ID
  Future<Category?> _findCategoryByNameAndParent(
      String name, int? parentId) async {
    final categories = parentId == null
        ? await repository.getRootCategories()
        : await repository.getCategoryChildren(parentId);

    for (final cat in categories) {
      if (cat.title == name) {
        return cat;
      }
    }
    return null;
  }

  /// Creates a book in the database and processes its content.
  ///
  /// [bookPath] The path to the book file
  /// [categoryId] The ID of the category the book belongs to
  /// [metadata] The metadata for the book
  /// [isPersonal] Whether the book is personal (default: false)
  Future<void> createAndProcessBook(
    String bookPath,
    int categoryId, {
    bool isPersonal = false,
    bool insertContent = true,
  }) async {
    try {
      final filename = path.basename(bookPath);
      final title = path.basenameWithoutExtension(filename);

      // Extract file type from the file path
      final fileExtension = path.extension(bookPath).toLowerCase();
      final fileType = fileExtension.startsWith('.')
          ? fileExtension.substring(1)
          : fileExtension;

      // Check for duplicates in the same category with the same file type (for performance measurement)
      final existingBook = await repository
          .checkBookExistsInCategoryWithFileType(title, categoryId, fileType);
      if (existingBook != null) {
        if ((fileType == 'txt' || fileType == 'docx' || fileType == 'pdf') &&
            insertContent) {
          await repository.clearBookContent(existingBook.id);
          await processBookContent(bookPath, existingBook.id);
          // Keep file stats and storage location in sync. If insertContent is true and it's a txt file, filePath becomes null.
          try {
            final file = File(bookPath);
            final stat = await file.stat();
            final targetFilePath =
                (fileType != "txt" || !insertContent) ? bookPath : null;
            await repository.updateBookStorage(existingBook.id, targetFilePath,
                stat.size, stat.modified.millisecondsSinceEpoch);
          } catch (e) {
            _log.warning(
                'Failed to update storage stats for file: $bookPath', e);
          }
        } else {
          try {
            if (fileType == 'txt' || fileType == 'docx') {
              // We're moving to file-backed storage, so clear lines from DB to save space, but preserve TOC
              await repository.deleteBookLines(existingBook.id);
              await repository.updateBookTotalLines(existingBook.id, 0);
            }
            final file = File(bookPath);
            final stat = await file.stat();
            final targetFilePath =
                (fileType != "txt" || !insertContent) ? bookPath : null;
            await repository.updateBookStorage(existingBook.id, targetFilePath,
                stat.size, stat.modified.millisecondsSinceEpoch);
          } catch (e) {
            _log.warning(
                'Failed to update storage stats for file: $bookPath', e);
          }
        }

        _processedBooksCount++;
        final pct = _totalBooksToProcess > 0
            ? (_processedBooksCount * 100 ~/ _totalBooksToProcess)
            : 0;
        onProgress?.call(
            _processedBooksCount /
                (_totalBooksToProcess > 0 ? _totalBooksToProcess : 1),
            'עודכן ספר: $title ($pct%)');

        // Call the callback if provided
        if (onDuplicateBook != null) {
          final shouldReplace = await onDuplicateBook!(title, categoryId);
          if (!shouldReplace) {
            onProgress?.call(
                _processedBooksCount /
                    (_totalBooksToProcess > 0 ? _totalBooksToProcess : 1),
                'מדלג על כפילות: $title');
            _processedBooksCount++;
            return;
          }
          // Delete the existing book and continue with insertion
          await repository.deleteBookCompletely(existingBook.id);
        } else {
          // Default behavior: skip duplicates
          onProgress?.call(
              _processedBooksCount /
                  (_totalBooksToProcess > 0 ? _totalBooksToProcess : 1),
              'מדלג על כפילות: $title');
          _processedBooksCount++;
          return;
        }
      }

      // קביעת מזהה לספר: שלילי אם אישי או קובץ שאינו txt, אחרת רגיל
      int currentBookId = await repository.getNextNegativeBookId();

      // Detect companion notes file named 'הערות על <title>.txt' in the same directory
      String? notesContent;
      try {
        final dir = Directory(path.dirname(bookPath));
        final notesTitle = 'הערות על $title';
        final candidate = path.join(dir.path, '$notesTitle.txt');
        final candidateFile = File(candidate);
        if (await candidateFile.exists()) {
          // Prefer preloaded cache if available
          final key = _toLibraryRelativeKey(candidate);
          final lines = _bookContentCache[key];
          notesContent = lines != null
              ? lines.join('\n')
              : await candidateFile.readAsString();
        }
      } catch (e) {
        // Ignore errors reading notes
      }

      // For non-txt files (external), get file stats
      int? fileSize;
      int? lastModified;
      try {
        final file = File(bookPath);
        final stat = await file.stat();
        fileSize = stat.size;
        lastModified = stat.modified.millisecondsSinceEpoch;
      } catch (e) {
        _log.warning('Failed to get stats for external file: $bookPath', e);
      }

      final sourceId = await _resolveSourceIdFor(bookPath);
      final book = Book(
        id: currentBookId,
        categoryId: categoryId,
        sourceId: sourceId,
        title: title,
        authors: [],
        pubPlaces: [],
        pubDates: [],
        heShortDesc: null,
        notesContent: notesContent,
        order: 999.0,
        topics: extractTopics(bookPath),
        isBaseBook: false,
        filePath: (fileType != "txt" || !insertContent) ? bookPath : null,
        fileType: fileType,
        fileSize: fileSize,
        lastModified: lastModified,
      );

      final insertedBookId = await repository.insertBook(book);

      // Verify categoryId is correct
      final insertedBook = await repository.getBook(insertedBookId);
      if (insertedBook?.categoryId != categoryId) {
        await repository.updateBookCategoryId(insertedBookId, categoryId);
      }

      // Process content of the book
      if (insertContent) {
        await processBookContent(bookPath, insertedBookId);
      } else {
        await repository.updateBookTotalLines(insertedBookId, 0);
      }

      // Book-level progress
      _processedBooksCount++;
      final pct = _totalBooksToProcess > 0
          ? (_processedBooksCount * 100 ~/ _totalBooksToProcess)
          : 0;
      onProgress?.call(
          _processedBooksCount /
              (_totalBooksToProcess > 0 ? _totalBooksToProcess : 1),
          'מעבד ספר: $title ($pct%)');

      // NOTE: Original files are never deleted. The DB is the single source of truth
      // but original files are always preserved on disk.
    } catch (e, stackTrace) {
      final title = path.basenameWithoutExtension(bookPath);
      _log.severe('❌ Critical error processing book: $title at $bookPath', e,
          stackTrace);
      debugPrint('❌ Critical error processing book: $title');
      debugPrint('   Path: $bookPath');
      debugPrint('   Error: $e');
      debugPrint('   Stack trace: $stackTrace');
      rethrow; // Re-throw so FileSyncService can handle it
    }
  }

  /// Processes the content of a book, extracting lines and TOC entries.
  ///
  /// [bookPath] The path to the book file
  /// [bookId] The ID of the book in the database
  Future<void> processBookContent(String bookPath, int bookId) async {
    final ext = path.extension(bookPath).toLowerCase();

    if (ext == '.pdf') {
      // Process PDF outline as TOC
      await _processPdfOutline(bookPath, bookId);
      await repository.updateBookTotalLines(bookId, 0);
      return;
    }

    if (ext == '.docx') {
      final title = path.basenameWithoutExtension(bookPath);
      final bytes = await File(bookPath).readAsBytes();
      final content = await Isolate.run(() => docxToText(bytes, title));
      final lines = content.split('\n');

      await processLinesWithTocEntries(bookId, lines);
      await repository.updateBookTotalLines(bookId, lines.length);
      return;
    }

    // Prefer preloaded content from RAM if available
    final key = _toLibraryRelativeKey(bookPath);
    final lines = _bookContentCache[key] ?? await readBookLines(bookPath);

    // Process each line one by one, handling TOC entries as we go
    await processLinesWithTocEntries(bookId, lines);

    // Update the total number of lines
    await repository.updateBookTotalLines(bookId, lines.length);
  }

  /// Processes PDF outline and inserts TOC entries into the database.
  Future<void> _processPdfOutline(String bookPath, int bookId) async {
    try {
      final document = await PdfDocument.openFile(bookPath);
      final outline = await document.loadOutline();

      if (outline.isEmpty) {
        _log.info('No outline found in PDF: $bookPath');
        return;
      }

      // Convert outline to TOC entries and insert them
      await _insertPdfOutlineNodes(outline, bookId, null, level: 1);

      _log.info('Processed PDF outline: $bookPath');
    } catch (e, stackTrace) {
      _log.warning('Failed to process PDF outline: $bookPath', e, stackTrace);
    }
  }

  /// Recursively inserts PDF outline nodes as TOC entries.
  Future<void> _insertPdfOutlineNodes(
    List<PdfOutlineNode> nodes,
    int bookId,
    int? parentId, {
    required int level,
  }) async {
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final pageNumber = node.dest?.pageNumber ?? 0;
      final isLastChild = i == nodes.length - 1;
      final hasChildren = node.children.isNotEmpty;

      // Create and insert the TOC entry
      final entry = TocEntry(
        bookId: bookId,
        parentId: parentId,
        text: node.title,
        level: level,
        lineIndex: pageNumber, // Using page number as lineIndex for PDFs
        isLastChild: isLastChild,
        hasChildren: hasChildren,
      );

      final insertedId = await repository.insertTocEntry(entry);

      // Process children recursively with the inserted ID as parent
      if (hasChildren) {
        await _insertPdfOutlineNodes(
          node.children,
          bookId,
          insertedId,
          level: level + 1,
        );
      }
    }
  }

  /// Reads book lines from file
  static Future<List<String>> readBookLines(String bookPath) async {
    final file = File(bookPath);
    try {
      final content = await file.readAsString(encoding: utf8);
      return content.split('\n');
    } on FormatException catch (e) {
      // Try with latin1 encoding if UTF-8 fails
      debugPrint('⚠️ UTF-8 decoding failed for $bookPath, trying latin1: $e');
      try {
        final content = await file.readAsString(encoding: latin1);
        return content.split('\n');
      } catch (e2) {
        debugPrint(
            '❌ Failed to read file with both UTF-8 and latin1: $bookPath');
        rethrow;
      }
    }
  }

  /// Processes lines of a book, identifying and creating TOC entries.
  /// OPTIMIZED: Batch inserts for lines; sequential inserts for tocEntries (needed for
  /// correct parent-ID resolution). After all insertions, tocEntry.lineId is fixed
  /// via SQL (matching on lineIndex) and line_toc is rebuilt correctly.
  ///
  /// [bookId] The ID of the book in the database
  /// [lines] The lines of the book content

  Future<void> processLinesWithTocEntries(
      int bookId, List<String> lines) async {
    // Collect all TOC entry metadata in a single pass.
    // We use the entry's position in allTocEntries as its local ID.
    final allTocEntries = <TocEntryData>[];

    // level → local index of the most recent entry at that level (for parent tracking)
    final localParentStack = <int, int>{};

    // local-parent-index → [local child indices] (for isLastChild / hasChildren)
    final entriesByParent = <int?, List<int>>{};

    const batchSize = 1000;
    final linesBatch = <Line>[];

    // ── PASS 1: Insert lines in batches, collect TOC structure ──────────────
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final plainText = cleanHtml(line);
      final level = detectHeaderLevel(line);

      if (level > 0) {
        if (plainText.trim().isEmpty) {
          localParentStack.remove(level);
        } else {
          // Find the nearest ancestor's local index
          int? parentLocalIdx;
          for (int l = level - 1; l >= 1; l--) {
            if (localParentStack.containsKey(l)) {
              parentLocalIdx = localParentStack[l];
              break;
            }
          }

          final localIdx = allTocEntries.length;
          allTocEntries.add(TocEntryData(
            id: localIdx,
            parentId: parentLocalIdx,
            level: level,
            text: plainText,
            lineIndex: lineIndex,
          ));

          localParentStack[level] = localIdx;
          entriesByParent.putIfAbsent(parentLocalIdx, () => []).add(localIdx);
        }
      }

      linesBatch.add(Line(
        id: 0, // auto-assigned by SQLite
        bookId: bookId,
        lineIndex: lineIndex,
        content: line,
      ));

      if (linesBatch.length >= batchSize) {
        await repository.insertLinesBatch(linesBatch);
        linesBatch.clear();
      }
    }

    if (linesBatch.isNotEmpty) {
      await repository.insertLinesBatch(linesBatch);
    }

    // ── PASS 2: Insert TOC entries one by one to get real DB IDs ─────────────
    // We need sequential insertion because each child's parentId must reference
    // the actual auto-incremented DB ID of its parent (not a placeholder).
    final localIdxToDbId = <int, int>{}; // local index → actual DB ID
    final actualParentStack = <int, int>{}; // level → actual DB ID

    for (final entryData in allTocEntries) {
      // Resolve parent's actual DB ID
      int? parentDbId;
      for (int l = entryData.level - 1; l >= 1; l--) {
        if (actualParentStack.containsKey(l)) {
          parentDbId = actualParentStack[l];
          break;
        }
      }

      final actualId = await repository.insertTocEntry(TocEntry(
        id: 0, // auto-assign
        bookId: bookId,
        parentId: parentDbId,
        text: entryData.text,
        level: entryData.level,
        lineIndex: entryData.lineIndex,
        lineId: null, // fixed by SQL below
        isLastChild: false,
        hasChildren: false,
      ));

      localIdxToDbId[entryData.id] = actualId;
      actualParentStack[entryData.level] = actualId;
    }

    // ── PASS 3: Fix lineId on tocEntries + rebuild line_toc via SQL ──────────
    if (allTocEntries.isNotEmpty) {
      await repository.updateTocEntryLineIdsByLineIndex(bookId);
      await repository.rebuildLineTocForBook(bookId);
    }

    // ── PASS 4: Mark hasChildren / isLastChild ────────────────────────────────
    final parentLocalIdxs = entriesByParent.keys.whereType<int>().toSet();

    final hasChildrenIds = parentLocalIdxs
        .map((idx) => localIdxToDbId[idx])
        .whereType<int>()
        .toList();

    final lastChildIds = entriesByParent.values
        .where((children) => children.isNotEmpty)
        .map((children) => localIdxToDbId[children.last])
        .whereType<int>()
        .toList();

    if (hasChildrenIds.isNotEmpty) {
      await repository.bulkUpdateTocEntryHasChildren(hasChildrenIds, true);
    }
    if (lastChildIds.isNotEmpty) {
      await repository.bulkUpdateTocEntryIsLastChild(lastChildIds, true);
    }
  }

  /// Link processor instance for processing link files
  LinkProcessor? _linkProcessor;

  /// Processes all link files in the links directory.
  /// Links connect lines between different books.
  Future<void> processLinks() async {
    // links directory should be in sourceDirectory (the parent folder)
    final linksPath = path.join(sourceDirectory, 'links');

    // Create link processor if needed
    _linkProcessor ??= LinkProcessor(repository, verboseLogging: false);

    // Use the unified processLinksDirectory method
    await _linkProcessor!.processLinksDirectory(
      linksPath: linksPath,
      onProgress: onProgress,
      updateBookHasLinks: true,
      batchCommitSize: 50,
    );
  }

  /// Extracts topics from the file path.
  /// Topics are derived from the directory structure.
  ///
  /// [path] The path to the book file
  /// Returns a list of topics extracted from the path
  List<Topic> extractTopics(String bookPath) {
    // Extract topics from the path
    final parts = path.split(bookPath);
    final topicNames = parts
        .take(parts.length - 1)
        .toList()
        .reversed
        .take(2)
        .toList()
        .reversed;

    return topicNames.map((name) => Topic(name: name)).toList();
  }

  /// Helper methods for source management and priority processing

  /// Deletes a directory if it is empty.
  Future<void> _deleteIfEmpty(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      if (await dir.list().isEmpty) {
        await dir.delete();
        _log.info('Deleted empty directory: ${dir.path}');
      }
    } catch (e) {
      // Ignore deletion mistakes (e.g. permissions)
    }
  }

  /// Compute a normalized key for a book file relative to the library root
  String _toLibraryRelativeKey(String filePath) {
    try {
      final rel =
          path.relative(filePath, from: _libraryRoot).replaceAll('\\', '/');
      return rel;
    } catch (e) {
      return path.basename(filePath);
    }
  }

  /// Resolve a source id for a book file using the manifest mapping
  Future<int> _resolveSourceIdFor(String filePath) async {
    final sourceName = 'Personal';
    final cached = _sourceNameToId[sourceName];
    if (cached != null) return cached;
    final id = await repository.insertSource(sourceName, -1);
    _sourceNameToId[sourceName] = id;
    return id;
  }

  /// Count txt files in directory for progress tracking
  Future<int> _countFiles(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      var count = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File &&
            ['.txt', '.pdf', '.docx']
                .contains(path.extension(entity.path).toLowerCase())) {
          count++;
        }
      }
      return count;
    } catch (e) {
      return 0;
    }
  }

  /// Disables foreign key constraints
  Future<void> _disableForeignKeys() async {
    await repository.executeRawQuery('PRAGMA foreign_keys = OFF');
  }

  /// Re-enables foreign key constraints
  Future<void> _enableForeignKeys() async {
    await repository.executeRawQuery('PRAGMA foreign_keys = ON');
  }

  /// Sanitizes an acronym term by removing diacritics, maqaf, gershayim and geresh.
  ///
  /// [raw] The raw acronym term to sanitize.
  /// Returns the sanitized term.
  static String sanitizeAcronymTerm(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';

    s = hebrew_text_utils.removeAllDiacritics(s);
    s = hebrew_text_utils.replaceMaqaf(s, replacement: ' ');
    s = s.replaceAll('\u05F4', ''); // remove Hebrew gershayim (״)
    s = s.replaceAll('\u05F3', ''); // remove Hebrew geresh (׳)
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    return s;
  }
}

/// Structure to store TOC entry data during processing
class TocEntryData {
  final int id;
  final int? parentId;
  final int level;
  final String text;
  final int lineIndex;

  const TocEntryData({
    required this.id,
    this.parentId,
    required this.level,
    required this.text,
    required this.lineIndex,
  });
}

/// Utility functions for HTML and text processing
String cleanHtml(String html) {
  // Simple HTML tag removal - replace with space to avoid concatenating words
  final tagRegex = RegExp(r'<[^>]*>');
  final cleaned = html.replaceAll(tagRegex, ' ');
  // Clean up multiple spaces and trim
  return hebrew_text_utils.removeNikud(
    cleaned.replaceAll(RegExp(r'\s+'), ' ').trim(),
  );
}

int detectHeaderLevel(String line) {
  final lowerLine = line.toLowerCase();
  if (lowerLine.startsWith('<h1')) return 1;
  if (lowerLine.startsWith('<h2')) return 2;
  if (lowerLine.startsWith('<h3')) return 3;
  if (lowerLine.startsWith('<h4')) return 4;
  if (lowerLine.startsWith('<h5')) return 5;
  if (lowerLine.startsWith('<h6')) return 6;
  return 0;
}
