import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/library_update/services/github_rate_limit.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/repository/semantic_release_locator.dart';

const _api = 'https://api.github.test/repos/Otzaria/SeforimLibrary';
const _manifestName = 'otzaria-vectors-0c3f95be-v30-base.manifest.json';
const _segmentName = 'otzaria-vectors-0c3f95be-v30-base.oxv.zst';
const _manifestUrl = 'https://github.test/download/$_manifestName';
const _segmentUrl = 'https://github.test/download/$_segmentName';

String _manifestFor({
  String kind = 'base',
  int to = 30,
  String tag = 'v30-20260930165019',
}) => jsonEncode({
  'format': 'otzaria-vectors-release',
  'formatVersion': 1,
  'kind': kind,
  'fromLibraryVersion': 0,
  'toLibraryVersion': to,
  'libraryReleaseTag': tag,
  'segment': {'sha256': 'cd' * 32, 'size': 1779752972},
  'files': [
    {
      'file': _segmentName,
      'compression': 'zstd',
      'sha256': 'AB' * 32,
      'size': 1642517351,
      'uncompressedSha256': 'cd' * 32,
      'uncompressedSize': 1779752972,
    },
  ],
});

final _manifest = _manifestFor();

String _shaOf(String text) => sha256.convert(utf8.encode(text)).toString();

String get _manifestSha => _shaOf(_manifest);

class _Server {
  final List<String> requested = [];
  bool vectorsPublished = true;
  String? body;
  String? assetDigest;
  bool noAssetDigest = false;
  String manifest = _manifest;

  static http.Response _json(Object? body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status);

