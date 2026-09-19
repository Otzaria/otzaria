import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_schema.dart';
import 'package:otzaria/external_catalog/responsa/responsa_paths.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_names.dart';
import 'package:otzaria/models/books.dart';

/// מטא-דאטה של קטלוג פרויקט השו"ת המקומי.
///
/// הקטלוג קשור להתקנה שממנה נבנה. `fingerprint` הוא מה שמאפשר לזהות
/// שההתקנה השתנתה ושצריך לבנות מחדש.
class ResponsaCatalogInfo {
  final bool exists;
  final int bookCount;
  final int? sourceVersion;
  final int? schemaVersion;
  final String? installPath;
  final String? builtAt;
  final Map<String, String> fingerprint;

  const ResponsaCatalogInfo({
    required this.exists,
    this.bookCount = 0,
    this.sourceVersion,
    this.schemaVersion,
    this.installPath,
    this.builtAt,
    this.fingerprint = const {},
  });

  static const ResponsaCatalogInfo missing = ResponsaCatalogInfo(exists: false);

  bool get isUsable => exists && bookCount > 0;

  /// קטלוג שנבנה בסכמה ישנה. הספרים בו עדיין נקראים — אחרת שדרוג היה
  /// מוחק את הספרייה מהמסך — אבל הכותרות וההפניות בו נבנו בכללים ישנים,
  /// ולכן מוצגת בקשה לרענון.
  bool get isOutdated =>
      exists && (schemaVersion ?? 1) < responsaCatalogSchemaVersion;
}

/// קורא את `responsa_catalog.db` — הקטלוג המקומי של פרויקט השו"ת.
///
/// הקטלוג נבנה אצל המשתמש מההתקנה שלו; אין קובץ קטלוג שאפשר להוריד
/// מהרשת, כי תוכן המאגר משתנה בין מהדורות ה-CD.
///
/// כל כשל כאן מחזיר ערך ריק ולא חריג: קטלוג חסר או פגום הוא מצב רגיל
/// (המשתמש טרם בנה אותו), ואסור שיפיל את חיפוש הספרים כולו.
class ResponsaCatalogRepository {
  static final ResponsaCatalogRepository instance = ResponsaCatalogRepository();

  /// מפריד רכיבי הנתיב בעץ הקטלוג של התוכנה.
  static const String pathSeparator = ' > ';

  /// עוקף את נתיב ה-DB בבדיקות.
  @visibleForTesting
  String? databasePathOverride;

  String? get databasePath => databasePathOverride ?? ResponsaPaths.catalogPath;

  Future<bool> exists() async {
    final target = databasePath;
    if (target == null) return false;
    return File(target).exists();
  }

  sqlite3.Database? _open() {
    final target = databasePath;
    if (target == null || !File(target).existsSync()) return null;
    try {
      return sqlite3.sqlite3.open(target, mode: sqlite3.OpenMode.readOnly);
    } catch (e) {
      debugPrint('ResponsaCatalogRepository: cannot open $target: $e');
      return null;
    }
  }

  /// מצב הקטלוג — קיים, כמה ספרים, ומאיזו התקנה נבנה.
  Future<ResponsaCatalogInfo> info() async {
    final db = _open();
    if (db == null) return ResponsaCatalogInfo.missing;
    try {
      final meta = <String, String>{};
      for (final row in db.select('SELECT key, value FROM db_meta')) {
        meta[row['key'].toString()] = row['value'].toString();
      }
      final count =
          (db.select('SELECT count(*) AS n FROM books').first['n'] as num)
              .toInt();
      return ResponsaCatalogInfo(
        exists: true,
        bookCount: count,
        sourceVersion: int.tryParse(meta['responsa_version'] ?? ''),
        schemaVersion: int.tryParse(meta['catalog_schema_version'] ?? ''),
        installPath: meta['install_path'],
        builtAt: meta['catalog_build_time'],
        fingerprint: meta,
      );
    } catch (e) {
      debugPrint('ResponsaCatalogRepository: info failed: $e');
      return ResponsaCatalogInfo.missing;
    } finally {
      db.close();
    }
  }

  /// כל ספרי הקטלוג. ב-CD25 מדובר ב-~8,500 רשומות ב-DB של ~5MB, ולכן
  /// טעינה לזיכרון זולה יותר מקטלוג היברובוקס שכבר נטען כך.
  Future<List<ExternalLibraryBook>> loadBooks() async {
    return _select(
      'SELECT * FROM books ORDER BY title COLLATE NOCASE',
      const [],
    );
  }

