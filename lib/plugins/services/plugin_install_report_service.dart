import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/http_client_registry.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// הקשר דיווח של התקנה ישירה מהחנות: טוקן חד-פעמי + כתובת callback,
/// כפי שהגיעו בקישור `otzaria://plugin/install?token=...&callback=...`
/// (או מ-`plugin.requestInstall` של תוסף החנות).
class PluginInstallReportContext {
  final String token;
  final Uri callbackUrl;

  const PluginInstallReportContext({
    required this.token,
    required this.callbackUrl,
  });
}

/// דיווח תוצאת התקנה ישירה חזרה לאתר (fire-and-forget).
///
/// דף החנות באתר יוצר טוקן לפני הפניית `otzaria://plugin/install`,
/// והאפליקציה מדווחת עליו הצלחה/כישלון כדי שהדף יוכל להציג את התוצאה.
/// כשל בדיווח לעולם אינו משפיע על ההתקנה עצמה — נבלע בשקט (debugPrint בלבד).
class PluginInstallReportService {
  static final http.Client _client = _createClient();

  static http.Client _createClient() {
    final client = http.Client();
    HttpClientRegistry.register(client.close);
    return client;
  }

  /// בדיקה שכתובת ה-callback לגיטימית: http/https בלבד, ובאותו origin של
  /// כתובת ההורדה. הקישור מגיע מדף אינטרנט לא-מהימן — הגבלת same-origin
  /// מונעת שימוש באפליקציה לשליחת בקשות לשרתים זרים.
  static Uri? validateCallback(String? rawCallback, Uri downloadUri) {
    if (rawCallback == null || rawCallback.trim().isEmpty) return null;
    final callback = Uri.tryParse(rawCallback.trim());
    if (callback == null) return null;
    final scheme = callback.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    final sameOrigin =
        callback.scheme.toLowerCase() == downloadUri.scheme.toLowerCase() &&
        callback.host.toLowerCase() == downloadUri.host.toLowerCase() &&
        callback.port == downloadUri.port;
    if (!sameOrigin) return null;
    return callback;
  }

  /// שולח את תוצאת ההתקנה. [success]=false מלווה ב-[errorMessage] שיוצג
  /// למשתמש בדף החנות.
  static Future<void> report(
    PluginInstallReportContext context, {
    required bool success,
    String? errorMessage,
  }) async {
    try {
      String? appVersion;
      try {
        appVersion = (await PackageInfo.fromPlatform()).version;
      } catch (_) {}

      final response = await _client
          .post(
            context.callbackUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'token': context.token,
              'status': success ? 'success' : 'failure',
              if (errorMessage != null && errorMessage.isNotEmpty)
                'error': errorMessage,
              'appVersion': ?appVersion,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Plugin install report failed: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Plugin install report failed: $e');
    }
  }
}
