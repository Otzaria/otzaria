import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/find_ref/repository/attached_find_ref_worker.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';

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
    return repo;
  }

  /// סוגר את ה-DB, וגם את חיבור הקריאה של איתור המקורות כדי שהקובץ ישוחרר.
  Future<void> close() async {
    AttachedFindRefWorker.instance.reset();
    _database?.close();
    _database = null;
    _repository = null;
    _initFuture = null;
  }
}