  /// ספרים לפי `external_key` — המסלול של טעינת ספרים שתוסף ביקש.
  Future<List<ExternalLibraryBook>> loadBooksByKeys(
    Iterable<String> keys,
  ) async {
    final list = keys.map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
    if (list.isEmpty) return const [];
    final results = <ExternalLibraryBook>[];
    // מתחת למגבלת המשתנים של SQLite.
    for (var start = 0; start < list.length; start += 900) {
      final chunk = list.sublist(
        start,
        start + 900 < list.length ? start + 900 : list.length,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      results.addAll(
        await _select(
          'SELECT * FROM books WHERE external_key IN ($placeholders)',
          chunk,
        ),
      );
    }
    return results;
  }

  /// ה-`open_ref` של ספר — ההפניה שנשלחת למנתח ההפניות של התוכנה.
  ///
  /// הוא נפרד מהכותרת בכוונה: `openBook("רא\"ש")` מחזיר מאות תוצאות
  /// שהראשונה בהן ספר אחר לגמרי, ולכן הקטלוג שומר הפניה הכוללת הקשר.
  Future<String?> openRefFor(String externalKey) async =>
      (await openRefsFor(externalKey)).firstOrNull;

  /// סולם ההפניות של ספר: ההפניה הראשית ואחריה החלופות, לפי סדר.
  ///
  /// הסולם נבנה בזמן בניית הקטלוג, כשמבנה הנתיב ושמות הליבה ידועים.
  /// נסיגה בזמן ריצה יכולה רק להשמיט מילים, וזה ניחוש: `היכלות` נפתח,
  /// ואילו השם כפי שהוא במאגר — `(108-126 'היכלות (עמ` — אינו נפתח כלל.
  Future<List<String>> openRefsFor(String externalKey) async {
    final db = _open();
    if (db == null) return const [];
    try {
      // `SELECT *` ולא רשימת עמודות: קטלוג בסכמה 1 אינו מכיר `alt_refs`,
      // ושאילתה ששמה אותו במפורש הייתה נכשלת ומשאירה את הספר בלי הפניה
      // כלל — כלומר משדרוג הקוד היה נובע שבר בפתיחה.
      final rows = db.select(
        'SELECT * FROM books WHERE external_key = ? LIMIT 1',
        [externalKey],
      );
      if (rows.isEmpty) return const [];
      final primary = rows.first['open_ref']?.toString() ?? '';
      final alternatives = rows.first['alt_refs']?.toString() ?? '';
      return [
        if (primary.isNotEmpty) primary,
        for (final line in alternatives.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];
    } catch (e) {
      debugPrint('ResponsaCatalogRepository: openRefsFor failed: $e');
      return const [];
    } finally {
      db.close();
    }
  }

  /// נתיב ההתקנה שממנה נבנה הקטלוג.
  ///
  /// נדרש בזמן פתיחה: על מחשב עם שתי התקנות, הפניה שנבנתה ממאגר אחד
  /// יכולה להוליך לספר אחר במאגר השני.
  Future<String?> sourceInstallPath() async {
    final db = _open();
    if (db == null) return null;
    try {
      final rows = db.select(
        "SELECT value FROM db_meta WHERE key = 'install_path' LIMIT 1",
      );
      if (rows.isEmpty) return null;
      final value = rows.first['value']?.toString();
      return (value == null || value.isEmpty) ? null : value;
    } catch (e) {
      debugPrint('ResponsaCatalogRepository: sourceInstallPath failed: $e');
      return null;
    } finally {
      db.close();
    }
  }

  Future<List<ExternalLibraryBook>> _select(
    String sql,
    List<Object?> arguments,
  ) async {
    final db = _open();
    if (db == null) return const [];
    try {
      return [
        for (final row in db.select(sql, arguments))
          mapRow(row as Map<String, Object?>),
      ];
    } catch (e) {
      // דגרדציה מכוונת: קטלוג פגום משאיר את שאר הספקים עובדים.
      debugPrint('ResponsaCatalogRepository: query failed: $e');
      return const [];
    } finally {
      db.close();
    }
  }

  /// ממיר שורת קטלוג ל-[ExternalLibraryBook].
  ///
  /// `link` הוא `null` — לפרויקט השו"ת אין אתר. `author`, `pubDate`
  /// ו-`pubPlace` נשארים ריקים: המטא-דאטה הזו אינה קיימת בהתקנה, ואין
  /// להמציא לה ערכים.
  @visibleForTesting
  static ExternalLibraryBook mapRow(Map<String, Object?> row) {
    final key = row['external_key']?.toString() ?? '';
    final refPath = row['ref_path']?.toString() ?? '';
    // `heCategories` הוא **נתיב הקטגוריה המלא בבר אילן**, לא רק השורש:
    // `ספרות חז"ל` לבדו מתפצל לחמש קטגוריות באוצריא, ורק הרמה השנייה
    // אומרת לאיזו מהן הספר שייך. קטלוג בסכמה 2 אינו מכיר את העמודה,
    // ואז השורש הוא מה שיש.
    final categoryPath =
        row['category_path']?.toString() ?? row['category']?.toString();
    return ExternalLibraryBook(
      title: row['title']?.toString() ?? '',
      id: int.tryParse(key) ?? 0,
      link: null,
      topics: row['topics']?.toString() ?? '',
      categoryPath: contextPathOf(refPath),
      heCategories: (categoryPath == null || categoryPath.isEmpty)
          ? null
          : categoryPath,
      externalLibraryId: ExternalProviderRegistry.responsa.externalLibraryIdFor(
        key,
      ),
    );
  }

  /// הקטגוריה שמוצגת למשתמש: הנתיב בעץ הקטלוג **בלי** שם הספר עצמו.
  ///
  /// הכרחי, לא קישוט: היוריסטיקת הסיווג מזהה במבנים מסוימים את הכרך
  /// כיחידת הספר, ולכן גם אחרי שהכותרת הושלמה לשם המלא — `הון עשיר
  /// אבות` — הקטגוריה היא שאומרת למשתמש היכן הספר יושב.
  ///
  /// כל רכיב עובר דרך [ResponsaNames.displayOf]: במאגר הם מאוחסנים עם
  /// עטיפת סוגריים בסדר חזותי, ובלי הסידור הנתיב מוצג שבור.
  @visibleForTesting
  static String contextPathOf(String refPath) {
    final parts = refPath
        .split(pathSeparator)
        .map((part) => ResponsaNames.displayOf(part))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length <= 1) return '';
    return parts.sublist(0, parts.length - 1).join('/');
  }
}
