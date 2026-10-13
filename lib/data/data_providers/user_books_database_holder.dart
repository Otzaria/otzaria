import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/search/library_line_source.dart';

/// סינגלטון שמחזיק את ה-DB וה-repository של ספרי המשתמש (תיקיות
/// מותאמות אישית).
///
/// ה-DB עצמו (`user_books.db`) משתמש באותה סכמה ובאותם DAOs כמו
/// `seforim.db`, אך הוא קובץ נפרד בתיקיית מסדי הנתונים הפעילה.
/// ההפרדה מבטיחה ששינויים בספרייה הרשמית לא ימחקו את הספרים של המשתמש,
/// ולהפך.
///
/// המופע מאותחל בעצלתיים — בקריאה הראשונה ל-[repository].
class UserBooksDatabaseHolder {
  UserBooksDatabaseHolder._();

  static final UserBooksDatabaseHolder instance = UserBooksDatabaseHolder._();

  MyDatabase? _database;
  SeforimRepository? _repository;
  String? _dbPath;
  Future<SeforimRepository>? _initFuture;

  /// מחזיר את ה-repository של ספרי המשתמש, מאתחל אם צריך.
  ///
  /// אם האתחול נכשל (DB נעול, נתיב חסר הרשאות וכו'), ה-Future שנשמר
  /// מאופס כדי שקריאה חוזרת תנסה לפתוח את ה-DB מחדש במקום להחזיר את
  /// אותה שגיאה לנצח.
  Future<SeforimRepository> get repository {
    if (_repository != null) return Future.value(_repository!);
    return _initFuture ??= _initialize().onError<Object>((error, stackTrace) {
      _initFuture = null;
      throw error;
    });
  }

  /// מחזיר את ה-repository רק אם כבר אותחל, אחרת null — בלי לכפות פתיחה
  /// (שהייתה יוצרת user_books.db ריק כשאין ספרי משתמש). משמש למשל לכוונון
  /// PRAGMA זמני בזמן אינדוקס, רק על חיבור שכבר פתוח.
  SeforimRepository? get repositoryIfInitialized => _repository;

  /// נתיב המסד הפתוח, או null כשהוא סגור.
  String? get openDbPath => _repository == null ? null : _dbPath;

  /// מקור השורות של המנוע גלובלי לתהליך: רק החלון הראשי, שבו רץ האינדוקס,
  /// מגדיר אותו — סגירה בחלון משני הייתה מנתקת אותו גם לראשי.
  static Future<void> configureSearchLineSource(String? dbPath) async {
    if (WindowRole.isSecondary) return;
    await LibraryLineSource.configureUserBooks(dbPath);
  }

  /// נתיב ה-DB. שימושי בזרימות isolate שצריכות לפתוח את הקובץ ישירות.
  static Future<String> resolveDbPath() => AppPaths.resolveUserBooksDbPath();

  Future<SeforimRepository> _initialize() async {
    final dbPath = await AppPaths.resolveUserBooksDbPath();
    debugPrint('📚 [UserBooksDB] Opening user_books.db at $dbPath');
    final db = MyDatabase.withPath(dbPath);
    final repo = SeforimRepository(db);
    await repo.ensureInitialized();
    // ספרים אישיים שנוצרו לפני אינדקס ההפניות — בנייה חד-פעמית.
    await repo.backfillMissingLineRefIndexes();
    _database = db;
    _repository = repo;
    _dbPath = dbPath;
    await configureSearchLineSource(dbPath);
    return repo;
  }

  final Set<FutureOr<void> Function()> _closeListeners = {};

  /// נקרא ב-[close] — לחיבורים נוספים לקובץ (למשל ב-isolate) שחייבים לשחרר
  /// אותו; [close] ממתין להם, כדי שהקובץ ישוחרר כשהוא מסתיים.
  void addCloseListener(FutureOr<void> Function() listener) =>
      _closeListeners.add(listener);

  /// סוגר את ה-DB ומודיע ל-[addCloseListener] כדי שהקובץ ישוחרר.
  Future<void> close() async {
    // המנוע מחזיק את הקובץ פתוח לקריאה; בלי זה החלפתו נכשלת ב-Windows.
    await configureSearchLineSource(null);
    for (final listener in _closeListeners.toList()) {
      await listener();
    }
    _database?.close();
    _database = null;
    _repository = null;
    _dbPath = null;
    _initFuture = null;
  }
}
