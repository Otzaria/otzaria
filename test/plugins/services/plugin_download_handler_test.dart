import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/plugins/services/plugin_download_handler.dart';

void main() {
  test('Windows מסתיר את חלונית WebView2 בלי לבטל את ההורדה', () {
    final response = PluginDownloadHandler.responseFor(isWindows: true);

    expect(response, isNotNull);
    expect(response!.handled, isTrue);
    expect(response.action, isNull);
  });

  test('פלטפורמה שאינה Windows אינה משנה את מסלול ההורדה', () {
    expect(
      PluginDownloadHandler.responseFor(isWindows: false),
      isNull,
    );
  });

  group('isExecutableDownload', () {
    DownloadStartRequest request({
      String url = 'blob:https://plugin.local/1b2c',
      String? suggestedFilename,
      String? contentDisposition,
    }) => DownloadStartRequest(
      url: WebUri(url),
      contentLength: 10,
      suggestedFilename: suggestedFilename,
      contentDisposition: contentDisposition,
    );

    test('שם מוצע של קובץ הרצה נחסם', () {
      expect(
        PluginDownloadHandler.isExecutableDownload(
          request(suggestedFilename: 'OtzariaAIProxy.exe'),
        ),
        isTrue,
      );
    });

    test('Content-Disposition עם filename או filename* נחסם', () {
      expect(
        PluginDownloadHandler.isExecutableDownload(
          request(contentDisposition: 'attachment; filename="setup.msi"'),
        ),
        isTrue,
      );
      expect(
        PluginDownloadHandler.isExecutableDownload(
          request(
            contentDisposition:
                "attachment; filename=\"a.txt\"; filename*=UTF-8''run%2Ebat",
          ),
        ),
        isTrue,
      );
    });

    test('כתובת שמסתיימת בקובץ הרצה נחסמת', () {
      expect(
        PluginDownloadHandler.isExecutableDownload(
          request(url: 'https://example.com/files/tool.exe?x=1'),
        ),
        isTrue,
      );
    });

    test('מסמך רגיל מותר, גם עם קידוד שבור בכותרת', () {
      expect(
        PluginDownloadHandler.isExecutableDownload(
          request(
            url: 'https://example.com/book.pdf',
            suggestedFilename: 'book.pdf',
            contentDisposition: 'attachment; filename*=UTF-8\'\'%E0%A4%A.pdf',
          ),
        ),
        isFalse,
      );
    });
  });

  test('ההודעה מתארת התחלה ולא הצלחה שטרם התרחשה', () {
    expect(PluginMessages.fileDownloadStarted, contains('החלה'));
    expect(PluginMessages.fileDownloadStarted, isNot(contains('נשמר')));
  });
}
