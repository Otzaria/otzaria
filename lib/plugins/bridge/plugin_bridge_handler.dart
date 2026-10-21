import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:otzaria/plugins/models/plugin_api_catalog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_rpc_request.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/models/plugin_rpc_response.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/database/plugin_database_service.dart';

class RateLimiter {
  int tokens = 50;
  DateTime lastRefill = DateTime.now();

  bool consume() {
    final now = DateTime.now();
    final diff = now.difference(lastRefill).inMilliseconds;
    tokens += diff ~/ 10;
    if (tokens > 50) tokens = 50;
    lastRefill = now;
    if (tokens > 0) {
      tokens--;
      return true;
    }
    return false;
  }
}

class PluginBridgeHandler {
  final InstalledPlugin plugin;
  final PluginBridgeAdapter adapter;
  final RateLimiter _rateLimiter;
  final PluginRegistryRepository _registry;

  /// תחילת RPC מחזירה פעולת סיום של אותו מופע ודף.
  final VoidCallback Function()? onWorkStarted;

  PluginBridgeHandler(
    this.plugin, {
    required this.adapter,
    PluginRegistryRepository? registry,
    RateLimiter? rateLimiter,
    this.onWorkStarted,
  }) : _registry = registry ?? PluginRegistryRepository(),
       _rateLimiter = rateLimiter ?? RateLimiter();

  /// סוד שמוזרק יחד עם ה-SDK ל-main frame בלבד ונדרש בכל קריאת RPC. iframe
  /// שהתוסף מטמיע (תוכן צד ג') מקבל את `callHandler` מהמנוע אך לא את הסוד,
  /// ולכן אינו יכול לקרוא ל-API בשם התוסף.
  final String bridgeNonce = _generateNonce();

  static final Random _nonceRandom = Random.secure();

