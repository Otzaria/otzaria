import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/search/magic_dictionary_downloader.dart';
import 'package:otzaria/tools/biographies/data/biographies_downloader.dart';
import 'package:otzaria/utils/download_sidecar.dart';
import 'package:otzaria/utils/file/tar_zst_extractor.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
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

enum CompanionAssetPhase { checking, downloading, extracting, applying }

typedef CompanionTarExtractor =
    Future<void> Function(
      String archivePath,
      String outputDir,
      void Function(double progress)? onProgress, {
      required int maxOutputBytes,
      bool Function()? isCancelled,
    });

typedef CompanionAssetStatusCallback =
    void Function(String message, CompanionAssetPhase phase);

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
  final BiographiesDownloader Function() _biographiesFactory;
  final CompanionTarExtractor _extractTarArchive;
  final int maxExtractedBytes;
  final List<String> Function() _talmudDirsProvider;
  final VoidCallback _invalidateExternalBooksCache;
  final VoidCallback _invalidateLibraryCaches;
  final String _talmudReleaseApiUrl;
  final void Function(String? libraryTag)? _scheduleSemanticVectorsUpdate;

  CompanionAssetsService({
    http.Client Function()? clientFactory,
    ExternalCatalogRepository Function()? catalogRepository,
    MagicDictionaryDownloader Function()? dictionaryFactory,
    BiographiesDownloader Function()? biographiesFactory,
    CompanionTarExtractor? extractTarArchive,
    this.maxExtractedBytes = kDefaultMaxExtractedBytes,
    List<String> Function()? talmudDirsProvider,
    VoidCallback? invalidateExternalBooksCache,
    VoidCallback? invalidateLibraryCaches,
    String? talmudReleaseApiUrl,
    this._scheduleSemanticVectorsUpdate,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _catalogRepository =
           catalogRepository ?? (() => ExternalCatalogRepository.instance),
       _dictionaryFactory =
           dictionaryFactory ??
           (() => MagicDictionaryDownloader(
             aroundReplace:
                 TantivyDataProvider.instance.replaceMagicDictionaryDetached,
           )),
       _biographiesFactory = biographiesFactory ?? BiographiesDownloader.new,
       _extractTarArchive =
           extractTarArchive ??
           ((
             archive,
             outputDir,
             onProgress, {
             required maxOutputBytes,
             isCancelled,
           }) => extractTarZstToDir(
             archive,
             outputDir,
             onProgress: onProgress,
             maxOutputBytes: maxOutputBytes,
             isCancelled: isCancelled,
           )),
       _talmudDirsProvider =
           talmudDirsProvider ?? DatabaseConstants.getTalmudBavliDirectoryPaths,
       _invalidateExternalBooksCache =
           invalidateExternalBooksCache ??
           (() => DataRepository.instance.invalidateExternalBooksCache()),
       _invalidateLibraryCaches =
           invalidateLibraryCaches ??
           (() => FileSystemData.instance.clearBookCache()),
       _talmudReleaseApiUrl = talmudReleaseApiUrl ?? talmudReleaseApi;

  /// מריץ אימות ועדכון של הפריטים הנלווים, לפי הסדר: תלמוד, קטלוג, מילון,
  /// ביוגרפיות. מחזיר האם תוכן הספרייה השתנה (תלמוד/קטלוג הותקנו או עודכנו)
  /// — אז נדרש ריענון ספרייה; עדכון מילון וביוגרפיות אינו משנה את הספרייה.
  Future<bool> verifyAndUpdate({
    CompanionAssetStatusCallback? onStatus,
    void Function(int received, int? total)? onDownloadProgress,
    bool Function()? isCancelled,
    String? libraryReleaseTag,
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
      if (await _ensureCatalog(onStatus, onDownloadProgress, cancelled)) {
        libraryChanged = true;
      }
    } catch (e) {
      debugPrint('[CompanionAssets] catalog update failed: $e');
    }
    if (cancelled()) return libraryChanged;

    try {
      onStatus?.call('בודק מילון חיפוש', CompanionAssetPhase.checking);
      final downloader = _dictionaryFactory();
      try {
        // ensureLatest מדווח 1.0 גם כשהמילון כבר מעודכן — לא מציגים "מוריד".
        var announced = false;
        await downloader.ensureLatest(
          onProgress: (progress) {
            if (progress >= 1.0) return;
            if (!announced) {
              announced = true;
              onStatus?.call(
                'מוריד מילון לחיפוש המקורב',
                CompanionAssetPhase.downloading,
              );
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
    if (cancelled()) return libraryChanged;

    try {
      onStatus?.call('בודק נתוני ביוגרפיות', CompanionAssetPhase.checking);
      final biographies = _biographiesFactory();
      try {
        await biographies.ensureLatest();
      } finally {
        biographies.dispose();
      }
    } catch (e) {
      debugPrint('[CompanionAssets] biographies update failed: $e');
    }

    // וקטורי החיפוש הסמנטי (~1.6GB) יורדים ברקע, מחוץ למד ההתקדמות של העדכון.
    try {
      _scheduleSemanticVectorsUpdate?.call(libraryReleaseTag);
    } catch (e) {
      debugPrint('[CompanionAssets] semantic vectors schedule failed: $e');
    }
    return libraryChanged;
  }

  /// מוריד ל-[destPath] עם resume לפי [resumeIdentity], אימות SHA-256 וגודל,
  /// התקדמות וביטול; זורק את חריגות `PatchDownloader` בכשל.
  Future<void> downloadVerifiedFile({
    required String url,
    required String destPath,
    required String resumeIdentity,
    int? expectedSize,
    String? expectedSha256,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final client = _clientFactory();
    try {
      await _downloadToFile(
        client,
        url,
        destPath,
        resumeIdentity,
        expectedSize ?? 0,
        expectedSha256,
        onProgress,
        isCancelled ?? () => false,
      );
    } finally {
      client.close();
    }
  }

  /// מוחק קובץ שהורד ב-[downloadVerifiedFile] יחד עם קובצי הצד של ה-resume.
  static Future<void> discardDownload(String destPath) async {
    final file = File(destPath);
    await file.delete().catchError((_) => file);
    await deleteDownloadSidecar(destPath);
    final resume = File(PatchDownloader.resumeSidecarPath(destPath));
    await resume.delete().catchError((_) => resume);
  }

  // ── תלמוד בבלי ────────────────────────────────────────────────────────

  /// מחזיר `true` רק כשהתלמוד הורד והותקן בפועל.
  Future<bool> _ensureTalmud(
    CompanionAssetStatusCallback? onStatus,
    void Function(int received, int? total)? onDownloadProgress,
    bool Function() cancelled,
  ) => withFileOperationLock(
    p.join(Directory.systemTemp.path, 'otzaria_talmud-update'),
    () => _ensureTalmudLocked(onStatus, onDownloadProgress, cancelled),
  );

  Future<bool> _ensureTalmudLocked(
    CompanionAssetStatusCallback? onStatus,
    void Function(int received, int? total)? onDownloadProgress,
    bool Function() cancelled,
  ) async {
    if (maxExtractedBytes <= 0) {
      throw ArgumentError.value(maxExtractedBytes, 'maxExtractedBytes');
    }
    if (cancelled()) return false;
    onStatus?.call('בודק את התלמוד הבבלי', CompanionAssetPhase.checking);
    final dirs = _talmudDirsProvider();
    // רק IO אסינכרוני על תיקיית התלמוד: מאות קבצים מול אנטי-וירוס או דיסק
    // איטי חוסמים את ה-UI לשניות ארוכות.
    String? existingDir;
    for (final d in dirs) {
      // תיקייה שאינה נגישה לקריאה (הרשאות, אחסון חיצוני) נחשבת כלא קיימת.
      try {
        await _recoverDirectory(d);
        final dir = Directory(d);
        if (await dir.exists() && await dir.list().any((e) => e is File)) {
          existingDir = d;
          break;
        }
      } on FileSystemException {
        continue;
      }
    }

    final client = _clientFactory();
    try {
      final release = await findLatestTalmudRelease(
        client,
        apiUrl: _talmudReleaseApiUrl,
      );
      if (existingDir != null) {
        final marker = File(p.join(existingDir, talmudVersionFileName));
        final installed = await marker.exists()
            ? (await marker.readAsString()).trim()
            : '';
        if (installed.isNotEmpty &&
            await _isInstalledUpToDate(client, installed, release)) {
          // תגי הספרייה מתחלפים כמעט יומית גם כשקובץ התלמוד זהה — מרעננים את
          // הסימון ל-digest כדי שהבדיקות הבאות ישוו תוכן ולא תג.
          if (release.sha256 != null && installed != release.sha256) {
            await marker.writeAsString(release.sha256!);
          }
          return false;
        }
      }
      if (cancelled()) return false;

      onStatus?.call('מוריד את התלמוד הבבלי', CompanionAssetPhase.downloading);
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

      onStatus?.call('מחלץ את התלמוד הבבלי', CompanionAssetPhase.extracting);
      final parent = Directory(p.dirname(targetDir));
      await parent.create(recursive: true);
      final stage = await parent.createTemp('.otzaria-talmud-');
      // הארכיון מכיל את התיקייה 'תלמוד בבלי/' — מחולץ לתיקיית האב.
      // ההתקדמות מכסה את שלב ה-zst; שלב פריסת ה-tar ללא מדידה — עוברים
      // להודעת ספינר כדי שהמד לא ייתקע על 100%.
      var zstDone = false;
      try {
        await _extractTarArchive(
          tempPath,
          stage.path,
          (progress) {
            if (zstDone) return;
            if (progress >= 0.999) {
              zstDone = true;
              onStatus?.call(
                'פורס את קבצי התלמוד',
                CompanionAssetPhase.extracting,
              );
            } else {
              onDownloadProgress?.call((progress * 10000).round(), 10000);
            }
          },
          maxOutputBytes: maxExtractedBytes,
          isCancelled: cancelled,
        );
        if (cancelled()) throw PatchDownloadCancelled();
        final extracted = Directory(
          p.join(stage.path, DatabaseConstants.talmudBavliFolderName),
        );
        if (!await extracted.exists()) {
          throw const FormatException(
            'Talmud archive is missing its directory',
          );
        }
        await _preserveSubdirectories(
          Directory(targetDir),
          extracted,
          cancelled,
          onDownloadProgress,
        );
        await File(
          p.join(extracted.path, talmudVersionFileName),
        ).writeAsString(release.sha256 ?? release.tag, flush: true);
        if (cancelled()) throw PatchDownloadCancelled();
        onStatus?.call('מתקין את התלמוד הבבלי', CompanionAssetPhase.applying);
        if (cancelled()) throw PatchDownloadCancelled();
        await _replaceDirectory(extracted, Directory(targetDir));
      } catch (e) {
        // ארכיון פגום שנשאר שלם יחזיר 416 (דילוג הורדה) ולולאה — מוחקים; כשל
        // מערכת-קבצים (קובץ יעד נעול) אינו ארכיון פגום — ה-temp נשמר ל-resume.
        if (e is FormatException) {
          await deleteDownloadWithSidecars(tempPath);
        }
        rethrow;
      } finally {
        await _cleanupDirectory(stage);
      }
      // מחיקת הקובץ הזמני לאחר חילוץ מוצלח.
      await deleteDownloadWithSidecars(tempPath);
      // קיום תיקיית התלמוד ממוטמן ב-DatabaseLibraryProvider — בלי ניקוי,
      // הריענון שאחרי העדכון לא יגלה את התיקייה החדשה עד הפעלה מחדש.
      _invalidateLibraryCaches();
      return true;
    } finally {
      client.close();
    }
  }

  static Future<void> _recoverDirectory(String path) async {
    final target = Directory(path);
    final backup = Directory('$path.update-old');
    if (!await target.exists() && await backup.exists()) {
      await backup.rename(path);
    }
  }

  Future<void> _preserveSubdirectories(
    Directory previous,
    Directory staged,
    bool Function() cancelled,
    void Function(int received, int? total)? onProgress,
  ) async {
    void checkCancelled() {
      if (cancelled()) throw const PatchDownloadCancelled();
    }

    checkCancelled();
    if (!await previous.exists()) return;
    var stagedBytes = 0;
    await for (final entry in staged.list(
      recursive: true,
      followLinks: false,
    )) {
      checkCancelled();
      if (entry is File) {
        final size = await entry.length();
        if (size > maxExtractedBytes - stagedBytes) {
          throw ZstdOutputLimitExceeded(maxExtractedBytes);
        }
        stagedBytes += size;
      }
    }
    var copied = 0;
    Future<void> preserve(FileSystemEntity source, String destination) async {
      checkCancelled();
      final destinationType = await FileSystemEntity.type(
        destination,
        followLinks: false,
      );
      if (source is Directory) {
        if (destinationType != FileSystemEntityType.notFound &&
            destinationType != FileSystemEntityType.directory) {
          throw StateError('קובץ בארכיון מתנגש בתיקייה קיימת');
        }
        await Directory(destination).create(recursive: true);
        await for (final child in source.list(followLinks: false)) {
          await preserve(child, p.join(destination, p.basename(child.path)));
        }
      } else if (destinationType == FileSystemEntityType.notFound) {
        if (source is File) {
          final expected = await source.length();
          if (expected > maxExtractedBytes - stagedBytes) {
            throw ZstdOutputLimitExceeded(maxExtractedBytes);
          }
          checkCancelled();
          final output = await File(destination).open(mode: FileMode.writeOnly);
          try {
            var read = 0;
            await for (final bytes in source.openRead()) {
              checkCancelled();
              if (bytes.length > expected - read) {
                throw StateError('קובץ קיים השתנה בזמן ההעתקה');
              }
              if (bytes.length > maxExtractedBytes - stagedBytes) {
                throw ZstdOutputLimitExceeded(maxExtractedBytes);
              }
              await output.writeFrom(bytes);
              read += bytes.length;
              stagedBytes += bytes.length;
              copied += bytes.length;
              onProgress?.call(copied, null);
              checkCancelled();
            }
            if (read != expected) {
              throw StateError('קובץ קיים השתנה בזמן ההעתקה');
            }
            await output.flush();
            checkCancelled();
          } finally {
            await output.close();
          }
        } else if (source is Link) {
          await Link(destination).create(await source.target());
        }
      }
      checkCancelled();
    }

    // Direct files belong to the release; subdirectories may hold user content.
    // Copy missing entries after extraction, so the archive never follows old links.
    await for (final entry in previous.list(followLinks: false)) {
      checkCancelled();
      if (entry is Directory || entry is Link) {
        await preserve(entry, p.join(staged.path, p.basename(entry.path)));
      }
    }
  }

  static Future<void> _cleanupDirectory(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException catch (error) {
      debugPrint('[CompanionAssets] directory cleanup failed: $error');
    }
  }

  static Future<void> _replaceDirectory(
    Directory staged,
    Directory target,
  ) async {
    final backup = Directory('${target.path}.update-old');
    var moved = false;
    var installed = false;
    await _recoverDirectory(target.path);
    if (await backup.exists()) await backup.delete(recursive: true);
    try {
      if (await target.exists()) {
        await target.rename(backup.path);
        moved = true;
      }
      await staged.rename(target.path);
      installed = true;
    } catch (_) {
      if (moved && !await target.exists()) {
        try {
          await backup.rename(target.path);
          moved = false;
        } catch (_) {
          // Leave the backup intact if rollback cannot complete.
        }
      }
      rethrow;
    } finally {
      if (installed && moved) await _cleanupDirectory(backup);
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

  // ── קטלוג otzar-HB ────────────────────────────────────────────────────

  /// מחזיר `true` כשהקטלוג הורד או עודכן בפועל.
  Future<bool> _ensureCatalog(
    CompanionAssetStatusCallback? onStatus,
    void Function(int received, int? total)? onDownloadProgress,
    bool Function() cancelled,
  ) async {
    final repository = _catalogRepository();
    void extractionProgress(double progress) {
      onStatus?.call('מחלץ את הקטלוגים', CompanionAssetPhase.extracting);
      onDownloadProgress?.call((progress * 10000).round(), 10000);
    }

    if (await repository.databaseExists()) {
      onStatus?.call('בודק עדכון קטלוגים', CompanionAssetPhase.checking);
      final updated = await repository.updateDatabaseIfNeeded(
        isCancelled: cancelled,
        onDownloadProgress: onDownloadProgress,
        onExtractionProgress: extractionProgress,
        onUpdateAvailable: () => onStatus?.call(
          'מוריד את הקטלוגים',
          CompanionAssetPhase.downloading,
        ),
      );
      if (updated) _invalidateExternalBooksCache();
      return updated;
    }
    onStatus?.call('מוריד את הקטלוגים', CompanionAssetPhase.downloading);
    await repository.downloadLatestDatabase(
      isCancelled: cancelled,
      onDownloadProgress: onDownloadProgress,
      onExtractionProgress: extractionProgress,
    );
    _invalidateExternalBooksCache();
    return true;
  }
}
