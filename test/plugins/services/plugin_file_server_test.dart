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
    final response = await get('$origin/f/deadbeef');
    expect(response.statusCode, 404);
    await response.drain();
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
    expect(url, '${server.origin}/f/$token');

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
}
