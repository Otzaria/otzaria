import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_content_security_policy.dart';
import 'package:otzaria/plugins/services/plugin_remote_file_cache.dart';
import 'package:path/path.dart' as p;

/// רשומת קובץ אישי שהמשתמש אישר לתוסף, כפי שהיא מוחזקת בזיכרון השרת.
class PluginFileGrant {
  final String pluginId;
  final String canonicalPath;

  const PluginFileGrant({required this.pluginId, required this.canonicalPath});
}

/// טוען את הבייטים של גופן שמוגש לתוספים.
typedef PluginFontLoader = Future<Uint8List> Function();

/// ה-URL של גופן כולל את ה-token של ההרצה, ולכן התוכן שמאחוריו אינו משתנה.
const String pluginFontCacheControl = 'max-age=31536000, immutable';

/// תוצאת רישום קובץ חדש: ה-token שנוצר וה-URL לטעינה ב-WebView.
typedef PluginFileRegistration = ({String token, String url});

/// כרטיס העלאה: לאן התוסף שולח את הבייטים, ועד מתי.
typedef PluginUploadTicket = ({
  String writeToken,
  String uploadUrl,
  DateTime expiresAt,
  int maxBytes,
});

/// כשל בפתיחת העלאה, עם קוד בפורמט של שגיאות ה-SDK.
class PluginUploadException implements Exception {
  const PluginUploadException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// העלאה פעילה — קובץ temp שממתין ל-commit.
class _UploadSession {
  _UploadSession({
    required this.pluginId,
    required this.tempFile,
    required this.maxBytes,
    required this.expiresAt,
  });

  final String pluginId;
  final File tempFile;
  final int maxBytes;
  final DateTime expiresAt;

  /// ה-PUT התחיל. חוסם PUT שני על אותו token.
  bool started = false;

  /// ה-PUT הושלם והבייטים על הדיסק.
  bool received = false;

  /// מתי ה-commit התחיל — כלומר ייתכן שדיאלוג „שמור בשם” פתוח כרגע. כל עוד
  /// זה מוגדר ה-session נשאר בבעלות השרת: נספר במכסה ונמחק ב-close/revoke.
  DateTime? committingSince;

  bool get committing => committingSince != null;

  /// ה-TTL חל על שלב ההעלאה בלבד.
  ///
  /// commit חי **אינו פג**, ולא בגלל אדיבות: הוא מריץ דיאלוג של המערכת, ואם
  /// שעון היה מוחק את ה-temp מתחתיו — וה-sweep רץ בכל `beginUpload` של כל
  /// תוסף — ה-commit היה נכשל בדיוק ברגע שהמשתמש לוחץ „שמור”. הניקוי קשור
  /// לסיום הפעולה ולא לזמן: `finishCommit` נקרא ב-`finally` של ה-commit,
  /// שרץ בצד ה-Host ולכן מסתיים גם אם ה-WebView של התוסף נעלם באמצע.
  bool get isExpired =>
      committingSince == null && DateTime.now().isAfter(expiresAt);
}

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
  PluginFileServer({
    this.maxUploadBytes = defaultMaxUploadBytes,
    this.uploadTtl = defaultUploadTtl,
    PluginRemoteFileCache? remoteFileCache,
  }) : _remoteFiles = remoteFileCache ?? PluginRemoteFileCache.instance;

  static final PluginFileServer instance = PluginFileServer();

  /// גבול הבייטים להעלאה אחת. פרמטר ולא קונסטנטה כדי שבדיקות יוכלו לאמת את
  /// מסלול הדחייה בלי להעלות 100MB.
  final int maxUploadBytes;

  HttpServer? _server;
  Future<void>? _starting;
  final Map<String, PluginFileGrant> _grants = {};
  final Map<String, _UploadSession> _uploads = {};
  final Map<String, PluginFontLoader> _fonts = {};
  String _fontToken = '';

  /// מטמון `network.fetchFile`, שהקבצים בו מוגשים כאן ונמחקים עם התוסף.
  final PluginRemoteFileCache _remoteFiles;
  final Random _random = Random.secure();

