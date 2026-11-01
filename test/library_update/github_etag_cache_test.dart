import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/library_update/services/github_etag_cache.dart';
import 'package:otzaria/library_update/services/github_rate_limit.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late GithubEtagCache cache;
  final releases = Uri.parse('https://api.github.com/repos/o/r/releases');

  setUp(() {
    dir = Directory.systemTemp.createTempSync('github_etag_test');
    cache = GithubEtagCache(() async => p.join(dir.path, 'cache'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('תשובה עם ETag נשמרת, והבקשה הבאה מותנית ומקבלת 304 כ-200', () async {
    final seenIfNoneMatch = <String?>[];
    final client = GithubRateLimitAwareClient(
      MockClient((request) async {
        seenIfNoneMatch.add(request.headers['If-None-Match']);
        if (request.headers['If-None-Match'] == '"v1"') {
          return http.Response('', 304, headers: {'etag': '"v1"'});
        }
        return http.Response(
          '[{"tag_name":"א"}]',
          200,
          headers: {
            'etag': '"v1"',
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
      cache,
    );

    final first = await client.get(releases);
    final second = await client.get(releases);

    expect(seenIfNoneMatch, [null, '"v1"']);
    expect(second.statusCode, 200);
    expect(second.body, first.body);
    expect(second.body, '[{"tag_name":"א"}]');
  });

  test('תוכן שהשתנה מחליף את המטמון', () async {
    final client = GithubRateLimitAwareClient(
      MockClient((request) async {
        expect(request.headers['If-None-Match'], '"v1"');
        return http.Response('v2', 200, headers: {'etag': '"v2"'});
      }),
      cache,
    );
    await cache.write(
      releases,
      GithubEtagEntry(
        etag: '"v1"',
        contentType: null,
        body: Uint8List.fromList('v1'.codeUnits),
      ),
    );

    expect((await client.get(releases)).body, 'v2');
    expect((await cache.read(releases))!.etag, '"v2"');
  });

  test('שרת אחר, שיטה אחרת ותשובה בלי ETag אינם נשמרים', () async {
    final client = GithubRateLimitAwareClient(
      MockClient((request) async {
        expect(request.headers.containsKey('If-None-Match'), isFalse);
        return http.Response('x', 200, headers: {'etag': '"e"'});
      }),
      cache,
    );
    await client.get(Uri.parse('https://example.com/a'));
    await client.post(releases);
    expect(await cache.read(Uri.parse('https://example.com/a')), isNull);
    expect(await cache.read(releases), isNull);

    final noEtag = GithubRateLimitAwareClient(
      MockClient((_) async => http.Response('x', 200)),
      cache,
    );
    await noEtag.get(releases);
    expect(await cache.read(releases), isNull);
  });

  test('חסימת מכסה ממשיכה להיזרק גם כשיש מטמון', () async {
    await cache.write(
      releases,
      GithubEtagEntry(
        etag: '"v1"',
        contentType: null,
        body: Uint8List.fromList('v1'.codeUnits),
      ),
    );
    final client = GithubRateLimitAwareClient(
      MockClient(
        (_) async =>
            http.Response('', 403, headers: {'x-ratelimit-remaining': '0'}),
      ),
      cache,
    );
    await expectLater(
      client.get(releases),
      throwsA(isA<GithubRateLimitException>()),
    );
  });

  test(
    'גוף קטוע או כתיבות מקבילות: לא מוגש גוף פגום ולא נשארים קבצים זמניים',
    () async {
      final entry = GithubEtagEntry(
        etag: 'W/"weak"',
        contentType: null,
        body: Uint8List.fromList(List.filled(1000, 65)),
      );
      await Future.wait([
        for (var i = 0; i < 5; i++) cache.write(releases, entry),
      ]);
      final files = Directory(p.join(dir.path, 'cache')).listSync();
      expect(files, hasLength(1));
      expect((await cache.read(releases))!.etag, 'W/"weak"');

      final file = File(files.single.path);
      final bytes = file.readAsBytesSync();
      file.writeAsBytesSync(bytes.sublist(0, bytes.length - 10));
      expect(await cache.read(releases), isNull);
    },
  );

  test('קובץ מטמון פגום מתעלמים ממנו', () async {
    final probe = GithubEtagCache(() async => p.join(dir.path, 'cache'));
    await probe.write(
      releases,
      GithubEtagEntry(etag: '"v1"', contentType: null, body: Uint8List(0)),
    );
    final file = Directory(p.join(dir.path, 'cache')).listSync().single;
    File(file.path).writeAsStringSync('לא JSON');
    expect(await probe.read(releases), isNull);
  });
}
