import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../../models/book.dart';
import '../book_read.dart';
import '../db_capabilities.dart';
import '../sqlite3_utils.dart';
import '../query_loader.dart';
import 'package:otzaria/attached_libraries/utils/attached_file_path.dart';
import 'database.dart';

class BookDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  BookDao(this._db) {
    _queries = QueryLoader.loadQueries('BookQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<DbCapabilities> get _capabilities => _db.capabilities;

  Future<T> _read<T>(
    BookReadOperation operation,
    List<Object?> arguments,
    Future<T> Function() localRead,
  ) => _db.bookReadDelegate == null
      ? localRead()
      : _db.readBooks<T>(operation, arguments);

  /// ספר משורת `book`. במסד מצורף `filePath` נפתר יחסית לתיקיית המסד, ונתיב
  /// אסור הופך ל-null — כך אף צרכן אינו פותח קובץ מחוץ לתיקייה.
  Book bookFromRow(Map<String, dynamic> row) {
    if (!_db.isUntrusted || row['filePath'] == null) return Book.fromJson(row);
    return Book.fromJson({
      ...row,
      'filePath': resolveAttachedBookFilePath(
        _db.path,
        row['filePath'] as String?,
      ),
    });
  }

  /// שורה ראשונה של [query], או null כשאין במסד טבלת ספרים.
  Future<Book?> _selectOne(String query, List<Object?> args) async {
    final capabilities = await _capabilities;
    if (!capabilities.hasBooks) return null;
    final db = await database;
    final result = db
        .select(capabilities.adaptBookQuery(query), args)
        .toMapList();
    if (result.isEmpty) return null;
    return bookFromRow(result.first);
  }

  Future<List<Book>> _selectMany(String query, List<Object?> args) async {
    final capabilities = await _capabilities;
    if (!capabilities.hasBooks) return const [];
    final db = await database;
    return db
        .select(capabilities.adaptBookQuery(query), args)
        .toMapList()
        .map((row) => bookFromRow(row))
        .toList();
  }

  Future<List<Book>> getAllBooks() => _read(
    BookReadOperation.allBooks,
    const [],
    () => _selectMany(_queries['selectAll']!, []),
  );

  /// נתוני קטלוג על חיבור קיים, לקריאה סינכרונית בתוך טרנזקציה.
  /// [withFileColumns] מוסיף נתוני קבצים ל-user_books.db; אינם קיימים ב-seforim.db v3.
  List<Map<String, dynamic>> getAllBooksMinimal(
    sqlite3.Database db, {
    bool withFileColumns = false,
  }) => selectBooksMinimal(
    db,
    DbCapabilities.forDatabase(_db.path, db),
    withFileColumns: withFileColumns,
  );

  /// גוף [getAllBooksMinimal] בלי תלות במופע — לקריאה ב-isolate על חיבור משלו.
  static List<Map<String, dynamic>> selectBooksMinimal(
    sqlite3.Database db,
    DbCapabilities capabilities, {
    bool withFileColumns = false,
  }) {
    if (!capabilities.hasBooks) return const [];
    String col(String name, {String fallback = 'NULL'}) =>
        capabilities.column('book', name, fallback: fallback);
    final categoryColumn = capabilities.hasBookCategories
        ? 'categoryId'
        : '0 AS categoryId';
    final order = capabilities.hasColumn('book', 'orderIndex')
        ? 'orderIndex, title'
        : 'title';

    if (withFileColumns) {
      return db.select('''
        SELECT id, title, $categoryColumn, ${col('orderIndex')},
               ${col('fileType')}, ${col('filePath')},
               ${col('heShortDesc')}, ${col('heDesc')}
        FROM book
        ${capabilities.hasColumn('book', 'fileType') ? "WHERE COALESCE(fileType, '') NOT IN ('link', 'url')" : ''}
        ORDER BY $order
      ''').toMapList();
    }
    return db.select('''
      SELECT id, title, $categoryColumn, ${col('orderIndex')},
             ${col('heShortDesc')}, ${col('heDesc')}
      FROM book
      ORDER BY $order
    ''').toMapList();
  }

  /// Loads authors for all local books in one query to keep catalog build fast.
  Map<int, String> getBookAuthorsMap(sqlite3.Database db) =>
      selectBookAuthorsMap(db, DbCapabilities.forDatabase(_db.path, db));

  /// גוף [getBookAuthorsMap] בלי תלות במופע — לקריאה ב-isolate.
  static Map<int, String> selectBookAuthorsMap(
    sqlite3.Database db,
    DbCapabilities capabilities,
  ) {
    if (!capabilities.hasAuthors) return {};
    final rows = db.select('''
      SELECT author_rows.bookId,
             GROUP_CONCAT(author_rows.name, ', ') AS author
      FROM (
        SELECT ba.bookId AS bookId,
               a.name AS name
        FROM book_author ba
        JOIN author a ON a.id = ba.authorId
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

  /// השדות שהקאש המשותף של טבלת `book` צורך, כמפות. ההקרנה הרזה שומרת את
  /// ההעתקה קטנה כשהשורות חוצות גבול isolate (~7,300 ספרים).
  Future<List<Map<String, dynamic>>> selectAllLocalBooksSlim() async {
    if (_db.bookReadDelegate != null) {
      return _db.readBooks(BookReadOperation.localBooksSlim, const []);
    }
    final capabilities = await _capabilities;
    if (!capabilities.hasBooks) return const [];
    final db = await database;
    return db
        .select(
          capabilities.adaptBookQuery(
            _queries['selectAllIgnoreExternalCatalogs']!,
          ),
        )
        .map(
          (row) => <String, dynamic>{
            'id': row['id'],
            'title': row['title'],
            'filePath': row['filePath'],
            'fileType': row['fileType'],
            'categoryId': row['categoryId'],
            'orderIndex': row['orderIndex'],
          },
        )
        .toList();
  }

  /// Gets all local books (excluding external catalog books).
  Future<List<Book>> getAllLocalBooks() => _read(
    BookReadOperation.allLocalBooks,
    const [],
    () => _selectMany(_queries['selectAllIgnoreExternalCatalogs']!, []),
  );

  /// כל הספרים והיחסים שלהם, בשאילתה אחת לכל סוג יחס במקום שאילתות לכל ספר.
  Future<List<Map<String, dynamic>>> getAllBooksWithRelations() async {
    if (_db.bookReadDelegate != null) {
      return _db.readBooks(BookReadOperation.allBooksWithRelations, const []);
    }
    final capabilities = await _capabilities;
    if (!capabilities.hasBooks) return const [];
    final db = await database;

    // Always exclude external catalog books (fileType='link') - they are in a separate DB
    final books = db
        .select(
          capabilities.adaptBookQuery(
            _queries['selectAllIgnoreExternalCatalogs']!,
          ),
        )
        .toMapList();

    if (books.isEmpty) return [];

    // The query selects every book, so the relation queries need no id
    // filter; an IN list of all ids made SQLite parse thousands of literals.
    final authorsData = !capabilities.hasAuthors
        ? const <Map<String, dynamic>>[]
        : db.select('''
        SELECT ba.bookId, a.id, a.name
        FROM book_author ba
        JOIN author a ON ba.authorId = a.id
        ORDER BY ba.bookId
      ''').toMapList();
    final topicsData = !capabilities.hasTopics
        ? const <Map<String, dynamic>>[]
        : db.select('''
        SELECT bt.bookId, t.id, t.name
        FROM book_topic bt
        JOIN topic t ON bt.topicId = t.id
        ORDER BY bt.bookId
      ''').toMapList();
    final pubPlacesData = !capabilities.hasPubPlaces
        ? const <Map<String, dynamic>>[]
        : db.select('''
        SELECT bpp.bookId, pp.id, pp.name
        FROM book_pub_place bpp
        JOIN pub_place pp ON bpp.pubPlaceId = pp.id
        ORDER BY bpp.bookId
      ''').toMapList();
    final pubDatesData = !capabilities.hasPubDates
        ? const <Map<String, dynamic>>[]
        : db.select('''
        SELECT bpd.bookId, pd.id, pd.date
        FROM book_pub_date bpd
        JOIN pub_date pd ON bpd.pubDateId = pd.id
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

  Future<Book?> getBookById(int id) => _read(
    BookReadOperation.byId,
    [id],
    () => _selectOne(_queries['selectById']!, [id]),
  );

  Future<List<Book>> getBooksByCategory(int categoryId) async {
    if (_db.bookReadDelegate != null) {
      return _db.readBooks(BookReadOperation.byCategory, [categoryId]);
    }
    if (!(await _capabilities).hasBookCategories) return const [];
    return _selectMany(_queries['selectByCategoryId']!, [categoryId]);
  }

  Future<Book?> getBookByTitle(String title) => _read(
    BookReadOperation.byTitle,
    [title],
    () => _selectOne(_queries['selectByTitle']!, [title]),
  );

  /// במסד בלי עמודת קטגוריה כל הספרים יושבים תחת שורש אחד — ההתאמה לפי כותרת.
  Future<Book?> getBookByTitleAndCategory(String title, int categoryId) async {
    if (_db.bookReadDelegate != null) {
      return _db.readBooks(BookReadOperation.byTitleAndCategory, [
        title,
        categoryId,
      ]);
    }
    if (!(await _capabilities).hasBookCategories) {
      return getBookByTitle(title);
    }
    return _selectOne(_queries['selectByTitleAndCategory']!, [
      title,
      categoryId,
    ]);
  }

  Future<Book?> getBookByTitleCategoryAndFileType(
    String title,
    int categoryId,
    String fileType,
  ) async {
    if (_db.bookReadDelegate != null) {
      return _db.readBooks(BookReadOperation.byTitleCategoryAndFileType, [
        title,
        categoryId,
        fileType,
      ]);
    }
    final capabilities = await _capabilities;
    if (!capabilities.hasBookCategories ||
        !capabilities.hasColumn('book', 'fileType')) {
      return null;
    }
    return _selectOne(_queries['selectByTitleCategoryAndFileType']!, [
      title,
      categoryId,
      fileType,
    ]);
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
    return insertBookSync(
      db,
      categoryId,
      sourceId,
      title,
      heShortDesc,
      orderIndex,
      totalLines,
      isBaseBook,
      hasTargumConnection: hasTargumConnection,
      hasReferenceConnection: hasReferenceConnection,
      hasSourceConnection: hasSourceConnection,
      hasCommentaryConnection: hasCommentaryConnection,
      hasOtherConnection: hasOtherConnection,
      hasAltStructures: hasAltStructures,
      hasTeamim: hasTeamim,
      hasNekudot: hasNekudot,
      isPersonal: isPersonal,
      filePath: filePath,
      fileType: fileType,
      fileSize: fileSize,
      lastModified: lastModified,
      pages: pages,
      volume: volume,
    );
  }

  /// גרעין סינכרוני של [insertBook] — לשימוש בתוך `withTransaction`.
  int insertBookSync(
    sqlite3.Database db,
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
  }) {
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

  /// Updates external book metadata (file size and last modified).
  Future<int> updateExternalMetadata(
    int id,
    int fileSize,
    int lastModified,
  ) async {
    final db = await database;
    db.execute(_queries['updateExternalMetadata']!, [
      fileSize,
      lastModified,
      id,
    ]);
    return db.updatedRows;
  }

  /// Gets an external book by its file path.
  Future<Book?> getBookByFilePath(String filePath) async {
    if (_db.bookReadDelegate != null) {
      return _db.readBooks(BookReadOperation.byFilePath, [filePath]);
    }
    final db = await database;
    final result = db.select(_queries['selectByFilePath']!, [
      filePath,
    ]).toMapList();
    if (result.isEmpty) return null;
    return bookFromRow(result.first);
  }

  Future<int> countAllBooks() async {
    if (_db.bookReadDelegate != null) {
      return _db.readBooks(BookReadOperation.count, const []);
    }
    final db = await database;
    return firstIntValue(db.select(_queries['countAll']!)) ?? 0;
  }
}
