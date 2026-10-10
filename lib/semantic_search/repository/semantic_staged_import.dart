import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:otzaria/library_update/services/companion_assets_service.dart';
import 'package:otzaria/library_update/services/github_rate_limit.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_import_layout.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_release.dart';
import 'package:otzaria/semantic_search/repository/semantic_release_locator.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart'
    show SemanticFileDownloader;
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show PatchDownloadCancelled;

/// נתוני החיפוש הסמנטי שמסייע ההורדה הכין ב-`<root>/semantic-import`.
///
/// אין כאן התקנה עצמאית: הקבצים משמשים רק בתוך עבודת ההורדה של המאגר, שכבר
/// מחייבת הסכמה, ומחליפים הורדה של קובץ שזהה לו בשם, בגודל וב-SHA-256.
class SemanticStagedImport {
  SemanticStagedImport(this._paths);

  final Future<SemanticPaths> Function() _paths;
  final _verified =
      <String, ({int size, String sha, DateTime modified, DateTime changed})>{};

  /// אימותים משותפים לתכנון המקום ולהעברה, למשך העבודה הנוכחית בלבד.
  void clearVerification() => _verified.clear();

  static void _checkCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) throw const PatchDownloadCancelled();
  }

  /// תיקיית הנתונים המוכנים של [paths].
  static String directoryOf(SemanticPaths paths) =>
      p.join(paths.root, kSemanticImportFolderName);

  /// האם יש בכלל נתונים מוכנים.
  Future<bool> hasData() async {
    final dir = Directory(directoryOf(await _paths()));
    try {
      return await dir.exists() &&
          await dir.list(recursive: true).any((entity) => entity is File);
    } on FileSystemException {
      return false;
    }
  }

  /// [download] שמעדיף קובץ מוכן תואם; בלעדיו, במצב לא מקוון — [SemanticFailureKind.offline].
  ///
  /// [onChecking] מסמן את תחילת בדיקת ה-hash של קובץ מוכן ואת סופה.
  SemanticFileDownloader wrap(
    SemanticFileDownloader download, {
    required bool Function() isOffline,
    void Function(bool checking)? onChecking,
  }) =>
      ({
        required String url,
        required String destPath,
        required String resumeIdentity,
        int? expectedSize,
        String? expectedSha256,
        void Function(int received, int? total)? onProgress,
        bool Function()? isCancelled,
      }) async {
        _checkCancelled(isCancelled);
        if (expectedSize != null &&
            expectedSha256 != null &&
            await _adopt(
              url,
              destPath,
              expectedSize,
              expectedSha256,
              onChecking,
              isCancelled,
            )) {
          onProgress?.call(expectedSize, expectedSize);
          return;
        }
        _checkCancelled(isCancelled);
        if (isOffline()) {
          throw const SemanticFailure(SemanticFailureKind.offline);
        }
        await download(
          url: url,
          destPath: destPath,
          resumeIdentity: resumeIdentity,
          expectedSize: expectedSize,
          expectedSha256: expectedSha256,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
      };

  /// ה-release של [libraryVersion]: מהרשת, ובהיעדר רשת — מהנתונים המוכנים.
  Future<SemanticVectorsRelease?> locate(
    int libraryVersion, {
    required bool offline,
    required Future<SemanticVectorsRelease?> Function() online,
  }) async {
    if (offline) {
      final staged = await stagedRelease(libraryVersion);
      if (staged == null) {
        throw const SemanticFailure(SemanticFailureKind.offline);
      }
      return staged;
    }
    try {
      return await online() ?? await stagedRelease(libraryVersion);
    } catch (error) {
      if (!_isUnreachable(error)) rethrow;
      final staged = await stagedRelease(libraryVersion);
      if (staged == null) rethrow;
      debugPrint(
        '[SemanticSearch] release lookup failed ($error); '
        'using the staged vectors',
      );
      return staged;
    }
  }

  /// סט הוקטורים המוכן לגרסת הספרייה [libraryVersion], או `null`.
  Future<SemanticVectorsRelease?> stagedRelease(int libraryVersion) async {
    final dir = Directory(
      p.join(directoryOf(await _paths()), kSemanticImportVectorsFolderName),
    );
    if (!await dir.exists()) return null;
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (entity is! File ||
          !name.startsWith(kSemanticVectorsManifestPrefix) ||
          !name.endsWith(kSemanticVectorsManifestSuffix)) {
        continue;
      }
      try {
        final release = parseStagedManifest(
          await entity.readAsBytes(),
          libraryVersion,
        );
        if (release != null) return release;
      } on FormatException catch (error) {
        debugPrint('[SemanticSearch] staged manifest $name ignored: $error');
      }
    }
    return null;
  }

  /// מפענח מניפסט וקטורים מוכן. `null` כשהוא של גרסת ספרייה אחרת.
  ///
  /// ה-digest שנמסר למנוע הוא ה-SHA-256 של הבתים עצמם: המסייע אימת אותם מול
  /// מניפסט ה-release, וה-CI אימת אותו מול ה-digest שפורסם בהערות.
  static SemanticVectorsRelease? parseStagedManifest(
    List<int> bytes,
    int libraryVersion,
  ) {
    final text = utf8.decode(bytes);
    final manifest = jsonDecode(text);
    if (manifest is! Map<String, dynamic>) {
      throw const FormatException('manifest is not an object');
    }
    final tag = manifest['libraryReleaseTag'];
    if (manifest['kind'] != 'base' ||
        manifest['toLibraryVersion'] != libraryVersion ||
        tag is! String ||
        SemanticVectorsReleaseLocator.versionOfTag(tag) != libraryVersion) {
      return null;
    }
    final files = manifest['files'];
    final segmentSize = (manifest['segment'] as Map?)?['size'];
    if (files is! List || files.isEmpty || segmentSize is! int) {
      throw const FormatException('manifest files/segment missing');
    }
    return SemanticVectorsRelease(
      libraryTag: tag,
      releaseTag: 'vectors-$tag',
      toLibraryVersion: libraryVersion,
      kind: 'base',
      manifestJson: text,
      publishedManifestSha256: sha256.convert(bytes).toString(),
      files: [
        for (final entry in files)
          if (entry case {
            'file': final String name,
            'size': final int size,
            'sha256': final String sha,
          } when _isPlainName(name))
            SemanticVectorsFile(
              name: name,
              downloadUrl: semanticVectorsAssetUrl(tag, name),
              size: size,
              sha256: sha.toLowerCase(),
              assetId: '',
            )
          else
            throw const FormatException('manifest file entry'),
      ],
      segmentUncompressedSize: segmentSize,
    );
  }

  /// קובץ מוכן שתואם בגודל וב-SHA; האימות חוזר אם מטא־נתוני הקובץ השתנו.
  Future<File?> verifiedStagedFile(
    String name,
    int size,
    String sha, {
    void Function(bool checking)? onChecking,
    bool Function()? isCancelled,
  }) async {
    _checkCancelled(isCancelled);
    final staged = await stagedFile(name);
    if (staged == null) return null;
    final path = staged.path;
    try {
      final stat = await staged.stat();
      _checkCancelled(isCancelled);
      final signature = (
        size: size,
        sha: sha.toLowerCase(),
        modified: stat.modified,
        changed: stat.changed,
      );
      if (stat.size != size) return null;
      if (_verified[path] != signature) {
        onChecking?.call(true);
        final bool matches;
        try {
          _checkCancelled(isCancelled);
          matches = await Isolate.run(() => _fileMatches(path, size, sha));
        } finally {
          onChecking?.call(false);
        }
        _checkCancelled(isCancelled);
        if (!matches) return null;
        final after = await staged.stat();
        if (after.size != stat.size ||
            after.modified != stat.modified ||
            after.changed != stat.changed) {
          return null;
        }
        _verified[path] = signature;
      }
      _checkCancelled(isCancelled);
      return staged;
    } on FileSystemException {
      return null;
    }
  }

  /// מעביר קובץ מוכן תואם ל-[destPath]. קובץ שאינו תואם נשאר במקומו.
  Future<bool> _adopt(
    String url,
    String destPath,
    int size,
    String sha,
    void Function(bool checking)? onChecking,
    bool Function()? isCancelled,
  ) async {
    final staged = await verifiedStagedFile(
      Uri.tryParse(url)?.pathSegments.lastOrNull ?? '',
      size,
      sha,
      onChecking: onChecking,
      isCancelled: isCancelled,
    );
    if (staged == null) return false;
    _verified.remove(staged.path);
    _checkCancelled(isCancelled);
    await CompanionAssetsService.discardDownload(destPath);
    _checkCancelled(isCancelled);
    await Directory(p.dirname(destPath)).create(recursive: true);
    _checkCancelled(isCancelled);
    try {
      await staged.rename(destPath);
    } on FileSystemException {
      // בכונן אחר המקור נשמר עד שההעתקה הושלמה ללא ביטול.
      _checkCancelled(isCancelled);
      await staged.copy(destPath);
      _checkCancelled(isCancelled);
      await staged.delete();
      return true;
    }
    if (isCancelled?.call() ?? false) {
      await File(destPath).rename(staged.path);
      throw const PatchDownloadCancelled();
    }
    return true;
  }

  /// הקובץ המוכן בשם [name] (במודל או בוקטורים), או `null`.
  Future<File?> stagedFile(String name) async {
    if (!_isPlainName(name)) return null;
    final root = directoryOf(await _paths());
    for (final folder in const [
      kSemanticModelFolderName,
      kSemanticImportVectorsFolderName,
    ]) {
      final candidate = File(p.join(root, folder, name));
      if (await candidate.exists()) return candidate;
    }
    return null;
  }

  static bool _isPlainName(String name) =>
      name.isNotEmpty &&
      name != '.' &&
      name != '..' &&
      !name.contains('/') &&
      !name.contains(r'\');

  static bool _isUnreachable(Object error) =>
      error is IOException ||
      error is http.ClientException ||
      error is TimeoutException ||
      error is GithubRateLimitException;
}

Future<bool> _fileMatches(String path, int size, String sha) async {
  final file = File(path);
  if (await file.length() != size) return false;
  return (await sha256.bind(file.openRead()).first).toString() ==
      sha.toLowerCase();
}
