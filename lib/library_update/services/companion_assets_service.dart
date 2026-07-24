import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/search/magic_dictionary_downloader.dart';
import 'package:otzaria/utils/download_sidecar.dart';
import 'package:otzaria/utils/file/tar_zst_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// מוודא שהקבצים הנלווים לספרייה — התלמוד הבבלי, קטלוג otzar-HB ומילון
/// החיפוש — קיימים ומעודכנים, כחלק מזרימת עדכון הספרייה.
///
/// פרטי נכס התלמוד ב-release (ראה [CompanionAssetsService.findLatestTalmudRelease]).
typedef TalmudRelease = ({
  String tag,
  String assetUrl,
  int size,
  String id,
  String updatedAt,
  String? sha256,
});

/// נזרק כשסריקת ה-releases הושלמה בלי למצוא את נכס התלמוד באף אחד מהם —
/// להבדיל מכשל רשת/API, שבו ייתכן שהנכס קיים אך לא ניתן היה לאתרו.
class TalmudAssetNotFoundException implements Exception {
  @override
  String toString() =>
      'לא נמצא ${DatabaseConstants.talmudBavliArchiveFileName} באף release';
}

/// כל פריט הוא best-effort: כשל (אין רשת, קובץ נעול) נרשם ללוג ולא מפיל את
/// העדכון. הקטלוג והמילון משתמשים במנגנוני הגרסה הקיימים שלהם; לתלמוד נוסף
/// כאן סימון גרסה בקובץ בתוך התיקייה — digest של הנכס (או תג ה-release
/// כ-fallback כשאין digest).
class CompanionAssetsService {
  static const String talmudReleaseApi =
      'https://api.github.com/repos/Otzaria/otzaria-library/releases/latest';
  static const String talmudVersionFileName =
      DatabaseConstants.talmudBavliVersionFileName;

  /// נכתב לקובץ הגרסה לפני החילוץ; חילוץ שנקטע משאיר אותו, וכך שכבת הספרייה
  /// מתעלמת מההתקנה החלקית וההרצה הבאה מורידה מחדש.
  static const String talmudInstallingMarker =
      DatabaseConstants.talmudBavliInstallingMarker;
  static const Duration _apiTimeout = Duration(seconds: 15);
  static const Duration _downloadConnectTimeout = Duration(seconds: 20);
  static const Duration _downloadStallTimeout = Duration(seconds: 60);

  final http.Client Function() _clientFactory;
  final ExternalCatalogRepository Function() _catalogRepository;
  final MagicDictionaryDownloader Function() _dictionaryFactory;
  final Future<void> Function(
    String archivePath,
    String outputDir,
    void Function(double progress)? onProgress,
  )
  _extractTarArchive;
  final List<String> Function() _talmudDirsProvider;
  final VoidCallback _invalidateExternalBooksCache;
  final VoidCallback _invalidateLibraryCaches;
  final String _talmudReleaseApiUrl;

