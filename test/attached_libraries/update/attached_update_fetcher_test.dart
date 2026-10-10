import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_host_policy.dart';
import 'package:path/path.dart' as p;

/// שרת מקומי: נתיב → תוכן, עם הפניות, השהיה ותמיכה ב-Range לפי דגל.
class _Server {
  late HttpServer server;
  final files = <String, List<int>>{};
  final redirects = <String, String>{};
  final ranges = <String>[];
  final stall = <String>{};
  bool honorRange = true;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final response = request.response;
    if (path == '/hang') {
      await Future<void>.delayed(const Duration(seconds: 30));
      return;
    }
    final redirect = redirects[path];
    if (redirect != null) {
      response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, redirect);
      await response.close();
      return;
    }
    final body = files[path];
    if (body == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final range = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    if (range != null) ranges.add('$path $range');
    if (range != null && honorRange) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${body.length - 1}/${body.length}',
        );
    }
    response.contentLength = body.length - start;
    if (stall.contains(path)) {
      response.add(body.sublist(start, start + 1));
      await response.flush();
      await Future<void>.delayed(const Duration(seconds: 30));
      return;
    }
    response.add(body.sublist(start));
    await response.close();
  }
}

List<int> _data(int length, int seed) =>
    List.generate(length, (i) => (i * 31 + seed) % 251);

AttachedUpdatePart _part(_Server s, String path, List<int> body) =>
    AttachedUpdatePart(
      url: s.url(path),
      size: body.length,
      sha256: sha256.convert(body).toString(),
    );

