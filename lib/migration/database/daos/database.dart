import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'author_dao.dart';
import 'book_acronym_dao.dart';
import 'book_dao.dart';
import 'book_has_links_dao.dart';
import 'category_dao.dart';
import 'connection_type_dao.dart';
import 'docx_text_cache_dao.dart';
import 'generation_dao.dart';
import 'line_dao.dart';
import 'link_dao.dart';
import 'pdf_anchor_cache_dao.dart';
import 'pdf_outline_cache_dao.dart';
import 'pub_date_dao.dart';
import 'pub_place_dao.dart';
import 'search_dao.dart';
import 'toc_dao.dart';
import 'toc_text_dao.dart';
import 'topic_dao.dart';
import '../sql/query_loader.dart';

class MyDatabase {
  // הקובץ מוחזק ברמת המופע, לא static. זה מאפשר ליצור כמה מופעים
  // (למשל seforim.db לצד user_books.db) שלא יתנגשו זה בזה.
  sqlite3.Database? _database;
  final String _path;

  /// כשהוא true, ה-DB נפתח read-only: ללא יצירת קובצי WAL, ללא DDL
  /// (`CREATE TABLE`), ועם `PRAGMA query_only=ON`. משמש כדי לפתוח את
  /// `seforim.db` הרשמי בלי לדרוש הרשאת כתיבה. ברירת המחדל היא כתיב
  /// (false) כדי לשמר את התנהגות user_books.db / cache.db / ה-generator.
  final bool _readOnly;

  /// האם החיבור נפתח במצב read-only.
  bool get isReadOnly => _readOnly;

  // (no platform initialization required – sqlite3 handles all platforms natively)

  // DAOs
  AuthorDao? _authorDao;
  BookAcronymDao? _bookAcronymDao;
  BookDao? _bookDao;
  BookHasLinksDao? _bookHasLinksDao;
  CategoryDao? _categoryDao;
  ConnectionTypeDao? _connectionTypeDao;
  DocxTextCacheDao? _docxTextCacheDao;
  GenerationDao? _generationDao;
  LineDao? _lineDao;
  LinkDao? _linkDao;
  PdfAnchorCacheDao? _pdfAnchorCacheDao;
  PdfOutlineCacheDao? _pdfOutlineCacheDao;
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

  DocxTextCacheDao get docxTextCacheDao {
    _ensureDaosInitialized();
    return _docxTextCacheDao!;
  }

  GenerationDao get generationDao {
    _ensureDaosInitialized();
    return _generationDao!;
  }

  LineDao get lineDao {
    _ensureDaosInitialized();
    return _lineDao!;
  }

  LinkDao get linkDao {
    _ensureDaosInitialized();
    return _linkDao!;
  }

  PdfAnchorCacheDao get pdfAnchorCacheDao {
    _ensureDaosInitialized();
    return _pdfAnchorCacheDao!;
  }

