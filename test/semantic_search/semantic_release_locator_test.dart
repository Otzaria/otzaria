import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/library_update/services/github_rate_limit.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_family.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_release.dart';
import 'package:otzaria/semantic_search/repository/semantic_release_locator.dart';

const _api = 'https://api.github.test/repos/Otzaria/SeforimLibrary';
const _manifestName = 'otzaria-vectors-0c3f95be-v30-base.manifest.json';
const _segmentName = 'otzaria-vectors-0c3f95be-v30-base.oxv.zst';
const _manifestUrl = 'https://github.test/download/$_manifestName';
const _segmentUrl = 'https://github.test/download/$_segmentName';
const _windowsManifestName = 'otzaria-vectors-5d1e7a20-v30-base.manifest.json';
const _windowsSegmentName = 'otzaria-vectors-5d1e7a20-v30-base.oxv.zst';
const _windowsSegmentUrl = 'https://github.test/download/$_windowsSegmentName';

const _anchorChunking = 2685558872390372738;
const _windowsChunking = 320260894818558297;
const _modelFamilyId = 'otzaria/Meivin-Embed-QA491-native256';
const _anchor = (
  family: SemanticVectorsFamily.anchor,
  modelFamilyId: _modelFamilyId,
  chunkingIdentity: _anchorChunking,
);
const _windows = (
  family: SemanticVectorsFamily.windows,
  modelFamilyId: _modelFamilyId,
  chunkingIdentity: _windowsChunking,
);
const _anchorOnly = [_anchor];
const _windowsFirst = [_windows, _anchor];