  static String _generateNonce() => List<int>.generate(
    16,
    (_) => _nonceRandom.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  void register(InAppWebViewController controller) {
    // פינג חיוּת של ערוץ הגשר JS→Dart: השעיה נייטיבית של טאב עלולה להשאיר
    // את ה-JS חי אך את ערוץ callHandler מת — ואז eval רגיל ('1+1') מצליח
    // בעוד שתשובות RPC לא יגיעו לעולם. ה-handler הזה מאפשר ל-dispatcher
    // לבדוק את הערוץ עצמו לפני מסירת אירוע ממוקד לטאב שהוחיה.
    controller.addJavaScriptHandler(
      handlerName: 'otzaria_bridge_ping',
      callback: (args) => true,
    );
    controller.addJavaScriptHandler(
      handlerName: 'otzaria_rpc',
      callback: (args) async {
        return _handleRpc(
          args,
          eventSink: (topic, payload) async {
            await controller.evaluateJavascript(
              source:
                  'window.dispatchEvent(new CustomEvent('
                  '${jsonEncode(topic)}, { detail: ${jsonEncode(payload)} }));',
            );
          },
        );
      },
    );
  }

  /// נקודת כניסה לבדיקות בלבד: מריצה את אותו נתיב RPC שמופעל מ-JavaScript,
  /// כדי לבדוק את אכיפת ההרשאות וצימוד ההחרגה-מ-throttle ב-[_handleRpc].
  /// [nonce] מוחלף כברירת מחדל ב-[bridgeNonce] התקין — העברת ערך מפורש
  /// מדמה קריאה שמקורה מחוץ ל-main frame.
  @visibleForTesting
  Future<dynamic> handleRpcForTesting(
    List<dynamic> args, {
    PluginRpcEventSink? eventSink,
    String? nonce,
  }) {
    final first = args.isEmpty ? null : args.first;
    final stamped = first is Map
        ? [
            {...first, 'nonce': nonce ?? bridgeNonce},
            ...args.skip(1),
          ]
        : args;
    return _handleRpc(stamped, eventSink: eventSink);
  }

  /// ההרשאה שה-runtime אוכף בפועל עבור `domain.action`, לבדיקת התאמה מול
  /// המפה שהאריזה מסתמכת עליה. `null` = הקריאה אינה מגודרת במניפסט.
  @visibleForTesting
  String? requiredPermissionForTesting(String domain, String action) {
    final entry = methodPermissions['$domain.$action'];
    return entry == noManifestPermission ? null : entry;
  }

  /// קובע אם קריאת RPC מוחרגת ממגביל הקצב.
  ///
  /// `library.getBookContent` מחולקת מראש ל-chunks של 5000 תווים, כך שטעינת
  /// ספר מלא מחייבת מטבעה עשרות קריאות RPC רצופות. ספירתן במגביל הקצב מרוקנת
  /// את דלי הטוקנים ומחזירה rate_limited באמצע — מה שגרם לתוספים לקבל טקסט
  /// חתוך (חצי ספר). הקריאה לקריאה-בלבד ולכן מוחרגת.
  static bool isRateLimitExempt(String method) =>
      method == 'library.getBookContent';

  /// האם הקריאה מנהלת חסם זמן או משאבים בתוך השירות שלה,
  /// ולכן אינה כפופה ל-timeout הגנרי של 30 שניות.
  // feedback.report ממתין לדיאלוג אישור ללא הגבלה; timeout גנרי היה מחזיר
  // error.timeout אחרי שהדיווח כבר נשלח, וגורם לכפילות בניסיון חוזר.
  static bool hasOwnTimeout(String method) =>
      method == 'search.query' ||
      method == 'network.fetchStream' ||
      method == 'network.download' ||
      method == 'network.fetchFile' ||
      method == 'fs.extractZip' ||
      // כמו extractZip: תיקייה גדולה שנעה בין כרכי דיסק שונים נופלת להעתקה
      // רקורסיבית (ראה PluginFsService.moveEntry), שיכולה לארוך זמן.
      method == 'fs.moveEntry' ||
      // סריקת התיקיות האישיות היא I/O על הדיסק שתלוי בכמות הקבצים אצל
      // המשתמש; היא מנהלת חסם זמן משלה באדפטר.
      method == 'library.refreshUserBooks' ||
      // „שמור בשם” מחכה לדיאלוג של המערכת. timeout גנרי היה מחזיר
      // error.timeout בזמן שהמשתמש בוחר תיקייה, והתוסף היה חושב שהשמירה נכשלה
      // אחרי שהקובץ כבר נכתב.
      method == 'fs.commitUserFileWrite' ||
      // בחירת תיקייה ממתינה לדיאלוג המערכת, וה-grant שלה קבוע: timeout גנרי
      // היה מחזיר שגיאה לתוסף בזמן שהתיקייה עוד נשמרת אחרי שהמשתמש בחר.
      method == 'fs.pickUserFolder' ||
      // דיאלוג ההדפסה של המערכת ממתין לבחירת מדפסת ללא הגבלת זמן.
      method == 'ui.print' ||
      method == 'ui.printFile' ||
      method == 'ui.exportPdf' ||
      method == 'reader.printRange' ||
      method == 'ui.showConfirm' ||
      method == 'feedback.report' ||
      method == 'feedback.submitBookCorrection';

  Future<dynamic> _handleRpc(
    List<dynamic> args, {
    PluginRpcEventSink? eventSink,
  }) async {
    if (args.isEmpty) {
      return _errorResp("error.invalid_params", "No arguments provided");
    }

    final first = args.first;
    if (first is! Map) {
      return _errorResp("error.invalid_params", "Invalid RPC request format");
    }
    // בדיקת ה-nonce קודמת ל-onWorkStarted: אחרת iframe עוין שקורא בלולאה
    // מחזיק את מופע הרקע חי לנצח. הדחייה נספרת במגביל הקצב.
    if (first['nonce'] != bridgeNonce) {
      if (!_rateLimiter.consume()) {
        return _errorResp("error.rate_limited", "Rate limit exceeded");
      }
      return _errorResp("error.forbidden", "Bridge call is not authorized");
    }

    final method = first['method'];
    final parts = method is String ? method.split('.') : const <String>[];
    final endWork = onWorkStarted?.call();
    try {
      return await adapter.withWindowDependencies(
        () => _dispatchRpc(args, eventSink: eventSink),
        domain: parts.firstOrNull,
        rpcAction: parts.skip(1).join('.'),
      );
    } catch (error) {
      return _errorResp("error.internal", error.toString());
    } finally {
      endWork?.call();
    }
  }

  Future<dynamic> _dispatchRpc(
    List<dynamic> args, {
    PluginRpcEventSink? eventSink,
  }) async {
    late final PluginRpcRequest request;
    try {
      request = PluginRpcRequest.fromDynamic(args.first);
    } on FormatException catch (e) {
      return _errorResp("error.invalid_params", e.message);
    }

    if (!request.method.contains('.')) {
      return _errorResp("error.invalid_params", "Invalid method format");
    }

    final parts = request.method.split('.');
    final domain = parts[0];
    final action = parts[1];

    final permissionEntry = methodPermissions[request.method];
    if (permissionEntry == null) {
      if (!_rateLimiter.consume()) {
        return _errorResp("error.rate_limited", "Rate limit exceeded");
      }
      return _errorResp(
        "error.unknown_method",
        "Unknown method: ${request.method}",
      );
    }
    final requiredPermission = permissionEntry == noManifestPermission
        ? null
        : permissionEntry;
    final declaresPermission =
        requiredPermission == null ||
        pluginBaselinePermissions.contains(requiredPermission) ||
        plugin.manifest.permissions.contains(requiredPermission) ||
        plugin.manifest.permissions.contains(
          pluginLegacyPermissionAliases[requiredPermission],
        );

    // ההחרגה ממגביל הקצב חלה רק על קריאת תוכן שההרשאה לה *הוענקה בפועל* (לא רק
    // הוצהרה במניפסט). לכן בודקים את ההענקה כבר עכשיו עבור getBookContent —
    // תוסף ללא הרשאה מוענקת אינו עוקף את ה-throttle אלא עובר דרכו ומקבל
    // permission_denied. כדי לא להוסיף קריאת DB לכל RPC, ההקדמה הזו מתבצעת רק
    // לקריאות תוכן; שאר הקריאות נבדקות כרגיל בהמשך.
    final isContentRead = isRateLimitExempt(request.method);
    final isStreamCancellation =
        (request.method == 'search.query' ||
            request.method == 'network.fetchStream') &&
        PluginBridgeAdapter.isStreamCancellationPayload(request.payload);
    bool? grantedEarly;
    if (isContentRead && declaresPermission && requiredPermission != null) {
      grantedEarly =
          await _registry.getPermission(plugin.pluginId, requiredPermission) ==
          true;
    }

    final exempt =
        (isContentRead && (grantedEarly ?? false)) || isStreamCancellation;
    if (!exempt && !_rateLimiter.consume()) {
      return _errorResp("error.rate_limited", "Rate limit exceeded");
    }

    try {
      if (requiredPermission != null) {
        if (!declaresPermission) {
          return _errorResp(
            "permission_denied",
            "Missing permission: $requiredPermission",
          );
        }
        final granted =
            grantedEarly ??
            (await _registry.getPermission(
                  plugin.pluginId,
                  requiredPermission,
                ) ==
                true);
        if (!granted) {
          return _errorResp(
            "permission_denied",
            "Permission denied: $requiredPermission",
          );
        }
      }

      // פעולות ארוכות מנהלות בעצמן חסם זמן; היתר נחתכות אחרי 30 שניות.
      final execution = adapter.execute(
        domain,
        action,
        request.payload,
        eventSink: eventSink,
      );
      final result = hasOwnTimeout(request.method)
          ? await execution
          : await execution.timeout(const Duration(seconds: 30));
      return _successResp(result);
    } on PluginDatabaseException catch (e) {
      return _errorResp(e.code, e.message);
    } on TimeoutException {
      PluginSystemDatabase.instance.writeLog(
        plugin.pluginId,
        'ERROR',
        'RPC timeout: $domain.$action',
      );
      return _errorResp("error.timeout", "Request timed out");
    } catch (e) {
      PluginSystemDatabase.instance.writeLog(
        plugin.pluginId,
        'ERROR',
        'RPC error $domain.$action: $e',
      );
      // ה-adapter מקדד את קוד השגיאה בתחילת הודעת ה-Exception בפורמט
      // `error.<code>: <detail>` (למשל error.forbidden, error.invalid_params).
      // ה-RPC חושף שדה `code` נפרד שתוספים מסתמכים עליו (ראה
      // docs/plugin-sdk/API_REFERENCE.md), לכן מחלצים את הקוד ומחזירים אותו
      // כ-code במקום לקבע את הכל ל-error.internal. הודעות ללא קידומת מוכרת
      // נשארות error.internal.
      final match = _codedErrorPattern.firstMatch(e.toString());
      if (match != null) {
        return _errorResp(match.group(1)!, match.group(2)!);
      }
      return _errorResp("error.internal", e.toString());
    }
  }

  /// תבנית לחילוץ קוד שגיאה מקודד מהודעת Exception של ה-adapter, בפורמט
  /// `error.<code>: <detail>` (עם או בלי הקידומת `Exception: ` ש-[Object.toString]
  /// מוסיף). שומר על אותה רשימת קודים שה-API מבטיח לתוספים.
  static final RegExp _codedErrorPattern = RegExp(
    r'^(?:Exception: )?(error\.[a-z_]+): (.*)$',
    dotAll: true,
  );

  static const String noManifestPermission = pluginApiNoManifestPermission;

  /// שיטה שאינה בקטלוג נדחית לפני הפעלת האדפטר.
  static final Map<String, String> methodPermissions =
      pluginApiMethodPermissions;

  Map<String, dynamic> _successResp(dynamic data) {
    return PluginRpcResponse.success(data).toJson();
  }

  Map<String, dynamic> _errorResp(String code, String message) {
    return PluginRpcResponse.error(code: code, message: message).toJson();
  }
}
