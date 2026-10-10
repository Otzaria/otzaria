import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/search/magic_dictionary_downloader.dart';
import 'package:path/path.dart' as p;

void main() {
  String latestJson({
    String tag = 'v0.3.0',
    bool withAsset = true,
    int assetSize = 57122816,
    String? digest,
    String? v2Digest,
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
            'digest': ?digest,
          },
        if (v2Digest != null)
          {
            'name': 'lexical-v2.db',
            'browser_download_url':
                'https://github.com/Otzaria/SeforimMagicIndexer/releases/download/$tag/lexical-v2.db',
            'size': assetSize,
            'digest': v2Digest,
          },
      ],
    });
  }

  test('fetchLatestRelease בלי lexical-v2.db נופל ל-lexical.db', () async {
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
    expect(release.sha256, isNull);
  });

  test('fetchLatestRelease מפענח את ה-digest של הנכס', () async {
    const sha =
        'b42e36626802629fed178068e8cf11f0f034d6f24ae3b72ac9999b9311bf29'
        '9f';
    final client = MockClient(
      (request) async => http.Response(latestJson(digest: 'sha256:$sha'), 200),
    );
    final dl = MagicDictionaryDownloader(client: client);
    addTearDown(dl.dispose);

    expect((await dl.fetchLatestRelease()).sha256, sha);
  });

  test('fetchLatestRelease מעדיף את lexical-v2.db על פני lexical.db', () async {
    final v2 = sha256.convert([2]).toString();
    final client = MockClient(
      (request) async => http.Response(
        latestJson(
          digest: 'sha256:${sha256.convert([1])}',
          v2Digest: 'sha256:$v2',
        ),
        200,
      ),
    );
    final dl = MagicDictionaryDownloader(client: client);
    addTearDown(dl.dispose);

    final release = await dl.fetchLatestRelease();
    expect(release.downloadUrl.path, endsWith('/lexical-v2.db'));
    expect(release.sha256, v2);
  });

  group('ensureLatest עם סימון גרסה קיים', () {
    // ה-digest ב-release תואם את תוכן הקובץ שנכתב ב-setUp.
    final sha = sha256.convert([1, 2, 3]).toString();
    late Directory temp;
    late String dest;
    var downloadRequests = 0;
    late MagicDictionaryDownloader dl;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('magic-dict-marker-');
      dest = p.join(temp.path, 'lexical.db');
      await File(dest).writeAsBytes([1, 2, 3]);
      downloadRequests = 0;
      final client = MockClient((request) async {
        if (request.url.toString() ==
            MagicDictionaryDownloader.latestReleaseApi) {
          return http.Response(latestJson(digest: 'sha256:$sha'), 200);
        }
        downloadRequests++;
        return http.Response('not found', 404);
      });
      dl = MagicDictionaryDownloader(
        client: client,
        destinationProvider: () async => dest,
      );
    });

    tearDown(() async {
      dl.dispose();
      await temp.delete(recursive: true);
    });

    test('סימון digest של מתקין FULL נחשב עדכני — בלי הורדה', () async {
      await File('$dest.version').writeAsString(sha);

      expect(await dl.ensureLatest(), isTrue);
      expect(downloadRequests, 0);
    });

    test('סימון תג ישן נחשב עדכני ומרוענן ל-digest בלי הורדה', () async {
      await File('$dest.version').writeAsString('v0.3.0');

      expect(await dl.ensureLatest(), isTrue);
      expect(downloadRequests, 0);
      expect(await File('$dest.version').readAsString(), sha);
    });

    test('סימון תג עם קובץ שאינו תואם את ה-digest גורר הורדה', () async {
      await File(dest).writeAsBytes([9, 9, 9]);
      await File('$dest.version').writeAsString('v0.3.0');

      await dl.ensureLatest();
      expect(downloadRequests, greaterThan(0));
      // הסימון לא הומר ל-digest — הקובץ המקומי סוטה מהנכס.
      expect(await File('$dest.version').readAsString(), 'v0.3.0');
    });

    test('סימון שאינו תואם תג או digest גורר הורדה', () async {
      await File('$dest.version').writeAsString('v0.2.0');

      await dl.ensureLatest();
      expect(downloadRequests, greaterThan(0));
    });
  });

  test('אחרי הורדה מוצלחת הסימון הוא ה-digest של הנכס', () async {
    final temp = await Directory.systemTemp.createTemp('magic-dict-dl-');
    addTearDown(() => temp.delete(recursive: true));
    final dest = p.join(temp.path, 'lexical.db');
    final body = List.filled(8, 7);
    final sha = sha256.convert(body).toString();
    final client = MockClient((request) async {
      if (request.url.toString() ==
          MagicDictionaryDownloader.latestReleaseApi) {
        return http.Response(
          latestJson(assetSize: body.length, digest: 'sha256:$sha'),
          200,
        );
      }
      return http.Response.bytes(body, 200);
    });
    final dl = MagicDictionaryDownloader(
      client: client,
      destinationProvider: () async => dest,
    );
    addTearDown(dl.dispose);

    expect(await dl.ensureLatest(), isTrue);
    expect(await File(dest).readAsBytes(), body);
    expect(await File('$dest.version').readAsString(), sha);
  });

  test('גוף בגודל הנכון עם sha256 שגוי נדחה ולא נכתב marker', () async {
    final temp = await Directory.systemTemp.createTemp('magic-dict-hash-');
    addTearDown(() => temp.delete(recursive: true));
    final dest = p.join(temp.path, 'lexical.db');
    final body = List.filled(8, 7);
    final wrongSha = sha256.convert(List.filled(8, 8)).toString();
    final client = MockClient((request) async {
      if (request.url.toString() ==
          MagicDictionaryDownloader.latestReleaseApi) {
        return http.Response(
          latestJson(assetSize: body.length, digest: 'sha256:$wrongSha'),
          200,
        );
      }
      return http.Response.bytes(body, 200);
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
          headers: {'location': 'https://cdn.example/redirected-latest'},
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

  test('writeVersionMarker כותב את התג לקובץ <dest>.version', () async {
    final dir = await Directory.systemTemp.createTemp('magic_dict_test');
    addTearDown(() => dir.delete(recursive: true));
    final dest = p.join(dir.path, 'lexical.db');

    await MagicDictionaryDownloader.writeVersionMarker(dest, 'v0.3.0');

    expect(await File('$dest.version').readAsString(), 'v0.3.0');
  });

  group('replaceDownloadedFile כשהיעד נעול (Windows)', () {
    late Directory dir;
    late String dest;
    late File source;
    late RandomAccessFile lockHandle;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('magic_dict_lock_test');
      dest = p.join(dir.path, 'lexical.db');
      source = File('$dest.part');
      // handle פתוח חוסם rename של הקובץ ב-Windows — כמו המנוע באפליקציה.
      await File(dest).writeAsBytes([1, 2, 3]);
      lockHandle = await File(dest).open();
    });

    tearDown(() async {
      await lockHandle.close();
      await dir.delete(recursive: true);
    });

    test('תוכן זהה — נחשב הצלחה וקובץ ה-part נמחק', () async {
      await source.writeAsBytes([1, 2, 3]);

      await MagicDictionaryDownloader.replaceDownloadedFile(source, dest);

      expect(await source.exists(), isFalse);
      expect(await File(dest).readAsBytes(), [1, 2, 3]);
    });

    test('תוכן שונה — החריגה מועברת הלאה', () async {
      await source.writeAsBytes([9, 9, 9]);

      expect(
        () => MagicDictionaryDownloader.replaceDownloadedFile(source, dest),
        throwsA(isA<FileSystemException>()),
      );
    });
  }, skip: !Platform.isWindows);

  group('החלפת מילון שהמנוע מחזיק', () {
    final oldBody = [1, 1, 1, 1];
    final newBody = [2, 2, 2, 2, 2, 2, 2, 2];
    final newSha = sha256.convert(newBody).toString();
    late Directory temp;
    late String dest;
    late int downloads;
    late MockClient client;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('magic-dict-swap-');
      dest = p.join(temp.path, 'lexical.db');
      await File(dest).writeAsBytes(oldBody);
      await File('$dest.version').writeAsString('old-digest');
      downloads = 0;
      client = MockClient((request) async {
        if (request.url.toString() ==
            MagicDictionaryDownloader.latestReleaseApi) {
          return http.Response(
            latestJson(
              tag: 'v0.3.1',
              assetSize: newBody.length,
              digest: 'sha256:${sha256.convert(oldBody)}',
              v2Digest: 'sha256:$newSha',
            ),
            200,
          );
        }
        expect(request.url.path, endsWith('/lexical-v2.db'));
        downloads++;
        return http.Response.bytes(newBody, 200);
      });
    });

    tearDown(() => temp.delete(recursive: true));

    MagicDictionaryDownloader downloader({
      Future<void> Function(Future<void> Function() replace)? aroundReplace,
    }) {
      final dl = MagicDictionaryDownloader(
        client: client,
        destinationProvider: () async => dest,
        aroundReplace: aroundReplace,
      );
      addTearDown(dl.dispose);
      return dl;
    }

    test('ההחלפה רצה בתוך ה-hook, והסימון הוא digest הנכס המותקן', () async {
      final events = <String>[];
      final dl = downloader(
        aroundReplace: (replace) async {
          events.add('detach');
          expect(await File(dest).readAsBytes(), oldBody);
          await replace();
          expect(await File(dest).readAsBytes(), newBody);
          events.add('attach');
        },
      );

      expect(await dl.ensureLatest(), isTrue);
      expect(events, ['detach', 'attach']);
      expect(await File('$dest.version').readAsString(), newSha);
      expect(File('$dest.next').existsSync(), isFalse);
      expect(File('$dest.next.version').existsSync(), isFalse);
    });

    test('החלפה שנכשלה משאירה עותק ממתין ואינה מורידה שוב', () async {
      final failing = downloader(
        aroundReplace: (_) async =>
            throw const FileSystemException('locked by engine'),
      );

      expect(await failing.ensureLatest(), isTrue, reason: 'הישן שמיש');
      expect(await File(dest).readAsBytes(), oldBody);
      expect(await File('$dest.version').readAsString(), 'old-digest');
      expect(await File('$dest.next').readAsBytes(), newBody);
      expect(await File('$dest.next.version').readAsString(), newSha);

      // בדיקה חוזרת שנכשלת שוב — עדיין בלי הורדה.
      await failing.ensureLatest();
      expect(downloads, 1);

      expect(await downloader().ensureLatest(), isTrue);
      expect(downloads, 1);
      expect(await File(dest).readAsBytes(), newBody);
      expect(await File('$dest.version').readAsString(), newSha);
      expect(File('$dest.next').existsSync(), isFalse);
    });

    test('עותק ממתין של גרסה אחרת מוחלף בהורדה', () async {
      await File('$dest.next').writeAsBytes(newBody);
      await File('$dest.next.version').writeAsString('other-digest');

      expect(await downloader().ensureLatest(), isTrue);
      expect(downloads, 1);
      expect(await File('$dest.version').readAsString(), newSha);
    });

    test('מילון שכבר עדכני מבטל עותק ממתין ישן לפני פתיחה ללא רשת', () async {
      await File(dest).writeAsBytes(newBody);
      await File('$dest.version').writeAsString(newSha);
      await File('$dest.next').writeAsBytes(oldBody);
      await File('$dest.next.version').writeAsString('old-digest');

      expect(await downloader().ensureLatest(), isTrue);
      expect(downloads, 0);
      await MagicDictionaryDownloader.installStagedBeforeAttach(dest);

      expect(await File(dest).readAsBytes(), newBody);
      expect(await File('$dest.version').readAsString(), newSha);
      expect(File('$dest.next').existsSync(), isFalse);
      expect(File('$dest.next.version').existsSync(), isFalse);
    });

    for (final useFileDigest in [false, true]) {
      test(
        'התקנה חדשה מבטלת עותק ממתין גם ללא בדיקת רשת ($useFileDigest)',
        () async {
          await File('$dest.next').writeAsBytes(oldBody);
          await File('$dest.next.version').writeAsString('old-digest');
          await File(dest).writeAsBytes(newBody);
          if (useFileDigest) {
            await MagicDictionaryDownloader.writeFileDigestMarker(dest);
          } else {
            await MagicDictionaryDownloader.writeVersionMarker(dest, newSha);
          }

          await MagicDictionaryDownloader.installStagedBeforeAttach(dest);

          expect(downloads, 0);
          expect(await File(dest).readAsBytes(), newBody);
          expect(await File('$dest.version').readAsString(), newSha);
          expect(File('$dest.next').existsSync(), isFalse);
          expect(File('$dest.next.version').existsSync(), isFalse);
        },
      );
    }

    test('installStagedBeforeAttach מתקין עותק ממתין בלי רשת', () async {
      await File('$dest.next').writeAsBytes(newBody);
      await File('$dest.next.version').writeAsString(newSha);

      await MagicDictionaryDownloader.installStagedBeforeAttach(dest);

      expect(await File(dest).readAsBytes(), newBody);
      expect(await File('$dest.version').readAsString(), newSha);
      expect(File('$dest.next').existsSync(), isFalse);
      expect(File('$dest.next.version').existsSync(), isFalse);
    });

    test(
      'installStagedBeforeAttach בלי סימון לעותק אינו נוגע במילון',
      () async {
        await File('$dest.next').writeAsBytes(newBody);

        await MagicDictionaryDownloader.installStagedBeforeAttach(dest);

        expect(await File(dest).readAsBytes(), oldBody);
        expect(await File('$dest.version').readAsString(), 'old-digest');
      },
    );

    test('קובץ נעול: מורידים פעם אחת, ומתקינים בפתיחה הבאה', () async {
      // handle פתוח חוסם rename ב-Windows — כמו מנוע שעוד מחזיק את המילון.
      final lock = await File(dest).open();
      try {
        expect(await downloader().ensureLatest(), isTrue);
        expect(await downloader().ensureLatest(), isTrue);
        expect(downloads, 1);
        expect(await File('$dest.version').readAsString(), 'old-digest');
        await MagicDictionaryDownloader.installStagedBeforeAttach(dest);
        expect(await File('$dest.version').readAsString(), 'old-digest');
      } finally {
        await lock.close();
      }

      await MagicDictionaryDownloader.installStagedBeforeAttach(dest);
      expect(await File(dest).readAsBytes(), newBody);
      expect(await File('$dest.version').readAsString(), newSha);
    }, skip: !Platform.isWindows);
  });
}
