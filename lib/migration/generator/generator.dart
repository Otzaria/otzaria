import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import '../core/models/author.dart';
import '../core/models/book.dart';
import '../core/models/book_metadata.dart';
import '../core/models/category.dart';
import '../core/models/line.dart';
import '../core/models/pub_date.dart';
import '../core/models/pub_place.dart';
import '../core/models/toc_entry.dart';
import '../core/models/topic.dart';
import '../dao/repository/seforim_repository.dart';
import '../shared/link_processor.dart';
import 'hebrew_text_utils.dart' as hebrew_text_utils;

/// DatabaseGenerator is responsible for generating the Otzaria database from source files.
/// It processes directories, books, and links to create a structured database.
///
/// This is a Dart conversion of the original Kotlin DatabaseGenerator.
class DatabaseGenerator {
  static final _log = Logger('DatabaseGenerator');

  /// The path to the source directory containing the data files
  final String sourceDirectory;

  /// Cache for acronym data loaded from acronym.json
  Map<String, dynamic>? _acronymData;

  /// The repository used to store the generated data
  final SeforimRepository repository;

  final JsonCodec _json;

  /// Callback for progress updates
  final void Function(double progress, String message)? onProgress;

  /// Callback to handle duplicate books. Returns true to replace, false to skip.
  /// If null, duplicates will be skipped by default.
  /// Parameters: bookTitle, categoryId
  Future<bool> Function(String bookTitle, int categoryId)? onDuplicateBook;

  /// Counter for book IDs
  int _nextBookId = 1;

  /// Counter for line IDs
  int _nextLineId = 1;

  /// Counter for TOC entry IDs
  int _nextTocEntryId = 1;

  /// Library root path for relative path computations
  late String _libraryRoot;

  /// Map from library-relative book key to source name
  final Map<String, String> _manifestSourcesByRel = {};

  /// Cache of source name -> id from DB
  final Map<String, int> _sourceNameToId = {};

  /// Source blacklist
  final Set<String> _sourceBlacklist = {'wiki_jewish_books'};

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
      : _json = const JsonCodec(reviver: _jsonReviver);

  /// Sets the ID counters.
  void setIds(int nextBookId, int nextLineId, int nextTocEntryId) {
    _nextBookId = nextBookId;
    _nextLineId = nextLineId;
    _nextTocEntryId = nextTocEntryId;
  }

  /// Sets the total books to process for progress reporting.
  void setTotalBooksToProcess(int total) {
    _totalBooksToProcess = total;
  }

  /// Initializes the generator for sync operations where generate() is not called.
  /// [libraryRoot] Optional root path for library-relative calculations.
  void initializeForSync({String? libraryRoot}) {
    _libraryRoot = libraryRoot ?? sourceDirectory;
  }

  /// Gets the current ID counters.
  ({int bookId, int lineId, int tocId}) getIds() {
    return (bookId: _nextBookId, lineId: _nextLineId, tocId: _nextTocEntryId);
  }

  /// JSON reviver to handle numeric values that might come as doubles
  static dynamic _jsonReviver(Object? key, Object? value) {
    if (value is double && value == value.toInt().toDouble()) {
      return value.toInt();
    }
    return value;
  }

