import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
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

    test(
      'lets another process share the user data folder (issue #2458)',
      () {
        final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
          r'C:\app-data\webview2',
        );

        expect(settings.exclusiveUserDataFolderAccess, isFalse);
      },
    );

    test('registers the plugin asset scheme as a secure origin', () {
      final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
        r'C:\app-data\webview2',
      );

      final registration = settings.customSchemeRegistrations!.single;
      expect(registration.scheme, pluginAssetScheme);
      expect(registration.treatAsSecure, isTrue);
      expect(registration.hasAuthorityComponent, isTrue);
    });
  });
}
