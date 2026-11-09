import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_os_location_permission.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';

/// שער בקשות ההרשאה של WebView התוספים.
///
/// יכולת מאושרת רק לאחר הצהרה במניפסט והענקה מפורשת של המשתמש; היתר נדחה ונרשם
/// בלוג הריצה של התוסף.
class PluginWebViewPermissionGate {
  const PluginWebViewPermissionGate._();

  /// משתמשים בערך המחרוזת כי `PermissionResourceType.==` אינו סימטרי.
  static const Map<String, String> requirements = {
    'CLIPBOARD_READ': pluginClipboardReadPermission,
    'LOCAL_FONTS': pluginLocalFontsPermission,
    'GEOLOCATION': pluginGeolocationPermission,
  };

  /// הרשאות שמוענקות רק לדף של התוסף עצמו, לא למסגרת אחרת שהוא טוען.
  ///
  /// מיקום הוא נתון אישי, ו-`<iframe allow="geolocation">` של אתר שבהצהרת
  /// הרשת של התוסף היה נהנה אחרת מההענקה שהמשתמש נתן לתוסף.
  static const Set<String> _ownOriginOnly = {pluginGeolocationPermission};

  // לא `const`: ראו ההערה במבחנים — `PermissionResourceType` אינו const.
  static final List<PermissionResourceType> _geolocationResources = [
    PermissionResourceType.GEOLOCATION,
  ];
  static final String _geolocationResourceName = PermissionResourceType
      .GEOLOCATION
      .toValue();

