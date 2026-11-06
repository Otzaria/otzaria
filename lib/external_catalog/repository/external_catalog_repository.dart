import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/models/books.dart';
import 'package:path/path.dart' as path;
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

typedef ExternalCatalogExtractor =
    Future<void> Function(
      String archivePath,
      String outputPath, {
      required int maxOutputBytes,
      bool Function()? isCancelled,
      void Function(double)? onProgress,
    });

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
  final ExternalCatalogExtractor _extractZst;
  final Duration apiTimeout;
  final Duration downloadTimeout;
  final int maxOutputBytes;
  final int maxDownloadBytes;
  final void Function(String source, String destination)? _beforeFileRename;

  ExternalCatalogRepository({
    http.Client? httpClient,
    @visibleForTesting ExternalCatalogExtractor? extractZst,
    @visibleForTesting this._beforeFileRename,
    this.apiTimeout = defaultApiTimeout,
    this.downloadTimeout = defaultDownloadTimeout,
    this.maxOutputBytes = kDefaultMaxExtractedBytes,
    this.maxDownloadBytes = kDefaultMaxExtractedBytes,
  }) : _httpClient = httpClient ?? http.Client(),
       _extractZst = extractZst ?? ZstdStreamExtractor.extractToFile {
    if (maxOutputBytes <= 0 || maxDownloadBytes <= 0) {
      throw ArgumentError('Catalog size limits must be positive');
    }
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
    return _loadBooks(tableName: 'otzar_hahochma', mapper: _mapOtzarBook);
  }

  /// מחזיר את ספרי היברובוקס מתוך מסד הקטלוגים החיצוני.
  Future<List<Book>> getHebrewBooks() async {
    return _loadBooks(tableName: 'hebrew_books', mapper: _mapHebrewBook);
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

  /// מזהי היברובוקס הממופים לספר אוצריא, מסודרים לפי איכות ההתאמה
  /// (`is_best` ואז `confidence`). מחזיר רשימה ריקה כשאין מיפוי או DB.
  Future<List<int>> getHebrewBookIdsForOtzariaId(int otzariaId) async {
    return _selectMappingColumn(
      select: 'hb_id',
      where: 'otzaria_id = ?',
      argument: otzariaId,
    );
  }

  /// מזהי ספרי אוצריא הממופים לספר היברובוקס — הכיוון ההפוך של
  /// [getHebrewBookIdsForOtzariaId].
  Future<List<int>> getOtzariaIdsForHebrewBookId(int hbId) async {
    return _selectMappingColumn(
      select: 'otzaria_id',
      where: 'hb_id = ?',
      argument: hbId,
    );
  }

  Future<List<int>> _selectMappingColumn({
    required String select,
    required String where,
    required int argument,
  }) async {
    if (!await databaseExists()) return const [];
    sqlite3.Database? db;
    try {
      db = sqlite3.sqlite3.open(databasePath, mode: sqlite3.OpenMode.readOnly);
      final rows = db.select(
        'SELECT $select FROM otzaria_hebrew_books WHERE $where '
        'ORDER BY is_best DESC, confidence DESC LIMIT 20',
        [argument],
      );
      return [
        for (final row in rows)
          if (row.values.first case final int id) id,
      ];
    } catch (e) {
      debugPrint('ExternalCatalogRepository: mapping query failed: $e');
      return const [];
    } finally {
      db?.close();
    }
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

  /// מעדכן את מסד הקטלוגים רק אם קיימת גרסה חדשה יותר.
  ///
  /// מחזיר `true` אם בוצע עדכון בפועל.
  Future<bool> updateDatabaseIfNeeded({
    VoidCallback? onUpdateAvailable,
    bool Function()? isCancelled,
    void Function(int received, int? total)? onDownloadProgress,
    void Function(double)? onExtractionProgress,
  }) async {
    _checkCancelled(isCancelled);
    await _recoverInterruptedInstall();
    if (!await databaseExists()) {
      return false;
    }

    final currentVersion = await getCurrentDatabaseVersion();
    final release = await _fetchLatestReleaseInfo();
    final latestVersion = await _fetchReleaseVersion(release);

    if (currentVersion != null && latestVersion <= currentVersion) {
      return false;
    }

    onUpdateAvailable?.call();
    await _downloadReleaseDatabase(
      release.databaseAsset,
      isCancelled: isCancelled,
      onDownloadProgress: onDownloadProgress,
      onExtractionProgress: onExtractionProgress,
      version: latestVersion,
    );
    return true;
  }

  /// מוודא שלמסד הקטלוגים שהורד יש גרסה קריאה ב-`db_meta`.
  ///
  /// בלי זה, מסד שהורד ללא מפתח `version` משאיר את הגרסה המקומית null,
  /// ו-[updateDatabaseIfNeeded] מוריד את הקטלוג מחדש בכל עליית אפליקציה.
  void _ensureVersionStamped(int version, String filePath) {
    sqlite3.Database? db;
    try {
      db = sqlite3.sqlite3.open(filePath);
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
      db.execute('INSERT OR REPLACE INTO db_meta (key, value) VALUES (?, ?)', [
        _versionMetaKey,
        version.toString(),
      ]);
    } catch (e) {
      debugPrint('Error stamping external catalog DB version: $e');
    } finally {
      db?.close();
    }
  }

  /// מוריד את מסד הקטלוגים מהרליס האחרון ומחלץ אותו ליד `seforim.db`.
  Future<void> downloadLatestDatabase({
    bool Function()? isCancelled,
    void Function(int received, int? total)? onDownloadProgress,
    void Function(double)? onExtractionProgress,
  }) async {
    _checkCancelled(isCancelled);
    await _recoverInterruptedInstall();
    final release = await _fetchLatestReleaseInfo();
    int? version;
    try {
      version = await _fetchReleaseVersion(release);
    } catch (e) {
      debugPrint('Could not read external catalog version: $e');
    }
    await _downloadReleaseDatabase(
      release.databaseAsset,
      isCancelled: isCancelled,
      onDownloadProgress: onDownloadProgress,
      onExtractionProgress: onExtractionProgress,
      version: version,
    );
  }

  Future<void> _recoverInterruptedInstall() async {
    final destination = databasePath;
    if (!Directory(_catalogBackupPath(destination)).existsSync() &&
        !File('$destination.bak').existsSync()) {
      return;
    }
    await withFileOperationLock(destination, () async {
      await _recoverCatalogFamily(destination);
      // הגיבוי הישן כלל רק את קובץ המסד; ה-sidecars נשארו בנתיב המקורי.
      if (!File(destination).existsSync() &&
          File('$destination.bak').existsSync()) {
        _renameCatalogFile('$destination.bak', destination);
      }
    });
  }

  Future<void> _downloadReleaseDatabase(
    ExternalCatalogReleaseAsset asset, {
    bool Function()? isCancelled,
    void Function(int received, int? total)? onDownloadProgress,
    void Function(double)? onExtractionProgress,
    int? version,
  }) async {
    final dbDir = Directory(path.dirname(databasePath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    final destination = databasePath;
    await withFileOperationLock(
      destination,
      () => _downloadAndInstall(
        destination,
        asset,
        isCancelled,
        onDownloadProgress,
        onExtractionProgress,
        version,
      ),
    );
  }

  Future<void> _downloadAndInstall(
    String databasePath,
    ExternalCatalogReleaseAsset asset,
    bool Function()? isCancelled,
    void Function(int received, int? total)? onDownloadProgress,
    void Function(double)? onExtractionProgress,
    int? version,
  ) async {
    final tempFile = File('$databasePath.download');
    final archiveFile = File('$databasePath.download.zst');
    var replaced = false;
    try {
      _checkCancelled(isCancelled);
      await _recoverCatalogFamily(databasePath);
      await _removeCatalogFamily(tempFile.path);
      // Keep the verified download separate from the staging output so a
      // cancelled extraction or validation can reuse it on the next attempt.
      await _downloadAssetToFile(
        asset,
        archiveFile.path,
        isCancelled,
        onDownloadProgress,
      );
      if (asset.isCompressed) {
        await _extractZst(
          archiveFile.path,
          tempFile.path,
          maxOutputBytes: maxOutputBytes,
          isCancelled: isCancelled,
          onProgress: onExtractionProgress,
        );
      } else {
        await _copyCatalog(archiveFile, tempFile, isCancelled);
      }
      if (await tempFile.length() > maxOutputBytes) {
        throw ZstdOutputLimitExceeded(maxOutputBytes);
      }
      _checkCancelled(isCancelled);
      await _validateCatalog(tempFile.path);
      _checkCancelled(isCancelled);
      if (version != null) _ensureVersionStamped(version, tempFile.path);
      await _prepareStagedCatalog(tempFile.path);
      if (tempFile.lengthSync() > maxOutputBytes) {
        throw ZstdOutputLimitExceeded(maxOutputBytes);
      }
      _checkCancelled(isCancelled);
      _swapCatalogFamily(databasePath, tempFile.path);
      replaced = true;
      try {
        await _cleanCommittedCatalogBackup(
          Directory(_catalogBackupPath(databasePath)),
        );
      } on FileSystemException catch (error) {
        debugPrint('Catalog installed; backup cleanup deferred: $error');
      }
    } on FormatException {
      await _discardDownload(archiveFile.path);
      rethrow;
    } finally {
      try {
        await _removeCatalogFamily(tempFile.path);
      } on FileSystemException catch (error) {
        debugPrint('Could not remove catalog staging files: $error');
      }
      if (replaced) await _discardDownload(archiveFile.path);
    }
  }

  static const _catalogSuffixes = ['', '-wal', '-shm', '-journal'];
  static String _catalogBackupPath(String target) =>
      '$target.catalog-update-backup';

  void _renameCatalogFile(String source, String destination) {
    _beforeFileRename?.call(source, destination);
    File(source).renameSync(destination);
  }

  static Future<void> _removeCatalogFamily(String target) async {
    for (final suffix in _catalogSuffixes) {
      final file = File('$target$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  static Future<void> _prepareStagedCatalog(String target) => Isolate.run(() {
    _closeCatalogGuard(_prepareCatalogForSwap(target));
  });

  static sqlite3.Database? _prepareCatalogForSwap(String target) {
    if (!File(target).existsSync()) return null;
    sqlite3.Database? db;
    try {
      db = sqlite3.sqlite3.open(target, mode: sqlite3.OpenMode.readWrite);
      db.execute('PRAGMA busy_timeout=0');
      db.execute('PRAGMA mmap_size=0');
      db.execute('PRAGMA cache_size=-8192');
      // WAL פעיל מחייב סגירת הקוראים; אין לנתק WAL ממסד שנמצא עדיין בשימוש.
      final journal = db.select('PRAGMA journal_mode=DELETE');
      if (journal.single.values.first.toString().toLowerCase() != 'delete') {
        throw ExternalCatalogDatabaseBusyException(target);
      }
      final locking = db.select('PRAGMA locking_mode=EXCLUSIVE');
      if (locking.single.values.first.toString().toLowerCase() != 'exclusive') {
        throw ExternalCatalogDatabaseBusyException(target);
      }
      db.execute('BEGIN EXCLUSIVE');
      return db;
    } catch (error, stack) {
      db?.close();
      if (error is sqlite3.SqliteException &&
          (error.resultCode == 5 || error.resultCode == 6)) {
        Error.throwWithStackTrace(
          ExternalCatalogDatabaseBusyException(target, error),
          stack,
        );
      }
      rethrow;
    }
  }

  static void _closeCatalogGuard(sqlite3.Database? guard) {
    if (guard == null) return;
    try {
      guard.execute('ROLLBACK');
    } finally {
      guard.close();
    }
  }

  void _swapCatalogFamily(String target, String staged) {
    final backup = Directory(_catalogBackupPath(target));
    final paths = [for (final suffix in _catalogSuffixes) '$target$suffix'];
    var guard = _prepareCatalogForSwap(target);
    var prepared = false;
    try {
      // ב-Windows SQLite אוסר rename עם handle פתוח; handles אחרים יכשילו
      // את ה-rename. ב-POSIX הנעילה נשארת עד שכל פעולות ההחלפה הסתיימו.
      if (Platform.isWindows) {
        _closeCatalogGuard(guard);
        guard = null;
      }
      final existed = [for (final name in paths) File(name).existsSync()];
      backup.createSync();
      final state = File(path.join(backup.path, 'state.json.tmp'));
      state.writeAsStringSync(jsonEncode(existed), flush: true);
      state.renameSync(path.join(backup.path, 'state.json'));
      prepared = true;
      for (var i = 0; i < paths.length; i++) {
        if (existed[i]) {
          _renameCatalogFile(paths[i], path.join(backup.path, '$i'));
        }
      }
      // אין await או נקודת ביטול בתוך ההחלפה; ההחלטה נשמרת לפני ניקוי הגיבוי.
      _renameCatalogFile(staged, target);
      for (var i = 1; i < paths.length; i++) {
        final source = '$staged${_catalogSuffixes[i]}';
        if (File(source).existsSync()) _renameCatalogFile(source, paths[i]);
      }
      final committed = File(path.join(backup.path, 'committed.tmp'));
      committed.writeAsStringSync('1', flush: true);
      _renameCatalogFile(committed.path, path.join(backup.path, 'committed'));
    } catch (error, stack) {
      try {
        if (prepared) {
          _restoreUncommittedCatalogFamily(target);
        } else if (backup.existsSync()) {
          backup.deleteSync(recursive: true);
        }
      } catch (recoveryError) {
        debugPrint('Catalog rollback deferred to next start: $recoveryError');
      }
      if (error is FileSystemException && _isFileInUseError(error)) {
        Error.throwWithStackTrace(
          ExternalCatalogDatabaseBusyException(target, error),
          stack,
        );
      }
      rethrow;
    } finally {
      _closeCatalogGuard(guard);
    }
  }

  Future<void> _recoverCatalogFamily(String target) async {
    final backup = Directory(_catalogBackupPath(target));
    if (!await backup.exists()) return;
    if (await File(path.join(backup.path, 'committed')).exists()) {
      await _cleanCommittedCatalogBackup(backup);
      return;
    }
    _restoreUncommittedCatalogFamily(target);
  }

  void _restoreUncommittedCatalogFamily(String target) {
    final backup = Directory(_catalogBackupPath(target));
    final state = File(path.join(backup.path, 'state.json'));
    if (!state.existsSync() &&
        backup.listSync().every(
          (entry) => path.basename(entry.path) == 'state.json.tmp',
        )) {
      backup.deleteSync(recursive: true);
      return;
    }
    final dynamic existed = jsonDecode(state.readAsStringSync());
    if (existed is! List ||
        existed.length != _catalogSuffixes.length ||
        existed.any((dynamic value) => value is! bool)) {
      throw StateError('Invalid catalog recovery journal: ${backup.path}');
    }
    // הקובץ החדש יורד ראשון והישן חוזר אחרון, כדי שלא ייפתח מסד עם WAL זר.
    if (File(path.join(backup.path, '0')).existsSync()) {
      final live = File(target);
      if (live.existsSync()) live.deleteSync();
    }
    for (var i = _catalogSuffixes.length - 1; i >= 0; i--) {
      final saved = File(path.join(backup.path, '$i'));
      final live = File('$target${_catalogSuffixes[i]}');
      if (saved.existsSync()) {
        if (live.existsSync()) live.deleteSync();
        _renameCatalogFile(saved.path, live.path);
      } else if (existed[i] == false && live.existsSync()) {
        live.deleteSync();
      }
    }
    for (final entry in backup.listSync(followLinks: false)) {
      if (path.basename(entry.path) != 'state.json') {
        entry.deleteSync(recursive: true);
      }
    }
    state.deleteSync();
    backup.deleteSync();
  }

  static Future<void> _cleanCommittedCatalogBackup(Directory backup) async {
    await for (final entry in backup.list(followLinks: false)) {
      if (path.basename(entry.path) != 'committed') {
        await entry.delete(recursive: true);
      }
    }
    await File(path.join(backup.path, 'committed')).delete();
    await backup.delete();
  }

  static void _checkCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) throw PatchDownloadCancelled();
  }

  Future<void> _copyCatalog(
    File source,
    File output,
    bool Function()? isCancelled,
  ) async {
    final target = await output.open(mode: FileMode.writeOnly);
    try {
      var written = 0;
      await for (final chunk in source.openRead()) {
        _checkCancelled(isCancelled);
        if (chunk.length > maxOutputBytes - written) {
          throw ZstdOutputLimitExceeded(maxOutputBytes);
        }
        await target.writeFrom(chunk);
        written += chunk.length;
      }
      await target.flush();
      _checkCancelled(isCancelled);
    } finally {
      await target.close();
    }
  }

  static Future<void> _validateCatalog(String filePath) => Isolate.run(() {
    if (File(filePath).lengthSync() == 0) {
      throw const FormatException('Catalog database is empty');
    }
    final input = File(filePath).openSync();
    try {
      final header = input.readSync(16);
      if (String.fromCharCodes(header) != 'SQLite format 3\u0000') {
        throw const FormatException('Catalog SQLite header is invalid');
      }
    } finally {
      input.closeSync();
    }
    sqlite3.Database? db;
    try {
      db = sqlite3.sqlite3.open(filePath, mode: sqlite3.OpenMode.readOnly);
      db.execute('PRAGMA mmap_size=0');
      db.execute('PRAGMA cache_size=-8192');
      final rows = db.select('PRAGMA quick_check');
      if (rows.isEmpty || rows.any((row) => row.values.first != 'ok')) {
        throw const FormatException('Catalog SQLite quick_check failed');
      }
    } on sqlite3.SqliteException catch (error) {
      if (error.resultCode == 11 || error.resultCode == 26) {
        throw FormatException('Invalid catalog database: $error');
      }
      rethrow;
    } finally {
      db?.close();
    }
  });

  static Future<void> _discardDownload(String filePath) async {
    for (final name in [
      filePath,
      PatchDownloader.resumeSidecarPath(filePath),
    ]) {
      final file = File(name);
      if (await file.exists()) await file.delete();
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
    return _queryBooksInIsolate(
      databasePath,
      tableName,
      mapper,
      idColumn,
      ids?.toList(),
    );
  }

  /// קריאה ומיפוי של כ-160K שורות חוסמים את ה-UI; ה-isolate פותח את המסד לפי
  /// נתיב. סטטית כדי שה-closure לא יתפוס את `this`.
  static Future<List<T>> _queryBooksInIsolate<T extends Book>(
    String dbPath,
    String tableName,
    T Function(Map<String, Object?> row) mapper,
    String? idColumn,
    List<int>? idList,
  ) {
    return Isolate.run(
      () => _queryBooks(dbPath, tableName, mapper, idColumn, idList),
    );
  }

  static List<T> _queryBooks<T extends Book>(
    String dbPath,
    String tableName,
    T Function(Map<String, Object?> row) mapper,
    String? idColumn,
    List<int>? idList,
  ) {
    sqlite3.Database? db;
    try {
      db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);

      if (idColumn != null && idList != null) {
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

      final statement = db.prepare(
        'SELECT * FROM $tableName ORDER BY title COLLATE NOCASE',
      );
      try {
        final cursor = statement.selectCursor();
        final results = <T>[];
        while (cursor.moveNext()) {
          results.add(mapper(cursor.current as Map<String, Object?>));
        }
        return results.toList(growable: false);
      } finally {
        // גם כשל במיפוי חייב לשחרר את ה-cursor ואת נעילת הקריאה שלו.
        statement.close();
      }
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
      throw Exception('לא נמצא קובץ DB של הקטלוגים בשחרור האחרון');
    }

    return ExternalCatalogReleaseInfo(
      tagName: decoded['tag_name']?.toString() ?? '',
      databaseAsset: databaseAsset,
      versionAsset: parseLatestVersionAsset(decoded),
    );
  }

  Future<void> _downloadAssetToFile(
    ExternalCatalogReleaseAsset asset,
    String outputPath,
    bool Function()? isCancelled,
    void Function(int received, int? total)? onProgress,
  ) =>
      PatchDownloader(
        decompress: (_) async => null,
        httpClient: _BoundedCatalogClient(_httpClient, maxDownloadBytes),
        connectTimeout: apiTimeout,
        stallTimeout: downloadTimeout,
      ).downloadToFile(
        url: asset.downloadUrl,
        destPath: outputPath,
        expectedSize: asset.size,
        expectedSha256: asset.sha256,
        resumeToken:
            '${asset.downloadUrl}|${asset.revision}|${asset.size}|${asset.sha256}',
        isCancelled: isCancelled,
        onProgress: onProgress,
      );

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
        'לא נמצא ${DatabaseConstants.externalCatalogVersionFileName} בשחרור ${release.tagName}',
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
          size: (asset['size'] as num?)?.toInt(),
          sha256: _assetDigest(asset['digest']),
          revision: '${asset['id']}|${asset['updated_at']}',
        );
      }

      if (name == DatabaseConstants.externalCatalogDatabaseFileName) {
        fallbackDb = ExternalCatalogReleaseAsset(
          fileName: name,
          downloadUrl: downloadUrl,
          isCompressed: false,
          size: (asset['size'] as num?)?.toInt(),
          sha256: _assetDigest(asset['digest']),
          revision: '${asset['id']}|${asset['updated_at']}',
        );
      }
    }

    return fallbackDb;
  }

  static String? _assetDigest(Object? digest) {
    if (digest is! String || !digest.startsWith('sha256:')) return null;
    final value = digest.substring(7).toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw const FormatException('Invalid catalog SHA-256 metadata');
    }
    return value;
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

  static ExternalLibraryBook _mapOtzarBook(Map<String, Object?> row) {
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

  static ExternalLibraryBook _mapHebrewBook(Map<String, Object?> row) {
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
    this.size,
    this.sha256,
    this.revision = '',
  });

  final String fileName;
  final String downloadUrl;
  final bool isCompressed;
  final int? size;
  final String? sha256;
  final String revision;
}

/// Rejects a chunk before the shared downloader can write beyond the ceiling,
/// including legacy metadata with no size and chunked HTTP responses. Range,
/// ETag, retry, resume and input hashing remain owned by PatchDownloader.
class _BoundedCatalogClient extends http.BaseClient {
  _BoundedCatalogClient(this.delegate, this.maxBytes);
  final http.Client delegate;
  final int maxBytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await delegate.send(request);
    final range = response.headers['content-range'];
    var received = response.statusCode == 206 && range != null
        ? int.tryParse(
                RegExp(r'^bytes (\d+)-').firstMatch(range)?.group(1) ?? '',
              ) ??
              0
        : 0;
    return http.StreamedResponse(
      response.stream.map((chunk) {
        if (chunk.length > maxBytes - received) {
          throw PatchDownloadException(
            'Catalog download exceeds $maxBytes bytes',
          );
        }
        received += chunk.length;
        return chunk;
      }),
      response.statusCode,
      contentLength: response.contentLength,
      headers: response.headers,
      request: response.request,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }
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
