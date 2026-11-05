import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/plugins/services/plugin_store_link_parser.dart';
import 'package:otzaria/plugins/utils/plugin_version_utils.dart';
import 'package:path/path.dart' as p;

class PluginDownloadService {
  final http.Client _client;
  final bool _ownsClient;
  final _downloads = <Completer<void>>{};
  late final FutureOr<void> Function() _closer = dispose;
  bool _disposed = false;

  /// משך מרבי ללא בייטים (גם בהמתנה לכותרות) לפני [TimeoutException].
  final Duration _stallTimeout;

  /// [client] מוזרק נשאר באחריות הקורא ואינו נסגר עם השירות.
  PluginDownloadService({
    http.Client? client,
    this._stallTimeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (_ownsClient) HttpClientRegistry.register(_closer);
  }

  /// מבטל הורדות פעילות ומשחרר רק את ה-client שבבעלות השירות.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsClient) HttpClientRegistry.unregister(_closer);
    for (final download in _downloads) {
      if (!download.isCompleted) download.complete();
    }
    if (_ownsClient) _client.close();
  }

  /// מורידה את ארכיון התוסף. [appVersion] — גרסת האוצריא הנוכחית; כשהכתובת
  /// היא של החנות היא נשלחת אליה כדי לקבל גרסת תוסף תואמת (ראו
  /// [PluginStoreLinkParser.appendAppVersion]).
  /// [storeOnly] — לאכוף שכל hop הוא מארח של החנות. נדרש כשההתקנה יזומה
  /// ע"י תוסף (`plugin.requestInstall`); בקישור שהמשתמש לחץ עליו במודע
  /// הגבלה כזו הייתה שוברת התקנה לגיטימית מכתובת אחרת.
  Future<String> downloadPluginArchive(
    Uri downloadUri, {
    String? appVersion,
    bool storeOnly = false,
  }) async {
    if (_disposed) throw StateError('PluginDownloadService is disposed');
    final abort = Completer<void>();
    _downloads.add(abort);
    http.StreamedResponse? response;
    var responseConsumed = false;
    try {
      final resolvedUri = PluginStoreLinkParser.appendAppVersion(
        downloadUri,
        appVersion,
      );
      response = await _sendFollowingRedirects(resolvedUri, storeOnly, abort);
      _checkActive(abort, downloadUri);

      if (response.statusCode >= 400 && resolvedUri != downloadUri) {
        responseConsumed = true;
        final body = await utf8.decodeStream(
          response.stream.timeout(_stallTimeout),
        );
        _checkActive(abort, downloadUri);
        final incompatible = PluginStoreIncompatibleException.tryParse(body);
        if (incompatible != null) throw incompatible;

        // סירוב שאינו אי-תאימות — מנסים את הכתובת המקורית ללא appVersion.
        response = await _sendFollowingRedirects(downloadUri, storeOnly, abort);
        responseConsumed = false;
        _checkActive(abort, downloadUri);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('שגיאה בהורדת התוסף (${response.statusCode})');
      }

      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria_plugin_download_',
      );
      final archivePath = p.join(
        tempDir.path,
        '${_resolveFileStem(downloadUri)}.otzplugin',
      );
      IOSink? sink;
      try {
        _checkActive(abort, downloadUri);
        sink = File(archivePath).openWrite();
        responseConsumed = true;
        await sink.addStream(response.stream.timeout(_stallTimeout));
        await sink.flush();
        await sink.close();
        sink = null;
        _checkActive(abort, downloadUri);
      } catch (_) {
        try {
          await sink?.close();
        } catch (_) {}
        await _cleanupDirectory(tempDir);
        rethrow;
      }

      return archivePath;
    } catch (error) {
      if (abort.isCompleted &&
          (error is http.ClientException || error is SocketException)) {
        throw http.RequestAbortedException(downloadUri);
      }
      rethrow;
    } finally {
      if (!abort.isCompleted) abort.complete();
      _downloads.remove(abort);
      if (response != null && !responseConsumed) {
        await response.stream.listen(null).cancel();
      }
    }
  }

  void _checkActive(Completer<void> abort, Uri uri) {
    if (abort.isCompleted) throw http.RequestAbortedException(uri);
  }

  Future<void> cleanupDownloadedArchive(String archivePath) async {
    final parent = Directory(p.dirname(archivePath));
    if (await parent.exists()) {
      await _cleanupDirectory(parent);
      return;
    }

    final archiveFile = File(archivePath);
    if (await archiveFile.exists()) {
      await archiveFile.delete();
    }
  }

  Future<void> _cleanupDirectory(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  /// תקרת ההפניות. חמש מספיקות לכל שרשרת סבירה של החנות.
  static const int _maxRedirects = 5;

  /// שולחת GET ועוקבת אחרי הפניות **ידנית**. מעקב אוטומטי היה מאפשר
  /// ל-redirect מהחנות להוציא את ההורדה לשרת זר, ובכך לרוקן את הגידור
  /// שנעשה בנקודת הקריאה.
  Future<http.StreamedResponse> _sendFollowingRedirects(
    Uri uri,
    bool storeOnly,
    Completer<void> abort,
  ) async {
    var current = uri;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      _checkActive(abort, current);
      if (storeOnly && !PluginStoreLinkParser.isStoreDownloadUri(current)) {
        throw Exception('הורדת תוסף מותרת רק מכתובת של חנות התוספים');
      }
      final request = http.AbortableRequest(
        'GET',
        current,
        abortTrigger: abort.future,
      )..followRedirects = false;
      final response = await _client
          .send(request)
          .then((response) async {
            if (abort.isCompleted) {
              await response.stream.listen(null).cancel();
              throw http.RequestAbortedException(request.url);
            }
            return response;
          })
          .timeout(_stallTimeout);
      final location = response.headers['location'];
      final isRedirect =
          response.statusCode >= 300 &&
          response.statusCode < 400 &&
          location != null;
      if (!isRedirect) return response;
      await response.stream.timeout(_stallTimeout).drain<void>();
      current = current.resolve(location);
    }
    throw Exception('יותר מדי הפניות בהורדת התוסף');
  }

  String _resolveFileStem(Uri uri) {
    final lastSegment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final sanitized = lastSegment
        .replaceAll('.otzplugin', '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .trim();

    if (sanitized.isEmpty) {
      return 'plugin';
    }

    return sanitized;
  }
}

