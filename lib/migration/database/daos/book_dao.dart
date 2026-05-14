import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../../models/book.dart';
import '../sql/sqlite3_utils.dart';
import '../sql/query_loader.dart';
import 'database.dart';

class BookDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  BookDao(this._db) {
    _queries = QueryLoader.loadQueries('BookQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<List<Book>> getAllBooks() async {
    final db = await database;
    return db
        .select(_queries['selectAll']!)
        .toMapList()
        .map((row) => Book.fromJson(row))
        .toList();
  }

  /// Gets minimal book data, optionally within an ongoing transaction.
  /// Used by [DatabaseLibraryProvider] to load books and categories atomically.
  /// Must be called synchronously inside a [withTransaction] block.
  List<Map<String, dynamic>> getAllBooksMinimal(sqlite3.Database db) {
    return db.select('''
      SELECT id, title, categoryId, orderIndex, fileType, filePath,
             heShortDesc
      FROM book
      WHERE COALESCE(fileType, '') NOT IN ('link', 'url')
      ORDER BY orderIndex, title
    ''').toMapList();
  }

  /// Loads authors for all local books in one query to keep catalog build fast.
  Map<int, String> getBookAuthorsMap(sqlite3.Database db) {
    final rows = db.select('''
      SELECT author_rows.bookId,
             GROUP_CONCAT(author_rows.name, ', ') AS author
      FROM (
        SELECT ba.bookId AS bookId,
               a.name AS name
        FROM book_author ba
        JOIN author a ON a.id = ba.authorId
        JOIN book b ON b.id = ba.bookId
        WHERE COALESCE(b.fileType, '') NOT IN ('link', 'url')
        ORDER BY ba.bookId, a.name
      ) AS author_rows
      GROUP BY author_rows.bookId
    ''').toMapList();

    return {
      for (final row in rows)
        if ((row['author'] as String?)?.isNotEmpty == true)
          row['bookId'] as int: row['author'] as String,
    };
  }

  /// Gets all local books (excluding external catalog books).
  Future<List<Book>> getAllLocalBooks() async {
    final db = await database;
    return db
        .select(_queries['selectAllIgnoreExternalCatalogs']!)
        .toMapList()
        .map((row) => Book.fromJson(row))
        .toList();
  }

  /// Gets all books with their relations (authors, topics, pubPlaces, pubDates) in a single optimized query.
  /// This is much faster than calling getAllBooks() and then loading relations separately.
  Future<List<Map<String, dynamic>>> getAllBooksWithRelations() async {
    final db = await database;

    // Always exclude external catalog books (fileType='link') - they are in a separate DB
    final books =
        db.select(_queries['selectAllIgnoreExternalCatalogs']!).toMapList();

    if (books.isEmpty) return [];

    // Get all book IDs
    final bookIds = books.map((b) => b['id'] as int).toList();
    final bookIdsStr = bookIds.join(',');

    final authorsData = db.select('''
        SELECT ba.bookId, a.id, a.name, a.generationId
        FROM book_author ba
        JOIN author a ON ba.authorId = a.id
        WHERE ba.bookId IN ($bookIdsStr)
        ORDER BY ba.bookId
      ''').toMapList();
    final topicsData = db.select('''
        SELECT bt.bookId, t.id, t.name
        FROM book_topic bt
        JOIN topic t ON bt.topicId = t.id
        WHERE bt.bookId IN ($bookIdsStr)
        ORDER BY bt.bookId
      ''').toMapList();
    final pubPlacesData = db.select('''
        SELECT bpp.bookId, pp.id, pp.name
        FROM book_pub_place bpp
        JOIN pub_place pp ON bpp.pubPlaceId = pp.id
        WHERE bpp.bookId IN ($bookIdsStr)
        ORDER BY bpp.bookId
      ''').toMapList();
    final pubDatesData = db.select('''
        SELECT bpd.bookId, pd.id, pd.date
        FROM book_pub_date bpd
        JOIN pub_date pd ON bpd.pubDateId = pd.id
        WHERE bpd.bookId IN ($bookIdsStr)
        ORDER BY bpd.bookId
      ''').toMapList();

    // Group relations by bookId
    final authorsByBook = <int, List<Map<String, dynamic>>>{};
    final topicsByBook = <int, List<Map<String, dynamic>>>{};
    final pubPlacesByBook = <int, List<Map<String, dynamic>>>{};
    final pubDatesByBook = <int, List<Map<String, dynamic>>>{};

    for (final row in authorsData) {
      final bookId = row['bookId'] as int;
      authorsByBook.putIfAbsent(bookId, () => []);
      authorsByBook[bookId]!.add({
        'id': row['id'],
        'name': row['name'],
        'generationId': row['generationId'],
      });
    }

    for (final row in topicsData) {
      final bookId = row['bookId'] as int;
      topicsByBook.putIfAbsent(bookId, () => []);
      topicsByBook[bookId]!.add({'id': row['id'], 'name': row['name']});
    }

    for (final row in pubPlacesData) {
      final bookId = row['bookId'] as int;
      pubPlacesByBook.putIfAbsent(bookId, () => []);
      pubPlacesByBook[bookId]!.add({'id': row['id'], 'name': row['name']});
    }

    for (final row in pubDatesData) {
      final bookId = row['bookId'] as int;
      pubDatesByBook.putIfAbsent(bookId, () => []);
      pubDatesByBook[bookId]!.add({'id': row['id'], 'date': row['date']});
    }

    // Combine books with their relations
    return books.map((book) {
      final bookId = book['id'] as int;
      return {
        ...book,
        'authors': authorsByBook[bookId] ?? [],
        'topics': topicsByBook[bookId] ?? [],
        'pubPlaces': pubPlacesByBook[bookId] ?? [],
        'pubDates': pubDatesByBook[bookId] ?? [],
      };
    }).toList();
  }