String _manifestFor({
  String kind = 'base',
  int to = 30,
  String tag = 'v30-20260930165019',
  int chunking = _anchorChunking,
  String modelFamilyId = _modelFamilyId,
  String segmentName = _segmentName,
}) => jsonEncode({
  'format': 'otzaria-vectors-release',
  'formatVersion': 1,
  'kind': kind,
  'identity': {
    'model': {'family_id': modelFamilyId, 'chunking_identity': chunking},
  },
  'identityDigest': '$chunking'.padLeft(64, '0'),
  'fromLibraryVersion': 0,
  'toLibraryVersion': to,
  'libraryReleaseTag': tag,
  'segment': {'sha256': 'cd' * 32, 'size': 1779752972},
  'files': [
    {
      'file': segmentName,
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

  /// מניפסט `vectors-qa491-windows-<תג>`; `null` = לא פורסם.
  String? windowsManifest;

  /// קוד שגיאה שה-API מחזיר על `vectors-qa491-windows-<תג>`.
  int? windowsStatus;

  /// digest אחר מהמניפסט לנכס המניפסט של `vectors-qa491-windows-<תג>`.
  String? windowsAssetDigest;

  static http.Response _json(Object? body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status);

  MockClient client() => MockClient((request) async {
    final url = request.url.toString();
    requested.add(url);
    if (url == '$_api/releases?per_page=100&page=1') {
      return _json([
        if (vectorsPublished) {'tag_name': 'vectors-qa491-v30-20260930165019'},
        {'tag_name': 'v30-20260930165019'},
        {'tag_name': 'pipeline-result-run-1'},
        {'tag_name': 'v29-20260927072953'},
      ]);
    }
    if (url == '$_api/releases?per_page=100&page=2') {
      return http.Response('[]', 200);
    }
    if (url == '$_api/releases/tags/vectors-qa491-v30-20260930165019') {
      if (!vectorsPublished) return http.Response('{}', 404);
      return _json({
        'tag_name': 'vectors-qa491-v30-20260930165019',
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
    final windows = windowsManifest;
    if (url == '$_api/releases/tags/vectors-qa491-windows-v30-20260930165019') {
      final status = windowsStatus;
      if (status != null) return http.Response('blocked', status);
      if (windows == null) return http.Response('{}', 404);
      return _json({
        'tag_name': 'vectors-qa491-windows-v30-20260930165019',
        'body': 'Manifest: `$_windowsManifestName`',
        'assets': [
          {
            'id': 17,
            'name': _windowsManifestName,
            'browser_download_url':
                'https://github.test/download/$_windowsManifestName',
            'digest': windowsAssetDigest ?? 'sha256:${_shaOf(windows)}',
          },
          {
            'id': 18,
            'name': _windowsSegmentName,
            'browser_download_url': _windowsSegmentUrl,
          },
        ],
      });
    }
    if (windows != null &&
        url == 'https://github.test/download/$_windowsManifestName') {
      return http.Response.bytes(utf8.encode(windows), 200);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  test('מוצא את vectors-qa491-<תג> לפי התג ולא דרך releases/latest', () async {
    final server = _Server();
    final locator = SemanticVectorsReleaseLocator(
      clientFactory: server.client,
      apiBase: _api,
    );

    final release = await locator.findForLibraryVersion(
      30,
      candidates: _anchorOnly,
    );

    expect(release, isNotNull);
    expect(release!.libraryTag, 'v30-20260930165019');
    expect(release.releaseTag, 'vectors-qa491-v30-20260930165019');
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
      contains('$_api/releases/tags/vectors-qa491-v30-20260930165019'),
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
      candidates: _anchorOnly,
    );

    expect(server.requested.where((u) => u.contains('per_page')), isEmpty);
  });

  test('release שעוד לא פורסם מחזיר null ולא שגיאה', () async {
    final server = _Server()..vectorsPublished = false;
    final locator = SemanticVectorsReleaseLocator(
      clientFactory: server.client,
      apiBase: _api,
    );

    expect(
      await locator.findForLibraryVersion(30, candidates: _anchorOnly),
      isNull,
    );
    expect(
      await locator.findForLibraryVersion(31, candidates: _anchorOnly),
      isNull,
    );
  });

  test('מניפסט שאינו תואם ל-digest שפורסם נדחה לפני ההורדה הגדולה', () async {
    final server = _Server()..body = 'SHA-256 `${'ee' * 32}`';
    final locator = SemanticVectorsReleaseLocator(
      clientFactory: server.client,
      apiBase: _api,
    );

    await expectLater(
      locator.findForLibraryVersion(30, candidates: _anchorOnly),
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

    final release = await locator.findForLibraryVersion(
      30,
      candidates: _anchorOnly,
    );
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
      locator.findForLibraryVersion(30, candidates: _anchorOnly),
      throwsA(
        isA<SemanticFailure>().having(
          (f) => f.kind,
          'kind',
          SemanticFailureKind.releaseUnverified,
        ),
      ),
    );
  });

  // deltas מתפרסמים רק בתג נפרד (findDeltaChain); תג של base נושא base בלבד.
  test('delta בתג של base נדחה (unsupportedRelease)', () async {
    final server = _Server()..manifest = _manifestFor(kind: 'delta');
    final locator = SemanticVectorsReleaseLocator(
      clientFactory: server.client,
      apiBase: _api,
    );

    await expectLater(
      locator.findForLibraryVersion(30, candidates: _anchorOnly),
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
        locator.findForLibraryVersion(30, candidates: _anchorOnly),
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
      candidates: _anchorOnly,
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
      locator.findForLibraryVersion(30, candidates: _anchorOnly),
      throwsA(isA<GithubRateLimitException>()),
    );
  });

  group('משפחת החלונות', () {
    SemanticVectorsReleaseLocator locatorOf(_Server server) =>
        SemanticVectorsReleaseLocator(
          clientFactory: server.client,
          apiBase: _api,
        );

    test('מודל אחר עם אותה חלוקה נדחה לפני הורדת הווקטורים', () async {
      for (final familyId in ['', 'previous-model']) {
        final server = _Server()
          ..windowsManifest = _manifestFor(
            modelFamilyId: familyId,
            chunking: _windowsChunking,
            segmentName: _windowsSegmentName,
          );
        final fallback = await locatorOf(
          server,
        ).findForLibraryVersion(30, candidates: _windowsFirst);
        expect(fallback!.family, SemanticVectorsFamily.anchor);

        await expectLater(
          locatorOf(server).findForLibraryVersion(
            30,
            candidates: const [_windows],
          ),
          throwsA(
            isA<SemanticFailure>()
                .having(
                  (f) => f.kind,
                  'kind',
                  SemanticFailureKind.artifactIncompatible,
                )
                .having((f) => f.field, 'field', 'model.family_id'),
          ),
        );
        expect(server.requested, isNot(contains(_windowsSegmentUrl)));
      }
    });

    test('vectors-qa491-windows-<תג> קודם, עם הזהות שבמניפסט', () async {
      final server = _Server()
        ..windowsManifest = _manifestFor(
          chunking: _windowsChunking,
          segmentName: _windowsSegmentName,
        );

      final release = await locatorOf(
        server,
      ).findForLibraryVersion(30, candidates: _windowsFirst);

      expect(release!.releaseTag, 'vectors-qa491-windows-v30-20260930165019');
      expect(release.chunkingIdentity, _windowsChunking);
      expect(release.family, SemanticVectorsFamily.windows);
      expect(release.identityDigest, '$_windowsChunking'.padLeft(64, '0'));
      expect(release.files.single.downloadUrl, _windowsSegmentUrl);
      expect(
        server.requested,
        isNot(contains('$_api/releases/tags/vectors-qa491-v30-20260930165019')),
      );
    });

    test('בלי vectors-qa491-windows-<תג> נופלים ל-vectors-<תג>', () async {
      final server = _Server();

      final release = await locatorOf(
        server,
      ).findForLibraryVersion(30, candidates: _windowsFirst);

      expect(release!.releaseTag, 'vectors-qa491-v30-20260930165019');
      expect(release.chunkingIdentity, _anchorChunking);
    });

    test('מנוע בלי חלונות אינו מבקש את vectors-qa491-windows-<תג>', () async {
      final server = _Server()
        ..windowsManifest = _manifestFor(
          chunking: _windowsChunking,
          segmentName: _windowsSegmentName,
        );

      final release = await locatorOf(
        server,
      ).findForLibraryVersion(30, candidates: _anchorOnly);

      expect(release!.releaseTag, 'vectors-qa491-v30-20260930165019');
      expect(server.requested.where((u) => u.contains('windows')), isEmpty);
    });

    test('chunking שאינו של המשפחה: הבאה בתור, ובלעדיה נדחה', () async {
      final server = _Server()
        ..windowsManifest = _manifestFor(segmentName: _windowsSegmentName);

      final fallback = await locatorOf(
        server,
      ).findForLibraryVersion(30, candidates: _windowsFirst);
      expect(fallback!.releaseTag, 'vectors-qa491-v30-20260930165019');

      await expectLater(
        locatorOf(
          server,
        ).findForLibraryVersion(30, candidates: const [_windows]),
        throwsA(
          isA<SemanticFailure>()
              .having(
                (f) => f.kind,
                'kind',
                SemanticFailureKind.artifactIncompatible,
              )
              .having((f) => f.field, 'field', 'model.chunking_identity'),
        ),
      );
      expect(server.requested, isNot(contains(_windowsSegmentUrl)));
    });
  });

  group('כשל במשפחת החלונות', () {
    SemanticVectorsReleaseLocator locatorOf(_Server server) =>
        SemanticVectorsReleaseLocator(
          clientFactory: server.client,
          apiBase: _api,
        );

    for (final status in [500, 418, 403]) {
      test(
        'תשובה $status על vectors-qa491-windows-<תג> נופלת לסט הישן',
        () async {
          final server = _Server()..windowsStatus = status;

          final release = await locatorOf(
            server,
          ).findForLibraryVersion(30, candidates: _windowsFirst);

          expect(release!.releaseTag, 'vectors-qa491-v30-20260930165019');
        },
      );
    }

    test('מניפסט חלונות שאינו תואם ל-digest נופל לסט הישן', () async {
      final server = _Server()
        ..windowsManifest = _manifestFor(
          chunking: _windowsChunking,
          segmentName: _windowsSegmentName,
        )
        ..windowsAssetDigest = 'sha256:${'ee' * 32}';

      final release = await locatorOf(
        server,
      ).findForLibraryVersion(30, candidates: _windowsFirst);

      expect(release!.releaseTag, 'vectors-qa491-v30-20260930165019');
      expect(server.requested, isNot(contains(_windowsSegmentUrl)));
    });

    for (final segment in <Object?>['invalid shape', [], null]) {
      test(
        'מבנה segment שגוי בחלונות מאפשר נפילה לסט הישן ($segment)',
        () async {
          final manifest =
              jsonDecode(
                    _manifestFor(
                      chunking: _windowsChunking,
                      segmentName: _windowsSegmentName,
                    ),
                  )
                  as Map<String, dynamic>;
          manifest['segment'] = segment;
          final server = _Server()..windowsManifest = jsonEncode(manifest);

          final release = await locatorOf(server).findForLibraryVersion(
            30,
            candidates: _windowsFirst,
          );
          expect(release!.family, SemanticVectorsFamily.anchor);

          await expectLater(
            locatorOf(
              server,
            ).findForLibraryVersion(30, candidates: const [_windows]),
            throwsA(
              isA<SemanticFailure>().having(
                (f) => f.kind,
                'kind',
                SemanticFailureKind.releaseMalformed,
              ),
            ),
          );
        },
      );
    }

    for (final field in ['assets', 'body', 'manifest URL', 'segment URL']) {
      test('שדה release שגוי בחלונות מאפשר נפילה לסט הישן ($field)', () async {
        final server = _Server()
          ..windowsManifest = _manifestFor(
            chunking: _windowsChunking,
            segmentName: _windowsSegmentName,
          );
        final client = server.client();
        final locator = SemanticVectorsReleaseLocator(
          apiBase: _api,
          clientFactory: () => MockClient((request) async {
            final response = await client.get(request.url);
            if (!request.url.path.contains(
              '/releases/tags/vectors-qa491-windows-',
            )) {
              return response;
            }
            final release = jsonDecode(response.body) as Map<String, dynamic>;
            switch (field) {
              case 'assets':
                release['assets'] = 'invalid shape';
              case 'body':
                release['body'] = [];
              case 'manifest URL':
                release['assets'][0]['browser_download_url'] = 7;
              case 'segment URL':
                release['assets'][1]['browser_download_url'] = 7;
            }
            return http.Response.bytes(utf8.encode(jsonEncode(release)), 200);
          }),
        );

        final release = await locator.findForLibraryVersion(
          30,
          candidates: _windowsFirst,
        );
        expect(release!.family, SemanticVectorsFamily.anchor);
        client.close();
      });
    }

    test('כשהסט הישן לא פורסם, כשל החלונות נזרק ולא null', () async {
      final server = _Server()
        ..windowsStatus = 500
        ..vectorsPublished = false;

      await expectLater(
        locatorOf(server).findForLibraryVersion(30, candidates: _windowsFirst),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('כששני המועמדים נכשלים — נזרק הכשל של האחרון', () async {
      final server = _Server()
        ..windowsStatus = 500
        ..body = 'SHA-256 `${'ee' * 32}`';

      await expectLater(
        locatorOf(server).findForLibraryVersion(30, candidates: _windowsFirst),
        throwsA(
          isA<SemanticFailure>().having(
            (f) => f.kind,
            'kind',
            SemanticFailureKind.artifactNotPublished,
          ),
        ),
      );
    });
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
      {'tag_name': 'vectors-qa491-v30-1'},
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

  group('שרשרת deltas', _deltaChainTests);
}

String _libraryTagOf(int version) => 'v$version-20260930165019';
final String _windowsDigest = '$_windowsChunking'.padLeft(64, '0');

/// ה-base של משפחת החלונות ב-v30, בגודל הורדה 1000.
SemanticVectorsRelease _windowsBase({
  SemanticVectorsFamily family = SemanticVectorsFamily.windows,
}) => SemanticVectorsRelease(
  libraryTag: _libraryTagOf(30),
  releaseTag: '${family.releaseTagPrefix}${_libraryTagOf(30)}',
  toLibraryVersion: 30,
  kind: 'base',
  manifestJson: '{}',
  publishedManifestSha256: 'aa' * 32,
  files: const [
    SemanticVectorsFile(
      name: 'otzaria-vectors-5d1e7a20-v30-base.oxv.zst',
      downloadUrl: 'https://github.test/download/base',
      size: 1000,
      sha256: 'ab',
      assetId: '1',
    ),
  ],
  segmentUncompressedSize: 1200,
  identityDigest: _windowsDigest,
  chunkingIdentity: _windowsChunking,
  family: family,
);

/// deltas שפורסמו: לפי גרסת היעד — הגרסה שממנה וגודל ההורדה.
class _DeltaServer {
  final Map<int, ({int from, int size})> deltas = {};
  final List<String> requested = [];
  String identityDigest = _windowsDigest;
  String? notesSha;

  /// `fromLibraryVersion` שהמניפסט מצהיר במקום הגרסה שבשמו.
  int? manifestFrom;

  /// תשובה במקום ה-release של ה-delta.
  http.Response? deltaResponse;

  String _manifestName(int from, int to) =>
      'otzaria-vectors-5d1e7a20-v$from-v$to.manifest.json';

  String manifest(int to) {
    final delta = deltas[to]!;
    return jsonEncode({
      'kind': 'delta',
      'identity': {
        'model': {'chunking_identity': _windowsChunking},
      },
      'identityDigest': identityDigest,
      'fromLibraryVersion': manifestFrom ?? delta.from,
      'toLibraryVersion': to,
      'libraryReleaseTag': _libraryTagOf(to),
      'segment': {'sha256': 'cd' * 32, 'size': delta.size * 2},
      'files': [
        {
          'file': 'otzaria-vectors-5d1e7a20-v${delta.from}-v$to.oxv.zst',
          'sha256': 'ef' * 32,
          'size': delta.size,
        },
      ],
    });
  }

  MockClient client() => MockClient((request) async {
    final url = request.url.toString();
    requested.add(url);
    if (url == '$_api/releases?per_page=100&page=1') {
      return http.Response(
        jsonEncode([
          for (var v = 31; v >= 10; v--) ...[
            {'tag_name': 'vectors-qa491-windows-delta-${_libraryTagOf(v)}'},
            {'tag_name': _libraryTagOf(v)},
          ],
        ]),
        200,
      );
    }
    if (url.contains('per_page=100&page=')) return http.Response('[]', 200);
    final tag = RegExp(
      r'/releases/tags/vectors-qa491-windows-delta-v(\d+)-',
    ).firstMatch(url);
    if (tag != null) {
      final to = int.parse(tag.group(1)!);
      final delta = deltas[to];
      final override = deltaResponse;
      if (override != null) return override;
      if (delta == null) return http.Response('{}', 404);
      final name = _manifestName(delta.from, to);
      final segment = 'otzaria-vectors-5d1e7a20-v${delta.from}-v$to.oxv.zst';
      return http.Response(
        jsonEncode({
          'tag_name': 'vectors-qa491-windows-delta-${_libraryTagOf(to)}',
          'body':
              'Manifest: `$name`, SHA-256 `${notesSha ?? _shaOf(manifest(to))}`',
          'assets': [
            {
              'id': 100 + to,
              'name': name,
              'browser_download_url': 'https://github.test/download/$name',
            },
            {
              'id': 200 + to,
              'name': segment,
              'browser_download_url': 'https://github.test/download/$segment',
            },
          ],
        }),
        200,
      );
    }
    final manifestUrl = RegExp(r'-v(\d+)-v(\d+)\.manifest\.json$');
    final match = manifestUrl.firstMatch(url);
    if (match != null) {
      return http.Response.bytes(
        utf8.encode(manifest(int.parse(match.group(2)!))),
        200,
      );
    }
    return http.Response('not found', 404);
  });

  Future<List<SemanticVectorsRelease>?> chain(
    int installed, {
    SemanticVectorsRelease? target,
  }) =>
      SemanticVectorsReleaseLocator(
        clientFactory: client,
        apiBase: _api,
      ).findDeltaChain(
        target: target ?? _windowsBase(),
        installedVersion: installed,
      );
}

void _deltaChainTests() {
  test('השרשרת מהגרסה המותקנת אל היעד, לפי סדר ההתקנה', () async {
    final server = _DeltaServer()
      ..deltas[29] = (from: 28, size: 100)
      ..deltas[30] = (from: 29, size: 100);

    final chain = await server.chain(28);

    expect(chain!.map((d) => (d.fromLibraryVersion, d.toLibraryVersion)), [
      (28, 29),
      (29, 30),
    ]);
    final last = chain.last;
    expect(last.kind, 'delta');
    expect(last.isDelta, isTrue);
    expect(last.releaseTag, 'vectors-qa491-windows-delta-${_libraryTagOf(30)}');
    expect(last.publishedManifestSha256, _shaOf(server.manifest(30)));
    expect(last.files.single.name, 'otzaria-vectors-5d1e7a20-v29-v30.oxv.zst');
    expect(last.family, SemanticVectorsFamily.windows);
  });

  test('delta שמדלג על גרסה ריקה, בלי סריקת releases', () async {
    final server = _DeltaServer()..deltas[30] = (from: 28, size: 100);

    final chain = await server.chain(28);

    expect(chain!.single.fromLibraryVersion, 28);
    expect(server.requested.where((u) => u.contains('per_page')), isEmpty);
  });

  test('יותר מ-${kSemanticDeltaChainLimits.maxSteps} צעדים — base', () async {
    final steps = kSemanticDeltaChainLimits.maxSteps + 1;
    final server = _DeltaServer();
    for (var to = 30; to > 30 - steps; to--) {
      server.deltas[to] = (from: to - 1, size: 1);
    }

    expect(await server.chain(30 - steps), isNull);
    expect(await server.chain(30 - steps + 1), hasLength(steps - 1));
  });

  test('deltas גדולים ממחצית ה-base — base', () async {
    final server = _DeltaServer()
      ..deltas[29] = (from: 28, size: 250)
      ..deltas[30] = (from: 29, size: 251);

    expect(await server.chain(28), isNull);
    server.deltas[30] = (from: 29, size: 250);
    expect(await server.chain(28), hasLength(2));
  });

  test('חוליה חסרה (404) — base', () async {
    final server = _DeltaServer()..deltas[30] = (from: 29, size: 1);

    expect(await server.chain(28), isNull);
  });

  test('delta שמתחיל לפני הגרסה המותקנת — base', () async {
    final server = _DeltaServer()..deltas[30] = (from: 28, size: 1);

    expect(await server.chain(29), isNull);
  });

  test('זהות אחרת ב-delta — base', () async {
    final server = _DeltaServer()
      ..deltas[30] = (from: 29, size: 1)
      ..identityDigest = 'ee' * 32;

    expect(await server.chain(29), isNull);
  });

  test('מניפסט שאינו תואם ל-digest שבהערות — base', () async {
    final server = _DeltaServer()
      ..deltas[30] = (from: 29, size: 1)
      ..notesSha = 'ee' * 32;

    expect(await server.chain(29), isNull);
  });

  test('המשפחה הישנה מתעדכנת רק ב-base, בלי לפנות לרשת', () async {
    final server = _DeltaServer()..deltas[30] = (from: 29, size: 1);

    expect(
      await server.chain(
        29,
        target: _windowsBase(family: SemanticVectorsFamily.anchor),
      ),
      isNull,
    );
    expect(server.requested, isEmpty);
  });

  for (final from in [30, 31, 28]) {
    test('מניפסט שמצהיר v$from-v30 בשם v29-v30 — base', () async {
      final server = _DeltaServer()
        ..deltas[30] = (from: 29, size: 1)
        ..manifestFrom = from;

      expect(await server.chain(29), isNull);
    });
  }

  test('חסימת מכסה בגילוי השרשרת נזרקת, לא base', () async {
    final server = _DeltaServer()
      ..deltas[30] = (from: 29, size: 1)
      ..deltaResponse = http.Response(
        '',
        403,
        headers: {'x-ratelimit-remaining': '0'},
      );

    await expectLater(
      server.chain(29),
      throwsA(isA<GithubRateLimitException>()),
    );
  });

  test('שגיאת שרת בגילוי השרשרת נזרקת, לא base', () async {
    final server = _DeltaServer()
      ..deltas[30] = (from: 29, size: 1)
      ..deltaResponse = http.Response('oops', 502);

    await expectLater(
      server.chain(29),
      throwsA(isA<http.ClientException>()),
    );
  });
}