  MockClient client() => MockClient((request) async {
    final url = request.url.toString();
    requested.add(url);
    if (url == '$_api/releases?per_page=100&page=1') {
      return _json([
        if (vectorsPublished) {'tag_name': 'vectors-v30-20260930165019'},
        {'tag_name': 'v30-20260930165019'},
        {'tag_name': 'pipeline-result-run-1'},
        {'tag_name': 'v29-20260927072953'},
      ]);
    }
    if (url == '$_api/releases?per_page=100&page=2') {
      return http.Response('[]', 200);
    }
    if (url == '$_api/releases/tags/vectors-v30-20260930165019') {
      if (!vectorsPublished) return http.Response('{}', 404);
      return _json({
        'tag_name': 'vectors-v30-20260930165019',
        'body':
            body ??
            'Manifest: `$_manifestName`, SHA-256 `${_shaOf(manifest)}` — check it.',
        'assets': [
          {
            'id': 7,
            'name': _manifestName,
            'browser_download_url': _manifestUrl,
            if (!noAssetDigest)
              'digest': assetDigest ?? 'sha256:${_shaOf(manifest)}',
          },
          {
            'id': 8,
            'name': _segmentName,
            'browser_download_url': _segmentUrl,
          },
          {'id': 9, 'name': 'gates.json', 'browser_download_url': 'x'},
        ],
      });
    }
    if (url == _manifestUrl) {
      return http.Response.bytes(utf8.encode(manifest), 200);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  test('מוצא את vectors-<תג> לפי התג ולא דרך releases/latest', () async {
    final server = _Server();
    final locator = SemanticVectorsReleaseLocator(
      clientFactory: server.client,
      apiBase: _api,
    );

    final release = await locator.findForLibraryVersion(30);

    expect(release, isNotNull);
    expect(release!.libraryTag, 'v30-20260930165019');
    expect(release.releaseTag, 'vectors-v30-20260930165019');
    expect(release.toLibraryVersion, 30);
    expect(release.manifestJson, _manifest);
    expect(release.publishedManifestSha256, _manifestSha);
    expect(release.segmentUncompressedSize, 1779752972);
    expect(release.files.single.name, _segmentName);
    expect(release.files.single.downloadUrl, _segmentUrl);
    expect(release.files.single.sha256, 'ab' * 32);
    expect(release.segmentFileName, _segmentName);
    expect(
      server.requested,
      contains('$_api/releases/tags/vectors-v30-20260930165019'),
    );
    expect(server.requested.where((u) => u.contains('latest')), isEmpty);
  });

  test('תג ידוע חוסך את סריקת ה-releases', () async {
    final server = _Server();
    final locator = SemanticVectorsReleaseLocator(
      clientFactory: server.client,
      apiBase: _api,
    );

    await locator.findForLibraryVersion(
      30,
      libraryTag: 'v30-20260930165019',
    );

    expect(server.requested.where((u) => u.contains('per_page')), isEmpty);
  });

  test('release שעוד לא פורסם מחזיר null ולא שגיאה', () async {
    final server = _Server()..vectorsPublished = false;
    final locator = SemanticVectorsReleaseLocator(
      clientFactory: server.client,
      apiBase: _api,
    );

    expect(await locator.findForLibraryVersion(30), isNull);
    expect(await locator.findForLibraryVersion(31), isNull);
  });

  test('מניפסט שאינו תואם ל-digest שפורסם נדחה לפני ההורדה הגדולה', () async {
    final server = _Server()..body = 'SHA-256 `${'ee' * 32}`';
    final locator = SemanticVectorsReleaseLocator(
      clientFactory: server.client,
      apiBase: _api,
    );

    await expectLater(
      locator.findForLibraryVersion(30),
      throwsA(
        isA<SemanticFailure>().having(
          (f) => f.kind,
          'kind',
          SemanticFailureKind.artifactNotPublished,
        ),
      ),
    );
    expect(server.requested, isNot(contains(_segmentUrl)));
  });

  test('בלי digest בהערות — ה-digest של הנכס הוא המפורסם', () async {
    final server = _Server()..body = 'Semantic vectors.';
    final locator = SemanticVectorsReleaseLocator(
      clientFactory: server.client,
      apiBase: _api,
    );

    final release = await locator.findForLibraryVersion(30);
    expect(release!.publishedManifestSha256, _manifestSha);
  });

  test('בלי שום digest שפורסם — מסרבים (releaseUnverified)', () async {
    final server = _Server()
      ..body = 'Semantic vectors.'
      ..noAssetDigest = true;
    final locator = SemanticVectorsReleaseLocator(
      clientFactory: server.client,
      apiBase: _api,
    );

    await expectLater(
      locator.findForLibraryVersion(30),
      throwsA(
        isA<SemanticFailure>().having(
          (f) => f.kind,
          'kind',
          SemanticFailureKind.releaseUnverified,
        ),
      ),
    );
  });

  test('delta נדחה בבירור (unsupportedRelease)', () async {
    final server = _Server()..manifest = _manifestFor(kind: 'delta');
    final locator = SemanticVectorsReleaseLocator(
      clientFactory: server.client,
      apiBase: _api,
    );

    await expectLater(
      locator.findForLibraryVersion(30),
      throwsA(
        isA<SemanticFailure>().having(
          (f) => f.kind,
          'kind',
          SemanticFailureKind.unsupportedRelease,
        ),
      ),
    );
  });

  test('מניפסט של גרסה או תג אחרים נדחה', () async {
    for (final manifest in [
      _manifestFor(to: 29),
      _manifestFor(tag: 'v30-20990101000000'),
    ]) {
      final server = _Server()..manifest = manifest;
      final locator = SemanticVectorsReleaseLocator(
        clientFactory: server.client,
        apiBase: _api,
      );
      await expectLater(
        locator.findForLibraryVersion(30),
        throwsA(
          isA<SemanticFailure>().having(
            (f) => f.kind,
            'kind',
            SemanticFailureKind.releaseMalformed,
          ),
        ),
      );
    }
  });

  test('תג רמז של גרסה אחרת אינו משמש', () async {
    final server = _Server();
    final locator = SemanticVectorsReleaseLocator(
      clientFactory: server.client,
      apiBase: _api,
    );

    final release = await locator.findForLibraryVersion(
      30,
      libraryTag: 'v29-20260927072953',
    );

    expect(release!.libraryTag, 'v30-20260930165019');
    expect(server.requested.where((u) => u.contains('per_page')), isNotEmpty);
  });

  test('חסימת מכסה של GitHub נזרקת כ-GithubRateLimitException', () async {
    final locator = SemanticVectorsReleaseLocator(
      clientFactory: () => MockClient(
        (_) async => http.Response(
          '',
          403,
          headers: {'x-ratelimit-remaining': '0'},
        ),
      ),
      apiBase: _api,
    );

    await expectLater(
      locator.findForLibraryVersion(30),
      throwsA(isA<GithubRateLimitException>()),
    );
  });

  group('parsePublishedManifestSha256', () {
    test('הערך שאחרי שם המניפסט גובר', () {
      final body =
          'gates ${'11' * 32}\nManifest: `$_manifestName`, SHA-256 `${'22' * 32}`';
      expect(
        SemanticVectorsReleaseLocator.parsePublishedManifestSha256(
          body,
          _manifestName,
        ),
        '22' * 32,
      );
    });

    test('כמה ערכים בלי שם מכריע — null', () {
      expect(
        SemanticVectorsReleaseLocator.parsePublishedManifestSha256(
          '${'11' * 32} ${'22' * 32}',
          _manifestName,
        ),
        isNull,
      );
      expect(
        SemanticVectorsReleaseLocator.parsePublishedManifestSha256(
          null,
          _manifestName,
        ),
        isNull,
      );
    });
  });

  test('libraryTagFor מתעלם מתגי vectors ומתגים אחרים', () {
    final releases = [
      {'tag_name': 'vectors-v30-1'},
      {'tag_name': 'lines-snapshot-sha256-aa'},
      {'tag_name': 'v300-1'},
      {'tag_name': 'v30-20260930165019'},
    ];
    expect(
      SemanticVectorsReleaseLocator.libraryTagFor(releases, 30),
      'v30-20260930165019',
    );
    expect(SemanticVectorsReleaseLocator.libraryTagFor(releases, 29), isNull);
  });
}
