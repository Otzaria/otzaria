import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/utils/http_redirect_download.dart';

/// מידע על ה-release האחרון של מילון המורפולוגיה (`lexical.db`).
class MagicDictionaryRelease {
  /// תג ה-release (למשל `v0.3.0`) — משמש לזיהוי גרסה מותקנת.
  final String tag;

  /// כתובת ההורדה הישירה של נכס ה-`lexical.db`.
  final Uri downloadUrl;

  /// גודל הנכס בבייטים, אם דווח ב-API (לחישוב התקדמות). `null` אם לא ידוע.
  final int? sizeBytes;

  /// ה-sha256 של הנכס כפי שדווח ב-API (`digest`), או `null` כשאינו זמין.
  final String? sha256;

  const MagicDictionaryRelease({
    required this.tag,
    required this.downloadUrl,
    this.sizeBytes,
    this.sha256,
  });
}

/// מוריד את מילון המורפולוגיה (`lexical.db`) שמשמש את **החיפוש המקורב**
/// מ-GitHub Releases של `SeforimMagicIndexer`, אל הנתיב שבו המנוע מצפה למצוא
/// אותו ([AppPaths.getMagicDictionaryPath]).
///
/// ההורדה נעשית בצד Dart (ולא ב-Rust) בכוונה: Flutter כבר מנהל הרשאות/אחסון,
/// וכך מנוע החיפוש נשאר נטול תלות HTTP/TLS — מה שמפשט מאוד את הבנייה ל-Android
/// ול-iOS. המנוע רק *פותח* קובץ מקומי; מי שמוריד אותו זה השירות הזה.
///
/// כל הפעולות best-effort: אם ההורדה נכשלה או שאין רשת, החיפוש המקורב פשוט
/// פועל ללא הרחבה מורפולוגית (המנוע נופל חזרה ל-fuzzy הרגיל).
class MagicDictionaryDownloader {
  /// נקודת ה-API של ה-release האחרון.
  static const String latestReleaseApi =
      'https://api.github.com/repos/Otzaria/SeforimMagicIndexer/releases/latest';

  static const int _maxRedirects = 5;
  static final RegExp _sha256DigestPattern = RegExp(
    r'^sha256:[0-9a-fA-F]{64}$',
  );

  final http.Client _client;
  final bool _ownsClient;
  final Future<String> Function() _destinationProvider;

  /// עוטף את החלפת הקובץ: המנוע משחרר את המילון לפניה וטוען אותו אחריה.
  final Future<void> Function(Future<void> Function() replace)? _aroundReplace;

  /// משך מרבי ללא התקדמות לפני קטיעה ([TimeoutException]). מתאפס עם כל בייט,
  /// כך שהורדה איטית של קובץ גדול (~57MB) נמשכת כל עוד יש זרימה.
  final Duration _stallTimeout;

