import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/models/books.dart';
import 'package:path/path.dart' as path;
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:zstandard/zstandard.dart';

/// מנהל את מסד הקטלוגים החיצוניים (אוצר החכמה והיברובוקס).
class ExternalCatalogRepository {
  static const String releaseApiUrl =
      'https://api.github.com/repos/Otzaria/otzar-HB_catalog/releases/latest';
  static const String _versionMetaKey = 'version';

  /// תקרת זמן לקריאות מטא-דאטה (פרטי רליס, קובץ גרסה).
  ///
  /// בלי תקרה, `http.Client` ממתין ללא הגבלה — ברשתות מסוננות שמחזיקות
  /// חיבורים פתוחים (סינון בצד שרת) בדיקת העדכון בעליית האפליקציה נתקעת לדקות.
  static const Duration defaultApiTimeout = Duration(seconds: 15);

  /// תקרת זמן להורדת קובץ ה-DB של הקטלוגים.
  static const Duration defaultDownloadTimeout = Duration(minutes: 5);

  static final ExternalCatalogRepository instance = ExternalCatalogRepository();

  final http.Client _httpClient;
  final Zstandard _zstandard;
  final Duration apiTimeout;
  final Duration downloadTimeout;

  ExternalCatalogRepository({
    http.Client? httpClient,
    Zstandard? zstandard,
    this.apiTimeout = defaultApiTimeout,
    this.downloadTimeout = defaultDownloadTimeout,
  }) : _httpClient = httpClient ?? http.Client(),
       _zstandard = zstandard ?? Zstandard() {
    HttpClientRegistry.register(_httpClient.close);
  }

  /// מחזיר את נתיב קובץ ה-DB של הקטלוגים.
  String get databasePath => DatabaseConstants.getExternalCatalogDatabasePath();

  /// בודק האם מסד הקטלוגים קיים ליד `seforim.db`.
  Future<bool> databaseExists() async {
    return File(databasePath).exists();
  }

  /// מחזיר את ספרי אוצר החכמה מתוך מסד הקטלוגים החיצוני.
  Future<List<ExternalLibraryBook>> getOtzarBooks() async {
    return _loadBooks(
      tableName: 'otzar_hahochma',
      mapper: _mapOtzarBook,
    );
  }

  /// מחזיר את ספרי היברובוקס מתוך מסד הקטלוגים החיצוני.
  Future<List<Book>> getHebrewBooks() async {
    return _loadBooks(
      tableName: 'hebrew_books',
      mapper: _mapHebrewBook,
    );
  }

  /// מחזיר ספרי היברובוקס לפי קבוצת מזהים בלבד (`id_book`).
  ///
  /// בניגוד ל-[getHebrewBooks] שטוען את כל הטבלה (~60K שורות), כאן נטענים
  /// רק הספרים המבוקשים דרך `WHERE id_book IN (...)`. משמש לטעינת המטא-דאטה
  /// של ספרים שיש להם PDF מקומי, בלי לשלם טעינת קטלוג מלאה בכל חיפוש.
  Future<List<Book>> getHebrewBooksByIds(Iterable<int> ids) async {
    return _loadBooks(
      tableName: 'hebrew_books',
      mapper: _mapHebrewBook,
      idColumn: 'id_book',
      ids: ids,
    );
  }

  /// מחזיר את גרסת מסד הקטלוגים המקומי, אם קיימת.
  Future<int?> getCurrentDatabaseVersion() async {
    if (!await databaseExists()) {
      return null;
    }

    sqlite3.Database? db;
    try {
      db = sqlite3.sqlite3.open(databasePath, mode: sqlite3.OpenMode.readOnly);

      final result = db.select(
        'SELECT value FROM db_meta WHERE key = ? LIMIT 1',
        [_versionMetaKey],
      );
      if (result.isEmpty) {
        return null;
      }

      final rawValue = result.first['value']?.toString();
      return parseVersionText(rawValue);
    } catch (e) {
      debugPrint('Error reading external catalog DB version: $e');
      return null;
    } finally {
      db?.close();
    }
  }

