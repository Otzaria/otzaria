import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_rpc_request.dart';
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

  PluginBridgeHandler(
    this.plugin, {
    required this.adapter,
    PluginRegistryRepository? registry,
    RateLimiter? rateLimiter,
  }) : _registry = registry ?? PluginRegistryRepository(),
       _rateLimiter = rateLimiter ?? RateLimiter();

  void register(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'otzaria_rpc',
      callback: _handleRpc,
    );
  }

  /// נקודת כניסה לבדיקות בלבד: מריצה את אותו נתיב RPC שמופעל מ-JavaScript,
  /// כדי לבדוק את אכיפת ההרשאות וצימוד ההחרגה-מ-throttle ב-[_handleRpc].
  @visibleForTesting
  Future<dynamic> handleRpcForTesting(List<dynamic> args) => _handleRpc(args);

  /// קובע אם קריאת RPC מוחרגת ממגביל הקצב.
  ///
  /// `library.getBookContent` מחולקת מראש ל-chunks של 5000 תווים, כך שטעינת
  /// ספר מלא מחייבת מטבעה עשרות קריאות RPC רצופות. ספירתן במגביל הקצב מרוקנת
  /// את דלי הטוקנים ומחזירה rate_limited באמצע — מה שגרם לתוספים לקבל טקסט
  /// חתוך (חצי ספר). הקריאה לקריאה-בלבד ולכן מוחרגת.
  static bool isRateLimitExempt(String method) =>
      method == 'library.getBookContent';

  /// קובע אם קריאת RPC מוחרגת מ-timeout ברירת המחדל של 30 שניות.
  ///
  /// `network.download` ו-`fs.extractZip` הן פעולות I/O ארוכות מטבען (הזרמת
  /// קובץ לדיסק, חילוץ ארכיון), ו-30 שניות חתכו אותן באמצע על קבצים גדולים.
  /// ההורדה אוכפת timeout על *תקיעה* (היעדר בייטים נכנסים) בתוך שירות ההורדה,
  /// כך שהורדה איטית נמשכת כל עוד יש התקדמות; החילוץ אוכף בתוך השירות תקרת גודל
  /// מחולץ ומספר רשומות (הגנת zip bomb), ולכן חסום בלי תלות ב-timeout הגנרי.
  static bool hasOwnTimeout(String method) =>
      method == 'network.download' || method == 'fs.extractZip';

  Future<dynamic> _handleRpc(List<dynamic> args) async {
    if (args.isEmpty) {
      return _errorResp("error.invalid_params", "No arguments provided");
    }

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

    final requiredPermission = _getRequiredPermission(domain, action);
    final declaresPermission =
        requiredPermission == null ||
        plugin.manifest.permissions.contains(requiredPermission);

    // ההחרגה ממגביל הקצב חלה רק על קריאת תוכן שההרשאה לה *הוענקה בפועל* (לא רק
    // הוצהרה במניפסט). לכן בודקים את ההענקה כבר עכשיו עבור getBookContent —
    // תוסף ללא הרשאה מוענקת אינו עוקף את ה-throttle אלא עובר דרכו ומקבל
    // permission_denied. כדי לא להוסיף קריאת DB לכל RPC, ההקדמה הזו מתבצעת רק
    // לקריאות תוכן; שאר הקריאות נבדקות כרגיל בהמשך.
    final isContentRead = isRateLimitExempt(request.method);
    bool? grantedEarly;
    if (isContentRead && declaresPermission && requiredPermission != null) {
      grantedEarly =
          await _registry.getPermission(plugin.pluginId, requiredPermission) ==
          true;
    }

    final exempt = isContentRead && (grantedEarly ?? false);
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

      // פעולות I/O ארוכות (download/extractZip) מנהלות בעצמן את חסם הזמן; שאר
      // הקריאות אמורות להיות מהירות ולכן נחתכות אחרי 30 שניות.
      final execution = adapter.execute(domain, action, request.payload);
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

  String? _getRequiredPermission(String domain, String action) {
    switch (domain) {
      case 'app':
        if (action == 'getUserEmail') {
          return 'app.user_email.read';
        }
        if (action == 'openUrl') {
          return 'app.open_url';
        }
        return 'app.info.read';
      case 'library':
        if (action == 'getBookContent' ||
            action == 'getBookToc' ||
            action == 'listBookAltStructures' ||
            action == 'getBookAltToc') {
          return 'library.content.read';
        }
        return 'library.books.read';
      case 'search':
        return 'search.fulltext.read';
      case 'reader':
        switch (action) {
          case 'addContextMenuItem':
          case 'removeContextMenuItem':
            return 'reader.context_menu';
          case 'setHighlight':
          case 'getHighlights':
          case 'clearHighlight':
          case 'clearAllHighlights':
            return 'reader.highlight';
          default:
            return 'reader.open';
        }
      case 'navigation':
        return 'navigation.write';
      case 'notes':
        if (action == 'add' || action == 'update' || action == 'delete') {
          return 'notes.write';
        }
        return 'notes.read';
      case 'ui':
        return 'ui.feedback';
      case 'storage':
        if (action == 'get' || action == 'list') {
          return 'plugin.storage.read';
        }
        return 'plugin.storage.write';
      case 'settings':
        return 'settings.read';
      case 'calendar':
        return 'calendar.read';
      case 'publishedData':
        return 'published_data.write';
      case 'feedback':
        return 'feedback.send_email';
      case 'history':
        if (action == 'clear' || action == 'remove') {
          return 'history.write';
        }
        return 'history.read';
      case 'notifications':
        if (action == 'showInApp') {
          return 'notifications.send';
        }
        return 'notifications.system';
      case 'database':
        return 'database.read';
      case 'fs':
        switch (action) {
          // פעולות על קובץ שהמשתמש בוחר במפורש — דורשות הרשאת manifest.
          case 'pickUserFile':
          case 'resolveFileUrl':
          case 'readTextFile':
          case 'revokeFile':
            return 'fs.user_files.read';
          // extractZip/deleteFile אינן דורשות הרשאת manifest: הן מגודרות בכך
          // שהנתיב חייב להיות בתוך תיקייה שהמשתמש בחר דרך ui.pickFolder
          // (הדורשת ui.feedback). הסכמת המשתמש בדיאלוג היא גבול האבטחה.
          default:
            return null;
        }
      case 'shortcut':
        return 'ui.create_shortcut';
      case 'plugin':
        // openSelf מעביר את המשתמש למסך אחר — דורש הרשאת ניווט.
        if (action == 'openSelf') {
          return 'navigation.write';
        }
        return null;
      default:
        return null;
    }
  }

  Map<String, dynamic> _successResp(dynamic data) {
    return PluginRpcResponse.success(data).toJson();
  }

  Map<String, dynamic> _errorResp(String code, String message) {
    return PluginRpcResponse.error(code: code, message: message).toJson();
  }
}
