import 'package:sqflite/sqflite.dart';
import '../../core/models/book.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class BookDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  BookDao(this._db) {
    _queries = QueryLoader.loadQueries('BookQueries.sq');
  }

  Future<Database> get database => _db.database;

  Future<List<Book>> getAllBooks() async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectAll']!);
    return result.map((row) => Book.fromJson(row)).toList();
  }

  /// Gets all books with their relations (authors, topics, pubPlaces, pubDates) in a single optimized query.
  /// This is much faster than calling getAllBooks() and then loading relations separately.
  Future<List<Map<String, dynamic>>> getAllBooksWithRelations() async {
    final db = await database;

    // Get all books
    final books = await db.rawQuery(_queries['selectAll']!);

    if (books.isEmpty) return [];

    // Get all book IDs
    final bookIds = books.map((b) => b['id'] as int).toList();
    final bookIdsStr = bookIds.join(',');

    // Load all relations in parallel with single queries each
    final results = await Future.wait([
      // Authors
      db.rawQuery('''
        SELECT ba.bookId, a.id, a.name
        FROM book_author ba
        JOIN author a ON ba.authorId = a.id
        WHERE ba.bookId IN ($bookIdsStr)
        ORDER BY ba.bookId
      '''),
      // Topics
      db.rawQuery('''
        SELECT bt.bookId, t.id, t.name
        FROM book_topic bt
        JOIN topic t ON bt.topicId = t.id
        WHERE bt.bookId IN ($bookIdsStr)
        ORDER BY bt.bookId
      '''),
      // Pub Places
      db.rawQuery('''
        SELECT bpp.bookId, pp.id, pp.name
        FROM book_pub_place bpp
        JOIN pub_place pp ON bpp.pubPlaceId = pp.id
        WHERE bpp.bookId IN ($bookIdsStr)
        ORDER BY bpp.bookId
      '''),
      // Pub Dates
      db.rawQuery('''
        SELECT bpd.bookId, pd.id, pd.date
        FROM book_pub_date bpd
        JOIN pub_date pd ON bpd.pubDateId = pd.id
        WHERE bpd.bookId IN ($bookIdsStr)
        ORDER BY bpd.bookId
      '''),
    ]);

    final authorsData = results[0];
    final topicsData = results[1];
    final pubPlacesData = results[2];
    final pubDatesData = results[3];

    // Group relations by bookId
    final authorsByBook = <int, List<Map<String, dynamic>>>{};
    final topicsByBook = <int, List<Map<String, dynamic>>>{};
    final pubPlacesByBook = <int, List<Map<String, dynamic>>>{};
    final pubDatesByBook = <int, List<Map<String, dynamic>>>{};

    for (final row in authorsData) {
      final bookId = row['bookId'] as int;
      authorsByBook.putIfAbsent(bookId, () => []);
      authorsByBook[bookId]!.add({'id': row['id'], 'name': row['name']});
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
    final result = await db.rawQuery(_queries['selectById']!, [id]);
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  Future<List<Book>> getBooksByCategory(int categoryId) async {
    final db = await database;
    final result =
        await db.rawQuery(_queries['selectByCategoryId']!, [categoryId]);
    return result.map((row) => Book.fromJson(row)).toList();
  }

  Future<Book?> getBookByTitle(String title) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByTitle']!, [title]);
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  Future<Book?> getBookByTitleAndCategory(String title, int categoryId) async {
    final db = await database;
    final result = await db
        .rawQuery(_queries['selectByTitleAndCategory']!, [title, categoryId]);
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  Future<Book?> getBookByTitleCategoryAndFileType(
      String title, int categoryId, String fileType) async {
    final db = await database;
    final result = await db.rawQuery(
        _queries['selectByTitleCategoryAndFileType']!,
        [title, categoryId, fileType]);
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  Future<List<Book>> getBooksByAuthor(String authorName) async {
    final db = await database;
    final result =
        await db.rawQuery(_queries['selectByAuthor']!, ['%$authorName%']);
    return result.map((row) => Book.fromJson(row)).toList();
  }

  Future<int> insertBook(
    int categoryId,
    int sourceId,
    String title,
    String? heShortDesc,
    double orderIndex,
    int totalLines,
    bool isBaseBook,
    String? notesContent, {
    bool hasTargumConnection = false,
    bool hasReferenceConnection = false,
    bool hasSourceConnection = false,
    bool hasCommentaryConnection = false,
    bool hasOtherConnection = false,
    bool hasAltStructures = false,
    bool hasTeamim = false,
    bool hasNekudot = false,
    bool isContentExternal = false,
    String? externalLibraryId,
    bool isPersonal = false,
    String? filePath,
    String? fileType,
    int? fileSize,
    int? lastModified,
  }) async {
    final db = await database;
    return await db.rawInsert(_queries['insert']!, [
      categoryId,
      sourceId,
      title,
      heShortDesc,
      notesContent,
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
      isContentExternal ? 1 : 0,
      externalLibraryId,
      isPersonal ? 1 : 0,
      filePath,
      fileType,
      fileSize,
      lastModified,
    ]);
  }

  Future<int> insertBookWithId(
    int id,
    int categoryId,
    int sourceId,
    String title,
    String? heShortDesc,
    double orderIndex,
    int totalLines,
    bool isBaseBook,
    String? notesContent, {
    bool hasTargumConnection = false,
    bool hasReferenceConnection = false,
    bool hasSourceConnection = false,
    bool hasCommentaryConnection = false,
    bool hasOtherConnection = false,
    bool hasAltStructures = false,
    bool hasTeamim = false,
    bool hasNekudot = false,
    bool isContentExternal = false,
    String? externalLibraryId,
    bool isPersonal = false,
    String? filePath,
    String? fileType,
    int? fileSize,
    int? lastModified,
  }) async {
    final db = await database;
    return await db.rawInsert(_queries['insertWithId']!, [
      id,
      categoryId,
      sourceId,
      title,
      heShortDesc,
      notesContent,
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
      isContentExternal ? 1 : 0,
      externalLibraryId,
      isPersonal ? 1 : 0,
      filePath,
      fileType,
      fileSize,
      lastModified,
    ]);
  }

  Future<int> updateBookTotalLines(int id, int totalLines) async {
    final db = await database;
    return await db.rawUpdate(_queries['updateTotalLines']!, [totalLines, id]);
  }

  Future<int> updateBookCategoryId(int id, int categoryId) async {
    final db = await database;
    return await db.rawUpdate(_queries['updateCategoryId']!, [categoryId, id]);
  }

  /// Inserts an external content book (content stored externally, metadata in DB).
  /// External content books have isContentExternal=1 and store file path, type, size, and last modified.
  Future<int> insertExternalContentBook({
    required int categoryId,
    required int sourceId,
    required String title,
    String? heShortDesc,
    required double orderIndex,
    String? externalLibraryId,
    bool isPersonal = false,
    required String filePath,
    required String fileType,
    required int fileSize,
    required int lastModified,
  }) async {
    final db = await database;
    return await db.rawInsert(_queries['insertExternalContent']!, [
      categoryId,
      sourceId,
      title,
      heShortDesc,
      orderIndex,
      externalLibraryId,
      isPersonal ? 1 : 0,
      filePath,
      fileType,
      fileSize,
      lastModified,
    ]);
  }

  /// Updates external book metadata (file size and last modified).
  Future<int> updateExternalMetadata(
      int id, int fileSize, int lastModified) async {
    final db = await database;
    return await db.rawUpdate(
        _queries['updateExternalMetadata']!, [fileSize, lastModified, id]);
  }

  /// Gets all external content books.
  Future<List<Book>> getExternalContentBooks() async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectExternalContent']!);
    return result.map((row) => Book.fromJson(row)).toList();
  }

  /// Gets all personal books.
  Future<List<Book>> getPersonalBooks() async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectPersonal']!);
    return result.map((row) => Book.fromJson(row)).toList();
  }

  /// Gets an external book by its file path.
  Future<Book?> getBookByFilePath(String filePath) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByFilePath']!, [filePath]);
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  /// Gets a book by its external library ID.
  Future<Book?> getBookByExternalLibraryId(String externalLibraryId) async {
    final db = await database;
    final result = await db
        .rawQuery(_queries['selectByExternalLibraryId']!, [externalLibraryId]);
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
    return await db.rawUpdate(_queries['updateConnectionFlags']!, [
      hasTargum ? 1 : 0,
      hasReference ? 1 : 0,
      hasSource ? 1 : 0,
      hasCommentary ? 1 : 0,
      hasOther ? 1 : 0,
      id
    ]);
  }

  Future<int> updateAltStructuresFlag(int id, bool hasAltStructures) async {
    final db = await database;
    return await db.rawUpdate(
        _queries['updateAltStructuresFlag']!, [hasAltStructures ? 1 : 0, id]);
  }

  Future<int> updateTeamimFlag(int id, bool hasTeamim) async {
    final db = await database;
    return await db
        .rawUpdate(_queries['updateTeamimFlag']!, [hasTeamim ? 1 : 0, id]);
  }

  Future<int> updateNekudotFlag(int id, bool hasNekudot) async {
    final db = await database;
    return await db
        .rawUpdate(_queries['updateNekudotFlag']!, [hasNekudot ? 1 : 0, id]);
  }

  Future<int> deleteBook(int id) async {
    final db = await database;
    return await db.rawDelete(_queries['delete']!, [id]);
  }

  Future<int> countBooksByCategory(int categoryId) async {
    final db = await database;
    final result =
        await db.rawQuery(_queries['countByCategoryId']!, [categoryId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countAllBooks() async {
    final db = await database;
    final result = await db.rawQuery(_queries['countAll']!);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int?> getMaxBookId() async {
    final db = await database;
    final result = await db.rawQuery(_queries['getMaxId']!);
    return Sqflite.firstIntValue(result);
  }

  // Search functionality - kept inline due to dynamic LIKE pattern
  Future<List<Book>> searchBooks(String query) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT * FROM book
      WHERE title LIKE ? OR heShortDesc LIKE ?
      ORDER BY orderIndex, title
    ''', ['%$query%', '%$query%']);
    return result.map((row) => Book.fromJson(row)).toList();
  }
}
