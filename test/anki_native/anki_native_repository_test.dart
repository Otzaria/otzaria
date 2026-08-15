import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/anki_native/models/anki_native_window.dart';
import 'package:otzaria/anki_native/repository/anki_native_repository.dart';
import 'package:otzaria/core/http_client_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('שגיאת Native מה־Bridge נשמרת עבור מעבר למסלול השיקוף', () async {
    final repository = LocalAnkiNativeRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'ok': false,
            'error': {
              'code': 'native_attach_failed',
              'message': 'Qt attach failed',
            },
          }),
          500,
        ),
      ),
      nativeChannel: const MethodChannel('test/anki_native'),
    );
    addTearDown(repository.dispose);

    await expectLater(
      repository.fetchWindows(),
      throwsA(
        isA<PlatformException>()
            .having((error) => error.code, 'code', 'native_attach_failed')
            .having((error) => error.message, 'message', 'Qt attach failed'),
      ),
    );
  });

  test('סגירת HTTP מנתקת את Anki לפני סגירת הלקוח', () async {
    const channel = MethodChannel('test/anki_native_shutdown');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'prepare') return 123;
      return true;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      HttpClientRegistry.clearForTest();
    });
    HttpClientRegistry.clearForTest();
    final paths = <String>[];
    final repository = LocalAnkiNativeRepository(
      client: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(jsonEncode({'ok': true, 'data': {}}), 200);
      }),
      nativeChannel: channel,
    );

    await repository.attach(
      const AnkiNativeWindow(
        targetId: 'main',
        hwnd: 'ABC',
        title: 'Anki',
        kind: 'mainWindow',
        active: true,
        modal: false,
        closable: false,
      ),
      42,
      'generation',
    );
    await HttpClientRegistry.closeAll(timeout: const Duration(seconds: 2));

    expect(paths, contains('/v1/native/attach-ended'));
  });
}
