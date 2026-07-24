import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// רשומת קובץ אישי שהמשתמש אישר לתוסף, כפי שהיא מוחזקת בזיכרון השרת.
class PluginFileGrant {
  final String pluginId;
  final String canonicalPath;

  const PluginFileGrant({required this.pluginId, required this.canonicalPath});
}

/// תוצאת רישום קובץ חדש: ה-token שנוצר וה-URL לטעינה ב-WebView.
typedef PluginFileRegistration = ({String token, String url});

/// שרת `HttpServer` פנימי שמגיש קבצים אישיים של המשתמש ל-WebView של תוספים.
///
/// **למה שרת ולא base64 דרך הגשר:** קובץ PDF גדול שמועבר כ-base64 ב-JSON-RPC
/// תוקע את ה-UI ומכפיל את הזיכרון. השרת מזרים את הבייטים ישירות ל-WebView,
/// כך שהם לעולם אינם חוצים את גשר ה-JS, ותומך ב-Range — מה שמציגי PDF
/// (PDF.js / WebView2) מסתמכים עליו.
///
/// **גבול אבטחה:** השרת מאזין ב-loopback בלבד (`127.0.0.1`) על פורט אקראי,
/// ומגיש אך ורק קבצים שנרשמו דרך [register]/[registerWithToken] עם token
/// אקראי בן 256 ביט. נתיב מה-URL אינו נוגע בדיסק — רק חיפוש token. כך אין
/// path-traversal דרך ה-URL, ותוסף יכול לטעון רק קבצים שהמשתמש בחר במפורש.
class PluginFileServer {
  PluginFileServer();

  static final PluginFileServer instance = PluginFileServer();

  HttpServer? _server;
  final Map<String, PluginFileGrant> _grants = {};
  final Random _random = Random.secure();

  /// ה-origin של השרת (`http://127.0.0.1:<port>`), או `null` אם טרם הופעל.
  String? get origin {
    final server = _server;
    return server == null ? null : 'http://127.0.0.1:${server.port}';
  }

  Future<void> _ensureStarted() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handleRequest);
  }

  String _generateToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// רושם קובץ מאושר חדש ומחזיר token טרי וה-URL לטעינה.
  Future<PluginFileRegistration> register({
    required String pluginId,
    required String canonicalPath,
  }) async {
    await _ensureStarted();
    final token = _generateToken();
    _grants[token] = PluginFileGrant(
      pluginId: pluginId,
      canonicalPath: canonicalPath,
    );
    return (token: token, url: '$origin/f/$token');
  }

  /// רושם מחדש קובץ עם token קיים (לאחר reload, כשרישום הזיכרון אבד אך
  /// ה-grant נשמר אצל התוסף). מחזיר את ה-URL הטרי בפורט הנוכחי.
  Future<String> registerWithToken({
    required String pluginId,
    required String canonicalPath,
    required String token,
  }) async {
    await _ensureStarted();
    _grants[token] = PluginFileGrant(
      pluginId: pluginId,
      canonicalPath: canonicalPath,
    );
    return '$origin/f/$token';
  }

  /// סוגר את השרת ומשחרר את כל ה-grants. בפרודקשן השרת חי לכל אורך חיי
  /// האפליקציה; משמש בעיקר לניקוי בין בדיקות.
  Future<void> close() async {
    _grants.clear();
    await _server?.close(force: true);
    _server = null;
  }

  void revoke(String token) => _grants.remove(token);

  void revokeAllForPlugin(String pluginId) =>
      _grants.removeWhere((_, grant) => grant.pluginId == pluginId);

  /// האם [uri] מצביעה לשרת הקבצים הפנימי (loopback + הפורט שהוקצה).
  bool isServerUri(Uri uri) {
    final server = _server;
    if (server == null) return false;
    if (uri.scheme != 'http') return false;
    const loopbacks = {'127.0.0.1', 'localhost'};
    if (!loopbacks.contains(uri.host.toLowerCase())) return false;
    return uri.hasPort && uri.port == server.port;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      // loopback + token אקראי; מתירים גישת fetch מ-origin file:// (Origin: null).
      response.headers.set('Access-Control-Allow-Origin', '*');
      response.headers.set('Access-Control-Allow-Headers', 'Range');
      response.headers.set(
        'Access-Control-Expose-Headers',
        'Content-Range, Accept-Ranges, Content-Length',
      );

      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.noContent;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }

      final segments = request.uri.pathSegments;
      if (segments.length != 2 || segments[0] != 'f') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final grant = _grants[segments[1]];
      if (grant == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final file = File(grant.canonicalPath);
      if (!await file.exists()) {
        response.statusCode = HttpStatus.notFound;
        return;
      }

      final length = await file.length();
      response.headers.set('Accept-Ranges', 'bytes');
      response.headers.contentType = _contentTypeForPath(grant.canonicalPath);

      final rangeHeader = request.headers.value('range');
      if (rangeHeader == null) {
        response.headers.contentLength = length;
        if (request.method == 'HEAD') return;
        await response.addStream(file.openRead());
        return;
      }

      final range = _parseRange(rangeHeader, length);
      if (range == null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set('Content-Range', 'bytes */$length');
        return;
      }
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        'Content-Range',
        'bytes ${range.start}-${range.end}/$length',
      );
      response.headers.contentLength = range.end - range.start + 1;
      if (request.method == 'HEAD') return;
      await response.addStream(file.openRead(range.start, range.end + 1));
    } catch (_) {
      // הזרם נקטע (ניווט/ביטול בצד התוסף) או שגיאת IO — אין מה לעשות מעבר לסגירה.
    } finally {
      await response.close();
    }
  }

  /// מפענח כותרת `Range` יחידה. מחזיר `null` אם אינה תקפה/מחוץ לתחום
  /// (השרת יחזיר אז 416), ולכן נקרא רק כשהכותרת קיימת.
  _ByteRange? _parseRange(String header, int length) {
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null) return null;
    final startStr = match.group(1)!;
    final endStr = match.group(2)!;
    int start;
    int end;
    if (startStr.isEmpty) {
      if (endStr.isEmpty) return null;
      final suffix = int.parse(endStr);
      if (suffix == 0) return null;
      start = length - suffix < 0 ? 0 : length - suffix;
      end = length - 1;
    } else {
      start = int.parse(startStr);
      end = endStr.isEmpty ? length - 1 : int.parse(endStr);
    }
    if (start > end || start >= length) return null;
    if (end >= length) end = length - 1;
    return _ByteRange(start, end);
  }

  ContentType _contentTypeForPath(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.pdf':
        return ContentType('application', 'pdf');
      case '.txt':
        return ContentType('text', 'plain', charset: 'utf-8');
      case '.html':
      case '.htm':
        return ContentType('text', 'html', charset: 'utf-8');
      case '.json':
        return ContentType('application', 'json', charset: 'utf-8');
      case '.csv':
        return ContentType('text', 'csv', charset: 'utf-8');
      case '.md':
        return ContentType('text', 'markdown', charset: 'utf-8');
      case '.epub':
        return ContentType('application', 'epub+zip');
      case '.png':
        return ContentType('image', 'png');
      case '.jpg':
      case '.jpeg':
        return ContentType('image', 'jpeg');
      case '.gif':
        return ContentType('image', 'gif');
      case '.svg':
        return ContentType('image', 'svg+xml');
      default:
        return ContentType('application', 'octet-stream');
    }
  }
}

class _ByteRange {
  final int start;
  final int end;

  const _ByteRange(this.start, this.end);
}
