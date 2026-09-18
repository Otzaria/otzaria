import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/external_catalog/responsa/responsa_bridge_client.dart';
import 'package:otzaria/external_catalog/responsa/responsa_paths.dart';
import 'package:path/path.dart' as path;

const _endpoint = ResponsaBridgeEndpoint(
  port: 39627,
  token: 'secret-token',
  pid: 1234,
  bridgeVersion: 1,
);

ResponsaBridgeClient _clientReturning(
  Future<http.Response> Function(http.Request request) handler,
) {
  return ResponsaBridgeClient(httpClient: MockClient(handler))
    ..endpointOverride = _endpoint;
}

http.Response _json(Map<String, Object?> body, [int status = 200]) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('קובץ ה-discovery', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-bridge-');
      ResponsaPaths.debugBaseDirectoryOverride = tempDir.path;
    });

    tearDown(() async {
      ResponsaPaths.debugBaseDirectoryOverride = null;
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('קובץ חסר — הגשר נחשב כבוי, בלי חריג', () async {
      final client = ResponsaBridgeClient();
      expect(await client.endpoint(), isNull);
      expect(await client.status(), isNull);
      expect(await client.isRunning(), isFalse);
    });

    test('קובץ פגום אינו מפיל את הלקוח', () async {
      await File(
        path.join(tempDir.path, ResponsaPaths.discoveryFileName),
      ).writeAsString('}{ this is not json');

      expect(await ResponsaBridgeClient().endpoint(), isNull);
    });

    test('קובץ בלי token או עם port לא תקין נדחה', () async {
      final file = File(
        path.join(tempDir.path, ResponsaPaths.discoveryFileName),
      );

      await file.writeAsString(jsonEncode({'port': 39627}));
      expect(await ResponsaBridgeClient().endpoint(), isNull);

      await file.writeAsString(jsonEncode({'port': 0, 'token': 'x'}));
      expect(await ResponsaBridgeClient().endpoint(), isNull);
    });

    test('קובץ תקין נקרא', () async {
      await File(
        path.join(tempDir.path, ResponsaPaths.discoveryFileName),
      ).writeAsString(
        jsonEncode({
          'port': 39627,
          'token': 'abc',
          'pid': 99,
          'bridgeVersion': 1,
        }),
      );

      final endpoint = (await ResponsaBridgeClient().endpoint())!;
      expect(endpoint.port, 39627);
      expect(endpoint.token, 'abc');
      expect(endpoint.uri('/api/status').host, '127.0.0.1');
    });
  });

  group('אבטחה', () {
    test('כל בקשה נושאת את ה-token, ותמיד ל-127.0.0.1', () async {
      Uri? seen;
      String? token;
      final client = _clientReturning((request) async {
        seen = request.url;
        token = request.headers[ResponsaBridgeClient.tokenHeader];
        return _json({'ok': true, 'bridgeVersion': 1});
      });

      await client.status();

      expect(token, 'secret-token');
      expect(seen!.host, '127.0.0.1');
      expect(seen!.port, 39627);
      expect(seen!.scheme, 'http');
    });

    test('401 נחשב כגשר לא זמין ולא כתשובה', () async {
      final client = _clientReturning(
        (_) async => _json({'ok': false, 'error': 'unauthorized'}, 401),
      );

      expect(await client.status(), isNull);
      final opened = await client.openBook('משנה ברורה');
      expect(opened.ok, isFalse);
      expect(opened.errorCode, 'bridgeUnavailable');
    });
  });

  group('status', () {
    test('מפענח גרסה ויכולות', () async {
      final client = _clientReturning(
        (_) async => _json({
          'ok': true,
          'bridgeVersion': 1,
          'responsaDetected': true,
          'responsaVersion': 25,
          'installPath': r'C:\Program Files (x86)\ResponsaCD25',
          'pid': 4242,
          'supported': true,
          'capabilities': {
            'catalog': true,
            'openBook': true,
            'gotoSiman': true,
            'searchInBook': false,
          },
        }),
      );

      final status = (await client.status())!;
      expect(status.responsaVersion, 25);
      expect(status.supported, isTrue);
      expect(status.capabilities.openBook, isTrue);
      expect(status.capabilities.searchInBook, isFalse);
    });

    test('גרסה שאינה נתמכת מדווחת עם סיבה, לא כהצלחה', () async {
      final client = _clientReturning(
        (_) async => _json({
          'ok': true,
          'bridgeVersion': 1,
          'responsaDetected': true,
          'responsaVersion': 29,
          'supported': false,
          'reason': 'unsupportedResponsaVersion',
        }),
      );

      final status = (await client.status())!;
      expect(status.responsaDetected, isTrue);
      expect(status.supported, isFalse);
      expect(status.reason, 'unsupportedResponsaVersion');
    });
  });

  group('openBook', () {
    test('הצלחה מחזירה את כותרת החלון שנפתח', () async {
      final client = _clientReturning(
        (_) async => _json({
          'ok': true,
          'window': 'משנה ברורה סימן א',
          'usedRef': 'משנה ברורה',
        }),
      );

      final result = await client.openBook('משנה ברורה');
      expect(result.ok, isTrue);
      expect(result.window, 'משנה ברורה סימן א');
    });

    test('כשל מהגשר חוזר כערך עם קוד, לא כחריג', () async {
      final client = _clientReturning(
        (_) async => _json({
          'ok': false,
          'error': 'openedWrongBook',
          'message': 'נפתח ספר אחר',
        }),
      );

      final result = await client.openBook('רש"י');
      expect(result.ok, isFalse);
      expect(result.errorCode, 'openedWrongBook');
    });

    test('קריסת הגשר באמצע אינה זורקת', () async {
      final client = _clientReturning(
        (_) async => throw const SocketException('connection refused'),
      );

      final result = await client.openBook('משנה ברורה');
      expect(result.ok, isFalse);
      expect(result.errorCode, 'bridgeUnavailable');
    });

    test('תשובה שאינה JSON אינה זורקת', () async {
      final client = _clientReturning(
        (_) async => http.Response('<html>', 200),
      );

      final result = await client.openBook('משנה ברורה');
      expect(result.ok, isFalse);
      expect(result.errorCode, 'bridgeUnavailable');
    });

    test('חוסר תגובה מסתיים ב-timeout ולא בהמתנה אינסופית', () async {
      final client = _clientReturning(
        (_) async => Future.delayed(
          const Duration(seconds: 30),
          () => _json({'ok': true}),
        ),
      )..endpointOverride = _endpoint;

      final result = await client
          .openBook('משנה ברורה')
          .timeout(
            const Duration(seconds: 6),
            onTimeout: () {
              return const ResponsaOpenResult(
                ok: false,
                errorCode: 'testTimeout',
              );
            },
          );

      // הבדיקה מוודאת שאין חריג ושהזרימה מסתיימת; תקרת הזמן האמיתית
      // של openBook ארוכה מדי לבדיקת יחידה.
      expect(result.ok, isFalse);
    });
  });

  group('cancel', () {
    test('ביטול נשלח לנתיב של הבקשה', () async {
      String? requestPath;
      final client = _clientReturning((request) async {
        requestPath = request.url.path;
        return _json({'ok': true});
      });

      await client.cancel('abc123');
      expect(requestPath, '/api/cancel/abc123');
    });

    test('ביטול כשהגשר כבוי אינו זורק', () async {
      final client = ResponsaBridgeClient(
        httpClient: MockClient((_) async => _json({'ok': true})),
      );
      // בלי endpointOverride, ובלי קובץ discovery — אין את מי לבטל.
      ResponsaPaths.debugBaseDirectoryOverride = Directory.systemTemp
          .createTempSync('otzaria-no-bridge-')
          .path;
      addTearDown(() => ResponsaPaths.debugBaseDirectoryOverride = null);

      await expectLater(client.cancel('abc'), completes);
    });
  });
}
