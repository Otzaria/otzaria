import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(null));

  group('WebViewEnvironmentHolder.isRuntimeAvailable', () {
    test('override true → מחזיר true', () async {
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(true);
      expect(await WebViewEnvironmentHolder.isRuntimeAvailable(), isTrue);
    });

    test('override false → מחזיר false', () async {
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(false);
      expect(await WebViewEnvironmentHolder.isRuntimeAvailable(), isFalse);
    });

    test('איפוס override מחזיר את הבדיקה להתנהגות הרגילה', () async {
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(false);
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(null);
      // ללא override, על פלטפורמה שאינה Windows התוצאה היא true; ב-Windows
      // ללא platform channel הקריאה נכשלת ומוחזר false. בשני המקרים אסור
      // שהקריאה תזרוק חריגה.
      await expectLater(
        WebViewEnvironmentHolder.isRuntimeAvailable(),
        completes,
      );
    });
  });

  group('WebViewEnvironmentHolder environment settings', () {
    test('uses the requested user data folder', () {
      final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
        r'C:\app-data\webview2',
      );

      expect(settings.userDataFolder, r'C:\app-data\webview2');
    });

    test('requires exclusive access to the user data folder', () {
      final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
        r'C:\app-data\webview2',
      );

      expect(settings.exclusiveUserDataFolderAccess, isTrue);
    });
  });
}
