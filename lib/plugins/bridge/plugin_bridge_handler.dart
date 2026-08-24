import 'dart:async';
import 'dart:convert';
import 'dart:math';
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

  /// מופעלים בתחילת ובסוף כל RPC — מאפשרים למופע רקע לאותת "אני עסוק"
  /// למנגנון הכיבוי אחרי חוסר פעילות, בלי לקטוע RPC ארוך באמצעו.
  final void Function()? onWorkStarted;
  final void Function()? onWorkEnded;

  PluginBridgeHandler(
    this.plugin, {
    required this.adapter,
    PluginRegistryRepository? registry,
    RateLimiter? rateLimiter,
    this.onWorkStarted,
    this.onWorkEnded,
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
      method == 'network.fetch' ||
      method == 'network.fetchStream' ||
      method == 'network.download' ||
      method == 'fs.extractZip' ||
      // „שמור בשם” מחכה לדיאלוג של המערכת. timeout גנרי היה מחזיר
      // error.timeout בזמן שהמשתמש בוחר תיקייה, והתוסף היה חושב שהשמירה נכשלה
      // אחרי שהקובץ כבר נכתב.
      method == 'fs.commitUserFileWrite' ||
      method == 'feedback.report';

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

    onWorkStarted?.call();
    try {
      return await _dispatchRpc(args, eventSink: eventSink);
    } finally {
      onWorkEnded?.call();
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
    final isSearchCancellation =
        request.method == 'search.query' &&
        PluginBridgeAdapter.isSearchCancellationPayload(request.payload);
    final isNetworkFetchCancellation =
        request.method == 'network.fetchStream' &&
        PluginBridgeAdapter.isNetworkFetchCancellationPayload(request.payload);
    bool? grantedEarly;
    if (isContentRead && declaresPermission && requiredPermission != null) {
      grantedEarly =
          await _registry.getPermission(plugin.pluginId, requiredPermission) ==
          true;
    }

    final exempt =
        (isContentRead && (grantedEarly ?? false)) ||
        isSearchCancellation ||
        isNetworkFetchCancellation;
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

  /// סמן לרישום מפורש של "ללא הרשאת manifest" ב-[methodPermissions]: הגבול
  /// נאכף במקום אחר (הסכמת המשתמש בדיאלוג, תיקייה מאושרת, או האדפטר עצמו).
  static const String noManifestPermission = '<none>';

  /// הרשאת המניפסט הנדרשת לכל method שהגשר מכיר. method שאינו ברשימה נדחה
  /// ב-`error.unknown_method` — אין נפילה שקטה ל"ללא הרשאה".
  static const Map<String, String> methodPermissions = {
    'app.getInfo': 'app.info.read',
    'app.getTheme': 'app.info.read',
    'app.getLocale': 'app.info.read',
    'app.getGrantedPermissions': 'app.info.read',
    'app.getConnectivity': 'app.info.read',
    'app.getUserEmail': 'app.user_email.read',
    'app.openUrl': 'app.open_url',
    'library.findBooks': 'library.books.read',
    'library.getBookMetadata': 'library.books.read',
    'library.resolveBooks': 'library.books.read',
    'library.resolveCategoryPaths': 'library.books.read',
    'library.listRecentBooks': 'library.books.read',
    'library.getTree': 'library.books.read',
    'library.getBookContent': 'library.content.read',
    'library.getBookToc': 'library.content.read',
    'library.listBookAltStructures': 'library.content.read',
    'library.getBookAltToc': 'library.content.read',
    'library.getLinkContent': 'library.content.read',
    'library.getCommentators': pluginLinksReadPermission,
    'library.getLinks': pluginLinksReadPermission,
    'library.getLinkTargetsSummary': pluginLinksReadPermission,
    'search.fullText': 'search.fulltext.read',
    'search.query': 'search.fulltext.read',
    'search.getOptions': 'search.fulltext.read',
    'reader.openBook': 'reader.open',
    'reader.openBookAtRef': 'reader.open',
    'reader.openSearchTab': 'reader.open',
    'reader.getCurrentState': 'reader.open',
    'reader.getCurrentRef': 'reader.open',
    'reader.getSelection': 'reader.open',
    'reader.getActiveCommentators': 'reader.open',
    'reader.setActiveCommentators': 'reader.open',
    'reader.scrollToSection': 'reader.open',
    'reader.getHighlightCapabilities': 'reader.open',
    'reader.findTextOccurrences': 'reader.open',
    'reader.getSectionTextMap': 'reader.open',
    'reader.registerInBookSearchProvider': 'reader.open',
    'reader.respondInBookSearch': 'reader.open',
    'reader.registerExternalSearchProvider': 'reader.open',
    'reader.respondExternalSearch': 'reader.open',
    'reader.addContextMenuItem': 'reader.context_menu',
    'reader.removeContextMenuItem': 'reader.context_menu',
    'reader.updateContextMenuItem': 'reader.context_menu',
    'reader.addToolbarItem': 'reader.toolbar',
    'reader.removeToolbarItem': 'reader.toolbar',
    'reader.updateToolbarItem': 'reader.toolbar',
    'reader.setHighlight': 'reader.highlight',
    'reader.updateHighlight': 'reader.highlight',
    'reader.getHighlights': 'reader.highlight',
    'reader.revealHighlight': 'reader.highlight',
    'reader.clearHighlight': 'reader.highlight',
    'reader.clearAllHighlights': 'reader.highlight',
    'navigation.goTo': 'navigation.write',
    'notes.list': 'notes.read',
    'notes.getBookNotesSummary': 'notes.read',
    'notes.add': 'notes.write',
    'notes.update': 'notes.write',
    'notes.delete': 'notes.write',
    'ui.showMessage': 'ui.feedback',
    'ui.showSuccess': 'ui.feedback',
    'ui.showError': 'ui.feedback',
    'ui.showConfirm': 'ui.feedback',
    'ui.showWarning': 'ui.feedback',
    // בחירת תיקייה היא גבול ההסכמה של פעולות ה-fs — הרשאה נפרדת.
    'ui.pickFolder': pluginFolderAccessPermission,
    'storage.get': 'plugin.storage.read',
    'storage.list': 'plugin.storage.read',
    'storage.set': 'plugin.storage.write',
    'storage.remove': 'plugin.storage.write',
    'settings.get': 'settings.read',
    'settings.getMany': 'settings.read',
    'calendar.getSelectedDate': 'calendar.read',
    'calendar.getDailyTimes': 'calendar.read',
    'calendar.getHalachicTimes': 'calendar.read',
    'calendar.getJewishDate': 'calendar.read',
    'calendar.getEvents': 'calendar.read',
    'calendar.getCities': 'calendar.read',
    'publishedData.upsert': 'published_data.write',
    'publishedData.remove': 'published_data.write',
    'publishedData.listOwn': 'published_data.write',
    'feedback.sendEmail': 'feedback.send_email',
    // report נשלח רק אחרי אישור המשתמש בדיאלוג, וההסכמה שם היא גבול האבטחה;
    // hasReporterEmail מחזירה ביט קיום בלבד, בלי הכתובת עצמה.
    'feedback.report': noManifestPermission,
    'feedback.hasReporterEmail': noManifestPermission,
    'history.list': 'history.read',
    'history.listSearches': 'history.read',
    'history.clear': 'history.write',
    'history.remove': 'history.write',
    'bookmarks.list': pluginBookmarksReadPermission,
    'bookmarks.add': pluginBookmarksWritePermission,
    'bookmarks.remove': pluginBookmarksWritePermission,
    'tools.gematria': pluginToolsReadPermission,
    'tools.dictionary': pluginToolsReadPermission,
    'notifications.showInApp': 'notifications.send',
    'notifications.sendSystem': 'notifications.system',
    'notifications.scheduleSystem': 'notifications.system',
    'notifications.cancel': 'notifications.system',
    'notifications.cancelAll': 'notifications.system',
    'notifications.checkPermissions': 'notifications.system',
    'notifications.requestPermissions': 'notifications.system',
    'database.listSources': 'database.read',
    'database.describeSource': 'database.read',
    'database.query': 'database.read',
    'database.batchQuery': 'database.read',
    // הרשאות הרשת (network.access / network.localhost) נבדקות באדפטר לפי
    // היעד, יחד עם רשימת ההיתר של המניפסט.
    'network.fetch': noManifestPermission,
    'network.fetchStream': noManifestPermission,
    'network.download': noManifestPermission,
    // extractZip/deleteFile מגודרות בכך שהנתיב חייב להיות בתוך תיקייה
    // שהמשתמש בחר דרך ui.pickFolder — ההסכמה שם היא גבול האבטחה.
    'fs.extractZip': noManifestPermission,
    'fs.deleteFile': noManifestPermission,
    // המרחב הפרטי: כל הפעולות מוגבלות לשורש `<data>/plugins/data/<id>/files`
    // ואינן יכולות לצאת ממנו. השורש עצמו הוא הגבול, ולכן אין מה לבקש מהמשתמש.
    'fs.writeFile': noManifestPermission,
    'fs.readFile': noManifestPermission,
    'fs.listDir': noManifestPermission,
    'fs.makeDir': noManifestPermission,
    'fs.deleteEntry': noManifestPermission,
    'fs.stat': noManifestPermission,
    'fs.pickUserFile': 'fs.user_files.read',
    'fs.resolveFileUrl': 'fs.user_files.read',
    'fs.readTextFile': 'fs.user_files.read',
    'fs.revokeFile': 'fs.user_files.read',
    // כתיבה לקובץ של המשתמש. pickUserFile עם access: 'readwrite' דורש את שתי
    // ההרשאות — הקריאה נאכפת כאן והכתיבה באדפטר, כי היא תלויה בארגומנט.
    'fs.beginBinaryWrite': 'fs.user_files.write',
    'fs.commitUserFileWrite': 'fs.user_files.write',
    'fs.abortBinaryWrite': 'fs.user_files.write',
    'shortcut.create': 'ui.create_shortcut',
    // openSelf מעביר את המשתמש למסך אחר — הרשאת ניווט; openOther מפעיל תוסף
    // שלישי — הרשאה נפרדת וחזקה יותר.
    'plugin.openSelf': 'navigation.write',
    'plugin.openOther': pluginOpenOtherPermission,
    'plugin.listInstalled': 'app.info.read',
    'plugin.requestInstall': 'app.info.read',
    // התוסף מדווח שסיים את עבודת הרקע שלו — על עצמו בלבד.
    'plugin.backgroundDone': noManifestPermission,
  };

  Map<String, dynamic> _successResp(dynamic data) {
    return PluginRpcResponse.success(data).toJson();
  }

  Map<String, dynamic> _errorResp(String code, String message) {
    return PluginRpcResponse.error(code: code, message: message).toJson();
  }
}
