import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:otzaria/core/windowing/library_suspension_marker.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/book_text_reader.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/journal_mode.dart';
import 'package:otzaria/migration/models/model_adapters.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/search/library_line_source.dart';
import 'package:otzaria/migration/models/toc_entry.dart' as db_models;
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' show SqliteException;

/// A data provider that manages SQLite database operations for the library.
///
/// This class handles all database related operations including:
/// - Reading book content from the database
/// - Managing the library structure (categories and books)
/// - Providing table of contents functionality
/// - Falling back to file system when data is not in database
class SqliteDataProvider {
  late SeforimRepository _repository;
  // לא late: ה-getter dbPath עשוי להיקרא לפני initialize.
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

    // מחוץ ל-future של האתחול, כדי ש-suspend לא ימתין לשחרור של עצמו.
    await LibrarySuspensionMarker.waitUntilReleased();
    if (_isInitialized) return;

    // קוראים ממתינים לחיבור ה-RO, בלי לפתוח אותו במהלך כתיבה חיצונית.
    if (_activeWriteSessions > 0) {
      // תקרה לקורא בלבד: session פעיל ממשיך לחסום פתיחה.
      var polls = 0;
      for (; _activeWriteSessions > 0 && !_isInitialized; polls++) {
        if (polls >= _maxExternalWriteWaitPolls) {
          // יש לאתר close שלא קיבל reopen תואם.
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

    // seforim.db נפתח read-only. עדכון הספרייה מחליף את הקובץ (או מחיל patch)
    // דרך [closeForExternalWrite]/[reopenAfterExternalWrite]. לפני הפתיחה
    // ה-read-only יש לוודא שהקובץ אינו במצב WAL — אחרת SQLite לא יוכל לפתוח
    // אותו ללא יצירת קובצי -wal/-shm (שדורשים הרשאת כתיבה).
    await normalizeJournalModeForReadOnly(_dbPath);

    try {
      final database = MyDatabase.withPath(
        _dbPath,
        readOnly: true,
        official: true,
      );
      _repository = SeforimRepository(database);
      await _repository.ensureInitialized();
      _isInitialized = true;
      DbReadWorker.allowReopen();
      unawaited(LibraryLineSource.configure(_dbPath));
    } on SqliteException catch (e) {
      // SQLITE_CANTOPEN (code 14) on Android: clear a stale keyDbEffectivePath
      // so the library path is re-resolved on the next check.
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

  @visibleForTesting
  bool get debugIsInitializing => _initializationFuture != null;

  /// Checks if the database is initialized and ready
  bool get isInitialized => _isInitialized;

  /// Closes the database connection to free resources
  /// [forAppExit] לא ממתין ל-worker עסוק: התהליך מסתיים ממילא.
  Future<void> dispose({bool forAppExit = false}) =>
      _dispose(waitForWorker: !forAppExit);

  Future<void> _dispose({required bool waitForWorker}) async {
    if (_isInitialized) {
      _repository.database.close();
      _isInitialized = false;
    }
    // ה-worker פותח לפי הנתיב של החיבור הזה, ולכן לא יחזיק את הקובץ אחריו.
    await DbReadWorker.closeConnectionIfRunning(wait: waitForWorker);
    // ביציאה אין טעם, ובכתיבה חיצונית closeForExternalWrite מחזיק אותו סגור.
    if (waitForWorker) await LibraryLineSource.closeNow();
  }

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

  /// סוגר את חיבור ה-RO לפני שאיזולייט חיצוני (diff-sync / background sync)
  /// פותח את seforim.db לכתיבה, כדי שלא תתפוס נעילת קובץ מתנגשת.
  ///
  /// מסמן כתיבה חיצונית פעילה כדי ש-[initialize] של קוראים מקבילים לא יפתח
  /// חיבור RO מתנגש בזמן שהאיזולייט כותב.
  /// יש לקרוא ל-[reopenAfterExternalWrite] לאחר שהאיזולייט סיים.
  /// זורק [StateError] אם שחרור ה-handle של ה-worker לא אומת.
  /// [releaseOnFailure]=false משאיר את השער סגור גם כשהשחרור נכשל; הקורא
  /// חייב אז לקרוא ל-[reopenAfterExternalWrite] בעצמו.
  Future<void> closeForExternalWrite({bool releaseOnFailure = true}) async {
    // נוצר *לפני* הגדלת המונה, כך שקורא מקביל שיראה _activeWriteSessions > 0
    // תמיד יראה גם gate להמתין עליו.
    _externalWriteGate ??= Completer<void>();
    _activeWriteSessions++;
    try {
      await LibraryLineSource.holdForExternalWrite();
      try {
        await _initializationFuture;
      } finally {
        // גם אתחול שכבר התחיל חייב לשחרר את החיבור לפני האישור.
        await _dispose(waitForWorker: false);
      }
      final findRefReleased = await FindRefDbIsolate.suspendForExternalWrite();
      final readWorkerReleased = await DbReadWorker.suspendForExternalWrite();
      if (!findRefReleased || !readWorkerReleased) {
        final message = 'לא ניתן לשחרר את seforim.db לפני החלפת הספרייה';
        throw findRefReleased
            ? DbReadWorkerNotReleased(message)
            : StateError(message);
      }
    } catch (_) {
      if (releaseOnFailure) {
        await reopenAfterExternalWrite(reopenDatabase: false);
      }
      rethrow;
    }
  }

  /// פותח מחדש את seforim.db read-only לאחר שאיזולייט חיצוני סיים לכתוב.
  ///
  /// [reopenDatabase] כבוי כאשר מסך הייבוא כבר קבע את נתיב/תקינות הספרייה;
  /// החיבור ייפתח עצל בקריאה הבאה, אחרי שההחלפה הושלמה במלואה.
  Future<void> reopenAfterExternalWrite({bool reopenDatabase = true}) async {
    if (_activeWriteSessions > 0) {
      _activeWriteSessions--;
    }
    // אם עדיין יש כתיבה חיצונית פעילה (close-ים חופפים), אסור לפתוח מחדש
    // עכשיו — חיבור ה-RW האחר עדיין כותב. נפתח רק כשהאחרון מסיים.
    if (_activeWriteSessions > 0) {
      return;
    }
    try {
      if (reopenDatabase) {
        // המונה כבר 0, ולכן initialize() לא ייכנס לבלוק ההמתנה ל-gate (אין
        // deadlock), ומנגנון _initializationFuture מונע פתיחה כפולה מול קורא מקביל.
        await initialize();
      }
    } finally {
      // ב-finally: worker שנשאר מושהה אחרי כשל פתיחה יחזיר שגיאה לכל TOC
      // וקטלוג עד סוף ה-session.
      await FindRefDbIsolate.resumeAfterExternalWrite();
      await DbReadWorker.resumeAfterExternalWrite();
      await LibraryLineSource.releaseExternalWriteHold();
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
    BookSource preferSource = BookSource.official,
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
        preferSource: preferSource,
      );
      if (resolvedBook == null || resolvedBook.book.totalLines <= 0) {
        return null;
      }
      final book = resolvedBook.book;

      // Load 10 lines before and 10 after (20 total)
      final startLine = (currentLine - 10).clamp(0, book.totalLines - 1);
      final endLine = (currentLine + 10).clamp(0, book.totalLines - 1);

      return await _linesText(resolvedBook, startLine, endLine);
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
    BookSource preferSource = BookSource.official,
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
        preferSource: preferSource,
      );
      if (resolvedBook == null || resolvedBook.book.totalLines <= 0) {
        return null;
      }
      final book = resolvedBook.book;

      final normalizedStart = startLine.clamp(0, book.totalLines - 1);
      final normalizedEnd = endLine.clamp(normalizedStart, book.totalLines - 1);
      return (
        startLine: normalizedStart,
        endLine: normalizedEnd,
        totalLines: book.totalLines,
        text: await _linesText(resolvedBook, normalizedStart, normalizedEnd),
      );
    } catch (e, st) {
      debugPrint(
        '[SqliteDataProvider] getBookTextRangeFromDb failed for '
        '"$title": $e\n$st',
      );
      return null;
    }
  }

  /// טקסט הספר מהמסד; [emptyWhenNoLines] מבדיל ספר קיים שהתרוקן מכשל קריאה.
  Future<String?> getBookTextFromDb(
    String title, [
    int? categoryId,
    String? fileType,
    BookSource preferSource = BookSource.official,
    bool emptyWhenNoLines = false,
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
        preferSource: preferSource,
      );
      if (resolvedBook == null) return null;
      final text = await BookTextReader.text(
        resolvedBook.repository,
        resolvedBook.book,
      );
      // מסד חסר אינו ספר שהתרוקן, גם כשקיים ספר בשם זהה במקור אחר.
      if (emptyWhenNoLines &&
          resolvedBook.source != preferSource &&
          (text == null || text.isEmpty)) {
        return null;
      }
      return text ?? (emptyWhenNoLines ? '' : null);
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
  /// [officialBookId] — ה-id ב-seforim.db כשהשורות נקראו משם, אחרת null.
  /// גם null כששורה מכילה `\n`: מספרי השורות במנוע לא יתאימו לרשומות.
  Future<({Uint8List bytes, int? officialBookId})?> getBookTextBytesFromDb(
    String title, [
    int? categoryId,
    String? fileType,
    BookSource preferSource = BookSource.official,
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
        preferSource: preferSource,
      );
      if (resolvedBook == null) return null;

      final read = await BookTextReader.bytes(
        resolvedBook.repository,
        resolvedBook.book,
      );
      if (read == null || read.bytes.isEmpty) return null;
      return (
        bytes: read.bytes,
        officialBookId: resolvedBook.source.isOfficial && !read.rowHasNewline
            ? resolvedBook.book.id
            : null,
      );
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
    BookSource preferSource = BookSource.official,
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
        preferSource: preferSource,
      );
      if (resolvedBook == null) return null;
      final book = resolvedBook.book;

      // ‏TOC של seforim.db יכול למנות אלפי שורות ולחסום את פתיחת הספר, ולכן
      // נקרא ב-isolate, שמכיר רק אותו. שאר המסדים נקראים בחיבור המקומי.
      final List<db_models.TocEntry> migrationTocEntries;
      if (!resolvedBook.source.isOfficial) {
        migrationTocEntries = await resolvedBook.repository.getBookTocs(
          book.id,
        );
      } else {
        final isolate = await FindRefDbIsolate.instance();
        migrationTocEntries = await isolate.getBookTocEntries(book.id);
      }

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

  /// השורות [start]..[end] כטקסט אחד; seforim.db מפוענח ב-[DbReadWorker].
  Future<String> _linesText(
    ResolvedDbBookRecord resolved,
    int start,
    int end,
  ) async {
    if (!resolved.source.isOfficial) {
      final lines = await resolved.repository.getLines(
        resolved.book.id,
        start,
        end,
      );
      return migrationLinesToText(lines);
    }
    final lines = await DbReadWorker.lines(
      _dbPath,
      resolved.book.id,
      start,
      end,
    );
    return lines.map((line) => line.content).join('\n');
  }

  Future<ResolvedDbBookRecord?> _resolveBookRecord(
    String title, {
    int? categoryId,
    String? fileType,
    BookSource preferSource = BookSource.official,
  }) async {
    return await BookDatabaseResolver.resolveBook(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
      preferSource: preferSource,
    );
  }
}
