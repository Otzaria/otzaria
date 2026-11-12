import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/link_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('copyLinkToClipboard', () {
    test('מעביר את הקישור ל-Clipboard.setData', () async {
      String? capturedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              capturedText = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });

      try {
        await copyLinkToClipboard('otzaria://open/book/123?index=5');
        expect(capturedText, 'otzaria://open/book/123?index=5');
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      }
    });
  });
}
