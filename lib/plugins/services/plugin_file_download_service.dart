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
  /// תיקיית האב נוצרת במידת הצורך. ללא [resume] קובץ קיים נדרס. עם [resume]
  /// השירות ממשיך רק חלקי שנוצר על ידו ושויך לאותו URL ול-ETag חזק בקובץ צד.
  /// בקשת ההמשך משתמשת ב-`Range` וב-`If-Range`, כדי ששינוי במשאב יגרום להורדה
  /// מלאה במקום לחיבור בייטים מגרסאות שונות.
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
    final resumeFile = File('$destPath.resume');

    var existingBytes = 0;
    String? validator;
    var hasResumeState = false;
    if (resume && await outFile.exists()) {
      final state = await _readResumeState(resumeFile);
      validator = _strongEtag(state?.etag);
      if (state?.url == downloadUri.toString() && validator != null) {
        existingBytes = await outFile.length();
        hasResumeState = existingBytes > 0;
      }
    }
    if (!hasResumeState) await _deleteResumeState(resumeFile);

    final response = await _fetchFollowingAllowedRedirects(
      downloadUri,
      isAllowed,
      isRedirectAllowed,
      rangeStart: existingBytes,
      ifRange: validator,
    );

    final contentRange = response.headers['content-range'];

    if (response.statusCode == 416) {
      await _abandonBody(response);
      final total = _unsatisfiedRangeTotal(contentRange);
      if (hasResumeState && total == existingBytes) {
        await _deleteResumeState(resumeFile);
        return PluginFileDownloadResult(outFile.path, p.basename(outFile.path));
      }
      if (await outFile.exists()) await outFile.delete();
      await _deleteResumeState(resumeFile);
      throw Exception('שגיאה בהורדת הקובץ (416)');
    }

    final FileMode writeMode;
    int? expectedTotal;
    int? expectedBodyBytes;
    var bytesBeforeResponse = 0;
    if (response.statusCode == 206) {
      final range = _parseContentRange(contentRange);
      final matchingResume =
          range != null && hasResumeState && range.start == existingBytes;
      final restartFromZero = range != null && range.start == 0;
      if (!matchingResume && !restartFromZero) {
        await _rejectResponse(
          response,
          outFile,
          resumeFile,
          'שגיאה בהורדת הקובץ (206 עם טווח לא תואם)',
        );
      }

      final responseValidator = _strongEtag(response.headers['etag']);
      if (matchingResume) {
        if (responseValidator != null && responseValidator != validator) {
          await _rejectResponse(
            response,
            outFile,
            resumeFile,
            'שגיאה בהורדת הקובץ (ETag לא תואם)',
          );
        }
        writeMode = FileMode.append;
        bytesBeforeResponse = existingBytes;
      } else {
        if (await outFile.exists()) await outFile.delete();
        writeMode = FileMode.write;
        validator = responseValidator;
      }
      expectedTotal = range.total;
      expectedBodyBytes = range.end - range.start + 1;
    } else {
      if (await outFile.exists()) await outFile.delete();
      writeMode = FileMode.write;
      expectedTotal = response.contentLength;
      expectedBodyBytes = response.contentLength;
      validator = _strongEtag(response.headers['etag']);
    }

    hasResumeState =
        resume &&
        validator != null &&
        await _writeResumeState(
          resumeFile,
          downloadUri.toString(),
          validator,
        );
    if (!hasResumeState) {
      await _deleteResumeState(resumeFile);
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
      final partialBytes = await outFile.exists()
          ? await outFile.length()
          : null;
      final receivedBytes = partialBytes == null
          ? null
          : partialBytes - bytesBeforeResponse;
      final safePartial =
          hasResumeState &&
          partialBytes != null &&
          receivedBytes != null &&
          receivedBytes >= 0 &&
          (expectedBodyBytes == null || receivedBytes <= expectedBodyBytes) &&
          (expectedTotal == null || partialBytes <= expectedTotal);
      if (!safePartial && await outFile.exists()) await outFile.delete();
      if (!await outFile.exists()) await _deleteResumeState(resumeFile);
      rethrow;
    }

    final finalBytes = await outFile.length();
    final receivedBytes = finalBytes - bytesBeforeResponse;
    if (expectedBodyBytes != null && receivedBytes != expectedBodyBytes) {
      final resumableShortRead =
          hasResumeState &&
          receivedBytes >= 0 &&
          receivedBytes < expectedBodyBytes;
      if (!resumableShortRead) {
        await outFile.delete();
        await _deleteResumeState(resumeFile);
      }
      throw Exception(
        'שגיאה בהורדת הקובץ (הטווח הצהיר $expectedBodyBytes בייטים, התקבלו $receivedBytes)',
      );
    }

    if (expectedTotal != null) {
      if (finalBytes != expectedTotal) {
        final resumableShortRead = hasResumeState && finalBytes < expectedTotal;
        if (!resumableShortRead && await outFile.exists()) {
          await outFile.delete();
          await _deleteResumeState(resumeFile);
        }
        throw Exception(
          'שגיאה בהורדת הקובץ (התקבלו $finalBytes מתוך $expectedTotal בייטים)',
        );
      }
    }

    await _deleteResumeState(resumeFile);
    return PluginFileDownloadResult(outFile.path, p.basename(outFile.path));
  }

  /// מבצעת GET תוך מעקב ידני אחרי redirects, כשכל יעד נבדק מול [isAllowed]
  /// ועבור יעדי redirect גם מול [isRedirectAllowed] (בהינתן ה-hop הקודם).
  /// מחזירה את התשובה הסופית (2xx). מנקזת תשובות-ביניים כדי לשחרר sockets.
  /// [rangeStart] ו-[ifRange] נשמרים בכל שרשרת ה-redirects לצורך resume בטוח.
  Future<http.StreamedResponse> _fetchFollowingAllowedRedirects(
    Uri initialUri,
    Future<bool> Function(Uri) isAllowed,
    bool Function(Uri previous, Uri target)? isRedirectAllowed, {
    int rangeStart = 0,
    String? ifRange,
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
          'error.forbidden: הכתובת אינה ברשימת ההיתר לגישת רשת של תוספים',
        );
      }

      final request = http.Request('GET', current)..followRedirects = false;
      request.headers['Accept-Encoding'] = 'identity';
      if (rangeStart > 0) {
        request.headers['Range'] = 'bytes=$rangeStart-';
        if (ifRange != null) request.headers['If-Range'] = ifRange;
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

  static final _contentRangePattern = RegExp(
    r'^bytes\s+(\d+)-(\d+)/(\d+)\s*$',
    caseSensitive: false,
  );
  static final _unsatisfiedRangePattern = RegExp(
    r'^bytes\s+\*/(\d+)\s*$',
    caseSensitive: false,
  );

  static ({int start, int end, int total})? _parseContentRange(String? header) {
    final match = header == null
        ? null
        : _contentRangePattern.firstMatch(header);
    if (match == null) return null;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    if (start == null || end == null || total == null) return null;
    if (start > end || end >= total) return null;
    return (start: start, end: end, total: total);
  }

  static int? _unsatisfiedRangeTotal(String? header) {
    final match = header == null
        ? null
        : _unsatisfiedRangePattern.firstMatch(header);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static String? _strongEtag(String? value) {
    final etag = value?.trim();
    if (etag == null || etag.isEmpty || etag.startsWith('W/')) return null;
    return etag;
  }

  Future<({String url, String etag})?> _readResumeState(File file) async {
    try {
      if (!await file.exists()) return null;
      final lines = (await file.readAsString()).split('\n');
      if (lines.length < 2) return null;
      return (url: lines.first, etag: lines[1]);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _writeResumeState(
    File file,
    String url,
    String etag,
  ) async {
    try {
      await file.writeAsString('$url\n$etag', flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteResumeState(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _abandonBody(http.StreamedResponse response) async {
    try {
      await response.stream.listen((_) {}).cancel().timeout(_stallTimeout);
    } catch (_) {}
  }

  Future<Never> _rejectResponse(
    http.StreamedResponse response,
    File outFile,
    File resumeFile,
    String message,
  ) async {
    await _abandonBody(response);
    if (await outFile.exists()) await outFile.delete();
    await _deleteResumeState(resumeFile);
    throw Exception(message);
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
