import 'package:sqflite/sqflite.dart';

import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';

/// SQLite database for storing personal notes.
///
/// Schema:
/// - personal_notes table: stores all note metadata and content
/// - Indexed by book_id and line_number for fast queries
class PersonalNotesDatabase {
  static const _databaseName = 'personal_notes.db';
  static const _databaseVersion = 2;

  static const _tableNotes = 'personal_notes';

  // Column names
  static const _columnId = 'id';
  static const _columnBookId = 'book_id';
  static const _columnLineNumber = 'line_number';

  static const _columnDisplayTitle = 'display_title';
  static const _columnLastKnownLine = 'last_known_line';
  static const _columnStatus = 'status';
  static const _columnContent = 'content';
  static const _columnContentPlain = 'content_plain';
  static const _columnContentFormat = 'content_format';
  static const _columnCreatedAt = 'created_at';
  static const _columnUpdatedAt = 'updated_at';

  PersonalNotesDatabase._();

  static final PersonalNotesDatabase instance = PersonalNotesDatabase._();

  Database? _database;

  /// Get or initialize the database
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize the database
  Future<Database> _initDatabase() async {
    final dbPath = await AppPaths.resolveNotesDbPath(_databaseName);

    return await openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create database schema
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableNotes (
        $_columnId TEXT PRIMARY KEY,
        $_columnBookId TEXT NOT NULL,
        $_columnLineNumber INTEGER,
        $_columnDisplayTitle TEXT,
        $_columnLastKnownLine INTEGER,
        $_columnStatus TEXT NOT NULL,
        $_columnContent TEXT NOT NULL,
        $_columnContentPlain TEXT NOT NULL,
        $_columnContentFormat TEXT NOT NULL,
        $_columnCreatedAt TEXT NOT NULL,
        $_columnUpdatedAt TEXT NOT NULL
      )
    ''');

    // Create indexes for faster queries
    await db.execute('''
      CREATE INDEX idx_book_id ON $_tableNotes($_columnBookId)
    ''');

    await db.execute('''
      CREATE INDEX idx_book_line ON $_tableNotes($_columnBookId, $_columnLineNumber)
    ''');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE $_tableNotes ADD COLUMN $_columnContentPlain TEXT NOT NULL DEFAULT \'\'');
      await db.execute(
          'ALTER TABLE $_tableNotes ADD COLUMN $_columnContentFormat TEXT NOT NULL DEFAULT \'plain\'');
      await db.execute(
          'UPDATE $_tableNotes SET $_columnContentPlain = $_columnContent WHERE $_columnContentPlain = \'\'');
    }
  }

  /// Load all notes for a specific book
  Future<List<PersonalNote>> loadNotes(String bookId) async {
    final db = await database;

    final maps = await db.query(
      _tableNotes,
      where: '$_columnBookId = ?',
      whereArgs: [bookId],
      orderBy: '$_columnLineNumber ASC, $_columnUpdatedAt DESC',
    );

    return maps.map((map) => _noteFromMap(map)).toList();
  }

  /// Insert a new note
  Future<void> insertNote(PersonalNote note) async {
    final db = await database;
    await db.insert(
      _tableNotes,
      _noteToMap(note),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update an existing note
  Future<void> updateNote(PersonalNote note) async {
    final db = await database;
    await db.update(
      _tableNotes,
      _noteToMap(note),
      where: '$_columnId = ?',
      whereArgs: [note.id],
    );
  }

  /// Delete a note
  Future<void> deleteNote(String noteId) async {
    final db = await database;
    await db.delete(
      _tableNotes,
      where: '$_columnId = ?',
      whereArgs: [noteId],
    );
  }

  /// Get a single note by ID
  Future<PersonalNote?> getNote(String noteId) async {
    final db = await database;

    final maps = await db.query(
      _tableNotes,
      where: '$_columnId = ?',
      whereArgs: [noteId],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return _noteFromMap(maps.first);
  }

  /// Get all books that have notes
  Future<List<BookNotesInfo>> listBooksWithNotes() async {
    final db = await database;

    final result = await db.rawQuery('''
      SELECT 
        $_columnBookId,
        COUNT(*) as note_count,
        MAX($_columnUpdatedAt) as last_updated
      FROM $_tableNotes
      GROUP BY $_columnBookId
      ORDER BY $_columnBookId ASC
    ''');

    return result.map((row) {
      return BookNotesInfo(
        bookId: row[_columnBookId] as String,
        noteCount: row['note_count'] as int,
        lastUpdated: DateTime.parse(row['last_updated'] as String),
      );
    }).toList();
  }

  /// Delete all notes for a specific book
  Future<void> deleteBookNotes(String bookId) async {
    final db = await database;
    await db.delete(
      _tableNotes,
      where: '$_columnBookId = ?',
      whereArgs: [bookId],
    );
  }

  /// Batch update multiple notes (for reconciliation)
  Future<void> batchUpdateNotes(List<PersonalNote> notes) async {
    final db = await database;
    final batch = db.batch();

    for (final note in notes) {
      batch.update(
        _tableNotes,
        _noteToMap(note),
        where: '$_columnId = ?',
        whereArgs: [note.id],
      );
    }

    await batch.commit(noResult: true);
  }

  /// Batch insert multiple notes (for migration)
  /// Skips notes that already exist (by ID)
  Future<int> batchInsertNotes(List<PersonalNote> notes) async {
    if (notes.isEmpty) return 0;

    final db = await database;
    final batch = db.batch();
    int count = 0;

    for (final note in notes) {
      batch.insert(
        _tableNotes,
        _noteToMap(note),
        conflictAlgorithm: ConflictAlgorithm.ignore, // Skip if ID exists
      );
      count++;
    }

    await batch.commit(noResult: true);
    return count;
  }

  /// Convert PersonalNote to database map
  Map<String, dynamic> _noteToMap(PersonalNote note) {
    return {
      _columnId: note.id,
      _columnBookId: note.bookId,
      _columnLineNumber: note.lineNumber,
      _columnDisplayTitle: note.displayTitle,
      _columnLastKnownLine: note.lastKnownLineNumber,
      _columnStatus: note.status.name,
      _columnContent: note.content,
      _columnContentPlain: note.contentPlain,
      _columnContentFormat: note.contentFormat.name,
      _columnCreatedAt: note.createdAt.toIso8601String(),
      _columnUpdatedAt: note.updatedAt.toIso8601String(),
    };
  }

  /// Convert database map to PersonalNote
  PersonalNote _noteFromMap(Map<String, dynamic> map) {
    return PersonalNote(
      id: map[_columnId] as String,
      bookId: map[_columnBookId] as String,
      lineNumber: map[_columnLineNumber] as int?,
      displayTitle: map[_columnDisplayTitle] as String?,
      lastKnownLineNumber: map[_columnLastKnownLine] as int?,
      status: PersonalNoteStatus.values.byName(map[_columnStatus] as String),
      content: map[_columnContent] as String,
      contentPlain: map[_columnContentPlain] as String? ??
          (map[_columnContent] as String),
      contentFormat: PersonalNoteContentFormat.values.byName(
          map[_columnContentFormat] as String? ??
              PersonalNoteContentFormat.plain.name),
      createdAt: DateTime.parse(map[_columnCreatedAt] as String),
      updatedAt: DateTime.parse(map[_columnUpdatedAt] as String),
    );
  }

  /// Close the database
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}

/// Information about a book that has notes
class BookNotesInfo {
  final String bookId;
  final int noteCount;
  final DateTime lastUpdated;

  BookNotesInfo({
    required this.bookId,
    required this.noteCount,
    required this.lastUpdated,
  });
}
