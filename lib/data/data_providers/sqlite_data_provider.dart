import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/models/model_adapters.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException, sqlite3;

/// A data provider that manages SQLite database operations for the library.
///
/// This class handles all database related operations including:
/// - Reading book content from the database
/// - Managing the library structure (categories and books)
/// - Providing table of contents functionality
/// - Falling back to file system when data is not in database
class SqliteDataProvider {
  late SeforimRepository _repository;
  // לא late: withWritableSession/optimizeDatabase עשויים להיקרא לפני initialize.
  String _dbPath = '';
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  /// Singleton instance
  static SqliteDataProvider? _instance;

  SqliteDataProvider._();

  static SqliteDataProvider get instance {
    _instance ??= SqliteDataProvider._();
    return _instance!;
  }

  /// Factory לבדיקות בלבד: יוצר provider עם repository מוזרק ומסומן כמאותחל.
  @visibleForTesting
  factory SqliteDataProvider.withRepository(SeforimRepository repository) {
    final provider = SqliteDataProvider._();
    provider._repository = repository;
    provider._isInitialized = true;
    return provider;
  }

  /// Initializes the database connection
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    // אם יש write-session פעיל, החיבור ה-RO סגור בכוונה. אסור לפתוח אותו
    // מחדש כאן במקביל לחיבור ה-RW (היה גורם ל"database locked"). ממתינים
    // לסיום שרשרת הכתיבה *וגם* ל-gate של כתיבה חיצונית — שניהם פותחים מחדש
    // את ה-RO בעצמם. כך קוראים שמגיעים בחלון הזה (למשל טעינת מפרשים/קישורים
    // ברקע בעלייה) ממתינים לפתיחה-מחדש ומצליחים, במקום לקבל null ולהציג ריק.
    if (_activeWriteSessions > 0) {
      try {
        await _writeChain;
      } catch (e) {
        // השגיאה עצמה מטופלת אצל מי שהריץ את הכתיבה; כאן רק ממתינים לסיום.
        debugPrint('[SqliteDataProvider] write chain ended with error: $e');
      }
      // ממתינים לפתיחה-מחדש של ה-RO ע"י ה-session — אך בפעימות עם תקרת זמן,
      // לא בהמתנה אינסופית. ההמתנה הישנה (await gate.future ללא תקרה) קפאה
      // לנצח אם reopen התעכב/התפספס (כתיבות חופפות בעלייה, איזולייט שקרס),
      // והקורא נתקע על מסך עיון/תצוגה מקדימה ריקים עד restart. עכשיו: אם
      // הפתיחה-מחדש קורית — gate.future מסתיים והלולאה יוצאת מיד (גם אחרי
      // כמה שניות); אם היא משתהה מעבר לתקרה — מפסיקים את ההמתנה ומחזירים
      // null פעם אחת (הקורא הבא יצליח) במקום להיתקע.
      var polls = 0;
      for (; _activeWriteSessions > 0 && !_isInitialized; polls++) {
        if (polls >= _maxExternalWriteWaitPolls) {
          // אנומליה: חרגנו מתקרת ההמתנה וה-session עדיין פעיל — חשד לדליפת
          // write-session (close בלי reopen תואם). הקורא לא נתקע (חוזר למטה),
          // אבל קריאות ימשיכו לקבל ריק עד restart. אם השורה הזו מופיעה בלוג —
          // יש לאתר את ה-close שלא קיבל reopen.
          debugPrint(
            '⚠️ [SqliteDataProvider] initialize() חרג מתקרת ההמתנה '
            'ל-gate ($_activeWriteSessions write-sessions פעילים, '
            '_externalWriteGate=${_externalWriteGate == null ? "null" : "ממתין"}). '
            'חשד לדליפת write-session — קריאות יקבלו ריק עד פתיחה-מחדש.',
          );
          break;
        }
        final gate = _externalWriteGate;
        if (gate == null) break;
        try {
          await gate.future.timeout(_externalWriteWaitPollInterval);
        } catch (_) {}
      }
      // אם החיבור נפתח מחדש — סיימנו. אם עדיין יש session פעיל (חפיפה או
      // השתהות מעבר לתקרה) — מוותרים זמנית. אחרת נופלים לאתחול הרגיל למטה.
      if (_isInitialized || _activeWriteSessions > 0) {
        return;
      }
    }

