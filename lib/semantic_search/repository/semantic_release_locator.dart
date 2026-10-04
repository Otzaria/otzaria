import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/library_update/services/github_rate_limit.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_release.dart';

/// מאתר ב-SeforimLibrary את release הוקטורים של גרסת ספרייה.
///
/// ה-release נקרא `vectors-<תג הספרייה>` ואינו מסומן latest, ולכן הוא נמצא
/// לפי התג בלבד. GitHub שחסם מכסה זורק [GithubRateLimitException].
class SemanticVectorsReleaseLocator {
  static const String defaultApiBase =
      'https://api.github.com/repos/Otzaria/SeforimLibrary';
  static const Duration _timeout = Duration(seconds: 15);

  /// כמה עמודי releases לסרוק בחיפוש תג הספרייה (100 בעמוד).
  static const int _maxPages = 3;

  static final RegExp _libraryTag = RegExp(r'^v(\d+)-');
  static final RegExp _sha256 = RegExp(r'\b[0-9a-f]{64}\b');

  final http.Client Function() _clientFactory;
  final String _apiBase;

  SemanticVectorsReleaseLocator({
    http.Client Function()? clientFactory,
    this._apiBase = defaultApiBase,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  /// ה-release של גרסת הספרייה [libraryVersion], או `null` כשהוא עוד לא
  /// פורסם. [libraryTag] חוסך את סריקת ה-releases כשהתג ידוע.
  ///
  /// זורק [SemanticFailure] על release פגום או מניפסט שאינו תואם ל-digest
  /// שפורסם, ו-[http.ClientException] על כשל רשת.
  Future<SemanticVectorsRelease?> findForLibraryVersion(
    int libraryVersion, {
    String? libraryTag,
  }) async {
    final client = GithubRateLimitAwareClient(_clientFactory());
    try {
      final hint =
          libraryTag != null && versionOfTag(libraryTag) == libraryVersion
          ? libraryTag
          : null;
      final tag = hint ?? await _findLibraryTag(client, libraryVersion);
      if (tag == null) return null;
      final releaseTag = 'vectors-$tag';
      final release = await _getJson(
        client,
        '$_apiBase/releases/tags/${Uri.encodeComponent(releaseTag)}',
      );
      if (release == null) return null;
      if (release is! Map<String, dynamic>) {
        throw const SemanticFailure(
          SemanticFailureKind.releaseMalformed,
          'release JSON is not an object',
        );
      }
      return await _parseRelease(
        client,
        release,
        tag,
        releaseTag,
        libraryVersion,
      );
    } finally {
      client.close();
    }
  }

  /// גרסת הספרייה של תג כמו `v30-20260930165019`, או `null`.
  static int? versionOfTag(String tag) =>
      int.tryParse(_libraryTag.firstMatch(tag)?.group(1) ?? '');

  /// תג הספרייה של [version] מתוך רשימת releases (החדש ראשון), או `null`.
  static String? libraryTagFor(List<dynamic> releases, int version) {
    for (final release in releases) {
      if (release is! Map<String, dynamic>) continue;
      final tag = release['tag_name'];
      if (tag is! String) continue;
      final match = _libraryTag.firstMatch(tag);
      if (match != null && int.parse(match.group(1)!) == version) return tag;
    }
    return null;
  }

  /// ה-SHA-256 של המניפסט מהערות ה-release: הערך שאחרי שם המניפסט, או הערך
  /// היחיד בהערות; `null` כשאין, או כשיש כמה בלי שם שמכריע ביניהם.
  static String? parsePublishedManifestSha256(String? body, String manifest) {
    if (body == null) return null;
    final text = body.toLowerCase();
    final at = text.indexOf(manifest.toLowerCase());
    if (at >= 0) {
      final after = _sha256.firstMatch(text.substring(at + manifest.length));
      if (after != null) return after.group(0);
    }
    final all = _sha256.allMatches(text).map((m) => m.group(0)).toSet();
    return all.length == 1 ? all.single : null;
  }

  Future<String?> _findLibraryTag(http.Client client, int version) async {
    for (var page = 1; page <= _maxPages; page++) {
      final list = await _getJson(
        client,
        '$_apiBase/releases?per_page=100&page=$page',
      );
      if (list is! List || list.isEmpty) return null;
      final tag = libraryTagFor(list, version);
      if (tag != null) return tag;
    }
    return null;
  }

  Future<SemanticVectorsRelease> _parseRelease(
    http.Client client,
    Map<String, dynamic> release,
    String libraryTag,
    String releaseTag,
    int libraryVersion,
  ) async {
    final assets = <String, Map<String, dynamic>>{
      for (final asset in (release['assets'] as List?) ?? const [])
        if (asset is Map<String, dynamic> && asset['name'] is String)
          asset['name'] as String: asset,
    };
    final manifestAsset = assets.values.where((asset) {
      final name = asset['name'] as String;
      return name.startsWith('otzaria-vectors-') &&
          name.endsWith('.manifest.json');
    }).firstOrNull;
    if (manifestAsset == null) throw _malformed('manifest asset missing');
    final manifestName = manifestAsset['name'] as String;

    final manifestBytes = await _getBytes(
      client,
      manifestAsset['browser_download_url'] as String? ?? '',
    );
    final manifestSha = sha256.convert(manifestBytes).toString();
    final assetDigest = _assetSha256(manifestAsset);
    final notesDigest = parsePublishedManifestSha256(
      release['body'] as String?,
      manifestName,
    );
    // בלי digest שפורסם מחוץ למניפסט אין הבדל בין הרשמי לבין מה שנבנה מחדש.
    final published = notesDigest ?? assetDigest;
    if (published == null) {
      throw SemanticFailure(
        SemanticFailureKind.releaseUnverified,
        'no published SHA-256 for $manifestName',
      );
    }
    for (final expected in [assetDigest, notesDigest]) {
      if (expected != null && expected != manifestSha) {
        throw SemanticFailure(
          SemanticFailureKind.artifactNotPublished,
          'manifest $manifestName is $manifestSha, published $expected',
        );
      }
    }

    final manifestJson = utf8.decode(manifestBytes);
    final Object? manifest;
    try {
      manifest = jsonDecode(manifestJson);
    } on FormatException catch (error) {
      throw _malformed('manifest is not JSON: ${error.message}');
    }
    if (manifest is! Map<String, dynamic>) throw _malformed('manifest shape');
    final files = manifest['files'];
    if (files is! List || files.isEmpty) throw _malformed('manifest files');
    final kind = manifest['kind'];
    if (kind != 'base') {
      throw SemanticFailure(
        SemanticFailureKind.unsupportedRelease,
        'release kind $kind is not installed yet',
      );
    }
    final toVersion = _int(manifest['toLibraryVersion'], 'toLibraryVersion');
    if (toVersion != libraryVersion ||
        manifest['libraryReleaseTag'] != libraryTag) {
      throw _malformed(
        'manifest is for ${manifest['libraryReleaseTag']} (v$toVersion), '
        'requested $libraryTag (v$libraryVersion)',
      );
    }

    return SemanticVectorsRelease(
      libraryTag: libraryTag,
      releaseTag: releaseTag,
      toLibraryVersion: toVersion,
      kind: 'base',
      manifestJson: manifestJson,
      publishedManifestSha256: published,
      files: [
        for (final entry in files) _file(entry, assets),
      ],
      segmentUncompressedSize: _int(
        (manifest['segment'] as Map<String, dynamic>?)?['size'],
        'segment.size',
      ),
    );
  }

  static SemanticVectorsFile _file(
    Object? entry,
    Map<String, Map<String, dynamic>> assets,
  ) {
    if (entry is! Map<String, dynamic>) throw _malformed('file entry');
    final name = entry['file'];
    final sha = entry['sha256'];
    if (name is! String || sha is! String) throw _malformed('file entry');
    final asset = assets[name];
    if (asset == null) throw _malformed('asset $name missing from release');
    return SemanticVectorsFile(
      name: name,
      downloadUrl: asset['browser_download_url'] as String? ?? '',
      size: _int(entry['size'], '$name.size'),
      sha256: sha.toLowerCase(),
      assetId: asset['id']?.toString() ?? '',
    );
  }

  static String? _assetSha256(Map<String, dynamic> asset) =>
      switch (asset['digest']) {
        final String digest when digest.startsWith('sha256:') =>
          digest.substring('sha256:'.length).toLowerCase(),
        _ => null,
      };

  static int _int(Object? value, String field) {
    if (value is int) return value;
    throw _malformed('$field missing');
  }

  static SemanticFailure _malformed(String detail) =>
      SemanticFailure(SemanticFailureKind.releaseMalformed, detail);

  /// JSON מ-GitHub API; `null` על 404.
  static Future<Object?> _getJson(http.Client client, String url) async {
    final response = await client
        .get(
          Uri.parse(url),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'otzaria',
          },
        )
        .timeout(_timeout);
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'GitHub API returned ${response.statusCode}',
        Uri.parse(url),
      );
    }
    return jsonDecode(response.body);
  }

  static Future<List<int>> _getBytes(http.Client client, String url) async {
    final response = await client
        .get(Uri.parse(url), headers: const {'User-Agent': 'otzaria'})
        .timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'manifest download returned ${response.statusCode}',
        Uri.parse(url),
      );
    }
    return response.bodyBytes;
  }
}