  CompanionAssetsService({
    http.Client Function()? clientFactory,
    ExternalCatalogRepository Function()? catalogRepository,
    MagicDictionaryDownloader Function()? dictionaryFactory,
    Future<void> Function(String, String, void Function(double)?)?
    extractTarArchive,
    List<String> Function()? talmudDirsProvider,
    VoidCallback? invalidateExternalBooksCache,
    VoidCallback? invalidateLibraryCaches,
    String? talmudReleaseApiUrl,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _catalogRepository =
           catalogRepository ?? (() => ExternalCatalogRepository.instance),
       _dictionaryFactory = dictionaryFactory ?? MagicDictionaryDownloader.new,
       _extractTarArchive =
           extractTarArchive ??
           ((archive, outputDir, onProgress) =>
               extractTarZstToDir(archive, outputDir, onProgress: onProgress)),
       _talmudDirsProvider =
           talmudDirsProvider ?? DatabaseConstants.getTalmudBavliDirectoryPaths,
       _invalidateExternalBooksCache =
           invalidateExternalBooksCache ??
           (() => DataRepository.instance.invalidateExternalBooksCache()),
       _invalidateLibraryCaches =
           invalidateLibraryCaches ??
           (() => FileSystemData.instance.clearBookCache()),
       _talmudReleaseApiUrl = talmudReleaseApiUrl ?? talmudReleaseApi;

  /// מריץ אימות ועדכון של שלושת הפריטים הנלווים, לפי הסדר: תלמוד, קטלוג,
  /// מילון. מחזיר האם תוכן הספרייה השתנה (תלמוד/קטלוג הותקנו או עודכנו) —
  /// אז נדרש ריענון ספרייה; עדכון מילון אינו משנה את הספרייה.
  Future<bool> verifyAndUpdate({
    void Function(String message)? onStatus,
    void Function(int received, int? total)? onDownloadProgress,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    var libraryChanged = false;

    try {
      if (await _ensureTalmud(onStatus, onDownloadProgress, cancelled)) {
        libraryChanged = true;
      }
    } catch (e) {
      debugPrint('[CompanionAssets] talmud update failed: $e');
    }
    if (cancelled()) return libraryChanged;

    try {
      if (await _ensureCatalog(onStatus)) libraryChanged = true;
    } catch (e) {
      debugPrint('[CompanionAssets] catalog update failed: $e');
    }
    if (cancelled()) return libraryChanged;

    try {
      onStatus?.call('בודק מילון חיפוש');
      final downloader = _dictionaryFactory();
      try {
        // ensureLatest מדווח 1.0 גם כשהמילון כבר מעודכן — לא מציגים "מוריד".
        var announced = false;
        await downloader.ensureLatest(
          onProgress: (progress) {
            if (progress >= 1.0) return;
            if (!announced) {
              announced = true;
              onStatus?.call('מוריד מילון לחיפוש המקורב');
            }
            onDownloadProgress?.call((progress * 10000).round(), 10000);
          },
        );
      } finally {
        downloader.dispose();
      }
    } catch (e) {
      debugPrint('[CompanionAssets] dictionary update failed: $e');
    }
    return libraryChanged;
  }

  // ── תלמוד בבלי ────────────────────────────────────────────────────────

  /// מחזיר `true` רק כשהתלמוד הורד והותקן בפועל.
  Future<bool> _ensureTalmud(
    void Function(String message)? onStatus,
    void Function(int received, int? total)? onDownloadProgress,
    bool Function() cancelled,
  ) async {
    onStatus?.call('בודק את התלמוד הבבלי');
    final dirs = _talmudDirsProvider();
    final existingDir = dirs.where((d) {
      // תיקייה שאינה נגישה לקריאה (הרשאות, אחסון חיצוני) נחשבת כלא קיימת.
      try {
        final dir = Directory(d);
        return dir.existsSync() && dir.listSync().whereType<File>().isNotEmpty;
      } on FileSystemException {
        return false;
      }
    }).firstOrNull;

    final client = _clientFactory();
    try {
      final release = await findLatestTalmudRelease(
        client,
        apiUrl: _talmudReleaseApiUrl,
      );
      if (existingDir != null) {
        final marker = File(p.join(existingDir, talmudVersionFileName));
        final installed = marker.existsSync()
            ? marker.readAsStringSync().trim()
            : '';
        if (installed.isNotEmpty &&
            await _isInstalledUpToDate(client, installed, release)) {
          // תגי הספרייה מתחלפים כמעט יומית גם כשקובץ התלמוד זהה — מרעננים את
          // הסימון ל-digest כדי שהבדיקות הבאות ישוו תוכן ולא תג.
          if (release.sha256 != null && installed != release.sha256) {
            marker.writeAsStringSync(release.sha256!);
          }
          return false;
        }
      }
      if (cancelled()) return false;

      onStatus?.call('מוריד את התלמוד הבבלי');
      final targetDir = existingDir ?? dirs.first;
      final tempPath = p.join(
        Directory.systemTemp.path,
        'otzaria_${DatabaseConstants.talmudBavliArchiveFileName}',
      );
      // כשל/ביטול משאירים את הקובץ החלקי בכוונה — ההרצה הבאה תמשיך דרך Range.
      // הזהות (תג+גודל+id+updated_at) קושרת את השריד לגרסה: העלאה-מחדש תחת אותו
      // תג וגודל משנה את id/updated_at, כך ששריד ישן לא ייחשב עדכני.
      await _downloadToFile(
        client,
        release.assetUrl,
        tempPath,
        '${release.tag}|${release.size}|${release.id}|${release.updatedAt}',
        release.size,
        release.sha256,
        onDownloadProgress,
        cancelled,
      );
      if (cancelled()) return false;

      onStatus?.call('מחלץ את התלמוד הבבלי');
      final dir = Directory(targetDir);
      dir.createSync(recursive: true);
      final markerFile = File(p.join(targetDir, talmudVersionFileName));
      markerFile.writeAsStringSync(talmudInstallingMarker);
      // עדכון מעל התקנה קיימת: מנקים קבצים ישנים שאולי הוסרו ב-release החדש.
      // הסימון-ביניים כבר נכתב, כך שקטיעה בשלב הזה מותירה התקנה חלקית מסומנת.
      for (final entity in dir.listSync()) {
        if (entity is File &&
            p.basename(entity.path) != talmudVersionFileName) {
          entity.deleteSync();
        }
      }
      // הארכיון מכיל את התיקייה 'תלמוד בבלי/' — מחולץ לתיקיית האב.
      // ההתקדמות מכסה את שלב ה-zst; שלב פריסת ה-tar ללא מדידה — עוברים
      // להודעת ספינר כדי שהמד לא ייתקע על 100%.
      var zstDone = false;
      try {
        await _extractTarArchive(tempPath, p.dirname(targetDir), (progress) {
          if (zstDone) return;
          if (progress >= 0.999) {
            zstDone = true;
            onStatus?.call('פורס את קבצי התלמוד');
          } else {
            onDownloadProgress?.call((progress * 10000).round(), 10000);
          }
        });
      } catch (e) {
        // ארכיון פגום שנשאר שלם יחזיר 416 (דילוג הורדה) ולולאה — מוחקים; כשל
        // מערכת-קבצים (קובץ יעד נעול) אינו ארכיון פגום — ה-temp נשמר ל-resume.
        if (e is! FileSystemException) {
          await File(tempPath).delete().catchError((_) => File(tempPath));
          await _deleteTalmudDownloadState(tempPath);
        }
        rethrow;
      }
      // מחיקת הקובץ הזמני לאחר חילוץ מוצלח.
      await File(tempPath).delete().catchError((_) => File(tempPath));
      await _deleteTalmudDownloadState(tempPath);
      File(
        p.join(targetDir, talmudVersionFileName),
      ).writeAsStringSync(release.sha256 ?? release.tag);
      // קיום תיקיית התלמוד ממוטמן ב-DatabaseLibraryProvider — בלי ניקוי,
      // הריענון שאחרי העדכון לא יגלה את התיקייה החדשה עד הפעלה מחדש.
      _invalidateLibraryCaches();
      return true;
    } finally {
      client.close();
    }
  }

  /// האם ההתקנה המסומנת ב-[installed] עדכנית מול [release]: תג או digest
  /// זהים, או שהתג המותקן ישן אך נכס התלמוד בו זהה בתוכנו ל-release האחרון.
  Future<bool> _isInstalledUpToDate(
    http.Client client,
    String installed,
    TalmudRelease release,
  ) async {
    if (installed == release.tag) return true;
    final sha = release.sha256;
    if (sha == null) return false;
    if (installed == sha) return true;
    if (installed == talmudInstallingMarker) return false;
    // תגי הספרייה מתחלפים כמעט יומית עם אותו קובץ תלמוד בדיוק — משווים את
    // ה-digest של התג המותקן כדי לא להוריד ~440MB על שינוי תג בלבד.
    try {
      final json = await _getGithubJson(
        client,
        _talmudReleaseApiUrl.replaceFirst(
          '/releases/latest',
          '/releases/tags/${Uri.encodeComponent(installed)}',
        ),
      );
      return json is Map<String, dynamic> && _talmudAssetSha256(json) == sha;
    } catch (_) {
      return false;
    }
  }

  /// ה-sha256 של נכס התלמוד מתוך JSON של release, או `null` אם אין digest.
  static String? _talmudAssetSha256(Map<String, dynamic> json) {
    final assets = (json['assets'] as List?) ?? const [];
    for (final a in assets) {
      final asset = a as Map<String, dynamic>;
      if (asset['name'] == DatabaseConstants.talmudBavliArchiveFileName) {
        return switch (asset['digest']) {
          final String digest when digest.startsWith('sha256:') =>
            digest.substring('sha256:'.length),
          _ => null,
        };
      }
    }
    return null;
  }

  /// ה-release העדכני ביותר שמכיל את נכס התלמוד: קודם `releases/latest`, ואם
  /// הנכס חסר בו (למשל release של fordb) — נסרקים ה-releases עמוד אחר עמוד.
  /// זורק [TalmudAssetNotFoundException] כשהסריקה הסתיימה בלי למצוא את הנכס.
  static Future<TalmudRelease> findLatestTalmudRelease(
    http.Client client, {
    String apiUrl = talmudReleaseApi,
  }) async {
    final latest = await _getGithubJson(client, apiUrl);
    if (latest is Map<String, dynamic>) {
      final release = _talmudReleaseFrom(latest);
      if (release != null) return release;
    }
    // תקרת העמודים שומרת על מגבלת ה-rate של GitHub; 300 releases רצופים בלי
    // הנכס פירושם שהוא כבר לא מתפרסם.
    for (var page = 1; page <= 3; page++) {
      final list = await _getGithubJson(
        client,
        apiUrl.replaceFirst(
          '/releases/latest',
          '/releases?per_page=100&page=$page',
        ),
      );
      if (list is! List || list.isEmpty) break;
      for (final r in list) {
        if (r is! Map<String, dynamic> || r['prerelease'] == true) continue;
        final release = _talmudReleaseFrom(r);
        if (release != null) return release;
      }
    }
    throw TalmudAssetNotFoundException();
  }

  static Future<dynamic> _getGithubJson(http.Client client, String url) async {
    final response = await client
        .get(
          Uri.parse(url),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'otzaria',
          },
        )
        .timeout(_apiTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('GitHub API החזיר ${response.statusCode}');
    }
    return jsonDecode(response.body);
  }

  /// פרטי נכס התלמוד מתוך JSON של release, או `null` כשהתג/הנכס חסרים.
  static TalmudRelease? _talmudReleaseFrom(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?)?.trim();
    if (tag == null || tag.isEmpty) return null;
    final assets = (json['assets'] as List?) ?? const [];
    for (final a in assets) {
      final asset = a as Map<String, dynamic>;
      if (asset['name'] == DatabaseConstants.talmudBavliArchiveFileName) {
        return (
          tag: tag,
          assetUrl: asset['browser_download_url'] as String,
          size: (asset['size'] as num?)?.toInt() ?? 0,
          id: asset['id']?.toString() ?? '',
          updatedAt: asset['updated_at']?.toString() ?? '',
          sha256: _talmudAssetSha256(json),
        );
      }
    }
    return null;
  }

  /// מוריד את [url] דרך מנגנון ה-resume המאומת של חבילת העדכון. [identity]
  /// קושר את השריד ל-release, ו-ETag חזק שנשמר ב-sidecar קושר את הבייטים לייצוג
  /// השרת דרך If-Range. 206/416, אורך, digest, timeout וביטול מאומתים בחבילה.
  Future<void> _downloadToFile(
    http.Client client,
    String url,
    String destPath,
    String identity,
    int expectedSize,
    String? expectedSha256,
    void Function(int received, int? total)? onProgress,
    bool Function() cancelled,
  ) async {
    // מסיר sidecar מהפורמט המקומי הישן. PatchDownloader משתמש ב-.resume
    // ושומר בו גם ETag חזק, כך שכל המשך נשלח עם If-Range ונמנע frankenfile.
    await deleteDownloadSidecar(destPath);
    final downloader = PatchDownloader(
      decompress: (_) async => null,
      httpClient: client,
      connectTimeout: _downloadConnectTimeout,
      stallTimeout: _downloadStallTimeout,
    );
    await downloader.downloadToFile(
      url: url,
      destPath: destPath,
      expectedSize: expectedSize > 0 ? expectedSize : null,
      expectedSha256: expectedSha256,
      resumeToken: identity,
      onProgress: onProgress,
      isCancelled: cancelled,
    );
  }

  Future<void> _deleteTalmudDownloadState(String destPath) async {
    // משאירים את ה-sidecar אם מחיקת הארכיון נכשלה, כדי שהניסיון הבא יוכל
    // לזהות/לאמת את השריד ולא יאבד את נקודת החידוש.
    if (await File(destPath).exists()) return;
    await deleteDownloadSidecar(destPath); // פורמט .meta הישן
    final resume = File(PatchDownloader.resumeSidecarPath(destPath));
    await resume.delete().catchError((_) => resume);
  }

  // ── קטלוג otzar-HB ────────────────────────────────────────────────────

  /// מחזיר `true` כשהקטלוג הורד או עודכן בפועל.
  Future<bool> _ensureCatalog(void Function(String message)? onStatus) async {
    final repository = _catalogRepository();
    if (await repository.databaseExists()) {
      onStatus?.call('בודק עדכון קטלוגים');
      final updated = await repository.updateDatabaseIfNeeded();
      if (updated) _invalidateExternalBooksCache();
      return updated;
    }
    onStatus?.call('מוריד את הקטלוגים');
    await repository.downloadLatestDatabase();
    _invalidateExternalBooksCache();
    return true;
  }
}