    // If initialization already started, await the same future
    if (_initializationFuture != null) {
      return _initializationFuture!;
    }

    _initializationFuture = _initializeInternal();

    try {
      await _initializationFuture;
    } finally {
      _initializationFuture = null;
    }
  }

  Future<void> _initializeInternal() async {
    // Use centralized database path
    _dbPath = DatabaseConstants.getDatabasePath();

    // Check if database file exists
    final dbFile = File(_dbPath);
    if (!await dbFile.exists()) {
      // Database will be created when first book is migrated
      return;
    }

    // seforim.db נפתח read-only כברירת מחדל. עדכוני ספרייה (sync/generator/
    // מחיקה) פותחים חיבור כתיב זמני דרך [withWritableSession]. לפני הפתיחה
    // ה-read-only יש לוודא שהקובץ אינו במצב WAL — אחרת SQLite לא יוכל לפתוח
    // אותו ללא יצירת קובצי -wal/-shm (שדורשים הרשאת כתיבה).
    await _normalizeJournalModeForReadOnly(_dbPath);

    try {
      final database = MyDatabase.withPath(_dbPath, readOnly: true);
      _repository = SeforimRepository(database);
      await _repository.ensureInitialized();
      _isInitialized = true;
    } on SqliteException catch (e) {
      // SQLITE_CANTOPEN (code 14): the native library cannot open the file.
      // On Android this happens when the DB is in Scoped Storage and sqlite3
      // native cannot access it via a raw file path.
      // Clear any stale keyDbEffectivePath so that the next
      // checkLibraryIsEmpty() returns true and the user reaches the
      // "select library" screen where the copy-to-internal flow is offered.
      if (Platform.isAndroid && e.resultCode == 14) {
        debugPrint(
          '[SqliteDataProvider] SQLITE_CANTOPEN on Android — '
          'clearing keyDbEffectivePath to trigger library-selection flow.',
        );
        await Settings.setValue(SettingsRepository.keyDbEffectivePath, '');
        // Do NOT rethrow: returning without _isInitialized = true causes the
        // app to treat the DB as missing and show the empty-library screen.
        return;
      }
      debugPrint('Error initializing SQLite database: $e');
      rethrow;
    } catch (e) {
      debugPrint('Error initializing SQLite database: $e');
      rethrow;
    }
  }

  /// Checks if the database is initialized and ready
  bool get isInitialized => _isInitialized;

  /// Closes the database connection to free resources
  Future<void> dispose() async {
    if (_isInitialized) {
      _repository.database.close();
      _isInitialized = false;
    }
  }

  /// שרשרת לסריאליזציה של write-sessions — מבטיחה שלא ירוצו שתי כתיבות
  /// במקביל על seforim.db.
  Future<void> _writeChain = Future<void>.value();

  /// מספר ה-write-sessions הפעילים. כשהוא > 0 חיבור ה-RO סגור ו-[initialize]
  /// לא יפתח אותו מחדש (כדי לא להתנגש עם חיבור ה-RW). יורד רק לאחר שה-session
  /// פתח מחדש את ה-RO.
  int _activeWriteSessions = 0;

  /// gate לכתיבה חיצונית (isolate סנכרון/generator) — נוצר ב-
  /// [closeForExternalWrite] ומושלם ב-[reopenAfterExternalWrite]. קוראים
  /// מקבילים ממתינים עליו ב-[initialize] במקום לקבל null, כדי שספרים/מפרשים
  /// לא ייטענו ריקים כשקריאת רקע מתנגשת עם חלון הסנכרון בעלייה.
  Completer<void>? _externalWriteGate;

  /// אורך פעימת המתנה בודדת ל-gate ב-[initialize]. ההמתנה מתעוררת מיד כש-
  /// reopen משלים את ה-gate; התקרה כאן רק מבטיחה שקורא לא ייתקע לנצח אם
  /// reopen מתעכב/מתפספס. ניתן לעקיפה בטסטים דרך [debugSetExternalWriteWait].
  Duration _externalWriteWaitPollInterval = const Duration(seconds: 2);

  /// מספר פעימות מרבי להמתנה ל-gate. מכפלת [_externalWriteWaitPollInterval]
  /// נותנת את תקרת ההמתנה הכוללת (כיום ~30ש') — מספיק ארוך לסנכרון לגיטימי
  /// בעלייה, ועדיין חוסם קיפאון לצמיתות בדליפת session.
  int _maxExternalWriteWaitPolls = 15;

  /// עקיפת פרמטרי ההמתנה ל-gate בטסטים בלבד, כדי לבדוק את חסימת הקיפאון
  /// בלי להמתין את התקרה המלאה (~30ש').
  @visibleForTesting
  void debugSetExternalWriteWait({
    Duration? pollInterval,
    int? maxPolls,
  }) {
    if (pollInterval != null) _externalWriteWaitPollInterval = pollInterval;
    if (maxPolls != null) _maxExternalWriteWaitPolls = maxPolls;
  }

  /// מנרמל את מצב היומן של [dbPath] ל-DELETE (best-effort) כדי שניתן יהיה
  /// לפתוח אותו read-only.
  ///
  /// התקנות קיימות שמרו את seforim.db במצב WAL. פתיחת קובץ WAL ב-read-only
  /// דורשת יצירת קובצי -wal/-shm (כתיבה לתיקייה). פתיחה כתיבה חד-פעמית כאן,
  /// checkpoint, והמרה ל-DELETE פותרים זאת. אם התיקייה אינה כתיבה (מדיה
  /// read-only אמיתית) — נכשל בשקט; הקובץ המופץ כבר במצב DELETE.
  Future<void> _normalizeJournalModeForReadOnly(String dbPath) async {
    try {
      final file = File(dbPath);
      if (!await file.exists()) return;

      // זיהוי מצב היומן דרך כותרת SQLite — בייטים 18/19 (write/read format
      // version): 1 = rollback (DELETE/TRUNCATE), 2 = WAL. זו קריאת בייטים
      // בלבד, ללא פתיחת DB ולכן ללא כתיבה. רוב ההתקנות (וה-DB המופץ) כבר
      // ב-rollback, ולכן ב-runtime רגיל לא נפתח כלל חיבור RW.
      bool isWal;
      final raf = await file.open();
      try {
        await raf.setPosition(18);
        final header = await raf.read(2);
        isWal = header.length == 2 && (header[0] == 2 || header[1] == 2);
      } finally {
        await raf.close();
      }

      // יומן rollback "חם": קובץ -journal לא-ריק שנותר מכתיבה שנקטעה (סגירת
      // התוכנה באמצע עדכון ספרייה). פתיחת RO על מצב כזה נכשלת ב-
      // SQLITE_READONLY_ROLLBACK (776) כי RO אינו יכול להריץ את ה-rollback.
      final journal = File('$dbPath-journal');
      final hasHotJournal =
          await journal.exists() && (await journal.length()) > 0;

      if (!isWal && !hasHotJournal) return;

      // פתיחת RW זמנית: ממירה WAL→DELETE, וגישתה הראשונה למסד מריצה את
      // ה-rollback של יומן חם — שניהם מאפשרים את הפתיחה ה-RO שאחריה.
      final db = sqlite3.open(dbPath);
      try {
        try {
          db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        } catch (_) {}
        db.execute('PRAGMA journal_mode=DELETE');
      } finally {
        db.close();
      }
    } catch (e) {
      debugPrint(
        '[SqliteDataProvider] Could not normalise journal mode '
        '(directory may be read-only): $e',
      );
    }
  }

  /// מריץ פעולת כתיבה על seforim.db דרך חיבור כתיב זמני, ואז חוזר ל-read-only.
  ///
  /// בזמן רגיל seforim.db פתוח read-only. כדי לעדכן את הספרייה (הוספת/מחיקת
  /// ספרים, generator) נדרשת כתיבה: המתודה סוגרת את חיבור ה-RO, פותחת חיבור
  /// RW מלא (כולל WAL ו-DDL), מריצה את [action] עם ה-repository הכתיב, מבצעת
  /// checkpoint והמרה חזרה ל-DELETE, ואז מאתחלת מחדש את חיבור ה-RO.
  ///
  /// קריאות מקבילות מסונכרנות דרך שרשרת פנימית כדי למנוע שתי כתיבות במקביל.
  Future<T> withWritableSession<T>(
    Future<T> Function(SeforimRepository repository) action,
  ) {
    // מסומן כפעיל באופן סינכרוני כדי שקריאות מקבילות שיגיעו מיד יזהו את
    // ה-session ולא ינסו לפתוח חיבור RO מתנגש. יורד רק לאחר שה-session
    // (כולל פתיחת ה-RO מחדש ב-finally) הסתיים.
    _activeWriteSessions++;
    final result = _writeChain.then((_) => _runWritableSession(action));
    // שומר את השרשרת חיה גם בכשל, בלי להדליף שגיאות לקריאה הבאה.
    _writeChain = result.then((_) {}, onError: (_) {});
    return result.whenComplete(() {
      _activeWriteSessions--;
    });
  }

  Future<T> _runWritableSession<T>(
    Future<T> Function(SeforimRepository repository) action,
  ) async {
    final dbPath = _dbPath.isNotEmpty
        ? _dbPath
        : DatabaseConstants.getDatabasePath();

    // שחרור חיבור ה-RO כדי לפנות את נעילת הקובץ.
    if (_isInitialized) {
      _repository.database.close();
      _isInitialized = false;
    }

    final writableDb = MyDatabase.withPath(dbPath, readOnly: false);
    final writableRepo = SeforimRepository(writableDb);
    try {
      await writableRepo.ensureInitialized();
      final result = await action(writableRepo);
      // checkpoint + המרה ל-DELETE כדי שהפתיחה ה-RO הבאה לא תצטרך -wal/-shm.
      try {
        await writableRepo.executeRawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (e) {
        debugPrint('[SqliteDataProvider] wal_checkpoint failed: $e');
      }
      try {
        await writableRepo.setJournalMode('DELETE');
      } catch (e) {
        debugPrint('[SqliteDataProvider] setJournalMode(DELETE) failed: $e');
      }
      return result;
    } finally {
      writableDb.close();
      // פתיחה מחדש read-only ישירות דרך _initializeInternal — לא דרך
      // initialize(), כי זו ממתינה ל-_writeChain שכולל את ה-session הזה
      // עצמו (deadlock). עוטפים ב-try כדי לא להסוות שגיאה מקורית מה-action.
      try {
        await _initializeInternal();
      } catch (e) {
        debugPrint(
          '[SqliteDataProvider] Failed to re-open RO connection after '
          'write session: $e',
        );
      }
    }
  }

  /// סוגר את חיבור ה-RO לפני שאיזולייט חיצוני (diff-sync / background sync)
  /// פותח את seforim.db לכתיבה, כדי שלא תתפוס נעילת קובץ מתנגשת.
  ///
  /// מסמן write-session פעיל (כמו [withWritableSession]) כדי ש-[initialize]
  /// של קוראים מקבילים לא יפתח חיבור RO מתנגש בזמן שהאיזולייט כותב.
  /// יש לקרוא ל-[reopenAfterExternalWrite] לאחר שהאיזולייט סיים.
  Future<void> closeForExternalWrite() async {
    // נוצר *לפני* הגדלת המונה, כך שקורא מקביל שיראה _activeWriteSessions > 0
    // תמיד יראה גם gate להמתין עליו.
    _externalWriteGate ??= Completer<void>();
    _activeWriteSessions++;
    await dispose();
  }

  /// פותח מחדש את seforim.db read-only לאחר שאיזולייט חיצוני סיים לכתוב.
  Future<void> reopenAfterExternalWrite() async {
    if (_activeWriteSessions > 0) {
      _activeWriteSessions--;
    }
    // אם עדיין יש כתיבה חיצונית פעילה (close-ים חופפים), אסור לפתוח מחדש
    // עכשיו — חיבור ה-RW האחר עדיין כותב. נפתח רק כשהאחרון מסיים.
    if (_activeWriteSessions > 0) {
      return;
    }
    try {
      // המונה כבר 0, ולכן initialize() לא ייכנס לבלוק ההמתנה ל-gate (אין
      // deadlock), ומנגנון _initializationFuture מונע פתיחה כפולה מול קורא מקביל.
      await initialize();
    } finally {
      // משחררים את הקוראים הממתינים. ה-finally מבטיח שחרור גם אם הפתיחה-מחדש
      // נכשלה (אחרת היו נתקעים לנצח).
      final gate = _externalWriteGate;
      _externalWriteGate = null;
      if (gate != null && !gate.isCompleted) {
        gate.complete();
      }
    }
  }

  /// Checks if a book exists in the database
  Future<bool> isBookInDatabase(
    String title, [
    int? categoryId,
    String? fileType,
  ]) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return false;

    try {
      final resolvedBook = await _resolveBookRecord(
        title,
        categoryId: categoryId,
        fileType: fileType,
      );
      return resolvedBook != null;
    } catch (e, st) {
      debugPrint(
        '[SqliteDataProvider] isBookInDatabase failed for "$title": '
        '$e\n$st',
      );
      return false;
    }
  }

  /// Retrieves quick preview of a book (40 lines around position) for instant display
  Future<String?> getBookQuickPreview(
    String title,
    int currentLine, {
    int? categoryId,
    String? fileType,
    bool preferUserBooks = false,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      final resolvedBook = await _resolveBookRecord(
        title,
        categoryId: categoryId,
        fileType: fileType,
        preferUserBooks: preferUserBooks,
      );
      if (resolvedBook == null) return null;
      final book = resolvedBook.book;

      // Load 10 lines before and 10 after (20 total)
      final startLine = (currentLine - 10).clamp(0, book.totalLines - 1);
      final endLine = (currentLine + 10).clamp(0, book.totalLines - 1);

      final lines = await resolvedBook.repository.getLines(
        book.id,
        startLine,
        endLine,
      );
      return migrationLinesToText(lines);
    } catch (e, st) {
      debugPrint(
        '[SqliteDataProvider] getBookQuickPreview failed for '
        '"$title": $e\n$st',
      );
      return null;
    }
  }

  Future<({int startLine, int endLine, int totalLines, String text})?>
  getBookTextRangeFromDb(
    String title, {
    required int startLine,
    required int endLine,
    int? categoryId,
    String? fileType,
    bool preferUserBooks = false,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      final resolvedBook = await _resolveBookRecord(
        title,
        categoryId: categoryId,
        fileType: fileType,
        preferUserBooks: preferUserBooks,
      );
      if (resolvedBook == null || resolvedBook.book.totalLines <= 0) {
        return null;
      }
      final book = resolvedBook.book;

      final normalizedStart = startLine.clamp(0, book.totalLines - 1);
      final normalizedEnd = endLine.clamp(normalizedStart, book.totalLines - 1);
      final lines = await resolvedBook.repository.getLines(
        book.id,
        normalizedStart,
        normalizedEnd,
      );

      return (
        startLine: normalizedStart,
        endLine: normalizedEnd,
        totalLines: book.totalLines,
        text: migrationLinesToText(lines),
      );
    } catch (e, st) {
      debugPrint(
        '[SqliteDataProvider] getBookTextRangeFromDb failed for '
        '"$title": $e\n$st',
      );
      return null;
    }
  }

  /// Retrieves the full text content of a book from the database
  Future<String?> getBookTextFromDb(
    String title, [
    int? categoryId,
    String? fileType,
    bool preferUserBooks = false,
  ]) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      final resolvedBook = await _resolveBookRecord(
        title,
        categoryId: categoryId,
        fileType: fileType,
        preferUserBooks: preferUserBooks,
      );
      if (resolvedBook == null) return null;
      final book = resolvedBook.book;

      // מסלול רזה: תוכן בלבד, בלי בניית Map ואובייקט Line לכל שורה —
      // האינדוקס (הקורא הכבד ביותר של טקסט מלא) רק מאחה שורות לטקסט אחד.
      final lines = await resolvedBook.repository.getLineContents(book.id);
      if (lines.isEmpty) return null;
      return lines.join('\n');
    } catch (e, st) {
      debugPrint(
        '[SqliteDataProvider] getBookTextFromDb failed for '
        '"$title": $e\n$st',
      );
      return null;
    }
  }

  /// כמו [getBookTextFromDb], אבל כבייטים גולמיים (UTF-8 כפי שמאוחסן),
  /// מאוחים ב-`\n` — מסלול האינדוקס מעביר אותם למנוע כמות-שהם
  /// (addTextBookBytes) בלי פענוח ל-String וקידוד חוזר על גשר ה-FFI.
  Future<Uint8List?> getBookTextBytesFromDb(
    String title, [
    int? categoryId,
    String? fileType,
    bool preferUserBooks = false,
  ]) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      final resolvedBook = await _resolveBookRecord(
        title,
        categoryId: categoryId,
        fileType: fileType,
        preferUserBooks: preferUserBooks,
      );
      if (resolvedBook == null) return null;

      final bytes = await resolvedBook.repository.getLineContentBytes(
        resolvedBook.book.id,
      );
      if (bytes.isEmpty) return null;
      return bytes;
    } catch (e, st) {
      debugPrint(
        '[SqliteDataProvider] getBookTextBytesFromDb failed for '
        '"$title": $e\n$st',
      );
      return null;
    }
  }

  /// Retrieves the table of contents of a book from the database
  Future<List<TocEntry>?> getBookTocFromDb(
    String title, [
    int? categoryId,
    String? fileType,
    bool preferUserBooks = false,
  ]) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      final resolvedBook = await _resolveBookRecord(
        title,
        categoryId: categoryId,
        fileType: fileType,
        preferUserBooks: preferUserBooks,
      );
      if (resolvedBook == null) return null;
      final book = resolvedBook.book;

      final migrationTocEntries = await resolvedBook.repository.getBookTocs(
        book.id,
      );

      // Convert migration TOC entries to otzaria TOC entries
      final Map<int, TocEntry> idToEntry = {};
      final List<TocEntry> rootEntries = [];

      for (final migrationToc in migrationTocEntries) {
        TocEntry? parent;
        if (migrationToc.parentId != null) {
          parent = idToEntry[migrationToc.parentId];
        }

        final otzariaToc = migrationTocToOtzariaToc(migrationToc, parent);
        idToEntry[migrationToc.id] = otzariaToc;

        if (parent != null) {
          parent.children.add(otzariaToc);
        } else {
          rootEntries.add(otzariaToc);
        }
      }

      return rootEntries;
    } catch (e, st) {
      debugPrint(
        '[SqliteDataProvider] getBookTocFromDb failed for '
        '"$title": $e\n$st',
      );
      return null;
    }
  }

  /// Retrieves source name for a book from DB source table.
  Future<String?> getBookSourceNameFromDb(
    String title, [
    int? categoryId,
    String? fileType,
  ]) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      final resolvedBook = await _resolveBookRecord(
        title,
        categoryId: categoryId,
        fileType: fileType,
      );
      if (resolvedBook == null) return null;
      final source = await resolvedBook.repository.getSourceById(
        resolvedBook.book.sourceId,
      );
      return source?.name;
    } catch (e, st) {
      debugPrint(
        '[SqliteDataProvider] getBookSourceNameFromDb failed for '
        '"$title": $e\n$st',
      );
      return null;
    }
  }

  /// Gets the repository instance (for advanced operations)
  SeforimRepository? get repository => _isInitialized ? _repository : null;

  /// Gets the database path
  String get dbPath => _dbPath;

  /// Checks if database file exists
  Future<bool> databaseExists() async {
    final dbFile = File(_dbPath);
    return await dbFile.exists();
  }

  /// Exports the database to a specified path
  Future<void> exportDatabase(String destinationPath) async {
    if (!_isInitialized) {
      await initialize();
    }

    final dbFile = File(_dbPath);
    if (!await dbFile.exists()) {
      throw Exception('Database file does not exist');
    }

    await dbFile.copy(destinationPath);
  }

  /// Imports a database from a specified path
  Future<void> importDatabase(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source database file does not exist');
    }

    // Close existing connection if open
    if (_isInitialized) {
      _repository.database.close();
      _isInitialized = false;
    }

    // Copy the file
    await sourceFile.copy(_dbPath);

    // Reinitialize
    await initialize();
  }

  /// Gets statistics about the database
  Future<Map<String, int>> getDatabaseStats() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) {
      return {'books': 0, 'lines': 0, 'links': 0};
    }

    try {
      final bookCount = await _repository.countAllBooks();
      final linkCount = await _repository.countLinks();

      return {
        'books': bookCount,
        'links': linkCount,
      };
    } catch (e) {
      return {'books': 0, 'lines': 0, 'links': 0};
    }
  }

  /// Performs a health check on the database
  Future<Map<String, dynamic>> performHealthCheck() async {
    final results = <String, dynamic>{
      'healthy': true,
      'issues': <String>[],
      'warnings': <String>[],
    };

    try {
      if (!_isInitialized) {
        await initialize();
      }

      if (!_isInitialized) {
        results['healthy'] = false;
        (results['issues'] as List).add('Database not initialized');
        return results;
      }

      // Check if database file exists
      if (!await databaseExists()) {
        results['healthy'] = false;
        (results['issues'] as List).add('Database file does not exist');
        return results;
      }

      // Check if we can query the database
      try {
        await _repository.countAllBooks();
      } catch (e) {
        results['healthy'] = false;
        (results['issues'] as List).add('Cannot query database: $e');
        return results;
      }
    } catch (e) {
      results['healthy'] = false;
      (results['issues'] as List).add('Health check failed: $e');
    }

    return results;
  }

  /// Optimizes the database (VACUUM)
  ///
  /// VACUUM כותב לקובץ ולכן רץ דרך write-session זמני (החיבור הרגיל פתוח
  /// read-only).
  Future<void> optimizeDatabase() async {
    try {
      await withWritableSession((repository) async {
        final db = await repository.database.database;
        db.execute('VACUUM');
      });
    } catch (e) {
      debugPrint('❌ Error optimizing database: $e');
      rethrow;
    }
  }

  Future<ResolvedDbBookRecord?> _resolveBookRecord(
    String title, {
    int? categoryId,
    String? fileType,
    bool preferUserBooks = false,
  }) async {
    return await BookDatabaseResolver.resolveBook(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      preferUserBooks: preferUserBooks,
    );
  }
}
