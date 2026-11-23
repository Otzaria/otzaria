import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/netfree_certificates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('קובץ CA שחסר בהתקנה מדולג ונרשם, והשאר נטענים בלי לזרוק', () async {
    final tempDir = Directory.systemTemp.createTempSync('otzaria_netfree_ca_');
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    addTearDown(() {
      AppPaths.debugOverrideDataRootPath(null);
      tempDir.deleteSync(recursive: true);
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = Uri.decodeFull(
        utf8.decode(message!.buffer.asUint8List(message.offsetInBytes)),
      );
      if (key == 'assets/ca/netfree_cas.pem') return null;
      return ByteData.sublistView(File(key).readAsBytesSync());
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));

    final bundles = await loadNetfreeCaBytes();

    expect(bundles, hasLength(kNetfreeCaAssets.length - 1));
    for (final bundle in bundles) {
      expect(utf8.decode(bundle), contains('-----BEGIN CERTIFICATE-----'));
    }
    await ErrorLogFile.flushPending(timeout: const Duration(seconds: 30));
    expect(
      ErrorLogFile.resolveFile().readAsStringSync(),
      contains('assets/ca/netfree_cas.pem'),
    );
  });
}
