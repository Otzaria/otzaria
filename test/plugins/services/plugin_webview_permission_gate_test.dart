import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_webview_permission_gate.dart';

InstalledPlugin _plugin({List<String> permissions = const []}) =>
    InstalledPlugin(
      pluginId: 'p1',
      name: 'P1',
      version: '1.0.0',
      installPath: '/tmp/p1',
      entrypointPath: 'index.html',
      enabled: true,
      pinned: false,
      manifest: PluginManifest.fromJson({
        'id': 'p1',
        'name': 'P1',
        'version': '1.0.0',
        'entrypoint': 'index.html',
        'permissions': permissions,
      }),
      installedAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

PermissionRequest _request(
  List<PermissionResourceType> resources, {
  String origin = 'file:///C:/plugins/p1/index.html',
}) => PermissionRequest(origin: WebUri(origin), resources: resources);

class _FakeRegistry implements PluginRegistryRepository {
  _FakeRegistry({this.grants = const {}, this.throwOnRead = false});

  final Map<String, bool> grants;
  final bool throwOnRead;

  @override
  Future<bool?> getPermission(String pluginId, String permission) async {
    if (throwOnRead) throw StateError('DB unavailable');
    return grants[permission];
  }

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<PermissionResponseAction?> _ask({
  required List<PermissionResourceType> resources,
  List<String> manifest = const [],
  Map<String, bool> grants = const {},
  bool throwOnRead = false,
  String origin = 'file:///C:/plugins/p1/index.html',
}) async {
  final response = await PluginWebViewPermissionGate.respond(
    plugin: _plugin(permissions: manifest),
    request: _request(resources, origin: origin),
    registry: _FakeRegistry(grants: grants, throwOnRead: throwOnRead),
  );
  return response.action;
}

void main() {
  // לא `const`: המחלקה המחוללת של `PermissionResourceType` אינה חושפת
  // מופעים const, ולכן רשימה const שלהם אינה מתקמפלת.
  final clipboard = [PermissionResourceType.CLIPBOARD_READ];

  group('requiredPermissionFor', () {
    test('קריאת לוח דורשת את ההרשאה שהמשתמש מאשר', () {
      expect(
        PluginWebViewPermissionGate.requiredPermissionFor(
          PermissionResourceType.CLIPBOARD_READ,
        ),
        pluginClipboardReadPermission,
      );
    });

    test('מניית הגופנים דורשת את ההרשאה שהמשתמש מאשר', () {
      expect(
        PluginWebViewPermissionGate.requiredPermissionFor(
          PermissionResourceType.LOCAL_FONTS,
        ),
        pluginLocalFontsPermission,
      );
    });

    test('מיקום דורש את ההרשאה שהמשתמש מאשר', () {
      expect(
        PluginWebViewPermissionGate.requiredPermissionFor(
          PermissionResourceType.GEOLOCATION,
        ),
        pluginGeolocationPermission,
      );
    });

    test('יכולת שאינה ממופה אינה נפתחת לתוספים', () {
      for (final resource in [
        PermissionResourceType.CAMERA,
        PermissionResourceType.MICROPHONE,
        PermissionResourceType.FILE_READ_WRITE,
        PermissionResourceType.UNKNOWN,
      ]) {
        expect(
          PluginWebViewPermissionGate.requiredPermissionFor(resource),
          isNull,
          reason: resource.toValue(),
        );
      }
    });

    test('כל הרשאה שהשער ממפה היא הרשאה תקפה — שומר על שגיאת כתיב', () {
      for (final permission
          in PluginWebViewPermissionGate.requirements.values) {
        expect(pluginValidPermissions, contains(permission));
      }
    });
  });

  group('respond', () {
    test('הוצהר במניפסט והוענק בפועל — מאושר', () async {
      expect(
        await _ask(
          resources: clipboard,
          manifest: const [pluginClipboardReadPermission],
          grants: const {pluginClipboardReadPermission: true},
        ),
        PermissionResponseAction.GRANT,
      );
    });

    test('מניית גופנים: הוצהר והוענק — מאושר, ובלי הצהרה — נדחה', () async {
      final fonts = [PermissionResourceType.LOCAL_FONTS];
      expect(
        await _ask(
          resources: fonts,
          manifest: const [pluginLocalFontsPermission],
          grants: const {pluginLocalFontsPermission: true},
        ),
        PermissionResponseAction.GRANT,
      );
      // הענקה לבדה אינה מספיקה: בלי הצהרה במניפסט אין למשתמש מה לאשר.
      expect(
        await _ask(
          resources: fonts,
          grants: const {pluginLocalFontsPermission: true},
        ),
        PermissionResponseAction.DENY,
      );
    });

    test('הוצהר אבל המשתמש עוד לא החליט — נדחה', () async {
      // `getPermission` מחזיר `null` כשאין החלטה שמורה. „טרם הוחלט” אינו
      // „אושר”, וזו אותה סמנטיקה שגשר התוסף אוכף על כל קריאת RPC.
      expect(
        await _ask(
          resources: clipboard,
          manifest: const [pluginClipboardReadPermission],
        ),
        PermissionResponseAction.DENY,
      );
    });

    test('הוצהר והמשתמש כיבה — נדחה', () async {
      expect(
        await _ask(
          resources: clipboard,
          manifest: const [pluginClipboardReadPermission],
          grants: const {pluginClipboardReadPermission: false},
        ),
        PermissionResponseAction.DENY,
      );
    });

    test('הוענק אך לא הוצהר במניפסט — נדחה', () async {
      // הענקה ללא הצהרה היא שארית: התוסף הסיר את ההרשאה מהמניפסט והרשומה
      // בבסיס הנתונים נשארה. המניפסט הוא מה שהמשתמש ראה כשאישר.
      expect(
        await _ask(
          resources: clipboard,
          grants: const {pluginClipboardReadPermission: true},
        ),
        PermissionResponseAction.DENY,
      );
    });

    test('יכולת שאינה ממופה נדחית גם לתוסף עם כל ההרשאות', () async {
      expect(
        await _ask(
          resources: [PermissionResourceType.CAMERA],
          manifest: const [pluginClipboardReadPermission],
          grants: const {pluginClipboardReadPermission: true},
        ),
        PermissionResponseAction.DENY,
      );
    });

    test('בקשה בלי משאבים אינה „הכול מותר”', () async {
      expect(
        await _ask(
          resources: [],
          manifest: const [pluginClipboardReadPermission],
          grants: const {pluginClipboardReadPermission: true},
        ),
        PermissionResponseAction.DENY,
      );
    });

    test('בקשה מרובת משאבים נדחית כשמשאב אחד אינו מותר', () async {
      // ב-Windows יש משאב אחד לכל בקשה, אבל ב-Android יש רשימה — ואישור
      // הרשימה כולה בגלל משאב אחד שאושר הוא בדיוק הדליפה שאין לה גדר.
      expect(
        await _ask(
          resources: [
            PermissionResourceType.CLIPBOARD_READ,
            PermissionResourceType.CAMERA,
          ],
          manifest: const [pluginClipboardReadPermission],
          grants: const {pluginClipboardReadPermission: true},
        ),
        PermissionResponseAction.DENY,
      );
    });

    test('כשל בקריאת ההענקה נדחה, ואינו זורק', () async {
      // חריגה כאן הייתה משאירה את ה-deferral של WebView2 פתוח — דף שממתין
      // לתשובה שלא תבוא.
      expect(
        await _ask(
          resources: clipboard,
          manifest: const [pluginClipboardReadPermission],
          throwOnRead: true,
        ),
        PermissionResponseAction.DENY,
      );
    });

    test('התשובה מחזירה את המשאבים שנשאלו — Android נשען עליהם', () async {
      final response = await PluginWebViewPermissionGate.respond(
        plugin: _plugin(permissions: const [pluginClipboardReadPermission]),
        request: _request(clipboard),
        registry: _FakeRegistry(
          grants: const {pluginClipboardReadPermission: true},
        ),
      );
      expect(response.resources, clipboard);
    });
  });

  group('respond: מיקום (GEOLOCATION)', () {
    final geolocation = [PermissionResourceType.GEOLOCATION];
    const manifest = [pluginGeolocationPermission];
    const granted = {pluginGeolocationPermission: true};

    test('הוצהר והוענק — מאושר', () async {
      expect(
        await _ask(resources: geolocation, manifest: manifest, grants: granted),
        PermissionResponseAction.GRANT,
      );
    });

    test('הוצהר אבל לא הוחלט או כובה — נדחה (כבוי כברירת מחדל)', () async {
      expect(
        await _ask(resources: geolocation, manifest: manifest),
        PermissionResponseAction.DENY,
      );
      expect(
        await _ask(
          resources: geolocation,
          manifest: manifest,
          grants: const {pluginGeolocationPermission: false},
        ),
        PermissionResponseAction.DENY,
      );
    });

    test('הוענק אך לא הוצהר — נדחה', () async {
      expect(
        await _ask(resources: geolocation, grants: granted),
        PermissionResponseAction.DENY,
      );
    });

    test('הענקת לוח ההעתקה אינה פותחת מיקום', () async {
      expect(
        await _ask(
          resources: geolocation,
          manifest: const [pluginClipboardReadPermission],
          grants: const {pluginClipboardReadPermission: true},
        ),
        PermissionResponseAction.DENY,
      );
    });

    test('מסגרת של אתר חיצוני לא נהנית מההענקה של התוסף', () async {
      for (final origin in [
        'https://nominatim.openstreetmap.org/ui/',
        'http://evil.example:8080/',
        'about:blank',
        '',
      ]) {
        expect(
          await _ask(
            resources: geolocation,
            manifest: manifest,
            grants: granted,
            origin: origin,
          ),
          PermissionResponseAction.DENY,
          reason: origin,
        );
      }
    });

    test('כשל בקריאת ההענקה נדחה, ואינו זורק', () async {
      expect(
        await _ask(
          resources: geolocation,
          manifest: manifest,
          throwOnRead: true,
        ),
        PermissionResponseAction.DENY,
      );
    });
  });

  group('isPluginOwnOrigin', () {
    test('דף של התוסף: קובץ מקומי, סכימה ייעודית ושרת הקבצים המקומי', () {
      for (final origin in [
        'file:///C:/plugins/p1/index.html',
        'file:///home/u/plugins/p1/index.html',
        'file://', // כך Android מדווח על דף file://
        'otzaria-plugin://p1/index.html',
        'http://127.0.0.1:5123/f/p1/index.html',
        'http://localhost:5123/f/p1/index.html',
      ]) {
        expect(
          PluginWebViewPermissionGate.isPluginOwnOrigin(origin),
          isTrue,
          reason: origin,
        );
      }
    });

    test('אתר, מקור חסר או לא תקין — אינם דף של התוסף', () {
      for (final origin in [
        null,
        '',
        'https://localhost/',
        'https://example.com/',
        'http://localhost.evil.example/',
        'about:blank',
        'data:text/html,x',
        'blob:null/1',
        ':::',
      ]) {
        expect(
          PluginWebViewPermissionGate.isPluginOwnOrigin(origin),
          isFalse,
          reason: '$origin',
        );
      }
    });
  });

  group('respondGeolocation (Android)', () {
    const manifest = [pluginGeolocationPermission];
    const granted = {pluginGeolocationPermission: true};
    const origin = 'file://';

    Future<GeolocationPermissionShowPromptResponse> ask({
      List<String> declared = manifest,
      Map<String, bool> grants = granted,
      String requestOrigin = origin,
      Future<bool> Function()? os,
      bool throwOnRead = false,
    }) => PluginWebViewPermissionGate.respondGeolocation(
      plugin: _plugin(permissions: declared),
      origin: requestOrigin,
      registry: _FakeRegistry(grants: grants, throwOnRead: throwOnRead),
      ensureOsPermission: os ?? () async => true,
    );

    test('הוצהר, הוענק ואושר במערכת — מותר, ולא נשמר מעבר לדף', () async {
      final response = await ask();
      expect(response.allow, isTrue);
      expect(response.retain, isFalse, reason: 'כל בקשה נבדקת מחדש');
      expect(response.origin, origin);
    });

    test('אישור המערכת מתבקש רק אחרי שהשער אישר', () async {
      var asked = 0;
      Future<bool> os() async {
        asked++;
        return true;
      }

      await ask(grants: const {}, os: os);
      await ask(declared: const [], os: os);
      await ask(requestOrigin: 'https://example.com/', os: os);
      expect(asked, 0, reason: 'תוסף שנדחה לא מקפיץ חלון מערכת למשתמש');

      await ask(os: os);
      expect(asked, 1);
    });

    test('המשתמש סירב במערכת — נדחה', () async {
      expect((await ask(os: () async => false)).allow, isFalse);
    });

    test('כשל באישור המערכת או בקריאת ההענקה נדחה, ואינו זורק', () async {
      expect(
        (await ask(os: () async => throw StateError('no activity'))).allow,
        isFalse,
      );
      expect((await ask(throwOnRead: true)).allow, isFalse);
    });

    test('בלי הענקה או בלי הצהרה — נדחה', () async {
      expect((await ask(grants: const {})).allow, isFalse);
      expect((await ask(declared: const [])).allow, isFalse);
    });
  });

  group('declaresPermission', () {
    test('הרשאת בסיס נחשבת מוצהרת גם בלי רשומה במניפסט', () {
      expect(
        PluginWebViewPermissionGate.declaresPermission(
          _plugin(),
          pluginBaselinePermissions.first,
        ),
        isTrue,
      );
    });

    test('הצהרה ותיקה מכסה הרשאה שפוצלה ממנה', () {
      final legacy = pluginLegacyPermissionAliases.entries.first;
      expect(
        PluginWebViewPermissionGate.declaresPermission(
          _plugin(permissions: [legacy.value]),
          legacy.key,
        ),
        isTrue,
      );
    });
  });
}
