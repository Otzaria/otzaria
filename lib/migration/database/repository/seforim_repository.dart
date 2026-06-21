import 'dart:async';
import 'package:logging/logging.dart';

import '../../../utils/text/text_manipulation.dart';
import '../../models/author.dart';
import '../../models/book.dart';
import '../../models/category.dart';
import '../../models/docx_text_cache_entry.dart';
import '../../models/line.dart';
import '../../models/link.dart';
import '../../models/pdf_outline_cache_entry.dart';
import '../../models/pub_date.dart';
import '../../models/pub_place.dart';
import '../../models/search_result.dart';
import '../../models/source.dart';
import '../../models/toc_entry.dart';
import '../../models/toc_text.dart';
import '../../models/topic.dart';
import '../daos/connection_type_dao.dart';
import '../daos/database.dart';
import '../sql/sqlite3_utils.dart';

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

  /// קאש בזיכרון לערכי TOC מעובדים לכל ספר.
  /// המפתח: bookId. הערך: מבנה הכולל את כל הערכים + מבנה היררכי.
  final Map<int, _TocBookCache> _tocCache = <int, _TocBookCache>{};

  /// קאש בזיכרון לערכי AltToc (כותרות-משנה) לכל ספר.
  final Map<int, _TocBookCache> _altTocCache = <int, _TocBookCache>{};

  SeforimRepository(this._database);

  /// מבטל את ערך הקאש של [getTocEntriesForReference] ו-[getAltTocEntriesForReference].
  /// אם [bookId] סופק — מבטל רק את הערך של אותו ספר; אחרת מנקה הכול.
  void _invalidateTocCache({int? bookId}) {
    if (bookId != null) {
      _tocCache.remove(bookId);
      _altTocCache.remove(bookId);
    } else {
      _tocCache.clear();
      _altTocCache.clear();
    }
  }

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
    // SQLite optimizations for normal operations.
    // In read-only mode we must not run any PRAGMA that mutates the file
    // (journal_mode/synchronous/page_size). Per-connection read tunables
    // (cache_size/temp_store/mmap_size) are safe and still applied.
    if (!_database.isReadOnly) {
      await _trySetWal();
      await _executeRawQuery('PRAGMA synchronous=NORMAL');
    }
    // cache_size שלילי = קילובייטים (חיובי = עמודים!). חיבור הקריאה נשאר פתוח
    // לכל אורך הריצה, ולכן מטמון ה-heap שלו תורם ישירות לצריכת ה-RAM במצב סרק.
    // 50MB מספיק; ה-OS file cache וה-mmap מכסים את רוב הקריאות ממילא.
    await _executeRawQuery('PRAGMA cache_size=-50000'); // 50MB
    await _executeRawQuery('PRAGMA temp_store=MEMORY');
    await _executeRawQuery('PRAGMA mmap_size=67108864'); // 64MB
    if (!_database.isReadOnly) {
      await _executeRawQuery('PRAGMA page_size=4096');
    }

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

  /// Bulk upsert line→toc mappings
  Future<void> bulkUpsertLineToc(List<({int lineId, int tocId})> pairs) async {
    if (pairs.isEmpty) return;
    final db = await _database.database;
    withTransaction(db, () {
      for (final pair in pairs) {
        db.execute(
            'INSERT OR REPLACE INTO line_toc (lineId, tocEntryId) VALUES (?, ?)',
            [pair.lineId, pair.tocId]);
      }
    });
  }

  /// Returns all line ids that belong to the given TOC entry (section), ordered by lineIndex.
  Future<List<int>> getLineIdsForTocEntry(int tocEntryId) async {
    final db = await _database.database;
    final result = db.select(
        'SELECT lineId FROM line_toc WHERE tocEntryId = ? ORDER BY lineId',
        [tocEntryId]).toMapList();
    return result.map((row) => row['lineId'] as int).toList();
  }

  /// Builds all mappings for a given book by assigning to each line
  /// the latest TOC entry whose start line index is <= line's index.
  Future<void> rebuildLineTocForBook(int bookId) async {
    final db = await _database.database;
    // Clear existing mappings for the book
    db.execute(
        'DELETE FROM line_toc WHERE lineId IN (SELECT id FROM line WHERE bookId = ?)',
        [bookId]);

    // Insert computed mappings.
    // Lines that appear before the first heading have no tocEntry covering them;
    // the subquery returns NULL for those rows.  We skip them rather than
    // violating the NOT NULL constraint on line_toc.tocEntryId.
    db.execute('''
      INSERT INTO line_toc(lineId, tocEntryId)
      SELECT lineId, tocEntryId
      FROM (
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
      )
      WHERE tocEntryId IS NOT NULL
    ''', [bookId]);
  }

  // --- Transactions ---

  /// Runs a synchronous block of code in a transaction.
  /// The block must be synchronous — do NOT use async/await inside it.
  /// sqlite3 is a synchronous API and using await inside a transaction
  /// would yield control to other tasks, risking database locked errors.
  Future<T> runInTransaction<T>(T Function() block) async {
    final db = await _database.database;
    late T result;
    withTransaction(db, () {
      result = block();
    });
    return result;
  }

  Future<void> setSynchronous(String mode) async {
    await executeRawQuery('PRAGMA synchronous=$mode');
  }

  Future<void> setJournalMode(String mode) async {
    await executeRawQuery('PRAGMA journal_mode=$mode');
  }

  /// WAL may fail when another process holds the DB lock — safe to skip.
  Future<void> _trySetWal() async {
    try {
      await _executeRawQuery('PRAGMA journal_mode=WAL');
    } catch (_) {}
  }

  /// Sets maximum performance mode for bulk operations
  Future<void> setMaxPerformanceMode() async {
    _logger.info('Setting maximum performance mode for bulk operations');
    await executeRawQuery('PRAGMA synchronous=OFF');
    await executeRawQuery('PRAGMA journal_mode=MEMORY'); // Faster than OFF
    await executeRawQuery('PRAGMA locking_mode=EXCLUSIVE');
    await executeRawQuery('PRAGMA cache_size=-200000'); // 200MB (שלילי=ק"ב)
    await executeRawQuery('PRAGMA temp_store=MEMORY');
    await executeRawQuery('PRAGMA mmap_size=536870912'); // 512MB memory-mapped
    _logger.info('Maximum performance mode enabled');
  }

  /// מעלה זמנית את מטמון הקריאה וה-mmap לטובת קריאות רציפות כבדות
  /// (אינדוקס החיפוש קורא את כל שורות כל ספר ברצף). בטוח גם על חיבור read-only —
  /// נוגע רק ב-cache_size/mmap_size, לא ב-journal/synchronous. יש לקרוא ל-
  /// [restoreReadCacheDefaults] בסיום כדי לחזור לפרופיל הסרק החסכוני.
  Future<void> setReadBoostMode() async {
    await _executeRawQuery('PRAGMA cache_size=-200000'); // 200MB (שלילי=ק"ב)
    await _executeRawQuery('PRAGMA mmap_size=536870912'); // 512MB
  }

  /// מחזיר את חיבור הקריאה לפרופיל הסרק החסכוני (תואם ל-[_initialize]).
  Future<void> restoreReadCacheDefaults() async {
    await _executeRawQuery('PRAGMA cache_size=-50000'); // 50MB (שלילי=ק"ב)
    await _executeRawQuery('PRAGMA mmap_size=67108864'); // 64MB
  }

  /// Restores normal performance mode after bulk operations
  Future<void> restoreNormalMode() async {
    _logger.info('Restoring normal performance mode');
    await executeRawQuery('PRAGMA synchronous=NORMAL');
    await _trySetWal();
    await executeRawQuery('PRAGMA locking_mode=NORMAL');
    await executeRawQuery('PRAGMA cache_size=-50000'); // 50MB (שלילי=ק"ב)
    _logger.info('Normal performance mode restored');
  }

  /// Rebuilds the category_closure table from the current category tree.
  Future<void> rebuildCategoryClosure() async {
    final db = await _database.database;
    // Clear existing closure data
    db.execute('DELETE FROM category_closure');

    // Load all categories
    final rows = db.select('SELECT id, parentId FROM category').toMapList();
    final parentMap = <int, int?>{};
    for (final row in rows) {
      parentMap[row['id'] as int] = row['parentId'] as int?;
    }

    // For each category, walk up to root and insert pairs
    for (final row in rows) {
      final descId = row['id'] as int;
      int? ancId = descId;

      // Self
      db.execute(
          'INSERT INTO category_closure (ancestorId, descendantId) VALUES (?, ?)',
          [descId, descId]);

      ancId = parentMap[descId];
      var guard = 0;
      const safety = 128;

      while (ancId != null && guard++ < safety) {
        db.execute(
            'INSERT INTO category_closure (ancestorId, descendantId) VALUES (?, ?)',
            [ancId, descId]);
        ancId = parentMap[ancId];
      }
    }
  }

  /// מוסיף את הרשומות הנדרשות ל-category_closure עבור קטגוריה שזה עתה הוכנסה.
  /// יש לקרוא לזה אחרי כל insertCategoryWithId מוצלח, כדי לשמור על הטבלה עקבית
  /// בלי צורך ב-rebuildCategoryClosure גלובלי.
  Future<void> _insertClosureForCategory(int categoryId, int? parentId) async {
    final db = await _database.database;
    // הפניה עצמית — כל קטגוריה היא צאצא של עצמה.
    db.execute(
        'INSERT OR IGNORE INTO category_closure (ancestorId, descendantId) VALUES (?, ?)',
        [categoryId, categoryId]);
    // ירושת כל האבות של ההורה — כולל ההורה עצמו (דרך ה-self-loop שלו).
    if (parentId != null) {
      db.execute(
          'INSERT OR IGNORE INTO category_closure (ancestorId, descendantId) '
          'SELECT ancestorId, ? FROM category_closure WHERE descendantId = ?',
          [categoryId, parentId]);
    }
  }

  /// Returns all descendant category IDs (including the category itself) using the
  /// category_closure table.
  Future<List<int>> getDescendantCategoryIds(int ancestorId) async {
    final db = await _database.database;
    final result = db.select(
        'SELECT descendantId FROM category_closure WHERE ancestorId = ?',
        [ancestorId]).toMapList();
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
      // בדוק אם קיימת קטגוריה עם אותו שם ואותו הורה
      final existingCategories =
          await _getCategoriesByParent(category.parentId);
      final existingCategory = existingCategories.firstWhere(
        (cat) => cat.title == category.title,
        orElse: () => Category(id: 0, title: '', parentId: null, level: 0),
      );
      if (existingCategory.id != 0) {
        return existingCategory.id;
      }

      final insertedId = await _database.categoryDao.insertCategory(
        category.parentId,
        category.title,
        category.level,
      );

      // ודא שההכנסה הצליחה
      if (insertedId == 0) {
        // בדוק שוב אם הקטגוריה נוספה למרות הכל
        final updatedCategories =
            await _getCategoriesByParent(category.parentId);
        final newCategory = updatedCategories.firstWhere(
          (cat) => cat.title == category.title,
          orElse: () => Category(id: 0, title: '', parentId: null, level: 0),
        );
        if (newCategory.id != 0) {
          // עדכון אינקרמנטלי של category_closure — מונע rebuild גלובלי בעלייה.
          await _insertClosureForCategory(newCategory.id, category.parentId);
          return newCategory.id;
        }
        throw Exception(
            'Failed to insert category \'${category.title}\' with parent ${category.parentId}');
      }
      // עדכון אינקרמנטלי של category_closure — מונע rebuild גלובלי בעלייה.
      await _insertClosureForCategory(insertedId, category.parentId);
      return insertedId;
    } catch (e) {
      _logger.warning(
          'Repository: Error inserting category \'${category.title}\': ${e.toString()}');
      // במקרה של שגיאה, בדוק אם הקטגוריה קיימת בכל זאת
      final categories = await _getCategoriesByParent(category.parentId);
      final existingCategory = categories.firstWhere(
        (cat) => cat.title == category.title,
        orElse: () => Category(id: 0, title: '', parentId: null, level: 0),
      );
      if (existingCategory.id != 0) {
        return existingCategory.id;
      }
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
    final result = db.select('''
      SELECT a.* FROM author a
      JOIN book_author ba ON a.id = ba.authorId
      WHERE ba.bookId = ?
    ''', [bookId]).toMapList();
    return result.map((row) => Author.fromJson(row)).toList();
  }

  // Get all topics for a book
  Future<List<Topic>> _getBookTopics(int bookId) async {
    final db = await _database.database;
    final result = db.select('''
      SELECT t.* FROM topic t
      JOIN book_topic bt ON t.id = bt.topicId
      WHERE bt.bookId = ?
    ''', [bookId]).toMapList();
    return result.map((row) => Topic.fromJson(row)).toList();
  }

  // Get all publication places for a book
  Future<List<PubPlace>> _getBookPubPlaces(int bookId) async {
    final db = await _database.database;
    final result = db.select('''
      SELECT pp.* FROM pub_place pp
      JOIN book_pub_place bpp ON pp.id = bpp.pubPlaceId
      WHERE bpp.bookId = ?
    ''', [bookId]).toMapList();
    return result.map((row) => PubPlace.fromJson(row)).toList();
  }

  // Get all publication dates for a book
  Future<List<PubDate>> _getBookPubDates(int bookId) async {
    final db = await _database.database;
    final result = db.select('''
      SELECT pd.* FROM pub_date pd
      JOIN book_pub_date bpd ON pd.id = bpd.pubDateId
      WHERE bpd.bookId = ?
    ''', [bookId]).toMapList();
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
    final bookData =
        await _database.bookDao.getBookByTitleAndCategory(title, categoryId);
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

  Future<Book?> getBookByTitleCategoryAndFileType(
      String title, int categoryId, String fileType) async {
    final bookData = await _database.bookDao
        .getBookByTitleCategoryAndFileType(title, categoryId, fileType);
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

  /// מחזיר ספר לפי כותרת וסוג קובץ.
  Future<Book?> getBookByTitleAndFileType(String title, String fileType) async {
    final bookData =
        await _database.bookDao.getBookByTitleAndFileType(title, fileType);
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
  /// SQLite assigns the ID via AUTOINCREMENT.
  ///
  /// @param book The book to insert
  /// @return The ID of the inserted book
  Future<int> insertBook(Book book) async {
    final bookId = await _database.bookDao.insertBook(
      book.categoryId,
      book.sourceId,
      book.title,
      book.heShortDesc,
      book.order,
      book.totalLines,
      book.isBaseBook,
      hasTargumConnection: book.hasTargumConnection,
      hasReferenceConnection: book.hasReferenceConnection,
      hasSourceConnection: book.hasSourceConnection,
      hasCommentaryConnection: book.hasCommentaryConnection,
      hasOtherConnection: book.hasOtherConnection,
      hasAltStructures: book.hasAltStructures,
      hasTeamim: book.hasTeamim,
      hasNekudot: book.hasNekudot,
      isPersonal: book.isPersonal,
      filePath: book.filePath,
      fileType: book.fileType,
      fileSize: book.fileSize,
      lastModified: book.lastModified,
      pages: book.pages,
      volume: book.volume,
    );

    for (final author in book.authors) {
      final authorId = await insertAuthor(author.name);
      await linkAuthorToBook(authorId, bookId);
    }
    for (final topic in book.topics) {
      final topicId = await insertTopic(topic.name);
      await linkTopicToBook(topicId, bookId);
    }
    for (final pubPlace in book.pubPlaces) {
      final pubPlaceId = await insertPubPlace(pubPlace.name);
      await linkPubPlaceToBook(pubPlaceId, bookId);
    }
    for (final pubDate in book.pubDates) {
      final pubDateId = await insertPubDate(pubDate.date);
      await linkPubDateToBook(pubDateId, bookId);
    }
    return bookId;
  }

  // --- Sources ---

  /// Returns a Source by id, or null if not found.
  Future<Source?> getSourceById(int id) async {
    final db = await _database.database;
    final result =
        db.select('SELECT * FROM source WHERE id = ?', [id]).toMapList();
    if (result.isEmpty) return null;
    return Source.fromJson(result.first);
  }

  /// Returns a Source by name, or null if not found.
  Future<Source?> getSourceByName(String name) async {
    final db = await _database.database;
    final result =
        db.select('SELECT * FROM source WHERE name = ?', [name]).toMapList();
    if (result.isEmpty) return null;
    return Source.fromJson(result.first);
  }

  /// Inserts a source if missing and returns its id.
  Future<int> insertSource(String name, int newSourceId) async {
    // Check existing
    final existing = await getSourceByName(name);
    if (existing != null) return existing.id;

    final db = await _database.database;
    if (newSourceId > 0) {
      db.execute(
        'INSERT OR IGNORE INTO source (id, name) VALUES (?, ?)',
        [newSourceId, name],
      );
    } else {
      db.execute(
        'INSERT OR IGNORE INTO source (name) VALUES (?)',
        [name],
      );
    }
    final again = await getSourceByName(name);
    if (again != null) return again.id;
    throw Exception('Failed to insert source \'$name\'');
  }

  Future<void> updateBookTotalLines(int bookId, int totalLines) async {
    await _database.bookDao.updateBookTotalLines(bookId, totalLines);
  }

  Future<void> updateBookCategoryId(int bookId, int categoryId) async {
    await _database.bookDao.updateBookCategoryId(bookId, categoryId);
  }

  // --- External Content Books ---

  /// Inserts an external content book (content stored externally, metadata in DB).
  /// External content books store file path, type, size, and last modified.
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
  /// @param isPersonal Whether this is a personal/user-added book
  /// @param tocEntries Optional list of TOC entries to create
  /// @return The ID of the inserted book
  Future<int> insertExternalContentBook({
    required int categoryId,
    required String title,
    required String filePath,
    required String fileType,
    required int fileSize,
    required int lastModified,
    String? heShortDesc,
    double orderIndex = 999,
    bool isPersonal = false,
    List<TocEntry>? tocEntries,
  }) async {
    // Get or create a source for external content books
    final sourceId = await insertSource('external', -1);

    final bookId = await _database.bookDao.insertBook(
      categoryId,
      sourceId,
      title,
      heShortDesc,
      orderIndex,
      0,
      false,
      isPersonal: isPersonal,
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

  /// מחליף את ה-TOC של ספר חיצוני קיים (מחיקת הישן + הוספת החדש). נדרש
  /// כשקובץ DOCX/TXT נערך — כדי שהניווט יתעדכן לפי התוכן החדש, ולא יישאר
  /// לפי הגרסה הישנה.
  Future<void> replaceExternalBookToc(
      int bookId, List<TocEntry> tocEntries) async {
    await deleteBookTocEntries(bookId);
    if (tocEntries.isNotEmpty) {
      await _insertTocEntriesForExternalBook(bookId, tocEntries);
    }
  }

  /// Updates a book's storage details (file path, file size, last modified).
  /// Required when a book transitions between being stored externally and within the DB.
  Future<void> updateBookStorage(
      int bookId, String? filePath, int? fileSize, int? lastModified) async {
    _logger.fine('Updating book storage: bookId=$bookId, filePath=$filePath');
    final db = await _database.database;
    db.execute(
        'UPDATE book SET filePath = ?, fileSize = ?, lastModified = ? WHERE id = ?',
        [filePath, fileSize, lastModified, bookId]);
  }

  Future<void> updateBookSourceId(int bookId, int sourceId) async {
    _logger.fine('Updating book source: bookId=$bookId, sourceId=$sourceId');
    final db = await _database.database;
    db.execute(
      'UPDATE book SET sourceId = ? WHERE id = ?',
      [sourceId, bookId],
    );
  }

  /// Gets an external book by its file path.
  Future<Book?> getExternalBookByFilePath(String filePath) async {
    return await _database.bookDao.getBookByFilePath(filePath);
  }

  /// Gets an external book by its file path and file type.
  Future<Book?> getExternalBookByFilePathAndType(
      String filePath, String fileType) async {
    return await _database.bookDao.getBookByFilePathAndType(filePath, fileType);
  }

  /// Inserts TOC entries for an external book.
  /// Creates toc_text entries and toc_entry entries.
  Future<void> _insertTocEntriesForExternalBook(
      int bookId, List<TocEntry> entries) async {
    _invalidateTocCache(bookId: bookId);
    _logger.fine(
        'Inserting ${entries.length} TOC entries for external book $bookId');
    final localToActualIds = <int, int>{};

    for (final entry in entries) {
      final textId = await _getOrCreateTocText(entry.text);
      final actualParentId =
          entry.parentId == null ? null : localToActualIds[entry.parentId];

      if (entry.parentId != null && actualParentId == null) {
        throw StateError(
          'Unresolved external TOC parentId ${entry.parentId} for book $bookId',
        );
      }

      // For external books, use lineIndex (not lineId) to store the line number.
      final tocEntry = TocEntry(
        id: 0,
        bookId: bookId,
        parentId: actualParentId,
        textId: textId,
        level: entry.level,
        lineId: null,
        lineIndex: entry.lineIndex,
        isLastChild: entry.isLastChild,
        hasChildren: entry.hasChildren,
      );

      final actualTocId = await _database.tocDao.insertTocEntry(tocEntry);

      if (entry.id != 0) {
        localToActualIds[entry.id] = actualTocId;
      }
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
    return db.select(
      'SELECT id, lineIndex FROM line WHERE bookId = ?',
      [bookId],
    ).toMapList();
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

    final lineId = await _database.lineDao.insertLine(line);
    if (lineId == 0) {
      final existingLine = await getLineByIndex(line.bookId, line.lineIndex);
      if (existingLine != null) {
        return existingLine.id;
      }

      throw Exception(
          'Failed to insert line for book ${line.bookId} at index ${line.lineIndex} - insertion returned ID 0. Context: content=\'${line.content.substring(0, line.content.length < 50 ? line.content.length : 50)}${line.content.length > 50 ? "..." : ""}\'');
    }

    return lineId;
  }

  /// Inserts multiple lines in a single batch operation for better performance
  Future<void> insertLinesBatch(List<Line> lines) async {
    if (lines.isEmpty) return;

    final db = await _database.database;
    withTransaction(db, () {
      for (final line in lines) {
        db.execute(
            'INSERT INTO line (bookId, lineIndex, content, heRef, tocEntryId) VALUES (?, ?, ?, ?, ?)',
            [
              line.bookId,
              line.lineIndex,
              line.content,
              line.heRef,
              null,
            ]);
      }
    });
  }

  Future<void> updateLineHeRefsBatch(Map<int, String> lineIdToHeRef) async {
    if (lineIdToHeRef.isEmpty) return;

    final db = await _database.database;
    withTransaction(db, () {
      for (final entry in lineIdToHeRef.entries) {
        db.execute(
          'UPDATE line SET heRef = ? WHERE id = ? AND (heRef IS NULL OR heRef = "" OR LENGTH(heRef) < LENGTH(?))',
          [entry.value, entry.key, entry.value],
        );
      }
    });
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

  Future<List<TocEntry>> getTocChildren(int parentId) async {
    return await _database.tocDao.selectChildren(parentId);
  }

  // --- Persistent external PDF outline cache ---

  Future<PdfOutlineCacheEntry?> getPdfOutlineCacheEntry(String filePath) async {
    return _database.pdfOutlineCacheDao.selectByFilePath(filePath);
  }

  Future<void> upsertPdfOutlineCacheEntry(PdfOutlineCacheEntry entry) async {
    await _database.pdfOutlineCacheDao.upsert(entry);
  }

  Future<void> touchPdfOutlineCacheEntry(
      String filePath, int accessedAt) async {
    await _database.pdfOutlineCacheDao.updateAccessedAt(filePath, accessedAt);
  }

  Future<void> deletePdfOutlineCacheEntry(String filePath) async {
    await _database.pdfOutlineCacheDao.deleteByFilePath(filePath);
  }

  Future<void> prunePdfOutlineCacheAccessedBefore(int cutoffMillis) async {
    await _database.pdfOutlineCacheDao.deleteAccessedBefore(cutoffMillis);
  }

  // --- Persistent external DOCX text cache ---

  Future<DocxTextCacheEntry?> getDocxTextCacheEntry(String filePath) async {
    return _database.docxTextCacheDao.selectByFilePath(filePath);
  }

  Future<void> upsertDocxTextCacheEntry(DocxTextCacheEntry entry) async {
    await _database.docxTextCacheDao.upsert(entry);
  }

  Future<void> deleteDocxTextCacheEntry(String filePath) async {
    await _database.docxTextCacheDao.deleteByFilePath(filePath);
  }

  Future<void> touchDocxTextCacheEntry(String filePath, int accessedAt) async {
    await _database.docxTextCacheDao.updateAccessedAt(filePath, accessedAt);
  }

  Future<void> pruneDocxTextCacheAccessedBefore(int cutoffMillis) async {
    await _database.docxTextCacheDao.deleteAccessedBefore(cutoffMillis);
  }

  Future<void> prunePdfOutlineCacheExceptFilePaths(
      Set<String> keepFilePaths) async {
    await _database.pdfOutlineCacheDao.deleteAllExceptFilePaths(keepFilePaths);
  }

  // --- TocText methods ---

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
    _invalidateTocCache(bookId: entry.bookId);
    final textId = entry.textId ?? await _getOrCreateTocText(entry.text);

    final entryWithTextId = TocEntry(
      id: 0,
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

    return _database.tocDao.insertTocEntry(entryWithTextId);
  }

  // Nouvelle méthode pour mettre à jour hasChildren
  Future<void> updateTocEntryHasChildren(
      int tocEntryId, bool hasChildren) async {
    // bookId לא ידוע כאן — ניקוי גורף בטוח יותר מ-stale data.
    _invalidateTocCache();
    await _database.tocDao.updateHasChildren(tocEntryId, hasChildren);
  }

  Future<void> updateTocEntryLineId(int tocEntryId, int lineId) async {
    _invalidateTocCache();
    await _database.tocDao.updateLineId(tocEntryId, lineId);
  }

  Future<void> updateTocEntryIsLastChild(
      int tocEntryId, bool isLastChild) async {
    _invalidateTocCache();
    await _database.tocDao.updateIsLastChild(tocEntryId, isLastChild);
  }

  /// Bulk update TOC entry lineIds
  Future<void> bulkUpdateTocEntryLineIds(
      List<({int tocId, int lineId})> updates) async {
    if (updates.isEmpty) return;
    _invalidateTocCache();
    final db = await _database.database;
    withTransaction(db, () {
      for (final update in updates) {
        db.execute('UPDATE tocEntry SET lineId = ? WHERE id = ?',
            [update.lineId, update.tocId]);
      }
    });
  }

  /// Bulk update TOC entries hasChildren flag
  Future<void> bulkUpdateTocEntryHasChildren(
      List<int> tocEntryIds, bool hasChildren) async {
    if (tocEntryIds.isEmpty) return;
    _invalidateTocCache();
    final db = await _database.database;
    final placeholders = List.filled(tocEntryIds.length, '?').join(',');
    db.execute(
        'UPDATE tocEntry SET hasChildren = ? WHERE id IN ($placeholders)',
        [hasChildren ? 1 : 0, ...tocEntryIds]);
  }

  /// Bulk update TOC entries isLastChild flag
  Future<void> bulkUpdateTocEntryIsLastChild(
      List<int> tocEntryIds, bool isLastChild) async {
    if (tocEntryIds.isEmpty) return;
    _invalidateTocCache();
    final db = await _database.database;
    final placeholders = List.filled(tocEntryIds.length, '?').join(',');
    db.execute(
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

    final types = ['OTHER', 'COMMENTARY', 'SOURCE', 'TARGUM', 'REFERENCE'];

    for (final type in types) {
      // Force creation/retrieval and cache it
      try {
        _connectionTypeCache[type] = await _fetchOrCreateConnectionType(type);
      } catch (e) {
        // In read-only mode a missing connection type cannot be created.
        // A properly generated seforim.db already has all types, so this is
        // only a safety net — skip the missing type rather than aborting.
        if (!_database.isReadOnly) rethrow;
      }
    }
    _logger.info('Initialized connection types cache: $_connectionTypeCache');
  }

  /// Internal method to fetch or create connection type without cache check
  Future<int> _fetchOrCreateConnectionType(String name) async {
    final db = await _database.database;
    final existingResult = db.select(
        'SELECT id FROM connection_type WHERE name = ?', [name]).toMapList();
    if (existingResult.isNotEmpty) {
      return existingResult.first['id'] as int;
    }

    if (_database.isReadOnly) {
      throw StateError(
          'Connection type "$name" is missing in a read-only database');
    }

    db.execute('INSERT INTO connection_type (name) VALUES (?)', [name]);
    final typeId = db.lastInsertRowId;

    if (typeId == 0) {
      final insertedResult = db.select(
          'SELECT id FROM connection_type WHERE name = ?', [name]).toMapList();
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
        db.select('SELECT name FROM connection_type ORDER BY name').toMapList();
    return result.map((row) => row['name'] as String).toList();
  }

  /// שליפת כל סוגי ההקשרים מטבלת connection_type
  Future<List<ConnectionTypeEntry>> getAllConnectionTypesObj() async {
    return await _database.connectionTypeDao.getAllConnectionTypes();
  }

  // --- Links ---

  Future<Link?> getLink(int id) async {
    final db = await _database.database;
    final result =
        db.select('SELECT * FROM link WHERE id = ?', [id]).toMapList();
    if (result.isEmpty) return null;
    return Link.fromJson(result.first);
  }

  Future<int> countLinks() async {
    final db = await _database.database;
    final result = db.select('SELECT COUNT(*) FROM link');
    return result.first.values.first as int;
  }

  Future<List<CommentaryWithText>> getCommentariesForLines(
      List<int> lineIds, Set<int> activeCommentatorIds) async {
    final db = await _database.database;
    final placeholders = List.filled(lineIds.length, '?').join(',');
    final result = db.select('''
      SELECT l.*, b.title as targetBookTitle, ln.plainText as targetText
      FROM link l
      JOIN book b ON l.targetBookId = b.id
      JOIN line ln ON l.targetLineId = ln.id
      WHERE l.sourceLineId IN ($placeholders)
      ${activeCommentatorIds.isNotEmpty ? 'AND l.targetBookId IN (${List.filled(activeCommentatorIds.length, '?').join(',')})' : ''}
      ORDER BY l.targetBookId, l.targetLineId
    ''', [...lineIds, ...activeCommentatorIds]).toMapList();

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
    final result = db.select('''
      SELECT b.id as targetBookId, b.title as targetBookTitle, a.name as author, COUNT(l.id) as linkCount
      FROM link l
      JOIN book b ON l.targetBookId = b.id
      LEFT JOIN book_author ba ON b.id = ba.bookId
      LEFT JOIN author a ON ba.authorId = a.id
      WHERE l.sourceBookId = ?
      GROUP BY b.id, b.title, a.name
      ORDER BY b.title
    ''', [bookId]).toMapList();

    return result
        .map((row) => CommentatorInfo(
              bookId: row['targetBookId'] as int,
              title: row['targetBookTitle'] as String,
              author: row['author'] as String?,
              linkCount: row['linkCount'] as int,
            ))
        .toList();
  }

  /// מחזיר את מידע הדור של ספר לפי ה-ID שלו
  ///
  /// [bookId] - מזהה הספר
  /// מחזיר [BookGenerationInfo] עם שם הדור וסדר המיון, או null אם לא נמצא
  Future<BookGenerationInfo?> getBookGenerationInfo(int bookId) async {
    final db = await _database.database;
    final result = db.select('''
      SELECT g.id, g.name
      FROM book b
      LEFT JOIN book_author ba ON b.id = ba.bookId
      LEFT JOIN author a ON ba.authorId = a.id
      LEFT JOIN generation g ON a.generationId = g.id
      WHERE b.id = ?
      LIMIT 1
    ''', [bookId]).toMapList();

    if (result.isEmpty || result.first['id'] == null) {
      return null;
    }

    return BookGenerationInfo(
      generationId: result.first['id'] as int,
      generationName: result.first['name'] as String,
    );
  }

  /// מחזיר את מידע הדור של ספר לפי שם הספר
  ///
  /// [bookTitle] - שם הספר
  /// מחזיר [BookGenerationInfo] עם שם הדור וסדר המיון, או null אם לא נמצא
  Future<BookGenerationInfo?> getBookGenerationInfoByTitle(
      String bookTitle) async {
    final db = await _database.database;
    final result = db.select('''
      SELECT g.id, g.name
      FROM book b
      LEFT JOIN book_author ba ON b.id = ba.bookId
      LEFT JOIN author a ON ba.authorId = a.id
      LEFT JOIN generation g ON a.generationId = g.id
      WHERE b.title = ?
        AND COALESCE(b.fileType, '') NOT IN ('link', 'url')
      LIMIT 1
    ''', [bookTitle]).toMapList();

    if (result.isEmpty || result.first['id'] == null) {
      return null;
    }

    return BookGenerationInfo(
      generationId: result.first['id'] as int,
      generationName: result.first['name'] as String,
    );
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
      final connectionTypeId =
          await getOrCreateConnectionType(link.connectionType.name);
      final linkId = await _database.linkDao.insertLink(link, connectionTypeId);
      // Check if insertion failed
      if (linkId == 0) {
        // Try to find a matching link
        final existingResult = await _database.linkDao.selectLinkByDetails(
            link.sourceBookId,
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

    db.execute('''
      INSERT OR IGNORE INTO link (sourceBookId, targetBookId, sourceLineId, targetLineId, connectionTypeId)
      VALUES $values
    ''');
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
    final result = db.select('''
      SELECT l.id, l.bookId, l.lineIndex, b.title as bookTitle, l.plainText,
             snippet(line_search, 4, '<b>', '</b>', '...', 50) as snippet
      FROM line_search
      JOIN line l ON line_search.id = l.id
      JOIN book b ON line_search.bookId = b.id
      WHERE line_search.plainText MATCH ?
      ORDER BY rank
      LIMIT ? OFFSET ?
    ''', [ftsQuery, limit, offset]).toMapList();

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
    final result = db.select('''
      SELECT l.id, l.bookId, l.lineIndex, b.title as bookTitle, l.plainText,
             snippet(line_search, 4, '<b>', '</b>', '...', 50) as snippet
      FROM line_search
      JOIN line l ON line_search.id = l.id
      JOIN book b ON line_search.bookId = b.id
      WHERE line_search.bookId = ? AND line_search.plainText MATCH ?
      ORDER BY rank
      LIMIT ? OFFSET ?
    ''', [bookId, ftsQuery, limit, offset]).toMapList();

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
    final result = db.select('''
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
    ''', ['%$author%', ftsQuery, limit, offset]).toMapList();

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
    db.execute(sql);
  }

  /// Begins a database transaction for better performance on bulk operations.
  Future<void> beginTransaction() async {
    final db = await _database.database;
    db.execute('BEGIN TRANSACTION');
  }

  /// Commits the current database transaction.
  Future<void> commitTransaction() async {
    final db = await _database.database;
    db.execute('COMMIT');
  }

  /// Rolls back the current database transaction.
  Future<void> rollbackTransaction() async {
    final db = await _database.database;
    db.execute('ROLLBACK');
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
    db.execute('''
      INSERT OR REPLACE INTO book_has_links (bookId, hasSourceLinks, hasTargetLinks)
      VALUES (?, ?, ?)
    ''', [bookId, hasSourceLinks ? 1 : 0, hasTargetLinks ? 1 : 0]);
  }

  // --- Connection type specific helpers ---

  Future<int> countLinksBySourceBookAndType(int bookId, String typeName) async {
    final db = await _database.database;
    final result = db.select('''
      SELECT COUNT(*) FROM link l
      JOIN connection_type ct ON l.connectionTypeId = ct.id
      WHERE l.sourceBookId = ? AND ct.name = ?
    ''', [bookId, typeName]);
    return result.first.values.first as int;
  }

  Future<int> countLinksByTargetBookAndType(int bookId, String typeName) async {
    final db = await _database.database;
    final result = db.select('''
      SELECT COUNT(*) FROM link l
      JOIN connection_type ct ON l.connectionTypeId = ct.id
      WHERE l.targetBookId = ? AND ct.name = ?
    ''', [bookId, typeName]);
    return result.first.values.first as int;
  }

  /// ספירת קישורים לפי מזהה סוג הקישור (במקום שם)
  Future<int> countLinksBySourceBookAndTypeId(int bookId, int typeId) async {
    final db = await _database.database;
    final result = db.select('''
      SELECT COUNT(*) FROM link
      WHERE sourceBookId = ? AND connectionTypeId = ?
    ''', [bookId, typeId]);
    return result.first.values.first as int;
  }

  Future<int> countLinksByTargetBookAndTypeId(int bookId, int typeId) async {
    final db = await _database.database;
    final result = db.select('''
      SELECT COUNT(*) FROM link
      WHERE targetBookId = ? AND connectionTypeId = ?
    ''', [bookId, typeId]);
    return result.first.values.first as int;
  }

  Future<void> updateBookConnectionFlags(
      int bookId,
      bool hasTargum,
      bool hasReference,
      bool hasSource,
      bool hasCommentary,
      bool hasOther) async {
    await _database.bookDao.updateBookConnectionFlags(
        bookId, hasTargum, hasReference, hasSource, hasCommentary, hasOther);
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
      final result = db.select(
          'SELECT id FROM connection_type WHERE name = ?', [type]).toMapList();
      if (result.isNotEmpty) {
        typeIds[type] = result.first['id'] as int;
      }
    }

    // Update book_has_links table with a single query
    db.execute('''
      INSERT OR REPLACE INTO book_has_links (bookId, hasSourceLinks, hasTargetLinks)
      SELECT b.id,
             CASE WHEN EXISTS(SELECT 1 FROM link WHERE sourceBookId = b.id) THEN 1 ELSE 0 END,
             CASE WHEN EXISTS(SELECT 1 FROM link WHERE targetBookId = b.id) THEN 1 ELSE 0 END
      FROM book b
    ''');

    // Update connection flags in book table with optimized queries
    if (typeIds.containsKey('TARGUM')) {
      db.execute('''
        UPDATE book SET hasTargumConnection = 
          CASE WHEN EXISTS(
            SELECT 1 FROM link 
            WHERE (sourceBookId = book.id OR targetBookId = book.id) 
            AND connectionTypeId = ${typeIds['TARGUM']}
          ) THEN 1 ELSE 0 END
      ''');
    }

    if (typeIds.containsKey('REFERENCE')) {
      db.execute('''
        UPDATE book SET hasReferenceConnection = 
          CASE WHEN EXISTS(
            SELECT 1 FROM link 
            WHERE (sourceBookId = book.id OR targetBookId = book.id) 
            AND connectionTypeId = ${typeIds['REFERENCE']}
          ) THEN 1 ELSE 0 END
      ''');
    }

    if (typeIds.containsKey('COMMENTARY')) {
      db.execute('''
        UPDATE book SET hasCommentaryConnection = 
          CASE WHEN EXISTS(
            SELECT 1 FROM link 
            WHERE (sourceBookId = book.id OR targetBookId = book.id) 
            AND connectionTypeId = ${typeIds['COMMENTARY']}
          ) THEN 1 ELSE 0 END
      ''');
    }

    if (typeIds.containsKey('OTHER')) {
      db.execute('''
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

  /// Gets all books that have any links (source or target).
  ///
  /// @return A list of books that have any links
  Future<List<Book>> getBooksWithAnyLinks() async {
    final db = await _database.database;
    final result = db.select('''
      SELECT b.* FROM book b
      JOIN book_has_links bhl ON b.id = bhl.bookId
      WHERE (bhl.hasSourceLinks = 1 OR bhl.hasTargetLinks = 1)
        AND COALESCE(b.fileType, '') NOT IN ('link', 'url')
      ORDER BY b.orderIndex, b.title
    ''').toMapList();

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
    final result = db.select('''
      SELECT b.* FROM book b
      JOIN book_has_links bhl ON b.id = bhl.bookId
      WHERE bhl.hasSourceLinks = 1
        AND COALESCE(b.fileType, '') NOT IN ('link', 'url')
      ORDER BY b.orderIndex, b.title
    ''').toMapList();

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
    final result = db.select('''
      SELECT b.* FROM book b
      JOIN book_has_links bhl ON b.id = bhl.bookId
      WHERE bhl.hasTargetLinks = 1
        AND COALESCE(b.fileType, '') NOT IN ('link', 'url')
      ORDER BY b.orderIndex, b.title
    ''').toMapList();

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
    final result = db.select(
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
    final result = db
        .select('SELECT COUNT(*) FROM book_has_links WHERE hasSourceLinks = 1');
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
    final result = db
        .select('SELECT COUNT(*) FROM book_has_links WHERE hasTargetLinks = 1');
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
    // External catalog books (fileType='link') are excluded since they are in a separate DB
    final booksWithRelations =
        await _database.bookDao.getAllBooksWithRelations();
    _logger.fine('Found ${booksWithRelations.length} books');

    // Convert to Book objects
    var all =
        booksWithRelations.map((bookData) => Book.fromJson(bookData)).toList();
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
    final result =
        db.select('SELECT COUNT(*) FROM link WHERE sourceBookId = ?', [bookId]);
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
    final result =
        db.select('SELECT COUNT(*) FROM link WHERE targetBookId = ?', [bookId]);
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

  /// Closes the database connection.
  /// Should be called when the repository is no longer needed.
  Future<void> close() async {
    _database.close();
  }

  /// Executes a raw SQL query.
  /// This is useful for operations that are not covered by the generated queries,
  /// such as enabling or disabling foreign key constraints.
  ///
  /// @param sql The SQL query to execute
  Future<void> _executeRawQuery(String sql) async {
    final db = await _database.database;
    db.execute(sql);
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

  /// Checks if a book with the given title, category and file type already exists in the database.
  /// Returns the book if found, null otherwise.
  Future<Book?> checkBookExistsInCategoryWithFileType(
      String title, int categoryId, String fileType) async {
    //_logger.fine('Checking if book exists in category with file type: $title (categoryId: $categoryId, fileType: $fileType)');
    return await _database.bookDao
        .getBookByTitleCategoryAndFileType(title, categoryId, fileType);
  }

  /// Deletes a book and all its related data (lines, TOC entries, links, etc.)
  /// This is useful when replacing an existing book.
  Future<void> deleteBookCompletely(int bookId) async {
    _invalidateTocCache(bookId: bookId);
    _logger.info('Deleting book completely: $bookId');

    final db = await _database.database;
    withTransaction(db, () {
      // Delete links where this book is source or target
      db.execute('DELETE FROM link WHERE sourceBookId = ? OR targetBookId = ?',
          [bookId, bookId]);

      // Delete book_has_links
      db.execute('DELETE FROM book_has_links WHERE bookId = ?', [bookId]);

      // Delete line_toc mappings for lines of this book
      db.execute(
          'DELETE FROM line_toc WHERE lineId IN (SELECT id FROM line WHERE bookId = ?)',
          [bookId]);

      // Delete line_toc mappings for tocEntries of this book
      db.execute(
          'DELETE FROM line_toc WHERE tocEntryId IN (SELECT id FROM tocEntry WHERE bookId = ?)',
          [bookId]);

      // Delete TOC entries
      db.execute('DELETE FROM tocEntry WHERE bookId = ?', [bookId]);

      // Delete lines
      db.execute('DELETE FROM line WHERE bookId = ?', [bookId]);

      // Delete junction tables
      db.execute('DELETE FROM book_author WHERE bookId = ?', [bookId]);
      db.execute('DELETE FROM book_topic WHERE bookId = ?', [bookId]);
      db.execute('DELETE FROM book_pub_place WHERE bookId = ?', [bookId]);
      db.execute('DELETE FROM book_pub_date WHERE bookId = ?', [bookId]);

      // Finally delete the book itself
      db.execute('DELETE FROM book WHERE id = ?', [bookId]);
    });

    _logger.info('Book $bookId deleted completely');
  }

  /// Deletes tocText entries that are no longer referenced by any tocEntry or alt_toc_entry.
  /// Should be called after bulk deletions of books/categories.
  Future<void> deleteOrphanedTocTexts() async {
    final db = await _database.database;
    db.execute(
        'DELETE FROM tocText WHERE id NOT IN (SELECT DISTINCT textId FROM tocEntry) AND id NOT IN (SELECT DISTINCT textId FROM alt_toc_entry)');
    final count = db.updatedRows;
    _logger.info('Deleted $count orphaned tocText entries');
  }

  /// Updates tocEntry.lineId for all entries in a book by matching lineIndex.
  /// Should be called after lines and tocEntries are inserted for a book (insertContent=true).
  Future<void> updateTocEntryLineIdsByLineIndex(int bookId) async {
    _invalidateTocCache(bookId: bookId);
    final db = await _database.database;
    db.execute('''
      UPDATE tocEntry SET lineId = (
        SELECT l.id FROM line l
        WHERE l.bookId = tocEntry.bookId AND l.lineIndex = tocEntry.lineIndex
      ) WHERE bookId = ? AND lineIndex IS NOT NULL
    ''', [bookId]);
    final count = db.updatedRows;
    _logger.info('Updated lineId for $count tocEntry rows in book $bookId');
  }

  /// Deletes orphaned line_toc rows (where lineId or tocEntryId no longer exist in their tables).
  /// Should be called after bulk deletions of books/categories.
  Future<void> deleteOrphanedLineToc() async {
    final db = await _database.database;
    db.execute('''
      DELETE FROM line_toc
      WHERE lineId NOT IN (SELECT id FROM line)
         OR tocEntryId NOT IN (SELECT id FROM tocEntry)
    ''');
    final count = db.updatedRows;
    _logger.info('Deleted $count orphaned line_toc entries');
  }

  /// Deletes a category from the database.
  /// Note: Make sure to delete all books and subcategories first!
  Future<void> deleteCategory(int categoryId) async {
    _logger.info('Deleting category: $categoryId');

    // Delete from category_closure table first to maintain hierarchy integrity
    final db = await _database.database;
    db.execute(
        'DELETE FROM category_closure WHERE ancestorId = ? OR descendantId = ?',
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

/// מידע על הדור של ספר
///
/// @property generationId מזהה הדור
/// @property generationName שם הדור (תורה שבכתב, חז"ל, ראשונים, אחרונים, מחברי זמננו)
class BookGenerationInfo {
  final int generationId;
  final String generationName;

  const BookGenerationInfo({
    required this.generationId,
    required this.generationName,
  });

  @override
  String toString() =>
      'BookGenerationInfo(id: $generationId, name: $generationName)';
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
    final result = db.select('''
      SELECT 
        (SELECT COALESCE(MAX(id), 0) FROM book) as maxBookId,
        (SELECT COALESCE(MAX(id), 0) FROM line) as maxLineId,
        (SELECT COALESCE(MAX(id), 0) FROM tocEntry) as maxTocId,
        (SELECT COALESCE(MAX(id), 0) FROM category) as maxCatId
    ''').toMapList();

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
    db.execute('DELETE FROM line WHERE bookId = ?', [bookId]);
  }

  /// Deletes all TOC entries for a specific book.
  /// Used when updating book content.
  Future<void> deleteBookTocEntries(int bookId) async {
    _invalidateTocCache(bookId: bookId);
    final db = await database.database;
    db.execute('DELETE FROM tocEntry WHERE bookId = ?', [bookId]);
  }

  /// Clears book content (lines and TOC entries) for updating.
  /// Preserves book metadata.
  Future<void> clearBookContent(int bookId) async {
    // Clean mapping rows explicitly to avoid orphans when foreign_keys PRAGMA is off.
    final db = await database.database;
    db.execute(
      'DELETE FROM line_toc WHERE lineId IN (SELECT id FROM line WHERE bookId = ?)',
      [bookId],
    );
    db.execute(
      'DELETE FROM line_toc WHERE tocEntryId IN (SELECT id FROM tocEntry WHERE bookId = ?)',
      [bookId],
    );

    await deleteBookLines(bookId);
    await deleteBookTocEntries(bookId);
  }
}

/// Extension methods for book acronyms
extension BookAcronymRepository on SeforimRepository {
  /// Searches for books by acronym term.
  Future<List<int>> searchBooksByAcronym(String term, {int? limit}) async {
    return await _database.bookAcronymDao
        .searchBooksByAcronym(term, limit: limit);
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
    final titleResults = db.select('''
        SELECT b.id, b.title, b.categoryId, b.filePath, b.fileType
        FROM book b
        WHERE LOWER(b.title) LIKE ?
          AND COALESCE(b.fileType, '') NOT IN ('link', 'url')
        ORDER BY 
          CASE WHEN LOWER(b.title) = ? THEN 0
               WHEN LOWER(b.title) LIKE ? THEN 1
               ELSE 2 END,
          b.orderIndex
        LIMIT ?
      ''', [
      queryPattern,
      normalizedQuery,
      '$normalizedQuery%',
      limit
    ]).toMapList();

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
    final acronymResults = db.select('''
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
      ''', [
      queryPattern,
      normalizedQuery,
      '$normalizedQuery%',
      limit
    ]).toMapList();

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
  ///
  /// בנייה ראשונית של ערכי ה-TOC (SQL + הרכבת reference + נורמליזציה)
  /// נשמרת במטמון פר-ספר. שיחות חוזרות (אופייניות בעת הקלדה הדרגתית של
  /// המשתמש) מסננות in-memory בלבד.
  Future<List<Map<String, dynamic>>> getTocEntriesForReference(
      int bookId, String bookTitle,
      {List<String>? queryTokens}) async {
    final cache = await _buildTocCacheForBook(bookId, bookTitle);

    if (cache.all.isEmpty || queryTokens == null || queryTokens.isEmpty) {
      return cache.all.map((e) => e.toMap()).toList();
    }

    // חיפוש היררכי: יורד רמה-אחר-רמה עם תמיכה בטרנספוזיציית אותיות.
    final matches = _searchTocHierarchically(cache, queryTokens);
    if (matches.isNotEmpty) {
      return matches.map((e) => e.toMap()).toList();
    }

    // Fallback שטוח — רק כשההיררכי לא מצא דבר **ולספר אין מבנה alt_toc**.
    // מאפשר לטוקן בודד להגיע לכותרת עמוקה (כמו "דף לו" תחת ספר→פרשה→דף
    // ב"הזוהר המתורגם") בלי לדרוש את שמות הביניים. ספרים עם alt_toc ("ספר
    // הזהר") כבר חושפים דפים שם — להם נשמר החיפוש ההיררכי בלבד, כדי לא
    // להציף בכותרות-משנה לא רלוונטיות ("פרק לו"/"סימן לו").
    final altCache = await _buildAltTocCacheForBook(bookId, bookTitle);
    if (altCache.all.isNotEmpty) return const [];

    return _searchTocFlat(cache, queryTokens).map((e) => e.toMap()).toList();
  }

  /// מחזיר את שורות המפרשים הגולמיות עבור תוצאת איתור מקורות, מוכנות לעיבוד
  /// ב-`FindRefRepository` (dedupe, מיון דורות). כל row כולל `targetBookTitle`,
  /// `targetBookId` ו-`targetLineIndex` (המיקום המקביל הראשון בספר המפרש).
  ///
  /// אסטרטגיית הטווח:
  ///   - תוצאת כותרת/דף ([sourceLineId] > 0): כל המפרשים מ-[startLineIndex]
  ///     ועד הכותרת הבאה ברמה <= [level] (לא כולל) — כלומר כל תוכן הקטע,
  ///     כולל תת-כותרות (רמה עמוקה יותר), ללא קישורי הקטע הבא.
  ///   - תוצאת ספר ([sourceLineId] == 0): אם לספר יש כותרות פנימיות (level >= 2)
  ///     מוחזר ריק — על המשתמש לבחור כותרת ספציפית. אם אין כותרות פנימיות
  ///     מוחזרים כל מפרשי הספר (טווח מלא), כל אחד במיקומו הראשון.
  ///
  /// [isAltToc] בוחר את מבנה הכותרות שלפיו נחשב הגבול (TOC רגיל מול AltToc).
  Future<List<Map<String, dynamic>>> getCommentatorsForReference({
    required int bookId,
    required String bookTitle,
    required int sourceLineId,
    required int startLineIndex,
    required int level,
    bool isAltToc = false,
  }) async {
    // גבול עליון "אינסופי" לטווח — אף ספר לא מתקרב ל-2 מיליון שורות.
    const maxLineIndex = 0x7fffffff;
    final int startIdx;
    final int endIdx;

    if (sourceLineId > 0) {
      // קטע ספציפי: מהכותרת ועד הכותרת הבאה ברמה <= level.
      final cache = isAltToc
          ? await _buildAltTocCacheForBook(bookId, bookTitle)
          : await _buildTocCacheForBook(bookId, bookTitle);
      startIdx = startLineIndex;
      endIdx = _nextHeadingLineIndex(cache, startLineIndex, level);
    } else {
      // תוצאת ספר: אם יש כותרות פנימיות — אין קטע נבחר, מחזירים ריק.
      // אחרת — כל הספר (ספר ללא TOC פנימי, כל מפרשיו רלוונטיים).
      final cache = await _buildTocCacheForBook(bookId, bookTitle);
      final hasInnerToc = cache.all.any((e) => e.level >= 2);
      if (hasInnerToc) return const [];
      startIdx = 0;
      endIdx = maxLineIndex;
    }

    return _database.linkDao
        .selectCommentatorsByLineRange(bookId, startIdx, endIdx);
  }

  /// מחזיר את ה-`segment` (=lineIndex) של ערך ה-TOC הבא **ברמה <= [level]**
  /// אחרי [afterLineIndex], או 0x7fffffff אם אין כזה (=עד סוף הספר).
  /// הכותרת הבאה באותה רמה או רדודה יותר חוסמת את הקטע, בעוד תת-כותרות
  /// (רמה עמוקה יותר) נכללות בו.
  int _nextHeadingLineIndex(
      _TocBookCache cache, int afterLineIndex, int level) {
    var end = 0x7fffffff;
    for (final e in cache.all) {
      if (e.level >= 1 &&
          e.level <= level &&
          e.segment > afterLineIndex &&
          e.segment < end) {
        end = e.segment;
      }
    }
    return end;
  }

  /// בונה (פעם אחת לכל [bookId]) את רשימת ערכי ה-TOC המעובדים.
  /// כל ערך כולל את ה-reference המלא (כולל נתיב אבות שלם) ואת הטוקנים המנורמלים
  /// שלו מראש. מבנה היררכי (childrenByParentId) מאפשר חיפוש רמה-אחר-רמה.
  Future<_TocBookCache> _buildTocCacheForBook(
      int bookId, String bookTitle) async {
    final cached = _tocCache[bookId];
    if (cached != null) return cached;

    final db = await _database.database;

    final tocEntries = db.select('''
        SELECT t.id, tt.text, t.level,
               COALESCE(l.lineIndex, t.lineId) as lineIndex,
               COALESCE(t.lineId, 0) as dbLineId,
               t.parentId
        FROM tocEntry t
        JOIN tocText tt ON t.textId = tt.id
        LEFT JOIN line l ON t.lineId = l.id
        WHERE t.bookId = ?
        ORDER BY COALESCE(l.lineIndex, t.lineId), t.level
      ''', [bookId]).toMapList();

    if (tocEntries.isEmpty) {
      _tocCache[bookId] = _TocBookCache.empty;
      return _TocBookCache.empty;
    }

    // מפות עזר לבניית נתיב אבות ומבנה היררכי.
    final entryTexts = <int, String>{};
    final entryLevels = <int, int>{};
    final entryParentIds = <int, int?>{};
    for (final e in tocEntries) {
      final id = e['id'] as int;
      entryTexts[id] = e['text'] as String;
      entryLevels[id] = e['level'] as int;
      entryParentIds[id] = e['parentId'] as int?;
    }

    // בונה נתיב reference מלא ע"י מעבר רקורסיבי על שרשרת האבות.
    String buildPath(int? id) {
      if (id == null) return bookTitle;
      final lvl = entryLevels[id];
      if (lvl == null || lvl == 0) return bookTitle;
      return '${buildPath(entryParentIds[id])} ${entryTexts[id]!}';
    }

    final built = <_CachedTocEntry>[];
    final childrenByParentId = <int, List<_CachedTocEntry>>{};
    final rootEntries = <_CachedTocEntry>[];

    for (final e in tocEntries) {
      final id = e['id'] as int;
      final level = e['level'] as int;
      if (level == 0) continue;

      final text = e['text'] as String;
      final lineIndex = e['lineIndex'] as int? ?? 0;
      final dbLineId = e['dbLineId'] as int? ?? 0;
      final parentId = e['parentId'] as int?;

      final ancestorPath = buildPath(parentId);
      final fullRef = text.isNotEmpty ? '$ancestorPath $text' : ancestorPath;

      final ownTokens = normalizeForFindRefMatch(text)
          .split(' ')
          .where((t) => t.isNotEmpty)
          .toList(growable: false);

      final entry = _CachedTocEntry(
        id: id,
        reference: fullRef,
        segment: lineIndex,
        level: level,
        dbLineId: dbLineId,
        ownTokens: ownTokens,
      );

      built.add(entry);

      final parentLevel = parentId == null ? null : entryLevels[parentId];
      final isRoot =
          parentId == null || parentLevel == null || parentLevel == 0;
      if (isRoot) {
        rootEntries.add(entry);
      } else {
        childrenByParentId.putIfAbsent(parentId, () => []).add(entry);
      }
    }

    // מיון לפי segment — כך הסינון העוקב שומר על הסדר.
    built.sort((a, b) => a.segment.compareTo(b.segment));
    rootEntries.sort((a, b) => a.segment.compareTo(b.segment));
    for (final children in childrenByParentId.values) {
      children.sort((a, b) => a.segment.compareTo(b.segment));
    }

    final cache = _TocBookCache(
      all: built,
      rootEntries: rootEntries,
      childrenByParentId: childrenByParentId,
    );
    _tocCache[bookId] = cache;
    return cache;
  }

  /// חיפוש היררכי ב-TOC: יורד רמה-אחר-רמה עבור כל טוקן.
  /// תומך בטרנספוזיציה של שתי אותיות עבריות ("טל" ↔ "לט").
  List<_CachedTocEntry> _searchTocHierarchically(
      _TocBookCache cache, List<String> tokens) {
    var searchScope = cache.rootEntries;
    var currentMatches = <_CachedTocEntry>[];

    for (final token in tokens) {
      final alts = _hebrewTokenAlternatives(token);

      List<_CachedTocEntry> found = const [];
      for (final alt in alts) {
        final hits =
            searchScope.where((e) => e.ownTokens.contains(alt)).toList();
        if (hits.isNotEmpty) {
          found = hits;
          break;
        }
      }

      if (found.isEmpty) break;

      // שומר רק את הרמה הרדודה ביותר בין ההתאמות.
      var minLevel = found.first.level;
      for (final e in found) {
        if (e.level < minLevel) minLevel = e.level;
      }
      currentMatches = found.where((e) => e.level == minLevel).toList();

      // מכין את מרחב החיפוש לטוקן הבא:
      // אם יש ילדים ישירים — יורדים אליהם (+ כל צאצאיהם).
      // אם אין ילדים — נשארים ב-currentMatches לסינון נוסף באותה רמה.
      final directChildren = currentMatches
          .expand((m) =>
              cache.childrenByParentId[m.id] ?? const <_CachedTocEntry>[])
          .toList();

      if (directChildren.isNotEmpty) {
        // כשיש מרובה התאמות (למשל כל הפרקים אחרי "פרק") — כולל את currentMatches
        // בסקופ הבא כדי שהטוקן הבא יוכל לחדד **באותה רמה** (למשל "כ" → "פרק כ").
        // כשיש התאמה יחידה — יורדים לילדים בלבד, כי הטוקן הבא נועד להעמיק.
        final includeCurrentLevel = currentMatches.length > 1;
        searchScope = [
          if (includeCurrentLevel) ...currentMatches,
          ...directChildren,
          ...directChildren.expand((c) => _getAllDescendants(cache, c)),
        ];
      } else {
        searchScope = currentMatches;
      }
    }

    return currentMatches;
  }

  /// מחזיר את כל הצאצאים (ילדים, נכדים, ...) של [entry].
  Iterable<_CachedTocEntry> _getAllDescendants(
      _TocBookCache cache, _CachedTocEntry entry) sync* {
    final children =
        cache.childrenByParentId[entry.id] ?? const <_CachedTocEntry>[];
    for (final child in children) {
      yield child;
      yield* _getAllDescendants(cache, child);
    }
  }

  /// חיפוש **שטוח** על ה-TOC הרגיל — מבנה זהה ל-[_searchAltTocFlat], אך מחשב
  /// את טוקני הנתיב מתוך ה-reference (ה-TOC הרגיל אינו שומר `pathTokens`).
  /// משמש כ-fallback בלבד (ראה [getTocEntriesForReference]); ההגנה מפני הצפה
  /// זהה: הטוקן האחרון חייב להופיע בעלה עצמו, וכל הטוקנים בנתיב המלא.
  List<_CachedTocEntry> _searchTocFlat(
      _TocBookCache cache, List<String> tokens) {
    if (tokens.isEmpty) return const [];

    final lastAlts = _hebrewTokenAlternatives(tokens.last);

    return cache.all.where((e) {
      if (!lastAlts.any((a) => e.ownTokens.contains(a))) return false;
      final pathTokens = normalizeForFindRefMatch(e.reference)
          .split(' ')
          .where((t) => t.isNotEmpty)
          .toList(growable: false);
      for (final token in tokens) {
        final alts = _hebrewTokenAlternatives(token);
        if (!alts.any((a) => pathTokens.contains(a))) return false;
      }
      return true;
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AltToc (כותרות-משנה) — חיפוש במבנים חלופיים (עליות, פרשות, וכד')
  // ─────────────────────────────────────────────────────────────────────────

  /// מחפש בכותרות-משנה (AltToc) של [bookId] לפי [queryTokens].
  ///
  /// מחזיר ערכים בפורמט זהה ל-[getTocEntriesForReference]:
  /// `{'reference': ..., 'segment': ..., 'level': ...}`.
  /// אם אין מבנים חלופיים לספר, מחזיר רשימה ריקה.
  Future<List<Map<String, dynamic>>> getAltTocEntriesForReference(
      int bookId, String bookTitle,
      {List<String>? queryTokens}) async {
    if (queryTokens == null || queryTokens.isEmpty) return const [];

    final cache = await _buildAltTocCacheForBook(bookId, bookTitle);
    if (cache.all.isEmpty) return const [];

    final matches = _searchAltTocFlat(cache, queryTokens);
    return matches.map((e) => e.toMap()).toList();
  }

  /// חיפוש **שטוח** בכותרות-המשנה: מחזיר כל ערך שכל טוקני השאילתה מופיעים
  /// בנתיב המלא שלו, **והטוקן האחרון** מופיע בטקסט של הערך עצמו (העלה).
  ///
  /// בניגוד לחיפוש ההיררכי (שדורש שהטוקן הראשון יתאים לשורש), כאן המשתמש יכול
  /// לדלג על שמות-ביניים: ב"טור" כותרות-המשנה ("הלכות הלואה") יושבות תחת שם
  /// החלק ("חושן משפט"), שלרוב נבלע בזיהוי שם הספר — כך שחיפוש היררכי משורש
  /// החלק לא היה מגיע אליהן. תנאי "הטוקן האחרון בעלה" מונע הצפה: שאילתה כמו
  /// "חושן" מחזירה רק את החלק "חושן משפט", לא את כל 133 ההלכות שתחתיו.
  ///
  /// תומך בטרנספוזיציית אותיות עבריות ("טל" ↔ "לט") כמו החיפוש ההיררכי.
  List<_CachedTocEntry> _searchAltTocFlat(
      _TocBookCache cache, List<String> tokens) {
    if (tokens.isEmpty) return const [];

    final lastAlts = _hebrewTokenAlternatives(tokens.last);

    return cache.all.where((e) {
      // אנטי-הצפה: הטוקן האחרון חייב להתאים לטקסט של הערך עצמו (העלה).
      if (!lastAlts.any((a) => e.ownTokens.contains(a))) return false;
      // כל טוקני השאילתה חייבים להופיע בנתיב המלא (בכל סדר).
      for (final token in tokens) {
        final alts = _hebrewTokenAlternatives(token);
        if (!alts.any((a) => e.pathTokens.contains(a))) return false;
      }
      return true;
    }).toList();
  }

  /// בונה (פעם אחת לכל [bookId]) את קאש ה-AltToc.
  /// מאחד את כל המבנים החלופיים (structureId) של הספר לתוך קאש יחיד.
  /// כל ערך כולל את `pathTokens` (טוקני הנתיב המלא) עבור החיפוש השטוח
  /// ב-[_searchAltTocFlat].
  Future<_TocBookCache> _buildAltTocCacheForBook(
      int bookId, String bookTitle) async {
    final cached = _altTocCache[bookId];
    if (cached != null) return cached;

    final db = await _database.database;

    final entries = db.select('''
        SELECT e.id, t.text, e.level,
               COALESCE(l.lineIndex, 0) as lineIndex,
               COALESCE(e.lineId, 0) as dbLineId,
               e.parentId
        FROM alt_toc_entry e
        JOIN tocText t ON e.textId = t.id
        LEFT JOIN line l ON e.lineId = l.id
        WHERE e.structureId IN (
            SELECT id FROM alt_toc_structure WHERE bookId = ?
        )
        ORDER BY COALESCE(l.lineIndex, 0), e.level
      ''', [bookId]).toMapList();

    if (entries.isEmpty) {
      _altTocCache[bookId] = _TocBookCache.empty;
      return _TocBookCache.empty;
    }

    final entryTexts = <int, String>{};
    final entryParentIds = <int, int?>{};
    final entryOwnTokens = <int, List<String>>{};
    for (final e in entries) {
      final id = e['id'] as int;
      entryTexts[id] = e['text'] as String;
      entryParentIds[id] = e['parentId'] as int?;
      entryOwnTokens[id] = normalizeForFindRefMatch(e['text'] as String)
          .split(' ')
          .where((t) => t.isNotEmpty)
          .toList(growable: false);
    }

    // בונה נתיב reference **ללא** שם הספר — AltToc references הם יחסיים לספר.
    // רמה 1: "פרשת לך לך"  (ולא "בראשית פרשת לך לך")
    // רמה 2: "פרשת לך לך עליה ו"
    String buildPath(int? id) {
      if (id == null) return ''; // שורש ריק — ללא שם הספר
      final parentId = entryParentIds[id];
      final parent = buildPath(parentId);
      return parent.isEmpty ? entryTexts[id]! : '$parent ${entryTexts[id]!}';
    }

    // טוקני הנתיב המלא (שורש→ערך) — לחיפוש השטוח של AltToc.
    List<String> buildPathTokens(int? id) {
      if (id == null) return const [];
      return [...buildPathTokens(entryParentIds[id]), ...?entryOwnTokens[id]];
    }

    final built = <_CachedTocEntry>[];
    final childrenByParentId = <int, List<_CachedTocEntry>>{};
    final rootEntries = <_CachedTocEntry>[];

    for (final e in entries) {
      final id = e['id'] as int;
      final level = e['level'] as int;
      final text = e['text'] as String;
      final lineIndex = e['lineIndex'] as int? ?? 0;
      final dbLineId = e['dbLineId'] as int? ?? 0;
      final parentId = e['parentId'] as int?;

      final ancestorPath = buildPath(parentId);
      final fullRef = text.isNotEmpty
          ? (ancestorPath.isEmpty ? text : '$ancestorPath $text')
          : ancestorPath;

      final entry = _CachedTocEntry(
        id: id,
        reference: fullRef,
        segment: lineIndex,
        level: level,
        dbLineId: dbLineId,
        ownTokens: entryOwnTokens[id] ?? const [],
        pathTokens: buildPathTokens(id),
      );

      built.add(entry);

      if (parentId == null) {
        rootEntries.add(entry);
      } else {
        childrenByParentId.putIfAbsent(parentId, () => []).add(entry);
      }
    }

    built.sort((a, b) => a.segment.compareTo(b.segment));
    rootEntries.sort((a, b) => a.segment.compareTo(b.segment));
    for (final children in childrenByParentId.values) {
      children.sort((a, b) => a.segment.compareTo(b.segment));
    }

    final cache = _TocBookCache(
      all: built,
      rootEntries: rootEntries,
      childrenByParentId: childrenByParentId,
    );
    _altTocCache[bookId] = cache;
    return cache;
  }

  /// מחזיר את כל הספרים שיש להם לפחות מבנה AltToc אחד.
  /// משמש ל-fallback גלובלי של חיפוש כותרות-משנה ללא שם ספר בשאילתה.
  Future<List<({int bookId, String bookTitle})>> getAllBooksWithAltToc() async {
    final db = await _database.database;
    final rows = db.select(
      'SELECT DISTINCT s.bookId, b.title '
      'FROM alt_toc_structure s JOIN book b ON b.id = s.bookId',
      [],
    ).toMapList();
    return rows
        .map((r) => (
              bookId: r['bookId'] as int,
              bookTitle: r['title'] as String,
            ))
        .toList();
  }

  /// מחזיר רשימה שטוחה של *כל* ערכי ה-AltToc על פני כל הספרים, עם הנתיב
  /// המלא לכל ערך — בשאילתת SQL אחת. נועד ל-fallback הגלובלי של FindRef:
  /// במקום 339 שאילתות סדרתיות (אחת לכל ספר), הוא מקבל קאש שטוח בודד
  /// ושאר העבודה היא פילטר O(N) ב-Dart.
  ///
  /// כל map בתוצאה כולל את המפתחות:
  /// `bookId`, `bookTitle`, `bookOrderIndex`, `reference` (נתיב מלא יחסי
  /// לספר, ללא שם הספר), `segment` (=lineIndex), `level`, `dbLineId`.
  Future<List<Map<String, dynamic>>> getAllAltTocFlatEntries() async {
    final db = await _database.database;
    final rows = db.select('''
      SELECT s.bookId AS bookId,
             b.title AS bookTitle,
             b.orderIndex AS bookOrderIndex,
             e.id AS entryId,
             t.text AS text,
             e.level AS level,
             e.parentId AS parentId,
             COALESCE(l.lineIndex, 0) AS lineIndex,
             COALESCE(e.lineId, 0) AS dbLineId
      FROM alt_toc_entry e
      JOIN alt_toc_structure s ON e.structureId = s.id
      JOIN book b ON b.id = s.bookId
      JOIN tocText t ON e.textId = t.id
      LEFT JOIN line l ON e.lineId = l.id
    ''').toMapList();

    if (rows.isEmpty) return const [];

    // נבנה memoized buildPath עבור parentId → reference. ה-`entryId` יחיד
    // ברמת ה-DB, ולכן מספיק קאש גלובלי אחד מעבר לכל הספרים.
    final entryTexts = <int, String>{};
    final entryParents = <int, int?>{};
    for (final r in rows) {
      final id = r['entryId'] as int;
      entryTexts[id] = r['text'] as String;
      entryParents[id] = r['parentId'] as int?;
    }

    final pathCache = <int, String>{};
    String buildPath(int? id) {
      if (id == null) return '';
      final cached = pathCache[id];
      if (cached != null) return cached;
      final parent = buildPath(entryParents[id]);
      final text = entryTexts[id]!;
      final result = parent.isEmpty ? text : '$parent $text';
      pathCache[id] = result;
      return result;
    }

    final result = <Map<String, dynamic>>[];
    for (final r in rows) {
      final text = r['text'] as String;
      final ancestorPath = buildPath(r['parentId'] as int?);
      final fullRef = text.isEmpty
          ? ancestorPath
          : (ancestorPath.isEmpty ? text : '$ancestorPath $text');
      result.add({
        'bookId': r['bookId'] as int,
        'bookTitle': r['bookTitle'] as String,
        'bookOrderIndex': (r['bookOrderIndex'] as num).toDouble(),
        'reference': fullRef,
        'segment': r['lineIndex'] as int,
        'level': r['level'] as int,
        'dbLineId': r['dbLineId'] as int,
      });
    }
    return result;
  }

  /// מחזיר טוקן + גרסת טרנספוזיציה לאותיות עבריות דו-תווניות.
  /// לדוגמה: "טל" → ["טל", "לט"] (שתי שיטות מניין עבריות ל-39).
  List<String> _hebrewTokenAlternatives(String token) {
    if (token.length == 2) {
      final c0 = token.codeUnitAt(0);
      final c1 = token.codeUnitAt(1);
      // אותיות עבריות U+05D0–U+05EA
      if (c0 >= 0x05D0 &&
          c0 <= 0x05EA &&
          c1 >= 0x05D0 &&
          c1 <= 0x05EA &&
          c0 != c1) {
        return [token, '${token[1]}${token[0]}'];
      }
    }
    return [token];
  }
}

/// ערך TOC מעובד שנשמר בקאש בזיכרון של [SeforimRepository].
/// `tokens` הם תוצאת [normalizeForFindRefMatch] על `reference`, מפוצלת לטוקנים.
class _CachedTocEntry {
  final int id;
  final String reference;
  final int segment;
  final int level;

  /// מזהה השורה הגלובלי ב-`line` table (או 0 אם לא ידוע).
  /// משמש לשאילתות segment-level כמו `link.sourceLineId`.
  final int dbLineId;

  /// טוקנים של הטקסט של ערך זה בלבד (ללא אבות) — לשימוש בחיפוש היררכי.
  final List<String> ownTokens;

  /// טוקנים של הנתיב המלא משורש העץ עד הערך הזה (כולל) — לשימוש בחיפוש
  /// השטוח של AltToc. ריק כברירת מחדל (TOC רגיל משתמש בחיפוש היררכי בלבד).
  final List<String> pathTokens;

  const _CachedTocEntry({
    required this.id,
    required this.reference,
    required this.segment,
    required this.level,
    required this.dbLineId,
    required this.ownTokens,
    this.pathTokens = const [],
  });

  Map<String, dynamic> toMap() => {
        'reference': reference,
        'segment': segment,
        'level': level,
        'dbLineId': dbLineId,
      };
}

/// קאש TOC לספר יחיד: רשימה שטוחה + מבנה היררכי לחיפוש.
class _TocBookCache {
  /// כל ערכי ה-TOC (ממוינים לפי segment).
  final List<_CachedTocEntry> all;

  /// ערכי שורש — ילדים ישירים של entry ברמה 0 (שם הספר).
  final List<_CachedTocEntry> rootEntries;

  /// מיפוי id → ילדים ישירים (ממוינים לפי segment).
  final Map<int, List<_CachedTocEntry>> childrenByParentId;

  static const empty = _TocBookCache(
    all: [],
    rootEntries: [],
    childrenByParentId: {},
  );

  const _TocBookCache({
    required this.all,
    required this.rootEntries,
    required this.childrenByParentId,
  });
}