void main() {
  late _Server s;
  late AttachedUpdateFetcher fetcher;
  late Directory temp;

  setUp(() async {
    s = _Server();
    await s.start();
    fetcher = AttachedUpdateFetcher(
      policy: AttachedUpdateHostPolicy.allowLoopbackForTesting({s.server.port}),
      readTimeout: const Duration(seconds: 2),
    );
    temp = await Directory.systemTemp.createTemp('otzaria_update_fetch');
  });

  tearDown(() async {
    await s.server.close(force: true);
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  test('production policy refuses the local test server', () async {
    s.files['/m.json'] = [1];
    await expectLater(
      AttachedUpdateFetcher().fetchBytes(
        Uri.parse(s.url('/m.json')),
        maxBytes: 10,
      ),
      throwsA(isA<AttachedUpdateHostRejected>()),
    );
  });

  test('fetches manifest and detached signature', () async {
    s.files['/lib/manifest.json'] = [1, 2, 3];
    s.files['/lib/manifest.json.sig'] = [4, 5];
    final result = await fetcher.fetchSignedManifest(
      s.url('/lib/manifest.json'),
    );
    expect(result.manifest, [1, 2, 3]);
    expect(result.signature, [4, 5]);
  });

  test('follows redirects that stay within the policy', () async {
    s.files['/final'] = [9];
    s.redirects['/start'] = '/final';
    expect(
      await fetcher.fetchBytes(Uri.parse(s.url('/start')), maxBytes: 10),
      [9],
    );
  });

  test('redirect to http or to an IP is rejected', () async {
    for (final target in [
      'http://example.org/m.json',
      'https://127.0.0.1/m.json',
      'https://192.168.1.1/m.json',
      'https://localhost/m.json',
    ]) {
      s.redirects['/start'] = target;
      await expectLater(
        fetcher.fetchBytes(Uri.parse(s.url('/start')), maxBytes: 10),
        throwsA(isA<AttachedUpdateHostRejected>()),
        reason: target,
      );
    }
  });

  test('too many redirects, 404 and oversize responses fail', () async {
    s.redirects['/loop'] = '/loop';
    await expectLater(
      fetcher.fetchBytes(Uri.parse(s.url('/loop')), maxBytes: 10),
      throwsA(isA<AttachedUpdateNetworkException>()),
    );
    await expectLater(
      fetcher.fetchBytes(Uri.parse(s.url('/missing')), maxBytes: 10),
      throwsA(
        isA<AttachedUpdateHttpException>().having(
          (e) => e.statusCode,
          'statusCode',
          HttpStatus.notFound,
        ),
      ),
    );
    s.files['/big'] = _data(100, 1);
    await expectLater(
      fetcher.fetchBytes(Uri.parse(s.url('/big')), maxBytes: 99),
      throwsA(isA<AttachedUpdateNetworkException>()),
    );
  });

  test('missing download part retains the HTTP status', () async {
    await expectLater(
      fetcher.downloadParts([
        _part(s, '/missing', [1]),
      ], p.join(temp.path, 'missing')),
      throwsA(
        isA<AttachedUpdateHttpException>().having(
          (e) => e.statusCode,
          'statusCode',
          HttpStatus.notFound,
        ),
      ),
    );
  });

  test('downloads parts in order into one file', () async {
    final a = _data(70000, 1), b = _data(50001, 2);
    s.files['/a'] = a;
    s.files['/b'] = b;
    final target = p.join(temp.path, 'combined');
    var last = 0;
    await fetcher.downloadParts(
      [_part(s, '/a', a), _part(s, '/b', b)],
      target,
      onProgress: (received, total) {
        expect(total, a.length + b.length);
        last = received;
      },
    );
    expect(await File(target).readAsBytes(), [...a, ...b]);
    expect(last, a.length + b.length);
  });

  test('part sha mismatch throws and drops that part only', () async {
    final a = _data(1000, 1), b = _data(1000, 2);
    s.files['/a'] = a;
    s.files['/b'] = b;
    final target = p.join(temp.path, 'combined');
    final badB = AttachedUpdatePart(
      url: s.url('/b'),
      size: b.length,
      sha256: 'f' * 64,
    );
    await expectLater(
      fetcher.downloadParts([_part(s, '/a', a), badB], target),
      throwsA(
        isA<AttachedUpdatePartMismatch>().having((e) => e.partIndex, 'i', 1),
      ),
    );
    expect(await File(target).length(), a.length);
  });

  test('part longer than declared fails', () async {
    s.files['/a'] = _data(1000, 1);
    final declared = AttachedUpdatePart(
      url: s.url('/a'),
      size: 999,
      sha256: 'f' * 64,
    );
    await expectLater(
      fetcher.downloadParts([declared], p.join(temp.path, 'c')),
      throwsA(isA<AttachedUpdateNetworkException>()),
    );
  });

  test('resumes a partial file with a Range request', () async {
    final a = _data(3000, 1), b = _data(4000, 2);
    s.files['/a'] = a;
    s.files['/b'] = b;
    final target = p.join(temp.path, 'combined');
    await File(target).writeAsBytes([...a, ...b.sublist(0, 1500)]);
    await fetcher.downloadParts([_part(s, '/a', a), _part(s, '/b', b)], target);
    expect(await File(target).readAsBytes(), [...a, ...b]);
    expect(s.ranges, ['/b bytes=1500-3999']);
  });

  test('corrupt complete part on disk is downloaded again', () async {
    final a = _data(3000, 1), b = _data(4000, 2);
    s.files['/a'] = a;
    s.files['/b'] = b;
    final target = p.join(temp.path, 'combined');
    await File(target).writeAsBytes([...(_data(3000, 9)), ...b.sublist(0, 10)]);
    await fetcher.downloadParts([_part(s, '/a', a), _part(s, '/b', b)], target);
    expect(await File(target).readAsBytes(), [...a, ...b]);
    expect(s.ranges, isEmpty);
  });

  test('server ignoring Range restarts the part', () async {
    final a = _data(4000, 3);
    s.files['/a'] = a;
    s.honorRange = false;
    final target = p.join(temp.path, 'combined');
    await File(target).writeAsBytes(a.sublist(0, 1000));
    await fetcher.downloadParts([_part(s, '/a', a)], target);
    expect(await File(target).readAsBytes(), a);
  });

  test('stalled response hits the read timeout', () async {
    s.files['/a'] = _data(1000, 1);
    s.stall.add('/a');
    await expectLater(
      fetcher.downloadParts([
        _part(s, '/a', s.files['/a']!),
      ], p.join(temp.path, 'c')),
      throwsA(isA<AttachedUpdateNetworkException>()),
    );
  });

  test('cancellation aborts an in-flight download', () async {
    s.files['/a'] = _data(1000, 1);
    s.stall.add('/a');
    final token = AttachedUpdateCancelToken();
    final slow = AttachedUpdateFetcher(
      policy: AttachedUpdateHostPolicy.allowLoopbackForTesting({s.server.port}),
    );
    final future = slow.downloadParts(
      [_part(s, '/a', s.files['/a']!)],
      p.join(temp.path, 'c'),
      cancel: token,
    );
    Timer(const Duration(milliseconds: 500), token.cancel);
    await expectLater(future, throwsA(isA<AttachedUpdateCancelled>()));
    await expectLater(
      slow.fetchBytes(Uri.parse(s.url('/a')), maxBytes: 1, cancel: token),
      throwsA(isA<AttachedUpdateCancelled>()),
    );
  });

  test('cancellation aborts while waiting for response headers', () async {
    final token = AttachedUpdateCancelToken();
    final slow = AttachedUpdateFetcher(
      policy: AttachedUpdateHostPolicy.allowLoopbackForTesting({s.server.port}),
    );
    Timer(const Duration(milliseconds: 300), token.cancel);
    await expectLater(
      slow.fetchBytes(Uri.parse(s.url('/hang')), maxBytes: 10, cancel: token),
      throwsA(isA<AttachedUpdateCancelled>()),
    );
  });

  test('signature URL keeps the query string', () {
    expect(
      AttachedUpdateFetcher.signatureUriFor(
        Uri.parse('https://h.example/x/m.json?t=1'),
      ).toString(),
      'https://h.example/x/m.json.sig?t=1',
    );
  });
}
