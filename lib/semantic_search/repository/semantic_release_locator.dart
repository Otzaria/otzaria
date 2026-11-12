import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:otzaria/library_update/services/github_rate_limit.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_family.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_release.dart';

/// מתי שרשרת deltas עדיפה על base: עד [maxSteps] צעדים, ובסך הורדה של עד
/// [maxBaseSizeRatio] מה-base. מעבר לזה — ה-base.
const kSemanticDeltaChainLimits = (maxSteps: 8, maxBaseSizeRatio: 0.5);

/// מאתר ב-SeforimLibrary את release הוקטורים של גרסת ספרייה.
///
/// ה-release נקרא בתחילית המשפחה ואחריה תג הספרייה, ואינו מסומן latest, ולכן
/// הוא נמצא לפי התג בלבד. GitHub שחסם מכסה זורק [GithubRateLimitException].
class SemanticVectorsReleaseLocator {
  static const String defaultApiBase =
      'https://api.github.com/repos/Otzaria/SeforimLibrary';
  static const Duration _timeout = Duration(seconds: 15);

  /// כמה עמודי releases לסרוק בחיפוש תג הספרייה (100 בעמוד).
  static const int _maxPages = 3;

  static final RegExp _libraryTag = RegExp(r'^v(\d+)-');
  static final RegExp _deltaManifest = RegExp(
    r'-v(\d+)-v(\d+)\.manifest\.json$',
  );
  static final RegExp _sha256 = RegExp(r'\b[0-9a-f]{64}\b');

  final http.Client Function() _clientFactory;
  final String _apiBase;

