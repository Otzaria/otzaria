import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/anki_native/repository/anki_native_repository.dart';

void main() {
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
}
