import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/services/data_collection_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:zstandard/zstandard.dart';

class FileSyncRepository {
  final String githubOwner;
  final String repositoryName;
  bool isSyncing = false;
  int _currentProgress = 0;
  int _totalFiles = 0;
  final http.Client _httpClient;
  final Zstandard _zstandard;
  final Future<Uint8List> Function(Uint8List compressedBytes)? _decompressDiff;

  FileSyncRepository({
    required this.githubOwner,
    required this.repositoryName,
    http.Client? httpClient,
    Zstandard? zstandard,
    Future<Uint8List> Function(Uint8List compressedBytes)? decompressDiff,
  })  : _httpClient = httpClient ?? http.Client(),
        _zstandard = zstandard ?? Zstandard(),
        _decompressDiff = decompressDiff;

  int get currentProgress => _currentProgress;
  int get totalFiles => _totalFiles;

  Future<List<String>> checkForUpdates({int? targetVersion}) async {
    final currentVersion = await getCurrentLibraryVersion();
    final assets = await fetchAvailableDiffAssets();
    final chain = buildUpdateChain(
      currentVersion: currentVersion,
      availableAssets: assets,
      targetVersion: targetVersion,
    );
    return chain.map((asset) => asset.assetName).toList();
  }

  Future<int> syncFiles({int? targetVersion}) async {
    if (isSyncing) {
      return 0;
    }

    isSyncing = true;
    _currentProgress = 0;
    _totalFiles = 0;

    try {
      final currentVersion = await getCurrentLibraryVersion();
      final assets = await fetchAvailableDiffAssets();
      final chain = buildUpdateChain(
        currentVersion: currentVersion,
        availableAssets: assets,
        targetVersion: targetVersion,
      );

      if (targetVersion != null &&
          currentVersion < targetVersion &&
          (chain.isEmpty || chain.last.toVersion != targetVersion)) {
        throw Exception(
          'לא נמצא רצף עדכונים מלא מגרסה $currentVersion לגרסה $targetVersion',
        );
      }

      _totalFiles = chain.length;

      if (chain.isEmpty) {
        developer.log(
          'No library DIFF updates found for version $currentVersion',
          name: 'FileSyncRepository',
        );
      } else {
        for (final asset in chain) {
          if (!isSyncing) {
            break;
          }

          developer.log(
            'Applying library DIFF ${asset.assetName}',
            name: 'FileSyncRepository',
          );

          final sql = await _downloadAndExtractDiff(asset);
          await _applyDiffSql(sql);
          _currentProgress++;
        }
      }

      return _currentProgress;
    } catch (e) {
      developer.log(
        'Error during DB DIFF sync',
        name: 'FileSyncRepository',
        error: e,
      );
      rethrow;
    } finally {
      isSyncing = false;
    }
  }

  Future<void> stopSyncing() async {
    isSyncing = false;
  }

  Future<int> getCurrentLibraryVersion() async {
    sqlite3.Database? db;
    try {
      db = _openRawDatabase();
      final result = db.select(
        'SELECT value FROM db_meta WHERE key = ? LIMIT 1',
        ['content_version_int'],
      );

      if (result.isNotEmpty) {
        final rawValue = result.first['value']?.toString();
        final parsed = int.tryParse(rawValue ?? '');
        if (parsed != null) {
          return parsed;
        }
      }
    } finally {
      db?.close();
    }

    final displayVersion = await DataCollectionService().readLibraryVersion();
    final match = RegExp(r'(\d+)').firstMatch(displayVersion);
    final fallback = match == null ? null : int.tryParse(match.group(1)!);
    if (fallback != null) {
      return fallback;
    }

    throw Exception('לא ניתן לזהות את גרסת מסד הנתונים הנוכחית');
  }

