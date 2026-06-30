import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria/core/http_client_registry.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// תוצאת הורדת קובץ.
class PluginFileDownloadResult {
  /// הנתיב המלא של הקובץ שנשמר.
  final String path;

  /// שם הקובץ שנשמר בפועל (לאחר תיקון התנגשויות שמות).
  final String filename;

  const PluginFileDownloadResult(this.path, this.filename);
}

/// שירות להורדת קובץ מ-URL אל תיקיית ההורדות של המערכת.
///
/// משמש את ה-RPC `network.download` של גשר התוספים. ההורדה מתבצעת בצד
/// אוצריא (Flutter) ולא ב-WebView, מכיוון שה-WebView נטען מ-origin מסוג
/// `file://` ואינו יכול לכתוב לדיסק (אין File System Access API).
///
/// **גבול אבטחה:** השירות אינו עוקב אוטומטית אחרי redirects. כל קפיצה —
/// כולל ה-URL ההתחלתי — נבדקת מול ה-predicate [isAllowed] שמועבר ע"י
/// הקורא (האדפטר → `isUriAllowedForPluginNetwork`). כך URL מותר אינו יכול
/// להפנות ליעד שאינו ב-allowlist ולעקוף את מודל ההרשאות.
class PluginFileDownloadService {
  final http.Client _client;
  late final FutureOr<void> Function() _closer = _client.close;

  /// מספר ה-redirects המרבי שיתבצע לפני שתיזרק שגיאה.
  static const int _maxRedirects = 5;

  /// משך מרבי ללא התקדמות לפני שההורדה נקטעת ב-[TimeoutException].
  ///
  /// timeout על *תקיעה* ולא על משך כולל: הוא מתאפס עם כל בייט נכנס, כך
  /// שהורדה איטית או של קובץ גדול נמשכת כל עוד הנתונים זורמים, ורק חיבור
  /// שמת באמת (אין בייטים כלל בחלון הזה) נקטע. חל גם על שלב יצירת החיבור.
  final Duration _stallTimeout;

