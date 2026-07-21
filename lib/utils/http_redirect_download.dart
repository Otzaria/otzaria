import 'package:http/http.dart' as http;

/// שולח בקשת GET ועוקב אחרי redirects **ידנית**, תוך שימור ה-headers (כולל
/// `Range`) בכל hop. package:http משמיט את כל ה-headers כשהוא עוקב אוטומטית
/// אחרי redirect, מה ששובר הורדות resume: ה-`Range` אובד, השרת מחזיר 200,
/// וההורדה מתחילה מ-0.
///
/// [maxRedirects] מגביל את מספר הקפיצות. [stallTimeout] חל על שלב
/// השליחה ועל זרם התגובה בכל hop. Location יחסי מפוענח מול ה-URI הנוכחי.
///
/// אזהרה: כל ה-headers מיושמים מחדש בכל hop, גם חוצה-host — אין להעביר כאן
/// כותרות רגישות (Authorization), הן יישלחו ליעד ה-redirect. כיום בטוח.
Future<http.StreamedResponse> sendGetFollowingRedirects(
  http.Client client,
  Uri url, {
  Map<String, String>? headers,
  int maxRedirects = 5,
  Duration stallTimeout = const Duration(seconds: 60),
}) async {
  var current = url;
  for (var hop = 0; hop <= maxRedirects; hop++) {
    final request = http.Request('GET', current)..followRedirects = false;
    if (headers != null) request.headers.addAll(headers);

    final sendFuture = client.send(request);
    final response = await sendFuture.timeout(stallTimeout);

    if (_isRedirect(response.statusCode)) {
      final location = response.headers['location'];
      // גוף redirect אינו נדרש. drain עלול לצרוך גוף גדול או stream פעיל ללא
      // גבול; ביטול המנוי עוקב מיד אחרי Location ומשחרר את החיבור.
      try {
        await response.stream.listen((_) {}).cancel();
      } catch (_) {}
      if (location == null || location.isEmpty) {
        throw Exception('redirect ללא Location');
      }
      current = current.resolve(location);
      continue;
    }
    // גם קורא שאינו עוטף את הגוף בעצמו מקבל הגנת stall על התגובה הסופית.
    return http.StreamedResponse(
      response.stream.timeout(stallTimeout),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }
  throw Exception('יותר מדי redirects');
}

bool _isRedirect(int code) =>
    code == 301 || code == 302 || code == 303 || code == 307 || code == 308;
