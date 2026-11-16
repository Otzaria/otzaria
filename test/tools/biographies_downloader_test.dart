import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/tools/biographies/data/author_biography_links.dart';
import 'package:otzaria/tools/biographies/data/biographies_downloader.dart';

void main() {
  late Directory tempDir;
  late String dest;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bio_dl_test_');
    dest = '${tempDir.path}${Platform.pathSeparator}biographies-app.json.gz';
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  final releaseJson = jsonEncode({
    'tag_name': 'bio-1',
    'assets': [
      {'browser_download_url': 'https://example.com/a/biographies-app.json.gz'},
    ],
  });

  BiographiesDownloader downloader(
    Stream<List<int>> Function() assetBody,
  ) => BiographiesDownloader(
    destinationProvider: () async => dest,
    client: MockClient.streaming((request, _) async {
      final url = request.url.toString();
      if (url == BiographiesDownloader.latestReleaseApi) {
        return http.StreamedResponse(
          Stream.value(utf8.encode(releaseJson)),
          200,
        );
      }
      if (url == 'https://example.com/a/biographies-app.json.gz') {
        return http.StreamedResponse(
          const Stream.empty(),
          302,
          headers: {
            'location': 'https://cdn.example.com/biographies-app.json.gz',
          },
        );
      }
      return http.StreamedResponse(assetBody(), 200);
    }),
  );

  test('refreshes author links and preserves them on an invalid response', () async {
    final mapping = jsonEncode({
      'version': 1,
      'authors': {'רש״י': 'Q26456'},
    });
    var body = mapping;
    final client = MockClient((request) async {
      expect(request.url.toString(), AuthorBiographyLinks.downloadUrl);
      return http.Response.bytes(utf8.encode(body), 200);
    });
    addTearDown(client.close);
    final downloader = BiographiesDownloader(
      destinationProvider: () async => dest,
      client: client,
    );
    addTearDown(downloader.dispose);
    final linksFile = File(
      '${tempDir.path}${Platform.pathSeparator}${AuthorBiographyLinks.fileName}',
    );

    await downloader.refreshAuthorLinks();
    expect(await linksFile.readAsString(), mapping);
    body = '{"version":2,"authors":{}}';
    await expectLater(downloader.refreshAuthorLinks(), throwsFormatException);
    expect(await linksFile.readAsString(), mapping);
  });

  test('follows the redirect and installs the streamed file', () async {
    final ok = await downloader(
      () => Stream.fromIterable([
        [1, 2],
        [3],
      ]),
    ).ensureLatest();

    expect(ok, isTrue);
    expect(await File(dest).readAsBytes(), [1, 2, 3]);
    expect(await File('$dest.version').readAsString(), 'bio-1');
    expect(await File('$dest.part').exists(), isFalse);
  });

  test('removes the Ta Shma file of earlier versions once installed', () async {
    final legacy = File(
      '${tempDir.path}${Platform.pathSeparator}biographies.tsb',
    );
    await legacy.writeAsBytes([9]);
    await File('${legacy.path}.version').writeAsString('bio-0');

    final ok = await downloader(() => Stream.value([1])).ensureLatest();

    expect(ok, isTrue);
    expect(await legacy.exists(), isFalse);
    expect(await File('${legacy.path}.version').exists(), isFalse);
  });

  test('a body that fails midway leaves no .part and no file', () async {
    Stream<List<int>> broken() async* {
      yield [1, 2];
      throw const SocketException('reset');
    }

    final ok = await downloader(broken).ensureLatest();

    expect(ok, isFalse);
    expect(await File(dest).exists(), isFalse);
    expect(await File('$dest.part').exists(), isFalse);
  });
}