  /// גדול מכל DOCX סביר, וקטן מלגרום ללחץ זיכרון או למלא את הדיסק בטעות.
  static const int defaultMaxUploadBytes = 100 * 1024 * 1024;

  /// חלון הזמן שבו ה-writeToken תקף. ההעלאה היא צעד אחד בשמירה, לא אחסון.
  /// פרמטר ולא קונסטנטה, כדי שבדיקות יוכלו לאמת את מסלולי הפקיעה.
  final Duration uploadTtl;

  static const Duration defaultUploadTtl = Duration(minutes: 2);

  /// גיל מינימלי לשארית `.part` שאין לה session — כלומר מריצה שקרסה. נדיב
  /// בכוונה; ההעלאות עצמן נמחקות לפי [uploadTtl] ולא לפי זה.
  static const Duration orphanMinAge = Duration(hours: 1);

  /// שתי העלאות במקביל מספיקות ל"שמור" ול"שמור בשם" שנלחצו יחד; יותר מזה הוא
  /// כבר תוסף שמשתמש בשרת כאחסון.
  static const int maxActiveUploadsPerPlugin = 2;

  static const String _uploadDirName = 'otzaria_plugin_uploads';

  /// טיפוסים שהדפדפן מריץ בהם סקריפט כשהם נפתחים כמסמך.
  static const Set<String> _activeDocumentTypes = {
    'text/html',
    'image/svg+xml',
  };

  /// ה-origin של השרת (`http://127.0.0.1:<port>`), או `null` אם טרם הופעל.
  String? get origin {
    final server = _server;
    return server == null ? null : 'http://127.0.0.1:${server.port}';
  }

  /// הפורט של השרת, שמופעל לפי הצורך. קבוע עד [close] — שערי ה-WebView
  /// מתירים רק אותו.
  Future<int> ensurePort() async {
    await _ensureStarted();
    return _server!.port;
  }

