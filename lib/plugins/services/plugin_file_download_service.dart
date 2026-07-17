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
  /// תיקיית האב נוצרת במידת הצורך. ללא [resume] קובץ קיים באותו נתיב נדרס;
  /// עם [resume] הוא עשוי להתווסף אליו (ראה למטה).
  ///
  /// כאשר [resume] הוא `true` ויש קובץ חלקי בנתיב [destPath], ההורדה ממשיכה
  /// מנקודת הסיום של הקובץ הקיים באמצעות `Range: bytes=N-`:
  ///  * **206 Partial Content** עם `Content-Range` שמתחיל בדיוק ב-offset
  ///    המבוקש → הנתונים מצורפים לקובץ. offset שאינו תואם אינו מצורף בעיוור
  ///    (היה יוצר קובץ פגום) — הקובץ החלקי נמחק ונזרקת שגיאה כדי שניסיון נקי
  ///    יתחיל מ-0.
  ///  * **200 OK** (השרת התעלם מה-Range) → הקובץ נכתב מחדש מ-0.
  ///  * **416 Range Not Satisfiable** → אם ה-total ב-`Content-Range` שווה
  ///    לגודל הקובץ הקיים, ההורדה כבר הושלמה בעבר ומוחזרת הצלחה; אחרת הקובץ
  ///    החלקי אינו תואם לשרת, הוא נמחק ונזרקת שגיאה.
  ///
  /// אם ידוע הגודל הכולל (מ-`Content-Range`/`Content-Length`) ובסיום התקבלו
  /// פחות בייטים — ההורדה נחשבת חלקית ונזרקת שגיאה (הקובץ אינו מדווח כהצלחה).
  /// במצב [resume] כשל אינו מוחק את הקובץ החלקי, כך שניסיון נוסף יוכל להמשיך
  /// מאותה נקודה.
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

    final contentRange = response.headers['content-range'];

    // 416 Range Not Satisfiable — נמסר מ-[_fetchFollowingAllowedRedirects]
    // (במקום שגיאה) רק כשביקשנו Range. אם ה-total ב-Content-Range שווה בדיוק
    // לגודל הקובץ הקיים → ההורדה כבר הושלמה בעבר; מחזירים הצלחה. אחרת הקובץ
    // החלקי אינו תואם למה שבשרת (למשל שריד של קובץ אחר) — מוחקים אותו וזורקים,
    // כדי שניסיון נוסף יתחיל נקי.
    if (response.statusCode == 416) {
      await response.stream.timeout(_stallTimeout).drain<void>();
      final total = _contentRangeTotal(contentRange);
      if (existingBytes > 0 && total == existingBytes) {
        return PluginFileDownloadResult(outFile.path, p.basename(outFile.path));
      }
      if (await outFile.exists()) {
        await outFile.delete();
      }
      throw Exception('שגיאה בהורדת הקובץ (416)');
    }

    // קביעת מצב הכתיבה — עם אימות ש-206 באמת ממשיך מ-existingBytes לפני
    // צירוף (append עיוור על offset לא תואם יוצר קובץ פגום בשקט).
    // expectedTotal = הגודל הסופי הצפוי של הקובץ על הדיסק, לבדיקת שלמות.
    final FileMode writeMode;
    int? expectedTotal;
    if (response.statusCode == 206) {
      final serverStart = _contentRangeStart(contentRange);
      expectedTotal = _contentRangeTotal(contentRange);
      if (existingBytes > 0 && serverStart == existingBytes) {
        // השרת כיבד את ה-Range והמשיך בדיוק מהנקודה הנכונה → צירוף.
        writeMode = FileMode.append;
      } else if (serverStart == 0) {
        // 206 שמתחיל מ-0 → הגוף מייצג את הקובץ המלא; כתיבה מחדש.
        writeMode = FileMode.write;
      } else {
        // 206 עם offset שאינו תואם ל-existingBytes ואינו 0 → אי אפשר לצרף
        // בבטחה. מנקזים, מוחקים את החלקי וזורקים כדי שניסיון נוסף יתחיל נקי.
        await response.stream.timeout(_stallTimeout).drain<void>();
        if (await outFile.exists()) {
          await outFile.delete();
        }
        throw Exception('שגיאה בהורדת הקובץ (206 עם טווח לא תואם)');
      }
    } else {
      // 200 — השרת התעלם מה-Range (או שלא ביקשנו); כתיבה מחדש מ-0.
      writeMode = FileMode.write;
      expectedTotal = response.contentLength;
    }

    final sink = outFile.openWrite(mode: writeMode);
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

    // בדיקת שלמות: אם ידוע הגודל הכולל וברשותנו פחות — ההורדה נקטעה (השרת
    // סגר את החיבור נקי לפני שהסתיים). זורקים כדי שהתוסף לא יחשוב שההצלחה
    // מלאה; במצב resume הקובץ החלקי נשמר להמשך.
    if (expectedTotal != null) {
      final finalBytes = await outFile.length();
      if (finalBytes != expectedTotal) {
        if (!resume && await outFile.exists()) {
          await outFile.delete();
        }
        throw Exception(
            'שגיאה בהורדת הקובץ (התקבלו $finalBytes מתוך $expectedTotal בייטים)');
      }
    }

    return PluginFileDownloadResult(outFile.path, p.basename(outFile.path));
  }

  /// מבצעת GET תוך מעקב ידני אחרי redirects, כשכל יעד נבדק מול [isAllowed]
  /// ועבור יעדי redirect גם מול [isRedirectAllowed] (בהינתן ה-hop הקודם).
  /// מחזירה את התשובה הסופית (2xx). מנקזת תשובות-ביניים כדי לשחרר sockets.
  /// [rangeStart] אופציונלי — אם גדול מ-0, מוסיף `Range: bytes=N-` לכל בקשה
  /// בשרשרת ה-redirects כדי לתמוך בהמשך הורדה (resume). כאשר [rangeStart] > 0
  /// גם תשובת **416** מוחזרת לקורא (במקום שגיאה), כדי שיוכל לזהות קובץ שכבר
  /// הושלם או טווח לא-תואם ולטפל בהם.
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
        // 416 בעת resume נמסר לקורא לטיפול (קובץ שכבר הושלם / טווח לא תואם)
        // במקום שגיאה. הגוף אינו מנוקז כאן — הקורא מנקז אותו.
        if (rangeStart > 0 && response.statusCode == 416) {
          return response;
        }
        await response.stream.timeout(_stallTimeout).drain<void>();
        throw Exception('שגיאה בהורדת הקובץ (${response.statusCode})');
      }

      return response;
    }
    throw Exception('שגיאה בהורדת הקובץ (יותר מדי redirects)');
  }

  /// מחלצת את ה-offset ההתחלתי (הבייט הראשון) מכותרת `Content-Range` בצורה
  /// `bytes 12345-99999/123456`. מחזירה `null` אם הכותרת חסרה או בפורמט לא
  /// מוכר (למשל `bytes */123456` בתשובת 416).
  static int? _contentRangeStart(String? header) {
    if (header == null) return null;
    final match = RegExp(r'bytes\s+(\d+)-').firstMatch(header);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// מחלצת את האורך הכולל של המשאב (החלק שאחרי `/`) מכותרת `Content-Range`.
  /// מחזירה `null` אם הכותרת חסרה או שהאורך אינו ידוע (`*`).
  static int? _contentRangeTotal(String? header) {
    if (header == null) return null;
    final match = RegExp(r'/(\d+)\s*$').firstMatch(header);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
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
