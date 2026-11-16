import 'package:otzaria/core/download_http_client.dart';
import 'package:otzaria/core/download_network_policy.dart';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/utils/http_redirect_download.dart';
import 'package:path/path.dart' as p;

/// The latest release of the biographies bundle.
class BiographiesRelease {
  /// Release tag (for example `v0.3.0`), stored to tell the installed version.
  final String tag;

  /// Direct download URL of the `biographies-app.json.gz` asset.
  final Uri downloadUrl;

  const BiographiesRelease({required this.tag, required this.downloadUrl});
}

/// Downloads the "Toldot Gedolei Yisrael" bundle (`biographies-app.json.gz`)
/// from the GitHub releases of `Otzaria/toldot-gedolei-yisrael` to the data
/// root, only when there is a new release; the same pattern as the morphology
/// dictionary (`lexical.db`).
///
/// כל הפעולות best-effort: בכשל רשת האזור ממשיך לעבוד עם הקובץ הקיים,
/// ובהיעדרו מוצגת הודעת "אין נתונים".
class BiographiesDownloader {
  /// נקודת ה-API של ה-release האחרון.
  static const String latestReleaseApi =
      'https://api.github.com/repos/Otzaria/toldot-gedolei-yisrael/releases/latest';

  static const String _assetSuffix = '/biographies-app.json.gz';

  /// The Ta Shma file of earlier versions, removed once the new one is in.
  static const String _legacyFileName = 'biographies.tsb';

  static const Duration _apiTimeout = Duration(seconds: 15);

  final http.Client _client;
  final bool _ownsClient;
  bool _disposed = false;
  final Future<String> Function() _destinationProvider;

  BiographiesDownloader({
    http.Client? client,
    Future<String> Function()? destinationProvider,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _destinationProvider =
           destinationProvider ?? AppPaths.getBiographiesPath;

  void dispose() {
    _disposed = true;
    if (_ownsClient) _client.close();
  }

  /// מוודא שהגרסה האחרונה מותקנת: מוריד רק אם חסר קובץ מקומי או שהתג
  /// השמור שונה מהתג של ה-release האחרון.
  ///
  /// מחזיר `true` אם בסוף הפעולה קיים קובץ מקומי (כולל קובץ ישן כשאין
  /// רשת). לעולם אינו זורק.
  Future<bool> ensureLatest({
    bool force = false,
    void Function()? checkCancelled,
    void Function()? onWaitingForWifi,
  }) async {
    final dest = await _destinationProvider();
    try {
      final release = await fetchLatestRelease();
      final installed = await installedTag();
      final hasFile = await File(dest).exists();
      if (!force && hasFile && installed == release.tag) return true;
      await DownloadNetworkPolicy.instance.runResumable(
        () => _download(release, dest),
        checkCancelled: () {
          if (_disposed) throw http.RequestAbortedException();
          checkCancelled?.call();
        },
        onWaiting: onWaitingForWifi,
      );
      await File(_versionPath(dest)).writeAsString(release.tag);
      await _deleteLegacyFile(dest);
      return true;
    } catch (_) {
      return File(dest).exists();
    }
  }

  /// שולף את פרטי ה-release האחרון. זורק [Exception] בכשל.
  Future<BiographiesRelease> fetchLatestRelease() async {
    final response = await _client
        .get(
          Uri.parse(latestReleaseApi),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(_apiTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('GitHub API החזיר ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String?)?.trim();
    final assets = (json['assets'] as List?) ?? const [];
    String? url;
    for (final a in assets) {
      final candidate =
          (a as Map<String, dynamic>)['browser_download_url'] as String?;
      if (candidate != null && candidate.endsWith(_assetSuffix)) {
        url = candidate;
        break;
      }
    }
    if (tag == null || tag.isEmpty || url == null) {
      throw Exception('לא נמצא נכס biographies-app.json.gz ב-release האחרון');
    }
    return BiographiesRelease(tag: tag, downloadUrl: Uri.parse(url));
  }

  /// התג המותקן כעת, או `null` אם אין.
  Future<String?> installedTag() async {
    final marker = File(_versionPath(await _destinationProvider()));
    if (!await marker.exists()) return null;
    final tag = (await marker.readAsString()).trim();
    return tag.isEmpty ? null : tag;
  }

  /// מוריד אל קובץ `.part` ומשנה שם אטומית, כדי שקובץ חלקי לא ייראה תקין.
  Future<void> _download(BiographiesRelease release, String dest) async {
    final response = await sendGetFollowingRedirects(
      createDownloadClient(_client),
      release.downloadUrl,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.listen((_) {}).cancel();
      throw Exception('הורדת הביוגרפיות נכשלה (${response.statusCode})');
    }
    final outFile = File('$dest.part');
    await outFile.parent.create(recursive: true);
    final sink = outFile.openWrite();
    try {
      await sink.addStream(response.stream);
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      if (await outFile.exists()) await outFile.delete();
      rethrow;
    }
    await outFile.rename(dest);
  }

  static String _versionPath(String dest) => '$dest.version';

  static Future<void> _deleteLegacyFile(String dest) async {
    final legacy = p.join(p.dirname(dest), _legacyFileName);
    for (final path in [legacy, _versionPath(legacy)]) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