  /// התשובה לבקשה של [request], אחרי בדיקת המניפסט וההענקה שנשמרה.
  ///
  /// אינה זורקת: חריגה כאן משאירה את ה-deferral של WebView2 פתוח, כלומר דף
  /// שממתין לתשובה שלא תבוא.
  static Future<PermissionResponse> respond({
    required InstalledPlugin plugin,
    required PermissionRequest request,
    required PluginRegistryRepository registry,
  }) async {
    final resources = request.resources.map((r) => r.toValue()).join(', ');
    try {
      final decision = await _decide(
        resources: request.resources,
        origin: request.origin.toString(),
        plugin: plugin,
        registry: registry,
      );
      if (decision.granted) {
        return PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.GRANT,
        );
      }
      _logDenial(plugin, resources, request.origin.toString(), decision);
    } catch (e) {
      debugPrint(
        'PluginWebViewPermissionGate: החלטה נכשלה לתוסף '
        '${plugin.pluginId} — נדחה. $e',
      );
    }
    return PermissionResponse(
      resources: request.resources,
      action: PermissionResponseAction.DENY,
    );
  }

  /// התשובה לבקשת מיקום באנדרואיד.
  ///
  /// ה-WebView של אנדרואיד אינו מבקש מיקום דרך `onPermissionRequest` אלא דרך
  /// `onGeolocationPermissionsShowPrompt`, ולכן הוא מקבל כניסה משלו לאותה
  /// החלטה. מעבר להצהרה ולהענקה צריך גם אישור מערכת — `ACCESS_COARSE_LOCATION`
  /// — וה-WebView מחזיר לדף שגיאה אם הוא חסר, גם כשההיתר ניתן כאן.
  ///
  /// ההיתר אינו נשמר ([GeolocationPermissionShowPromptResponse.retain]):
  /// כל בקשה נבדקת מחדש, כך שכיבוי ההרשאה במסך ההגדרות חל מיד. אינה זורקת.
  static Future<GeolocationPermissionShowPromptResponse> respondGeolocation({
    required InstalledPlugin plugin,
    required String origin,
    required PluginRegistryRepository registry,
    Future<bool> Function()? ensureOsPermission,
  }) async {
    var allow = false;
    try {
      var denial = await _decide(
        resources: _geolocationResources,
        origin: origin,
        plugin: plugin,
        registry: registry,
      );
      if (denial.granted) {
        allow =
            await (ensureOsPermission ?? PluginOsLocationPermission.ensure)();
        denial = allow
            ? denial
            : const _Decision.denied(
                reason: 'המשתמש לא אישר מיקום במערכת ההפעלה',
              );
      }
      if (!allow) _logDenial(plugin, _geolocationResourceName, origin, denial);
    } catch (e) {
      allow = false;
      debugPrint(
        'PluginWebViewPermissionGate: החלטת מיקום נכשלה לתוסף '
        '${plugin.pluginId} — נדחה. $e',
      );
    }
    return GeolocationPermissionShowPromptResponse(
      origin: origin,
      allow: allow,
      retain: false,
    );
  }

  static Future<_Decision> _decide({
    required List<PermissionResourceType> resources,
    required String? origin,
    required InstalledPlugin plugin,
    required PluginRegistryRepository registry,
  }) async {
    // בקשה בלי משאבים אינה "הכול מותר" אלא בקשה שאין מה לאשר בה.
    if (resources.isEmpty) return const _Decision.denied();

    for (final resource in resources) {
      final permission = requiredPermissionFor(resource);
      if (permission == null) {
        return _Decision.denied(missingPermission: resource.toValue());
      }
      if (_ownOriginOnly.contains(permission) && !isPluginOwnOrigin(origin)) {
        return _Decision.denied(
          reason: 'הבקשה אינה מדף של התוסף עצמו, ו-$permission ניתנת רק לו',
        );
      }
      if (!declaresPermission(plugin, permission)) {
        return _Decision.denied(missingPermission: permission);
      }
      if (await registry.getPermission(plugin.pluginId, permission) != true) {
        return _Decision.denied(missingPermission: permission);
      }
    }
    return const _Decision.granted();
  }

  /// ההרשאה שנדרשת ל-[resource], או `null` כשהיכולת אינה נפתחת לתוספים.
  @visibleForTesting
  static String? requiredPermissionFor(PermissionResourceType resource) {
    return requirements[resource.toValue()];
  }

  /// האם [origin] הוא דף של התוסף עצמו: קובץ מקומי, הסכימה הייעודית שלו או
  /// שרת הקבצים המקומי. כתובת אינטרנט, וגם מקור חסר או לא תקין, אינם.
  ///
  /// באנדרואיד ה-origin של דף `file://` מגיע כ-`file://` בלי נתיב, ולכן
  /// הבדיקה היא לפי הסכימה בלבד.
  @visibleForTesting
  static bool isPluginOwnOrigin(String? origin) {
    if (origin == null || origin.isEmpty) return false;
    final uri = Uri.tryParse(origin);
    if (uri == null) return false;
    return switch (uri.scheme) {
      'file' || pluginAssetScheme => true,
      'http' => const {
        '127.0.0.1',
        'localhost',
        '::1',
      }.contains(uri.host.toLowerCase()),
      _ => false,
    };
  }

  /// האם המניפסט הצהיר על [permission].
  ///
  /// כולל את אליאס התאימות לאחור, כמו ב-`PluginBridgeHandler`: תוסף ותיק
  /// שהצהיר על ההרשאה שממנה זו פוצלה אינו נשבר בעדכון.
  @visibleForTesting
  static bool declaresPermission(InstalledPlugin plugin, String permission) {
    final declared = plugin.manifest.permissions;
    return pluginBaselinePermissions.contains(permission) ||
        declared.contains(permission) ||
        declared.contains(pluginLegacyPermissionAliases[permission]);
  }

  static void _logDenial(
    InstalledPlugin plugin,
    String resources,
    String? origin,
    _Decision decision,
  ) {
    final missing = decision.missingPermission;
    final reason =
        decision.reason ??
        (missing == null
            ? 'היכולת אינה נפתחת לתוספים'
            : 'חסרה ההרשאה $missing');
    final message = 'בקשת הרשאת WebView נדחתה [$resources] מ-$origin: $reason';
    debugPrint('PluginWebViewPermissionGate [${plugin.pluginId}]: $message');
    // fire-and-forget, כמו כל כתיבה ללוג הריצה.
    unawaited(
      PluginSystemDatabase.instance.writeLog(plugin.pluginId, 'warn', message),
    );
  }
}

class _Decision {
  final bool granted;

  /// ההרשאה שחסרה, או `null` כשהיכולת עצמה אינה ממופה.
  final String? missingPermission;

  /// סיבת דחייה מפורשת כשאין הרשאה אחת שחסרה (למשל מקור זר).
  final String? reason;

  const _Decision.granted()
    : granted = true,
      missingPermission = null,
      reason = null;

  const _Decision.denied({this.missingPermission, this.reason})
    : granted = false;
}
