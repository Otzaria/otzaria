import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/models/books.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:zstandard/zstandard.dart';

/// מנהל את מסד הקטלוגים החיצוניים (אוצר החכמה והיברובוקס).
class ExternalCatalogRepository {
  static const String releaseApiUrl =
      'https://api.github.com/repos/Otzaria/otzar-HB_catalog/releases/latest';
  static const String _versionMetaKey = 'version';

  static final ExternalCatalogRepository instance = ExternalCatalogRepository();

  final http.Client _httpClient;
  final Zstandard _zstandard;

  ExternalCatalogRepository({
    http.Client? httpClient,
    Zstandard? zstandard,
  })  : _httpClient = httpClient ?? http.Client(),
        _zstandard = zstandard ?? Zstandard();

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
    return true;
  }

  /// מוריד את מסד הקטלוגים מהרליס האחרון ומחלץ אותו ליד `seforim.db`.
  Future<void> downloadLatestDatabase() async {
    final release = await _fetchLatestReleaseInfo();
    await _downloadReleaseDatabase(release.databaseAsset);
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
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    await dbFile.writeAsBytes(dbBytes, flush: true);
  }

  Future<List<T>> _loadBooks<T extends Book>({
    required String tableName,
    required T Function(Map<String, Object?> row) mapper,
  }) async {
    if (!await databaseExists()) {
      return <T>[];
    }

    sqlite3.Database? db;
    try {
      db = sqlite3.sqlite3.open(databasePath, mode: sqlite3.OpenMode.readOnly);

      final rows = db.select(
        'SELECT * FROM $tableName ORDER BY title COLLATE NOCASE',
      );

      return rows
          .map((row) => mapper(row as Map<String, Object?>))
          .toList(growable: false);
    } catch (e) {
      debugPrint('Error loading external catalog table $tableName: $e');
      return <T>[];
    } finally {
      db?.close();
    }
  }

  Future<ExternalCatalogReleaseInfo> _fetchLatestReleaseInfo() async {
    final response = await _httpClient.get(
      Uri.parse(releaseApiUrl),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
          'שגיאה בקבלת רליס הקטלוגים האחרון: ${response.statusCode}');
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
    final response = await _httpClient.get(Uri.parse(downloadUrl));
    if (response.statusCode != 200) {
      throw Exception('שגיאה בהורדת DB הקטלוגים: ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<String> _downloadTextAsset(String downloadUrl) async {
    final response = await _httpClient.get(Uri.parse(downloadUrl));
    if (response.statusCode != 200) {
      throw Exception(
          'שגיאה בהורדת קובץ הגרסה של הקטלוגים: ${response.statusCode}');
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
