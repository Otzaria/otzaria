import 'package:sqlite3/sqlite3.dart';

import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/migration/dao/sqflite/sqlite3_utils.dart';

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

    final db = sqlite3.open(dbPath);
    db.execute('PRAGMA journal_mode=WAL');
    _migrateSchema(db);
    return db;
  }

  /// Apply schema migrations based on user_version
  void _migrateSchema(Database db) {
    final currentVersion =
        db.select('PRAGMA user_version').first.values.first as int;

    if (currentVersion == 0) {
      _createSchemaV1(db);
    }
    if (currentVersion < 2) {
      _migrateV1ToV2(db);
    }
    db.execute('PRAGMA user_version = $_databaseVersion');
  }

  /// Create database schema version 1
  void _createSchemaV1(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableNotes (
        $_columnId TEXT PRIMARY KEY,
        $_columnBookId TEXT NOT NULL,
        $_columnLineNumber INTEGER,
        $_columnDisplayTitle TEXT,
        $_columnLastKnownLine INTEGER,
        $_columnStatus TEXT NOT NULL,
        $_columnContent TEXT NOT NULL,
        $_columnCreatedAt TEXT NOT NULL,
        $_columnUpdatedAt TEXT NOT NULL
      )
    ''');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_book_id ON $_tableNotes($_columnBookId)');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_book_line ON $_tableNotes($_columnBookId, $_columnLineNumber)');
  }

  /// Migrate schema from v1 to v2
  void _migrateV1ToV2(Database db) {
    // Check if columns already exist (safe to re-run)
    final info = db.select('PRAGMA table_info($_tableNotes)');
    final cols = info.map((r) => r['name'] as String).toSet();
    if (!cols.contains(_columnContentPlain)) {
      db.execute(
          'ALTER TABLE $_tableNotes ADD COLUMN $_columnContentPlain TEXT NOT NULL DEFAULT \'\'');
      db.execute(
          'ALTER TABLE $_tableNotes ADD COLUMN $_columnContentFormat TEXT NOT NULL DEFAULT \'plain\'');
      db.execute(
          'UPDATE $_tableNotes SET $_columnContentPlain = $_columnContent WHERE $_columnContentPlain = \'\'');
    }
  }

  /// Load all notes for a specific book
  Future<List<PersonalNote>> loadNotes(String bookId) async {
    final db = await database;
    final maps = db.select(
      'SELECT * FROM $_tableNotes WHERE $_columnBookId = ? ORDER BY $_columnLineNumber ASC, $_columnUpdatedAt DESC',
      [bookId],
    ).toMapList();
    return maps.map((map) => _noteFromMap(map)).toList();
  }

  /// Insert a new note
  Future<void> insertNote(PersonalNote note) async {
    final db = await database;
    final m = _noteToMap(note);
    final cols = m.keys.join(', ');
    final placeholders = List.filled(m.length, '?').join(', ');
    db.execute(
      'INSERT OR REPLACE INTO $_tableNotes ($cols) VALUES ($placeholders)',
      m.values.toList(),
    );
  }

  /// Update an existing note
  Future<void> updateNote(PersonalNote note) async {
    final db = await database;
    final m = _noteToMap(note);
    final setClause = m.keys.map((k) => '$k = ?').join(', ');
    db.execute(
      'UPDATE $_tableNotes SET $setClause WHERE $_columnId = ?',
      [...m.values, note.id],
    );
  }

  /// Delete a note
  Future<void> deleteNote(String noteId) async {
    final db = await database;
    db.execute('DELETE FROM $_tableNotes WHERE $_columnId = ?', [noteId]);
  }

  /// Get a single note by ID
  Future<PersonalNote?> getNote(String noteId) async {
    final db = await database;
    final maps = db.select(
      'SELECT * FROM $_tableNotes WHERE $_columnId = ? LIMIT 1',
      [noteId],
    ).toMapList();
    if (maps.isEmpty) return null;
    return _noteFromMap(maps.first);
  }

  /// Get all books that have notes
  Future<List<BookNotesInfo>> listBooksWithNotes() async {
    final db = await database;
    final result = db.select('''
      SELECT 
        $_columnBookId,
        COUNT(*) as note_count,
        MAX($_columnUpdatedAt) as last_updated
      FROM $_tableNotes
      GROUP BY $_columnBookId
      ORDER BY $_columnBookId ASC
    ''').toMapList();
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
    db.execute('DELETE FROM $_tableNotes WHERE $_columnBookId = ?', [bookId]);
  }

  /// Batch update multiple notes (for reconciliation)
  Future<void> batchUpdateNotes(List<PersonalNote> notes) async {
    final db = await database;
    withTransaction(db, () {
      for (final note in notes) {
        final m = _noteToMap(note);
        final setClause = m.keys.map((k) => '$k = ?').join(', ');
        db.execute(
          'UPDATE $_tableNotes SET $setClause WHERE $_columnId = ?',
          [...m.values, note.id],
        );
      }
    });
  }

  /// Batch insert multiple notes (for migration)
  /// Skips notes that already exist (by ID)
  Future<int> batchInsertNotes(List<PersonalNote> notes) async {
    if (notes.isEmpty) return 0;
    final db = await database;
    int count = 0;
    withTransaction(db, () {
      for (final note in notes) {
        final m = _noteToMap(note);
        final cols = m.keys.join(', ');
        final placeholders = List.filled(m.length, '?').join(', ');
        db.execute(
          'INSERT OR IGNORE INTO $_tableNotes ($cols) VALUES ($placeholders)',
          m.values.toList(),
        );
        count++;
      }
    });
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
      db.close();
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