  PluginFileDownloadService({
    http.Client? client,
    this._stallTimeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client() {
    HttpClientRegistry.register(_closer);
  }

  /// משחרר את ה-client ומסיר אותו מ-[HttpClientRegistry]. יש לקרוא כשהשירות
  /// אינו נחוץ יותר (אחרת ה-registry צובר closers ומחזיק sockets פתוחים).
  void dispose() {
    HttpClientRegistry.unregister(_closer);
    _client.close();
  }

  /// מורידה את הקובץ מ-[downloadUri] אל תיקיית ההורדות.
  ///
  /// [isAllowed] נבדק על ה-URL ההתחלתי וגם על כל יעד redirect (מול הרשימה
  /// הגלובלית). [isRedirectAllowed] (אופציונלי) מתיר יעד redirect שאינו
  /// ברשימה הגלובלית, בהינתן ה-hop הקודם — משמש למקרה הספציפי של redirect
  /// מ-GitHub Releases ל-CDN, מבלי לפתוח את ה-CDN לגישה ישירה. אם קפיצה
  /// כלשהי אינה מותרת בשתי הבדיקות — נזרקת שגיאה וההורדה לא מתבצעת.
  /// [filename] אופציונלי — אם לא סופק, נגזר משם הקובץ ב-URL ההתחלתי. אם כבר
  /// קיים קובץ באותו שם, נוספת לו סיומת מספרית (` (1)`) כדי לא לדרוס.
  /// [targetDir] משמש בעיקר לבדיקות; כברירת מחדל תיקיית ההורדות של המערכת.
  ///
  /// מחזירה [PluginFileDownloadResult]. זורקת [Exception] אם ההורדה נכשלה
  /// (קוד סטטוס מחוץ ל-2xx), בקפיצה לא-מותרת, או חריגה ממספר ה-redirects.
  Future<PluginFileDownloadResult> downloadToDownloads(
    Uri downloadUri, {
    required Future<bool> Function(Uri) isAllowed,
    bool Function(Uri previous, Uri target)? isRedirectAllowed,
    String? filename,
    Directory? targetDir,
  }) async {
    final response = await _fetchFollowingAllowedRedirects(
      downloadUri,
      isAllowed,
      isRedirectAllowed,
    );

    final dir = targetDir ?? await _resolveDownloadsDir();
    await dir.create(recursive: true);

    final baseName = _sanitizeFilename(
      (filename == null || filename.trim().isEmpty)
          ? _filenameFromUri(downloadUri)
          : filename,
    );
    final outFile = _resolveNonColliding(dir, baseName);

    final sink = outFile.openWrite();
    try {
      await sink.addStream(response.stream.timeout(_stallTimeout));
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      if (await outFile.exists()) {
        await outFile.delete();
      }
      rethrow;
    }

    return PluginFileDownloadResult(outFile.path, p.basename(outFile.path));
  }

  /// מורידה את הקובץ מ-[downloadUri] אל נתיב קובץ מלא [destPath].
  ///
  /// בשונה מ-[downloadToDownloads], היעד הוא קובץ ספציפי (ולא תיקיית
  /// ההורדות), המאפשר לתוסף לשמור את הקובץ למבנה תיקיות שהמשתמש בחר.
  /// תיקיית האב נוצרת במידת הצורך, וקובץ קיים באותו נתיב נדרס.
  ///
  /// כאשר [resume] הוא `true` ויש קובץ חלקי בנתיב [destPath], ההורדה ממשיכה
  /// מנקודת הסיום של הקובץ הקיים באמצעות `Range: bytes=N-`. אם השרת מחזיר
  /// 206 Partial Content — הנתונים מצורפים לקובץ; אם הוא מחזיר 200 (התעלם
  /// מה-Range) — הקובץ נכתב מחדש. במצב resume כשל לא ימחק את הקובץ החלקי,
  /// כך שניסיון נוסף יוכל להמשיך מאותה נקודה.
  ///
  /// **גבול אבטחה:** השירות אינו מאמת את [destPath] — האחריות לוודא שהוא
  /// בתוך תיקייה שהמשתמש אישר מוטלת על הקורא (האדפטר). אכיפת ה-allowlist על
  /// ה-URL ועל כל redirect זהה ל-[downloadToDownloads]: [isAllowed] נבדק על
  /// ה-URL ההתחלתי ועל כל קפיצה, ו-[isRedirectAllowed] (אופציונלי) מתיר יעד
  /// redirect שאינו ברשימה הגלובלית בהינתן ה-hop הקודם.
  ///
  /// מחזירה [PluginFileDownloadResult] עם הנתיב והשם שנשמרו. זורקת [Exception]
  /// בקוד סטטוס שאינו 2xx, בקפיצה לא-מותרת, או בחריגה ממספר ה-redirects.
  Future<PluginFileDownloadResult> downloadToPath(
    Uri downloadUri,
    String destPath, {
    required Future<bool> Function(Uri) isAllowed,
    bool Function(Uri previous, Uri target)? isRedirectAllowed,
    bool resume = false,
  }) async {
    final outFile = File(destPath);
    await outFile.parent.create(recursive: true);

    // אם resume=true ויש קובץ חלקי — שלח Range: bytes=N-
    final existingBytes =
        (resume && await outFile.exists()) ? await outFile.length() : 0;

    final response = await _fetchFollowingAllowedRedirects(
      downloadUri,
      isAllowed,
      isRedirectAllowed,
      rangeStart: existingBytes,
    );

    // 206 = השרת כיבד את ה-Range → צרף לקובץ קיים; 200 = כתוב מחדש
    final shouldAppend = existingBytes > 0 && response.statusCode == 206;
    final sink = outFile.openWrite(
      mode: shouldAppend ? FileMode.append : FileMode.write,
    );

    try {
      await sink.addStream(response.stream.timeout(_stallTimeout));
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      // במצב resume — שמור את הקובץ החלקי לניסיון הבא
      if (!resume && await outFile.exists()) {
        await outFile.delete();
      }
      rethrow;
    }

    return PluginFileDownloadResult(outFile.path, p.basename(outFile.path));
  }

  /// מבצעת GET תוך מעקב ידני אחרי redirects, כשכל יעד נבדק מול [isAllowed]
  /// ועבור יעדי redirect גם מול [isRedirectAllowed] (בהינתן ה-hop הקודם).
  /// מחזירה את התשובה הסופית (2xx). מנקזת תשובות-ביניים כדי לשחרר sockets.
  /// [rangeStart] אופציונלי — אם גדול מ-0, מוסיף `Range: bytes=N-` לכל בקשה
  /// בשרשרת ה-redirects כדי לתמוך בהמשך הורדה (resume).
  Future<http.StreamedResponse> _fetchFollowingAllowedRedirects(
    Uri initialUri,
    Future<bool> Function(Uri) isAllowed,
    bool Function(Uri previous, Uri target)? isRedirectAllowed, {
    int rangeStart = 0,
  }) async {
    var current = initialUri;
    Uri? previous;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      // ה-URL ההתחלתי חייב להיות ברשימה הגלובלית. יעד redirect מותר אם הוא
      // ברשימה הגלובלית, או שאושר במפורש ע"י isRedirectAllowed לפי ה-hop הקודם.
      final permitted =
          await isAllowed(current) ||
          (previous != null &&
              (isRedirectAllowed?.call(previous, current) ?? false));
      if (!permitted) {
        throw Exception(
            'error.forbidden: הכתובת אינה ברשימת ההיתר לגישת רשת של תוספים');
      }

      final request = http.Request('GET', current)..followRedirects = false;
      if (rangeStart > 0) {
        request.headers['Range'] = 'bytes=$rangeStart-';
      }
      final response = await _client.send(request).timeout(_stallTimeout);

      if (_isRedirect(response.statusCode)) {
        final location = response.headers['location'];
        // ניקוז גוף תשובת ה-redirect כדי לשחרר את החיבור.
        await response.stream.timeout(_stallTimeout).drain<void>();
        if (location == null || location.isEmpty) {
          throw Exception('שגיאה בהורדת הקובץ (redirect ללא Location)');
        }
        previous = current;
        current = current.resolve(location);
        continue;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.timeout(_stallTimeout).drain<void>();
        throw Exception('שגיאה בהורדת הקובץ (${response.statusCode})');
      }

      return response;
    }
    throw Exception('שגיאה בהורדת הקובץ (יותר מדי redirects)');
  }

  bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  /// מאתרת את תיקיית ההורדות של המערכת, עם נפילה חזרה לתיקיית המסמכים
  /// בפלטפורמות שבהן [getDownloadsDirectory] אינו נתמך (כגון אנדרואיד).
  Future<Directory> _resolveDownloadsDir() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
    return getApplicationDocumentsDirectory();
  }

  String _filenameFromUri(Uri uri) {
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    return last.isEmpty ? 'download' : last;
  }

  /// מסירה תווי נתיב ותווים לא חוקיים משם הקובץ כדי למנוע path traversal
  /// וכתיבה מחוץ לתיקיית ההורדות.
  String _sanitizeFilename(String name) {
    final base = p.basename(name.trim());
    final cleaned = base.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    return cleaned.isEmpty ? 'download' : cleaned;
  }

  /// מחזירה קובץ ב-[dir] בשם [name], ואם הוא כבר קיים מוסיפה ` (n)` לפני
  /// הסיומת כדי לא לדרוס קובץ קיים.
  File _resolveNonColliding(Directory dir, String name) {
    var candidate = File(p.join(dir.path, name));
    if (!candidate.existsSync()) return candidate;

    final ext = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    var counter = 1;
    while (candidate.existsSync()) {
      candidate = File(p.join(dir.path, '$stem ($counter)$ext'));
      counter++;
    }
    return candidate;
  }
}