/// לחנות אין גרסה של התוסף שתואמת לגרסת האוצריא המותקנת. נבנית מגוף תשובת
/// ה-404 של החנות, שכולל את פרטי התאימות — כך שאין צורך להוריד ארכיון כדי
/// לדעת מה להציג למשתמש.
class PluginStoreIncompatibleException implements Exception {
  final String appVersion;
  final String latestVersion;

  /// גרסת האוצריא המינימלית שהגרסה האחרונה של התוסף דורשת ('' = ללא רצפה).
  final String minAppVersion;

  /// הגרסה המינימלית להרצת גרסה *כלשהי* של התוסף — נמוכה מ-[minAppVersion]
  /// כשגרסאות ישנות יותר עוד תמכו באוצריא ישנה. null כשהחנות לא שלחה אותה.
  final String? minSupportedAppVersion;

  /// גרסת האוצריא המקסימלית שהיא תומכת בה (null = ללא תקרה).
  final String? maxAppVersion;

  const PluginStoreIncompatibleException({
    required this.appVersion,
    required this.latestVersion,
    required this.minAppVersion,
    this.minSupportedAppVersion,
    this.maxAppVersion,
  });

  /// האם הכשל נובע מכך שהאוצריא *חדשה* מדי לתוסף (ולא ישנה מדי).
  bool get isAboveCeiling {
    final ceiling = maxAppVersion;
    if (ceiling == null || ceiling.isEmpty) return false;
    try {
      return PluginVersionUtils.compareCoreVersions(appVersion, ceiling) > 0;
    } on PluginVersionFormatException {
      return false;
    }
  }

  static PluginStoreIncompatibleException? tryParse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final appVersion = decoded['appVersion'];
      final latestVersion = decoded['latestVersion'];
      if (appVersion is! String || appVersion.isEmpty) return null;
      if (latestVersion is! String || latestVersion.isEmpty) return null;
      final rawMax = decoded['maxAppVersion'];
      final maxAppVersion = rawMax is String && rawMax.isNotEmpty
          ? rawMax
          : null;
      final rawMin = decoded['compatibleWith'];
      final minAppVersion = rawMin is String ? rawMin : '';
      // בלי אף גבול אין מה להציג למשתמש — עדיף המסלול הרגיל של הורדה ובדיקה.
      if (minAppVersion.isEmpty && maxAppVersion == null) return null;

      final rawMinSupported = decoded['minSupportedAppVersion'];
      final minSupported =
          rawMinSupported is String && rawMinSupported.isNotEmpty
          ? rawMinSupported
          : null;

      return PluginStoreIncompatibleException(
        appVersion: appVersion,
        latestVersion: latestVersion,
        minAppVersion: minAppVersion,
        // זהה לדרישת הגרסה האחרונה — אין מה להוסיף למשתמש.
        minSupportedAppVersion: minSupported == minAppVersion
            ? null
            : minSupported,
        maxAppVersion: maxAppVersion,
      );
    } on FormatException {
      return null;
    }
  }
}