  // שתי קריאות במקביל היו מפעילות שני שרתים, והראשון היה נזנח עם פורט אחר.
  Future<void> _ensureStarted() =>
      _starting ??= _start().catchError((Object error, StackTrace stack) {
        _starting = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<void> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _fontToken = _generateToken();
    server.listen(_handleRequest);
    // שאריות `.part` מריצה שקרסה — עד 100MB לכל אחת. הניקוי כאן ולא רק
    // ב-beginUpload, כדי שהן לא ימתינו לתוסף הבא שישמור.
    await _sweepExpiredUploads();
  }

  String _generateToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// רושם קובץ מאושר חדש ומחזיר token טרי וה-URL לטעינה.
  Future<PluginFileRegistration> register({
    required String pluginId,
    required String canonicalPath,
    void Function()? checkAccess,
  }) async {
    await _ensureStarted();
    checkAccess?.call();
    final token = _generateToken();
    _grants[token] = PluginFileGrant(
      pluginId: pluginId,
      canonicalPath: canonicalPath,
    );
    return (token: token, url: _urlFor(pluginId, token));
  }

  /// רושם מחדש קובץ עם token קיים (לאחר reload, כשרישום הזיכרון אבד אך
  /// ה-grant נשמר אצל התוסף). מחזיר את ה-URL הטרי בפורט הנוכחי.
  Future<String> registerWithToken({
    required String pluginId,
    required String canonicalPath,
    void Function()? checkAccess,
    required String token,
  }) async {
    await _ensureStarted();
    checkAccess?.call();
    _grants[token] = PluginFileGrant(
      pluginId: pluginId,
      canonicalPath: canonicalPath,
    );
    return _urlFor(pluginId, token);
  }

  /// URL של גופן [id] בהרצה הזו; [load] נקרא בכל בקשה. ה-token משותף לכל
  /// התוספים — בלעדיו כל דף ב-loopback היה מגיע לגופן המערכת שנבחר.
  Future<String> fontUrl(String id, PluginFontLoader load) async {
    await _ensureStarted();
    _fonts[id] = load;
    return '$origin/fonts/$_fontToken/${Uri.encodeComponent(id)}';
  }

  /// הבייטים של גופן רשום לפי ה-URL שלו, או null. לשער של Windows ו-Android,
  /// שעונה בעצמו בלי בקשת רשת.
  Future<Uint8List?> fontBytesFor(Uri uri) async =>
      isServerUri(uri) ? _loadFont(uri.pathSegments) : null;

  Future<Uint8List?> _loadFont(List<String> segments) async {
    if (_fontToken.isEmpty ||
        segments.length != 3 ||
        segments[0] != 'fonts' ||
        segments[1] != _fontToken) {
      return null;
    }
    final load = _fonts[segments[2]];
    if (load == null) return null;
    try {
      return await load();
    } catch (_) {
      // גופן מערכת שנמחק או asset חסר: הדף נופל ל-fallback.
      return null;
    }
  }

  /// ה-URL כולל את מזהה התוסף כדי שה-WebView של התוסף יוכל לחסום בקשה
  /// לקובץ של תוסף אחר; השרת עצמו אינו יכול לזהות את הפונה (pluginId אינו
  /// סוד ודולף יחד עם ה-URL) — האכיפה היא ב-`shouldInterceptRequest`.
  String _urlFor(String pluginId, String token) =>
      '$origin/f/${Uri.encodeComponent(pluginId)}/$token';

  /// האם [uri] היא בקשה לשרת הקבצים שמותר ל-WebView של [pluginId] לבצע.
  ///
  /// זו נקודת האכיפה היחידה של בידוד בין תוספים: רק כאן ידוע מי הפונה.
  static bool isUriForPlugin(Uri uri, String pluginId) {
    final segments = uri.pathSegments;
    return segments.length == 3 &&
        segments[0] == 'f' &&
        segments[1] == pluginId;
  }

  /// האם [uri] הוא נתיב ההעלאה (`/w/<token>`) של העלאה פתוחה של [pluginId].
  ///
  /// שערי ה-WebView חוסמים כל בקשה לשרת שאינה מזוהה כשל התוסף הפונה,
  /// ו-[isUriForPlugin] מכיר רק נתיבי קבצים (`/f/...`) — כלומר בלי הבדיקה
  /// הזאת ה-PUT של `fs.beginBinaryWrite` נחסם בשער עוד לפני שהגיע לשרת,
  /// וכל שמירה בינארית נופלת ב-"Failed to fetch". token שאינו מוכר אינו
  /// מאושר: לתוסף אין מה לחפש בנתיבי העלאה שאינם שלו.
  bool isUploadUriForPlugin(Uri uri, String pluginId) {
    final segments = uri.pathSegments;
    if (segments.length != 2 || segments[0] != 'w') return false;
    return _uploads[segments[1]]?.pluginId == pluginId;
  }

  /// פותח העלאה: מקצה writeToken חד-פעמי, קובץ temp ו-URL ל-PUT.
  ///
  /// הבייטים אינם עוברים בגשר ה-JS — התוסף שולח אותם ב-PUT יחיד לשרת ה-loopback,
  /// וה-commit (בצד ה-RPC) הוא זה שמחליט לאן הם נכתבים. ה-token הוא ההרשאה:
  /// הוא אקראי בן 256 ביט, משויך לתוסף, חד-פעמי ופג תוך [uploadTtl].
  Future<PluginUploadTicket> beginUpload({
    required String pluginId,
    int? expectedSize,
  }) async {
    await _ensureStarted();
    await _sweepExpiredUploads();

    if (expectedSize != null && expectedSize > maxUploadBytes) {
      throw PluginUploadException(
        'error.too_large',
        'expectedSize exceeds $maxUploadBytes bytes',
      );
    }
    if (expectedSize != null && expectedSize <= 0) {
      throw const PluginUploadException(
        'error.invalid_params',
        'expectedSize must be positive',
      );
    }

    // מכינים את תיקיית ה-temp לפני בדיקת המכסה. מכאן ועד רישום ה-session אין
    // נקודת השהיה, ולכן קריאות מקבילות אינן יכולות לעקוף את המכסה.
    final dir = await _uploadDir();
    final active = _uploads.values.where((u) => u.pluginId == pluginId).length;
    if (active >= maxActiveUploadsPerPlugin) {
      throw const PluginUploadException(
        'error.too_many_requests',
        'too many active uploads for this plugin',
      );
    }

    final token = _generateToken();
    final session = _UploadSession(
      pluginId: pluginId,
      tempFile: File(p.join(dir.path, '$token.part')),
      maxBytes: maxUploadBytes,
      expiresAt: DateTime.now().add(uploadTtl),
    );
    _uploads[token] = session;

    return (
      writeToken: token,
      uploadUrl: '$origin/w/$token',
      expiresAt: session.expiresAt,
      maxBytes: maxUploadBytes,
    );
  }

  /// לוקח העלאה שהושלמה, פעם אחת, ומעביר אותה למצב commit.
  ///
  /// ה-session **אינו** מוסר כאן: „שמור בשם” פותח דיאלוג, וכל עוד הוא פתוח
  /// הקובץ חייב להישאר בבעלות השרת — אחרת `close`, `revokeAllForPlugin`
  /// וה-sweep אינם מכירים אותו, והוא מדליף או נמחק מתחת לידיים. הקורא מחויב
  /// לסגור את המצב הזה ב-[finishCommit].
  ///
  /// `null` אם ה-token אינו מוכר, אינו של התוסף הזה, פג, שה-PUT טרם הושלם, או
  /// שכבר נלקח — כולם מתמזגים לכשל אחד בכוונה, כדי שלא ניתן יהיה להסיק דבר
  /// על token של תוסף אחר.
  Future<File?> takeUpload({
    required String pluginId,
    required String writeToken,
  }) async {
    final session = _uploads[writeToken];
    if (session == null) return null;
    if (session.pluginId != pluginId) return null;
    if (session.isExpired) {
      _uploads.remove(writeToken);
      await _deleteQuietly(session.tempFile);
      return null;
    }
    if (!session.received) return null;
    // חד-פעמי: commit שני על אותו token לא מקבל את הקובץ.
    if (session.committing) return null;

    session.committingSince = DateTime.now();
    return session.tempFile;
  }

  /// מסיים commit: מסיר את ה-session ומוחק את ה-temp. חייב להיקרא בכל מסלול
  /// יציאה מ-commit — הצלחה, ביטול או שגיאה.
  Future<void> finishCommit({
    required String pluginId,
    required String writeToken,
  }) async {
    final session = _uploads[writeToken];
    if (session == null || session.pluginId != pluginId) return;
    // רק session שנלקח ל-commit נסגר כאן. בלי התנאי, קריאה מוקדמת בטעות הייתה
    // מוחקת העלאה שעוד לא הועלתה.
    if (!session.committing) return;
    _uploads.remove(writeToken);
    await _deleteQuietly(session.tempFile);
  }

  /// מבטל העלאה שטרם נכנסה ל-commit, ומוחק את ה-temp שלה.
  ///
  /// נצרך כשהתוסף מחליט שההעלאה אינה רלוונטית יותר — למשל שמירה שהמסמך שלה
  /// הוחלף באמצע. בלי זה ה-temp והסלוט במכסה נתפסים עד שה-token פג.
  ///
  /// **אינו מבטל commit חי**: אם דיאלוג „שמור בשם” פתוח, מחיקת ה-temp הייתה
  /// מפילה אותו. מחזיר `true` אם אין יותר העלאה פעילה עם ה-token הזה — כלומר
  /// גם כשלא היה מה לבטל, כדי שהפעולה תהיה אידמפוטנטית.
  Future<bool> abortUpload({
    required String pluginId,
    required String writeToken,
  }) async {
    final session = _uploads[writeToken];
    if (session == null) return true;
    if (session.pluginId != pluginId) return false;
    if (session.committing) return false;

    _uploads.remove(writeToken);
    await _deleteQuietly(session.tempFile);
    return true;
  }

  /// מספר ההעלאות הפעילות של תוסף. לבדיקות ולאכיפת המגבלה.
  int activeUploadsFor(String pluginId) =>
      _uploads.values.where((u) => u.pluginId == pluginId).length;

  /// סוגר את השרת ומשחרר את כל ה-grants. בפרודקשן השרת חי לכל אורך חיי
  /// האפליקציה; משמש בעיקר לניקוי בין בדיקות.
  Future<void> close() async {
    _grants.clear();
    _fonts.clear();
    _fontToken = '';
    await _sweepExpiredUploads();
    // snapshot: PUT שבאוויר מסיר את ה-session שלו בזמן שאנחנו מוחקים temp,
    // וזה מבטל את האיטרטור.
    final sessions = _uploads.values.toList();
    _uploads.clear();
    for (final session in sessions) {
      await _deleteQuietly(session.tempFile);
    }
    await _server?.close(force: true);
    _server = null;
    _starting = null;
  }

  void revoke(String token) => _grants.remove(token);

  /// מנקה הכול עבור תוסף: grants, העלאות פעילות והקבצים ש-`network.fetchFile`
  /// הוריד אליו למטמון.
  ///
  /// מיועד להסרה, כיבוי או איפוס של תוסף. **אינו נקרא מ-`PluginBridgeAdapter.dispose`
  /// בכוונה:** ה-dispose הוא של מופע, ואותו תוסף יכול להחזיק מופע נוסף חי
  /// (טאב + רקע) שהיה מאבד את ההעלאה שלו.
  ///
  /// שים לב: קריאה כאן **כן** מוחקת temp של commit חי, ולכן הסרה או כיבוי של
  /// תוסף בזמן שדיאלוג „שמור בשם” פתוח יפילו את ה-commit. זה נובע מפעולה
  /// מפורשת של המשתמש, ולכן מקובל — אבל אין להסתמך על כך שהוא ייגמר.
  ///
  /// מופע שנסגר באמצע אינו מדליף לאורך זמן, וזה לא תלוי בקריאה כאן: העלאה
  /// שלא הועלתה פגה תוך [uploadTtl] וה-sweep מוחק את ה-temp, ו-commit שרץ
  /// מסתיים בצד ה-Host גם אם ה-WebView נעלם — ה-`finally` שלו קורא
  /// ל-[finishCommit]. אחרי הפעלה מחדש של האפליקציה אין sessions בזיכרון,
  /// ולכן שאריות `.part` נמחקות כ-orphan (ראו [orphanMinAge]).
  Future<void> revokeAllForPlugin(String pluginId) async {
    final remoteCleanup = _remoteFiles.deleteForPlugin(pluginId);
    _grants.removeWhere((_, grant) => grant.pluginId == pluginId);
    final tokens = _uploads.entries
        .where((e) => e.value.pluginId == pluginId)
        .map((e) => e.key)
        .toList();
    for (final token in tokens) {
      final session = _uploads.remove(token);
      if (session != null) await _deleteQuietly(session.tempFile);
    }
    await remoteCleanup;
  }

  Future<Directory> _uploadDir() async {
    final dir = Directory(p.join(Directory.systemTemp.path, _uploadDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// מוחק temp של העלאות שפגו, וגם שאריות `.part` מריצה קודמת שקרסה.
  Future<void> _sweepExpiredUploads() async {
    final expired = _uploads.entries
        .where((e) => e.value.isExpired)
        .map((e) => e.key)
        .toList();
    for (final token in expired) {
      final session = _uploads.remove(token);
      if (session != null) await _deleteQuietly(session.tempFile);
    }

    // שאריות מריצה שקרסה. הסף הוא [orphanMinAge] ולא [uploadTtl]: התיקייה
    // משותפת לכל מופעי השרת, וסף קצר היה מוחק temp פעיל של מופע אחר.
    try {
      final dir = await _uploadDir();
      final live = _uploads.values.map((u) => u.tempFile.path).toSet();
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is! File || !entry.path.endsWith('.part')) continue;
        if (live.contains(entry.path)) continue;
        final age = DateTime.now().difference((await entry.stat()).modified);
        if (age > orphanMinAge) await _deleteQuietly(entry);
      }
    } catch (_) {
      // ניקוי best-effort; אין להפיל בגללו העלאה.
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // קובץ שנעול או נמחק במקביל — אין מה לעשות.
    }
  }

  /// האם [uri] מצביעה לשרת הקבצים הפנימי (loopback + הפורט שהוקצה).
  bool isServerUri(Uri uri) {
    final server = _server;
    if (server == null) return false;
    if (uri.scheme != 'http') return false;
    const loopbacks = {'127.0.0.1', 'localhost'};
    if (!loopbacks.contains(uri.host.toLowerCase())) return false;
    return uri.hasPort && uri.port == server.port;
  }

  /// `null` הוא ה-origin של דף file:// (ה-WebView הארוז); loopback הוא שרת
  /// הפיתוח המקומי של תוסף development; [pluginAssetScheme] הוא ה-origin של
  /// תוסף שמוגש דרך הסכימה הייעודית (במק) — בלעדיו fetch מהדף נחסם ב-CORS
  /// ("Load failed") וכל שמירה בינארית נכשלת.
  static bool isAllowedOrigin(String origin) {
    if (origin == 'null') return true;
    final uri = Uri.tryParse(origin);
    if (uri == null) return false;
    if (uri.scheme == pluginAssetScheme) return true;
    const loopbacks = {'127.0.0.1', 'localhost', '::1'};
    return loopbacks.contains(uri.host.toLowerCase());
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      // ה-WebView של תוסף רץ מ-origin file:// (Origin: null) או משרת פיתוח
      // מקומי. משקפים רק את אלה — כדי שדף אינטרנט לא יוכל לקרוא את הקובץ.
      final requestOrigin = request.headers.value('origin');
      if (requestOrigin != null && isAllowedOrigin(requestOrigin)) {
        response.headers.set('Access-Control-Allow-Origin', requestOrigin);
        response.headers.set('Vary', 'Origin');
      }
      // PUT ו-Content-Type נדרשים ל-preflight של העלאה.
      response.headers.set(
        'Access-Control-Allow-Methods',
        'GET, HEAD, PUT, OPTIONS',
      );
      response.headers.set(
        'Access-Control-Allow-Headers',
        'Range, Content-Type',
      );
      response.headers.set(
        'Access-Control-Expose-Headers',
        'Content-Range, Accept-Ranges, Content-Length',
      );

      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.noContent;
        return;
      }

      final segments = request.uri.pathSegments;

      // העלאה: PUT יחיד ל-/w/<writeToken>.
      if (segments.length == 2 && segments[0] == 'w') {
        await _handleUpload(request, segments[1]);
        return;
      }

      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }

      if (segments.firstOrNull == 'fonts') {
        await _handleFont(request, segments);
        return;
      }

      // קובץ: GET/HEAD ל-/f/<pluginId>/<token>.
      if (segments.length != 3 || segments[0] != 'f') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final grant = _grants[segments[2]];
      if (grant == null || grant.pluginId != segments[1]) {
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
      final contentType = contentTypeForPath(grant.canonicalPath);
      response.headers.contentType = contentType;
      response.headers.set('X-Content-Type-Options', 'nosniff');
      // Dart שולח כברירת מחדל X-Frame-Options: SAMEORIGIN, וזה חוסם גם את דף
      // התוסף (file:// או otzaria-plugin://, תמיד origin אחר מהשרת). את ההטמעה
      // מגבילה frame-ancestors לדפי התוסף שהקובץ הוענק לו.
      response.headers.removeAll('x-frame-options');
      final policy = [
        // תוסף שמנווט למסמך כזה יוצא מה-CSP של הדף שלו; בלי סקריפט ורשת הוא
        // אינו יכול להוציא דרכו נתונים.
        if (_activeDocumentTypes.contains(contentType.mimeType))
          "sandbox; default-src 'none'; img-src data: blob:; "
              "media-src data: blob:; font-src data:; style-src 'unsafe-inline'",
        pluginFrameAncestorsDirective(grant.pluginId),
      ];
      response.headers.set('Content-Security-Policy', policy.join('; '));

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
      try {
        await response.close();
      } catch (_) {
        // התשובה כבר נסגרה (דחיית העלאה מנתקת את ה-socket), או שהלקוח נעלם.
      }
    }
  }