  Future<Book?> getBookById(int id) async {
    final db = await database;
    final result = db.select(_queries['selectById']!, [id]).toMapList();
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  Future<List<Book>> getBooksByCategory(int categoryId) async {
    final db = await database;
    return db
        .select(_queries['selectByCategoryId']!, [categoryId])
        .toMapList()
        .map((row) => Book.fromJson(row))
        .toList();
  }

  Future<Book?> getBookByTitle(String title) async {
    final db = await database;
    final result = db.select(_queries['selectByTitle']!, [title]).toMapList();
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  Future<Book?> getBookByTitleAndCategory(String title, int categoryId) async {
    final db = await database;
    final result = db.select(
        _queries['selectByTitleAndCategory']!, [title, categoryId]).toMapList();
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  Future<Book?> getBookByTitleCategoryAndFileType(
      String title, int categoryId, String fileType) async {
    final db = await database;
    final result = db.select(_queries['selectByTitleCategoryAndFileType']!,
        [title, categoryId, fileType]).toMapList();
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  /// Gets a book by its title and file type.
  Future<Book?> getBookByTitleAndFileType(String title, String fileType) async {
    final db = await database;
    final result = db.select(
        _queries['selectByTitleAndFileType']!, [title, fileType]).toMapList();
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  Future<List<Book>> getBooksByAuthor(String authorName) async {
    final db = await database;
    return db
        .select(_queries['selectByAuthor']!, ['%$authorName%'])
        .toMapList()
        .map((row) => Book.fromJson(row))
        .toList();
  }

  Future<int> insertBook(
    int categoryId,
    int sourceId,
    String title,
    String? heShortDesc,
    double orderIndex,
    int totalLines,
    bool isBaseBook, {
    bool hasTargumConnection = false,
    bool hasReferenceConnection = false,
    bool hasSourceConnection = false,
    bool hasCommentaryConnection = false,
    bool hasOtherConnection = false,
    bool hasAltStructures = false,
    bool hasTeamim = false,
    bool hasNekudot = false,
    bool isPersonal = false,
    String? filePath,
    String? fileType,
    int? fileSize,
    int? lastModified,
    int? pages,
    String? volume,
  }) async {
    final db = await database;
    db.execute(_queries['insert']!, [
      categoryId,
      sourceId,
      title,
      heShortDesc,
      orderIndex,
      totalLines,
      (isBaseBook ? 1 : 0),
      hasTargumConnection ? 1 : 0,
      hasReferenceConnection ? 1 : 0,
      hasSourceConnection ? 1 : 0,
      hasCommentaryConnection ? 1 : 0,
      hasOtherConnection ? 1 : 0,
      hasAltStructures ? 1 : 0,
      hasTeamim ? 1 : 0,
      hasNekudot ? 1 : 0,
      isPersonal ? 1 : 0,
      filePath,
      fileType,
      fileSize,
      lastModified,
      pages,
      volume,
    ]);
    return db.lastInsertRowId;
  }

  Future<int> updateBookTotalLines(int id, int totalLines) async {
    final db = await database;
    db.execute(_queries['updateTotalLines']!, [totalLines, id]);
    return db.updatedRows;
  }

  Future<int> updateBookCategoryId(int id, int categoryId) async {
    final db = await database;
    db.execute(_queries['updateCategoryId']!, [categoryId, id]);
    return db.updatedRows;
  }

  /// Inserts an external content book (content stored externally, metadata in DB).
  /// External content books store file path, type, size, and last modified.
  Future<int> insertExternalContentBook({
    required int categoryId,
    required int sourceId,
    required String title,
    String? heShortDesc,
    required double orderIndex,
    bool isPersonal = false,
    required String filePath,
    required String fileType,
    required int fileSize,
    required int lastModified,
  }) async {
    final db = await database;
    db.execute(_queries['insertExternalContent']!, [
      categoryId,
      sourceId,
      title,
      heShortDesc,
      orderIndex,
      isPersonal ? 1 : 0,
      filePath,
      fileType,
      fileSize,
      lastModified,
    ]);
    return db.lastInsertRowId;
  }

  /// Updates external book metadata (file size and last modified).
  Future<int> updateExternalMetadata(
      int id, int fileSize, int lastModified) async {
    final db = await database;
    db.execute(
        _queries['updateExternalMetadata']!, [fileSize, lastModified, id]);
    return db.updatedRows;
  }

  /// Gets all external content books.
  Future<List<Book>> getExternalContentBooks() async {
    final db = await database;
    return db
        .select(_queries['selectExternalContent']!)
        .toMapList()
        .map((row) => Book.fromJson(row))
        .toList();
  }

  /// Gets all personal books.
  Future<List<Book>> getPersonalBooks() async {
    final db = await database;
    return db
        .select(_queries['selectPersonal']!)
        .toMapList()
        .map((row) => Book.fromJson(row))
        .toList();
  }

  /// Gets an external book by its file path.
  Future<Book?> getBookByFilePath(String filePath) async {
    final db = await database;
    final result =
        db.select(_queries['selectByFilePath']!, [filePath]).toMapList();
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  /// Gets an external book by its file path and file type.
  Future<Book?> getBookByFilePathAndType(
      String filePath, String fileType) async {
    final db = await database;
    final result = db.select(
        _queries['selectByFilePathAndType']!, [filePath, fileType]).toMapList();
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  Future<int> updateBookConnectionFlags(
      int id,
      bool hasTargum,
      bool hasReference,
      bool hasSource,
      bool hasCommentary,
      bool hasOther) async {
    final db = await database;
    db.execute(_queries['updateConnectionFlags']!, [
      hasTargum ? 1 : 0,
      hasReference ? 1 : 0,
      hasSource ? 1 : 0,
      hasCommentary ? 1 : 0,
      hasOther ? 1 : 0,
      id
    ]);
    return db.updatedRows;
  }

  Future<int> updateAltStructuresFlag(int id, bool hasAltStructures) async {
    final db = await database;
    db.execute(
        _queries['updateAltStructuresFlag']!, [hasAltStructures ? 1 : 0, id]);
    return db.updatedRows;
  }

  Future<int> updateTeamimFlag(int id, bool hasTeamim) async {
    final db = await database;
    db.execute(_queries['updateTeamimFlag']!, [hasTeamim ? 1 : 0, id]);
    return db.updatedRows;
  }

  Future<int> updateNekudotFlag(int id, bool hasNekudot) async {
    final db = await database;
    db.execute(_queries['updateNekudotFlag']!, [hasNekudot ? 1 : 0, id]);
    return db.updatedRows;
  }

  Future<int> deleteBook(int id) async {
    final db = await database;
    db.execute(_queries['delete']!, [id]);
    return db.updatedRows;
  }

  Future<int> countBooksByCategory(int categoryId) async {
    final db = await database;
    return firstIntValue(
            db.select(_queries['countByCategoryId']!, [categoryId])) ??
        0;
  }

  Future<int> countAllBooks() async {
    final db = await database;
    return firstIntValue(db.select(_queries['countAll']!)) ?? 0;
  }

  Future<int?> getMaxBookId() async {
    final db = await database;
    return firstIntValue(db.select(_queries['getMaxId']!));
  }

  // Search functionality - kept inline due to dynamic LIKE pattern
  Future<List<Book>> searchBooks(String query) async {
    final db = await database;
    return db
        .select('''
      SELECT * FROM book
      WHERE (title LIKE ? OR heShortDesc LIKE ?)
        AND COALESCE(fileType, '') NOT IN ('link', 'url')
      ORDER BY orderIndex, title
    ''', ['%$query%', '%$query%'])
        .toMapList()
        .map((row) => Book.fromJson(row))
        .toList();
  }
}
