import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/utils/http_redirect_download.dart';

/// מידע על ה-release האחרון של מילון המורפולוגיה (`lexical.db`).
class MagicDictionaryRelease {
  /// תג ה-release (למשל `v0.3.0`) — משמש לזיהוי גרסה מותקנת.
  final String tag;

  /// כתובת ההורדה הישירה של נכס ה-`lexical.db`.
  final Uri downloadUrl;

  /// גודל הנכס בבייטים, אם דווח ב-API (לחישוב התקדמות). `null` אם לא ידוע.
  final int? sizeBytes;

  const MagicDictionaryRelease({
    required this.tag,
    required this.downloadUrl,
    this.sizeBytes,
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

  /// מזהים את נכס המילון לפי סיומת ה-URL.
  static const String _assetSuffix = '/lexical.db';

  static const int _maxRedirects = 5;

  final http.Client _client;
  final bool _ownsClient;
  final Future<String> Function() _destinationProvider;

  /// משך מרבי ללא התקדמות לפני קטיעה ([TimeoutException]). מתאפס עם כל בייט,
  /// כך שהורדה איטית של קובץ גדול (~57MB) נמשכת כל עוד יש זרימה.
  final Duration _stallTimeout;

  MagicDictionaryDownloader({
    http.Client? client,
    Future<String> Function()? destinationProvider,
    this._stallTimeout = const Duration(seconds: 60),
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
      final upToDate =
          !force &&
          await _fileIsUsable(dest) &&
          (await installedVersion()) == release.tag;
      if (upToDate) {
        onProgress?.call(1.0);
        return true;
      }
      await _download(release, dest, onProgress);
      await _writeVersion(dest, release.tag);
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
      headers: {
        'Accept': 'application/vnd.github+json',
      },
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
    for (final a in assets) {
      final url =
          (a as Map<String, dynamic>)['browser_download_url'] as String?;
      if (url != null && url.endsWith(_assetSuffix)) {
        asset = a;
        break;
      }
    }
    if (tag == null || tag.isEmpty || asset == null) {
      throw Exception('לא נמצא נכס lexical.db ב-release האחרון');
    }
    return MagicDictionaryRelease(
      tag: tag,
      downloadUrl: Uri.parse(asset['browser_download_url'] as String),
      sizeBytes: (asset['size'] as num?)?.toInt(),
    );
  }

  /// הגרסה המותקנת כעת (תג ה-release), או `null` אם אין מילון/סימון גרסה.
  Future<String?> installedVersion() async {
    final dest = await _destinationProvider();
    final marker = File(_versionPath(dest));
    if (!await marker.exists()) return null;
    final tag = (await marker.readAsString()).trim();
    return tag.isEmpty ? null : tag;
  }

  // ── פנימי ──────────────────────────────────────────────────────────────

  /// מוריד את הנכס אל קובץ `.part` זמני ואז משנה שם אטומית ליעד — כדי שלא
  /// יישאר קובץ חלקי שייראה תקין אם ההורדה נקטעה.
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
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(_stallTimeout)) {
        if (expectedSize != null && received + chunk.length > expectedSize) {
          throw Exception(
            'הורדת המילון חרגה מהגודל הצפוי ($expectedSize בייטים)',
          );
        }
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && expectedSize != null && expectedSize > 0) {
          onProgress(received / expectedSize);
        }
      }
      await sink.flush();
      await sink.close();
      if (expectedSize != null && received != expectedSize) {
        throw Exception(
          'הורדת המילון נקטעה: צפויים $expectedSize בייטים, התקבלו $received',
        );
      }

      await _replaceDownloadedFile(outFile, dest);
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      if (await outFile.exists()) await outFile.delete();
      rethrow;
    }
    onProgress?.call(1.0);
  }

  Future<bool> _fileIsUsable(String path) async {
    try {
      final f = File(path);
      return await f.exists() && (await f.length()) > 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _replaceDownloadedFile(File source, String dest) async {
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
      await destFile.rename(backupFile.path);
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

  String _versionPath(String dest) => '$dest.version';

  Future<void> _writeVersion(String dest, String tag) async {
    try {
      await File(_versionPath(dest)).writeAsString(tag);
    } catch (_) {
      // סימון גרסה הוא נחמד-שיהיה; כישלון בו לא אמור להפיל את ההורדה.
    }
  }

  /// GET עם מעקב ידני אחרי redirects (נכסי GitHub Releases מפנים ל-CDN).
  Future<http.StreamedResponse> _send(
    Uri uri, {
    Map<String, String>? headers,
  }) {
    return sendGetFollowingRedirects(
      _client,
      uri,
      headers: {'User-Agent': 'otzaria-search', ...?headers},
      maxRedirects: _maxRedirects,
      stallTimeout: _stallTimeout,
    );
  }
}
