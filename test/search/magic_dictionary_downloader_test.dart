import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/search/magic_dictionary_downloader.dart';

void main() {
  String latestJson({
    String tag = 'v0.3.0',
    bool withAsset = true,
    int assetSize = 57122816,
  }) {
    return jsonEncode({
      'tag_name': tag,
      'assets': [
        {
          'name': 'readme.txt',
          'browser_download_url':
              'https://github.com/Otzaria/SeforimMagicIndexer/releases/download/$tag/readme.txt',
          'size': 12,
        },
        if (withAsset)
          {
            'name': 'lexical.db',
            'browser_download_url':
                'https://github.com/Otzaria/SeforimMagicIndexer/releases/download/$tag/lexical.db',
            'size': assetSize,
          },
      ],
    });
  }

  test('fetchLatestRelease בוחר את נכס lexical.db ומחזיר תג וגודל', () async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        MagicDictionaryDownloader.latestReleaseApi,
      );
      return http.Response(latestJson(), 200);
    });
    final dl = MagicDictionaryDownloader(client: client);
    addTearDown(dl.dispose);

    final release = await dl.fetchLatestRelease();
    expect(release.tag, 'v0.3.0');
    expect(release.downloadUrl.path, endsWith('/lexical.db'));
    expect(release.sizeBytes, 57122816);
  });

  test('fetchLatestRelease זורק כשאין נכס lexical.db', () async {
    final client = MockClient((request) async {
      return http.Response(latestJson(withAsset: false), 200);
    });
    final dl = MagicDictionaryDownloader(client: client);
    addTearDown(dl.dispose);

    expect(dl.fetchLatestRelease(), throwsA(isA<Exception>()));
  });

  test('fetchLatestRelease עוקב אחרי redirect', () async {
    var hop = 0;
    final client = MockClient((request) async {
      if (hop++ == 0) {
        return http.Response(
          '',
          302,
          headers: {
            'location': 'https://cdn.example/redirected-latest',
          },
        );
      }
      return http.Response(latestJson(), 200);
    });
    final dl = MagicDictionaryDownloader(client: client);
    addTearDown(dl.dispose);

    final release = await dl.fetchLatestRelease();
    expect(release.tag, 'v0.3.0');
    expect(hop, 2); // ניגש פעמיים: המקור ואז יעד ה-redirect.
  });

  test('fetchLatestRelease זורק על קוד סטטוס שאינו 2xx', () async {
    final client = MockClient(
      (request) async => http.Response('rate limited', 403),
    );
    final dl = MagicDictionaryDownloader(client: client);
    addTearDown(dl.dispose);

    expect(dl.fetchLatestRelease(), throwsA(isA<Exception>()));
  });

  test('גוף lexical.db קצר מגודל ה-asset נדחה ולא נכתב marker', () async {
    final temp = await Directory.systemTemp.createTemp('magic-dict-short-');
    addTearDown(() => temp.delete(recursive: true));
    final dest = '${temp.path}/lexical.db';
    final client = MockClient((request) async {
      if (request.url.toString() ==
          MagicDictionaryDownloader.latestReleaseApi) {
        return http.Response(latestJson(assetSize: 10), 200);
      }
      if (request.url.path.endsWith('/lexical.db')) {
        return http.Response.bytes(List.filled(5, 1), 200);
      }
      return http.Response('not found', 404);
    });
    final dl = MagicDictionaryDownloader(
      client: client,
      destinationProvider: () async => dest,
    );
    addTearDown(dl.dispose);

    expect(await dl.ensureLatest(), isFalse);
    expect(File(dest).existsSync(), isFalse);
    expect(File('$dest.part').existsSync(), isFalse);
    expect(File('$dest.version').existsSync(), isFalse);
  });
}
