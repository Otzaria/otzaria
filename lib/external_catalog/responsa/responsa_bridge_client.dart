import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/external_catalog/responsa/responsa_paths.dart';

/// פרטי החיבור לגשר, מתוך קובץ ה-discovery שהוא כותב בהפעלה.
class ResponsaBridgeEndpoint {
  final int port;
  final String token;
  final int pid;
  final int bridgeVersion;

  const ResponsaBridgeEndpoint({
    required this.port,
    required this.token,
    required this.pid,
    required this.bridgeVersion,
  });

  /// תמיד `127.0.0.1` — הגשר מאזין מקומית בלבד, והלקוח לא יפנה לשום
  /// מארח אחר גם אם קובץ ה-discovery ישונה.
  Uri uri(String path) => Uri.http('127.0.0.1:$port', path);

  static ResponsaBridgeEndpoint? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final port = decoded['port'];
      final token = decoded['token'];
      if (port is! int || port <= 0 || token is! String || token.isEmpty) {
        return null;
      }
      return ResponsaBridgeEndpoint(
        port: port,
        token: token,
        pid: decoded['pid'] is int ? decoded['pid'] as int : 0,
        bridgeVersion: decoded['bridgeVersion'] is int
            ? decoded['bridgeVersion'] as int
            : 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// היכולות שהגשר מדווח עליהן עבור הגרסה המותקנת.
class ResponsaBridgeCapabilities {
  final bool catalog;
  final bool openBook;
  final bool gotoSiman;
  final bool globalSearch;
  final bool bookText;
  final bool searchInBook;

  const ResponsaBridgeCapabilities({
    this.catalog = false,
    this.openBook = false,
    this.gotoSiman = false,
    this.globalSearch = false,
    this.bookText = false,
    this.searchInBook = false,
  });

  factory ResponsaBridgeCapabilities.fromJson(Map<String, dynamic> json) {
    bool read(String key) => json[key] == true;
    return ResponsaBridgeCapabilities(
      catalog: read('catalog'),
      openBook: read('openBook'),
      gotoSiman: read('gotoSiman'),
      globalSearch: read('globalSearch'),
      bookText: read('bookText'),
      searchInBook: read('searchInBook'),
    );
  }
}

class ResponsaBridgeStatus {
  final int bridgeVersion;
  final bool responsaDetected;
  final int? responsaVersion;
  final String? installPath;
  final int? pid;
  final bool supported;

  /// קוד הסיבה כשהגרסה אינה נתמכת (`unsupportedResponsaVersion`,
  /// `responsaNotInstalled`).
  final String? reason;

  final ResponsaBridgeCapabilities capabilities;

  const ResponsaBridgeStatus({
    required this.bridgeVersion,
    required this.responsaDetected,
    required this.supported,
    this.responsaVersion,
    this.installPath,
    this.pid,
    this.reason,
    this.capabilities = const ResponsaBridgeCapabilities(),
  });

  factory ResponsaBridgeStatus.fromJson(Map<String, dynamic> json) {
    return ResponsaBridgeStatus(
      bridgeVersion: json['bridgeVersion'] is int ? json['bridgeVersion'] : 0,
      responsaDetected: json['responsaDetected'] == true,
      supported: json['supported'] == true,
      responsaVersion: json['responsaVersion'] is int
          ? json['responsaVersion']
          : null,
      installPath: json['installPath']?.toString(),
      pid: json['pid'] is int ? json['pid'] : null,
      reason: json['reason']?.toString(),
      capabilities: json['capabilities'] is Map
          ? ResponsaBridgeCapabilities.fromJson(
              Map<String, dynamic>.from(json['capabilities'] as Map),
            )
          : const ResponsaBridgeCapabilities(),
    );
  }
}

/// תוצאת פתיחה. `ok == false` הוא ערך תקין, לא חריג.
class ResponsaOpenResult {
  final bool ok;
  final String? errorCode;
  final String? message;

  /// כותרת חלון ה-MDI שנפתח בפועל, כפי שנקראה מהתוכנה.
  final String? window;

  /// ההפניה שבה הגשר השתמש בפועל — עשויה להיות קצרה מזו שנשלחה, אם
  /// המנתח דחה את ההקשר המלא.
  final String? usedRef;

  final String? requestId;

  const ResponsaOpenResult({
    required this.ok,
    this.errorCode,
    this.message,
    this.window,
    this.usedRef,
    this.requestId,
  });

  factory ResponsaOpenResult.fromJson(Map<String, dynamic> json) {
    return ResponsaOpenResult(
      ok: json['ok'] == true,
      errorCode: json['error']?.toString(),
      message: json['message']?.toString(),
      window: json['window']?.toString(),
      usedRef: json['usedRef']?.toString(),
      requestId: json['requestId']?.toString(),
    );
  }
}

/// הגשר אינו רץ, או שקובץ ה-discovery חסר/פגום.
class ResponsaBridgeUnavailable implements Exception {
  final String reason;
  const ResponsaBridgeUnavailable(this.reason);

  @override
  String toString() => 'ResponsaBridgeUnavailable($reason)';
}

/// הגשר לא ענה בתוך תקרת הזמן של הפעולה.
class ResponsaBridgeTimeout implements Exception {
  final String operation;
  const ResponsaBridgeTimeout(this.operation);

  @override
  String toString() => 'ResponsaBridgeTimeout($operation)';
}

/// לקוח הגשר המקומי של פרויקט השו"ת.
///
/// שלושה כללים שהמחלקה הזו אוכפת:
///
/// * **localhost בלבד** — הכתובת נבנית תמיד מ-`127.0.0.1`.
/// * **תקרת זמן לכל פעולה**, נפרדת לכל סוג: `status` קצר, `openBook`
///   ארוך מספיק לפתיחה קרה.
/// * **שום חריג לא מטופל אינו מגיע ל-UI** — כשל רשת, גשר שנפל או תשובה
///   פגומה חוזרים כ-[ResponsaOpenResult] עם קוד שגיאה.
class ResponsaBridgeClient {
  static const String tokenHeader = 'X-Responsa-Bridge-Token';

  static const Duration statusTimeout = Duration(seconds: 8);
  static const Duration openBookTimeout = Duration(minutes: 4);
  static const Duration gotoSimanTimeout = Duration(seconds: 90);
  static const Duration cancelTimeout = Duration(seconds: 5);

  final http.Client _httpClient;

  /// עוקף את קריאת קובץ ה-discovery בבדיקות.
  @visibleForTesting
  ResponsaBridgeEndpoint? endpointOverride;

  ResponsaBridgeClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  /// קורא את קובץ ה-discovery. `null` כשהגשר אינו רץ.
  Future<ResponsaBridgeEndpoint?> endpoint() async {
    if (endpointOverride case final override?) return override;
    final target = ResponsaPaths.discoveryPath;
    if (target == null) return null;
    final file = File(target);
    if (!await file.exists()) return null;
    try {
      return ResponsaBridgeEndpoint.tryParse(await file.readAsString());
    } catch (e) {
      debugPrint('ResponsaBridgeClient: cannot read discovery file: $e');
      return null;
    }
  }

  Future<bool> isRunning() async => (await status()) != null;

  /// מצב הגשר, או `null` כשאינו רץ או אינו עונה.
  Future<ResponsaBridgeStatus?> status() async {
    try {
      final json = await _call('GET', '/api/status', timeout: statusTimeout);
      return ResponsaBridgeStatus.fromJson(json);
    } on ResponsaBridgeUnavailable {
      return null;
    } on ResponsaBridgeTimeout {
      return null;
    }
  }

  Future<ResponsaOpenResult> openBook(
    String openRef, {
    String? expectedTitle,
    String? requestId,
  }) {
    return _openCall(
      '/api/openBook',
      {
        'ref': openRef,
        'expectedTitle': ?expectedTitle,
        'requestId': ?requestId,
      },
      openBookTimeout,
      'openBook',
    );
  }

  /// פותח ספר ואז מנווט לסימן. הניווט דורש חלון פתוח, ולכן הוא שלב
  /// שני ולא פרמטר של הפתיחה.
  Future<ResponsaOpenResult> openBookAtSiman(
    String openRef,
    int siman, {
    String? expectedTitle,
    String? requestId,
  }) async {
    final opened = await openBook(
      openRef,
      expectedTitle: expectedTitle,
      requestId: requestId,
    );
    if (!opened.ok) return opened;
    final window = opened.window;
    if (window == null) return opened;
    final jumped = await _openCall(
      '/api/gotoSiman',
      {
        'book': _bookTitleOf(window),
        'siman': siman,
        if (requestId != null) 'requestId': '$requestId-siman',
      },
      gotoSimanTimeout,
      'gotoSiman',
    );
    // כשל בניווט אינו מבטל פתיחה מוצלחת — הספר פתוח, רק לא בסימן.
    return jumped.ok ? jumped : opened;
  }

  Future<void> cancel(String requestId) async {
    try {
      await _call(
        'POST',
        '/api/cancel/$requestId',
        body: const {},
        timeout: cancelTimeout,
      );
    } on ResponsaBridgeUnavailable {
      // אין את מי לבטל.
    } on ResponsaBridgeTimeout {
      // הביטול הוא best-effort; הפעולה עצמה תיפול על תקרת הזמן שלה.
    }
  }

  void dispose() => _httpClient.close();

  /// כותרת חלון MDI היא `<ספר> סימן <גימטריה>`; הניווט מצפה לשם הספר.
  static String _bookTitleOf(String windowTitle) {
    final index = windowTitle.indexOf('סימן');
    return index <= 0
        ? windowTitle.trim()
        : windowTitle.substring(0, index).trim();
  }

  Future<ResponsaOpenResult> _openCall(
    String path,
    Map<String, Object?> body,
    Duration timeout,
    String operation,
  ) async {
    try {
      final json = await _call('POST', path, body: body, timeout: timeout);
      return ResponsaOpenResult.fromJson(json);
    } on ResponsaBridgeUnavailable catch (e) {
      return ResponsaOpenResult(
        ok: false,
        errorCode: 'bridgeUnavailable',
        message: e.reason,
      );
    } on ResponsaBridgeTimeout {
      return ResponsaOpenResult(ok: false, errorCode: 'timeout');
    }
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Map<String, Object?>? body,
    required Duration timeout,
  }) async {
    final target = await endpoint();
    if (target == null) {
      throw const ResponsaBridgeUnavailable('discoveryFileMissing');
    }

    final request = http.Request(method, target.uri(path))
      ..headers[tokenHeader] = target.token;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }

    http.Response response;
    try {
      final streamed = await _httpClient.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw ResponsaBridgeTimeout(path);
    } catch (e) {
      throw ResponsaBridgeUnavailable(e.toString());
    }

    if (response.statusCode == 401) {
      throw const ResponsaBridgeUnavailable('unauthorized');
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // נופל לשגיאה המובנית למטה.
    }
    throw ResponsaBridgeUnavailable('badResponse:${response.statusCode}');
  }
}
