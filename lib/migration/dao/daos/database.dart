import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;
import 'package:path/path.dart' as p;

import 'author_dao.dart';
import 'book_acronym_dao.dart';
import 'book_dao.dart';
import 'book_has_links_dao.dart';
import 'category_dao.dart';
import 'connection_type_dao.dart';
import 'line_dao.dart';
import 'link_dao.dart';
import 'pub_date_dao.dart';
import 'pub_place_dao.dart';
import 'search_dao.dart';
import 'toc_dao.dart';
import 'toc_text_dao.dart';
import 'topic_dao.dart';
import '../sqflite/query_loader.dart';

class MyDatabase {
  static Database? _database;
  static String? _customPath;

  /// Initialize the database factory for the appropriate platform.
  /// This must be called before using any database operations.
  static void initialize() {
    // Initialize FFI for desktop platforms
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqflite_ffi.sqfliteFfiInit();
      databaseFactory = sqflite_ffi.databaseFactoryFfi;
    }
  }

  // DAOs
  AuthorDao? _authorDao;
  BookAcronymDao? _bookAcronymDao;
  BookDao? _bookDao;
  BookHasLinksDao? _bookHasLinksDao;
  CategoryDao? _categoryDao;
  ConnectionTypeDao? _connectionTypeDao;
  LineDao? _lineDao;
  LinkDao? _linkDao;
  PubDateDao? _pubDateDao;
  PubPlaceDao? _pubPlaceDao;
  SearchDao? _searchDao;
  TocDao? _tocDao;
  TocTextDao? _tocTextDao;
  TopicDao? _topicDao;

  AuthorDao get authorDao {
    _ensureDaosInitialized();
    return _authorDao!;
  }

  BookAcronymDao get bookAcronymDao {
    _ensureDaosInitialized();
    return _bookAcronymDao!;
  }

  BookDao get bookDao {
    _ensureDaosInitialized();
    return _bookDao!;
  }

  BookHasLinksDao get bookHasLinksDao {
    _ensureDaosInitialized();
    return _bookHasLinksDao!;
  }

  CategoryDao get categoryDao {
    _ensureDaosInitialized();
    return _categoryDao!;
  }

  ConnectionTypeDao get connectionTypeDao {
    _ensureDaosInitialized();
    return _connectionTypeDao!;
  }

  LineDao get lineDao {
    _ensureDaosInitialized();
    return _lineDao!;
  }

  LinkDao get linkDao {
    _ensureDaosInitialized();
    return _linkDao!;
  }

  PubDateDao get pubDateDao {
    _ensureDaosInitialized();
    return _pubDateDao!;
  }

  PubPlaceDao get pubPlaceDao {
    _ensureDaosInitialized();
    return _pubPlaceDao!;
  }

  SearchDao get searchDao {
    _ensureDaosInitialized();
    return _searchDao!;
  }

  TocDao get tocDao {
    _ensureDaosInitialized();
    return _tocDao!;
  }

  TocTextDao get tocTextDao {
    _ensureDaosInitialized();
    return _tocTextDao!;
  }

  TopicDao get topicDao {
    _ensureDaosInitialized();
    return _topicDao!;
  }

  void _ensureDaosInitialized() {
    if (_authorDao == null) {
      _initializeDaos();
    }
  }

  MyDatabase._privateConstructor();

  static final MyDatabase _instance = MyDatabase._privateConstructor();

  factory MyDatabase() {
    return _instance;
  }

  /// Creates a new MyDatabase instance with a custom database path.
  /// This is useful for migrations where you need to specify the exact database file.
  factory MyDatabase.withPath(String path) {
    _customPath = path;
    // Create a new instance to avoid conflicts with the singleton
    final instance = MyDatabase._privateConstructor();
    // DAOs will be initialized in _onCreate when the database is first opened
    return instance;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    // Initialize QueryLoader before creating DAOs
    await QueryLoader.initialize();
    _database = await _initDatabase();
    _initializeDaos();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path;

    if (_customPath != null) {
      // Use the custom path provided
      path = _customPath!;
    } else {
      // Use the current working directory as the database folder to avoid depending on path_provider.
      final dbFolder = Directory.current;
      path = p.join(dbFolder.path, 'db.sqlite');
    }

    return await openDatabase(
      path,
      version: 3, // Incremented version to trigger migration for lineIndex
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  Future<void> _onOpen(Database db) async {
    // Ensure all tables exist even when opening an existing database
    // This handles cases where the schema has been updated
    final createScripts = _getCreateScripts();
    for (final script in createScripts) {
      try {
        await db.execute(script);
      } catch (e) {
        // Ignore errors for tables that already exist
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // Execute all table creation scripts from Database.sq
    final createScripts = _getCreateScripts();
    for (final script in createScripts) {
      await db.execute(script);
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle database upgrades
    if (oldVersion < 2) {
      // Migration from version 1 to 2: Add externalId column to book table
      try {
        await db.execute('ALTER TABLE book ADD COLUMN externalId TEXT;');
        debugPrint('✅ Migration v1→v2: Added externalId column to book table');
      } catch (e) {
        // Column might already exist, ignore error
        debugPrint(
            '⚠️ Migration v1→v2: externalId column might already exist: $e');
      }
    }

    if (oldVersion < 3) {
      // Migration from version 2 to 3: Add lineIndex column to tocEntry table
      try {
        await db.execute('ALTER TABLE tocEntry ADD COLUMN lineIndex INTEGER;');
        debugPrint(
            '✅ Migration v2→v3: Added lineIndex column to tocEntry table');
      } catch (e) {
        // Column might already exist, ignore error
        debugPrint(
            '⚠️ Migration v2→v3: lineIndex column might already exist: $e');
      }
    }

    // Ensure all other tables exist (for any missing tables)
    final createScripts = _getCreateScripts();
    for (final script in createScripts) {
      try {
        await db.execute(script);
      } catch (e) {
        // Ignore errors for tables that already exist
      }
    }
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  void _initializeDaos() {
    if (_authorDao != null) return; // Already initialized

    _authorDao = AuthorDao(this);
    _bookAcronymDao = BookAcronymDao(this);
    _bookDao = BookDao(this);
    _bookHasLinksDao = BookHasLinksDao(this);
    _categoryDao = CategoryDao(this);
    _connectionTypeDao = ConnectionTypeDao(this);
    _lineDao = LineDao(this);
    _linkDao = LinkDao(this);
    _pubDateDao = PubDateDao(this);
    _pubPlaceDao = PubPlaceDao(this);
    _searchDao = SearchDao(this);
    _tocDao = TocDao(this);
    _tocTextDao = TocTextDao(this);
    _topicDao = TopicDao(this);
  }

  List<String> _getCreateScripts() {
    return [
      // Categories table
      '''
      CREATE TABLE IF NOT EXISTS category (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          parentId INTEGER,
          title TEXT NOT NULL,
          level INTEGER NOT NULL DEFAULT 0,
          orderIndex INTEGER NOT NULL DEFAULT 999,
          FOREIGN KEY (parentId) REFERENCES category(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_category_parent ON category(parentId);',
      'CREATE INDEX IF NOT EXISTS idx_category_order ON category(orderIndex);',

      // Category closure table
      '''
      CREATE TABLE IF NOT EXISTS category_closure (
          ancestorId INTEGER NOT NULL,
          descendantId INTEGER NOT NULL,
          PRIMARY KEY (ancestorId, descendantId),
          FOREIGN KEY (ancestorId) REFERENCES category(id) ON DELETE CASCADE,
          FOREIGN KEY (descendantId) REFERENCES category(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_category_closure_ancestor ON category_closure(ancestorId);',
      'CREATE INDEX IF NOT EXISTS idx_category_closure_descendant ON category_closure(descendantId);',

      // Authors table
      '''
      CREATE TABLE IF NOT EXISTS author (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_author_name ON author(name);',

      // Table des topics
      '''
      CREATE TABLE IF NOT EXISTS topic (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_topic_name ON topic(name);',

      // Publication places table
      '''
      CREATE TABLE IF NOT EXISTS pub_place (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_pub_place_name ON pub_place(name);',

      // Publication dates table
      '''
      CREATE TABLE IF NOT EXISTS pub_date (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT NOT NULL UNIQUE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_pub_date_date ON pub_date(date);',

      // Sources table
      '''
      CREATE TABLE IF NOT EXISTS source (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_source_name ON source(name);',

      // Books table
      '''
      CREATE TABLE IF NOT EXISTS book (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          categoryId INTEGER NOT NULL,
          sourceId INTEGER NOT NULL,
          title TEXT NOT NULL,
          heShortDesc TEXT,
          notesContent TEXT,
          orderIndex INTEGER NOT NULL DEFAULT 999,
          totalLines INTEGER NOT NULL DEFAULT 0,
          isBaseBook INTEGER NOT NULL DEFAULT 0,
          hasTargumConnection INTEGER NOT NULL DEFAULT 0,
          hasReferenceConnection INTEGER NOT NULL DEFAULT 0,
          hasSourceConnection INTEGER NOT NULL DEFAULT 0,
          hasCommentaryConnection INTEGER NOT NULL DEFAULT 0,
          hasOtherConnection INTEGER NOT NULL DEFAULT 0,
          hasAltStructures INTEGER NOT NULL DEFAULT 0,
          hasTeamim INTEGER NOT NULL DEFAULT 0,
          hasNekudot INTEGER NOT NULL DEFAULT 0,
          isContentExternal INTEGER DEFAULT 0,
          externalLibraryId TEXT DEFAULT NULL,
          isPersonal INTEGER DEFAULT 0,
          filePath TEXT DEFAULT NULL,
          fileType TEXT DEFAULT 'txt',
          fileSize INTEGER DEFAULT NULL,
          lastModified INTEGER DEFAULT NULL,
          FOREIGN KEY (categoryId) REFERENCES category(id) ON DELETE CASCADE,
          FOREIGN KEY (sourceId) REFERENCES source(id) ON DELETE RESTRICT
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_book_category ON book(categoryId);',
      'CREATE INDEX IF NOT EXISTS idx_book_title ON book(title);',
      'CREATE INDEX IF NOT EXISTS idx_book_order ON book(orderIndex);',
      'CREATE INDEX IF NOT EXISTS idx_book_source ON book(sourceId);',

      // Book-publication place junction table
      '''
      CREATE TABLE IF NOT EXISTS book_pub_place (
          bookId INTEGER NOT NULL,
          pubPlaceId INTEGER NOT NULL,
          PRIMARY KEY (bookId, pubPlaceId),
          FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
          FOREIGN KEY (pubPlaceId) REFERENCES pub_place(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_book_pub_place_book ON book_pub_place(bookId);',
      'CREATE INDEX IF NOT EXISTS idx_book_pub_place_place ON book_pub_place(pubPlaceId);',

      // Book-publication date junction table
      '''
      CREATE TABLE IF NOT EXISTS book_pub_date (
          bookId INTEGER NOT NULL,
          pubDateId INTEGER NOT NULL,
          PRIMARY KEY (bookId, pubDateId),
          FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
          FOREIGN KEY (pubDateId) REFERENCES pub_date(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_book_pub_date_book ON book_pub_date(bookId);',
      'CREATE INDEX IF NOT EXISTS idx_book_pub_date_date ON book_pub_date(pubDateId);',

      // Book-topic junction table
      '''
      CREATE TABLE IF NOT EXISTS book_topic (
          bookId INTEGER NOT NULL,
          topicId INTEGER NOT NULL,
          PRIMARY KEY (bookId, topicId),
          FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
          FOREIGN KEY (topicId) REFERENCES topic(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_book_topic_book ON book_topic(bookId);',
      'CREATE INDEX IF NOT EXISTS idx_book_topic_topic ON book_topic(topicId);',

      // Book-author junction table
      '''
      CREATE TABLE IF NOT EXISTS book_author (
          bookId INTEGER NOT NULL,
          authorId INTEGER NOT NULL,
          PRIMARY KEY (bookId, authorId),
          FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
          FOREIGN KEY (authorId) REFERENCES author(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_book_author_book ON book_author(bookId);',
      'CREATE INDEX IF NOT EXISTS idx_book_author_author ON book_author(authorId);',

      // Lines table
      '''
      CREATE TABLE IF NOT EXISTS line (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bookId INTEGER NOT NULL,
          lineIndex INTEGER NOT NULL,
          content TEXT NOT NULL,
          heRef TEXT,
          tocEntryId INTEGER,
          FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
          FOREIGN KEY (tocEntryId) REFERENCES tocEntry(id) ON DELETE SET NULL
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_line_book_index ON line(bookId, lineIndex);',
      'CREATE INDEX IF NOT EXISTS idx_line_toc ON line(tocEntryId);',
      'CREATE INDEX IF NOT EXISTS idx_line_heref ON line(heRef);',

      // TOC texts table
      '''
      CREATE TABLE IF NOT EXISTS tocText (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          text TEXT NOT NULL UNIQUE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_toc_text ON tocText(text);',
      'CREATE INDEX IF NOT EXISTS idx_toctext_text_length ON tocText(text, length(text));',

      // TOC entries table
      '''
      CREATE TABLE IF NOT EXISTS tocEntry (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bookId INTEGER NOT NULL,
          parentId INTEGER,
          textId INTEGER NOT NULL,
          level INTEGER NOT NULL,
          lineId INTEGER,
          lineIndex INTEGER,
          isLastChild INTEGER NOT NULL DEFAULT 0,
          hasChildren INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
          FOREIGN KEY (parentId) REFERENCES tocEntry(id) ON DELETE CASCADE,
          FOREIGN KEY (textId) REFERENCES tocText(id) ON DELETE CASCADE,
          FOREIGN KEY (lineId) REFERENCES line(id) ON DELETE SET NULL
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_toc_book ON tocEntry(bookId);',
      'CREATE INDEX IF NOT EXISTS idx_toc_parent ON tocEntry(parentId);',
      'CREATE INDEX IF NOT EXISTS idx_toc_text_id ON tocEntry(textId);',
      'CREATE INDEX IF NOT EXISTS idx_toc_line ON tocEntry(lineId);',
      'CREATE INDEX IF NOT EXISTS idx_tocentry_text_level ON tocEntry(textId, level);',
      'CREATE INDEX IF NOT EXISTS idx_tocentry_level_book ON tocEntry(level, bookId);',

      // Connection types table
      '''
      CREATE TABLE IF NOT EXISTS connection_type (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_connection_type_name ON connection_type(name);',

      // Links table
      '''
      CREATE TABLE IF NOT EXISTS link (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sourceBookId INTEGER NOT NULL,
          targetBookId INTEGER NOT NULL,
          sourceLineId INTEGER NOT NULL,
          targetLineId INTEGER NOT NULL,
          connectionTypeId INTEGER NOT NULL,
          FOREIGN KEY (sourceBookId) REFERENCES book(id) ON DELETE CASCADE,
          FOREIGN KEY (targetBookId) REFERENCES book(id) ON DELETE CASCADE,
          FOREIGN KEY (sourceLineId) REFERENCES line(id) ON DELETE CASCADE,
          FOREIGN KEY (targetLineId) REFERENCES line(id) ON DELETE CASCADE,
          FOREIGN KEY (connectionTypeId) REFERENCES connection_type(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_link_source_book ON link(sourceBookId);',
      'CREATE INDEX IF NOT EXISTS idx_link_source_line ON link(sourceLineId);',
      'CREATE INDEX IF NOT EXISTS idx_link_target_book ON link(targetBookId);',
      'CREATE INDEX IF NOT EXISTS idx_link_target_line ON link(targetLineId);',
      'CREATE INDEX IF NOT EXISTS idx_link_type ON link(connectionTypeId);',
      'CREATE INDEX IF NOT EXISTS idx_link_type_source_line ON link(connectionTypeId, sourceLineId);',

      // FTS5 removed - no longer using SQLite full-text search
      // View and virtual table have been removed

      // Table to track whether books have links (as source or target)
      '''
      CREATE TABLE IF NOT EXISTS book_has_links (
          bookId INTEGER PRIMARY KEY,
          hasSourceLinks INTEGER NOT NULL DEFAULT 0,
          hasTargetLinks INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_book_has_source_links ON book_has_links(hasSourceLinks);',
      'CREATE INDEX IF NOT EXISTS idx_book_has_target_links ON book_has_links(hasTargetLinks);',

      // Line to TOC mapping table
      '''
      CREATE TABLE IF NOT EXISTS line_toc (
          lineId INTEGER PRIMARY KEY,
          tocEntryId INTEGER NOT NULL,
          FOREIGN KEY (lineId) REFERENCES line(id) ON DELETE CASCADE,
          FOREIGN KEY (tocEntryId) REFERENCES tocEntry(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_linetoc_toc ON line_toc(tocEntryId);',

      // Book acronyms table
      '''
      CREATE TABLE IF NOT EXISTS book_acronym (
          bookId INTEGER NOT NULL,
          term TEXT NOT NULL,
          PRIMARY KEY (bookId, term),
          FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_book_acronym_term ON book_acronym(term);',

      // Alternative TOC structures (e.g., Parasha/Aliyah)
      '''
      CREATE TABLE IF NOT EXISTS alt_toc_structure (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bookId INTEGER NOT NULL,
          key TEXT NOT NULL,
          title TEXT,
          heTitle TEXT,
          UNIQUE (bookId, key),
          FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_alt_toc_structure_book ON alt_toc_structure(bookId);',
      'CREATE INDEX IF NOT EXISTS idx_alt_toc_structure_key ON alt_toc_structure(key);',

      // Alternative TOC entries
      '''
      CREATE TABLE IF NOT EXISTS alt_toc_entry (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          structureId INTEGER NOT NULL,
          parentId INTEGER,
          textId INTEGER NOT NULL,
          level INTEGER NOT NULL,
          lineId INTEGER,
          isLastChild INTEGER NOT NULL DEFAULT 0,
          hasChildren INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (structureId) REFERENCES alt_toc_structure(id) ON DELETE CASCADE,
          FOREIGN KEY (parentId) REFERENCES alt_toc_entry(id) ON DELETE CASCADE,
          FOREIGN KEY (textId) REFERENCES tocText(id) ON DELETE CASCADE,
          FOREIGN KEY (lineId) REFERENCES line(id) ON DELETE SET NULL
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_alt_toc_entry_structure ON alt_toc_entry(structureId);',
      'CREATE INDEX IF NOT EXISTS idx_alt_toc_entry_parent ON alt_toc_entry(parentId);',
      'CREATE INDEX IF NOT EXISTS idx_alt_toc_entry_text ON alt_toc_entry(textId);',
      'CREATE INDEX IF NOT EXISTS idx_alt_toc_entry_line ON alt_toc_entry(lineId);',

      // Line to alternative TOC mapping
      '''
      CREATE TABLE IF NOT EXISTS line_alt_toc (
          lineId INTEGER NOT NULL,
          structureId INTEGER NOT NULL,
          altTocEntryId INTEGER NOT NULL,
          PRIMARY KEY (lineId, structureId),
          FOREIGN KEY (lineId) REFERENCES line(id) ON DELETE CASCADE,
          FOREIGN KEY (structureId) REFERENCES alt_toc_structure(id) ON DELETE CASCADE,
          FOREIGN KEY (altTocEntryId) REFERENCES alt_toc_entry(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_line_alt_toc_entry ON line_alt_toc(altTocEntryId);',
      'CREATE INDEX IF NOT EXISTS idx_line_alt_toc_structure ON line_alt_toc(structureId);',

      // Default commentators table
      '''
      CREATE TABLE IF NOT EXISTS default_commentator (
          bookId INTEGER NOT NULL,
          commentatorBookId INTEGER NOT NULL,
          position INTEGER NOT NULL,
          PRIMARY KEY (bookId, commentatorBookId),
          FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
          FOREIGN KEY (commentatorBookId) REFERENCES book(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_default_commentator_book ON default_commentator(bookId);',
      'CREATE INDEX IF NOT EXISTS idx_default_commentator_commentator ON default_commentator(commentatorBookId);',

      // Default targum table
      '''
      CREATE TABLE IF NOT EXISTS default_targum (
          bookId INTEGER NOT NULL,
          targumBookId INTEGER NOT NULL,
          position INTEGER NOT NULL,
          PRIMARY KEY (bookId, targumBookId),
          FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
          FOREIGN KEY (targumBookId) REFERENCES book(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_default_targum_book ON default_targum(bookId);',
      'CREATE INDEX IF NOT EXISTS idx_default_targum_target ON default_targum(targumBookId);',
    ];
  }
}
