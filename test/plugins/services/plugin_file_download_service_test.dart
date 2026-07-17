import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/plugins/services/plugin_file_download_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_dl_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<bool> allowAll(Uri _) async => true;

  PluginFileDownloadService serviceReturning(
    List<int> body, {
    int status = 200,
  }) {
    final client = MockClient((request) async {
      return http.Response.bytes(body, status);
    });
    return PluginFileDownloadService(client: client);
  }

  test('מוריד קובץ לתיקיית היעד ומחזיר נתיב ושם', () async {
    final service = serviceReturning([1, 2, 3, 4]);
    final result = await service.downloadToDownloads(
      Uri.parse('https://github.com/Owner/Repo/releases/latest/download/a.zip'),
      isAllowed: allowAll,
      targetDir: tempDir,
    );

    expect(result.filename, 'a.zip');
    expect(p.basename(result.path), 'a.zip');
    final file = File(result.path);
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
  });

  test('שם הקובץ נגזר מה-URL כשלא סופק filename', () async {
    final service = serviceReturning([9]);
    final result = await service.downloadToDownloads(
      Uri.parse('https://github.com/Owner/Repo/releases/latest/download/x.zip'),
      isAllowed: allowAll,
      targetDir: tempDir,
    );
    expect(result.filename, 'x.zip');
  });

  test('filename מפורש גובר על שם ה-URL', () async {
    final service = serviceReturning([9]);
    final result = await service.downloadToDownloads(
      Uri.parse('https://github.com/Owner/Repo/releases/latest/download/x.zip'),
      isAllowed: allowAll,
      filename: 'custom.zip',
      targetDir: tempDir,
    );
    expect(result.filename, 'custom.zip');
  });

  test('אינו דורס קובץ קיים — מוסיף סיומת מספרית', () async {
    await File(p.join(tempDir.path, 'a.zip')).writeAsBytes([0]);
    final service = serviceReturning([1, 2]);
    final result = await service.downloadToDownloads(
      Uri.parse('https://github.com/Owner/Repo/releases/latest/download/a.zip'),
      isAllowed: allowAll,
      targetDir: tempDir,
    );
    expect(result.filename, 'a (1).zip');
    expect(await File(p.join(tempDir.path, 'a.zip')).readAsBytes(), [0]);
  });

  test('שם קובץ עם תווי נתיב מנוקה למניעת path traversal', () async {
    final service = serviceReturning([7]);
    final result = await service.downloadToDownloads(
      Uri.parse('https://github.com/Owner/Repo/releases/latest/download/a.zip'),
      isAllowed: allowAll,
      filename: '../../evil.zip',
      targetDir: tempDir,
    );
    // basename בלבד — בלי רכיבי ../
    expect(result.filename, 'evil.zip');
    expect(p.dirname(result.path), tempDir.path);
  });

  test('זורק שגיאה בקוד סטטוס שאינו 2xx', () async {
    final service = serviceReturning([], status: 404);
    expect(
      () => service.downloadToDownloads(
        Uri.parse(
            'https://github.com/Owner/Repo/releases/latest/download/a.zip'),
        isAllowed: allowAll,
        targetDir: tempDir,
      ),
      throwsA(isA<Exception>()),
    );
  });

  // isAllowed המדמה את הרשימה הגלובלית: רק github.com מורשה ישירות (ה-CDN
  // אינו ברשימה הגלובלית בכוונה).
  Future<bool> globalAllowsGithubOnly(Uri uri) async =>
      uri.host == 'github.com';

  // isRedirectAllowed המדמה את isGithubReleaseRedirectAllowed: מתיר redirect
  // ל-CDN רק כש-hop הקודם הוא github.com.
  bool redirectAllowsCdnFromGithub(Uri previous, Uri target) =>
      target.host == 'release-assets.githubusercontent.com' &&
      (previous.host == 'github.com' ||
          previous.host == 'release-assets.githubusercontent.com');

  test('עוקב אחרי redirect ל-CDN מותר (רק כיעד redirect) ומוריד', () async {
    const cdn =
        'https://release-assets.githubusercontent.com/abc/a.zip?token=x';
    final client = MockClient((request) async {
      if (request.url.host == 'github.com') {
        return http.Response('', 302, headers: {'location': cdn});
      }
      return http.Response.bytes([5, 6, 7], 200);
    });
    final service = PluginFileDownloadService(client: client);

    final result = await service.downloadToDownloads(
      Uri.parse('https://github.com/Owner/Repo/releases/latest/download/a.zip'),
      isAllowed: globalAllowsGithubOnly,
      isRedirectAllowed: redirectAllowsCdnFromGithub,
      targetDir: tempDir,
    );

    expect(await File(result.path).readAsBytes(), [5, 6, 7]);
    // שם הקובץ נגזר מה-URL ההתחלתי, לא מיעד ה-CDN.
    expect(result.filename, 'a.zip');
  });

  test('חוסם redirect ליעד שאינו ב-allowlist (לא עוקף את ה-allowlist)',
      () async {
    var hitEvil = false;
    final client = MockClient((request) async {
      if (request.url.host == 'github.com') {
        return http.Response('', 302,
            headers: {'location': 'https://evil.example.com/a.zip'});
      }
      hitEvil = true;
      return http.Response.bytes([0], 200);
    });
    final service = PluginFileDownloadService(client: client);

    await expectLater(
      service.downloadToDownloads(
        Uri.parse(
            'https://github.com/Owner/Repo/releases/latest/download/a.zip'),
        isAllowed: globalAllowsGithubOnly,
        isRedirectAllowed: redirectAllowsCdnFromGithub,
        targetDir: tempDir,
      ),
      throwsA(isA<Exception>()),
    );
    // ודא שהבקשה ליעד האסור מעולם לא יצאה.
    expect(hitEvil, isFalse);
  });

  test('חוסם גישה ישירה ל-CDN ככתובת התחלתית (ללא redirect)', () async {
    var hit = false;
    final client = MockClient((request) async {
      hit = true;
      return http.Response.bytes([0], 200);
    });
    final service = PluginFileDownloadService(client: client);

    await expectLater(
      service.downloadToDownloads(
        Uri.parse('https://release-assets.githubusercontent.com/abc/a.zip'),
        isAllowed: globalAllowsGithubOnly,
        isRedirectAllowed: redirectAllowsCdnFromGithub,
        targetDir: tempDir,
      ),
      throwsA(isA<Exception>()),
    );
    // ה-CDN אינו נגיש ישירות — isRedirectAllowed חל רק על יעדי redirect.
    expect(hit, isFalse);
  });

  group('downloadToPath', () {
    test('שומר את הקובץ בנתיב המלא ויוצר את תיקיית האב', () async {
      final service = serviceReturning([1, 2, 3]);
      final destPath = p.join(tempDir.path, 'nested', 'deep', 'books.zip');

      final result = await service.downloadToPath(
        Uri.parse(
            'https://github.com/Owner/Repo/releases/latest/download/books.zip'),
        destPath,
        isAllowed: allowAll,
      );

      expect(result.path, destPath);
      expect(result.filename, 'books.zip');
      expect(await File(destPath).readAsBytes(), [1, 2, 3]);
    });

    test('דורס קובץ קיים באותו נתיב', () async {
      final destPath = p.join(tempDir.path, 'books.zip');
      await File(destPath).writeAsBytes([9, 9, 9]);
      final service = serviceReturning([4, 5]);

      await service.downloadToPath(
        Uri.parse(
            'https://github.com/Owner/Repo/releases/latest/download/books.zip'),
        destPath,
        isAllowed: allowAll,
      );

      expect(await File(destPath).readAsBytes(), [4, 5]);
    });

    test('זורק בקוד סטטוס שאינו 2xx', () async {
      final service = serviceReturning([], status: 404);
      await expectLater(
        service.downloadToPath(
          Uri.parse(
              'https://github.com/Owner/Repo/releases/latest/download/a.zip'),
          p.join(tempDir.path, 'a.zip'),
          isAllowed: allowAll,
        ),
        throwsA(isA<Exception>()),
      );
    });

    group('resume', () {
      test('מצרף ל-206 כשה-offset תואם (Content-Range) ושולח Range נכון',
          () async {
        final destPath = p.join(tempDir.path, 'big.zip');
        await File(destPath).writeAsBytes([1, 2, 3]);
        String? sentRange;
        final client = MockClient((request) async {
          sentRange = request.headers['range'];
          return http.Response.bytes([4, 5], 206,
              headers: {'content-range': 'bytes 3-4/5'});
        });
        final service = PluginFileDownloadService(client: client);

        final result = await service.downloadToPath(
          Uri.parse(
              'https://github.com/Owner/Repo/releases/latest/download/big.zip'),
          destPath,
          isAllowed: allowAll,
          resume: true,
        );

        expect(sentRange, 'bytes=3-');
        expect(result.path, destPath);
        expect(await File(destPath).readAsBytes(), [1, 2, 3, 4, 5]);
      });

      test('416 על קובץ שכבר הושלם → הצלחה, הקובץ נשמר כמות שהוא', () async {
        final destPath = p.join(tempDir.path, 'done.zip');
        await File(destPath).writeAsBytes([1, 2, 3, 4, 5]);
        final client = MockClient((request) async {
          return http.Response.bytes([], 416,
              headers: {'content-range': 'bytes */5'});
        });
        final service = PluginFileDownloadService(client: client);

        final result = await service.downloadToPath(
          Uri.parse(
              'https://github.com/Owner/Repo/releases/latest/download/done.zip'),
          destPath,
          isAllowed: allowAll,
          resume: true,
        );

        expect(result.path, destPath);
        expect(await File(destPath).readAsBytes(), [1, 2, 3, 4, 5]);
      });

      test('200 (השרת מתעלם מ-Range) → כתיבה מחדש מ-0', () async {
        final destPath = p.join(tempDir.path, 'restart.zip');
        await File(destPath).writeAsBytes([9, 9]);
        final client = MockClient((request) async {
          return http.Response.bytes([1, 2, 3], 200);
        });
        final service = PluginFileDownloadService(client: client);

        await service.downloadToPath(
          Uri.parse(
              'https://github.com/Owner/Repo/releases/latest/download/restart.zip'),
          destPath,
          isAllowed: allowAll,
          resume: true,
        );

        expect(await File(destPath).readAsBytes(), [1, 2, 3]);
      });

      test('206 עם offset לא תואם → זריקה ומחיקת הקובץ החלקי', () async {
        final destPath = p.join(tempDir.path, 'bad.zip');
        await File(destPath).writeAsBytes([1, 2, 3]);
        final client = MockClient((request) async {
          // ביקשנו bytes=3- אך השרת מתחיל מ-1 (לא 3 ולא 0) — צירוף היה מקלקל.
          return http.Response.bytes([2, 3, 4, 5], 206,
              headers: {'content-range': 'bytes 1-4/5'});
        });
        final service = PluginFileDownloadService(client: client);

        await expectLater(
          service.downloadToPath(
            Uri.parse(
                'https://github.com/Owner/Repo/releases/latest/download/bad.zip'),
            destPath,
            isAllowed: allowAll,
            resume: true,
          ),
          throwsA(isA<Exception>()),
        );
        expect(await File(destPath).exists(), isFalse);
      });

      test('206 שנקטע לפני הסוף → זריקה, הקובץ החלקי נשמר להמשך', () async {
        final destPath = p.join(tempDir.path, 'partial.zip');
        await File(destPath).writeAsBytes([1, 2, 3]);
        final client = MockClient((request) async {
          // total=10 אך הגוף מכיל רק 2 בייטים → 5 מתוך 10 בסיום.
          return http.Response.bytes([4, 5], 206,
              headers: {'content-range': 'bytes 3-9/10'});
        });
        final service = PluginFileDownloadService(client: client);

        await expectLater(
          service.downloadToPath(
            Uri.parse(
                'https://github.com/Owner/Repo/releases/latest/download/partial.zip'),
            destPath,
            isAllowed: allowAll,
            resume: true,
          ),
          throwsA(isA<Exception>()),
        );
        // הקובץ נשמר עם מה שהתקבל, לניסיון resume נוסף.
        expect(await File(destPath).readAsBytes(), [1, 2, 3, 4, 5]);
      });

      test('resume ללא קובץ קיים → הורדה רגילה מ-0 ללא כותרת Range', () async {
        final destPath = p.join(tempDir.path, 'fresh.zip');
        String? sentRange = 'unset';
        final client = MockClient((request) async {
          sentRange = request.headers['range'];
          return http.Response.bytes([1, 2, 3], 200);
        });
        final service = PluginFileDownloadService(client: client);

        await service.downloadToPath(
          Uri.parse(
              'https://github.com/Owner/Repo/releases/latest/download/fresh.zip'),
          destPath,
          isAllowed: allowAll,
          resume: true,
        );

        expect(sentRange, isNull);
        expect(await File(destPath).readAsBytes(), [1, 2, 3]);
      });
    });
  });

  test('זורק TimeoutException כשהזרם נתקע (אין בייטים בחלון התקיעה)', () async {
    // זרם שמתעכב מעבר לחלון התקיעה לפני הבייט הראשון — מדמה חיבור מת.
    final client = MockClient.streaming((request, bodyStream) async {
      Stream<List<int>> stalled() async* {
        await Future.delayed(const Duration(seconds: 1));
        yield [1];
      }

      return http.StreamedResponse(stalled(), 200);
    });
    final service = PluginFileDownloadService(
      client: client,
      stallTimeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      service.downloadToDownloads(
        Uri.parse(
            'https://github.com/Owner/Repo/releases/latest/download/a.zip'),
        isAllowed: allowAll,
        targetDir: tempDir,
      ),
      throwsA(isA<TimeoutException>()),
    );
    // הקובץ החלקי נמחק בכישלון — אין שאריות בתיקיית היעד.
    expect(tempDir.listSync(), isEmpty);
  });

  test('זורק TimeoutException כשגוף תשובת ה-redirect נתקע ב-drain', () async {
    // 302 שגופו לא נסגר — לפני התיקון ה-drain היה נתקע לנצח (download מוחרג
    // מה-timeout הכללי של ה-RPC).
    final client = MockClient.streaming((request, bodyStream) async {
      Stream<List<int>> neverEnds() async* {
        await Future.delayed(const Duration(seconds: 1));
        yield [0];
      }

      return http.StreamedResponse(
        neverEnds(),
        302,
        headers: {'location': 'https://github.com/Owner/Repo/final/a.zip'},
      );
    });
    final service = PluginFileDownloadService(
      client: client,
      stallTimeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      service.downloadToDownloads(
        Uri.parse(
            'https://github.com/Owner/Repo/releases/latest/download/a.zip'),
        isAllowed: allowAll,
        targetDir: tempDir,
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('dispose מסיר את ה-closer מ-HttpClientRegistry', () async {
    final service = serviceReturning([1]);
    final before = HttpClientRegistry.registeredCount;
    service.dispose();
    expect(HttpClientRegistry.registeredCount, before - 1);
  });
}