  /// Generates the database by processing metadata, directories, and links.
  /// This is the main entry point for the database generation process.
  Future<void> generate() async {
    try {
      // Disable foreign keys for better performance
      await _disableForeignKeys();

      // Set maximum performance mode for bulk generation
      await repository.setMaxPerformanceMode();

      // Load metadata
      final metadata = await loadMetadata();

      // Load sources from files_manifest.json and upsert source table
      await _loadSourcesFromManifest();
      await _precreateSourceEntries();

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

      // Process priority books first (if any)
      try {
        await _processPriorityBooks(metadata);
      } catch (e) {
        _log.warning(
            'Failed processing priority list; continuing with full generation',
            e);
      }

      // Preload all book contents into RAM
      await _preloadAllBookContents(libraryPath);
      await processDirectory(libraryPath, null, 0, metadata);

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

  /// Loads book metadata from the metadata.json file.
  /// Attempts to parse the file in different formats (Map or List).
  ///
  /// Returns a map of book titles to their metadata
  Future<Map<String, BookMetadata>> loadMetadata() async {
    // metadata.json should be in sourceDirectory (the parent folder)
    final metadataFile = File(path.join(sourceDirectory, 'metadata.json'));

    if (!await metadataFile.exists()) {
      return {};
    }

    final content = await metadataFile.readAsString();
    try {
      // Try to parse as Map first (original format)
      final metadataMap = _json.decode(content) as Map<String, dynamic>;
      return metadataMap.map((key, value) =>
          MapEntry(key, BookMetadata.fromJson(value as Map<String, dynamic>)));
    } catch (e) {
      // If that fails, try to parse as List and convert to Map
      try {
        final metadataList = (_json.decode(content) as List<dynamic>)
            .map((item) => BookMetadata.fromJson(item as Map<String, dynamic>))
            .toList();
        // Convert list to map using title as key
        return {for (var item in metadataList) item.title: item};
      } catch (e) {
        return {};
      }
    }
  }

  /// Processes a directory recursively, creating categories and books.
  ///
  /// [directory] The directory to process
  /// [parentCategoryId] The ID of the parent category, if any
  /// [level] The current level in the directory hierarchy
  /// [metadata] The metadata for books
  Future<void> processDirectory(
    String directory,
    int? parentCategoryId,
    int level,
    Map<String, BookMetadata> metadata,
  ) async {
    final dir = Directory(directory);
    final entities = await dir.list().toList();
    final sortedEntities = entities
      ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

    for (final entity in sortedEntities) {
      if (entity is Directory) {
        final categoryId =
            await createCategory(entity.path, parentCategoryId, level);
        await processDirectory(entity.path, categoryId, level + 1, metadata);
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
        await createAndProcessBook(entity.path, parentCategoryId, metadata);
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

  /// Creates a book in the database and processes its content.
  ///
  /// [bookPath] The path to the book file
  /// [categoryId] The ID of the category the book belongs to
  /// [metadata] The metadata for the book
  /// [isBaseBook] Whether this is a base/priority book
  Future<void> createAndProcessBook(
    String bookPath,
    int categoryId,
    Map<String, BookMetadata> metadata, {
    bool isBaseBook = false,
    bool insertContent = true,
    bool updateExisting = false,
  }) async {
    final filename = path.basename(bookPath);
    final title = path.basenameWithoutExtension(filename);
    final meta = metadata[title];
    // Apply source blacklist
    final srcName = _getSourceNameFor(bookPath);
    if (_sourceBlacklist.contains(srcName)) {
      _processedBooksCount++;
      onProgress?.call(
          _processedBooksCount /
              (_totalBooksToProcess > 0 ? _totalBooksToProcess : 1),
          'מדלג על ספר: $title');
      return;
    }

    // Extract file type from the file path
    final fileExtension = path.extension(bookPath).toLowerCase();
    final fileType = fileExtension.startsWith('.')
        ? fileExtension.substring(1)
        : fileExtension;

    // Check for duplicates in the same category with the same file type (for performance measurement)
    final existingBook = await repository.checkBookExistsInCategoryWithFileType(
        title, categoryId, fileType);
    if (existingBook != null) {
      if (updateExisting) {
        if (fileType == 'txt' && insertContent) {
          await repository.clearBookContent(existingBook.id);
          await processBookContent(bookPath, existingBook.id);
        } else {
          try {
            final file = File(bookPath);
            final stat = await file.stat();
            await repository.updateExternalBookMetadata(
                existingBook.id, stat.size, stat.modified.millisecondsSinceEpoch);
          } catch (e) {
            _log.warning('Failed to update stats for external file: $bookPath', e);
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

         // Delete source files if it's a txt file
        if (fileType == 'txt') {
          try {
            final file = File(bookPath);
            if (await file.exists()) {
              await file.delete();
            }
            // Also delete companion notes file if it exists
            final dir = Directory(path.dirname(bookPath));
            final notesTitle = 'הערות על $title';
            final notesPath = path.join(dir.path, '$notesTitle.txt');
            final notesFile = File(notesPath);
            if (await notesFile.exists()) {
              await notesFile.delete();
            }
          } catch (e) {
            _log.warning('Failed to delete source file(s) for $title', e);
          }
        }
        return;
      }

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

    // Assign a unique ID to this book
    final currentBookId = _nextBookId++;

    // Create author list if author is available in metadata
    final authors =
        meta?.author != null ? [Author(name: meta!.author!)] : <Author>[];

    // Create publication places list if pubPlace is available in metadata
    final pubPlaces = meta?.pubPlace != null
        ? [PubPlace(name: meta!.pubPlace!)]
        : <PubPlace>[];

    // Create publication dates list if pubDate is available in metadata
    final pubDates =
        meta?.pubDate != null ? [PubDate(date: meta!.pubDate!)] : <PubDate>[];

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
    if (fileType != 'txt' || !insertContent) {
      try {
        final file = File(bookPath);
        final stat = await file.stat();
        fileSize = stat.size;
        lastModified = stat.modified.millisecondsSinceEpoch;
      } catch (e) {
        _log.warning('Failed to get stats for external file: $bookPath', e);
      }
    }

    final sourceId = await _resolveSourceIdFor(bookPath);
    final book = Book(
      id: currentBookId,
      categoryId: categoryId,
      sourceId: sourceId,
      title: title,
      authors: authors,
      pubPlaces: pubPlaces,
      pubDates: pubDates,
      heShortDesc: meta?.heShortDesc,
      notesContent: notesContent,
      order: meta?.order ?? 999.0,
      topics: extractTopics(bookPath),
      isBaseBook: isBaseBook,
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

    // Insert acronyms for this book
    try {
      final terms = await fetchAcronymsForTitle(title);
      if (terms.isNotEmpty) {
        await repository.bulkInsertBookAcronyms(insertedBookId, terms);
      }
    } catch (e) {
      // Ignore acronym errors
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

    // Delete source files if it's a txt file
    if (fileType == 'txt' && insertContent) {
      try {
        final file = File(bookPath);
        if (await file.exists()) {
          await file.delete();
        }
        // Also delete companion notes file if it exists
        final dir = Directory(path.dirname(bookPath));
        final notesTitle = 'הערות על $title';
        final notesPath = path.join(dir.path, '$notesTitle.txt');
        final notesFile = File(notesPath);
        if (await notesFile.exists()) {
          await notesFile.delete();
        }
      } catch (e) {
        _log.warning('Failed to delete source file(s) for $title', e);
      }
    }
  }

  /// Processes the content of a book, extracting lines and TOC entries.
  ///
  /// [bookPath] The path to the book file
  /// [bookId] The ID of the book in the database
  Future<void> processBookContent(String bookPath, int bookId) async {
    final ext = path.extension(bookPath).toLowerCase();
    if (ext == '.pdf' || ext == '.docx') {
      await repository.updateBookTotalLines(bookId, 0);
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

  /// Reads book lines from file
  static Future<List<String>> readBookLines(String bookPath) async {
    final file = File(bookPath);
    final content = await file.readAsString(encoding: utf8);
    return content.split('\n');
  }

  /// Processes lines of a book, identifying and creating TOC entries.
  /// OPTIMIZED: Uses batch inserts for maximum performance
  ///
  /// [bookId] The ID of the book in the database
  /// [lines] The lines of the book content

  Future<void> processLinesWithTocEntries(
      int bookId, List<String> lines) async {
    // Data structures for TOC processing
    final allTocEntries = <TocEntryData>[];
    final parentStack = <int, int>{};
    final entriesByParent = <int?, List<int>>{};
    int? currentOwningTocEntryId;

    // Batch buffers
    final linesBatch = <Line>[];
    final tocEntriesBatch = <TocEntry>[];
    final lineTocBuffer = <({int lineId, int tocId})>[];
    final tocUpdates = <({int tocId, int lineId})>[];

    const batchSize = 1000;

    // First pass - collect all data
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final plainText = cleanHtml(line);
      final level = detectHeaderLevel(line);

      if (level > 0) {
        if (plainText.trim().isEmpty) {
          parentStack.remove(level);
          continue;
        }

        int? parentId;
        for (int l = level - 1; l >= 1; l--) {
          if (parentStack.containsKey(l)) {
            parentId = parentStack[l];
            break;
          }
        }

        final currentTocEntryId = _nextTocEntryId++;
        final currentLineId = _nextLineId++;

        // Store TOC entry info
        allTocEntries.add(TocEntryData(
          id: currentTocEntryId,
          parentId: parentId,
          level: level,
          text: plainText,
          lineIndex: lineIndex,
        ));

        // Buffer TOC entry
        tocEntriesBatch.add(TocEntry(
          id: currentTocEntryId,
          bookId: bookId,
          parentId: parentId,
          text: plainText,
          level: level,
          lineId: null,
          isLastChild: false,
          hasChildren: false,
        ));

        parentStack[level] = currentTocEntryId;
        entriesByParent.putIfAbsent(parentId, () => []).add(currentTocEntryId);
        currentOwningTocEntryId = currentTocEntryId;

        // Buffer line
        linesBatch.add(Line(
          id: currentLineId,
          bookId: bookId,
          lineIndex: lineIndex,
          content: line,
        ));

        // Store update for later
        tocUpdates.add((tocId: currentTocEntryId, lineId: currentLineId));

        // Buffer line-toc mapping
        lineTocBuffer.add((lineId: currentLineId, tocId: currentTocEntryId));
      } else {
        // Regular line
        final currentLineId = _nextLineId++;

        linesBatch.add(Line(
          id: currentLineId,
          bookId: bookId,
          lineIndex: lineIndex,
          content: line,
        ));

        // Buffer mapping for regular line if there is a current owner
        if (currentOwningTocEntryId != null) {
          lineTocBuffer
              .add((lineId: currentLineId, tocId: currentOwningTocEntryId));
        }
      }

      // Flush batches when they reach size limit
      if (linesBatch.length >= batchSize) {
        await repository.insertLinesBatch(linesBatch);
        linesBatch.clear();
      }
      if (tocEntriesBatch.length >= batchSize) {
        await repository.insertTocEntriesBatch(tocEntriesBatch);
        tocEntriesBatch.clear();
      }
    }

    // Flush remaining batches
    if (linesBatch.isNotEmpty) {
      await repository.insertLinesBatch(linesBatch);
    }
    if (tocEntriesBatch.isNotEmpty) {
      await repository.insertTocEntriesBatch(tocEntriesBatch);
    }
    if (lineTocBuffer.isNotEmpty) {
      await repository.bulkUpsertLineToc(lineTocBuffer);
    }

    // Update TOC entries with their line IDs in batch
    if (tocUpdates.isNotEmpty) {
      await repository.bulkUpdateTocEntryLineIds(tocUpdates);
    }

    // Second pass: Update isLastChild and hasChildren in batch
    final parentIds =
        allTocEntries.map((e) => e.parentId).whereType<int>().toSet();

    // Collect IDs to update
    final hasChildrenIds = allTocEntries
        .where((e) => parentIds.contains(e.id))
        .map((e) => e.id)
        .toList();
    final lastChildIds = entriesByParent.values
        .where((children) => children.isNotEmpty)
        .map((children) => children.last)
        .toList();

    // Batch update
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
    final linksDir = Directory(path.join(sourceDirectory, 'links'));

    if (!await linksDir.exists()) {
      return;
    }
    // Create link processor and load books cache
    _linkProcessor = LinkProcessor(repository, verboseLogging: false);
    await _linkProcessor!.loadBooksCache();

    // First, count total link files for progress tracking
    final linkFiles = <File>[];
    await for (final entity in linksDir.list()) {
      if (entity is File && path.extension(entity.path) == '.json') {
        linkFiles.add(entity);
      }
    }

    final totalLinkFiles = linkFiles.length;
    var processedLinkFiles = 0;
    var totalLinks = 0;

    // Report initial progress for links phase
    onProgress?.call(0.0, 'מתחיל עיבוד קישורים (0/$totalLinkFiles קבצים)');

    // Process all link files within a single transaction for better performance
    await repository.beginTransaction();

    // Track files to delete after successful commit
    final filesToDelete = <File>[];

    try {
      for (final file in linkFiles) {
        if (file.path.endsWith('_headings.json')) {
          continue;
        }

        final result = await _linkProcessor!.processLinkFile(file.path);
        totalLinks += result.processedLinks;
        processedLinkFiles++;

        final progress =
            totalLinkFiles > 0 ? processedLinkFiles / totalLinkFiles : 0.0;
        final fileName = path.basename(file.path);
        onProgress?.call(progress,
            'מעבד קישורים: $fileName ($processedLinkFiles/$totalLinkFiles)');

        // Add to deletion list only if successful
        if (result.success) {
          filesToDelete.add(file);
        }

        // Commit transaction every 50 files to avoid excessive memory usage
        if (processedLinkFiles % 50 == 0) {
          await repository.commitTransaction();

          // Delete files that were just committed
          for (final f in filesToDelete) {
            try {
              if (await f.exists()) {
                await f.delete();
                _log.info('Deleted processed link file: ${f.path}');
              }
            } catch (e) {
              _log.warning('Failed to delete link file ${f.path}', e);
            }
          }
          filesToDelete.clear();

          // Clear line cache to prevent memory explosion
          _linkProcessor!.clearLineCache();
          await repository.beginTransaction();
        }
      }

      // Commit the transaction after all links are processed
      await repository.commitTransaction();

      // Delete remaining files
      for (final f in filesToDelete) {
        try {
          if (await f.exists()) {
            await f.delete();
            _log.info('Deleted processed link file: ${f.path}');
          }
        } catch (e) {
          _log.warning('Failed to delete link file ${f.path}', e);
        }
      }
      filesToDelete.clear();

      // Clear caches to free memory
      _linkProcessor!.clearCaches();
    } catch (e) {
      // Rollback on error
      _log.severe('Error during link processing, rolling back transaction', e);
      await repository.rollbackTransaction();
      rethrow;
    }

    // Update the book_has_links table
    onProgress?.call(1.0, 'מעדכן טבלת קישורים לספרים...');
    await updateBookHasLinksTable();

    // Final progress update with summary
    onProgress?.call(
        1.0, 'הושלם עיבוד $totalLinks קישורים מ-$totalLinkFiles קבצים');

    // Delete links directory if it became empty
    await _deleteIfEmpty(linksDir);
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

  /// Updates the book_has_links table to indicate which books have source links, target links, or both.
  /// This should be called after all links have been processed.
  Future<void> updateBookHasLinksTable() async {
    // 1. Update book_has_links table using bulk SQL
    // We use INSERT OR REPLACE to update existing entries or insert new ones
    await repository.executeRawQuery('''
      INSERT OR REPLACE INTO book_has_links (bookId, hasSourceLinks, hasTargetLinks)
      SELECT 
        b.id,
        CASE WHEN EXISTS (SELECT 1 FROM link WHERE sourceBookId = b.id) THEN 1 ELSE 0 END,
        CASE WHEN EXISTS (SELECT 1 FROM link WHERE targetBookId = b.id) THEN 1 ELSE 0 END
      FROM book b
      WHERE 
        EXISTS (SELECT 1 FROM link WHERE sourceBookId = b.id) 
        OR 
        EXISTS (SELECT 1 FROM link WHERE targetBookId = b.id)
    ''');

    // 2. Update connection flags in book table
    final connectionTypes = await repository.getAllConnectionTypesObj();
    final typeMap = <String, int>{};
    for (final type in connectionTypes) {
      typeMap[type.name.toUpperCase()] = type.id;
    }

    String query = '''
      WITH book_connections AS (
    SELECT 
        book_id,
        MAX(CASE WHEN connectionTypeId = 2 THEN 1 ELSE 0 END) as has_targum,
        MAX(CASE WHEN connectionTypeId = 3 THEN 1 ELSE 0 END) as has_reference,
        MAX(CASE WHEN connectionTypeId = 1 THEN 1 ELSE 0 END) as has_commentary,
        MAX(CASE WHEN connectionTypeId = 4 THEN 1 ELSE 0 END) as has_other
    FROM (
        SELECT sourceBookId as book_id, connectionTypeId FROM link
        UNION ALL
        SELECT targetBookId as book_id, connectionTypeId FROM link
    ) all_connections
    GROUP BY book_id
)
UPDATE book 
SET 
    hasTargumConnection = COALESCE(bc.has_targum, 0),
    hasReferenceConnection = COALESCE(bc.has_reference, 0),
    hasCommentaryConnection = COALESCE(bc.has_commentary, 0),
    hasOtherConnection = COALESCE(bc.has_other, 0)
FROM book_connections bc
WHERE book.id = bc.book_id;
    ''';
    // Update all books that have links
    _log.fine(query);
    await repository.executeRawQuery(query);

    // Get stats for logging
    final db = await repository.database.database;
    final stats = await db.rawQuery('''
      SELECT 
        SUM(hasSourceLinks) as source,
        SUM(hasTargetLinks) as target,
        COUNT(*) as total
      FROM book_has_links
    ''');

    final row = stats.first;
    final booksWithSourceLinks = row['source'] ?? 0;
    final booksWithTargetLinks = row['target'] ?? 0;
    final booksWithAnyLinks = row['total'] ?? 0;

    _log.info('Book_has_links table updated. Found:');
    _log.info('- $booksWithSourceLinks books with source links');
    _log.info('- $booksWithTargetLinks books with target links');
    _log.info('- $booksWithAnyLinks books with any links (source or target)');
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

  /// Loads files_manifest.json and builds mapping from library-relative path to source name
  Future<void> _loadSourcesFromManifest() async {
    _manifestSourcesByRel.clear();
    // files_manifest.json should be in sourceDirectory (the parent folder)
    final manifestFile =
        File(path.join(sourceDirectory, 'files_manifest.json'));

    if (!await manifestFile.exists()) {
      _log.warning(
          'files_manifest.json not found in $sourceDirectory; assigning source \'Unknown\' to all books');
      return;
    }

    try {
      final content = await manifestFile.readAsString();
      final map = _json.decode(content) as Map<String, dynamic>;

      for (final entry in map.entries) {
        final pathStr = entry.key;
        final parts = pathStr.split('/');
        if (parts.isEmpty) continue;

        final sourceName = parts.first;
        final idx = parts.indexOf('אוצריא');
        if (idx < 0 || idx == parts.length - 1) continue;

        final rel = parts.skip(idx + 1).join('/');
        final prev = _manifestSourcesByRel.putIfAbsent(rel, () => sourceName);
        if (prev != sourceName) {
          _log.warning(
              'Duplicate source mapping for \'$rel\': existing=$prev new=$sourceName; keeping existing');
        }
      }
    } catch (e) {
      _log.warning(
          'Failed to parse files_manifest.json; sources will be \'Unknown\'',
          e);
    }
  }

  /// Ensure all known source names from manifest are present in DB
  Future<void> _precreateSourceEntries() async {
    // Always ensure 'Unknown' exists
    final unknownId = await repository.insertSource('Unknown');
    _sourceNameToId['Unknown'] = unknownId;

    // Insert all discovered sources
    final uniqueSources = _manifestSourcesByRel.values.toSet();
    for (final name in uniqueSources) {
      final id = await repository.insertSource(name);
      _sourceNameToId[name] = id;
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
    final rel = _toLibraryRelativeKey(filePath);
    final sourceName = _manifestSourcesByRel[rel] ?? 'Unknown';
    final cached = _sourceNameToId[sourceName];
    if (cached != null) return cached;
    final id = await repository.insertSource(sourceName);
    _sourceNameToId[sourceName] = id;
    return id;
  }

  String _getSourceNameFor(String filePath) {
    final rel = _toLibraryRelativeKey(filePath);
    return _manifestSourcesByRel[rel] ?? 'Unknown';
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

  /// Preload all book file contents into RAM
  Future<void> _preloadAllBookContents(String libraryPath) async {
    if (_bookContentCache.isNotEmpty) return;

    final files = <String>[];
    final dir = Directory(libraryPath);
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && path.extension(entity.path) == '.txt') {
        final rel = _toLibraryRelativeKey(entity.path);
        final src = _manifestSourcesByRel[rel] ?? 'Unknown';
        if (_sourceBlacklist.contains(src)) {
          continue;
        }
        files.add(entity.path);
      }
    }

    // Preload regular books
    for (final filePath in files) {
      try {
        final key = _toLibraryRelativeKey(filePath);
        final content = await File(filePath).readAsString();
        _bookContentCache[key] = content.split('\n');
      } catch (e) {
        _log.warning('Failed to preload $filePath', e);
      }
    }
  }

  /// Process priority books first
  Future<void> _processPriorityBooks(Map<String, BookMetadata> metadata) async {
    final entries = await _loadPriorityList();
    if (entries.isEmpty) {
      _log.warning('No priority entries found');
      return;
    }

    for (var idx = 0; idx < entries.length; idx++) {
      final relative = entries[idx];
      final parts = relative.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.isEmpty) continue;

      final categories =
          parts.length > 1 ? parts.sublist(0, parts.length - 1) : <String>[];
      final bookFileName = parts.last;

      // Build filesystem path
      var currentPath = _libraryRoot;
      for (final cat in categories) {
        currentPath = path.join(currentPath, cat);
      }
      final bookPath = path.join(currentPath, bookFileName);

      if (!await File(bookPath).exists()) {
        _log.warning(
            'Priority entry ${idx + 1}/${entries.length}: file not found: $bookPath');
        continue;
      }

      // Avoid duplicates
      final key = _toLibraryRelativeKey(bookPath);
      if (_processedPriorityBookKeys.contains(key)) {
        continue;
      }

      // Ensure categories exist
      int? parentId;
      var level = 0;
      var catPath = _libraryRoot;
      for (final cat in categories) {
        catPath = path.join(catPath, cat);
        parentId = await createCategory(catPath, parentId, level);
        level++;
      }

      if (parentId == null) {
        _log.warning(
            'Priority entry ${idx + 1}/${entries.length}: missing parent category for $bookPath; skipping');
        continue;
      }

      await createAndProcessBook(bookPath, parentId, metadata,
          isBaseBook: true);

      _processedPriorityBookKeys.add(key);
    }
  }

  /// Load priority list from resources
  /// Reads the priority list from file and returns normalized relative paths under the library root.
  Future<List<String>> _loadPriorityList() async {
    try {
      // priority should be in "אודות התוכנה" subdirectory
      final priorityPath =
          path.join(sourceDirectory, 'אוצריא', 'אודות התוכנה', 'priority');
      final priorityFile = File(priorityPath);

      if (!await priorityFile.exists()) {
        _log.warning('priority not found at $priorityPath');
        return [];
      }

      final content = await priorityFile.readAsString(encoding: utf8);
      final lines = content.split('\n');

      final result = <String>[];
      for (var line in lines) {
        var s = line.trim();

        // Skip empty lines and comments
        if (s.isEmpty || s.startsWith('#')) continue;

        // Normalize separators
        s = s.replaceAll('\\', '/');

        // Remove BOM if present
        if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) {
          s = s.substring(1);
        }

        // Remove leading slash
        if (s.startsWith('/')) {
          s = s.substring(1);
        }

        // Try to start from 'אוצריא' if present
        final idx = s.indexOf('אוצריא');
        if (idx >= 0) {
          s = s.substring(idx + 'אוצריא'.length);
          if (s.startsWith('/')) {
            s = s.substring(1);
          }
        }

        // Filter for supported files
        final lower = s.toLowerCase();
        if (lower.endsWith('.txt') ||
            lower.endsWith('.pdf') ||
            lower.endsWith('.docx')) {
          result.add(s);
        }
      }
      return result;
    } catch (e) {
      _log.warning('Unable to read priority.txt', e);
      return [];
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

  /// Fetches and sanitizes acronym terms for a given book title from acronym.json.
  ///
  /// The acronym.json file is expected to be in "אודות התוכנה" subdirectory.
  /// [title] The book title to look up.
  /// Returns a list of sanitized acronym terms, or empty list if not found.
  Future<List<String>> fetchAcronymsForTitle(String title) async {
    // acronym.json should be in "אודות התוכנה" subdirectory
    final acronymPath =
        path.join(sourceDirectory, 'אוצריא', 'אודות התוכנה', 'acronym.json');

    try {
      // Load acronym data if not already cached
      if (_acronymData == null) {
        final file = File(acronymPath);
        if (!await file.exists()) {
          _log.warning('acronym.json not found at $acronymPath');
          return [];
        }

        final content = await file.readAsString();
        final decoded = _json.decode(content);

        // Handle both Map and List formats
        if (decoded is Map<String, dynamic>) {
          _acronymData = decoded;
        } else if (decoded is List) {
          // Convert list to map using 'title' field as key
          _acronymData = <String, dynamic>{};
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              final itemTitle = item['book_title'] as String?;
              if (itemTitle != null) {
                _acronymData![itemTitle] = item;
              }
            }
          }
        } else {
          _log.warning('Unexpected acronym.json format');
          _acronymData = <String, dynamic>{};
        }
      }

      // Look up the title in the acronym data
      final entry = _acronymData![title];
      if (entry == null) {
        return [];
      }

      // Extract terms - handle both string and list formats
      String? raw;
      if (entry is String) {
        raw = entry;
      } else if (entry is Map<String, dynamic>) {
        raw = entry['terms'] as String?;
      } else if (entry is List) {
        // If it's already a list, process each item
        final parts = entry.map((e) => e.toString()).toList();
        final clean = parts
            .map((t) => sanitizeAcronymTerm(t))
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();

        final titleNormalized = sanitizeAcronymTerm(title);
        return clean
            .where((t) => !t.toLowerCase().contains(title.toLowerCase()))
            .where(
                (t) => !t.toLowerCase().contains(titleNormalized.toLowerCase()))
            .toSet()
            .toList();
      }

      if (raw == null || raw.isEmpty) {
        return [];
      }

      // Split by comma and sanitize each term
      final parts = raw.split(',');
      final clean = parts
          .map((t) => sanitizeAcronymTerm(t))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      // De-duplicate and drop items identical to the title after normalization
      final titleNormalized = sanitizeAcronymTerm(title);
      return clean
          .where((t) => !t.toLowerCase().contains(title.toLowerCase()))
          .where(
              (t) => !t.toLowerCase().contains(titleNormalized.toLowerCase()))
          .toSet()
          .toList();
    } catch (e) {
      _log.warning(
          'Error reading acronyms for \'$title\' from $acronymPath', e);
      return [];
    }
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
