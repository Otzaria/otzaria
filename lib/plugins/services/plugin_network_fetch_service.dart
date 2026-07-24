import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:otzaria/core/http_client_registry.dart';

/// תוצאת קריאת `network.fetch`.
class PluginNetworkFetchResult {
  /// קוד הסטטוס של התשובה.
  final int status;

  /// האם הסטטוס בטווח 2xx.
  final bool ok;

  /// גוף התשובה כטקסט.
  final String body;

  const PluginNetworkFetchResult({
    required this.status,
    required this.ok,
    required this.body,
  });
}

/// שירות לביצוע בקשת HTTP כללית עבור ה-RPC `network.fetch`.
///
/// הבקשה רצה בצד אוצריא (Flutter) ולא ב-WebView, ולכן **אינה כפופה ל-CORS**.
/// זהו הנתיב שתוספים צריכים להשתמש בו לקריאות ל-APIs חיצוניים (במיוחד `POST`),
/// מכיוון ש-`fetch()` ישיר מה-WebView (origin `file://`) נחסם ב-CORS מול
/// שרתים שאינם מחזירים `Access-Control-Allow-Origin`.
///
/// בדיקת ההרשאה וה-allowlist מתבצעות אצל הקורא (האדפטר), לא כאן.
class PluginNetworkFetchService {
  final http.Client _client;
  late final FutureOr<void> Function() _closer = _client.close;

  PluginNetworkFetchService({http.Client? client})
    : _client = client ?? http.Client() {
    HttpClientRegistry.register(_closer);
  }

  /// משחרר את ה-client ומסירו מ-[HttpClientRegistry].
  void dispose() {
    HttpClientRegistry.unregister(_closer);
    _client.close();
  }

  /// מבצעת בקשת HTTP אל [uri] ומחזירה את התשובה כטקסט.
  ///
  /// אינה עוקבת אחרי redirects (יעד redirect יוחזר כסטטוס 3xx). ברירת המחדל
  /// של כותרת `Accept` היא `*/*` — התוסף יכול לדרוס אותה (וכל כותרת אחרת)
  /// דרך [headers]. [body] נשלח כ-UTF-8 אם סופק.
  Future<PluginNetworkFetchResult> fetch(
    Uri uri, {
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
  }) async {
    final request = http.Request(method, uri)..followRedirects = false;
    // ברירת מחדל כללית; לא קובעים application/json כדי לא לשבור content
    // negotiation. headers מפורשים מהתוסף דורסים זאת.
    request.headers['accept'] = '*/*';
    if (headers != null && headers.isNotEmpty) {
      request.headers.addAll(headers);
    }
    if (body != null && body.isNotEmpty) {
      request.body = body;
    }

    final response = await _client.send(request);
    final responseBody = await response.stream.bytesToString();
    final status = response.statusCode;
    return PluginNetworkFetchResult(
      status: status,
      ok: status >= 200 && status < 300,
      body: responseBody,
    );
  }
}
