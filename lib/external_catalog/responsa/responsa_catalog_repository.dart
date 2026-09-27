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

/// מטא-דאטה של הקטלוג המקומי. `fingerprint` מזהה שההתקנה שממנה נבנה
/// השתנתה ושצריך לבנות מחדש.
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

  /// קטלוג בסכמה ישנה עדיין נקרא (אחרת שדרוג מעלים את הספרייה מהמסך),
  /// אך מוצגת בקשה לרענון.
  bool get isOutdated =>
      exists && (schemaVersion ?? 1) < responsaCatalogSchemaVersion;

  /// הספרייה עוברת בין מחשבים, והפניות ממהדורה אחרת עלולות לפתוח ספר אחר.
  /// מחזיר `true` כשאי אפשר לדעת, כדי לא להרגיל את המשתמש להתעלם מאזהרה.
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

/// כל כשל מחזיר ערך ריק ולא חריג: קטלוג חסר הוא מצב רגיל (טרם נבנה),
/// ואסור שיפיל את חיפוש הספרים כולו.
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

  /// קטלוג קיים אינו ממתין לעותק (גיבוי ברשת לא זמין יתקע כל קריאה); קטלוג
  /// חסר נבדק בכל קריאה, כי הספרייה יכולה לעבור מיקום באמצע הסשן.
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

  /// באיזולט רקע: קריאת ~8,500 שורות וההמרה שלהן לוקחות מאות מילישניות
  /// ומפילות פריימים על ה-UI isolate בדיוק כשהמשתמש מחפש.
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

  /// נפרד מהכותרת בכוונה: `openBook("רא\"ש")` מחזיר מאות תוצאות שהראשונה
  /// בהן ספר אחר, ולכן נשמרת הפניה הכוללת הקשר.
  Future<String?> openRefFor(String externalKey) async =>
      (await openRefsFor(externalKey)).firstOrNull;

  /// ההפניה הראשית ואחריה החלופות - נבנות בזמן בניית הקטלוג, כשמבנה הנתיב
  /// ידוע; נסיגה בזמן ריצה הייתה רק ניחוש.
  Future<List<String>> openRefsFor(String externalKey) async {
    final db = await _open();
    if (db == null) return const [];
    try {
      // `SELECT *` ולא רשימת עמודות: קטלוג בסכמה 1 אינו מכיר `alt_refs`,
      // ושאילתה שדורשת אותו תיכשל ותשאיר את הספר בלי הפניה.
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

  /// נדרש בזמן פתיחה: על מחשב עם שתי התקנות, הפניה ממאגר אחד יכולה להוליך
  /// לספר אחר במאגר השני.
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

  /// העמודות נקראות דרך `row[...]` בלי לדרוש אותן: קטלוג בסכמה ישנה אינו
  /// מכיר את כולן, ושאילתה שדורשת אותן תשאיר את המשתמש בלי ספרייה.
  @visibleForTesting
  static ExternalLibraryBook mapRow(Map<String, Object?> row) {
    final key = row['external_key']?.toString() ?? '';
    final refPath = row['ref_path']?.toString() ?? '';
    // הנתיב המלא ולא רק השורש: `ספרות חז"ל` מתפצל לחמש קטגוריות באוצריא,
    // ורק הרמה השנייה מכריעה. בסכמה 2 אין את העמודה ונשאר רק השורש.
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

  /// ריק הופך ל-`null`: הממשק מציג שורת מחבר לפי `author != null`, ומחרוזת
  /// ריקה תייצר שורה ריקה מתחת לכל ספר בלי מחבר.
  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// הנתיב בעץ בלי שם הספר. כל רכיב עובר [ResponsaNames.displayOf] כי במאגר
  /// הוא מאוחסן בסדר חזותי, ובלי הסידור הנתיב מוצג שבור.
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