  MagicDictionaryDownloader({
    http.Client? client,
    Future<String> Function()? destinationProvider,
    this._stallTimeout = const Duration(seconds: 60),
    this._aroundReplace,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _destinationProvider =
           destinationProvider ?? AppPaths.getMagicDictionaryPath;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  /// מוודא שגרסת המילון האחרונה מותקנת. מוריד רק אם חסר קובץ, אם הגרסה
  /// השמורה ישנה מ-[release] האחרון, או אם [force].
  ///
  /// מחזיר `true` אם בסוף הפעולה קיים `lexical.db` תקין במקום (כולל המקרה
  /// שכבר היה מעודכן). מחזיר `false` אם לא ניתן היה להבטיח קובץ (אין רשת,
  /// שגיאת API/הורדה) — ללא זריקת חריגה כלפי מעלה.
  Future<bool> ensureLatest({
    void Function(double progress)? onProgress,
    bool force = false,
  }) async {
    final dest = await _destinationProvider();
    try {
      final release = await fetchLatestRelease();
      final installed = await installedVersion();
      // הסימון עשוי להיות תג (התקנות ישנות) או digest (מתקיני FULL) — שניהם
      // עדכניים; ההשוואה לפי digest שורדת גם החלפת תג עם אותו קובץ.
      var upToDate =
          !force &&
          await _fileIsUsable(dest) &&
          installed != null &&
          (installed == release.tag || installed == release.sha256);
      if (upToDate && release.sha256 != null && installed != release.sha256) {
        // המרה חד-פעמית של סימון-תג ל-digest, רק אחרי אימות שהקובץ המקומי
        // אכן תואם — אחרת קובץ סוטה היה מוחתם כעדכני לצמיתות.
        if (await _fileSha256(dest) == release.sha256) {
          await writeVersionMarker(dest, release.sha256!);
        } else {
          upToDate = false;
        }
      }
      if (upToDate) {
        await _discardStaged(dest);
        onProgress?.call(1.0);
        return true;
      }
      // עותק מאומת שהחלפתו נכשלה קודם (קובץ נעול) מותקן בלי הורדה חוזרת.
      final version = release.sha256 ?? release.tag;
      if (force || !await _hasStagedVersion(dest, version, release.sizeBytes)) {
        await _download(release, dest, onProgress);
      }
      final aroundReplace = _aroundReplace;
      Future<void> install() => _installStaged(dest);
      await (aroundReplace == null ? install() : aroundReplace(install));
      onProgress?.call(1.0);
      return true;
    } catch (_) {
      // אם נכשלנו אבל כבר יש קובץ שמיש מהורדה קודמת — עדיין שמיש.
      return _fileIsUsable(dest);
    }
  }

  /// שולף את פרטי ה-release האחרון מ-GitHub. זורק [Exception] בכשל.
  Future<MagicDictionaryRelease> fetchLatestRelease() async {
    final response = await _send(
      Uri.parse(latestReleaseApi),
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw Exception('GitHub API החזיר ${response.statusCode}');
    }
    final body = await response.stream.bytesToString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final tag = (json['tag_name'] as String?)?.trim();
    final assets = (json['assets'] as List?) ?? const [];
    Map<String, dynamic>? asset;
    // נכסי המילון לפי סדר העדפה, מזוהים לפי סיומת ה-URL.
    for (final name in DatabaseConstants.lexicalReleaseAssetFileNames) {
      asset = assets.cast<Map<String, dynamic>>().firstWhereOrNull(
        (a) =>
            (a['browser_download_url'] as String?)?.endsWith('/$name') ?? false,
      );
      if (asset != null) break;
    }
    if (tag == null || tag.isEmpty || asset == null) {
      throw Exception('לא נמצא נכס lexical.db ב-release האחרון');
    }
    return MagicDictionaryRelease(
      tag: tag,
      downloadUrl: Uri.parse(asset['browser_download_url'] as String),
      sizeBytes: (asset['size'] as num?)?.toInt(),
      sha256: switch (asset['digest']) {
        final String digest when _sha256DigestPattern.hasMatch(digest) =>
          digest.substring('sha256:'.length).toLowerCase(),
        _ => null,
      },
    );
  }

  /// הסימון המותקן כעת — digest של הנכס, או תג release בהתקנות ישנות.
  /// `null` אם אין מילון/סימון גרסה.
  Future<String?> installedVersion() async {
    final dest = await _destinationProvider();
    final marker = File(_versionPath(dest));
    if (!await marker.exists()) return null;
    final tag = (await marker.readAsString()).trim();
    return tag.isEmpty ? null : tag;
  }

  // ── פנימי ──────────────────────────────────────────────────────────────

  /// מוריד את הנכס אל קובץ `.part` זמני, ואחרי אימות מעביר אותו לעותק
  /// הממתין (`.next`) עם סימון הגרסה שלו — כדי שלא יישאר קובץ חלקי שנראה תקין.
  Future<void> _download(
    MagicDictionaryRelease release,
    String dest,
    void Function(double progress)? onProgress,
  ) async {
    final response = await _send(release.downloadUrl);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw Exception('הורדת המילון נכשלה (${response.statusCode})');
    }
    // גודל ה-asset מה-API הוא החוזה היציב; כשאינו זמין נופלים ל-Content-Length.
    // בלי אימות זה גוף קטוע אך לא-ריק היה מותקן ומסומן כגרסה העדכנית.
    final expectedSize = release.sizeBytes ?? response.contentLength;

    final outFile = File('$dest.part');
    await outFile.parent.create(recursive: true);
    final sink = outFile.openWrite();
    final digestOutput = AccumulatorSink<Digest>();
    final digestInput = sha256.startChunkedConversion(digestOutput);
    var digestClosed = false;
    void closeDigest() {
      if (digestClosed) return;
      digestInput.close();
      digestClosed = true;
    }

    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(_stallTimeout)) {
        if (expectedSize != null && received + chunk.length > expectedSize) {
          throw Exception(
            'הורדת המילון חרגה מהגודל הצפוי ($expectedSize בייטים)',
          );
        }
        sink.add(chunk);
        digestInput.add(chunk);
        received += chunk.length;
        if (onProgress != null && expectedSize != null && expectedSize > 0) {
          onProgress(received / expectedSize);
        }
      }
      await sink.flush();
      await sink.close();
      closeDigest();
      if (expectedSize != null && received != expectedSize) {
        throw Exception(
          'הורדת המילון נקטעה: צפויים $expectedSize בייטים, התקבלו $received',
        );
      }
      final expectedSha256 = release.sha256;
      final downloadedSha256 = digestOutput.events.single.toString();
      if (expectedSha256 != null && downloadedSha256 != expectedSha256) {
        throw Exception('ה-sha256 של המילון שהורד אינו תואם ל-release');
      }

      final stagedMarker = File(_versionPath(_stagedPath(dest)));
      if (await stagedMarker.exists()) await stagedMarker.delete();
      await outFile.rename(_stagedPath(dest));
      await stagedMarker.writeAsString(release.sha256 ?? release.tag);
    } catch (_) {
      closeDigest();
      try {
        await sink.close();
      } catch (_) {}
      if (await outFile.exists()) await outFile.delete();
      rethrow;
    }
  }

  static String _stagedPath(String dest) => '$dest.next';

  Future<bool> _hasStagedVersion(
    String dest,
    String version,
    int? sizeBytes,
  ) async {
    try {
      final staged = File(_stagedPath(dest));
      final marker = File(_versionPath(staged.path));
      return await staged.exists() &&
          await marker.exists() &&
          (await marker.readAsString()).trim() == version &&
          (sizeBytes == null || await staged.length() == sizeBytes);
    } catch (_) {
      return false;
    }
  }

  /// מחליף את המילון בעותק הממתין וכותב את סימון הגרסה שלו. זורק כשההחלפה
  /// נכשלה — העותק נשאר במקומו לניסיון הבא.
  static Future<void> _installStaged(String dest) async {
    final staged = File(_stagedPath(dest));
    final stagedMarker = File(_versionPath(staged.path));
    if (!await staged.exists() || !await stagedMarker.exists()) return;
    final version = (await stagedMarker.readAsString()).trim();
    if (version.isEmpty) return;
    await replaceDownloadedFile(staged, dest);
    await writeVersionMarker(dest, version);
  }

  /// מתקין עותק ממתין לפני שהמנוע פותח את המילון, כשהקובץ עוד אינו נעול.
  /// זול (rename בלבד, בלי רשת); כשל נבלע והעותק נשאר לניסיון הבא.
  static Future<void> installStagedBeforeAttach(String dest) async {
    try {
      await _installStaged(dest);
    } catch (e) {
      debugPrint('⚠️ התקנת המילון הממתין נכשלה: $e');
    }
  }

  /// ה-sha256 של [path] בזרימה — בלי לטעון 57MB לזיכרון. `null` בכשל קריאה.
  static Future<String?> _fileSha256(String path) async {
    try {
      return (await sha256.bind(File(path).openRead()).first).toString();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _fileIsUsable(String path) async {
    try {
      final f = File(path);
      return await f.exists() && (await f.length()) > 0;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static Future<void> replaceDownloadedFile(File source, String dest) async {
    final destFile = File(dest);
    if (!Platform.isWindows) {
      await source.rename(dest);
      return;
    }

    final backupFile = File('$dest.bak');
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    final hadExistingDest = await destFile.exists();
    if (hadExistingDest) {
      try {
        await destFile.rename(backupFile.path);
      } on FileSystemException {
        // מנוע החיפוש מחזיק את הקובץ פתוח (Windows חוסם rename). אם התוכן
        // שהורד זהה לקיים — היעד כבר עדכני ודי במחיקת הזמני וכתיבת הסימון.
        if (await _filesIdentical(source, destFile)) {
          await source.delete();
          return;
        }
        rethrow;
      }
    }

    try {
      await source.rename(dest);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (_) {
      if (hadExistingDest &&
          !(await destFile.exists()) &&
          await backupFile.exists()) {
        await backupFile.rename(dest);
      }
      rethrow;
    }
  }

  static String _versionPath(String dest) => '$dest.version';

  /// מסמן מילון שהותקן בהצלחה ב-[dest] ומבטל עותק ממתין מהתקנה קודמת.
  /// best-effort: כשל בסימון אינו מכשיל את ההתקנה.
  static Future<void> writeVersionMarker(String dest, String tag) async {
    try {
      await File(_versionPath(dest)).writeAsString(tag);
    } catch (_) {}
    await _discardStaged(dest);
  }

  static Future<void> _discardStaged(String dest) async {
    try {
      // מבטלים את הסימון תחילה, כדי שכשל במחיקת הקובץ לא יאפשר התקנה שלו.
      for (final path in [_versionPath(_stagedPath(dest)), _stagedPath(dest)]) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}
  }

  /// כותב סימון מה-sha256 של מילון שהותקן ממקור מקומי, כמו מתקין FULL —
  /// כך מילון עדכני שיובא אינו מורד שוב.
  static Future<void> writeFileDigestMarker(String dest) async {
    final digest = await _fileSha256(dest);
    if (digest != null) await writeVersionMarker(dest, digest);
  }

  /// השוואת תוכן מלאה בקריאת chunks — בלי לטעון 57MB לזיכרון.
  static Future<bool> _filesIdentical(File a, File b) async {
    final length = await a.length();
    if (length != await b.length()) return false;
    final ra = await a.open();
    final rb = await b.open();
    try {
      const chunkSize = 1 << 20;
      var remaining = length;
      while (remaining > 0) {
        final want = remaining < chunkSize ? remaining : chunkSize;
        final ca = await ra.read(want);
        final cb = await rb.read(want);
        if (ca.isEmpty || ca.length != cb.length) return false;
        for (var i = 0; i < ca.length; i++) {
          if (ca[i] != cb[i]) return false;
        }
        remaining -= ca.length;
      }
      return true;
    } finally {
      await ra.close();
      await rb.close();
    }
  }

  /// GET עם מעקב ידני אחרי redirects (נכסי GitHub Releases מפנים ל-CDN).
  Future<http.StreamedResponse> _send(Uri uri, {Map<String, String>? headers}) {
    return sendGetFollowingRedirects(
      _client,
      uri,
      headers: {'User-Agent': 'otzaria-search', ...?headers},
      maxRedirects: _maxRedirects,
      stallTimeout: _stallTimeout,
    );
  }
}
