import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' show SqliteException;

/// בדיקות ל-write-session של [SqliteDataProvider]: seforim.db פתוח read-only,
/// וכתיבות עוברות דרך [SqliteDataProvider.withWritableSession] שמחזיר ל-RO.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String libraryPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-write-session-');
    libraryPath = path.join(tempDir.path, 'library');
    final dataRootPath = path.join(tempDir.path, 'data_root');
    await Directory(libraryPath).create(recursive: true);

    await Settings.init(cacheProvider: _MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(dataRootPath);

    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libraryPath,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');

    // בונים seforim.db עם קטגוריה אחת, ואז **סוגרים** — אסור להשאיר חיבור
    // מתחרה פתוח, אחרת ה-write-session ייתקל בנעילת קובץ.
    final dbPath = path.join(libraryPath, DatabaseConstants.databaseFileName);
    final db = MyDatabase.withPath(dbPath);
    final repo = SeforimRepository(db);
    await repo.ensureInitialized();
    await repo.insertCategory(const migration_models.Category(title: 'שורש'));
    db.close();

    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();

    // איפוס פרמטרי ההמתנה ל-gate לברירת המחדל — ה-provider הוא singleton
    // ועקיפה בטסט אחד הייתה דולפת לבא אחריו.
    SqliteDataProvider.instance.debugSetExternalWriteWait(
      pollInterval: const Duration(seconds: 2),
      maxPolls: 15,
    );
  });

  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    AppPaths.debugOverrideDataRootPath(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('החיבור הרגיל פתוח read-only — כתיבה ישירה נכשלת', () async {
    final repo = SqliteDataProvider.instance.repository;
    expect(repo, isNotNull);
    final db = await repo!.database.database;
    expect(
      () => db.execute("INSERT INTO category (title, level) VALUES ('x', 0)"),
      throwsA(isA<SqliteException>()),
    );
  });

  test('withWritableSession כותב, והכתיבה נראית אחרי החזרה ל-RO', () async {
    await SqliteDataProvider.instance.withWritableSession((rw) async {
      await rw.insertCategory(const migration_models.Category(title: 'חדש'));
    });

    // החיבור נפתח מחדש read-only.
    expect(SqliteDataProvider.instance.isInitialized, isTrue);

    final categories = await SqliteDataProvider.instance.repository!
        .getRootCategories();
    expect(
      categories.where((c) => c.title == 'חדש'),
      isNotEmpty,
      reason: 'הקטגוריה שנכתבה ב-write-session נראית בחיבור ה-RO',
    );

    // וה-RO עדיין חוסם כתיבה ישירה.
    final db = await SqliteDataProvider.instance.repository!.database.database;
    expect(
      () => db.execute("INSERT INTO category (title, level) VALUES ('y', 0)"),
      throwsA(isA<SqliteException>()),
    );
  });

  test(
    'initialize() מקבילה ל-write-session אינה קורסת ואינה פותחת חיבור מתנגש',
    () async {
      final session = SqliteDataProvider.instance.withWritableSession((
        rw,
      ) async {
        // משהים כדי שה-initialize המקבילה תתפוס את ה-session כפעיל.
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await rw.insertCategory(
          const migration_models.Category(title: 'במקביל'),
        );
      });

      // קריאה מקבילה (כמו lazy-init של מסלול קריאה) — צריכה להמתין לסיום
      // השרשרת ולא לפתוח חיבור RO מתנגש מול ה-RW.
      await SqliteDataProvider.instance.initialize();
      await session;

      expect(SqliteDataProvider.instance.isInitialized, isTrue);
      final categories = await SqliteDataProvider.instance.repository!
          .getRootCategories();
      expect(categories.where((c) => c.title == 'במקביל'), isNotEmpty);
    },
  );

  test('initialize() בזמן כתיבה חיצונית ממתינה לפתיחה-מחדש ולא מחזירה null '
      '(תיקון ספר/מפרשים ריקים בעלייה)', () async {
    // מדמים את זרימת הסנכרון ברקע: סוגרים את החיבור לכתיבה חיצונית, ובזמן
    // שהוא סגור מפעילים קורא מקביל (כמו טעינת מפרשים ברקע). הקורא חייב
    // להמתין לפתיחה-מחדש ולראות את החיבור פתוח — לא לקבל חיבור סגור.
    await SqliteDataProvider.instance.closeForExternalWrite();
    expect(
      SqliteDataProvider.instance.isInitialized,
      isFalse,
      reason: 'בזמן כתיבה חיצונית החיבור סגור',
    );

    var readerDone = false;
    final readerInitialized = SqliteDataProvider.instance.initialize().then(
      (_) => readerDone = true,
    );

    // מוודאים שהקורא באמת *נחסם* ולא חזר מוקדם: נותנים ל-event loop להתרוקן,
    // ועדיין ה-future לא הושלם כל עוד הכתיבה החיצונית פעילה. בלי החסימה, רגרסיה
    // של "מחזיר מוקדם וריק" הייתה משלימה כאן והבדיקה הייתה נכשלת.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      readerDone,
      isFalse,
      reason: 'הקורא חייב להמתין לפתיחה-מחדש, לא לחזור מוקדם',
    );

    // האיזולייט החיצוני "סיים" — פותחים מחדש.
    await SqliteDataProvider.instance.reopenAfterExternalWrite();

    await readerInitialized;
    expect(
      SqliteDataProvider.instance.isInitialized,
      isTrue,
      reason: 'הקורא המתין לפתיחה-מחדש במקום לקבל null',
    );

    final categories = await SqliteDataProvider.instance.repository!
        .getRootCategories();
    expect(categories.where((c) => c.title == 'שורש'), isNotEmpty);
  });

  test('כתיבות חיצוניות חופפות — reopen מקונן אינו נכנס ל-deadlock, '
      'והקורא נפתח רק אחרי שהאחרון סיים', () async {
    // שני close חיצוניים לפני שום reopen (כמו שני סנכרונים חופפים).
    await SqliteDataProvider.instance.closeForExternalWrite();
    await SqliteDataProvider.instance.closeForExternalWrite();
    expect(SqliteDataProvider.instance.isInitialized, isFalse);

    var readerDone = false;
    final reader = SqliteDataProvider.instance.initialize().then(
      (_) => readerDone = true,
    );

    // reopen ראשון מוריד את המונה ל-1 בלבד — אסור שייתקע ואסור שיפתח עדיין.
    await SqliteDataProvider.instance.reopenAfterExternalWrite().timeout(
      const Duration(seconds: 5),
    );
    expect(
      SqliteDataProvider.instance.isInitialized,
      isFalse,
      reason: 'עוד יש כתיבה חיצונית פעילה — לא פותחים מחדש',
    );
    expect(
      readerDone,
      isFalse,
      reason: 'הקורא עדיין חסום — רק הכתיבה הראשונה מבין השתיים הסתיימה',
    );

    // reopen שני (האחרון) פותח מחדש ומשחרר את הקורא.
    await SqliteDataProvider.instance.reopenAfterExternalWrite().timeout(
      const Duration(seconds: 5),
    );
    await reader.timeout(const Duration(seconds: 5));

    expect(SqliteDataProvider.instance.isInitialized, isTrue);
  });

  test('initialize() לא נתקעת לנצח כש-reopen מתפספס — חוזרת בתקרת הזמן '
      '(תיקון מסך עיון/תצוגה מקדימה ריקים שדורשים restart)', () async {
    // מקצרים את תקרת ההמתנה כדי לבדוק את החסימה בלי להמתין ~30ש'.
    SqliteDataProvider.instance.debugSetExternalWriteWait(
      pollInterval: const Duration(milliseconds: 20),
      maxPolls: 3,
    );

    // מדמים דליפת session: סוגרים לכתיבה חיצונית אך *לעולם* לא קוראים ל-
    // reopen (איזולייט שקרס / close בלי finally תואם). ה-gate לא יושלם.
    await SqliteDataProvider.instance.closeForExternalWrite();
    expect(SqliteDataProvider.instance.isInitialized, isFalse);

    // הקורא חייב לחזור בתוך תקרת ההמתנה, לא להיתקע לנצח. בלי התיקון
    // (await gate.future ללא תקרה) ה-timeout כאן היה מתפוצץ.
    await SqliteDataProvider.instance.initialize().timeout(
      const Duration(seconds: 5),
    );

    // עדיין יש session פעיל (דלף) ולכן ה-RO לא נפתח — אבל האפליקציה
    // רספונסיבית: הקורא חזר (יציג ריק) במקום לקפוא על סקלטון.
    expect(
      SqliteDataProvider.instance.isInitialized,
      isFalse,
      reason: 'ה-session דלף — RO לא נפתח, אבל הקורא לא נתקע',
    );

    // ניקוי: סוגרים את ה-session הדלוף כדי שלא ידלוף לטסט הבא.
    await SqliteDataProvider.instance.reopenAfterExternalWrite();
  });

  test(
    'initialize() מתאוששת מיד כש-reopen מגיע אחרי השהיה (לא ממתינה פעימה מלאה)',
    () async {
      SqliteDataProvider.instance.debugSetExternalWriteWait(
        pollInterval: const Duration(seconds: 30),
        maxPolls: 15,
      );

      await SqliteDataProvider.instance.closeForExternalWrite();

      var readerDone = false;
      final reader = SqliteDataProvider.instance.initialize().then(
        (_) => readerDone = true,
      );

      // reopen מגיע אחרי השהיה קצרה (כמו סנכרון שנמשך "כמה שניות"). אף שפעימת
      // ההמתנה היא 30ש', gate.future מסתיים מיד עם reopen והקורא מתעורר — לא
      // ממתין את הפעימה המלאה.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(readerDone, isFalse);
      await SqliteDataProvider.instance.reopenAfterExternalWrite();

      await reader.timeout(const Duration(seconds: 2));
      expect(
        SqliteDataProvider.instance.isInitialized,
        isTrue,
        reason: 'הקורא התעורר מיד עם reopen, לא חיכה לתום הפעימה',
      );
    },
  );

  test('initialize() מתאוששת מיומן rollback חם שנותר מסגירה באמצע עדכון '
      '(תיקון SQLITE_READONLY_ROLLBACK 776)', () async {
    final dbPath = path.join(libraryPath, DatabaseConstants.databaseFileName);

    // סוגרים את ה-RO הראשי כדי לשחרר את נעילת הקובץ.
    await SqliteDataProvider.instance.dispose();

    // משחזרים מצב "סגירה באמצע כתיבה": פותחים חיבור כתיב במצב rollback עם
    // מטמון זעיר (מכריח spill ליומן), מתחילים טרנזקציה כבדה, ומצלמים את
    // הקובץ + היומן בעודם לא-עקביים. החזרת הצילום מדמה את היומן החם.
    final writable = MyDatabase.withPath(dbPath);
    final wdb = await writable.database;
    wdb.execute('PRAGMA journal_mode=DELETE');
    wdb.execute('PRAGMA cache_size=1');
    wdb.execute('BEGIN IMMEDIATE');
    for (var i = 0; i < 500; i++) {
      wdb.execute("INSERT INTO category (title, level) VALUES ('flood$i', 0)");
    }
    final dbBytes = File(dbPath).readAsBytesSync();
    final journalBytes = File('$dbPath-journal').readAsBytesSync();
    wdb.execute('ROLLBACK');
    writable.close();

    // החזרת הצילום — עכשיו על הדיסק DB + יומן rollback חם לא-עקביים.
    File('$dbPath-wal').existsSync() ? File('$dbPath-wal').deleteSync() : null;
    File('$dbPath-shm').existsSync() ? File('$dbPath-shm').deleteSync() : null;
    File(dbPath).writeAsBytesSync(dbBytes);
    File('$dbPath-journal').writeAsBytesSync(journalBytes);
    expect(
      File('$dbPath-journal').lengthSync(),
      greaterThan(0),
      reason: 'התרחיש דורש יומן חם לא-ריק',
    );

    // ללא נרמול היומן החם, הפתיחה ה-RO הייתה נכשלת ב-776 והאפליקציה לא נפתחת.
    await SqliteDataProvider.instance.initialize();
    expect(
      SqliteDataProvider.instance.isInitialized,
      isTrue,
      reason: 'היומן החם נורמל ל-DELETE, וה-RO נפתח בהצלחה',
    );

    // הטרנזקציה שנקטעה בוטלה (rollback), והקריאה עובדת.
    final categories = await SqliteDataProvider.instance.repository!
        .getRootCategories();
    expect(categories.where((c) => c.title == 'שורש'), isNotEmpty);
    expect(
      categories.where((c) => c.title.startsWith('flood')),
      isEmpty,
      reason: 'הטרנזקציה הלא-גמורה לא הוחלה',
    );
  });

  test('write-sessions סדרתיים — שתי כתיבות מצטברות', () async {
    await SqliteDataProvider.instance.withWritableSession((rw) async {
      await rw.insertCategory(const migration_models.Category(title: 'א'));
    });
    await SqliteDataProvider.instance.withWritableSession((rw) async {
      await rw.insertCategory(const migration_models.Category(title: 'ב'));
    });

    final titles =
        (await SqliteDataProvider.instance.repository!.getRootCategories())
            .map((c) => c.title)
            .toSet();
    expect(titles.containsAll({'א', 'ב'}), isTrue);
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) return value;
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> removeAll() async => _values.clear();

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;
}