  /// מחזיר את גרסת הקטלוג העדכנית ביותר שפורסמה ב-GitHub.
  Future<int> fetchLatestDatabaseVersion() async {
    final release = await _fetchLatestReleaseInfo();
    return _fetchReleaseVersion(release);
  }

  /// מעדכן את מסד הקטלוגים רק אם קיימת גרסה חדשה יותר.
  ///
  /// מחזיר `true` אם בוצע עדכון בפועל.
  Future<bool> updateDatabaseIfNeeded() async {
    if (!await databaseExists()) {
      return false;
    }

    final currentVersion = await getCurrentDatabaseVersion();
    final release = await _fetchLatestReleaseInfo();
    final latestVersion = await _fetchReleaseVersion(release);

    if (currentVersion != null && latestVersion <= currentVersion) {
      return false;
    }

    await _downloadReleaseDatabase(release.databaseAsset);
    _ensureVersionStamped(latestVersion);
    return true;
  }

  /// מוודא שלמסד הקטלוגים שהורד יש גרסה קריאה ב-`db_meta`.
  ///
  /// בלי זה, מסד שהורד ללא מפתח `version` משאיר את הגרסה המקומית null,
  /// ו-[updateDatabaseIfNeeded] מוריד את הקטלוג מחדש בכל עליית אפליקציה.
  void _ensureVersionStamped(int version) {
    sqlite3.Database? db;
    try {
      db = sqlite3.sqlite3.open(databasePath);
      db.execute(
        'CREATE TABLE IF NOT EXISTS db_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      final result = db.select(
        'SELECT value FROM db_meta WHERE key = ? LIMIT 1',
        [_versionMetaKey],
      );
      if (result.isNotEmpty &&
          parseVersionText(result.first['value']?.toString()) != null) {
        return;
      }
      db.execute(
        'INSERT OR REPLACE INTO db_meta (key, value) VALUES (?, ?)',
        [_versionMetaKey, version.toString()],
      );
    } catch (e) {
      debugPrint('Error stamping external catalog DB version: $e');
    } finally {
      db?.close();
    }
  }

  /// מוריד את מסד הקטלוגים מהרליס האחרון ומחלץ אותו ליד `seforim.db`.
  Future<void> downloadLatestDatabase() async {
    final release = await _fetchLatestReleaseInfo();
    await _downloadReleaseDatabase(release.databaseAsset);
    // החתמת גרסה גם במסלול ההורדה הראשונית — אחרת DB שהורד בלי
    // db_meta.version משאיר גרסה מקומית null, ו-maybeAutoSyncCatalogs יוריד
    // אותו שוב בעלייה הבאה. best-effort: כשל בקריאת הגרסה (version.txt חסר)
    // לא מכשיל את ההורדה עצמה, שהצליחה גם בלעדיו עד כה.
    try {
      _ensureVersionStamped(await _fetchReleaseVersion(release));
    } catch (e) {
      debugPrint('Could not stamp external catalog version after download: $e');
    }
  }

