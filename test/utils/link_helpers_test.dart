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

    test('משתמש ב-Clipboard.setData ולא מסתמך על super_clipboard', () async {
      // הגנה מול רגרסיה: אם helper היה משתמש ב-SystemClipboard.instance
      // (super_clipboard) הוא היה יכול להחזיר null בלי לכתוב כלום ולהראות
      // הודעת הצלחה כוזבת. כאן בודקים שערוץ Clipboard.setData אכן נקרא.
      bool clipboardCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardCalled = true;
            }
            return null;
          });

      try {
        await copyLinkToClipboard('otzaria://open/pdf/42');
        expect(
          clipboardCalled,
          isTrue,
          reason: 'copyLinkToClipboard חייב להשתמש ב-Clipboard.setData',
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      }
    });
  });
}