  Future<void> _handleFont(HttpRequest request, List<String> segments) async {
    final response = request.response;
    final bytes = await _loadFont(segments);
    if (bytes == null) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    response.headers.contentType = ContentType.parse(
      pluginAssetContentType(segments.last),
    );
    response.headers.set('Cache-Control', pluginFontCacheControl);
    response.headers.contentLength = bytes.length;
    if (request.method == 'HEAD') return;
    response.add(bytes);
  }

  /// קולט את גוף ה-PUT אל קובץ ה-temp של ההעלאה.
  ///
  /// כל כשל מוחק את ה-temp ומסיים את ה-session: העלאה חלקית אינה יכולה להפוך
  /// למסמך שנשמר. ה-token חד-פעמי — PUT שני על אותו token נדחה.
  Future<void> _handleUpload(HttpRequest request, String token) async {
    final response = request.response;

    /// דחייה בלי לקרוא את הגוף.
    ///
    /// ב-Dart התשובה נשטפת רק אחרי שגוף הבקשה נצרך, ולכן לקוח שמצהיר על גוף
    /// ואינו שולח אותו לא יראה את הסטטוס. `fetch(uploadUrl, { body: blob })`
    /// תמיד שולח את הגוף עד הסוף, ולכן הוא מקבל את הסטטוס — גם כשהדחייה
    /// הוחלטה לפני הבייט הראשון. `persistentConnection = false` מונע שימוש חוזר
    /// בחיבור שגופו לא נצרך.
    void reject(int statusCode) {
      response.statusCode = statusCode;
      response.persistentConnection = false;
    }

    if (request.method != 'PUT') {
      reject(HttpStatus.methodNotAllowed);
      return;
    }

    final session = _uploads[token];
    // token לא מוכר, של תוסף אחר או שפג — כולם 404, בלי להסביר מה מהם.
    if (session == null) {
      reject(HttpStatus.notFound);
      return;
    }
    if (session.isExpired) {
      _uploads.remove(token);
      await _deleteQuietly(session.tempFile);
      reject(HttpStatus.gone);
      return;
    }
    if (session.started) {
      reject(HttpStatus.conflict);
      return;
    }

    final declared = request.contentLength;
    if (declared <= 0) {
      reject(HttpStatus.lengthRequired);
      return;
    }
    if (declared > session.maxBytes) {
      reject(HttpStatus.requestEntityTooLarge);
      return;
    }

    session.started = true;
    final sink = session.tempFile.openWrite();
    var closed = false;
    var written = 0;

    Future<void> closeSink() async {
      if (closed) return;
      closed = true;
      try {
        await sink.close();
      } catch (_) {
        // הזרם נקטע או כבר נסגר.
      }
    }

    Future<void> discard() async {
      await closeSink();
      _uploads.remove(token);
      await _deleteQuietly(session.tempFile);
    }

    try {
      await for (final chunk in request) {
        written += chunk.length;
        // הגנה בלבד: framing של HTTP חוסם גוף ארוך מ-Content-Length, אבל בלי
        // הבדיקה הכתיבה לדיסק אינה חסומה.
        if (written > declared || written > session.maxBytes) {
          await discard();
          reject(HttpStatus.requestEntityTooLarge);
          return;
        }
        sink.add(chunk);
      }
      await sink.flush();
      await closeSink();

      if (written != declared) {
        // גוף קטוע: הצהיר יותר ממה ששלח.
        await discard();
        response.statusCode = HttpStatus.badRequest;
        return;
      }

      session.received = true;
      response.statusCode = HttpStatus.noContent;
    } catch (_) {
      await discard();
      response.statusCode = HttpStatus.internalServerError;
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

  /// סוג התוכן שבו מוגש קובץ, לפי הסיומת בלבד.
  static ContentType contentTypeForPath(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.pdf':
        return ContentType('application', 'pdf');
      case '.txt':
      case '.text':
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
