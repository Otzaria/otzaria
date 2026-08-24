import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';

void main() {
  late Directory tempDir;
  late PluginFileServer server;
  late HttpClient client;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_file_server_test');
    server = PluginFileServer();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> writeFile(String name, String content) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsString(content);
    return file;
  }

  Future<HttpClientResponse> get(String url, {String? range}) async {
    final request = await client.getUrl(Uri.parse(url));
    if (range != null) request.headers.set('range', range);
    return request.close();
  }

  test('מגיש קובץ מלא עם 200 ו-Content-Type נכון', () async {
    final file = await writeFile('doc.txt', 'hello world');
    final reg = await server.register(
      pluginId: 'p1',
      canonicalPath: file.path,
    );

    final response = await get(reg.url);
    expect(response.statusCode, 200);
    expect(response.headers.value('accept-ranges'), 'bytes');
    expect(response.headers.contentType?.mimeType, 'text/plain');
    expect(await response.transform(utf8.decoder).join(), 'hello world');
  });

  test('Range מחזיר 206 עם המקטע ו-Content-Range', () async {
    final file = await writeFile('doc.txt', '0123456789');
    final reg = await server.register(pluginId: 'p1', canonicalPath: file.path);

    final response = await get(reg.url, range: 'bytes=2-5');
    expect(response.statusCode, 206);
    expect(response.headers.value('content-range'), 'bytes 2-5/10');
    expect(response.headers.contentLength, 4);
    expect(await response.transform(utf8.decoder).join(), '2345');
  });

  test('Range עם suffix מחזיר את הבייטים האחרונים', () async {
    final file = await writeFile('doc.txt', '0123456789');
    final reg = await server.register(pluginId: 'p1', canonicalPath: file.path);

    final response = await get(reg.url, range: 'bytes=-3');
    expect(response.statusCode, 206);
    expect(response.headers.value('content-range'), 'bytes 7-9/10');
    expect(await response.transform(utf8.decoder).join(), '789');
  });

  test('Range מחוץ לתחום מחזיר 416', () async {
    final file = await writeFile('doc.txt', '0123456789');
    final reg = await server.register(pluginId: 'p1', canonicalPath: file.path);

    final response = await get(reg.url, range: 'bytes=50-60');
    expect(response.statusCode, 416);
    expect(response.headers.value('content-range'), 'bytes */10');
    await response.drain();
  });

  test('token לא מוכר מחזיר 404', () async {
    await server.register(pluginId: 'p1', canonicalPath: '/nonexistent');
    final origin = server.origin!;
    final response = await get('$origin/f/p1/deadbeef');
    expect(response.statusCode, 404);
    await response.drain();
  });

  test('ה-URL כולל את מזהה התוסף', () async {
    final file = await writeFile('doc.txt', 'x');
    final reg = await server.register(pluginId: 'p1', canonicalPath: file.path);
    expect(reg.url, '${server.origin}/f/p1/${reg.token}');
    await (await get(reg.url)).drain();
  });

  test('token של תוסף אחר בנתיב מחזיר 404', () async {
    final file = await writeFile('doc.txt', 'secret');
    final reg = await server.register(pluginId: 'pA', canonicalPath: file.path);

    final response = await get('${server.origin}/f/pB/${reg.token}');
    expect(response.statusCode, 404);
    await response.drain();
  });

  test('URL בפורמט הישן /f/<token> עדיין מוגש (תאימות לגרסה אחת)', () async {
    final file = await writeFile('doc.txt', 'legacy');
    final reg = await server.register(pluginId: 'p1', canonicalPath: file.path);

    final response = await get('${server.origin}/f/${reg.token}');
    expect(response.statusCode, 200);
    expect(await response.transform(utf8.decoder).join(), 'legacy');
  });

  test('נתיב עם מספר סגמנטים חריג מחזיר 404', () async {
    final file = await writeFile('doc.txt', 'x');
    final reg = await server.register(pluginId: 'p1', canonicalPath: file.path);

    final response = await get('${server.origin}/f/p1/extra/${reg.token}');
    expect(response.statusCode, 404);
    await response.drain();
  });

  group('isUriForPlugin — אכיפת הבידוד בצד ה-WebView', () {
    Uri uri(String path) => Uri.parse('http://127.0.0.1:1234$path');

    test('מאשר רק URL עם מזהה התוסף עצמו', () {
      expect(PluginFileServer.isUriForPlugin(uri('/f/pA/tok'), 'pA'), isTrue);
      expect(PluginFileServer.isUriForPlugin(uri('/f/pB/tok'), 'pA'), isFalse);
    });

    test('פורמט ישן (2 סגמנטים) מאושר, נתיב אחר נדחה', () {
      expect(PluginFileServer.isUriForPlugin(uri('/f/tok'), 'pA'), isTrue);
      expect(PluginFileServer.isUriForPlugin(uri('/other/x'), 'pA'), isFalse);
      expect(
        PluginFileServer.isUriForPlugin(uri('/f/pA/x/tok'), 'pA'),
        isFalse,
      );
      expect(PluginFileServer.isUriForPlugin(uri('/'), 'pA'), isFalse);
    });
  });

  test('CORS מוחזר ל-origin של file:// בלבד', () async {
    final file = await writeFile('doc.txt', 'x');
    final reg = await server.register(pluginId: 'p1', canonicalPath: file.path);

    final fileOrigin = await client.getUrl(Uri.parse(reg.url));
    fileOrigin.headers.set('origin', 'null');
    final allowed = await fileOrigin.close();
    expect(allowed.headers.value('access-control-allow-origin'), 'null');
    await allowed.drain();

    final webOrigin = await client.getUrl(Uri.parse(reg.url));
    webOrigin.headers.set('origin', 'https://evil.example.com');
    final blocked = await webOrigin.close();
    expect(blocked.headers.value('access-control-allow-origin'), isNull);
    await blocked.drain();
  });

  test('לאחר revoke ה-token מחזיר 404', () async {
    final file = await writeFile('doc.txt', 'data');
    final reg = await server.register(pluginId: 'p1', canonicalPath: file.path);

    server.revoke(reg.token);
    final response = await get(reg.url);
    expect(response.statusCode, 404);
    await response.drain();
  });

  test('revokeAllForPlugin מסיר רק את הקבצים של אותו תוסף', () async {
    final fileA = await writeFile('a.txt', 'a');
    final fileB = await writeFile('b.txt', 'b');
    final regA = await server.register(
      pluginId: 'pA',
      canonicalPath: fileA.path,
    );
    final regB = await server.register(
      pluginId: 'pB',
      canonicalPath: fileB.path,
    );

    server.revokeAllForPlugin('pA');

    expect((await get(regA.url)).statusCode, 404);
    final responseB = await get(regB.url);
    expect(responseB.statusCode, 200);
    await responseB.drain();
  });

  test('registerWithToken בונה מחדש URL לאותו token', () async {
    final file = await writeFile('doc.txt', 'persisted');
    const token = 'fixed-token-123';
    final url = await server.registerWithToken(
      pluginId: 'p1',
      canonicalPath: file.path,
      token: token,
    );
    expect(url, '${server.origin}/f/p1/$token');

    final response = await get(url);
    expect(response.statusCode, 200);
    expect(await response.transform(utf8.decoder).join(), 'persisted');
  });

  test('HEAD מחזיר כותרות בלי גוף', () async {
    final file = await writeFile('doc.txt', 'hello world');
    final reg = await server.register(pluginId: 'p1', canonicalPath: file.path);

    final request = await client.openUrl('HEAD', Uri.parse(reg.url));
    final response = await request.close();
    expect(response.statusCode, 200);
    expect(response.headers.contentLength, 11);
    expect(await response.transform(utf8.decoder).join(), isEmpty);
  });

  test('PDF מקבל Content-Type של application/pdf', () async {
    final file = await writeFile('book.pdf', '%PDF-1.4 fake');
    final reg = await server.register(pluginId: 'p1', canonicalPath: file.path);

    final response = await get(reg.url);
    expect(response.headers.contentType?.mimeType, 'application/pdf');
    await response.drain();
  });

  test('isServerUri מזהה את ה-origin של השרת ושולל פורט אחר', () async {
    final file = await writeFile('doc.txt', 'x');
    await server.register(pluginId: 'p1', canonicalPath: file.path);
    final origin = Uri.parse(server.origin!);

    expect(server.isServerUri(origin), isTrue);
    expect(
      server.isServerUri(origin.replace(port: origin.port + 1)),
      isFalse,
    );
    expect(server.isServerUri(Uri.parse('https://example.com')), isFalse);
  });

  // ==========================================================================
  // העלאות (PUT) — הצעד שבו הבייטים של DOCX מגיעים מהתוסף אל הדיסק.
  // ==========================================================================
  group('העלאות', () {
    Future<HttpClientResponse> put(
      String url,
      List<int> body, {
      bool declareLength = true,
      int? declaredLength,
    }) async {
      final request = await client.putUrl(Uri.parse(url));
      request.headers.contentType = ContentType('application', 'octet-stream');
      if (declareLength) {
        request.contentLength = declaredLength ?? body.length;
      }
      request.add(body);
      return request.close();
    }

    test('העלאה תקינה נקלטת, ו-commit לוקח את הבייטים פעם אחת', () async {
      final ticket = await server.beginUpload(pluginId: 'p1');
      expect(ticket.uploadUrl, startsWith('${server.origin}/w/'));
      expect(ticket.maxBytes, PluginFileServer.defaultMaxUploadBytes);
      expect(server.activeUploadsFor('p1'), 1);

      final bytes = utf8.encode('docx-bytes');
      final response = await put(ticket.uploadUrl, bytes);
      expect(response.statusCode, HttpStatus.noContent);
      await response.drain();

      final file = await server.takeUpload(
        pluginId: 'p1',
        writeToken: ticket.writeToken,
      );
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), bytes);
      // ה-session נשאר בבעלות השרת עד finishCommit — גם במכסה.
      expect(server.activeUploadsFor('p1'), 1);

      // חד-פעמי: commit שני אינו מקבל את הקובץ.
      expect(
        await server.takeUpload(
          pluginId: 'p1',
          writeToken: ticket.writeToken,
        ),
        isNull,
      );

      await server.finishCommit(
        pluginId: 'p1',
        writeToken: ticket.writeToken,
      );
      expect(server.activeUploadsFor('p1'), 0);
      expect(await file.exists(), isFalse);
    });

    test('PUT ללא Content-Length נדחה ב-411', () async {
      final ticket = await server.beginUpload(pluginId: 'p1');
      final response = await put(
        ticket.uploadUrl,
        utf8.encode('abc'),
        declareLength: false,
      );

      expect(response.statusCode, HttpStatus.lengthRequired);
      await response.drain();
    });

    /// שולח בקשה מפוברקת ב-socket גולמי. HttpClient אוכף Content-Length בעצמו,
    /// ולכן אי אפשר לבדוק דרכו גוף שאינו תואם את מה שהוצהר.
    Future<String> rawPut(
      String url,
      String body, {
      required int declaredLength,
      bool closeEarly = false,
    }) async {
      final uri = Uri.parse(url);
      final socket = await Socket.connect(uri.host, uri.port);
      // המקטע הראשון מכיל את שורת הסטטוס והכותרות. אין להשתמש ב-join: החיבור
      // הוא keep-alive ולכן ה-EOF לא יגיע.
      final response = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .first
          .timeout(const Duration(seconds: 5), onTimeout: () => '')
          .catchError((_) => '');

      socket.write(
        'PUT ${uri.path} HTTP/1.1\r\n'
        'Host: ${uri.host}:${uri.port}\r\n'
        'Content-Type: application/octet-stream\r\n'
        'Content-Length: $declaredLength\r\n'
        '\r\n',
      );
      if (body.isNotEmpty) socket.write(body);
      await socket.flush();
      if (closeEarly) {
        // חצי-סגירה: השרת רואה סוף זרם לפני שהגיעו כל הבייטים שהוצהרו.
        await socket.close();
      }
      final text = await response;
      socket.destroy();
      return text;
    }

    /// הנתיב שבו השרת מחזיק את ה-temp של העלאה. דטרמיניסטי לפי ה-token, ולכן
    /// אפשר לאמת שלא נכתב בכלל.
    File tempFileFor(String writeToken) => File(
      '${Directory.systemTemp.path}/otzaria_plugin_uploads/$writeToken.part',
    );

    test('Content-Length מעל המגבלה נדחה לפני שנכתב בייט', () async {
      // שרת עם מגבלה קטנה, כדי לבדוק את מסלול הדחייה האמיתי בלי להעלות 100MB.
      final small = PluginFileServer(maxUploadBytes: 8);
      addTearDown(small.close);
      final ticket = await small.beginUpload(pluginId: 'p1');
      expect(ticket.maxBytes, 8);

      final request = await client.putUrl(Uri.parse(ticket.uploadUrl));
      request.contentLength = 9;
      request.add(utf8.encode('123456789'));
      final response = await request.close();

      expect(response.statusCode, HttpStatus.requestEntityTooLarge);
      await response.drain();
      // העיקר: הדחייה על סמך הכותרת בלבד — הקובץ לא נוצר. בלי האסרשן הזאת
      // הבדיקה עוברת גם אם המגבלה נאכפת רק אחרי שהבייטים ירדו לדיסק.
      expect(await tempFileFor(ticket.writeToken).exists(), isFalse);
      expect(
        await small.takeUpload(pluginId: 'p1', writeToken: ticket.writeToken),
        isNull,
      );
    });

    group('פקיעת writeToken', () {
      /// ברירת המחדל פוגה מיד — לבדיקות שה-token כבר פג בהן. בדיקה שצריכה
      /// שההעלאה *תצליח* לפני הפקיעה חייבת [ttl] גדול מזמן ה-PUT.
      Future<PluginFileServer> expiredServer({
        Duration ttl = const Duration(milliseconds: 1),
      }) async {
        final server = PluginFileServer(uploadTtl: ttl);
        addTearDown(server.close);
        return server;
      }

      test('PUT אחרי שה-token פג מוחזר 410 והקובץ אינו נוצר', () async {
        final server = await expiredServer();
        final ticket = await server.beginUpload(pluginId: 'p1');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final request = await client.putUrl(Uri.parse(ticket.uploadUrl));
        request.contentLength = 3;
        request.add(utf8.encode('abc'));
        final response = await request.close();

        expect(response.statusCode, HttpStatus.gone);
        await response.drain();
        expect(await tempFileFor(ticket.writeToken).exists(), isFalse);
      });

      test('commit אחרי פקיעה מחזיר null ומוחק את ה-temp', () async {
        final server = await expiredServer(ttl: const Duration(seconds: 1));
        final ticket = await server.beginUpload(pluginId: 'p1');
        final request = await client.putUrl(Uri.parse(ticket.uploadUrl));
        request.contentLength = 3;
        request.add(utf8.encode('abc'));
        await (await request.close()).drain();
        expect(await tempFileFor(ticket.writeToken).exists(), isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 1200));

        expect(
          await server.takeUpload(
            pluginId: 'p1',
            writeToken: ticket.writeToken,
          ),
          isNull,
        );
        expect(await tempFileFor(ticket.writeToken).exists(), isFalse);
        expect(server.activeUploadsFor('p1'), 0);
      });

      test('העלאה שפגה משוחררת מהמכסה בפתיחה הבאה', () async {
        final server = await expiredServer();
        await server.beginUpload(pluginId: 'p1');
        await server.beginUpload(pluginId: 'p1');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // בלי ה-sweep שב-beginUpload שתי אלה היו חוסמות את המכסה לנצח.
        expect(await server.beginUpload(pluginId: 'p1'), isNotNull);
      });
    });

    test('גוף שעובר את המגבלה תוך כדי נעצר ואינו נשמר', () async {
      // המגבלה נאכפת גם כשהלקוח מצהיר על גודל תקין ומגדיל בפועל — כאן דרך
      // מגבלה קטנה מהמוצהר.
      final small = PluginFileServer(maxUploadBytes: 4);
      addTearDown(small.close);
      final ticket = await small.beginUpload(pluginId: 'p1');

      final request = await client.putUrl(Uri.parse(ticket.uploadUrl));
      request.contentLength = 5;
      request.add(utf8.encode('12345'));
      final response = await request.close();

      expect(response.statusCode, HttpStatus.requestEntityTooLarge);
      await response.drain();
      expect(
        await small.takeUpload(pluginId: 'p1', writeToken: ticket.writeToken),
        isNull,
      );
    });

    test('גוף קטוע אינו הופך למסמך שנשמר', () async {
      final ticket = await server.beginUpload(pluginId: 'p1');

      await rawPut(
        ticket.uploadUrl,
        'abc',
        declaredLength: 10,
        closeEarly: true,
      );

      // הקוד מגיב 400 או 500 לפי איך שהזרם נקטע; בשני המקרים אין מה לקחת.
      expect(
        await server.takeUpload(
          pluginId: 'p1',
          writeToken: ticket.writeToken,
        ),
        isNull,
      );
    });

    test('expectedSize מעל המגבלה נדחה לפני שנפתחה העלאה', () async {
      expect(
        () => server.beginUpload(
          pluginId: 'p1',
          expectedSize: PluginFileServer.defaultMaxUploadBytes + 1,
        ),
        throwsA(
          isA<PluginUploadException>().having(
            (e) => e.code,
            'code',
            'error.too_large',
          ),
        ),
      );
      expect(server.activeUploadsFor('p1'), 0);
    });

    test('מעל שתי העלאות פעילות נדחה', () async {
      await server.beginUpload(pluginId: 'p1');
      await server.beginUpload(pluginId: 'p1');

      expect(
        () => server.beginUpload(pluginId: 'p1'),
        throwsA(
          isA<PluginUploadException>().having(
            (e) => e.code,
            'code',
            'error.too_many_requests',
          ),
        ),
      );
      // המגבלה היא לכל תוסף, לא גלובלית.
      expect(await server.beginUpload(pluginId: 'p2'), isNotNull);
    });

    test('קריאות beginUpload מקבילות אינן עוקפות את המכסה', () async {
      final results = await Future.wait(
        List.generate(3, (_) async {
          try {
            await server.beginUpload(pluginId: 'p1');
            return true;
          } on PluginUploadException catch (error) {
            expect(error.code, 'error.too_many_requests');
            return false;
          }
        }),
      );

      expect(results.where((accepted) => accepted), hasLength(2));
      expect(server.activeUploadsFor('p1'), 2);
    });

    test('PUT שני על אותו token נדחה ב-409', () async {
      final ticket = await server.beginUpload(pluginId: 'p1');
      final first = await put(ticket.uploadUrl, utf8.encode('abc'));
      expect(first.statusCode, HttpStatus.noContent);
      await first.drain();

      final second = await put(ticket.uploadUrl, utf8.encode('xyz'));
      expect(second.statusCode, HttpStatus.conflict);
      await second.drain();
    });

    test('token לא מוכר מחזיר 404', () async {
      await server.beginUpload(pluginId: 'p1');
      final response = await put(
        '${server.origin}/w/deadbeef',
        utf8.encode('x'),
      );

      expect(response.statusCode, HttpStatus.notFound);
      await response.drain();
    });

    test('מתודה שאינה PUT על נתיב העלאה נדחית', () async {
      final ticket = await server.beginUpload(pluginId: 'p1');
      final response = await (await client.getUrl(
        Uri.parse(ticket.uploadUrl),
      )).close();

      expect(response.statusCode, HttpStatus.methodNotAllowed);
      await response.drain();
    });

    test('תוסף אחר אינו יכול לקחת את ההעלאה', () async {
      final ticket = await server.beginUpload(pluginId: 'p1');
      final response = await put(ticket.uploadUrl, utf8.encode('abc'));
      await response.drain();

      expect(
        await server.takeUpload(
          pluginId: 'p2',
          writeToken: ticket.writeToken,
        ),
        isNull,
      );
      // ולבעלים היא עדיין זמינה.
      final file = await server.takeUpload(
        pluginId: 'p1',
        writeToken: ticket.writeToken,
      );
      expect(file, isNotNull);
      await file!.delete();
    });

    test('commit לפני שה-PUT הושלם מחזיר null', () async {
      final ticket = await server.beginUpload(pluginId: 'p1');

      expect(
        await server.takeUpload(
          pluginId: 'p1',
          writeToken: ticket.writeToken,
        ),
        isNull,
      );
    });

    group('ביטול העלאה', () {
      test('מוחק את ה-temp ומשחרר את המכסה מיד', () async {
        final ticket = await server.beginUpload(pluginId: 'p1');
        await (await put(ticket.uploadUrl, utf8.encode('abc'))).drain();
        expect(await tempFileFor(ticket.writeToken).exists(), isTrue);

        final aborted = await server.abortUpload(
          pluginId: 'p1',
          writeToken: ticket.writeToken,
        );

        expect(aborted, isTrue);
        expect(server.activeUploadsFor('p1'), 0);
        expect(await tempFileFor(ticket.writeToken).exists(), isFalse);
      });

      test('עובד גם על העלאה שטרם קיבלה בייטים', () async {
        final ticket = await server.beginUpload(pluginId: 'p1');

        expect(
          await server.abortUpload(
            pluginId: 'p1',
            writeToken: ticket.writeToken,
          ),
          isTrue,
        );
        expect(server.activeUploadsFor('p1'), 0);
      });

      test('אידמפוטנטי — token שאינו קיים מחזיר true', () async {
        expect(
          await server.abortUpload(pluginId: 'p1', writeToken: 'deadbeef'),
          isTrue,
        );
      });

      test('תוסף אחר אינו יכול לבטל', () async {
        final ticket = await server.beginUpload(pluginId: 'p1');

        expect(
          await server.abortUpload(
            pluginId: 'p2',
            writeToken: ticket.writeToken,
          ),
          isFalse,
        );
        expect(server.activeUploadsFor('p1'), 1);
      });

      test('אינו מבטל commit חי', () async {
        // ביטול באמצע commit היה מוחק את ה-temp מתחת לדיאלוג „שמור בשם” פתוח.
        final ticket = await server.beginUpload(pluginId: 'p1');
        await (await put(ticket.uploadUrl, utf8.encode('abc'))).drain();
        final file = await server.takeUpload(
          pluginId: 'p1',
          writeToken: ticket.writeToken,
        );
        expect(file, isNotNull);

        expect(
          await server.abortUpload(
            pluginId: 'p1',
            writeToken: ticket.writeToken,
          ),
          isFalse,
        );
        expect(await file!.exists(), isTrue);
        expect(server.activeUploadsFor('p1'), 1);
      });
    });

    test('revokeAllForPlugin מבטל גם העלאות פעילות', () async {
      final ticket = await server.beginUpload(pluginId: 'p1');
      // העלאה של תוסף אחר, כדי לוודא שהניקוי ממוקד.
      await server.beginUpload(pluginId: 'p2');
      final response = await put(ticket.uploadUrl, utf8.encode('abc'));
      await response.drain();

      await server.revokeAllForPlugin('p1');

      expect(server.activeUploadsFor('p1'), 0);
      expect(server.activeUploadsFor('p2'), 1);
      expect(
        await server.takeUpload(
          pluginId: 'p1',
          writeToken: ticket.writeToken,
        ),
        isNull,
      );
    });

    test('close מוחק את קובצי ה-temp של העלאות פעילות', () async {
      final ticket = await server.beginUpload(pluginId: 'p1');
      await (await put(ticket.uploadUrl, utf8.encode('abc'))).drain();
      final temp = tempFileFor(ticket.writeToken);
      expect(await temp.exists(), isTrue);

      await server.close();

      expect(server.activeUploadsFor('p1'), 0);
      expect(await temp.exists(), isFalse);
    });

    group('העלאה בזמן commit', () {
      /// „שמור בשם” פותח דיאלוג, וכל עוד הוא פתוח הקובץ חייב להישאר בבעלות
      /// השרת. אחרת הוא יתום: close ו-revoke אינם מכירים אותו, וה-sweep עלול
      /// למחוק אותו מתחת לידיים.
      Future<({PluginUploadTicket ticket, File temp})> uploadInCommit(
        PluginFileServer target,
      ) async {
        final ticket = await target.beginUpload(pluginId: 'p1');
        await (await put(ticket.uploadUrl, utf8.encode('abc'))).drain();
        final file = await target.takeUpload(
          pluginId: 'p1',
          writeToken: ticket.writeToken,
        );
        expect(file, isNotNull);
        return (ticket: ticket, temp: file!);
      }

      test('נספרת במכסה', () async {
        final first = await uploadInCommit(server);
        await server.beginUpload(pluginId: 'p1');

        expect(server.activeUploadsFor('p1'), 2);
        await expectLater(
          server.beginUpload(pluginId: 'p1'),
          throwsA(isA<PluginUploadException>()),
        );

        await server.finishCommit(
          pluginId: 'p1',
          writeToken: first.ticket.writeToken,
        );
        expect(server.activeUploadsFor('p1'), 1);
      });

      test('close מוחק גם אותה', () async {
        final held = await uploadInCommit(server);

        await server.close();

        expect(await held.temp.exists(), isFalse);
        expect(server.activeUploadsFor('p1'), 0);
      });

      test('revokeAllForPlugin מוחק גם אותה', () async {
        final held = await uploadInCommit(server);

        await server.revokeAllForPlugin('p1');

        expect(await held.temp.exists(), isFalse);
        expect(server.activeUploadsFor('p1'), 0);
      });

      test('אינה נמחקת ב-sweep גם אחרי שה-TTL עבר', () async {
        // דיאלוג שמירה יכול להישאר פתוח יותר משתי דקות; ה-TTL חל על שלב
        // ההעלאה בלבד.
        // TTL קצר אך מספיק כדי להשלים PUT ו-takeUpload לפני שהוא עובר.
        final shortLived = PluginFileServer(
          uploadTtl: const Duration(milliseconds: 400),
        );
        addTearDown(shortLived.close);
        final held = await uploadInCommit(shortLived);
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // beginUpload מריץ sweep.
        await shortLived.beginUpload(pluginId: 'p2');

        expect(await held.temp.exists(), isTrue);
        expect(shortLived.activeUploadsFor('p1'), 1);

        await shortLived.finishCommit(
          pluginId: 'p1',
          writeToken: held.ticket.writeToken,
        );
        expect(await held.temp.exists(), isFalse);
      });

      test('commit חי אינו פג גם אחרי הרבה זמן', () async {
        // דיאלוג „שמור בשם” יכול להישאר פתוח זמן בלתי מוגבל, וה-sweep רץ בכל
        // beginUpload של כל תוסף. אם שעון היה מוחק את ה-temp, ה-commit היה
        // נכשל בדיוק ברגע שהמשתמש לוחץ „שמור”.
        final shortLived = PluginFileServer(
          uploadTtl: const Duration(milliseconds: 300),
        );
        addTearDown(shortLived.close);
        final held = await uploadInCommit(shortLived);

        await Future<void>.delayed(const Duration(milliseconds: 400));
        await shortLived.beginUpload(pluginId: 'p2');
        await shortLived.beginUpload(pluginId: 'p3');

        expect(await held.temp.exists(), isTrue);
        expect(shortLived.activeUploadsFor('p1'), 1);

        // מה שמשחרר הוא סיום הפעולה, לא הזמן.
        await shortLived.finishCommit(
          pluginId: 'p1',
          writeToken: held.ticket.writeToken,
        );
        expect(await held.temp.exists(), isFalse);
        expect(shortLived.activeUploadsFor('p1'), 0);
      });

      test('finishCommit של תוסף אחר אינו נוגע בה', () async {
        final held = await uploadInCommit(server);

        await server.finishCommit(
          pluginId: 'p2',
          writeToken: held.ticket.writeToken,
        );

        expect(await held.temp.exists(), isTrue);
        expect(server.activeUploadsFor('p1'), 1);
      });
    });
  });
}