  Future<List<DiffReleaseAsset>> fetchAvailableDiffAssets() async {
    final url = Uri.parse(
        'https://api.github.com/repos/$githubOwner/$repositoryName/releases');
    final response = await _httpClient.get(
      url,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('שגיאה בקבלת רשימת רליסים: ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw Exception('מבנה התשובה של GitHub אינו תקין');
    }

    final assets = <DiffReleaseAsset>[];

    for (final rawRelease in decoded) {
      if (rawRelease is! Map<String, dynamic>) {
        continue;
      }

      if (rawRelease['draft'] == true || rawRelease['prerelease'] == true) {
        continue;
      }

      final tagName = rawRelease['tag_name']?.toString() ?? '';
      final releaseName = rawRelease['name']?.toString() ?? tagName;
      final rawAssets = rawRelease['assets'];

      if (rawAssets is! List) {
        continue;
      }

      for (final rawAsset in rawAssets) {
        if (rawAsset is! Map<String, dynamic>) {
          continue;
        }

        final parsed = DiffReleaseAsset.tryParse(
          rawAsset,
          releaseTag: tagName,
          releaseName: releaseName,
        );
        if (parsed != null) {
          assets.add(parsed);
        }
      }
    }

    assets.sort(
      (a, b) => a.fromVersion == b.fromVersion
          ? a.toVersion.compareTo(b.toVersion)
          : a.fromVersion.compareTo(b.fromVersion),
    );

    return assets;
  }

  @visibleForTesting
  static List<DiffReleaseAsset> buildUpdateChain({
    required int currentVersion,
    required List<DiffReleaseAsset> availableAssets,
    int? targetVersion,
  }) {
    final bySourceVersion = <int, List<DiffReleaseAsset>>{};

    for (final asset in availableAssets) {
      bySourceVersion.putIfAbsent(asset.fromVersion, () => []).add(asset);
    }

    final chain = <DiffReleaseAsset>[];
    var version = currentVersion;

    while (true) {
      final candidates = bySourceVersion[version];
      if (candidates == null || candidates.isEmpty) {
        break;
      }

      DiffReleaseAsset? nextAsset;
      for (final candidate in candidates) {
        if (candidate.toVersion == version + 1) {
          nextAsset = candidate;
          break;
        }
      }

      if (nextAsset == null) {
        break;
      }

      chain.add(nextAsset);
      version = nextAsset.toVersion;
      if (targetVersion != null && version >= targetVersion) {
        break;
      }
    }

    return chain;
  }

  Future<String> _downloadAndExtractDiff(DiffReleaseAsset asset) async {
    final response = await _httpClient.get(
      Uri.parse(asset.downloadUrl),
      headers: const {'Accept': 'application/octet-stream'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'שגיאה בהורדת ${asset.assetName}: ${response.statusCode}',
      );
    }

    final compressedBytes = Uint8List.fromList(response.bodyBytes);
    final extractedBytes = _decompressDiff != null
        ? await _decompressDiff(compressedBytes)
        : await _zstandard.decompress(compressedBytes);

    if (extractedBytes == null || extractedBytes.isEmpty) {
      throw Exception('קובץ ה-DIFF שחולץ ריק: ${asset.assetName}');
    }

    return utf8.decode(extractedBytes);
  }

  Future<void> _applyDiffSql(String sql) async {
    final statements = splitSqlStatements(sql);
    if (statements.isEmpty) {
      throw Exception('קובץ ה-DIFF אינו מכיל פקודות SQL');
    }

    await SqliteDataProvider.instance.dispose();

    sqlite3.Database? db;
    try {
      db = _openRawDatabase();

      for (final statement in statements) {
        if (!isSyncing) {
          throw Exception('הסינכרון בוטל');
        }

        db.execute(statement);
      }
    } finally {
      db?.close();
    }
  }

  sqlite3.Database _openRawDatabase() {
    return sqlite3.sqlite3.open(
      DatabaseConstants.getDatabasePath(),
    );
  }

  @visibleForTesting
  static List<String> splitSqlStatements(String sql) {
    final statements = <String>[];
    var buffer = StringBuffer();
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var inLineComment = false;
    var inBlockComment = false;

    for (var i = 0; i < sql.length; i++) {
      final char = sql[i];
      final nextChar = i + 1 < sql.length ? sql[i + 1] : '';

      if (inLineComment) {
        buffer.write(char);
        if (char == '\n') {
          inLineComment = false;
        }
        continue;
      }

      if (inBlockComment) {
        buffer.write(char);
        if (char == '*' && nextChar == '/') {
          buffer.write(nextChar);
          i++;
          inBlockComment = false;
        }
        continue;
      }

      if (!inSingleQuote && !inDoubleQuote) {
        if (char == '-' && nextChar == '-') {
          buffer.write(char);
          buffer.write(nextChar);
          i++;
          inLineComment = true;
          continue;
        }

        if (char == '/' && nextChar == '*') {
          buffer.write(char);
          buffer.write(nextChar);
          i++;
          inBlockComment = true;
          continue;
        }
      }

      if (char == "'" && !inDoubleQuote) {
        if (inSingleQuote && nextChar == "'") {
          buffer.write(char);
          buffer.write(nextChar);
          i++;
          continue;
        }

        inSingleQuote = !inSingleQuote;
        buffer.write(char);
        continue;
      }

      if (char == '"' && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
        buffer.write(char);
        continue;
      }

      if (char == ';' && !inSingleQuote && !inDoubleQuote) {
        final statement = buffer.toString().trim();
        if (statement.isNotEmpty) {
          statements.add(statement);
        }
        buffer = StringBuffer();
        continue;
      }

      buffer.write(char);
    }

    final trailingStatement = buffer.toString().trim();
    if (trailingStatement.isNotEmpty) {
      statements.add(trailingStatement);
    }

    return statements;
  }
}

class DiffReleaseAsset {
  final int fromVersion;
  final int toVersion;
  final String assetName;
  final String downloadUrl;
  final String releaseTag;
  final String releaseName;

  const DiffReleaseAsset({
    required this.fromVersion,
    required this.toVersion,
    required this.assetName,
    required this.downloadUrl,
    required this.releaseTag,
    required this.releaseName,
  });

  static final RegExp _assetPattern =
      RegExp(r'^(\d+)-(\d+)\.DIFF\.zst$', caseSensitive: false);

  static DiffReleaseAsset? tryParse(
    Map<String, dynamic> asset, {
    required String releaseTag,
    required String releaseName,
  }) {
    final assetName = asset['name']?.toString();
    final downloadUrl = asset['browser_download_url']?.toString();

    if (assetName == null || downloadUrl == null) {
      return null;
    }

    final match = _assetPattern.firstMatch(assetName);
    if (match == null) {
      return null;
    }

    final fromVersion = int.tryParse(match.group(1)!);
    final toVersion = int.tryParse(match.group(2)!);

    if (fromVersion == null || toVersion == null || toVersion <= fromVersion) {
      return null;
    }

    return DiffReleaseAsset(
      fromVersion: fromVersion,
      toVersion: toVersion,
      assetName: assetName,
      downloadUrl: downloadUrl,
      releaseTag: releaseTag,
      releaseName: releaseName,
    );
  }
}
