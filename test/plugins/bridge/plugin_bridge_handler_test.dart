import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';

/// adapter פיקטיבי: מיישם רק את execute (השאר דרך noSuchMethod), סופר קריאות
/// ומחזיר ערך מוגדר מראש — כך אפשר לוודא אם execute נקרא בכלל ובאילו ארגומנטים.
class _FakeAdapter implements PluginBridgeAdapter {
  _FakeAdapter({this.result, this.errorToThrow});

  final dynamic result;

  /// אם מוגדר — execute יזרוק את החריגה הזו במקום להחזיר [result].
  final Object? errorToThrow;
  int executeCalls = 0;
  String? lastDomain;
  String? lastAction;

  @override
  Future<dynamic> execute(
    String domain,
    String action,
    Map<String, dynamic> args, {
    PluginRpcEventSink? eventSink,
  }) async {
    executeCalls++;
    lastDomain = domain;
    lastAction = action;
    if (errorToThrow != null) throw errorToThrow!;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// registry שמחזיר ערך הרשאה קבוע ל-getPermission, בלי גישה ל-DB.
class _StubRegistry extends PluginRegistryRepository {
  _StubRegistry(this.grantValue);

  /// הערך שיוחזר מ-getPermission: true=הוענקה, false=נדחתה, null=לא הוגדרה.
  final bool? grantValue;

  @override
  Future<bool?> getPermission(String pluginId, String permission) async {
    return grantValue;
  }
}

/// RateLimiter שתמיד חוסם וסופר כמה פעמים נקרא — לבדיקת צימוד throttle/הרשאה
/// בלי תלות בתזמון (consume אמיתי מתחדש לפי שעון).
class _BlockingRateLimiter extends RateLimiter {
  int consumeCalls = 0;

  @override
  bool consume() {
    consumeCalls++;
    return false;
  }
}

InstalledPlugin _buildInstalledPlugin({List<String> permissions = const []}) {
  return InstalledPlugin(
    pluginId: 'test.plugin',
    name: 'Test Plugin',
    version: '1.0.0',
    installPath: '/',
    entrypointPath: 'index.html',
    enabled: true,
    pinned: true,
    manifest: PluginManifest(
      schemaVersion: 1,
      id: 'test.plugin',
      name: 'Test Plugin',
      version: '1.0.0',
      description: '',
      author: '',
      homepage: '',
      entrypoint: 'index.html',
      minAppVersion: '1.0.0',
      sdkVersion: '1.x',
      permissions: permissions,
      networkEnabled: false,
      networkAllowlist: const [],
      toolTabTitle: 'Test Plugin',
      toolTabOrder: 1,
      defaultPinned: true,
      publishedDataTypes: const [],
    ),
    installedAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

/// בקשת RPC ל-getBookContent (הקריאה היחידה המוחרגת ממגביל הקצב).
List<dynamic> _getBookContentRequest() => [
  {
    'method': 'library.getBookContent',
    'payload': {'bookId': 'ספר-כלשהו'},
  },
];

/// בקשת RPC ל-shortcut.create.
List<dynamic> _shortcutCreateRequest() => [
  {
    'method': 'shortcut.create',
    'payload': {'label': 'בדיקה'},
  },
];

/// בקשת RPC ל-plugin.openOther.
List<dynamic> _openOtherRequest() => [
  {
    'method': 'plugin.openOther',
    'payload': {'pluginId': 'other.plugin'},
  },
];

/// בקשת RPC ל-feedback.report.
List<dynamic> _feedbackReportRequest() => [
  {
    'method': 'feedback.report',
    'payload': {'details': 'התוסף קורס'},
  },
];

/// בקשת RPC ל-feedback.sendEmail.
List<dynamic> _feedbackSendEmailRequest() => [
  {
    'method': 'feedback.sendEmail',
    'payload': {'to': 'a@b.c', 'subject': 'x', 'body': 'y'},
  },
];

/// בקשת RPC ל-app.openUrl.
List<dynamic> _openUrlRequest() => [
  {
    'method': 'app.openUrl',
    'payload': {'url': 'https://example.com'},
  },
];

/// בקשת RPC ל-app.getConnectivity.
List<dynamic> _getConnectivityRequest() => [
  {'method': 'app.getConnectivity', 'payload': <String, dynamic>{}},
];

List<dynamic> _cancelSearchRequest({bool includeExtraKey = false}) => [
  {
    'method': 'search.query',
    'payload': {
      '__cancelStreamId': 'search_test_1',
      if (includeExtraKey) 'query': 'בדיקה',
    },
  },
];

List<dynamic> _cancelNetworkFetchRequest({bool includeExtraKey = false}) => [
  {
    'method': 'network.fetchStream',
    'payload': {
      '__cancelStreamId': 'network_test_1',
      if (includeExtraKey) 'url': 'https://example.com',
    },
  },
];

void main() {
  group('PluginBridgeHandler.isRateLimitExempt', () {
    test('library.getBookContent מוחרג ממגביל הקצב', () {
      // טעינת ספר מלא מחולקת ל-chunks ומחייבת עשרות קריאות רצופות; ספירתן
      // במגביל הקצב חתכה את הטעינה באמצע (חצי ספר).
      expect(
        PluginBridgeHandler.isRateLimitExempt('library.getBookContent'),
        isTrue,
      );
    });

    test('קריאות אחרות אינן מוחרגות וממשיכות להיות מוגבלות', () {
      expect(
        PluginBridgeHandler.isRateLimitExempt('library.getBookToc'),
        isFalse,
      );
      expect(PluginBridgeHandler.isRateLimitExempt('library.getTree'), isFalse);
      expect(PluginBridgeHandler.isRateLimitExempt('storage.set'), isFalse);
      expect(
        PluginBridgeHandler.isRateLimitExempt('reader.setHighlight'),
        isFalse,
      );
      expect(PluginBridgeHandler.isRateLimitExempt(''), isFalse);
    });
  });

  group('PluginBridgeHandler.hasOwnTimeout', () {
    test('פעולות עם timeout פנימי מוחרגות מ-timeout ברירת המחדל', () {
      // פעולות I/O ארוכות שנחתכו על קבצים גדולים ע"י ה-30 שניות.
      expect(PluginBridgeHandler.hasOwnTimeout('search.query'), isTrue);
      expect(PluginBridgeHandler.hasOwnTimeout('network.fetch'), isTrue);
      expect(PluginBridgeHandler.hasOwnTimeout('network.fetchStream'), isTrue);
      expect(PluginBridgeHandler.hasOwnTimeout('network.download'), isTrue);
      expect(PluginBridgeHandler.hasOwnTimeout('fs.extractZip'), isTrue);
      // ממתין לדיאלוג אישור — timeout גנרי היה מדווח כשל אחרי שליחה בפועל.
      expect(PluginBridgeHandler.hasOwnTimeout('feedback.report'), isTrue);
    });

    test('שאר הקריאות נשארות תחת timeout ברירת המחדל', () {
      expect(PluginBridgeHandler.hasOwnTimeout('fs.deleteFile'), isFalse);
      expect(
        PluginBridgeHandler.hasOwnTimeout('library.getBookContent'),
        isFalse,
      );
      expect(PluginBridgeHandler.hasOwnTimeout(''), isFalse);
    });
  });

  group('RateLimiter', () {
    test('מתחיל עם 50 טוקנים וחוסם לאחר שהם נגמרים בפרץ אחד', () {
      final limiter = RateLimiter();
      var allowed = 0;
      // פרץ מיידי של 60 קריאות: 50 הראשונות אמורות לעבור, השאר להיחסם
      // (הטוקנים מתחדשים רק ~1 כל 10ms, וכאן אין שהייה ביניהן).
      for (var i = 0; i < 60; i++) {
        if (limiter.consume()) allowed++;
      }
      expect(allowed, lessThanOrEqualTo(51));
      expect(allowed, greaterThanOrEqualTo(50));
    });
  });

  // אכיפת ההרשאות ב-_handleRpc עצמו — לא רק שה-helper הסטטי מחזיר true.
  // getBookContent דורש את ההרשאה 'library.content.read', וההחרגה ממגביל הקצב
  // מותנית בכך שההרשאה *הוענקה בפועל* (ראה ההערה ב-plugin_bridge_handler.dart).
  group('PluginBridgeHandler._handleRpc — אכיפת הרשאות', () {
    const contentPermission = 'library.content.read';

    PluginBridgeHandler buildHandler({
      required List<String> declaredPermissions,
      required bool? granted,
      required _FakeAdapter adapter,
      RateLimiter? rateLimiter,
    }) {
      return PluginBridgeHandler(
        _buildInstalledPlugin(permissions: declaredPermissions),
        adapter: adapter,
        registry: _StubRegistry(granted),
        rateLimiter: rateLimiter,
      );
    }

    test(
      'הרשאה הוצהרה אך לא הוענקה → permission_denied, adapter.execute לא נקרא',
      () async {
        final adapter = _FakeAdapter();
        final handler = buildHandler(
          declaredPermissions: const [contentPermission],
          granted: false,
          adapter: adapter,
        );

        final resp =
            await handler.handleRpcForTesting(_getBookContentRequest())
                as Map<String, dynamic>;

        expect(resp['success'], isFalse);
        expect(resp['error']['code'], 'permission_denied');
        expect(adapter.executeCalls, 0);
      },
    );

    test(
      'הרשאה לא הוצהרה כלל במניפסט → permission_denied, execute לא נקרא',
      () async {
        final adapter = _FakeAdapter();
        final handler = buildHandler(
          declaredPermissions: const [], // המניפסט ריק
          granted: true, // גם אם ה-DB היה מאשר — ההצהרה חסרה
          adapter: adapter,
        );

        final resp =
            await handler.handleRpcForTesting(_getBookContentRequest())
                as Map<String, dynamic>;

        expect(resp['success'], isFalse);
        expect(resp['error']['code'], 'permission_denied');
        expect(adapter.executeCalls, 0);
      },
    );

    test('shortcut.create ללא ui.create_shortcut במניפסט → permission_denied, '
        'execute לא נקרא', () async {
      // מוודא ש-domain shortcut נאכף בשכבת ה-RPC (לא רק ב-adapter): תוסף שלא
      // הצהיר על ui.create_shortcut נחסם לפני adapter.execute, גם אם ה-DB מאשר.
      final adapter = _FakeAdapter();
      final handler = buildHandler(
        declaredPermissions: const [],
        granted: true,
        adapter: adapter,
      );

      final resp =
          await handler.handleRpcForTesting(_shortcutCreateRequest())
              as Map<String, dynamic>;

      expect(resp['success'], isFalse);
      expect(resp['error']['code'], 'permission_denied');
      expect(adapter.executeCalls, 0);
    });

    test(
      'plugin.openOther עם navigation.write בלבד → permission_denied',
      () async {
        // openSelf מסתפק ב-navigation.write; פתיחת תוסף אחר דורשת הרשאה נפרדת,
        // ולכן תוסף ותיק שהצהיר רק על ניווט אינו מקבל אותה בירושה.
        final adapter = _FakeAdapter();
        final handler = buildHandler(
          declaredPermissions: const ['navigation.write'],
          granted: true,
          adapter: adapter,
        );

        final resp =
            await handler.handleRpcForTesting(_openOtherRequest())
                as Map<String, dynamic>;

        expect(resp['success'], isFalse);
        expect(resp['error']['code'], 'permission_denied');
        expect(adapter.executeCalls, 0);
      },
    );

    test(
      'plugin.openOther עם plugin.open_other מוצהרת ומוענקת → execute נקרא',
      () async {
        final adapter = _FakeAdapter(result: true);
        final handler = buildHandler(
          declaredPermissions: const [pluginOpenOtherPermission],
          granted: true,
          adapter: adapter,
        );

        final resp =
            await handler.handleRpcForTesting(_openOtherRequest())
                as Map<String, dynamic>;

        expect(resp['success'], isTrue);
        expect(adapter.lastDomain, 'plugin');
        expect(adapter.lastAction, 'openOther');
      },
    );

    test('feedback.report ללא הרשאה כלשהי במניפסט → execute נקרא', () async {
      // גבול האבטחה של report הוא דיאלוג האישור של המשתמש, ולכן היא אינה
      // דורשת הרשאת manifest — בשונה מ-feedback.sendEmail.
      final adapter = _FakeAdapter(result: true);
      final handler = buildHandler(
        declaredPermissions: const [],
        granted: null,
        adapter: adapter,
      );

      final resp =
          await handler.handleRpcForTesting(_feedbackReportRequest())
              as Map<String, dynamic>;

      expect(resp['success'], isTrue);
      expect(adapter.executeCalls, 1);
      expect(adapter.lastDomain, 'feedback');
      expect(adapter.lastAction, 'report');
    });

    test('feedback.hasReporterEmail ללא הרשאה כלשהי → execute נקרא', () async {
      final adapter = _FakeAdapter(result: false);
      final handler = buildHandler(
        declaredPermissions: const [],
        granted: null,
        adapter: adapter,
      );

      final resp =
          await handler.handleRpcForTesting([
                {'method': 'feedback.hasReporterEmail', 'payload': {}},
              ])
              as Map<String, dynamic>;

      expect(resp['success'], isTrue);
      expect(adapter.executeCalls, 1);
      expect(adapter.lastAction, 'hasReporterEmail');
    });

    test('feedback.sendEmail עדיין דורשת feedback.send_email', () async {
      final adapter = _FakeAdapter(result: true);
      final handler = buildHandler(
        declaredPermissions: const [],
        granted: true,
        adapter: adapter,
      );

      final resp =
          await handler.handleRpcForTesting(_feedbackSendEmailRequest())
              as Map<String, dynamic>;

      expect(resp['success'], isFalse);
      expect(resp['error']['code'], 'permission_denied');
      expect(adapter.executeCalls, 0);
    });

    test('app.openUrl ללא app.open_url במניפסט → permission_denied, '
        'execute לא נקרא', () async {
      final adapter = _FakeAdapter();
      final handler = buildHandler(
        declaredPermissions: const [],
        granted: true,
        adapter: adapter,
      );

      final resp =
          await handler.handleRpcForTesting(_openUrlRequest())
              as Map<String, dynamic>;

      expect(resp['success'], isFalse);
      expect(resp['error']['code'], 'permission_denied');
      expect(adapter.executeCalls, 0);
    });

    test('app.openUrl עם app.open_url מוצהרת ומוענקת → execute נקרא', () async {
      final adapter = _FakeAdapter(result: true);
      final handler = buildHandler(
        declaredPermissions: const ['app.open_url'],
        granted: true,
        adapter: adapter,
      );

      final resp =
          await handler.handleRpcForTesting(_openUrlRequest())
              as Map<String, dynamic>;

      expect(resp['success'], isTrue);
      expect(adapter.executeCalls, 1);
      expect(adapter.lastDomain, 'app');
      expect(adapter.lastAction, 'openUrl');
    });

    test(
      'app.getConnectivity ללא הצהרה → מותר (app.info.read הרשאת בסיס)',
      () async {
        final adapter = _FakeAdapter(
          result: const {
            'isOfflineMode': false,
            'hasNetwork': true,
            'isOnline': true,
          },
        );
        final handler = buildHandler(
          declaredPermissions: const [],
          granted: true,
          adapter: adapter,
        );

        final resp =
            await handler.handleRpcForTesting(_getConnectivityRequest())
                as Map<String, dynamic>;

        expect(resp['success'], isTrue);
        expect(adapter.executeCalls, 1);
      },
    );

    test('app.getConnectivity עם app.info.read → execute נקרא', () async {
      final adapter = _FakeAdapter(
        result: const {
          'isOfflineMode': false,
          'hasNetwork': true,
          'isOnline': true,
        },
      );
      final handler = buildHandler(
        declaredPermissions: const ['app.info.read'],
        granted: true,
        adapter: adapter,
      );

      final resp =
          await handler.handleRpcForTesting(_getConnectivityRequest())
              as Map<String, dynamic>;

      expect(resp['success'], isTrue);
      expect(adapter.lastDomain, 'app');
      expect(adapter.lastAction, 'getConnectivity');
      expect(resp['data']['isOnline'], isTrue);
    });

    test('הרשאה הוצהרה והוענקה → הצלחה, adapter.execute נקרא', () async {
      final adapter = _FakeAdapter(result: 'תוכן-הספר');
      final handler = buildHandler(
        declaredPermissions: const [contentPermission],
        granted: true,
        adapter: adapter,
      );

      final resp =
          await handler.handleRpcForTesting(_getBookContentRequest())
              as Map<String, dynamic>;

      expect(resp['success'], isTrue);
      expect(resp['data'], 'תוכן-הספר');
      expect(adapter.executeCalls, 1);
      expect(adapter.lastDomain, 'library');
      expect(adapter.lastAction, 'getBookContent');
    });

    test(
      'ההחרגה ממגביל הקצב חלה רק כשההרשאה הוענקה: מגביל מרוקן + הרשאה מוענקת '
      '→ עדיין מצליח (consume לא נקרא)',
      () async {
        // grantedEarly=true ⇒ exempt=true ⇒ הקוד לא קורא ל-consume כלל.
        final adapter = _FakeAdapter(result: 'תוכן');
        final limiter = _BlockingRateLimiter();
        final handler = buildHandler(
          declaredPermissions: const [contentPermission],
          granted: true,
          adapter: adapter,
          rateLimiter: limiter,
        );

        final resp =
            await handler.handleRpcForTesting(_getBookContentRequest())
                as Map<String, dynamic>;

        expect(
          resp['success'],
          isTrue,
          reason: 'getBookContent עם הרשאה מוענקת מוחרג ממגביל הקצב',
        );
        expect(
          limiter.consumeCalls,
          0,
          reason: 'נתיב מוחרג לא אמור לגעת במגביל הקצב בכלל',
        );
      },
    );

    test('ביטול stream תקין עוקף throttle אך עדיין דורש הרשאת חיפוש', () async {
      final adapter = _FakeAdapter(result: const {'cancelled': true});
      final limiter = _BlockingRateLimiter();
      final handler = buildHandler(
        declaredPermissions: const ['search.fulltext.read'],
        granted: true,
        adapter: adapter,
        rateLimiter: limiter,
      );

      final resp =
          await handler.handleRpcForTesting(_cancelSearchRequest())
              as Map<String, dynamic>;

      expect(resp['success'], isTrue);
      expect(adapter.executeCalls, 1);
      expect(limiter.consumeCalls, 0);

      final deniedAdapter = _FakeAdapter();
      final denied = buildHandler(
        declaredPermissions: const ['search.fulltext.read'],
        granted: false,
        adapter: deniedAdapter,
        rateLimiter: _BlockingRateLimiter(),
      );
      final deniedResp =
          await denied.handleRpcForTesting(_cancelSearchRequest()) as Map;
      expect(deniedResp['error']['code'], 'permission_denied');
      expect(deniedAdapter.executeCalls, 0);
    });

    test('payload דמוי ביטול עם מפתח נוסף אינו עוקף throttle', () async {
      final adapter = _FakeAdapter();
      final limiter = _BlockingRateLimiter();
      final handler = buildHandler(
        declaredPermissions: const ['search.fulltext.read'],
        granted: true,
        adapter: adapter,
        rateLimiter: limiter,
      );

      final resp =
          await handler.handleRpcForTesting(
                _cancelSearchRequest(includeExtraKey: true),
              )
              as Map<String, dynamic>;

      expect(resp['error']['code'], 'error.rate_limited');
      expect(adapter.executeCalls, 0);
      expect(limiter.consumeCalls, 1);
    });

    test('רק payload ביטול מדויק של fetchStream עוקף throttle', () async {
      final adapter = _FakeAdapter(result: const {'cancelled': true});
      final limiter = _BlockingRateLimiter();
      final handler = buildHandler(
        declaredPermissions: const [],
        granted: null,
        adapter: adapter,
        rateLimiter: limiter,
      );

      final cancelled =
          await handler.handleRpcForTesting(_cancelNetworkFetchRequest())
              as Map<String, dynamic>;
      expect(cancelled['success'], isTrue);
      expect(adapter.executeCalls, 1);
      expect(limiter.consumeCalls, 0);

      final fakeCancellation =
          await handler.handleRpcForTesting(
                _cancelNetworkFetchRequest(includeExtraKey: true),
              )
              as Map<String, dynamic>;
      expect(fakeCancellation['error']['code'], 'error.rate_limited');
      expect(adapter.executeCalls, 1);
      expect(limiter.consumeCalls, 1);
    });

    test('תוסף ללא הרשאה מוענקת אינו עוקף את ה-throttle: מגביל מרוקן + הרשאה לא '
        'מוענקת → rate_limited (עובר דרך המגביל)', () async {
      // grantedEarly=false ⇒ exempt=false ⇒ הקריאה עוברת דרך consume, שמרוקן
      // ולכן חוסם. כך תוסף לא-מורשה לא מנצל את ההחרגה כדי לעקוף את ה-throttle.
      final adapter = _FakeAdapter();
      final limiter = _BlockingRateLimiter();
      final handler = buildHandler(
        declaredPermissions: const [contentPermission],
        granted: false,
        adapter: adapter,
        rateLimiter: limiter,
      );

      final resp =
          await handler.handleRpcForTesting(_getBookContentRequest())
              as Map<String, dynamic>;

      expect(resp['success'], isFalse);
      expect(resp['error']['code'], 'error.rate_limited');
      expect(
        limiter.consumeCalls,
        1,
        reason: 'תוסף לא-מורשה חייב לעבור דרך מגביל הקצב, לא לעקוף אותו',
      );
      expect(adapter.executeCalls, 0);
    });
  });

  // ה-adapter מקדד את קוד השגיאה בהודעת ה-Exception (error.<code>: detail).
  // ה-RPC חייב לחשוף אותו כ-code כפי ש-API_REFERENCE.md מבטיח לתוספים — ולא
  // לקבע הכל ל-error.internal. הטסטים האלה רצים על נתיב ה-RPC המלא (לא על
  // adapter.execute ישירות) כי שם מתבצע המיפוי.
  group('PluginBridgeHandler._handleRpc — מיפוי קודי שגיאה מ-adapter', () {
    // fs.* אינו דורש הרשאת manifest, לכן הקריאה מגיעה ל-execute ללא חסימה.
    List<dynamic> fsDeleteRequest() => [
      {
        'method': 'fs.deleteFile',
        'payload': {'path': '/tmp/x'},
      },
    ];

    PluginBridgeHandler buildHandler(_FakeAdapter adapter) {
      return PluginBridgeHandler(
        _buildInstalledPlugin(),
        adapter: adapter,
        registry: _StubRegistry(true),
      );
    }

    test(
      'Exception עם קידומת error.forbidden מוחזר עם code=error.forbidden',
      () async {
        final handler = buildHandler(
          _FakeAdapter(
            errorToThrow: Exception(
              'error.forbidden: path outside a user-selected folder',
            ),
          ),
        );

        final resp =
            await handler.handleRpcForTesting(fsDeleteRequest()) as Map;

        expect(resp['success'], isFalse);
        expect(resp['error']['code'], 'error.forbidden');
        expect(resp['error']['message'], 'path outside a user-selected folder');
        expect(resp['error']['schemaVersion'], 1);
        expect(resp['error']['retryable'], isFalse);
        expect(resp['error']['category'], 'permission');
      },
    );

    test(
      'קידומת error.invalid_params ו-error.not_found ממופות גם הן',
      () async {
        final invalid =
            await buildHandler(
                  _FakeAdapter(
                    errorToThrow: Exception(
                      'error.invalid_params: path required',
                    ),
                  ),
                ).handleRpcForTesting(fsDeleteRequest())
                as Map;
        expect(invalid['error']['code'], 'error.invalid_params');

        final notFound =
            await buildHandler(
                  _FakeAdapter(
                    errorToThrow: Exception(
                      'error.not_found: zip file does not exist',
                    ),
                  ),
                ).handleRpcForTesting(fsDeleteRequest())
                as Map;
        expect(notFound['error']['code'], 'error.not_found');
      },
    );

    test('Exception ללא קידומת מוכרת נשאר error.internal', () async {
      final handler = buildHandler(
        _FakeAdapter(errorToThrow: Exception('משהו נשבר')),
      );

      final resp = await handler.handleRpcForTesting(fsDeleteRequest()) as Map;

      expect(resp['error']['code'], 'error.internal');
    });

    test(
      'TimeoutException פנימי של search.query מוחזר כ-error.timeout',
      () async {
        final handler = PluginBridgeHandler(
          _buildInstalledPlugin(
            permissions: const ['search.fulltext.read'],
          ),
          adapter: _FakeAdapter(errorToThrow: TimeoutException('search')),
          registry: _StubRegistry(true),
        );

        final resp =
            await handler.handleRpcForTesting([
                  {
                    'method': 'search.query',
                    'payload': {
                      'query': 'בדיקה',
                      '__streamId': 'search_test_1',
                    },
                  },
                ])
                as Map;

        expect(resp['success'], isFalse);
        expect(resp['error']['code'], 'error.timeout');
      },
    );
  });

  // פעולות הקבצים האישיים (pickUserFile וכו') דורשות הרשאת manifest
  // 'fs.user_files.read', בניגוד ל-extractZip/deleteFile שמגודרות בתיקייה
  // שהמשתמש בחר ולכן אינן דורשות הרשאה.
  group('PluginBridgeHandler._handleRpc — אכיפת fs.user_files.read', () {
    List<dynamic> pickUserFileRequest() => [
      {'method': 'fs.pickUserFile', 'payload': const <String, dynamic>{}},
    ];

    test(
      'pickUserFile ללא ההרשאה במניפסט → permission_denied, execute לא נקרא',
      () async {
        final adapter = _FakeAdapter();
        final handler = PluginBridgeHandler(
          _buildInstalledPlugin(permissions: const []),
          adapter: adapter,
          registry: _StubRegistry(true), // גם אם ה-DB מאשר — ההצהרה חסרה
        );

        final resp =
            await handler.handleRpcForTesting(pickUserFileRequest()) as Map;

        expect(resp['success'], isFalse);
        expect(resp['error']['code'], 'permission_denied');
        expect(adapter.executeCalls, 0);
      },
    );

    test('pickUserFile עם הרשאה מוצהרת ומוענקת → execute נקרא', () async {
      final adapter = _FakeAdapter(result: {'cancelled': true});
      final handler = PluginBridgeHandler(
        _buildInstalledPlugin(permissions: const ['fs.user_files.read']),
        adapter: adapter,
        registry: _StubRegistry(true),
      );

      final resp =
          await handler.handleRpcForTesting(pickUserFileRequest()) as Map;

      expect(resp['success'], isTrue);
      expect(adapter.executeCalls, 1);
      expect(adapter.lastDomain, 'fs');
      expect(adapter.lastAction, 'pickUserFile');
    });

    test('כתיבה דורשת fs.user_files.write, ולא מספיקה הרשאת קריאה', () async {
      for (final method in ['fs.beginBinaryWrite', 'fs.commitUserFileWrite']) {
        final adapter = _FakeAdapter();
        final handler = PluginBridgeHandler(
          // קריאה בלבד: מי שמצהיר על read אינו יכול לכתוב.
          _buildInstalledPlugin(permissions: const ['fs.user_files.read']),
          adapter: adapter,
          registry: _StubRegistry(true),
        );

        final resp =
            await handler.handleRpcForTesting([
                  {'method': method, 'payload': const <String, dynamic>{}},
                ])
                as Map;

        expect(resp['success'], isFalse, reason: method);
        expect(resp['error']['code'], 'permission_denied', reason: method);
        expect(adapter.executeCalls, 0, reason: method);
      }
    });

    test('כתיבה עם ההרשאה המוצהרת והמוענקת → execute נקרא', () async {
      final adapter = _FakeAdapter(result: {'cancelled': true});
      final handler = PluginBridgeHandler(
        _buildInstalledPlugin(
          permissions: const ['fs.user_files.read', 'fs.user_files.write'],
        ),
        adapter: adapter,
        registry: _StubRegistry(true),
      );

      final resp =
          await handler.handleRpcForTesting([
                {
                  'method': 'fs.commitUserFileWrite',
                  'payload': {'writeToken': 'x'},
                },
              ])
              as Map;

      expect(resp['success'], isTrue);
      expect(adapter.lastAction, 'commitUserFileWrite');
    });

    test('commitUserFileWrite אינו כפוף ל-timeout הגנרי', () {
      // הוא ממתין לדיאלוג „שמור בשם”; timeout גנרי היה מחזיר error.timeout
      // בזמן שהמשתמש בוחר תיקייה, אחרי שהבייטים כבר עלו.
      expect(PluginBridgeHandler.hasOwnTimeout('fs.commitUserFileWrite'), isTrue);
      expect(PluginBridgeHandler.hasOwnTimeout('fs.beginBinaryWrite'), isFalse);
    });

    test(
      'deleteFile נשאר ללא הרשאת manifest (execute נקרא גם בלי הרשאה)',
      () async {
        final adapter = _FakeAdapter(result: true);
        final handler = PluginBridgeHandler(
          _buildInstalledPlugin(permissions: const []),
          adapter: adapter,
          registry: _StubRegistry(null),
        );

        final resp =
            await handler.handleRpcForTesting([
                  {
                    'method': 'fs.deleteFile',
                    'payload': {'path': '/tmp/x'},
                  },
                ])
                as Map;

        expect(resp['success'], isTrue);
        expect(adapter.executeCalls, 1);
      },
    );
  });

  // iframe עוין יכול לקרוא ל-otzaria_rpc בלי ה-nonce; אסור שקריאה כזו תסמן
  // "עבודה התחילה" (מחזיק מופע רקע חי) או תעקוף את מגביל הקצב.
  group('PluginBridgeHandler — דחייה לפני onWorkStarted', () {
    test('קריאה ללא nonce תקין אינה מסמנת תחילת עבודה ונספרת במגביל', () async {
      var workStarted = 0;
      final limiter = _BlockingRateLimiter();
      final handler = PluginBridgeHandler(
        _buildInstalledPlugin(),
        adapter: _FakeAdapter(),
        registry: _StubRegistry(true),
        rateLimiter: limiter,
        onWorkStarted: () => workStarted++,
      );

      final resp =
          await handler.handleRpcForTesting(
                _getBookContentRequest(),
                nonce: 'wrong-nonce',
              )
              as Map<String, dynamic>;

      expect(resp['error']['code'], 'error.rate_limited');
      expect(limiter.consumeCalls, 1);
      expect(workStarted, 0);
    });

    test('קריאה עם nonce תקין מסמנת תחילת עבודה וסיומה', () async {
      var workStarted = 0;
      var workEnded = 0;
      final handler = PluginBridgeHandler(
        _buildInstalledPlugin(permissions: const ['library.content.read']),
        adapter: _FakeAdapter(result: const {'ok': true}),
        registry: _StubRegistry(true),
        onWorkStarted: () => workStarted++,
        onWorkEnded: () => workEnded++,
      );

      await handler.handleRpcForTesting(_getBookContentRequest());

      expect(workStarted, 1);
      expect(workEnded, 1);
    });

    test('method לא מוכר נספר במגביל הקצב', () async {
      final limiter = _BlockingRateLimiter();
      final handler = PluginBridgeHandler(
        _buildInstalledPlugin(),
        adapter: _FakeAdapter(),
        registry: _StubRegistry(true),
        rateLimiter: limiter,
      );

      final resp =
          await handler.handleRpcForTesting([
                {'method': 'no.such_method', 'payload': {}},
              ])
              as Map<String, dynamic>;

      expect(resp['error']['code'], 'error.rate_limited');
      expect(limiter.consumeCalls, 1);
    });
  });
}
