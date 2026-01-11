import 'dart:async';
import 'package:logging/logging.dart';

import '../../core/models/author.dart';
import '../../core/models/book.dart';
import '../../core/models/category.dart';
import '../../core/models/line.dart';
import '../../core/models/link.dart';
import '../../core/models/pub_date.dart';
import '../../core/models/pub_place.dart';
import '../../core/models/search_result.dart';
import '../../core/models/source.dart';
import '../../core/models/toc_entry.dart';
import '../../core/models/toc_text.dart';
import '../../core/models/topic.dart';
import '../daos/connection_type_dao.dart';
import '../daos/database.dart';

/// Repository class for accessing and manipulating the Seforim database.
/// Provides methods for CRUD operations on books, categories, lines, TOC entries, and links.
///
/// This is a Dart conversion of the original Kotlin SeforimRepository.
class SeforimRepository {
  final MyDatabase _database;
  final Logger _logger = Logger('SeforimRepository');

  /// Expose database for advanced operations
  MyDatabase get database => _database;

  bool _initialized = false;

  SeforimRepository(this._database);

  /// Ensures the database is initialized before use
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await _initialize();
    _initialized = true;
  }

  Future<void> _initialize() async {
    _logger.info('Initializing SeforimRepository');
    
    // Ensure QueryLoader and database are initialized first
    await _database.database;
    
    // Database schema creation is handled by MyDatabase
    // SQLite optimizations for normal operations
    await _executeRawQuery('PRAGMA journal_mode=WAL');
    await _executeRawQuery('PRAGMA synchronous=NORMAL');
    await _executeRawQuery('PRAGMA cache_size=100000');
    await _executeRawQuery('PRAGMA temp_store=MEMORY');
    await _executeRawQuery('PRAGMA mmap_size=268435456');
    await _executeRawQuery('PRAGMA page_size=4096');

    // Check if the database is empty
    try {
      final count = await _database.bookDao.countAllBooks();
      _logger.info('Database contains $count books');
      
      // Initialize connection types cache
      await initializeConnectionTypes();
    } catch (e) {
      _logger.info('Error counting books: ${e.toString()}');
    }
  }

  // --- Line ⇄ TOC mapping ---

  /// Maps a line to the TOC entry it belongs to. Upserts on conflict.
  Future<void> upsertLineToc(int lineId, int tocEntryId) async {
    final db = await _database.database;
    await db.rawInsert(
        'INSERT OR REPLACE INTO line_toc (lineId, tocEntryId) VALUES (?, ?)',
        [lineId, tocEntryId]);
  }

  /// Bulk upsert line→toc mappings
  Future<void> bulkUpsertLineToc(List<({int lineId, int tocId})> pairs) async {
    if (pairs.isEmpty) return;
    final db = await _database.database;
    final batch = db.batch();
    for (final pair in pairs) {
      batch.rawInsert(
          'INSERT OR REPLACE INTO line_toc (lineId, tocEntryId) VALUES (?, ?)',
          [pair.lineId, pair.tocId]);
    }
    await batch.commit(noResult: true);
  }

  /// Gets the tocEntryId associated with a line via the mapping table.
  Future<int?> getTocEntryIdForLine(int lineId) async {
    final db = await _database.database;
    final result = await db
        .rawQuery('SELECT tocEntryId FROM line_toc WHERE lineId = ?', [lineId]);
    if (result.isEmpty) return null;
    return result.first['tocEntryId'] as int;
  }

  /// Gets the TocEntry model associated with a line via the mapping table.
  Future<TocEntry?> getTocEntryForLine(int lineId) async {
    final tocId = await getTocEntryIdForLine(lineId);
    if (tocId == null) return null;
    return await getTocEntry(tocId);
  }

  /// Returns the TOC entry whose heading line is the given line id, or null if not a TOC heading.
  Future<TocEntry?> getHeadingTocEntryByLineId(int lineId) async {
    return await _database.tocDao.selectByLineId(lineId);
  }

  /// Returns all line ids that belong to the given TOC entry (section), ordered by lineIndex.
  Future<List<int>> getLineIdsForTocEntry(int tocEntryId) async {
    final db = await _database.database;
    final result = await db.rawQuery(
        'SELECT lineId FROM line_toc WHERE tocEntryId = ? ORDER BY lineId',
        [tocEntryId]);
    return result.map((row) => row['lineId'] as int).toList();
  }

  /// Returns mappings (lineId -> tocEntryId) for a book ordered by line index.
  Future<List<LineTocMapping>> getLineTocMappingsForBook(int bookId) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT lt.lineId, lt.tocEntryId
      FROM line_toc lt
      JOIN line l ON lt.lineId = l.id
      WHERE l.bookId = ?
      ORDER BY l.lineIndex
    ''', [bookId]);
    return result
        .map((row) => LineTocMapping(
              lineId: row['lineId'] as int,
              tocEntryId: row['tocEntryId'] as int,
            ))
        .toList();
  }

  /// Builds all mappings for a given book by assigning to each line
  /// the latest TOC entry whose start line index is <= line's index.
  Future<void> rebuildLineTocForBook(int bookId) async {
    final db = await _database.database;
    // Clear existing mappings for the book
    await db.rawDelete(
        'DELETE FROM line_toc WHERE lineId IN (SELECT id FROM line WHERE bookId = ?)',
        [bookId]);

    // Insert computed mappings
    await db.execute('''
      INSERT INTO line_toc(lineId, tocEntryId)
      SELECT l.id AS lineId,
             (
                 SELECT t.id
                 FROM tocEntry t
                 JOIN line sl ON sl.id = t.lineId
                 WHERE t.bookId = l.bookId
                   AND t.lineId IS NOT NULL
                   AND sl.lineIndex <= l.lineIndex
                 ORDER BY sl.lineIndex DESC
                 LIMIT 1
             ) AS tocEntryId
      FROM line l
      WHERE l.bookId = ?
    ''', [bookId]);
  }

  // --- Transactions ---

  /// Runs a block of code in a transaction
  Future<T> runInTransaction<T>(Future<T> Function() block) async {
    final db = await _database.database;
    return await db.transaction((txn) async {
      // Temporarily replace the database connection with the transaction
      return await block();
    });
  }

  Future<void> setSynchronous(String mode) async {
    await executeRawQuery('PRAGMA synchronous=$mode');
  }

  Future<void> setSynchronousOff() => setSynchronous('OFF');
  Future<void> setSynchronousNormal() => setSynchronous('NORMAL');

  Future<void> setJournalMode(String mode) async {
    await executeRawQuery('PRAGMA journal_mode=$mode');
  }

  Future<void> setJournalModeOff() => setJournalMode('OFF');
  Future<void> setJournalModeWal() => setJournalMode('WAL');

  /// Sets maximum performance mode for bulk operations
  Future<void> setMaxPerformanceMode() async {
    _logger.info('Setting maximum performance mode for bulk operations');
    await executeRawQuery('PRAGMA synchronous=OFF');
    await executeRawQuery('PRAGMA journal_mode=MEMORY'); // Faster than OFF
    await executeRawQuery('PRAGMA locking_mode=EXCLUSIVE');
    await executeRawQuery('PRAGMA cache_size=200000'); // 200MB cache
    await executeRawQuery('PRAGMA temp_store=MEMORY');
    await executeRawQuery('PRAGMA mmap_size=536870912'); // 512MB memory-mapped
    _logger.info('Maximum performance mode enabled');
  }

  /// Restores normal performance mode after bulk operations
  Future<void> restoreNormalMode() async {
    _logger.info('Restoring normal performance mode');
    await executeRawQuery('PRAGMA synchronous=NORMAL');
    await executeRawQuery('PRAGMA journal_mode=WAL');
    await executeRawQuery('PRAGMA locking_mode=NORMAL');
    await executeRawQuery('PRAGMA cache_size=100000');
    _logger.info('Normal performance mode restored');
  }

  /// Rebuilds the category_closure table from the current category tree.
  Future<void> rebuildCategoryClosure() async {
    final db = await _database.database;
    // Clear existing closure data
    await db.rawDelete('DELETE FROM category_closure');

    // Load all categories
    final rows = await db.rawQuery('SELECT id, parentId FROM category');
    final parentMap = <int, int?>{};
    for (final row in rows) {
      parentMap[row['id'] as int] = row['parentId'] as int?;
    }

    // For each category, walk up to root and insert pairs
    for (final row in rows) {
      final descId = row['id'] as int;
      int? ancId = descId;

      // Self
      await db.rawInsert(
          'INSERT INTO category_closure (ancestorId, descendantId) VALUES (?, ?)',
          [descId, descId]);

      ancId = parentMap[descId];
      var guard = 0;
      const safety = 128;

      while (ancId != null && guard++ < safety) {
        await db.rawInsert(
            'INSERT INTO category_closure (ancestorId, descendantId) VALUES (?, ?)',
            [ancId, descId]);
        ancId = parentMap[ancId];
      }
    }
  }

  /// Returns all descendant category IDs (including the category itself) using the
  /// category_closure table.
  Future<List<int>> getDescendantCategoryIds(int ancestorId) async {
    final db = await _database.database;
    final result = await db.rawQuery(
        'SELECT descendantId FROM category_closure WHERE ancestorId = ?',
        [ancestorId]);
    return result.map((row) => row['descendantId'] as int).toList();
  }

  // --- Categories ---

  /// Retrieves all categories.
  ///
  /// @return A list of all categories
  Future<List<Category>> getAllCategories() async {
    return await _database.categoryDao.getAllCategories();
  }

  /// Retrieves a category by its ID.
  ///
  /// @param id The ID of the category to retrieve
  /// @return The category if found, null otherwise
  Future<Category?> getCategory(int id) async {
    return await _database.categoryDao.getCategoryById(id);
  }

  /// Retrieves all root categories (categories without a parent).
  ///
  /// @return A list of root categories
  Future<List<Category>> getRootCategories() async {
    return await _database.categoryDao.getRootCategories();
  }

  /// Retrieves all child categories of a parent category.
  ///
  /// @param parentId The ID of the parent category
  /// @return A list of child categories
  Future<List<Category>> getCategoryChildren(int parentId) async {
    return await _database.categoryDao.getCategoriesByParentId(parentId);
  }

  /// Inserts a category into the database.
  /// If a category with the same title already exists, returns its ID instead.
  ///
  /// @param category The category to insert
  /// @return The ID of the inserted or existing category
  /// @throws Exception If the insertion fails
  Future<int> insertCategory(Category category) async {
    try {
      // Check if a category with the same title AND SAME PARENT already exists
      final existingCategories =
          await _getCategoriesByParent(category.parentId);

      // Find a category with the same title in the same parent
      final existingCategory = existingCategories.firstWhere(
        (cat) => cat.title == category.title,
        orElse: () => Category(id: -1, title: '', parentId: null, level: 0),
      );

      if (existingCategory.id != -1) {
        return existingCategory.id;
      }

      // Try the insertion
      final insertedId = await _database.categoryDao
          .insertCategory(category.parentId, category.title, category.level);

      if (insertedId == 0) {
        // Check again if the category was inserted despite lastInsertRowId() returning 0
        final updatedCategories =
            await _getCategoriesByParent(category.parentId);

        final newCategory = updatedCategories.firstWhere(
          (cat) => cat.title == category.title,
          orElse: () => Category(id: -1, title: '', parentId: null, level: 0),
        );

        if (newCategory.id != -1) {
          return newCategory.id;
        }

        // If all else fails, throw an exception
        throw Exception(
            'Failed to insert category \'${category.title}\' with parent ${category.parentId}');
      }

      return insertedId;
    } catch (e) {
      // Changed from error to warning level to reduce unnecessary error logs
      _logger.warning(
          'Repository: Error inserting category \'${category.title}\': ${e.toString()}');

      // In case of error, check if the category exists anyway
      final categories = await _getCategoriesByParent(category.parentId);

      final existingCategory = categories.firstWhere(
        (cat) => cat.title == category.title,
        orElse: () => Category(id: -1, title: '', parentId: null, level: 0),
      );

      if (existingCategory.id != -1) {
        return existingCategory.id;
      }

      // Re-throw the exception if we can't recover
      rethrow;
    }
  }

  Future<List<Category>> _getCategoriesByParent(int? parentId) async {
    if (parentId != null) {
      return await _database.categoryDao.getCategoriesByParentId(parentId);
    } else {
      return await _database.categoryDao.getRootCategories();
    }
  }

  /// Gets a category by its title.
  Future<Category?> getCategoryByTitle(String title) async {
    return await _database.categoryDao.getCategoryByTitle(title);
  }

  /// Gets a category by its title and parent ID.
  Future<Category?> getCategoryByTitleAndParent(
      String title, int? parentId) async {
    return await _database.categoryDao
        .getCategoryByTitleAndParent(title, parentId);
  }

  // --- Books ---

  /// Retrieves a book by its ID, including all related data (authors, topics, etc.).
  ///
  /// @param id The ID of the book to retrieve
  /// @return The book if found, null otherwise
  Future<Book?> getBook(int id) async {
    final bookData = await _database.bookDao.getBookById(id);
    if (bookData == null) return null;

    final authors = await _getBookAuthors(id);
    final topics = await _getBookTopics(id);
    final pubPlaces = await _getBookPubPlaces(id);
    final pubDates = await _getBookPubDates(id);

    return bookData.copyWith(
      authors: authors,
      topics: topics,
      pubPlaces: pubPlaces,
      pubDates: pubDates,
    );
  }

  /// Retrieves all books in a specific category.
  ///
  /// @param categoryId The ID of the category
  /// @return A list of books in the category
  Future<List<Book>> getBooksByCategory(int categoryId) async {
    final books = await _database.bookDao.getBooksByCategory(categoryId);
    return Future.wait(books.map((bookData) async {
      final authors = await _getBookAuthors(bookData.id);
      final topics = await _getBookTopics(bookData.id);
      final pubPlaces = await _getBookPubPlaces(bookData.id);
      final pubDates = await _getBookPubDates(bookData.id);
      return bookData.copyWith(
        authors: authors,
        topics: topics,
        pubPlaces: pubPlaces,
        pubDates: pubDates,
      );
    }));
  }

  Future<List<Book>> searchBooksByAuthor(String authorName) async {
    final books = await _database.bookDao.getBooksByAuthor(authorName);
    return Future.wait(books.map((bookData) async {
      final authors = await _getBookAuthors(bookData.id);
      final topics = await _getBookTopics(bookData.id);
      final pubPlaces = await _getBookPubPlaces(bookData.id);
      final pubDates = await _getBookPubDates(bookData.id);
      return bookData.copyWith(
        authors: authors,
        topics: topics,
        pubPlaces: pubPlaces,
        pubDates: pubDates,
      );
    }));
  }

  // Get all authors for a book
  Future<List<Author>> _getBookAuthors(int bookId) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT a.* FROM author a
      JOIN book_author ba ON a.id = ba.authorId
      WHERE ba.bookId = ?
    ''', [bookId]);
    return result.map((row) => Author.fromJson(row)).toList();
  }

  // Get all topics for a book
  Future<List<Topic>> _getBookTopics(int bookId) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT t.* FROM topic t
      JOIN book_topic bt ON t.id = bt.topicId
      WHERE bt.bookId = ?
    ''', [bookId]);
    return result.map((row) => Topic.fromJson(row)).toList();
  }

  // Get all publication places for a book
  Future<List<PubPlace>> _getBookPubPlaces(int bookId) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT pp.* FROM pub_place pp
      JOIN book_pub_place bpp ON pp.id = bpp.pubPlaceId
      WHERE bpp.bookId = ?
    ''', [bookId]);
    return result.map((row) => PubPlace.fromJson(row)).toList();
  }

  // Get all publication dates for a book
  Future<List<PubDate>> _getBookPubDates(int bookId) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT pd.* FROM pub_date pd
      JOIN book_pub_date bpd ON pd.id = bpd.pubDateId
      WHERE bpd.bookId = ?
    ''', [bookId]);
    return result.map((row) => PubDate.fromJson(row)).toList();
  }

  // Get an author by name, returns null if not found
  Future<Author?> getAuthorByName(String name) async {
    return await _database.authorDao.getAuthorByName(name);
  }

  // Insert an author and return its ID
  Future<int> insertAuthor(String name) async {
    // Check if author already exists
    final existingId = await _database.authorDao.getAuthorIdByName(name);
    if (existingId != null) {
      return existingId;
    }

    // Insert the author
    await _database.authorDao.insertAuthor(name);

    // Get the ID by name (handles INSERT OR IGNORE case)
    final insertedId = await _database.authorDao.getAuthorIdByName(name);
    if (insertedId != null) {
      return insertedId;
    }

    // If all else fails, return a dummy ID that will be used for this session only
    _logger.warning(
        'Could not insert author \'$name\' after multiple attempts, using temporary ID');
    return 999999;
  }

  // Link an author to a book
  Future<void> linkAuthorToBook(int authorId, int bookId) async {
    await _database.authorDao.linkBookAuthor(bookId, authorId);
  }

  Future<Book?> getBookByTitle(String title) async {
    final bookData = await _database.bookDao.getBookByTitle(title);
    if (bookData == null) return null;

    final authors = await _getBookAuthors(bookData.id);
    final topics = await _getBookTopics(bookData.id);
    final pubPlaces = await _getBookPubPlaces(bookData.id);
    final pubDates = await _getBookPubDates(bookData.id);

    return bookData.copyWith(
      authors: authors,
      topics: topics,
      pubPlaces: pubPlaces,
      pubDates: pubDates,
    );
  }

  Future<Book?> getBookByTitleAndCategory(String title, int categoryId) async {
    final bookData = await _database.bookDao.getBookByTitleAndCategory(title, categoryId);
    if (bookData == null) return null;

    final authors = await _getBookAuthors(bookData.id);
    final topics = await _getBookTopics(bookData.id);
    final pubPlaces = await _getBookPubPlaces(bookData.id);
    final pubDates = await _getBookPubDates(bookData.id);

    return bookData.copyWith(
      authors: authors,
      topics: topics,
      pubPlaces: pubPlaces,
      pubDates: pubDates,
    );
  }

  Future<Book?> getBookByTitleCategoryAndFileType(String title, int categoryId, String fileType) async {
    final bookData = await _database.bookDao.getBookByTitleCategoryAndFileType(title, categoryId, fileType);
    if (bookData == null) return null;

    final authors = await _getBookAuthors(bookData.id);
    final topics = await _getBookTopics(bookData.id);
    final pubPlaces = await _getBookPubPlaces(bookData.id);
    final pubDates = await _getBookPubDates(bookData.id);

    return bookData.copyWith(
      authors: authors,
      topics: topics,
      pubPlaces: pubPlaces,
      pubDates: pubDates,
    );
  }

  // Get a topic by name, returns null if not found
  Future<Topic?> getTopicByName(String name) async {
    return await _database.topicDao.getTopicByName(name);
  }

  // Get a publication place by name, returns null if not found
  Future<PubPlace?> getPubPlaceByName(String name) async {
    return await _database.pubPlaceDao.getPubPlaceByName(name);
  }

  // Get a publication date by date, returns null if not found
  Future<PubDate?> getPubDateByDate(String date) async {
    return await _database.pubDateDao.getPubDateByDate(date);
  }

  // Insert a topic and return its ID
  Future<int> insertTopic(String name) async {
    // Check if topic already exists
    final existingId = await _database.topicDao.getTopicIdByName(name);
    if (existingId != null) {
      return existingId;
    }

    // Insert the topic
    await _database.topicDao.insertTopic(name);

    // Get the ID by name (handles INSERT OR IGNORE case)
    final insertedId = await _database.topicDao.getTopicIdByName(name);
    if (insertedId != null) {
      return insertedId;
    }

    // If all else fails, return a dummy ID that will be used for this session only
    _logger.warning(
        'Could not insert topic \'$name\' after multiple attempts, using temporary ID');
    return 999999;
  }

  // Link a topic to a book
  Future<void> linkTopicToBook(int topicId, int bookId) async {
    await _database.topicDao.linkBookTopic(bookId, topicId);
  }

  // Insert a publication place and return its ID
  Future<int> insertPubPlace(String name) async {
    // Check if publication place already exists
    final existingPubPlace = await getPubPlaceByName(name);
    if (existingPubPlace != null) {
      return existingPubPlace.id;
    }

    // Insert the publication place
    await _database.pubPlaceDao.insertPubPlace(name);

    // Get the ID by name (handles INSERT OR IGNORE case)
    final insertedPubPlace = await getPubPlaceByName(name);
    if (insertedPubPlace != null) {
      return insertedPubPlace.id;
    }

    // If all else fails, return a dummy ID that will be used for this session only
    _logger.warning(
        'Could not insert publication place \'$name\' after multiple attempts, using temporary ID');
    return 999999;
  }

  // Insert a publication date and return its ID
  Future<int> insertPubDate(String date) async {
    // Check if publication date already exists
    final existingPubDate = await getPubDateByDate(date);
    if (existingPubDate != null) {
      return existingPubDate.id;
    }

    // Insert the publication date
    await _database.pubDateDao.insertPubDate(date);

    // Get the ID by date (handles INSERT OR IGNORE case)
    final insertedPubDate = await getPubDateByDate(date);
    if (insertedPubDate != null) {
      return insertedPubDate.id;
    }

    // If all else fails, return a dummy ID that will be used for this session only
    _logger.warning(
        'Could not insert publication date \'$date\' after multiple attempts, using temporary ID');
    return 999999;
  }

  // Link a publication place to a book
  Future<void> linkPubPlaceToBook(int pubPlaceId, int bookId) async {
    await _database.pubPlaceDao.linkBookPubPlace(bookId, pubPlaceId);
  }

  // Link a publication date to a book
  Future<void> linkPubDateToBook(int pubDateId, int bookId) async {
    await _database.pubDateDao.linkBookPubDate(bookId, pubDateId);
  }

  /// Inserts a book into the database, including all related data (authors, topics, etc.).
  /// If the book has an ID greater than 0, uses that ID; otherwise, generates a new ID.
  ///
  /// @param book The book to insert
  /// @return The ID of the inserted book
  Future<int> insertBook(Book book) async {
    // Use the ID from the book object if it's greater than 0
    if (book.id > 0) {
      await _database.bookDao.insertBookWithId(
          book.id,
          book.categoryId,
          book.sourceId,
          book.title,
          book.heShortDesc,
          book.order,
          book.totalLines,
          book.isBaseBook,
          book.notesContent,
          book.filePath,
          book.fileType);

      // Process authors
      for (final author in book.authors) {
        final authorId = await insertAuthor(author.name);
        await linkAuthorToBook(authorId, book.id);
      }

      // Process topics
      for (final topic in book.topics) {
        final topicId = await insertTopic(topic.name);
        await linkTopicToBook(topicId, book.id);
      }

      // Process publication places
      for (final pubPlace in book.pubPlaces) {
        final pubPlaceId = await insertPubPlace(pubPlace.name);
        await linkPubPlaceToBook(pubPlaceId, book.id);
      }

      // Process publication dates
      for (final pubDate in book.pubDates) {
        final pubDateId = await insertPubDate(pubDate.date);
        await linkPubDateToBook(pubDateId, book.id);
      }

      return book.id;
    } else {
      // Fall back to auto-generated ID if book.id is 0
      final id = await _database.bookDao.insertBook(
          book.categoryId,
          book.sourceId,
          book.title,
          book.heShortDesc,
          book.order,
          book.totalLines,
          book.isBaseBook,
          book.notesContent,
          book.filePath,
          book.fileType);

      // Check if insertion failed
      if (id == 0) {
        // Try to find the book by title
        final existingBook = await _database.bookDao.getBookByTitle(book.title);
        if (existingBook != null) {
          return existingBook.id;
        }

        throw Exception(
            'Failed to insert book \'${book.title}\' - insertion returned ID 0. Context: categoryId=${book.categoryId}, authors=${book.authors.map((a) => a.name)}, topics=${book.topics.map((t) => t.name)}, pubPlaces=${book.pubPlaces.map((p) => p.name)}, pubDates=${book.pubDates.map((d) => d.date)}');
      }

      // Process authors
      for (final author in book.authors) {
        final authorId = await insertAuthor(author.name);
        await linkAuthorToBook(authorId, id);
      }

      // Process topics
      for (final topic in book.topics) {
        final topicId = await insertTopic(topic.name);
        await linkTopicToBook(topicId, id);
      }

      // Process publication places
      for (final pubPlace in book.pubPlaces) {
        final pubPlaceId = await insertPubPlace(pubPlace.name);
        await linkPubPlaceToBook(pubPlaceId, id);
      }

      // Process publication dates
      for (final pubDate in book.pubDates) {
        final pubDateId = await insertPubDate(pubDate.date);
        await linkPubDateToBook(pubDateId, id);
      }

      return id;
    }
  }

  // --- Sources ---

  /// Returns a Source by name, or null if not found.
  Future<Source?> getSourceByName(String name) async {
    final db = await _database.database;
    final result =
        await db.rawQuery('SELECT * FROM source WHERE name = ?', [name]);
    if (result.isEmpty) return null;
    return Source.fromJson(result.first);
  }

  /// Inserts a source if missing and returns its id.
  Future<int> insertSource(String name) async {
    // Check existing
    final existing = await getSourceByName(name);
    if (existing != null) return existing.id;

    final db = await _database.database;
    final id =
        await db.rawInsert('INSERT INTO source (name) VALUES (?)', [name]);
    if (id == 0) {
      // Try to read back just in case
      final again = await getSourceByName(name);
      if (again != null) return again.id;
      throw Exception('Failed to insert source \'$name\'');
    }
    return id;
  }

  Future<void> updateBookTotalLines(int bookId, int totalLines) async {
    await _database.bookDao.updateBookTotalLines(bookId, totalLines);
  }

  Future<void> updateBookCategoryId(int bookId, int categoryId) async {
    await _database.bookDao.updateBookCategoryId(bookId, categoryId);
  }

  // --- External Books ---

  /// Inserts an external book (file-based book with metadata only in DB).
  /// External books have isExternal=1 and store file path, type, size, and last modified.
  /// Also creates TOC entries for the book if it's a text file.
  ///
  /// @param categoryId The category ID for the book
  /// @param title The book title
  /// @param filePath The full path to the file
  /// @param fileType The file type (pdf, txt, docx, etc.)
  /// @param fileSize The file size in bytes
  /// @param lastModified The last modified timestamp (milliseconds since epoch)
  /// @param heShortDesc Optional short description
  /// @param orderIndex Optional order index (defaults to 999)
  /// @param tocEntries Optional list of TOC entries to create
  /// @return The ID of the inserted book
  Future<int> insertExternalBook({
    required int categoryId,
    required String title,
    required String filePath,
    required String fileType,
    required int fileSize,
    required int lastModified,
    String? heShortDesc,
    double orderIndex = 999,
    List<TocEntry>? tocEntries,
  }) async {

    // Get or create a source for external books
    final sourceId = await insertSource('external');

    final bookId = await _database.bookDao.insertExternalBook(
      categoryId: categoryId,
      sourceId: sourceId,
      title: title,
      heShortDesc: heShortDesc,
      orderIndex: orderIndex,
      filePath: filePath,
      fileType: fileType,
      fileSize: fileSize,
      lastModified: lastModified,
    );

    // Insert TOC entries if provided
    if (tocEntries != null && tocEntries.isNotEmpty) {
      await _insertTocEntriesForExternalBook(bookId, tocEntries);
    }

    return bookId;
  }

  /// Updates an external book's metadata (file size and last modified).
  Future<void> updateExternalBookMetadata(
      int bookId, int fileSize, int lastModified) async {
    _logger.fine('Updating external book metadata: bookId=$bookId');
    await _database.bookDao
        .updateExternalMetadata(bookId, fileSize, lastModified);
  }

  /// Gets an external book by its file path.
  Future<Book?> getExternalBookByFilePath(String filePath) async {
    return await _database.bookDao.getBookByFilePath(filePath);
  }

  /// Gets all external books.
  Future<List<Book>> getAllExternalBooks() async {
    return await _database.bookDao.getExternalBooks();
  }

  /// Inserts TOC entries for an external book.
  /// Creates toc_text entries and toc_entry entries.
  Future<void> _insertTocEntriesForExternalBook(
      int bookId, List<TocEntry> entries) async {
    _logger.fine(
        'Inserting ${entries.length} TOC entries for external book $bookId');

    for (final entry in entries) {
      // Create toc_text entry
      final textId = await _getOrCreateTocText(entry.text);

      // Create toc_entry with the book ID
      final tocEntry = TocEntry(
        id: 0,
        bookId: bookId,
        parentId: entry.parentId,
        textId: textId,
        level: entry.level,
        lineId: entry.lineId,
        isLastChild: entry.isLastChild,
        hasChildren: entry.hasChildren,
      );

      await _database.tocDao.insertTocEntry(tocEntry);
    }

    _logger.fine('Inserted TOC entries for external book $bookId');
  }

  // --- Lines ---

  Future<Line?> getLine(int id) async {
    return await _database.lineDao.getLineById(id);
  }

  Future<Line?> getLineByIndex(int bookId, int lineIndex) async {
    return await _database.lineDao.selectByBookIdAndIndex(bookId, lineIndex);
  }

  Future<List<Line>> getLines(int bookId, int startIndex, int endIndex) async {
    return await _database.lineDao
        .selectByBookIdRange(bookId, startIndex, endIndex);
  }

  /// Gets only IDs and indices for all lines in a book.
  /// Optimized for link processing to avoid loading content.
  Future<List<Map<String, dynamic>>> getLineIdsAndIndices(int bookId) async {
    final db = await _database.database;
    return await db.rawQuery(
      'SELECT id, lineIndex FROM line WHERE bookId = ?',
      [bookId],
    );
  }

  /// Gets the previous line for a given book and line index.
  ///
  /// @param bookId The ID of the book
  /// @param currentLineIndex The index of the current line
  /// @return The previous line, or null if there is no previous line
  Future<Line?> getPreviousLine(int bookId, int currentLineIndex) async {
    if (currentLineIndex <= 0) return null;

    final previousIndex = currentLineIndex - 1;
    return await getLineByIndex(bookId, previousIndex);
  }

  /// Gets the next line for a given book and line index.
  ///
  /// @param bookId The ID of the book
  /// @param currentLineIndex The index of the current line
  /// @return The next line, or null if there is no next line
  Future<Line?> getNextLine(int bookId, int currentLineIndex) async {
    final nextIndex = currentLineIndex + 1;
    return await getLineByIndex(bookId, nextIndex);
  }

  Future<int> insertLine(Line line) async {
    _logger.fine('Repository inserting line with bookId: ${line.bookId}');

    // Use the ID from the line object if it's greater than 0
    if (line.id > 0) {
      await _database.lineDao.insertWithId(line);
      return line.id;
    } else {
      // Fall back to auto-generated ID if line.id is 0
      final lineId = await _database.lineDao.insertLine(line);

      // Check if insertion failed
      if (lineId == 0) {
        // Try to find the line by bookId and lineIndex
        final existingLine = await getLineByIndex(line.bookId, line.lineIndex);
        if (existingLine != null) {
          return existingLine.id;
        }

        throw Exception(
            'Failed to insert line for book ${line.bookId} at index ${line.lineIndex} - insertion returned ID 0. Context: content=\'${line.content.substring(0, line.content.length < 50 ? line.content.length : 50)}${line.content.length > 50 ? "..." : ""}\'');
      }

      return lineId;
    }
  }

  /// Inserts multiple lines in a single batch operation for better performance
  Future<void> insertLinesBatch(List<Line> lines) async {
    if (lines.isEmpty) return;

    final db = await _database.database;
    final batch = db.batch();

    for (final line in lines) {
      if (line.id > 0) {
        batch.rawInsert(
            'INSERT OR IGNORE INTO line (id, bookId, lineIndex, content) VALUES (?, ?, ?, ?)',
            [line.id, line.bookId, line.lineIndex, line.content]);
      } else {
        batch.rawInsert(
            'INSERT INTO line (bookId, lineIndex, content) VALUES (?, ?, ?)',
            [line.bookId, line.lineIndex, line.content]);
      }
    }

    await batch.commit(noResult: true);
  }

  Future<void> updateLineTocEntry(int lineId, int tocEntryId) async {
    await _database.lineDao.updateTocEntryId(lineId, tocEntryId);
  }

  // --- Table of Contents ---
  Future<List<TocEntry>> getBookTocs(int bookId) async {
    return _database.tocDao.selectByBookId(bookId);
  }

  Future<TocEntry?> getTocEntry(int id) async {
    return await _database.tocDao.selectTocById(id);
  }

  Future<List<TocEntry>> getBookToc(int bookId) async {
    return await _database.tocDao.selectByBookId(bookId);
  }

  Future<List<TocEntry>> getBookRootToc(int bookId) async {
    return await _database.tocDao.selectRootByBookId(bookId);
  }

  Future<List<TocEntry>> getTocChildren(int parentId) async {
    return await _database.tocDao.selectChildren(parentId);
  }

  // --- TocText methods ---

  // Returns all distinct tocText values using generated SQLDelight query
  Future<List<String>> getAllTocTexts() async {
    final tocTexts = await _database.tocTextDao.selectAll();
    return tocTexts.map((t) => t.text).toList();
  }

  // Get or create a tocText entry and return its ID
  Future<int> _getOrCreateTocText(String text) async {
    // Truncate text for logging if it's too long
    final truncatedText =
        text.length > 50 ? '${text.substring(0, 50)}...' : text;

    try {
      // Check if the text already exists
      final existingId = await _database.tocTextDao.selectIdByText(text);
      if (existingId > 0) {
        return existingId;
      }

      // Insert the text
      final tocText = TocText(id: 0, text: text);
      await _database.tocTextDao.insert(tocText);

      // Get the ID of the inserted text
      final insertedId = await _database.tocTextDao.selectIdByText(text);
      if (insertedId > 0) {
        return insertedId;
      }

      // If we can't find the text by exact match, this is unexpected
      final totalTocTexts = await _database.tocTextDao.countAll();
      _logger.warning(
          'Failed to insert tocText and couldn\'t find it after insertion. Text: \'$truncatedText\', Length: ${text.length}, Total TocTexts: $totalTocTexts');

      throw Exception(
          'Failed to insert tocText \'$truncatedText\' - couldn\'t find text afterward. Context: textLength=${text.length}, totalTocTexts=$totalTocTexts');
    } catch (e) {
      _logger.warning(
          'Exception in getOrCreateTocText for text: \'$truncatedText\', Length: ${text.length}}. Error: ${e.toString()}');
      rethrow;
    }
  }

  Future<int> insertTocEntry(TocEntry entry) async {
    // Get or create the tocText entry
    final textId = entry.textId ?? await _getOrCreateTocText(entry.text);

    final entryWithTextId = TocEntry(
      id: entry.id,
      bookId: entry.bookId,
      parentId: entry.parentId,
      textId: textId,
      text: entry.text,
      level: entry.level,
      lineId: entry.lineId,
      lineIndex: entry.lineIndex,
      isLastChild: entry.isLastChild,
      hasChildren: entry.hasChildren,
    );

    // Use the ID from the entry object if it's greater than 0
    if (entry.id > 0) {
      await _database.tocDao.insertWithId(entryWithTextId);
      return entry.id;
    } else {
      // Fall back to auto-generated ID if entry.id is 0
      final tocId = await _database.tocDao.insertTocEntry(entryWithTextId);

      // Check if insertion failed
      if (tocId == 0) {
        // Try to find a matching TOC entry by bookId and text
        final existingEntries =
            await _database.tocDao.selectByBookId(entry.bookId);
        final matchingEntry = existingEntries.firstWhere(
          (e) => e.text == entry.text && e.level == entry.level,
          orElse: () => TocEntry(
              id: 0,
              bookId: 0,
              parentId: null,
              textId: 0,
              text: '',
              level: 0,
              lineId: null,
              lineIndex: null,
              isLastChild: false,
              hasChildren: false),
        );

        if (matchingEntry.id > 0) {
          return matchingEntry.id;
        }

        throw Exception(
            'Failed to insert TOC entry for book ${entry.bookId} with text \'${entry.text.substring(0, entry.text.length < 30 ? entry.text.length : 30)}${entry.text.length > 30 ? "..." : ""}\' - insertion returned ID 0. Context: parentId=${entry.parentId}, level=${entry.level}, lineId=${entry.lineId}');
      }

      return tocId;
    }
  }

  /// Inserts multiple TOC entries in a single batch operation for better performance
  Future<void> insertTocEntriesBatch(List<TocEntry> entries) async {
    if (entries.isEmpty) return;


    // Pre-create all tocText entries
    final textIds = <String, int>{};
    for (final entry in entries) {
      if (!textIds.containsKey(entry.text)) {
        textIds[entry.text] = await _getOrCreateTocText(entry.text);
      }
    }

    // Create entries with textIds
    final entriesWithTextIds = entries
        .map((entry) {
          final textId = textIds[entry.text];
          if (textId == null) {
            _logger.warning(
                'Text ID not found for TOC entry text: ${entry.text}, skipping entry');
            return null;
          }
          return TocEntry(
            id: entry.id,
            bookId: entry.bookId,
            parentId: entry.parentId,
            textId: textId,
            text: entry.text,
            level: entry.level,
            lineId: entry.lineId,
            lineIndex: entry.lineIndex,
            isLastChild: entry.isLastChild,
            hasChildren: entry.hasChildren,
          );
        })
        .whereType<TocEntry>()
        .toList();

    // Batch insert using raw SQL
    final db = await _database.database;
    final batch = db.batch();

    for (final entry in entriesWithTextIds) {
      if (entry.id > 0) {
        batch.rawInsert('''
          INSERT OR IGNORE INTO tocEntry (id, bookId, parentId, textId, level, lineId, isLastChild, hasChildren)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', [
          entry.id,
          entry.bookId,
          entry.parentId,
          entry.textId,
          entry.level,
          entry.lineId,
          entry.isLastChild ? 1 : 0,
          entry.hasChildren ? 1 : 0,
        ]);
      } else {
        batch.rawInsert('''
          INSERT INTO tocEntry (bookId, parentId, textId, level, lineId, isLastChild, hasChildren)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', [
          entry.bookId,
          entry.parentId,
          entry.textId,
          entry.level,
          entry.lineId,
          entry.isLastChild ? 1 : 0,
          entry.hasChildren ? 1 : 0,
        ]);
      }
    }

    await batch.commit(noResult: true);
  }

  // Nouvelle méthode pour mettre à jour hasChildren
  Future<void> updateTocEntryHasChildren(
      int tocEntryId, bool hasChildren) async {
    await _database.tocDao.updateHasChildren(tocEntryId, hasChildren);
  }

  Future<void> updateTocEntryLineId(int tocEntryId, int lineId) async {
    await _database.tocDao.updateLineId(tocEntryId, lineId);
  }

  Future<void> updateTocEntryIsLastChild(
      int tocEntryId, bool isLastChild) async {
    await _database.tocDao.updateIsLastChild(tocEntryId, isLastChild);
  }

  /// Bulk update TOC entry lineIds
  Future<void> bulkUpdateTocEntryLineIds(
      List<({int tocId, int lineId})> updates) async {
    if (updates.isEmpty) return;
    final db = await _database.database;
    final batch = db.batch();
    for (final update in updates) {
      batch.rawUpdate('UPDATE tocEntry SET lineId = ? WHERE id = ?',
          [update.lineId, update.tocId]);
    }
    await batch.commit(noResult: true);
  }

  /// Bulk update TOC entries hasChildren flag
  Future<void> bulkUpdateTocEntryHasChildren(
      List<int> tocEntryIds, bool hasChildren) async {
    if (tocEntryIds.isEmpty) return;
    final db = await _database.database;
    final placeholders = List.filled(tocEntryIds.length, '?').join(',');
    await db.rawUpdate(
        'UPDATE tocEntry SET hasChildren = ? WHERE id IN ($placeholders)',
        [hasChildren ? 1 : 0, ...tocEntryIds]);
  }

  /// Bulk update TOC entries isLastChild flag
  Future<void> bulkUpdateTocEntryIsLastChild(
      List<int> tocEntryIds, bool isLastChild) async {
    if (tocEntryIds.isEmpty) return;
    final db = await _database.database;
    final placeholders = List.filled(tocEntryIds.length, '?').join(',');
    await db.rawUpdate(
        'UPDATE tocEntry SET isLastChild = ? WHERE id IN ($placeholders)',
        [isLastChild ? 1 : 0, ...tocEntryIds]);
  }

  // --- Connection Types ---

  // Cache for connection types
  final Map<String, int> _connectionTypeCache = {};

  /// Pre-loads all connection types into memory.
  /// Should be called before processing links.
  Future<void> initializeConnectionTypes() async {
    if (_connectionTypeCache.isNotEmpty) return;

    final types = ['commentary', 'targum', 'reference', 'other'];
    
    for (final type in types) {
      // Force creation/retrieval and cache it
      _connectionTypeCache[type] = await _fetchOrCreateConnectionType(type);
    }
    _logger.info('Initialized connection types cache: $_connectionTypeCache');
  }

  /// Internal method to fetch or create connection type without cache check
  Future<int> _fetchOrCreateConnectionType(String name) async {
    final db = await _database.database;
    final existingResult = await db
        .rawQuery('SELECT id FROM connection_type WHERE name = ?', [name]);
    if (existingResult.isNotEmpty) {
      return existingResult.first['id'] as int;
    }

    final typeId = await db
        .rawInsert('INSERT INTO connection_type (name) VALUES (?)', [name]);

    if (typeId == 0) {
      final insertedResult = await db
          .rawQuery('SELECT id FROM connection_type WHERE name = ?', [name]);
      if (insertedResult.isNotEmpty) {
        return insertedResult.first['id'] as int;
      }
      throw Exception('Failed to insert connection type $name');
    }
    return typeId;
  }

  /// Gets a connection type by name, or creates it if it doesn't exist.
  /// Uses in-memory cache for performance.
  ///
  /// @param name The name of the connection type
  /// @return The ID of the connection type
  Future<int> getOrCreateConnectionType(String name) async {
    // Check cache first
    if (_connectionTypeCache.containsKey(name)) {
      return _connectionTypeCache[name]!;
    }
    
    // If not in cache, fetch/create and cache it
    final id = await _fetchOrCreateConnectionType(name);
    _connectionTypeCache[name] = id;
    return id;
  }

  /// Gets all connection types from the database.
  ///
  /// @return A list of all connection types
  Future<List<String>> getAllConnectionTypes() async {
    final db = await _database.database;
    final result =
        await db.rawQuery('SELECT name FROM connection_type ORDER BY name');
    return result.map((row) => row['name'] as String).toList();
  }

  /// שליפת כל סוגי ההקשרים מטבלת connection_type
  Future<List<ConnectionTypeEntry>> getAllConnectionTypesObj() async {
    return await _database.connectionTypeDao.getAllConnectionTypes();
  }

  // --- Links ---

  Future<Link?> getLink(int id) async {
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM link WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return Link.fromJson(result.first);
  }

  Future<int> countLinks() async {
    final db = await _database.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM link');
    return result.first.values.first as int;
  }

  Future<List<CommentaryWithText>> getCommentariesForLines(
      List<int> lineIds, Set<int> activeCommentatorIds) async {
    final db = await _database.database;
    final placeholders = List.filled(lineIds.length, '?').join(',');
    final result = await db.rawQuery('''
      SELECT l.*, b.title as targetBookTitle, ln.plainText as targetText
      FROM link l
      JOIN book b ON l.targetBookId = b.id
      JOIN line ln ON l.targetLineId = ln.id
      WHERE l.sourceLineId IN ($placeholders)
      ${activeCommentatorIds.isNotEmpty ? 'AND l.targetBookId IN (${List.filled(activeCommentatorIds.length, '?').join(',')})' : ''}
      ORDER BY l.targetBookId, l.targetLineId
    ''', [...lineIds, ...activeCommentatorIds]);

    return result.map((row) {
      final link = Link(
        id: row['id'] as int,
        sourceBookId: row['sourceBookId'] as int,
        targetBookId: row['targetBookId'] as int,
        sourceLineId: row['sourceLineId'] as int,
        targetLineId: row['targetLineId'] as int,
        connectionType: ConnectionType.fromString(row['connectionTypeId']
            .toString()), // This needs to be mapped properly
      );
      return CommentaryWithText(
        link: link,
        targetBookTitle: row['targetBookTitle'] as String,
        targetText: row['targetText'] as String,
      );
    }).toList();
  }

  Future<List<CommentatorInfo>> getAvailableCommentators(int bookId) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT b.id as targetBookId, b.title as targetBookTitle, a.name as author, COUNT(l.id) as linkCount
      FROM link l
      JOIN book b ON l.targetBookId = b.id
      LEFT JOIN book_author ba ON b.id = ba.bookId
      LEFT JOIN author a ON ba.authorId = a.id
      WHERE l.sourceBookId = ?
      GROUP BY b.id, b.title, a.name
      ORDER BY b.title
    ''', [bookId]);

    return result
        .map((row) => CommentatorInfo(
              bookId: row['targetBookId'] as int,
              title: row['targetBookTitle'] as String,
              author: row['author'] as String?,
              linkCount: row['linkCount'] as int,
            ))
        .toList();
  }

  // New paginated methods for per-commentator pagination use cases
  Future<List<CommentaryWithText>> getCommentariesForLineRange(
    List<int> lineIds,
    Set<int> activeCommentatorIds,
    int offset,
    int limit,
  ) async {
    final commentaries =
        await getCommentariesForLines(lineIds, activeCommentatorIds);
    return commentaries.skip(offset).take(limit).toList();
  }

  Future<List<CommentatorInfo>> getAvailableCommentatorsPaginated(
    int bookId,
    int offset,
    int limit,
  ) async {
    final commentators = await getAvailableCommentators(bookId);
    return commentators.skip(offset).take(limit).toList();
  }

  Future<int> insertLink(Link link) async {
    try {
      // Get or create the connection type
      final connectionTypeId = await getOrCreateConnectionType(link.connectionType.name);
      final linkId = await _database.linkDao.insertLink(link, connectionTypeId);
      // Check if insertion failed
      if (linkId == 0) {
        // Try to find a matching link
        final existingResult = await _database.linkDao.selectLinkByDetails( link.sourceBookId,
          link.targetBookId,
          link.sourceLineId,
          link.targetLineId);

        if (existingResult != null) {
          return existingResult.id;
        }
        throw Exception(
            'Failed to insert link from book ${link.sourceBookId} to book ${link.targetBookId} - insertion returned ID 0. Context: sourceLineId=${link.sourceLineId}, targetLineId=${link.targetLineId}, connectionType=${link.connectionType.name}');
      }

      return linkId;
    } catch (e) {
      // Changed from error to warning level to reduce unnecessary error logs
      _logger.warning('Error inserting link: ${e.toString()}');
      rethrow;
    }
  }

  /// Inserts multiple links in a single batch operation for better performance
  /// Uses raw SQL with multiple VALUES for maximum performance
  Future<void> insertLinksBatch(List<Link> links) async {
    if (links.isEmpty) return;

    // Ensure cache is populated (safety check)
    if (_connectionTypeCache.isEmpty) {
      await initializeConnectionTypes();
    }

    final db = await _database.database;
    
    // Build VALUES string with all links in a single SQL statement
    final values = links.map((link) {
      // Use cache directly - extremely fast
      int? connectionTypeId = _connectionTypeCache[link.connectionType.name];
      
      // Fallback only if not found in cache (rare case for non-standard types)
      connectionTypeId ??= _connectionTypeCache['default'] ?? 1;

      return '(${link.sourceBookId}, ${link.targetBookId}, ${link.sourceLineId}, ${link.targetLineId}, $connectionTypeId)';
    }).join(',');

    await db.execute('''
      INSERT OR IGNORE INTO link (sourceBookId, targetBookId, sourceLineId, targetLineId, connectionTypeId)
      VALUES $values
    ''');
  }

  /// Migrates existing links to use the new connection_type table.
  /// This should be called once after updating the database schema.
  Future<void> migrateConnectionTypes() async {
    try {
      // Make sure all connection types exist in the connection_type table
      for (final type in ConnectionType.values) {
        await getOrCreateConnectionType(type.name);
      }

      // Get all links from the database
      final db = await _database.database;
      final linksResult = await db.rawQuery('SELECT * FROM link');

      // For each link, update the connectionTypeId
      var migratedCount = 0;
      for (final linkRow in linksResult) {
        final linkId = linkRow['id'] as int;
        final connectionTypeName = linkRow['connectionType']
            as String; // This assumes the old column exists
        final connectionTypeId =
            await getOrCreateConnectionType(connectionTypeName);

        // Execute a raw SQL query to update the link
        final updateSql =
            'UPDATE link SET connectionTypeId = $connectionTypeId WHERE id = $linkId';
        await db.execute(updateSql);

        migratedCount++;
      }

      _logger.info('Successfully migrated $migratedCount links');
    } catch (e) {
      _logger
          .severe('Error during connection types migration: ${e.toString()}');
      rethrow;
    }
  }

  // --- Search ---

  /// Searches for text across all books.
  ///
  /// @param query The search query
  /// @param limit Maximum number of results to return
  /// @param offset Number of results to skip (for pagination)
  /// @return A list of search results
  Future<List<SearchResult>> search(String query, int limit, int offset) async {
    final ftsQuery = _prepareFtsQuery(query);
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT l.id, l.bookId, l.lineIndex, b.title as bookTitle, l.plainText,
             snippet(line_search, 4, '<b>', '</b>', '...', 50) as snippet
      FROM line_search
      JOIN line l ON line_search.id = l.id
      JOIN book b ON line_search.bookId = b.id
      WHERE line_search.plainText MATCH ?
      ORDER BY rank
      LIMIT ? OFFSET ?
    ''', [ftsQuery, limit, offset]);

    return result
        .map((row) => SearchResult(
              bookId: row['bookId'] as int,
              bookTitle: row['bookTitle'] as String,
              lineId: row['id'] as int,
              lineIndex: row['lineIndex'] as int,
              snippet: row['snippet'] as String? ?? '',
              rank: 1.0, // Default rank since FTS doesn't provide it directly
            ))
        .toList();
  }

  /// Searches for text within a specific book.
  ///
  /// @param bookId The ID of the book to search in
  /// @param query The search query
  /// @param limit Maximum number of results to return
  /// @param offset Number of results to skip (for pagination)
  /// @return A list of search results
  Future<List<SearchResult>> searchInBook(
      int bookId, String query, int limit, int offset) async {
    final ftsQuery = _prepareFtsQuery(query);
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT l.id, l.bookId, l.lineIndex, b.title as bookTitle, l.plainText,
             snippet(line_search, 4, '<b>', '</b>', '...', 50) as snippet
      FROM line_search
      JOIN line l ON line_search.id = l.id
      JOIN book b ON line_search.bookId = b.id
      WHERE line_search.bookId = ? AND line_search.plainText MATCH ?
      ORDER BY rank
      LIMIT ? OFFSET ?
    ''', [bookId, ftsQuery, limit, offset]);

    return result
        .map((row) => SearchResult(
              bookId: row['bookId'] as int,
              bookTitle: row['bookTitle'] as String,
              lineId: row['id'] as int,
              lineIndex: row['lineIndex'] as int,
              snippet: row['snippet'] as String? ?? '',
              rank: 1.0, // Default rank since FTS doesn't provide it directly
            ))
        .toList();
  }

  /// Searches for text in books by a specific author.
  ///
  /// @param author The author name to filter by
  /// @param query The search query
  /// @param limit Maximum number of results to return
  /// @param offset Number of results to skip (for pagination)
  /// @return A list of search results
  Future<List<SearchResult>> searchByAuthor(
      String author, String query, int limit, int offset) async {
    final ftsQuery = _prepareFtsQuery(query);
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT l.id, l.bookId, l.lineIndex, b.title as bookTitle, l.plainText,
             snippet(line_search, 4, '<b>', '</b>', '...', 50) as snippet
      FROM line_search
      JOIN line l ON line_search.id = l.id
      JOIN book b ON line_search.bookId = b.id
      JOIN book_author ba ON b.id = ba.bookId
      JOIN author a ON ba.authorId = a.id
      WHERE a.name LIKE ? AND line_search.plainText MATCH ?
      ORDER BY rank
      LIMIT ? OFFSET ?
    ''', ['%$author%', ftsQuery, limit, offset]);

    return result
        .map((row) => SearchResult(
              bookId: row['bookId'] as int,
              bookTitle: row['bookTitle'] as String,
              lineId: row['id'] as int,
              lineIndex: row['lineIndex'] as int,
              snippet: row['snippet'] as String? ?? '',
              rank: 1.0, // Default rank since FTS doesn't provide it directly
            ))
        .toList();
  }

  // --- Helpers ---

  /// Prepares a search query for full-text search.
  /// Adds wildcards and quotes to improve search results.
  ///
  /// @param query The raw search query
  /// @return The formatted query for FTS
  String _prepareFtsQuery(String query) {
    return query
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) => '"$word"*')
        .join(' ');
  }

  /// Executes a raw SQL query.
  /// This is useful for operations that are not covered by the generated queries,
  /// such as enabling or disabling foreign key constraints.
  ///
  /// @param sql The SQL query to execute
  Future<void> executeRawQuery(String sql) async {
    final db = await _database.database;
    await db.execute(sql);
  }

  /// Begins a database transaction for better performance on bulk operations.
  Future<void> beginTransaction() async {
    final db = await _database.database;
    await db.execute('BEGIN TRANSACTION');
  }

  /// Commits the current database transaction.
  Future<void> commitTransaction() async {
    final db = await _database.database;
    await db.execute('COMMIT');
  }

  /// Rolls back the current database transaction.
  Future<void> rollbackTransaction() async {
    final db = await _database.database;
    await db.execute('ROLLBACK');
  }

  // FTS5 removed - rebuildFts5Index function no longer needed
  // Future<void> rebuildFts5Index() async {
  //   _logger.fine('Rebuilding FTS5 index for line_search table');
  //   await executeRawQuery('INSERT INTO line_search(line_search) VALUES(\'rebuild\')');
  //   _logger.fine('FTS5 index rebuilt successfully');
  // }

  /// Updates the book_has_links table to indicate whether a book has source links, target links, or both.
  ///
  /// @param bookId The ID of the book to update
  /// @param hasSourceLinks Whether the book has source links (true) or not (false)
  /// @param hasTargetLinks Whether the book has target links (true) or not (false)
  Future<void> updateBookHasLinks(
      int bookId, bool hasSourceLinks, bool hasTargetLinks) async {
    final db = await _database.database;
    await db.rawInsert('''
      INSERT OR REPLACE INTO book_has_links (bookId, hasSourceLinks, hasTargetLinks)
      VALUES (?, ?, ?)
    ''', [bookId, hasSourceLinks ? 1 : 0, hasTargetLinks ? 1 : 0]);
  }

  /// Updates only the source links status for a book.
  ///
  /// @param bookId The ID of the book to update
  /// @param hasSourceLinks Whether the book has source links (true) or not (false)
  Future<void> updateBookSourceLinks(int bookId, bool hasSourceLinks) async {
    final db = await _database.database;
    await db.rawUpdate(
        'UPDATE book_has_links SET hasSourceLinks = ? WHERE bookId = ?',
        [hasSourceLinks ? 1 : 0, bookId]);
  }

  /// Updates only the target links status for a book.
  ///
  /// @param bookId The ID of the book to update
  /// @param hasTargetLinks Whether the book has target links (true) or not (false)
  Future<void> updateBookTargetLinks(int bookId, bool hasTargetLinks) async {
    final db = await _database.database;
    await db.rawUpdate(
        'UPDATE book_has_links SET hasTargetLinks = ? WHERE bookId = ?',
        [hasTargetLinks ? 1 : 0, bookId]);
  }

  // --- Connection type specific helpers ---

  Future<int> countLinksBySourceBookAndType(int bookId, String typeName) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) FROM link l
      JOIN connection_type ct ON l.connectionTypeId = ct.id
      WHERE l.sourceBookId = ? AND ct.name = ?
    ''', [bookId, typeName]);
    return result.first.values.first as int;
  }

  Future<int> countLinksByTargetBookAndType(int bookId, String typeName) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) FROM link l
      JOIN connection_type ct ON l.connectionTypeId = ct.id
      WHERE l.targetBookId = ? AND ct.name = ?
    ''', [bookId, typeName]);
    return result.first.values.first as int;
  }

  /// ספירת קישורים לפי מזהה סוג הקישור (במקום שם)
  Future<int> countLinksBySourceBookAndTypeId(int bookId, int typeId) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) FROM link
      WHERE sourceBookId = ? AND connectionTypeId = ?
    ''', [bookId, typeId]);
    return result.first.values.first as int;
  }

  Future<int> countLinksByTargetBookAndTypeId(int bookId, int typeId) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) FROM link
      WHERE targetBookId = ? AND connectionTypeId = ?
    ''', [bookId, typeId]);
    return result.first.values.first as int;
  }

  Future<void> updateBookConnectionFlags(int bookId, bool hasTargum,
      bool hasReference, bool hasCommentary, bool hasOther) async {
    await _database.bookDao.updateBookConnectionFlags(
        bookId, hasTargum, hasReference, hasCommentary, hasOther);
  }

  /// Optimized version that updates all book connection flags in a single query
  /// This is MUCH faster than looping through books individually
  Future<void> updateAllBookConnectionFlagsOptimized() async {
    _logger.info('Updating all book connection flags with optimized query...');
    final db = await _database.database;

    // First, ensure connection_type table has all types
    final types = ['TARGUM', 'REFERENCE', 'COMMENTARY', 'OTHER'];
    for (final type in types) {
      await getOrCreateConnectionType(type);
    }

    // Get connection type IDs
    final typeIds = <String, int>{};
    for (final type in types) {
      final result = await db
          .rawQuery('SELECT id FROM connection_type WHERE name = ?', [type]);
      if (result.isNotEmpty) {
        typeIds[type] = result.first['id'] as int;
      }
    }

    // Update book_has_links table with a single query
    await db.execute('''
      INSERT OR REPLACE INTO book_has_links (bookId, hasSourceLinks, hasTargetLinks)
      SELECT b.id,
             CASE WHEN EXISTS(SELECT 1 FROM link WHERE sourceBookId = b.id) THEN 1 ELSE 0 END,
             CASE WHEN EXISTS(SELECT 1 FROM link WHERE targetBookId = b.id) THEN 1 ELSE 0 END
      FROM book b
    ''');

    // Update connection flags in book table with optimized queries
    if (typeIds.containsKey('TARGUM')) {
      await db.execute('''
        UPDATE book SET hasTargumConnection = 
          CASE WHEN EXISTS(
            SELECT 1 FROM link 
            WHERE (sourceBookId = book.id OR targetBookId = book.id) 
            AND connectionTypeId = ${typeIds['TARGUM']}
          ) THEN 1 ELSE 0 END
      ''');
    }

    if (typeIds.containsKey('REFERENCE')) {
      await db.execute('''
        UPDATE book SET hasReferenceConnection = 
          CASE WHEN EXISTS(
            SELECT 1 FROM link 
            WHERE (sourceBookId = book.id OR targetBookId = book.id) 
            AND connectionTypeId = ${typeIds['REFERENCE']}
          ) THEN 1 ELSE 0 END
      ''');
    }

    if (typeIds.containsKey('COMMENTARY')) {
      await db.execute('''
        UPDATE book SET hasCommentaryConnection = 
          CASE WHEN EXISTS(
            SELECT 1 FROM link 
            WHERE (sourceBookId = book.id OR targetBookId = book.id) 
            AND connectionTypeId = ${typeIds['COMMENTARY']}
          ) THEN 1 ELSE 0 END
      ''');
    }

    if (typeIds.containsKey('OTHER')) {
      await db.execute('''
        UPDATE book SET hasOtherConnection = 
          CASE WHEN EXISTS(
            SELECT 1 FROM link 
            WHERE (sourceBookId = book.id OR targetBookId = book.id) 
            AND connectionTypeId = ${typeIds['OTHER']}
          ) THEN 1 ELSE 0 END
      ''');
    }

    _logger.info('All book connection flags updated successfully');
  }

  /// Checks if a book has any links (source or target).
  ///
  /// @param bookId The ID of the book to check
  /// @return True if the book has any links, false otherwise
  Future<bool> bookHasAnyLinks(int bookId) async {
    _logger.fine('Checking if book $bookId has any links');

    // Check if the book has any links as source or target
    final hasSourceLinks = await bookHasSourceLinks(bookId);
    final hasTargetLinks = await bookHasTargetLinks(bookId);
    final result = hasSourceLinks || hasTargetLinks;

    _logger.fine('Book $bookId has any links: $result');
    return result;
  }

  /// Checks if a book has source links.
  ///
  /// @param bookId The ID of the book to check
  /// @return True if the book has source links, false otherwise
  Future<bool> bookHasSourceLinks(int bookId) async {
    final count = await countLinksBySourceBook(bookId);
    return count > 0;
  }

  /// Checks if a book has target links.
  ///
  /// @param bookId The ID of the book to check
  /// @return True if the book has target links, false otherwise
  Future<bool> bookHasTargetLinks(int bookId) async {
    final count = await countLinksByTargetBook(bookId);
    return count > 0;
  }

  /// Checks if a book has OTHER type comments.
  Future<bool> bookHasOtherComments(int bookId) async {
    final book = await _database.bookDao.getBookById(bookId);
    return book?.hasOtherConnection ?? false;
  }

  /// Checks if a book has COMMENTARY type comments.
  Future<bool> bookHasCommentaryComments(int bookId) async {
    final book = await _database.bookDao.getBookById(bookId);
    return book?.hasCommentaryConnection ?? false;
  }

  /// Checks if a book has REFERENCE type comments.
  Future<bool> bookHasReferenceComments(int bookId) async {
    final book = await _database.bookDao.getBookById(bookId);
    return book?.hasReferenceConnection ?? false;
  }

  /// Checks if a book has TARGUM type comments.
  Future<bool> bookHasTargumComments(int bookId) async {
    final book = await _database.bookDao.getBookById(bookId);
    return book?.hasTargumConnection ?? false;
  }

  /// Gets all books that have any links (source or target).
  ///
  /// @return A list of books that have any links
  Future<List<Book>> getBooksWithAnyLinks() async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT b.* FROM book b
      JOIN book_has_links bhl ON b.id = bhl.bookId
      WHERE bhl.hasSourceLinks = 1 OR bhl.hasTargetLinks = 1
      ORDER BY b.orderIndex, b.title
    ''');

    // Convert the database books to model books
    return Future.wait(result.map((row) async {
      final bookData = Book.fromJson(row);
      final authors = await _getBookAuthors(bookData.id);
      final topics = await _getBookTopics(bookData.id);
      final pubPlaces = await _getBookPubPlaces(bookData.id);
      final pubDates = await _getBookPubDates(bookData.id);
      return bookData.copyWith(
        authors: authors,
        topics: topics,
        pubPlaces: pubPlaces,
        pubDates: pubDates,
      );
    }));
  }

  /// Gets all books that have source links.
  ///
  /// @return A list of books that have source links
  Future<List<Book>> getBooksWithSourceLinks() async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT b.* FROM book b
      JOIN book_has_links bhl ON b.id = bhl.bookId
      WHERE bhl.hasSourceLinks = 1
      ORDER BY b.orderIndex, b.title
    ''');

    // Convert the database books to model books
    return Future.wait(result.map((row) async {
      final bookData = Book.fromJson(row);
      final authors = await _getBookAuthors(bookData.id);
      final topics = await _getBookTopics(bookData.id);
      final pubPlaces = await _getBookPubPlaces(bookData.id);
      final pubDates = await _getBookPubDates(bookData.id);
      return bookData.copyWith(
        authors: authors,
        topics: topics,
        pubPlaces: pubPlaces,
        pubDates: pubDates,
      );
    }));
  }

  /// Gets all books that have target links.
  ///
  /// @return A list of books that have target links
  Future<List<Book>> getBooksWithTargetLinks() async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT b.* FROM book b
      JOIN book_has_links bhl ON b.id = bhl.bookId
      WHERE bhl.hasTargetLinks = 1
      ORDER BY b.orderIndex, b.title
    ''');

    // Convert the database books to model books
    return Future.wait(result.map((row) async {
      final bookData = Book.fromJson(row);
      final authors = await _getBookAuthors(bookData.id);
      final topics = await _getBookTopics(bookData.id);
      final pubPlaces = await _getBookPubPlaces(bookData.id);
      final pubDates = await _getBookPubDates(bookData.id);
      return bookData.copyWith(
        authors: authors,
        topics: topics,
        pubPlaces: pubPlaces,
        pubDates: pubDates,
      );
    }));
  }

  /// Counts the number of books that have any links (source or target).
  ///
  /// @return The number of books that have any links
  Future<int> countBooksWithAnyLinks() async {
    _logger.fine('Counting books with any links');
    final db = await _database.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) FROM book_has_links WHERE hasSourceLinks = 1 OR hasTargetLinks = 1');
    final count = result.first.values.first as int;
    _logger.fine('Found $count books with any links');
    return count;
  }

  /// Counts the number of books that have source links.
  ///
  /// @return The number of books that have source links
  Future<int> countBooksWithSourceLinks() async {
    _logger.fine('Counting books with source links');
    final db = await _database.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) FROM book_has_links WHERE hasSourceLinks = 1');
    final count = result.first.values.first as int;
    _logger.fine('Found $count books with source links');
    return count;
  }

  /// Counts the number of books that have target links.
  ///
  /// @return The number of books that have target links
  Future<int> countBooksWithTargetLinks() async {
    _logger.fine('Counting books with target links');
    final db = await _database.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) FROM book_has_links WHERE hasTargetLinks = 1');
    final count = result.first.values.first as int;
    _logger.fine('Found $count books with target links');
    return count;
  }

  /// Gets all books from the database.
  ///
  /// @return A list of all books
  Future<List<Book>> getAllBooks() async {
    _logger.fine('Getting all books with optimized query');

    // Use the optimized query that loads all relations in a single batch
    final booksWithRelations =
        await _database.bookDao.getAllBooksWithRelations();
    _logger.fine('Found ${booksWithRelations.length} books');

    // Convert to Book objects
    var all =  booksWithRelations
        .map((bookData) => Book.fromJson(bookData))
        .toList();
    return all;
  }

  /// Counts the total number of books in the database.
  ///
  /// @return The total number of books
  Future<int> countAllBooks() async {
    _logger.fine('Counting all books');
    final count = await _database.bookDao.countAllBooks();
    _logger.fine('Found $count books');
    return count;
  }

  /// Counts the number of links where the given book is the source.
  ///
  /// @param bookId The ID of the book to count links for
  /// @return The number of links where the book is the source
  Future<int> countLinksBySourceBook(int bookId) async {
    _logger.fine('Counting links where book $bookId is the source');
    final db = await _database.database;
    final result = await db
        .rawQuery('SELECT COUNT(*) FROM link WHERE sourceBookId = ?', [bookId]);
    final count = result.first.values.first as int;
    _logger.fine('Found $count links where book $bookId is the source');
    return count;
  }

  /// Counts the number of links where the given book is the target.
  ///
  /// @param bookId The ID of the book to count links for
  /// @return The number of links where the book is the target
  Future<int> countLinksByTargetBook(int bookId) async {
    _logger.fine('Counting links where book $bookId is the target');
    final db = await _database.database;
    final result = await db
        .rawQuery('SELECT COUNT(*) FROM link WHERE targetBookId = ?', [bookId]);
    final count = result.first.values.first as int;
    _logger.fine('Found $count links where book $bookId is the target');
    return count;
  }

  /// Finalizes database settings after bulk operations
  Future<void> finalizeDatabase() async {
    _logger.info('Finalizing database settings...');
    await _executeRawQuery('PRAGMA synchronous=FULL');
    await _executeRawQuery('PRAGMA locking_mode=NORMAL');
    _logger.info('Database finalized');
  }

  /// Creates optimization indexes for faster queries
  Future<void> createOptimizationIndexes() async {
    _logger.info('Creating optimization indexes...');

    final db = await _database.database;

    // Indexes for book searches
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_book_title ON book(title)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_book_category ON book(categoryId)');

    // Indexes for lines
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_line_book_index ON line(bookId, lineIndex)');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_line_toc ON line(tocEntryId)');

    // Indexes for links - CRITICAL for performance
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_link_source ON link(sourceBookId, sourceLineId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_link_target ON link(targetBookId, targetLineId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_link_type ON link(connectionTypeId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_link_source_type ON link(sourceBookId, connectionTypeId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_link_target_type ON link(targetBookId, connectionTypeId)');

    // Indexes for authors and topics
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_author_name ON author(name)');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_topic_name ON topic(name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_book_author ON book_author(bookId, authorId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_book_topic ON book_topic(bookId, topicId)');

    // Index for line_toc mapping table
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_line_toc_line ON line_toc(lineId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_line_toc_entry ON line_toc(tocEntryId)');

    _logger.info('Optimization indexes created');
  }

  /// Closes the database connection.
  /// Should be called when the repository is no longer needed.
  Future<void> close() async {
    await _database.close();
  }

  /// Executes a raw SQL query.
  /// This is useful for operations that are not covered by the generated queries,
  /// such as enabling or disabling foreign key constraints.
  ///
  /// @param sql The SQL query to execute
  Future<void> _executeRawQuery(String sql) async {
    final db = await _database.database;
    await db.execute(sql);
  }

  /// Disables foreign key constraints.
  Future<void> disableForeignKeys() async {
    await _executeRawQuery('PRAGMA foreign_keys = OFF');
  }

  /// Enables foreign key constraints.
  Future<void> enableForeignKeys() async {
    await _executeRawQuery('PRAGMA foreign_keys = ON');
  }

  /// Checks if a book with the given title already exists in the database.
  /// Returns the book if found, null otherwise.
  Future<Book?> checkBookExists(String title) async {
    _logger.fine('Checking if book exists: $title');
    return await _database.bookDao.getBookByTitle(title);
  }

  /// Checks if a book with the given title and category already exists in the database.
  /// Returns the book if found, null otherwise.
  Future<Book?> checkBookExistsInCategory(String title, int categoryId) async {
    //_logger.fine('Checking if book exists in category: $title (categoryId: $categoryId)');
    return await _database.bookDao.getBookByTitleAndCategory(title, categoryId);
  }

  /// Checks if a book with the given title, category and file type already exists in the database.
  /// Returns the book if found, null otherwise.
  Future<Book?> checkBookExistsInCategoryWithFileType(String title, int categoryId, String fileType) async {
    //_logger.fine('Checking if book exists in category with file type: $title (categoryId: $categoryId, fileType: $fileType)');
    return await _database.bookDao.getBookByTitleCategoryAndFileType(title, categoryId, fileType);
  }

  /// Deletes a book and all its related data (lines, TOC entries, links, etc.)
  /// This is useful when replacing an existing book.
  Future<void> deleteBookCompletely(int bookId) async {
    _logger.info('Deleting book completely: $bookId');

    // Delete all related data first (due to foreign key constraints)
    final db = await _database.database;

    // Delete links where this book is source or target
    await db.rawDelete(
        'DELETE FROM link WHERE sourceBookId = ? OR targetBookId = ?',
        [bookId, bookId]);

    // Delete book_has_links
    await db.rawDelete('DELETE FROM book_has_links WHERE bookId = ?', [bookId]);

    // Delete TOC entries
    await db.rawDelete('DELETE FROM tocEntry WHERE bookId = ?', [bookId]);

    // Delete lines
    await db.rawDelete('DELETE FROM line WHERE bookId = ?', [bookId]);

    // Delete junction tables
    await db.rawDelete('DELETE FROM book_author WHERE bookId = ?', [bookId]);
    await db.rawDelete('DELETE FROM book_topic WHERE bookId = ?', [bookId]);
    await db.rawDelete('DELETE FROM book_pub_place WHERE bookId = ?', [bookId]);
    await db.rawDelete('DELETE FROM book_pub_date WHERE bookId = ?', [bookId]);

    // Finally delete the book itself
    await _database.bookDao.deleteBook(bookId);

    _logger.info('Book $bookId deleted completely');
  }

  /// Deletes a category from the database.
  /// Note: Make sure to delete all books and subcategories first!
  Future<void> deleteCategory(int categoryId) async {
    _logger.info('Deleting category: $categoryId');

    // Delete from category_closure table
    final db = await _database.database;
    await db.rawDelete(
        'DELETE FROM category_closure WHERE ancestor = ? OR descendant = ?',
        [categoryId, categoryId]);

    // Delete the category itself
    await _database.categoryDao.deleteCategory(categoryId);

    _logger.info('Category $categoryId deleted');
  }
}

// Data classes for enriched results

/// Information about a commentator (author who comments on other books).
///
/// @property bookId The ID of the commentator's book
/// @property title The title of the commentator's book
/// @property author The name of the commentator
/// @property linkCount The number of links (comments) by this commentator
class CommentatorInfo {
  final int bookId;
  final String title;
  final String? author;
  final int linkCount;

  const CommentatorInfo({
    required this.bookId,
    required this.title,
    this.author,
    required this.linkCount,
  });
}

/// A commentary with its text content.
///
/// @property link The link connecting the source text to the commentary
/// @property targetBookTitle The title of the book containing the commentary
/// @property targetText The text of the commentary
class CommentaryWithText {
  final Link link;
  final String targetBookTitle;
  final String targetText;

  const CommentaryWithText({
    required this.link,
    required this.targetBookTitle,
    required this.targetText,
  });
}

/// Mapping between a line and its TOC entry
class LineTocMapping {
  final int lineId;
  final int tocEntryId;

  const LineTocMapping({
    required this.lineId,
    required this.tocEntryId,
  });
}

/// Result of getting max IDs from database tables
class MaxIdsResult {
  final int maxBookId;
  final int maxLineId;
  final int maxTocId;
  final int maxCategoryId;

  const MaxIdsResult({
    required this.maxBookId,
    required this.maxLineId,
    required this.maxTocId,
    required this.maxCategoryId,
  });
}

/// Extension methods for file sync operations
extension FileSyncRepository on SeforimRepository {
  /// Gets the maximum IDs from all relevant tables in a single query.
  /// Used for initializing ID counters in file sync operations.
  Future<MaxIdsResult> getMaxIds() async {
    final db = await database.database;
    final result = await db.rawQuery('''
      SELECT 
        (SELECT COALESCE(MAX(id), 0) FROM book) as maxBookId,
        (SELECT COALESCE(MAX(id), 0) FROM line) as maxLineId,
        (SELECT COALESCE(MAX(id), 0) FROM tocEntry) as maxTocId,
        (SELECT COALESCE(MAX(id), 0) FROM category) as maxCatId
    ''');

    return MaxIdsResult(
      maxBookId: result.first['maxBookId'] as int,
      maxLineId: result.first['maxLineId'] as int,
      maxTocId: result.first['maxTocId'] as int,
      maxCategoryId: result.first['maxCatId'] as int,
    );
  }

  /// Deletes all lines for a specific book.
  /// Used when updating book content.
  Future<void> deleteBookLines(int bookId) async {
    final db = await database.database;
    await db.rawDelete('DELETE FROM line WHERE bookId = ?', [bookId]);
  }

  /// Deletes all TOC entries for a specific book.
  /// Used when updating book content.
  Future<void> deleteBookTocEntries(int bookId) async {
    final db = await database.database;
    await db.rawDelete('DELETE FROM tocEntry WHERE bookId = ?', [bookId]);
  }

  /// Clears book content (lines and TOC entries) for updating.
  /// Preserves book metadata.
  Future<void> clearBookContent(int bookId) async {
    await deleteBookLines(bookId);
    await deleteBookTocEntries(bookId);
  }
}

/// Extension methods for book acronyms
extension BookAcronymRepository on SeforimRepository {
  /// Bulk inserts acronym terms for a book.
  ///
  /// [bookId] The ID of the book
  /// [terms] List of acronym terms to associate with the book
  Future<void> bulkInsertBookAcronyms(int bookId, List<String> terms) async {
    await _database.bookAcronymDao.bulkInsertAcronyms(bookId, terms);
  }

  /// Gets all acronym terms for a book.
  Future<List<String>> getBookAcronyms(int bookId) async {
    return await _database.bookAcronymDao.getTermsByBookId(bookId);
  }

  /// Searches for books by acronym term.
  Future<List<int>> searchBooksByAcronym(String term, {int? limit}) async {
    return await _database.bookAcronymDao
        .searchBooksByAcronym(term, limit: limit);
  }

  /// Deletes all acronyms for a book.
  Future<void> deleteBookAcronyms(int bookId) async {
    await _database.bookAcronymDao.deleteByBookId(bookId);
  }

  /// Inserts a single acronym term for a book.
  Future<void> insertBookAcronym(int bookId, String term) async {
    await _database.bookAcronymDao.insertAcronym(bookId, term);
  }

  /// Gets all book IDs that have a specific acronym term (exact match).
  Future<List<int>> getBookIdsByAcronym(String term) async {
    return await _database.bookAcronymDao.getBookIdsByTerm(term);
  }

  /// Counts the number of acronym terms for a specific book.
  Future<int> countBookAcronyms(int bookId) async {
    return await _database.bookAcronymDao.countByBookId(bookId);
  }

  /// Searches for books by title or acronym for reference finding.
  /// Returns a list of maps containing book info and TOC entries.
  ///
  /// [query] - The search query (book name or acronym)
  /// [limit] - Maximum number of results to return
  Future<List<Map<String, dynamic>>> searchBooksForReference(String query,
      {int limit = 100}) async {
    if (query.isEmpty) return [];

    final db = await _database.database;
    final results = <Map<String, dynamic>>[];
    final seenBookIds = <int>{};

    // Normalize query for matching
    final normalizedQuery = query.trim().toLowerCase();
    final queryPattern = '%$normalizedQuery%';

    // 1. Search by book title (LIKE search)
    final titleResults = await db.rawQuery('''
        SELECT b.id, b.title, b.categoryId, b.filePath, b.fileType
        FROM book b
        WHERE LOWER(b.title) LIKE ?
        ORDER BY 
          CASE WHEN LOWER(b.title) = ? THEN 0
               WHEN LOWER(b.title) LIKE ? THEN 1
               ELSE 2 END,
          b.orderIndex
        LIMIT ?
      ''', [queryPattern, normalizedQuery, '$normalizedQuery%', limit]);

    for (final row in titleResults) {
      final bookId = row['id'] as int;
      if (seenBookIds.add(bookId)) {
        results.add({
          'bookId': bookId,
          'title': row['title'] as String,
          'categoryId': row['categoryId'] as int,
          'filePath': row['filePath'] as String? ?? '',
          'fileType': row['fileType'] as String? ?? 'txt',
          'matchType': 'title',
        });
      }
    }

    // 2. Search by acronym
    final acronymResults = await db.rawQuery('''
        SELECT DISTINCT b.id, b.title, b.categoryId, b.filePath, b.fileType, ba.term
        FROM book_acronym ba
        JOIN book b ON ba.bookId = b.id
        WHERE LOWER(ba.term) LIKE ?
        ORDER BY 
          CASE WHEN LOWER(ba.term) = ? THEN 0
               WHEN LOWER(ba.term) LIKE ? THEN 1
               ELSE 2 END,
          b.orderIndex
        LIMIT ?
      ''', [queryPattern, normalizedQuery, '$normalizedQuery%', limit]);

    for (final row in acronymResults) {
      final bookId = row['id'] as int;
      if (seenBookIds.add(bookId)) {
        results.add({
          'bookId': bookId,
          'title': row['title'] as String,
          'categoryId': row['categoryId'] as int,
          'filePath': row['filePath'] as String? ?? '',
          'fileType': row['fileType'] as String? ?? 'txt',
          'matchType': 'acronym',
          'matchedTerm': row['term'] as String,
        });
      }
    }

    return results.take(limit).toList();
  }

  /// Gets TOC entries for a book that match a reference query.
  /// Returns entries with their full path (e.g., "פרק א" -> "בראשית פרק א")
  ///
  /// [bookId] - The book ID
  /// [bookTitle] - The book title (for building full reference)
  /// [queryTokens] - Optional tokens to filter TOC entries
  Future<List<Map<String, dynamic>>> getTocEntriesForReference(
      int bookId, String bookTitle,
      {List<String>? queryTokens}) async {
    final db = await _database.database;

    // Get all TOC entries for the book
    final tocEntries = await db.rawQuery('''
        SELECT t.id, tt.text, t.level, l.lineIndex, t.parentId
        FROM tocEntry t
        JOIN tocText tt ON t.textId = tt.id
        LEFT JOIN line l ON t.lineId = l.id
        WHERE t.bookId = ?
        ORDER BY l.lineIndex, t.level
      ''', [bookId]);

    if (tocEntries.isEmpty) {
      // If no TOC, return just the book itself
      return [
        {
          'reference': bookTitle,
          'segment': 0,
          'level': 0,
        }
      ];
    }

    final results = <Map<String, dynamic>>[];

    // Build a map of parent IDs to their text for building full paths
    final parentTexts = <int, String>{};
    for (final entry in tocEntries) {
      parentTexts[entry['id'] as int] = entry['text'] as String;
    }

    for (final entry in tocEntries) {
      final text = entry['text'] as String;
      final level = entry['level'] as int;
      final lineIndex = entry['lineIndex'] as int? ?? 0;
      final parentId = entry['parentId'] as int?;

      // Build full reference path
      String fullRef = bookTitle;
      if (text.isNotEmpty) {
        // Add parent path if exists
        if (parentId != null && parentTexts.containsKey(parentId)) {
          fullRef = '$bookTitle ${parentTexts[parentId]} $text';
        } else {
          fullRef = '$bookTitle $text';
        }
      }

      // Filter by query tokens if provided
      if (queryTokens != null && queryTokens.isNotEmpty) {
        final refLower = fullRef.toLowerCase();
        final matches = queryTokens.every((token) => refLower.contains(token));
        if (!matches) continue;
      }

      results.add({
        'reference': fullRef,
        'segment': lineIndex,
        'level': level,
      });
    }

    return results;
  }
}
