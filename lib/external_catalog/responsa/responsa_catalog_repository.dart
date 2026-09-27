import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_backup.dart';
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

  /// כמה צמתים נסרקו בבנייה שיצרה את הקטלוג. המכנה של סרגל ההתקדמות
  /// בבנייה הבאה.
  final int? nodeCount;

  final Map<String, String> fingerprint;

  const ResponsaCatalogInfo({
    required this.exists,
    this.bookCount = 0,
    this.sourceVersion,
    this.schemaVersion,
    this.installPath,
    this.builtAt,
    this.nodeCount,
    this.fingerprint = const {},
  });

  static const ResponsaCatalogInfo missing = ResponsaCatalogInfo(exists: false);

  bool get isUsable => exists && bookCount > 0;

  /// קטלוג שנבנה בסכמה ישנה. הספרים בו עדיין נקראים — אחרת שדרוג היה
  /// מוחק את הספרייה מהמסך — אבל הכותרות וההפניות בו נבנו בכללים ישנים,
  /// ולכן מוצגת בקשה לרענון.
  bool get isOutdated =>
      exists && (schemaVersion ?? 1) < responsaCatalogSchemaVersion;

  /// האם הקטלוג נבנה מהתקנה שקיימת על המחשב הזה.
  ///
  /// הבדיקה נדרשת מפני שהקטלוג יושב בתיקיית הספרייה, והספרייה עוברת בין
  /// מחשבים. קטלוג שנבנה במחשב אחר מתאר מאגר שאינו כאן: ההפניות שבו
  /// נבנו ממהדורה אחרת, והפתיחה תיכשל או — גרוע מכך — תפתח ספר אחר.
  ///
  /// מחזיר `true` כשאי אפשר לדעת: קטלוג בלי `install_path` (סכמה 1),
  /// או מחשב שלא נמצאה בו התקנה כלל. אזהרה על סמך חוסר מידע היא אזהרה
  /// שהמשתמש לומד להתעלם ממנה.
  bool describesAnyOf(Iterable<String> installPaths) {
    final source = installPath?.trim();
    if (source == null || source.isEmpty) return true;
    final known = installPaths
        .map((value) => _comparablePath(value))
        .where((value) => value.isNotEmpty)
        .toSet();
    if (known.isEmpty) return true;
    return known.contains(_comparablePath(source));
  }

  /// נתיב להשוואה: מערכת הקבצים של Windows אינה רגישה לרישיות, ונתיב
  /// שנקרא מהרישום יכול להסתיים בלוכסן ונתיב שנקרא מתהליך חי לא.
  static String _comparablePath(String value) => value
      .trim()
      .replaceAll('/', r'\')
      .replaceAll(RegExp(r'\\+$'), '')
      .toLowerCase();
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
    final target = await _readyPath();
    if (target == null) return false;
    return File(target).exists();
  }

  /// הנתיב שעותק הביטחון שלו כבר יושר בסשן הזה.
  String? _syncedPath;

  /// מיישר את עותק הביטחון עכשיו. לפני בנייה — כדי שקטלוג שנמחק ישוחזר
  /// ומזהי הספרים יישמרו — ואחריה, כי הקטלוג הוחלף.
  Future<void> refreshBackup() async {
    final target = databasePath;
    if (target != null) await _syncBackup(target);
  }

  Future<void> _syncBackup(String target) async {
    // עותק שהיה נכתב מבדיקה לתיקיית הגיבויים האמיתית של המשתמש.
    if (databasePathOverride != null) return;
    try {
      await ResponsaCatalogBackup.sync(
        catalogPath: target,
        backupDirectory: await AppPaths.getBackupPath(),
      );
    } catch (error) {
      debugPrint('ResponsaCatalogRepository: backup sync failed: $error');
    }
  }

  /// נתיב הקטלוג, ואם הוא חסר — אחרי ניסיון לשחזר אותו מהעותק.
  ///
  /// קטלוג קיים אינו ממתין לעותק: תיקיית גיבויים ברשת שאינה זמינה הייתה
  /// תוקעת כל קריאה. קטלוג חסר נבדק בכל קריאה ולא פעם לסשן — ספרייה
  /// שעברה מיקום באמצע הסשן הייתה נשארת בלעדיו.
  Future<String?> _readyPath() async {
    final target = databasePath;
    if (target == null) return null;
    if (!File(target).existsSync()) {
      await _syncBackup(target);
    } else if (_syncedPath != target) {
      _syncedPath = target;
      unawaited(_syncBackup(target));
    }
    return target;
  }

  Future<sqlite3.Database?> _open() async {
    final target = await _readyPath();
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
    final db = await _open();
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
        nodeCount: int.tryParse(meta['catalog_node_count'] ?? ''),
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
  ///
  /// **באיזולט רקע.** כל שאר המתודות כאן קצרות ורצות אצל הקורא, אבל זו
  /// פותחת מסד, קוראת 8,500 שורות וממירה כל אחת — עבודה של מאות
  /// אלפי-שניות שרצה על ה-UI isolate ומפילה פריימים בדיוק ברגע שהמשתמש
  /// מחפש. היא נקראת פעם אחת לסשן.
  Future<List<ExternalLibraryBook>> loadBooks() async {
    final path = await _readyPath();
    if (path == null || !File(path).existsSync()) return const [];
    try {
      final rows = await Isolate.run(() {
        final db = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
        try {
          return db
              .select('SELECT * FROM books ORDER BY title COLLATE NOCASE')
              .map((row) => {for (final key in row.keys) key: row[key]})
              .toList();
        } finally {
          db.close();
        }
      });
      return [for (final row in rows) mapRow(row)];
    } catch (e) {
      debugPrint('ResponsaCatalogRepository: loadBooks failed: $e');
      return const [];
    }
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
    final db = await _open();
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
    final db = await _open();
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

  /// ממיר שורת קטלוג ל-[ExternalLibraryBook].
  ///
  /// `link` הוא `null` — לפרויקט השו"ת אין אתר.
  ///
  /// `author`, `pubPlace` ו-`pubDate` נקראים מ"רשימת הספרים והמהדורות"
  /// של התוכנה, ולכן הם ריקים לספר שאינו מופיע שם. הם נקראים דרך
  /// `row[...]` בלי לדרוש את העמודה: קטלוג בסכמה 4 ומטה אינו מכיר אותן,
  /// ושאילתה שדורשת אותן הייתה משאירה את המשתמש בלי ספרייה עד לרענון.
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
      author: _text(row['author']),
      pubPlace: _text(row['pub_place']),
      pubDate: _text(row['pub_date']),
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

  /// ערך טקסט מהקטלוג, או `null` כשהוא חסר או ריק.
  ///
  /// מחרוזת ריקה אינה "מידע ריק" אלא **מידע שגוי**: הממשק מחליט לפי
  /// `author != null` אם להציג שורת מחבר, ומחרוזת ריקה הייתה מייצרת
  /// שורה ריקה מתחת לכל ספר שאין לו מחבר.
  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
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