  SemanticVectorsReleaseLocator({
    http.Client Function()? clientFactory,
    this._apiBase = defaultApiBase,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  /// ה-release של גרסת הספרייה [libraryVersion] מהמועמד הראשון ב-[candidates]
  /// שנמצא תקין, או `null` כשאף אחד לא פורסם. [libraryTag] חוסך את סריקת
  /// ה-releases כשהתג ידוע.
  ///
  /// כשל במועמד (רשת, release פגום, digest או chunking שאינם תואמים) עובר
  /// למועמד הבא. כשאף מועמד לא נמצא תקין נזרק הכשל האחרון: של המועמד הרחב
  /// ביותר, או של קודמו כשהרחב לא פורסם — אז release קיים ולא הושג.
  Future<SemanticVectorsRelease?> findForLibraryVersion(
    int libraryVersion, {
    String? libraryTag,
    required List<SemanticVectorsCandidate> candidates,
  }) async {
    final client = GithubRateLimitAwareClient(_clientFactory());
    try {
      final hint =
          libraryTag != null && versionOfTag(libraryTag) == libraryVersion
          ? libraryTag
          : null;
      final tag = hint ?? await _findLibraryTag(client, libraryVersion);
      if (tag == null) return null;
      (Object, StackTrace)? failure;
      for (final candidate in candidates) {
        try {
          final release = await _findCandidate(
            client,
            candidate,
            tag,
            libraryVersion,
          );
          if (release != null) return release;
        } catch (error, stackTrace) {
          if (error is Error) rethrow;
          failure = (error, stackTrace);
        }
      }
      if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2);
      return null;
    } finally {
      client.close();
    }
  }

  /// ה-deltas מ-[installedVersion] אל [target] לפי סדר ההתקנה; `null` — ה-base
  /// עדיף. כשל רשת נזרק: base של כמה GB אינו תחליף לניסיון חוזר.
  Future<List<SemanticVectorsRelease>?> findDeltaChain({
    required SemanticVectorsRelease target,
    required int installedVersion,
  }) async {
    final prefix = target.family.deltaReleaseTagPrefix;
    if (prefix == null ||
        target.identityDigest.isEmpty ||
        installedVersion >= target.toLibraryVersion) {
      return null;
    }
    final maxBytes =
        target.downloadSize * kSemanticDeltaChainLimits.maxBaseSizeRatio;
    final client = GithubRateLimitAwareClient(_clientFactory());
    try {
      final chain = <SemanticVectorsRelease>[];
      final scanned = <dynamic>[];
      var scannedPages = 0;
      Future<String?> tagOf(int version) async {
        var tag = libraryTagFor(scanned, version);
        while (tag == null && scannedPages < _maxPages) {
          final list = await _getJson(
            client,
            '$_apiBase/releases?per_page=100&page=${++scannedPages}',
          );
          if (list is! List || list.isEmpty) return null;
          scanned.addAll(list);
          tag = libraryTagFor(list, version);
        }
        return tag;
      }

      String? tag = target.libraryTag;
      var to = target.toLibraryVersion;
      var bytes = 0;
      while (to > installedVersion) {
        if (tag == null || chain.length >= kSemanticDeltaChainLimits.maxSteps) {
          return null;
        }
        final delta = await _findDelta(client, '$prefix$tag', tag, to, target);
        if (delta == null || delta.fromLibraryVersion < installedVersion) {
          return null;
        }
        bytes += delta.downloadSize;
        if (bytes > maxBytes) return null;
        chain.insert(0, delta);
        to = delta.fromLibraryVersion;
        if (to > installedVersion) tag = await tagOf(to);
      }
      return chain;
    } on SemanticFailure catch (failure) {
      if (!const {
        SemanticFailureKind.releaseMalformed,
        SemanticFailureKind.unsupportedRelease,
        SemanticFailureKind.artifactNotPublished,
        SemanticFailureKind.releaseUnverified,
      }.contains(failure.kind)) {
        rethrow;
      }
      debugPrint('[SemanticSearch] delta chain unusable: $failure');
      return null;
    } on FormatException catch (error) {
      debugPrint('[SemanticSearch] delta chain unusable: $error');
      return null;
    } finally {
      client.close();
    }
  }

  /// ה-delta שב-[releaseTag] אל [to]; `null` כשלא פורסם או כשאינו של זהות [target].
  Future<SemanticVectorsRelease?> _findDelta(
    http.Client client,
    String releaseTag,
    String tag,
    int to,
    SemanticVectorsRelease target,
  ) async {
    final release = await _getJson(
      client,
      '$_apiBase/releases/tags/${Uri.encodeComponent(releaseTag)}',
    );
    if (release == null) return null;
    if (release is! Map<String, dynamic>) throw _malformed('release JSON');
    final delta = await _parseRelease(
      client,
      release,
      tag,
      releaseTag,
      to,
      target.family,
      kind: 'delta',
    );
    return delta.identityDigest == target.identityDigest &&
            delta.chunkingIdentity == target.chunkingIdentity
        ? delta
        : null;
  }

  /// ה-release של [candidate]; `null` כשלא פורסם.
  Future<SemanticVectorsRelease?> _findCandidate(
    http.Client client,
    SemanticVectorsCandidate candidate,
    String tag,
    int libraryVersion,
  ) async {
    final releaseTag = '${candidate.family.releaseTagPrefix}$tag';
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
    final parsed = await _parseRelease(
      client,
      release,
      tag,
      releaseTag,
      libraryVersion,
      candidate.family,
    );
    // מתכונת חלוקה זהה אינה מבטיחה שהווקטורים הופקו באותו מודל.
    if (parsed.modelFamilyId != candidate.modelFamilyId) {
      throw SemanticFailure(
        SemanticFailureKind.artifactIncompatible,
        '$releaseTag is model ${parsed.modelFamilyId}, '
            'expected ${candidate.modelFamilyId}',
        'model.family_id',
      );
    }
    if (parsed.chunkingIdentity != candidate.chunkingIdentity) {
      throw SemanticFailure(
        SemanticFailureKind.artifactIncompatible,
        '$releaseTag is chunking ${parsed.chunkingIdentity}, '
            'expected ${candidate.chunkingIdentity}',
        'model.chunking_identity',
      );
    }
    return parsed;
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
    SemanticVectorsFamily family, {
    String kind = 'base',
  }) async {
    final releaseAssets = release['assets'];
    if (releaseAssets is! List) throw _malformed('release assets');
    final assets = <String, Map<String, dynamic>>{
      for (final asset in releaseAssets)
        if (asset is Map<String, dynamic> && asset['name'] is String)
          asset['name'] as String: asset,
    };
    final manifests = assets.values.where((asset) {
      final name = asset['name'] as String;
      return name.startsWith('otzaria-vectors-') &&
          name.endsWith('.manifest.json');
    });
    final manifestAsset = kind == 'delta'
        ? manifests
              .where((a) => _deltaManifest.hasMatch(a['name'] as String))
              .firstOrNull
        : manifests
                  .where(
                    (a) =>
                        (a['name'] as String).endsWith('-base.manifest.json'),
                  )
                  .firstOrNull ??
              manifests.firstOrNull;
    if (manifestAsset == null) throw _malformed('manifest asset missing');
    final manifestName = manifestAsset['name'] as String;

    final manifestBytes = await _getBytes(
      client,
      _string(manifestAsset['browser_download_url'], 'manifest download URL'),
    );
    final manifestSha = sha256.convert(manifestBytes).toString();
    final assetDigest = _assetSha256(manifestAsset);
    final body = release['body'];
    if (body != null && body is! String) throw _malformed('release body');
    final notesDigest = parsePublishedManifestSha256(
      body as String?,
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
    final manifestKind = manifest['kind'];
    if (manifestKind != kind) {
      throw SemanticFailure(
        SemanticFailureKind.unsupportedRelease,
        '$releaseTag holds a $manifestKind manifest, expected $kind',
      );
    }
    final toVersion = _int(manifest['toLibraryVersion'], 'toLibraryVersion');
    final fromVersion = switch (manifest['fromLibraryVersion']) {
      final int version => version,
      _ when kind == 'base' => 0,
      _ => throw _malformed('fromLibraryVersion missing'),
    };
    if (kind == 'delta') {
      final named = _deltaManifest.firstMatch(manifestName)!;
      if (fromVersion >= toVersion ||
          int.parse(named.group(1)!) != fromVersion ||
          int.parse(named.group(2)!) != toVersion) {
        throw _malformed('$manifestName holds v$fromVersion-v$toVersion');
      }
    }
    if (toVersion != libraryVersion ||
        manifest['libraryReleaseTag'] != libraryTag) {
      throw _malformed(
        'manifest is for ${manifest['libraryReleaseTag']} (v$toVersion), '
        'requested $libraryTag (v$libraryVersion)',
      );
    }

    final segment = manifest['segment'];
    if (segment is! Map<String, dynamic>) throw _malformed('manifest segment');
    final identity = SemanticVectorsRelease.identityOf(
      manifest,
      rawJson: manifestJson,
    );
    return SemanticVectorsRelease(
      libraryTag: libraryTag,
      releaseTag: releaseTag,
      toLibraryVersion: toVersion,
      kind: kind,
      fromLibraryVersion: fromVersion,
      manifestJson: manifestJson,
      publishedManifestSha256: published,
      files: [
        for (final entry in files) _file(entry, assets),
      ],
      segmentUncompressedSize: _int(segment['size'], 'segment.size'),
      identityDigest: identity.identityDigest,
      modelFamilyId: identity.modelFamilyId,
      chunkingIdentity: identity.chunkingIdentity,
      family: family,
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
      downloadUrl: _string(asset['browser_download_url'], '$name download URL'),
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

  static String _string(Object? value, String field) {
    if (value is String) return value;
    throw _malformed('$field missing');
  }

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