  PdfOutlineCacheDao get pdfOutlineCacheDao {
    _ensureDaosInitialized();
    return _pdfOutlineCacheDao!;
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

  /// יוצרת מופע MyDatabase שמצביע על נתיב DB ספציפי.
  ///
  /// כל מופע מחזיק את ה-connection וה-DAOs שלו, כך שניתן להריץ
  /// בו-זמנית את seforim.db ואת user_books.db ללא התנגשויות.
  /// אין סינגלטון ברירת-מחדל — כל קוד הצורך גישה ל-seforim.db עובר דרך
  /// [SqliteDataProvider], וקוד הצורך גישה ל-user_books.db דרך
  /// [UserBooksDatabaseHolder].
  MyDatabase.withPath(String path, {this._readOnly = false}) : _path = path;

  Future<sqlite3.Database> get database async {
    if (_database != null) return _database!;
    // Initialize QueryLoader before creating DAOs
    await QueryLoader.initialize();
    _database = _initDatabase();
    _initializeDaos();
    return _database!;
  }

  sqlite3.Database _initDatabase() {
    if (_readOnly) {
      // Read-only open: never create WAL side-files (-wal/-shm) and never run
      // DDL. This lets seforim.db be opened from read-only media / without
      // write permission. Assumes the file is already in a rollback journal
      // mode (DELETE) — SqliteDataProvider normalises it before opening.
      final db = sqlite3.sqlite3.open(_path, mode: sqlite3.OpenMode.readOnly);
      try {
        db.execute('PRAGMA query_only=ON');
      } catch (_) {}
      return db;
    }

    final db = sqlite3.sqlite3.open(_path);

    // Wait-and-retry on lock contention instead of failing immediately with
    // SQLITE_BUSY (code 5). Without this, a transient lock — e.g. a second app
    // instance, a stale -wal/-shm, or the schema-creation write racing another
    // connection — surfaces as "database is locked" on the very first DDL.
    db.execute('PRAGMA busy_timeout=5000');

    // Enable WAL for concurrent read/write access (uniform across all platforms).
    // May fail if another process holds the DB lock (e.g. second instance or stale lock).
    // WAL is an optimisation only — safe to skip on failure.
    try {
      db.execute('PRAGMA journal_mode=WAL');
    } catch (_) {}

    // Ensure schema exists (all scripts use CREATE TABLE/INDEX IF NOT EXISTS).
    for (final script in _getCreateScripts()) {
      db.execute(script);
      if (script.contains('CREATE TABLE IF NOT EXISTS generation')) {
        _ensureGenerationSchema(db);
      } else if (script.contains('CREATE TABLE IF NOT EXISTS author')) {
        _ensureAuthorSchema(db);
      } else if (script.contains('CREATE TABLE IF NOT EXISTS user_link')) {
        _ensureUserLinkSchema(db);
      }
    }

    return db;
  }

  void _ensureGenerationSchema(sqlite3.Database db) {
    final columns = db
        .select('PRAGMA table_info(generation)')
        .map((row) => row['name'] as String)
        .toSet();

    if (!columns.contains('startYear')) {
      db.execute('ALTER TABLE generation ADD COLUMN startYear INTEGER');
    }
    if (!columns.contains('endYear')) {
      db.execute('ALTER TABLE generation ADD COLUMN endYear INTEGER');
    }
    if (!columns.contains('parentGenerationId')) {
      db.execute(
        'ALTER TABLE generation ADD COLUMN parentGenerationId INTEGER',
      );
    }
  }

  void _ensureAuthorSchema(sqlite3.Database db) {
    final columns = db
        .select('PRAGMA table_info(author)')
        .map((row) => row['name'] as String)
        .toSet();

    if (!columns.contains('generationId')) {
      db.execute('ALTER TABLE author ADD COLUMN generationId INTEGER');
    }
  }

  /// משדרג user_link מהסכמה הישנה (מקור=FK sourceBookId לספר אישי) לסכמה
  /// חוצה-DB (מקור לפי כותרת+דגל). מריצים לפני יצירת האינדקסים החדשים כי הם
  /// מתייחסים לעמודות החדשות. שורות קיימות נשמרות כמקור אישי (הסמנטיקה הישנה).
  void _ensureUserLinkSchema(sqlite3.Database db) {
    final columns = db
        .select('PRAGMA table_info(user_link)')
        .map((row) => row['name'] as String)
        .toSet();
    if (columns.contains('sourceTitle')) return;

    db.execute('''
      CREATE TABLE user_link_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sourceTitle TEXT NOT NULL,
          sourceCategoryId INTEGER,
          sourceIsUserBook INTEGER NOT NULL DEFAULT 0,
          sourceLineIndex INTEGER NOT NULL,
          targetTitle TEXT NOT NULL,
          targetCategoryId INTEGER,
          targetIsUserBook INTEGER NOT NULL DEFAULT 0,
          targetRef TEXT,
          targetLineIndex INTEGER,
          connectionType TEXT NOT NULL
      );
    ''');
    db.execute('''
      INSERT INTO user_link_new (sourceTitle, sourceCategoryId, sourceIsUserBook,
          sourceLineIndex, targetTitle, targetCategoryId, targetIsUserBook,
          targetRef, targetLineIndex, connectionType)
      SELECT b.title, b.categoryId, 1, ul.sourceLineIndex, ul.targetTitle,
          ul.targetCategoryId, ul.targetIsUserBook, ul.targetRef,
          ul.targetLineIndex, ul.connectionType
      FROM user_link ul JOIN book b ON b.id = ul.sourceBookId;
    ''');
    db.execute('DROP TABLE user_link');
    db.execute('ALTER TABLE user_link_new RENAME TO user_link');
  }

  void close() {
    _database?.close();
    _database = null;
  }

  void _initializeDaos() {
    if (_authorDao != null) return; // Already initialized

    _authorDao = AuthorDao(this);
    _bookAcronymDao = BookAcronymDao(this);
    _bookDao = BookDao(this);
    _bookHasLinksDao = BookHasLinksDao(this);
    _categoryDao = CategoryDao(this);
    _connectionTypeDao = ConnectionTypeDao(this);
    _docxTextCacheDao = DocxTextCacheDao(this);
    _generationDao = GenerationDao(this);
    _lineDao = LineDao(this);
    _linkDao = LinkDao(this);
    _pdfAnchorCacheDao = PdfAnchorCacheDao(this);
    _pdfOutlineCacheDao = PdfOutlineCacheDao(this);
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

      // Generations table
      '''
        CREATE TABLE IF NOT EXISTS generation (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          startYear INTEGER,
          endYear INTEGER,
          parentGenerationId INTEGER,
          FOREIGN KEY (parentGenerationId) REFERENCES generation(id),
          CHECK (startYear IS NULL OR endYear IS NULL OR startYear <= endYear)
        );
        ''',
      'CREATE INDEX IF NOT EXISTS idx_generation_name ON generation(name);',
      'CREATE INDEX IF NOT EXISTS idx_generation_start_year ON generation(startYear);',
      'CREATE INDEX IF NOT EXISTS idx_generation_end_year ON generation(endYear);',
      'CREATE INDEX IF NOT EXISTS idx_generation_parent ON generation(parentGenerationId);',

      // Authors table
      '''
        CREATE TABLE IF NOT EXISTS author (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          generationId INTEGER,
          FOREIGN KEY (generationId) REFERENCES generation(id) ON DELETE SET NULL
        );
        ''',
      'CREATE INDEX IF NOT EXISTS idx_author_name ON author(name);',
      'CREATE INDEX IF NOT EXISTS idx_author_generation ON author(generationId);',

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
          pages INTEGER DEFAULT NULL,
          volume TEXT DEFAULT NULL,
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

      // DB meta table
      '''
        CREATE TABLE IF NOT EXISTS db_meta (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        ''',
      'CREATE INDEX IF NOT EXISTS idx_db_meta_key ON db_meta(key);',

      // Persistent cache for outlines of external PDF files
      '''
        CREATE TABLE IF NOT EXISTS pdf_outline_cache (
          filePath TEXT PRIMARY KEY,
          fileSize INTEGER NOT NULL,
          lastModified INTEGER NOT NULL,
          outlineJson TEXT NOT NULL,
          createdAt INTEGER NOT NULL,
          accessedAt INTEGER NOT NULL
        );
        ''',
      'CREATE INDEX IF NOT EXISTS idx_pdf_outline_cache_accessed_at ON pdf_outline_cache(accessedAt);',

      // Persistent cache of PDF page-map anchors (text<->PDF page conversion)
      '''
        CREATE TABLE IF NOT EXISTS pdf_anchor_cache (
          filePath TEXT PRIMARY KEY,
          fileSize INTEGER NOT NULL,
          lastModified INTEGER NOT NULL,
          anchorsJson TEXT NOT NULL,
          createdAt INTEGER NOT NULL,
          accessedAt INTEGER NOT NULL
        );
        ''',
      'CREATE INDEX IF NOT EXISTS idx_pdf_anchor_cache_accessed_at ON pdf_anchor_cache(accessedAt);',

      // Persistent cache of converted external DOCX text (populated in cache.db)
      '''
        CREATE TABLE IF NOT EXISTS docx_text_cache (
          filePath TEXT PRIMARY KEY,
          fileSize INTEGER NOT NULL,
          lastModified INTEGER NOT NULL,
          converterVersion INTEGER NOT NULL DEFAULT 0,
          text TEXT NOT NULL,
          createdAt INTEGER NOT NULL,
          accessedAt INTEGER NOT NULL
        );
        ''',
      'CREATE INDEX IF NOT EXISTS idx_docx_text_cache_accessed_at ON docx_text_cache(accessedAt);',

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

      // Book ↔ generation (זהה ל-seforim.db). ב-seforim.db נבנה חיצונית;
      // כאן נוצר עבור user_books.db כדי שספר אישי יקבל דור דרך אותו מסלול.
      '''
      CREATE TABLE IF NOT EXISTS book_generation (
          bookId INTEGER NOT NULL,
          generationId INTEGER NOT NULL,
          PRIMARY KEY (bookId, generationId),
          FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
          FOREIGN KEY (generationId) REFERENCES generation(id) ON DELETE CASCADE
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_book_generation_generation ON book_generation(generationId);',

      // קישורי-משתמש שיובאו מ-CSV. גם המקור וגם היעד מזוהים לפי כותרת+דגל
      // (לא FK שלם), כדי לתמוך בקישור חוצה-DB בשני הצדדים — כולל ספר רשמי
      // כמקור — בלי לכתוב ל-seforim.db (FK חוצה-קבצים אינו אפשרי).
      '''
      CREATE TABLE IF NOT EXISTS user_link (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sourceTitle TEXT NOT NULL,
          sourceCategoryId INTEGER,
          sourceIsUserBook INTEGER NOT NULL DEFAULT 0,
          sourceLineIndex INTEGER NOT NULL,
          targetTitle TEXT NOT NULL,
          targetCategoryId INTEGER,
          targetIsUserBook INTEGER NOT NULL DEFAULT 0,
          targetRef TEXT,
          targetLineIndex INTEGER,
          connectionType TEXT NOT NULL
      );
      ''',
      'CREATE INDEX IF NOT EXISTS idx_user_link_source ON user_link(sourceTitle, sourceIsUserBook);',
      'CREATE INDEX IF NOT EXISTS idx_user_link_target ON user_link(targetTitle, targetIsUserBook);',
    ];
  }
}