  Future<void> _downloadReleaseDatabase(
    ExternalCatalogReleaseAsset asset,
  ) async {
    final dbDir = Directory(path.dirname(databasePath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    final downloadedBytes = await _downloadAssetBytes(asset.downloadUrl);
    final dbBytes = asset.isCompressed
        ? await _zstandard.decompress(downloadedBytes)
        : downloadedBytes;
    if (dbBytes == null) {
      throw Exception('חילוץ DB הקטלוגים נכשל');
    }

    final dbFile = File(databasePath);
    final tempFile = File('$databasePath.download');
    final backupFile = File('$databasePath.bak');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await tempFile.writeAsBytes(dbBytes, flush: true);

    // מעבירים את הקובץ הקיים לגיבוי לפני ההחלפה (במקום למחוק אותו), כדי שאם
    // ההחלפה תיכשל באמצע — נוכל לשחזר ולא להשאיר את המשתמש ללא קטלוג כלל.
    var backupCreated = false;
    var replaced = false;
    try {
      if (await dbFile.exists()) {
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
        try {
          await dbFile.rename(backupFile.path);
          backupCreated = true;
        } on FileSystemException catch (e) {
          if (_isFileInUseError(e)) {
            throw ExternalCatalogDatabaseBusyException(databasePath, e);
          }
          rethrow;
        }
      }

      try {
        await tempFile.rename(databasePath);
        replaced = true;
      } on FileSystemException catch (e) {
        // ההחלפה נכשלה — משחזרים את הגיבוי כדי לא להשאיר את המשתמש ללא קטלוג.
        if (backupCreated) {
          try {
            await backupFile.rename(databasePath);
            backupCreated = false;
          } catch (_) {
            // השחזור נכשל — משאירים את הגיבוי על כנו לשחזור ידני (אל תמחק!).
          }
        }
        if (_isFileInUseError(e)) {
          throw ExternalCatalogDatabaseBusyException(databasePath, e);
        }
        rethrow;
      }
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      // מוחקים את הגיבוי רק אם ההחלפה הצליחה (אז הוא מיותר). אם ההחלפה
      // נכשלה — הגיבוי הוא הקטלוג היחיד ששרד, ואסור למחוק אותו.
      if (replaced && backupCreated && await backupFile.exists()) {
        await backupFile.delete();
      }
    }
  }

  /// מספר המזהים המקסימלי לכל שאילתת `IN` — מתחת למגבלת המשתנים של SQLite.
  static const int _idChunkSize = 900;

  /// טוען ספרים מטבלה בקטלוג.
  ///
  /// כברירת מחדל טוען את כל הטבלה ממוינת לפי כותרת. אם הועברו [idColumn]
  /// ו-[ids], נטענים רק הספרים שמזההם נמצא ב-[ids] (ב-chunks כדי לעמוד
  /// במגבלת המשתנים של SQLite), ללא מיון.
  Future<List<T>> _loadBooks<T extends Book>({
    required String tableName,
    required T Function(Map<String, Object?> row) mapper,
    String? idColumn,
    Iterable<int>? ids,
  }) async {
    if (!await databaseExists()) {
      return <T>[];
    }

    sqlite3.Database? db;
    try {
      db = sqlite3.sqlite3.open(databasePath, mode: sqlite3.OpenMode.readOnly);

      if (idColumn != null && ids != null) {
        final idList = ids.toList();
        if (idList.isEmpty) {
          return <T>[];
        }
        final results = <T>[];
        for (var i = 0; i < idList.length; i += _idChunkSize) {
          final end = (i + _idChunkSize < idList.length)
              ? i + _idChunkSize
              : idList.length;
          final chunk = idList.sublist(i, end);
          final placeholders = List.filled(chunk.length, '?').join(',');
          final rows = db.select(
            'SELECT * FROM $tableName WHERE $idColumn IN ($placeholders)',
            chunk,
          );
          results.addAll(
            rows.map((row) => mapper(row as Map<String, Object?>)),
          );
        }
        return results;
      }

      final rows = db.select(
        'SELECT * FROM $tableName ORDER BY title COLLATE NOCASE',
      );

      return rows
          .map((row) => mapper(row as Map<String, Object?>))
          .toList(growable: false);
    } catch (e, st) {
      // דגרדציה מכוונת: כשל כאן (DB פגום/סכמה) לא מפיל את חיפוש הספרים
      // כולו — רק הספרים החיצוניים חסרים. הלוג המלא נדרש לאבחון.
      debugPrint('Error loading external catalog table $tableName: $e\n$st');
      return <T>[];
    } finally {
      db?.close();
    }
  }

  Future<ExternalCatalogReleaseInfo> _fetchLatestReleaseInfo() async {
    final response = await _httpClient
        .get(
          Uri.parse(releaseApiUrl),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(apiTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'שגיאה בקבלת רליס הקטלוגים האחרון: ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('מבנה תשובת GitHub של קטלוג הספרים אינו תקין');
    }

    final databaseAsset = parseLatestDatabaseAsset(decoded);
    if (databaseAsset == null) {
      throw Exception('לא נמצא קובץ DB של הקטלוגים ברליס האחרון');
    }

    return ExternalCatalogReleaseInfo(
      tagName: decoded['tag_name']?.toString() ?? '',
      databaseAsset: databaseAsset,
      versionAsset: parseLatestVersionAsset(decoded),
    );
  }

  Future<Uint8List> _downloadAssetBytes(String downloadUrl) async {
    final response = await _httpClient
        .get(Uri.parse(downloadUrl))
        .timeout(downloadTimeout);
    if (response.statusCode != 200) {
      throw Exception('שגיאה בהורדת DB הקטלוגים: ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<String> _downloadTextAsset(String downloadUrl) async {
    final response = await _httpClient
        .get(Uri.parse(downloadUrl))
        .timeout(apiTimeout);
    if (response.statusCode != 200) {
      throw Exception(
        'שגיאה בהורדת קובץ הגרסה של הקטלוגים: ${response.statusCode}',
      );
    }
    return utf8.decode(response.bodyBytes);
  }

  Future<int> _fetchReleaseVersion(ExternalCatalogReleaseInfo release) async {
    final versionAsset = release.versionAsset;
    if (versionAsset == null) {
      throw Exception(
        'לא נמצא ${DatabaseConstants.externalCatalogVersionFileName} ברליס ${release.tagName}',
      );
    }

    final versionText = await _downloadTextAsset(versionAsset.downloadUrl);
    final version = parseVersionText(versionText);
    if (version == null) {
      throw Exception(
        'לא ניתן לקרוא את גרסת הקטלוג מתוך ${versionAsset.fileName}',
      );
    }

    return version;
  }

  @visibleForTesting
  static ExternalCatalogReleaseAsset? parseLatestDatabaseAsset(
    Map<String, dynamic> releaseJson,
  ) {
    final assets = releaseJson['assets'];
    if (assets is! List) {
      return null;
    }

    ExternalCatalogReleaseAsset? fallbackDb;

    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) {
        continue;
      }

      final name = asset['name']?.toString() ?? '';
      final downloadUrl = asset['browser_download_url']?.toString() ?? '';
      if (downloadUrl.isEmpty) {
        continue;
      }

      if (name == DatabaseConstants.externalCatalogArchiveFileName) {
        return ExternalCatalogReleaseAsset(
          fileName: name,
          downloadUrl: downloadUrl,
          isCompressed: true,
        );
      }

      if (name == DatabaseConstants.externalCatalogDatabaseFileName) {
        fallbackDb = ExternalCatalogReleaseAsset(
          fileName: name,
          downloadUrl: downloadUrl,
          isCompressed: false,
        );
      }
    }

    return fallbackDb;
  }

  @visibleForTesting
  static ExternalCatalogReleaseAsset? parseLatestVersionAsset(
    Map<String, dynamic> releaseJson,
  ) {
    final assets = releaseJson['assets'];
    if (assets is! List) {
      return null;
    }

    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) {
        continue;
      }

      final name = asset['name']?.toString() ?? '';
      final downloadUrl = asset['browser_download_url']?.toString() ?? '';
      if (name == DatabaseConstants.externalCatalogVersionFileName &&
          downloadUrl.isNotEmpty) {
        return ExternalCatalogReleaseAsset(
          fileName: name,
          downloadUrl: downloadUrl,
          isCompressed: false,
        );
      }
    }

    return null;
  }

  @visibleForTesting
  static int? parseVersionText(String? rawValue) {
    if (rawValue == null) {
      return null;
    }

    final match = RegExp(r'(\d+)').firstMatch(rawValue.trim());
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  static bool _isFileInUseError(FileSystemException error) {
    final message = error.message.toLowerCase();
    final osMessage = error.osError?.message.toLowerCase() ?? '';
    return message.contains('being used by another process') ||
        message.contains('used by another process') ||
        message.contains('process cannot access the file') ||
        message.contains('access is denied') ||
        osMessage.contains('being used by another process') ||
        osMessage.contains('used by another process') ||
        osMessage.contains('process cannot access the file') ||
        osMessage.contains('access is denied');
  }

  ExternalLibraryBook _mapOtzarBook(Map<String, Object?> row) {
    final bookId = (row['book_id'] as num).toInt();
    final authors = _decodeStringList(row['authors']);
    final subjects = _decodeStringList(row['subjects']);
    final fromYear = row['from_year']?.toString().trim();
    final toYear = row['to_year']?.toString().trim();
    final years = _buildYearRange(fromYear, toYear);
    final places = _normalizeNullableString(row['places']);

    return ExternalLibraryBook(
      title: row['title']?.toString() ?? '',
      id: bookId,
      author: authors.isEmpty ? null : authors.join(', '),
      pubPlace: places,
      pubDate: years,
      topics: subjects.join(', '),
      link: 'https://tablet.otzar.org/book/book.php?book=$bookId',
      externalLibraryId: 'oh:$bookId',
    );
  }

  ExternalLibraryBook _mapHebrewBook(Map<String, Object?> row) {
    final bookId = (row['id_book'] as num).toInt();
    final tags = _decodeStringList(row['tags']);
    final author = _normalizeNullableString(row['author']);
    final printingPlace = _normalizeNullableString(row['printing_place']);
    final printingYear = _normalizeNullableString(row['printing_year']);
    final pubDateYear = row['pub_date']?.toString();

    return ExternalLibraryBook(
      title: row['title']?.toString() ?? '',
      id: bookId,
      author: author,
      pubPlace: printingPlace,
      pubDate: printingYear ?? pubDateYear,
      topics: tags.join(', '),
      link: 'https://hebrewbooks.org/$bookId',
      externalLibraryId: 'hb:$bookId',
    );
  }

  static List<String> _decodeStringList(Object? rawValue) {
    if (rawValue == null) {
      return const <String>[];
    }

    final value = rawValue.toString().trim();
    if (value.isEmpty) {
      return const <String>[];
    }

    if (value.startsWith('[') && value.endsWith(']')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded
              .map((item) => item?.toString().trim() ?? '')
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
        }
      } catch (_) {
        // Fall back to plain-text splitting below.
      }
    }

    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String? _buildYearRange(String? fromYear, String? toYear) {
    if (fromYear == null || fromYear.isEmpty) {
      return toYear == null || toYear.isEmpty ? null : toYear;
    }
    if (toYear == null || toYear.isEmpty || toYear == fromYear) {
      return fromYear;
    }
    return '$fromYear-$toYear';
  }

  static String? _normalizeNullableString(Object? value) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}

class ExternalCatalogReleaseAsset {
  const ExternalCatalogReleaseAsset({
    required this.fileName,
    required this.downloadUrl,
    required this.isCompressed,
  });

  final String fileName;
  final String downloadUrl;
  final bool isCompressed;
}

class ExternalCatalogReleaseInfo {
  const ExternalCatalogReleaseInfo({
    required this.tagName,
    required this.databaseAsset,
    required this.versionAsset,
  });

  final String tagName;
  final ExternalCatalogReleaseAsset databaseAsset;
  final ExternalCatalogReleaseAsset? versionAsset;
}

class ExternalCatalogDatabaseBusyException implements Exception {
  ExternalCatalogDatabaseBusyException(this.databasePath, [this.innerError]);

  final String databasePath;
  final Object? innerError;

  @override
  String toString() {
    return 'קובץ הקטלוג נמצא בשימוש ולא ניתן לעדכן אותו כעת: $databasePath';
  }
}
